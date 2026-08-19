# Phase 17: Render-Path Cross-Hardware Tolerance - Research

**Researched:** 2026-08-19
**Domain:** Vulkan offscreen rendering (RenderProcessor), GLSL shader authoring, cross-hardware floating-point/byte-quantization tolerance, capture/diff empirical tooling
**Confidence:** HIGH (mechanism, wire format, and existing code paths are all directly read from source in this session) / MEDIUM (exact cross-hardware divergence magnitude and byteQuantMode/N values for each new fixture — genuinely unknown until Phase 11-style capture runs happen; this is expected, not a research gap)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**RENDTOL-02 reframe**
- **D-01:** The byte-quantization tolerance mechanism (`ResolveByteQuantMode`/`QuantizeByteBuffer`) already exists (Phase 14) and is already wired into the render path's call site. Phase 17 does not build a new mechanism — it (a) derives real `byteQuantMode` value(s) from this phase's own fixtures' empirical cross-hardware capture data, and (b) proves via a new counter-test that each derived value still catches a deliberately wrong/corrupted result (SC5).

**Fixture technique selection**
- **D-02:** All three roadmap-named techniques are in scope — texturing, blending, and lighting — not just one.
- **D-03:** MSAA is excluded and stays excluded — an architectural hard-block (`processing_processor_render.cpp:1526` hardcodes `VK_SAMPLE_COUNT_1_BIT`, "ALWAYS -- DETV-02, never configurable"). This phase does not reopen DETV-02.
- **D-04:** The three techniques land as **separate fixtures**, not one combined fixture.
- **D-05:** Per-technique implementation scope differs significantly:
  - **Lighting** — zero `RenderProcessor` C++ or schema changes. Pure GLSL fragment-shader math using uniform types already supported (`VEC3`/`VEC4`/`MAT4`, `processing_processor_render.cpp:760-799`).
  - **Blending** — needs a new `pipeline_state` schema field plus real `VkPipelineColorBlendAttachmentState` wiring in `BuildPipeline()`. Currently hardcoded `blendEnable = VK_FALSE` (`processing_processor_render.cpp:1531`); `pipeline_state`'s schema (`gnus-processing-schema.json:549-574`) is "curated, minimal v1" (D-13) with no blend field.
  - **Texturing** — the largest: zero sampler/descriptor infrastructure exists for render-path texture uniforms. `ResolveUniforms` explicitly rejects `TEXTURE1_D`/`TEXTURE2_D`/`TEXTURE3_D`/`TEXTURE_CUBE` (`processing_processor_render.cpp:800-809`) — no `VkSampler`/`VkImageView` creation, no combined-image-sampler descriptor-set-layout entry, no image-upload path exists on the render side today.

