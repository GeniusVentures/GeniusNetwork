# Roadmap: rocksdb-backup

## Milestones

- 🚧 **v1.0 CRDT Cold-Storage BlockStore Library (Sia s3d backend)** — Phases 1-5 (roadmap created 2026-10-19)

## Phases

- [x] **Phase 1: BlockStore Contract, Memory Backend & Conformance Kit** - `sgns-blockstore` skeleton with the frozen type system (status taxonomy, DurabilityLevel, eviction-safe List-free API), MemoryBlockStore reference implementation, and the reusable conformance kit (completed 2026-10-20)
- [x] **Phase 2: LocalBlockStore (RocksDB Cold Tier)** - Durable local persistence through its own RocksDB instance: atomic writes, crash-recoverable upload journal, verify-on-read (completed 2026-10-20)
- [x] **Phase 3: minio-cpp Integration & S3Client Adapter** - The one genuinely new external surface: minio-cpp at the pinned tag built shaderc-style through the superbuild, isolated behind an internal adapter with an in-memory fake (completed 2026-10-21)
- [ ] **Phase 4: S3BlockStore & Sia s3d Roundtrip** - The terminal cold tier: `v1/blocks/` codec-preserving layout, conditional create-only PUTs, opt-in MinIO-binary tests, dev-gated live s3d E2E, durability-signal discovery
- [ ] **Phase 5: Fault Injection & Three-Tier Hardening** - Prove the trust claims under induced failure: taxonomy honesty, crash recovery, corruption rejection; CI stays fully hermetic

## Phase Details

### Phase 1: BlockStore Contract, Memory Backend & Conformance Kit

**Goal**: The `sgns-blockstore` library exists as a buildable/installable thirdparty target whose public contract is frozen and proven — the retrofit-brutal type-system and API-shape decisions land before any real backend exists
**Depends on**: Nothing (first phase)
**Requirements**: CORE-01, CORE-02, CORE-03, CORE-04, CORE-05, CORE-06, BACK-01, BACK-02, BUILD-01
**Success Criteria** (what must be TRUE):
  1. `sgns-blockstore` builds as a CMake static-library target through the thirdparty superbuild and installs public headers that compile standalone using only CID/bytes/strings — a consumer TU including every installed header pulls in no SuperGenius and no GeniusSDK types (enforced by a compile/grep check)
  2. A caller can Put/Get/Has/GetSize CID-addressed blocks against `MemoryBlockStore` and receives structured results where a missing block reports `NotFound` and an induced backend failure reports `TemporarilyUnavailable`/`Corrupt`/`Unauthorized` — the classes are never conflated
  3. A block whose bytes do not hash to the requested CID is rejected as `Corrupt` with source attribution — proven by the conformance kit's corruption test passing against `MemoryBlockStore`
  4. `BlockStoreConformanceTests` is a reusable suite any backend can instantiate in one step, and it runs green against `MemoryBlockStore` in CI (hermetic, no network)
  5. The API shape is verifiably safe: no delete-shaped method exists (`EvictLocal` is local-only, asserted by a guard test) and enumeration is exposed only on a separate tooling/audit interface, never on `BlockStore` itself

**Plans**: 3/3 plans complete
Plans:
**Wave 1**
- [x] 01-01-PLAN.md — Repo bootstrap, superbuild entry & C1 CID spike (tracer: repo → CommonTargets → install tree → green spike; BUILD-01, p2p_cid adoption per D-05/D-06)

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 01-02-PLAN.md — Frozen v1 contract headers (taxonomy, DurabilityLevel, options, capabilities, List-free interface, tooling seam, FaultController) & MemoryBlockStore reference backend

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 01-03-PLAN.md — Conformance kit (one-macro instantiation + fault seam), API-shape guard tests (SFINAE + include hygiene) & CI ctest lane

**Research note**: Resolve conflict C1 (CID dependency: libp2p `p2p_cid` vs ipfs-lite-cpp granular `cid` target) as a day-one spike — p2p_cid round-trip + `CidOf` helper; fallback = granular-target linking. C3/C4 decisions (no Remove/Delete; List-free core) are frozen here with the guard test.

### Phase 2: LocalBlockStore (RocksDB Cold Tier)

**Goal**: Blocks persist durably on local disk through `LocalBlockStore`'s own RocksDB instance — atomic writes and a crash-recoverable upload journal establish the LocalCommitted tier and the crash-safety machinery the S3 tier reuses
**Depends on**: Phase 1
**Requirements**: BACK-03, BACK-04
**Success Criteria** (what must be TRUE):
  1. A block Put to `LocalBlockStore` survives process restart and is retrieved byte-identical and CID-verified; the store opens its own RocksDB instance/directory (consumer-provided, API-compatible with both RocksDB 9.4 and 11.1), never the GlobalDB handle
  2. The Phase-1 conformance kit runs green against `LocalBlockStore`
  3. An interrupted write never leaves a torn block visible: after a simulated mid-write crash, Get returns either the complete verified block or `NotFound` — never partial or corrupt bytes
  4. After a crash, restart reconciles the durable upload journal (pending remote uploads recorded before the crash are recoverable) and sweeps stale temp files (CONTEXT D-02: vacuous by design — no temp files exist; startup sweep = journal reconciliation only; headers document this mapping)

