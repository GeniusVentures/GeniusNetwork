# Plan 05-01 Summary: CMake Refactoring — Render Libraries Platform-Agnostic Build

**Status:** Complete
**Date:** 2026-07-31
**Duration:** ~30min
**Files modified:** 1 (`thirdparty/build/CommonTargets.cmake`)

## What was built

Refactored `thirdparty/build/CommonTargets.cmake` to make the four render-specific thirdparty libraries (SPIRV-Headers, SPIRV-Tools, shaderc, vk-bootstrap) buildable unconditionally for all platforms including Android and iOS, per D-02 from the phase context.

## Tasks completed

### Task 1: Extract render libs from `if(NOT ANDROID)` to unconditional blocks
- Closed the `if(NOT ANDROID)` guard immediately after `Vulkan-Loader` + `set(ENV{VULKAN_SDK})` + `set(vulkanTarget)` — only Vulkan-Headers and Vulkan-Loader remain platform-gated.
- Moved SPIRV-Headers, SPIRV-Tools, vk-bootstrap, and shaderc `ExternalProject_Add` blocks to unconditional scope.
- Moved both IMPORTED target blocks (`SPIRV-Tools::SPIRV-Tools` and `shaderc::shaderc`) to unconditional scope.
- No CMAKE_CACHE_ARGS or IMPORTED target properties were modified — pure structural reorganization.

### Task 2: Platform-conditional Vulkan dependency wiring for vk-bootstrap
- Added `_VK_BOOTSTRAP_VULKAN_HEADERS_DIR` and `_VK_BOOTSTRAP_DEPENDS` variables set per platform group:
  - **Desktop** (`NOT ANDROID AND NOT IOS`): points to existing `Vulkan-Loader/share/cmake/VulkanHeaders`
  - **Android** (`ANDROID`): builds Vulkan-Headers from source with `_CMAKE_COMMON_CACHE_ARGS` (NDK toolchain propagates automatically)
  - **iOS** (`IOS`): builds Vulkan-Headers from source with `_CMAKE_COMMON_CACHE_ARGS` (apple toolchain propagates automatically)
- Replaced hardcoded `-DVulkanHeaders_DIR:PATH=...` in vk-bootstrap with `${_VK_BOOTSTRAP_VULKAN_HEADERS_DIR}`.
- Replaced hardcoded `DEPENDS Vulkan-Headers` with `${_VK_BOOTSTRAP_DEPENDS}`.

### Task 3: Verify IMPORTED targets and link chain
- Confirmed `shaderc::shaderc` and `SPIRV-Tools::SPIRV-Tools` IMPORTED targets are unconditional — defined for all platforms.
- Confirmed `SGShaderCompiler` links `shaderc::shaderc` and `SPIRV-Tools::SPIRV-Tools` unconditionally — no changes needed.
- Confirmed `SGProcessors` links `Vulkan::Vulkan` and `vk-bootstrap::vk-bootstrap` unconditionally — no changes needed.
- Confirmed iOS framework linking in SGProcessors covers all MoltenVK requirements (Metal, Foundation, QuartzCore, IOSurface, UIKit).
- Zero changes to any SGProcessingManager CMakeLists.txt file — pure verification.

## Acceptance criteria results

| Criterion | Result |
|-----------|--------|
| Vulkan-Headers/Loader inside `if(NOT ANDROID)` | ✅ Lines 364-374 inside guard, `endif()` at 393 |
| SPIRV-Headers unconditional | ✅ Line 396, top-level |
| SPIRV-Tools unconditional | ✅ Line 410, top-level |
| vk-bootstrap unconditional | ✅ Line 480, top-level |
| shaderc unconditional | ✅ Line 493, top-level |
| `_VK_BOOTSTRAP_VULKAN_HEADERS_DIR` ≥ 3 occurrences | ✅ 4 occurrences (3 sets + 1 use) |
| `shaderc::shaderc` ≥ 3 occurrences | ✅ 4 (add_library + set_target_properties + add_dependencies + comment) |
| `SPIRV-Tools::SPIRV-Tools` ≥ 3 occurrences | ✅ 7 (find_package + ALIAS + IMPORTED + set_target_properties + add_dependencies) |
| `if(NOT ANDROID)` count = 1 | ✅ Only line 362 (original guard) |
| SGShaderCompiler link chain verified | ✅ No changes needed |
| SGProcessors link chain verified | ✅ No changes needed |

## Deviations

None. All tasks executed exactly as planned.

## Decisions

None — all design decisions were pre-made in Phase 05 CONTEXT.md (D-01 through D-11).
