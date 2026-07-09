---
phase: 2
plan: 1
type: fix_test
wave: 1
depends_on: []
files_modified:
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp
  - SuperGenius/test/src/CMakeLists.txt
  - SuperGenius/test/src/bitswap/CMakeLists.txt (NEW)
  - SuperGenius/test/src/bitswap/stubs.hpp (NEW)
  - SuperGenius/test/src/bitswap/stubs.cpp (NEW)
  - SuperGenius/test/src/bitswap/concurrency_cache_dir_test.cpp (NEW)
  - SuperGenius/test/src/bitswap/concurrency_config_test.cpp (NEW)
  - SuperGenius/test/src/bitswap/concurrency_publish_test.cpp (NEW)
  - SuperGenius/test/src/bitswap/concurrency_get_block_test.cpp (NEW)
autonomous: false
requirements:
  - FIX-01
  - FIX-02
  - FIX-03
  - FIX-04
  - TEST-02
---

# Plan 1: Wave 1 — CRITICAL + Simple HIGH Fixes (C-1, C-2, C-4, C-3)

**Coverage:** FIX-01 (C-1 cacheDir_ mutex, C-2 config atomics), FIX-02 (C-3 detached threads), FIX-03 (C-2 atomic ordering), FIX-04 (C-3 io_context::post). TEST-02: 4 per-finding concurrency test files + shared stubs/infrastructure.

**Must-Haves:**
- MH-01: `cacheDir_` has a `mutable std::mutex mutexCacheDir_` guard in bitswap.hpp and all 7 access sites in bitswap.cpp are locked
- MH-02: `maxPeerAttempts_` and `peerFailureThreshold_` are `std::atomic` with correct memory ordering at all 7 access sites
- MH-03: `GetBlock()` is non-const, `const_cast` removed
- MH-04: PublishFile/PublishDirectory use `boost::asio::post(*context_, ...)` instead of `std::thread(...).detach()`
- MH-05: Stubs and 4 concurrency test files build and link, covering C-1, C-2, C-3, C-4 race scenarios
- MH-06: `SuperGenius/test/src/CMakeLists.txt` has `add_subdirectory(bitswap)` entry

---

## Task 1: C-1 — Add mutexCacheDir_ and guard all cacheDir_ access sites

<read_first>
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp (lines 337-340 — cacheDir_ and mutexDiskIndex_ member block)
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (lines 1908-1920 setCacheDir/getCacheDir, 1924-1955 buildDiskIndex, 1958-1961 cidToFilePath, 1963-2006 persistBlock, 2009-2041 unpersistBlock, 2043-2097 tryLoadFromDisk)
  - .planning/phases/02-fix-test/02-RESEARCH.md (C-1 section, lines 17-43 — fix implementation strategy, mutex name, lock-and-copy pattern)
  - .planning/phases/02-fix-test/02-PATTERNS.md (lines 10-39 — mutex declaration style, lines 40-79 lock guard pattern)
</read_first>

<action>
**In bitswap.hpp (after line 338 — right after `cacheDir_;`):**
Add new member: `mutable std::mutex mutexCacheDir_;` — positioned between `cacheDir_` (line 338) and `mutexDiskIndex_` (line 339). Since cacheDir_ and mutexDiskIndex_ are in the same member block, follow the existing alignment near line 337 where `mutexDiskIndex_` uses padding whitespace.

**In bitswap.cpp — guard all 7 access sites:**

1. `setCacheDir()` (lines 1908-1914): Wrap body in `std::lock_guard<std::mutex> guard(mutexCacheDir_);`. Assignment to `cacheDir_` and logger call stay inside.

2. `getCacheDir()` (lines 1917-1920): Replace `return cacheDir_;` with local-copy pattern: lock, copy to local, return copy.

3. `buildDiskIndex()` (lines 1922-1955): Lock `mutexCacheDir_` at entry, copy `cacheDir_` to local `dirCopy`, release lock. Use `dirCopy` for all filesystem operations and logger calls. The existing `mutexDiskIndex_` guards remain unchanged. **Lock ordering:** `mutexCacheDir_` is acquired BEFORE `mutexDiskIndex_` in this method. No other method acquires both, so this is a new documented nesting: `mutexCacheDir_ → mutexDiskIndex_`.