**Plans**: 3/3 plans complete
Plans:
**Wave 1**
- [x] 02-01-PLAN.md — LocalBlockStore durable tracer: own RocksDB instance, one-batch Put+journal, restart proof, all build wiring (BACK-03/BACK-04; D-01..D-05, pimpl + no-version find_package + superbuild DEPENDS rocksdb)

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 02-02-PLAN.md — Journal lifecycle (D-06 transitions + state reader), unconditional EvictLocal (D-10) & conformance kit green (BACK-03/BACK-04; SC 2)

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 02-03-PLAN.md — Crash-before-commit seam (D-07), corruption self-heal (D-09) & journal reconciliation proof (BACK-03/BACK-04; SC 3/SC 4)

### Phase 3: minio-cpp Integration & S3Client Adapter

**Goal**: S3 client capability exists behind an internal adapter — minio-cpp at the pinned upstream tag builds through the superbuild on all five platforms, and the adapter interface plus in-memory fake make S3 behavior testable hermetically
**Depends on**: Phase 1 (library repo skeleton + CommonTargets orchestration entry)
**Requirements**: BUILD-02, BUILD-03, BACK-05, BACK-06
**Success Criteria** (what must be TRUE):
  1. minio-cpp (pinned upstream tag, integrated shaderc-style — nested deps fetched/bundled inside its ExternalProject step, statically linked, non-exported, no GNUS fork of minio-cpp, no separate dep submodules) builds on all five platform builds via `CommonTargets.cmake` orchestration
  2. All library S3 traffic goes through the internal `S3Client` adapter interface (~5 ops: put/get/head/delete + config); no minio-cpp/SDK type appears in any installed public header (compile-time check)
  3. `InMemoryS3Client` fake drives hermetic tests for every adapter op including 200/404/error paths — no network, no live endpoint, no Docker
  4. `MinioS3Client` performs put/get/head/delete against a local endpoint and maps every failure to the Phase-1 status taxonomy in exactly one place — unknown failures map to Unknown/`TemporarilyUnavailable`, never `NotFound`

**Plans**: 4/4 plans complete (3 executed + 1 gap closure planned)
Plans:
**Wave 1**
- [x] 03-01-PLAN.md — minio-cpp/pugixml submodules + superbuild wiring + D-11 entrance-criterion spike (tracer: submodule → CommonTargets → build green → trio proof; BUILD-02/BUILD-03; Q1 pugixml amendment, D-12, stub + harness utilities)

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 03-02-PLAN.md — Internal S3Client interface (5 ops + config) + InMemoryS3Client fake + hermetic op tests (BACK-05/SC3; D-01..D-05)

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 03-03-PLAN.md — MinioS3Client one-place taxonomy mapping + D-08 stub fault matrix + env-gated MinIO live tier + SC2 hygiene guards (BACK-06/SC2/SC4; D-06..D-09)

**Gap-closure Wave** *(G-3-1 from 03-UAT.md; runs via /gsd-execute-phase --gaps-only)*
- [x] 03-04-PLAN.md — G-3-1: in-process TLS cert generation (OpenSSL C API, per binding USER DECISION) replacing the openssl.exe shell-out so EnvGatedTlsOnSmoke runs live on Windows + hermetic cert-gen case + explicit OpenSSL::Crypto wiring (BACK-06)

**Research note**: `--research-phase` recommended — minio-cpp v1.0.0 header-level API surface at the pinned tag (BaseUrl config, path-style, conditional-header exposure, error codes; hosted doxygen is stale), hermeticity patch shape, inih GNUS fork (CMakeLists for meson-only upstream), Windows source build, ExternalProject wiring. Entrance criteria: conditional `If-None-Match:*` sendable at the pinned tag.

### Phase 4: S3BlockStore & Sia s3d Roundtrip

