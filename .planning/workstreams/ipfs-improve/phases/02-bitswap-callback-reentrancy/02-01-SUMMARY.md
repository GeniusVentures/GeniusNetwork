---
phase: 02-bitswap-callback-reentrancy
plan: 01
subsystem: testing
tags: [cpp, concurrency, bitswap, callbacks, reentrancy, asan, gtest]

requires:
  - phase: 01-bitswap-timer-correctness
    provides: HandleResponse move-out-under-lock dispatch shape, Cancel() no-callback semantics, 7-case deterministic race harness, Windows test build tree
provides:
  - Synchronous terminal-result replay in BitswapRequestContext::AddCallback (D-01..D-03) with no-fresh-timer guarantee (SC3 clause 2)
  - messageSent find-or-replace map policy with registration hoisted outside mutexRequestCallbacks_ (BSTP-04, D-04, closes D-10 inventory site 3)
  - processReceivedBlocks retention-until-replaced (sole map-erase deleted; completion flag selects the single winner)
  - TEST-01 complete: 13-case deterministic race suite (7 Phase 1 + 6 new) green twice, ctest 100%
  - WSL ASan supplementary run of the full suite: zero sanitizer findings, exit 0
affects: [03-gossipsub-bounds, 04-repin-verify]

actuals:
  tokens: 6476   # chars/4 over the realized e2dc906..HEAD diff (estimate was 45000 — conservative)
  tasks: 3
  commits: 3     # submodule-local on dev_timer_correctness; never pushed

tech-stack:
  added: []      # no new libraries — in-tree C++17/Boost.Asio/GTest only
  patterns:
    - "Replay-after-lock-release: capture stored terminal outcome under mutex_, invoke the late subscriber strictly after the guard scope closes (extends Phase 1's move-out dispatch idiom to registration)"
    - "Find-or-replace-under-lock / register-outside-lock: the Bitswap-tier map policy pattern (IsCompleted advisory gate + operator[] assign with retention comment)"

key-files:
  created: []
  modified:
    - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp   # IsCompleted() accessor, terminalResult_ member, mutable mutex_, updated @mutex contract
    - thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp   # AddCallback completed/replay branch, HandleResponse terminal store, messageSent find-or-replace + hoisted AddCallback, processReceivedBlocks erase-drop, IsCompleted definition
    - thirdparty/ipfs-bitswap-cpp/test/bitswap_request_timer_race_test.cpp  # 6 new cases (7 → 13), harness header case list
  evidence-only:
    - "~/gsd-asan/bitswap/race_test_asan + asan_run.log (WSL throwaway tree, D-07)"

key-decisions:
  - "None new — all ten locked decisions (D-01..D-11) and both flagged-assumption resolutions (A2 silent drop, A4 hang-triage) executed exactly as planned"

patterns-established:
  - "Replay-branch registration: AddCallback captures terminalResult_ under mutex_ (empty = canceled-terminal drop per A2), replays synchronously after lock release, never arms the timer on a completed context"
  - "Registration hoist: the single ctx->AddCallback call in messageSent sits textually outside the mutexRequestCallbacks_ scope with the WHY comment — the D-02 replay may execute consumer code on the registering stack"

requirements-completed: [BSTP-04, BSTP-05, TEST-01]

coverage:
  - id: D1
    description: "Three BSTP-04 seams landed on dev_timer_correctness: synchronous terminal-result replay in AddCallback (both outcomes, canceled-drop), messageSent find-or-replace with registration outside the outer lock, processReceivedBlocks retention (no map-erase anywhere)"
    requirement: BSTP-04
    verification:
      - kind: unit
        ref: "bitswap_request_timer_race_test.exe — LateRegistrationOnCompletedReplaysStoredSuccess, LateRegistrationOnTimedOutReplaysRequestTimeout, LateRegistrationOnCanceledContextIsDroppedNoTimerArmed"
        status: pass
      - kind: integration
        ref: "bitswap_server_client_test.exe — '[COMPLETE] All tests passed!' through restructured messageSent/processReceivedBlocks over real libp2p streams"
        status: pass
      - kind: unit
        ref: "source-shape greps at HEAD: requestContexts_.erase returns nothing; single AddCallback in messageSent outside lock scope; mutable std::mutex count == 8"
        status: pass
  - id: D2
    description: "Consumer callbacks re-enter synchronously without deadlock or UAF — reentrant cancel (D-05a), reentrant chain (D-05b), D-08 SC3×BSTP-05 inline collision — with owning references on every dispatch path"
    requirement: BSTP-05
    verification:
      - kind: unit
        ref: "ReentrantCancelOwnRequestNoDeadlock, ReentrantChainNewRequestCallbackFires, ReentrantAddCallbackOnCompletedDeliversReplayInline — all green, bounded-step drains, final poll()==0"
        status: pass
      - kind: other
        ref: "WSL ASan full-suite run (~/gsd-asan/bitswap/asan_run.log): 13/13 passed, ASAN_EXIT:0, zero AddressSanitizer findings"
        status: pass
  - id: D3
    description: "TEST-01 complete: 13-case deterministic race suite — 7 Phase 1 orderings unweakened + 6 new cases — green in two consecutive full runs with identical counts, ctest 100%, sleep-free and single-threaded"
    requirement: TEST-01
    verification:
      - kind: unit
        ref: "two consecutive runs '[  PASSED  ] 13 tests.'; ctest -R bitswap_request_timer_race_test: 100% tests passed; Select-String sleep_for/std::thread over the suite: no matches"
        status: pass

