# Phase 3: GossipSub Resource Bounds - Context

**Gathered:** 2026-10-13
**Status:** Ready for planning

<domain>
## Phase Boundary

A remote peer can no longer grow unbounded state in the local GossipSub node — per-peer remote subscriptions and outbound per-peer pending bytes are capped via additive `Gossip::Config` knobs, cap hits drop visibly (never silently buffer), sustained overflow closes the slow stream, and persistent violators escalate through ipfs-pubsub's existing `DenyListConnectionGater::BlockPeer()` path. Requirements: GOSS-01, GOSS-02, GOSS-03, GOSS-04, TEST-02.

This is a **two-submodule phase**: enforcement internals land in libp2p (branch cut from `28f6a629` — per-peer subscription cap in `RemoteSubscriptions`, `write()`-entry byte cap + K-consecutive-drops close in `Stream`, violation callback on `Gossip`); escalation wiring + tests land in ipfs-pubsub (branch cut from `b6eb6268` — `GossipPubSub` registers the handler calling `BlockPeer()`, TEST-02 suite). Both branches feed Phase 4's content-probed pin chain, never pushed.

Out of scope: peer scoring / graylisting (v2 PSCG-01/02), two-lane outbound queue (v2 QUER-01), idle stream recycling (QUER-02), burst-aware tuning (QUER-03), GossipSub 1.1 / signed peer records.

**Carry-forward from Phases 1–2 (locked — do not re-litigate):**
- Fix branches cut from integrated SHAs, single linear chain, never pushed (Phase 4 content-probes them)
- Greppable content-probe marker style for fix verification
- Deterministic test discipline — with one documented deviation for this phase (see D-11): determinism comes from entry-point checks and idempotent waits, not mock-scheduler stepping
- WSL ASan as supplementary evidence only; Windows suite is primary (D-07 pattern)
- Observability via existing `log::SubLogger` with peer/topic/count/bytes (SC4) — details agent discretion

</domain>

<decisions>
## Implementation Decisions

### Config surface (GOSS-01/02)
- **D-01:** Minimal 3-knob set in `Gossip::Config` — `max_remote_subscriptions_per_peer`, `max_pending_bytes_per_stream`, and the overflow-close threshold (K consecutive drops). Exactly what GOSS-01/02 name; further knobs (per-RPC subscribe-entry cap, queue-length cap) can be added later without breakage since additive config fields carry defaults. — **Reversibility:** reversible — additive struct fields with defaults; existing SuperGenius/GeniusSDK builds unchanged.
- **D-02:** `max_pending_bytes_per_stream` default = `max_message_size` (16 MiB) — a single legitimate RPC (large CRDT broadcast) never trips the cap; only queued backlog beyond one in-flight message does. — **Reversibility:** reversible — default value choice.

### Subscription bound (GOSS-01)
- **D-03:** Receiver-side cumulative cap — `RemoteSubscriptions::onPeerSubscribed` checks the peer's counted topic count; entries beyond the cap are ignored and logged (GOSS-04). One choke point; bounds drip-flooding across many small RPCs (a parser-side per-RPC cap cannot see cumulative state and would need a 4th knob — rejected by D-01). Per-peer counting placement (incremental in `PeerContext` vs computed in `RemoteSubscriptions`) is agent discretion. — **Reversibility:** reversible — internal bookkeeping.
- **D-04:** Heartbeat sweep = GC empty topics — the sweep removes table entries with zero counted remote subscribers that we are not locally subscribed to and that carry no mesh/graft state. Composes with D-03 into a full table bound: a flooder's ignored subscriptions never populate topics, so excess topics stay empty and get collected. Trivially never evicts state a live remote subscriber depends on (SC1's Graft/Prune/IHAVE clause). The in-file TODO's LRU idea and a hard total-table ceiling were considered and rejected as unneeded given cap+sweep composition. — **Reversibility:** reversible — sweep policy internal to `RemoteSubscriptions`.

