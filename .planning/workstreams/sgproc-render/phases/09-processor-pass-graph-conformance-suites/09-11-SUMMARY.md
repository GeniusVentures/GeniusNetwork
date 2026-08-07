---
phase: 09-processor-pass-graph-conformance-suites
plan: 11
subsystem: processingbase
tags: [gtest, ctest, vulkan, capability-validation, execution-manifest, artifacts]

# Dependency graph
requires:
  - phase: 09 (plan 08/09/10)
    provides: corrected fixtures, granular error propagation, deterministic combinedHash — the schema/hashing baseline the three gap-closure suites in this plan build on
provides:
  - capability_conformance_test now genuinely exercises ProcessingManager::CanExecute() (3 new TEST_F cases), closing TEST-08
  - RenderConformanceTest now probes a real Vulkan device and executes Process() through the actual pipeline instead of only re-parsing JSON, closing TEST-05
  - output_hashing_test now covers artifact metadata (ARTF-01/02) and manifest-level byte-serialization determinism (ARTF-05), closing TEST-06's remaining gap
  - A genuine pre-existing production bug fix: ProcessOutput's artifact-metadata builder no longer crashes on BUFFER-type inputs with no explicit "format" field
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "CanExecute() capability-gate test pattern: build via Create(), extract the pass, call manager->CanExecute(pass, lambda), assert on the captured CanExecuteResult synchronously (callback fires inline, no async wait needed)"
    - "GTEST_SKIP() inside a fixture's static SetUpTestSuite() to skip an entire GPU-dependent test class on hosts without a usable Vulkan device (D-05), matching processing_dispatch_test.cpp's established precedent"

key-files:
  created: []
  modified:
    - SuperGenius/test/src/processing_conformance_capability/capability_conformance_test.cpp
    - SuperGenius/test/src/processing_conformance_regression/regression_test.cpp
    - SuperGenius/test/src/processing_conformance_regression/CMakeLists.txt
    - SuperGenius/test/src/processing_conformance_hashing/output_hashing_test.cpp
    - SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp

key-decisions:
  - "InferenceCanExecuteReflectsPassTypeRegistryGap asserts today's real, verified behavior (INFERENCE passes are schema-valid but not capability-registered) rather than treating it as a bug to fix — registering INFERENCE into the PassType-keyed capability registry is a separate, larger cross-phase change, explicitly out of this test-authoring-only plan's scope. Documented as a discovered follow-up item."
  - "Fixed a genuine pre-existing crash in ProcessOutput's artifact-metadata builder (procInput.get_format().value() called unconditionally on an optional that BUFFER-type inputs may legitimately omit) rather than working around it in the tests — the plan's stated 'test-authoring only, no production code changes' assumption held for two of three tasks, but this crash was a real correctness bug newly exposed by actually calling Process() for a render pass for the first time, squarely a Rule 1 auto-fix."
  - "Added a second copy_directory step to processing_conformance_regression's CMakeLists.txt rather than editing the shared fixture JSON's shader source URIs — the existing 'file://processing_conformance_regression/fixtures/...' URI convention is also referenced by processing_conformance_schema and this plan's own new capability_conformance_test literals, so fixing the build-output layout (not the URI) has the smallest blast radius."

patterns-established: []

requirements-completed: [TEST-08, TEST-05, TEST-06]

