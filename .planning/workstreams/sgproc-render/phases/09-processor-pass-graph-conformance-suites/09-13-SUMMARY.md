---
phase: 09-processor-pass-graph-conformance-suites
plan: 13
subsystem: testing
tags: [mnn, inference, string-processor, conformance-test, cpp, vulkan]

# Dependency graph
requires:
  - phase: 09-processor-pass-graph-conformance-suites (plans 01, 02, 06)
    provides: StringInputProcessingTest (pre-existing) and StringConformanceProcessingTest (added by plan 09-02), both exercising MNN_String
provides:
  - "Gap 5 (TEST-04) closure: processing_processor_mnn_string.cpp's resize decision now driven by the job's schema-declared maxLength parameter instead of a hardcoded literal or the arbitrary elementSize()<=4 heuristic"
  - "runSession() return code checked; a failed session now surfaces as a structured ProcessingResult.error instead of reading a garbage/unresized tensor"
  - "processing_datatypes_test reports 0 failures across all 18 MNN processor types (41/41 tests) after the fix, confirming no regression outside the touched file"
affects: [processing_processor_mnn_string, processing_datatypes_test, mnn-string-processor]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Schema-parameter lookup by name inside a processor's StartProcessing() (find_param-by-name over the job's parameters vector), mirroring the existing tokenizerMode/vocabUri pattern in ProcessingManager.cpp's CheckProcessValidity()"

key-files:
  created: []
  modified:
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_string.cpp

key-decisions:
  - "Derived the per-tensor resize length from the job's schema-declared \"maxLength\" parameter (16 for the tiny embedding model, 128 for the legacy BERT model) rather than the plan's literally-specified tokenIds.size() — see Deviations for why the literal plan text does not actually pass its own acceptance test"
  - "Left the runSession()/ProcessingResult.error hardening exactly as specified in the plan (Task 1, fixes #3/#4) — that part of the plan's diagnosis was correct and required no adjustment"

requirements-completed: [TEST-04]

coverage:
  - id: D1
    description: "StringInputProcessingTest (legacy bert-tiny.mnn, 128-length multi-input model) and StringConformanceProcessingTest (tiny embedding model, fixed 16-length single input) both pass without a reshape/shape-inference error"
    requirement: "TEST-04"
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/processing_datatypes/processing_datatypes_test.cpp#ProcessingDatatypesTest.StringInputProcessingTest"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/processing_datatypes/processing_datatypes_test.cpp#ProcessingDatatypesTest.StringConformanceProcessingTest"
        status: pass
    human_judgment: false
  - id: D2
    description: "No regression across the other 17 MNN processor conformance cases in processing_datatypes_test, and all 7 processing_conformance_* binaries remain green"
    requirement: "TEST-04"
    verification:
      - kind: unit
        ref: "processing_datatypes_test.exe (full suite) — 41/41 tests passed, 0 failures"
        status: pass
      - kind: integration
        ref: "ctest -R processing_datatypes_test|processing_conformance_(schema|executor|hashing|migration|cancellation|capability|regression)_test -V — 8/8 binaries passed, 100% tests passed"
        status: pass
    human_judgment: false

duration: 25min
completed: 2026-08-06
status: complete
---

# Phase 09 Plan 13: MNN String Processor Reshape Fix (Gap 5) Summary

