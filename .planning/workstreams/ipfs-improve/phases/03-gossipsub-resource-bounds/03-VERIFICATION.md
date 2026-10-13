---
phase: 03-gossipsub-resource-bounds
verified: 2026-10-13T20:05:00Z
status: passed
score: 10/10 must-haves verified
covered_files:
  - .planning/workstreams/ipfs-improve/phases/03-gossipsub-resource-bounds/03-01-PLAN.md
  - .planning/workstreams/ipfs-improve/phases/03-gossipsub-resource-bounds/03-02-PLAN.md
  - .planning/workstreams/ipfs-improve/phases/03-gossipsub-resource-bounds/03-01-SUMMARY.md
  - .planning/workstreams/ipfs-improve/phases/03-gossipsub-resource-bounds/03-02-SUMMARY.md
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
covered_digest: "v2:sha256:6646d7c32f284fa3c2723ae49a40bdcd5d39b104550343662fcaa5ce6a4d19d7"
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: none
---

# Phase 3: GossipSub Resource Bounds Verification Report

**Phase Goal:** GossipSub's remote-driven state (per-peer subscription table, outbound pending bytes) is bounded with additive `Gossip::Config` knobs, drop-not-buffer policy, full observability, and escalation through the existing `BlockPeer()` path
**Verified:** 2026-10-13T20:05:00Z
**Status:** passed → **VERDICT: VERIFIED**
**Re-verification:** No — initial verification (no prior VERIFICATION.md in the phase directory)

## Goal Achievement

