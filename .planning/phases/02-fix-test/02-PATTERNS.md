# Phase 02: Fix & Test — PATTERNS.md

**Base refs:** CONTEXT.md, RESEARCH.md, CONCURRENCY-MAP.md (Phase 1), `thirdparty/ipfs-bitswap-cpp/src/bitswap.{hpp,cpp}`, `SuperGenius/test/src/`

---

## 1. Bitswap Source Changes (bitswap.hpp / bitswap.cpp)

### 1.1 Mutex Declaration Style

**Existing pattern** in `bitswap.hpp:324-346` — trailing underscore, no alignment to column:
```cpp
mutable std::mutex                                    mutexRequestCallbacks_;
mutable std::mutex                                    mutexContentRequests_;
mutable std::mutex                                                          mutexActiveStreams_;
mutable std::mutex              mutexBlockStore_;
mutable std::mutex         mutexDiskIndex_;
mutable std::mutex                       mutexProviders_;
```

| Element | Convention | Example |
|---------|-----------|---------|
| Keyword | `mutable std::mutex` | `mutable std::mutex mutexCacheDir_;` |
| Naming | `mutexCamelCase_` (trailing underscore, NO `m_` prefix) | `mutexProviders_` |
| Alignment | Inconsistent — whitespace padded per-member-block, not column-aligned across blocks | Line 324 vs 333 |
| Placement | Immediately above the guarded members, same member block | Lines 333-335 (mutex above blockStore_ + publishedContent_) |

**New mutex (C-1) — add after `cacheDir_` at line 338:**
```cpp
mutable std::mutex         mutexCacheDir_;
```

**New mutex (C-6) — add to `BitswapRequestContext` private section (line 112 area):**
```cpp
std::mutex mutex_;
```

### 1.2 Lock Guard Usage Patterns

**Existing pattern** in `bitswap.cpp` — RAII `std::lock_guard`, named `guard` or `guardName`:

```cpp
// bitswap.cpp:271 — unnamed guard pattern
std::lock_guard<std::mutex> callbacksGuard( mutexRequestCallbacks_ );

// bitswap.cpp:324 — guard name matches member
std::lock_guard<std::mutex> callbacksGuard( mutexRequestCallbacks_ );

// bitswap.cpp:1297 — simple guard
std::lock_guard<std::mutex> guard( mutexBlockStore_ );

// bitswap.cpp:1550 — simple guard
std::lock_guard<std::mutex> guard( mutexProviders_ );
```

| Element | Convention |
|---------|-----------|
| Type | `std::lock_guard<std::mutex>` |
| Variable name | `guard` or `memberGuard` (e.g., `callbacksGuard`) |
| Scope | Braced block — lock released at `}` |
| Rule | Never held across async calls or filesystem I/O |

**New guard patterns to follow (from RESEARCH.md):**
```cpp
// C-1: cacheDir_ guard (local copy before I/O)
std::string dirCopy;
{
    std::lock_guard<std::mutex> guard( mutexCacheDir_ );
    dirCopy = cacheDir_;
}
// use dirCopy for filesystem I/O...

// C-6: BitswapRequestContext guard
void BitswapRequestContext::HandleResponse( ... )
{
    std::lock_guard<std::mutex> guard( mutex_ );
    // body...
}
```

### 1.3 Atomic Member Usage (New Pattern — C-2)

**No existing atomics in bitswap.hpp.** First introduction:

```cpp
// In bitswap.hpp:344-345 (replacing size_t/int):
std::atomic<size_t> maxPeerAttempts_{3};
std::atomic<int>    peerFailureThreshold_{3};
```

**Read patterns in bitswap.cpp (per RESEARCH.md):**
```cpp
// Under lock (relaxed ordering sufficient)
p.failureCount < peerFailureThreshold_.load( std::memory_order_relaxed );

// Outside lock (acquire ordering)
attemptCount >= static_cast<int>( maxPeerAttempts_.load( std::memory_order_acquire ) );
```

**Write patterns:**
```cpp
maxPeerAttempts_.store( maxPeers, std::memory_order_release );
peerFailureThreshold_.store( threshold, std::memory_order_release );
```

### 1.4 boost::asio::post Usage Pattern (C-3)

**No existing `boost::asio::post` in bitswap.cpp.** Pattern derived from `AsyncIOManager/src/IPFSLoader.cpp:119-121` and bitswap's own async callback pattern:

**From IPFSLoader.cpp:119-121 (canonical pattern):**
```cpp
boost::asio::post( *ioc,
    [handle_read, ioc]()
    { handle_read( ioc, outcome::failure( Error::INVALID_URL ), false, false ); } );
```

**From bitswap.cpp:108-113 (existing shared_from_this capture pattern):**
```cpp
[weak_self = std::weak_ptr<Bitswap>( shared_from_this() )]( auto stream_result )
{
    if ( auto self = weak_self.lock() )
    {
        self->handle( std::move( stream_result ) );
    }
} );
```

**New pattern for C-3 (PublishFile/PublishDirectory):**
```cpp
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
            // ... blockStore_ access ...
        }
        self->logger_->info( "..." );
        callback( rootCID );
    } );
```

Key conventions:
- Capture `shared_from_this()` as `self` (not `ctx` for member-access clarity)
- `*context_` takes a `shared_ptr<io_context>` — dereference to get reference
- Lambda captures: `[self, args...]()` not `[this]`

### 1.5 boost::asio::dispatch Usage Pattern (C-5)

**No existing `boost::asio::dispatch` in bitswap.cpp.** Analogous to `post` but uses `dispatch` for inline execution when already on target executor:

```cpp
// C-5: wrapping libp2p-thread callbacks
RequestBlock( pi, cid,
    [this, ctx]( libp2p::outcome::result<std::string> blockResult )
    {
        boost::asio::dispatch( *context_,
            [this, ctx, blockResult = std::move( blockResult )]() mutable
            {
                if ( !blockResult )
                {
                    failContentRequest( *ctx, ... );
                    return;
                }
                processUnixFSBlock( ctx, ctx->rootCID, blockResult.value(), "" );
            } );
    } );
```

### 1.6 Doxygen Comment Style

**Existing pattern** in `bitswap.hpp:169-178`:
```cpp
/**
 * /bitswap/1.0.0 protocol implementation
 * Allows getting/serving blocks from/to remote peers
 */
class Bitswap : ...
```

**Method-level comments** in `bitswap.hpp:179-183`:
```cpp
/** Initialize and register protocol handlers (call after shared_ptr construction) */
void initialize();
```

**New lock documentation (C-10) format from RESEARCH.md:**
```cpp
/**
 * @name Request Callback Synchronization
 *
 * @mutex mutexRequestCallbacks_ — Guards requestContexts_ map.
 *   Lock ordering: mutexRequestCallbacks_ → mutexProviders_ (via markProviderSuccess).
 *   Held on: libp2p I/O thread (processReceivedBlocks, messageSent).
 *   Callbacks NOT invoked under this lock (C-7 fix).
 */
///@{
mutable std::mutex                                    mutexRequestCallbacks_;
std::map<CID, std::shared_ptr<BitswapRequestContext>> requestContexts_;
///@}
```

### 1.7 Const-Correctness Fix Pattern (C-4)

**Before** (`bitswap.hpp:215`):
```cpp
libp2p::outcome::result<std::string> GetBlock( const CID &cid ) const;
```

**After:**
```cpp
libp2p::outcome::result<std::string> GetBlock( const CID &cid );
```

**In bitswap.cpp:1492** — remove `const_cast<Bitswap*>(this)->`, replace with direct call:
```cpp
// Before:
if ( const_cast<Bitswap *>( this )->tryLoadFromDisk( cid ) )
// After:
if ( tryLoadFromDisk( cid ) )
```

### 1.8 Callback-Outside-Lock Pattern (C-7)

**Before** (`bitswap.cpp:271-285`) — callback invoked under lock:
```cpp
std::lock_guard<std::mutex> callbacksGuard( mutexRequestCallbacks_ );
auto itContext = requestContexts_.find( cid.value() );
if ( itContext != requestContexts_.end() )
{
    if ( auto remotePeer = stream->remotePeerId() )
    {
        markProviderSuccess( cid.value(), remotePeer.value() );
    }
    itContext->second->HandleResponse( block );
}
```

**After** — callback invoked outside lock:
```cpp
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
        ctx = itContext->second;
        requestContexts_.erase( itContext );
    }
}
if ( ctx )
{
    ctx->HandleResponse( block );
}
```

---

## 2. Test Infrastructure

### 2.1 GTest Fixture Patterns

