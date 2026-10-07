---
phase: 08-consensus-integration
plan: "03"
subsystem: consensus
tags: [consensus, escrow-release, task-rejection, refund, utxo, cpp17]

requires:
  - phase: 08-consensus-integration (08-01)
    provides: escrow price gate seam (EvaluateEscrowPriceGate / PriceRejectNotifierFn / SetPriceRejectNotifier) + honest-flow green with gate live
  - phase: 08-consensus-integration (08-02)
    provides: TaskRejectionSubject published (sgns.task_rejection.v1), Create/Decode helpers, CheckSubject forged-subject branch, dispatch routing
provides:
  - Registered subject + certificate handlers for TASK_REJECTION_SUBJECT_TYPE (weak_ptr/owner_dead shape, symmetric teardown unregisters)
  - D-08-06 independent verification at vote time (subject handler re-runs the gate; Approve only on recomputed-reason == reject_reason)
  - Regime-1 refund: certified rejection drives a tracked non-CONFIRMED escrow to FAILED -> existing RollbackUTXOs restores the poster's balance
  - Regime-2 refund: BuildRejectionReleaseTransaction (CONFIRMED-gated, single full-amount output to the poster, no burn)
  - First-rejector trigger: TransactionManager::SubmitTaskRejectionSubject + Blockchain::CreateTaskRejectionProposal + GeniusNode SetPriceRejectNotifier wiring (08-01 seam live)
  - Rejection-slot identity keyed on the rejected escrow (duplicate rejector proposals collapse in one consensus slot)
affects: [08-consensus-integration (08-04 multi-node behavioral test), consensus certificate application path, escrow refund observers]

actuals:
  tokens: 8844   # chars/4 over the realized submodule diff (35,374 chars, 544 insertions)
  tasks: 3
  commits: 3     # MEASURED: git rev-list --count 28e15b157..HEAD in the SuperGenius submodule
plan_head_before: 28e15b157b183c6b26cccab40e1ee6cae111472d
plan_head_after: 11e8b76c7

tech-stack:
  added: []   # no new libraries — in-repo C++17 + existing consensus machinery only
  patterns:
    - "Rejection-subject handler trio in TransactionManager::New: certificate handler (refund regimes) + subject handler (independent gate re-run) + slot-key handler (escrow-keyed identity), all in the NONCE weak_ptr/owner_dead shape"
    - "No-burn refund construction: PayEscrow's InputUTXOInfo/FillDAGStruct/EnqueueTransaction shape with a directly-built single full-amount output — the burn-splitting payout helper is never called (D-08-07)"
    - "Shared slot-key formula (TaskRejectionSlotKey) used by both the registered handler and the submitter's certificate dedupe so dedupe identity can never drift"

key-files:
  created: []
  modified:
    - SuperGenius/src/transaction/TransactionManager.hpp
    - SuperGenius/src/transaction/TransactionManager.cpp
    - SuperGenius/src/blockchain/Blockchain.hpp
    - SuperGenius/src/blockchain/impl/Blockchain.cpp
    - SuperGenius/src/account/GeniusNode.cpp

key-decisions:
  - "Duplicate-proposal collapse implemented via a namespaced rejection slot key (type + ':' + original_escrow_hash) instead of relying on ComputeSubjectId: identical-content subjects from DIFFERENT rejectors carry different account_ids, so the default subject-id slot key would not collapse them — the escrow-keyed slot makes every rejector's proposal for one escrow compete in a single slot (must-have truth 5; flagged assumption (a) resolved)"
  - "Subject handler Rejects on unresolvable refs (plan-literal) — CheckSubject already drops structurally-forged subjects before proposal handling, so this branch covers refs that parse but do not resolve locally; D-08-08 tolerates the verdict divergence"
  - "Certificate handler returns Approve on ignore paths (unknown escrow, untracked, undecodable) so certificate work is settled once; only the FAILED-transition failure keeps work retryable"
  - "Regime-2 release construction failure settles the certificate (logs only): the release either landed or the CONFIRMED gate correctly declined; a re-fired release would fail as a UTXO double-spend anyway (D-08-05)"
  - "Blockchain::CreateTaskRejectionProposal added because the existing CreateConsensusProposal wrapper is nonce-specific (BuildConsensusProposal carries nonce/tx_hash/EmbeddedTransaction parameters)"

