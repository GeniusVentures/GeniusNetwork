---
phase: 02-fix-test
plan: 01
subsystem: concurrency
tags: [ipfs-bitswap-cpp, mutex, stdatomic, boost-asio, gtest]

requires:
  - phase: 01-audit
    provides: "CONCURRENCY-MAP.md identifying C-1 through C-4 data races"
provides:
  - "mutexCacheDir_ guarding all 7 cacheDir_ access sites"
  - "std::atomic maxPeerAttempts_ and peerFailureThreshold_ with correct memory ordering"
  - "Non-const GetBlock() eliminating const_cast data race"
  - "io_context::post replacing detached std::thread in PublishFile/PublishDirectory"
  - "StubHost, StubRouter, BitswapTestBase concurrency test fixture"
  - "4 concurrency test files covering C-1, C-2, C-3, C-4 race scenarios"
affects: [02-fix-test, 03-consumer-integration]

tech-stack:
  added: []
  patterns:
    - "Lock-and-copy pattern for cacheDir_ (lock, copy to local, release before I/O)"
    - "release/acquire memory ordering for cross-thread atomic reads"
    - "relaxed ordering for atomic reads already under mutex"
    - "shared_from_this + io_context::post for async publish work"
    - "Manual stub classes (no GMock) following CustomBroadcaster pattern"

key-files:
  created:
    - "SuperGenius/test/src/bitswap/stubs.hpp"
    - "SuperGenius/test/src/bitswap/stubs.cpp"
    - "SuperGenius/test/src/bitswap/CMakeLists.txt"
    - "SuperGenius/test/src/bitswap/concurrency_cache_dir_test.cpp"
    - "SuperGenius/test/src/bitswap/concurrency_config_test.cpp"
    - "SuperGenius/test/src/bitswap/concurrency_publish_test.cpp"
    - "SuperGenius/test/src/bitswap/concurrency_get_block_test.cpp"
  modified:
    - "thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp"
    - "thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp"
    - "SuperGenius/test/src/CMakeLists.txt"

key-decisions:
  - "mutexCacheDir_ positioned between cacheDir_ and mutexDiskIndex_ matching existing alignment"
  - "Lock ordering: mutexCacheDir_ → mutexDiskIndex_ (in buildDiskIndex)"
  - "getCacheDir() returns copy under lock (not reference) for thread safety"
  - "cidToFilePath() acquires mutexCacheDir_ internally; callers don't hold it"
  - "persistBlock/unpersistBlock/tryLoadFromDisk use lock-copy-release pattern for minimum critical section"
  - "memory_order_relaxed for peerFailureThreshold_ reads inside mutexProviders_ (already serialized)"
  - "memory_order_acquire for maxPeerAttempts_ reads outside lock in requestBlockWithProviders*"

patterns-established:
  - "Lock-and-copy: acquire mutex, copy shared state to local variable, release mutex, use local copy for all subsequent work"
  - "Atomic accessor pattern: .store(release) for writes, .load(acquire) for unprotected reads, .load(relaxed) for mutex-protected reads"

requirements-completed:
  - FIX-01
  - FIX-02
  - FIX-03
  - FIX-04
  - TEST-02

metrics:
  duration: ~15min
  completed: 2026-07-08
---

# Plan 01: Wave 1 — CRITICAL + Simple HIGH Fixes Summary

**Mutex-guarded cacheDir_, atomic config fields, const-correct GetBlock, and io_context::post-based publish — all 4 CRITICAL/HIGH race conditions from Phase 1 audit resolved with 4 per-finding concurrency test files.**

## Performance

- **Duration:** ~15 min
- **Tasks:** 10
- **Files modified:** 9 (2 source + 7 new)

## Accomplishments
- C-1: Added `mutexCacheDir_` guarding all 7 `cacheDir_` access sites across setCacheDir, getCacheDir, buildDiskIndex, persistBlock, unpersistBlock, tryLoadFromDisk, cidToFilePath
- C-2: Converted `maxPeerAttempts_` and `peerFailureThreshold_` to `std::atomic` with correct memory ordering at all 8 access sites
- C-4: Removed `const` from `GetBlock()` and eliminated `const_cast<Bitswap*>(this)` data race
- C-3: Replaced detached `std::thread` in PublishFile/PublishDirectory with `boost::asio::post(*context_, ...)` + `shared_from_this()` capture

## Task Commits

### ipfs-bitswap-cpp (dev_threadsafety)
1. **Task 1: C-1 mutexCacheDir_** - `14f51b5` (fix)
2. **Task 2: C-2 std::atomic config** - `4c1b160` (fix)
3. **Task 3: C-4 const correctness** - `9ad5a2f` (fix)
4. **Task 4: C-3 io_context::post** - `ea90e3f` (fix)

### SuperGenius (dev_persisprocresults)
5. **Task 5: Test stubs** - `7c3eeab4` (test)
6. **Task 6: CMakeLists.txt** - `371eed33` (test)
7. **Tasks 7-10: 4 concurrency tests** - `35c4032b` (test)

## Files Created/Modified
- `thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp` - Added mutexCacheDir_, std::atomic config fields, removed GetBlock() const
- `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` - Guarded 7 cacheDir_ sites, 8 atomic access sites, replaced std::thread with io_context::post
- `SuperGenius/test/src/bitswap/stubs.hpp` - StubHost, StubRouter, BitswapTestBase fixture
- `SuperGenius/test/src/bitswap/stubs.cpp` - Stub implementation placeholder
- `SuperGenius/test/src/bitswap/CMakeLists.txt` - Build targets for 4 concurrency tests + bitswap_test_stubs library
- `SuperGenius/test/src/CMakeLists.txt` - Added add_subdirectory(bitswap)
- `SuperGenius/test/src/bitswap/concurrency_cache_dir_test.cpp` - C-1: SetGetRace, SetPersistRace, BuildReadRace, MultiThreadedCache
- `SuperGenius/test/src/bitswap/concurrency_config_test.cpp` - C-2: ConcurrentSetAndRead, WriteDuringRead, StressConfigAccess
- `SuperGenius/test/src/bitswap/concurrency_publish_test.cpp` - C-3: PublishFileCallback, PublishDirectoryCallback, PublishDataCallback, MultiConcurrentPublish
- `SuperGenius/test/src/bitswap/concurrency_get_block_test.cpp` - C-4: ConcurrentGetBlockSameCid, ConcurrentGetHasBlock, GetBlockLazyLoadRace, ConstCorrectnessVerification

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Next Phase Readiness
- Plan 2 (Complex HIGH + MEDIUM Fixes) depends on the BitswapTestBase fixture and stubs created here — ready to proceed.
- Submodule nesting (main → thirdparty → ipfs-bitswap-cpp → …) requires careful git commit discipline for future tasks.

---
*Plan: 02-01*
*Completed: 2026-07-08*
