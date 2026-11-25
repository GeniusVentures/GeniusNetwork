---
phase: 16-txpruner-gc-composition-hardening
plan: 01
subsystem: crdt
tags: [crdt, cold-storage, erase-compose, lru-cache, gc-parity, race-testing, gtest, tier1]

requires:
  - phase: 15-03
    provides: "Widened EraseEntry (extra_entries vector + /prune/blk markers), SetEraseInterruptHookForTest abort seam, cold_evidence_matrix hermetic fixture posture, syncerOf idiom"
  - phase: 14-01
    provides: "SetColdUploadStateHookForTest read seam, guard 5 in-compose durability re-check, cold_prune_gate_test fixture kit (healthy-fakes fast-cadence Durable drive)"
provides:
  - "COMP-01's SC1 window closed at the single home: (void)m_dagSyncer->DeleteCIDBlock( cid ) immediately after the single batch commit and before the seal re-assert, covering BOTH committed exits (success + POST_COMMIT_ERASE_ANOMALY) for EVERY caller (D-04)"
  - "SetEraseWindowObserverForTest — the observe-and-continue TEST-ONLY sibling seam firing exactly once per erase immediately before the commit (after all guards + staging); NOT an abort seam; the deterministic substrate every 16-02/16-03 matrix leg parks on"
  - "cold_compose_matrix_test — the phase's Tier-1 evidence home, born with legs W1-W4: deterministic window counter-test (red-first observed), real-thread barrier window (WindowGate), abort-path survival, never-cached idempotence"
  - "GraphsyncDAGSyncer's LRU insert/read pair (AddCIDBlock/GrabCIDBlock) made public beside their IsCIDInCache/DeleteCIDBlock siblings — the counter-test surfaces the production received-block path uses"
affects: [phase-16-plans-02-03, phase-17-probe, phase-19-ci-capstone, tx-pruner, gc-hot-cleanup]

actuals:
  tokens: 10000   # chars/4 over realized diffs (Task 1: ~33.5K chars / Task 2: ~6.5K chars)
  tasks: 2
  commits: 2      # SuperGenius: 5f6ff19d9 (Task 1), 88283905e (Task 2)

tech-stack:
  added: []
  patterns:
    - "Observe-and-continue seam (void-return static observer) as the deterministic-interleaving layer for the compose window — strictly sibling to the bool-return abort hook, never folded into it (research Open Question 1 ruling, now proven)"
    - "Red-first counter-test with an identifying failure token (SC1-STALE-SERVE) in every assertion message — the pre-fix run's output IS the captured red signature (position discipline)"
    - "WindowGate barrier leg through the observer: the erase thread parks INSIDE the guard-3-to-commit window while a second thread drives the inserter primitive — true-concurrency proof without timing luck"

key-files:
  created:
    - SuperGenius/test/src/crdt/cold_compose_matrix_test.cpp
  modified:
    - SuperGenius/src/crdt/globaldb/globaldb.hpp
    - SuperGenius/src/crdt/globaldb/globaldb.cpp
    - SuperGenius/src/crdt/graphsync_dagsyncer.hpp
    - SuperGenius/test/src/crdt/CMakeLists.txt

key-decisions:
  - "Seam shape locked per the planner ruling: sibling observe-and-continue hook SetEraseWindowObserverForTest(std::function<void()>) — one fire site immediately before BOOST_OUTCOME_TRY( batch->commit() ); no step parameter (only the latest window point matters: widest window, tightest determinism); abort contract stays exclusive to the interrupt hook steps 1-3"
  - "Anomaly-path coverage per the Q3 ruling: the close sits immediately after the commit and BEFORE the isResolved re-assert — source-ordering probe green (commit=1666 < delete=1682 < seal=1690) — one call site covers both committed exits without duplication"
  - "Fixture posture: lean Phase-14 kit (hermetic cold stack + real RocksDB, NO account/blockchain/TransactionManager layer — the W legs drive EraseEntry directly); healthy fakes + fast cadence (drain 50ms, flush 50/300ms) drive real Pending->Accepted->Durable transitions polled to evidence before every erase (guard 5's conjunct)"
  - "W4's second-erase contract ruled by code read: StageEraseElement stages absent-key removes as harmless no-ops by design, so the second erase of an erased key SUCCEEDS idempotently — the property D-01's convergence proof leans on (asserted as success + no LRU side effects; the plan's 'expected not-found/guard error' wording was the weaker guess)"
  - "LRU pair (AddCIDBlock/GrabCIDBlock) moved to the public section beside IsCIDInCache/DeleteCIDBlock — the plan cited them as the counter-test surface; access-only change, no behavioral diff, full build + Tier-1 lane green"

patterns-established:
  - "Observe-and-continue seam discipline: void observer fires inside the window, erase proceeds unconditionally; fixtures clear it in teardown beside the interrupt hook"
  - "Mid-window insert recipe: capture the node pre-erase via GetNodeFromMerkleDAG (never touches the LRU), insert from inside the observer (deterministic) or from a second thread while parked on WindowGate (true concurrency)"

requirements-completed: [COMP-01]

