---
gsd_state_version: "1.0"
milestone: v1.0
milestone_name: CRDT Cold-Storage BlockStore Library (Sia s3d backend)
current_phase: 1
current_phase_name: BlockStore Contract, Memory Backend & Conformance Kit
current_plan: N/A
status: planning
stopped_at: Phase 1 context gathered
last_updated: "2026-10-20T20:49:36.549Z"
last_activity: 2026-10-19
last_activity_desc: v1.0 ROADMAP.md created (5 phases, 21 requirements mapped)
state_head: cf5f6be20b55f67dc5979da2c1769db237084d78
progress:
  total_phases: 5
  completed_phases: 0
  total_plans: 3
  completed_plans: 0
---

# Project State

## Project Reference

See: `.planning/PROJECT.md`, workstream sections; `.planning/workstreams/rocksdb-backup/REQUIREMENTS.md`; `.planning/workstreams/rocksdb-backup/ROADMAP.md`

**Core value:** Older CRDT/IPLD blocks can spill from RocksDB hot state to durable, CID-verified object storage through a shared thirdparty static library (`sgns-blockstore`) consumable by both SuperGenius and genius-tube — no RocksDB remote-FS integration, no SDK/SuperGenius types in the public API, and local eviction is never a CRDT deletion.

**Current focus:** v1.0 roadmap created (Phases 1-5, 21/21 requirements mapped) — ready for `/gsd-plan-phase 1`

## Current Position

Phase: 1 (BlockStore Contract, Memory Backend & Conformance Kit) — READY TO EXECUTE
Plan: —
Status: Roadmap complete, awaiting Phase 1 planning
Last activity: 2026-10-19 — v1.0 ROADMAP.md created (5 phases, 21 requirements mapped)

## Progress

**Phases Complete:** 0/5
**Current Plan:** N/A

| Phase | Plans | Status |
|-------|-------|--------|
| 01 — BlockStore Contract, Memory Backend & Conformance Kit | 0/TBD | Not started |
| 02 — LocalBlockStore (RocksDB Cold Tier) | 0/TBD | Not started |
| 03 — minio-cpp Integration & S3Client Adapter | 0/TBD | Not started (--research-phase flagged) |
| 04 — S3BlockStore & Sia s3d Roundtrip | 0/TBD | Not started |
| 05 — Fault Injection & Three-Tier Hardening | 0/TBD | Not started |

## Accumulated Context

**Key decisions (from research SUMMARY, 2026-10-19):**
- Phase order follows dependency facts: CORE-* type-system decisions are retrofit-brutal → Phase 1; minio-cpp build risk isolated → Phase 3; TEST-02 fault injection depends on Phase 2's upload journal → Phase 5
- C1 CID-dependency conflict (libp2p `p2p_cid` vs ipfs-lite-cpp granular `cid` target) → day-one Phase-1 spike; record the decision before planning starts
- C3/C4 interface shape: no Remove/Delete in the v1 core API; enumeration only on a separate tooling/audit interface — frozen Phase-1 decisions with a guard test
- C2 CI S3 endpoint: MinIO server binary as child process (repo CI runners have no Docker); s3d stays dev-gated only
- s3d 200-OK ≠ durable (staged on local disk) → 4-value DurabilityLevel + honest ObjectStoreAccepted semantics in Phase 1; durability-signal discovery pinned in Phase 4

**Todos:**
- Run `/gsd-plan-phase 1` (C1 CID spike is the entrance criterion)

**Blockers:** None

## Session Continuity

**Last session:** 2026-10-20T19:16:58.712Z

**Stopped At:** Phase 1 context gathered
**Resume File:** .planning/workstreams/rocksdb-backup/phases/01-blockstore-contract-memory-backend-conformance-kit/01-CONTEXT.md
