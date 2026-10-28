# Phase 1: Bitswap Timer Correctness - Pattern Map

**Mapped:** 2026-10-12
**Files analyzed:** 4 (2 modify, 1 create, 1 possibly-modify)
**Analogs found:** 4 / 4 (3 exact, 1 partial — the race-test file has structure analogs but NO deterministic-stepping precedent)

All analog paths verified git-TRACKED via `git ls-files` inside their submodules (`thirdparty/ipfs-bitswap-cpp`, `SuperGenius`). No mirror/build-tree paths are referenced.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` (modify: `BitswapRequestContext` ctor + `AddCallback` + `HandleResponse` + `HandleResponseTimeout`) | service (library core) | event-driven (timer expiry + response dispatch) | In-file: `ContentRequestContext` timeout handler (`setupContentRequest`, same file L575-600) + `checkContentRequestComplete` (L925-940) | exact — the port source is in the same file |
| `thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp` (modify: ctor default param D-01; optional additive `Cancel()` per RESEARCH Q1/A2) | model (class declaration) | — | In-file: existing `BitswapRequestContext` decl (L108-129) + `ContentRequestContext` ctor-initialized-duration idiom (bitswap.cpp L100-103) | exact |
| `thirdparty/ipfs-bitswap-cpp/test/bitswap_request_timer_race_test.cpp` (CREATE — name is agent discretion) | test | event-driven (deterministic timer ordering) | `SuperGenius/test/src/bitswap/concurrency_request_context_test.cpp` (GTest structure, same subject) + `test/bitswap_server_client_test.cpp` (suite include conventions) | partial — GTest shape yes; deterministic `poll()` stepping has NO codebase analog (see No Analog Found) |
| `thirdparty/ipfs-bitswap-cpp/test/CMakeLists.txt` (modify: register new race test) | config (build wiring) | — | In-file: the three existing `add_executable`/`target_link_libraries`/`add_test` blocks (L11-44, L46-77, L79-115) + `addtest()` macro (`cmake/test.cmake` L8-27) | exact |

## Pattern Assignments

### `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` (service, event-driven)

**Analog:** the `ContentRequestContext` timeout handler in `setupContentRequest` (same file, L575-600) — the verbatim D-04 porting template — plus `checkContentRequestComplete` (L925-940) for the explicit `.cancel()`.

**The code being replaced** (L65-99, read at `d2ec18af` this session):

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp L65-67
    BitswapRequestContext::BitswapRequestContext( boost::asio::io_context &context ) :
        responseTimer_( context ), responseTimeout_( boost::posix_time::seconds( 5 ) )
    {
    }
```

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp L69-84
    void BitswapRequestContext::AddCallback( BlockCallback callback )
    {
        std::lock_guard<std::mutex> guard( mutex_ );
        responseTimer_.expires_from_now( responseTimeout_ );
        // Capture shared_from_this so the armed timer keeps the context
        // alive until it fires — a raw `this` capture dangles once the last
        // external shared_ptr is released (requestContexts_.erase) while the
        // timer is still pending, and the later handler runs on freed memory.
        responseTimer_.async_wait(
            [self = shared_from_this()]( const boost::system::error_code & ) {   // ec IGNORED (BSTP-01 bug)
                self->HandleResponseTimeout();
            } );
        callbacks_.emplace_back( std::move( callback ) );
    }
```

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp L86-99
    void BitswapRequestContext::HandleResponse( libp2p::outcome::result<std::string> block )
    {
        std::lock_guard<std::mutex> guard( mutex_ );
        responseTimer_.expires_at( boost::posix_time::pos_infin );               // disarm-by-infinity (SC1: must become .cancel())
        for ( auto &callback : callbacks_ )
        {
            callback( block );                                                   // invoked UNDER mutex_ (D-04 move-out)
        }
        callbacks_.clear();                                                       // no completion flag (BSTP-02 bug)
    }

    void BitswapRequestContext::HandleResponseTimeout()
    {
        HandleResponse( BitswapError::OUTBOUND_STREAM_FAILURE );                  // wrong error (D-06: REQUEST_TIMEOUT)
    }
```

