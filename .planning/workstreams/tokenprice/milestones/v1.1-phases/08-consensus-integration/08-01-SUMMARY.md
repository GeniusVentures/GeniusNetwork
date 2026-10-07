---
phase: 08-consensus-integration
plan: "01"
subsystem: consensus
tags: [consensus, escrow, price-validation, task-queue, gtest, cpp17]

requires:
  - phase: 07-price-validator
    provides: ValidatePrice / ResolvePriceValidatorConfig / PriceObservationWindow / ShouldTriggerRefetch (pure decision core)
  - phase: 06-price-claim-wire-format-history
    provides: Task.claimed_price double on the wire + escrow DAG timestamp reference
provides:
  - TransactionManager escrow price gate seam (EscrowPriceGateOutcome / EscrowPriceGateFn / PriceRejectNotifierFn / SetEscrowPriceGate / EvaluateEscrowPriceGate / SetPriceRejectNotifier)
  - Escrow-hold gate branch in TransactionConsensusHandler::ValidateTransactionForConsensus (D-08-01) with Pending-on-missing-task (D-08-02)
  - GeniusNode::ValidateTaskPriceClaim / FindTaskByEscrow — node-local price evidence assembly for both enforcement points
  - TaskQueueImpl claim-time price backstop (TaskPriceBackstopFn / SetPriceBackstop / price_backstop_) routing rejects to MarkTaskBad (D-08-04/D-08-10)
  - GeniusNode::CheckTaskPriceBackstop — escrow-fetch seam with fail-closed policy (08-RESEARCH Open Q5)
  - TaskQueue.PriceBackstop* unit cases (suite named TaskQueue for the gtest filter)
affects: [08-consensus-integration (08-02, 08-03, 08-04), consensus validation chain, processing claim path]

actuals:
  tokens: 9819   # chars/4 over the realized submodule diff (39,275 chars, 630 insertions)
  tasks: 2
  commits: 2     # MEASURED: git rev-list --count 600de1e664..HEAD in the SuperGenius submodule
plan_head_before: 600de1e6641f761c4d460ee9d5ae3840d8b560c5
plan_head_after: 914731e0a

tech-stack:
  added: []   # no new libraries — in-repo C++17 only
  patterns:
    - "Injected-seam enforcement: transaction/processing layers stay coinprices-free; GeniusNode supplies evidence behind std::function seams (gate + notifier + backstop)"
    - "Pending-on-evidence-absence at the consensus gate (NoCoverage maps to Pending; deterministic reasons Reject) — the migration-allowlist precedent extended to price evidence"
    - "Bounded synchronous self-heal at the claim-time backstop (fetch-and-revalidate once before failing closed)"

key-files:
  created: []
  modified:
    - SuperGenius/src/transaction/TransactionManager.hpp
    - SuperGenius/src/transaction/TransactionManager.cpp
    - SuperGenius/src/transaction/TransactionConsensusHandler.cpp
    - SuperGenius/src/account/GeniusNode.hpp
    - SuperGenius/src/account/GeniusNode.cpp
    - SuperGenius/src/processing/impl/TaskQueueImpl.hpp
    - SuperGenius/src/processing/impl/TaskQueueImpl.cpp
    - SuperGenius/test/src/processing/task_queue_test.cpp

key-decisions:
  - "Gate maps NoCoverage to Pending instead of Reject: evidence absence is retryable (D-07-06 self-heal + 3-min pending TTL with 1-s retries); the plan-literal mapping poison-marked honest escrows on coverage-less validators (empirically reproduced, log-cited deviation)"
  - "Backstop treats NoCoverage with one bounded synchronous fetch + re-validation before failing closed, so an honest task on a coverage-less node stays claimable instead of being permanently MarkTaskBad'd; every deterministic reject still fails closed (Open Q5 preserved)"
  - "DAG timestamps are milliseconds since epoch (FillDAGStruct/GetCurrentTimestamp verified) — dagTimestamp built with std::chrono::milliseconds, not the research sketch's seconds"
  - "GetOrCreatePriceManager lazy construction mutex-guarded now that the consensus thread can reach it"
  - "Test suite named TaskQueue (subclassing TaskQueueImplTest) so --gtest_filter=TaskQueue.PriceBackstop* selects exactly the new cases"

patterns-established:
  - "Price-enforcement seams: layer-neutral int-typed reason crossing layer boundaries (no coinprices include in transaction/processing headers)"
  - "Unit-proof of MarkTaskBad vs claim-lock: remove the lock key via the db seam, then prove the durable incompatible_jobs_ skip"

requirements-completed: [CONS-01, CONS-03]

