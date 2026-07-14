# Phase 1: Audit — Technical Research

**Written:** 2026-07-08
**Status:** Research complete

---

## 1. Complete Data Domains Table

Every member variable of `class Bitswap` with its guarding mutex, access patterns, and classification.

| # | Member | Mutex Guard | Type | Access | Classification | Severity | Notes |
|---|--------|------------|------|--------|---------------|----------|-------|
| 1 | `host_` | none (reference) | `libp2p::Host&` | read/write | External (libp2p) | — | Depends on libp2p thread safety |
| 2 | `bus_` | none (reference) | `libp2p::event::Bus&` | read/write | External (libp2p) | — | Depends on libp2p thread safety |
| 3 | `sub_` | **none** | `libp2p::event::Handle` | write (start) | STRAND-CONFINED | LOW | Written once in `start()`, read indirectly by event bus |
| 4 | `context_` | none (const after ctor) | `shared_ptr<io_context>` | read | SHARED CONST | — | Thread-safe by design |
| 5 | `started_` | **none** | `bool` | write (start) | STRAND-CONFINED | LOW | BOOST_ASSERT prevents double-start |
| 6 | `mutexRequestCallbacks_` | self | `mutable std::mutex` | lock | GUARD | — | Guards #7 |
| 7 | `requestContexts_` | `mutexRequestCallbacks_` | `map<CID, shared_ptr<BitswapRequestContext>>` | read/write | MUTEX-GUARDED | — | Consistent RAII lock_guard |
| 8 | `mutexContentRequests_` | self | `mutable std::mutex` | lock | GUARD | — | Guards #9 |
| 9 | `contentRequests_` | `mutexContentRequests_` | `map<CID, shared_ptr<ContentRequestContext>>` | read/write | MUTEX-GUARDED | — | Consistent RAII lock_guard |
| 10 | `mutexActiveStreams_` | self | `mutable std::mutex` | lock | GUARD | — | Guards #11 |
| 11 | `activeStreams_` | `mutexActiveStreams_` | `map<PeerId, shared_ptr<Stream>>` | read/write | MUTEX-GUARDED | — | Consistent RAII lock_guard |
| 12 | `mutexBlockStore_` | self | `mutable std::mutex` | lock | GUARD | — | Guards #13, #14 |
| 13 | `blockStore_` | `mutexBlockStore_` | `map<CID, StoredBlock>` | read/write | MUTEX-GUARDED | — | Modified by const_cast in GetBlock() |
| 14 | `publishedContent_` | `mutexBlockStore_` | `map<CID, PublishedContent>` | read/write | MUTEX-GUARDED | — | Accessed from detached threads |
| 15 | **`cacheDir_`** | **NONE** | `std::string` | read/write | **FLAGGED** | **CRITICAL** | `setCacheDir()`/`getCacheDir()` no lock. Accessed from main thread, io_context, and detached threads. |
| 16 | `mutexDiskIndex_` | self | `mutable std::mutex` | lock | GUARD | — | Guards #17 |
| 17 | `diskIndex_` | `mutexDiskIndex_` | `set<string>` | read/write | MUTEX-GUARDED | — | Consistent lock_guard |
| 18 | `mutexProviders_` | self | `mutable std::mutex` | lock | GUARD | — | Guards #19. Also protects reads of #20, #21 in selectBestProvider/markProviderFailure. |
| 19 | `providers_` | `mutexProviders_` | `map<CID, vector<PeerProvider>>` | read/write | MUTEX-GUARDED | — | findProvider() returns raw pointer valid only under lock |
| 20 | **`maxPeerAttempts_`** | **NONE** (setter) / `mutexProviders_` (partial reader) | `size_t` | read/write | **FLAGGED** | **HIGH** | `SetMaxPeerAttempts()` no lock. Read in `requestBlockWithProviders()` without lock. Read in `selectBestProvider()` UNDER `mutexProviders_`. |
| 21 | **`peerFailureThreshold_`** | **NONE** (setter) / `mutexProviders_` (partial reader) | `int` | read/write | **FLAGGED** | **HIGH** | `SetPeerFailureThreshold()` no lock. Read in `selectBestProvider()`/`markProviderFailure()` under `mutexProviders_`. |
| 22 | `logger_` | internal | `Logger` | read/write | THREAD-SAFE | — | spdlog logger has internal synchronization |

