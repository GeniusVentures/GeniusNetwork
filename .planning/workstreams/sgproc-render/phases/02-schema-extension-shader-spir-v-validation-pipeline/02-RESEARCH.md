# Phase 2: Schema Extension & Shader/SPIR-V Validation Pipeline - Research

**Researched:** 2026-07-30
**Domain:** JSON Schema (draft-07) extension for a hand-rolled Vulkan render pass + in-process GLSL→SPIR-V compilation (shaderc) + mandatory SPIR-V validation (SPIRV-Tools) inside SGProcessingManager
**Confidence:** HIGH for repo-grounded findings (direct file reads, including one confirmed blocking bug); MEDIUM for shaderc/SPIRV-Tools API and CMake-integration findings (cross-checked WebSearch/WebFetch against official `google/shaderc`/`KhronosGroup/SPIRV-Tools` GitHub sources, Context7 MCP tool unavailable in this session so no HIGH-tier docs-provider fetch was possible)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**GLSL→SPIR-V Toolchain**
- **D-08:** shaderc is the vendored toolchain (bundles glslang for GLSL parsing/codegen + SPIRV-Tools for `spirv-val`/optimization behind one coherent Apache-2.0 dependency). Re-derived from first principles during discussion (not taken on faith): user first challenged whether GLSL compilation was needed at all (given `shader_config.type: "spirv"` already exists), weighed binary-size/crash-surface trade-offs for low-end/mobile deployment (Orange-Pi-class ARM SBCs explicitly named), then settled on keeping `glsl` support via shaderc rather than going spirv-only. Key rationale points: MoltenVK consumes SPIR-V directly (spirv-only would be portable across the milestone's actual v1 targets — Windows/Linux/macOS-MoltenVK — but that wasn't decisive); `spirv-val` is mandatory regardless of this toolchain choice (orthogonal, not a reason to pick a side); MNN's own precompiled-shader pipeline bakes SPIR-V at MNN's own build time via a system `glslangValidator`, never validates with `spirv-val`, and doesn't transfer to `RenderProcessor`'s untrusted runtime job-supplied shaders; iOS runtime code-gen restrictions do NOT block glslang/shaderc (GLSL→SPIR-V is CPU-side text-to-bytecode, not JIT machine code); final call: lower barrier for hand-authored job shaders (text vs. requiring every job author to run a local SPIR-V toolchain) outweighed the binary-size argument.
- **D-09:** Real HLSL support explicitly rejected for v1 — glslang's built-in HLSL frontend is Khronos-documented legacy/incomplete; proper HLSL would require vendoring Microsoft's DXC (NCSA license) as a second toolchain, reopening the "minimize libraries" goal. Scoped out.
- **D-10:** `shader_config.type` schema enum narrows to **`["glsl", "spirv"]`** only. `metal` removed entirely (MoltenVK translates SPIR-V→MSL internally; a job never submits MSL directly — this value was always dead). `hlsl` also removed entirely (not merely deferred-with-rejection-error) — no DXC vendoring in v1, no schema-enum trace of an unimplemented language.

**Multi-Stage Shader Schema Shape**
- **D-11:** `shader_config` gains a **`stages` array**: `[{stage: "vertex"|"fragment", type, source, entry_point}, ...]`, replacing the single top-level `source`/`type`/`entry_point` fields **for render passes only** (compute passes, out of scope this milestone, are unaffected — their `shader_config` shape stays as-is). Each stage entry independently declares `glsl` or `spirv` as its `type` — a render pass could in principle mix a GLSL vertex shader with a directly-submitted SPIR-V fragment shader. Array shape (not named `vertex_shader`/`fragment_shader` fields) chosen for extensibility to future stages (geometry/tessellation) without another schema break — no such stages needed for v1.
- **D-12:** `uniforms` stays a **single shared map at the top level** of `shader_config`, visible to every stage — not per-stage-entry. Matches how MVP-matrix-style uniforms are actually used (same value needed in both vertex and fragment stages) and avoids duplicated bookkeeping ahead of Phase 3's RENDER-05 push-constant work.

**Pipeline State Schema Surface**
- **D-13:** Curated minimal v1 subset, not a full Vulkan enum mirror: `topology` ∈ {`triangle_list`, `line_list`, `point_list`}; `cull_mode` ∈ {`none`, `front`, `back`}; `front_face`/winding ∈ {`cw`, `ccw`}; `depth_test` ∈ {`enabled`, `disabled`}. Covers RENDER-04's stated scope without over-building; extend the enum later (non-breaking addition) if strip/fan topologies or `front_and_back` culling are ever needed.
- **D-14:** Depth comparison is **fixed at `less`**, not schema-configurable — no `depth_compare_op` field. Matches DETV-02's determinism-guard framing (fixed, predictable pipeline behavior); no current requirement calls for reverse-Z or other compare-op tricks.

**render_target / Vertex Layout Ergonomics**
- **D-15:** **All `render_target` fields are explicitly required** in the job definition — color format, depth format, dimensions, and clear values. No schema defaults. (Deliberate override of the initial recommendation toward defaults — user chose explicitness over lower per-job boilerplate.)
- **D-16:** `vertex_layout` is a small array of `{name, format, offset}` entries, reusing the existing `pass_io_binding` `source:`/`target:` prefix-notation convention as the reference mechanism for *which* buffer feeds the binding (no new binding DSL invented). **Stride is auto-computed** from the tightly-packed sum of attribute sizes/offsets, not an explicit required field — removes a field and a class of job-author error (explicit stride disagreeing with actual attribute layout).
- **D-17:** Index buffer type (`uint16`/`uint32`) is **schema-configurable** per render pass via a field on the vertex/index binding — real jobs will span both small meshes (uint16) and large meshes (uint32, needed past 65535 vertices).

### Claude's Discretion
- Exact JSON field/object naming beyond what's specified above (e.g. whether the array is literally named `stages`, exact enum string casing) — as long as the shapes in D-08 through D-17 are honored.
- Exact `CheckProcessValidity()` error message text for a render pass presenting `hlsl`/`metal` (now schema-invalid, fails generic schema validation before reaching render-specific C++ code) or an unsupported pipeline-state enum value.
- Exact quicktype output structure/class names for the new nested types (`RenderTarget`, `VertexLayoutEntry`, `PipelineState`, `ShaderStage` or equivalent) — quicktype's existing pascal-case/underscore-case conventions apply automatically; no new convention decision needed.

### Deferred Ideas (OUT OF SCOPE)
- **Real HLSL support via DirectXShaderCompiler (DXC)** — considered (D-09), explicitly deferred. `hlsl` removed from the schema enum entirely; revisit (re-add to enum + vendor DXC) if HLSL demand materializes in a future milestone.
- **Configurable depth compare_op** (reverse-Z, equal-depth tricks) — considered (D-14), fixed at `less` instead. Revisit if a future render pass genuinely needs it.
- **Full Vulkan pipeline-state enum surface** (all topology/cull/front-face variants) — scoped down to the curated v1 subset (D-13). Additive-extensible, not blocked, just not built until a concrete need appears.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SCHEMA-01 | Render pass schema defines a render-target/framebuffer config (color+depth attachment formats/dimensions/clear values) | See Architecture Patterns → Pattern 1 (render_target shape, all-fields-required per D-15, confirmed maps cleanly to quicktype non-optional plain members) |
| SCHEMA-02 | Render pass schema defines vertex/index buffer bindings + layout | See Architecture Patterns → Pattern 2 (`vertex_layout` reusing `pass_io_binding` prefix convention, auto-computed stride, configurable index type) |
| SCHEMA-03 | Render pass schema supports a multi-stage shader pipeline (vertex+fragment), replacing the single `shader_config` for render passes | See Architecture Patterns → Pattern 3 (two-shape `shader_config` split via `if`/`then`, critical schema-modeling finding — `shader_config` is shared with `compute` today) |
| SCHEMA-04 | Render pass schema defines pipeline state (topology, cull mode, winding order, depth-test) configurable via schema | See Architecture Patterns → Pattern 1 (`pipeline_state` object, curated enums per D-13/D-14) |
| SCHEMA-05 | quicktype-generated headers regenerated from the extended schema (`generated/` never hand-edited) | See Common Pitfalls → Pitfall 1 (blocking JSON syntax error must be fixed before ANY regeneration can succeed) and Architecture Patterns → local quicktype invocation recommendation |
| SHADER-01 | GLSL shader source compiled to SPIR-V in-process via vendored shaderc, at job-load time, before any GPU call | See Standard Stack (shaderc API/vendoring) and Architecture Patterns → Pattern 4 (`ShaderCompiler` component boundary — no VkInstance needed) |
| SHADER-02 | All SPIR-V reaching `vkCreateShaderModule` passes a mandatory `spirv-val` gate | See Common Pitfalls → Pitfall 2 (shaderc does NOT run spirv-val internally — critical correction to workstream-level research) and Code Examples (SPIRV-Tools `Validate` API) |
| SHADER-03 | `shader_config.type: "spirv"` explicitly accepted for render passes, subject to SHADER-02's gate | See Architecture Patterns → Pattern 3/4 (both `glsl` and `spirv` stage types flow through the same validation gate before reaching the byte buffer RenderProcessor will consume in Phase 3) |
</phase_requirements>

