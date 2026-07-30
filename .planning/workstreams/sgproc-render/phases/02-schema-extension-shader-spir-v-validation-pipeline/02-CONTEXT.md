# Phase 2: Schema Extension & Shader/SPIR-V Validation Pipeline - Context

**Gathered:** 2026-07-30
**Status:** Ready for planning

<domain>
## Phase Boundary

The processing schema (`gnus-processing-schema.json`) gains the ability to fully describe a render pass — render-target/framebuffer config, vertex/index buffer bindings + layout, a multi-stage (vertex+fragment) shader array, and pipeline state (topology/cull/winding/depth-test) — with quicktype headers regenerated (`generated/` never hand-edited). A GLSL→SPIR-V compile pipeline (shaderc) is wired in, and every piece of SPIR-V that could reach the driver — whether compiled from job-supplied GLSL or submitted directly as `shader_config.type: "spirv"` — passes a mandatory `spirv-val` gate before it ever reaches `vkCreateShaderModule`. No `VkInstance`/pipeline/draw code (Phase 3), no CI wiring (Phase 4). Requirements: SCHEMA-01..05, SHADER-01..03.

</domain>

<decisions>
## Implementation Decisions

### GLSL→SPIR-V Toolchain
- **D-08:** **shaderc** is the vendored toolchain (bundles glslang for GLSL parsing/codegen + SPIRV-Tools for `spirv-val`/optimization behind one coherent Apache-2.0 dependency), confirming research's Decision Flag #2. This was re-derived from first principles during discussion, not taken on faith from the research recommendation alone: the user first challenged whether GLSL compilation was needed at all (given `shader_config.type: "spirv"` already exists per SHADER-03) — see rationale below — and, after weighing binary-size/crash-surface trade-offs for low-end/mobile deployment targets, settled on keeping `glsl` support via shaderc rather than going spirv-only.
- **Rationale explicitly walked through:**
  - MoltenVK consumes SPIR-V directly (translates to MSL internally) — so a spirv-only design would be portable across Windows/Linux/macOS-MoltenVK, the milestone's actual target platforms (Android/iOS are NOT in REQUIREMENTS.md/PROJECT.md's v1 platform list).
  - `spirv-val`/SPIRV-Tools is mandatory regardless of the GLSL-in-process-compile decision (SHADER-02) — untrusted job-supplied SPIR-V is a documented driver-crash vector no matter how it was produced. This is orthogonal to the toolchain choice, not a reason to pick one side.
  - MNN's own precompiled-shader pipeline (`thirdparty/MNN/source/backend/vulkan/*/compiler/{getSpirv.sh,makeshader.py}`) bakes SPIR-V at MNN's own **build time** via a system-installed `glslangValidator`, never at runtime, and never validates with `spirv-val` — this doesn't transfer to `RenderProcessor`, whose shaders are untrusted, job-supplied content arriving at runtime, not static build-time-known content.
  - Low-end/mobile deployment nodes (explicitly named: even Orange-Pi-class ARM SBCs) are a real target for this distributed compute node — shaderc's binary footprint (statically bundles the full glslang frontend + SPIRV-Tools) and glslang's documented crash class on malformed input (PITFALLS.md) are real costs on constrained hardware, which is why spirv-only was seriously considered.
  - iOS's runtime code-generation restrictions do NOT block running glslang/shaderc — GLSL→SPIR-V compilation is CPU-side text-to-bytecode transformation, not JIT-compiled/executable machine code, so no special entitlement is needed. This removed an assumed objection but wasn't itself a reason to prefer shaderc.
  - Final call: keep `glsl` support via shaderc. The lower barrier for hand-authored job shaders (text vs. requiring every job author to run a local SPIR-V toolchain) outweighed the binary-size argument once the crash-surface/portability concerns were resolved as non-blocking.
- **D-09:** Real HLSL support was considered and explicitly rejected for v1 — glslang's built-in HLSL frontend is documented by Khronos itself as legacy/incomplete; proper HLSL support would require vendoring Microsoft's DirectXShaderCompiler (DXC, NCSA license, permissive/non-GPL) as a second toolchain. This reopens the "minimize libraries" goal the toolchain decision was trying to resolve, so it was scoped out.
- **D-10:** `shader_config.type` schema enum narrows to **`["glsl", "spirv"]`** only. `metal` is removed entirely (not applicable — MoltenVK translates SPIR-V→MSL internally; a job never submits Metal Shading Language directly, so this value was always dead). `hlsl` is also removed entirely (not merely deferred-with-a-rejection-error) — no DXC vendoring in v1, and no schema-enum trace of a language that isn't implemented.

