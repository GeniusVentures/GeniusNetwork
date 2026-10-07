---
phase: 08-consensus-integration
plan: "02"
subsystem: consensus
tags: [consensus, protobuf, subject, task-rejection, escrow-release, cpp17]

requires:
  - phase: 08-consensus-integration (08-01)
    provides: consensus escrow price gate + claim-time backstop (seams live; undisturbed by this plan)
provides:
  - Proto message TaskRejectionSubject{escrow_path=1, task_id=2, reject_reason=3, original_escrow_hash=4} (append-only, user-approved per D-08-06)
  - ConsensusManager::TASK_REJECTION_SUBJECT_TYPE = "sgns.task_rejection.v1"
  - ConsensusManager::CreateTaskRejectionSubject / DecodeTaskRejectionSubject (TaskResult-trio shape)
  - CheckSubject forged-subject branch (drops empty refs or reject_reason == 0) — T-08-03 mitigation
  - TASK_REJECTION_SUBJECT_TYPE routed at all three SubjectTypeMatches dispatch sites (GetSubjectHash, ValidateSubject, CheckSubject)
affects: [08-consensus-integration (08-03 handler registration, 08-04 multi-node test), consensus subject machinery, Consensus.proto consumers (GeniusSDK/GeniusWallet)]

actuals:
  tokens: 2632   # chars/4 over the realized submodule diff (10,528 chars, 129 insertions)
  tasks: 2
  commits: 1     # MEASURED: git rev-list --count 914731e0..HEAD in the SuperGenius submodule (+ parent pointer bump + docs commit outside)
plan_head_before: 914731e0aa71fad5cacb504d0fbb9725a1b37fb2
plan_head_after: 28e15b157b183c6b26cccab40e1ee6cae111472d

tech-stack:
  added: []   # no new libraries — in-repo C++17 + existing protobuf machinery
  patterns:
    - "Typed-consensus-subject trio extended verbatim: proto message → type-string constant → CheckSubject branch → Create/Decode helpers (fourth subject in the family)"
    - "Forged-subject drop at CheckSubject: refs non-empty AND typed reason non-zero (0 = Accepted can never legitimate a rejection)"

key-files:
  created: []
  modified:
    - SuperGenius/src/blockchain/impl/proto/Consensus.proto
    - SuperGenius/src/blockchain/Consensus.hpp
    - SuperGenius/src/blockchain/Consensus.cpp

key-decisions:
  - "D-08-06 contract published verbatim after checkpoint:decision (gate=blocking-human) approval — message name, field names/numbers 1-4, type string sgns.task_rejection.v1 frozen"
  - "reject_reason typed as uint32 carrying static_cast<uint32_t>(PriceValidationReason); CheckSubject rejects 0 (Accepted) explicitly — forged-zero subjects dropped before proposal handling (T-08-03)"
  - "GetSubjectHash maps the rejection subject to original_escrow_hash (the escrow UTXO identity the release spends) mirroring how TASK_RESULT maps to task_result_hash"

patterns-established:
  - "Fourth typed subject in Consensus.proto — future subjects copy this exact trio shape (append-only; new field numbers only)"

requirements-completed: [CONS-02]

coverage:
  - id: D1
    description: "TaskRejectionSubject published end-to-end: proto message, type constant, Create/Decode helpers, CheckSubject validation branch, and routing at all three SubjectTypeMatches dispatch sites"
    requirement: CONS-02
    verification:
      - kind: integration
        ref: "cmake --build SuperGenius\\build\\Windows\\Release --config Release --target processing_nodes_test — BUILD SUCCEEDED, processing_nodes_test.exe linked (proto regenerated as build dependency)"
        status: pass
      - kind: other
        ref: "git -C SuperGenius grep -c TaskRejectionSubject — proto 1, hpp 2, cpp 7; grep -c TASK_REJECTION_SUBJECT_TYPE Consensus.cpp — 5 (>= 4 required: CheckSubject + three dispatch clusters + Create/Decode)"
        status: pass
    human_judgment: false
  - id: D2
    description: "One-way D-08-06 protocol publish authorized by human decision (checkpoint:decision, gate=blocking-human)"
    requirement: CONS-02
    verification: []
    human_judgment: true
    rationale: "One-way protocol contract: the whole point of the blocking-human gate is that a human sees and owns the publish decision before the contract freezes; automation cannot substitute for that authorization"

# Metrics
duration: 11min
completed: 2026-10-06
status: complete
---

# Phase 8 Plan 02: TaskRejectionSubject Publish Summary

**Published the typed rejection-release consensus subject (sgns.task_rejection.v1) end-to-end — proto message, constant, Create/Decode helpers, forged-subject CheckSubject branch, and routing at all three dispatch sites — the one-way D-08-06 contract that authorizes CONS-02 rejection refunds.**

## Performance

