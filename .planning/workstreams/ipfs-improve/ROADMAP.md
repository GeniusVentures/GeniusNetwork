# Roadmap: IPFS P0 Remediation

## Overview

Milestone v1.0 closes the two non-CI P0 findings from the `gnus_libp2p_comparison.md` audit on the GNUS C++ libp2p/IPFS fork. The journey: first port the timer-correctness pattern already proven in-file (`ContentRequestContext` C-5) to `BitswapRequestContext` so canceled timers stop manufacturing false timeouts; then port the reentrancy pattern (C-7) so consumer callbacks leave every internal mutex before dispatch — with the four race-ordering regression tests as the observable definition of "closed". In parallel-by-nature but sequenced third, bound GossipSub's remote-driven state (per-peer subscription table, outbound pending bytes) with additive `Gossip::Config` knobs, drop-not-buffer policy, full observability, and escalation through the existing `BlockPeer()` path. Finally, repin `thirdparty` with content-probed verification and prove the fixes survive integration through the SuperGenius focus suites and a clean GeniusSDK build.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Bitswap Timer Correctness** - Canceled timers never fire the failure path; each request yields exactly one terminal result (completed 2026-10-12)
- [x] **Phase 2: Bitswap Callback Reentrancy** - Callbacks dispatched outside all mutexes; full race-ordering regression suite green (completed 2026-10-13)
- [x] **Phase 3: GossipSub Resource Bounds** - Per-peer subscription table and outbound queue bounded, observable, with existing-path escalation (completed 2026-10-13)
- [ ] **Phase 4: Repin & Cross-Repo Verification** - Content-probed thirdparty pin bumps proven through SuperGenius focus suites and GeniusSDK build

## Phase Details

### Phase 1: Bitswap Timer Correctness

**Goal**: A canceled Bitswap request timer is treated as canceled, never as a timeout, and every block request produces exactly one terminal result
**Depends on**: Nothing (first phase)
**Requirements**: BSTP-01, BSTP-02, BSTP-03
**Success Criteria** (what must be TRUE):
  1. A canceled Bitswap request timer never fires the failure path — the `async_wait` handler checks its `error_code` and returns on `operation_aborted` (explicit `.cancel()`, never `expires_at(pos_infin)`)
  2. Every block request yields exactly one terminal result — a completion flag checked under the mutex makes success and timeout mutually exclusive, even when an already-dequeued genuinely-expired handler fires late with success after a cancel
  3. Consumer-initiated cancellation and success produce no error callback; only a genuine timeout produces exactly one failure callback (`REQUEST_TIMEOUT`-class)
  4. Race tests for the timer orderings (cancel-vs-expiry in both orders, response-then-canceled-timer-fires, timeout-then-late-response) pass deterministically on a single-threaded `io_context` with injected timeouts and no sleeps — establishing the harness Phase 2 extends

**Plans**: 1/1 plans complete
Plans:
- [x] 01-01-PLAN.md — Disk-space gate (W: vs C: build tree), tracer: fix branch from `d2ec18af` + full C-5/C-7 port + first race ordering green through the verified Windows harness; expansion: remaining orderings + consumer `Cancel()` + regression + content-probe self-check

### Phase 2: Bitswap Callback Reentrancy

**Goal**: Consumer callbacks are safe to call from — Bitswap never invokes them under an internal mutex, so re-entrant consumers cannot deadlock the protocol
**Depends on**: Phase 1 (completion-flag semantics and the deterministic test harness carry forward)
**Requirements**: BSTP-04, BSTP-05, TEST-01
**Success Criteria** (what must be TRUE):
  1. Consumer callbacks are invoked only after every internal Bitswap mutex is released — state is mutated under lock (callbacks moved out, request marked complete, erased from the request map) with exactly one winner, and dispatch happens after unlock
  2. A consumer callback may synchronously re-enter Bitswap — cancel its own request or chain new requests — without deadlock or use-after-free (context kept alive via `shared_from_this()` during dispatch)
  3. A callback registered on an already-completed request receives the terminal result immediately (or fails fast) — no fresh timer is armed on a completed request
  4. The full race-ordering regression suite exists and passes: cancel raced with expiry (both orders), response-then-canceled-timer-fires (no failure after success), timeout-then-late-response (no double callback), and reentrant callback canceling its own request without deadlock

