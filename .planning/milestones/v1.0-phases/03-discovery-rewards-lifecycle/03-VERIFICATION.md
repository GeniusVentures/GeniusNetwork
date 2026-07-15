---
phase: 03-discovery-rewards-lifecycle
verified: 2026-07-13T22:00:00Z
status: passed
score: 11/11 must-haves verified
overrides_applied: 0
---

# Phase 3: Discovery, Rewards & Lifecycle — Verification Report

**Phase Goal:** "Phase 3: Discovery, Rewards & Lifecycle — Design main-wallet discovery/monitoring, per-child reward policy, and lifecycle/change flows."
**Verified:** 2026-07-13
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### ROADMAP Success Criteria

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| SC-1 | Design doc specifies main-wallet discovery of registered children, per-child information displayed, and actions (fund, recover, inspect, revoke/detach), traceable to DISC-01..03 | ✓ VERIFIED | `docs/03-01-discovery-monitoring.md` §2 (push), §3 (poll), §4 (per-child info table), §6 (5 actions mapped to Phase 2/3 mechanics), §7 (traceability table) |
| SC-2 | Design doc specifies per-child reward policy resolution for standalone and registered children, hold-time policy pinning, and authenticated dev-wallet/split updates, reusing escrow, traceable to RWD-01..03 | ✓ VERIFIED | `docs/03-02-reward-policy-lifecycle.md` §2 (dual-source resolution), §3 (EscrowTransaction immutability), §4 (child-only updates), §12 (traceability table) |
| SC-3 | Design doc specifies lifecycle state machine and replace/remove/detach flows with "supersedes seq N" linkage and deterministic conflict resolution, traceable to LIFE-01, LIFE-02, LIFE-04 | ✓ VERIFIED | `docs/03-02-reward-policy-lifecycle.md` §6 (4-state machine + transitions), §7 (detach), §8 (revoke), §9 (replace main + supersedes + nonce chain), §12 (traceability table) |
| SC-4 | Main-replacement policy fork (require existing-main consent vs child-only) is decided and documented with rationale, traceable to LIFE-03 | ✓ VERIFIED | `docs/03-02-reward-policy-lifecycle.md` §9.2 (child-only replacement, deadlock-avoidance rationale, rejected alternatives) |

### Observable Truths (from PLAN frontmatter)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Developer can trace how a main wallet discovers registered children via push-primary (pubsub CID on main topic) and poll-fallback (AccountMessenger ChildDiscoveryRequest/Response) | ✓ VERIFIED | 03-01 §2 §3 — end-to-end push flow (7 steps), poll path with AccountMessenger extension, proto arms 10/11, handler methods following HandleNonceRequest pattern |
| 2 | Developer can identify every per-child data source: reg/ CRDT for metadata, child CRDT deltas for balance/UTXO/activity, local JSON cache for display prefs — no new CRDT namespace | ✓ VERIFIED | 03-01 §4.1 — 13-row display field → data source mapping table with concrete anchors |
| 3 | Developer can map each main-wallet action (fund, recover, inspect, revoke, detach) to its Phase 2 consensus rule or lifecycle mechanic with concrete file:line anchors | ✓ VERIFIED | 03-01 §6.1-6.5 — all 5 actions with gate-by-gate validation flows + §6.6 summary table |
| 4 | Developer can verify that discovery responses are validated: CID content-addressed resolution + certified-status check (D-26), never trusted on pubsub topic membership alone | ✓ VERIFIED | 03-01 §2.1 (steps 5-6), §3.3.2 (certified filter in HandleChildDiscoveryRequest) |
| 5 | Developer can determine the reward policy source for any child wallet: DevConfig_st (standalone) or RegistrationMetadata.dev_wallet/peers_cut from certified reg/{child_addr} (registered) | ✓ VERIFIED | 03-02 §1.1, §2.1-2.3 — dual-source selection with certified-status gate |
| 6 | Developer can verify that reward policy is pinned at HoldEscrow time via EscrowTransaction immutability — PayEscrow reads stored values, not live CRDT — and this is existing behavior requiring zero design changes | ✓ VERIFIED | 03-02 §3 — immutability chain documented with EscrowTransaction.hpp:122-131 + TransactionManager.cpp:846-875 anchors, explicit "Zero Phase 3 changes" |
| 7 | Developer can trace how the child updates its reward policy: new RegistrationTx at higher sequence with updated RegistrationMetadata — child-signed only, no main co-signature (D-33) | ✓ VERIFIED | 03-02 §4 — update flow, trust model table, sequence ordering, conflict scenario |
| 8 | Developer can identify all 4 lifecycle states (Unregistered/Registered/Detached/Revoked) and every valid transition with the initiating actor and mechanism | ✓ VERIFIED | 03-02 §6 — state definitions with CRDT conditions, 5-transition table, ASCII state machine diagram |
| 9 | Developer can verify that competing lifecycle updates are resolved deterministically: supersedes_sequence filter gate rejects mismatches, and the sgns.nonce.v1 nonce chain ensures first-to-consensus wins | ✓ VERIFIED | 03-02 §9.3 — gate 3b pseudocode + nonce chain explanation, "NOT first-to-CRDT-wins" statement |
| 10 | Developer knows that main replacement is child-only (no old-main consent, D-37), revoke is the only main-signed lifecycle action (D-36), and detach/revoke leaves child as valid standalone wallet (D-39) | ✓ VERIFIED | 03-02 §9.2 (child-only replacement + deadlock rationale), §8 (revoke main-signed), §10 (standalone validity) |
| 11 | Developer can locate every anchor point by file path + line number | ✓ VERIFIED | Verified against real SuperGenius source: Consensus.hpp:37 (NONCE_SUBJECT_TYPE), EscrowTransaction.hpp:129-131 (dev_addr_/peers_cut_/amount_), TransactionManager.cpp:778 (HoldEscrow) — all match |

