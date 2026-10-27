---
phase: 11-retention-gc-of-cold-eligible-crdt-data
verified: 2026-10-27T23:23:47Z
status: passed
score: 4/4
covered_files:
  - .planning/workstreams/rocksdb-backup/phases/11-retention-gc-of-cold-eligible-crdt-data/11-CONTEXT.md
  - .planning/workstreams/rocksdb-backup/phases/11-retention-gc-of-cold-eligible-crdt-data/11-PATTERNS.md
  - .planning/workstreams/rocksdb-backup/phases/11-retention-gc-of-cold-eligible-crdt-data/11-RESEARCH.md
  - .planning/workstreams/rocksdb-backup/phases/11-retention-gc-of-cold-eligible-crdt-data/11-DISCUSSION-LOG.md
  - .planning/workstreams/rocksdb-backup/phases/11-retention-gc-of-cold-eligible-crdt-data/11-01-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/11-retention-gc-of-cold-eligible-crdt-data/11-01-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/11-retention-gc-of-cold-eligible-crdt-data/11-02-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/11-retention-gc-of-cold-eligible-crdt-data/11-02-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/11-retention-gc-of-cold-eligible-crdt-data/11-03-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/11-retention-gc-of-cold-eligible-crdt-data/11-03-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/11-retention-gc-of-cold-eligible-crdt-data/11-04-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/11-retention-gc-of-cold-eligible-crdt-data/11-04-SUMMARY.md
  - thirdparty/sgns-blockstore/include/sgns-blockstore/LocalBlockStore.hpp
  - thirdparty/sgns-blockstore/include/sgns-blockstore/Cid.hpp
  - thirdparty/sgns-blockstore/src/LocalBlockStore.cpp
  - thirdparty/sgns-blockstore/src/S3BlockStore.cpp
  - thirdparty/sgns-blockstore/test/local_block_store_test.cpp
  - thirdparty/sgns-blockstore/test/s3d_gc_e2e.cpp
  - thirdparty/sgns-blockstore/test/gc_minio_roundtrip_test.cpp
  - thirdparty/sgns-blockstore/test/CMakeLists.txt
  - thirdparty/sgns-blockstore/docs/evidence/gc-e2e/README.md
  - thirdparty/sgns-blockstore/docs/evidence/gc-e2e/run-capture.md
  - thirdparty/sgns-blockstore/docs/evidence/gc-e2e/stats-capture.txt
  - SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp
  - SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStackStub.cpp
  - SuperGenius/src/crdt/globaldb/globaldb.hpp
  - SuperGenius/src/crdt/globaldb/globaldb.cpp
  - SuperGenius/src/crdt/globaldb/ColdReadService.hpp
  - SuperGenius/src/crdt/globaldb/ColdReadService.cpp
  - SuperGenius/src/crdt/cold_read_fallback.hpp
  - SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp
  - SuperGenius/src/account/GeniusNode.cpp
  - SuperGenius/test/src/crdt/cold_storage_gc_test.cpp
  - SuperGenius/test/src/crdt/cold_storage_gc_retrievability_test.cpp
  - SuperGenius/test/src/crdt/cold_storage_config_gate_test.cpp
  - SuperGenius/test/src/crdt/CMakeLists.txt
covered_digest: v2:sha256:e532ed248deceb36f0dd2e30c84cfb8b93acfa1c1796757602cae2e5549c4ad9
---

# Phase 11 Verification: Retention GC of Cold-Eligible CRDT Data

Goal (ROADMAP): eviction-only GC of cold-eligible CRDT data — retention
identification (GC-01), safe destructive eviction (GC-02), preserved
retrievability (GC-03), and live-tier evidence (TEST-03) — with tombstones
and CRDT metadata never purged in v1.1.

## Requirement Verification

### GC-01 — retention policy identifies cold-eligible data (SC1/SC5) — PASS
- Strict `blockstore.retention` config live (7 matrix cases; required
  positive age loud, 0-default cadence, retention-only never activates +
  inert WARN; wallet asset guard counts zero `retention`).
