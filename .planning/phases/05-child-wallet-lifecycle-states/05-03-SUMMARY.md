---
phase: 05-child-wallet-lifecycle-states
plan: 03
subsystem: account/transaction-manager
tags: [transaction-manager, genius-node, detach, revoke, replace-main]
dependency-graph:
  requires:
    - "SGTransaction::RegistrationTx.detach_flag/.supersedes_sequence (Plan 01)"
    - "SGTransaction::RevokeTx, RevokeTransaction class (Plan 01)"
    - "transaction_parsers[\"revoke\"], FilterRegistration gate 3b, CheckParentChildAuthority revoke branch (Plan 02)"
  provides:
    - "TransactionManager::DetachChild (2 overloads)"
    - "TransactionManager::ReplaceMain (2 overloads)"
    - "TransactionManager::RevokeChild"
    - "GeniusNode::DetachChild (2 overloads)"
    - "GeniusNode::ReplaceMain (2 overloads)"
    - "GeniusNode::RevokeChild (2 overloads incl. WaitForFinalized timeout variant)"
  affects:
    - "SuperGenius/src/account/TransactionManager.hpp"
    - "SuperGenius/src/account/TransactionManager.cpp"
    - "SuperGenius/src/account/GeniusNode.hpp"
    - "SuperGenius/src/account/GeniusNode.cpp"
tech-stack:
  added: []
  patterns:
    - "128-char zero-sentinel address (kZeroAddress) used for Detach's main_address instead of a special-cased empty/null value, so FilterRegistration's existing exact-128-char gate needs no branching"
    - "Auto-derive overloads fail closed (std::errc::invalid_argument) when no prior reg/ record exists, unlike RegisterChild's auto-derive which defaults to sequence=1 — lifecycle-change txs always require a record to supersede"
    - "Two-layer wrapper convention (state-check -> delegate -> log -> return) reused verbatim for child-self-signed ops (RegisterChild shape) and main-acting-on-child ops (RecoverFromChild shape, incl. WaitForFinalized timeout overload)"
key-files:
  created: []
  modified:
    - SuperGenius/src/account/TransactionManager.hpp
    - SuperGenius/src/account/TransactionManager.cpp
    - SuperGenius/src/account/GeniusNode.hpp
    - SuperGenius/src/account/GeniusNode.cpp
decisions:
  - "DetachChild/ReplaceMain auto-derive overloads return outcome::failure(std::errc::invalid_argument) when no prior reg/ record exists, deliberately diverging from RegisterChild's auto-derive (which defaults to sequence=1 when absent) — there is nothing to detach from or replace"
  - "RevokeChild's client-side fail-fast checks absence, deserialization failure, cast failure, AND existing_reg->GetDetachFlag()==true as equivalent invalid_argument outcomes, avoiding broadcast of a transaction CheckParentChildAuthority (Plan 02) would reject anyway"
  - "RevokeChild uses FillDAGStruct() (own address as source), never FillDAGStructForAddress — main is Revoke's own signer/src, unlike RecoverFromChild's child-sourced-but-main-signed transfer"
metrics:
  duration: ~25min
  completed: 2026-07-21
status: complete
---

# Phase 5 Plan 3: DetachChild/ReplaceMain/RevokeChild Caller-Facing Methods Summary

Added the child-initiated `DetachChild`/`ReplaceMain` and main-initiated `RevokeChild` methods at both `TransactionManager` and `GeniusNode` layers, using the exact two-layer convention already established by `RegisterChild`/`RecoverFromChild` — these are the methods that actually let a child (or main) trigger a lifecycle transition; Plans 01-02 only built the underlying transaction types and consensus/CRDT wiring.

## What Was Built

