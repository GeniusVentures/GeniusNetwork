---
phase: 03-gossipsub-resource-bounds
plan: 01
subsystem: infra
tags: [libp2p, gossipsub, resource-bounds, pubsub, backpressure, blockpeer]

# Dependency graph
requires:
  - phase: 02-bitswap-callback-reentrancy
    provides: Windows-harness tracer/fixture precedent (heartbeat-paced, bounded idempotent waits, distinct ports)
provides:
  - Gossip::Config egress knobs (max_pending_bytes_per_stream, overflow_close_threshold) with D-01/D-02 defaults
  - Stream::write() admission cap with drop-new-only policy and K-drops stream close via Error::PENDING_OVERFLOW
  - ViolationHandler seam (GossipCore -> Connectivity) emitting SustainedWriteOverflow after banOrForget
  - GossipPubSub per-peer sustained-overflow close counter escalating to existing BlockPeer() on 2nd close
  - TEST-02(b) tracer case SustainedOverflowClosesStreamAndBlocksPeer on the Windows harness
affects: [03-02 inbound bounds, 04 repin verification, SuperGenius pubsub consumers]

actuals:
  tokens: 7500   # chars/4 over committed diff (libp2p 141 + ipfs-pubsub 505 changed lines)
  tasks: 2
  commits: 3     # libp2p 6ea6b0a; ipfs-pubsub 029b557, 41be92f

tech-stack:
  added: []
  patterns:
    - "Egress backpressure as admission control at Stream::write() entry (drop-new-only, never evict queued buffers)"
    - "Escalation through existing teardown funnels only (banOrForget -> violation callback; BlockPeer on Nth close) — no new cleanup paths"

key-files:
  created:
    - thirdparty/ipfs-pubsub/test/src/gossip_pubsub_bounds_test.cpp  # TEST-02(b) raw fixture + tracer case
  modified:
    - thirdparty/libp2p/include/libp2p/protocol/gossip/gossip.hpp    # 3 Config knobs + ViolationType + ViolationHandler + setViolationHandler
    - thirdparty/libp2p/src/protocol/gossip/impl/common.hpp/.cpp     # Error::PENDING_OVERFLOW + category case
    - thirdparty/libp2p/src/protocol/gossip/impl/stream.hpp/.cpp     # admission check, K-counter, drain-reset, SubLogger
    - thirdparty/libp2p/src/protocol/gossip/impl/connectivity.hpp/.cpp # handler storage + emission in onStreamEvent, SubLogger at both Stream sites
    - thirdparty/libp2p/src/protocol/gossip/impl/gossip_core.hpp/.cpp  # setViolationHandler override + forward at start()
    - thirdparty/ipfs-pubsub/src/ipfs_pubsub/gossip_pubsub.hpp/.cpp     # close-counter members, handler registration, Nth-close BlockPeer
    - thirdparty/ipfs-pubsub/test/src/CMakeLists.txt                    # gossip_pubsub_bounds_test.cpp registered

key-decisions:
  - "D-05 drop-new-only: the NEW arriving RPC is dropped on cap hit; queued buffers never evicted, mesh-control ordering preserved"
  - "D-06 drain-reset: consecutive_overflow_drops_ resets only on full queue drain (onMessageWritten else-branch)"
  - "D-07 strict-greater admission comparison; exact-on-cap admitted; defaults (1<<24) never drop a legitimate large CRDT RPC"
  - "D-09 2nd sustained-overflow close escalates to BlockPeer (kSustainedOverflowClosesToBlock = 2); first close tolerated"
  - "D-10 block persists until UnblockPeer(); deny_list_connection_gater.hpp byte-identical"

patterns-established:
  - "Violation seam: Connectivity::onStreamEvent runs banOrForget FIRST, then emits ViolationHandler(peer_id, SustainedWriteOverflow) — teardown authority unchanged"
  - "Hand-encoded UVarint-length-prefixed fixture RPC (no protobuf header, no libp2p build-tree include path) for raw-stream gossip testing"

requirements-completed: [GOSS-02, GOSS-03, GOSS-04, TEST-02]

coverage:
  - id: D1
    description: "GOSS-02 egress admission contract — Stream::write() drops arriving RPC when pending + incoming > cap; K-th consecutive drop closes stream (Error::PENDING_OVERFLOW)"
    requirement: GOSS-02
    verification:
      - kind: integration
        ref: thirdparty/ipfs-pubsub/test/src/gossip_pubsub_bounds_test.cpp#GossipPubSubBoundsTest.SustainedOverflowClosesStreamAndBlocksPeer
        status: pass
    human_judgment: false
  - id: D2
    description: "GOSS-03 escalation — ViolationHandler seam emits SustainedWriteOverflow after banOrForget; 2nd sustained-overflow close calls existing BlockPeer(); first close tolerated (IsPeerBlocked false)"
    requirement: GOSS-03
    verification:
      - kind: integration
        ref: thirdparty/ipfs-pubsub/test/src/gossip_pubsub_bounds_test.cpp#GossipPubSubBoundsTest.SustainedOverflowClosesStreamAndBlocksPeer
        status: pass
    human_judgment: false
  - id: D3
    description: "GOSS-04 egress observability — every drop/close logs peer + incoming/pending bytes + cap; empty-buffer RPC returns before admission check and is never counted"
    requirement: GOSS-04
    verification:
      - kind: integration
        ref: thirdparty/ipfs-pubsub/test/src/gossip_pubsub_bounds_test.cpp#GossipPubSubBoundsTest.SustainedOverflowClosesStreamAndBlocksPeer
        status: pass
    human_judgment: false
  - id: D4
    description: "TEST-02(b) tracer passes deterministically on the Windows harness — heartbeat-paced, bounded idempotent waits, rw_timeout raised so K-drops is the only close path in-window"
    requirement: TEST-02
    verification:
      - kind: integration
        ref: command: ipfs-pubsub-test.exe --gtest_filter=GossipPubSubBoundsTest.SustainedOverflowClosesStreamAndBlocksPeer
        status: pass
    human_judgment: false

