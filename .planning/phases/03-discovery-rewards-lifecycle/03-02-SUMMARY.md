---
phase: 03-discovery-rewards-lifecycle
plan: 02
subsystem: design-docs
tags: [child-wallet, reward-policy, lifecycle, state-machine, escrow, RegistrationTx, RevokeTx, supersedes-sequence, conflict-resolution, proto-extension]

# Dependency graph
requires:
  - phase: 01-child-identity-registration-protocol
    provides: RegistrationTx schema, RegistrationMetadata fields (dev_wallet, peers_cut, game_id, publisher_id)
  - phase: 02-crdt-persistence-pubsub-consensus-authority
    provides: reg/ CRDT namespace, FilterRegistration, CheckParentChildAuthority gate, certified status, pubsub broadcast/subscription
  - phase: 03-discovery-rewards-lifecycle (plan 01)
    provides: Discovery push/poll mechanism, per-child info aggregation, main-wallet action mappings
provides:
  - "Complete reward policy & lifecycle design document (docs/03-02-reward-policy-lifecycle.md, 494 lines, 13 sections)"
  - "Dual-source reward policy resolution (DevConfig_st for standalone, reg/ CRDT RegistrationMetadata for registered) with certified-status gate"
  - "Hold-time pinning via existing EscrowTransaction immutability — verified invariant, zero Phase 3 design changes"
  - "Child-only authenticated policy updates via RegistrationTx at higher sequence with supersedes_sequence linkage"
  - "Four-state lifecycle model (Unregistered/Registered/Detached/Revoked) with 5 valid transitions and state machine diagram"
  - "Detach (child-initiated) and Revoke (main-initiated) change flows with supersedes-sequence + nonce-chain conflict resolution"
  - "Main replacement policy fork decision (child-only, no old-main consent) with deadlock-avoidance rationale"
  - "Detach semantics: UTXOs/keypair/nonce unaffected — child remains valid standalone wallet"
  - "Proto evolution summary: 6 additive fields across RegistrationTx/RevokeTx/EmbeddedTransaction — backward-compatible"
