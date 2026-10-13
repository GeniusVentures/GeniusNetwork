# Phase 2: Bitswap Callback Reentrancy - Pattern Map

**Mapped:** 2026-10-12
**Files analyzed:** 4 (3 modify, 1 conditional no-op)
**Analogs found:** 4 / 4 (all exact — every seam this phase touches has in-file prior art on the same branch)

**Track-gate (rule #3645):** all analog paths verified git-TRACKED via `git ls-files` inside the `thirdparty/ipfs-bitswap-cpp` submodule. Submodule confirmed on branch `dev_timer_correctness` @ `e2dc906` (matches D-11). No mirror/build-tree paths referenced.

**Key mapping fact:** Phase 2's strongest analog is **the Phase 1 changes already on this working tree**. `HandleResponse` restructure, `Cancel()`, and the 7-case race suite are the in-file patterns this phase extends. The `ContentRequestContext` timeout handler (`setupContentRequest`) supplies the outer-integration move-out shape and the map-assign idiom.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` (modify: `AddCallback` completed/replay branch, `HandleResponse` terminal-result store, `messageSent` find-or-replace + `AddCallback` outside lock, `processReceivedBlocks` erase-drop) | service (library core) | event-driven (timer + response dispatch) | In-file (3 anchors): Phase-1 `HandleResponse` (≈L95-118) for store-under-lock/dispatch-after; `setupContentRequest` timeout handler (≈L609-637) for outer-map-under-lock/dispatch-outside; `contentRequests_[cid] = ctx;` (≈L606) for insert-or-replace | exact |
| `thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp` (modify: `terminalResult_` member, `IsCompleted()` accessor) | model (class declaration) | — | In-file: existing `BitswapRequestContext` decl (≈L108-150); Phase 1's additive `Cancel()` slot is the direct precedent for both additions | exact |
| `thirdparty/ipfs-bitswap-cpp/test/bitswap_request_timer_race_test.cpp` (extend: ~6 new GTest cases) | test | event-driven (deterministic single-threaded `io_context`) | In-file: the 7 existing cases — each new case maps to a named idiom below | exact |
| `thirdparty/ipfs-bitswap-cpp/test/CMakeLists.txt` (only if sibling test target chosen — expected NO change) | config (build wiring) | — | In-file: `addtest( bitswap_request_timer_race_test ... )` block (L115-117) + its `target_link_libraries` list (L119-133) | exact (no-op expected) |

Line numbers are session-verified at HEAD `e2dc906` (structure independently confirmed by read this session; ±2-line drift possible in the `messageSent` region — verbatim excerpts are the authoritative anchors).

---

## Pattern Assignments

### `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` (service, event-driven)

**Analogs (3, all in-file):** Phase-1 landed `BitswapRequestContext::HandleResponse`; `ContentRequestContext` timeout handler in `setupContentRequest`; the `contentRequests_[cid] = ctx;` map-assign.

#### Seam 1 — `AddCallback` completed/replay branch (D-01..D-03)

**The code being modified** (≈L72-93, read at `e2dc906` this session — arms timer unconditionally, appends under `mutex_`; a completed context silently swallows the callback):

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (AddCallback, current)
    void BitswapRequestContext::AddCallback( BlockCallback callback )
    {
        std::lock_guard<std::mutex> guard( mutex_ );
        responseTimer_.expires_from_now( responseTimeout_ );
        // Capture shared_from_this so the armed timer keeps the context
        // alive until it fires — a raw `this` capture dangles once the last
        // external shared_ptr is released (requestContexts_.erase) while the
        // timer is still pending, and the later handler runs on freed memory.
        responseTimer_.async_wait(
            [self = shared_from_this()]( const boost::system::error_code &ec ) {
                // A canceled wait (completion disarm, consumer Cancel, or io
                // shutdown) arrives with operation_aborted — a canceled timer
                // is never a timeout; bail before the failure path (BSTP-01,
                // same ec-guard shape as the ContentRequestContext handler).
                if ( ec )
                {
                    return;
                }
                self->HandleResponseTimeout();
            } );
        callbacks_.emplace_back( std::move( callback ) );
    }
```

**The shape to port** — move-out-then-dispatch with the invocation strictly after the lock scope. Phase 1 landed this exact idiom in `HandleResponse` (≈L95-118):

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (HandleResponse, Phase-1 landed shape — KEEP, add only the terminalResult_ store)
    void BitswapRequestContext::HandleResponse( libp2p::outcome::result<std::string> block )
    {
        std::list<BlockCallback> callbacksToInvoke;
        {
            std::lock_guard<std::mutex> guard( mutex_ );
            if ( completed_ )
            {
                // A terminal result (success, timeout, or cancel) was already
                // delivered — drop the late transition (BSTP-02).
                return;
            }
            completed_         = true;
            responseTimer_.cancel();
            callbacksToInvoke  = std::move( callbacks_ );
            callbacks_.clear();
        }
        // Invoke consumers only after the lock is released — a callback may
        // re-enter Bitswap freely (D-04, same shape as the C-7 fix in
        // processReceivedBlocks).
        for ( auto &callback : callbacksToInvoke )
        {
            callback( block );
        }
    }
```

Planner notes for the replay branch:
- The `AddCallback` restructure mirrors this exactly: capture an `std::optional<libp2p::outcome::result<std::string>> replayResult` under `mutex_` (completed branch: copy `terminalResult_`, do NOT arm the timer — SC3 clause 2; incomplete branch: existing timer-arm + append verbatim), then invoke after the closing brace. RESEARCH Pattern 1 has the full recommended shape.
- `HandleResponse` gains exactly one line-class change: store the terminal outcome (`terminalResult_ = block;`) inside the lock beside `completed_ = true;`. Everything else stays.
- `Cancel()` (≈L128-134, sets `completed_` and clears callbacks, stores nothing) is unchanged — a canceled request keeps `terminalResult_` empty; late registration on it is dropped (RESEARCH Open Q1 — planner confirms this is the intended D-01 semantics: only success/timeout outcomes are replayable).

**Error-value idiom for the timeout store** — `HandleResponseTimeout` (≈L120-122) already produces the exact outcome to store and replay:

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp
    void BitswapRequestContext::HandleResponseTimeout()
    {
        HandleResponse( BitswapError::REQUEST_TIMEOUT );
    }
```

No new `BitswapError` values, no enum edit (prohibition 5) — D-03 symmetry falls out of storing whatever `HandleResponse` received.

#### Seam 2 — `messageSent` find-or-replace, `AddCallback` outside the outer lock (BSTP-04/D-04)

**The code being modified** (≈L378-393 — registration currently under `mutexRequestCallbacks_`; becomes a dispatch-under-outer-mutex hazard the moment D-02 replay lands):

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (messageSent registration block, current)
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

Target shape (RESEARCH Pattern 2): under the lock — find; reuse only if `!IsCompleted()`, else make a fresh context and **assign** into the map; outside the lock — the single `ctx->AddCallback( std::move( onBlockCallback ) );` call.

**Insert-or-replace analog** (≈L606, `setupContentRequest` — the only existing `operator[]`-assign into a guarded request map; this is the idiom D-04's `requestContexts_[cid] = ctx;` copies):

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (setupContentRequest)
        {
            std::lock_guard<std::mutex> guard( mutexContentRequests_ );
            contentRequests_[cid] = ctx;
        }
```

**Dispatch-with-no-lock-held precedent in the same function** (≈L374-376, the write-failure branch — `messageSent` already invokes a consumer callback before any lock is taken; the relocated `AddCallback` joins this class):

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (messageSent write-failure branch)
            onBlockCallback( BitswapError::MESSAGE_SENDING_FAILURE );
            return;
```

**Local-capture-then-call-outside-lock precedent** (≈L354-358, `writeBitswapMessageToStream` — `ctx` captured by value into the lambda, invoked after the enclosing scope; same lifetime shape `messageSent` needs for the hoisted `ctx`):

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (writeBitswapMessageToStream)
        rw->write<bitswap_pb::Message>(
            pb_msg,
            [ctx    = shared_from_this(),
             stream = std::move( stream ),
             cid( cid ),
             onBlockCallback = std::move( onBlockCallback )]( auto &&writtenBytes ) mutable
            { ctx->messageSent( writtenBytes, std::move( stream ), cid, std::move( onBlockCallback ) ); } );
```

#### Seam 3 — `processReceivedBlocks` retention (D-04/SC1): delete the erase

**The code being modified** (≈L320-341 — erase at :331 is the ONLY `requestContexts_.erase` in the file; keep find + `markProviderSuccess` under the lock, keep dispatch outside, delete the erase line):

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (processReceivedBlocks, current)
            std::shared_ptr<BitswapRequestContext> ctx;
            {
                std::lock_guard<std::mutex> callbacksGuard( mutexRequestCallbacks_ );
                auto                        itContext = requestContexts_.find( cid.value() );
                if ( itContext != requestContexts_.end() )
                {
                    if ( auto remotePeer = stream->remotePeerId() )
                    {
                        markProviderSuccess( cid.value(), remotePeer.value() );
                    }
                    ctx = itContext->second;
                    requestContexts_.erase( itContext );     // :331 — REMOVE for D-04
                }
                else
                {
                    logger_->warn( "No request context found for received block CID: {}", cidToString( cid.value() ) );
                }
            }
            if ( ctx )
            {
                ctx->HandleResponse( block );                // keep — outside the lock
            }
```

This is a **deletion, not new code**. Winner selection already lives in `HandleResponse`'s `completed_` check-and-set (≈L98-105) — duplicate/late blocks hit the completed gate and dispatch nothing. Note the local `std::shared_ptr<BitswapRequestContext> ctx` (≈L320) IS the BSTP-05 lifetime owner on this path — with the erase removed, the map entry becomes a second owner; both facts belong in the plan's lifetime-proof step.

#### Outer-integration reference — the original C-5/C-7 port source (read-only, do NOT modify)

`setupContentRequest`'s timeout handler (≈L609-637) is the canonical outer-tier find/flag/move-out/erase-under-lock + dispatch-after shape Phase 1 ported from; cited for structural reference only (content paths are out of scope, prohibition 1):

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (setupContentRequest timeout handler — OUT OF SCOPE, reference only)
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

**Includes pattern** (L1-20): plain relative includes (`"bitswap.hpp"`, `"bitswap_message.hpp"`), `<proto/unixfs.pb.h>`, `<boost/asio/deadline_timer.hpp>`. **New includes needed by Phase 2 cpp changes: none** (flag/optional/outcome all already reachable).

---

### `thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp` (model, class declaration)

**Analog:** the in-file declaration itself (≈L108-150) — Phase 1 already added the two kinds of members Phase 2 adds (a defaulted ctor param and an additive public method `Cancel()` with a `@brief` contract comment, plus the `bool completed_ = false;` member). Phase 2 copies that exact additive style.

**The declaration being extended** (current at `e2dc906`):

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp
    class BitswapRequestContext : public std::enable_shared_from_this<BitswapRequestContext>
    {
    public:
        BitswapRequestContext( boost::asio::io_context          &context,
                               boost::posix_time::time_duration responseTimeout
                                   = boost::posix_time::seconds( 5 ) );

        void AddCallback( BlockCallback callback );
        void HandleResponse( libp2p::outcome::result<std::string> block );

        /**
         * @brief Consumer-initiated cancellation — the request is retired with
         *        NO callback of any kind (BSTP-03 consumer-cancel clause).
         *        Sets completed_, cancels the timer, and clears callbacks under
         *        mutex_; never invokes a consumer callback.
         */
        void Cancel();

    private:
        void HandleResponseTimeout();

        /**
         * @mutex mutex_ — Guards callbacks_ list, responseTimer_, and completed_.
         *   Acquired in AddCallback() (under outer mutexRequestCallbacks_ in messageSent)
         *   and HandleResponse(). ...
         */
        std::mutex                       mutex_;
        std::list<BlockCallback>         callbacks_;
        bool                             completed_ = false;
        boost::asio::deadline_timer      responseTimer_;
        boost::posix_time::time_duration responseTimeout_;
    };
```

Additive slots (fork-internal, same class of change as Phase 1's `Cancel()`):
1. `bool IsCompleted() const;` — public, beside `Cancel()`; acquires `mutex_`, returns `completed_`. Doc-comment with `@brief` covering the TOCTOU-by-design note (outer check decides map reuse vs replacement; `AddCallback`'s completed-branch stays authoritative). Update the `@mutex` contract comment: after Phase 2, `AddCallback` is called **outside** `mutexRequestCallbacks_` in `messageSent` — the comment's parenthetical must change with the code.
2. `std::optional<libp2p::outcome::result<std::string>> terminalResult_;` — private member, initialized empty, slotted after `completed_`.

**Zero new includes:** `<optional>` is already at hpp L8 and `libp2p/outcome/outcome.hpp` at L9.

**Do not touch:** the `BitswapError` enum (≈L94-106) — replay uses existing `REQUEST_TIMEOUT` (prohibition 5); the `enable_shared_from_this` base (≈L108) — the `d2dc906` lifetime mechanism BSTP-05 builds on.

Style guardrails: `sgns::ipfs_bitswap` namespace, Ullman braces, trailing-underscore members, PascalCase methods, Doxygen `@brief` on new public API — all already followed by this header; new members slot in without drift.

---

### `thirdparty/ipfs-bitswap-cpp/test/bitswap_request_timer_race_test.cpp` (test, event-driven) — EXTEND

**Analog:** in-file — the 7 existing cases. Every new case composes idioms already proven in this file. Harness contract (header comment, L1-21): single-threaded `io_context`, injected durations (`seconds(60)` never-fires / `milliseconds(-1)` already-expired), `poll()`/`run_one()` stepping, **no sleeps, no worker threads** (SC4) — extend the ordering list in the header comment when adding cases.

**File skeleton new cases plug into** (L22-33):

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/test/bitswap_request_timer_race_test.cpp L22-33
#include <gtest/gtest.h>

#include <boost/asio.hpp>

#include <memory>
#include <string>
#include <vector>

#include "../src/bitswap.hpp"

using namespace sgns::ipfs_bitswap;
```

**Case construction idiom** (direct-context construction — no `Bitswap`, no libp2p host; every Phase 2 case uses this tier):

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/test/bitswap_request_timer_race_test.cpp (first test body)
    boost::asio::io_context io;

    auto context = std::make_shared<BitswapRequestContext>(
        io, boost::posix_time::seconds( 60 ) );

    int successCount = 0;
    int errorCount   = 0;

    context->AddCallback( [&successCount, &errorCount](
                              libp2p::outcome::result<std::string> result ) {
        if ( result )
        {
            ++successCount;
        }
        else
        {
            ++errorCount;
        }
    } );
```

**Per-new-case idiom anchors:**

| New case (names per RESEARCH, planner discretion) | In-file idiom source | What to copy |
|---|---|---|
| `ReentrantCancelOwnRequestNoDeadlock` (D-05a/D-06) | `ConsumerCancelProducesNoCallback` (~L285-316) + drain loops | `weak_ptr`/capture-by-ref callback body calling `Cancel()`; count asserts; add the bounded-step drain cap (D-06: `for ( step < 100 && io.poll() > 0 ) {}`) |
| `ReentrantChainNewRequestCallbackFires` (D-05b) | `ExpiryDequeuedThenCompletionYieldsSingleResult` (~L103-160) + `MultipleCallbacksDispatchedInRegistrationOrder` (~L322-364) | `io.post(...)` pre-queue + `run_one()` steps for the second context's completion; per-context counters; second `make_shared<BitswapRequestContext>` construction (multi-callback test shows two live contexts are fine) |
| `LateRegistrationOnCompletedReplaysStoredSuccess` (D-01/D-03) | `TerminalTransitionWithZeroCallbacksIsSafe` (~L318-341) | `EXPECT_EQ( io.poll(), 0 )` as the no-fresh-timer assertion (SC3 clause 2); synchronous-order flag set inside the late callback |
| `LateRegistrationOnTimedOutReplaysRequestTimeout` (D-01/D-03) | `GenuineTimeoutThenLateResponseSingleTimeout` (~L210-278) | The exact error-VALUE idiom: `lastErrorValue = result.error().value();` then `EXPECT_EQ( lastErrorValue, static_cast<int>( BitswapError::REQUEST_TIMEOUT ) );` — mirrored for the replayed result |
| `ReentrantAddCallbackOnCompletedDeliversReplayInline` (D-08) | `MultipleCallbacksDispatchedInRegistrationOrder` (ordering flags) + `ConsumerCancelProducesNoCallback` (reentry body) | Live callback whose body calls `AddCallback` on the same completed context; ordered flag (`replayRanBeforeOuterReturned`) proves the replay fired synchronously inside the outer callback's stack |
| no-fresh-timer fold (SC3) | `TerminalTransitionWithZeroCallbacksIsSafe` | drain-to-`poll()==0` after every late registration |

**Reused verbatim error-VALUE assertion idiom** (from `GenuineTimeoutThenLateResponseSingleTimeout`):

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/test/bitswap_request_timer_race_test.cpp
        else
        {
            ++errorCount;
            lastErrorValue = result.error().value();
        }
    ...
    EXPECT_EQ( lastErrorValue, static_cast<int>( BitswapError::REQUEST_TIMEOUT ) );
```

**Reused no-fresh-timer / drain idiom** (from `TerminalTransitionWithZeroCallbacksIsSafe`):

```cpp
// Source: thirdparty/ipfs-bitswap-cpp/test/bitswap_request_timer_race_test.cpp
    while ( io.poll() > 0 )
    {
    }

    EXPECT_EQ( io.poll(), 0 );
```

Platform guardrail (mandatory, from Phase 1 deviation A1/A3 notes): never assert on timer `error_code` identity — on MSVC 19.44/Boost 1.85 retired handlers arrive `operation_aborted` and `poll()` cannot deterministically extract expired timers; use `run_one()` for genuine-expiry extraction, `poll()==0` for no-fresh-timer. Replay is timer-free — the new replay/reentrancy cases must not depend on timer ec at all.

None of the 7 existing cases may be weakened or renamed (TEST-01: they must stay green).

---

### `thirdparty/ipfs-bitswap-cpp/test/CMakeLists.txt` (config) — expected NO change

**Analog:** the in-file registration block. Extending the existing source file requires zero CMake changes:

```cmake
# Source: thirdparty/ipfs-bitswap-cpp/test/CMakeLists.txt L115-117
# ── Bitswap request timer race test (GTest via addtest) ──
addtest(bitswap_request_timer_race_test
    bitswap_request_timer_race_test.cpp
)
```

If (and only if) the planner chooses a sibling file instead (agent discretion), copy the full block shape: `addtest( <name> <file>.cpp )` + the `target_link_libraries` list (L119-133) + `target_include_directories( ... ${GSL_INCLUDE_DIR} )` — the link list is also the authoritative dependency set for the WSL ASan link line (D-07).

---

## Shared Patterns

### Move-out-under-lock / dispatch-after-release
**Source:** `HandleResponse` (bitswap.cpp ≈L95-118) — landed Phase 1; `setupContentRequest` timeout handler (≈L619-636) — original C-5/C-7 shape.
**Apply to:** the `AddCallback` replay branch (capture replay result under `mutex_`, invoke after release) and the hoisted `ctx->AddCallback(...)` in `messageSent` (outer lock scope must close first). This is THE BSTP-04 pattern — every consumer invocation in Phase 2 code sits after the closing brace of every lock scope on its stack.

### `shared_from_this` lifetime across dispatch windows (BSTP-05)
**Source:** timer lambda `self = shared_from_this()` capture (bitswap.cpp ≈L81); Bitswap-tier `ctx = shared_from_this()` capture (`writeBitswapMessageToStream` ≈L355-358); local owning `std::shared_ptr<BitswapRequestContext> ctx` (`processReceivedBlocks` ≈L320, :330).
**Apply to:** every dispatch path — timer-lambda `self` (existing), `processReceivedBlocks` local `ctx` (existing), and the map entry itself once D-04 retention lands (new third owner). The lifetime proof is enumerative, not new code: show each dispatch path holds an owning reference for the duration of the callback loop, including through reentrant `Cancel()`.

### ec-guard in timer lambdas
**Source:** `AddCallback` lambda (≈L84-88) and `setupContentRequest` lambda (≈L614-617) — identical `if ( ec ) { return; }` shape.
**Apply to:** nothing new — the completed branch of `AddCallback` arms NO timer, so no new ec-guard site exists. Keep the existing guard untouched when restructuring.

### Bounded-step deterministic drain (SC4/D-06)
**Source:** the race suite's `while ( io.poll() > 0 ) {}` + `io.run_one()` idioms.
**Apply to:** every new case. D-06 upgrades the drain to a capped loop (`for ( step < N && io.poll() > 0 ) {}`) plus post-drain `EXPECT_EQ( io.poll(), 0 )` — a synthesized extension of the in-file idiom (see No Analog Found). No sleeps, no watchdog threads (Pitfall 3: a hang IS the red signal; triage timeouts as lock inversions).

### Greppable content-probe markers (Phase 4 pin chain)
**Source:** Phase 1 markers `completed_` (bitswap.hpp) and `REQUEST_TIMEOUT` (error mapping + timeout path).
**Apply to:** new Phase 2 identifiers in the same greppable style: `terminalResult_` (hpp member + both cpp touch points), `IsCompleted` (hpp accessor + `messageSent`), test names `LateRegistration*`/`Reentrant*`, and a `D-04`/until-replaced comment at the `requestContexts_[cid] = ctx;` replace-site.

### Map insert-or-replace under guard
**Source:** `contentRequests_[cid] = ctx;` under `mutexContentRequests_` (≈L606).
**Apply to:** `requestContexts_[cid] = ctx;` in `messageSent`'s replace branch (D-04) — `operator[]` assignment overwrites a completed entry in place; contrast with the current `emplace` (insert-only, no-op on existing key) which is precisely why stale completed entries survive today.

---

## No Analog Found

| Item | Kind | Reason / Planner guidance |
|------|------|---------------------------|
| Bitswap-tier map-policy unit coverage (`messageSent` find-or-replace, `processReceivedBlocks` retention) | test coverage gap | Not unit-reachable — these are `Bitswap` member functions needing a libp2p host. Use RESEARCH option (a): code-shape verification (greps: dispatch outside lock scopes; no `requestContexts_.erase` on block paths) + `bitswap_server_client_test` regression as the safety net. Optionally extend `bitswap_server_client_test` with a same-CID-second-request scenario if cheap (RESEARCH Q2). |
| Bounded-step (capped) drain loop | test idiom | Existing suite uses uncapped `while ( io.poll() > 0 ) {}`; D-06's bounded-step variant is RESEARCH-synthesized (`for ( int step = 0; step < 100 && io.poll() > 0; ++step ) {}`). No codebase precedent — take the shape from RESEARCH's skeleton. |
| WSL ASan evidence pipeline (D-07) | operational, not a source file | No codebase analog (rsync-over-`/mnt/w` throwaway copy + clang++ `-fsanitize=address` + prebuilt WSL `.a` set). Mechanics fully specified in RESEARCH §WSL ASan Run; not a pattern-mapping concern. |

## Metadata

**Analog search scope:** `thirdparty/ipfs-bitswap-cpp/src/` (bitswap.cpp targeted sections ≈L1-140, L295-420, L560-680; bitswap.hpp L1-220 full), `thirdparty/ipfs-bitswap-cpp/test/` (race suite full 342 lines; CMakeLists.txt full 140 lines), prior art `.planning/workstreams/ipfs-improve/phases/01-bitswap-timer-correctness/01-PATTERNS.md`.
**Files scanned:** 5 source/config files + 1 planning artifact; D-10 inventory (21 dispatch sites, RESEARCH) used as the site map — no re-derivation needed.
**Pattern extraction date:** 2026-10-12 (all reads at `dev_timer_correctness` @ `e2dc906`)