**Score:** 11/11 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|----------|
| `docs/03-01-discovery-monitoring.md` | Complete discovery & monitoring design, ≥350 lines, 8 sections | ✓ VERIFIED | 627 lines, 8 sections, all required patterns present |
| `docs/03-02-reward-policy-lifecycle.md` | Complete reward policy & lifecycle design, ≥450 lines, 13 sections | ✓ VERIFIED | 707 lines, 13 sections, all required patterns present |

### Key Link Verification

| From | To | Via | Status |
|------|----|-----|--------|
| 03-01 §3 Poll Path | AccountMessenger.hpp:199-223, SGAccountComm.proto (arms 10/11) | ChildDiscoveryRequest/Response proto extension | ✓ VERIFIED |
| 03-01 §4 Per-Child Info | SGTransaction.proto RegistrationTx, reg/{child_addr} CRDT | RegistrationMetadata fields via 01-01-SUMMARY.md | ✓ VERIFIED |
| 03-01 §6 Main-Wallet Actions | TransactionManager.cpp:4234-4304, Phase 2 docs | ValidateTransactionForConsensus pipeline | ✓ VERIFIED |
| 03-02 §2 Reward Policy | GeniusNode.cpp:1977-1985, TransactionManager.cpp:778-810 | Policy-source selection at GeniusNode level | ✓ VERIFIED |
| 03-02 §3 Hold-Time Pinning | EscrowTransaction.hpp:122-131, TransactionManager.cpp:846-875 | EscrowTransaction immutability chain | ✓ VERIFIED |
| 03-02 §6 Lifecycle | Phase 2 reg/ CRDT, SGTransaction.proto RegistrationTx | State derived from CRDT fields | ✓ VERIFIED |
| 03-02 §9 Supersedes | TransactionManager.cpp:2984-3039, Consensus.hpp:37 | FilterRegistration gate 3b + nonce chain | ✓ VERIFIED |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| DISC-01 | 03-01-PLAN | How main wallet discovers all child wallets registered to it | ✓ SATISFIED | 03-01 §2 (push), §3 (poll) |
| DISC-02 | 03-01-PLAN | Per-child information displayed (balance, assets, game, publisher, etc.) | ✓ SATISFIED | 03-01 §4.1 (13-field table) |
| DISC-03 | 03-01-PLAN | Main-wallet actions over discovered children (fund, recover, inspect, revoke/detach) | ✓ SATISFIED | 03-01 §6.1-6.5, §6.6 summary |
| RWD-01 | 03-02-PLAN | Per-child processing-reward policy resolution for standalone and registered children | ✓ SATISFIED | 03-02 §2 |
| RWD-02 | 03-02-PLAN | Pinning reward policy at escrow-hold time | ✓ SATISFIED | 03-02 §3 |
| RWD-03 | 03-02-PLAN | Authenticated update rules for dev wallet and cut ratio | ✓ SATISFIED | 03-02 §4 |
| LIFE-01 | 03-02-PLAN | Child-wallet lifecycle state machine and valid transitions | ✓ SATISFIED | 03-02 §6 (states), §7 (detach), §8 (revoke) |
| LIFE-02 | 03-02-PLAN | Replace/remove-main flows with "supersedes sequence N" linkage and conflict resolution | ✓ SATISFIED | 03-02 §7, §8, §9 (supersedes + nonce chain) |
| LIFE-03 | 03-02-PLAN | Main-replacement policy fork decision with rationale | ✓ SATISFIED | 03-02 §9.2 (child-only, deadlock rationale, rejected alternatives) |
| LIFE-04 | 03-02-PLAN | Detach leaves child as valid standalone wallet | ✓ SATISFIED | 03-02 §10 (unaffected/changes tables + 4 design invariants) |

**Coverage:** 10/10 requirements satisfied
**Orphaned requirements:** None

### Context Decisions Honored

