# Feature Research

**Domain:** libp2p/IPFS correctness & resource-bounding remediation (C++, Boost.Asio) — behaviors referenced against Go boxo bitswap + go-libp2p-pubsub
**Researched:** 2026-10-12
**Confidence:** HIGH (behavior contracts verified against primary sources: Boost.Asio official reference docs, go-libp2p-pubsub master source, boxo main source, plus direct inspection of GNUS fork code at pinned commits in `thirdparty/`)

**Scope guard (from milestone context):** Bitswap 1.0 only. OUT: CI, Bitswap 1.1/1.2, CIDv1, Want-Have/Dont-Have, QUIC/WebSocket, Go interop, benchmarks. "Features" here = **observable behaviors of the fixes**, since consumers of this milestone are GNUS SDK/node developers, not end users.

---

## Feature Landscape

### Table Stakes (Users Expect These)

Behaviors that MUST hold for P0 closure. Missing any = the bug class remains.

| # | Feature (Observable Behavior) | Why Expected | Complexity | Notes |
|---|-------------------------------|--------------|------------|-------|
| TS-1 | **Canceled Bitswap timer never fires failure path** — handler checks `ec == boost::asio::error::operation_aborted` and returns without invoking callbacks | Boost.Asio contract: `cancel()`/`expires_at(pos_infin)`/re-arming `expires_from_now()` all deliver `operation_aborted` to pending `async_wait` handlers; ignoring it manufactures false `OUTBOUND_STREAM_FAILURE`. Go boxo contract: cancel is *silent* (`GetBlocks` context cancel just closes the channel — no error result) | LOW | Fix site: `BitswapRequestContext` (`thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` ~L70–99 — handler currently discards `ec`). The sibling content-request timer (~L575) already does `if (ec) return;` — mirror that pattern |
| TS-2 | **Exactly-once result per request** — success path and timeout path mutually exclusive; a state flag (completed/timed-out) checked under the mutex prevents double-callback even when a genuinely-expired handler is already queued and can no longer be canceled | Boost.Asio caveat (official docs): if the timer already expired when you cancel, the handler has already run or is queued with *success* — error-code checking alone is insufficient; the cancel-vs-timeout race needs a completion flag | LOW–MED | Pattern already proven in-file: `ContentRequestContext::timedOut` flag + move-callback-out-under-lock (~L596–621). Extend to `BitswapRequestContext` which has no such flag (`callbacks_` can be re-fired by a stale timer) |
| TS-3 | **Cancel means silence** — consumer-initiated cancellation (or success) produces NO error callback; only genuine timeout produces exactly one failure callback (`REQUEST_TIMEOUT`-class) | boxo observable contract: canceled retrieval = channel closed, no error; timeouts/failures = error delivered once | LOW | Depends on TS-1 + TS-2; mostly falls out of them |
| TS-4 | **Consumer callbacks dispatched outside all internal mutexes** — state mutated under lock (move callbacks out, mark completed, erase from request map), callbacks invoked after unlock | Holding `mutex_` while running arbitrary consumer code is the classic reentrancy deadlock (consumer re-enters Bitswap → blocks on the same mutex). Go equivalent: results delivered on a channel, never under internal lock | MED | Fix site: `BitswapRequestContext::HandleResponse` (~L86–93) currently loops `callback(block)` under `lock_guard(mutex_)`. The move-out/dispatch-after pattern is already proven in the same file (content-timer fix, "same pattern as C-7 fix in processReceivedBlocks") — reuse it |
| TS-5 | **Callback may synchronously re-enter Bitswap** — cancel its own request, issue new requests, or destroy consumer state without deadlock or use-after-free | This is the acceptance criterion for TS-4; boxo consumers routinely cancel from their receive goroutine. Requires `shared_from_this()`-kept context alive during dispatch (pattern already present in the timer lambda) | MED | Test doubles as the regression test for TS-4. Thread-identity documented in-file: dispatch happens on the libp2p io_context (serialized), so no new locking model needed |
| TS-6 | **Per-peer subscription cap with configurable knob** — remote subscription table bounded; excess subscribes in an RPC ignored (and/or violating peer blocked), config field in `Gossip::Config` | Gossipsub RPC spec imposes **no** bound on `repeated string subscriptions` — implementations must self-defend. Go relies on resource-manager memory limits + ignoring unsubscribed topics; GNUS C++ has neither, and the fork's own TODO (`remote_subscriptions.hpp` L75–77: "bound table size (which may grow!)") calls for pruning topics not locally subscribed (LRU) | MED | Fix sites: `RemoteSubscriptions::table_` + `MessageParser` (bounds the subscribe list per RPC). Config goes in `gossip.hpp` `Config` (~L60–90, where other knobs live). Default suggested: a few hundred (Go has no equivalent; Kubo deployments see ~tens of topics) |
| TS-7 | **Bounded outbound per-peer queue with drop-on-full default** — pending outbound buffers/bytes capped per peer; on cap hit, drop the RPC for that peer (log + metric), do NOT disconnect by default; knob in `Config` | Go gossipsub (verified from master source): `peerOutboundQueueSize` default **32 RPCs**, option `WithPeerOutboundQueueSize` (must be positive); on full → `ErrQueueFull` → `doDropRPC(rpc, p, "queue full")` with tracer visibility — no disconnect; subscribe announces get a scheduled retry | MED–HIGH | Fix site: `Stream::pending_buffers_`/`pending_bytes_` (`stream.hpp` L64–70 TODO: "limit pending bytes and close slow streams that way"). Count-based (Go parity: 32) and/or byte-based cap. Byte cap is where the C++ TODO already plans *disconnect* for slow streams — acceptable escalation, but must be a distinct, higher threshold than the count cap (Go drops at 32, never disconnects for queue-full) |
| TS-8 | **Violation escalation via existing peer-block path** — a peer that persistently exceeds bounds (repeated sub-list overflow, sustained queue-full from slow drain) is blockable through the existing `DenyListConnectionGater::BlockPeer()` (or disconnect per TODO) rather than inventing new policy machinery | Go's answer to persistent violators is score-driven graylisting; GNUS already ships manual peer blocking (`DenyListConnectionGater` BlockPeer/UnblockPeer in ipfs-pubsub) — reuse it as the P0 escalation mechanism | LOW | Keeps milestone additive; wiring only |
| TS-9 | **Observability on bound hit** — every cap enforcement event logged (peer, topic/count, bytes) via existing `log::SubLogger`; no silent drops | Go: queue-full drops surfaced via `tracer.DropRPC` + Info log "queue full; scheduling retry". Silent drops are undebugtable in a P2P mesh | LOW | `LIBP2P_METRICS_INSTANCE_COUNT_IF_ENABLED` already exists in `Stream` — extend naturally |
| TS-10 | **Regression tests for each race** — (a) cancel raced with expiry (both orders), (b) response-then-canceled-timer-fires (no failure after success), (c) timeout-then-late-response (no success-after-failure / no double callback), (d) reentrant callback cancels own request without deadlock | Each fix is a race-condition fix; without the adversarial ordering test the P0 cannot be declared closed. GTest already in thirdparty; bitswap has existing test patterns | MED | Highest-leverage table-stakes item for "P0 closure" semantics; tests are the observable proof |

