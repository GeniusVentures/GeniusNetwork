# Architecture Research: sgns-blockstore Integration

**Domain:** CID-native BlockStore cold-storage library (`sgns-blockstore`, thirdparty/ static lib) integrating with the existing SuperGenius / GeniusSDK / genius-tube ecosystem
**Researched:** 2026-10-19
**Confidence:** HIGH (all SuperGenius/thirdparty facts read directly from source; S5 patterns read from `s5-dev/s5-rs` main on 2026-10-19; MinIO SDK build integration flagged MEDIUM — not yet prototyped in-repo)

**Scope:** Vertical slice = doc Phase 1+2 only (BlockStore abstraction + MemoryBlockStore + LocalBlockStore + S3Client adapter + S3BlockStore). NO tiering, NO sharding, NO eviction. Interfaces must not preclude them. The library must build and test standalone in thirdparty/ with **zero SuperGenius headers**.

---

## System Overview

### Today: CID→bytes path inside SuperGenius (all inside one process, one RocksDB instance)

```
CrdtDatastore (SuperGenius/src/crdt/crdt_datastore.hpp)
        |  IPLD blocks via DAGSyncer; CRDT meta via plain RocksDB
        v
GraphsyncDAGSyncer (SuperGenius/src/crdt/graphsync_dagsyncer.hpp)
        |  ctor wraps shared_ptr<IpfsDatastore> into MerkleDagServiceImpl
        |  + private in-memory lru_cid_cache_ (2nd tier already exists de facto)
        v
MerkleDagServiceImpl (thirdparty/ipfs-lite-cpp .../merkledag/impl/merkledag_service_impl.hpp)
        |
        v
IpfsDatastore (pure virtual, SYNCHRONOUS: contains/set/get/remove/seal)
        ^
        | implemented by
RocksdbDatastore (thirdparty/ipfs-lite-cpp .../impl/datastore_rocksdb.hpp)
        |  key = cid.toBytes(), value = raw bytes, NO CID verification (FIL-117 TODO)
        v
ipfs_lite::rocksdb wrapper  <-- wraps the SAME rocksdb::DB handle
        v
sgns::storage::RocksDB (SuperGenius/src/storage)  <-- opened in GlobalDB::Start(),
        with backup-engine restore-on-corruption lifecycle (globaldb.cpp ~200-300)
```

Wiring point, all in `SuperGenius/src/crdt/globaldb/globaldb.cpp`:
`RocksDB::create(...)` → `m_datastore`; `IpfsRocksDb::create(m_datastore->getDB())` (**:322**); `std::make_shared<RocksdbDatastore>(...)` (**:327-329**); `std::make_shared<GraphsyncDAGSyncer>(ipfsDataStore, graphsync, host)` (**:335-336**); `CrdtDatastore::New(m_datastore, HierarchicalKey("crdt"), dagSyncer, m_broadcaster, crdtOptions)` (**:344-349**).

### Future (NOT this milestone): where sgns-blockstore slots in

```
GraphsyncDAGSyncer  (UNCHANGED — still takes shared_ptr<IpfsDatastore>)
        ^
        | new adapter, implemented INSIDE SuperGenius (not in the library)
BlockStoreBackedIpfsDatastore : public ipfs_lite::ipfs::IpfsDatastore
        ^
        |
sgns::blockstore::BlockStore  (the new library — standalone in thirdparty/)
   ├── MemoryBlockStore
   ├── LocalBlockStore        (own RocksDB instance, CID-verified)
   └── S3BlockStore ──> S3Client adapter ──> MinIO C++ SDK ──> Sia s3d / MinIO / R2 / B2
```

The library never points up at SuperGenius; SuperGenius (later) supplies the adapter. Dependency direction is enforced structurally: thirdparty builds before SuperGenius/GeniusSDK in every build tree, so a SuperGenius include from sgns-blockstore cannot even link.

---

## Q1: Exact shape of the IpfsDatastore / RocksdbDatastore boundary

### The interface (read from source)

`thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/datastore.hpp` — `sgns::ipfs_lite::ipfs::IpfsDatastore`, pure virtual, **synchronous**, Boost.Outcome-based:

| Method | Signature shape | Notes |
|---|---|---|
| `contains` | `result<bool> contains(const CID&) const` | |
| `set` | `result<void> set(const CID&, Value)` | `Value = common::Buffer` |
| `get` | `result<Value> get(const CID&) const` | error `IpfsDatastoreError::NOT_FOUND` on miss |
| `remove` | `result<void> remove(const CID&)` | |
| `seal` / `is_sealed` | `result<void>` / `result<bool>` | prune markers; seal key is `<cid-string>sealed` (string, different encoding from block keys) |
| `setCbor`/`getCbor` | templates | CBOR convenience, not needed by a block store |

