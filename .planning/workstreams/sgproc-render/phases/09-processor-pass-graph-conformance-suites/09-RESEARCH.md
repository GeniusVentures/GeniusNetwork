# Phase 09: Processor & Pass-Graph Conformance Suites - Research

**Researched:** 2026-08-05
**Domain:** CTest/GTest conformance test infrastructure for C++ processing pipeline (MNN inference, Vulkan compute/render)
**Confidence:** HIGH

## Summary

Phase 09 creates ~7 CTest conformance test executables in `SuperGenius/test/src/`, each covering a distinct dimension of the processor conformance contract: schema parsing, executor selection, output hashing, cancellation, capability validation, regression, and backward-compat migration. Every processor (18 MNN + RenderProcessor) runs a full pipeline through `ProcessingManager::Process()` with deterministic fixtures — pre-baked `.mnn` models, `.raw` input/output, JSON processing definitions, and GLSL/SPIR-V shader pairs — and output hashes are verified against expected values.

The research is HIGH confidence because the codebase provides exhaustive examples of every pattern needed: the `addtest()` CMake macro (`SuperGenius/cmake/functions.cmake`), the `processing_datatypes_test` fixture pattern (13 MNN processors already covered), the SGProcessingManager per-category test pattern (`test/capability/`, `test/execution/`, `test/artifacts/`), the `vulkan_gpu_probe.hpp` GPU detection helper, and the outcome assertion macros. The 5 remaining MNN types (audio, image, ml, string, volume) and RenderProcessor shader fixtures follow the same established patterns.

**Primary recommendation:** Add 6 new `add_subdirectory()` entries to `SuperGenius/test/src/CMakeLists.txt` — one per test category — each following the `addtest()` macro + POST_BUILD fixture copy pattern. Regression tests live inside the relevant category target, not as separate executables.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TEST-01 | `ctest` runs from standalone SGProcessingManager build AND as submodule by SuperGenius. Tests use small deterministic fixtures. | D-04 confirms tests live in SuperGenius. The `addtest()` macro in `SuperGenius/cmake/functions.cmake` already registers targets with CTest. SGProcessingManager standalone tests remain separate in `SGProcessingManager/test/`. |
| TEST-02 | Schema parsing and pass-specific validation tests cover every `PassType` (including render path) with both valid and invalid inputs. | `processing_schema_test` pattern covers schema validation. Render pass already has dispatch tests (`processing_dispatch_test`). New conformance schema tests cover all PassType enum values with positive/negative JSON fixtures. |
| TEST-03 | Executor selection by pass type and backend tested for every registered executor (MNN inference, Vulkan compute, Vulkan render). | `ProcessingManager::RegisterPassProcessorFactory()` and `SetProcessorByPassType()` provide the dispatch points. Tests exercise the existing registry with PassType::INFERENCE, PassType::RENDER, and verify the correct processor factory is invoked. |
| TEST-04 | Every existing MNN processor runs the same core conformance contract — no backend-specific drift. | D-01 confirms: expand the existing `processing_datatypes_test` pattern to remaining 5 MNN types (audio, image, ml, string, volume). Each runs Process() with known fixture, output hash verified. |
| TEST-05 | Native Vulkan compute/render and MoltenVK path run equivalent fixtures where CI hardware permits; unsupported environments skip. | D-05 confirms: `GTEST_SKIP()` + Vulkan device probe at `SetUp()`. `vulkan_gpu_probe.hpp`'s `HasUsableVulkanDevice()` provides the probe. |
| TEST-06 | Output hashing, artifact metadata construction, persistence round-trip, and deterministic serialization tested end-to-end. | `artifact_serializer_test` in SGProcessingManager already covers unit-level round-trip. Conformance tests add pipeline-level verification: Process() → verify ProcessOutput.artifacts + ProcessOutput.manifest. |
| TEST-07 | Cancellation, deadline expiry, budget exceeded, progress event emission, partial result delivery, and resource cleanup tested with at least one processor type. | SGProcessingManager `test/execution/` has unit tests for each concern (cancellation_test, timeout_test, budget_test, progress_event_test, leak_detection_test). Conformance tests add pipeline integration: Process() with ExecutionContext, cancel mid-execution, verify teardown. |
| TEST-08 | Capability acceptance and rejection cases both covered. | `capability_validator_test` covers unit-level. Conformance tests add full pipeline: ProcessingManager::CanExecute() with valid/invalid passes, verify structured rejection reasons. |
| TEST-09 | Migration adapter from ARTF-06 tested — ProcessingResult shape and output-location string behavior preserved. | `migration_adapter_test` covers NoOp. Conformance tests verify: ProcessOutput→ProcessingResult conversion preserves hash.size(), output_locations shape, empty error field on success. |
| TEST-10 | Regression tests for 4 known v1.0 bugs. | D-08 provides exact triggers: (a) multi-pass index mismatch, (b) shader-only ParseBlockSize crash, (c) zero-element output tensor fallback, (d) unregistered PassType silent fallthrough. Each gets a minimal JSON fixture exercising the exact code path. |
</phase_requirements>

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Follow the existing `processing_datatypes_test` pattern — pre-baked tiny `.mnn` models, `.raw` input/output files, JSON processing definitions, Python model-generation scripts, POST_BUILD copy. Expand to remaining 5 MNN types (audio, image, ml, string, volume).
- **D-02:** Add GLSL source + pre-compiled SPIR-V binary fixtures for `RenderProcessor` conformance. Trivial pass-through vertex+fragment shader pair, pre-validated through `spirv-val`.
- **D-03:** Follow existing per-category test pattern — separate test executables by test dimension, each with `add_executable` + `add_test` + `gtest_discover_tests`. Not per-processor targets.
- **D-04:** Conformance tests live in `SuperGenius/test/src/` alongside `processing_datatypes_test`. SGProcessingManager standalone tests remain separate.
- **D-05:** `GTEST_SKIP()` + Vulkan device probe at `SetUp()` for GPU-dependent tests. No special CMake labels initially.
- **D-06:** Full pipeline per processor — Process() with known fixture, verify output hash, verify teardown.
- **D-07:** Conformance contract covers: (a) StartProcessing accepts ExecutionContext + respects cancel callback, (b) progress events at stage boundaries, (c) output hash deterministic, (d) RunTeardown fires on success/cancel/failure.
- **D-08:** Synthetic trigger inputs for 4 known v1.0 bugs — minimal inputs exercising exact code paths. Assert FIXED behavior.