### Multi-Stage Shader Schema Shape
- **D-11:** `shader_config` gains a **`stages` array**: `[{stage: "vertex"|"fragment", type, source, entry_point}, ...]`, replacing the single top-level `source`/`type`/`entry_point` fields for render passes (compute passes, out of scope this milestone, are unaffected). Each stage entry independently declares `glsl` or `spirv` as its `type` — a render pass could in principle mix a GLSL vertex shader with a directly-submitted SPIR-V fragment shader. Array shape (not named `vertex_shader`/`fragment_shader` fields) chosen for extensibility to future stages (geometry/tessellation) without another schema break — no such stages are needed for v1.
- **D-12:** `uniforms` stays a **single shared map at the top level** of `shader_config`, visible to every stage — not per-stage-entry. Matches how MVP-matrix-style uniforms are actually used (the same value needed in both vertex and fragment stages) and avoids duplicated bookkeeping ahead of Phase 3's RENDER-05 push-constant work.

### Pipeline State Schema Surface
- **D-13:** Curated minimal v1 subset, not a full Vulkan enum mirror: `topology` ∈ {`triangle_list`, `line_list`, `point_list`}; `cull_mode` ∈ {`none`, `front`, `back`}; `front_face`/winding ∈ {`cw`, `ccw`}; `depth_test` ∈ {`enabled`, `disabled`}. Covers RENDER-04's stated scope without over-building; extend the enum later (non-breaking addition) if strip/fan topologies or `front_and_back` culling are ever needed.
- **D-14:** Depth comparison is **fixed at `less`**, not schema-configurable — no `depth_compare_op` field. Matches DETV-02's determinism-guard framing (fixed, predictable pipeline behavior) and keeps the validation surface narrow; no current requirement calls for reverse-Z or other compare-op tricks.

### render_target / Vertex Layout Ergonomics
- **D-15:** **All `render_target` fields are explicitly required** in the job definition — color format, depth format, dimensions, and clear values. No schema defaults. (This was a deliberate override of the initial recommendation toward defaults — user chose explicitness over lower per-job boilerplate.)
- **D-16:** `vertex_layout` is a small array of `{name, format, offset}` entries, reusing the existing `pass_io_binding` `source:`/`target:` prefix-notation convention as the reference mechanism for *which* buffer feeds the binding (per FEATURES.md's established pattern — no new binding DSL invented). **Stride is auto-computed** from the tightly-packed sum of attribute sizes/offsets, not an explicit required field — removes a field and a class of job-author error (explicit stride disagreeing with the actual attribute layout).
- **D-17:** Index buffer type (`uint16`/`uint32`) is **schema-configurable** per render pass via a field on the vertex/index binding — real jobs will span both small meshes (uint16, half the index-buffer size) and large meshes (uint32, needed past 65535 vertices), not fixed to one type.
- **D-16 Amendment (resolved during plan revision, 2026-07-30):** D-16's "which buffer feeds the binding" reference mechanism was under-specified in the original schema draft — `vertex_layout_entry` only carried `{name, format, offset}`, with no field naming which buffer actually supplies the attribute data (SCHEMA-02 requires vertex/index buffer *bindings*, not just layout). **Resolved:** a new sibling definition, `vertex_buffer` (`{source: string}`, `source` required, reusing `pass_io_binding`'s exact `^(input|output|internal|parameter):[a-zA-Z][a-zA-Z0-9_]*$` prefix-notation regex verbatim per D-16), is added as a new `pass.vertex_buffer` property — one buffer binding feeds all of a render pass's `vertex_layout` entries (each entry describes one attribute's `{name, format, offset}` within that single bound buffer), mirroring `index_buffer`'s existing one-buffer-per-binding shape rather than a per-attribute source. Empirically re-verified end-to-end: the extended schema (with `vertex_buffer` added, `pass.allOf`'s render branch requiring `["render_shader", "render_target", "vertex_buffer"]`) regenerates cleanly via this machine's installed quicktype v23.2.6 — `generated/VertexBuffer.hpp` produces a plain (non-`boost::optional`) required `source` member (matching `PassIoBinding.hpp`'s existing regex-constrained-string-field convention), and `Pass.hpp` gains a `boost::optional<VertexBuffer> vertex_buffer` member/accessor alongside the other render-only optional fields.