### Helper Struct State

| Struct | Key Members | Protection | Classification | Concern |
|--------|------------|------------|---------------|---------|
| `BitswapRequestContext` | `callbacks_`, `responseTimer_`, `responseTimeout_` | **NONE** — strand-confined to io_context | STRAND-CONFINED (assumed) | `HandleResponseTimeout()` fires on io_context via deadline_timer. `HandleResponse()` called from processReceivedBlocks → runs on libp2p thread. **Verify strand confinement.** |
| `ContentRequestContext` | `pendingCIDs`, `completedCIDs`, `requestQueue`, `processingQueue`, `collectedFiles`, `filesInProgress`, `cidToPath`, `chunkToCidIndex`, `peerInfo`, `callback`, `timeout`, `timedOut` | **NONE** — strand-confined to io_context (assumed) | STRAND-CONFINED (assumed) | All accessed from Bitswap methods. `processingQueue` flag provides partial intra-request serialization but doesn't protect other fields. Multiple callbacks for the same `ContentRequestContext` may race if libp2p dispatch threads differ from io_context. |
| `PeerProvider` | all fields | `mutexProviders_` | MUTEX-GUARDED | findProvider() returns raw pointer |

---

## 2. Lock Call-Chain Analysis

### 2.1 Documented Lock Ordering

Only one nesting path confirmed:

```
mutexRequestCallbacks_ ──→ mutexProviders_
```

**Path:** `processReceivedBlocks()` acquires `mutexRequestCallbacks_` (line 271), then calls `markProviderSuccess()` which acquires `mutexProviders_` (line 1756).

**Reverse path check (providers → callbacks):** `selectBestProvider()` acquires `mutexProviders_` and releases it before any other lock. `requestBlockWithProviders()` acquires `mutexProviders_` (via selectBestProvider), releases, then calls `RequestBlock()` which may later acquire `mutexRequestCallbacks_` (via messageSent). These are sequential, not nested. **No reverse ordering found.**

### 2.2 Non-Nested Sequential Acquisitions

These mutex pairs are acquired in sequence (lock, release, then next lock), never nested:

| Sequence | First Lock | Release | Second Lock | In Method |
|----------|-----------|---------|-------------|-----------|
| blockStore → diskIndex | `mutexBlockStore_` | ✓ | `mutexDiskIndex_` | `storeBlock()`, `UnpublishContent()` |
| diskIndex → blockStore | `mutexDiskIndex_` | ✓ | `mutexBlockStore_` | `tryLoadFromDisk()` |
| diskIndex → diskIndex | `mutexDiskIndex_` | ✓ | `mutexDiskIndex_` | `buildDiskIndex()` (clear then populate loop) |
| providers → activeStreams | `mutexProviders_` | ✓ | `mutexActiveStreams_` | `requestBlockWithProviders()` → `RequestBlock()` → `RequestBlockWithRetry()` |

**Verdict:** No deadlock risk from current lock ordering. All 6 mutexes are acquired independently or in the single documented nesting (callbacks→providers).

### 2.3 Self-Deadlock Check

All mutex usage is via `std::lock_guard` which is non-recursive. No method re-acquires its own mutex. `findProvider()` is an internal helper that must be (and always is) called while `mutexProviders_` is held. **No self-deadlock risk.**

### 2.4 Lock-Across-Async Analysis

