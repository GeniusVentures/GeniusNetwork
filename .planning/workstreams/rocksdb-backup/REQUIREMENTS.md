# Requirements: sgns-blockstore — CRDT Cold-Storage BlockStore Library

**Defined:** 2026-10-19
**Workstream:** rocksdb-backup
**Milestone:** v1.0 — CRDT Cold-Storage BlockStore Library (Sia s3d backend)
**Core Value:** Older CRDT/IPLD blocks can spill from RocksDB hot state to durable, CID-verified object storage through a shared thirdparty static library (`sgns-blockstore`) consumable by both SuperGenius and genius-tube — no RocksDB remote-FS integration, no SDK or SuperGenius types in the public API, and local eviction is never a CRDT deletion.

**Authoritative design reference:** `supergenius-sharded-ipld-cache-architecture.md` (workspace root) — this milestone delivers the doc's Phase 1 (block-store abstraction) + Phase 2 (S3 backend) vertical slice only.
**Research:** `.planning/research/*-rocksdb-backup-2026-10-19.md` (STACK / FEATURES / ARCHITECTURE / PITFALLS / SUMMARY)

## v1 Requirements

### Core Contract (CORE)

- [x] **CORE-01**: `BlockStore` public interface exposes core operations (`Put`, `Get`, `Has`, `GetSize`) with structured result types; installed headers carry only CID/bytes/strings — no SDK types, no SuperGenius types
- [x] **CORE-02**: Status taxonomy distinguishes `Found` / `NotFound` / `TemporarilyUnavailable` / `Corrupt` / `Unauthorized`; transport failures, timeouts, and backend outages never surface as `NotFound`
- [x] **CORE-03**: `DurabilityLevel` enum and capability struct ship in the v1 API (anchors future eviction work; retrofit would be an API break)
- [x] **CORE-04**: CID verification happens at the facade boundary — every fetched byte is verified against the requested CID; corrupt results are rejected and attributed to their source
- [x] **CORE-05**: No delete-shaped API — local eviction (`EvictLocal`) only; nothing in the API can remove remote blocks or CRDT history
- [x] **CORE-06**: Enumeration is exposed via a separate tooling/audit interface; the core `BlockStore` interface stays List-free

### Backends (BACK)

- [x] **BACK-01**: `MemoryBlockStore` hermetic reference implementation
- [x] **BACK-02**: Reusable `BlockStoreConformanceTests` kit runs against every backend implementation
- [x] **BACK-03**: `LocalBlockStore` opens its own RocksDB instance (consumer-provided; API-compatible with both RocksDB 9.4 and 11.1), never the GlobalDB handle; writes are atomic (temp + fsync + rename)
- [x] **BACK-04**: `LocalBlockStore` maintains a durable upload journal recording pending remote uploads, recoverable after crash
- [x] **BACK-05**: Internal `S3Client` adapter interface (~5 ops: put/get/head/delete + config) with an `InMemoryS3Client` fake for hermetic tests
- [x] **BACK-06**: `MinioS3Client` implementation via minio-cpp; SDK types never leak past the adapter
- [x] **BACK-07**: `S3BlockStore` uses the `v1/blocks/` full-CID (codec-preserving) key layout, conditional create-only PUTs, and HEAD→exists mapping (200/404→bool, everything else→`TemporarilyUnavailable`)

### Thirdparty Integration (BUILD)

- [x] **BUILD-01**: `sgns-blockstore` exists as a new `thirdparty/` submodule with a CMake static-library target and installed public headers
- [x] **BUILD-02**: minio-cpp integrated at upstream tag as a submodule, shaderc-style — its own dependency mechanism fetches/bundles nested deps (pugixml/cpp-httplib/inih) inside the ExternalProject step, statically linked and non-exported; pinning enforced per its mechanism (or a small patch step mirroring the shaderc `git-sync-deps` precedent at `CommonTargets.cmake:438`); no GNUS fork, no separate dep submodules
- [x] **BUILD-03**: `sgns-blockstore` and minio-cpp wired into `thirdparty/build/CommonTargets.cmake` ExternalProject orchestration across all five platform builds