There is **no** deadline, no status taxonomy (authoritative-NotFound vs transient vs corrupt), no verification, no durability semantics, no async anything. This is precisely the gap the architecture doc's `BlockStatus`/`GetBlockResult`/`ReadOptions`/`WriteOptions` close.

### The RocksDB implementation

`thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/impl/datastore_rocksdb.{hpp,cpp}`:
- Key = `cid.toBytes()` (raw CID binary); value = raw bytes (`datastore_rocksdb.cpp:17-21`, `:33-40`).
- **No CID verification on write or read** — `RocksdbDatastore::set` carries `TODO(turuslan): FIL-117 maybe check value hash matches cid` (`.cpp:36`). Strongest single piece of evidence that the new library's verify-on-put/verify-on-get hooks are additive value, not duplication.
- Two construction paths: static `create(directory, options)` (standalone DB) and `explicit RocksdbDatastore(shared_ptr<ipfs_lite::rocksdb>)` over an **existing** `rocksdb::DB` handle — GlobalDB uses the second (globaldb.cpp:322), sharing its CRDT/meta DB with the block store.

### The consumer

`SuperGenius/src/crdt/graphsync_dagsyncer.hpp:33` (`using IpfsDatastore = ipfs_lite::ipfs::IpfsDatastore`), ctor at `:117-120`, impl `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp:58-66`: the datastore is **immediately wrapped** into `ipfs_lite::ipfs::merkledag::MerkleDagServiceImpl` and never used directly again. `StartSync()` registers `graphsync_->start(dagService_, blockCallback)` (`.cpp:552-556`) — Graphsync serves incoming block requests purely through the MerkleDagService over the datastore. Additionally, `GraphsyncDAGSyncer` keeps its own in-process memory tier `lru_cid_cache_` (`InitCIDBlock`/`AddCIDBlock`/`GrabCIDBlock`/`IsCIDInCache`/`DeleteCIDBlock`, `.cpp:811-870`) for blocks received outside an explicit CRDT request — a de facto two-tier read already exists (`HasBlock` = MerkleDAG store ∪ LRU, `.cpp:511-516`; `GetNodeWithoutRequest` = MerkleDAG then LRU, `.cpp:519-529`).

This directly answers architecture-doc Open Question #9: **yes**, the Graphsync layer can already serve blocks restored from a fallback store, because it serves from whatever `IpfsDatastore` it was handed — no Graphsync/libp2p changes are required to make S3-restored blocks servable. It also answers #1: today `GraphsyncDAGSyncer` (via `MerkleDagServiceImpl` → `RocksdbDatastore`) owns CID→bytes retrieval, plus the private LRU tier.

### Can BlockStore wrap IpfsDatastore, or must LocalBlockStore be standalone?

**Standalone. Do not build LocalBlockStore on IpfsDatastore.** Reasons:

1. **DB lifecycle ownership.** The live `RocksdbDatastore` shares the GlobalDB RocksDB instance whose lifecycle includes backup-engine restore-on-corruption with a `std::abort()` path and a lock-retry loop (globaldb.cpp ~200-300). A thirdparty library must not couple its existence to that lifecycle; genius-tube (the second consumer) has no GlobalDB at all.
2. **Interface ceiling.** Wrapping `IpfsDatastore` inherits its sync-only, no-status, no-deadline, no-verification shape — making the library's own `BlockStatus`/deadline/verification features unimplementable and precluding future tiering (a decorator over IpfsDatastore can't distinguish authoritative NotFound from transport failure).
3. **Dependency weight for genius-tube.** The base `BlockStore` + `LocalBlockStore` should not drag ipfs-lite-cpp's graphsync/merkledag machinery into consumers that only want RocksDB-backed CID storage. (The CID type itself is a separate, deliberate exception — see Q2.)

The shared-instance question ("can LocalBlockStore live in the same RocksDB as the CRDT store?") is technically possible — keys are byte-identical (`cid.toBytes()`) — but is explicitly **not** the milestone's design: LocalBlockStore owns its own directory/instance from day one. Sharing an instance would re-couple lifecycles and is only interesting for a far-future eviction-aware integration (doc Phase 5 territory).

---

## Q2: Where the CID type lives; least-coupled dependency choice

Read from source, `thirdparty/ipfs-lite-cpp/primitives/cid/cid.hpp`:

- The CID type is **rooted in libp2p**: `class CID : public libp2p::multi::ContentIdentifier` (`cid.hpp:3-6`). Content = version + multicodec + multihash, all libp2p types.
- `sgns::CID` (in the **GNUS fork of ipfs-lite-cpp**, already re-namespaced to `sgns::`) adds the codecs the block store actually needs: `toString()/fromString()` (base32 CIDv1 — needed for S3 object keys), `toBytes()/fromBytes()/read()` (needed for RocksDB keys), `std::hash<CID>`, and `sgns::common::getCidOf(bytes)` (needed for verify-on-put).
- These codecs live in compiled targets exported by ipfs-lite-cpp's package: its `install(TARGETS ... EXPORT ipfs-lite-cppConfig ...)` exports **granular targets including `cid`, `outcome`, `buffer`, `blob`, `hexutil`** (`thirdparty/ipfs-lite-cpp/CMakeLists.txt:59-75`).

