---
phase: 04-repin-cross-repo-verification
plan: 01
subsystem: infra
tags: [git, submodules, bitswap, gtest, baseline, msbuild]

requires:
  - phase: 03-gossipsub-resource-bounds
    provides: fix HEADs (libp2p a54f5c4, ipfs-pubsub 5c6653c) + the rollback residue characterization this plan reconciles
provides:
  - Clean ipfs-bitswap-cpp worktree byte-exact at f899393 (D-05 restore proven by 13-case suite from freshly rebuilt standalone binary)
  - Freshly rebuilt standalone bitswap race-test exe (the binary 04-02's D-12 TEST-01 pin-time re-run consumes)
  - D-11 pre-repin baseline: four per-case logs from Sep-15 pre-fix exes + fully-green pre-existing-red ledger (zero reds)
affects: [04-02 (pin chain), 04-03 (repinned comparison)]

actuals:
  tokens: 2400   # chars/4 over d05-rollback-evidence.txt + baseline-summary.md; the four baseline-*.log files are ~4.2MB raw gtest capture artifacts, excluded
  tasks: 2
  commits: 0     # by plan design - no commits in 04-01; evidence files commit at 04-03's evidence step

tech-stack:
  added: []
  patterns: [diff-vs-prior-HEAD emptiness gate before worktree restore, ASCII-decode byte-grep tripwire on rebuilt binaries, Sep-15-exe baseline without rebuild]

key-files:
  created:
    - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/d05-rollback-evidence.txt
    - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/baseline-pubsub_counts_test.log
    - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/baseline-globaldb_integration_test.log
    - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/baseline-pubsub_graphsync_test.log
    - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/baseline-transaction_sync_test.log
    - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/baseline-summary.md
  modified: []   # src/bitswap.{cpp,hpp}, test/bitswap_request_timer_race_test.cpp were RESTORED to committed f899393 content (worktree-only; net zero diff)

key-decisions:
  - "D-05 restore executed without a checkpoint: the diff-vs-e2dc906 emptiness gate proved zero novel content, making attribution (actor undetermined) non-blocking per RESEARCH OQ1 [RESOLVED]"
  - "A3/OQ3 contingency not triggered: transaction_sync_test ran to completion, so genius_node_bootstrap_reconnect_test never enters the focus set (no fifth baseline log)"

patterns-established:
  - "Restore-safety gate: git diff <prior-HEAD> --stat over the dirty paths must be EMPTY before any git restore - proves the rollback is fully explained by committed history"
  - "Contamination tripwire: after any standalone-tree rebuild, ASCII-decode byte-grep the exe for Phase-2 case names AND require the literal 'Running 13 tests' count - never trust the exe name"

requirements-completed: [INTG-01, INTG-03]

coverage:
  - id: D1
    description: "D-05 bitswap rollback reconciliation - worktree restored byte-exact to f899393 with bounded evidence, 13-case race suite green from freshly rebuilt standalone binary, Phase-2 case-name byte-greps True"
    requirement: INTG-01
    verification:
      - kind: unit
        ref: "thirdparty/build/Windows/Debug/ipfs-bitswap-cpp-test/test_bin/Debug/bitswap_request_timer_race_test.exe -> [==========] Running 13 tests / [  PASSED  ] 13 tests."
        status: pass
      - kind: other
        ref: "git status --short empty; HEAD f899393 on dev_timer_correctness; ASCII byte-grep ReentrantCancelOwnRequestNoDeadlock=True, LateRegistrationOnTimedOutReplaysRequestTimeout=True"
        status: pass
  - id: D2
    description: "D-11 pre-repin baseline - four Sep-15 focus exes run as-is with per-case logs and pre-existing-red ledger; baseline fully green (17/17 cases, zero reds)"
    requirement: INTG-03
    verification:
      - kind: integration
        ref: "baseline-pubsub_counts_test.log (1/1), baseline-globaldb_integration_test.log (9/9), baseline-pubsub_graphsync_test.log (1/1), baseline-transaction_sync_test.log (6/6) - all exit 0, zero [  FAILED  ] lines"
        status: pass

duration: 12min
completed: 2026-10-14
status: complete
---

# Phase 4 Plan 04-01: D-05 Rollback Reconciliation + D-11 Pre-Repin Baseline

**The bitswap worktree is byte-exact at f899393 (13/13 race cases green from a freshly rebuilt, uncontaminated standalone binary) and the four Sep-15 focus exes produced a fully green pre-repin baseline - zero pre-existing reds, so any repin-time failure is by definition new.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-10-14T22:00Z (approx; session-local 18:00)
- **Completed:** 2026-10-14 (session-local 18:12)
- **Tasks:** 2/2
- **Files created:** 6 evidence files (phase dir); 3 submodule files restored to committed content (net-zero diff)

## Accomplishments

- **D-05 closed:** bounded rollback investigation (status/diff-stat/stash/reflog/mtimes + the decisive diff-vs-e2dc906 emptiness gate) recorded in `d05-rollback-evidence.txt`; `git restore --source=f899393` left the worktree clean (0 status lines) with no commit; the standalone race tree rebuilt with real compile output (6 .cpp compiles incl. `bitswap.cpp`); the rebuilt exe reported the literal `[==========] Running 13 tests` / `[  PASSED  ] 13 tests.` lines; both Phase-2 case-name byte-greps returned True (contamination tripwire green).
- **D-11 baseline captured:** all four Sep-15 exes ran to completion from `SuperGenius\build\Windows\Debug` with Tee-Object per-case capture - pubsub_counts 1/1, globaldb_integration 9/9, pubsub_graphsync 1/1, transaction_sync 6/6, all exit 0, zero `^\[  FAILED  \]` lines anywhere; `baseline-summary.md` carries exe Name/Length/LastWriteTime provenance, the deployed-lib no-rebuild assertion (p2p_gossip Oct 13 18:45 / ipfs-pubsub Oct 2 / ipfs-bitswap-cpp Sep 29), and the per-target ledger.
- **A3 contingency not triggered:** transaction_sync_test completed, so no fifth substitute target; post-run exe mtimes unchanged (Sep 15).

## Task Commits

None - by plan design ("No git commit or push is issued in this plan"). The evidence files
and this SUMMARY are committed at 04-03's evidence step per the plan's artifact note.
The bitswap restore is worktree-only; f899393 already contains the content.

## Files Created/Modified

- `d05-rollback-evidence.txt` - D-05 bounded investigation transcript + safety-gate result + conclusion (actor undetermined, zero novel content)
- `baseline-pubsub_counts_test.log` (17 KB), `baseline-globaldb_integration_test.log` (389 KB), `baseline-pubsub_graphsync_test.log` (768 KB), `baseline-transaction_sync_test.log` (3.1 MB) - raw per-case gtest transcripts from the Sep-15 pre-fix exes
- `baseline-summary.md` - provenance, no-rebuild assertion, per-target pre-existing-red ledger (zero reds)
- `thirdparty/ipfs-bitswap-cpp/{src/bitswap.cpp, src/bitswap.hpp, test/bitswap_request_timer_race_test.cpp}` - restored to committed f899393 content (worktree-only, no commit; status clean)
- Build-tree (not source, never committed): standalone `bitswap_request_timer_race_test.exe` rebuilt 2026-10-14 18:04 from restored source

## Decisions Made

- Restore proceeded without operator checkpoint: the e2dc906 emptiness gate is the D-05 safety proof and passed; attribution intentionally not required (RESEARCH OQ1 disposition).
- No fifth baseline target: contingency rule evaluated (transaction_sync completed) and rejected.

## Deviations from Plan

None - plan executed exactly as written. Every precondition, expected output shape
(3 files / 32 insertions / 463 deletions; mtimes 10/13/2026 1:36 PM; empty stash; reflog
tail Oct-13 commits), and acceptance criterion matched the recorded found-state exactly.

## Issues Encountered

None. (Notable absence: the race-test exe did NOT exhibit the known ipfs-pubsub-test
post-summary exit-hang; all runs returned promptly.)

## User Setup Required

None.

## Next Phase Readiness

- 04-02 can proceed: bitswap worktree clean at f899393; the rebuilt standalone exe is the
  D-12 TEST-01 input; pin chain (dev_ipfs_p0 from 1cbf85a, three gitlinks) is unblocked.
- 04-03 receives a maximally strict comparison bar: baseline fully green means the repinned
  runs must also be fully green (zero new failures == zero failures).

---
*Phase: 04-repin-cross-repo-verification - Plan 01*
*Completed: 2026-10-14*
