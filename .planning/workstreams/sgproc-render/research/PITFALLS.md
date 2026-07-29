# Pitfalls Research: Hand-Rolled Headless Vulkan Render Pass in SGProcessingManager

**Domain:** Adding a second, independent, hand-rolled headless Vulkan `RenderProcessor` to a distributed-compute node process that already uses Vulkan internally via MNN (inference-only, fully encapsulated), per `GeniusVentures/SGProcessingManager#7`
**Researched:** 2026-07-29
**Confidence:** HIGH for repo-grounded findings (direct source read, confirmed current as of this research date); MEDIUM for general Vulkan/MoltenVK ecosystem findings (web search, cross-checked across multiple independent sources per topic — see Sources). Nothing here is presented as LOW confidence; where sources disagreed or a claim couldn't be cross-checked, it is flagged inline.

**Scope note:** This is a full restart of a prior bgfx-based attempt (archived at `.planning/milestones/ws-sgproc-render-2026-07-29/research/PITFALLS.md`). Several grounding facts and integration pitfalls carry over unchanged because they live at the Vulkan-coexistence layer, not the bgfx layer — this document re-verifies each against current repo state and re-scopes the determinism pitfall specifically to **same-node repeat-run determinism only** (cross-vendor/cross-tier tolerance is explicitly out of scope this milestone, unlike the prior attempt).

## Grounding facts (from this repo, verified 2026-07-29 — not general Vulkan knowledge)

- MNN's Vulkan backend is invoked via `MNN::ScheduleConfig.type = MNN_FORWARD_VULKAN` in 3 processors (`processing_processor_mnn_image.cpp`, `_string.cpp`, `_volume.cpp`). MNN owns its `VkInstance`/`VkDevice`/`VkQueue` internally — nothing is exposed to callers.
- `processing_processor_mnn_image.cpp:114-115` still guards MNN Vulkan init with a **function-local `static std::mutex mnn_vulkan_mutex`**, scoped to that one translation unit only — `_string.cpp`/`_volume.cpp` do NOT share this instance, so their `createSession(netConfig)` calls with `MNN_FORWARD_VULKAN` are unguarded relative to each other and to any new `RenderProcessor` init code. The comment explicitly frames this as a stopgap "until MNN exposes a shareable runtime/session API."
- `thirdparty/` vendors `Vulkan-Headers` and `Vulkan-Loader` (confirmed present as submodules) plus `MoltenVK` for Apple targets. **No `Vulkan-ValidationLayers`/VVL submodule exists.** No `glslang`, `shaderc`, or `SPIRV-Tools` submodule exists either — confirming PROJECT.md's open question: a SPIR-V compiler/validator toolchain does need to be added net-new this milestone, it is not already vendored.
- `SGProcessingManager/src/processors/CMakeLists.txt` already links `MNN::MNN` and `Vulkan::Vulkan` directly — a single `Vulkan::Vulkan` CMake target already exists in scope. A `RenderProcessor` must reuse this target, not add a second `find_package(Vulkan)` or a second vendored loader.
- CI (`SuperGenius/.github/workflows/cmake.yml:520`) installs only `libvulkan-dev` on Linux runners (loader dev package) — no `mesa-vulkan-drivers`/lavapipe, no `vulkan-validationlayers-dev`, no SwiftShader. GitHub-hosted Linux runners have no GPU. MNN's Vulkan backend is known to silently fall back to CPU when Vulkan device init fails, which has likely masked this CI gap for the 3 existing MNN Vulkan processors. `RenderProcessor` has **no fallback tier by explicit mandate** — it will hard-fail `vkCreateInstance`/`vkEnumeratePhysicalDevices` in exactly this CI environment where MNN silently degraded, unless CI is given at least a software Vulkan implementation.
- `generated/ShaderType.hpp` currently defines `enum class ShaderType : int { GLSL, HLSL, METAL, SPIRV }`, and `gnus-processing-schema.json`'s `shader_config.type` enum still literally allows `"glsl" | "hlsl" | "metal" | "spirv"` (default `"glsl"`) — **`"spirv"` is already a valid schema value today**, meaning a job can supply raw SPIR-V bytes directly, bypassing GLSL source and any GLSL-level compiler diagnostics entirely. This milestone's decision to author shaders as GLSL compiled via glslang/shaderc does not by itself close this path unless the render-specific schema validation explicitly narrows or gates it.
- `PassType::RENDER` is still an empty `case PassType::RENDER: break;` in `CheckProcessValidity()` (`ProcessingManager.cpp:151`) — no field validation exists yet, and `Process()`'s dispatch is entirely `DataType`-keyed via MNN processor factories, with no `PassType`-based branch anywhere yet.
- Output hashing already exists as an established pattern: MNN processors compute `sha256(...)` over raw tensor bytes and chain results into a `subTaskResultHash`. The render path is expected to plug into the same raw-bytes-hash convention — this milestone narrows the correctness bar to **same-node, repeat-run bit-exactness**, not cross-node bit-exactness, which changes which non-determinism sources actually matter (see Pitfall 5).

---

## Critical Pitfalls

### Pitfall 1: Treating "independent VkInstance" as "isolated from MNN," and racing instance/device creation with MNN's init path

**What goes wrong:**
A developer assumes that because the render context uses its own `VkInstance`/`VkDevice`, it can't interfere with MNN's separate Vulkan context — "independent objects" reads as "isolated," but it only means "separately-owned handles." Both instances load the same system Vulkan loader/ICD in the same process and can target the same physical GPU. `vkCreateInstance`/`vkCreateDevice`/`vkEnumeratePhysicalDevices` are the exact calls MNN already needed a mutex around (`mnn_vulkan_mutex`) because concurrent Vulkan init is documented as unsafe on at least some ICDs. That mutex is a **function-local static** in one MNN file — it does not protect a new `RenderProcessor`'s init path, nor MNN's own `_string.cpp`/`_volume.cpp` call sites, against each other.

**Why it happens:**
The mutex was scoped defensively to the one file it lives in, with a comment acknowledging it's a stopgap. It isn't exported, documented outside that comment, or discoverable from a render-feature vantage point — nobody adding `RenderProcessor` has a natural reason to go find it.

