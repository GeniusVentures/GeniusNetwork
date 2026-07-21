---
phase: 03-parent-child-transfer-authority
plan: 04
subsystem: consensus
tags: [consensus, transfer, recovery, regression-test, cpp]

# Dependency graph
requires:
  - phase: 03-parent-child-transfer-authority (plan 02)
    provides: "TransactionManager::CheckParentChildAuthority gate, CheckTransactionAuthorization D-60 branch, ValidateWitness D-60 branch"
  - phase: 03-parent-child-transfer-authority (plan 03)
    provides: "TransactionManager::RecoverFromChild(child_address, amount, token_id)"
provides:
  - "Automated E2E regression coverage for CONS-01, CONS-02, D-21, REGR-01, REGR-02, REGR-03 — the phase's final empirical proof"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "CertifyChildRegistration test helper: manual CRDT injection of a child registration + real Blockchain::CreateConsensusProposal/SubmitProposal/CheckCertificate certification, mirroring TransactionManager.cpp's own real-transaction submission recipe (verified against TransactionManager.cpp:1344-1371) rather than mocking certification"
    - "Second bare GeniusAccount (child_account_, no own TransactionManager) added to RegistrationTransactionE2ETest fixture — sufficient because the gates under test operate on whatever tx object reaches ValidateTransactionForConsensus, regardless of which node constructed it"

key-files:
  created: []
  modified:
    - SuperGenius/test/src/account/registration_transaction_test.cpp
    - SuperGenius/src/account/TransactionManager.hpp
    - SuperGenius/src/account/TransactionManager.cpp

key-decisions:
  - "Discovered and fixed a pre-existing gap while building the CertifyChildRegistration helper: TransactionManager's transaction_parsers dispatch table had no entry for the \"registration\" tx type, so ValidateTransactionForConsensus rejected every registration transaction as \"Unknown tx type\" before Blockchain::CheckCertifiedParent's CheckCertificate gate (D-26, Plan 01) could ever resolve true. Added a no-op ParseRegistrationTransaction/RevertRegistrationTransaction pair — registration state is already fully handled by FilterRegistration/RegElementCallback, independent of this post-confirmation dispatch table; this entry only satisfies the membership check."
  - "child_account_ is a bare keypair-only GeniusAccount with no TransactionManager of its own (per 03-RESEARCH.md's Open Question #1 simpler-shape recommendation) — avoided standing up a second full node."
  - "REGR-02 (PayDev) is covered transitively via ChildTransferToDevWalletUnaffected rather than instantiating a full GeniusNode, justified by PayDev's verified thin-wrapper implementation (GeniusNode.cpp:2331-2334 — `return TransferFunds(amount, dev_config_.Addr, token_id);`, zero separate code path)."
  - "MainRecoveryWrongDestinationRejected and ChildCannotClaimMainAsSourceRejected both isolate WHICH gate rejects (CheckParentChildAuthority vs CheckTransactionAuthorization) rather than asserting only that the overall tx fails — proving D-21 and REGR-03 are enforced by the specific mechanism the requirement describes, not an incidental side effect."

requirements-completed: [CONS-01, CONS-02, REGR-01, REGR-02, REGR-03]

