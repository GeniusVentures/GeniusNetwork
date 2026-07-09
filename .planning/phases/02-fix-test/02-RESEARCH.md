# Phase 02: Fix & Test — RESEARCH.md

**Project:** Genius Network — IPFS Bitswap Thread Safety
**Phase:** 02 — Fix & Test
**Researcher:** gsd-phase-researcher
**Date:** 2026-07-08

---

## 1. Fix Implementation Strategies

All fixes target `thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp` and `bitswap.cpp`.  
Fix order per D-03: C-1 → C-2 → C-4 → C-3 → C-5 → C-6/C-7/C-8/C-9 → C-10.

### C-1 (CRITICAL): `cacheDir_` — Unsynchronized std::string

**Decision:** Mutex guard (not immutable-post-init).  
**Rationale:** `cacheDir_` is read by 7 methods across 4 thread contexts. The immutable-post-init approach is unsafe because `setCacheDir()` is a public API callable at any time; even if consumers currently call it only during init, the guard should be structural. A mutex is consistent with all 6 existing mutex domains in the class.

**Primitive:** `mutable std::mutex mutexCacheDir_` (add to `bitswap.hpp:338`, next to existing `cacheDir_` member).

**Code changes in `bitswap.hpp` (line 338 area):**
```cpp
// Add after line 338:
mutable std::mutex mutexCacheDir_;
```

**Code changes in `bitswap.cpp`:**

| # | Method | Current Line(s) | Fix |
|---|--------|-----------------|-----|
| 1 | `setCacheDir()` | 1908-1914 | Surround body with `std::lock_guard<std::mutex> guard(mutexCacheDir_);` |
| 2 | `getCacheDir()` | 1917-1920 | Surround with lock; return a copy of `cacheDir_` |
| 3 | `buildDiskIndex()` | 1924 | Read `cacheDir_` under lock (line 1924 empty check + line 1930 filesystem check). Lock once for entire build, release before directory iteration I/O. |
| 4 | `persistBlock()` | 1965, 1985, 1996 | Lock at entry to read `cacheDir_` (line 1965). Release before filesystem I/O (line 1985+). Keep `cacheDir_` value in a local copy to avoid holding lock across I/O. |
| 5 | `tryLoadFromDisk()` | 2045, 2065 | Lock at entry to read `cacheDir_` (line 2045). Release before filesystem I/O (line 2065+). Same local-copy pattern. |
| 6 | `cidToFilePath()` | 1960 (called from persistBlock, tryLoadFromDisk, unpersistBlock) | Callers already hold the lock or have a local copy. For standalone calls, lock `mutexCacheDir_`. |
| 7 | `unpersistBlock()` | 2011, 2022 | Lock at entry to read `cacheDir_` (line 2011). Release before filesystem I/O. |

**Key pattern:** `cacheDir_` must never be held across filesystem I/O (>microseconds). Use a local `std::string dirCopy = cacheDir_;` inside the lock scope, then release the lock and use the copy for all I/O operations.

**Note on buildDiskIndex (line 1937-1939):** The existing `mutexDiskIndex_` lock protects `diskIndex_`. The new `mutexCacheDir_` must be acquired *before* `mutexDiskIndex_` in this method. No other method acquires both, so this is a new nesting: `mutexCacheDir_ → mutexDiskIndex_`. Document this ordering.

---

### C-2 (HIGH): `maxPeerAttempts_` / `peerFailureThreshold_` — Unsynchronized config setters

**Decision:** Convert both to `std::atomic`.  
**Rationale:** Simpler than extending mutex coverage (which would require lock in `selectBestProvider` and `markProviderFailure` already holding `mutexProviders_`, creating a lock-ordering dependency). Atomics provide zero-overhead reads in the hot path (`selectBestProvider` is called per-request).

**Primitive changes in `bitswap.hpp:344-345`:**
```cpp
// Before:
size_t maxPeerAttempts_      = 3;
int    peerFailureThreshold_ = 3;

// After:
std::atomic<size_t> maxPeerAttempts_{3};
std::atomic<int>    peerFailureThreshold_{3};
```

**Code changes in `bitswap.cpp`:**

| # | Method | Line | Fix |
|---|--------|------|-----|
| 1 | `SetMaxPeerAttempts()` | 1618 | Change `maxPeerAttempts_ = maxPeers;` → `maxPeerAttempts_.store(maxPeers, std::memory_order_release);` |
| 2 | `SetPeerFailureThreshold()` | 1623 | Change `peerFailureThreshold_ = threshold;` → `peerFailureThreshold_.store(threshold, std::memory_order_release);` |
| 3 | `requestBlockWithProviders()` | 1809 | Change `maxPeerAttempts_` read → `maxPeerAttempts_.load(std::memory_order_acquire)` |
| 4 | `requestBlockWithProvidersFromRoot()` | 1854 | Same as #3 |
| 5 | `selectBestProvider()` | 1680 | Change `peerFailureThreshold_` read → `peerFailureThreshold_.load(std::memory_order_relaxed)` (already under `mutexProviders_`; relaxed sufficient) |
| 6 | `selectBestProvider()` | 1713 | Remove the `maxPeerAttempts_` read — this line `size_t candidateCount = std::max(static_cast<size_t>(1), reachableProviders.size() / 4);` does NOT use `maxPeerAttempts_`. Audit line 1713 confirmed no ref. |
| 7 | `markProviderFailure()` | 1737 | Change `peerFailureThreshold_` read → `peerFailureThreshold_.load(std::memory_order_relaxed)` (under `mutexProviders_`) |

