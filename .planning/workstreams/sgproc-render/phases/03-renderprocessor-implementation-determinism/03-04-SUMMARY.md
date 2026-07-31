---
phase: 03-renderprocessor-implementation-determinism
plan: 04
subsystem: SGProcessingManager (RenderProcessor)
tags: [vulkan, render-pass, framebuffer, graphics-pipeline, determinism]

requires:
  - phase: 03-03
    provides: "ParsedStage/RenderTarget/PipelineState/VertexLayoutEntry/ResolvedUniforms data structures and CreateImageDedicated()/CreateBufferDedicated()/CheckFormatSupport()/PushTeardown() allocation helpers this plan's render pass/pipeline code consumes"
provides:
  - "RenderProcessor::BuildRenderPass() -- offscreen VkRenderPass (color+depth, explicit CLEAR load ops, VK_SAMPLE_COUNT_1_BIT, format-support-checked before creation), sets m_renderWidth/m_renderHeight"
  - "RenderProcessor::BuildFramebuffer() -- offscreen VkFramebuffer with dedicated color+depth VkImage/VkImageView pairs (DEVICE_LOCAL) referencing m_renderPass"
  - "RenderProcessor::BuildPipeline() -- complete VkPipeline: per-stage VkShaderModule from real entry points, fixed (never dynamic) pipeline state from schema or defaults, auto-computed vertex input, pipeline layout branching on the push-constant/descriptor-set threshold"
  - "RenderProcessor::ToVkFormat(ColorFormat|DepthFormat|VertexLayoutFormat)/ToVkTopology()/ToVkCullMode()/ToVkFrontFace()/ToVkBool()/VertexFormatByteSize() -- schema-to-Vulkan mapping helpers"
  - "kMaxRenderDimension -- new 8192 render_target width/height bound (DoS guard)"
affects: [03-05-startprocessing-wiring-and-determinism]

tech-stack:
  added: []
  patterns:
    - "Fixed (never VK_DYNAMIC_STATE_*) pipeline state baked into VkGraphicsPipelineCreateInfo at creation time, matching D-22's fresh-pipeline-per-job design -- includes viewport/scissor, which the plan's action text didn't explicitly call out but VkGraphicsPipelineCreateInfo requires when no dynamic viewport/scissor state is used"
    - "Format-support-checked-before-creation (CheckFormatSupport() called for both color and depth formats before any VkImage/VkRenderPass exists) -- RESEARCH.md Pitfall 7"
    - "Per-stage shader-module teardown registered immediately after each successful vkCreateShaderModule, before the next stage's module is created -- an earlier stage's module is never leaked if a later stage's creation fails (D-24)"
    - "Scalar-component vertex_layout reading: stride = sum of per-entry scalar byte sizes, location = array index -- documented in 03-04-PLAN.md as the only defensible reading given the schema has no vec2/vec3/vec4 variant or explicit location field"

key-files:
  created: []
  modified:
    - SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp

key-decisions:
  - "Added m_renderWidth/m_renderHeight member state (set by BuildRenderPass() after its bounds check succeeds, consumed by BuildPipeline()'s fixed viewport/scissor) -- the plan's BuildPipeline() signature and action text never mention viewport/scissor at all, but VkGraphicsPipelineCreateInfo requires a concrete VkPipelineViewportStateCreateInfo (with real width/height) whenever no VK_DYNAMIC_STATE_VIEWPORT/SCISSOR is used, and D-22/the plan's own VK_DYNAMIC_STATE==0 acceptance criterion forbid dynamic viewport/scissor. This is a Rule 3 (blocking-issue) fix: without it, BuildPipeline() could not produce a valid VkGraphicsPipelineCreateInfo at all."
  - "Depth image view's aspectMask conditionally includes VK_IMAGE_ASPECT_STENCIL_BIT when depth_format is D24_UNORM_S8_UINT (which has a stencil component the schema never exposes/uses) -- Vulkan's depth-stencil-attachment image-view rules require the aspectMask to reflect every aspect physically present in the image. This is a Rule 1/2 addition: the plan's action text specifies stencilLoadOp/StoreOp=DONT_CARE for the unused stencil aspect at the render-pass level, but doesn't separately call out the image view's aspectMask, which needed the same treatment for correctness."
  - "Comment wording near the fixed viewport/scissor code avoids the literal substring 'VK_DYNAMIC_STATE' (an early draft's comment read 'per D-22/acceptance-criteria's VK_DYNAMIC_STATE==0', which self-polluted the plan's own grep -c \"VK_DYNAMIC_STATE\" == 0 acceptance criterion to 1) -- same class of self-defeating-comment issue as 03-03-SUMMARY's vkAllocateMemory precedent."
  - "Committed as two atomic per-task commits by reverting to the prior commit and re-applying each task's code in isolation (rather than one combined edit), so each task's own acceptance-criteria greps could be verified against that task's commit in isolation, matching the plan's Task 1/Task 2 boundary exactly."