## Summary

This phase is pure schema + validation-pipeline work — no `VkInstance`, no pipeline, no draw calls (those are Phase 3). Two things dominate the research: (1) a **confirmed, currently-blocking JSON syntax error** in `gnus-processing-schema.json`'s `shader_config.type` block that makes the schema file invalid JSON *today*, which must be the literal first fix in this phase before any other schema edit or quicktype regeneration can be attempted; and (2) a load-bearing correction to the workstream-level research's framing of shaderc "getting `spirv-val` for free" — **shaderc's public `CompileGlslToSpv` API does not invoke SPIR-V validation internally**; it only runs glslang's codegen. SPIRV-Tools' own validator (`spvtools::SpirvTools::Validate` / C API `spvValidateBinary`) must be invoked as an explicit, separate step, which in turn means SPIRV-Tools needs to be reachable as a directly-linkable dependency (either shaderc's internal build-tree copy, reached by path — fragile — or a second, version-pinned top-level vendoring, matching this project's existing per-library `ExternalProject_Add` convention). A second load-bearing finding: **shaderc does not install a CMake package config** for `find_package(shaderc CONFIG REQUIRED)` the way vk-bootstrap/Vulkan-Headers/Vulkan-Loader do (confirmed via multiple upstream issues) — the vendoring plan needs a different CMake integration shape than the pattern Phase 1 already established for vk-bootstrap.

On the schema side, the critical modeling finding is that `shader_config` is **currently shared, unmodified, between `compute` and `render` pass types** via the existing `pass.allOf`/`if`/`then` block — but D-11 only changes the shape for render passes. This requires splitting `shader_config` into two distinct schema shapes (existing single-source shape for `compute`, new `stages`-array shape for `render`), using the exact same `if`/`then` conditional-schema pattern already present in this file (lines 205-222) one level deeper. Everything else — `render_target` (all-required fields per D-15), `vertex_layout` (reusing `pass_io_binding`'s prefix convention), and `pipeline_state` (curated enums) — is straightforward JSON Schema `object`/`array` modeling with no novel pattern needed, and (confirmed via direct read of `ModelConfig.hpp`) required fields already map cleanly to plain (non-`boost::optional`) quicktype members, meaning D-15's all-required-fields choice sidesteps the `.value()`-crash pattern class (Pitfall 8 from workstream PITFALLS.md) by construction.

**Primary recommendation:** Fix the JSON syntax bug first (one-line change, blocks everything else). Split `shader_config` into `shader_config` (compute, unchanged shape, narrowed `type` enum) and a new `render_shader_config` (render, `stages` array) via a nested `if`/`then` inside the existing pass-level conditional. Vendor shaderc via `ExternalProject_Add` + a hand-written `IMPORTED` CMake target (no upstream config file exists); vendor SPIRV-Tools as its own explicit, version-pinned dependency (pin to shaderc's own `DEPS`-referenced commit to avoid SPIR-V dialect skew) so its C++ `Validate()` API is directly linkable. Build a standalone `ShaderCompiler`/`ShaderValidator` component with zero Vulkan-device dependency, unit-testable in isolation, that Phase 3's `RenderProcessor` will call before `vkCreateShaderModule`.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Schema definition (`gnus-processing-schema.json`) | Backend / Data Contract | — | Pure JSON Schema — no runtime tier, consumed by both the CI header-generation step and (indirectly) by every C++ consumer of `generated/` |
| quicktype-generated C++ types (`generated/*.hpp`) | Backend / API | — | Compile-time data contract for `ProcessingManager` and `RenderProcessor`; never hand-edited |
| GLSL→SPIR-V compilation (shaderc) | Backend / Compute (CPU-side, in-process) | — | Pure CPU text-to-bytecode transform; explicitly NOT GPU/driver-tier work — no `VkInstance` involved despite operating on GPU-bound bytecode |
| SPIR-V validation (SPIRV-Tools `spirv-val`) | Backend / Compute (CPU-side, in-process) | Security/Input-Validation | Gatekeeper between untrusted job input and the GPU driver — logically a security-boundary component, physically colocated with the compiler since both operate on the same in-memory byte buffers before any Vulkan call |
| Schema validation (`CheckProcessValidity()`) | Backend / Data Contract | — | Existing `ProcessingManager` responsibility, extended (not replaced) this phase |
| Job-shader fetch (`GetCidForProc`) | Backend / Data Contract | — | Existing `FileManager`/CID-fetch machinery, extended to loop over the new `stages` array instead of a single shader source |
| `RenderProcessor`'s eventual `vkCreateShaderModule` call | GPU / Driver (Phase 3, not this phase) | — | Explicitly out of scope this phase — this phase only guarantees the bytes handed to Phase 3 are already validated |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| **shaderc** | `v2024.3` tag (pinned per workstream STACK.md to stay on the Vulkan-1.3-targeting release line, matching this repo's pinned Vulkan-Headers/Loader `~1.3.302`; `v2024.4`+ shifted default targeting to Vulkan 1.4) `[CITED: github.com/google/shaderc]` | In-process GLSL→SPIR-V compilation via `shaderc::Compiler::CompileGlslToSpv` | Purpose-built embeddable compiler for exactly "compile this untrusted GLSL string, get back SPIR-V bytes or a structured error" — locked by D-08 |
| **SPIRV-Tools** | Pin to the exact commit shaderc's own `DEPS` file references for its bundled copy — confirmed as commit `a665e21f3061f34064b39937cf00fe8d8769f4ef` at time of this research `[CITED: raw.githubusercontent.com/google/shaderc/main/DEPS]` — to avoid SPIR-V-dialect skew between what shaderc emits and what the validator checks | Vendored as its **own, separately-linkable** dependency (not merely relied upon as shaderc's internal, non-exported build artifact) so `spvtools::SpirvTools::Validate()` is a directly-callable C++ API — see Common Pitfalls → Pitfall 2 for why this is required, not optional | `spirv-val` (SHADER-02's mandatory gate) is NOT invoked by shaderc's public API; the validator must be reachable as its own target |
| **glslang** | Not vendored as a top-level dependency — arrives transitively as shaderc's nested `third_party/glslang` submodule, built as part of shaderc's own `ExternalProject_Add` step | GLSL parsing/codegen backend used internally by shaderc | Never touched directly by this project's code — shaderc's C++ API is the only surface this project calls |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| **SPIRV-Headers** | Pin to shaderc's `DEPS`-referenced commit `29981f65241605e08b0ede4cfeb999fe3b723c6a` `[CITED: raw.githubusercontent.com/google/shaderc/main/DEPS]` | Required nested dependency of a standalone SPIRV-Tools build (`SPIRV-Tools` CMake config expects `spirv-headers` to already be configured — confirmed via `shaderc/third_party/CMakeLists.txt`'s own handling pattern) | Needed if SPIRV-Tools is vendored as its own top-level submodule (recommended path) |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Vendoring SPIRV-Tools separately (own submodule) | Reach into shaderc's internal build tree (`<shaderc-build-dir>/third_party/spirv-tools/...`) for the `SPIRV-Tools-static`/`SPIRV-Tools-opt` artifacts shaderc's own build already produces | Avoids a second copy of the same library, but reaches into a non-stable internal build-tree path that shaderc's own CMake does not export as a public target — brittle across shaderc version bumps. **Not recommended.** |
| shaderc for GLSL→SPIR-V | bare glslang (`glslang::TShader`/`TProgram`) | Locked by D-08 as rejected — more ceremony-heavy embedding surface, no built-in structured error/warning string, and doesn't avoid needing SPIRV-Tools separately anyway (see above) since validation is mandatory regardless |