coverage:
  - id: D1
    description: "MainFundsChildApprovedByGate: ordinary main-signed transfers to a registered-child address and to an arbitrary unregistered address both succeed unchanged"
    requirement: "CONS-01"
    verification:
      - kind: integration
        ref: "registration_transaction_test.exe --gtest_filter=RegistrationTransactionE2ETest.MainFundsChildApprovedByGate"
        status: pass
    human_judgment: false
  - id: D2
    description: "MainRecoversFromChildApproved: a certified child's funds are recoverable via RecoverFromChild, and both CheckParentChildAuthority and CheckTransactionAuthorization independently approve the resulting transaction"
    requirement: "CONS-02"
    verification:
      - kind: integration
        ref: "registration_transaction_test.exe --gtest_filter=RegistrationTransactionE2ETest.MainRecoversFromChildApproved"
        status: pass
    human_judgment: false
  - id: D3
    description: "MainRecoveryWrongDestinationRejected: a certified-child-sourced recovery tx to a non-matching destination is rejected specifically by CheckParentChildAuthority (D-21), while CheckTransactionAuthorization still approves the signature"
    requirement: "CONS-02"
    verification:
      - kind: integration
        ref: "registration_transaction_test.exe --gtest_filter=RegistrationTransactionE2ETest.MainRecoveryWrongDestinationRejected"
        status: pass
    human_judgment: false
  - id: D4
    description: "ChildTransferToArbitraryAndMainUnaffected: child-self-signed transfers to an arbitrary address and to its registered main are both approved unchanged by both gates"
    requirement: "REGR-01"
    verification:
      - kind: integration
        ref: "registration_transaction_test.exe --gtest_filter=RegistrationTransactionE2ETest.ChildTransferToArbitraryAndMainUnaffected"
        status: pass
    human_judgment: false
  - id: D5
    description: "ChildTransferToDevWalletUnaffected: same child-self-signed shape covering PayDev's destination pattern; PayDev verified as a thin TransferFunds wrapper, so this transitively covers REGR-02"
    requirement: "REGR-02"
    verification:
      - kind: integration
        ref: "registration_transaction_test.exe --gtest_filter=RegistrationTransactionE2ETest.ChildTransferToDevWalletUnaffected"
        status: pass
    human_judgment: false
  - id: D6
    description: "ChildCannotClaimMainAsSourceRejected: a child-signed transaction claiming src=main_addr is rejected by CheckTransactionAuthorization — the core child-cannot-spend-main invariant, unaffected by Plans 01-03's new certified-main branch"
    requirement: "REGR-03"
    verification:
      - kind: integration
        ref: "registration_transaction_test.exe --gtest_filter=RegistrationTransactionE2ETest.ChildCannotClaimMainAsSourceRejected"
        status: pass
    human_judgment: false
  - id: D7
    description: "Full registration_transaction_test binary (18 pre-existing + 6 new) passes with zero regressions"
    requirement: "CONS-06"
    verification:
      - kind: integration
        ref: "SuperGenius/build/Windows/Release/test_bin/Release/registration_transaction_test.exe -> [==========] 24 tests from 2 test suites ran. [  PASSED  ] 24 tests."
        status: pass
    human_judgment: false

duration: ~3.5hr (includes discovery + fix of the registration-parser dispatch gap, plus multiple full ~26-38min registration_transaction_test.exe runs during iteration)
completed: 2026-07-20
status: complete
---

# Phase 3 Plan 04: CONS-01/CONS-02/REGR-01/02/03 Regression Tests Summary

**Proves, with automated E2E tests against the real consensus pipeline, that CONS-01 and CONS-02 work correctly and that REGR-01/02/03 confirm every existing child-signed path is unaffected by Plans 01-03 — the phase's final empirical closeout.**

## Performance

- **Duration:** ~3.5 hours (dominated by iterative debugging of a real pre-existing bug found mid-implementation — see Decisions — plus several full ~26-38 minute `registration_transaction_test.exe` runs)
- **Completed:** 2026-07-20
- **Tasks:** 2 completed
- **Files modified:** 3

## Accomplishments

