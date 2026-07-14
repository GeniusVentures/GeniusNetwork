# CONCURRENCY-MAP.md — IPFS Bitswap Thread Safety Audit

**Project:** Genius Network — IPFS Bitswap Thread Safety
**Phase 1:** Audit — `thirdparty/ipfs-bitswap-cpp`
**Created:** 2026-07-08

---

## Data Domains Table

Every member variable of `class Bitswap` with guarding mutex, access pattern, and classification.

### Domain: `mutexBlockStore_`

**Mutex declaration:** `bitswap.hpp:333` — `mutable std::mutex mutexBlockStore_`
**Guarded members:** `blockStore_` (bitswap.hpp:334), `publishedContent_` (bitswap.hpp:335)
**Lock pattern:** `std::lock_guard<std::mutex>` — RAII, never nested with other mutexes, released before async calls

#### `blockStore_` — `std::map<CID, StoredBlock>` — Access Sites

| # | Method | File:Line | Thread Context | Lock Pattern | Classification | Notes |
|---|--------|-----------|---------------|-------------|---------------|-------|
| 1 | `storeBlock()` | `bitswap.cpp:1296-1305` | Caller thread (various: publish, server, consumer) | `lock_guard` (line 1297) | MUTEX-GUARDED | emplace — lock held for map insertion only, released before `persistBlock()` |
| 2 | `encodeChunkedFile()` | `bitswap.cpp:1100-1103` | Caller thread (publish paths) | `lock_guard` (line 1100) | MUTEX-GUARDED | find — reads `block.size` for tsize link field |
| 3 | `encodeChunkedFile()` | `bitswap.cpp:1111-1127` | Caller thread (publish paths) | `lock_guard` (line 1111) | MUTEX-GUARDED | find + contentSize write — multiple finds to compute totalSizeWithOverhead, then mutates root block's contentSize |
| 4 | `encodeAndStoreDirectory()` | `bitswap.cpp:1176-1204` | Caller thread (publish paths) | `lock_guard` (line 1176) | MUTEX-GUARDED | find — reads `contentSize` for tsize on each directory link entry |
| 5 | `encodeAndStoreDirectory()` | `bitswap.cpp:1210-1216` | Caller thread (publish paths) | `lock_guard` (line 1210) | MUTEX-GUARDED | find + contentSize write — updates directory root block's contentSize |
| 6 | `handleWantlistRequest()` | `bitswap.cpp:1312-1318` | **libp2p thread** (via `handle()` → server read loop) | `lock_guard` (line 1312) | MUTEX-GUARDED | find — lock released before `tryLoadFromDisk()` at line 1321 |
| 7 | `handleWantlistRequest()` | `bitswap.cpp:1323-1329` | **libp2p thread** | `lock_guard` (line 1323) | MUTEX-GUARDED | find — re-acquired after `tryLoadFromDisk()`, sends block data |
| 8 | `PublishFile()` | `bitswap.cpp:1368-1383` | **DETACHED std::thread** (line 1358 → `.detach()`) | `lock_guard` (line 1369) | MUTEX-GUARDED | find + emplace — **thread identity: detached std::thread, NOT io_context** |
| 9 | `PublishDirectory()` | `bitswap.cpp:1405-1424` | **DETACHED std::thread** (line 1395 → `.detach()`) | `lock_guard` (line 1406) | MUTEX-GUARDED | iteration + emplace — iterates entire blockStore_ looking for directory-prefix matches. **thread identity: detached std::thread** |
| 10 | `PublishData()` | `bitswap.cpp:1445-1460` | Caller thread (inline, no detach) | `lock_guard` (line 1446) | MUTEX-GUARDED | find + emplace — inline, no detached thread |
| 11 | `HasBlock()` | `bitswap.cpp:1468-1473` | Caller thread (various: consumer, server) | `lock_guard` (line 1469) | MUTEX-GUARDED | count — const method, lock_guard within scope block |
| 12 | `GetBlock()` | `bitswap.cpp:1483-1490` | Caller thread (various: consumer) | `lock_guard` (line 1484) | MUTEX-GUARDED | find — const method, returns block data. Lock released before line 1492 |
| 13 | `GetBlock()` | `bitswap.cpp:1494-1499` | Caller thread (various: consumer) | `lock_guard` (line 1494) | MUTEX-GUARDED | find — re-acquired after const_cast→tryLoadFromDisk. **const_cast at line 1492 violates const-correctness = thread-safety contract** |
| 14 | `UnpublishContent()` | `bitswap.cpp:1506-1520` | Caller thread (consumer) | `lock_guard` (line 1506) | MUTEX-GUARDED | find + erase — iterates content blocks to erase from blockStore_. Lock held for full operation |
| 15 | `ListPublishedContent()` | `bitswap.cpp:1525-1532` | Caller thread (consumer) | `lock_guard` (line 1525) | MUTEX-GUARDED | iteration + reserve — const method, copies content to return vector |
| 16 | `tryLoadFromDisk()` | `bitswap.cpp:2084-2093` | Various (libp2p thread via handleWantlistRequest, consumer via GetBlock) | `lock_guard` (line 2085) | MUTEX-GUARDED | emplace — inserts block loaded from disk into blockStore_ |

**Total blockStore_ access sites:** 16 confirmed, each with lock_guard. All guarded. 2 detached-thread sites (sites 8-9) flagged as Thread Confusion risk.

#### `publishedContent_` — `std::map<CID, PublishedContent>` — Access Sites

