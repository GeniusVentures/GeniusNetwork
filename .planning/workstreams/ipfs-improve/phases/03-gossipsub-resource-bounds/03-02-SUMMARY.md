---
phase: 03-gossipsub-resource-bounds
plan: 02
subsystem: infra
tags: [libp2p, gossipsub, resource-bounds, remote-subscriptions, pubsub, testing, asan]

# Dependency graph
requires:
  - phase: 03-gossipsub-resource-bounds/03-01
    provides: Egress admission spine + ViolationHandler seam + BlockPeer escalation + raw-fixture tracer precedent + pre-drafted boundary test pair
provides:
  - RemoteSubscriptions::onPeerSubscribed per-peer subscription cap (GOSS-01, D-03) using max_remote_subscriptions_per_peer from 03-01's Config
  - GOSS-01 composition marker over the existing heartbeat GC sweep (D-04 — zero new sweep code)
  - TEST-02(a) SubscribeCapBoundsRemoteSubscriptions + TEST-02(c) SweepCollectsTopicAfterUnsubscribeAndResubscribeRelearns
  - Committed boundary pair BelowCapAdmittedAboveCapDroppedAtEntry / BlockedPeerRedialRejected (pre-drafted during 03-01)
  - Phase 3 closing evidence: two-look Windows full-suite parity + WSL ASan clean run + deferred-items ledger
affects: [04 repin verification, libp2p fork maintenance (deferred item 1), TEST-02 fixture hardening (deferred items 2-3)]

actuals:
  tokens: 4500   # chars/4 over committed diff (libp2p +37/-3; ipfs-pubsub +347/-3)
  tasks: 2
  commits: 2     # libp2p a54f5c4; ipfs-pubsub 5c6653c

tech-stack:
  added: []
  patterns:
    - "Receiver-side bound as check-then-insert admission on the std::set itself (dedup early-return precedes cap check; the set size IS the counter — no drift)"
    - "Bound-by-composition: cap prevents entry, existing heartbeat GC collects never-populated entries — no new sweep path"

key-files:
  created: []
  modified:
    - thirdparty/libp2p/src/protocol/gossip/impl/remote_subscriptions.hpp  # GOSS-01/D-04 composition marker where the TODO stood
    - thirdparty/libp2p/src/protocol/gossip/impl/remote_subscriptions.cpp  # cap check at onPeerSubscribed + warn log (peer, topic, count, cap)
    - thirdparty/ipfs-pubsub/test/src/gossip_pubsub_bounds_test.cpp        # +TEST-02(a)/(c) cases; committed the 03-01 pre-drafted boundary pair

key-decisions:
  - "D-03 check-then-insert: dedup early-return first (re-subscribing an admitted topic never consumes headroom), then cap check with warn log, then the existing insert — cap+1-th topic ignored with NO table mutation"
  - "D-04 sweep-by-composition: onHeartbeat/TopicSubscriptions::empty byte-identical to 28f6a629 (verified: 0 diff lines touch onHeartbeat); capped-out flooder's topics never populate and are collected by the existing GC"
  - "D-12 ASan evidence route: WSL ASan full suite minus BlockedPeerRedialRejected (16 ran, 15 passed, 1 pre-existing failure, 0 sanitizer findings) — the excluded case trips a PRE-EXISTING upstream assert (upgrader_session.cpp:88, Linux Debug abort vs Windows continue), recorded as deferred item 1, never a silent skip"

patterns-established:
  - "Receiver-side admission on set-membership state: the authoritative count is the container itself; duplicates are idempotent at every boundary"
  - "Deferred-items ledger for out-of-scope discoveries in files a phase's prohibitions forbid touching"

requirements-completed: [GOSS-01, GOSS-04, TEST-02]

coverage:
  - id: D1
    description: "GOSS-01 remote subscription cap — peer's already-admitted set below max_remote_subscriptions_per_peer admits; cap+1-th topic ignored, no table mutation; duplicates never gain or spend headroom"
    requirement: GOSS-01
    verification:
      - kind: integration
        ref: thirdparty/ipfs-pubsub/test/src/gossip_pubsub_bounds_test.cpp#GossipPubSubBoundsTest.SubscribeCapBoundsRemoteSubscriptions
        status: pass
    human_judgment: false
  - id: D2
    description: "GOSS-01 sweep-by-composition — existing heartbeat GC collects dead entries; re-subscription after collection re-learns (liveness)"
    requirement: GOSS-01
    verification:
      - kind: integration
        ref: thirdparty/ipfs-pubsub/test/src/gossip_pubsub_bounds_test.cpp#GossipPubSubBoundsTest.SweepCollectsTopicAfterUnsubscribeAndResubscribeRelearns
        status: pass
    human_judgment: false
  - id: D3
    description: "GOSS-04 ingress observability — cap rejection logs warn with peer, topic, admitted count, cap; no silent rejection path"
    requirement: GOSS-04
    verification:
      - kind: integration
        ref: thirdparty/libp2p/src/protocol/gossip/impl/remote_subscriptions.cpp#GOSS-01-warn-log (source-asserted backstop; exercised by SubscribeCapBoundsRemoteSubscriptions)
        status: pass
    human_judgment: false
  - id: D4
    description: "TEST-02 full evidence set — Windows full suite 17 ran / 16 passed / exactly 1 pre-existing failure / 1 disabled across consecutive runs; WSL ASan clean (0 findings)"
    requirement: TEST-02
    verification:
      - kind: integration
        ref: command: ipfs-pubsub-test.exe (full suite, Windows) + asan_run.log/asan_bounds5.log (WSL ASan, BlockedPeerRedialRejected excluded per deferred item 1)
        status: pass
    human_judgment: false

