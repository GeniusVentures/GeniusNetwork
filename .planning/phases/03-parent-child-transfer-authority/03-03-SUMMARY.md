---
phase: 03-parent-child-transfer-authority
plan: 03
subsystem: consensus
tags: [consensus, transfer, recovery, utxo, cpp]

# Dependency graph
requires:
  - phase: 03-parent-child-transfer-authority (plan 01)
    provides: "Blockchain::CheckCertifiedParent(child_addr) -> optional<main_addr>, GeniusTransaction::CheckSignatureAgainst(address)"
  - phase: 03-parent-child-transfer-authority (plan 02)
    provides: "TransactionManager::CheckParentChildAuthority gate, CheckTransactionAuthorization D-60 branch, ValidateWitness D-60 branch"
provides:
  - "TransactionManager::RecoverFromChild(child_address, amount, token_id) — main-signed, child-scoped recovery transaction construction"
  - "GeniusNode::RecoverFromChild two-overload thin wrapper (fire-and-return, wait-for-finalized)"
affects: [03-04-regression-tests]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "FillDAGStructForAddress(source_address) — a parameterized sibling of FillDAGStruct() that derives nonce from account_m->GetPeerNonce(source_address) instead of ReserveNextNonce(), and scopes the previous-hash lookup (tx_processed_m scan + CRDT network scan) to source_address instead of account_m->GetAddress(); intentionally skips the persisted-local-confirmed-hash tier since that cache is main-local-only and has no meaning for a non-owned child address"
    - "Manual InputUTXOInfo construction + explicit account_m->Sign(...) per input (mirroring the existing escrow-payout pattern) instead of routing through UTXOManager::CreateTxParameter/SelectUTXOs, which only ever read the manager's own bound address"

key-files:
  created: []
  modified:
    - SuperGenius/src/account/TransactionManager.hpp
    - SuperGenius/src/account/TransactionManager.cpp
    - SuperGenius/src/account/GeniusNode.hpp
    - SuperGenius/src/account/GeniusNode.cpp

key-decisions:
  - "Added a new private TransactionManager::FillDAGStructForAddress(source_address) helper rather than overloading FillDAGStruct() itself — keeps the existing no-arg FillDAGStruct() (used by TransferFunds and the escrow payout path) completely untouched while giving RecoverFromChild its own child-scoped nonce/previous-hash derivation"
  - "UTXO selection built directly from GetUnconsumedUTXOs(child_address), filtered by token_id, with an early-stop once the running total covers the requested amount — mirrors SelectUTXOs's early-stop behavior without needing to call the private, main-scoped SelectUTXOs/CreateTxParameter"
  - "Primary output {amount, main's own address, token_id} is always pushed first (before any change output) — required so Plan 02's CheckParentChildAuthority gate, which reads params->second.front().dest_address for the D-21 destination check, sees the correct primary recipient"
  - "Change output (when selected_amount > amount) is explicitly {change, child_address, token_id} — routes leftover child balance back to the child, never to main's own address"
  - "GeniusNode::RecoverFromChild's balance pre-check uses the address-parameterized GetBalance(token_id, child_address) overload (the child's own balance), matching Phase 1's GetChildBalance argument-order convention (token first, address second) — not the no-arg overload, which would check main's own balance"

requirements-completed: [CONS-02]

coverage:
  - id: D1
    description: "TransactionManager::RecoverFromChild builds a transaction with src=child_address, primary output {amount, main's own address, token_id}, and (if applicable) a change output {change, child_address, token_id}, spending only child_address's own unconsumed UTXOs and signed (whole-tx + every per-input) with main's own key"
    requirement: "CONS-02"
    verification:
      - kind: unit
        ref: "grep -c 'outcome::result<std::string> TransactionManager::RecoverFromChild' SuperGenius/src/account/TransactionManager.cpp == 1; grep -c 'GetUnconsumedUTXOs( child_address )' SuperGenius/src/account/TransactionManager.cpp == 1"
        status: pass
      - kind: integration
        ref: "cmake --build SuperGenius/build/Windows/Release --target genius_node_test --config Release"
        status: pass
    human_judgment: false
  - id: D2
    description: "GeniusNode::RecoverFromChild (both overloads) checks the child's own balance via the address-parameterized GetBalance(token_id, child_address) overload and delegates to TransactionManager::RecoverFromChild"
    requirement: "CONS-02"
    verification:
      - kind: unit
        ref: "grep -c 'GeniusNode::RecoverFromChild' SuperGenius/src/account/GeniusNode.cpp == 2; grep -c 'GetBalance( token_id, child_address )' SuperGenius/src/account/GeniusNode.cpp == 2"
        status: pass
      - kind: integration
        ref: "cmake --build SuperGenius/build/Windows/Release --target registration_transaction_test --config Release; SuperGenius/build/Windows/Release/test_bin/Release/registration_transaction_test.exe (18/18 passed)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Nonce is derived from account_m->GetPeerNonce(child_address) (never ReserveNextNonce), and the DAGStruct's source_addr is child_address (never account_m->GetAddress())"
    requirement: "CONS-02"
    verification:
      - kind: unit
        ref: "Read of FillDAGStructForAddress implementation — no ReserveNextNonce() call, dag.set_source_addr( source_address ) not account_m->GetAddress()"
        status: pass
    human_judgment: false

