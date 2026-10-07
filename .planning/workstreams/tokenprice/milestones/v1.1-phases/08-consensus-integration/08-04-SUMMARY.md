---
phase: 08-consensus-integration
plan: "04"
subsystem: consensus
tags: [consensus, price-validation, escrow, refund, gtest, multi-node, loopback]

requires:
  - phase: 08-consensus-integration (08-01)
    provides: escrow price gate seam + Pending-on-NoCoverage mapping + claim-time backstop (all live, honest flow green)
  - phase: 08-consensus-integration (08-02)
    provides: TaskRejectionSubject published end-to-end (sgns.task_rejection.v1, CheckSubject branch, dispatch routing)
  - phase: 08-consensus-integration (08-03)
    provides: rejection-subject handlers with independent re-verification, dual-regime refund, first-rejector trigger + SetPriceRejectNotifier wiring
provides:
  - "ProcessingNodesTest.GamedPriceJobRejectedAndRefunded — the phase-8 acceptance proof: gamed job BelowBand-rejected by both validators, never processed, fully refunded (regime 1 asserted in-test)"
  - "Deterministic single-process gamed-claim construction recipe: L1-freshness-aware era sequencing (61s aging) + shrunk validation window via ScopedEnvVar SGNS_PRICEVAL_* + stub flip, all through the real ProcessImage wire path"
  - "Log-cited end-to-end evidence chain: gate Reject -> notifier -> rejection subject proposed into escrow-keyed slot -> independent re-verification on both processors -> certificate -> poster escrow FAILED -> RollbackUTXOs refund"
affects: [tokenprice milestone acceptance (TEST-02), future price-enforcement regressions, ROADMAP phase-8 close-out]

actuals:
  tokens: 3613   # chars/4 over the realized submodule diff (14,451 chars, 326 insertions)
  tasks: 2
  commits: 1     # MEASURED: git rev-list --count 11e8b76c7..HEAD in the SuperGenius submodule (+ parent pointer bump + docs commit outside)
plan_head_before: 11e8b76c7735d2afbdc660e5d4383f93eba7026b
plan_head_after: 5dbcf2a5c0887488dc09db9c02a979dd6c9de018

tech-stack:
  added: []
  patterns:
    - "L1-freshness-aware era sequencing for single-process price gaming: kFreshMaxAge (60s, fresh-closed) is a first-class test parameter — age caches past fresh so forced fetches are guaranteed network fetches, then re-warm only the node whose era you need to pin"
    - "Time-invariant gamed verdict: age the old era BEFORE acquiring the new-era evidence so the shrunk window's verdict (BelowBand) cannot depend on when the vote lands"
    - "ScopedStubPrice RAII guard restoring the fixture-default stub payload on every exit path — early ASSERT_* exits can never leak a flipped price into a later suite case"

key-files:
  created: []
  modified:
    - SuperGenius/test/src/processing_nodes/processing_nodes_test.cpp

key-decisions:
  - "Era sequencing corrected from the plan-literal order (deviation 1): GetQuotes serves fresh L1 entries (kFreshMaxAge=60s) with zero network, so the plan's warm->flip->force-fetch would have been 1.0 cache hits — 61s aging before the flip makes the validators' forced fetches real network fetches of 50.0"
  - "Aging moved BEFORE the 50.0-era fetches (not after the env shrink as the plan sketched): the plan's post-shrink 6s sleep would have evicted the 50.0-era observations too (NoCoverage -> Pending per 08-01, refund never fires); aging-first makes the verdict time-invariant BelowBand"
  - "Poster's claim era re-pinned with a brief stub flip-back to 1.0 + poster refetch immediately before ProcessImage (the plan's own 'shorten the gap' latitude) — after 61s the poster's 1.0 L1 entry is stale and ProcessImage would otherwise have priced honestly at 50.0"
  - "Regime asserted via WaitForTransactionOutgoing == FAILED (returns the tracked outgoing status); WaitForEscrowRelease can only return CONFIRMED/INVALID because regime 1 is a rollback, not a spend — the plan's alternative clause (CountTransactions(FAILED) increased) in direct wait form"
  - "Mint moved before era sequencing with an explicit exact-credit wait so mint finalization latency cannot eat the poster's 60s quote-freshness window"