**Core pattern to port — ec check + flag-under-lock + callback-moved-out** (L575-600, verbatim template from `setupContentRequest`):

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp L575-600
        // Set up timeout
        ctx->timeout.expires_from_now( ctx->contentTimeout_ );
        ctx->timeout.async_wait(
            [this, cid]( const boost::system::error_code &ec )
            {
                if ( ec )
                {
                    return;
                }

                // Erase context from map under lock, invoke callback outside lock
                // to prevent re-entrancy deadlock (same pattern as C-7 fix in
                // processReceivedBlocks).
                ContentCallback callback;
                {
                    std::lock_guard<std::mutex> guard( mutexContentRequests_ );
                    auto                        it = contentRequests_.find( cid );
                    if ( it != contentRequests_.end() && !it->second->timedOut )
                    {
                        it->second->timedOut = true;
                        callback             = std::move( it->second->callback );
                        contentRequests_.erase( it );
                    }
                }
                if ( callback )
                {
                    callback( BitswapError::CONTENT_REQUEST_TIMEOUT );
                }
            } );
```

Port adaptation notes for the planner:
- `BitswapRequestContext` has no outer map keyed by CID inside the class — the flag/callback extraction happens on `this` under `mutex_` only (lock-order contract below). The `timedOut`-style flag becomes a new private bool member (e.g. `completed_`) checked under `mutex_`.
- The `if (ec) return;` shape is the BSTP-01 fix — dropped into the existing `async_wait` lambda, which already captures `self = shared_from_this()` (keep that capture).

**Explicit `.cancel()` precedent** (L925-940, `checkContentRequestComplete`):

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp L925-940
    void Bitswap::checkContentRequestComplete( std::shared_ptr<ContentRequestContext> ctx )
    {
        if ( ctx->timedOut || !ctx->pendingCIDs.empty() || !ctx->filesInProgress.empty() )
        {
            return;
        }

        UnixFSContent content = assembleContent( ctx );
        ctx->timeout.cancel();
        ctx->callback( std::move( content ) );

        std::lock_guard<std::mutex> guard( mutexContentRequests_ );
        contentRequests_.erase( ctx->rootCID );
    }
```

`ctx->timeout.cancel()` at L932 is the disarm idiom SC1 requires — `HandleResponse` replaces `expires_at(pos_infin)` with `responseTimer_.cancel()` inside the `mutex_` critical section.

**Production call site — unchanged by D-01** (L344-358, `messageSent`; the `make_shared` at ~L353 compiles identically with the new default parameter):

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp L344-358
        {
            std::lock_guard<std::mutex> callbacksGuard( mutexRequestCallbacks_ );
            auto                        itCallbacks = requestContexts_.find( cid );
            if ( itCallbacks != requestContexts_.end() )
            {
                itCallbacks->second->AddCallback( std::move( onBlockCallback ) );
            }
            else
            {
                auto requestContext = std::make_shared<BitswapRequestContext>( *context_ );
                requestContext->AddCallback( std::move( onBlockCallback ) );
                requestContexts_.emplace( cid, std::move( requestContext ) );
            }
        }
```

**Error-mapping pattern** (L22-50) — `REQUEST_TIMEOUT` already has its message; D-06 needs no category change:

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp L22-32
OUTCOME_CPP_DEFINE_CATEGORY( sgns::ipfs_bitswap, BitswapError, e )
{
    using sgns::ipfs_bitswap::BitswapError;
    switch ( e )
    {
        case BitswapError::OUTBOUND_STREAM_FAILURE:
            return "failed to create an outbound stream";
        case BitswapError::MESSAGE_SENDING_FAILURE:
            return "cannot send bitswap message";
        case BitswapError::REQUEST_TIMEOUT:
            return "bitswap request timeout";
```

**Imports/includes pattern** (L1-20): plain relative includes for module headers (`"bitswap.hpp"`, `"bitswap_message.hpp"`), `<proto/unixfs.pb.h>` for generated protobuf, `<boost/asio/deadline_timer.hpp>` for the timer. New includes needed by the fix: none expected (`boost::posix_time` arrives via the deadline_timer header; the flag is a plain `bool`).

---

### `thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp` (model, class declaration)

**Analog:** the in-file class declaration itself (L108-129) plus the duration-as-ctor-member idiom from `ContentRequestContext` (bitswap.cpp L100-103: `contentTimeout_( boost::posix_time::seconds( 30 ) )` in the member-init list).

**Declaration to change** (L108-129, verbatim, includes the mutex contract the restructure must respect):

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp L108-129
    class BitswapRequestContext : public std::enable_shared_from_this<BitswapRequestContext>
    {
    public:
        BitswapRequestContext( boost::asio::io_context &context );

        void AddCallback( BlockCallback callback );
        void HandleResponse( libp2p::outcome::result<std::string> block );

    private:
        void HandleResponseTimeout();

        /**
         * @mutex mutex_ — Guards callbacks_ list and responseTimer_.
         *   Acquired in AddCallback() (under outer mutexRequestCallbacks_ in messageSent)
         *   and HandleResponse(). HandleResponseTimeout() does NOT acquire mutex_ —
         *   it forwards to HandleResponse which handles its own locking.
         */
        std::mutex                       mutex_;
        std::list<BlockCallback>         callbacks_;
        boost::asio::deadline_timer      responseTimer_;
        boost::posix_time::time_duration responseTimeout_;
    };
