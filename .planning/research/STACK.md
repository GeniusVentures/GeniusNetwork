# Stack Research

**Domain:** P0 correctness/resource-bound remediation in the GNUS C++ libp2p/IPFS fork (ipfs-improve workstream, milestone v1.0)
**Researched:** 2026-10-12
**Confidence:** HIGH for local-code facts (every integration point below was opened and read in this session); MEDIUM for Go-parameter precedents (read directly from canonical `libp2p/go-libp2p-pubsub` master sources via raw.githubusercontent — primary sources, but the research-store seam mechanically tags `curl`-fetched content LOW, so tiers below reflect that grading while flagging primary-source verification)

**Headline:** This milestone adds **zero new dependencies**. Every fix is in-tree, on Boost.Asio 1.85 idioms already present in the same file, using GTest suites already wired in both submodules. The only "additions" are `Config` fields, two limits in `Stream`, a table-bound in `RemoteSubscriptions`, and regression tests.

---

## Recommended Stack

### Core Technologies (all already integrated — no changes)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Boost.Asio (`deadline_timer`) | **1.85** (verified: `thirdparty/build/Windows/Debug/boost/build/include/boost-1_85/`) | Bitswap response/retry/content timers | Already in use in `bitswap.cpp` at 5 call sites; the fix is adopting the *correct* idiom, not swapping timers |
| `boost::system::error_code` / `operation_aborted` | 1.85 | Distinguish timer cancellation from expiry | The exact mechanism the P0-1 fix needs; already used correctly at `bitswap.cpp:507` and `:577` |
| Google Test (GTest) | via libp2p's Hunter/CMake (both submodules already build tests) | Regression tests for all three fixes | Suites already exist: `thirdparty/ipfs-bitswap-cpp/test/` (`bitswap_content_test.cpp`, `bitswap_persistence_test.cpp`, `bitswap_server_client_test.cpp`) and `thirdparty/libp2p/test/libp2p/protocol/gossip/` (`gossip_structures_test.cpp`, `gossip_local_subs_test.cpp`) |
| Boost.Asio `io_context` + `std::mutex` (existing pattern) | 1.85 / C++17 | Callback dispatch outside critical section | The codebase already uses the correct erase-under-lock/invoke-outside pattern at `bitswap.cpp:583–604` (`setupContentRequest` timeout handler) — reuse that exact pattern for `HandleResponse` |

### Fix Design (the actual "stack additions")

#### Fix 1 — Bitswap timer cancellation (`bitswap.cpp:63–98`)

**What's wrong (verified in source):** `BitswapRequestContext::AddCallback` (L63–85) arms `responseTimer_.async_wait` whose handler (L78–82) ignores its `const boost::system::error_code &` parameter and unconditionally calls `HandleResponseTimeout()`. `HandleResponse` (L86–92) disarms the timer with `expires_at(boost::posix_time::pos_infin)` — but per Boost.Asio semantics, resetting the expiry on a timer with a pending `async_wait` **cancels the pending handler, which is then invoked with `operation_aborted`**. Because the handler ignores `ec`, a *successful* response disarm is processed as a *timeout* → spurious `BitswapError::OUTBOUND_STREAM_FAILURE` delivered to consumers.

**Correct 1.85-era idiom (already proven in this same file):**

```cpp
responseTimer_.async_wait(
    [self = shared_from_this()]( const boost::system::error_code &ec ) {
        if ( ec ) { return; }  // operation_aborted => disarmed/canceled: success path, not a timeout
        self->HandleResponseTimeout();
    } );
```

- Cancel/disarm explicitly with `responseTimer_.cancel()` in `HandleResponse` before/at the `expires_at(pos_infin)` disarm; treat any `ec != false` as "not a timeout".
- Keep the `shared_from_this()` capture (L75–78 comment documents a real fixed dangling bug — preserve it).
- **Regression test:** in `thirdparty/ipfs-bitswap-cpp/test/` (new `bitswap_timer_test.cpp` or extend an existing suite): arm context → call `HandleResponse(success)` (which disarms) → run `io_context.run()` to completion → assert callbacks received **exactly one success result and zero error results**. Also mirror-test: no response → `run()` → assert exactly one `OUTBOUND_STREAM_FAILURE`/timeout error. Note sibling sites already correct: L504–514 (`ec`-gated retry backoff) and L574–606 (content timeout, `if (ec) return;`) — the fix makes L78–82 consistent with them.

#### Fix 2 — `HandleResponse()` callbacks outside `mutex_` (`bitswap.cpp:86–92`)

**What's wrong (verified):** the loop invoking `callback(block)` runs inside `std::lock_guard guard(mutex_)`. Any consumer that re-enters Bitswap (e.g., looks up the same CID in `requestContexts_`, calls `AddCallback`, or destroys the request) deadlocks or races.

