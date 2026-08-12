# Phase 12: Quantization / Normalization Implementation - Pattern Map

**Mapped:** 2026-08-12
**Files analyzed:** 6 (2 to implement, ~2 call-site references confirming no changes needed, 2 new test/build files)
**Analogs found:** 6 / 6

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|----------------|
| `SuperGenius/SGProcessingManager/include/util/quantization.hpp` | utility (header, pure function decls) | transform | same file (Phase 10 stub, in-repo) | exact — signatures final, doc comments to update only |
| `SuperGenius/SGProcessingManager/src/util/quantization.cpp` | utility (in-place buffer transform) | transform | same file (Phase 10 stub, in-repo) + `SuperGenius/SGProcessingManager/src/util/sha256.cpp` (sibling utility, same directory/namespace convention) | exact for shape, sha256.cpp for style |
| *(no call-site changes)* `processing_processor_mnn_float.cpp:307-360` | processor (call site, unchanged) | CRUD-adjacent / transform-then-hash | itself — already wired by Phase 10, confirms no edits needed | n/a (verification only) |
| *(no call-site changes)* `processing_processor_render.cpp:2198-2214` | processor (call site, unchanged) | transform-then-hash | itself — already wired by Phase 10, confirms no edits needed | n/a (verification only) |
| New SECV-01 counter-test (e.g. `SuperGenius/test/src/processing_conformance_security/secv01_counter_test.cpp` — name at Claude's discretion) | test (CTest conformance suite) | request-response (Create→Process→assert) | `SuperGenius/test/src/processing_conformance_hashing/output_hashing_test.cpp` (hash-assertion shape) + `SuperGenius/test/src/processing_conformance_cancellation/cancellation_conformance_test.cpp` (GTEST_SKIP/Vulkan-probe + render JSON fixture shape) | role-match (hashing test) + role-match (Vulkan-skip pattern) |
| New SECV-01 CTest registration, e.g. `SuperGenius/test/src/processing_conformance_security/CMakeLists.txt` | config (build/test registration) | n/a | `SuperGenius/test/src/processing_conformance_hashing/CMakeLists.txt` and `processing_conformance_cancellation/CMakeLists.txt` | exact — both use identical `addtest(...)` macro shape |

## Pattern Assignments

### `SuperGenius/SGProcessingManager/include/util/quantization.hpp` (utility, transform)

**Analog:** itself (Phase 10 stub) — full current content, lines 1-27:

```cpp
#ifndef SGPROCMGR_QUANTIZATION_HPP
#define SGPROCMGR_QUANTIZATION_HPP

#include <cstddef>
#include <cstdint>

namespace sgns::sgprocmanagerquant
{
    /// Phase 10 no-op/identity stub. Phase 12 replaces this body with real
    /// IEEE-754 canonicalization (NaN/Inf/denormal/signed-zero normalization)
    /// plus fixed-precision scale-round-cast, once Phase 11's empirical
    /// cross-machine capture data justifies a real constant.
    ///
    /// @param data  Pointer to a float buffer to (eventually) quantize in place.
    /// @param count Number of float elements in the buffer.
    void QuantizeFloatBuffer( float *data, size_t count );

    /// Phase 10 no-op/identity stub. Phase 12 replaces this body with real
    /// integer tolerance-banding for the byte path, once Phase 11's empirical
    /// cross-machine capture data justifies a real constant.
    ///
    /// @param data  Pointer to a byte buffer to (eventually) quantize in place.
    /// @param count Number of bytes in the buffer.
    void QuantizeByteBuffer( uint8_t *data, size_t count );
}

#endif
```

**Signatures are final (per CONTEXT.md canonical_refs) — do not change the function names, parameter types, or `sgns::sgprocmanagerquant` namespace.** Only the doc comments change (drop "Phase 10 no-op stub" language, document the real D-03/D-05/D-06-D-09 semantics: fixed-point scale-round-cast grid, NaN/Inf/denormal/zero canonicalization for the float path; D-11's "wrong shader constant must still diverge" — i.e. `QuantizeByteBuffer` must remain a true identity/tolerance-band function, not lossy-enough to mask SECV-01's render counter-test).

---

### `SuperGenius/SGProcessingManager/src/util/quantization.cpp` (utility, transform)

**Analog:** itself (Phase 10 stub, full current content, lines 1-21) — the body to replace:

```cpp
#include "util/quantization.hpp"

namespace sgns::sgprocmanagerquant
{
    void QuantizeFloatBuffer( float *data, size_t count )
    {
        // Phase 10 identity stub — see header doc comment. No arithmetic on data.
        (void)data;
        (void)count;
    }

    void QuantizeByteBuffer( uint8_t *data, size_t count )
    {
        // Phase 10 identity stub — see header doc comment. No arithmetic on data.
        (void)data;
        (void)count;
    }
} // namespace sgns::sgprocmanagerquant
```

**Sibling-utility style analog:** `SuperGenius/SGProcessingManager/src/util/sha256.cpp` and `SuperGenius/SGProcessingManager/include/util/sha256.hpp` — for the file-header/include-guard/namespace convention this pair already follows (same directory, same `sgns::sgprocmanagerXXX` namespace shape). Recommend reading that pair only if the eventual implementer needs a second confirmation of house style; the two files above already fully establish the shape needed here.

**New logic to implement (D-03 through D-09), concretely, in order per CONTEXT.md — this is guidance for the planner/implementer, not an existing-code excerpt, since no real IEEE canonicalization exists elsewhere in this codebase to copy from:**

1. **`QuantizeFloatBuffer`** — for each element `x`:
   - First branch (D-07, explicit, before any rounding arithmetic): if `x` is denormal (subnormal, nonzero, exponent bits all 0), flush to signed-then-canonical zero.
   - If `std::isnan(x)`: overwrite with hardcoded bit pattern `0x7FC00000` (D-09) — use `memcpy`/`std::bit_cast`/union punning into the `float`, not `std::numeric_limits<float>::quiet_NaN()` (D-09 explicitly rejects the platform-native call).
   - If `std::isinf(x)`: overwrite with `0x7F800000` (+Inf) or `0xFF800000` (-Inf) depending on sign (D-06 — distinct patterns, never collapsed).
   - If `x == 0.0f` (including negative zero) or was just flushed from denormal: canonicalize to one bit pattern, e.g. `+0.0f`, sign discarded (D-08).
   - Otherwise: `q = std::round(x * S) / S` with `S = 2^20` (D-05), i.e. `constexpr float kScale = 1048576.0f;` (power-of-two, exact in float arithmetic per D-05).
2. **`QuantizeByteBuffer`** — D-01/D-10/D-11 scope this function only for the render/byte path; per Phase 11's empirical render capture (`contentHashMatch: true`, all deltas 0 on the sampled fixture), no evidence yet demands lossy byte-level tolerance-banding — confirm with CONTEXT.md D-05's phrasing ("QuantizeByteBuffer" is named but D-03-D-09 detail only covers the float path explicitly). If the implementer's own research/testing finds no real divergence requiring byte-level banding, an identity function here (explicitly documented as "confirmed unnecessary by Phase 11 data, not a stub") is consistent with the empirical findings — but this is a planning-time decision the phase's own PLAN.md must make explicit, not silently inherited from Phase 10.

---

### Call sites — verification only, no changes (D-per CONTEXT.md "signatures are final")

**`SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_float.cpp:307-360`** — confirmed two-layer call pattern (excerpt, lines 308-321 per-chunk layer):

```cpp
// Phase 10 CAPT-02: quantize-then-capture-then-hash at the per-chunk site.
// Never mutate MNN-owned `data` (const float*) in place -- copy first.
std::vector<float> localCopy( data, data + ( dataSize / sizeof( float ) ) );
sgprocmanagerquant::QuantizeFloatBuffer( localCopy.data(), localCopy.size() );
if ( execCtx.rawOutputCapture )
{
    const auto *quantizedBytes = reinterpret_cast<const uint8_t *>( localCopy.data() );
    const auto *preQuantizeBytes = reinterpret_cast<const uint8_t *>( data );
    execCtx.rawOutputCapture( std::vector<uint8_t>( quantizedBytes, quantizedBytes + dataSize ),
                               std::vector<uint8_t>( preQuantizeBytes, preQuantizeBytes + dataSize ) );
}

auto hash = sgprocmanagersha::sha256( localCopy.data(), dataSize );
chunkhashes.emplace_back( hash.begin(), hash.end() );
```

...and lines 341-360 (stitched/combined layer), same shape, calling `QuantizeFloatBuffer` on `stitchedOutput.data()` in place before `sgprocmanagersha::sha256(...)`. **No edits needed here** — the call shape and argument types are already correct for whatever the real `QuantizeFloatBuffer` body does; this phase changes only the function body at the declaration site.

**`SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp:2198-2214`** — single call site, confirmed correct as-is:

```cpp
std::vector<uint8_t> preQuantizeSnapshot;
if ( execCtx.rawOutputCapture )
{
    preQuantizeSnapshot = readbackBytes;
}
sgns::sgprocmanagerquant::QuantizeByteBuffer( readbackBytes.data(), readbackBytes.size() );
if ( execCtx.rawOutputCapture )
{
    execCtx.rawOutputCapture( readbackBytes, preQuantizeSnapshot );
}

ProcessingResult result;
result.hash = sgns::sgprocmanagersha::sha256( readbackBytes.data(), readbackBytes.size() );
```

Again, **no edits needed** — confirms D-01's scope: this phase's only code change is the two function bodies in `quantization.cpp`.

---

### New SECV-01 counter-test (test, request-response)

**Analog 1 (hash-assertion shape):** `SuperGenius/test/src/processing_conformance_hashing/output_hashing_test.cpp`

Key excerpt — `ContentHashChangesOnDifferentInput` (lines 72-126) is the direct template for SECV-01's "two runs must produce different hashes" shape (D-13's `ASSERT_NE` requirement):

