---
phase: 06-supergenius-merge-regression-verification
plan: 03
subsystem: SuperGenius submodule / CMake build verification (post-merge, still uncommitted)
tags: [build-verification, cmake, msvc, semantic-regression-review, MVER-01]
dependency_graph:
  requires:
    - "06-01: SuperGenius mid-merge state (MERGE_HEAD present), 9 shared files conflict-resolved"
    - "06-02: DevConfig_st -> GeniusNodeConfig rename sweep complete, zero DevConfig_st references repo-wide"
  provides:
    - "genius_node, registration_transaction_test, child_registration_test all build with exit code 0 against the merged, rename-swept, still-uncommitted working tree"
    - "Manual read-through confirmation: zero symbol overlap between origin/develop's bridge-catchup/genesis-registry refactors and child-wallet consensus code (GeniusNode.hpp/.cpp, Blockchain.cpp, TransactionManager.cpp EvaluateTransactionReplayProtection)"
  affects:
    - "06-04 (or Plan 04, whichever plan runs the full regression suite): builds against these freshly-verified binaries; the flagged EvaluateTransactionReplayProtection rewrite is the highest-priority target for that plan's targeted test execution"
tech_stack:
  added: []
  patterns:
    - "Region-scoped grep (sed -n '<range>p' | grep -c ...) used in place of whole-file grep when a symbol legitimately exists elsewhere in the file for pre-existing reasons unrelated to the refactor under review"
key_files:
  created: []
  modified: []
decisions:
  - "The plan's literal Task 2 verify command (grep -c '...' src/account/GeniusNode.cpp expecting 0) does not hold as written, because GeniusNode.cpp legitimately implements RegisterChild/DetachChild/ReplaceMain/RevokeChild/RecoverFromChild/GetRegistrationsForMain as pre-existing v2.0-v2.3 wrapper methods (20 matches, all inside these pre-existing implementations at lines 2316-2501). The verify command's intent (confirm the bridge-catchup rewrite itself never references these symbols) was instead satisfied via region-scoped greps restricted to the actual touched hunks (lines 755-775, 1600-1620, 3080-3235), all returning 0."
metrics:
  duration: "~70min (dominated by a from-scratch-feeling MSVC rebuild of genius_node against the full merge diff; Tasks 2's read-through ran in parallel with the build)"
  completed: "2026-07-23"
status: complete
---

# Phase 6 Plan 3: Post-Merge Build Verification & Semantic Regression Read-Through Summary

Built all three required SuperGenius targets (`genius_node`, `registration_transaction_test`, `child_registration_test`) against the merged, rename-swept, still-uncommitted `dev_childwallet` working tree — all three exit 0 with only pre-existing `[[nodiscard]]`/LNK4099-PDB warnings, no new compiler or linker errors. Both test binaries are confirmed freshly rebuilt (Jul 23 16:27/16:28) versus the stale pre-merge baseline (Jul 22 17:13). Completed a manual, line-range-verified read-through of the 4 large auto-merged files flagged by 06-RESEARCH.md's Pitfall 1 — confirmed zero textual/symbol overlap between `origin/develop`'s bridge-catchup and genesis-registry refactors and the child-wallet consensus code (`CheckParentChildAuthority`, `FilterRegistration`, registration/lifecycle methods), and confirmed the `ValidateTransactionForConsensus` pipeline order (`CheckTransactionAuthorization` -> `CheckParentChildAuthority` -> `CheckTransactionTimestamp` -> `EvaluateTransactionReplayProtection`) is preserved exactly as documented in the project's decision log. MERGE_HEAD remains present in SuperGenius; the merge was not committed and no `cmake --install` was run.

## What Was Built

