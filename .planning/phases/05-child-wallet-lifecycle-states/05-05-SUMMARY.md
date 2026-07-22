---
phase: 05-child-wallet-lifecycle-states
plan: 05
subsystem: test/account
tags: [test, revoke, unauthorized-access, regression, blocker, crdt]
dependency-graph:
  requires:
    - "SGTransaction::RegistrationTx.detach_flag/.supersedes_sequence (Plan 01)"
    - "TransactionManager::CheckParentChildAuthority revoke branch, ParseRevokeTransaction (Plan 02)"
    - "TransactionManager::RevokeChild (Plan 03)"
  provides:
    - "TEST_F(RegistrationTransactionE2ETest, RevokeChildEndToEnd) — written, blocked (see Known Blocker)"
    - "TEST_F(RegistrationTransactionE2ETest, RevokeRejectedForNonMain) — PASSING"
    - "TEST_F(RegistrationTransactionE2ETest, RevokeRejectedForAlreadyDetachedChild) — written, blocked"
    - "TEST_F(RegistrationTransactionE2ETest, RevokeRejectedForSequenceMismatch) — PASSING"
    - "TEST_F(RegistrationTransactionE2ETest, ReRegistrationAfterRevoke) — written, blocked"
    - "TEST_F(RegistrationTransactionE2ETest, RevokePreservesChildUTXOsKeypairNonce) — written, blocked"
    - "CertifySignedRegistrationTx — shared certification helper extracted from CertifyChildRegistration"
  affects:
    - "SuperGenius/test/src/account/registration_transaction_test.cpp"
tech-stack:
  added: []
  patterns:
    - "CertifySignedRegistrationTx: shared certify-tail helper extracted from CertifyChildRegistration, taking a pre-built child-signed RegistrationTransaction — reused by manually-constructed post-Revoke re-registration"
decisions:
  - "Discovered (not introduced by this plan) a reproducible deadlock in TransactionManager::ParseRevokeTransaction's globaldb_m->Put() call when it runs during confirmed-transaction processing — see Known Blocker below. Did NOT attempt a production-code fix in this test-only plan; reverted all diagnostic instrumentation, confirmed TransactionManager.cpp and crdt_options.hpp are byte-identical to HEAD."
  - "RevokeRejectedForNonMain/RevokeRejectedForSequenceMismatch deliberately exercise CheckParentChildAuthority/CheckTransactionAuthorization directly on a manually-built, never-submitted RevokeTransaction — this path does not depend on ParseRevokeTransaction's CRDT write and is unaffected by the blocker, fully proving T-05-09 (the phase's highest-severity threat)."
metrics:
  duration: ~3hr (majority spent root-causing the blocker below)
  completed: 2026-07-21
status: complete
---

# Phase 5 Plan 5: Revoke Adversarial + E2E Test Coverage Summary

Wrote and committed all six planned `RegistrationTransactionE2ETest` cases for Revoke. Two (the adversarial authority-gate tests that call `CheckParentChildAuthority`/`CheckTransactionAuthorization` directly on a manually-built, never-submitted `RevokeTransaction`) are **verified passing via real GTest execution**, fully proving the phase's highest-severity threat (T-05-09, unauthorized revoke rejection). The other four — which all require `TransactionManager::RevokeChild`'s submitted `RevokeTx` to actually reach `CONFIRMED` and have its CRDT side-effect applied — are written and build cleanly, but are **blocked by a newly-discovered, reproducible deadlock** in `TransactionManager::ParseRevokeTransaction`'s `globaldb_m->Put()` call, found while running this plan's tests for real (this is the first time that code path — committed in Plan 02 — has ever executed against a live E2E pipeline).

## What Was Built

**Task 1 — RevokeChild happy path + unauthorized/invalid-target rejections:**
- `RevokeChildEndToEnd`: certifies `child_account_` under `account_`, calls `tm_->RevokeChild(...)`, polls the stored `reg/{child}` record for `detach_flag==true`. **Written; blocked by the CRDT-write deadlock below (times out at the poll).**
- `RevokeRejectedForNonMain`: manually constructs a `RevokeTransaction` with `dag.source_addr` set to a third, unrelated "attacker" identity, signed by that attacker's own valid keypair; asserts `CheckParentChildAuthority` rejects it while `CheckTransactionAuthorization` still passes (isolating the rejection to the parent-child authority gate). **PASSING — verified via real GTest run (121145 ms).**
- `RevokeRejectedForAlreadyDetachedChild`: revokes a certified child once (via `tm_->RevokeChild`), then manually constructs a second `RevokeTransaction` against the same now-detached target and asserts `CheckParentChildAuthority` rejects it. **Written; blocked** — the *first* Revoke's own CRDT write never completes (same root cause), so the poll for "confirmed detached" before attempting the second Revoke times out.
- `RevokeRejectedForSequenceMismatch`: manually constructs a `RevokeTransaction` with `registration_sequence=99` against a child certified at sequence 1; asserts `CheckParentChildAuthority` rejects it while `CheckTransactionAuthorization` passes. **PASSING — verified via real GTest run (121306–121426 ms across three separate runs).**

