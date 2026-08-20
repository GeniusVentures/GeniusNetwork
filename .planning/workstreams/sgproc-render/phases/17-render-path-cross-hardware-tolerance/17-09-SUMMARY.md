---
phase: 17-render-path-cross-hardware-tolerance
plan: 09
subsystem: infra
tags: [vulkan, capture-diff, quantization, tolerance, cross-hardware, gtest]

# Dependency graph
requires:
  - phase: 17-08
    provides: Round 2 cross-machine capture data (blending .cap files with preQuantizeBytes intact) and the honestly-documented RENDTOL-02 blending residual gap
provides:
  - IsByteChunkWithinToleranceForMode wrapper (diff_utils.hpp/.cpp) for bare-int CLI callers
  - capture_diff --byte-quant-mode raw-tolerance check + rawToleranceCheck JSON output
  - diff-render-blending-r2-rawtolerance.json evidence file proving blending's byteQuantMode=6 is a valid numeric-tolerance fallback
  - RENDTOL-02 closure documentation (17-TOLERANCE-RESULTS.md Gap Closure Addendum, REQUIREMENTS.md, ROADMAP.md)
affects: [phase-18-build-stability, phase-19-validation-re-verification, future-milestone-close]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "CLI-facing wrapper functions that build a single-entry Parameter vector and delegate unmodified to an existing tolerance function, for callers with only a bare scalar (byteQuantMode int) instead of a full job Parameter array"
    - "Additive-only JSON report extension: new nested object (rawToleranceCheck) alongside unchanged existing top-level fields, so two independently-meaningful pass/fail verdicts (strict-hash vs. raw-tolerance) coexist in the same evidence file"

key-files:
  created:
    - .planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/captures/diff-render-blending-r2-rawtolerance.json
  modified:
    - SuperGenius/SGProcessingManager/include/util/diff_utils.hpp
    - SuperGenius/SGProcessingManager/src/util/diff_utils.cpp
    - SuperGenius/SGProcessingManager/test/util/diff_utils_test.cpp
    - SuperGenius/SGProcessingManager/tools/capture/capture_diff.cpp
    - .planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/17-TOLERANCE-RESULTS.md
    - .planning/workstreams/sgproc-render/REQUIREMENTS.md
    - .planning/workstreams/sgproc-render/ROADMAP.md

key-decisions:
  - "IsByteChunkWithinToleranceForMode is a pure additive wrapper -- delegates to IsByteChunkWithinTolerance unmodified, never refactors it or TryGetDeclaredByteQuantMode"
  - "capture_diff's rawToleranceCheck is opt-in (--byte-quant-mode) and additive -- every pre-existing top-level report field (quantizedBytes-based) is unchanged in meaning and value"
  - "Both the strict quantized-hash mismatch (64.0/false) and the new raw-tolerance pass (1.0/true) are documented side by side everywhere (evidence JSON, 17-TOLERANCE-RESULTS.md, REQUIREMENTS.md) -- neither number is silently reinterpreted or omitted"

patterns-established:
  - "Gap-closure plans that reuse an already-captured dataset (Round 2's preQuantizeBytes) rather than requiring a new hardware capture round, when the needed raw data was already recorded unconditionally by the capture format"

requirements-completed: [RENDTOL-02]