### Claude's Discretion
- Exact GTest suite and test case names
- Exact GLSL/SPIR-V fixture content for RenderProcessor
- Whether conformance tests share a common fixture base class
- CMake library target linkage per test executable
- GTEST_SKIP reason strings
- Whether regression tests are separate executables or within category targets
- Python model-generation scripts for 5 remaining MNN types

### Deferred Ideas (OUT OF SCOPE)
- Per-processor CTest targets
- CMake labels for GPU tests
- Cross-node, cross-vendor determinism tests
- Coverage tooling (gcov/lcov/OpenCppCoverage)
- MoltenVK-specific conformance tests
</user_constraints>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Schema parsing & validation | API / Backend | — | `ProcessingManager::Create()` + `CheckProcessValidity()` operate on JSON job definitions; no UI or storage tier involved |
| Executor selection (PassType → processor) | API / Backend | — | `ProcessingManager::SetProcessorByPassType()` is a pure backend dispatch concern |
| Output hashing & artifact metadata | API / Backend | — | SHA-256 computation and artifact serialization happen inside processors and ProcessingManager |
| Cancellation, deadline, budget, progress | API / Backend | — | ExecutionContext is passed through to processor StartProcessing() — purely backend |
| Capability validation (CanExecute) | API / Backend | — | CapabilityValidator is constructed internally by ProcessingManager — backend only |
| Migration adapter (ProcessOutput→ProcessingResult) | API / Backend | — | `ProcessingResult::FromProcessOutput()` is a static conversion — no tier crossing |
| Regression triggers (synthetic inputs) | API / Backend | — | All 4 bugs are in backend code paths (ParseBlockSize, pass indexing, output-buffer, PassType dispatch) |
| GPU-dependent test probing | API / Backend | — | Vulkan device probe happens at test SetUp() time, targets RenderProcessor backend |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| GTest | ~1.14.0 (pinned in `CommonBuildParameters.cmake`) | Test framework — fixture classes, assertions, `GTEST_SKIP()` | Already used by ALL existing tests in `SuperGenius/test/src/` and `SGProcessingManager/test/` |
| `addtest()` CMake macro | (custom, in `SuperGenius/cmake/functions.cmake`) | Test executable registration — handles `add_executable`, GTest linking, `add_test`, XML output, output directory | Standard for all SuperGenius test targets; 20+ existing uses |
| `gtest_discover_tests()` | CMake builtin via `include(GoogleTest)` | Automatic test case discovery for CTest | Already used in SGProcessingManager test CMakeLists; SuperGenius tests use `addtest()` which calls `add_test()` directly |
| `nlohmann_json` | (as built by thirdparty) | JSON fixture parsing in test setup | Already linked by `processing_datatypes_test`, `processing_schema_test` — needed for conformance tests that parse JSON job definitions |
| `ProcessingBase` | (SGProcessingManager library) | ProcessingManager::Create(), Process(), GetProcessingData() | Already linked by all SuperGenius processing tests |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `SGExecution` | (SGProcessingManager library) | ExecutionContext, CancellationToken, ProgressEvent | Tests exercising cancellation, timeout, budget, progress |
| `SGCapability` | (SGProcessingManager library) | CapabilityValidator, CanExecuteResult | Tests exercising capability acceptance/rejection |
| `SGArtifacts` | (SGProcessingManager library) | Artifact, ExecutionManifest, artifact serialization | Tests verifying output hashing and metadata |
| `sgprocmanagersha` | (SGProcessingManager library) | SHA-256 hashing utilities | Tests verifying content hashes |
| `sgprocmanagerlogger` | (SGProcessingManager library) | Structured logging | Tests that verify error stage classification |
| `sgprocmanagertypes` | (SGProcessingManager library) | Core type definitions | Capability validation tests |
| `vulkan_gpu_probe.hpp` | (header-only, in `SGProcessingManager/include/processors/`) | `HasUsableVulkanDevice()` | GPU-dependent tests — probe at SetUp(), skip if false |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `addtest()` macro | Raw `add_executable` + `target_link_libraries` + `add_test` | `addtest()` auto-configures output dirs and XML output; raw approach used in SGProcessingManager standalone tests for finer control. Both valid — D-03 says "follow existing per-category pattern" which uses raw `add_executable`, but D-04 says "live in SuperGenius/test/src/" where `addtest()` is the convention. **Recommend `addtest()` for SuperGenius-hosted tests** to match `processing_datatypes_test`, `processing_schema_test`, etc. |