### Differentiators (Competitive Advantage)

Optional hardening beyond P0 closure. Valuable, but NOT required for this milestone.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| D-1 | **Behavior-based peer scoring** — Go `PeerScoreThresholds` model: `GossipThreshold` (suppress gossip from peer), `PublishThreshold` (don't publish toward peer), `GraylistThreshold` (suppress ALL processing = graylist), `BehaviourPenalty` (squared excess above threshold, decays per heartbeat); `validate()` enforces negative ordering Gossip ≥ Publish ≥ Graylist ≤ 0 | Automatic, proportionate response to misbehaving peers vs. manual BlockPeer | HIGH | This is GossipSub v1.1 territory; explicitly beyond P0. GNUS `/meshsub/1.0.0` default already signals v1.0 semantics. Defer to a future milestone |
| D-2 | **Decay-based graylist** — auto-unblock after TTL (Go: penalty decay per heartbeat; ban_interval already exists in C++ config) | Removes manual UnblockPeer babysitting | MED | Cheap middle ground: TTL on BlockPeer entries using existing `ban_interval_msec` precedent |
| D-3 | **Two-lane outbound queue (urgent control lane)** — Go's `UrgentPush` keeps control/subscribe-announce RPCs from being starved behind bulk publish traffic | Keeps mesh maintenance alive under load | MED | Nice-to-have on top of TS-7's single bounded deque; Go parity argument |
| D-4 | **Idle outbound stream recycling** — close/respawn writer for peers whose queues sit idle (Go `deadPeerBackoff` respawn w/ backoff) | Reclaims per-peer queue memory from departed-but-connected peers | LOW–MED | `Connectivity` scheduler already periodic (heartbeat) — hook there |
| D-5 | **Slow-local-consumer backpressure policy** — bounded inbound delivery queue per local subscription with documented overflow policy | Protects node from its own slow CRDT-sync consumer | MED–HIGH | Touches consumer-facing API semantics; not part of P0 resource-bounding of *remote* peers |

### Anti-Features (Commonly Requested, Often Problematic)

Scope creep to reject at requirement categorization time.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| AF-1 | **Full peer-score port (GossipSub v1.1 scoring/signed peer records)** | "Go has it, parity!" | Large surface (per-topic params, decay infra, validation), explicitly v1.1 while GNUS runs v1.0 protocol ID; mixes remediation with feature work | TS-8 escalation via existing BlockPeer now; D-1 as its own future milestone |
| AF-2 | **Disconnect-on-any-queue-full default** | "Simplest way to bound memory" | Disconnects are self-inflicted mesh damage under transient bursts; Go's verified default is drop-at-32, never disconnect for queue-full | TS-7: drop by default; disconnect only at a distinct sustained/byte-level slow-stream threshold (the stream.hpp TODO's own plan) |
| AF-3 | **"Just make queues/tables bigger" (raise limits, no policy)** | Cheap one-liner | Moves the exhaustion point, doesn't fix it; untrusted-peer memory growth remains | Bounded caps with drop/ignore policy + knob (TS-6/TS-7) |
| AF-4 | **Bitswap 1.1/1.2, Want-Have/Dont-Have, CIDv1** while touching bitswap.cpp | "We're in there anyway" | Explicitly OUT OF SCOPE per milestone; changes wire protocol surface and interop risk while fixing races | Land P0 fixes on 1.0; protocol bumps are their own milestone |
| AF-5 | **Go interop harness / benchmarks / CI restoration** while fixing these bugs | Tempting to bundle verification | Each is explicitly OUT OF SCOPE; bundling stalls the correctness fixes behind infra work | In-repo GTest regression tests (TS-10) prove the fixes; interop/bench/CI tracked separately |
| AF-6 | **Silent drop without logging** ("logging in hot path costs perf") | Perf instinct | Undebugtable mesh; violates Go-observed contract (drops traced + logged) | TS-9: log at bounded rate if hot-path concern, but never silent |