| Decision | Description | Documented In |
|----------|-------------|---------------|
| D-27 | Push-primary/poll-fallback, local JSON cache, no new CRDT namespace | 03-01 §1, §2, §3, §5 |
| D-28 | Three-source per-child info (reg/ CRDT, child deltas, local cache) | 03-01 §4 |
| D-29 | 5 actions mapped to Phase 2/3 mechanics | 03-01 §6 |
| D-30 | Standalone: DevConfig_st at HoldEscrow | 03-02 §1.1, §2.3 |
| D-31 | Registered: RegistrationMetadata supersedes DevConfig for new escrows | 03-02 §1.1, §2.1 |
| D-32 | Hold-time pinning via EscrowTransaction immutability (existing) | 03-02 §3 |
| D-33 | Policy updates child-only via RegistrationTx at higher sequence | 03-02 §4 |
| D-34 | 4 states (no pending/closed), all transitions | 03-02 §6 |
| D-35 | Detach: child-initiated RegistrationTx with detach_flag | 03-02 §7 |
| D-36 | Revoke: main-initiated consensus transaction | 03-02 §8 |
| D-37 | Main replacement: child-only, no old-main consent | 03-02 §9.2 |
| D-38 | Supersedes sequence + nonce chain for deterministic ordering | 03-02 §9.3 |
| D-39 | Detach/revoke leaves child as valid standalone wallet | 03-02 §10 |

**All 13 decisions honored.** No deferred idea leaked.

### Proto Field Numbers Verified

| File | Message/Oneof | Field | Value | Document |
|------|--------------|-------|-------|----------|
| SGAccountComm.proto | AccountMessage.payload | child_discovery_request | 10 | 03-01 §3.2 |
| SGAccountComm.proto | AccountMessage.payload | child_discovery_response | 11 | 03-01 §3.2 |
| SGTransaction.proto | RegistrationTx | detach_flag | 5 | 03-02 §11.1 |
| SGTransaction.proto | RegistrationTx | supersedes_sequence | 6 | 03-02 §11.1 |
| SGTransaction.proto | RevokeTx (new) | dag_struct | 1 | 03-02 §11.2 |
| SGTransaction.proto | RevokeTx (new) | child_address | 2 | 03-02 §11.2 |
| SGTransaction.proto | RevokeTx (new) | registration_sequence | 3 | 03-02 §11.2 |
| Consensus.proto | EmbeddedTransaction | revoke | 9 | 03-02 §11.3 |

### Open Questions Resolved

| # | Question | Resolution | Evidence |
|---|----------|------------|----------|
| 1 | RegistrationTx schema reference path | Uses `01-01-SUMMARY.md` for RegistrationMetadata fields (not stale `docs/registration-protocol.md`) | Both docs reference `01-01-SUMMARY.md` for RegistrationMetadata; 03-01 references `docs/registration-protocol.md` only for general RegistrationTx creation (§2.3) — acceptable per PLAN scope |
| 2 | GlobalDB prefix-scan capability for reg/ iteration | Prefix scan preferred, full CRDT iteration fallback — acceptable for sparse reg/ records | 03-01 §3.4 |
| 3 | RevokeTx: first-class subclass vs flagged transfer | First-class `RevokeTx` as new `GeniusTransaction` subclass recommended, NOT a flagged transfer | 03-01 §6.4, 03-02 §8.1 |

### Source Anchor Verification

Key anchor points verified against actual SuperGenius submodule source:

| Anchor | Document Claim | Source Match |
|--------|---------------|-------------|
| `Consensus.hpp:37` | `NONCE_SUBJECT_TYPE = "sgns.nonce.v1"` | ✓ Line 37: `static constexpr std::string_view NONCE_SUBJECT_TYPE = "sgns.nonce.v1";` |
| `EscrowTransaction.hpp:129-131` | `amount_`, `dev_addr_`, `peers_cut_` member variables | ✓ Lines 129-131: `uint64_t amount_;`, `std::string dev_addr_;`, `uint64_t peers_cut_;` |
| `TransactionManager.cpp:778` | `HoldEscrow` entry point | ✓ Line 778: `outcome::result<std::pair<std::string, EscrowDataPair>> TransactionManager::HoldEscrow(` |
| `AccountMessenger.hpp` | File exists | ✓ |
| `SGAccountComm.proto` | File exists | ✓ |
| `SGTransaction.proto` | File exists | ✓ |
| `Consensus.proto` | File exists | ✓ |
| `pubsub_broadcaster_ext.hpp` | File exists | ✓ |
| `globaldb.hpp` | File exists | ✓ |

### Anti-Patterns Found

None. Both documents are design documentation (markdown), not code. No TBD/FIXME/XXX markers, no placeholder implementations, no empty handlers.

### Human Verification Required

None. All must-haves are programmatically verifiable:
- Document existence and line counts: verified
- Required pattern presence (grep checks): verified
- Requirement traceability: verified
- Decision coverage (D-27 through D-39): verified
- Proto field numbering: verified
- Source anchor file existence: verified
- Key line-number references: verified against actual source

### Behavioral Spot-Checks

Skipped — this is a design-documentation phase. No runnable code produced. The deliverables are specifications, not implementations.

### Probe Execution

No probes declared for this phase. The phase is design-documentation only.

### Gaps Summary

No gaps found. All 11 must-have truths are verified. Both deliverables exceed minimum line counts, cover all 10 phase requirements, honor all 13 context decisions, resolve all 3 researcher open questions, and correctly reference SuperGenius anchor points that exist at the claimed file paths and line numbers.

---

_Verified: 2026-07-13T22:00:00Z_
_Verifier: the agent (gsd-verifier)_