**Installation:** No new external packages. All libraries already exist in the build.

**Version verification:** All dependencies are internal SGProcessingManager/SuperGenius libraries — no npm/PyPI/crates.io packages to verify.

## Package Legitimacy Audit

> SKIPPED — No external packages are installed by this phase. All dependencies are existing internal C++ libraries.

## Architecture Patterns

### System Architecture Diagram

```text
┌─────────────────────────────────────────────────────────────┐
│                    CTest (ctest -C Release)                  │
├─────────────────────────────────────────────────────────────┤
│  SuperGenius/test/src/                                       │
│  ┌──────────────────────┐  ┌──────────────────────────┐     │
│  │ processing_datatypes │  │ processing_conformance_*  │     │
│  │ _test (existing)     │  │ (NEW — Phase 09)          │     │
│  │                      │  │                           │     │
│  │ 13 MNN processors ✓  │  │ schema_validation_test    │     │
│  │ +5 new MNN types     │  │ executor_selection_test   │     │
│  └──────┬───────────────┘  │ output_hashing_test       │     │
│         │                  │ cancellation_test         │     │
│         │                  │ capability_test           │     │
│         │                  │ regression_test           │     │
│         │                  │ migration_adapter_test    │     │
│         │                  └──────────┬───────────────┘     │
│         │                             │                      │
│         └──────────┬──────────────────┘                      │
│                    ▼                                         │
│         ProcessingManager::Process()                         │
│         ProcessingManager::CanExecute()                      │
│         ProcessingManager::CheckProcessValidity()            │
│                    │                                         │
│         ┌──────────┼──────────┐                              │
│         ▼          ▼          ▼                              │
│   MNN Processor  RenderProc  Capability                      │
│   (18 types)     (Vulkan)    Validator                       │
│         │          │          │                              │
│         └──────────┼──────────┘                              │
│                    ▼                                         │
│         Fixture Files (POST_BUILD copy)                      │
│         *.mnn, *.raw, *.json, *.glsl, *.spv                  │
└─────────────────────────────────────────────────────────────┘

Fixture Generation (offline, not in CTest):
  Python scripts (*.py) → ONNX models → MNNConvert → *.mnn
  GLSL shaders → glslangValidator → SPIR-V binaries (*.spv)
```

### Recommended Project Structure

```
SuperGenius/test/src/
├── CMakeLists.txt                              # ADD: 6 new add_subdirectory() entries
├── processing_datatypes/                       # EXTEND: +5 MNN types
│   ├── CMakeLists.txt                          # EXTEND: +POST_BUILD copy for new fixtures
│   ├── processing_datatypes_test.cpp           # EXTEND: +ValidationTest/ProcessingTest per new type
│   ├── create_audio_model.py                   # NEW
│   ├── create_image_model.py                   # NEW
│   ├── create_ml_model.py                      # NEW
│   ├── create_string_model.py                  # NEW (full conformance, not just schema)
│   ├── create_volume_model.py                  # NEW
│   ├── audio-processing-definition.json        # NEW
│   ├── audio_tiny.mnn                          # NEW
│   ├── audio_input.raw                         # NEW
│   ├── audio_output_pt.raw                     # NEW
│   ├── image-processing-definition.json        # NEW
│   ├── image_tiny.mnn                          # NEW
│   ├── image_input.raw                         # NEW
│   ├── image_output_pt.raw                     # NEW
│   ├── ml-processing-definition.json           # NEW
│   ├── ml_tiny.mnn                             # NEW
│   ├── ml_input.raw                            # NEW
│   ├── ml_output_pt.raw                        # NEW
│   ├── string-conformance-definition.json      # NEW (full pipeline, beyond existing schema test)
│   ├── volume-processing-definition.json       # NEW
│   └── ... (existing 13 type fixtures)
├── processing_conformance_schema/              # NEW: TEST-02
│   ├── CMakeLists.txt
│   ├── schema_validation_test.cpp
│   └── fixtures/
│       ├── valid-every-passtype.json
│       ├── invalid-missing-model.json
│       ├── invalid-bad-format.json
│       ├── render-valid.json
│       ├── render-missing-shader.json
│       └── render-bad-spirv.json
├── processing_conformance_executor/            # NEW: TEST-03
│   ├── CMakeLists.txt
│   └── executor_selection_test.cpp
├── processing_conformance_hashing/             # NEW: TEST-06
│   ├── CMakeLists.txt
│   ├── output_hashing_test.cpp
│   └── fixtures/
│       └── (shares processing_datatypes fixtures via ../ reference)
├── processing_conformance_cancellation/        # NEW: TEST-07
│   ├── CMakeLists.txt
│   └── cancellation_conformance_test.cpp
├── processing_conformance_capability/          # NEW: TEST-08
│   ├── CMakeLists.txt
│   └── capability_conformance_test.cpp
├── processing_conformance_regression/          # NEW: TEST-10
│   ├── CMakeLists.txt
│   ├── regression_test.cpp
│   └── fixtures/
│       ├── regression-a-index-mismatch.json
│       ├── regression-b-parseblocksize-model-only.json
│       ├── regression-c-output-buffer-zero.json
│       └── regression-d-unsupported-passtype.json
└── processing_conformance_migration/           # NEW: TEST-09
    ├── CMakeLists.txt
    └── migration_adapter_conformance_test.cpp
```

### Pattern 1: addtest() Macro Test Registration

**What:** Use the `addtest()` macro from `SuperGenius/cmake/functions.cmake` for all new test executables in `SuperGenius/test/src/`.

