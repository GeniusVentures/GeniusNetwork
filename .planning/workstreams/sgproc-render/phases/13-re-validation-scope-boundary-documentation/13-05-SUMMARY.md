---
phase: 13-re-validation-scope-boundary-documentation
plan: 05
subsystem: testing
tags: [capture_diff, quantization, cross-hardware, sha256, mnn, gtest]

# Dependency graph
requires:
  - phase: 13-04
    provides: "S=2^15 (32768.0f) widened-grid quantization fix (chosen over the plan's originally-proposed S=2^14 after a SECV-01 regression was found), plus fresh xhw-mnn-float_*.cap captures on Mac + Windows with the fix compiled in"
provides:
  - "Fresh capture_diff report (diff-mnn-float-refit.json) comparing the two newest Mac/Windows xhw-mnn-float_*.cap files, produced under the S=2^15 fix"
  - "13-SCOPE-BOUNDARY.md 'SC1 Refit' section documenting the fresh outcome honestly (gap narrowed, not closed) with the real S=2^15 derivation numbers"
  - "Root-cause investigation of the chunkHashesMatch[10]-despite-zero-delta anomaly, with file:line citations into capture_diff.cpp/capture_harness.cpp/capture_file_format.hpp"
  - "REQUIREMENTS.md/ROADMAP.md VALD-01/SC1 evidence citations updated to reference the fresh Refit section alongside the original round's numbers, status correctly left Partial"
affects: [future-VALD-01-followup, capture_diff-tooling]

# Tech tracking
tech-stack:
  added: []
  patterns: ["conditional status-flip branching on verbatim JSON fields, not paraphrased assumptions (mirrors 13-03's discipline)"]

key-files:
  created:
    - ".planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/captures/diff-mnn-float-refit.json"
  modified:
    - ".planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/13-SCOPE-BOUNDARY.md"
    - ".planning/workstreams/sgproc-render/REQUIREMENTS.md"
    - ".planning/workstreams/sgproc-render/ROADMAP.md"

key-decisions:
  - "Used the correct (newest, 2026-08-12T23:23-23:24) xhw-mnn-float_*.cap pair for the diff, not the original round's same-labeled files (2026-08-12T21:20-21:25) still present in the same directory, per the plan-text deviation note"
  - "VALD-01/SC1 status stays Partial: contentHashMatch is now true (up from false) and only 1 of 15 chunkHashesMatch entries is false (down from 12/15), but this is not the unconditionally-clean bar this plan's must_haves require for a status flip to Complete"
  - "Investigated and documented (rather than hand-waved) the chunkHashesMatch[10]-despite-zero-measured-delta anomaly: capture_diff.cpp's numeric pass (maxAbsDelta/maxRelDelta/maxUlpDistance) only ever diffs the trailing combined-hash CaptureRecord (rawRecordsPerArtifact[0].back()), never any of the 15 individual per-chunk records that feed chunkHashesMatch[j] — a real, distinct scope limitation in capture_diff inherited unmodified from Phase 10, not a contradiction and not a new defect introduced by the S=2^15 fix"

patterns-established:
  - "Gap-closure re-measurement plans cite the fresh JSON verbatim in a new '<SC> Refit' section appended after (not replacing) the original round's section, keeping both rounds visible for before/after comparison"

requirements-completed: []

coverage:
  - id: D1
    description: "capture_diff run against the fresh (correct, newest) Mac-vs-Windows xhw-mnn-float_*.cap pair produced under the S=2^15 fix, written to captures/diff-mnn-float-refit.json"
    requirement: "VALD-01"
    verification:
      - kind: other
        ref: "capture_diff.exe --a captures/xhw-mnn-float_Fuus-Mac-mini.local---macOS_20260812T232347.cap --b captures/xhw-mnn-float_Mofu---Windows_20260812T232430.cap --element-type float32 --json-output captures/diff-mnn-float-refit.json (exit 0, JSON written and verified valid)"
        status: pass
    human_judgment: false
  - id: D2
    description: "13-SCOPE-BOUNDARY.md SC1 Refit section honestly records the outcome (gap narrowed, not closed) and REQUIREMENTS.md/ROADMAP.md VALD-01/SC1 status is correctly left Partial with updated evidence citations"
    requirement: "VALD-01"
    verification: []
    human_judgment: true
    rationale: "Whether the honesty/no-rounding-away-an-unfavorable-result discipline was correctly applied to the prose is a qualitative judgment call this session made in good faith per the plan's must_haves, but is not mechanically re-verifiable by a script — a human reviewer should confirm the Refit section's stated outcome matches diff-mnn-float-refit.json's actual fields exactly."

# Metrics
duration: 12min
completed: 2026-08-12
status: complete
---

# Phase 13 Plan 05: SC1 Refit Re-Measurement Summary