## Feature Dependencies

```
[TS-1 ec-check]      [TS-2 exactly-once flag]     [TS-4 dispatch-outside-lock]
      └──both──┬──────────┘                                    │
               v                                              v
          [TS-3 cancel-is-silent]                    [TS-5 reentrancy-safe]
               │                                              │
               └──────────────┬───────────────────────────────┘
                              v
                       [TS-10 regression tests]
                              (proves TS-1..TS-5)

[TS-6 sub cap + knob] ──uses──> [gossip.hpp Config]
[TS-7 outbound queue cap] ──uses──> [Stream::pending_buffers_/pending_bytes_]
[TS-6]──persistently violating──>[TS-8 BlockPeer escalation]──uses──> existing DenyListConnectionGater
[TS-7]──sustained slow stream──>[TS-8 disconnect variant per stream.hpp TODO]
[TS-6]/[TS-7]/[TS-8] ──all──> [TS-9 observability]

[D-2 decay graylist] ──enhances──> [TS-8]
[D-3 urgent lane]    ──enhances──> [TS-7]
[D-1 peer scoring]   ──supersedes──> [TS-8] (future milestone; conflicts if built simultaneously)
```

### Dependency Notes

- **TS-3 requires TS-1 + TS-2:** silence-on-cancel only holds if both the error-code check and the completion-flag guard exist; either alone leaves a race (Asio can deliver a queued *success* expiry after cancel).
- **TS-5 requires TS-4:** reentrancy is the test of lock-free dispatch; fix and test are one work unit.
- **TS-10 requires TS-1…TS-5 to exist:** tests encode the race orderings; write them against the fixed contract, and they double as the P0 acceptance evidence.
- **TS-6/TS-7 require Config extension (`gossip.hpp`):** both knobs land in the existing `Config` struct alongside `max_message_size`/`ban_interval_msec` — single touch point for "configurable knobs" requirement.
- **TS-8 reuses ipfs-pubsub `DenyListConnectionGater` (BlockPeer/UnblockPeer):** no new gater interface; gossip core signals violations up through its `Feedback`/`Connectivity` seams.
- **Bitswap fixes depend on in-file precedent, not new design:** the content-timer fix (ec-check + `timedOut` + move-out-under-lock, `bitswap.cpp` ~L575–621) is the reference implementation for TS-1/2/4 — port it to `BitswapRequestContext` (~L66–99) and `checkContentRequestComplete` (~L930–940, whose `timeout.cancel()` currently relies on that ec-check).
- **D-1 conflicts with TS-8 if attempted together:** scoring supersedes manual-block escalation; building both in one milestone wastes the TS-8 wiring and expands blast radius.