duration: 65min
completed: 2026-07-20
status: complete
---

# Phase 3 Plan 03: RecoverFromChild Transaction Construction Summary

**Added `TransactionManager::RecoverFromChild` and `GeniusNode::RecoverFromChild` — the one new transfer-construction method this phase introduces (D-62), building a `TransferTransaction` with `src = child_address`, `dst = main's own address`, spending only the child's own UTXOs, and signed with main's own key so Plan 02's `CheckParentChildAuthority`/`CheckTransactionAuthorization`/`ValidateWitness` extensions can approve it**

## Performance

- **Duration:** ~65 min (includes an incremental C++ build, a full ~26-minute `registration_transaction_test.exe` run, and a re-run after an interrupted first attempt for clean verification)
- **Completed:** 2026-07-20
- **Tasks:** 2 completed
- **Files modified:** 4

## Accomplishments
- `TransactionManager::RecoverFromChild(child_address, amount, token_id)` — new public method that:
  1. Iterates `account_m->GetUTXOManager().GetUnconsumedUTXOs(child_address)`, filters to the requested `token_id`, and builds `InputUTXOInfo` entries (each signed via `account_m->Sign(input.SerializeForSigning())`) with an early-stop once the running total covers `amount`; returns `std::errc::invalid_argument` if the child's UTXOs are insufficient — never touches `CreateTxParameter`/`SelectUTXOs`, which are main-scoped only
  2. Builds outputs primary-first: `{amount, account_m->GetAddress(), token_id}`, then (if there's leftover) a change output `{selected_amount - amount, child_address, token_id}` — change always returns to the child, never to main
  3. Builds a child-scoped `DAGStruct` via the new `FillDAGStructForAddress(child_address)` helper (see below) instead of the main-scoped `FillDAGStruct()`
  4. Signs the whole transaction with `MakeSignature(*account_m)` (main signs, per D-60 — this line is directly reused from `TransferFunds`), reserves the selected UTXOs, enqueues, and returns the hash
- New private `TransactionManager::FillDAGStructForAddress(const std::string &source_address)` — a parameterized sibling of `FillDAGStruct()`. Derives `nonce` from `account_m->GetPeerNonce(source_address)` (value + 1 if present, else 0 — matching the exact convention `EvaluateTransactionReplayProtection` reads), and re-runs the previous-hash lookup (tx_processed_m scan, then CRDT network scan via `GetMonitoredNetworkIDs()`/`QueryKeyValues`) scoped to `source_address` instead of `account_m->GetAddress()`. Deliberately skips the persisted-local-confirmed-hash tier (`account_m->GetLocalConfirmedTxHash`), since that cache is main-local-only and meaningless for a non-owned child address. `FillDAGStruct()` itself is completely untouched.
- `GeniusNode::RecoverFromChild` — two overloads (fire-and-return, wait-for-finalized-with-timeout) mirroring `TransferFunds`'s exact two-overload shape. The fire-and-return overload's balance pre-check uses `account_->GetUTXOManager().GetBalance(token_id, child_address)` (the child's own balance, address-parameterized) rather than the no-arg overload, which would check main's own balance.
- Both files compile cleanly as part of `genius_node`/`genius_node_test`; full `registration_transaction_test` build + run confirms zero regressions in the shared consensus-pipeline code paths touched by Plans 01/02 (this plan adds new methods but modifies no existing gate/validator logic).

## Task Commits

Each task was committed atomically inside the `SuperGenius` submodule:

1. **Task 1: Add TransactionManager::RecoverFromChild** - `0cccc6fc` (feat)
2. **Task 2: Add GeniusNode::RecoverFromChild (two-overload thin wrapper)** - `3b66c1df` (feat)

**SuperGenius submodule pointer bump (outer repo):** committed alongside this SUMMARY (see final commit)

_Note: this is a sequential (non-worktree) executor because the plan touches the `SuperGenius` git submodule — each task commit is a real commit inside `SuperGenius`, and the outer `GeniusNetwork` repo tracks the resulting submodule pointer with its own dedicated commit._

## Files Created/Modified
- `SuperGenius/src/account/TransactionManager.hpp` - declares `RecoverFromChild(std::string child_address, uint64_t amount, TokenID token_id)` in the public section (immediately after the two `RegisterChild` overloads) and the private `FillDAGStructForAddress(const std::string &source_address)` helper (immediately after `FillDAGStruct`)
- `SuperGenius/src/account/TransactionManager.cpp` - implements `RecoverFromChild` (placed immediately after `TransferFunds`) and `FillDAGStructForAddress` (placed immediately after `FillDAGStruct`)
- `SuperGenius/src/account/GeniusNode.hpp` - declares both `GeniusNode::RecoverFromChild` overloads (immediately after `RegisterChild`'s two-overload block), mirroring `TransferFunds`'s pair
- `SuperGenius/src/account/GeniusNode.cpp` - implements both overloads (placed immediately after `TransferFunds`), the wait-for-finalized overload calling the fire-and-return overload then `WaitForFinalized`, byte-for-byte matching `TransferFunds`'s timeout-overload control flow

## Decisions Made
- Chose a new dedicated `FillDAGStructForAddress` helper over overloading/modifying `FillDAGStruct()` itself, per the plan's explicit guidance — keeps every existing caller of `FillDAGStruct()` (unchanged `TransferFunds`, the escrow payout path) completely untouched, with zero risk of accidentally corrupting main's own nonce sequence
- Followed the plan's explicit "primary output first" ordering requirement, since Plan 02's `CheckParentChildAuthority` gate reads `params->second.front().dest_address` for its D-21 destination check
- Reused the manual `InputUTXOInfo` + `account_m->Sign(...)` idiom from the existing escrow-payout code (`TransactionManager.cpp` escrow block) rather than inventing a new signing helper — this was already the established pattern for "main signs an input regardless of whose UTXO it nominally is"

## Deviations from Plan

None — plan executed exactly as written. Both tasks' acceptance criteria were verified against current source with zero drift from the plan's `read_first` line-number claims, and both automated verification greps specified in the plan (`RecoverFromChild` count, `GetUnconsumedUTXOs( child_address )` count for Task 1; `GeniusNode::RecoverFromChild` count, `GetBalance( token_id, child_address )` count for Task 2) passed on the first attempt.

## Issues Encountered

**Test-run verification took two attempts due to background-process log-buffering ambiguity, not a code issue.** The first `registration_transaction_test.exe` run was launched in the background per this session's tooling; its captured log file stopped mid-suite (after 2 of 18 tests) even though the process had already exited, which is consistent with Windows' fully-buffered (non-console) stdout losing unflushed buffer contents on abnormal process termination — not evidence of an actual regression, just an artifact of output capture under a redirected/backgrounded run. A clean re-run (redirected to a dedicated log file with an explicit trailing `echo EXITCODE:$?`) produced an unambiguous result: **`[  PASSED  ] 18 tests.`** immediately followed by **`EXITCODE:139`** (SIGSEGV) during process teardown, after every GTest assertion had already reported success and after the final `GlobalDB shutdown finished` log line. This exactly matches the known pre-existing `libp2p`/`boost::asio` thread-joining teardown segfault documented in `STATE.md` and this plan's own `<project_specifics>` guidance ("if you see `[  PASSED  ] N tests` followed by a crash/non-zero exit during shutdown, treat the test as passed") — **treated as a pass, not a regression introduced by this plan.** Stray RocksDB test-fixture directories left behind by the interrupted first run (`CRDT.Datastore.TEST*`, `reg_tx_e2e_test/`, all untracked/gitignored) were cleaned up before the second run and are not present in the final working tree.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `TransactionManager::RecoverFromChild` and both `GeniusNode::RecoverFromChild` overloads are compiled and structurally verified (full `genius_node_test` + `registration_transaction_test` builds, plus the full 18-test `registration_transaction_test.exe` regression run — all passing, zero regressions)
- Plan 04 can now write the new CONS-01/CONS-02/REGR-01/02/03 test cases (`MainFundsChildApprovedByGate`, `MainRecoversFromChildApproved`, `MainRecoveryWrongDestinationRejected`, `ChildTransferToArbitraryAndMainUnaffected`, `ChildTransferToDevWalletUnaffected`, `ChildCannotClaimMainAsSourceRejected`) against this plan's `RecoverFromChild` and Plan 02's gate — this plan's construction-side prerequisite is complete
- Per the phase's requirements-bookkeeping note: CONS-02 is marked complete in this plan's state update, since `RecoverFromChild` is the actual missing construction mechanism the requirement calls for ("main wallet CAN recover funds") — full end-to-end behavioral proof (an actual passing regression test exercising `RecoverFromChild` against the live gate) remains Plan 04's job, and the orchestrator will reconcile if that proof surfaces any gap
- No blockers carried forward beyond the pre-existing `child_registration_test.exe`-family teardown segfault issue already tracked in `STATE.md` (confirmed again in this plan's own test run, unaffected by and unrelated to this plan's changes)

---
*Phase: 03-parent-child-transfer-authority*
*Completed: 2026-07-20*

## Self-Check: PASSED

- FOUND: `SuperGenius/src/account/TransactionManager.hpp`
- FOUND: `SuperGenius/src/account/TransactionManager.cpp`
- FOUND: `SuperGenius/src/account/GeniusNode.hpp`
- FOUND: `SuperGenius/src/account/GeniusNode.cpp`
- FOUND: `.planning/phases/03-parent-child-transfer-authority/03-03-SUMMARY.md`
- FOUND: SuperGenius commit `0cccc6fc` (Task 1)
- FOUND: SuperGenius commit `3b66c1df` (Task 2)