**When to use:** Every new conformance test target. This is the standard SuperGenius convention — 20+ existing targets use it.

**Example:**
```cmake
# Source: SuperGenius/test/src/processing_datatypes/CMakeLists.txt
addtest(processing_conformance_schema_test
    schema_validation_test.cpp
)

target_include_directories(processing_conformance_schema_test
    PRIVATE ${AsyncIOManager_INCLUDE_DIR}
)

target_link_libraries(processing_conformance_schema_test
    nlohmann_json
    ProcessingBase
)

add_custom_command(TARGET processing_conformance_schema_test POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
    "${CMAKE_CURRENT_SOURCE_DIR}/fixtures/"
    "$<TARGET_FILE_DIR:processing_conformance_schema_test>/fixtures/"
    COMMENT "Copying schema conformance test fixtures"
)
```

### Pattern 2: ProcessingManager Pipeline Test

**What:** Create ProcessingManager from JSON, call Process(), verify output hash and teardown.

**When to use:** Every processor conformance test (D-06).

**Example:**
```cpp
// Source: SuperGenius/test/src/processing_datatypes/processing_datatypes_test.cpp lines ~96-150 (StringInputProcessingTest)
TEST_F( ProcessorConformanceFixture, MNNStringFullPipeline )
{
    const std::string &json = PatchedJson( "string-conformance-definition.json" );
    ASSERT_FALSE( json.empty() );

    auto mgr = sgns::sgprocessing::ProcessingManager::Create( json );
    ASSERT_TRUE( mgr.has_value() );

    auto processing = mgr.value()->GetProcessingData();
    const auto &passes = processing.get_passes();
    ASSERT_EQ( passes.size(), 1 );

    auto ioc = std::make_shared<boost::asio::io_context>();
    std::vector<std::vector<uint8_t>> chunkhashes;
    std::vector<std::string> output_locations;
    sgns::ModelNode model_node = passes[0].get_model().value().get_input_nodes()[0];

    auto result = mgr.value()->Process( ioc, chunkhashes, model_node, output_locations );

    ASSERT_TRUE( result.has_value() ) << result.error().message();
    ASSERT_FALSE( result.value().empty() );

    // Verify deterministic output against expected hash
    // (expected hash derived from reference PyTorch output)
    ASSERT_GT( chunkhashes.size(), 0 );
}
```

### Pattern 3: Vulkan GPU Probe + GTEST_SKIP

**What:** Call `HasUsableVulkanDevice()` in `SetUp()` — if false, skip the entire test suite.

**When to use:** Any test that requires a Vulkan GPU (RenderProcessor conformance, native Vulkan paths).

**Example:**
```cpp
// Source: SuperGenius/SGProcessingManager/include/processors/vulkan_gpu_probe.hpp
// and existing pattern in processing_dispatch_test.cpp
#include <processors/vulkan_gpu_probe.hpp>

class RenderConformanceTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        if ( !sgns::sgprocessing::HasUsableVulkanDevice() )
        {
            GTEST_SKIP() << "No Vulkan device available — "
                            "DISCRETE_GPU/INTEGRATED_GPU not found, "
                            "or MoltenVK not present";
        }
    }
};
```

### Pattern 4: Shared Fixture Base Class

**What:** A common `ProcessorConformanceFixture` base class providing `PatchJsonUrisToAbsolute()`, `DataPath()`, and fixture caching.

**When to use:** All conformance test executables that parse JSON job definitions with `file://` URIs. This is a recommendation within Claude's discretion — it parallels the existing `ProcessingDatatypesTest` fixture class.

**Example:**
```cpp
// Reuse the exact pattern from processing_datatypes_test.cpp lines ~20-85
class ProcessorConformanceFixture : public ::testing::Test
{
protected:
    static inline std::string binary_path;
    static inline std::string data_path;
    static inline std::map<std::string, std::string> patched_json_cache;

    static void SetUpTestSuite()
    {
        binary_path = boost::dll::program_location().parent_path().string() + "/";
        data_path   = binary_path + "fixtures/";
    }

    static const std::string &PatchedJson( const std::string &filename )
    {
        // ... same caching + PatchJsonUrisToAbsolute pattern
    }
};
```

### Pattern 5: Regression Test Structure

**What:** Regression tests live within the relevant category target, not as separate executables.

**When to use:** TEST-10's 4 regression test cases — each maps to a specific test dimension (schema, executor selection, MNN processing, capability) and fits naturally in the corresponding category test.

**Example:**
```cpp
// In processing_conformance_regression/regression_test.cpp
TEST_F( RegressionTest, BugA_IndexMismatchInPassInputIndexing )
{
    // Minimal multi-pass job: 2 passes, second pass's input references pass index
    // that shifts after first pass insertion
    const std::string json = R"({...})";  // synthetic trigger
    auto mgr = ProcessingManager::Create( json );
    ASSERT_TRUE( mgr.has_value() );  // FIXED: should not crash or mis-index
    // Verify input bindings resolve to correct pass indices
}

TEST_F( RegressionTest, BugB_ModelOnlyAssumptionCrashInParseBlockSize )
{
    // Shader-only render pass with NO "model" field
    const std::string json = LoadFixture( "regression-b-parseblocksize-model-only.json" );
    auto mgr = ProcessingManager::Create( json );
    ASSERT_TRUE( mgr.has_value() );  // FIXED: should not crash
    auto blockSize = mgr.value()->ParseBlockSize();
    ASSERT_TRUE( blockSize.has_value() );  // FIXED: should return valid size for render passes
}
```

