---
phase: 02-crdt-persistence-pubsub-consensus-authority
plan: 02
subsystem: consensus
tags: [parent-child-authority, CheckParentChildAuthority, ValidateTransactionForConsensus, consensus-pipeline, CRDT, reg-namespace]

# Dependency graph
requires:
  - phase: 02-crdt-persistence-pubsub-consensus-authority
    provides: CRDT reg/ namespace, FilterRegistration, certified status flag
  - phase: 01-child-identity-registration-protocol
    provides: RegistrationTx schema, child-signed-only signing model, dual-counter design
provides:
  - Consensus parent-child authority rules design document with all 6 CONS requirements
  - Gate integration specification for CheckParentChildAuthority in ValidateTransactionForConsensus pipeline
  - Rule dispatch logic with deterministic classification
  - Main-recover-from-child with D-21 destination restriction
  - Child-cannot-spend-main invariant documented at GeniusInputValidator.cpp:419-432
  - RegistrationTx field validation recommendation for CheckTransactionTypeRules
  - Full requirement traceability and decision compliance matrices
affects:
  - Phase 3 discovery/rewards/lifecycle (depends on authority rules defined here)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Consensus gate insertion: new gate slots between existing gates in ValidateTransactionForConsensus pipeline at TransactionManager.cpp:4250-4303"
    - "State-dependent authority: CheckParentChildAuthority reads CRDT reg/ records during consensus validation — first non-cryptographic authority gate"
    - "Defense-in-depth: RegistrationTx fields validated at both CRDT filter level (FilterRegistration) and consensus level (CheckTransactionTypeRules)"
    - "Orthogonal authority: delegated authority (gate 2.5) separated from UTXO ownership (gate 5) per CONS-06/D-23"

key-files:
  created:
    - docs/02-consensus-parent-child-authority.md - Complete consensus parent-child authority rules design document (717 lines, 8 sections)
  modified: []

key-decisions:
  - "CheckParentChildAuthority gates between CheckTransactionAuthorization and CheckTransactionTimestamp in ValidateTransactionForConsensus (D-19)"
  - "Rule dispatch reuses existing transfer tx type with signer+reg/+certified checks (D-20)"
  - "Main-recover-from-child hard dst==main_address restriction prevents recovery-as-seizure (D-21)"
  - "Child-cannot-spend-main enforced by existing ValidateWitness owner_address check — documented as invariant, no new code (D-22)"
  - "Hierarchical authority orthogonal to UTXO ownership via separate gate (D-23/CONS-06)"

patterns-established:
  - "Gate insertion pattern: new consensus gate declared in TransactionManager.hpp, implemented in TransactionManager.cpp, called in ValidateTransactionForConsensus between existing gates"
  - "Invariant documentation: existing enforcement documented with negative test spec, no code modification"
  - "Cross-document dependency: authority gate depends on CRDT reg/ key layout and certified status from Plan 02-01"
  - "Defense-in-depth validation: same semantic fields validated at both CRDT filter and consensus pipeline levels"

requirements-completed: [CONS-01, CONS-02, CONS-03, CONS-04, CONS-05, CONS-06]

# Metrics
duration: 22min
completed: 2026-07-14
---

# Phase 02 Plan 02: Consensus Parent-Child Authority Rules Summary

**Complete design document specifying how parent-child authority is enforced by consensus through a new `CheckParentChildAuthority` gate in `ValidateTransactionForConsensus`, with all six CONS rules mapped to concrete SuperGenius pipeline stages and anchor points.**

## Performance

- **Duration:** 22 min
- **Started:** 2026-07-14T01:09:00Z
- **Completed:** 2026-07-14T01:31:00Z
- **Tasks:** 2
- **Files modified:** 1 (created)

## Accomplishments

- Created `docs/02-consensus-parent-child-authority.md` (717 lines, 8 sections) with comprehensive consensus parent-child authority design
- Documented the complete extended 7-gate consensus pipeline with `CheckParentChildAuthority` gate insertion between `CheckTransactionAuthorization` and `CheckTransactionTimestamp` (D-19)
- Specified all 6 CONS rules with exact SuperGenius anchor points: CONS-01 (main→child fund), CONS-02 (main-recover with D-21 dst restriction), CONS-03/04 (child→arbitrary/developer pass-through), CONS-05 (child-cannot-spend-main invariant), CONS-06 (orthogonal authority separation)
- Documented RegistrationTx field validation recommendation for `CheckTransactionTypeRules` with defense-in-depth rationale
- Resolved the critical interaction between gate 2.5 (`CheckParentChildAuthority`) and gate 5 (`ValidateWitness`) for main-recover-from-child — demonstrated that `src_address` matches `payload_owner` naturally, making the delegated-authority flag unnecessary
- Corrected the uncertified registration handling: gate MUST `Reject()` (not `Approve()`) when main-signed from child address with no certified registration
- Created full requirement traceability and decision compliance tables with all 5 decisions (D-19..23) marked Included
- All Phase 3 requirements (DISC, RWD, LIFE) explicitly deferred

## Task Commits

Each task was committed atomically:

1. **Task 1: Gate Integration, Rule Dispatch, and Rule Specifications 1–5 (Sections 1–5)** — `c0ae6d6` (feat)
2. **Task 2: RegistrationTx Field Validation, Rule Summary Matrix, and Traceability (Sections 6–8)** — `a624c9c` (feat)

## Files Created/Modified

- `docs/02-consensus-parent-child-authority.md` — Complete consensus parent-child authority rules design document with 8 sections, 717 lines, covering gate integration, rule dispatch, all 6 CONS rules (CONS-01 through CONS-06), RegistrationTx field validation, rule summary matrix, full lifecycle traces, and requirement traceability

## Decisions Made

None — followed plan as specified. All decisions (D-19 through D-23) were locked in CONTEXT.md prior to execution. The document faithfully implements all decisions and requirements.

Key design refinements made during execution:
- Clarified that for main-recover-from-child, `ValidateWitness` passes naturally because `src_address` (child) matches `payload_owner` (child) — no delegated-authority flag needed
- Corrected uncertified registration handling: gate must `Reject()` main-signed-from-child-address transfers when registration is not certified (safe default)
- Section 7 lifecycle traces demonstrate the full gate-by-gate flow for both fund and recover scenarios

## Deviations from Plan

None — plan executed exactly as written. The plan's action blocks were followed precisely with all anchor points, line numbers, cross-references, and structural requirements met.

## Issues Encountered

- `docs/02-crdt-registry-pubsub.md` (Plan 02-01 output) was not present on disk at execution time (parallel/prior execution). Used PATTERNS.md, CONTEXT.md, and RESEARCH.md as fallback sources for CRDT cross-references — all necessary information (reg/ key layout, FilterRegistration design, certified status flag) was available in those files.
- The interaction between gate 2.5 (`CheckParentChildAuthority`) and gate 5 (`ValidateWitness`) required deeper analysis during the lifecycle trace write-up. Determined that no special flag mechanism is needed because `src_address == payload_owner` for child UTXOs — the UTXO ownership check passes naturally.

## Next Phase Readiness

- All 6 CONS requirements documented with traceable anchor points
- Cross-references to Plan 02-01 (CRDT registry/pubsub) established for certified status dependency
- Phase 3 deferred items (DISC-01..03, RWD-01..03, LIFE-01..04) explicitly listed for hand-off
- Document is implementation-ready: a developer can locate every anchor point by file path + line number

---
*Phase: 02-crdt-persistence-pubsub-consensus-authority*
*Completed: 2026-07-14*