### Sia s3d & Durability (S3D)

- [ ] **S3D-01**: S3 integration tests run against a local MinIO binary (opt-in; no Docker-in-CI dependency)
- [ ] **S3D-02**: Live Sia `s3d` end-to-end roundtrip acceptance test — dev-gated (requires Sia account), evidence artifact committed, never in CI
- [x] **S3D-03**: Durability-signal discovery — probe s3d's admin API (`/stats/uploads` + `openapi.yml`) to characterize staged-vs-durable semantics; documented finding (polling implementation is fast-follow work)

### Testing & Hardening (TEST)

- [ ] **TEST-01**: Three-tier test strategy — Tier 1 hermetic fakes in CI, Tier 2 MinIO-binary opt-in, Tier 3 s3d dev-only; no live endpoints in CI, no fixed sleeps
- [ ] **TEST-02**: Fault/crash injection — partial uploads, crash between local commit and remote upload, journal recovery, corrupt-response rejection

## Future Requirements

Deferred (with reconsideration triggers, per research):

- Metrics surface — corruption counters, fetch latency, backend attribution (fast-follow after v1.0)
- Scale/measurement probe — SQLite metadata growth, staging disk usage, PUT/GET throughput (input for the CARv2 decision; doc Phase 6)
- Tiered retrieval / peer racing (`TieredBlockStore`, request coalescing) — doc Phase 3; needs measured latencies
- Path-based sharding (rendezvous hash, manifests) — doc Phase 4; needs a stable path-component decision
- Eviction-policy enforcement (durability-state gating) — doc Phase 5; consumes CORE-03 types
- CARv2 packing — doc Phase 6; only if measurements justify it
- SuperGenius-side `BlockStoreBackedIpfsDatastore` adapter + `globaldb.cpp:322-344` wiring + `CommonBuildParameters.cmake` consumer entry — later milestone
- CRDT-history garbage collection — requires a formal causal-stability/reachability spec first

## Out of Scope

| Feature | Reason |
|---------|--------|
| RocksDB remote-filesystem / SST-archive / storage-engine integration | Explicitly ruled out by the architecture doc — application-level content-addressed layer instead |
| Modifying the existing RocksDB `BackupEngine` path in `globaldb.cpp` | Separate, simpler mechanism; stays untouched |
| Any SuperGenius production-code change this milestone | Library ships standalone; the consumption seam is documented only (research ARCHITECTURE file) |
| AWS SDK for C++ | Rejected — libcurl/CRT dependency weight vs minio-cpp's cpp-httplib footprint |
| Deleting or pruning archived CRDT history/tombstones | CRDT correctness — no formal GC policy exists; eviction ≠ delete is a v1 invariant |
| Docker-based test services in CI | Repo CI runners cannot host Docker (documented in research PITFALLS) |
| Live-internet endpoints in CI | Hermeticity requirement |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CORE-01 | Phase 1 | Complete |
| CORE-02 | Phase 1 | Complete |
| CORE-03 | Phase 1 | Complete |
| CORE-04 | Phase 1 | Complete |
| CORE-05 | Phase 1 | Complete |
| CORE-06 | Phase 1 | Complete |
| BACK-01 | Phase 1 | Complete |
| BACK-02 | Phase 1 | Complete |
| BUILD-01 | Phase 1 | Complete |
| BACK-03 | Phase 2 | Complete |
| BACK-04 | Phase 2 | Complete |
| BUILD-02 | Phase 3 | Complete |
| BUILD-03 | Phase 3 | Complete |
| BACK-05 | Phase 3 | Complete |
| BACK-06 | Phase 3 | Complete |
| BACK-07 | Phase 4 | Complete |
| S3D-01 | Phase 4 | Pending |
| S3D-02 | Phase 4 | Pending |
| S3D-03 | Phase 4 | Complete |
| TEST-01 | Phase 5 | Pending |
| TEST-02 | Phase 5 | Pending |

---
*Requirements defined: 2026-10-19 — rocksdb-backup workstream, milestone v1.0*
