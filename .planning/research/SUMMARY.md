# Project Research Summary

**Project:** IPFS P0 Remediation (ipfs-improve workstream, milestone v1.0)
**Domain:** C++ libp2p/IPFS correctness & resource-bounding remediation (Boost.Asio, std::mutex, GossipSub v1.0 / Bitswap 1.0)
**Researched:** 2026-10-12
**Confidence:** HIGH

## Executive Summary

This is a surgical remediation milestone on the GNUS C++ libp2p/IPFS fork, closing the two non-CI P0 findings from the `gnus_libp2p_comparison.md` audit: (1) Bitswap treats canceled timers as timeouts (`async_wait` handler ignores its `error_code`, so a success-path disarm via `expires_at(pos_infin)` — which per Boost.Asio semantics *is* a cancellation delivering `operation_aborted` — manufactures a false `OUTBOUND_STREAM_FAILURE` and clears live callbacks, dropping the block that arrives later), and invokes consumer callbacks while holding `mutex_` (a deadlock the library's own UnixFS chaining can trigger); (2) GossipSub grows unbounded remote-driven state — `RemoteSubscriptions::table_` (topic-churn spam) and `Stream::pending_buffers_`/`pending_bytes_` (one slow peer pins unbounded publisher memory). The recommended approach, unanimous across all four researchers: **port the patterns already fixed in-file** (`ContentRequestContext`'s C-5/C-7 fixes at `bitswap.cpp:~565-621`: `if (ec) return;`, `timedOut` flag under lock, move-callbacks-out-then-invoke) to `BitswapRequestContext` (`bitswap.cpp:60-99`), and bound the GossipSub containers with additive `gossip.hpp Config` fields anchored to verified Go precedents (`peerOutboundQueueSize=32` drop-on-full, `DefaultMaxControlMessageSize=512KiB`, `GossipSubMaxIHave*=10/5000`). Zero new dependencies; every change is in-tree on Boost 1.85 idioms and existing GTest suites.

Two research corrections materially change implementation. First, the **workspace pins differ from the audit doc** — verified via `git submodule status`: libp2p @ `28f6a629` (audit said `10166f9c`), ipfs-pubsub @ `b6eb6268` (audit said `b9f9051f8`), ipfs-bitswap-cpp @ `d2ec18af` (matches). Fixes must branch from the *actual* SHAs, and every repin must be content-probed (grep the fix marker), never trusted by branch name — a fix cherry-picked onto a stale pin silently doesn't build. Second, **`GossipSubMaxSubscriptions` does not exist in Go master** (the brief was wrong): Go bounds subscriptions via RPC size caps + `dropIfOversized`, and bounds outbound queues at 32 RPCs with drop-on-full and **no disconnect**. Therefore: bound `RemoteSubscriptions` by capping distinct topics per peer + pruning empty/non-local entries in the existing `onHeartbeat` sweep (never evicting live mesh state — that breaks Graft/Prune/IHAVE), and bound `Stream` by **bytes at `write()` entry** with drop-new + close only on sustained overflow (Go's 32 counts RPCs, not messages — copying it as a message count would throttle far below Go throughput, and a bound below CRDT-sync burst size causes consensus divergence).

Key risks, all with concrete mitigations from research: reintroducing the bug subtly (use explicit `.cancel()`, not `expires_at(pos_infin)`; keep all timer ops under `mutex_` — `deadline_timer` is not thread-safe; add a completion flag set atomically with callback clearing, since error-code checking alone loses the already-queued-genuine-expiry race); creating new races in the refactor (late `AddCallback` after completion must fail fast, not arm a 5s orphan timer; state transition under lock with exactly one winner, then dispatch outside); and racy tests that pass vacuously (single-threaded `io_context`, posted cancels, no `sleep_for`, injectable timeouts — the hardcoded `seconds(5)`/`seconds(30)` need test seams; gossip tests use the already-mockable `basic::Scheduler`). Tests are first-class P0 acceptance evidence (TS-10): the four race orderings (cancel-vs-expiry both orders, response-then-canceled-timer, timeout-then-late-response, reentrant callback cancels own request) are the observable definition of "closed."

## Key Findings

### Recommended Stack

Zero new dependencies. Boost.Asio 1.85 `deadline_timer` + `boost::system::error_code`/`operation_aborted` (already in-tree, already used correctly at `bitswap.cpp:507`/`:577`), GTest (both submodules already wire test targets), spdlog/soralog for drop observability, and libp2p's `basic::Scheduler` (mockable — use it for deterministic gossip tests instead of real timers). The only additions are `Config` fields, two limits in `Stream`, a table bound in `RemoteSubscriptions`, and regression tests.

