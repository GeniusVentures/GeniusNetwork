---
phase: 04-grid-integration-e2e-proof
plan: 04
subsystem: processing
tags: [settlement, escrow, payout, refund, uint128, deterministic-arithmetic]

requires:
  - phase: 04-grid-integration-e2e-proof
    provides: stamped envelopes (D-04), submit branch + composed elm_rate record
  - phase: 01-elm-job-model-funding
    provides: ElmEscrowMinions integer path, 01-DESIGN-SETTLEMENT §2/§3 contract
provides:
  - sgns::processing::{ElmSubtaskWindow, ElmSettlementData, ElmSplitResult, ElmShare}
  - ElmWindowMillihours (llround, clamp ≥0) + ElmWindowsToShares (proportional uint128 floor split, largest-window remainder with lexicographic tiebreak, cap, refund) + ElmWindowFromEnvelopeJson (non-throwing filter)
  - TransactionManager parameter chain: AsyncPayEscrow/PayEscrow/BuildPayoutOutputs + additive defaulted (elmSettlement, refundAddress)
  - BuildPayoutOutputs ELM branch: post-burn cap, ledger-owned refund target, per-share developer_cut, §3.3 filter, fail-closed refusals
affects: [04-05 e2e settlement wiring]

tech-stack:
  added: []
  patterns:
    - "Burn-aware conservation: ELM billable caps at post-burn available; refund + exact burn tail reconcile Σ == escrow for any burn basis"
    - "Fail-closed payout refusals: zero-well-formed-windows and refund-without-address both return invalid_argument"

key-files:
  created:
    - SuperGenius/src/processing/elm_settlement.hpp
    - SuperGenius/src/processing/elm_settlement.cpp
    - SuperGenius/test/src/processing/elm_settlement_test.cpp
  modified:
    - SuperGenius/src/processing/CMakeLists.txt
    - SuperGenius/src/account/TransactionManager.cpp
    - SuperGenius/src/account/TransactionManager.hpp
    - SuperGenius/test/src/processing/CMakeLists.txt

key-decisions:
  - "ELM billable pool caps at the POST-BURN available (not raw escrow): refund + exact burn tail then conserve Σ == escrow for ANY burn basis; the design's §2 formula holds exactly at burn=0 (the ELM default today)"
  - "Refund target is threaded as a defaulted string but PayEscrow fills it from escrow_tx->GetSrcAddress() — ledger-owned, never result/envelope data (T-04-04-03)"
  - "All-malformed windows -> empty shares -> invalid_argument refusal (never pay-everything-to-nobody); same fail-closed for refund>0 with empty refundAddress"
  - "Test access via the EXISTING PayoutOutputsTestAccess friend (extended signature) — no new friend, no WHOLEARCHIVE-only path needed beyond genius_node_test's link closure"

patterns-established:
  - "Per-row conservation assertions (S(shares)+refund == escrow on every matrix row, not one global check)"
  - "Composite floor(Σ*3/10) via div/mod equals the direct uint64 division exactly (documented in code)"

requirements-completed: [JOB-04, E2E-03]

coverage:
  - id: D1
    description: "Settlement arithmetic unit: millihours, *3/10 floor, cap, proportional split, tiebreak, refund, malformed exclusion, conservation"
    requirement: E2E-03
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/processing/elm_settlement_test.cpp#ElmSettlementArithmetic.* (7 legs, per-row conservation)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Envelope filter: valid stamps parse with caller-keyed subtaskid; malformed inputs -> nullopt without throwing"
    requirement: E2E-03
    verification:
      - kind: unit
        ref: "elm_settlement_test.cpp#ElmSettlementEnvelopeFilter.* (3 legs)"
        status: pass
    human_judgment: false
  - id: D3
    description: "BuildPayoutOutputs ELM branch: proportional+refund+conservation, no-window filter, all-malformed refusal, refund-address fail-closed"
    requirement: JOB-04
    verification:
      - kind: unit
        ref: "elm_settlement_test.cpp#ElmPayoutBranch.* (6 legs via the test-access friend)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Additive parameter chain + parity: existing AsyncPayEscrow call site compiles unmodified; nullptr settlement reproduces even-split; existing payout test green"
    requirement: E2E-03
    verification:
      - kind: unit
        ref: "git diff GeniusNode.cpp == 0 lines; payout_outputs_test 4/4; elm_settlement_test#NullSettlementReproducesEvenSplitExactly"
        status: pass
    human_judgment: false

duration: 55min
completed: 2026-09-14
status: complete
---

# Phase 4 Plan 04: Settlement Arithmetic + Payout Branch Summary

**01-DESIGN-SETTLEMENT §2/§3 as a pure deterministic unit plus the additive BuildPayoutOutputs ELM branch — proportional-by-window payouts with ledger-owned refunds, burn-aware conservation, and the even-split default untouched.**

## Performance

- **Duration:** ~55 min
- **Completed:** 2026-09-14 (commits d0efb341e, bbc2e9f90, a85d9497b)
- **Tasks:** 3 (all auto)
- **Files:** 7 created/modified

## Accomplishments

- `elm_settlement` unit: the §2 arithmetic (llround milli-hours, `*3/10` floor, escrow cap) and §3 split (uint128 proportional floors, largest-window remainder with lexicographic tiebreak, malformed exclusion, refund) with the never-throwing envelope filter
- `BuildPayoutOutputs` ELM branch behind additive defaulted parameters; `PayEscrow` supplies the refund target from the escrow transaction's own source address
- 17/17 settlement tests + 4/4 existing payout parity tests green; the untouched `GeniusNode.cpp` call site proves A1 source compatibility

## Task Commits

1. **Task 1: elm_settlement unit** — `d0efb341e`
2. **Task 2: ELM branch + parameter chain** — `bbc2e9f90`
3. **Task 3: test matrix** — `a85d9497b`

## Decisions Made

- Post-burn cap (see key-decisions): generalizes the design's burn=0 formula; documented in code
- Refusals fail closed rather than degrading

## Deviations from Plan

None — plan executed as written (the two test-literal fixes during bring-up are ordinary TDD adjustments, recorded below for completeness: raw-string newline + collapsed-developer/ordering expectations).

## Issues Encountered

- Test bring-up fixed two leg bugs (multi-line raw-string JSON literal; developer-credit aggregation + result-order expectations in the parity leg). No production-code changes required.

## Next Phase Readiness

- 04-05 wires `ProcessingDone`'s ELM settlement leg: fetch envelopes → `ElmWindowFromEnvelopeJson` per subtask → `ElmSettlementData` → the extended `AsyncPayEscrow` — every building block is now unit-proven, so the E2E only needs to prove the WIRING (and D-05's live refund)

---
*Phase: 04-grid-integration-e2e-proof*
*Completed: 2026-09-14*
