# Phase 2: Schema Extension & Shader/SPIR-V Validation Pipeline - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-30
**Phase:** 2-Schema Extension & Shader/SPIR-V Validation Pipeline
**Areas discussed:** GLSL→SPIR-V toolchain, Multi-stage shader schema shape, Pipeline-state schema surface, render_target/vertex_layout ergonomics

---

## GLSL→SPIR-V Toolchain

| Option | Description | Selected |
|--------|-------------|----------|
| shaderc (recommended) | Bundles glslang+SPIRV-Tools behind one API, gets spirv-val for free | ✓ (after discussion) |
| Bare glslang + separate SPIRV-Tools | One fewer Khronos-lineage dependency, but more ceremony-heavy embedding, doesn't reduce total vendoring | |
| You decide | Take the research recommendation as final | |
| spirv-only (drop shaderc/glslang, vendor SPIRV-Tools alone) | Seriously considered mid-discussion; smaller binary/no glslang crash surface | |

**User's choice:** shaderc, keeping GLSL support.

**Notes:** User first challenged the premise — asked why compile GLSL at all when `shader_config.type: "spirv"` is already a valid, load-bearing schema value (SHADER-03). Walked through: MoltenVK consumes SPIR-V directly (portable across all 3 target platforms); `spirv-val` is mandatory regardless of this decision (SHADER-02); MNN's own shader pipeline precompiles at build time via a system-installed toolchain and never validates, which doesn't transfer to RenderProcessor's runtime job-supplied-shader model. User then raised that low-end/mobile deployment nodes (explicitly named Orange-Pi-class ARM SBCs) are a real target, prompting a deeper look at shaderc's binary-size cost and glslang's documented crash class on malformed input — both real costs on constrained hardware. User also asked whether iOS would block runtime shader compilation (it wouldn't — not a JIT/executable-memory scenario, no special entitlement needed; also moot since iOS isn't in this milestone's platform list). After weighing all of this, user settled on keeping GLSL support via shaderc — the lower barrier for hand-authored job shaders outweighed the binary-size argument once the crash-surface/portability objections were resolved as non-blocking either way.

Follow-up: user asked whether permissive (non-GPL) libraries exist for both GLSL and HLSL compilation. Answer: shaderc (Apache-2.0) for GLSL; Microsoft's DirectXShaderCompiler/DXC (NCSA license) would be needed for real HLSL support, since glslang's built-in HLSL frontend is documented by Khronos as legacy/incomplete. This would mean vendoring a second toolchain.

| Option | Description | Selected |
|--------|-------------|----------|
| glsl + spirv for v1 (shaderc only); defer hlsl | Vendor shaderc only, hlsl deferred | |
| glsl + hlsl + spirv for v1 (shaderc + DXC) | Vendor both toolchains now | |

**User's choice:** "glsl+spirv, remove metal/hlsl from schema definitions."

**Notes:** User also asked a tangential but important question — whether games' pattern of runtime shader compilation implies precompiled SPIR-V might not work on all hardware. Clarified: SPIR-V is a portable IR, not final GPU machine code; every Vulkan driver compiles SPIR-V→native ISA internally at `vkCreateShaderModule`/pipeline-creation time regardless of whether the SPIR-V arrived precompiled or was produced in-process from GLSL a moment earlier — this is orthogonal to the toolchain decision. Cross-vendor/cross-driver bit-exact output is already out of scope for v1 per REQUIREMENTS.md's DETV-01.

---

## Multi-Stage Shader Schema Shape

| Option | Description | Selected |
|--------|-------------|----------|
| Array of stage entries (recommended) | `stages: [{stage, type, source, entry_point}]`, extensible, per-entry glsl/spirv | ✓ |
| Named fields | `vertex_shader`/`fragment_shader` fields, mirrors current naming, less extensible | |

**User's choice:** Array of stage entries.

**Notes:** No pushback — chosen directly on the first pass.

| Option | Description | Selected |
|--------|-------------|----------|
| Shared across all stages (recommended) | uniforms stays top-level, visible to all stages | ✓ |
| Per-stage uniforms | Each stage entry gets its own uniforms map, more isolated but duplicates shared values | |

**User's choice:** Shared across all stages.

---

## Pipeline-State Schema Surface

| Option | Description | Selected |
|--------|-------------|----------|
| Curated minimal subset (recommended) | topology/cull/winding/depth-test limited to a small useful set | ✓ |
| Full Vulkan enum mirror | All VkPrimitiveTopology/VkCullModeFlags/VkCompareOp values | |

**User's choice:** Curated minimal subset.

| Option | Description | Selected |
|--------|-------------|----------|
| Enable/disable only, fixed 'less' (recommended) | Depth compare_op not configurable | ✓ |
| Expose compare_op as configurable | Adds a depth_compare_op enum field | |

**User's choice:** Enable/disable only, fixed 'less'.

---

## render_target / Vertex Layout Ergonomics

| Option | Description | Selected |
|--------|-------------|----------|
| Sensible defaults, override optional (recommended) | Default RGBA8/D32_SFLOAT/black clear, dimensions still required | |
| All fields explicitly required | No defaults anywhere in render_target | ✓ |

**User's choice:** All fields explicitly required — overrode the recommended default-based option.

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-computed stride (recommended) | vertex_layout {name, format, offset}, stride computed from attribute list | ✓ |
| Explicit stride field required | Job author supplies stride explicitly alongside attributes | |

**User's choice:** Auto-computed stride.

| Option | Description | Selected |
|--------|-------------|----------|
| Schema-configurable (uint16 or uint32) | index_type field, real jobs span both cases | ✓ |
| Fixed to uint32 only for v1 | Simplest, no per-job choice | |

**User's choice:** Schema-configurable.

---

## Claude's Discretion

- Exact JSON field/object naming beyond the shapes locked in CONTEXT.md (e.g. literal name of the stages array, enum string casing)
- Exact `CheckProcessValidity()` error message text for now-schema-invalid `hlsl`/`metal` values or unsupported pipeline-state enum values
- Exact quicktype output class/structure names for new nested types — existing pascal-case/underscore-case conventions apply automatically

## Deferred Ideas

- Real HLSL support via DirectXShaderCompiler (DXC) — deferred, not built this milestone; `hlsl` removed from the schema enum entirely rather than left as a documented-rejected value
- Configurable depth compare_op (reverse-Z, equal-depth tricks) — fixed at `less` instead
- Full Vulkan pipeline-state enum surface (all topology/cull/front-face variants) — scoped down to a curated v1 subset, additive-extensible later
