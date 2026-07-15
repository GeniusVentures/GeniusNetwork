---
phase: 02-crdt-persistence-pubsub-consensus-authority
plan: 01
subsystem: crdt
tags: [crdt, pubsub, libp2p, registration, filter, consensus, supergenius]

# Dependency graph
requires:
  - phase: 01-child-identity-registration-protocol
    provides: RegistrationTx proto schema (REG-01), C++ subclass design (D-06), child-signed-only signing (D-04/D-05), dual-counter sequence numbering (D-09), emergent child identity (D-01)
provides:
  - CRDT registry namespace design anchored to TransactionManager/GlobalDB code
  - FilterRegistration four-gate element filter design
  - PubSub CID-only broadcast and main-subscription sync design
  - SendTransactionItem 8-step RegistrationTx consensus flow
  - Certified status flag two-tier CRDT+consensus model
  - CRDT eventual-consistency vs consensus-ordering resolution
affects: [02-consensus-parent-child-authority, 03-discovery-rewards-lifecycle]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "CRDT element filter registration with regex capture group for reg/ namespace"
    - "do{}while(0)+should_delete filter gate pattern matching FilterTransaction"
    - "PubSub CID-only payload constraint (never full protobuf)"
    - "Two-tier CRDT (optimistic) + consensus (authoritative) model for eventual-consistency vs ordering"
    - "First-to-consensus wins tie-break via nonce chain"

key-files:
  created:
    - docs/02-crdt-registry-pubsub.md
  modified: []

key-decisions:
  - "D-11: reg/ namespace only, FilterRegistration method, regex ^/?/bc-{net}/reg/([^/]+)"
  - "D-12: Single key per child: reg/{child_addr}, updated in-place on higher sequence"
  - "D-13: Four rejection gates — deserialize, signature, sequence monotonicity, well-formed. No cascade-delete."
  - "D-14: CRDT value = full RegistrationTx protobuf (self-contained, no cross-referencing)"
  - "D-15: Registration broadcast: CID on main_address topic + CRDT write"
  - "D-16: Main discovery: pubsub triggers AddListenTopic; authority NOT from topic membership"
  - "D-17: Ongoing sync: main subscribes to child_address topic, merges CRDT deltas without child private key"
  - "D-18: Pubsub payload = RegistrationTx CID/hash only (not full protobuf)"
  - "D-24: RegistrationTx flows through full consensus, reuses sgns.nonce.v1"
  - "D-25: Tie-break: first-to-consensus wins; nonce chain prevents double-certification"
  - "D-26: Certified status flag; two-tier CRDT+consensus model; pre-certificate accept"

patterns-established:
  - "FilterRegistration: do{}while(0)+should_delete gate pattern paralleling FilterTransaction (TransactionManager.cpp:2984-3039)"
  - "CRDT key construction: GetBlockChainBase() + 'reg/' + child_addr → /bc-{net}/reg/{child_addr}"
  - "Certified status: Option C (in-memory tx_processed_m CONFIRMED) + Option A (reg-cert/ CRDT key backup)"
  - "Authority chain: pubsub (untrusted) → CID resolution (content-addressed) → consensus certificate (authoritative) → certified status (actionable)"

requirements-completed: [SYNC-01, SYNC-02, SYNC-03, SYNC-04, SYNC-05]

# Metrics
duration: 12min
completed: 2026-07-13
---

# Phase 02 Plan 01: CRDT Registry Namespace, PubSub & Sync Summary

**CRDT reg/ namespace with four-gate FilterRegistration, CID-only pubsub broadcast, and two-tier certified-status model resolving eventual-consistency vs consensus-ordering tension — all anchored to 27+ concrete SuperGenius code points.**

## Performance

- **Duration:** 12 min
- **Started:** 2026-07-13T23:45:00Z
- **Completed:** 2026-07-13T23:57:00Z
- **Tasks:** 2
- **Files created:** 1

## Accomplishments