```cpp
TEST_F( OutputHashingTest, ContentHashChangesOnDifferentInput )
{
    // ... Create() manager1 from json_str, manager2 from json_str2 (different input) ...
    auto pr1 = manager1->Process( ioc, chunkhashes1, model_node1, output_locations1 );
    ASSERT_TRUE( pr1.has_value() );
    auto pr2 = manager2->Process( ioc, chunkhashes2, model_node2, output_locations2 );
    ASSERT_TRUE( pr2.has_value() );

    // Different inputs should produce different combined hashes
    ASSERT_NE( pr1.value().combinedHash, pr2.value().combinedHash )
        << "Different inputs must produce different hashes";
}
```

**IMPORTANT deviation for SECV-01:** D-01 establishes the target hash is the **processor-level** `ProcessingResult.hash`/chunk hashes, NOT `ProcessOutput.combinedHash`/`ExecutionManifest.manifestHash`. This existing test asserts on `combinedHash` — SECV-01's new test must assert on the processor-level hash instead (e.g. `pr1.value().hash` / per-chunk `chunkhashes1` vs `chunkhashes2`, mirroring `ChunkHashesPresent`'s access pattern at lines 128-162 for how chunk hashes are read off `Process()`'s output param). Do not copy the `combinedHash` field access verbatim — that would test the wrong hash per this phase's own D-01/D-02 finding.

