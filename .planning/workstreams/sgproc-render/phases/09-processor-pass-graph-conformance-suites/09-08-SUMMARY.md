---
phase: 09-processor-pass-graph-conformance-suites
plan: 08
subsystem: testing
tags: [json-schema, gtest, ctest, processingmanager, sgprocessingmanager]

# Dependency graph
requires:
  - phase: 09 (plans 01-07)
    provides: conformance test suites (schema, capability, executor) scaffolded and wired into CTest, but with fixtures/inline literals that used the wrong field names for the real Pass/DataType schema
provides:
  - Corrected valid-inference.json / valid-render.json shared fixtures matching the real generated Pass/DataType schema
  - Corrected inline JSON literals in capability_conformance_test.cpp and executor_selection_test.cpp (4 TEST_F cases)
affects: [09-09, 09-10]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Render pass JSON fixtures use render_shader/render_target/vertex_buffer/vertex_layout (not shader_pipeline/framebuffer/vertex_buffers), mirroring processing_dispatch/render-pass-valid-definition.json"]

key-files:
  created: []
  modified:
    - SuperGenius/test/src/processing_conformance_schema/fixtures/valid-inference.json
    - SuperGenius/test/src/processing_conformance_schema/fixtures/valid-render.json
    - SuperGenius/test/src/processing_conformance_capability/capability_conformance_test.cpp
    - SuperGenius/test/src/processing_conformance_executor/executor_selection_test.cpp

key-decisions:
  - "Used DataType::FLOAT (not TENSOR) for all fixed inference-input fixtures/literals, matching the [1,16] model shape already declared, since FLOAT/TENSOR share the same dimensions.width requirement"
  - "Reused testInput as the vertex_buffer source in executor_selection_test.cpp's MultiplePassesDifferentExecutors render_pass_fixture instead of declaring a new input, since CheckProcessValidity only checks the input: prefix, not that a matching declared input exists by name"

patterns-established: []

requirements-completed: [TEST-02, TEST-03, TEST-08]

coverage:
  - id: D1
    description: "valid-inference.json and valid-render.json shared fixtures use the real Pass/DataType schema field names and are accepted by ProcessingManager::Create()"
    requirement: "TEST-02"
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_schema/schema_validation_test.cpp#SchemaValidationTest.ValidInferencePass"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_schema/schema_validation_test.cpp#SchemaValidationTest.ValidRenderPass"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_schema/schema_validation_test.cpp#SchemaValidationTest.MultiplePassesValid"
        status: pass
    human_judgment: false
  - id: D2
    description: "capability_conformance_test.cpp's AcceptValidInferenceJob and AcceptValidRenderJob inline JSON literals fixed identically to the shared fixtures"
    requirement: "TEST-03"
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_capability/capability_conformance_test.cpp#CapabilityConformanceTest.AcceptValidInferenceJob"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_capability/capability_conformance_test.cpp#CapabilityConformanceTest.AcceptValidRenderJob"
        status: pass
    human_judgment: false
  - id: D3
    description: "executor_selection_test.cpp's ExecutorIdentityStable and MultiplePassesDifferentExecutors inline JSON/raw-string literals fixed identically to the shared fixtures"
    requirement: "TEST-08"
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_executor/executor_selection_test.cpp#ExecutorSelectionTest.ExecutorIdentityStable"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_executor/executor_selection_test.cpp#ExecutorSelectionTest.MultiplePassesDifferentExecutors"
        status: pass
    human_judgment: false

duration: 25min
completed: 2026-08-06
status: complete
---

# Phase 09 Plan 08: Fix JSON Fixture Field Name Mismatch (Gap 1) Summary

**Corrected 2 shared schema fixtures + 4 duplicated inline JSON literals across 2 test files to use ProcessingManager's real Pass/DataType field names (render_shader/render_target/vertex_buffer/vertex_layout, DataType::FLOAT+dimensions), fixing all 6 named UAT-reported acceptance-test failures.**

## Performance

- **Duration:** ~25 min
- **Tasks:** 2 completed
- **Files modified:** 4

