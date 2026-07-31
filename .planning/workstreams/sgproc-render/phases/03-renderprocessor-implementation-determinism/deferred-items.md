# Phase 3 Deferred Items

## DI-03-01-01: `RenderPassValidGlslShadersCompileAndValidateEndToEnd` fails pre-existing, out of scope for plan 03-01

**Discovered during:** Plan 03-01, Task 2 verification (running `processing_dispatch_test.exe --gtest_filter="*RenderPass*"` as this working tree's first full end-to-end link+run of this suite).

**Symptom:** The test asserts `Process()` fails with `INPUT_UNAVAIL` (proving both real GLSL stages compiled+validated successfully before the genuinely-missing render input is reached), but it actually fails with `SHADER_COMPILE_FAILED`. The `ShaderCompiler` log shows `GLSL compile failed: shader: error: #version: Desktop shaders for Vulkan SPIR-V require version 140 or higher` — despite both fixture shaders (`dummy_shader.glsl`/`dummy_fragment_shader.glsl`) declaring `#version 450`. Preceding log lines (`Failed to obtain processing source: File could not be opened` x3, `FILECommon: Failed to open file (Windows): The system cannot find the path specified`) indicate the `file://processing_dispatch/dummy_shader.glsl`/`dummy_fragment_shader.glsl` fixture URLs are not resolving in this test run's working directory, so an empty buffer (falling back to a `#version 110`-equivalent default) is what's actually reaching `shaderc`, not the real fixture GLSL source.

**Root cause hypothesis (not confirmed/fixed this plan):** A working-directory-relative fixture-path resolution gap in the test's `file://` URL fetch path, unrelated to plan 03-01's wire-format/error-field work.

**Confirmed out of scope for plan 03-01:** Verified by stashing Task 2's edits and re-running the same test against Task-1-only state — the identical failure (same enum value, same log messages) reproduces byte-for-byte. This proves plan 03-01's `SerializeCompiledStages`/`Process()` gate changes do not cause, alter, or interact with this failure; it predates this plan's changes and is very likely also present on `dev_rendering`'s prior HEAD (`af18dd1`), just never surfaced because a full MSBuild link+run of this suite had not previously been executed in this working tree (per STATE.md's carried-forward Blocker).

**Status:** Deferred — not fixed. Other 5/6 `*RenderPass*` tests pass unchanged. Recommend investigating the `file://processing_dispatch/...` fixture-fetch working-directory assumption early in a subsequent 03-0X plan (e.g. during 03-02/03-03's own build+test verification), since later plans' own render-pass fixtures will hit the same resolution path.
