---
phase: 17-render-path-cross-hardware-tolerance
plan: 04
subsystem: render-processing
tags: [vulkan, glsl, texturing, sampler, descriptor-set, capture-harness, sgprocessingmanager]

requires:
  - phase: 17-render-path-cross-hardware-tolerance
    provides: "Plan 03's texture_buffer schema/wire-format contract (ParseRenderPassConfig's outHasTextureBuffer/outTextureWidth/outTextureHeight/outTextureBytes out-params) that this plan's UploadTexture()/BuildPipeline()/RecordAndSubmit() consume"
provides:
  - "RenderProcessor::UploadTexture() -- staging buffer -> device-local sampled VkImage -> VkImageView -> VkSampler (VK_FILTER_NEAREST) -> binding=1 combined-image-sampler descriptor write, with T-17-09's byte-count-vs-dimensions validation gating every GPU resource creation"
  - "BuildPipeline()'s hasTexture parameter and dynamic VkDescriptorSetLayoutBinding/VkDescriptorPoolSize vectors, so binding=1 (texture) and binding=0 (uniform buffer) can each independently exist"
  - "RecordAndSubmit()'s pre-render-pass texture upload barrier/copy/barrier sequence, recorded into the same single command buffer/submission as the draw and readback copy"
  - "texturing-fixture-definition.json + texturing_vertex_shader.glsl + texturing_fragment_shader.glsl + texturing-vertex-data.raw -- the first fixture to exercise Waves 2-3's full texturing contract together, smoke-verified end-to-end via capture_harness on real hardware (rendered output byte-identical to the source checkerboard)"
affects: [17-05-cross-machine-capture, 17-06-tolerance-derivation]

tech-stack:
  added: []
  patterns: ["texture upload path modeled as staging-buffer->device-local-image->view->sampler->descriptor-write, mirroring the Vulkan combined-image-sampler tutorial pattern adapted to this file's existing CreateBufferDedicated()/CreateImageDedicated() dedicated-allocation helpers (RESEARCH.md Pattern 3)"]

key-files:
  created:
    - SuperGenius/test/src/processing_dispatch/texturing-fixture-definition.json
    - SuperGenius/test/src/processing_dispatch/texturing_vertex_shader.glsl
    - SuperGenius/test/src/processing_dispatch/texturing_fragment_shader.glsl
    - SuperGenius/test/src/processing_dispatch/texturing-vertex-data.raw
  modified:
    - SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp

key-decisions:
  - "The wire format (17-03) never carries a per-texture filter mode across SerializeRenderPassConfig/ParseRenderPassConfig, so UploadTexture() is always invoked with sgns::TextureFilter::NEAREST from StartProcessing() regardless of what the fixture's texture_buffer.filter schema field declares -- this matches Pitfall 1's recommended bit-reproducible default and the fixture's own filter:\"nearest\" declaration, but the schema's filter field is not yet functionally threaded through end-to-end. Documented here rather than silently assumed; adding a filter tag to the wire format was out of this plan's files_modified scope (ProcessingManager.cpp is not listed)."

requirements-completed: [RENDTOL-01, RENDTOL-02]

