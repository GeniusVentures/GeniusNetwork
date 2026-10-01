---
phase: 03-local-price-manager
plan: 02
subsystem: coinprices
tags: [price, coalescing, batching, single-flight]
requires:
  - "03-01 LocalPriceManager skeleton (L1 cache, strand executor, blocking GetQuotes)"
provides:
  - "Per-currency PendingWindow coalescing (~50ms default, injectable) with id-union batching (D-05/D-08)"
  - "DispatchBatchOnStrand — move-out-then-erase dispatch, inline tier walk, per-waiter subset resolution"
  - "Dtor waiter resolution + window-timer cancellation (shutdown safety)"
  - "FakePriceSource::SetCallGate (latch-parked calls for D-07 scenarios)"
affects: []
tech-stack:
  added: []
  patterns:
    - "Timer-armed == window-open idempotence (the coordinator.ts scheduleFlush translation, strand-strengthened — P-5)"
    - "bind_executor(strand_, ...) on steady_timer::async_wait — timer built from *ioc_, callback bound to the strand"
key-files:
  created: []
  modified:
    - SuperGenius/src/coinprices/LocalPriceManager.hpp
    - SuperGenius/src/coinprices/LocalPriceManager.cpp
    - SuperGenius/test/src/price_manager/price_manager_test.cpp
key-decisions:
  - "D-03 single-in-flight and D-07 new-window-queues remain STRUCTURAL (asio handler serialization) — no in-flight flag, no condition variables, no mutex anywhere in the manager"
  - "Two coalescing cases ran red at Task 1 (NConcurrent + EachWaiter), both on the same pre-window cause (CallCount 2 vs 1) — the plan predicted one; the second case's CallCount==1 assertion is equally window-dependent, so both flipped green with the implementation"
requirements-completed: [LPM-02, LPM-03]
coverage:
  - deliverable: "Coalescing window with union batching and per-waiter subsets"
    verification:
      - kind: tests
        ref: "price_manager_test#NConcurrentRequestsCollapseIntoOneCall,EachWaiterReceivesItsSubsetWithCorrectSource,MultiIdRequestIsOneBatch,PerCurrencyWindowsAreSeparate,NewMissesDuringInflightOpenNewWindow,FirstCallerPaysTheWindowCost"
        status: pass
    human_judgment: false
  - deliverable: "No regression to 03-01 behavior or Phase 2 suites"
    verification:
      - kind: command
        ref: "ctest -R 'price_manager_test|price_quote_test|price_http_client_test|price_facade_test' — 4/4 suites, 13 manager cases"
        status: pass
    human_judgment: false
duration: 12 min
completed: 2026-10-01T22:02:00Z
---

# Phase 3 Plan 02: Coalescing Window + Union Batching Summary

Per-currency PendingWindow coalescing (timer-armed on first miss, id-union batches, per-waiter subset resolution) with D-07 as a structural property of the inline strand walk — N-in-window requests collapse to exactly one tier call; new misses during an in-flight walk open a fresh window that dispatches only after it completes.

**Duration:** ~12 min | **Tasks:** 3/3 | **Files:** 3 modified

## Accomplishments

- `LocalPriceManager.hpp` — nested `PendingWaiter{requestedIds, immediate, done}` and `PendingWindow{ids(set), waiters, timer}`; `windows_` keyed by currency placed with state members before `m_logger`/`thread_`; `DispatchBatchOnStrand` declaration.
- `LocalPriceManager.cpp` — miss path joins the currency's window instead of dispatching: first miss arms `make_unique<steady_timer>(*ioc_)` + `expires_after(coalescingWindow_)` + `async_wait(bind_executor(strand_, ...))` (comment documents the one-thread invariant); dispatch moves the window out and erases it BEFORE walking (the window closes when dispatch begins — D-07), then the inline tier-1 walk + per-waiter assembly with tier-source-preserved serving; dtor now cancels window timers and resolves every parked waiter with `{NetworkError, 0}` before reset/join (shutdown-safety landmine closed).
- Tests — 6 coalescing cases: NConcurrent (4 requests → CallCount==1, 4-id union set-equality, per-waiter subsets 2/2/2/1), EachWaiter subsets+source, MultiId one-batch, PerCurrency separation, NewMissesDuringInflight (latch-gated call 1 via `SetCallGate` + shared future; call 2 lands in a disjoint `{"q"}` batch), FirstCallerPaysTheWindowCost. 13/13 green.

## Commit

- SuperGenius `dev_tokenprice` @ `cf80e3e9d` — `feat(coinprices): coalescing window + union batching - per-currency PendingWindow, timer-armed dispatch, D-07 structural serialization (LPM-02, LPM-03, D-05..D-08)`
- Also includes the Task-1 red-first test additions (TDD: red observed at NConcurrent + EachWaiter before implementation).

## Deviations from Plan

**[Rule 1 - Test observability] FakePriceSource::SetCallGate added in Task 1 (not later)** — Found during: Task 1 | Issue: `NewMissesDuringInflightOpenNewWindow` needs the gate hook now (the plan's Task-1 action itself specifies extending the fake with `SetCallGate`); also the gate must run OUTSIDE the fake's mutex or the parked call deadlocks test observation | Fix: gate stored under lock, invoked after release, receives the zero-based call index exactly as specified | Files: `price_manager_test.cpp` | Verification: case green | Commit: cf80e3e9d

**[Rule 1 - Expected-red count] Two red cases instead of one at Task 1** — Found during: Task 1 verify | Issue: plan expected only NConcurrent red; EachWaiterReceivesItsSubsetWithCorrectSource also asserts `CallCount()==1` and was equally red pre-window (2 calls observed) | Fix: none needed — same coalescing cause; both flipped green after Task 2. Recorded for honest bookkeeping | Files: test file | Verification: 13/13 green | Commit: cf80e3e9d

**Total deviations:** 2 auto-fixed (fixture timing, red-count bookkeeping). **Impact:** none — production code matches the plan; D-03/D-07 remain structural (grep `inflight|in_flight|std::mutex` in the manager: 0).

## Self-Check: PASSED

- Task 1 AC: 6 cases existed and compiled; pre-Task-2 red = the window-dependent CallCount assertions (NConcurrent, EachWaiter) with the other 4 green as regression guards; post-Task-2 all 13 green — PASS (see deviation 2).
- Task 2 AC: header declares PendingWaiter/PendingWindow (with `unique_ptr<steady_timer> timer`), `windows_` keyed string, DispatchBatchOnStrand — PASS. `.cpp` contains `expires_after( coalescingWindow_ )` and move-out-then-erase prologue (`windows_.erase(` before the tier call) — PASS. Dtor cancels timers and resolves parked waiters (`cancel` + `set_value` in the shutdown handler) — PASS. No `std::mutex` in the manager — PASS.
- Task 3 AC: four suites green in one ctest invocation (manager at 13 cases); commit on dev_tokenprice with the coalescing message; tree clean; nothing pushed — PASS.

## Verification Results

| Check | Result |
|---|---|
| 13/13 price_manager_test cases | PASSED |
| 4-suite ctest gate | 100% PASSED |
| `std::mutex`/`inflight`/`in_flight` grep in manager | 0 hits |
| `git -C SuperGenius log -1` | cf80e3e9d on dev_tokenprice |

Ready for 03-03 (fallback chain + D-14 fold-in).