**Memory ordering rationale:**
- `Set*` methods use `memory_order_release` to publish the write.
- `requestBlockWithProviders*` use `memory_order_acquire` since they read outside any lock.
- Methods under `mutexProviders_` use `memory_order_relaxed` — the mutex already provides acquire/release semantics. No need for stronger ordering inside an already-synchronized region.

---

### C-4 (HIGH): `GetBlock()` const_cast — Mutable access through const method

**Decision:** Remove `const` from `GetBlock()` declaration.  
**Rationale:** Per D-02, this is the lowest-risk HIGH fix. It makes the mutation explicit and restores the C++ const-correctness contract that was violated. Consumer code already treats `GetBlock()` as potentially side-effecting (it loads from disk).

**Header change in `bitswap.hpp:215`:**
```cpp
// Before:
libp2p::outcome::result<std::string> GetBlock( const CID &cid ) const;

// After:
libp2p::outcome::result<std::string> GetBlock( const CID &cid );
```

**Implementation change in `bitswap.cpp:1481`:**
```cpp
// Before:
libp2p::outcome::result<std::string> Bitswap::GetBlock( const CID &cid ) const

// After:
libp2p::outcome::result<std::string> Bitswap::GetBlock( const CID &cid )
```

**Impact on `bitswap.cpp:1492`:** Remove the `const_cast<Bitswap*>(this)->`, replace with direct `this->tryLoadFromDisk(cid);`.

**Consumer impact (Phase 3):**
- `SuperGenius/src/processing/processing_subtask_queue_accessor_impl.hpp` — check if callers have `const Bitswap&` or `const shared_ptr<Bitswap>`. If so, they need updating.
- `SuperGenius/src/account/GeniusNode.cpp` — Bitswap is held as `shared_ptr<Bitswap>`, so removing const is transparent for non-const shared_ptrs.
- No ripple to AsyncIOManager since it receives Blocks via Bitswap callbacks, not by calling `GetBlock()` directly.

---

### C-3 (HIGH): Detached `std::thread` in PublishFile/PublishDirectory

**Decision:** Replace `std::thread(...).detach()` with `boost::asio::post(context_, ...)` (D-04, D-05).  
**Rationale:** Serializes publish work on the existing io_context, eliminates use-after-free risk (shared_from_this lifetime), and makes the thread context predictable. Callback contract preserved (D-05) — fires on io_context instead of detached thread.

**Code changes in `bitswap.cpp`:**

**PublishFile (lines 1354-1389):**
```cpp
// Before (lines 1358-1388):
std::thread(
    [this, filePath, callback = std::move( onPublishCallback )]()
    {
        CID rootCID = encodeAndStoreFile( filePath );
        // ... blockStore_ access ...
        callback( rootCID );
    } )
    .detach();

// After:
auto self = shared_from_this();
boost::asio::post( *context_,
    [self, filePath, callback = std::move( onPublishCallback )]()
    {
        CID rootCID = self->encodeAndStoreFile( filePath );
        if ( rootCID.content_address.toBuffer().empty() )
        {
            callback( BitswapError::ENCODING_FAILURE );
            return;
        }
        {
            std::lock_guard<std::mutex> guard( self->mutexBlockStore_ );
            // ... same body as before, using self-> instead of this ...
        }
        self->logger_->info( ... );
        callback( rootCID );
    } );
```

**PublishDirectory (lines 1391-1432):** Same pattern — replace `std::thread(...).detach()` with `boost::asio::post(*context_, ...)` and capture `shared_from_this()`.

**Key details:**
- The lambda now captures `shared_from_this()` via `self`, guaranteeing the Bitswap object lives for the duration of the async work.
- The `mutexBlockStore_` lock_guard within the lambda body is unchanged — it still works correctly regardless of which thread owns the io_context.
- `callback()` invocations now fire on the io_context thread, not a detached thread. This is a thread-context change for consumers (documented in DOCS-01/DOCS-02).

**Removal of `#include <thread>`:** After this fix, `std::thread` is no longer used in bitswap.cpp. The `#include <thread>` at line 15 can be removed.

---

### C-5 (HIGH): ContentRequestContext — No synchronization on context fields

**Decision:** Strand confinement via `boost::asio::dispatch(context_, ...)` in all libp2p-thread callbacks that access `ContentRequestContext`.  
**Rationale:** The `ContentRequestContext` is a complex, deeply-nested call graph (processUnixFSBlock → handleFileBlock → processRequestQueue → RequestBlock → callback → processUnixFSBlock). A recursive mutex would work but introduces overhead and fragility. Strand confinement is more natural: `ContentRequestContext` already has io_context-driven operations (deadline_timer for timeout, delay timer for queue processing) — the only off-strand accesses come from libp2p callbacks.

**How strand confinement works for C-5:**

1. All `ContentRequestContext` field mutations are serialized by ensuring they run on the Bitswap io_context.
2. The timeout handler at `bitswap.cpp:546-561` already runs on io_context (via `deadline_timer::async_wait`).
3. The delay timer in `handleQueuedBlockResult()` at `bitswap.cpp:998-1007` already runs on io_context.
4. The libp2p thread callbacks (via `RequestBlock` → `messageSent` → `rw->read` → `processReceivedBlocks` → `HandleResponse`) invoke `processUnixFSBlock` on libp2p threads. These need to be dispatched to io_context.

