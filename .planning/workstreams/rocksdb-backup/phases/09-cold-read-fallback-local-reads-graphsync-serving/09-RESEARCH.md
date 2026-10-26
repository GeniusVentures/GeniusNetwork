# Phase 9: Cold Read Fallback — Local Reads & Graphsync Serving - Research

**Researched:** 2026-10-26
**Domain:** SuperGenius CRDT read-path integration of `sgns-blockstore` (cold-read fallback chain + responder-side async cold serving)
**Confidence:** HIGH (codebase-grounded — every load-bearing claim read from source this session with file:line; the two MEDIUM/ASSUMED items are isolated and flagged)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Local-read fallback chain (READ-01 / SC1)**
- **D-01:** **Cold before peers** — the local read chain is hot datastore → LocalBlockStore → S3BlockStore → peers. Deterministic resolution with no peer dependency; this is the required shape for Phase-11 GC-evicted CIDs (GC-03 end-to-end retrieval) and the literal reading of READ-01 ("miss the hot datastore → fetch from the blockstore"). Peers-before-cold was rejected: GC-evicted reads would pay a full peer-failure timeout before S3 — **Reversibility:** costly
- **D-02:** **Both cold tiers are read sources** — LocalBlockStore (cold dir, same disk) is consulted before S3; a cold-dir hit avoids the S3 round trip — **Reversibility:** reversible
- **D-03:** **Cold transport failure falls through to peers** — when the cold tiers are reachable-but-failing (s3d down, network fault) during a local read, the failure is logged + counted and the chain continues to peers; only failure across all sources surfaces, classified honestly (definitive absence at both cold tiers + peers = NotFound; transport = TemporarilyUnavailable) — **Reversibility:** costly
- **D-04:** **Always re-cache** — every successful cold fetch (either tier) writes back into the hot store through the dedicated rehydrate path (SC4) before the read returns; spill re-journals implicitly since Phase-8 spill-on-write is the default write path — **Reversibility:** reversible

