---
phase: 2
plan: 3
type: fix_test
wave: 3
depends_on:
  - plan: 1
    reason: "Requires Plan 1's BitswapTestBase fixture and test infrastructure"
  - plan: 2
    reason: "Combined stress test exercises all fixes from Plans 1 and 2"
files_modified:
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp
  - SuperGenius/test/src/bitswap/CMakeLists.txt
  - SuperGenius/test/src/bitswap/concurrency_stress_test.cpp (NEW)
autonomous: false
requirements:
  - DOCS-01
  - TEST-02
---

# Plan 3: Wave 3 — Documentation, Cleanup, Combined Stress Test (C-8, C-9, C-10, DOCS-01)

**Coverage:** DOCS-01 (C-8 dead code removal, C-9 handle() thread doc, C-10 lock documentation). TEST-02: combined stress test exercising all 10 fixes.

**Depends on Plans 1 and 2:** The BitswapTestBase fixture, all per-finding fixes, and the stubs/infrastructure must exist before the combined stress test can exercise them all.

**Must-Haves:**
- MH-01: `cleanupStaleProviders()` removed from both bitswap.hpp and bitswap.cpp (C-8)
- MH-02: `handle()` has Doxygen comment documenting libp2p thread contract (C-9)
- MH-03: All 7 mutexes + 2 atomics have structured `@mutex`/`@atomic` Doxygen documentation blocks grouping guarded members (C-10) — this IS the DOCS-01 deliverable
- MH-04: `concurrency_stress_test.cpp` exists with an N-thread hammer test exercising all fixed code paths
- MH-05: bitswap/CMakeLists.txt includes the stress test target

---

## Task 1: C-8 — Remove cleanupStaleProviders() dead code

<read_first>
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp (line 307 — `void cleanupStaleProviders();` declaration)
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (lines 1772-1805 — full implementation)
  - .planning/phases/02-fix-test/02-RESEARCH.md (C-8 section, lines 303-313 — Option A recommended: remove entirely)
</read_first>

<action>
**In bitswap.hpp (line 307):**
Delete the line `void cleanupStaleProviders();`.

**In bitswap.cpp (lines 1772-1805):**
Delete the entire `cleanupStaleProviders()` method body (lines 1772-1805).

No other changes — grep confirmed zero call sites across the entire codebase.
</action>

<acceptance_criteria>
  - bitswap.hpp no longer contains `cleanupStaleProviders` declaration
  - bitswap.cpp no longer contains `cleanupStaleProviders` implementation
  - Grep: `rg 'cleanupStaleProviders' thirdparty/ipfs-bitswap-cpp/` returns zero matches
</acceptance_criteria>

---

## Task 2: C-9 — Add Doxygen comment on handle() documenting thread contract

<read_first>
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp (line 183 — handle() declaration)
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (lines 123-216 — handle() implementation with server read loop)
  - .planning/phases/02-fix-test/02-RESEARCH.md (C-9 section, lines 317-343 — Doxygen comment text, implementation comment)
</read_first>

<action>
**In bitswap.hpp (above line 183, before the `handle()` declaration):**
Add a Doxygen comment block:
```
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
```

**In bitswap.cpp (above line 163, where the server read loop begins):**
Add a comment:
```
// Server read loop: persists on the libp2p I/O thread via recursive
// async read continuations. Each completion re-arms the read for the
// next wantlist message from the peer. This thread identity is
// inherited from the libp2p protocol handler dispatch.
```
Place this comment above the `// Set up continuous reading for server mode` comment at line 163.
</action>

<acceptance_criteria>
  - bitswap.hpp:182 (before or around line 183) has a Doxygen `@brief` block on `handle()` mentioning libp2p protocol dispatch thread
  - bitswap.cpp:162 (above the server read loop setup at line 163) has the inline comment about libp2p I/O thread recursive async reads
  - The documentation clearly states that lock acquisitions in the handle() path occur on libp2p threads, NOT the Bitswap io_context
</acceptance_criteria>

---

## Task 3: C-10 + DOCS-01 — Add structured lock documentation to bitswap.hpp

