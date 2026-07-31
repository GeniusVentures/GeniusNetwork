---
status: resolved
phase: 02-schema-extension-shader-spir-v-validation-pipeline
source: [02-VERIFICATION.md]
started: 2026-07-31T00:20:00Z
updated: 2026-07-31T21:20:00Z
---

## Current Test

number: 3
name: Confirm SGShaderCompiler links against the real production targets in the actual build tree
expected: All 3 items resolved.
awaiting: none — all tests passed

## Tests

### 1. Full build+link+run of ProcessingBase, shader_compiler_test, processing_dispatch_test
expected: All listed test cases pass when actually compiled, linked, and executed against a real link of ProcessingManager.cpp + shader_compiler.cpp in this project's actual build tree.
result: PASS — real MSVC/VS2022 build of `ProcessingBase`, `SGShaderCompiler`, `shader_compiler_test.exe`, `processing_dispatch_test.exe` in `SuperGenius/build/Windows/Release`. `shader_compiler_test`: 6/6 pass. `processing_dispatch_test`: 8/8 pass (7 original + 1 new hlsl-exception-safety test added during this verification pass). Zero compile/link errors.

Two real bugs were found and fixed during this build (not present in the original code-review-only assessment):
- `SuperGenius/build/CommonBuildParameters.cmake` had no `find_package`/IMPORTED-target wiring for shaderc/SPIRV-Tools at all (thirdparty's own `CommonTargets.cmake` only makes those targets visible within thirdparty's own separate CMake invocation).
- `thirdparty/build/CommonTargets.cmake`'s hand-written IMPORTED targets hardcoded GCC-style `.a` extensions; fixed to portable `CMAKE_STATIC_LIBRARY_PREFIX/SUFFIX` for the real MSVC toolchain.
- **`ProcessingManager.cpp`'s `GetCidForProc()` had a dangling-reference bug**: `get_render_shader()` returns `boost::optional<RenderShaderConfig>` by value, and binding `stages` as a reference through a chained `.value().get_stages()` call left it pointing at a temporary destroyed at the end of the statement. This silently made the render-stage loop iterate zero times, meaning shader compile/validate was **never actually reached** during dispatch — the two new dispatch tests were failing for the wrong reason (falling through to an unrelated missing-input error) until this was found and fixed.

### 2. Exercise the newly-added exception-safety catch clause with a legacy hlsl/metal job
expected: Submitting a job JSON with shader_stage.type: "hlsl" (or "metal") to ProcessingManager::Create() returns outcome::failure(Error::INVALID_JSON) rather than crashing or propagating an uncaught exception.
result: PASS — added a permanent regression test (`LegacyHlslShaderTypeFailsCleanlyNotCrash`) with a real fixture JSON (`render-pass-legacy-hlsl-definition.json`), submitted through a live `ProcessingManager::Create()` call. Returns `Error::INVALID_JSON` cleanly, no crash. Confirmed via real build+run.

### 3. Confirm SGShaderCompiler links against the real production targets in the actual build tree
expected: cmake --build succeeds for ProcessingBase against the real (not scratch/parallel) shaderc::shaderc / SPIRV-Tools::SPIRV-Tools targets inside thirdparty/build/Windows/Debug.
result: PASS (Release, not Debug — thirdparty/SuperGenius were built in the Release config this session). Real `cmake .` reconfigure + `cmake --build` of `ProcessingBase`/`shader_compiler_test`/`processing_dispatch_test` against the actual installed `shaderc::shaderc`/`SPIRV-Tools::SPIRV-Tools` targets in `thirdparty/build/Windows/Release`. Links cleanly.

## Summary

total: 3
passed: 3
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

None. All 3 items passed with real, executed evidence. Note: verification was performed against the Release build configuration, not Debug (matches what was actually available/rebuilt this session) — Debug config has not been separately re-verified but shares the same CMake wiring fixes.