coverage:
  - id: D1
    description: "Consensus escrow price gate: TransactionManager seam + escrow-hold branch (Pending on missing task, Reject on typed reason) + GeniusNode evidence wiring, live on the honest 3-node flow"
    requirement: CONS-01
    verification:
      - kind: integration
        ref: "SuperGenius/build/Windows/Release/test_bin/Release/processing_nodes_test.exe --gtest_filter=ProcessingNodesTest.PostProcessing (9/9 green across Task 1 and Task 2 verification batches with the gate live)"
        status: pass
      - kind: other
        ref: "git -C SuperGenius grep -c EvaluateEscrowPriceGate -- src/transaction/{TransactionManager.hpp,TransactionManager.cpp,TransactionConsensusHandler.cpp} — 1 match per file"
        status: pass
    human_judgment: false
  - id: D2
    description: "Claim-time price backstop in TaskQueueImpl::GrabTask routing Reject verdicts to the MarkTaskBad skip, with unit proof that a rejected task is never returned and the null default leaves the queue unchanged"
    requirement: CONS-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/processing/task_queue_test.cpp#TaskQueue.PriceBackstopRejectMarksTaskBad + #TaskQueue.PriceBackstopUnsetKeepsBehavior (2/2 pass; full suite 20/20)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Phase 7 validator consumed unmodified — exact-boundary suite stays green after both enforcement points are wired"
    verification:
      - kind: unit
        ref: "SuperGenius/build/Windows/Release/test_bin/Release/price_validator_test.exe (22/22 pass, no validator file touched)"
        status: pass
    human_judgment: false

duration: 108min
completed: 2026-10-07
status: complete
---

# Phase 8 Plan 01: Consensus Integration — Escrow Price Gate + Claim-Time Backstop Summary

**Escrow price gate wired into ValidateTransactionForConsensus (Pending on missing task / typed Reject) plus a GrabTask claim-time backstop, with all price evidence assembled node-locally in GeniusNode behind injected seams — honest 3-node flow green 9/9 runs with enforcement live.**

## Performance

- **Duration:** 108 min
- **Started:** 2026-10-06T23:51:22Z
- **Completed:** 2026-10-07T01:39:37Z
- **Tasks:** 2 (tracer + auto)
- **Files modified:** 8 (all in the SuperGenius submodule)

## Accomplishments

