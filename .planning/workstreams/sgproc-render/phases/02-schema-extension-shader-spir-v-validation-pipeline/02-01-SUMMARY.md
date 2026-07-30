---
phase: 02-schema-extension-shader-spir-v-validation-pipeline
plan: 01
subsystem: infra
tags: [json-schema, quicktype, vulkan, render-pass, shader, spirv]

# Dependency graph
requires:
  - phase: 01-vulkan-foundation-dispatch-plumbing
    provides: PassType::RENDER dispatch plumbing this schema extension eventually feeds
provides:
  - Fixed gnus-processing-schema.json (was invalid JSON) with a full render-pass schema surface: render_target, multi-stage shader pipeline (render_shader/shader_stage), vertex_buffer + vertex_layout, index_buffer, pipeline_state
  - Fully regenerated generated/*.hpp (quicktype v23.2.6, zero hand-edits), including new Pass accessors (get_render_shader/get_render_target/get_vertex_layout/get_vertex_buffer/get_index_buffer/get_pipeline_state)
  - Shared sgns::ShaderSourceType enum (GLSL, SPIRV) consumed by both ShaderConfig::get_type() and ShaderStage::get_type()
affects: [02-03-shader-compiler-spirv-validation, 02-04-processingmanager-wiring]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "New render-only schema properties attached as siblings on pass (render_shader, render_target, vertex_layout, vertex_buffer, index_buffer, pipeline_state) rather than re-typing the shared shader property, since quicktype v23.2.6 cannot produce a discriminated per-pass-type union for the same property name (D-11 Amendment)"

key-files:
  created:
    - SuperGenius/SGProcessingManager/generated/RenderShaderConfig.hpp
    - SuperGenius/SGProcessingManager/generated/ShaderStage.hpp
    - SuperGenius/SGProcessingManager/generated/RenderTarget.hpp
    - SuperGenius/SGProcessingManager/generated/VertexLayoutEntry.hpp
    - SuperGenius/SGProcessingManager/generated/VertexBuffer.hpp
    - SuperGenius/SGProcessingManager/generated/IndexBuffer.hpp
    - SuperGenius/SGProcessingManager/generated/PipelineState.hpp
    - SuperGenius/SGProcessingManager/generated/ShaderSourceType.hpp
    - SuperGenius/SGProcessingManager/generated/RenderShaderUniform.hpp
    - SuperGenius/SGProcessingManager/generated/ShaderUniform.hpp
    - SuperGenius/SGProcessingManager/generated/Stage.hpp
    - SuperGenius/SGProcessingManager/generated/Topology.hpp
    - SuperGenius/SGProcessingManager/generated/CullMode.hpp
    - SuperGenius/SGProcessingManager/generated/FrontFace.hpp
    - SuperGenius/SGProcessingManager/generated/DepthTest.hpp
    - SuperGenius/SGProcessingManager/generated/ColorFormat.hpp
    - SuperGenius/SGProcessingManager/generated/DepthFormat.hpp
    - SuperGenius/SGProcessingManager/generated/VertexLayoutFormat.hpp
    - SuperGenius/SGProcessingManager/generated/IndexType.hpp
  modified:
    - SuperGenius/SGProcessingManager/gnus-processing-schema.json
    - SuperGenius/SGProcessingManager/generated/Pass.hpp
    - SuperGenius/SGProcessingManager/generated/ShaderConfig.hpp
    - SuperGenius/SGProcessingManager/generated/SGNSProcMain.hpp
    - SuperGenius/SGProcessingManager/generated/Generators.hpp
    - SuperGenius/test/src/processing_schema/gnus-processing-schema.json
    - SuperGenius/SGProcessingManager (submodule pointer)
    - SuperGenius (submodule pointer)

key-decisions:
  - "Confirmed via actual quicktype v23.2.6 run: RenderTarget's six fields and VertexBuffer's source are plain (non-boost::optional) members, matching the plan's spike-verified prediction exactly"
  - "generated/ShaderType.hpp and generated/Uniform.hpp deleted as orphaned (superseded by ShaderSourceType.hpp and ShaderUniform.hpp/RenderShaderUniform.hpp) after confirming zero references outside generated/"

patterns-established:
  - "Nested-submodule commit chain: commit inside SGProcessingManager -> bump SGProcessingManager pointer in SuperGenius -> bump SuperGenius pointer in the GeniusNetwork superproject, matching the existing chore(NN-NN): bump <submodule> pointer convention"

requirements-completed: [SCHEMA-01, SCHEMA-02, SCHEMA-03, SCHEMA-04, SCHEMA-05, SHADER-03]

coverage:
  - id: D1
    description: "gnus-processing-schema.json's pre-existing JSON syntax bug (missing/trailing comma in shader_config.type) is fixed, and the file parses as valid JSON"
    requirement: "SCHEMA-05"
    verification:
      - kind: other
        ref: "node -e \"JSON.parse(require('fs').readFileSync('SuperGenius/SGProcessingManager/gnus-processing-schema.json','utf8')); console.log('VALID')\" -> VALID"
        status: pass
    human_judgment: false
  - id: D2
    description: "shader_config.type and the new shader_stage.type both narrow to glsl/spirv only via a shared shader_source_type definition; hlsl/metal are fully removed from the schema"
    requirement: "SHADER-03"
    verification:
      - kind: other
        ref: "grep -c '\"metal\"\\|\"hlsl\"' gnus-processing-schema.json -> 0; grep -c 'shader_source_type' gnus-processing-schema.json -> 3"
        status: pass
    human_judgment: false
  - id: D3
    description: "Render pass schema fully describes render_target (color+depth format, dimensions, clear values, all required), a multi-stage vertex+fragment shader pipeline (render_shader/shader_stage), a vertex_buffer binding + vertex_layout attribute array, an optional index_buffer, and pipeline_state"
    requirement: "SCHEMA-01, SCHEMA-02, SCHEMA-03, SCHEMA-04"
    verification:
      - kind: other
        ref: "grep -c 'render_shader_config\\|render_target\\|vertex_layout_entry\\|vertex_buffer\\|index_buffer\\|pipeline_state' gnus-processing-schema.json -> 17 (>= 14 required)"
        status: pass
    human_judgment: false
  - id: D4
    description: "quicktype regeneration (v23.2.6, identical CI invocation) produces generated/*.hpp with zero hand-edits; Pass.hpp exposes the six new boost::optional accessors; RenderTarget/VertexBuffer's required fields are plain (non-optional) members; orphaned ShaderType.hpp/Uniform.hpp deleted"
    requirement: "SCHEMA-05"
    verification:
      - kind: other
        ref: "grep -c 'boost::optional<RenderShaderConfig> render_shader;' Pass.hpp -> 1; grep -c 'boost::optional<VertexBuffer> vertex_buffer;' Pass.hpp -> 1; grep -c 'class RenderTarget' RenderTarget.hpp -> 1 (plain fields confirmed); grep -c 'class VertexBuffer' VertexBuffer.hpp -> 1 (plain source confirmed); test ! -f ShaderType.hpp && test ! -f Uniform.hpp -> both absent"
        status: pass
    human_judgment: false

duration: 25min
completed: 2026-07-30
status: complete
---

# Phase 2 Plan 1: Schema Extension & Quicktype Regeneration Summary

**Fixed a blocking JSON syntax bug in gnus-processing-schema.json and extended it with a full render-pass schema (render_target, multi-stage vertex+fragment shader pipeline, vertex/index buffer bindings, pipeline state), then fully regenerated the quicktype C++ headers with zero hand-edits.**

## Performance

- **Duration:** ~25 min
- **Tasks:** 2
- **Files modified:** 27 (1 schema, 1 fixture copy, 23 generated headers, 2 submodule pointer bumps)

## Accomplishments
- Fixed the pre-existing, currently-blocking JSON syntax error in `shader_config.type` (missing comma, trailing comma) — the schema now parses as valid JSON
- Narrowed the shader-language enum to `["glsl", "spirv"]` via a new shared `shader_source_type` definition, referenced by both `shader_config.type` (compute) and the new `shader_stage.type` (render) — `hlsl`/`metal` fully removed
- Added `render_shader_config`/`shader_stage` (D-11/D-12 multi-stage vertex+fragment pipeline with shared top-level `uniforms`)
- Added `render_target` (D-15, all six fields required, no schema defaults)
- Added `vertex_layout_entry` + `vertex_buffer` (D-16/D-16 Amendment, one buffer binding feeds every vertex_layout entry) and `index_buffer` (D-17, configurable index_type)
- Added `pipeline_state` (D-13/D-14 curated topology/cull_mode/front_face/depth_test subset, each with a schema default)
- `pass` gained six new optional sibling properties (`render_shader`, `render_target`, `vertex_layout`, `vertex_buffer`, `index_buffer`, `pipeline_state`); `pass.allOf`'s combined compute/render `required: ["shader"]` branch split into two separate branches
- Ran quicktype v23.2.6 with the exact CI invocation from `generate-headers.yml`; regenerated every currently-referenced type's header (`--source-style multi-source` rewrites all of them)
- Deleted orphaned `generated/ShaderType.hpp` and `generated/Uniform.hpp` after confirming zero references to `sgns::ShaderType`/`sgns::Uniform` anywhere outside `generated/`
- Synced the stale test fixture copy at `SuperGenius/test/src/processing_schema/gnus-processing-schema.json` (byte-identical to the source schema after copy)
- Bumped the `SGProcessingManager` submodule pointer in `SuperGenius`, and the `SuperGenius` submodule pointer in the `GeniusNetwork` superproject, so both commits are actually referenced by their parent checkouts

## Task Commits

Each task was committed atomically (nested-submodule chain — SGProcessingManager submodule commits, then pointer bumps up through SuperGenius and the GeniusNetwork superproject):

1. **Task 1: Fix the JSON bug and extend the schema** - `d0f0c80` (SGProcessingManager repo, fix)
2. **Task 2: Regenerate quicktype headers, delete orphaned generated files, sync the test fixture copy** - `97f1b55` (SGProcessingManager repo, feat) + `505d6d79` (SuperGenius repo, chore: sync fixture copy)

**Submodule pointer bumps:**
- `cd5543bf` (SuperGenius repo, chore: bump SGProcessingManager pointer)
- `b563201` (GeniusNetwork superproject, chore: bump SuperGenius pointer)

_Note: No TDD tasks in this plan — both tasks are schema/codegen edits verified by JSON parse + grep + direct header inspection, not unit tests._

## Files Created/Modified
- `SuperGenius/SGProcessingManager/gnus-processing-schema.json` - Bug fix + eight new definitions (`shader_source_type`, `render_shader_config`, `shader_stage`, `render_target`, `vertex_layout_entry`, `vertex_buffer`, `index_buffer`, `pipeline_state`) + six new `pass` properties + split `allOf` conditional
- `SuperGenius/SGProcessingManager/generated/Pass.hpp` - Gains `render_shader`/`render_target`/`vertex_layout`/`vertex_buffer`/`index_buffer`/`pipeline_state` `boost::optional` members + accessors, alongside unchanged `shader`/`model`
- `SuperGenius/SGProcessingManager/generated/RenderTarget.hpp` (new) - All-required plain members: `clear_color`, `clear_depth`, `color_format`, `depth_format`, `height`, `width`
- `SuperGenius/SGProcessingManager/generated/VertexBuffer.hpp` (new) - Plain required `source` member (regex-constrained prefix notation)
- `SuperGenius/SGProcessingManager/generated/RenderShaderConfig.hpp`, `ShaderStage.hpp`, `IndexBuffer.hpp`, `PipelineState.hpp`, `ShaderSourceType.hpp`, `RenderShaderUniform.hpp`, `ShaderUniform.hpp`, `Stage.hpp`, `Topology.hpp`, `CullMode.hpp`, `FrontFace.hpp`, `DepthTest.hpp`, `ColorFormat.hpp`, `DepthFormat.hpp`, `VertexLayoutFormat.hpp`, `IndexType.hpp` (all new) - quicktype-regenerated classes/enums for the new schema shapes
- `SuperGenius/SGProcessingManager/generated/ShaderConfig.hpp` - `type` now `ShaderSourceType` (shared enum) instead of a locally-scoped enum
- `SuperGenius/SGProcessingManager/generated/ShaderType.hpp`, `Uniform.hpp` - **Deleted** (orphaned, superseded)
- `SuperGenius/test/src/processing_schema/gnus-processing-schema.json` - Synced copy, byte-identical to source schema

## Decisions Made
- None beyond what CONTEXT.md/PLAN.md already locked (D-08 through D-17, D-11 Amendment, D-16 Amendment) — this plan's job was mechanical reproduction of the spike-verified schema edit, and the actual quicktype run confirmed every predicted class/enum name and optional-vs-required shape exactly as documented in the plan's `<objective>` and `must_haves`.

## Deviations from Plan

None - plan executed exactly as written. The quicktype regeneration output matched the plan's spike-verified predictions exactly (class names, `boost::optional` vs. plain-member shapes, orphaned-file set).

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- SCHEMA-01 through SCHEMA-05 satisfied: the schema fully describes a render pass's render target, multi-stage shader pipeline, vertex/index buffer bindings, and pipeline state, entirely through quicktype-regenerated headers
- SHADER-03's schema-level half satisfied (`spirv` accepted for `shader_stage.type`); the runtime validation-gate half is plan 02-03/02-04's responsibility
- Plan 02-03 (ShaderCompiler/SPIR-V validation) and 02-04 (ProcessingManager wiring) can now consume `Pass::get_render_shader()`/`get_render_target()`/`get_vertex_layout()`/`get_vertex_buffer()`/`get_index_buffer()`/`get_pipeline_state()` and the shared `sgns::ShaderSourceType` enum exactly as documented in this plan's `key_links`
- No blockers

---
*Phase: 02-schema-extension-shader-spir-v-validation-pipeline*
*Completed: 2026-07-30*

## Self-Check: PASSED

- FOUND: `SuperGenius/SGProcessingManager/gnus-processing-schema.json`
- FOUND: `SuperGenius/SGProcessingManager/generated/RenderTarget.hpp`
- FOUND: `SuperGenius/SGProcessingManager/generated/VertexBuffer.hpp`
- CONFIRMED ABSENT: `SuperGenius/SGProcessingManager/generated/ShaderType.hpp`
- CONFIRMED ABSENT: `SuperGenius/SGProcessingManager/generated/Uniform.hpp`
- FOUND: `SuperGenius/test/src/processing_schema/gnus-processing-schema.json`
- FOUND: commit `d0f0c80` (SGProcessingManager)
- FOUND: commit `97f1b55` (SGProcessingManager)
- FOUND: commit `505d6d79` (SuperGenius)
- FOUND: commit `cd5543bf` (SuperGenius)
- FOUND: commit `b563201` (GeniusNetwork superproject)
