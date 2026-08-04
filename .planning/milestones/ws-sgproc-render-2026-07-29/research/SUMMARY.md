# Project Research Summary

**Project:** GeniusNetwork — sgproc-render workstream
**Domain:** Headless/offscreen Vulkan rendering as a new verifiable-compute `PassType::RENDER` job in SGProcessingManager, a distributed-processing node that already runs MNN inference (including an internal, fully-encapsulated MNN Vulkan backend)
**Researched:** 2026-07-28
**Confidence:** MEDIUM-HIGH (repo-grounded findings HIGH; ecosystem/library and determinism-policy findings MEDIUM; cross-vendor determinism itself is a genuinely unsettled industry problem, not just a gap in this research)

## Executive Summary

This workstream turns `PassType::RENDER` from a no-op stub into a real capability: a headless Vulkan render pass that builds a pipeline from schema config (shader source, vertex/index buffers, render target), executes with no window/swapchain, and returns a hashed, verifiable output through the exact same `ProcessingResult` -> `FileManager::SaveASync` -> hash-return path that MNN inference/retrain jobs already use. Experts building comparable systems (offscreen Vulkan renderers, distributed render networks like Render Network/Golem) converge on the same shape: a thin renderer built directly on the Vulkan API (no game-engine abstraction), render-to-texture via `VkImage`+`vkCmdCopyImageToBuffer` with zero swapchain/surface involvement, and, critically, an explicit, separate answer for how to verify render output across heterogeneous hardware, because bit-exact GPU output across vendors is not guaranteed and naive reuse of the existing exact-hash convention will misfire.

The recommended approach is to vendor three small, permissively-licensed libraries (vk-bootstrap for headless instance/device bootstrap, VMA for buffer/image allocation, shaderc for runtime GLSL->SPIR-V compilation) directly on top of the already-vendored Vulkan-Headers/Vulkan-Loader, and hand-roll a RenderProcessor as a parallel interface alongside (not inheriting) ProcessingProcessor, because the render pass's inputs are plural, PassIoBinding-resolved, and model-less, which does not fit the existing single-IoDeclaration, DataType-keyed factory dispatch at all. PassType-based dispatch must be added as a sibling branch in ProcessingManager::Process(), with a new pass-name-keyed lookup map, since the current passes[i]-by-input-index positional trick has no input to key off of for a render pass.

The single highest-severity risk, cutting across stack, features, architecture, and pitfalls research alike, is cross-vendor/cross-driver output non-determinism: Vulkan does not guarantee bit-identical floating-point or rasterization results across GPU vendors, so hashing raw render-output bytes exactly like MNN tensors do today will falsely reject legitimate results from different hardware. This must be resolved as an explicit design decision (same-node repeat-execution determinism for v1, deferring cross-node tolerance-based verification) before RenderProcessor implementation, not discovered during end-to-end testing. Secondary but real risks are Vulkan-context concurrency (the existing mnn_vulkan_mutex is a function-local static that will not protect a new render init path), MoltenVK's historically weaker headless/no-swapchain support, and CI's current lack of any GPU/software-Vulkan driver (render end-to-end tests cannot run in CI without adding lavapipe/SwiftShader).

## Key Findings

### Recommended Stack

