---
phase: 04-repin-cross-repo-verification
plan: 02
subsystem: infra
tags: [git, submodules, gitlink, pin-chain, content-probes, gossipsub, bitswap]

requires:
  - phase: 04-repin-cross-repo-verification (plan 01)
    provides: clean bitswap worktree at f899393 + rebuilt standalone TEST-01 binary + the D-11 baseline that gates 04-03's rebuild
provides:
  - thirdparty branch dev_ipfs_p0 (from develop@1cbf85a) with the single three-gitlink pin commit 97b648a (never pushed)
  - Root commit 2e46a2f on dev_persisprocresults bumping the thirdparty gitlink to 97b648a (never pushed)
  - content-probes.txt - the SHA->marker D-04 evidence (six probes, all non-zero) plus D-12 pin-time greens and never-push proof
affects: [04-03 (rebuild + comparison)]

actuals:
  tokens: 1300   # chars/4 over content-probes.txt + this summary; git commits carry ~0 new content bytes (gitlink-only diffs)
  tasks: 2
  commits: 2     # thirdparty 97b648a (chore(pins)), root 2e46a2f (chore(thirdparty))

tech-stack:
  added: []
  patterns: [lineage assertion before pin (merge-base --is-ancestor), SHA-level content probes as the only trust anchor, surgical gitlink staging]

key-files:
  created:
    - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/content-probes.txt
  modified:
    - thirdparty (gitlink 1cbf85a -> 97b648a via root commit 2e46a2f)
    - thirdparty/{ipfs-bitswap-cpp,libp2p,ipfs-pubsub} (gitlinks via thirdparty commit 97b648a)

key-decisions:
  - "Trust granted exclusively by content probes at exact SHAs (D-04); branch names recorded as provenance only - INTG-02's degenerate rule (zero-match = UNVERIFIED) had no occasion to fire: all six probes matched expected counts exactly"
  - "dev_ipfs_p0 cut from develop@1cbf85a per D-01; develop left untouched at 1cbf85a for reviewed merge later"

patterns-established:
  - "Pin-landing discipline: lineage assertions FIRST (merge-base --is-ancestor x3), then integration branch, then surgical staging by exact path, then post-commit --stat gate (exactly N gitlink lines, nothing else)"

requirements-completed: [INTG-01, INTG-02]

coverage:
  - id: D1
    description: "Pin chain landed locally - three lineage-verified gitlink bumps on dev_ipfs_p0 (97b648a) and the root gitlink bump (2e46a2f); develop untouched; nothing pushed"
    requirement: INTG-01
    verification:
      - kind: other
        ref: "merge-base --is-ancestor d2ec18af f899393 / 28f6a629 a54f5c4 / b6eb6268 5c6653c all exit 0; git show --stat 97b648a = exactly 3 gitlink lines; git ls-tree HEAD thirdparty = 97b648a; branch -r shows no dev_ipfs_p0"
        status: pass
  - id: D2
    description: "Content-probed verification - six SHA-level probes all non-zero with expected counts; TEST-01 13/13 and TEST-02 exact Phase-03 final state at pin time"
    requirement: INTG-02
    verification:
      - kind: unit
        ref: "content-probes.txt: terminalResult_ 2+2, TEST( RequestContextRaceTest 13, gossip knob 1, violation seam 5 files, BlockPeer 8, kSustainedOverflowClosesToBlock 3; bitswap [  PASSED  ] 13 tests; pubsub 17 ran/16 passed/1 pre-existing fail/1 disabled"
        status: pass

duration: 10min
completed: 2026-10-14
status: complete
---

# Phase 4 Plan 04-02: Content-Probed Pin Chain

**The three P0 fix SHAs are now the pinned tree - lineage-verified, content-proven at the exact SHAs, suite-green at pin time, and existing only in local git (dev_ipfs_p0 @ 97b648a -> root 2e46a2f).**

## Performance

- **Duration:** ~10 min
- **Tasks:** 2/2
- **Commits:** 2 (thirdparty + root), both local-only