### Outbound bound (GOSS-02)
- **D-05:** Drop-new-only at `write()` entry — when `pending_bytes_` cannot admit the arriving RPC, that RPC is dropped and logged; queued buffers are never evicted and order is preserved. Exactly GOSS-02's wording ("the RPC is dropped (logged, not silently buffered)"); avoids mesh-control-message reordering and does not creep toward the v2-deferred two-lane queue. — **Reversibility:** reversible — drop policy in `Stream`.
- **D-06:** Sustained overflow = K consecutive cap-hit drops with no intervening full drain → close the stream. Counter resets on drain; K default (~8) left to research/discretion. Note: once drops fire at entry, `pending_bytes_` cannot grow past the cap, so a byte-level "higher threshold" is unreachable by construction — K defines SC2's "distinct higher threshold" instead. — **Reversibility:** reversible — counter + threshold.
- **D-07:** Cap check semantics: the entry check is `pending_bytes_ + incoming > cap` (admission control), so an RPC larger than the cap alone is dropped deterministically at entry — this is also what makes the TEST-02 outbound tests deterministic (D-12). `writing_bytes_`/`pending_bytes_` accounting details are agent discretion. — **Reversibility:** reversible.

### Escalation wiring (GOSS-03)
- **D-08:** Violation callback seam — libp2p `Gossip` grows a setter (e.g. `setViolationHandler(fn(peer_id, violation_type))`); ipfs-pubsub's `GossipPubSub` registers a handler that calls `m_connection_gater->BlockPeer()`. Explicit, unit-testable in both repos, minimal API surface. (Extending the internal `Stream::Feedback` chain and a counters+poll design were rejected — feedback is internal plumbing that still needs a new external surface; polling is laggy.) Exact callback signature/payload is agent discretion. — **Reversibility:** reversible — additive setter, no existing-signature change.
- **D-09:** Escalation criterion = Nth sustained-overflow stream close — a peer whose outbound stream was closed for sustained overflow `K_close` times (default 2–3, research/discretion) is blocked. Catches reconnect-and-reoffend while tolerating one legitimately-slow episode (e.g. one large CRDT burst). — **Reversibility:** reversible.
- **D-10:** Block is permanent until `UnblockPeer()` — existing `DenyListConnectionGater` semantics, zero new policy machinery (GOSS-03 verbatim). TTL auto-unblock is v2's PSCG-02 and stays deferred. — **Reversibility:** reversible — no new machinery to unwind.

