---
phase: 01-child-identity-registration-protocol
plan: 02
subsystem: design-docs
tags: [child-wallet, registration-protocol, RegistrationTx, proto-schema, Consensus.proto, EmbeddedTransaction, additive-only, backward-compatibility, child-signed-only, REG-02-reversal]

# Dependency graph
requires:
  - phase: 01-child-identity-registration-protocol
    provides: "Child-wallet identity model (IDENT-01..04) — independent keypair, nonce tracking, UTXO ownership"
provides:
  - "Registration protocol design document (docs/registration-protocol.md)"
  - "8 sections covering RegistrationTx schema, proto changes, oneof dispatch, C++ subclass, child-signed-only signing, connect flow, sequence numbering, backward-compatibility matrix, requirement traceability"
  - "All REG-01..05 requirements traceable to SuperGenius anchor points"
  - "REG-02 dual-signature reversal documented with security impact analysis"
  - "7-scenario backward-compatibility matrix"
affects: ["02-consensus-authority (Phase 2 consensus rules)", "02-crdt-pubsub (Phase 2 CRDT namespace + pubsub)", "03-lifecycle-rewards (Phase 3 lifecycle + reward policy)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Additive-only proto evolution: new messages appended, no renumbering of existing fields"
    - "GeniusTransaction subclass pattern: RegistrationTransaction follows MintTransaction analog"
    - "Dual-counter design: DAGStruct.nonce (tx ordering) + sequence (registration lineage)"
    - "Child-signed-only registration: main pubkey delivered via connect flow, no main counter-signature"
    - "Emergent identity integration: registration record = child-ness, no creation-time flag"

key-files:
  created:
    - "docs/registration-protocol.md — complete registration protocol design document (545 lines, 8 sections)"
  modified: []

key-decisions:
  - "D-04/D-05 (REG-02 reversal): Registration is child-signed-only — main does NOT counter-sign. Impact bounded to discovery spam, zero authority grant."
  - "D-06: RegistrationTx is a first-class GeniusTransaction subclass flowing through existing TransactionManager path."
  - "D-08: RegistrationTx schema — 8 fields total (4 + 4), additive-only proto changes."
  - "D-09: Dual-counter design — DAGStruct.nonce (tx ordering) + sequence (registration lineage), tie-break = Phase 2 hand-off."
  - "D-10: Connect flow delivers main pubkey only — transport-agnostic handshake, main private key never enters child process."

patterns-established:
  - "Design-document format: proto schemas in fenced code blocks with protobuf language tag"
  - "Backward-compatibility matrix: 7 scenarios with Compatible?/Why columns, proto3 rationale"
  - "Phase hand-off documentation: every deferred concept marked with target phase + requirement IDs"

requirements-completed: [REG-01, REG-02, REG-03, REG-04, REG-05]

# Metrics
duration: 3min
completed: 2026-07-13
---

# Phase 01 Plan 02: Registration Protocol Design Document Summary

**Complete registration protocol design document specifying the RegistrationTx proto schema, additive proto changes to SGTransaction.proto and Consensus.proto, C++ RegistrationTransaction subclass design, child-signed-only signing protocol with REG-02 reversal documentation, connect flow for main-pubkey delivery, dual-counter sequence numbering for replay protection, and 7-scenario backward-compatibility matrix — all with concrete SuperGenius anchor points.**

## Performance

- **Duration:** 3 min
- **Started:** 2026-07-13T22:11:43Z
- **Completed:** 2026-07-13T22:15:27Z
- **Tasks:** 3
- **Files modified:** 1 (created)

## Accomplishments

- Produced `docs/registration-protocol.md` (545 lines, 8 sections) — the authoritative registration protocol design document
- All five registration requirements (REG-01..05) are traceable to concrete SuperGenius anchor points with file paths, line numbers, and method signatures
- REG-02 dual-signature requirement is explicitly REVERSED per D-04/D-05 with security impact analysis in three places (§5.2 signing model, §5.3 impact analysis, §8 traceability table)
- Proto field audit recorded: `EmbeddedTransaction` oneof fields 1-7 verified used, field 8 proposed for `registration = 8`
- 7-scenario backward-compatibility matrix with proto3 rationale — all 7 scenarios documented, only 2 breaking (rows 5-6) and both explicitly avoided by additive-only design
- C++ subclass design fully specified: RegistrationTransaction file placement, constructor chain, New() factory, SerializeToEmbeddedTransaction, DeSerializeByteVector, RegisterDeserializer, TransactionManager dispatch integration

## Task Commits

Each task was committed atomically:

1. **Task 1: Sections 1-3 (RegistrationTx schema, proto changes, oneof dispatch)** — `9a0f1e9` (feat)
2. **Task 2: Sections 4-5 (C++ subclass, signing protocol, REG-02 reversal, connect flow)** — `c2b9ef2` (feat)
3. **Task 3: Sections 6-8 (sequence numbering, backward-compat matrix, traceability)** — `59a66a0` (feat)

## Files Created/Modified

- `docs/registration-protocol.md` — Complete registration protocol design document with 8 sections:
  - §1 Overview — RegistrationTx as first-class GeniusTransaction subclass, child-signed-only, CRDT Phase 2 hand-off, REG-01 traceability
  - §2 Proto Schema — `RegistrationTx` (4 fields: dag_struct, main_address, sequence, metadata) and `RegistrationMetadata` (4 fields: game_id, publisher_id, dev_wallet, peers_cut) appended to `SGTransaction.proto`, field-by-field explanation, additive-only guarantee
  - §3 Oneof Dispatch — `Consensus.proto` `EmbeddedTransaction` oneof field audit (fields 1-7 used, field 8 proposed), `registration = 8` addition, deserialization dispatch path
  - §4 C++ Subclass — `RegistrationTransaction` class design with file placement, constructor chain, `New()` factory, serialization methods, `DeSerializeByteVector`, `RegisterDeserializer`, `TransactionManager.cpp` dispatch integration
  - §5 Signing Protocol — REG-02 reversal documentation (§5.1), child-signed-only model (§5.2), security impact analysis with bounded-impact assessment (§5.3), rationale for child-only vs dual-signature (§5.4), transport-agnostic connect flow for main-pubkey delivery (§5.5, REG-04)
  - §6 Sequence Numbering — dual-counter design (`DAGStruct.nonce` vs `sequence`), authoritative registration selection (Phase 2 hand-off), defense-in-depth replay protection (REG-05)
  - §7 Backward-Compatibility Matrix — 7 scenarios with Compatible?/Why columns, proto3 rationale for each, additive-only summary (REG-03)
  - §8 Requirement Traceability — REG-01..05 traceability table with concrete anchor points, Phase 2/3 hand-offs table, cross-reference review, no-deferred-ideas-leaked audit

## Decisions Made

- D-04/D-05 confirmed: Registration is child-signed-only — REG-02 reversed with documented security impact (bounded to discovery spam, zero authority grant)
- D-06 confirmed: RegistrationTx is first-class GeniusTransaction subclass flowing through existing TransactionManager path
- D-08 confirmed: RegistrationTx schema with 8 fields (4 + 4), additive-only proto changes to SGTransaction.proto
- D-09 confirmed: Dual-counter design — DAGStruct.nonce (tx ordering) + sequence (registration lineage), tie-break = Phase 2 hand-off
- D-10 confirmed: Connect flow delivers main pubkey only, transport-agnostic handshake, main private key never enters child process

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Threat Flags

None — all threat model entries from PLAN.md are documented in the design document (§5.3 Security Impact Analysis, §6.3 Replay Protection). No new security-relevant surface beyond what the threat model covers.

## Known Stubs

None — all 8 sections are complete with concrete content. No placeholder text, no unwired data sources, no mock values. Phase hand-offs are explicitly deferred to later phases, not stubbed.

## Next Phase Readiness

- Registration protocol document is complete and ready for Phase 2 (CRDT Persistence, PubSub & Consensus Authority)
- All SuperGenius anchor points are concrete (file path + line number), enabling Phase 2 planners to reference the registration tx schema, signing protocol, and sequence numbering directly
- Phase Hand-Offs table in §8 clearly defers CRDT namespace, pubsub, consensus authority, lifecycle, reward policy, and platform UI to Phases 2-3 and v2
- The child-signed-only security model and bounded-impact analysis (discovery spam only, zero authority grant) are explicitly documented and must be honored by Phase 2 consensus rules (CONS-01..06)
- REG-02 is flagged for requirements update at phase transition (the REQUIREMENTS.md REG-02 description still references dual-signature)

---

*Phase: 01-child-identity-registration-protocol*
*Completed: 2026-07-13*
