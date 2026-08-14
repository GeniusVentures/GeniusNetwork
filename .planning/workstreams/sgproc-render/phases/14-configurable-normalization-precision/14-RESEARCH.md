# Phase 14: Configurable Normalization Precision - Research

**Researched:** 2026-08-13
**Domain:** C++ schema-driven configuration threading into an existing quantization utility (SuperGenius/SGProcessingManager), plus a new corrupted-model security counter-test
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Reuse the existing generic `parameters` array — no changes to `gnus-processing-schema.json` or the quicktype-generated headers. Mirrors the exact find-by-name-in-`parameters` convention `processing_processor_mnn_volume.cpp`'s `ParseLayout` already uses for `layout`/`volumeLayout`. Rejected: adding a new formal schema field, since it would require a quicktype regen across every consumer and REQUIREMENTS.md doesn't ask for a schema redesign.
- **D-02:** Parameter key names are `quantScale` (float32 path) and `byteQuantMode` (uint8 path) — distinct, type-specific names, not one shared key.
- **D-03:** `quantScale` declares the raw scale `S` directly (not a grid-step/epsilon the code converts). Same `round(x * S) / S` formula Phase 12/13 already established — only `S` becomes a schema-declarable variable instead of a compile-time constant; the technique itself is not reopened.
- **D-04:** Any invalid declared `quantScale` (non-numeric, zero/negative, or not a power-of-two) silently falls back to v2.1's `S=2^15` constant — no warning logged, no job rejection. Same silent-fallback spirit as `ParseLayout`'s handling of an unrecognized value.
- **D-05:** "Must be a power-of-two" is an enforced code check, not just documented guidance — the config-resolution path validates the declared `S` is a positive power-of-two before using it; anything else triggers the same D-04 fallback. Guarantees the exact float round-trip property Phase 12's D-03 relies on can never be silently violated by a bad schema value.
- **D-06:** `byteQuantMode` uses bit-masking of the low N bits (`value &= ~((1<<N)-1)`), not a scale-round-cast analog of the float path. No existing byte-divergence fixture data justifies porting the float technique verbatim; bit-masking is the cheaper, more directly analogous "coarsen the grid" operation for an integer byte value.
- **D-07:** `byteQuantMode`'s declared value literally is `N` (number of low bits to mask). `N=0` or absent is exactly today's byte-identity no-op — satisfies QUANT-CFG-02's additive requirement by construction, no separate on/off flag needed.
- **D-08:** Invalid `byteQuantMode` (negative, `N>8`, non-numeric) falls back to `N=0` (byte-identity) — same silent-fallback pattern as D-04/D-05.
- **D-09:** Phase 14 adds a **new** SECV-01-style corrupted-model counter-test specifically for tex3d/spleen_ct_seg's own (much coarser) precision. The existing `secv01_counter_test.cpp` only exercises the small MNN float fixture at `S=2^15` — it does not prove a substantially coarser grid (~`S=2^7`-`2^8`) still catches a genuinely corrupted result. This goes beyond REQUIREMENTS.md's literal QUANT-CFG-01/02/03 wording, but stays within this phase's own tex3d-precision deliverable — not scope creep into unrelated work.
- **D-10:** tex3d's actual `quantScale` value is derived via the same binary-search-against-a-counter-test methodology Phase 12/13 already used for the small model (`13-04-PLAN.md`'s process): start from the STATE.md estimate (~`S=2^7`-`2^8`), binary-search power-of-two `S` values against the new D-09 counter-test, and pick the widest `S` that still passes with one power-of-two step of margin above the first confirmed failure boundary — identical discipline to how `S=2^15` was chosen for the small model.

### Claude's Discretion

- Exact mechanism for threading the resolved `S`/`N` value into `QuantizeFloatBuffer`/`QuantizeByteBuffer` (new function parameter, overload, or a small resolver invoked at each of the ~20 existing call sites before the unchanged function call) — left to research/planning. **This research's recommendation:** a required (non-defaulted) new function parameter, resolved via new `ResolveQuantScale`/`ResolveByteQuantMode` helpers centralized in `quantization.hpp`/`.cpp`. See "Architecture Patterns" and "Assumptions Log" A1/A2.
- Exact file/test names for the new tex3d SECV counter-test — follow whatever convention `secv01_counter_test.cpp` already established. **This research's recommendation:** `secv01_tex3d_counter_test.cpp`, added as a second source in the existing `processing_conformance_security_test` CMake target. See "Open Questions" #2.

### Deferred Ideas (OUT OF SCOPE)

- **Relative/ULP-based (mantissa-bit-masking) quantization technique for the float path** — still not chosen; Phase 12's own deferred item stands unchanged. This phase makes the existing absolute-epsilon technique's `S` configurable, it does not reopen the technique choice itself.
- **Scale-round-cast analog for the byte path** — considered during discussion, not chosen (D-06 picked bit-masking instead). Could be revisited if a future byte fixture's real divergence data shows bit-masking doesn't generalize.
- **New formal schema field / quicktype schema changes for precision declaration** — considered, not chosen (D-01 reuses the generic `parameters` array instead).
- **Modifying `ComputeManifestHash`/`ExecutionManifest` for a cross-machine-comparable manifest-level hash** — reaffirmed out of scope again (recurring deferred item from Phase 12/13), unrelated to this phase's precision work.
- **Actual cross-node consensus/redundant-execution plumbing (XNODE-01c)** — explicitly out of scope per REQUIREMENTS.md, unrelated to this phase.
- **`ProcessingValidationCore::ValidateResults`, the concatenation bug, or any numeric-tolerance comparison mechanism** — Phase 15's scope (XNODE-01b, XNODE-02, SECV-02), not this phase's.

