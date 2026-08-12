---
phase: 12-quantization-normalization-implementation
plan: 02
subsystem: processing
tags: [secv-01, counter-test, ctest, mnn, render, vulkan, quantization, cross-hardware-tolerance]

# Dependency graph
requires:
  - phase: 12-quantization-normalization-implementation
    provides: "Plan 12-01's real QuantizeFloatBuffer/QuantizeByteBuffer bodies -- without these, both counter-test cases would trivially pass against the Phase 10 identity stub without proving anything about the real, tightened tolerance"
provides:
  - "New CTest target processing_conformance_security_test (2 TEST_F cases) proving a corrupted MNN model and a wrong render shader constant both still produce a different post-quantization artifactId than the correct result"
  - "SECV-01 counter-test fixtures: secv01-wrong-color.frag, secv01-corrupted-float_model.mnn"
affects: [13-re-validation-scope-boundary-documentation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Binary std::memcmp != 0 on output.artifacts[0].artifactId only (D-13) -- no secondary magnitude/divergence-threshold check, never on combinedHash or ExecutionManifest fields"
    - "Deliberately-wrong fixture pattern: byte-perturbed model / mismatched-but-well-formed shader constant, run through the exact same real pipeline shape as the correct result, to prove tolerance is not too loose"
    - "pipeline_state: {topology: point_list, ...} required to guarantee actual fragment rasterization in inline render job JSON literals -- the default TRIANGLE_LIST topology with arbitrary vertex data can silently produce zero visible fragments, making a fragment-shader-only counter-test vacuous"

key-files:
  created:
    - SuperGenius/test/src/processing_conformance_security/secv01_counter_test.cpp
    - SuperGenius/test/src/processing_conformance_security/CMakeLists.txt
    - SuperGenius/test/src/processing_conformance_security/fixtures/secv01-wrong-color.frag
    - SuperGenius/test/src/processing_conformance_security/fixtures/secv01-corrupted-float_model.mnn
  modified:
    - SuperGenius/test/src/CMakeLists.txt

key-decisions:
  - "secv01-corrupted-float_model.mnn uses a single-byte XOR-0xFF flip at offset 15360 (the first offset tried, per the plan's ordered fallback list) -- empirically confirmed to still load via MNN::Interpreter and to produce a materially different inference result than the original"
  - "Both render job JSON literals gained an explicit pipeline_state (topology: point_list, cull_mode: none, depth_test: disabled) not specified in the plan's literal action text -- required because the plan's as-written shape (mirroring cancellation_conformance_test.cpp's never-actually-completing pre-cancelled render job) defaults to TRIANGLE_LIST topology, which produced zero visible fragments for float_input.bin's arbitrary vertex data, making both runs hash the identical clear-color-only output regardless of fragment shader"

patterns-established:
  - "Before trusting an existing test's JSON shape as a 'proven' reference for a new happy-path test, confirm that test actually reaches a successful Process() completion (not just Create()+cancel) -- cancellation_conformance_test.cpp's render job was structurally valid but never exercised past pre-cancellation, so its shape alone did not guarantee visible rasterization"

requirements-completed: [SECV-01]

coverage:
  - id: D1
    description: "A byte-perturbed copy of float_model.mnn, run through the same MNN float pipeline shape as float-processing-definition.json, produces a post-quantization artifactId that differs from the correct model's artifactId"
    requirement: "SECV-01"
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/processing_conformance_security/secv01_counter_test.cpp#Secv01CounterTest.MnnCorruptedModelStillDiverges"
        status: pass
    human_judgment: false
  - id: D2
    description: "A render job whose fragment shader outputs a different constant color than passthrough.frag, run through the same render pipeline, produces a post-quantization artifactId that differs from the correct shader's artifactId"
    requirement: "SECV-01"
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/processing_conformance_security/secv01_counter_test.cpp#Secv01CounterTest.RenderWrongShaderConstantStillDiverges"
        status: pass
    human_judgment: false
  - id: D3
    description: "Both counter-test cases live in one new CTest target that runs automatically under ctest in CI, not a standalone manual tool"
    requirement: "SECV-01"
    verification:
      - kind: unit
        ref: "ctest --test-dir SuperGenius/build/Windows/Debug -C Debug -R processing_conformance_security_test --output-on-failure"
        status: pass
    human_judgment: false

duration: 35min
completed: 2026-08-12
status: complete
---

# Phase 12 Plan 2: SECV-01 wrong-result-still-diverges counter-test Summary

**New `processing_conformance_security_test` CTest target proves, for both the MNN inference path and the render path, that a deliberately corrupted/wrong result still produces a different post-quantization artifact hash than the correct result -- confirming Plan 12-01's real quantization tolerance is not loose enough to also mask a substituted model or shader constant.**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-08-12T02:18Z
- **Tasks:** 2
- **Files modified:** 5 (4 created, 1 modified)

## Accomplishments

- `secv01-wrong-color.frag`: a deliberately-wrong fragment shader fixture, structurally identical to `passthrough.frag` (`#version 450`, single `out vec4 outColor`, `main()`) but outputting solid mid-gray `vec4(0.5, 0.5, 0.5, 1.0)` instead of solid white -- referenced with `"type": "glsl"` so it is compiled and spirv-val-validated at test runtime by the real `ShaderCompiler`.
- `secv01-corrupted-float_model.mnn`: a byte-perturbed copy of `float_model.mnn` -- a single byte at offset 15360 (in the Linear layers' weight-tensor region) XORed with `0xFF`. Empirically confirmed loadable end-to-end through the real MNN inference path and produces a materially different output than the original on the same 512-float input.
- `secv01_counter_test.cpp`: new `Secv01CounterTest` fixture (extends `ProcessorConformanceFixture`) with two `TEST_F` cases:
  - `MnnCorruptedModelStillDiverges`: builds two inline job JSON literals shaped like `float-processing-definition.json`, differing only in which `.mnn` file the model points at (correct vs. Task 1's corrupted copy); asserts `std::memcmp` on `.artifacts[0].artifactId` is non-zero.
  - `RenderWrongShaderConstantStillDiverges`: builds two inline render job JSON literals, differing only in the fragment stage (correct precompiled `passthrough.frag.spv` vs. Task 1's `secv01-wrong-color.frag` GLSL source); `GTEST_SKIP()`s on hosts with no usable Vulkan device (Phase 09 D-05 pattern); asserts the same binary `artifactId` inequality.
- New `processing_conformance_security_test` CTest target registered via `add_subdirectory(processing_conformance_security)` in `test/src/CMakeLists.txt`, alongside the existing Phase 09 `processing_conformance_*` suites.
- Both new `TEST_F` cases pass on a machine with a real Vulkan-capable GPU (NVIDIA GeForce RTX 4070 Ti SUPER); the MNN case has no GPU dependency and always runs.

## Task Commits

Each task was committed atomically, respecting the nested-submodule commit order (SuperGenius first, then the top-level GeniusNetwork pointer -- this plan's files live directly in the SuperGenius submodule, with no SGProcessingManager-level changes):

1. **Task 1: Author the two corrupted-result fixtures**
   - `1c16248b` (SuperGenius, test): add SECV-01 counter-test fixtures (`secv01-wrong-color.frag`, `secv01-corrupted-float_model.mnn`)
   - `37f27b6` (GeniusNetwork, chore): bump SuperGenius pointer
2. **Task 2: Write the SECV-01 counter-test suite + CTest registration**
   - `5538b606` (SuperGenius, test): add SECV-01 wrong-result-still-diverges counter-test (`secv01_counter_test.cpp`, `CMakeLists.txt`, `test/src/CMakeLists.txt`)
   - `c1040cb` (GeniusNetwork, chore): bump SuperGenius pointer

**Plan metadata:** (this commit, docs: complete plan -- created after this SUMMARY)

## Files Created/Modified

- `SuperGenius/test/src/processing_conformance_security/fixtures/secv01-wrong-color.frag` - New: deliberately-wrong solid mid-gray fragment shader fixture (D-11)
- `SuperGenius/test/src/processing_conformance_security/fixtures/secv01-corrupted-float_model.mnn` - New: byte-perturbed copy of `float_model.mnn` (D-10), single byte flipped at offset 15360
- `SuperGenius/test/src/processing_conformance_security/secv01_counter_test.cpp` - New: `Secv01CounterTest` fixture, two `TEST_F` cases
- `SuperGenius/test/src/processing_conformance_security/CMakeLists.txt` - New: `addtest()` + fixture-copy `POST_BUILD` command, mirroring `processing_conformance_regression/CMakeLists.txt`'s shape
- `SuperGenius/test/src/CMakeLists.txt` - Added `add_subdirectory(processing_conformance_security)`

## Decisions Made

- Task 1's fixture offset search: tried offset 15360 first (per the plan's ordered fallback list) and it worked on the first attempt -- confirmed via the actual `MnnCorruptedModelStillDiverges` run (the real end-to-end MNN load+inference path), not a separate standalone MNN harness. No fallback offsets (18000/12000/10000) were needed.
- **Render job JSON needed an explicit `pipeline_state`** (`{"topology": "point_list", "cull_mode": "none", "front_face": "ccw", "depth_test": "disabled"}`) added to both the correct and wrong-color render job literals. The plan's action text specified mirroring `cancellation_conformance_test.cpp`'s `RenderCancelBeforeStartProducesNoSuccessfulResult` render job shape, which omits `pipeline_state` entirely (defaulting to `TRIANGLE_LIST` topology). That job was never actually exercised past pre-cancellation in its original test, so its shape was never proven to produce a visible rendered image. With the default topology and `float_input.bin`'s arbitrary vertex data (not designed for rendering), both the correct and wrong-color runs produced bit-identical `artifactId`s -- both had rasterized zero fragments, so the render target stayed at its `clear_color` in both cases regardless of which fragment shader was configured, making the counter-test vacuously pass-proof rather than a real proof. Added the `point_list` topology (mirroring `processing_dispatch_test.cpp`'s already-proven `render-pass-happy-path-definition.json` pattern) to guarantee at least one rasterized point per run; confirmed via the actual test run that both artifactIds now differ as required. Classified as Rule 1 (auto-fix bug) -- the as-written shape produced an accidentally-vacuous test, not a deliberate design choice.
- Also attempted adding `"format": "FLOAT32"` to the render job's `vertexData` buffer input to silence a `SGProcessingManager` warning ("Buffer input missing format; defaulting to INT8"); reverted immediately after `ProcessingManager::Create()` rejected it with "Buffer type supports INT8 format only" -- the `buffer` input type's schema only accepts `INT8`, so the warning is benign and the field was left unset, matching `cancellation_conformance_test.cpp`'s existing pattern.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Render job JSON needed `pipeline_state.topology: point_list` to actually rasterize fragments**
- **Found during:** Task 2, first `ctest` run of `RenderWrongShaderConstantStillDiverges`
- **Issue:** The plan's action text specified mirroring `cancellation_conformance_test.cpp`'s render job JSON shape verbatim (default `TRIANGLE_LIST` topology, no `pipeline_state`). That reference test never actually completed a real render (pre-cancelled before `Process()` ran), so the shape was unproven. With `float_input.bin`'s vertex data and default topology, zero fragments were rasterized in either run, and both the correct (`passthrough.frag.spv`) and wrong-color (`secv01-wrong-color.frag`) runs produced bit-identical `artifactId`s -- the counter-test passed the build but was not actually testing anything, since the fragment shader that differed was never invoked.
- **Fix:** Added `"pipeline_state": {"topology": "point_list", "cull_mode": "none", "front_face": "ccw", "depth_test": "disabled"}` to both render job JSON literals, mirroring the already-proven-working `render-pass-happy-path-definition.json`/`processing_dispatch_test.cpp` pattern. Re-ran the test; confirmed the corrected and wrong-color `artifactId`s now differ.
- **Files modified:** `SuperGenius/test/src/processing_conformance_security/secv01_counter_test.cpp`
- **Commit:** `5538b606`

### None Other

No other deviations. Task 1's fixture creation (fixture content, byte-flip offset, empirical load verification) followed the plan's action steps exactly, including succeeding on the plan's first-listed offset (15360) without needing any of the three ordered fallback offsets.

## Issues Encountered

- This build environment's `cmake` reconfigure reported "Could NOT find Vulkan (missing: Vulkan_INCLUDE_DIR)" during CMake configuration, but a real Vulkan-capable device (NVIDIA GeForce RTX 4070 Ti SUPER) was still enumerated and usable at runtime (the Vulkan loader/runtime is present even though the CMake `find_package(Vulkan)` include-dir probe failed) -- both render-dependent `TEST_F` cases ran to completion rather than skipping via `GTEST_SKIP()`. Pre-existing environment quirk, not caused by this plan's changes; not investigated further since it did not block verification.
- `processing_conformance_regression_test` had not yet been built in this build directory (only `processing_conformance_security_test`'s own build was initially run), which meant the shared `test_bin/Debug/processing_conformance_regression/fixtures/` nested-path copy (containing `passthrough.vert.spv`/`passthrough.frag.spv`) did not yet exist when the security suite's correct-render case tried to load them. Built `processing_conformance_regression_test` once to populate that shared fixture directory (no source changes); this is expected first-time-build behavior for this shared `test_bin/Debug/` output directory convention, not a bug.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- SECV-01 is now closed for both the MNN and render paths, satisfying the milestone's central non-optional risk item flagged by research and 12-CONTEXT.md: Plan 12-01's real quantization tolerance is proven loose enough to absorb genuine cross-machine floating-point noise (Phase 11 data) AND tight enough to reject a substituted model or shader constant.
- Phase 12 (quantization-normalization-implementation) is now complete: Plan 12-01 (real quantization + hash-agreement proof) and Plan 12-02 (SECV-01 counter-test) both done.
- No files touched by this plan modified `ComputeManifestHash`, `ExecutionManifest`, `executorIdentity`, or `gpuMemoryUsedBytes` -- confirmed via `git show` diff inspection on both SuperGenius commits (`1c16248b`, `5538b606`); D-01/D-02's scope boundary is intact. Neither new `TEST_F` case reads or asserts on `.combinedHash`.
- No blockers for Phase 13 (Re-Validation & Scope Boundary Documentation).

---
*Phase: 12-quantization-normalization-implementation*
*Completed: 2026-08-12*

## Self-Check: PASSED

All 4 created files and 1 modified file confirmed present on disk with expected content; all 4 commit hashes (1c16248b, 37f27b6, 5538b606, c1040cb) confirmed present in their respective repos' git logs.
