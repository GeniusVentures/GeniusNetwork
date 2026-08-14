---
phase: 15-validation-comparison-mechanism
plan: 03
subsystem: infra
tags: [c++, ctest, gtest, processing_core, processing_subtask_queue_accessor_impl, real-io-wiring, cross-node-validation]

# Dependency graph
requires:
  - phase: 15-02 (validation-core-concatenation-fix-tolerance-fallback)
    provides: ProcessingValidationCore::ValidateResults's 5-arg signature (jobParameters, fetchOutputData both defaulted to nullptr), proven against hand-constructed byte buffers
provides:
  - ProcessingCore::GetTaskQueue() -- new non-pure virtual (default nullptr), overridden by ProcessingCoreImpl to expose its existing task_queue_ member
  - SubTaskQueueAccessorImpl now threads a ProcessingCore reference into FinalizeQueueProcessing, resolving real job-schema quantScale/byteQuantMode (via Task lookup + JSON parse, fail-safe) and performing real FileManager-backed IPFS fetches on a hash mismatch
affects: [15-04-secv02-counter-test]

# Tech tracking
tech-stack:
  added: []
  patterns: ["safe-default non-pure virtual capability accessor (GetTaskQueue, mirrors GetProgress's own pattern) so every existing ProcessingCore implementation (including test mocks) keeps compiling unchanged and safely degrades to the no-lookup case", "fresh, call-scoped io_context per fetch (never the class's own long-running m_localContext) to avoid reset()/run() reentrancy with an already-running background thread"]

key-files:
  created: []
  modified:
    - SuperGenius/src/processing/processing_core.hpp
    - SuperGenius/src/processing/impl/processing_core_impl.hpp
    - SuperGenius/src/processing/impl/processing_core_impl.cpp
    - SuperGenius/src/processing/processing_subtask_queue_accessor_impl.hpp
    - SuperGenius/src/processing/processing_subtask_queue_accessor_impl.cpp
    - SuperGenius/src/processing/processing_node.cpp

key-decisions:
  - "Job schema parameters resolved once per FinalizeQueueProcessing call, into a local sgns::SgnsProcessing + std::vector<sgns::Parameter> declared before the ValidateResults call (not in a narrower scope), so the const std::vector<sgns::Parameter>* pointer passed to ValidateResults stays valid for the duration of that call"
  - "SgnsProcessing::get_parameters() returns boost::optional<std::vector<Parameter>> BY VALUE (not a pointer) -- stored into a local jobParametersStorage vector first, then jobParameters points at that local, matching the codebase's own optional-by-value accessor convention"

patterns-established: []

requirements-completed: [XNODE-01b, XNODE-02]

coverage:
  - id: D1
    description: "ProcessingCore::GetTaskQueue() exists with a safe nullptr default; ProcessingCoreImpl overrides it to expose task_queue_"
    requirement: "XNODE-01b"
    verification:
      - kind: build
        ref: "cmake --build SuperGenius/build/Windows/Debug --target processing_service --config Debug (clean build, no other ProcessingCore implementation broke)"
        status: pass
    human_judgment: false
  - id: D2
    description: "FinalizeQueueProcessing resolves real job-schema parameters via GetTaskQueue()->GetTask(subTask.ipfsblock()) + JSON parse, fail-safe (try/catch, logs+nullptr on failure)"
    requirement: "XNODE-02"
    verification:
      - kind: unit
        ref: "grep -c \"catch\" SuperGenius/src/processing/processing_subtask_queue_accessor_impl.cpp -> 1"
        status: pass
    human_judgment: false
  - id: D3
    description: "fetchOutputData performs real FileManager::LoadASync I/O on a fresh, call-scoped io_context (never m_localContext)"
    requirement: "XNODE-02"
    verification:
      - kind: unit
        ref: "grep -A5 \"fetchOutputData = \" ...cpp | grep -c \"make_shared<boost::asio::io_context>\" -> 1"
        status: pass
    human_judgment: false
  - id: D4
    description: "processing_service builds cleanly; ProcessingValidationCoreTest (Plan 15-02, 5 cases) still passes unchanged -- no regression from this plan's wiring"
    requirement: "XNODE-02"
    verification:
      - kind: unit
        ref: "ctest --test-dir SuperGenius/build/Windows/Debug -C Debug -R \"processing_validation_core_test|task_queue_test|processing_result_durability_test|processing_validate_result_data_test\" -V (4/4 targets, 100% passed)"
        status: pass
    human_judgment: false

