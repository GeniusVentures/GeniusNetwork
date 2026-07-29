# Project Research Summary

**Project:** sgproc-render (SGProcessingManager RenderProcessor)
**Domain:** Hand-rolled headless Vulkan render-pass execution inside a distributed batch-processing node, scoped to GeniusVentures/SGProcessingManager#7
**Researched:** 2026-07-29
**Confidence:** HIGH

## Executive Summary

This is a full restart of a prior bgfx-based attempt: instead of adding a cross-platform rendering-abstraction engine, the node gets its own small, hand-rolled, headless Vulkan render path -- own VkInstance/VkPhysicalDevice/VkDevice, no swapchain, no WSI surface extensions, ever. All four research passes converge on the same shape: reuse the already-vendored Vulkan-Headers/Vulkan-Loader/MoltenVK and the existing Vulkan::Vulkan CMake target; add exactly one new net-new capability class (a GLSL-to-SPIR-V compiler toolchain, since none is vendored today); skip VMA (allocation count for a single render job is tiny -- a ~100-line RAII wrapper is simpler to audit); skip Vulkan-ValidationLayers for v1 (defer, don't block); and integrate through ProcessingManager's existing ProcessingProcessor interface and output/hash path completely unmodified. The engineering shape is well-understood -- this is Vulkan mechanics against canonical, cross-checked references, not a novel product-feature landscape.

The two biggest correctness risks are not "can we write a Vulkan render pass" (well-trodden) but (1) whether a second, independently-created VkInstance/VkDevice in the same process as MNN's own internal Vulkan usage needs explicit synchronization at creation time, and (2) making same-node repeat-run bit-exact-hash determinism actually hold, which requires deliberate guards (explicit clears, no MSAA, fixed shader precision, no unordered parallel reduction, a pinned pipeline-cache policy) that are easy to skip in a first working demo and only surface as flaky hash mismatches later. A third, sharper risk is security-adjacent: the schema already accepts shader_config.type: "spirv" today, meaning a job can hand raw SPIR-V straight to vkCreateShaderModule, bypassing GLSL compilation and its error-reporting entirely -- unvalidated SPIR-V is a documented driver-crash vector, making an spirv-val gate mandatory, not a nice-to-have.

Two specific technical decisions surfaced disagreement across the four research files and are called out explicitly below rather than silently resolved: (1) whether MNN's own Vulkan-instance-creation mutex implies concurrent Vulkan-instance/device creation genuinely needs a shared lock, and (2) shaderc vs. bare glslang for the GLSL-to-SPIR-V toolchain. Both are flagged as roadmap-level decisions to carry forward into phase planning, not settled facts.

## Key Findings

### Recommended Stack

Confirmed via direct repo inspection: none of vk-bootstrap, VMA, glslang (standalone), or shaderc exist anywhere in thirdparty/ today (the only glslang hit is MoltenVK's private, Xcode-built internal copy -- not consumable). The only genuinely new additions needed are a bootstrap helper and a GLSL-to-SPIR-V compiler.

**Core technologies:**
- **Vulkan-Headers / Vulkan-Loader / MoltenVK** (already vendored, ~v1.3.302-line + MoltenVK ~v1.2.8) -- reuse the existing Vulkan::Vulkan CMake target already linked in SGProcessingManager/src/processors/CMakeLists.txt; do not add a second loader/headers copy.
- **vk-bootstrap** (MIT, any recent v1.3.x-line tag) -- automates instance/device/queue bootstrap boilerplate, in particular the VK_KHR_portability_subset/MoltenVK dance that's easy to silently get wrong on macOS only. Hands back raw native handles; does not replace the Vulkan API surface, so it does not reopen the "no new GPU backend" concern that killed bgfx.
- **A GLSL-to-SPIR-V compiler (shaderc vs. glslang -- see Decision Flags below)** -- net-new vendoring, needed as an in-process, linkable library (not a build-time-only CLI step) because shader source arrives as runtime-fetched job bytes, not a build artifact.
- **Hand-rolled RAII memory allocator (~100-150 lines)** instead of VMA -- a render job needs only 4-6 fixed VkDeviceMemory allocations (color/depth attachments, vertex/index buffers, readback staging buffer), well under any practical allocation-count limit; VMA's sub-allocation/defragmentation value doesn't apply at this scope.

**Explicitly not added for v1:** VMA, any WSI/swapchain extension, Vulkan-ValidationLayers (deferred, not blocking), OpenGL/SwiftShader/any CPU fallback tier (explicitly prohibited by the issue).

### Expected Features

This is an engineering-capability landscape, not a consumer feature landscape -- "table stakes" means "required for issue #7 to be satisfied at all."

**Must have (table stakes):**
- Independent headless VkInstance/VkPhysicalDevice/VkDevice creation, no swapchain/WSI extensions
- Offscreen framebuffer (color + depth attachment), VkRenderPass/VkFramebuffer
- Vertex + index buffer upload (host-visible+coherent directly is fine -- no staging-buffer optimization needed for a submit-once job)
- Multi-stage (vertex+fragment) shader pipeline built from schema-declared config
- GLSL -> SPIR-V compilation at job-load time (rejects malformed shaders before any GPU call)
- Uniform/parameter binding reusing the existing shader_config.uniforms schema block
- Single draw call + fence-gated submit/wait (no frames-in-flight, no semaphore-chained presentation)
- Image->buffer readback via vkCmdCopyImageToBuffer into host-visible memory
- Determinism guards: explicit LOAD_OP_CLEAR everywhere (never DONT_CARE on hashed regions), VK_SAMPLE_COUNT_1_BIT always, explicit shader precision qualifiers
- Pre-existing crash-bug fix: ParseBlockSize()'s unconditional pass.get_model().value() must be type-guarded before any render pass can reach Process()
- PassType-keyed dispatch added to ProcessingManager::Process() (a new, separate map -- colliding with the existing DataType-keyed map is a confirmed exact bug: static_cast<int>(PassType::RENDER) == static_cast<int>(DataType::INT) == 3)
- CheckProcessValidity() parity fix for render passes (currently a no-op case PassType::RENDER: break;)
- Schema extension: render_target (dimensions/formats/clear values), vertex/index buffer bindings + layout, multi-stage shader array, pipeline state enums (topology/cull/winding/depth-test)

**Should have (v1.x, not launch-blocking):**
- Push constants as an alternative to descriptor-set uniforms for the common small-MVP-matrix case
- Vulkan validation layers wired into debug/CI builds
- Structured VkResult -> ProcessingManager::Error mapping with clear per-failure-point messages

**Defer (v2+):**
- Multi-pass/post-processing GPU chains, MRT, texture sampling from external input, instancing, compute-render interop, alpha blending, cross-node/cross-vendor tolerance-based verification -- all explicitly out of scope and would silently reintroduce complexity or determinism risk the milestone deliberately avoids.

### Architecture Approach

RenderProcessor is added as a sibling file next to the existing 17-class MNN processor family, implementing the same ProcessingProcessor base interface (StartProcessing(chunkhashes, proc, imageData, modelFile, parameters) -> ProcessingResult) with buffer-slot reinterpretation (shader bytes in the "model" slot, vertex/index bytes in the "image" slot) -- no new sibling class hierarchy, no new CMake target, no changes to the existing output-save/hash path (FileManager::SaveASync, IPFS dual-save) at all. Dispatch requires a new, separate PassType-keyed factory map in ProcessingManager (not reuse of the existing DataType-keyed map -- confirmed enum collision, see above), hooked in immediately after the existing index = GetInputIndex(...) call, reusing the already-implicit (and already load-bearing at cpp:840) convention that passes[i] and inputs[i] are positionally paired.

**Major components:**
1. ProcessingManager -- parses/validates passes, dispatches to a processor via PassType (new) or DataType (existing), forwards output to FileManager unchanged
2. RenderProcessor (new) -- owns its own headless Vulkan instance/device/queue; builds pipeline from schema; executes one offscreen render pass; reads back color attachment
3. GLSL-to-SPIR-V compiler integration -- runtime, in-process compilation of job-fetched shader bytes (not a build-time-only step), gated by spirv-val before vkCreateShaderModule
4. Existing Vulkan::Vulkan CMake target / vendored Vulkan-Headers+Loader+MoltenVK -- shared substrate for both MNN's internal Vulkan usage and the new RenderProcessor, never a second loader

Headless/offscreen rendering is confirmed platform-agnostic in the way that matters here: no VkSurfaceKHR, no swapchain, ever, on any platform (Windows/Linux/macOS via MoltenVK) -- the entire class of WGL/EGL/GLX-style windowing concern that applied to the prior bgfx design does not carry over, since Vulkan's WSI layer is additive/optional rather than baked into context creation the way OpenGL's is.

### Critical Pitfalls

1. **Reintroducing "independent = isolated" thinking around Vulkan init** -- MNN already guards its own Vulkan instance/device creation with a function-local-static mutex (mnn_vulkan_mutex) that doesn't protect a new RenderProcessor's init path (or MNN's own other two Vulkan call sites) against it. Avoid by introducing one process-wide, header-declared init-time lock shared by all Vulkan-instance/device-creation call sites in the process (see Decision Flag below -- this is the resolution of the ARCHITECTURE/PITFALLS tension).
2. **Reflexively reaching for VK_KHR_surface/swapchain/VK_EXT_headless_surface** -- none of this is needed or wanted; render to a plain VkImage and read back via vkCmdCopyImageToBuffer. MoltenVK's WSI-adjacent code paths have historically been the weakest part of the implementation -- never touch them.
3. **Assuming same-node/same-hardware repeat runs are automatically bit-exact** -- uninitialized memory (LOAD_OP_DONT_CARE), unordered parallel-reduction shader math, and driver pipeline-cache cold/warm variance are all real, independent non-determinism sources even with cross-vendor tolerance out of scope. Guard with explicit clears everywhere, no unordered accumulation, and a pinned pipeline-cache policy. Verify with an N>=10 repeat-run identical-hash test, not "ran it twice."
4. **Unvalidated job-supplied shader/SPIR-V reaching vkCreateShaderModule** -- the schema already accepts shader_config.type: "spirv" directly today, bypassing GLSL/glslang entirely; invalid SPIR-V is a documented driver-crash vector in multiple ICDs. spirv-val must be a mandatory gate on all SPIR-V (compiled or job-supplied) before vkCreateShaderModule, and the render PassType's acceptance/rejection of "spirv" must be an explicit validation decision, not an assumption.
5. **Reintroducing the exact .value()-on-unchecked-boost::optional crash shape** for new render-specific schema fields -- the same bug class that produced the original ParseBlockSize() crash. Any generic Pass&-operating code must type-guard on pass.get_type() == PassType::RENDER before dereferencing render-specific optionals.

## Decision Flags for the Roadmap (not fully resolved -- carry forward explicitly)

### 1. Does concurrent Vulkan instance/device creation with MNN need explicit synchronization?

ARCHITECTURE.md and PITFALLS.md reach different-sounding conclusions on this exact point:

- **ARCHITECTURE.md's verdict:** No explicit synchronization is needed. Reasoning: Vulkan has no instance-spanning global state by design (device-scoped object privacy per spec); MNN's Vulkan types are not exposed through any public header SGProcessingManager consumes, so there's no handle-sharing path; the Vulkan Loader's own global bookkeeping (ICD enumeration, dispatch table construction) is documented as internally mutex-guarded and thread-safe; and today's pipeline has no code path where MNN's and a render pass's Vulkan init would even run concurrently (everything is synchronous, one pass per Process() call).
- **PITFALLS.md's finding:** MNN's own codebase already carries a dedicated, function-local-static mnn_vulkan_mutex in processing_processor_mnn_image.cpp:114-115, specifically guarding vkCreateInstance/createSession(MNN_FORWARD_VULKAN) calls, with an explicit code comment framing it as a stopgap "until MNN exposes a shareable runtime/session API" -- implying MNN's own authors determined, at some point, that concurrent Vulkan instance/device creation was NOT safe without a lock, at least defensively. Critically, PITFALLS.md also notes this mutex is scoped to one file only -- MNN's own _string.cpp/_volume.cpp Vulkan call sites are not covered by it either, so even MNN-vs-MNN concurrent init is only partially guarded today.

**Reconciled recommendation:** Treat MNN's existing mutex as the stronger evidence here, not general spec/loader-thread-safety reasoning. A prior engineering decision made by people looking directly at real driver behavior outweighs a theoretical "the spec doesn't require it" argument, especially given the cost of sharing one lock is negligible and the downside of a race (intermittent VK_ERROR_INITIALIZATION_FAILED/VK_ERROR_DEVICE_LOST, driver-dependent, hard to reproduce) is expensive to debug post-ship. Concretely: introduce one process-wide, header-declared synchronization primitive (e.g. a VulkanInitGuard singleton) acquired by MNN's three existing Vulkan call sites and RenderProcessor's instance/device creation path, before any vkCreateInstance/vkCreateDevice/vkEnumeratePhysicalDevices call -- migrating the existing mnn_vulkan_mutex to use it rather than leaving two (or four) uncoordinated locks. Steady-state work (vkQueueSubmit on already-created devices, using separate queues) does not need this lock -- only the init/create phase does.

**This is not fully closed** -- the roadmap/planning phase should verify via a concurrent-init stress test (construct the render context and trigger MNN Vulkan inference concurrently from multiple threads, repeated enough times to catch a race) rather than trusting either research file's reasoning alone. Flag as an early-architecture decision, not an implementation-detail afterthought.

### 2. shaderc vs. bare glslang for GLSL-to-SPIR-V compilation

- **STACK.md recommends shaderc** -- its purpose-built shaderc::Compiler::CompileGlslToSpv API returns a structured .GetCompilationStatus()/.GetErrorMessage() result, exactly the shape needed to cleanly reject malformed job-supplied shaders rather than crash or trust attacker-controlled bytes. shaderc transitively bundles glslang (parsing/codegen) + SPIRV-Tools (validation/optimization) behind one coherent dependency -- so choosing shaderc gets spirv-val-capable validation "for free" as the same dependency, rather than needing a separate SPIRV-Tools vendoring decision.
- **FEATURES.md leans toward bare glslang** -- reasoning that glslang's own TShader/TProgram C++ API is sufficient to compile GLSL->SPIR-V in-process with no extra dependency, and that shaderc is "strictly more to vendor for no functional gain in this narrow use case."
- **ARCHITECTURE.md is open to either**, but notes shaderc is "the more common choice specifically because callers want compile-this-string-to-SPIR-V-bytes-right-now rather than driving glslang's own multi-step API," and separately, independently, PITFALLS.md establishes that spirv-val (part of SPIRV-Tools) is mandatory, not optional, given the schema's existing "spirv" direct-input path.

**Reconciled recommendation:** Go with **shaderc**. The deciding factor is that spirv-val/SPIRV-Tools validation is already a hard requirement independent of this shader-toolchain question (see Pitfall 4 / the "spirv" schema finding below) -- so a bare-glslang choice doesn't actually avoid vendoring SPIRV-Tools, it just splits it into a second, separately-integrated dependency instead of getting it "for free" as part of one coherent shaderc dependency. glslang's lower-level API (manual TBuiltInResource limits struct, no built-in structured error/warning string) is also more ceremony-heavy and more error-prone to get right for a validation path that must gracefully reject hostile/malformed job-supplied shader text -- a meaningful correctness concern given this is untrusted job-supplied input on a distributed compute node, not a first-party build-time asset pipeline. shaderc's license (Apache-2.0) and its glslang/SPIRV-Tools dependencies (BSD-style Khronos license / Apache-2.0) are fully permissive-compatible.

**This is a phase-level decision, not fully closed** -- if the team weighs "one Khronos-lineage dependency, hand-roll the TBuiltInResource/error-plumbing ourselves" more heavily than "smaller integration surface, more code to vendor," bare glslang + a separately-vendored SPIRV-Tools is a legitimate alternative. The roadmap should surface this explicitly during the schema-extension/RenderProcessor-implementation phase rather than let either research file's preference silently win by default.

### 3. shader_config.type: "spirv" is already a valid, load-bearing schema value today

Confirmed directly (PITFALLS.md, cross-referenced against generated/ShaderType.hpp and gnus-processing-schema.json): the schema's shader_config.type enum already accepts "glsl" | "hlsl" | "metal" | "spirv" today, with "spirv" letting a job hand raw SPIR-V bytes straight toward vkCreateShaderModule, bypassing GLSL/glslang (and thus bypassing whichever GLSL-level compile-error-reporting mechanism is chosen per Decision Flag #2) entirely. This is not a hypothetical edge case to design around later -- it makes an spirv-val validation gate mandatory, not optional, on all SPIR-V reaching vkCreateShaderModule, whether the SPIR-V was compiled in-process from job-supplied GLSL or supplied directly. The CheckProcessValidity() schema-validation work for the render PassType must make an explicit accept/reject decision for "spirv" direct input this milestone -- if accepted, spirv-val is required for that path specifically; if rejected, that must be a one-line explicit validation rule, not an assumption based on "we only document GLSL usage." Invalid-but-syntactically-parseable SPIR-V that skips spirv-val is documented to crash drivers (reported segfaults in RADV and others) rather than return a clean VkResult, and Vulkan validation layers do not reliably catch every such case -- so "validation layers were clean" is not sufficient proof of safety.

## Implications for Roadmap

Based on combined research, suggested phase structure:

### Phase 1: Vulkan Context Setup & Coexistence
**Rationale:** Foundational -- every other phase depends on a correctly-initialized, coexistence-safe headless Vulkan context existing first. This is also where the two most expensive-to-retrofit decisions (init synchronization, device-selection policy) must be made, since they're architectural, not bolted on later.
**Delivers:** Independent headless VkInstance/VkPhysicalDevice/VkDevice/VkQueue creation (no WSI/swapchain extensions anywhere); a process-wide, header-declared init-time synchronization primitive shared with MNN's existing Vulkan call sites (resolves Decision Flag #1); an explicit, deterministic device-selection scoring function (not "index 0"); a written decision on Vulkan-ValidationLayers vendoring (deferred vs. debug-only).
**Addresses:** Table-stakes "independent VkInstance/VkDevice, headless" and "coexistence with MNN's Vulkan usage" from FEATURES.md.
**Avoids:** Pitfalls 1, 2, 3 (init race, inconsistent device selection, missing validation/env-var surprises).
**Research flag:** Needs deeper research/spike during planning -- the concurrent-init stress test and the exact shape of the shared lock/singleton are non-trivial and worth validating against MNN's real behavior before committing to an approach.

### Phase 2: Schema Extension & Shader/SPIR-V Validation Pipeline
**Rationale:** Can be developed and tested in isolation (GLSL/SPIR-V bytes in, validated SPIR-V bytes out) before any VkInstance/pipeline code exists -- a natural phase-ordering seam per FEATURES.md's dependency notes. Also where the "spirv" accept/reject decision and the shaderc-vs-glslang toolchain decision must be made and encoded, since they're schema-validation-shaped decisions, not implementation details.
**Delivers:** Extended gnus-processing-schema.json (render_target, vertex/index buffer bindings + layout, multi-stage shader array, pipeline-state enums, clear values) with regenerated quicktype headers; vendored GLSL-to-SPIR-V compiler toolchain (shaderc recommended, see Decision Flag #2) wired into thirdparty/; mandatory spirv-val gate; explicit CheckProcessValidity() decision on shader_config.type: "spirv" direct input for render passes.
**Addresses:** Schema table-stakes rows from FEATURES.md; resolves Decision Flags #2 and #3.
**Avoids:** Pitfall 6 (unvalidated shader/SPIR-V reaching the driver).
**Research flag:** Standard pattern for the Vulkan-mechanics side (glslang/shaderc APIs are well-documented); the schema-design shape (vertex_layout array, shader-stage array) benefits from a quick review against the existing pass_io_binding convention but doesn't need deep external research.

### Phase 3: ProcessingManager Dispatch Plumbing
**Rationale:** Small, mechanical, and unblocks everything downstream -- RenderProcessor cannot be invoked at all until this lands, and the pre-existing crash bug must be fixed before any render pass can safely reach Process(). Low implementation cost, high blocking value (P1 in FEATURES.md's prioritization matrix).
**Delivers:** ParseBlockSize() type-guard fix (pre-existing pass.get_model().value() crash on model-less passes); a new, separate PassType-keyed dispatch map in ProcessingManager (confirmed NOT safe to reuse the existing DataType-keyed map due to an exact enum collision); GetCidForProc branch for render passes (fetches shader + vertex/index buffer bytes via the existing FileManager/CID-fetch machinery); CheckProcessValidity() parity check requiring a shader config for render passes.
**Uses:** Existing ProcessingProcessor interface, existing FileManager::LoadASync/SaveASync machinery -- deliberately no new plumbing.
**Implements:** ARCHITECTURE.md's "PassType-keyed dispatch alongside DataType-keyed dispatch" pattern.
**Avoids:** Pitfalls 8 (.value()-on-unchecked-optional crash reintroduced for new render fields) and the anti-pattern of reusing the int-cast dispatch map.
**Research flag:** Standard pattern -- this is a well-understood, directly-cited code change (ProcessingManager.cpp:649-840 region) with exact file:line grounding already established in ARCHITECTURE.md; skip research-phase.

### Phase 4: RenderProcessor Implementation (Pipeline, Draw, Readback, Determinism)
**Rationale:** The core deliverable -- depends on Phases 1-3 all being in place (context, validated shaders, dispatch plumbing). Highest implementation cost per FEATURES.md's prioritization matrix, and where the determinism guards must be architectural (not bolted on later per PITFALLS.md).
**Delivers:** Offscreen framebuffer (color+depth), vertex/index buffer upload, pipeline creation from schema pipeline-state fields, uniform/parameter binding (reusing shader_config.uniforms, with push-constants considered as a v1.x simplification), single draw call, fence-gated submit/wait, image->buffer readback; hand-rolled RAII memory allocator (no VMA) with a pooled/reused allocation strategy (not per-job fresh vkAllocateMemory, to avoid allocation-count exhaustion over node uptime); determinism guards (explicit clears everywhere, VK_SAMPLE_COUNT_1_BIT, fixed shader precision, no unordered parallel reduction, pinned pipeline-cache policy).
**Delivers:** RenderProcessor::StartProcessing populating ProcessingResult.output_buffers/.hash, flowing unmodified through the existing output-save/hash path.
**Avoids:** Pitfalls 5 (same-node non-determinism) and 7 (allocation exhaustion/misalignment).
**Research flag:** Needs deeper research/spike during planning specifically for the determinism-guard mechanics (pipeline-cache policy, reduction-order constraints) -- this is the area PITFALLS.md flags as MEDIUM-confidence risk (driver JIT/caching behavior) rather than a certainty, and is worth validating empirically rather than assuming a guard is sufficient.

### Phase 5: Cross-Platform Build Wiring & CI
**Rationale:** Comes last because it validates the full stack (vendoring, macOS/MoltenVK actual execution, CI coverage tiers) rather than building new capability -- but must not be skipped, since CI today has zero real-GPU or software-Vulkan-ICD signal and macOS has zero CI signal of any kind for Vulkan.
**Delivers:** thirdparty/.gitmodules + CommonTargets.cmake additions for vk-bootstrap and the GLSL-to-SPIR-V toolchain (following the existing ExternalProject_Add convention); an actual (not just compiled) run of the render path on a MoltenVK/macOS target; a two-tier CI strategy -- hardware-independent tier (schema validation, shader compile, spirv-val, pipeline construction via a software Vulkan ICD like Lavapipe, test-only, never product code) and a hardware-dependent tier (real vkQueueSubmit+readback, the N>=10-repeat-run determinism test) on a real-GPU runner.
**Avoids:** Pitfalls 4 (MoltenVK/WSI reflexes, zero macOS CI signal) and 9 (conflating "no GPU in CI" with "untestable," or worse, smuggling a software-rasterizer fallback into product code).
**Research flag:** Needs research during planning -- Lavapipe/SwiftShader CI provisioning and GitHub Actions GPU-runner options are infra-specific and not yet verified against this repo's actual CI setup beyond the grounding fact that libvulkan-dev alone is currently installed.

### Phase Ordering Rationale

- Context/coexistence (Phase 1) must precede shader validation (Phase 2) only loosely -- FEATURES.md/ARCHITECTURE.md both note the shader-compile-to-SPIR-V step is independently developable/testable (GLSL string in, SPIR-V bytes out) before any VkInstance exists, so Phases 1 and 2 could in principle run in parallel; they're ordered sequentially here for planning clarity, not a hard dependency.
- Dispatch plumbing (Phase 3) is deliberately small and early because it unblocks RenderProcessor invocation entirely and fixes a pre-existing crash bug that blocks ANY render pass from reaching Process() -- this is explicitly called out in FEATURES.md's dependency graph as a blocking bug fix, not optional hardening.
- The core RenderProcessor implementation (Phase 4) depends on all three prior phases (a validated context, a validated shader/SPIR-V pipeline, and working dispatch) -- this is the genuine critical-path phase and carries the highest implementation cost.
- CI/build wiring (Phase 5) is last because it validates rather than builds -- but pulling in the software-ICD CI tier earlier (even during Phase 2-3) may de-risk faster feedback loops; the roadmap phase should decide whether to front-load part of Phase 5's CI wiring alongside earlier phases rather than treating it as strictly sequential.

### Research Flags

Phases likely needing deeper research/spike during planning:
- **Phase 1 (Vulkan Context Setup & Coexistence):** the concurrent-init stress test and shared-lock design need validation against MNN's actual runtime behavior -- Decision Flag #1 is explicitly not fully closed.
- **Phase 4 (RenderProcessor Implementation):** determinism-guard mechanics (pipeline-cache policy, reduction-order constraints) are MEDIUM-confidence risk per PITFALLS.md, not a certainty -- needs empirical validation, not just design.
- **Phase 5 (Cross-Platform Build Wiring & CI):** Lavapipe/SwiftShader CI provisioning and real-GPU runner options are infra-specific and unverified against this repo's actual CI setup.

Phases with standard, well-documented patterns (skip research-phase):
- **Phase 2 (Schema Extension & Shader Validation):** glslang/shaderc APIs and spirv-val usage are well-documented; the schema-shape work is small and incremental over an existing convention (pass_io_binding).
- **Phase 3 (ProcessingManager Dispatch Plumbing):** exact file:line grounding already established directly in ARCHITECTURE.md; mechanical, low-risk change.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Direct repo inspection (git log/describe on submodules, full-tree grep) plus official-repo/release-note web sources for vk-bootstrap/shaderc/glslang/VMA versioning. |
| Features | HIGH (Vulkan mechanics) / MEDIUM (SPIR-V toolchain choice, determinism guidance) | Vulkan render/readback mechanics cross-checked against canonical spec docs and widely-cited reference implementations (SaschaWillems/Vulkan); toolchain/determinism guidance is established practice, not GNUS-specific verification. |
| Architecture | HIGH for codebase findings, MEDIUM for external Vulkan-spec/loader claims | Direct source reads with file:line citations for all integration points (dispatch collision, GetCidForProc, coexistence code paths); external loader-thread-safety claims cross-checked across 2+ sources but not primary-spec-text quoted verbatim. |
| Pitfalls | HIGH for repo-grounded findings, MEDIUM for general Vulkan/MoltenVK ecosystem findings | mnn_vulkan_mutex, CI vendoring gaps, and schema "spirv" acceptance all directly re-verified against current repo state (2026-07-29); MoltenVK issue reports and driver-crash claims are web-sourced but cross-checked across multiple independent sources per topic. |

**Overall confidence:** HIGH

### Gaps to Address

- **Init-synchronization mechanism (Decision Flag #1):** ARCHITECTURE.md and PITFALLS.md disagree on whether explicit synchronization is strictly necessary; the reconciled recommendation (share one lock, treat MNN's existing mutex as stronger evidence than spec reasoning) should be validated via an actual concurrent-init stress test during Phase 1 planning, not assumed correct from research alone.
- **shaderc vs. glslang (Decision Flag #2):** reconciled toward shaderc here, but this is a real trade-off (integration surface vs. dependency count) that the team should explicitly confirm during Phase 2 planning rather than treat as fully settled.
- **shader_config.type: "spirv" accept/reject policy (Decision Flag #3):** the schema already allows it; the roadmap must make an explicit, written decision (accept-with-spirv-val or reject-for-render) during Phase 2, not defer indefinitely.
- **Driver pipeline-cache determinism risk:** flagged as MEDIUM-confidence (not confirmed to manifest in observed bit differences) -- worth an explicit empirical test early in Phase 4 rather than assuming the guard is sufficient by design alone.
- **CI GPU/software-ICD provisioning:** current CI (libvulkan-dev only, no GPU, no software ICD) has zero real signal for either the render path or macOS/MoltenVK behavior -- this is a known, unaddressed gap to resolve in Phase 5, not something research can close further.

## Sources

### Primary (HIGH confidence)
- Direct repository inspection across all four research passes: thirdparty/.gitmodules, thirdparty/build/CommonTargets.cmake, thirdparty/build/cmake/kompute-fix.cmake, SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp, include/processingbase/ProcessingManager.hpp, include/processors/processing_processor.hpp, src/processors/CMakeLists.txt, generated/PassType.hpp/DataType.hpp/ShaderType.hpp, gnus-processing-schema.json, src/processors/processing_processor_mnn_{image,string,volume}.cpp, SuperGenius/.github/workflows/cmake.yml, thirdparty/MNN/source/backend/vulkan/component/VulkanInstance.hpp, .planning/PROJECT.md (sgproc-render section), archived .planning/milestones/ws-sgproc-render-2026-07-29/research/PITFALLS.md

### Secondary (MEDIUM confidence)
- https://github.com/charles-lunarg/vk-bootstrap, https://github.com/google/shaderc, https://github.com/KhronosGroup/glslang, https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator -- version/license verification
- https://github.com/SaschaWillems/Vulkan/blob/master/examples/renderheadless/renderheadless.cpp and https://www.saschawillems.de/blog/2017/09/16/headless-vulkan-examples/ -- canonical headless render+readback reference
- https://docs.vulkan.org/spec/latest/chapters/{pipelines,fundamentals,initialization,debugging}.html -- Vulkan spec chapters (object scoping, pipeline model, multi-instance behavior)
- https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderInterfaceArchitecture.md -- loader-internal mutex-guarded global state
- https://registry.khronos.org/vulkan/specs/1.3-extensions/man/html/VK_EXT_headless_surface.html -- headless-surface still depends on VK_KHR_surface
- MoltenVK issues #2049, #908, #836 -- headless-adjacent WSI weaknesses
- https://arxiv.org/pdf/2408.05148 -- floating-point non-associativity/GPU determinism
- glslang issue #590, wgpu issue #7198, AMD/NVIDIA developer-forum threads -- compiler/driver crash classes on malformed input

### Tertiary (LOW confidence)
- None -- all sources across the four research files were cross-checked to at least MEDIUM confidence; nothing was flagged LOW.

---
*Research completed: 2026-07-29*
*Ready for roadmap: yes*