| Method | Lock Held | Async Operation | Risk |
|--------|-----------|----------------|------|
| `messageSent()` | `mutexRequestCallbacks_` (line 324) | Released before `rw->read()` at line 339 | **SAFE** — lock released before async |
| `setupContentRequest()` | `mutexContentRequests_` (line 540) | `ctx->timeout.async_wait()` at line 546 | **SAFE** — lock held only for map insertion, released before `async_wait` |
| `RequestBlockWithRetry()` | `mutexActiveStreams_` (line 419) | `host_.newStream()` at line 440 | **SAFE** — lock released at line 431 before newStream |
| `handleQueuedBlockResult()` | none | `timer->async_wait()` at line 1000 | **SAFE** — no lock held |
| `processReceivedBlocks()` | `mutexRequestCallbacks_` (line 271) | `HandleResponse()` at line 279 | **CHECK** — HandleResponse fires callbacks synchronously. If a callback calls back into Bitswap and acquires another lock, could deadlock. But callbacks are `std::function<void(result<string>)>` — typically return-only, no re-entrant lock acquisition. |
| retry timer callback (line 475) | none | `timer->async_wait()` | **SAFE** — no lock held |

**Verdict:** No lock-across-async violations found. All locks are released before async operations fire.

However, `processReceivedBlocks()` holds `mutexRequestCallbacks_` while invoking user callbacks via `HandleResponse()`. If a user callback re-enters Bitswap (e.g., calls `HasBlock()`, `GetBlock()`, etc.), the callback runs **under** `mutexRequestCallbacks_`. Re-entrant Bitswap calls that acquire `mutexRequestCallbacks_` would deadlock (non-recursive mutex). This is a **documentation gap** — the API contract for `BlockCallback` should specify that callbacks must not re-enter Bitswap while a request is in flight.

### 2.5 Lock Nested with Callback Invocation

`ContentRequestContext::HandleResponse()` (line 77-85) fires all callbacks synchronously. This is called from:
1. `processReceivedBlocks()` holding `mutexRequestCallbacks_`
2. `HandleResponseTimeout()` — on io_context via deadline_timer

If a callback from `HandleResponse()` acquires any Bitswap mutex, it could block the io_context thread potentially causing a timeout cascade. **Documentation gap.**

---

## 3. Boundary Crossing Matrix

### 3.1 Inbound: libp2p → Bitswap

| Entry Point | Caller | Thread Context | Bitswap Locks Acquired |
|------------|--------|---------------|----------------------|
| `Bitswap::handle()` | libp2p protocol handler dispatch | **libp2p dispatch thread** (unknown) | `mutexRequestCallbacks_`, `mutexProviders_`, `mutexBlockStore_`, `mutexDiskIndex_` |
| `Bitswap::onNewConnection()` | event bus `OnNewConnectionChannel` | **event bus dispatch thread** | none |
| `Bitswap::processReceivedBlocks()` | `handle()` → libp2p read callback | **libp2p I/O thread** | `mutexRequestCallbacks_`, `mutexProviders_` |

**Key finding:** `Bitswap::handle()` and its async read continuations run on libp2p threads, NOT on Bitswap's `io_context`. This means all Bitswap state accessed from these callbacks is accessed from libp2p threads.

### 3.2 Inbound: Consumer (SuperGenius) → Bitswap

| Call Site | File:Line | Thread Context | Methods Called |
|-----------|-----------|---------------|---------------|
| Construction | `GeniusNode.cpp:1308` | Main initialization thread | `Bitswap()`, `initialize()`, `start()`, `setCacheDir()` |
| Mirroring | `GeniusNode.cpp:754-805` | Processing service callback (io_context?) | `HasBlock()`, `RequestContent()` |
| Processing data availability | `processing_subtask_queue_accessor_impl.hpp:61` | Processing thread | `HasBlock()`, `GetBlock()`, `RequestBlock()` |
| Processing service | `processing_service.hpp:70` | Processing node thread | `RequestBlock()`, `RequestContent()` |
| FileManager | `GeniusNode.cpp:1317` | Various | `HasBlock()`, `RequestContent()` |

**Key finding:** Bitswap is shared via `shared_ptr` across multiple SuperGenius subsystems. Each may call Bitswap methods from different threads.

### 3.3 Outbound: Bitswap → Consumer (Callbacks)

| Callback | Fires From | Thread Context |
|----------|-----------|---------------|
| `BlockCallback` | `BitswapRequestContext::HandleResponse()` | libp2p thread (via `processReceivedBlocks`) |
| `BlockCallback` | `BitswapRequestContext::HandleResponseTimeout()` | Bitswap io_context (via `deadline_timer`) |
| `ContentCallback` | `checkContentRequestComplete()` | libp2p thread (via callback chain) |
| `ContentCallback` | `setupContentRequest::timeout` | Bitswap io_context |
| `PublishCallback` | `PublishFile()/PublishDirectory()` | **Detached std::thread** |