Verification stance: goal-backward, adversarial. Every SUMMARY claim was re-checked against the ACTUAL committed code — `git -C <submodule> diff/show/grep` at libp2p `dev_gossip_bounds` HEAD `a54f5c4` (2 commits, linear from `28f6a629`, unpushed) and ipfs-pubsub `dev_ipfs_fix` HEAD `5c6653c` (3 commits, linear from `b6eb6268`, unpushed) — plus a fresh live run of all 5 `GossipPubSubBoundsTest` cases on the Windows harness. Working-tree parity with HEAD confirmed for all gossip files in both submodules (committed code = tested code).

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | **GOSS-01 cap:** `RemoteSubscriptions::onPeerSubscribed` enforces the receiver-side cumulative per-peer cap — dedup early-return first, then cap check reading `config_.max_remote_subscriptions_per_peer` BEFORE any table mutation, then the existing insert as final admission; cap+1-th topic ignored with no mutation | ✓ VERIFIED | Committed diff read at `a54f5c4`: original `insert().second` replaced by `count()` dedup check → `if (peer->subscribed_to.size() >= config_.max_remote_subscriptions_per_peer) { warn; return; }` → `insert(topic)`. Exactly check-then-insert per D-03. Behavioral: `SubscribeCapBoundsRemoteSubscriptions` PASS live (cap=3; T1..T3 learned via `getAllPeers`, T4 stays empty) |
| 2 | **GOSS-01 precision:** the `std::set<TopicId>` size IS the count — no parallel counter; duplicates are exact set-membership hits that never gain or spend headroom | ✓ VERIFIED | Code: no counter member added anywhere in the diff; dedup precedes the cap check. Behavioral: test re-subscribes T1 three times → A's view unchanged (PASS live) |
| 3 | **GOSS-01 sweep (D-04):** existing heartbeat GC is the sweep — `onHeartbeat`/`TopicSubscriptions::empty` untouched, GOSS-01 composition marker replaces the stale TODO, capped-out flooder's topics never populate and are collected | ✓ VERIFIED | `git diff 28f6a62..HEAD -- remote_subscriptions.cpp` contains ZERO code changes to `onHeartbeat`/`empty` (only match is an added comment line "stay empty()…"). `remote_subscriptions.hpp` diff: `TODO(artem): bound table size… LRU(???)` replaced by the GOSS-01 cap+sweep marker. Behavioral: `SweepCollectsTopicAfterUnsubscribeAndResubscribeRelearns` PASS live (sweep collects, re-subscribe re-learns — liveness proven) |
| 4 | **GOSS-02 admission contract:** `Stream::write()` drops the arriving RPC exactly when `pending_bytes_ + buffer->size() > max_pending_bytes_` (strict-greater — exact-on-cap admitted); drop-new-only (queued buffers never evicted); defaults (`1 << 24`) never drop a legitimate large CRDT RPC | ✓ VERIFIED | Committed `stream.cpp` diff read: `if (pending_bytes_ + buffer->size() > max_pending_bytes_)` — strict `>`, matches backstop truth verbatim; drop branch returns without touching `pending_buffers_`. Config default `max_pending_bytes_per_stream = 1 << 24` mirrors `max_message_size` (D-02/D-07). Behavioral: `BelowCapAdmittedAboveCapDroppedAtEntry` PASS live |
| 5 | **GOSS-02 accounting + K-drops close:** `pending_bytes_` counts queued bytes only (plain size_t); `consecutive_overflow_drops_` resets ONLY on full queue drain (`onMessageWritten` else-branch); K-th drop posts `Error::PENDING_OVERFLOW` via strong-self-capture scheduler post and closes the stream through the existing feedback funnel | ✓ VERIFIED | Code: reset is the sole `else` branch after the pending-pop loop (queue empty ⇒ drain); `asyncPostViolation()` captures `shared_from_this()`, does NOT gate on `closed_` (comment documents why it is distinct from `asyncPostError`); `Error::PENDING_OVERFLOW` enum + category case landed additively in `common.hpp/.cpp`. Behavioral: `SustainedOverflowClosesStreamAndBlocksPeer` PASS live — the close fires under heartbeat-paced (interleaved) traffic, proving the counter does not reset spuriously |
| 6 | **GOSS-03 escalation:** ViolationHandler fires from `Connectivity::onStreamEvent` AFTER `banOrForget`; GossipPubSub's mutex-guarded per-peer close counter invokes the existing `BlockPeer()` chain on the 2nd sustained-overflow close (first tolerated); block persists until `UnblockPeer()`; `deny_list_connection_gater.hpp` byte-identical — no new policy machinery | ✓ VERIFIED | Committed diffs read: `connectivity.cpp` — `banOrForget(from);` THEN `if (violation_handler_ && event.error() == Error::PENDING_OVERFLOW) violation_handler_(…)`. `gossip_core.cpp` forwards handler in `start()`. `gossip_pubsub.cpp` — handler registered immediately after gossip create (strictly before `Start()`), `++m_sustainedOverflowCloses[peerId]` under `m_sustained_overflow_mutex`, `BlockPeer(peerId)` at `closes >= kSustainedOverflowClosesToBlock` (constexpr = 2, D-09). Gater diff 28f6a62..HEAD: **empty** (byte-identical). Behavioral: tracer asserts `IsPeerBlocked == false` after close 1, `== true` after close 2; `BlockedPeerRedialRejected` PASS live (post-block dial rejected, block persists) |
| 7 | **GOSS-04 observability:** every enforcement event logs — egress drop warns with peer, incoming bytes, pending bytes, cap (new `Stream` `SubLogger` wired at BOTH construction sites); ingress cap rejection warns with peer, topic, admitted count, cap; block logs via existing `BlockPeer` info line; no silent enforcement path | ✓ VERIFIED | Committed diffs read: `stream.cpp` warn names all five values incl. `consecutive_drops`; `remote_subscriptions.cpp` warn names peer/topic/count/cap; `connectivity.cpp` passes `log_` at both `make_shared<Stream>` sites (L217/L341 regions). Both are the ONLY new enforcement returns and both log before returning |
| 8 | **TEST-02:** all 5 bound-enforcement cases pass deterministically — cap enforced per peer, outbound cap drops at threshold (not buffers, not disconnects), sustained overflow closes the stream, violations reach peer-block escalation | ✓ VERIFIED | Live re-run this verification: `--gtest_filter=GossipPubSubBoundsTest.*` → **5/5 PASSED** (14.2 s total). Orchestrator's two consecutive full-suite runs: 17 ran / 16 passed / exactly 1 pre-existing failure / 1 disabled, 5/5 bounds cases OK. ASan (D-12): `asan_run.log` 16 ran / 15 passed / 1 pre-existing failure / **0 AddressSanitizer findings**; `asan_bounds5.log` documents the excluded `BlockedPeerRedialRejected` upstream assert at `upgrader_session.cpp:88` (deferred item 1 — pre-existing, Windows passes). Note: SC5's "(mock scheduler)" wording was superseded by the plan-locked D-11 documented deviation (entry-point checks + bounded idempotent waits, no `scheduler_mock.hpp` — grep confirms 0 uses); determinism substance verified |
| 9 | **Compatibility + baseline:** defaults preserve existing behavior (additive Config fields, additive enum, additive pure-virtual); suite keeps exactly one pre-existing failure (`MutipleGossipSubObjectsOnSingleChannel` — untouched, still failing) + 1 disabled; branches linear and never pushed | ✓ VERIFIED | `gossip.hpp` diff purely additive (3 knobs + enum + typedef + setter); no existing behavior touched under defaults. Full-suite failure set identical to pre-phase (orchestrator runs + ASan log: the failure is present and is THE only one). `git branch -r` → no `origin/dev_gossip_bounds`, no `origin/dev_ipfs_fix`; `git log` linear from `28f6a62` / `b6eb6268` |
| 10 | **Scope confinement:** exactly the planned files changed; no edits to ipfs-bitswap-cpp; no gitlink bumps in thirdparty/GeniusNetwork; no protobuf-header or libp2p build-tree include from tests; violation callback never invoked inline from `write()` | ✓ VERIFIED | `diff --stat` vs bases: libp2p 11 gossip files (+170/−11), ipfs-pubsub 4 files (+849) — exactly the plan's `files_modified` union, nothing else. ipfs-bitswap-cpp HEAD `f899393` on `dev_timer_correctness` (unmoved); its dirty files (`bitswap.cpp/hpp`, race test) are the PRE-EXISTING pre-phase-3 local revert (orchestrator-verified; phase-3 commits touch only libp2p/ipfs-pubsub). Test-file include scan: no `gossip.pb`/`pb.hh`/`libp2p/build`/`scheduler_mock` (0 matches each); `asyncPostViolation` posts through the scheduler, never inline |