4. `persistBlock()` (lines 1963-2006): At entry (before line 1965), lock `mutexCacheDir_`, copy `cacheDir_` to local `dirCopy`, release lock. Use `dirCopy` for empty check at line 1965, filesystem ops at lines 1985-1996, and cidToFilePath call at line 1996.

5. `tryLoadFromDisk()` (lines 2043-2097): At entry (before line 2045), lock, copy `cacheDir_` to local, release. Use local for empty check at line 2045 and cidToFilePath at line 2065.

6. `cidToFilePath()` (lines 1958-1961): At entry, lock `mutexCacheDir_`, read `cacheDir_`, construct path, return path (value copy). Lock released at return.

7. `unpersistBlock()` (lines 2009-2041): At entry (before line 2011), lock, copy `cacheDir_` to local, release. Use local for empty check at line 2011 and cidToFilePath at line 2022.
</action>

<acceptance_criteria>
  - bitswap.hpp contains declaration `mutable std::mutex         mutexCacheDir_;` positioned between `cacheDir_` (line 338) and `mutexDiskIndex_` (line 339)
  - bitswap.cpp: `setCacheDir()` body is wrapped in `std::lock_guard<std::mutex> guard(mutexCacheDir_);`
  - bitswap.cpp: `getCacheDir()` uses lock + local copy pattern (not direct return of `cacheDir_`)
  - bitswap.cpp: `buildDiskIndex()` reads `cacheDir_` under lock once, uses local copy for all I/O
  - bitswap.cpp: `persistBlock()`, `tryLoadFromDisk()`, `cidToFilePath()`, `unpersistBlock()` each lock `mutexCacheDir_` at entry, copy to local, release before I/O
  - Grep: `rg 'cacheDir_' thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp -n` — every line reading/writing `cacheDir_` appears within a `mutexCacheDir_` lock_guard scope (or uses a local copy taken under lock)
</acceptance_criteria>

---

## Task 2: C-2 — Convert maxPeerAttempts_ and peerFailureThreshold_ to std::atomic

<read_first>
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp (lines 342-345 — providers member block with maxPeerAttempts_ and peerFailureThreshold_)
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (lines 1616-1619 SetMaxPeerAttempts, 1621-1624 SetPeerFailureThreshold, 1667-1725 selectBestProvider, 1729-1752 markProviderFailure, 1807-1814 requestBlockWithProviders, 1849-1861 requestBlockWithProvidersFromRoot)
  - .planning/phases/02-fix-test/02-RESEARCH.md (C-2 section, lines 48-78 — memory ordering decisions, 7 access sites)
  - .planning/phases/02-fix-test/02-PATTERNS.md (lines 81-104 — atomic member usage patterns)
</read_first>

<action>
**In bitswap.hpp (lines 344-345):**
Change `size_t maxPeerAttempts_ = 3;` to `std::atomic<size_t> maxPeerAttempts_{3};`
Change `int peerFailureThreshold_ = 3;` to `std::atomic<int> peerFailureThreshold_{3};`

**In bitswap.cpp — update 7 access sites:**

1. `SetMaxPeerAttempts()` (line 1618): Change `maxPeerAttempts_ = maxPeers;` to `maxPeerAttempts_.store(maxPeers, std::memory_order_release);`

2. `SetPeerFailureThreshold()` (line 1623): Change `peerFailureThreshold_ = threshold;` to `peerFailureThreshold_.store(threshold, std::memory_order_release);`

3. `requestBlockWithProviders()` (line 1809): Change `static_cast<int>(maxPeerAttempts_)` to `static_cast<int>(maxPeerAttempts_.load(std::memory_order_acquire))`

4. `requestBlockWithProviders()` (line 1811 — logger line): Change `maxPeerAttempts_` to `maxPeerAttempts_.load(std::memory_order_acquire)`