**Installation:**
```bash
# Nested submodule init for shaderc's own build (glslang + its own copy of spirv-tools/spirv-headers)
git submodule add https://github.com/google/shaderc.git thirdparty/shaderc
cd thirdparty/shaderc && git submodule update --init --recursive

# Separate, explicit SPIRV-Tools vendoring for the directly-linkable Validate() API
git submodule add https://github.com/KhronosGroup/SPIRV-Tools.git thirdparty/SPIRV-Tools
git submodule add https://github.com/KhronosGroup/SPIRV-Headers.git thirdparty/SPIRV-Tools/external/spirv-headers
```

**Version verification:** `npm view`/`pip index versions`/`cargo search` do not apply — these are C++ libraries consumed as git submodules, not registry packages. Verified instead via direct `DEPS`-file/README inspection of the official `google/shaderc` and `KhronosGroup/SPIRV-Tools` GitHub repositories (see Sources). No local registry command exists to double-check "currency" the way `npm view` does for npm; treat the pinned commit hashes above as the verified-current snapshot as of this research date (2026-07-30) and re-confirm against `shaderc/DEPS` if planning happens materially later.

## Package Legitimacy Audit

> This phase's only new external dependencies (shaderc, SPIRV-Tools, SPIRV-Headers, glslang-transitively) are **C++ libraries vendored as git submodules**, not npm/PyPI/crates registry packages. The `gsd-tools query package-legitimacy check --ecosystem npm shaderc` command was run as a sanity probe; it returned a match against an unrelated npm placeholder package (`npm/security-holder`, 6 weekly downloads, verdict `SUS`) — **this is a false-positive cross-ecosystem name collision, not the actual dependency**, confirming the npm/PyPI/crates legitimacy gate does not apply to this phase's vendoring model. Manual provenance verification was performed instead, against the same standard the gate encodes (official org, license, activity, source-repo presence):