**Score:** 10/10 truths verified (0 present-behavior-unverified)

### Prohibition Checks (all automated)

| Prohibition | Evidence | Result |
|---|---|---|
| Drop-new-only, no eviction of queued buffers | Drop branch returns before any queue access | ✓ HELD |
| Exactly 3 Config knobs, no byte-level second threshold | gossip.hpp diff adds exactly 3 knobs; K-counter IS the higher threshold | ✓ HELD |
| No TTL auto-unblock / decay / scoring / graylist | No such code in any committed diff; block persists (test asserts) | ✓ HELD |
| `deny_list_connection_gater.hpp` byte-identical | `git diff` vs base: empty | ✓ HELD |
| No silent drops | Both enforcement sites warn before returning; block logs via existing line | ✓ HELD |
| Violation callback never inline from `write()` | `asyncPostViolation` = scheduler post with strong self-capture | ✓ HELD |
| No generated-protobuf / build-tree includes in tests | grep: 0 matches | ✓ HELD |
| Never pushed, never rebased; no gitlink bumps | No remote branches; linear logs; GeniusNetwork tree pins untouched by phase commits | ✓ HELD |
| No edits to ipfs-bitswap-cpp | Phase commits confined to libp2p/ipfs-pubsub; bitswap dirty tree is the pre-existing revert | ✓ HELD |
| `MutipleGossipSubObjectsOnSingleChannel` never fixed/skipped/weakened | Still the sole failure in every suite run incl. ASan log | ✓ HELD |
| No mock-scheduler stepping | `scheduler_mock` grep: 0 | ✓ HELD |
| Gater escalation asserted via `IsPeerBlocked`, not connection death | Test lines 542/557/740/777/785/803 assert `IsPeerBlocked` + redial rejection | ✓ HELD |
| No burst-then-count / unbounded waits | All loops bounded (`max_iters`, fixed caps — lines 463/482/626/730) | ✓ HELD |

