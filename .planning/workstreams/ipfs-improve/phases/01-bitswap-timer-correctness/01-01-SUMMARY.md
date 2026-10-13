---
phase: 01-bitswap-timer-correctness
plan: 01
subsystem: testing
tags: [boost-asio, deadline-timer, race-conditions, gtest, ipfs-bitswap, windows-msvc]

# Dependency graph
requires:
  - phase: research
    provides: verified Windows configure recipe, C-5/C-7 porting template, pinned SHA d2ec18af
provides:
  - Timer-correct BitswapRequestContext (ec guard, completion flag, explicit cancel, out-of-lock dispatch, REQUEST_TIMEOUT mapping) on branch dev_timer_correctness (4 local commits from d2ec18af)
  - Additive consumer-initiated Cancel() retiring a request with zero callbacks
  - Deterministic 7-case GTest race harness (single-threaded io_context, injected durations, run_one stepping, zero sleeps) ready for Phase 2's TEST-01 extension
  - Phase 4 content-probe markers (completed_, REQUEST_TIMEOUT) greppable in src/bitswap.cpp at HEAD e2dc906
affects: [02-bitswap-reentrancy, 04-repin-verify, bitswap-consumers]

actuals:
  tokens: 5000
  tasks: 3
  commits: 4

tech-stack:
  added: []
  patterns:
    - "ec-guard + flag-under-mutex + cancel + move-out-dispatch (C-5/C-7 port) on timer contexts"
    - "Deterministic race-ordering tests: injected past/long durations + run_one()/poll() stepping, no sleeps, no threads"

key-files:
  created:
    - thirdparty/ipfs-bitswap-cpp/test/bitswap_request_timer_race_test.cpp
  modified:
    - thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp
    - thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp
    - thirdparty/ipfs-bitswap-cpp/test/CMakeLists.txt

key-decisions:
  - "Task 1 (blocking-human) resolved by operator-directed W:\\ubuntu-22 ext4.vhdx fstrim + sparse-VHD conversion — 650 GiB trimmed, 4.855 GB freed on W:; conventional tree $B = thirdparty/build/Windows/Debug/ipfs-bitswap-cpp-test chosen over the C: probe"
  - "RESEARCH A1+A3 resolved empirically against the platform: poll()-family stepping CANNOT deterministically extract an expired deadline_timer on MSVC 19.44/Boost 1.85 (clock-tick dependent; -1/-100/-1000 ms drives fired in only ~50% of bounded poll rounds); run_one() fires a genuinely expired -1 ms deadline on the first call, every run — substituted per the plan's stepping-discretion clause"
  - "Ordering 2 on this platform degrades to completion-first + aborted-handler-second (ec-guard drop); the flag-drops-a-late-terminal half of BSTP-02 is proven deterministically by ordering 4's and ConsumerCancel's late HandleResponse — documented in the test's doc comment, assertions unweakened"
  - "Fix branch named dev_timer_correctness (dev_* convention), cut from d2ec18af, never rebased, local only — no gitlink commits in thirdparty or GeniusNetwork (Phase 4's repin)"

patterns-established:
  - "Deterministic single-threaded timer-race testing in this workspace: injected durations + run_one/poll stepping (no codebase precedent existed; AsyncIOManager's pollUntil is the documented anti-example)"
  - "GTest registration via addtest() + explicit target_link_libraries of the full sibling link set + GSL include — the minimal 4-target list does not link (unresolved ContentIdentifier symbols)"

requirements-completed: [BSTP-01, BSTP-02, BSTP-03]

coverage:
  - id: D1
    description: "Canceled timers never fire the failure path; every request yields exactly one terminal result (BSTP-01, BSTP-02)"
    requirement: BSTP-01
    verification:
      - kind: unit
        ref: "bitswap_request_timer_race_test.cpp#RequestContextRaceTest.CancelBeforeExpiryYieldsExactlyOneSuccess (7/7 x5 runs)"
        status: pass
      - kind: unit
        ref: "bitswap_request_timer_race_test.cpp#RequestContextRaceTest.ExpiryDequeuedThenCompletionYieldsSingleResult"
        status: pass
      - kind: unit
        ref: "bitswap_request_timer_race_test.cpp#RequestContextRaceTest.ResponseThenCanceledTimerFiresNoFailure"
        status: pass
    human_judgment: false
  - id: D2
    description: "Error semantics: genuine timeout delivers exactly one REQUEST_TIMEOUT failure; consumer cancel and success deliver no error callback (BSTP-03, D-06)"
    requirement: BSTP-03
    verification:
      - kind: unit
        ref: "bitswap_request_timer_race_test.cpp#RequestContextRaceTest.GenuineTimeoutThenLateResponseSingleTimeout (asserts error VALUE == 3)"
        status: pass
      - kind: unit
        ref: "bitswap_request_timer_race_test.cpp#RequestContextRaceTest.ConsumerCancelProducesNoCallback"
        status: pass
    human_judgment: false
  - id: D3
    description: "Deterministic race harness (SC4/D-03): single-threaded, injected durations, zero sleeps/threads; dispatch-order and zero-callback shapes covered (D-04 evidence)"
    verification:
      - kind: unit
        ref: "bitswap_request_timer_race_test.cpp#RequestContextRaceTest.MultipleCallbacksDispatchedInRegistrationOrder"
        status: pass
      - kind: unit
        ref: "bitswap_request_timer_race_test.cpp#RequestContextRaceTest.TerminalTransitionWithZeroCallbacksIsSafe"
        status: pass
      - kind: unit
        ref: "ctest -C Debug -R bitswap_request_timer_race_test: 100% passed; suite x5 identical counts"
        status: pass
    human_judgment: false
  - id: D4
    description: "Production-path regression unbroken on the fix branch"
    verification:
      - kind: integration
        ref: "bitswap_server_client_test.exe: exit 0, '[COMPLETE] All tests passed!' marker present"
        status: pass
    human_judgment: false

