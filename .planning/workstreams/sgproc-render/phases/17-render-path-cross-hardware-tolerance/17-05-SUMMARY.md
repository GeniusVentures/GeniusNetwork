---
phase: 17-render-path-cross-hardware-tolerance
plan: 05
subsystem: testing
tags: [capture_harness, capture_diff, cross-hardware, vulkan, render]

requires:
  - phase: 17-01, 17-02, 17-04
    provides: three fully-implemented render fixtures (lighting, blending, texturing) that this plan captured cross-machine data for
provides:
  - Round 1's six-file .cap capture set (3 fixtures x 2 machines) for lighting/blending/texturing
  - Three capture_diff JSON reports (Mac vs Windows) for the same three fixtures
  - 17-CAPTURE-RESULTS-ROUND1.md documenting each fixture's real divergence numbers honestly
affects: [17-06, 17-07 (tolerance derivation waves that consume this plan's raw maxAbsDelta numbers)]

tech-stack:
  added: []
  patterns: [capture_harness/capture_diff two-machine empirical capture cycle (Phase 10/11 precedent, reused as-is)]

key-files:
  created:
    - .planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/17-CAPTURE-RESULTS-ROUND1.md
    - .planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/captures/diff-render-lighting.json
    - .planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/captures/diff-render-blending.json
    - .planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/captures/diff-render-texturing.json
  modified: []

key-decisions:
  - "Blending is the fixture that confirmed real cross-hardware divergence this round (maxAbsDelta=1, contentHashMatch=false); lighting and texturing both measured zero divergence, honestly flagged per D-08 rather than reinterpreted as a passing/generalizing result."
  - "Texturing's zero-divergence result is annotated with the known caveat from 17-04's SUMMARY: the schema's per-texture filter field is not yet functionally wired into UploadTexture() (always NEAREST), so this round's zero result cannot be read as proof that texturing/filtering in general is byte-identical cross-hardware."
  - "Did not run requirements.mark-complete for RENDTOL-01/RENDTOL-02 -- both were already (prematurely) marked Complete in REQUIREMENTS.md after Plan 17-02, a known-tracked STATE.md item flagged for revisit at phase close, not something this plan re-triggers or fixes."

requirements-completed: []

coverage:
  - id: D1
    description: "Round 1's six-file .cap capture set exists for all three fixtures on both machines of Phase 11's dataset (Task 2 checkpoint verified: 6 files present, no capture_harness instability reported)"
    requirement: "RENDTOL-01"
    verification:
      - kind: manual_procedural
        ref: "User's 'captured' resume-signal + orchestrator file-existence check of all 6 xhw-render-*.cap files"
        status: pass
    human_judgment: true
    rationale: "Whether both machines' capture_harness binaries were rebuilt from the current commit before capturing is not independently derivable from .cap bytes alone -- mirrors 13-04's accepted resume-signal precedent (STATE.md decision log)."
  - id: D2
    description: "capture_diff --element-type uint8 run for all three Mac-vs-Windows fixture pairs; results documented honestly in 17-CAPTURE-RESULTS-ROUND1.md with no averaging/rounding/favorable reinterpretation"
    requirement: "RENDTOL-01"
    verification:
      - kind: other
        ref: "capture_diff.exe --a <mac.cap> --b <windows.cap> --element-type uint8 --json-output captures/diff-render-<technique>.json (run 3x, JSON reports committed verbatim into 17-CAPTURE-RESULTS-ROUND1.md)"
        status: pass
    human_judgment: false

duration: 25min
completed: 2026-08-20
status: complete
---

# Phase 17 Plan 05: Round 1 Cross-Hardware Capture and Diff Summary

**Round 1 empirical capture confirms real cross-hardware divergence in blending (maxAbsDelta=1) while lighting and texturing both measured zero divergence, all reported honestly with no favorable reinterpretation.**

## Performance

- **Duration:** 25 min (this continuation session; Task 1 was completed in a prior session)
- **Started:** 2026-08-19 (Task 1, prior session) / 2026-08-19T21:30:00Z (this continuation)
- **Completed:** 2026-08-20
- **Tasks:** 3 (Task 1 completed prior session; Task 2 checkpoint resolved and Task 3 executed this session)
- **Files modified:** 7 (3 Mac `.cap` files, 3 `capture_diff` JSON reports, 1 results doc)

## Accomplishments
- Verified and committed Round 1's Mac-side captures (3 `.cap` files: lighting, blending, texturing), completing the six-file two-machine capture set alongside Task 1's Windows-side captures (commit `bf5e1a8`)
- Built `capture_diff` and ran it three times (`--element-type uint8`) for each Mac-vs-Windows fixture pair
- Documented all three fixtures' real divergence numbers in `17-CAPTURE-RESULTS-ROUND1.md`, mirroring `11-CAPTURE-RESULTS.md`'s structure and honest-reporting convention: blending shows genuine divergence (`maxAbsDelta=1.0`, `contentHashMatch=false`); lighting and texturing both show zero divergence (`contentHashMatch=true`), each honestly flagged rather than silently treated as a pass

## Task Commits

Each task was committed atomically:

1. **Task 1: Capture all three fixtures on this (Windows) machine** - `bf5e1a8` (feat) -- completed in prior session
2. **Task 2: Hands-on capture on the Mac mini (Round 1, all three fixtures)** - `a146781` (feat) -- Mac-side `.cap` files added/committed this session after user's "captured" resume-signal and orchestrator's file-existence verification
3. **Task 3: Diff all three Mac-vs-Windows pairs and document Round 1 results honestly** - `5d6904d` (docs)

**Plan metadata:** (this commit) `docs(17-05): complete plan`

## Files Created/Modified
- `.planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/captures/xhw-render-lighting_Fuus-Mac-mini.local---macOS_20260820T012827.cap` - Mac-side lighting capture
- `.planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/captures/xhw-render-blending_Fuus-Mac-mini.local---macOS_20260820T012840.cap` - Mac-side blending capture
- `.planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/captures/xhw-render-texturing_Fuus-Mac-mini.local---macOS_20260820T012844.cap` - Mac-side texturing capture
- `.planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/captures/diff-render-lighting.json` - capture_diff report (Mac vs Windows, uint8) -- zero divergence
- `.planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/captures/diff-render-blending.json` - capture_diff report (Mac vs Windows, uint8) -- maxAbsDelta=1, contentHashMatch=false
- `.planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/captures/diff-render-texturing.json` - capture_diff report (Mac vs Windows, uint8) -- zero divergence
- `.planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/17-CAPTURE-RESULTS-ROUND1.md` - Round 1 results document, per-fixture honest interpretation

## Decisions Made
- Accepted the user's "captured" resume-signal as sufficient confirmation both machines' `capture_harness` binaries were rebuilt from the current commit, mirroring Phase 13-04's accepted precedent (not independently re-derivable from `.cap` bytes alone, per this plan's own threat model).
- Reported blending's real divergence (`maxAbsDelta=1.0`, `maxRelDelta=0.0078125`, `maxUlpDistance=1`) exactly as `capture_diff` produced it -- no rounding.
- Reported lighting's and texturing's zero divergence exactly as measured, flagging each as an honest per-fixture finding (D-08) rather than a favorable "the byte-identity claim generalizes" conclusion. Texturing's zero result is explicitly annotated with the known nearest-filter caveat carried over from 17-04's SUMMARY.
- Deliberately did not invoke `requirements.mark-complete` for RENDTOL-01/RENDTOL-02 in this plan's state updates -- both are already (prematurely) checked off in REQUIREMENTS.md as of Plan 17-02, a known STATE.md-tracked discrepancy explicitly flagged for revisit at phase close/verification, not something this plan should re-trigger or silently "fix" by re-running the same command.

## Deviations from Plan

None - plan executed exactly as written. Task 2's Mac-side `.cap` files were already present on disk (transferred by the user per the plan's own action text) and were simply verified and committed; Task 3 ran `capture_diff` and wrote the results document exactly as the plan's action/acceptance criteria specified.

