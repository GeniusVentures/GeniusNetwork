---
phase: 10-capture-harness-diff-tool-quantization-stub
plan: 05
subsystem: infra
tags: [cpp, cmake, cli-tooling, sgprocessingmanager, capture, hashing]

# Dependency graph
requires:
  - phase: "10-01"
    provides: "sgprocmanagerquant identity-stub library + ExecutionContext::rawOutputCapture opt-in callback field"
  - phase: "10-02"
    provides: "6 stitched-family MNN processors offering quantized/pre-quantize bytes to rawOutputCapture at chunk + stitched-combined hash sites"
  - phase: "10-03"
    provides: "7 chained-family MNN processors offering quantized/pre-quantize bytes to rawOutputCapture at chunk hash sites"
  - phase: "10-04"
    provides: "RenderProcessor rawOutputCapture wiring + sgns::sgproccapture::CaptureRecord/CaptureFile binary format (capture_file_format.hpp/.cpp)"
provides:
  - "capture_harness CLI: runs a Phase 09 fixture --repeat N times, self-checks CAPT-02 (re-hashes captured bytes against artifact chunk/content hashes), self-checks CAPT-03/D-04/D-05 (same-node stability across N runs), writes one .cap file only when both pass"
  - "capture_diff CLI: reads two .cap files, reports DIFF-01/02 per-element numeric divergence (abs/rel delta, ULP distance, whole-buffer summary stats) plus DIFF-03 independent hash-match booleans, to console and JSON"
  - "sgproccapture CMake static library wrapping Plan 10-04's capture_file_format.hpp/.cpp, now wired into the real build (previously only verified via an ad-hoc scratch build)"
  - "SGProcessingManager/tools/ and tools/capture/ CMake subdirectories, non-CTest-gated CLI target pattern"
affects: [10-06, phase-11-empirical-cross-machine-capture-run]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Standalone CLI executable (no add_test), hand-rolled argv parser -- no new parsing dependency"
    - "Local, gtest-free copy of processing_conformance_fixture.hpp's PatchJsonUrisToAbsolute regex logic for CLI tooling that isn't a GTest binary"
    - "Ordered-integer bit-reinterpretation ULP distance for float32 (sign-magnitude-to-monotonic transform, computed in int64_t)"

key-files:
  created:
    - SuperGenius/SGProcessingManager/tools/CMakeLists.txt
    - SuperGenius/SGProcessingManager/tools/capture/CMakeLists.txt
    - SuperGenius/SGProcessingManager/tools/capture/capture_harness.cpp
    - SuperGenius/SGProcessingManager/tools/capture/capture_diff.cpp
  modified:
    - SuperGenius/SGProcessingManager/CMakeLists.txt

key-decisions:
  - "capture_diff hard-exits (non-zero, clear message) on any artifacts[0].chunkHashCount mismatch between the two files, before computing DIFF-03 booleans or the DIFF-01/02 numeric pass -- Phase 10's exactly-two-known-fixtures scope means a chunk-count difference indicates an incompatible comparison (different fixture or a structural divergence), not a legitimate numeric one; DIFF-03's chunkHashesMatch loop still uses min(count_a, count_b) defensively per the plan's literal spec, though it is unreachable once counts are gated equal"
  - "capture_diff treats a byte-length mismatch in the two files' final CaptureRecord.quantizedBytes as non-fatal: reports sizeMismatch=true in console+JSON, skips the per-element numeric pass, still reports the three DIFF-03 hash-match booleans, and exits 0 -- matches the plan's explicit 'skip the per-element pass (still report the DIFF-03 hash booleans)' instruction"

requirements-completed: [CAPT-01, CAPT-02, CAPT-03, DIFF-01, DIFF-02, DIFF-03]