**Class/fixture skeleton** (`OutputHashingTest`, lines 11-21) — same `ProcessorConformanceFixture`-derived shape to reuse:
```cpp
namespace sgns
{
    class OutputHashingTest : public ProcessorConformanceFixture
    {
    protected:
        static void SetUpTestSuite()
        {
            binary_path = boost::dll::program_location().parent_path().string() + "/";
            data_path   = binary_path + "processing_datatypes/";
        }
    };
```
(Name the new fixture class e.g. `Secv01CounterTest` deriving from the same `ProcessorConformanceFixture` base, found at `SuperGenius/test/src/testutil/` — grep found no exact header path in this pass; locate it via the base-class usage above before writing the new test, since it supplies `PatchedJson(...)` used by both `output_hashing_test.cpp` and `cancellation_conformance_test.cpp`.)

**Analog 2 (Vulkan-skip + render JSON fixture, for D-11's render-path counter-test case):** `SuperGenius/test/src/processing_conformance_cancellation/cancellation_conformance_test.cpp`, `RenderCancelBeforeStartProducesNoSuccessfulResult` (lines 177-243):

```cpp
TEST_F( CancellationConformanceTest, RenderCancelBeforeStartProducesNoSuccessfulResult )
{
    if ( !sgns::sgprocessing::HasUsableVulkanDevice() )
    {
        GTEST_SKIP() << "No usable Vulkan device (DISCRETE_GPU/INTEGRATED_GPU) found on this "
                        "host; skipping this GPU-dependent test, not failing it.";
    }

    // Identical inline JSON literal to capability_conformance_test.cpp's
    // AcceptValidRenderJob (64x64 render target, shared passthrough.vert.spv/.frag.spv
    // fixtures) — reused here to exercise the same real Vulkan RenderProcessor path
    const std::string json_str = R"({
        "name": "cap-check-render",
        "version": "1.0.0",
        "gnus_spec_version": 1.0,
        "inputs": [ { "name": "vertexData", "source_uri_param": "file://processing_datatypes/float_input.bin", "type": "buffer", "dimensions": { "width": 1 } } ],
        "outputs": [ { "name": "renderTarget", "source_uri_param": "file://processing_datatypes/render_output.raw", "type": "image" } ],
        "passes": [ {
            "render_shader": {
                "stages": [
                    { "stage": "vertex", "type": "spirv", "source": "file://processing_conformance_regression/fixtures/passthrough.vert.spv", "entry_point": "main" },
                    { "stage": "fragment", "type": "spirv", "source": "file://processing_conformance_regression/fixtures/passthrough.frag.spv", "entry_point": "main" }
                ]
            },
            "render_target": { "color_format": "RGBA8", "depth_format": "D32_SFLOAT", "width": 64, "height": 64, "clear_color": [0.0, 0.0, 0.0, 1.0], "clear_depth": 1.0 },
            "vertex_buffer": { "source": "input:vertexData" },
            "vertex_layout": [ { "name": "inPosition", "format": "FLOAT32", "offset": 0 } ]
        } ]
    })";
    // ...
}
```

For D-11's render counter-test (wrong shader push-constant/uniform), reuse this same inline JSON shape but perturb the shader definition — since `passthrough.vert`/`passthrough.frag` source (`SuperGenius/test/src/processing_conformance_regression/fixtures/passthrough.vert`, `.frag`, plus their compiled `.spv`) already exist as plain-text GLSL alongside their `.spv`, the corrupted-shader fixture can be built by copying+perturbing the `.vert`/`.frag` source and recompiling to a new `.spv`, or by directly byte-perturbing a copy of the existing `.spv` (per Claude's discretion note in CONTEXT.md).

