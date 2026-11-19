---
phase: 18-role-downgrade-collectibility-policy-gc-walk-gap-exemption
plan: 01
subsystem: database
tags: [gc, cold-storage, prune-evidence, crdt, rocksdb, gtest]

requires:
  - phase: 15-evidence-aware-cold-serving-forced-walk-recovery
    provides: the ONE role-aware prune-evidence predicate (GraphsyncDAGSyncer::LookupPruneEvidence + ColdReadService install) the exemption consult extends to the GC walk
provides:
  - the GC walk-gap evidence exemption as production code (one-predicate consult at the WalkReachable gap site, counted-continue leaf semantics)
  - the walk-exempted observable spine (pass_walk_exempted_ per-pass member + gc_last_pass_exempted_ status atomic + GetStatus field + extended per-pass INFO line)
  - the red-first Tier-1 counter-test cold_gc_walk_gap_exempt_test (LEG-1 live poisoned-triangle, LEG-2 v2 fault-injected deleted-cold, NoEvidence/Malformed fail-closed controls, repeat-pass idempotency, zero-baseline)
affects: [18-02, 18-03, 18-04, phase-19-capstone, sgns-blockstore-v2]

actuals:
  tokens: 12000
  tasks: 2
  commits: 4

tech-stack:
  added: []
  patterns:
    - "evidence consult at a destructive/aborting boundary - only the Pruned verdict is permissive, everything else fails closed (extends Shared Pattern 1 to the GC walk)"
    - "never-healthy-by-omission two-level counter (per-CID per-pass member + relaxed status atomic + INFO field before the parenthesized options so tail-greps survive)"

key-files:
  created:
    - SuperGenius/test/src/crdt/cold_gc_walk_gap_exempt_test.cpp
  modified:
    - SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp
    - SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp
    - SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp
    - SuperGenius/test/src/crdt/CMakeLists.txt
    - SuperGenius/test/src/crdt/cold_compose_matrix_test.cpp

key-decisions:
  - "Consult seam resolved per 18-RESEARCH: GraphsyncDAGSyncer::LookupPruneEvidence through the gc_dag_syncer_ handle the walk already holds - no new exposure path, D-02 consistency-by-construction"
  - "Counter naming per plan ruling: pass_walk_exempted_ (per-pass plain member under gc_pass_mutex_) + gc_last_pass_exempted_ (status atomic) + INFO field appended before the parenthesized options"
  - "Walk-completion canary: each leg seeds one backdated past-retention Durable orphan - a completed pass necessarily nominates it (gc_last_pass_candidates == 1), an aborted pass cannot (== 0) - the strongest pre-consult pass-outcome observable"
  - "Red-first trail on the branch: test(18-01) commit 69fa79c29 (observed red) then feat(18-01) commit 01d0e85d1 (green) - the evidence chain any v2 collection milestone gates on"

patterns-established:
  - "Pattern: evidence consult at the GC walk-gap abort site - terminal-leaf continue on Pruned only"
  - "Pattern: posture-update discipline for legacy suites when a designed behavior change moves a recorded fixed point (drive to the NEW fixed point, assert stability there)"

requirements-completed: [POLICY-01, POLICY-02]

coverage:
  - id: D1
    description: "The GC walk-gap evidence exemption as production code: one-predicate consult at the WalkReachable gap site, counted-continue leaf semantics, fail-closed arms preserved"
    requirement: POLICY-01
    verification:
      - kind: integration
        ref: "ctest -R cold_gc_walk_gap_exempt_test (LEG-1/LEG-2 green with exempted > 0)"
        status: pass
      - kind: integration
        ref: "ctest -R cold_gc_walk_gap_exempt_test (CONTROL-NoEvidence/CONTROL-Malformed still abort)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Red-first counter-test born red: LEG-1 (live poisoned-GC-triangle) and LEG-2 (deleted-cold fault injection) observed failing against the unmodified walk, red signature committed"
    requirement: POLICY-01
    verification:
      - kind: integration
        ref: "RED commit 69fa79c29 - ctest exit 8 with gc: pass-aborted-walk-gap signature (recorded in this SUMMARY's Evidence section)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Walk-exempted observability: two-level counter surfaced through GetStatus (gc_last_pass_exempted) and the extended per-pass INFO line, zero-baseline included"
    requirement: POLICY-02
    verification:
      - kind: integration
        ref: "ctest -R cold_gc_walk_gap_exempt_test (repeat-pass identical counts + NoEvidenceBaselinePassReportsZeroExempted)"
        status: pass
      - kind: automated
        ref: "Select-String gates: LookupPruneEvidence|walk-exempted in ColdStorageManager.cpp (4), pass_walk_exempted_|gc_last_pass_exempted_ in hpp (4), no PRUNE_BLOCK_MARKER_PREFIX|GetRaw( in the GC TU"
        status: pass
    human_judgment: false
  - id: D4
    description: "Zero regression: full Tier-1 lane green including tier1_static_audit and cold_storage_gc_test; cold_compose_matrix_test LEG M8 posture-updated to the post-exemption disposal fixed point"
    requirement: POLICY-01
    verification:
      - kind: integration
        ref: "ctest -L Tier1 --no-tests=error -C Release: 18/18 passed, exit 0"
        status: pass
    human_judgment: false

duration: 65min
completed: 2026-11-19
status: complete
---

# Phase 18 Plan 01: GC Walk-Gap Evidence Exemption (Red-First Tracer) Summary

