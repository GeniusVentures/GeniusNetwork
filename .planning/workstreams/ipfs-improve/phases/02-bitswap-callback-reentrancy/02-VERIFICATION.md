---
phase: 02-bitswap-callback-reentrancy
verified: 2026-10-13T13:25:00Z
status: passed
score: 9/9 must-haves verified
covered_files:
  - .planning/workstreams/ipfs-improve/phases/02-bitswap-callback-reentrancy/02-01-PLAN.md
  - .planning/workstreams/ipfs-improve/phases/02-bitswap-callback-reentrancy/02-01-SUMMARY.md
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp
  - thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp
  - thirdparty/ipfs-bitswap-cpp/test/bitswap_request_timer_race_test.cpp
  - thirdparty/ipfs-bitswap-cpp/test/CMakeLists.txt
covered_digest: "v2:sha256:49c91168fa2f1d186aedf6928bc86c94c9238bfa5c4a9b732679980f23b7d907"
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: none
---

# Phase 2: Bitswap Callback Reentrancy Verification Report

**Phase Goal:** Consumer callbacks are safe to call from — Bitswap never invokes them under an internal mutex, so re-entrant consumers cannot deadlock the protocol (ROADMAP Phase 2; SC1–SC4)
**Verified:** 2026-10-13
**Status:** passed → **VERDICT: VERIFIED**
**Re-verification:** No — initial verification (no prior VERIFICATION.md in the phase directory)

## Goal Achievement

