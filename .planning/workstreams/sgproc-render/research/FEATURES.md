# Feature Research

**Domain:** Headless Vulkan render-pass execution inside a distributed compute node (SGProcessingManager `PassType::RENDER`)
**Researched:** 2026-07-29
**Confidence:** HIGH (Vulkan mechanics — canonical spec/tutorial/community sources, cross-checked) / MEDIUM (SPIR-V toolchain choice, determinism guidance — established practice, not GNUS-specific verification)

This is not a consumer feature landscape — it's an engineering capability landscape for making ONE schema-declared render pass execute correctly, deterministically, and integrate with existing SGProcessingManager plumbing. "Table stakes" = required for issue `SGProcessingManager#7` to be satisfied at all. "Differentiators" = correct-but-deferrable robustness. "Anti-features" = the explicit out-of-scope items already locked in `.planning/PROJECT.md` and the archived `REQUIREMENTS.md` Out-of-Scope table, restated here so the roadmap doesn't accidentally reintroduce them.

## Feature Landscape

### Table Stakes (Required for issue #7 to be satisfied)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Independent `VkInstance`/`VkPhysicalDevice`/`VkDevice` creation, headless (no `VK_KHR_surface`/swapchain extensions requested) | Issue #7 mandates "own independent VkInstance/VkDevice," not sharing MNN's internal Vulkan context; headless because this is a compute node with no display, ever | MEDIUM | No windowing extensions needed at all — this is the one place hand-rolled Vulkan is genuinely simpler than a graphics-engine tutorial, which usually assumes a window. Physical device selection is a straight "pick a device with `VK_QUEUE_GRAPHICS_BIT`" — no presentation-support query needed. Confirmed against `SaschaWillems/Vulkan` headless example (canonical community reference, HIGH confidence) and the Vulkan spec. |
| Vulkan init coexistence with MNN's existing (fully internal, un-exposed) Vulkan usage in the same process | MNN already opens Vulkan for its own inference backend; two independent `VkInstance`s in one process is legal per spec but driver-level global state (e.g. validation layers, loader ICD enumeration) is a real shared-resource concern | MEDIUM | Not a "3-tier fallback lock" like the archived bgfx design — just: confirm the loader/ICD enumeration path used by MNN's Vulkan init doesn't assume single-instance-per-process, and that render-processor teardown properly destroys its own `VkDevice`/`VkInstance` without touching MNN's. This needs a real concurrent-init smoke test regardless of which processor initializes first. |
| Offscreen framebuffer: color attachment (matches schema output format, e.g. RGBA8) + depth attachment, `VkRenderPass` + `VkFramebuffer` | Standard minimal render pass has depth testing; color output is what gets read back and hashed | LOW-MEDIUM | Depth attachment can be omitted only if the schema explicitly declares a 2D pass with no depth test — but a "single triangle" or general 3D-geometry render pass needs it. Recommend making depth optional per-pass (schema flag), defaulting to on. |
| Vertex + index buffer upload (`VkBuffer` + `VkDeviceMemory`, host-visible staging → device-local, or host-visible-and-coherent directly for a batch job where perf doesn't matter) | Table-stakes geometry input mechanism; every Vulkan render tutorial treats this as non-optional | LOW-MEDIUM | For a single submit-once-return-hash job, skipping the staging-buffer-to-device-local-copy optimization (i.e., just using a host-visible+coherent buffer directly) is legitimate — this is not a real-time engine, throughput doesn't matter, and it removes a whole synchronization step. Recommend this simplification explicitly for v1. |
| Multi-stage shader pipeline: vertex + fragment `VkShaderModule` (SPIR-V bytecode) → single `VkPipeline` | Schema already models `shader_config` as single-stage; render needs at minimum vertex+fragment, per issue #7 and `PROJECT.md` | MEDIUM | Vulkan pipelines are otherwise immutable/monolithic by design — this pushes pipeline-state fields (topology, cull mode, winding order, depth-test enable) into schema-declared, pipeline-creation-time config, not runtime state changes. Matches how `docs.vulkan.org` describes the pipeline model (HIGH confidence, primary spec doc). |
| GLSL → SPIR-V compilation at job-load time (not shipped as SPIR-V by the job author) | `PROJECT.md` explicitly commits to "shaders authored as GLSL, compiled to SPIR-V" via glslang/shaderc, not any engine-specific dialect | MEDIUM | **Confirmed gap**: neither `glslang` nor `google/shaderc` nor `SPIRV-Tools` are currently vendored anywhere under `thirdparty/` (checked: only `Vulkan-Headers`, `Vulkan-Loader`, `MoltenVK` exist there today). This is new vendoring that PROJECT.md's context note ("confirm during research whether a SPIR-V compiler toolchain needs adding") explicitly asked to resolve — **answer: yes, it needs adding.** Recommend `glslang` alone (not the heavier `shaderc` wrapper) — shaderc exists specifically to wrap glslang with a nicer API/build-system story, but glslang's own C++ API (`glslang::TShader`/`TProgram`) is sufficient to compile GLSL source to SPIR-V in-process with no extra dependency (shaderc pulls in glslang + SPIRV-Tools transitively anyway, so it's strictly more to vendor for no functional gain in this narrow use case). Compiling at job-load time (not shipped precompiled) also gets free malformed-shader rejection before any GPU call — validate-then-fail-fast, satisfying a lighter version of what the archived design called `DETV-02`. |
| Uniform/parameter binding (MVP matrices etc.) via `VkDescriptorSetLayout`/`VkDescriptorSet` + uniform buffer (`VkBuffer` with `VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT`), sourced from the existing `shader_config.uniforms` schema block | Schema already has a `uniforms` object under `shader_config` with a `source` field supporting `parameter:` prefix notation — this is the existing mechanism to reuse, not reinvent | MEDIUM | This is genuinely the most Vulkan-boilerplate-heavy step (descriptor pool, layout, set allocation, `vkUpdateDescriptorSets`) but has no simpler alternative in raw Vulkan — push constants could replace a *small fixed* uniform block (e.g. just an MVP mat4) with much less code, and are worth considering as the v1 mechanism given the "single schema-declared pass" scope (see Differentiators). |
| Draw call submission + CPU/GPU sync via fence (`vkQueueSubmit` with a fence, `vkWaitForFences`), not semaphore-only (no presentation queue to hand off to) | This is a discrete submit-once-return-hash batch job (per `PROJECT.md`/archived Out-of-Scope table) — a single-fence wait-until-done is correct and simpler than a real-time engine's semaphore-chained frames-in-flight pattern | LOW | Confirmed against `vkguide.dev`/`vulkan-tutorial.com` patterns (MEDIUM-confidence tutorials, consistent with primary spec). No frames-in-flight, no swapchain-image-acquire semaphore — this entire category of real-time-engine complexity doesn't apply here. |
| Readback: image layout transition (`VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL`) → `vkCmdCopyImageToBuffer` (or `vkCmdCopyImage` to a linear-tiled staging image, then map) → host-visible/coherent buffer → `vkMapMemory`/`memcpy` | This is the actual "get pixels back to CPU to hash" mechanism; canonical technique confirmed in `SaschaWillems/Vulkan`'s `renderheadless.cpp` example (HIGH confidence — widely-cited reference implementation, matches spec-described barrier requirements) | MEDIUM | Requires correct image memory barriers around the copy (color-attachment-output → transfer-src, and a final transfer-dst-optimal → general/host-read barrier on the destination if using a linear staging image) — this is the single area where a naive implementation is most likely to introduce subtle bugs (wrong `VkAccessFlags`/`VkPipelineStageFlags` in barriers causing readback races). Direct `vkCmdCopyImageToBuffer` into a host-visible buffer skips one image-layout hop vs. the staging-image-then-map pattern and is simpler for a one-shot job. |
| Deterministic uniform/vertex-buffer initialization — no reads of uninitialized `VkDeviceMemory` | `VkDeviceMemory` allocations are **not** zero-initialized by the Vulkan spec (implementation-defined contents) — any shader or buffer region not explicitly written before use is a genuine non-determinism source, not a hypothetical one | LOW | Concrete guard: every buffer (vertex, index, uniform, and the color+depth attachments themselves) must be fully written/cleared before the pipeline reads or the render pass begins (`VkAttachmentLoadOp::VK_ATTACHMENT_LOAD_OP_CLEAR` with an explicit, schema-or-default-sourced clear color/depth value — never `VK_ATTACHMENT_LOAD_OP_DONT_CARE` for a job whose output gets hashed). |
| Disable/avoid non-deterministic driver optimization paths for hash comparison | Same-node repeat-execution bit-exact hashing (the project's determinism bar, scoped explicitly to same-node/same-hardware — no cross-vendor claim) is achievable but not automatic | LOW-MEDIUM | Concrete guards for v1: (1) fixed, explicit shader-stage floating-point precision — avoid GLSL `mediump`/relaxed-precision qualifiers, use `highp` explicitly if targeting mobile-class Vulkan drivers where default precision is implementation-defined; (2) disable multisampling (`VkPipelineMultisampleStateCreateInfo::rasterizationSamples = VK_SAMPLE_COUNT_1_BIT`) — this is already a locked out-of-scope item (MSAA) and doubles as a determinism guard, not just a scope-narrowing one; (3) avoid any use of `VK_EXT_shader_atomic_float`/parallel-reduction-style shaders where floating-point summation order is GPU-scheduler-dependent (not applicable to a simple vertex+fragment raster pass, but worth stating as a boundary — determinism claims do NOT extend to future compute-shader-style render passes without re-verification); (4) driver/ICD version pinning is implicitly required — "same node" for repeat-execution determinism means same driver build too, not just same hardware, though this is an operational constraint outside this feature's code, not something the render pass itself can enforce. |
| `ParseBlockSize()` type-guard fix | Ground truth: `ProcessingManager.cpp` line ~649 calls `pass.get_model().value()` unconditionally for every pass in the definition — a render (or compute) pass has no `model` field (`optional` per schema/generated headers), so `.value()` on an empty `optional` is undefined behavior/throws — this is a pre-existing crash bug, not new work, but it blocks RENDER passes from ever reaching `Process()` today | LOW | Direct code fix: guard with `pass.get_type() == PassType::INFERENCE \|\| pass.get_type() == PassType::RETRAIN` (or equivalent `if (pass.get_model())` check) before dereferencing. Table stakes because without it, adding a render pass to any processing definition crashes `ParseBlockSize()` before `Process()` is ever called. |
| `PassType`-based dispatch added to `ProcessingManager::Process()` | Ground truth: `Process()` today only ever looks up a processor via `SetProcessorByName(static_cast<int>(processing_.get_inputs()[index].get_type()))` — a `DataType`-keyed factory lookup. There is no branch anywhere that inspects `pass.get_type()` to route to a different processor family | MEDIUM | This is the actual "hook-in point" for `RenderProcessor`. Minimal-viable approach: before the existing `DataType` dispatch, check `pass.get_type() == PassType::RENDER` and route to a `RenderProcessor` implementing the same `IProcessingProcessor`/`StartProcessing(...)`-shaped interface the MNN processors already implement, so the rest of `Process()` (output-saving, hashing) is untouched. |
| `CheckProcessValidity()` actually validates render passes | Ground truth: `case PassType::RENDER: break;` today — accepted with zero checks, unlike `INFERENCE` which validates `get_model()` is present | LOW | Minimal parity fix: require `pass.get_shader()` present (schema already marks `shader` required for `render`/`compute` passes via the `allOf`/`if`/`then` block — the JSON Schema enforces it at parse time already, but `CheckProcessValidity()` should still surface a clear domain error rather than relying solely on schema-level `from_json` throwing). |
| Output written as `texture2D` through the existing `pass_io_binding` → `ProcessingResult` output-buffer mechanism | Ground truth: `Process()`'s existing output path (lines ~695-820) is generic over `processResult.output_buffers` (a `pair<vector<string> names, vector<vector<char>> data>`) and `processResult.hash` — it does not care which processor produced the bytes | LOW (for the render feature) / MEDIUM (implementing `RenderProcessor::StartProcessing` correctly) | This is the single most important integration finding: **no changes are needed to the output/save/hash path at all.** `RenderProcessor` just needs to populate `ProcessingResult.output_buffers` (raw pixel bytes read back from the GPU, named per `pass_io_binding`/`outputs[]`) and `ProcessingResult.hash`, exactly like `MNN_Image` etc. already do. `FileManager::SaveASync` and the IPFS dual-save logic are completely reused, unmodified. |

### Schema Fields — Table Stakes vs. Speculative

Current `gnus-processing-schema.json` already has: `pass.type` enum including `"render"`, `pass.shader` (`shader_config`: `source`, `type` enum `glsl/hlsl/metal/spirv`, `entry_point`, `uniforms`), `pass.inputs`/`pass.outputs` (`pass_io_binding`: `name`, `source`, `target`), and a separate `pass.data_transforms` array for post-processing. None of this today supports a *second* shader stage, render-target dimensions, or vertex/index buffer bindings — `shader_config` is singular and generic (shared with `compute`).

| Schema field (new/extended) | Table stakes? | Notes |
|---|---|---|
| Render target dimensions (width/height) + color format + depth format/enable | **Table stakes** | No existing field carries this for a render pass; `io_declaration.dimensions`/`.format` exist but describe *input/output data*, not an intermediate framebuffer. Needs a new `render_target` (or similarly named) object on the `pass`, scoped to `type: render` only. |
| Vertex buffer binding (source `pass_io_binding`-style reference + vertex layout: attribute count/types/offsets/stride) | **Table stakes** | Nothing today expresses vertex attribute layout at all. Minimal viable shape: reuse `pass_io_binding`'s `source`/`target` prefix-notation pattern for *which* buffer, plus a small new `vertex_layout` array (`{name, format, offset}`) — do not invent a whole new binding DSL beyond what's needed to build a `VkPipelineVertexInputStateCreateInfo`. |
| Index buffer binding (+ index type: uint16/uint32) | **Table stakes** | Same reasoning as vertex buffers; can be optional (non-indexed draw is valid Vulkan) but the field must exist since indexed geometry is the common case. |
| Second shader stage (fragment, alongside existing single `shader.source`) | **Table stakes** | `shader_config` needs either an array of `{stage, source, entry_point}` or two named fields (`vertex_shader`/`fragment_shader`) replacing the single `source` for `type: render` specifically (compute passes stay single-stage). Prefer an array shape — it composes with future stages (geometry/tessellation) without another schema break, even though those are not needed for v1. |
| Pipeline state: primitive topology, cull mode, front-face winding, depth-test enable | **Table stakes** | Small enum-valued fields, not point of speculation — these are exactly what `VkPipelineInputAssemblyStateCreateInfo`/`VkPipelineRasterizationStateCreateInfo`/`VkPipelineDepthStencilStateCreateInfo` require to build a valid pipeline. Recommend narrow enums (e.g. `topology: triangle_list \| triangle_strip \| line_list \| point_list`; `cull_mode: none \| front \| back`; `winding: cw \| ccw`) rather than exposing the full raw Vulkan enum surface. |
| Uniform/parameter bindings (MVP matrices etc.) | **Already exists** — `shader_config.uniforms` | Reuse as-is; extend only if a render-specific uniform type (mat4) isn't already representable — the schema's `data_type` enum already includes `mat4`, so no change needed here. |
| Clear color / clear depth value | **Table stakes**, small | Needed to satisfy the determinism guard above (`LOAD_OP_CLEAR` needs an explicit value) — a small addition, easy to miss if not called out explicitly. Default to a fixed value (e.g. black/1.0) if the schema author omits it, but the *mechanism* (explicit clear, not don't-care) must exist regardless. |
| Blend mode / alpha blending config | **Speculative — not needed for v1** | Order-dependent blending directly conflicts with the determinism goal and isn't required by issue #7. Matches the archived design's own `BLEND-01` v2-deferred item — still correctly deferred under the new hand-rolled-Vulkan scope. |
| Multiple render targets (MRT) | **Speculative — not needed for v1** | A single schema-declared render pass producing one `texture2D` output has no MRT need. Archived design's `MRT-01` deferral still applies. |
| Texture sampling from external input (samplers/combined-image-samplers) | **Speculative — not needed for v1** | No stated requirement references sampling an *input* texture within the render pass (only vertex/index geometry + uniforms in, one texture out). Don't build descriptor infrastructure for sampled images until a concrete job needs it — this would otherwise silently drag in far more Vulkan surface (samplers, image layouts for `SHADER_READ_ONLY_OPTIMAL`, combined-image-sampler descriptor types) than the narrow scope requires. |
| Multi-pass / post-processing shader chains (render-to-texture feeding another render pass) | **Speculative — not needed for v1** | `data_transforms` (existing, CPU-side, already schema-present) is the correct place for post-processing per issue scope, not a second GPU pass. Archived `MPASS-01` deferral still applies. |
| Instancing | **Speculative — not needed for v1** | No stated use case for this narrow single-pass job needs instanced draws (`vkCmdDrawIndexed` non-instanced form is sufficient). Archived `INST-01` deferral still applies. |
| Compute/inference ↔ render interop (MNN tensor → Vulkan buffer bridging) | **Speculative — explicitly deferred**, and arguably a separate feature entirely | Archived `INTEROP-01`. Nothing in issue #7 or `PROJECT.md`'s v1.0 target features asks for this; the render pass's vertex/uniform inputs come from `pass_io_binding`-resolved job inputs (files/CIDs), same as every other pass type today, not from another pass's live GPU buffer. |

### Differentiators (Correct but deferrable robustness — v1.x candidates, not launch blockers)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Push constants instead of a uniform-buffer + descriptor-set for the common small-MVP-matrix case | Removes descriptor pool/layout/set boilerplate entirely for the majority case (one or two 4x4 matrices); push constants have a guaranteed-available minimum size (128 bytes per spec) which comfortably fits an MVP matrix (64 bytes) or MVP+normal-matrix | LOW (once decided) | Worth deciding explicitly during phase planning rather than defaulting to full descriptor-set machinery "because that's how the tutorials do it" — for a single schema-declared pass with a small, known uniform set, push constants are less code and fewer failure modes. Only fall back to descriptor sets if a job needs a uniform block that would exceed push-constant limits. |
| Explicit Vulkan validation-layer instrumentation in debug/CI builds | Catches barrier/sync mistakes (the most likely bug class per the readback discussion above) during development rather than as silent GPU-driver-dependent corruption | LOW-MEDIUM | Matches archived `VVL-01` (`Vulkan-ValidationLayers` vendoring) — still a reasonable v1.x add, not v1-blocking; correctness can be manually verified for the first working pass without it, but it materially de-risks any *second* render pass definition added later. |
| Structured Vulkan error surfacing (map `VkResult` failures to the existing `ProcessingManager::Error` outcome enum with actionable messages) | Consistent with how MNN processor failures presumably surface today (`m_logger->error(...)` + `outcome::failure`) | LOW | Straightforward but worth calling out since a raw Vulkan error is often just an integer enum with a cryptic name — mapping the handful of load-bearing failure points (device creation, shader compile, pipeline creation, fence timeout) to clear log messages pays for itself the first time a job author submits a malformed render pass. |

### Anti-Features (Locked out of scope — restated to prevent re-drift)

These come directly from `.planning/PROJECT.md`'s "sgproc-render" section and the still-valid rows of the archived `REQUIREMENTS.md` Out-of-Scope table. Restated here because this is exactly the kind of scope that "looks reasonable" in a generic Vulkan-features research pass and must not silently creep back in.

| Feature | Why it looks appealing | Why it's out of scope here | Alternative |
|---------|------------------------|------------------------------|-------------|
| OpenGL backend / hardware fallback tier | Broader hardware compatibility on Linux without a real Vulkan driver | Issue #7 explicitly mandates reusing the existing Vulkan stack only, no new GPU backend; this was the core flaw in the archived bgfx design (itself a new backend-abstraction layer) | Hard-fail with a clear error if no suitable Vulkan physical device is found — this is an explicit issue-#7 requirement, not a gap to patch over |
| SwiftShader / CPU software Vulkan fallback | Lets CI/headless runners without real GPU hardware exercise the render path | Explicitly excluded by both `PROJECT.md` and the milestone context ("no OpenGL, no SwiftShader, no CPU/software rendering fallback anywhere in scope") | CI either runs on GPU-capable runners for render-path tests, or the render path's tests are gated/skipped where no Vulkan device is present — a CI/infra decision, not a feature to build |
| Any hardware/software multi-tier fallback chain (of any kind, not just the two above) | Feels like resilience/robustness | Directly contradicts the "own independent VkInstance/VkDevice... no new GPU backend/engine" mandate — a fallback chain is itself the abstraction layer the issue says not to build | Single explicit Vulkan hardware path; if unavailable, the job fails loudly |
| Windowed/interactive rendering, swapchain, VSync | "Might as well support previewing renders" | This is a headless distributed compute node — there is no display surface, ever, in any deployment topology | N/A — not a real requirement anywhere in the project |
| Continuous frame-pacing render loop | Feels like the "normal" way rendering works | This is a discrete submit-once-return-hash batch job, identical in shape to how inference/retrain passes already work | One `vkQueueSubmit` + one fence wait per job execution |
| Shader hot-reload | Nice developer-experience feature in game-engine contexts | No development-time iteration workflow exists for job-supplied shaders in a distributed compute job context | N/A |
| Full 3D-engine surface (skinning, PBR, scene graphs) | "As long as we're doing Vulkan, why not build it properly" | Out of scope for a single schema-declared render-to-texture pass; this is a hand-rolled minimal pipeline, not an engine | N/A — if a future job genuinely needs skinning/PBR, that's new schema + new pipeline features scoped at that time, not speculative infrastructure now |
| MSAA enabled by default | Better visual quality | Directly conflicts with the same-node bit-exact-hash determinism goal (see Table Stakes determinism row) — multisample resolve introduces another non-determinism/driver-optimization surface | `rasterizationSamples = VK_SAMPLE_COUNT_1_BIT` always for v1 |
| Cross-node/cross-vendor/cross-driver exact-hash verification | Sounds more rigorous | Vulkan does not guarantee bit-identical output across GPU vendors/drivers even for identical input — this is a well-documented reproducibility limitation (see determinism search findings), not a solvable engineering gap within this scope | Same-node/same-hardware/same-driver repeat-execution determinism only, exactly as scoped in `PROJECT.md` |

## Feature Dependencies

```
Independent VkInstance/VkDevice init (headless)
    └──requires──> Vulkan physical device selection (graphics-queue-capable)
                       └──requires──> Coexistence check with MNN's existing Vulkan usage (no shared instance)

Offscreen framebuffer (color+depth attachments)
    └──requires──> VkRenderPass + VkFramebuffer creation
    └──requires──> Schema: render_target dimensions/formats (new field)

GLSL shader source (schema-declared, vertex+fragment)
    └──requires──> glslang vendored + integrated (thirdparty/ addition)
                       └──produces──> SPIR-V VkShaderModule(s)
                                          └──requires──> VkPipeline creation (topology/cull/winding from schema)

Vertex/index buffer schema bindings (new field)
    └──requires──> pass_io_binding-resolved input buffers (existing mechanism, reused)
    └──enables──> VkPipelineVertexInputStateCreateInfo construction

ParseBlockSize() type-guard fix
    └──blocks──> any render pass reaching Process() at all (pre-existing crash bug)

PassType-based dispatch in Process()
    └──requires──> ParseBlockSize() fix (else crashes before dispatch is ever reached)
    └──enables──> RenderProcessor invocation

RenderProcessor (draw + readback)
    └──requires──> Uniform/parameter binding (existing shader_config.uniforms, reused)
    └──requires──> Determinism guards (explicit clears, fixed precision, no MSAA)
    └──produces──> ProcessingResult.output_buffers + .hash
                       └──feeds (unmodified)──> existing pass_io_binding output → FileManager::SaveASync → hash path

data_transforms (existing, per-pass array)
    └──optionally post-processes──> RenderProcessor's raw pixel output (CPU-side, no new GPU pass)
```

### Dependency Notes

- **PassType dispatch requires the ParseBlockSize() fix:** confirmed directly in `ProcessingManager.cpp` — `ParseBlockSize()` runs before/independent of `Process()`'s dispatch logic and unconditionally calls `pass.get_model().value()` for every pass. A render pass with no `model` will crash here regardless of how well `Process()`'s new dispatch branch is written, so this fix must land first (or in the same change) — it is a blocking bug fix, not an optional hardening step.
- **RenderProcessor output requires no changes to the save/hash path:** confirmed directly in `ProcessingManager::Process()` (lines ~695-820) — the existing output-saving loop is generic over `ProcessingResult.output_buffers`/`.hash`, keyed only by `outputs[]` names and URL-ness of `source_uri_param`. `RenderProcessor` only needs to conform to the same `IProcessingProcessor`-shaped `StartProcessing(...)` return contract the MNN processors already use.
- **Vertex/index buffer schema fields enable but don't require pass_io_binding changes:** the *existing* `pass_io_binding` prefix-notation (`input:`/`output:`/`internal:`/`parameter:`) is reused as the *reference mechanism* for which buffer feeds a vertex/index binding — only the *shape describing the buffer's layout* (attribute types/strides, index type) is new.
- **glslang vendoring enables SPIR-V compilation but is independent of the Vulkan render/init work:** the shader-compile-to-SPIR-V step could, in principle, be developed and unit-tested in isolation (GLSL string in, SPIR-V bytes out) before any `VkInstance`/pipeline code exists — a natural phase-ordering seam.
- **MSAA-off and explicit-clear conflict with "differentiator" visual-quality features:** anything that later wants multisampling or blending must be evaluated against the determinism requirement first — these are the two clearest "looks like an improvement, actually breaks a core requirement" traps in this feature set.

## MVP Definition

### Launch With (v1) — required to satisfy `SGProcessingManager#7`

- [ ] `ParseBlockSize()` type-guard fix — blocking pre-existing bug, render passes can't reach `Process()` without it
- [ ] Schema extension: `render_target` (dimensions/color format/depth format+enable/clear values), vertex/index buffer bindings + vertex layout, multi-stage (`vertex`+`fragment`) shader array, pipeline state (topology/cull/winding) — quicktype headers regenerated
- [ ] `CheckProcessValidity()` validates render passes have a shader config (parity with existing `INFERENCE` model-check)
- [ ] `PassType`-keyed dispatch added to `ProcessingManager::Process()`, routing `render` to a new `RenderProcessor`
- [ ] glslang vendored under `thirdparty/`, wired into build — GLSL → SPIR-V compile at job-load time (reject malformed shaders before any GPU call)
- [ ] Independent headless `VkInstance`/`VkDevice` init in `RenderProcessor`, coexisting with MNN's internal Vulkan usage (no shared instance, confirmed no crash under concurrent init)
- [ ] Offscreen framebuffer (color+depth), vertex/index buffer upload, pipeline creation, uniform/parameter binding (reusing existing `shader_config.uniforms`), single draw call, fenced wait, image→buffer readback to host-visible memory
- [ ] Determinism guards: explicit `LOAD_OP_CLEAR` with schema/default clear values everywhere, `VK_SAMPLE_COUNT_1_BIT` always, explicit shader precision qualifiers
- [ ] `RenderProcessor` output feeds existing `ProcessingResult` → `pass_io_binding` output → `FileManager::SaveASync` → hash path unmodified
- [ ] End-to-end proof: one real render pass definition executes through the real distributed pipeline, produces a same-node repeat-execution bit-exact-hash-verified output, zero regressions to the existing MNN inference/retrain suite

### Add After Validation (v1.x)

- [ ] Push-constant-based uniform path as an alternative/replacement for descriptor-set uniforms, if the small-MVP-matrix case dominates real usage
- [ ] Vulkan validation layers wired into debug/CI builds (archived `VVL-01`)
- [ ] Structured `VkResult` → `ProcessingManager::Error` mapping with clearer per-failure-point log messages

### Future Consideration (v2+, not this milestone)

- [ ] Multi-pass/post-processing GPU shader chains, MRT, texture sampling from external input, instancing, compute↔render interop, alpha blending — all previously identified in the archived design's v2 backlog and still correctly deferred under the hand-rolled-Vulkan scope
- [ ] Cross-node/cross-vendor tolerance-based verification (only relevant once heterogeneous-hardware verification is actually required)

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| ParseBlockSize() fix | HIGH (blocking) | LOW | P1 |
| Schema extension (render_target/buffers/multi-stage shader/pipeline state) | HIGH | MEDIUM | P1 |
| PassType dispatch in Process() | HIGH | MEDIUM | P1 |
| glslang vendoring + GLSL→SPIR-V compile | HIGH | MEDIUM | P1 |
| Headless VkInstance/VkDevice init + MNN coexistence | HIGH | MEDIUM | P1 |
| Framebuffer + buffers + pipeline + draw + readback | HIGH | HIGH | P1 |
| Determinism guards (clear ops, no MSAA, precision) | HIGH | LOW | P1 |
| Output integration via existing pass_io_binding/hash path | HIGH | LOW (reuse) | P1 |
| Push constants for uniforms | MEDIUM | LOW | P2 |
| Validation layers in CI | MEDIUM | LOW-MEDIUM | P2 |
| Structured Vulkan error mapping | LOW-MEDIUM | LOW | P2 |
| Multi-pass/MRT/sampling/instancing/interop | LOW (no current use case) | HIGH | P3 |
| Cross-node/cross-vendor verification | LOW (not required) | HIGH | P3 |

**Priority key:**
- P1: Must have to satisfy `SGProcessingManager#7` and the v1.0 milestone target features
- P2: Should have, meaningfully de-risks or simplifies P1 work, add when possible without blocking launch
- P3: Explicitly deferred, tracked but not in this milestone's roadmap

## Sources

- `W:\gnus\GeniusNetwork\.planning\PROJECT.md` — sgproc-render workstream section (ground truth for scope/decisions), read directly
- `W:\gnus\GeniusNetwork\SuperGenius\SGProcessingManager\gnus-processing-schema.json` — current schema, read directly (HIGH confidence, primary source)
- `W:\gnus\GeniusNetwork\SuperGenius\SGProcessingManager\src\processingbase\ProcessingManager.cpp` — current dispatch/validation/output code, read directly (HIGH confidence, primary source)
- `W:\gnus\GeniusNetwork\.planning\milestones\ws-sgproc-render-2026-07-29\REQUIREMENTS.md` — archived requirements, Out-of-Scope table rows still valid per current milestone context (cross-referenced, not reintroduced)
- Repo `thirdparty/` submodule listing, checked directly — confirms `Vulkan-Headers`/`Vulkan-Loader`/`MoltenVK` present, no `glslang`/`shaderc`/`SPIRV-Tools` present (HIGH confidence, direct filesystem check)
- [SaschaWillems/Vulkan — renderheadless.cpp](https://github.com/SaschaWillems/Vulkan/blob/master/examples/renderheadless/renderheadless.cpp) and [Headless Vulkan examples blog post](https://www.saschawillems.de/blog/2017/09/16/headless-vulkan-examples/) — canonical headless-render + readback reference (HIGH confidence, widely-cited)
- [Vulkan Documentation Project — Pipelines chapter](https://docs.vulkan.org/spec/latest/chapters/pipelines.html) — primary spec source for pipeline immutability/state model (HIGH confidence)
- [vulkan-tutorial.com — Graphics pipeline / Index buffer chapters](https://vulkan-tutorial.com/Drawing_a_triangle/Graphics_pipeline_basics/Introduction) and [vkguide.dev — pipeline building](https://vkguide.dev/docs/new_chapter_3/building_pipeline/) — MEDIUM-confidence but consistent, widely-used community tutorials
- [google/shaderc GitHub](https://github.com/google/shaderc) and [Android NDK shader compilers doc](https://developer.android.com/ndk/guides/graphics/shader-compilers) — confirms shaderc wraps glslang + SPIRV-Tools transitively (HIGH confidence, official Google/Android docs)
- [NVIDIA/framework-reproducibility determinism discussion](https://github.com/NVIDIA/framework-reproducibility/issues/28) and [NVIDIA Vulkan SC blog](https://developer.nvidia.com/blog/using-vulkan-sc-for-safety-critical-graphics-and-real-time-gpu-processing/) — MEDIUM confidence, general GPU-determinism context (not Vulkan-render-specific, used only to confirm known non-determinism sources are real and well-documented, not GNUS-specific verification)

---
*Feature research for: Headless Vulkan render-pass execution (SGProcessingManager#7)*
*Researched: 2026-07-29*