| Package | Registry | Age | Activity/Stars | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------------|-------------|---------|-------------|
| shaderc | git submodule (not a package registry) | Est. 2015+, actively maintained by Google `[CITED: github.com/google/shaderc]` | Official Google org repo, widely used (Android NDK ships it) `[CITED: developer.android.com/ndk/guides/graphics/shader-compilers]` | github.com/google/shaderc | OK (manual verification — official org, Apache-2.0, already locked by D-08) | Approved |
| SPIRV-Tools | git submodule | Est. 2015+, actively maintained by Khronos Group | Official Khronos org repo, canonical validator/optimizer for the Vulkan ecosystem | github.com/KhronosGroup/SPIRV-Tools | OK (manual verification — official Khronos org, Apache-2.0) | Approved |
| SPIRV-Headers | git submodule | Est. 2016+, actively maintained by Khronos Group | Official Khronos org repo, required transitive dependency of SPIRV-Tools | github.com/KhronosGroup/SPIRV-Headers | OK (manual verification — official Khronos org, permissive MIT-style license) | Approved |
| glslang | Not a top-level vendoring decision this phase (arrives transitively inside shaderc's own submodule tree) | N/A this phase | N/A this phase | Nested inside `thirdparty/shaderc/third_party/glslang` | N/A — not independently vendored by this project's `.gitmodules` | N/A |

**Packages removed due to `[SLOP]` verdict:** none.
**Packages flagged as suspicious `[SUS]`:** none of the actual C++ dependencies — the only `SUS` verdict returned was the unrelated npm cross-ecosystem false positive described above, which is not this phase's dependency and requires no `checkpoint:human-verify` gate.

*Package-name provenance note: shaderc/SPIRV-Tools/SPIRV-Headers were identified via the workstream-level STACK.md research and confirmed against official GitHub organizations (`google`, `KhronosGroup`) directly in this session via WebFetch/WebSearch — tagged `[CITED]`, not `[VERIFIED]`, per this project's provenance rule (no `npm view`-equivalent registry command exists for git-submodule C++ deps; the closest available legitimacy gate is npm/PyPI/crates-shaped and does not apply here). The planner should still add a lightweight `checkpoint:human-verify` before the actual `git submodule add` commands run, consistent with treating any new external code source with appropriate caution, even though the org/repo identity is well-established.*

## Architecture Patterns

### System Architecture Diagram

```
gnus-processing-schema.json (edited this phase)
    │
    ├─ pass.allOf[if type∈{compute,render}].then.required: ["shader"]   (existing, unchanged)
    │
    ├─ pass.shader → NEW nested if/then:
    │     if pass.type == "compute"  → $ref shader_config          (existing shape, type enum narrowed)
    │     if pass.type == "render"   → $ref render_shader_config   (NEW: stages[] array)
    │
    ├─ pass.render_target (NEW, render-only, all fields required)   ── SCHEMA-01
    ├─ pass.vertex_layout / pass.index_buffer (NEW, render-only)    ── SCHEMA-02
    └─ pass.pipeline_state (NEW, render-only, curated enums)        ── SCHEMA-04
            │
            ▼  (CI push to main, or local dev invocation)
    quicktype --src-lang schema --lang cpp ... gnus-processing-schema.json
            │
            ▼
    generated/{Pass,RenderShaderConfig,ShaderStage,RenderTarget,VertexLayoutEntry,PipelineState}.hpp
            │
            ▼
ProcessingManager::CheckProcessValidity()  — extended: validate new render fields present,
    reject hlsl/metal at the C++ layer too (defense-in-depth against a hand-edited schema)
            │
            ▼
ProcessingManager::GetCidForProc()  — extended: loop over shader.stages[], fetch each stage's
    source bytes via existing FileManager/CID machinery (cpp:864-871 today fetches ONE shader)
            │
            ▼
NEW: ShaderCompiler component (no VkInstance — pure CPU, unit-testable in isolation)
    for each stage:
        if stage.type == "glsl"  → shaderc::Compiler::CompileGlslToSpv(source, kind, ...)
                                     → on failure: clean job-rejection error (SHADER-01)
        if stage.type == "spirv" → bytes used as-is (SHADER-03 accept-path)
        ALWAYS: spvtools::SpirvTools::Validate(spirv_bytes)     ← MANDATORY, both paths (SHADER-02)
                                     → on failure: clean job-rejection error, NEVER reaches
                                       vkCreateShaderModule
            │
            ▼ (validated SPIR-V byte buffers, one per stage)
   [Phase 3: RenderProcessor::StartProcessing — vkCreateShaderModule, pipeline, draw, readback]
```

### Recommended Project Structure
```
SGProcessingManager/
├── gnus-processing-schema.json          # this phase: shader_config split, render_target,
│                                        #   vertex_layout, pipeline_state additions
├── generated/                           # regenerate via quicktype — NEVER hand-edit
│   ├── ShaderType.hpp                   # enum narrows to {GLSL, SPIRV}
│   ├── RenderShaderConfig.hpp           # NEW — stages[] + uniforms
│   ├── ShaderStage.hpp                  # NEW — {stage, type, source, entry_point}
│   ├── RenderTarget.hpp                 # NEW — all-required fields (plain members, no .value())
│   ├── VertexLayoutEntry.hpp            # NEW — {name, format, offset}
│   └── PipelineState.hpp                # NEW — curated topology/cull_mode/front_face/depth_test
├── include/shaders/                     # NEW subfolder — shader compile+validate component
│   └── shader_compiler.hpp              # ShaderCompiler class, no Vulkan-device dependency
├── src/shaders/
│   └── shader_compiler.cpp              # shaderc + SPIRV-Tools calls live here, unit-testable
├── src/processingbase/
│   └── ProcessingManager.cpp            # CheckProcessValidity() + GetCidForProc() extended
└── src/processors/
    └── processing_processor_render.cpp  # UNCHANGED this phase (Phase 3 wires ShaderCompiler in)
```

### Pattern 1: `render_target` and `pipeline_state` — plain object/enum additions, no novel schema shape

**What:** Two new sibling objects on `pass`, scoped to `type: render` only via the existing `allOf`/`if`/`then` block (extend the existing `then.required` array, don't replace it).
**When to use:** Directly implements SCHEMA-01/SCHEMA-04.
**Confirmed quotitype behavior (direct read of `ModelConfig.hpp`):** JSON-Schema `required` fields become **plain, non-`boost::optional` members** with `get_X()`/`get_mutable_X()`/`set_X()` accessors — no `.value()` call needed, no crash risk. This directly confirms D-15's "all `render_target` fields required" choice sidesteps the exact `.value()`-on-unchecked-optional crash class documented as Pitfall 8 in the workstream's own PITFALLS.md, for this object specifically.
**Example schema addition (illustrative — exact key names are Claude's discretion per CONTEXT.md):**
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
},
"pipeline_state": {
  "type": "object",
  "properties": {
    "topology":   { "type": "string", "enum": ["triangle_list", "line_list", "point_list"] },
    "cull_mode":  { "type": "string", "enum": ["none", "front", "back"] },
    "front_face": { "type": "string", "enum": ["cw", "ccw"] },
    "depth_test": { "type": "string", "enum": ["enabled", "disabled"] }
  }
}
```
`[ASSUMED]` — the exact required-vs-optional split for `pipeline_state`'s own fields (all four required vs. having sensible schema-level defaults) was not explicitly locked in CONTEXT.md the way `render_target` was (D-15 only names `render_target`) — flagged in Open Questions.

### Pattern 2: `vertex_layout` — reuse `pass_io_binding`'s prefix-notation convention, auto-computed stride

**What:** A `vertex_layout` array of `{name, format, offset}` on `pass` (render-only), plus a `pass_io_binding`-style reference for *which* buffer feeds it, plus an `index_buffer` object with a configurable `index_type` enum (`uint16`/`uint32`) per D-17.
**Confirmed reuse point:** `pass_io_binding`'s existing `source`/`target` fields (`gnus-processing-schema.json:357-376`) already use the pattern `^(input|output|internal|parameter):[a-zA-Z][a-zA-Z0-9_]*$` — this is the exact regex to reuse verbatim for the vertex/index buffer's source reference, not a new pattern.
**Stride:** per D-16, NOT a schema field — computed in C++ at pipeline-build time (Phase 3) as the tightly-packed sum of each entry's format-implied byte size. This phase only needs to encode `{name, format, offset}` — no `stride` property in the schema at all. `offset` stays schema-explicit even though stride is computed, since `offset` can express deliberate padding/interleaving that a naive tightly-packed sum wouldn't capture on its own if a job author wants gaps.
**Example:**
```json
"vertex_layout": {
  "type": "array",
  "items": {
    "type": "object",
    "required": ["name", "format", "offset"],
    "properties": {
      "name":   { "type": "string" },
      "format": { "type": "string", "enum": ["FLOAT32", "FLOAT16", "INT32"] },
      "offset": { "type": "integer", "minimum": 0 }
    }
  }
},
"index_buffer": {
  "type": "object",
  "properties": {
    "index_type": { "type": "string", "enum": ["uint16", "uint32"], "default": "uint32" },
    "source": { "type": "string", "pattern": "^(input|output|internal|parameter):[a-zA-Z][a-zA-Z0-9_]*$" }
  }
}
```

### Pattern 3: Splitting `shader_config` into two shapes — the single most important schema-modeling decision this phase

**What:** `shader_config` (`gnus-processing-schema.json:326-356`) is **currently referenced by both `compute` and `render` pass types**, unchanged, via `pass.allOf[1]` (`then: { required: ["shader"] }` for `type ∈ {compute, render}`, `properties.shader: { $ref: "#/definitions/shader_config" }`). D-11 explicitly changes the shape **only for render passes** ("compute passes, out of scope this milestone, are unaffected"). A naive in-place edit of `shader_config` would silently also change compute's shape — this must NOT happen.
**Recommended approach:** introduce a second definition, e.g. `render_shader_config` (`stages` array + shared `uniforms`), and branch `pass.shader`'s `$ref` on `pass.type` using the identical `if`/`then` conditional-schema pattern the file already uses at the `pass` level — one level deeper, keyed on the same discriminator:
```json
"allOf": [
  { "if": { "properties": { "type": { "enum": ["inference", "retrain"] } } },
    "then": { "required": ["model"] } },
  { "if": { "properties": { "type": { "const": "compute" } } },
    "then": { "properties": { "shader": { "$ref": "#/definitions/shader_config" } }, "required": ["shader"] } },
  { "if": { "properties": { "type": { "const": "render" } } },
    "then": { "properties": { "shader": { "$ref": "#/definitions/render_shader_config" } }, "required": ["shader"] } }
]
```
`shader_config` itself keeps its current shape (`source`/`type`/`entry_point`/`uniforms`) for compute, with only D-10's enum narrowing (`["glsl","spirv"]`, drop `hlsl`/`metal`) applied — that narrowing is safe to apply globally since it's a "this value was always dead" removal, not a shape change. `[ASSUMED]` — whether the enum narrowing should also literally apply to `shader_config`'s (compute) `type` field is not explicitly re-stated for compute in CONTEXT.md (D-10 talks about "the schema enum" generically); recommend applying it uniformly since `hlsl`/`metal` are dead for either pass type per the same reasoning, but flag as a confirm-during-planning item.
`[CITED: draft-07 if/then/allOf composition — jsonic.io/guides/json-schema-composition-examples, ajv.js.org/json-schema.html]` — general JSON Schema conditional-composition mechanics; this file's own existing pass-level `allOf` block is the primary, HIGH-confidence precedent already proven to work with this project's quicktype invocation.

### Pattern 4: `ShaderCompiler` — a standalone, Vulkan-device-free component (this phase's actual "shader validation pipeline" deliverable)

**What:** A new class (suggested: `sgns::sgprocessing::ShaderCompiler`, `include/shaders/shader_compiler.hpp` + `src/shaders/shader_compiler.cpp`) exposing something shaped like:
```cpp
struct CompiledStage { std::vector<uint32_t> spirv; std::string stage_name; };
outcome::result<CompiledStage> CompileAndValidate(
    const std::string &source_or_raw_bytes,
    ShaderStageKind stage,      // vertex | fragment
    ShaderType type,            // glsl | spirv  (post-D-10 narrowed enum)
    const std::string &entry_point );
```
**Why this shape:** SHADER-01/02/03's success criteria all describe behavior that must happen "before any GPU call is made" / "before it ever reaches `vkCreateShaderModule`" — none of shaderc's or SPIRV-Tools' APIs require a live `VkInstance`/`VkDevice` (confirmed: `shaderc::Compiler` takes only source text + a `shaderc_shader_kind` enum; `spvtools::SpirvTools`'s constructor takes only a `spv_target_env` enum, not a device handle). This means the entire compile+validate pipeline can be built and unit-tested in complete isolation from Phase 1/3's Vulkan context work — matching the workstream SUMMARY.md's own phase-ordering rationale ("the shader-compile-to-SPIR-V step could... be developed and unit-tested in isolation... before any VkInstance exists").
**Where it plugs in:** `ProcessingManager::GetCidForProc()` (`ProcessingManager.cpp:847-899`) is the natural integration point — it already fetches the render pass's shader bytes (today: a single `p.get_shader().value().get_source()` call at `cpp:864-871`sourcing ONE shader). This phase extends that function to loop over `shader.stages[]`, fetch each stage's source bytes via the existing `GetSubCidForProc`/`FileManager` machinery (unchanged), then run each fetched buffer through `ShaderCompiler::CompileAndValidate` before it ever reaches the buffer that Phase 3's `RenderProcessor::StartProcessing` will receive. By the time Phase 3 code runs, the "modelFile"-slot buffer(s) handed to `RenderProcessor` are already-validated SPIR-V — `RenderProcessor` in Phase 3 only needs to call `vkCreateShaderModule` directly, no compile/validate logic of its own.
**Confirmed current call site (direct read, `ProcessingManager.cpp:864-871`):**
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
This is a URI-resolution step only (fetches bytes from a location), not shader-content compilation — it must be extended to iterate `stages[]` (plural sources) instead of one `get_source()` call, matching the new `render_shader_config` shape from Pattern 3.

### Anti-Patterns to Avoid
- **Assuming shaderc validates SPIR-V for you:** see Common Pitfalls → Pitfall 2. This is the single most consequential anti-pattern this phase must avoid — `CompileGlslToSpv` returning `shaderc_compilation_status_success` means "glslang produced *some* SPIR-V," not "SPIRV-Tools' validator approved it."
- **Editing `shader_config` in place for the `stages` array:** silently breaks `compute` passes, which share the same definition today and are explicitly out of scope this milestone (see Pattern 3).
- **Assuming a `find_package(shaderc CONFIG REQUIRED)` will work** the way it does for vk-bootstrap/Vulkan-Headers/Loader in this exact repo's existing convention — it will not (see Common Pitfalls → Pitfall 3).
- **Wiring `ShaderCompiler` calls directly into `RenderProcessor::StartProcessing`** instead of the `ProcessingManager`/`GetCidForProc` fetch path — this would smuggle Phase 3-shaped pipeline work into a phase explicitly scoped to have "no VkInstance/pipeline/draw code."

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| GLSL→SPIR-V compilation | A custom GLSL parser/codegen, or driving glslang's raw `TShader`/`TProgram` API directly | `shaderc::Compiler::CompileGlslToSpv` | Purpose-built, structured error reporting (`GetCompilationStatus()`/`GetErrorMessage()`), already locked by D-08 |
| SPIR-V structural/semantic validation | A hand-written SPIR-V binary-format checker | `spvtools::SpirvTools::Validate()` (SPIRV-Tools' actual validator, the same one Vulkan SDK's `spirv-val` CLI wraps) | This is exactly the kind of "deceptively complex, security-relevant parsing" problem a hand-rolled check would get subtly wrong on adversarial input — Khronos' own validator is the canonical implementation |
| Vertex-layout stride computation | N/A — this one IS hand-rolled by design (D-16), but the *validation* of attribute-size lookups per `VkFormat` should reuse Vulkan's own format-size semantics, not a custom guess table | A small `FormatByteSize(VkFormat)` lookup matching the Vulkan spec's component/size table for the narrow enum subset this schema actually exposes | Small, bounded lookup — not worth an external dependency, but worth getting exactly right against the spec rather than assuming |

**Key insight:** The temptation in this phase is to treat "shaderc is vendored" as equivalent to "SPIR-V validation is solved" — they are not the same dependency-shape question, and conflating them is the single largest correctness risk this phase carries forward into Phase 3.

## Common Pitfalls

### Pitfall 1: `gnus-processing-schema.json` is currently invalid JSON — this blocks ALL schema work, not just this phase's additions

**What goes wrong:** `[VERIFIED: direct `node -e "JSON.parse(...)"` execution against the live file, 2026-07-30]` — `gnus-processing-schema.json` lines 334-338 currently read:
```json
"type": {
  "type": "string",
  "default": "glsl"
  "enum": ["glsl", "hlsl", "metal", "spirv"],
},
```
This has **two syntax errors**: a missing comma after `"default": "glsl"`, and a trailing comma after the `enum` array before the closing `}`. Running `JSON.parse()` on the file fails with `SyntaxError: Expected ',' or '}' after property value ... at position 10085 (line 337 column 11)`. This is not a hypothetical risk — it is the file's actual current state on disk in this repo, verified directly in this research session.
**Why it happens:** Likely a manual hand-edit of the schema (outside the quicktype-regeneration flow) that was never round-tripped through a JSON validator or quicktype before being committed — quicktype's CI job (`generate-headers.yml`) only triggers `on: push: paths: gnus-processing-schema.json`, and if that CI run failed silently or its resulting PR was never merged, the broken JSON could persist in the schema file itself indefinitely without anyone noticing (the *generated* headers in `generated/` are stale-but-valid C++, so nothing downstream visibly breaks until someone tries to edit the schema again).
**How to avoid:** Fix this as the literal first task of this phase, before any of D-08 through D-17's schema additions are attempted — any JSON-Schema editor/linter, or every other schema change in this phase, will be blocked or silently malformed until this is corrected. The fix is mechanical: add the missing comma, remove the trailing comma.
**Warning signs:** Any attempt to run `quicktype` locally, or any JSON-Schema-aware editor opening the file, will immediately flag a parse error at this exact location — this should have been caught by literally any tooling touching the file, which is itself a signal that no CI/local validation currently runs against schema edits before commit.
**Phase to address:** This phase, first task, before any other schema edit.

### Pitfall 2: shaderc's `CompileGlslToSpv` does NOT run `spirv-val` internally — a correction to the workstream-level research's framing

**What goes wrong:** The workstream-level STACK.md/SUMMARY.md research states shaderc "gets `spirv-val`-capable validation for free" because it bundles SPIRV-Tools as a transitive build dependency. This is **true only for shaderc's internal build graph** (SPIRV-Tools is compiled as part of shaderc's own build), but **shaderc's public C++ API (`shaderc::Compiler`/`shaderc::CompileOptions`) does not expose or automatically invoke SPIRV-Tools' validator**. `CompileGlslToSpv()`'s `GetCompilationStatus() == shaderc_compilation_status_success` means glslang's codegen produced a well-formed-per-glslang SPIR-V module — it is not the same claim as "SPIRV-Tools' validator approved this module." `[CITED: cross-checked WebSearch across shaderc's own repo/issue tracker and SPIRV-Tools' own README — validation is documented as a distinct, separate tool/step from compilation]`.
**Why it happens:** "Bundles the dependency" and "invokes the dependency's every capability automatically" are easy to conflate, especially when the workstream-level research correctly identified that adding shaderc avoids a *second vendoring decision* for SPIRV-Tools' build — but that's a build-graph fact, not an API-surface fact.
**How to avoid:** Treat `spvtools::SpirvTools::Validate()` (or the C API `spvValidateBinary`) as a mandatory, explicit second call after every `CompileGlslToSpv()` (and, per SHADER-03, on every directly-submitted `type: "spirv"` payload too) — see Code Examples. This requires SPIRV-Tools to be reachable as its own directly-linkable CMake target, not merely present somewhere inside shaderc's private build tree (see Standard Stack's "Alternatives Considered" row on why reaching into shaderc's internal build tree is not recommended).
**Warning signs:** A test suite that only checks `GetCompilationStatus() == shaderc_compilation_status_success` and never separately calls a validator function anywhere in the code path — this looks complete but has not actually satisfied SHADER-02.
**Phase to address:** This phase — `ShaderCompiler`'s `CompileAndValidate()` must call both steps, for both the GLSL-compiled path and the directly-submitted-SPIR-V path.

### Pitfall 3: shaderc does not install a CMake package config — the existing `find_package(... CONFIG REQUIRED)` vendoring convention does not directly apply

**What goes wrong:** Phase 1 vendored vk-bootstrap and reuses the existing Vulkan-Headers/Vulkan-Loader `ExternalProject_Add` blocks, all of which install a proper CMake config consumed via `find_package(<lib> CONFIG REQUIRED)` (confirmed: `CommonTargets.cmake:390-401` passes `-DVulkanHeaders_DIR:PATH=...` and vk-bootstrap resolves via its own installed config). A naive attempt to vendor shaderc the same way (`ExternalProject_Add(shaderc ...)` then `find_package(shaderc CONFIG REQUIRED)`) will fail — **shaderc does not install a CMake package-config file**, confirmed via multiple upstream sources: `[CITED: github.com/google/shaderc/issues/1369 "Including shaderc/CMakeLists.txt as suggested in README not working"]`, `[CITED: github.com/microsoft/vcpkg/issues/23208 "Shaderc doesn't install a config CMake file, so it can't be found with find_package after a successful install"]`.
**Why it happens:** shaderc's own README recommends the *in-tree* consumption pattern (`add_subdirectory(shaderc)` inside a project that also vendors glslang/SPIRV-Tools as CMake subdirectories itself, linking against the `shaderc`/`shaderc_combined` targets shaderc's own `CMakeLists.txt` defines) — this is a fundamentally different integration shape than this project's existing `ExternalProject_Add`-with-separate-install-step convention, which assumes every vendored dependency installs a discoverable config.
**How to avoid:** Two viable paths, both requiring more manual CMake work than the existing pattern: (a) `ExternalProject_Add(shaderc ...)` with `-DSHADERC_SKIP_INSTALL:BOOL=OFF` (shaderc DOES install its compiled static libraries and headers even without a CONFIG file — confirm the exact installed file layout during implementation), then a hand-written `add_library(shaderc::shaderc STATIC IMPORTED)` target pointing at the installed `libshaderc_combined.a`/`.lib` + include dir; or (b) skip `ExternalProject_Add` for shaderc specifically and use `add_subdirectory()` in-tree, accepting the build-graph inconsistency with the rest of `CommonTargets.cmake`'s pattern. Recommend (a) for consistency with the rest of the file, but this needs a build-time spike to confirm exact installed artifact paths/names — flagged in Open Questions.
**Warning signs:** `find_package(shaderc CONFIG REQUIRED)` failing with "config file not found" immediately after a clean `ExternalProject_Add(shaderc ...)` build — this is expected, not a build misconfiguration to chase further.
**Phase to address:** This phase's CMake vendoring work (schema/validation-only per phase scope, but the `ShaderCompiler` component needs to actually link against shaderc to be buildable/testable).

### Pitfall 4: Two copies of SPIRV-Tools/glslang in the tree if SPIRV-Tools is vendored separately — version-skew risk

**What goes wrong:** If SPIRV-Tools is vendored as its own top-level submodule (recommended, per Pitfall 2/Standard Stack) *and* shaderc's own nested `third_party/spirv-tools` submodule also builds its own copy for shaderc's internal use, the tree ends up with two SPIRV-Tools source checkouts. If they're pinned to different commits, the SPIR-V dialect/feature-set the validator checks against could subtly diverge from what shaderc's bundled glslang+SPIRV-Tools-based codegen actually emits.
**Why it happens:** Two independent `.gitmodules` entries (this project's top-level `SPIRV-Tools` submodule vs. shaderc's own nested one) have no built-in mechanism keeping them in sync.
**How to avoid:** Pin this project's own top-level `SPIRV-Tools`/`SPIRV-Headers` submodules to the exact commit hashes shaderc's own `DEPS` file references at vendoring time (captured in Standard Stack above: `a665e21f...` / `29981f65...`) — re-check `shaderc/DEPS` if the shaderc version pin changes later in the project's lifetime.
**Warning signs:** A shader that compiles successfully via `shaderc::Compiler` but fails validation via the separately-vendored `SpirvTools::Validate()` (or vice versa) in a way that looks like a validator bug but is actually a dialect/capability mismatch between the two pinned versions.
**Phase to address:** This phase, at vendoring time — a one-time pin-matching check, not an ongoing maintenance burden unless shaderc's version is bumped later.

### Pitfall 5: Reintroducing the exact `.value()`-on-unchecked-`boost::optional` crash shape for new fields not covered by D-15's "all required" decision

**What goes wrong:** D-15 locks `render_target` as all-required (sidesteps this class of bug per Pattern 1's finding). But `pipeline_state`'s own field-level required/optional split is NOT explicitly locked in CONTEXT.md, nor is `vertex_layout`/`index_buffer`'s. Any new field left `boost::optional` in the generated headers re-opens Pitfall 8 from the workstream-level PITFALLS.md (the exact `ParseBlockSize()`/`pass.get_model().value()` crash shape) the moment some C++ code path calls `.value()` on it without checking presence first, or without already being inside a `case PassType::RENDER:` branch.
**Why it happens:** It's easy to focus schema-design attention on the fields CONTEXT.md explicitly named (`render_target`) and let newer, adjacent fields (`pipeline_state`, `index_buffer`) default to "optional, decide later" without applying the same rigor.
**How to avoid:** For every new `boost::optional`-returning accessor introduced this phase, `CheckProcessValidity()`'s render-pass branch (`ProcessingManager.cpp:153-161` today) should explicitly check presence and return a clean validation error — matching the existing pattern already used for `pass.get_shader()` at that exact call site — rather than letting a `.value()` crash surface later in Phase 3's `RenderProcessor` code.
**Warning signs:** Any `.value()` call on a render-specific optional field outside a `case PassType::RENDER:` block or an explicit prior presence check.
**Phase to address:** This phase (schema field optionality decisions + `CheckProcessValidity()` extension) — verify with a test that feeds a non-render pass, and separately a render pass missing an optional-but-expected field, through the validation path.

## Code Examples

### shaderc: compile GLSL to SPIR-V with structured error handling
```cpp
// Source: cross-checked against github.com/google/shaderc/blob/main/libshaderc/include/shaderc/shaderc.hpp
// and github.com/google/shaderc/blob/main/examples/online-compile/main.cc  [CITED, MEDIUM confidence]
#include <shaderc/shaderc.hpp>

outcome::result<std::vector<uint32_t>> CompileGlslStage(
    const std::string &source, shaderc_shader_kind kind,
    const std::string &debug_name, const std::string &entry_point )
{
    shaderc::Compiler compiler;
    shaderc::CompileOptions options;
    options.SetTargetEnvironment( shaderc_target_env_vulkan, shaderc_env_version_vulkan_1_3 );
    // SetOptimizationLevel(shaderc_optimization_level_zero) recommended for v1 — determinism
    // guard from workstream PITFALLS.md Pitfall 5 favors predictable, unoptimized codegen
    // over driver/compiler-version-dependent optimization passes. [ASSUMED — not explicitly
    // locked in CONTEXT.md; flagged in Open Questions.]

    shaderc::SpvCompilationResult result = compiler.CompileGlslToSpv(
        source.c_str(), source.size(), kind, debug_name.c_str(), entry_point.c_str(), options );

    if ( result.GetCompilationStatus() != shaderc_compilation_status_success )
    {
        // Clean job-rejection path — NOT a crash. result.GetErrorMessage() has details.
        return outcome::failure( Error::SHADER_COMPILE_FAILED );
    }
    return std::vector<uint32_t>( result.cbegin(), result.cend() );
}
```

### SPIRV-Tools: mandatory validation gate (both the GLSL-compiled path and the direct-`spirv`-submission path)
```cpp
// Source: cross-checked against github.com/KhronosGroup/SPIRV-Tools/include/spirv-tools/libspirv.hpp
// [CITED, MEDIUM confidence — WebFetch of official header, spot-checked; exact overload set
// not independently confirmed against a second source]
#include <spirv-tools/libspirv.hpp>

outcome::result<void> ValidateSpirV( const std::vector<uint32_t> &spirv )
{
    spvtools::SpirvTools tools( SPV_ENV_VULKAN_1_3 );
    tools.SetMessageConsumer(
        []( spv_message_level_t, const char *, const spv_position_t &, const char *message ) {
            // log message — do not throw/crash on malformed input
        } );

    if ( !tools.Validate( spirv ) )
    {
        // Clean job-rejection path. This is the SHADER-02 gate — MUST run before
        // vkCreateShaderModule regardless of whether spirv came from shaderc or
        // was submitted directly via shader_config.type: "spirv" (SHADER-03).
        return outcome::failure( Error::SPIRV_VALIDATION_FAILED );
    }
    return outcome::success();
}
```

### JSON Schema: existing prefix-notation pattern to reuse verbatim for `vertex_layout`'s buffer reference
```json
// Source: direct read, gnus-processing-schema.json:365-369 (pass_io_binding.source) — reuse this
// exact pattern string, do not invent a new one, per D-16.
"source": {
  "type": "string",
  "description": "Data source using prefix notation",
  "pattern": "^(input|output|internal|parameter):[a-zA-Z][a-zA-Z0-9_]*$"
}
```

### CMake: illustrative shaderc vendoring (no installed config — hand-written IMPORTED target required)
```cmake
# Source: illustrative, synthesized from this repo's existing ExternalProject_Add pattern
# (thirdparty/build/CommonTargets.cmake:363-401, Vulkan-Headers/Loader/vk-bootstrap block)
# plus CITED shaderc CMake option names (github.com/google/shaderc/blob/main/CMakeLists.txt).
# Exact installed artifact paths must be confirmed via a build-time spike (see Open Questions).
ExternalProject_Add(
    shaderc
    PREFIX shaderc
    SOURCE_DIR "${THIRDPARTY_DIR}/shaderc"
    CMAKE_CACHE_ARGS
        -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
        -DSHADERC_SKIP_TESTS:BOOL=ON
        -DSHADERC_SKIP_EXAMPLES:BOOL=ON
        -DSHADERC_SKIP_COPYRIGHT_CHECK:BOOL=ON
        -DSHADERC_ENABLE_HLSL:BOOL=OFF          # D-09: no HLSL support — skip building glslang's
                                                 # HLSL frontend entirely (binary-size guard, D-08)
        -DSHADERC_ENABLE_WGSL_OUTPUT:BOOL=OFF   # not needed, matches upstream default
    ${_CMAKE_COMMON_CACHE_ARGS}
)
# No find_package(shaderc CONFIG REQUIRED) — confirmed unavailable (Pitfall 3). Instead:
add_library(shaderc::shaderc STATIC IMPORTED)
set_target_properties(shaderc::shaderc PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_BINARY_DIR}/shaderc/lib/libshaderc_combined.a"  # path TBD, spike
    INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_BINARY_DIR}/shaderc/include"
)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| `shader_config.type` accepting `["glsl","hlsl","metal","spirv"]` with no render-specific validation | Narrowed to `["glsl","spirv"]`, with an explicit `spirv-val` gate on both accepted types | This phase (D-10, SHADER-02/03) | Closes a documented driver-crash vector (workstream PITFALLS.md Pitfall 6) that exists in the schema today |
| Single `shader_config.source`/`type`/`entry_point` for both compute and render | `stages[]` array for render only, compute unchanged | This phase (D-11) | Enables true vertex+fragment multi-stage pipelines (SCHEMA-03) without breaking existing compute-pass jobs |