- Extended `RegistrationTransactionE2ETest` with `child_account_` (a second bare `GeniusAccount`) and `CertifyChildRegistration(...)`, a test helper that manually injects a child registration into the CRDT and certifies it via the exact same `Blockchain::CreateConsensusProposal` → `SubmitProposal` → poll `CheckCertificate` recipe real registration transactions use (verified against `TransactionManager.cpp:1344-1371`) — no mocking of certification.
- **Task 1** added three tests: `MainFundsChildApprovedByGate` (CONS-01), `MainRecoversFromChildApproved` (CONS-02 happy path, asserting both `CheckParentChildAuthority` and `CheckTransactionAuthorization` independently approve), `MainRecoveryWrongDestinationRejected` (D-21, isolating that `CheckParentChildAuthority` specifically is what rejects a mismatched destination).
- **Task 2** added three tests: `ChildTransferToArbitraryAndMainUnaffected` (REGR-01), `ChildTransferToDevWalletUnaffected` (REGR-02, transitively via `PayDev`'s verified thin-wrapper equivalence), `ChildCannotClaimMainAsSourceRejected` (REGR-03, isolating that `CheckTransactionAuthorization` specifically rejects a child signing as main).
- **Discovered and fixed a real pre-existing bug while building the certification helper**: `TransactionManager`'s `transaction_parsers` dispatch table had no entry for the `"registration"` tx type. Without it, `ValidateTransactionForConsensus`'s `CheckTransactionWellFormed` step rejected *every* registration transaction as `"Unknown tx type"` before it could ever reach a confirmed state — meaning `Blockchain::CheckCertifiedParent`'s `CheckCertificate` gate (D-26, added in Plan 01) could never resolve `true` for any real registration proposal submitted through the normal pipeline, silently breaking the entire certified-parent mechanism this phase depends on. Fixed with a narrowly-scoped no-op `ParseRegistrationTransaction`/`RevertRegistrationTransaction` pair (registration state is already fully owned by `FilterRegistration`/`RegElementCallback`, independent of this dispatch table).
- Full `registration_transaction_test.exe`: **24/24 tests pass** (18 pre-existing + 6 new), confirmed via directly-observed log output. Exits via the documented pre-existing post-`PASSED` teardown segfault (`libp2p`/`boost::asio` thread-join issue, tracked in `STATE.md`) — not a regression from this phase.

## Task Commits

Committed inside the `SuperGenius` submodule:

1. **Registration-parser dispatch fix** (supports Task 1's certification helper) - `8ed16e11` (fix)
2. **Task 1 + Task 2: CONS-01/CONS-02/D-21/REGR-01/REGR-02/REGR-03 test cases** - `a289a464` (test)

**SuperGenius submodule pointer bump (outer repo):** committed alongside this SUMMARY (see final commit)

_Note: this is a sequential (non-worktree) executor because the plan touches the `SuperGenius` git submodule._

## Files Created/Modified
- `SuperGenius/test/src/account/registration_transaction_test.cpp` - `child_account_` fixture member, `CertifyChildRegistration` helper, six new `TEST_F` cases
- `SuperGenius/src/account/TransactionManager.hpp` - declares `ParseRegistrationTransaction`/`RevertRegistrationTransaction`
- `SuperGenius/src/account/TransactionManager.cpp` - registers `"registration"` in `transaction_parsers`, implements both no-op methods

## Decisions Made
- Registration-parser fix scoped to a no-op pair rather than touching `FilterRegistration`/`RegElementCallback` — the actual registration acceptance/validation logic was already correct and untouched; only the post-confirmation dispatch-table membership check was missing an entry.
- `child_account_` kept as a bare `GeniusAccount` (no second `TransactionManager`) — the gates under test operate on the constructed `tx` object directly, so a full second node was unnecessary overhead.
- REGR-02 covered transitively through `ChildTransferToDevWalletUnaffected` rather than instantiating a full `GeniusNode` to call `PayDev` directly, justified by `PayDev`'s verified thin-wrapper implementation.

## Deviations from Plan

**One necessary deviation, outside the plan's declared `files_modified` scope:** the plan listed only `registration_transaction_test.cpp` as a modified file. Implementing `CertifyChildRegistration` surfaced the pre-existing `transaction_parsers` dispatch-table gap described above, which required a small fix in `TransactionManager.hpp`/`.cpp` to make certification possible at all — without it, no test in this plan (or any future real registration flow) could ever reach a certified state. This is a minimal, narrowly-scoped, no-op-only fix; it does not touch any gate logic from Plans 01-03.

## Issues Encountered

**Extended iteration time due to the dispatch-table bug.** The certification helper initially failed silently (registrations never certified) because of the missing `"registration"` dispatch-table entry described above; diagnosing this required tracing `ValidateTransactionForConsensus` → `CheckTransactionWellFormed` → `transaction_parsers.find()` to find the actual rejection point, rather than a straightforward test-writing exercise. Several full-suite runs (~26-38 min each) were needed across the debug cycle. Final directly-observed result: `[==========] 24 tests from 2 test suites ran... [  PASSED  ] 24 tests.` followed by the known pre-existing teardown segfault (exit 139) — treated as a pass per the documented pattern.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All six phase requirements (CONS-01, CONS-02, CONS-06, REGR-01, REGR-02, REGR-03) now have direct automated regression coverage, all passing against the real `ValidateTransactionForConsensus` pipeline.
- This is the last plan in Phase 3. The phase is ready for goal-backward verification.
- No blockers carried forward beyond the pre-existing `child_registration_test.exe`-family teardown segfault issue already tracked in `STATE.md` (observed again in this plan's runs, confirmed unrelated to this phase's changes).

---
*Phase: 03-parent-child-transfer-authority*
*Completed: 2026-07-20*

## Self-Check: PASSED

- FOUND: `SuperGenius/test/src/account/registration_transaction_test.cpp`
- FOUND: `SuperGenius/src/account/TransactionManager.hpp`
- FOUND: `SuperGenius/src/account/TransactionManager.cpp`
- FOUND: `.planning/phases/03-parent-child-transfer-authority/03-04-SUMMARY.md`
- FOUND: SuperGenius commit `8ed16e11` (dispatch-table fix)
- FOUND: SuperGenius commit `a289a464` (Task 1 + Task 2 tests)
