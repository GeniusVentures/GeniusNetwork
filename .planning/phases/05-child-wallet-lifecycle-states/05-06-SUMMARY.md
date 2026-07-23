---
phase: 05-child-wallet-lifecycle-states
plan: 06
subsystem: consensus
tags: [crdt, mutex, deadlock, revoke, transaction-manager, gtest]

# Dependency graph
requires:
  - phase: 05-child-wallet-lifecycle-states (05-02, 05-05)
    provides: Revoke dispatch wiring (ParseRevokeTransaction), FilterRegistration gate 3b, and the six Revoke adversarial/E2E tests that this plan makes pass
provides:
  - CrdtDatastore::PutKeyLocal / GlobalDB::PutLocal — local-only, non-broadcast CRDT write path
  - CrdtSet::mutex_ as std::recursive_mutex — the actual deadlock fix
  - Working RevokeChild lifecycle transition (reg/ mutation now lands) and full Revoke test coverage
affects: [future test-infra/node-shutdown-hygiene phase (segfault-on-exit), any future CrdtSet reentrancy work]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "CrdtDatastore::PutKeyLocal for per-node-derived, deterministically-recomputed CRDT side effects that must not go through DAG broadcast"
    - "CRDTFixture::SetUpTestSuite defensive cleanup for cross-run leftover test directories"

key-files:
  created: []
  modified:
    - SuperGenius/src/crdt/crdt_datastore.hpp
    - SuperGenius/src/crdt/impl/crdt_datastore.cpp
    - SuperGenius/src/crdt/globaldb/globaldb.hpp
    - SuperGenius/src/crdt/globaldb/globaldb.cpp
    - SuperGenius/src/crdt/crdt_set.hpp
    - SuperGenius/src/account/TransactionManager.cpp
    - SuperGenius/test/src/account/registration_transaction_test.cpp
    - SuperGenius/test/testutil/storage/base_crdt_test.cpp

key-decisions:
  - "Root cause was CrdtSet::mutex_ reentrancy (non-recursive std::mutex held across a synchronous callback that re-enters PutElems), not the plan's own PutKeyLocal-only hypothesis"
  - "Kept PutKeyLocal/PutLocal alongside the recursive_mutex fix — architecturally correct on its own merits, even though it alone didn't fix the deadlock"
  - "Test-file nonce and previous_hash fixes were in-scope despite the plan's 'no test code changes' line — both are pre-existing test bugs blocking verification of the plan's real target, explicitly authorized by the user"

patterns-established:
  - "A hang/deadlock diagnosis should be grounded in an actual stack trace, not log-timing correlation alone — the original 05-05/05-VERIFICATION hypothesis was wrong despite being log-consistent"

requirements-completed: [LIFE-01, LIFE-04]

coverage:
  - id: D1
    description: "TransactionManager::ParseRevokeTransaction's reg/{child_addr} write completes synchronously without deadlocking (CrdtSet::mutex_ -> std::recursive_mutex; PutKeyLocal/PutLocal added as the local-only write path)"
    requirement: "LIFE-01"
    verification:
      - kind: e2e
        ref: "registration_transaction_test.exe#RegistrationTransactionE2ETest.RevokeChildEndToEnd"
        status: pass
      - kind: e2e
        ref: "registration_transaction_test.exe#RegistrationTransactionE2ETest.RevokeRejectedForAlreadyDetachedChild"
        status: pass
    human_judgment: false
  - id: D2
    description: "Post-revoke invariants hold: child can re-register at a higher sequence, and UTXOs/keypair/nonce are unaffected by revoke"
    requirement: "LIFE-04"
    verification:
      - kind: e2e
        ref: "registration_transaction_test.exe#RegistrationTransactionE2ETest.ReRegistrationAfterRevoke"
        status: pass
      - kind: e2e
        ref: "registration_transaction_test.exe#RegistrationTransactionE2ETest.RevokePreservesChildUTXOsKeypairNonce"
        status: pass
    human_judgment: false
  - id: D3
    description: "Pre-existing Revoke authority-rejection tests remain unaffected by the fix"
    verification:
      - kind: e2e
        ref: "registration_transaction_test.exe#RegistrationTransactionE2ETest.RevokeRejectedForNonMain"
        status: pass
      - kind: e2e
        ref: "registration_transaction_test.exe#RegistrationTransactionE2ETest.RevokeRejectedForSequenceMismatch"
        status: pass
    human_judgment: false

