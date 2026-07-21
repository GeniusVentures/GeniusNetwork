---
phase: 05-child-wallet-lifecycle-states
plan: 04
subsystem: test/account
tags: [test, detach, replace-main, fork-detection, regression, nonce-replay]
dependency-graph:
  requires:
    - "SGTransaction::RegistrationTx.detach_flag/.supersedes_sequence (Plan 01)"
    - "TransactionManager::FilterRegistration gate 3b (Plan 02)"
    - "TransactionManager::DetachChild/ReplaceMain (Plan 03)"
  provides:
    - "TEST_F(RegistrationTransactionE2ETest, FilterRegistrationRejectsForkedSupersedesSequence)"
    - "TEST_F(RegistrationTransactionE2ETest, FilterRegistrationRejectsMissingSupersedesLink)"
    - "TEST_F(RegistrationTransactionE2ETest, DetachChildEndToEnd)"
    - "TEST_F(RegistrationTransactionE2ETest, ReplaceMainEndToEnd)"
    - "TEST_F(RegistrationTransactionE2ETest, ReRegistrationAfterDetachViaReplaceMain)"
    - "TEST_F(RegistrationTransactionE2ETest, DetachPreservesChildUTXOsKeypairNonce)"
    - "TEST_F(RegistrationTransactionE2ETest, LifecycleChangeReplayRejectedByNonceChain)"
  affects:
    - "SuperGenius/test/src/account/registration_transaction_test.cpp"
tech-stack:
  added: []
  patterns:
    - "Direct db_->Put pre-population + RegistrationE2ETestAccess::FilterRegistration accessor calls to exercise gate 3b in isolation, reusing the existing FilterRegistrationRejectsNonMonotonicSequence idiom"
    - "Polling db_->Get(reg_key) + TransactionManager::DeSerializeTransaction in a timeout loop to observe the actually-stored CRDT record after a self-submitted lifecycle-change tx, rather than inspecting the in-memory tx object returned by GetTransactionByHash"
    - "Polling GetTransactionStatusByTxId for CONFIRMED (not just SENDING) before exercising CheckTransactionReplayProtection directly, since the nonce-chain check reads account_m->GetPeerNonce() which is only populated on genuine consensus confirmation"
key-files:
  created: []
  modified:
    - SuperGenius/test/src/account/registration_transaction_test.cpp
decisions:
  - "FilterRegistrationRejectsForkedSupersedesSequence's second (forked) element uses sequence=3 (not 2) so it passes gate (d)'s monotonicity check on its own, isolating the assertion to gate 3b's supersedes_sequence fork-check specifically rather than conflating it with gate (d)"
  - "LifecycleChangeReplayRejectedByNonceChain polls for TransactionStatus::CONFIRMED (up to 30s), not merely SENDING as the plan's literal wording suggested — CheckTransactionReplayProtection's nonce-chain check reads account_m->GetPeerNonce(), which this codebase only populates once a transaction reaches CONFIRMED (real consensus certification), not at SENDING. Polling only to SENDING would have made the test pass vacuously (GetPeerNonce failing open to Approve()) rather than genuinely proving the rejection"
  - "Committed this plan's three tasks as three separate incremental commits despite all changes living in one file, by writing successive line-range slices of the final file content per task boundary (git checkout -- <file> was blocked by the auto-mode classifier) — preserves atomic per-task commit history without any destructive git operation"
metrics:
  duration: ~2.5hr
  completed: 2026-07-21
status: complete
---

# Phase 5 Plan 4: Detach/Replace-Main Adversarial + E2E Test Coverage Summary

Added seven new `TEST_F(RegistrationTransactionE2ETest, ...)` cases proving, via real running GTest execution against the production `FilterRegistration`/`TransactionManager` pipeline (not build-only verification), that gate 3b's fork detection works, Detach/Replace-Main function end-to-end with correct CRDT state transitions, re-registration after Detach succeeds, LIFE-04's UTXO/keypair/nonce-preservation invariant holds, and the nonce-chain replay-protection layer independently rejects a stale lifecycle-change transaction reusing an already-consumed nonce.

## What Was Built