**Plans**: 1/1 plans complete
Plans:
- [x] 02-01-PLAN.md — Tracer: the three BSTP-04 seams (terminal-result replay store in AddCallback per D-01/D-02, registration hoisted outside the outer lock with find-or-replace per D-04, map-erase deleted so the completion flag selects the winner) proven by the late-registration replay case + server-client regression; expansion: five reentrancy/replay/cancel-drop race cases completing TEST-01 at 13 deterministic cases; WSL ASan supplementary run (D-07) + content probes + scope-confinement evidence

### Phase 3: GossipSub Resource Bounds

**Goal**: A remote peer can no longer grow unbounded state in the local GossipSub node — subscriptions and outbound queue bytes are capped, drops are visible, and persistent violators are blocked
**Depends on**: Nothing (technically independent of Phases 1–2 — different submodule; sequenced third because its design decisions need resolution during planning)
**Requirements**: GOSS-01, GOSS-02, GOSS-03, GOSS-04, TEST-02
**Success Criteria** (what must be TRUE):
  1. The per-peer remote subscription table is bounded — subscribe entries beyond the `Gossip::Config` cap in an RPC are ignored, and the heartbeat sweep prunes only entries no live subscriber depends on, never state required by Graft/Prune/IHAVE
  2. Outbound per-peer pending bytes are capped at `write()` entry via a `Gossip::Config` knob — on cap hit the RPC is dropped (logged, not silently buffered), and overflow sustained beyond the distinct higher threshold closes the slow stream
  3. A peer that persistently violates bounds is escalated through the existing `DenyListConnectionGater::BlockPeer()` path — no new policy machinery
  4. Every bound-enforcement event is observable — logged with peer, topic/count, and bytes via the existing `log::SubLogger`; there are no silent drops
  5. Bound-enforcement tests pass deterministically (mock scheduler): subscription cap enforced per peer, outbound cap drops at the configured threshold (not buffers, not disconnects), sustained overflow closes the stream, and violations reach the peer-block escalation path

**Plans**: 2/2 plans complete
Plans:
**Wave 1**
- [x] 03-01-PLAN.md — Tracer: outbound-bound spine end-to-end (3 Config knobs per D-01/D-02, Stream::write admission + K-drops close per D-05..D-07 through the existing error funnel, setViolationHandler seam per D-08, 2nd-close BlockPeer escalation per D-09/D-10) + TEST-02(b) raw-fixture cases (SustainedOverflowClosesStreamAndBlocksPeer, egress boundary pair); expansion: blocked-redial + below/above-cap boundary cases

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 03-02-PLAN.md — GOSS-01 receiver-side per-peer subscription cap (check-then-insert in onPeerSubscribed per D-03) + D-04 sweep composition marker + TEST-02(a)/(c) (subscribe-cap boundary/duplicates, sweep/liveness); phase evidence: D-12 WSL ASan run, double-run determinism, GOSS-01..04/TEST-02 content probes, branch/scope confinement

### Phase 4: Repin & Cross-Repo Verification

**Goal**: The fixes verifiably reach the integrated tree — pinned by content, not by branch name — and the consuming repos build and pass against them
**Depends on**: Phases 1, 2, 3 (all fixes must land before repin and rebuild)
**Requirements**: INTG-01, INTG-02, INTG-03
**Success Criteria** (what must be TRUE):
  1. Every fix lands on and is verified against the actual integrated submodule SHAs — branches cut from ipfs-bitswap-cpp `d2ec18af`, libp2p `28f6a629`, and ipfs-pubsub `b6eb6268` as needed — not branch tips
  2. The `thirdparty` pins are updated with content-probed verification — fix markers confirmed present at each pinned commit (e.g., by grep), never trusted by branch name
  3. SuperGenius focus suites pass on the repinned tree — the CRDT/PubSub, DAG-syncer, and AccountMessenger paths that consume bitswap/gossip
  4. GeniusSDK builds and links cleanly against the repinned tree (build-only; no source change expected)

**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 (Phase 3 is technically parallelizable with 1–2; Phase 4 requires all three)

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Bitswap Timer Correctness | 1/1 | Complete    | 2026-10-12 |
| 2. Bitswap Callback Reentrancy | 1/1 | Complete    | 2026-10-13 |
| 3. GossipSub Resource Bounds | 2/2 | Complete    | 2026-10-13 |
| 4. Repin & Cross-Repo Verification | 0/? | Not started | - |