- Escrow price gate seam on TransactionManager (`EscrowPriceGateOutcome{Approve,Reject,Pending}`, `EscrowPriceGateFn`, `PriceRejectNotifierFn`, `SetEscrowPriceGate`, `SetPriceRejectNotifier`, null-safe `EvaluateEscrowPriceGate`, `NotifyPriceReject`) — layer-neutral (int-typed reason, no coinprices include), installed between `TransactionManager::New` and `Start` via a `weak_from_this` lambda (D-08-01)
- Escrow-hold branch in the `ValidateTransactionForConsensus` check chain after `CheckTransactionTypeRules`: Pending maps to `ValidationResult::Pending()` exactly like the migration-allowlist precedent (D-08-02 — never Reject on a missing task record); Reject logs the typed reason, fires the reject notifier (08-03's hook point), and Rejects
- `GeniusNode::ValidateTaskPriceClaim` — the single evidence-assembly helper both enforcement points share: `ResolvePriceValidatorConfig`, millisecond-epoch `dagTimestamp`, blockSize recomputed exactly as the poster (`ProcessingManager::Create` + `ParseBlockSize`, Pitfall 7), injected `now` (purity contract), the ONE shared `PriceObservationWindow` + `QueryHistory` (D-04 node-local evidence), `ValidatePrice`, and the D-07-06 posted (non-blocking) self-heal fetch
- `GeniusNode::FindTaskByEscrow` — bounded claimable-list scan matching `task.escrow_path() == escrow.GetUncleHash()`; zero matches → Pending; cast/db failures never Reject
- Claim-time backstop in `TaskQueueImpl::GrabTask` (after `GetTask`/`IsProcessingValid`, before return) routing false verdicts to the existing `MarkTaskBad` per-node in-memory skip (D-08-04/D-08-10 — no CRDT write, no tombstone); `GeniusNode::CheckTaskPriceBackstop` fetches the escrow via `TransactionManager::FetchTransaction(*tx_globaldb_, task.escrow_path())` and fails closed on fetch failure (Open Q5)
- Unit cases `TaskQueue.PriceBackstopRejectMarksTaskBad` (with lock-key removal to prove the `incompatible_jobs_` skip rather than the claim lock) and `TaskQueue.PriceBackstopUnsetKeepsBehavior`

## Task Commits

All in the `SuperGenius` submodule on `dev_price_validation` (base `600de1e6`):

1. **Task 1: Consensus price gate — seam, escrow branch, GeniusNode evidence wiring** - `cdb2491b7` (feat)
2. **Task 2: Claim-time backstop with fail-closed fetch policy + unit tests** - `914731e0a` (feat)

Parent repo: `f241d9a` (chore: bump SuperGenius submodule pointer — carries the previously-uncommitted Phase 7 delta `9fcdabf5..600de1e6` plus the two 08-01 commits)

**Plan metadata:** committed with this SUMMARY (docs(08-01))

## Files Created/Modified

- `SuperGenius/src/transaction/TransactionManager.hpp` — gate seam types/members/setters (layer-neutral)
- `SuperGenius/src/transaction/TransactionManager.cpp` — seam implementations; null-safe Approve default
- `SuperGenius/src/transaction/TransactionConsensusHandler.cpp` — escrow-hold gate branch in the check chain
- `SuperGenius/src/account/GeniusNode.hpp` — `ValidateTaskPriceClaim` / `FindTaskByEscrow` / `CheckTaskPriceBackstop` declarations, `price_manager_mutex_`, PriceValidator include
- `SuperGenius/src/account/GeniusNode.cpp` — evidence assembly, gate entry, backstop check, both wiring sites
- `SuperGenius/src/processing/impl/TaskQueueImpl.hpp` — `TaskPriceBackstopFn`, `SetPriceBackstop`, `price_backstop_`
- `SuperGenius/src/processing/impl/TaskQueueImpl.cpp` — backstop insert in `GrabTask`
- `SuperGenius/test/src/processing/task_queue_test.cpp` — `TaskQueue` suite + two PriceBackstop cases

## Decisions Made

- **NoCoverage → Pending at the gate** (deviation, below): evidence absence is not a validation failure; the D-07-06 self-heal plus the built-in pending retry machinery (3-min TTL, 1-s retries) converges honest escrows, while every deterministic reason still Rejects — CONS-01's "cannot be approved" holds because Pending never approves
- **Backstop NoCoverage: fetch-and-revalidate once, then fail closed** — keeps honest tasks claimable on coverage-less nodes without ever processing an unverified job (D-08-08 invariant preserved)
- **Millisecond DAG timestamps** — `FillDAGStruct`/`GetCurrentTimestamp` verified to stamp/count milliseconds; the research sketch's `seconds{}` construction would have been off by 1000×
- **Suite named `TaskQueue`** (subclass of the `TaskQueueImplTest` fixture) so the plan's `--gtest_filter=TaskQueue.PriceBackstop*` selects exactly the new cases

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Gate must not Reject on NoCoverage — honest escrows were poison-marked**
- **Found during:** Task 1 (tracer verification)
- **Issue:** The plan's literal outcome mapping (Reject on every `!result.accepted`) made a coverage-less validator reject the honest escrow with reason=7 (NoCoverage) — log-proven: `ValidateTransactionForConsensus: Escrow price gate rejected tx=1e9ff953... task=b626e47b... reason=7` on both processors, after which the embedded-tx FAILED tracking permanently poisoned the proposal, no certificate formed, the payout failed, and `PostProcessing` failed (WaitForEscrowRelease timeout + balance assertion). The escrow and its task commit in ONE atomic CRDT transaction, so the task is always found on first evaluation — the "task not synced" Pending path cannot shield the NoCoverage case.
- **Fix:** `FindTaskByEscrow` maps NoCoverage to `Check::Pending` (warn log) instead of Reject; the D-07-06 self-heal fetch (posted inside `ValidateTaskPriceClaim`) plus pending retries re-evaluate once coverage lands. Deterministic reasons (LegacyNoPrice, TimestampFuture/Stale, CostMismatch, AboveBand, BelowBand) still Reject, so gamed claims can never be approved. After the fix: PostProcessing 5/5 (Task 1 verify) and 4/4 (Task 2 verify) green.
- **Files modified:** SuperGenius/src/account/GeniusNode.cpp
- **Verification:** ProcessingNodesTest.PostProcessing 9/9 green across both verification batches; gate activity log-verified (pending → retry → certified honest flow)
- **Committed in:** `cdb2491b7`

**2. [Rule 1 - Bug] Backstop must not permanently MarkTaskBad honest tasks on coverage-less nodes**
- **Found during:** Task 2 design (pre-wiring analysis of the same race class as deviation 1)
- **Issue:** Plan-literal backstop semantics (false → MarkTaskBad, permanent in-memory skip) would permanently skip an honest task whenever a processor's claim scan runs before its first price fetch — the task is claimable from CRDT sync, well before any quote fetch. Both processors marking it bad means nobody processes it and PostProcessing fails.
- **Fix:** `CheckTaskPriceBackstop` treats NoCoverage with ONE bounded synchronous `GetQuotes` fetch + re-validation before falling closed (fetch failure or still-empty window → false → MarkTaskBad). The claim loop may briefly block — never the consensus thread. Fail-closed semantics for escrow-fetch failure (Open Q5) and all deterministic rejects are unchanged.
- **Files modified:** SuperGenius/src/account/GeniusNode.cpp, SuperGenius/src/account/GeniusNode.hpp
- **Verification:** PostProcessing 4/4 green with the backstop live; two processor-side "Dispatched batch" fetches in the passing logs evidence the fetch-and-revalidate path
- **Committed in:** `914731e0a`

**3. [Rule 2 - Missing Critical] Mutex-guard lazy price manager construction**
- **Found during:** Task 1
- **Issue:** `GetOrCreatePriceManager`'s unsynchronized lazy construction was previously reachable only from RPC/processing threads; the gate now reaches it from the consensus-validation thread — a concurrent first-use could race two managers into existence.
- **Fix:** `std::mutex price_manager_mutex_` guarding the check-construct window.
- **Files modified:** SuperGenius/src/account/GeniusNode.hpp, SuperGenius/src/account/GeniusNode.cpp
- **Verification:** Build clean; PostProcessing green
- **Committed in:** `cdb2491b7` (member) / `914731e0a` (final form)

**4. [Rule 3 - Blocking] Baseline-comparison stale-object builds produced spurious fixture hangs**
- **Found during:** Task 1 regression triage
- **Issue:** Comparing against the unmodified tree via file copy + `git checkout --` left `Copy-Item`-restored sources with OLD mtimes, so MSBuild kept stale objects and produced mixed-layout binaries → all three nodes failed to reach a trust lifecycle state (SetUpTestSuite failure). This was a measurement artifact, not a code defect — disproven by a from-scratch rebuild of the same sources.
- **Fix:** Touch restored sources (or delete the affected .objs) before rebuilding; the same sources then built and passed 9/9.
- **Files modified:** none (build-tree hygiene only)
- **Verification:** Clean rebuild + 5/5 and 4/4 PostProcessing passes
- **Committed in:** n/a (process note)

**5. Research corrections adopted as ground truth (no code impact beyond correctness of units)**
- DAG `timestamp` is milliseconds (research sketch used seconds — would have been 1000× off); `PostProcessing` is NOT truncated (08-RESEARCH Pitfall 8 / assumption A4 wrong — it carries full assertions at :548/:563), which is what made the honest-green requirement binding.

---

**Total deviations:** 4 auto-fixed (2 bug, 1 missing-critical, 1 blocking/process) + 1 research-correction note
**Impact on plan:** Deviations 1-2 were required for the plan's own success criteria (honest flow green) and preserve every locked decision's intent: Pending is the sanctioned "can't decide yet" verdict, gamed claims can never be approved, and the backstop never processes an unverified task. No scope creep.

## Issues Encountered

- The first PostProcessing run after wiring the gate failed; root-caused via a baseline A/B (baseline 2/2 pass), a log-captured failing run (gate reject reason=7 on both processors), and a controlled rebuild of the plan-literal mapping to reproduce — the fix (NoCoverage→Pending) then passed 9/9. The interleaved "all nodes stuck in setup" failures were stale-object builds from the A/B procedure (deviation 4), not code.

## Authentication Gates

None — no external services or credentials involved.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Gate + backstop seams are live and green on the honest path; 08-02 (rejection subject/reason taxonomy surfacing) can consume `PriceRejectNotifierFn` via `SetPriceRejectNotifier` (already invoked on every Reject with the typed reason + task_id)
- 08-03's refund machinery can rely on: gate never rejects on absence (Pending), certificates still apply without re-running the gate (Pitfall 3 unchanged — the backstop remains the processing guard)
- 08-04's gamed-job test should flip the stub price to produce AboveBand/BelowBand (deterministic reasons — these still hard-Reject at the gate); note the NoCoverage→Pending mapping means a coverage-less validator abstains rather than rejects, which the convergence assertions (D-08-08) should account for
- Submodule pointer bumped in the parent repo (`f241d9a`), carrying the previously-uncommitted Phase 7 delta

## Self-Check: PASSED

All 8 modified files exist on disk; both task commits (`cdb2491b7`, `914731e0a`) verified in the submodule log; measured commit count `git rev-list --count 600de1e664..HEAD` = 2 matches `actuals.commits`. Builds clean (processing_nodes_test, task_queue_test, price_validator_test); TaskQueue.PriceBackstop* 2/2; task_queue_test full suite 20/20; ProcessingNodesTest.PostProcessing 9/9 green across verification batches; price_validator_test 22/22.

---
*Phase: 08-consensus-integration, Plan: 01*
*Completed: 2026-10-07*
