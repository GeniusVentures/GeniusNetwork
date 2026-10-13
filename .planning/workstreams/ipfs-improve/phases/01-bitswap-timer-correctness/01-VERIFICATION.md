---
phase: 01-bitswap-timer-correctness
verified: 2026-10-12T00:00:00Z
status: passed
score: 9/9 must-haves verified
covered_files:
  - .planning/workstreams/ipfs-improve/phases/01-bitswap-timer-correctness/01-01-PLAN.md
  - .planning/workstreams/ipfs-improve/phases/01-bitswap-timer-correctness/01-01-SUMMARY.md
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp
  - thirdparty/ipfs-bitswap-cpp/test/bitswap_request_timer_race_test.cpp
  - thirdparty/ipfs-bitswap-cpp/test/CMakeLists.txt
covered_digest: "v2:sha256:0c900c496d8c1cc781031af7c3864e43270fb5fba5816103f5dce3642ae53e77"
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: none
---

# Phase 1: Bitswap Timer Correctness Verification Report

**Phase Goal:** A canceled Bitswap request timer is treated as canceled, never as a timeout, and every block request produces exactly one terminal result — proven by deterministic race-ordering tests on a single-threaded `io_context` with injected durations and no sleeps
**Verified:** 2026-10-12
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | **BSTP-01 (SC1):** ec-guard in the `AddCallback` async_wait lambda — set `error_code` returns before `HandleResponseTimeout`; failure path disarmed via explicit `.cancel()`, never `expires_at(pos_infin)` | ✓ VERIFIED | `git diff d2ec18af..HEAD -- src/bitswap.cpp`: `if ( ec ) { return; }` is the first statement of the lambda body (L81-88); old `expires_at(pos_infin)` removed, `responseTimer_.cancel()` in its place. Behavioral: `CancelBeforeExpiryYieldsExactlyOneSuccess` and `ResponseThenCanceledTimerFiresNoFailure` both PASS (aborted handler provably runs via `poll()` drain; successCount==1, errorCount==0) |
| 2 | **BSTP-02 core:** `HandleResponse` check-and-sets `completed_` under `mutex_`, disarms timer, moves callbacks out under lock, dispatches after release | ✓ VERIFIED | Diff L94-120: exact shape (flag check → set → `cancel()` → `std::move(callbacks_)` inside lock scope; invocation loop outside). Only `mutex_` acquired (prohib 6). Behavioral: `ExpiryDequeuedThenCompletionYieldsSingleResult` PASS (1 success, 0 error) |
| 3 | **BSTP-02 boundary:** expired handler already dequeued runs late after completion landed — flag drops it, exactly one terminal result | ✓ VERIFIED | `ExpiryDequeuedThenCompletionYieldsSingleResult` PASS. Platform deviation (triaged in 01-REVIEW-DISPOSITION.md): on MSVC 19.44/Boost 1.85 the late handler arrives `operation_aborted` (ec-guard drop) rather than success-ec (flag drop). The flag-drops-late-terminal mechanism has **direct** behavioral evidence elsewhere: `GenuineTimeoutThenLateResponseSingleTimeout` (late `HandleResponse` after timeout-terminal changes nothing) and `ConsumerCancelProducesNoCallback` (late `HandleResponse` after cancel-terminal delivers nothing). Asserted outcome — exactly one terminal — is identical either way; assertions unweakened |
| 4 | **BSTP-02 empty:** terminal transition with zero callbacks is safe, no error | ✓ VERIFIED | `TerminalTransitionWithZeroCallbacksIsSafe` PASS in both runs: no crash, final `poll()==0` |
| 5 | **BSTP-02 dispatch order:** multiple callbacks invoked in registration order (wholesale ordered-list move-out) | ✓ VERIFIED | `MultipleCallbacksDispatchedInRegistrationOrder` PASS: `dispatchOrder == {1,2,3}`, all three observed `"shared-block"` |
| 6 | **SC4 determinism:** single-threaded `io_context`, injected durations, `poll()`/`run_one()` stepping only, no wall-clock waits, no worker threads, identical counts across runs | ✓ VERIFIED | Full test-file read: every test constructs its own `io_context`, durations injected (60 s / −1 ms), stepping is `poll()`/`run_one()` only. `Select-String "sleep\|std::thread\|pos_infin"` over the test file: zero code matches (doc comment only). Race exe run **twice**: 7/7 PASSED both runs, identical counts |
| 7 | **BSTP-03 error semantics:** genuine timeout → exactly one `REQUEST_TIMEOUT` failure; consumer Cancel and success → no error callback | ✓ VERIFIED | Per-class explicit evidence (flagged assumption resolved — never inferred): timeout class: `GenuineTimeoutThenLateResponseSingleTimeout` asserts `lastErrorValue == static_cast<int>(BitswapError::REQUEST_TIMEOUT)`, errorCount==1, successCount==0 — PASS; consumer-cancel class: `ConsumerCancelProducesNoCallback` — 0 invocations incl. after late `HandleResponse` — PASS; success class: `CancelBeforeExpiry` + `ResponseThenCanceledTimerFiresNoFailure` — errorCount==0 — PASS |
| 8 | **D-01 production invariance:** `messageSent` call site compiles unchanged; default stays 5 s via defaulted ctor param | ✓ VERIFIED | `git grep "make_shared<BitswapRequestContext>" HEAD`: line 389 single-arg `(*context_)`, zero diff lines touch it. hpp diff: `responseTimeout = boost::posix_time::seconds( 5 )` defaulted |
| 9 | **Regression:** pre-existing `bitswap_server_client_test` passes on the fix branch | ✓ VERIFIED | Executed from the build tree: `[COMPLETE] All tests passed! Bitswap server-client communication working!` marker present, clean client/server shutdown |