**Deprecated/outdated:** none — this is new capability, not a replacement of a previously-working mechanism (the render pass type has never had working shader/pipeline support).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `pipeline_state`'s individual fields (topology/cull_mode/front_face/depth_test) should each have a sensible schema-level `default` rather than being all-required like `render_target` | Architecture Patterns → Pattern 1 | Low — if wrong, planner adds `required` entries instead of `default` entries; a schema-shape tweak, not a rework |
| A2 | D-10's `type` enum narrowing (`["glsl","spirv"]`) applies uniformly to both the render (`render_shader_config.stages[].type`) and compute (`shader_config.type`) shapes, not render-only | Architecture Patterns → Pattern 3 | Low-Medium — if compute passes still need `hlsl`/`metal` for some undocumented reason, narrowing globally would be a breaking change to compute jobs; no evidence found that compute passes ever used `hlsl`/`metal` in practice, but this wasn't explicitly re-confirmed for the compute path in CONTEXT.md |
| A3 | `SetOptimizationLevel(shaderc_optimization_level_zero)` (unoptimized codegen) is the correct choice for shaderc's `CompileOptions`, for determinism reasons | Code Examples → shaderc compile example | Medium — if wrong (e.g. if some optimization level is actually more deterministic, or if performance matters more than assumed), this is a one-line `CompileOptions` change, not an architectural rework; flagged here because it directly touches Phase 3's/DETV's determinism requirements even though this phase doesn't implement the render loop itself |
| A4 | Vendoring SPIRV-Tools as a second, separate top-level submodule (rather than reaching into shaderc's internal build tree) is the correct integration shape | Standard Stack, Common Pitfalls Pitfall 2/4 | Medium — if a stable way to reach shaderc's internal SPIRV-Tools build artifacts is later found (e.g. a future shaderc release adds proper CMake exports), the separate-vendoring approach could be revisited to reduce duplication; not a correctness risk either way, just a build-graph tidiness question |
| A5 | shaderc's exact installed artifact layout (`libshaderc_combined.a` path, include-dir path) when built via `ExternalProject_Add` with `SHADERC_SKIP_INSTALL:BOOL=OFF` | Code Examples → CMake vendoring | Medium — this needs a build-time spike; if the installed layout differs from what's illustrated, the `IMPORTED` target's `IMPORTED_LOCATION`/`INTERFACE_INCLUDE_DIRECTORIES` paths need adjusting, but the overall approach (hand-written IMPORTED target, no config file) is not in question |

**If this table is empty:** N/A — see entries above; none of these block starting the phase, all are confirm-during-planning/implementation items.

## Open Questions

1. **Exact shaderc installed artifact paths for the hand-written CMake `IMPORTED` target**
   - What we know: shaderc does not install a CMake config file (Pitfall 3), but does have a `SHADERC_SKIP_INSTALL` option implying it can install compiled artifacts + headers with a config-free layout.
   - What's unclear: the exact relative paths (`lib/libshaderc_combined.a` vs. some other layout) after `cmake --install` runs, and whether `libshaderc_combined` (the bundled variant including glslang+SPIRV-Tools statically) or `libshaderc` (requiring separate linking against glslang/SPIRV-Tools libs) is the right target to consume — `libshaderc_combined` is very likely correct here since it minimizes separate-linking bookkeeping, but the exact CMake target/output name should be confirmed against a real local build.
   - Recommendation: a short build-time spike (build shaderc via the illustrative `ExternalProject_Add` block, `cmake --install`, inspect the resulting directory tree) before finalizing the CMake integration, budgeted as part of this phase's first task alongside the JSON syntax fix.

2. **Does the compute pass type's `shader_config.type` enum also narrow to `["glsl","spirv"]`, or does narrowing apply render-only?**
   - What we know: D-10 states "the schema enum" narrows, without explicitly scoping to render vs. compute; D-11 explicitly scopes the `stages`-array shape change to render-only.
   - What's unclear: whether any existing/planned compute-pass job definition relies on `hlsl`/`metal` (workstream research found no evidence of this, but didn't explicitly rule it out for compute specifically).
   - Recommendation: apply the narrowing uniformly (both shapes), consistent with D-10's stated rationale that `hlsl`/`metal` were "always dead" — flagged as low-risk in the Assumptions Log (A2) since no evidence contradicts uniform narrowing.