Verification stance: goal-backward, adversarial. Every SUMMARY claim below was re-executed or re-read at HEAD `f899393` on `dev_timer_correctness` (Windows-side, read-only; the two Windows test executables re-run; the WSL ASan log re-read via read-only `tail`/`grep` only — no git, no rebuild inside WSL).

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | **BSTP-04 core:** `messageSent` registers callbacks strictly outside the `mutexRequestCallbacks_` scope (find-or-replace under the lock, reuse when incomplete, fresh context + `operator[]` assign when completed); `AddCallback`'s synchronous replay and `HandleResponse`'s dispatch loop execute with no Bitswap mutex held anywhere on the dispatching stack | ✓ VERIFIED | Function read at HEAD (src/bitswap.cpp L404-453): lock scope closes at `}` before the BSTP-04 WHY comment; the single `requestContext->AddCallback( std::move( onBlockCallback ) );` sits at L445 outside it. `git grep -n "AddCallback" HEAD -- src/bitswap.cpp` → exactly one call site (L445; L72 is the definition, L440 a comment). `AddCallback` (L72-118): completed branch contains ONLY `replayResult = terminalResult_;` — zero timer statements; the D-02 replay `callback( *replayResult )` sits textually after the guard scope's closing brace. `HandleResponse` (L121-149): move-out under `mutex_`, dispatch loop after release. Behavioral: `ReentrantAddCallbackOnCompletedDeliversReplayInline` PASS (a replay executed on a live dispatch stack without deadlock proves no mutex held); server-client `[COMPLETE]` exercises messageSent end-to-end |
| 2 | **BSTP-04 adjacency:** duplicate/late delivery for a completed CID dispatches nothing (completed check-and-set admits one winner); a registration at the completion boundary is either dispatched in the move-out loop or replayed from `terminalResult_`, never appended-and-silent (latent timeout-retention bug closed) | ✓ VERIFIED | Code: `HandleResponse` check-and-set under `mutex_`; `git grep -n "requestContexts_.erase" HEAD -- src/bitswap.cpp` → **empty** (exit 1); D-04 retention comment at the map site in `processReceivedBlocks` (L364-369) — a late/duplicate block finds the retained entry and hits the completed gate. Behavioral: `ExpiryDequeuedThenCompletionYieldsSingleResult` (pre-completion registration → move-out loop) and `LateRegistrationOnTimedOutReplaysRequestTimeout` (post-completion → replay, both flags asserted) both PASS; before this fix the timed-out entry + late AddCallback silently lost the callback — now replayed |
| 3 | **BSTP-04 empty (A2):** late registration on a consumer-canceled context (empty store) silently drops the callback — zero invocations, zero timers armed | ✓ VERIFIED | Code: `if ( replayResult && callback )` — empty `terminalResult_` (Cancel stores nothing) drops without invocation, without arming. Behavioral: `LateRegistrationOnCanceledContextIsDroppedNoTimerArmed` PASS — test body read: `EXPECT_EQ( totalInvocations, 0 )` + `EXPECT_EQ( io.poll(), 0 )` after a 100-step bounded drain. Phase 1 `TerminalTransitionWithZeroCallbacksIsSafe` and `ConsumerCancelProducesNoCallback` still green in the 13/13 runs |
| 4 | **BSTP-04 ordering:** replay delivers the stored terminal result unchanged — multiple late registrations each receive the identical stored value, synchronously, in registration order, before `AddCallback` returns | ✓ VERIFIED | `LateRegistrationOnTimedOutReplaysRequestTimeout` test body read (L536-604): two sequential late registrations, each with a `replayedBeforeReturn` flag set INSIDE the callback body and asserted `EXPECT_TRUE` immediately after the `AddCallback` call returns (before any io stepping — a posted delivery would leave it false); both subscribers share `lastErrorValue`. Phase 1 `MultipleCallbacksDispatchedInRegistrationOrder` green |
| 5 | **SC3 clause 2 / D-04:** no fresh `responseTimer_` armed on a completed request; completed entries retained until a same-CID request replaces them; sole map-erase deleted, no sweep machinery | ✓ VERIFIED | Code read: AddCallback completed branch contains no timer statement (only the `terminalResult_` capture); replay path is timer-free; erase grep empty; `messageSent` uses `requestContexts_[cid] = requestContext;` with the D-04 insert-or-replace comment — a completed entry is replaced, never replayed-into. Every new test ends with `EXPECT_EQ( io.poll(), 0 )` (no-fresh-timer idiom): 6/6 confirmed in the source read |
| 6 | **BSTP-05:** a consumer callback may synchronously `Cancel()` its own request or construct+register+complete a new request without deadlock or UAF — owning references on every dispatch path (timer-lambda `shared_from_this()`, `processReceivedBlocks` local ctx, retained map entry as third owner) | ✓ VERIFIED | Code: timer lambda captures `self = shared_from_this()` (L88-90); `processReceivedBlocks` holds local `ctx` across the post-scope `ctx->HandleResponse( block )` (L373-378); D-04 retention makes the map entry a long-lived owner (documented in the timer-capture comment). Behavioral: `ReentrantCancelOwnRequestNoDeadlock` PASS — test asserts `cancelReturned == 1` (the `++cancelReturned` after `locked->Cancel()` is reached only if Cancel returned: no deadlock) and `successCount == 1`; `ReentrantChainNewRequestCallbackFires` PASS — inline ctx2 chain delivers `chainedValue == "chained-block"`; D-08 inline-collision PASS. Supplementary: WSL ASan full-suite run — zero findings (spot-check table) |
| 7 | **TEST-01:** the full race suite passes — 7 Phase 1 cases unweakened + 6 new — deterministically, twice, identical counts, zero wall-clock waits, zero thread creation | ✓ VERIFIED | `git grep -c "TEST( RequestContextRaceTest" HEAD -- test/...` → **13**; all 13 names enumerated (7 Phase 1 names byte-identical + the 6 new). Test-file diff `e2dc906..HEAD` numstat = **358 insertions, 0 deletions** — purely additive, Phase 1 bodies provably untouched. Two consecutive full-binary runs: `[  PASSED  ] 13 tests.` both, 3 ms each, exit 0. ctest: `100% tests passed, 0 tests failed out of 1`. `git grep -E "sleep_for\|std::thread" HEAD -- test/...` → no matches |
| 8 | **D-03 symmetry:** a late subscriber to a timed-out request receives the stored REQUEST_TIMEOUT asserted **by value**; a late subscriber to a completed request receives the stored block payload | ✓ VERIFIED | Test body read: `EXPECT_EQ( lastErrorValue, static_cast<int>( BitswapError::REQUEST_TIMEOUT ) )` at L592 (the replay test; L243 is Phase 1's on-time assertion of the same value); `LateRegistrationOnCompletedReplaysStoredSuccess` asserts `replayedValue == "block-data"` |
| 9 | **Regression + evidence:** `bitswap_server_client_test` passes on the branch; WSL ASan run reports zero sanitizer findings; Phase 4 content probes greppable at HEAD | ✓ VERIFIED | Server-client re-executed: `[COMPLETE] ✅ All tests passed! Bitswap server-client communication working!`, clean client/server shutdown, exit 0. ASan log re-read: 13 PASSED, sanitizer-pattern count 0. Content probes at HEAD: `terminalResult_` 2(hpp)+2(cpp), `IsCompleted` 3+3, `D-04` 4, `completed_` 6, `REQUEST_TIMEOUT` 6, all 6 new case names + 13 TEST count greppable |

**Score:** 9/9 truths verified (0 present, behavior-unverified)

### ROADMAP Success Criteria Mapping

| SC | Criterion | Truths | Status |
|----|-----------|--------|--------|
| SC1 | Callbacks invoked only after every internal mutex released; state mutated under lock, exactly one winner; dispatch after unlock | 1, 2, 5 | ✓ VERIFIED |
| SC2 | Synchronous re-entry (cancel own request, chain new requests) without deadlock or UAF; `shared_from_this()` keeps context alive during dispatch | 6 | ✓ VERIFIED |
| SC3 | Late registration on a completed request receives the terminal result immediately (or fails fast); no fresh timer on a completed request | 3, 4, 5, 8 | ✓ VERIFIED |
| SC4 | Full race-ordering regression suite exists and passes deterministically — all four Phase 1 orderings unweakened plus reentrant cancel without deadlock | 7 | ✓ VERIFIED |

**Note on SC1 wording ("erased from the request map"):** the roadmap parenthetical describes mutation-under-lock examples in Phase 1's baseline shape. Phase 2's locked planning decision D-04 (02-CONTEXT) deliberately *deletes* the erase in favor of retention-until-replaced, because erase-on-complete is the root of the silent-callback-loss hole (truth 2). The plan's must_haves codify the erase deletion explicitly, and SC1's core assertion — mutate under lock, exactly one winner, dispatch after unlock — holds with the stronger semantics. Recorded as an intentional, planned refinement, not a gap.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp` | `IsCompleted()` accessor (TOCTOU @brief), `terminalResult_` member after `completed_`, `mutable mutex_`, updated `@mutex` contract, no new includes | ✓ VERIFIED | Single-hunk diff e2dc906..HEAD reviewed: all four present; no include changes; enum untouched |
| `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` | AddCallback completed/replay branch, HandleResponse terminal store, messageSent find-or-replace + hoisted registration, processReceivedBlocks erase-drop | ✓ VERIFIED | All read at HEAD (functions quoted in truth table); wired via test binary + server-client |
| `thirdparty/ipfs-bitswap-cpp/test/bitswap_request_timer_race_test.cpp` | 6 new GTest cases + header case list, purely additive | ✓ VERIFIED | 358/0 numstat; 13 cases; substantive assertions (values, ordered flags, zero-invocation counts) read in all 6 bodies |
| `thirdparty/ipfs-bitswap-cpp/test/CMakeLists.txt` | NO change (in-place extension of addtest target) | ✓ VERIFIED | `git diff --stat e2dc906..HEAD -- test/CMakeLists.txt` empty; ctest runs the target green |
| `dev_timer_correctness` branch | 3 new local commits (7 total from d2ec18af), never pushed | ✓ VERIFIED | `git log --oneline d2ec18af..HEAD` → exactly 7 (7fe1450, 0fcd1b2, 3463c14, e2dc906 = Phase 1; 3e88b9f, 93eb335, f899393 = Phase 2), linear; `git status --short` clean; `git branch -r` has no dev_timer_correctness |
| WSL throwaway ASan tree `~/gsd-asan/bitswap/` | `race_test_asan` + `asan_run.log` (evidence only) | ✓ VERIFIED | Both present, mtime 2026-10-13 13:01:29 (inside the execution session window); log shows 13 tests |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `messageSent` | `AddCallback` registration | find-or-replace under `mutexRequestCallbacks_` (IsCompleted gate, `operator[]` assign) → **outside** the lock the single `AddCallback` | ✓ WIRED | Code read L404-453; exercised end-to-end by `bitswap_server_client_test` `[COMPLETE]` |
| `processReceivedBlocks` | `HandleResponse` | under lock: find + `markProviderSuccess` + **no erase** (D-04 comment) → outside the lock `ctx->HandleResponse( block )` | ✓ WIRED | Code read L341-381; exercised by server-client (provider-success log line observed in its output) |
| `HandleResponseTimeout` | `HandleResponse(REQUEST_TIMEOUT)` → terminal store → replay | single store site gives D-03 both-outcomes symmetry | ✓ WIRED | Code read L121-154; `LateRegistrationOnTimedOutReplaysRequestTimeout` PASS |
| Race suite (13 cases) | existing addtest target → ctest | unchanged CMake registration | ✓ WIRED | `ctest -R bitswap_request_timer_race_test`: `100% tests passed, 0 tests failed out of 1` (0.02 s) |
| Windows source → WSL ASan evidence | `~/gsd-asan/bitswap` rsync copy → `race_test_asan` → log | D-07 file-copy pipeline | ✓ WIRED | Log reports the 13-case suite — the 13-case test file exists only at HEAD, so the sync provably carried the fix branch; zero git artifacts in WSL (log/binary only) |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `AddCallback` replay | `replayResult` ← `terminalResult_` | `HandleResponse`'s store of the incoming result / funneled REQUEST_TIMEOUT | ✓ real outcomes flow to late subscribers (value-asserted by tests) | ✓ FLOWING |
| `HandleResponse` dispatch | `callbacksToInvoke` ← `std::move( callbacks_ )` | real registrations from `messageSent` / test direct construction | ✓ real callbacks invoked post-release | ✓ FLOWING |
| `messageSent` map policy | `requestContext` ← `requestContexts_.find` or fresh `make_shared` | real request stream | ✓ exercised by server-client exchange | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Race suite run 1 | `bitswap_request_timer_race_test.exe` (test_bin/Debug) | `[==========] Running 13 tests` / `[  PASSED  ] 13 tests.` (3 ms), exit 0 | ✓ PASS |
| Race suite run 2 (SC4 determinism) | same exe, second invocation | `[  PASSED  ] 13 tests.` — identical counts, exit 0 | ✓ PASS |
| ctest registration | `ctest -C Debug -R bitswap_request_timer_race_test` | `100% tests passed, 0 tests failed out of 1` | ✓ PASS |
| Server-client regression | `bitswap_server_client_test.exe` (test/Debug) | `[COMPLETE] ✅ All tests passed! Bitswap server-client communication working!`, clean shutdown, exit 0 | ✓ PASS |
| WSL ASan log (read-only) | `wsl -e bash -lc "tail -n 5 ~/gsd-asan/bitswap/asan_run.log; grep -c -E 'AddressSanitizer\|heap-use-after-free\|heap-buffer-overflow\|stack-use-after-return\|SEGV on unknown address' ..."` | tail: `[  PASSED  ] 13 tests.`; sanitizer-pattern count: **0** | ✓ PASS |
| Branch discipline | `git log --oneline d2ec18af..HEAD`; `git status --short`; `git branch -r` | exactly 7 linear commits; clean; no remote dev_timer_correctness | ✓ PASS |
| Diff confinement | `git diff --stat e2dc906..HEAD` | only `src/bitswap.cpp` (102±), `src/bitswap.hpp` (35±), `test/bitswap_request_timer_race_test.cpp` (+358) | ✓ PASS |
| Content-path confinement (D-09/D-10) | `git diff d2ec18af..HEAD -- src/bitswap.cpp` \| grep `checkContentRequestComplete\|failContentRequest\|setupContentRequest\|processRequestQueue` | zero match lines | ✓ PASS |
| Map-erase prohibition | `git grep -n "requestContexts_.erase" HEAD -- src/bitswap.cpp` | empty (grep exit 1) | ✓ PASS |
| mutable mutex count | `git grep -c "mutable std::mutex" HEAD -- src/bitswap.hpp` | **8** (7 Bitswap-tier + context `mutex_`) | ✓ PASS |
| Cancel() byte-identity | `git show e2dc906:src/bitswap.cpp` vs `HEAD` — Cancel body extract | identical line-for-line (flag check → set → timer cancel → clear; stores nothing) | ✓ PASS |
| Phase 1 suite unweakened | `git diff --numstat e2dc906..HEAD -- test/bitswap_request_timer_race_test.cpp` | `358 0` — purely additive | ✓ PASS |
| Superproject discipline | root `git status --short` | `m thirdparty` gitlink dirty-uncommitted (expected — Phase 4 repins); no gitlink commits | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| BSTP-04 | 02-01-PLAN | Consumer callbacks dispatched outside all internal mutexes — state mutated under lock, callbacks invoked after unlock (C-7 port) | ✓ SATISFIED | Truths 1-5: code-shape reads + 5 passing new cases + server-client integration |
| BSTP-05 | 02-01-PLAN | Synchronous re-entry (cancel own request, new requests) without deadlock/UAF; context alive via `shared_from_this()` during dispatch | ✓ SATISFIED | Truth 6: three reentrancy tests PASS + owning references on all three dispatch paths + ASan zero findings |
| TEST-01 | 02-01-PLAN | Race-ordering regression suite exists and passes — Phase 1 orderings plus reentrant callback canceling its own request | ✓ SATISFIED | Truth 7: 13 cases, green twice identically, ctest 100%, sleep-free, single-threaded |

Orphaned requirements: none — REQUIREMENTS.md maps exactly BSTP-04, BSTP-05, TEST-01 to Phase 2 (traceability table lines 78-84).

### Prohibitions Check

| # | Prohibition | Status | Evidence |
|---|-------------|--------|----------|
| 1 | No consumer callback (incl. D-02 replay) invoked under any Bitswap mutex; AddCallback not inside the messageSent lock scope | ✓ HELD | Code reads (truth 1); D-08 inline-collision test PASS |
| 2 | No fresh `responseTimer_` on a completed request — completed branch has no timer statement at all | ✓ HELD | AddCallback completed branch read: only `replayResult = terminalResult_;`; 6/6 new tests assert drained `poll()==0` |
| 3 | No map-erase on completion reintroduced anywhere | ✓ HELD | `git grep requestContexts_.erase HEAD -- src/bitswap.cpp` empty; D-04 comments at both map sites |
| 4 | Replay never posted/queued to io_context — synchronous after lock release only; no stale replay into a NEW same-CID request | ✓ HELD | Direct `callback( *replayResult )` call, no `post`/`dispatch`; messageSent replaces completed entries (IsCompleted gate), never replays into them |
| 5 | No content-request-path fixes — the four functions byte-identical | ✓ HELD | Cumulative diff `d2ec18af..HEAD -- src/bitswap.cpp` contains zero lines naming any of the four functions |
| 6 | No timer abstraction/factory/mock in production header; no new BitswapError enum values | ✓ HELD | hpp diff: single hunk, class-interior only — no enum, no includes, real `deadline_timer` unchanged |
| 7 | `BitswapRequestContext` acquires no lock other than `mutex_` | ✓ HELD | AddCallback/HandleResponse/Cancel/IsCompleted bodies read: only `std::lock_guard<std::mutex> guard( mutex_ )` |
| 8 | 7 existing race cases not weakened/renamed/deleted; no sleeps, no threads, no timer error_code-identity assertions | ✓ HELD | numstat 358/0 (additive only); zero `sleep_for`/`std::thread`; sole `error_code` occurrence in tests is a doc comment (L93), no assertion reads it |
| 9 | Never pushed, never rebased — linear from d2ec18af, commits only on dev_timer_correctness | ✓ HELD | 7 linear commits; no remote branch; clean tree; superproject gitlinks uncommitted |
| 10 | No git inside WSL — rsync file-copy only, throwaway tree | ✓ HELD | WSL tree holds only source copy + `race_test_asan` + `asan_run.log`; verification itself used read-only `tail`/`grep`/`stat` in WSL |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | none | — | Debt-marker scan (`TBD/FIXME/XXX` and `TODO/HACK/PLACEHOLDER/not-yet-implemented`) over all three modified files at HEAD: zero matches; no stub returns; the restructured branches are full implementations, not shells |

### Deviations Judgment (from SUMMARY)

1. **Stale erase-reference comment reworded + folded via amend of the executor's own unpushed commit:** gate-hygiene fix so the plan's fails-ANY-line erase grep is not tripped by a comment. Net chain verified: still exactly 7 linear commits from d2ec18af, never pushed. **Accepted.**
2. **WSL ASan compile/link line resolved empirically** (research assumption A1): Boost include root, spdlog fmt macros, Debug-suffixed protobuf archive, soralog object set, `--start-group` link wrapping — all build-environment discoveries, no code impact. Evidence verified: log shows the 13-case suite passing with zero sanitizer findings and artifact mtimes inside the session window. **Accepted.**
3. **SUMMARY claims vs. observed:** every table row in the SUMMARY's Verification Results was reproduced exactly (13/13 ×2, ctest 100%, `[COMPLETE]` marker, erase grep empty, mutable count 8, 7 commits, 3-file confinement, no content-path hunks, clean tree). **No discrepancy found.**

### Human Verification Required

None. All must-haves have deterministic automated evidence — the 13-case suite IS the deterministic acceptance evidence TEST-01 demands; the ASan run supplies the lifetime evidence; no UI, no external services, no real-time behavior in scope.

### Gaps Summary

No gaps. All 9 must-have truths verified with code-read evidence plus re-executed behavioral tests (race suite ×2 identical 13/13, ctest green, server-client regression green on the restructured branch, WSL ASan log 13-pass with zero findings). All 3 phase requirements (BSTP-04, BSTP-05, TEST-01) satisfied. All 10 prohibitions held. Scope exactly confined: 3 Phase 2 commits on `dev_timer_correctness`, linear from `d2ec18af`, touching only the three plan files with zero content-path hunks (D-09/D-10), never pushed, superproject gitlinks dirty-uncommitted as planned. Phase 4 inherits greppable content-probe markers at HEAD `f899393`: `terminalResult_`, `IsCompleted`, the `D-04` retention comments, and the six new case names (alongside Phase 1's `completed_`, `REQUEST_TIMEOUT`).

---

_Verified: 2026-10-13_
_Verifier: the agent (gsd-verifier)_