### TEST-02 harness
- **D-11:** All TEST-02 tests live in **ipfs-pubsub's own suite** (`thirdparty/ipfs-pubsub/test/src/`, extending `gossip_pubsub_test.cpp` patterns) — operator preference: ipfs-pubsub is "our" code, while libp2p's own test build is documented broken (audit: CI failing on Python environment setup; deferred-items report: outdated mocks and test-build problems). Determinism comes from config, not mock scheduler: (a) subscribe-cap test = two hosted `GossipPubSub` nodes, B subscribes to `cap+1` topics via public `Subscribe()`, assert A's table bounded via `getAllPeers()` on excess topics — zero timing; (b) outbound cap/K-drops/close/violation test = a small raw libp2p-host fixture (public libp2p APIs only: negotiate `/meshsub`, subscribe, then never read) with test config making each serialized publish exceed `max_pending_bytes_per_stream`, so every `write()` entry check fails deterministically (D-07) — K writes → K drops → close → violation; (c) heartbeat sweep = `heartbeat_interval_msec` set tiny in test config + short idempotent waits. **This is a conscious, documented deviation from SC5's "(mock scheduler)" parenthetical and from the Phase 1–2 no-sleeps discipline — no sleep-dependent orderings exist here (drops are entry-point checks; the sweep is idempotent).** Consequence: the libp2p pinned commit carries code-marker probes only (INTG-02 explicitly allows grep markers — roadmap-compliant, weaker than Phases 1–2's co-located tests). Research MUST verify ipfs-pubsub's suite actually builds and runs on Windows in this workspace; documented fallback = a SuperGenius `pubsub_counts`-style host (`SuperGenius/test/src/pubsub_counts/pubsub_counts.cpp` pattern, Windows-proven in this workspace). — **Reversibility:** reversible — test placement only.
- **D-12:** Repeat the Phase 2 D-07 WSL ASan supplementary run for the new suite — stream close-during-pending-writes and violation-callback dispatch are lifetime-adjacent (`shared_from_this` during close). Windows deterministic suite remains primary evidence; WSL ASan supplementary. Same WSL constraints: `~/gnus/GeniusNetwork/thirdparty`, no git inside WSL, file-copy sync, every git operation on the Windows side. — **Reversibility:** reversible — evidence-only.

### the agent's Discretion
- Per-peer subscription counting placement (incremental counter in `PeerContext` vs computed in `RemoteSubscriptions`)
- K (consecutive drops to close) and `K_close` (closes to block) defaults; sweep/heartbeat interaction details
- Violation callback exact signature and payload (peer id + violation type at minimum)
- `writing_bytes_`/`pending_bytes_` accounting shape at the cap check
- Branch names for the libp2p and ipfs-pubsub fix branches (cut from `28f6a629` / `b6eb6268`; Phase 4 records final pins by content probe)
- Test file naming/placement within ipfs-pubsub's suite; raw-peer fixture design (as long as public libp2p APIs only)
- Gater-observability seam for asserting the block reached `DenyListConnectionGater` (research verifies whether an existing query path exists or the close/callback outcome is the assertion point)

### Folded Todos
None — the single todo match (Vulkan capability-probe deadlock, score 0.2, keyword "path") was a spurious match reviewed in Phases 1–2 and here; left for its natural owner.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream planning artifacts
- `.planning/workstreams/ipfs-improve/REQUIREMENTS.md` — GOSS-01..04, TEST-02 definitions (the WHAT); v2 deferrals (PSCG-01/02, QUER-01..03) that bound this phase's policy ambition
- `.planning/workstreams/ipfs-improve/ROADMAP.md` §Phase Details → Phase 3 — success criteria SC1–SC5
- `.planning/workstreams/ipfs-improve/STATE.md` — pinned SHAs (libp2p `28f6a629`, ipfs-pubsub `b6eb6268`) and the four flagged design blockers this context resolves

### Audit origin
- `.planning/research/gnus_libp2p_comparison.md` §PubSub and GossipSub — the P0 finding: "unfinished bounds for remote subscription tables and outbound buffered messages"; links to the two in-file TODOs; §Testing and CI — libp2p CI failing on Python setup (grounds D-11)

### Source of truth — libp2p (enforcement internals)
- `thirdparty/libp2p/include/libp2p/protocol/gossip/gossip.hpp` — `Config` struct (D-01 knob insertion point; `max_message_size = 1<<24`, `heartbeat_interval_msec`, `ban_interval_msec` precedents); `Gossip` interface (D-08 setter insertion point)
- `thirdparty/libp2p/src/protocol/gossip/impl/remote_subscriptions.hpp` — topic→subscribers table, the in-file bound TODO (L75-77), `onPeerSubscribed` (D-03 choke point), `onHeartbeat` (D-04 sweep)
- `thirdparty/libp2p/src/protocol/gossip/impl/stream.hpp` — `pending_buffers_` deque, unbounded `pending_bytes_` with in-file TODO (L64-70), `write()` (D-05/D-06/D-07 enforcement point), `Feedback` (rejected seam)
- `thirdparty/libp2p/src/protocol/gossip/impl/message_parser.cpp` — RPC ingress (subscribe/IHAVE/IWANT/graft/prune loops) — context for why parser-side capping was rejected

### Source of truth — ipfs-pubsub (escalation + tests)
- `thirdparty/ipfs-pubsub/src/ipfs_pubsub/gossip_pubsub.cpp` / `.hpp` — `BlockPeer()`/`UnblockPeer()` (L237-252), `m_connection_gater` (D-08 registration site)
- `thirdparty/ipfs-pubsub/src/ipfs_pubsub/deny_list_connection_gater.hpp` — `BlockPeer()` semantics (D-10)
- `thirdparty/ipfs-pubsub/test/src/gossip_pubsub_test.cpp`, `gossip_pubsub_topic_test.cpp`, `test/CMakeLists.txt` — D-11 test home; MUST-verify Windows build

### Test wiring
- `SuperGenius/test/src/pubsub_counts/pubsub_counts.cpp` — D-11 fallback host pattern; Windows-proven multi-node `GossipPubSub` + gater-blocking test in this workspace
- `.planning/codebase/TESTING.md` — verification convention: build/test inside the existing `build/<Platform>/<Config>` tree
- `.planning/workstreams/ipfs-improve/phases/02-bitswap-callback-reentrancy/02-CONTEXT.md` §D-07 — the WSL ASan recipe Phase 3 repeats (constraints: no git in WSL, file-copy sync, Windows-side git)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- ipfs-pubsub test suite + `GossipPubSub` hosted-node pattern — proven in-workspace way to run multiple pubsub nodes in-process (per memory: multiple instances do NOT alias; distinct peer IDs assertable)
- SuperGenius `pubsub_counts` suite — 4-node pnet/gater integration test incl. gater-blocked node, Windows-proven (fallback harness + gater-blocking precedent)
- `scheduler_mock.hpp` (`thirdparty/libp2p/test/mock/libp2p/basic/`) — exists but deliberately unused per D-11
- Phase 1–2 WSL ASan recipe (D-07) — sync/toolchain mechanics reusable verbatim for D-12

### Established Patterns
- Additive `Gossip::Config` fields with defaults — existing consumers unchanged (compatibility constraint); new knobs follow `max_message_size`/`heartbeat_interval_msec` style
- Single enforcement choke points: `onPeerSubscribed` (ingress state) and `Stream::write()` (egress bytes) — both already single-door functions, no fan-out
- Content-probe markers greppable at pinned commits (Phase 4 INTG-02); libp2p gets code markers only this phase (D-11 consequence)

### Integration Points
- `Gossip::setViolationHandler` (new) ↔ `GossipPubSub`'s existing `m_connection_gater` wiring — the one cross-repo seam (D-08)
- `Stream` close path already reaches `Feedback` events upward — violation emission hooks the close site
- `onHeartbeat` already runs per `heartbeat_interval_msec` — sweep piggybacks existing cadence; tests shrink the interval via config
- Phase 4 pin chain: two new branches (libp2p, ipfs-pubsub) cut from `28f6a629`/`b6eb6268`, never pushed, content-probed by marker

</code_context>

<specifics>
## Specific Ideas

- Operator's repo preference (verbatim intent): ipfs-pubsub is "our" code; libp2p "contains a lot of weird setups and python stuff" — prefer ipfs-pubsub for anything placable there (drove D-11)
- TEST-02 outbound test shape: config cap < serialized publish size so the D-07 entry check fails every time — K publishes with no reads → exactly K drops → close (deterministic, no interleaving dependence)
- A single legit CRDT-sized RPC must never be dropped under default config (D-02 rationale); drops under defaults imply genuine multi-message backlog
- Escalation must tolerate one legitimately-slow episode before blocking (D-09 rationale — same large-CRDT-burst scenario)

</specifics>

<deferred>
## Deferred Ideas

- **Two-lane outbound queue** (urgent control lane, Go `UrgentPush` parity) — v2 QUER-01; D-05's drop-new-only deliberately avoids creeping toward it
- **TTL auto-unblock / decay graylist** — v2 PSCG-02 (`ban_interval_msec` precedent); D-10 keeps blocks permanent to honor "no new policy machinery"
- **Behavior-based peer scoring** — v2 PSCG-01; D-09's simple Nth-close criterion deliberately avoids it
- **Per-RPC subscribe-entry parser cap + queue-length cap knobs** — rejected for D-01 minimalism; additive later if needed
- **LRU topic-table eviction / hard total-table cap** — superseded by D-03+D-04 composition; revisit only if coordinated many-peer topic floods become real
- **Idle stream recycling, CRDT-burst-aware tuning** — v2 QUER-02/03

### Reviewed Todos (not folded)
- "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" (`.planning/todos/2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md`) — matched only on keyword "path" (score 0.2); unrelated to GossipSub; reviewed in Phases 1–2 and here; left for its natural owner.

</deferred>

---

*Phase: 3-GossipSub Resource Bounds*
*Context gathered: 2026-10-13*
