---
phase: 15-validation-comparison-mechanism
plan: 04
subsystem: infra
tags: [c++, ctest, gtest, secv02, processing_conformance_security, cross-node-validation, full-pipeline-test]

# Dependency graph
requires:
  - phase: 15-03 (real-io-and-schema-wiring)
    provides: SubTaskQueueAccessorImpl threading a ProcessingCore reference into FinalizeQueueProcessing, real job-schema quantScale/byteQuantMode resolution, real FileManager-backed IPFS fetches on a hash mismatch
provides:
  - Secv02CounterTest.CorruptedSubtaskResultStillCaughtBySubTaskQueueAccessor -- the phase's final, mandatory full-pipeline proof that the fixed ValidateResults (XNODE-01b) plus its tolerance fallback (XNODE-02) acting together still catch a deliberately corrupted subtask result, reached exclusively via SubTaskQueueAccessorImpl's real public API
  - fixtures/secv02-corrupted-float_model.mnn -- a new, dedicated corrupted-model fixture for the single-window (width=64/block_len=64) granularity this test requires
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: ["Real two-job ProcessingManager::Process() pipeline feeding synthetic SGProcessing::SubTask/SubTaskResult objects built via ProcessTaskSplitter::SplitTask's real addvalidationsubtask=true code path, exercised through SubTaskQueueAccessorImpl's public AssignSubTasks/GrabSubTask API instead of a direct ValidateResults call (D-05)"]

key-files:
  created:
    - SuperGenius/test/src/processing_conformance_security/secv02_counter_test.cpp
    - SuperGenius/test/src/processing_conformance_security/fixtures/secv02-corrupted-float_model.mnn
  modified:
    - SuperGenius/test/src/processing_conformance_security/CMakeLists.txt

key-decisions:
  - "Created a NEW corrupted-model fixture (secv02-corrupted-float_model.mnn) instead of reusing SECV-01's secv01-corrupted-float_model.mnn as the plan's literal text specified, because SECV-01's fixture was empirically confirmed to produce a bit-identical post-quantization chunk hash to the correct model at the single-window (width=64/block_len=64) granularity this test requires -- its real divergence only manifests once stitched across all 15 of SECV-01's own overlapping windows."
  - "Gave the two jobs distinct output filenames (float_output.raw vs float_output_corrupted.raw) -- unlike secv01_counter_test.cpp, which never re-reads its saved files, this test later fetches both runs' saved outputs by URI (D-01), so reusing the same output path would let the second run's save silently overwrite the first's before the fetch ever happens."

patterns-established: []

requirements-completed: [SECV-02]

coverage:
  - id: D1
    description: "A deliberately corrupted subtask result, run through a real ProcessingManager::Process() pipeline and fed through SubTaskQueueAccessorImpl's real public API, is still caught as invalid by the fixed ValidateResults plus tolerance fallback acting together"
    requirement: "SECV-02"
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_security/secv02_counter_test.cpp#Secv02CounterTest.CorruptedSubtaskResultStillCaughtBySubTaskQueueAccessor"
        status: pass
    human_judgment: false
  - id: D2
    description: "The tolerance-fallback fetch+diff mechanism is exercised for real (genuine FileManager::LoadASync fetch of real file:// output data), not a trivially-absent-capability path"
    requirement: "SECV-02"
    verification:
      - kind: unit
        ref: "Test asserts ipfs_results_data_id is set to real Process()-written file:// output locations for both subtask results, and errorFired/errorMessage confirm the mismatch was resolved via AttemptToleranceFallback's real fetch+diff path, not the no-fetchOutputData fail-closed path"
        status: pass
    human_judgment: false
  - id: D3
    description: "Two subtasks sharing one chunk are produced via ProcessTaskSplitter::SplitTask's real addvalidationsubtask=true code path, not hand-built protobuf objects"
    requirement: "SECV-02"
    verification:
      - kind: unit
        ref: "grep -c \"SplitTask(\" secv02_counter_test.cpp == 1, 5th argument literally true; ASSERT_EQ on both subtasks' chunkstoprocess(0).SerializeAsString() confirming the identical shared ProcessingChunk"
        status: pass
    human_judgment: false
  - id: D4
    description: "ctest -R processing_conformance_security_test passes (registered CTest target name, not the GTest suite name), including the new Secv02CounterTest case alongside SECV-01's existing cases"
    requirement: "SECV-02"
    verification:
      - kind: unit
        ref: "ctest --test-dir SuperGenius/build/Windows/Debug -C Debug -R processing_conformance_security_test -V (4/4 tests passed: Secv01CounterTest x2, Secv01Tex3dCounterTest, Secv02CounterTest)"
        status: pass
    human_judgment: false
  - id: D5
    description: "No regression in adjacent processing test targets"
    requirement: "SECV-02"
    verification:
      - kind: unit
        ref: "ctest --test-dir SuperGenius/build/Windows/Debug -C Debug -R \"processing_validation_core_test|task_queue_test|processing_result_durability_test|processing_validate_result_data_test\" -V (4/4 targets, 100% passed)"
        status: pass
    human_judgment: false

