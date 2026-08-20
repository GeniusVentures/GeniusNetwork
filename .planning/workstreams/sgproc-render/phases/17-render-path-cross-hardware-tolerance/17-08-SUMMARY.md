---
phase: 17-render-path-cross-hardware-tolerance
plan: 08
subsystem: rendering
tags: [byteQuantMode, cross-hardware, capture-diff, SC4, honest-reporting, render-path]

requires:
  - phase: 17-06
    provides: lighting=5 and blending=6 byteQuantMode values, plus the corrected lighting shader this plan's Round 2 lighting capture depends on
  - phase: 17-07
    provides: texturing=7 byteQuantMode value
provides:
  - Round 2's complete six-file cross-machine capture set (all three fixtures, both machines, final derived tolerances active)
  - Three fresh capture_diff JSON reports (diff-render-lighting-r2.json, diff-render-blending-r2.json, diff-render-texturing-r2.json)
  - 17-TOLERANCE-RESULTS.md -- the phase's final, honest per-fixture SC4 verdict
  - A root-caused, previously-unknown limitation of QuantizeByteBuffer's bit-masking design (amplifies boundary-straddling raw deltas instead of absorbing them)
  - ROADMAP.md's Phase 17 section closed out with real per-fixture outcomes (not assumed-passing)
affects: [Phase 17 close (final plan), any future work on RENDTOL-02's blending residual gap]

tech-stack:
  added: []
  patterns: [honest per-fixture SC4 verdict reporting (13-SCOPE-BOUNDARY.md convention), before/after Round 1 vs Round 2 side-by-side comparison]

key-files:
  created:
    - .planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/17-TOLERANCE-RESULTS.md
    - .planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/captures/diff-render-lighting-r2.json
    - .planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/captures/diff-render-blending-r2.json
    - .planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/captures/diff-render-texturing-r2.json
  modified:
    - .planning/workstreams/sgproc-render/ROADMAP.md

decisions:
  - "Blending's Round 2 residual gap (contentHashMatch=false, maxAbsDelta=64.0, up from raw 1.0) is reported as a genuine, worsened gap, not reinterpreted or hidden -- root-caused to QuantizeByteBuffer's bit-masking (value &= ~((1<<N)-1)) having no rounding tie-break protection: raw deltas straddling a 2^N-wide bucket boundary get amplified into a full-bucket-width difference. Confirmed directly by inspecting the actual quantized render output bytes (only {0,64,128} present, consistent with 6-low-bit masking)."
  - "Lighting's Round 2 zero-divergence result is reported as a fresh, legitimate measurement (first real cross-hardware test of corrected Phong math per 17-06's shader fix), not assumed to still hold from Round 1's now-known-degenerate figure -- but the honest caveat that this fixture's flat-geometry-facing-directional-light setup still produces spatially uniform output (not stressing per-fragment cross-hardware variation) is carried forward, not resolved by the shader fix."
  - "Did not re-run requirements.mark-complete for RENDTOL-02 -- consistent with 17-05/17-06/17-07's own decision, and now additionally justified: RENDTOL-02 is genuinely NOT fully closed (blending's residual gap is real and unresolved), so marking it complete would misrepresent the phase's actual outcome. REQUIREMENTS.md's RENDTOL-01/RENDTOL-02 checkboxes were found already unchecked with accurate in-progress annotations (not prematurely marked complete as an earlier STATE.md note suggested) -- left untouched since this plan's files_modified scope is ROADMAP.md, not REQUIREMENTS.md."

requirements-completed: []

coverage:
  - id: D1
    description: "Round 2's six .cap files exist (3 fixtures x 2 machines), using each fixture's final empirically-derived byteQuantMode, distinct from Round 1's files"
    requirement: "RENDTOL-02"
    verification:
      - kind: other
        ref: "All 6 xhw-render-<technique>-r2_*.cap files present under captures/ (3 Windows, from Task 1's 170a4dd; 3 Mac, from this plan's Task 2, commit 6bdb643), distinct filenames from Round 1's xhw-render-<technique>_*.cap"
        status: pass
    human_judgment: false
  - id: D2
    description: "Three fresh capture_diff JSON reports exist, one per fixture, run with --element-type uint8 against Round 2's Mac-vs-Windows pairs"
    requirement: "RENDTOL-02"
    verification:
      - kind: automated_test
        ref: "capture_diff.exe rebuilt and run 3x against the Round-2 pairs; diff-render-lighting-r2.json/diff-render-blending-r2.json/diff-render-texturing-r2.json all written"
        status: pass
    human_judgment: false
  - id: D3
    description: "17-TOLERANCE-RESULTS.md states a real, honest (a)/(b)/(c) outcome per fixture, sourced directly from the JSON reports"
    requirement: "RENDTOL-02"
    verification:
      - kind: other
        ref: "Lighting (a) hash match confirmed; blending (b) residual gap, root-caused and characterized specifically; texturing (c) never diverged in the first place -- all three numbers cited verbatim from the capture_diff JSON output, no invented figures"
        status: pass
    human_judgment: false
  - id: D4
    description: "ROADMAP.md's Phase 17 Success Criteria 1-5 each annotated with a real per-fixture outcome via scoped Edit calls; Plans count/list and Progress table row updated to reflect actual 8-plan completion"
    requirement: "RENDTOL-02"
    verification:
      - kind: other
        ref: "4 scoped Edit calls applied to ROADMAP.md: phase bullet checkbox+status, SC1-5 annotations, Plans count (8/8), Wave 7 task checkbox, Progress table row (8/8, Complete, 2026-08-20) -- rest of file untouched"
        status: pass
    human_judgment: false

duration: 55min
completed: 2026-08-20
status: complete
---

# Phase 17 Plan 08: Round 2 Cross-Hardware Capture, SC4 Verdict & ROADMAP Close-Out Summary

**Round 2's final cross-machine capture (all three fixtures, final derived byteQuantMode values) is complete and diffed -- lighting hash-matches (a fresh, legitimate zero-divergence measurement against 17-06's corrected shader) and texturing hash-matches (confirmed never diverging in the first place), but blending has a real, unresolved residual gap that the chosen tolerance mechanism makes WORSE, not better (raw maxAbsDelta=1.0 became quantized maxAbsDelta=64.0), root-caused to QuantizeByteBuffer's bit-masking amplifying boundary-straddling raw deltas -- reported honestly, not silently declared passing.**

