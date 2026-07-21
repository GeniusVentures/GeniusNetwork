---
phase: 05-child-wallet-lifecycle-states
plan: 02
subsystem: account/consensus
tags: [consensus, crdt-filter, transaction-manager, revoke, detach, fork-prevention]
dependency-graph:
  requires:
    - "SGTransaction::RegistrationTx.detach_flag/.supersedes_sequence (Plan 01)"
    - "SGTransaction::RevokeTx, EmbeddedTransaction.revoke oneof arm 9 (Plan 01)"
    - "RegistrationTransaction::GetDetachFlag()/GetSupersedesSequence() (Plan 01)"
    - "RevokeTransaction class (Plan 01)"
  provides:
    - "transaction_parsers[\"revoke\"] dispatch entry"
    - "TransactionManager::ParseRevokeTransaction(...) / RevertRevokeTransaction(...)"
    - "DeSerializeEmbeddedTransaction's case EmbeddedTransaction::kRevoke"
    - "FilterRegistration gate 3b (supersedes_sequence fork-prevention, D-38)"
    - "CheckParentChildAuthority's \"revoke\" branch"
  affects:
    - "SuperGenius/src/account/TransactionManager.hpp"
    - "SuperGenius/src/account/TransactionManager.cpp"
tech-stack:
  added: []
  patterns:
    - "Per-node local side-effect derivation (ParseRevokeTransaction mirrors PutProducedUTXOs — apply a locally-derived reg/ mutation after independent consensus validation, bypassing FilterRegistration's peer-delta-only filter path)"
    - "Scope-lifted shared_ptr reused across two sibling gates in the same do{}while(0) filter body (avoids duplicate CRDT read/deserialize)"
key-files:
  created: []
  modified:
    - SuperGenius/src/account/TransactionManager.hpp
    - SuperGenius/src/account/TransactionManager.cpp
decisions:
  - "ParseRevokeTransaction tolerates an absent/mismatched reg/{child_addr} record by logging a warning and returning success, rather than failing the whole confirmed-transaction pipeline — CheckParentChildAuthority already guaranteed a valid Registered record existed at validation time"
  - "Gate 3b's supersedes_sequence check is unconditional on transaction sub-kind (no detach_flag branching) — per design doc §9.3, it uniformly covers Detach, Replace-Main, and any future lifecycle-change tx with a non-zero supersedes_sequence"
  - "CheckParentChildAuthority's revoke branch deliberately does not call blockchain_->CheckCertifiedParent — reg/{child_addr} was already gated into this node's CRDT view by FilterRegistration's own gate (b) child-signature check, so re-gating on consensus certification here would be redundant"
metrics:
  duration: ~30min
  completed: 2026-07-21
status: complete
---

# Phase 5 Plan 2: Revoke Dispatch Wiring + Fork-Prevention Gate Summary

Wired the new "revoke" transaction type into every dispatch point `TransactionManager` uses to recognize, apply, and gate transaction types (closing the exact "Unknown tx type" class of bug Phase 3 found for "registration"), added the `FilterRegistration` gate 3b `supersedes_sequence` fork-prevention check (D-38), and added `CheckParentChildAuthority`'s dedicated "revoke" authority branch.

## What Was Built

**Task 1 — "revoke" dispatch wiring + real ParseRevokeTransaction:**
- Added `#include "RevokeTransaction.hpp"` to `TransactionManager.cpp`.
- Added a `transaction_parsers["revoke"]` entry pointing at `ParseRevokeTransaction`/`RevertRevokeTransaction`, immediately after the existing `"registration"` entry — this is the exact dispatch-table membership check `CheckTransactionWellFormed` uses; without it every RevokeTx would be rejected as "Unknown tx type" before ever reaching consensus validation.
- `DeSerializeEmbeddedTransaction`'s `registered` lambda now registers `"revoke"` via `RevokeTransaction::DeSerializeByteVector`, and a new `case EmbeddedTransaction::kRevoke:` dispatches through `GetDeSerializers().at("revoke")`, following the exact 3-line shape of every other case.
- Implemented `ParseRevokeTransaction` as a real (non-no-op) mutator: reads the target `reg/{child_addr}` record via `globaldb_m->Get`, deserializes it, and — if it exists and is a `RegistrationTransaction` — writes back an updated copy via `globaldb_m->Put` with `detach_flag=true`, preserving `main_address`/`sequence`/`metadata`/`supersedes_sequence` from the existing record untouched. Tolerates an absent or type-mismatched record by logging a warning and returning success (CheckParentChildAuthority already validated a Registered record existed before this RevokeTx was ever confirmed).
- `RevertRevokeTransaction` is a documented no-op — reverting a Revoke would require snapshotting the prior `reg/` state (not tracked); leaving the target Detached on rollback is the conservative, fail-safe default.