**Score:** 9/9 truths verified (0 present, behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp` | defaulted ctor param, `Cancel()` decl, `completed_` member | ✓ VERIFIED | 17-line diff, all three present + updated mutex-contract doc |
| `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` | full C-5 port on BitswapRequestContext | ✓ VERIFIED | 52-line diff: ec-guard, flag-under-mutex, explicit cancel, move-out dispatch, REQUEST_TIMEOUT |
| `thirdparty/ipfs-bitswap-cpp/test/bitswap_request_timer_race_test.cpp` | NEW deterministic race suite | ✓ VERIFIED | 342 lines, 7 GTest cases, @given/@when/@then docs, unweakened assertions |
| `thirdparty/ipfs-bitswap-cpp/test/CMakeLists.txt` | addtest() registration | ✓ VERIFIED | addtest + link set + GSL include; wired (ctest runs it green) |
| Fix branch from `d2ec18af` | local-only branch, 4 commits | ✓ VERIFIED | `dev_timer_correctness`; `7fe1450`→parent `d2ec18a`; exactly 4 commits; clean tree |
| Configured test build tree | `$B` per Task 1 decision | ✓ VERIFIED | `thirdparty/build/Windows/Debug/ipfs-bitswap-cpp-test` — all three exes executed from it |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| AddCallback async_wait lambda | HandleResponseTimeout → HandleResponse(REQUEST_TIMEOUT) | ec check gates the only call | ✓ WIRED | Code read; exercised by 4 ordering tests |
| processReceivedBlocks | HandleResponse → flag/cancel/move-out under `mutex_` → dispatch after release | no outer lock at the HandleResponse call | ✓ WIRED | Diff preserves invocation structure; real path exercised by `bitswap_server_client_test` [COMPLETE] |
| `messageSent` make_shared site | defaulted constructor | single-arg call unchanged | ✓ WIRED | HEAD grep line 389; zero diff lines |
| `test/CMakeLists.txt` addtest | ctest registration → green run | GTest target through build tree | ✓ WIRED | `ctest -R bitswap_request_timer_race_test`: 100% passed, 0 failed |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Race suite (run 1) | `bitswap_request_timer_race_test.exe` | 7/7 PASSED (2 ms) | ✓ PASS |
| Race suite (run 2 — SC4 determinism) | same exe, second invocation | 7/7 PASSED, identical counts | ✓ PASS |
| ctest registration | `ctest -C Debug -R bitswap_request_timer_race_test` | 100% passed (1/1, 0.02 s) | ✓ PASS |
| Production-path regression | `bitswap_server_client_test.exe` | exit clean, `[COMPLETE] All tests passed!` marker | ✓ PASS |
| Content probe: `completed_` | `git grep -n "completed_" HEAD -- src/bitswap.cpp` | lines 100, 106, 128, 132 | ✓ PASS |
| Content probe: `REQUEST_TIMEOUT` | `git grep -n "REQUEST_TIMEOUT" HEAD -- src/bitswap.cpp` | line 122 (timeout mapping) present | ✓ PASS |
| Branch provenance | `git log --format='%h %p' -4` | linear: e2dc906→3463c14→0fcd1b2→7fe1450→d2ec18af | ✓ PASS |
| No-push | `git branch -r` | no `origin/dev_timer_correctness` | ✓ PASS |
| Scope confinement (D-05) | `git diff --stat d2ec18af..HEAD` | 4 files only (2 src BitswapRequestContext, 2 test); zero hunks in ContentRequestContext / processReceivedBlocks / messageSent | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|---------------------|----------|
| BSTP-01 | 01-01-PLAN | Canceled request timer never fires the failure path (ec check, `operation_aborted` return) | ✓ SATISFIED | Truth 1: ec-guard in diff + 2 passing ordering tests with drained aborted handlers |
| BSTP-02 | 01-01-PLAN | Exactly one terminal result per request — completion flag under mutex makes success/timeout mutually exclusive incl. late expired handler | ✓ SATISFIED | Truths 2-5: flag semantics in diff + 5 passing tests (boundary, empty, dispatch-order) |
| BSTP-03 | 01-01-PLAN | Consumer cancel and success → no error callback; genuine timeout → exactly one `REQUEST_TIMEOUT` failure | ✓ SATISFIED | Truth 7: all three outcome classes with explicit passing test evidence (flagged assumption resolved) |

Orphaned requirements: none — REQUIREMENTS.md maps exactly BSTP-01/02/03 to Phase 1; no other IDs claim this phase.

### Prohibitions Check

| # | Prohibition | Status | Evidence |
|---|-------------|--------|----------|
| 1 | No modification to ContentRequestContext / content-request paths (D-05) | ✓ HELD | src diff confined to BitswapRequestContext ctor/AddCallback/HandleResponse/HandleResponseTimeout/Cancel |
| 2 | No timer abstraction/factory/mock in production header (D-02) | ✓ HELD | real `boost::asio::deadline_timer responseTimer_` unchanged in hpp |
| 3 | No wall-clock waits / worker threads in race tests (SC4) | ✓ HELD | grep: zero `sleep`/`std::thread` code matches in test file |
| 4 | Never rebased, cut only from `d2ec18af`, nothing pushed | ✓ HELD | linear parent chain from d2ec18a; no remote branch; working tree clean |
| 5 | No Phase 2 scope in Phase 1 commits | ✓ HELD | no processReceivedBlocks/messageSent/request-map changes; `Cancel()` was planner-approved (RESEARCH Q1) |
| 6 | Only `mutex_` acquired inside BitswapRequestContext | ✓ HELD | diff: only `std::lock_guard<std::mutex> guard( mutex_ )` (HandleResponse, Cancel); outer mutex never taken |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | none | — | Debt-marker scan over the phase diff (429 added lines) and the new test file: zero matches for TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER; no stub returns |

### Deviations Judgment (pre-triaged)

1. **Ordering-2 platform behavior (ec-guard drop instead of flag-drop):** Does NOT break BSTP-02. The truth's asserted outcome — exactly one terminal result — is asserted and passes; the flag-drops-late-terminal mechanism has direct behavioral evidence in ordering 4 and ConsumerCancel late-`HandleResponse` phases. Documented in the test's doc comment. Accepted.
2. **CMake full-sibling link set + GSL include (vs plan's minimal 4-target list):** Wiring-only deviation; sibling-pattern-conformant and proven by the green ctest run. Accepted.
3. **Flagged assumption (BSTP-03 three outcome classes, never inferred):** Resolved — each class confirmed above with a named passing test asserting the exact error value or zero-invocation count.

### Human Verification Required

None. All must-haves have deterministic automated evidence — the race suite IS the deterministic acceptance evidence the requirements demand. No UI, no external services, no real-time behavior in scope.

### Gaps Summary

No gaps. All 9 must-have truths verified with codebase evidence plus self-executed behavioral tests (race suite ×2 identical, ctest green, regression green). All 3 phase requirements satisfied. All 6 prohibitions held. Scope exactly confined (4 commits, 4 files, BitswapRequestContext only) on `dev_timer_correctness` cut linearly from `d2ec18af`, never pushed. Phase 2 inherits the harness and completion-flag semantics; Phase 4 inherits greppable content-probe markers (`completed_`, `REQUEST_TIMEOUT` at HEAD e2dc906).

---

_Verified: 2026-10-12_
_Verifier: the agent (gsd-verifier)_