coverage:
  - id: D1
    description: "UploadTexture() validates textureBytes.size() == width*height*4 before any CreateBufferDedicated/CreateImageDedicated call, failing closed with RESOURCE_RESOLUTION on mismatch (T-17-09)"
    requirement: RENDTOL-01
    verification:
      - kind: other
        ref: "grep-verified: the size check (line ~1197 of processing_processor_render.cpp) appears before the function's first CreateBufferDedicated call (line ~1207); a CheckFormatSupport gate runs even earlier"
        status: pass
    human_judgment: false
  - id: D2
    description: "BuildPipeline()'s descriptor-set-layout/pool building is restructured to dynamic std::vector<VkDescriptorSetLayoutBinding>/std::vector<VkDescriptorPoolSize>, with a binding=1 VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER entry gated on a new hasTexture parameter, independent of whether uniforms also route through a descriptor set (binding=0)"
    requirement: RENDTOL-01
    verification:
      - kind: other
        ref: "grep-verified: useDescriptorSet = hasTexture || hasUniformDescriptor; bindings/poolSizes built as std::vector, each entry pushed conditionally; ProcessingBase target builds cleanly"
        status: pass
    human_judgment: false
  - id: D3
    description: "RecordAndSubmit() records exactly two vkCmdPipelineBarrier calls and one vkCmdCopyBufferToImage call (UNDEFINED->TRANSFER_DST_OPTIMAL, copy, TRANSFER_DST_OPTIMAL->SHADER_READ_ONLY_OPTIMAL), gated on m_hasTexture, all before vkCmdBeginRenderPass -- no second vkQueueSubmit is introduced"
    requirement: RENDTOL-01
    verification:
      - kind: other
        ref: "grep -c on the function body (lines 2136-2363): vkCmdPipelineBarrier=2, vkCmdCopyBufferToImage=1, vkQueueSubmit call sites=1 (2 other matches are a comment and an error-message string, not calls)"
        status: pass
    human_judgment: false
  - id: D4
    description: "texturing-fixture-definition.json (64x64 render pass, vertex_buffer + texture_buffer with filter:nearest, full-screen-triangle vertex data mapping the UV range [0,1]x[0,1] onto the viewport) runs end-to-end via capture_harness on real hardware, actually sampling the checkerboard texture"
    requirement: RENDTOL-02
    verification:
      - kind: other
        ref: "capture_harness --fixture-root SuperGenius/test/src --fixture processing_dispatch/texturing-fixture-definition.json --label smoke-texturing --repeat 2 --model-input-source input:texturingVertexInput -- stdout contained \"wrote ... 2/2 stable runs\" on NVIDIA GeForce RTX 4070 Ti SUPER; the resulting texturing-render-output.raw (16384 bytes) was byte-for-byte identical (0/16384 diffs) to texturing-source-image.raw, confirming the sampler/descriptor/upload path actually samples the texture, not merely compiles"
        status: pass
    human_judgment: false

duration: 50min
completed: 2026-08-20
status: complete
---

# Phase 17 Plan 4: Texturing Vulkan Implementation and Fixture Summary

**RenderProcessor gains a real combined-image-sampler upload path (staging buffer -> device-local VkImage -> layout-transition barriers -> vkCmdCopyBufferToImage -> VkImageView -> VkSampler -> descriptor binding=1) proven end-to-end by a new 64x64 texturing fixture whose rendered output is byte-identical to its source checkerboard texture.**

## Performance