| # | Method | File:Line | Thread Context | Lock Pattern | Classification | Notes |
|---|--------|-----------|---------------|-------------|---------------|-------|
| 1 | `PublishFile()` | `bitswap.cpp:1382` | **DETACHED std::thread** | `lock_guard` (line 1369) | MUTEX-GUARDED | emplace — publishes content with SINGLE_FILE type |
| 2 | `PublishDirectory()` | `bitswap.cpp:1423` | **DETACHED std::thread** | `lock_guard` (line 1406) | MUTEX-GUARDED | emplace — publishes content with DIRECTORY type |
| 3 | `PublishData()` | `bitswap.cpp:1459` | Caller thread (inline) | `lock_guard` (line 1446) | MUTEX-GUARDED | emplace — publishes raw data content |
| 4 | `UnpublishContent()` | `bitswap.cpp:1507-1520` | Caller thread (consumer) | `lock_guard` (line 1506) | MUTEX-GUARDED | find + erase — removes published content and its blocks |
| 5 | `ListPublishedContent()` | `bitswap.cpp:1525-1532` | Caller thread (consumer) | `lock_guard` (line 1525) | MUTEX-GUARDED | iteration — const method, copies content to return vector |

**Total publishedContent_ access sites:** 5 confirmed. All guarded.

---

### Domain: `mutexRequestCallbacks_`

**Mutex declaration:** `bitswap.hpp:324` — `mutable std::mutex mutexRequestCallbacks_`
**Guarded members:** `requestContexts_` (bitswap.hpp:325)
**Lock pattern:** `std::lock_guard<std::mutex>` — RAII. **WARNING: callback invoked while lock held** (see Finding F-04)

#### `requestContexts_` — `std::map<CID, std::shared_ptr<BitswapRequestContext>>` — Access Sites

| # | Method | File:Line | Thread Context | Lock Pattern | Classification | Notes |
|---|--------|-----------|---------------|-------------|---------------|-------|
| 1 | `processReceivedBlocks()` | `bitswap.cpp:271-285` | **libp2p thread** (via `handle()` → server read loop) | `lock_guard` (line 271) | MUTEX-GUARDED | find + HandleResponse() invocation. **Callback fires while lock held** (line 279) — if callback re-enters Bitswap and acquires mutexRequestCallbacks_, deadlock. |
| 2 | `messageSent()` | `bitswap.cpp:324-336` | **libp2p I/O thread** (via `rw->write` callback) | `lock_guard` (line 324) | MUTEX-GUARDED | find + emplace. Lock released at line 336 before async `rw->read()` at line 340 — ASYNC SAFE. |
| 3 | `processReceivedBlocks()` | `bitswap.cpp:277` | **libp2p thread** | `lock_guard` (line 271) | MUTEX-GUARDED | markProviderSuccess called under lock → acquires `mutexProviders_`. **This is the only documented lock nesting: mutexRequestCallbacks_ → mutexProviders_.** |
| 4 | `messageSent()` | `bitswap.cpp:328` | **libp2p I/O thread** | `lock_guard` (line 324) | MUTEX-GUARDED | AddCallback() invoked under lock — adds BlockCallback to request context. |

**Total requestContexts_ access sites:** 4 confirmed. All guarded.

**Lock nesting:** Line 277: `mutexRequestCallbacks_` → `markProviderSuccess()` → `mutexProviders_`. No reverse nesting found.

---

### Domain: `mutexContentRequests_`

**Mutex declaration:** `bitswap.hpp:327` — `mutable std::mutex mutexContentRequests_`
**Guarded members:** `contentRequests_` (bitswap.hpp:328)
**Lock pattern:** `std::lock_guard<std::mutex>` — RAII, never nested with other mutexes

#### `contentRequests_` — `std::map<CID, std::shared_ptr<ContentRequestContext>>` — Access Sites

| # | Method | File:Line | Thread Context | Lock Pattern | Classification | Notes |
|---|--------|-----------|---------------|-------------|---------------|-------|
| 1 | `setupContentRequest()` | `bitswap.cpp:540-542` | Caller thread (content request path) | `lock_guard` (line 540) | MUTEX-GUARDED | emplace — lock held for map insertion only, released before `ctx->timeout.async_wait()` at line 546 |
| 2 | `setupContentRequest()` timeout handler | `bitswap.cpp:553-559` | **Bitswap io_context** (via `deadline_timer::async_wait`) | `lock_guard` (line 553) | MUTEX-GUARDED | find + erase + callback invocation. **Callback invoked while lock held** — same pattern as mutexRequestCallbacks_. |
| 3 | `failContentRequest()` | `bitswap.cpp:573-574` | Caller thread (error paths) | `lock_guard` (line 573) | MUTEX-GUARDED | erase — removes context from map on failure |
| 4 | `checkContentRequestComplete()` | `bitswap.cpp:890-891` | **libp2p thread** (via callback chain from `processUnixFSBlock`) | `lock_guard` (line 890) | MUTEX-GUARDED | erase — removes completed content request from map |

**Total contentRequests_ access sites:** 4 confirmed. All guarded.

### Domain: `mutexActiveStreams_`

**Mutex declaration:** `bitswap.hpp:330` — `mutable std::mutex mutexActiveStreams_`
**Guarded members:** `activeStreams_` (bitswap.hpp:331)
**Lock pattern:** `std::lock_guard<std::mutex>` — RAII. Lock held for minimal scope, always released before async operations (`newStream`, `writeBitswapMessageToStream`).

#### `activeStreams_` — `std::map<libp2p::peer::PeerId, std::shared_ptr<libp2p::connection::Stream>>` — Access Sites

| # | Method | File:Line | Thread Context | Lock Pattern | Classification | Notes |
|---|--------|-----------|---------------|-------------|---------------|-------|
| 1 | `RequestBlockWithRetry()` | `bitswap.cpp:419-431` | Caller thread (various: consumer, server, retry) | `lock_guard` (line 419) | MUTEX-GUARDED | find + isClosed check + erase. Lock released at line 431 before `host_.newStream()` — ASYNC SAFE. |
| 2 | `RequestBlockWithRetry()` retry callback | `bitswap.cpp:465-467` | **Bitswap io_context** (via retry timer) | `lock_guard` (line 465) | MUTEX-GUARDED | erase — cleans up failed stream from map on stream creation failure |
| 3 | `RequestBlockWithRetry()` newStream success | `bitswap.cpp:501-504` | **libp2p async callback** (via `newStream` result) | `lock_guard` (line 502) | MUTEX-GUARDED | emplace — caches new stream. Lock released before `writeBitswapMessageToStream()` at line 505 — ASYNC SAFE. |

