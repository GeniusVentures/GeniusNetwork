# Phase 17: Render-Path Cross-Hardware Tolerance - Pattern Map

**Mapped:** 2026-08-19
**Files analyzed:** 14 (3 fixture JSON + shaders, 2 wire-format functions, 1 schema section, BuildPipeline/ResolveUniforms edits, 3 counter-tests + 3 "wrong" fixtures, 1 synthetic texture asset)
**Analogs found:** 12 / 14 (texture-upload Vulkan sequence and sampler/descriptor code have zero in-repo precedent, per RESEARCH.md — external Vulkan-tutorial pattern used instead)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `SuperGenius/test/src/processing_dispatch/lighting-fixture-definition.json` | config (job fixture) | request-response (single-shot render job) | `SuperGenius/test/src/processing_dispatch/render-pass-happy-path-definition.json` | exact |
| `SuperGenius/test/src/processing_dispatch/lighting_fragment_shader.glsl` | utility (GPU shader) | transform (per-pixel FP compute) | `SuperGenius/test/src/processing_dispatch/solid_red_fragment_shader.glsl` (+ vertex analog `scalar_position_vertex_shader.glsl`) | role-match (new compute, same shader-stage shape) |
| `SuperGenius/test/src/processing_dispatch/blending-fixture-definition.json` | config (job fixture) | request-response | `render-pass-happy-path-definition.json` | exact (extends `pipeline_state` block) |
| `SuperGenius/test/src/processing_dispatch/texturing-fixture-definition.json` | config (job fixture) | request-response + file-I/O (new `texture_buffer` binary asset) | `render-pass-happy-path-definition.json` + `vertex_buffer`'s `"input:"` convention | role-match |
| `SuperGenius/test/src/processing_dispatch/texturing-source-image.raw` | file (synthetic RGBA8 binary asset) | file-I/O | `happy-path-vertex-data.raw` (raw binary fixture input) | role-match |
| `SuperGenius/SGProcessingManager/gnus-processing-schema.json` (`pipeline_state`, new `texture_buffer` def) | config (JSON schema) | CRUD (schema-validated data definition) | same file's existing `pipeline_state:549-574` / `vertex_buffer`/`index_buffer:~521-532` definitions | exact |
| `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` — `CheckProcessValidity()` texture_buffer gate | controller/validation | request-response (fail-closed input gating) | same file's `vertex_buffer` gate, lines 579-624 | exact |
| `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` — `Process()` texture fetch | service (I/O fetch) | file-I/O | same file's `vertex_buffer` fetch, lines 1771-1827 | exact |
| `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` — `SerializeRenderPassConfig()` (blend fields + texture section) | service (binary serializer) | transform (struct → wire bytes) | same function's existing `pipeline_state` optional-field append blocks, lines 195-370 | exact |
| `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp` — `ParseRenderPassConfig()` (inverse edits) | service (binary deserializer) | transform (wire bytes → struct) | same file's existing bounds-checked field-read blocks (inverse of serializer above) | exact |
| `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp` — `BuildPipeline()` blend wiring | service (Vulkan pipeline builder) | transform (schema config → `VkPipelineColorBlendAttachmentState`) | same function's existing hardcoded block, lines 1526-1536, and `ToVkCullMode`/`ToVkFrontFace`/`ToVkTopology` mapping-function convention (`processing_processor_render.hpp:218-221`) | exact |
| `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp` — texture upload/sampler/descriptor (new) | service (Vulkan resource creation) | file-I/O + transform (CPU bytes → GPU image) | `CreateImageDedicated()`/`CreateBufferDedicated()` (existing helpers, reused) + descriptor-set-layout block, lines 1576-1610 | role-match (no in-repo upload-path precedent; external Vulkan-tutorial pattern for staging→copy→barrier) |
| `SuperGenius/test/src/processing_conformance_security/secv01_render_lighting_counter_test.cpp` | test (GTest counter-test) | request-response (two-job byte-diff assertion) | `secv01_tex3d_counter_test.cpp` (structure) + `secv01_counter_test.cpp::RenderWrongShaderConstantStillDiverges` (render-specific job shape) | exact |
| `secv01_render_blending_counter_test.cpp` / `secv01_render_texturing_counter_test.cpp` | test (GTest counter-test) | request-response | same as above | exact |