5. `requestBlockWithProvidersFromRoot()` (line 1854): Change `static_cast<int>(maxPeerAttempts_)` to `static_cast<int>(maxPeerAttempts_.load(std::memory_order_acquire))`

6. `requestBlockWithProvidersFromRoot()` (line 1857 — logger line): Change `maxPeerAttempts_` to `maxPeerAttempts_.load(std::memory_order_acquire)`

7. `selectBestProvider()` (line 1680): Change `p.failureCount < peerFailureThreshold_` to `p.failureCount < peerFailureThreshold_.load(std::memory_order_relaxed)` (already under `mutexProviders_`)

8. `markProviderFailure()` (line 1737): Change `peerFailureThreshold_` to `peerFailureThreshold_.load(std::memory_order_relaxed)` (already under `mutexProviders_`)
</action>

<acceptance_criteria>
  - bitswap.hpp:344 reads `std::atomic<size_t> maxPeerAttempts_{3};`
  - bitswap.hpp:345 reads `std::atomic<int> peerFailureThreshold_{3};`
  - bitswap.cpp:1618 uses `maxPeerAttempts_.store(maxPeers, std::memory_order_release)`
  - bitswap.cpp:1623 uses `peerFailureThreshold_.store(threshold, std::memory_order_release)`
  - bitswap.cpp:1809, 1854 read maxPeerAttempts_ via `.load(std::memory_order_acquire)`
  - bitswap.cpp:1680, 1737 read peerFailureThreshold_ via `.load(std::memory_order_relaxed)` inside mutexProviders_ lock scope
  - No plain `maxPeerAttempts_` or `peerFailureThreshold_` reads/writes remain without `.load()` or `.store()`
</acceptance_criteria>

---

## Task 3: C-4 — Remove const from GetBlock() and eliminate const_cast

<read_first>
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp (line 215 — GetBlock declaration with `const`)
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (lines 1481-1502 — GetBlock implementation with `const_cast`)
  - .planning/phases/02-fix-test/02-RESEARCH.md (C-4 section, lines 82-109)
  - .planning/phases/02-fix-test/02-PATTERNS.md (lines 209-227 — const-correctness fix pattern)
</read_first>

<action>
**In bitswap.hpp (line 215):**
Change `libp2p::outcome::result<std::string> GetBlock( const CID &cid ) const;` to `libp2p::outcome::result<std::string> GetBlock( const CID &cid );` — remove trailing `const`.

**In bitswap.cpp (line 1481):**
Change `libp2p::outcome::result<std::string> Bitswap::GetBlock( const CID &cid ) const` to `libp2p::outcome::result<std::string> Bitswap::GetBlock( const CID &cid )` — remove trailing `const`.

**In bitswap.cpp (line 1492):**
Change `if ( const_cast<Bitswap *>( this )->tryLoadFromDisk( cid ) )` to `if ( tryLoadFromDisk( cid ) )` — remove the const_cast wrapper.
</action>

<acceptance_criteria>
  - bitswap.hpp:215 reads `libp2p::outcome::result<std::string> GetBlock( const CID &cid );` (no trailing `const`)
  - bitswap.cpp:1481 reads `Bitswap::GetBlock( const CID &cid )` (no trailing `const`)
  - bitswap.cpp:1492 reads `if ( tryLoadFromDisk( cid ) )` (no `const_cast`)
  - Grep: `rg 'const_cast' thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` returns zero matches
</acceptance_criteria>

---

## Task 4: C-3 — Replace detached std::thread with boost::asio::post in PublishFile and PublishDirectory

<read_first>
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (lines 1354-1389 PublishFile, 1391-1432 PublishDirectory)
  - .planning/phases/02-fix-test/02-RESEARCH.md (C-3 section, lines 113-159)
  - .planning/phases/02-fix-test/02-PATTERNS.md (lines 106-153 — boost::asio::post pattern with shared_from_this capture)
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp (line 321 — context_ is `shared_ptr<boost::asio::io_context>`)
</read_first>

