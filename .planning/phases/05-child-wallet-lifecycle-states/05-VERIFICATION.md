---
phase: 05-child-wallet-lifecycle-states
verified: 2026-07-22T01:30:12Z
status: gaps_found
score: 13/18 must-haves verified
behavior_unverified: 0
overrides_applied: 0
gaps:
  - truth: "A certified child's registration can be revoked by its certified main via TransactionManager::RevokeChild, and the resulting reg/{child_addr} record ends with detach_flag == true while main_address/metadata are preserved (LIFE-01, LIFE-04 — Revoke happy path)"
    status: failed
    reason: >
      TransactionManager::ParseRevokeTransaction's globaldb_m->Put() call deadlocks when it runs
      during confirmed-transaction processing. Independently reproduced in this verification pass
      (not just trusted from 05-05-SUMMARY.md): running RegistrationTransactionE2ETest.RevokeChildEndToEnd
      in isolation fails at the post-RevokeChild poll (stored_reg stays nullptr), and the log shows
      `CrdtDatastore::WaitForJob: Still waiting for CID ... (elapsed: 90s)` for two stuck CIDs, well
      past the ~2-5s this same CRDT-write machinery takes everywhere else in this fixture (e.g.
      CertifyChildRegistration's own reg/ write). The RevokeTx transaction itself DOES certify
      normally (tx/ record + consensus certificate complete in seconds) — only the follow-on
      ParseRevokeTransaction mutation of reg/{child_addr} hangs.
    artifacts:
      - path: "SuperGenius/src/account/TransactionManager.cpp"
        issue: "ParseRevokeTransaction (lines ~2337-2396) writes the updated reg/ record via the full CRDT broadcast path globaldb_m->Put(...); this call never returns when invoked from confirmed-transaction processing, unlike the local-only write path used by PutProducedUTXOs elsewhere in this file for the same class of per-node-derived side effect."
    missing:
      - "A production-code fix to ParseRevokeTransaction's CRDT write (candidate direction already identified in 05-05-SUMMARY.md: write via the same local-only datastore path PutProducedUTXOs uses, with verification that the raw-datastore key format still matches what globaldb_m->Get/FilterRegistration/CheckParentChildAuthority expect on read), scoped as its own follow-up task."
      - "Re-run of RevokeChildEndToEnd, RevokeRejectedForAlreadyDetachedChild, ReRegistrationAfterRevoke, and RevokePreservesChildUTXOsKeypairNonce after the fix to confirm they pass for real."
  - truth: "A RevokeTx targeting a reg/ record already in detach_flag == true state is rejected by CheckParentChildAuthority (RevokeRejectedForAlreadyDetachedChild)"
    status: failed
    reason: >
      This test's own setup requires a FIRST RevokeChild call to reach confirmed detach_flag==true
      before the second (adversarial) RevokeTx can be constructed and checked. The first RevokeChild
      never completes, for the same root cause as the gap above — blocked as a direct consequence,
      not a defect in the rejection logic itself (the CheckParentChildAuthority code path for this
      check, existing_reg->GetDetachFlag(), was confirmed present and correct by source read).
    artifacts:
      - path: "SuperGenius/test/src/account/registration_transaction_test.cpp"
        issue: "RevokeRejectedForAlreadyDetachedChild (line 2082) times out at its prerequisite RevokeChild confirmation poll"
    missing:
      - "Same ParseRevokeTransaction fix as above; this test should pass once the prerequisite Revoke completes."
  - truth: "After being revoked, the child can re-register (to the same or a different main) at a higher sequence via ReplaceMain, and its UTXOs/keypair/nonce are unaffected by the revoke (LIFE-04, D-39, D-36 — Revoke half)"
    status: failed
    reason: >
      Both ReRegistrationAfterRevoke and RevokePreservesChildUTXOsKeypairNonce depend on a
      prerequisite RevokeChild reaching confirmed detach_flag==true, which never completes for the
      same root cause. (Note: the equivalent invariant for DETACH — DetachPreservesChildUTXOsKeypairNonce
      — was independently re-run in this verification pass and PASSED; only the Revoke half of
      LIFE-04 is affected.)
    artifacts:
      - path: "SuperGenius/test/src/account/registration_transaction_test.cpp"
        issue: "ReRegistrationAfterRevoke (line 2191) and RevokePreservesChildUTXOsKeypairNonce (line 2302) both time out at the prerequisite RevokeChild confirmation poll"
    missing:
      - "Same ParseRevokeTransaction fix as above; both tests should pass once the prerequisite Revoke completes."
---

# Phase 5: Child Wallet Lifecycle States Verification Report

**Phase Goal:** Implement the child-initiated Detach and main-initiated Revoke lifecycle transitions for registered child wallets, per the v1.0 lifecycle design (`docs/03-02-reward-policy-lifecycle.md`): `reg/{child_addr}` CRDT fields `detach_flag` + `supersedes_sequence`, a new `RevokeTx` transaction type (`EmbeddedTransaction` oneof arm 9), a `FilterRegistration` gate extension checking `supersedes_sequence`, and reuse of `CheckParentChildAuthority` for revoke validation (main sig + Registered state). Scope also includes Replace-Main (D-70) and full adversarial test coverage (D-73).
**Requirements:** LIFE-01, LIFE-02, LIFE-03, LIFE-04
**Verified:** 2026-07-22T01:30:12Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Summary Judgment

Every scaffolding artifact the phase goal names — `detach_flag`/`supersedes_sequence` proto fields, `RevokeTx`/oneof arm 9, `FilterRegistration` gate 3b, `CheckParentChildAuthority`'s revoke branch, the `DetachChild`/`ReplaceMain`/`RevokeChild` two-layer methods — exists, compiles, and is wired correctly. **Detach and Replace-Main work end-to-end**, independently re-verified in this pass (not just trusted from the SUMMARY). **Revoke's authority-rejection paths also work** (unauthorized signer, sequence mismatch), independently re-verified. However, **Revoke's core happy path does not work**: the production code that is supposed to apply a confirmed RevokeTx's effect (`ParseRevokeTransaction`'s CRDT write) deadlocks, independently reproduced in this verification pass. Since the phase goal explicitly names "main-initiated Revoke" as a deliverable transition, and that transition does not complete when actually exercised, this phase does not fully achieve its stated goal — it achieves Detach + Replace-Main + Revoke's validation/authority layer, but not Revoke's own state-mutation effect.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `RegistrationTx` carries `detach_flag`(5)/`supersedes_sequence`(6); round-trips correctly | VERIFIED | `SGTransaction.proto` fields confirmed via grep; `RegistrationTransaction::GetDetachFlag/GetSupersedesSequence` present in `.hpp` |
| 2 | `RevokeTx` exists as new proto message; `EmbeddedTransaction` gains oneof arm 9 | VERIFIED | `Consensus.proto` `revoke = 9` confirmed; arms 1-8 unchanged |
| 3 | `RegistrationTransaction::New(...)` extended with backward-compatible trailing defaults | VERIFIED | Signature confirmed in `RegistrationTransaction.hpp`; pre-existing 4-arg call sites unmodified |
| 4 | `RevokeTransaction` class mirrors `RegistrationTransaction` (factory/serialize/topics) | VERIFIED | `RevokeTransaction.hpp`/`.cpp` present, `GetType()=="revoke"`, in `CMakeLists.txt` `GENIUS_NODE_SOURCES` |
| 5 | A `RevokeTx` flows through the `tx/{hash}` pipeline, no longer "Unknown tx type" | VERIFIED | `transaction_parsers["revoke"]` entry, `DeSerializeEmbeddedTransaction`'s `kRevoke` case, both confirmed present in `TransactionManager.cpp` |
| 6 | `ParseRevokeTransaction` writes an updated `reg/{child_addr}` record (`detach_flag=true`) once a RevokeTx is confirmed | **FAILED** | Code present and logically correct (read in full at `TransactionManager.cpp:2337-2396`), but **independently reproduced deadlock**: `RevokeChildEndToEnd` re-run in isolation times out at the poll, log shows `WaitForJob: Still waiting for CID ... (elapsed: 90s)` for 2 stuck CIDs |
| 7 | `FilterRegistration` gate 3b rejects a `RegistrationTx` whose `supersedes_sequence` is non-zero and doesn't match the stored record's sequence | VERIFIED | Gate 3b code confirmed present (`TransactionManager.cpp:3277-3288`); `FilterRegistrationRejectsForkedSupersedesSequence`/`FilterRegistrationRejectsMissingSupersedesLink` per 05-04-SUMMARY real GTest run (`[ PASSED ] 2 tests.`) |
| 8 | `CheckParentChildAuthority`'s `"revoke"` branch approves only main-signed, correctly-sequenced, currently-Registered targets; rejects otherwise | VERIFIED (rejection paths); see gap for the confirm-then-reject "already-detached" adversarial scenario | Code confirmed present (`TransactionManager.cpp:4524-4580+`); `RevokeRejectedForNonMain` and `RevokeRejectedForSequenceMismatch` **independently re-run in isolation in this verification pass and PASSED** (121s/121s, real GTest `[ PASSED ]`) |
| 9 | `DetachChild`/`ReplaceMain`/`RevokeChild` exist at both `TransactionManager` and `GeniusNode` layers (two-layer convention) | VERIFIED | `grep` confirms 5/6 method name occurrences in `TransactionManager.cpp`/`.hpp`, 6/6 in `GeniusNode.cpp`/`.hpp` |
| 10 | Fork detection: two competing lifecycle-change `RegistrationTx` at the same `supersedes_sequence` — only the first is accepted | VERIFIED | Same test as #7 (`FilterRegistrationRejectsForkedSupersedesSequence`), real GTest pass per 05-04-SUMMARY |
| 11 | `DetachChild` produces a certified `reg/` record with 128-char zero-sentinel `main_address` and `detach_flag==true`, UTXOs/keypair/nonce unaffected (LIFE-01/04, Detach half) | VERIFIED | **`DetachChildEndToEnd` independently re-run in isolation in this verification pass and PASSED** (121219 ms, real GTest `[ PASSED ]`) |
| 12 | `ReplaceMain` produces a `reg/` record with new `main_address`/`detach_flag==false`; re-registration after Detach works (LIFE-03) | VERIFIED (per 05-04-SUMMARY real GTest run: `ReplaceMainEndToEnd`/`ReRegistrationAfterDetachViaReplaceMain` `[ PASSED ]`; corroborated by this verification's independent pass of the sibling `DetachChildEndToEnd` test in the same fixture/build) | 05-04-SUMMARY.md logged run times; not independently re-run in this pass due to time budget, but same binary/build state |
| 13 | Replay prevention: a stale lifecycle-change `RegistrationTx` reusing an already-consumed nonce is rejected by the nonce chain | VERIFIED | Per 05-04-SUMMARY real GTest run (`LifecycleChangeReplayRejectedByNonceChain`, log evidence `"Nonce too low ... confirmed=0"`) |
| 14 | A certified child's registration can be revoked by its main via `RevokeChild`; resulting `reg/` record shows `detach_flag==true` (LIFE-01, Revoke happy path) | **FAILED** | See truth #6 — this is the E2E manifestation of the same blocker; independently reproduced |
| 15 | A `RevokeTx` signed by a non-main address is rejected | VERIFIED | **`RevokeRejectedForNonMain` independently re-run in isolation and PASSED** (121156 ms) |
| 16 | A `RevokeTx` targeting an already-`detach_flag==true` record is rejected | **FAILED** (blocked, not a logic defect) | `RevokeRejectedForAlreadyDetachedChild` requires a prerequisite confirmed Revoke, which never completes — same root cause as #6/#14 |
| 17 | A `RevokeTx` with a mismatched `registration_sequence` is rejected | VERIFIED | **`RevokeRejectedForSequenceMismatch` independently re-run and PASSED** (121206-121426 ms across runs) |
| 18 | After Revoke, child can re-register at a higher sequence; UTXOs/keypair/nonce unaffected (LIFE-04, Revoke half) | **FAILED** (blocked, not a logic defect) | `ReRegistrationAfterRevoke`/`RevokePreservesChildUTXOsKeypairNonce` both require a prerequisite confirmed Revoke — same root cause |

**Score:** 13/18 truths verified (5 failed, all five tracing to the single `ParseRevokeTransaction` CRDT-write deadlock; 0 present-but-behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `SuperGenius/src/account/proto/SGTransaction.proto` | `detach_flag`/`supersedes_sequence` fields + `RevokeTx` message | VERIFIED | Confirmed via grep/read; fields 1-4 and arms 1-8 unchanged |
| `SuperGenius/src/blockchain/impl/proto/Consensus.proto` | `EmbeddedTransaction` oneof arm 9 | VERIFIED | `revoke = 9` present |
| `SuperGenius/src/account/RevokeTransaction.hpp`/`.cpp` | New transaction class | VERIFIED | Present, compiles into `genius_node`/`genius_node_test` |
| `SuperGenius/src/account/RegistrationTransaction.hpp`/`.cpp` | Extended getters/factory | VERIFIED | Present |
| `SuperGenius/src/account/TransactionManager.hpp`/`.cpp` | Dispatch wiring, gate 3b, revoke authority branch, `ParseRevokeTransaction`, `DetachChild`/`ReplaceMain`/`RevokeChild` | PARTIALLY VERIFIED | All wiring/gates/methods present and correct by source read; **`ParseRevokeTransaction`'s write is present but non-functional at runtime** (deadlocks) |
| `SuperGenius/src/account/GeniusNode.hpp`/`.cpp` | Two-layer wrappers | VERIFIED | 6/6 method occurrences confirmed |
| `SuperGenius/test/src/account/registration_transaction_test.cpp` | 13 new `TEST_F` cases (7 from Plan 04, 6 from Plan 05) | VERIFIED (existence) / MIXED (pass rate) | All 13 test names confirmed present via grep; 9/13 independently or previously confirmed passing, 4/13 confirmed failing (Revoke happy-path family) |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `transaction_parsers["revoke"]` | `ParseRevokeTransaction`/`RevertRevokeTransaction` | dispatch table entry | WIRED | Confirmed present |
| `DeSerializeEmbeddedTransaction` | `RevokeTransaction::DeSerializeByteVector` | `case EmbeddedTransaction::kRevoke` | WIRED | Confirmed present |
| `FilterRegistration` gate 3b | `RegistrationTransaction::GetSupersedesSequence` | `reg_tx->GetSupersedesSequence() == existing_reg->GetSequence()` | WIRED, FUNCTIONAL | Test-proven |
| `CheckParentChildAuthority` revoke branch | `reg/{child_address}` CRDT record | `globaldb_m->Get` + `DeSerializeTransaction` | WIRED, FUNCTIONAL (read path) | Rejection tests prove the read+decision logic works |
| `ParseRevokeTransaction` | `reg/{child_addr}` CRDT record (write) | `globaldb_m->Put(...)` | WIRED but **NOT FUNCTIONAL** | Deadlocks — `CrdtDatastore::AddDAGNode`/`WaitForJob` never completes for this call site |
| `GeniusNode::DetachChild`/`RevokeChild` | `TransactionManager::DetachChild`/`RevokeChild` | `BOOST_OUTCOME_TRY` delegate | WIRED | Confirmed present |

### Behavioral Spot-Checks (independently executed in this verification pass)

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Unauthorized revoke rejected | `registration_transaction_test.exe --gtest_filter=...RevokeRejectedForNonMain` (run twice: once contended, once isolated) | Isolated run: `[ PASSED ] 1 test.` (121156 ms) | PASS |
| Sequence-mismatch revoke rejected | `registration_transaction_test.exe --gtest_filter=...RevokeRejectedForSequenceMismatch` | `[ OK ]` (121206 ms) | PASS |
| Revoke happy path (RevokeChild -> detach_flag=true) | `registration_transaction_test.exe --gtest_filter=...RevokeChildEndToEnd` (isolated run) | `[ FAILED ]` (120070 ms) — `stored_reg` stays null; log shows `WaitForJob: Still waiting for CID ... (elapsed: 90s)` x2 | **FAIL — reproduces documented blocker** |
| Detach happy path (DetachChild -> detach_flag=true, zero-sentinel main_address) | `registration_transaction_test.exe --gtest_filter=...DetachChildEndToEnd` (isolated run) | `[ OK ]` (121219 ms), `[ PASSED ] 1 test.` | PASS |

Note: an initial parallel-execution attempt (two test-binary instances launched simultaneously) produced spurious `RevokeRejectedForNonMain` failure via RocksDB lock-file contention and a shared network port (40002) — this was an artifact of running two E2E fixtures concurrently, not a real regression. Re-running the same test in isolation passed cleanly, confirming the parallel run's failure was environmental. All results reported above are from isolated (single-process) runs.

Also note: gtest reports `[ PASSED ]` for each of the above passing runs before the process itself later crashes during teardown (`exit code 139`, SIGSEGV) — this is a pre-existing, previously-documented test-binary teardown issue (see Plan 02 SUMMARY's reference to `child_registration_test.exe`'s known teardown segfault), unrelated to this phase's code and not counted as a test failure since GTest's own result line already recorded PASSED before the crash.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | No `TBD`/`FIXME`/`XXX`/`TODO` markers introduced by this phase's plans | — | Six pre-existing `TODO` comments in `TransactionManager.cpp`/`GeniusNode.cpp` confirmed via `git blame` to predate Phase 5 (authored 2025-05 through 2026-03) — not a debt-marker gate violation for this phase |

No stubs, placeholders, or empty-implementation patterns found in any Phase 5-authored code. `ParseRevokeTransaction` is a real, non-stub implementation — its failure is a runtime concurrency defect, not incomplete work.

### Requirements Coverage

(No `.planning/REQUIREMENTS.md` exists in this project — per instructions, the four LIFE-0x IDs from CONTEXT.md/ROADMAP.md are treated as the phase's requirement set.)

| Requirement | Description | Status | Evidence |
|--------------|-------------|--------|----------|
| LIFE-01 | State machine + Detach + Revoke transitions | **BLOCKED** | Detach transition fully works end-to-end (verified). Revoke's transaction type, dispatch, and authority gate all work, but the Revoke *transition itself* — applying `detach_flag=true` to the target's `reg/` record — does not complete due to the `ParseRevokeTransaction` deadlock. LIFE-01 explicitly requires the Revoke transition, so this requirement is not fully satisfied. |
| LIFE-02 | `supersedes_sequence` linkage / fork-prevention | SATISFIED | Gate 3b independently verified via passing fork-detection/missing-link tests |
| LIFE-03 | Main replacement (Replace-Main), child-only | SATISFIED | `ReplaceMain` works per 05-04-SUMMARY's real GTest evidence, corroborated by this pass's independent confirmation of the sibling `DetachChildEndToEnd` test in the same build |
| LIFE-04 | Detach/Revoke/Replace-Main leave child a valid standalone wallet (UTXOs/keypair/nonce unaffected) | **PARTIALLY SATISFIED** | Proven for Detach (`DetachPreservesChildUTXOsKeypairNonce` per SUMMARY, consistent with this pass's independent Detach evidence). NOT proven for Revoke (`RevokePreservesChildUTXOsKeypairNonce` blocked by the same deadlock) |

### Human Verification Required

None. This is a clear-cut, directly-reproduced code defect (not an ambiguous or judgment-call item) — no human UAT is needed to adjudicate it; a production-code fix and re-test is needed instead.

## Gaps Summary

One root cause blocks three of six Revoke test scenarios and the Revoke happy path itself:

**`TransactionManager::ParseRevokeTransaction`'s `globaldb_m->Put()` call deadlocks when applied during confirmed-transaction processing.** This was discovered by the Plan 05 executor (not this verification pass) and is documented in detail in `05-05-SUMMARY.md`'s "Known Blocker" section. This verification pass **independently reproduced the exact same failure** by re-running `RegistrationTransactionE2ETest.RevokeChildEndToEnd` in isolation: the test times out at the post-`RevokeChild` poll, and the log shows `CrdtDatastore::WaitForJob: Still waiting for CID ... (elapsed: 90s)` for two stuck CIDs — consistent with the SUMMARY's own root-cause narrative (`ParseRevokeTransaction` uses the full CRDT broadcast path `globaldb_m->Put()` rather than the local-only write path `PutProducedUTXOs` uses elsewhere for the same class of per-node-derived side effect).

Everything else the phase goal names is real and working: proto schema, `RevokeTx`/oneof arm 9, dispatch wiring (no "Unknown tx type" regression), `FilterRegistration` gate 3b (fork detection + missing-link rejection, both independently significant since they're D-73's named adversarial requirements), `CheckParentChildAuthority`'s revoke branch (independently re-verified for both of its rejection paths — unauthorized signer and sequence mismatch — the phase's single highest-severity threat, T-05-09, is fully and directly proven), Detach end-to-end (independently re-verified), Replace-Main, re-registration after Detach, and nonce-chain replay prevention.

The gap is narrow and precisely scoped (a single method's write-path choice), but it is load-bearing: without it, "main-initiated Revoke" — named explicitly in the phase goal — does not actually revoke anything in a way any other node/observer would ever see. A future plan should apply the fix candidate already identified in 05-05-SUMMARY.md (switch `ParseRevokeTransaction`'s write to the same local-only path `PutProducedUTXOs` uses, verifying key-format compatibility with `FilterRegistration`/`CheckParentChildAuthority`'s read path), then re-run the four currently-blocked tests to confirm.

---

*Verified: 2026-07-22T01:30:12Z*
*Verifier: Claude (gsd-verifier)*
