---
phase: 2
plan: 2
type: fix_test
wave: 2
depends_on:
  - plan: 1
    reason: "Requires the BitswapTestBase fixture and stubs from Plan 1's test infrastructure"
files_modified:
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp
  - SuperGenius/test/src/bitswap/CMakeLists.txt
  - SuperGenius/test/src/bitswap/concurrency_content_request_test.cpp (NEW)
  - SuperGenius/test/src/bitswap/concurrency_request_context_test.cpp (NEW)
  - SuperGenius/test/src/bitswap/concurrency_callback_test.cpp (NEW)
autonomous: false
requirements:
  - FIX-02
  - FIX-03
  - FIX-04
  - TEST-02
---

# Plan 2: Wave 2 — Complex HIGH + MEDIUM Fixes (C-5, C-6, C-7)

**Coverage:** FIX-02 (C-7 callback outside lock), FIX-03 (C-6 BitswapRequestContext mutex), FIX-04 (C-5 ContentRequestContext strand dispatch). TEST-02: 3 per-finding concurrency test files.

**Depends on Plan 1:** The BitswapTestBase fixture, StubHost, StubRouter, and bitswap/CMakeLists.txt infrastructure created in Plan 1 are prerequisites for the test files in this plan.

**Must-Haves:**
- MH-01: ContentRequestContext callbacks from libp2p threads are dispatched via `boost::asio::dispatch(*context_, ...)` at all 3 entry points
- MH-02: BitswapRequestContext has `std::mutex mutex_` guarding `HandleResponse`, `HandleResponseTimeout`, and `AddCallback`
- MH-03: `processReceivedBlocks()` invokes `HandleResponse()` AFTER releasing `mutexRequestCallbacks_` (callback-outside-lock pattern)
- MH-04: 3 new concurrency test files (C-5, C-6, C-7) build and link, exercising strand dispatch and re-entrancy guard scenarios
- MH-05: bitswap/CMakeLists.txt in Plan 1 is updated to register the 3 new test targets

---

## Task 1: C-5 — Add boost::asio::dispatch wrappers at ContentRequestContext callback entry points

<read_first>
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (lines 351-367 RequestContent with PeerInfo, lines 369-394 RequestContent without PeerInfo, lines 929-973 processRequestQueue with RequestBlock callbacks at lines 946-960 and 964-966)
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp (lines 121-167 — ContentRequestContext struct with all unprotected fields: pendingCIDs, completedCIDs, filesInProgress, cidToPath, chunkToCidIndex, requestQueue, processingQueue, timedOut, etc.)
  - .planning/phases/02-fix-test/02-RESEARCH.md (C-5 section, lines 163-223 — strand confinement via boost::asio::dispatch, why dispatch over post, 3 entry points)
  - .planning/phases/02-fix-test/02-PATTERNS.md (lines 155-175 — boost::asio::dispatch usage pattern)
  - .planning/phases/01-audit/CONCURRENCY-MAP.md (lines 431-455 — Strand Confinement Analysis for ContentRequestContext, table of fields vs threads)
</read_first>

<action>
**C-5 fixes the strand violation:** `processUnixFSBlock()` runs on libp2p threads via block result callbacks. The timeout handler runs on io_context. Both access `ContentRequestContext` fields concurrently. Fix: wrap all libp2p→ContentRequestContext entry points in `boost::asio::dispatch(*context_, ...)`.

**Three entry points to wrap:**

1. **`RequestContent(const PeerInfo&, ...)` (lines 356-366):** Wrap the callback body inside `boost::asio::dispatch(*context_, ...)`. The existing lambda at line 358 captures `[this, ctx]`. Replace with:
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

2. **`RequestContent(const CID&, ...)` (lines 377-389):** Same dispatch wrapper pattern. The existing RequestBlock callback at lines 380-388 captures `[this, ctx]`. Wrap the entire body in `boost::asio::dispatch(*context_, ...)` with move semantics on blockResult.

3. **`processRequestQueue()` (lines 944-960 and 964-966):** Two RequestBlock callbacks need dispatch wrappers:
   - Lines 946-960 (with peerInfo): Wrap body in dispatch. The callback already captures `[this, ctx, nextCid]`. Add dispatch wrapping the if-else logic.
   - Lines 964-966 (without peerInfo, useProviders): Wrap body in dispatch. Callback captures `[this, ctx, nextCid]`.

