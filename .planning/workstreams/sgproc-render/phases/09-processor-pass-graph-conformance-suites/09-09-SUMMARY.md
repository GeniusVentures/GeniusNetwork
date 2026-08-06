---
phase: 09-processor-pass-graph-conformance-suites
plan: 09
subsystem: processingbase
tags: [error-handling, json-schema, gtest, ctest, processingmanager]

# Dependency graph
requires:
  - phase: 09 (plan 08)
    provides: corrected schema fixtures/inline JSON literals (Gap 1) so valid-job acceptance tests pass, leaving only rejection-path error-message tests failing
provides:
  - 4 new granular ProcessingManager::Error values with distinct, field-referencing messages
  - CheckProcessValidity() explicit model-format-executability check (rejects recognized-but-non-MNN formats like ONNX)
  - Init() pre-parse raw-JSON validation of passes[].type and passes[].model.format, run before the quicktype from_json() that would otherwise throw context-free
affects: [09-10]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Pre-parse raw nlohmann::json scan (is_object/is_array/is_string/contains-guarded) to intercept unrecognized quicktype enum strings before from_json() throws a context-free std::runtime_error"]

key-files:
  created: []
  modified:
    - SuperGenius/SGProcessingManager/include/processingbase/ProcessingManager.hpp
    - SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp

key-decisions:
  - "Model-format rejection is split across two layers by design: unrecognized strings (e.g. 'UNKNOWN') are caught by Init()'s pre-parse scan as MODEL_FORMAT_UNSUPPORTED before from_json() would throw; recognized-but-non-executable formats (ONNX/PyTorch/TensorFlow) parse successfully and are instead rejected by CheckProcessValidity()'s new ModelFormat::MNN equality check, also returning MODEL_FORMAT_UNSUPPORTED — both paths converge on the same distinct error message"
  - "Only the INFERENCE case's missing-model check and RENDER case's missing-render_shader check were changed to granular errors, per the plan's explicit scope; all other RENDER-case checks (render_target, vertex_buffer, vertex_layout) were left returning PROCESS_INFO_MISSING since no test requires them to be granular"

patterns-established: []

requirements-completed: [TEST-02, TEST-08]

coverage:
  - id: D1
    description: "InvalidMissingModel, InvalidBadModelFormat, InvalidUnknownPassType, RenderMissingShader (schema_test) receive field-specific error messages instead of generic PROCESS_INFO_MISSING/INVALID_JSON text"
    requirement: "TEST-02"
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_schema/schema_validation_test.cpp#SchemaValidationTest.InvalidMissingModel"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_schema/schema_validation_test.cpp#SchemaValidationTest.InvalidBadModelFormat"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_schema/schema_validation_test.cpp#SchemaValidationTest.InvalidUnknownPassType"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_schema/schema_validation_test.cpp#SchemaValidationTest.RenderMissingShader"
        status: pass
    human_judgment: false
  - id: D2
    description: "RejectUnsupportedModelFormat rejects an ONNX-format model with a message mentioning format; RejectUnsupportedPassType and UnknownPassTypeRejected reject unregistered pass types without an unhandled from_json exception reaching the caller"
    requirement: "TEST-08"
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_capability/capability_conformance_test.cpp#CapabilityConformanceTest.RejectUnsupportedModelFormat"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_capability/capability_conformance_test.cpp#CapabilityConformanceTest.RejectUnsupportedPassType"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_executor/executor_selection_test.cpp#ExecutorSelectionTest.UnknownPassTypeRejected"
        status: pass
    human_judgment: false
  - id: D3
    description: "RejectionReasonsAreDistinct observes 3 textually distinct rejection messages across model-format, missing-model, and unknown-pass-type failures"
    requirement: "TEST-08"
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_capability/capability_conformance_test.cpp#CapabilityConformanceTest.RejectionReasonsAreDistinct"
        status: pass
    human_judgment: false

duration: 35min
completed: 2026-08-06
status: complete
---

# Phase 09 Plan 09: Granular Error Messages for Rejection Paths (Gaps 2, 4, 5) Summary

**Added 4 new `ProcessingManager::Error` values with field-specific messages, an explicit `ModelFormat::MNN` executability check in `CheckProcessValidity()`, and a pre-parse raw-JSON scan in `Init()` that intercepts unrecognized `passes[].type`/`passes[].model.format` strings before quicktype's `from_json()` discards their context — closing UAT Gaps 2, 4, and 5.**

## Performance

- **Duration:** ~35 min
- **Tasks:** 2 completed
- **Files modified:** 2

## Accomplishments