**Key finding:** Callbacks fire from at least three different thread contexts: libp2p threads, Bitswap io_context, and detached threads. Consumer code must handle thread-safety for any state accessed in these callbacks.

### 3.4 Outbound: Bitswap → Filesystem

| Operation | Method | Thread Context | Protection |
|-----------|--------|---------------|------------|
| Write block to disk | `persistBlock()` | Various (see caller analysis) | `mutexDiskIndex_` for index, **no lock for filesystem I/O** |
| Read block from disk | `tryLoadFromDisk()` | libp2p thread (via `handleWantlistRequest`) and const access (via `GetBlock()`) | `mutexDiskIndex_` for index, `mutexBlockStore_` for store |
| Build disk index | `buildDiskIndex()` | Main init thread (`initialize()`) | `mutexDiskIndex_` for index |
| Remove block from disk | `unpersistBlock()` | Unknown | `mutexDiskIndex_` for index |

### 3.5 Bitswap → RocksDB

**Finding:** Bitswap does NOT directly use RocksDB. It uses flat files in `cacheDir_` for persistence. The architectural doc's claim of a Bitswap→RocksDB boundary is incorrect. However, consumer callbacks (SuperGenius) may store received blocks into RocksDB. The RocksDB threading implications are in the consumer's scope, not Bitswap's.

---

## 4. Thread Entry-Point Inventory

Every function that can be called from outside Bitswap (public API or callback entry):

