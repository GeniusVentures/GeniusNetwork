# Phase 2: Schema Extension & Shader/SPIR-V Validation Pipeline - Pattern Map

**Mapped:** 2026-07-30
**Files analyzed:** 9 (1 modified schema, 6 regenerated headers, 1 modified C++ source, 2 new components, 1 modified CMake vendoring block)
**Analogs found:** 9 / 9 (all files have an in-repo analog; no external-pattern-only files)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `SuperGenius/SGProcessingManager/gnus-processing-schema.json` (edit: fix syntax bug, split `shader_config`, add `render_shader_config`/`shader_stage`/`render_target`/`vertex_layout`/`index_buffer`/`pipeline_state`) | config (JSON Schema) | transform (schema → quicktype → C++) | same file's existing `pass.allOf`/`if`/`then` block (lines 205-222) and `pass_io_binding` (lines 357-376) | exact (in-file precedent for the exact conditional-schema mechanism and prefix-notation regex needed) |
| `SuperGenius/SGProcessingManager/generated/ShaderType.hpp` (regenerated: enum narrows to `GLSL`/`SPIRV`) | model (quicktype enum) | transform | same file (pre-image) | exact — pure regen, no hand-edit |
| `SuperGenius/SGProcessingManager/generated/RenderShaderConfig.hpp` (new, regenerated) | model (quicktype class) | CRUD (getters/setters over parsed JSON) | `generated/ShaderConfig.hpp` | exact — same shape family (source/type/entry_point/uniforms), extended with a `stages` array |
| `SuperGenius/SGProcessingManager/generated/ShaderStage.hpp` (new, regenerated) | model (quicktype class) | CRUD | `generated/ShaderConfig.hpp` (per-field shape) and `generated/ModelNode.hpp` (small nested object with `oneOf`-free plain fields) | role-match |
| `SuperGenius/SGProcessingManager/generated/RenderTarget.hpp` (new, regenerated) | model (quicktype class, all-required fields) | CRUD | `generated/ModelConfig.hpp` (plain non-optional members for `required` fields — `format`, `input_nodes`, `output_nodes`, `source_uri_param`) | exact — confirms `required` → plain member, no `.value()` |
| `SuperGenius/SGProcessingManager/generated/VertexLayoutEntry.hpp`, `generated/IndexBuffer.hpp`, `generated/PipelineState.hpp` (new, regenerated) | model (quicktype class) | CRUD | `generated/PassIoBinding.hpp` (small object, `ClassMemberConstraints` for regex-pattern fields) | exact for `VertexLayoutEntry`'s buffer-reference field (reuses the `source_constraint`/regex pattern shape verbatim); role-match for `PipelineState` (plain enum fields, no regex) |
| `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` (`CheckProcessValidity()` extended, lines 153-161; `GetCidForProc()`/shader-fetch extended, lines 864-871) | controller/service (validation + fetch orchestration) | request-response (validate) + file-I/O (fetch) | same file, same functions (self-analog — extending an existing `switch`/`case PassType::RENDER` branch and an existing lambda-based fetch) | exact |
| `SuperGenius/SGProcessingManager/include/shaders/shader_compiler.hpp` + `src/shaders/shader_compiler.cpp` (new) | service (compile+validate component, no device dependency) | transform (bytes-in, validated-bytes-out) | `include/processors/processing_processor_render.hpp` + `src/processors/processing_processor_render.cpp` (closest existing "Vulkan-adjacent standalone component with its own outcome-result methods and its own logger," even though `RenderProcessor` itself is device-bound and this component deliberately is not) | role-match (closest available; no existing device-free compute component exists yet in this codebase — flagged in "No Analog Found") |
| `thirdparty/build/CommonTargets.cmake` (add `shaderc` + `SPIRV-Tools`/`SPIRV-Headers` vendoring block) | config (CMake `ExternalProject_Add` vendoring) | batch (one-time build-graph step) | same file's `Vulkan-Headers`/`Vulkan-Loader`/`vk-bootstrap` block (lines 362-405) | role-match (same `ExternalProject_Add` convention, but shaderc needs a hand-written `IMPORTED` target since it has no installed CMake config — see Pitfall 3 in RESEARCH.md; not an exact match because the `find_package(... CONFIG REQUIRED)` half of the pattern does not transfer) |

## Pattern Assignments

### `SuperGenius/SGProcessingManager/gnus-processing-schema.json`

**Analog:** same file, `pass` object (lines 153-223) and `pass_io_binding` (lines 357-376)