**Code changes:**

**In `RequestContent(const PeerInfo&, ...)` (bitswap.cpp:356-367):** Wrap the block callback body in `boost::asio::dispatch()`:

```cpp
RequestBlock( pi, cid,
    [this, ctx]( libp2p::outcome::result<std::string> blockResult )
    {
        boost::asio::dispatch( *context_,
            [this, ctx, blockResult = std::move(blockResult)]() mutable
            {
                if ( !blockResult )
                {
                    failContentRequest( *ctx, static_cast<BitswapError>( blockResult.error().value() ) );
                    return;
                }
                processUnixFSBlock( ctx, ctx->rootCID, blockResult.value(), "" );
            } );
    } );
```

**In `RequestContent(const CID&, ...)` (bitswap.cpp:369-394):** Same dispatch wrapper around the callback body at lines 380-388.

**In `processRequestQueue()` (bitswap.cpp:929-973):** The `RequestBlock` callbacks at lines 946-960 and 964-966 need dispatch wrappers:

```cpp
RequestBlock( ctx->peerInfo.value(), nextCid,
    [this, ctx, nextCid]( libp2p::outcome::result<std::string> result )
    {
        boost::asio::dispatch( *context_,
            [this, ctx, nextCid, result = std::move(result)]() mutable
            {
                if ( !result && ctx->useProviders )
                {
                    ctx->processingQueue = false;
                    requestBlockWithProvidersFromRoot( ... );
                    return;
                }
                handleQueuedBlockResult( ctx, nextCid, std::move( result ) );
            } );
    } );
```

**In `requestBlockWithProviders()` fallback (bitswap.cpp:1826-1839):** The retry callback already calls `requestBlockWithProviders()` → `RequestBlock()` which goes through the dispatch chain. But to be safe, wrap the success callback too:
Actually, the retry callback at line 1838 calls `onBlockCallback(std::move(result))` directly. Since it's called from `RequestBlock` → `messageSent` which runs on libp2p thread, this ends up calling `processUnixFSBlock` on libp2p thread. This is already caught by the dispatch wrappers above.

**`processingQueue` flag:** This existing serialization flag at `bitswap.hpp:157` becomes redundant but is retained as an optimization — it prevents unnecessary queue pushes when already inside processRequestQueue. It's safe because all accesses are now on io_context (single-threaded or strand-serialized).

**Note:** `boost::asio::dispatch` is used instead of `post` — if the caller is already on the io_context, `dispatch` executes inline (no queueing delay). If the caller is on an external thread (libp2p), `dispatch` posts. This preserves latency for the common case where callbacks chain through io_context timers.

---

### C-6 (MEDIUM): BitswapRequestContext — Timer race between HandleResponse and HandleResponseTimeout

**Decision:** Add a `std::mutex mutex_` to `BitswapRequestContext`.  
**Rationale:** This is a simple struct with two entry points (`HandleResponse` and `HandleResponseTimeout`). A mutex is the smallest, simplest fix. Unlike ContentRequestContext, there's no deep call chain here — just iterate/clear `callbacks_` and cancel the timer.

**Code changes in `bitswap.hpp:104-118`:**

Add to `BitswapRequestContext` private section (line 112 area):
```cpp
std::mutex mutex_;
```

**Code changes in `bitswap.cpp`:**

| # | Method | Lines | Fix |
|---|--------|-------|-----|
| 1 | `HandleResponse()` | 77-85 | Wrap body in `std::lock_guard<std::mutex> guard(mutex_);` |
| 2 | `HandleResponseTimeout()` | 87-89 | Wrap body in `std::lock_guard<std::mutex> guard(mutex_);` |
| 3 | `AddCallback()` | 70-75 | Wrap body in `std::lock_guard<std::mutex> guard(mutex_);` |