**Recommendation (opinionated):** depend on **ipfs-lite-cpp, but link only the granular `cid` (+ `outcome`, `buffer`) targets**, and include only `primitives/cid/cid.hpp` + `common/*` headers. Rationale:

- Re-implementing multibase/varint/multihash codecs in sgns-blockstore guarantees drift bugs in exactly the code path that verifies content integrity — the worst place for a private reimplementation.
- Every current and future consumer (SuperGenius, AsyncIOManager, genius-tube via its AsyncIOManager adapters) already builds ipfs-lite-cpp from the same thirdparty tree; the marginal dependency cost is near zero and ABI-consistent (one CID definition everywhere).
- Depending on raw libp2p `ContentIdentifier` instead would drop `toBytes/toString/getCidOf` — i.e., RocksDB keys, S3 keys, and CID verification would all need hand-rolled codecs. Not acceptable.

Coupling guardrails: sgns-blockstore must **never include** `ipfs_lite/ipfs/datastore.hpp`, `merkledag/*`, `graphsync/*` — a CI-checkable grep rule. If a future consumer wants to shed ipfs-lite-cpp entirely, the escape hatch is extracting `primitives/cid` into its own micro-package inside the fork (flagged as an open option; do not design now).

---

## Q3: How SuperGenius consumes the library later (the seam, without designing P3+)

The seam is `GraphsyncDAGSyncer`'s constructor parameter: `std::shared_ptr<IpfsDatastore>` (graphsync_dagsyncer.hpp:117-120, .cpp:58-66). Because the syncer and Graphsync only ever see `IpfsDatastore`, **the adapter direction is: implement `IpfsDatastore` over `BlockStore`, inside SuperGenius**:

- New file in SuperGenius (suggested `SuperGenius/src/crdt/globaldb/blockstore_ipfs_datastore.{hpp,cpp}` or a `src/crdt/blockstore_adapter/` module): `class BlockStoreBackedIpfsDatastore : public ipfs_lite::ipfs::IpfsDatastore` forwarding `get/set/contains/remove` to an injected `sgns::blockstore::BlockStore`. The adapter belongs in SuperGenius (not in the library) because it references ipfs-lite-cpp API types beyond CID — keeping the library's ipfs-lite surface CID-only (Q2 guardrail).
- Wiring point: `GlobalDB::Start()`, globaldb.cpp:322-344. Two future modes, both single-file-sized changes:
  1. **Read-path mode:** construct `BlockStoreBackedIpfsDatastore` (LocalBlockStore, optionally with S3 read-through later) and pass it where `ipfsDataStore` goes today. Zero changes to GraphsyncDAGSyncer, CrdtDatastore, or ipfs-lite-cpp.
  2. **Mirror mode (lowest risk first step):** keep today's `RocksdbDatastore` untouched and mirror writes into the new library (e.g., from `BlockReceivedCallback`/`addNode` paths) purely for durable archival, out of the read path.
- `seal`/`is_sealed` in the adapter: map to no-ops or a sidecar column initially — these are ipfs-lite prune markers, not block-store concepts; the library should NOT put them in the core `BlockStore` interface (keeps the boundary clean for genius-tube).
- GeniusSDK needs nothing: it wraps SuperGenius, and inherits the behavior once SuperGenius wires it. No SDK C-API change is implied by this milestone.

**Not precluding tiering/sharding:** because SuperGenius consumes via an `IpfsDatastore` adapter over the *composition root* `BlockStore`, whatever the library composes behind that handle later (TieredBlockStore decorator, PeerBlockStore racing S3, sharded routing) is invisible to SuperGenius. That is the entire reason the adapter-over-composition-root seam is the right one.

---

## Q4: How a new thirdparty submodule slots into orchestration and is consumed

The mechanism, verified end-to-end in the repo:

1. **Submodule:** add `thirdparty/sgns-blockstore` with a relative URL like the other GNUS-owned repos — `thirdparty/.gitmodules:96-98` shows the precedent: `[submodule "AsyncIOManager"] path = AsyncIOManager url = ../AsyncIOManager.git`. MinIO C++ SDK gets its own submodule the same way (or is vendored — flagged below).
2. **Orchestration:** `thirdparty/build/CommonTargets.cmake` declares each lib as an `ExternalProject_Add(<name> SOURCE_DIR "${THIRDPARTY_DIR}/<name>" CMAKE_CACHE_ARGS -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR> -D<Dep>_DIR:PATH=${_FINDPACKAGE_<DEP>_CONFIG_DIR} ... DEPENDS <deps>)`. Precedents read in full: rocksdb (`:140-173`), ipfs-lite-cpp with its full dependency fan-in and `DEPENDS ... libp2p rocksdb ...` (`:497-532`), AsyncIOManager — the closest template, a GNUS-owned consumer-facing lib (`:741-776`). Each block exports `_FINDPACKAGE_<NAME>_CONFIG_DIR/LIBRARY_DIR/INCLUDE_DIR` variables.
   - `sgns-blockstore` entry: `DEPENDS rocksdb ipfs-lite-cpp` (+ `minio-cpp` once Phase C lands), `-DRocksDB_DIR`, `-Dipfs-lite-cpp_DIR`, plus the standard `${_CMAKE_COMMON_CACHE_ARGS}`, `${_BOOST_CACHE_ARGS}`, `${_OPENSSL_CACHE_ARGS}` so cross-compilation flags flow like every other lib.
3. **Consumption:** downstream builds set `<name>_DIR` at the install tree and `find_package(<name> CONFIG REQUIRED)`. Precedents: `GeniusSDK/cmake/CommonBuildParameters.cmake:247-252` (ipfs-lite-cpp), `:314-316` (AsyncIOManager — the exact three-line template for sgns-blockstore), `:142-143` (RocksDB). SuperGenius links such libs by imported target name directly (`SuperGenius/src/CMakeLists.txt:10` links `AsyncIOManager`).
4. **The library's own CMakeLists** should mirror `thirdparty/AsyncIOManager/CMakeLists.txt`: `cmake_minimum_required(3.20)`, default cxx17 toolchain, `include(GNUInstallDirs)`, `find_package(... CONFIG REQUIRED)` per dependency, `option(BUILD_TESTING)` gating GTest, and an `install(TARGETS ... EXPORT ...)` + config packaging so `find_package(sgns-blockstore CONFIG)` works.
5. **Dependency direction is structural:** thirdparty is built first; SuperGenius and GeniusSDK configure against the install tree (`THIRDPARTY_BUILD_DIR`). A SuperGenius header included from sgns-blockstore fails at generate time — the "no SuperGenius headers" boundary is enforced by the build system, not convention.

**MinIO SDK decision (flagged MEDIUM confidence, resolve in phase planning):** minio-cpp has its own dependency set (libcurl, openssl, pugixml, etc.). Two viable paths: (a) thirdparty submodule + its own `ExternalProject_Add` — fits the 48-lib repo convention, cache/patch/cross-compile friendly, **recommended**; (b) `FetchContent` inside sgns-blockstore — hides deps from orchestration, harder to patch on Windows/Android cross builds. Verify minio-cpp's CMake package + cross-platform behavior in an early plan task before committing.

---

## Q5: Suggested build order (for the roadmapper to map phases onto)

Vertical slice = doc Phase 1+2. Ordering rationale: the conformance kit must exist before the first real backend so every backend is born under test; the thirdparty orchestration entry must exist before the first external dependency; S3Client adapter precedes S3BlockStore by construction.

| # | Phase candidate | Contents | Why this position |
|---|---|---|---|
| 1 | **Library skeleton + MemoryBlockStore** | submodule + repo bootstrap (AsyncIOManager-style CMakeLists, install/export config), `Block`/`BlockStatus`/`GetBlockResult`/`ReadOptions`/`WriteOptions`/`BlockStore` types, CID dependency (link `cid`+`outcome` targets), **shared conformance test kit**, `MemoryBlockStore`, verify-on-put/get hooks (borrowed `getCidOf`), CommonTargets.cmake `ExternalProject_Add(sgns-blockstore ... DEPENDS ipfs-lite-cpp)` + `.gitmodules` entry from day one | Types + conformance kit are the verification instrument for everything after; orchestration entry early keeps CI honest from the first commit |
| 2 | **LocalBlockStore (RocksDB)** | own RocksDB instance/directory, key = `cid.toBytes()` (byte-compatible with `RocksdbDatastore` — future migration aid), atomic put path, corruption-injection tests, conformance suite green; extend CommonTargets `DEPENDS rocksdb` | Pure-local: no network, no MinIO; proves the abstraction against a real persistent backend |
| 3 | **S3Client adapter (MinIO SDK)** | internal `S3Client` interface (PutObject/GetObject/HeadObject/DeleteObject per the architecture doc), MinIO C++ SDK impl behind it, minio-cpp thirdparty submodule + `ExternalProject_Add`, in-memory fake `S3Client` for hermetic tests | Adapter + fake client decouple Phase 4 from a live service; SDK build integration risk (MEDIUM) is isolated here |
| 4 | **S3BlockStore** | CID→object-key layout `v1/blocks/<multicodec>/<prefix>/<cid>`, idempotent/conditional PUT, HeadObject-backed `Has`, deadlines/retries/structured errors, verify-on-get, integration tests vs local MinIO server and Sia `s3d` | Composed over Phase 3's adapter; the slice's terminal deliverable |
| 5 | *(future milestone, out of scope)* SuperGenius seam | `BlockStoreBackedIpfsDatastore` adapter + globaldb.cpp:322-344 wiring (mirror mode first), CommonBuildParameters.cmake entry + `find_package(sgns-blockstore CONFIG REQUIRED)` in SuperGenius/GeniusSDK builds | Needs the library shipped first; adapter lives in SuperGenius |