**Why `dispatch` not `post`:** `dispatch` executes inline if already on io_context (timeout/delay timer handlers), `post` if on an external thread (libp2p). This preserves low latency for io_context→io_context chains while fixing the cross-thread access.

**`processingQueue` flag interaction:** The flag at bitswap.hpp:157 prevents recursive queue processing. Since all accesses to `processingQueue` and other ContentRequestContext fields now happen on io_context (via dispatch), the flag remains a safe optimization. No changes needed to the flag itself.
</action>

<acceptance_criteria>
  - bitswap.cpp:358-366 (RequestContent with PeerInfo callback) body is wrapped in `boost::asio::dispatch( *context_, [this, ctx, blockResult = std::move(blockResult)]() mutable { ... } );`
  - bitswap.cpp:380-388 (RequestContent without PeerInfo callback) body is wrapped in `boost::asio::dispatch( *context_, ... )`
  - bitswap.cpp:946-960 (processRequestQueue with peerInfo callback) body is wrapped in `boost::asio::dispatch( *context_, ... )`
  - bitswap.cpp:964-966 (processRequestQueue without peerInfo callback) body is wrapped in `boost::asio::dispatch( *context_, ... )`
  - All ContentRequestContext field accesses (pendingCIDs, completedCIDs, filesInProgress, cidToPath, chunkToCidIndex, requestQueue, processingQueue, timedOut) now execute on io_context only
  - Existing io_context paths (timeout handler at lines 546-561, delay timer at lines 998-1007) are unchanged — they already run on io_context
</acceptance_criteria>

---

## Task 2: C-6 — Add std::mutex mutex_ to BitswapRequestContext and guard 3 methods

<read_first>
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp (lines 104-118 — BitswapRequestContext class with callbacks_ list, responseTimer_, AddCallback, HandleResponse, HandleResponseTimeout)
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (lines 65-89 — BitswapRequestContext constructor and all 3 method implementations)
  - .planning/phases/02-fix-test/02-RESEARCH.md (C-6 section, lines 228-250 — mutex_ addition, lock ordering: mutexRequestCallbacks_ → BitswapRequestContext::mutex_)
  - .planning/phases/02-fix-test/02-PATTERNS.md (lines 33-36 — mutex declaration style, lines 73-79 — BitswapRequestContext guard pattern)
</read_first>

<action>
**In bitswap.hpp (line 112 area, BitswapRequestContext private section):**
Add `std::mutex mutex_;` to the private section of BitswapRequestContext (after line 113, before the `callbacks_` declaration).

**In bitswap.cpp — guard all 3 methods:**

1. **`AddCallback()` (lines 70-75):** Wrap body in `std::lock_guard<std::mutex> guard(mutex_);`. This introduces lock ordering: `mutexRequestCallbacks_` (held by messageSent caller) → `BitswapRequestContext::mutex_` (acquired here). Document this ordering.

2. **`HandleResponse()` (lines 77-85):** Wrap body in `std::lock_guard<std::mutex> guard(mutex_);`. The `responseTimer_.expires_at(...)` call at line 79 and the callback iteration at lines 80-83 and `callbacks_.clear()` at line 84 are all guarded.

3. **`HandleResponseTimeout()` (lines 87-89):** Wrap body in `std::lock_guard<std::mutex> guard(mutex_);`. Since this calls `HandleResponse()` which also acquires `mutex_`, this would self-deadlock with `std::lock_guard`. **Solution:** Do NOT add a separate lock here. Instead, remove the lock from `HandleResponse()` and wrap `HandleResponse()` in a private implementation method. OR simpler: `HandleResponseTimeout()` body stays as `HandleResponse(BitswapError::OUTBOUND_STREAM_FAILURE);` — the lock is acquired inside HandleResponse(). Do NOT double-lock.

**Revised approach for HandleResponseTimeout (line 87-89):**
Since `HandleResponse()` already acquires `mutex_`, `HandleResponseTimeout()` does NOT need its own lock_guard — the lock is already held inside `HandleResponse()`. The body of `HandleResponseTimeout()` is just a forward call: `HandleResponse( BitswapError::OUTBOUND_STREAM_FAILURE );`. No race here because HandleResponse itself is guarded.

