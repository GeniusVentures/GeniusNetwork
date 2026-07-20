---
phase: 03-parent-child-transfer-authority
plan: 02
subsystem: consensus
tags: [consensus, gate, signature, transfer, cpp, security]

# Dependency graph
requires:
  - phase: 03-parent-child-transfer-authority (plan 01)
    provides: "Blockchain::CheckCertifiedParent(child_addr) -> optional<main_addr>, GeniusTransaction::CheckSignatureAgainst(address)"
provides:
  - "TransactionManager::CheckParentChildAuthority(tx) consensus gate, wired into ValidateTransactionForConsensus"
  - "CheckTransactionAuthorization extended with the D-60 certified-main whole-tx signature branch"
  - "GeniusInputValidator::ValidateWitness per-input signature check extended with the matching D-60 OR-branch"
affects: [03-03-recover-from-child, 03-04-regression-tests]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Gate-list pattern in ValidateTransactionForConsensus extended with a new CheckParentChildAuthority call between CheckTransactionAuthorization and CheckTransactionTimestamp, matching the exact reject-and-log shape of every neighboring gate"
    - "Additive OR-branch signature acceptance: original fast-path (child's own key) unchanged, new certified-main branch only tried when the original fails and tx.GetType() == \"transfer\""

key-files:
  created: []
  modified:
    - SuperGenius/src/account/TransactionManager.hpp
    - SuperGenius/src/account/TransactionManager.cpp
    - SuperGenius/src/account/GeniusInputValidator.cpp

key-decisions:
  - "CheckParentChildAuthority re-derives tx.CheckSignature() as a cheap branch selector (not redundant verification work) to distinguish REGR-01/02 child-self-signed spends from CONS-02 certified-main-delegated recovery, since both cases share src = certified-child-address"
  - "D-21 destination restriction implemented as exact string equality against params->second.front().dest_address (the primary/first output, per the CreateTxParameter/RecoverFromChild primary-output-first convention) - fails closed (reject) on empty/missing UTXO parameters"
  - "GeniusInputValidator.cpp's owner-address check (delegated_escrow_spend block) left byte-for-byte untouched per RESEARCH.md's Critical Gap analysis - it naturally passes for D-60 recovery txs since payload_owner == child_addr == tx->GetSrcAddress()"

requirements-completed: [CONS-01, CONS-02, CONS-06]

coverage:
  - id: D1
    description: "CheckTransactionAuthorization accepts a certified-main-signed whole-tx signature for a transfer whose src is a certified registered child, unchanged for every other case"
    requirement: "CONS-06"
    verification:
      - kind: unit
        ref: "grep -c 'CheckSignatureAgainst' SuperGenius/src/account/TransactionManager.cpp == 1"
        status: pass
      - kind: integration
        ref: "cmake --build SuperGenius/build/Windows/Release --target registration_transaction_test --config Release"
        status: pass
    human_judgment: false
  - id: D2
    description: "CheckParentChildAuthority gate exists, is wired into ValidateTransactionForConsensus at the verified insertion point, and implements the three-case gate logic (not-a-child, child-self-signed, certified-main-delegated)"
    requirement: "CONS-01"
    verification:
      - kind: unit
        ref: "grep -c 'bool TransactionManager::CheckParentChildAuthority' SuperGenius/src/account/TransactionManager.cpp == 1; grep -c 'CheckParentChildAuthority( *tx )' SuperGenius/src/account/TransactionManager.cpp == 1"
        status: pass
      - kind: integration
        ref: "SuperGenius/build/Windows/Release/test_bin/Release/registration_transaction_test.exe (18 tests from 2 test suites)"
        status: pass
    human_judgment: false
  - id: D3
    description: "GeniusInputValidator::ValidateWitness per-input check accepts a certified-main-delegated signature for a certified child's src, with the owner-address check and delegated_escrow_spend block left unmodified"
    requirement: "CONS-02"
    verification:
      - kind: unit
        ref: "grep -c 'CheckCertifiedParent' SuperGenius/src/account/GeniusInputValidator.cpp == 1; grep -n 'delegated_escrow_spend' SuperGenius/src/account/GeniusInputValidator.cpp | wc -l unchanged (2)"
        status: pass
      - kind: integration
        ref: "SuperGenius/build/Windows/Release/test_bin/Release/registration_transaction_test.exe (18 tests from 2 test suites, includes pre-existing consensus/transfer/registration regression coverage)"
        status: pass
    human_judgment: false