patterns-established:
  - "Gamed-price test construction against LocalPriceManager: sequence eras around the L1 freshness boundary; never assume a forced GetGNUSPrice fetches from the network while its cache is fresh"

requirements-completed: [CONS-01, CONS-02, CONS-03, TEST-02]

coverage:
  - id: D1
    description: "Gamed-price job rejected + never processed + fully refunded, posted through the real ProcessImage wire path (TEST-02 / CONS-01 / CONS-03 low-side)"
    requirement: TEST-02
    verification:
      - kind: integration
        ref: "processing_nodes_test.exe --gtest_filter=ProcessingNodesTest.GamedPriceJobRejectedAndRefunded — PASSED (75.3s; first run), assertions: exact uint64 balance refund 50000000000==50000000000, escrow terminal FAILED (regime 1), both processor balances unchanged, no task result"
        status: pass
      - kind: other
        ref: "Log evidence (.gsd/08-04-t1-test.log): both role=full validators logged 'Escrow price gate rejected ... reason=6' (BelowBand); CheckTaskPriceBackstop rejected the same task reason=6 (fail-closed); both processors 'rejection independently verified ... reason=6'; both proposals collapsed into slot sgns.task_rejection.v1:6fd03bd8...; poster node 'HandleTaskRejectionCertificate: rejection certificate driving tracked escrow 6fd03bd8... (status=3) to FAILED (regime 1)'"
        status: pass
    human_judgment: false
  - id: D2
    description: "Honest job accepted end-to-end with gate + backstop + rejection-subject machinery all live (ROADMAP criterion 2)"
    requirement: CONS-01
    verification:
      - kind: integration
        ref: "Full processing_nodes_test binary (2 cases, one suite per D-08-11): PostProcessing PASSED 27.9s BEFORE GamedPriceJobRejectedAndRefunded PASSED 75.1s in the same run — no case-order dependency, stub/env restored between cases"
        status: pass
    human_judgment: false
  - id: D3
    description: "Phase 7 pure validator contract unperturbed by the consensus hook (edge-inheritance backstop truth of 08-01); CONS-03 high-side coverage lives here"
    requirement: CONS-03
    verification:
      - kind: unit
        ref: "ctest -R 'price_|processing_nodes' -C Release — 7/7 Passed (price_validator_test included, 0.07s; no validator file touched this plan)"
        status: pass
    human_judgment: false

# Metrics
duration: 63min
completed: 2026-10-06
status: complete
---

# Phase 8 Plan 04: TEST-02 Multi-Node Behavioral Proof Summary

**Proved Phase 8 end-to-end in the 3-node loopback topology: a gamed-price job posted through the real ProcessImage wire path is BelowBand-rejected by both honest validators (reason=6), never processed, and refunded to the poster to exact uint64 equality via the regime-1 FAILED rollback — while the honest PostProcessing case stays green in the same suite with all enforcement live.**

## Performance

- **Duration:** ~63 min (22:12 → 23:15 local; includes two full multi-node suite runs)
- **Started:** 2026-10-06T22:12-04:00
- **Completed:** 2026-10-06T23:15-04:00
- **Tasks:** 2 (both auto; no checkpoints)
- **Files modified:** 1 (SuperGenius/test/src/processing_nodes/processing_nodes_test.cpp, +326 lines)

## Accomplishments

- **`ProcessingNodesTest.GamedPriceJobRejectedAndRefunded`** — a self-contained TEST_F on the existing fixture (D-08-11) that deterministically constructs a gamed claim in one process: warm all caches at 1.0, age L1 past fresh (61s), flip the stub to 50.0 and force fresh evidence on both validators only, re-pin the poster's claim era with a brief flip-back refetch, then post via the real `ProcessImage` wire path (D-08-12) while the stub serves 50.0
- **All TEST-02 truths asserted in one case**: no processing (both processor balances exactly unchanged + no task result), exact uint64 full refund (50000000000 → 50000000000, no burn — D-08-07/D-08-13), and the escrow terminal state FAILED **asserted in-test via `WaitForTransactionOutgoing == FAILED`** (regime asserted, never assumed — 08-RESEARCH Open Q1)
- **Full end-to-end machinery exercised and log-verified**: consensus-gate Reject on both validators → first-rejector notifier fires → both processors propose into the SAME escrow-keyed slot (`sgns.task_rejection.v1:6fd0…` — the 08-03 slot collapse working) → independent D-08-06 re-verification on both → certificate → poster's `HandleTaskRejectionCertificate` drives the tracked escrow to FAILED (regime 1) → RollbackUTXOs refund; the claim-time backstop ALSO rejected the task reason=6 (fail-closed) — D-08-04 proven live in the same run
- **Full-suite green in one suite**: honest `PostProcessing` (27.9s) + gamed case (75.1s) passed back-to-back — no case-order dependency (RAII stub/env guards restore fixture defaults per case); ctest `price_|processing_nodes` family 7/7