## Accomplishments
- `valid-inference.json` now declares its input as `DataType::FLOAT` with a `dimensions` object (`width`/`block_len`/`chunk_stride`: 16), matching the `[1, 16]` model shape it already referenced — previously it was `tensor` with no `dimensions`, which `CheckProcessValidity()` rejected with "Tensor type missing width"
- `valid-render.json`'s pass now uses the real `Pass` schema fields (`render_shader` with two `spirv`-typed stages, `render_target`, `vertex_buffer`, `vertex_layout`) instead of the non-existent `shader_pipeline`/`framebuffer`/`vertex_buffers` keys, mirroring the confirmed-working precedent `processing_dispatch/render-pass-valid-definition.json`; its `vertexData` input's `dimensions.width: 1` was also added and the invalid `format: FLOAT32` (rejected for `DataType::BUFFER`) was removed
- The identical mismatch, independently duplicated as inline JSON string literals in 4 `TEST_F` cases across `capability_conformance_test.cpp` and `executor_selection_test.cpp`, was fixed the same way
- All 6 named `TEST_F` cases from the plan's `done` criteria now show `[ OK ]`: `ValidInferencePass`, `ValidRenderPass`, `MultiplePassesValid` (schema_test); `AcceptValidInferenceJob`, `AcceptValidRenderJob` (capability_test); `ExecutorIdentityStable`, `MultiplePassesDifferentExecutors` (executor_test) — 7 cases total (the plan's objective mentions 6; `MultiplePassesValid` was additionally confirmed passing as part of Task 1's verification)

## Task Commits

Each task was committed atomically inside the `SuperGenius` submodule:

1. **Task 1: Fix shared schema fixtures valid-inference.json and valid-render.json** - `dfb1ab10` (fix)
2. **Task 2: Fix duplicated inline JSON literals in capability_conformance_test.cpp and executor_selection_test.cpp** - `7fa33130` (fix)

**Plan metadata:** committed separately at the outer repo level (docs commit, see below)

## Files Created/Modified
- `SuperGenius/test/src/processing_conformance_schema/fixtures/valid-inference.json` - input type changed tensor->float, added dimensions
- `SuperGenius/test/src/processing_conformance_schema/fixtures/valid-render.json` - pass restructured to render_shader/render_target/vertex_buffer/vertex_layout, vertexData input fixed
- `SuperGenius/test/src/processing_conformance_capability/capability_conformance_test.cpp` - AcceptValidInferenceJob and AcceptValidRenderJob inline JSON literals fixed identically
- `SuperGenius/test/src/processing_conformance_executor/executor_selection_test.cpp` - ExecutorIdentityStable and MultiplePassesDifferentExecutors inline JSON/raw-string literals fixed identically

## Decisions Made
- Used `DataType::FLOAT` (not `TENSOR`) per the plan's explicit instruction for all inference-input fixes, since the model's `[1, 16]` shape and the confirmed-working `float-processing-definition.json` precedent both use `float`
- In `executor_selection_test.cpp`'s `MultiplePassesDifferentExecutors`, set the render pass's `vertex_buffer.source` to `input:testInput` (reusing the existing declared input) rather than declaring a new `vertexData` input, per the plan's explicit guidance that `CheckProcessValidity()` only validates the `input:` prefix, not that a matching input exists by name

## Deviations from Plan

None - plan executed exactly as written. Every field name, value, and structural change matched the plan's `<action>` instructions verbatim, cross-verified directly against `ProcessingManager.cpp`'s `CheckProcessValidity()` and the generated `Pass.hpp`/`ShaderStage.hpp`/`RenderTarget.hpp`/`VertexBuffer.hpp`/`VertexLayoutEntry.hpp`/`DataType.hpp` headers before editing.

## Issues Encountered

None. Build and verification succeeded on the first attempt for both tasks.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All 6 (7 counting `MultiplePassesValid`) named test cases pass; the schema/capability/executor conformance test binaries are otherwise still red because of gaps owned by Plan 09-09 (rejection-path error-message assertions: `InvalidMissingModel`, `InvalidBadModelFormat`, `InvalidUnknownPassType`, `RenderMissingShader`, `RejectUnsupportedModelFormat`, `RejectUnsupportedPassType`, `RejectionReasonsAreDistinct`, `RejectMissingExecutor`, `UnknownPassTypeRejected`) — these are explicitly out of scope for this plan per its `done` criteria and are expected to close when 09-09 lands in the same wave
- No blockers for 09-09/09-10

---
*Phase: 09-processor-pass-graph-conformance-suites*
*Completed: 2026-08-06*

## Self-Check: PASSED

All modified files exist on disk and both task commits (`dfb1ab10`, `7fa33130`) are present in the SuperGenius submodule's git history.