- `ProcessingManager::Error` gained 4 new values (`MODEL_MISSING=10`, `MODEL_FORMAT_UNSUPPORTED=11`, `RENDER_SHADER_MISSING=12`, `UNKNOWN_PASS_TYPE=13`), each with a distinct static category-message string containing the field name a caller would search for (`model`/`format`/`shader`/`type`)
- `CheckProcessValidity()`'s `INFERENCE` case now returns `MODEL_MISSING` (was generic `PROCESS_INFO_MISSING`) when no model is present, and gained a new explicit check rejecting any model whose `ModelFormat` is not `MNN` — this is what actually rejects `ONNX`/`PyTorch`/`TensorFlow` models, since those are recognized enum values that parse successfully and can only be caught by a post-parse business-rule check, not by JSON validation
- `CheckProcessValidity()`'s `RENDER` case's missing-`render_shader` branch now returns `RENDER_SHADER_MISSING` (the other RENDER-case checks — `render_target`, `vertex_buffer`, `vertex_layout` — were left untouched per the plan's explicit scope)
- `Init()` gained a pre-parse raw-JSON scan (guarded with `is_object()`/`is_array()`/`is_string()`/`contains()` at every step) that runs after `nlohmann::json::parse()` and before `sgns::from_json()`: it walks `passes[]`, rejects any unrecognized `type` string (not one of `compute`/`data_transform`/`inference`/`render`/`retrain`) as `UNKNOWN_PASS_TYPE`, and for `inference`/`retrain` passes, rejects any unrecognized `model.format` string (not one of `MNN`/`ONNX`/`PyTorch`/`TensorFlow`) as `MODEL_FORMAT_UNSUPPORTED` — both immediately, before the quicktype `from_json()` call that would otherwise throw a plain `std::runtime_error` with no field context
- Verified against `Generators.hpp`'s actual `from_json(PassType&)`/`from_json(ModelFormat&)` implementations to confirm the exact recognized-string sets before writing the validation logic
- Full ctest run of all 3 target binaries: 6/6 (`capability`), 5/5 (`executor`), 10/10 (`schema`) — 100% pass, 0 failures, including all named `done`-criteria cases plus the pre-existing `EmptyJobDefinition`/`MissingPassesArray` regression cases (unaffected, still `Json cannot be parsed`)

## Task Commits

Each task was committed atomically inside the `SGProcessingManager` submodule (nested inside `SuperGenius`):

1. **Task 1: Add 4 granular Error enum values with distinct category messages** - `ab13978` (feat)
2. **Task 2: Wire granular errors into CheckProcessValidity() and pre-parse validation into Init()** - `f1e289f` (fix)

Submodule pointer bumps:
- `SuperGenius` repo: `458b8850` (docs) — bumps `SGProcessingManager` b9c445b0..f1e289f9
- Outer `GeniusNetwork` repo: `db3c28a` (docs) — bumps `SuperGenius` 7fa3313..458b885

**Plan metadata:** committed separately at the outer repo level (see final commit below)

## Files Created/Modified

- `SuperGenius/SGProcessingManager/include/processingbase/ProcessingManager.hpp` - appended 4 new `Error` enum values (10-13)
- `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` - 4 new category-message cases; `CheckProcessValidity()` INFERENCE/RENDER granular-error wiring + new MNN-format check; `Init()` pre-parse `passes[].type`/`model.format` validation; added `#include <set>`

## Decisions Made

- Model-format rejection intentionally split across two layers: unrecognized strings (`UNKNOWN`) caught pre-parse in `Init()`; recognized-but-unsupported formats (`ONNX` etc.) caught post-parse in `CheckProcessValidity()`'s explicit `ModelFormat::MNN` equality check — both converge on the same `MODEL_FORMAT_UNSUPPORTED` error and message
- Only the two specific checks named in the plan (`INFERENCE` missing-model, `RENDER` missing-render_shader) were made granular; all other `RENDER`-case field checks were left as `PROCESS_INFO_MISSING` since no test requires otherwise, per plan scope

## Deviations from Plan

None - plan executed exactly as written. Both tasks matched the `<action>` instructions verbatim; recognized `PassType`/`ModelFormat` string sets were cross-verified directly against `Generators.hpp`'s `from_json()` implementations before writing the pre-parse validation logic.

## Issues Encountered

None. Build and full `ctest -R "processing_conformance_schema_test|processing_conformance_executor_test|processing_conformance_capability_test"` run succeeded on the first attempt after implementing both tasks.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All 3 conformance test binaries (`processing_conformance_schema_test`, `processing_conformance_capability_test`, `processing_conformance_executor_test`) are fully green (0 failures) with Plan 09-08's fixture fixes combined with this plan's error-message wiring
- No blockers for 09-10

---
*Phase: 09-processor-pass-graph-conformance-suites*
*Completed: 2026-08-06*

## Self-Check: PASSED

All modified files exist on disk and both task commits (`ab13978`, `f1e289f`) are present in the `SGProcessingManager` submodule's git history; submodule pointer bump commits (`458b8850` in `SuperGenius`, `db3c28a` in the outer repo) are present in their respective histories.
