---
phase: 09-cold-read-fallback-local-reads-graphsync-serving
reviewer: inline (Copilot runtime — gsd-code-reviewer spawn unavailable; same contract)
depth: standard
date: 2026-10-27
commits_reviewed:
  - SuperGenius@76e813710 feat(9-01) hook + chain + injection
  - SuperGenius@157d7e1ce test(9-01) happy paths
  - SuperGenius@f9236a5c4 feat(9-01) getNode leg + precedence + HasBlock
  - SuperGenius@1a6fd18ea test(9-01) taxonomy breadth
  - SuperGenius@8ffae19ec feat(9-02) re-warm executor
  - SuperGenius@459308fba feat(9-02) ColdServeDagService wrapper
  - SuperGenius@c730e5be8 test(9-02) SC2 suite
  - SuperGenius@b08fc9cc4 test(9-03) fault matrix
  - SuperGenius@70e17d501 test(9-03) silence + regression
  - SuperGenius@b17643b5a test(9-03) banners
files_reviewed:
  - SuperGenius/src/crdt/cold_read_fallback.hpp
  - SuperGenius/src/crdt/globaldb/ColdReadService.hpp
  - SuperGenius/src/crdt/globaldb/ColdReadService.cpp
  - SuperGenius/src/crdt/graphsync_dagsyncer.hpp
  - SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStackStub.cpp
  - SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp
  - SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp
  - SuperGenius/src/crdt/globaldb/globaldb.hpp
  - SuperGenius/src/crdt/globaldb/globaldb.cpp
  - SuperGenius/src/crdt/globaldb/BlockStoreBackedIpfsDatastore.cpp
  - SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp
  - SuperGenius/test/src/crdt/cold_read_freeze_latency_test.cpp
counts: { critical: 0, warning: 2, info: 3 }
---

# Phase 9 Code Review

Scope: all Phase-9 commits (READ-01/READ-02), standard depth — per-file analysis of the cold-read chain, re-warm executor, responder wrapper, and lifecycle wiring, plus the two Tier-1 suites.

## Verdict

No Critical findings. The phase lands a clean ungated/gated boundary (no sgns-blockstore type crosses into always-compiled TUs), mutex discipline is correct (cold_store_mutex_ / remote_store_mutex_ / rewarm_mutex_ with a one-directional nesting order rewarm→idle and no cycle), the disabled bar is preserved structurally (null hook short-circuits in both the DAGSyncer helper and the wrapper), and the freeze hazards stay closed by construction (the wrapper waits on nothing; HasBlock is local-only).

## Findings

### W-01 — Repeat chain-run per read for a block whose bytes fail DAG-node parsing (Warning, robustness/efficiency)

- **File:** `impl/graphsync_dagsyncer.cpp` (`FetchNodeFromColdStorage`)
- **Issue:** When a cold fetch succeeds and Rehydrate writes the hot store, the node is produced by re-reading via `GetNodeFromMerkleDAG`. If those bytes do not parse as an IPLD node (possible for RAW blocks), the re-read fails and EVERY subsequent read re-runs the cold chain. Repeat cost is bounded — Rehydrate's journal write means the chain hits the LOCAL tier on every retry (no repeated S3 Gets) — but each read still pays a chain traversal plus an idempotent rehydrate write.
- **Risk:** low (CRDT DAG blocks are DAG_CBOR and parse; a pathological block degrades to a cheap repeated local read, never data loss or a freeze).
- **Recommendation:** document the behavior at the helper (or LRU-cache the failure for a bounded window in a future phase).

### W-02 — Worker loop has no top-level catch (Warning, hardening)

- **File:** `ColdReadService.cpp` (`RewarmWorkerLoop`)
- **Issue:** `Get()` catches `std::invalid_argument` per tier, but any OTHER exception escaping library or datastore code on the worker thread (e.g. a RocksDB-layer throw through `Rehydrate` → decorator `set()` → inner write) would propagate out of the thread function and terminate the process.
- **Risk:** low-probability (the Phase-8 drainer thread shipped the identical shape and no such throw has been observed), but the blast radius is the whole node.
- **Recommendation:** wrap the per-item body in a `try { ... } catch (...) { log + count + erase map entry }` — a 5-line hardening candidate for `gsd-quick`.

### I-01 — `EnqueueRewarm` cannot distinguish attached vs enqueued (Info, API)

Both "already in flight" and "newly enqueued" return true. The only caller (the wrapper) discards the result by contract; the distinction is unobservable where it matters. Documented in the header; no change needed.

### I-02 — Re-warm worker started in `GlobalDB::New` before later construction steps (Info, lifecycle)

If a later step of `New` fails, the worker runs with no subscribers until destruction; `ShutdownNow` (called from the destructor) stops it with the bounded-grace join. Benign by construction; noted for the record.

### I-03 — Budget measured from enqueue, not from first byte (Info, semantics)

`kRewarmBudget` bounds scheduling + waiting only (RESEARCH §6.4); a hung S3 Get pins the single worker until the SDK's own HTTP timeout. This is the documented flagged assumption (09-02 A1) — recorded here for review visibility, not a defect.

## Security checks

- Credentials/endpoints never logged: all cold-failure lines carry `BlockStatus.code` integers or fixed text only; the responder wrapper logs nothing per-request. Redaction-by-omission preserved.
- The re-warm fetch path reuses the 09-01 chain (library CID verification cannot be bypassed — T-9-07); corrupted bytes classify Corrupt and are never re-cached (verified by `SC3_*` cases).
- No new trust boundary crossed beyond the phase's registered threats (T-9-05..T-9-08) — peer-induced re-warms are bounded by coalescing + queue depth (proven by `D07_*` cases).

## Regression posture

`crdt_test`, `globaldb_integration_test`, `cold_storage_config_gate_test`, and the full Tier-1 lane (5 targets, fail-closed) green on `build/Windows/Debug` at HEAD `b17643b5a`.