duration: 32min
completed: 2026-10-13
status: complete
---

# Phase 2: Bitswap Callback Reentrancy Summary

**Consumer callbacks — including the new synchronous replay — are never invoked under any Bitswap mutex; reentrant consumers (cancel-own-request, chain-new-request) cannot deadlock or UAF; late registrants receive the stored terminal outcome immediately; the 13-case deterministic race suite plus a clean WSL ASan run close audit C-7's P0 at the block-request tier.**

## Performance

- **Duration:** ~32 min (execution session 2026-10-13 12:40–13:12 local)
- **Tasks:** 3/3
- **Files modified:** 3 (all inside thirdparty/ipfs-bitswap-cpp)

## Accomplishments

- **Seam 1 (D-01..D-03):** `AddCallback` restructured into a two-branch lock-guard body — incomplete branch keeps Phase 1's timer-arm + self-capture + append verbatim; completed branch captures `terminalResult_` (empty on the canceled terminal → silent drop per A2/BSTP-03) and touches no timer statement. The D-02 replay invocation sits textually after the lock scope. `HandleResponse` gained exactly one store (`terminalResult_ = block;` beside the completed-flag set) — REQUEST_TIMEOUT funnels through it, giving both-outcomes replay symmetry from a single site. `Cancel()` is byte-identical to e2dc906.
- **Seam 2 (BSTP-04/D-04):** `messageSent` now find-or-replaces under `mutexRequestCallbacks_` (reuse when `!IsCompleted()`, else fresh context + `operator[]` assign with the D-04 retention comment — insert-or-replace, never replay-into) and performs the single `AddCallback` strictly outside the lock, closing D-10 inventory site 3 (the one SC1 integration gap).
- **Seam 3 (D-04/SC1):** the sole `requestContexts_.erase` in the file is deleted; the completion flag selects the single winner; the retained map entry is the third BSTP-05 owner (timer-lambda `self`, local `ctx`, map entry).
- **TEST-01 at 13 cases:** tracer `LateRegistrationOnCompletedReplaysStoredSuccess` (Task 1) + reentrant cancel/chain, replay-timeout with the D-03 error-VALUE assertion on both late subscribers, the D-08 ordered-flag inline-collision proof, and the canceled-drop case. Two consecutive full runs: identical 13-pass counts; ctest 100%; zero sleeps/threads.
- **D-07 supplementary ASan:** full suite under clang++ `-fsanitize=address` in WSL (throwaway rsync copy, zero git inside WSL) — 13/13, `ASAN_EXIT:0`, zero sanitizer findings; log preserved at `~/gsd-asan/bitswap/asan_run.log`.

## Task Commits

All commits are local-only on `dev_timer_correctness` inside the submodule (never pushed, never rebased; D-11):

1. **Task 1 seams** — `3e88b9f` feat(02-01): close BSTP-04 — synchronous terminal-result replay in AddCallback (D-01..D-03), registration hoisted outside request-map lock, retention-until-replaced map policy (D-04)
2. **Task 1 tracer** — `93eb335` test(02-01): add late-registration race case — synchronous replay of stored success, no fresh timer (D-02/SC3 clause 2)
3. **Task 2 suite** — `f899393` test(02-01): extend race suite to thirteen cases — reentrancy both flavors (D-05a/D-05b), replay both outcomes (D-03), D-08 inline collision, canceled drop (A2)

