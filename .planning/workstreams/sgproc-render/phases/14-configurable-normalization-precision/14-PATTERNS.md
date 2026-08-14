# Phase 14: Configurable Normalization Precision - Pattern Map

**Mapped:** 2026-08-13
**Files analyzed:** 21 (2 core util + 14 processor files + 1 test-util + 1 fixture JSON + 2-3 new test files)
**Analogs found:** 21 / 21 (all files have a direct in-repo analog; this phase is pure extension of existing conventions)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `SuperGenius/SGProcessingManager/include/util/quantization.hpp` | utility (header) | transform | itself (existing file, extend in place) | exact |
| `SuperGenius/SGProcessingManager/src/util/quantization.cpp` | utility | transform | itself (existing file, extend in place) + `processing_processor_mnn_volume.cpp`'s `ParseLayout` (lookup-with-fallback) | exact |
| `SuperGenius/SGProcessingManager/test/util/quantization_test.cpp` | test | transform | itself (existing file, extend in place) | exact |
| `processing_processor_mnn_float.cpp` (2 call sites) | processor | CRUD/transform | itself; representative "vestigial `(void)parameters;`" case | exact |
| `processing_processor_mnn_buffer.cpp` (1 call site) | processor | transform | `mnn_float.cpp` | role-match |
| `processing_processor_mnn_bool.cpp` (1 call site) | processor | transform | `mnn_float.cpp` | role-match |
| `processing_processor_mnn_mat4.cpp` (2 call sites) | processor | transform | `mnn_tensor.cpp` (2-call-site shape) | exact |
| `processing_processor_mnn_mat3.cpp` (2 call sites) | processor | transform | `mnn_tensor.cpp` | exact |
| `processing_processor_mnn_mat2.cpp` (2 call sites) | processor | transform | `mnn_tensor.cpp` | exact |
| `processing_processor_mnn_int.cpp` (2 call sites) | processor | transform | `mnn_tensor.cpp` | exact |
| `processing_processor_mnn_image.cpp` (1 call site) | processor | transform | `mnn_float.cpp` | role-match |
| `processing_processor_mnn_texture1d.cpp` (1 call site; `parameters` already used via `ParseLayout`) | processor | transform | `mnn_volume.cpp` (`ParseLayout`-in-use case) | exact |
| `processing_processor_mnn_tensor.cpp` (2 call sites) | processor | transform | itself; representative 2-call-site case | exact |
| `processing_processor_mnn_texturecube.cpp` (2 call sites; `parameters` already used via `ParseLayout`) | processor | transform | `mnn_volume.cpp` | exact |
| `processing_processor_mnn_string.cpp` (1 call site; `parameters` already used for `maxLength`) | processor | transform | itself; representative "already-wired lookup, no vestigial `(void)parameters;`" case | exact |
| `processing_processor_mnn_volume.cpp` (1 call site; `parameters` already used via `ParseLayout`) | processor | transform | itself; representative "`ParseLayout`-in-use" case | exact |
| `processing_processor_render.cpp` (1 `QuantizeByteBuffer` call site; `parameters` already used via `ResolveUniforms`) | processor | transform | itself; the sole byte-path call site | exact |
| `SuperGenius/test/src/processing_datatypes/texture3d-processing-definition.json` | config (fixture) | file-I/O | itself (existing file, extend `parameters` array) | exact |
| `SuperGenius/test/src/processing_conformance_security/secv01_tex3d_counter_test.cpp` (new) | test | request-response | `secv01_counter_test.cpp` | exact |
| `SuperGenius/test/src/processing_conformance_security/fixtures/secv01-corrupted-spleen_ct_seg.mnn` (new) | config (binary fixture) | file-I/O | `fixtures/secv01-corrupted-float_model.mnn` (referenced by `secv01_counter_test.cpp`; not separately read, same technique per 12-02-PLAN.md) | exact |
| `SuperGenius/test/src/processing_conformance_security/CMakeLists.txt` | config (build) | file-I/O | itself (existing file, add one source line) | exact |

## Pattern Assignments

### `SuperGenius/SGProcessingManager/include/util/quantization.hpp` (utility, transform)

**Analog:** itself (current state, lines 1-95) — extend, don't replace.

