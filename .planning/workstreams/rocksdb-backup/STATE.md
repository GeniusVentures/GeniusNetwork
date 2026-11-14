---
gsd_state_version: "1.0"
milestone: v1.2
milestone_name: SuperGenius Cold-Storage Archive Integration
status: planning
last_updated: "2026-11-14T02:41:08.053Z"
last_activity: 2026-11-13
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: `.planning/PROJECT.md` (workstream sections); `.planning/workstreams/rocksdb-backup/ROADMAP.md`; v1.0 archive: `.planning/workstreams/rocksdb-backup/milestones/` (ROADMAP, REQUIREMENTS, MILESTONE-AUDIT, phase artifacts)

**Core value:** Older CRDT/IPLD blocks can spill from RocksDB hot state to durable, CID-verified object storage through a shared thirdparty static library (`sgns-blockstore`) consumable by both SuperGenius and genius-tube — no RocksDB remote-FS integration, no SDK/SuperGenius types in the public API, and local eviction is never a CRDT deletion.

**Current focus:** v1.1 shipped & archived 2026-11-10 — planning next milestone (`/gsd-new-milestone`)

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-11-13 — Milestone v1.2 started

## Progress

**Phases Complete:** 7/7 (v1.1) · v1.0 archived 2026-10-22 · v1.1 archived 2026-11-10

All v1.1 phases shipped — see [milestones/v1.1-ROADMAP.md](milestones/v1.1-ROADMAP.md) for the completion record.

## Accumulated Context

**Key decisions (from v1.1 research SUMMARY, 2026-10-22):**
- BLOCKING: CRDT DAG blocks are CIDv1/DAG_CBOR/blake2b-256 but the v1.0 library gates on sha-256 → Phase 6 widens additively (blake2b widening preferred over dual-CID mapping; conformance kit + guards extended)
- Second library gap: MinioS3Client not installed → installed `OpenMinioS3Client` factory (Phase 6)
- Single integration seam: the IpfsDatastore at globaldb.cpp:329 — one decorator delivers spill + fallback + serving with zero changes to GraphsyncDAGSyncer/CrdtDatastore/ipfs-lite
- Spill discipline: journal-then-drain — never inline S3 on the dagMutex_-held write path; drainer on its own thread mirroring the backup-loop pattern
- GC shape: local-tombstone/eviction-only for v1.1 (dispose bytes past retention, bounded disposed-CID markers, tombstones/metadata never purged; epoch-based deletion compaction is v2+)
- Durability bar: flush-gated (s3d /objects/flush + pendingObjects==0) before local bytes are evictable; ObjectStoreAccepted alone leaves the only copy in s3d staging
- Config: crdt_config.json blockstore section canonical + SGNS_BLOCKSTORE_S3_* env overrides; blank = disabled = today's behavior; malformed = loud failure
- Open planner decisions carried in ROADMAP research notes: config section naming, backpressure policy, retention age evidence (priority-height vs wall-clock), cold-serve latency budget, mobile superbuild leg coverage, GlobalDB backup vs cold-store dir

**Todos:**
- None — v1.1 archived; start the next milestone with `/gsd-new-milestone`

**Blockers:** None

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 261029-uj0 | Debug failing SuperGenius cold storage tests (SC4, CI 40963277318) on macOS - serialize GcPassOnce, fixed OSX fault_race/resurrection aborts (SuperGenius 72e54000) | 2026-10-29 | e9cbd77 | [261029-uj0-debug-failing-supergenius-cold-storage-t](./quick/261029-uj0-debug-failing-supergenius-cold-storage-t/) |

## Session Continuity

**Last session:** 2026-11-11T00:31:29.075Z

**Stopped At:** Phase 12 VERIFIED - UAT 17/17 pass (CI 42905264387 accepted as evidence per user ruling) + 12-VERIFICATION.md PASSED 4/4 (TEST-02). Phase 12 gate closed; next: complete-milestone
**Resume File:** .planning/workstreams/rocksdb-backup/phases/12-integration-hardening-fault-races-fresh-clone-proof/12-VERIFICATION.md

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

- Start the next milestone with /gsd-new-milestone