**How to avoid:**
- Keep the render context's ownership model strictly independent (own `VkInstance`, own `VkPhysicalDevice` selection, own `VkDevice`, own `VkQueue`) — do not attempt to reach into or share MNN's internal handles even if a future MNN version exposes them.
- Introduce **one process-wide, header-declared synchronization primitive** (e.g. a `VulkanInitGuard` singleton with a real header) that both the 3 existing MNN Vulkan call sites and the new render context-creation path acquire before any `vkCreateInstance`/`vkCreateDevice`/`vkEnumeratePhysicalDevices` call. Migrate the existing `mnn_vulkan_mutex` call site to use it rather than leaving two uncoordinated locks. Steady-state work (`vkQueueSubmit` after creation, using separate queues) does not need this lock — only the init/create phase does.

**Warning signs:**
Intermittent `VK_ERROR_INITIALIZATION_FAILED`/`VK_ERROR_DEVICE_LOST` only under load or only on first-run-after-boot; crashes that only reproduce when a render subtask and an MNN-Vulkan inference subtask are scheduled close together in time; driver-specific (NVIDIA vs AMD vs Mesa) crashes that don't reproduce in isolation.

**Phase to address:** Early architecture — Vulkan context setup phase, before `RenderProcessor` implementation begins. Verify with a stress test that constructs the render context and triggers MNN Vulkan inference concurrently from multiple threads, repeated enough times to catch a race (a single passing run proves nothing here).

---

### Pitfall 2: Both Vulkan clients independently "auto-pick the best GPU" with no coordination, landing on inconsistent or resource-contending devices

**What goes wrong:**
`vkEnumeratePhysicalDevices` device ordering is not guaranteed stable or consistent across systems (Linux in particular can report an integrated GPU before a discrete one even when the discrete GPU is primary). If MNN's internal device-selection logic and the new `RenderProcessor`'s device-selection logic each independently implement "index 0" or a similarly naive rule without coordinating, on a multi-GPU node they can silently select *different* physical devices — causing avoidable cross-GPU data movement if their outputs ever need to interact, and making driver-level VRAM/queue contention behavior effectively random per node. Conversely, if they *do* land on the same GPU (the common single-GPU-node case), Vulkan itself provides no built-in visibility between the two independent clients into each other's VRAM usage — each is a fully separate GPU context from the other's point of view, so a render job's memory footprint and an MNN inference job's memory footprint can compete for the same heap budget with neither side aware of the other.

**Why it happens:**
Vulkan intentionally does not provide inter-process- or inter-context-aware resource arbitration — that's the application's job. It's easy to write device selection as "just pick the first suitable device" without realizing a second, independent Vulkan client already exists in the same process making its own independent choice.

**How to avoid:**
- Implement device selection as an explicit, deterministic scoring function (discrete > integrated, required features/limits present, then lowest `deviceID` as a tiebreaker) rather than "index 0" — this alone makes the render context's choice *reproducible* across runs even without direct coordination with MNN.
- If MNN's device-selection logic is inspectable/controllable (check MNN's Vulkan backend config surface), apply the same scoring rule on both sides so they converge on the same physical device by construction, rather than by accident.
- Do not attempt cross-context VRAM budget sharing (out of scope, and Vulkan has no first-class primitive for it across independent contexts) — but do document, as an explicit known limitation, that a node running large MNN inference and a render pass concurrently has no built-in memory-pressure coordination between the two.

**Warning signs:**
`VK_ERROR_OUT_OF_DEVICE_MEMORY` under concurrent MNN+render load that doesn't reproduce when either workload runs alone; render or inference selecting a different GPU than expected on a multi-GPU test machine; behavior that differs between single-GPU and multi-GPU nodes in ways that aren't accounted for in test coverage.

**Phase to address:** Early architecture — Vulkan context setup phase, alongside Pitfall 1's synchronization work (device selection logic is part of the same init path).

---

### Pitfall 3: Missing validation layers and process-global loader environment variables give false confidence and cross-context surprises

**What goes wrong:**
Two related traps: (1) No `Vulkan-ValidationLayers` submodule is vendored, and CI's `libvulkan-dev` package provides only the loader, not layers. A developer testing locally with a system-installed Vulkan SDK (which *does* have `VK_LAYER_KHRONOS_validation`) sees clean validation output and ships, while CI/clean-checkout builds silently have zero validation coverage — API misuse (invalid usage, missing synchronization, resource lifetime errors) goes undetected until it manifests as a driver crash on a different machine. (2) Loader-level environment variables like `VK_ICD_FILENAMES`/`VK_LAYER_PATH` are **process-global**, not per-instance — if anything in the process (test harness, CI config, a debugging session) sets one of these to steer MNN's Vulkan context to a specific ICD/layer set, it silently affects the render context's instance creation too, and vice versa.

**Why it happens:**
Validation layers are conventionally assumed to "just be there" with any Vulkan install, but this repo deliberately vendors only headers/loader (permissive-license constraint), and the loader's environment-variable-driven configuration surface was designed for single-application-per-process use, predating the idea of two independent Vulkan clients sharing one process.

**How to avoid:**
- Make an explicit, written decision this milestone: vendor `Vulkan-ValidationLayers` (Apache-2.0, satisfies the no-GPL constraint) gated behind `CMAKE_BUILD_TYPE STREQUAL "Debug"` following the existing debug-only-define pattern in `CommonBuildParameters.cmake`, or explicitly document validation as developer-machine-only/opt-in and not CI-covered. Do not let "debug build" implicitly mean "validated build."
- Debug messengers themselves are safe to use per-context — each `VkInstance` gets its own `VkDebugUtilsMessengerEXT`, callbacks fire independently and thread-safely per Vulkan's documented behavior. The trap is specifically the environment-variable layer, not the messenger API. Avoid setting `VK_ICD_FILENAMES`/`VK_LAYER_PATH` in test/CI scripts without accounting for the fact that it applies to *both* MNN's and the render context's instance creation in the same process.