## MVP Definition

### Launch With (v1.0 — P0 closure)

- [ ] TS-1 canceled-timer ec-check (`BitswapRequestContext`) — kills the false-failure bug class
- [ ] TS-2 exactly-once completion flag on both bitswap request contexts — kills double-callback class
- [ ] TS-3 cancel-is-silent observable contract — the consumer-visible definition of "fixed"
- [ ] TS-4 callbacks outside `mutex_`/`mutexContentRequests_` — kills deadlock class
- [ ] TS-5 reentrancy-safe dispatch (callback may cancel its own request) — acceptance test for TS-4
- [ ] TS-6 per-peer subscription cap + Config knob + ignore-excess — closes remote_subscriptions TODO
- [ ] TS-7 bounded outbound queue (count 32 Go-parity default and/or bytes) + drop-on-full + Config knob — closes stream.hpp TODO
- [ ] TS-8 escalation wiring to existing BlockPeer (+ disconnect variant only for sustained slow-stream byte threshold)
- [ ] TS-9 log/metric on every bound hit
- [ ] TS-10 regression tests for all four race orderings + sub/queue bound tests

### Add After Validation (v1.x)

- [ ] D-3 urgent control-message lane — when mesh instability under publish load is observed
- [ ] D-4 idle stream recycling — when per-peer memory from departed peers shows up in metrics
- [ ] D-2 TTL/decay graylist — when manual UnblockPeer becomes operational burden

### Future Consideration (v2+)

- [ ] D-1 peer scoring w/ thresholds — its own milestone (GossipSub v1.1 scope)
- [ ] D-5 local-consumer backpressure — changes public API semantics; needs its own design pass

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| TS-1 timer ec-check | HIGH | LOW | P1 |
| TS-2 exactly-once flag | HIGH | LOW | P1 |
| TS-3 cancel-silent contract | HIGH | LOW | P1 |
| TS-4 dispatch outside lock | HIGH | MEDIUM | P1 |
| TS-5 reentrancy safety | HIGH | MEDIUM | P1 |
| TS-10 race regression tests | HIGH | MEDIUM | P1 |
| TS-6 subscription cap + knob | HIGH | MEDIUM | P1 |
| TS-7 bounded outbound queue | HIGH | MEDIUM | P1 |
| TS-8 escalation via BlockPeer | MEDIUM | LOW | P1 |
| TS-9 bound-hit observability | MEDIUM | LOW | P1 |
| D-2 decay graylist | MEDIUM | MEDIUM | P2 |
| D-3 urgent lane | MEDIUM | MEDIUM | P2 |
| D-4 idle stream recycle | LOW–MED | LOW–MED | P2 |
| D-5 consumer backpressure | MEDIUM | HIGH | P3 |
| D-1 peer scoring | HIGH (long-term) | HIGH | P3 |