**Pattern A: Simple TEST() (no fixture)** — `SuperGenius/test/src/base/blob_test.cpp:12`:
```cpp
#include "base/blob.hpp"
#include <gtest/gtest.h>

using namespace sgns::base;

/**
 * @given hex string
 * @when create blob object from this string using fromHex method
 * @then blob object is created and contains expected byte representation
 */
TEST(BlobTest, CreateFromValidHex) {
  std::string hex32 = "00ff";
  std::array<uint8_t, 2> expected{ 0, 255 };
  auto result = Blob<2>::fromHex(hex32);
  ASSERT_NO_THROW({
    auto blob = result.value();
    EXPECT_EQ(blob, expected);
  }) << "fromHex returned an error instead of value";
}
```

**Pattern B: Fixture with SetUp** — `SuperGenius/test/src/processing/processing_service_test_base.cpp:39-43`:
```cpp
class ProcessingServiceTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        // Initialize logging, databases, etc.
    }
    void TearDown() override { /* cleanup */ }
};
```

**Pattern C: Static SetUpTestSuite** — `SuperGenius/test/src/graphsync/pubsub_graphsync_test.cpp:58-87`:
```cpp
class PubsubGraphsyncTest : public ::testing::Test
{
protected:
    static void SetUpTestSuite()
    {
        // One-time initialization: logging system, etc.
        auto logSystem = std::make_shared<soralog::LoggingSystem>( ... );
        logSystem->configure();
        libp2p::log::setLoggingSystem( logSystem );
    }
    static void TearDownTestSuite() {}
};
```

**New bitswap fixture pattern (composite of B + C):**
```cpp
#include <gtest/gtest.h>
#include <memory>
#include <thread>
#include <boost/asio.hpp>
#include "stubs.hpp"
#include "bitswap.hpp"

using namespace sgns::ipfs_bitswap;

class BitswapTestBase : public ::testing::Test
{
protected:
    void SetUp() override
    {
        io_context_ = std::make_shared<boost::asio::io_context>();
        host_       = std::make_shared<StubHost>();
        bus_        = libp2p::event::Bus();    // default-constructable (bitswap.hpp:213)
        // Bitswap constructor: Bitswap(libp2p::Host&, libp2p::event::Bus&, shared_ptr<io_context>)
        bitswap_    = std::make_shared<Bitswap>( *host_, bus_, io_context_ );
        bitswap_->initialize();
        io_thread_  = std::thread( [this]() { io_context_->run(); } );
    }

    void TearDown() override
    {
        io_context_->stop();
        if ( io_thread_.joinable() )
        {
            io_thread_.join();
        }
    }

    std::shared_ptr<boost::asio::io_context> io_context_;
    std::thread                             io_thread_;
    std::shared_ptr<StubHost>               host_;
    libp2p::event::Bus                      bus_;
    std::shared_ptr<Bitswap>                bitswap_;
};
```

Key conventions for test fixtures:
- `SetUp()` / `TearDown()` overrides with `override` keyword
- `protected:` access for test-accessible members
- Members use trailing underscore `_` (matches bitwap source, NOT `m_` prefix)
- `shared_ptr<Bitswap>` for ownership (Bitswap inherits `enable_shared_from_this`)
- Background `io_thread_` running `io_context_->run()` for async completion

### 2.2 Multi-threaded Stress Test Patterns

**No existing concurrent stress test in `SuperGenius/test/src/`.** The mock tests in `processing_mock.hpp` use `std::thread` for sleep simulation (line 73, single-threaded).

**New pattern derived from RESEARCH.md + codebase threading conventions:**
```cpp
TEST_F( BitswapStressTest, ConcurrentAccessNoCrashes )
{
    constexpr int kNumThreads = 8;
    constexpr int kIterations = 100;
    std::atomic<int> errors{ 0 };

    auto worker = [&]( int threadId )
    {
        for ( int i = 0; i < kIterations; ++i )
        {
            try
            {
                bitswap_->HasBlock( dummyCid_ );
                bitswap_->setCacheDir( "/tmp/test_" + std::to_string( threadId ) );
                bitswap_->getCacheDir();
                bitswap_->SetMaxPeerAttempts( threadId % 5 + 1 );
                bitswap_->PublishData( smallData_, []( auto ) {} );
                bitswap_->AddProvider( dummyCid_, dummyPeerInfo_ );
                bitswap_->GetProviders( dummyCid_ );
                bitswap_->ListPublishedContent();
            }
            catch ( ... )
            {
                errors.fetch_add( 1 );
            }
        }
    };

    std::vector<std::thread> threads;
    for ( int t = 0; t < kNumThreads; ++t )
    {
        threads.emplace_back( worker, t );
    }
    for ( auto &t : threads )
    {
        t.join();
    }
    EXPECT_EQ( errors.load(), 0 );
}
```

