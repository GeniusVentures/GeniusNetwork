---
phase: 18-role-downgrade-collectibility-policy-gc-walk-gap-exemption
plan: 03
subsystem: database
tags: [downgrade, e2e, cold-storage, gc, prune-evidence, minio, tier3]

requires:
  - phase: 18-role-downgrade-collectibility-policy-gc-walk-gap-exemption
    provides: 18-01's exemption consult + walk-exempted status surface; 18-02's RoleFingerprint interlock + the cold_downgrade_e2e_test fixture/registration
provides:
  - the single-node in-process re-open downgrade timeline t0->t3 as Tier-1 evidence (SC2 downgraded half, SC3 no-re-drain the strong way, SC4 markers + refusal + interlock observability, D-12 t3 steady state)
  - the Tier-3 dev-gated live leg (cold_downgrade_live_smoke_test) on a real MinIO stack through the production S3 client, with the loud-skip contract verified
affects: [18-04, phase-19-capstone]

actuals:
  tokens: 18000
  tasks: 3
  commits: 6

tech-stack:
  added: []
  patterns:
    - "persistent in-memory remote tier across in-process re-opens (fixture-member fakes re-injected around every GlobalDB::New; Put faulted from t0 so unchurned is structural)"
    - "below-exempted-leaf eviction class (the pruned CID itself stays walk-pinned; what retention evicts is the non-pruned data the leaf orphans)"

key-files:
  created:
    - SuperGenius/test/src/crdt/cold_downgrade_live_smoke_test.cpp
    - .planning/workstreams/rocksdb-backup/phases/18-role-downgrade-collectibility-policy-gc-walk-gap-exemption/18-USER-SETUP.md
  modified:
    - SuperGenius/test/src/crdt/cold_downgrade_e2e_test.cpp
    - SuperGenius/test/src/crdt/CMakeLists.txt

key-decisions:
  - "SC3 proven the strong way: the drainer is structurally dead (faulted Put + Unreachable admin) while archive-era Durable groups still erase and their journal records stay Durable across the cycle"
  - "t3 semantics recorded: the exempted leaf itself stays walk-visited (pinned - its local cold copy is NOT evictable); what retention evicts is the BELOW-link non-pruned data the leaf orphans (the spender block), which then serves remote-backed"
  - "t1 ack leg uses the FP-AckArms re-seed shape (the unack check rewrites the record to the light posture, so the archive-era record is re-established before the ack verdict is read)"
  - "t3 admin fault CLEARS (the GC staging gate needs a healthy admin) while the Put fault stays - unchurned remains structural"

patterns-established:
  - "Pattern: in-process restart topology over persistent fakes (same dirs + keypair, role param flip, teardown verbatim between opens)"
  - "Pattern: live-leg loud-skip contract (labelled message + deterministic stand-in named + runbook), Tier3-registered and lane-excluded"

requirements-completed: [POLICY-02]

coverage:
  - id: D1
    description: "t0-t2 timeline: archive seed all-Durable + fingerprint, light re-open interlock fire/ack, held-drainer prune cycle with markers + refusal + remote unchurned"
    requirement: POLICY-02
    verification:
      - kind: integration
        ref: "ctest -R cold_downgrade_e2e_test (TimelineT0ThroughT3 green: erased>0, journal-stays-Durable, NOT_FOUND->PRUNED, HISTORY_PRUNED_LOCALLY, ObjectKeys unchanged)"
        status: pass
    human_judgment: false
  - id: D2
    description: "t3 steady state: exemption carrying the walk in-band (walk-exempted > 0), below-link retention eviction through the real GC, remote-backed serving of non-pruned cold, seals untouched"
    requirement: POLICY-02
    verification:
      - kind: integration
        ref: "ctest -R cold_downgrade_e2e_test (PollUntil gc_last_pass_exempted>0 + IsColdDisposed(spender) + remote-backed GetNodeWithoutRequest + isResolved)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Tier-3 live leg with the loud-skip contract on a real MinIO stack through the production S3 client"
    requirement: POLICY-02
    verification:
      - kind: manual_procedural
        ref: "ungated direct-binary run shows [SGNS_COLD_DOWNGRADE][LIVE-SMOKE] labelled skip naming the stand-in; ctest -L Tier1 -N does not list it; the gated live execution is the dev-opt-in UAT (18-USER-SETUP.md)"
        status: pass
    human_judgment: true
    rationale: "the live MinIO execution itself is a dev-opt-in UAT item (the plan's user_setup block) - the loud-skip contract is automated, the live run is not CI-enforced by design"

duration: 75min
completed: 2026-11-19
status: complete
---