<read_first>
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp (lines 169-183 — existing Doxygen comment style for class and initialize())
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp (lines 324-345 — all 6 mutexes and guarded members with their current positions)
  - .planning/phases/02-fix-test/02-RESEARCH.md (C-10 section, lines 347-409 — full Doxygen template with `@mutex`/`@atomic` blocks)
  - .planning/phases/02-fix-test/02-PATTERNS.md (lines 175-207 — Doxygen comment style for lock documentation)
  - .planning/phases/01-audit/CONCURRENCY-MAP.md (lines 9-300 — all 6 mutex domains, guarded members, thread contexts, lock ordering)
</read_first>

<action>
**In bitswap.hpp — add documentation blocks for all synchronization domains:**
This task IS the DOCS-01 deliverable. Add structured Doxygen `@name`/`@mutex`/`@atomic` documentation blocks grouping each mutex with its guarded members. Add at lines 324-345 area, wrapping existing member declarations.

**Block 1 — Request Callback Synchronization (lines 324-325):**
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

**Block 2 — Content Request Synchronization (lines 327-328):**
```cpp
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
```

**Block 3 — Active Stream Synchronization (lines 330-331):**
```cpp
/**
 * @name Active Stream Synchronization
 *
 * @mutex mutexActiveStreams_ — Guards activeStreams_ map.
 *   Held on: caller thread, io_context (retry timer), libp2p callback (newStream result).
 *   Released before all async calls (writeBitswapMessageToStream, host_.newStream).
 *   NOT nested with other mutexes. Stream cached via shared_ptr for lifetime safety.
 */
///@{
mutable std::mutex                                                          mutexActiveStreams_;
std::map<libp2p::peer::PeerId, std::shared_ptr<libp2p::connection::Stream>> activeStreams_;
///@}
```

**Block 4 — Block Store Synchronization (lines 333-335):**
```cpp
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
```

**Block 5 — Cache Directory Synchronization (NEW — lines 337-338 area, after C-1 fix):**
```cpp
/**
 * @name Cache Directory Synchronization
 *
 * @mutex mutexCacheDir_ — Guards cacheDir_ string.
 *   Lock ordering: mutexCacheDir_ → mutexDiskIndex_ (via buildDiskIndex).
 *   Held for minimum scope — value copied to local before any filesystem I/O.
 *   Held on: caller thread, main init thread (buildDiskIndex).
 */
///@{
std::string                cacheDir_;
mutable std::mutex         mutexCacheDir_;
///@}
```

**Block 6 — Disk Index Synchronization (lines 339-340):**
```cpp
/**
 * @name Disk Index Synchronization
 *
 * @mutex mutexDiskIndex_ — Guards diskIndex_ set.
 *   Held on: main init thread (buildDiskIndex), caller thread (persistBlock, unpersistBlock),
 *            libp2p/consumer thread (tryLoadFromDisk, HasBlock).
 *   NOT nested with other mutexes except via mutexCacheDir_ → mutexDiskIndex_ in buildDiskIndex.
 *   buildDiskIndex() clear-then-populate creates a transitory empty-index window — benign.
 */
///@{
mutable std::mutex         mutexDiskIndex_;
std::set<std::string>      diskIndex_;
///@}
```

**Block 7 — Provider Synchronization (lines 342-345, with C-2 atomics):**
```cpp
/**
 * @name Provider Synchronization
 *
 * @mutex mutexProviders_ — Guards providers_ map.
 *   Lock ordering: acquired inside mutexRequestCallbacks_ via markProviderSuccess.
 *   Held on: caller thread, libp2p thread (markProviderSuccess).
 *   findProvider() returns raw PeerProvider* valid only under lock.
 *
 * @atomic maxPeerAttempts_ — Max provider selection attempts (C-2 fix).
 *   Written by SetMaxPeerAttempts (release ordering).
 *   Read under mutexProviders_ in selectBestProvider (relaxed ordering sufficient).
 *   Read without lock in requestBlockWithProviders* (acquire ordering).
 *
 * @atomic peerFailureThreshold_ — Failure count before marking provider unreachable (C-2 fix).
 *   Written by SetPeerFailureThreshold (release ordering).
 *   Read under mutexProviders_ in selectBestProvider/markProviderFailure (relaxed ordering).
 */
///@{
mutable std::mutex                       mutexProviders_;
std::map<CID, std::vector<PeerProvider>> providers_;
std::atomic<size_t>                      maxPeerAttempts_{3};
std::atomic<int>                         peerFailureThreshold_{3};
///@}
```