**Schema-driven `maxLength` parameter (16 vs. 128, read from the job's declared parameters) replaces a hardcoded resize literal in `MNN_String::Process()`, fixing the tiny embedding model's reshape error while keeping the legacy BERT model passing, plus a checked `runSession()` return code that now surfaces failures as structured `ProcessingResult.error` instead of reading garbage tensor memory.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-08-07T00:24:00Z (approx., following 09-12 completion)
- **Completed:** 2026-08-07T00:46:01Z
- **Tasks:** 2 (1 code fix, 1 verification-only regression sweep)
- **Files modified:** 1 (`processing_processor_mnn_string.cpp`)

## Accomplishments
- Fixed the pre-existing, confirmed production bug (Gap 5 / TEST-04) in `MNN_String::Process()`: the per-tensor resize target is now read from the job's schema-declared `maxLength` parameter (16 for the new tiny embedding model, 128 for the legacy multi-input BERT model) instead of a single hardcoded `128` literal, and the resize condition changed from an arbitrary `elementSize() <= 4` threshold to `elementSize() != maxLength` so it reliably resizes to the correct value regardless of a tensor's initial/dynamic shape.
- Hardened `runSession()`'s previously-discarded `MNN::ErrorCode` return: a failed session now logs the error code and returns an empty sentinel `Tensor` instead of letting the caller read output data from an unresized session; `StartProcessing()` converts that sentinel into a structured `ProcessingResult.error` instead of dereferencing a degenerate tensor.
- Verified via a full regression sweep that no other MNN processor type regressed: `processing_datatypes_test` reports 41/41 tests passing (all 18 MNN types, including both `StringInputProcessingTest` and `StringConformanceProcessingTest`), and all 7 `processing_conformance_*` binaries (schema, executor, hashing, migration, cancellation, capability, regression) remain green — 8/8 binaries, 100% tests passed via `ctest`.

## Task Commits

Each task was committed atomically (multi-repo: fix committed in the `SGProcessingManager` submodule, then pointer bumps propagated up through `SuperGenius` and the top-level repo):

1. **Task 1: Fix the per-tensor resize decision and harden runSession()'s error handling**
   - `SGProcessingManager@bc74bc0` — `fix(09-13): schema-driven maxLength fixes MNN_String reshape error (Gap 5)`
   - `SuperGenius@95e46966` — `docs(09-13): bump SGProcessingManager pointer — schema-driven maxLength fix (Gap 5)`
   - `GeniusNetwork@71c5172` — `docs(09-13): bump SuperGenius pointer — schema-driven maxLength fix (Gap 5)`
2. **Task 2: Full regression sweep confirming no other MNN processor case regressed** — verification-only, no code changes; see Performance/Accomplishments for results.

**Plan metadata:** (this commit) — `docs(09-13): complete MNN string processor reshape fix plan`

## Files Created/Modified
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_string.cpp` — `StartProcessing()` now reads the job's `maxLength` schema parameter (falling back to 128 if absent/invalid) to compute `resizeLen`, the exact sequence length each model's compiled graph expects; guards the `Process()` return against a null/zero-size tensor and converts that into a structured `ProcessingResult.error`. `Process()`'s per-tensor resize condition changed from `elementSize() <= 4` to `elementSize() != maxLength`; `runSession()`'s return code is now captured and checked, returning an empty sentinel `Tensor` on failure instead of proceeding to read output data.

## Decisions Made
- Derived `resizeLen`/`maxLength` from the job's schema-declared `maxLength` parameter (read via a `find-by-name` loop over the `parameters` vector, mirroring the existing `tokenizerMode`/`vocabUri` lookup pattern already used in `ProcessingManager.cpp`'s `CheckProcessValidity()`) rather than from `tokenIds.size()` as the plan's literal action text specified. See Deviations below for the empirical reason this was necessary.
- Left the `runSession()` error-code check and the `ProcessingResult.error` guard exactly as the plan specified (Task 1 fixes #3/#4) — no adjustment needed there.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Plan's literal `resizeLen = tokenIds.size()` fix does not pass its own acceptance test; corrected to a schema-parameter-driven `maxLength`**
- **Found during:** Task 1, immediately after applying the plan's literally-specified fix and running the verification command
- **Issue:** The plan's action text instructs computing `resizeLen` from the actual parsed token count (`std::max(1, tokenIds.size())`), on the stated assumption that the conformance fixture's input text tokenizes to exactly 16 tokens (matching the tiny embedding model's fixed-shape `Linear(128, 4)` layer, compiled for `seq_len(16) * embed_dim(8) = 128`). Empirically, `StringConformanceProcessingTest` and the legacy `StringInputProcessingTest` both source their input from the same `test_input.txt` fixture, which tokenizes to 12 tokens, not 16. Applying the plan's literal fix made `StringInputProcessingTest` pass (12 tokens happens to work for the flexible-length legacy BERT model) but `StringConformanceProcessingTest` still failed identically to before ("Reshape error: 96 -> 0", `runSession` ErrorCode 3) because resizing the tiny model's single input to 12 (12*8=96 flattened features) still doesn't match its fixed 128-input-feature FC layer.
- **Fix:** Instead of deriving the resize length from the actual token count, read the job's already-present schema-declared `maxLength` parameter (`16` for `string-conformance-definition.json`, `128` for `string-processing-definition.json` — both fixtures already declare this parameter; it was simply never read by the processor). This generalizes correctly: the tiny model always resizes to exactly the fixed length its compiled graph expects (padding/truncating `tokenIds` via the existing fill-loop's `(i < tokenIds.size()) ? tokenIds[i] : 0` bounds check), and the legacy BERT model continues to resize to its own declared 128, matching its pre-fix (and intended) behavior. The resize-condition improvement (`elementSize() != maxLength` instead of `<= 4`) and the `runSession()`/`ProcessingResult.error` hardening from the plan's Task 1 fixes #3/#4 are unchanged and still fully in effect.
- **Files modified:** `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_string.cpp`
- **Verification:** Rebuilt `processing_datatypes_test` and ran `--gtest_filter=ProcessingDatatypesTest.StringInputProcessingTest:ProcessingDatatypesTest.StringConformanceProcessingTest` — both `[ OK ]`, no reshape/shape-inference errors in the console log. Full regression sweep (Task 2) confirms no other MNN type or conformance binary regressed.
- **Committed in:** `SGProcessingManager@bc74bc0` (documents the deviation in the commit body as well)

---

**Total deviations:** 1 auto-fixed (Rule 1 - bug in the plan's literal fix, corrected using the plan's own diagnostic context — the schema-declared `maxLength` parameter — which the plan had already identified as the distinguishing factor between the two models but did not wire into the actual resize-length computation)
**Impact on plan:** The plan's stated *acceptance criteria* (grep patterns for `resizeLen`, `elementSize() != maxLength`, checked `runSession()`, no `PushTeardown`/`RunTeardown`) are all still satisfied verbatim. The plan's stated *behavior contract* and *done criteria* (both string tests pass; no other MNN type touched/regressed) are now genuinely met, which the plan's literal action text alone did not achieve. No scope creep — only `processing_processor_mnn_string.cpp` was touched, matching the plan's `files_modified` list exactly.

## Issues Encountered
- Initial application of the plan's literal fix passed `StringInputProcessingTest` but left `StringConformanceProcessingTest` failing with the same symptom as before. Diagnosed via temporary debug logging (`tensor->elementSize()`, `tensor->shape()`) added and then removed before the final commit, confirming the tiny model's input tensor has a dynamic/unresolved declared shape (`[1, -1]`) at session-creation time — there is no way to infer the required fixed length of 16 from the tensor itself; it can only come from the job's schema (`maxLength` parameter or `model.input_nodes[0].shape`), which is exactly what the corrected fix now reads.
- `gsd-tools state update-progress --ws sgproc-render` recomputed the STATE.md frontmatter `progress.percent` field as `completed_phases/total_phases*100` (25%, since `completed_phases` flipped 0→1) instead of the plan-based `completed_plans/total_plans*100` (81%) that this field has consistently held across every prior plan in this workstream (e.g. 78% for 21/27 before this plan). Manually corrected `percent` back to 81 and `completed_phases` back to 0 in STATE.md's frontmatter, since Phase 09 is not actually fully verified/complete yet (a fresh goal-backward re-verification is still pending per "Next Phase Readiness" below) — flagging this as a likely pre-existing tool inconsistency for future investigation, out of this plan's scope to fix.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Gap 5 (TEST-04's string-processor partial status) is now closed: all 18 MNN processor types, including both string sub-cases, pass conformance with 0 failures.
- This was the last of the three plans in gap-closure round 2 (09-11, 09-12, 09-13). All three of 09-VERIFICATION.md's `failed`/`partial` gaps (TEST-04/05/07/08, and TEST-06's missing cases from 09-04/09-10) have now had dedicated closure plans executed across 09-11 through 09-13; a fresh goal-backward re-verification of the full phase is the appropriate next step before considering Phase 09 complete.

---
*Phase: 09-processor-pass-graph-conformance-suites*
*Completed: 2026-08-06*

## Self-Check: PASSED

- FOUND: `.planning/workstreams/sgproc-render/phases/09-processor-pass-graph-conformance-suites/09-13-SUMMARY.md`
- FOUND: `SGProcessingManager@bc74bc0` (fix commit)
- FOUND: `SuperGenius@95e46966` (pointer bump)
- FOUND: `GeniusNetwork@71c5172` (pointer bump)
- FOUND: `GeniusNetwork@0416409` (this summary's commit)
