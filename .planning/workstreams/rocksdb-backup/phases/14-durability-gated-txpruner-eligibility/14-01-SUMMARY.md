---
phase: 14-durability-gated-txpruner-eligibility
plan: 01
subsystem: transaction
tags: [txpruner, cold-storage, prune-gate, durability, globaldb, tier1]

# Dependency graph
requires:
  - phase: 13-bootstrap-branch-merge-composition-baseline
    provides: merged-line baseline 2af184fa1 (dev_coldstorage_additions) with the evaluator, block gate, /prune/ marker contract, and the cold stack (GetColdUploadState bridge) all in-tree
provides:
  - GlobalDB::HasColdStorage() — public cold-tier presence signal (the SC4 vacuous-branch key; shutdown-clause-free by Pitfall-8 ruling)
  - The named cold-durability admission conjunct (ColdGateAdmitsGroup) inside TxPruner::RunCycle's block-group work-list filter — exact-equality Durable-only permit, whole-group deferral
  - PruneCycleStats::cold_deferred_groups / cold_unreadable_groups counters surfaced in the per-cycle INFO summary (and PruneStatus via the existing last_cycle copy)
  - cold_prune_gate_test — Tier-1 gate suite (LEG 1 Durable-admits-erases / LEG 2 Pending-defers-whole-group / LEG 3 cold-off-vacuous)
affects: [14-02 (guard-5 TOCTOU re-check maps its refusal onto cold_deferred_groups), 14-03 (extends the suite: five-state matrix, SC3 composition, live smoke), Phase 15 (evidence-serving), Phase 16 (pruner×GC hardening)]

# Actuals (#2632) — pairs with the plan's `estimate` to calibrate future estimates.
actuals:
  tokens: 11200
  tasks: 2
  commits: 1

# Tech tracking
tech-stack:
  added: []
  patterns: ["named filter-local admission conjunct composing beside erasable_cids as an AND (evaluator stays pure — D-05)", "whole-group cold deferral keyed on the single delta-block CID (D-01 removal set)", "tier presence via manager-null accessor, never journal-state inference (Pitfall 7)"]

key-files:
  created:
    - SuperGenius/test/src/crdt/cold_prune_gate_test.cpp
  modified:
    - SuperGenius/src/crdt/globaldb/globaldb.hpp
    - SuperGenius/src/crdt/globaldb/globaldb.cpp
    - SuperGenius/src/transaction/TxPruner.hpp
    - SuperGenius/src/transaction/TxPruner.cpp
    - SuperGenius/test/src/crdt/CMakeLists.txt

key-decisions:
  - "HasColdStorage() implemented WITHOUT any shutdown clause (planner ruling overriding the PATTERNS Analog C sketch): during shutdown the gate must flow into GetColdUploadState → NoRecord → defer (Pitfall 8's safe under-prune direction); a shutdown clause would flip the conjunct into a vacuous permit exactly when teardown races"
  - "ColdGateAdmitsGroup is a file-local helper in TxPruner.cpp's anonymous namespace (executor's choice within D-05): exact-equality Durable-only permit mirroring GC's kEvictionDurabilityGate three properties; an unparseable CID fails closed into cold_deferred_groups; the default switch arm defers so an unknown future enum value can never admit (T-14-01)"
  - "Group admission consults the gate exactly once per NEW group at the try_emplace point; a cold_gate_deferred set keeps later same-CID candidates out of the work list without re-consulting the gate (whole-group skip, Pitfall 4)"
  - "LEG 2's deterministic Pending hold uses a 60000 ms drain interval (no drainer pass inside the test window); LEG 1 uses 50 ms drain + 50/300 ms flush cadence for real Pending→Accepted→Durable transitions on the injected InMemory fakes"

patterns-established:
  - "Cold admission gate at the cycle filter: consult HasColdStorage() once per group, switch on the ungated ColdUploadState enum, count into dedicated counters, continue-never-abort"
  - "Hermetic cold GlobalDB + TxPruner fixture: resurrection cold recipe (SetColdStorageStackClientsForTesting + hygiene clear) combined with the tx_pruner_test account/blockchain/TransactionManager wiring"

requirements-completed: [PRUNE-01, PRUNE-03]