**Task 1 - Build all targets post-merge:**
- Confirmed pre-flight state before building: `MERGE_HEAD` present (`2981cd83abb08aba6fdb594103fddb89f8b5dd64`), SuperGenius HEAD still at pre-merge `5fd137dc`, existing test binaries dated Jul 22 17:13 (stale pre-merge baseline recorded for later comparison).
- Ran `cmake --build SuperGenius/build/Windows/Debug --target genius_node --config Debug` from the repo root. Exit code 0. Compiled `GeniusTransaction.cpp`, `RegistrationTransaction.cpp`, `RevokeTransaction.cpp`, `GeniusNode.cpp`, `TransactionManager.cpp`, and others; only `warning C4834` (`[[nodiscard]]` discard, pre-existing style, not new) surfaced — no errors. Produced `genius_node.lib`.
- Ran `cmake --build SuperGenius/build/Windows/Debug --target registration_transaction_test --config Debug`. Exit code 0. Produced `build/Windows/Debug/test_bin/Debug/registration_transaction_test.exe` (Jul 23 16:27, 143,363,072 bytes) — only pre-existing LNK4099 PDB-not-found warnings (LLVM support libs shipped without matching PDBs, unrelated to this merge).
- Ran `cmake --build SuperGenius/build/Windows/Debug --target child_registration_test --config Debug`. Exit code 0. Produced `build/Windows/Debug/test_bin/Debug/child_registration_test.exe` (Jul 23 16:28, 142,874,624 bytes) — same class of pre-existing LNK4099 warnings only.
- Confirmed via `Grep` across all three captured build logs: zero matches for `error C\d|fatal error|LNK2019|LNK2001|LNK1` in any of the three builds.
- No target failure occurred, so the plan's fallback diagnostic path (checking for a lingering `ProcessingTransaction` reference or an incomplete `DevConfig_st` rename-sweep miss) was never needed.
- No `cmake --install` was run at any point, per the plan's explicit scope boundary (Phase 7's concern).

**Task 2 - Manual read-through of the 4 large auto-merged files:**
- `src/account/GeniusNode.hpp` (1313 lines, read in full): confirmed the `BridgeCatchupWatcher` forward declaration and `catchup_watcher_`/`chainlist_fetcher_`/`catchup_chains_`/`catchup_mutex_` members live in a structurally separate section of the class from the registration/lifecycle method declarations (`RegisterChild`, `DetachChild`, `ReplaceMain`, `RevokeChild`, `RecoverFromChild`, `GetRegistrationsForMain`) — no interleaving, no shared members.
- `src/account/GeniusNode.cpp`: located the bridge-catchup rewrite (`OnRpcEndpointsReady`/`InitializeAndStartBridge`, lines 3089-3234, plus call site at line 766 and teardown at lines 1609-1612) and the registration/lifecycle wrapper implementations (lines 2316-2501) via grep, confirmed via line-range separation there is zero overlap. Read the full bridge-catchup rewrite (lines 3089-3238) — it exclusively touches `MintTokens`, `BridgeRelayer`, `ChainRpcEndpointProvider`, and UTXO-consumed/reserved checks; read the full registration/lifecycle block (lines 2316-2501) — each method is an unchanged thin delegation to `TransactionManager`, matching pre-merge behavior exactly.
  - Deviation note: the plan's literal verify grep (`grep -c '...' GeniusNode.cpp` expecting 0) returns 20, not 0, because the file legitimately contains the pre-existing registration/lifecycle implementations themselves (these are not part of develop's diff — they are v2.0-v2.3 child-wallet code that has always lived in this file). Re-ran the same symbol set scoped to just the bridge-catchup touched line ranges (755-775, 1600-1620, 3080-3235 via `sed -n '<range>p' | grep -c`) — all three scoped greps return 0, which is what actually proves the acceptance criterion's stated intent ("the bridge-catchup refactor never references child-wallet consensus symbols").