**Lock ordering documentation:** New nesting: `mutexRequestCallbacks_ → BitswapRequestContext::mutex_` (via `messageSent()` → `AddCallback()`). This is compatible with the existing `mutexRequestCallbacks_ → mutexProviders_` nesting — they share the outer lock but different inner locks. No code acquires both `BitswapRequestContext::mutex_` and `mutexProviders_` in any order.
</action>

<acceptance_criteria>
  - bitswap.hpp:112 area contains `std::mutex mutex_;` in BitswapRequestContext private section
  - bitswap.cpp:70-75 AddCallback body wrapped in `std::lock_guard<std::mutex> guard(mutex_);`
  - bitswap.cpp:77-85 HandleResponse body wrapped in `std::lock_guard<std::mutex> guard(mutex_);`
  - bitswap.cpp:87-89 HandleResponseTimeout body is ONLY the call to `HandleResponse(...)` — no duplicate lock (HandleResponse handles its own locking)
  - All 3 methods serialize concurrent access to `callbacks_` list and `responseTimer_` via `mutex_`
  - No self-deadlock: HandleResponseTimeout does not acquire mutex_ before calling HandleResponse (which acquires mutex_)
</acceptance_criteria>

---

## Task 3: C-7 — Move HandleResponse invocation outside mutexRequestCallbacks_ lock scope

<read_first>
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (lines 271-285 — processReceivedBlocks with callback invoked under lock at line 279)
  - .planning/phases/02-fix-test/02-RESEARCH.md (C-7 section, lines 254-300 — callback-outside-lock pattern, erase-before-callback, shared_ptr lifetime)
  - .planning/phases/02-fix-test/02-PATTERNS.md (lines 230-265 — callback-outside-lock pattern, exact before/after code)
</read_first>

<action>
**In bitswap.cpp (lines 271-285 — processReceivedBlocks):**
Replace the current block (lines 271-285) with the callback-outside-lock pattern:

1. Declare `std::shared_ptr<BitswapRequestContext> ctx;` before the lock scope.
2. Under `mutexRequestCallbacks_` lock: find context, call `markProviderSuccess(...)` (preserving the existing `mutexRequestCallbacks_ → mutexProviders_` nesting), copy context to local `ctx`, erase context from `requestContexts_`.
3. After lock release: if `ctx` is non-null, call `ctx->HandleResponse(block)`.

Key behavior changes:
- `markProviderSuccess()` is still called under the lock (no change to the lock ordering).
- Context is erased from `requestContexts_` under lock — a duplicate block arrival for the same CID will find no context and hit the existing warn log at line 283. This is acceptable: content-addressed blocks are idempotent.
- `HandleResponse(block)` fires AFTER lock release — no re-entrancy deadlock risk if the callback re-enters Bitswap.

**Interaction with C-6:** After C-6 adds `mutex_` to BitswapRequestContext, this C-7 fix eliminates the nesting `mutexRequestCallbacks_ → BitswapRequestContext::mutex_` (previously both acquired together during HandleResponse under lock). Now HandleResponse acquires only `mutex_` (no outer lock held). The only remaining nesting is `mutexRequestCallbacks_ → mutexProviders_` (via markProviderSuccess, unchanged).
</action>

<acceptance_criteria>
  - bitswap.cpp:271-285 is restructured to the callback-outside-lock pattern
  - `std::shared_ptr<BitswapRequestContext> ctx;` is declared before the lock scope
  - `markProviderSuccess(cid.value(), remotePeer.value())` is called under `mutexRequestCallbacks_` lock (unchanged behavior)
  - `requestContexts_.erase(itContext)` is called under lock (context removed before lock release)
  - `ctx->HandleResponse(block)` is called AFTER the lock scope closes (`}` before the if(ctx) block)
  - No `HandleResponse` or callback invocation occurs while `mutexRequestCallbacks_` is held
</acceptance_criteria>

---

## Task 4: Update bitswap/CMakeLists.txt to register C-5, C-6, C-7 test targets