**`HasUsableVulkanDevice()` declaration** — `SuperGenius/SGProcessingManager/include/processors/vulkan_gpu_probe.hpp` (full file, 17 lines): confirms this is the single canonical probe function; `#include <processors/vulkan_gpu_probe.hpp>` and call `sgns::sgprocessing::HasUsableVulkanDevice()` exactly as `cancellation_conformance_test.cpp` and `capture_smoke_test.cpp` both do.

---

### New SECV-01 CTest registration (config)

**Analog:** `SuperGenius/test/src/processing_conformance_hashing/CMakeLists.txt` and `processing_conformance_cancellation/CMakeLists.txt` — both identical shape using the project's `addtest(...)` macro:

```cmake
addtest(processing_conformance_hashing_test
    output_hashing_test.cpp
)

target_include_directories(processing_conformance_hashing_test PRIVATE ${AsyncIOManager_INCLUDE_DIR})

target_link_libraries(processing_conformance_hashing_test
    nlohmann_json
    ProcessingBase
)
```

For the new SECV-01 suite (e.g. directory `SuperGenius/test/src/processing_conformance_security/`, target `processing_conformance_security_test`), copy this shape verbatim with the new source filename and target name. This registers as a real CTest target automatically (D-12) — no separate CLI-tool wiring like `SuperGenius/SGProcessingManager/test/capture/CMakeLists.txt`'s manual `add_executable`/`add_test(NAME ... COMMAND ...)` pattern is needed, since `addtest()` already handles CTest registration for conformance suites. Must also add `add_subdirectory(processing_conformance_security)` to the parent `SuperGenius/test/src/CMakeLists.txt` (not read in this pass — locate the existing `add_subdirectory(processing_conformance_hashing)` line there and add the new one alongside it).

