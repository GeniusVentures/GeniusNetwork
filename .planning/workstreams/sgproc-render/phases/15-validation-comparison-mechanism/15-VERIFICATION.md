---
phase: 15-validation-comparison-mechanism
verified: 2026-08-14T18:15:00Z
status: passed
score: 8/8 must-haves verified
behavior_unverified: 0
overrides_applied: 0
re_verification: false
---

# Phase 15: Validation Comparison Mechanism Verification Report

**Phase Goal:** `ProcessingValidationCore::ValidateResults` is fixed to actually compare same-chunk hashes across subtasks (today's concatenation bug silently passes a genuine cross-node mismatch), and extended with a bounded numeric-tolerance fallback so a hash mismatch is not automatically treated as a genuine divergence — directly closing the false-mismatch risk v2.1's chunk-10 diagnostic exposed, where a correct result can still fail bit-exact hash equality on a boundary tie-break. A counter-test proves the combined mechanism still catches genuinely wrong results, not just tolerant ones.

**Verified:** 2026-08-14
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

Truths are ROADMAP.md's 5 Success Criteria (SC1-SC5), merged with each plan's `must_haves.truths` (deduplicated where they restate the same SC).

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SC1: Given two subtasks with genuinely different hashes for the same chunk, `ValidateResults` reports a mismatch (concatenation-bug fix) | VERIFIED | `processing_validation_core.cpp` lines 63-146: `chunksBySubtask` (`map<chunkKey, map<subtaskId, ChunkContribution>>`) replaces the old flattening `std::map<string, vector<uint8_t>>` accumulator; a genuine per-chunk cross-subtask comparison pass (lines 111-146) now runs. Proven behaviorally by `ProcessingValidationCoreTest.DifferingHashesNoToleranceCapabilityFail`, independently re-run and passing (see Behavioral Spot-Checks). |
| 2 | SC2: Given two subtasks with identical hashes for the same chunk, `ValidateResults` still reports a match | VERIFIED | Same comparison pass's `allMatch` branch (lines 118-131) `continue`s on an identical-hash chunk. Proven by `ProcessingValidationCoreTest.IdenticalHashesStillPass`, independently re-run and passing. |
| 3 | SC3: Given two subtasks whose hashes differ but whose underlying chunk data falls within configured tolerance, `ValidateResults` reports a match | VERIFIED | `AttemptToleranceFallback` (lines 257-355) fetches, slices, and diffs via `sgprocmanagerdiff::IsFloatChunkWithinTolerance`/`IsByteChunkWithinTolerance`. Proven by `ProcessingValidationCoreTest.DifferingHashesWithinToleranceStillPass` (quantScale=32768, delta below `2/S`), independently re-run and passing. |
| 4 | SC4: Given two subtasks whose hashes differ and whose underlying data exceeds tolerance, `ValidateResults` still reports a genuine mismatch | VERIFIED | Same `AttemptToleranceFallback` path; proven by `ProcessingValidationCoreTest.DifferingHashesExceedsToleranceFail` (delta above `2/S`), independently re-run and passing. |
| 5 | SC5/SECV-02: A deliberately corrupted subtask result is still caught by the fixed `ValidateResults` + tolerance fallback acting together, exercised through a real end-to-end pipeline | VERIFIED | `secv02_counter_test.cpp`'s `Secv02CounterTest.CorruptedSubtaskResultStillCaughtBySubTaskQueueAccessor`: two real `ProcessingManager::Process()` runs (correct vs. corrupted MNN model), real `ProcessTaskSplitter::SplitTask(..., addvalidationsubtask=true)` two-subtask/one-chunk construction, real `SubTaskQueueAccessorImpl::AssignSubTasks`/`GrabSubTask` public API, real `FileManager::LoadASync` fetch of on-disk outputs, asserts `errorFired==true` and the exact `"Invalid results for the entire task"` message. Independently re-run via the full `processing_conformance_security_test` CTest binary — passed (232.23s, all 4 gtest cases including `Secv02CounterTest`). |
| 6 | (Plan-level) `sgprocmanagerdiff` extraction is byte-identical / behavior-neutral relative to `capture_diff.cpp`'s pre-extraction primitives | VERIFIED | `diff_utils.cpp`'s `ComputeFloat32Diff`/`ComputeUint8Diff`/`OrderedFloatBits`/`UlpDistanceFloat` are verbatim relocations reading header-exported constants; `capture_diff.cpp` now `#include`s the shared header and calls `sgns::sgprocmanagerdiff::` qualified functions, no local redefinition (`grep -c "ElementDiffStats ComputeFloat32Diff" capture_diff.cpp` = 0, confirmed). 18 `DiffUtilsTest` cases independently re-run and passing. |
| 7 | (Plan-level) Real production job-schema resolution (quantScale/byteQuantMode) and real IPFS fetch flow into `ValidateResults` via `FinalizeQueueProcessing`, fail-safe on any lookup/parse/fetch failure | VERIFIED | `processing_subtask_queue_accessor_impl.cpp` lines 329-422: `GetTaskQueue()`→`GetTask()`→`nlohmann::json::parse`+`sgns::from_json` wrapped in `try/catch(std::exception)`, falls back to `jobParameters=nullptr` on any failure; `fetchOutputData` lambda constructs a fresh, call-scoped `io_context` (never `m_localContext`) and calls `FileManager::LoadASync`. `ProcessingCore::GetTaskQueue()` exists with a safe `nullptr` default (mirrors `GetProgress()`); `ProcessingCoreImpl::GetTaskQueue()` returns `task_queue_`. `processing_node.cpp` passes `m_processingCore` as the 6th constructor argument. |
| 8 | (Plan-level) The happy path (no mismatch) triggers zero fetch attempts / zero Task lookups | VERIFIED | Job-parameter resolution and the comparison-triggered tolerance fallback are both gated behind the mismatch branch (`AttemptToleranceFallback` is only called from inside the `!allMatch` branch at line 135); `fetchOutputData` is only invoked from within `AttemptToleranceFallback`. Structurally guaranteed by the call graph, consistent with SC2's passing/no-fetch test case. |

**Score:** 8/8 truths verified (0 present-but-behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `SuperGenius/SGProcessingManager/include/util/diff_utils.hpp` | Exported diff primitives + D-03/D-04 tolerance functions in `sgns::sgprocmanagerdiff` | VERIFIED | All declared symbols present (`kDefaultFloatRelativeThreshold`, `kDefaultByteAbsoluteThreshold`, `ElementDiffStats`, `ComputeFloat32Diff`, `ComputeUint8Diff`, `ChunkElementType`, `ResolveChunkElementTypeHint`, `IsFloatChunkWithinTolerance`, `IsByteChunkWithinTolerance`) |
| `SuperGenius/SGProcessingManager/src/util/diff_utils.cpp` | Implementation, isolated Try-lookups, no dependence on quantization.cpp's resolvers | VERIFIED | `TryGetDeclaredQuantScale`/`TryGetDeclaredByteQuantMode` are isolated; no `ResolveQuantScale`/`ResolveByteQuantMode` calls found |
| `SuperGenius/SGProcessingManager/test/util/diff_utils_test.cpp` | ≥10 TEST_F cases | VERIFIED | 18 TEST_F cases present, all passing (re-run independently) |
| `sgprocmanagerdiff` (CMake target) | New static library, reachable from `processing_service` | VERIFIED | Declared in `src/util/CMakeLists.txt`; added to `SGProcessors`' PUBLIC link list; build of `processing_validation_core_test`/`processing_service` succeeds |
| `SuperGenius/src/processing/processing_validation_core.hpp` | New Error enumerator, ChunkContribution struct, 5-arg ValidateResults, AttemptToleranceFallback decl | VERIFIED | All present exactly as specified |
| `SuperGenius/src/processing/processing_validation_core.cpp` | Concatenation bug fixed; AttemptToleranceFallback fully implemented (not a stub) | VERIFIED | Real fetch/slice/diff logic present (lines 257-355), not the Task-1 stub |
| `SuperGenius/test/src/processing/processing_validation_core_test.cpp` | 5 TEST cases covering SC1-SC4 | VERIFIED | Exactly 5 `TEST(ProcessingValidationCoreTest, ...)` cases, all passing (re-run independently) |
| `SuperGenius/src/processing/processing_core.hpp` (GetTaskQueue) | Safe-default non-pure virtual | VERIFIED | `virtual std::shared_ptr<ProcessingTaskQueue> GetTaskQueue() const { return nullptr; }` present |
| `SuperGenius/src/processing/impl/processing_core_impl.{hpp,cpp}` | Override returning `task_queue_` | VERIFIED | `GetTaskQueue() const override` declared and implemented returning `task_queue_` |
| `SuperGenius/src/processing/processing_subtask_queue_accessor_impl.{hpp,cpp}` | 6th defaulted ctor param, real resolution/fetch wiring | VERIFIED | Constructor takes `processingCore` as 6th param; `FinalizeQueueProcessing` performs real resolution + real fetch (see Truth 7) |
| `SuperGenius/src/processing/processing_node.cpp` | Passes `m_processingCore` to `SubTaskQueueAccessorImpl` | VERIFIED | 6th constructor argument confirmed at `Initialize()` call site |
| `SuperGenius/test/src/processing_conformance_security/secv02_counter_test.cpp` | Full-pipeline SECV-02 counter-test | VERIFIED | Present; real pipeline, real `SplitTask`, real public API, no direct `ValidateResults` call (`grep -c "ValidateResults(" secv02_counter_test.cpp` = 0, confirmed) |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `sgprocmanagerdiff`'s exported constants | `capture_diff.cpp`'s post-edit calls | Shared symbol, not independent copies | WIRED | `capture_diff.cpp` includes `util/diff_utils.hpp` and calls `sgns::sgprocmanagerdiff::ComputeFloat32Diff` — same symbol |
| `SGProcessors`' CMakeLists.txt PUBLIC link list | `processing_service`'s PUBLIC link chain | `sgprocmanagerdiff` added to `SGProcessors` PUBLIC links | WIRED | Confirmed at `src/processors/CMakeLists.txt` line 78; `processing_validation_core.cpp` successfully `#include`s `util/diff_utils.hpp` and builds |
| `ProcessingValidationCore::AttemptToleranceFallback` | `sgprocmanagerdiff::IsFloat/IsByteChunkWithinTolerance`/`ResolveChunkElementTypeHint` | Direct function calls | WIRED | Confirmed at lines 325-341 of `processing_validation_core.cpp` |
| `ChunkContribution`'s chunkIdx/totalChunksForSubtask | Blob-slicing logic in `AttemptToleranceFallback` | Struct fields read directly | WIRED | Confirmed at lines 301-321 |
| `SubTaskQueueAccessorImpl`'s `m_processingCore` | `ProcessingNode::Initialize()`'s `m_processingCore` | 6th constructor argument | WIRED | Confirmed at `processing_node.cpp` line 148 |
| `ProcessingCoreImpl::GetTaskQueue()` | `task_queue_` | Direct accessor | WIRED | Confirmed at `processing_core_impl.cpp` lines 163-166 |
| `FinalizeQueueProcessing`'s real resolution/fetch | `ValidateResults`'s `jobParameters`/`fetchOutputData` params | Direct call-site pass-through | WIRED | Confirmed at line 422 of `processing_subtask_queue_accessor_impl.cpp` |
| `secv02_counter_test.cpp`'s new addtest() target | Existing `processing_conformance_security_test` CTest target | Added source + link libs | WIRED | Confirmed in `test/src/processing_conformance_security/CMakeLists.txt`; binary's `--gtest_list_tests` shows `Secv02CounterTest.CorruptedSubtaskResultStillCaughtBySubTaskQueueAccessor` alongside SECV-01's cases |

### Behavioral Spot-Checks / Test Execution (independently re-run, not trusted from SUMMARY)

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `sgprocmanagerdiff` builds and its 18-case unit suite passes | `cmake --build ... --target diff_utils_test` then `ctest -R "^DiffUtilsTest$" -V` | 18/18 passed, 0.68s | PASS |
| `ValidateResults`'s SC1-SC4 fix/tolerance logic (5 live TEST cases) | `cmake --build ... --target processing_validation_core_test` then `ctest -R "^processing_validation_core_test$" -V` | 5/5 passed, 0.02s | PASS |
| `processing_service` still builds cleanly against the new `ProcessingCore::GetTaskQueue()` + `SubTaskQueueAccessorImpl` 6-arg wiring | `cmake --build ... --target processing_service --config Debug` | Build succeeded | PASS |
| Full-pipeline SECV-02 counter-test (`processing_conformance_security_test`, includes `Secv02CounterTest`) | `cmake --build ... --target processing_conformance_security_test` then scoped `ctest -R "processing|capture|quantiz|diff" -j` | 15/15 tests passed incl. `processing_conformance_security_test` (232.23s, all 4 gtest cases: `Secv01CounterTest`x2, `Secv01Tex3dCounterTest`, `Secv02CounterTest`) | PASS |
| Full scoped regression matches orchestrator's claim (15 test binaries, `processing\|capture\|quantiz\|diff` filter) | `ctest --test-dir SuperGenius/build/Windows/Debug -j -C Debug -R "processing|capture|quantiz|diff"` | 100% tests passed, 15/15, 232.27s total | PASS |

All test executions above were run independently by the verifier in this session (not sourced from SUMMARY.md claims); build artifacts and CTest output were captured directly.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| XNODE-01b | 15-02, 15-03 | `ValidateResults` actually diffs (not concatenates) per-chunk hashes | SATISFIED | `chunksBySubtask` restructure + comparison pass; `DifferingHashesNoToleranceCapabilityFail`/`IdenticalHashesStillPass` passing |
| XNODE-02 | 15-01, 15-02, 15-03 | Bounded numeric-tolerance fallback on hash mismatch before declaring divergence | SATISFIED | `sgprocmanagerdiff` D-03/D-04 tolerance functions + `AttemptToleranceFallback`'s real fetch/slice/diff, wired to real I/O in `FinalizeQueueProcessing`; `DifferingHashesWithinToleranceStillPass`/`DifferingHashesExceedsToleranceFail` passing |
| SECV-02 | 15-04 | Deliberately corrupted result still caught (counter-test) | SATISFIED | `Secv02CounterTest.CorruptedSubtaskResultStillCaughtBySubTaskQueueAccessor` — full real pipeline, passing |

No orphaned requirements: REQUIREMENTS.md maps exactly XNODE-01b/XNODE-02/SECV-02 to Phase 15, and all three are claimed and satisfied across the four plans.

**Minor documentation gap (non-blocking):** REQUIREMENTS.md's traceability table (lines 51-53) still reads "Not started" for XNODE-01b/XNODE-02/SECV-02 even though the requirement checkboxes above it (lines 20-22) are marked `[x]` and the phase is functionally complete and verified. This is a stale-bookkeeping issue in the traceability table, not a functional gap — flagged for cleanup, does not block phase completion.

### Anti-Patterns Found

No blocker or warning-level anti-patterns found. Scanned all 8 core files modified across the phase's 4 plans (`diff_utils.hpp/.cpp`, `processing_validation_core.hpp/.cpp`, `processing_core.hpp`, `processing_core_impl.cpp`, `processing_subtask_queue_accessor_impl.cpp`, `secv02_counter_test.cpp`) for `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER`/stub-return patterns — none found. One pre-existing, unrelated `@todo` comment in `processing_subtask_queue_accessor_impl.cpp`'s constructor (line 34, "replace hardcoded channel identifier") predates this phase and is out of scope.

### Human Verification Required

None. Every truth is proven by a live, independently-re-executed automated test (unit-level for SC1-SC4, full real-pipeline end-to-end for SC5/SECV-02). No UI, real-time, or external-service behavior in this phase requires human judgment.

### Gaps Summary

No gaps. All 3 requirement IDs (XNODE-01b, XNODE-02, SECV-02) are satisfied with both static code evidence (artifacts present, correctly wired, matching plan specifications exactly) and independently re-executed passing tests (23 unit-level assertions across `DiffUtilsTest`/`ProcessingValidationCoreTest`, plus the full-pipeline `Secv02CounterTest`). The only finding is a non-blocking documentation staleness item (REQUIREMENTS.md traceability table) noted above.

---

*Verified: 2026-08-14*
*Verifier: Claude (gsd-verifier)*