# Phase 18 Plan 03: Downgrade E2E t0->t3 + Tier-3 Live Smoke Summary

The downgrade is E2E-proven on the locked single-node topology — archive era, interlock fire/ack, a structurally-dead drainer still erasing against archive-era Durable evidence, markers + refusal activating, and the t3 steady state where retention evicts below-link data, the remote tier serves it back, and the 18-01 exemption carries every GC walk.

## Performance

- **Duration:** 75 min
- **Tasks:** 3 / 3
- **Files:** 3 code (1 new live suite, 1 extended E2E, 1 cmake) + 1 planning (USER-SETUP)

## Tasks Completed

1. **t0-t2** - `test(18-03)` `8ce2557a4`: the timeline over persistent fakes (D-10 remote modeling), the interlock fire at t1, SC3 the strong way at t2.
2. **t3** - `test(18-03)` `c167ee838`: retention 1ms + 50ms cadence; exemption in-band; below-link eviction + remote-backed serving + seals.
3. **Live smoke** - `test(18-03)` `2c94e481b`: Tier-3 MinIO-backed compact timeline; loud-skip verified; lane-excluded.

## Evidence (for 18-04's policy record)

- **TimelineT0ThroughT3** (Tier-1, cold_downgrade_e2e_test): t0 FirstRun + record parses as Archive; t1 DowngradeUnacknowledged + zero markers + objects intact + ack DowngradeAcknowledged; t2 `stats.erased > 0`, journal stays Durable, marker NOT_FOUND->PRUNED, refusal `HISTORY_PRUNED_LOCALLY`, objects unchurned; t3 `gc_last_pass_exempted > 0`, `IsColdDisposed(spender)`, remote-backed `GetNodeWithoutRequest(spender)` succeeds, seals true, objects unchurned.
- **LiveStack_DowngradeTimelineWithExemptionWalk** (Tier-3, opt-in): the same timeline on real MinIO through the production client; ungated = loud labelled skip.
- t3 semantics note: the exempted leaf is walk-pinned (its cold copy stays); what evicts is the below-link non-pruned data the leaf orphans — the observable class recorded for the policy record.

## Deviations from Plan

- **[Rule 1-3 - Fixture-exposed drive] t3 GC driven by the stack's own GC thread (retention 1ms + 50ms cadence + PollUntil on observables), not direct GcPassOnce** - Found during: Task 2 | Issue: the plan's determinism posture prefers direct-drive, but the GlobalDB-owned manager is private (the compose-matrix fixture's own recorded posture: "the manager is private; the thread IS the driver"); retention 1ms makes every t0 spill timestamp provably old without a Backdate surface (which the GlobalDB stack does not expose) | Fix: the proven compose-matrix GC posture (retention 1ms, interval 50ms, grace 1ms) + PollUntil bounded predicates on GetColdStorageStatus/IsColdDisposed | Verification: timeline green, Tier-1 lane 19/19 | Commit: c167ee838
- **[Rule 1-3 - Semantics clarification] t3's eviction target is the below-link spender, not the pruned victim** - Found during: Task 2 analysis | Issue: the exempted leaf is walk-visited (pinned), so its own local cold copy is not evictable; the plan's "local cold copies of pruned data" phrasing reads as the pruned CID itself | Fix: assert the eviction on the below-link non-pruned block (the data the exempted leaf orphans) and record the class distinction in the commit + this SUMMARY - the honest observable | Commit: c167ee838
- **[Rule 1-3 - Stage posture] t3 clears the admin fault** - Found during: Task 2 | Issue: the GC staging gate (RefreshStagingStats) requires a healthy admin; with the admin held Unreachable every pass is inhibited and t3 cannot run | Fix: Put stays faulted (unchurned structural; no pending uploads exist anyway - every record is Durable), admin clears for the t3 stack only; SC3 was already proven at t2 under the fully-held posture | Commit: c167ee838

**Total deviations:** 3 auto-fixed (all mechanical/observable-class clarifications; none weaken a must_have). **Impact:** none - SC3's strong-way proof happened at t2 under the fully-held drainer; t3's posture change is after the SC3 evidence is complete.

## Issues Encountered

None.

## Next Phase Readiness

Ready for 18-04 (the policy record) - every leg name and observable this plan produced is cited in the Evidence section above.

## USER SETUP

⚠️ **USER SETUP REQUIRED** — `.planning/workstreams/rocksdb-backup/phases/18-role-downgrade-collectibility-policy-gc-walk-gap-exemption/18-USER-SETUP.md`: the Tier-3 live leg needs `SGNS_BLOCKSTORE_TEST_MINIO_BIN` (MinIO community build) + the one-time bucket creation. The Tier-1 hermetic evidence is complete without it.
