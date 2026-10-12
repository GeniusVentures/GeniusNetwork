# Architecture Research

**Domain:** P0 remediation of the GNUS C++ libp2p/IPFS stack — Bitswap timer/reentrancy fixes and GossipSub resource bounds
**Researched:** 2026-10-12
**Workstream:** ipfs-improve (milestone v1.0)
**Confidence:** HIGH (all change points read directly from the pinned working tree at `thirdparty/` commits libp2p `10166f9c`, ipfs-bitswap-cpp `d2ec18af`, ipfs-pubsub `b9f051f8`)

> Prior child-wallet architecture doc archived as `ARCHITECTURE-childwallet-v2.4-archived.md`. Prior stack audit: `gnus_libp2p_comparison.md` (its P0 rows 2–3 are exactly this milestone's scope).

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Consumers (verified against, NOT modified)                              │
│  SuperGenius: src/account/GeniusNode.cpp (builds gossip Config, owns     │
│    pubsub_), src/account/AccountMessenger.{cpp,hpp} (topic subs),        │
│    src/crdt/globaldb/globaldb.cpp (PubSubBroadcasterExt),                │
│    src/storage + src/processing (via ipfs_lite DAGSyncer)                │
│  GeniusSDK: links SuperGenius static lib — no direct gossip/bitswap API  │
├──────────────────────────────────────────────────────────────────────────┤
│  Wrapper layer (config plumbing surface)                                 │
│  thirdparty/ipfs-pubsub/src/ipfs_pubsub/gossip_pubsub.{hpp,cpp}          │
│    - GossipPubSub(keypair, libp2p::protocol::gossip::Config[, pnet key]) │
│    - GetDefaultConfig() static; config_ member; gossip::create(config_)  │
├──────────────────────────────────────────────────────────────────────────┤
│  Protocol implementations (ALL changes live here)                        │
│  ┌──────────────────────────┐  ┌───────────────────────────────────────┐ │
│  │ ipfs-bitswap-cpp         │  │ libp2p (gossip/)                      │ │
│  │ src/bitswap.cpp          │  │  include/.../gossip/gossip.hpp (CFG)  │ │
│  │  BitswapRequestContext   │  │  src/.../impl/remote_subscriptions.hpp│ │
│  │   - timer arm/cancel     │  │  src/.../impl/stream.{hpp,cpp}        │ │
│  │   - callback dispatch    │  │  src/.../impl/message_parser.cpp      │ │
│  │ test/ (GTest, own ctx)   │  │  test/ (GTest)                        │ │
│  └──────────────────────────┘  └───────────────────────────────────────┘ │
├──────────────────────────────────────────────────────────────────────────┤
│  Boost.Asio io_context per node (Bitswap::context_ — shared_ptr,         │
│  injected; GossipSub uses libp2p basic::Scheduler over the host context) │
└──────────────────────────────────────────────────────────────────────────┘
Change flow (per fix): submodule repo fix+test → push → thirdparty pin
update → SuperGenius rebuild → GeniusSDK rebuild.
```

### Component Responsibilities

| Component | Responsibility | Where the P0 work touches it |
|-----------|----------------|------------------------------|
| `sgns::ipfs_bitswap::BitswapRequestContext` | One CID's pending want: arms a 5 s `boost::asio::deadline_timer`, holds `callbacks_` vector, guarded by `mutex_` | **Modified** — timer-cancellation guard + callback-outside-lock (`bitswap.cpp:65-99`) |
| `sgns::ipfs_bitswap::Bitswap` | Owns `context_` (shared_ptr io_context), `requestContexts_` map CID→context under `mutexRequestCallbacks_`, dispatches received blocks (`processReceivedBlocks` L268-305) | Unchanged (its own locking at L286→L304 is already correct: erase under guard, `HandleResponse` after) |
| `libp2p::protocol::gossip::RemoteSubscriptions` | `table_` unordered_map<TopicId, TopicSubscriptions> of remote peers' subscriptions; fed by `onPeerSubscribed` (creates entries), drained partly in `onHeartbeat` | **Modified** — bound `table_` size (TODO at `remote_subscriptions.hpp:75-77` says exactly this: "bound table size (which may grow!) by removing items not subscribed to locally") |
| `libp2p::protocol::gossip::Stream` | Per-peer RPC reader/writer; `pending_buffers_` deque + `pending_bytes_` grow when `writing_bytes_ > 0` | **Modified** — bound pending bytes, close slow streams (TODO at `stream.hpp:64-70`) |
| `libp2p::protocol::gossip::Config` (`gossip.hpp:~60-90`) | Value struct threaded to `Stream` and `RemoteSubscriptions` ctors (both already receive `const Config &`) | **Modified** — add bound fields with safe defaults |
| `MessageParser` (`message_parser.cpp`) | Decodes inbound RPC → dispatches to receivers (`onGraft`/`onPrune`/`onTopicMessage`/`onMessageEnd`) | Read-only context: bounds are enforced at the receivers (`RemoteSubscriptions`), not in the parser; prune path carries the meshsub-1.1 signed-peer-record TODO (L~98) which stays out of scope |
| `ipfs_pubsub::GossipPubSub` | DI-assembles host/injector, passes `config_` into `gossip::create` (gossip_pubsub.cpp:301-307) | **Modified (plumbing only)** — nothing new required unless defaults need overriding; `GetDefaultConfig()` (hpp:304-311) gains the new fields implicitly |
| SuperGenius `GeniusNode` | Builds the production `gossip::Config` inline (GeniusNode.cpp:1872-1878) then constructs `GossipPubSub` (L1898/1904) | Optionally modified to set explicit bound values; otherwise inherits gossip.hpp defaults |

## Recommended Project Structure

No new directories. All work lands in existing submodule trees:

```
ipfs-bitswap-cpp/            (repo: GeniusVentures/ipfs-bitswap-cpp, branch develop)
├── src/bitswap.cpp          # MODIFIED: two surgical fixes (see Data Flow A)
└── test/
    └── bitswap_request_context_test.cpp   # NEW: cancel_then_no_error_callback,
                                           #      callback_reentrancy (see Patterns)

libp2p/                      (repo: GeniusVentures/libp2p, branch master)
├── include/libp2p/protocol/gossip/gossip.hpp        # MODIFIED: Config bound fields
├── src/protocol/gossip/impl/remote_subscriptions.{hpp,cpp}  # MODIFIED: table bound
├── src/protocol/gossip/impl/stream.{hpp,cpp}        # MODIFIED: pending-bytes bound
└── test/protocol/gossip/    # NEW/EXTENDED tests near existing gossip tests

thirdparty/                  (repo: GeniusVentures/thirdparty)
└── ipfs-bitswap-cpp, libp2p # PIN UPDATE commits after submodule pushes

SuperGenius/                 # rebuild + test verification only (optional Config override)
GeniusSDK/                   # rebuild verification only (no source change)
```

### Structure Rationale

- **Fixes belong in the submodules, not vendored locally:** every consumer (SuperGenius, GeniusSDK, any future Go-interop harness) gets them via the pin chain; local patching forks the tree and breaks the documented change flow.
- **Tests live beside each submodule's existing GTest suite** (`ipfs-bitswap-cpp/test/` already hosts the `BitswapNode` harness pattern; libp2p has `test/protocol/gossip/`), so CI in each repo gates the fix independently of SuperGenius.

## Architectural Patterns

### Pattern 1: Cancellation-aware Asio timer handler

**What:** A `deadline_timer::async_wait` handler must distinguish "timer expired" from "timer was canceled" via the error code.
**When:** whenever a timer is armed per-request and canceled on success — exactly `BitswapRequestContext`.
**Trade-offs:** one-line guard; zero behavioral change for genuine timeouts.

Current code (`bitswap.cpp:78-82`) discards the error code:

```cpp
responseTimer_.async_wait(
    [self = shared_from_this()]( const boost::system::error_code & ) {  // BUG: ignored
        self->HandleResponseTimeout();
    } );
```

Fix:

```cpp
responseTimer_.async_wait(
    [self = shared_from_this()]( const boost::system::error_code &ec ) {
        if ( !ec || ec == boost::asio::error::operation_aborted ) {
            if ( ec == boost::asio::error::operation_aborted ) return;  // canceled ⇒ not a timeout
        }
        if ( ec ) return;              // any other error: nothing sensible to report
        self->HandleResponseTimeout(); // only a genuine expiry is a timeout
    } );
```

(Simplified: `if (ec) return; self->HandleResponseTimeout();` — canceled or failed waits are silent; only a clean expiry reports `OUTBOUND_STREAM_FAILURE`.)

**Why it matters here:** `AddCallback` **re-arms** the timer on every call (`expires_from_now` at L73 cancels any prior pending wait). The retry path (`RequestBlockWithRetry` → `messageSent` → L345-349 re-`AddCallback` on an existing context) therefore guarantees aborted handlers fire mid-request. Today those aborted handlers call `HandleResponseTimeout()` → `HandleResponse(OUTBOUND_STREAM_FAILURE)` → consumer callbacks fire with a **false error and are cleared**, and the block that arrives later is dropped (`HandleResponse` on empty `callbacks_`, L85-93). That is the concrete false-failure + block-loss chain the regression test pins.

### Pattern 2: Callbacks outside the critical section

**What:** Never invoke consumer callbacks while holding the mutex that guards the callback container.
**When:** any producer/consumer dispatch under a lock — `HandleResponse` here.
**Trade-offs:** requires copying callbacks out and clearing under the lock, then invoking after release; slight allocation cost, eliminates deadlock class.

Current (`bitswap.cpp:85-93`): `callback(block)` runs under `guard(mutex_)`. A callback that re-enters the same context (the UnixFS traversal in this very file does exactly this — `FetchContent` chains `RequestBlock` callbacks, L377-415, and the retry path re-`AddCallback`s the same context, which takes `mutex_` again) deadlocks on the non-recursive `std::mutex`.

Fix shape:

```cpp
void BitswapRequestContext::HandleResponse( outcome::result<std::string> block ) {
    std::vector<BlockCallback> to_invoke;
    {
        std::lock_guard<std::mutex> guard( mutex_ );
        responseTimer_.expires_at( boost::posix_time::pos_infin );
        to_invoke = std::move( callbacks_ );
        callbacks_.clear();
    }
    for ( auto &cb : to_invoke ) cb( block );   // outside the lock
}
```

### Pattern 3: Bounded remote-driven state (the GossipSub resource bounds)

**What:** Any container grown by untrusted remote input (peer SUBSCRIBEs, outbound writes to a slow peer) needs a config-driven ceiling with a defined overflow behavior.
**When:** `RemoteSubscriptions::table_` (attacker grows topic entries) and `Stream::pending_buffers_`/`pending_bytes_` (slow reader grows writer queue).
**Trade-offs:** bounds can drop legitimate subscriptions under pathological topic counts; the TODO-prescribed policy ("remove items not subscribed to locally") keeps locally-interesting topics immune.

- `RemoteSubscriptions`: bound check belongs in `onPeerSubscribed`/`getItem(topic, create_if_not_exist=true)` — if `table_.size() >= config_.max_remote_subscription_topics` and the topic is not locally subscribed and not already present, ignore the subscription (log + drop). The existing `onHeartbeat` sweep (remote_subscriptions.cpp:145-147) already erases empty/non-local entries, so the cap plus sweep converge.
- `Stream`: bound check belongs at the top of `write()` (stream.cpp:123-147) — if `pending_bytes_ + buffer->size() > config_.max_pending_bytes_per_stream`, `asyncPostError(Error::WRITER_TIMEOUT)` (existing error channel → `Feedback` → peer context tears the stream down), exactly what the `stream.hpp:64-70` TODO sketches ("limit pending bytes and close slow streams that way").
- `message_parser.cpp` stays untouched for these bounds: the parser is a pure decoder; enforcement lives in the receivers it dispatches to. (Its L~98 TODO is meshsub-1.1 signed peer records — explicitly out of scope.)

## Data Flow

### A. Bitswap request lifecycle (fix sites marked)

```
RequestBlock(pi, cid, cb)                       bitswap.cpp:426
  └─ RequestBlockWithRetry(..., 0)              :431  retry ladder
       └─ ... onBlockCallback
            └─ messageSent(written, stream, cid, cb)   :330
                 ├─ write error → cb(MESSAGE_SENDING_FAILURE)         :340
                 └─ context exists? under mutexRequestCallbacks_     :345-349
                      ├─ YES → ctx->AddCallback(cb)  ◄── RE-ARMS TIMER (cancels prior wait)
                      └─ NO  → new BitswapRequestContext(*context_)  :353
                                 └─ AddCallback(cb)
AddCallback(cb)                                 bitswap.cpp:70-83   [MOD-FIX1 site]
  ├─ lock mutex_
  ├─ responseTimer_.expires_from_now(5 s)   ← cancels any pending wait ⇒ aborted handler queued
  ├─ async_wait( handler IGNORING ec )      ◄── FIX 1: if (ec) return;
  └─ callbacks_.emplace_back(cb)

                                   ┌── race ───────────────────────────────┐
network: BitswapMessage arrives    │            timer expires (5 s)        │
  onMessageOutcome :119/224        │                                        │
  └─ processReceivedBlocks :268    │  async_wait fires (ec == success)      │
       ├─ lock mutexRequestCallbacks_       │                              │
       ├─ find(cid) → ctx; ERASE from map   │  HandleResponseTimeout :96    │
       ├─ unlock (guard scope ends)         │    └─ HandleResponse(ERR)     │
       └─ ctx->HandleResponse(block) :304   │         lock mutex_           │
            lock mutex_                     │         invoke callbacks(ERR) │
            expires_at(pos_infin)  ◄────────┤         clear                │
            invoke callbacks(block)  ◄── FIX 2: invoke AFTER unlock        │
            clear callbacks_                │                              │
            unlock                          │  aborted handler (op_aborted) │
                                           │    currently ALSO calls       │
                                           │    HandleResponseTimeout       │
                                           │    → false ERR + cleared cbs   │
                                           └───────────────────────────────┘
```

**Ownership:** the `io_context` is `Bitswap::context_` (shared_ptr, ctor-injected — `bitswap.cpp:108-109`; tests inject via `injector.create<std::shared_ptr<boost::asio::io_context>>()` and run it on a dedicated thread with a work guard, `bitswap_server_client_test.cpp:173-216`). The request context lifetime is `shared_ptr` in `requestContexts_`, kept alive through the armed timer by the existing `shared_from_this()` capture (L74-82 comment) — that lifetime fix is already present; do not regress it.

**Regression test hook (`cancel_then_no_error_callback`)** — pure unit test, no full `BitswapNode` needed:

1. `boost::asio::io_context io; auto ctx = std::make_shared<BitswapRequestContext>(io);`
2. `ctx->AddCallback(recorder);` (arm t₁) then `ctx->AddCallback(recorder);` (re-arm ⇒ t₁ canceled ⇒ aborted handler queued — this is the production retry interleaving).
3. Run `io.run()` to completion; assert recorder saw **no** `OUTBOUND_STREAM_FAILURE` (before the fix it sees one, and callbacks are cleared).
4. Variant: `AddCallback` once → `HandleResponse("data")` success → `io.run()` → assert exactly one success callback and no second error invocation.

**Reentrancy test:** `AddCallback(cb)` where `cb` itself calls `ctx->AddCallback(cb2)` (simulating the chained UnixFS fetch). Before fix 2 this deadlocks (hang — guard with a test timeout/`std::async` + `wait_for`); after fix 2 it completes.

### B. GossipSub data flow (bound sites marked)

```
remote peer ──RPC──► Stream::onLengthRead/onMessageRead        stream.cpp:49-118
                       └─ MessageParser::parse + dispatch      message_parser.cpp
                            ├─ onPeerSubscribed(peer, topic) ─► RemoteSubscriptions  [BOUND-1 site]
                            │    └─ getItem(topic, create=true)                     remote_subscriptions.cpp:44-61
                            │         table_[topic] grows forever                    TODO hpp:75-77
                            │         FIX: cap at config.max_remote_subscription_topics;
                            │              drop if not locally subscribed & table full
                            ├─ onGraft/onPrune ─► mesh bookkeeping (unchanged; parser
                            │    prune-branch L~98 TODO = meshsub 1.1, OUT OF SCOPE)
                            └─ onTopicMessage ─► RemoteSubscriptions::onNewMessage
                                                  └─ TopicSubscriptions → local subscribers
local publish ──► GossipPubSub::Publish ─► gossip core ─► Stream::write(serialized)   [BOUND-2 site]
                       stream.cpp:123-147
                       ├─ writing_bytes_ > 0 → pending_buffers_.emplace_back
                       │   pending_bytes_ += size          grows forever on slow peer   TODO hpp:64-70
                       │   FIX: if pending_bytes_ > config.max_pending_bytes_per_stream
                       │        → asyncPostError(WRITER_TIMEOUT) → Feedback closes stream
                       └─ onMessageWritten drains deque → beginWrite(next)
                          (rw_timeout handle already exists: beginWrite/endWrite L168-252)
```

**Config plumbing chain (the full thread):**

```
libp2p gossip.hpp Config                      ← ADD: max_remote_subscription_topics,
  │                                              max_pending_bytes_per_stream (safe defaults)
  ├─► Stream ctor (already takes const Config&)            stream.hpp:47
  ├─► RemoteSubscriptions ctor (already takes const Config&)  remote_subscriptions.hpp:28
  │
  └─► ipfs-pubsub gossip_pubsub.hpp:95/103/114  GossipPubSub(..., Config config)
        ├─ config_ member (hpp:314) — GetDefaultConfig() (hpp:304-311) picks up defaults automatically
        └─ gossip_pubsub.cpp:301-307  gossip::create(..., config_)
              │
              └─► SuperGenius GeniusNode.cpp:1872-1878  builds Config inline
                    (echo_forward=false, sign=true, seen_cache_limit=10,
                     heartbeat=500 ms, rw_timeout=30 s)
                    → make_shared<GossipPubSub>(keypair, config)  L1898/1904
                    ← OPTIONAL: set the two new bound fields explicitly here
                    → consumed by AccountMessenger (account/AccountMessenger.cpp:46+),
                      GlobalDB PubSubBroadcasterExt (crdt/globaldb/globaldb.cpp:354)
                    → GeniusSDK links the SuperGenius static lib: no direct Config
                      surface, inherits whatever GeniusNode sets — safe defaults in
                      gossip.hpp mean SDK builds are correct with ZERO SDK changes.
```

Because both impl classes already hold `const Config &`, **no constructor signatures change anywhere** — the plumbing is additive struct fields only. That keeps ABI/API blast radius at "recompile dependents," not "rewrite call sites."

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Small mesh (dev/test, <100 peers) | Defaults suffice; bounds never trip; behavior identical to today |
| GNUS production edge nodes | Explicit values in `GeniusNode.cpp` (e.g. topics ≈ 2× expected local topic count; pending bytes ≈ a few × `max_message_size` (16 MiB default) to absorb oneControl burst) |
| Hostile public network | The bounds ARE the fix: topic-table cap stops subscription-flood memory growth; pending-bytes cap + stream close stops slowloris-style write buffering. Peer-level behavior scoring (meshsub 1.1) remains future work |

### Scaling Priorities

1. **First bottleneck (this milestone):** unbounded `table_` and `pending_buffers_` per peer — fixed by BOUND-1/BOUND-2.
2. **Next bottleneck (deferred):** no behavior-based peer scoring; the `DenyListConnectionGater` manual block/unblock is the only peer-control surface — out of scope.

## Anti-Patterns

### Anti-Pattern 1: Patching submodules in-place under `thirdparty/`
**What people do:** edit `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` directly.
**Why it's wrong:** `thirdparty` is a pin repository of nested submodules; local edits are invisible to the upstream repos, unmergeable, and silently lost on the next pin update.
**Do this instead:** fix + test in the submodule repo (develop for bitswap, master for libp2p), push, then update the pin in the `thirdparty` repo, then the GeniusNetwork superproject's thirdparty ref.

### Anti-Pattern 2: Treating every timer handler firing as a timeout
**What people do:** ignore the `error_code` in `async_wait` handlers (the exact bug being fixed).
**Why it's wrong:** Asio delivers canceled handlers with `operation_aborted`; reacting to it double-reports and clears live request state.
**Do this instead:** Pattern 1 — `if (ec) return;`.

### Anti-Pattern 3: Invoking application callbacks under an internal mutex
**What people do:** call consumer code while holding the container guard (`HandleResponse` today).
**Why it's wrong:** any re-entrant call chain (this library's own UnixFS fetch chaining) deadlocks; callbacks also run with lock-ordering constraints they cannot know.
**Do this instead:** Pattern 2 — move callbacks out under the lock, invoke after release.

### Anti-Pattern 4: Hard-coding bound values in the impl
**What people do:** bake `if (pending_bytes_ > 1<<20)` into `stream.cpp`.
**Why it's wrong:** SuperGenius and GeniusSDK deployments differ; no tuning path without another repin.
**Do this instead:** thread Config fields (additive defaults) through the existing `Config` value struct — the ctor plumbing already exists.

## Integration Points

### External Repositories / Pin Chain

| Boundary | Integration Pattern | Notes |
|----------|---------------------|-------|
| GeniusVentures/ipfs-bitswap-cpp (develop) → thirdparty | fix commits → push → submodule pin update | Current pin `d2ec18af` = develop; two fixes can be separate commits, one pin bump |
| GeniusVentures/libp2p (master) → thirdparty | gossip bound commits → push → submodule pin update | Current pin `10166f9c` (~4 behind master); Config struct grows ⇒ **all dependents must rebuild** (ipfs-pubsub, ipfs-lite-cpp, SuperGenius) |
| thirdparty → GeniusNetwork superproject | thirdparty repo commit → superproject ref update | One combined thirdparty commit covering both submodule bumps minimizes rebuild cycles; keep per-repo commits clean for revertability |
| SuperGenius → GeniusSDK | static lib rebuild → SDK Release x64 rebuild + link check | SDK has no gossip/bitswap source surface (verified: no GossipPubSub/Bitswap references in GeniusSDK tree); verification = build only |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Bitswap → consumer callback | synchronous callback on the io_context thread (post-fix: outside `mutex_`) | Consumers (`FetchContent`/UnixFS chaining, ipfs-lite block service) already assume re-entrancy is possible — that's why fix 2 exists |
| GossipSub → Feedback (Stream errors) | async post via scheduler (`asyncPostError`) | BOUND-2 rides this existing channel; no new teardown path invented |
| ipfs-pubsub GossipPubSub → libp2p gossip | `gossip::create(..., config_)` value-passed Config | Additive fields only; no signature change |
| GeniusNode → GossipPubSub | inline Config literal (GeniusNode.cpp:1872-1878) | Single place to set production bound values |

## Suggested Build Order (dependency-respecting)

1. **ipfs-bitswap-cpp** — fix 1 (timer cancel) + fix 2 (callback outside lock) + both regression tests in one PR/branch; run submodule GTest suite standalone.
2. **libp2p** — gossip bounds: Config fields → `RemoteSubscriptions` cap → `Stream` pending-bytes cap + tests; run libp2p gossip tests standalone. (Independent of step 1 — can proceed in parallel; both must land before step 3.)
3. **thirdparty repin** — bump `ipfs-bitswap-cpp` and `libp2p` submodule pins (single thirdparty commit acceptable), then update the GeniusNetwork superproject's thirdparty ref.
4. **SuperGenius verification** — full rebuild; focus suites: CRDT/GlobalDB + PubSubBroadcasterExt tests (gossip bounds), storage/DAG-syncer tests (bitswap), AccountMessenger tests (both). Optionally add explicit bound values in `GeniusNode.cpp:1872-1878`.
5. **GeniusSDK verification** — Release x64 configure + build + link against the rebuilt SuperGenius static lib. No source changes expected.

**Blast radius summary:** Config struct growth in libp2p is the widest-reaching change (forces recompilation of every dependent). The bitswap fixes are self-contained (no header/signature changes; `bitswap.hpp` untouched unless the test needs a friend declaration — prefer keeping `BitswapRequestContext` fully public, as it already is in `src/bitswap.cpp`'s anonymous reach). No API consumed by SuperGenius or GeniusSDK changes signature; behavioral changes are strictly "no false timeout after cancel" and "no deadlock on chained callbacks."

## Sources

- `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` L65-99 (timer arm/cancel, HandleResponse under lock), L268-305 (dispatch), L345-355 (retry re-AddCallback), L377-415 (chained UnixFS callbacks) — **direct read, pinned d2ec18af**
- `thirdparty/ipfs-bitswap-cpp/test/bitswap_server_client_test.cpp` L38-216 (io_context injection/harness pattern for the new unit test) — **direct read**
- `thirdparty/libp2p/src/protocol/gossip/impl/remote_subscriptions.hpp` L75-77 (unbounded-table TODO), `.cpp` L26-147 (growth + heartbeat sweep) — **direct read, pinned 10166f9c**
- `thirdparty/libp2p/src/protocol/gossip/impl/stream.hpp` L64-70 (pending-bytes TODO), `stream.cpp` L49-252 (read/write lifecycle, timeout handle, `asyncPostError`) — **direct read**
- `thirdparty/libp2p/src/protocol/gossip/impl/message_parser.cpp` L70-130 (dispatch surface; prune/signed-peer-record TODO) — **direct read (partial range)**
- `thirdparty/libp2p/include/libp2p/protocol/gossip/gossip.hpp` L60-130 (Config fields + defaults) — **direct read**
- `thirdparty/ipfs-pubsub/src/ipfs_pubsub/gossip_pubsub.{hpp,cpp}` (Config ctors L95-114, `GetDefaultConfig` L304-311, `gossip::create` L301-307) — **direct read via symbol search**
- `SuperGenius/src/account/GeniusNode.cpp` L1860-1910 (production Config construction + GossipPubSub construction) — **direct read**
- `SuperGenius/src/account/AccountMessenger.{cpp,hpp}`, `SuperGenius/src/crdt/globaldb/globaldb.cpp` L354 (consumer surface) — **direct symbol search**
- `.planning/research/gnus_libp2p_comparison.md` (prior audit: P0 rows "Audit/fix Bitswap cancellation and callbacks under locks", "Bound GossipSub queues, subscriptions, per-peer memory") — **prior project research**

---
*Architecture research for: ipfs-improve (IPFS P0 remediation) workstream*
*Researched: 2026-10-12*