patterns-established:
  - "Escrow-keyed slot identity for non-transaction subjects: future refund/attestation subjects that need one-certificates-per-referenced-object should copy the namespaced-slot-key handler shape"
  - "Refs-consistency check at both subject and certificate trust boundaries: path-resolved hash must equal the subject's claimed hash (T-08-07 strengthening)"

requirements-completed: [CONS-02, CONS-03]

coverage:
  - id: D1
    description: "TaskRejectionSubject handlers registered with independent D-08-06 verification: subject handler re-runs the price gate and approves only on recomputed-reason == reject_reason; certificate handler dispatches refund regimes; symmetric teardown unregisters"
    requirement: CONS-03
    verification:
      - kind: integration
        ref: "cmake --build SuperGenius\\build\\Windows\\Release --config Release --target processing_nodes_test — BUILD SUCCEEDED (after Tasks 1 and 3)"
        status: pass
      - kind: other
        ref: "git -C SuperGenius grep -c TASK_REJECTION_SUBJECT_TYPE -- src/transaction/TransactionManager.cpp = 7 (>= 4: subject + certificate + slot-key registrations, 2 teardown unregisters); ProcessingNodesTest.PostProcessing green 9/9 cumulative across the plan (validation approve=3 reject=0 per node on the honest path)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Regime-2 rejection release: BuildRejectionReleaseTransaction emits exactly ONE full-amount output to the escrow's source address, gated on tracked status == CONFIRMED, sole call site the certificate handler's CONFIRMED branch, no burn (D-08-07)"
    requirement: CONS-02
    verification:
      - kind: other
        ref: "git -C SuperGenius grep -c BuildPayoutOutputs -- src/transaction/TransactionManager.cpp = 2 exactly (definition + PayEscrow call; no third site introduced); refund_outputs.push_back site is the single-output construction; build green"
        status: pass
    human_judgment: false
  - id: D3
    description: "First-rejector trigger end-to-end: gate Reject verdict -> notifier -> SubmitTaskRejectionSubject (CreateTaskRejectionSubject + CreateTaskRejectionProposal + SubmitProposal, certificate-dedupe early return) with GeniusNode wiring beside the 08-01 gate wiring"
    requirement: CONS-02
    verification:
      - kind: integration
        ref: "processing_nodes_test.exe --gtest_filter=ProcessingNodesTest.PostProcessing PASSED with the notifier live (no rejection fired on the honest path — correct); task_queue_test full suite 20/20"
        status: pass
      - kind: other
        ref: "git -C SuperGenius grep -c SubmitTaskRejectionSubject — TransactionManager.cpp 1, GeniusNode.cpp 1 (implementation + wiring); build green"
        status: pass
    human_judgment: false

# Metrics
duration: 20min
completed: 2026-10-07
status: complete
---

# Phase 8 Plan 03: Rejection-Subject Handlers + Dual-Regime Refund + First-Rejector Trigger Summary

**Made the rejection subject live end-to-end: vote-time independent re-verification (Approve only when the recomputed gate reason matches), certified rejections restore the poster's funds through FAILED-rollback (regime 1) or a CONFIRMED-gated full-refund no-burn release spend (regime 2), and the first honest rejector proposes the subject the instant the gate Rejects.**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-10-07T01:55:06Z
- **Completed:** 2026-10-07T02:15:00Z
- **Tasks:** 3 (all auto; no checkpoints)
- **Files modified:** 5 (all in the SuperGenius submodule)

## Accomplishments