coverage:
  - id: D1
    description: "IsByteChunkWithinToleranceForMode wrapper added to diff_utils.hpp/.cpp, delegating unmodified to IsByteChunkWithinTolerance"
    requirement: "RENDTOL-02"
    verification:
      - kind: unit
        ref: "SuperGenius/SGProcessingManager/test/util/diff_utils_test.cpp#DiffUtilsTest.IsByteChunkWithinToleranceForModeUsesMaskBoundWhenDeclaredPasses / ...Fails / ...MatchesBlendingRealDelta"
        status: pass
    human_judgment: false
  - id: D2
    description: "capture_diff --byte-quant-mode CLI flag with strict [0,8] validation and additive rawToleranceCheck JSON/console output"
    requirement: "RENDTOL-02"
    verification:
      - kind: other
        ref: "capture_diff --a <Mac .cap> --b <Windows .cap> --element-type uint8 --byte-quant-mode 6 -> diff-render-blending-r2-rawtolerance.json (rawToleranceCheck.withinTolerance=true, byteQuantMode=6, maxAbsDelta=1.0)"
        status: pass
    human_judgment: false
  - id: D3
    description: "REQUIREMENTS.md/ROADMAP.md/17-TOLERANCE-RESULTS.md updated to reflect RENDTOL-02's honest closure (both numbers documented side by side)"
    requirement: "RENDTOL-02"
    verification:
      - kind: other
        ref: "grep -A2 RENDTOL-02 REQUIREMENTS.md | grep -qi complete; grep -q 'Gap Closure Addendum' 17-TOLERANCE-RESULTS.md; grep -q 17-09 ROADMAP.md"
        status: pass
    human_judgment: false

duration: 25min
completed: 2026-08-20
status: complete
---

# Phase 17 Plan 09: RENDTOL-02 Gap Closure Summary

**Closed RENDTOL-02's blending residual gap by extending capture_diff with a raw-buffer numeric-tolerance check that reuses production's IsByteChunkWithinTolerance unmodified, proving blending's byteQuantMode=6 against already-captured Round 2 preQuantizeBytes -- no new hardware capture round.**

## Performance

- **Duration:** ~25 min
- **Tasks:** 3
- **Files modified:** 8 (3 SGProcessingManager source/test files, 1 new evidence JSON, 3 planning docs, plus submodule pointer bumps)

## Accomplishments