### Anti-Patterns to Avoid
- **Per-processor executables:** D-03 explicitly says "not per-processor targets." Group by test dimension.
- **Hardcoded absolute paths in JSON fixtures:** Use relative `file://` URIs + `PatchJsonUrisToAbsolute()` — the existing pattern.
- **Skipping teardown verification:** D-07(d) requires verifying RunTeardown fires on all paths. Don't just check Process() succeeded — also verify no leaks.
- **GPU tests that fail on CPU-only CI:** Always probe with `HasUsableVulkanDevice()` and `GTEST_SKIP()`. Never `FAIL()` on missing GPU.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Test executable registration | Custom CMake `add_executable` + manual `add_test` | `addtest()` macro from `SuperGenius/cmake/functions.cmake` | Standardizes output dirs, XML output, GTest linking — 20+ existing targets use it |
| JSON URI path resolution | Manual string manipulation per test | `PatchJsonUrisToAbsolute()` helper (already implemented in `processing_datatypes_test.cpp`) | Handles Windows/Linux path separators, `file://` scheme, regex-based replacement |
| Vulkan device detection | Custom `vkEnumeratePhysicalDevices` in each test | `vulkan_gpu_probe.hpp`'s `HasUsableVulkanDevice()` | Already mirrors RenderProcessor::IsAcceptable's device-type filter — avoids drift |
| Outcome assertion boilerplate | `if (result) { ... } else { FAIL() }` | `EXPECT_OUTCOME_TRUE`, `ASSERT_OUTCOME_SUCCESS` macros from `test/testutil/outcome.hpp` | Consistent error messages, line numbers, value extraction |
| MNN model generation | Manual model construction | Existing Python scripts (`create_float_model.py`, etc.) — extend the pattern | Deterministic, reproducible, already integrated with MNNConvert toolchain |

**Key insight:** All infrastructure already exists. Phase 09 primarily extends existing patterns — new test files, new fixtures, new JSON definitions — not new infrastructure.

## Runtime State Inventory

> SKIPPED — Phase 09 is purely additive (new test files, new fixtures). No rename, refactor, or migration to perform.

## Common Pitfalls

### Pitfall 1: fixture file paths break when SuperGenius builds as submodule

**What goes wrong:** Tests use `CMAKE_CURRENT_SOURCE_DIR` for fixture paths, but when SuperGenius is a submodule of GeniusSDK, the build directory structure differs.

**Why it happens:** The `addtest()` macro sets `RUNTIME_OUTPUT_DIRECTORY` to `${CMAKE_BINARY_DIR}/test_bin`, which may not match the source tree layout.

**How to avoid:** Use `$<TARGET_FILE_DIR:target_name>` in POST_BUILD copy commands (generator expression — always resolves correctly). Fixture loading in C++ uses `boost::dll::program_location().parent_path()` at runtime — already the pattern in `processing_datatypes_test.cpp`. [VERIFIED: codebase — `processing_datatypes_test.cpp` line 78]

**Warning signs:** `Failed to open instance file` errors in CI but not local builds.

### Pitfall 2: MNN model forward-compatibility across MNN versions

**What goes wrong:** Pre-baked `.mnn` models generated with one MNN version fail to load with a different MNN version.

**Why it happens:** MNN model format can change between versions (though it strives for backward compatibility).

**How to avoid:** Regenerate `.mnn` models from source ONNX files as part of the build or document the MNN version used for generation. The existing Python scripts produce ONNX first, then convert via `MNNConvert` — regeneration is scriptable. [CITED: `create_buffer_model.py` lines 56-58]

**Warning signs:** MNN session creation failures in tests after upgrading thirdparty MNN.

### Pitfall 3: SPIR-V binary fixture endianness

**What goes wrong:** Pre-compiled SPIR-V binaries are little-endian (SPIR-V spec requirement), but test infrastructure or CI might produce big-endian artifacts on some platforms.

**Why it happens:** SPIR-V is always little-endian per the Khronos spec, but `glslangValidator` output on a big-endian host could theoretically produce incorrect byte order.

**How to avoid:** Generate SPIR-V fixtures on an x86_64 (LE) host. Pre-validate with `spirv-val`. Store as binary blobs — never as text. The existing `render-pass-happy-path-definition.json` already shows the pattern of referencing shader files by URI. [VERIFIED: codebase — `processing_dispatch/` directory]

**Warning signs:** `VK_ERROR_INVALID_SHADER_NV` or SPIR-V validation errors on ARM64 macOS CI.

### Pitfall 4: GTEST_SKIP in SetUpTestSuite vs SetUp

**What goes wrong:** `GTEST_SKIP()` in `SetUpTestSuite()` (static) behaves differently from `SetUp()` (per-test). Skipping in `SetUpTestSuite` skips ALL tests in the suite, which is desired for GPU tests.

**Why it happens:** GTest's `SetUpTestSuite()` is called once; `SetUp()` is called before each test. `GTEST_SKIP()` in `SetUpTestSuite()` causes all tests to be skipped, which is correct when no GPU is available.

**How to avoid:** Put Vulkan device probe in `SetUpTestSuite()` for RenderProcessor conformance tests — skips the entire suite once if no GPU. This matches D-05: "GTEST_SKIP() + Vulkan device probe at SetUp() time" but `SetUpTestSuite()` is more efficient (no per-test probe). [VERIFIED: codebase — `processing_datatypes_test.cpp` uses `SetUpTestSuite()` for path initialization]

