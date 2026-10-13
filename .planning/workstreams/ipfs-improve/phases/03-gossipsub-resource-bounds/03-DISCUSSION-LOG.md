# Phase 3: GossipSub Resource Bounds - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-13
**Phase:** 3-GossipSub Resource Bounds
**Areas discussed:** Config knobs & defaults, Subs cap enforcement, Overflow drop/close line, BlockPeer wiring, TEST-02 harness

---

## Config knobs & defaults

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal 3 | max_remote_subscriptions_per_peer + max_pending_bytes_per_stream + overflow-close threshold. Exactly what GOSS-01/02 name; additive fields can extend later. | ✓ |
| Go-anchored ~5 | Also per-RPC subscribe-entry cap + queue-length cap (go-libp2p-pubsub parity); more tuning surface now. | |
| Researcher proposes | Researcher anchors to go-libp2p-pubsub defaults during research. | |

**User's choice:** Minimal 3
**Notes:** None.

| Option | Description | Selected |
|--------|-------------|----------|
| = max_message_size | Cap = 16 MiB; single legit RPC never trips it; only queued backlog beyond one message does. | ✓ |
| 1 MiB | Go ballpark; tight but drops legit >1 MiB RPCs at write() entry. | |
| 4 MiB | Middle ground. | |
| k x msg size | e.g. 1.5x max_message_size headroom. | |

**User's choice:** = max_message_size
**Notes:** Tension surfaced during discussion: CRDT broadcasts can be large single RPCs; a sub-16 MiB default would drop legitimate publishes (false positive, not bound enforcement).

---

## Subs cap enforcement

| Option | Description | Selected |
|--------|-------------|----------|
| Receiver-side cap | RemoteSubscriptions::onPeerSubscribed checks cumulative per-peer topic count; excess ignored + logged. One choke point; bounds drip-flooding; keeps 3-knob set. | ✓ |
| Parser-side cap | message_parser drops subscribe entries beyond per-RPC limit. Stateless but can't see cumulative state; adds 4th knob. | |
| Both layers | Per-RPC first line + receiver-side true bound; 4th knob. | |

**User's choice:** Receiver-side cap
**Notes:** Scout found RemoteSubscriptions is topic→subscriber-set with no per-peer view today — new bookkeeping needed either way.

| Option | Description | Selected |
|--------|-------------|----------|
| GC empty topics | Heartbeat removes zero-counted-subscriber, not-locally-subscribed, no-mesh/graft topics. Composes with cap into full table bound; never evicts live state. | ✓ |
| LRU (TODO idea) | In-file TODO's original: LRU-evict non-local topics, skipping live subscribers. | |
| Total table cap | Hard ceiling with LRU-first eviction, live eviction as last resort. Strongest ceiling, most eviction-risk analysis. | |

**User's choice:** GC empty topics
**Notes:** None.

---

## Overflow drop/close line

| Option | Description | Selected |
|--------|-------------|----------|
| Drop new only | Queued buffers stay; arriving RPC dropped + logged. GOSS-02 verbatim; no control-message reordering; no two-lane creep. | ✓ |
| Shed oldest too | Evict oldest queued to admit new. Freshest data flows; reorder/drop risk for graft/prune; drifts toward v2 QUER-01. | |
| Agent discretion | Planner picks per GOSS-02 wording and code constraints. | |

**User's choice:** Drop new only
**Notes:** None.

| Option | Description | Selected |
|--------|-------------|----------|
| Consecutive drops K | K consecutive cap-hit drops with no intervening full drain → close. Counter resets on drain; easiest deterministic test drive. | ✓ |
| Full for N beats | pending_bytes_ at/above cap continuously for N heartbeats → close. Byte-anchored; needs since-full tracking. | |
| Windowed rate | M drops within T-heartbeat window → close. Burst-tolerant; most bookkeeping. | |

**User's choice:** Consecutive drops K
**Notes:** Subtlety surfaced: once drops fire at entry, pending_bytes_ can never exceed the cap, so a byte-level higher threshold is unreachable by construction — K (event count) defines SC2's "distinct higher threshold" instead.

---

## BlockPeer wiring

| Option | Description | Selected |
|--------|-------------|----------|
| Violation callback | Gossip::setViolationHandler(fn(peer_id, violation_type)); GossipPubSub registers handler → m_connection_gater->BlockPeer(). Explicit, unit-testable, minimal API. | ✓ |
| Extend Feedback | Route violations through existing Stream::Feedback chain. Still needs new external surface at top; internal plumbing. | |
| Counters + poll | Gossip exposes per-peer violation counters; GossipPubSub polls on timer. Laggy; policy lands in poller. | |

