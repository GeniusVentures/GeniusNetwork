# Phase 3: RenderProcessor Implementation & Determinism - Pattern Map

**Mapped:** 2026-07-31
**Files analyzed:** 5 (2 heavily modified, 1 new-error-type addition, 2 lightly touched)
**Analogs found:** 5 / 5 (all analogs are the files' own current/prior state or a sibling processor — this is almost entirely a "fill in the stub, following sibling conventions" phase, not a "copy from an unrelated file" phase)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|----------------|
| `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp` | processor (GPU execution) | request-response (batch job in, hash out) | itself (current stub, `InitializeContext()` already correct) + `processing_processor_mnn_image.cpp` (sibling processor's `StartProcessing()`/error-return shape) | exact (own file) / role-match (MNN sibling) |
| `SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp` | processor header | — | itself (current stub) | exact |
| `SuperGenius/SGProcessingManager/include/processors/processing_processor.hpp` | model/DTO | — | itself (`ProcessingResult` struct, gaining new error field) | exact |
| `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` (`Process()` dispatch gate, D-27/D-28; possibly `GetCidForProc()`/wire format, Pitfall 1/6) | service/dispatcher | request-response + batch | itself (current `Process()`/`GetCidForProc()`/`SerializeCompiledStages()`) | exact |
| `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_image.cpp` (retroactive D-28 fix only — read, not otherwise copied) | processor (sibling) | request-response | itself + `_mnn_string`/`_mnn_volume` siblings (same anti-pattern, same fix shape) | exact |

No render-specific analog exists elsewhere in the codebase (no other Vulkan graphics-pipeline code, no other offscreen-framebuffer code) — the closest available patterns are (a) this file's own already-correct `InitializeContext()`, and (b) sibling MNN processors' `StartProcessing()` signature/return conventions, which is exactly what CONTEXT.md's Established Patterns section already points to.

## Pattern Assignments

### `processing_processor_render.cpp` / `.hpp` (processor, GPU execution)

**Analog:** itself (`InitializeContext()` is done; `StartProcessing()` is the stub to replace) + `processing_processor_mnn_image.cpp` (sibling `StartProcessing()` shape)

**Imports pattern** (render file, lines 1-5):
```cpp
#include "processors/processing_processor_render.hpp"
#include "processingbase/vulkan_init_guard.hpp"
#include <VkBootstrap.h>
#include <algorithm>
#include <mutex>
```
New Vulkan work will need additional generated-schema headers (`RenderShaderConfig.hpp`, `RenderTarget.hpp`, `VertexBuffer.hpp`, `PipelineState.hpp`, `Stage.hpp`, etc.) and `shaders/shader_compiler.hpp`'s `CompiledShaderStage` shape (used only by `ProcessingManager`, but its `sgns::Stage` enum is the type `RenderProcessor` must parse back out of the wire format) — pull these in as needed, following the same flat, non-barrel `#include "x/y.hpp"` convention already used.

**Existing, already-correct context-init pattern** (`processing_processor_render.cpp:29-118`) — DO NOT rewrite; only add new logic that runs after `InitializeContext()` succeeds:
```cpp
bool RenderProcessor::InitializeContext()
{
    if ( m_contextInitialized )
        return true;

    std::lock_guard<std::mutex> lock( sgns::sgprocessing::VulkanInitMutex() );

    if ( m_contextInitialized )
        return true;
    // ... vkb::InstanceBuilder / PhysicalDeviceSelector / DeviceBuilder ...
    m_instance = vkb_instance.instance;
    m_physicalDevice = vkb_device.physical_device;
    m_device = vkb_device.device;
    m_queue = queue_ret.value();
    m_contextInitialized = true;
    return true;
}
```
Note the mutex is taken ONLY around instance/device creation, not around the whole method — per RESEARCH.md's Anti-Pattern warning, do not extend this lock around the new per-job pipeline/buffer/draw work; that would wrongly serialize render jobs against MNN inference jobs on unrelated devices.

**Current stub to replace** (`processing_processor_render.cpp:120-143`):
```cpp
ProcessingResult RenderProcessor::StartProcessing(
    std::vector<std::vector<uint8_t>> &chunkhashes,
    const sgns::IoDeclaration         &proc,
    std::vector<char>                 &imageData,
    std::vector<char>                 &modelFile,
    const std::vector<sgns::Parameter> *parameters )
{
    (void)proc;
    (void)imageData;
    (void)modelFile;
    (void)parameters;

    if ( !InitializeContext() )
    {
        ProcessingResult result;
        result.hash = std::vector<uint8_t>( 32, 0 );
        return result;
    }

    ProcessingResult result;
    result.hash = std::vector<uint8_t>( 32, 0 );
    m_progress = 100.0f;
    return result;
}
```
`modelFile` currently arrives as the raw bytes of `SerializeCompiledStages()`'s output (see ProcessingManager pattern below) — `RenderProcessor` must invert that exact packing (Code Examples §1 in RESEARCH.md is the concrete inverse-parse snippet to use, keyed off this file's own `SerializeCompiledStages` comment block).

**Sibling processor's failure-return anti-pattern to explicitly NOT copy** (`processing_processor_mnn_image.cpp:47,82`):
```cpp
if ( !maybe_channels )
{
    return ProcessingResult{};   // hash of zeros, NO detail — this is exactly what D-25..D-28 replace
}
...
if ( !procresults || procresults->elementSize() == 0 || !procresults->host<float>() )
{
    m_logger->error( "MNN image processing failed for chunk {}", chunkIdx );
    return ProcessingResult{};   // same anti-pattern
}
```
`RenderProcessor`'s every failure path must instead populate the new `ProcessingResult` error field (D-25/D-26) with a per-stage enum + `VkResult`/message detail, per D-24 destroying whatever was already built first (see teardown-list note below). Do not use the exception path — matches D-25's explicit constraint.

**Progress-reporting convention** (`processing_processor_mnn_image.cpp:64,95`):
```cpp
m_progress = 0.0f; // Reset progress at start
...
m_progress = std::round(((chunkIdx + 1) * 100.0f / totalChunks) * 100.0f) / 100.0f;
```
`RenderProcessor` is a single-draw-call job (no per-chunk loop), so `m_progress` can simply be set to `100.0f` on success (as the current stub already does) — no intermediate progress reporting is expected for a one-shot render pass unless the planner decides otherwise.

**Teardown-on-failure shape (D-22/D-23/D-24):** No existing analog for "ordered teardown list built up as each Vulkan object is created, unwound on any failure" exists in this codebase yet (MNN processors don't own per-job Vulkan objects at this granularity — MNN's `createSession()`/`Interpreter` lifetime is managed differently, by MNN itself, not by hand-rolled `Vk*` handles). This is genuinely new code; RESEARCH.md's Recommended Project Structure suggests private helper methods (`BuildRenderPass()`, `BuildPipeline()`, `UploadBuffers()`, `RecordAndSubmit()`, `Readback()`, `TeardownAll()`) each appending to a single ordered destroy-list — follow that structure since no closer in-repo precedent exists.

---

### `processing_processor.hpp` (`ProcessingResult`, model/DTO)

**Analog:** itself — current struct to extend, not replace

**Current shape** (lines 19-25):
```cpp
struct ProcessingResult
{
    std::vector<uint8_t> hash;
    std::shared_ptr<std::pair<std::vector<std::string>, std::vector<std::vector<char>>>> output_buffers;
    /// Output locations for each saved result (file paths, IPFS CIDs, URLs, etc.)
    std::vector<std::string> output_locations;
};
```
D-25 adds a new error field here (exact shape — struct vs. `std::optional<Error>` — left to planner's discretion per CONTEXT.md). Follow the existing sibling `ShaderCompiler::Error` pattern below for the enum+outcome idiom already used in this codebase, rather than inventing a new error-handling convention.

**Existing enum+outcome idiom to mirror for the new per-stage error type** (`shaders/shader_compiler.hpp:41-45,70`):
```cpp
class ShaderCompiler
{
public:
    enum class Error
    {
        COMPILE_FAILED    = 1,
        VALIDATION_FAILED = 2
    };
    outcome::result<CompiledShaderStage> CompileAndValidate( ... );
    ...
};
...
OUTCOME_HPP_DECLARE_ERROR_2( sgns::sgprocessing, ShaderCompiler::Error );
```
And the `ProcessingManager::Error` enum this same idiom already extends for dispatch-level errors (`ProcessingManager.hpp:38-48`):
```cpp
enum class Error
{
    PROCESS_INFO_MISSING     = 1,
    INVALID_JSON             = 2,
    INVALID_BLOCK_PARAMETERS = 3,
    NO_PROCESSOR             = 4,
    MISSING_INPUT            = 5,
    INPUT_UNAVAIL            = 6,
    SHADER_COMPILE_FAILED    = 7,
    SPIRV_VALIDATION_FAILED  = 8,
};
```
D-26's new per-stage render error enum (pipeline creation, buffer/image allocation, shader module creation, draw submission, readback, etc.) should follow this exact `enum class Error { NAME = N, ... }` + `OUTCOME_HPP_DECLARE_ERROR_2` style if it needs outcome-result plumbing, OR — since D-25 says "new field, not exceptions, no signature change" — it may more simply live as a plain struct/optional field on `ProcessingResult` carrying `{ enum StageError; std::string message; }` without going through the `outcome::result<>` machinery at all (since `StartProcessing()`'s return type is the concrete `ProcessingResult`, not an `outcome::result<ProcessingResult>`). Planner should pick one; both idioms already exist side-by-side in this codebase.

---

### `ProcessingManager.cpp` (dispatch gate D-27/D-28, and possibly `GetCidForProc()`/wire format per Pitfall 1/6)

**Analog:** itself — current `Process()`/`GetCidForProc()`/`SerializeCompiledStages()`

**Current dispatch call site to gate** (`ProcessingManager.cpp:791-796` + `922`):
```cpp
auto processResult = m_processor->StartProcessing( chunkhashes,
                                                   processing_.get_inputs()[index.value()],
                                                   *buffers->second,
                                                   *buffers->first,
                                                   parameters );

const auto &outputs = processing_.get_outputs();
if ( processResult.output_buffers && !outputs.empty() )
{
    // ... FileManager::SaveASync(...) loop ...
}

return processResult.hash;   // <-- D-27/D-28: must check processResult's new error field
                              //     BEFORE this save loop runs, for BOTH render and MNN paths,
                              //     and return a failure instead of a zero-hash success.
```
The gate should be inserted immediately after `StartProcessing()` returns, before the `if ( processResult.output_buffers ...)` save block, checking the new error field from D-25 and returning an `outcome::failure(...)` (reusing/extending `ProcessingManager::Error` or wrapping the processor-level error) instead of falling through to `FileManager::SaveASync`/`return processResult.hash`.

**Existing per-stage wire-format pattern to invert (Pitfall 6 gap noted)** (`ProcessingManager.cpp:65-110`):
```cpp
/**
 * Packs validated per-stage SPIR-V into a single byte buffer.
 * PROVISIONAL WIRE FORMAT ...
 * Layout (all integers little-endian, native uint32_t width):
 *   uint32_t stage_count
 *   per stage:
 *     uint32_t stage_tag    (static_cast<uint32_t>(sgns::Stage))
 *     uint32_t word_count   (number of following uint32_t SPIR-V words)
 *     word_count * uint32_t spirv_words
 */
std::vector<char> SerializeCompiledStages(
    const std::vector<sgns::sgprocessing::CompiledShaderStage> &stages )
{
    std::vector<char> out;
    auto appendU32 = [&out]( uint32_t value ) { /* memcpy append */ };
    appendU32( static_cast<uint32_t>( stages.size() ) );
    for ( const auto &compiled : stages )
    {
        appendU32( static_cast<uint32_t>( compiled.stage ) );
        appendU32( static_cast<uint32_t>( compiled.spirv.size() ) );
        // memcpy spirv words
    }
    return out;
}
```
`entry_point` is NOT in this format (Pitfall 6) — if the planner decides to extend the wire format rather than hard-code `"main"`, this is the exact function to extend (append a length-prefixed string per stage), and `processing_processor_render.cpp`'s new parse function must be kept as the exact byte-for-byte inverse.

**Where render-pass input fetching currently happens** (`ProcessingManager.cpp:942-1018`, `GetCidForProc()`) — read for context on Pitfall 1 (only "input:" is resolved; `vertex_buffer`/`index_buffer`/uniform `source:`/`target:` refs are NOT resolved anywhere yet). If the planner's resolution to Pitfall 1 is "extend `ProcessingManager`'s fetch plumbing," this `isRender` branch (lines 954-974) is the analogous per-stage-fetch-and-serialize pattern to extend (queue additional `GetSubCidForProc()` calls alongside the existing per-stage shader fetch, pack results into a new or extended wire format consumed by `RenderProcessor`).

**Existing single-lookup resolver this phase's new resolver must go beyond** (`ProcessingManager.cpp:186-191`, `1037-1042`):
```cpp
const auto &inputs = processing_.get_inputs();
for ( size_t i = 0; i < inputs.size(); ++i )
{
    std::string sourceKey = "input:" + inputs[i].get_name();
    m_inputMap[sourceKey] = i;
}
...
outcome::result<size_t> ProcessingManager::GetInputIndex( const std::string &input )
{
    auto it = m_inputMap.find( input );
    if ( it != m_inputMap.end() ) { return it->second; }
    ...
}
```
This is the ONLY working prefix-resolution code in the repo today — it only handles `"input:name"`. Per RESEARCH.md Pitfall 1/Open Question 1, this is the concrete gap the planner must explicitly decide how to close (extend this map/resolver to also index `output:`/`internal:`/`parameter:` prefixes for `vertex_buffer.source`/`index_buffer.source`/uniform `source`/output `target`, vs. have `RenderProcessor` resolve locally) — do not let a plan assume a generic resolver already exists beyond this.

---

## Shared Patterns

### Error-field-gates-save-path (D-27/D-28)
**Source:** `ProcessingManager.cpp:791-796,922` (dispatch call site)
**Apply to:** Both the new render dispatch path and the existing MNN dispatch path (single shared call site — `Process()` doesn't branch by processor type after `StartProcessing()` returns, so one gate insertion covers both per D-28).
```cpp
auto processResult = m_processor->StartProcessing( ... );
// INSERT: if (processResult has error) return outcome::failure(...);  // skip save+hash entirely
```

### Vulkan init/device-creation locking convention
**Source:** `processing_processor_render.cpp:34,36` and `processing_processor_mnn_image.cpp:113` and `vulkan_init_guard.hpp`
**Apply to:** Any NEW Vulkan instance/device/session creation call this phase might add (should be none beyond what `InitializeContext()` already does) — but explicitly NOT to per-job pipeline/buffer/draw work, per RESEARCH.md's Anti-Pattern section.
```cpp
std::lock_guard<std::mutex> lock( sgns::sgprocessing::VulkanInitMutex() );
```

### Enum-class `Error` + `OUTCOME_HPP_DECLARE_ERROR_2` idiom
**Source:** `ProcessingManager.hpp:38-48,166`, `shaders/shader_compiler.hpp:41-45,70`
**Apply to:** D-26's new per-stage render error enum, IF the planner chooses the `outcome::result<>`-based idiom over a plain struct field on `ProcessingResult`.
```cpp
enum class Error { STAGE_A = 1, STAGE_B = 2, /* ... */ };
```
```cpp
OUTCOME_HPP_DECLARE_ERROR_2( sgns::sgprocessing, SomeClass::Error );
```

### Optional-value copy-before-reference-binding pitfall (already fixed once in this file, worth repeating)
**Source:** `ProcessingManager.cpp:956-969` (comment + code)
```cpp
// NOTE: get_render_shader() returns boost::optional<RenderShaderConfig> BY VALUE ...
// binding `stages` as a reference into a chained `.value().get_stages()` call would
// dangle ... Copy the optional into a named local first so its lifetime covers the loop.
const auto                        renderShader = p.get_render_shader().value();
const std::vector<sgns::ShaderStage> &stages    = renderShader.get_stages();
```
Apply the same defensive copy-before-bind pattern anywhere `RenderProcessor`/`ProcessingManager` reads `boost::optional<T>`-returning quicktype accessors for `PipelineState`, `RenderTarget`, `RenderShaderConfig`, uniform maps, etc. — this is a repeat-risk given how many `boost::optional<...>` accessors the Phase 2 generated headers expose (`RenderShaderConfig::get_uniforms()`, `RenderShaderUniform::get_source()`/`get_type()`, `PipelineState`'s four optional fields, etc.).

## No Analog Found

| File/Concern | Role | Data Flow | Reason |
|------|------|-----------|--------|
| Offscreen graphics-pipeline construction (render pass, framebuffer, pipeline, buffers, draw, readback) | processor/GPU-execution | request-response | No other Vulkan graphics-pipeline code exists anywhere in this codebase — MNN's Vulkan usage (`MNN_FORWARD_VULKAN` backend selection) is a black-box library call, not hand-rolled pipeline code. Must be built from RESEARCH.md's Architecture Patterns/Code Examples (Vulkan-spec-derived), not copied from an in-repo analog. |
| `vertex_buffer`/`index_buffer`/uniform `source:` and output `target:` prefix resolution beyond `"input:name"` | dispatch/resolver | CRUD-ish lookup | No generic resolver exists (Pitfall 1) — this is new code regardless of where it's placed (RenderProcessor vs. ProcessingManager); see Pattern Assignments above for the nearest partial precedent (`m_inputMap`/`GetInputIndex`). |
| `data_transform` post-processing executor (RENDER-07) | transform | transform | Zero C++ consumers of `DataTransform`/`DataTransformType` anywhere (Pitfall 9) — genuinely greenfield; RESEARCH.md recommends a no-op-if-absent/error-if-present minimal stance rather than searching for a pattern that doesn't exist. |

## Metadata

**Analog search scope:** `SuperGenius/SGProcessingManager/{include,src,generated}/**` (processors, processingbase, shaders, generated schema headers)
**Files scanned:** `processing_processor_render.hpp/.cpp`, `processing_processor.hpp`, `processing_processor_mnn_image.cpp`, `ProcessingManager.hpp/.cpp`, `vulkan_init_guard.hpp`, `shader_compiler.hpp`, `RenderShaderConfig.hpp`, `RenderTarget.hpp`, `VertexBuffer.hpp`, `PipelineState.hpp`, `RenderShaderUniform.hpp`
**Pattern extraction date:** 2026-07-31