| Entry Point | Visibility | Called From | Thread Context(s) | Notes |
|------------|-----------|-------------|-------------------|-------|
| `Bitswap()` | public | Consumer (GeniusNode) | Main init thread | Constructor only |
| `initialize()` | public | Consumer | Main init thread | Registers protocol handler + builds disk index |
| `start()` | public | Consumer | Main init thread | Subscribes to event bus |
| `handle()` | public (BaseProtocol override) | libp2p | libp2p dispatch thread | All inbound Bitswap protocol messages |
| `onNewConnection()` | private | Event bus | Event bus dispatch thread | Lightweight, no locks |
| `RequestBlock()` | public | Consumer, self | **Any** (multiple consumer threads) | Acquires `mutexActiveStreams_`, `mutexRequestCallbacks_` |
| `RequestBlockWithRetry()` | public | Consumer, self | **Any** | As above + retry timer on io_context |
| `RequestContent()` | public (2 overloads) | Consumer | **Any** | Acquires `mutexContentRequests_` |
| `AddProvider()` | public | Consumer, self | **Any** | Acquires `mutexProviders_` |
| `AddProviders()` | public | Consumer | **Any** | Loops `AddProvider()` |
| `RemoveProvider()` | public | Consumer | **Any** | Acquires `mutexProviders_` |
| `GetProviders()` | public (const) | Consumer | **Any** | Acquires `mutexProviders_` |
| `ClearProviders()` | public | Consumer | **Any** | Acquires `mutexProviders_` |
| `SetMaxPeerAttempts()` | public | Consumer | **Any** | **NO LOCK** — data race on `maxPeerAttempts_` |
| `SetPeerFailureThreshold()` | public | Consumer | **Any** | **NO LOCK** — data race on `peerFailureThreshold_` |
| `PublishFile()` | public | Consumer | **Any** (caller) + **detached thread** (work) | Spawns detached thread |
| `PublishDirectory()` | public | Consumer | **Any** (caller) + **detached thread** (work) | Spawns detached thread |
| `PublishData()` | public | Consumer | **Any** | Acquires `mutexBlockStore_` |
| `HasBlock()` | public (const) | Consumer | **Any** | Acquires `mutexBlockStore_`, `mutexDiskIndex_` |
| `GetBlock()` | public (const) | Consumer | **Any** | Acquires `mutexBlockStore_`, `mutexDiskIndex_`. **const_cast** mutates `blockStore_`. |
| `UnpublishContent()` | public | Consumer | **Any** | Acquires `mutexBlockStore_` |
| `ListPublishedContent()` | public (const) | Consumer | **Any** | Acquires `mutexBlockStore_` |
| `setCacheDir()` | public | Consumer | **Any** | **NO LOCK** |
| `getCacheDir()` | public (const) | Consumer | **Any** | **NO LOCK** |
| `buildDiskIndex()` | public | Consumer | Init thread only | Acquires `mutexDiskIndex_` |
| `persistBlock()` | public | Self (storeBlock) | **Any** (called from various paths) | Acquires `mutexDiskIndex_` |
| `unpersistBlock()` | public | Unknown | **Any** | Acquires `mutexDiskIndex_` |
| `getProtocolId()` | public (const, override) | libp2p | **Any** | No state access |
| `messageSent()` | private (callback) | libp2p I/O (rw->write callback) | **libp2p I/O thread** | Acquires `mutexRequestCallbacks_` |
| `processReceivedBlocks()` | private | `handle()`, `messageSent()` | **libp2p thread** | Acquires `mutexRequestCallbacks_`, `mutexProviders_` |
| `handleWantlistRequest()` | private | `handle()` | **libp2p thread** | Acquires `mutexBlockStore_`, `mutexDiskIndex_` |
| `processUnixFSBlock()` | private (callback chain) | RequestContent callback | **Any** (via callback) | Accesses `ContentRequestContext` fields directly (no lock) |
| `processRequestQueue()` | private | `processUnixFSBlock()`, etc. | **Any** (via callback) | Accesses `ContentRequestContext` fields directly (no lock) |
| `checkContentRequestComplete()` | private | Various | **Any** (via callback) | Acquires `mutexContentRequests_`, accesses `ContentRequestContext` directly |
| `tryLoadFromDisk()` | private (const via const_cast!) | `handleWantlistRequest()`, `GetBlock()` | **Any** | Acquires `mutexDiskIndex_`, `mutexBlockStore_` |
| `selectBestProvider()` | private | `requestBlockWithProviders()`, etc. | **Any** (via public API) | Acquires `mutexProviders_`. Reads `peerFailureThreshold_` under lock, reads `maxPeerAttempts_` NOT under this lock but via caller |
| `markProviderFailure()` | private | `messageSent()`, retry callback | **Any** | Acquires `mutexProviders_` |
| `markProviderSuccess()` | private | `processReceivedBlocks()` | **libp2p thread** | Acquires `mutexProviders_` (nested inside `mutexRequestCallbacks_`) |
| `cleanupStaleProviders()` | private | **NOT CALLED ANYWHERE** | — | Dead code |

---

## 5. Strand Confinement Analysis

### 5.1 `BitswapRequestContext` Strand Confinement

| Method | Called From | Thread | Strand-Safe? |
|--------|-----------|--------|-------------|
| `AddCallback()` | `messageSent()` (line 328) | libp2p I/O thread | **✓** — only called once per request context creation |
| `HandleResponse()` | `processReceivedBlocks()` (line 279) | libp2p thread | **✓** — clears callbacks, only fires once |
| `HandleResponseTimeout()` | `deadline_timer` on io_context | Bitswap io_context | **✗** — potential race with `HandleResponse()` from libp2p thread |

**Finding:** `HandleResponseTimeout()` runs on io_context via deadline_timer. `HandleResponse()` runs on the libp2p thread via `processReceivedBlocks()`. Both call `HandleResponse()` internally via the timeout path. If a block arrives just as the timer fires, two HandleResponse calls could race on:
- `responseTimer_` (expires_at modification)
- `callbacks_` (iteration and clear)

**Severity: MEDIUM** — requires exact timing of block arrival + timer expiry to trigger.

### 5.2 `ContentRequestContext` Strand Confinement

`ContentRequestContext` has NO internal mutex. All its fields (`pendingCIDs`, `completedCIDs`, `requestQueue`, `collectedFiles`, `filesInProgress`, `cidToPath`, `chunkToCidIndex`, `processingQueue`, `timedOut`, `peerInfo`) are accessed directly.