- **Duration:** 50 min
- **Started:** 2026-08-19T22:51:15Z (per STATE.md's prior stopped-at timestamp)
- **Completed:** 2026-08-20T00:24:00Z
- **Tasks:** 2
- **Files modified:** 6 (2 in the SGProcessingManager nested submodule, 4 new fixture files in SuperGenius, plus submodule pointer bumps)

## Accomplishments
- Added `RenderProcessor::UploadTexture()`: a `CheckFormatSupport(VK_FORMAT_R8G8B8A8_UNORM, VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT, ...)` fail-closed gate, then `textureBytes.size() == width*height*4` validation (T-17-09) before any GPU resource is created, then a HOST_VISIBLE|HOST_COHERENT staging buffer (`CreateBufferDedicated`), a `DEVICE_LOCAL` sampled `VkImage` (`CreateImageDedicated`, `TRANSFER_DST_BIT | SAMPLED_BIT`), a `VkImageView`, and a `VkSampler` (`VK_FILTER_NEAREST` by default, `CLAMP_TO_EDGE`, anisotropy/mipmapping disabled per T-17-11's accepted-risk minimal-sampler-state decision) -- finally writing the descriptor set's binding=1 `VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER` entry via `vkUpdateDescriptorSets`, mirroring `UploadBuffers()`'s existing binding=0 write.
- Restructured `BuildPipeline()`'s descriptor-set-layout/pool building from single fixed structs to `std::vector<VkDescriptorSetLayoutBinding>`/`std::vector<VkDescriptorPoolSize>`, added a new `hasTexture` parameter, and changed `useDescriptorSet`'s condition to `hasTexture || hasUniformDescriptor` -- a descriptor set (and binding=1) now exists whenever a texture is present, independent of whether uniforms also route through a descriptor set (binding=0 only appears when uniforms need it).
- Extended `RecordAndSubmit()` with a pre-render-pass texture upload sequence -- `vkCmdPipelineBarrier` (UNDEFINED -> TRANSFER_DST_OPTIMAL), `vkCmdCopyBufferToImage`, `vkCmdPipelineBarrier` (TRANSFER_DST_OPTIMAL -> SHADER_READ_ONLY_OPTIMAL) -- recorded into the exact same command buffer the draw and readback copy already use; confirmed via grep that the function still records only one `vkQueueSubmit` call.
- Wired `hasTextureBuffer`/`textureWidth`/`textureHeight`/`textureBytes` (17-03's already-parsed out-params) into `BuildPipeline()`'s new parameter and a new `UploadTexture()` call in `StartProcessing()`, positioned after `UploadBuffers()` succeeds (so `m_descriptorSet` already exists) and before `RecordAndSubmit()` (so `m_hasTexture` is set before the barrier/copy sequence is recorded).
- Authored the texturing fixture: a full-screen-triangle vertex shader passing UV coordinates through, a fragment shader sampling `binding=1 sampler2D`, a 48-byte vertex buffer (3 vertices, posX/posY/uvX/uvY) whose UV range covers exactly `[0,1]x[0,1]` across the 64x64 viewport, and `texturing-fixture-definition.json` combining `vertex_buffer` + `texture_buffer` (`filter: "nearest"`) against 17-03's already-committed `texturing-source-image.raw` checkerboard.
- Smoke-verified via `capture_harness` on real hardware (NVIDIA GeForce RTX 4070 Ti SUPER, DISCRETE_GPU): 2/2 stable runs, `.cap` file written. Went further than the plan's literal bar (stdout containing "wrote") by directly diffing the produced `texturing-render-output.raw` against the source checkerboard: 0/16384 byte differences -- proof the sampler/descriptor/upload infrastructure actually samples the texture correctly, not merely that the pipeline runs without error.

## Task Commits

Each task was committed atomically (submodule-first, then outer-repo pointer bump, per this project's convention):

1. **Task 1: Build the texture upload path -- staging buffer, VkImage, sampler, and the new descriptor binding**
   - `243fefb` (SGProcessingManager nested submodule, feat) -- `UploadTexture()`, `BuildPipeline()`'s `hasTexture` parameter and dynamic binding vectors, `RecordAndSubmit()`'s upload barrier/copy sequence, `StartProcessing()`'s wiring
   - `6fbb4ddb` (SuperGenius submodule, chore) -- bump SGProcessingManager submodule pointer to `243fefb`
   - `59d550d` (outer repo, chore) -- bump SuperGenius submodule pointer to `6fbb4ddb`
2. **Task 2: Author the texturing fixture and smoke-verify it via capture_harness**
   - `07c52f05` (SuperGenius submodule, feat) -- `texturing_vertex_shader.glsl`, `texturing_fragment_shader.glsl`, `texturing-vertex-data.raw`, `texturing-fixture-definition.json`
   - `136ba3e` (outer repo, chore) -- bump SuperGenius submodule pointer to `07c52f05`

**Plan metadata:** committed via the standard `docs({phase}-{plan}): complete [plan-name] plan` final commit (see below)

_Note: no TDD tasks in this plan (Vulkan resource-creation code and fixture authoring, mirroring 17-01/17-02/17-03's precedent)._

## Files Created/Modified
- `SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp` - `UploadTexture()` declaration, `BuildPipeline()`'s new `hasTexture` parameter, eight new texture-related private members (`m_textureStagingBuffer`/`m_textureStagingMemory`/`m_textureImage`/`m_textureMemory`/`m_textureView`/`m_textureSampler`/`m_hasTexture`/`m_textureWidth`/`m_textureHeight`), new `<TextureFilter.hpp>` include
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp` - `UploadTexture()` definition, `BuildPipeline()`'s restructured descriptor-set-layout/pool building and new parameter, `RecordAndSubmit()`'s upload barrier/copy/barrier sequence, `StartProcessing()`'s `BuildPipeline`/`UploadTexture` call-site wiring
- `SuperGenius/test/src/processing_dispatch/texturing_vertex_shader.glsl` (new) - forwards `inPosX`/`inPosY` to `gl_Position`, passes `inUvX`/`inUvY` through as `outUV`
- `SuperGenius/test/src/processing_dispatch/texturing_fragment_shader.glsl` (new) - `layout(binding = 1) uniform sampler2D texSampler`, `outColor = texture(texSampler, inUV)`
- `SuperGenius/test/src/processing_dispatch/texturing-vertex-data.raw` (new) - 48-byte full-screen-triangle vertex buffer (3 vertices x posX/posY/uvX/uvY)
- `SuperGenius/test/src/processing_dispatch/texturing-fixture-definition.json` (new) - 64x64 render pass combining `vertex_buffer` + `texture_buffer` (`filter: "nearest"`) against 17-03's `texturing-source-image.raw`

## Decisions Made
- The wire format (17-03) never threads a per-texture filter mode across `SerializeRenderPassConfig`/`ParseRenderPassConfig`, so `UploadTexture()` is always invoked with `sgns::TextureFilter::NEAREST` from `StartProcessing()` regardless of what the fixture's `texture_buffer.filter` schema field declares. This matches Pitfall 1's recommended bit-reproducible default and the fixture's own `filter: "nearest"` declaration, so no behavioral gap exists for this plan's fixture -- but the schema's `filter` field is not yet functionally threaded through end-to-end (a job declaring `filter: "linear"` would still render with `NEAREST`). Editing `ProcessingManager.cpp`'s wire format to carry the filter tag was out of this plan's `files_modified` scope; flagged here rather than silently assumed, for whoever revisits texturing's `LINEAR` path.
- Went beyond the plan's literal verification bar (capture_harness stdout containing "wrote") by directly byte-diffing the rendered output against the source texture (0/16384 diffs) -- a stronger, more direct proof that the sampler infrastructure is functionally correct, not just that the pipeline completed without error.

## Deviations from Plan

None - plan executed exactly as written. `BuildPipeline`'s only existing caller (`StartProcessing`) was updated in the same task/commit; no other call sites existed to break.

## Issues Encountered
None. `capture_harness` required the already-known `--model-input-source input:texturingVertexInput` flag for this render-type fixture (no MNN model field) -- the same requirement documented as a deviation in 17-01's SUMMARY, applied here without needing to re-discover it.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Texturing's Vulkan infrastructure is complete and functionally proven end-to-end on real hardware -- RENDTOL-01 now has all three fixtures (lighting, blending, texturing) built and smoke-verified. RENDTOL-02 (empirical tolerance derivation) remains entirely for Waves 4-7 (17-05/17-06) -- no `byteQuantMode` value has been derived for any of the three fixtures yet, and no cross-machine capture has been run for texturing.
- The captured `.cap` file from this plan's smoke run (`captures/smoke/smoke-texturing_Mofu---Windows_20260820T002314.cap`) is a same-machine smoke artifact only, not part of the two-machine (Mac+Windows) empirical dataset D-09 requires -- Wave 4/17-05 will need its own fresh same-convention capture on both machines.
- Per REQUIREMENTS.md's mark-complete SOP note carried from 17-02/17-03's summaries: RENDTOL-01/RENDTOL-02 checkboxes should reflect "all 3 fixtures built" (true as of this plan) but RENDTOL-02 must stay pending until real cross-machine capture data and a derived tolerance value exist -- not yet true.

---
*Phase: 17-render-path-cross-hardware-tolerance*
*Completed: 2026-08-20*

## Self-Check: PASSED

All 4 created fixture files exist on disk (texturing-fixture-definition.json, texturing_vertex_shader.glsl, texturing_fragment_shader.glsl, texturing-vertex-data.raw, 48 bytes), the SUMMARY.md file exists, and all 5 task commit hashes (243fefb in SGProcessingManager; 6fbb4ddb, 59d550d, 07c52f05, 136ba3e across SuperGenius and the outer repo) are present in their respective git histories.