**Fresh capture_diff on the correct (newest) Mac-vs-Windows MNN capture pair under the S=2^15 quantization fix: contentHashMatch flipped false→true and chunk divergence narrowed from 12/15 to 1/15, but VALD-01/SC1 correctly stays Partial since chunkHashesMatch[10] is still false.**

## Performance

- **Duration:** 12 min
- **Started:** 2026-08-12T23:33:00Z (approx.)
- **Completed:** 2026-08-12T23:45:00Z (approx.)
- **Tasks:** 2
- **Files modified:** 4 (1 new, 3 edited)

## Accomplishments
- Ran `capture_diff` on the two newest `xhw-mnn-float_*.cap` files (Mac `...T232347`, Windows `...T232430`) — the pair produced under Plan 13-04's S=2^15 fix, correctly distinguished from the original round's identically-labeled pair still on disk (`...T212550`/`...T212019`) — writing `captures/diff-mnn-float-refit.json`
- Result: `contentHashMatch: true` (was `false`), only `chunkHashesMatch[10]` is `false` (12/15 were false in the original round), `maxAbsDelta`/`maxRelDelta`/`maxUlpDistance` all exactly `0` (was `9.5367431640625e-07`/`5.3748990467283875e-05`/`512`)
- Wrote a new "SC1 Refit: Widened-Grid Re-Measurement" section in `13-SCOPE-BOUNDARY.md`, citing the real applied fix (S=2^15/32768.0f, chosen after S=2^14 was found to regress SECV-01) rather than the plan's stale S=2^14 text, embedding the fresh JSON verbatim
- Investigated the chunkHashesMatch[10]-despite-zero-delta anomaly by reading `capture_diff.cpp`, `capture_harness.cpp`, and `capture_file_format.hpp` source (not guessed): the numeric per-element pass only ever diffs the trailing combined-hash `CaptureRecord`, never any per-chunk record — so a chunk-level hash mismatch and a zero-delta trailing-record comparison are not in tension, they describe two different byte buffers that this tool has never cross-diffed at the per-element level
- Updated `REQUIREMENTS.md`'s VALD-01 line/traceability row and `ROADMAP.md`'s Phase 13 SC1/Progress-table/phase-list-bullet/Wave-list to cite the fresh Refit evidence alongside the original round's, keeping status "Partial" per the plan's strict branching rule (fresh diff is not unconditionally clean)

## Task Commits

Each task was committed atomically:

1. **Task 1: Run capture_diff on Plan 13-04's fresh widened-grid MNN captures** - `9760792` (feat)
2. **Task 2: Write 13-SCOPE-BOUNDARY.md's Refit section + conditional REQUIREMENTS.md/ROADMAP.md update** - `3471a11` (docs)

**Plan metadata:** (final commit hash recorded after this SUMMARY is committed)