metrics:
  duration: "~35 min"
  completed: "2026-07-31"
status: complete
---

# Phase 3 Plan 4: RenderProcessor Render Pass/Framebuffer + Graphics Pipeline Construction Summary

**Built RenderProcessor's offscreen VkRenderPass/VkFramebuffer (color+depth, explicit clears, format-checked) and its complete VkGraphicsPipeline (fixed pipeline state, auto-computed vertex input, push-constant/descriptor-set-branching layout) -- Vulkan objects only, no command buffer recording, buffer upload, or readback yet, and `StartProcessing()` is still the pre-existing stub (that wiring is plan 03-05's job).**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-07-31
- **Tasks:** 2
- **Files modified:** 2 (SGProcessingManager submodule) + 2 submodule-pointer bumps (SuperGenius, GeniusNetwork)

## Accomplishments

- `BuildRenderPass()` bounds-checks `render_target.width/height` against the new `kMaxRenderDimension` (8192), calls plan 03-03's `CheckFormatSupport()` for both color and depth formats before creating anything (RESEARCH.md Pitfall 7), then creates a `VkRenderPass` with `VK_ATTACHMENT_LOAD_OP_CLEAR` on both color and depth attachments (never `DONT_CARE` except the legitimately-unused stencil aspect), `VK_SAMPLE_COUNT_1_BIT` unconditionally (DETV-02), and the color attachment's `finalLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL` so plan 03-05's `vkCmdCopyImageToBuffer` needs no extra barrier.
- `BuildFramebuffer()` allocates dedicated color+depth `VkImage`/`VkImageView` pairs via plan 03-03's `CreateImageDedicated()` (`VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT`, `VK_SAMPLE_COUNT_1_BIT`) and builds the `VkFramebuffer` referencing `m_renderPass` at the target's width/height.
- `BuildPipeline()` builds one `VkShaderModule`/`VkPipelineShaderStageCreateInfo` per parsed stage using each stage's real `entry_point` (plan 03-01's wire format), never a hard-coded `"main"`; computes vertex input binding/attributes from `vertex_layout`'s scalar-component reading; bakes `topology`/`cull_mode`/`front_face`/`depth_test` from `pipeline_state` (or schema defaults) with `depthCompareOp` fixed at `VK_COMPARE_OP_LESS` (D-14) and multisample fixed at `VK_SAMPLE_COUNT_1_BIT` (DETV-02); and builds a pipeline layout that branches on D-29/D-30's fixed 128-byte push-constant threshold (push-constant range, a single descriptor-set-layout/pool/set, or neither when no uniforms are declared).
- New schema-to-Vulkan mapping helpers: `ToVkFormat(ColorFormat|DepthFormat|VertexLayoutFormat)`, `ToVkTopology()`, `ToVkCullMode()`, `ToVkFrontFace()`, `ToVkBool(DepthTest)`, `VertexFormatByteSize()`.
- Every object this plan creates (render pass, color/depth images+views, framebuffer, shader modules, descriptor set layout/pool, pipeline layout, pipeline) registers its teardown via plan 03-03's `PushTeardown()` in creation order, satisfying D-22/D-24's "always destroy whatever was already created" rule.

## Task Commits

Each task was committed atomically (SGProcessingManager submodule):

1. **Task 1: Offscreen render pass + framebuffer (color+depth, explicit clears)** - `dff39f6` (feat)
2. **Task 2: Graphics pipeline (fixed pipeline state, vertex input, push-constant/descriptor-set layout)** - `d51a572` (feat)

**Submodule pointer bumps:**
- SuperGenius: `8126c094` (chore) -- points to SGProcessingManager `d51a572`, encompassing both tasks
- GeniusNetwork: `ce82866` (chore) -- points to SuperGenius `8126c094`