coverage:
  - id: D1
    description: "SC1 window closed — deterministic layer: the observer-inserted LRU entry cannot outlive EraseEntry (GrabCIDBlock fails, IsCIDInCache false post-return), proven red-first against the seam-only line"
    requirement: COMP-01
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/crdt/cold_compose_matrix_test.cpp#W1_DeterministicWindowInsertCannotOutliveErase (red observed pre-fix: SC1-STALE-SERVE, then green)"
        status: pass
    human_judgment: false
  - id: D2
    description: "SC1 window closed — true-concurrency layer: erase thread parked inside the window via WindowGate while a second thread inserts through AddCIDBlock; insert still cannot outlive the erase"
    requirement: COMP-01
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/crdt/cold_compose_matrix_test.cpp#W2_RealThreadWindowInsertCannotOutliveErase"
        status: pass
    human_judgment: false
  - id: D3
    description: "Edge rulings: abort-path never evicts (hook-inserted entry + value row survive a step-1 abort; observer never fires on aborted erases) and never-cached erase is idempotent (second erase of the absent key succeeds with zero LRU side effects)"
    requirement: COMP-01
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/crdt/cold_compose_matrix_test.cpp#W3_AbortPathNeverEvicts + #W4_NeverCachedEraseIsIdempotent"
        status: pass
    human_judgment: false
  - id: D4
    description: "Placement + non-regression gates: delete strictly between commit and seal re-assert; zero diff lines vs af644481f intersecting guard 3 (globaldb.cpp:1567-1573, D-05) or RunHotCleanup/A6 (ColdStorageManager.cpp:1317-1353, D-04); suite registered Tier1 under SGNS_COLD_STORAGE"
    requirement: COMP-01
    verification:
      - kind: integration
        ref: "ordering probe commit=1666<delete=1682<seal=1690=True; guard3_hunks=0; gc_hunks=0; ctest -L Tier1 16/16 passed incl. cold_compose_matrix_test"
        status: pass
    human_judgment: false

duration: 35min
completed: 2026-11-18
status: complete
---

# Phase 16 Plan 01: SC1 Post-Commit LRU Close + Observe-and-Continue Seam Summary

**The COMP-01 stale-LRU window is closed at EraseEntry's single home for every caller and both committed exits, proven red→green at both D-06 layers by the phase's new Tier-1 suite.**

## Performance

- **Duration:** 35 min
- **Started:** 2026-11-18T18:05:00Z
- **Completed:** 2026-11-18T18:40:00Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Red-first proof executed exactly as ruled: LEG W1 run against the seam-only line FAILED by serving the stale node — the captured signature (both assertion failures, `SC1-STALE-SERVE` tokens) — then the close landed and the same leg went green.
- The close `(void)m_dagSyncer->DeleteCIDBlock( cid )` sits immediately after the single batch commit and before the seal re-assert: unconditional (D-04), GC-A6-parity, lock-free (A2), idempotent on absent keys, and covering the POST_COMMIT_ERASE_ANOMALY exit without duplication (Q3 ruling, source-ordering probe green).
- The observe-and-continue seam `SetEraseWindowObserverForTest` fires once per erase immediately before the commit — the deterministic substrate 16-02/16-03's matrix legs build on; the abort contract stays exclusive to the interrupt hook.
- Legs W2–W4 rule the remaining edges: true-concurrency window (WindowGate park + second-thread insert), abort-path survival (inserted entry + value row alive; observer silent on aborts), never-cached idempotence (second erase succeeds as a no-op with zero LRU side effects).
- Zero-diff gates hold against af644481f: guard 3 (D-05) and RunHotCleanup/A6 (D-04) untouched — the diff is purely additive (110 insertions, 3 deletions before the test suite grew in Task 2).

## Red Signature (captured pre-fix, seam-only line)

```
W:\gnus\GeniusNetwork\SuperGenius\test\src\crdt\cold_compose_matrix_test.cpp(443): error: Value of: stale_serve.has_error()
  Actual: false
Expected: true
SC1-STALE-SERVE: GrabCIDBlock still serves the mid-window-inserted LRU entry for the erased CID

W:\gnus\GeniusNetwork\SuperGenius\test\src\crdt\cold_compose_matrix_test.cpp(445): error: Value of: syncer->IsCIDInCache( entry_a.cid )
  Actual: true
Expected: false
SC1-STALE-SERVE: IsCIDInCache still true for the erased CID after EraseEntry returned
```

## Task Commits

Each task was committed atomically (SuperGenius submodule, `dev_coldstorage_additions`):

1. **Task 1: TRACER — seam + post-commit DeleteCIDBlock + W1 red→green + Tier-1 registration** - `5f6ff19d9` (feat)
2. **Task 2: SC1 expansion legs W2–W4** - `88283905e` (test; names the WindowGate verbatim copy from cold_storage_fault_race_test.cpp — the CLAUDE.md hard-invariant-2 named exception)

**Plan metadata:** this commit (docs)