## Pattern Assignments

### `lighting-fixture-definition.json` / `blending-fixture-definition.json` / `texturing-fixture-definition.json` (config, request-response)

**Analog:** `SuperGenius/test/src/processing_dispatch/render-pass-happy-path-definition.json` (full file, 68 lines — read in full above)

**Base job shape to copy verbatim** (`render-pass-happy-path-definition.json:1-68`):
```json
{
  "name": "render-pass-happy-path",
  "version": "1.0.0",
  "gnus_spec_version": 1.0,
  "inputs": [
    { "name": "renderInput", "source_uri_param": "file://processing_dispatch/happy-path-vertex-data.raw",
      "type": "buffer", "dimensions": { "width": 1 } }
  ],
  "outputs": [
    { "name": "renderOutput", "source_uri_param": "file://processing_dispatch/happy-path-render-output.raw", "type": "image" }
  ],
  "passes": [
    {
      "name": "renderPass",
      "type": "render",
      "render_shader": {
        "stages": [
          { "stage": "vertex", "type": "glsl", "source": "file://processing_dispatch/scalar_position_vertex_shader.glsl", "entry_point": "main" },
          { "stage": "fragment", "type": "glsl", "source": "file://processing_dispatch/solid_red_fragment_shader.glsl", "entry_point": "main" }
        ]
      },
      "render_target": { "color_format": "RGBA8", "depth_format": "D32_SFLOAT", "width": 8, "height": 8,
                          "clear_color": [0.0, 0.0, 0.0, 1.0], "clear_depth": 1.0 },
      "vertex_buffer": { "source": "input:renderInput" },
      "vertex_layout": [ { "name": "inPosition", "format": "FLOAT32", "offset": 0 } ],
      "pipeline_state": { "topology": "point_list", "cull_mode": "none", "front_face": "ccw", "depth_test": "disabled" }
    }
  ]
}
```
For all three new fixtures: copy this skeleton, keep `render_target` non-trivial (bigger than 8x8 to actually exercise interpolation — RESEARCH.md's Pattern 1/2/3 designs), and add:
- **Lighting:** a second `render_shader.uniforms` block (`lightDir`/`lightColor`/`viewPos`, all `vec3`) plus a `normal` vertex-layout entry — no new schema/C++ needed (RESEARCH.md Pattern 1).
- **Blending:** `pipeline_state.blend_enable: true` + `blend_src_factor`/`blend_dst_factor` (RESEARCH.md Pattern 2).
- **Texturing:** new top-level `texture_buffer: { "source": "input:textureData" }` sibling to `vertex_buffer` inside the pass, plus a matching `inputs[]` entry pointing at the new `.raw` RGBA8 asset (RESEARCH.md Pattern 3).
- Add a `parameters` array (new for these fixtures; happy-path has none) declaring `byteQuantMode` per Phase 14's convention — see Shared Pattern "byteQuantMode declaration" below.

**Counter-test "correct vs wrong" job pair pattern** (`secv01_counter_test.cpp:216-270`, `RenderWrongShaderConstantStillDiverges`) — mirror this inline-JSON-string job-pair shape (not a file on disk) for each of the 3 new counter-tests' "wrong" variant, changing only the one deliberately-corrupted field (wrong shader source / wrong `blend_src_factor` / wrong texture asset) while keeping everything else byte-identical between the two JSON strings.

---

### Lighting shader (`lighting_fragment_shader.glsl`) (utility, transform)

**Analog:** `SuperGenius/test/src/processing_dispatch/solid_red_fragment_shader.glsl` (stage/`#version`/`precision` conventions) — read RESEARCH.md's already-cited shader body directly for the concrete GLSL:
```glsl
#version 450
precision highp float;

layout(location = 0) in vec3 inNormal;
layout(location = 1) in vec3 inFragPos;

layout(push_constant) uniform Lighting {
    vec3 lightDir;
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
    float spec = pow(max(dot(V, R), 0.0), 32.0);
    vec3 result = (diff + spec) * u.lightColor;
    outColor = vec4(result, 1.0);
}
```
Uses only already-supported `VEC3`/`VEC4`/`MAT4` uniform types (`processing_processor_render.cpp:760-799`) — no `ResolveUniforms` change required.

**Texturing fragment shader** (RESEARCH.md Pattern 3, part 6):
```glsl
#version 450
precision highp float;
layout(location = 0) in vec2 inUV;
layout(binding = 1) uniform sampler2D texSampler;
layout(location = 0) out vec4 outColor;
void main() { outColor = texture(texSampler, inUV); }
```

---

### `gnus-processing-schema.json` — `pipeline_state` blend fields + new `texture_buffer` def (config, CRUD)

**Analog:** same file, existing `pipeline_state` object (`gnus-processing-schema.json:549-574`) and `vertex_buffer`/`index_buffer` definitions (`~521-532`).

**Blend field additions** (append after existing `depth_test` property, same enum-string style as `cull_mode`/`front_face`):
```json
"blend_enable":     { "type": "boolean", "default": false },
"blend_src_factor": { "type": "string", "enum": ["one", "zero", "src_alpha", "one_minus_src_alpha"], "default": "src_alpha" },
"blend_dst_factor": { "type": "string", "enum": ["one", "zero", "src_alpha", "one_minus_src_alpha"], "default": "one_minus_src_alpha" }
```

**New `texture_buffer` definition** (structurally identical to `vertex_buffer`, same `"input:"`-prefix pattern):
```json
"texture_buffer": {
  "type": "object",
  "required": ["source", "width", "height"],
  "properties": {
    "source": { "type": "string", "pattern": "^(input|output|internal|parameter):[a-zA-Z][a-zA-Z0-9_]*$" },
    "width":  { "type": "integer", "minimum": 1 },
    "height": { "type": "integer", "minimum": 1 },
    "filter": { "type": "string", "enum": ["nearest", "linear"], "default": "nearest" }
  }
}
```
Add `"texture_buffer": { "$ref": "#/definitions/texture_buffer" }` alongside `vertex_buffer`/`index_buffer` in the `pass` object. **After any schema edit, regenerate `generated/PipelineState.hpp` (and new blend/enum headers) via quicktype — never hand-edit `generated/`** (project convention, confirmed unverified-but-required in RESEARCH.md's Environment Availability table; run `quicktype --version` first as a cheap Wave-0 check).

---

### `ProcessingManager.cpp` — `CheckProcessValidity()` texture_buffer gate (controller/validation, request-response)

**Analog:** same file, `vertex_buffer` gate (lines 579-624, read in full above):
```cpp
if ( !pass.get_vertex_buffer() )
{
    m_logger->error( "Render pass has no vertex_buffer binding" );
    return outcome::failure( Error::PROCESS_INFO_MISSING );
}
...
auto rejectUnsupportedBufferSourcePrefix =
    [this]( const char *fieldName, const std::string &source ) -> outcome::result<void>
{
    m_logger->error(
        "Render pass {}.source '{}' uses an unsupported prefix -- "
        "only input: is resolvable (no cross-pass output:/internal: dependency "
        "graph exists; parameter:-sourced raw buffers are not supported)",
        fieldName, source );
    return outcome::failure( Error::PROCESS_INFO_MISSING );
};
{
    const auto        vertexBufferCfg = pass.get_vertex_buffer().value();
    const std::string vertexSource    = vertexBufferCfg.get_source();
    if ( vertexSource.rfind( "input:", 0 ) != 0 )
    {
        return rejectUnsupportedBufferSourcePrefix( "vertex_buffer", vertexSource );
    }
}
```
**Copy exactly for `texture_buffer`** (RESEARCH.md's own proposed code, mirroring this block 1:1): `texture_buffer` is optional (`if (pass.get_texture_buffer())`, not required like `vertex_buffer`), call `rejectUnsupportedBufferSourcePrefix("texture_buffer", textureSource)` on the same `"input:"`-only rule. Also add a dimension-bound check mirroring `render_target`'s existing DoS guard (`processing_processor_render.hpp:142-146`, no schema max — recommend reusing `kMaxRenderDimension`=8192) and a byte-length check (`textureBytes.size() == width*height*4`) before any GPU command, mirroring `UploadBuffers`'s existing stride/index-count validation (`processing_processor_render.cpp:1712-1720`).

---

### `ProcessingManager.cpp` — `Process()` texture fetch (service, file-I/O)

**Analog:** same file, `vertex_buffer` resolve/fetch (lines 1771-1827):
```cpp
// Resolve vertex_buffer.source as an independently-named "input:" reference.
const auto        vertexBufferCfg = p.get_vertex_buffer().value();
const std::string vertexSource    = vertexBufferCfg.get_source();
auto vertexInputIndex = GetInputIndex( vertexSource );
```
**Copy for `texture_buffer`** (RESEARCH.md's proposed mirror):
```cpp
if ( p.get_texture_buffer() )
{
    auto texInputIndex = GetInputIndex( p.get_texture_buffer().value().get_source() );
    if ( !texInputIndex ) { return outcome::failure( Error::MISSING_INPUT ); }
    std::string textureUrl = processing_.get_inputs()[texInputIndex.value()].get_source_uri_param();
    textureBuffer = std::make_shared<std::vector<char>>();
    GetSubCidForProc( ioc, textureUrl, textureBuffer );
}
```

---

### `ProcessingManager.cpp::SerializeRenderPassConfig()` / `processing_processor_render.cpp::ParseRenderPassConfig()` (service, transform — wire-format pair)

**Analog:** same-file existing optional-field append pattern for `pipeline_state` (`ProcessingManager.cpp:195-370`, read directly):
```cpp
auto appendU32 = [&out]( uint32_t value ) { /* ... 4-byte little-endian append ... */ };
auto appendU8  = [&out]( uint8_t value ) { out.push_back( static_cast<char>( value ) ); };
...
if ( ps.get_depth_test() )
{
    appendU8( 1 );
    appendU32( static_cast<uint32_t>( ps.get_depth_test().value() ) );
}
else
{
    appendU8( 0 );
}
```
**Copy this exact `appendU8(present?1:0)` + `appendU32(enumValue)` pattern for the 3 new blend fields**, appended immediately after the existing `depth_test` pair (RESEARCH.md Pattern 2's proposed ordering) — and copy the same optional-tag shape for the new `texture_buffer` binary section (RESEARCH.md Pattern 3, part 3):
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

**CRITICAL constraint (Pitfall 2, both files must change together):** `ParseRenderPassConfig()` on the `processing_processor_render.cpp` side is documented in its own comment as "the exact byte-for-byte inverse" of this function — every task that adds a field to `SerializeRenderPassConfig` MUST, in the same task/commit, add the matching bounds-checked read to `ParseRenderPassConfig` in the identical order. A schema-only or serializer-only change produces silent garbage values in every field read after the mismatch point, not a build error.

---

### `processing_processor_render.cpp::BuildPipeline()` blend wiring (service, transform)

**Analog:** same function's existing hardcoded block, lines 1526-1536 (`colorBlendAttachment.blendEnable = VK_FALSE`), plus the `ToVkCullMode`/`ToVkFrontFace`/`ToVkTopology` static-mapping-function convention (`processing_processor_render.hpp:218-221`).

**Pattern to copy** (RESEARCH.md's concrete replacement, follows the existing mapping-function style exactly):
```cpp
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
Add a new `ToVkBlendFactor()` static function next to `ToVkCullMode`/`ToVkFrontFace`/`ToVkTopology` declarations (`processing_processor_render.hpp:218-221`) — same signature/switch-statement shape as those existing functions.

---

### `processing_processor_render.cpp` — texture upload/sampler/descriptor (service, file-I/O + transform)

**Analog:** No in-repo precedent for the upload direction (every existing `VkImage` use in this file is a render *target*, GPU-written only). Reuse `CreateImageDedicated()` (`processing_processor_render.cpp:1022-1070`) and `CreateBufferDedicated()` (same dedicated-allocation convention, no sub-allocation — D-18/D-19) for the new `VkImage`/staging `VkBuffer`. The upload sequence itself (staging buffer → `vkCmdCopyBufferToImage` → layout transitions) has zero in-repo template; follow the external Vulkan-tutorial "Combined image sampler" pattern cited in RESEARCH.md, and mirror `UploadBuffers()`'s existing memcpy-into-staging-buffer style for the CPU-side memcpy step. Descriptor-set-layout/pool additions mirror the existing single-binding block at `processing_processor_render.cpp:1576-1610` — add binding=1 `VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER` alongside the existing binding=0 uniform buffer, and a second `VkDescriptorPoolSize` entry. Record all barriers/copies inline on the single existing command buffer per `RecordAndSubmit()`'s own doc comment (no second command buffer/queue in this codebase).

**Do NOT** route the texture through `ResolveUniforms`/`PackUniformValue`'s uniforms map (Pitfall 4) — model it as an independent `texture_buffer` pass-level field, exactly like `vertex_buffer`/`index_buffer` already bypass that map.

---

### `secv01_render_lighting_counter_test.cpp` / `_blending_` / `_texturing_` (test, request-response)

**Analog:** `SuperGenius/test/src/processing_conformance_security/secv01_tex3d_counter_test.cpp` (full structure, read in full above) and `secv01_counter_test.cpp::RenderWrongShaderConstantStillDiverges` (lines 200-270+, render-specific job shape/GTEST_SKIP guard).

**Structure to copy verbatim** (test fixture class, `HasUsableVulkanDevice()` skip guard, `ProcessingManager::Create()` → `Process()` → binary `memcmp` assertion):
```cpp
class Secv01Render<Technique>CounterTest : public ProcessorConformanceFixture {};

TEST_F( Secv01Render<Technique>CounterTest, <Technique>WrongXStillDiverges )
{
    if ( !sgns::sgprocessing::HasUsableVulkanDevice() )
    {
        GTEST_SKIP() << "No usable Vulkan device...";
    }
    // correctJson / corruptedJson: identical render job strings except ONE
    // deliberately-wrong field (light color / blend factor / texture asset),
    // both declaring the SAME candidate byteQuantMode under test.
    ...
    EXPECT_NE( std::memcmp( prCorrect.value().artifacts[0].artifactId,
                             prCorrupted.value().artifacts[0].artifactId,
                             sgns::sgprocessing::SHA256_HASH_SIZE ),
               0 )
        << "A deliberately corrupted <X> must produce a different post-quantization "
           "artifactId than the correct <X> at this fixture's own empirically-derived "
           "byteQuantMode -- SECV-01/T-17-XX";
}
```
Binary-compare ONLY `artifacts[0].artifactId`, never `ExecutionManifest::manifestHash`/`combinedHash` (13-03's documented distinction, reused verbatim from `secv01_tex3d_counter_test.cpp`'s own comment). Register in `SuperGenius/test/src/processing_conformance_security/CMakeLists.txt`'s existing `processing_conformance_security_test` target (add 3 new `.cpp` sources, no new target).

**"Deliberately wrong" fixture design per technique** (mirrors `secv01-wrong-color.frag`'s "structurally identical, materially different constant" convention):
- Lighting: wrong `lightColor`/`lightDir` uniform value, identical shader code.
- Blending: wrong `blend_src_factor`/`blend_dst_factor`, identical shader/geometry.
- Texturing: a byte-perturbed copy of `texturing-source-image.raw` (mirrors `secv01_tex3d_counter_test.cpp`'s byte-perturbed `.mnn` model precedent), identical shader/sampler config.

## Shared Patterns

### byteQuantMode declaration (generic `parameters` array, Phase 14 convention)
**Source:** `secv01_tex3d_counter_test.cpp:98-109` (the `quantScale` parameter declaration, structurally identical mechanism):
```json
"parameters": [
    { "name": "byteQuantMode", "type": "int", "default": <N> }
]
```
**Apply to:** all three new fixture JSON files, and both correct/corrupted variants of all three new counter-tests (same candidate `N` in both, per D-06's binary-search discipline).

### Wire-format pairing discipline (Pitfall 2)
**Source:** `ProcessingManager.cpp::SerializeRenderPassConfig()` (lines 195-370) / `processing_processor_render.cpp::ParseRenderPassConfig()` (its documented "exact byte-for-byte inverse")
**Apply to:** every plan task touching `pipeline_state` blend fields or the new `texture_buffer` binary section — the serializer and parser edits must land in the same task, never split across waves, and verification must include an end-to-end `Create()`+`Process()` round-trip, not a unit test of one side only.

### "input:"-prefix-only fail-closed gating
**Source:** `ProcessingManager.cpp:596-624` (`rejectUnsupportedBufferSourcePrefix` lambda, `vertex_buffer`/`index_buffer`'s existing gate)
**Apply to:** the new `texture_buffer` field's `CheckProcessValidity()` gate — reuse the exact same lambda/rule (`"input:"` only, reject `output:`/`internal:`/`parameter:`).

### Binary-search-against-counter-test tolerance derivation
**Source:** `secv01_tex3d_counter_test.cpp:12-50` (full doc-comment methodology, `S=256/128/64/2/1` search log) — the exact template D-06 replicates for `byteQuantMode ∈ [0,8]`.
**Apply to:** all three fixtures independently; no shared/global tolerance value. Direction note: for `byteQuantMode`, INCREASING `N` is the "more tolerant" direction (opposite of `quantScale`'s decreasing-S convention) — see RESEARCH.md's Tolerance Derivation Methodology step 4 for the exact search-direction reasoning.

### GTEST_SKIP guard for GPU-dependent tests
**Source:** `secv01_counter_test.cpp:200-206` (`HasUsableVulkanDevice()` check)
**Apply to:** all 3 new counter-tests and any new dispatch/integration tests exercising the render path on a machine without a usable Vulkan device.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| Texture upload sequence (staging buffer → `vkCmdCopyBufferToImage` → layout transition → `VkSampler`) inside `processing_processor_render.cpp` | service | file-I/O + transform | Every existing `VkImage` use in this file is a render *target* (GPU-written only); no CPU-to-GPU image upload path exists anywhere in the codebase to crib from. Use the external Vulkan-tutorial "Combined image sampler" pattern (cited in RESEARCH.md Sources, Secondary) adapted to this file's `CreateBufferDedicated()`/`CreateImageDedicated()` dedicated-allocation helpers and inline single-command-buffer submission style. |
| `texturing-source-image.raw` generation script | utility (one-off asset generator) | transform | No existing procedural-image-generation script in the repo; RESEARCH.md recommends a short one-off script producing a small checkerboard/gradient RGBA8 buffer — do not vendor a PNG decoder or real photo. |

## Metadata

**Analog search scope:** `SuperGenius/SGProcessingManager/src/processingbase/`, `SuperGenius/SGProcessingManager/src/processors/`, `SuperGenius/SGProcessingManager/gnus-processing-schema.json`, `SuperGenius/test/src/processing_dispatch/`, `SuperGenius/test/src/processing_conformance_security/`
**Files scanned:** `ProcessingManager.cpp` (targeted reads: lines 100-370, 570-630, 1160-1220, 1700-1920), `processing_processor_render.cpp`/`.hpp` (per RESEARCH.md's own targeted reads, lines 700-950/1440-1830/2040-2225, not re-read here), `render-pass-happy-path-definition.json` (full), `secv01_tex3d_counter_test.cpp` (full), `secv01_counter_test.cpp` (targeted, lines 200-270)
**Pattern extraction date:** 2026-08-19