3. **Should `pipeline_state` fields have schema-level `default` values, or be required like `render_target`?**
   - What we know: D-15 explicitly locks `render_target` as all-required, no defaults. D-13/D-14 describe `pipeline_state`'s enum value sets but don't explicitly state a required-vs-default posture the way D-15 does for `render_target`.
   - What's unclear: whether the user's "explicitness over boilerplate" preference (the stated rationale behind D-15) extends to `pipeline_state` too, or whether sensible defaults (e.g. `topology: triangle_list`, `cull_mode: back`, `front_face: ccw`, `depth_test: enabled`) are acceptable here since they're genuinely uncontroversial defaults for a typical render pass.
   - Recommendation: surface this explicitly to the user during `/gsd-plan-phase` rather than silently picking one — the two options produce meaningfully different schema/quicktype shapes (required plain members vs. `boost::optional` members with default-application logic in `CheckProcessValidity()` or `RenderProcessor`).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Node.js + `quicktype` (npm global) | SCHEMA-05 (header regeneration) | Not verified locally this session — CI (`generate-headers.yml`) installs Node 20 + `npm install -g quicktype` fresh every run | quicktype (latest, unpinned in CI workflow) | If a developer needs local regeneration for iteration (per CONTEXT.md's "Established Patterns" note that no local regen script exists today), the same `npm install -g quicktype` + CLI invocation from `generate-headers.yml` works locally — no CI-specific dependency |
| C++17 toolchain + CMake (already project baseline) | Building the new `ShaderCompiler` component, shaderc vendoring | Assumed available (existing project baseline per workstream STACK.md) | — | — |
| Git submodule support (`git submodule update --init --recursive`) | Nested shaderc→glslang/SPIRV-Tools/SPIRV-Headers submodules | Assumed available (already used for MoltenVK's own nested submodules per workstream research) | — | — |

**Missing dependencies with no fallback:** none identified — this phase has no hardware (GPU) dependency at all (explicitly no VkInstance/pipeline work), which is a deliberate scope boundary, not a gap.

**Missing dependencies with fallback:** the quicktype local-invocation gap (no committed local script) has a trivial fallback (copy the exact CLI invocation from `generate-headers.yml`) — not a blocker, but worth the planner adding a documented local-dev command (e.g. a `Makefile`/`package.json` script) as a small, high-value convenience task this phase, since CI-only regeneration makes local schema-edit iteration slow (push → wait for CI → pull the auto-PR).

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-------------------|
| V1 Architecture | yes | Validation gate placed structurally before any GPU-facing call (`vkCreateShaderModule` in Phase 3) — a defense-in-depth boundary, not a bolt-on check |
| V5 Input Validation | yes | Both GLSL source (via shaderc's structured compile-error reporting) and raw SPIR-V (via SPIRV-Tools' `Validate()`) are treated as untrusted, job-supplied input requiring explicit validation before use — this is the core of SHADER-01/02/03 |
| V6 Cryptography | no | Not applicable — this phase produces no cryptographic material; output hashing (SHA-256 over render output) is Phase 3/4 scope, unchanged mechanism |
| V12 File/Resource | yes (partially) | Shader source bytes arrive via the existing `FileManager`/CID-fetch mechanism (unchanged this phase) — no new file-handling surface introduced, but the fetched bytes are exactly the untrusted input V5's controls apply to |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|----------------------|
| Malformed/adversarial GLSL source crashing the compiler process (glslang's documented linker-pass `nullptr treeRoot` crash class on malformed input) | Denial of Service | Treat `shaderc::Compiler::CompileGlslToSpv` as untrusted-input-handling code — rely on its structured `GetCompilationStatus()`/`GetErrorMessage()` return path; do not assume all malformed input returns cleanly rather than crashing the process, and consider process-level isolation (out of this phase's scope, but worth flagging for Phase 3/4 hardening) if crash reports are observed |
| Malformed/adversarial raw SPIR-V (`shader_config.type: "spirv"` direct-submission path) reaching the driver unvalidated | Tampering / Denial of Service | Mandatory `spvtools::SpirvTools::Validate()` gate on ALL SPIR-V, both GLSL-compiled and directly-submitted, before any byte buffer is handed toward Phase 3's `vkCreateShaderModule` call — this is SHADER-02's entire purpose, and per workstream PITFALLS.md Pitfall 6, invalid-but-syntactically-parseable SPIR-V is a documented driver-crash vector (reported segfaults in RADV and other ICDs) that Vulkan validation layers do not reliably catch |
| Schema-enum bypass (a hand-edited/malformed schema or a client that ignores schema validation submitting `hlsl`/`metal` directly) | Tampering | Defense-in-depth: `CheckProcessValidity()` should explicitly reject `hlsl`/`metal` at the C++ layer too, not rely solely on JSON-Schema-level enum validation catching it — matches this phase's existing pattern of double-checking at both the schema and C++ layers |

## Sources

### Primary (HIGH confidence)
- Direct file reads, this repo, 2026-07-30: `SuperGenius/SGProcessingManager/gnus-processing-schema.json` (confirmed invalid JSON via `node -e "JSON.parse(...)"`), `generated/{ShaderConfig,ShaderType,Pass,PassIoBinding,Uniform,DataType,ModelConfig}.hpp`, `.github/workflows/generate-headers.yml`, `src/processingbase/ProcessingManager.cpp` (lines 120-180, 830-920), `src/processors/CMakeLists.txt`, `include/processors/processing_processor_render.hpp`, `src/processors/processing_processor_render.cpp`, `thirdparty/build/CommonTargets.cmake` (lines 358-408), `thirdparty/.gitmodules`
- `.planning/workstreams/sgproc-render/phases/02-.../02-CONTEXT.md`, `01-.../01-CONTEXT.md`, `REQUIREMENTS.md`, `STATE.md` — locked decisions, requirement text, prior-phase state (Phase 1 confirmed already landed: vk-bootstrap vendored, `RenderProcessor` context-init stub exists, `CheckProcessValidity`/`GetCidForProc` already have `PassType::RENDER` branches per DISP-01/02/03)
- Workstream-level research: `.planning/workstreams/sgproc-render/research/{STACK,PITFALLS,ARCHITECTURE,FEATURES,SUMMARY}.md` (2026-07-29) — reused as grounding, with two explicit corrections this phase's research made: (1) shaderc does not auto-validate SPIR-V (Pitfall 2), refining STACK.md/SUMMARY.md's "gets spirv-val for free" framing; (2) shaderc has no installed CMake config (Pitfall 3), not previously identified

### Secondary (MEDIUM confidence)
- https://github.com/google/shaderc — official repo, Apache-2.0, `shaderc.hpp` header content (via WebFetch), `CMakeLists.txt` options (via WebFetch), `DEPS` file pinned commit hashes for glslang/spirv-tools/spirv-headers (via WebFetch)
- https://github.com/google/shaderc/blob/main/examples/online-compile/main.cc — `CompileGlslToSpv` usage pattern (via WebSearch)
- https://github.com/google/shaderc/issues/1369, https://github.com/microsoft/vcpkg/issues/23208 — shaderc's lack of an installed CMake config, cross-checked across two independent sources
- https://github.com/KhronosGroup/SPIRV-Tools — official Khronos repo, `libspirv.hpp` C++ API shape (via WebFetch), README's external-dependency/CMake-option documentation (via WebFetch)
- https://github.com/google/shaderc/blob/main/third_party/CMakeLists.txt — nested submodule `add_subdirectory` ordering (spirv-headers → spirv-tools → glslang) (via WebFetch)
- https://developer.android.com/ndk/guides/graphics/shader-compilers — confirms shaderc's real-world adoption (Android NDK ships it)
- General JSON Schema draft-07 `if`/`then`/`allOf` composition mechanics (jsonic.io, ajv.js.org) — cross-checked against this repo's own existing, already-working `pass.allOf` block, which is the higher-confidence precedent

### Tertiary (LOW confidence)
- None — Context7 MCP tool was unavailable in this session (`mcp__context7__resolve-library-id` returned "No such tool available"), so all non-repo findings are WebSearch/WebFetch-sourced and cross-checked at least once per claim; nothing is presented as single-source/unverified beyond what's explicitly flagged `[ASSUMED]` in the Assumptions Log.

## Metadata

**Confidence breakdown:**
- Standard stack: MEDIUM-HIGH — shaderc/SPIRV-Tools identity and licensing already vetted at workstream level (HIGH); the specific API/CMake-integration findings this phase adds are WebFetch/WebSearch-cross-checked against official repos (MEDIUM, no Context7 available this session)
- Architecture: HIGH for the schema-split finding (Pattern 3) and the JSON-syntax-bug finding (Pitfall 1) — both are direct-file-read, reproducible facts about this exact repo, not general-knowledge claims
- Pitfalls: HIGH for Pitfalls 1 and 5 (repo-grounded); MEDIUM for Pitfalls 2, 3, 4 (shaderc/SPIRV-Tools API and CMake-integration behavior, cross-checked WebSearch/WebFetch, not independently confirmed via a local build spike in this session)

**Research date:** 2026-07-30
**Valid until:** 30 days for the shaderc/SPIRV-Tools version pins and CMake-integration findings (fast-moving upstream repos); the JSON-syntax-bug finding and schema-split finding are valid until the schema file is next edited (i.e., until this phase's own work lands)