### Pitfall 5: Output hash nondeterminism from floating-point variance

**What goes wrong:** MNN Vulkan backend may produce slightly different floating-point results than CPU backend, or different GPU drivers produce different results.

**Why it happens:** Vulkan shader floating-point operations can vary by GPU/driver (mad vs. fmad instructions, denorm handling, etc.).

**How to avoid:** Use tolerance-based comparison (`mean_abs_diff < 1e-3`, `max_abs_diff < 1e-2`) for floating-point output verification — the existing pattern in `processing_datatypes_test.cpp`. For hash-based verification, verify that the hash is stable across repeated runs on the SAME hardware (D-06: same-node determinism). Cross-vendor determinism is explicitly deferred. [VERIFIED: codebase — `processing_datatypes_test.cpp` Texture1DProcessingTest lines ~470-490]

## Code Examples

Verified patterns from the codebase:

### MNN Processor Test with Output Verification
```cpp
// Source: SuperGenius/test/src/processing_datatypes/processing_datatypes_test.cpp
// Pattern used by BoolProcessingTest, BufferProcessingTest, FloatProcessingTest, etc.
TEST_F( ProcessingDatatypesTest, BufferProcessingTest )
{
    const std::string &instance_str = PatchedJson( "buffer-processing-definition.json" );
    ASSERT_FALSE( instance_str.empty() );

    auto manager_result = sgns::sgprocessing::ProcessingManager::Create( instance_str );
    ASSERT_TRUE( manager_result.has_value() );

    const auto &manager = manager_result.value();
    auto processing = manager->GetProcessingData();
    const auto &passes = processing.get_passes();
    ASSERT_EQ( passes.size(), 1 );
    ASSERT_TRUE( passes[0].get_model().has_value() );
    const auto model = passes[0].get_model().value();
    const auto &input_nodes = model.get_input_nodes();
    ASSERT_EQ( input_nodes.size(), 1 );

    auto ioc = std::make_shared<boost::asio::io_context>();
    std::vector<std::vector<uint8_t>> chunkhashes;
    std::vector<std::string> output_locations;
    sgns::ModelNode model_node = input_nodes[0];

    auto process_result = manager->Process( ioc, chunkhashes, model_node, output_locations );

    ASSERT_TRUE( process_result.has_value() );
    ASSERT_FALSE( process_result.value().empty() );
    ASSERT_GT( chunkhashes.size(), 0 );

    // Compare output to reference
    const std::string output_file    = DataPath() + "buffer_output.raw";
    const std::string reference_file = DataPath() + "buffer_output_pt.raw";
    // ... binary comparison with mean_abs_diff < 1e-3, max_abs_diff < 1e-2
}
```

### CancellationToken Unit Test (No ProcessingManager needed)
```cpp
// Source: SuperGenius/SGProcessingManager/test/execution/cancellation_test.cpp lines 67-80
TEST_F( CancellationTest, CancelBeforeStart )
{
    CancellationToken token;
    EXPECT_FALSE( token.IsCancelled() );

    bool callbackInvoked = false;
    token.SetCallback( [&callbackInvoked]() { callbackInvoked = true; } );

    token.Cancel();
    EXPECT_TRUE( token.IsCancelled() );
    EXPECT_TRUE( callbackInvoked );

    // Second cancel should not invoke callback again
    callbackInvoked = false;
    token.Cancel();
    EXPECT_FALSE( callbackInvoked );
}
```

### Migration Adapter Shape Verification
```cpp
// Source: SuperGenius/SGProcessingManager/test/execution/migration_adapter_test.cpp lines 22-35
TEST_F( MigrationAdapterTest, NoOpDoesNotCancel )
{
    auto ctx = ExecutionContext::NoOp();
    EXPECT_FALSE( ctx->cancelToken.IsCancelled() );
}

TEST_F( MigrationAdapterTest, NoOpProgressCallbackDoesNotThrow )
{
    auto ctx = ExecutionContext::NoOp();
    EXPECT_NO_THROW( ctx->progressCallback(
        ProgressEvent::ForRender( "test", RenderStage::COMPILE, 0.0f ) ) );
}
```

### CapabilityValidator Mock Snapshot Pattern
```cpp
// Source: SuperGenius/SGProcessingManager/test/capability/capability_validator_test.cpp lines 20-70
CapabilitySnapshot MakeMockSnapshot()
{
    CapabilitySnapshot snap;
    snap.vulkanProps.deviceType = VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU;
    snap.vulkanProps.limits.maxImageDimension2D = 16384;
    snap.vulkanProps.limits.maxColorAttachments  = 8;
    // ... fill in mock device properties
    snap.availableDiskBytes = 100ULL * 1024 * 1024 * 1024;
    // Register RENDER executor
    ExecutorCapability cap;
    cap.passType = PassType::RENDER;
    cap.backend  = "VULKAN";
    snap.executorCaps.push_back( cap );
    return snap;
}
```

