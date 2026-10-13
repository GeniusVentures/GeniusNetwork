---
phase: 03-gossipsub-resource-bounds
reviewed: 2026-10-13T00:00:00Z
depth: deep
files_reviewed: 15
files_reviewed_list:
  - thirdparty/libp2p/include/libp2p/protocol/gossip/gossip.hpp
  - thirdparty/libp2p/src/protocol/gossip/impl/common.hpp
  - thirdparty/libp2p/src/protocol/gossip/impl/common.cpp
  - thirdparty/libp2p/src/protocol/gossip/impl/stream.hpp
  - thirdparty/libp2p/src/protocol/gossip/impl/stream.cpp
  - thirdparty/libp2p/src/protocol/gossip/impl/connectivity.hpp
  - thirdparty/libp2p/src/protocol/gossip/impl/connectivity.cpp
  - thirdparty/libp2p/src/protocol/gossip/impl/gossip_core.hpp
  - thirdparty/libp2p/src/protocol/gossip/impl/gossip_core.cpp
  - thirdparty/libp2p/src/protocol/gossip/impl/remote_subscriptions.hpp
  - thirdparty/libp2p/src/protocol/gossip/impl/remote_subscriptions.cpp
  - thirdparty/ipfs-pubsub/src/ipfs_pubsub/gossip_pubsub.hpp
  - thirdparty/ipfs-pubsub/src/ipfs_pubsub/gossip_pubsub.cpp
  - thirdparty/ipfs-pubsub/test/src/gossip_pubsub_bounds_test.cpp
  - thirdparty/ipfs-pubsub/test/src/CMakeLists.txt
findings:
  critical: 0
  major: 1
  minor: 2
  info: 2
  total: 5
status: issues_found
submodules:
  libp2p: dev_gossip_bounds @ a54f5c4 (2 commits from 28f6a629, linear)
  ipfs-pubsub: dev_ipfs_fix @ 5c6653c (3 commits from b6eb6268, linear)
---

# Phase 03: GossipSub Resource Bounds — Code Review Report

**Reviewed:** 2026-10-13
**Depth:** deep (cross-file: admission check → error funnel → violation seam → BlockPeer chain; both submodule diffs read in full)
**Scope:** libp2p `28f6a629..a54f5c4`, ipfs-pubsub `b6eb6268..5c6653c` (`src/` primary; test file scanned for prohibited patterns)
**Status:** issues_found (0 critical / 1 major / 2 minor / 2 info)

## Summary

The egress spine (Stream admission cap → K-drops close → `Error::PENDING_OVERFLOW` → violation seam → 2nd-close BlockPeer) and the ingress cap (check-then-insert in `onPeerSubscribed`) are implemented faithfully to the plan's locked decisions. The three review-focus verifications all pass:

- **(b) Admission ordering** — the empty-buffer early return (`stream.cpp:136-138`) precedes the admission check (`stream.cpp:146`); an empty RPC is never counted as a drop. ✓
- **(c) Registration race** — `GossipPubSub` registers the handler in `InitHostFromInjector` (invoked from `Init()` in the constructor), strictly before `Start()`; `GossipCore::start()` forwards it to `Connectivity` at the moment `connectivity_` is created (`gossip_core.cpp:126-141`). ✓
- **Plan conformance** — strict-greater comparison (D-07), single reset-on-full-drain site (D-06), drop-new-only (D-05), cap check before any table mutation with dedup first (D-03), `onHeartbeat`/`empty()` untouched (D-04), `deny_list_connection_gater.hpp` untouched, fmt data-only logging (no injection surface). ✓

The one significant gap is the one the review focus anticipated: the per-peer close-counter map in `GossipPubSub` has **no eviction** and is attacker-reachable (MAJ-01). Two smaller API/boundary defects and two informational notes follow. No finding contradicts a D-01..D-12 decision; overlaps are called out per finding.

## Major

### MAJ-01: Per-peer sustained-overflow close-counter map grows without bound; no eviction on block, unblock, or disconnect

**File:** `thirdparty/ipfs-pubsub/src/ipfs_pubsub/gossip_pubsub.hpp:360-371`, `thirdparty/ipfs-pubsub/src/ipfs_pubsub/gossip_pubsub.cpp:317-337`
**Issue:** `m_sustainedOverflowCloses[peerId]` is inserted on every sustained-overflow close and erased nowhere — not when the peer is blocked, not in `UnblockPeer()` (`gossip_pubsub.cpp:256-260` only touches the gater), not on peer disconnect. The entry is attacker-reachable: a Sybil remote peer grafts into a busy topic's mesh, stalls reading (the sustained-overflow trigger is *our* outbound backlog), reconnects, and repeats — each distinct attacker PeerId that survives one K-drops close pins a permanent `unordered_map` node (`PeerId` + `size_t` + hash buckets). With churn (the natural consequence of close→redial cycles the design itself induces) this is an unbounded memory growth vector in the exact violation-handler path the review was asked to scrutinize. It is slow-growth (bounded by distinct offending PeerIds, not by traffic volume), hence Major rather than Critical.