### Required Artifacts

| Artifact | Status | Details |
|---|---|---|
| `libp2p …/gossip/gossip.hpp` (Config knobs + ViolationType + handler) | ✓ VERIFIED | Committed at `a54f5c4`; additive; defaults 1024 / 1<<24 / 8 |
| `libp2p …/impl/stream.{hpp,cpp}` (admission + K-drops + SubLogger) | ✓ VERIFIED | Strict `>` check, drain-only reset, dedicated violation post; TODO replaced by GOSS-02 marker |
| `libp2p …/impl/connectivity.{hpp,cpp}` (emission after banOrForget) | ✓ VERIFIED | Handler storage + emission; `log_` at both Stream sites |
| `libp2p …/impl/gossip_core.{hpp,cpp}` (setViolationHandler) | ✓ VERIFIED | Stored, forwarded to Connectivity in `start()` |
| `libp2p …/impl/common.{hpp,cpp}` (PENDING_OVERFLOW) | ✓ VERIFIED | Enum value + category case, additive |
| `libp2p …/impl/remote_subscriptions.{hpp,cpp}` (cap + marker) | ✓ VERIFIED | Check-then-insert; onHeartbeat/empty untouched; TODO replaced |
| `ipfs-pubsub …/gossip_pubsub.{hpp,cpp}` (counter + BlockPeer) | ✓ VERIFIED | Mutex-guarded map, k=2, existing BlockPeer chain |
| `ipfs-pubsub …/gossip_pubsub_bounds_test.cpp` (5 cases) | ✓ VERIFIED | 806 lines, 5 TEST_F cases, registered in CMakeLists; 5/5 pass live |
| Branch state (libp2p +2 linear, ipfs-pubsub +3 linear, unpushed) | ✓ VERIFIED | Confirmed via log/branch -r |

### Key Link Verification

| From → To | Via | Status |
|---|---|---|
| `Config.max_pending_bytes_per_stream` → Stream ctor → admission check → K-th drop post → `onStreamEvent` → handler → counter → `BlockPeer` → deny-set → `IsPeerBlocked` | Full chain read in committed diffs; tracer exercises it end-to-end (close 1 tolerated, close 2 blocked, redial rejected) | ✓ WIRED |
| `GossipPubSub::InitHostFromInjector`: handler registered after gossip create, before `Start()` | Committed `gossip_pubsub.cpp` — registration site precedes DHT/Start sequence; `GossipCore::start()` forwards | ✓ WIRED |
| `Config.max_remote_subscriptions_per_peer` → `RemoteSubscriptions` cap → empty topics → heartbeat GC | Committed diff + sweep/liveness test PASS | ✓ WIRED |
| Submodule public `Subscribe()` → wire RPC → `onPeerSubscribed` (choke point) → `getAllPeers` | Subscribe-cap + sweep tests assert through this surface | ✓ WIRED |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| All 5 TEST-02 bound cases | `ipfs-pubsub-test.exe --gtest_filter=GossipPubSubBoundsTest.*` (this verification) | 5/5 PASSED (14.2 s) | ✓ PASS |
| Full-suite baseline (orchestrator, 2 consecutive runs) | full `ipfs-pubsub-test.exe` | 17 ran / 16 passed / 1 pre-existing failure / 1 disabled, identical both runs | ✓ PASS |
| D-12 WSL ASan | `asan_run.log` / `asan_bounds5.log` in phase dir | 16 ran / 15 passed / 1 pre-existing failure / 0 ASan findings; excluded case's upstream assert documented (deferred item 1) | ✓ PASS |
| Phase 1 race-suite regression (rebuilt vs new libp2p) | Orchestrator-executed | 7/7 PASSED | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
|---|---|---|---|
| GOSS-01 | 03-02 | ✓ SATISFIED | Truths 1–3: cap code at `a54f5c4`, marker, sweep composition, 2 tests PASS live |
| GOSS-02 | 03-01 | ✓ SATISFIED | Truths 4–5: admission + K-drops close, 2 tests PASS live |
| GOSS-03 | 03-01 | ✓ SATISFIED | Truth 6: full escalation chain through existing BlockPeer, gater byte-identical |
| GOSS-04 | 03-01 + 03-02 | ✓ SATISFIED | Truth 7: warn logs at both enforcement sites, no silent path |
| TEST-02 | 03-01 + 03-02 | ✓ SATISFIED | Truth 8: 5/5 cases live + double-run Windows + ASan clean |