**Plus a top-level concurrency model comment before the class or in the class Doxygen block (line 169 area):**
Add to the existing class comment at line 169-172:
```
 * Concurrency model: 7 mutex domains (mutexRequestCallbacks_, mutexContentRequests_,
 * mutexActiveStreams_, mutexBlockStore_, mutexCacheDir_, mutexDiskIndex_,
 * mutexProviders_) + 2 atomics (maxPeerAttempts_, peerFailureThreshold_).
 * One documented lock ordering: mutexCacheDir_ → mutexDiskIndex_.
 * One documented lock ordering: mutexRequestCallbacks_ → mutexProviders_.
 * Callbacks posted to io_context (PublishFile/PublishDirectory) or dispatched to
 * io_context (ContentRequestContext callbacks). io_context provides strand
 * serialization for publish and content-request processing.
 * All locks released before async calls and filesystem I/O.
 */
```
</action>

<acceptance_criteria>
  - All 7 mutex domains have `@mutex` documentation blocks grouping their guarded members
  - The 2 atomics have `@atomic` documentation in the Provider Synchronization block
  - Lock ordering (mutexCacheDir_ → mutexDiskIndex_, mutexRequestCallbacks_ → mutexProviders_) is documented
  - Thread contexts for each lock are documented (caller thread, libp2p thread, io_context)
  - The class-level Doxygen comment includes a concurrency model summary
  - `BitswapRequestContext::mutex_` (C-6) is also documented — add a brief comment above its declaration noting it guards `callbacks_` and `responseTimer_`
  - No undocumented mutexes remain — grep `mutex` in bitswap.hpp shows a comment for every one
</acceptance_criteria>

---

## Task 4: Combined stress test (concurrency_stress_test.cpp)

<read_first>
  - .planning/phases/02-fix-test/02-RESEARCH.md (lines 492-539 — BitswapStressTest fixture and Hammer + Verify pattern)
  - .planning/phases/02-fix-test/02-PATTERNS.md (lines 378-418 — multi-threaded stress test patterns with errors counter and threads vector)
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp (all public API methods exercised by the stress test: HasBlock, GetBlock, setCacheDir, getCacheDir, SetMaxPeerAttempts, PublishData, AddProvider, GetProviders, ListPublishedContent)
</read_first>

<action>
**In SuperGenius/test/src/bitswap/concurrency_stress_test.cpp (NEW):**
Create a `BitswapStressTest` fixture inheriting `BitswapTestBase`. Test cases:

1. **`ConcurrentAccessNoCrashes`:** Spawn 8 threads, each performing 100 iterations of random Bitswap operations:
   - `HasBlock(dummyCid)`
   - `GetBlock(dummyCid)` — exercises C-4 (non-const, lazy-load from disk)
   - `setCacheDir("/tmp/test_" + threadId)` — exercises C-1 (mutexCacheDir_)
   - `getCacheDir()` — exercises C-1
   - `SetMaxPeerAttempts(threadId % 5 + 1)` — exercises C-2 (atomics)
   - `PublishData(smallData, [](auto){})` — exercises C-3 (io_context post, synchronous path)
   - `AddProvider(dummyCid, dummyPeerInfo)` — exercises mutexProviders_
   - `GetProviders(dummyCid)` — exercises mutexProviders_
   - `ListPublishedContent()` — exercises mutexBlockStore_
   - Each operation wrapped in try/catch; errors counted via `std::atomic<int> errors{0}`
   - After all threads join: `EXPECT_EQ(errors.load(), 0)`

2. **`CacheDirRaceAmplification`:** 2 threads: setter hammers `setCacheDir` alternating between two paths for 10000 iterations, while reader hammers `storeBlock` (which triggers `persistBlock` → reads `cacheDir_`). Verify no crash.

