---
gsd_state_version: "1.0"
milestone: v1.2
milestone_name: SuperGenius Cold-Storage Archive Integration
current_phase: 19
current_phase_name: Cross-Feature Fault-Race Matrix & Three-Platform CI Capstone
status: executing
stopped_at: "Phase 19: 19-05 Tasks 1+2 COMPLETE; Task 3 - dispatch 3 (run 45257655488, @ 583734cba, thirdparty_tag=test_coldstorage) delivered the WINDOWS + LINUX Release CLOSING EVIDENCE (both lanes green, cold_cross+X11 green on Windows, Tier-1 20/20; Linux x86_64+aarch64 Release green; Android+iOS-Debug green - the stub fix held). iOS-RESOLVED (verified against release assets): the test_coldstorage tag's iOS libMoltenVK.a is the UNMERGED 48-member core archive (no MVKOSExtensions.mm.o = mvkOSVersion() undefined, no SPIRV) while test_coldstorage_rtti carries the complete 139-member merged archive - RE-DISPATCH WITH thirdparty_tag=test_coldstorage_rtti and iOS links; no MoltenVK work needed. REMAINING BLOCKERS: (1) OSX X11 = the REAL production find: the consult teeth passed but the merge happened - the broadcaster's direct peer-queue push is TOPIC-AGNOSTIC and getNode consults evidence only on cold-chain misses, so stored blocks merge unconsulted; the fix (worker-side terminal evidence guard in HandleRootCIDBlock, no-retry marking) is DESIGNED and STASHED in SuperGenius (x11-guard-wip) - local pubsub tests currently wedge even on the pristine tree (dev machine needs a reboot; hermetic cases pass), so the next CI dispatch is the working verifier. (2) OSX compose race-legs (InteractionC/Interleave/Race, tart-VM load; Converge GREEN - the fix held) + cold_storage_resurrection_test Tier-1 (detail untriaged). (3) Linux Debug cold_seal_growth_test (Debug-only soak slowness; Release green). NEXT: decide whether the X11 guard rides the next dispatch (tag=test_coldstorage_rtti); OSX green closes the capstone."
last_updated: "2026-11-23T23:30:00.000Z"
last_updated: "2026-11-23T20:30:00.000Z"
last_updated: "2026-11-23T00:00:00.000Z"
last_updated: "2026-11-21T05:20:00.000Z"
last_activity: 2026-11-20
last_activity_desc: Phase 19 execution started
state_head: 1ffb0aab53656ddecd10fa857f8e787a1c3f02a3
progress:
  total_phases: 7
  completed_phases: 2
  total_plans: 25
  completed_plans: 24
---

# Project State

## Project Reference

See: `.planning/PROJECT.md` (workstream sections); `.planning/workstreams/rocksdb-backup/ROADMAP.md`; v1.0 archive: `.planning/workstreams/rocksdb-backup/milestones/` (ROADMAP, REQUIREMENTS, MILESTONE-AUDIT, phase artifacts)

**Core value:** Older CRDT/IPLD blocks can spill from RocksDB hot state to durable, CID-verified object storage through a shared thirdparty static library (`sgns-blockstore`) consumable by both SuperGenius and genius-tube — no RocksDB remote-FS integration, no SDK/SuperGenius types in the public API, and local eviction is never a CRDT deletion.

**Current focus:** Phase 19 — Cross-Feature Fault-Race Matrix & Three-Platform CI Capstone

## Current Position

Phase: 19 (Cross-Feature Fault-Race Matrix & Three-Platform CI Capstone) — EXECUTING
Plan: 4 of 5 complete
Status: Executing Phase 19 (Wave 5 next — blocking user checkpoint)
Last activity: 2026-11-20 — 19-04 complete (the matrix closed)

## Progress

**Phases Complete:** 0/7 (v1.2) · v1.0 archived 2026-10-22 · v1.1 archived 2026-11-10

v1.2 Phases 13-19 defined — see [ROADMAP.md](ROADMAP.md). v1.1 completion record: [milestones/v1.1-ROADMAP.md](milestones/v1.1-ROADMAP.md).

## Accumulated Context

