---
status: diagnosed
phase: 02-fix-test
source: 01-SUMMARY.md, 02-SUMMARY.md, 03-SUMMARY.md
started: 2026-07-09T14:13:10-04:00
updated: 2026-07-09T14:13:10-04:00
---

## Current Test

[testing complete]

## Tests

### 1. Build — All 8 Concurrency Test Targets Compile
expected: CMake configure succeeds for SuperGenius tests with Bitswap test subdirectory enabled. All 8 concurrency test targets compile without errors and without warnings.
result: issue
reported: "bitswap.cpp(993,50): error C4573: 'sgns::ipfs_bitswap::Bitswap::handleQueuedBlockResult' requires the compiler to capture 'this' but the current default capture mode does not allow it. error C2352: a call of a non-static member function requires an object"
severity: blocker

### 2. C-1 — Cache Directory Concurrency Tests Pass
expected: Run concurrency_cache_dir_test — SetGetRace, SetPersistRace, BuildReadRace, and MultiThreadedCache all pass without assertion failures or timeouts.
result: blocked
blocked_by: prior-phase
reason: "Cannot compile anything in SuperGenius without compiling bitswap itself"

### 3. C-2 — Atomic Config Concurrency Tests Pass
expected: Run concurrency_config_test — ConcurrentSetAndRead, WriteDuringRead, and StressConfigAccess all pass. Atomic reads/writes on maxPeerAttempts_ and peerFailureThreshold_ are correctly synchronized.
result: blocked
blocked_by: prior-phase
reason: "Build failure in test 1 prevents any test execution"

### 4. C-3 — Async Publish Concurrency Tests Pass
expected: Run concurrency_publish_test — PublishFileCallback, PublishDirectoryCallback, PublishDataCallback, and MultiConcurrentPublish all pass. No detached std::thread usage remains.
result: blocked
blocked_by: prior-phase
reason: "Build failure in test 1 prevents any test execution"

### 5. C-4 — GetBlock Concurrency Tests Pass
expected: Run concurrency_get_block_test — ConcurrentGetBlockSameCid, ConcurrentGetHasBlock, GetBlockLazyLoadRace, and ConstCorrectnessVerification all pass. GetBlock() is non-const (no const_cast data race).
result: blocked
blocked_by: prior-phase
reason: "Build failure in test 1 prevents any test execution"

### 6. C-5 — Content Request Strand Confinement Tests Pass
expected: Run concurrency_content_request_test — ConcurrentTimeoutAndProcessing, MultiBlockConcurrentArrival, and QueueProcessingUnderStrand all pass. All ContentRequestContext callbacks are dispatched on io_context.
result: blocked
blocked_by: prior-phase
reason: "Build failure in test 1 prevents any test execution"

### 7. C-6 — Request Context Mutex Tests Pass
expected: Run concurrency_request_context_test — ResponseTimeoutDuringResponse, MultiCallbackConcurrentFire, and AddCallbackDuringHandleResponse all pass. BitswapRequestContext::mutex_ correctly serializes callback and timer access.
result: blocked
blocked_by: prior-phase
reason: "Build failure in test 1 prevents any test execution"

### 8. C-7 — Callback Reentrancy Tests Pass
expected: Run concurrency_callback_test — ReenterDuringCallback, NestedRequestFromCallback, and ConcurrentCallbacksNoDeadlock all pass. HandleResponse is invoked outside the requestContexts_ lock.
result: blocked
blocked_by: prior-phase
reason: "Build failure in test 1 prevents any test execution"

### 9. Combined Stress Test Passes
expected: Run concurrency_stress_test — FullSystemStress with 12 threads × 50 iterations across all public API methods completes without crashes, hangs, or assertion failures.
result: blocked
blocked_by: prior-phase
reason: "Build failure in test 1 prevents any test execution"

### 10. Doxygen Thread-Safety Documentation Present
expected: Open bitswap.hpp — all 7 mutexes have @mutex Doxygen blocks, 2 atomics have @atomic doc blocks, class-level concurrency model summary is present, lock ordering (mutexCacheDir_ → mutexDiskIndex_, mutexRequestCallbacks_ → mutexProviders_) is documented, and BitswapRequestContext::mutex_ documents the HandleResponseTimeout non-double-lock contract.
result: pass

### 11. Source Code Cleanliness
expected: No const_cast<Bitswap*>(this) remains in bitswap.cpp. No cleanupStaleProviders() dead code remains in bitswap.hpp or bitswap.cpp. No detached std::thread spawns remain in PublishFile/PublishDirectory (replaced with io_context::post).
result: pass

## Summary

total: 11
passed: 2
issues: 1
pending: 0
skipped: 0
blocked: 8

## Gaps

- truth: "All 8 concurrency test targets compile without errors and without warnings"
  status: failed
  reason: "User reported: bitswap.cpp(993,50): error C4573: 'sgns::ipfs_bitswap::Bitswap::handleQueuedBlockResult' requires the compiler to capture 'this' but the current default capture mode does not allow it. error C2352: a call of a non-static member function requires an object"
  severity: blocker
  test: 1
  root_cause: "Inner dispatch lambda at line 992 in processRequestQueue calls handleQueuedBlockResult() (non-static member function) but capture list [ctx, nextCid, result] omitted `this`. MSVC requires explicit `this` capture when calling member functions from lambdas. Only 1 of 6 dispatch/post lambdas has this bug — the other 5 correctly capture `this` or use `self` (shared_ptr)."
  artifacts:
    - path: "thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp"
      issue: "Line 992: capture list [ctx, nextCid, result = std::move(result)] missing `this`"
  missing:
    - "Add `this` to capture list at line 992: [this, ctx, nextCid, result = std::move(result)]"
  debug_session: ""