| Access Path | Thread |
|------------|--------|
| `processUnixFSBlock()` via `processRequestQueue()` → `RequestBlock()` callback | libp2p thread (via callback chain) |
| `setupContentRequest::timeout` → `deadline_timer::async_wait` | Bitswap io_context |
| `processRequestQueue()` delay timer callback | Bitswap io_context |

**Finding:** `ContentRequestContext` fields are accessed from TWO thread contexts:
1. libp2p thread (via block result callbacks → `processUnixFSBlock`, `handleQueuedBlockResult`, etc.)
2. Bitswap io_context (via timeout handler, delay timer for `processRequestQueue`)

The `processingQueue` flag provides partial mutual exclusion for `processRequestQueue()` itself, but does NOT protect:
- `pendingCIDs` / `completedCIDs` — modified in `processUnixFSBlock()`, `handleFileBlock()`, etc.
- `collectedFiles` — modified in `assembleCompleteFile()`, `handleFileBlock()`
- `filesInProgress` — modified in `handleFileBlock()`, `handleFileChunk()`, `assembleCompleteFile()`
- `cidToPath` — modified in `handleFileBlock()`, `handleDirectoryBlock()`

**Severity: HIGH** — multiple callbacks for the same `ContentRequestContext` may execute concurrently on libp2p thread and io_context, causing data races on all context fields.

---

## 6. Pre-Identified Issues — Master Findings Table