## Performance

- **Duration:** ~55 min (continuation from Task 2's checkpoint)
- **Completed:** 2026-08-20
- **Tasks:** 2 (Task 2 checkpoint resolution + Task 3)
- **Files modified:** 8 (6 .cap files across Task 1/2, 3 new diff JSON reports, 1 new results doc, 1 ROADMAP.md edit)

## Accomplishments

- Verified Task 2's checkpoint: all 6 Round-2 `.cap` files (3 Windows from Task 1, 3 Mac from Task 2) present in `captures/`, both machines captured against a checkout including 17-06/17-07's final `byteQuantMode` values (lighting=5, blending=6, texturing=7).
- Rebuilt `capture_diff` and ran it 3x (`--element-type uint8`) against each Round-2 Mac-vs-Windows pair, writing fresh JSON reports.
- Confirmed lighting's Round 1 "zero divergence" figure was a documented pre-existing artifact of a since-fixed degenerate-render shader bug (17-06); this plan's Round 2 lighting capture is the first real cross-hardware measurement of the corrected Phong math, and it independently landed at zero divergence again (`contentHashMatch=true`) -- a fresh, legitimate result, not a reused stale one.
- Confirmed texturing's Round 1 zero-divergence result carries forward unchanged and remains honest (already independently verified non-degenerate in 17-07).
- Found blending's Round 2 result got measurably WORSE under quantization: raw `maxAbsDelta=1.0` (Round 1) became quantized `maxAbsDelta=64.0` (Round 2), with `contentHashMatch=false` and 25% of elements now exceeding `capture_diff`'s absolute-delta threshold (up from 0%). Root-caused this to `QuantizeByteBuffer`'s bit-masking implementation (`value &= ~((1<<N)-1)`, floor-to-bucket with no rounding tie-break): raw per-element deltas of 1 unit that straddle a 64-wide bucket boundary get amplified into a full 64-unit quantized difference. Confirmed directly by inspecting the actual quantized render output bytes on this machine -- only `{0, 64, 128}` appear, consistent with 6-low-bit masking.
- Wrote `17-TOLERANCE-RESULTS.md`: one subsection per fixture with Round 1 vs Round 2 numbers side by side, an explicit (a)/(b)/(c) outcome per fixture, and a specific root-cause explanation for blending's regression -- mirroring `13-SCOPE-BOUNDARY.md`'s honesty convention. Explicitly notes that SC4 (hash-match/honest-gap) and SC5 (counter-test proves not-too-loose) answer different questions -- blending's SC4 failure does not indicate an SC5 problem.
- Closed out `ROADMAP.md`'s Phase 17 section via 4 scoped `Edit` calls: phase-list bullet checkbox + completion note, all 5 Success Criteria annotated with real per-fixture outcomes, `Plans` count updated to 8/8, Wave 7's task checkbox marked complete, and the Progress table's Phase 17 row updated (8/8, Complete with residual-gap note, 2026-08-20).

## Task Commits

1. **Task 2: Mac-side Round 2 capture files** - `6bdb643` (outer repo, feat)
2. **Task 3: Diff Round 2, honest SC4 verdict, ROADMAP close-out** - `e5c4855` (outer repo, docs)

**Plan metadata:** (this commit) `docs(17-08): complete plan`

## Files Created/Modified

- `.planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/captures/xhw-render-{lighting,blending,texturing}-r2_Fuus-Mac-mini.local---macOS_*.cap` - Mac-side Round 2 captures (Task 2)
- `.planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/captures/diff-render-{lighting,blending,texturing}-r2.json` - fresh Round 2 `capture_diff` reports
- `.planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/17-TOLERANCE-RESULTS.md` - new, the phase's final honest SC4 verdict document
- `.planning/workstreams/sgproc-render/ROADMAP.md` - Phase 17 section closed out (SC annotations, Plans count, Progress table)

## Decisions Made

- Blending's residual gap is reported as a genuine regression under quantization (not a smaller-but-still-open gap) -- root-caused specifically to the bit-masking mechanism's lack of rounding, confirmed via direct byte inspection of the quantized output, not left as an unexplained anomaly.
- Lighting's zero-divergence Round 2 result is treated as a fresh, independently-earned measurement (real Phong math this time), while still honestly flagging that this fixture's specific geometry (flat surface, directional light, no spatial attenuation) doesn't stress cross-hardware spatial variation -- carried forward from Round 1's own honesty flag, not resolved by the shader fix.
- Did not re-run `requirements.mark-complete` for RENDTOL-02: it is genuinely not fully closed (blending's gap is real and unresolved), so marking it complete would misrepresent the phase's outcome. REQUIREMENTS.md's RENDTOL-01/RENDTOL-02 lines were found already unchecked with accurate in-progress annotations (contrary to an earlier STATE.md note suggesting they were prematurely marked complete) -- left untouched, consistent with this plan's ROADMAP.md-only files_modified scope.
- No fix to `QuantizeByteBuffer`'s bit-masking mechanism was attempted -- redesigning it (e.g. to a round-to-nearest-grid scheme mirroring the float path) is an architectural decision outside this plan's scope, flagged in `17-TOLERANCE-RESULTS.md` as a real follow-up.

## Deviations from Plan

None - plan executed exactly as written for Task 2 (checkpoint resolution) and Task 3 (diff + honest reporting + ROADMAP close-out). The blending residual gap and its root cause are a *finding*, not a deviation -- the plan's own must_haves explicitly anticipated and required this exact honest-reporting outcome (D-08).

## Issues Encountered

- Confirmed (via direct byte inspection of this session's local quantized render outputs) that `byteQuantMode` masking is genuinely active and behaving as `quantization.hpp` documents (`{0,64,128}` bucket values for blending's N=6) -- ruling out a capture/diff tooling bug as the explanation for blending's worsened Round 2 result. The regression is real and mechanism-driven, not an artifact of this plan's own process.

## User Setup Required

None - no external service configuration required.

## Phase 17 Close: Final Status

**This is the final plan of Phase 17.** Reporting the phase-wide outcome honestly, per the objective's explicit instruction:

- **RENDTOL-01** (three non-trivial fixtures exist, each genuinely exercising floating-point-heavy render computation): **fully satisfied**. All three fixtures are built, and each one's behavior is independently confirmed genuine -- lighting's degenerate-render bug was found and fixed (17-06), texturing's zero-divergence was proven honest via its own counter-test (17-07), and blending's real floating-point sensitivity was confirmed via real non-zero raw divergence (17-05).
- **RENDTOL-02** (real schema-configurable tolerance mechanism, proven against real cross-hardware capture data for all three fixtures): **NOT fully closed**. The mechanism itself (`ResolveByteQuantMode`/`QuantizeByteBuffer`) exists and is wired in for all three fixtures, and each fixture's chosen `byteQuantMode` independently passes its own SECV-01-style counter-test (SC5 -- not too loose to mask corruption). But SC4's cross-hardware hash-match target is only achieved for 2 of 3 fixtures: lighting and texturing hash-match; **blending does not**, and its gap is not merely unresolved but measurably worse under the current quantization mechanism than the raw unquantized divergence was. This is a real, understood, specifically-characterized limitation of the bit-masking design (documented in `17-TOLERANCE-RESULTS.md`), not a hidden or reinterpreted failure.
- **Do not read this phase as fully closing RENDTOL-02.** Whoever picks up blending's residual gap next should start from `17-TOLERANCE-RESULTS.md`'s Root Cause section (bit-masking vs. round-to-nearest-grid), not re-derive it from scratch.

## Next Phase Readiness

- Phase 17 is now 8/8 plans complete. Phases 18 (Build Stability) and 19 (Validation Re-Verification) remain independent and unblocked by this phase's residual gap.
- A future plan/phase revisiting RENDTOL-02's blending gap should consider either (a) switching `QuantizeByteBuffer` to a round-to-nearest-grid scheme (mirroring the float path's `round(x*S)/S`) instead of bit-masking, or (b) accepting blending's cross-hardware hash as unmatchable under the current mechanism and relying on a numeric-tolerance comparison bar instead (as Phase 15 already does for the MNN path) -- both are architectural decisions, not covered by this plan.

---
*Phase: 17-render-path-cross-hardware-tolerance*
*Completed: 2026-08-20*