### Python Model Generation Script Pattern
```python
# Source: SuperGenius/test/src/processing_datatypes/create_buffer_model.py
# Pattern: PyTorch → ONNX → MNNConvert
class TinyBufferNet(nn.Module):
    def __init__(self, length):
        super().__init__()
        self.fc1 = nn.Linear(length, length)
        self.act = nn.ReLU()
        self.fc2 = nn.Linear(length, length)

    def forward(self, x):
        return self.fc2(self.act(self.fc1(x.float())))

# Export to ONNX, then convert: MNNConvert -f ONNX --modelFile X.onnx --MNNModel X.mnn
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Per-processor ad-hoc testing | Per-category conformance contract (D-03) | Phase 09 | 6-7 test executables cover all 20 processors systematically |
| GPU tests fail on headless CI | `GTEST_SKIP()` + Vulkan device probe (D-05) | Phase 09 | CI passes cleanly on GPU-less nodes |
| No teardown verification | `RunTeardown()` tested on success/cancel/failure (D-07) | Phase 07/09 | Resource leak detection in CI |
| No regression guards for v1.0 bugs | Synthetic trigger inputs assert FIXED behavior (D-08) | Phase 09 | Prevents regression of 4 known v1.0 bugs |

**Deprecated/outdated:**
- Manual `VkInstance` creation in each GPU test — use `RenderProcessor::InitializeContext()` or `vulkan_gpu_probe.hpp`'s `HasUsableVulkanDevice()` instead.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The 5 remaining MNN processor types (audio, image, ml, string, volume) follow the same `Process()` interface as the 13 already-covered types | Processor Inventory | If any of these 5 processors have fundamentally different initialization requirements, the `processing_datatypes_test` pattern won't directly apply — need custom fixture setup. LOW risk: all 18 MNN processors inherit from the same `ProcessingProcessor` base class. |
| A2 | `gtest_discover_tests()` is available in SuperGenius test CMakeLists (not just SGProcessingManager) | CMake Integration | If `include(GoogleTest)` is not available in the SuperGenius test scope, fall back to explicit `add_test()` calls (which `addtest()` already does). LOW risk: `addtest()` already handles `add_test()` registration. |
| A3 | Regression test bug triggers (D-08) can be expressed as JSON processing definitions | Regression Tests | If any bug requires programmatic trigger construction (not just JSON), need C++ helper to construct the trigger state. MEDIUM risk: bug (b) "model-only assumption crash in ParseBlockSize()" needs a shader-only job definition, which should be expressible as JSON. |
| A4 | RenderProcessor shader fixtures can use existing `processing_dispatch/` shaders (`scalar_position_vertex_shader.glsl`, `solid_red_fragment_shader.glsl`) | RenderProcessor Fixtures | If the RenderProcessor conformance test needs different shader behavior (e.g., texture sampling, uniform blocks), new shader fixtures are needed. LOW risk: the existing shaders are trivially simple pass-through shaders ideal for conformance testing. |
| A5 | `ProcessingBase` library target includes `ProcessingManager` and all MNN processor implementations | CMake Linkage | If `ProcessingBase` only includes the base classes and not processor implementations, tests need additional links to individual processor libraries. LOW risk: `processing_datatypes_test` links only `ProcessingBase` and successfully calls `Process()` on all processor types. |
| A6 | `SGPROCMGR_TEST_FRIEND` is not needed for conformance tests (they exercise public API only) | Test Access | If internal ProcessingManager state needs verification (teardown stack, processor registry), `SGPROCMGR_TEST_FRIEND` may be needed. LOW risk: conformance tests verify through public API (Process(), CanExecute(), CheckProcessValidity()). |

## Open Questions (RESOLVED 2026-08-05 — per PLAN.md)

1. **Should the string processor get a new Python model-gen script, or should the existing `bert-tiny.mnn` + `string-processing-definition.json` be reused for conformance?** **(RESOLVED: New Python script)**
   - Decision per 09-01-PLAN.md: Add `create_string_model.py` generating a tiny deterministic string model. The existing `bert-tiny.mnn` (~16MB) is too large for CI speed.

2. **Should `gtest_discover_tests()` be used instead of `addtest()` for the new conformance test executables?** **(RESOLVED: Use `addtest()`)**
   - Decision per 09-03 through 09-06 PLANs: Use `addtest()` to match SuperGenius conventions. The macro already handles `add_test()` + XML output.

3. **Where should shared fixture base class code live?** **(RESOLVED: test/testutil/)**
   - Decision per 09-01-PLAN.md: Create `SuperGenius/test/testutil/processing_conformance_fixture.hpp`. Follows existing `base_fs_test.hpp` pattern.

4. **Should regression tests be in one executable or split across category targets?** **(RESOLVED: Single executable)**
   - Decision per 09-06-PLAN.md: All 4 regression tests in one `processing_conformance_regression` executable. Simpler to maintain and run.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| CMake | Test build system | ✓ [ASSUMED] | 3.5+ (per STACK.md) | — |
| GTest | Test framework | ✓ [VERIFIED: codebase — CommonBuildParameters.cmake pins ~1.14.0] | ~1.14.0 | — |
| Python 3.7+ | Fixture generation scripts (offline, not in CTest) | ✓ [ASSUMED] | — | Pre-generated fixtures checked into repo; Python only needed when regenerating |
| PyTorch (`torch`) | MNN model generation scripts (offline) | ✗ [ASSUMED — not probed] | — | Models are pre-generated and checked in; PyTorch only needed for regeneration |
| MNNConvert | ONNX→MNN conversion (offline) | ✗ [ASSUMED — not probed] | — | `.mnn` files are pre-generated and checked in; MNNConvert only needed for regeneration |
| `glslangValidator` | GLSL→SPIR-V compilation (offline) | ✗ [ASSUMED — not probed] | — | Pre-compiled `.spv` files checked in; glslangValidator only needed for regeneration |
| `spirv-val` | SPIR-V validation (offline) | ✗ [ASSUMED — not probed] | — | Pre-validated `.spv` files checked in; spirv-val only needed for regeneration |
| Vulkan GPU | RenderProcessor conformance tests | ✗ [ASSUMED — CI may lack GPU] | — | `GTEST_SKIP()` via `HasUsableVulkanDevice()` — tests gracefully skip |
| MNN runtime | All MNN processor tests | ✓ [VERIFIED: codebase — MNN is a thirdparty dependency] | — | — |

**Missing dependencies with no fallback:**
- None — all build-time dependencies are already in the thirdparty tree. Offline fixture generation tools can be installed as needed.

**Missing dependencies with fallback:**
- Vulkan GPU → `GTEST_SKIP()` with explicit reason string
- PyTorch, MNNConvert, glslangValidator, spirv-val → pre-generated fixtures checked into repo

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | yes | JSON schema validation via `CheckProcessValidity()`, pass-specific validation in `processing_schema_test`. Malformed shader/SPIR-V tests in `processing_dispatch_test` pattern. |
| V6 Cryptography | yes | SHA-256 content hashing via `sgprocmanagersha` library — already verified in Phase 08 (ARTF-05 determinism). Never hand-roll. |

### Known Threat Patterns for C++ GTest / Processing Pipeline

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malformed JSON job definition crashes parser | Denial of Service | `CheckProcessValidity()` returns structured error, never crashes. Conformance tests verify: invalid JSON → error, not crash. |
| Shader injection via malicious GLSL/SPIR-V | Elevation of Privilege | SPIR-V validated through `spirv-val` before use. RenderProcessor's `ParseCompiledStages()` bounds-checks every read. Conformance tests verify: malformed SPIR-V → FORMAT_UNSUPPORTED error, not crash. |
| Unbounded render target dimensions | Denial of Service | `kMaxRenderDimension = 8192` in RenderProcessor. Conformance tests verify: oversized render target → rejection. |
| Unsigned shader execution | Tampering | All shader fixtures for conformance are pre-validated and checked into repo. No runtime shader compilation from untrusted sources in tests. |
| Test fixture files with path traversal | Tampering | `PatchJsonUrisToAbsolute()` resolves relative URIs against known `data_path` — no `../` escape possible because the helper strips the relative prefix and prepends the binary path. |

## Sources

### Primary (HIGH confidence)
- `SuperGenius/test/src/processing_datatypes/CMakeLists.txt` — `addtest()` macro usage, POST_BUILD fixture copy pattern
- `SuperGenius/test/src/processing_datatypes/processing_datatypes_test.cpp` — GTest fixture class, `PatchJsonUrisToAbsolute()`, pipeline test pattern
- `SuperGenius/cmake/functions.cmake` — `addtest()` macro definition (links GTest::gtest_main + GTest::gmock_main, sets RUNTIME_OUTPUT_DIRECTORY, XML output)
- `SuperGenius/test/src/CMakeLists.txt` — `add_subdirectory()` registration point for new test targets
- `SuperGenius/SGProcessingManager/test/capability/capability_validator_test.cpp` — Mock snapshot pattern, `SGPROCMGR_TEST_FRIEND`
- `SuperGenius/SGProcessingManager/test/execution/cancellation_test.cpp` — CancellationToken unit test pattern
- `SuperGenius/SGProcessingManager/test/execution/migration_adapter_test.cpp` — Migration adapter shape verification pattern
- `SuperGenius/SGProcessingManager/test/artifacts/artifact_serializer_test.cpp` — Artifact round-trip test pattern
- `SuperGenius/SGProcessingManager/include/processors/vulkan_gpu_probe.hpp` — `HasUsableVulkanDevice()` declaration
- `SuperGenius/SGProcessingManager/include/processors/processing_processor.hpp` — `ProcessingProcessor`, `ProcessingResult`, `ProcessingError`, `ProcessingErrorStage` full definitions
- `SuperGenius/SGProcessingManager/include/processingbase/ProcessingManager.hpp` — `Process()`, `CanExecute()`, `CheckProcessValidity()`, `ProcessOutput`, executor registry
- `SuperGenius/test/testutil/outcome.hpp` — `EXPECT_OUTCOME_TRUE`, `ASSERT_OUTCOME_SUCCESS` macros
- `SuperGenius/test/src/processing_dispatch/` — GLSL shader fixtures, SPIR-V, render pass JSON definitions, happy-path definition
- `SuperGenius/test/src/processing_datatypes/create_buffer_model.py` — Python model-generation script pattern
- `SuperGenius/test/src/processing_datatypes/buffer-processing-definition.json` — JSON processing definition schema
- `.planning/workstreams/sgproc-render/phases/09-processor-pass-graph-conformance-suites/09-CONTEXT.md` — Locked decisions D-01 through D-08

### Secondary (MEDIUM confidence)
- `SuperGenius/SGProcessingManager/test/execution/CMakeLists.txt` — Per-category `add_executable` + `gtest_discover_tests` pattern
- `SuperGenius/SGProcessingManager/test/CMakeLists.txt` — `include(GoogleTest)` availability in SGProcessingManager scope

### Tertiary (LOW confidence)
- None — all research was codebase-verified.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries already exist in the codebase; no external packages needed
- Architecture: HIGH — every pattern has at least one existing implementation to copy from
- Pitfalls: HIGH — pitfalls derived from codebase patterns and CI concerns documented in existing tests

**Research date:** 2026-08-05
**Valid until:** 2026-09-05 (30 days — stable domain, no external dependency changes expected)