**Fix — copy-and-invoke pattern already established in-file at L583–604:**

```cpp
void BitswapRequestContext::HandleResponse( libp2p::outcome::result<std::string> block )
{
    std::vector<BlockCallback> to_invoke;
    {
        std::lock_guard<std::mutex> guard( mutex_ );
        responseTimer_.cancel();  // explicit cancel; handler's ec-check makes this safe
        to_invoke = std::move( callbacks_ );
        callbacks_.clear();
    }
    for ( auto &callback : to_invoke ) { callback( block ); }  // outside critical section
}
```

- **Reentrancy test:** a callback that (a) calls `AddCallback` again, (b) synchronously queries the same CID — must complete without deadlock. GTest timed `io_context.run_for(seconds(2))` + `ASSERT_TRUE(finished)` catches the old behavior deterministically; run once under TSan for the race proof.

#### Fix 3 — GossipSub bounds (three integration points, one Config change)

**Verified local state:** `stream.hpp:64–70` TODO — `pending_buffers_` (deque) and `pending_bytes_` are unbounded; `stream.cpp:144–210` pushes every serialized message and only pops front after the write completes, so one slow peer pins unbounded memory on the publisher. `remote_subscriptions.hpp:75–77` TODO — `table_` (`unordered_map<TopicId, TopicSubscriptions>`) grows with every remote-subscribed topic, never shrinks for topics we don't care about. `gossip.hpp` `Config` (L23–90) has `max_message_size = 1<<24` (16 MiB) but **no** per-peer queue bound, no RPC subscription-count cap, no IHave/IWant caps.

**Go libp2p precedents (read directly from canonical master sources):**

| Go parameter (file) | Value | Meaning | C++ translation |
|---|---|---|---|
| `peerOutboundQueueSize` (`pubsub.go`, opt `WithPeerOutboundQueueSize`) | **32** RPCs | Per-peer outbound queue; **messages are dropped when full** ("We start dropping messages to a peer if the outbound queue is full") — drop-not-block | `Stream::pending_buffers_` cap: new `Config::max_pending_bytes_per_peer` (default ~2 MiB) or count cap; on overflow **drop + close/reset the slow stream** per the existing TODO's own suggestion |
| `DefaultMaxMessageSize` (`pubsub.go`) | **1 MiB** (1<<20) | Global wire-message cap | Fork currently uses 16 MiB — keep (changing it is a wire-behavior change out of scope) but note the 16× delta in docs |
| `DefaultMaxControlMessageSize` (`pubsub.go`) | **512 KiB** | Control-message cap (IHave/IWant/Graft/Prune) | Add `Config::max_control_message_size`; enforce in `message_parser.cpp` before iterating `control()` entries |
| `GossipSubMaxIHaveMessages` / `GossipSubMaxIHaveLength` (`gossipsub.go`) | **10** / **5000** | Max IHaves per RPC / total message-ids advertised | Cap `messageids` processing per control message in `message_parser.cpp:60–66`; bound the response side similarly |
| `D`/`Dlo`/`Dhi`/`Dscore`/`Dout` = 6/5/12/4/2; `HistoryLength`=5, `HistoryGossip`=3 (`gossipsub.go`) | — | Mesh density | Existing `Config` already has `D_min`/`D_max` — no change needed; listed to anchor review |
| ~~`GossipSubMaxSubscriptions`~~ | **does not exist** in master `gossipsub.go` | **Correction to the research brief:** verified absent; subscription bounding in Go is achieved via the RPC size caps + `dropIfOversized`, not a named subscription-count constant | Bound `RemoteSubscriptions::table_` by pruning topics with no local subscription on heartbeat (`onHeartbeat()` already exists) or LRU as the TODO suggests; plus cap subscriptions-per-peer processed per RPC in `message_parser.cpp` |

**Concrete C++ changes:**