duration: 80min
completed: 2026-10-12
status: complete
---

# Phase 01 Plan 01: Bitswap Timer Correctness Summary

**Ported the proven ContentRequestContext timer-correctness shape onto BitswapRequestContext — a canceled timer is now never a timeout, every request yields exactly one terminal result — proven by a deterministic 7-case race suite on a single-threaded io_context with zero sleeps.**

## Accomplishments

1. **Production port** (commit 7fe1450): ec-guard in the async_wait lambda (BSTP-01, d2ec18af's shared_from_this capture preserved), completion flag `completed_` checked-and-set under `mutex_` with explicit `responseTimer_.cancel()` disarm and wholesale callback move-out, dispatch only after lock release (BSTP-02/D-04), genuine-timeout mapping switched to `BitswapError::REQUEST_TIMEOUT` (D-06), injectable duration via defaulted ctor parameter leaving the messageSent call site unchanged (D-01).
2. **Consumer Cancel()** (commit 3463c14): additive public method retiring a request with zero callbacks — the under-lock half of HandleResponse with no invocation (BSTP-03 consumer-cancel clause).
3. **Deterministic race suite** (commits 0fcd1b2, e2dc906): 7 GTest cases — four orderings, consumer cancel, multi-callback registration order, zero-callback terminal — all green through 5 consecutive full-suite runs and ctest; `bitswap_server_client_test` regression green on the fix branch.
4. **Task 1 disk gate resolved**: operator-directed fstrim of the 371.52 GB `W:\ubuntu-22\ext4.vhdx` (650 GiB trimmed inside the distro; sparse-VHD conversion) reclaimed 4.855 GB on W:, unblocking the conventional build tree.

## Performance

- **Duration:** ~80 min
- **Commits:** 4 (all local, submodule `thirdparty/ipfs-bitswap-cpp`, branch `dev_timer_correctness` from `d2ec18af`: 7fe1450, 0fcd1b2, 3463c14, e2dc906)

## Key learnings

- **poll() cannot deterministically extract expired deadline_timers on Windows/Boost 1.85** — extraction is gated on the ~15.6 ms clock tick; a microsecond-scale poll loop usually exhausts first. `run_one()` computes its wait from the timer queue and fires a past deadline on the first call, every time (measured across 10 iterations x 3 process runs). This invalidates RESEARCH A1's same-batch FIFO assumption as a *deterministic* mechanism and is documented in the ordering-2 doc comment.
- The plan's minimal 4-target link list for the race test does not link — the sibling tests' full p2p::* family + GSL include are required (transitive propagation is incomplete in this standalone tree).

## Deviations

1. **CMake wiring (Task 2 step 4)**: added `target_include_directories(... ${GSL_INCLUDE_DIR})` and extended `target_link_libraries` to the full sibling set (spdlog, Boost.DI, seven p2p::* targets, ipfs-lite-cpp::ipld_node, WIN_CRYPT_LIBRARY, Boost_LIBRARIES) — plan's literal 4-target list produced C1083 (gsl/span) and LNK2019 (ContentIdentifier symbols). Sibling-pattern-conformant.
2. **Stepping mechanics (A1/A3)**: `run_one()` substituted for poll() in the two must-expire drives per the plan's stepping-discretion clause, after empirical measurement showed poll() extraction is clock-tick dependent. Ordering 2's late handler arrives aborted (ec-guard drop) rather than success-ec (flag drop) on this platform; the flag-drop half of BSTP-02 is proven deterministically by ordering 4's and ConsumerCancel's late-HandleResponse phases. Assertions unweakened; doc comments carry the full resolution.
3. **No pushes, no gitlink commits** — per plan prohibitions; superproject intentionally left with dirty (uncommitted) gitlinks for Phase 4's repin.

## Self-Check: PASSED

- All 4 key files exist on disk; 4 commits on d2ec18af..HEAD; 7/7 tests x5 runs + ctest 100%; regression marker present; content probes (completed_, REQUEST_TIMEOUT) greppable at HEAD; zero sleep_for / std::thread in the test file; src diff confined to BitswapRequestContext (D-05).