duration: 50min
completed: 2026-07-20
status: complete
---

# Phase 3 Plan 02: Parent-Child Consensus Gate + D-60 Signature Extension Summary

**Extended `CheckTransactionAuthorization` and `GeniusInputValidator::ValidateWitness`'s per-input signature check with the narrow D-60 certified-main OR-branch, and added the new `CheckParentChildAuthority` gate enforcing D-21's destination restriction — all three call sites additive, zero behavior change for non-certified-child transactions**

## Performance

- **Duration:** ~50 min (includes an incremental C++ build and a full ~26-minute registration_transaction_test.exe run)
- **Started:** 2026-07-20T22:58:00Z (approx, following Plan 01's completion)
- **Completed:** 2026-07-20T23:52:17Z
- **Tasks:** 3 completed
- **Files modified:** 3

## Accomplishments
- `CheckTransactionAuthorization` (`TransactionManager.cpp:4066-4076` originally) now tries a narrow additional branch when neither `tx.CheckSignature()` nor `tx.CheckDAGSignatureLegacy()` verifies: for `"transfer"` txs, look up `blockchain_->CheckCertifiedParent(tx.GetSrcAddress())` and, if certified, verify `tx.CheckSignatureAgainst(*certified_main)` — accepting a main-signed recovery transaction whose declared `src` is a certified registered child
- New public `TransactionManager::CheckParentChildAuthority(const GeniusTransaction &tx) const` gate implements the full D-64 three-case dispatch: non-`"transfer"` txs and txs whose src isn't a certified registered child are approved unconditionally; a certified-child-src tx whose whole-tx signature verifies against the child's own key (REGR-01/02) is approved with no destination restriction; otherwise (the certified-main-delegated case) the primary output's `dest_address` must exactly equal the certified main address (D-21) or the tx is rejected
- Gate wired into `ValidateTransactionForConsensus` at the verified `3988-3997` insertion point, between `CheckTransactionAuthorization` and `CheckTransactionTimestamp`, using the identical reject-and-log shape as every neighboring gate
- `GeniusInputValidator::ValidateWitness`'s per-input signature check (`GeniusInputValidator.cpp:357-366` originally) extended with the matching OR-branch: `sig_ok` (original check, unchanged) OR, for `TRANSFER_TX_TYPE` txs, `delegated_sig_ok` (signature verifies against `blockchain->CheckCertifiedParent(tx->GetSrcAddress())`'s returned main address). The owner-address check and `delegated_escrow_spend` block a few lines below (`:419-432`) were left byte-for-byte unchanged, confirmed via `grep -n delegated_escrow_spend` returning the same count (2) before and after
- Full build (`registration_transaction_test` target) and full test run (`registration_transaction_test.exe`) both green: 18/18 tests passed, exit code 0, confirming zero regression in the shared consensus-pipeline code paths this plan modified

## Task Commits

Each task was committed atomically inside the `SuperGenius` submodule:

1. **Task 1: Extend CheckTransactionAuthorization with the D-60 certified-main whole-tx signature branch** - `32e38b5e` (feat)
2. **Task 2: Add CheckParentChildAuthority gate and insert into ValidateTransactionForConsensus** - `93536f5b` (feat)
3. **Task 3: Extend GeniusInputValidator's per-input signature check with the matching D-60 branch** - `b5ccbd4a` (feat)

**SuperGenius submodule pointer bump (outer repo):** `52d834e` (chore)

**Plan metadata:** committed separately after this SUMMARY (docs: complete plan)

_Note: this is a sequential (non-worktree) executor because the plan touches the `SuperGenius` git submodule — each task commit is a real commit inside `SuperGenius`, and the outer `GeniusNetwork` repo tracks the resulting submodule pointer with its own dedicated commit._