`git log d2ec18af..HEAD` = exactly 7 linear commits (4 Phase 1 + 3 Phase 2). Task 3 modifies no repository file (evidence only). Superproject/thirdparty gitlinks intentionally left dirty-uncommitted (Phase 4 repins).

## Files Created/Modified

- `thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp` — public `bool IsCompleted() const` (TOCTOU-by-design @brief; definition locks `mutable mutex_`), private `std::optional<libp2p::outcome::result<std::string>> terminalResult_` after `completed_`, updated `@mutex` contract (guards terminalResult_; AddCallback now called outside the outer lock; mutable rationale)
- `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` — seams 1/1b/2/3 + `IsCompleted` definition; D-04 retention comments at both map sites; timer-capture comment reworded for retention reality
- `thirdparty/ipfs-bitswap-cpp/test/bitswap_request_timer_race_test.cpp` — 6 new cases + harness-contract case list naming all 13
- No CMake changes; no enum changes; no new includes in the header

## Decisions Made

None — followed plan as specified. All planner resolutions (A2 silent drop, A4 hang-triage, baseline evidence scope) executed as codified.

## Deviations from Plan

### Auto-fixed Issues

**1. Stale comment referenced the deleted erase (gate hygiene)**
- **Found during:** Task 1 verify
- **Issue:** the Phase 1 timer-capture rationale comment named `requestContexts_.erase` — an operation that no longer exists under D-04, and a false positive on the plan's `git grep requestContexts_.erase` fails-ANY-line gate
- **Fix:** reworded to retention-accurate wording; folded into the feat commit via amend of my own just-created unpushed commit (chain stays 7-linear, unpushed)

**2. WSL ASan compile/link line — research A1 [ASSUMED] resolved empirically (primary route succeeded; fallback not needed)**
- Boost 1.85 headers live at `build/Linux/Debug/x86_64/boost/build/include` (NOT thirdparty/boost, which is a partial checkout, and NOT system 1.74, which is incompatible)
- Required `-DSPDLOG_FMT_EXTERNAL -DSPDLOG_COMPILED_LIB` (the prebuilt spdlog uses external fmt)
- protobuf archive is Debug-suffixed `libprotobufd.a`; GTest include at `$B/GTest/include`
- The installed `libsoralog.a` is a 3 KB stub — linked the real soralog `.o` set from the build tree instead, plus `libyaml-cppd.a`
- All archives wrapped in `-Wl,--start-group … --end-group` for absl's cyclic cross-references

### Notes for the Verifier

- Safe-resume gate context: four `fix(02-01)` commits (C-1..C-4, an earlier milestone's numbering) exist in submodule history BELOW base d2ec18af — ancestors of the base, not orphan work for this plan
- Windows suite remains the primary acceptance evidence (D-07); the WSL run is supplementary and succeeded on the primary direct-compile route

## Verification Results

| Gate | Result |
|------|--------|
| Full race suite (Task 1, 8 tests; all 7 Phase 1 unweakened) | `[  PASSED  ] 8 tests.` |
| Filtered tracer | `[  PASSED  ] 1 test.` |
| bitswap_server_client_test (restructured outer integration) | `[COMPLETE] ✅ All tests passed!` |
| Full suite run 1 / run 2 (determinism, SC4) | 13/13 both, identical counts |
| ctest -R bitswap_request_timer_race_test | 100% tests passed |
| sleep_for/std::thread source check | no matches |
| WSL ASan full suite (D-07) | 13/13, `ASAN_EXIT:0`, 0 sanitizer patterns |
| `git grep requestContexts_.erase HEAD -- src/bitswap.cpp` | empty |
| `mutable std::mutex` count in src/bitswap.hpp | 8 (7 Bitswap-tier + context mutex_) |
| terminalResult_ / IsCompleted / D-04 / completed_ / REQUEST_TIMEOUT / 13 TEST / 6 case names at HEAD | all greppable |
| `git log d2ec18af..HEAD` | exactly 7 commits, linear |
| Remote branch `dev_timer_correctness` | does not exist (never pushed) |
| `git diff --stat e2dc906..HEAD` | only the 3 plan files |
| Cumulative diff vs d2ec18af contains content-path function hunks (D-09/D-10) | none |
| Submodule tree | clean |

## Self-Check: PASSED

All plan-level `<verification>` commands and every task's `<acceptance_criteria>` re-checked at HEAD `f899393`.