---

## Shared Patterns

### Vulkan-device GTEST_SKIP guard (Phase 09 D-05)
**Source:** `SuperGenius/SGProcessingManager/include/processors/vulkan_gpu_probe.hpp` (declaration), used identically in `SuperGenius/test/src/processing_conformance_cancellation/cancellation_conformance_test.cpp:179-183` and `SuperGenius/SGProcessingManager/test/capture/capture_smoke_test.cpp:36-40`.
**Apply to:** SECV-01's render-path counter-test case (D-11) — mandatory per CONTEXT.md discretion note ("almost certainly yes").
```cpp
if ( !sgns::sgprocessing::HasUsableVulkanDevice() )
{
    GTEST_SKIP() << "No usable Vulkan device (DISCRETE_GPU/INTEGRATED_GPU) found on this "
                    "host; skipping this GPU-dependent test, not failing it.";
}
```

### `ProcessorConformanceFixture` + `PatchedJson(...)` test-fixture base
**Source:** used by `output_hashing_test.cpp`, `cancellation_conformance_test.cpp`, and others under `SuperGenius/test/src/processing_conformance_*`. Header path not resolved in this pass (grep matched only usage sites, not the declaring header) — locate via `grep -r "class ProcessorConformanceFixture"` under `SuperGenius/test/src/testutil/` before writing the new test file; it supplies `PatchedJson("some-fixture.json")` (loads + path-patches a fixture JSON file) and the `binary_path`/`data_path` static members shown in the `OutputHashingTest::SetUpTestSuite()` excerpt above.
**Apply to:** the new SECV-01 test's fixture class (MNN-corruption case in particular, which likely wants an on-disk model fixture the same way the hashing/cancellation tests use `buffer-processing-definition.json`/`float-processing-definition.json`).

### `addtest(...)` CMake macro for conformance suites
**Source:** every `processing_conformance_*/CMakeLists.txt` (hashing, cancellation, migration, schema, regression, executor, capability) uses this exact 3-part shape (`addtest(target file.cpp)`, `target_include_directories`, `target_link_libraries`).
**Apply to:** the new `processing_conformance_security/CMakeLists.txt`.

## No Analog Found

None — all files in this phase's scope have at least a role-match analog; the two implementation files (`quantization.hpp`/`.cpp`) are self-analogs (Phase 10's own stub, being replaced in place), and no other file in this codebase performs IEEE-754 canonicalization to copy an algorithm from — that logic must be written from CONTEXT.md's D-03 through D-09 spec directly (see "New logic to implement" above), not copied from an existing analog.

## Metadata

**Analog search scope:** `SuperGenius/SGProcessingManager/include/util/`, `SuperGenius/SGProcessingManager/src/util/`, `SuperGenius/SGProcessingManager/src/processors/`, `SuperGenius/SGProcessingManager/test/`, `SuperGenius/test/src/processing_conformance_*/`
**Files scanned:** quantization.hpp, quantization.cpp, processing_processor_mnn_float.cpp (partial, lines 290-370), processing_processor_render.cpp (partial, lines 2190-2226), vulkan_gpu_probe.hpp, cancellation_test.cpp (SGProcessingManager/test/execution), cancellation_conformance_test.cpp, output_hashing_test.cpp, capture_smoke_test.cpp (partial), 5x CMakeLists.txt
**Pattern extraction date:** 2026-08-12
