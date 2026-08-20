---
phase: 17-render-path-cross-hardware-tolerance
verified: 2026-08-20T19:00:00Z
status: passed
score: 5/5 must-haves verified
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: "4/5 (5th truth verified as 'honestly reported' but its underlying requirement RENDTOL-02 was not fully satisfied)"
  gaps_closed:
    - "RENDTOL-02: blending's residual cross-hardware divergence — now closed via a new raw-buffer numeric-tolerance check (capture_diff --byte-quant-mode) that reuses production's IsByteChunkWithinTolerance unmodified, independently re-run and reproduced byte-for-byte against blending's already-captured Round 2 data (withinTolerance=true, byteQuantMode=6, raw maxAbsDelta=1.0)."
    - "REQUIREMENTS.md's RENDTOL-01/RENDTOL-02 stale annotations — both rows now read complete with accurate, non-stale wording; confirmed by direct read, not just SUMMARY claim."
  gaps_remaining: []
  regressions: []
---

# Phase 17: Render-Path Cross-Hardware Tolerance Verification Report (Re-Verification)

**Phase Goal:** The render path gains three non-trivial fixtures (texturing, blending, and lighting — MSAA excluded per D-03's architectural hard-block) that actually exercise floating-point-heavy render computation, and a real, schema-configurable tolerance mechanism for its output comparison — replacing `QuantizeByteBuffer`'s current byte-identity no-op — closing the untested risk v2.2's STATE.md flagged: that the render path's byte-identity claim was only ever measured against a near-zero-computation 8x8 solid-color fixture.
**Verified:** 2026-08-20
**Status:** passed
**Re-verification:** Yes — after gap closure (17-09-PLAN.md/17-09-SUMMARY.md)

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Three new render fixture definitions exist (texturing, blending, lighting), each producing more FP computation than the 8x8 happy-path fixture | ✓ VERIFIED (regression check) | `SuperGenius/test/src/processing_dispatch/{lighting,blending,texturing}-fixture-definition.json` all still present on disk, unmodified by this gap-closure cycle (17-09 touched no fixture/shader files). Carried forward from prior VERIFICATION.md's full inspection. |
| 2 | Each fixture, run cross-machine (Mac + Windows), produces real non-zero raw divergence | ✓ VERIFIED (regression check) | `captures/diff-render-blending.json` (`maxAbsDelta=1.0`) and the lighting/texturing zero-divergence captures are unchanged on disk — re-read, byte-identical to prior verification's citation. |
| 3 | A schema-configurable tolerance parameter governs `QuantizeByteBuffer`, with silent fallback to byte-identity when unconfigured | ✓ VERIFIED (regression check) | `quantization.cpp`/`quantization.hpp` confirmed via `git log` in the `SGProcessingManager` submodule to be last touched at `a71bfec` (Phase 14) — no commit from Wave 8/17-09 touches either file. Byte-identity fallback logic unchanged. |
| 4 | RENDTOL-02's tolerance mechanism is proven independently against real cross-hardware capture data from EACH of RENDTOL-01's three fixtures (lighting/texturing via strict hash-match, blending via a new numeric-tolerance fallback) | ✓ VERIFIED | Independently re-ran `capture_diff --element-type uint8 --byte-quant-mode 6` against the actual on-disk Round 2 blending `.cap` files (not the SUMMARY's claim) — output reproduced byte-for-byte identical to the committed `captures/diff-render-blending-r2-rawtolerance.json`: `rawToleranceCheck.byteQuantMode=6`, `maxAbsDelta=1.0`, `withinTolerance=true`. Confirmed the pre-existing strict fields in the same file (`contentHashMatch=false`, `maxAbsDelta=64.0`) are byte-for-byte unchanged from the original `diff-render-blending-r2.json`. Lighting/texturing's strict hash-match evidence (`diff-render-{lighting,texturing}-r2.json`, `contentHashMatch=true`) unchanged since prior verification. |
| 5 | A SECV-01-style counter-test proves each fixture's tolerance is not too loose to mask deliberate corruption | ✓ VERIFIED (regression check) | `secv01_render_{lighting,blending,texturing}_counter_test.cpp` all still present, unmodified by 17-09. Carried forward from prior verification's full inspection. |

**Score:** 5/5 truths verified. Truth 4 (previously the sole gap) is now fully closed and independently reproduced against the real evidence file, not merely re-asserted by SUMMARY.md.

### Gap-Closure Mechanism Integrity (D-11's explicit constraint)

Verified via `git log`/`git show` inside the `SGProcessingManager` submodule (not trusting the SUMMARY's "no edits" claim):

| File | Last commit touching it | Touched by 17-09? |
|------|--------------------------|--------------------|
| `SGProcessingManager/src/util/quantization.cpp` / `include/util/quantization.hpp` | `a71bfec` (Phase 14) | No |
| `SGProcessingManager/src/util/diff_utils.cpp` / `include/util/diff_utils.hpp` | `62b2735` (17-09) | Yes — additive only (28+14 lines inserted, 0 deleted; new function `IsByteChunkWithinToleranceForMode` appended after the existing `IsByteChunkWithinTolerance`, whose body is byte-for-byte unchanged) |
| `SGProcessingManager/tools/capture/capture_diff.cpp` | `bfabebf` (17-09) | Yes — additive only (67 insertions, 1 deletion which is a one-line context edit for the usage string; new CLI flag + new nested JSON object, all pre-existing report fields/logic untouched) |
| `SuperGenius/src/processing/processing_validation_core.cpp` (`ValidateResults`/`AttemptToleranceFallback`) | `097ec484` (Phase 15) | No |

`IsByteChunkWithinTolerance`'s own function body confirmed unchanged via `git diff <phase-15-commit> HEAD -- diff_utils.cpp` showing zero delta inside that function. D-11's explicit "do not modify production tolerance code" constraint is honored.

### Behavioral Spot-Checks (independent re-execution, not SUMMARY trust)

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| 3 new `IsByteChunkWithinToleranceForMode` unit tests actually pass | `diff_utils_test.exe --gtest_filter="*IsByteChunkWithinToleranceForMode*"` (binary timestamp matches the 17-09 commit, confirmed pre-built, no rebuild needed) | `[ PASSED ] 3 tests` | ✓ PASS |
| Full `DiffUtilsTest` suite has no regressions | `diff_utils_test.exe --gtest_filter="DiffUtilsTest.*"` (single full run of this one test binary, not the whole project suite) | `[ PASSED ] 21 tests` | ✓ PASS |
| `capture_diff --byte-quant-mode 6` reproduces the committed evidence file exactly | Re-ran `capture_diff.exe --a <Mac Round-2 blending .cap> --b <Windows Round-2 blending .cap> --element-type uint8 --byte-quant-mode 6` against the real on-disk `.cap` files, diffed output against the committed JSON | Byte-identical output: `withinTolerance=true`, `byteQuantMode=6`, `maxAbsDelta=1.0` (raw); `contentHashMatch=false`, `maxAbsDelta=64.0` (quantized, unchanged) | ✓ PASS |
| Out-of-range `--byte-quant-mode` fails closed | `capture_diff.exe ... --byte-quant-mode 99` | `capture_diff: --byte-quant-mode must be an integer in [0,8], got "99"`, exit code 1 | ✓ PASS |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `captures/diff-render-blending-r2-rawtolerance.json` | New raw-tolerance evidence file | ✓ VERIFIED | Read directly; contains both the unchanged strict fields and the new `rawToleranceCheck` object exactly as claimed; independently reproduced by re-running `capture_diff` |
| `SGProcessingManager/include/util/diff_utils.hpp` / `.cpp` (`IsByteChunkWithinToleranceForMode`) | New additive wrapper | ✓ VERIFIED | Exists, delegates unmodified to `IsByteChunkWithinTolerance`, confirmed via `git show` diff and passing unit tests |
| `SGProcessingManager/tools/capture/capture_diff.cpp` (`--byte-quant-mode`) | New CLI flag + `rawToleranceCheck` JSON | ✓ VERIFIED | Confirmed via `git show` diff (additive) and independent re-execution |
| `17-TOLERANCE-RESULTS.md` (Gap Closure Addendum) | Honest side-by-side documentation | ✓ VERIFIED | Section exists, states unchanged strict number (64.0/false) alongside new raw-tolerance number (1.0/true), does not reinterpret either |
| `REQUIREMENTS.md` (RENDTOL-01/02 rows) | Accurate, non-stale completion state | ✓ VERIFIED | Both `[x]`, wording cites 17-TOLERANCE-RESULTS.md's Gap Closure Addendum, does not erase the still-true strict-hash mismatch; Traceability table row updated to "Complete — numeric-tolerance fallback proven" |
| `ROADMAP.md` (Phase 17 section) | 9/9 plans, Wave 8/17-09 entry, honest SC4 outcome | ✓ VERIFIED | Milestone bullet, SC4 outcome text, Plans count (9/9), Wave 8 heading with `[x] 17-09-PLAN.md`, and Progress table row all confirmed present and accurate via direct grep/read |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| Fixture's declared `byteQuantMode=6` | new `capture_diff --byte-quant-mode` CLI flag | `IsByteChunkWithinToleranceForMode` wrapper | WIRED | Confirmed by independent re-execution producing the exact evidence file |
| `IsByteChunkWithinToleranceForMode` | `IsByteChunkWithinTolerance` (production, unmodified) | Direct delegation, single-entry `Parameter` vector construction | WIRED, VERIFIED UNMODIFIED | `git show`-diffed; production function body byte-identical since Phase 15 |
| Round 2 `.cap` files' `preQuantizeBytes` | new raw-tolerance check | `capture_diff` reads `lastRecordA/B.preQuantizeBytes` | WIRED | No new hardware capture round used; same `.cap` files from Wave 7 re-read, confirmed via file listing and re-execution |
| `17-TOLERANCE-RESULTS.md` Gap Closure Addendum | `REQUIREMENTS.md` / `ROADMAP.md` | Direct citation | WIRED, VERIFIED ACCURATE | Cross-checked wording in all three documents — consistent, no contradiction |

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|--------------|-------------|--------|----------|
| RENDTOL-01 | 17-01 through 17-05, 17-08 | Three non-trivial render fixtures exist, each exercising real FP-heavy computation | ✓ SATISFIED | Unchanged since prior verification; regression-checked, still present and non-stub |
| RENDTOL-02 | 17-01 through 17-09 | Real schema-configurable tolerance mechanism, proven against real cross-hardware data from each of the 3 fixtures | ✓ SATISFIED | Now fully closed: lighting/texturing via strict hash-match (unchanged), blending via the new, independently-reproduced raw-tolerance check |

Cross-referenced requirement IDs across all 9 plans' frontmatter (`grep -A2 "^requirements:"` on every `17-0*-PLAN.md`): every plan declares only `RENDTOL-01` and/or `RENDTOL-02`. Both IDs are present in REQUIREMENTS.md's v2.3 section and Traceability table, both marked complete. No orphaned requirement IDs found.

### Anti-Patterns Found

None. Scanned all files modified/created by 17-09 (`diff_utils.hpp`, `diff_utils.cpp`, `diff_utils_test.cpp`, `capture_diff.cpp`) for `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER` — zero matches. No debt markers introduced.

### Probe Execution

SKIPPED (no `scripts/*/tests/probe-*.sh` probes found in this repository, and none declared in this phase's PLAN/SUMMARY files) — same as prior verification.

### Human Verification Required

None. All must-haves, including the previously-open gap, were resolvable via direct codebase inspection, independent test execution, and independent re-running of the evidence-producing tool against real on-disk capture files.

### Gaps Summary

No gaps remain. Both gaps from the prior `gaps_found` verification are closed:

1. **RENDTOL-02's blending residual gap** — closed via the user's chosen numeric-tolerance-fallback path (17-CONTEXT.md D-10), implemented per D-11's grounded finding: `capture_diff` now applies the same raw-buffer tolerance bound (`IsByteChunkWithinTolerance`) production's `ValidateResults`/`AttemptToleranceFallback` already uses, against blending's already-captured Round 2 `preQuantizeBytes` — no new hardware capture round. Independently re-executed by this verifier (not just SUMMARY-trusted): reproduces `withinTolerance=true`, `byteQuantMode=6`, raw `maxAbsDelta=1.0` exactly. The pre-existing strict quantized-hash mismatch (`contentHashMatch=false`, `maxAbsDelta=64.0`) is confirmed byte-for-byte unchanged in the same evidence file and in `17-TOLERANCE-RESULTS.md` — never silently overwritten or reinterpreted as passing. Confirmed via `git log`/`git show` in the `SGProcessingManager` submodule that `QuantizeByteBuffer`, `IsByteChunkWithinTolerance`, `IsFloatChunkWithinTolerance`, and `ProcessingValidationCore::ValidateResults`/`AttemptToleranceFallback` were not modified by this plan — the two touched files (`diff_utils.*`, `capture_diff.cpp`) received purely additive changes.
2. **REQUIREMENTS.md's stale annotations** — confirmed resolved by direct read: RENDTOL-01 and RENDTOL-02 both show `[x]`, accurate non-stale wording, and the Traceability table row correctly reads "Complete — numeric-tolerance fallback proven (17-TOLERANCE-RESULTS.md Gap Closure Addendum)". ROADMAP.md's Phase 17 section independently confirmed to show 9/9 plans, a Wave 8/17-09 entry, and an honest SC4 outcome that does not erase the historical fact that the strict quantized-hash comparison for blending still mismatches.

Phase goal fully achieved: three non-trivial, non-stub render fixtures (texturing, blending, lighting) exist and are cross-hardware capture-proven; a real, schema-configurable tolerance mechanism (`byteQuantMode`/`QuantizeByteBuffer`, pre-existing since Phase 14) governs the render path's output comparison and is now proven — for all three fixtures, not two of three — against real cross-hardware capture data, closing the untested risk v2.2's STATE.md flagged.

---

*Verified: 2026-08-20*
*Verifier: Claude (gsd-verifier)*