<action>
**In PublishFile() (lines 1354-1388):**
Replace the entire `std::thread(...).detach()` block (lines 1358-1388) with:
- Capture `auto self = shared_from_this();` before the post call (required: Bitswap inherits `enable_shared_from_this`)
- `boost::asio::post(*context_, [self, filePath, callback = std::move(onPublishCallback)](){ ... });`
- Lambda body preserves the exact same logic: call `self->encodeAndStoreFile(filePath)`, check rootCID, lock guard on `self->mutexBlockStore_` for block lookup and publishedContent_ emplace, logger calls, callback invocation. Use `self->` for all member access instead of `this->`.
- Remove the `// PublishFile` placeholder comment from the async lambda (replace the entire body from `std::thread(` through `.detach();`).

**In PublishDirectory() (lines 1391-1431):**
Same replacement pattern — `auto self = shared_from_this(); boost::asio::post(*context_, [self, directoryPath, callback = std::move(onPublishCallback)](){ ... });` with `self->` member access.

**Remove `#include <thread>` (line 15):** After both PublishFile and PublishDirectory are converted, `std::thread` is no longer used in bitswap.cpp. Delete `#include <thread>` at line 15 of bitswap.cpp.
</action>

<acceptance_criteria>
  - bitswap.cpp:1358 area contains `auto self = shared_from_this();` followed by `boost::asio::post( *context_,` for PublishFile
  - bitswap.cpp:1395 area contains `auto self = shared_from_this();` followed by `boost::asio::post( *context_,` for PublishDirectory
  - PublishFile/PublishDirectory lambdas capture `self` (shared_ptr) not raw `this`
  - PublishCallback invocation inside the io_context-posted lambda is unchanged in signature and semantics
  - Grep: `rg 'std::thread' thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` returns zero matches
  - bitswap.cpp no longer has `#include <thread>` (line 15 removed)
  - Grep: `rg '#include <thread>' thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` returns zero matches
</acceptance_criteria>

---

## Task 5: Create test stubs (StubHost, StubRouter) for Bitswap test fixtures

<read_first>
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp (lines 173-177 — Bitswap constructor: takes `libp2p::Host&`, `libp2p::event::Bus&`, `shared_ptr<io_context>`)
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp (line 213 — `libp2p::event::Bus` is default-constructible)
  - .planning/phases/02-fix-test/02-RESEARCH.md (lines 437-454 — StubHost/StubRouter mock strategy, key methods to implement)
  - .planning/phases/02-fix-test/02-PATTERNS.md (lines 423-462 — stub patterns from crdt_custom_broadcaster and processing_mock)
  - SuperGenius/test/src/crdt/crdt_custom_broadcaster.hpp (concrete stub implementing abstract interface)
</read_first>

<action>
**In SuperGenius/test/src/bitswap/stubs.hpp (NEW):**
Create `StubHost` class inheriting from `libp2p::Host` and `StubRouter` class implementing `network::Router`.

StubHost must override these methods called by Bitswap:
- `getRouter()` → returns reference to the StubRouter instance
- `connectedness(const PeerInfo&)` → returns `libp2p::Host::Connectedness::CAN_NOT_CONNECT` (prevents actual network calls)
- `newStream(const PeerInfo&, const Protocol&, StreamResultFunc)` → invokes callback with error
- `setProtocolHandler(const std::vector<Protocol>&, ProtocolHandlerFunc)` → no-op (store handler if desired)
- All remaining pure virtual methods → no-op or default return value (stub them minimally to compile)

StubRouter:
- `setProtocolHandler(const std::vector<Protocol>&, ProtocolHandlerFunc)` → no-op

**In SuperGenius/test/src/bitswap/stubs.cpp (NEW):**
Implement the method bodies for StubHost and StubRouter. Keep implementations thin — override just enough to satisfy libp2p::Host's pure virtual interface.
</action>

<acceptance_criteria>
  - SuperGenius/test/src/bitswap/stubs.hpp exists, declares `StubHost : public libp2p::Host` and `StubRouter : public network::Router`
  - SuperGenius/test/src/bitswap/stubs.cpp exists with implementations
  - StubHost::getRouter() returns a StubRouter reference
  - StubHost::connectedness() returns CAN_NOT_CONNECT
  - StubHost::newStream() fires callback with an error outcome
  - All other pure virtual methods of libp2p::Host have minimal stub bodies (no-op or default)