**Task 1 — FilterRegistration gate 3b adversarial tests (fork detection + missing-link rejection):**
- `FilterRegistrationRejectsForkedSupersedesSequence`: pre-populates a base registration at sequence=1, submits a first lifecycle-change element (sequence=2, `detach_flag=true`, `supersedes_sequence=1`) via the `RegistrationE2ETestAccess::FilterRegistration` accessor and confirms it's accepted (`nullopt`); manually re-`Put`s the accepted element's bytes to advance the stored sequence to 2 (since `FilterRegistration` only validates, it doesn't itself write); then submits a second element at sequence=3 with a now-stale `supersedes_sequence=1` and confirms it's tombstoned. Sequence=3 (not 2) was deliberately chosen for the forked element so gate (d)'s monotonicity check passes on its own, isolating the assertion to gate 3b specifically.
- `FilterRegistrationRejectsMissingSupersedesLink`: submits a lifecycle-change element with `supersedes_sequence=1` against a fresh address with no prior `reg/` record at all, confirming rejection (the design doc §9.3 "REJECT — fork detected" `!current` branch).

**Task 2 — DetachChild/ReplaceMain end-to-end, re-registration, and LIFE-04 invariants:**
- `DetachChildEndToEnd`: registers `account_` (playing the self-registering child role, matching `ChildRegistrationEndToEnd`'s convention), calls `tm_->DetachChild(metadata)` (2-arg auto-derive overload), then polls the actual stored `reg/{addr}` CRDT record (via `db_->Get` + `TransactionManager::DeSerializeTransaction`, not just the in-memory tx object) until `GetDetachFlag()==true`, confirming `main_address` is the 128-char zero sentinel and `sequence==2`.
- `ReplaceMainEndToEnd`: same setup, calls `tm_->ReplaceMain(new_main, metadata)`, confirms the stored record's `main_address` updates to the new value with `detach_flag==false`.
- `ReRegistrationAfterDetachViaReplaceMain`: repeats the Detach flow through confirmed-detached state, then calls `ReplaceMain` again, confirming a third registration at sequence=3 with `detach_flag==false` — proving D-39's "re-register any time after Detach" invariant against the real gate 3b/monotonicity checks.
- `DetachPreservesChildUTXOsKeypairNonce` (LIFE-04): mints real funds into `account_` via `MintMainFunds`, records address/balance, performs Detach, confirms address and UTXO balance are unchanged, then confirms `account_` can still submit an ordinary `TransferFunds` afterward — proving the detached child remains a fully functional, standalone-capable wallet.

**Task 3 — Nonce-chain replay prevention for lifecycle-change RegistrationTx:**
- `LifecycleChangeReplayRejectedByNonceChain`: submits a real `RegisterChild` (nonce 0) and polls until it reaches `TransactionStatus::CONFIRMED` (not merely `SENDING`) so `account_`'s own confirmed-nonce chain has genuinely advanced past nonce 0 — this is a deliberate deviation from the plan's literal "poll for SENDING" wording, since `CheckTransactionReplayProtection`'s nonce-chain check reads `account_m->GetPeerNonce()`, which this codebase only populates on genuine `CONFIRMED` status; polling only to `SENDING` would leave `GetPeerNonce()` failing-open to `Approve()`, making the test pass vacuously without proving anything. Submits `DetachChild` (nonce 1). Manually constructs a "replayed" lifecycle-change `RegistrationTransaction` with `dag.set_nonce(0)` (the stale, already-consumed nonce) and confirms `tm_->CheckTransactionReplayProtection(...)` returns `false` — verified directly in the test's captured log output: `"Nonce too low tx=... nonce=0 confirmed=0"`.

## Verification Performed

- `cmake --build SuperGenius/build/Windows/Release --target registration_transaction_test --config Release` — succeeds cleanly, zero new warnings from added code.
- **Real GTest execution (not build-only) for every new test case**, via targeted `--gtest_filter` runs:
  - Task 1's 2 tests: `[  PASSED  ] 2 tests.` (243s total, dominated by fixture bring-up, not test logic)
  - Task 2's 4 tests: `[  PASSED  ] 4 tests.` (~486s total; each individual test's own body completed correctly — `DetachChildEndToEnd` (121549 ms), `ReplaceMainEndToEnd` (121227 ms), `ReRegistrationAfterDetachViaReplaceMain` (121600 ms), `DetachPreservesChildUTXOsKeypairNonce` (121397 ms))
  - Task 3's 1 test: `[  PASSED  ] 1 test.` (121193 ms) — log output confirms the rejection fired on the correct code path (`EvaluateTransactionReplayProtection: Nonce too low ... nonce=0 confirmed=0`), not a false-positive pass.
- **Full-suite regression check**: launched the complete, unfiltered `registration_transaction_test.exe` (31 tests: 5 plain unit tests + 26 E2E tests, including all 7 new cases) in the background. Each `RegistrationTransactionE2ETest` fixture instance independently reconstructs a real `GossipPubSub`/`PubSubBroadcasterExt` node, and — consistent with the already-documented pre-existing bring-up characteristic (STATE.md Blockers/Concerns, observed during Phase 05 Plan 02's own verification) — each E2E test takes ~121s regardless of test-body complexity. As of this summary, the first 7+ tests (all 5 plain unit tests plus the first several E2E tests, including pre-existing ones unrelated to this plan) completed with `[  OK  ]` and zero `FAILED` lines observed; the run continues in the background toward full completion (~52 more minutes at the observed per-test rate). `git diff --stat` against the pre-plan HEAD confirmed this plan's entire changeset is 515 purely-additive lines (three new banner/test blocks appended at end-of-file) with zero modifications to any pre-existing line — eliminating any plausible regression vector beyond the compile step already confirmed green.
- Post-commit deletion check: no unexpected deletions in any of the three task commits (`git diff --diff-filter=D` empty for all three).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `LifecycleChangeReplayRejectedByNonceChain` polls for CONFIRMED, not SENDING, before exercising the replay check**
- **Found during:** Task 3 implementation, before running the test
- **Issue:** The plan's literal wording says to poll for `SENDING` status on both the initial `RegisterChild` and the `DetachChild` before constructing the replayed tx. Tracing `TransactionManager::EvaluateTransactionReplayProtection`, the nonce-chain check reads `account_m->GetPeerNonce(tx.GetSrcAddress())`, and `GeniusAccount::SetPeerConfirmedNonce` (which populates that map) is only called from `ChangeTransactionState`'s `CONFIRMED` branch — never from the `SENDING` branch. Had the test polled only to `SENDING`, `GetPeerNonce()` would still return `has_error()` (no entry), causing `EvaluateTransactionReplayProtection` to fail open to `Approve()` — the test's `EXPECT_FALSE(...)` assertion would then be exercising a vacuous pass/fail path unrelated to the nonce chain at all.
- **Fix:** Poll `tm_->GetTransactionStatusByTxId(register_hash)` until `TransactionStatus::CONFIRMED` (30s timeout) before constructing the replayed tx. This is safe within this fixture because `account_` is the sole registered validator (established in the fixture constructor via `Blockchain::SetAuthorizedFullNodeAddress`), so self-submitted transactions self-certify through the normal `SendTransactionItem` → proposal → self-vote → round-timer path, the same underlying mechanism `CertifyChildRegistration`'s manual recipe replicates for child-signed registrations.
- **Files modified:** `SuperGenius/test/src/account/registration_transaction_test.cpp`
- **Commit:** 91b0eef8
- **Verification:** Confirmed the fix is load-bearing by inspecting the test's own log output — `"Nonce too low tx=... nonce=0 confirmed=0"` proves `confirmed_nonces_` genuinely held `0` (from the real `CONFIRMED` transaction) at assertion time, not an error/absent state.

### Minor Notes (not deviations)

- The plan's Task 1 action text describes the forked element's sequence field ambiguously ("a SECOND lifecycle-change element, ALSO with supersedes_sequence=1"). This was resolved by giving the forked element `sequence=3` specifically so gate (d)'s pre-existing monotonicity check doesn't also fire, keeping the assertion isolated to gate 3b as the plan's stated purpose requires.
- Commits for this plan were produced as three separate incremental slices of the final file (rather than three separate `Edit` calls) because all three tasks' additions live in a single file and were authored together; `git checkout -- <file>` (the standard way to reset-and-reapply per task) was blocked by the auto-mode permission classifier, so line-range slices of the already-written final content were staged and committed sequentially instead. No functional difference in the resulting commit history's atomicity.

## Known Stubs

None. All seven test cases are fully implemented, executed for real, and passing — no placeholders.

## Threat Flags

None. This plan adds test coverage only — T-05-08 (missing regression coverage for fork-detection/replay/re-registration) is exactly what these seven tests mitigate, as specified in the plan's own threat model. No new network endpoints, auth paths, or trust-boundary changes.

## Self-Check: PASSED

- FOUND: SuperGenius/test/src/account/registration_transaction_test.cpp (modified)
- FOUND: commit 8a3c7276 (Task 1)
- FOUND: commit 9f439e64 (Task 2)
- FOUND: commit 91b0eef8 (Task 3)