**Key decisions (from v1.2 research SUMMARY, 2026-11-13):**
- Governing principle: evidence outranks bytes, node-locally — prune markers decide serve-vs-refuse and restore-vs-skip; cold bytes alone are never authoritative
- Governing invariants: never erase hot what is not Durable in cold; node-local prune evidence is terminal; seals are never deleted by any path; collectibility + the GC walk-gap exemption are two halves of one rule, shipped together
- Zero new dependencies — all v1.2 work composes pinned mechanisms (RocksDB 9.4.0, s3d v0.2.1, vendored ipfs-lite-cpp unedited, minio-cpp 1.0.0); no compaction-filter deletion, no DeleteRange
- Two discovered bugs v1.2 must fix (research-verified): the cold-chain resurrection gap (`FetchNodeFromColdStorage` consults no prune evidence) + the forced-walk GC-evicted conflation (`!retained && sealed` treats GC-evicted as pruned)
- Durability gate lives in `TxPruner::RunCycle`'s block-group filter, NOT `PruneEligibility::Evaluate` (contractually pure; develop Phase 17 landing stays a merge, not a rewrite)
- Pruner composition: sequence + close the LRU window — never unify the two pruners; both idempotent on absent keys; reverse order safe by construction
- Frozen constraint: cold collectibility is POLICY-ONLY this milestone (sgns-blockstore v1 has no Remove); the poisoned-GC-triangle constraint is honored by construction
- External gates: the Phase 13 merge gates ALL walk work; develop Phase 17 evaluator shape gates Phase 14 executability (keep the cold conjunct a separate predicate argument)
- Converged phase order: merge (13) → durability gate (14) → evidence-serving + walk fix (15) → pruner×GC hardening (16) → seals measurement (17) → policy/downgrade capstone (18) → fault-race + 3-platform CI capstone (19)
- SEAL probe feeds Phase 15's walk bounds (probe = first plan of Phase 17; the recorded decision closes citing real walk-recovery numbers)
- SEAL-01 measured and decided (2026-11-19): accept hot seal growth — 52.000 B/row measured at 10^6/10^7, 10^8 extrapolated at 5.2 GB / ~16 s full sweep (evidence: phases/17-seal-growth-measurement-decision/17-seal-growth-evidence/); redesign deferred to the recorded D-11 numeric triggers in notes/17-seal-growth-decision.md; D-12 verdict: kForcedWalkPeerFailoverPerCid = 8 validated in-band-with-noted-limitation (hermetic topology, zero production touch)
- POLICY-01/02 decided (2026-11-19): cold permanent this milestone (frozen v1, no Remove) + the GC walk-gap evidence exemption shipped as code (one-predicate consult at the WalkReachable gap site, counted-continue observable) + the downgrade interlock (persisted role fingerprint + downgrade_acknowledged ack key + start-normally disarm) E2E-proven on the t0→t3 single-node timeline; v2 collectibility recorded as a contract ask in notes/18-collectibility-policy-downgrade-interlock.md

v1.1 key decisions archived with the milestone (`milestones/v1.1-ROADMAP.md` + phase artifacts).

**Todos:**
- Next: `/gsd-plan-phase 13` (Bootstrap Branch Merge & Composition Baseline)
- Phase 14 planning needs `--research-phase` (durability monotonicity — `AdvanceDurabilityOnce` code read; develop Phase 17 landing status)

**Blockers:** None — watching two external gates: develop Phase 17/20 timing (composition-vs-rebase if they land mid-milestone) and the bootstrap-merge conflict surface (MEDIUM confidence until the merge executes)

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 261029-uj0 | Debug failing SuperGenius cold storage tests (SC4, CI 40963277318) on macOS - serialize GcPassOnce, fixed OSX fault_race/resurrection aborts (SuperGenius 72e54000) | 2026-10-29 | e9cbd77 | [261029-uj0-debug-failing-supergenius-cold-storage-t](./quick/261029-uj0-debug-failing-supergenius-cold-storage-t/) |

## Session Continuity

**Last session:** 2026-11-21T04:35:00.000Z

**Stopped At:** Phase 19: 19-01..19-04 COMPLETE (SuperGenius b17787b0e; knob-off 16/16 x3 consecutive, RED 9/9 arms with X10 teeth ungated-green, Tier1 20/20). 19-04 closed the matrix: X10 (trichotomy audit + audit-x-GC coherence + empty baseline + byte-flip teeth + VALUE_PRESENT_INVARIANT_VIOLATION counter teeth via WritePrunedEntryForTest) + X11 (the ONE full-wire leg: refusal terminal on the wire - zero cold Gets after the drain-quiesce find; failover serves y-value from A CID-verified; A5 invoked for the A-side concurrent-erase leg - covered by X3-B/X8-B; rebroadcasts bounded-retry vs the address-resolution race). The X1..X11 set is complete. NEXT: /gsd-execute-phase 19 --ws rocksdb-backup runs Wave 5 (19-05: TEST-03 closure - build-release-tags.yml Tier-1 fail-closed lane + the notes/19 rulings doc + refreshed FRESH-CLONE-CHECKLIST + the D-15/D-16 per-platform evidence checkpoint; BLOCKING user checkpoint per the wave marker).
**Resume File:** .planning/workstreams/rocksdb-backup/phases/19-cross-feature-fault-race-matrix-three-platform-ci-capstone/19-CONTEXT.md