**Goal**: The terminal cold-storage tier ships — `S3BlockStore` composed over the adapter with the codec-preserving key layout and conditional writes, accepted end-to-end against real MinIO (opt-in) and live Sia s3d (dev-gated), with s3d's staged-vs-durable semantics characterized
**Depends on**: Phase 2 (local tier + upload journal interplay), Phase 3
**Requirements**: BACK-07, S3D-01, S3D-02, S3D-03
**Success Criteria** (what must be TRUE):
  1. The conformance kit runs green against `S3BlockStore` (fake client, hermetic CI); blocks land under the `v1/blocks/` full-CID codec-preserving layout — observable by inspecting stored object keys
  2. `Has` maps HEAD 200/404 → true/false with every other response → `TemporarilyUnavailable`; PUTs are conditional create-only with 412 → AlreadyExists-as-success (idempotent re-put) — proven at the adapter level
  3. Opt-in MinIO-binary integration tests (env-gated local server process, no Docker-in-CI dependency) exercise the real MinioS3Client→S3BlockStore roundtrip: Put → Get → CID-verify
  4. The dev-gated live s3d E2E passes: a fresh library instance retrieves a block previously uploaded to Sia s3d and verifies its CID; the evidence artifact is committed; it never runs in CI
  5. s3d's staged-vs-durable semantics are characterized from the pinned version's admin API (`/stats/uploads`) and `openapi.yml`, with a documented finding — a per-object durability signal exists, or the accepted-is-max-provable fallback is documented

**Plans**: 1/3 plans executed (pending execution)
Plans:
**Wave 1**
- [x] 04-01-PLAN.md — Hermetic core: S3Client.hpp promotion + api_hygiene extension + S3BlockStore (v1/blocks/ layout, conditional create-only, taxonomy) + conformance/key-layout tests + UploadDrainer installed API (BACK-07/SC1+SC2 hermetic, D-01..D-04, 03 D-04; S3D-02 drainer path)

**Wave 2** *(blocked on Wave 1 — test/CMakeLists.txt + api_hygiene serialization points; opens the s3d-gated half per D-05)*
- [ ] 04-02-PLAN.md — Day-one live s3d spike (D-05..D-07 hard gate: 412 shape, HEAD absence, /stats/uploads trio) + evidence artifacts + docs/s3d-durability.md finding + Durability.hpp citation (S3D-03/SC5, D-12/D-13; human checkpoint for the live session)

**Wave 3** *(blocked on 04-01 store/drainer + 04-02 spike gate per D-07)*
- [ ] 04-03-PLAN.md — Opt-in MinIO-binary store roundtrip (S3D-01/SC3, executor-runnable) + dev-gated two-run fresh-process s3d E2E with committed evidence log (S3D-02/SC4, D-08..D-11; human checkpoint for the live session)

**Research note**: In-phase discovery task — s3d durability-signal field semantics at pinned v0.2.1 (staged-read headers, metric names); design the fallback if no per-object signal exists. Polling implementation is fast-follow, not this milestone.

### Phase 5: Fault Injection & Three-Tier Hardening

**Goal**: The library's trust claims hold under induced failure — taxonomy honesty, crash safety, and corruption rejection are proven, and the three-tier test strategy is complete with CI fully hermetic
**Depends on**: Phase 2 (upload journal), Phase 4 (S3 tier)
**Requirements**: TEST-01, TEST-02
**Success Criteria** (what must be TRUE):
  1. A loopback-stub fault matrix — connection-refused, 5xx, truncated bodies, garbage responses — surfaces each failure as the correct taxonomy class with no sticky negative caching: a subsequent good fetch succeeds
  2. Crash injection (kill between local commit and remote upload, mid-temp-write, post-upload) always recovers cleanly via journal reconciliation; byte-flipped local and remote blocks are rejected as `Corrupt` with source attribution
  3. The three-tier strategy is enforced and inspectable: Tier 1 hermetic fakes run in CI with no live endpoints and no fixed sleeps; Tier 2 MinIO-binary tests are opt-in; Tier 3 s3d tests are dev-only with committed evidence — verifiable from CI/test configuration

**Plans**: TBD

## Phase Ordering Rationale

- **Contract before backends:** the CORE-* type-system decisions (taxonomy, DurabilityLevel, eviction-safe shape) are retrofit-brutal; the conformance kit is the verification instrument every later phase instantiates
- **Pure-local backend before any network dependency:** Phase 2 proves the abstraction against real persistence and lands the crash-safety machinery (journal, atomic writes) the S3 tier reuses
- **SDK build risk quarantined:** minio-cpp — the only genuinely new external surface, and the highest build-system risk — is isolated in Phase 3 behind the adapter + fake, so Phase 4 composes instead of debugging SDK integration and store semantics simultaneously
- **Hardening last, hermetic tests from day one:** Tier-1 tests exist from Phase 1; Phase 5 adds failure modes (which depend on Phase 2's journal and Phase 4's S3 tier), not the first tests

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. BlockStore Contract, Memory Backend & Conformance Kit | 3/3 | Complete    | 2026-10-20 |
| 2. LocalBlockStore (RocksDB Cold Tier) | 3/3 | Complete    | 2026-10-20 |
| 3. minio-cpp Integration & S3Client Adapter | 4/4 | Complete    | 2026-10-21 |
| 4. S3BlockStore & Sia s3d Roundtrip | 1/3 | In Progress|  |
| 5. Fault Injection & Three-Tier Hardening | 0/TBD | Not started | - |

---
*Roadmap created: 2026-10-19 — rocksdb-backup workstream, milestone v1.0 (21/21 requirements mapped)*