# Metrics
duration: ~4-5h across two sessions (live-debugging with the user; root cause diverged from the plan's own hypothesis)
completed: 2026-07-23
status: complete
---

# Phase 5 Plan 06 (Gap Closure): Revoke Deadlock Fix Summary

**Fixed the ParseRevokeTransaction deadlock via CrdtSet::mutex_ -> std::recursive_mutex (not the plan's own PutKeyLocal-only hypothesis), then closed two separate pre-existing test bugs (nonce collision, missing previous_hash) that were blocking verification of the fix itself.**

## Performance

- **Duration:** ~4-5h across two sessions
- **Tasks:** 3 (Task 1: fix, Task 2: verification, Task 3: human checkpoint)
- **Files modified:** 8 (6 production/test files in SuperGenius across the two sessions, plus this SUMMARY and the outer submodule bump)

## Accomplishments
- Root-caused and fixed the real deadlock: `CrdtSet::mutex_` was a plain `std::mutex` held across `PutElems`'s synchronous `putHookFunc_` callback, which could re-enter `PutElems` on the same thread via `ConsensusManager::CertificateReceived` -> confirmed-tx processing -> `ParseRevokeTransaction` -> `PutKeyLocal` -> `set_->Merge` -> `PutElems` again. Changed to `std::recursive_mutex`. Confirmed via a live debugger stack trace plus zero deadlock reproductions across 46+ test executions.
- Added `CrdtDatastore::PutKeyLocal`/`GlobalDB::PutLocal` (the plan's original proposed fix) — necessary but not sufficient on its own; kept because it's still the architecturally correct way to apply a per-node-derived side effect without unnecessary DAG broadcast.
- Fixed a separate, pre-existing, 100%-deterministic test bug in `ReRegistrationAfterRevoke`: the manually-built re-registration DAGStruct hardcoded `nonce=0`, colliding with the child's original registration (also nonce=0) — changed to `nonce=1`.
- Fixed a second issue the nonce fix alone exposed: nonce>0 requires `previous_hash` to resolve to a certified transaction for the same address (`EvaluateTransactionReplayProtection`), which the test never set — added `dag.set_previous_hash(child_reg.GetHash())`.
- Added defensive cleanup in `CRDTFixture::SetUpTestSuite()` for leftover `CRDT.Datastore.TEST`/`CRDT.Datastore.TEST.unit_N` directories from a prior run's segfault-on-exit (a separate, already-tracked issue) — the fixture's counter restarts at 0 every process, so stale directories from a crashed run could collide with a fresh run's paths.
- All 6 Revoke tests (`RevokeChildEndToEnd`, `RevokeRejectedForAlreadyDetachedChild`, `RevokeRejectedForNonMain`, `RevokeRejectedForSequenceMismatch`, `RevokePreservesChildUTXOsKeypairNonce`, `ReRegistrationAfterRevoke`) now pass reliably in isolation, with zero `WaitForJob: Still waiting for CID` occurrences and zero replay-protection rejections.

## Task Commits

1. **Task 1: PutKeyLocal/PutLocal + the actual fix (CrdtSet::mutex_ -> recursive_mutex)** - `be369162` "Debugging results, for now" (SuperGenius submodule; committed directly by the user during live debugging, outside this session's controlled commit flow — retroactively confirmed by the user as their Task 3 approval for this code)
2. **Task 2: Verification** - no commit (verification-only task; see Verification Performed below)
3. **Task 3: Human checkpoint** - approved verbally by the user in the resuming session ("Yes, that commit was my approval") for `be369162`, and separately for the follow-on test fixes below

**Follow-on test fixes (this session, after Task 3 approval):** `5fd137dc` "fix(test): resolve ReRegistrationAfterRevoke nonce chain gap, clean stale CRDT test dirs" (SuperGenius submodule)

**Outer repo:** this SUMMARY.md + SuperGenius submodule pointer bump (e595a5d..5fd137d), committed together per this plan's `<output>` instruction.

## Files Created/Modified
- `SuperGenius/src/crdt/crdt_datastore.hpp` / `impl/crdt_datastore.cpp` - `PutKeyLocal`: local-only CRDT write, no DAG broadcast
- `SuperGenius/src/crdt/globaldb/globaldb.hpp` / `globaldb.cpp` - `PutLocal`: thin delegate to `PutKeyLocal`
- `SuperGenius/src/crdt/crdt_set.hpp` - `mutex_` changed from `std::mutex` to `std::recursive_mutex` (the actual deadlock fix)
- `SuperGenius/src/account/TransactionManager.cpp` - `ParseRevokeTransaction`'s `reg/` write now goes through `PutLocal`
- `SuperGenius/test/src/account/registration_transaction_test.cpp` - `ReRegistrationAfterRevoke`: nonce 0->1, added `previous_hash`
- `SuperGenius/test/testutil/storage/base_crdt_test.cpp` - `SetUpTestSuite` now clears leftover `CRDT.Datastore.TEST*` directories

## Decisions Made
- Chose `std::recursive_mutex` over deferring `putHookFunc_` invocation outside the lock (the more "architecturally clean" alternative) — smaller, more surgical change, and testing showed it worked. Deferred-hook-execution remains a candidate if reentrancy issues are later found elsewhere in `SetValue`'s priority-check logic.
- Kept `PutKeyLocal`/`PutLocal` even though they weren't the actual fix — still the right mechanism for a per-node-derived side effect that shouldn't trigger unnecessary DAG broadcast.
- Test-file nonce and previous_hash fixes were treated as in-scope despite the plan's stated "no test code changes" boundary — both are pre-existing, deterministic test bugs (not flakiness) that blocked verifying the plan's actual target; explicitly authorized by the user.

## Deviations from Plan

### Auto-fixed Issues

**1. [Root cause divergence] Plan's own PutKeyLocal/PutLocal hypothesis was necessary but not sufficient**
- **Found during:** Task 2 (verification) — 4/6 Revoke tests still failed after Task 1's PutKeyLocal/PutLocal change
- **Issue:** Live debugging (with the user, real debugger stack trace) found the actual deadlock was `CrdtSet::mutex_` reentrancy via `PutElems`'s synchronous callback chain, not the DAG-broadcast path the plan targeted
- **Fix:** Changed `CrdtSet::mutex_` from `std::mutex` to `std::recursive_mutex`
- **Files modified:** `SuperGenius/src/crdt/crdt_set.hpp`
- **Verification:** Zero deadlock reproductions across 46+ test executions across two sessions
- **Committed in:** `be369162` (same commit as Task 1, committed directly by the user)

**2. [Pre-existing test bug] ReRegistrationAfterRevoke nonce collision**
- **Found during:** Task 2 — `ReRegistrationAfterRevoke` failed 4/4, deterministically, at a different assertion than the deadlock
- **Issue:** The re-registration tx and the original registration tx both hardcoded `nonce=0` for the same child address; replay protection correctly rejected the second as "Nonce too low"
- **Fix:** Changed the re-registration DAGStruct's nonce to 1
- **Files modified:** `SuperGenius/test/src/account/registration_transaction_test.cpp`
- **Verification:** Isolated re-run after the fix
- **Committed in:** `5fd137dc`

**3. [Pre-existing test bug] ReRegistrationAfterRevoke missing previous_hash**
- **Found during:** This session, after applying fix #2 — new failure "Missing previous hash" from `EvaluateTransactionReplayProtection`
- **Issue:** Nonce>0 requires `previous_hash` to resolve to a certified tx for the same address; the manually-built DAGStruct never set it (production code sets this automatically via `FillDAGStruct`/`FillDAGStructForAddress`, but the test builds the DAGStruct by hand)
- **Fix:** Set `dag.set_previous_hash(child_reg.GetHash())` — `child_reg` is the account's certified nonce=0 registration
- **Files modified:** `SuperGenius/test/src/account/registration_transaction_test.cpp`
- **Verification:** 2 clean isolated runs, `validation(approve=3 reject=0)` in metrics, zero rejections
- **Committed in:** `5fd137dc`

**4. [Test infra hygiene] Leftover CRDT.Datastore.TEST* directories**
- **Found during:** This session — user reported having to manually delete `CRDT.Datastore.TEST/`/`CRDT.Datastore.TEST.unit_N` directories left at the outer repo root
- **Issue:** `CRDTFixture`'s destructor cleanup can be skipped by the known, separately-tracked segfault-on-exit issue; since the fixture counter restarts at 0 every process, a fresh run's paths can collide with a prior crashed run's leftovers
- **Fix:** Added defensive cleanup in `CRDTFixture::SetUpTestSuite()` clearing `CRDT.Datastore.TEST` and any `CRDT.Datastore.TEST.unit_*` siblings before any fixture runs
- **Files modified:** `SuperGenius/test/testutil/storage/base_crdt_test.cpp`
- **Verification:** Manually confirmed no leftover directories after subsequent test runs (including one that segfaulted-on-exit as expected)
- **Committed in:** `5fd137dc`

---

**Total deviations:** 4 (1 root-cause divergence, 2 pre-existing test bugs, 1 test-infra hygiene fix)
**Impact on plan:** All four were necessary to actually prove the plan's own success criteria (LIFE-01's Revoke transition, LIFE-04's Revoke-half invariants). No scope creep beyond what was needed to make the existing tests correctly exercise already-implemented behavior.

## Issues Encountered
- No CLI debugger (`cdb.exe`/`windbg.exe`) was available in the automated environment for the initial hypothesis testing; the user separately used Visual Studio's debugger to capture the live stack trace that found the actual root cause.
- The full unfiltered regression suite (37 tests) takes ~75-90 minutes to run to completion (each E2E test has ~2min of built-in polling/timeout waits) — verification in this session used isolated per-test runs plus partial full-suite runs (9/9 and 5/5 passing subsets) rather than one uninterrupted full pass, per explicit user direction to prioritize confirming the specific target test first.
- Every test run of `registration_transaction_test.exe` segfaults on process exit, after GTest already prints its PASS/FAIL summary (exit code 139) — this is a separate, pre-existing, already-tracked issue (see `.planning/phases/01-child-balance-query/deferred-items.md`), not a regression from this plan.

## Next Phase Readiness
- Phase 5 (Child Wallet Lifecycle States) is now fully verified: proto schema, dispatch wiring, `FilterRegistration` gate 3b, `CheckParentChildAuthority`'s Detach/Revoke branches, Detach, Replace-Main, and Revoke (including its state-mutation effect) all work end-to-end with direct automated test coverage.
- GeniusSDK does not yet expose Detach/Revoke/Replace-Main through the public C API — this was never in Phase 5's scope (which stops at the `TransactionManager`/`GeniusNode` method layer, mirroring Wave 3's own "two-layer" framing). A future phase would be needed to add `GeniusSDKDetachChild`/`GeniusSDKRevokeChild`/`GeniusSDKReplaceMain` wrappers, mirroring the Phase 2/4 pattern, if external games/apps need to trigger these transitions directly.
- The segfault-on-exit issue and the earlier `RegistrationTransactionE2ETest` fixture bring-up idling observation remain open, tracked separately, and are candidates for a future test-infra/node-shutdown-hygiene phase.

---
*Phase: 05-child-wallet-lifecycle-states*
*Completed: 2026-07-23*