```

D-01 target shape (from the locked decision): `BitswapRequestContext( boost::asio::io_context &context, boost::posix_time::time_duration responseTimeout = boost::posix_time::seconds( 5 ) );` with member init `responseTimeout_( responseTimeout )`. Additive private bool (completion flag) and — if the planner accepts RESEARCH A2 — a small public `Cancel()` slot in beside `HandleResponse`. The class already derives `enable_shared_from_this` (the `d2ec18a` capture fix builds on it; do not remove).

**Enum to reuse** (L94-106) — D-06 uses the existing value, no enum edit:

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp L94-106
    enum class BitswapError : uint8_t
    {
        OUTBOUND_STREAM_FAILURE = 1,
        MESSAGE_SENDING_FAILURE,
        REQUEST_TIMEOUT,
        INVALID_UNIXFS_DATA,
        IPLD_DECODE_FAILURE,
        CONTENT_REQUEST_TIMEOUT,
        FILE_NOT_FOUND,
        ENCODING_FAILURE,
        BLOCK_NOT_FOUND,
        NO_PROVIDERS_AVAILABLE
    };
```

Header-guard/naming conventions: `sgns::ipfs_bitswap` namespace, Ullman braces, `m_`/trailing-underscore members, PascalCase methods — already followed by this header; new members slot in without style drift. Note `HandleResponseTimeout` is private (L117) — tests must reach the timeout through the timer itself (the 0 ms duration recipe does this naturally).

---

### `thirdparty/ipfs-bitswap-cpp/test/bitswap_request_timer_race_test.cpp` (test, event-driven) — CREATE

**Primary analog (GTest structure, same subject):** `SuperGenius/test/src/bitswap/concurrency_request_context_test.cpp`

```cpp
// Source: SuperGenius/test/src/bitswap/concurrency_request_context_test.cpp L1-11
#include "stubs.hpp"

#include <gtest/gtest.h>
#include <thread>
#include <atomic>
#include <vector>
#include <chrono>
#include "testutil/wait_condition.hpp"

using namespace sgns::ipfs_bitswap;
```

```cpp
// Source: SuperGenius/test/src/bitswap/concurrency_request_context_test.cpp L20-38 (doc + first TEST_F)
/**
 * @given a BitswapRequestContext with C-6 mutex guard
 * @when HandleResponseTimeout fires from deadline_timer while HandleResponse is called
 * @then both serialize via mutex_ — no crash and no double callback
 */
TEST_F( RequestContextTimerTest, ResponseTimeoutDuringResponse )
{
    std::atomic<int>  errors{ 0 };
    std::atomic<bool> running{ true };
    ...
```

Copy from this analog: `#include <gtest/gtest.h>`, plain `TEST`/`TEST_F` naming, the `@given/@when/@then` doc-comment convention, callback-capture into local vectors for assertion. **Do NOT copy its determinism approach** — it drives races with 4 spin threads + `std::this_thread::sleep_for( std::chrono::seconds( 1 ) )` (L57-94), exactly what SC4 forbids. The new file drives orderings with injected 0 ms/long durations + `poll()` stepping (no analog — see No Analog Found).

**Secondary analog (suite file conventions):** `thirdparty/ipfs-bitswap-cpp/test/bitswap_server_client_test.cpp`

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/test/bitswap_server_client_test.cpp L1-2, L21-26 (abridged)
#include <iostream>
#include <memory>
...
#include <boost/asio.hpp>
...
#include "../src/bitswap.hpp"
#include "../src/logger.hpp"

using namespace sgns::ipfs_bitswap;
```

Copy from this analog: the relative include `"../src/bitswap.hpp"`, `using namespace sgns::ipfs_bitswap;`, `<boost/asio.hpp>` for `io_context`. The new file needs far less — it constructs `BitswapRequestContext` directly (public API: ctor, `AddCallback`, `HandleResponse`), so no libp2p host injector, no `BitswapNode` fixture, no threads. Existing tests are plain-`main()` (L929-946: `int main()` with try/catch returning 0/1) — the new file deliberately departs from that by using GTest (per RESEARCH Pitfall 4 recommendation; `addtest()` links `gtest_main`).

**Harness skeleton the planner should hand the executor** (composition of the above + RESEARCH recipe — the four orderings from RESEARCH "Race-Test Mechanics"):

```cpp
// No codebase analog — synthesized from RESEARCH.md. Single-threaded, no sleeps.
//   ordering 1: long duration; AddCallback(cb); HandleResponse(success); poll() → aborted handler no-ops
//   ordering 2: 0ms duration; AddCallback(cb); io.post(HandleResponse); poll() → late-expired handler (ec==success) dropped by flag
//   ordering 3: long duration; response then poll-to-exhaustion → proves aborted handler ran and fired nothing
//   ordering 4: 0ms duration; poll() → exactly one REQUEST_TIMEOUT; late HandleResponse(success) dropped by flag
#include <gtest/gtest.h>
#include <boost/asio.hpp>
#include "../src/bitswap.hpp"