</acceptance_criteria>

---

## Task 6: Create CMakeLists.txt for bitswap test targets

<read_first>
  - SuperGenius/cmake/functions.cmake (lines 1-30 — addtest() macro definition)
  - SuperGenius/test/src/crdt/CMakeLists.txt (pattern B and C — stub library + test targets + target_link_libraries)
  - .planning/phases/02-fix-test/02-PATTERNS.md (lines 647-732 — CMakeLists.txt template for bitswap tests)
  - .planning/phases/02-fix-test/02-RESEARCH.md (lines 577-611 — CMakeLists.txt for Bitswap Tests section)
</read_first>

<action>
**In SuperGenius/test/src/bitswap/CMakeLists.txt (NEW):**
1. Define `bitswap_test_stubs` STATIC library from `stubs.cpp`
2. `target_include_directories(bitswap_test_stubs PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})` so test files can `#include "stubs.hpp"`
3. `target_link_libraries(bitswap_test_stubs PUBLIC ipfs-bitswap-cpp p2p::p2p_basic_host Boost::headers)`
4. Register these test targets via `addtest()`:
   - `concurrency_cache_dir_test` (C-1)
   - `concurrency_config_test` (C-2)
   - `concurrency_publish_test` (C-3)
   - `concurrency_get_block_test` (C-4)
5. Each test target links `bitswap_test_stubs` and `ipfs-bitswap-cpp`

Exact template (one test registration pattern, repeat for each file):
```cmake
addtest(concurrency_cache_dir_test
    concurrency_cache_dir_test.cpp
)
target_link_libraries(concurrency_cache_dir_test
    bitswap_test_stubs
    ipfs-bitswap-cpp
)
```
Repeat for concurrency_config_test, concurrency_publish_test, concurrency_get_block_test.

**In SuperGenius/test/src/CMakeLists.txt (line 3 area):**
Add `add_subdirectory(bitswap)` — place alphabetically between `base` (line 3) and `bridge_e2e` (line 5). No other lines changed.
</action>

<acceptance_criteria>
  - SuperGenius/test/src/bitswap/CMakeLists.txt exists with add_library(bitswap_test_stubs ...) and 4 addtest() calls
  - SuperGenius/test/src/CMakeLists.txt contains `add_subdirectory(bitswap)` between `add_subdirectory(base)` and `add_subdirectory(bridge_e2e)`
  - bitswap_test_stubs links ipfs-bitswap-cpp, p2p::p2p_basic_host, Boost::headers
  - Each addtest() target links bitswap_test_stubs and ipfs-bitswap-cpp
</acceptance_criteria>

---

## Task 7: C-1 test — cacheDir_ concurrency test (concurrency_cache_dir_test.cpp)

<read_first>
  - SuperGenius/test/src/base/blob_test.cpp (line 1-30 — GTest TEST/TEST_F pattern, includes, Doxygen @given/@when/@then)
  - .planning/phases/02-fix-test/02-PATTERNS.md (lines 336-364 — BitswapTestBase fixture with SetUp/TearDown, io_context thread, StubHost)
  - .planning/phases/02-fix-test/02-RESEARCH.md (lines 544-558 — Race Window Amplification pattern for C-1)
  - .planning/codebase/TESTING.md (lines 111-156 — GTest fixture patterns with SetUp/TearDown)
</read_first>

<action>
**In SuperGenius/test/src/bitswap/concurrency_cache_dir_test.cpp (NEW):**
Create a `CacheDirConcurrencyTest` fixture inheriting `BitswapTestBase` (defined in stubs.hpp). Test cases:

1. `SetGetRace`: Start one thread calling `setCacheDir("/tmp/a")` in a loop while another thread calls `getCacheDir()` in a loop. Run for 10000 iterations. Verify no crash.

2. `SetPersistRace`: Set cacheDir, then run one thread calling `setCacheDir` alternating between two paths while another thread calls `storeBlock` → triggers `persistBlock` which reads cacheDir_. Run 1000 iterations. Verify no crash.