**Bug to fix first (lines 334-338, current broken state)** — confirmed via direct read:
```json
"type": {
  "type": "string",
  "default": "glsl"
  "enum": ["glsl", "hlsl", "metal", "spirv"],
},
```
Two syntax errors: missing comma after `"default": "glsl"`; trailing comma after the `enum` array. Fix (also narrows enum per D-10):
```json
"type": {
  "type": "string",
  "default": "glsl",
  "enum": ["glsl", "spirv"]
}
```

**Existing conditional-schema pattern to extend, not replace** (lines 205-222) — this is the exact `if`/`then` shape to nest one level deeper for the `shader_config` vs. `render_shader_config` split (Pattern 3 in RESEARCH.md):
```json
"allOf": [
  {
    "if": { "properties": { "type": { "enum": ["inference", "retrain"] } } },
    "then": { "required": ["model"] }
  },
  {
    "if": { "properties": { "type": { "enum": ["compute", "render"] } } },
    "then": { "required": ["shader"] }
  }
]
```
New nested shape (illustrative — exact key naming is Claude's discretion per CONTEXT.md):
```json
"allOf": [
  { "if": { "properties": { "type": { "enum": ["inference", "retrain"] } } },
    "then": { "required": ["model"] } },
  { "if": { "properties": { "type": { "const": "compute" } } },
    "then": { "properties": { "shader": { "$ref": "#/definitions/shader_config" } }, "required": ["shader"] } },
  { "if": { "properties": { "type": { "const": "render" } } },
    "then": {
      "properties": {
        "shader": { "$ref": "#/definitions/render_shader_config" },
        "render_target": { "$ref": "#/definitions/render_target" },
        "vertex_layout": { "type": "array", "items": { "$ref": "#/definitions/vertex_layout_entry" } },
        "index_buffer": { "$ref": "#/definitions/index_buffer" },
        "pipeline_state": { "$ref": "#/definitions/pipeline_state" }
      },
      "required": ["shader", "render_target"]
    } }
]
```

**Amendment (resolved during plan revision, 2026-07-30 — see 02-CONTEXT.md "D-11 Amendment"):** the nested `allOf[].if.then.properties`-based override of `pass.shader` shown above (redefining the SAME property name per branch) was empirically re-tested against this machine's installed quicktype v23.2.6 and confirmed to silently drop the `shader` property from the generated `Pass` class entirely — quicktype never emits a member for a property declared only inside `allOf[].then.properties`, not at the base `pass.properties` level. A root-level `oneOf`-on-`pass` alternative was also spiked and found worse: it merges both branches into one ambiguous class rather than a discriminated union. The design actually implemented (02-01-PLAN.md) keeps `shader` (property name) compute-only, unchanged, and adds a NEW sibling property `render_shader` (`$ref: render_shader_config`) for the render-only multi-stage shape — same set of new definitions shown above, different property-attachment point. Read 02-CONTEXT.md's "D-11 Amendment" section for the full three-spike empirical record before treating this illustrative code block as the literal implementation shape.

**Prefix-notation pattern to reuse verbatim** (lines 365-369, `pass_io_binding.source`) — for `vertex_layout`/`index_buffer`'s buffer reference (D-16), do not invent a new regex:
```json
"source": {
  "type": "string",
  "description": "Data source using prefix notation",
  "pattern": "^(input|output|internal|parameter):[a-zA-Z][a-zA-Z0-9_]*$"
}
```

**`render_target` shape** (all fields required per D-15 — see Pattern 1 in RESEARCH.md for the confirmed quicktype required→plain-member mapping):
```json
"render_target": {
  "type": "object",
  "required": ["color_format", "depth_format", "width", "height", "clear_color", "clear_depth"],
  "properties": {
    "color_format": { "type": "string", "enum": ["RGBA8", "RGB8"] },
    "depth_format": { "type": "string", "enum": ["D32_SFLOAT", "D24_UNORM_S8_UINT"] },
    "width": { "type": "integer", "minimum": 1 },
    "height": { "type": "integer", "minimum": 1 },
    "clear_color": { "type": "array", "items": { "type": "number" }, "minItems": 4, "maxItems": 4 },
    "clear_depth": { "type": "number", "minimum": 0, "maximum": 1 }
  }
}
```

**`vertex_layout` entry shape** (D-16 — no `stride` field, auto-computed in C++):
```json
"vertex_layout_entry": {
  "type": "object",
  "required": ["name", "format", "offset"],
  "properties": {
    "name":   { "type": "string" },
    "format": { "type": "string", "enum": ["FLOAT32", "FLOAT16", "INT32"] },
    "offset": { "type": "integer", "minimum": 0 }
  }
}
```

**Amendment (resolved during plan revision, 2026-07-30 — see 02-CONTEXT.md "D-16 Amendment"):** `vertex_layout_entry` alone does not name which buffer supplies the attribute data (SCHEMA-02 requires a vertex/index buffer *binding*, not just a layout). A new sibling definition, `vertex_buffer` (`{source: string}`, `source` required, reusing `pass_io_binding`'s exact prefix-notation regex below), is added as a new `pass.vertex_buffer` property — one buffer binding feeds all of a render pass's `vertex_layout` entries, mirroring `index_buffer`'s existing one-buffer-per-binding shape. Empirically re-verified: `generated/VertexBuffer.hpp` regenerates cleanly with a plain (non-optional) required `source` member.

**`render_shader_config`/`shader_stage` shape** (D-11/D-12 — `stages` array, shared top-level `uniforms`):
```json
"render_shader_config": {
  "type": "object",
  "required": ["stages"],
  "properties": {
    "stages": {
      "type": "array",
      "minItems": 1,
      "items": { "$ref": "#/definitions/shader_stage" }
    },
    "uniforms": { "$comment": "identical shape to shader_config.uniforms — reuse the same additionalProperties block" }
  }
},
"shader_stage": {
  "type": "object",
  "required": ["stage", "type", "source"],
  "properties": {
    "stage": { "type": "string", "enum": ["vertex", "fragment"] },
    "type": { "type": "string", "enum": ["glsl", "spirv"], "default": "glsl" },
    "source": { "type": "string" },
    "entry_point": { "type": "string", "default": "main" }
  }
}
```

**`pipeline_state` shape** (D-13/D-14 — curated enums, defaults per Assumption A1/Open Question 3; planner should confirm required-vs-default posture during planning):
```json
"pipeline_state": {
  "type": "object",
  "properties": {
    "topology":   { "type": "string", "enum": ["triangle_list", "line_list", "point_list"], "default": "triangle_list" },
    "cull_mode":  { "type": "string", "enum": ["none", "front", "back"], "default": "back" },
    "front_face": { "type": "string", "enum": ["cw", "ccw"], "default": "ccw" },
    "depth_test": { "type": "string", "enum": ["enabled", "disabled"], "default": "enabled" }
  }
}
```

---

### `generated/*.hpp` (RenderShaderConfig, ShaderStage, RenderTarget, VertexLayoutEntry, IndexBuffer, PipelineState)

**Analog:** `generated/ShaderConfig.hpp`, `generated/ModelConfig.hpp`, `generated/PassIoBinding.hpp` — never hand-edit, only regenerate via the CI command below.

**Regeneration command** (`.github/workflows/generate-headers.yml` lines 27-43 — the only existing regen mechanism; planner should also document a local-dev equivalent per RESEARCH.md's Open Question/recommendation):
```bash
quicktype \
  --src-lang schema \
  --lang cpp \
  --top-level SGNSProcessing \
  --code-format with-getter-setter \
  --const-style west-const \
  --namespace sgns \
  --type-style pascal-case \
  --member-style underscore-case \
  --boost \
  --source-style multi-source \
  --include-location global-include \
  --out generated/SGNSProcMain.hpp \
  gnus-processing-schema.json
```

**Required-field → plain-member confirmation** (`generated/ModelConfig.hpp` lines 44, 45, 48, 49 — no `boost::optional`, no `.value()` needed):
```cpp
ModelFormat format;
std::vector<ModelNode> input_nodes;
std::vector<ModelNode> output_nodes;
std::string source_uri_param;
```
This is the exact shape `RenderTarget.hpp` will take for its all-required fields (D-15) — plain members, `const T & get_X() const`, no crash-prone `.value()` accessor.

**Regex-constrained string field pattern** (`generated/PassIoBinding.hpp` lines 21-24, 29-32, 46) — the shape to expect for `VertexLayoutEntry`'s/`IndexBuffer`'s buffer-reference field if it reuses the `source`/`target` prefix-notation regex:
```cpp
PassIoBinding() :
    source_constraint(boost::none, boost::none, boost::none, boost::none, boost::none, boost::none, std::string("^(input|output|internal|parameter):[a-zA-Z][a-zA-Z0-9_]*$"))
{}
...
boost::optional<std::string> source;
ClassMemberConstraints source_constraint;
...
void set_source(boost::optional<std::string> value) { if (value) CheckConstraint("source", source_constraint, *value); this->source = value; }
```

**Nested-object include pattern** (`generated/Pass.hpp` lines 12-19) — how a new `Pass.hpp` (post-regen) will pull in `RenderTarget.hpp`/`VertexLayoutEntry.hpp`/`PipelineState.hpp`/`RenderShaderConfig.hpp` alongside the existing includes:
```cpp
#include <boost/optional.hpp>
#include <nlohmann/json.hpp>
#include "helper.hpp"

#include "DataTransform.hpp"
#include "PassIoBinding.hpp"
#include "ModelConfig.hpp"
#include "ShaderConfig.hpp"
```

---

### `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp`

**Analog:** self (extending existing functions in place)

**`CheckProcessValidity()` — existing render-pass branch to extend** (lines 153-161):
```cpp
case PassType::RENDER:
{
    if ( !pass.get_shader() )
    {
        m_logger->error( "Render pass has no shader config" );
        return outcome::failure( Error::PROCESS_INFO_MISSING );
    }
    break;
}
```
Extend this exact branch (per RESEARCH.md Pattern 1 / Pitfall 5) to also check presence of `render_target` and any other now-required-for-render fields, following the identical `if (!pass.get_X()) { m_logger->error(...); return outcome::failure(Error::PROCESS_INFO_MISSING); }` shape already used here and at line 176 (`if ( !input.get_dimensions() || !input.get_dimensions()->get_width() )`) for other optional-field presence checks. Add explicit rejection of any residual `hlsl`/`metal` enum values reaching this C++ layer (defense-in-depth per RESEARCH.md's Security Domain section), matching the existing `m_logger->error(...); return outcome::failure(...)` idiom used throughout this function — do not throw/crash.

**`GetCidForProc()` — existing single-shader fetch to extend into a stages-array loop** (lines 864-871):
```cpp
std::string modelFile = [&]() -> std::string {
    const auto &p = processing_.get_passes()[index.value()];
    if ( p.get_type() == PassType::RENDER && p.get_shader() )
    {
        return p.get_shader().value().get_source();
    }
    return p.get_model().value().get_source_uri_param();
}();
```
This lambda fetches ONE shader source URI. Per D-11/Pattern 4 (RESEARCH.md), extend this to iterate `p.get_shader().value().get_stages()`, fetching each stage's `source` via the existing `GetSubCidForProc`/`FileManager` machinery (unchanged, see lines 876-883 for the existing `FileManager::GetInstance().InitializeSingletons()` / `GetSubCidForProc(ioc, url, buffer)` calls this loop should reuse per-stage) before handing each stage's bytes to the new `ShaderCompiler::CompileAndValidate`.

---

### `include/shaders/shader_compiler.hpp` + `src/shaders/shader_compiler.cpp` (new)

**Analog:** `include/processors/processing_processor_render.hpp` + `src/processors/processing_processor_render.cpp` (closest available — device-adjacent standalone component with its own logger and `outcome::result`-style error handling; note this new component must NOT take a `VkInstance`/device dependency, unlike its analog)

**Class-shape pattern to follow** (`processing_processor_render.hpp` lines 1-32 — member-function/private-state layout convention):
```cpp
#pragma once
#include <vulkan/vulkan.h>
#include "processing_processor.hpp"

namespace sgns::sgprocessing
{
    class RenderProcessor : public ProcessingProcessor
    {
    public:
        RenderProcessor() {}
        ~RenderProcessor() override = default;

        ProcessingResult StartProcessing( std::vector<std::vector<uint8_t>> &chunkhashes,
                           const sgns::IoDeclaration         &proc,
                           std::vector<char>                 &imageData,
                           std::vector<char>                 &modelFile,
                           const std::vector<sgns::Parameter> *parameters ) override;

    private:
        bool InitializeContext();
        static bool IsAcceptable( VkPhysicalDeviceType type );
        static VkDeviceSize LargestDeviceLocalHeap( VkPhysicalDevice device );

        VkInstance m_instance{VK_NULL_HANDLE};
        ...
    };
}
```
`ShaderCompiler` should mirror the `#pragma once` + `namespace sgns::sgprocessing` + small-class-with-static-helpers shape, but its constructor/state must hold zero Vulkan handles — see RESEARCH.md's Pattern 4 for the exact suggested signature:
```cpp
struct CompiledStage { std::vector<uint32_t> spirv; std::string stage_name; };
outcome::result<CompiledStage> CompileAndValidate(
    const std::string &source_or_raw_bytes,
    ShaderStageKind stage,      // vertex | fragment
    ShaderType type,            // glsl | spirv  (post-D-10 narrowed enum)
    const std::string &entry_point );
```

**Error-handling convention to match** (`processing_processor_render.cpp` lines 45-50 — `m_logger->error(...)` + early return, no exceptions/crashes on failure path):
```cpp
if ( !inst_ret )
{
    m_logger->error( "RenderProcessor: failed to create Vulkan instance: {}",
                     inst_ret.error().message() );
    return false;
}
```
`ShaderCompiler::CompileAndValidate` should follow the same "log via `m_logger`, return `outcome::failure(...)`, never throw" shape for both the `shaderc::CompileGlslToSpv` failure path and the `spvtools::SpirvTools::Validate()` failure path (RESEARCH.md's Code Examples section has the concrete shaderc/SPIRV-Tools call shapes to wrap in this idiom).

**CMakeLists.txt registration pattern** — new component should follow `src/processors/CMakeLists.txt`'s `add_library(... STATIC ...)` + `target_include_directories`/`target_link_libraries` shape (see Shared Patterns below) rather than being folded into `SGProcessors`, since RESEARCH.md explicitly calls for a standalone, unit-testable, Vulkan-device-free target.

---

### `thirdparty/build/CommonTargets.cmake` (shaderc + SPIRV-Tools vendoring)

**Analog:** same file, `Vulkan-Headers`/`Vulkan-Loader`/`vk-bootstrap` block (lines 362-405) — the exact `ExternalProject_Add` convention already proven for Phase 1's vk-bootstrap vendoring.

**Pattern to follow (with the required deviation flagged):**
```cmake
if(NOT ANDROID)
    # Vulkan-Headers
    ExternalProject_Add(
        Vulkan-Headers
        PREFIX Vulkan-Headers
        SOURCE_DIR "${THIRDPARTY_DIR}/Vulkan-Headers"
           CMAKE_CACHE_ARGS
        -DCMAKE_INSTALL_PREFIX:PATH=${CMAKE_CURRENT_BINARY_DIR}/Vulkan-Loader
        ${_CMAKE_COMMON_CACHE_ARGS}
    )
    ...
    # vk-bootstrap
    ExternalProject_Add(
        vk-bootstrap
        PREFIX vk-bootstrap
        SOURCE_DIR "${THIRDPARTY_DIR}/vk-bootstrap"
           CMAKE_CACHE_ARGS
        -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
        -DVulkanHeaders_DIR:PATH=${CMAKE_CURRENT_BINARY_DIR}/Vulkan-Loader/share/cmake/VulkanHeaders
        -DVK_BOOTSTRAP_TEST:BOOL=OFF
        ${_CMAKE_COMMON_CACHE_ARGS}
        DEPENDS Vulkan-Headers
    )
endif()
```
**Deviation required for shaderc (RESEARCH.md Pitfall 3):** shaderc installs no CMake package config, so the `vk-bootstrap` block's implicit downstream `find_package(vk-bootstrap CONFIG REQUIRED)` half of the pattern does NOT transfer. Use `ExternalProject_Add` for the fetch/build/install step (same convention) but follow with a hand-written `IMPORTED` target, per RESEARCH.md's illustrative CMake block:
```cmake
ExternalProject_Add(
    shaderc
    PREFIX shaderc
    SOURCE_DIR "${THIRDPARTY_DIR}/shaderc"
    CMAKE_CACHE_ARGS
        -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
        -DSHADERC_SKIP_TESTS:BOOL=ON
        -DSHADERC_SKIP_EXAMPLES:BOOL=ON
        -DSHADERC_SKIP_COPYRIGHT_CHECK:BOOL=ON
        -DSHADERC_ENABLE_HLSL:BOOL=OFF
        -DSHADERC_ENABLE_WGSL_OUTPUT:BOOL=OFF
    ${_CMAKE_COMMON_CACHE_ARGS}
)
add_library(shaderc::shaderc STATIC IMPORTED)
set_target_properties(shaderc::shaderc PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_BINARY_DIR}/shaderc/lib/libshaderc_combined.a"  # path TBD, spike
    INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_BINARY_DIR}/shaderc/include"
)
```
SPIRV-Tools should be vendored as its own separate `ExternalProject_Add` block (same convention, pinned to shaderc's `DEPS`-referenced commit) so `spvtools::SpirvTools::Validate()` is directly linkable — see RESEARCH.md Pitfall 2/4 for why reaching into shaderc's internal build tree is explicitly not recommended.

## Shared Patterns

### Error handling (outcome::result + logger, never throw/crash)
**Source:** `src/processingbase/ProcessingManager.cpp` (`CheckProcessValidity`, lines 133-168) and `src/processors/processing_processor_render.cpp` (lines 45-50)
**Apply to:** `CheckProcessValidity()` extension, `GetCidForProc()` extension, and the new `ShaderCompiler` component
```cpp
if ( !pass.get_shader() )
{
    m_logger->error( "Render pass has no shader config" );
    return outcome::failure( Error::PROCESS_INFO_MISSING );
}
```
Every new validation/compile/validate failure path in this phase should follow this exact "log via `m_logger`, return `outcome::failure(Error::...)`" idiom — no exceptions, no crashes on malformed/untrusted input (this is the load-bearing convention RESEARCH.md's Pitfall 5 and Security Domain section both point back to).

### Conditional JSON Schema composition (`allOf`/`if`/`then`)
**Source:** `gnus-processing-schema.json:205-222` (`pass.allOf` block)
**Apply to:** the new `shader_config` vs. `render_shader_config` split, and the render-only `render_target`/`vertex_layout`/`pipeline_state` field additions
```json
"allOf": [
  { "if": { "properties": { "type": { "enum": ["inference", "retrain"] } } },
    "then": { "required": ["model"] } },
  { "if": { "properties": { "type": { "enum": ["compute", "render"] } } },
    "then": { "required": ["shader"] } }
]
```

### Prefix-notation buffer reference (`source:`/`target:`)
**Source:** `gnus-processing-schema.json:365-373` (`pass_io_binding`)
**Apply to:** `vertex_layout`/`index_buffer`'s buffer-reference field (D-16) — reuse verbatim, do not invent a new pattern
```json
"pattern": "^(input|output|internal|parameter):[a-zA-Z][a-zA-Z0-9_]*$"
```

### quicktype required-field → plain-member mapping (no `.value()` crash risk)
**Source:** `generated/ModelConfig.hpp` (lines 42-49)
**Apply to:** `RenderTarget` (all-required per D-15) and any other new object where planner locks fields as `required`
```cpp
ModelFormat format;                    // required → plain member, not boost::optional
std::vector<ModelNode> input_nodes;    // required → plain member
```

### CMake `ExternalProject_Add` vendoring convention
**Source:** `thirdparty/build/CommonTargets.cmake:362-405` (Vulkan-Headers/Vulkan-Loader/vk-bootstrap block)
**Apply to:** shaderc, SPIRV-Tools, SPIRV-Headers vendoring — same `ExternalProject_Add(... PREFIX ... SOURCE_DIR "${THIRDPARTY_DIR}/..." CMAKE_CACHE_ARGS ... ${_CMAKE_COMMON_CACHE_ARGS} DEPENDS ...)` shape, with the shaderc-specific deviation (hand-written `IMPORTED` target, no `find_package(... CONFIG REQUIRED)`) noted above.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `include/shaders/shader_compiler.hpp` / `src/shaders/shader_compiler.cpp` | service | transform | No existing Vulkan-device-free CPU-side compile/validate component exists in this codebase yet — `RenderProcessor` is the closest analog for logging/error-handling/namespace conventions, but it is device-bound (`VkInstance`/`VkDevice` member state) where this new component must deliberately have none. Planner should treat RESEARCH.md's Pattern 4 (`ShaderCompiler`/`CompileAndValidate` shape) and Code Examples (shaderc + SPIRV-Tools call shapes) as the primary source for this file's internals, using `processing_processor_render`'s file/namespace/logging conventions only for the surrounding scaffolding. |

## Metadata

**Analog search scope:** `SuperGenius/SGProcessingManager/` (schema, `generated/`, `src/processingbase/`, `src/processors/`, `include/processors/`, CMakeLists.txt files), `thirdparty/build/CommonTargets.cmake`
**Files scanned:** 13 read directly (schema JSON, 4 generated headers, ProcessingManager.cpp x2 ranges, processing_processor_render.hpp/.cpp, 2 CMakeLists.txt, CommonTargets.cmake, generate-headers.yml) + 1 phase-2 CONTEXT.md + 1 phase-2 RESEARCH.md
**Pattern extraction date:** 2026-07-30