## Files Created/Modified
- `SuperGenius/src/account/TransactionManager.hpp` - declares `bool CheckParentChildAuthority( const GeniusTransaction &tx ) const;` in the public section, immediately after `CheckTransactionAuthorization`
- `SuperGenius/src/account/TransactionManager.cpp` - extends `CheckTransactionAuthorization` with the D-60 OR-branch; implements `CheckParentChildAuthority`; inserts the gate call into `ValidateTransactionForConsensus`
- `SuperGenius/src/account/GeniusInputValidator.cpp` - extends the per-input signature check in `ValidateWitness` with the matching D-60 OR-branch; owner-address check block left unmodified

## Decisions Made
- `CheckParentChildAuthority` calls `tx.CheckSignature()` again as a branch selector, not redundant security work — `CheckTransactionAuthorization` already established earlier in the pipeline that either the child's own key or the certified main's key verified; this call just determines which one, to decide whether the destination restriction applies
- D-21 destination equality checked against `params->second.front().dest_address` (exact string match, no normalization), matching the `CreateTxParameter`/`RecoverFromChild` "primary output first" convention documented in RESEARCH.md and PATTERNS.md
- Fail-closed on malformed/empty UTXO parameters in the certified-main-delegated branch (`!params.has_value() || params->second.empty()` → reject) rather than assuming a well-formed transaction
- Split the single combined edit to `TransactionManager.cpp`/`.hpp` into two separate task commits (Task 1's `CheckTransactionAuthorization` extension, then Task 2's `CheckParentChildAuthority` gate + insertion) by temporarily reverting Task 2's portion, committing Task 1 alone, then restoring and committing Task 2 — this kept each git commit scoped exactly to its plan task despite both changes landing in the same file during implementation

## Deviations from Plan

None - plan executed exactly as written. All three tasks' acceptance criteria were verified against current source (exact line numbers 4066-4076, 3966-4033, 357-366/419-432 all matched the plan's `read_first` claims with zero drift), and all automated verification greps specified in the plan passed on the first attempt.

## Issues Encountered
None. The full `registration_transaction_test.exe` run (18 tests, ~26 minutes) completed cleanly with exit code 0 — no segfault-on-teardown was observed in this run (the known pre-existing libp2p/boost::asio teardown issue tracked in STATE.md did not manifest this time, but is unrelated to this plan's changes regardless).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `CheckParentChildAuthority`, the extended `CheckTransactionAuthorization`, and the extended `ValidateWitness` per-input check are all compiled and test-verified (full `registration_transaction_test` build + 18/18 test run)
- Plan 03 (`RecoverFromChild`) can now build transactions with `src = child_addr`, `dst = main_addr`, signed by main's own key — this plan's gate and signature extensions are the only consensus-side prerequisite, and both are in place
- Plan 04's new targeted test cases (`MainFundsChildApprovedByGate`, `MainRecoversFromChildApproved`, `MainRecoveryWrongDestinationRejected`, `ChildTransferToArbitraryAndMainUnaffected`, `ChildTransferToDevWalletUnaffected`, `ChildCannotClaimMainAsSourceRejected`) can now exercise this plan's gate logic directly
- No blockers carried forward beyond the pre-existing `child_registration_test.exe` teardown segfault issue already tracked in STATE.md (unaffected by this plan)

---
*Phase: 03-parent-child-transfer-authority*
*Completed: 2026-07-20*

## Self-Check: PASSED

- FOUND: `SuperGenius/src/account/TransactionManager.hpp`
- FOUND: `SuperGenius/src/account/TransactionManager.cpp`
- FOUND: `SuperGenius/src/account/GeniusInputValidator.cpp`
- FOUND: `.planning/phases/03-parent-child-transfer-authority/03-02-SUMMARY.md`
- FOUND: SuperGenius commit `32e38b5e` (Task 1)
- FOUND: SuperGenius commit `93536f5b` (Task 2)
- FOUND: SuperGenius commit `b5ccbd4a` (Task 3)
- FOUND: GeniusNetwork commit `52d834e` (submodule pointer bump)