### 2.3 Stub / Mock Patterns

**Pattern from `SuperGenius/test/src/crdt/crdt_custom_broadcaster.hpp:14-41`** — concrete class implementing abstract interface, with std::mutex for thread safety:
```cpp
namespace sgns::crdt
{
    class CustomBroadcaster : public Broadcaster
    {
    public:
        outcome::result<void> Broadcast( ... ) override;
        outcome::result<base::Buffer> Next() override;
        bool HasTopic(const std::string &topic) override;
        std::queue<std::string> listOfBroadcasts_;
    private:
        std::mutex mutex_;
    };
}
```

**Mock pattern from `SuperGenius/test/src/processing/processing_mock.hpp:20-60`** — inline method bodies, no separate .cpp:
```cpp
namespace sgns::test
{
    class SubTaskResultStorageMock : public SubTaskResultStorage
    {
    public:
        void AddSubTaskResult( const SGProcessing::SubTaskResult &subTaskResult ) override
        {
            auto [_, success] = results.insert( { subTaskResult.subtaskid(), subTaskResult } );
            // ...
        }
        // ...
    private:
        std::map<std::string, SGProcessing::SubTaskResult> results;
    };
}
```

**New stubs pattern (stubs.hpp / stubs.cpp):**
- `StubHost` inherits `libp2p::Host` — overrides `getRouter()`, `connectedness()`, `newStream()`, `setProtocolHandler()`; all others no-op
- `StubRouter` inherits `network::Router` — overrides `setProtocolHandler()` as no-op
- Declarations in `stubs.hpp`, implementations in `stubs.cpp` (separate .cpp matches `crdt_custom_broadcaster` pattern)

### 2.4 Test File Naming Conventions

**From `SuperGenius/test/src/`:**
| Pattern | Example |
|---------|---------|
| `{module}_test.cpp` | `blob_test.cpp`, `buffer_test.cpp`, `crdt_set_test.cpp` |
| `{component}_integration_test.cpp` | `globaldb_integration.cpp` |
| `{component}_mock.hpp` | `processing_mock.hpp` |
| `{component}_custom_broadcaster.hpp` | `crdt_custom_broadcaster.hpp` |

**New pattern for bitswap tests (from RESEARCH.md D-07):**
| File | Convention |
|------|-----------|
| `stubs.hpp` / `stubs.cpp` | Test utilities — no `_test` suffix |
| `concurrency_cache_dir_test.cpp` | `concurrency_{finding}_test.cpp` |
| `concurrency_stress_test.cpp` | `{scope}_test.cpp` |

These use `concurrency_` prefix (not `bitswap_`) because:
1. The test directory already scopes to bitswap (path = `SuperGenius/test/src/bitswap/`)
2. The prefix describes the test category (concurrency) not the module name
3. Precedence: `processing_result_durability_test.cpp` uses feature prefix, not module prefix

### 2.5 Doxygen Comment Style for Tests

**Pattern from `SuperGenius/test/src/base/blob_test.cpp:6-11`:**
```cpp
/**
 * @given hex string
 * @when create blob object from this string using fromHex method
 * @then blob object is created and contains expected byte representation of the
 * hex string
 */
TEST(BlobTest, CreateFromValidHex) {
```

**New pattern for concurrent tests:**
```cpp
/**
 * @given a Bitswap instance with cacheDir_ set, multiple threads
 * @when one thread calls setCacheDir while others call persistBlock/tryLoadFromDisk
 * @then no data races, no crashes, cacheDir_ values are consistent
 */
TEST_F(CacheDirConcurrencyTest, SetPersistRace) {
```

### 2.6 EXPECT_OUTCOME_TRUE / Outcome Macro Usage

**From `SuperGenius/test/testutil/outcome.hpp:13-58`:**
```cpp
EXPECT_OUTCOME_TRUE_1( expr )                      // success only, ignore value
EXPECT_OUTCOME_TRUE( val, expr )                   // success + extract value
EXPECT_OUTCOME_FALSE_1( expr )                     // failure only
EXPECT_OUTCOME_FALSE( val, expr )                  // failure + extract error
EXPECT_OUTCOME_EQ( expr, value )                   // success + value equality
```