3. `BuildReadRace`: Set cacheDir to a valid temp directory with a test file. Run one thread calling `buildDiskIndex()` while another reads `getCacheDir()`. Run 100 iterations. Verify no crash and `getCacheDir()` returns consistent values.

4. `MultiThreadedCache`: Spawn 8 threads, each doing random set/get/persist/unpersist operations for 500 iterations. Verify thread join succeeds without exceptions or crashes.

Use `std::atomic<bool>` for start/stop signaling. All test methods must include `@given`/`@when`/`@then` Doxygen comments. Include `"stubs.hpp"`, `<gtest/gtest.h>`, `<thread>`, `<atomic>`, `<vector>`.
</action>

<acceptance_criteria>
  - concurrency_cache_dir_test.cpp exists with `CacheDirConcurrencyTest` fixture and 4 test methods
  - Each test method has Doxygen `@given`/`@when`/`@then` comment block
  - Tests compile with the CML targets, link to bitswap_test_stubs and ipfs-bitswap-cpp
  - All tests complete without crash (pass/fail status may vary without a mock I/O filesystem, but no segfault/exception escape)
</acceptance_criteria>

---

## Task 8: C-2 test — config atomic concurrency test (concurrency_config_test.cpp)

<read_first>
  - .planning/phases/02-fix-test/02-RESEARCH.md (lines 560-573 — Invariant Check pattern for C-2)
  - .planning/phases/02-fix-test/02-PATTERNS.md (lines 374-419 — stress test patterns)
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp (lines 203-204 — SetMaxPeerAttempts and SetPeerFailureThreshold public API)
</read_first>

<action>
**In SuperGenius/test/src/bitswap/concurrency_config_test.cpp (NEW):**
Create a `ConfigConcurrencyTest` fixture inheriting `BitswapTestBase`. Test cases:

1. `ConcurrentSetAndRead_NoCrash`: 4 threads each calling `SetMaxPeerAttempts(tid+1)` in a loop for 5000 iterations. Verify no crash.

2. `WriteDuringRead_ConsistentValues`: 2 writer threads setting different values + 2 reader threads calling `GetTotalProviderCount()` (which reads under providers lock). Verify no crash, all threads join.

3. `StressConfigAccess`: 8 threads hammering `SetMaxPeerAttempts`, `SetPeerFailureThreshold`, `GetTotalProviderCount`, and `GetProviderDebugInfo` concurrently for 1000 iterations each. Verify no crashes.

Use `@given`/`@when`/`@then` Doxygen comments on all test methods.
</action>

<acceptance_criteria>
  - concurrency_config_test.cpp exists with `ConfigConcurrencyTest` fixture and 3 test methods
  - Each test method has Doxygen comment block
  - Tests compile and link correctly
  - All tests complete without crash under concurrent access
</acceptance_criteria>

---

## Task 9: C-3 test — publish io_context::post concurrency test (concurrency_publish_test.cpp)

<read_first>
  - .planning/phases/02-fix-test/02-RESEARCH.md (lines 533-552 — async wait pattern for PublishFile callback)
  - .planning/phases/02-fix-test/02-PATTERNS.md (lines 532-552 — wait condition / async test patterns with std::atomic<bool> callbackFired)
  - SuperGenius/test/testutil/wait_condition.hpp (ASSERT_WAIT_FOR_CONDITION macro if available)
</read_first>

<action>
**In SuperGenius/test/src/bitswap/concurrency_publish_test.cpp (NEW):**
Create a `PublishConcurrencyTest` fixture inheriting `BitswapTestBase`. Test cases:

1. `PublishFileCallbackOnIoContext`: Call `PublishFile` with a test file, verify the callback fires (use `std::atomic<bool> callbackFired` with timeout-based wait loop). The callback should complete — this validates that io_context::post works and the callback fires correctly.

2. `PublishDirectoryCallbackOnIoContext`: Same pattern for `PublishDirectory`.