**Why AddCallback needs the lock too:** `AddCallback()` is called from `messageSent()` which holds `mutexRequestCallbacks_`. Before the fix, `AddCallback()` is only accessible under `mutexRequestCallbacks_`, so single-threaded. After adding `mutex_`, `HandleResponse()` and `HandleResponseTimeout()` also acquire `mutex_`, so `AddCallback()` must acquire it too for consistency. This introduces a new lock ordering: `mutexRequestCallbacks_ → mutex_` (BitswapRequestContext's mutex). Document this.

**Lock ordering:** New nesting: `mutexRequestCallbacks_ → BitswapRequestContext::mutex_`. This is compatible with the existing `mutexRequestCallbacks_ → mutexProviders_` ordering (they share the outer lock but different inner locks, never nested in reverse).

---

### C-7 (MEDIUM): Callback invoked under mutexRequestCallbacks_ lock — Re-entrancy deadlock risk

**Decision:** Copy callbacks to a local variable under the lock, then invoke after releasing the lock.  
**Rationale:** The `processReceivedBlocks()` at line 279 calls `HandleResponse()` while holding `mutexRequestCallbacks_`. If a `BlockCallback` re-enters Bitswap (e.g., calls `RequestBlock()` again), it will try to acquire `mutexRequestCallbacks_` in `messageSent()`, causing a non-recursive mutex deadlock.

**Code change in `bitswap.cpp:271-285`:**

```cpp
// Before:
std::lock_guard<std::mutex> callbacksGuard( mutexRequestCallbacks_ );
auto itContext = requestContexts_.find( cid.value() );
if ( itContext != requestContexts_.end() )
{
    if ( auto remotePeer = stream->remotePeerId() )
    {
        markProviderSuccess( cid.value(), remotePeer.value() );  // nested mutexProviders_
    }
    itContext->second->HandleResponse( block );  // callback fires under lock
}

// After:
std::shared_ptr<BitswapRequestContext> ctx;
{
    std::lock_guard<std::mutex> callbacksGuard( mutexRequestCallbacks_ );
    auto itContext = requestContexts_.find( cid.value() );
    if ( itContext != requestContexts_.end() )
    {
        if ( auto remotePeer = stream->remotePeerId() )
        {
            markProviderSuccess( cid.value(), remotePeer.value() );
        }
        ctx = itContext->second;  // shared_ptr keeps it alive after lock release
        requestContexts_.erase( itContext );  // remove from map under lock
    }
}
if ( ctx )
{
    ctx->HandleResponse( block );  // callback fires WITHOUT lock held
}
```

**Key details:**
- `markProviderSuccess()` is still called under the lock (preserving the existing nesting: `mutexRequestCallbacks_ → mutexProviders_`).
- The context is erased from `requestContexts_` under the lock to prevent double-processing (a second block for the same CID arriving between lock release and callback would find no context and log a warning — acceptable behavior).
- `ctx` is a `shared_ptr<BitswapRequestContext>` — it keeps the request context alive until the callback completes, even though it's been removed from the map.

**Note on C-6 interaction:** After C-6 adds `mutex_` to `BitswapRequestContext`, the C-7 fix also eliminates the need to hold `mutexRequestCallbacks_` while acquiring `mutex_`. This simplifies the lock ordering to purely non-nested acquires.

---

### C-8 (MEDIUM): `cleanupStaleProviders()` — Dead code

**Decision:** Remove the method or mark it deprecated with a comment.  
**Rationale:** The method has zero call sites across the entire codebase. It's dead code that clutters the interface and may confuse future developers. If periodic cleanup is desired, it should be wired into the io_context via a timer — but that's feature work beyond this phase's scope.

**Option A (recommended):** Remove the method entirely from both `bitswap.hpp:307` (declaration) and `bitswap.cpp:1772-1805` (implementation).

**Option B (conservative):** Add a comment `// TODO: Wire to periodic timer on io_context` and leave the code in place. This avoids any risk of removing code that might be needed later.

**Recommendation:** Option A. The git history preserves the code if needed. Dead code in a thread-safety hardening pass is noise — removing it reduces the surface area for future audits.

---

### C-9 (MEDIUM): `handle()` server read loop on libp2p thread — Undocumented

**Decision:** Add a Doxygen comment on the `handle()` method documenting the thread contract.  
**Rationale:** The loop is correct behavior (Bitswap servers must continuously read wantlists from peers), but the thread assumption (libp2p dispatch/I/O thread) is undocumented. Adding a comment makes the threading contract explicit for future maintainers.

**Code change in `bitswap.hpp:183` (above or after the `handle()` declaration):**
```cpp
/**
 * @brief Handle an incoming Bitswap stream from a peer.
 *
 * Runs on the libp2p protocol dispatch thread. The server read loop
 * (recurring async reads for wantlist messages) also executes on
 * libp2p I/O threads via the ProtobufMessageReadWriter callback chain.
 *
 * All lock acquisitions in this path occur on libp2p threads, not on
 * the Bitswap io_context.
 */
void handle( libp2p::StreamAndProtocol stream_res ) override;
```

**Additional comment in `bitswap.cpp:163-201`** above the server read loop setup:
```cpp
// Server read loop: persists on the libp2p I/O thread via recursive
// async read continuations. Each completion re-arms the read for the
// next wantlist message from the peer. This thread identity is
// inherited from the libp2p protocol handler dispatch.
```

---

### C-10 (LOW): No lock documentation in header

**Decision:** Add structured Doxygen comments documenting every mutex domain.  
**Rationale:** Makes the concurrency model self-documenting, prevents future developers from introducing lock-ordering violations, and serves as the primary deliverable for DOCS-01.

**Format:** Each mutex+guarded-member group gets a block comment:

```cpp
/**
 * @name Request Callback Synchronization
 *
 * @mutex mutexRequestCallbacks_ — Guards requestContexts_ map.
 *   Lock ordering: mutexRequestCallbacks_ → mutexProviders_ (via markProviderSuccess).
 *   Lock ordering: mutexRequestCallbacks_ → BitswapRequestContext::mutex_ (via AddCallback).
 *   Held on: libp2p I/O thread (processReceivedBlocks, messageSent).
 *   Callbacks NOT invoked under this lock (C-7 fix).
 */
///@{
mutable std::mutex                                    mutexRequestCallbacks_;
std::map<CID, std::shared_ptr<BitswapRequestContext>> requestContexts_;
///@}

/**
 * @name Block Store Synchronization
 *
 * @mutex mutexBlockStore_ — Guards blockStore_ and publishedContent_ maps.
 *   Held on: caller thread, libp2p thread (handleWantlistRequest), io_context (publish work).
 *   NOT nested with any other mutex. Always released before async calls or filesystem I/O.
 */
///@{
mutable std::mutex              mutexBlockStore_;
std::map<CID, StoredBlock>      blockStore_;
std::map<CID, PublishedContent> publishedContent_;
///@}

/**
 * @name Content Request Synchronization
 *
 * @mutex mutexContentRequests_ — Guards contentRequests_ map.
 *   Held on: caller thread and io_context (timeout handler).
 *   NOT nested with other mutexes. Callbacks invoked under this lock (timeout path;
 *   re-entrancy risk noted — content callback should not re-enter Bitswap's request APIs).
 */
///@{
mutable std::mutex                                    mutexContentRequests_;
std::map<CID, std::shared_ptr<ContentRequestContext>> contentRequests_;
///@}

// ... same pattern for mutexActiveStreams_, mutexDiskIndex_, mutexProviders_, mutexCacheDir_

/**
 * @name Config Members
 *
 * @atomic maxPeerAttempts_ — Max provider selection attempts (C-2 fix).
 * @atomic peerFailureThreshold_ — Failure count before marking provider unreachable (C-2 fix).
 *   Read under mutexProviders_ in selectBestProvider/markProviderFailure (relaxed ordering sufficient).
 *   Read without mutex in requestBlockWithProviders* (acquire ordering).
 *   Written by Set* methods (release ordering).
 */
///@{
std::atomic<size_t> maxPeerAttempts_{3};
std::atomic<int>    peerFailureThreshold_{3};
///@}
```

---

## 2. Testing Strategy

### 2.1 Test Location & Build Integration

**Directory:** `SuperGenius/test/src/bitswap/` (new)  
**Files:**
- `CMakeLists.txt` — registers test targets via `addtest()`
- `stubs.hpp` / `stubs.cpp` — StubHost, StubRouter, common test utilities  
- `concurrency_cache_dir_test.cpp` — C-1: cacheDir_ race
- `concurrency_config_test.cpp` — C-2: atomic config race
- `concurrency_publish_test.cpp` — C-3: PublishFile/PublishDirectory io_context post
- `concurrency_get_block_test.cpp` — C-4: GetBlock concurrent access
- `concurrency_content_request_test.cpp` — C-5: ContentRequestContext strand confinement
- `concurrency_request_context_test.cpp` — C-6: BitswapRequestContext timer race
- `concurrency_callback_test.cpp` — C-7: Re-entrancy deadlock guard
- `concurrency_stress_test.cpp` — Combined multi-threaded stress test (exercises all fixes)

**Parent CMakeLists.txt registration:** Add to `SuperGenius/test/src/CMakeLists.txt`:
```cmake
add_subdirectory(bitswap)
```

### 2.2 Mock / Stub Strategy

**StubHost:** A minimal implementation of `libp2p::Host` that returns dummy values and no-ops for all methods not exercised by the test. Defined in `stubs.hpp`.

Key mock methods needed (the ones Bitswap actually calls):
- `getRouter()` → returns a StubRouter
- `connectedness()` → returns `CAN_NOT_CONNECT` (prevents actual network calls)
- `newStream()` → callback with error (prevents actual connections)
- `setProtocolHandler()` → no-op
- All other Host methods → no-op or default return

**StubRouter:** A minimal `network::Router` that provides `setProtocolHandler()` as a no-op.

**StubStream:** For tests that exercise the response-handling path.

**Event Bus:** Default-construct `libp2p::event::Bus` — the class has an implicit default constructor (`bitswap.hpp:213` confirms).

**Shared io_context:** Create `std::make_shared<boost::asio::io_context>()` and start a background worker thread for tests that need async completion.

**Note:** The libp2p already has `HostMock` at `thirdparty/libp2p/test/mock/libp2p/host/host_mock.hpp` using gmock. However, this is in the libp2p test tree, not exported as a reusable library. We create our own thin stub in the SuperGenius test tree to avoid cross-module mock dependencies.

### 2.3 GTest Fixture Design

**Base Fixture (`BitswapTestBase`):**
```cpp
class BitswapTestBase : public ::testing::Test {
protected:
    void SetUp() override {
        io_context_ = std::make_shared<boost::asio::io_context>();
        // StubHost and Bus creation
        // Bitswap construction via shared_ptr
    }
    void TearDown() override {
        io_context_->stop();
        if (io_thread_.joinable()) io_thread_.join();
    }

    std::shared_ptr<boost::asio::io_context> io_context_;
    std::thread io_thread_;
    StubHost host_;
    libp2p::event::Bus bus_;
    std::shared_ptr<Bitswap> bitswap_;
};
```

**Per-Finding Fixtures:**

| Finding | Fixture Name | Key Test Methods |
|---------|-------------|------------------|
| C-1 | `CacheDirConcurrencyTest` | `SetGetRace`, `SetPersistRace`, `BuildReadRace` |
| C-2 | `ConfigConcurrencyTest` | `SetWhileRequesting`, `SetWhileSelecting`, `TornReadCheck` |
| C-3 | `PublishConcurrencyTest` | `PublishFileCallbackContext`, `PublishDirectoryCallbackContext`, `MultiConcurrentPublish` |
| C-4 | `GetBlockConcurrencyTest` | `ConcurrentGetBlockSameCid`, `ConcurrentGetHasBlock` |
| C-5 | `ContentRequestConcurrencyTest` | `TimeoutDuringProcessing`, `MultiBlockConcurrentArrival` |
| C-6 | `RequestContextTimerTest` | `ResponseTimeoutDuringResponse`, `MultiCallbackConcurrentFire` |
| C-7 | `CallbackReentrancyTest` | `ReenterDuringCallback`, `NestedRequestFromCallback` |

**Combined Stress Fixture (`BitswapStressTest`):**
```cpp
class BitswapStressTest : public BitswapTestBase {
    // Spawns N threads (default 8), each performs M iterations (default 100)
    // of random Bitswap operations, checking invariants.
    // Operations: HasBlock, GetBlock, SetMaxPeerAttempts, setCacheDir,
    // getCacheDir, PublishData, AddProvider, GetProviders, ListPublishedContent.
};
```

### 2.4 Multi-threaded Stress Test Patterns

**Pattern: Hammer + Verify**

```cpp
TEST_F(BitswapStressTest, ConcurrentAccessNoCrashes) {
    constexpr int kNumThreads = 8;
    constexpr int kIterations = 100;
    std::atomic<bool> running{true};
    std::atomic<int> errors{0};

    auto worker = [&](int threadId) {
        for (int i = 0; i < kIterations && running; ++i) {
            try {
                bitswap_->HasBlock(dummyCid);
                bitswap_->setCacheDir("/tmp/test_" + std::to_string(threadId));
                bitswap_->getCacheDir();
                bitswap_->SetMaxPeerAttempts(threadId % 5 + 1);
                bitswap_->PublishData(smallData, [](auto) {});
                bitswap_->AddProvider(dummyCid, dummyPeerInfo);
                bitswap_->GetProviders(dummyCid);
                bitswap_->ListPublishedContent();
            } catch (...) {
                errors.fetch_add(1);
            }
        }
    };

    std::vector<std::thread> threads;
    for (int t = 0; t < kNumThreads; ++t) {
        threads.emplace_back(worker, t);
    }
    for (auto& t : threads) t.join();
    running = false;

    EXPECT_EQ(errors.load(), 0);
    // If we get here without crashing, test passes
}
```

**Pattern: Race Window Amplification**

For C-1 (cacheDir_): Hammer `setCacheDir` on one thread while `persistBlock` reads `cacheDir_` on another:
```cpp
std::atomic<bool> toggle{true};
auto setter = [&]() {
    for (int i = 0; i < 10000; ++i) {
        bitswap_->setCacheDir(i % 2 ? "/tmp/a" : "/tmp/b");
    }
};
auto reader = [&]() {
    for (int i = 0; i < 10000; ++i) {
        bitswap_->storeBlock(testCid, "test_data");
    }
};
// storeBlock -> persistBlock -> reads cacheDir_
```

**Pattern: Invariant Check**

For C-2 (config): Set config from multiple threads, then verify the last-written value is consistent:
```cpp
bitswap_->SetMaxPeerAttempts(42);
std::vector<std::future<size_t>> futures;
for (int t = 0; t < 8; ++t) {
    futures.push_back(std::async([&]() {
        bitswap_->SetMaxPeerAttempts(t + 1);
        return bitswap_->GetTotalProviderCount(); // indirectly validates no crash
    }));
}
// All threads complete without data race → pass
```

### 2.5 CMakeLists.txt for Bitswap Tests

```cmake
# SuperGenius/test/src/bitswap/CMakeLists.txt

# Stub library
add_library(bitswap_test_stubs STATIC
    stubs.cpp
)
target_include_directories(bitswap_test_stubs PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
)
target_link_libraries(bitswap_test_stubs PUBLIC
    ipfs-bitswap-cpp
    p2p::p2p_basic_host
    Boost::headers
)

# C-1: cacheDir_ race
addtest(concurrency_cache_dir_test
    concurrency_cache_dir_test.cpp
)
target_link_libraries(concurrency_cache_dir_test
    bitswap_test_stubs
    ipfs-bitswap-cpp
)
# ... repeat for each test file ...

# Combined stress test
addtest(concurrency_stress_test
    concurrency_stress_test.cpp
)
target_link_libraries(concurrency_stress_test
    bitswap_test_stubs
    ipfs-bitswap-cpp
)
```

---

## 3. Build System Impact

### 3.1 thirdparty/build/CommonTargets.CMake

**No changes required.** The `ipfs-bitswap-cpp` ExternalProject_Add target (lines 489-519) already:
- Has GTest as a dependency (`DEPENDS ... GTest ...`)
- Passes `-DGTest_DIR:PATH=${_FINDPACKAGE_GTEST_CONFIG_DIR}` for internal testing
- Passes `-DTESTING:BOOL=${TESTING}`

The fixes are source-only changes to `bitswap.hpp` and `bitswap.cpp` — no new files, dependencies, or build flags are needed at the thirdparty level.

### 3.2 SuperGenius/test/src/CMakeLists.txt

**Add one line:**
```cmake
add_subdirectory(bitswap)
```

### 3.3 New Files Created

| File | Purpose |
|------|---------|
| `SuperGenius/test/src/bitswap/CMakeLists.txt` | Test target registration |
| `SuperGenius/test/src/bitswap/stubs.hpp` | StubHost, StubRouter declarations |
| `SuperGenius/test/src/bitswap/stubs.cpp` | StubHost, StubRouter implementations |
| `SuperGenius/test/src/bitswap/concurrency_cache_dir_test.cpp` | C-1 tests |
| `SuperGenius/test/src/bitswap/concurrency_config_test.cpp` | C-2 tests |
| `SuperGenius/test/src/bitswap/concurrency_publish_test.cpp` | C-3 tests |
| `SuperGenius/test/src/bitswap/concurrency_get_block_test.cpp` | C-4 tests |
| `SuperGenius/test/src/bitswap/concurrency_content_request_test.cpp` | C-5 tests |
| `SuperGenius/test/src/bitswap/concurrency_request_context_test.cpp` | C-6 tests |
| `SuperGenius/test/src/bitswap/concurrency_callback_test.cpp` | C-7 tests |
| `SuperGenius/test/src/bitswap/concurrency_stress_test.cpp` | Combined stress test |

### 3.4 No Changes To

- `SuperGenius/cmake/functions.cmake` — `addtest()` macro already supports the pattern.
- Platform CMakeLists.txt files — no new platform-specific dependencies.
- CommonCompilerOptions.cmake — no new compiler flags needed.
- Any consumer CMakeLists — API changes in Phase 2 are source-compatible (const removal on GetBlock is the only signature change; callers already use non-const shared_ptr<Bitswap>).

---

## 4. Validation Architecture

Without TSAN, validation relies on three pillars:

### 4.1 Manual Code Review Checklist

Per finding, verify:
- [ ] Lock guard covers ALL access sites (grep the member name in `bitswap.cpp`, confirm every read/write is under the lock).
- [ ] Lock-guard scope does not extend across async calls or I/O operations.
- [ ] No new lock nesting introduced without documenting the order.
- [ ] No `shared_from_this()` calls inside detached threads (after C-3 fix).
- [ ] No `const_cast` remaining in method bodies (after C-4 fix).
- [ ] Callback invocation always outside lock scope (after C-7 fix).

### 4.2 Static Analysis (Manual Pattern Match)

**Checklist-driven grep commands:**
```bash
# Verify no unprotected cacheDir_ access remains
rg 'cacheDir_' thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp -n

# Verify no const_cast remains
rg 'const_cast' thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp -n

# Verify no std::thread remains
rg 'std::thread' thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp -n

# Verify every mutex is documented in header
rg 'mutex' thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp -n
```

### 4.3 Runtime Stress Tests

The GTest stress tests serve as regression detection:
- **Crash detection:** If a race causes a crash (segfault, std::map corruption), the stress tests will crash reliably under high concurrency (8 threads × 100 iterations).
- **Invariant violation:** Tests check that operations produce correct results (e.g., `GetBlock` returns the stored block, `GetProviders` returns the same count as `AddProvider` calls).
- **Deadlock detection:** Tests that exercise the callback chain (C-7, C-5) would hang if a deadlock is introduced. A 30-second timeout on each test provides passive deadlock detection.

### 4.4 Validation Matrix

| Fix | Manual Review | Grep Verification | Stress Test | Deadlock Test |
|-----|:---:|:---:|:---:|:---:|
| C-1 (cacheDir_ mutex) | ✓ | ✓ | ✓ | — |
| C-2 (config atomics) | ✓ | ✓ | ✓ | — |
| C-3 (io_context::post) | ✓ | ✓ | ✓ | — |
| C-4 (const-correctness) | ✓ | ✓ | ✓ | — |
| C-5 (strand dispatch) | ✓ | — | ✓ | ✓ |
| C-6 (request ctx mutex) | ✓ | — | ✓ | ✓ |
| C-7 (callback outside lock) | ✓ | — | ✓ | ✓ |
| C-8 (dead code removal) | ✓ | — | — | — |
| C-9 (thread doc) | ✓ | — | — | — |
| C-10 (lock doc) | ✓ | — | — | — |

---

## 5. Risk Assessment

### 5.1 Highest-Risk Fixes

| Rank | Finding | Risk | Mitigation |
|------|---------|------|------------|
| 1 | **C-5** (ContentRequestContext strand) | **HIGH** — Most complex fix. Touches 5+ callback sites. Could introduce deadlock if dispatch chains incorrectly, or drop blocks if dispatch is skipped for any path. | Dispatch only at 3 well-defined entry points (two `RequestContent` overloads, processRequestQueue callbacks). All other paths (timeout, delay timer) already on io_context. Use `dispatch` not `post` to preserve synchronization when already on io_context. |
| 2 | **C-7** (Callback outside lock) | **MEDIUM** — Removing the context from `requestContexts_` under lock changes the double-processing semantics. A second block for the same CID arriving between erase and callback invocation will find no context and be silently dropped (logged as warning). | Acceptable: IPFS blocks are content-addressed; a duplicate block is idempotent. The warning log is correct behavior. |
| 3 | **C-3** (io_context::post) | **MEDIUM** — Changes the thread context for PublishCallback. Consumer code that assumed callback fires on a fresh thread may be affected. | Documented in threading contract (DOCS-01). Phase 3 (CONS-01, CONS-02) will verify consumer compatibility. The callback still fires — only the thread identity changes. |
| 4 | **C-4** (const removal) | **LOW** — One-line signature change. Consumer callers already treat GetBlock as side-effecting (it loads from disk). No behavior change. | Phase 3 verification needed only if consumers use `const Bitswap&` (unlikely — Bitswap is held as shared_ptr<Bitswap>). |
| 5 | **C-1** (cacheDir_ mutex) | **LOW** — Adds lock overhead on filesystem operations. Lock held for minimal scope (read cacheDir_, release before I/O). | Acceptable: filesystem I/O dominates any lock overhead by orders of magnitude. |

### 5.2 Deadlock Introduction Risks

| Scenario | Risk | Pre-Mitigation |
|----------|------|---------------|
| C-1: `mutexCacheDir_ → mutexDiskIndex_` in buildDiskIndex vs reverse | **LOW** — Only buildDiskIndex acquires both. No other method acquires both. | Document the ordering. Verify no reverse path exists via grep. |
| C-6: `mutexRequestCallbacks_ → BitswapRequestContext::mutex_` in messageSent → AddCallback vs HandleResponse outside | **LOW** — Only AddCallback acquires both. HandleResponse acquires only the inner lock. | Document the ordering. Since C-7 removes the HandleResponse-from-under-callbacks-lock path, there's no way to hold both in reverse. |
| C-5: dispatch from io_context calls back into io_context handler | **NONE** — `boost::asio::dispatch` executes inline when already on the target executor. The `processingQueue` flag prevents recursive queue processing. | Existing safeguards verified. |

### 5.3 Behavioral Change Risks

| Finding | Behavioral Change | Consumer Impact |
|---------|------------------|-----------------|
| C-1 | None — `cacheDir_` values still readable, writable. | Transparent. |
| C-2 | None — atomic loads/stores have the same observable value as plain reads/writes on x64 (the target platform). | Transparent. |
| C-3 | PublishCallback now fires on io_context thread, not detached thread. | Consumers that assumed detached-thread context need checking. Most callbacks just log or update UI — thread context is irrelevant. |
| C-4 | `GetBlock()` is no longer `const`. | Any code taking `const Bitswap&` and calling GetBlock needs updating. |
| C-5 | Content request callbacks now fire on io_context. Previously fired on libp2p thread. | Consumers that assumed libp2p-thread context need checking. Most content callbacks just store data — thread context is irrelevant. |
| C-6 | None — the mutex serializes concurrent access but the external behavior is identical. | Transparent. |
| C-7 | Duplicate block arrivals for the same CID no longer invoke callbacks (silently dropped). Previously they would fire again. | Acceptable: content-addressed blocks are idempotent by definition. |

---

## 6. API Impact (Phase 3 Forewarning)

### 6.1 Signature Changes

| API | Change | Consumer Files Affected |
|-----|--------|------------------------|
| `GetBlock()` | `const` removed | `SuperGenius/src/processing/processing_subtask_queue_accessor_impl.hpp` (call site at line ~61) |

### 6.2 Threading Contract Changes

| Callback | Old Thread | New Thread | Consumer Files Affected |
|----------|-----------|------------|------------------------|
| `PublishCallback` | Detached `std::thread` | Bitswap `io_context` | `SuperGenius/src/account/GeniusNode.cpp` (any publish callbacks registered) |
| Content `BlockCallback` (via `RequestContent`) | libp2p I/O thread | Bitswap `io_context` | `SuperGenius/src/processing/processing_service.hpp` (line ~70), `SuperGenius/src/account/GeniusNode.cpp` (line ~754-805) |

### 6.3 No API Surface Changes For

- `PublishFile()` / `PublishDirectory()` — same parameters, same callback signature  
- `SetMaxPeerAttempts()` / `SetPeerFailureThreshold()` — same signatures, underlying type changed to `std::atomic` (ABI-compatible with plain type)  
- All provider methods, content request methods, block request methods — no signature changes  
- `setCacheDir()` / `getCacheDir()` — same signatures  

### 6.4 Build System No-Ops

None of the fixes change the ipfs-bitswap-cpp library's exported target name, include paths, or link dependencies. All consumer builds will continue to work without CMake changes.

---

## 7. Summary: Research Complete

### Fix Summary

| # | Fix | Lines Changed | New Primitive | Risk |
|---|-----|:---:|---|:---:|
| C-1 | Add `mutexCacheDir_` + guard 7 access sites | ~15 | `mutable std::mutex` | LOW |
| C-2 | Convert 2 members to `std::atomic` + update 7 access sites | ~10 | `std::atomic<size_t>`, `std::atomic<int>` | LOW |
| C-4 | Remove `const` from `GetBlock()` | 2 | none | LOW |
| C-3 | Replace `std::thread::detach()` with `boost::asio::post()` | ~20 | none | MEDIUM |
| C-5 | Add `boost::asio::dispatch()` wrappers at 3 callback entry points | ~30 | none | HIGH |
| C-6 | Add `mutex_` to `BitswapRequestContext`, guard 3 methods | ~15 | `std::mutex` | LOW |
| C-7 | Move `HandleResponse()` invocation outside `mutexRequestCallbacks_` scope | ~15 | none | MEDIUM |
| C-8 | Remove `cleanupStaleProviders()` dead code | ~35 | none | NONE |
| C-9 | Add Doxygen comment on `handle()` | 10 | none | NONE |
| C-10 | Add lock documentation to header | ~50 | none | NONE |

**Total estimated lines changed:** ~200 (across bitswap.hpp and bitswap.cpp).

### Test Summary

- **7 per-finding fixtures** + 1 combined stress test = **8 test files**
- **1 stub library** (`stubs.hpp/cpp`) for Host/Router mocks
- **1 new CMakeLists.txt** for test target registration
- **1 line added** to `SuperGenius/test/src/CMakeLists.txt`

### Build System Changes

- **thirdparty/build/CommonTargets.CMake:** No changes.
- **SuperGenius/cmake/functions.cmake:** No changes.
- **ipfs-bitswap-cpp CMake files:** No changes.
- **Consumer CMake files:** No changes (Phase 3 task).

---

## RESEARCH COMPLETE
