# Pitfalls Research: Headless Vulkan Rendering alongside MNN-Vulkan Inference in SGProcessingManager

**Domain:** Adding a second, independent Vulkan rendering context to a distributed-compute node process that already uses Vulkan internally via MNN inference
**Researched:** 2026-07-28
**Confidence:** HIGH for repo-grounded findings (direct source read); MEDIUM for general Vulkan/MoltenVK ecosystem findings (web search, cross-checked against multiple sources); explicitly marked per pitfall below.

## Grounding facts (from this repo, not general Vulkan knowledge)

- MNN's Vulkan backend is invoked via `MNN::ScheduleConfig.type = MNN_FORWARD_VULKAN` in 3 of 17 processors (`processing_processor_mnn_image.cpp`, `_string.cpp`, `_volume.cpp`). MNN owns `VkInstance`/`VkDevice`/`VkQueue` internally — nothing is exposed to callers.
- `processing_processor_mnn_image.cpp:114-115` already guards MNN Vulkan init with a **process-wide** `static std::mutex mnn_vulkan_mutex` (function-local static, so `_string.cpp`/`_volume.cpp` do NOT share this same mutex instance — each TU's Vulkan-backend `createSession` call is unguarded relative to the others). Comment explicitly says this is a workaround "until MNN exposes a shareable runtime/session API."
- `thirdparty/` vendors only `Vulkan-Headers` (v1.3.302) and `Vulkan-Loader` (v1.3.302) — **no `Vulkan-ValidationLayers`/VVL submodule is vendored**. Validation layers are only available if the *system* has a Vulkan SDK installed with `VK_LAYER_KHRONOS_validation` registered; the repo's own `VULKAN_SDK` fallback (`CommonBuildParameters.cmake:254-255`, `SGProcessingManager/cmake/CommonBuildParameters.cmake:39-40`) points at the vendored **loader only**, which ships no layers.
- CI (`SuperGenius/.github/workflows/cmake.yml:520`, `build-release-tags.yml:365`) installs only `libvulkan-dev` on Linux runners — the loader dev package, not `mesa-vulkan-drivers`, not `vulkan-validationlayers-dev`, not any software rasterizer (lavapipe/SwiftShader). GitHub-hosted Linux runners have no GPU. There is currently no `SGProcessingManager` test suite at all (no `test/` directory found), so there is no existing precedent in this repo for how Vulkan-backend code behaves in CI. MNN's Vulkan backend is known to silently fall back to CPU forward-type when Vulkan device init fails (it does not hard-error) — this has likely been masking the CI GPU gap for the existing 3 MNN Vulkan processors. A raw Vulkan renderer with no MNN-style fallback will **hard-fail** `vkCreateInstance`/`vkEnumeratePhysicalDevices` in this exact CI environment where MNN silently degraded.
- `SGProcessingManager/src/processors/CMakeLists.txt:57-58` already links `MNN::MNN` and `Vulkan::Vulkan` directly in this target — a `Vulkan::Vulkan` CMake target already exists in scope for this library. A new render capability does not need (and must not add) a second `find_package(Vulkan)`/vendored loader.
- Apple platforms already link MoltenVK (`build/OSX/CMakeLists.txt:31`, `build/iOS/CMakeLists.txt:34`) as a static `.xcframework`, with `Vulkan_LIBRARY` pointed directly at it, plus Apple frameworks (CoreFoundation, CoreGraphics, CoreServices, IOKit, IOSurface, Metal, QuartzCore, AppKit/UIKit) linked in `src/processing/CMakeLists.txt`.
- The schema (`generated/ShaderType.hpp`) already defines `ShaderType` as `glsl | hlsl | metal | spirv` — i.e. the schema *can* express platform-native shader source (Metal Shading Language, HLSL) as an alternative to SPIR-V, which is a determinism trap (see Pitfall 6).
- `PassType::RENDER` is fully unimplemented — `CheckProcessValidity()` (`ProcessingManager.cpp:151-152`) has an empty `case PassType::RENDER: break;` with no field validation at all, and `Process()`'s dispatch is keyed entirely by input `DataType` via MNN processor factories, with no `PassType`-based branch anywhere.
- Output hashing already exists as a pattern: MNN processors compute `SHA256_DIGEST_LENGTH`-sized `sgprocmanagersha::sha256(...)` hashes over raw tensor bytes and chain them into a combined `subTaskResultHash` (`processing_processor_mnn_image.cpp:70-99`). The render path is expected to plug into this exact same hash-of-raw-output-bytes convention — meaning any non-bit-exact GPU output directly becomes a consensus-breaking hash mismatch.

---

## Critical Pitfalls

### Pitfall 1: Assuming MNN's Vulkan context can be reused or is safely isolated from the new renderer's context

**What goes wrong:**
A developer either (a) tries to obtain MNN's internal `VkInstance`/`VkDevice` to "save overhead" and share it with the renderer (impossible today — MNN exposes none of it, but someone may patch MNN or reach into private engine internals to get it), or (b) assumes that because MNN's Vulkan context and the renderer's Vulkan context are "independent," they can't interfere with each other. Both VkInstances still load the *same* system Vulkan loader/ICD and the same physical GPU, and Vulkan objects like the ICD's internal device-lock, GPU memory heaps, and (on validation-layer builds) the layer's per-process instance dispatch tables are process/driver global. Concurrently calling `vkCreateInstance`/`vkCreateDevice` from MNN's init path and the renderer's init path on the same GPU is the same class of hazard as the documented MNN-internal concurrency bug (Pitfall 2), just at a different boundary (MNN-vs-render instead of MNN-vs-MNN).

**Why it happens:**
The task narrative correctly says MNN's Vulkan use is fully encapsulated with "no VkInstance/VkDevice/VkQueue exposed anywhere" — but that description is about API surface, not about GPU/driver-level isolation. Vulkan contexts in the same process on the same GPU are not automatically thread- or resource-isolated just because the C++ objects are separate. This is easy to miss because "independent context" reads as "isolated," when it only means "separately-owned handles."

**How to avoid:**
Treat the renderer's Vulkan context as fully independent at the API level (own `VkInstance`, own `VkPhysicalDevice` selection, own `VkDevice`, own `VkQueue`) — do not attempt to obtain or share MNN's internal Vulkan handles even if a future MNN version exposes them, unless a dedicated design decision is made later with its own review. Serialize *creation* of both contexts (see Pitfall 2) even though they are logically independent, because `vkCreateInstance`/`vkCreateDevice` themselves are documented as not thread-safe with respect to concurrent instance/device creation in the same process for at least some ICDs (this is exactly why MNN needed its own mutex). Steady-state rendering/inference (post-creation, using separate `VkQueue`s) is fine to run concurrently — the risk is concentrated at instance/device *creation*, not steady-state submission.

**Warning signs:**
Intermittent `VK_ERROR_INITIALIZATION_FAILED` / `VK_ERROR_DEVICE_LOST` only under load or only on first-run-after-boot; crashes that only reproduce when a render pass and an MNN-Vulkan inference pass are scheduled close together in time; driver-specific crashes (NVIDIA vs AMD vs Mesa) that don't reproduce in isolation.

**Phase to address:** Vulkan context setup (own instance/device/queue creation code) — with a design note (not code sharing) cross-referenced against the MNN concurrency mutex during code review.

---

### Pitfall 2: New renderer's instance/device creation races with MNN's Vulkan init, defeating the existing `mnn_vulkan_mutex` workaround

**What goes wrong:**
The existing `mnn_vulkan_mutex` in `processing_processor_mnn_image.cpp` is a **function-local `static std::mutex`** — it is scoped to that one TU/function, not a process-wide singleton shared across `_string.cpp`/`_volume.cpp`/the new renderer. If the render pass and an MNN-Vulkan inference pass execute in different worker threads at roughly the same time (very plausible — `ProcessingManager` dispatches passes to be processed, and a distributed compute node processes many subtasks concurrently), the renderer's `vkCreateInstance`/`vkCreateDevice` call has zero mutual exclusion against MNN's `mnnNet->createSession(netConfig)` call with `MNN_FORWARD_VULKAN`. The known-unsafe MNN Vulkan concurrent-init bug is reintroduced at a new call site that the existing single-file mutex cannot protect.

**Why it happens:**
The mutex was scoped defensively for the one file it lives in, with an explicit comment acknowledging it's a stopgap. Nobody extending the codebase later has a natural reason to go find that mutex and reuse it — it's not exported, not documented outside a code comment, and lives in an MNN-specific processor file that a render-feature author has no reason to open.

**How to avoid:**
Introduce one process-wide, header-declared synchronization primitive (e.g. a `sgns::processing::VulkanInitGuard` singleton with a real header, not a function-local static) that both the existing MNN Vulkan processors and the new renderer's context-creation path acquire before doing *any* `vkCreateInstance`/`vkCreateDevice`/`vkEnumeratePhysicalDevices` call. Migrate the 3 existing MNN Vulkan call sites to use it (small, mechanical diff) rather than leaving the old mutex in place and adding a second, uncoordinated one for the renderer. Steady-state submission (`vkQueueSubmit`) after creation does not need this lock — only the init/create phase does.

**Warning signs:**
Rare, non-reproducible crashes or hangs specifically when render passes and inference passes are scheduled in overlapping time windows; crashes that vanish under a debugger or with `--gtest_repeat`-style serialized test runs (classic race-condition tell).

**Phase to address:** Vulkan context setup — must land before or alongside RenderProcessor implementation, since this is the phase that introduces the second concurrent init path. Verify with a stress test that runs render-pass and MNN-Vulkan-inference-pass construction concurrently from multiple threads (end-to-end verification test phase).

---

### Pitfall 3: Vulkan validation layers silently unavailable in this repo's build (no VVL vendored), giving false confidence in debug builds

**What goes wrong:**
A developer builds and tests locally with system-installed Vulkan SDK (which does have `VK_LAYER_KHRONOS_validation`), sees clean validation output, and ships. But `thirdparty/` only vendors `Vulkan-Headers`/`Vulkan-Loader` — no `Vulkan-ValidationLayers` submodule. Any teammate or CI runner that relies purely on the repo's vendored/fallback `VULKAN_SDK` path (`CommonBuildParameters.cmake:254-255`, pointed at `thirdparty/Vulkan-Loader`) gets a loader with zero layers registered — `vkCreateInstance` with `VK_LAYER_KHRONOS_validation` requested will simply fail to find the layer (or silently produce a warning depending on loader version), and API-misuse bugs (invalid usage, missing synchronization, resource lifetime errors) go completely undetected in that environment, right up until they manifest as GPU driver crashes on a machine with a different driver.

**Why it happens:**
Validation layers are conventionally assumed to "just be there" when Vulkan is installed via the LunarG SDK, but this repo deliberately vendors only the minimal loader/headers (permissive-license constraint — VVL itself is Apache-2.0 so it *could* be vendored, but currently isn't), and CI's `libvulkan-dev` apt package similarly provides only the loader, not `vulkan-validationlayers-dev`.

**How to avoid:**
Decide explicitly, as part of this milestone, whether to vendor `Vulkan-ValidationLayers` as a new `thirdparty/` submodule (it's Apache-2.0, satisfies the no-GPL constraint) gated behind `CMAKE_BUILD_TYPE STREQUAL "Debug"` (mirroring the existing `SGNS_DEBUGLOGS`/`DEBUG_BYTECODE_CIRCUITS` debug-only-define pattern already in `CommonBuildParameters.cmake:17-28`), or explicitly document that validation is a developer-machine-only, opt-in, non-CI practice. Do not assume "debug build" implies "validated build" in this repo without vendoring the layer.

**Warning signs:**
No validation errors ever surface in CI logs even when a known-bad synchronization bug is deliberately introduced during development testing (a good canary check); `vkCreateInstance` returning `VK_ERROR_LAYER_NOT_PRESENT` only in CI/clean-checkout builds, never on a developer's pre-configured machine.

**Phase to address:** Vulkan context setup phase should include an explicit, written decision (vendor VVL or not) rather than leaving it implicit. If deferred, cross-platform build wiring phase must still confirm CI does not silently assume validation ran.

---

### Pitfall 4: Headless render output is not deterministic across GPU vendors/drivers, breaking the hash-verification consensus model

**What goes wrong:**
The pipeline's entire verification model (per the grounding facts: `sha256`-over-raw-bytes, chained across subtasks) requires bit-exact output across heterogeneous distributed nodes. Vulkan the API is a thin, standardized cross-vendor interface, but it explicitly does **not** guarantee bit-identical floating-point results across different GPU vendors/drivers: IEEE-754 rounding-mode defaults, fused-multiply-add (FMA) contraction, transcendental-function (`sin`/`cos`/`exp`/etc.) implementations, and rasterization tie-breaking rules for primitive coverage are all vendor/driver-implementation-defined in the general case (this is a well-documented, cross-checked general Vulkan/GPU-compute finding — MEDIUM confidence, not GNUS-specific). A render pass that looks correct on the developer's NVIDIA card can produce a different hash on an AMD or Apple Silicon (MoltenVK) node, causing consensus/validation failures that have nothing to do with a logic bug.

**Why it happens:**
Rendering (unlike most inference workloads MNN already handles, which at least attempt determinism at the framework level for a given backend) fundamentally trades cross-hardware bit-exactness for performance — this is true of graphics APIs generally, and Vulkan does not opt out of it. The task's own framing ("a real risk if rendered output must be hash-verified/compared across distributed nodes with heterogeneous hardware") is correct, and it is the single highest-severity risk in this milestone because it can invalidate the entire consensus-adjacent verification design after everything else is built and works "correctly" per-node.

**How to avoid:**
Do not assume raw framebuffer bytes can be hashed and compared bit-for-bit across arbitrary nodes, the way MNN's tensor output currently is. Concrete mitigations, in order of preference: (1) constrain the render pass's shader math to operations known to be exactly reproducible on integer/fixed-point paths where the schema allows it (e.g., quantize final output to a coarser format before hashing, trading precision for cross-vendor stability); (2) require a canonical, single-toolchain SPIR-V compilation path (see Pitfall 6) so shader *semantics* are at least not divergent by construction, even though driver execution still isn't guaranteed bit-exact; (3) consider a tolerance-based comparison (e.g., perceptual/structural hash or an epsilon-bounded comparison over decoded pixel values) instead of a raw SHA-256 for the render output specifically, distinct from the exact-match hash used for MNN tensor output — this is a schema/consensus-design decision, not just an implementation detail, and should be flagged to whoever owns the consensus-validation design outside SGProcessingManager. Get an explicit answer to "does the render `PassType` use the same exact-hash consensus rule as inference, or a different one?" before implementing `RenderProcessor`.

**Warning signs:**
Render-pass proof-of-concept produces a stable hash on one dev machine/CI runner but a different hash when re-run on different hardware (test this explicitly — do not only test on one GPU); intermittent consensus/validation failures reported for render-type jobs specifically, correlated with which node executed them.

**Phase to address:** This must be resolved as a design decision during schema extension / PassType dispatch plumbing (before RenderProcessor implementation), not discovered during end-to-end verification. The end-to-end verification test phase must explicitly test cross-hardware or cross-driver (e.g. run same job against two different GPU vendors/software-vs-hardware backends) reproducibility, not just single-machine round-trip.

---

### Pitfall 5: MoltenVK headless/offscreen rendering assumed to work identically to native Vulkan without a swapchain

**What goes wrong:**
Standard Vulkan offscreen rendering (render directly to a `VkImage`/framebuffer with no `VkSwapchainKHR`, no `VkSurfaceKHR`) is a well-supported, native pattern on Linux/Windows ICDs. On MoltenVK (Apple), several surface/swapchain-adjacent Vulkan extensions historically required a real window-system surface or had quirks when no surface existed — MoltenVK only gained `VK_EXT_headless_surface` support relatively recently (Vulkan SDK ~1.3.275+), specifically to let apps create a `VkSurfaceKHR`/`VkSwapchainKHR` with a true no-op presentation for exactly this "no window, just copy the image out" use case (source: MoltenVK release notes / GitHub issue #2049, MEDIUM confidence). A developer who never creates a swapchain at all (true offscreen-to-`VkImage` rendering, no surface whatsoever) mostly sidesteps this — but if any part of the implementation reflexively reaches for a swapchain-based pattern (common in Vulkan sample code/tutorials, which are almost universally window-based), it will hit macOS/iOS-specific failures or be forced through `VK_EXT_headless_surface`, which was buggy in early MoltenVK releases (e.g. an incorrectly-returned `VK_SUBOPTIMAL_KHR`, per the same source).

**Why it happens:**
Most public Vulkan tutorials, sample code, and even much internal team experience is windowed-rendering-first; "headless" is the less-traveled path, and MoltenVK — being a Metal-translation shim rather than a native Vulkan ICD — has historically had gaps precisely in the window-system-integration (WSI) surface area, which is exactly where the headless/offscreen distinction lives.

**How to avoid:**
Design the renderer to never create a `VkSurfaceKHR`/`VkSwapchainKHR` at all: render to a plain `VkImage` (`VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT`) backing a `VkFramebuffer`, then `vkCmdCopyImageToBuffer` (or `vkMapMemory` on a linear-tiled staging image) to read pixels back on the host — this pattern is portable across MoltenVK, Linux Mesa, and Windows drivers with no WSI involvement whatsoever, and sidesteps the entire `VK_EXT_headless_surface` question. Only use `VK_EXT_headless_surface` if a future requirement genuinely needs swapchain semantics (e.g. multiple in-flight frames coordinated via present) — for a single deterministic render-and-read-back job, it isn't needed. If MoltenVK is used, pin to a MoltenVK/Vulkan-SDK version confirmed to have the headless-surface fixes if that path is ever used, and pay attention to MoltenVK's `MVK_CONFIG_*` environment-variable/API configuration surface which controls behaviors (e.g. synchronous queue submission, Metal argument buffer usage) that don't exist on native Vulkan ICDs.

**Warning signs:**
`vkCreateSwapchainKHR`/`vkCreateXlibSurfaceKHR`-style calls anywhere in the renderer's code (a design smell for a headless compute node); MoltenVK-specific validation warnings about surface/swapchain usage; behavior that only differs on macOS/iOS builds.

**Phase to address:** Vulkan context setup / RenderProcessor implementation — establish the "no swapchain, ever" invariant as a design constraint up front. Cross-platform build wiring phase should include an actual macOS/MoltenVK build+run of the render path in CI or a documented manual verification step (this repo's Vulkan-backend code has no evidence of ever being exercised on macOS CI — see grounding facts on `libvulkan-dev`-only Linux CI).

---

### Pitfall 6: Schema allows platform-native shader source (`metal`/`hlsl` `ShaderType` values), which reintroduces the determinism problem at the shader-authoring level

**What goes wrong:**
`generated/ShaderType.hpp` already defines `glsl | hlsl | metal | spirv`. If the schema/RenderProcessor implementation allows a render pass to specify `shader.type = "metal"` on Apple and a hand-written `"spirv"`/`"glsl"` equivalent elsewhere for the "same" render pass, these are not the same program — different compilers (Apple's Metal shader compiler vs `glslang`/`shaderc`/DXC) with different optimization behavior, different intrinsic implementations, and no guaranteed semantic equivalence. This is strictly worse than Pitfall 4 (driver-level FP differences on identical SPIR-V) because it adds compiler/toolchain divergence on top of driver divergence, for output that must still hash-match.

**Why it happens:**
The schema was presumably designed generally (any render/shader use case, not necessarily this consensus-hashing one), and `ShaderType` enumerating all four is a reasonable general-purpose graphics-schema choice that predates the render `PassType` actually being wired up for verifiable distributed execution.

**How to avoid:**
For this milestone, constrain the render `PassType` (via schema validation added in `CheckProcessValidity()`, not just documentation) to a single canonical shader representation across all platforms — SPIR-V is the correct choice, since it's the one format every target (native Vulkan Linux/Windows, MoltenVK on Apple) consumes through the same driver-level SPIR-V-to-native translation path already used by Vulkan itself. Reject (fail validation on) `metal`/`hlsl` `ShaderType` values for render passes specifically at this stage, even though the enum technically allows them — this is a deliberate narrowing, not a schema bug, and should be called out explicitly in the schema-extension phase's docs/comments so a future maintainer doesn't "helpfully" add native-shader support back in without revisiting the determinism implications.

**Warning signs:**
A render-pass definition validates successfully with `shader.type: "metal"` or `"hlsl"`; two render passes that are supposed to be equivalent across platforms produce different SPIR-V/bytecode because they were authored separately per-`ShaderType` rather than compiled from one source.

**Phase to address:** Schema extension phase (add the `ShaderType`-narrowing validation for render passes specifically) and PassType dispatch plumbing (`CheckProcessValidity()` render-case validation, replacing the current empty `break;`).

---

### Pitfall 7: `ParseBlockSize()`'s known `pass.get_model().value()` bug is fixed for render, but the same "assume inference-shaped fields" mistake gets reintroduced elsewhere in new render-specific code

**What goes wrong:**
The milestone explicitly calls out fixing the unconditional `pass.get_model().value()` crash in `ParseBlockSize()` for any render/compute pass. That's a known, named fix. But the render `PassType`'s new fields (render target/framebuffer config, vertex/index buffer bindings, multi-stage shader pipeline) are new `boost::optional<T>` schema fields, following the exact same pattern that produced the original bug (`.value()` called on an unchecked `boost::optional` from `Pass.hpp`-style generated accessors). Any new code path that reads render-specific fields without checking `has_value()`/using the guarded-access idiom the fix establishes will reintroduce the same crash class for a different field (e.g., `pass.get_render_target().value()` called from a code path that also handles compute/inference passes).

**Why it happens:**
The generated quicktype accessors (`get_X()` returning `boost::optional<T>`) make `.value()` look like normal, safe accessor usage at a glance — the crash only manifests when a pass of a *different* `PassType` reaches code written assuming a specific `PassType`'s fields are always present. This is exactly the shape of bug that was already found once in this exact schema (`ParseBlockSize`).

**How to avoid:**
Any function that receives a generic `Pass&`/`Pass` reference and doesn't already `switch` on `pass.get_type()` first must not call `.value()` on any `PassType`-specific optional field. Apply the same type-guard pattern the `ParseBlockSize()` fix establishes to every new render-specific field accessor, and add this as an explicit code-review checklist item for the RenderProcessor implementation phase, not just the one named `ParseBlockSize()` fix.

**Warning signs:**
Any `.value()` call (vs. `if (opt) { ... }`/`opt.value_or(...)`) on a render-specific optional field in code that isn't already inside a `case PassType::RENDER:` branch or hasn't validated the type first; crashes on non-render passes after render fields are added to shared/generic code paths.

**Phase to address:** RenderProcessor implementation phase (and PassType dispatch plumbing, where the type-guard pattern is established) — verify via a test that feeds a non-render pass through any function touching the new render fields.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|-----------------|-----------------|
| Reuse the existing exact-match SHA-256 hash chain for render output unchanged | No new consensus/verification code path needed | Cross-vendor GPU non-determinism (Pitfall 4) makes render passes unusable in a real heterogeneous-node network even though single-node tests pass | Never for production; acceptable only for an initial same-machine/same-GPU proof-of-concept explicitly scoped as such |
| Leave `mnn_vulkan_mutex` as-is (function-local static) and add a separate, uncoordinated lock just for the renderer | Fast, isolated change with no risk of touching MNN processor files | Reintroduces the exact concurrent-Vulkan-init hazard MNN's mutex exists to prevent, just at a new boundary (Pitfall 2) | Never — this is the one shortcut that directly undoes an existing, documented safety fix |
| Skip vendoring `Vulkan-ValidationLayers`, rely on developer-machine SDK installs for validation | No new submodule/CMake work, no CI runner changes | Validation silently absent in CI and on any clean checkout; false confidence in "debug build tested it" (Pitfall 3) | Acceptable short-term if explicitly documented as a known gap, with a follow-up item to vendor VVL before render is trusted in production consensus paths |
| Allow `ShaderType` to remain unconstrained (`metal`/`hlsl` accepted for render passes) to avoid extra schema validation work | Less validation code, more schema flexibility | Determinism failures at the shader-authoring level that are hard to root-cause later (Pitfall 6) | Never for the consensus/hash-verified render path; fine for any future non-verified/local-only rendering use case, if one is ever added |
| Test the render path only on one developer's GPU/OS before calling it "end-to-end verified" | Fastest path to a demo | Ships a feature whose core value proposition (cross-node verifiable render) is untested on the actual heterogeneous hardware it must work across | Never — the milestone's own success criterion (hash-verified output across nodes) requires at least a two-different-GPU-vendor (or hardware-vs-software-renderer) test |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|-------------------|
| Vulkan (existing `find_package(Vulkan)`/`Vulkan::Vulkan` target) | Adding a second `find_package(Vulkan)` call or a second vendored Vulkan loader/headers submodule for the new render library "to keep it self-contained" | Reuse the single existing `Vulkan::Vulkan` CMake target already established in `CommonBuildParameters.cmake`/`SGProcessingManager/cmake/CommonBuildParameters.cmake` and already linked in `src/processors/CMakeLists.txt` — one loader, one set of headers, shared by MNN's Vulkan backend and the new renderer |
| New Vulkan rendering third-party library (git submodule under `thirdparty/`) | Picking a library that statically links or vendors its own copy of Vulkan headers/loader internally (common in "batteries included" rendering frameworks), creating a second, divergent Vulkan ABI/version in the same binary | Vet the candidate library specifically for "uses caller-provided `Vulkan::Vulkan`/system loader" vs. "vendors its own Vulkan" before selecting it; confirm license is non-GPL/AGPL per the hard constraint (check the library's own dependency tree, not just its own top-level license, since rendering libs often pull in GPL-licensed shader-compiler or model-loading dependencies transitively) |
| MoltenVK (Apple) | Assuming the render path works "for free" on Apple because MNN's Vulkan-via-MoltenVK path already works — MNN's usage never creates a swapchain or does WSI-adjacent work, so it never exercised MoltenVK's weaker surface areas | Explicitly build and run (not just compile) the render path on macOS/iOS as part of cross-platform build wiring, not just Linux/Windows — this repo's CI currently only installs Vulkan deps on Linux runners, so macOS Vulkan-backend behavior has no CI signal today |
| CMake / git submodule vendoring convention | Vendoring the new render library via a raw `add_subdirectory`/`FetchContent` instead of the repo's `.gitmodules`-based `thirdparty/` submodule + `find_package(... CONFIG REQUIRED)` convention documented in `ThirdParty_Libraries_Integration.md` | Add it as a `git submodule` under `thirdparty/`, wire an entry into `CommonBuildParameters.cmake`/`SGProcessingManager/cmake/CommonBuildParameters.cmake` following the existing `${_THIRDPARTY_BUILD_DIR}/<lib>/...` + `find_package(<Lib> CONFIG REQUIRED)` pattern used for every other library in that file, and add the library to `ThirdParty_Libraries_Integration.md`'s table |
| CI (GitHub Actions, Linux runners) | Assuming `libvulkan-dev` is sufficient for the render path the way it (apparently) has been for MNN's silently-CPU-falling-back Vulkan usage | Explicitly install/provide a software Vulkan implementation for CI (e.g. Mesa's `lavapipe`/`llvmpipe` via `mesa-vulkan-drivers`, or Google's SwiftShader) so `vkEnumeratePhysicalDevices` returns at least one usable device on GPU-less CI runners — without this, the end-to-end verification test cannot run in CI at all, only locally on a dev machine with a real GPU |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Creating a new `VkInstance`/`VkDevice` per render subtask (mirroring naive `mnnNet->createSession` per-call patterns already seen in MNN processors) | Render subtask latency dominated by instance/device setup rather than actual GPU work; the shared init-mutex (Pitfall 2) becomes a serialization bottleneck under load | Create the render `VkInstance`/`VkDevice`/`VkQueue` once per node process (or pooled), not per subtask; only per-subtask-create the cheap objects (command buffers, framebuffers, the specific `VkImage` output target) | Becomes visible as soon as concurrent render subtasks are processed on one node — the mutex around device creation (necessary per Pitfall 2) turns every subtask into a serialized bottleneck if creation happens per-subtask |
| Synchronous host readback (`vkMapMemory` + wait-idle) after every render pass | Render throughput far below GPU compute capability; node appears "slow" specifically on render passes vs. inference passes | Use a `VkFence`-gated async readback (submit, do other work, wait on fence, then map) rather than a blocking `vkDeviceWaitIdle` after every single pass | Matters once render passes are a meaningful fraction of a node's total workload, not for a single-pass proof-of-concept |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Trusting the hash of GPU render output as consensus-equivalent to the existing MNN tensor-hash convention without re-litigating the trust model | A malicious or simply divergent-hardware node produces a "different but not wrong" hash for a render pass, and the consensus/validation logic (outside SGProcessingManager) either wrongly flags an honest node as faulty, or — worse — accepts divergent outputs as valid because the mismatch is expected/tolerated, silently weakening the verification guarantee for render passes specifically | Explicitly scope, with whoever owns the consensus-validation logic, whether render `PassType` output uses the same strict-equality hash rule as inference, or a distinct tolerance-based rule (see Pitfall 4) — do not let this be decided implicitly by whatever `RenderProcessor` happens to implement |
| Accepting shader bytecode (SPIR-V) from schema/job input without validating it, and feeding it straight to `vkCreateShaderModule` | A malformed or adversarially-crafted SPIR-V module submitted as part of a job could crash the node's Vulkan driver (some ICDs are not robust to malformed SPIR-V) or, in the worst case, exploit a driver vulnerability — this is a distributed compute node executing job-supplied code | Validate SPIR-V with `SPIRV-Tools`' validator (`spirv-val`, Apache-2.0/MIT-family license, could be vendored alongside the render library) before passing it to `vkCreateShaderModule`, and treat shader-module creation failures as a normal job-rejection path, not a crash |

## "Looks Done But Isn't" Checklist

- [ ] **Vulkan context setup:** Often missing a *shared, header-declared* init-time lock between the new renderer and MNN's Vulkan backend — verify it's not just a second isolated mutex sitting next to `mnn_vulkan_mutex` (Pitfall 2).
- [ ] **Headless rendering:** Often "works on the developer's machine" while secretly still creating a `VkSurfaceKHR`/swapchain somewhere in copied sample code — verify with a grep for `Swapchain`/`SurfaceKHR` in the new render code and confirm zero WSI calls (Pitfall 5).
- [ ] **Determinism / hash verification:** Often verified only via "run it twice on my machine, hashes match" — verify by running the identical job against at least two different GPU vendors/backends (or hardware vs. a software rasterizer) and confirming (or explicitly documenting the expected divergence and tolerance model for) matching output (Pitfall 4).
- [ ] **Schema validation for render passes:** Often the `CheckProcessValidity()` render case looks "done" once it stops being an empty `break;`, but is still missing the `ShaderType` narrowing (reject `metal`/`hlsl`) and the `boost::optional` guard pattern for all new render-specific fields (Pitfalls 6, 7).
- [ ] **CI coverage:** Often "green in CI" only because CI silently has no real GPU and no software Vulkan driver — verify CI is actually exercising the render path device-creation-through-readback flow, not skipping/erroring silently (grounding facts: current CI installs `libvulkan-dev` only).
- [ ] **Cross-platform build wiring:** Often verified only via a successful *compile* on macOS/iOS, not an actual *run* — verify the render path is executed (not just built) on a MoltenVK target at least once (Pitfall 5).

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|----------------|-----------------|
| Shared init-lock missing (Pitfall 2) discovered post-ship via intermittent crash reports | LOW | Introduce the header-declared `VulkanInitGuard` singleton, migrate the 3 existing MNN call sites and the renderer's context-creation call site to acquire it; no schema/wire-format changes needed, purely an internal synchronization fix |
| Cross-vendor determinism failure (Pitfall 4) discovered after render `PassType` is already in production use | HIGH | Requires a consensus-model change (exact-hash → tolerance-based comparison, or output-format quantization) that may require a schema/wire-format addition (e.g. a `tolerance`/`comparison_mode` field on render passes) and coordination with whatever consumes the pass's verification result outside SGProcessingManager — much cheaper to resolve during schema design than after nodes are relying on strict-hash render verification |
| Native shader source (`metal`/`hlsl`) already in use for some render passes when Pitfall 6 is caught | MEDIUM | Recompile/re-author the affected shaders from a single canonical SPIR-V source, then add (retroactively) the schema validation that should have prevented this from the start; audit any already-submitted jobs using non-SPIR-V `ShaderType` |
| CI has no real Vulkan device signal (grounding fact) discovered late | LOW-MEDIUM | Add `mesa-vulkan-drivers` (lavapipe) or SwiftShader to the Linux CI job; both are readily apt-installable/vendorable and don't require any code changes, only CI workflow and possibly a documented "software-rasterizer results may not match hardware GPU hash" caveat if strict-hash comparison is still in use |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|-------------------|---------------|
| MNN-vs-render Vulkan context conflicts (Pitfall 1) | Vulkan context setup | Code review confirms no attempt to obtain/share MNN's internal Vulkan handles; design doc states independent-context decision explicitly |
| Concurrent Vulkan init race (Pitfall 2) | Vulkan context setup | Stress test: construct render context and trigger MNN Vulkan inference concurrently from multiple threads, confirm no crash/hang across repeated runs |
| Missing validation layers (Pitfall 3) | Vulkan context setup | Explicit written decision (vendor VVL or document the gap); if vendored, confirm `VK_LAYER_KHRONOS_validation` is actually loaded in a debug build via a deliberate test error |
| Cross-vendor render determinism (Pitfall 4) | Schema extension / PassType dispatch plumbing (design decision) → verified in end-to-end verification test | Run identical render job on ≥2 distinct GPU vendors or hardware-vs-software backends; confirm agreed comparison model (exact hash vs. tolerance) actually holds |
| MoltenVK headless/offscreen quirks (Pitfall 5) | Vulkan context setup / RenderProcessor implementation → verified in cross-platform build wiring | Actual run (not just compile) of the render path on a MoltenVK/Apple target; confirm no `VkSurfaceKHR`/`VkSwapchainKHR` calls exist in the implementation |
| Schema allows non-portable shader types (Pitfall 6) | Schema extension | `CheckProcessValidity()` rejects `metal`/`hlsl` `ShaderType` for render passes; test confirms rejection |
| `boost::optional` `.value()` crash pattern reintroduced for new render fields (Pitfall 7) | PassType dispatch plumbing / RenderProcessor implementation | Test feeds a non-render pass through any function touching new render-specific fields; confirm no crash, following the same pattern as the `ParseBlockSize()` fix |
| No GPU/software-Vulkan in CI (grounding fact) | Cross-platform build wiring | CI log shows `vkEnumeratePhysicalDevices` returning ≥1 device (software or hardware) and the render end-to-end test actually executing, not skipping |

## Sources

- Direct repository reads (HIGH confidence, curated/primary source): `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_image.cpp`, `_string.cpp`, `_volume.cpp`; `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp`; `SuperGenius/SGProcessingManager/generated/PassType.hpp`, `ShaderType.hpp`, `ShaderConfig.hpp`, `Pass.hpp`; `SuperGenius/build/CommonBuildParameters.cmake`; `SuperGenius/SGProcessingManager/cmake/CommonBuildParameters.cmake`; `SuperGenius/build/OSX/CMakeLists.txt`, `iOS/CMakeLists.txt`; `SuperGenius/src/processing/CMakeLists.txt`; `SuperGenius/SGProcessingManager/src/processors/CMakeLists.txt`; `SuperGenius/.github/workflows/cmake.yml`, `build-release-tags.yml`; `thirdparty/ThirdParty_Libraries_Integration.md`; `thirdparty/Vulkan-Headers`/`Vulkan-Loader` submodule commit tags (v1.3.302); `.planning/codebase/INTEGRATIONS.md`, `STACK.md`.
- [MoltenVK VK_EXT_headless_surface issue #2049](https://github.com/KhronosGroup/MoltenVK/issues/2049) (MEDIUM confidence, web search)
- [MoltenVK Whats_New.md](https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/Whats_New.md) (MEDIUM confidence, web search)
- [VK_EXT_headless_surface Khronos registry](https://registry.khronos.org/VulkanSC/specs/1.0-extensions/man/html/VK_EXT_headless_surface.html) (MEDIUM confidence, official spec via web search)
- General GPU floating-point non-determinism discussion, cross-checked across arXiv sources and Khronos community forum ("Floating point computation errors on GPU") (MEDIUM confidence — well-established general graphics/compute knowledge, not GNUS-specific)
- NVIDIA developer forums on multi-VkInstance/VkDevice behavior in one process (MEDIUM confidence, web search, used to confirm instance/device creation is the risk boundary rather than steady-state submission)

---
*Pitfalls research for: adding headless Vulkan rendering alongside existing MNN-Vulkan inference in SGProcessingManager*
*Researched: 2026-07-28*