affects: ["implementation"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dual-source policy resolution: certified reg/ CRDT → RegistrationMetadata; no reg/ → DevConfig_st fallback"
    - "Certified-status gate before policy-source selection (D-26, T-03-06 mitigation)"
    - "Child-only lifecycle control via RegistrationTx at higher sequence + supersedes_sequence linkage (D-33, D-38)"
    - "First-class RevokeTx as GeniusTransaction subclass (revoke=9 in EmbeddedTransaction oneof) — NOT a flagged transfer"
    - "CRDT filter gate 3b: reject if supersedes_sequence ≠ current.sequence — fork prevention"
    - "Nonce chain total ordering (sgns.nonce.v1): first-to-consensus-wins, NOT first-to-CRDT-wins"
    - "PayDev vs HoldEscrow two-integration-point model: pin at hold, resolve at pay"

key-files:
  created:
    - "docs/03-02-reward-policy-lifecycle.md — Complete reward policy & lifecycle design document (494 lines, 13 sections)"
  modified: []

key-decisions:
  - "Policy-source selection at GeniusNode level — TransactionManager::HoldEscrow is policy-agnostic; caller chooses source based on child registration status"
  - "Hold-time pinning requires zero Phase 3 changes — EscrowTransaction immutability is existing behavior verified at EscrowTransaction.hpp:122-131 + TransactionManager.cpp:846-875"
  - "Reward policy updates are child-only — publishers trust the child not to redirect payouts (D-33 trust model, not cryptographic constraint)"
  - "Main replacement is child-only (D-37) — old-main consent creates deadlock risk; consistent with child-owned identity model (D-04/D-05)"
  - "First-class RevokeTx recommended as GeniusTransaction subclass (NOT flagged transfer) — cleaner audit trail, dedicated CheckParentChildAuthority path"
  - "Supersedes_sequence + nonce chain = deterministic first-to-consensus-wins conflict resolution (D-38)"
  - "No registration-pending or closed states (D-34) — child-signed-only means immediate registration; keypair accounts don't close"
  - "RegistrationTx schema references 01-01-SUMMARY.md (not stale docs/registration-protocol.md path)"

patterns-established:
  - "Design-document format: anchor points include file path + line number in backtick monospace"
  - "Proto additive evolution: fields 5-6 appended to RegistrationTx; revoke=9 in EmbeddedTransaction oneof"
  - "Cross-document references: Phase 2 design docs cited as docs/02-crdt-registry-pubsub.md and docs/02-consensus-parent-child-authority.md"

requirements-completed: [RWD-01, RWD-02, RWD-03, LIFE-01, LIFE-02, LIFE-03, LIFE-04]

# Metrics
duration: 6min
completed: 2026-07-14
---

# Phase 03 Plan 02: Reward Policy & Lifecycle Design Summary

**Complete reward policy & lifecycle design document specifying dual-source per-child reward policy resolution (DevConfig_st vs reg/ CRDT RegistrationMetadata), hold-time pinning via existing EscrowTransaction immutability, child-only authenticated policy updates, four-state lifecycle model with all valid transitions, detach/revoke/replace-main change-flows with supersedes-sequence + nonce-chain conflict resolution, and main-replacement policy fork decision — all mapped to concrete SuperGenius anchor points with file:line references.**

## Performance

- **Duration:** 6 min
- **Started:** 2026-07-14T01:52:09Z
- **Completed:** 2026-07-14T01:58:12Z
- **Tasks:** 2
- **Files modified:** 1 (created)

## Accomplishments

- Produced `docs/03-02-reward-policy-lifecycle.md` (494 lines, 13 sections) — the authoritative design document for child-wallet reward policy + lifecycle
- Reward policy resolution (§2) documents dual-source selection: certified `reg/{child_addr}` CRDT → `RegistrationMetadata.dev_wallet`/`.peers_cut` for registered children; `DevConfig_st` (`GeniusNode.hpp:59-66`) for standalone children. TransactionManager::HoldEscrow is policy-agnostic — caller (GeniusNode) chooses the source.
- Hold-time pinning (§3) documents the EscrowTransaction immutability chain: constructor pins `dev_addr_`/`peers_cut_` at `EscrowTransaction.hpp:122-131`; `PayEscrow` reads stored values at `TransactionManager.cpp:846-875`, NOT live CRDT. Explicitly states "Zero Phase 3 changes needed — existing behavior satisfies RWD-02."
- Authenticated policy updates (§4) document child-only RegistrationTx at higher sequence with updated RegistrationMetadata, FilterRegistration gate validation (gates 2, 3, 3b), publisher trust model, and competing-update conflict scenario
- Lifecycle state machine (§6) defines 4 states (Unregistered/Registered/Detached/Revoked) with CRDT-derived conditions, 5 valid transitions with initiator + mechanism mapping, explicit exclusion of registration-pending/closed states, and an ASCII state machine diagram
- Detach flow (§7) documents child-initiated detach via RegistrationTx with `detach_flag=5`, higher sequence, `supersedes_sequence=6`, FilterRegistration gate 3b
- Revoke flow (§8) recommends first-class `RevokeTx` as new `GeniusTransaction` subclass with `revoke=9` in `EmbeddedTransaction` oneof, full consensus gate pipeline (gates 1-5 + CheckParentChildAuthority gate 2.5)
- Replace main (§9) documents child-only replacement (D-37) with deadlock-avoidance rationale, supersedes_sequence linkage (D-38), deterministic conflict resolution ("NOT first-to-CRDT-wins — first-to-consensus-wins"), and replay attack prevention
- Detach semantics (§10) documents that UTXOs/keypair/nonce are unaffected — detach/revoke only severs the parent-child authority relationship; child remains valid standalone wallet; `reg/` record retained as audit trail
- Proto evolution (§11) summarizes all 6 additive changes in a table: RegistrationTx fields 5 (`detach_flag`), 6 (`supersedes_sequence`); RevokeTx message with fields 1-3; EmbeddedTransaction oneof arm 9 (`revoke`)
- All 7 requirements (RWD-01..03, LIFE-01..04) traceable to document sections with concrete SuperGenius anchor points in the traceability table (§12)
- All 10 locked decisions (D-30 through D-39) honored with explicit references and rationale
- Phase hand-offs (§13) document dependencies on Phase 1/2, integration surface for implementation, and v2 deferrals

## Task Commits

Each task was committed atomically:

1. **Task 1: Write reward policy design — policy resolution, hold-time pinning, authenticated updates (RWD-01, RWD-02, RWD-03)** — `9556ab5` (feat)
   - Sections 1-5: Overview, Reward Policy Resolution Flow (RWD-01), Hold-Time Pinning (RWD-02), Authenticated Policy Updates (RWD-03), PayDev Path

2. **Task 2: Write lifecycle design — state machine, transitions, change flows, conflict resolution (LIFE-01, LIFE-02, LIFE-03, LIFE-04)** — `2270c88` (feat)
   - Sections 6-13: Lifecycle State Machine (LIFE-01), Detach Flow, Revoke Flow, Replace Main + Policy Fork (LIFE-02, LIFE-03), Detach Semantics (LIFE-04), Proto Evolution, Traceability, Phase Hand-Offs

## Files Created/Modified

- `docs/03-02-reward-policy-lifecycle.md` — Complete reward policy & lifecycle design document with 13 sections:
  - §1 Overview — Two-mode architecture (standalone DevConfig_st vs registered RegistrationMetadata), per-child processing reward policy definition
  - §2 Reward Policy Resolution Flow (RWD-01) — Policy-source selection at GeniusNode level: certified reg/ CRDT lookup; certified-status gate (D-26, T-03-06); TransactionManager::HoldEscrow is policy-agnostic; integration surface table
  - §3 Hold-Time Pinning (RWD-02) — EscrowTransaction immutability chain: `dev_addr_`/`peers_cut_` pinned at construction (EscrowTransaction.hpp:122-131); PayEscrow reads stored values (TransactionManager.cpp:846-875); mid-flight policy change scenario; explicit "zero Phase 3 changes" statement
  - §4 Authenticated Policy Updates (RWD-03) — Child-only RegistrationTx at higher sequence with updated RegistrationMetadata; FilterRegistration gate validation (gates 2, 3, 3b); publisher trust model (child controls own policy, not cryptographic constraint); competing update conflict scenario; proto fields used
  - §5 PayDev Path — Two-mode developer wallet resolution (RegistrationMetadata.dev_wallet for registered; dev_config_.Addr for standalone); PayDev vs HoldEscrow two-integration-point model
  - §6 Lifecycle State Machine (LIFE-01) — 4-state definitions with CRDT conditions; design rationale for excluded states (no registration-pending/closed); 5-transition table with initiator + mechanism; ASCII state machine diagram
  - §7 Detach Flow (LIFE-01, LIFE-02) — Child-initiated via RegistrationTx with detach_flag=5, higher sequence, supersedes_sequence=6; FilterRegistration gate 3b; detach protections table; post-detach state
  - §8 Revoke Flow (LIFE-01, LIFE-02) — First-class RevokeTx as GeniusTransaction subclass (revoke=9 in EmbeddedTransaction); RevokeTx proto message (dag_struct=1, child_address=2, registration_sequence=3); full consensus pipeline (gates 1-5 + CheckParentChildAuthority gate 2.5); revoke vs detach comparison table
  - §9 Replace Main + Policy Fork (LIFE-02, LIFE-03) — Child-only replacement flow; policy fork decision with deadlock-avoidance rationale and rejected alternatives; supersedes_sequence + nonce chain conflict resolution ("first-to-consensus-wins"); replay attack prevention (T-03-12)
  - §10 Detach Semantics (LIFE-04) — What is unaffected table (address/keypair/nonce/UTXOs/escrows/history); what changes table (reg/ record, authority, policy source); 4 design invariants
  - §11 Proto Evolution Summary — RegistrationTx extension table (fields 1-6); RevokeTx message table; EmbeddedTransaction oneof table (arms 1-9); backward compatibility statement
  - §12 Requirement Traceability — Table mapping all 7 requirements (RWD-01..03, LIFE-01..04) to sections with key anchor points and decision references
  - §13 Phase Hand-Offs — Dependencies table (Phase 1, 2, 3-01); integration surface for implementation; v2 deferrals (PLAT-01/02, ADV-01/02, token economics, optional main acceptance)

## Decisions Made

- Policy-source selection at GeniusNode level — TransactionManager::HoldEscrow receives `dev_addr`/`peers_cut` as parameters; caller chooses source based on child registration status. No TransactionManager change needed.
- Hold-time pinning requires zero Phase 3 changes — EscrowTransaction immutability (`EscrowTransaction.hpp:122-131`) + PayEscrow stored reads (`TransactionManager.cpp:846-875`) are existing behavior. Design doc documents this as a verified invariant.
- Reward policy updates are child-only (D-33) — publisher trust model: publishers trust the child not to redirect payouts; UX/social contract, not cryptographic constraint.
- Main replacement is child-only (D-37) — requiring old-main consent creates deadlock if old main key is lost; consistent with child-owned identity model (D-04/D-05).
- First-class `RevokeTx` recommended as `GeniusTransaction` subclass (`revoke=9` in `EmbeddedTransaction`), NOT a flagged transfer — cleaner audit trail, dedicated `CheckParentChildAuthority` path, follows `RegistrationTx` pattern.
- Supersedes_sequence (D-38) + nonce chain (`sgns.nonce.v1`, `Consensus.hpp:37`) = deterministic first-to-consensus-wins conflict resolution. NOT first-to-CRDT-wins — consensus ordering determines the winner.
- No registration-pending or closed states (D-34) — child-signed-only means immediate registration upon certification; keypair accounts don't close; `reg/` record retained as audit trail.
- RegistrationTx schema references `01-01-SUMMARY.md` for `RegistrationMetadata` fields — not the stale `docs/registration-protocol.md` path per PLAN.md instruction.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Threat Model Coverage

All 7 STRIDE threats from the plan's threat register are addressed in the document:

| Threat ID | Category | Mitigation | Document Section |
|-----------|----------|------------|------------------|
| T-03-06 | Tampering (reward policy resolution) | Policy source read from certified reg/{child_addr} CRDT only; uncertified → DevConfig fallback; certified-status gate documented | §2.3, §2.4 Certified-Status Gate |
| T-03-07 | Repudiation (payout redirection) | Accepted per D-33 — publisher trust model explicitly documented; child controls own registration | §4.2 Trust Model, §4.3 Sequence Ordering |
| T-03-08 | Tampering (mid-flight policy change) | EscrowTransaction stores dev_addr_/peers_cut_ immutably at construction; PayEscrow reads stored values, NOT live CRDT; zero Phase 3 changes needed | §3.1 Immutability Chain, §3.2 Mid-Flight Scenario |
| T-03-09 | Tampering (competing lifecycle updates) | FilterRegistration gate 3b rejects supersedes_sequence ≠ current.sequence; nonce chain (sgns.nonce.v1) provides total ordering; first-to-consensus-wins | §9.3 Conflict Resolution, §4.5 Competing Updates |
| T-03-10 | Elevation of Privilege (recovery-as-seizure) | Revoke sets detach_flag=true — main loses recovery authority immediately; recovery destination hard-restricted to main_address (CONS-02, D-21) | §8.4 Post-Revoke State |
| T-03-11 | DoS (main key loss deadlock) | Main replacement is child-only (D-37) — no old-main consent required; child issues new RegistrationTx at higher sequence with new main_address | §9.2 Policy Fork Decision |
| T-03-12 | Tampering (replay of old lifecycle tx) | Gate 3 (sequence > current.sequence) + nonce chain (sgns.nonce.v1) — old sequences and old nonces rejected | §9.4 Replay Attack Prevention |

## Next Phase Readiness

- **Phase 3 is now complete** — both plans (03-01 discovery & monitoring, 03-02 reward policy & lifecycle) have been executed and committed
- All 10 Phase 3 requirements (DISC-01..03, RWD-01..03, LIFE-01..04) are traceable with concrete SuperGenius anchor points
- All 13 locked decisions (D-27 through D-39) are honored
- Phase 2 requirements (CONS-01..06, SYNC-01..05) remain pending — the design documents in Phase 3 specify how they get used, but the Phase 2 plans themselves need execution
- Implementation-ready: every design concept maps to a concrete file:line anchor in the SuperGenius codebase
- Extension to v2 deferred items is clearly scoped (§13.3)

---

*Phase: 03-discovery-rewards-lifecycle*
*Completed: 2026-07-14*