# Coverage metadata (#1602) — one entry per shipped deliverable.
coverage:
  - id: D1
    description: "The cold-durability admission gate wired end-to-end on the production path: GlobalDB::HasColdStorage() accessor + the named conjunct in RunCycle's group filter + deferral counters + INFO-summary extension"
    requirement: PRUNE-01
    verification:
      - kind: unit
        ref: "tests: SuperGenius/test/src/crdt/cold_prune_gate_test.cpp#Gate_DurableAdmitsAndErases"
        status: pass
      - kind: unit
        ref: "tests: SuperGenius/test/src/crdt/cold_prune_gate_test.cpp#Gate_PendingDefersWholeGroupAsCounter"
        status: pass
      - kind: unit
        ref: "tests: SuperGenius/test/src/crdt/cold_prune_gate_test.cpp#Gate_ColdDisabledNodeVacuousBranch"
        status: pass
      - kind: other
        ref: "command: git -C SuperGenius diff --exit-code 2af184fa1 -- src/transaction/PruneEligibility.hpp src/transaction/PruneEligibility.cpp (purity gate, exit 0)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Tier-1 gate suite registered inside if(SGNS_COLD_STORAGE) with LABELS Tier1; the full Tier-1 lane green with it included (13/13 incl. tier1_static_audit)"
    requirement: PRUNE-03
    verification:
      - kind: integration
        ref: "command: ctest -C Release -L Tier1 → 100% tests passed, 0 failed out of 13 (cold_prune_gate_test = test #108, 3.60s)"
        status: pass
    human_judgment: false

# Metrics
duration: 25min
completed: 2026-11-17
status: complete
---

# Phase 14 Plan 01: Cold-Durability Admission Gate Summary

**TxPruner::RunCycle now admits a block group for erasure only when its delta-block CID reads exactly ColdUploadState::Durable through the GlobalDB bridge — everything else defers the whole group as dedicated counters, and cold-off nodes behave byte-for-byte as before.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-11-17T02:50Z
- **Completed:** 2026-11-17T03:14Z
- **Tasks:** 2
- **Files modified:** 6 (4 source + 1 new test + 1 CMake)

## Accomplishments
- **SC1 core mechanism landed (PRUNE-01):** the named conjunct `ColdGateAdmitsGroup` at RunCycle's group-assembly loop consults `GlobalDB::HasColdStorage()` (new public tier-presence accessor) then `GetColdUploadState(cid)` per new group — Durable is the only admit case (exact equality, mirroring GC's kEvictionDurabilityGate); NoRecord/Pending/Accepted/default (and an unparseable CID) defer the whole group into `cold_deferred_groups`; Unreadable defers loudly into `cold_unreadable_groups` + one WARN (D-03). Deferral is never an error, never a WARN "Prune erase failed", never a permanent-stop class.
- **SC4 vacuous branch proven (D-04):** `HasColdStorage()` is `cold_manager_ != nullptr` under `lifecycle_mutex_` with deliberately NO shutdown clause (Pitfall 8); LEG 3 proves a cold-disabled node erases identically with both cold counters zero, and activation is automatic (Light AND cold-enabled — no config knob, NodeType::Light check at TxPruner.cpp untouched).
- **PRUNE-03 placement enforced (D-05):** the gate lives in the filter as an AND conjunct beside erasable_cids membership; `PruneEligibility.{hpp,cpp}` verified byte-identical to the merged line 2af184fa1 (purity gate exit 0).
- **Tier-1 gate suite (D-08a/D-09):** hermetic cold GlobalDB + real TransactionManager + TxPruner fixture (resurrection recipe + tx_pruner_test wiring, zero network, real RocksDB on both tiers); LEG 1 drives REAL Pending→Accepted→Durable transitions on the injected fakes and asserts erased==2/markers PRUNED; LEG 2 holds the journal at Pending and asserts the whole two-tx shared-block group defers as one counter with a re-evaluating second cycle; LEG 3 asserts the cold-off node is unchanged.

## Task Commits

Each task was committed atomically (Task 1 held its commit for the Task 2 atomic landing per the plan):

1. **Task 1 + Task 2: tracer + Tier-1 gate suite** - `dc788261d` (feat, SuperGenius @ dev_coldstorage_additions)

**Plan metadata:** root pointer bump + this summary (docs(14-01), GeniusNetwork)

## Self-Check: PASSED

- Incremental Windows Release build: exit 0, zero error C diagnostics
- `ctest -R cold_prune_gate_test`: 1/1 passed (3 legs, 4.00s)
- `ctest -L Tier1`: 13/13 passed (12 existing green-lane entries + the new suite; tier1_static_audit label-parity included)
- Evaluator purity: `git diff --exit-code 2af184fa1 -- PruneEligibility.{hpp,cpp}` exit 0
- No new dependencies, no thirdparty/sgns-blockstore edits, no compaction-filter deletion, no DeleteRange, no cross-store WriteBatch, no push (commit local on dev_coldstorage_additions per v1.1 D-03)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Next Phase Readiness

Ready for 14-02 (Wave 2): the durability re-check inside GlobalDB::EraseEntry's compose critical section (guard 5) + the red-first TOCTOU counter-test — `cold_deferred_groups` (landed here) is the counter its refusal signal maps onto.