**Bitswap-specific outcome types** declared in bitswap.hpp:351:
```cpp
OUTCOME_HPP_DECLARE_ERROR_2( sgns::ipfs_bitswap, BitswapError );
```

### 2.7 Wait Condition / Async Test Patterns

**From `SuperGenius/test/testutil/wait_condition.hpp:101-104`:**
```cpp
ASSERT_WAIT_FOR_CONDITION( condition, timeout, description, actual_duration );
EXPECT_WAIT_FOR_CONDITION( condition, timeout, description, actual_duration );
```

**Publish test pattern (C-3) — waiting for async io_context callback:**
```cpp
std::atomic<bool> callbackFired{ false };
CID resultCID;
bitswap_->PublishFile( testFilePath, [&]( libp2p::outcome::result<CID> cidResult )
{
    EXPECT_OUTCOME_TRUE( cid, cidResult );
    resultCID     = cid;
    callbackFired.store( true );
} );

// Give io_context time to process the posted work
int ticks = 0;
while ( !callbackFired.load() && ticks < 100 )
{
    std::this_thread::sleep_for( std::chrono::milliseconds( 10 ) );
    ++ticks;
}
ASSERT_TRUE( callbackFired.load() );
```

---

## 3. Build System

### 3.1 addtest() Pattern

**From `SuperGenius/cmake/functions.cmake:8-27`:**
```cmake
function(addtest test_name)
    add_executable(${test_name} ${ARGN})
    addtest_part(${test_name} ${ARGN})
    target_link_libraries(${test_name}
        GTest::gtest_main
        GTest::gmock_main
    )
    # ... xunit output, RUNTIME_OUTPUT_DIRECTORY ...
endfunction()
```

- `addtest()` accepts a target name + source files as `ARGN`
- Automatically links `GTest::gtest_main` and `GTest::gmock_main`
- Output goes to `${CMAKE_BINARY_DIR}/test_bin`

### 3.2 addtest() + target_link_libraries Usage

**Pattern A: Simple single-source test** — `SuperGenius/test/src/base/CMakeLists.txt:1-6`:
```cmake
addtest(buffer_test
    buffer_test.cpp
)
target_link_libraries(buffer_test
    buffer
)
```

**Pattern B: Multi-source test with mock** — `SuperGenius/test/src/crdt/CMakeLists.txt:1-30`:
```cmake
addtest(crdt_test
    crdt_hierarchical_key_test.cpp
    crdt_set_test.cpp
    crdt_custom_broadcaster.cpp
)
target_link_libraries(crdt_test
    crdt_datastore
    rocksdb
    ipfs-lite-cpp::cid
    Boost::headers
    Boost::filesystem
)
```

**Pattern C: Test with bitswap dependency** — `SuperGenius/test/src/processing/CMakeLists.txt:31-46`:
```cmake
addtest(processing_result_durability_test
    processing_result_durability_test.cpp
    processing_service_test_base.cpp
)
target_link_libraries(processing_result_durability_test
    processing_service
    ipfs-bitswap-cpp    # ← the link target name for bitswap
    logger
    Boost::headers
    p2p::p2p_logger
)
```

### 3.3 add_subdirectory() Pattern

**From `SuperGenius/test/src/CMakeLists.txt:1-23`:**
```cmake
add_subdirectory(account)
add_subdirectory(account_creation)
add_subdirectory(base)
add_subdirectory(mock)
add_subdirectory(bridge_e2e)
add_subdirectory(startup)
add_subdirectory(blockchain)
add_subdirectory(crdt)
add_subdirectory(crypto)
add_subdirectory(graphsync)
# ... etc (alphabetical ordering)
```

**New entry** — add `add_subdirectory(bitswap)` between `base` and `bridge_e2e` (alphabetical):
```cmake
add_subdirectory(base)
add_subdirectory(bitswap)    # ← new line
add_subdirectory(bridge_e2e)
```

### 3.4 New bitswap/CMakeLists.txt Template