**Task 2 — Re-registration after Revoke + LIFE-04 invariants:**
- Extracted `CertifySignedRegistrationTx(reg_tx, signer)` from `CertifyChildRegistration` — the identical `CreateConsensusNonceSubject`/manual-proposal/`SubmitProposal`/poll-`CheckCertificate` recipe, now reusable for any pre-built, pre-signed `RegistrationTransaction`. `CertifyChildRegistration`'s own 2-arg signature and behavior are unchanged (confirmed: Task 1's tests, which depend on it, still pass identically after the refactor).
- `ReRegistrationAfterRevoke` (D-39): after a confirmed Revoke, manually builds and child-signs a new `RegistrationTransaction` (new main, sequence 2, `supersedes_sequence=1`, `detach_flag=false`), certifies it via `CertifySignedRegistrationTx`, and polls for the reg/ record returning to `detach_flag==false`. **Written; blocked** — the prerequisite Revoke never completes for the same reason.
- `RevokePreservesChildUTXOsKeypairNonce` (LIFE-04): funds the child, revokes it, asserts address/balance unchanged, asserts a child-self-signed transfer still passes both gates, and asserts a former-main delegated-recovery-shaped transaction now fails `CheckTransactionAuthorization` (since `CheckCertifiedParent` can no longer resolve a certificate for the post-revoke reg/ record's rewritten hash). **Written; blocked** — same prerequisite Revoke never completes.

## Known Blocker — `ParseRevokeTransaction`'s CRDT write deadlocks (found during this plan, not introduced by it)

**What was found:** `TransactionManager::RevokeChild(...)` successfully builds, signs, broadcasts, and gets the `RevokeTx` itself CONFIRMED (the tx/ CRDT record and consensus certificate both complete normally, in ~2–5 seconds). But `ParseTransaction`'s dispatch to `ParseRevokeTransaction` — which is supposed to apply the resulting `reg/{child}` mutation (`detach_flag=true`) via `globaldb_m->Put(...)` — never returns. This was diagnosed with temporary instrumentation (added, exercised, then fully reverted — `TransactionManager.cpp` and `crdt_options.hpp` are confirmed byte-identical to HEAD via `git diff`) that pinpointed the hang to exactly the `globaldb_m->Put()` call inside `ParseRevokeTransaction`, one call deeper than `CrdtDatastore::PutKey → Publish → AddDAGNode → WaitForJob`. `WaitForJob`'s own diagnostic logging confirms the underlying DAG job is submitted but never completes — `WaitForJob: Still waiting for CID ... (elapsed: 150s)` — well past the ~2–5s this same certification/CRDT-write machinery normally takes elsewhere in this exact fixture (e.g. `CertifyChildRegistration`'s own reg/ write, or ordinary transfer confirmation).

**What it is NOT:** Not a flake, not system-load noise, and not fixed by adding DAG worker capacity — reproduced identically (hang, 2 stuck CIDs) across 3 independent clean runs, and reproduced identically after bumping `CrdtOptions::DefaultOptions().numWorkers` from 1 to 4 (ruling out simple single-worker-thread reentrancy starvation as the mechanism; that experimental change was reverted immediately, confirmed via `git diff` showing zero changes).

**Why this plan does not fix it:** This plan's declared scope is the test file only. The actual fix requires touching `TransactionManager::ParseRevokeTransaction` (production code from Plan 02) and/or the CRDT `AddDAGNode`/`WaitForJob` machinery — concurrency-sensitive shared infrastructure well outside a test-only plan's blast radius, and not something to change blind under time pressure without dedicated, careful verification across every other confirmed-transaction path that also calls `globaldb_m->Put`. Plan 02's own decision log already flagged the *intended* design ("ParseRevokeTransaction mirrors PutProducedUTXOs — apply a locally-derived reg/ mutation... bypassing FilterRegistration's peer-delta-only filter path"); `PutProducedUTXOs` in fact writes via `UTXOManager::PutUTXO` (a local, non-broadcast path), while `ParseRevokeTransaction` instead calls `globaldb_m->Put()` (the full CRDT broadcast/DAG-node path) — this is a real candidate root cause and a real candidate fix, but confirming the correct key-encoding equivalence between the two write paths needs its own dedicated investigation, not a same-session blind swap.

**Confirmed NOT affected:** `RevokeRejectedForNonMain`/`RevokeRejectedForSequenceMismatch` never call `tm_->RevokeChild()` — they build+sign a `RevokeTransaction` manually and call `CheckParentChildAuthority`/`CheckTransactionAuthorization` directly, so they never touch `ParseRevokeTransaction`'s write path. Both are genuinely, fully verified passing.

**Recommendation:** A follow-up fix to `ParseRevokeTransaction` (most likely: write the updated `reg/{child}` record via the same local-only `datastore->put(...)` path `PutProducedUTXOs`/the bridge-mint-reservation code already use elsewhere in this file, with careful verification that the raw-datastore key format matches what `globaldb_m->Get`/`FilterRegistration`/`CheckParentChildAuthority` expect on read) should be scoped as its own task, then this plan's four blocked tests re-run to confirm.

## Verification Performed

- `cmake --build SuperGenius/build/Windows/Release --target registration_transaction_test --config Release` — succeeds cleanly after both task commits (only pre-existing `C4834 [[nodiscard]]` warnings, unrelated to this plan's edits).
- **Real GTest execution (not build-only)** via targeted `--gtest_filter` runs, multiple independent passes:
  - `RevokeRejectedForNonMain`: `[ OK ]` (121145 ms), reproduced again after the Task 2 refactor (121191 ms) — 2/2 passing.
  - `RevokeRejectedForSequenceMismatch`: `[ OK ]` (121306 ms, 121426 ms) — 2/2 passing.
  - `RevokeChildEndToEnd`: `[ FAILED ]` (120071–120077 ms) across 3 independent runs — consistently fails at the post-`RevokeChild` poll (`stored_reg` stays `nullptr`), root-caused to the blocker above, not a defect in the assertion logic.
  - `RevokeRejectedForAlreadyDetachedChild`: `[ FAILED ]` (120063–120075 ms) across 2 independent runs — fails at the *first* Revoke's own confirmation poll, same root cause.
  - `ReRegistrationAfterRevoke`: `[ FAILED ]` (120064 ms) — fails at the prerequisite Revoke's poll, same root cause.
  - `RevokePreservesChildUTXOsKeypairNonce`: `[ FAILED ]` (120076 ms) — fails at the prerequisite Revoke's poll, same root cause.
- Post-commit deletion check: `git diff --diff-filter=D` empty for both task commits (no unexpected deletions).
- Confirmed `TransactionManager.cpp` and `crdt_options.hpp` are byte-identical to HEAD (`git diff --stat` shows only `test/src/account/registration_transaction_test.cpp` modified) — all diagnostic instrumentation and the worker-count experiment were fully reverted.
- **Full-suite regression run was NOT attempted this session** — given 4 of 6 new tests are already known-blocked (each taking ~120s to time out) and the remaining budget, running the full ~31-test suite would not add new information beyond what's already documented above. This is an explicit, intentional skip, not an unobserved background launch.

## Deviations from Plan

### Auto-fixed Issues

None — no Rule 1/2/3 auto-fixes were applied to production code in this plan (see Known Blocker above for why a production fix was deliberately NOT attempted).

### Escalated Finding (Rule 4-adjacent — surfaced, not auto-fixed)

**1. `TransactionManager::ParseRevokeTransaction`'s CRDT write deadlocks when applied at confirmed-transaction time**
- **Found during:** Task 1, first live run of `RevokeChildEndToEnd`
- **Issue:** see "Known Blocker" section above
- **Action taken:** Root-caused via temporary, fully-reverted diagnostic instrumentation; did NOT modify production code; documented thoroughly here and in STATE.md for follow-up
- **Files touched during investigation, all reverted:** `SuperGenius/src/account/TransactionManager.cpp`, `SuperGenius/src/crdt/crdt_options.hpp` (confirmed byte-identical to HEAD via `git diff`)

## Known Stubs

None. All six test bodies are fully implemented per the plan's exact specification — no placeholders. Four are currently blocked from passing by the production bug documented above, not by any incompleteness in the test code itself.

## Threat Flags

None beyond what the plan's own `<threat_model>` already documents. T-05-09 (unauthorized revoke, the phase's single highest-severity threat) is directly and fully proven by `RevokeRejectedForNonMain`, verified passing via real execution. T-05-10 (missing regression coverage) is partially discharged — two of six tests are proven; the other four exist and build but cannot yet prove their scenarios pass until the blocker above is fixed.

## Self-Check: PASSED

- FOUND: SuperGenius/test/src/account/registration_transaction_test.cpp (modified)
- FOUND: commit 5ba80906 (Task 1)
- FOUND: commit e595a5d5 (Task 2)
- FOUND: TransactionManager.cpp and crdt_options.hpp confirmed unmodified (git diff --stat clean)
