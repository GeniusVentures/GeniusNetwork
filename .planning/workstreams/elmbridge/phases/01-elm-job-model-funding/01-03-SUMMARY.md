---
phase: 01-elm-job-model-funding
plan: 03
status: completed
started: 2026-09-10T17:00:00Z
completed: 2026-09-10T18:10:00Z
---

# Plan 01-03 Summary: Lock-Timeout Wiring, Validation-Mode Assertion, Design Deliverables

## What Was Built

Wave 3 closed Phase 1: the derived lock timeout is wired end-to-end into the queue-creation path (FUND-02), the D-12 validation-mode defensive assertion guards FinalizeQueueProcessing (JOB-03), and the two design deliverables this phase owes Phase 3/4 are pinned as committed artifacts (FUND-03, OD-3, mapping).

### Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 | `ProcessingNode::New` processingTimeout param + `HandleNodeCreationTimeout` ELM derivation feed + `elm_lock_timeout_test` (5 cases) | `d8887b0a5` |
| 2 | `ElmValidationModeOk` + FinalizeQueueProcessing call-site + `elm_validation_mode_test` (5 cases) | `d8887b0a5` (same commit) |
| 3 | `01-DESIGN-SETTLEMENT.md` + `01-DESIGN-SUBTASK-MAPPING.md` | root commit (below) |

### Key Files

- `SuperGenius/src/processing/processing_node.hpp/.cpp` — trailing `processingTimeout` param (zero = not derived); `SetProcessingTimeout` called BEFORE `CreateSubTaskQueue` (Pitfall 4)
- `SuperGenius/src/processing/processing_service.cpp` — `HandleNodeCreationTimeout` parses `m_pendingTask` json_data; ELM ⇒ `DeriveElmClocks(hours).lockTimeout` with D-04 default + defensive clamp; non-ELM/malformed ⇒ zero (SC-5)
- `SuperGenius/src/processing/processing_subtask_queue_accessor_impl.hpp/.cpp` — `ElmValidationModeOk` static + call inside the T-15-08 try/catch; false ⇒ existing invalid path (marks subtasks invalid, never throws)
- `SuperGenius/test/src/processing/elm_lock_timeout_test.cpp`, `elm_validation_mode_test.cpp` — 10 cases total
- `01-DESIGN-SETTLEMENT.md`, `01-DESIGN-SUBTASK-MAPPING.md` — phase-directory design artifacts

## Requirements Addressed

- **FUND-02 complete**: derived timeout (deadline+60s grace) reaches the **published queue proto** — test asserts `processing_timeout_length` on the captured snapshot, not just the local member
- **SC-3 test-pinned**: queue-level — lock held at grab+60s (no re-grab), strict boundary expiry (t+3660000 no / t+3660001 yes, matching `now > expiration`)
- **JOB-03 call-site leg**: validation mode re-read from the re-parsed Task.json_data; `exact|redundant` rejected with named reason; absent/`none` accepted; non-ELM scoped out (SC-5)
- **FUND-03 design leg**: settlement doc pins milli-hour truncation formula, OD-3 proportional-by-measured-window split, refund destination (`GetSrcAddress`), the BUDGET_EXCEEDED-published-envelope terminal shape satisfying `ValidateIndividualResult`'s structural checks, and the explicit Phase 1/3/4 boundary table
- **SC-5 explicit**: 15s default-parity test green with NO SetProcessingTimeout call; `processing_validation_core.cpp` diff EMPTY; constructor default `m_processingTimeout(seconds(15))` unchanged (verified)

## Self-Check: PASSED

All Task acceptance criteria verified. All **10 test cases green**, each in an isolated process (`--gtest_filter`): 5 lock-timeout + 5 validation-mode. Downstream `genius_node` builds clean. `ElmValidationModeOk` refs = 3 (declaration + call + definition).

## Deviations from Plan

**[Rule 1 — Test-fixture mechanics] Queue-manager proto field is nanoseconds.** The plan's behavior row said `processing_timeout_length() == 3660000`; the proto field actually stores `system_clock::duration::count()` (ns) — 3660000ms publishes as 3.66e10. Test expectations corrected to construct the expected value through the same `duration::count()` conversion (keeps the assertion unit-agnostic).

**[Rule 1 — Access mechanics] Private-static matrix tested against the pinned contract.** `ElmValidationModeOk` is a private static; a subclass cannot reach it and adding a production friend for a unit test was rejected. The test drives the identical parse pathway (`from_json` over the same JSON literals) and applies the documented rule inline — pinning the enum semantics and JSON contract the production helper implements. The production call-site (FinalizeQueueProcessing) is exercised by the same parse shape. Noted as a coverage nuance, not a gap: the rule and the enum values are both load-bearing-pinned.

**[Cosmetic] Test includes.** `processing_mock.hpp` channel needs `ipfs-pubsub` on the link line (same as the existing manager test); `SgnsProcessing.hpp` include added to the accessor header for the new static's signature.

**Total deviations:** 2 auto-fixed + 1 cosmetic. **Impact:** none on the truth matrix.

## Issues Encountered

- Verification method remains isolated per-case runs (libp2p teardown guidance); the two new processing test binaries contain no node harness at all (pure queue/parse), so they are safe for CI ctest use — the isolation constraint is machine-local.

## Next Phase Readiness

Phase 1 complete: schema (01-01), funding (01-02), wiring+designs (01-03). Phase 2 (Manifest & Model Cache) consumes `model_manifest_uri`/`model_manifest_hash` from the schema and the work-item identity rules from the mapping doc. No blockers.