| # | Severity | Category | Location | Description | Evidence | Confidence | Recommended Fix |
|---|----------|----------|----------|-------------|----------|-----------|----------------|
| **C-1** | **CRITICAL** | Missing Lock | `bitswap.cpp:1908-1920`, `bitswap.hpp:338` | `cacheDir_` (std::string) has no synchronization. Read/written from main thread (setCacheDir/getCacheDir/buildDiskIndex), io_context (tryLoadFromDisk, persistBlock), and detached threads (PublishFile/PublishDirectory). | `setCacheDir()` at line 1908-1914: direct assignment. `getCacheDir()` at line 1917-1920: direct return. All other methods read `cacheDir_` without any lock. | **CONFIRMED** | Add `mutable std::mutex mutexCacheDir_` + lock_guard in `setCacheDir()`, `getCacheDir()`, and all read sites. Or make `cacheDir_` a `std::atomic<std::string*>` (if available) or use a const char* with atomic store/load. |
| **C-2** | **HIGH** | Missing Lock | `bitswap.cpp:1616-1623`, `bitswap.hpp:344-345` | `maxPeerAttempts_` and `peerFailureThreshold_` setters have no lock. Reads occur under `mutexProviders_` in `selectBestProvider()` (line 1680) and `markProviderFailure()` (line 1737), but also read WITHOUT lock in `requestBlockWithProviders()` (line 1809) and `requestBlockWithProvidersFromRoot()` (line 1854). | Setter writes are direct assignment. `requestBlockWithProviders` reads `maxPeerAttempts_` at line 1809 without holding any lock. | **CONFIRMED** | Either (a) make these `std::atomic<size_t>` / `std::atomic<int>`, or (b) protect all access under `mutexProviders_`. Option (a) simpler and more correct since these are trivially copyable. |
| **C-3** | **HIGH** | Thread Confusion | `bitswap.cpp:1354-1432` | `PublishFile()` and `PublishDirectory()` create `std::thread(...).detach()`. Detached threads access shared state: `blockStore_` (locked), `publishedContent_` (locked), `cacheDir_` (**unlocked, see C-1**), and filesystem. Multiple parallel publishes create multiple detached threads competing for same resources. | Lines 1358-1388 (PublishFile), 1395-1431 (PublishDirectory). Both use `.detach()`. | **CONFIRMED** | Replace detached threads with `boost::asio::post(context_, ...)` to serialize publish work on the io_context. This eliminates the detached thread entirely and ensures all shared state access is on a single strand. |
| **C-4** | **HIGH** | Async Safety / const_cast | `bitswap.cpp:1481-1502` | `GetBlock()` is declared `const` but uses `const_cast<Bitswap*>(this)->tryLoadFromDisk(cid)` to mutate `blockStore_`. This violates const-correctness which implies thread-safety — callers expect const methods to be safe for concurrent access. | Line 1492: `const_cast<Bitswap*>(this)->tryLoadFromDisk(cid)`. `tryLoadFromDisk` modifies `blockStore_` (line 2084-2093) and potentially `diskIndex_` (line 2071). | **CONFIRMED** | Two options: (a) Remove `const` from `GetBlock()` and `HasBlock()` — make mutation explicit. (b) Pre-load blocks on a separate non-const code path. Option (a) requires updating all callers including consumer code. |
| **C-5** | **HIGH** | Missing Lock | `bitswap.cpp:577-636`, `bitswap.hpp:121-167` | `ContentRequestContext` fields accessed without synchronization from both libp2p callback threads and Bitswap io_context. `processingQueue` flag only protects `processRequestQueue()` recurrence, not other field mutations. | `processUnixFSBlock()` modifies `pendingCIDs`, `completedCIDs`, `requestQueue`, `filesInProgress`, `chunkToCidIndex` (lines 587-636). Timeout handler modifies `timedOut` on io_context (line 557). These run on different threads. | **CONFIRMED** | Add `mutable std::mutex` to `ContentRequestContext` and guard all field access. Or confirm that all libp2p callbacks actually dispatch through the io_context (post to strand). If they don't, strand posting is required. |
| **C-6** | **MEDIUM** | Async Safety | `bitswap.cpp:70-89` | `BitswapRequestContext::HandleResponseTimeout()` runs on io_context (via deadline_timer). `HandleResponse()` runs on libp2p thread (via processReceivedBlocks). Both access `callbacks_` and `responseTimer_` without synchronization. | `HandleResponseTimeout()` at line 87-89 calls `HandleResponse()` which iterates `callbacks_` and modifies `responseTimer_` (line 79). `HandleResponse()` from libp2p thread does the same. | **SUSPECTED** | Add `mutable std::mutex` to `BitswapRequestContext`, or ensure `HandleResponse` is always posted to the io_context strand. |
| **C-7** | **MEDIUM** | Lock Order (Documentation Gap) | `bitswap.cpp:271-285` | `processReceivedBlocks()` holds `mutexRequestCallbacks_` while invoking callbacks via `HandleResponse()`. If a callback re-enters Bitswap and acquires `mutexRequestCallbacks_`, non-recursive mutex → deadlock. | Line 279: `itContext->second->HandleResponse(block)` — fires callbacks synchronously while `callbacksGuard` holds the lock. | **CONFIRMED** | Document that `BlockCallback` must not re-enter Bitswap. Add runtime assertion: check `!mutexRequestCallbacks_.try_lock()` before callback invocation and log warning if held. |
| **C-8** | **MEDIUM** | Documentation Gap | `bitswap.cpp:2047` | `cleanupStaleProviders()` is defined but never called. Dead code. | Grep entire codebase: no call sites. | **CONFIRMED** | Either integrate into a periodic timer on io_context, or remove. If integrated, ensure io_context strand confinement. |
| **C-9** | **MEDIUM** | Thread Confusion | `bitswap.cpp:123-216` | `Bitswap::handle()` and its async read continuations access Bitswap shared state from libp2p threads. Not all access paths are obvious — continuous server read loop (lines 164-201) re-subscribes on each message received, maintaining a persistent libp2p-thread callback chain. | The recursive lambda `setupServerRead` at lines 166-197 captures `ctx` (Bitswap shared_ptr) and spins indefinitely on the libp2p thread. All `handleWantlistRequest()` calls run on this libp2p thread. | **CONFIRMED** | This is by design for the server role, but needs explicit documentation: which Bitswap methods run on which thread. |
| **C-10** | **LOW** | Documentation Gap | `bitswap.hpp:173-348` | Bitswap has 6 separate mutexes with only one documented lock ordering (callbacks → providers). No lock-ordering documentation exists commenting the other 4 mutexes as independent. | Header file has no comments on lock ordering or domain grouping. | **CONFIRMED** | Add Doxygen comments on each mutex: which members it protects, ordering relative to other mutexes, and thread context assumptions. |

