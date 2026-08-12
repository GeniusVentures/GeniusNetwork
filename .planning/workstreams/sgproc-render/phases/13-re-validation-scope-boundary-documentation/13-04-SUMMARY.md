---
phase: 13-re-validation-scope-boundary-documentation
plan: 04
subsystem: testing
tags: [quantization, cross-hardware, secv-01, gap-closure, capture_harness]

# Dependency graph
requires:
  - phase: 13-03
    provides: "13-SCOPE-BOUNDARY.md's honest 'Open Gap Against SC1' statement (12/15 MNN chunkHashesMatch false at S=2^20) that this plan responds to"
provides:
  - "QuantizeFloatBuffer's rounding grid widened from S=2^20 (1048576.0f) to S=2^15 (32768.0f), the widest power-of-two value confirmed safe against SECV-01's MnnCorruptedModelStillDiverges via local binary search, after the plan's originally-proposed S=2^14 was found to regress that same test"
  - "2 fresh xhw-mnn-float_*.cap files (Mac + Windows) captured with the S=2^15 fix compiled in, the raw evidence Plan 13-05's capture_diff run consumed"
affects: [13-05-refit-diff]

# Tech tracking
tech-stack:
  added: []
  patterns: ["local binary search over power-of-two grid constants against a security counter-test, to find the widest value that still fails-closed on a deliberately-wrong result, before committing a widened tolerance"]

key-files:
  created: []
  modified:
    - "SuperGenius/SGProcessingManager/include/util/quantization.hpp"
    - "SuperGenius/SGProcessingManager/src/util/quantization.cpp"
    - "SuperGenius/SGProcessingManager/test/util/quantization_test.cpp"

key-decisions:
  - "Abandoned the plan's literal S=2^14 target after it deterministically regressed Secv01CounterTest.MnnCorruptedModelStillDiverges (reproduced twice, confirmed non-flaky); no commit was ever made for that attempt, it was fully reverted before any commit"
  - "User chose to investigate a narrower value rather than abandon the fix or accept the MNN gap as-is"
  - "Ran a local binary search over power-of-two S values against the same SECV-01 test: S=2^17/2^16/2^15 all pass, S=2^14 fails deterministically; chose S=2^15 (32768.0f) as the widest confirmed-safe value, one power-of-two step of margin above the confirmed failure boundary"

requirements-completed: []

coverage:
  - id: D1
    description: "QuantizeFloatBuffer's kScale widened from 1048576.0f (2^20) to 32768.0f (2^15), with quantization.hpp's doc comment and quantization_test.cpp's echoed constant both updated to match; QuantizationTest (7/7) and processing_conformance_security_test's SECV-01 cases pass locally at the new constant"
    requirement: "VALD-01"
    verification:
      - kind: unit
        ref: "ctest -R QuantizationTest (7/7 TEST_F pass, confirmed both by executor at S=2^15 and independently re-run by 13-VERIFICATION.md's verifier)"
        status: pass
      - kind: unit
        ref: "ctest -R processing_conformance_security_test -- Secv01CounterTest.MnnCorruptedModelStillDiverges / RenderWrongShaderConstantStillDiverges (both OK at S=2^15)"
        status: pass
    human_judgment: false
  - id: D2
    description: "2 fresh xhw-mnn-float_*.cap files (Mac + Windows), captured hands-on by the user with the S=2^15 fix compiled in, landed in Phase 13's captures/ directory for Plan 13-05 to diff"
    verification: []
    human_judgment: true
    rationale: "Whether both machines' capture_harness binaries were genuinely rebuilt from a checkout including this plan's Task 1 commit before capturing is asserted by the user via the resume signal, not independently derivable from the .cap bytes alone within this task -- same precondition-acceptance pattern as Plan 13-01's own threat model (T-13-02)."

# Metrics
duration: 65min
completed: 2026-08-12
status: complete
---

# Phase 13 Plan 04: Widen QuantizeFloatBuffer's Rounding Grid (S=2^14 -> S=2^15 Pivot) Summary

**QuantizeFloatBuffer's MNN float32 rounding grid widened to S=2^15 (32768.0f) -- not the plan's originally-specified S=2^14 -- after S=2^14 was found to deterministically regress SECV-01's corrupted-model counter-test; a local binary search over power-of-two values found S=2^15 the widest value still safe, and 2 fresh cross-machine captures were taken with the fix active.**

