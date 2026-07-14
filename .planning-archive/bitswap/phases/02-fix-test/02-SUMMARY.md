---
phase: 02-fix-test
plan: 02
subsystem: concurrency
tags: [ipfs-bitswap-cpp, strand-confinement, mutex, callback-outside-lock, boost-asio-dispatch]

requires:
  - phase: 02-fix-test
    plan: 01
    provides: "BitswapTestBase fixture, StubHost, StubRouter, test infrastructure"
provides:
  - "boost::asio::dispatch wrappers at 4 ContentRequestContext entry points (C-5)"
  - "std::mutex mutex_ in BitswapRequestContext guarding callbacks_ and responseTimer_ (C-6)"
  - "HandleResponse invoked outside mutexRequestCallbacks_ lock scope (C-7)"
  - "3 concurrency test files covering C-5, C-6, C-7 race scenarios"
affects: [02-fix-test, 03-consumer-integration]

tech-stack:
  added: []
  patterns:
    - "boost::asio::dispatch for strand confinement (idempotent for same-io_context calls)"
    - "erase-before-callback pattern (context removed under lock, callback outside lock)"
    - "mutex per object pattern (BitswapRequestContext owns its synchronization)"

key-files:
  created:
    - "SuperGenius/test/src/bitswap/concurrency_content_request_test.cpp"
    - "SuperGenius/test/src/bitswap/concurrency_request_context_test.cpp"
    - "SuperGenius/test/src/bitswap/concurrency_callback_test.cpp"
  modified:
    - "thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp"
    - "thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp"
    - "SuperGenius/test/src/bitswap/CMakeLists.txt"

key-decisions:
  - "dispatch chosen over post for io_context identity check (inline for same, post for different thread)"
  - "HandleResponseTimeout does NOT acquire mutex_ — HandleResponse handles its own locking (self-deadlock prevention)"
  - "Context erased from requestContexts_ under lock before HandleResponse called outside lock — duplicate block arrivals get idempotent warn log"
  - "C-7 eliminates mutexRequestCallbacks_ → BitswapRequestContext::mutex_ nesting (previously both acquired simultaneously)"

patterns-established:
  - "Strand confinement via boost::asio::dispatch: best-effort inline for io_context, post for external threads"
  - "Callback-outside-lock: copy shared_ptr, erase from container under lock, invoke callback after lock release"
  - "Per-object mutex: each BitswapRequestContext owns its own std::mutex for its callbacks_ and responseTimer_"

requirements-completed:
  - FIX-02
  - FIX-03
  - FIX-04
  - TEST-02

metrics:
  duration: ~10min
  completed: 2026-07-08
---

# Plan 02: Wave 2 — Complex HIGH + MEDIUM Fixes Summary

**Strand-confinement dispatch wrappers for ContentRequestContext, mutex-guarded BitswapRequestContext, and callback-outside-lock restructuring — all 3 remaining HIGH/MEDIUM race conditions resolved.**

## Performance

- **Duration:** ~10 min
- **Tasks:** 7
- **Files modified:** 5 (2 source + 3 new test files)

## Accomplishments
- C-5: Wrapped all 4 ContentRequestContext callbacks (2 RequestContent + 2 processRequestQueue) in `boost::asio::dispatch(*context_, ...)` to ensure all ContentRequestContext field access happens on io_context
- C-6: Added `std::mutex mutex_` to BitswapRequestContext, guarding AddCallback, HandleResponse (HandleResponseTimeout forwards without double-lock)
- C-7: Restructured `processReceivedBlocks` to erase context from `requestContexts_` under lock, then invoke `HandleResponse` outside lock — callback-outside-lock pattern

## Task Commits

### ipfs-bitswap-cpp (dev_threadsafety)
1. **Task 1: C-5 dispatch wrappers** - `f6badc1` (fix)
2. **Task 2: C-6 BitswapRequestContext mutex** - `e854fc0` (fix)
3. **Task 3: C-7 callback-outside-lock** - `f6badc1` (fix, same commit as C-5 — sequential file modifications)

### SuperGenius (dev_persisprocresults)
4. **Task 4: CMakeLists.txt update** - `004c6fd8` (test)
5. **Task 5: C-5 content request test** - `004c6fd8` (test)
6. **Task 6: C-6 request context timer test** - `004c6fd8` (test)
7. **Task 7: C-7 callback reentrancy test** - `004c6fd8` (test)

## Files Created/Modified
- `thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp` - Added `std::mutex mutex_` to BitswapRequestContext
- `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` - 4 dispatch wrappers, 2 lock_guards, callback-outside-lock restructuring
- `SuperGenius/test/src/bitswap/CMakeLists.txt` - 3 new test targets (7 total now)
- `SuperGenius/test/src/bitswap/concurrency_content_request_test.cpp` - C-5: ConcurrentTimeoutAndProcessing, MultiBlockConcurrentArrival, QueueProcessingUnderStrand
- `SuperGenius/test/src/bitswap/concurrency_request_context_test.cpp` - C-6: ResponseTimeoutDuringResponse, MultiCallbackConcurrentFire, AddCallbackDuringHandleResponse
- `SuperGenius/test/src/bitswap/concurrency_callback_test.cpp` - C-7: ReenterDuringCallback, NestedRequestFromCallback, ConcurrentCallbacksNoDeadlock

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Next Phase Readiness
- Plan 3 (Documentation, Cleanup, Combined Stress Test) depends on all fixes from Plans 1 and 2 — ready to proceed.
- All 7 concurrency test targets registered in CMakeLists.txt, ready for build verification.

---
*Plan: 02-02*
*Completed: 2026-07-08*