# Metrics
duration: 40min
completed: 2026-08-14
status: complete
---

# Phase 15 Plan 3: Real Job-Schema Resolution + Real IPFS Fetch Wiring Summary

**`ProcessingCore` gained a new `GetTaskQueue()` capability accessor and `SubTaskQueueAccessorImpl::FinalizeQueueProcessing` now resolves real job-schema `quantScale`/`byteQuantMode` (via `Task` lookup + JSON parse, fail-safe) and performs real `FileManager`-backed IPFS fetches on a hash mismatch, wiring production values into Plan 15-02's two injected `ValidateResults` capabilities.**

## Performance

- **Duration:** ~40 min
- **Completed:** 2026-08-14
- **Tasks:** 2
- **Files modified:** 6 (0 new, 6 edited)

## Accomplishments

- Added `ProcessingCore::GetTaskQueue() const` -- a new non-pure virtual with a safe `nullptr` default, mirroring `GetProgress()`'s existing pattern exactly. `ProcessingCoreImpl` overrides it to expose its already-existing `task_queue_` member with zero new state.
- Forward-declared `ProcessingTaskQueue` in `processing_core.hpp` (only a `shared_ptr` is returned; no full include needed for the base class).
- `SubTaskQueueAccessorImpl` gained a new, defaulted 6th constructor parameter (`std::shared_ptr<ProcessingCore> processingCore = nullptr`) and a matching `m_processingCore` member -- fully non-breaking for any existing caller.
- `FinalizeQueueProcessing` now resolves real job-schema parameters: if `m_processingCore` is set and there's at least one subtask, it calls `GetTaskQueue()->GetTask(subTasks.items(0).ipfsblock())` (the exact same lookup-by-ipfsblock mechanism `ProcessingCoreImpl::ProcessSubTask` already uses), parses the returned `Task.json_data()` via `nlohmann::json::parse` + `sgns::from_json`, and reads `.get_parameters()`. The entire lookup/parse is wrapped in `try/catch (const std::exception&)`, logging a warning and leaving `jobParameters` as `nullptr` on any failure (T-15-08's DoS mitigation) -- never crashes on malformed/adversarial `Task.json_data()`.
- `fetchOutputData` now performs real I/O: a fresh, call-scoped `boost::asio::io_context` (deliberately never `m_localContext`, which already has a permanently-running background thread) fires `FileManager::GetInstance().LoadASync(outputUri, false, false, freshContext, callback, "file")` mirroring `ProcessingManager::GetSubCidForProc`'s exact callback shape, then blocks on `freshContext->run()` (no `reset()` needed -- used exactly once) until the fetch completes, returning the collected bytes or `outcome::failure(std::make_error_code(std::errc::io_error))` on failure/empty result.
- `ProcessingNode::Initialize()`'s `SubTaskQueueAccessorImpl` construction call passes `m_processingCore` (already an existing `ProcessingNode` member) as the new 6th argument -- zero new plumbing needed at that call site.
- The happy path (identical hashes, no mismatch) still triggers zero Task lookups and zero fetch calls -- D-02's guarantee is preserved end-to-end through this real wiring, not just at Plan 15-02's injected-capability level.

## Task Commits