## Fired Regime (recorded per plan instruction)

**Regime 1 — reservation rollback via the rejection certificate (the D-08-13/A3-expected outcome).** Evidence, poster node (`role=light`): `HandleTaskRejectionCertificate: rejection certificate driving tracked escrow 6fd03bd8796cb362359e8c45b9231e94068a91ff45e8a5a20fe271596a2972ea (status=3) to FAILED (regime 1)`; the in-test assertion `WaitForTransactionOutgoing == FAILED` held. The processors' certificate handlers logged `already FAILED — rejection refund already applied` (idempotent). No release spend occurred (regime 2 correctly dormant in the all-honest topology).

## Gate-Reject Evidence (which nodes rejected, and why)

- **Both voting validators (Full/processor nodes)** logged `ValidateTransactionForConsensus: Escrow price gate rejected tx=6fd03bd8… task=5246d028… reason=6` — **reason 6 = BelowBand** (claim 1.0-era vs in-window 50.0-era evidence; band [45,55], tolerance 10%, flip magnitude 50x ≫ tolerance — no boundary sensitivity).
- **Claim-time backstop** on the same task: `CheckTaskPriceBackstop: price backstop rejected task 5246d028… escrow_path=0x41e4… reason=6 (fail-closed)` — the belt-and-suspenders layer fired too.
- **Poster's light node**: did NOT gate-reject its own escrow (assumption A1's substance verified — its own window contains its fresh 1.0 quote, so its gate approves). It DID evaluate the rejection subject and dissented (`recomputed gate verdict is not Reject (check=0) … honest job falsely accused, rejecting subject`) — per-node evidence divergence that D-08-08 explicitly tolerates; the certificate formed on the two full-node validator votes.
- **Independent re-verification (D-08-06)** on both processors: `HandleTaskRejectionSubject: rejection independently verified escrow=6fd03bd8… task=5246d028… reason=6`; both first-rejector proposals collapsed into the one escrow-keyed slot (`SubmitTaskRejectionSubject: … slot=sgns.task_rejection.v1:6fd03bd8…` on both nodes).

## CONS-03 Coverage Rationale (union, disclosed — flagged assumption)

CONS-03 requires rejection of a poster who games the price **"high or low."** Coverage is delivered as a **disclosed union**: the multi-node loopback case proves the **low side live** (BelowBand, reason=6, through the full consensus/certificate/refund chain), while the **high side (AboveBand)** is proven hermetically at the unit level in Phase 7's `price_validator_test` exact-boundary suite (green in this plan's ctest run, validator untouched). The band check itself is symmetric (`claimedPrice > max*(1+tol)` / `claimedPrice < min*(1−tol)` — one code path, mirrored comparisons), so a multi-node high-side case would duplicate the same live path with the sign flipped; it is deliberately not duplicated to keep multi-node suite runtime and flake surface bounded (suite already ~108s; each case boots 3 nodes).

## Task Commits

1. **Task 1: GamedPriceJobRejectedAndRefunded — sequenced stub-flip gamed post, no-processing + exact-refund + regime assertions** - `5dbcf2a5c` (test) — SuperGenius submodule, branch `dev_price_validation`
2. **Task 2: Full-suite proof (honest + gamed + price family)** - no code delta (hygiene pass confirmed self-containment; all verify commands green); captured by the parent pointer bump

**Parent-repo commits:**
- `5343626` (chore): bump SuperGenius submodule pointer (11e8b76c7 → 5dbcf2a5c)
- SUMMARY commit follows this file (docs(08-04))

## Files Created/Modified

