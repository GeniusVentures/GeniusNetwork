---
phase: 14-durability-gated-txpruner-eligibility
plan: 02
subsystem: transaction
tags: [txpruner, cold-storage, toctou, guard, erase-entry, globaldb, tier1, red-first]

# Dependency graph
requires:
  - phase: 14-01
    provides: the cold-durability admission conjunct + cold_deferred_groups counter (the refusal's mapping target) + the cold_prune_gate_test fixture family
provides:
  - GlobalDB::Error::COLD_NOT_DURABLE — distinct refusal value (nothing erased; a deferral, not a policy violation)
  - Guard 5 in GlobalDB::EraseEntry — the in-compose cold-durability re-read (after guard 4, before staging, no new lock edges)
  - TxPruner::kInterruptAfterColdGate = 5 — the admission→erase observation seam (D-07's probe position)
  - GlobalDB::SetColdUploadStateHookForTest — TEST-ONLY per-CID cold-state override (the induced-regression injector; reused by 14-03's Unreadable legs)
  - TxPruner's COLD_NOT_DURABLE → cold_deferred_groups mapping branch (never stats.errors, never the failure WARN)
  - cold_prune_toctou_test — Tier-1 red-first counter-test, parameterized over {DurableToAccepted, DurableToNoRecord}
affects: [14-03 (extends the gate suite; reuses the read hook for Unreadable legs), Phase 16 (Interaction-C: the post-re-check window's monotonicity ownership), Phase 15 (evidence-serving composes with the refusal)]

# Actuals (#2632) — pairs with the plan's `estimate` to calibrate future estimates.
actuals:
  tokens: 9800
  tasks: 2
  commits: 2

# Tech tracking
tech-stack:
  added: []
  patterns: ["in-compose evidence re-check: a new guard inside the MakeComposeLock critical section, distinct-error refusal, caller maps to a deferral counter (Pitfall 1)", "induced regression at the shared read seam: TEST-ONLY per-CID override consulted FIRST in GetColdUploadState because the real journal is monotone in-process (research Q1)", "red-first proof cycle: counter-test authored against the guard-less gate, destroying-erase signature recorded, then the guard lands and the test goes green"]

key-files:
  created:
    - SuperGenius/test/src/crdt/cold_prune_toctou_test.cpp
  modified:
    - SuperGenius/src/crdt/globaldb/globaldb.hpp
    - SuperGenius/src/crdt/globaldb/globaldb.cpp
    - SuperGenius/src/transaction/TxPruner.hpp
    - SuperGenius/src/transaction/TxPruner.cpp
    - SuperGenius/test/src/crdt/CMakeLists.txt

key-decisions:
  - "SetColdUploadStateHookForTest returns std::optional<ColdUploadState> and is consulted FIRST in GetColdUploadState — an armed value IS 'the state read changed' for every reader of the shared seam (gate and guard alike); inert when unset (cold_prune_gate_test green proves the unset path)"
  - "GetColdUploadState moved beside its injector (SetColdUploadStateHookForTest + the static) below the QueryRaw block so the read seam and its override stay together — behavior byte-identical"
  - "Guard 5 refuses on Unreadable too (any non-Durable state) — at the commit boundary the guard does not distinguish WHY the evidence is insufficient, only THAT it is not exactly Durable"
  - "The RED run's signature (recorded verbatim in this summary): erased != 0, cold_deferred_groups 0 vs 1, hot value DESTROYED, /prune/ marker STAGED — the 14-01 gate alone loses to the regression; with guard 5 both parameterizations pass with errors == 0"

patterns-established:
  - "In-compose re-check shape: slot AFTER isResolved (guard 4), BEFORE the batch creation; comment block carries the lock-discipline proof and the two-layer TOCTOU story (guard closes pre-admission staleness; monotonicity + Phase 16 own the post-read window)"
  - "D-07 probe discipline: flip armed ONLY at TxPruner step 5 (admission→erase gap), NEVER GlobalDB's erase-hook steps 1/2/3 (post-re-check, unprovable by any read-then-commit implementation)"

requirements-completed: [PRUNE-02]

# Coverage metadata (#1602) — one entry per shipped deliverable.
coverage:
  - id: D1
    description: "Guard 5 — the in-compose cold-durability re-read inside EraseEntry's compose critical section, refusing with the distinct COLD_NOT_DURABLE value"
    requirement: PRUNE-02
    verification:
      - kind: unit
        ref: "tests: SuperGenius/test/src/crdt/cold_prune_toctou_test.cpp#InducedRegressionBetweenAdmissionAndComposeIsRefused/DurableToAccepted (red → green)"
        status: pass
      - kind: unit
        ref: "tests: SuperGenius/test/src/crdt/cold_prune_toctou_test.cpp#InducedRegressionBetweenAdmissionAndComposeIsRefused/DurableToNoRecord (red → green)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Refusal-as-counter mapping + zero regression on the cold-off erase/cycle surfaces"
    requirement: PRUNE-02
    verification:
      - kind: integration
        ref: "command: ctest -R 'globaldb_integration_test' → Passed 86.38s (contains globaldb_erase_test incl. EraseInterruptSteps 1/2/3)"
        status: pass
      - kind: integration
        ref: "command: ctest -R 'tx_pruner_test' → Passed 46.25s"
        status: pass
      - kind: other
        ref: "command: git -C SuperGenius diff --exit-code 2af184fa1 -- PruneEligibility.{hpp,cpp} (purity, exit 0)"
        status: pass
    human_judgment: false

# Metrics
duration: 20min
completed: 2026-11-17
status: complete
---

# Phase 14 Plan 02: In-Compose Durability Re-Check (Guard 5) Summary

**A journal-state regression between gate admission and erase-commit can no longer authorize a destroying erase: EraseEntry re-reads the cold evidence inside the compose critical section and refuses with a distinct counter-mapped error — proven red-first on both regression vectors.**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-11-17T03:20Z
- **Completed:** 2026-11-17T03:55Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- **SC2 closed (PRUNE-02, D-06):** guard 5 in `GlobalDB::EraseEntry` — after guard 4 (isResolved), before the first staging act, inside the same MakeComposeLock critical section spanning guard→staging→commit. `HasColdStorage() && GetColdUploadState(cid) != Durable` refuses with `Error::COLD_NOT_DURABLE` (nothing erased). Lock discipline held: only lifecycle-scoped accessor reads over the pre-existing compose→lifecycle→cold_store chain — no new edges, no datastore re-entry (Pitfall 3).
- **Red→green cycle (D-07) recorded verbatim:** the RED run (commit 1c84799f1, guard-less) failed with the destroying-erase signature on BOTH parameterizations — `erased != 0`, `cold_deferred_groups 0 vs 1`, hot value destroyed, `/prune/` marker staged — all TOCTOU-marked. With guard 5 (20a437a25): erased==0, value present, marker absent, counter ≥1, errors==0 on both DurableToAccepted and DurableToNoRecord.
- **The injector:** `GlobalDB::SetColdUploadStateHookForTest` — TEST-ONLY per-CID override consulted FIRST in `GetColdUploadState` (required because the real journal is monotone in-process per research Q1 and the coldstore RocksDB is held by the live GlobalDB). PRODUCTION-MUST-NEVER-CALL Doxygen; inert when unset (gate suite green proves it); cleared in fixture teardown. The probe arms ONLY TxPruner's new step-5 seam (`kInterruptAfterColdGate`) — GlobalDB's erase-hook steps 1/2/3 are never armed (Pitfall 2 documented in the test file header).
- **Pitfall 1 held end-to-end:** `TxPruner` maps exactly `COLD_NOT_DURABLE` to `++cold_deferred_groups` ahead of the generic `++stats.errors` + "Prune erase failed" WARN branch; the counter-test's `errors == 0` assertion enforces the classification.
- **Two-layer TOCTOU story in code:** the guard's comment block states that it closes pre-admission staleness while the post-read window is closed by journal monotonicity (research Q1) and owned by Phase 16's Interaction-C ruling.

## Task Commits

1. **Task 1 (RED): step-5 seam + cold-state read hook + failing counter-test** - `1c84799f1` (test, SuperGenius)
2. **Task 2 (GREEN): guard 5 + COLD_NOT_DURABLE + refusal mapping** - `20a437a25` (feat, SuperGenius)

**Plan metadata:** root pointer bump + this summary (docs(14-02), GeniusNetwork)

## EraseEntry Call-Site Posture Audit (research A4 — closed)

`git grep 'EraseEntry(' -- src/` finds exactly ONE production call site:
- `TransactionManager.cpp:4755` — `EraseTransactionEntryWithMarker`, driving BOTH `EraseTransactionEntry` (plain) and `EraseTransactionEntryPruned` (production pruned driver). Posture: on cold-enabled nodes every erase driver now refuses non-Durable erases — fail-correct by design (no driver may destroy undurable hot data; both drivers surface the same refusal the TxPruner maps to a counter); cold-off nodes take the guard vacuously (byte-identical behavior). No other production call sites exist; `globaldb_integration_test` (which contains `globaldb_erase_test` and its EraseInterruptSteps 1/2/3 instantiation over the plain-driver path) passes unchanged.

## Self-Check: PASSED

- Build exit 0 (library + both test binaries)
- cold_prune_toctou_test: Passed (2/2 parameterizations, 2.81s) — after RED evidence recorded above
- cold_prune_gate_test: Passed (3.52s) — seam/hook inert when unarmed
- globaldb_integration_test: Passed (86.38s) — cold-off erase path + interrupt-step matrix unchanged
- tx_pruner_test: Passed (46.25s) — existing cycle behavior untouched
- Purity gate: exit 0; no thirdparty/sgns-blockstore edits; no new lock edges; no push (local on dev_coldstorage_additions per v1.1 D-03)

## Deviations from Plan

**[Rule 2 - Placement] GetColdUploadState definition relocated within globaldb.cpp** — Found during: Task 1 | Issue: the TEST-ONLY override (its injector) lives at the SetEraseInterruptHookForTest block below QueryRaw; keeping the read seam and its injector together required moving GetColdUploadState's definition there instead of leaving a consult call up at :1024 | Fix: definition moved (behavior byte-identical; the original site keeps a pointer comment) | Files: globaldb.cpp | Verification: build 0 errors, cold_prune_gate_test green (the unset-hook path), TOCTOU red→green | Commit: 1c84799f1

**Total deviations:** 1 auto-fixed (placement). **Impact:** none — pure definition-site relocation within one TU.

## Issues Encountered

None.

## Next Phase Readiness

Ready for 14-03 (Wave 3): the five-state journal matrix (direct CF seeding for NoRecord/Accepted; the read hook drives real-fault Unreadable legs), the SC3 composition proof, and the dev-gated live-stack smoke — sealed by the full Tier-1 lane.