3. `PublishDataCallbackInvoked`: Verify `PublishData` callback fires inline (PublishData is synchronous, not converted — it serves as baseline).

4. `MultiConcurrentPublish`: Spawn 4 threads each calling `PublishData` (synchronous) + 2 threads calling `PublishFile` (async via io_context::post). Run 20 iterations. Verify all threads complete, all PublishFile callbacks fire.

Use `@given`/`@when`/`@then` Doxygen comments on all test methods. For async tests, use a polling loop with `std::this_thread::sleep_for(10ms)` up to 100 ticks (1 second timeout).
</action>

<acceptance_criteria>
  - concurrency_publish_test.cpp exists with `PublishConcurrencyTest` fixture and 4 test methods
  - Each test method has Doxygen comment block
  - PublishFile/PublishDirectory async tests use atomic flag + timeout loop to wait for callback
  - Tests compile, link, run without crash
  - PublishData callback fires immediately (synchronous path unchanged)
</acceptance_criteria>

---

## Task 10: C-4 test — GetBlock const-correctness test (concurrency_get_block_test.cpp)

<read_first>
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp (lines 214-217 — HasBlock and GetBlock declarations)
  - .planning/phases/02-fix-test/02-PATTERNS.md (lines 285-293 — Simple TEST pattern from blob_test.cpp)
</read_first>

<action>
**In SuperGenius/test/src/bitswap/concurrency_get_block_test.cpp (NEW):**
Create a `GetBlockConcurrencyTest` fixture inheriting `BitswapTestBase`. Test cases:

1. `ConcurrentGetBlockSameCid`: Store a block, then spawn 4 threads each calling `GetBlock(cid)` concurrently for 500 iterations. Verify no crash.

2. `ConcurrentGetHasBlock`: Spawn 4 threads alternating between `HasBlock(cid)` and `GetBlock(cid)` for 500 iterations. Verify no crash.

3. `GetBlockLazyLoadRace`: Store a block only via persistBlock (disk), then 4 threads call `GetBlock(cid)` concurrently to trigger lazy-load from disk. Verify no crash.

4. `ConstCorrectnessVerification`: Verify that `GetBlock` can be called on a non-const Bitswap reference. This is a compile-time test — the function signature `GetBlock(const CID&)` (non-const method) must compile when called on `bitswap_` (a `shared_ptr<Bitswap>`).

Use `@given`/`@when`/`@then` Doxygen comments on all test methods.
</action>

<acceptance_criteria>
  - concurrency_get_block_test.cpp exists with `GetBlockConcurrencyTest` fixture and 4 test methods
  - Each test method has Doxygen comment block
  - Tests compile and link correctly
  - All concurrent access tests complete without crash
  - Test 4 compiles only if `GetBlock()` is non-const (verifying the C-4 fix)
</acceptance_criteria>

---

## Verification

**Manual code review checklist:**
- [ ] All 7 cacheDir_ access sites inside mutexCacheDir_ lock scope or use local copy
- [ ] All maxPeerAttempts_ / peerFailureThreshold_ accesses use .load()/.store() with correct memory ordering
- [ ] GetBlock() signature has no const, no const_cast remains
- [ ] PublishFile/PublishDirectory use shared_from_this + io_context::post, no std::thread
- [ ] `#include <thread>` removed from bitswap.cpp

**Grep verification commands:**
```bash
# Verify no unprotected cacheDir_ access
rg 'cacheDir_' thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp -n

# Verify no const_cast remains
rg 'const_cast' thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp -n

# Verify no std::thread remains
rg 'std::thread' thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp -n

# Verify every atomic access uses .load() or .store()
rg 'maxPeerAttempts_|peerFailureThreshold_' thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp -n

# Verify new mutex declared
rg 'mutexCacheDir_' thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp -n
```

**Test verification:**
- Build in SuperGenius build tree with `BUILD_TESTING=ON`
- Run `ctest -R concurrency_cache_dir_test`
- Run `ctest -R concurrency_config_test`
- Run `ctest -R concurrency_publish_test`
- Run `ctest -R concurrency_get_block_test`
- All 4 test binaries pass (no crashes under concurrent load)