<read_first>
  - SuperGenius/test/src/bitswap/CMakeLists.txt (created in Plan 1 — will exist after Plan 1 executes)
  - .planning/phases/02-fix-test/02-PATTERNS.md (lines 697-731 — test target entries for C-5, C-6, C-7 in CMakeLists.txt)
</read_first>

<action>
**In SuperGenius/test/src/bitswap/CMakeLists.txt:**
Add 3 new `addtest()` entries following the same pattern as Plan 1's test targets:

1. `concurrency_content_request_test` (C-5) — links `bitswap_test_stubs` and `ipfs-bitswap-cpp`
2. `concurrency_request_context_test` (C-6) — links `bitswap_test_stubs` and `ipfs-bitswap-cpp`
3. `concurrency_callback_test` (C-7) — links `bitswap_test_stubs` and `ipfs-bitswap-cpp`

Place these entries after the C-4 test entry (concurrency_get_block_test) and before the end of the file.
</action>

<acceptance_criteria>
  - CMakeLists.txt has 3 new `addtest()` entries for concurrency_content_request_test, concurrency_request_context_test, concurrency_callback_test
  - Each entry links bitswap_test_stubs and ipfs-bitswap-cpp
  - All 7 test targets (4 from Plan 1 + 3 from Plan 2) are registered in the same CMakeLists.txt
</acceptance_criteria>

---

## Task 5: C-5 test — ContentRequestContext strand confinement test (concurrency_content_request_test.cpp)

<read_first>
  - .planning/phases/02-fix-test/02-RESEARCH.md (lines 542-558 — race window amplification pattern)
  - .planning/phases/02-fix-test/02-PATTERNS.md (lines 374-419 — multi-threaded stress test patterns)
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp (lines 121-167 — ContentRequestContext struct fields)
</read_first>

<action>
**In SuperGenius/test/src/bitswap/concurrency_content_request_test.cpp (NEW):**
Create a `ContentRequestConcurrencyTest` fixture inheriting `BitswapTestBase`. Test cases:

1. `ConcurrentTimeoutAndProcessing`: Call `RequestContent()` with a real Cid. The test verifies that concurrent timeout handler (io_context) and block arrival (dispatched to io_context) don't cause data races. Since C-5 dispatches all ContentRequestContext access to io_context, both paths serialize. Test validates no crash.

2. `MultiBlockConcurrentArrival`: Initiate a content request that causes multiple block requests. Verify the callback chain works without data races on `pendingCIDs`, `completedCIDs`. This is a stress test for the dispatch wrappers.

3. `QueueProcessingUnderStrand`: Verify that `processRequestQueue` serializes correctly when called from timeout handler (io_context) and block callback (dispatched to io_context). Both should now run on io_context — test validates no concurrent access to `requestQueue` or `processingQueue`.

Use `@given`/`@when`/`@then` Doxygen comments. Tests focus on "no crash under concurrent content request operations" — the strand dispatch ensures serialization.
</action>

<acceptance_criteria>
  - concurrency_content_request_test.cpp exists with `ContentRequestConcurrencyTest` fixture
  - At least 3 test methods with Doxygen comment blocks
  - Tests compile, link, run without crash
  - Tests exercise the boost::asio::dispatch paths added in C-5 fix
</acceptance_criteria>

---

## Task 6: C-6 test — BitswapRequestContext timer race test (concurrency_request_context_test.cpp)

<read_first>
  - .planning/phases/02-fix-test/02-RESEARCH.md (lines 489-490 — RequestContextTimerTest entry in fixture table)
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (lines 65-89 — BitswapRequestContext implementation with timer and callbacks)
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp (lines 104-118 — BitswapRequestContext class definition)
</read_first>

<action>
**In SuperGenius/test/src/bitswap/concurrency_request_context_test.cpp (NEW):**
Create a `RequestContextTimerTest` fixture inheriting `BitswapTestBase`. Test cases:

1. `ResponseTimeoutDuringResponse`: Create a BitswapRequestContext, call AddCallback to start a timer, then call HandleResponse from one thread while the deadline_timer fires HandleResponseTimeout from io_context. With C-6 mutex fix, both serialize — verify no crash and no double callback.

2. `MultiCallbackConcurrentFire`: Add 4 callbacks, then fire HandleResponse from 4 threads simultaneously. Verify all callbacks are invoked and the list is cleared atomically.