### D-11 Amendment — `shader` stays a compute-only property name; render's multi-stage shape is a sibling property (resolved during plan revision, 2026-07-30)

D-11/SCHEMA-03 was originally read during planning as requiring the schema property literally named `shader` on `pass` to be replaced/re-typed per pass type (a discriminated shape keyed on `pass.type`). This amendment records why that literal reading is not achievable with this project's actually-installed quicktype toolchain, and locks in the design that is achievable.

**Empirical verification performed during this revision** (this machine's installed quicktype v23.2.6, exact CLI invocation from `.github/workflows/generate-headers.yml`, run against throwaway scratch schemas, not the real committed schema):
- **Spike 1 — nested `allOf[].if.then.properties` override of `pass.shader`** (redefining the *same* property name one level deeper than the existing `pass.allOf` block, keyed on `pass.type` per branch): the `shader` property is silently DROPPED from the generated `Pass` class entirely — it never appears as a member at all, in either branch.
- **Spike 2 — root-level `oneOf` on the `pass` definition itself** (two full object alternatives, each `required`-discriminated by a `type` const, each independently declaring a `shader` property with a different `$ref`): quicktype does **not** produce a discriminated union/tagged variant for the C++ target. It merges both `oneOf` alternatives into a single `Pass` class, AND separately merges the two `$ref`-ed shapes themselves (`shader_config`'s `source` field and `render_shader_config`'s `stages` field) into one ambiguous class carrying both fields, both `boost::optional` — the two shapes become structurally indistinguishable.
- **Spike 3 — fully disjoint-field `oneOf`** (two alternatives sharing zero property names, to rule out "overlap" as the cause of the merge): identical merge-into-one-class behavior. Re-ran with `--no-combine-classes` passed (a flag that sounded relevant): no change — that flag governs a different, unrelated unification pass, not `oneOf`/`allOf.then` handling.
- **Conclusion:** quicktype v23.2.6's C++ (`--lang cpp`) target unconditionally collapses JSON-Schema `oneOf`/`allOf.then`-based per-branch redefinition of the same object property into a single merged class, for every construction tried (nested-then, root-oneOf-with-discriminant, disjoint-oneOf, with and without `--no-combine-classes`). There is no schema construction, using the actually-installed quicktype toolchain, that preserves `pass.shader` as a real, distinctly-typed member per pass type at the C++ codegen level — and the closest attempt (Spike 2) is actively worse than doing nothing, since it silently merges two structurally different shapes into one ambiguous class rather than either preserving or cleanly rejecting the split.

**Amended design (locked):** `shader_config` (property name `shader` on `pass`) remains **compute-only** and structurally unchanged (`source`/`type`/`entry_point`/`uniforms`), narrowed per D-10. A **new, separate, sibling top-level property**, `render_shader` (`$ref: render_shader_config`), carries D-11/D-12's `stages` array + shared `uniforms` for render passes. Both `shader` and `render_shader` are schema/codegen-level `boost::optional` on `Pass` — matching this schema's only proven-working presence-enforcement pattern: `ProcessingManager::CheckProcessValidity()` performs the actual pass-type-specific presence check in C++ (see plan 02-04), not the schema's `allOf`/`if`/`then` conditional composition, which quicktype's generated `from_json` never enforces regardless of how it is written (confirmed: `pass.allOf`'s existing `required: ["model"]`/`required: ["shader"]` entries already have zero effect on today's generated code — `Pass::model`/`Pass::shader` are `boost::optional` unconditionally).

This satisfies SCHEMA-03's substance in full — a render pass can declare a complete, multi-stage vertex+fragment shader pipeline entirely through the schema — while working within quicktype's actual, empirically-confirmed capabilities, rather than a literal same-property-name reading that this toolchain cannot produce. Resolved autonomously during plan revision under this project's yolo-mode planning authority; recorded here rather than left as a silent, unconfirmed deviation. See `02-01-PLAN.md`'s `<objective>` for the resulting task-level design and `02-04-PLAN.md` for the `get_render_shader()`-based consumer wiring this amendment makes load-bearing.

### Open Question 3 Resolution — `pipeline_state` field defaults (resolved during plan revision, 2026-07-30)

02-RESEARCH.md's Open Question 3 flagged that `pipeline_state`'s required-vs-default posture was not explicitly locked the way D-15 locks `render_target` as all-required, and recommended surfacing it rather than silently picking one. **Resolved:** `pipeline_state`'s four fields (`topology`, `cull_mode`, `front_face`, `depth_test`) each carry a schema-level `default` and are **not** required — unlike `render_target`. Rationale: D-15's all-required, no-defaults stance was a deliberate user override specifically for `render_target`'s semantically load-bearing, job-specific values (color/depth format, dimensions, clear values) with no universally "safe" default. `pipeline_state`'s curated v1 fields instead describe conventional rasterization defaults (triangle list, back-face cull, CCW winding, depth test on) that match the overwhelmingly common case; a job author who needs non-default behavior states it explicitly, and adding/adjusting a schema default later is a non-breaking, additive change for existing job definitions — unlike D-15's explicit-required fields, where a missing field is a deliberate, hard validation failure by design. This does not need the same user sign-off bar D-15's explicitness override required, since defaulting here forecloses nothing (a job can always override the default) and carries no correctness risk from being "wrong."

### Claude's Discretion
- Exact JSON field/object naming beyond what's specified above (e.g. whether the array is literally named `stages`, exact enum string casing) — left to planner/researcher as long as the shapes in D-08 through D-17 are honored.
- Exact `CheckProcessValidity()` error message text for a render pass presenting `hlsl`/`metal` (now schema-invalid, will fail generic schema validation before reaching render-specific C++ code) or an unsupported pipeline-state enum value.
- Exact quicktype output structure/class names for the new nested types (`RenderTarget`, `VertexLayoutEntry`, `PipelineState`, `ShaderStage` or equivalent) — quicktype's existing pascal-case/underscore-case conventions (per `generate-headers.yml`'s invocation) apply automatically; no new convention decision needed.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & Roadmap
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` — SCHEMA-01..05, SHADER-01..03 locked requirements for this phase. Note: SHADER-01's "GLSL shader source is compiled to SPIR-V in-process via a vendored shaderc toolchain" stands as originally written (D-08 confirms shaderc); the schema-enum narrowing in D-10 (drop metal/hlsl) is a refinement discovered during this discussion, not a requirements change.
- `.planning/workstreams/sgproc-render/ROADMAP.md` — Phase 2 success criteria, phase-ordering rationale (independently developable in parallel with Phase 1)

### Research
- `.planning/workstreams/sgproc-render/research/SUMMARY.md` — Decision Flags #2 (shaderc vs glslang, resolved here as D-08/D-09/D-10) and #3 (shader_config.type "spirv" already load-bearing, resolved as SHADER-03 stands, D-10 narrows the enum around it)
- `.planning/workstreams/sgproc-render/research/STACK.md` — shaderc/glslang/SPIRV-Tools license and version grounding (shaderc v2024.3, Apache-2.0; glslang/SPIRV-Tools permissive)
- `.planning/workstreams/sgproc-render/research/PITFALLS.md` — Pitfall 6 (unvalidated SPIR-V driver-crash vector, `spirv-val` mandatory), glslang linker-pass crash class on malformed input (informed D-08's crash-surface discussion)
- `.planning/workstreams/sgproc-render/research/ARCHITECTURE.md` — `shader_config`/schema integration points, buffer-slot reinterpretation convention
- `.planning/workstreams/sgproc-render/research/FEATURES.md` — schema field-shape recommendations (`vertex_layout` reusing `pass_io_binding` convention, shader-stage array shape) that D-11/D-16 build directly on

### Project Context
- `.planning/PROJECT.md` §"Workstream: sgproc-render" — issue #7 constraint framing, hand-rolled-Vulkan-only restart rationale
- `.planning/workstreams/sgproc-render/phases/01-vulkan-foundation-dispatch-plumbing/01-CONTEXT.md` — Phase 1 decisions this phase builds alongside (vk-bootstrap adopted, D-01; shared Vulkan init-lock, D-04/D-05; ValidationLayers deferred to v1.x, D-07)

### Source of Truth (current state, pre-this-phase)
- `SuperGenius/SGProcessingManager/gnus-processing-schema.json` — `pass` (lines 153–223), `shader_config` (lines 326–356, single-source-only today, `type` enum currently `["glsl","hlsl","metal","spirv"]`), `pass_io_binding` (lines 357–376) — the exact objects this phase extends
- `SuperGenius/SGProcessingManager/generated/ShaderConfig.hpp`, `ShaderType.hpp`, `Pass.hpp`, `PassIoBinding.hpp` — current quicktype output shape, to be regenerated (never hand-edited) once the schema changes land
- `SuperGenius/SGProcessingManager/.github/workflows/generate-headers.yml` (lines 27–43) — the quicktype regeneration command/CI trigger (`--src-lang schema --lang cpp ... --boost --source-style multi-source`), the only existing regeneration mechanism (no local script/Makefile target)

No external ADRs/specs beyond the above — requirements fully captured in REQUIREMENTS.md and this discussion.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `pass_io_binding`'s `source:`/`target:` prefix-notation pattern (`input:`/`output:`/`internal:`/`parameter:`) — reused as-is for referencing which buffer feeds a `vertex_layout` entry (D-16); no new binding DSL needed.
- `shader_config.uniforms`' existing `data_type` enum already includes `mat4` — no schema change needed to represent MVP-matrix-style uniforms.
- Existing `ExternalProject_Add` vendoring convention in `thirdparty/build/CommonTargets.cmake` (see the `Vulkan-Headers`/`Vulkan-Loader` block, lines ~362–392) — the pattern shaderc's vendoring should follow. `vk-bootstrap` is already vendored via this same convention (Phase 1), confirming the pattern works for a small MIT-licensed helper library; shaderc is larger (bundles glslang+SPIRV-Tools as its own nested submodules) and will need `git submodule update --init --recursive` scoped to its path plus explicit `SHADERC_SKIP_TESTS`/`SHADERC_SKIP_EXAMPLES` CMake cache args (see STACK.md's illustrative `ExternalProject_Add` block).

### Established Patterns
- quicktype regeneration is CI-triggered only (`generate-headers.yml`, on push to `gnus-processing-schema.json`) — no local regen script exists. Planner should account for how/when regeneration actually runs during implementation (CI-only vs. also documenting a local `quicktype` invocation for dev iteration).
- `generated/` is produced with `--boost --source-style multi-source --type-style pascal-case --member-style underscore-case` — new nested types (stages array entries, render_target, vertex_layout entries, pipeline state) will follow this same convention automatically; no new convention to design.
- `ProcessingManager.cpp:153-161`'s current render-pass validation only checks `pass.get_shader()` is present — this is the exact site `CheckProcessValidity()`'s expanded validation (new render_target/vertex_layout/pipeline-state field presence checks, `metal`/`hlsl`-now-schema-invalid handling, and the `spirv-val` gate wiring) will extend, per SHADER-02/SHADER-03 and SCHEMA-01..04.
- `ProcessingManager.cpp:864-871` currently treats the render pass's single shader as a "model file" URL (`p.get_shader().value().get_source()`) — this call site will need updating once `shader` becomes a `stages` array (D-11) rather than a single source field.

### Integration Points
- `gnus-processing-schema.json:326-356` (`shader_config`) — the exact object gaining the `stages` array (D-11) and losing `metal`/`hlsl` from its `type` enum (D-10); this same object is also used by `compute` pass type (out of scope this milestone — confirm during implementation that compute passes are unaffected by the `stages`-array restructuring, or that the restructuring is render-specific via an `allOf`/`if-then` schema branch).
- `gnus-processing-schema.json:153-223` (`pass`) — gains new render-specific fields: `render_target`, vertex/index buffer bindings (`vertex_layout` + `pass_io_binding` references per D-16/D-17), and pipeline state (D-13/D-14).

</code_context>

<specifics>
## Specific Ideas

No UI/UX-style references — this is schema/backend infrastructure. The concrete, grounding specifics from discussion (schema field shapes, enum value sets, default-vs-required stance) are recorded above in `<decisions>` and `<code_context>`.

</specifics>

<deferred>
## Deferred Ideas

- **Real HLSL support via DirectXShaderCompiler (DXC)** — considered during the toolchain discussion (D-09), explicitly deferred rather than built now. `hlsl` removed from the schema enum entirely rather than left as a rejected-but-present value; revisit (re-add to the enum + vendor DXC) if HLSL demand materializes in a future milestone.
- **Configurable depth compare_op** (reverse-Z, equal-depth tricks) — considered during pipeline-state discussion (D-14), explicitly fixed at `less` instead. Revisit if a future render pass genuinely needs it.
- **Full Vulkan pipeline-state enum surface** (all topology/cull/front-face variants) — considered and scoped down to the curated v1 subset (D-13). The chosen enum shape is additive-extensible, so this isn't blocked, just not built until a concrete need appears.

</deferred>

---

*Phase: 2-Schema Extension & Shader/SPIR-V Validation Pipeline*
*Context gathered: 2026-07-30*
</code_context>