## Performance

- **Duration:** ~65 min (18:40 first attempt start -> 19:45 fresh captures landed)
- **Started:** 2026-08-12T18:40:00-04:00 (approx., first Task 1 attempt)
- **Completed:** 2026-08-12T19:45:45-04:00 (5c3379a, fresh captures committed)
- **Tasks:** 2 (Task 1: auto/tdd; Task 2: checkpoint:human-action)
- **Files modified:** 3 source files (quantization.hpp/cpp, quantization_test.cpp) + 4 new .cap files (2 MNN, 2 render duplicates) + STATE.md (3 intermediate commits)

## Accomplishments
- **First attempt (reverted, no commit):** Implemented the plan exactly as written -- widened `kScale` from `1048576.0f` (2^20) to `16384.0f` (2^14), updated `quantization.hpp`'s doc comment and `quantization_test.cpp`'s echoed constant. Locally, `QuantizationTest` passed 7/7, but `processing_conformance_security_test`'s `Secv01CounterTest.MnnCorruptedModelStillDiverges` **FAILED** -- the corrupted-model fixture's post-quantization `artifactId` collided bit-for-bit with the correct model's. Reverted and reproduced the failure a second time to confirm it was deterministic, not flaky, before halting.
- Presented the S=2^14 regression to the user and asked how to proceed; the user chose to investigate a narrower value rather than abandon the fix or accept the MNN gap unmitigated.
- **Second attempt (committed):** Ran a local binary search over power-of-two `S` values against the same SECV-01 test: `S=2^17`, `2^16`, `2^15` all pass; `S=2^14` fails deterministically. Chose **S=2^15 (32768.0f)** -- one full power-of-two step of margin above the confirmed failure boundary -- giving a grid step 32x the original S=2^20 grid step and ~292x Phase 11's originally-measured `maxAbsDelta` (`1.043081283569336e-07`).
- Committed the S=2^15 fix to `quantization.cpp`/`.hpp`/`quantization_test.cpp` in the `SGProcessingManager` nested submodule (`bbe8621`), with pointer-bump commits through `SuperGenius` (`5574d5f2`) and the outer repo (`987d773`).
- `QuantizationTest` (7/7) and both SECV-01 cases (`MnnCorruptedModelStillDiverges`, `RenderWrongShaderConstantStillDiverges`) pass locally at S=2^15 -- confirmed both by this plan's own local rebuild and, independently, by 13-VERIFICATION.md's later re-run against the live source tree.
- Task 2 (checkpoint:human-action): the user physically rebuilt `capture_harness` on Mac and Windows against the S=2^15 commit and ran fresh MNN captures. The user reused their existing capture script rather than the plan's suggested `-refit` label, so the fresh files are labeled `xhw-mnn-float` (not `xhw-mnn-float-refit`) -- distinguishable from the original round's same-labeled pair only by timestamp (`_20260812T232347`/`_20260812T232430` vs the original round's `_20260812T212550`/`_20260812T212019`). The render fixture was also harmlessly recaptured, though not required (render already satisfies SC1 and was not re-diffed).
- These fresh `.cap` files were committed as part of Plan 13-05's Task 1 wrap-up (`5c3379a`, correctly attributed to this plan's Task 2 per the commit message), since they were produced hands-on by the user under this plan's checkpoint before Plan 13-05 diffed them.

## Task Commits

Each task was committed atomically (across 3 repo layers: nested `SGProcessingManager` submodule, `SuperGenius` submodule, outer repo):

