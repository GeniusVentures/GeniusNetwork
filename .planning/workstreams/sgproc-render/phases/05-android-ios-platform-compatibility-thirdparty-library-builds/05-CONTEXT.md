# Phase 5: Android/iOS Platform Compatibility - Context

**Gathered:** 2026-07-31
**Status:** Ready for planning

## Phase Boundary

Make the thirdparty build system produce all library dependencies the RenderProcessor needs on Android (arm64-v8a, armeabi-v7a) and iOS (arm64 device), and verify SGProcessingManager's render path compiles and links against the mobile-built libraries. This is a build-system phase — no new code, no on-device test execution.

## Implementation Decisions

### Build Scope — Library Inclusion
- **D-01:** All 4 render-specific libraries build for both Android and iOS: vk-bootstrap, SPIRV-Tools, shaderc, plus Vulkan-Loader (for iOS; Android uses NDK's loader).
- **D-02:** vk-bootstrap, SPIRV-Headers, SPIRV-Tools, and shaderc are platform-agnostic C++ — they must be pulled OUT of the `if(NOT ANDROID)` guard in `CommonTargets.cmake` and built for all platforms including Android. Only Vulkan-Headers + Vulkan-Loader remain platform-gated (NDK provides them on Android; MoltenVK on Apple).
- **D-03:** Additive only — no modifications to existing thirdparty ExternalProject blocks unless necessary. New blocks are added for the mobile platforms.
- **D-04:** MoltenVK is already vendored for iOS. Continue the existing pattern — extend `CommonTargets.cmake` to cover the iOS build target.

### shaderc Cross-Compilation
- **D-05:** Build shaderc from source via NDK toolchain for Android, apple.toolchain.cmake for iOS — same ExternalProject_Add pattern as desktop. Let shaderc build its own bundled glslang/SPIRV-Tools/SPIRV-Headers copies internally.
- **D-06:** Python is a documented build dependency for glslang's code generation step (inside shaderc). No code changes needed — CI runners and developer machines already have Python.

### Platform Targets
- **D-07:** Android ABIs: arm64-v8a and armeabi-v7a only. No x86_64.
- **D-08:** iOS: arm64 device only. No simulator architectures.

### Integration & Verification
- **D-09:** Phase scope includes both thirdparty library builds AND verifying SGProcessingManager's render path compiles/links against the mobile-built libraries. "Done" = all 4 libs produce `.a` files + SGProcessingManager links without errors.
- **D-10:** Manual hardware verification only. No CI changes in this phase. Verify on real Mac (iOS builds) and WSL (Android NDK builds). Build logs captured as evidence.
- **D-11:** No on-device test execution. RenderProcessor unit tests running on physical Android/iOS devices is deferred to a follow-up phase.

### Claude's Discretion
- Exact CMake `ExternalProject_Add` argument structure for mobile platforms (NDK cache args, apple toolchain args) — follow existing patterns in `thirdparty/build/Android/CMakeLists.txt` and `thirdparty/build/apple.toolchain.cmake`.
- Whether to create separate `CommonTargets.cmake` sections or a unified cross-platform block — researcher determines the cleanest approach.

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Build System
- `thirdparty/build/CommonTargets.cmake` §L362 — The `if(NOT ANDROID)` guard that currently excludes all render libs from Android. This is the primary file to modify.
- `thirdparty/build/Android/CMakeLists.txt` — Existing Android thirdparty build entry point. Pattern for NDK cross-compile args, ABI setup, Boost-for-Android integration.
- `thirdparty/build/apple.toolchain.cmake` — iOS/macOS toolchain. Pattern for Apple platform builds.
- `SuperGenius/build/Android/CMakeLists.txt` — SuperGenius Android build entry point.
- `SuperGenius/build/iOS/CMakeLists.txt` — SuperGenius iOS build entry point.

### Render Dependencies (vendored in thirdparty/)
- `thirdparty/vk-bootstrap/` — vk-bootstrap (MIT, pinned at v1.4.357)
- `thirdparty/shaderc/` — shaderc (Apache-2.0, pinned at v2024.3)
- `thirdparty/SPIRV-Tools/` — SPIRV-Tools (Apache-2.0, pinned to shaderc v2024.3 DEPS commit)
- `thirdparty/SPIRV-Headers/` — SPIRV-Headers (Khronos, pinned to shaderc v2024.3 DEPS commit)
- `thirdparty/Vulkan-Headers/` + `thirdparty/Vulkan-Loader/` — Vulkan SDK (already vendored)
- `thirdparty/MoltenVK/` — MoltenVK for Apple platforms (already vendored, including iOS)

### Prior Phase Decisions
- `docs/02-consensus-parent-child-authority.md` — (root project context, not directly relevant but part of the broader milestone)
- Research summary: `.planning/workstreams/sgproc-render/research/SUMMARY.md` — Decision Flags #1 (Vulkan init mutex) and #2 (shaderc vs glslang) established the toolchain choices Phase 5 builds upon.
- Phase 2 context: `.planning/workstreams/sgproc-render/phases/02-schema-extension-shader-spir-v-validation-pipeline/` — SHADER-01/SHADER-02 requirements that shaderc + SPIRV-Tools serve.

## Existing Code Insights

### Reusable Assets
- **`thirdparty/build/Android/CMakeLists.txt`**: Already sets up `ANDROID_ABI`, `CMAKE_ANDROID_NDK`, `ANDROID_NATIVE_API_LEVEL`, and `_CMAKE_COMMON_CACHE_ARGS` for cross-compilation. New render libs reuse the same cache args pattern.
- **`thirdparty/build/apple.toolchain.cmake`**: Already supports `OS=IOS`, `ARCHS=arm64`, `DEPLOYMENT_TARGET`. New iOS render libs reuse the same toolchain.
- **`SuperGenius/build/Android/CMakeLists.txt`** and **`SuperGenius/build/iOS/CMakeLists.txt`**: Existing platform entry points that will pick up the new render libraries once they're in the thirdparty build.

### Established Patterns
- **`ExternalProject_Add` in `CommonTargets.cmake`**: Every thirdparty library follows this pattern with `SOURCE_DIR`, `CMAKE_CACHE_ARGS`, `DEPENDS`, and `_CMAKE_COMMON_CACHE_ARGS`. New mobile blocks follow the same pattern.
- **`if(NOT ANDROID)` guard**: Used for platform-specific exclusions. The fix is to tighten this guard to only cover Vulkan-Headers/Loader (which the NDK provides).
- **IMPORTED targets for libraries without CMake configs**: shaderc and SPIRV-Tools use hand-written `IMPORTED` targets. These must be extended for Android/iOS library paths.

### Integration Points
- **`SGProcessingManager/src/processors/CMakeLists.txt`**: Links `vk-bootstrap::vk-bootstrap`, `shaderc::shaderc`, `SPIRV-Tools::SPIRV-Tools`. This file must resolve these targets correctly when building for Android/iOS.
- **`GeniusSDK/cmake/CommonBuildParameters.cmake`**: Contains `find_package(vk-bootstrap CONFIG REQUIRED)`. Must resolve on mobile platforms.

## Specific Ideas

- shaderc may ship tools with the Android NDK (glslc CLI), but `libshaderc_combined` needs a source build — the NDK does not ship it as a linkable library.
- SPIRV-Tools explicitly supports Android builds — this is a well-traveled path.
- The refactoring of `if(NOT ANDROID)` to only cover Vulkan-Headers/Loader (not SPIRV-Tools/shaderc) is the key architectural insight that simplifies the whole phase.

## Deferred Ideas

None — discussion stayed within phase scope.

---

*Phase: 05-Android/iOS Platform Compatibility: Thirdparty Library Builds*
*Context gathered: 2026-07-31*