- **Duration:** ~11 min execution (checkpoint pause between Tasks 1 and 2 excluded; plan dispatched 21:41, completed 21:52 local)
- **Started:** 2026-10-06T21:41:43-04:00
- **Completed:** 2026-10-06T21:52:23-04:00
- **Tasks:** 2 (1 checkpoint:decision + 1 auto)
- **Files modified:** 3 (all in SuperGenius submodule)

## Accomplishments

- **TaskRejectionSubject published** exactly as user-approved at the blocking-human decision gate: `escrow_path = 1`, `task_id = 2`, `reject_reason = 3` (uint32, PriceValidationReason domain), `original_escrow_hash = 4` — append-only after TaskResultSubject, nothing renumbered
- **Full subject machinery wired**: `TASK_REJECTION_SUBJECT_TYPE` constant, `CreateTaskRejectionSubject`/`DecodeTaskRejectionSubject` in the TaskResult-trio shape (`ComputeSubjectTypeHash` + `SetSubjectPayload`), and the type routed at every `SubjectTypeMatches` dispatch site — `GetSubjectHash` (~:818), `ValidateSubject` (~:4300), `CheckSubject` (~:4420)
- **Forged subjects dropped at the trust boundary** (T-08-03 mitigation): CheckSubject rejects empty `escrow_path`/`task_id`/`original_escrow_hash` and `reject_reason == 0` (0 = Accepted can never legitimate a rejection), each with an error log in the established format
- **08-01 work undisturbed**: zero edits outside the three planned files; the gate/backstop seams from wave 1 are untouched

## Task Commits

Each task was committed atomically:

1. **Task 1: Checkpoint decision (D-08-06 one-way publish)** — no code; user approved verbatim contract via orchestrator (blocking-human gate honored; no commit applicable)
2. **Task 2: Subject publish** - `28e15b157` (feat) — SuperGenius submodule, branch `dev_price_validation`

**Parent-repo commits:**
- `c1d955f` (chore): bump SuperGenius submodule pointer

**Plan metadata:** SUMMARY commit follows this file (docs)

## Files Created/Modified

- `SuperGenius/src/blockchain/impl/proto/Consensus.proto` — TaskRejectionSubject message with Doxygen-style field comments (escrow lock id, task id, PriceValidationReason domain, escrow tx hash)
- `SuperGenius/src/blockchain/Consensus.hpp` — `TASK_REJECTION_SUBJECT_TYPE` constant beside the existing three; Create/Decode declarations with @brief/@param docs
- `SuperGenius/src/blockchain/Consensus.cpp` — Decode helper beside DecodeTaskResultSubject; Create helper mirroring CreateTaskResultSubject; CheckSubject validation branch; dispatch entries at all three SubjectTypeMatches clusters

## Decisions Made

- **Checkpoint outcome (Task 1):** user chose `approve` — contract published verbatim, frozen for network lifetime (D-08-06)
- **GetSubjectHash mapping:** rejection subjects map to `original_escrow_hash` — the escrow UTXO identity the release spends — mirroring how TASK_RESULT subjects map to `task_result_hash`
- **Submodule branch note:** runtime notes mentioned `dev_persisprocresults`; pre-flight found the submodule HEAD (with both 08-01 commits) on `dev_price_validation` — per dispatch instruction ("use the submodule's CURRENT checked-out branch, do not switch"), Task 2 committed there. Parent repo is on `dev_persisprocresults`

## Deviations from Plan

None - plan executed exactly as written.

Two verification-command notes (checks still performed and passed; not code deviations):
- The plan's grep pathspec `src/blockchain/Consensus.proto` does not match the file's real location `src/blockchain/impl/proto/Consensus.proto` (as its own `files_modified`/`read_first` correctly state); the grep was run against the correct path.
- The plan requires `TASK_REJECTION_SUBJECT_TYPE` count ≥ 4 in Consensus.cpp; actual count is 5 (CheckSubject branch + Create + Decode + ValidateSubject + GetSubjectHash clusters) — exceeds the threshold.

## Issues Encountered

None - build succeeded on the first attempt (10-40 min expected; actual ~7 min warm tree). All C4834 warnings in build output are pre-existing in files not touched by this plan (out of scope per SCOPE BOUNDARY).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **08-03 (handler registration)** can proceed immediately: register the subject + certificate handlers for `TASK_REJECTION_SUBJECT_TYPE` per the TransactionManager registration pattern (08-PATTERNS.md — weak-ptr capture, `std::errc::owner_dead`), re-running the price gate as the independent D-08-06 verification
- **08-04 (multi-node test)** will exercise the full reject → subject → release loop; the carrier is now on the wire
- D-08-09/D-08-10 prohibitions respected: the subject is the only rejection-propagation carrier added — no CRDT marker, no side-channel record, no tombstone anywhere in this plan

## Self-Check: PASSED

---

*Phase: 08-consensus-integration*
*Plan: 02*
*Completed: 2026-10-06*
