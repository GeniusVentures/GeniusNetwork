# Phase 09: Processor & Pass-Graph Conformance Suites - Context

**Gathered:** 2026-08-05
**Status:** Ready for planning

<domain>
## Phase Boundary

CTest targets in `SuperGenius/test/src/` cover every processor against a common conformance contract — schema parsing, executor selection, output hashing, cancellation, capability checks, backward-compat adapters — plus regression tests for the four known v1.0 bugs. Each processor runs a full pipeline with known fixtures: Process() with deterministic input, verify output hash, verify teardown. Tests follow the existing `processing_datatypes_test` pattern (pre-baked `.mnn` models, `.raw` input/output files, JSON definitions, POST_BUILD copy). GLSL/SPIR-V fixtures are added for RenderProcessor.

**Depends on:** Phase 06, Phase 07, Phase 08 (TEST tests everything those phases build).

</domain>

<decisions>
## Implementation Decisions

### Test Fixture Strategy (TEST-02, TEST-03, TEST-04)

- **D-01:** Follow the existing `processing_datatypes_test` pattern — pre-baked tiny `.mnn` models, `.raw` input/output files, JSON processing definitions, Python model-generation scripts, all copied to the build directory via `POST_BUILD` custom commands. This pattern already covers 13 MNN processor types; expand to the remaining 5 (audio, image, ml, string, volume) using the same approach.
- **D-02:** Add GLSL source + pre-compiled SPIR-V binary fixtures for `RenderProcessor` conformance tests. A trivial pass-through vertex+fragment shader pair, pre-validated through `spirv-val`. Input: a small vertex buffer with known coordinates. Expected output: a rendered framebuffer readback with deterministic pixels.

### CTest Target Organization (TEST-01, TEST-02, TEST-03, TEST-07, TEST-08)

- **D-03:** Follow the existing SGProcessingManager per-category pattern — separate test executables by test dimension, each with `add_executable` + `add_test` + `gtest_discover_tests`. Not per-processor targets. Categories: schema parsing, executor selection, output hashing, cancellation, capability, regression.
- **D-04:** Conformance tests live in `SuperGenius/test/src/` alongside `processing_datatypes_test` — where fixtures, processing definitions, and the full ProcessingManager pipeline already exist. SGProcessingManager standalone tests (`test/capability/`, `test/execution/`, `test/artifacts/`) cover unit-level concerns and remain separate. SuperGenius has no reason to consume SGProcessingManager unit tests.

### GPU-Dependent Test Handling (TEST-05)

- **D-05:** `GTEST_SKIP()` + Vulkan device probe at `SetUp()` time. Every GPU-dependent test (RenderProcessor conformance, native Vulkan paths) probes for a Vulkan physical device. If none found, `GTEST_SKIP()` with a reason string (e.g., "No Vulkan device available — MoltenVK not present or no GPU"). No special CMake labels required initially; can add later if CI needs label-based filtering.

### Processor Conformance Contract (TEST-03, TEST-04, TEST-06, TEST-07)

- **D-06:** Full pipeline per processor — not just API shape validation. Each processor runs with a known fixture input through `ProcessingManager::Process()`, output hash is verified against an expected hash, and teardown is verified (no leaks, no dangling resources). Matches `processing_datatypes_test`'s existing "process with known input, compare to expected output" approach.
- **D-07:** The conformance contract covers: (a) `StartProcessing()` accepts `ExecutionContext` and respects cancel callback, (b) progress events are emitted at stage boundaries, (c) output hash is deterministic across repeat runs, (d) `RunTeardown()` fires on success, cancel, and failure paths.

### Regression Test Reproduction (TEST-10)

- **D-08:** Synthetic trigger inputs for each of the four known v1.0 bugs — minimal inputs crafted to exercise the exact code path. Assert the FIXED behavior, not the buggy behavior:
  - (a) Index mismatch in pass/input indexing — a multi-pass job where input bindings reference pass indices that shift after insertions
  - (b) Model-only assumption crash in `ParseBlockSize()` — a shader-only render pass with no `model` field
  - (c) Output-buffer-zero fallback — an edge case where the output tensor has zero elements, triggering the fallback path that produced incorrect results
  - (d) Unsupported pass type silently falling through — a job definition referencing an unregistered `PassType` enum value

### Claude's Discretion