**User's choice:** Violation callback
**Notes:** Scout established libp2p gossip has no block/gater concept at all — BlockPeer lives one layer up in ipfs-pubsub. Confirms Phase 3 spans two submodules (libp2p `28f6a629` + ipfs-pubsub `b6eb6268`), both feeding Phase 4's pin chain.

| Option | Description | Selected |
|--------|-------------|----------|
| Nth stream close | Block after K_close sustained-overflow closes (2–3). Catches reconnect-and-reoffend; tolerates one slow episode. | ✓ |
| Block on 1st close | Harshest; risks permanently blocking a legitimately slow peer after one CRDT burst. | |
| Weighted budget | Subs-ignores + drops + closes feed a weighted budget. Drifts into v2-deferred PSCG-01 peer scoring — requirements conflict. | |

**User's choice:** Nth stream close
**Notes:** None.

| Option | Description | Selected |
|--------|-------------|----------|
| Permanent | Block holds until UnblockPeer(). Existing DenyList semantics; zero new machinery (GOSS-03 verbatim). | ✓ |
| TTL auto-unblock | ban_interval_msec-precedent decay graylist. This IS v2's PSCG-02 — would pull deferred scope in. | |

**User's choice:** Permanent
**Notes:** None.

---

## TEST-02 harness

| Option | Description | Selected |
|--------|-------------|----------|
| libp2p gossip suite | Extend test/libp2p/protocol/gossip/ + scheduler_mock; D-03 pattern; MUST-verify Windows. | |
| New minimal target | New in-libp2p target instantiating internals with mocks; sidesteps broken suite, stays in-submodule. | |
| AsyncIOManager | Phase 1 fallback host; Windows-proven but poorly suited to internal enforcement points. | |
| ipfs-pubsub (user freeform) | Tests in ipfs-pubsub — "our" code; libp2p has weird setups and python stuff. | ✓ |

**User's choice:** ipfs-pubsub (freeform suggestion, then delegated final shape)
**Notes:** User asked "Maybe in ipfs-pubsub repo?"; agent scouted ipfs-pubsub's suite (gossip_pubsub_test.cpp, topic test, CMakeLists) and workspace memory (SuperGenius pubsub_counts gater-blocking test, Windows-proven), then presented three refined shapes: A split, B all-ipfs-pubsub, C all-libp2p. User replied "Just make the best choice for this situation." → agent locked **B as refined**: subscribe cap via two hosted nodes + getAllPeers assertions; outbound/violation via raw non-reading libp2p-host fixture (public APIs) + oversized-publish config determinism; sweep via config-tiny heartbeat_interval_msec. Conscious deviation from SC5's "(mock scheduler)" parenthetical documented in CONTEXT D-11; libp2p pin gets marker-only probes (INTG-02-compliant); MUST-verify Windows build with SuperGenius pubsub_counts-style host as fallback.

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, supplementary | Repeat D-07 WSL ASan run — stream close-during-pending-writes and violation-callback dispatch are lifetime-adjacent. | ✓ |
| No, Windows only | Bounds logic is counter/flag logic, less UAF-prone than Phase 2. | |

**User's choice:** Yes, supplementary
**Notes:** None.

---

## the agent's Discretion

- Per-peer subscription counting placement (incremental in PeerContext vs computed in RemoteSubscriptions)
- K and K_close defaults; sweep/heartbeat interaction details
- Violation callback exact signature/payload
- writing_bytes_/pending_bytes_ accounting shape at the cap check
- Branch names (cut from 28f6a629 / b6eb6268)
- Test file naming/placement in ipfs-pubsub; raw-peer fixture design (public libp2p APIs only)
- Gater-observability seam for asserting the block reached the gater

## Deferred Ideas

- Two-lane outbound queue (v2 QUER-01)
- TTL auto-unblock / decay graylist (v2 PSCG-02)
- Behavior-based peer scoring (v2 PSCG-01)
- Per-RPC parser cap + queue-length knob (rejected for D-01 minimalism)
- LRU topic eviction / hard total-table cap (superseded by cap+GC composition)
- Idle stream recycling, CRDT-burst-aware tuning (v2 QUER-02/03)