coverage:
  - id: D1
    description: "capability_conformance_test genuinely calls ProcessingManager::CanExecute() (not just Create()) for acceptance, Vulkan-feature rejection, and pass-type-registration rejection"
    requirement: "TEST-08"
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_capability/capability_conformance_test.cpp#CapabilityConformanceTest.AcceptValidRenderJobViaCanExecute"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_capability/capability_conformance_test.cpp#CapabilityConformanceTest.RejectUnsupportedVulkanFeature"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_capability/capability_conformance_test.cpp#CapabilityConformanceTest.InferenceCanExecuteReflectsPassTypeRegistryGap"
        status: pass
    human_judgment: false
  - id: D2
    description: "RenderConformanceTest probes a real Vulkan device (GTEST_SKIP if absent) and executes Process() through the actual Vulkan pipeline, verifying a rendered-output hash, instead of only re-parsing JSON via Create()"
    requirement: "TEST-05"
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_regression/regression_test.cpp#RenderConformanceTest.RenderPassFullPipeline"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_regression/regression_test.cpp#RenderConformanceTest.RenderPassOutputHashDeterministic"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_regression/regression_test.cpp#RenderConformanceTest.RenderPassTeardownVerified"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_regression/regression_test.cpp#RenderConformanceTest.MoltenVkEquivalentPath"
        status: pass
    human_judgment: false
  - id: D3
    description: "output_hashing_test covers artifact metadata construction (ARTF-01/02) and manifest-level deterministic byte-serialization (ARTF-05), completing the originally-planned 7 cases (was 4)"
    requirement: "TEST-06"
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_hashing/output_hashing_test.cpp#OutputHashingTest.ArtifactMetadataPresent"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_hashing/output_hashing_test.cpp#OutputHashingTest.ManifestFieldsPresent"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_hashing/output_hashing_test.cpp#OutputHashingTest.ManifestDeterministicSerialization"
        status: pass
    human_judgment: false
  - id: D4
    description: "No regression to the pre-existing 6 CapabilityConformanceTest, 4 RegressionTest, and 4 OutputHashingTest cases, or to sibling conformance suites (schema, executor, migration, cancellation)"
    verification:
      - kind: integration
        ref: "ctest -C Release -R \"processing_conformance_(capability|regression|hashing)_test\" -V — 25/25 pass"
        status: pass
      - kind: integration
        ref: "ctest -C Release -R \"processing_conformance_(migration|executor|schema|cancellation)_test\" — 4/4 binaries pass, no new failures"
        status: pass
    human_judgment: false

# Metrics
duration: 68min
completed: 2026-08-07
status: complete
---

# Phase 09 Plan 11: CanExecute()/Vulkan-Process()/Manifest-Metadata Test-Authoring Gap Closure Summary

**Closed 3 goal-backward verification gaps (Gap 1/3/4) by wiring capability_conformance_test to real ProcessingManager::CanExecute() calls, RenderConformanceTest to a real Vulkan device probe + Process() execution, and output_hashing_test to cover artifact metadata + manifest-serialization determinism — plus fixed a genuine pre-existing crash in artifact-metadata building that this work newly exposed.**

## Performance

- **Duration:** 68 min
- **Started:** 2026-08-06T22:59:59Z (approx, per plan-start convention)
- **Completed:** 2026-08-07T00:08:50Z
- **Tasks:** 3
- **Files modified:** 5 (3 test files, 1 CMakeLists.txt, 1 production source file)

## Accomplishments

- `capability_conformance_test.cpp` gained 3 new `TEST_F` cases (`AcceptValidRenderJobViaCanExecute`, `RejectUnsupportedVulkanFeature`, `InferenceCanExecuteReflectsPassTypeRegistryGap`) that call `ProcessingManager::CanExecute()` directly and assert on the returned `CanExecuteResult` — the exact production entry point the verification report found was never exercised by any of the 6 pre-existing cases (which all only called `Create()`, the earlier schema-validation gate)
- `RenderConformanceTest` (5 cases inside `processing_conformance_regression_test`) now probes a real Vulkan device via `HasUsableVulkanDevice()`/`GTEST_SKIP()` (D-05) and actually calls `Process()` through the real Vulkan pipeline, verifying 32-byte rendered-output hashes, bit-exact same-node determinism across two independent manager instances, and teardown-then-reuse — replacing 5 cases that previously only re-parsed the same JSON via `Create()`
- `output_hashing_test.cpp` gained the 3 missing planned cases (`ArtifactMetadataPresent`, `ManifestFieldsPresent`, `ManifestDeterministicSerialization`), bringing it from 4/7 to 7/7 originally-planned cases, covering ARTF-01/02 (artifact identity + format metadata) and ARTF-05 (full manifest byte-serialization determinism, distinct from Plan 09-10's combinedHash-value-only fix)
- Fixed a genuine pre-existing crash in `ProcessingManager.cpp`'s artifact-metadata builder: `procInput.get_format().value()` was called unconditionally on an optional that BUFFER-type inputs (e.g. a render pass's `vertex_buffer` source) may legitimately omit — latent until this plan's Task 2 became the first test to ever call `Process()` for a render pass whose output triggers artifact construction