# Metrics
duration: 65min
completed: 2026-08-14
status: complete
---

# Phase 15 Plan 4: SECV-02 Full-Pipeline Counter-Test Summary

**A new `Secv02CounterTest` proves, end-to-end, that a deliberately corrupted MNN subtask result -- run through a real `ProcessingManager::Process()` pipeline and reached exclusively via `SubTaskQueueAccessorImpl`'s real public API -- is still caught as invalid by the fixed `ValidateResults` plus its tolerance fallback (Plans 15-01/15-02/15-03) acting together.**

## Performance

- **Duration:** ~65 min (including empirical fixture-divergence diagnosis)
- **Completed:** 2026-08-14
- **Tasks:** 1
- **Files modified:** 3 (2 new, 1 edited)

## Accomplishments

- Built `Secv02CounterTest.CorruptedSubtaskResultStillCaughtBySubTaskQueueAccessor`: two real `ProcessingManager::Create()`/`Process()` runs (correct `float_model.mnn` vs. a corrupted model), each producing genuine `chunkhashes` and `outputLocations` from the real MNN + quantization + hashing pipeline -- no fabricated hash strings.
- Built the shared "two subtasks, one chunk" scenario via `ProcessTaskSplitter().SplitTask(..., numchunks=1, addvalidationsubtask=true, ...)`, the real production code path (never hand-built protobuf objects): the first subtask gets a real generated UUID, the second is literally `"subtask_validation"`, both referencing the identical `ProcessingChunk`.
- Attached the two runs' real chunk hashes and real `file://` output locations to two `SGProcessing::SubTaskResult` objects, then fed them through `SubTaskQueueAccessorImpl`'s real public API: `AssignSubTasks` (→ `ProcessingSubTaskQueueManager::CreateQueue`), `SubTaskResultStorageMock::AddSubTaskResult` (direct storage injection, mirroring the plan's specified construction), then `GrabSubTask` -- which internally runs `UpdateResultsFromStorage`, confirms `IsProcessed()`, and calls the real, fixed `FinalizeQueueProcessing` → `ValidateResults` → `AttemptToleranceFallback` (real `FileManager::LoadASync` fetch of both on-disk outputs, real `ComputeFloat32Diff`).
- Used a locally-constructed `sgns::test::ProcessingCoreImpl` mock whose inherited `ProcessingCore::GetTaskQueue()` returns `nullptr` (the mock never overrides it) -- deliberately exercising Plan 15-01's D-04 fixed-constant tolerance fallback (`kDefaultFloatRelativeThreshold = 1e-4`), the loosest legitimate configuration and the strongest form of this proof.
- Asserted `errorFired == true` and the captured `processingErrorSink` message equals exactly `"Invalid results for the entire task"`, proving the deliberately corrupted result was caught by the combined fixed-comparison + tolerance-fallback mechanism.
- Wired `secv02_counter_test.cpp` into the existing `processing_conformance_security_test` CTest target; added `processing_service` (transitively brings `SubTaskQueueAccessorImpl`/`ProcessingSubTaskQueueManager`/`SGProcessingProto`) plus `ipfs-bitswap-cpp`/`logger`/`Boost::headers`/`p2p::p2p_logger`/`ipfs-pubsub` to its link libraries (needed once `processing_subtask_queue_accessor_impl.hpp` is included directly -- mirroring `processing_result_durability_test`'s existing link set in `test/src/processing/CMakeLists.txt`).

## Task Commits

Committed atomically at the `SuperGenius` submodule layer, mirroring Plans 15-02/15-03's exact commit-layering pattern:

1. **Task 1: Create secv02_counter_test.cpp and wire it into processing_conformance_security_test** -- `SuperGenius@e99f749e` (feat)

**Submodule pointer bump:**
- `GeniusNetwork@27297d4` (chore: bump SuperGenius pointer, Task 1)

**Plan metadata:** captured in a separate final commit (docs: complete plan)

## Files Created/Modified

- `SuperGenius/test/src/processing_conformance_security/secv02_counter_test.cpp` - New: the full-pipeline SECV-02 counter-test
- `SuperGenius/test/src/processing_conformance_security/fixtures/secv02-corrupted-float_model.mnn` - New: dedicated corrupted-model fixture for the single-window scope (see Deviations)
- `SuperGenius/test/src/processing_conformance_security/CMakeLists.txt` - Added `secv02_counter_test.cpp` to `processing_conformance_security_test`'s sources, and `processing_service`/`ipfs-bitswap-cpp`/`logger`/`Boost::headers`/`p2p::p2p_logger`/`ipfs-pubsub` to its link libraries

## Decisions Made

- Created a new corrupted-model fixture (`secv02-corrupted-float_model.mnn`) rather than reusing SECV-01's `secv01-corrupted-float_model.mnn` as the plan's literal action text specified (see Deviations below for the full empirical finding).
- Gave the correct and corrupted jobs distinct output filenames (`float_output.raw` vs. `float_output_corrupted.raw`) since this test, unlike `secv01_counter_test.cpp`, re-fetches both runs' saved output files by URI later -- reusing the same path would let the second run silently overwrite the first's file before the fetch happens.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug in test design] SECV-01's existing corrupted-model fixture does not diverge at the single-window granularity this plan specifies**

- **Found during:** Task 1, first test run
- **Issue:** The plan's action text instructed reusing `secv01-corrupted-float_model.mnn` (a single-byte flip at offset 15360) with `"width": 64, "block_len": 64` (one non-overlapping window). Empirically, this exact fixture produces a **bit-identical** post-quantization SHA-256 chunk hash to the correct model for this specific single-window (offset 0, length 64) computation -- the real divergence SECV-01 proves only manifests once stitched across all 15 of SECV-01's own overlapping windows (`width=512, block_len=64, chunk_stride=32`). Using it as specified would have made this test vacuous (an `ASSERT_NE` precondition on the two runs' chunk hashes failed on the first attempt).
- **Fix:** Created a new, dedicated fixture (`secv02-corrupted-float_model.mnn`) using the exact same "byte-perturbed copy, empirically verified in-place" methodology as SECV-01's own Phase 12 Task 1 fixture-creation step: 100 consecutive 4-byte-aligned floats' most-significant byte (sign+exponent) starting at the same weight-region offset (15360) are XORed with `0xFF`. Confirmed via the test itself that the corrupted model still loads via `MNN::Interpreter` (`ASSERT_TRUE` on both `Create()` and `Process()`) and produces a genuinely different post-quantization window-0 chunk hash from the correct model.
- **Files modified:** `secv02_counter_test.cpp` (JSON model URI references), new `fixtures/secv02-corrupted-float_model.mnn`
- **Commit:** `SuperGenius@e99f749e`

**2. [Rule 1 - Bug in test design] Both jobs' declared output path collided, masking any real divergence in the tolerance-fallback fetch**

- **Found during:** Task 1, second diagnostic iteration
- **Issue:** The correct and corrupted jobs' JSON both declared `"source_uri_param": "file://processing_datatypes/float_output.raw"` for their output (mirroring `secv01_counter_test.cpp`, which never re-reads its saved files so the collision never mattered there). Since this test's `AttemptToleranceFallback` path fetches **both** subtask results' output data by URI **after** both `Process()` calls have already run, the corrupted run's save silently overwrote the correct run's file at the identical path -- both fetches then read the same (corrupted) bytes, making every tolerance comparison trivially "no divergence" regardless of the real difference between the two model runs.
- **Fix:** Gave the corrupted job's output a distinct filename (`float_output_corrupted.raw`), so both runs' saved files remain independently present and fetchable.
- **Files modified:** `secv02_counter_test.cpp` (corrupted JSON's `outputs[0].source_uri_param`)
- **Commit:** `SuperGenius@e99f749e`

## Issues Encountered

Both issues above were diagnosed empirically by iterating candidate corrupted-model fixtures directly against the built test binary (temporarily pointing the corrupted JSON's model URI at scratch candidates copied into the built binary's fixtures directory, without rebuilding each time) before finalizing the permanent fixture and reverting the test to reference it. No production code (`processing_validation_core.cpp`, `processing_subtask_queue_accessor_impl.cpp`, `diff_utils.cpp`) was touched -- this plan's threat model correctly anticipated "this test introduces no new production code path... it is a test-only artifact."

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- SECV-02 is now proven end-to-end: the phase's three requirements (XNODE-01b, XNODE-02, SECV-02) are all closed with concrete, passing tests.
- This is the last plan in Phase 15 (Validation Comparison Mechanism) per ROADMAP.md -- no further plans are queued for this phase.
- No blockers identified.

---
*Phase: 15-validation-comparison-mechanism*
*Completed: 2026-08-14*

## Self-Check: PASSED

All created/modified files found on disk (secv02_counter_test.cpp, fixtures/secv02-corrupted-float_model.mnn, CMakeLists.txt, this SUMMARY.md). All commit hashes verified present: SuperGenius@e99f749e, GeniusNetwork@27297d4.