## Performance Metrics

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 01 P01 | 22min | 3 tasks | 11 files |
| Phase 01 P02 | 15min | 2 tasks | 14 files |
| Phase 01 P03 | 10min | 3 tasks | 6 files |
| Phase 2 P1 | 35 min | 2 tasks | 10 files |
| Phase 2 P2 | 25 min | 2 tasks | 4 files |
| Phase 2 P3 | 25 min | 2 tasks | 4 files |
| Phase 03 P01 | 55 min | 3 tasks | 13 files |
| Phase 03 P02 | 20 min | 2 tasks | 6 files |
| Phase 03 P03 | 35 min | 3 tasks | 6 files |
| Phase 03 P04 | 56 min | 2 tasks | 7 files |
| Phase 04 P01 | 95 min | 3 tasks | 14 files |
| Phase 04 P02 | 50 min | 3 tasks | 10 files |
| Phase 04 P03 | 45 min | 3 tasks | 5 files |
| Phase 07 P01 | 75 min | 2 tasks | 8 files |
| Phase 07 P02 | 55 min | 2 tasks | 4 files |
| Phase 07 P03 | 50 min | 3 tasks | 6 files |
| Phase 08 P01 | 70 min | 2 tasks | 10 files |
| Phase 08 P02 | 65 min | 2 tasks | 9 files |
| Phase 08 P03 | 55 min | 2 tasks | 2 files |
| Phase 09 P01 | 75 min | 3 tasks | 17 files |
| Phase 09 P02 | 55 min | 3 tasks | 13 files |
| Phase 09 P03 | 30 min | 3 tasks | 2 files |
| Phase 10 P01 | 55 min | 3 tasks | 23 files |
| Phase 10 P02 | 45 min | 2 tasks | 6 files |
| Phase 11 P01 | 90 min | 3 tasks | 16 files |
| Phase 11 P02 | 105 min | 2 tasks | 10 files |
| Phase 11 P03 | 70 min | 2 tasks | 3 files |
| Phase 11 P04 | 75 min | 3 tasks | 6 files |
| Phase 14 P01 | 25min | 2 tasks | 6 files |
| Phase 14 P02 | 20min | 2 tasks | 6 files |
| Phase 14 P03 | 65min | 3 tasks | 3 files |
| Phase 16 P01 | 35min | 2 tasks | 5 files |
| Phase 16 P02 | 55min | 3 tasks | 11 files |
| Phase 16 P03 | 85min | 2 tasks | 5 files |
| Phase 18 P01 | 65min | 2 tasks | 6 files |
| Phase 18 P02 | 50min | 2 tasks | 7 files |
| Phase 18 P03 | 75min | 3 tasks | 5 files |
| Phase 18 P04 | 20min | 2 tasks | 2 files |

## Decisions

Decision log archived with v1.0 (`milestones/v1.0-ROADMAP.md` + `milestones/v1.0-phases/*/` SUMMARYs). Notable outcomes: `p2p_cid` adopted (D-05/D-06); library-local `result<T,BlockStatus>` alias with `policy::terminate` (D-01 shape preserved); D-11 three-shape 412 classification; G-3-1 closed via in-process OpenSSL cert gen + TLS health probe; s3d accepted-is-max-provable durability ceiling documented.
- [Phase 10]: DUR-01 tracer landed: Durable is evidence-backed - AdvanceDurabilityOnce (hybrid floor+quiescence-or-backstop cadence, separate flush backoff) marks exactly the pre-flush Accepted snapshot after flush+pendingObjects==0 via the installed S3AdminClient facade; ctor widened by trailing defaults so the Phase-8 5-arg posture stays compiling — DUR-01 tracer landed: Durable is evidence-backed - AdvanceDurabilityOnce (hybrid floor+quiescence-or-backstop cadence, separate flush backoff) marks exactly the pre-flush Accepted snapshot after flush+pendingObjects==0 via the installed S3AdminClient facade; ctor widened by trailing defaults so the Phase-8 5-arg posture stays compiling
- [Phase 11]: 11-01 GC-01 observe-only retention GC landed: eligibility = spilled-journal Durable (exactly, MI-02) INTERSECT strictly-past-retention age MINUS fresh-walk-reachable MINUS pinned; TRACER fixed the CIDv0 delta-spill defect (EquivalentCidClaim across LocalBlockStore/S3BlockStore verify paths) - CRDT deltas are CIDv0/DAG_PB/sha256, contradicting the research's CIDv1/DAG_CBOR claim; crash/skew/missing-stamp/heads-change all steer to under-eviction — 11-01-SUMMARY key-decisions + deviations 1/4; the CIDv0 fix is load-bearing for Waves 2-4 (no delta spills without it)

## Deferred Items

Items acknowledged and deferred at milestone close, most recent first:

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| hardening | Soak-scale GC eviction-storm crash (12-02 deviation; repro: retention ~1 ms + ~2000 Durable orphans + live GC thread; candidate: mark-capture/eviction at ~2000-mark scale) | open | 2026-11-10 | v1.1 |
| testing | TEST-03 MinIO-binary live leg (`gc_minio_roundtrip_test`, Tier2) registered + loud-skip-verified but never executed live — runbook-deferred (SGNS_BLOCKSTORE_TEST_MINIO_BIN) | open | 2026-11-10 | v1.1 |
| ci | Permanent cmake.yml ON-leg regression-net baseline first runs when dev_blockstore merges to develop (push-filter topology, self-resolving; tag-build legs prove the identical configure) | pending-merge | 2026-11-10 | v1.1 |
| uat_gaps | 03/03-UAT.md | passed | 2026-10-22 | v1.0 |

## Operator Next Steps

- `/gsd-plan-phase 13` — Bootstrap Branch Merge & Composition Baseline (gates all v1.2 recovery/walk work)