- `src/blockchain/impl/Blockchain.cpp` (1902 lines): confirmed via grep that `SetAdditionalGenesisValidatorAddresses`/`start_deferred_`/`StoreGenesisRegistry` call sites (lines 165, 522-548, 713, 1104) all sit well above `CheckCertifiedParent`'s definition at line 1852. Read `CheckCertifiedParent` in full (lines 1852-1884) — syntactically intact, balanced braces, exactly one definition in the file, logic unchanged from pre-merge (reg-key lookup via `boost::format`, `RegistrationTx` parse, certificate check, returns `main_address()`).
- `src/account/TransactionManager.cpp`'s `EvaluateTransactionReplayProtection` (lines 4553-4656): read the full merged function body. Confirmed it calls the new `GetOutgoingPreviousHash(nonce)` helper (line 4568, helper defined at line 1276) and applies the new own-address previous-hash consistency check (lines 4566-4576: when `tx.GetSrcAddress() == account_m->GetAddress()`, the tx's declared previous_hash is compared against the expected value and rejected on mismatch). Function is otherwise structurally intact (nonce-window/intermediate-nonce checks, balanced braces, single closing brace at line 4656) — not modified in this task, per plan design; flagged for the next plan's targeted `LifecycleChangeReplayRejectedByNonceChain`/`DetachChildEndToEnd`/`ReplaceMainEndToEnd`/`RevokeChildEndToEnd`/`ReRegistrationAfter*` test execution.
- Additionally confirmed (beyond the plan's minimum) the `ValidateTransactionForConsensus` pipeline order at lines 4272-4341: `CheckTransactionWellFormed` -> `CheckTransactionAuthorization` (4294) -> `CheckParentChildAuthority` (4303) -> `CheckTransactionTimestamp` (4312) -> `EvaluateTransactionReplayProtection` (4321) -> `CheckTransactionTypeRules` (4332) — matches the project's existing `[Roadmap, v2.3]` decision log entry exactly; no reordering introduced by the merge.
- Read `CheckParentChildAuthority`'s body (lines 4402+) as a light sanity check beyond the plan's strict requirement — confirmed logic unchanged (transfer-type certified-parent branch, revoke-type `RevokeTransaction` dynamic_cast branch).

## Deviations from Plan

### Informational (non-blocking)

**1. Task 2's literal verify grep command doesn't return 0 against the whole file, as written**
- **Found during:** Task 2, immediately after reading GeniusNode.hpp/.cpp.
- **What the plan expected:** `grep -c 'CheckParentChildAuthority\|FilterRegistration\|RegisterChild\|DetachChild\|RevokeChild\|ReplaceMain\|RecoverFromChild' SuperGenius/src/account/GeniusNode.cpp` returns 0.
- **What actually happened:** Returns 20. `GeniusNode.cpp` legitimately implements `RegisterChild`/`DetachChild`/`ReplaceMain`/`RevokeChild`/`RecoverFromChild`/`GetRegistrationsForMain` as pre-existing v2.0-v2.3 child-wallet wrapper methods (lines 2316-2501) — these are not new code introduced by this merge or by develop's diff; they've been in this file since prior phases (v2.0-v2.3). The plan's stated acceptance-criteria intent — "confirms the bridge-catchup refactor never references child-wallet consensus symbols" — is a claim about the *bridge-catchup rewrite specifically*, not about the whole file, and the whole-file grep can never return 0 while these legitimate methods exist in the same file.
- **Why this is not a bug:** No code was changed to "fix" this; it's a pre-existing verify-command imprecision in the plan text itself. Re-scoped the same symbol grep to the actual bridge-catchup touched line ranges (755-775, 1600-1620, 3080-3235) — all three return 0, which is the correct empirical proof of the stated claim.
- **Action taken:** Documented the discrepancy here rather than silently substituting a different check; used the region-scoped grep results as the evidence satisfying the acceptance criterion's actual intent.
- **Impact:** None — the underlying claim (zero symbol overlap between the bridge-catchup refactor and child-wallet consensus code) is proven true by the scoped greps; only the literal command text in the plan was imprecise.

### Auto-fixed Issues

None — no build failures occurred, so the plan's Rule-1/Rule-3 fallback diagnostic path (checking for `ProcessingTransaction` remnants or `DevConfig_st` rename-sweep misses) was never triggered.

## Known Stubs

None — this plan performs build verification and read-only manual review; no source logic authored.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes introduced. Per the plan's threat register, T-06-05 (semantic regression risk in the 4 auto-merged files) is mitigated by this plan's Task 2 read-through (documented above); T-06-06 (stale-binary false-pass risk) is mitigated by Task 1's confirmed fresh timestamps.

## Verification Results

- `cmake --build SuperGenius/build/Windows/Debug --target genius_node --config Debug` -> exit 0, `genius_node.lib` produced, only pre-existing `[[nodiscard]]` warnings.
- `cmake --build SuperGenius/build/Windows/Debug --target registration_transaction_test --config Debug` -> exit 0, `registration_transaction_test.exe` produced (Jul 23 16:27, freshly rebuilt vs. stale Jul 22 17:13 baseline).
- `cmake --build SuperGenius/build/Windows/Debug --target child_registration_test --config Debug` -> exit 0, `child_registration_test.exe` produced (Jul 23 16:28, freshly rebuilt vs. stale Jul 22 17:13 baseline).
- All three captured build logs scanned for `error C\d|fatal error|LNK2019|LNK2001|LNK1` -> zero matches in all three.
- `grep -n 'std::optional<std::string> Blockchain::CheckCertifiedParent' src/blockchain/impl/Blockchain.cpp` -> exactly one line (1852), function body read in full and confirmed syntactically intact.
- Region-scoped grep of bridge-catchup-touched line ranges (755-775, 1600-1620, 3080-3235) in `GeniusNode.cpp` for `CheckParentChildAuthority|FilterRegistration|RegisterChild|DetachChild|RevokeChild|ReplaceMain|RecoverFromChild` -> 0 matches in all three ranges.
- `EvaluateTransactionReplayProtection` (TransactionManager.cpp:4553-4656) read in full -> confirmed calls `GetOutgoingPreviousHash(tx.GetNonce())` (line 4568) and applies the new own-address previous-hash consistency check (lines 4566-4576); function otherwise structurally intact.
- `ValidateTransactionForConsensus` pipeline order (lines 4272-4341) confirmed unchanged: `CheckTransactionAuthorization` -> `CheckParentChildAuthority` -> `CheckTransactionTimestamp` -> `EvaluateTransactionReplayProtection` -> `CheckTransactionTypeRules`.
- `git rev-parse -q --verify MERGE_HEAD` (inside SuperGenius) -> `2981cd83abb08aba6fdb594103fddb89f8b5dd64` (present, merge still open); `git log -1 --oneline` -> `5fd137dc` (pre-merge HEAD, unchanged — merge not committed).
- No `cmake --install` was run at any point.

All must-haves from the plan frontmatter confirmed:
- SuperGenius builds cleanly across all targets post-merge (genius_node, registration_transaction_test, child_registration_test), with no new compiler/linker errors: CONFIRMED
- The 4 large auto-merged files have been manually read through, not just build-verified: CONFIRMED
- Built artifacts (genius_node static lib, both test .exe files) all rebuilt post-merge, replacing the stale pre-merge binaries: CONFIRMED (timestamps Jul 23 16:27/16:28 vs. stale Jul 22 17:13)

## Self-Check: PASSED

- FOUND: `W:\gnus\GeniusNetwork\SuperGenius\build\Windows\Debug\src\account\Debug\genius_node.lib`
- FOUND: `W:\gnus\GeniusNetwork\SuperGenius\build\Windows\Debug\test_bin\Debug\registration_transaction_test.exe` (Jul 23 16:27)
- FOUND: `W:\gnus\GeniusNetwork\SuperGenius\build\Windows\Debug\test_bin\Debug\child_registration_test.exe` (Jul 23 16:28)
- CONFIRMED: `MERGE_HEAD` present inside SuperGenius (`2981cd83abb08aba6fdb594103fddb89f8b5dd64`), merge not committed

This plan does not create per-task outer-repo commits during Tasks 1-2 (no source files were modified inside SuperGenius; only build artifacts were produced, and the SuperGenius merge itself remains intentionally uncommitted, consistent with Plans 01-02's precedent). This SUMMARY.md's own commit in the outer repo (GeniusNetwork) is the only commit associated with this plan.