</user_constraints>

## Summary

This phase is pure in-repo C++ engineering with no new external dependencies: it makes the already-hardcoded `S=2^15` float scale and byte-identity no-op in `SuperGenius/SGProcessingManager/src/util/quantization.cpp` schema-configurable, using the exact same find-by-name-in-`parameters` pattern the codebase already established in `ParseLayout` (`processing_processor_mnn_volume.cpp`/`_texture1d.cpp`/`_texturecube.cpp`) and `ResolveUniforms` (`processing_processor_render.cpp`). All 21 existing call sites (across 14 processor files — CONTEXT.md's "~20" is confirmed exact) already receive `parameters` as a `StartProcessing` function parameter; 13 of the 14 files currently `(void)parameters;`-no-op it (a vestigial unused-parameter silencer, since 3 of those 13 — `mnn_volume.cpp`, `mnn_texture1d.cpp`, `mnn_texturecube.cpp` — actually already use `parameters` later in the same function via `ParseLayout`, despite the leftover `(void)parameters;` line). `mnn_string.cpp` is the only file with no `(void)parameters;` at all — it already reads a `maxLength` parameter directly inline. This means every call site's enclosing function has `parameters` in scope for the resolver call with zero signature changes needed at the `StartProcessing` level.

The concrete engineering decision left to planning is how `QuantizeFloatBuffer`/`QuantizeByteBuffer`'s signatures change to accept a resolved value. Recommended: add a required (non-defaulted) `float scale` / `int maskBits` parameter to each function, resolved once per `StartProcessing` call via two new free-function helpers (`ResolveQuantScale`/`ResolveByteQuantMode`) added to `quantization.hpp`/`quantization.cpp` themselves (not duplicated per-file), since centralizing avoids replicating the same ~15-line find-by-name/validate/fallback logic 14 times and keeps the D-04/D-05/D-08 fallback rules defined in exactly one place. This is the one area this research recommends prescriptively but leaves final call to planning, per CONTEXT.md's explicit discretion grant.

**Primary recommendation:** Add `ResolveQuantScale(const std::vector<sgns::Parameter>*)` / `ResolveByteQuantMode(const std::vector<sgns::Parameter>*)` free functions to `quantization.hpp`/`.cpp` (new dependency: `#include "generated/Parameter.hpp"` in that pair only); change `QuantizeFloatBuffer`/`QuantizeByteBuffer` to take the resolved value as a new required parameter; update all 21 call sites to call the resolver once per `StartProcessing` invocation (replacing the vestigial `(void)parameters;` line where present) and pass the result through unchanged otherwise.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Schema `parameters` declaration/parsing | API/Backend (job schema layer, quicktype-generated `Parameter`/`ParameterType`) | — | Already-existing generic schema mechanism (D-01); no new tier touched |
| Quantization scale/mode resolution (`quantScale`/`byteQuantMode` lookup + fallback) | API/Backend (`SGProcessingManager` util layer) | — | Pure in-process C++ logic, no I/O, no network boundary |
| Quantize-then-hash at chunk/stitched-output boundary | API/Backend (processor layer, `processing_processor_*.cpp`) | — | Unchanged Phase 10/12 architecture; only the value fed into the existing call changes |
| tex3d/spleen_ct_seg counter-test (new SECV-01-style test) | API/Backend (test binary, `processing_conformance_security_test`) | — | Local GTest executable, no runtime service boundary |
| `texture3d-processing-definition.json` fixture edit | Database/Storage (static test fixture file) | — | On-disk JSON fixture, not a runtime service |

This phase has no browser/client, SSR, or CDN tier — it is exclusively backend/library C++ code and its test fixtures.

## Standard Stack

### Core

No new libraries. This phase extends existing in-repo code only:

| Component | Location | Purpose | Why Standard (already in use) |
|-----------|----------|---------|-------------------------------|
| `sgns::sgprocmanagerquant::QuantizeFloatBuffer`/`QuantizeByteBuffer` | `SuperGenius/SGProcessingManager/{include,src}/util/quantization.{hpp,cpp}` | The functions this phase makes configurable | Established Phase 12/13 |
| `sgns::Parameter`/`sgns::ParameterType` | `SuperGenius/SGProcessingManager/generated/Parameter.hpp`, `ParameterType.hpp` | Quicktype-generated schema parameter accessor | Already used by `ParseLayout`, `ResolveUniforms`, `mnn_string.cpp`'s `maxLength` lookup |
| `nlohmann::json` | via `Parameter::get_parameter_default()` | Untyped default-value carrier for a declared parameter | Already the project-wide JSON library (quicktype target) |
| GTest (`ProcessorConformanceFixture`) | `SuperGenius/test/testutil/processing_conformance_fixture.hpp` | Base fixture for the new tex3d counter-test | Already used by `secv01_counter_test.cpp`, `processing_datatypes_test.cpp` |

### Supporting

None — no supporting libraries are introduced.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Reusing generic `parameters` array (D-01, locked) | New formal schema field | Rejected in CONTEXT.md D-01 — would need quicktype regen across every consumer; not revisited here |
| Bit-masking for byte path (D-06, locked) | Scale-round-cast analog | Rejected in CONTEXT.md D-06 — not revisited here |

**Installation:** None — no new packages for any ecosystem. This phase modifies existing C++ source under `SuperGenius/SGProcessingManager/` and `SuperGenius/test/`, rebuilt via the project's existing CMake targets (`sgprocmanagerquant`, `quantization_test`, `processing_conformance_security_test`).

## Package Legitimacy Audit

**Not applicable.** This phase installs zero external packages in any ecosystem (npm/pip/cargo). All work is in-repo C++ source modification, existing CMake targets, and a new test file wired into an already-existing `CMakeLists.txt` (`processing_conformance_security/CMakeLists.txt`, which already lists `secv01_counter_test.cpp` as its one source — the new tex3d counter-test either gets added as a second source in that same target, or its own new sibling `CMakeLists.txt`/target, per planning's naming discretion). No package-manager legitimacy gate applies.

## Architecture Patterns

### System Architecture Diagram

```
Job schema (JSON, on disk or inline string)
        │
        │  parsed via quicktype-generated
        │  ProcessingData/Pass/Parameter classes
        ▼
ProcessingManager::Create()
        │
        │  parameters: const std::vector<sgns::Parameter>*
        ▼
Processor::StartProcessing(chunkhashes, proc, data, modelFile, parameters, execCtx)
        │
        │  [NEW] resolve once per call:
        │    scale     = ResolveQuantScale(parameters)      -- float, D-04/D-05 fallback to 2^15
        │    maskBits  = ResolveByteQuantMode(parameters)   -- int,   D-08 fallback to 0
        ▼
   ... existing per-chunk / stitched-output loop (UNCHANGED) ...
        │
        ├─► QuantizeFloatBuffer(localCopy.data(), localCopy.size(), scale)     [21 float call sites, 13 files]
        │        │
        │        │ canonicalize NaN/Inf/denormal/signed-zero (UNCHANGED, D-06..D-09)
        │        ▼
        │   round(x * scale) / scale   (D-03, now variable `scale` not `kScale`)
        │
        └─► QuantizeByteBuffer(readbackBytes.data(), readbackBytes.size(), maskBits)  [1 byte call site, render.cpp]
                 │
                 ▼
            value &= ~((1 << maskBits) - 1)   (D-06/D-07, maskBits=0 is exact v2.1 no-op)
        │
        ▼
sha256(quantized bytes) → chunkhashes / artifactId   (UNCHANGED, Phase 8/10 architecture)
```

### Recommended Project Structure

No new directories. Files touched/added:

```
SuperGenius/SGProcessingManager/
├── include/util/quantization.hpp        # MODIFY: add ResolveQuantScale/ResolveByteQuantMode decls, new required params
├── src/util/quantization.cpp            # MODIFY: implement resolvers, add param to both Quantize* functions
├── test/util/quantization_test.cpp      # MODIFY: extend with new fallback/config-path TEST_F cases
├── gnus-processing-schema.json          # NO CHANGE (D-01) -- generic parameters/parameter schema already sufficient
└── src/processors/
    ├── processing_processor_mnn_float.cpp        # MODIFY: resolve + pass scale (2 call sites)
    ├── processing_processor_mnn_buffer.cpp       # MODIFY: resolve + pass scale (1 call site)
    ├── processing_processor_mnn_bool.cpp         # MODIFY: resolve + pass scale (1 call site)
    ├── processing_processor_mnn_mat4.cpp         # MODIFY: resolve + pass scale (2 call sites)
    ├── processing_processor_mnn_mat3.cpp         # MODIFY: resolve + pass scale (2 call sites)
    ├── processing_processor_mnn_mat2.cpp         # MODIFY: resolve + pass scale (2 call sites)
    ├── processing_processor_mnn_int.cpp          # MODIFY: resolve + pass scale (2 call sites)
    ├── processing_processor_mnn_image.cpp        # MODIFY: resolve + pass scale (1 call site)
    ├── processing_processor_mnn_texture1d.cpp    # MODIFY: resolve + pass scale (1 call site; parameters already used by ParseLayout)
    ├── processing_processor_mnn_tensor.cpp       # MODIFY: resolve + pass scale (2 call sites)
    ├── processing_processor_mnn_texturecube.cpp  # MODIFY: resolve + pass scale (2 call sites; parameters already used by ParseLayout)
    ├── processing_processor_mnn_string.cpp       # MODIFY: resolve + pass scale (1 call site; parameters already used for maxLength)
    ├── processing_processor_mnn_volume.cpp       # MODIFY: resolve + pass scale (1 call site; parameters already used by ParseLayout)
    └── processing_processor_render.cpp           # MODIFY: resolve + pass maskBits (1 QuantizeByteBuffer call site; parameters already used by ResolveUniforms)

SuperGenius/test/src/
├── processing_datatypes/texture3d-processing-definition.json   # MODIFY: add quantScale parameter entry (D-10, final value TBD via binary search)
└── processing_conformance_security/
    ├── secv01_counter_test.cpp             # UNCHANGED (Phase 12's 2 existing cases stay as-is)
    ├── secv01_tex3d_counter_test.cpp       # NEW (D-09) -- name mirrors secv01_counter_test.cpp's convention
    ├── CMakeLists.txt                      # MODIFY: add new test source (or new target, planner's call)
    └── fixtures/
        └── secv01-corrupted-spleen_ct_seg.mnn   # NEW (D-09) -- byte-perturbed copy of spleen_ct_seg.mnn, same technique as 12-02-PLAN.md Task 1
```

### Pattern 1: Find-by-name-in-`parameters` lookup with silent fallback (D-01/D-02, existing convention)

**What:** A free function takes `const std::vector<sgns::Parameter> *parameters` and a key name, iterates with `std::find_if` comparing `param.get_name() == key`, validates the found value's shape/type, and returns a default if not found or invalid.

**When to use:** Every schema-declarable per-job configuration value that doesn't warrant a dedicated formal schema field.

**Example (existing, `processing_processor_mnn_volume.cpp:40-71`, the exact template to replicate):**
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
    return VolumeLayout::HWD; // silent fallback, mirrors D-04/D-08
}
```

**Recommended new code, mirroring this exactly (single-key lookup, not a multi-key list since `quantScale`/`byteQuantMode` are fixed names per D-02):**
```cpp
// Recommended addition to quantization.hpp/quantization.cpp
namespace sgns::sgprocmanagerquant
{
    // D-04/D-05: falls back to 2^15 (32768.0f) on missing, non-numeric,
    // zero/negative, or non-power-of-two declared value.
    float ResolveQuantScale( const std::vector<sgns::Parameter> *parameters );

    // D-07/D-08: falls back to 0 (identity, matches v2.1) on missing,
    // negative, N>8, or non-numeric declared value.
    int ResolveByteQuantMode( const std::vector<sgns::Parameter> *parameters );

    void QuantizeFloatBuffer( float *data, size_t count, float scale );
    void QuantizeByteBuffer( uint8_t *data, size_t count, int maskBits );
}
```

### Pattern 2: Power-of-two validation (new, D-05 — not yet established anywhere in the codebase)

**What:** `S > 0 && (bits_of(S) & (bits_of(S) - 1)) == 0` style check, applied to the resolved float value's `S` before it's used as a rounding scale.

**When to use:** Only for `quantScale`, per D-05 — this is a hard requirement, not documented guidance.

**Example (no direct precedent in-repo; standard bit-trick, recommended implementation):**
```cpp
// Recommended: validate resolved scale is a positive power of two (D-05)
bool IsPositivePowerOfTwo( double value )
{
    if ( !( value > 0.0 ) ) { return false; }
    // A float/double power-of-two has a value whose base-2 logarithm is an
    // integer; simplest robust check for values already known to be exact
    // powers of two in the relevant range is frexp-based or integer-bit-check
    // after confirming value has no fractional part and fits an integral type.
    if ( std::floor( value ) != value ) { return false; }
    const auto asInt = static_cast<uint64_t>( value );
    return asInt != 0 && ( asInt & ( asInt - 1u ) ) == 0u;
}
```
Any value failing this check triggers D-04's silent fallback to `S=32768.0f` — no warning, no job rejection.

### Anti-Patterns to Avoid

- **Defaulted function parameters for `scale`/`maskBits`:** Would let a future new call site silently omit resolution and keep behaving as if `parameters` were never consulted, defeating the purpose of making this configurable. Make the new parameters required (no default) so every call site is forced to explicitly resolve first — matches how `ParseLayout`/`ResolveUniforms` are always explicitly called, never defaulted.
- **Duplicating the resolver logic per-file:** `ParseLayout` is already duplicated 3x (`volume.cpp`/`texture1d.cpp`/`texturecube.cpp`) as an established (if imperfect) local convention, but that duplication is for a per-input-name-prefixed key (`inputName + "Layout"`); `quantScale`/`byteQuantMode` are single fixed global key names per D-02, with no per-file variation, so there is no reason to duplicate — centralizing in `quantization.cpp` itself is strictly better here and keeps the D-04/D-05/D-08 fallback rules in exactly one place for the binary-search tuning process (D-10) to iterate against.
- **Mutable global/static configuration state set by a "resolver invoked before the unchanged call":** Would reintroduce hidden shared state and break thread-safety assumptions the rest of the codebase doesn't have to reason about. Always thread the resolved value explicitly through the function's argument list.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Schema parameter declaration mechanism | A new formal schema field + quicktype regen | Existing generic `parameters` array (D-01) | Already locked; avoids regenerating headers across every consumer |
| Find-by-name parameter lookup | A generic templated parameter-lookup utility class | The existing `std::find_if` inline pattern (`ParseLayout`/`ResolveUniforms`) | Matches established codebase convention; a new abstraction here is unjustified for 2 fixed key names |
| Power-of-two check | A custom float-parsing/logarithm-based approach | Integer bit-trick (`x & (x-1) == 0`) on the value cast to an integral type after an exactness check | Standard, branch-free, avoids floating-point comparison pitfalls |

**Key insight:** Every piece of infrastructure this phase needs (parameter declaration, lookup-with-fallback, quantize-then-hash ordering) already exists in the codebase from Phase 10-13; this phase's job is threading a resolved value through, not building new infrastructure.

## Common Pitfalls

### Pitfall 1: Forgetting a call site when wiring in the new required parameter

**What goes wrong:** One of the 21 call sites (or a future 22nd) is missed, causing either a compile error (good, since the parameter is required) or — if a default value were used instead — silent continuation of hardcoded behavior for that one site only, invisible until a cross-hardware divergence investigation.

**Why it happens:** 21 call sites across 14 files is easy to undercount by hand; two files (`mnn_float.cpp`, `mnn_int.cpp`, `mnn_mat2/3/4.cpp`, `mnn_tensor.cpp` — 6 files total) each have 2 call sites (a per-chunk loop call and a final stitched-output call), which is easy to miss if only grepping for the function name once per file.

**How to avoid:** Use the exact grep-confirmed call site table in this document (21 sites, 14 files) as the task checklist; make the new parameter required (no default) so a missed site fails to compile rather than silently using stale behavior.

**Warning signs:** A file compiles but its `StartProcessing` still has a vestigial `(void)parameters;` line untouched after the phase claims completion.

### Pitfall 2: Validating `quantScale` as a power of two using naive float equality after division

**What goes wrong:** A check like `log2(value) == floor(log2(value))` suffers from floating-point imprecision near powers of two, potentially accepting or rejecting borderline values inconsistently across platforms — reintroducing exactly the kind of cross-hardware nondeterminism this whole milestone exists to eliminate (per D-05's explicit goal: "guarantees the exact float round-trip property... can never be silently violated").

**Why it happens:** `log2`/`pow` based checks are the first thing most engineers reach for, but they are library/platform-dependent in their last-bit behavior.

**How to avoid:** Use the integer bit-trick (`asInt & (asInt - 1) == 0`) after confirming the value has no fractional part (`std::floor(value) == value`) and fits in the target integral type — deterministic across all platforms, no library-dependent transcendental function involved.

**Warning signs:** The same declared `quantScale` value passes validation on one platform's build and fails (or vice versa) on another.

### Pitfall 3: New tex3d counter-test uses the old-style `Process()` return value instead of `.artifacts[0].artifactId`

**What goes wrong:** `processing_datatypes_test.cpp`'s existing `Texture3DProcessingTest` calls the same 4-arg `Process()` overload but treats the return value as an implicitly-convertible `std::vector<uint8_t>` (`.size()`/`.empty()`) — this is `ProcessOutput`'s backward-compat conversion operator (Phase 08 D-10), not the D-01-compliant artifact-level hash `secv01_counter_test.cpp` uses. The new D-09 tex3d counter-test needs the artifact-level hash (`.artifacts[0].artifactId`, compared via `std::memcmp` against `sgns::sgprocessing::SHA256_HASH_SIZE`), matching `secv01_counter_test.cpp`'s existing two `TEST_F` cases exactly, not `processing_datatypes_test.cpp`'s older style.

**Why it happens:** Both patterns compile and both are present in the codebase for different fixtures; picking the wrong one produces a test that technically runs but doesn't actually assert what SECV-01-style counter-tests require (D-13's binary `ASSERT_NE`/`EXPECT_NE` on `artifactId`, never on `combinedHash`/the legacy vector-of-bytes conversion).

**How to avoid:** Copy `secv01_counter_test.cpp`'s exact `Process()` → `.value().artifacts[0].artifactId` → `std::memcmp(..., SHA256_HASH_SIZE)` pattern verbatim for the new test, not `processing_datatypes_test.cpp`'s pattern.

**Warning signs:** New test code calls `.value().size()`/`.empty()` on the `Process()` result instead of indexing into `.artifacts`.

### Pitfall 4: Corrupting `spleen_ct_seg.mnn` at an offset that breaks the flatbuffers header/vtable region

**What goes wrong:** The existing `secv01-corrupted-float_model.mnn` fixture (12-02-PLAN.md) was created by XORing a single byte at an offset chosen to fall in the back ~75-80% region of the file, specifically inside the weight-tensor data (not the flatbuffers schema/vtable region near the front) — an offset too close to the front risks the file failing to parse at all (`MNN::Interpreter::createFromBuffer()` returning null) rather than loading with a materially different (but structurally valid) inference result.

**Why it happens:** `spleen_ct_seg.mnn` (~19.3 MB) is a real, much larger model than `float_model.mnn` (20496 bytes); an offset chosen by naive proportional scaling from the small model's offset (15360/20496 ≈ 75%) may still land in a different structural region for this larger, differently-laid-out file.

**How to avoid:** Follow the exact same empirical verification loop 12-02-PLAN.md's Task 1 used: pick an offset well into the back region, XOR one byte with `0xFF`, then verify empirically (a standalone check, or the new test itself failing to load) that `MNN::Interpreter::createFromBuffer()` still returns non-null and that the corrupted model's inference output on the same input differs materially from the original before committing the corrupted `.mnn` file. Try a different offset if the first choice breaks parsing or produces byte-identical output.

**Warning signs:** `ProcessingManager::Create()`/`Process()` on the corrupted-model job fails outright, or the new counter-test's two `artifactId`s come back equal (meaning the corruption produced no detectable difference at this scale's precision — try a different offset or reconsider the chosen `S`).

## Code Examples

### Existing: `mnn_string.cpp`'s already-wired parameter lookup (the one file with no vestigial `(void)parameters;`)

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
This is the exact style to replicate for `quantScale` (checking `param.get_type() == sgns::ParameterType::FLOAT` and `def.is_number()`/`def.get<float>()`) and `byteQuantMode` (checking `ParameterType::INT` and `def.is_number_integer()`).

### Existing: `processing_processor_render.cpp`'s `ResolveUniforms` parameter-lookup pattern (`~854-873`)

```cpp
// Source: SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp:854-873
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

### Existing: `QuantizeFloatBuffer`'s current hardcoded rounding branch (`quantization.cpp:37,90-94`), the only branch this phase changes

```cpp
// Source: SuperGenius/SGProcessingManager/src/util/quantization.cpp:37,90-94
constexpr float kScale = 32768.0f; // 2^15
// ...
else
{
    data[i] = std::round( x * kScale ) / kScale;
}
```
Becomes: `data[i] = std::round( x * scale ) / scale;` where `scale` is the function's new required parameter (resolved once per `StartProcessing` call, not per-element).

### Existing: `secv01_counter_test.cpp`'s exact assertion pattern to replicate for the new tex3d test

```cpp
// Source: SuperGenius/test/src/processing_conformance_security/secv01_counter_test.cpp:188-193
EXPECT_NE( std::memcmp( prCorrect.value().artifacts[0].artifactId,
                         prCorrupted.value().artifacts[0].artifactId,
                         sgns::sgprocessing::SHA256_HASH_SIZE ),
           0 )
    << "A deliberately corrupted MNN model must produce a different "
       "post-quantization artifactId than the correct model -- SECV-01/T-12-06";
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| `S=2^20` fixed float scale | `S=2^15` fixed float scale | Phase 13 Plan 13-04 (2026-08-12) | Current baseline this phase makes per-job-configurable; unrelated to this phase's own change |
| Single global `kScale` for all float jobs | Per-job `quantScale` schema override, `S=2^15` global-default fallback | This phase (14) | Directly closes the tex3d/spleen_ct_seg gap documented in STATE.md |
| Byte path: literal no-op (`(void)data; (void)count;`) | Per-job `byteQuantMode` (N low bits masked), `N=0` global-default fallback | This phase (14) | Additive per QUANT-CFG-02 — existing jobs declaring nothing get byte-identical v2.1 behavior |

**Deprecated/outdated:** None — this phase is purely additive per QUANT-CFG-02; no existing behavior is removed for jobs that declare nothing.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Centralizing `ResolveQuantScale`/`ResolveByteQuantMode` in `quantization.hpp`/`.cpp` (rather than duplicating per-processor-file, mirroring `ParseLayout`'s 3x duplication) is the better structural choice | Architecture Patterns, Pattern 1 | If the planner/team has an unstated preference for per-file duplication (e.g. to keep `quantization.cpp` dependency-free of `generated/Parameter.hpp`), the recommended file layout in "Recommended Project Structure" would need adjusting — this is flagged in CONTEXT.md as explicit Claude's Discretion, not a locked decision, so this is a recommendation, not fact |
| A2 | Required (non-defaulted) function parameters for `scale`/`maskBits` is preferable to a defaulted overload | Anti-Patterns to Avoid | If the team prefers overloads for a smoother rollout (old 2-arg calls in third-party or future code keep compiling), a defaulted overload could be chosen instead without changing any other conclusion in this research |
| A3 | The corrupted-`spleen_ct_seg.mnn` fixture should use the same single-byte-XOR-in-weight-region technique as `secv01-corrupted-float_model.mnn`, scaled to the larger file's actual layout | Common Pitfalls, Pitfall 4 | If MNN's flatbuffers layout differs structurally enough between the two models that a proportionally-scaled offset lands in the header/vtable region, the planner's task should budget for an empirical offset-search loop (as documented), not a single fixed offset |

**If this table is empty:** N/A — see above; all three assumptions are engineering-judgment recommendations within CONTEXT.md's explicitly granted discretion, not claims about external facts.

## Open Questions

1. **Exact final `quantScale` value for `spleen_ct_seg`**
   - What we know: STATE.md estimates ~`S=2^7`-`2^8` based on the measured delta `0.005126953125` being 168x the current `S=2^15` grid step (`3.0517578125e-05`); D-10 specifies binary-search-against-the-new-D-09-counter-test methodology, identical to Phase 13's local rebuild+ctest binary search that chose `S=2^15` for the small model (13-04-PLAN.md).
   - What's unclear: The exact value is empirically determined at execution time, not knowable from research alone — it depends on where the new tex3d counter-test's pass/fail boundary actually falls for this specific corrupted-model fixture.
   - Recommendation: Plan a binary-search task identical in shape to 13-04-PLAN.md's Task 1 (build the new counter-test first per D-09, then locally rebuild + `ctest -R` iteratively over power-of-two `S` candidates starting from `2^7`/`2^8`, no cross-machine capture needed for this step since it's a local pass/fail check, not a divergence measurement).

2. **CMakeLists.txt wiring for the new tex3d counter-test: same target as `secv01_counter_test.cpp` or a new sibling target?**
   - What we know: `processing_conformance_security/CMakeLists.txt` currently lists exactly one source file (`secv01_counter_test.cpp`) in its `addtest(processing_conformance_security_test ...)` call, and has a `POST_BUILD` step copying `fixtures/` into the binary's output directory — a pattern the new corrupted-`.mnn` fixture file would also need.
   - What's unclear: Whether the new test should be a second source in the same `processing_conformance_security_test` target (simpler, reuses the same `POST_BUILD` fixture-copy step) or its own new target (cleaner isolation given the ~19MB model file and correspondingly slower test).
   - Recommendation: Add as a second source (`secv01_tex3d_counter_test.cpp`) in the existing `processing_conformance_security_test` target — the `POST_BUILD` copy step already generalizes to any file placed under `fixtures/`, and creating a second target purely for one new test adds CMake surface area without a clear benefit; the ~19MB fixture's build-time cost is a one-time copy, not a compile-time cost.

## Environment Availability

Not applicable — this phase has no new external tool/service/runtime dependencies. It builds against the same existing CMake/MSVC (Windows) or equivalent (Mac/Linux) toolchain, MNN library, and GTest framework already used by every prior phase in this workstream (Phase 09-13). `spleen_ct_seg.mnn`/`spleen_15.raw` fixture files already exist on disk (`SuperGenius/test/src/processing_datatypes/`, ~19.3 MB / ~24.1 MB respectively) — no new download or fetch step is needed.

## Validation Architecture

Skipped — `workflow.nyquist_validation` is explicitly `false` in `.planning/config.json`.

## Security Domain

`security_enforcement` is `true` (ASVS level 1, `security_block_on: high`) in `.planning/config.json` — this section is required.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-------------------|
| V2 Authentication | No | No auth surface touched by this phase |
| V3 Session Management | No | No session surface touched by this phase |
| V4 Access Control | No | No access-control surface touched by this phase |
| V5 Input Validation | **Yes** | Schema-declared `quantScale`/`byteQuantMode` values are attacker-influenceable input (a job author, potentially adversarial in this project's distributed/P2P processing context, controls the schema). D-04/D-05/D-08's silent-fallback-on-invalid-value rules ARE this phase's V5 control — enforced by the power-of-two/type/range checks in `ResolveQuantScale`/`ResolveByteQuantMode`, never by trusting the declared value directly. |
| V6 Cryptography | No | SHA-256 hashing usage is unchanged; this phase touches only the pre-hash quantization step, not the hash algorithm itself |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|----------------------|
| Adversarial job schema declares an out-of-range/degenerate `quantScale` (e.g. an enormous or tiny non-power-of-two value) attempting to widen the effective tolerance enough to mask a genuinely corrupted result | Tampering | D-04/D-05's mandatory power-of-two + range validation with silent fallback to the safe `S=2^15` default; this is exactly what D-09's new tex3d counter-test is designed to empirically prove holds even at tex3d's much coarser chosen scale |
| Adversarial job schema declares `byteQuantMode` (`N`) at the maximum allowed value (`N=8`, masking all 8 bits, collapsing every byte to 0) to trivially force byte-identical output regardless of actual content | Tampering | D-08's explicit `N>8` rejection and D-07's requirement that `N=0`/absent is the only value satisfying the "no separate on/off flag needed" additive requirement; planning should note `N=8` is a real, disclosed edge case explicitly allowed by "N>8 is invalid" and worth an explicit fallback-boundary test case (`N=8` valid/no-fallback vs `N=9` invalid/fallback-to-0) in the extended `quantization_test.cpp` |
| Non-numeric or malformed `default` JSON value for either parameter (schema author error or deliberate malformation) | Tampering | `nlohmann::json`'s `.is_number()`/`.is_number_integer()` type checks before any numeric conversion, mirroring `mnn_string.cpp`'s existing `def.is_number_integer() && def.get<int>() > 0` pattern — never call `.get<T>()` on an unchecked type |

## Sources

### Primary (HIGH confidence — all `[VERIFIED: local codebase read]`)

- `SuperGenius/SGProcessingManager/include/util/quantization.hpp` — current `QuantizeFloatBuffer`/`QuantizeByteBuffer` doc comments and signatures
- `SuperGenius/SGProcessingManager/src/util/quantization.cpp` — current implementation, `kScale=32768.0f` (2^15), byte-identity no-op
- `SuperGenius/SGProcessingManager/src/processors/*.cpp` (14 files, grep-confirmed 21 call sites) — every `QuantizeFloatBuffer`/`QuantizeByteBuffer` call site and its enclosing `StartProcessing` signature
- `SuperGenius/SGProcessingManager/generated/Parameter.hpp`, `ParameterType.hpp`, `Constraints.hpp`, `Generators.hpp` — exact accessor API (`get_name()`, `get_parameter_default()` returning `const nlohmann::json&`, `get_type()` returning `const ParameterType&`, enum values `ARRAY/BOOL/FLOAT/INT/OBJECT/STRING/URI`), and `from_json`'s `"default"` → `parameter_default` mapping
- `SuperGenius/SGProcessingManager/gnus-processing-schema.json:56-62,123-152` — existing generic `parameters`/`parameter` schema (type/default/description/constraints with min/max/enum/pattern)
- `SuperGenius/test/src/processing_datatypes/texture3d-processing-definition.json` — current structure (only a `modelUri` parameter; no `quantScale` yet)
- `SuperGenius/test/src/processing_conformance_security/secv01_counter_test.cpp` — full existing SECV-01 methodology (both `MnnCorruptedModelStillDiverges` and `RenderWrongShaderConstantStillDiverges` cases), `Process()` → `.artifacts[0].artifactId` → `std::memcmp` pattern
- `SuperGenius/SGProcessingManager/test/util/quantization_test.cpp` — existing 7-case `QuantizationTest` structure/conventions
- `SuperGenius/test/testutil/processing_conformance_fixture.hpp` — `ProcessorConformanceFixture`, `PatchJsonUrisToAbsolute`, `BinPath()`/`PatchedJson()` helpers
- `SuperGenius/test/src/processing_conformance_security/CMakeLists.txt` — existing test target wiring and fixture `POST_BUILD` copy pattern
- `.planning/workstreams/sgproc-render/phases/12-quantization-normalization-implementation/12-02-PLAN.md`/`12-VERIFICATION.md` — exact corrupted-model fixture creation technique (byte-perturbation offset selection, empirical load/divergence verification loop)
- `.planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/13-04-PLAN.md` — exact local binary-search-against-SECV-01 methodology (no cross-machine capture needed for the search itself)
- `SuperGenius/test/src/processing_datatypes/processing_datatypes_test.cpp:302-372` — the older `Process()` return-value convention to explicitly NOT replicate for the new counter-test (Pitfall 3)
- `SuperGenius/SGProcessingManager/test/util/CMakeLists.txt` — `quantization_test` target wiring

### Secondary (MEDIUM confidence)

None — all findings for this phase were directly verifiable by reading the actual source files in this repository; no web-search-derived claims were needed since this phase's scope is entirely internal engineering.

### Tertiary (LOW confidence)

None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new libraries; every component already in active use in this codebase
- Architecture: HIGH — resolver pattern is a direct, verified replication of `ParseLayout`/`ResolveUniforms`, both read in full
- Pitfalls: HIGH — Pitfall 3 (wrong `Process()` return convention) and Pitfall 4 (corruption offset) are both grounded in directly-read existing code/plans, not speculation
- Call site enumeration: HIGH — grep-verified exact count (21 call sites, 14 files) with line numbers

**Research date:** 2026-08-13
**Valid until:** No expiry concern — this is a closed, self-contained codebase snapshot; re-verify only if `quantization.hpp`/`.cpp` or any of the 14 processor files change before planning executes.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-------------------|
| QUANT-CFG-01 | A processing job's schema can declare a per-data-type normalization precision parameter (e.g. a quantization scale for float32 outputs), read by `QuantizeFloatBuffer`/`QuantizeByteBuffer` instead of the single hardcoded `kScale` constant from v2.1 | "Architecture Patterns" Pattern 1 gives the exact find-by-name-in-`parameters` mechanism (mirroring `ParseLayout`/`ResolveUniforms`) to replicate; "Recommended Project Structure" lists all 21 call sites (14 files) that need the resolved value wired in; "Code Examples" gives the exact current hardcoded branch (`quantization.cpp:37,90-94`) that changes from `kScale` to a variable `scale` parameter |
| QUANT-CFG-02 | When no precision is schema-declared, normalization falls back to v2.1's existing fixed constants (S=2^15 for float32, byte-identity for uint8) — additive, not a breaking change to existing jobs | "Pattern 1" and "Pitfall 2" describe the exact D-04/D-05/D-08 silent-fallback validation (power-of-two check for `quantScale`, `N=0`/absent for `byteQuantMode`) that guarantees this; "State of the Art" table confirms the fallback values are the existing S=2^15 / no-op byte behavior, unchanged |
| QUANT-CFG-03 | A workload with materially different divergence characteristics (tex3d/spleen_ct_seg) can be configured with its own empirically-derived precision, citing real captured cross-machine divergence data | "Common Pitfalls" Pitfalls 3-4 and "Open Questions" #1 document the exact binary-search-against-a-new-counter-test methodology (mirroring 13-04-PLAN.md) and the corrupted-model fixture creation technique (mirroring 12-02-PLAN.md) needed to derive and prove tex3d's own `quantScale`; "Recommended Project Structure" specifies the new test file and fixture paths |

</phase_requirements>