coverage:
  - id: D1
    description: "capture_harness runs a fixture N times, independently re-hashes captured bytes against artifact chunk/content hashes (CAPT-02), verifies same-node stability across all N runs (CAPT-03/D-04/D-05), and writes one machine/fixture/timestamp-named .cap file only when both pass"
    requirement: "CAPT-01"
    verification:
      - kind: other
        ref: "cmake --build build/Windows/Debug --target capture_harness --config Debug"
        status: pass
      - kind: other
        ref: "Manual run: capture_harness --fixture-root SuperGenius/test/src --fixture processing_datatypes/float-processing-definition.json --label mnn-float --repeat 3 -> wrote mnn-float_*.cap, '3/3 stable runs, 15 chunk hashes self-checked'"
        status: pass
      - kind: other
        ref: "Manual run: capture_harness --fixture-root SuperGenius/test/src --fixture processing_dispatch/render-pass-happy-path-definition.json --label render-happy-path --repeat 2 --model-input-source input:renderInput --write-render-vertex-fixture -> wrote render-happy-path_*.cap, '2/2 stable runs, 0 chunk hashes self-checked' (render fixture has no chunking, only the trailing combined-level capture)"
        status: pass
    human_judgment: false
  - id: D2
    description: "capture_diff reports DIFF-01/02 per-element numeric divergence (abs/rel delta, ULP distance, whole-buffer max/percent-exceeding-threshold) and DIFF-03 independent hash-match booleans (contentHashMatch/chunkHashesMatch/combinedHashMatch) to both console and a JSON report; identical-byte capture files report 0 divergence and all-true booleans (ROADMAP Success Criterion 3)"
    requirement: "DIFF-01"
    verification:
      - kind: other
        ref: "cmake --build build/Windows/Debug --target capture_diff --config Debug"
        status: pass
      - kind: other
        ref: "Manual run: capture_diff on two capture_harness runs of the identical mnn-float fixture -> contentHashMatch=true, combinedHashMatch=true, chunkHashesMatch=[true x15], elementCount=512, maxAbsDelta=0, maxRelDelta=0, maxUlpDistance=0, percentExceedingThreshold=0%; diff_report.json written with matching fields"
        status: pass
    human_judgment: false

# Metrics
duration: 25min
completed: 2026-08-10
status: complete
---

# Phase 10 Plan 05: Capture Harness & Diff Tool CLIs Summary

**Built `capture_harness` (runs a fixture N times, self-checks CAPT-02/CAPT-03, writes a `.cap` file) and `capture_diff` (reports DIFF-01/02 numeric divergence plus DIFF-03 hash-match booleans to console+JSON), wired into a new non-CTest-gated `tools/` CMake tree -- Phase 10's literal deliverable.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-08-10T19:39:19Z
- **Completed:** 2026-08-10T19:59:40Z
- **Tasks:** 2
- **Files modified:** 5 (4 created, 1 modified)

## Accomplishments