1. **Task 1, first attempt (S=2^14): reverted, no commit** -- locally failed `Secv01CounterTest.MnnCorruptedModelStillDiverges`; fully reverted before any commit was made.
2. **Task 1, halt notice** -- `5ee651b` (docs, outer repo): "halt Task 1 -- S=2^14 grid widening regresses SECV-01 corrupted-model divergence"
3. **Task 1, second attempt (S=2^15): widen QuantizeFloatBuffer grid to empirically-safe S=2^15** -- `bbe8621` (feat, `SGProcessingManager` nested submodule)
4. **Task 1, pointer bump** -- `987d773` (chore, `SuperGenius` submodule): "bump SuperGenius pointer -- widened quantization grid"; corresponding outer-repo pointer bump -- `5574d5f2` (chore, `SuperGenius` submodule, points at `bbe8621`)
5. **Task 1, resolution record** -- `6156791` (docs, outer repo): "record Task 1 binary-search resolution and Task 2 checkpoint pending"
6. **Task 2: hands-on cross-machine re-capture (checkpoint:human-action)** -- no code commit (data-gathering only); fresh `.cap` files landed via `5c3379a` (feat, outer repo): "land fresh Mac+Windows re-captures with S=2^15 widened-grid quantization active" (committed at the tail end of Plan 13-05's Task 1, after 13-05 had already diffed the on-disk-but-not-yet-tracked files)

**Plan metadata:** this SUMMARY.md's own commit (docs, outer repo)

## Files Created/Modified
- `SuperGenius/SGProcessingManager/include/util/quantization.hpp` - Doc comment extended with the S=2^14-regresses-SECV-01 discovery and the S=2^15 choice's derivation (grid step, 32x/~292x margin ratios)
- `SuperGenius/SGProcessingManager/src/util/quantization.cpp` - `kScale` changed from `1048576.0f` (2^20) to `32768.0f` (2^15); all canonicalization branches (denormal/NaN/Inf/signed-zero) and `QuantizeByteBuffer` untouched
- `SuperGenius/SGProcessingManager/test/util/quantization_test.cpp` - `QuantizeFloatBufferRoundsToFixedGrid`'s echoed `kScale` updated to `32768.0f` to match
- `.planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/captures/xhw-mnn-float_Fuus-Mac-mini.local---macOS_20260812T232347.cap` - fresh Mac-origin MNN capture, S=2^15 fix active
- `.planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/captures/xhw-mnn-float_Mofu---Windows_20260812T232430.cap` - fresh Windows-origin MNN capture, S=2^15 fix active
- `.planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/captures/xhw-render_Fuus-Mac-mini.local---macOS_20260812T232352.cap` / `xhw-render_Mofu---Windows_20260812T232432.cap` - incidental, unrequested render-fixture duplicates (render already satisfies SC1; left on disk, not re-diffed)
- `.planning/workstreams/sgproc-render/STATE.md` - intermediate halt/resolution notes recording the S=2^14->S=2^15 pivot

## Decisions Made
- Abandoned the plan's literal S=2^14 target after confirming (twice, non-flaky) it deterministically regresses `Secv01CounterTest.MnnCorruptedModelStillDiverges` -- the corrupted-model fixture's artifactId collided bit-for-bit with the correct model's at that grid coarseness.
- Asked the user how to proceed rather than silently substituting a value or reverting to accept the MNN gap; the user chose to investigate a narrower value.
- Ran a local binary search over power-of-two `S` values (2^20/2^17/2^16/2^15/2^14) against the same SECV-01 test to find the widest confirmed-safe grid step, rather than guessing a single alternative value.
- Chose S=2^15 (32768.0f) -- one full power-of-two step of margin above the confirmed S=2^14 failure boundary -- as the widest value that keeps SECV-01's corrupted-model counter-test failing-closed while still substantially narrowing the MNN cross-hardware divergence.
- Accepted the user's reuse of their existing (non-`-refit`-labeled) capture script for Task 2, rather than insisting on the plan's literal `xhw-mnn-float-refit` label -- the fresh files are still unambiguously distinguishable by timestamp, and Plan 13-05 correctly identified and diffed the newest pair.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 4 - Architectural/blocking, escalated to user] S=2^14 (plan's literal target) regresses SECV-01**
- **Found during:** Task 1
- **Issue:** The plan's action text specified widening `kScale` to `16384.0f` (2^14). Implemented exactly as written, `QuantizationTest` passed 7/7 locally, but `processing_conformance_security_test`'s `Secv01CounterTest.MnnCorruptedModelStillDiverges` FAILED -- the corrupted-model fixture's post-quantization `artifactId` collided with the correct model's. Confirmed non-flaky by reverting and reproducing the failure a second time.
- **Fix:** This is a security-relevant regression, not a simple bug -- widening the tolerance far enough to mask a deliberately-corrupted model is exactly what SECV-01 exists to catch. Per Rule 4 (architectural/security-relevant decision), stopped and asked the user how to proceed rather than auto-fixing. The user chose to investigate a narrower value. A local binary search over power-of-two `S` values (2^17/2^16/2^15 all pass, 2^14 confirmed to fail deterministically) found S=2^15 as the widest safe value, which was then implemented and committed.
- **Files modified:** `SuperGenius/SGProcessingManager/src/util/quantization.cpp`, `include/util/quantization.hpp`, `test/util/quantization_test.cpp`
- **Verification:** `QuantizationTest` (7/7) and both SECV-01 cases pass locally at S=2^15; independently re-confirmed later by 13-VERIFICATION.md's verifier via a fresh rebuild-and-run against the live source tree.
- **Committed in:** `bbe8621` (SGProcessingManager), `5574d5f2`/`987d773` (pointer bumps), `5ee651b`/`6156791` (STATE.md record of the halt and resolution)

---

**Total deviations:** 1 (Rule 4 - escalated to user rather than auto-fixed, since it involved a security-tolerance tradeoff the plan itself did not anticipate)
**Impact on plan:** The plan's literal S=2^14 target was not viable; S=2^15 was substituted after empirical investigation and explicit user sign-off. This changed the plan's specific numeric constant and margin-ratio citations (64x/~585x -> 32x/~292x) but not its objective (widen the grid to reduce cross-hardware MNN divergence without regressing SECV-01).

## Issues Encountered
- The plan's Task 2 checkpoint text suggested labeling fresh captures `xhw-mnn-float-refit`; the user instead reused their existing capture script, producing a second `xhw-mnn-float_*.cap` pair sharing the original round's label prefix, distinguishable only by timestamp. This was not a blocker -- Plan 13-05 correctly identified and diffed the newest (correct) pair by timestamp, as documented in 13-05-SUMMARY.md's own deviations section.
- This plan's own `<output>` instruction ("Create 13-04-SUMMARY.md when done") was not fulfilled at the time -- Task 2's checkpoint returned control to the user, and execution proceeded directly into Plan 13-05 without a continuation agent producing this file. The underlying work (both tasks) was genuinely complete and committed; only this completion record was missing, until this gap-closure round produced it retroactively.

## User Setup Required

None beyond Task 2's own hands-on checkpoint (already completed by the user: rebuilding `capture_harness` on Mac + Windows against the S=2^15 commit and running fresh MNN captures).

## Next Phase Readiness
- Plan 13-05's `capture_diff` run and `13-SCOPE-BOUNDARY.md` SC1 Refit section both depend on this plan's fresh `xhw-mnn-float_*.cap` pair (`_20260812T232347`/`_20260812T232430`) and its S=2^15 fix -- both already consumed and reported on (see `13-05-SUMMARY.md`).
- VALD-01/SC1's MNN gap is substantially narrowed by this plan's fix (12/15 -> 1/15 divergent chunks, per Plan 13-05's diff) but not fully closed -- `chunkHashesMatch[10]` remains false. This residual gap is tracked honestly in `13-SCOPE-BOUNDARY.md` and `REQUIREMENTS.md`/`ROADMAP.md`, not resolved by this plan.

---
*Phase: 13-re-validation-scope-boundary-documentation*
*Completed: 2026-08-12*

## Self-Check: PASSED

- FOUND: `SuperGenius/SGProcessingManager/include/util/quantization.hpp` (kScale doc comment updated)
- FOUND: `SuperGenius/SGProcessingManager/src/util/quantization.cpp` (kScale = 32768.0f)
- FOUND: `SuperGenius/SGProcessingManager/test/util/quantization_test.cpp` (echoed kScale = 32768.0f)
- FOUND: `.planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/captures/xhw-mnn-float_Fuus-Mac-mini.local---macOS_20260812T232347.cap`
- FOUND: `.planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/captures/xhw-mnn-float_Mofu---Windows_20260812T232430.cap`
- FOUND commit: `bbe8621` (SGProcessingManager submodule)
- FOUND commit: `5574d5f2` (SuperGenius submodule)
- FOUND commit: `987d773` (SuperGenius submodule pointer bump)
- FOUND commit: `5ee651b` (outer repo, halt notice)
- FOUND commit: `6156791` (outer repo, resolution record)
- FOUND commit: `5c3379a` (outer repo, fresh captures landed)