No orphaned requirements — REQUIREMENTS.md maps exactly GOSS-01..04 + TEST-02 to Phase 3, all claimed by plans and satisfied.

### Anti-Patterns Found

None in phase-modified files. The swept diffs contain no TBD/FIXME/XXX (the two swept TODOs — stream pending bound, table bound — were *replaced* by implemented bounds and their markers, which is the goal, not debt). No stub returns, no console-only paths, no hardcoded empties.

### Human Verification Required

None — all evidence is automated (live test re-run this verification, committed-diff reads, grep checks, ASan logs).

### Regression Notes (non-blocking)

1. **Phase 2 bitswap regression suite currently unrunnable** — a PRE-EXISTING uncommitted local revert in `thirdparty/ipfs-bitswap-cpp` (`dev_timer_correctness` @ `f899393`, dirty: `bitswap.cpp/hpp`, race test) removes Phase 2's 6 additional cases. Orchestrator-verified pre-phase-3; Phase 3 committed nothing to that submodule; those cases exercise bitswap callback semantics, not gossip/libp2p. **Not a Phase 3 gap** — Phase 2's VERIFICATION passed at the committed state `f899393`; restoring/repinning the bitswap tree is Phase 4's declared work (ROADMAP Phase 4 SC1/SC2).
2. **Advisory — open review findings (03-REVIEW-DISPOSITION.md, all `open`)**: MAJ-01 (per-peer close-counter map never evicted — Sybil pinning / post-unblock single-close re-block) is a legitimate follow-up candidate before Phase 4 repin; MIN-01/02, INF-01/02 are documented. None are D-09/D-10-locked plan violations; the constant and map are additive and test-observable.
3. **Deferred items 1–3** (`deferred-items.md`): upstream `upgrader_session.cpp:88` assert (Linux Debug only — reason `BlockedPeerRedialRejected` was excluded from ASan, passes on Windows), raw-fixture teardown hardening, post-summary exit-hang. All pre-existing, all in files prohibitions forbid touching; correctly routed to fork-maintenance backlog.
4. **SC5 wording deviation (accepted):** "mock scheduler" in ROADMAP SC5 was superseded by plan-locked D-11 (documented deviation: entry-point checks + bounded idempotent waits). The observable substance — deterministic passing tests — is verified; noted for the record, not a gap.

### Gaps Summary

None. All 10 merged must-have truths (ROADMAP SCs 1–5 × plan frontmatter detail) verified against committed code with behavioral evidence; all 13 prohibitions held under automated checks; requirements GOSS-01..04 + TEST-02 all satisfied; branches linear, unpushed, correctly scoped for Phase 4's content-probed repin.

---

_Verified: 2026-10-13T20:05:00Z_
_Verifier: the agent (gsd-verifier)_