- **Handlers registered in the NONCE shape** (`TransactionManager::New`, weak_ptr capture + `std::errc::owner_dead` fallback): certificate handler for refund regimes, subject handler for independent verification, slot-key handler for escrow-keyed identity; both per-instance handlers unregistered in teardown beside the NONCE unregisters (slot-key handler deliberately retained — process-global static registry, nonce precedent)
- **D-08-06 independent verification (CONS-03):** the subject handler resolves `escrow_path` from local GlobalDB, requires `dynamic_pointer_cast<EscrowTransaction>` success AND `escrow_tx->GetHash() == original_escrow_hash` (refs-consistency, T-08-07), re-runs `EvaluateEscrowPriceGate`, and approves ONLY when the recomputed verdict is Reject with reason == `reject_reason` — forged/stale rejections and honest-job accusations all Reject
- **Regime 1 (all-honest topology):** the certificate handler drives a tracked non-CONFIRMED escrow through `ChangeTransactionState( escrow_tx, FAILED )` — the existing FAILED machinery performs `RollbackUTXOs`, returning the poster's `GetBalance` (UTXO_READY-only) to its pre-post level; FAILED/INVALID are idempotent no-ops; the UNCONFIRMED branch was left untouched
- **Regime 2 (divergence topology):** `BuildRejectionReleaseTransaction` follows the PayEscrow construction verbatim (record fetch, escrow `InputUTXOInfo` signed by the local account, `FillDAGStruct` lock id with empty-fallback, `MakeSignature`, `EnqueueTransaction`) but emits exactly ONE output — full `GetAmount()` to `GetSrcAddress()` (the poster), zero burn; construction unreachable for non-CONFIRMED escrows (tracked-status gate, 08-RESEARCH Pitfall 1)
- **First-rejector trigger (D-08-05):** `SubmitTaskRejectionSubject` builds the subject (`CreateTaskRejectionSubject`: proposer address, escrow `GetUncleHash()`, `outcome.task_id`, typed reason, `escrow_tx.GetHash()`) and submits via the new `Blockchain::CreateTaskRejectionProposal` (CreateConsensusProposal style) + `SubmitProposal`; certificate-dedupe early return on the canonical slot key; zero-reason invocations never reach consensus; all failures logged and swallowed — the already-returned gate verdict is never affected
- **GeniusNode wiring:** `SetPriceRejectNotifier` installed directly after the 08-01 `SetEscrowPriceGate` wiring (before Start) with a weak-manager capture — the 08-01 null-safe notifier slot is now live

## Task Commits

All in the `SuperGenius` submodule on `dev_price_validation` (base `28e15b157`):

1. **Task 1: Register TaskRejectionSubject handlers — subject re-runs the gate, certificate dispatches regimes** - `54b12cbc0` (feat)
2. **Task 2: Regime-2 rejection release — full-amount single-output CONFIRMED-gated spend** - `17ef604eb` (feat)
3. **Task 3: First-rejector proposal trigger — gate Reject verdict submits the rejection subject** - `11e8b76c7` (feat)

**Parent-repo commits:**
- `acd4ce6` (chore): bump SuperGenius submodule pointer

**Plan metadata:** SUMMARY commit follows this file (docs(08-03))

## Files Created/Modified

- `SuperGenius/src/transaction/TransactionManager.hpp` — handler/helper declarations (`HandleTaskRejectionSubject`, `HandleTaskRejectionCertificate`, `BuildRejectionReleaseTransaction`, `SubmitTaskRejectionSubject`, `TaskRejectionSlotKey`), `EscrowTransaction` forward declaration
- `SuperGenius/src/transaction/TransactionManager.cpp` — registrations + teardown unregisters, both handler implementations with regime dispatch, regime-2 release construction, first-rejector submission with dedupe
- `SuperGenius/src/blockchain/Blockchain.hpp` — `CreateTaskRejectionProposal` declaration
- `SuperGenius/src/blockchain/impl/Blockchain.cpp` — `CreateTaskRejectionProposal` in the CreateConsensusProposal shape (registry cid/epoch)
- `SuperGenius/src/account/GeniusNode.cpp` — `SetPriceRejectNotifier` wiring beside the 08-01 gate wiring

## Decisions Made

- **Escrow-keyed rejection slot key (namespaced `type:original_escrow_hash`)** instead of relying on default `ComputeSubjectId` slot identity: rejection subjects embed the proposer's `account_id`, so two honest rejectors produce different subject bytes and different default slot keys — their proposals would NOT have collapsed. Keying the slot on the escrow makes every rejector's proposal for one escrow compete in a single slot, and the settled certificate locks it (must-have truth 5; flagged assumption (a) verified and resolved during implementation, as the plan directed)
- **`CheckCertificateForSlot` as the submit-side dedupe seam** (the plan-named lookup): a durable certificate for the rejection slot short-circuits re-proposal; in-flight duplicates are collapsed by the slot's existing candidate machinery; no local dedupe set, no second mechanism (D-08-09)
- **Certificate handler settles (Approve) on every ignore path** — locally-unknown escrow, untracked escrow, undecodable certified subject, refs mismatch — so certificate work is marked done rather than retried forever; only a FAILED-transition error keeps the refund retryable
- **Slot-key handler retained at teardown** (not unregistered), matching the documented nonce precedent: the registry is process-global and static

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `EscrowTransaction` type not visible in `TransactionManager.hpp`**
- **Found during:** Task 2 (first build attempt)
- **Issue:** The new private declaration `BuildRejectionReleaseTransaction( const EscrowTransaction & )` failed to compile (`error C2143` in dependents) — the header never names the type and does not include `account/EscrowTransaction.hpp`
- **Fix:** Forward-declared `class EscrowTransaction;` beside the existing `MintTransactionV2` forward declaration (sufficient for a const-ref parameter; no new include)
- **Files modified:** SuperGenius/src/transaction/TransactionManager.hpp
- **Verification:** Full `processing_nodes_test` build green
- **Committed in:** `17ef604eb`

