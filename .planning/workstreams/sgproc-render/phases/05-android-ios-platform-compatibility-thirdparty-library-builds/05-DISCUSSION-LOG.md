# Phase 5: Android/iOS Platform Compatibility - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-31
**Phase:** 05-Android/iOS Platform Compatibility: Thirdparty Library Builds
**Areas discussed:** Build Scope, shaderc Cross-Compilation, ABI/iOS Architectures, Integration & Verification

---

## Build Scope — Which Libraries?

| Option | Description | Selected |
|--------|-------------|----------|
| All 4 render libs for both platforms | Vulkan-Loader, vk-bootstrap, SPIRV-Tools, shaderc — built for Android (NDK) and iOS. Full parity with desktop. | ✓ |
| Render libs, but skip shaderc on mobile | SPIR-V arrives pre-compiled, no runtime GLSL compile needed | |
| Minimal: just vk-bootstrap + Vulkan-Loader | Skip SPIRV-Tools/shaderc entirely on mobile | |

**User's choice:** All 4 render libs for both platforms
**Notes:** User clarified that MoltenVK is already vendored for iOS — continue that pattern. User also identified that vk-bootstrap, SPIRV-Tools, and shaderc are platform-agnostic C++ and should NOT be inside the `if(NOT ANDROID)` guard at all — only Vulkan-Headers/Loader need platform-gating since Android NDK provides them. Additive approach only — don't modify existing ExternalProject blocks unless necessary. Build verification runs on real Mac/WSL hardware.

---

## shaderc Cross-Compilation Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Let shaderc build its own copies via NDK | Same as desktop — shaderc's CMake builds bundled third_party/. NDK cross-compile handles it. | ✓ |
| Prebuilt shaderc binaries for mobile | Ship pre-compiled libshaderc_combined.a, avoid NDK complexity | |
| Skip shaderc on mobile, SPIR-V pre-compiled only | Mobile jobs receive pre-validated SPIR-V, no runtime GLSL compile | |

**User's choice:** Build from source via NDK, same pattern as desktop
**Notes:** User noted shaderc may ship tools with NDK but libshaderc_combined still needs a source build. Python is a documented build dependency for glslang codegen. SPIRV-Tools explicitly supports Android builds.

---

## Android ABI Targets & iOS Architectures

| Option | Description | Selected |
|--------|-------------|----------|
| arm64-v8a only | Default, 99%+ of modern Android devices | |
| All 3: arm64-v8a, armeabi-v7a, x86_64 | Full coverage, x86_64 for emulator | |

**User's choice:** arm64-v8a and armeabi-v7a (free text: "arm64-v8a and armeabi-v7a, we never build x86 really")

**iOS:**

| Option | Description | Selected |
|--------|-------------|----------|
| Device only (arm64) | Physical iOS devices, simpler build, no simulator | ✓ |
| Device + simulator (arm64, x86_64) | Full Xcode simulator support | |

**User's choice:** arm64 device only

---

## Integration & Verification

**Scope boundary:**

| Option | Description | Selected |
|--------|-------------|----------|
| Thirdparty libs only | Just build .a/.framework artifacts | |
| Thirdparty libs + RenderProcessor compiles | Also verify SGProcessingManager compiles/links against mobile libs | ✓ |

**User's choice:** Full compile verification included

**Verification approach:**

| Option | Description | Selected |
|--------|-------------|----------|
| CI automation + manual hardware verify | Add to cmake.yml CI | |
| Manual hardware verification only | Document build commands, verify on real hardware | ✓ |

**User's choice:** Manual hardware verification only — no CI in this phase

**Success criterion:**

| Option | Description | Selected |
|--------|-------------|----------|
| All 4 libs build + RenderProcessor links | .a files produced + SGProcessingManager links | ✓ |
| Plus unit tests pass on device | On-device test execution | |

**User's choice:** Build + link verification only. No on-device tests.

---

## Claude's Discretion

- Exact CMake `ExternalProject_Add` argument structure for mobile platforms — follow existing patterns in Android CMakeLists.txt and apple.toolchain.cmake.
- Whether to create separate CommonTargets.cmake sections or a unified cross-platform block — researcher determines the cleanest approach.

## Deferred Ideas

None — discussion stayed within phase scope.
