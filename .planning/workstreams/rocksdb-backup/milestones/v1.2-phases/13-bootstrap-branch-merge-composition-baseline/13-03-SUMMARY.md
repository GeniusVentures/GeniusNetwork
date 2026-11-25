# 13-03 SUMMARY — Merged-Line Proof: SC2 Pair + SC3 Evidence (RECOVER-01)

**Phase:** 13 Bootstrap Branch Merge & Composition Baseline · **Plan:** 13-03 · **Wave:** 3
**Status:** COMPLETE · **Date:** 2026-11-16

## What Was Built

1. **SC2 post-merge leg (Task 1)** — full suite on the merge commit `2af184fa1` in the same Windows Release tree/config as the pre leg (serial, matched scope; WARP ABSENT both legs): **167/167, 100% passed, ctest exit 0** (wall-clock **36m13s** / 2172.70s — Phase 19 planning input). Tier-1 fail-closed lane: **12/12, exit 0**. Subset verify: **`subset-ok`** — post failure set EMPTY vs the composed pre denominator (0 failures at `4ae8a9a4e`). **VERDICT: ZERO REGRESSIONS.**
2. **SC3 items 1–3 (Task 2)** — filtered lane 6/6 (fallback 21 cases, node_startup, prune_eligibility, crdt_test, gc, gc_retrievability); walk cases named-green via binary (`BootstrapRecoverySettingsAreLoadedStrictlyFromSgnsConfig` 1026ms, `ForcedBootstrapWalkRunsBeforeBlockchainIsReady` 8131ms); GATE-03 quote-safe grep **0 matches**; 4-term source check **16 matches** (≥4); `EraseSurfaceGateTest.SealKeyHasNoProductionHome` **[ OK ]** 36ms.
3. **SC3 item 4 / D-12 (Task 3)** — escalated-deferred per user ruling (see Deviation 2): structurally unobservable via logs this phase, findings proven from source and recorded in the checklist row with compensating evidence.

## SC2 Numbers (D-08: here + commit messages only)

| Leg | Tree/SHA | Result | Wall-clock | WARP |
|-----|----------|--------|-----------|------|
| Pre (composed) | `4ae8a9a4e` (166 carried @ `7961ec264` + fixed resurrection green) | 0 failures; Tier-1 12/12 exit 0 | 33m34s (the `7961ec264` run) | ABSENT |
| Post | `2af184fa1` (merge) | **167/167 passed, 0 failures**; Tier-1 12/12 exit 0 | **36m13s** | ABSENT |

Shared exclusions: **NONE** (the `requires_foundry` family — 9 tests — passed on both legs). Isolated re-runs needed: **NONE**. Subset gate: post (∅) ⊆ pre (∅) — `subset-ok` printed.

## Files Modified

- `.planning/.../13-MERGE-CHECKLIST.md` — §7.3 SC2 verdict + SC3 rows 1–4 amended as-run (row 4 = escalated-deferred record)
- No SuperGenius source/test/build changes in this plan (D-09/D-10 held: nothing new authored, nothing new in CI)

## Commits

| Repo | SHA | Message |
|------|-----|---------|
| root | (this commit) | docs(13-03): SC2 zero-regression verdict + SC3 evidence (item 4 escalated-deferred to Phase 15) |

## Deviations from Plan

1. **[Rule 2 — verify-target gap in plan] `crdt_erase_test` is not a ctest target.** The GATE-03 runtime half (`EraseSurfaceGateTest.SealKeyHasNoProductionHome`) lives in `crdt_test` (`test/src/crdt/CMakeLists.txt` compiles `crdt_erase_test.cpp` into `crdt_test`). Fix: filtered lane used `-R crdt_test`; the named case additionally run directly via `--gtest_filter` (36ms, OK) and `crdt_test` green in both the post full-leg (30.05s) and the filtered lane. Evidence intact; plan regex corrected in execution.
2. **[Rule 4 — user ruling] D-12 log observation escalated-deferred to Phase 15.** Primary path executed as planned (Release `D01_S3TierHitEndToEnd` driven, output captured to `%TEMP%\p13-d12-cold-read.log`) — 0 cold-read lines. Source-level proof of structural unobservability followed: both lines are `logger_->debug` on the `"GraphsyncDAGSyncer"` spdlog logger; `base::createLogger` never sets a level (spdlog default `info` filters them in ALL build types); vendored spdlog 1.12.0 has no env-var level hook; no existing test pairs debug activation with a cold S3 miss (`crdt_datastore_test` raises `CrdtDatastore` only; `GeniusNode` SGNS_DEBUGLOGS raises `GraphsyncDAGSyncer`→debug but node scenarios have no cold miss). The in-flight Debug rebuild was stopped as structurally futile (zombie compilers cleared). User ruling (a): record the gap + compensating evidence (seam cold-first by construction, `:750`–`:806` source-cited; `D01` + `SC4_RehydrateSilence_BytesOnlyNoMarkers` green — cold chain serves with zero peer involvement); Phase 15 owns the deterministic enforcement + observation harness. A zero-observation was NOT recorded as a pass.
3. **[Evidence-chain note] Pre-leg `%TEMP%` log absent.** The cancelled pre-leg re-run's `Remove-Item` fired before cancellation, so `p13-sc2-pre-full.log` no longer exists on disk. Pre-leg numbers are carried by the committed 13-01 SUMMARY/checklist record per the user-approved composed-denominator ruling; the post log exists and was parsed for the subset verify.

**Total deviations:** 3 (1 auto-fixed, 1 user-ruled deferral, 1 recorded evidence note). **Impact:** SC2 verdict unaffected (empty post failure set); SC3 items 1–3 fully evidenced; item 4 honestly deferred with proven findings.

## Verification Results

- Plan verify block 1 (Tier-1 fail-closed): exit 0, 12/12
- Plan verify block 2 (subset comparison): `post-failed-names=0 pre-failed-names=0`, `subset-ok`
- Plan verify block 3 (post log summary): `100% tests passed, 0 tests failed out of 167`
- Plan verify block 4 (filtered suites incl. corrected crdt_test): exit 0, 6/6
- Plan verify block 5 (GATE-03 grep): `grep-matches=0` (quote-safe piped form)
- Plan verify block 6 (4-term source check): `term-count=16`
- D-12 verify blocks: intentionally not satisfiable this phase — escalation recorded instead (user ruling); no pass was manufactured

## Self-Check: PASSED