The poisoned-GC-triangle is defused: a prune-evidenced absent link no longer aborts the GC walk - it is an expected-absent counted leaf through the ONE Phase 15 predicate, visible per pass in status and the INFO line, proven by a counter-test that was born red against the unmodified walk.

## Performance

- **Duration:** 65 min
- **Tasks:** 2 / 2
- **Files:** 6 (1 created test, 3 production headers/sources, 2 test-config/legacy-suite)

## Tasks Completed

1. **Task 1 (TRACER RED)** - `test(18-01)` commit `69fa79c29`: cold_gc_walk_gap_exempt_test.cpp (hermetic GC-fixture family, evidence install via real ColdReadService SetPruneEvidenceLookup with a production-shaped lambda reading PrunedBlockRecord rows at PruneEligibility::BuildPruneBlockMarkerKey keys - zero hand-built keys) + Tier-1 registration (cold_compose_matrix link set with genius_node_test whole-archive). RED OBSERVED: LEG-1/LEG-2 fail, both controls pass.
2. **Task 2 (GREEN)** - `feat(18-01)` commit `01d0e85d1`: the gap-site consult + counted-continue in ColdStorageManager.cpp, the two-level counter in the hpp, the ColdStorageStatus field, the extended INFO line, strengthened test legs + zero-baseline leg. Full Tier-1 lane 18/18 green.

## Evidence: the red signature (pre-consult, ctest exit 8)

```
[warning][ColdStorageManager] gc: pass-aborted-walk-gap - CID QmYTxnviXzqUf56TP3et71x2mBZsZgv9qGvGQXLK8mv55X is head-reachable but missing from every tier; reachability not computable (under-eviction)
[warning][ColdStorageManager] gc: pass-aborted-walk (streak 1); no candidates this pass
[info][ColdStorageManager] gc: pass complete - 0 candidate(s), 0 evicted (retention 5000 ms, dry_run false)
error: Expected equality of these values: pass1.size() (0) != 1u
```

LEG-1's CID above carried /prune/blk evidence PRUNED with cold bytes STILL PRESENT in both cold tiers - the live poisoned-GC-triangle (18-RESEARCH Pitfall 1), broken GC liveness from the first prune cycle onward. LEG-2 (cold deleted from both tiers via the fake's conformance Delete + LocalBlockStore::EvictLocal) produced the identical signature. Post-consult both legs complete with walk-exempted > 0 and the canary nominated.

## Accomplishments

- The two-halves rule's enforced half (D-01) is live: v2 collection cannot ship without this exemption already existing and tested
- D-02 honored by construction: the ONLY evidence surface in the GC TU is `gc_dag_syncer_->LookupPruneEvidence` - source gate clean (no PRUNE_BLOCK_MARKER_PREFIX, no GetRaw in ColdStorageManager.cpp)
- D-04: `gc: pass complete - {} candidate(s), {} evicted, {} walk-exempted (retention {} ms, dry_run {})` - the new field sits before the parenthesized options so existing tail-greps survive; GetStatus carries gc_last_pass_exempted
- D-03 both-legs posture: the dev-gated live leg lives in 18-03's cold_downgrade_live_smoke_test.cpp (header note in the suite)

## Deviations from Plan

- **[Rule 1-3 - Missing file in manifest] ColdStorageStack.hpp modified** - Found during: Task 2 | Issue: the plan requires the exempted count "surfaced via GetStatus/ColdStorageStatus" but ColdStorageStatus is defined in the always-compiled ColdStorageStack.hpp, absent from files_modified | Fix: added the `gc_last_pass_exempted` field there (plain type, Pitfall 5 discipline), filled from the atomic in GetStatus | Files: SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp | Verification: Tier-1 lane green | Commit: 01d0e85d1
- **[Rule 1-3 - Designed behavior change vs. legacy expectation] cold_compose_matrix_test.cpp LEG M8 posture update** - Found during: Task 2 Tier-1 lane run | Issue: the fixed-point leg encoded the pre-exemption walk-abort (its comment cited "passes abort on the T1 gap" as the stability mechanism); post-exemption the GC converges to a disposal fixed point for classes below the exempted link, so before/after snapshots diverged mid-convergence | Fix: drive that convergence before the before-snapshot (DriveGcToQuiescence with include_overlap=false - the overlap group stays walk-reachable in this leg, no DetachT2Chain), comment records the Phase 18 posture | Files: SuperGenius/test/src/crdt/cold_compose_matrix_test.cpp | Verification: cold_compose_matrix_test green, full lane 18/18 | Commit: 01d0e85d1
- **[Rule 1-3 - Transient environment] cold_storage_soak_test flaked once under full-lane load** (failed in the 3rd lane run, passed isolated and in the final lane run; the suite has zero prune-evidence references so the consult is behaviorally inert there - pure-read NoEvidence). No fix; recorded for the CI watchers.

**Total deviations:** 3 auto-fixed (2 code, 1 recorded-no-op). **Impact:** none on the contract - all must_haves hold; the two file additions are mechanical consequences of the designed behavior change.

## Issues Encountered

None blocking. (The PS 5.1 embedded-quote commit-message mangling was a tooling hiccup, retried via `git commit -F`.)

## Next Phase Readiness

Ready for 18-02 (downgrade interlock mechanics) - the walk now survives prune-evidenced gaps, which 18-03's t3 leg exercises in-band.