**Warning signs:**
No validation errors ever surface in CI even when a known-bad synchronization bug is deliberately introduced (a good canary check to run once); `vkCreateInstance` returning `VK_ERROR_LAYER_NOT_PRESENT` only in CI/clean builds, never on a preconfigured dev machine; MNN Vulkan behavior changing unexpectedly after a render-context environment-variable tweak intended only for the renderer.

**Phase to address:** Early architecture — Vulkan context setup phase should include the written VVL vendoring decision. Cross-platform build wiring phase should confirm CI doesn't silently assume validation ran.

---

### Pitfall 4: Reflexively pulling in `VK_KHR_surface`/swapchain machinery (and MoltenVK-specific headless gaps) for a job that never presents anything

**What goes wrong:**
Nearly all public Vulkan tutorials and sample code are window/swapchain-first. A developer implementing "headless" rendering by habit reaches for `VK_KHR_surface`/`VK_KHR_swapchain` extensions, or worse, for `VK_EXT_headless_surface` thinking it's the "headless" answer — but `VK_EXT_headless_surface` is a *different, narrower* mechanism (a no-op presentable surface, mainly for driver conformance/testing) that itself still depends on `VK_KHR_surface`, reintroducing the exact WSI dependency a true offscreen compute-node job should avoid entirely. On MoltenVK specifically, WSI-adjacent surfaces have historically been the weakest part of the implementation (a pure Metal-translation shim, not a native ICD) — `VK_EXT_headless_surface` support was only requested/added relatively recently, and headless-adjacent usage has had reported issues (system freeze/GPU timeout in one headless-compute issue, black-image results from `vkCmdCopyImage` in another). None of this is required for true offscreen rendering.

**Why it happens:**
"Headless" is easy to conflate with "headless *surface*" because of naming, and copied sample code almost universally assumes a window exists.

**How to avoid:**
- Never create a `VkSurfaceKHR`/`VkSwapchainKHR` at all, on any platform. Render to a plain `VkImage` (`VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT`) backing a `VkFramebuffer`, then read back via `vkCmdCopyImageToBuffer` or `vkMapMemory` on a linear-tiled staging image. This is portable across Windows, Linux, and MoltenVK with zero WSI involvement and sidesteps `VK_EXT_headless_surface` entirely — it isn't needed for a submit-once, no-presentation job.
- On the instance/device level, do not request `VK_KHR_surface`, `VK_KHR_swapchain`, or any platform-surface extension (`VK_KHR_win32_surface`, `VK_KHR_xlib_surface`/`VK_KHR_xcb_surface`, `VK_MVK_macos_surface`/`VK_EXT_metal_surface`) — none of these are needed for image-only offscreen work.
- If MoltenVK's environment/config surface (`MVK_CONFIG_*`) is touched for any reason, treat it as a MoltenVK-only code path with its own explicit testing — do not assume behavior parity with native Windows/Linux ICDs.

**Warning signs:**
Any `vkCreateSwapchainKHR`/`vkCreateXlibSurfaceKHR`/`vkCreateWin32SurfaceKHR`/`vkCreateMacOSSurfaceMVK`-style call anywhere in the renderer's code (a design smell for a headless compute node); `VK_KHR_surface` or `VK_KHR_swapchain` appearing in the enabled-extensions list at instance/device creation; behavior that only differs on macOS/MoltenVK builds.

**Phase to address:** Early architecture — establish "no swapchain, no surface extensions, ever" as a hard design constraint before `RenderProcessor` implementation begins. Cross-platform build wiring phase must include an actual macOS/MoltenVK *run* (not just compile) of the render path — CI currently only installs Vulkan deps on Linux runners, so macOS behavior has no CI signal today.

---

### Pitfall 5: Assuming "same GPU, same driver" guarantees bit-exact output across repeat runs

**What goes wrong:**
Even fully restricting the correctness bar to same-node, same-hardware, repeat-run determinism (as this milestone does — cross-vendor tolerance is explicitly out of scope), several independent sources of non-determinism remain and can silently break a strict-hash comparison between two runs of the identical job on the identical machine:
- **Uninitialized memory:** `VK_ATTACHMENT_LOAD_OP_DONT_CARE` and freshly-allocated (or aliased) device memory leave contents explicitly undefined per the Vulkan spec — if any output byte range is read before being fully written by the render pass (e.g. a partially-covered framebuffer region, padding bytes in a buffer layout, or an aliased resource read before its first write), its value differs run-to-run based on whatever was previously in that memory.
- **Multi-threaded/asynchronous submission ordering:** If command buffer recording or queue submission order for a job's independent pieces varies between runs (e.g. driven by a thread pool without deterministic ordering), and the shader's math includes any parallel-reduction-style accumulation (atomics, unordered adds across invocations/subgroups), floating-point non-associativity means summation order differences produce different least-significant-bit results even on identical hardware.
- **Driver-level caching/JIT behavior:** Drivers commonly cache compiled shader binaries (pipeline caches) and may apply different internal optimization passes on a "cold" first compile vs. a "warm" cache hit; if the render pass ever creates its `VkPipeline` without an explicit, deterministic `VkPipelineCache` policy, a rebuilt pipeline from source SPIR-V could theoretically diverge from a cache-hit pipeline in the driver's JIT output (documented as at least a theoretical risk in driver-caching discussions; not confirmed to manifest in observed bit differences the way the other two mechanisms are — flag as MEDIUM-confidence risk, not a certainty).

**Why it happens:**
GPU execution is fundamentally massively parallel; "same hardware" does not imply "same execution schedule" unless the application explicitly constrains it, and reading uninitialized memory is the single most common source of apparent non-determinism in graphics code generally.

**How to avoid:**
- Never rely on `LOAD_OP_DONT_CARE` for any region whose contents feed the hash — either explicitly clear (`VK_ATTACHMENT_LOAD_OP_CLEAR` with a fixed clear value) or guarantee full coverage by the render pass before any readback.
- Design shader math and buffer layouts to avoid unordered parallel accumulation into the hashed output; if any reduction is needed, use a fixed, deterministic reduction order (e.g. a tree reduction with a fixed shape) rather than `atomicAdd`-style unordered accumulation.
- Treat command buffer/queue submission order for a single job as fixed and single-threaded from this component's perspective (submit-once batch job, not a real-time multi-frame pipeline — there's no performance reason to parallelize submission order within one job), removing that entire class of non-determinism by construction rather than by testing around it.
- Pin a specific `VkPipelineCache` policy (either always create fresh with an empty cache, or always warm the cache identically before the timed/hashed run) so cold-vs-warm driver-compile variance isn't a variable the test happens to not exercise.
- Zero-fill (or otherwise fully initialize) any staging/output buffer before use as a defensive measure, independent of whether `LOAD_OP_DONT_CARE` is used elsewhere — cheap insurance against accidentally-read uninitialized regions.

