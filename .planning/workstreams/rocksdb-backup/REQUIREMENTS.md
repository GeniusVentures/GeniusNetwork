# Requirements: rocksdb-backup v1.1 — SuperGenius Cold-Storage Integration & CRDT Garbage Collection

**Defined:** 2026-10-22
**Workstream:** rocksdb-backup
**Milestone:** v1.1 — SuperGenius Cold-Storage Integration & CRDT Garbage Collection
**Core Value:** SuperGenius nodes gain durable, retrievable cold storage for aging CRDT data through the shipped `sgns-blockstore` library — config-gated so unchanged deployments behave identically, spill-on-write keeps s3d current, and GC reclaims local space without ever sacrificing retrievability or CRDT correctness.

**Authoritative design reference:** `supergenius-sharded-ipld-cache-architecture.md` (workspace root) — this milestone delivers the doc's consumer-integration vertical: block spill (write path), cold read fallback (read path), and eviction-only GC under its CRDT correctness requirements.
**Prior milestone:** v1.0 (archived at `milestones/v1.0-*`) — the complete sgns-blockstore library: frozen contract, Memory/Local(RocksDB)/S3 backends, upload journal, UploadDrainer, three-tier testing, fault injection.
**Research:** `.planning/research/*-rocksdb-backup-2026-10-22.md` (STACK / FEATURES / ARCHITECTURE / PITFALLS / SUMMARY)

## v1.1 Requirements

### Library Prerequisites (LIB)

- [x] **LIB-01**: `sgns-blockstore` accepts blake2b-256 CIDv1 blocks additively alongside sha-256 (hash-gate widening with known vectors for DAG_CBOR/blake2b; conformance kit + guard tests extended; no public-API break) — the Phase-0 blocker: every CRDT DAG block is CIDv1/DAG_CBOR/blake2b-256
- [x] **LIB-02**: an installed factory (e.g. `OpenMinioS3Client(S3ClientConfig)` exported from installed `S3Client.hpp`) lets consumers construct the production S3 client from the install tree without non-installed headers

### Build & Config (INTG)

- [x] **INTG-01**: SuperGenius and GeniusSDK resolve sgns-blockstore via `find_package(sgns-blockstore CONFIG REQUIRED)` against the superbuild install tree in both `CommonBuildParameters.cmake` files (ordered after the miniocpp dependency chain), linking `sgns-blockstore::sgns-blockstore` on all desktop platforms
- [x] **INTG-02**: `crdt_config.json` gains a blockstore section (endpoint, access key, secret key, bucket; optional prefix/path-style/tls) — blank or absent ⇒ blockstore not constructed, behavior byte-identical to today; malformed ⇒ loud startup failure (never silent disable); `SGNS_BLOCKSTORE_S3_ACCESS_KEY`/`_SECRET_KEY` env vars take precedence; credentials never logged

### Spill-on-Write (SPILL)

- [x] **SPILL-01**: every CRDT block Put passing the `IpfsDatastore` seam (`globaldb.cpp:329`) journals block + PendingUpload record into `LocalBlockStore` atomically — local WAL only, no remote I/O on the `dagMutex_`-held write path
- [x] **SPILL-02**: a background UploadDrainer thread drains the journal to S3 (backup-loop lifecycle pattern) with a defined backpressure policy when s3d is slow/unavailable, and drains cleanly at shutdown / resumes from the journal after crash-restart

### Read Fallback (READ)

- [x] **READ-01**: local node reads that miss the hot datastore fetch from the blockstore (Local tier → S3 tier), CID-verify, and re-cache before returning; transport failures surface as `TemporarilyUnavailable`, never as `NotFound`
- [x] **READ-02**: graphsync serving for a CID not held locally performs an async cold fetch with a deadline, off the responder's inline path (the past whole-node-freeze hazard), CID-verifies, then serves

### Durability (DUR)

- [x] **DUR-01**: recorded durability advances LocalCommitted → ObjectStoreAccepted → Durable via s3d `/objects/flush` + `pendingObjects==0` evidence (`MarkUploadedDurable`); local bytes become evictable only after the configured durability state is recorded

### Garbage Collection (GC)

- [ ] **GC-01**: a configurable retention policy (age threshold in `crdt_config.json`) identifies cold-eligible CRDT data; policy evaluation never touches tombstones or head-reachable causal history
- [ ] **GC-02**: eviction-only GC removes block bytes locally (two-phase: durability-record gate + non-reachability check; block bytes, resolved marker, and set rows evicted as one unit) and writes a bounded disposed-CID marker yielding authoritative `NotFound` + re-broadcast dedup; tombstones and CRDT metadata are never purged in v1.1
- [ ] **GC-03**: any GC-evicted CID remains retrievable end-to-end — a graphsync request or local read for it resolves from the blockstore, CID-verified