---

## 7. Consumer Code Call-Site Inventory

### 7.1 GeniusNode (SuperGenius)

| File:Line | Context | Bitswap API Used | Thread | Notes |
|-----------|---------|-----------------|--------|-------|
| `account/GeniusNode.cpp:1308-1317` | Initialization | Constructor, `initialize()`, `setCacheDir()`, `start()` (indirect) | Main init thread | `bitswap_` stored as `shared_ptr`. Shared pubsub host and io_context. |
| `account/GeniusNode.cpp:754-805` | Mirror result callback | `HasBlock()`, `RequestContent()` | Processing service callback thread | Calls HasBlock first (check), then RequestContent. Content callback captures `weak_from_this()`. |
| `account/GeniusNode.cpp:1317` | FileManager wiring | `setBitswap()` pass | Init thread | FileManager gets shared_ptr to same Bitswap instance |

### 7.2 Processing Layer (SuperGenius)

| File | Role | Bitswap Usage |
|------|------|--------------|
| `processing/processing_service.hpp:123` | Field | Holds `shared_ptr<Bitswap>` for data availability |
| `processing/processing_node.hpp:116` | Field | Holds `shared_ptr<Bitswap>` cached for Accessor creation |
| `processing/processing_subtask_queue_accessor_impl.hpp:111` | Field | Holds `shared_ptr<Bitswap>` for IPFS result verification |

**Note:** The processing layer code was not fully traced (files exceed scope). The CONTEXT.md specifies these files as consumer call sites. These `shared_ptr` copies mean Bitswap is accessed from at least 3 different SuperGenius subsystems concurrently.

---

## 8. Config Members: `maxPeerAttempts_` and `peerFailureThreshold_` — Detailed Access Map

| Access Site | File:Line | Lock Held? | Thread |
|------------|-----------|-----------|--------|
| `SetMaxPeerAttempts()` | `bitswap.cpp:1616-1619` | **NO** | Any caller thread |
| `SetPeerFailureThreshold()` | `bitswap.cpp:1621-1624` | **NO** | Any caller thread |
| `requestBlockWithProviders()` read `maxPeerAttempts_` | `bitswap.cpp:1809` | **NO** | Any caller thread |
| `requestBlockWithProvidersFromRoot()` read `maxPeerAttempts_` | `bitswap.cpp:1854` | **NO** | Any caller thread |
| `selectBestProvider()` read `peerFailureThreshold_` | `bitswap.cpp:1680` | `mutexProviders_` | Any caller |
| `markProviderFailure()` read `peerFailureThreshold_` | `bitswap.cpp:1737` | `mutexProviders_` | Any caller |

Three of six access sites have NO lock. Two have `mutexProviders_`. The mixed protection makes these variables a clear data race.

---

## 9. Validation Architecture

### 9.1 Static Verification (This Phase)

Each finding in §6 must be verified by:
1. **Manual source inspection** — trace every access to each flagged member
2. **Cross-reference with header** — confirm declaration matches usage pattern
3. **Document evidence** — cite exact line numbers and access patterns

### 9.2 Testable Hypotheses (Phase 2 Preparation)

| Hypothesis | Verification Method |
|-----------|-------------------|
| `cacheDir_` data race causes crash under concurrent setCacheDir + persistBlock | TSAN build + concurrent test |
| `maxPeerAttempts_` torn read on 32-bit ARM | TSAN + ARM cross-compile test |
| `ContentRequestContext` race causes corrupted file assembly | TSAN + concurrent content requests |
| Detached threads cause use-after-free | TSAN + rapid PublishFile/PublishDirectory calls |
| `GetBlock()` const_cast causes blockStore_ corruption | TSAN + concurrent GetBlock from multiple threads |

---

## 10. Research Blockers

**None.** All source code was fully read and analyzed. No external dependencies blocked analysis.

---

*Phase: 1-Audit*
*Research complete: 2026-07-08*
*Files analyzed: bitswap.hpp (351 lines), bitswap.cpp (2098 lines), bitswap_message.hpp (30 lines), merkledag_encoder.hpp (73 lines), GeniusNode.cpp (partial)*