## Files Created/Modified
- `SuperGenius/src/crdt/globaldb/globaldb.cpp` — static + setter + pre-commit observer fire + the post-commit close (the load-bearing fix)
- `SuperGenius/src/crdt/globaldb/globaldb.hpp` — SetEraseWindowObserverForTest declaration (observe-and-continue contract, TEST-ONLY, nullptr-clear) + static member
- `SuperGenius/src/crdt/graphsync_dagsyncer.hpp` — AddCIDBlock/GrabCIDBlock moved to the public section beside their LRU siblings
- `SuperGenius/test/src/crdt/cold_compose_matrix_test.cpp` — NEW: the phase's Tier-1 evidence home, legs W1–W4 + WindowGate
- `SuperGenius/test/src/crdt/CMakeLists.txt` — cold_compose_matrix_test registered under SGNS_COLD_STORAGE, LABELS "Tier1", genius_node_test whole-archive link posture

## Decisions Made
- Planner rulings locked as planned (no discretion exercised beyond): seam shape (sibling, no step parameter), fire site (immediately before the single commit), close placement (after commit, before seal re-assert).
- Fixture kept lean (no TransactionManager/TxPruner layer): the W legs drive EraseEntry directly; 16-02's SC3 leg adds the pruner machinery it needs on top.
- W4's second-erase expectation ruled from the StageEraseElement contract read: idempotent success, not an error (see Deviations #2).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical access] AddCIDBlock/GrabCIDBlock were private members**
- **Found during:** Task 1 (first compile)
- **Issue:** The plan's counter-test surface (insert via AddCIDBlock, assert via GrabCIDBlock) cited the two primitives without noting they sat in GraphsyncDAGSyncer's private section — the test could not compile against them.
- **Fix:** Moved both declarations to the public section beside their already-public LRU siblings (IsCIDInCache, DeleteCIDBlock) with a COMP-01 provenance comment. Access-only change: no virtual/layout/behavior delta (non-virtual members; access specifiers do not affect codegen).
- **Files modified:** SuperGenius/src/crdt/graphsync_dagsyncer.hpp (not in the plan's files_modified — this deviation)
- **Verification:** Full Windows Release build exit 0; Tier-1 lane 16/16 green (no target regressed on the widened surface).
- **Commit:** 5f6ff19d9

**2. [Rule 1 - Plan-letter conflict] W4's "second erase returns the expected not-found/guard error"**
- **Found during:** Task 2 (W4 authoring)
- **Issue:** The plan guessed an error return; the actual contract is idempotent SUCCESS — CrdtSet::StageEraseElement stages absent-key removes as harmless no-ops BY DESIGN ("removing an absent key is a harmless staged no-op"), and every guard re-passes (seal retained, journal still Durable).
- **Fix:** W4 asserts success + zero LRU side effects — the stronger property the phase's own governing invariant ("both pruners idempotent on absent keys") requires.
- **Files modified:** none beyond the suite
- **Verification:** W4 green (ctest 0).
- **Commit:** 88283905e

**3. [Rule 1 - Probe-letter conflict] std::this_thread::sleep_for count = 1, plan's zero-count probe**
- **Found during:** Task 2 (static probes)
- **Issue:** The probe's fails_when (count non-zero) contradicts the canonical PollUntil helper every sanctioned sibling carries: the single occurrence is the 10 ms poll STEP inside the deadline-bounded loop, not a race-leg wait.
- **Fix:** Kept PollUntil verbatim (sibling posture: cold_prune_gate_test = 1 occurrence, cold_prune_toctou_test = 1, cold_evidence_matrix_test = 3); W2 parks exclusively on WindowGate — zero timing-luck waits in any race leg (the probe's actual intent).
- **Verification:** occurrence located at cold_compose_matrix_test.cpp:133 (inside PollUntil); W2 uses no sleep.
- **Commit:** 88283905e

**Total deviations:** 3 auto-fixed (2 plan-letter conflicts, 1 missing access). **Impact:** none on the D-04/D-05/D-06 contracts; all placement and zero-diff gates green.

## Verification Results

| Gate | Result |
|------|--------|
| Full incremental Release build (parallel 8) | exit 0, no `error C`/`error LNK` |
| ctest -R cold_compose_matrix_test (red, seam-only) | FAILED as required — SC1-STALE-SERVE captured above |
| ctest -R cold_compose_matrix_test (green, close landed) | Passed, exit 0 |
| ctest -L Tier1 (full lane, 16 tests) | 100% passed, exit 0 |
| Source-ordering probe | commit=1666 < delete=1682 < seal=1690 → True |
| Guard-3 zero-diff window (:1567-1573 vs af644481f) | 0 hunks |
| RunHotCleanup/A6 zero-diff window (:1317-1353 vs af644481f) | 0 hunks |
| SetEraseWindowObserverForTest in hpp | 2 (declaration + setter) ≥ 1 |
| erase_window_observer_for_test_ in cpp | 4 (definition + setter + fire check + call) ≥ 2 |
| WindowGate/PollUntil in suite | 7 ≥ 3 |
| SC1-STALE-SERVE tokens | 8 ≥ 1 |

## Next Plan

Ready for 16-02 — the GC-disposal starvation interplay (COMP-03) extends this suite with the journal-injection leg and the TxPruner split counter, plus the D-02/D-12 rulings at both destructive homes.

## Self-Check: PASSED