Note on CommonBuildParameters.cmake: do **not** add the sgns-blockstore block in this milestone — it is dead config until a consumer exists; it lands with Phase 5. CommonTargets.cmake, by contrast, is required from Phase 1 (that *is* the build entry for the library).

genius-tube consumes the finished library the same way it consumes AsyncIOManager today: its own build points `sgns-blockstore_DIR` at the thirdparty install tree. Nothing in the library may assume a SuperGenius-shaped host.

---

## Q6: S5 (s5-dev/s5-rs) patterns worth borrowing

Read from `s5-dev/s5-rs` @ main, 2026-10-19. S5 splits a low-level path-keyed `Store` trait (`s5_core/src/store.rs`: `put_stream/put_bytes/open_read_stream/open_read_bytes/exists/size/list/delete/rename/sync`) from a content-addressed `BlobStore` facade (`s5_core/src/blob/store.rs`) that derives deterministic paths from hashes and **owns hash verification**. Borrow the patterns, not the stack (no BLAKE3/Bao, no Iroh/QUIC, no path-keyed primary store — sgns-blockstore is CID-native from the start).

| S5 pattern | Evidence | Borrow for sgns-blockstore |
|---|---|---|
| **Capability feature struct** — `StoreFeatures { supports_rename, case_sensitive, recommended_max_dir_size, supports_reflink }`; every backend declares, e.g. S3: `supports_rename: false` (`store.rs:150-187`; `blob_stores/s3/src/lib.rs:85-92`; Sia: `blob_stores/sia/src/store.rs:280-288`) | backend-declared capabilities adapt higher layers without API proliferation | Add a `BlockStoreCapabilities` (e.g. `cheap_has`, `deletes_are_tombstones`, `eventual_consistency`, `max_object_size`) reported by each backend. This is where Sia `s3d` staging semantics (accepted-vs-durable) get expressed *later* without touching the core interface |
| **Decorator composition** — `CachingStore : Store` wraps any `Store` (`s5_core/src/caching.rs`); `IndexdStore<C: Store>` is a generic wrapper; packing staging is itself a `Store` (`docs/reference/packing-store.md`) | tiering = decorators, core trait knows nothing about tiers | `TieredBlockStore` (future P3) must be *just another `BlockStore` implementation* composing others. Design `BlockStore` now so a decorator can map per-backend statuses upward — this is the concrete mechanism by which the milestone "must not preclude tiering/sharding" |
| **Conformance test kit** — `s5_core::testutil::StoreTests` runs a standard suite (put/get bytes+streams, exists, size) against *any* `Store` impl (`testutil.rs:0-143`) | one suite, all backends, incl. test fakes | Build `BlockStoreConformanceTests` as a reusable target linked against MemoryBlockStore (P1), LocalBlockStore (P2), S3BlockStore-with-fake-client (P4). New backends inherit the suite for free |
| **Verification in the facade, not per-backend** — `BlobStore` "Handles `BlobId` verification (hash checking)" (`s5_core/README.md`) | verify once, uniformly | CID verification (getCidOf compare) belongs in the library's core put/get path (and as a decorating hook), so Memory/Local/S3 all get it without each backend re-implementing it |
| **Location metadata — the cautionary tale** — `provide() -> Vec<BlobLocation>` with backend-specific variants (`SiaFile/SiaFileSlab`) is explicitly marked **vestigial, TODO(breaking)**: "Location sharing belongs in a higher layer" (`store.rs:49-59`) | provider-specific location types leak into every backend | Keep `GetBlockResult` backend-agnostic (status + block + diagnostic). Structured location/durability metadata, when needed (P5), goes in a **separate optional interface**, never in Get/Put results |
| **Atomic write + durability hooks** — default `put_temp` writes `.tmp/<uuid>` then renames (`store.rs:62-73`); `sync()` default no-op flush hook (`store.rs:95-98`) | cheap defaults, backends upgrade | LocalBlockStore: temp-write + atomic commit from day one. Reserve a `Sync/Flush` hook in `WriteOptions`/options struct so future `DurabilityLevel` lands without interface breakage |
| **Capability-split views** — `BlobsRead/BlobsWrite/BlobsDelete/BlobsList` + registry handing out read-only views (`s5_node/src/store_registry.rs:55-89`) | read-only code gets read-only handles | Optional: a read-only base interface (`BlockReader`?) so SuperGenius's future adapter can expose a const read path. Keep it minimal — don't over-engineer for the slice |
| **Substrate for by-reference migration** — `migration_substrate() -> Option<Substrate>` marks stores sharing a physical medium so migration skips byte copying (`store.rs:116-123, 150+`) | future S3↔S3 tier moves | Note only; explicitly out of scope, but another reason capabilities/metadata live beside, not inside, the core interface |
| **HEAD→exists mapping** — SiaStore `exists` = HEAD, 200→true/404→false, other→error (`blob_stores/sia/src/store.rs:289-309`) | transport status ≠ boolean | `S3BlockStore::Has` must map HeadObject 200/404 → true/false and everything else → `TemporarilyUnavailable`, never to a false "NotFound" (mirrors the architecture doc's read-path rules) |

---

## Recommended Project Structure (the library)

```
thirdparty/sgns-blockstore/
├── CMakeLists.txt              # AsyncIOManager-style: cxx17, GNUInstallDirs, find_package CONFIG,
│                               #   install(TARGETS ... EXPORT sgns-blockstoreConfig)
├── cmake/                      # functions/toolchain mirroring repo conventions
├── include/sgns-blockstore/    # public headers (installed)
│   ├── Block.hpp               # { CID cid; bytes }
│   ├── BlockStatus.hpp         # Found/NotFound/TemporarilyUnavailable/Corrupt/Unauthorized
│   ├── BlockResult.hpp         # GetBlockResult / PutResult / DeleteResult
│   ├── Options.hpp             # ReadOptions / WriteOptions (deadline, verify, sync hints)
│   ├── BlockStore.hpp          # the pure virtual interface — the only thing backends implement
│   ├── Capabilities.hpp        # BlockStoreCapabilities (S5 StoreFeatures analog)
│   ├── MemoryBlockStore.hpp
│   ├── LocalBlockStore.hpp
│   └── S3BlockStore.hpp
├── src/                        # impls (.cpp) + internal/
│   └── internal/S3Client.hpp   # adapter interface; MinIO types NEVER leave this dir
├── test/
│   ├── conformance/            # the reusable BlockStoreConformanceTests target
│   ├── memory/ local/ s3/      # backend-specific + corruption/deadline tests
│   └── fakes/                  # InMemoryS3Client
└── example/                    # minimal standalone vertical-slice demo (put→get→verify→S3)
```

Structure rationale: `include/` vs `src/internal/` separation enforces that MinIO SDK types cannot leak into the public API (architecture doc's explicit requirement); `test/conformance` as its own target makes the S5-style suite reusable per backend; no `ipfs_lite/ipfs/*` includes anywhere except `primitives/cid` + `common` (Q2 guardrail, CI-grep-able).

### Component Responsibilities

| Component | Responsibility | New/Modified | Evidence-anchor |
|---|---|---|---|
| `sgns-blockstore` lib (all classes above) | CID-native block storage, verification, statuses | **NEW** (this milestone) | this doc Q1/Q2/Q6 |
| `thirdparty/minio-cpp` submodule | MinIO C++ SDK build | **NEW** (P3) | Q4 decision (a) |
| `thirdparty/build/CommonTargets.cmake` | `ExternalProject_Add` for sgns-blockstore (+ minio-cpp) | **MODIFIED** (P1 / P3) | `:741-776` AsyncIOManager precedent |
| `thirdparty/.gitmodules` | 2 new submodule entries | **MODIFIED** (P1/P3) | `:96-98` precedent |
| `GlobalDB::Start()` (globaldb.cpp:322-344) | future wiring point only | **UNCHANGED this milestone**; modified in future seam phase | Q3 |
| `BlockStoreBackedIpfsDatastore` | future `IpfsDatastore`-over-`BlockStore` adapter | **NEW, future milestone, lives in SuperGenius** | Q3 |
| `GeniusSDK/cmake/CommonBuildParameters.cmake` | future `sgns-blockstore_DIR` + find_package | **UNCHANGED this milestone** | `:314-316` pattern |
| `graphsync_dagsyncer.{hpp,cpp}`, `crdt_datastore.*`, ipfs-lite-cpp `datastore*` | — | **UNCHANGED, ever** (the entire point of the seam) | Q1/Q3 |

---

## Data Flow

### This milestone (standalone library, no SuperGenius involvement)

```
library test / example / (future) genius-tube
    → BlockStore::Put(cid, bytes, WriteOptions{verify=true})
        → verify bytes hash to cid (getCidOf)          [library core]
        → LocalBlockStore: atomic temp-write → commit  (own RocksDB dir)
        → S3BlockStore: PutObject(v1/blocks/<mc>/<prefix>/<cid>) via S3Client adapter
    → BlockStore::Get(cid, ReadOptions{deadline, verify=true})
        → LocalBlockStore hit → verify → Found
        → miss → S3BlockStore GetObject → verify → Found (→ optional local backfill later, P3)
        → transport failure → TemporarilyUnavailable (NEVER cached as NotFound)
        → hash mismatch → Corrupt + diagnostic attribution
```

### Future read path through SuperGenius (Phase 5 seam, for context only)

```
CrdtDatastore → GraphsyncDAGSyncer.getNode / graphsync responder
    → MerkleDagServiceImpl → BlockStoreBackedIpfsDatastore (adapter, in SuperGenius)
    → sgns::blockstore composition root (LocalBlockStore → [P3: TieredBlockStore → S3/Peer])
    → bytes verified against CID before they ever reach Graphsync
Existing path (RocksdbDatastore) remains valid; mirror mode adopts with zero read-path risk.
```

---

## Architectural Patterns

### Pattern 1: Composition-root decorator (S5 CachingStore analog)
**What:** backends implement only `BlockStore`; tiering/racing/caching are decorators implementing the same interface over N inner stores.
**When:** now (design the interface for it), P3 (implement TieredBlockStore).
**Trade-offs:** uniform status-mapping discipline required at each decorator; in exchange, SuperGenius's adapter never changes when composition changes.

### Pattern 2: Adapter-buried SDK (S3Client)
**What:** MinIO SDK types confined to `src/internal/`; public API speaks only CID/bytes/strings.
**When:** P3–P4.
**Trade-offs:** one thin translation layer to maintain; buys the architecture doc's "change S3 client without touching the cache" guarantee.

### Pattern 3: Sync-first interface with internal async
**What:** `BlockStore` is synchronous, outcome-based — matching `IpfsDatastore`'s sync shape so the future SuperGenius adapter is trivial (graphsync/merkledag call the datastore synchronously today). The S3Client adapter runs its own executor (Boost.Asio io_context / thread pool) with deadline-bounded waits internally.
**When:** P1 interface definition.
**Trade-offs:** a streaming/range-read variant later wants a separate optional interface (S5's `open_read_stream(offset, max_len)` shape); `ReadOptions` should be an extensible struct now so that lands non-breakingly.

---

## Scaling Considerations

| Concern | Slice (P1–P4) | Later (P3+/P5, do not build now) |
|---|---|---|
| Block count in LocalBlockStore | single RocksDB column, CID-bytes keys — fine to millions | watermark/LRU eviction (doc's cache policy) |
| S3 object count / s3d SQLite metadata | measure PUT/GET/HEAD + object counts in P4 benchmarks | CARv2 packing only if measurements justify (doc's "measure first") |
| Listing/enumeration | not needed by Get/Has/Put | prefix fan-out already in key layout `v1/blocks/<mc>/<prefix>/` |
| Concurrent same-CID fetches | single-flight in library core (cheap, in-scope for correctness tests) | full staggered-race policy is P3 |

Scaling priorities: (1) first bottleneck will be small-object request overhead on S3 — that's why P4 must benchmark, not optimize; (2) second is local cache bounding — explicitly deferred with the eviction guardrail.

---

## Anti-Patterns

### Anti-Pattern 1: Building LocalBlockStore over IpfsDatastore
**What people do:** wrap the existing `RocksdbDatastore` to "reuse" code.
**Why it's wrong:** inherits no-verification/sync-only/no-status limits; couples thirdparty lib to GlobalDB's DB lifecycle (backup/restore/abort); drags ipfs-lite graphsync machinery into genius-tube.
**Do this instead:** standalone own-RocksDB `LocalBlockStore`; the adapter direction is SuperGenius-implements-`IpfsDatastore`-over-`BlockStore` (Q3).

### Anti-Pattern 2: MinIO types in the public header
**What people do:** `#include <minio/minio.h>` in `S3BlockStore.hpp`.
**Why it's wrong:** the architecture doc's pluggable-backend guarantee dies; every consumer's build needs MinIO headers.
**Do this instead:** `src/internal/S3Client.hpp` interface; public headers mention only CID/bytes/strings.

### Anti-Pattern 3: Provider-specific location/durability types in Get/Put results
**What people do:** S5 did — `BlobLocation` with `SiaFile/SiaFileSlab` variants in the core trait; now marked vestigial with a breaking-removal TODO.
**Why it's wrong:** every new backend must stub irrelevant types; wire format leaks.
**Do this instead:** status + diagnostic string now; separate optional capabilities/metadata interface later.

### Anti-Pattern 4: Transport failure masquerading as NotFound
**What people do:** catch S3 exceptions → return "not found".
**Why it's wrong:** violates the doc's read-path rules; negative-caching a transient outage poisons the cache (and later, CRDT convergence).
**Do this instead:** `BlockStatus::TemporarilyUnavailable` vs `NotFound` from day one; conformance suite includes failure-injection cases.

### Anti-Pattern 5: Adding tier/shard/eviction parameters to the core interface now
**What people do:** design for the future by widening `Get(cid, tier_hint, shard_ctx, ...)`.
**Why it's wrong:** speculative complexity; the decorator pattern (Q6) is how those arrive later without breaking backends.
**Do this instead:** small CID-centric interface + capabilities struct + extensible options structs.

### Anti-Pattern 6: Sharing the CRDT RocksDB instance for LocalBlockStore
**What people do:** open `ipfs_lite::rocksdb` over GlobalDB's handle since keys are byte-compatible.
**Why it's wrong:** re-couples lifecycles; backup/restore of the CRDT DB would imply block-store semantics it doesn't have; eviction (P5) becomes impossible to reason about.
**Do this instead:** own directory/instance; byte-compatible key encoding is retained merely as a future migration convenience.

---

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---|---|---|
| Sia `s3d` | via S3BlockStore → S3Client adapter (MinIO SDK), path-style endpoint | accepted ≠ durable (staging) — express via capabilities later (P5); benchmarks in P4 |
| MinIO server (local) | same S3Client path | primary test target for CI integration tests |
| Other S3 (R2/B2) | runtime config only, no code paths | guarantees come from the adapter, not per-provider classes |

### Internal Boundaries

| Boundary | Communication | Notes |
|---|---|---|
| sgns-blockstore ↔ ipfs-lite-cpp | link `cid`+`outcome` targets only; include `primitives/cid` + `common` headers only | CI-grep guardrail; escape hatch = cid micro-package extraction (open option) |
| sgns-blockstore ↔ SuperGenius | **none this milestone**; future: SuperGenius-side `IpfsDatastore` adapter at globaldb.cpp:322-344 | dependency direction enforced by build order |
| sgns-blockstore ↔ genius-tube | find_package(sgns-blockstore CONFIG) against thirdparty install tree | same as AsyncIOManager consumption today |
| sgns-blockstore ↔ RocksDB / MinIO SDK | ExternalProject via CommonTargets.cmake | AsyncIOManager precedent `:741-776` |

---

## Sources

**Read directly from the workspace (HIGH confidence):**
- `SuperGenius/src/crdt/globaldb/globaldb.cpp` (:62-63 aliases, :200-300 backup/restore lifecycle, :322 IpfsRocksDb::create, :327-329 RocksdbDatastore, :335-336 GraphsyncDAGSyncer, :344-349 CrdtDatastore::New)
- `SuperGenius/src/crdt/graphsync_dagsyncer.hpp` (:33 IpfsDatastore alias, :117-120 ctor) and `impl/graphsync_dagsyncer.cpp` (:58-66 MerkleDagServiceImpl wrap, :511-529 HasBlock/GetNodeWithoutRequest, :552-556 graphsync start, :606-664 BlockReceivedCallback, :811-870 LRU cid cache)
- `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/datastore.hpp` (interface), `impl/datastore_rocksdb.{hpp,cpp}` (key encoding, FIL-117 no-verification TODO), `ipfs_lite/ipfs/merkledag/impl/merkledag_service_impl.hpp` (ctor over IpfsDatastore)
- `thirdparty/ipfs-lite-cpp/primitives/cid/cid.hpp` (CID = libp2p ContentIdentifier subclass); `thirdparty/ipfs-lite-cpp/CMakeLists.txt:59-75` (granular exported targets incl. `cid`)
- `thirdparty/build/CommonTargets.cmake` (:140-173 rocksdb, :497-532 ipfs-lite-cpp, :741-776 AsyncIOManager)
- `GeniusSDK/cmake/CommonBuildParameters.cmake` (:142-143 RocksDB, :247-252 ipfs-lite-cpp, :314-316 AsyncIOManager)
- `thirdparty/.gitmodules:96-98`; `thirdparty/AsyncIOManager/CMakeLists.txt`; `SuperGenius/src/CMakeLists.txt:10`
- `supergenius-sharded-ipld-cache-architecture.md` (authoritative doc — interfaces, phases, open questions #1/#9)

**Read from GitHub (s5-dev/s5-rs @ main, 2026-10-19; MEDIUM-HIGH confidence):**
- `s5_core/src/store.rs` (Store trait, StoreFeatures, Substrate, put_temp/sync defaults, provide deprecation TODO)
- `s5_core/src/caching.rs` (CachingStore decorator), `s5_core/src/blob/store.rs` + `blob/read.rs` + `s5_core/README.md` (BlobStore facade, verification placement)
- `s5_node/src/store_registry.rs` (capability views), `s5_core/src/testutil.rs` (conformance kit)
- `blob_stores/{s3,sia,local,memory,lib.rs}` (features per backend, HEAD→exists mapping)

**Not yet verified in-repo (MEDIUM — resolve in phase planning):** minio-cpp CMake packaging quality and cross-platform (Windows/Android) build behavior; Sia `s3d` local test harness availability for CI.

---

*Architecture research for: sgns-blockstore cold-storage library integration*
*Researched: 2026-10-19*