## Task Commits

Each task was committed atomically (nested submodule structure: `GeniusNetwork` → `SuperGenius` → `SGProcessingManager`):

1. **Task 1: Wire capability_conformance_test.cpp to CanExecute()** — SuperGenius `37121a8d` (test)
2. **Task 2: Wire RenderConformanceTest to a real Vulkan device and Process()** — SuperGenius `280cae68` (test), which bundles a CMake fixture-path fix and the `SGProcessingManager` submodule bump for `c6f993e` (fix)
3. **Task 3: Add the 3 missing output-hashing conformance cases** — SuperGenius `f8721dcc` (test)

**Plan metadata (top-level GeniusNetwork):**
- `e04cd73`: `docs(09-11): bump SuperGenius pointer — Gap 1/3/4 test-authoring closure`

## Files Created/Modified

- `SuperGenius/test/src/processing_conformance_capability/capability_conformance_test.cpp` — 3 new `TEST_F` cases calling `CanExecute()`; clarifying comments on the 3 pre-existing schema-layer cases
- `SuperGenius/test/src/processing_conformance_regression/regression_test.cpp` — real GPU probe in `SetUpTestSuite()`; all 5 `RenderConformanceTest` bodies rewritten to call `Process()`
- `SuperGenius/test/src/processing_conformance_regression/CMakeLists.txt` — added a second `copy_directory` placing fixtures at the nested path the JSON literals' `file://` URIs actually reference (Rule 3 deviation, see below)
- `SuperGenius/test/src/processing_conformance_hashing/output_hashing_test.cpp` — 3 new `TEST_F` cases covering artifact metadata + manifest determinism
- `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` — `value_or(InputFormat::INT8)` fix for the artifact-metadata format-mapping crash (Rule 1 deviation, see below)

## Decisions Made

- `InferenceCanExecuteReflectsPassTypeRegistryGap` documents, rather than "fixes," that INFERENCE passes are schema-valid but not yet capability-registered (only `PassType::RENDER` is registered via `RegisterPassProcessorFactory` in `Init()`). Registering INFERENCE/RETRAIN into the capability registry would be a separate, larger cross-phase production change — flagged as a discovered follow-up item, not undertaken here.
- The CMake fixture-path fix adds a second copy destination rather than changing the shared JSON literal's `file://processing_conformance_regression/fixtures/...` URI convention, since that same URI pattern is also used by `processing_conformance_schema`'s fixtures and this plan's own new capability-test literals — smallest blast radius.
- The `ProcessingManager.cpp` crash fix mirrors the exact same INT8-default convention `CheckProcessValidity()` already applies to BUFFER-type inputs elsewhere in the same file, rather than inventing a new fallback.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Missing nested fixture directory for render-pass shader URIs**
- **Found during:** Task 2 (wiring `RenderConformanceTest` to call `Process()`)
- **Issue:** The `regression-b-parseblocksize-model-only.json` fixture's SPIR-V shader `source` fields use `file://processing_conformance_regression/fixtures/passthrough.{vert,frag}.spv` — a URI whose relative path, once absolutized against the test binary's directory, requires the fixture files to also exist at `test_bin/processing_conformance_regression/fixtures/`, not just the flat `test_bin/fixtures/` the existing `copy_directory` populated. This was invisible before because no prior test ever called `Process()` for a render pass (only `Create()`, which never reads shader bytes from disk).
- **Fix:** Added a second `copy_directory` command in `processing_conformance_regression/CMakeLists.txt` placing the same fixture files at the nested path the URIs reference.
- **Files modified:** `SuperGenius/test/src/processing_conformance_regression/CMakeLists.txt`
- **Verification:** Rebuilt and re-ran `processing_conformance_regression_test` — shader files load successfully, SPIR-V validation passes.
- **Committed in:** `280cae68` (Task 2 commit)