- Exact GTest suite and test case names — follow existing naming conventions in `processing_datatypes_test.cpp` and SGProcessingManager test files.
- Exact structure of GLSL/SPIR-V fixtures for RenderProcessor — shader content, vertex data, expected output hash.
- Whether conformance tests share a common test fixture base class (recommended — parallels the existing `FSFixture` pattern from SuperGenius test infrastructure).
- Which CMake library targets each test executable links against (follow existing patterns: `ProcessingBase`, `SGExecution`, `SGCapability`, `SGArtifacts`, etc.).
- Exact `GTEST_SKIP()` reason strings for GPU-unavailable environments.
- Whether regression tests are separate executables or live within the relevant category target.
- How the Python model-generation scripts are extended for the 5 remaining MNN processor types (audio, image, ml, string, volume).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & Roadmap
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` — TEST-01..10 locked requirements for this phase
- `.planning/workstreams/sgproc-render/ROADMAP.md` — Phase 09 goal, success criteria, and requirement traceability. **Note:** success criterion #5 says "ctest runs from standalone SGProcessingManager AND as submodule" — D-04 refines this: conformance tests live in SuperGenius, standalone SGProcessingManager tests remain separate.

### Prior Phase Context (v2.0 Phases 06-08)
- `.planning/workstreams/sgproc-render/phases/06-capability-validation-foundation/06-CONTEXT.md` — D-01/D-04 (internally constructed by ProcessingManager — tests exercise through ProcessingManager), D-05 (C++ structs only, no protobuf), D-06 (flat list pattern), D-08 (SHA-256 executor identity), D-19 (caller-responsibility model), D-20/D-24 (validation layers best-effort — tests must not depend on layer availability)
- `.planning/workstreams/sgproc-render/phases/07-cancellable-execution-context/07-CONTEXT.md` — D-14/D-15 (unified teardown stack + cancel pending saves — conformance tests verify teardown), D-05 (unified terminal path with distinct error codes), D-18/D-19 (adapter pattern), D-10/D-11 (progress event shape and stages)
- `.planning/workstreams/sgproc-render/phases/08-structured-artifacts-execution-manifests/08-CONTEXT.md` — D-07 (SHA-256 everywhere), D-01 (content-hash-based artifact IDs), D-08 (chunk hashes from existing processor output), D-04 (custom deterministic binary serialization), D-10/D-12 (adapter removal + clean break)

### Existing Test Infrastructure (Source of Truth)
- `SuperGenius/test/src/processing_datatypes/` — **Primary pattern to follow.** Contains: 13 MNN processor test fixtures (`.mnn` models, `.raw` inputs/outputs, JSON definitions, Python model-generation scripts), `processing_datatypes_test.cpp` (GTest suite), `CMakeLists.txt` (POST_BUILD copy pattern, `addtest()` macro usage)
- `SuperGenius/test/src/CMakeLists.txt` — `add_subdirectory(processing_datatypes)` — the registration point for new conformance test subdirectories
- `SuperGenius/test/testutil/` — Shared test utilities: `outcome.hpp` (outcome assertion macros), `literals.hpp`, `base_fs_test.hpp`, `base_rocksdb_test.hpp`, `wait_condition.hpp`
- `SuperGenius/cmake/functions.cmake` — `addtest()` macro definition — all new test targets use this macro
- `SuperGenius/SGProcessingManager/test/capability/CMakeLists.txt` — Existing per-category test pattern: `add_executable` + `target_link_libraries(GTest::gtest_main ...)` + `add_test()` + `gtest_discover_tests()`
- `SuperGenius/SGProcessingManager/test/execution/CMakeLists.txt` — Seven per-category test executables following the same pattern

### Processor Inventory
- `SuperGenius/SGProcessingManager/include/processors/` — 20 processor headers: 18 MNN (audio, bool, buffer, float, image, int, mat2, mat3, mat4, ml, string, tensor, texture1d, texturecube, vec2, vec3, vec4, volume) + RenderProcessor + GPU probe
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_image.cpp` — Example MNN processor with chunk hashing, cancel checks, progress events, Vulkan init mutex, teardown stack — the pattern every processor must conform to

### Coding Standards
- `Coding Standards.md` (repo root) — C++ naming, formatting, brace style (Allman/Ulman), member prefix convention
- `.planning/codebase/TESTING.md` — GTest patterns: `SetUp()`/`TearDown()`, fixture classes, `TEST_F()`, `gtest_discover_tests()`, `addtest()` macro, outcome assertion macros

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`processing_datatypes_test`** (`SuperGenius/test/src/processing_datatypes/`) — 13 existing MNN processor test fixtures with tiny `.mnn` models, `.raw` input/output files, and JSON processing definitions. The exact pattern to follow and expand. Python model-generation scripts (`create_float_model.py`, etc.) show how to generate new fixtures.
- **`addtest()` CMake macro** (`SuperGenius/cmake/functions.cmake`) — the standard way to register test executables. All new conformance test targets use this.
- **Outcome assertion macros** (`SuperGenius/test/testutil/outcome.hpp`) — `EXPECT_OUTCOME_TRUE`, `ASSERT_OUTCOME_SUCCESS`, etc. — existing patterns for asserting on `outcome::result<T>` return values from ProcessingManager.
- **`gtest_discover_tests()`** — already used in all SGProcessingManager test CMakeLists.txt. CTest integration is automatic.
- **Existing unit tests** from Phases 06-08 (`capability_validator_test`, `sgprocmanagerexec_*_test`, `artifact_serializer_test`) — cover unit-level concerns. Conformance tests complement these with integration-level pipeline tests.