- Produced a 968-line design document (`docs/02-crdt-registry-pubsub.md`) with 8 sections covering the complete CRDT registry namespace, pubsub broadcast/subscription, and certified-status model
- Mapped every claim to 27+ concrete SuperGenius anchor points (file paths + line numbers in backtick monospace)
- Documented the FilterRegistration four-gate sequence with rejection behavior for each FAIL branch, including the unique sequence-monotonicity gate
- Defined the CID-only pubsub payload constraint (D-18) with the explicit declaration that "Authority is NEVER derived from topic membership"
- Specified the SendTransactionItem 8-step flow for RegistrationTx with all RegistrationTx-specific differences from TransferTx
- Resolved the CRDT eventual-consistency vs consensus-ordering tension through the two-tier model: optimistic CRDT storage + authoritative consensus certification
- All 11 Phase 2 decisions (D-11..D-18, D-24..D-26) included and traceable in the compliance table
- All 5 SYNC requirements (SYNC-01..05) traceable with concrete anchor points
- Phase 3 deferred items explicitly listed (DISC, RWD, LIFE, PLAT, ADV)

## Task Commits

Each task was committed atomically:

1. **Task 1: CRDT Namespace, FilterRegistration, and PubSub Design (Sections 1-4)** - `5cc09a4` (feat)
2. **Task 2: Consensus Flow, Certified Status, Ordering Resolution, Traceability (Sections 5-8)** - `093eca0` (feat)

## Files Created/Modified

- `docs/02-crdt-registry-pubsub.md` — Complete design document: 968 lines, 8 sections, 27+ anchor points, 3 code block diagrams, 6 comparison tables, 2 traceability tables

## Decisions Made

All 11 locked decisions from Phase 2 CONTEXT.md are reflected in the document with explicit decision IDs:

| Decision | Key Design Choice |
|----------|------------------|
| D-11 | `reg/` namespace only; FilterRegistration method on TransactionManager |
| D-12 | Single key per child: `reg/{child_addr}`, updated in-place |
| D-13 | Four rejection gates; no cascade-delete |
| D-14 | CRDT value = full RegistrationTx protobuf |
| D-15 | Registration broadcast: CID on main_address topic |
| D-16 | Main discovery: pubsub triggers AddListenTopic; authority not from topic |
| D-17 | Ongoing sync: main subscribes to child_address topic |
| D-18 | Pubsub payload = CID only |
| D-24 | RegistrationTx through full consensus, reuses sgns.nonce.v1 |
| D-25 | First-to-consensus wins tie-break |
| D-26 | Certified status flag; two-tier CRDT+consensus model |

**Agent discretion decisions:**
- **Certified status implementation:** Recommended Option C (in-memory `tx_processed_m` with CONFIRMED status) augmented with Option A (`reg-cert/` CRDT key backup) — matches existing `ChangeTransactionState` pattern at `TransactionManager.cpp:5110-5184`
- **CID selection:** Use CRDT IPLD CID from `GlobalDB::Put`, not transaction hash — canonical content-addressed reference into CRDT DAG

## Deviations from Plan

None - plan executed exactly as written. All sections, anchor points, decision IDs, and traceability tables match the plan's action blocks precisely.

## Issues Encountered

None. The design document compiled cleanly from the extensive Phase 02 research (CONTEXT.md, RESEARCH.md, PATTERNS.md) and Phase 01 design docs — no code-level troubleshooting needed.

## User Setup Required

None — design-documentation phase, no external services or configuration required.

## Next Phase Readiness

- This document provides the CRDT persistence and pubsub foundation for Phase 02 Plan 02 (`docs/02-consensus-parent-child-authority.md`)
- `CheckParentChildAuthority` gate (Plan 02) references this document's certified-status design (§6) for `IsRegistrationCertified` semantics
- All 5 SYNC requirements are satisfied; the 6 CONS requirements (CONS-01..06) are covered in Plan 02
- Ready for Phase 02 verification (combined with Plan 02): both documents together must satisfy all 11 Phase 2 requirement IDs

## Known Stubs

None — all sections have concrete content with code excerpts, anchor points, decision IDs, and cross-references. No placeholder content.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: pre-certificate-accept | docs/02-crdt-registry-pubsub.md §3 | FilterRegistration accepts well-formed RegistrationTx immediately (optimistic storage). Uncertified entries must NOT be treated as authoritative by downstream gates. Mitigated by certified-status check in §6. |

---

*Phase: 02-crdt-persistence-pubsub-consensus-authority*
*Completed: 2026-07-13*