## Issues Encountered

None. Mac-side `.cap` files were untracked on disk at continuation start (the prior session's checkpoint transfer had not yet been committed) -- committed as part of completing Task 2, not a deviation from the plan's intent.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Round 1's raw, `byteQuantMode`-absent cross-hardware divergence data now exists for all three fixtures, ready for Wave 5 (17-06/17-07) to consume:
- **Blending** has a concrete non-zero `maxAbsDelta=1.0` target to binary-search a `byteQuantMode` value against.
- **Lighting** and **texturing** measured zero divergence this round -- Wave 5 should not invent a search target for either where none was empirically observed; per D-08, any resulting gap in deriving a meaningful non-zero tolerance for these two fixtures must be documented honestly rather than papered over.
- REQUIREMENTS.md's RENDTOL-01/02 premature-completion discrepancy (flagged in STATE.md since Plan 17-02) remains open for revisit at phase 17's close -- Waves 5-7 (tolerance derivation, counter-tests, Round 2) are still pending.

---
*Phase: 17-render-path-cross-hardware-tolerance*
*Completed: 2026-08-20*

## Self-Check: PASSED

All created files confirmed present on disk (17-CAPTURE-RESULTS-ROUND1.md, 3 diff-render-*.json reports, 3 Mac-side .cap files) and all 3 commits (`bf5e1a8`, `a146781`, `5d6904d`) confirmed present in git log --all.