Do not vendor a rendering engine (bgfx, Diligent, Filament, VulkanSceneGraph were all evaluated and rejected — each imposes an abstraction, a large dependency surface, or unconfirmed/rougher headless-Vulkan support that this single-pipeline, schema-declared job doesn't need). Instead, vendor three small libraries as new `thirdparty/` git submodules alongside the existing Vulkan-Headers/Vulkan-Loader, following the repo's established submodule + `find_package(CONFIG REQUIRED)` convention.

**Core technologies:**
- **vk-bootstrap** (MIT, ~1.4.350) — instance/device/queue bootstrap with a first-class `set_headless()` path; removes ~300-500 lines of boilerplate the repo would otherwise hand-roll.
- **VulkanMemoryAllocator / VMA** (MIT, v3.4.0) — buffer/image memory allocation for vertex/index buffers and render-target images; the de-facto industry standard, vendors as cleanly as existing header-only libs already in `thirdparty/`.
- **shaderc** (Apache-2.0, wraps glslang + SPIRV-Tools + SPIRV-Headers) — runtime GLSL->SPIR-V compilation, required because the schema carries raw shader source, not precompiled SPIR-V, as per-job config.
- **Vulkan 1.3 dynamic rendering** (already available in the vendored header version) — avoids VkRenderPass/VkFramebuffer boilerplate for the render-target setup.
- **Reuse the existing `Vulkan::Vulkan` CMake target** — already linked in `SGProcessingManager/src/processors/CMakeLists.txt`; do not add a second `find_package(Vulkan)` or a second vendored loader.

One licensing nuance to flag explicitly for sign-off: glslang (pulled in transitively by shaderc) carries a legacy "GPL-3-with-Bison-exception" clause scoped to an unused legacy preprocessor code path — does not block the non-GPL constraint, but should be on record rather than silently waved through as "just Apache-2.0."

### Expected Features

The MVP scope is a single-mesh render-to-texture job: the smallest slice that proves PassType::RENDER end-to-end and satisfies the milestone's own "verifiable hashed output" criterion.

**Must have (table stakes):**
- `ParseBlockSize()` type-guard fix (hard blocker — unconditional `pass.get_model().value()` crashes on any model-less render/compute pass)
- `RenderProcessor` registered via `PassType`-keyed dispatch in `ProcessingManager::Process()`
- Offscreen framebuffer (color + depth attachment, no swapchain)
- Minimal vertex+fragment shader pipeline, fixed pipeline state (triangle list, back-face cull, no blending)
- Vertex/index buffer upload via staging -> device-local pattern
- Uniform/parameter binding (MVP matrices) reusing existing `shader_config.uniforms` + `parameter:` refs
- Rendered output exposed as `texture2D` through the existing `pass_io_binding` output mechanism (reused, not rebuilt)
- Same-node deterministic hash via repeat execution (explicitly NOT cross-vendor for v1)

**Should have (differentiators, sequenced after MVP):**
- Configurable pipeline state (topology, cull mode, winding)
- Post-render `data_transform` reuse on rendered output (cheapest differentiator — pure config, no new engine code)
- Instancing (once vertex-buffer schema extension lands)
- Texture sampling from external input (shares descriptor/sampler infra with multi-pass)

**Defer (v2+):**
- Multi-pass/post-processing chains (needs new descriptor/sampler infra + inter-pass schema support — genuinely the next big lift)
- Multiple render targets / MRT (needs schema support for multiple color attachments)
- Compute/inference -> render interop (new MNN-tensor-to-Vulkan-buffer bridging plumbing, no existing mechanism covers it)
- Alpha blending/transparency (order-dependent — actively conflicts with determinism)
- Cross-node tolerance/redundancy-based verification (only needed once heterogeneous-hardware verification is actually required)

**Explicit anti-features:** no swapchain/presentation/VSync ever (this is a headless compute node), no continuous frame-pacing render loop (discrete batch job, submit-once-return-hash like inference today), no full 3D-engine surface (skinning, PBR, scene graphs), no shader hot-reload, no persistent Vulkan context shared across unrelated jobs, no default-on MSAA.

### Architecture Approach

The render path is added as a second, independent resolution branch inside `ProcessingManager::Process()` — dispatched on `pass.get_type()` before falling through to the existing `DataType`-keyed `m_processorFactories` path, which remains completely untouched. `RenderProcessor` is a new, parallel interface (does NOT inherit `ProcessingProcessor`) because the inference-shaped interface (`StartProcessing(chunkhashes, const IoDeclaration&, imageData, modelFile, parameters)`) assumes one input and one model file, while a render pass has an ordered list of `PassIoBinding`-resolved inputs and no model at all. A new pass-name-keyed lookup map (`m_passMap`), built in `Init()` alongside the existing `m_inputMap`, replaces the positional `passes[i]`-by-input-index trick that has nothing to key off of for a model-less render pass.

**Major components:**
1. `ProcessingManager` — modified to add the PassType switch, pass-name map, and a `CheckProcessValidity()` render case that validates `pass.get_shader()` presence (currently a silent no-op).
2. `RenderProcessor` (new) — builds and executes one headless render pipeline from a schema Pass; constructed per-execution (construct -> execute -> readback -> destroy), not a long-lived member like `m_processor`.
3. `VulkanRenderContext` (new) — a process-wide singleton owning `VkInstance`/`VkPhysicalDevice`/`VkDevice`/`VkQueue`, created once and lazily, fully independent of MNN's internal (unexposed) Vulkan context; command pools/buffers/descriptor pools/render-target images are owned per-`RenderProcessor` instance, not on the shared context.
4. Everything downstream of `ProcessingResult` (hash format, `FileManager::SaveASync`, IPFS dual-save, `output_locations`, proto `SubTaskResult`) is reused completely unmodified — a render pass is just another producer of a `ProcessingResult`.

Recommended build order: schema extension -> `ParseBlockSize()` fix (parallelizable with schema work) -> `PassType` dispatch plumbing + `CheckProcessValidity()` render case -> Vulkan context setup (parallelizable, independently smoke-testable) -> `RenderProcessor` implementation (depends on all three prior) -> end-to-end proof.

### Critical Pitfalls

1. **Cross-vendor/cross-driver output non-determinism breaks hash-verification consensus** — Vulkan does not guarantee bit-identical floating-point/rasterization results across GPU vendors; reusing the exact-match SHA-256 convention MNN uses today will misfire across heterogeneous hardware. Resolve as an explicit design decision (same-node determinism for v1) during schema/dispatch design, before RenderProcessor implementation, and test on >=2 distinct GPU vendors/backends at end-to-end verification, not just one machine.
2. **Concurrent Vulkan init race with MNN's existing (function-local-static, not process-wide) `mnn_vulkan_mutex`** — a new render-context init path has zero mutual exclusion against MNN's Vulkan session creation if scheduled concurrently. Introduce one header-declared, process-wide `VulkanInitGuard` singleton and migrate the 3 existing MNN Vulkan call sites onto it, rather than adding a second uncoordinated lock.
3. **No Vulkan validation layers vendored, and CI has no GPU/software Vulkan driver at all** — `thirdparty/` vendors only headers+loader, and CI installs only `libvulkan-dev` (no `mesa-vulkan-drivers`, no VVL). This gives false confidence in "debug builds" and means the render path's end-to-end test literally cannot run in CI until a software rasterizer (lavapipe/SwiftShader) is added.
4. **MoltenVK headless assumed to "just work"** because MNN's Vulkan-via-MoltenVK usage already works — but MNN never creates a swapchain/does WSI work, so it never exercised MoltenVK's historically weaker surface areas. Design the renderer to never create a `VkSurfaceKHR`/`VkSwapchainKHR` at all (pure `VkImage` + `vkCmdCopyImageToBuffer`), and actually run (not just compile) the render path on a MoltenVK target.
5. **Schema allows non-portable `ShaderType` values (`metal`/`hlsl`)** that would reintroduce the determinism problem at the shader-authoring level on top of driver-level divergence. Constrain render passes to SPIR-V only via an explicit `CheckProcessValidity()` rejection, not just documentation.
6. **The `ParseBlockSize()` `.value()`-on-unchecked-`boost::optional` bug pattern will recur** for every new render-specific optional schema field unless a type-guard discipline (switch on `pass.get_type()` before touching type-specific fields) is applied uniformly and checked in code review, not just at the one named call site.

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: Dispatch plumbing + validity-guard fixes
**Rationale:** Cheapest, most independent work; unblocks testing of everything else and fixes an already-identified crash. Can proceed with a stub render handler before the Vulkan work exists.
**Delivers:** `ParseBlockSize()` type-guard fix; `PassType`-keyed dispatch branch + `m_passMap` in `ProcessingManager::Process()`; `CheckProcessValidity()` render case validating `pass.get_shader()` presence and rejecting non-SPIR-V `ShaderType`.
**Addresses:** Table-stakes "`ParseBlockSize()` fix" and "`RenderProcessor` registered via `PassType`-keyed dispatch" from FEATURES.md.
**Avoids:** Pitfall 6 (non-portable shader types) and Pitfall 7 (`.value()` crash pattern reintroduced).

### Phase 2: Schema extension
**Rationale:** Everything downstream (vertex/index buffer bindings, multi-stage shader config, render-target/framebuffer config) reads generated types from this; must land early even though it's largely parallelizable with Phase 1's scaffolding.
**Delivers:** Extended `gnus-processing-schema.json` + regenerated `generated/*.hpp` for render-specific `Pass` fields.
**Addresses:** Dependency root for nearly every table-stakes feature in FEATURES.md.
**Avoids:** Pitfall 6 by design (schema should not even offer `metal`/`hlsl` as valid for render passes, reinforced by Phase 1's validation).

### Phase 3: Vulkan context setup (`VulkanRenderContext`)
**Rationale:** Independently smoke-testable (a standalone "create headless device, clear a framebuffer, read back a solid color" test) before any `ProcessingManager` wiring exists; also where the highest-severity concurrency and platform pitfalls must be resolved.
**Delivers:** Process-wide singleton owning `VkInstance`/`VkPhysicalDevice`/`VkDevice`/`VkQueue`, headless-only (no `VkSurfaceKHR`/`VkSwapchainKHR` anywhere), plus the shared `VulkanInitGuard` migration for MNN's existing call sites.
**Uses:** vk-bootstrap (`set_headless()`), VMA, Vulkan-Headers/Loader (already vendored) from STACK.md.
**Implements:** `VulkanRenderContext` component from ARCHITECTURE.md.
**Avoids:** Pitfall 1 (MNN context sharing assumptions), Pitfall 2 (concurrent init race), Pitfall 5 (MoltenVK swapchain assumptions).

### Phase 4: `RenderProcessor` implementation
**Rationale:** Depends on schema (Phase 2), dispatch branch (Phase 1), and context (Phase 3) all being in place; this is the actual pipeline-construction -> execution -> readback logic.
**Delivers:** Pipeline build from schema shader config (via shaderc runtime compilation), vertex/index buffer upload, offscreen render-to-texture with depth testing, uniform binding, `vkCmdCopyImageToBuffer` readback wrapped in the existing `ProcessingResult` shape.
**Uses:** shaderc, VMA from STACK.md; Pattern 2 (parallel interface, not `ProcessingProcessor` subclass) from ARCHITECTURE.md.
**Addresses:** The full P1 feature set from FEATURES.md's MVP definition.
**Avoids:** Pitfall 7 (optional-field type guards must be applied to every new field touched here).

### Phase 5: Determinism policy + CI enablement
**Rationale:** The single highest-severity cross-cutting risk (Pitfall 4) must be explicitly decided and testable before calling the feature "done," and it requires CI infrastructure (software Vulkan driver) that doesn't exist today.
**Delivers:** Explicit same-node-determinism verification design (repeat-execution hash match), SPIR-V validation of job-supplied shaders before `vkCreateShaderModule` (security mitigation), and CI wiring to install `mesa-vulkan-drivers`/lavapipe so the render path's device-creation-through-readback flow actually executes in CI instead of silently having no GPU signal.
**Addresses:** "Deterministic, reproducible readback for hashing/verification" (P1 feature) and the cross-vendor determinism gap flagged throughout FEATURES/PITFALLS.
**Avoids:** Pitfall 4 (cross-vendor non-determinism), Pitfall 3 (validation layers/CI GPU gap), the SPIR-V injection security mistake noted in PITFALLS.md.

### Phase 6: End-to-end proof + cross-platform verification
**Rationale:** Final integration phase — confirms the entire pipeline (schema -> dispatch -> context -> RenderProcessor -> hash -> save) actually works, and specifically exercises the platform/hardware variance that earlier phases could only design against.
**Delivers:** A real render pass definition executing through the distributed pipeline end-to-end, producing a verifiable output hash; an actual (not just compiled) run on a MoltenVK/Apple target; a test run against >=2 GPU vendors or hardware-vs-software backends confirming the determinism policy from Phase 5 holds.
**Addresses:** Milestone's own "end-to-end proof" success criterion.
**Avoids:** All "looks done but isn't" checklist items from PITFALLS.md — this phase is specifically where those get caught if earlier phases missed them.

### Phase Ordering Rationale

- Dispatch/validity plumbing (Phase 1) and schema extension (Phase 2) are largely parallelizable, but both must land before `RenderProcessor` (Phase 4) can be written against real types.
- Vulkan context setup (Phase 3) is architecturally independent of the schema shape and can be developed/smoke-tested concurrently with Phases 1-2 — sequencing it third here reflects dependency completeness for `RenderProcessor`, not a hard technical ordering constraint.
- Determinism policy (Phase 5) is deliberately placed after a working `RenderProcessor` rather than before, because same-node repeat-execution testing needs a working pipeline to test against — but the decision (same-node-only for v1) must be made conceptually during Phases 1-2, not discovered late; this is called out as a cross-cutting flag, not something Phase 5 invents from scratch.
- CI enablement is bundled into Phase 5 rather than a separate phase because it's a hard precondition for Phase 6's cross-hardware verification claim to be trustworthy/repeatable rather than a one-off manual test.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 3 (Vulkan context setup):** MoltenVK headless-surface edge cases and the exact shared-lock design versus MNN's existing mutex are non-trivial; worth a `--research-phase` pass to nail down the concrete vk-bootstrap + VMA wiring and the `VulkanInitGuard` migration mechanics.
- **Phase 5 (Determinism policy + CI):** This is explicitly flagged in PITFALLS.md as a cross-cutting, currently-unresolved design decision requiring sign-off from whoever owns consensus/verification logic outside SGProcessingManager — needs research/discussion beyond what STACK/FEATURES/PITFALLS could resolve unilaterally.

Phases with standard patterns (skip research-phase):
- **Phase 1 (Dispatch plumbing):** Well-documented in ARCHITECTURE.md (Pattern 1, Anti-Pattern 1) with concrete illustrative code and an exact existing precedent (`m_inputMap` construction) to mirror.
- **Phase 4 (`RenderProcessor` implementation):** Standard offscreen-Vulkan patterns (staging->device-local buffer upload, dynamic rendering, `vkCmdCopyImageToBuffer` readback) are well-established and cross-corroborated across multiple independent Vulkan tutorial/reference sources in STACK.md/FEATURES.md.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Licenses verified directly against source LICENSE files; library capability claims (headless support, MIT/Apache-2.0 status) cross-checked across multiple independent sources. A few rejected-alternative capability details are MEDIUM/LOW as individually noted in STACK.md. |
| Features | MEDIUM | Vulkan mechanics (offscreen framebuffer, staging-buffer uploads, MVP scoping) are HIGH-confidence, well-established patterns. The verifiable-render-output/determinism policy is genuinely unsettled industry-wide — MEDIUM/LOW by nature, not a research gap. |
| Architecture | HIGH | Entirely grounded in direct, primary-source reads of this repo's actual `ProcessingManager.cpp`, generated schema headers, and CMake files at the checked-out commit — not inference from general Vulkan knowledge. |
| Pitfalls | HIGH for repo-grounded findings (direct source read of the mutex, CI workflow files, CMake linkage); MEDIUM for general Vulkan/MoltenVK ecosystem findings (web search, cross-checked against multiple sources), explicitly marked per-pitfall in PITFALLS.md. |

**Overall confidence:** MEDIUM-HIGH — the engineering path (stack, architecture, implementation pitfalls) is solidly grounded in this repo's own code and industry-standard Vulkan patterns. The one genuine open question — cross-node/cross-vendor verification policy — is not a research gap so much as a real, industry-wide unsolved tradeoff that this workstream must make an explicit, scoped decision about (same-node determinism for v1) rather than resolve definitively.

### Gaps to Address

- **Cross-node verification policy is undecided and needs sign-off from whoever owns consensus/validation logic outside SGProcessingManager.** Handle during Phase 5 planning: explicitly scope v1 to same-node repeat-execution determinism, and treat cross-node tolerance-based verification as an explicitly deferred v2+ item, not an implicit assumption.
- **CI currently has zero Vulkan device signal (no GPU, no software rasterizer installed).** Handle during Phase 5/6 planning: add `mesa-vulkan-drivers` (lavapipe) or SwiftShader to Linux CI runners before treating any render-path CI result as meaningful; without this, "green in CI" is not evidence of anything for this feature.
- **Whether to vendor `Vulkan-ValidationLayers` (VVL) is an explicit open decision**, not yet made one way or the other. Handle during Phase 3 planning: make and document the decision (vendor gated to debug builds, vs. explicitly accept the gap) rather than leaving it implicit.
- **Descriptor/sampler binding infrastructure needed for multi-pass chains and external-texture sampling does not exist yet and is deliberately out of scope for this milestone's phases.** Flag for a future milestone rather than building speculatively now.
- **Schema extension's exact field shapes (render_target/framebuffer config, vertex/index buffer bindings, multi-stage shader) were deliberately not designed by this research round** — ARCHITECTURE.md and FEATURES.md both treat it as a dependency, not a deliverable, of this synthesis. Phase 2 planning will need to nail down the concrete schema shape as its own design step.

## Sources

### Primary (HIGH confidence)
- Direct repository reads: `SGProcessingManager/src/processingbase/ProcessingManager.cpp`, `include/processingbase/ProcessingManager.hpp`, `include/processors/processing_processor.hpp`, `src/processors/processing_processor_mnn_image.cpp` (mutex pattern), `gnus-processing-schema.json` and generated `*.hpp` types, `src/processing/impl/processing_core_impl.cpp`, `src/processing_tasksplit.cpp`, `src/processors/CMakeLists.txt`, `src/processing/CMakeLists.txt`, `build/OSX/CMakeLists.txt`, `build/iOS/CMakeLists.txt`, `.github/workflows/cmake.yml`/`build-release-tags.yml`, `thirdparty/Vulkan-Headers`/`Vulkan-Loader` submodule state, `thirdparty/ThirdParty_Libraries_Integration.md`, `.planning/PROJECT.md`
- Direct fetch of `charles-lunarg/vk-bootstrap` `LICENSE.txt` (MIT), `google/shaderc` `LICENSE` (Apache-2.0), `KhronosGroup/glslang` `LICENSE.txt` (mixed, GPL-Bison-exception noted)

### Secondary (MEDIUM confidence)
- Sascha Willems' Vulkan offscreen rendering example (reference pattern for framebuffer/render-pass-without-swapchain)
- Vulkan-Tutorial / KhronosGroup staging-buffer chapter (staging -> device-local upload pattern)
- Render Network (RNDR), Golem/iExec public docs and Golem's Blender-verification blog post (determinism/verification policy precedent)
- MoltenVK issue #2049, `Whats_New.md`, and the `VK_EXT_headless_surface` Khronos registry spec (headless surface support history)
- bgfx/Diligent Engine/VulkanSceneGraph/Filament license and headless-status web research (rejected alternatives)
- NVIDIA developer forum discussion on multi-`VkInstance`/`VkDevice` behavior in one process

### Tertiary (LOW confidence)
- General GPU floating-point non-determinism literature (arXiv summaries on verifiable ML inference) — analogous to, but not specific to, graphics rasterization; treated as strong circumstantial evidence
- SwiftShader/Mesa Lavapipe as a CI mitigation path — noted but not independently verified against this project's specific needs
- Diligent Engine's headless-Vulkan-without-swapchain claim — could not be confirmed from public docs alone

---
*Research completed: 2026-07-28*
*Ready for roadmap: yes*