**Tolerance derivation methodology**
- **D-06:** Each fixture's `byteQuantMode` value is derived independently via the same binary-search-against-a-counter-test discipline Phase 14's D-10 used for tex3d's `quantScale`. `byteQuantMode` is a discrete `[0,8]` bit-count (9 possible values), not a continuous power-of-two float scale — "one step of margin" means one integer step in `[0,8]`.
- **D-07:** Each fixture gets its own independent tolerance value and its own new counter-test (mirrors `secv01_tex3d_counter_test.cpp`'s dedicated-file-per-fixture precedent, not reusing `secv01_counter_test.cpp`). Falls out of `byteQuantMode` being declared per-job via the existing generic `parameters` array.
- **D-08:** Residual-gap honesty bar mirrors VALD-01/`13-SCOPE-BOUNDARY.md`'s convention: if no value in `[0,8]` closes a fixture's real captured divergence, that gap is documented and characterized honestly — never silently declared passing.

**Capture dataset**
- **D-09:** Reuses Phase 11's exact two-machine dataset — Mac mini (`Fuus-Mac-mini.local`, macOS) and Windows (`Mofu`, Windows) — no new hardware. WSL's `llvmpipe` remains excluded. All three new fixtures get fresh `capture_harness` runs on both machines.

### Claude's Discretion
- Exact new `pipeline_state` schema field name(s)/shape for blend state.
- Exact new schema mechanism for declaring a sampled-image render input (new input `type`, descriptor-set-layout shape, `VkSampler` creation parameters/filtering mode).
- Exact GLSL lighting model (Phong vs. Lambertian-only) and uniform naming.
- Exact new counter-test file names (mirror `secv01_tex3d_counter_test.cpp`'s naming convention — three new files expected).
- Whether ROADMAP.md's Phase 17 SC wording (currently "a fixture," singular) should be updated to reflect three fixtures.
- Whether all three fixtures ship in one wave or are sequenced.

### Deferred Ideas (OUT OF SCOPE)
- **MSAA as a fixture technique** — architecturally hard-blocked by DETV-02 (`VK_SAMPLE_COUNT_1_BIT` unconditional). Not requested by the user; do not reopen.
- **Combining all three techniques into one fixture** — considered, not chosen (D-04 picked separate fixtures instead).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| RENDTOL-01 | A non-trivial render fixture exists (texturing, blending, or MSAA/lighting) exercising real floating-point-heavy render computation | See "Standard Stack" / "Architecture Patterns" — three separate fixtures (texturing, blending, lighting) with concrete GLSL/schema/Vulkan-API designs below; MSAA excluded per D-03 |
| RENDTOL-02 | The render output path has a real schema-configurable tolerance mechanism, proven against real cross-hardware capture data | See "Tolerance Derivation Methodology" — mechanism already exists (Phase 14); this phase's work is deriving+proving per-fixture `byteQuantMode` values against fresh Phase-11-style capture data |
</phase_requirements>

## Summary

RENDTOL-01/02 close a documented, architecturally-inferred (not yet empirically observed) risk: the render path's only tested fixture (`render-pass-happy-path-definition.json`) is an 8x8 constant-color point-list draw that produces zero measurable cross-hardware divergence, so `QuantizeByteBuffer`'s render-path call is still the exact v2.1 byte-identity no-op. This phase's job is entirely mechanical/empirical, not architectural invention: the tolerance mechanism itself (`ResolveByteQuantMode`/`QuantizeByteBuffer`, Phase 14) is complete and already wired at `processing_processor_render.cpp:2096,2209` — nothing there needs to change. What is genuinely new is (1) three render fixtures that actually do floating-point-heavy work, and (2) for two of the three (blending, texturing) real Vulkan/schema infrastructure that does not exist today.

The single most load-bearing finding of this research, not called out explicitly in 17-CONTEXT.md's canonical refs, is that **render pass configuration crosses a hand-rolled binary wire format between two files that must be edited in lockstep**: `ProcessingManager.cpp`'s `SerializeRenderPassConfig()` (the producer, run once per job at `Process()` time) and `processing_processor_render.cpp`'s `RenderProcessor::ParseRenderPassConfig()` (the consumer, the "exact byte-for-byte inverse" per its own doc comment). Every new `pipeline_state` field (blending) and every new binary payload (a texture's raw pixel bytes) needs a matching append/read pair in both files, in the same order, with the same optional-tag encoding already used for `topology`/`cull_mode`/`front_face`/`depth_test`. Missing this is the single highest-risk silent-bug vector for this phase — worse than a compile error, it manifests as garbage pixel data or an out-of-bounds read that may or may not crash depending on platform.

For texturing specifically, this research also found (by reading `ProcessingManager.cpp`'s vertex_buffer resolution code directly, not by inference) the existing, reusable pattern for getting raw job-input bytes into a render pass: `vertex_buffer`/`index_buffer`'s `"source": "input:<name>"` convention, resolved via `GetInputIndex()` + `GetSubCidForProc()` fetch, fail-closed at `Create()` time if the prefix isn't `input:`. A new `texture_buffer`/`texture_bindings` schema field, structurally identical to `vertex_buffer`'s, is the natural fit — **not** the render-irrelevant `DataType::TEXTURE2_D`/`TEXTURE3_D` MNN-chunking convention (block_len/chunk_stride/etc.), which is a completely different data shape built for CPU-side tensor processing and would be over-engineering for a single flat RGBA8 image buffer.

**Primary recommendation:** Build lighting first (zero infra, proves the empirical/tolerance-derivation loop end-to-end fastest), then blending (one new schema field + `BuildPipeline()` wiring), then texturing (genuinely new descriptor/sampler/image-upload infrastructure, and the wire-format extension). Use `VK_FILTER_NEAREST` for the texturing fixture's sampler unless the fixture's design deliberately wants hardware bilinear-interpolation divergence as its "floating-point-heavy computation" source (see Common Pitfall 1 — this is a real, unresolved design fork with cross-hardware divergence-size implications for SC4).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Render fixture JSON definitions (3 new) | Backend / Processing schema | — | Job definitions are schema-validated data, consumed entirely inside `SGProcessingManager`; no client/UI tier involved |
| GLSL shader authoring (lighting/blending/texturing) | Backend (GPU-side, compiled at job-parse time) | — | Shaders execute on the Vulkan device inside `RenderProcessor`; compiled via `ShaderCompiler`/shaderc at `ProcessingManager::Process()` time, not ahead-of-time in a build step |
| Pipeline-state schema extension (blend fields) | Backend / Processing schema | Backend (C++ `BuildPipeline()`) | Schema is the source of truth (quicktype-generated C++ types); `BuildPipeline()` is the consumer that turns schema values into `VkPipelineColorBlendAttachmentState` |
| Texture descriptor/sampler infrastructure | Backend (Vulkan/GPU) | Backend / Processing schema (new input-binding field) | New `VkSampler`/`VkImageView`/descriptor-set-layout entries are pure GPU-resource code in `RenderProcessor`; the schema only needs to describe where the raw pixel bytes come from |
| `byteQuantMode` derivation + counter-tests | Backend (quantization mechanism, already shipped) | Backend (test suite) | `ResolveByteQuantMode`/`QuantizeByteBuffer` already exist; this phase only supplies per-fixture data (job JSON `parameters` entries) and new `GTEST`/`CTest` cases |
| Cross-machine capture runs | Operator / manual (two physical machines) | Backend (`capture_harness`/`capture_diff` CLI tools, already shipped) | Not automatable in CI — requires physical access to the Mac mini and Windows machine per D-09, mirroring Phase 11 |

## Standard Stack

No new third-party libraries are introduced by this phase. Every dependency needed (Vulkan 1.x, `shaderc` GLSL→SPIR-V compiler, SPIRV-Tools validator, `vk-bootstrap`) is already vendored and wired from Phase 1/3. This phase is pure extension of existing hand-rolled Vulkan code plus GLSL shader authoring plus JSON schema/fixture authoring.

### Core (already present, reused as-is)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Vulkan (hand-rolled, no bgfx/OpenGL) | Project's existing SDK version | Offscreen render pipeline, image/sampler/descriptor creation | Locked project convention (STATE.md "Key Decisions v1.0+v2.0") |
| `shaderc` | Already vendored | GLSL→SPIR-V compilation for the new lighting/blending/texturing fragment shaders | Already the project's only shader-compile path (`ShaderCompiler::CompileAndValidate`) |
| SPIRV-Tools (`spirv-val`) | Already vendored | Validates every GLSL-compiled shader at job-`Create()` time | Already wired; texturing's GLSL will need `sampler2D`/`texture()` — standard core GLSL 450, no extension required |
| quicktype | External dev tool (Node/npm), not a runtime dependency | Regenerates `PipelineState.hpp` (and a new `BlendFactor`/similar enum header) from `gnus-processing-schema.json` after schema edits | Existing project convention (`SuperGenius/SGProcessingManager/README.md` "Schema-to-C++ Header Generation") — never hand-edit `generated/` |

### Package Legitimacy Audit

**Not applicable.** This phase installs no new external packages (no `npm install`, `pip install`, or `cargo add`). All work is C++/GLSL/JSON changes inside the existing `SGProcessingManager` codebase using already-vendored Vulkan/shaderc/SPIRV-Tools/quicktype tooling. The Package Legitimacy Gate protocol is skipped for this reason — flag to the planner: no `checkpoint:human-verify` package-install tasks are needed for this phase.

## Architecture Patterns

### System Architecture Diagram (render-pass data flow, showing where each new fixture's new work lands)

```
Job JSON (fixture file)
   │  {name, inputs[], outputs[], parameters[], passes[{render_shader, render_target,
   │   vertex_buffer, [NEW] texture_buffer, pipeline_state[+blend fields], ...}]}
   ▼
ProcessingManager::Create()/CheckProcessValidity()   [existing, extend for D-05 texture/blend fields]
   │  - schema validation (nlohmann::json_schema)
   │  - render-pass field presence checks (vertex_buffer/index_buffer prefix gating)
   │  - [NEW] texture_buffer "input:" prefix gate, mirroring vertex_buffer (ProcessingManager.cpp:~608-624)
   ▼
ProcessingManager::Process()
   │  - GetSubCidForProc() fetches raw bytes for vertex_buffer, index_buffer,
   │    [NEW] texture_buffer -- all via the same "input:<name>" -> source_uri_param lookup
   │  - ShaderCompiler::CompileAndValidate() compiles GLSL->SPIR-V+validates (per-stage)
   │  - SerializeCompiledStages() -> mainbuffers->first (modelFile)
   │  - SerializeRenderPassConfig() -> mainbuffers->second (imageData)
   │      [MUST EDIT for D-05]: append new pipeline_state blend fields (optional-tag
   │      encoding, same pattern as topology/cull_mode/front_face/depth_test);
   │      append new texture-buffer section (width/height/format + raw bytes)
   ▼
RenderProcessor::StartProcessing()
   │  1. ParseCompiledStages(modelFile)              -- unchanged
   │  2. ParseRenderPassConfig(imageData)             [MUST EDIT: exact inverse of the
   │                                                    SerializeRenderPassConfig additions above]
   │  3. ResolveUniforms(uniformsMap, parameters)      [lighting: unchanged, reuses VEC3/VEC4/MAT4;
   │                                                    texturing: extend to accept a texture-typed
   │                                                    uniform entry whose "source" resolves to the
   │                                                    new texture-buffer binding, not a packed byte value]
   │  4. ResolveByteQuantMode(parameters)              -- unchanged (Phase 14, reused as-is)
   │  5. BuildRenderPass / BuildFramebuffer            -- unchanged
   │  6. BuildPipeline(stages, vertexLayout,
   │                    pipelineState, resolvedUniforms) [MUST EDIT for D-05:
   │                                                       blending: real VkPipelineColorBlendAttachmentState
   │                                                       from schema fields instead of hardcoded VK_FALSE;
   │                                                       texturing: new combined-image-sampler
   │                                                       VkDescriptorSetLayoutBinding at binding=1]
   │  7. UploadBuffers(vertexBytes, indexBytes,
   │                    resolvedUniforms)               [MUST EDIT for texturing: create+upload the
   │                                                       VkImage/VkImageView/VkSampler here, mirroring
   │                                                       CreateImageDedicated()'s existing pattern]
   │  8. RecordAndSubmit / Readback                    -- unchanged
   │  9. QuantizeByteBuffer(readbackBytes, maskBits)   -- unchanged (Phase 14 mechanism); maskBits now
   │                                                       becomes genuinely non-zero for the new fixtures
   ▼
ProcessOutput.artifacts[0] (hash + raw bytes)
   │
   ▼
capture_harness (--repeat N, rawOutputCapture callback)  -- unchanged, reused as-is
   │
   ▼
.cap file (per machine, per fixture)  ──►  capture_diff --element-type uint8  ──►  diff JSON
   │                                            (maxAbsDelta/chunkHashesMatch/contentHashMatch)
   ▼
Binary-search byteQuantMode in [0,8] against a new SECV-01-style counter-test
   │  (mirrors secv01_tex3d_counter_test.cpp's methodology exactly)
   ▼
Final byteQuantMode value wired into the fixture JSON's `parameters` array
   │
   ▼
Fresh two-machine capture_diff re-run  ──►  SC4 (hash match or honestly-documented residual gap)
```

### Recommended Project Structure (new files only; existing directories reused)
```
SuperGenius/SGProcessingManager/
├── gnus-processing-schema.json          # extend pipeline_state (blend fields), add texture_buffer definition
├── generated/                            # quicktype-regenerated after schema edit (BlendFactor.hpp etc.)
└── src/processors/processing_processor_render.cpp   # BuildPipeline/UploadBuffers/ResolveUniforms/ParseRenderPassConfig edits
SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp   # SerializeRenderPassConfig + CheckProcessValidity edits (texture_buffer)
SuperGenius/test/src/processing_dispatch/                                  # (or a new processing_conformance_render/ dir)
├── lighting-fixture-definition.json
├── lighting_fragment_shader.glsl
├── blending-fixture-definition.json
├── blending_fragment_shader.glsl        # or reuse solid-color + rely on pipeline blend state alone
├── texturing-fixture-definition.json
├── texturing_fragment_shader.glsl       # sampler2D + texture() sampling
└── texturing-source-image.raw           # small synthetic RGBA8 image (generated procedurally, not a real photo)
SuperGenius/test/src/processing_conformance_security/
├── secv01_render_lighting_counter_test.cpp
├── secv01_render_blending_counter_test.cpp
├── secv01_render_texturing_counter_test.cpp
└── fixtures/  (wrong-lighting.frag / wrong-blend-constant / wrong-texture-source, mirroring secv01-wrong-color.frag)
```

### Pattern 1: Lighting fixture — pure GLSL, zero C++/schema changes

**What:** A Phong or Lambertian fragment shader computing per-pixel lighting from a normal, light direction, and view direction — all as `VEC3`/`VEC4`/`MAT4` uniforms already fully supported end-to-end by `ResolveUniforms`/`PackUniformValue` (`processing_processor_render.cpp:752-799`).

**When to use:** This is the fastest fixture to build and the one to build FIRST — it validates the entire empirical/tolerance-derivation loop (capture_harness → capture_diff → binary search → counter-test → re-capture) without touching a single line of `RenderProcessor`/schema code, so any process problems surface before the two harder fixtures' extra infrastructure work is even started.

**Example (fragment shader, GLSL 450, mirrors the project's existing `precision highp float;` convention seen in every other fixture shader):**
```glsl
// Source: pattern derived from existing project fixtures
// (SuperGenius/test/src/processing_dispatch/solid_red_fragment_shader.glsl,
// scalar_position_vertex_shader.glsl) -- same #version/precision conventions.
#version 450
precision highp float;

layout(location = 0) in vec3 inNormal;
layout(location = 1) in vec3 inFragPos;

layout(push_constant) uniform Lighting {
    vec3 lightDir;      // normalized, world space
    vec3 lightColor;
    vec3 viewPos;
} u;

layout(location = 0) out vec4 outColor;

void main()
{
    vec3 N = normalize(inNormal);
    vec3 L = normalize(-u.lightDir);
    float diff = max(dot(N, L), 0.0);

    vec3 V = normalize(u.viewPos - inFragPos);
    vec3 R = reflect(-L, N);
    float spec = pow(max(dot(V, R), 0.0), 32.0);   // real transcendental FP work (pow)

    vec3 result = (diff + spec) * u.lightColor;
    outColor = vec4(result, 1.0);
}
```
The `pow()` call and the `normalize()`/`dot()`/`reflect()` chain are exactly the kind of floating-point-heavy computation the roadmap names (each GPU vendor's transcendental-function implementation — `pow`, `sqrt` inside `normalize`/`reflect` — is a well-known source of last-bit cross-vendor divergence; this is precisely why the happy-path fixture, which does none of this, showed zero divergence in Phase 11).

**Uniform declaration convention** (matches the already-working `VEC3`/`VEC4` path exactly, no ResolveUniforms change needed):
```json
"render_shader": {
  "stages": [ /* vertex + fragment as usual */ ],
  "uniforms": {
    "lightDir":   { "type": "vec3", "value": [-0.3, -1.0, -0.2] },
    "lightColor": { "type": "vec3", "value": [1.0, 1.0, 1.0] },
    "viewPos":    { "type": "vec3", "value": [0.0, 0.0, 3.0] }
  }
}
```
Per-vertex normals need a second `vertex_layout` entry (`inNormal`, `FLOAT32`, offset past position) — this is also an already-supported, unchanged code path (`VertexFormatByteSize`/`ToVkFormat` already handle multiple vertex attributes generically).

### Pattern 2: Blending fixture — one schema field + `BuildPipeline()` wiring

**What:** Real alpha blending (`VkPipelineColorBlendAttachmentState` with `blendEnable = VK_TRUE`), replacing the hardcoded `VK_FALSE` at `processing_processor_render.cpp:1531`.

**Schema extension** (extends `pipeline_state`'s "curated, minimal v1" set, `gnus-processing-schema.json:549-574`, mirroring D-13's existing enum-string style for `cull_mode`/`front_face`):
```json
"pipeline_state": {
  "type": "object",
  "description": "Curated, minimal v1 fixed-function pipeline state subset (D-13); depth compare op is fixed at 'less' (D-14); [NEW] blend state added Phase 17 (D-05)",
  "properties": {
    "topology": { "...": "unchanged" },
    "cull_mode": { "...": "unchanged" },
    "front_face": { "...": "unchanged" },
    "depth_test": { "...": "unchanged" },
    "blend_enable":     { "type": "boolean", "default": false },
    "blend_src_factor": { "type": "string", "enum": ["one", "zero", "src_alpha", "one_minus_src_alpha"], "default": "src_alpha" },
    "blend_dst_factor": { "type": "string", "enum": ["one", "zero", "src_alpha", "one_minus_src_alpha"], "default": "one_minus_src_alpha" }
  }
}
```
A minimal 4-value enum (`one`/`zero`/`src_alpha`/`one_minus_src_alpha`) covers the single most common blend equation (standard "over" alpha compositing) without expanding the curated set beyond what this phase's fixture actually needs — consistent with D-13's stated minimalism philosophy the canonical refs explicitly flag.

**`BuildPipeline()` wiring** (`processing_processor_render.cpp:1528-1536`, replacing the hardcoded block):
```cpp
// Source: pattern extending the existing hardcoded block at
// processing_processor_render.cpp:1528-1536
VkPipelineColorBlendAttachmentState colorBlendAttachment{};
colorBlendAttachment.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                                       VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;
bool blendEnable = pipelineState && pipelineState->get_blend_enable().value_or(false);
colorBlendAttachment.blendEnable = blendEnable ? VK_TRUE : VK_FALSE;
if ( blendEnable )
{
    colorBlendAttachment.srcColorBlendFactor = ToVkBlendFactor( pipelineState->get_blend_src_factor().value_or( sgns::BlendFactor::SRC_ALPHA ) );
    colorBlendAttachment.dstColorBlendFactor = ToVkBlendFactor( pipelineState->get_blend_dst_factor().value_or( sgns::BlendFactor::ONE_MINUS_SRC_ALPHA ) );
    colorBlendAttachment.colorBlendOp        = VK_BLEND_OP_ADD;
    colorBlendAttachment.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
    colorBlendAttachment.dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO;
    colorBlendAttachment.alphaBlendOp        = VK_BLEND_OP_ADD;
}
```
`ToVkBlendFactor()` follows the exact same static-mapping-function convention already used for `ToVkCullMode`/`ToVkFrontFace`/`ToVkTopology` (declared in `processing_processor_render.hpp:218-221`).

**The fixture itself** does not strictly need a new shader — two overlapping semi-transparent triangles (or point-list quads) drawn with `blend_enable: true` against a non-trivial clear color is sufficient to produce a real floating-point blend computation (`src*srcFactor + dst*dstFactor`) whose final byte-quantized result depends on each GPU's rounding when converting the blended float result back to `UNORM8`.

**CRITICAL — wire-format edit required in `ProcessingManager.cpp`:** `pipeline_state`'s existing fields are serialized in `SerializeRenderPassConfig()` (`ProcessingManager.cpp:248-296`) as a sequence of `appendU8(present ? 1 : 0)` + `appendU32(enumValue)` pairs, in schema-declaration order, and `ParseRenderPassConfig()` on the `RenderProcessor` side must read them back in the exact same order. The three new blend fields MUST be appended after `depth_test`'s existing pair in both functions, in the same order, or every field after the insertion point silently misaligns (garbage cull_mode/front_face/depth_test values, not a crash) on any job that doesn't set 100% of pipeline_state's optional fields. See Common Pitfall 2.

### Pattern 3: Texturing fixture — genuinely new descriptor/sampler/image-upload infrastructure

**What:** A combined-image-sampler texture bound at descriptor set binding 1 (uniform buffer, if present, stays at binding 0 — same descriptor set, two bindings, per the standard Vulkan combined-image-sampler tutorial pattern [CITED: docs.vulkan.org/tutorial "Texture mapping / Combined image sampler"]).

**Data path (the new part, following the exact `vertex_buffer` precedent read directly from `ProcessingManager.cpp` this session):**

1. **Schema** — new `texture_buffer` definition, structurally identical to `vertex_buffer`/`index_buffer` (`gnus-processing-schema.json:521-532`):
```json
"texture_buffer": {
  "type": "object",
  "description": "Raw RGBA8 image bytes for a render pass's sampled texture input, using the same prefix-notation convention as vertex_buffer",
  "required": ["source", "width", "height"],
  "properties": {
    "source": { "type": "string", "pattern": "^(input|output|internal|parameter):[a-zA-Z][a-zA-Z0-9_]*$" },
    "width":  { "type": "integer", "minimum": 1 },
    "height": { "type": "integer", "minimum": 1 },
    "filter": { "type": "string", "enum": ["nearest", "linear"], "default": "nearest" }
  }
}
```
Add `"texture_buffer": { "$ref": "#/definitions/texture_buffer" }` to the `pass` object (`gnus-processing-schema.json:198-205`, alongside `vertex_buffer`/`index_buffer`). Deliberately reuses `vertex_buffer`'s exact "flat raw buffer, not the MNN `texture2D` chunking convention" shape — `DataType::TEXTURE2_D`'s `block_len`/`chunk_stride`/`chunk_line_stride` fields (`ProcessingManager.cpp:946-960`) are purpose-built for MNN CPU-side chunked tensor processing and are the wrong shape for a single small GPU-sampled image; do not reuse that `DataType` path for this.

2. **`ProcessingManager.cpp` — validation + fetch** (mirrors the existing `vertex_buffer` block, `ProcessingManager.cpp:579-624` and `1776-1789` read directly this session):
```cpp
// Validation (CheckProcessValidity, alongside the existing vertex_buffer check):
if ( pass.get_texture_buffer() )
{
    const std::string textureSource = pass.get_texture_buffer().value().get_source();
    if ( textureSource.rfind( "input:", 0 ) != 0 )
    {
        return rejectUnsupportedBufferSourcePrefix( "texture_buffer", textureSource );
    }
}
// Fetch (Process(), alongside the existing vertexBuffer fetch):
if ( p.get_texture_buffer() )
{
    auto texInputIndex = GetInputIndex( p.get_texture_buffer().value().get_source() );
    if ( !texInputIndex ) { return outcome::failure( Error::MISSING_INPUT ); }
    std::string textureUrl = processing_.get_inputs()[texInputIndex.value()].get_source_uri_param();
    textureBuffer = std::make_shared<std::vector<char>>();
    GetSubCidForProc( ioc, textureUrl, textureBuffer );
}
```

3. **`SerializeRenderPassConfig()` — append the new section** (after the existing `dataTransformCount` append or before it, but MUST match `ParseRenderPassConfig`'s read order exactly):
```cpp
if ( hasTextureBuffer )
{
    appendU8( 1 );
    appendU32( textureWidth );
    appendU32( textureHeight );
    appendU32( static_cast<uint32_t>( textureBytes.size() ) );
    appendBytes( textureBytes.data(), textureBytes.size() );
}
else
{
    appendU8( 0 );
}
```

4. **`RenderProcessor` side — the genuinely new Vulkan work.** `CreateImageDedicated()` (`processing_processor_render.cpp:1022-1070`) already exists and is directly reusable for the texture's `VkImage` (currently only used for the color/depth render targets, `BuildFramebuffer()`). The upload path (staging buffer → `vkCmdCopyBufferToImage` → layout transition) does **not** exist anywhere in this file today — every current image use is a render *target* (written by the GPU, never uploaded from the CPU) — this is the one piece of infrastructure with zero precedent in the codebase to crib from:
```cpp
// Source: pattern from the standard Vulkan texture-upload sequence
// [CITED: docs.vulkan.org/tutorial "Texture mapping" chapter] adapted to this
// codebase's CreateBufferDedicated()/CreateImageDedicated() helpers (D-18/D-19
// dedicated-allocation convention, no sub-allocation, mirrors every existing
// buffer/image creation in this file).
// 1. Staging buffer (HOST_VISIBLE|HOST_COHERENT), memcpy raw RGBA8 bytes in --
//    identical pattern to UploadBuffers()'s existing vertex/index/uniform buffers.
// 2. VkImage (DEVICE_LOCAL, usage = TRANSFER_DST | SAMPLED, initialLayout = UNDEFINED)
//    via the EXISTING CreateImageDedicated().
// 3. vkCmdPipelineBarrier: UNDEFINED -> TRANSFER_DST_OPTIMAL
// 4. vkCmdCopyBufferToImage(stagingBuffer, image, TRANSFER_DST_OPTIMAL, ...)
// 5. vkCmdPipelineBarrier: TRANSFER_DST_OPTIMAL -> SHADER_READ_ONLY_OPTIMAL
// 6. VkImageView (existing vkCreateImageView pattern, mirrors m_colorView/m_depthView)
// 7. VkSampler -- NEW, no existing call anywhere in this file:
VkSamplerCreateInfo samplerInfo{};
samplerInfo.sType     = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
samplerInfo.magFilter = filter;   // VK_FILTER_NEAREST recommended -- see Pitfall 1
samplerInfo.minFilter = filter;
samplerInfo.addressModeU = samplerInfo.addressModeV = samplerInfo.addressModeW =
    VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
samplerInfo.anisotropyEnable = VK_FALSE;   // avoid an extra cross-vendor divergence axis
samplerInfo.compareEnable    = VK_FALSE;
samplerInfo.mipmapMode       = VK_SAMPLER_MIPMAP_MODE_NEAREST;
vkCreateSampler( m_device, &samplerInfo, nullptr, &m_textureSampler );
```
Steps 3/5's pipeline barriers must be recorded on the SAME command buffer/queue submission the project already uses in `RecordAndSubmit()` (there is no separate transfer queue in this codebase — `m_queue`/`m_commandPool` are reused, mirroring how the existing readback copy is recorded inline into the single command buffer per that function's own doc comment about avoiding "no second command buffer/submission").

5. **Descriptor set layout** — add a second binding alongside the existing uniform-buffer binding at `processing_processor_render.cpp:1576-1585`:
```cpp
VkDescriptorSetLayoutBinding samplerBinding{};
samplerBinding.binding         = 1;
samplerBinding.descriptorType  = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
samplerBinding.descriptorCount = 1;
samplerBinding.stageFlags      = VK_SHADER_STAGE_FRAGMENT_BIT;
// bindings[] = { existing uniform-buffer binding (0), samplerBinding (1) };
// layoutInfo.bindingCount = 2; layoutInfo.pBindings = bindings;
```
The descriptor pool (`processing_processor_render.cpp:1600-1610`) needs a second `VkDescriptorPoolSize` entry for `VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER`. `vkUpdateDescriptorSets` needs a second `VkWriteDescriptorSet` using `VkDescriptorImageInfo{sampler, imageView, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL}` [CITED: docs.vulkan.org/tutorial "Combined image sampler"].

6. **GLSL fragment shader:**
```glsl
#version 450
precision highp float;
layout(location = 0) in vec2 inUV;
layout(binding = 1) uniform sampler2D texSampler;
layout(location = 0) out vec4 outColor;
void main() { outColor = texture(texSampler, inUV); }
```

7. **`ResolveUniforms` extension** — the cleanest fit is NOT to route the texture through `PackUniformValue`'s byte-packing path at all (a sampler binding has no packed-byte payload). Instead, treat `texture_buffer`'s presence as an independent signal `BuildPipeline()`/`UploadBuffers()` check directly (mirroring how `vertex_buffer`/`index_buffer` already bypass `ResolveUniforms` entirely) rather than teaching `ResolveUniforms` a new non-byte-packing uniform kind. This avoids the awkwardness of `PackUniformValue`'s current all-uniforms-produce-bytes contract (`processing_processor_render.cpp:701-815`) and keeps the "texture is a resource binding, not a uniform value" distinction clean — this is this phase's most important architectural judgment call for the planner to make explicitly, since 17-CONTEXT.md leaves the "exact new schema mechanism" as Claude's Discretion.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cross-hardware float/byte tolerance | A new comparison/rounding mechanism | `ResolveByteQuantMode`/`QuantizeByteBuffer` (Phase 14, already wired) | D-01: this phase's entire RENDTOL-02 scope is deriving+proving VALUES for the existing mechanism, not building a new one. Building a second mechanism would directly contradict the locked reframe. |
| GLSL→SPIR-V compilation/validation | A shell-out to `glslc`/manual SPIR-V hex | `ShaderCompiler::CompileAndValidate` (already exists, already used by every fixture including `secv01-wrong-color.frag`) | Already integrated with `shaderc`+SPIRV-Tools at job-parse time; a new fixture just needs a `"type": "glsl"` shader-stage entry, same as every existing fixture |
| Image data upload (staging→device-local) | A generic/abstracted texture-upload utility class | Direct `CreateBufferDedicated()`+`CreateImageDedicated()`+manual barrier/copy sequence, matching this file's existing per-function style | This codebase deliberately has no abstraction layer over Vulkan resource creation (D-18/D-19 "dedicated allocation, no sub-allocation" convention) — introducing an abstraction here would be inconsistent with every other resource in this file |
| Binary-search tolerance-derivation tooling | A new automated bisection script/CI job | Manual rebuild+`--gtest_filter` iteration against the new counter-test, exactly as Phase 13/14 did (documented in `13-04-PLAN.md`, `14-03-SUMMARY.md`) | Explicitly the project's own established methodology (D-06 cites it directly); each iteration costs real GPU time and a real cross-hardware capture is not CI-automatable per D-09/Phase 11 precedent — a "script" would still need a human to run it on two physical machines |

**Key insight:** Every piece of "don't hand-roll" guidance here is really the same point restated: this phase is disciplined *extension* of an already-designed system, not new architecture. The temptation to invent a cleaner/more general mechanism (a generic texture-uniform abstraction, a new tolerance formula, an automated capture pipeline) should be resisted — the existing patterns (Phase 10's capture tooling, Phase 13/14's binary-search discipline, this file's per-resource Vulkan creation style) are the standard to match, not a starting point to redesign.

## Tolerance Derivation Methodology (D-06/D-07/D-08, the phase's central empirical work)

This mirrors Phase 13's small-model `quantScale` search and Phase 14's tex3d `quantScale` search (`14-03-SUMMARY.md`, `secv01_tex3d_counter_test.cpp`), adapted from a continuous power-of-two float scale to `byteQuantMode`'s discrete `N ∈ [0,8]` bit-count:

1. **Capture raw (unquantized) cross-hardware divergence first.** Run each new fixture through `capture_harness --repeat 3` on both machines with `byteQuantMode` NOT declared (falls back to `N=0`, exact v2.1 identity, per `ResolveByteQuantMode`'s own doc comment) — this reproduces Phase 11's methodology exactly. Diff via `capture_diff --element-type uint8`. Record `maxAbsDelta` (an integer 0-255 magnitude, since `ComputeUint8Diff` treats each raw byte as one element) and `contentHashMatch`.
2. **Convert the tolerance question into an integer decision.** `QuantizeByteBuffer(N)` clears the low `N` bits of every byte (`value &= ~((1<<N)-1)`), so it can absorb any two raw values that fall in the same `2^N`-wide bucket. The relevant empirical question is: what `N` makes `2^N > maxAbsDelta` (bucket wide enough to swallow the real captured delta) while remaining low enough that `SECV-01`'s counter-test (a deliberately wrong shader constant / wrong blend factor / wrong texture pixel) still diverges post-quantization?
3. **Binary-search `N` in `[0,8]` against a new counter-test**, exactly mirroring `secv01_tex3d_counter_test.cpp`'s structure: two otherwise-identical render jobs, one correct, one deliberately wrong (see below), each declaring the SAME candidate `byteQuantMode` in its `parameters` array, asserting `std::memcmp` on `artifacts[0].artifactId` still differs. Run this by rebuilding + `--gtest_filter`-invoking the new test at each candidate `N`, same iteration style Phase 13/14 used (no new automated bisection tooling — see Don't Hand-Roll).
4. **Two possible outcomes, both already precedented:**
   - **A genuine failure boundary exists** (like Phase 13's small MNN model, S=2^14 failed): choose one step of margin above the confirmed-passing boundary (e.g. if `N=5` fails and `N=4` passes, ship `N=4`... but read the direction carefully — HIGHER `N` masks MORE bits = MORE tolerant = MORE likely to also mask corruption, so the search direction is: increasing `N` eventually starts failing SECV-01; pick the highest `N` one step below that failure point, not above it. This is the mirror image of Phase 13/14's power-of-two search, where DEcreasing `S` (widening the grid) is the "more tolerant" direction — for `byteQuantMode`, INcreasing `N` is the "more tolerant" direction).
   - **No failure boundary exists anywhere in `[0,8]`** (like Phase 14's tex3d search, all of 256/128/64/2/1 passed): fall back to D-08's divergence-absorption constraint — pick the smallest `N` such that `2^N > maxAbsDelta` (finest/most-precise `N` that still absorbs the real measured delta), same "prefer precision, only widen as far as the real data requires" philosophy `14-03-SUMMARY.md`'s key-decisions documents for tex3d's `quantScale=128.0` choice.
   - **If no `N` in `[0,8]` absorbs the divergence at all** (i.e. even `N=8`, masking all 8 bits and effectively zeroing every byte, still leaves `maxAbsDelta` non-zero — which cannot actually happen since `N=8` clears every bit, making all bytes `0x00` and `maxAbsDelta=0` trivially; the real risk is closer to "N=8 zeroes so much of the image that SECV-01 ALSO can't distinguish a corrupted image from a correct one, because both quantize to all-zero"): this is D-08's honest-gap case — document it exactly like `13-SCOPE-BOUNDARY.md` did for the MNN float fixture, do not force a pass.
5. **Counter-test "deliberately wrong" fixtures per technique** (each needs its own new GLSL/JSON fixture, mirroring `secv01-wrong-color.frag`'s "structurally identical, materially different constant" pattern):
   - **Lighting:** a wrong light color/direction constant (e.g. `lightColor: [0.5, 0.5, 0.5]` instead of `[1.0, 1.0, 1.0]`), same shader code.
   - **Blending:** a wrong `blend_src_factor`/`blend_dst_factor` in `pipeline_state` (e.g. `one` instead of `src_alpha`), same shader/geometry.
   - **Texturing:** a wrong source texture (different pixel content at the same dimensions), same shader/sampler config — this is the closest structural analog to `secv01_tex3d_counter_test.cpp`'s "same pipeline, corrupted input data" pattern (there, a byte-perturbed `.mnn` model; here, a byte-perturbed texture image).
6. **Re-run the fresh two-machine capture with the final `byteQuantMode` wired into the fixture's `parameters` array** (SC4) — this is a NEW capture, not a reinterpretation of step 1's raw data, exactly as Phase 13's Plan 13-05 re-captured after changing the quantization constant rather than reusing Phase 11's stale numbers.

## Common Pitfalls

### Pitfall 1: Bilinear texture filtering may make SC4 unreachable within `[0,8]`, or may not diverge at all — this is a genuine, unresolved design fork
**What goes wrong:** Vulkan's `VK_FILTER_LINEAR` interpolation weight computation (subtexel fractional-position precision) is implementation-defined per the Vulkan spec, and different GPU vendors are known to use different fixed-point precision for the interpolation weights — this is a textbook source of cross-hardware divergence, and is arguably the most "authentic" way to satisfy SC2's requirement for "real, non-zero captured divergence." But if that divergence is large/inconsistent enough, no `byteQuantMode` in `[0,8]` may close it without also masking real corruption (SC5 tension).
**Why it happens:** Texture sampling hardware is one of the few genuinely vendor-specific fixed-function GPU units (unlike blend/lighting math, which route through standard IEEE-754 float ALUs with much more spec-constrained behavior).
**How to avoid:** Recommend starting the texturing fixture with `VK_FILTER_NEAREST` (exact, bit-reproducible texel lookup, no interpolation) — this still exercises "real floating-point-heavy render computation" via the UV coordinate math and any per-pixel shading combined with the sampled color, satisfying RENDTOL-01's letter without gambling SC4 on a known-hard vendor-specific divergence source. If the captured `NEAREST` divergence turns out to be zero (mirroring the happy-path fixture's own zero-divergence surprise), that is itself a valid, documentable finding — switch to `LINEAR` only as a deliberate follow-up, with D-08's honesty bar ready if needed.
**Warning signs:** `capture_diff`'s `maxAbsDelta` for the texturing fixture is either suspiciously 0 (mirrors the original happy-path finding — check the fixture is actually forcing texture reads that land on non-trivial fractional UV coordinates if using LINEAR) or very large/inconsistent between repeated same-machine runs (a sign of filtering-hardware divergence beyond what a single fixed `byteQuantMode` can characterize with a single number).

### Pitfall 2: The `SerializeRenderPassConfig()` / `ParseRenderPassConfig()` wire-format pair is edited in only one file
**What goes wrong:** Adding a new `pipeline_state` field or a new binary section (texture bytes) to only `ProcessingManager.cpp`'s serializer OR only `processing_processor_render.cpp`'s parser produces silent byte-offset misalignment — every field read AFTER the mismatch point gets garbage values (wrong enum ordinals reinterpreted as different enums, wrong buffer lengths triggering out-of-bounds reads). This does not necessarily crash; it can produce a plausible-looking but wrong render result, which is exactly the kind of bug this phase's SC5 counter-tests exist to catch in the OUTPUT but would NOT catch as a build/schema error.
**Why it happens:** This is a hand-rolled fixed-format binary protocol (not a schema-driven serialization library) split across two files in two different classes, with no shared struct/type enforcing the pairing — `ParseRenderPassConfig`'s own doc comment calls itself "the exact byte-for-byte inverse," which is a manual invariant, not a compiler-enforced one.
**How to avoid:** Every plan task that adds a schema field consumed by `ParseRenderPassConfig` MUST include a paired edit to `SerializeRenderPassConfig` in the same task (not a separate task/wave), and the verification step should include running the modified fixture through `ProcessingManager::Create()`+`Process()` end-to-end (not just a unit test of one side) to prove the pairing round-trips correctly.
**Warning signs:** A render job that used to produce the happy-path's expected 8x8 solid-red output now produces black, garbage colors, or a crash after a schema-only-looking change; `cull_mode`/`front_face`/`depth_test` behaving inconsistently with what the JSON declares, for jobs that don't set every optional `pipeline_state` field.

### Pitfall 3: Masking low bits is not equivalent to grid-rounding — boundary straddling
**What goes wrong:** `QuantizeByteBuffer`'s bit-masking clears bits to zero (floor-to-bucket, buckets aligned at `0, 2^N, 2*2^N, ...`), unlike `QuantizeFloatBuffer`'s round-to-nearest-grid-point. Two raw byte values that differ by less than `2^N` can still straddle a bucket boundary (e.g. `N=4`, values 15 and 16 differ by 1 but mask to `0` and `16` respectively) and end up MORE different post-quantization than pre-quantization for that specific pair, even though the chosen `N` is "correct" on average.
**Why it happens:** This is an inherent property of floor-masking vs. round-to-nearest; it was already anticipated by the existing quantization design and is analogous to the float grid's own well-documented tie-break risk (`quantization.cpp`'s own header comment: "cannot mathematically guarantee zero cross-hardware divergence for arbitrary per-element deltas that happen to land arbitrarily close to a rounding boundary").
**How to avoid:** Do not expect a chosen `byteQuantMode` to be a mathematically airtight guarantee — treat it exactly as the project already treats `quantScale`: "a probabilistic engineering mitigation, not a one-shot guaranteed solution" (quoting `quantization.cpp` verbatim). Report SC4 results honestly per D-08 even if a rare boundary-straddle produces an unexpected chunk mismatch on a specific run.
**Warning signs:** A capture_diff re-run occasionally shows a hash mismatch on a fixture where a previous run (same `byteQuantMode`) matched — this can be genuine boundary-straddle noise, not necessarily an implementation bug; re-run `capture_harness`'s own same-machine stability check (already built in, `CheckStability()`) to rule out same-machine nondeterminism first before concluding cross-hardware straddle.

### Pitfall 4: `render_shader_config`'s `uniforms` map is a `std::map` keyed by name — a new "texture" pseudo-uniform in that same map would need special-casing everywhere `uniforms` is iterated
**What goes wrong:** If the texturing design (against this research's Pattern 3 recommendation) is instead implemented by adding `texture2D` as an accepted `uniform.get_type()` value inside the existing `uniforms` map/`ResolveUniforms`/`PackUniformValue` path, every consumer that currently assumes "every uniform produces packed bytes" (the push-constant-vs-descriptor-set size decision at `ResolveUniforms:898`, `SerializeRenderPassConfig`'s uniform-serialization loop at `ProcessingManager.cpp:306-341`) needs a parallel special case to skip byte-packing for it. This is more invasive than adding an independent `texture_buffer` pass-level field (Pattern 3's recommendation).
**Why it happens:** `ResolvedUniforms::packedBytes`/`pushConstant` decision logic implicitly assumes homogeneity (every declared uniform contributes bytes to one buffer).
**How to avoid:** Follow Pattern 3's recommendation — model the texture as an independent `texture_buffer` pass-level binding (like `vertex_buffer`/`index_buffer`), not as an entry inside the `uniforms` map. This is a genuine "Claude's Discretion" design call this research is making explicitly, not something 17-CONTEXT.md pre-decided.
**Warning signs:** If a plan's task list has you editing `PackUniformValue`'s `switch` to "un-reject" `TEXTURE2_D` (removing it from the `case ... default: return false` block at line 800-809) — that is the wrong-path signal; the right fix is a new pass-level field, not un-rejecting a byte-packing case that was never meant to hold a sampler.

## Code Examples

### Existing counter-test methodology to mirror exactly (verified from source this session)
```cpp
// Source: SuperGenius/test/src/processing_conformance_security/secv01_tex3d_counter_test.cpp
// (the exact template for this phase's 3 new counter-tests)
EXPECT_NE( std::memcmp( prCorrect.value().artifacts[0].artifactId,
                         prCorrupted.value().artifacts[0].artifactId,
                         sgns::sgprocessing::SHA256_HASH_SIZE ),
           0 )
    << "A deliberately corrupted <X> must produce a different post-quantization "
       "artifactId than the correct <X> at this fixture's own empirically-derived "
       "byteQuantMode -- SECV-01/T-17-XX";
```
Binary comparison ONLY on `artifacts[0].artifactId` (`ComputeArtifactIdentity`'s hash) — never on `ExecutionManifest::manifestHash`/`combinedHash`, which bake in machine-specific fields by design (13-03's own documented distinction).

### `capture_harness`/`capture_diff` invocation for a new fixture (unchanged tool, new arguments only)
```bash
# Source: SuperGenius/SGProcessingManager/tools/capture/capture_harness.cpp usage string
capture_harness --fixture-root <dir> --fixture processing_dispatch/lighting-fixture-definition.json \
  --label xhw-render-lighting --repeat 3 --output-dir captures/
capture_diff --a captures/xhw-render-lighting_Fuus-Mac-mini.local---macOS_*.cap \
              --b captures/xhw-render-lighting_Mofu---Windows_*.cap \
              --element-type uint8 --json-output captures/diff-render-lighting.json
```
Note `--element-type uint8` (not `float32`) — render output is always RGBA8/RGB8 raw pixel bytes, matching the happy-path fixture's own Phase 11 capture (`diff-render.json`'s `"elementType": "uint8"`).

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| `QuantizeByteBuffer` byte-identity no-op, justified only by the 8x8 happy-path fixture's zero-divergence result | Schema-configurable `byteQuantMode` bit-masking, mechanism already shipped Phase 14, values now derived per-fixture in Phase 17 | Phase 14 (mechanism), Phase 17 (per-fixture values) | The render path gains the same "measured, not guessed" tolerance discipline the MNN float/tex3d paths already have |
| No render fixture exercises real floating-point-heavy computation | Three separate fixtures (lighting/blending/texturing), each independently capturing real cross-hardware data | This phase | Closes STATE.md's "untested risk" — either confirms the render path generalizes, or documents an honest residual gap per D-08 |

**Deprecated/outdated:** None — this phase does not remove or replace any existing mechanism; it is purely additive (three new fixtures, one new schema field set, one new sampler/descriptor code path, per-fixture parameter values).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | GPU vendors implement `VK_FILTER_LINEAR` interpolation with different fixed-point subtexel precision, making it a likely (not certain) source of cross-hardware divergence | Common Pitfall 1 | If wrong (all vendors happen to agree bit-for-bit), the texturing fixture may show zero divergence like the original happy-path fixture, requiring a design pivot (e.g., deliberately mismatched sampler border/wrap behavior, or accepting NEAREST-only exercises less "real" FP work) |
| A2 | A minimal 4-value blend-factor enum (`one`/`zero`/`src_alpha`/`one_minus_src_alpha`) is sufficient to produce a real, non-zero blend-driven cross-hardware divergence | Pattern 2 | If the standard "over" blend equation happens to produce identical results cross-hardware (plausible — it's simple arithmetic on values already agreeing pre-blend), the fixture may need a more numerically-sensitive blend op (e.g. `VK_BLEND_OP_ADD` with saturating near-255 values, or introducing a lighting-style transcendental into the blended color first) |
| A3 | Modeling the texture as an independent `texture_buffer` pass-level field (not as a `uniforms`-map entry) is the cleaner design | Pattern 3 / Pitfall 4 | If the planner instead extends the `uniforms` map's byte-packing contract, extra special-casing is needed in `ResolveUniforms`/`SerializeRenderPassConfig`'s uniform loop and the push-constant-size decision — more invasive but not wrong, just a different (research-recommended-against) path |
| A4 | Standard GLSL 450 core (`sampler2D`, `texture()`, `pow`/`normalize`/`reflect`) needs no shaderc/SPIRV-Tools version bump or extension enable | Standard Stack | If the vendored shaderc version is old enough to reject standard combined-image-sampler GLSL syntax (unlikely — this is core GLSL, not an extension), a shaderc upgrade would be an unplanned dependency change |

**None of these are compliance/security/retention-policy claims** — they are engineering predictions about GPU hardware behavior that the phase's own empirical capture step (Phase-11-style, D-09) will confirm or refute directly. This is expected and by design: SC2 exists specifically to observe whichever outcome the real hardware produces, and D-08 exists specifically to handle the "didn't diverge enough" or "diverged too much to close" outcomes honestly.

## Open Questions (RESOLVED — see per-item resolution notes)

1. **(RESOLVED) Does the texturing fixture's chosen filter mode (NEAREST vs LINEAR) actually produce measurable divergence on the Mac+Windows pair?**
   - What we know: Bilinear filtering hardware is a plausible, commonly-cited divergence source; nearest-neighbor sampling is bit-exact by construction (no interpolation).
   - What's unclear: Whether THIS PARTICULAR pair of machines (an Apple Silicon or Intel/AMD Mac GPU vs. whatever Windows GPU "Mofu" has — not established in any read document this session) actually diverges on either mode, given that even the trivial happy-path fixture's uint8 output matched byte-for-byte in Phase 11.
   - Recommendation: Start with NEAREST (Pitfall 1's recommendation); if capture shows zero divergence, that is itself a valid documented finding, and the plan should have a documented decision point (not a silent fallback) for whether to retry with LINEAR.
   - **Resolution:** Not a planning blocker — this is an empirical question the plans resolve by measurement, not by research. Plan 17-05 (Round 1 capture) executes the NEAREST-first fixture against both machines; Plan 17-08 (Round 2 capture) reflects whichever filter mode Round 1's data supports, with the decision point documented rather than silently defaulted.

2. **(RESOLVED) What GPU hardware does "Mofu" (the Windows machine) actually have?**
   - What we know: STATE.md/11-CAPTURE-RESULTS.md identify it only as `Mofu---Windows`; capture_harness's `MachineIdTag()` deliberately excludes GPU vendor/driver detail (D-03: "hostname + OS only, no GPU vendor/driver detail").
   - What's unclear: Whether it's discrete or integrated, which vendor (matters directly for predicting texture-filtering/blend-rounding divergence characteristics).
   - Recommendation: Not necessary to resolve before planning — the empirical capture step will reveal actual behavior regardless of a priori vendor knowledge; do not block planning on this.
   - **Resolution:** Deliberately deferred, no action needed — confirmed non-blocking by this research's own recommendation; no plan depends on knowing this in advance.

3. **(RESOLVED) Should ROADMAP.md's Phase 17 SC1/SC2 wording (singular "a fixture") be corrected to reflect three fixtures before or after implementation?**
   - What we know: 17-CONTEXT.md flags this explicitly as Claude's Discretion, citing Phase 16's own SC-wording-correction precedent (done as part of implementation, not a blocking pre-step).
   - What's unclear: Nothing — this is a pure sequencing/discretion call, not a technical unknown.
   - Recommendation: Follow the Phase 16 precedent — correct the wording as part of implementation (likely in the first plan/wave), not as a separate blocking task.
   - **Resolution:** Addressed in Plan 17-01, Task 2 — the ROADMAP.md/REQUIREMENTS.md wording fix lands as part of the first implementation wave, per the Phase 16 precedent.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Vulkan runtime/driver (this machine) | Building/running `capture_harness`/`RenderProcessor` locally | ✓ | `vulkaninfo.exe` present on PATH (Windows machine) | — |
| cmake | Building the modified `SGProcessingManager`/test targets | ✓ | 3.29.2 | — |
| shaderc / SPIRV-Tools | Compiling the new GLSL fixture shaders | ✓ (already vendored, used by every existing render fixture) | Project-pinned version, unchanged this phase | — |
| quicktype (npm global) | Regenerating `PipelineState.hpp`/new blend-enum header after schema edits | Not verified this session (not probed — requires Node/npm) | — | Manual header edit matching quicktype's exact existing output style is a viable but error-prone fallback; recommend verifying quicktype is installed as a Wave 0 task before the blending plan starts |
| Second physical machine (Mac mini, `Fuus-Mac-mini.local`) | SC2/SC4's two-machine capture requirement (D-09) | Not verified this session (operator-owned hardware, per Phase 11 precedent) | — | None — this is a hard, non-automatable, non-fallback-able requirement inherited unchanged from Phase 11's own scope decision; the plan must include a manual/operator checkpoint for the cross-machine capture step, exactly as Phase 11/13's plans did |

**Missing dependencies with no fallback:**
- Physical access to the second machine (Mac mini) for the two-machine capture step (SC2, SC4) — this is not new to this phase, it is the same operator-dependency Phase 11/13 already worked within; the plan should structure this as a discrete "hands-on capture" checkpoint task, mirroring `11-01-PLAN.md`'s structure, rather than assuming it can be scripted end-to-end.

**Missing dependencies with fallback:**
- quicktype availability unverified — falls back to manual header editing if genuinely absent, but this should be confirmed cheaply before the blending/texturing plans begin (a single `quicktype --version` check).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | GoogleTest (GTest), registered via this project's `addtest()` CMake helper -> CTest |
| Config file | `SuperGenius/test/src/processing_conformance_security/CMakeLists.txt` (existing target `processing_conformance_security_test`, add 3 new `.cpp` sources here) |
| Quick run command | `cd SuperGenius && cmake --build build/Windows/Debug --target processing_conformance_security_test` then run the built binary directly with `--gtest_filter=<NewFixture>*` (per-candidate binary-search iteration, mirrors 14-03-SUMMARY.md's documented workflow — `ctest -R <TestFixtureName>` does NOT work at per-`TEST_F` granularity, only at the whole-binary target level) |
| Full suite command | `cd SuperGenius && ctest --test-dir build/Windows/Debug -j -C Debug --verbose` (matches `.planning/workstreams/sgproc-render/config.json`'s configured `test_command`) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| RENDTOL-01 | Lighting/blending/texturing fixtures compile+run to a non-error `ProcessingResult` | integration (GTest, GPU-dependent, `GTEST_SKIP()`-guarded like existing `Secv01CounterTest.RenderWrongShaderConstantStillDiverges` when no usable Vulkan device) | `--gtest_filter=*Lighting*:*Blending*:*Texturing*` against a new or existing `processing_dispatch`/`processing_conformance_render` GTest target | ❌ Wave 0 — new fixture JSON + shader files + (for lighting only, trivially) a happy-path-style dispatch test |
| RENDTOL-02 | Each fixture's derived `byteQuantMode` still catches a deliberately-corrupted variant | integration (GTest, mirrors `secv01_tex3d_counter_test.cpp`) | `ctest -R processing_conformance_security_test` (whole-binary; use `--gtest_filter` for per-candidate binary-search iteration) | ❌ Wave 0 — 3 new counter-test files + 3 "wrong" fixture variants |
| SC2/SC4 (empirical cross-hardware match/gap) | Two-machine `capture_harness`/`capture_diff` run per fixture | manual/other (not CI-automatable, matches Phase 11's own classification) | `capture_harness ...` / `capture_diff ...` (see Code Examples) | ✓ tooling exists (Phase 10); ❌ the actual capture run itself is Wave 0-adjacent manual work, not a file gap |

### Sampling Rate
- **Per task commit:** Rebuild + `--gtest_filter` run of the specific new counter-test/dispatch test being touched (fast local iteration, matches Phase 13/14's own documented per-candidate workflow)
- **Per wave merge:** Full `processing_conformance_security_test` + `processing_dispatch_test` + `processing_datatypes_test` CTest run (regression-check existing fixtures alongside new ones, mirroring 14-03-SUMMARY.md's "re-ran the full suite... all pass, confirming no regression")
- **Phase gate:** Full suite green (`ctest --test-dir build/Windows/Debug -j -C Debug --verbose`) before `/gsd-verify-work`, PLUS the two-machine capture/diff artifacts (`.cap`/diff JSON files) committed as evidence, mirroring `11-CAPTURE-RESULTS.md`'s precedent — this phase's SC2/SC4 cannot be verified by CTest alone

### Wave 0 Gaps
- [ ] Three new fixture JSON definitions (`lighting-fixture-definition.json`, `blending-fixture-definition.json`, `texturing-fixture-definition.json`) + their shader files
- [ ] Schema edits (`gnus-processing-schema.json`: `pipeline_state` blend fields, new `texture_buffer` definition) + quicktype regeneration
- [ ] `ProcessingManager.cpp`: `CheckProcessValidity`/`SerializeRenderPassConfig` edits for `texture_buffer` and blend fields
- [ ] `processing_processor_render.cpp`/`.hpp`: `BuildPipeline` blend wiring, new sampler/image-upload infrastructure, `ParseRenderPassConfig` inverse edits
- [ ] Three new SECV-01-style counter-test files + their "deliberately wrong" fixture variants
- [ ] A small synthetic RGBA8 source image for the texturing fixture (generate procedurally in-repo, e.g. a small checkerboard or gradient pattern written by a short one-off script — do NOT vendor a real photo/PNG decoder dependency for this; raw uncompressed RGBA8 bytes are sufficient and match every other fixture's raw-binary convention in this codebase)

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Not applicable — no auth surface touched |
| V3 Session Management | No | Not applicable |
| V4 Access Control | No | Not applicable |
| V5 Input Validation | Yes | Schema validation (`nlohmann::json_schema`) + `CheckProcessValidity`'s fail-closed `"input:"`-prefix-only gating, extended identically to the new `texture_buffer` field (mirrors existing `vertex_buffer`/`index_buffer` gating, `ProcessingManager.cpp:596-624`) |
| V6 Cryptography | No | Not applicable — no new hashing/crypto primitive; reuses existing `sha256`/`ComputeArtifactIdentity` unchanged |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Out-of-bounds GPU buffer read from a texture byte length that doesn't match declared width*height*bpp | Tampering / DoS | Validate `textureBytes.size() == width * height * 4` (or the declared format's bpp) BEFORE any `vkCmdCopyBufferToImage`/`VkImage` creation — mirrors `UploadBuffers`'s existing `T-03-03-02` pattern (stride/index-count validated before any GPU command is recorded, `processing_processor_render.cpp:1712-1720`) |
| Oversized texture dimensions causing excessive GPU memory allocation (DoS) | Denial of Service | Reuse the existing `kMaxRenderDimension` (8192) bound, or a similarly conservative bound, for `texture_buffer.width`/`height` — mirrors the render_target's own existing DoS guard (`processing_processor_render.hpp:142-146`, "the schema only enforces minimum:1, no maximum") |
| A deliberately-corrupted texture/blend-constant/lighting-constant masking as "close enough" post-quantization to a correct result | Tampering | Exactly what SC5's new counter-tests exist to prove is NOT possible for each fixture's derived `byteQuantMode` — this is the phase's own explicit security requirement, not a gap to separately mitigate |
| Wire-format misalignment (Pitfall 2) silently producing a wrong-but-plausible render result | Tampering (unintentional, but same class of bug a malicious job could also exploit if the parser doesn't bounds-check) | `ParseRenderPassConfig`'s existing bounds-checked reads (already required per its own doc comment: "Bounds-checks every read against modelFile.size() -- never reads past the end of a malformed/truncated buffer") must be extended identically for every new field this phase adds, not just the happy-path-length case |

## Sources

### Primary (HIGH confidence — read directly from the project's own source this session)
- `SuperGenius/SGProcessingManager/include/util/quantization.hpp`, `src/util/quantization.cpp` — `ResolveByteQuantMode`/`QuantizeByteBuffer` full implementation and doc-comment history
- `SuperGenius/SGProcessingManager/include/util/diff_utils.hpp`, `src/util/diff_utils.cpp` — `ComputeUint8Diff`, `IsByteChunkWithinTolerance`, tolerance-derivation primitives
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp` (lines 700-950, 1440-1830, 2040-2225) — `ResolveUniforms`/`PackUniformValue`, `BuildPipeline`, `UploadBuffers`, `StartProcessing`'s call-site wiring
- `SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp` — full `RenderProcessor` class shape, existing helper methods (`CreateImageDedicated`, `CreateBufferDedicated`) directly reusable for texturing
- `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` (lines 195-370, 570-630, 1760-1890) — `SerializeRenderPassConfig`, `CheckProcessValidity`'s vertex_buffer gating, the "input:" resolution precedent for the new `texture_buffer` field
- `SuperGenius/SGProcessingManager/gnus-processing-schema.json` (pipeline_state, vertex_buffer, index_buffer, render_shader_config, data_type definitions) — exact schema shapes this phase's new fields must match stylistically
- `SuperGenius/SGProcessingManager/generated/PipelineState.hpp` — confirms the quicktype-generated `boost::optional<Enum>` getter/setter pattern new blend fields will follow
- `SuperGenius/test/src/processing_conformance_security/secv01_counter_test.cpp`, `secv01_tex3d_counter_test.cpp` — exact counter-test methodology and binary-search-derivation precedent to mirror
- `SuperGenius/SGProcessingManager/tools/capture/capture_harness.cpp`, `capture_diff.cpp` — exact CLI usage, `--element-type uint8` convention for render fixtures
- `.planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/11-CAPTURE-RESULTS.md` — the render fixture's own Phase 11 numbers (contentHashMatch:true, all deltas 0.0) this phase must exceed
- `.planning/workstreams/sgproc-render/phases/14-configurable-normalization-precision/14-03-SUMMARY.md` — the exact binary-search-against-a-counter-test methodology this phase's D-06 replicates, including both a "found a failure boundary" and a "found no failure boundary" outcome

### Secondary (MEDIUM confidence — external docs, cross-checked against project convention)
- [Combined image sampler — Vulkan Documentation Project](https://docs.vulkan.org/tutorial/latest/06_Texture_mapping/02_Combined_image_sampler.html) — standard `VkDescriptorImageInfo`/`vkUpdateDescriptorSets` combined-image-sampler pattern
- [Combined image sampler — Vulkan Tutorial (mirror)](https://vulkan-tutorial.com/Texture_mapping/Combined_image_sampler) — same pattern, alternate host

### Tertiary (LOW confidence — informs an open question, not a locked recommendation)
- General GPU-industry knowledge (training data, not independently verified this session) that bilinear texture filtering interpolation precision is implementation-defined and known to vary across vendors — this is the basis for Assumption A1/Pitfall 1's recommendation, flagged honestly as unverified for this specific fixture/hardware pair until the phase's own empirical capture step runs

## Metadata

**Confidence breakdown:**
- Standard stack / existing mechanism: HIGH — every claim about `ResolveByteQuantMode`/`QuantizeByteBuffer`/`ResolveUniforms`/`BuildPipeline`/wire-format structure is read directly from source this session, not inferred
- Architecture (new schema/Vulkan design for blending/texturing): HIGH confidence on the pattern-matching (mirrors existing `vertex_buffer`/`pipeline_state` conventions exactly), MEDIUM confidence on the exact field names chosen (explicitly left as Claude's Discretion by 17-CONTEXT.md — this research proposes concrete names, not the only valid ones)
- Pitfalls: HIGH for the wire-format pairing risk (directly observed in source, not speculative) — MEDIUM for the texture-filtering-divergence-magnitude risk (grounded in general GPU domain knowledge, not verified against this specific hardware pair)
- Cross-hardware divergence magnitude/final `byteQuantMode` values per fixture: UNKNOWN BY DESIGN — this is empirical work the phase itself must perform (D-06/D-09), not something research can predict

**Research date:** 2026-08-19
**Valid until:** No fixed expiry — this research is grounded in the current state of a private, actively-developed codebase (not a fast-moving external ecosystem); re-verify only if the `RenderProcessor`/`ProcessingManager.cpp`/schema files change materially before this phase is planned/executed.