**Total activeStreams_ access sites:** 3 confirmed. All guarded. Lock always released before async calls — zero lock-across-async violations for this domain.

**Stream reuse pattern:** Lines 419-431 demonstrate the pattern: lock held to check and erase a closed stream, then released before `writeBitswapMessageToStream()` or `host_.newStream()`. The `shared_ptr<Stream>` keeps the stream alive after the lock is released — lifetime safety through shared ownership.

---

### Domain: `mutexDiskIndex_`

**Mutex declaration:** `bitswap.hpp:339` — `mutable std::mutex mutexDiskIndex_`
**Guarded members:** `diskIndex_` (bitswap.hpp:340)
**Lock pattern:** `std::lock_guard<std::mutex>` — RAII. **buildDiskIndex() lock/re-lock pattern** creates a transitory empty-index window (see Finding F-05).

#### `diskIndex_` — `std::set<std::string>` — Access Sites

| # | Method | File:Line | Thread Context | Lock Pattern | Classification | Notes |
|---|--------|-----------|---------------|-------------|---------------|-------|
| 1 | `HasBlock()` | `bitswap.cpp:1476-1478` | Caller thread (consumer, server, various) | `lock_guard` (line 1477) | MUTEX-GUARDED | count — checks disk index as fallback when block not in blockStore_ |
| 2 | `buildDiskIndex()` | `bitswap.cpp:1937-1939` | **Main init thread** (via `initialize()`) | `lock_guard` (line 1937) | MUTEX-GUARDED | clear — wipes entire index. Lock released after clear, **re-acquired per file** at line 1948 |
| 3 | `buildDiskIndex()` per-file | `bitswap.cpp:1948-1950` | **Main init thread** | `lock_guard` (line 1948) | MUTEX-GUARDED | insert per file — lock acquired and released for EACH file in cache directory. **Between clear (site 2) and first insert, diskIndex_ is empty** |
| 4 | `persistBlock()` | `bitswap.cpp:1978-1980` | Various (via `storeBlock()` → caller chain) | `lock_guard` (line 1978) | MUTEX-GUARDED | insert — adds CID to disk index after persisting. Lock held for index insertion only |
| 5 | `unpersistBlock()` | `bitswap.cpp:2038-2040` | Unknown (API available but callers not traced) | `lock_guard` (line 2038) | MUTEX-GUARDED | erase — removes CID from disk index |
| 6 | `tryLoadFromDisk()` | `bitswap.cpp:2058-2063` | Various (libp2p thread via handleWantlistRequest, consumer via GetBlock's const_cast) | `lock_guard` (line 2058) | MUTEX-GUARDED | count — checks if CID exists in disk index before attempting file read |
| 7 | `tryLoadFromDisk()` | `bitswap.cpp:2070-2071` | Various | `lock_guard` (line 2070) | MUTEX-GUARDED | erase — removes CID from index if file disappeared from disk (stale index entry) |

**Total diskIndex_ access sites:** 7 confirmed. All guarded. **buildDiskIndex() empty-index window flagged as LOW severity finding (F-05).**

### Domain: `mutexProviders_`

**Mutex declaration:** `bitswap.hpp:342` — `mutable std::mutex mutexProviders_`
**Guarded members:** `providers_` (bitswap.hpp:343). Also partially protects reads of `maxPeerAttempts_` and `peerFailureThreshold_` in `selectBestProvider()` and `markProviderFailure()`.
**Lock pattern:** `std::lock_guard<std::mutex>` — RAII. `findProvider()` returns raw `PeerProvider*` valid only under lock — all callers hold the lock (fragile but currently correct).

#### `providers_` — `std::map<CID, std::vector<PeerProvider>>` — Access Sites

| # | Method | File:Line | Thread Context | Lock Pattern | Classification | Notes |
|---|--------|-----------|---------------|-------------|---------------|-------|
| 1 | `AddProvider()` | `bitswap.cpp:1550-1569` | Caller thread (consumer, self) | `lock_guard` (line 1550) | MUTEX-GUARDED | `findProvider()` + emplace_back — updates existing or creates new provider entry |
| 2 | `RemoveProvider()` | `bitswap.cpp:1574-1594` | Caller thread (consumer) | `lock_guard` (line 1574) | MUTEX-GUARDED | find + remove_if + erase — removes provider by peerId, erases CID entry if vector empty |
| 3 | `GetProviders()` | `bitswap.cpp:1599-1607` | Caller thread (consumer) | `lock_guard` (line 1599) | MUTEX-GUARDED | find — returns copy of provider vector (safe — data copied before lock released) |
| 4 | `ClearProviders()` | `bitswap.cpp:1611-1613` | Caller thread (consumer) | `lock_guard` (line 1611) | MUTEX-GUARDED | erase — removes all providers for a CID |
| 5 | `GetTotalProviderCount()` | `bitswap.cpp:1637-1643` | Caller thread (consumer) | `lock_guard` (line 1637) | MUTEX-GUARDED | iteration + sum — counts all providers across all CIDs |
| 6 | `GetProviderDebugInfo()` | `bitswap.cpp:1648-1663` | Caller thread (consumer, debugging) | `lock_guard` (line 1648) | MUTEX-GUARDED | iteration — copies provider info to string map |
| 7 | `selectBestProvider()` | `bitswap.cpp:1667-1725` | Caller thread (various: consumer, retry) | `lock_guard` (line 1667) | MUTEX-GUARDED | find + sort + select. Reads `peerFailureThreshold_` under lock (line 1680). Returns `PeerInfo` by value — safe. |
| 8 | `markProviderFailure()` | `bitswap.cpp:1729-1752` | Caller thread (various: messageSent error, retry) | `lock_guard` (line 1729) | MUTEX-GUARDED | `findProvider()` + failureCount++. Reads `peerFailureThreshold_` under lock (line 1737). |
| 9 | `markProviderSuccess()` | `bitswap.cpp:1756-1770` | **libp2p thread** (via `processReceivedBlocks`) | `lock_guard` (line 1756) | MUTEX-GUARDED | `findProvider()` + failureCount reset. **Called under nested mutexRequestCallbacks_ lock** (see line 277) — part of documented nesting. |
| 10 | `cleanupStaleProviders()` | `bitswap.cpp:1774-1805` | **NEVER CALLED** — dead code | `lock_guard` (line 1774) | MUTEX-GUARDED (dead code) | remove_if + erase — removes providers older than 1 hour. **No call site exists in entire codebase** (grep confirmed). |

**Total providers_ access sites:** 10 confirmed (9 live, 1 dead code). All well-guarded. `findProvider()` returns raw pointer — all callers hold the lock, but this pattern is fragile.

**Lock ordering verified:** `mutexRequestCallbacks_` → `mutexProviders_` via `processReceivedBlocks()` → `markProviderSuccess()`. No reverse ordering exists.

---

### Config Members: `maxPeerAttempts_` and `peerFailureThreshold_`

**Declaration:** `bitswap.hpp:344-345`
**Status:** **FLAGGED** — mixed protection. Setter methods have no lock. Readers inconsistently protected.

#### `maxPeerAttempts_` — `size_t` — Access Sites

| # | Method | File:Line | Lock Held? | Classification | Notes |
|---|--------|-----------|-----------|---------------|-------|
| 1 | `SetMaxPeerAttempts()` | `bitswap.cpp:1616-1619` | **NO** | **FLAGGED** | Direct assignment — data race if concurrent with any read |
| 2 | `requestBlockWithProviders()` | `bitswap.cpp:1809` | **NO** | **FLAGGED** | Read without lock — torn read possible on 32-bit platforms |
| 3 | `requestBlockWithProvidersFromRoot()` | `bitswap.cpp:1854` | **NO** | **FLAGGED** | Read without lock |
| 4 | `selectBestProvider()` | `bitswap.cpp:1713` | `mutexProviders_` | GUARDED (partial) | Read under provider lock — safe for this path |

**3 of 4 access sites have NO lock. Severity: HIGH.**

#### `peerFailureThreshold_` — `int` — Access Sites

| # | Method | File:Line | Lock Held? | Classification | Notes |
|---|--------|-----------|-----------|---------------|-------|
| 1 | `SetPeerFailureThreshold()` | `bitswap.cpp:1621-1624` | **NO** | **FLAGGED** | Direct assignment — data race if concurrent with any read |
| 2 | `selectBestProvider()` | `bitswap.cpp:1680` | `mutexProviders_` | GUARDED (partial) | Read under provider lock — safe for this path |
| 3 | `markProviderFailure()` | `bitswap.cpp:1737` | `mutexProviders_` | GUARDED (partial) | Read under provider lock — safe for this path |

**2 of 3 access sites have a lock (partial protection). Write site unprotected. Severity: HIGH.**

---

### Unprotected State (FLAGGED)

#### `cacheDir_` — `std::string` — **CRITICAL**

| # | Method | File:Line | Thread Context | Lock Held? | Type |
|---|--------|-----------|---------------|-----------|------|
| 1 | `setCacheDir()` | `bitswap.cpp:1908-1914` | **Any** (public API) | **NO** | WRITE |
| 2 | `getCacheDir()` | `bitswap.cpp:1917-1920` | **Any** (public API) | **NO** | READ |
| 3 | `buildDiskIndex()` | `bitswap.cpp:1924` | Main init thread | **NO** | READ |
| 4 | `persistBlock()` | `bitswap.cpp:1965` | Various (via storeBlock → call chain) | **NO** | READ |
| 5 | `tryLoadFromDisk()` | `bitswap.cpp:2047` | **libp2p thread** + consumer (via const_cast) | **NO** | READ |
| 6 | `cidToFilePath()` | `bitswap.cpp:1960` | Various (called from persistBlock, tryLoadFromDisk, unpersistBlock) | **NO** | READ |
| 7 | `unpersistBlock()` | `bitswap.cpp:2011` | Unknown (API available) | **NO** | READ |

**7 access sites across 4 thread contexts (main init, libp2p thread, io_context, detached thread). ZERO lock protection. Severity: CRITICAL — data race on std::string can cause corruption, crashes, or incorrect file paths.**

#### `started_` — `bool` — **LOW**

| # | Method | File:Line | Thread Context | Lock Held? | Type |
|---|--------|-----------|---------------|-----------|------|
| 1 | `start()` | `bitswap.cpp:220-221` | Main init thread | **NO** (BOOST_ASSERT guard) | WRITE |

**Written once during initialization (main thread). Internal use only — no external readers. BOOST_ASSERT prevents double-start. Severity: LOW — not a concurrency risk in practice, but undocumented assumption.**

---

## Findings — `mutexBlockStore_` Domain

### Finding F-01: Detached Thread Access to Shared State

| Attribute | Value |
|-----------|-------|
| **Severity** | **HIGH** |
| **Category** | Thread Confusion |
| **Confidence** | **CONFIRMED** |
| **Location** | `bitswap.cpp:1354-1431` |

**Description:** `PublishFile()` (line 1354-1388) and `PublishDirectory()` (line 1391-1431) both create `std::thread(...).detach()` that capture `this` and access `blockStore_` and `publishedContent_` under `mutexBlockStore_`. While the lock is held for the duration of the data structure access, the detached threads:

1. Cannot be joined or coordinated — the caller has no way to know when publishing completes
2. Multiple publishes create multiple parallel detached threads competing for `mutexBlockStore_`
3. Detached threads bypass the io_context — they are not part of the Asio strand model
4. If the Bitswap object is destroyed while a detached thread is still running, the `this` capture becomes a dangling pointer → **use-after-free**

**Evidence:**
- `bitswap.cpp:1358`: `std::thread(...).detach()` — PublishFile
- `bitswap.cpp:1395`: `std::thread(...).detach()` — PublishDirectory
- `bitswap.cpp:1369`: `lock_guard( mutexBlockStore_ )` inside detached lambda
- `bitswap.cpp:1406`: `lock_guard( mutexBlockStore_ )` inside detached lambda

**Recommended Fix:** Replace detached threads with `boost::asio::post(context_, ...)` to serialize publish work on the io_context strand.

---

### Finding F-02: const_cast Mutation of Shared State

| Attribute | Value |
|-----------|-------|
| **Severity** | **HIGH** |
| **Category** | Async Safety |
| **Confidence** | **CONFIRMED** |
| **Location** | `bitswap.cpp:1481-1502` |

**Description:** `GetBlock()` is declared `const` (line 1481) but uses `const_cast<Bitswap*>(this)->tryLoadFromDisk(cid)` at line 1492 to mutate `blockStore_`. `tryLoadFromDisk()` modifies `blockStore_` (emplace at line 2084-2093) and potentially `diskIndex_` (erase at line 2071). This violates const-correctness which is the implicit thread-safety contract in C++ — callers expect `const` methods to be safe for concurrent access from multiple threads.

The `HasBlock()` method at line 1466 also has a similar pattern: it checks `blockStore_` under lock, then calls `diskIndex_.count()` under `mutexDiskIndex_`, but does NOT use const_cast to tryLoadFromDisk — so HasBlock is actually safe despite the misleading name.

**Evidence:**
- `bitswap.cpp:1481`: `GetBlock() const`
- `bitswap.cpp:1492`: `const_cast<Bitswap*>(this)->tryLoadFromDisk(cid)`
- `bitswap.cpp:2084-2093`: `tryLoadFromDisk()` → `blockStore_.emplace(...)` under `mutexBlockStore_`

**Recommended Fix:** Remove `const` from `GetBlock()` — make mutation explicit. Or pre-load blocks on a separate non-const code path. Option (a) requires updating external callers.

---

### Finding F-03: tryLoadFromDisk Gap in handleWantlistRequest

| Attribute | Value |
|-----------|-------|
| **Severity** | **LOW** |
| **Category** | Documentation Gap |
| **Confidence** | **CONFIRMED** |
| **Location** | `bitswap.cpp:1309-1331` |

**Description:** `handleWantlistRequest()` at line 1312-1318 acquires `mutexBlockStore_`, checks `blockStore_.find()`, and if not found, releases the lock and calls `tryLoadFromDisk()` at line 1321. Between the lock release and the `tryLoadFromDisk()` call, another thread may load the same block into `blockStore_` (e.g., via concurrent `GetBlock()` or `storeBlock()`). The second `blockStore_.find()` at line 1324 will find the block whether loaded by this call or the concurrent one. The result is redundant disk I/O but NO data corruption — the lock-protected find/emplace semantics prevent data races on the map itself.

This is a benign race condition: the outcome is deterministic (block is served) but the work performed may be duplicated. Not a data race — the lock_guard at line 1297 in `storeBlock()` and at line 2085 in `tryLoadFromDisk()` serialize the actual map mutations.

**Evidence:**
- `bitswap.cpp:1318`: lock released (scope block ends)
- `bitswap.cpp:1321`: `tryLoadFromDisk()` called without lock
- `bitswap.cpp:1323`: lock re-acquired for second find
- `bitswap.cpp:2084-2093`: `tryLoadFromDisk()` uses lock_guard for actual emplace

**Recommended Fix:** Document the benign nature of this gap. If optimization is desired, use a double-checked pattern with a try_lock or upgrade the sequence to hold the lock throughout.

---

## Lock Call-Chain Analysis

### Documented Lock Ordering

Only one nesting path exists in the codebase:

```
mutexRequestCallbacks_ ──→ mutexProviders_
```

**Path:** `processReceivedBlocks()` acquires `mutexRequestCallbacks_` (line 271), calls `markProviderSuccess()` which acquires `mutexProviders_` (line 1756). This is the only multi-mutex nesting in the entire Bitswap codebase.

**Reverse check:** No method acquires `mutexProviders_` first then `mutexRequestCallbacks_`. All provider methods run independently.

### Non-Nested Sequential Acquisitions

These mutex pairs are acquired in sequence (lock, release, next lock), never nested:

| Sequence | First Lock | Released? | Second Lock | In Method |
|----------|-----------|-----------|-------------|-----------|
| blockStore → diskIndex | `mutexBlockStore_` | Yes | `mutexDiskIndex_` | `storeBlock()`, `HasBlock()` |
| diskIndex → blockStore | `mutexDiskIndex_` | Yes | `mutexBlockStore_` | `tryLoadFromDisk()` |
| diskIndex → diskIndex | `mutexDiskIndex_` | Yes | `mutexDiskIndex_` | `buildDiskIndex()` (clear then populate) |
| providers → streams | `mutexProviders_` | Yes | `mutexActiveStreams_` | `requestBlockWithProviders()` → `RequestBlockWithRetry()` |

### Self-Deadlock Check

All locks use `std::lock_guard` (non-recursive). No method re-acquires its own mutex. No self-deadlock risk.

### Lock-Across-Async Analysis

| Method | Lock Held | Async Operation | Verdict |
|--------|-----------|----------------|---------|
| `messageSent()` | `mutexRequestCallbacks_` (line 324) | Released before `rw->read()` at line 339 | **SAFE** |
| `setupContentRequest()` | `mutexContentRequests_` (line 540) | Released before `ctx->timeout.async_wait()` at line 546 | **SAFE** |
| `RequestBlockWithRetry()` | `mutexActiveStreams_` (line 419) | Released before `host_.newStream()` at line 440 | **SAFE** |
| `processReceivedBlocks()` | `mutexRequestCallbacks_` (line 271) | `HandleResponse()` callbacks invoked at line 279 while lock held | **RE-ENTRANCY RISK** — if callback re-enters Bitswap and acquires mutexRequestCallbacks_, non-recursive mutex deadlock |

**Verdict:** No lock-across-async violations found. The `processReceivedBlocks()` callback invocation under lock is a re-entrancy risk, not an async violation — callbacks are synchronous but could re-enter Bitswap.

### Deadlock Risk Assessment

| Risk | Status |
|------|--------|
| Lock ordering deadlock | **None** — only 1 documented nesting, verified no reverse path |
| Self-deadlock (re-entrant) | **None** — all std::lock_guard, no re-acquisition of same mutex |
| Callback re-entrancy deadlock | **POSSIBLE** — if BlockCallback re-enters Bitswap (see Finding C-7 / F-04) |

---

## Boundary Crossing Matrix

### libp2p → Bitswap

| Entry Point | Caller | Thread Context | Bitswap Locks Acquired |
|------------|--------|---------------|----------------------|
| `Bitswap::handle()` | libp2p protocol handler dispatch | **libp2p dispatch thread** (assumed — not confirmed from libp2p source) | `mutexRequestCallbacks_`, `mutexProviders_`, `mutexBlockStore_`, `mutexDiskIndex_` |
| `Bitswap::onNewConnection()` | event bus `OnNewConnectionChannel` | **event bus dispatch thread** | none (lightweight — only logs connection state) |
| `Bitswap::processReceivedBlocks()` | `handle()` → libp2p read callback | **libp2p I/O thread** | `mutexRequestCallbacks_`, `mutexProviders_` |
| `bitswap.cpp:164-201` server read loop | `handle()` → async read completion | **libp2p I/O thread** (persistent) | Called from handle(), inherits same context |

**Key finding:** `Bitswap::handle()` and all async read continuations run on libp2p threads, NOT on Bitswap's `io_context`. This means all locks acquired in these paths are held on libp2p threads.

### Consumer (SuperGenius) → Bitswap

| Call Site | File:Line | Thread Context | Methods Called |
|-----------|-----------|---------------|---------------|
| Construction | `GeniusNode.cpp:1308` | Main initialization thread | `Bitswap()`, `initialize()`, `setCacheDir()`, `start()` (indirect via event bus) |
| Mirroring callback | `GeniusNode.cpp:754-805` | Processing service callback thread | `HasBlock()`, `RequestContent()` |
| Data availability | `processing_subtask_queue_accessor_impl.hpp:61` | Processing worker thread | `HasBlock()`, `GetBlock()`, `RequestBlock()` |
| Processing service | `processing_service.hpp:70` | Processing node thread | `RequestBlock()`, `RequestContent()` |
| FileManager | `GeniusNode.cpp:1317` | Various (FileManager thread) | `HasBlock()`, `RequestContent()` |

**Key finding:** Bitswap is shared via `shared_ptr<Bitswap>` across at least 4 SuperGenius subsystems. Each may call Bitswap from different threads — internals must be thread-safe.

### Bitswap → Consumer (Callbacks)

| Callback Type | Fires From | Thread Context | Severity |
|--------------|-----------|---------------|----------|
| `BlockCallback` | `BitswapRequestContext::HandleResponse()` | **libp2p thread** (via `processReceivedBlocks`) | Consumer must handle thread-safety |
| `BlockCallback` (timeout) | `BitswapRequestContext::HandleResponseTimeout()` | **Bitswap io_context** (via `deadline_timer`) | Different thread from normal callback! |
| `ContentCallback` | `checkContentRequestComplete()` | **libp2p thread** (via callback chain) | Consumer must handle thread-safety |
| `ContentCallback` (timeout) | `setupContentRequest::timeout` handler | **Bitswap io_context** | Different thread from normal callback! |
| `PublishCallback` | `PublishFile()` / `PublishDirectory()` | **DETACHED std::thread** | **HIGH severity** — detached thread identity unknown to consumer |

**Key finding:** Callbacks fire from 3 different thread contexts (libp2p thread, io_context, detached thread). Consumer code MUST handle thread-safety for all state accessed in callbacks.

### Bitswap → Filesystem

| Operation | Method | Thread Context | Protection |
|-----------|--------|---------------|------------|
| Write block to disk | `persistBlock()` | Various (called from `storeBlock()`) | `mutexDiskIndex_` for index only — **NO lock for filesystem I/O** |
| Read block from disk | `tryLoadFromDisk()` | libp2p thread + consumer (via const_cast) | `mutexDiskIndex_` for index, `mutexBlockStore_` for store |
| Build disk index | `buildDiskIndex()` | Main init thread only | `mutexDiskIndex_` for index |
| Remove block from disk | `unpersistBlock()` | Unknown | `mutexDiskIndex_` for index |

### Bitswap → RocksDB

**No direct boundary.** Bitswap uses flat files in `cacheDir_` for persistence, not RocksDB. The architectural doc's claim of a Bitswap→RocksDB boundary is incorrect. However, consumer callbacks in SuperGenius may store received blocks into RocksDB — that boundary is in the consumer's scope, not Bitswap's.

---

## Thread Entry-Point Inventory

Every function that can be called from outside Bitswap (public API or callback entry):

| Entry Point | Visibility | Called From | Thread Context(s) | Locks Acquired | Notes |
|------------|-----------|-------------|-------------------|---------------|-------|
| `Bitswap()` | public | Consumer | Main init thread | none | Constructor only |
| `initialize()` | public | Consumer | Main init thread | none (registers protocol handler, builds disk index via `buildDiskIndex()`) | |
| `start()` | public | Consumer | Main init thread | none (subscribes to event bus) | |
| `handle()` | public (BaseProtocol override) | libp2p | **libp2p dispatch thread** | `mutexRequestCallbacks_`, `mutexProviders_`, `mutexBlockStore_`, `mutexDiskIndex_` | |
| `onNewConnection()` | private | Event bus | **event bus dispatch thread** | none | |
| `RequestBlock()` | public | Consumer, self | **Any** | `mutexActiveStreams_`, `mutexRequestCallbacks_` | |
| `RequestBlockWithRetry()` | public | Consumer, self, retry timer | **Any** | `mutexActiveStreams_` | Retry timer runs on io_context |
| `RequestContent()` | public (2 overloads) | Consumer | **Any** | `mutexContentRequests_` | |
| `AddProvider()` | public | Consumer, self | **Any** | `mutexProviders_` | |
| `AddProviders()` | public | Consumer | **Any** | `mutexProviders_` (per item) | Loops `AddProvider()` |
| `RemoveProvider()` | public | Consumer | **Any** | `mutexProviders_` | |
| `GetProviders()` | public (const) | Consumer | **Any** | `mutexProviders_` | Returns copy |
| `ClearProviders()` | public | Consumer | **Any** | `mutexProviders_` | |
| `SetMaxPeerAttempts()` | public | Consumer | **Any** | **NONE — FLAGGED** | Data race |
| `SetPeerFailureThreshold()` | public | Consumer | **Any** | **NONE — FLAGGED** | Data race |
| `PublishFile()` | public | Consumer | **Any** (caller) + **DETACHED std::thread** (work) | `mutexBlockStore_` | Spawns detached thread |
| `PublishDirectory()` | public | Consumer | **Any** (caller) + **DETACHED std::thread** (work) | `mutexBlockStore_` | Spawns detached thread |
| `PublishData()` | public | Consumer | **Any** (inline) | `mutexBlockStore_` | Inline, no detach |
| `HasBlock()` | public (const) | Consumer | **Any** | `mutexBlockStore_`, `mutexDiskIndex_` | Safe |
| `GetBlock()` | public (const) | Consumer | **Any** | `mutexBlockStore_`, `mutexDiskIndex_` | **const_cast** mutates blockStore_ |
| `UnpublishContent()` | public | Consumer | **Any** | `mutexBlockStore_` | |
| `ListPublishedContent()` | public (const) | Consumer | **Any** | `mutexBlockStore_` | |
| `setCacheDir()` | public | Consumer | **Any** | **NONE — FLAGGED** | Data race |
| `getCacheDir()` | public (const) | Consumer | **Any** | **NONE — FLAGGED** | Data race |
| `buildDiskIndex()` | public | Consumer | Init thread | `mutexDiskIndex_` | |
| `persistBlock()` | public | Self (storeBlock) | **Any** | `mutexDiskIndex_` | |
| `unpersistBlock()` | public | Unknown | **Any** | `mutexDiskIndex_` | |
| `getProtocolId()` | public (const, override) | libp2p | **Any** | none | No state access |
| `messageSent()` | private (callback) | libp2p I/O thread | **libp2p I/O thread** | `mutexRequestCallbacks_` | |
| `cleanupStaleProviders()` | private | **NEVER CALLED** | — | `mutexProviders_` (dead code) | |

**Functions with ambiguous thread context:** `handle()`, `onNewConnection()`, `messageSent()` — all assume libp2p dispatch/I/O threads. This assumption needs verification from libp2p source code.

---

## Phase 3: Consumer Contract

Method-by-method thread-safety reference for Bitswap consumers (SuperGenius, AsyncIOManager). This is the canonical thread-safety reference for Bitswap consumers — every public method's threading contract, current synchronization coverage, and Phase 2 change impact are documented here.

| Method | Caller Thread Requirement | Callback Thread | Mutex/Atomic Guarantee | Phase 2 Change Summary |
|---|---|---|---|---|
| PublishFile | Any | Bitswap io_context (was: detached std::thread) | mutexBlockStore_ | io_context::post replaces detached thread |
| PublishDirectory | Any | Bitswap io_context (was: detached std::thread) | mutexBlockStore_ | io_context::post replaces detached thread |
| HasBlock | Any | N/A | mutexBlockStore_ + mutexDiskIndex_ | Unchanged |
| RequestContent | Any | libp2p thread (success) / io_context (timeout) | mutexContentRequests_ | Unchanged |
| GetBlock | Any | N/A | mutexBlockStore_ + mutexDiskIndex_ | const removed |
| setCacheDir | Called once before async ops begin | N/A | mutexCacheDir_ | Added mutex guard |
| getCacheDir | Caller's thread | N/A | mutexCacheDir_ | Added mutex guard |
| SetMaxPeerAttempts | Any | N/A | std::atomic | Plain → atomic |
| SetPeerFailureThreshold | Any | N/A | std::atomic | Plain → atomic |

---

## Strand Confinement Analysis

### ContentRequestContext — Strand Violation

`ContentRequestContext` (bitswap.hpp:121-167) has **NO internal mutex**. All fields are accessed directly.

| Field | Modified By | Thread |
|-------|------------|--------|
| `pendingCIDs` | `processUnixFSBlock()` | **libp2p thread** (via callback chain) |
| `completedCIDs` | `processUnixFSBlock()` | **libp2p thread** |
| `collectedFiles` | `assembleCompleteFile()`, `handleFileBlock()` | **libp2p thread** |
| `filesInProgress` | `handleFileBlock()`, `handleFileChunk()`, `assembleCompleteFile()` | **libp2p thread** |
| `cidToPath` | `handleFileBlock()`, `handleDirectoryBlock()` | **libp2p thread** |
| `chunkToCidIndex` | `processUnixFSBlock()` (via chunk registration) | **libp2p thread** |
| `requestQueue` | `processUnixFSBlock()` → `processRequestQueue()` | **libp2p thread** + **io_context** (delay timer) |
| `processingQueue` | `processRequestQueue()` | **libp2p thread** + **io_context** |
| `timedOut` | `setupContentRequest::timeout` handler | **Bitswap io_context** |
| `peerInfo` | `RequestContent()` | Caller thread |

**Race window:** `processUnixFSBlock()` runs on libp2p thread (via block result callback). The timeout handler at `bitswap.cpp:553-559` runs on io_context. These may execute concurrently, and `processingQueue` only serializes `processRequestQueue()` calls — it does NOT protect `pendingCIDs`, `completedCIDs`, `filesInProgress`, `cidToPath`, or other fields.

**Severity: HIGH** — multiple callbacks for the same `ContentRequestContext` may execute concurrently on libp2p thread and io_context, causing data races on all context fields.

**Fields at risk:** `pendingCIDs`, `completedCIDs`, `collectedFiles`, `filesInProgress`, `cidToPath`, `chunkToCidIndex`, `requestQueue`, `timedOut`.

### BitswapRequestContext — Timer Race

| Method | Thread | Fields Accessed |
|--------|--------|----------------|
| `HandleResponse()` | **libp2p thread** (via `processReceivedBlocks`) | `callbacks_`, `responseTimer_` |
| `HandleResponseTimeout()` | **Bitswap io_context** (via `deadline_timer`) | calls `HandleResponse()` → same fields |

**Race window:** If a block arrives via the protocol handler just as the deadline_timer fires, both `HandleResponse()` (libp2p) and `HandleResponseTimeout()` → `HandleResponse()` (io_context) may execute in parallel, both iterating and clearing `callbacks_` and modifying `responseTimer_`.

**Severity: MEDIUM** (SUSPECTED) — requires exact timing. Double callback invocation possible.

---

## Master Findings Summary

| # | Severity | Category | Location | Description | Evidence | Confidence |
|---|----------|----------|----------|-------------|----------|-----------|
| **C-1** | **CRITICAL** | Missing Lock | `cacheDir_` (bitswap.cpp:1908-1920, bitswap.hpp:338) | No synchronization on std::string. 7 read/write sites across 4 thread contexts. | `setCacheDir()` line 1908-1914: direct assignment, no lock. `getCacheDir()` line 1917-1920: direct return, no lock. All other methods read cacheDir_ without lock. | **CONFIRMED** |
| **C-2** | **HIGH** | Missing Lock | `maxPeerAttempts_`, `peerFailureThreshold_` (bitswap.cpp:1616-1624, bitswap.hpp:344-345) | Setters have no lock. Partial reader coverage under mutexProviders_. 3 of 4 maxPeerAttempts_ reads unprotected. | Setter direct assignment at line 1618, 1623. `requestBlockWithProviders()` reads maxPeerAttempts_ at line 1809 without lock. | **CONFIRMED** |
| **C-3** | **HIGH** | Thread Confusion | `PublishFile()`/`PublishDirectory()` (bitswap.cpp:1358, 1395) | Detached std::thread accesses blockStore_ and publishedContent_ under lock. Detached threads cannot be joined/coordinated. Multiple publishes → parallel detached threads → potential use-after-free if Bitswap destroyed. | Lines 1358-1388 (PublishFile), 1395-1431 (PublishDirectory). Both use `.detach()`. | **CONFIRMED** |
| **C-4** | **HIGH** | Async Safety | `GetBlock()` (bitswap.cpp:1481-1502) | const method uses `const_cast<Bitswap*>(this)->tryLoadFromDisk()` to mutate blockStore_. Violates const-correctness = thread-safety contract. | Line 1492: `const_cast<Bitswap*>(this)->tryLoadFromDisk(cid)`. | **CONFIRMED** |
| **C-5** | **HIGH** | Missing Lock | `ContentRequestContext` (bitswap.hpp:121-167) | No synchronization on context fields. Accessed from libp2p thread AND io_context. processingQueue flag only protects processRequestQueue() — not other fields. | `processUnixFSBlock()` modifies pendingCIDs, completedCIDs, filesInProgress, etc. on libp2p thread. Timeout handler modifies timedOut on io_context. | **CONFIRMED** |
| **C-6** | **MEDIUM** | Async Safety | `BitswapRequestContext` (bitswap.cpp:70-89) | HandleResponse() on libp2p thread races with HandleResponseTimeout() on io_context. Both access callbacks_ and responseTimer_. | `HandleResponseTimeout()` line 87-89 calls HandleResponse(). HandleResponse() line 79 iterates callbacks_. | **SUSPECTED** |
| **C-7** | **MEDIUM** | Async Safety | `processReceivedBlocks()` (bitswap.cpp:271-285) | Callback invoked while mutexRequestCallbacks_ held. If BlockCallback re-enters Bitswap and acquires mutexRequestCallbacks_, non-recursive mutex → deadlock. | Line 279: `itContext->second->HandleResponse(block)` under lock_guard. | **CONFIRMED** |
| **C-8** | **MEDIUM** | Documentation Gap | `cleanupStaleProviders()` (bitswap.cpp:1774-1805) | Defined but never called. Dead code. | Grep entire codebase: zero call sites. | **CONFIRMED** |
| **C-9** | **MEDIUM** | Thread Confusion | `Bitswap::handle()` (bitswap.cpp:123-216) | Server read loop runs on libp2p thread indefinitely. All handleWantlistRequest() calls run on this libp2p thread. Implicit threading contract — not documented. | Lines 164-201: recursive `setupServerRead` lambda captures shared_ptr and spins on libp2p thread. | **CONFIRMED** |
| **C-10** | **LOW** | Documentation Gap | 6 mutexes (bitswap.hpp:324-345) | Only one lock ordering documented (callbacks→providers). No comments on mutex domains or thread context assumptions. | Header file has zero lock documentation. | **CONFIRMED** |

**Summary:** 1 CRITICAL, 4 HIGH, 4 MEDIUM, 1 LOW. 9 CONFIRMED, 1 SUSPECTED.

---

## Atomic Operations Review

### Current State
- **ZERO `std::atomic` usage** in Bitswap source (`bitswap.hpp` + `bitswap.cpp`)
- `maxPeerAttempts_` (size_t) and `peerFailureThreshold_` (int) are plain types — candidates for atomic conversion (see C-2)
- No `std::atomic_flag`, `std::atomic_ref`, or `__atomic_*` primitives found

### Recommendation for Phase 2
1. Convert `maxPeerAttempts_` to `std::atomic<size_t>` — eliminates the 4-access-site mixed protection finding (C-2), simpler than extending mutex coverage
2. Convert `peerFailureThreshold_` to `std::atomic<int>` — same rationale
3. Default memory ordering: `std::memory_order_seq_cst` unless explicitly relaxed with performance benchmarking justification
4. No other candidates for atomic conversion identified — remaining shared state involves complex types (maps, strings, structs) that require mutex protection

---

*Audit started: 2026-07-08*