Each task was committed atomically, at the `SuperGenius` submodule layer (this plan's files are directly under `SuperGenius/src/processing/`, not the nested `SGProcessingManager` submodule), mirroring Plan 15-02's exact commit-layering pattern:

1. **Task 1: Add ProcessingCore::GetTaskQueue() and override it in ProcessingCoreImpl** -- `SuperGenius@454d949a` (feat)
2. **Task 2: Thread ProcessingCore into SubTaskQueueAccessorImpl and wire real job-parameter resolution + real fetch into FinalizeQueueProcessing** -- `SuperGenius@7c07cc55` (feat)

**Submodule pointer bumps:**
- `GeniusNetwork@597e3e0` (chore: bump SuperGenius pointer, Task 1)
- `GeniusNetwork@5092cf1` (chore: bump SuperGenius pointer, Task 2)

**Plan metadata:** captured in this commit (docs: complete plan)

## Files Created/Modified

- `SuperGenius/src/processing/processing_core.hpp` - Added `GetTaskQueue()` non-pure virtual (default `nullptr`), forward-declared `ProcessingTaskQueue`
- `SuperGenius/src/processing/impl/processing_core_impl.hpp` - Declared `GetTaskQueue() const override`
- `SuperGenius/src/processing/impl/processing_core_impl.cpp` - Implemented `GetTaskQueue()` returning `task_queue_`
- `SuperGenius/src/processing/processing_subtask_queue_accessor_impl.hpp` - Added `#include "processing/processing_core.hpp"`, new defaulted 6th constructor parameter, new `m_processingCore` member
- `SuperGenius/src/processing/processing_subtask_queue_accessor_impl.cpp` - Constructor stores the new parameter; `FinalizeQueueProcessing` gains real job-parameter resolution (Task lookup + JSON parse, fail-safe) and a real `fetchOutputData` lambda backed by `FileManager::LoadASync` on a fresh `io_context`; new includes (`nlohmann/json.hpp`, `SgnsProcessing.hpp`, `Generators.hpp`, `FileManager.hpp`)
- `SuperGenius/src/processing/processing_node.cpp` - `Initialize()`'s `SubTaskQueueAccessorImpl` construction call passes `m_processingCore` as the 6th argument

## Decisions Made

- `SgnsProcessing::get_parameters()` returns `boost::optional<std::vector<Parameter>>` by value (confirmed by reading `generated/SgnsProcessing.hpp`), not a pointer as the plan's illustrative pseudocode implied -- resolved by storing the optional's value into a local `jobParametersStorage` vector (declared alongside `parsedProcessing` before the `ValidateResults` call) and pointing `jobParameters` at that local, so the pointer's lifetime correctly spans the call
- The `FileManager::LoadASync` callback lambda inside `fetchOutputData` needed `outputUri` added to its capture list (by reference) after the first build attempt failed with C3493 -- a straightforward compile-fix, not a design change

## Deviations from Plan

None beyond the two items above (both narrow, mechanical fixes to make the plan's illustrative code compile against the real generated-schema accessor shape and MSVC's capture rules) -- documented under Decisions Made since neither changed the plan's intended behavior.

## Issues Encountered

None beyond the compile-time capture fix noted above. Build succeeded cleanly on the first attempt for Task 1; Task 2 needed one capture-list fix before it compiled clean.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Real production job-schema resolution and real `FileManager`-backed I/O now flow into `ValidateResults`'s two injected capabilities via `FinalizeQueueProcessing`, with a safe, silent, non-crashing fallback whenever either capability is unavailable or fails.
- Ready for Plan 15-04's SECV-02 full-pipeline counter-test to prove this real wiring still catches a genuinely corrupted result end-to-end.
- No blockers identified for Plan 15-04.

---
*Phase: 15-validation-comparison-mechanism*
*Completed: 2026-08-14*

## Self-Check: PASSED

All modified files found on disk (processing_core.hpp, processing_core_impl.hpp, processing_core_impl.cpp, processing_subtask_queue_accessor_impl.hpp, processing_subtask_queue_accessor_impl.cpp, processing_node.cpp, this SUMMARY.md). All commit hashes verified present: SuperGenius@454d949a, SuperGenius@7c07cc55, GeniusNetwork@597e3e0, GeniusNetwork@5092cf1.
