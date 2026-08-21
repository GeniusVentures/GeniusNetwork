---
phase: 19-validation-re-verification
captured: 2026-08-21
status: CLOSED -- ValidateResults/AttemptToleranceFallback genuinely engages for chunk 10 and resolves it as a tolerant match; no subtask invalidated
---

# Phase 19: Validation Re-Verification — Results

**Phase Goal:** Determine, with real evidence rather than assumption, whether Phase 15's `ProcessingValidationCore::ValidateResults` tolerance-fallback mechanism (XNODE-02) actually closes VALD-01's original MNN float32 gap — Phase 13's finding that 1 of 15 chunk hashes (chunk 10, `maxAbsDelta = 3.0517578125e-05`, exactly one S=2^15 grid step) still diverges cross-hardware after quantization — and document the outcome honestly, whichever way it lands.

## Fixture Used (D-01-REVISED)

D-01 originally specified reusing Phase 13's exact archived `.cap` pair (`xhw-mnn-float_Fuus-Mac-mini.local---macOS_20260812T232347.cap` / `xhw-mnn-float_Mofu---Windows_20260812T232430.cap`). During this phase's execution, that pair was found to be **unreadable by any current tooling**: `sgns::sgproccapture::DeserializeCaptureFile()` returned `false` for both files, independently reproduced with the unmodified `capture_diff` CLI (the same tool that produced Phase 13's own published numbers). Byte-level analysis confirmed the root cause: `SGProcessingManager` commit `bf7e694` ("fix(17): read MANIFEST_V2_SERIALIZED_SIZE in DeserializeCaptureFile, not the stale pre-ARTF-10 constant", 2026-08-19) made the parser unconditionally require the newer, larger post-Phase-16 manifest region, silently breaking backward compatibility with every pre-Phase-16 `.cap` file (Phase 13's captures included) — a real, previously-undiscovered regression unrelated to this phase's own work, and out of this phase's scope to fix (per D-04, no production code is modified).

Presented to the user as a three-way decision (document as still-open / fix the parser / take a fresh capture); the user chose a **fresh 2-machine capture**. The re-run used:

- `mnn-float_Fuus-Mac-mini.local---macOS_20260821T221542.cap` (Mac)
- `mnn-float_Mofu---Windows_20260821T221735.cap` (Windows)

both under `.planning/workstreams/sgproc-render/phases/19-validation-re-verification/captures/`, captured live on the same two machines (Mac `Fuus-Mac-mini.local`, Windows `Mofu`) using the current `capture_harness` tool, producing new-format files that parse cleanly under current tooling. D-02 (direct-call harness style), D-03 (all-15-chunks coverage), and D-04 (no production-code fix) are all unaffected by this substitution.

An independent `capture_diff` cross-check of this fresh pair (`.../captures/diff-mnn-float-vald02-fresh.json`) confirms it reproduces **the exact same signature** as Phase 13's original finding — itself a notable, citable fact given this is a wholly new, independently-captured pair on different dates:

```json
"chunkHashesMatch": [true, true, true, true, true, true, true, true, true, true, false, true, true, true, true],
"contentHashMatch": true,
"chunkDiffs[10]": {
  "maxAbsDelta": 3.0517578125e-05,
  "maxRelDelta": 0.00015477479610126466,
  "maxUlpDistance": 2048,
  "percentExceedingThreshold": 1.5625
}
```

This is an exact numeric match to Phase 13's original `diff-mnn-float-refit-chunkdiag.json` chunk-10 diagnostic — the same one-grid-step rounding-boundary divergence reproduces reliably across an independent capture session five days later.

## Self-Check (Task 1, `Vald02ChunkHashSelfCheckMatchesPublishedRefit`)

This test's own `ReadFileBytes` + `DeserializeCaptureFile` + per-chunk `std::equal` comparison over the fresh fixture pair produced **exactly** the published pattern: all 15 `chunkHashesMatch` entries `true` except index 10, which is `false`. This matches both Phase 13's historical `diff-mnn-float-refit.json` and this phase's own fresh `diff-mnn-float-vald02-fresh.json` cross-check. Verbatim ctest result:

```
[ RUN      ] ProcessingValidationCoreTest.Vald02ChunkHashSelfCheckMatchesPublishedRefit
[       OK ] ProcessingValidationCoreTest.Vald02ChunkHashSelfCheckMatchesPublishedRefit (3 ms)
```

This proves the test's own file-parsing produces the identical chunk-hash-match pattern before any conclusion is drawn from `ValidateResults`' behavior.

## Chunk 10 Tolerance Cross-Check (Task 1, direct `IsFloatChunkWithinTolerance` call)

Independently of `ValidateResults`, chunk 10's two 256-byte quantized slices (`captureA.rawRecordsPerArtifact[0][10].quantizedBytes` / `captureB...`) were fed directly into `sgns::sgprocmanagerdiff::IsFloatChunkWithinTolerance` — a second, independent code path proving the test's own byte extraction/slicing is correct regardless of `ValidateResults`' internal uniform-division slicing.

- Measured `statsOut.maxAbsDelta`: **3.0517578125e-05** (asserted via `ASSERT_DOUBLE_EQ`, matching both Phase 13's original diagnostic and this phase's fresh `diff-mnn-float-vald02-fresh.json` cross-check exactly)
- D-03 tolerance bound: `2.0 / 32768.0 = 6.103515625e-05` (quantization.hpp's shipped S=2^15 constant)
- `3.0517578125e-05 <= 6.103515625e-05` → **within tolerance**, `directWithinTolerance == true`

## ValidateResults Full-Fixture Outcome (Task 1, `Vald02FullFixtureValidateResultsToleranceOutcome`)

All 15 chunks of the fresh fixture were fed through the real, unmodified 5-arg `ValidateResults`/`AttemptToleranceFallback` production code path (via public `SGProcessing::SubTaskCollection`/`SubTaskResult` protobuf objects — `ChunkContribution` is a private struct and cannot be constructed directly). Chunks 0-9/11-14 hash-matched trivially (no fallback invoked); chunk 10's genuine hash mismatch triggered `AttemptToleranceFallback`, which fetched both subtasks' reconstructed output blobs, sliced out chunk 10's 256-byte range via the exact same uniform-division logic exercised above, and ran `IsFloatChunkWithinTolerance` internally.

Verbatim ctest console output (captured with `spdlog::set_level(debug)` raised inside this one test, so the production `AttemptToleranceFallback` debug log line is visible — no production code change, test-file-scoped logging verbosity only):

```
[ RUN      ] ProcessingValidationCoreTest.Vald02FullFixtureValidateResultsToleranceOutcome
[2026-08-21 18:24:40][debug][ProcessingValidationCore] AttemptToleranceFallback: maxAbsDelta=3.0517578125e-05 maxRelDelta=0.00015477479610126466 withinTolerance=true
[       OK ] ProcessingValidationCoreTest.Vald02FullFixtureValidateResultsToleranceOutcome (4 ms)
```

This is the actual, freshly-observed outcome — not inferred, not assumed:

- `validate_res.has_error()` → **false**
- `invalidSubTaskIds.empty()` → **true**
- `AttemptToleranceFallback`'s own internal `maxAbsDelta`/`maxRelDelta` values are bit-for-bit identical to the independent direct cross-check above and to the fresh `capture_diff` cross-check, confirming `ValidateResults`' internal slicing extracted exactly the same bytes as the direct extraction.

Full 7-test ctest run (5 pre-existing `ProcessingValidationCoreTest` cases + 2 new `Vald02*` cases), verbatim:

```
[==========] Running 7 tests from 1 test suite.
[----------] 7 tests from ProcessingValidationCoreTest
[ RUN      ] ProcessingValidationCoreTest.NoResultsForSubtaskStillFails
[       OK ] ProcessingValidationCoreTest.NoResultsForSubtaskStillFails (0 ms)
[ RUN      ] ProcessingValidationCoreTest.IdenticalHashesStillPass
[       OK ] ProcessingValidationCoreTest.IdenticalHashesStillPass (0 ms)
[ RUN      ] ProcessingValidationCoreTest.DifferingHashesNoToleranceCapabilityFail
[       OK ] ProcessingValidationCoreTest.DifferingHashesNoToleranceCapabilityFail (0 ms)
[ RUN      ] ProcessingValidationCoreTest.DifferingHashesWithinToleranceStillPass
[       OK ] ProcessingValidationCoreTest.DifferingHashesWithinToleranceStillPass (0 ms)
[ RUN      ] ProcessingValidationCoreTest.DifferingHashesExceedsToleranceFail
[       OK ] ProcessingValidationCoreTest.DifferingHashesExceedsToleranceFail (0 ms)
[ RUN      ] ProcessingValidationCoreTest.Vald02ChunkHashSelfCheckMatchesPublishedRefit
[       OK ] ProcessingValidationCoreTest.Vald02ChunkHashSelfCheckMatchesPublishedRefit (3 ms)
[ RUN      ] ProcessingValidationCoreTest.Vald02FullFixtureValidateResultsToleranceOutcome
[2026-08-21 18:24:40][debug][ProcessingValidationCore] AttemptToleranceFallback: maxAbsDelta=3.0517578125e-05 maxRelDelta=0.00015477479610126466 withinTolerance=true
[       OK ] ProcessingValidationCoreTest.Vald02FullFixtureValidateResultsToleranceOutcome (4 ms)
[----------] 7 tests from ProcessingValidationCoreTest (9 ms total)
[  PASSED  ] 7 tests.
100% tests passed, 0 tests failed out of 1
```

## Classification

**CLOSED.**

Phase 15's `ProcessingValidationCore::ValidateResults`/`AttemptToleranceFallback` mechanism genuinely engages for chunk 10 and resolves it as a tolerant match — not because the gap was already absent (chunk 10's raw hash mismatch is real and reproducible, confirmed independently three separate ways this session: the self-check test's `std::equal` comparison, the direct `IsFloatChunkWithinTolerance` cross-check, and a fresh `capture_diff` run), but because the production tolerance-fallback code path, unmodified since Phase 15 shipped, correctly measures chunk 10's real divergence (`maxAbsDelta=3.0517578125e-05`) as within the D-03 bound (`2.0/32768.0=6.103515625e-05`) and treats it as a match. `ValidateResults` reports no error and invalidates zero subtasks for the full 15-chunk fixture. This is the honest, evidence-backed answer VALD-02 asked for: the mechanism works as designed against the real fixture that originally exposed the gap.

This closes VALD-01's residual 1/15-chunk MNN float32 finding for the purposes of `ValidateResults`' consumption of chunk hashes — the underlying cross-hardware numeric divergence (one S=2^15 grid-step rounding-boundary tie-break, per 13-SCOPE-BOUNDARY.md's own diagnostic) still physically exists and is not eliminated; what closes is the question this phase asked, namely whether the *comparison mechanism* correctly absorbs it. No production code (`quantScale`, `IsFloatChunkWithinTolerance`'s bound formula, `QuantizeFloatBuffer`) was modified to reach this result, per D-04.

## Note on the D-01-REVISED Capture-Format Regression

Independent of VALD-02's own outcome, this phase surfaced a real, previously-undiscovered regression: `DeserializeCaptureFile` (SGProcessingManager, `tools/capture/capture_file_format.cpp`) can no longer parse any `.cap` file captured before Phase 16's manifest schema evolution (ARTF-09/10), because Phase 17's own fix (`bf7e694`) made it unconditionally require the newer, larger manifest region with no backward-compatible fallback. This affects every `.cap` file in `13-re-validation-scope-boundary-documentation/captures/` and would affect any future attempt to re-analyze that phase's archived forensic data with current tooling. Fixing this is out of this phase's scope (D-04: no production code modified) and is not addressed here beyond this note — flagged for a future phase to pick up if Phase 13's archived captures need to be read again.