Secondary semantic consequence of the same missing reset: after an operator calls `UnblockPeer()`, the counter is already ≥ 2, so a *single* further sustained-overflow close re-blocks the peer instantly — the one-episode tolerance (D-09) silently no longer applies post-unblock. If instant re-block of a previously-unblocked peer is intended policy, it is undocumented; D-10 covers only block *persistence*, not counter lifetime, so eviction is not plan-locked out (the D-10 prohibition on "decay" targets the block/deny-list entry, not map hygiene).

**Fix:**
```cpp
void GossipPubSub::UnblockPeer( const libp2p::peer::PeerId &peerId )
{
    m_logger->info( "Connection gater: unblocking peer {}", peerId.toBase58() );
    m_connection_gater->UnblockPeer( peerId );
    // Fresh start after an explicit operator unblock: the peer must sustain
    // kSustainedOverflowClosesToBlock fresh closes to be re-blocked (D-09
    // one-episode tolerance applies again). Also bounds the map for the
    // block/unblock cycle path.
    {
        std::lock_guard<std::mutex> lock( m_sustained_overflow_mutex );
        m_sustainedOverflowCloses.erase( peerId );
    }
}
```
For the disconnect/Sybil path, additionally cap or sweep the map (e.g., erase on `onPeerDisconnected` if a hook exists, or evict oldest entries above a hard ceiling such as 10× the gater's deny-list size). If the instant-re-block-after-unblock semantics is deliberate, document it in the D-09/D-10 marker comment and fix only the eviction half.

## Minor

### MIN-01: `GossipCore::setViolationHandler` after `start()` silently has no effect

**File:** `thirdparty/libp2p/src/protocol/gossip/impl/gossip_core.cpp:188-195` (vs. forwarding at `gossip_core.cpp:137-141`)
**Issue:** The handler is stored in `GossipCore::violation_handler_` and forwarded to `Connectivity` **only inside `start()`**. `Connectivity` is created at `start()` (`gossip_core.cpp:126`), so a registration that arrives after `start()` returns is stored but never forwarded — the seam silently never fires. `GossipPubSub` (the only current embedder) registers pre-start, so no live bug today, but this is a public-API footgun exactly one refactor away from a "why doesn't my handler fire" defect. Note the same one-shot-forward shape exists for other setters in this codebase, so this is consistency-with-footgun rather than a new pattern.
**Fix:** Forward immediately when already started (both assignments are safe pre-start since the gossip strand cannot be reading `Connectivity::violation_handler_` before `connectivity_->start()`):
```cpp
void GossipCore::setViolationHandler(ViolationHandler handler) {
    violation_handler_ = std::move(handler);
    if (started_) {
      // forward late registrations; safe only from a non-gossip thread
      // before connectivity_->start() has emitted events — otherwise the
      // embedder contract (register before start()) applies
      connectivity_->setViolationHandler(violation_handler_);
    }
}
```
or, minimally, extend the existing comment into a hard contract (assert/warn when called after `start()`).

### MIN-02: Default-config boundary — a batched/piggybacked outbound RPC can exceed the cap with an empty queue, feeding the close→block escalation against honest slow mesh peers

**File:** `thirdparty/libp2p/src/protocol/gossip/impl/stream.cpp:146-149`, `thirdparty/libp2p/include/libp2p/protocol/gossip/gossip.hpp:97-101`
**Issue:** Inbound frames are admitted up to `max_message_size` inclusive (`onLengthRead`, `stream.cpp:83-85` — strict `>`), and `max_pending_bytes_per_stream` defaults to the same `1 << 24` (D-02). An *outbound* RPC is a fresh serialization: relayed message(s) plus protobuf framing, plus any piggybacked control (IHAVE/graft) or a second message flushed in the same heartbeat. Two legitimate 8 MiB messages batched into one RPC, or one near-16 MiB message plus framing, serialize strictly greater than the cap and are dropped **at entry with an empty queue** — the D-02 claim "a single legitimate large CRDT RPC is never dropped" holds per-RPC but not per-batch. Under sustained large-message traffic toward an honest-but-slow mesh peer, each flushed batch is dropped, the K=8 consecutive-drop counter never resets (the queue drains between drops only if traffic subsides), the stream closes twice, and the peer is **permanently blocked** — the full escalation machinery aimed at an honest peer by composition, not by attack.
**Plan-lock status:** D-02 (cap default mirrors `max_message_size`), D-07 (strict-greater), and D-09 (2nd-close block) are plan-locked, and the 03-01 truth explicitly frames the empty-queue over-cap drop as intended — so this is raised as boundary documentation/known-limitation, not as a request to change the locked comparisons. The *batching* consequence is not addressed anywhere in the plan truths.
**Fix (v2 candidate, consistent with locked decisions):** either (a) bound batch assembly upstream so a serialized flush never exceeds `max_pending_bytes_per_stream` (drop the *batch*, not the whole RPC, at assembly time), or (b) set the documented default to `k * max_message_size` for piggyback headroom, or (c) at minimum record this boundary in the D-02 marker comment in `gossip.hpp` so embedders sizing `max_message_size` near real payload sizes know to raise the pending cap.

## Info

### INF-01: Pure-virtual `setViolationHandler` added to the public `Gossip` interface is source-breaking for out-of-tree implementers

**File:** `thirdparty/libp2p/include/libp2p/protocol/gossip/gossip.hpp:175-176`
**Issue:** Adding a pure virtual to `Gossip` compiles only for implementers that override it; the plan-acknowledged assumption is that `GossipCore` is the only implementer (true in-tree). Any external embedder subclassing `Gossip` breaks at compile time. Defaults preserve *behavioral* compatibility for all existing embedders (verified: the three Config knobs default to no-op bounds for legitimate traffic, and the enum/category additions are additive). No action required for this phase; flag for the Phase-4 repin/upstream-sync notes.

### INF-02: `asyncPostViolation` strong self-capture and `this`-capturing GossipPubSub handler — teardown safety rests on Stop() ordering (verified, with residual caveat)

**File:** `thirdparty/libp2p/src/protocol/gossip/impl/stream.cpp:256-266`, `thirdparty/ipfs-pubsub/src/ipfs_pubsub/gossip_pubsub.cpp:319-337`
**Issue:** The posted violation lambda holds a strong `Stream` ref until dispatch, and `Stream::feedback_`/`log_` reference `Connectivity` members while the `GossipPubSub` handler captures `this`. I traced the teardown path: `~GossipPubSub` → `Stop()` → `StopImpl()` stops gossip, drains/joins the io_context thread, and only then resets `m_gossip`/`m_context` before member destruction — so in-flight posts either execute while members are alive or are destroyed unexecuted with the io_context. This is plan-locked (FLAGGED ASSUMPTION #5 chose the strong capture deliberately; the WSL ASan run was clean). Residual caveat: safety depends on every embedder destroying `GossipPubSub` through `Stop()`/destructor only — never destroying `m_gossip`-adjacent members out of order. The intermittently-observed test-fixture teardown crash and exit hang are **already recorded** as deferred items 2 and 3 (not re-raised here). No action; keep the assumption documented at the `asyncPostViolation` comment.

## Explicitly verified clean (review-focus items)

| Focus item | Result |
|---|---|
| (a) Close-counter map eviction | **Missing — MAJ-01** |
| (b) `write()` empty-buffer early return vs. admission check | Correct: `stream.cpp:136-138` returns before the `stream.cpp:146` check; empty RPCs never counted (GOSS-04 truth holds) |
| (c) Handler registration before `Start()` | Correct: ctor-path registration (`gossip_pubsub.cpp:313-337` → `Init()` → `InitHostFromInjector`), forwarded at `gossip_core.cpp:137-141` inside `start()` — no window where a stream event can precede registration |
| `consecutive_overflow_drops_` reset semantics | Single reset site, full-drain else-branch only (`stream.cpp:238-244`) — matches D-06 exactly; no admission-path reset exists |
| Strict-greater admission (`pending_bytes_ + size > cap`) | Matches D-07 (`stream.cpp:146`); exact-on-cap admitted |
| Ingress cap ordering | Dedup early-return (`remote_subscriptions.cpp:45-49`) → cap check (`:64-65`) → insert (`:76`) — check-then-insert, no table mutation before decision (D-03); `onPeerDisconnected` swaps `subscribed_to`, so disconnect regains headroom |
| Log injection | All new logs use fmt `{}` placeholders with `peer->str`/`TopicId`/byte counts as data only — no interpolation of user-controlled strings into format strings |
| Style consistency | libp2p additions follow 2-space/snake_case/Scheduler-strand conventions; ipfs-pubsub additions follow Allman/`m_` prefix; comments use the GOSS/decision markers consistently with the plan |
| `deny_list_connection_gater.hpp` | Byte-identical (not in diff); `onHeartbeat`/`empty()` untouched (D-04 verified from diffstat + hunk contents) |
| Branch discipline | libp2p `dev_gossip_bounds` = 2 commits linear from `28f6a629`; ipfs-pubsub `dev_ipfs_fix` = 3 commits linear from `b6eb6268`; matches the prohibitions |

## Deferred-items cross-check

- Deferred item 1 (upstream `assert(close_res)` in `upgrader_session.cpp:88` on Linux Debug): untouched by this diff — not re-raised.
- Deferred items 2 & 3 (shared raw-fixture teardown crash; process exit-hang): test-fixture-only, pre-existing, referenced in INF-02 — not re-raised.

---

_Reviewed: 2026-10-13_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: deep_