**Composite of patterns A, B, C — stub library + per-finding tests:**
```cmake
# Stub library (shared across all bitswap tests)
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

# C-2: config atomics race
addtest(concurrency_config_test
    concurrency_config_test.cpp
)
target_link_libraries(concurrency_config_test
    bitswap_test_stubs
    ipfs-bitswap-cpp
)

# C-3: publish io_context::post
addtest(concurrency_publish_test
    concurrency_publish_test.cpp
)
target_link_libraries(concurrency_publish_test
    bitswap_test_stubs
    ipfs-bitswap-cpp
)

# C-4: GetBlock concurrent access
addtest(concurrency_get_block_test
    concurrency_get_block_test.cpp
)
target_link_libraries(concurrency_get_block_test
    bitswap_test_stubs
    ipfs-bitswap-cpp
)

# C-5: ContentRequestContext strand confinement
addtest(concurrency_content_request_test
    concurrency_content_request_test.cpp
)
target_link_libraries(concurrency_content_request_test
    bitswap_test_stubs
    ipfs-bitswap-cpp
)

# C-6: BitswapRequestContext timer race
addtest(concurrency_request_context_test
    concurrency_request_context_test.cpp
)
target_link_libraries(concurrency_request_context_test
    bitswap_test_stubs
    ipfs-bitswap-cpp
)

# C-7: callback re-entrancy guard
addtest(concurrency_callback_test
    concurrency_callback_test.cpp
)
target_link_libraries(concurrency_callback_test
    bitswap_test_stubs
    ipfs-bitswap-cpp
)

# Combined stress test
addtest(concurrency_stress_test
    concurrency_stress_test.cpp
)
target_link_libraries(concurrency_stress_test
    bitswap_test_stubs
    ipfs-bitswap-cpp
)
```

### 3.5 Common Link Dependencies

All bitswap test targets link:
- `bitswap_test_stubs` — the shared stub library
- `ipfs-bitswap-cpp` — the bitswap library under test

These are sufficient because:
- `ipfs-bitswap-cpp` already transitively pulls `libp2p`, `Boost::headers`, `ipfs-lite-cpp` via its thirdparty build target (`thirdparty/build/CommonTargets.CMake:489-519`)
- `GTest::gtest_main` and `GTest::gmock_main` are auto-linked by the `addtest()` macro
- The stub library provides the mock host/router implementation

---

## 4. File-to-Pattern Mapping Summary

| File | Role | Pattern Source |
|------|------|---------------|
| `bitswap.hpp` (MODIFIED) | Add mutex, atomic, lock docs | bitswap.hpp:324-346 (mutex style), bitswap.hpp:169-183 (Doxygen style) |
| `bitswap.cpp` (MODIFIED) | Add guards, post/dispatch, fix const_cast | bitswap.cpp:271-285 (lock guard), IPFSLoader.cpp:119-121 (post), bitswap.cpp:108 (shared_from_this) |
| `stubs.hpp` (NEW) | Test doubles (StubHost, StubRouter) | `SuperGenius/test/src/crdt/crdt_custom_broadcaster.hpp:14-41` (concrete mock) |
| `stubs.cpp` (NEW) | Stub implementations | `SuperGenius/test/src/processing/processing_service_test_base.cpp` (separate .cpp) |
| `concurrency_cache_dir_test.cpp` (NEW) | C-1: cacheDir_ mutex guard tests | `SuperGenius/test/src/base/blob_test.cpp` (TEST structure) |
| `concurrency_config_test.cpp` (NEW) | C-2: atomic config race tests | Same as above + RESEARCH.md stress patterns |
| `concurrency_publish_test.cpp` (NEW) | C-3: io_context::post tests | RESEARCH.md async wait pattern |
| `concurrency_get_block_test.cpp` (NEW) | C-4: GetBlock const fix tests | `SuperGenius/test/src/base/blob_test.cpp` |
| `concurrency_content_request_test.cpp` (NEW) | C-5: ContentRequestContext strand tests | RESEARCH.md dispatch pattern |
| `concurrency_request_context_test.cpp` (NEW) | C-6: BitswapRequestContext timer tests | RESEARCH.md mutex pattern |
| `concurrency_callback_test.cpp` (NEW) | C-7: callback-outside-lock guard tests | RESEARCH.md callback pattern |
| `concurrency_stress_test.cpp` (NEW) | Combined N-thread stress test | RESEARCH.md stress test pattern |
| `bitswap/CMakeLists.txt` (NEW) | Test target registration | `SuperGenius/test/src/crdt/CMakeLists.txt:1-30`, `base/CMakeLists.txt:1-6` |
| `test/src/CMakeLists.txt` (MODIFIED) | Add `add_subdirectory(bitswap)` | `SuperGenius/test/src/CMakeLists.txt:1-23` |

---

## PATTERN MAPPING COMPLETE