3. `AddCallbackDuringHandleResponse`: One thread adds callbacks while another fires HandleResponse. Verify no data race on `callbacks_` list.

Use `@given`/`@when`/`@then` Doxygen comments. Tests require starting the io_context worker thread (done by BitswapTestBase::SetUp) so the deadline_timer can fire.
</action>

<acceptance_criteria>
  - concurrency_request_context_test.cpp exists with `RequestContextTimerTest` fixture
  - At least 3 test methods with Doxygen comment blocks
  - Tests compile, link, run without crash
  - Tests verify the mutex_ added in C-6 fix serializes concurrent HandleResponse/HandleResponseTimeout/AddCallback access
</acceptance_criteria>

---

## Task 7: C-7 test — callback re-entrancy deadlock guard test (concurrency_callback_test.cpp)

<read_first>
  - .planning/phases/02-fix-test/02-RESEARCH.md (lines 491-492 — CallbackReentrancyTest fixture in table)
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (lines 271-285 — processReceivedBlocks, the pre-fix lock+callback pattern to understand the re-entrancy risk)
</read_first>

<action>
**In SuperGenius/test/src/bitswap/concurrency_callback_test.cpp (NEW):**
Create a `CallbackReentrancyTest` fixture inheriting `BitswapTestBase`. Test cases:

1. `ReenterDuringCallback`: Register a BlockCallback that calls `RequestBlock()` again (re-entering Bitswap). The callback should NOT deadlock — the C-7 fix ensures HandleResponse fires outside mutexRequestCallbacks_ lock. Test verifies this by checking that the nested RequestBlock completes.

2. `NestedRequestFromCallback`: Same pattern but deeper nesting — callback calls `RequestBlock()`, whose callback calls `RequestBlock()` again. Verify no deadlock.

3. `ConcurrentCallbacksNoDeadlock`: Fire multiple block callbacks from different threads concurrently. Verify all complete without deadlock or crash.

Use `@given`/`@when`/`@then` Doxygen comments. These tests specifically verify the C-7 callback-outside-lock fix prevents re-entrancy deadlock.
</action>

<acceptance_criteria>
  - concurrency_callback_test.cpp exists with `CallbackReentrancyTest` fixture
  - At least 3 test methods with Doxygen comment blocks
  - Tests compile, link, run without deadlock (consider a 5-second timeout per test as deadlock guard)
  - Re-entrancy tests complete without hanging — validates C-7 fix prevents the non-recursive mutex deadlock
</acceptance_criteria>

---

## Verification

**Manual code review checklist:**
- [ ] All 3 libp2p→ContentRequestContext entry points are wrapped in `boost::asio::dispatch(*context_, ...)`
- [ ] BitswapRequestContext has `std::mutex mutex_` and all 3 methods are guarded (HandleResponseTimeout does NOT double-lock)
- [ ] processReceivedBlocks() invokes HandleResponse AFTER releasing mutexRequestCallbacks_
- [ ] Context is erased from requestContexts_ under lock, HandleResponse uses the local shared_ptr copy

**Deadlock verification:**
- [ ] No lock ordering violation: C-7 eliminates the `mutexRequestCallbacks_ → BitswapRequestContext::mutex_` nesting by moving HandleResponse outside the lock
- [ ] C-5 dispatch chains do not create circular dependencies (dispatch is idempotent for same-events calls)
- [ ] C-6 HandleResponseTimeout does not double-lock (only HandleResponse acquires mutex_)

**Grep verification commands:**
```bash
# Verify dispatch wrappers exist in correct locations
rg 'boost::asio::dispatch' thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp -n

# Verify HandleResponse is called outside mutexRequestCallbacks_ lock
# (check that the lock guard scope ends before the HandleResponse call)

# Verify BitswapRequestContext::mutex_ is used
rg 'mutex_' thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp -n | rg 'requestContext\|BitswapRequestContext'
```

**Test verification:**
- Build with `BUILD_TESTING=ON`
- Run `ctest -R concurrency_content_request_test`
- Run `ctest -R concurrency_request_context_test`
- Run `ctest -R concurrency_callback_test`
- All tests pass without hanging or crashing