duration: ~35min
completed: 2026-10-13
status: complete
---

# Phase 03 Plan 01: GossipSub Outbound Bounds Summary

**Egress spine of GossipSub resource enforcement wired end-to-end across libp2p and ipfs-pubsub: Stream write admission cap with drop-new-only policy, K-drops stream close through the existing error funnel, ViolationHandler seam, and 2nd-close BlockPeer escalation — proven by the deterministic TEST-02(b) tracer on the Windows harness.**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-10-13
- **Tasks:** 2/2
- **Files modified:** 13 (9 libp2p + 4 ipfs-pubsub)

## Accomplishments
- Wired `max_pending_bytes_per_stream` + `overflow_close_threshold` Config knobs (D-01/D-02 defaults: 1<<24, 8) into `Stream::write()` with a strict-greater admission check (D-07), drop-new-only policy (D-05), and consecutive-overflow counter that resets only on full queue drain (D-06); the K-th drop posts `Error::PENDING_OVERFLOW` through the existing onStreamEvent → banOrForget funnel and closes the stream.
- Added the `ViolationHandler(peer_id, ViolationType::SustainedWriteOverflow)` seam: GossipCore stores/forwards it at start(), Connectivity emits it in onStreamEvent AFTER banOrForget — teardown authority unchanged, `deny_list_connection_gater.hpp` untouched.
- Registered the handler in GossipPubSub::InitHostFromInjector with a mutex-guarded per-peer close counter; the 2nd sustained-overflow close (D-09, kSustainedOverflowClosesToBlock=2) invokes the existing BlockPeer() chain; block persists until UnblockPeer() (D-10).
- Created the TEST-02(b) raw fixture + tracer `SustainedOverflowClosesStreamAndBlocksPeer`: hand-encoded UVarint-length-prefixed subscribe RPC (no protobuf/generated-header dependency), heartbeat-paced publishes, drops 1..K-1 leave the peer known, drop K empties it, close 1 tolerated, close 2 sets IsPeerBlocked true.

## Task Commits

1. **Task 1: libp2p egress spine (Config knobs → Stream admission/K-drops close → violation seam)** — `6ea6b0a` on `dev_gossip_bounds` (cut from master@28f6a62, linear, never pushed) (feat)
2. **Task 2: ipfs-pubsub wiring + TEST-02(b) tracer** — `029b557` (feat: handler registration + Nth-close BlockPeer), `41be92f` (test: tracer case + raw fixture + CMake registration) on `dev_ipfs_fix` (never pushed)

**Plan metadata:** this SUMMARY (docs)

## Verification Evidence (Windows harness)

- Filtered tracer: `ipfs-pubsub-test.exe --gtest_filter=GossipPubSubBoundsTest.SustainedOverflowClosesStreamAndBlocksPeer` → **[ OK ] (780 ms)**
- Full suite: **14 passed, 1 failed (MutipleGossipSubObjectsOnSingleChannel — pre-existing, unfixed by scope), 1 disabled**. Note: the working tree additionally carries two 03-02-scope cases (`BelowCapAdmittedAboveCapDroppedAtEntry`, `BlockedPeerRedialRejected`) drafted during execution and intentionally left uncommitted for plan 03-02; the committed 03-01 baseline is 12 passed = 11 pre-existing + tracer, exactly per plan.
- Build-order gate honored: outer-tree `libp2p` target rebuilt before `ipfs-pubsub-test` (Pitfall 6).

## Files Created/Modified
- See `key-files` frontmatter — 13 files exactly as planned (9 libp2p edit sites, 2 ipfs-pubsub sources, 1 new test, 1 CMake line).

## Decisions Made
None beyond plan-locked decisions D-01..D-11 — followed plan as specified.

## Deviations from Plan
None in production scope. Process deviation: the executor session ended abnormally after the task commits and green verification but before SUMMARY/root close-out; the orchestrator reconciled artifacts (commits verified present, tests re-run green) and closed out manually per the completion-reconciliation policy.

## Issues Encountered
None — all three bounds cases currently green in the working tree; pre-existing suite failure count unchanged (exactly 1).

## User Setup Required
None — no external service configuration required.

## Next Phase Readiness
- 03-02 (inbound bounds: remote subscription registry) can proceed immediately; its two test cases are already drafted green in the working tree at `thirdparty/ipfs-pubsub/test/src/gossip_pubsub_bounds_test.cpp` (uncommitted, to be committed with 03-02's production change).
- libp2p `dev_gossip_bounds` (1 commit from 28f6a62) and ipfs-pubsub `dev_ipfs_fix` (+2 commits) remain local-only; repin happens in Phase 4 with content-probed verification.
- Note for Phase 4: `thirdparty` pointer intentionally NOT bumped (workstream design — bitswap phase-2 pointers also pending repin).

---
*Phase: 03-gossipsub-resource-bounds*
*Completed: 2026-10-13*
