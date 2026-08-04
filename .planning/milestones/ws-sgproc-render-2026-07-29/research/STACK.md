# Stack Research

**Domain:** Headless/offscreen Vulkan rendering for a distributed processing node (`SGProcessingManager` `RenderProcessor`, `PassType::RENDER`)
**Researched:** 2026-07-28
**Confidence:** HIGH (licenses verified directly against source LICENSE files; library capability claims cross-checked via multiple independent sources; a few capability details on rejected candidates are MEDIUM/LOW as noted)

> **Recommendation in one line:** Do **not** vendor a rendering engine. Vendor 3 small, focused Khronos/GPUOpen/independent libraries directly on top of the already-vendored `Vulkan-Headers`/`Vulkan-Loader`, and hand-roll a thin `RenderProcessor` that builds `VkPipeline`/`VkBuffer`/`VkImage` objects straight from schema config. This is the only option that is simultaneously fully headless, minimal in footprint, and a natural fit for `find_package`/`include_directories` git-submodule vendoring.

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **Vulkan-Headers** (already vendored) | commit `9dff1f5`, `VK_HEADER_VERSION 302` (~SDK 1.3.2xx, late 2024), Apache-2.0 | Vulkan C API headers, `VK_API_VERSION_1_3` present | No new dependency — already in `thirdparty/`. Vulkan 1.3 core headers mean **dynamic rendering** (`vkCmdBeginRendering`/`VK_KHR_dynamic_rendering`, core since 1.3) is available, letting the render pass avoid `VkRenderPass`/`VkFramebuffer` boilerplate entirely — simpler headless-target setup than classic render-pass objects. |
| **Vulkan-Loader** (already vendored) | commit `2534c1e`, Apache-2.0 | ICD loader, resolves `vkGet*ProcAddr` to the GPU driver | No new dependency. Already wired into `find_package(Vulkan)` via `VULKAN_SDK` env pointing at `thirdparty/Vulkan-Loader` in both `SGProcessingManager/cmake/CommonBuildParameters.cmake` and the top-level `SuperGenius/build/CommonBuildParameters.cmake`. |
| **vk-bootstrap** (`charles-lunarg/vk-bootstrap`) | ~1.4.350 (tracks Vulkan SDK tags), **MIT** (verified via direct `LICENSE.txt` fetch) | Instance/physical-device/logical-device/queue bootstrap | `vkb::InstanceBuilder::set_headless()` exists explicitly to **skip WSI/surface creation** — this is a first-class supported headless code path, not a workaround. Removes ~300-500 lines of boilerplate (extension/layer negotiation, queue-family selection, feature-chain building) that every hand-rolled Vulkan init otherwise reimplements badly. Single small library, trivial CMake target (`add_subdirectory` or a couple of source files) — fits the existing convention with the least new surface area of any option evaluated. |
| **VulkanMemoryAllocator (VMA)** (`GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator`) | v3.4.0 (2026), **MIT** | Buffer/image memory allocation | Vertex/index buffers and render-target images/textures all need `VkDeviceMemory` allocation + binding; VMA is the de-facto standard for this (AMD/GPUOpen-maintained, used across the industry). Effectively single-header (`vk_mem_alloc.h` + a small implementation TU) — vendors as cleanly as the existing header-only libs already in `thirdparty/` (e.g. `json`, `GSL`, `stb`). |
| **shaderc** (`google/shaderc`, wraps `glslang` + `SPIRV-Tools` + `SPIRV-Headers`) | tracks upstream Vulkan SDK releases, **Apache-2.0** (verified via direct `LICENSE` fetch) | Compiles schema-supplied GLSL shader source + entry point into SPIR-V at job-execution time | The schema carries raw shader source (not precompiled SPIR-V), so the render pipeline needs a runtime GLSL→SPIR-V compiler. `shaderc_compile_into_spv(source, stage, entry_point, ...)` maps directly onto the "shader source + entry point" schema fields with a clean C/C++ API. See **licensing nuance** below — does not block the non-GPL constraint but must be scoped correctly. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `glslang` (pulled in as shaderc's compiler backend, KhronosGroup) | tracks shaderc's pinned revision, mixed license (see nuance below) | GLSL front-end / SPIR-V code generation | Automatically vendored as shaderc's dependency — do not vendor/invoke it standalone unless shaderc's API proves insufficient (e.g. need `#include` directive support beyond shaderc's built-in includer, in which case use `glslang::TShader`/`TProgram` directly). |
| `SPIRV-Tools` + `SPIRV-Headers` (KhronosGroup) | tracks shaderc's pinned revision, Apache-2.0 | SPIR-V validation/optimization, assembler/disassembler | Pulled in transitively by shaderc for `shaderc_optimization_level` and SPIR-V validation. Useful directly if the render processor wants to validate/log a job's compiled SPIR-V before executing it (defense against malformed job-supplied shaders). |
| Vulkan 1.3 dynamic rendering (`VK_KHR_dynamic_rendering` / core) | N/A — spec feature, no library | Render-to-texture target setup without `VkRenderPass`/`VkFramebuffer` | Use for the render-target/framebuffer schema config — a `VkImageView` + `vkCmdBeginRendering(VkRenderingInfo)` is enough; avoids a whole category of render-pass-compatibility bugs that classic `VkRenderPass` objects introduce. Available today from the already-vendored header version. |
| MoltenVK (already vendored, `thirdparty/MoltenVK`) | existing pin, Apache-2.0 | Vulkan-over-Metal on macOS/iOS build targets | Already present for other reasons; no change needed — the render path runs through the same `Vulkan::Vulkan` CMake target on every platform including macOS, so it benefits automatically. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Vulkan Validation Layers (`VK_LAYER_KHRONOS_validation`, part of the Vulkan SDK / `Vulkan-ValidationLayers` repo, Apache-2.0) | Catch pipeline/descriptor/sync misuse during development | Not required at runtime in production, but strongly recommended to vendor or install during implementation/testing of the new `RenderProcessor` — this is exactly the class of bug (wrong image layout, missing barrier, pipeline-render-target mismatch) that silently produces wrong pixels instead of a crash. Consider a 4th thin submodule (`Vulkan-ValidationLayers`, KhronosGroup, Apache-2.0) gated to debug/test builds only, mirroring how `GTest` is already scoped. |
| RenderDoc / `glslangValidator` CLI (external, not vendored) | Manual debugging of a captured headless frame; offline shader sanity-checking during development | Dev-machine tool only, no repo footprint. |

## Installation (submodule + CMake, matching existing convention)

```bash
# From repo root, alongside the existing Vulkan-Headers / Vulkan-Loader submodules:
git submodule add https://github.com/charles-lunarg/vk-bootstrap.git thirdparty/vk-bootstrap
git submodule add https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator.git thirdparty/VulkanMemoryAllocator
git submodule add https://github.com/google/shaderc.git thirdparty/shaderc
# shaderc vendors glslang/SPIRV-Tools/SPIRV-Headers as its OWN nested submodules
# (run its documented `utils/git-sync-deps` or add them as further nested submodules,
# consistent with the existing ~35-nested-submodule pattern under thirdparty/)
```

```cmake
# In SGProcessingManager/cmake/CommonBuildParameters.cmake, alongside the existing:
#   find_package(Vulkan) / find_package(Vulkan REQUIRED) block

add_subdirectory(${_THIRDPARTY_BUILD_DIR}/vk-bootstrap vk-bootstrap-build)

set(VMA_STATIC_VULKAN_FUNCTIONS OFF) # loader-resolved, matches existing Vulkan::Vulkan usage
include_directories(${_THIRDPARTY_BUILD_DIR}/VulkanMemoryAllocator/include)

set(SHADERC_SKIP_TESTS ON)
set(SHADERC_SKIP_EXAMPLES ON)
set(SHADERC_SKIP_COPYRIGHT_CHECK ON)
add_subdirectory(${_THIRDPARTY_BUILD_DIR}/shaderc shaderc-build)
```

New processor target (`SGProcessingManager/src/processors/CMakeLists.txt`) links: `Vulkan::Vulkan`, `vk-bootstrap`, `shaderc` (or `shaderc_combined`), and includes VMA's header-only path — same pattern as the existing MNN processors linking `MNN::MNN`.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|--------------------------|
| Custom thin `RenderProcessor` on raw Vulkan + vk-bootstrap + VMA + shaderc | **bgfx** (`bkaradzic/bgfx`, BSD-2-Clause) | If the project later needs to support **multiple graphics backends** (D3D12/Metal/GL) behind one API for portability beyond Vulkan. Its headless mode (`nwh == NULL`) is real for GL/D3D but Vulkan-backend headless has historically had rougher edges (surface-creation assumptions); would need direct verification before relying on it. Not worth its cross-API abstraction overhead when the constraint here is Vulkan-only, one node type. |
| Custom thin `RenderProcessor` | **Diligent Engine** (Apache-2.0) | If the render passes grow into a full engine-shaped problem (many material types, editor tooling, multiple backends). For "execute one schema-described pipeline headlessly," its abstraction layers (its own shader cross-compiler, render-state notation, asset system) are pure overhead, and this research could not fully confirm a clean headless-Vulkan-without-swapchain code path from public docs alone — would need source-level verification before adoption. |
| Custom thin `RenderProcessor` | **VulkanSceneGraph (vsg)** (MIT, actively maintained, v1.1.13 Dec 2025) | If SGProcessingManager later needs actual **scene-graph** semantics (hierarchical transforms, culling, multi-object scenes) rather than single schema-defined pipelines. VSG's `vsgheadless` example proves genuine headless capability, making it the most credible engine-level alternative of the four evaluated — but it still imposes a scene-graph object model (`ref_ptr`, `Visitor`, `Viewer`/`CommandGraph`) that the current schema (single vertex+fragment pipeline, explicit buffers/targets) doesn't need. |
| Custom thin `RenderProcessor` | **Filament** (Apache-2.0, Google) | Not recommended at all for this milestone: Filament's Vulkan backend headless/no-swapchain support was still an open feature request as of its GitHub issue #2007, and its headless story is materially more mature on Android-via-SwiftShader (software rasterizer) than on a real Vulkan device — a poor match for "distributed compute node with a real GPU, no display." It's also the heaviest option (PBR material system, `matc` shader compiler, asset pipeline) of everything evaluated. |
| shaderc (Apache-2.0 wrapper) | Vendor `glslang` directly, skip shaderc | If minimizing nested-submodule count is prioritized over API ergonomics. `glslang` alone (via `glslang::TShader`/`TProgram`) can compile GLSL→SPIR-V without `SPIRV-Tools`, but the API is materially more verbose than shaderc's `shaderc_compile_into_spv(...)`, and shaderc adds useful validation/optimization passes essentially for free. |
| Runtime GLSL compilation | Precompile shaders to SPIR-V offline, ship only `.spv` blobs | Only viable if job-submitted shader source is a **fixed, known set** decided at build time. Given the milestone's schema explicitly carries shader source + entry point as per-job config (jobs are submitted by external requesters over the distributed network), offline precompilation isn't applicable here — runtime compilation is a hard requirement. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Any full rendering **engine** (bgfx, Diligent, Filament, vsg) as the render execution path | All four impose an abstraction (draw-call submission model, material/asset system, or scene graph) the schema doesn't need; all add a large transitive dependency surface (their own shader cross-compilers, asset pipelines, or multi-backend abstraction layers) for a job that is fundamentally "build one `VkPipeline`, bind buffers, draw, copy out the target image" | Thin custom `RenderProcessor` directly on Vulkan-Headers/Loader + vk-bootstrap + VMA + shaderc |
| Anything requiring a live **swapchain/window** as a hard dependency (e.g. GLFW-coupled Vulkan samples, most beginner Vulkan-engine starter templates) | SGProcessingManager is a headless distributed compute node — there is no display, no window manager, and the existing MNN Vulkan backend already proves this environment has no windowing surface anywhere in the process | `vk-bootstrap`'s `set_headless()` instance path; render-to-texture via `VkImage`/`VkImageView` + dynamic rendering, output read back via `vkCmdCopyImageToBuffer` |
| GPL/AGPL-licensed Vulkan tooling of any kind | Hard non-GPL constraint from the user for all new `thirdparty/` additions | Every library recommended above is Apache-2.0 or MIT; see licensing nuance below for the one component (`glslang`, pulled in transitively via shaderc) that has legacy GPL-adjacent text |
| Treating MNN's internal Vulkan usage as reusable for rendering | MNN fully encapsulates its Vulkan context (no exposed `VkInstance`/`VkDevice`/`VkQueue` anywhere in the repo) and its Vulkan init is explicitly not thread-safe (process-wide mutex) — there is nothing to hook into or share | Independent Vulkan instance/device created by the new `RenderProcessor` via `vk-bootstrap`, isolated from MNN's internal context entirely |

### Licensing nuance: `glslang`'s legacy GPL-adjacent clause (do not skip this)

`glslang`'s `LICENSE.txt` lists multiple licenses side by side; alongside the permissive BSD-3/BSD-2/MIT/Apache-2.0 grants, it also carries a **"GPL 3 with special Bison exception"** clause that the file itself scopes to the *preprocessor's* legacy Bison-generated-parser code. The Bison runtime exception text explicitly states such a larger work may be distributed "under terms of your choice" — this is the standard GNU Bison linking exception, specifically designed so that using Bison-generated parser code does **not** impose GPL/copyleft on the surrounding project. The same license file also notes Bison was removed from glslang's build long ago, meaning current glslang builds likely don't even exercise this legacy code path. **Recommendation:** this does not block the non-GPL constraint, but flag it explicitly for whoever signs off on new `thirdparty/` licenses this milestone — don't let "glslang" get silently approved as "just Apache-2.0" without this caveat on record. If the strict reading of "no GPL text anywhere in a vendored dependency, even with an exception" is required, fall back to vendoring `glslang` at a revision/config with the legacy preprocessor path excluded, or use `SPIRV-Tools`' assembler and hand-write SPIR-V for a fixed shader set (loses the "arbitrary job-supplied GLSL source" flexibility).

## Stack Patterns by Variant

**If job-submitted shaders must be treated as untrusted input (they come from external network requesters):**
- Run `shaderc`'s compile step with strict `shaderc_optimization_level_zero` first and validate the resulting SPIR-V via `SPIRV-Tools`' validator (`spvValidateBinary`) before ever submitting it to the driver.
- Because a malformed/malicious shader reaching the GPU driver directly is a much worse failure mode (driver crash / device-lost) than a rejected job — this mirrors the existing pattern of validating `DataType`-specific processing config before execution (`CheckProcessValidity()`).

**If the render target is consumed the same way MNN inference outputs are today (buffer/texture output, no display):**
- Use `vkCmdCopyImageToBuffer` after rendering to pull the color attachment into a host-visible/coherent staging buffer (allocated via VMA), then feed it through whatever output path the existing MNN processors already use for `TEXTURE2_D`/`TEXTURE3_D` outputs.
- Because this reuses the established output-handoff convention instead of inventing a second one specific to render passes.

**If build-time cost of vendoring shaderc's full dependency chain (glslang + SPIRV-Tools + SPIRV-Headers, each their own nested submodule) is a concern:**
- Vendor `glslang` alone and call its `TShader`/`TProgram` API directly for GLSL→SPIR-V, skipping `SPIRV-Tools` optimization/validation passes initially.
- Because it's a strictly smaller dependency footprint at the cost of a more verbose compile-call API and losing free SPIR-V validation — acceptable if the render pass is initially scoped to trusted/internal shader sources only.

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|------------------|-------|
| `vk-bootstrap` ~1.4.350 | `Vulkan-Headers` `VK_HEADER_VERSION 302` (already vendored) | vk-bootstrap tracks Vulkan SDK versioning loosely; it targets the Vulkan C API surface, not a specific header revision, so no strict pin required — but bumping `Vulkan-Headers` to a current SDK release alongside adding vk-bootstrap is worth doing in the same phase to avoid mismatched extension enums. |
| VMA v3.4.0 | Vulkan 1.0+ (uses 1.1/1.2/1.3 features opportunistically when available) | Works fine against the currently vendored header version; no forced bump required. |
| `shaderc` | Bundles its own pinned `glslang`/`SPIRV-Tools`/`SPIRV-Headers` revisions | Do not attempt to point shaderc at independently-vendored copies of glslang/SPIRV-Tools unless deliberately overriding — version skew between shaderc and its compiler backend is a common source of build breaks. |
| Vulkan 1.3 dynamic rendering | `Vulkan-Headers` `VK_API_VERSION_1_3` (present today) + a driver reporting `VK_KHR_dynamic_rendering`/Vulkan 1.3 support | Virtually universal on desktop GPU drivers from 2022+; `vk-bootstrap`'s device selector can require this feature explicitly during physical-device selection, failing job execution cleanly on unsupported hardware rather than crashing mid-pipeline. |

## Sources

- Direct fetch of `charles-lunarg/vk-bootstrap` `LICENSE.txt` — confirmed MIT — HIGH
- Direct fetch of `google/shaderc` `LICENSE` — confirmed Apache License 2.0 — HIGH
- Direct fetch of `KhronosGroup/glslang` `LICENSE.txt` — confirmed mixed BSD/MIT/Apache-2.0 core license + a GPL-3-with-Bison-exception clause scoped to legacy preprocessor code — HIGH (direct source read)
- Web search: bgfx license/headless status (`bkaradzic/bgfx` GitHub issues #1974, #1285, #1226, official docs) — MEDIUM
- Web search: Diligent Engine license/headless status (`DiligentGraphics/DiligentEngine`, `DiligentCore` GitHub) — LOW (headless-Vulkan-without-swapchain not independently confirmed)
- Web search: VulkanSceneGraph license/maintenance/headless status (`vsg-dev/VulkanSceneGraph` releases, discussions #1451, #875) — MEDIUM
- Web search: Vulkan-Hpp / Vulkan-Utility-Libraries license/version (`KhronosGroup` GitHub) — MEDIUM
- Web search: SaschaWillems/Vulkan offscreen example license/pattern — MEDIUM
- Web search: Filament license/headless-Vulkan status (`google/filament` issue #2007) — MEDIUM
- Web search: VulkanMemoryAllocator license/version (releases page, v3.4.0 / v3.3.0 / v3.2.0 tags) — MEDIUM, license further confirmed HIGH by cross-reference with well-established MIT status
- Repo inspection (this session): `thirdparty/Vulkan-Headers`, `thirdparty/Vulkan-Loader` git log + `VK_HEADER_VERSION`/`VK_API_VERSION_1_3` grep; `SGProcessingManager/cmake/CommonBuildParameters.cmake` and `SuperGenius/build/CommonBuildParameters.cmake` `find_package(Vulkan)` blocks; `SGProcessingManager/src/processingbase/ProcessingManager.cpp` `PassType::RENDER` stub — HIGH (primary source, this repo)

---
*Stack research for: headless Vulkan rendering capability, SGProcessingManager sgproc-render workstream*
*Researched: 2026-07-28*