1. `include/libp2p/protocol/gossip/gossip.hpp` — add to `Config` (next to `max_message_size`, ~L87–90): `size_t max_pending_bytes_per_peer = 2 << 20; size_t max_pending_messages_per_peer = 32; size_t max_control_message_size = 512 << 10; size_t max_ihave_messages = 10; size_t max_ihave_length = 5000; size_t max_subscriptions_per_peer = 100;` (defaults anchored to Go).
2. `src/protocol/gossip/impl/stream.hpp/.cpp` — resolve TODO at L64–70: in `write()` (cpp L144–147), if `pending_bytes_ + buffer->size() > config.max_pending_bytes_per_peer` or `pending_buffers_.size() >= max_pending_messages_per_peer` → drop message (log + metrics) and, if persistent across N writes, `close()` the stream via existing `feedback_` error path (`asyncPostError`) so `Connectivity` reaps the peer.
3. `src/protocol/gossip/impl/remote_subscriptions.hpp/.cpp` — resolve TODO at L75–77: in `onHeartbeat()`, erase `table_` entries where the topic has no local subscription and zero remote subscribers; that alone bounds growth from topic-churn spam. Optionally cap per-peer subscription count in `onPeerSubscribed`.
4. `src/protocol/gossip/impl/message_parser.cpp` — enforce `max_ihave_messages`/`max_ihave_length`/`max_subscriptions_per_peer` while iterating `control()` (~L60–66) and `subscriptions()` — drop excess entries with a debug log (mirrors Go `dropIfOversized`/`DropRPC`).
5. **Regression tests** in `thirdparty/libp2p/test/libp2p/protocol/gossip/`: (a) `gossip_structures_test.cpp`-style unit — feed a `Stream` a write workload with a stalled underlying stream, assert `pending_buffers_` never exceeds the cap and stream gets closed; (b) parser test — craft RPC with 10,000 subscriptions / oversized IHave lists, assert bounded processing; (c) `RemoteSubscriptions` heartbeat-prune test.

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Boost.Asio `deadline_timer` | 1.85 (in-tree) | All P0-1 timer work | Now — no alternative needed |
| GTest | already wired via `add_subdirectory(test)` in both submodules | All regression tests | Now — add new `.cpp` suites to the existing `test/CMakeLists.txt` targets |
| spdlog/soralog (already integrated) | as pinned | Log dropped messages / slow-peer closes at warn | Fix 3 observability (Go's `DropRPC` tracer equivalent) |
| libp2p `basic::Scheduler` (already used by gossip) | in-tree | Any time-based pruning/decay in `RemoteSubscriptions` if LRU is chosen over heartbeat-prune | Only if heartbeat pruning proves insufficient |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Existing per-submodule GTest targets (`test/` CMake in both `ipfs-bitswap-cpp` and `libp2p`) | Build & run regression tests standalone | Faster than full GeniusNetwork build: configure `ipfs-bitswap-cpp` alone (its `CMakeLists.txt` already `find_package(libp2p CONFIG REQUIRED)` against the thirdparty build) |
| ThreadSanitizer build of the bitswap tests | Prove Fix 2 reentrancy/deadlock resolution | One-off local build; CI restoration is out of scope |
| `git log`/blame on integrated commits (`d2ec18af` bitswap, `10166f9c` libp2p) | Anchor fixes against pinned submodule state | Prior audit warns branch-tip findings must be rechecked against pinned commits — done here: files read from the pinned working tree |

## Installation

```bash
# Nothing to install. Zero new dependencies.
# Boost 1.85, GTest, libp2p, spdlog all already integrated via thirdparty/ build.
# Regression tests are added to existing test targets:
#   thirdparty/ipfs-bitswap-cpp/test/CMakeLists.txt   (timer + reentrancy suites)
#   thirdparty/libp2p/test/libp2p/protocol/gossip/     (bounds suites)
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Explicit `cancel()` + `if (ec) return;` on `deadline_timer` | Switch to `boost::asio::steady_timer` | Only if the codebase later removes `posix_time` (deadline_timer is fine at 1.85; swapping types churns the diff with zero correctness gain) |
| Copy-callbacks-then-invoke-outside-lock (matches L583–604 pattern) | Post callbacks to `io_context.post()`/`scheduler` | If a strictly-single-thread dispatch order is required; posting changes ordering semantics — keep synchronous-outside-lock to match the established in-file pattern |
| Drop-on-full per-peer queue + close chronic offenders (Go precedent) | Block/backpressure publisher | Never here: blocking the gossip publisher on one slow peer stalls everyone — Go explicitly chose drop (`WithPeerOutboundQueueSize` doc comment) |
| Heartbeat-prune `table_` of empty/non-local topics | Full LRU keyed by last-use (TODO's suggestion) | LRU only if heartbeat pruning leaves a proven residual (topic churn where peers stay subscribed to garbage) — start simple |
| In-tree `Config` knobs on the existing struct | New resource-manager framework (Go `rcmgr`-style) | Out of scope for P0; a fork-wide resource manager is a milestone of its own — these knobs are its future building blocks |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| New heavyweight deps (new Boost modules beyond in-tree, actor frameworks, async runtime rewrites) | Submodule pin discipline (`d2ec18af`, `10166f9c`, `0b6f1a59`); every new dep multiplies cross-platform build risk already seen in `21_Build thirdparty.txt` | In-tree edits + existing Boost 1.85 |
| `expires_at(pos_infin)` as the *only* disarm + handler ignoring `ec` | Root cause of P0-1: disarm-cancel produces `operation_aborted` that reads as timeout | Explicit `cancel()` + `ec` check (Fix 1) |
| Invoking user callbacks while holding `mutex_` (any new code) | P0-2 root cause; latent deadlock | Copy-then-invoke outside lock; make it a review invariant for this milestone |
| Unbounded `std::deque` per peer ("we'll monitor it") | Slow-peer memory exhaustion is exactly the P0-3 threat model | Config-bounded queue with drop+close (Go `peerOutboundQueueSize=32` precedent) |
| Copying Go's 1 MiB `DefaultMaxMessageSize` down from the fork's 16 MiB | Silently changes accepted wire traffic — out of scope and a liveness risk for existing GNUS nets | Keep 16 MiB; add *new* independent control/subs/queue caps |
| Citing `GossipSubMaxSubscriptions` in code comments/docs | **Does not exist** in go-libp2p-pubsub master (verified); propagates a false precedent | Reference `DefaultMaxControlMessageSize`, `GossipSubMaxIHave*`, `WithPeerOutboundQueueSize` — all verified above |

## Stack Patterns by Variant

**If the timer is disarmed on success (Fix 1):** call `cancel()` and let the handler's `if (ec) return;` no-op it — with a pending `async_wait`, any expiry reset/cancel surfaces the handler with `operation_aborted`, and only `ec == false` means genuine expiry.

**If callbacks must not run under lock (Fix 2):** move the callback list out under the lock, invoke after the guard's scope ends — do not `post()` unless ordering semantics demand it.

**If an untrusted peer can inflate per-peer state (Fix 3):** bound it with a `Config` default anchored to Go's published value, drop the excess, log at warn, and escalate to stream-close/peer-reap on persistence — never block the local publisher.

**If a bound is enforced on receive:** enforce it in `message_parser.cpp` *before* the data enters `RemoteSubscriptions`/mesh state (defense at the parse boundary), and again at the table itself (defense against slow-drain).

## Version Compatibility

| Component | Compatible With | Notes |
|-----------|----------------|-------|
| Boost.Asio timer semantics (cancel → `operation_aborted`) | Boost 1.85 in-tree; stable for many releases | No version risk |
| New `Config` fields (gossip.hpp) | All GNUS `Config` consumers | Additive with defaults — old call sites (`Config{}`) compile unchanged; ipfs-pubsub (`b9f051f8`) constructs `Config` and inherits defaults — audit its expectations during implementation |
| `Stream` write-path changes | `Connectivity`/peer feedback plumbing (`feedback_` error path) | Reuse existing `asyncPostError`/close flow so peer reap behaves like today's stream failures |
| Bitswap changes (Fixes 1–2) | `ipfs-lite-cpp 0b6f1a59` consumers of `BitswapRequestContext` | Public behavior unchanged except fewer spurious failures; no API change |

## Sources

- Local source (verified this session, HIGH): `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` L63–98 (bug sites), L504–514/L573–606 (correct in-file idioms to mirror), L933 (`ctx->timeout.cancel()` success-path cancel — precedent for Fix 1's explicit cancel)
- Local source (verified this session, HIGH): `thirdparty/libp2p/src/protocol/gossip/impl/stream.hpp` L64–70 + `stream.cpp` L144–210; `remote_subscriptions.hpp` L75–77; `include/libp2p/protocol/gossip/gossip.hpp` Config L23–90; `message_parser.cpp` L60–98
- Local build (verified): Boost 1.85 include path; GTest suites in both submodules; `ipfs-bitswap-cpp/CMakeLists.txt` dependency set
- `libp2p/go-libp2p-pubsub` master `gossipsub.go` — `GossipSubD/Dlo/Dhi/Dscore/Dout`, `HistoryLength/Gossip`, `GossipSubMaxIHaveLength=5000`, `GossipSubMaxIHaveMessages=10`; **`GossipSubMaxSubscriptions` absent** (seam tag LOW; direct primary-source read)
- `libp2p/go-libp2p-pubsub` master `pubsub.go` — `peerOutboundQueueSize=32`, `WithPeerOutboundQueueSize`, drop-on-full policy, `DefaultMaxMessageSize=1<<20`, `DefaultMaxControlMessageSize=512<<10`, `dropIfOversized`/`DropRPC` (seam tag LOW; direct primary-source read)
- Prior audit (context only, not re-researched): `.planning/research/gnus_libp2p_comparison.md`
- Prior milestone STACK archived at: `.planning/research/STACK-childwallet-2026-07-13.md`

---
*Stack research for: IPFS P0 remediation (ipfs-improve v1.0)*
*Researched: 2026-10-12*