**2. [Rule 3 - Blocking] Plan's "exactly 2" grep gate vs. documenting comment**
- **Found during:** Task 2 verify
- **Issue:** The D-08-07 rationale comment inside the release helper named the burn-splitting payout helper verbatim, which would have made the `grep -c BuildPayoutOutputs` count 3 — tripping the plan's `fails_when: count is not exactly 2` gate even though no new call site existed
- **Fix:** Reworded the comment ("the payout helper always emits a burn output") so the grep measures exactly the definition + PayEscrow call; the header's Doxygen rationale (outside the grepped file) still names it explicitly
- **Files modified:** SuperGenius/src/transaction/TransactionManager.cpp
- **Verification:** `grep -c` = 2 exactly; rebuild green
- **Committed in:** `17ef604eb`

---

**Total deviations:** 2 auto-fixed (1 bug, 1 blocking)
**Impact on plan:** Both fixes were required to satisfy the plan's own verification gates; no scope change. No architectural deviations (Rule 4 never triggered).

**Plan-tag notes (not code deviations):**
- Task 1 carries `tdd="true"`, but the plan's `<verify>` contract for it is build + registration-count gates only, and the plan's `<verification>` section explicitly assigns the multi-node behavioral proof to 08-04 ("this plan's build+source gates are the pre-verification"). All listed verify commands ran and passed; additionally the honest-flow regression `ProcessingNodesTest.PostProcessing` and the full `task_queue_test` suite (20/20) were run after each task as extra regression coverage since `TransactionManager::New` (used by every node type) was touched.
- Task 1's commit necessarily contained the regime-2 branch as routing-only (log + Approve) because the release helper is Task 2's deliverable; Task 2's commit immediately wired `BuildRejectionReleaseTransaction` into that branch. The final tree contains no stubs.

## Issues Encountered

None beyond the deviations above — every build succeeded after the forward-declaration fix, and both regression suites stayed green throughout (honest flow never fires the notifier: `validation(approve=3 reject=0)` on all three nodes, no rejection-subject logs).

## Authentication Gates

None — no external services or credentials involved.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **08-04 (multi-node behavioral test)** can exercise the full loop now: gamed job -> gate Reject -> notifier -> rejection subject proposed -> independent re-verification by peers -> certificate -> poster escrow FAILED -> balance restored (regime 1). The in-test "which regime fired" assertion should watch for the new `rejection subject proposed` / `rejection independently verified` / `driving tracked escrow ... to FAILED` log lines
- Divergence (regime 2) coverage remains source-gated per the planning resolution (Q1: multi-node exercise NOT required); the release builder is CONFIRMED-gated and no-burn
- The `TaskRejectionSlotKey` shape is the template for any future per-object attestation subjects

## Self-Check: PASSED

All 5 modified files exist on disk; all three task commits (`54b12cbc0`, `17ef604eb`, `11e8b76c7`) verified in the submodule log; measured commit count `git rev-list --count 28e15b157..HEAD` = 3 matches `actuals.commits`; parent pointer bump `acd4ce6` verified. Builds green after every task; `ProcessingNodesTest.PostProcessing` and `task_queue_test` (20/20) green; registration symmetry (2 unregister sites beside NONCE), payout-helper count exactly 2, single full-refund output construction, and SubmitTaskRejectionSubject presence in both files all re-verified at plan level.

---
*Phase: 08-consensus-integration*
*Plan: 03*
*Completed: 2026-10-07*