## Files Created/Modified

- `SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp` - `kMaxRenderDimension` constant; `BuildRenderPass()`/`BuildFramebuffer()`/`BuildPipeline()` declarations; `ToVkFormat`/`ToVkTopology`/`ToVkCullMode`/`ToVkFrontFace`/`ToVkBool`/`VertexFormatByteSize` static helper declarations; new member state (`m_renderWidth`/`m_renderHeight`, `m_renderPass`, `m_framebuffer`, `m_colorImage`/`m_depthImage`, `m_colorView`/`m_depthView`, `m_colorMemory`/`m_depthMemory`, `m_pipelineLayout`, `m_pipeline`, `m_descriptorSetLayout`, `m_descriptorPool`, `m_descriptorSet`).
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp` - implementations of all of the above, plus new includes for `ColorFormat.hpp`/`DepthFormat.hpp`/`Topology.hpp`/`CullMode.hpp`/`FrontFace.hpp`/`DepthTest.hpp`/`VertexLayoutFormat.hpp` (full enum definitions needed for the mapping-helper switch statements).

## Decisions Made

- **Added `m_renderWidth`/`m_renderHeight` member state**: the plan's `BuildPipeline()` signature and action text never mention a render-target-dimensions parameter, viewport, or scissor at all, but `VkGraphicsPipelineCreateInfo` requires a concrete `VkPipelineViewportStateCreateInfo` with real width/height whenever no `VK_DYNAMIC_STATE_VIEWPORT`/`SCISSOR` is used -- and D-22 plus the plan's own `grep -c "VK_DYNAMIC_STATE" == 0` acceptance criterion forbid using dynamic viewport/scissor state. `BuildRenderPass()` sets these two fields right after its own bounds check succeeds (the authoritative already-validated source), and `BuildPipeline()` reads them for a fixed viewport/scissor sized to the actual framebuffer. Without this, `BuildPipeline()` could not construct a valid `VkGraphicsPipelineCreateInfo` at all -- a Rule 3 (blocking-issue) fix.
- **Depth image view's `aspectMask` conditionally includes `VK_IMAGE_ASPECT_STENCIL_BIT`** when `depth_format == D24_UNORM_S8_UINT`: this format has a stencil component the schema never exposes/uses, but Vulkan's depth-stencil-attachment image-view rules require the view's `aspectMask` to reflect every aspect physically present in the underlying image, not just the aspects the application cares about. The plan's action text calls out `stencilLoadOp`/`stencilStoreOp = DONT_CARE` at the render-pass-attachment level for this same reason but doesn't separately mention the image view's `aspectMask` -- added for correctness (Rule 1/2).
- **Comment wording near the viewport/scissor code deliberately avoids the literal substring `VK_DYNAMIC_STATE`**: an early draft's comment read "per D-22/acceptance-criteria's VK_DYNAMIC_STATE==0", which self-polluted the plan's own `grep -c "VK_DYNAMIC_STATE"` acceptance criterion from the expected 0 to 1. Reworded to "per D-22" without repeating the literal macro-name substring, matching 03-03-SUMMARY's precedent for the same class of self-defeating-comment issue (that plan's `vkAllocateMemory` grep).
- **Two atomic per-task commits produced by reverting and re-applying each task's code in isolation**: since both tasks' code was drafted together during implementation exploration, the file was reverted to the prior commit (`git checkout --` on the two modified files, a project-sanctioned non-destructive per-file revert) and each task's code was re-applied and independently build-verified before its own commit, so Task 1's commit (`dff39f6`) contains only `BuildRenderPass`/`BuildFramebuffer`/the two `ColorFormat`/`DepthFormat` mapping helpers, and Task 2's commit (`d51a572`) contains only `BuildPipeline` and its five remaining mapping helpers -- matching the plan's Task 1/Task 2 boundary exactly, with each task's own acceptance-criteria greps verified against that task's isolated commit state.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] `BuildPipeline()` needed render-target width/height for a mandatory static viewport/scissor, which the plan's signature/action text never provided**
- **Found during:** Task 2 implementation, while assembling `VkGraphicsPipelineCreateInfo`.
- **Issue:** The plan's `BuildPipeline()` declaration and action text list every other fixed-function state block (vertex input, input assembly, rasterization, depth-stencil, multisample, pipeline layout) but never mention `VkPipelineViewportStateCreateInfo`, `VkViewport`, or `VkRect2D` scissor at all -- yet `vkCreateGraphicsPipelines` requires a valid `pViewportState` with concrete extents whenever the pipeline doesn't use `VK_DYNAMIC_STATE_VIEWPORT`/`SCISSOR`, and D-22 plus the plan's own acceptance criterion (`grep -c "VK_DYNAMIC_STATE" == 0`) forbid using that dynamic state.
- **Fix:** Added `m_renderWidth`/`m_renderHeight` member state, set by `BuildRenderPass()` immediately after its own width/height bounds check succeeds (the same values already used to size the framebuffer/images in Task 1), and read by `BuildPipeline()` to build a fixed, full-framebuffer-sized viewport and scissor.
- **Files modified:** `SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp`, `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp`
- **Verification:** Full CMake link-build of `SGProcessors` succeeded with the fix; `vkCreateGraphicsPipelines` receives a fully-populated, valid `VkGraphicsPipelineCreateInfo`.
- **Committed in:** `dff39f6` (Task 1, the member-state addition) and `d51a572` (Task 2, the viewport/scissor construction that consumes it).

**2. [Rule 1 - Bug] Depth image view's `aspectMask` omitted the stencil aspect for `D24_UNORM_S8_UINT`**
- **Found during:** Task 1 implementation, while writing `BuildFramebuffer()`'s depth `VkImageViewCreateInfo`.
- **Issue:** A first draft set the depth image view's `subresourceRange.aspectMask` to `VK_IMAGE_ASPECT_DEPTH_BIT` unconditionally. For `D32_SFLOAT` this is correct (no stencil component exists), but `D24_UNORM_S8_UINT` has a physical stencil aspect the schema never exposes/uses -- Vulkan's depth-stencil-attachment image-view rules require the view's `aspectMask` to include every aspect actually present in the image when used as a framebuffer attachment.
- **Fix:** Added a conditional check on `target.get_depth_format() == sgns::DepthFormat::D24_UNORM_S8_UINT` that ORs in `VK_IMAGE_ASPECT_STENCIL_BIT` for that specific format.
- **Files modified:** `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp`
- **Verification:** Full CMake link-build succeeded; existing dispatch/datatypes test suites unaffected (neither exercises the render pipeline's actual draw/readback path yet -- that's plan 03-05).
- **Committed in:** `dff39f6` (Task 1 commit).

**3. [Rule 1 - Bug] `grep -c "VK_DYNAMIC_STATE"` returned 1 instead of the plan's expected 0**
- **Found during:** Task 2's own acceptance-criteria self-check, before committing.
- **Issue:** An explanatory comment above the fixed viewport/scissor code read "Fixed (never dynamic, per D-22/acceptance-criteria's VK_DYNAMIC_STATE==0) viewport/scissor..." -- the comment's own literal reference to the acceptance criterion contained the substring `VK_DYNAMIC_STATE`, inflating the grep count from the expected 0 to 1 even though no actual `VK_DYNAMIC_STATE_*` enum value or `vkCmdSetDynamicState`-family call exists anywhere in the file.
- **Fix:** Reworded the comment to "Fixed (never a runtime-settable pipeline attribute, per D-22) viewport/scissor..." (applied to both the `.hpp` member-state doc comment and the `.cpp` code comment), removing the incidental substring match while preserving the explanation.
- **Files modified:** `SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp`, `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp`
- **Verification:** `grep -c "VK_DYNAMIC_STATE" processing_processor_render.cpp` -> 0; full rebuild succeeded.
- **Committed in:** `d51a572` (Task 2 commit) -- fixed before the commit, so no separate follow-up commit was needed.

### Out-of-Scope Observation (not a deviation)

None beyond the three fixes above.

---

**Total deviations:** 3 auto-fixed (1 blocking-issue fix, 2 bug fixes -- all Rule 1/3, all fixed before their respective task's commit, no scope creep). All three were necessary to produce a valid, buildable `VkGraphicsPipelineCreateInfo`/`VkImageViewCreateInfo` and an accurate acceptance-criteria grep proof. No functional scope was added beyond what the plan already specified.

## Issues Encountered

None beyond the deviations above.

## User Setup Required

None - no external service configuration required.

## Verification

- **Full CMake link-build** of `SGProcessors` succeeded after each task in isolation (`cmake --build "SuperGenius/build/Windows/Release" --target SGProcessors --config Release`) -- this working tree's real MSBuild link-build, consistent with plans 03-01/02/03.
- **Full CMake link-build** of `ProcessingBase` and `processing_dispatch_test` both succeeded against the combined (both-tasks) final state.
- `processing_dispatch_test.exe` (8 tests, no filter): **8/8 PASSED**, confirming no regression to the render-pass dispatch/validation/compile-and-validate end-to-end tests. (This plan's `BuildRenderPass`/`BuildFramebuffer`/`BuildPipeline` are not yet called from `StartProcessing()` -- that wiring is plan 03-05's task -- so these tests exercise the unchanged dispatch path, not the new Vulkan object construction directly.)
- `processing_datatypes_test.exe` (31 tests, the MNN/non-render dispatch regression suite): **31/31 PASSED** -- confirms this plan's changes (scoped entirely to `RenderProcessor`, not yet wired into `StartProcessing()`) introduced no regression to the non-render dispatch path.
- Task 1 acceptance criteria (verified against commit `dff39f6` in isolation): `grep -c "VK_ATTACHMENT_LOAD_OP_DONT_CARE"` -> 2 (color+depth `stencilLoadOp` only); `grep -c "loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR"` -> 2; `grep -c "VK_SAMPLE_COUNT_1_BIT"` -> 4 (>= 2 required); `grep -c "CheckFormatSupport"` -> 4 (>= 2 required).
- Task 2 acceptance criteria (verified against the combined final state, commit `d51a572`): `grep -c "VK_DYNAMIC_STATE"` -> 0; `grep -n "pName = "` shows the sole assignment is `stageInfo.pName = s.entry_point.c_str();` (never a literal `"main"`); `grep -c "VK_SAMPLE_COUNT_1_BIT"` -> 5 (>= 3 total across both tasks required).

### Requirements Marking Deferred

This plan's frontmatter lists `requirements: [RENDER-01, RENDER-03, RENDER-04, DETV-02]`. Per the phase's established precedent (03-01/02/03-SUMMARY.md), these are multi-plan requirements whose literal wording describes runtime behavior this plan does not yet exercise end-to-end: `BuildRenderPass()`/`BuildFramebuffer()`/`BuildPipeline()` are built and build-verified, but none are yet called from `StartProcessing()` -- that wiring, plus the actual draw/readback that would let RENDER-01/03/04 be exercised as real runtime behavior and DETV-01's repeat-run hash test prove DETV-02's guards, is plan 03-05's task. Deliberately skipped; plan 03-05 should perform the `requirements mark-complete` call for these once `StartProcessing()` actually wires this plan's methods together and the determinism test runs.

## Next Phase Readiness

`RenderProcessor` now has a complete, build-verified render pass/framebuffer/pipeline construction layer: `BuildRenderPass()` and `BuildFramebuffer()` produce a valid offscreen color+depth target with explicit clears, `VK_SAMPLE_COUNT_1_BIT`, and format-support checks; `BuildPipeline()` produces a complete, non-dynamic `VkPipeline` from real per-stage entry points, schema-declared (or defaulted) fixed-function state, and a pipeline layout matching D-29/D-30's push-constant/descriptor-set threshold. No blockers for plan 03-05 (`StartProcessing()` wiring: threading plan 03-03's `ParseRenderPassConfig()`/`ResolveUniforms()` output and this plan's `BuildRenderPass()`/`BuildFramebuffer()`/`BuildPipeline()` together with command-buffer recording, buffer upload, draw, readback, and the DETV-01 repeat-run determinism proof).

## Self-Check: PASSED

- `.planning/workstreams/sgproc-render/phases/03-renderprocessor-implementation-determinism/03-04-SUMMARY.md` — FOUND
- Commit `dff39f6` (SGProcessingManager, Task 1) — FOUND
- Commit `d51a572` (SGProcessingManager, Task 2) — FOUND
- Commit `8126c094` (SuperGenius, pointer bump) — FOUND
- Commit `ce82866` (GeniusNetwork, pointer bump) — FOUND

---
*Phase: 03-renderprocessor-implementation-determinism*
*Completed: 2026-07-31*
