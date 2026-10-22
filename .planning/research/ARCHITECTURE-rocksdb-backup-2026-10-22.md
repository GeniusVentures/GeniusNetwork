# Architecture Research: SuperGenius ↔ sgns-blockstore Integration (v1.1)

**Domain:** Runtime integration of the shipped `sgns-blockstore` v1.0 cold-storage library into the SuperGenius node (rocksdb-backup workstream, milestone v1.1)
**Researched:** 2026-10-22
**Confidence:** HIGH — every SuperGenius/thirdparty/sgns-blockstore fact below was read directly from this tree on 2026-10-22; all file:line citations verified this session. s3d durability facts trace to `thirdparty/sgns-blockstore/docs/s3d-durability.md` (committed evidence, HIGH).

**Scope:** Config-gated (crdt_config.json `s3d` fields, blank = disabled) integration of: spill-on-write for every CRDT block, read fallback (graphsync serving + local reads), UploadDrainer lifecycle inside the node, and GC of cold-eligible CRDT data past retention preserving retrievability. Builds on v1.0 research (`.planning/research/ARCHITECTURE-rocksdb-backup-2026-10-19.md`) which established the library, the seam direction, and the standalone build.

---

## Executive Summary — One Blocking Finding, One Seam, Three Compositions

1. **BLOCKER (must land first, in sgns-blockstore v1.1):** every CRDT DAG-node CID is `CIDv1 / DAG_CBOR / blake2b-256` (`thirdparty/ipfs-lite-cpp/primitives/cid/cid.cpp:129-135`, `sgns::common::getCidOf`), but the shipped BlockStore API **throws `std::invalid_argument` for any non-sha256 multihash** (`thirdparty/sgns-blockstore/include/sgns-blockstore/Cid.hpp:50-56`, D-08 note in `BlockStore.hpp:47-56`). Spilling "every CRDT block" is impossible until the hash gate is widened to blake2b-256 (additive per the header's own note). The S3 key layout's codec token must also learn `dag-cbor` (`S3BlockStore.hpp:22-38` — currently displays only `raw`/`dag-pb`).
2. **The seam is unchanged from v1.0 research and verified still exact:** all CRDT block bytes flow through ONE object — the `ipfs_lite::ipfs::IpfsDatastore` constructed at `SuperGenius/src/crdt/globaldb/globaldb.cpp:329` — for both writes (`MerkleDagServiceImpl::addNode` → `set`, `merkledag_service_impl.cpp:17-21`) and all serving/local reads (`GraphsyncImpl::onRemoteRequest` → `service->getNode` at `graphsync_impl.cpp:374`; `GraphsyncDAGSyncer::GetNodeFromMerkleDAG` at `graphsync_dagsyncer.cpp:1006`). One decorator (`BlockStoreBackedIpfsDatastore`) at that single construction site delivers spill-on-write AND read-fallback with zero changes to `GraphsyncDAGSyncer`, `CrdtDatastore`, or ipfs-lite-cpp.
3. **Spill must be journal-then-drain, never inline-S3:** `IpfsDatastore::set` executes on the CRDT DAG worker thread under `GraphsyncDAGSyncer::dagMutex_` (`graphsync_dagsyncer.cpp:189-191`) — the same mutex `GetNodeFromMerkleDAG` takes for reads (`:1007`). A blocking S3 PUT inside `set` stalls all block adds and all local/serving reads. `LocalBlockStore::Put` (local RocksDB WAL commit, fast) inline + `UploadDrainer` on a dedicated thread is the only safe shape — and is exactly what the v1.0 journal was designed for.
4. **UploadDrainer lifecycle pattern already exists in this file:** mirror `GlobalDB::StartBackupLoop/StopBackupLoop` (`globaldb.cpp:429-467` / `:469-477`) — dedicated `std::thread` + condition-variable wait, joined first in `ShutdownNow` (`:124`). Never run the drainer on `io_` or on the pubsub host's asio context (that context serves graphsync; `graphsync_dagsyncer.cpp:544-548` documents why it must not be blocked).
5. **GC = local eviction, never deletion.** The CRDT RocksDB contains five keyspaces: raw CID→bytes blocks (via `cid.toBytes()`), `/crdt/s` elements, `/crdt/t` tombstones, `/crdt/k/<key>/v|/p` current values, `/crdt/h/<topic>/<cid>` heads. GC touches ONLY the block-bytes keyspace, only for CIDs proven (a) durably uploaded, (b) not reachable from current heads, (c) past retention. Mapping: local removal = `IpfsDatastore::remove` on the CRDT store + `LocalBlockStore::EvictLocal`; CRDT-layer `DeleteKey` (tombstone delta, `crdt_datastore.cpp:1438-1454`) is a replicated logical delete and is NEVER the GC mechanism. Tombstones and `/crdt/k`, `/crdt/h` metadata are never age-purged.

---

## Standard Architecture

### System Overview — the CRDT block write path today (question a)

Verified end-to-end this session:

```
GeniusNode (SuperGenius/src/account/GeniusNode.cpp)
  │  GlobalDB::Put(key, value, topics)                    globaldb.cpp:502-511
  ▼
CrdtDatastore::PutKey → Publish(delta, topics)            crdt_datastore.cpp:1456-1461
  │  CreateDAGNode (delta → IPLD node, heads as links)    crdt_datastore.cpp:1475-1533
  │  AddDAGNode → selfCreatedJobList_ queue               crdt_datastore.cpp:1586-1610
  ▼
DAG worker thread (std::async, numberOfDagWorkers = 1)    crdt_datastore.cpp:86-120
  │  ProcessJobIteration → dagSyncer_->addNode(node)      crdt_datastore.cpp:1029
  ▼
GraphsyncDAGSyncer::addNode                                graphsync_dagsyncer.cpp:187-202
  │  lock_guard dagMutex_ (:189); dagService_->addNode (:191)
  ▼
MerkleDagServiceImpl::addNode                              merkledag_service_impl.cpp:17-21
  │  block_service_->set(node->getCID(), raw_bytes)       ← EVERY persisted block passes here
  ▼
RocksdbDatastore::set (no CID verification, FIL-117)       datastore_rocksdb (v1.0 research .cpp:36)
  ▼
ipfs_lite::rocksdb → sgns::storage::RocksDB (the ONE CRDT DB, globaldb.cpp:196-318)
```

Construction of the whole chain is in `GlobalDB::Init` (`SuperGenius/src/crdt/globaldb/globaldb.cpp`):

| Line | Statement |
|---|---|
| :318 | `m_datastore = std::move(dataStore)` — the shared RocksDB handle (opened at :196-317 with backup-engine restore-on-corruption + lock-retry loop) |
| :322 | `IpfsRocksDb::create( m_datastore->getDB() )` |
| :329 | `auto ipfsDataStore = std::make_shared<RocksdbDatastore>( ipfsDBResult.value() )` ← **THE seam** |
| :339-343 | `GraphsyncImpl(host, scheduler, graphsyncnetwork, generator, m_pubsub->GetAsioContext())` — responder runs on the pubsub host's asio context |
| :344 | `GraphsyncDAGSyncer(ipfsDataStore, graphsync, host)` — ctor immediately wraps datastore into `MerkleDagServiceImpl` (`graphsync_dagsyncer.cpp:58-66`) |
| :347-350 | `dagSyncer->StartSync()` — registers responder (`graphsync_->start(dagService_, blockCallback)`, `graphsync_dagsyncer.cpp:550`) |
| :354 | `PubSubBroadcasterExt::New(dagSyncer, m_pubsub)` |
| :360-365 | `CrdtDatastore::New(m_datastore, HierarchicalKey("crdt"), dagSyncer, m_broadcaster, crdtOptions)` |

**Where the spill-on-write hook belongs:** inside a decorator implementing `ipfs_lite::ipfs::IpfsDatastore` (`thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/datastore.hpp:26-70` — `contains/set/get/remove/seal/is_sealed`), constructed at `globaldb.cpp:329` wrapping the existing `RocksdbDatastore`, and passed unchanged to `GraphsyncDAGSyncer` at `:344`. Two candidate choke points exist — `GraphsyncDAGSyncer::addNode` (`:187`) and the `IpfsDatastore::set` call — but they are the *same stream* (addNode's only persistence act is `dagService_->addNode` → `set`, `:191` / `merkledag_service_impl.cpp:17-21`), including externally-fetched blocks, which are persisted only when the CRDT worker processes them via `dagSyncer_->addNode` (`crdt_datastore.cpp:1029`; `BlockReceivedCallback` itself only populates the in-memory LRU, `graphsync_dagsyncer.cpp:606-664`, `:819-838`). The datastore decorator is the right hook because it also captures the read-fallback surface in the same object with one wiring change.

**Async-safety of the hook:** `set` runs on the CRDT DAG worker (`std::async`, `crdt_datastore.cpp:86-90`, single worker by default) while holding `GraphsyncDAGSyncer::dagMutex_` (`graphsync_dagsyncer.cpp:189`); `GetNodeFromMerkleDAG` takes the same mutex for every local read and serving lookup (`:1007`). Therefore: `set` may do a *local-synchronous* journal write (`LocalBlockStore::Put` = one sync RocksDB WriteBatch, `LocalBlockStore.hpp:96-108` — "committed locally… in ONE atomic WriteBatch") but MUST NOT do network I/O. S3 upload is exclusively the background drainer's job. This also gives a benign single-writer discipline for the pending-upload journal (all `set` calls serialize under `dagMutex_`).

### System Overview — the block read/serve path today (question b)

Two consumers read through the same datastore:

```
SERVING (graphsync responder):
  remote peer request
    → GraphsyncImpl::onRemoteRequest                    graphsync_impl.cpp:286
      posts onto io_context (:312), locks service_ (:326)
      → service->getNode(request.root_cid)              graphsync_impl.cpp:374
    → MerkleDagServiceImpl::getNode                     merkledag_service_impl.cpp:28-31
    → block_service_->get(cid)                          ← the decorator's get()

LOCAL READS (CRDT fetch/processing, graphsync client):
  GraphsyncDAGSyncer::getNode                           graphsync_dagsyncer.cpp:206-353
    1. GrabCIDBlock (in-memory LRU, ≤250)               :842-859
    2. GetNodeFromMerkleDAG (locks dagMutex_)           :1006-1010
       → dagService_->getNode → block_service_->get     ← the decorator's get()
    3. route peers → RequestNode (network fetch)        :122-168
  HasBlock = store ∪ LRU                                :511-516
  GetNodeWithoutRequest = store then LRU                :519-529
```

`GraphsyncDAGSyncer::StartSync` hands `dagService_` (over the datastore) to graphsync as the responder's block source (`graphsync_->start(dagService_, blockCallback)`, `graphsync_dagsyncer.cpp:550`), so **serving automatically follows whatever `IpfsDatastore` it was handed** — v1.0 research's answer to architecture-doc Open Question #9 holds and is re-verified: no Graphsync/libp2p change is needed for S3-restored blocks to be servable.

**Least-disruptive wrapper (read fallback):** `BlockStoreBackedIpfsDatastore : public ipfs_lite::ipfs::IpfsDatastore`, in SuperGenius (not the library — it references ipfs-lite types beyond CID, per v1.0 Q2/Q3 guardrails):

- `get(cid)`: try inner `RocksdbDatastore::get`; on `NOT_FOUND` miss → `BlockStore::Get` over `LocalBlockStore` then `S3BlockStore` (the library re-verifies bytes against the CID on every Get, `BlockStore.hpp:91-101`) → on Found, re-cache via inner `set(cid, bytes)` → return. Transport failure must propagate as an error (the wrapper cannot distinguish taxonomy through `IpfsDatastore`'s flat error space — it returns the inner miss error; v1.0's "never conflate" discipline is preserved *inside* the library, and the wrapper simply does not fall back on non-miss errors).
- `set(cid, bytes)`: inner `set` + (gated) `LocalBlockStore::Put` journal spill (see write path).
- `contains/has`: inner contains; optionally OR with `LocalBlockStore::Has`. v1: inner-only (cheap, avoids S3 HEAD on the hot path).
- `seal/is_sealed`: delegate to inner store unchanged — these are ipfs-lite prune markers (`merkledag_service_impl.cpp:23-25, :34-37` maps them to `markResolved/isResolved`), not block-store concepts (v1.0 research Q3).
- `remove`: delegate to inner (used by `removeNode`; today only reachable via `GraphsyncDAGSyncer::removeNode` — the CRDT path never calls it; GC eviction composes over it deliberately, see GC section).

Wiring change is confined to `globaldb.cpp:322-349`: construct `LocalBlockStore`/`S3BlockStore` (config-gated) → wrap `ipfsDataStore` → pass wrapper to `GraphsyncDAGSyncer` at `:344`. `GraphsyncDAGSyncer`, `CrdtDatastore`, `PubSubBroadcasterExt`, and ipfs-lite-cpp remain untouched.

**CID-type note:** `sgns::blockstore::Cid = libp2p::multi::ContentIdentifier` (`Cid.hpp:38`) and `sgns::CID : public libp2p::multi::ContentIdentifier` (`primitives/cid/cid.hpp:3-6`) — reference binding is slice-free, no conversion layer needed. But the library's verify path (`CidOf`, sha-256 only, `Cid.hpp:42-49`) must gain blake2b-256 before any CRDT CID is accepted (see Blocking Finding).

### UploadDrainer lifecycle inside the node (question c)

Facts from the shipped contract:

- `DrainPendingUploads(local, remote, options)` is a **synchronous one-shot**: snapshot `GetPendingUploads`, one remote Put per pending CID, advance journal to `UploadedAccepted` only on remote-present outcomes; interrupted drains converge idempotently (`alreadyPresent` in the success slot) (`thirdparty/sgns-blockstore/include/sgns-blockstore/UploadDrainer.hpp:29-95`). The `UploadedAccepted → UploadedDurable` transition is deliberately NOT the drainer's — caller territory (`UploadDrainer.hpp:24-27`).
- `LocalBlockStore` is single-threaded by contract (`LocalBlockStore.hpp:106-108`) — all access (spill `Put` from the DAG worker, drainer's `Get`/`MarkUploadedAccepted`, GC's `EvictLocal`) must serialize. The spill hook already serializes under `dagMutex_`; the drainer thread needs its own mutex around LocalBlockStore access (or a strand).

**Recommended lifecycle (mirrors the existing backup loop exactly):**

| Concern | Decision | Precedent / citation |
|---|---|---|
| Thread | Dedicated `std::thread` + `condition_variable::wait_for` interval loop, owned by `GlobalDB` (or a small `ColdStorageManager` it owns) | `GlobalDB::StartBackupLoop` `globaldb.cpp:429-467`, `StopBackupLoop` `:469-477` |
| Which asio context | **Neither.** Not `io_` (GeniusNode's main context, `GeniusNode.cpp:308`) and not `m_pubsub->GetAsioContext()` — that context runs graphsync serving; blocking it freezes the node (`graphsync_dagsyncer.cpp:544-548` comment documents exactly this hazard) | GeniusNode's dedicated-io_context-per-adapter precedent at `GeniusNode.cpp:3989-4002` exists but a plain thread is simpler for a sync loop |
| Start | From `GlobalDB::Start()` after `StartBackupLoop()` (`globaldb.cpp:479-490`): first run **restart reconciliation** — `GetPendingUploads()` snapshot → immediate drain pass (clears crash leftovers; the journal is the recovery contract, `LocalBlockStore.hpp:115-121`) — then enter the interval loop | `Start()` structure `globaldb.cpp:479-490` |
| Stop/shutdown | Join in `GlobalDB::ShutdownNow` adjacent to `StopBackupLoop()` (`:124`): stop accepting spills (CRDT workers quiesce via `CancelAndCloseNow`, `:131-134`) → final drain pass (bounded; interrupted items simply stay pending — next startup reconciles) → close `LocalBlockStore` (releases the Windows LOCK; `LocalBlockStore.hpp:122-135` teardown-order note) → tear down S3 client | `ShutdownNow` `globaldb.cpp:113-135` |
| Interplay with backup engine | Independent artifacts, no shared state: RocksDB `BackupEngine` operates on the CRDT DB (`globaldb.cpp:231-313`); the blockstore journal lives in its own DB directory (`LocalBlockStore.hpp:76-90`, D-01 — never the GlobalDB directory). A backup restore of the CRDT DB does not (and must not) restore the blockstore; block CIDs restored into the CRDT DB may miss locally but remain fetchable via read-fallback | `globaldb.cpp:228-277` restore path; `LocalBlockStore.hpp:76-90` |
| Durability advancement | A separate, slower cadence (or drain-epilogue): s3d v0.2.1 has **no per-object staged-vs-durable signal**; the only positive mechanism is admin `POST /objects/flush` ("Uploads all pending objects to Sia immediately… Blocks until done") + pipeline-global counters (`pendingObjects == 0`) | `thirdparty/sgns-blockstore/docs/s3d-durability.md` §2-§3 |

### GC design sketch (question d)

**What is actually in the CRDT RocksDB** (single DB, opened `globaldb.cpp:196-318`; CRDT namespace root `HierarchicalKey("crdt")`, `globaldb.cpp:360-365`):

| Keyspace | Layout | Owner / citation |
|---|---|---|
| Block bytes | key = `cid.toBytes()` (raw CID binary), value = raw node bytes | `RocksdbDatastore` (v1.0 research, `datastore_rocksdb.cpp:17-21`) — same keyspace `LocalBlockStore` uses (`LocalBlockStore.hpp` D-01 note: byte-compatible keys) |
| Elements (AWORSET membership) | `/crdt/s/<key>` (cid sets) | `crdt_set.hpp` `ElemsPrefix` ("`/namespace/s/key`"); wired at `crdt_datastore.cpp:65` (`setsNamespace_ = "s"`, `crdt_datastore.hpp`) |
| Tombstones | `/crdt/t/<key>` | `crdt_set.hpp` `TombsPrefix` ("`/namespace/t/key`") |
| Current values + priority | `/crdt/k/<key>/v`, `/crdt/k/<key>/p` | `crdt_set.hpp` `ValueKey` ("`/namespace/k/key/v`"), `KeysKey`, `GetPrioritySuffix` |
| Heads + heights | `/crdt/h/<topic>/<cid>` | `crdt_heads.hpp` `GetKey` ("`/namespace/topic/cid`"); wired at `crdt_datastore.cpp:448` (`headsNamespace_ = "h"`) |

**What "cold-eligible CRDT data past retention" means against this layout:** *only the block-bytes keyspace*. A CID is a GC candidate iff:

1. **Retention-aged:** the delta it carries is older than the retention horizon. Age evidence: the CRDT priority (monotonic height, `crdt_datastore.cpp:1512-1522` — "height + 1… minimum height is 1") recorded in `/crdt/h` head entries and in the delta itself; plus an app-level notion for bulky namespaces (the existing precedent is result retention: `result_retention_hours` / `result_retention_max_mb` parsed at `GeniusNode.cpp:538-548`, enforced by `StartResultGC`/`RunResultGC` `GeniusNode.cpp:4674-4800` — note that precedent is *file-system* GC of the bitswap results dir + `bitswap_->unpersistBlock`, i.e. local eviction without CRDT deletion; CRDT GC reuses its shape, not its storage).
2. **Not reachable from current heads:** enumerate heads via `CrdtHeads::GetList` (`crdt_heads.hpp:117-120`), walk the causal DAG via node links (`GraphsyncDAGSyncer::TraverseCIDsLinks`, `graphsync_dagsyncer.cpp:665+`; link enumeration per node). Everything reachable from any head is pinned. Sealed/resolved markers (`isResolved` → `is_sealed`, `merkledag_service_impl.cpp:34-37`) may shortcut traversal but are per-node state, not a reachability proof — walk, don't assume.
3. **Durably remote:** `LocalBlockStore::GetUploadState(cid) == UploadedDurable` (`LocalBlockStore.hpp:188-215`). Given s3d v0.2.1's accepted-is-max-provable ceiling (`s3d-durability.md` §2), the honest gate is: run a flush cycle (admin `POST /objects/flush`, blocks until done, §3), observe `pendingObjects == 0`, only then bulk-`MarkUploadedDurable` the drained set. Never evict on `UploadedAccepted` alone.

**Mechanism — local removal maps to eviction, not deletion:**

```
GC pass (own cadence, off the hot paths):
  candidates = ForEach(LocalBlockStore) ∪ spilled-CID index         [BlockStoreTooling.hpp:36-45]
             ∩ age > retention
             ∖ reachable(heads walk)
             ∩ UploadState == UploadedDurable
  for each cid:
      GlobalDB ipfsDatastore->remove(cid)      // drop hot-copy bytes from the CRDT RocksDB
      LocalBlockStore::EvictLocal(cid)         // drop cold-copy bytes + journal record
      // S3 object is NEVER deleted: BlockStore has no Remove (BlockStore.hpp:22-28, CORE-05)
      // /crdt/s, /crdt/t, /crdt/k, /crdt/h metadata rows are NEVER touched
  retrievability: next get(cid) anywhere (local read or graphsync serve)
      → RocksdbDatastore miss → read-fallback → S3 Get (CID-verified) → re-cache → serve
```

**Why this honors the doc's CRDT correctness requirements** (`supergenius-sharded-ipld-cache-architecture.md`, "CRDT correctness requirements"):

- *Local eviction is not a logical delete* — `EvictLocal`'s own contract says it "never touches any remote tier" and "local eviction is not a CRDT deletion" (`LocalBlockStore.hpp:224-249`); the eviction invariant is quoted verbatim in `BlockStore.hpp:22-28`.
- *Tombstones cannot be purged merely because they are old* — tombstones live under `/crdt/t/<key>` as CRDT metadata, a keyspace this GC never enumerates or writes. They are also tiny relative to blocks; leaving them permanent is cheap.
- *Current heads retain causal history* — the reachability walk from `GetList` pins exactly that set; `/crdt/h/**` and `/crdt/s/**` rows are never removed, so a later re-fetch/re-merge cannot resurrect tombstoned values (merge precedence rides on stored priorities + tombstone sets, not on block presence).
- *A cache miss must not be interpreted as absence* — true by construction: the CRDT layer's `GetKey`/`QueryKeyValues` read `/crdt/s`, `/crdt/k` (metadata), never block bytes; block bytes are only materialized via the DAG syncer paths that the read-fallback covers.
- *Restoration must not resurrect hidden values* — restored blocks re-enter only through `MerkleDagServiceImpl::getNode` as raw bytes for DAG traversal; the merge decision was already recorded in the metadata keyspaces.
- *GC requires a formally defined causal-stability and reachability policy; initial versions avoid permanent deletion of archived history* — v1 GC is eviction-only; permanent S3 deletion is out of scope by interface (no `Remove` on `BlockStore`, `BlockStore.hpp:30-33`).

**Open GC risks to flag for the planner:** (1) the reachability walk is O(history) — needs batching/_rate limiting and must not run on `io_`; (2) `result_retention_hours` semantics are filesystem-level today — v1.1 should decide whether CRDT-keyed result namespaces get a height/timestamp-based horizon (needs a per-key age source; priorities are monotonic per-topic but not wall-clock); (3) a node that evicts a block another node still needs will re-fetch via graphsync from peers or S3 — fallback ordering (peers already race inside `getNode`; S3 enters only via the decorator's miss path) must be measured, not assumed cheap.

### Component inventory and build order (question e)

See Component Responsibilities table (new vs modified) and the Build Order section below.

---

## Component Responsibilities

| Component | Responsibility | New/Modified | Anchor (file:line) |
|---|---|---|---|
| `sgns-blockstore` blake2b-256 widening + dag-cbor key token | Accept CRDT CIDs (blake2b-256/DAG_CBOR); S3 key codec token | **MODIFIED** (library v1.1, additive) | `Cid.hpp:42-60` (CidOf sha256-only), `cid.cpp:129-135` (getCidOf blake2b), `S3BlockStore.hpp:22-38` |
| `BlockStoreBackedIpfsDatastore` | `IpfsDatastore` decorator: spill-on-`set`, fallback-on-`get`, pass-through `seal`/`contains`/`remove` | **NEW** (SuperGenius) | implements `datastore.hpp:26-70`; wraps object built at `globaldb.cpp:329` |
| `ColdStorageManager` (or GlobalDB members) | Own `LocalBlockStore` + `S3BlockStore` + drainer thread + durability-flush cadence + GC pass | **NEW** (SuperGenius; may live inside GlobalDB to reuse lifecycle) | pattern: `globaldb.cpp:429-477` |
| `GlobalDB::New` / `Init` / `Start` / `ShutdownNow` | Accept `ColdStorageOptions`; build wrapper at :329; start/stop drainer | **MODIFIED** | `globaldb.hpp:50-59`, `globaldb.cpp:322-349`, `:479-490`, `:113-135` |
| `GeniusNode::LoadCrdtConfig` + `InitDatabase` | Parse `s3d.*` config (blank = disabled); pass options into `GlobalDB::New` | **MODIFIED** | `GeniusNode.cpp:552-610` (backup fields precedent `:577-600`), `:2119-2127` |
| GC scheduler | Retention pass over spilled CIDs: age ∩ ¬reachable ∩ durable → evict | **NEW** (SuperGenius) | precedent `GeniusNode.cpp:4674-4800` |
| `SuperGenius/src/crdt/CMakeLists.txt` + `GeniusSDK/cmake/CommonBuildParameters.cmake` | Link `sgns-blockstore` (already built by thirdparty superbuild) | **MODIFIED** | `CommonTargets.cmake:863-919` (exists); `CommonBuildParameters.cmake:313-317` (AsyncIOManager pattern, sgns-blockstore entry absent today) |
| `GeniusWallet/assets/crdt_config.json` (+ SuperGenius assets) | Document `s3d` fields | **MODIFIED** | config file consumed via `GeniusNode.cpp:556-560` |
| `GraphsyncDAGSyncer`, `CrdtDatastore`, `PubSubBroadcasterExt`, `MerkleDagServiceImpl`, ipfs-lite-cpp | — | **UNCHANGED (deliberately)** | the entire point of the seam; `graphsync_dagsyncer.cpp:58-66`, `crdt_datastore.cpp:44-48` |
| `UploadDrainer`, `LocalBlockStore`, `S3BlockStore`, `BlockStoreTooling` | Library side (shipped v1.0) | **UNCHANGED** (except widening above) | `UploadDrainer.hpp:85-95`, `LocalBlockStore.hpp:96-249`, `S3BlockStore.hpp:61-145` |

## Recommended Project Structure (SuperGenius side)

```
SuperGenius/src/crdt/globaldb/
├── globaldb.hpp/.cpp              # MODIFIED: ColdStorageOptions param, wiring, lifecycle
├── blockstore_ipfs_datastore.hpp   # NEW: the IpfsDatastore decorator (spill + fallback)
├── blockstore_ipfs_datastore.cpp
├── cold_storage_options.hpp       # NEW: config struct (endpoint, bucket, key_prefix,
│                                  #     local_store_path, drain_interval, retention,
│                                  #     durability gate policy; blank == disabled)
└── cold_storage_manager.hpp/.cpp  # NEW: drainer thread, flush cadence, GC pass
```

Rationale: keeps the adapter beside its single wiring site (`globaldb.cpp:322-349`) per v1.0 research Q3; `CMakeLists.txt` in `src/crdt` gains the link; nothing new appears outside `src/crdt/globaldb` on the C++ side except `GeniusNode` config plumbing.

## Architectural Patterns

### Pattern 1: Single-choke-point datastore decorator
**What:** one decorator at the `IpfsDatastore` construction site captures write-spill, read-fallback, and (via `remove`) GC eviction for every block, because writes serialize through `MerkleDagServiceImpl::addNode` (`merkledag_service_impl.cpp:17-21`) and all reads (local + serving) resolve through `block_service_->get` (`graphsync_impl.cpp:374`, `graphsync_dagsyncer.cpp:1006-1010`).
**When:** always, in this codebase.
**Trade-offs:** the decorator inherits `IpfsDatastore`'s flat error space (cannot export `BlockStatus` taxonomy upward — acceptable; taxonomy discipline stays inside the library); it sees only block bytes, never CRDT semantics (correct — the doc's block layer "should not know about CRDT merges").

### Pattern 2: Journal-then-drain durability
**What:** inline spill = `LocalBlockStore::Put` (atomic block+PendingUpload WriteBatch, local RocksDB WAL — milliseconds), remote durability = background `UploadDrainer` passes; crash between the two is recovered by startup `GetPendingUploads` reconciliation; idempotent re-drain via `alreadyPresent`.
**When:** any write path that holds a shared mutex (`dagMutex_`) or runs on a latency-sensitive thread.
**Trade-offs:** two local copies of cold bytes exist until drain (CRDT RocksDB + LocalBlockStore) — bounded by drain cadence; acceptable and explicitly the v1.0 design.

### Pattern 3: Backup-loop-thread lifecycle for background loops
**What:** dedicated `std::thread` + CV-interval + stop-flag + join-in-shutdown, twice-proven in `globaldb.cpp:429-477`.
**When:** any synchronous library loop (drainer, GC, flush cadence).
**Trade-offs:** no asio integration (can't use steady_timer on `io_` without occupying it); fine for minute-scale cadences.

### Pattern 4: Eviction-only GC with reachability pinning
**What:** GC = `remove` hot copy + `EvictLocal` cold copy, gated on durability + ¬head-reachability + age; no remote deletion (impossible by interface), no metadata purge.
**When:** whenever "GC" is said in a CRDT context.
**Trade-offs:** remote history grows unboundedly (doc explicitly accepts this for initial versions; permanent-deletion policy is a future, formally-specified step).

## Data Flow

### Write-spill (config-gated; disabled = today's path byte-for-byte)

```
App → GlobalDB::Put → CrdtDatastore::Publish → AddDAGNode → DAG worker
   → GraphsyncDAGSyncer::addNode [dagMutex_]
   → MerkleDagServiceImpl::addNode
   → BlockStoreBackedIpfsDatastore::set(cid, bytes)
        ├─ inner RocksdbDatastore::set            (unchanged hot path)
        └─ if s3d.enabled: LocalBlockStore::Put   (atomic bytes+PendingUpload journal,
                                                   │  local RocksDB, sync WAL — fast)
                                                   ▼
                              [drainer thread, interval] DrainPendingUploads
                                                   │  S3BlockStore::Put (conditional,
                                                   │  v1/blocks/<codec>/<xx>/<cid>)
                                                   └─ MarkUploadedAccepted
                              [flush cadence] s3d admin flush + pendingObjects==0
                                                   └─ MarkUploadedDurable   ← eviction gate
```

### Read-fallback (serving + local reads share it)

```
graphsync responder (graphsync_impl.cpp:374)  │  local read (graphsync_dagsyncer.cpp:1006)
                  └──────────┬────────────────┘
             MerkleDagServiceImpl::getNode
                             ▼
             BlockStoreBackedIpfsDatastore::get(cid)
               1. inner RocksdbDatastore::get ─── hit ──► return
               2. miss ─► LocalBlockStore::Get ─── hit ──► (verified) re-cache(set) ─► return
               3. miss ─► S3BlockStore::Get ────── hit ──► (CID-verified) re-cache ──► return
               4. all miss ─► propagate inner NOT_FOUND (requester falls back to
                              peer fetch inside getNode's route loop, :206-353)
```

### GC pass

```
timer ─► candidates = spilled-CID index (or LocalBlockStore::ForEach, tooling surface)
         ∩ age/priority past retention   ∖ reachable(CrdtHeads::GetList → link walk)
         ∩ UploadState == UploadedDurable
         ─► ipfsDatastore remove(cid) + LocalBlockStore::EvictLocal(cid)
         ─► S3 object retained; retrievability via read-fallback on any later get
```

## Scaling Considerations

| Concern | Integration slice | Later |
|---|---|---|
| Spill overhead per block write | +1 sync local-RocksDB WriteBatch on the (serialized) DAG worker — same order as the existing CRDT RocksDB write it accompanies | none needed |
| Drain throughput | one S3 PUT per pending CID per pass; s3d packs small objects into slabs server-side | CARv2 packing only if benchmarks justify (doc's "measure first") |
| Read-fallback latency | S3 GET only on double miss; serving path unchanged on hit | staggered peer-vs-S3 race is doc Phase 3 territory, not this milestone |
| GC pass cost | O(history) reachability walk + RocksDB deletes — must be batched and scheduled off `io_` | incremental/anchored walks from head checkpoints |
| Object count on S3 | one object per CID (`v1/blocks/...`) | s3d SQLite metadata growth is a characterized risk (`s3d-durability.md` §1) — monitor, don't pre-optimize |

## Anti-Patterns

### Anti-Pattern 1: Inline S3 PUT inside `IpfsDatastore::set`
**What people do:** "just call S3BlockStore::Put in set()".
**Why it's wrong:** `set` holds `GraphsyncDAGSyncer::dagMutex_` (`graphsync_dagsyncer.cpp:189`); `GetNodeFromMerkleDAG` needs the same mutex (`:1007`) — one slow upload freezes all block adds, all local reads, and every serving lookup.
**Do this instead:** journal locally (`LocalBlockStore::Put`), drain in background.

### Anti-Pattern 2: Running the drainer on the pubsub/graphsync asio context
**Why it's wrong:** `GraphsyncImpl` runs response handling on `m_pubsub->GetAsioContext()` (`globaldb.cpp:339-343`); a blocking drain stalls the responder — the hazard is documented in-tree at `graphsync_dagsyncer.cpp:544-548`.
**Do this instead:** dedicated thread, backup-loop pattern.

### Anti-Pattern 3: GC by deleting CRDT rows or tombstones
**Why it's wrong:** violates every CRDT-correctness clause in the architecture doc; `/crdt/t`, `/crdt/s`, `/crdt/k`, `/crdt/h` are the convergence state, not cache.
**Do this instead:** evict block bytes only, gate on durability + reachability.

### Anti-Pattern 4: Spilling before the hash gate is widened
**Why it's wrong:** every CRDT CID (blake2b-256) throws `std::invalid_argument` at the library boundary today (`Cid.hpp:50-56`) — the node would crash (or need to swallow) on the very first block.
**Do this instead:** land the additive widening first; keep the SuperGenius seam behind it.

### Anti-Pattern 5: Sharing the CRDT RocksDB with LocalBlockStore to "save a DB"
**Why it's wrong:** re-couples lifecycles (backup/restore/corruption-abort of the CRDT DB, `globaldb.cpp:228-317`); v1.0 research Anti-Pattern 6 stands.
**Do this instead:** own directory per `LocalBlockStoreOptions::path` (D-01).

### Anti-Pattern 6: Treating `UploadedAccepted` as evictable
**Why it's wrong:** s3d v0.2.1 accepted = local staging only; no per-object durable signal exists (`s3d-durability.md` §2).
**Do this instead:** flush + `pendingObjects == 0` → `MarkUploadedDurable` → only then evict.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---|---|---|
| Sia `s3d` | `S3BlockStore` → `S3Client` adapter (minio-cpp), endpoint/bucket from `crdt_config.json` | accepted ≠ durable; admin flush cadence; dev-gated test lane per v1.0 TEST-01 |
| RocksDB BackupEngine (existing) | unchanged | independent of blockstore journal; restore does not touch it |

### Internal Boundaries

| Boundary | Communication | Notes |
|---|---|---|
| SuperGenius ↔ sgns-blockstore | `BlockStoreBackedIpfsDatastore` decorator only; C++ static link via `find_package(sgns-blockstore CONFIG)` | library stays CID/bytes-only; adapter lives in SuperGenius (v1.0 Q2/Q3 guardrails) |
| GlobalDB ↔ drainer/GC threads | owned `std::thread`s + stop flags, joined in `ShutdownNow` | backup-loop precedent `globaldb.cpp:429-477` |
| CRDT metadata ↔ block bytes | GC never crosses: metadata keyspaces read-only to GC | reachability input only (`GetList` + link walk) |
| Build system | thirdparty superbuild already produces `sgns-blockstore` (`CommonTargets.cmake:863-919`, `DEPENDS libp2p rocksdb minio-cpp` at `:915`); downstream `find_package` wiring still absent | add per `CommonBuildParameters.cmake:313-317` pattern |

## Suggested Build Order (for the roadmapper)

Dependency rationale: the storage library is done ⇒ (0) its API must accept real CRDT CIDs before anything in SuperGenius can so much as link a spilled block ⇒ (1) build wiring before runtime code (nothing compiles otherwise) ⇒ (2) config plumbing before behavior (the gate must exist before the gated feature) ⇒ (3) write-spill before read-fallback (fallback needs S3 content to fall back *to*; spill fills it; both live in one adapter but ship as separate phases for risk isolation) ⇒ (4) lifecycle hardening once both directions move bytes ⇒ (5) GC strictly last (it *depends on* fallback for retrievability and on the durability journal for its gate — evicting before those exist destroys data).

| # | Phase candidate | Contents | Why this position |
|---|---|---|---|
| 0 | **sgns-blockstore v1.1: CRDT-CID support** | widen hash gate to blake2b-256 (verify-on-put/get against the CID's own multihash), `dag-cbor` codec token in S3 key layout, conformance cases with blake2b DAG_CBOR CIDs | hard blocker: `Cid.hpp:50-56` vs `cid.cpp:129-135`; additive, library-only, no SuperGenius coupling |
| 1 | **Build wiring** | `CommonBuildParameters.cmake` `sgns-blockstore_DIR` + `find_package` (AsyncIOManager pattern `:313-317`); link in `SuperGenius/src/crdt`; (already-built thirdparty artifact, `CommonTargets.cmake:863-919`) | compile/link before runtime; keeps CI green on all platforms incl. cross-compiles |
| 2 | **Config + options plumbing** | `ColdStorageOptions`; `LoadCrdtConfig` `s3d.*` fields (`GeniusNode.cpp:552-610` pattern); thread through `GlobalDB::New` (`globaldb.hpp:50-59`, `GeniusNode.cpp:2119-2127`); blank = disabled (gate semantics live here) | the config gate must precede any behavior; also defines retention knobs GC will consume |
| 3 | **Write-spill (adapter `set` + journal)** | `BlockStoreBackedIpfsDatastore` `set` path + `LocalBlockStore::Put` inline + `ColdStorageManager` drainer thread (backup-loop pattern) + startup `GetPendingUploads` reconciliation + shutdown ordering in `ShutdownNow` | fills S3; journal-then-drain keeps `dagMutex_` latency flat; disabled path = byte-identical to today |
| 4 | **Read-fallback (adapter `get`)** | miss → LocalBlockStore → S3 → CID-verified re-cache; covers graphsync serving (`graphsync_impl.cpp:374`) and local reads (`:1006`) with no further wiring | needs S3 content (phase 3) to be testable end-to-end; single wiring already in place |
| 5 | **Durability & lifecycle hardening** | flush cadence + `MarkUploadedDurable` bulk advancement; drainer/GC shutdown interplay with backup loop; failure-injection (crash between journal and drain; s3d outage ≠ NotFound) | makes the eviction *gate* real before GC exists; v1.0 fault-kit reuse |
| 6 | **GC of cold-eligible blocks** | retention scan ∩ ¬head-reachable ∩ `UploadedDurable` → `remove` + `EvictLocal`; pinned namespaces (`/genesis/**`, heads); metrics | last: depends on fallback (retrievability) + durability gate (safety); also the only phase that deletes anything anywhere |

Phase-flags for the planner: Phase 0 needs library-side decisions (which multihashes beyond blake2b-256, key-layout compat for already-written sha256 objects — none in production yet, so free); Phase 4 needs a latency-budget decision (S3 GET on the serving path — measure before enabling by default); Phase 6 needs the reachability-walk cost model and the age-evidence decision (priority-height vs wall-clock). Everything else is established pattern.

## Sources

**Read directly from the workspace on 2026-10-22 (HIGH):**
- `SuperGenius/src/crdt/globaldb/globaldb.cpp` — `:60-88 New`, `:106-135 ShutdownNow`, `:196-318 DB open/restore`, `:322/:329/:339-343/:344/:347-350/:354/:360-365 Init seam`, `:429-477 backup loop`, `:479-490 Start`, `:502-511 Put`
- `SuperGenius/src/crdt/globaldb/globaldb.hpp` — `:28-34 BackupOptions`, `:50-59 New signature`
- `SuperGenius/src/crdt/impl/crdt_datastore.cpp` — `:44-48 New`, `:65 sets namespace`, `:448 heads namespace`, `:1029 dagSyncer_->addNode`, `:1438-1454 DeleteKey`, `:1456-1461 Publish`, `:1475-1533 CreateDAGNode`, `:1586-1610 AddDAGNode`
- `SuperGenius/src/crdt/crdt_datastore.hpp` — worker model, `AddDAGNode`, `WaitForJob`, namespaces (`headsNamespace_="h"`, `setsNamespace_="s"`)
- `SuperGenius/src/crdt/graphsync_dagsyncer.hpp` + `impl/graphsync_dagsyncer.cpp` — `:58-66 ctor/MerkleDagServiceImpl`, `:187-202 addNode`, `:206-353 getNode`, `:511-516 HasBlock`, `:519-529 GetNodeWithoutRequest`, `:532-558 StartSync` (`:544-548 responder-thread comment`), `:606-664 BlockReceivedCallback`, `:665+ TraverseCIDsLinks`, `:819-859 LRU`, `:1006-1010 GetNodeFromMerkleDAG`
- `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/graphsync/impl/graphsync_impl.{hpp,cpp}` — `:286 onRemoteRequest`, `:312 post`, `:326 service lock`, `:374 getNode`
- `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/merkledag/impl/merkledag_service_impl.cpp` — `:17-21 addNode→set`, `:28-31 getNode→get`, `:23-25/:34-37 seal`
- `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/datastore.hpp` — the `IpfsDatastore` surface
- `thirdparty/ipfs-lite-cpp/primitives/cid/cid.cpp` — `:129-135 getCidOf = CIDv1/DAG_CBOR/blake2b-256`
- `SuperGenius/src/crdt/crdt_set.hpp` — `ElemsPrefix /crdt/s`, `TombsPrefix /crdt/t`, `KeysKey/ValueKey /crdt/k/<key>/v|/p`
- `SuperGenius/src/crdt/crdt_heads.hpp` — `GetKey /namespace/topic/cid`, `GetList`
- `SuperGenius/src/account/GeniusNode.cpp` — `:308 io_`, `:538-548 retention config`, `:552-610 LoadCrdtConfig`, `:2119-2127 GlobalDB::New call`, `:2141 Start`, `:3989-4002 io_context precedent`, `:4674-4800 StartResultGC/RunResultGC`
- `thirdparty/sgns-blockstore/include/sgns-blockstore/{BlockStore,LocalBlockStore,S3BlockStore,UploadDrainer,BlockStoreTooling,Cid,Durability}.hpp` — the frozen v1.0 contract (sha256 gate, EvictLocal, journal states, drain semantics, S3 key layout, durability levels)
- `thirdparty/sgns-blockstore/docs/s3d-durability.md` — §2 no per-object signal, §3 flush primitive (committed evidence)
- `thirdparty/build/CommonTargets.cmake` — `:837 minio-cpp`, `:863-919 sgns-blockstore` (`:915 DEPENDS`, `:919 config dir`)
- `GeniusSDK/cmake/CommonBuildParameters.cmake` — `:313-317 AsyncIOManager pattern` (no sgns-blockstore entry yet)
- `supergenius-sharded-ipld-cache-architecture.md` — authoritative design: read/write paths, durability levels, CRDT correctness requirements, implementation phases
- `.planning/research/ARCHITECTURE-rocksdb-backup-2026-10-19.md` — v1.0 baseline (seam decision Q3, guardrails Q2, S5 patterns Q6)

---

*Architecture research for: SuperGenius ↔ sgns-blockstore integration (rocksdb-backup v1.1)*
*Researched: 2026-10-22*