**Task 2 — FilterRegistration gate 3b (supersedes_sequence fork-prevention, D-38):**
- Lifted the previously block-scoped `existing_reg` local (inside gate (d)'s `if (existing_data.has_value())` block) to the enclosing `do{}while(0)` scope, so the new gate 3b reuses the same already-fetched/parsed value without a second CRDT read or a second `DeSerializeTransaction` call.
- Added gate 3b immediately after gate (d): if `reg_tx->GetSupersedesSequence() != 0`, requires `existing_reg` to be non-null AND `reg_tx->GetSupersedesSequence() == existing_reg->GetSequence()` — otherwise logs an error and tombstones the element (via the existing `should_delete = true` default). This single condition governs Detach and Replace-Main uniformly, per design doc §9.3.
- Updated the `FilterRegistration` Doxygen comment in `TransactionManager.hpp` to document gate (e).

**Task 3 — CheckParentChildAuthority "revoke" branch:**
- Restructured `CheckParentChildAuthority` from `if (tx.GetType() != "transfer") { return true; } ...` into an explicit three-way dispatch: `"transfer"` branch (unchanged logic), new `"revoke"` branch, and a catch-all `return true` fallthrough for every other type (mint, escrow-hold, registration, etc.) — preserving prior behavior for all non-transfer/non-revoke types.
- New revoke branch: `dynamic_cast<const RevokeTransaction *>` the tx (reject if null), look up `reg/{child_addr}` via `globaldb_m->Get` + `DeSerializeTransaction` + `dynamic_pointer_cast<RegistrationTransaction>` (reject if absent/wrong-type/cast-fails), then reject if `existing_reg->GetDetachFlag()` is true, or `existing_reg->GetMainAddress() != tx.GetSrcAddress()`, or `revoke_tx->GetRegistrationSequence() != existing_reg->GetSequence()`. Approves otherwise.
- Deliberately does NOT call `blockchain_->CheckCertifiedParent` for revoke (unlike the transfer branch) — the `reg/{child_addr}` record it reads was itself only ever accepted into this node's CRDT view by passing `FilterRegistration`'s own gate (b) child-signature check, so re-gating on consensus certification here would be redundant.
- `GeniusInputValidator.cpp` / `CheckTransactionAuthorization`'s signature-verification model is untouched — confirmed via grep (0 references to `"revoke"` in `GeniusInputValidator.cpp`).

## Verification Performed

- `grep -c "\"revoke\"" SuperGenius/src/account/TransactionManager.cpp` → 3 (transaction_parsers entry, RegisterDeserializer call, DeSerializeEmbeddedTransaction `.at("revoke")` call) — meets the plan's "at least 3" threshold.
- `grep -c "EmbeddedTransaction::kRevoke" SuperGenius/src/account/TransactionManager.cpp` → 1.
- `grep -c "GetSupersedesSequence() != 0" SuperGenius/src/account/TransactionManager.cpp` → 1.
- `grep -c 'GetType() == "revoke"' SuperGenius/src/account/TransactionManager.cpp` → 1; `grep -c 'GetRegistrationSequence() != existing_reg->GetSequence()' SuperGenius/src/account/TransactionManager.cpp` → 1.
- `grep -c 'GetType() == "revoke"' SuperGenius/src/account/GeniusInputValidator.cpp` → 0 (signature-verification model confirmed untouched).
- `cmake --build SuperGenius/build/Windows/Release --target genius_node_test --config Release` — succeeds cleanly (only pre-existing, unrelated `C4834 [[nodiscard]]` warnings at lines outside this plan's edits).
- `cmake --build SuperGenius/build/Windows/Release --target registration_transaction_test --config Release` — succeeds cleanly.

## Deviations from Plan

### Auto-fixed Issues

None - plan executed exactly as written.

### Test-run note (not a code deviation)

The plan's overall `<verification>` section asks to run `registration_transaction_test.exe` after building. This binary's `RegistrationTransactionE2ETest` fixture instantiates a real `GossipPubSub`/`PubSubBroadcasterExt` networking stack (address-refresh cycles logged every ~30s, "No addresses found for broadcasting" warning), and the run was observed idling (near-zero CPU time across ~10+ minutes wall-clock) during process bring-up before any GTest `[ RUN ]` line was ever emitted — consistent with the project's already-documented class of test-binary networking/lifecycle hangs (see `.planning/phases/01-child-balance-query/deferred-items.md`'s `child_registration_test.exe` teardown-segfault issue, and PROJECT.md's "Known Issues"). This appears to be pre-existing test-infrastructure behavior unrelated to this plan's code changes (none of Task 1-3's changes touch thread/lifecycle management, `GossipPubSub`, or `PubSubBroadcasterExt`). The process was terminated after confirming it was not making CPU progress, rather than left blocking indefinitely. Both build targets compiled and linked successfully, and all `<task>`-level automated verify steps (grep + `cmake --build`) passed. Running the full E2E suite to completion is deferred — flagged below for phase-level follow-up, matching the existing `child_registration_test.exe` deferred-items precedent.

## Known Stubs

None. `ParseRevokeTransaction`, `FilterRegistration` gate 3b, and `CheckParentChildAuthority`'s revoke branch are fully implemented per the plan's exact specification — no placeholders.

## Threat Flags

None beyond what the plan's own `<threat_model>` already documents (T-05-03/T-05-04/T-05-05 mitigations were implemented exactly as specified — main-signer + detach_flag + sequence-match gate, post-authority-gate local write, and gate 3b + nonce chain fork prevention respectively). No new network endpoints, auth paths, or trust-boundary changes beyond the plan's own register.

## Self-Check: PASSED

- FOUND: SuperGenius/src/account/TransactionManager.hpp (modified)
- FOUND: SuperGenius/src/account/TransactionManager.cpp (modified)
- FOUND: commit 5baa98e6 (Task 1)
- FOUND: commit be88ffd4 (Task 2)
- FOUND: commit 3e60ddd9 (Task 3)