**Task 1 — `TransactionManager::DetachChild`/`ReplaceMain`/`RevokeChild`:**
- Declared six new public methods in `TransactionManager.hpp` (Doxygen-commented, citing D-35/D-37/D-36) immediately after `RecoverFromChild`.
- `DetachChild(metadata, sequence, supersedes_sequence)`: `State::READY` guard; builds a local `static const std::string kZeroAddress(128, '0')`; constructs `RegistrationTransaction::New(kZeroAddress, sequence, metadata, FillDAGStruct(), /*detach_flag=*/true, supersedes_sequence)`; signs with `MakeSignature(*account_m)`; enqueues; returns hash.
- `DetachChild(metadata)` (auto-derive): reads `reg/{own_address}` via `globaldb_m->Get` — returns `outcome::failure(std::errc::invalid_argument)` if absent, deserialization fails, or the cast to `RegistrationTransaction` fails; otherwise delegates to the 3-arg overload with `sequence = existing->GetSequence()+1`, `supersedes_sequence = existing->GetSequence()`.
- `ReplaceMain(new_main_address, metadata, sequence, supersedes_sequence)`: identical shape to `DetachChild`'s 3-arg overload except `main_address = new_main_address` (caller-supplied) and `detach_flag = false`. Handles both Registered->Registered replacement and re-registration from Detached/Revoked uniformly — no branching on the prior record's own `detach_flag`.
- `ReplaceMain(new_main_address, metadata)` (auto-derive): same reg/-lookup + fail-if-absent pattern, delegating to the 4-arg overload.
- `RevokeChild(child_address)`: `State::READY` guard; reads `reg/{child_address}`; returns `invalid_argument` if absent, deserialization fails, cast fails, or `existing_reg->GetDetachFlag()` is already true; otherwise constructs `RevokeTransaction::New(child_address, existing_reg->GetSequence(), FillDAGStruct())` (own address as source — main is Revoke's signer, not `FillDAGStructForAddress`), signs, enqueues, returns hash.

**Task 2 — `GeniusNode::DetachChild`/`ReplaceMain`/`RevokeChild` wrappers:**
- Declared six new public methods in `GeniusNode.hpp` immediately after `RecoverFromChild`'s declarations.
- `DetachChild`/`ReplaceMain` (both overloads each) follow `RegisterChild`'s exact wrapper shape verbatim: `GetTransactionManagerState() != TransactionManager::State::READY` guard returning `Error::TRANSACTIONS_NOT_READY`, `BOOST_OUTCOME_TRY` delegate to the `TransactionManager` counterpart, `node_logger_->debug` log, return `tx_id`. No balance pre-check (these never touch UTXOs).
- `RevokeChild(child_address)` and `RevokeChild(child_address, timeout)` follow `RecoverFromChild`'s exact two-overload shape verbatim: the fire-and-forget overload does state-check + delegate + log + return; the timeout overload calls the fire-and-forget overload then `WaitForFinalized(tx_id, timeout)`, mapping a non-`CONFIRMED` terminal status to `outcome::failure(Error::TRANSACTION_FAILED)`.
- No new `GeniusNode::Error` enum value added — reuses `TRANSACTIONS_NOT_READY`/`TRANSACTION_FAILED` (D-69 precedent).

## Verification Performed

- `grep -c "TransactionManager::DetachChild\|TransactionManager::ReplaceMain\|TransactionManager::RevokeChild" SuperGenius/src/account/TransactionManager.cpp` -> 5 (matches plan expectation).
- `grep -c "GeniusNode::DetachChild\|GeniusNode::ReplaceMain\|GeniusNode::RevokeChild" SuperGenius/src/account/GeniusNode.cpp` -> 6 (matches plan expectation).
- `grep -c 'old_main' SuperGenius/src/account/TransactionManager.hpp SuperGenius/src/account/TransactionManager.cpp` -> 0 for both files (Replace-Main is child-only, no old-main consent parameter, per D-37 prohibition).
- `grep -rc 'GeniusSDKDetach\|GeniusSDKRevoke\|GeniusSDKReplaceMain' GeniusSDK/` -> 0 across all files (no SDK C API wrappers added, per D-72 prohibition/deferred scope).
- `cmake --build SuperGenius/build/Windows/Release --target genius_node_test --config Release` -> succeeds after Task 1 (TransactionManager changes) and again after Task 2 (GeniusNode changes). Only pre-existing `C4834 [[nodiscard]]` warnings at lines outside this plan's edits (same class already noted in Plan 02's summary) — no new warnings from added code.
- Declaration presence confirmed at both layers via targeted grep for all five/six method signatures — all present in both `.hpp` files.

## Deviations from Plan

### Auto-fixed Issues

None - plan executed exactly as written.

## Known Stubs

None. All eleven new methods (`TransactionManager::DetachChild` x2, `ReplaceMain` x2, `RevokeChild` x1; `GeniusNode::DetachChild` x2, `ReplaceMain` x2, `RevokeChild` x2) are fully implemented per the plan's exact specification — no placeholders. Dedicated E2E test coverage is explicitly deferred to Plans 04/05 per this phase's stated test-ownership convention (matching Plan 01/02's precedent).

## Threat Flags

None beyond what the plan's own `<threat_model>` already documents. T-05-06 (ReplaceMain's no-old-main-consent design) is an accepted, explicitly-locked decision (D-37) — verified via the `old_main` grep showing zero occurrences of any old-main parameter. T-05-07 (RevokeChild DoS via repeated calls against a non-existent/already-detached target) is mitigated exactly as specified — client-side fail-fast before any signing/broadcast. No new network endpoints, auth paths, or trust-boundary changes beyond the plan's own register.

## Self-Check: PASSED

- FOUND: SuperGenius/src/account/TransactionManager.hpp (modified)
- FOUND: SuperGenius/src/account/TransactionManager.cpp (modified)
- FOUND: SuperGenius/src/account/GeniusNode.hpp (modified)
- FOUND: SuperGenius/src/account/GeniusNode.cpp (modified)
- FOUND: commit 59736cad (Task 1)
- FOUND: commit 10abc4a6 (Task 2)