duration: ~50min
completed: 2026-10-13
status: complete
---

# Phase 03 Plan 02: GossipSub Inbound Bounds Summary

**Inbound half of GossipSub resource bounds landed as a minimal check-then-insert cap on the remote subscription table (zero new sweep code — composition with the existing heartbeat GC), closing Phase 3's evidence set: 5 bounds cases green on Windows, WSL ASan clean, branches linear and unpushed.**

## Performance

- **Duration:** ~50 min
- **Completed:** 2026-10-13
- **Tasks:** 2/2
- **Files modified:** 3

## Accomplishments
- Bounded `RemoteSubscriptions::onPeerSubscribed` with `config_.max_remote_subscriptions_per_peer` (GOSS-01/D-03): dedup early-return → cap check with warn log (peer, topic, admitted count, cap) → existing insert; entries beyond the cap are ignored with no table mutation, and the set size itself is the counter (no parallel counter to drift).
- Documented sweep-by-composition (D-04): the GOSS-01 marker replaces the stale in-file TODO; `onHeartbeat` and `TopicSubscriptions::empty` are byte-identical to 28f6a629 (verified — 0 diff lines touch onHeartbeat).
- Added TEST-02(a) `SubscribeCapBoundsRemoteSubscriptions` (cap-th admitted, cap+1-th ignored, duplicate re-subscribe idempotent) and TEST-02(c) `SweepCollectsTopicAfterUnsubscribeAndResubscribeRelearns` (subscribe → learn → unsubscribe → sweep-collect → re-subscribe → re-learn); committed the boundary pair pre-drafted during 03-01.
- Recorded 3 non-blocking deferred discoveries in `deferred-items.md` (upstream upgrader assert on Linux Debug; shared raw-fixture teardown hardening; post-summary process exit-hang) — all pre-existing, all in files this phase's prohibitions forbid touching.

## Task Commits

1. **Task 1: libp2p inbound cap** — `a54f5c4` on `dev_gossip_bounds` (feat)
2. **Task 2: TEST-02(a)/(c) cases + boundary pair** — `5c6653c` on `dev_ipfs_fix` (test)

**Plan metadata:** this SUMMARY (docs)

## Verification Evidence

- **Windows full suite (final state):** 17 ran / **16 passed / exactly 1 failed (MutipleGossipSubObjectsOnSingleChannel, pre-existing, untouched) / 1 disabled** — all 5 `GossipPubSubBoundsTest` cases OK. (Plan's must-have itemized 11 pre-existing + 3 (03-01) + 2 (03-02) = 16 passing; the literal "14" in the plan text is an arithmetic slip — itemization and reality agree at 16.)
- **D-12 WSL ASan:** full suite minus `BlockedPeerRedialRejected`: 16 ran / 15 passed / 1 pre-existing failure / **0 AddressSanitizer findings**. The excluded case trips `assert(close_res)` at `upgrader_session.cpp:88` — a PRE-EXISTING upstream assert (Linux Debug aborts; Windows logs and continues), documented as deferred item 1, never a silent skip.
- **Backstops:** GOSS-01 markers greppable at both submodule HEADs; `onHeartbeat` untouched; branches linear and unpushed (libp2p `dev_gossip_bounds` = 2 commits from 28f6a629; ipfs-pubsub `dev_ipfs_fix` = 3 commits from b6eb6268); `thirdparty/ipfs-bitswap-cpp` unmoved at f899393.

## Files Created/Modified
- See `key-files` frontmatter — 3 files exactly as planned.

## Decisions Made
None beyond plan-locked decisions D-03/D-04/D-12 — followed plan as specified.

## Deviations from Plan
None in production scope. Process deviation (same as 03-01): the executor session ended after task commits and green verification but before SUMMARY/root close-out; the orchestrator reconciled artifacts (commits verified, full suite re-run green on the final committed state) and closed out manually.

## Issues Encountered
Three pre-existing, out-of-scope discoveries — fully documented in `deferred-items.md` with suggested owners (libp2p fork maintenance; TEST-02 fixture hardening). None block Phase 3; none were touched (phase prohibitions).

## User Setup Required
None.

## Next Phase Readiness
- Phase 3 evidence set is complete: GOSS-01..04 + TEST-02 markers at both submodule HEADs, Windows suite parity, ASan clean.
- Phase 4 (Repin & Cross-Repo Verification) can proceed: content-probe markers = the GOSS-*/BSTP-*/TEST-02 comment anchors greppable at libp2p HEAD (a54f5c4), ipfs-pubsub HEAD (5c6653c), ipfs-bitswap-cpp (f899393); branches remain local-only for the repin.
- Deferred items 1–3 should be triaged into fork-maintenance backlog (suggested: a libp2p-fork workstream).

---
*Phase: 03-gossipsub-resource-bounds*
*Completed: 2026-10-13*