using namespace sgns::ipfs_bitswap;
```

Per-ordering assertions track callback counts (success count, error count, and the error value being `BitswapError::REQUEST_TIMEOUT`) in lambdas captured by reference. Ordering 2 must empirically assert the posted-lambda-before-expired-handler FIFO assumption (RESEARCH A1) and fall back to two `poll_one()` steps if MSVC/Asio disagrees.

---

### `thirdparty/ipfs-bitswap-cpp/test/CMakeLists.txt` (config, build wiring)

**Analog:** the three existing registration blocks in the same file. Full pattern for one test (L46-77):

```cmake
# Source: thirdparty/ipfs-bitswap-cpp/test/CMakeLists.txt L46-77
# Add our server-client test
add_executable(bitswap_server_client_test
    bitswap_server_client_test.cpp
)

target_link_libraries(bitswap_server_client_test
    ipfs-bitswap-cpp
    ipfs-bitswap-proto
    ipfs-unixfs-proto
    spdlog::spdlog
    Boost::Boost.DI
    p2p::p2p_basic_host
    p2p::p2p_multiaddress
    p2p::p2p_ping
    p2p::p2p_identify
    p2p::p2p_identify_proto
    p2p::p2p_default_host
    p2p::p2p_default_network
    ipfs-lite-cpp::ipld_node
    ${WIN_CRYPT_LIBRARY}
    ${Boost_LIBRARIES}
)

target_include_directories(bitswap_server_client_test PRIVATE
    ${GSL_INCLUDE_DIR}
)

set_target_properties(bitswap_server_client_test PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
)

add_test(NAME BitswapServerClientTest COMMAND bitswap_server_client_test)
```

**Recommended registration for the new race test** — `addtest()` macro (`cmake/test.cmake` L8-27), which links `gtest_main`/`gmock_main`, emits xunit XML, and registers ctest:

```cmake
# Source: thirdparty/ipfs-bitswap-cpp/cmake/test.cmake L8-27
function(addtest test_name)
  add_executable(${test_name} ${ARGN})
  addtest_part(${test_name} ${ARGN})
  target_link_libraries(${test_name}
      GTest::gtest_main
      GTest::gmock_main
      )
  file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/xunit)
  set(xml_output "--gtest_output=xml:${CMAKE_BINARY_DIR}/xunit/xunit-${test_name}.xml")
  add_test(
      NAME ${test_name}
      COMMAND $<TARGET_FILE:${test_name}> ${xml_output}
  )
  set_target_properties(${test_name} PROPERTIES
      RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/test_bin
      ARCHIVE_OUTPUT_PATH ${CMAKE_BINARY_DIR}/test_lib
      LIBRARY_OUTPUT_PATH ${CMAKE_BINARY_DIR}/test_lib
      )
  disable_clang_tidy(${test_name})