### Testing (TEST)

- [x] **TEST-01**: hermetic Tier-1 integration tests (InMemoryS3Client fake; config-gate, spill, fallback, GC paths) run in the fail-closed CI lane on all platforms — no Docker, no live endpoints
- [ ] **TEST-02**: hardening evidence — evict × serve × drain fault races, a resurrection counter-test (restore must not resurrect GC'd values), an s3d-unavailable soak with bounded journal growth, and fresh-clone Tier-1 green on Windows/Linux/macOS with cold storage ON
- [ ] **TEST-03**: dev-gated live tier — MinIO-binary opt-in roundtrip plus one live s3d spill → GC → retrieve E2E with committed evidence artifacts; never in CI

## Future Requirements

- Epoch-based deletion compaction with checkpoint bootstrap (consensus-anchored; the Merkle-CRDT "external source of truth" SuperGenius uniquely has) — v2+; v1.1 records only an epoch watermark
- Metrics surface — corruption counters, fetch latency, backend attribution, journal depth (fast-follow)
- CARv2 packing — only if per-CID object measurements justify it (doc Phase 6)
- Tiered retrieval peer racing / staggered peer-vs-object-store races — needs measured latencies (doc Phase 3)
- Eviction-policy watermark enforcement (high/low disk watermarks, LRU classes) beyond the GC age gate
- Mobile consumer legs (iOS/Android) — pending verification that the superbuild produces sgns-blockstore install trees there

## Out of Scope

| Feature | Reason |
|---------|--------|
| Tombstone or CRDT-metadata purging | Age-only tombstone purge is forbidden by the architecture doc; epoch-based deletion is v2+ (Future) |
| Deleting remote/archived objects from s3d | Eviction ≠ delete is a v1 invariant; the cold store is the system of record for GC'd data |
| RocksDB `BackupEngine` / `globaldb.cpp` backup-path changes | Separate mechanism, stays untouched |
| New external dependencies (AWS SDK, curl, etc.) | v1.0 rejected them; minio-cpp already integrated |
| Docker-based test services or live-internet endpoints in CI | Repo CI runners cannot host Docker; hermeticity requirement |
| Per-object durability-signal polling beyond flush-gating | s3d v0.2.1 has no per-object signal (v1.0 S3D-03 finding); polling implementation is fast-follow |
| SuperGenius production behavior changes when blockstore config is blank | Blank config MUST leave behavior identical to today (acceptance criterion, not an exclusion of the integration) |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| LIB-01 | Phase 6 | Complete (06-01; verification 17/17 2026-10-22 — checkbox repaired 2026-10-24, verb had left it stale) |
| LIB-02 | Phase 6 | Complete (06-02; verification 17/17 2026-10-22 — checkbox repaired 2026-10-24, verb had left it stale) |
| INTG-01 | Phase 7 | Complete (07-01; Windows local evidence; Linux/macOS via CI on push) |
| INTG-02 | Phase 7 | Complete (07-02 + 07-03; matrix green, wallet parity) |
| SPILL-01 | Phase 8 | Complete (08-01 + 08-03; journal-first seam, SC1 latency benchmark) |
| SPILL-02 | Phase 8 | Complete (08-02 + 08-03; drainer, backpressure config, crash-resume, outage window) |
| READ-01 | Phase 9 | Complete (09-01 + 09-03; chain + taxonomy fault matrix, SC1/SC3/SC4 evidence — checkboxes repaired 2026-10-27, verb had left them stale) |
| READ-02 | Phase 9 | Complete (09-02 + 09-03; re-warm executor + wrapper, SC2 freeze/latency evidence — checkboxes repaired 2026-10-27, verb had left them stale) |
| DUR-01 | Phase 10 | Complete (10-01 + 10-02; evidence-gated advancement + SC3/SC4 honesty suites, 2026-10-26) |
| GC-01 | Phase 11 | |
| GC-02 | Phase 11 | |
| GC-03 | Phase 11 | |
| TEST-01 | Phase 7 | Complete (07-03; Windows local lane green; CI yaml committed, runtime on push) |
| TEST-02 | Phase 12 | |
| TEST-03 | Phase 11 | |

---
*Requirements defined: 2026-10-22 — rocksdb-backup workstream, milestone v1.1*