3. **`ConfigWriteDuringRequest`:** 4 writer threads calling `SetMaxPeerAttempts` and `SetPeerFailureThreshold` while 4 reader threads call `GetTotalProviderCount` and `GetProviderDebugInfo`. 1000 iterations. Verify no crash.

4. **`ProviderMapConcurrentAccess`:** 8 threads: 2 add providers, 2 remove providers, 2 query GetProviders, 2 query GetTotalProviderCount. 500 iterations. Verify no crash and total provider count after operations is >= 0.

5. **`FullSystemStress`:** 12 threads, 200 iterations each, exercising ALL public API methods simultaneously. Include `PublishFile` (async io_context path from C-3) and `RequestContent` (dispatch path from C-5) to stress-test the async paths. Verify all threads complete, no crash, no deadlock.

Use `@given`/`@when`/`@then` Doxygen comments on all test methods. Use `std::atomic<bool> running{true}` for coordinated start/stop. Include `<thread>`, `<atomic>`, `<vector>`, `<random>`.
</action>

<acceptance_criteria>
  - concurrency_stress_test.cpp exists with `BitswapStressTest` fixture and 5 test methods
  - Each test method has Doxygen `@given`/`@when`/`@then` comment block
  - Test `ConcurrentAccessNoCrashes` exercises at least 8 different Bitswap API methods
  - Test `FullSystemStress` exercises 12 threads × 200 iterations and includes async publish/content-request paths
  - All tests compile, link, run without crash
  - All tests complete within 30 seconds (no deadlock)
  - `errors.load()` is 0 after concurrent operations (no exceptions escaped)
</acceptance_criteria>

---

## Task 5: Update bitswap/CMakeLists.txt to register stress test target

<read_first>
  - SuperGenius/test/src/bitswap/CMakeLists.txt (created in Plan 1, updated in Plan 2)
  - .planning/phases/02-fix-test/02-RESEARCH.md (lines 603-611 — stress test CMake entry)
</read_first>

<action>
**In SuperGenius/test/src/bitswap/CMakeLists.txt:**
Add the stress test entry at the end of the file:
```cmake
# Combined stress test
addtest(concurrency_stress_test
    concurrency_stress_test.cpp
)
target_link_libraries(concurrency_stress_test
    bitswap_test_stubs
    ipfs-bitswap-cpp
)
```
This is the 8th test target (after the 4 from Plan 1 and 3 from Plan 2).
</action>

<acceptance_criteria>
  - CMakeLists.txt has addtest(concurrency_stress_test ...) entry at end of file
  - Entry links bitswap_test_stubs and ipfs-bitswap-cpp
  - CMakeLists.txt now has 8 test targets total (4 Plan 1 + 3 Plan 2 + 1 Plan 3)
</acceptance_criteria>

---

## Verification

**Documentation review checklist:**
- [ ] Every mutex in bitswap.hpp has a `@mutex` Doxygen block explaining what it guards
- [ ] Every atomic has an `@atomic` explanation with memory ordering rationale
- [ ] Lock ordering is documented for both nesting pairs
- [ ] Thread context assumptions are documented per mutex domain
- [ ] Class-level concurrency model summary exists
- [ ] `handle()` has thread contract documentation
- [ ] BitswapRequestContext::mutex_ (from C-6) is documented

**Dead code removal checklist:**
- [ ] `cleanupStaleProviders` declaration removed from header
- [ ] `cleanupStaleProviders` implementation removed from source

**Stress test verification:**
- [ ] Build with `BUILD_TESTING=ON`
- [ ] Run `ctest -R concurrency_stress_test`
- [ ] All 5 stress test methods pass without crash
- [ ] `FullSystemStress` test completes in under 30 seconds (no deadlock)
- [ ] `errors.load()` is 0 in all tests

**Grepping final state:**
```bash
# Verify no dead code references
rg 'cleanupStaleProviders' thirdparty/ipfs-bitswap-cpp/

# Verify all 7 mutex docs
rg '@mutex' thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp

# Verify atomic docs
rg '@atomic' thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp

# Verify handle() doc
rg '@brief.*Handle.*incoming' thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp -i
```