**Warning signs:**
Two back-to-back runs of the identical job on the identical machine/GPU/driver produce different output hashes (the single most important test to actually run — do not assume same-node determinism holds just because same-node execution "looks" deterministic); hash differences that appear only after a cold process start vs. a warm one (pipeline-cache suspect); hash differences correlated with concurrent-load conditions (submission-ordering suspect) rather than appearing on isolated single-job runs.

**Phase to address:** Design decision during schema extension / `RenderProcessor` implementation (buffer initialization and reduction-order constraints must be architectural, not bolted on later); explicitly tested in the end-to-end verification phase via a "run the identical job N times back-to-back on one node, assert identical hash every time" test — this is the actual acceptance criterion for the milestone's determinism requirement, and it is cheap to run (no second machine/GPU vendor needed, unlike the prior cross-vendor attempt).

---

### Pitfall 6: Job-supplied shader (GLSL *or* raw SPIR-V) reaches `vkCreateShaderModule`/pipeline creation without an explicit, separate validation gate

**What goes wrong:**
Two distinct failure classes if shader validation is skipped or assumed to be "handled by the compiler":
- Malformed GLSL source can crash `glslang`/`shaderc`'s compiler itself on some inputs (documented glslang issue: a `nullptr` `treeRoot` crash in the linker pass on certain malformed HLSL/GLSL geometry-shader-style inputs) rather than returning a clean compile error.
- Separately — and this is the sharper edge case for this repo specifically — `gnus-processing-schema.json`'s `shader_config.type` enum already includes `"spirv"` today. A job that supplies `type: "spirv"` bypasses GLSL/glslang entirely and hands raw SPIR-V bytes straight toward `vkCreateShaderModule`. Invalid-but-syntactically-parseable SPIR-V that skips `spirv-val` is documented to crash `vkCreateShaderModule`/`vkCreateGraphicsPipelines` **inside the driver** (reported segfaults in RADV and other implementations) rather than returning a clean `VkResult` error — and Vulkan validation layers do not catch every case that later crashes the driver, so "validation layers were clean" is not sufficient proof the SPIR-V was safe to hand to the GPU.

**Why it happens:**
It's natural to assume "the shader compiler already checked this" or "the validation layers will catch anything bad," but neither claim holds for all malformed inputs — and the schema's existing `"spirv"` shader-type option means a compile-time-safe path (GLSL → glslang → SPIR-V) can be bypassed by a job that supplies SPIR-V directly, whether accidentally or adversarially. This is a distributed compute node executing job-supplied code; robustness here isn't optional.

**How to avoid:**
- Run `spirv-val` (from `SPIRV-Tools`, MIT-family license, would need to be vendored alongside the GLSL compiler toolchain) as an explicit, separate gate on the final SPIR-V bytes — whether they came from compiling job-supplied GLSL or were supplied directly as `"spirv"` — before ever calling `vkCreateShaderModule`. Treat `spirv-val` failure as a normal job-rejection path (return an error result), not something that should ever reach the driver.
- Decide explicitly, as part of the schema-validation work in `CheckProcessValidity()`, whether the render `PassType` accepts `shader_config.type: "spirv"` at all this milestone, given the stated design intent is GLSL-authored shaders compiled via glslang/shaderc. If `"spirv"` is accepted, `spirv-val` is mandatory, not optional, for that path specifically. If it is rejected for render passes, that must be an explicit validation-schema decision (a one-line `if (type == spirv) reject`), not an assumption based on "we only document GLSL usage."
- Wrap `glslang`/`shaderc` compilation calls defensively (known crash class in the linker pass on malformed input) — do not assume compiler-side errors always come back as a return code rather than a process crash; treat compilation as untrusted-input handling, matching the SPIR-V-validation posture.

**Warning signs:**
A render job with `shader_config.type: "spirv"` accepted and passed to `vkCreateShaderModule` with no `spirv-val` call anywhere in the code path; a malformed shader test case that crashes the process instead of returning a job-rejection error; validation layers reporting no errors on a shader that still crashes a specific driver.

**Phase to address:** Schema extension phase (decide and encode the `"spirv"`-type acceptance/rejection rule for render passes) and `RenderProcessor` implementation (wire `spirv-val` as a mandatory pre-pipeline-creation gate). This is an early-architecture decision — retrofitting validation after `vkCreateShaderModule` call sites already exist without it is a straightforward but easy-to-forget follow-up if not designed in from the start.

---

### Pitfall 7: Manual (non-VMA) memory allocation exhausts `maxMemoryAllocationCount` or wastes alignment padding — even for a short-lived, submit-once workload

**What goes wrong:**
Without VMA, the naive approach — one `vkAllocateMemory` call per buffer/image (render target, vertex buffer, index buffer, staging/readback buffer) — hits `maxMemoryAllocationCount` surprisingly fast; some GPUs/drivers cap live allocations as low as 4096. This matters differently for a submit-once batch job than for a long-running renderer: a single job's own allocation count is small and safe, but a **node process that runs many render jobs over its lifetime** will accumulate live allocations if each job's resources aren't freed (or a pooled/reused allocation strategy isn't used) before the next job starts — the risk is cumulative across the node's uptime, not necessarily within one job. Separately, manually packing multiple resource types (e.g. render target image + vertex/index buffers) into a single suballocated memory block without respecting `bufferImageGranularity` alignment requirements between buffer and image resources sharing a block can produce driver-defined-behavior corruption (image and buffer granularity requirements differ and must not overlap incorrectly) — a mistake fragmentation-focused advice doesn't always flag because it's an alignment/correctness issue, not a space-efficiency one.