**Core technologies:**
- **Boost.Asio `deadline_timer` (1.85)**: Bitswap response/retry/content timers — adopt the *correct* idiom (`if (ec) return;`) already proven in the same file; do not swap timer types (churns the diff for zero correctness gain)
- **`boost::system::error_code` / `operation_aborted`**: distinguish cancel from expiry — the exact mechanism Fix 1 needs
- **Google Test**: regression tests for all three fixes — suites already exist in `thirdparty/ipfs-bitswap-cpp/test/` and `thirdparty/libp2p/test/libp2p/protocol/gossip/`; build submodules standalone (much faster than the full GeniusNetwork build)
- **ThreadSanitizer (one-off local)**: prove the reentrancy/race fixes; expect it to also flag pre-existing races (`timedOut`, `closed_`) — triage, don't silence

**Critical version/pin facts:** Boost 1.85 (verified include path); workspace submodule pins `ipfs-bitswap-cpp@d2ec18af`, `libp2p@28f6a629`, `ipfs-pubsub@b6eb6268` (audit doc's libp2p/pubsub pins are stale); Go parameter precedents read from canonical master sources.

### Expected Features

"Features" = observable behaviors of the fixes (consumers are GNUS SDK/node developers). Scope guard: Bitswap 1.0 only — OUT: CI, Bitswap 1.1/1.2, CIDv1, Want-Have/Dont-Have, QUIC, Go interop, benchmarks.

**Must have (table stakes — v1.0 P0 closure):**
- TS-1 — canceled timer never fires failure path (`ec` check in `BitswapRequestContext` handler)
- TS-2 — exactly-once result per request (completion flag under mutex; error-code check alone is insufficient)
- TS-3 — cancel means silence: success/cancel produce no error callback; genuine timeout produces exactly one
- TS-4 — callbacks dispatched outside all internal mutexes (copy-out-under-lock, invoke after unlock)
- TS-5 — callback may synchronously re-enter Bitswap (cancel own request, chain fetches) — the acceptance test for TS-4
- TS-6 — per-peer subscription cap + `Config` knob; excess subscribes ignored; never evict live mesh state
- TS-7 — bounded outbound queue, **byte-based primary** (count secondary), drop-on-full default, no disconnect-on-first-overflow
- TS-8 — escalation via existing `DenyListConnectionGater::BlockPeer()` / stream-close for sustained overflow — wiring only
- TS-9 — every bound hit logged (rate-limited) + counted; no silent drops
- TS-10 — regression tests for all four race orderings + bounds tests — the P0 acceptance evidence

**Should have (post-validation, v1.x):** D-3 urgent control-message lane (Go `UrgentPush` parity, keeps mesh maintenance alive under load); D-4 idle stream recycling; D-2 TTL/decay graylist on BlockPeer entries.

**Defer (v2+):** D-1 full peer-scoring port (GossipSub v1.1 scope — its own milestone; conflicts with TS-8 if built together); D-5 local-consumer backpressure (changes public API semantics).

**Anti-features (reject at requirements time):** AF-1 peer-score port now; AF-2 disconnect-on-any-queue-full (self-inflicted mesh damage — Go never disconnects for queue-full); AF-3 "raise limits" without policy; AF-4 Bitswap 1.1/1.2 scope creep; AF-5 bundling CI/interop/benchmarks; AF-6 silent drops. Also: do **not** copy Go's 1 MiB `DefaultMaxMessageSize` over the fork's 16 MiB (wire-behavior change, out of scope); do **not** cite `GossipSubMaxSubscriptions` in code/docs (doesn't exist).

### Architecture Approach

All changes live in the two protocol submodules; the wrapper layer needs plumbing only; consumers need rebuild-verification only. Fixes land in the submodule repos (ipfs-bitswap-cpp `develop`, libp2p `master`), push, then bump the `thirdparty` pins, then the GeniusNetwork superproject ref — never patch in-place under `thirdparty/` (local edits are invisible upstream and lost on repin). The GossipSub fix is purely additive `Config` struct fields threaded through a chain that already exists: `gossip.hpp Config` → `Stream`/`RemoteSubscriptions` ctors (both already take `const Config&` — no signature changes) → `ipfs_pubsub::GossipPubSub` (`GetDefaultConfig()` inherits defaults automatically) → `GeniusNode.cpp:1872-1878` (optional explicit values) → GeniusSDK (static lib link, zero source change).

**Major components / touch points:**
1. `BitswapRequestContext` (`ipfs-bitswap-cpp/src/bitswap.cpp:60-99`) — **modified**: timer-ec guard + completion flag + callback-outside-lock
2. `libp2p::protocol::gossip::Config` (`gossip.hpp`) — **modified**: additive bound fields appended at struct end with safe defaults (mid-struct insertion breaks aggregate-init sites across repos)
3. `RemoteSubscriptions` (`remote_subscriptions.{hpp,cpp}`) — **modified**: per-peer topic cap + heartbeat prune of empty/non-local entries
4. `Stream` (`stream.{hpp,cpp}`) — **modified**: byte bound at `write()` entry, drop-new, `asyncPostError(WRITER_TIMEOUT)` → existing Feedback teardown on sustained overflow
5. `MessageParser` — read-only for bounds (pure decoder; enforcement at receivers) — STACK proposes optional parser-side caps on IHave/subs lists; ARCHITECTURE notes parser stays untouched — resolve in Phase 3 planning
6. `ipfs_pubsub::GossipPubSub` / `GeniusNode` / GeniusSDK — plumbing, optional override, build-only

**Widest blast radius:** the `Config` struct growth forces recompilation of ipfs-pubsub, ipfs-lite-cpp, and SuperGenius; the bitswap fixes are self-contained (no header/signature changes). Behavioral changes are strictly "no false timeout after cancel" and "no deadlock on chained callbacks" — but callback timing/locking contract changes must be audited at SuperGenius/GeniusSDK consumption sites.

### Critical Pitfalls

1. **Reintroducing `operation_aborted`-as-timeout subtly** — handler must be `if (ec) return;`; disarm with explicit `.cancel()`, never `expires_at(pos_infin)`; add a completion flag because a genuinely-expired handler already dequeued fires with *success* and cannot be canceled.
2. **Timer thread-safety violations created by the refactor** — `deadline_timer` is not thread-safe; keep arm/cancel/wait all under `mutex_`; only the *user callback invocation* leaves the lock. Don't generalize "callback outside mutex" to "timer ops outside mutex."
3. **Late-`AddCallback` TOCTOU (lost wakeup)** — a callback registered after completion must fail fast (immediate error/queued-result delivery), never arm a fresh 5s timer on a completed request.
4. **GossipSub eviction breaking Graft/Prune/IHAVE correctness** — the table is protocol state, not a cache; only entries with zero local AND zero remote subscribers are evictable; prefer capping distinct topics **per peer** (bounds at the source) over table eviction; requires graft/prune regression tests + unique-topic flood test.
5. **Outbound bound with wrong policy/unit/value/site** — Go's 32 counts RPCs (this deque holds messages): bound **bytes** primarily, enforce at `Stream::write()` entry, drop-new not drop-oldest, defaults generous vs CRDT-sync bursts, close stream only on sustained (K-heartbeat) overflow, always log+count drops.
6. **Fixing on branch tips instead of pinned SHAs** — branch from `d2ec18af`/`28f6a629`/`b6eb6268`; at repin, verify by `git submodule status` + content-probe the fix marker; re-run the audit's source-review checks against final pins.
7. **Racy regression tests passing vacuously** — single-threaded `io_context`, posted cancels for determinism, no `sleep_for`, synchronization (condition_variable/future) not bare flags, injectable timeouts (the 5s/30s values are hardcoded today — expose them for tests), mock `basic::Scheduler` for gossip timing.

## Implications for Roadmap

Three implementation phases plus one integration phase, matching the dependency graph (bitswap fixes are independent of gossip bounds; both must precede repin/rebuild) and every researcher's phase mapping.

### Phase 1: Bitswap timer cancellation correctness
**Rationale:** Smallest, highest-certainty fix; the in-file precedent (`ContentRequestContext` C-5/C-7 pattern) makes it a port, not a design. Establishes the test harness (single-threaded io_context, injectable timeout) Phase 2 reuses.
**Delivers:** TS-1, TS-2, TS-3 + regression tests (cancel-then-no-error; genuine-timeout mirror test). Branch from `d2ec18af` in ipfs-bitswap-cpp.
**Addresses:** Audit P0-1a. **Avoids:** Pitfalls 1 (ec check + explicit `.cancel()` + completion flag), 2 (timer ops stay under mutex), 3 (keep `shared_from_this()` capture), 9 (deterministic test, injected timeout).
**Test seam prerequisite:** expose `responseTimeout_` for injection in this phase.

### Phase 2: Bitswap callback dispatch outside mutex
**Rationale:** Depends on Phase 1's completion-flag semantics; its reentrancy acceptance test (TS-5) also re-verifies Phase 1 under interaction. Same file, same branch, second commit.
**Delivers:** TS-4, TS-5, TS-10(a–d) race tests + documented post-completion contract for late `AddCallback`. One pin bump for Phases 1+2 together.
**Addresses:** Audit P0-1b. **Avoids:** Pitfalls 3 (lifetime), 4 (late-AddCallback fail-fast), 5 (lock order: never hold `mutexRequestCallbacks_` across context methods), 6 (state transition under lock, single winner), 2 (re-verify via TSan).

### Phase 3: GossipSub resource bounds
**Rationale:** Independent of Phases 1–2 (different submodule — can start in parallel after planning); needs its own research pass because two open design questions exist (see Research Flags). Config-first ordering: fields land before consumers so defaults are inherited everywhere.
**Delivers:** TS-6 (per-peer topic cap + heartbeat prune), TS-7 (byte-based outbound bound at `write()` entry, drop-new, sustained-overflow close), TS-8 (BlockPeer/stream-close escalation wiring), TS-9 (log+counter), + gossip test suites (flood test, graft/prune regression, slow-peer stream test via mock `basic::Scheduler`). Branch from `28f6a629` in libp2p.
**Addresses:** Audit P0-2. **Avoids:** Pitfalls 7 (evict only dead entries), 8 (policy/unit/value/site), 3 (new close paths respect `closed_`/lifetime), 5 (collect-then-erase in sweeps, no `table_mutex_` across feedback calls), 9 (scheduler mock).

### Phase 4: Repin, rebuild, and cross-repo verification
**Rationale:** Integration is where fixes silently vanish (Pitfall 10) and where the widest blast radius lands (Config struct growth forces recompiles).
**Delivers:** thirdparty pin bumps (single thirdparty commit acceptable covering both submodules; keep per-repo commits clean for revertability); `GeniusNode.cpp:1872-1878` explicit production bound values (optional); SuperGenius full rebuild + focus suites (CRDT/GlobalDB + PubSubBroadcasterExt for gossip; storage/DAG-syncer for bitswap; AccountMessenger for both); GeniusSDK Release x64 build + link (no source change expected); callback-timing contract release note.
**Avoids:** Pitfall 10 (content-probe fix markers at final pins; re-run audit checks); UX pitfall (silent behavior change — audit SDK consumers of callback timing).

### Phase Ordering Rationale

- **Bitswap before GossipSub:** timer fix → callback-outside-lock is sequential within bitswap (Phase 2's contract depends on Phase 1's flag); gossip is parallelizable but gets the later slot because its design has open questions needing research, while bitswap is a pattern port.
- **Tests are first-class, not a tail phase:** each fix is a race-condition fix — TS-10 orderings are the P0 acceptance evidence, and the harness built in Phase 1 is reused throughout.
- **Config fields before plumbing:** additive-with-defaults means `Config{}` call sites compile unchanged and `GetDefaultConfig()` picks bounds up automatically — landing fields first minimizes cross-repo coordination.
- **Repin/rebuild last, with probes:** one integration phase keeps rebuild cycles minimal and puts the content-probe discipline in one checklist.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 3:** Two researcher disagreements to resolve + design decisions: (a) parser-side caps (STACK/FEATURES propose `message_parser.cpp` enforcement of IHave/subs limits; ARCHITECTURE says parser stays untouched, enforcement at receivers); (b) exact Config surface — `max_remote_subscription_topics` + `max_pending_bytes_per_stream` (ARCHITECTURE) vs. the fuller Go-anchored set incl. `max_control_message_size`, `max_ihave_*`, `max_pending_messages_per_peer` (STACK); (c) eviction vs. per-peer-cap emphasis; (d) sustained-overflow threshold (K heartbeats). Recommend `--research-phase 3`.
- **Phase 4:** Repin mechanics for this repo pair (probe checklist, revert strategy, rebuild matrix) — light research or reuse from prior thirdparty work.

Phases with standard patterns (skip research-phase):
- **Phase 1, Phase 2:** the target patterns exist in-file at `bitswap.cpp:565-621` and the test harness pattern at `bitswap_server_client_test.cpp:38-216`; planning needs only the port checklist and the "Looks Done But Isn't" list from PITFALLS.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Every local integration point opened and read at pinned SHAs; Boost 1.85 verified in-tree; zero-dep claim verified. Go parameters read from canonical master sources (primary, but the research-store seam mechanically tags curl-fetched content LOW — flagged, not downgraded here) |
| Features | HIGH | Behavior contracts verified against primary sources: Boost.Asio official reference, go-libp2p-pubsub master, boxo main, plus direct fork inspection. `GossipSubMaxSubscriptions` absence verified |
| Architecture | HIGH | All change points read directly from the pinned working tree; Config plumbing chain traced end-to-end including `GeniusNode.cpp:1872-1878` and GeniusSDK build-only surface |
| Pitfalls | HIGH | Code-grounded pitfalls read from pinned integrated sources; Boost cancel semantics verified against vendor docs; one researcher (ARCHITECTURE) cites stale audit pins (`10166f9c`) — superseded by PITFALLS' `git submodule status` verification |

**Overall confidence:** HIGH

### Gaps to Address

- **Phase 3 Config surface & parser role:** researcher disagreement (STACK's fuller Go-anchored field set + parser-side caps vs. ARCHITECTURE's two-field minimal set + receiver-side enforcement). Resolve during Phase 3 planning; either is safe, but pick one to avoid two patterns.
- **Exact bound defaults:** byte cap order-of-magnitude agreed (1–4 MiB/peer, above CRDT burst) but the concrete default and the sustained-overflow threshold (K) are unsettled — decide in Phase 3 with a documented CRDT-fanout rationale.
- **Timeout injection seam:** `seconds(5)`/`seconds(30)` are hardcoded constructors; the deterministic-test strategy requires exposing them — small API addition to be specified in Phase 1 planning.
- **Pre-existing races TSan will surface** (`timedOut`, `closed_` unsynchronized): triage-don't-block policy agreed, but fix-or-file disposition should be recorded per finding.
- **`bitswap.hpp`/test friend access:** keeping `BitswapRequestContext` public is preferred; confirm no friend declaration needed when writing the unit test.
- **Callback-timing contract consumers:** enumerate SuperGenius/GeniusSDK callback consumers and audit their assumptions (inline delivery, caller thread) — Phase 4 checklist item, not yet inventoried.

## Sources

### Primary (HIGH confidence)
- Pinned local sources (read 2026-10-12): `thirdparty/ipfs-bitswap-cpp@d2ec18af` — `src/bitswap.cpp` (bug sites L60-99; fixed precedent L565-621; dispatch L268-306; retry re-arm L345-349; chained callbacks L377-415; cancel site L933; providers map L1591-1670), `test/bitswap_server_client_test.cpp` L38-216
- Pinned local sources: `thirdparty/libp2p@28f6a629` — `gossip/impl/remote_subscriptions.{hpp,cpp}` (TODO L75-77, heartbeat sweep L145-147), `impl/stream.{hpp,cpp}` (TODO L64-70, write path L123-147, timeout handle L168-252), `include/.../gossip/gossip.hpp` Config, `impl/message_parser.cpp`
- `thirdparty/ipfs-pubsub@b6eb6268` — `gossip_pubsub.{hpp,cpp}` (Config ctors L95-114, GetDefaultConfig L304-311, gossip::create L301-307)
- `SuperGenius/src/account/GeniusNode.cpp` L1860-1910 (production Config + GossipPubSub construction)
- Boost.Asio official reference (`basic_deadline_timer::cancel/expires_at/expires_from_now`): cancel/re-arm posts handlers with `operation_aborted`; already-queued genuine expiry cannot be canceled; timer not thread-safe
- go-libp2p-pubsub master source: `pubsub.go` (`peerOutboundQueueSize=32` counting RPCs, `WithPeerOutboundQueueSize`, drop-on-full, `DefaultMaxMessageSize=1<<20`, `DefaultMaxControlMessageSize=512<<10`), `gossipsub.go` (`GossipSubMaxIHaveMessages=10`, `GossipSubMaxIHaveLength=5000`, D-params; **`GossipSubMaxSubscriptions` absent**), `rpc_queue.go`, `score.go`
- boxo main source: `bitswap/client/client.go` `GetBlocks` cancellation contract (cancel = silent channel close)
- Prior audit: `.planning/research/gnus_libp2p_comparison.md` (P0 rows this milestone remediates; pin-drift warning now concretized by PITFALLS)

### Secondary (MEDIUM confidence)
- IPFS Bitswap protocol spec (CANCEL wantlist semantics)
- Gossipsub RPC spec — no bound on subscriptions field (implementation self-defense requirement; retrieval partial)
- Kubo deployment topic-count heuristics (tens of topics → few-hundred cap default)

### Tertiary (LOW confidence)
- None — external claims either verified from primary sources or omitted. Seam note: `classify-confidence --provider websearch` mechanically tags fetched content LOW; the Boost and Go claims above were elevated on direct primary-source fetch (vendor docs / canonical repos) and are marked as such in the source files.

---
*Research completed: 2026-10-12*
*Ready for roadmap: yes*