**Cold-serve degradation (READ-02 / SC2)**
- **D-05:** **Don't-have + re-warm** — on deadline expiry the responder completes the peer's request negatively now (the peer's own retry ladder fails over), and a background re-warm continues fetching the block into the hot store so the NEXT request for that CID is served locally. Bounded responder work per request. Hold-to-deadline was rejected: a slow s3d inflates concurrent held requests across many peers — **Reversibility:** costly
- **D-06:** **Cold-serve is on whenever the blockstore section is enabled** — no extra activation switch; the deadline + bounded executor are the safety mechanisms — **Reversibility:** costly
- **D-07:** **Coalesced re-warm on the same bounded executor** — one in-flight re-warm per CID; concurrent deadline-missed requests for the same CID attach to the in-flight re-warm or find it hot. The re-warm carries its own (longer) budget — **Reversibility:** reversible

**HasBlock cold-awareness (SC3)**
- **D-08:** **HasBlock stays local-only** — hot check then cold-dir presence check; NEVER an S3/network lookup from `HasBlock`. `HasBlock` runs on the pubsub receive path (`pubsub_broadcaster_ext.cpp:632`) and CRDT datastore (`crdt_datastore.cpp:706, 1881`) — exactly where the documented whole-node-freeze hazard lives — **Reversibility:** costly
- **D-09:** **Cold-dir check slots after the hot check misses, gated on cold storage enabled** — disabled deployments keep byte-identical HasBlock — **Reversibility:** reversible

**Config surface**
- **D-12:** **Compile-time only — no new config knobs this phase** — serve deadline, executor size, and re-warm budget are compile-time defaults; the `blockstore` schema (Phase 7 D-01/D-02 + Phase 8 D-06 `backpressure` sub-object) is unchanged — **Reversibility:** reversible

### The Agent's Discretion
(researched and recommended in this document — see the numbered sections below)
- Exact compile-time default values (serve deadline vs peer stream timeout headroom, executor size, re-warm budget) — §7, §9
- Where the fallback chain lives: Phase-8 decorator `Get` vs `GraphsyncDAGSyncer::GetNodeWithoutRequest` vs both — §4
- Executor mechanics (thread-pool shape, queue bounds, shutdown join ordering relative to the D-10/D-11 drainer lifecycle) — §6, §8
- Negative-response semantics toward the peer on deadline expiry (graphsync partial/final response shape) — §5
- The exact `BlockStatus{StatusClass, BlockSource}` → SuperGenius error mapping table at the seam — §3
- Rehydrate path mechanics: how bytes + resolved marker compose with the hot-store write — §2
- Whether `GetNodeWithoutRequest` gains the same cold-chain awareness as the decorator read path (and how pubsub-received CIDs interact with D-08) — §4
- How the SC2 whole-node-freeze regression test is built and how the latency-budget benchmark measures cold-serve without live endpoints — §10
- Exact log-message wording (s3d blips distinguishable from peer failures in logs) — §3.3
- Tier-1 test target registration mechanics — §10.3
- In-flight cold-fetch coalescing for concurrent local reads of the same CID — §8.3

### Deferred Ideas (OUT OF SCOPE)
- A `blockstore.read` config sub-object (serve deadline / executor knobs) — deferred to the milestone-Future metrics surface; this phase is compile-time only (D-12)
- Cold-serve latency metrics / per-CID cold-fetch telemetry — milestone-Future metrics list
- Read-path per-CID in-flight coalescing beyond what the planner deems necessary — candidate for later hardening if SC2 evidence shows stampede behavior
- Reviewed todo `2026-08-10-fix-vulkan-capability-probe-deadlock…` — standing unrelated ruling; stays backlog
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| READ-01 | Local node reads that miss the hot datastore fetch from the blockstore (Local tier → S3 tier), CID-verify, and re-cache before returning; transport failures surface as `TemporarilyUnavailable`, never as `NotFound` | §2 (rehydrate), §3 (taxonomy table), §4 (placement), §7 (chain mechanics); library `Get` CID-verifies internally [VERIFIED: BlockStore.hpp:96-102] |
| READ-02 | Graphsync serving for a CID not held locally performs an async cold fetch with a deadline, off the responder's inline path, CID-verifies, then serves | §5 (responder semantics), §6 (executor), §8 (coalescing), §9 (latency budget), §11 (freeze-regression test design) |
| (context) GC-03 | Any GC-evicted CID remains retrievable end-to-end (Phase 11, but D-01's chain order exists to serve it) | §4 chain order; Local-tier-before-S3 makes eviction-window reads cheap |
</phase_requirements>

## Project Constraints (from AGENTS.md)

- **C++17/C++20, CMake, Boost.Asio, libp2p, Protocol Buffers** — must match existing SuperGenius conventions; no new external dependencies (workstream Out of Scope table)
- **Coding standard** (`Coding Standards.md`, Corelinux-derived): Ullman braces, PascalCase types/functions, `m_`/trailing-underscore members, `Get`/`Is`/`Set` accessor prefixes, Doxygen `@brief/@param/@return/@note` on public interfaces, `outcome::result<T>` for fallible operations
- **Header hygiene (Phase-7/8 established, binding)**: `globaldb.hpp`, `globaldb.cpp`, `ColdStorageStack.hpp` must NEVER include gated sgns-blockstore headers; the decorator (`BlockStoreBackedIpfsDatastore.hpp:7-15`) and `ColdStorageManager.hpp` are GATED TU headers compiled only under `SGNS_COLD_STORAGE`; ungated code reaches the stack only through the `ColdStorageStack` free-function bridges [VERIFIED: ColdStorageStack.hpp:15-22]
- **Compatibility**: blank `blockstore` config = nothing constructed = byte-identical behavior (Phase-7 SC2 bar); Phase 9 must preserve this for `HasBlock`, `GetNodeWithoutRequest`, `getNode`, and the responder
- **Security**: credentials never logged (Phase-7 posture; the library's own rule: BlockStatus.hpp:63-66 "message content must NEVER embed secrets"); cold-read failure logging extends the Phase-8 redaction-by-omission pattern
- **Testing discipline** (`.planning/codebase/TESTING.md`): tests run inside the `build/<Platform>/<Config>` tree; `addtest()` registration has no LABELS support — `set_tests_properties(... LABELS "Tier1")` is mandatory for the Tier-1 lane [VERIFIED: SuperGenius/test/src/crdt/CMakeLists.txt:50-54]

## Summary

Phase 9 extends the Phase-8 cold-storage stack from the write path to the read path. The write side is already fully in place: the `BlockStoreBackedIpfsDatastore` decorator sits at the single `IpfsDatastore` seam inside `GlobalDB::New` (`globaldb.cpp:604-623`), the `ColdStorageManager` drainer owns both store handles and the one shared `cold_store_mutex_`, and `ShutdownNow()` already stops the manager between the backup loop and the lifecycle-mutex teardown [VERIFIED: globaldb.cpp:396-402].

Three structural facts dominate the design, and all three were verified in source this session:

1. **The graphsync responder runs `select`/`getNode` on the pubsub host's SINGLE-THREADED io_context.** `GraphsyncImpl` is constructed with `m_pubsub->GetAsioContext()` ("Run Graphsync response handling on the executor that owns the pubsub host's stream queues", globaldb.cpp:637-643); `GetAsioContext()` returns `m_context` [VERIFIED: gossip_pubsub.cpp:1283-1286], and `m_context` is run by exactly one thread (`m_thread = std::thread( [this]() { m_context->run(); } )` [VERIFIED: gossip_pubsub.cpp:518]). Every incoming graphsync request is handled by a task posted onto that context (`boost::asio::post(*io_context_, …)` [VERIFIED: graphsync_impl.cpp:307]) which synchronously calls the injected `MerkleDagService::getNode`/`select` and then sends one terminal response. **Any blocking wait inside the serve path — including a "bounded" deadline wait for a cold fetch — freezes all pubsub + graphsync stream processing for the wait duration.** This is the same hazard the codebase already documents at `graphsync_dagsyncer.cpp:552-555` ("pins the host's only thread and freezes the whole node").

2. **The decorator's `get()` is called under `dagMutex_`** by `GraphsyncDAGSyncer::GetNodeFromMerkleDAG` (`graphsync_dagsyncer.cpp:1006-1010`, `std::lock_guard lock( dagMutex_ )` then `dagService_->getNode( cid )`), and `dagMutex_` is the same mutex `addNode` takes (`:189-191`) — i.e., the CRDT publish path. A synchronous cold fetch inside the decorator `get()` would hold `dagMutex_` across remote S3 I/O and stall consensus publishes during an s3d outage — the read-side twin of the Phase-8 "never remote I/O on the dagMutex_-held write path" discipline. Additionally, the responder's serve path reaches the very same decorator `get()` (empty-selector requests: `service->getNode(root_cid)` at `graphsync_impl.cpp:374`), so putting the synchronous chain in the decorator would inject inline remote I/O into the single-threaded responder — violating SC2.

3. **The responder's only legal terminal answers today are `RS_FULL_CONTENT` and `RS_NOT_FOUND`**, both sent synchronously at the end of the posted task; a `select`/`getNode` *error* sets `RS_REQUEST_FAILED` but sends **no response at all** (the peer waits out its own activity timeout) [VERIFIED: graphsync_impl.cpp:396-446]. SuperGenius requesters send empty selectors (`RequestNode` passes `{}` as selector, `graphsync_dagsyncer.cpp:146`), so the empty-selector `getNode` path is the one that matters. There is no mechanism exposed to SuperGenius for sending a response later from another thread — that would require thirdparty `graphsync_impl`/`Network` surgery.

Together these facts settle the central discretion questions: **the synchronous READ-01 chain must live in `GraphsyncDAGSyncer` (outside `dagMutex_`), NOT in the decorator's `get()`**; and **the READ-02 responder integration must be a never-blocking wrapper around the dag service handed to `graphsync_->start()` — immediate don't-have (`RS_NOT_FOUND`) plus a coalesced background re-warm on a bounded executor** (exactly D-05's locked shape). A "hold the request ≤ deadline then serve" responder is NOT implementable without either thirdparty graphsync changes or freezing the single-threaded context; this research recommends against both, and the SC2 latency-budget benchmark documents the don't-have+re-warm posture rather than a hold.

**Primary recommendation:** Implement (1) a `ColdReadFallback` hook interface (ungated header, std/CID/Buffer types only) implemented in a gated TU over the Phase-8 stack's `LocalBlockStore`/`S3BlockStore` handles, injected into `GraphsyncDAGSyncer` at its single construction site (`globaldb.cpp:643`); (2) the READ-01 chain as a private `GraphsyncDAGSyncer` helper called from `GetNodeWithoutRequest` after the hot miss and from `getNode` after the hot miss **before** the peer loop (D-01 ordering); (3) the READ-02 responder as a `MerkleDagService` wrapper installed at `StartSync()` that delegates hot reads and, on miss, enqueues a per-CID coalesced re-warm on a single-thread bounded executor owned by the cold-read service, then fails fast (→ honest `RS_NOT_FOUND`); (4) `HasBlock` gains only the gated `LocalBlockStore::Has` check (D-08/D-09); (5) rehydrate = decorator `set()` bytes (+ seal-marker handling per §2.4), never `addNode`-with-routing, never pubsub, never heads.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Hot-store read + LRU cache | `GraphsyncDAGSyncer` (GrabCIDBlock / GetNodeFromMerkleDAG) | decorator (forward) | existing read front door [VERIFIED: graphsync_dagsyncer.cpp:205-227, 519-528, 1006-1010] |
| Cold-tier fetch (Local → S3), CID-verify | New gated cold-read service over library stores | `GraphsyncDAGSyncer` chain orchestration | library `Get` verifies internally [VERIFIED: BlockStore.hpp:96-102]; library single-threaded-use contract requires the shared mutex [VERIFIED: LocalBlockStore.hpp:117-119] |
| Re-cache (rehydrate) | Gated cold-read service through decorator `set()` | — | one dedicated path (SC4); decorator set = journal + hot write, local disk only [VERIFIED: BlockStoreBackedIpfsDatastore.cpp:49-95] |
| Responder cold-serve (async) | Bounded executor owned by cold-read service | responder wrapper dag service | must never block the single-thread pubsub io_context [VERIFIED: gossip_pubsub.cpp:518; graphsync_impl.cpp:307] |
| Miss taxonomy (BlockStatus → seam errors) | Cold-read service (classification) + `GraphsyncDAGSyncer` (error surface) | logging | SC3 mapping table, §3 |
| `HasBlock` cold awareness | `GraphsyncDAGSyncer::HasBlock` + gated `LocalBlockStore::Has` | — | D-08/D-09; RocksDB point lookup is freeze-safe |
| Executor lifecycle/shutdown | `GlobalDB::ShutdownNow` ordering (drainer-adjacent stop) | cold-read service `Stop()` (grace + join) | Phase-8 D-10/D-11 pattern [VERIFIED: globaldb.cpp:396-402] |
| Hermetic fault-injection tests | `SuperGenius/test/src/crdt/` (Tier-1 lane, gated) | `InMemoryS3Client` + `S3FaultKind`/keyed faults | SC5; Phase-8 spill-test pattern |

## Standard Stack (all in-repo — no new packages)

### Core
| Component | Version/State | Purpose | Why Standard |
|-----------|---------------|---------|--------------|
| `LocalBlockStore` / `S3BlockStore` / `BlockStatus` | frozen v1.0 + Phase-6 widening, already linked via `sgns-blockstore::sgns-blockstore` | cold reads (`Get` CID-verifies; `Has` cheap point lookup), rich failure taxonomy | shipped library contracts; Phase-8 already links them under `SGNS_COLD_STORAGE` [VERIFIED: test/src/crdt/CMakeLists.txt:98-113] |
| `BlockStoreBackedIpfsDatastore` (Phase-8 decorator) | shipped Phase 8 | rehydrate write target (journal + hot write in one call) | SC4's dedicated path rides its `set()`; `get()` currently a pure forward with an explicit "Phase 9 adds the cold fallback" marker comment [VERIFIED: BlockStoreBackedIpfsDatastore.cpp:120-125] |
| `ColdStorageManager` + `ColdStorageStack` | shipped Phase 8 | store-handle ownership, shared mutex, lifecycle bridges | owns `local_block_store_` + `remote_block_store_` + `cold_store_mutex_` [VERIFIED: ColdStorageManager.hpp:129-131] |
| `InMemoryS3Client` (test fake) | shipped v1.0 | hermetic S3 tier + fault table | per-op and per-key `S3FaultKind` scripting + `SetFlipBytesForKey` CID-verify corruption [VERIFIED: InMemoryS3Client.hpp:75-110] |
| GTest + `addtest()` + `set_tests_properties(LABELS "Tier1")` | existing | Tier-1 fail-closed lane | Phase-7/8 lane discipline [VERIFIED: test/src/crdt/CMakeLists.txt:50-54] |

### Supporting
| Component | Purpose | When to Use |
|-----------|---------|-------------|
| `FaultKind` on `LocalBlockStore` (it publicly inherits `FaultController`) | inject Local-tier Unavailable/CorruptData/Unauthorized for taxonomy tests | SC1 fault suite — Local tier faults, not just S3 [VERIFIED: LocalBlockStore.hpp:117-122, FaultController.hpp:19-25] |
| `LatencyInjectingS3Client` pattern (test-local `S3Client` subclass that sleeps then delegates) | latency injection for the SC2 latency-budget benchmark — the fake has NO latency hook of its own [VERIFIED: cold_storage_spill_test.cpp:226-279] | mirror it with per-**Get** latency for Phase 9 |
| `ReadOptions{deadline, verify}` | documented deadline field on library reads | NOTE: `S3BlockStore::Get` reads only `options.verify` and ignores `deadline` [VERIFIED: S3BlockStore.cpp:170-184] — deadlines must be enforced caller-side (§6.4) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Immediate don't-have + re-warm (recommended) | Thirdparty `graphsync_impl` change: make the posted handler an asio coroutine that awaits the cold fetch with a timer, then sends `RS_FULL_CONTENT` late | Only path to true first-request cold-serve; requires ipfs-lite-cpp surgery + cross-thread `sendResponse` — high risk, against the "without touching libp2p internals" constraint; reject for this phase |
| Second `S3BlockStore` instance (own `OpenMinioS3Client`) for reads | One shared `remote_store_mutex_` serializing drainer Puts + cold Gets | §6.3 — recommend the mutex first (one connection); second instance is the contention fallback |

**Installation:** none — no new packages, no Package Legitimacy Audit needed (per phase contract).

## 1. Responder Path — Verified Mechanics (READ-02 grounding)

### 1.1 How a peer request is served today
[All VERIFIED: thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/graphsync/impl/graphsync_impl.cpp:286-451]

1. `GraphsyncImpl::onRemoteRequest(from, request)` (:286) registers a `StatusHolder` and **posts the entire handling task** onto `*io_context_` (:307). The io_context is the pubsub host context passed at construction (globaldb.cpp:637-643: "Run Graphsync response handling on the executor that owns the pubsub host's stream queues") — `GetAsioContext()` returns `m_context` [VERIFIED: gossip_pubsub.cpp:1283-1286], which one thread runs [VERIFIED: gossip_pubsub.cpp:518].
2. Inside the posted task: if `request_copy.selector.empty()` (SuperGenius requesters always send empty — `RequestNode` passes `{}` [VERIFIED: graphsync_dagsyncer.cpp:140-147]) the responder calls `service->getNode(request_copy.root_cid)` (:374). A `getNode` **failure returns 0** — the comment states: "A block we don't have is 'nothing selected', not a failed request … RS_NOT_FOUND tells it that immediately." (:369-373). Success streams the block via `data_handler` → `network_->addBlockToResponse` per block, then:
3. `select_res.value() > 0` → `status = RS_FULL_CONTENT` (:408) and `network_->sendResponse(...)` (:417) — **sent synchronously, inside the posted task**.
4. `== 0` → `status = RS_NOT_FOUND` (:432), sent only after `reqgenerator_->allStatusesNotFound(request_copy.id)` (:435-446).
5. `select`/`getNode` **error** → `status_holder->status = RS_REQUEST_FAILED` and early `return` — **no response is ever sent** (:396-404). The peer waits out its own timeout ladder. (Non-empty-selector requests hitting a missing link take this path today — unchanged by Phase 9.)

**What the response writer supports:** one terminal status per request after block streaming; `RS_FULL_CONTENT`/`RS_NOT_FOUND` are the only statuses the responder ever sends. `RS_PARTIAL_CONTENT` (21), `RS_TRY_AGAIN` (31) exist in the wire enum [VERIFIED: graphsync.hpp:60-67] but are never emitted by this responder. Sending anything asynchronously from another thread is not exposed through the `Graphsync` interface — the `Network::sendResponse` plumbing is `graphsync_impl`-internal.

### 1.2 The freeze hazard, precisely
[VERIFIED: graphsync_dagsyncer.cpp:549-556] — verbatim:
```
// Not shared_from_this(): graphsync serves incoming requests off this service on the
// libp2p host's io_context, and GraphsyncDAGSyncer::getNode fetches a block it does not
// have from the network, polling for up to two minutes. That pins the host's only
// thread and freezes the whole node. Responders serve what they already hold.
graphsync_->start( dagService_, blockCallback );
```
Phase 9 must preserve this discipline: whatever dag service is handed to `graphsync_->start()` must answer **from local state only, without blocking**.

### 1.3 The timeout ladder (derives D-12's headroom)
| Constant | Value | Where | Effect |
|----------|-------|-------|--------|
| `kRequestActivityTimeoutMs` | `180000` ms (3 min); request killed at 2× | graphsync_impl.hpp:112-115 (verbatim: `constexpr std::chrono::milliseconds kCleanupIntervalMs( 120000 );` / `constexpr std::chrono::milliseconds kRequestActivityTimeoutMs( 180000 ); // 3 minutes`) | the "peer stream timeout" — requester-side activity sweep |
| `kTotalFetchTimeout` | `20 s` | graphsync_dagsyncer.cpp:27 | requester's whole-fetch budget across peers |
| `kInProgressRequestTimeout` | `120 s` | graphsync_dagsyncer.cpp:20 | per-peer IN_PROGRESS give-up |
| `CID_FAILURE_SUPPRESSION` | `4 s` | graphsync_dagsyncer.hpp:158 | per-(peer,cid) re-request suppression after `RecordCIDFailure`; header comment: "must stay below CrdtDatastore's failed-root retry cadence (5s base doubling to a 60s cap)" (:154-156) |
| failed-root retry ladder | 5 s base → 60 s cap | crdt_datastore (per :155 comment) | the peer's own retry of the same root |

**Derived defaults (D-12, recommended in §7.3):** the re-warm budget must complete before the peer's t≈+5 s first retry finds the CID warm ⇒ re-warm deadline ≈ 4 s (aligned with `CID_FAILURE_SUPPRESSION`), comfortably below every outer budget (20 s / 120 s / 180 s).

### 1.4 What the requester does with `RS_NOT_FOUND` (why don't-have is safe)
[VERIFIED: graphsync_dagsyncer.cpp:375-391, 1136-1146] `RS_NOT_FOUND` in the FAILED case is not a connection failure (`IsConnectionFailureStatus` covers only `RS_NO_PEERS`, `RS_CANNOT_CONNECT`, `RS_CONNECTION_ERROR` — :1136-1146), so the requester records a **CID-specific failure** (4 s suppression) and fails over to the next route; when no route succeeds, `getNode` returns `Error::ROUTE_NOT_FOUND` and the CRDT failed-root retry ladder (5 s→60 s) reschedules. **No peer blacklist is written for `RS_NOT_FOUND`** — exactly the honest-degradation D-05 relies on.

## 2. Rehydrate Path Mechanics (SC4)

### 2.1 What "bytes" means — and the re-journal question
The rehydrate write goes through the decorator's `set()`: one call journals block bytes + PendingUpload into `LocalBlockStore` (atomic sync WriteBatch, local disk only) and then writes the hot store [VERIFIED: BlockStoreBackedIpfsDatastore.cpp:49-95]. Re-journaling is **benign and verified idempotent at both tiers**:
- `LocalBlockStore::Put` writes the journal record **only for NEW blocks** — [VERIFIED: LocalBlockStore.cpp:330-365, verbatim: "the journal record is written only for NEW blocks"; `if (!already_present) { batch.Put(impl_->journal_, …, UploadState::PendingUpload); }`], returning `PutOutcome{DurabilityLevel::LocalCommitted, already_present}` (:400). A Local-tier rehydrate hit (block still in the cold dir) creates **no** new PendingUpload.
- After a future Phase-11 eviction (`EvictLocal` removes bytes AND journal record in one batch [VERIFIED: LocalBlockStore.cpp:457-464]), an S3-tier rehydrate writes a fresh PendingUpload; the drainer re-puts to S3 with `createOnly=true`; a re-put of a stored CID "returns the SUCCESS slot with alreadyPresent=true (the adapter absorbs the object store's 412 precondition evidence), and the original bytes are never overwritten" [VERIFIED: S3BlockStore.hpp:70-77]. Converges, no churn. This confirms D-04's "spill re-journals implicitly" is safe by construction.

### 2.2 What the "resolved marker" is in library/store terms
The resolved marker is **`IpfsDatastore::seal` / `is_sealed`** — a TEXT key in the hot RocksDB store, not a library record [VERIFIED: datastore_rocksdb.cpp:53-70, verbatim: `cid_string += "sealed";` … `rocksdb_->put( key_buf, std::move( value_buf ) );`]. The call chain: `markResolved` → `dagService_->markResolved` → `block_service_->seal` [VERIFIED: merkledag_service_impl.cpp:23-27, graphsync_dagsyncer.cpp:800-804]. The decorator forwards `seal`/`is_sealed` hot-only ("Seal markers are TEXT keys in the hot store's namespace - the cold store never sees them" [VERIFIED: BlockStoreBackedIpfsDatastore.cpp:109-119]).

### 2.3 What the rehydrate path must NOT touch (no re-entry storms)
- **Pubsub broadcast**: only `PubSubBroadcasterExt::Broadcast` publishes; it is invoked exclusively from CRDT publish paths — a direct decorator `set()` never reaches it.
- **`AddRoute`**: touched only from `BlockReceivedCallback` link-walking (`graphsync_dagsyncer.cpp:660-676`) and `AddMultiCIDInfo` (pubsub_broadcaster_ext.cpp:616-657). Writing through the datastore seam touches neither.
- **Heads**: `heads_` are updated only by CRDT delta merging (`MergeDataFromDelta` et al.); rehydrate performs no delta merge ⇒ heads unchanged by construction.
- **LRU/`AddCIDBlock`**: peer-received blocks land in `lru_cid_cache_` + routing via `BlockReceivedCallback`; the rehydrate path should at most insert into the LRU (`lru_cid_cache_.add`) when initiated from inside a `GraphsyncDAGSyncer` read so the just-fetched node is returned without a second read — this touches no routing state.

### 2.4 Seal-on-rehydrate — the one nuance the planner must rule on
SC4's letter says the rehydrate path writes "bytes + resolved marker only". Analysis of when the marker may honestly be written:
- The marker's semantic is "this delta's subtree is fully processed" — `TraverseCIDsLinks` **skips** `isResolved` children [VERIFIED: graphsync_dagsyncer.cpp:757-765]. Sealing an *unprocessed* block would make traversal skip it and its delta would never merge — a correctness hazard.
- The cold store only contains blocks this node previously wrote through the seam (its own journal), i.e. previously-processed blocks — EXCEPT the crash window between the decorator's journal Put and the inner hot write (journal has bytes, hot missing, delta unprocessed, marker absent — `set()` failed and CRDT retries). Unconditionally sealing on rehydrate would seal that unprocessed block.
- In Phase 9 there is no eviction, so a hot miss never *removes* an existing marker: the marker is either still in the hot store (normal case — nothing to restore) or was never written (crash window — restoring it would be wrong).
**Recommendation:** Phase 9's rehydrate writes **bytes** (+ optional LRU insert); `seal` is written **only if the hot store already reports `is_sealed` true** — which is a no-op — or, more simply, not at all this phase. The marker-restoration half of SC4 becomes meaningful in Phase 11, where the GC eviction unit evicts "block bytes, resolved marker, and set rows as one unit" (GC-02) and can therefore restore the marker from eviction-time knowledge. This reads SC4's "bytes + resolved marker" as defining the path's *complete write surface* (it may write exactly these two things and nothing else), and is the only reading that is honest in the crash corner. Flag to planner: if the SC4 verification insists on an observed marker write, gate it on prior-resolution evidence available at the call site.

## 3. The `BlockStatus` → Seam Taxonomy Table (SC3)

### 3.1 The library's codes (verbatim, frozen v1.0)
[VERIFIED: thirdparty/sgns-blockstore/include/sgns-blockstore/BlockStatus.hpp:29-55]
```cpp
enum class StatusClass
{
    NotFound,               ///< authoritative absence ONLY
    TemporarilyUnavailable, ///< transport error, outage, timeout - never NotFound
    Corrupt,                ///< bytes do not hash to the requested CID
    Unauthorized,           ///< authentication / permission failure
};
enum class BlockSource
{
    Memory, Local, Remote, Peer, Caller, Unknown,
};
```
Plus the envelope rule: "Non-authoritative conditions (transport, outage, timeout) are TemporarilyUnavailable and must NEVER be surfaced as NotFound - an authoritative miss is the only legitimate NotFound" (BlockStatus.hpp:22-27). `NotFound` rides the **error slot** (an authoritative miss is a FAILURE value; BlockStore.hpp:32-36). Out-of-set multihash CIDs **throw** `std::invalid_argument` at entry (programmer-error taxonomy; BlockStore.hpp:46-56; Phase-6 widened the accepted set to include blake2b-256 — the throw remains for out-of-set hashes, and the Phase-8 decorator already catches it, BlockStoreBackedIpfsDatastore.cpp:83-92).

### 3.2 The mapping table at the seam
| BlockStatus (code + source) | Chain behavior | Final seam classification | Honesty rules |
|---|---|---|---|
| `NotFound + Local` (LocalBlockStore miss) | **expected, non-terminal** — continue to S3 tier | — (chain continues) | a Local miss is the common case (block only in S3); it is NOT the seam's NotFound |
| `NotFound + Remote` (S3 miss) | cold chain exhausted → continue to peers (D-01) | NotFound only if peers also report authoritative absence | definitive-absence-everywhere = the ONLY NotFound (SC1) |
| `TemporarilyUnavailable + Local` (local RocksDB IO error) | log + count; continue to S3 tier (D-03 fall-through) | if all sources fail transport-shaped: seam surfaces **TemporarilyUnavailable** | never map to NotFound; never blacklist; never `RecordCIDFailure` |
| `TemporarilyUnavailable + Remote` (s3d down / network fault) | log + count; continue to peers (D-03) | as above | the SC1 fault test's headline case |
| `Corrupt + Local` or `Corrupt + Remote` (CID verify failed) | **stop the chain for that tier**; log loud with source | seam surfaces **Corrupt with source attribution** (`Corrupt(local)` vs `Corrupt(remote)` in the log line) | do NOT fall through silently; do NOT retry-loop |
| `Unauthorized + Local/Remote` | stop; log | distinct failure class surfaced as-is (not NotFound, not TemporarilyUnavailable) | credentials never appear in `message` (BlockStatus.hpp:63-66) |
| `Peer + *`, `Caller + *`, `Memory + *` | not producible by the cold tiers | — | `Peer` exists for peer-sourced data; cold chain never emits it |

**Where `TemporarilyUnavailable` surfaces concretely:** `GraphsyncDAGSyncer::Error` today has no such member [VERIFIED: graphsync_dagsyncer.hpp:47-55 — verbatim: `CID_NOT_FOUND = 0, ROUTE_NOT_FOUND, PEER_BLACKLISTED, TIMED_OUT, DAGSYNCER_NOT_STARTED, GRAPHSYNC_IS_NULL, HOST_IS_NULL`]. Recommended mechanism (planner finalizes): an additive enum value (e.g. `COLD_STORAGE_TEMPORARILY_UNAVAILABLE`) returned by the chain when the failure is transport-shaped, so `GetNodeWithoutRequest`'s failure slot stops conflating "not found" with "cold tier unreachable". The library status detail (`code`/`source`/`message`) rides the rate-limited log line regardless.

### 3.3 Honesty rules vs the existing failure-recording call sites
The `BlackListPeer`/`RecordCIDFailure` call sites all live **inside the peer loop or peer-response handling** [VERIFIED: graphsync_dagsyncer.cpp:262-267 (request setup failure), :313-317 (request-state lost), :359-363 (COMPLETED without block), :375-391 (FAILED), :396-420 (IN_PROGRESS timeouts)]. Because the cold chain runs **before** `GetRouteKeys`/the peer loop (§4, D-01) and inside `GetNodeWithoutRequest` (no peer involved), cold-tier failures cannot reach them by construction — the rule to test (SC3/Wave 3) is that this stays true: with `S3FaultKind::Unavailable` scripted on Get, a routed `getNode` must still attempt the peer, write no blacklist entry, and write no per-(peer,cid) failure record.

### 3.4 Log wording constraint (discretion)
Cold-tier failures and peer failures must be distinguishable in logs. Recommended line shapes (extending the Phase-8 rate-limited precedent at BlockStoreBackedIpfsDatastore.cpp:67 / ColdStorageStack logging):
- `"cold read: local tier miss, cid=…"` (trace), `"cold read: s3 tier unavailable (code {}), falling through to peers"` (warn, rate-limited, `BlockStatus.code` only, no CID stringification on hot paths — Phase-8 redaction-by-omission pattern)
- `"cold read: CID verify failed at {local|remote} tier"` — the Corrupt attribution line
- Never log endpoint/credential values (Phase-7 posture; S3Client.hpp:68-69 "credentials - never logged").

## 4. Where the Fallback Chain Lands (discretion — audited)

### 4.1 Call-site audit (all VERIFIED this session)
| Call site | Path | Cold-chain effect |
|---|---|---|
| `GraphsyncDAGSyncer::getNode` :205-227 | GrabCIDBlock → `GetNodeFromMerkleDAG` → **peer loop** | chain must insert after the hot miss, **before** `GetRouteKeys` — this is D-01's "cold before peers" for the CRDT worker fetch path (runs on the CRDT DAG worker; a bounded synchronous cold fetch here is within existing tolerance — peer fetches already block this worker up to `kTotalFetchTimeout` = 20 s) |
| `GraphsyncDAGSyncer::GetNodeWithoutRequest` :519-528 | `GetNodeFromMerkleDAG` → GrabCIDBlock | chain appends after both — serves `crdt_datastore.cpp:1846` (stalled deltas), `:1938` (PrintDAGRec), `:2277`, and `TraverseCIDsLinks` :794 |
| `GraphsyncDAGSyncer::GetNodeFromMerkleDAG` :1006-1010 | `dagService_->getNode` **under `dagMutex_`** | DO NOT put the chain here — `dagMutex_` is the publish mutex (`addNode` :189-191); remote I/O under it stalls consensus publishes (Phase-8 discipline) |
| decorator `get()` :120-125 | pure forward today; called (transitively) by BOTH `GetNodeFromMerkleDAG` and the **responder** (`graphsync_impl.cpp:374` → `MerkleDagServiceImpl::getNode` → `block_service_->get`, merkledag_service_impl.cpp:29-33) | DO NOT put the synchronous chain here — it would leak inline remote I/O onto the single-thread responder (SC2 violation) |
| responder (Wave 2) | `graphsync_->start(dagService_, …)` :556 | gets the **wrapper** dag service (§5), not the raw `dagService_` |

### 4.2 Recommendation
**Both `GetNodeWithoutRequest` AND `getNode` (pre-peer), implemented as ONE private `GraphsyncDAGSyncer` helper** (e.g. `FetchNodeFromColdStorage(cid)`), backed by the injected cold-read hook. The decorator's `get()` stays a pure forward. Rationale:
- one chain implementation serves every local read path and the pre-peer leg (D-01 ordering for `getNode`);
- the chain runs OUTSIDE `dagMutex_` (called after `GetNodeFromMerkleDAG` returned failure and released it) — publishes never wait on s3d;
- the responder is untouched by the synchronous chain (its cold-serve is the Wave-2 async mechanism);
- `GetNodeWithoutRequest` cold-awareness + D-08 interplay: pubsub-received CIDs (`AddMultiCIDInfo`, pubsub_broadcaster_ext.cpp:632) call `HasBlock` first — with the gated Local-tier `Has` check, a CID present in the cold dir reports held ⇒ no route added ⇒ no peer fetch; the cold chain rehydrates on demand when something actually reads it. Correct and freeze-safe.
**Hook injection:** `GraphsyncDAGSyncer` is constructed at exactly ONE site (`globaldb.cpp:643` [VERIFIED — the only `make_shared<GraphsyncDAGSyncer>` in `SuperGenius/src`; other hits are `static_pointer_cast` downcasts in GeniusAccount.cpp:728, Blockchain.cpp:397, ValidatorRegistry.cpp:285, crdt_datastore.cpp:1238/1300]). Add an optional constructor parameter (null when cold storage disabled ⇒ byte-identical behavior). The interface must live in an **ungated header** with no sgns-blockstore types (CID + Buffer + a std error payload only), implemented in a gated TU — same boundary discipline as the `ColdStorageStack` bridges.

## 5. Responder Negative-Response Semantics (discretion — confirmed)

What the graphsync layer supports, verified (§1.1): the responder can send, synchronously at the end of the posted task, exactly `RS_FULL_CONTENT` (blocks streamed) or `RS_NOT_FOUND` (nothing selected). It cannot send `RS_TRY_AGAIN`/`RS_PARTIAL_CONTENT` (never emitted by this implementation), cannot send anything after the posted task returns, and cannot send from another thread without thirdparty surgery. A `select`/`getNode` error sends NOTHING (peer waits out its own ladder) — worse than don't-have.

**Therefore D-05's deadline-expiry negative completion maps to `RS_NOT_FOUND` now** (immediately — the "deadline" governs the background re-warm, §6.4), with these verified safety properties on the requesting peer: no blacklist write (`RS_NOT_FOUND` is not a connection failure, §1.4), a 4 s per-(peer,cid) suppression, and the 5 s→60 s failed-root retry ladder that will find the re-warmed block hot. The peer-facing contract is unchanged from today's local-only responder for a genuinely-absent CID — the only new behavior is that the block becomes hot milliseconds-to-seconds later, so retries succeed.

## 6. Executor / Deadline Design (READ-02 — the novel part)

### 6.1 Shape: single-thread bounded executor, queue-bounded, per-CID coalescing
- **Thread pool: ONE dedicated `std::thread`** (the re-warm worker). Rationale: re-warms are rare (only responder misses on CIDs the peer retry ladder will re-request); S3 Get latencies are 10–300 ms-class; and a single worker keeps library remote-store access simple (§6.3). SC2's "bounded dedicated executor" is satisfied by (worker count × queue bound).
- **Queue bound:** compile-time `kMaxRewarmQueueDepth` (recommend 64). Overflow policy: drop + count + rate-limited warn (the next request for that CID re-enqueues — D-07 makes drops cheap). NEVER block the enqueuer (the responder thread) — enqueue is a try-operation.
- **Never the responder's inline path:** the wrapper dag service's `getNode`/`select` NEVER waits on the executor — it delegates the hot read and returns (§5).
- **Never `io_`, never the pubsub asio context:** Phase-8 D-10 pattern — own `std::thread`, cv-based wake, explicit `Stop()` (flag → notify → bounded grace → unconditional join), mirroring `ColdStorageManager`'s lifecycle [VERIFIED: ColdStorageManager.hpp:26-45, 137-152].

### 6.2 The responder wrapper (how it integrates without touching libp2p)
`GraphsyncDAGSyncer::StartSync()` currently passes `dagService_` to `graphsync_->start` (:556). Phase 9 hands it a **wrapper `MerkleDagService`** (e.g. `ColdServeDagService`, ungated TU, owned by the DAGSyncer or injected from globaldb):
- `getNode(cid)`: delegate to inner `dagService_->getNode`; on success return; on failure, if the cold-read hook is enabled → `hook->EnqueueRewarm(cid)` (try-enqueue, per-CID coalesced) → return the failure (⇒ responder maps to `RS_NOT_FOUND`, §1.1). If disabled → return the failure unchanged (byte-identical).
- `select(...)`: delegate whole-call; on inner error return the error (today's behavior for non-empty selectors — `RS_REQUEST_FAILED`, no response; no regression).
- `addNode`/`removeNode`/`markResolved`/`isResolved`/`fetchGraph*`: pure delegation.
The wrapper holds only interface types ⇒ it compiles ungated; the cold-read hook behind it is the gated implementation.

### 6.3 Remote-store concurrency (a real trap)
The library's thread-safety contract is single-threaded-use per backend: `LocalBlockStore` ("single-threaded use - no internal synchronization is promised", LocalBlockStore.hpp:117-119), `S3BlockStore` ("single-threaded use", S3BlockStore.hpp:34-36), and `MinioS3Client` ("concurrent-call guarantees are out of the Phase-3 contract", MinioS3Client.hpp:31-34). Today only the drainer thread touches `remote_block_store_`. Phase 9 adds the re-warm worker calling `S3BlockStore::Get` concurrently with drainer `Put`s. **Recommended: a dedicated `remote_store_mutex_` serializing ALL `S3BlockStore` calls** (drainer takes it per Put-item in its already-unlocked-from-cold-store-mutex remote phase; the re-warm worker takes it around `Get`). Cost is negligible relative to S3 RTTs. Fallback if the latency budget shows contention: a second `S3BlockStore` over its own `OpenMinioS3Client` (construction is zero-network-I/O, Phase-6 D-06) dedicated to reads — zero shared state, one extra lazy connection. `LocalBlockStore` access (chain's Local tier, `Has` check, rehydrate journal write) continues under the existing `cold_store_mutex_` — every such op is local RocksDB (microseconds), freeze-safe.

### 6.4 Deadline semantics (what a deadline CAN bound here)
`S3BlockStore::Get` ignores `ReadOptions::deadline` (only `options.verify` is read; S3BlockStore.cpp:170-184 — "backends that can honor it do", and this one doesn't). A hung blocking Get pins the worker thread until the SDK's own HTTP timeout returns. Therefore:
- the **re-warm budget** (recommend 4 s, §7.3) bounds *scheduling and waiting*: a task found past-deadline before starting is skipped; a waiter past deadline detaches (D-07 attach semantics); the underlying op's completion is bounded by the executor bound itself (1 worker ⇒ at most one pinned thread ⇒ the node's freeze-safety never depends on the deadline firing);
- the **serve deadline** concept from SC2 materializes as: first answer is immediate don't-have; "deadline below the peer stream timeout" is honored by the re-warm budget (4 s ≪ 20 s ≪ 180 s) so the retry ladder converges. The SC2 latency-budget benchmark (§10.2) documents exactly this posture as the built-in default per D-12.
- minio-cpp's own per-op HTTP timeout is the terminal backstop for a hung Get — value not pinned down this session [ASSUMED] — see Assumptions Log.

### 6.5 Shutdown / lifecycle join ordering (D-10/D-11 pattern)
Current verified order in `GlobalDB::ShutdownNow()` (globaldb.cpp:396-424): `StopBackupLoop()` → `StopColdStorageManager()` (comment: "D-11 (v1.1 Phase 8): the drainer stops IMMEDIATELY AFTER the backup loop and BEFORE the lifecycle_mutex_ teardown block - bounded grace then join while the stores still live") → lifecycle-mutex teardown → `broadcaster->Stop()` → `crdt_datastore->CancelAndCloseNow()`. **Slot the cold-read/serve service stop inside/next to `StopColdStorageManager()`** — either extend `ColdStorageManager` (it already owns both stores + mutex) or add a sibling bridge (`StopColdReadService()`) called between `StopBackupLoop()` and datastore teardown, BEFORE broadcaster/crdt teardown so in-flight re-warms finish their decorator writes while the stores still live. Stop shape: flag → notify → bounded grace (Phase-8 used `kShutdownGraceWindow{5000}` ms, ColdStorageManager.hpp:128-130) → unconditional join; queued-but-unstarted re-warms are abandoned (the hot store simply stays cold; next startup's reads re-fetch). Recommended grace: reuse 5 s. Also note `StopSync()` (graphsync stop) happens later, at CRDT datastore teardown (`crdt_datastore.cpp:621`), so the responder stops asking AFTER the re-warm service has drained — correct order.

## 7. READ-01 Chain Mechanics (the local read path)

### 7.1 The chain, concretely
1. Hot: existing `GrabCIDBlock` (LRU) → `GetNodeFromMerkleDAG` (hot RocksDB) — unchanged.
2. **Local tier**: under `cold_store_mutex_`, `LocalBlockStore::Get(cid)` — internally CID-verifies (`Get` "re-verifying bytes against the CID unless ReadOptions::verify == false", BlockStore.hpp:96-102). Hit → rehydrate (§2) → return node.
3. **S3 tier**: `S3BlockStore::Get(cid)` under `remote_store_mutex_` (§6.3) — CID-verifies internally; corruption surfaces as `Corrupt + Remote` (the fake's `SetFlipBytesForKey` is the test seam for exactly this). Hit → rehydrate → return.
4. **Peers** (only in `getNode`'s flow): existing route loop, with cold transport failures logged + counted per D-03 before falling through.
5. Classification per §3.2; `TemporarilyUnavailable` never exits as `CID_NOT_FOUND`.

### 7.2 Threading of the chain
`GetNodeWithoutRequest`/`getNode` run on the CRDT DAG worker(s) (the codebase documents "the (single) CRDT DAG worker" for FetchNodes, graphsync_dagsyncer.cpp:23-26). A synchronous cold fetch there blocks CRDT operations for its duration — acceptable and bounded: peer fetches already occupy this worker up to 20 s (`kTotalFetchTimeout`); a cold fetch is strictly cheaper than the peer round trip it usually eliminates. The Unavailable fault fails fast (no hang) — D-03's fall-through keeps the worker moving.

### 7.3 Recommended compile-time defaults (D-12)
| Default | Value | Derivation |
|---|---|---|
| Re-warm budget (per task) | `4 s` | must complete before the peer's first failed-root retry (5 s base) and matches `CID_FAILURE_SUPPRESSION` (4 s) so the retry window and the warm-completion window align; ≪ requester's 20 s total budget |
| Executor size | `1` thread | §6.1; re-warms are rare; keeps remote-store serialization trivial |
| Queue bound | `64` | bounds re-warm memory; overflow drops are re-enqueued by the next request (D-07) |
| Shutdown grace for re-warm join | `5 s` | Phase-8 `kShutdownGraceWindow` parity |
| (documented, not a knob) serve posture | immediate don't-have + re-warm | §5/§6.4 — the measured latency budget (§10.2) is the evidence file |
All become named `static constexpr` constants in the gated TU, documented in the SC2 benchmark's evidence header — nothing enters `crdt_config.json` (D-12).

## 8. In-flight Coalescing (D-07 + read-path discretion)

### 8.1 The minimal mechanism
A `std::map<CID, RewarmState>` + mutex inside the cold-read service. `RewarmState` = {enqueued-or-running flag, completion epoch}. `EnqueueRewarm(cid)`: under the mutex — if an entry exists, return (attached: nothing to do — the peer's *next* request finds it hot, which is the whole point); else insert + try-enqueue to the bounded queue (on queue-full: erase + drop + count). Worker: run fetch → rehydrate → under mutex erase the entry (+ notify a generation counter). This is exactly "one in-flight re-warm per CID; concurrent deadline-missed requests … attach or find it hot" — no futures, no waiter lists, because nobody waits (§5).

### 8.2 What NOT to build
No shared_future fan-out, no per-waiter callbacks — the responder never blocks on the result, so there is nobody to wake. The map is dedup metadata, not a promise infrastructure.

### 8.3 Read-path coalescing (discretion — recommendation: none)
Concurrent LOCAL reads of the same cold CID duplicate the S3 Get (idempotent read, harmless; the decorator `set()` re-write is idempotent per §2.1). The deferred list explicitly parks read-path coalescing unless SC2 evidence shows stampede. **Recommendation: ship without it; the SC2 benchmark should nonetheless record concurrent-miss behavior so Phase-12 hardening has data.** One cheap exception worth taking: a local read MAY consult the re-warm map to learn "already being fetched — skip enqueue" — read-only, no waiting.

## 9. HasBlock Cold-Awareness (D-08/D-09)

`HasBlock` today: `GetNodeFromMerkleDAG(cid) || GrabCIDBlock(cid)` [VERIFIED: graphsync_dagsyncer.cpp:511-517]. Add, **gated on the cold-read hook being present**: after both miss → `hook->HasInLocalColdStore(cid)` (LocalBlockStore::Has under `cold_store_mutex_`; `Has` contract: "true/false as SUCCESS values; under a non-authoritative failure a BlockStatus FAILURE is returned - NEVER the value false", BlockStore.hpp:110-116 — map a failure to `false` + a rate-limited log, since `HasBlock`'s contract is a bool and the freeze-sensitive callers must never block or throw). NEVER S3. `LocalBlockStore::Has` is a RocksDB point lookup — microseconds under a mutex that is only ever held for local-disk ops (drainer's split-phase contract) — freeze-proof for the pubsub-thread callers (pubsub_broadcaster_ext.cpp:632; crdt_datastore.cpp:706 head processing, :1881 `GetJobStatus`). SC3's "retrievable before deadline" half is honored by the fetch paths (§4, §7), not by `HasBlock`. Disabled deployments: hook null ⇒ `HasBlock` byte-identical (D-09/Phase-7 SC2 bar).

## 10. Testing Design (SC1/SC2/SC5 — hermetic, Tier-1)

### 10.1 Taxonomy-honesty suite (Wave 3, READ-01 evidence)
Pattern: the Phase-8 spill test's direct-construction harness (`cold_storage_spill_test.cpp` constructs decorator + manager + `InMemoryS3Client` directly; include path reaches the NOT-installed fake header via `target_include_directories(... thirdparty/sgns-blockstore/src)` [VERIFIED: test/src/crdt/CMakeLists.txt:105-113]). Phase 9 needs the cold-read hook + a thin fake DAGSyncer-adjacent harness (or construct the real `GraphsyncDAGSyncer` without a host where possible — its constructor needs graphsync/host, so prefer testing the hook + chain helper through the seam they actually expose; the planner picks the exact cut):
- **no-NotFound-escape**: script `S3FaultKind::Unavailable` on Get (op-level `SetFault(S3Op::Get, …)` [VERIFIED: InMemoryS3Client.hpp:75-79]) with the block absent everywhere ⇒ chain result must be `TemporarilyUnavailable`-shaped, never `CID_NOT_FOUND`;
- **definitive absence**: block absent in both cold tiers + no route ⇒ `NotFound`;
- **Corrupt attribution**: `SetFlipBytesForKey(key, true)` (success-slot byte flip; "S3BlockStore's CID verification is the detector", InMemoryS3Client.hpp:92-99) ⇒ `Corrupt` attributed to the remote tier; same via `FaultKind::CorruptData` on `LocalBlockStore` for the local tier;
- **no-blacklist/no-CID-failure**: with a route registered and s3d Unavailable, the peer attempt still happens; assert no blacklist/CID-failure side effects (behavioral: a second `getNode` still walks the peer; or a test-only probe mirroring `SetBlacklistBackoffTimeoutForTest` precedent [VERIFIED: graphsync_dagsyncer.hpp:120-128, "Test-only configuration seam … No production caller may invoke this method"]);
- **rehydrate silence**: spy `IpfsDatastore` inner + fake broadcaster ⇒ after a cold fetch exactly `set` (+optional `seal` per §2.4) fire; zero broadcast, zero route additions, heads fixture unchanged.

### 10.2 SC2 latency-budget benchmark + freeze regression (hermetic)
- **Latency injection**: mirror `LatencyInjectingS3Client` (cold_storage_spill_test.cpp:226-279 — a test-local `S3Client` subclass sleeping per-op then delegating; the fake has no native latency hook) with per-**Get** latency. Measure: (a) READ-01 inline cold-fetch p50/p95 at injected 10/50/200/500 ms; (b) time-to-warm after a responder miss (must be < the 4 s budget at 500 ms injected latency); (c) hot-hit serve latency while the re-warm queue is saturated — proving the wrapper never waits on the executor. Same discipline as Phase-8 SC1: never compare ON-vs-OFF builds — compare distributions under identical injected latency (08-CONTEXT: "drainer paused vs running under injected latency — never ON-vs-OFF").
- **Freeze regression**: with s3d Get faulted Unavailable (fail-fast) AND latency-injected (slow), a hot CID served through the responder wrapper must return within a tight bound (e.g. < 50 ms) while N cold misses are in flight — asserting non-blocking by measurement, no real libp2p needed at the wrapper level. For a whole-node-level E2E, the existing two-GlobalDB harness (`test/src/graphsync/pubsub_graphsync_test.cpp` — real pubsub + graphsync over in-process libp2p hosts) is the model; the planner should weigh its cost (full `crdt_globaldb` + libp2p link) against the wrapper-level proof — recommend wrapper-level for Tier-1, node-level optional.

### 10.3 Tier-1 registration mechanics
Follow the Phase-8 pattern exactly: `addtest(cold_storage_fallback_test …)` under `if(SGNS_COLD_STORAGE)` + `target_link_libraries(… sgns-blockstore::sgns-blockstore crdt_globaldb)` + the relative include dir for the fake header + `set_tests_properties(… PROPERTIES LABELS "Tier1")` — `addtest()` has no LABELS support so `set_tests_properties` is mandatory [VERIFIED: test/src/crdt/CMakeLists.txt:50-54, 98-113]. The lane stays non-empty on OFF builds via the unconditional config-gate test (:79-88). CI posture unchanged from the Phase-7 verdict (ON-lane blocked-on-thirdparty-release-cut; local `ctest -L Tier1 --no-tests=error` is the fail-closed bar).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CID verification on fetch | custom hash-compare | library `Get` (verifies internally, BlockStore.hpp:96-102) | CORE-04: verification can never be compiled out |
| Failure taxonomy | ad-hoc error strings | `BlockStatus{StatusClass, BlockSource}` | first-class, assertable, carries source attribution |
| Fault injection | hand-rolled flags | `SetFault`/`SetFaultForKey`/`SetFlipBytesForKey` + `FaultKind` | shipped kit; drives the honesty suite deterministically |
| Async executor | asio io_context for the re-warm worker | own `std::thread` + cv + bounded queue (backup-loop/drainer pattern) | Phase-8 D-10: never `io_`, never the pubsub context; twice-proven lifecycle |
| Latency injection | sleeps in production code | test-local `S3Client` decorator (LatencyInjecting pattern) | keeps production seam clean; Phase-8 precedent |
| Late graphsync responses | cross-thread `sendResponse` from the executor | don't-have now + re-warm (D-05) | `Network::sendResponse` is graphsync_impl-internal; thirdparty surgery rejected (§5) |

**Key insight:** every mechanism below the policy line (verification, taxonomy, journaling, fault kit, fakes) is a frozen shipped contract; Phase 9's surface is chain policy, the executor, the wrapper, the hook, and tests.

## Common Pitfalls

### Pitfall 1: Putting the chain in the decorator's `get()`
**What goes wrong:** remote S3 I/O runs under `dagMutex_` (via `GetNodeFromMerkleDAG`) AND inline on the single-thread responder (via `graphsync_impl.cpp:374`). **Why:** the decorator is the one object both paths share. **Avoid:** chain in `GraphsyncDAGSyncer` after the hot miss, outside the mutex (§4). **Warning signs:** consensus publish latency correlating with s3d state; freeze regression failing on outage cases.

### Pitfall 2: Any wait in the responder wrapper
**What goes wrong:** even a "bounded 200 ms" condvar wait pins the pubsub host's only thread; concurrent cold misses serialize into multi-second stalls — the exact whole-node freeze SC2's regression test exists to catch. **Avoid:** wrapper delegates and returns; the executor does the fetching (§6.2). **Warning signs:** hot-hit serve latency growing with in-flight cold misses.

### Pitfall 3: Concurrent `S3BlockStore` use
**What goes wrong:** re-warm worker `Get` racing drainer `Put` on one `MinioS3Client` — "concurrent-call guarantees are out of the Phase-3 contract" (MinioS3Client.hpp:31-34). **Avoid:** `remote_store_mutex_` (or a second read-dedicated store instance) (§6.3). **Warning signs:** rare crashes/UB under drain+read overlap in the fault suite.

### Pitfall 4: Cold transport failure surfacing as NotFound
**What goes wrong:** s3d blip misread as authoritative absence ⇒ wrong `NotFound` escapes the seam, poisoning higher-layer retry decisions; or worse, `RecordCIDFailure`/blacklist writes blaming peers. **Avoid:** §3.2 table + the no-NotFound-escape fault test. **Warning signs:** any `CID_NOT_FOUND` returned while `S3FaultKind::Unavailable` is scripted.

### Pitfall 5: Sealing unprocessed blocks on rehydrate
**What goes wrong:** `TraverseCIDsLinks` skips `isResolved` children (graphsync_dagsyncer.cpp:757-765); a marker written for a never-processed block (crash-window journal-only block) makes traversal skip its delta permanently. **Avoid:** §2.4 — bytes only in Phase 9; marker restoration belongs to Phase 11's eviction unit. **Warning signs:** deltas that never merge after a restore.

### Pitfall 6: `HasBlock` doing anything remote
**What goes wrong:** the pubsub-thread callers (pubsub_broadcaster_ext.cpp:632; crdt_datastore.cpp:706) block on S3 ⇒ receive-path freeze. **Avoid:** gated Local-tier `Has` only (D-08/D-09, §9). **Warning signs:** pubsub delivery latency spikes when cold reads miss.

### Pitfall 7: Expecting `ReadOptions::deadline` to bound S3 ops
**What goes wrong:** a design that relies on the library aborting a hung Get at the deadline — it doesn't (S3BlockStore.cpp:170-184 ignores it). **Avoid:** executor bound is the safety mechanism; deadlines bound scheduling/waiting only (§6.4). **Warning signs:** any test that hangs rather than fails when a Get never returns — the fake's faults all fail fast, so hung-op coverage needs the latency wrapper with a very large value, or is simply out of hermetic reach (document it).

### Pitfall 8: Breaking the disabled bar
**What goes wrong:** any ungated reference to cold-read types, or a non-null-by-default hook, changes OFF-build behavior. **Avoid:** hook injected only when `cold_storage_options_.enabled`; ungated interface header; gated TU; the Phase-7/8 stub pattern. **Warning signs:** OFF-build binary diff; config-gate test failures.

## Code Examples

### The responder wrapper (shape — ungated TU)
```cpp
// Verified against: graphsync_dagsyncer.cpp:549-556 (start/dagService contract),
// graphsync_impl.cpp:368-385 (empty-selector getNode -> 0 -> RS_NOT_FOUND),
// merkledag_service.hpp:33-46 (interface incl. markResolved/isResolved).
class ColdServeDagService final : public ipfs_lite::ipfs::merkledag::MerkleDagService
{
public:
    ColdServeDagService( std::shared_ptr<MerkleDagService> inner, ColdReadFallback *hook )
        : inner_( std::move( inner ) ), hook_( hook )
    {
    }
    // getNode: hot-first delegation; on miss, enqueue the coalesced re-warm and
    // fail FAST — never wait (single-thread pubsub context; SC2).
    IPFS::outcome::result<std::shared_ptr<ipfs_lite::ipld::IPLDNode>> getNode( const CID &cid ) const override
    {
        auto node = inner_->getNode( cid );
        if ( !node && hook_ != nullptr )
        {
            (void) hook_->EnqueueRewarm( cid ); // try-enqueue, bounded queue, per-CID dedup
        }
        return node; // failure => responder answers RS_NOT_FOUND (honest don't-have)
    }
    // select/addNode/removeNode/markResolved/isResolved: pure delegation (select
    // errors keep today's RS_REQUEST_FAILED-no-response shape; no regression).
private:
    std::shared_ptr<MerkleDagService> inner_;
    ColdReadFallback                 *hook_;
};
```

### The chain slot in `getNode` (D-01 ordering)
```cpp
// Verified against: graphsync_dagsyncer.cpp:205-227 (current flow) — insert the
// cold leg AFTER the hot miss and BEFORE GetRouteKeys:
//   GrabCIDBlock -> GetNodeFromMerkleDAG -> [NEW: FetchNodeFromColdStorage] -> peers
// and in GetNodeWithoutRequest (:519-528) after GrabCIDBlock. Runs OUTSIDE dagMutex_
// (both hot helpers have returned and released it) — publishes never wait on s3d.
```

### The hook interface (ungated header — no library types cross)
```cpp
// Modeled on the ColdStorageStack bridge discipline (ColdStorageStack.hpp:15-22).
// Error payload carries the taxonomy, not the library type:
struct ColdReadStatus { enum Class { NotFound, TemporarilyUnavailable, Corrupt, Unauthorized } cls; bool fromRemoteTier; };
class ColdReadFallback
{
public:
    virtual ~ColdReadFallback() = default;
    virtual ColdReadStatus Get( const CID &cid, sgns::common::Buffer &out ) = 0;      // Local tier then S3 tier, CID-verified
    virtual bool           HasLocalCold( const CID &cid ) = 0;                        // LocalBlockStore::Has ONLY (D-08)
    virtual bool           EnqueueRewarm( const CID &cid ) = 0;                       // coalesced, bounded, never blocks
    virtual void           Rehydrate( const CID &cid, const sgns::common::Buffer &bytes ) = 0; // decorator set (+seal per §2.4)
};
```

### Tier-1 registration (verbatim pattern from Phase 8)
```cmake
# Verified: SuperGenius/test/src/crdt/CMakeLists.txt:98-113
if(SGNS_COLD_STORAGE)
addtest(cold_storage_fallback_test
    cold_storage_fallback_test.cpp
)
target_link_libraries(cold_storage_fallback_test
    sgns-blockstore::sgns-blockstore
    crdt_globaldb
)
target_include_directories(cold_storage_fallback_test PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../../../../thirdparty/sgns-blockstore/src"
)
set_tests_properties(cold_storage_fallback_test PROPERTIES LABELS "Tier1")
endif()
```

## State of the Art (in-codebase drift watch)

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Responder could fetch from network (freeze) | "Responders serve what they already hold" (local-only) | pre-v1.1 comment, graphsync_dagsyncer.cpp:549-556 | Phase 9's async cold-serve is the FIRST sanctioned non-local serve; it must preserve the non-blocking discipline via the wrapper + executor |
| Missing block ⇒ silent no-response (`RS_REQUEST_FAILED` internal) | empty-selector miss ⇒ `RS_NOT_FOUND` sent | ipfs-lite-cpp patch (comment at graphsync_impl.cpp:369-373) | the honest don't-have D-05 relies on exists at the wire level |
| Decorator `get()` pure forward | (this phase) chain in DAGSyncer, decorator `get()` stays forward | — | keeps responder + publish mutex clean |

**Deprecated/outdated:** none obsolete this phase; note `BlockStore.hpp:46-56`'s sha256-only comment text predates the Phase-6 blake2b widening — the accepted set is wider; out-of-set multihashes still throw (decorator already catches, BlockStoreBackedIpfsDatastore.cpp:83-92).

## Security Domain (ASVS L1 — `security_enforcement: true`)

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no (no new auth surface) | — |
| V3 Session Management | no | — |
| V4 Access Control | marginal — S3 `Unauthorized` class | surfaced distinctly through the §3.2 table; never as NotFound |
| V5 Input Validation | yes | CID bytes validated by library entry (throws on out-of-set multihash — caught at the seam, Phase-8 precedent); fetched bytes CID-verified by library `Get` (CORE-04, cannot be disabled) |
| V6 Cryptography | yes, inherited | CID verification (blake2b-256/sha-256) is the integrity control on every cold fetch — never hand-rolled, never bypassed (`verify=false` must NOT be used by the chain) |
| V9/V10 Logging | yes | credential redaction by omission (Phase-7/8 posture; BlockStatus.hpp:63-66); cold-vs-peer failure distinguishability (§3.4) |

| Threat Pattern | STRIDE | Standard Mitigation |
|----------------|--------|---------------------|
| Corrupted cold bytes served as valid | Tampering | library CID-verify at Get; `Corrupt + source` classification; never re-broadcast (SC4 silence) |
| Restore re-entry storm (attacker-triggered cold misses) | DoS | bounded executor + queue cap + per-CID coalescing (D-07) + immediate don't-have (D-05) |
| Responder pin via slow/hung s3d | DoS | wrapper never blocks; single io_context thread never touches S3 (§1, §6.2) |
| Credential leakage through logs | Information Disclosure | BlockStatus message-only logging; no endpoint/keys in lines (§3.4) |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | minio-cpp applies its own per-op HTTP/connect timeout so a hung `Get` eventually returns (value unpinned) | §6.4, P7 | re-warm worker pinned indefinitely; mitigated by 1-thread bound (node stays freeze-safe) but that CID never re-warms; could justify the second-store-instance fallback |
| A2 | Two `GlobalDB` instances in one process share one `RequestIdGenerator` scope such that `allStatusesNotFound` gates multi-instance NOT_FOUND correctly for single-instance deployments (single-instance — the normal case — is trivially correct; multi-instance path read, not runtime-verified) | §1.1 | none for Phase 9 (single GlobalDB per process is the shipped topology; multi-node tests use separate processes/hosts) |
| A3 | `crdt_datastore` failed-root retry constants are 5 s base doubling to a 60 s cap (taken verbatim from the `CID_FAILURE_SUPPRESSION` comment at graphsync_dagsyncer.hpp:154-156; the crdt_datastore constants themselves were not re-read this session) | §1.3, §7.3 | re-warm budget of 4 s might miss the true first-retry instant; retry ladder still converges on a later tick — low risk |
| A4 | Peer-received blocks reach the decorator via `ProcessJobIteration → addNode` (so the cold store contains all processed blocks, local history only) — inferred from `crdt_datastore.cpp:1029` (`dagSyncer_->addNode( node_to_process )`) without tracing every sync path | §2.4 | seal-on-rehydrate reasoning shifts; recommendation (bytes-only this phase) is safe either way |

All other claims in this document are `[VERIFIED: file:line]` against sources read this session.

## Open Questions

1. **Seal-on-rehydrate ruling** — §2.4 recommends bytes-only for Phase 9 with marker restoration deferred to Phase 11's eviction unit. Does the SC4 verification accept "the path *may* write exactly bytes+marker" with the marker branch exercised only when prior resolution is known? (Planner/verifier call; hazard evidence documented.)
2. **Freeze-regression test depth** — wrapper-level measurement (recommended, cheap, hermetic) vs full two-GlobalDB node-level E2E on the `pubsub_graphsync_test` harness (stronger, costly, links the world). Recommend wrapper-level Tier-1 + optional node-level; needs a ruling if SC2's "whole-node-freeze regression test" is read as requiring the full harness.
3. **Remote-store serialization choice** — shared `remote_store_mutex_` (recommended) vs read-dedicated second `S3BlockStore`. Decidable now, revisitable with §10.2 data.
4. **`TemporarilyUnavailable` surfacing mechanism** — additive `GraphsyncDAGSyncer::Error` value (recommended) vs a richer error payload type; affects `GetNodeWithoutRequest` callers' error handling (`crdt_datastore.cpp:1846/:1938/:2277` currently ignore error detail — additive enum is low-risk).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| sgns-blockstore (superbuild install tree) | all cold-read code + fakes | ✓ (Phase 6-8 shipped; linked via `sgns-blockstore::sgns-blockstore`) | v1.0+Phase-6 | — |
| `SGNS_COLD_STORAGE=ON` build | fallback tests + gated TUs | ✓ (Phase-7/8 lane; local evidence pattern) | — | OFF builds keep config-gate Tier-1 tests non-empty |
| CMake + MSVC/Ninja build tree | verification-inside-build-tree rule | ✓ | existing | — |
| GTest / `addtest()` | all tests | ✓ | existing | — |
| Live s3d / MinIO | NOT required | — | — | hermetic by design (SC5); Tier-2/3 legs are other phases |

**Missing dependencies with no fallback:** none. **With fallback:** none needed.

*(Validation Architecture section omitted — `workflow.nyquist_validation: false` in .planning/config.json.)*

## Sources

### Primary (HIGH confidence — read this session)
- `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` (:20,:27,:140-147,:189-191,:205-227,:262-267,:313-317,:359-363,:375-391,:396-420,:511-517,:519-528,:549-556,:607+,:757-765,:800-810,:997-1010,:1084+,:1136-1146)
- `SuperGenius/src/crdt/graphsync_dagsyncer.hpp` (:47-55,:120-128,:154-158,:212), `SuperGenius/src/crdt/dagsyncer.hpp`
- `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/graphsync/impl/graphsync_impl.cpp` (:286-451) + `.hpp` (:112-115); `graphsync.hpp` (:33-67); `merkledag/impl/merkledag_service_impl.cpp` (:17-46); `ipfs/impl/datastore_rocksdb.cpp` (:53-70); `ipfs/datastore.hpp`
- `thirdparty/ipfs-pubsub/src/ipfs_pubsub/gossip_pubsub.cpp` (:518,:1283-1286)
- `SuperGenius/src/crdt/globaldb/globaldb.cpp` (:368-424,:560-700), `globaldb.hpp` (:61-118), `ColdStorageStack.hpp/.cpp`, `ColdStorageManager.hpp`, `BlockStoreBackedIpfsDatastore.hpp/.cpp`
- `SuperGenius/src/crdt/globaldb/pubsub_broadcaster_ext.cpp` (:616-657); `SuperGenius/src/crdt/impl/crdt_datastore.cpp` (:706,:809-811,:924-933,:1029,:1846,:1881,:1938,:2117-2168,:2277)
- `thirdparty/sgns-blockstore/include/sgns-blockstore/`: `BlockStatus.hpp`, `BlockStore.hpp`, `LocalBlockStore.hpp`, `S3BlockStore.hpp`, `FaultController.hpp`, `S3Client.hpp`, `Options.hpp`; `src/`: `LocalBlockStore.cpp` (:296-400,:457-464), `S3BlockStore.cpp` (:170-184), `InMemoryS3Client.hpp`, `MinioS3Client.hpp`; `docs/testing-tiers.md`
- `SuperGenius/test/src/crdt/CMakeLists.txt` (:50-113), `cold_storage_spill_test.cpp` (:226-279,:865-892), `test/src/graphsync/pubsub_graphsync_test.cpp`
- Workstream artifacts: 09-CONTEXT.md, REQUIREMENTS.md, ROADMAP.md (Phase 9), STATE.md, 08-CONTEXT.md, 08-RESEARCH.md; `.planning/research/STACK-rocksdb-backup-2026-10-22.md`

### Secondary (MEDIUM)
- `.planning/codebase/TESTING.md` conventions (via 08 artifacts' citations; lane mechanics independently re-verified in test CMakeLists)

## Metadata

**Confidence breakdown:**
- Read-chain placement & taxonomy: HIGH — every call path read in source; the dagMutex_ and single-thread-responder facts are the load-bearing evidence
- Executor/responder design: HIGH on constraints (verified threading + response mechanics), MEDIUM on the recommended shape (design judgment within locked D-05..D-07)
- Rehydrate/journal semantics: HIGH — library re-Put and createOnly behavior verified in impl source
- Defaults (4 s/1 thread/64 queue): MEDIUM — derived from verified constants (A3 caveat)

**Research date:** 2026-10-26
**Valid until:** indefinite (repo-grounded; re-verify only if graphsync_dagsyncer.cpp / graphsync_impl.cpp / ColdStorage* files change)