**Why it happens:**
VMA exists specifically to hide `maxMemoryAllocationCount` and `bufferImageGranularity` correctly; without it, both constraints are easy to satisfy accidentally for a single small job (masking the problem in early testing) while still being wrong in general, and only surfacing once the node has processed enough jobs or once a specific buffer/image combination triggers the granularity edge case.

**How to avoid:**
- Explicitly free (`vkFreeMemory`)/reset all per-job allocations at job completion, or maintain a small fixed-size pool of pre-sized allocations reused across jobs, rather than allocating fresh per job and trusting cleanup always runs (it must run even on the job-rejection/error paths from Pitfall 6).
- Because this is a discrete, bounded-resource-count workload (a handful of buffers/images per render job, not thousands of draw calls' worth of resources like a real-time renderer), a hand-rolled allocator does not need VMA's full sophistication — a fixed small number of memory blocks (one per required memory type: device-local for render target/vertex/index, host-visible for readback) sized generously enough for the largest expected job, with simple bump/reset suballocation reset at job boundaries, is sufficient and avoids both the allocation-count and fragmentation concerns without needing a general-purpose allocator.
- Explicitly query and respect `VkPhysicalDeviceLimits::bufferImageGranularity` when placing buffer and image suballocations adjacent to each other in a shared block — pad offsets to satisfy it rather than assuming natural resource-size alignment is sufficient.

**Warning signs:**
`VK_ERROR_TOO_MANY_OBJECTS` (the `maxMemoryAllocationCount` exhaustion error) appearing only after many render jobs have run on a long-lived node process, not on early/isolated test runs; intermittent corruption specifically in scenarios where a buffer and image share a suballocated block; allocation count monotonically increasing across a node's uptime in diagnostic logging (a good canary metric to add).

**Phase to address:** `RenderProcessor` implementation phase — design the allocation strategy (pool/reuse, not per-job `vkAllocateMemory`) from the start. Verify via a soak test that runs many sequential render jobs on one node process and confirms allocation count stays bounded rather than growing.

---

### Pitfall 8: Reintroducing the exact `pass.get_model().value()`-shaped crash for new render-specific optional schema fields

**What goes wrong:**
The milestone explicitly fixes the known `pass.get_model().value()` unconditional-unwrap crash in `ParseBlockSize()` for render/compute passes with no `model`. But the new render-specific fields (render target/framebuffer config, vertex/index buffer bindings, multi-stage shader pipeline) are new `boost::optional<T>`-returning generated accessors following the exact same quicktype pattern that produced the original bug. Any new shared/generic code path (one that receives a generic `Pass&` and doesn't already switch on `pass.get_type()` first) that calls `.value()` on a render-specific optional field will crash identically for a different field, the first time a non-render pass reaches that code.

**Why it happens:**
The generated `get_X()` accessors returning `boost::optional<T>` look like ordinary, safe accessor usage at a glance — the crash only manifests when a pass of a *different* `PassType` reaches code written assuming a specific `PassType`'s fields are always present. This is the same bug shape already found once in this exact schema.

**How to avoid:**
Apply the type-guard pattern the `ParseBlockSize()` fix establishes to every new render-specific field accessor: any function operating on a generic `Pass&` must not call `.value()` on a render-specific optional unless it has already confirmed `pass.get_type() == PassType::RENDER` (or is already inside a `case PassType::RENDER:` branch). Add this as an explicit code-review checklist item for the `RenderProcessor` implementation and `PassType` dispatch plumbing work, not scoped only to the one named `ParseBlockSize()` fix.

**Warning signs:**
Any `.value()` call (vs. `if (opt) {...}`/`opt.value_or(...)`) on a render-specific optional field in code that isn't already inside a `case PassType::RENDER:` branch or hasn't checked the type first; crashes on non-render passes after render fields are added to shared/generic code paths.

**Phase to address:** `RenderProcessor` implementation and `PassType` dispatch plumbing (where the type-guard pattern is established for the render case). Verify via a test that feeds a non-render pass through any function touching the new render-specific fields.

---

### Pitfall 9: CI having no real GPU is treated as "the render path can't be tested at all," when a meaningful slice can be exercised without hardware

**What goes wrong:**
Because the milestone has zero CPU/software-fallback tier *in the shipped product*, it's tempting to conclude the entire render path is untestable in CI (which currently has no GPU and no software Vulkan implementation at all). This both overclaims (a substantial portion of the pipeline — schema validation, GLSL→SPIR-V compilation, `spirv-val`, and even `VkPipeline` creation — needs no real GPU execution) and risks underclaims if someone reaches for a software rasterizer as a way to make full end-to-end tests "pass" in CI, which would quietly reintroduce a software-fallback code path into the product surface that the issue explicitly prohibits.

**Why it happens:**
"No fallback in the product" and "no GPU testing possible" get conflated, when they're actually orthogonal — one is a product-scope constraint on `RenderProcessor`'s runtime behavior, the other is a CI-infrastructure choice about what test doubles are acceptable *only inside test code*, never compiled into the shipped path.

**How to avoid:**
- Split test coverage into two explicit tiers: (1) **hardware-independent**, runnable on any CI runner today — schema/JSON validation, GLSL→SPIR-V compilation via glslang/shaderc, `spirv-val` validation, and even `VkInstance`/`VkPhysicalDevice`/`VkPipeline` creation *if* a software Vulkan implementation (Mesa Lavapipe/LLVMpipe, or Google SwiftShader) is installed on the CI runner purely as a **test-time Vulkan ICD substitute** — this is a CI environment choice (which ICD the loader finds), not a code change to `RenderProcessor`, and does not violate the "no CPU/software fallback tier" product constraint because no product code path selects or depends on a software renderer; (2) **hardware-dependent**, requiring a real GPU runner (self-hosted CI runner or a scheduled/manual job) — actual `vkQueueSubmit`+readback execution and the same-node repeat-run determinism test from Pitfall 5.
- Explicitly document, in the CI/build-wiring phase, that a software-Vulkan-ICD CI runner exercises pipeline *construction* correctness (shader compiles, layouts valid, pipeline creates) but its numerical output must never be treated as validating the same-node determinism guarantee (Pitfall 5) — that guarantee is about repeat runs on the *same real GPU/driver a node actually deploys on*, and software rasterizers do not have the same non-determinism profile as hardware ICDs, so passing on Lavapipe proves nothing about hardware repeat-run stability.

**Warning signs:**
CI is "green" on the render path with no real GPU runner in the workflow and no explicit note about what's actually being covered; a PR review can't tell from CI status alone whether real end-to-end GPU execution ever ran; someone proposes adding a runtime software-rasterizer fallback "to make tests pass" rather than treating it as a CI-only test double.

**Phase to address:** Cross-platform build wiring / CI phase — explicitly provision a software Vulkan ICD (Lavapipe or SwiftShader) for the hardware-independent CI tier, and separately provision (or explicitly schedule as manual/best-effort) a real-GPU runner for the hardware-dependent tier. This should be decided early enough that the `RenderProcessor` implementation phase's own test suite is written against both tiers from the start, not retrofitted.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|-----------------|-----------------|
| Leave `mnn_vulkan_mutex` as-is (function-local static) and add a separate, uncoordinated lock just for the renderer | Fast, isolated change, zero risk of touching MNN processor files | Reintroduces the exact concurrent-Vulkan-init hazard MNN's mutex exists to prevent, just at a new boundary (Pitfall 1) | Never — this is the one shortcut that directly undoes an existing, documented safety fix |
| Skip vendoring `Vulkan-ValidationLayers`, rely on developer-machine SDK installs for validation | No new submodule/CMake work, no CI runner changes | Validation silently absent in CI and on any clean checkout; false confidence in "debug build tested it" (Pitfall 3) | Acceptable short-term only if explicitly documented as a known gap with a follow-up item, never left implicit |
| Skip `spirv-val` because "the compiler already validated it" or "validation layers will catch bad shaders" | Less code, faster to first working demo | Driver crashes on malformed/adversarial SPIR-V, especially via the schema's existing `"spirv"` direct-input path (Pitfall 6) — this is job-supplied code on a distributed compute node | Never — this is a robustness requirement, not an optimization |
| One `vkAllocateMemory` per resource, no pooling/reuse across jobs | Simplest possible allocation code, fine in a single-job smoke test | `maxMemoryAllocationCount` exhaustion on a long-lived node processing many jobs (Pitfall 7) | Acceptable only for an initial single-job proof-of-concept explicitly not intended to run unattended for many jobs |
| Test the render path only on one developer's GPU/OS before calling it "verified" | Fastest path to a demo | Misses same-node repeat-run non-determinism (Pitfall 5) that only shows up across many repeat runs, and misses MoltenVK-specific issues (Pitfall 4) with zero macOS coverage | Never — the milestone's own acceptance criterion (deterministic repeatable hash) requires an explicit repeat-run test, and macOS is an explicit target platform |
| Reach for a software rasterizer (Lavapipe/SwiftShader) to make CI "fully green" including numerical output checks | Simpler CI, no self-hosted GPU runner needed | Either quietly violates the no-software-fallback product constraint (if wired into product code) or gives false confidence that hardware determinism holds (if used to validate Pitfall 5's guarantee) | Acceptable only as a CI-only test double for pipeline/compile-time correctness (Pitfall 9), never for validating numerical/hash output |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|-------------------|
| Vulkan (existing `find_package(Vulkan)`/`Vulkan::Vulkan` target) | Adding a second `find_package(Vulkan)` call or a second vendored loader/headers submodule for the new render code "to keep it self-contained" | Reuse the single existing `Vulkan::Vulkan` CMake target already linked in `SGProcessingManager/src/processors/CMakeLists.txt` — one loader, one set of headers, shared by MNN's Vulkan backend and the new renderer |
| GLSL→SPIR-V toolchain (glslang/shaderc — not yet vendored) | Vendoring a toolchain that also pulls in its own Vulkan headers/loader copy, or a GPL-licensed dependency transitively (rendering/shader toolchains sometimes pull in non-permissive dependencies deeper in their tree) | Vet glslang/shaderc/SPIRV-Tools specifically for license (all are permissive — check transitive deps too) and for not vendoring a second Vulkan ABI; add via the existing `thirdparty/` git-submodule + `CommonBuildParameters.cmake` `find_package(... CONFIG REQUIRED)` convention, matching every other library in that file |
| MoltenVK (Apple) | Assuming the render path works "for free" on Apple because MNN's Vulkan-via-MoltenVK path already works — MNN's usage never creates a swapchain or touches WSI, so it never exercised MoltenVK's weaker surface areas | Explicitly build *and run* (not just compile) the render path on macOS as part of cross-platform build wiring — CI currently only installs Vulkan deps on Linux runners, so macOS behavior has zero CI signal today |
| CI (GitHub Actions, Linux runners) | Assuming `libvulkan-dev` alone is sufficient the way it's been for MNN's silently-CPU-falling-back usage | Explicitly install a software Vulkan ICD (Lavapipe/`mesa-vulkan-drivers` or SwiftShader) for the hardware-independent CI tier only (Pitfall 9); provision a real-GPU runner separately for hardware-dependent determinism tests |
| Schema (`gnus-processing-schema.json` / generated headers, never hand-edited) | Assuming the `"spirv"` shader-type value is dead/unused because the design intent is GLSL-authored shaders, and skipping validation work for it | Explicitly decide and encode (in `CheckProcessValidity()`) whether render passes accept `shader_config.type: "spirv"` at all this milestone; if accepted, `spirv-val` is mandatory on that path (Pitfall 6) |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Creating a new `VkInstance`/`VkDevice` per render job (mirroring naive per-call patterns already seen in MNN processors) | Render job latency dominated by instance/device setup rather than actual GPU work; the shared init-mutex (Pitfall 1) becomes a serialization bottleneck under concurrent job load | Create the render `VkInstance`/`VkDevice`/`VkQueue` once per node process (or pooled), not per job — only per-job-create cheap objects (command buffers, framebuffers, the specific output target) | Visible as soon as concurrent render jobs are processed on one node — the mutex around device creation turns every job into a serialized bottleneck if creation happens per-job |
| Synchronous host readback (`vkMapMemory` + `vkDeviceWaitIdle`) after every render pass | Render throughput far below GPU capability; a node appears "slow" specifically on render jobs vs. inference jobs | Use a `VkFence`-gated readback (submit, wait on fence, then map) rather than a blocking device-wide wait-idle after every single job | Matters once render jobs are a meaningful fraction of a node's total workload, not for a single-pass proof-of-concept |
| One `vkAllocateMemory` per resource per job, never pooled (see Pitfall 7) | Allocation count grows across node uptime; eventual `VK_ERROR_TOO_MANY_OBJECTS` | Fixed small pool of pre-sized memory blocks reused/reset across jobs | Breaks once enough jobs accumulate on a long-lived node process — timeline depends on the device's `maxMemoryAllocationCount`, as low as 4096 on some GPUs |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Accepting job-supplied shader source or raw SPIR-V (`shader_config.type: "spirv"`, already a valid schema value) without a `spirv-val` gate before `vkCreateShaderModule` | Malformed or adversarially-crafted SPIR-V can crash the node's Vulkan driver (documented driver crashes on invalid SPIR-V in multiple ICDs) or, worst case, exploit a driver vulnerability — this is a distributed compute node executing job-supplied code from potentially untrusted sources | Validate all SPIR-V (whether compiled from job-supplied GLSL or supplied directly) with `spirv-val` before it ever reaches `vkCreateShaderModule`; treat validation failure as a normal job-rejection path, not a crash (Pitfall 6) |
| Treating render-pass output hash as consensus-equivalent to the MNN tensor-hash convention without confirming the comparison model matches this milestone's narrowed same-node scope | If render output is ever compared across nodes downstream (even though this milestone scopes verification to same-node repeatability), an implicit assumption that render hashes behave like MNN tensor hashes could silently reintroduce the cross-vendor non-determinism problem this milestone deliberately deferred | Explicitly document, wherever the render-pass hash is consumed, that it is validated for same-node repeat-run stability only this milestone — do not let a downstream consumer assume cross-node comparability without a separate, later decision |

## "Looks Done But Isn't" Checklist

- [ ] **Vulkan context setup:** Often missing a *shared, header-declared* init-time lock between the new renderer and MNN's Vulkan backend — verify it's not just a second isolated mutex sitting next to `mnn_vulkan_mutex` (Pitfall 1).
- [ ] **Device selection:** Often "works" on a single-GPU dev machine while implicitly relying on `vkEnumeratePhysicalDevices` index 0 — verify an explicit scoring/selection function exists and is tested on (or at least reasoned about for) a multi-GPU machine (Pitfall 2).
- [ ] **Headless rendering:** Often "works on the developer's machine" while secretly still creating a `VkSurfaceKHR`/swapchain somewhere in copied sample code — grep the new render code for `Swapchain`/`SurfaceKHR` and confirm zero WSI calls (Pitfall 4).
- [ ] **Determinism / hash verification:** Often verified only via "ran it twice on my machine, hashes matched once" — verify with an explicit N-repeat-run same-node test (N ≥ 10, not 2) asserting identical hash every time, including a cold-process-start case (Pitfall 5).
- [ ] **Shader validation:** Often the `CheckProcessValidity()` render case looks "done" once schema fields are checked, but is still missing (a) the `spirv-val` gate before `vkCreateShaderModule`, and (b) an explicit accept/reject decision for `shader_config.type: "spirv"` direct input (Pitfall 6).
- [ ] **Memory allocation:** Often "works" in a single-job test while silently allocating fresh per job — verify a soak test running many sequential jobs shows bounded (not growing) live allocation count (Pitfall 7).
- [ ] **New render-specific schema fields:** Often the one named `ParseBlockSize()` fix is applied but the same `.value()`-on-unchecked-`boost::optional` pattern is reintroduced for new render fields elsewhere — grep for `.value()` calls on render-specific accessors outside `case PassType::RENDER:` blocks (Pitfall 8).
- [ ] **CI coverage:** Often "green in CI" only because CI silently has no real GPU and no software Vulkan ICD at all — verify CI is exercising at least the hardware-independent tier (compile + `spirv-val` + pipeline creation via a software ICD), and that a real-GPU tier exists somewhere (even if manual/scheduled) for the determinism test (Pitfall 9).
- [ ] **Cross-platform build wiring:** Often verified only via a successful *compile* on macOS, not an actual *run* — verify the render path is executed (not just built) on a MoltenVK target at least once (Pitfall 4).

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|----------------|-----------------|
| Shared init-lock missing (Pitfall 1) discovered post-ship via intermittent crash reports | LOW | Introduce the header-declared `VulkanInitGuard` singleton, migrate the existing `mnn_vulkan_mutex` call site and the renderer's context-creation call site to acquire it; no schema/wire-format changes needed, purely an internal synchronization fix |
| `spirv-val` gate missing (Pitfall 6) discovered after render passes are already accepting shader input in production | LOW-MEDIUM | Add the `spirv-val` call at the existing `vkCreateShaderModule` call site (mechanical, localized change); audit any already-accepted jobs that used `shader_config.type: "spirv"` directly for retroactive validation |
| Same-node non-determinism (Pitfall 5) discovered after `RenderProcessor` is already in use | MEDIUM | Root-cause via the specific mechanisms in Pitfall 5 (check for `DONT_CARE` loads on hashed regions first — the most common culprit — then submission ordering, then pipeline-cache policy); fixes are typically localized to buffer-initialization and reduction-order code, not architectural, if caught before the render `PassType` is relied upon for consensus-adjacent behavior |
| CI has no real Vulkan device/ICD signal (grounding fact) discovered late | LOW-MEDIUM | Add Lavapipe or SwiftShader to the Linux CI job for the hardware-independent tier; both are apt-installable/vendorable with no product code changes; provision a real-GPU runner (self-hosted or scheduled) separately for the determinism tier |
| Allocation-count exhaustion (Pitfall 7) discovered in a long-running node deployment | MEDIUM | Retrofit a pooled/reset allocation strategy at job boundaries; requires touching every `vkAllocateMemory` call site in the render path but no schema/wire-format changes |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|-------------------|---------------|
| MNN-vs-render Vulkan init race (Pitfall 1) | Vulkan context setup (early architecture) | Stress test: construct render context and trigger MNN Vulkan inference concurrently from multiple threads, repeated runs, confirm no crash/hang |
| Uncoordinated device selection (Pitfall 2) | Vulkan context setup (early architecture) | Explicit scoring function exists and is reasoned about/tested against multi-GPU hardware if available |
| Missing validation layers / global loader env vars (Pitfall 3) | Vulkan context setup (early architecture) | Written VVL vendoring decision exists; if vendored, confirm `VK_LAYER_KHRONOS_validation` actually loads in a debug build via a deliberate test error |
| Reflexive surface/swapchain usage, MoltenVK headless gaps (Pitfall 4) | Vulkan context setup / `RenderProcessor` implementation (early architecture) → verified in cross-platform build wiring (later hardening) | Grep confirms zero `SurfaceKHR`/`SwapchainKHR` calls; actual (not just compiled) run on a MoltenVK/macOS target |
| Same-node repeat-run non-determinism (Pitfall 5) | Schema extension / `RenderProcessor` implementation design (early architecture) → verified in end-to-end verification (later hardening) | N-repeat-run (N ≥ 10) identical-job test on one node asserts identical hash every time, including a cold-start case |
| Unvalidated job-supplied shader/SPIR-V (Pitfall 6) | Schema extension (accept/reject `"spirv"` decision) + `RenderProcessor` implementation (`spirv-val` gate) (early architecture) | Malformed-shader and malformed-SPIR-V test cases confirm job-rejection, not crash |
| Manual allocation exhaustion/misalignment (Pitfall 7) | `RenderProcessor` implementation (early architecture — allocation strategy) | Soak test: many sequential jobs on one node, confirm bounded live-allocation count |
| `.value()` crash pattern reintroduced for render fields (Pitfall 8) | `RenderProcessor` implementation / `PassType` dispatch plumbing (early architecture) | Test feeds a non-render pass through any function touching new render-specific fields, confirms no crash |
| CI has no real GPU signal (Pitfall 9) | Cross-platform build wiring / CI (later hardening) | CI log shows hardware-independent tier passing (compile + `spirv-val` + pipeline creation via software ICD) and a documented real-GPU tier (even if manual/scheduled) exists for the determinism test |

## Sources

**Direct repository reads (HIGH confidence, curated/primary source — re-verified 2026-07-29):** `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_image.cpp`, `_string.cpp`, `_volume.cpp`; `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp`; `SuperGenius/SGProcessingManager/generated/ShaderType.hpp`; `SuperGenius/SGProcessingManager/gnus-processing-schema.json`; `SuperGenius/SGProcessingManager/src/processors/CMakeLists.txt`; `SuperGenius/.github/workflows/cmake.yml`; `thirdparty/Vulkan-Headers`, `thirdparty/Vulkan-Loader`, `thirdparty/MoltenVK` (confirmed present, no `Vulkan-ValidationLayers`/glslang/shaderc/SPIRV-Tools vendored); `.planning/PROJECT.md` (sgproc-render workstream section); prior archived research at `.planning/milestones/ws-sgproc-render-2026-07-29/research/PITFALLS.md` (bgfx-based attempt — Vulkan-coexistence-layer findings carried forward and re-verified, bgfx-specific content dropped, determinism scope narrowed to same-node per current milestone's explicit constraint).

**Web search (MEDIUM confidence, cross-checked across multiple independent sources per topic):**
- [Vulkan-Loader LoaderInterfaceArchitecture.md](https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderInterfaceArchitecture.md) — loader global state / multi-instance behavior
- [Vulkan debugging chapter, Vulkan Documentation Project](https://docs.vulkan.org/spec/latest/chapters/debugging.html) — multiple debug messengers per process
- [VK_EXT_headless_surface, Khronos Registry](https://registry.khronos.org/vulkan/specs/1.3-extensions/man/html/VK_EXT_headless_surface.html) — headless surface still depends on VK_KHR_surface
- [MoltenVK issue #2049 (headless_surface support request)](https://github.com/KhronosGroup/MoltenVK/issues/2049), [MoltenVK issue #908 (headless black images)](https://github.com/KhronosGroup/MoltenVK/issues/908), [MoltenVK issue #836 (headless compute freeze)](https://github.com/KhronosGroup/MoltenVK/issues/836)
- [Impacts of floating-point non-associativity on reproducibility, arXiv](https://arxiv.org/pdf/2408.05148) — GPU parallel-reduction determinism
- [VMA debugging incorrect memory usage docs](https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/debugging_memory_usage.html) — uninitialized-memory debug pattern (0xDCDCDCDC fill)
- [glslang issue #590](https://github.com/KhronosGroup/glslang/issues/590) — compiler crash on malformed input
- [wgpu issue #7198 (pipeline creation crash from invalid SPIR-V)](https://github.com/gfx-rs/wgpu/issues/7198); AMD/NVIDIA developer-forum threads on driver crashes from invalid SPIR-V in `vkCreateGraphicsPipelines`
- [Vulkan Memory Allocator usage patterns / Khronos Vulkanised 2018 memory management slides](https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/usage_patterns.html) — `maxMemoryAllocationCount`, suballocation, fragmentation
- [install-vulkan-sdk-action / jakoch/rasterizers](https://github.com/marketplace/actions/install-vulkan-sdk-and-runtime), [Vulkan CI/CD tutorial page](https://docs.vulkan.org/tutorial/latest/Building_a_Simple_Engine/Tooling/02_cicd.html) — Lavapipe/SwiftShader for headless CI
- [Vulkan-Loader issue #153 (device enumeration ordering)](https://github.com/KhronosGroup/Vulkan-Loader/issues/153), [vulkan-tutorial.com physical device selection](https://vulkan-tutorial.com/Drawing_a_triangle/Setup/Physical_devices_and_queue_families) — device selection stability
- [shaderc / glslc README, google/shaderc](https://github.com/google/shaderc) — offline shader compilation without a GPU driver

---
*Pitfalls research for: hand-rolled headless Vulkan render pass execution in SGProcessingManager (sgproc-render v1.0 restart)*
*Researched: 2026-07-29*
