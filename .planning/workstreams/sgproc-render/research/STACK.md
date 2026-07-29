# Stack Research

**Domain:** Hand-rolled headless (offscreen, no swapchain) Vulkan render-pass execution for a distributed batch-processing node (SGProcessingManager `RenderProcessor`)
**Researched:** 2026-07-29
**Confidence:** HIGH (official repo/release data + direct inspection of this repo's own `thirdparty/` tree)

## Context Recap (ground truth already established, not re-derived here)

- `thirdparty/.gitmodules` vendors `Vulkan-Headers` (pinned `v1.3.302`-adjacent, commit `9dff1f5`), `Vulkan-Loader` (pinned `v1.3.302`-adjacent, commit `2534c1e`), and `MoltenVK` (pinned `v1.2.8`-adjacent, commit `e97ec49`) — confirmed by direct `git log`/`git describe` on the submodules.
- These exist **solely** so MNN can build its own internal Vulkan compute backend (`thirdparty/build/CommonTargets.cmake:362-392`, `MNN_VULKAN:BOOL=ON` at line 404). No `VkInstance`/`VkDevice` is exposed outside MNN.
- `thirdparty/build/cmake/kompute-fix.cmake` is confirmed dead/orphaned (a `find_package(Vulkan)`/`target_link_libraries(... Vulkan::Vulkan)` shim rerouting to a `kompute` target that isn't vendored anywhere) — not a working integration path, not reused.
- Grep across all of `thirdparty/` for `vk-bootstrap|VulkanMemoryAllocator|glslang|shaderc|VMA` found **zero** vendored submodules or CMake targets for any of the four candidate libraries. The only `glslang` hit is nested **inside** `MoltenVK/MoltenVKShaderConverter/glslang` — that's MoltenVK's own private, Xcode-project-built copy (used internally to convert GLSL→SPIR-V→MSL for Metal), not exposed via `CommonTargets.cmake`, not consumable by our CMake build, and Apple-only in build tooling. MNN's own precompiled-shader pipeline (`thirdparty/MNN/source/backend/vulkan/*/compiler/{getSpirv.sh,makeshader.py}`) shells out to a system-installed `glslangValidator`/`spirv-opt` at MNN's own dev-time shader-baking step — again, not a vendored dependency, and not something `RenderProcessor` can rely on being present in a deployed node's environment.
- **Conclusion: all four candidate libraries (vk-bootstrap, VMA, glslang, shaderc) are genuinely net-new additions if recommended.** None are transitively available today.

## Recommended Stack

### Core Additions

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **vk-bootstrap** | `v1.3.x` release line (pin to a tag built against Vulkan-Headers ~1.3, e.g. latest `v1.3.***` before the project's own Vulkan-Headers submodule is ever bumped past 1.3 — current upstream `HEAD` is `1.4.350` but any recent tag works since vk-bootstrap only needs Headers ≥1.1) | Instance/physical-device/device/queue bootstrap helper | Solves exactly the boilerplate this milestone needs once (enumerate/enable instance extensions+validation layers, pick a physical device against required features, resolve queue families, create the logical device) — and specifically automates the `VK_KHR_portability_subset` device-extension + portability-enumeration instance-extension dance required when running against **MoltenVK**, which this project's issue explicitly mandates supporting. Hand-rolling this correctly across "Windows/Linux native loader" + "macOS via MoltenVK" is where subtle bootstrap bugs live (pNext feature-chain ordering, silently missing the portability subset flag so device creation fails only on macOS). vk-bootstrap does **not** wrap or replace any Vulkan render/command API — it hands back raw `VkInstance`/`VkPhysicalDevice`/`VkDevice`/`VkQueue` handles for you to use directly with normal `vkCmd*` calls. That is categorically different from bgfx (a full cross-platform rendering-abstraction engine that replaces the Vulkan API surface with its own) — recommending it does not reopen the "no new GPU backend/abstraction" concern that killed bgfx. |
| **shaderc** | `v2024.3` (last release still targeting the Vulkan 1.3 SPIR-V/feature line, matching this repo's pinned Vulkan-Headers/Loader `~1.3.302`; `v2024.4`+ shifted default targeting to Vulkan 1.4 and isn't necessary here) | GLSL→SPIR-V compilation, both at project build time (baking any first-party default shaders, mirroring MNN's own `glslangValidator`-at-build-time pattern) **and** at job-submission time inside the running node process (compiling/validating job-supplied GLSL text embedded in a schema-declared render pass before any SPIR-V reaches `vkCreateShaderModule`) | See "Shader Compilation" analysis below — shaderc is the purpose-built embeddable library for exactly this "compile untrusted GLSL text, get back SPIR-V or a structured error" use case; glslang alone is lower-level and not chosen as the direct dependency (see rationale). |

### Explicitly NOT Added

| Technology | Why Not | What To Do Instead |
|------------|---------|---------------------|
| **Vulkan Memory Allocator (VMA)** | This milestone's `RenderProcessor` allocates a small, fixed, well-known set of GPU resources per job — one offscreen color attachment image, one depth attachment image, a vertex buffer, an index buffer, and a host-visible readback (staging) buffer: on the order of 4-6 `VkDeviceMemory` allocations per render job, nowhere near any GPU's `maxMemoryAllocationCount` limit (typically 4096+ on desktop, lower but still ample on mobile/MoltenVK). VMA's value proposition — sub-allocating many small resources out of large memory blocks, defragmentation, arbitrary-lifetime pooling — solves a problem this narrow single-render-pass batch job does not have. Adding it would be introducing an allocation *abstraction* for a workload that never needs one, which runs against the same "avoid unnecessary abstraction for a single schema-declared pipeline" reasoning that killed bgfx. | Hand-roll a small RAII wrapper (~80-120 lines) around `vkAllocateMemory`/`vkBindImageMemory`/`vkBindBufferMemory`/`vkFreeMemory`, using `vkGetPhysicalDeviceMemoryProperties` + a straightforward "find a memory type matching the required property flags" helper (the same ~20-line helper reproduced in nearly every Vulkan tutorial). If a future milestone adds many concurrent render/compute resource types or dynamic per-job resource counts, VMA (MIT, header-only) remains a trivial drop-in to revisit then — but it is not warranted for v1. |
| **glslang as the direct project dependency** | glslang's native API (`glslang::TShader`/`TProgram`/`TIntermediate`, manual `TBuiltInResource` limits struct, no built-in "return me a clean structured error/warning string") is a lower-level, more ceremony-heavy embedding surface than what's needed here, and is more error-prone to get right for a validation path that must gracefully reject hostile/malformed job-supplied shader text rather than crash or leak. It's also strictly a *subset* of what's needed: it does not include SPIR-V validation (`spirv-val`) or optimization — those live in the separate SPIRV-Tools project. | Use **shaderc** instead — it statically vendors/depends on both glslang (GLSL frontend) and SPIRV-Tools (validation/optimization/assembly) and exposes them behind one small, purpose-built C/C++ API (`shaderc::Compiler::CompileGlslToSpv`, `shaderc::SpvCompilationResult` with `.GetCompilationStatus()`/`.GetErrorMessage()`). Adding shaderc effectively gets glslang's parsing *and* SPIRV-Tools' validation for free, as one coherent dependency, instead of two. |
| **VK_KHR_swapchain / any WSI (window-system-integration) extension or surface-creation code path (Win32/Xlib/Xcb/Wayland/Metal-CAMetalLayer surfaces)** | This is a headless distributed-compute node with no display surface, ever. Swapchain/surface code exists purely to present images to a window — nothing here presents anything. | Skip `VK_KHR_swapchain` (and all platform WSI instance extensions: `VK_KHR_win32_surface`, `VK_KHR_xcb_surface`, `VK_EXT_metal_surface`, etc.) entirely. The offscreen render target is a plain `VkImage` with `VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT` (+ a depth image with `VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT`), read back via a `VK_IMAGE_USAGE_TRANSFER_SRC_BIT` + `vkCmdCopyImageToBuffer` into a host-visible/host-coherent buffer. This also means `vk-bootstrap`'s device-selection call should build with `.set_headless_surface(true)` semantics (i.e., skip its surface-requiring device-selection criteria) — vk-bootstrap explicitly supports headless device selection with no surface. |
| **Vulkan-ValidationLayers submodule** | Optional/deferred per the question's own framing — genuinely not required for v1 correctness, and adding a 5th new vendored dependency for a debug-only convenience isn't justified in the same research pass that's trying to keep net-new additions minimal. | Deferred — see "Validation Layers (Deferred)" below for the concrete recommendation to revisit later, without blocking v1. |

## Detailed Rationale by Question

### 1. Instance/device/queue bootstrap — vk-bootstrap vs hand-rolled

**Recommendation: add vk-bootstrap.** This is the one place this research diverges from "when in doubt, skip the dependency," and it's a narrow, deliberate exception — not a reopening of the bgfx question. The distinguishing test applied: *does this library replace/abstract the Vulkan API surface, or does it just automate one bounded, error-prone piece of boilerplate and hand back raw native handles?* vk-bootstrap is squarely the latter — its `Instance`/`PhysicalDevice`/`Device` builder types are thin convenience wrappers that terminate in a plain `VkInstance`/`VkPhysicalDevice`/`VkDevice`/`VkQueue`, which `RenderProcessor` then uses with completely ordinary Vulkan calls (`vkCreateRenderPass`, `vkCreateGraphicsPipelines`, `vkCmd*`, etc.) — there's no vk-bootstrap object in the render/command-recording path at all. The concrete value it adds for *this* project specifically: (a) it already special-cases the MoltenVK/`VK_KHR_portability_subset` requirement (enabling the portability enumeration instance extension and the portability-subset device extension only when the physical device reports it), which is exactly the platform this issue mandates supporting and exactly the kind of "gets silently missed and only breaks on macOS" bug hand-rolled code is prone to; (b) it's tiny — one header + one source file, MIT-licensed, its only dependency is Vulkan-Headers (already vendored) and C++17 (already the project baseline) — so it vendors cleanly into `thirdparty/` following the exact same `ExternalProject_Add` pattern already used for small utility deps like `GSL`/`fmt`/`rapidjson` in `CommonTargets.cmake`. License: MIT — fully compatible with the project's permissive-only constraint.
If the team prefers to hold the line at zero net-new deps for the bootstrap layer specifically, hand-rolling ~150-250 lines directly against Vulkan-Headers/Loader is a legitimate, simple alternative for a *single* fixed target platform — but given multi-platform + MoltenVK is an explicit, non-negotiable requirement of `SGProcessingManager#7`, vk-bootstrap meaningfully de-risks that specific surface and is the recommended default.

### 2. Memory/resource allocation — VMA vs manual `vkAllocateMemory`

**Recommendation: skip VMA, hand-roll manual allocation.** See "Explicitly NOT Added" table above for the full reasoning — allocation count for a single render pass (color attachment, depth attachment, vertex buffer, index buffer, readback staging buffer) is small and fixed, well under any practical `VkDeviceMemory` allocation-count limit, and does not need sub-allocation/pooling/defragmentation. A ~100-line RAII helper (`FindMemoryTypeIndex` + `AllocateAndBind{Image,Buffer}`) is simpler to review, audit, and reason about for this scope than pulling in a general-purpose allocator whose main value (avoiding `vkAllocateMemory` call-count/allocation-count pressure at scale) doesn't apply here. Revisit only if a future milestone adds many concurrent render targets or dynamic per-job resource multiplicities. (For the record: VMA is MIT-licensed and would be license-compatible if ever added later.)

### 3. Shader compilation — glslang vs shaderc

**Recommendation: shaderc**, used two ways:
- **Job-submission-time (the requirement that actually matters for security):** the render pass's vertex/fragment GLSL source arrives as part of an untrusted, schema-declared job payload and must be validated/rejected *before* any SPIR-V is handed to `vkCreateShaderModule`. shaderc's `shaderc::Compiler::CompileGlslToSpv(source, shader_kind, filename)` returns a `shaderc::SpvCompilationResult` whose `.GetCompilationStatus()` (an enum: success / invalid-stage / compilation-error / internal-error / invalid-assembly / validation-error / transformation-error) and `.GetErrorMessage()` give a clean, structured pass/fail plus human-readable diagnostics — exactly the shape needed to reject a malformed job cleanly instead of crashing the node or trusting attacker-controlled bytes into the GPU driver. Internally shaderc runs the GLSL through glslang for parsing/codegen and then through SPIRV-Tools for validation, so a single dependency gets both stages "for free."
- **Build-time (first-party/default shaders shipped with the node, if any exist):** the same `glslc` CLI (shaderc's command-line frontend, built alongside the library) can bake `.spv` blobs at build time, mirroring the pattern MNN's own build already follows (`glslangValidator`/`spirv-opt` invoked from `makeshader.py`) — except shaderc's `glslc` is what should actually be vendored/built rather than assuming a system-installed `glslangValidator`, since MNN's dev-time tool invocation is not itself part of the CMake build graph and can't be relied on to exist in this project's build environment.
- Defense-in-depth note: because shaderc already links SPIRV-Tools, it's trivial to additionally run `spirv-val` (SPIRV-Tools' standalone validator) on the resulting SPIR-V module as a second, independent check before `vkCreateShaderModule` — cheap insurance against any GLSL construct glslang accepts but that produces borderline-invalid SPIR-V, given the input is untrusted.
License: shaderc is Apache-2.0. Its glslang and SPIRV-Tools dependencies are both permissively licensed (BSD-style/Khronos license for glslang core; Apache-2.0 for SPIRV-Tools) — no GPL anywhere in the chain. Fully compatible with the project's permissive-only constraint.

### 4. Transitive vendoring check

Confirmed via direct read of `thirdparty/.gitmodules` and grep across the full `thirdparty/` tree: **none of vk-bootstrap, VMA, glslang (as a standalone/consumable dependency), or shaderc exist anywhere in this repo today.** The only false-positive hit was `glslang` vendored *inside* MoltenVK's own `MoltenVKShaderConverter` subtree — private to MoltenVK's Xcode-based internal shader-conversion pipeline (GLSL→SPIR-V→MSL), not exposed to or reusable by the rest of the build. `thirdparty/build/cmake/kompute-fix.cmake` is confirmed dead/orphaned as stated in the milestone context (a `find_package(Vulkan)` interception shim redirecting to a non-vendored `kompute` target) and was not treated as a viable integration path.

### 5. Headless/offscreen rendering pattern

No new library is needed for this — it's a matter of which Vulkan APIs to use and which to avoid, all already available via the vendored Vulkan-Headers/Loader:
- **Skip entirely:** `VK_KHR_swapchain` device extension, any WSI surface-creation instance extension (`VK_KHR_surface`, `VK_KHR_win32_surface`, `VK_KHR_xcb_surface`, `VK_KHR_wayland_surface`, `VK_EXT_metal_surface`/MoltenVK's surface path), `vkAcquireNextImageKHR`, `vkQueuePresentKHR`. None of these are needed or wanted for a server/node deployment with zero display surface — this satisfies "genuinely swapchain-free" directly; there is no headless-specific Vulkan extension required to *avoid* the swapchain, you simply never create one.
- **What replaces it:** a plain offscreen framebuffer — a color-attachment `VkImage` (`VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT`, typically `VK_FORMAT_R8G8B8A8_UNORM` or similar) plus a depth-attachment `VkImage` (`VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT`, e.g. `VK_FORMAT_D32_SFLOAT`), each with a `VkImageView`, bound into a `VkFramebuffer` created against a `VkRenderPass` with matching attachment descriptions. Render into it with the ordinary `vkCmdBeginRenderPass`/draw/`vkCmdEndRenderPass` sequence.
- **Readback:** after rendering, transition the color image to `VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL` and `vkCmdCopyImageToBuffer` into a host-visible + host-coherent `VkBuffer` (`VK_BUFFER_USAGE_TRANSFER_DST_BIT`), then `vkMapMemory`/`memcpy`/`vkUnmapMemory` (or a persistently-mapped buffer) to pull the rendered pixels into CPU memory for hashing/output — matching the "submit-once-return-hash" batch-job model rather than a real-time present loop.
- One optional extension worth considering (not required, purely a convenience): `VK_KHR_synchronization2` / just using core `vkQueueWaitIdle`/fences for the single-shot submit-and-wait pattern this batch job needs — no swapchain-adjacent synchronization primitives (semaphores tied to `vkAcquireNextImageKHR`) are relevant here at all, only a plain `VkFence` signaled on `vkQueueSubmit` and waited on before the readback copy is read.

### 6. Validation layers (deferred)

Not required for v1 correctness, and appropriately deferred rather than added now — agreeing with the question's own framing. When picked up later: `Vulkan-ValidationLayers` (Khronos, Apache-2.0) would be added as a debug-only vendored submodule (or, more simply, activated via `VK_LAYER_KHRONOS_validation` if a system Vulkan SDK install is present on the dev machine, with no build-time dependency at all) and enabled only when `vk-bootstrap`'s instance builder is configured with `.request_validation_layers()` in Debug configs — vk-bootstrap already has first-class support for conditionally requesting this layer, so choosing vk-bootstrap now makes picking up validation layers later a one-line change rather than new bootstrap plumbing. No action needed for v1.

## Installation / Vendoring Plan

Following the existing `ExternalProject_Add` convention in `thirdparty/build/CommonTargets.cmake` (see the `Vulkan-Headers`/`Vulkan-Loader` block at lines 362-392 for the closest existing pattern — small header/library deps with no exotic build requirements):

```
# thirdparty/.gitmodules additions
[submodule "vk-bootstrap"]
    path = vk-bootstrap
    url = https://github.com/charles-lunarg/vk-bootstrap.git
[submodule "shaderc"]
    path = shaderc
    url = https://github.com/google/shaderc.git
```

```cmake
# thirdparty/build/CommonTargets.cmake additions (illustrative; exact CACHE_ARGS to be
# finalized during phase planning against shaderc's actual CMake options, e.g.
# SHADERC_SKIP_TESTS, SHADERC_SKIP_EXAMPLES, SHADERC_ENABLE_SHARED_CRT on Windows)

ExternalProject_Add(
    vk-bootstrap
    PREFIX vk-bootstrap
    SOURCE_DIR "${THIRDPARTY_DIR}/vk-bootstrap"
    CMAKE_CACHE_ARGS
    -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
    -DVulkanHeaders_DIR:PATH=<Vulkan-Loader's VulkanHeaders install path>
    ${_CMAKE_COMMON_CACHE_ARGS}
    DEPENDS Vulkan-Headers
)

ExternalProject_Add(
    shaderc
    PREFIX shaderc
    SOURCE_DIR "${THIRDPARTY_DIR}/shaderc"
    CMAKE_CACHE_ARGS
    -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
    -DSHADERC_SKIP_TESTS:BOOL=ON
    -DSHADERC_SKIP_EXAMPLES:BOOL=ON
    -DSHADERC_SKIP_COPYRIGHT_CHECK:BOOL=ON
    ${_CMAKE_COMMON_CACHE_ARGS}
)
```

Note: shaderc's own repo vendors glslang and SPIRV-Tools as git submodules internally (via its `utils/git-sync-deps` script or its own `.gitmodules`) — when adding the `shaderc` submodule to this project, its nested submodules must also be initialized (`git submodule update --init --recursive` scoped to the shaderc path), the same recursive-submodule handling this project already needs for e.g. `MoltenVK`'s and `boost`'s own nested dependencies.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|--------------------------|
| vk-bootstrap for instance/device bootstrap | Hand-rolled bootstrap code, zero new dependency | If the team decides MoltenVK/macOS support can be validated manually and kept correct by hand, or if a future audit wants to minimize `thirdparty/` submodule count even further than this research recommends — hand-rolling is legitimate, just riskier specifically for the portability-subset edge case. |
| shaderc for GLSL→SPIR-V | glslang directly (skip shaderc, embed glslang's C++ API) | If the team wants exactly one Khronos-lineage dependency instead of shaderc's three-deep chain (shaderc→glslang+SPIRV-Tools), and is willing to hand-write the `TBuiltInResource` limits struct and error-message plumbing themselves. Not recommended given the added embedding complexity for an untrusted-input validation path, but not unreasonable. |
| Manual `vkAllocateMemory` | Vulkan Memory Allocator (VMA) | If a later milestone expands `RenderProcessor` to many concurrent render targets, dynamic per-job resource counts, or compute+render resource sharing at a scale where allocation-count limits or fragmentation become real concerns. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| bgfx, Kompute, Diligent Engine, or any other cross-platform rendering-abstraction engine | Explicitly ruled out by `SGProcessingManager#7` ("Do not add another GPU backend or duplicate platform setup") and by this milestone's own restart rationale — any such engine performs its own independent Vulkan instance/device bootstrap, which is exactly the "duplicate platform setup" the issue prohibits. `thirdparty/build/cmake/kompute-fix.cmake` is the fossil of exactly this mistake from a prior attempt. | Hand-rolled `RenderProcessor` directly against Vulkan-Headers/Vulkan-Loader (+ vk-bootstrap for bootstrap boilerplate only, per above). |
| `VK_KHR_swapchain` / any WSI surface extension | No display surface exists or will ever exist on this deployment target (distributed compute node). | Offscreen framebuffer + `vkCmdCopyImageToBuffer` readback, per Question 5 above. |
| OpenGL / SwiftShader / any CPU software-rasterizer fallback | Explicitly out of scope per the issue and the milestone context — Vulkan hardware only, hard-fail if unavailable. | Fail fast (a clear error result) at `RenderProcessor` initialization if `vk-bootstrap`'s physical-device selection finds no suitable Vulkan-capable device — no fallback tier. |

## Version Compatibility

| Package | Compatible With | Notes |
|---------|------------------|-------|
| vk-bootstrap (any recent tag, e.g. `v1.3.3xx` line) | Vulkan-Headers `~v1.3.302` (this repo's pinned version) | vk-bootstrap only requires Headers ≥1.1; no tight coupling to an exact SDK patch version, so pinning to the newest available tag at implementation time is safe and does not force a Vulkan-Headers bump. |
| shaderc `v2024.3` | glslang `vulkan-sdk-1.3.296.0`-line, SPIRV-Tools of the same SDK generation | Matches this repo's pinned Vulkan-Headers/Loader `~1.3.302` line. Avoid shaderc `v2024.4`+ for this milestone — it shifted default SPIR-V/Vulkan targeting to the 1.4 line, which is a needless version-skew risk against this repo's still-1.3-pinned Vulkan-Headers/Loader/MoltenVK submodules. |
| MoltenVK `~v1.2.8` (this repo's pinned version) | Vulkan 1.2 core + most Vulkan 1.3 extensions via `VK_KHR_portability_subset` | Confirm during implementation which specific 1.3-era features (e.g. dynamic rendering, if ever considered as a swapchain-free-attachment convenience) MoltenVK 1.2.8 actually supports before relying on them — this pinned MoltenVK version is chronologically older than the pinned Vulkan-Headers/Loader, so not every 1.3 feature surfaced in the headers is necessarily implemented by this specific MoltenVK commit. This milestone's plan should stick to well-established core Vulkan 1.0/1.1 render-pass/framebuffer APIs (traditional `VkRenderPass`/`VkFramebuffer`, not `VK_KHR_dynamic_rendering`) to sidestep this risk entirely. |

## Sources

- https://github.com/charles-lunarg/vk-bootstrap — vk-bootstrap repo, MIT license, dependency-free-beyond-Headers claim, latest tag `1.4.350` (WebSearch, MEDIUM-HIGH confidence, official repo)
- https://vcpkg.link/ports/vk-bootstrap/versions — version history cross-check (WebSearch, MEDIUM confidence, third-party mirror)
- https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator — VMA repo, latest release `v3.3.0`, MIT license (WebSearch, HIGH confidence, official repo)
- https://github.com/KhronosGroup/glslang/releases and tag listing (`vulkan-sdk-1.3.296.0`, `vulkan-sdk-1.3.290.0`, `vulkan-sdk-1.4.328.1`, `vulkan-sdk-1.4.341`) (WebSearch, HIGH confidence, official repo + Google-mirrored tags)
- https://github.com/google/shaderc — shaderc repo, Apache-2.0 license, glslang+SPIRV-Tools dependency chain, CLI (`glslc`) and library API confirmed (WebSearch, HIGH confidence, official repo)
- https://github.com/google/shaderc/blob/main/CHANGES — shaderc `v2024.0`–`v2024.4` release notes, confirming `v2024.4` moved default Vulkan targeting to 1.4 (WebSearch, HIGH confidence, official changelog)
- Direct repository inspection: `W:\gnus\GeniusNetwork\thirdparty\.gitmodules`, `thirdparty\build\CommonTargets.cmake`, `thirdparty\build\cmake\kompute-fix.cmake`, `git log`/`git describe` on `Vulkan-Headers`/`Vulkan-Loader`/`MoltenVK` submodules, and a full-tree grep for `vk-bootstrap|VulkanMemoryAllocator|glslang|shaderc|VMA` (direct tool use, HIGHEST confidence — ground truth for this repo)

---
*Stack research for: hand-rolled headless Vulkan render-pass execution, SGProcessingManager `RenderProcessor`, workstream `sgproc-render` v1.0*
*Researched: 2026-07-29*