- `capture_harness` hand-rolls its own `argv` parser (`--fixture-root`, `--fixture`, `--label`, `--repeat` default 3 reject <2, `--output-dir`, `--model-input-source`, `--write-render-vertex-fixture`), a local gtest-free copy of `PatchJsonUrisToAbsolute`, and per-iteration model-node resolution matching `output_hashing_test.cpp`'s MNN pattern (`passes[0].get_model().value().get_input_nodes()[0]`) and `processing_dispatch_test.cpp`'s render pattern (`ModelNode::set_source`)
- Calls the 5-arg `ProcessingManager::Process()` overload with an `ExecutionContext` whose `rawOutputCapture` accumulates `CaptureRecord`s, then runs the CAPT-02 self-check (independently re-hashes every captured chunk/trailing-combined buffer and compares against `artifacts[0].chunkHashes`/`contentHash`) and the CAPT-03/D-04/D-05 stability check (compares iteration 0's `contentHash`/`chunkHashes`/`combinedHash` against every other iteration) -- aborting with no file written if either fails
- On success, builds a `sgns::sgproccapture::CaptureFile` (machine-identity tag = hostname + compile-time OS name per D-03, fixture label, artifact, capture records, manifest, combined hash) and writes it via `SerializeCaptureFile` to `<label>_<sanitized-machine-tag>_<UTC-timestamp>.cap` (D-02 naming)
- `capture_diff` deserializes two `.cap` files, computes DIFF-03's three hash-match booleans purely from artifact/manifest metadata, then reinterprets the final `CaptureRecord.quantizedBytes` per `--element-type` (`float32` or `uint8`) to compute per-element absolute delta, relative delta (with a `1e-6f` denominator floor), and ULP distance (standard ordered-integer bit-reinterpretation for floats, raw delta for bytes), reducing to whole-buffer `maxAbsDelta`/`maxRelDelta`/`maxUlpDistance`/`percentExceedingThreshold` against fixed named thresholds (`kDefaultFloatRelativeThreshold = 1e-4`, `kDefaultByteAbsoluteThreshold = 1`, per D-07)
- New `sgproccapture` CMake static library wraps Plan 10-04's `capture_file_format.hpp/.cpp` (previously verified only via an ad-hoc, uncommitted scratch build) into the real build for the first time, linked against `sgprocmanagersha` + `SGArtifacts`
- New `tools/` and `tools/capture/` CMake subdirectories wired via `add_subdirectory(tools)`; neither `capture_harness` nor `capture_diff` is registered with `add_test()` (Pattern 5 -- a meaningful cross-machine pass/fail needs Phase 11's physical machines)
- End-to-end smoke-tested both fixtures: MNN float fixture (3 self-checked, stable runs; 15 chunk hashes) and the render happy-path fixture (2 self-checked, stable runs; 0 chunk hashes -- render has no chunking, only the trailing combined-level capture, exercising the CAPT-02 self-check's "size == chunkHashCount + 1" branch); `capture_diff`-ing two independent `mnn-float` runs of the identical fixture reported 0 divergence across every metric and `true` for every hash-match boolean, matching ROADMAP Success Criterion 3 exactly

## Task Commits

Each task was committed atomically in the `SGProcessingManager` submodule (branch `dev_rendering`):

1. **Task 1: Build capture_harness.cpp + tools/CMakeLists.txt + tools/capture/CMakeLists.txt** - `f759d7e` (feat)
2. **Task 2: Build capture_diff.cpp** - `ea0c064` (feat)

_Note: commits landed in the nested `SGProcessingManager` git submodule (`W:\gnus\GeniusNetwork\SuperGenius\SGProcessingManager`), not the top-level repo or the `SuperGenius` submodule pointer directly -- consistent with Plans 10-01 through 10-04's precedent._

## Files Created/Modified

- `SuperGenius/SGProcessingManager/CMakeLists.txt` - Added `add_subdirectory(tools)` after the existing `add_subdirectory(src)`
- `SuperGenius/SGProcessingManager/tools/CMakeLists.txt` - New: `add_subdirectory(capture)`
- `SuperGenius/SGProcessingManager/tools/capture/CMakeLists.txt` - New: `sgproccapture` static library (wraps Plan 10-04's `capture_file_format.hpp/.cpp`), `capture_harness` and `capture_diff` executables (no `add_test()` for either)
- `SuperGenius/SGProcessingManager/tools/capture/capture_harness.cpp` - New: CLI that runs a fixture `--repeat N` times, self-checks CAPT-02/CAPT-03, writes a `.cap` file
- `SuperGenius/SGProcessingManager/tools/capture/capture_diff.cpp` - New: CLI that compares two `.cap` files, reports DIFF-01/02/03 to console + JSON

## Decisions Made

- `capture_diff` hard-exits (non-zero, distinct error message) on any `chunkHashCount` mismatch between the two compared files, treating it as an incompatible-comparison failure mode rather than degrading gracefully via `min(count_a, count_b)` -- consistent with the plan's literal "exit non-zero...if...chunkHashCount values differ in a way that makes comparison meaningless" instruction, since Phase 10's scope is exactly two known, deterministic fixtures where any count difference indicates a structural mismatch, not legitimate divergence data
- `capture_diff` treats a byte-length mismatch in the two files' final `quantizedBytes` buffers as non-fatal (reports `sizeMismatch: true`, skips only the numeric pass, still reports hash-match booleans, exits 0) per the plan's explicit "skip the per-element pass (still report the DIFF-03 hash booleans)" instruction

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added SGProcessingManager-root include directory to the `sgproccapture` CMake target**
- **Found during:** Task 1 (initial build of `capture_harness`)
- **Issue:** Plan 10-04's `capture_file_format.cpp` includes its own header via the root-relative path `"tools/capture/capture_file_format.hpp"` (verified only through an ad-hoc scratch build in Plan 10-04, never through the real CMake target). The plan's literal `tools/capture/CMakeLists.txt` spec for `sgproccapture` only added `../../include` as an include directory, which does not contain a `tools/` subtree -- the real CMake build failed with `C1083: Cannot open include file: 'tools/capture/capture_file_format.hpp'`.
- **Fix:** Added a second `target_include_directories(sgproccapture PUBLIC ...)` entry pointing at the `SGProcessingManager` root (`${CMAKE_CURRENT_SOURCE_DIR}/../..`), so the root-relative include resolves.
- **Files modified:** `SuperGenius/SGProcessingManager/tools/capture/CMakeLists.txt`
- **Verification:** `cmake --build build/Windows/Debug --target capture_harness --config Debug` and `--target capture_diff` both succeed with zero errors/warnings after the fix.
- **Committed in:** `f759d7e` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking build-config fix)
**Impact on plan:** Necessary to make Plan 10-04's already-designed binary format actually buildable through the real CMake tree for the first time. No scope creep -- the fix is confined to one CMakeLists.txt include-directory line.

## Issues Encountered

- The render happy-path fixture copied into `build/Windows/Debug/test_bin/Debug/processing_dispatch/render-pass-happy-path-definition.json` is a stale build artifact predating Plan 09-15's fix (which gave the *source* fixture at `SuperGenius/test/src/processing_dispatch/render-pass-happy-path-definition.json` a real `outputs[0]` entry; the copied build-dir version still has `"outputs": []` because the CMake custom command that refreshes it is tied to the `processing_dispatch_test` CTest target, which this plan's build did not rebuild). Running `capture_harness` with `--fixture-root` pointed at the stale build-dir copy produced a successful `Process()` call with zero artifacts (silently no-op since `ProcessingManager.cpp` only builds artifacts when `!outputs.empty()`). Re-ran with `--fixture-root` pointed at the real source tree (`SuperGenius/test/src`) -- exactly what the plan's own `<verification>` section already specifies (`--fixture-root <path-to-SuperGenius/test/src>`) -- and the render fixture then produced a correct, self-checked, stable 2-run capture with 0 chunk hashes as expected. No code change was needed; this was purely a smoke-test fixture-root choice, not a bug in `capture_harness`. The two `--write-render-vertex-fixture`-generated files this produced in the source tree (`happy-path-vertex-data.raw`, `happy-path-render-output.raw`) were deleted after verification to leave the working tree clean.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

`capture_harness` and `capture_diff` are both built, wired into the real CMake tree, and smoke-tested end-to-end against both Phase 09 fixtures on this machine. Phase 11 (Empirical Cross-Machine Capture Run) can now use these two CLIs, as-is, on the user's Mac + PC + a third machine -- no further tooling work is required before that phase's manual capture/copy/diff workflow can begin. No blockers identified.

---
*Phase: 10-capture-harness-diff-tool-quantization-stub*
*Completed: 2026-08-10*

## Self-Check: PASSED

- FOUND: SuperGenius/SGProcessingManager/tools/CMakeLists.txt
- FOUND: SuperGenius/SGProcessingManager/tools/capture/CMakeLists.txt
- FOUND: SuperGenius/SGProcessingManager/tools/capture/capture_harness.cpp
- FOUND: SuperGenius/SGProcessingManager/tools/capture/capture_diff.cpp
- FOUND: .planning/workstreams/sgproc-render/phases/10-capture-harness-diff-tool-quantization-stub/10-05-SUMMARY.md
- FOUND: commit f759d7e (SGProcessingManager submodule)
- FOUND: commit ea0c064 (SGProcessingManager submodule)