**Current signatures to change** (lines 76, 92):
```cpp
void QuantizeFloatBuffer( float *data, size_t count );
...
void QuantizeByteBuffer( uint8_t *data, size_t count );
```
Becomes (per RESEARCH.md's recommended, required-parameter approach — A2 in Assumptions Log):
```cpp
#include <vector>
namespace sgns { class Parameter; }  // forward-declare, or #include "generated/Parameter.hpp" directly

namespace sgns::sgprocmanagerquant
{
    // D-04/D-05: falls back to 2^15 (32768.0f) on missing, non-numeric,
    // zero/negative, or non-power-of-two declared "quantScale".
    float ResolveQuantScale( const std::vector<sgns::Parameter> *parameters );

    // D-07/D-08: falls back to 0 (identity, matches v2.1) on missing,
    // negative, N>8, or non-numeric declared "byteQuantMode".
    int ResolveByteQuantMode( const std::vector<sgns::Parameter> *parameters );

    void QuantizeFloatBuffer( float *data, size_t count, float scale );
    void QuantizeByteBuffer( uint8_t *data, size_t count, int maskBits );
}
```
Note: `#include "generated/Parameter.hpp"` is a **new** dependency for this pair of files only — currently `quantization.hpp`/`.cpp` include nothing but `<cstddef>`/`<cstdint>`/`<cmath>`/`<cstring>` (see full header above). This is Assumption A1 (centralize resolvers here rather than duplicate per-processor-file).

---

### `SuperGenius/SGProcessingManager/src/util/quantization.cpp` (utility, transform)

**Analog:** itself + `ParseLayout` lookup convention.

**Current hardcoded branch to parameterize** (lines 37, 90-94):
```cpp
constexpr float kScale = 32768.0f; // 2^15
...
else
{
    data[i] = std::round( x * kScale ) / kScale;
}
```
Becomes: replace `kScale` with the function's new `scale` parameter; the entire canonicalization branch order (denormal/NaN/Inf/zero, lines 43-89) is **unchanged**, only the final `else` arm's constant becomes the parameter.

**Current byte-path no-op to parameterize** (lines 98-107):
```cpp
void QuantizeByteBuffer( uint8_t *data, size_t count )
{
    (void)data;
    (void)count;
}
```
Becomes (D-06/D-07):
```cpp
void QuantizeByteBuffer( uint8_t *data, size_t count, int maskBits )
{
    if ( maskBits <= 0 ) { return; } // N=0/absent: exact v2.1 identity no-op
    const uint8_t mask = static_cast<uint8_t>( ~( ( 1u << maskBits ) - 1u ) );
    for ( size_t i = 0; i < count; ++i )
    {
        data[i] &= mask;
    }
}
```

**Lookup-with-fallback pattern to replicate exactly** (`processing_processor_mnn_volume.cpp:40-71`, `ParseLayout`):
```cpp
// Source: SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_volume.cpp:40-71
VolumeLayout ParseLayout( const std::vector<sgns::Parameter> *parameters, const std::string &inputName )
{
    const std::vector<std::string> keys = {
        inputName + "Layout", inputName + "_layout", "volumeLayout", "layout"
    };
    if ( parameters )
    {
        for ( const auto &key : keys )
        {
            auto it = std::find_if( parameters->begin(), parameters->end(),
                                     [&key]( const sgns::Parameter &param ) { return param.get_name() == key; } );
            if ( it != parameters->end() && it->get_parameter_default().is_string() )
            {
                const std::string layout = ToUpperAscii( it->get_parameter_default().get<std::string>() );
                if ( layout == "HWD" ) return VolumeLayout::HWD;
                // ... other enum values ...
            }
        }
    }
    return VolumeLayout::HWD; // silent fallback
}
```
`quantScale`/`byteQuantMode` use a **single fixed key name** (D-02), so no multi-key `keys` vector is needed — closer to `mnn_string.cpp`'s single-key style below.

**Type-checked lookup pattern to replicate exactly** (`processing_processor_mnn_string.cpp:74-89`, `maxLength`):
```cpp
// Source: SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_string.cpp:76-90
int maxLength = 128;
if ( parameters )
{
    for ( const auto &param : *parameters )
    {
        if ( param.get_name() == "maxLength" && param.get_type() == sgns::ParameterType::INT )
        {
            const auto &def = param.get_parameter_default();
            if ( def.is_number_integer() && def.get<int>() > 0 )
            {
                maxLength = def.get<int>();
            }
            break;
        }
    }
}
```
Direct template for `ResolveByteQuantMode` (checking `ParameterType::INT`, `def.is_number_integer()`, range `0 <= N <= 8`) and for `ResolveQuantScale`'s lookup half (checking `ParameterType::FLOAT`, `def.is_number()`, `def.get<float>()`) before applying the D-05 power-of-two check below.

**Power-of-two validation (new, no direct precedent — recommended implementation from RESEARCH.md):**
```cpp
bool IsPositivePowerOfTwo( double value )
{
    if ( !( value > 0.0 ) ) { return false; }
    if ( std::floor( value ) != value ) { return false; }
    const auto asInt = static_cast<uint64_t>( value );
    return asInt != 0 && ( asInt & ( asInt - 1u ) ) == 0u;
}
```
`ParameterType` enum values available (`generated/ParameterType.hpp:19`): `ARRAY, BOOL, FLOAT, INT, OBJECT, STRING, URI`.

---

### `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_float.cpp` (processor, transform) — representative "vestigial no-op" case, 2 call sites

**Analog:** itself.

**Current `StartProcessing` signature + no-op** (lines 168-175):
```cpp
ProcessingResult MNN_Float::StartProcessing( std::vector<std::vector<uint8_t>> &chunkhashes,
                                              const sgns::IoDeclaration         &proc,
                                              std::vector<char>                 &tensorData,
                                              std::vector<char>                 &modelFile,
                                              const std::vector<sgns::Parameter> *parameters,
                                              const ExecutionContext            &execCtx )
{
    (void)parameters;
```
**Current call sites** (lines 311, 349):
```cpp
sgprocmanagerquant::QuantizeFloatBuffer( localCopy.data(), localCopy.size() );      // per-chunk loop
...
sgprocmanagerquant::QuantizeFloatBuffer( stitchedOutput.data(), stitchedOutput.size() ); // stitched-output
```
**Pattern to apply:** delete `(void)parameters;`; add once near the top of `StartProcessing` (after signature, before the per-chunk loop):
```cpp
const float scale = sgprocmanagerquant::ResolveQuantScale( parameters );
```
then pass `scale` as the new third argument at both call sites:
```cpp
sgprocmanagerquant::QuantizeFloatBuffer( localCopy.data(), localCopy.size(), scale );
sgprocmanagerquant::QuantizeFloatBuffer( stitchedOutput.data(), stitchedOutput.size(), scale );
```
This exact recipe (delete `(void)parameters;`, resolve once, pass through unchanged at every call site) applies verbatim to `mnn_buffer.cpp` (1 site), `mnn_bool.cpp` (1 site), `mnn_image.cpp` (1 site) — all currently `(void)parameters;`-no-op with a single call site, same shape as `mnn_float.cpp` minus the second call.

---

### `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_tensor.cpp` (processor, transform) — representative 2-call-site case

**Analog:** itself; template for `mnn_mat4.cpp`/`mnn_mat3.cpp`/`mnn_mat2.cpp`/`mnn_int.cpp` (each also has exactly 2 call sites: per-chunk loop + stitched-output).

**Current signature + no-op** (lines 186-193):
```cpp
ProcessingResult MNN_Tensor::StartProcessing( std::vector<std::vector<uint8_t>> &chunkhashes,
                                              const sgns::IoDeclaration         &proc,
                                              std::vector<char>                 &tensorData,
                                              std::vector<char>                 &modelFile,
                                              const std::vector<sgns::Parameter> *parameters,
                                              const ExecutionContext            &execCtx )
{
    (void)parameters;
```
**Current call sites** (lines 362, 400):
```cpp
sgprocmanagerquant::QuantizeFloatBuffer( localCopy.data(), localCopy.size() );
...
sgprocmanagerquant::QuantizeFloatBuffer( stitchedOutput.data(), stitchedOutput.size() );
```
**Pattern to apply:** identical to `mnn_float.cpp` above — resolve `scale` once via `ResolveQuantScale( parameters )` immediately after deleting `(void)parameters;`, then thread it through both existing calls unchanged otherwise.

---

### `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_volume.cpp` (processor, transform) — representative "`parameters` already used via `ParseLayout`" case

**Analog:** itself; template for `mnn_texture1d.cpp`/`mnn_texturecube.cpp` (same "already consumes `parameters` via a local `ParseLayout`, but still has the vestigial `(void)parameters;` line" shape).

**Current state** (lines 209-216, 261, 521):
```cpp
ProcessingResult MNN_Volume::StartProcessing( std::vector<std::vector<uint8_t>> &chunkhashes,
                                              const sgns::IoDeclaration         &proc,
                                              std::vector<char>                 &tensorData,
                                              std::vector<char>                 &modelFile,
                                              const std::vector<sgns::Parameter> *parameters,
                                              const ExecutionContext            &execCtx )
{
    (void)parameters;
    ...
    const VolumeLayout layout = ParseLayout( parameters, proc.get_name() );   // line 261: parameters ALREADY used
    ...
    sgprocmanagerquant::QuantizeFloatBuffer( localCopy.data(), localCopy.size() );  // line 521: the one call site
```
**Pattern to apply:** delete the vestigial `(void)parameters;` (now genuinely redundant since `ParseLayout` already consumes `parameters` two lines later); add `const float scale = sgprocmanagerquant::ResolveQuantScale( parameters );` alongside/near the existing `ParseLayout` call; pass `scale` into the one `QuantizeFloatBuffer` call at line 521. `#include "util/quantization.hpp"` is already present (line 15) — no new include needed in this file.

---

### `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp` (processor, transform) — the sole byte-path call site

**Analog:** itself; `ResolveUniforms` (lines 818-873) is the direct precedent for parameter-lookup-by-name in this file.

**`ResolveUniforms`'s existing lookup-by-name pattern** (lines 854-865):
```cpp
const sgns::Parameter *found = nullptr;
if ( parameters )
{
    for ( const auto &param : *parameters )
    {
        if ( param.get_name() == paramName )
        {
            found = &param;
            break;
        }
    }
}
if ( !found ) { /* error/fallback path */ }
resolvedValue = found->get_parameter_default();
```
**Current byte-path call site** (line 2207, inside `StartProcessing` which already receives `parameters` per line 2090's `ResolveUniforms( uniformsMap, parameters, resolvedUniforms, errorOut )` call):
```cpp
sgns::sgprocmanagerquant::QuantizeByteBuffer( readbackBytes.data(), readbackBytes.size() );
```
**Pattern to apply:** resolve once (e.g. right after or alongside the existing `ResolveUniforms` call around line 2090):
```cpp
const int maskBits = sgns::sgprocmanagerquant::ResolveByteQuantMode( parameters );
```
then at line 2207:
```cpp
sgns::sgprocmanagerquant::QuantizeByteBuffer( readbackBytes.data(), readbackBytes.size(), maskBits );
```
No `(void)parameters;` exists in this file to delete — `parameters` is already actively consumed by `ResolveUniforms`.

---

### `SuperGenius/SGProcessingManager/test/util/quantization_test.cpp` (test, transform)

**Analog:** itself — extend, don't create a new file (per CONTEXT.md canonical refs).

**Existing structure** (lines 1-38):
```cpp
#include <gtest/gtest.h>
#include <cstdint>
#include <cstring>
#include <cmath>
#include "util/quantization.hpp"

namespace sgns::sgprocmanagerquant
{
    namespace
    {
        uint32_t BitsOf( float value ) { ... }
        float FloatFromBits( uint32_t bits ) { ... }
    }
    class QuantizationTest : public ::testing::Test { };

    TEST_F( QuantizationTest, QuantizeFloatBufferCanonicalizesNaN )
    {
        float data1[1] = { FloatFromBits( 0x7FC00123u ) };
        QuantizeFloatBuffer( data1, 1 );          // <-- 2-arg call, needs updating to 3-arg
        ASSERT_EQ( BitsOf( data1[0] ), 0x7FC00000u );
        ...
    }
```
**Impact:** every existing `TEST_F` in this file calls the current 2-arg `QuantizeFloatBuffer(data, count)` / 2-arg `QuantizeByteBuffer(data, count)` — all such calls must be updated to pass an explicit `scale`/`maskBits` (e.g. `32768.0f`/`0` to preserve existing test intent) since the new parameter is required, not defaulted (RESEARCH.md Anti-Patterns). New `TEST_F` cases should be added for: `ResolveQuantScale` fallback on missing/non-numeric/zero/negative/non-power-of-two `quantScale` (D-04/D-05), `ResolveByteQuantMode` fallback on negative/`N>8`/non-numeric `byteQuantMode` (D-08), and the `N=8` valid vs `N=9` invalid boundary case flagged in RESEARCH.md's Security Domain section.

---

### `SuperGenius/test/src/processing_conformance_security/secv01_tex3d_counter_test.cpp` (new test) (test, request-response)

**Analog:** `SuperGenius/test/src/processing_conformance_security/secv01_counter_test.cpp` (full existing file — copy structure verbatim per D-09).

**Fixture base class + includes** (lines 1-32):
```cpp
#include <gtest/gtest.h>
#include <cstring>
#include <iostream>
#include <memory>
#include <artifacts/artifact_types.hpp>
#include <processingbase/ProcessingManager.hpp>
#include <processors/vulkan_gpu_probe.hpp>
#include "testutil/processing_conformance_fixture.hpp"

namespace sgns
{
    class Secv01CounterTest : public ProcessorConformanceFixture
    {
    };

    TEST_F( Secv01CounterTest, MnnCorruptedModelStillDiverges )
    {
        const std::string correctJson = R"({ ... two full inline job JSON literals, correct vs corrupted model URI ... })";
```
**Assertion pattern to replicate exactly** (lines 355-361, confirmed via RESEARCH.md's excerpt):
```cpp
EXPECT_NE( std::memcmp( prCorrect.value().artifacts[0].artifactId,
                         prCorrupted.value().artifacts[0].artifactId,
                         sgns::sgprocessing::SHA256_HASH_SIZE ),
           0 )
    << "A deliberately corrupted MNN model must produce a different "
       "post-quantization artifactId than the correct model -- SECV-01/T-12-06";
```
**Pitfall to avoid (Pitfall 3, RESEARCH.md):** use `.value().artifacts[0].artifactId` + `std::memcmp`, never `processing_datatypes_test.cpp`'s older `.value().size()`/`.empty()` convention.

**New class name suggestion:** `Secv01Tex3dCounterTest` (mirrors `Secv01CounterTest`), single `TEST_F` e.g. `MnnCorruptedSpleenCtSegModelStillDiverges`, using two inline JSON job definitions shaped like `texture3d-processing-definition.json` (see below) differing only in `model.source_uri_param` (correct `spleen_ct_seg.mnn` vs corrupted copy) and each declaring the new `quantScale` parameter at the tex3d-derived value from D-10's binary search.

---

### `SuperGenius/test/src/processing_datatypes/texture3d-processing-definition.json` (config fixture, file-I/O)

**Analog:** itself — extend `parameters` array in place.

**Current `parameters` array** (lines 39-46):
```json
"parameters": [
  {
    "name": "modelUri",
    "type": "uri",
    "default": "file://processing_datatypes/spleen_ct_seg.mnn",
    "description": "URI to the spleen CT segmentation model"
  }
],
```
**Pattern to apply (D-10, final numeric value from empirical binary search):**
```json
"parameters": [
  {
    "name": "modelUri",
    "type": "uri",
    "default": "file://processing_datatypes/spleen_ct_seg.mnn",
    "description": "URI to the spleen CT segmentation model"
  },
  {
    "name": "quantScale",
    "type": "float",
    "default": 128.0,
    "description": "Empirically-derived coarser quantization scale for tex3d/spleen_ct_seg's larger cross-hardware divergence (Phase 14 QUANT-CFG-03/D-10)"
  }
],
```
(`128.0` = `2^7`, STATE.md's low estimate — placeholder; the exact power-of-two must come from D-10's binary search against the new `secv01_tex3d_counter_test.cpp`, not assumed here.) Uses `"type": "float"` per `gnus-processing-schema.json:123-152`'s existing generic parameter type enum — no schema changes needed (D-01).

---

### `SuperGenius/test/src/processing_conformance_security/CMakeLists.txt` (config/build, file-I/O)

**Analog:** itself — one-line addition per RESEARCH.md's Open Question #2 recommendation.

**Current full file:**
```cmake
addtest(processing_conformance_security_test
    secv01_counter_test.cpp
)

target_include_directories(processing_conformance_security_test PRIVATE ${AsyncIOManager_INCLUDE_DIR})

target_link_libraries(processing_conformance_security_test
    nlohmann_json
    ProcessingBase
)

add_custom_command(TARGET processing_conformance_security_test POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
    "${CMAKE_CURRENT_SOURCE_DIR}/fixtures/"
    "$<TARGET_FILE_DIR:processing_conformance_security_test>/processing_conformance_security/fixtures/"
)
```
**Pattern to apply:** add `secv01_tex3d_counter_test.cpp` as a second source in the existing `addtest(...)` call (RESEARCH.md's recommendation — reuses the existing `POST_BUILD` fixture-copy step, which already generalizes to any file placed under `fixtures/`, including the new `secv01-corrupted-spleen_ct_seg.mnn`):
```cmake
addtest(processing_conformance_security_test
    secv01_counter_test.cpp
    secv01_tex3d_counter_test.cpp
)
```
No other lines need to change — the `POST_BUILD` `copy_directory` already covers any new file dropped into `fixtures/`.

## Shared Patterns

### Find-by-name-in-`parameters` lookup with silent fallback (D-01/D-02)
**Source:** `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_volume.cpp:40-71` (`ParseLayout`, multi-key) and `processing_processor_mnn_string.cpp:76-90` (`maxLength`, single-key, type-checked — closer template since `quantScale`/`byteQuantMode` are fixed single names per D-02)
**Apply to:** the two new `ResolveQuantScale`/`ResolveByteQuantMode` functions in `quantization.cpp` (centralized, not duplicated per D-01/A1)
```cpp
if ( param.get_name() == "quantScale" && param.get_type() == sgns::ParameterType::FLOAT )
{
    const auto &def = param.get_parameter_default();
    if ( def.is_number() ) { /* validate power-of-two, else fall back per D-04/D-05 */ }
}
```

### Power-of-two validation (D-05, new — no prior precedent)
**Source:** RESEARCH.md "Architecture Patterns" Pattern 2 (recommended, not yet in codebase)
```cpp
bool IsPositivePowerOfTwo( double value )
{
    if ( !( value > 0.0 ) ) { return false; }
    if ( std::floor( value ) != value ) { return false; }
    const auto asInt = static_cast<uint64_t>( value );
    return asInt != 0 && ( asInt & ( asInt - 1u ) ) == 0u;
}
```
**Apply to:** `ResolveQuantScale` only (D-05); use the integer bit-trick, never `log2`/`pow` (Pitfall 2 — floating-point imprecision near powers of two is platform-dependent, exactly the nondeterminism this milestone exists to eliminate).

### Required (non-defaulted) function parameter, not an overload (A2)
**Source:** RESEARCH.md "Anti-Patterns to Avoid"
**Apply to:** `QuantizeFloatBuffer`/`QuantizeByteBuffer`'s new `scale`/`maskBits` parameters — every one of the 21 call sites must be touched; a missed site fails to compile rather than silently keeping stale behavior (Pitfall 1).

### Quantize-then-hash ordering (Phase 8/10, unaffected)
**Source:** every processor's `StartProcessing` — quantize happens before the per-chunk/stitched-output SHA-256 hash call; this phase changes only the value fed into the existing `Quantize*` calls, never the surrounding ordering.

### `secv01_counter_test.cpp`'s artifact-level assertion convention (D-09/D-13)
**Source:** `SuperGenius/test/src/processing_conformance_security/secv01_counter_test.cpp:188-193` (per RESEARCH.md excerpt)
**Apply to:** the new `secv01_tex3d_counter_test.cpp` — `.value().artifacts[0].artifactId` + `std::memcmp(..., SHA256_HASH_SIZE)`, never `.value().size()`/`.empty()` (Pitfall 3).

## No Analog Found

None — every file this phase touches either already exists (modify-in-place) or has a directly-analogous sibling file already read above (new `secv01_tex3d_counter_test.cpp` mirrors `secv01_counter_test.cpp`; new `secv01-corrupted-spleen_ct_seg.mnn` mirrors the existing `secv01-corrupted-float_model.mnn` creation technique per 12-02-PLAN.md, referenced but not independently re-read since it is a binary fixture, not source).

## Metadata

**Analog search scope:** `SuperGenius/SGProcessingManager/{include,src}/util/`, `SuperGenius/SGProcessingManager/src/processors/`, `SuperGenius/SGProcessingManager/test/util/`, `SuperGenius/test/src/processing_conformance_security/`, `SuperGenius/test/src/processing_datatypes/`
**Files scanned:** 2 core util files (full read), 4 representative processor files (`mnn_tensor.cpp`, `mnn_volume.cpp`, `mnn_float.cpp`, `mnn_string.cpp` — targeted reads) + 1 render file (targeted reads at `ResolveUniforms` and the `QuantizeByteBuffer` call site), 1 existing security counter-test (partial read), 1 existing quantization unit test (partial read), 1 fixture JSON (full read), 1 CMakeLists.txt (full read), 1 generated enum header (grep)
**Pattern extraction date:** 2026-08-13