- Added `IsByteChunkWithinToleranceForMode` to `diff_utils.hpp`/`.cpp` -- a thin wrapper for CLI callers with only a bare `byteQuantMode` int, delegating unmodified to the existing `IsByteChunkWithinTolerance`. 3 new unit tests (mask-bound pass/fail at N=6, plus blending's real measured raw delta of 1) all pass; full `DiffUtilsTest` suite (16 cases) green with no regressions.
- Wired a new `--byte-quant-mode <N>` CLI flag into `capture_diff`, validated to `[0,8]` and failing closed (usage error, exit 1) on any parse failure or out-of-range value -- confirmed via a live `--byte-quant-mode 99` smoke test.
- Ran the extended `capture_diff --element-type uint8 --byte-quant-mode 6` against the two already-on-disk Round 2 blending `.cap` files (`xhw-render-blending-r2_Fuus-Mac-mini.local---macOS_20260820T070308.cap`, `xhw-render-blending-r2_Mofu---Windows_20260820T031711.cap`), producing `captures/diff-render-blending-r2-rawtolerance.json`: `rawToleranceCheck.maxAbsDelta=1.0` (matches Round 1's independently-measured raw delta exactly), `withinTolerance=true`, `byteQuantMode=6` -- while every pre-existing top-level field (`contentHashMatch=false`, `maxAbsDelta=64.0`) stayed numerically unchanged from the original `diff-render-blending-r2.json`.
- Documented the closure honestly in a new "Gap Closure Addendum" section of `17-TOLERANCE-RESULTS.md`, and updated `REQUIREMENTS.md` (RENDTOL-02 checkbox + bullet + traceability row) and `ROADMAP.md` (Phase 17 milestone bullet, SC4 outcome text, Plans count 9/9, Wave 8 checkbox, Progress table row) -- all citing the new evidence rather than "human decision needed".

## Task Commits

1. **Task 1: Add IsByteChunkWithinToleranceForMode to diff_utils** - `62b2735` (SGProcessingManager, feat) -> pointer-bumped through `a2586ce3` (SuperGenius) -> `5759848` (outer repo)
2. **Task 2: Wire --byte-quant-mode into capture_diff and prove it against Round 2 data** - `bfabebf` (SGProcessingManager, feat) -> pointer-bumped through `5e6515b5` (SuperGenius) -> `62deb86` (outer repo, includes the new evidence JSON)
3. **Task 3: Document the gap closure and update REQUIREMENTS.md/ROADMAP.md** - `2e5877d` (outer repo, docs)

_Note: this plan touches the `SGProcessingManager` nested git submodule (inside `SuperGenius`, itself a submodule of the outer repo) -- each source-code task required 3 commits (submodule, SuperGenius pointer bump, outer repo pointer bump), mirroring this workstream's established multi-level-submodule convention._

## Files Created/Modified

- `SuperGenius/SGProcessingManager/include/util/diff_utils.hpp` - Declares `IsByteChunkWithinToleranceForMode`
- `SuperGenius/SGProcessingManager/src/util/diff_utils.cpp` - Implements the wrapper (builds a 1-entry Parameter vector, delegates to `IsByteChunkWithinTolerance`)
- `SuperGenius/SGProcessingManager/test/util/diff_utils_test.cpp` - 3 new `TEST_F` cases
- `SuperGenius/SGProcessingManager/tools/capture/capture_diff.cpp` - New `--byte-quant-mode` CLI flag, raw-tolerance check inside the `haveRecords` block, `rawToleranceCheck` JSON/console output
- `.planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/captures/diff-render-blending-r2-rawtolerance.json` - New evidence file
- `.planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/17-TOLERANCE-RESULTS.md` - New Gap Closure Addendum section
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` - RENDTOL-02 checkbox/bullet/traceability row updated to Complete
- `.planning/workstreams/sgproc-render/ROADMAP.md` - Phase 17 milestone bullet, SC4 outcome, Plans count (9/9), Wave 8 checkbox, Progress table row

## Decisions Made

None beyond the plan's own explicit design (D-10/D-11 were already locked before this plan started) - implemented exactly as specified: pure additive wrapper function, opt-in CLI flag, additive JSON object, honest side-by-side documentation of both the still-true strict-hash mismatch and the new raw-tolerance pass.

## Deviations from Plan

None - plan executed exactly as written. All three tasks' acceptance criteria were met without needing any Rule 1-4 auto-fixes: the build succeeded cleanly on the first attempt for both `diff_utils_test` and `capture_diff`, the two named Round 2 blending `.cap` files existed exactly as the plan cited them (no glob fallback needed), and the resulting numbers (`maxAbsDelta=1.0`/`withinTolerance=true` for the raw check, `maxAbsDelta=64.0`/`false` unchanged for the strict check) matched the plan's stated expectations exactly.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

RENDTOL-02 is now fully closed for all three RENDTOL-01 fixtures (lighting/texturing via strict hash-match, blending via the new raw-tolerance proof). Phase 17 is fully complete (9/9 plans). No blockers for Phase 18 (Build Stability) or Phase 19 (Validation Re-Verification) -- both are independent of Phase 17 per the v2.3 roadmap's dependency note. `IsByteChunkWithinToleranceForMode` and the `--byte-quant-mode` capture_diff flag are available for reuse by any future phase needing a bare-int raw-tolerance check.

---
*Phase: 17-render-path-cross-hardware-tolerance*
*Completed: 2026-08-20*

## Self-Check: PASSED

All created/modified files confirmed present on disk (diff_utils.hpp/.cpp, diff_utils_test.cpp, capture_diff.cpp, diff-render-blending-r2-rawtolerance.json, this SUMMARY). All commit hashes confirmed present in their respective repos: `62b2735`/`bfabebf` in `SuperGenius/SGProcessingManager`; `a2586ce3`/`5e6515b5` in `SuperGenius`; `5759848`/`62deb86`/`2e5877d` in the outer repo (`2e5877d` is docs-only, outer repo only, as expected -- no corresponding submodule change).