## Competitor Feature Analysis

Here "competitors" = reference implementations defining expected behavior.

| Behavior | Go boxo bitswap (main) | Go go-libp2p-pubsub (master) | GNUS C++ approach (this milestone) |
|----------|------------------------|-------------------------------|-------------------------------------|
| Cancel semantics | Context cancel = silent channel close, no error; wants broadcast as CANCEL | n/a | TS-1/2/3: ec==operation_aborted → no callback; flag guarantees exactly-once |
| Timeout semantics | Error delivered once via channel after deadline/attempts | n/a | Exactly one failure callback via completion flag |
| Result delivery | Channel (never under internal lock) | n/a | Move-out-under-lock, dispatch after unlock (TS-4/5) |
| Per-peer sub bound | n/a | None explicit (resource manager + ignore-unknown-topic) | Explicit cap + ignore-excess + knob — strictly stronger than C++ status quo; simpler than Go's resmgr dependency (TS-6) |
| Outbound queue | n/a | 32 RPCs default, `WithPeerOutboundQueueSize`, drop-on-full w/ tracer.DropRPC, no disconnect; announce retry; UrgentPush lane | Count(32)/byte cap, drop default, disconnect only for sustained slow streams, knob in Config (TS-7/8); urgent lane deferred (D-3) |
| Violator handling | n/a | Score thresholds → gossip-suppress/publish-suppress/graylist; BehaviourPenalty squared-excess decay | Reuse manual BlockPeer escalation now (TS-8); scoring later (D-1) |
| Bound visibility | n/a | Info log + pubsub tracer events | SubLogger warn + metrics counter on every hit (TS-9) |

## Sources

- Boost.Asio official reference (`boost.org/doc/libs/latest`, via context7, retrieved 2026-10-12): `basic_deadline_timer::cancel/expires_at/expires_from_now` — operation_aborted delivery + queued-expiry cannot-be-canceled caveat. **Confidence: HIGH (curated docs, cross-checked against handler semantics in GNUS code).**
- go-libp2p-pubsub master raw source (retrieved 2026-10-12): `pubsub.go` (peerOutboundQueueSize=32, WithPeerOutboundQueueSize, deadPeerBackoff), `rpc_queue.go` (priority lanes, ErrQueueFull on non-blocking push), `gossipsub.go` (doSendRPC/doDropRPC "queue full"), `score.go` + `score_params.go` (PeerScoreThresholds, BehaviourPenalty P7). **Confidence: HIGH (primary source).**
- boxo main raw source (retrieved 2026-10-12): `bitswap/client/client.go` GetBlocks cancellation doc contract. **Confidence: HIGH (primary source).**
- IPFS Bitswap protocol spec (specs.ipfs.tech) — CANCEL wantlist entries. **Confidence: MEDIUM.**
- Gossipsub RPC spec — no bound on subscriptions field; implementation self-defense requirement. **Confidence: MEDIUM** (spec text retrieval was partial; consistent with Go implementation's resmgr-based defense).
- GNUS fork code inspection (2026-10-12): `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` (L66–99 block-context timer; L575–621 fixed content-timer as in-file precedent; L933 cancel site), `thirdparty/libp2p/include/libp2p/protocol/gossip/gossip.hpp` (Config L60–90, no bound knobs), `src/protocol/gossip/impl/remote_subscriptions.hpp` (L75–77 bound-table TODO), `src/protocol/gossip/impl/stream.hpp` (L64–70 pending-bytes TODO). **Confidence: HIGH (direct inspection at integrated submodule state).**
- Prior audit: `.planning/research/gnus_libp2p_comparison.md` (P0 list this milestone remediates).

---
*Feature research for: IPFS P0 remediation (ipfs-improve workstream, milestone v1.0)*
*Researched: 2026-10-12*