- `GcPassOnce` eligibility = journal-enumerated Durable (exactly
  kEvictionDurabilityGate, MI-02) ∩ strictly-past-retention age ∖
  fresh-walk-reachable ∖ pinned; SC1 prefix-spy proves ZERO hot ops under
  /t/ /h/ /k/ (and /s/ save the eviction unit); source gate counts zero
  CRDT-enumerator calls.
- SC5 epoch watermark written per pass under pinned /crdt/gc/, advisory
  only; honesty cases (resolved-subtree, heads-change abort, backfill
  fairness, staging inhibition, empty pass, fail-closed attach) green.

### GC-02 — two-phase eviction, every crash window under-eviction (SC2) — PASS
- Library half-1 single-batch primitive (3 deletes + marker put) with
  idempotence + all-or-nothing units; dual-bound trim.
- Manager mark/grace (defer-to-next-tick)/delete-time heads-equality
  (vs the mark's OWN snapshot) with cancel-keep-bytes; hot-cleanup half-2
  (binary key + seal text key + exactly the block's OWN s-rows + LRU
  after deletes); orphan re-scan completes half-2 after a between-halves
  crash; dry_run suppresses both halves with identical evidence.
- Fault suite: crash mid-grace deletes nothing + re-marks; delete-time
  cancel keeps all bytes; unreadable evidence maps Unreadable and evicts
  nothing; re-delivery dedup at HasBlock with zero S3 Gets.

### GC-03 — evicted CIDs remain retrievable, CID-verified (SC3) — PASS
- Both legs over real evictions: local read resolves from the S3 tier
  CID-verified (byte-equal to the pre-eviction snapshot) and re-caches
  hot; the graphsync request path (getNode, cold-before-peers) resolves
  with no peers wired; responder don't-have → live re-warm → retry serves.
- Verification honesty: flipped S3 object rejected COLD_STORAGE_CORRUPT
  (never good bytes, never NotFound). Never-purged end-state guard:
  t/k/h keyspaces byte-identical across aggressive passes over a store
  with tombstones; 25-delivery storm dedups with zero S3 traffic.
- Documented deviation (11-03-SUMMARY): the libp2p-mediated two-GlobalDB
  wire was not rebuilt — the request-resolution entry and serving path
  are proven; transport mediation is Phase-9-proven territory.

### TEST-03 — live-tier evidence (SC4) — PASS
- LIVE s3d run (human checkpoint, numbers operator-confirmed): 3 real
  uploads (s3d console: objects=3 size=173, matching reclaimed_bytes=58),
  eviction (local absent, marker present), CID-verified retrieval
  (sha-256 match), reclaimed 1/58B.
- Honest ceiling recorded and log-corroborated: Sia finalize never
  completed ("context canceled" at the client flush budgets; retrieval
  served from s3d staging) — the S3-API vertical is proven live; the
  Sia-cloud durability leg is documented-not-claimed with rerun
  instructions. MinIO Tier-2 tooling shipped (loud-skip verified; binary
  leg not executed this session — runbook documents it).
- Tier discipline: Tier3/Tier2 labels only; Tier-1 lanes hermetic.

## Requirement Traceability

GC-01, GC-02, GC-03, TEST-03 — all four declared by the phase's plans,
all four marked complete in REQUIREMENTS.md with traceability dates,
each backed by its plan's SUMMARY coverage block.

## Verification Evidence (fresh runs, 2026-10-27T23:2xZ)

- SuperGenius Tier-1 lane: 8/8 passed (config gate, gc suite 22 cases,
  gc-retrievability 4 cases, spill/durability/fallback/freeze lanes).
- Library Tier-1 lane: 14/14 passed (journal suites incl. spill-times,
  disposed, trim, crash atomicity).
- Registration/label parity: 8 cold_* registrations == 8 Tier1 labels.
- Live evidence artifacts committed under
  thirdparty/sgns-blockstore/docs/evidence/gc-e2e/ (run-capture.md,
  stats-capture.txt; redaction: credential-value shapes = 0).

## Gaps

None blocking. Noted for future sessions: (1) the Sia-cloud durability
leg needs funded rent + a long flush budget (rerun instructions in the
capture); (2) the MinIO Tier-2 binary leg is available but was not
executed live; (3) 11-03's two-GlobalDB libp2p wire deviation is
documented and consciously accepted.

## Verdict

PASSED — 4/4 requirements verified against the codebase and evidence.