### Established Patterns
- **Per-category test executables** — `capability/capability_validator_test`, `execution/sgprocmanagerexec_cancellation_test`, `artifacts/artifact_serializer_test`. Each is a standalone binary linked to specific SGProcessingManager library targets.
- **POST_BUILD fixture copy** — `processing_datatypes_test` copies `.mnn`, `.raw`, and `.json` files to `$<TARGET_FILE_DIR>` via `add_custom_command(TARGET ... POST_BUILD)`. RenderProcessor SPIR-V fixtures follow the same pattern.
- **`SGPROCMGR_TEST_FRIEND`** compile definition — used in `capability_validator_test` to grant test access to internal ProcessingManager members. Conformance tests may need the same for teardown verification.
- **GTest fixture classes** — `FSFixture`, `RocksDBFixture` in `test/testutil/`. Conformance tests may define a shared `ProcessorConformanceFixture` base class for setup/teardown of ProcessingManager + fixtures.
- **Deterministic output verification via SHA-256** — `processing_datatypes_test` compares processing output hashes to expected hashes. Conformance tests use the same approach, consistent with Phase 08 D-07 (SHA-256 everywhere).

### Integration Points
- **`SuperGenius/test/src/CMakeLists.txt`** — `add_subdirectory(processing_datatypes)` is the registration point. New conformance test subdirectories are added here.
- **`ProcessingManager::Process()`** — the entry point for full-pipeline conformance tests. Tests construct a ProcessingManager, call Process() with a fixture job definition, and verify the result.
- **`SuperGenius/test/src/processing_datatypes/` JSON definitions** — schema for processing job definitions used by tests. New fixtures for RenderProcessor and the 5 remaining MNN types need matching JSON definitions.
- **`VulkanInitMutex`** — GPU-dependent tests acquire this mutex during setup. The device probe in D-05 also acquires it.

</code_context>

<specifics>
## Specific Ideas

Key domain context from discussion:

- **Tests live in SuperGenius, not SGProcessingManager** — SuperGenius is compiled more often and already has the `processing_datatypes_test` pattern with fixtures, JSON definitions, and the full ProcessingManager pipeline. SGProcessingManager standalone tests cover unit-level concerns; conformance tests exercise processors through the real pipeline.
- **Expand, don't replace** — the existing `processing_datatypes_test` covers 13 of 18 MNN processors. Phase 09 extends this to cover all 18 + RenderProcessor, and adds cross-cutting tests (schema, executor selection, hashing, cancellation, capability, regression) that the existing test doesn't cover.
- **GLSL/SPIR-V as first-class fixtures** — RenderProcessor needs shader fixtures just like MNN processors need model fixtures. A trivial pass-through shader pair (vertex: pass-through coordinates, fragment: solid color or identity texture sample) with known output pixels is sufficient for conformance.
- **Regression tests are targeted, not comprehensive** — the four known bugs each get a minimal synthetic trigger that exercises the exact code path. These are regression guards, not exhaustive edge-case coverage.
</specifics>

<deferred>
## Deferred Ideas

- **Per-processor CTest targets** — per-category organization is simpler and matches existing patterns. Per-processor granularity can be added later if failure isolation becomes an issue.
- **CMake labels for GPU tests** — `GTEST_SKIP()` is sufficient for now. CMake labels (`ctest -L gpu`) can be added if CI scripting needs label-based filtering.
- **Cross-node, cross-vendor determinism tests** — explicitly out of scope per v1.0 DETV-01. Phase 09 tests same-node determinism only.
- **Coverage tooling (gcov/lcov/OpenCppCoverage)** — not scoped for v2.0. Phase 09 adds test coverage through new test cases, not coverage measurement tooling.
- **MoltenVK-specific conformance tests** — macOS CI will exercise the MoltenVK path automatically. No separate MoltenVK-specific test fixtures needed.
</deferred>

---

*Phase: 09-Processor & Pass-Graph Conformance Suites*
*Context gathered: 2026-08-05*