endfunction()
```

Wiring to add (RESEARCH-verified): `addtest(bitswap_request_timer_race_test bitswap_request_timer_race_test.cpp)` followed by explicit `target_link_libraries(bitswap_request_timer_race_test ipfs-bitswap-cpp ipfs-bitswap-proto ipfs-unixfs-proto ipfs-merkledag-proto)` — `addtest()` links only GTest, so the library targets must be appended. Note the exe lands in `${CMAKE_BINARY_DIR}/test_bin` (VS multi-config: `test_bin/Debug/`), unlike the three existing exes in `test/Debug/`. GTest is already `find_package`-d by the top-level `CMakeLists.txt` when `TESTING=ON` (L57-61); no new find_package needed.

---

## Shared Patterns

### Terminal-state transition under mutex; callback dispatch outside the lock

**Source:** `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` L575-600 (excerpt above)
**Apply to:** the restructured `BitswapRequestContext::HandleResponse` AND the rewritten `async_wait` lambda in `AddCallback` — both become: take `mutex_`; check completion flag; if not complete, set flag, `.cancel()` (response path) / mark timed-out (timeout path), `std::move` callbacks out to a local, clear the list; release lock; invoke the moved-out callbacks. This is the D-04 restructure and the Phase-2 reentrancy groundwork in one shape.

### Explicit timer disarm via `.cancel()`, never `expires_at(pos_infin)`

**Source:** `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` L932 (`ctx->timeout.cancel()` in `checkContentRequestComplete`)
**Apply to:** `BitswapRequestContext::HandleResponse`. Note (Boost 1.85 header, verified in RESEARCH): changing expiry also cancels pending waits — the current code's bug is the ec-ignoring handler, not a missing cancel; `.cancel()` is still required so the abort signal is explicit and the handler can distinguish cancel from expiry via `operation_aborted`.

### Lock-order contract: `mutexRequestCallbacks_` → `mutex_`, nothing else inside the class

**Source:** `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` L344-358 (`messageSent` holds `mutexRequestCallbacks_` while calling `AddCallback`) + the hpp contract comment L119-124
**Apply to:** every new line in `BitswapRequestContext`. The restructure must acquire only `mutex_`; never `mutexRequestCallbacks_` from inside the class. Also: `processReceivedBlocks` calls `HandleResponse` AFTER releasing the outer lock — `HandleResponse` may not assume any outer lock in either direction.

### Keep the `shared_from_this()` timer capture

**Source:** `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` L74-84 (the `d2ec18a` use-after-free fix, comment included in excerpt above)
**Apply to:** the rewritten `async_wait` lambda — preserve `[self = shared_from_this()]` so the armed timer keeps the context alive; the race tests rely on it for the late-handler window.

### Error classification via existing enum + category

**Source:** `thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp` L94-106 + `bitswap.cpp` L22-50
**Apply to:** `HandleResponseTimeout` → `BitswapError::REQUEST_TIMEOUT` (D-06). No enum entry, no category edit, no header change for this piece.

### Test registration + build invocation

**Source:** `test/CMakeLists.txt` L46-77 + `cmake/test.cmake` L8-27
**Apply to:** the new race test only. Build/run via the RESEARCH-verified recipe (configure with the full `-D*_DIR` hint set, `cmake --build ... --target bitswap_request_timer_race_test --parallel 4`, `ctest --test-dir <tree> -C Debug`, or the exe directly with `--gtest_filter`). **Disk-space gate first:** W: has ~582 KB free; freeing ≥1 GB (or consciously using the proven C: probe tree) is the phase's first checkpoint — MSVC fails with misleading `C1033` PDB errors when the drive is full.

## No Analog Found

Files/mechanisms with no close codebase match (planner uses RESEARCH.md patterns instead):

| Item | Role | Data Flow | Reason |
|------|------|-----------|--------|
| Deterministic single-threaded `io_context` stepping (`poll()`/`poll_one()` race-ordering driver) | test harness | event-driven | No sleep-free deterministic-stepping precedent exists anywhere in the workspace. `thirdparty/AsyncIOManager/test/testutil/asio_helpers.hpp` L56-70 `pollUntil` is the explicit ANTI-example (background thread + `std::this_thread::sleep_for`). `SuperGenius/test/src/bitswap/concurrency_request_context_test.cpp` is likewise thread+sleep based. Use the RESEARCH.md "Race-Test Mechanics" recipe verbatim (0 ms / long injected durations + posted lambdas + single `poll()`); RESEARCH A1/A3 flag the two assumptions the executor must verify empirically. |
| Additive public `Cancel()` on `BitswapRequestContext` (RESEARCH Q1/A2, planner decides) | model API | event-driven | No cancel API exists anywhere in the class or on `Bitswap`. The closest shape is the under-lock portion of the restructured `HandleResponse` itself (flag + `.cancel()` + clear callbacks, no invocation) — i.e., the pattern is being introduced by this phase, not copied. |

## Metadata

**Analog search scope:** `thirdparty/ipfs-bitswap-cpp/{src,test,cmake}` (submodule, tracked at `d2ec18af`), `SuperGenius/test/src/{bitswap,processing_conformance_cancellation,processing}` (submodule), `thirdparty/AsyncIOManager/test/testutil` (anti-example check)
**Files scanned:** bitswap.cpp (4 targeted ranges), bitswap.hpp, test/CMakeLists.txt, cmake/test.cmake, bitswap_server_client_test.cpp (2 ranges), concurrency_request_context_test.cpp, cancellation_conformance_test.cpp (structure reference)
**Tracked-source gate:** all 6 named analog paths verified via `git ls-files` in their submodules — all tracked, no mirrors
**Pattern extraction date:** 2026-10-12