## Files Created/Modified
- `.planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/captures/diff-mnn-float-refit.json` - Fresh capture_diff JSON report for the S=2^15-fixed MNN fixture (Mac vs Windows)
- `.planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/13-SCOPE-BOUNDARY.md` - New "SC1 Refit" section: real S=2^15 derivation, verbatim fresh JSON, honest outcome statement, capture_diff.cpp anomaly investigation with file:line citations
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` - VALD-01 line + traceability row + footer updated to cite the fresh Refit evidence alongside the original round's, status left "Partial"
- `.planning/workstreams/sgproc-render/ROADMAP.md` - Phase 13 SC1 success-criterion text, Progress table row, phase-list summary bullet, Plans-complete count, and 13-05 Wave checkbox updated to reflect the Refit outcome

## Decisions Made
- Used the two newest `xhw-mnn-float_*.cap` files (2026-08-12T23:23/23:24) for the diff, not the original round's identically-labeled pair (2026-08-12T21:20/21:25) still present in the same `captures/` directory — per the plan-text deviation note explaining the user re-ran the same capture command without the `-refit` label suffix
- Left the render fixture and its captures (`xhw-render_*.cap`, both timestamp pairs) completely untouched — the render path already fully satisfies SC1 and this plan's scope is the MNN fixture's remaining gap only
- Kept VALD-01/SC1 status "Partial" (not flipped to Complete) because `chunkHashesMatch[10]` is `false` in the fresh diff — the plan's must_haves require an unconditionally clean result (contentHashMatch true AND every chunkHashesMatch entry true) before a status flip is permitted, and this result does not meet that bar despite being a dramatic improvement
- Investigated (rather than hand-waved) the apparent contradiction between zero measured numeric deltas and a still-false chunk hash: read `capture_diff.cpp:295-296/308-319/283-291`, `capture_file_format.hpp:52-59/73-78`, and `capture_harness.cpp:276-315` to confirm `capture_diff`'s numeric pass (`maxAbsDelta`/`maxRelDelta`/`maxUlpDistance`) only ever examines the trailing combined-hash `CaptureRecord` (the same bytes feeding `contentHash`), never any of the 15 individual per-chunk records that independently feed `chunkHashesMatch[j]` — this is a real, pre-existing (Phase 10-era) scope limitation in `capture_diff`'s diagnostic coverage, not a logical contradiction and not a new defect from this fix

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug/documentation gap] Plan's Task 1 read_first cited stale filenames**

- **Found during:** Task 1
- **Issue:** The plan text (and its own must_haves/read_first) expected fresh captures labeled `xhw-mnn-float-refit_*.cap`. The user instead re-ran the identical Plan 13-01 capture command without the `-refit` label, producing a second `xhw-mnn-float_*.cap` pair sharing the original round's label prefix. Naively globbing for `xhw-mnn-float-refit_*` would have found nothing; naively taking the first `xhw-mnn-float_*` match risked re-diffing the original (pre-fix, S=2^20) round instead of the fresh S=2^15 round.
- **Fix:** Used the file timestamps in `captures/` (via `ls -la`) to identify the two newest `xhw-mnn-float_*.cap` files (2026-08-12T23:23/23:24, matching the S=2^15 fix's capture window) and diffed exactly that pair, per the deviation note already supplied in this plan's execution context.
- **Files modified:** N/A (identification only; the diff output filename itself still uses the `-refit` suffix per the plan's own convention note)
- **Verification:** Confirmed via `ls -la` timestamps and cross-referenced against `13-04`'s commit/checkpoint timeline in STATE.md
- **Committed in:** `9760792` (Task 1 commit)

**2. [Rule 2 - Missing critical functionality] Plan cited stale S=2^14/64x/585x numbers**

- **Found during:** Task 2
- **Issue:** The plan's Task 2 action text instructed citing "S=2^14 ... 64x ... 585x" as the applied fix's derivation. The actual committed fix (per `quantization.hpp`'s already-updated doc comment and STATE.md's Blockers/Concerns entry) is S=2^15 (32768.0f), chosen after S=2^14 was found to deterministically regress `Secv01CounterTest.MnnCorruptedModelStillDiverges`. Citing the plan's literal stale numbers in a permanent milestone-closing document would have been factually wrong.
- **Fix:** Cited the real numbers throughout the new Refit section: S=2^15, grid step `3.0517578125e-05`, 32x the old S=2^20 grid step, ~292x Phase 11's original `maxAbsDelta`, including the SECV-01 boundary discovery (S=2^14 fails deterministically, S=2^15 chosen for one power-of-two of margin above that boundary) — matching this plan's own execution-context deviation note and `quantization.hpp`'s source-of-truth doc comment.
- **Files modified:** `13-SCOPE-BOUNDARY.md`
- **Verification:** Cross-checked against `quantization.hpp` lines 32-63 (read directly) and STATE.md's Phase 13-04 decision entry
- **Committed in:** `3471a11` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 file-identification correction, 1 stale-numbers correction), both required to avoid citing wrong evidence in a permanent traceability document. No scope creep — no source files under `SuperGenius/` were touched by this plan.
**Impact on plan:** Both corrections were necessary for factual accuracy; neither changed the plan's actual objective or success criteria.

## Issues Encountered

- The chunkHashesMatch[10]-despite-zero-delta result initially looked like a tool bug or a contradiction. Root-caused by reading `capture_diff.cpp`/`capture_harness.cpp`/`capture_file_format.hpp` directly: `capture_diff`'s numeric per-element pass only ever diffs the trailing combined-hash `CaptureRecord` (the bytes feeding `contentHash`), never any of the 15 individual per-chunk records that feed `chunkHashesMatch[j]`. This is documented in the new Refit section with file:line citations as a real, pre-existing scope limitation in `capture_diff`'s diagnostic coverage (inherited unmodified from Phase 10) — not a defect introduced by this plan or Plan 13-04's fix, and flagged as a follow-up item for whoever next extends `capture_diff` to also numeric-diff per-chunk records.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- VALD-01's MNN gap is now well-characterized: narrowed to a single divergent chunk (chunk 10 of 15) with zero measured numeric delta anywhere `capture_diff`'s current tooling can see, and a documented follow-up path exists (extend `capture_diff` to numeric-diff per-chunk records, not just the trailing combined record) for whoever picks this up next.
- No further work is scoped into this milestone (v2.1) beyond this plan per ROADMAP.md's Wave 4 — Phase 13 is otherwise closed out (13-01/02/03/05 complete; 13-04's substantive fix is committed and reflected in `quantization.hpp`, though its own checkpoint/SUMMARY remain formally outstanding, noted in ROADMAP.md's Plans-complete line).

---
*Phase: 13-re-validation-scope-boundary-documentation*
*Completed: 2026-08-12*

## Self-Check: PASSED

- FOUND: `captures/diff-mnn-float-refit.json`
- FOUND: `13-SCOPE-BOUNDARY.md`
- FOUND: `13-05-SUMMARY.md`
- FOUND commit: `9760792` (Task 1)
- FOUND commit: `3471a11` (Task 2)