- `SuperGenius/test/src/processing_nodes/processing_nodes_test.cpp` — new `GamedPriceJobRejectedAndRefunded` TEST_F (+326 lines) and the file-local `ScopedStubPrice` RAII guard (D-08-11 discretion: helpers kept local)

## Decisions Made

See key-decisions frontmatter. In brief: the gamed construction was re-derived around the L1 freshness boundary the flagged TEST-02 assumption pointed at; the plan's own latitude clauses ("verify the cache-hit serving path… if needed, shorten the gap between the poster's forced fetch and the post", "or assert CountTransactions(FAILED) increased") were exercised exactly as intended.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Plan-literal gamed sequence could not deterministically construct the gamed claim**
- **Found during:** Task 1 (mandatory `read_first` verification of the flagged TEST-02 cache-hit assumption against `LocalPriceManager::HandleRequestOnStrand`)
- **Issue:** Three interacting flaws: (a) `GetQuotes` serves FRESH L1 cache (kFreshMaxAge=60s, fresh-closed boundary) with zero network — the plan's "flip stub, then force 50.0 fetch on validators" would have been 1.0 cache hits, recording no 50.0-era observations (verdict: in-band accept; test fails loudly); (b) the plan's step (6) post-shrink 6s sleep would evict the just-fetched 50.0-era observations too (window empty → NoCoverage → Pending per the 08-01 mapping; refund never fires); (c) after any >60s sequencing the poster's own 1.0 L1 entry goes stale, so `ProcessImage` would have refetched 50.0 and priced the job honestly.
- **Fix:** Era sequencing re-derived: mint+credit-wait first; warm all caches at 1.0; sleep 61s (guaranteed stale for every entry); flip to 50.0 and force validator fetches (guaranteed network); flip back to 1.0 briefly and refetch the poster's quote (fresh L1 pin); post via `ProcessImage` with the stub back at 50.0. Shrunk window [T−5s, T+2s] then contains only 50.0-era observations with the verdict BelowBand regardless of exact vote timing. Regime asserted via `WaitForTransactionOutgoing` (WaitForEscrowRelease structurally cannot report FAILED — it waits for a spend; regime 1 is a rollback). `ScopedStubPrice` RAII keeps every exit path restoring the fixture-default price.
- **Files modified:** SuperGenius/test/src/processing_nodes/processing_nodes_test.cpp
- **Verification:** GamedPriceJobRejectedAndRefunded PASSED first run (75.3s) with the full log chain (gate reason=6 both validators → subject verified → certificate → FAILED regime 1 → exact refund); full binary + ctest family green afterward
- **Committed in:** `5dbcf2a5c`

---

**Total deviations:** 1 auto-fixed (Rule 1 — deterministic-construction bug in the plan's literal step ordering)
**Impact on plan:** Every must-have truth, acceptance criterion, and locked decision (D-08-07/08/11/12/13) is preserved and now actually provable; the deviation was the plan's own flagged assumption being resolved empirically, exactly as its statement directed. No scope change.

## Issues Encountered

None beyond the deviation above — build green first try; both multi-node runs green; no auth gates.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 8 is functionally complete: all four requirements (CONS-01, CONS-02, CONS-03, TEST-02) delivered and machine-verified; ROADMAP criteria 1-3 all evidenced (gamed rejected+refunded; honest accepted with enforcement live; full multi-node suite green).
- The `.gsd/08-04-*.log` captures retain the raw evidence chain if the verifier wants to audit the gate/certificate/refund interleaving.

## Self-Check: PASSED

- `08-04-SUMMARY.md` exists at `.planning/workstreams/tokenprice/phases/08-consensus-integration/` — FOUND
- `TEST_F( ProcessingNodesTest, GamedPriceJobRejectedAndRefunded )` present in `SuperGenius/test/src/processing_nodes/processing_nodes_test.cpp` — FOUND
- Submodule commit `5dbcf2a5c` (test), parent commits `5343626` (chore pointer bump), `9acdb96` (docs) — FOUND
- Shared orchestrator artifacts (`tokenprice/STATE.md`, `tokenprice/ROADMAP.md`, `.planning/STATE.md`) — untouched (clean `git status`)

---
*Phase: 08-consensus-integration*
*Completed: 2026-10-06*
