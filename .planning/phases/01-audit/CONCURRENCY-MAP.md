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

*To be populated in Plan 02 — Task 2.*

### Domain: `mutexDiskIndex_`

*To be populated in Plan 02 — Task 2.*

### Domain: `mutexProviders_`

*To be populated in Plan 02 — Task 3.*

### Unprotected State (FLAGGED)

*To be populated in Plan 02 — Task 3.*

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

*To be populated in Plan 02 — Tasks 1-3.*

---

## Boundary Crossing Matrix

*To be populated in Plan 02 — Task 4.*

---

## Thread Entry-Point Inventory

*To be populated in Plan 02 — Task 5.*

---

## Strand Confinement Analysis

*To be populated in Plan 02 — Task 5.*

---

## Master Findings Summary

*To be populated in Plan 02 — Task 6.*

---

## Atomic Operations Review

*To be populated in Plan 02 — Task 6.*

---

*Audit started: 2026-07-08*