## Accomplishments

- **Lineage gate 3/3:** every pinned SHA proven a linear descendant of its recorded integrated gitlink before any commit (`merge-base --is-ancestor` exit 0 x3).
- **Pin commits landed surgically:** `dev_ipfs_p0` cut from `develop@1cbf85a`; commit `97b648a` stages exactly the three gitlinks (`ipfs-bitswap-cpp | 2 +-`, `libp2p | 2 +-`, `ipfs-pubsub | 2 +-` - nothing else); root commit `2e46a2f` on `dev_persisprocresults` touches only the thirdparty gitlink. Known drift (`gnus_upnp` modified, `MNN`/`fmt` untracked, libp2p untracked `Testing/`/`.planning/research/.cache/`) untouched and uncommitted.
- **Six content probes all MATCH** (see `content-probes.txt`): `terminalResult_` 2+2, race cases 13, `max_remote_subscriptions_per_peer` 1, violation seam exactly 5 files (`connectivity.hpp`, `gossip_core.{cpp,hpp}`, `stream.{cpp,hpp}`), `BlockPeer` 8, `kSustainedOverflowClosesToBlock` 3. No degenerate zero-results.
- **D-12 pin-time greens:** TEST-01 = 13/13 PASSED (on 04-01's rebuilt binary); TEST-02 = 17 ran / 16 passed / exactly `MutipleGossipSubObjectsOnSingleChannel` failed (pre-existing, untouched) / 1 disabled, all 5 `GossipPubSubBoundsTest` cases green.
- **Never-push proof recorded:** no `dev_ipfs_p0` on any thirdparty remote, empty upstream tracking, root remote-branch list unchanged. **No push command was issued by this plan.**
- **Remote-state note (operator-acknowledged):** `origin/dev_persisprocresults` advanced from `e632cca` (Oct-7) to `2e46a2f` at 18:22:16 local, ~9 min after the root commit - pushed by the operator's own action (VS Code sync), confirmed in-session during execute-phase 4. Not a plan action; thirdparty/fix branches remain remote-absent.

## Task Commits

1. **Task 1: pin-chain commits** - `97b648a` (thirdparty, chore(pins)) + `2e46a2f` (root, chore(thirdparty))
2. **Task 2: probes + re-runs + never-push proof** - evidence-only (`content-probes.txt`; no commit by design - commits with the docs at 04-03's evidence step)

## Files Created/Modified

- `thirdparty` gitlink: `1cbf85a` -> `97b648a` (root commit `2e46a2f`)
- `thirdparty/ipfs-bitswap-cpp` gitlink: `d2ec18af` -> `f899393` (commit `97b648a`)
- `thirdparty/libp2p` gitlink: `28f6a629` -> `a54f5c4` (commit `97b648a`)
- `thirdparty/ipfs-pubsub` gitlink: `b6eb6268` -> `5c6653c` (commit `97b648a`)
- `content-probes.txt` - verbatim D-04/D-12/never-push transcript

## Decisions Made

None beyond plan text - executed exactly as specified.

## Deviations from Plan

None. (TEST-02's known post-summary exit-hang occurred as documented in deferred item 3;
summary lines were captured from the full transcript before the terminal was killed - the
Phase-3-proven recovery, recorded inside content-probes.txt.)

## Issues Encountered

None blocking. The ipfs-pubsub-test post-summary exit-hang recurred (expected, documented
deferred item 3); handled without data loss.

## User Setup Required

None.

## Next Phase Readiness

- 04-03 unblocked: pins are landed and content-proven; the D-06 ordered rebuild
  (libp2p -> bitswap -> pubsub, INSTALL x3, hash audits) can start against the pinned
  worktree state, followed by the 5-project SuperGenius clean rebuild and the D-11
  comparison vs the fully-green baseline from 04-01.

---
*Phase: 04-repin-cross-repo-verification - Plan 02*
*Completed: 2026-10-14*