**2. [Rule 1 - Bug] Fixed crash on BUFFER-type input with no explicit format**
- **Found during:** Task 2 (first real `Process()` call for a render pass reaching artifact-metadata construction)
- **Issue:** `ProcessOutput`'s artifact-metadata builder called `procInput.get_format().value()` unconditionally. BUFFER-type inputs (this fixture's `vertex_buffer` source) may legitimately omit `format`, which `CheckProcessValidity()` already handles by defaulting to INT8 with a warning — but this later artifact-building code path had no equivalent guard, so it threw "Attempted to access the value of an uninitialized optional object," surfacing as `Process()` returning `PROCESSING_FAILED`.
- **Fix:** Changed to `procInput.get_format().value_or( sgns::InputFormat::INT8 )`, mirroring the existing default convention.
- **Files modified:** `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp`
- **Verification:** Rebuilt; `RenderPassFullPipeline`/`RenderPassOutputHashDeterministic`/`RenderPassTeardownVerified`/`MoltenVkEquivalentPath` all pass with real 32-byte `combinedHash` values. Re-ran `processing_conformance_capability_test` (9/9), `processing_conformance_hashing_test` (7/7), `processing_datatypes_test` (41/41), `processing_conformance_migration_test`, `processing_conformance_executor_test`, `processing_conformance_schema_test`, `processing_conformance_cancellation_test` — no regressions.
- **Committed in:** `c6f993e` (SGProcessingManager submodule), bundled into SuperGenius commit `280cae68` via submodule pointer bump (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking/build-config, 1 bug)
**Impact on plan:** Both deviations were required for Task 2's `Process()`-calling tests to pass at all — not scope creep, but genuine blockers this plan's first-ever real-pipeline-execution work exposed. The plan's stated "test-authoring only, no production code changes" premise held for the intended test-writing surface; the production fix was a one-line, narrowly-scoped correctness fix directly necessitated by that test-authoring work actually exercising the pipeline for the first time.

## Issues Encountered

- `ProcessingDispatchTest` still shows its 4 pre-existing, previously-disclosed GLSL `#version` compile-target failures (unrelated to this plan — file last touched by Phase 08, confirmed by `09-VERIFICATION.md`). Not touched by this plan.
- `processing_datatypes_test`'s `StringInputProcessingTest`/`StringConformanceProcessingTest` — flagged in `09-VERIFICATION.md` as pre-existing failures on the verifier's host — passed cleanly on this execution host (41/41). Environment-dependent, unrelated to any file this plan modified; no action taken.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All 3 of `09-VERIFICATION.md`'s test-authoring-only gaps (Gap 1/TEST-08, Gap 3/TEST-05, Gap 4/TEST-06) assigned to this plan are closed and independently rebuilt/re-run, not just claimed.
- `09-VERIFICATION.md`'s Gap 2 (TEST-07, cancellation/deadline/budget never exercised — flagged as a possible cross-phase blocker since `ProcessingManager::Process()`'s public signature has no `ExecutionContext` parameter) and Gap 5 (TEST-04, pre-existing `processing_processor_mnn_string.cpp` bug) are out of this plan's scope — see `09-VERIFICATION.md` and sibling plans 09-12/09-13 in this phase directory for their disposition.
- No blockers for downstream work; the discovered INFERENCE capability-registration gap and the `procInput.get_format()` fix are both documented above for future reference.

---
*Phase: 09-processor-pass-graph-conformance-suites*
*Completed: 2026-08-07*

## Self-Check: PASSED

- FOUND: `.planning/workstreams/sgproc-render/phases/09-processor-pass-graph-conformance-suites/09-11-SUMMARY.md`
- FOUND: SuperGenius commit `37121a8d`
- FOUND: SuperGenius commit `280cae68`
- FOUND: SuperGenius commit `f8721dcc`
- FOUND: SGProcessingManager commit `c6f993e`
- FOUND: GeniusNetwork commit `e04cd73`
