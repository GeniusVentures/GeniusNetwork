# Seed: develop-merge exposed erase (v1.2 erasure) × cold-storage retention gap

Date: 2026-11-12
Context: `origin/develop` merged into SuperGenius `dev_blockstore` (merge `55fca03f8`, 275 commits; follow-up `7961ec264`). Recorded as a next-milestone seed because v1.1 is closed and neither feature knew about the other when designed.

## What develop added (their v1.2 erasure work, phases 16-18 in SuperGenius/.planning)

- `GlobalDB::EraseEntry` + `GraphsyncDAGSyncer::StageBlockRemoval` + `GlobalDB::Error::POST_COMMIT_ERASE_ANOMALY` — authoritative CRDT erase with post-commit seal re-check.
- Seal markers: vendored `RocksdbDatastore::seal()/is_sealed()` (thirdparty/ipfs-lite-cpp `datastore_rocksdb.cpp`), key format `<cid>sealed`. Semantics per their header: seal is the traversal terminator preventing re-fetch storms; **erasing a block must never erase its seal**.
- GATE-03 (`EraseSurfaceGateTest.SealKeyHasNoProductionHome` in `test/src/crdt/crdt_erase_test.cpp`): the quoted `"sealed"` literal must have NO production home in SuperGenius `src/` — all seal access must flow through the sanctioned `markResolved`/`isResolved` API (which forward to seal/is_sealed).

## What we shipped in v1.1 (cold storage)

- GC eviction (`ColdStorageManager`) previously deleted `<cid>sealed` rows at eviction and hand-constructed the key with a `"sealed"` literal in `ColdStorageManager.cpp`.
- S3/object storage retains block copies after hot eviction (spill-on-write); `disposed_cids` CF tracks library-side disposal.

## Resolution already applied (commit `7961ec264` on `dev_blockstore`)

- GC eviction now RETAINS seal markers (keep-seal, matching develop's invariant: an evicted-then-re-delivered block stays "already processed").
- Seal reads/writes in `ColdStorageManager` go through the sanctioned `markResolved`/`isResolved` path; no quoted `"sealed"` literal remains in production `src/` — GATE-03 passes.
- Verified: `cold_storage_gc_test` 22/22 (keep-seal assertions), `crdt_test` 47/47 (all erase behavior + gate tests), `cold_storage_gc_retrievability_test` 4/4, `cold_storage_fallback_test` 21/21 (incl. SC4 seal-preservation cases).

## OPEN GAP for next milestone requirements

1. **Erase → cold propagation**: develop's erase removes hot blocks only. A cold-enabled node that already spilled a block keeps the S3 copy — erased content remains recoverable via cold read/re-warm. Need a policy bridging `EraseEntry` to cold disposal (interaction with `disposed_cids`, drainer durability gates, and the never-inline-S3-under-`dagMutex_` rule).
2. **Seal lifecycle on cold-evicted blocks**: seals now stay in hot RocksDB forever (by design, both sides). Assess unbounded seal-row growth vs. spilling seals (they are not DAG blocks; the library gates on CID-shaped keys) — may need a dedicated answer rather than blockstore spill.
3. **Pruned-mesh × cold-read interplay**: develop's erase tests exercise refusal-failover and pruned-history serving; cold-enabled nodes answer `HasBlock` via the cold term first. Verify refusal semantics (`pruned` responses) are not bypassed when the serving node can still fetch the block from cold storage.

## Environmental note (not a gap)

Local Windows network-dependent suites (globaldb_integration/erase-redelivery, resurrection full-wire) currently fail "nodes did not connect" — the CloudflareWARP adapter (100.96.0.1) is picked as the interface address and dials to it hang. Reproduced identically on PRE-merge code (A/B verified 2026-11-12); develop's Windows CI green 12h prior. Disconnect WARP before running pubsub-dependent suites locally.
