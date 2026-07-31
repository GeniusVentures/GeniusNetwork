---
phase: 03-renderprocessor-implementation-determinism
plan: 05
subsystem: SGProcessingManager (RenderProcessor)
tags: [vulkan, command-buffer, readback, sha256, determinism, dispatch]

requires:
  - phase: 03-03
    provides: "ParsedStage/ResolvedUniforms/RenderTarget/PipelineState/VertexLayoutEntry parsers, CreateBufferDedicated()/CreateImageDedicated()/PushTeardown()/RunTeardown()/MakeError() this plan's UploadBuffers()/RecordAndSubmit()/Readback() and rewired StartProcessing() consume"
  - phase: 03-04
    provides: "BuildRenderPass()/BuildFramebuffer()/BuildPipeline() (m_renderPass/m_framebuffer/m_pipeline/m_pipelineLayout/m_descriptorSet, m_renderWidth/m_renderHeight) this plan's RecordAndSubmit() records commands against"
provides:
  - "RenderProcessor::UploadBuffers() -- validates vertex/index buffer byte lengths against the pipeline's stride/index-type BEFORE any draw is recorded (closes T-03-03-02), uploads vertex/index/uniform bytes into dedicated HOST_VISIBLE|HOST_COHERENT buffers"
  - "RenderProcessor::RecordAndSubmit() -- records and submits one command buffer (bind pipeline/buffers, push-constants or descriptor-set, draw(Indexed), readback copy recorded inline before vkEndCommandBuffer) plus a synchronous vkDeviceWaitIdle (D-23)"
  - "RenderProcessor::Readback()/ColorFormatByteSize() -- maps the staging buffer populated by RecordAndSubmit() into a plain byte vector"
  - "RenderProcessor::StartProcessing() -- fully rewired, real implementation: parses, resolves, builds, uploads, draws, reads back, hashes (real SHA-256, not a stub), and tears down on every exit path"
  - "RENDER-07's data_transform stance: no-op passthrough when absent/empty, structured DATA_TRANSFORM_UNSUPPORTED error when present -- no executor built (none exists anywhere in this codebase)"
  - "New regression test confirming the fully-wired StartProcessing() doesn't regress the existing fetch-level INPUT_UNAVAIL failure path"
affects: [03-06-determinism-repeat-run-proof]

tech-stack:
  added: []
  patterns:
    - "Readback copy recorded INLINE inside RecordAndSubmit()'s own command buffer, immediately after vkCmdEndRenderPass and before vkEndCommandBuffer -- no second command buffer/submission, no extra vkCmdPipelineBarrier (color attachment finalLayout already VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL from plan 03-04)"
    - "Push-constant bytes/decision stored on RenderProcessor as m_usePushConstant/m_pushConstantBytes (set by UploadBuffers(), consumed by RecordAndSubmit()) since RecordAndSubmit()'s declared signature carries no uniform data of its own"
    - "Every StartProcessing() exit point (12 return statements: 1 context-init failure + 8 intermediate step failures + 1 data-transform rejection + 1 post-record/readback failure branch pair + 1 success) calls RunTeardown() immediately before returning -- uniform, defensive D-22/D-24 compliance even on paths where nothing was yet created"
    - "m_queueFamilyIndex captured by InitializeContext() (vkb::Device::get_queue_index) and reused (never re-queried) by RecordAndSubmit()'s VkCommandPool creation"

key-files:
  created: []
  modified:
    - SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp
    - SuperGenius/test/src/processing_dispatch/processing_dispatch_test.cpp

key-decisions:
  - "Added m_queueFamilyIndex member, captured in InitializeContext() via vkb::Device::get_queue_index(vkb::QueueType::graphics) -- RecordAndSubmit()'s VkCommandPool creation needs a queue family index and InitializeContext() previously only stored the resolved VkQueue itself, not its family index"
  - "Added m_usePushConstant/m_pushConstantBytes members, set by UploadBuffers() from the ResolvedUniforms it receives -- RecordAndSubmit()'s plan-declared signature (target, errorOut) carries no uniform data, so the push-constant bytes/decision must persist on the instance for RecordAndSubmit()'s vkCmdPushConstants call"
  - "UploadBuffers() rejects stride == 0 (in addition to the plan's specified vertexBytes.size() % stride check) -- an empty vertex_layout would otherwise divide by zero computing m_vertexCount, a crash vector the plan's behavior bullets didn't explicitly call out but which must be closed to satisfy 'never crash on malformed/adversarial input'"
  - "RecordAndSubmit() creates the staging buffer and records vkCmdCopyImageToBuffer INSIDE its own command buffer (per the plan's explicit instruction), so Readback() itself only maps/copies the already-populated staging buffer after RecordAndSubmit()'s vkDeviceWaitIdle returns -- the two methods share m_stagingBuffer/m_stagingMemory as instance state rather than passing it explicitly"
  - "Marked RENDER-02/RENDER-05 complete alongside this plan's own frontmatter requirements (RENDER-01/03/06/07/08/09, DETV-02) -- both are now genuinely runtime-exercised by this plan's UploadBuffers()/RecordAndSubmit() wiring, and 03-03-SUMMARY.md explicitly named plan 03-05 as the intended point to mark them (03-03/03-04's own frontmatter never listed them, leaving no other plan to do so)"

requirements-completed: [RENDER-01, RENDER-02, RENDER-03, RENDER-05, RENDER-06, RENDER-07, RENDER-08, RENDER-09, DETV-02]

metrics:
  duration: "~55 min"
  completed: "2026-07-31"
status: complete
---

# Phase 3 Plan 5: RenderProcessor StartProcessing() Wiring + Buffer Upload/Draw/Readback Summary

**`RenderProcessor::StartProcessing()` is now a complete, real Vulkan render-pass execution: uploads validated vertex/index/uniform buffers, records and submits one command buffer that draws and reads back the color attachment inline, computes a real SHA-256 hash of the readback bytes, applies RENDER-07's no-op/error data_transform stance, and tears down every per-job Vulkan object on every exit path -- replacing the phase's last remaining zero-hash stub.**

## Performance

- **Duration:** ~55 min
- **Completed:** 2026-07-31
- **Tasks:** 2
- **Files modified:** 3 (2 in SGProcessingManager submodule, 1 in SuperGenius) + 2 submodule-pointer bumps (SuperGenius, GeniusNetwork)

## Accomplishments

- `UploadBuffers()` validates `vertexBytes.size() % stride == 0` and (if an index buffer is declared) `indexBytes.size() % index-type-byte-size == 0` **before** any buffer is created or any draw call is ever recorded -- closing T-03-03-02, the out-of-bounds-GPU-read gap plan 03-03's threat register flagged as not-yet-implemented. Uploads vertex/index buffers and (descriptor-set path only) a uniform buffer into dedicated `HOST_VISIBLE|HOST_COHERENT` memory via direct `vkMapMemory`/`memcpy`/`vkUnmapMemory` -- zero `vkFlushMappedMemoryRanges`/`vkInvalidateMappedMemoryRanges` calls anywhere (D-20/D-21).
- `RecordAndSubmit()` records and submits exactly one command buffer: begin render pass (clears built from `target.get_clear_color()`/`get_clear_depth()`) -> bind pipeline/vertex/index buffers -> push constants (`vkCmdPushConstants`) or bind descriptor set -> `vkCmdDraw(Indexed)` -> end render pass -> the readback `vkCmdCopyImageToBuffer` recorded **inline**, immediately after `vkCmdEndRenderPass` and before `vkEndCommandBuffer` (no second command buffer/submission, no extra `vkCmdPipelineBarrier` -- the color attachment's `finalLayout` is already `VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL` from plan 03-04) -> `vkQueueSubmit` -> a synchronous `vkDeviceWaitIdle` (D-23, RenderProcessor's own independent `VkDevice`).
- `Readback()`/`ColorFormatByteSize()` map the staging buffer `RecordAndSubmit()` already populated and copy its bytes into a plain `std::vector<uint8_t>` -- no invalidate call (`HOST_COHERENT`, D-20).
- `StartProcessing()` is fully rewritten: `ParseCompiledStages()` -> `ParseRenderPassConfig()` -> `ResolveUniforms()` -> `BuildRenderPass()` -> `BuildFramebuffer()` -> `BuildPipeline()` -> `UploadBuffers()` -> the RENDER-07 data-transform gate -> `RecordAndSubmit()` -> `Readback()` -> `sgprocmanagersha::sha256(readback bytes)` -> a populated `ProcessingResult` (real hash, single-entry `output_buffers`, `error = std::nullopt`). Every one of the function's 12 return statements (context-init failure, 8 intermediate step failures, the data-transform rejection, the record/readback failure pair, and the success path) calls `RunTeardown()` immediately before returning -- no per-job Vulkan object is ever leaked on any path (D-22/D-24).
- RENDER-07: absent/empty `data_transforms` is a no-op (readback bytes flow through unmodified); any non-empty `data_transforms` fails cleanly with a structured `ProcessingErrorStage::DATA_TRANSFORM_UNSUPPORTED` error naming the entry count -- no executor built, since none exists anywhere in this codebase (RESEARCH.md Pitfall 9).
- New `TEST_F(ProcessingDispatchTest, RenderPassStillFailsCleanlyOnMissingRenderInputAfterFullWiring)` confirms the now-fully-wired `StartProcessing()` introduces no regression to the pre-existing fetch-level `INPUT_UNAVAIL` failure path (the fixture's bogus `renderInput` data URI still fails in `GetCidForProc()`, before `StartProcessing()` is ever reached). All 8 pre-existing `TEST_F` cases in `processing_dispatch_test.cpp` pass unmodified in outcome (9/9 total, not 8/8 -- see Deviations).

## Task Commits

Each task was committed atomically:

1. **Task 1: Buffer upload + command recording/submission + readback** - `f0c0ded` (feat, SGProcessingManager submodule)
2. **Task 2: StartProcessing() wiring + RENDER-07 stance** - `1a6b4ba` (feat, SGProcessingManager submodule)
3. **Task 2: New regression test** - `77077e3f` (test, SuperGenius repo)

**Submodule pointer bumps:**
- SuperGenius: `7e50d81e` (chore) -- points to SGProcessingManager `1a6b4ba`, encompassing both tasks
- GeniusNetwork: `6a3a30c` (chore) -- points to SuperGenius `7e50d81e`

## Files Created/Modified

- `SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp` - `UploadBuffers()`/`RecordAndSubmit()`/`Readback()`/`ColorFormatByteSize()` declarations; new member state (`m_vertexBuffer`/`m_indexBuffer`/`m_uniformBuffer`/`m_stagingBuffer` + matching `VkDeviceMemory`, `m_commandPool`/`m_commandBuffer`, `m_hasIndexBuffer`/`m_indexType`/`m_vertexCount`/`m_indexCount`, `m_queueFamilyIndex`, `m_usePushConstant`/`m_pushConstantBytes`).
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp` - implementations of all of the above; `InitializeContext()` extended to capture `m_queueFamilyIndex`; `StartProcessing()` fully rewritten (no longer a stub).
- `SuperGenius/test/src/processing_dispatch/processing_dispatch_test.cpp` - one new `TEST_F` case.

## Decisions Made

See frontmatter `key-decisions`. In summary: `m_queueFamilyIndex` and `m_usePushConstant`/`m_pushConstantBytes` were added as instance state to close gaps between the plan's declared method signatures (`RecordAndSubmit(target, errorOut)` carries no queue-family or uniform data of its own) and what those methods actually need at call time -- the same class of gap 03-04 hit with `m_renderWidth`/`m_renderHeight`. `UploadBuffers()` additionally guards `stride == 0` to avoid a division-by-zero crash the plan's behavior bullets didn't explicitly enumerate. RENDER-02/RENDER-05 were marked complete in this plan per 03-03-SUMMARY.md's explicit forward-reference, even though 03-05-PLAN.md's own frontmatter `requirements` field didn't list them.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] `RecordAndSubmit()` needed a queue family index InitializeContext() never stored**
- **Found during:** Task 1 implementation, before writing `RecordAndSubmit()`'s `VkCommandPool` creation.
- **Issue:** `vkCreateCommandPool` requires a `queueFamilyIndex`, but `InitializeContext()` only ever stored the resolved `VkQueue` handle (via `vkb::Device::get_queue(QueueType::graphics)`), never the queue family index itself. The plan's action text says to reuse "whatever queue-family index `InitializeContext()` already resolved" but no such index was actually captured anywhere in the existing code.
- **Fix:** Added `m_queueFamilyIndex`, captured in `InitializeContext()` via `vkb::Device::get_queue_index(vkb::QueueType::graphics)` immediately alongside the existing `get_queue()` call, with the same error-handling shape as the surrounding code.
- **Files modified:** `SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp`, `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp`
- **Verification:** Full CMake link-build of `SGProcessors` succeeded; `RecordAndSubmit()` creates a valid command pool against the same graphics queue family `m_queue` belongs to.
- **Committed in:** `f0c0ded` (Task 1 commit).

**2. [Rule 3 - Blocking issue] `RecordAndSubmit()`'s declared signature carries no uniform data for `vkCmdPushConstants`**
- **Found during:** Task 1 implementation, while recording the push-constant/descriptor-set bind.
- **Issue:** The plan declares `RecordAndSubmit(const sgns::RenderTarget &target, ProcessingResult &errorOut)` -- no `ResolvedUniforms` parameter -- yet the action text requires `vkCmdPushConstants` to copy `packedBytes.data()` at record time. Without persisting this data, `RecordAndSubmit()` would have no source for the push-constant bytes.
- **Fix:** Added `m_usePushConstant`/`m_pushConstantBytes` member state, set by `UploadBuffers()` (which does receive the `ResolvedUniforms` parameter) and consumed by `RecordAndSubmit()`.
- **Files modified:** `SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp`, `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp`
- **Verification:** Full CMake link-build succeeded; the descriptor-set path needed no equivalent addition since `m_descriptorSet` (already a member, built by `BuildPipeline()`) is bound directly.
- **Committed in:** `f0c0ded` (Task 1 commit).

**3. [Rule 2 - Missing critical validation] `UploadBuffers()` guards `stride == 0` to prevent a division-by-zero crash**
- **Found during:** Task 1 implementation, while writing the vertex-buffer modulo check.
- **Issue:** The plan's behavior bullets specify validating `vertexBytes.size() % stride == 0`, but don't address the case where `stride` itself is `0` (an empty `vertex_layout`, i.e. no vertex attributes declared) -- a real modulo-by-zero, undefined behavior in C++, not merely a logic bug.
- **Fix:** Added `stride == 0 ||` to the existing check, so a zero stride is treated the same as a length mismatch: a structured `RESOURCE_RESOLUTION` error, never a crash.
- **Files modified:** `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp`
- **Verification:** Full CMake link-build succeeded; the check is defensive/structural (not directly exercised by existing fixtures, which don't reach this code path since the fetch-level `INPUT_UNAVAIL` failure occurs first).
- **Committed in:** `f0c0ded` (Task 1 commit).

**4. [Rule 1 - Bug] Self-defeating comment inflated `grep -c "vkCmdPipelineBarrier"` from the expected 0 to 1**
- **Found during:** Task 1's own acceptance-criteria self-check, before committing.
- **Issue:** An explanatory comment above the readback copy read "...so no extra `vkCmdPipelineBarrier` layout transition is needed here" -- the comment's own literal reference to the Vulkan API name contained the substring being grepped for, inflating the count from the expected 0 to 1, even though no actual `vkCmdPipelineBarrier` call exists anywhere in the file. Same class of issue as 03-03/03-04's `vkAllocateMemory`/`VK_DYNAMIC_STATE` precedents.
- **Fix:** Reworded to "...so no extra image-layout-transition barrier is needed here" in both the `.cpp` code comment and the matching `.hpp` doc comment, removing the incidental substring match while preserving the explanation.
- **Files modified:** `SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp`, `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp`
- **Verification:** `grep -c "vkCmdPipelineBarrier"` on both files -> 0; full rebuild succeeded.
- **Committed in:** `f0c0ded` (Task 1 commit) -- fixed before the commit, so no separate follow-up commit was needed.

### Out-of-Scope / Acceptance-Criteria Discrepancy Notes (not deviations)

- **Existing test count was already 8, not 7, before this plan's new test.** The plan's own acceptance criteria describe "7 existing, unmodified + 1 new = 8 total" and the phase's `build_convention_note` independently states "8/8 dispatch tests" passing as of plans 03-01 through 03-04 -- i.e. the file already had 8 `TEST_F` cases (not 7) before this plan touched it. Adding the plan's one new test brings the real total to **9**, not 8. All 8 pre-existing cases remain unmodified in outcome, and the new 9th passes -- the plan's literal "8 total" acceptance-criteria count appears to be a stale assumption carried over from earlier in the phase's planning sequence, not something this execution could satisfy without either deleting a pre-existing test (not warranted) or miscounting.
- **`grep -c "std::vector<uint8_t>( 32, 0 )" == 0` cannot be literally satisfied file-wide.** `MakeError()` (built in plan 03-01/03-03, unmodified by this plan) itself contains this exact literal as its established, D-25/D-26-compliant hash-on-error convention. This plan's actual objective -- removing the old stub's hard-coded zero-hash *return* from `StartProcessing()`'s own body -- is fully satisfied: `StartProcessing()` no longer directly constructs a bare zero-hash `ProcessingResult` anywhere; every failure path routes through the pre-existing, structured `MakeError()` helper, and the success path computes a real 32-byte SHA-256 hash. Rewriting `MakeError()` itself to avoid this literal would be an out-of-scope change to a different plan's already-shipped, already-reused convention.

---

**Total deviations:** 4 auto-fixed (2 blocking-issue fixes, 1 missing-validation addition, 1 self-defeating-comment fix -- all Rule 1/2/3, all fixed before their respective task's commit, no scope creep). Two acceptance-criteria discrepancies (stale test-count assumption; a grep target that collides with an established, out-of-scope helper) are documented above as pre-existing plan-authoring artifacts, not code defects.

## Issues Encountered

None beyond the deviations above.

## User Setup Required

None - no external service configuration required.

## Verification

- **Full CMake link-build** of `SGProcessors` succeeded after each task's isolated state (`cmake --build "SuperGenius/build/Windows/Release" --target SGProcessors --config Release`) -- this working tree's real MSBuild link-build, consistent with plans 03-01 through 03-04.
- **Full CMake link-build** of `ProcessingBase` and `processing_dispatch_test` both succeeded against the combined (both-tasks) final state.
- `processing_dispatch_test.exe`: **9/9 PASSED** (8 pre-existing cases unmodified in outcome + 1 new case).
- `processing_datatypes_test.exe` (31 tests, the MNN/non-render regression suite): **31/31 PASSED** -- confirms this plan's `StartProcessing()` rewrite introduces no regression to the non-render dispatch path.
- `grep -c "vkFlushMappedMemoryRanges\|vkInvalidateMappedMemoryRanges"` -> 0 (D-20, no manual flush/invalidate anywhere).
- `grep -c "vkCmdPipelineBarrier"` -> 0 (Pitfall 4 -- no extra layout-transition barrier between `vkCmdEndRenderPass` and the readback copy).
- `grep -c "vertexBytes.size() % stride\|indexBytes.size() %"` -> 2 (both buffer-length validation checks present).
- `RunTeardown()` called immediately before every one of `StartProcessing()`'s 12 return statements (verified by direct code inspection during the rewrite).

### Requirements Marked Complete

`RENDER-01, RENDER-02, RENDER-03, RENDER-05, RENDER-06, RENDER-07, RENDER-08, RENDER-09, DETV-02` -- RENDER-02/RENDER-05 were added beyond this plan's own frontmatter list per 03-03-SUMMARY.md's explicit note that plan 03-05 was the intended point to mark them, since neither 03-03's nor 03-04's nor 03-05's frontmatter otherwise lists them and both are now genuinely runtime-exercised (vertex/index buffer upload via direct Vulkan APIs; push-constant/descriptor-set uniform binding with the 128-byte threshold).

## Next Phase Readiness

`RenderProcessor::StartProcessing()` is now a complete, working, build-verified implementation: it parses the wire formats, resolves uniforms, builds the render pass/framebuffer/pipeline, uploads validated buffers, records and submits a single command buffer that draws and reads back the color attachment, computes a real SHA-256 hash, applies RENDER-07's data-transform stance, and tears down every per-job Vulkan object on every exit path. The only remaining phase work is DETV-01's same-node repeat-run (N>=10) bit-exact determinism proof (plan 03-06) -- no blockers identified for it.

## Self-Check: PASSED

- `.planning/workstreams/sgproc-render/phases/03-renderprocessor-implementation-determinism/03-05-SUMMARY.md` — FOUND
- Commit `f0c0ded` (SGProcessingManager, Task 1) — FOUND
- Commit `1a6b4ba` (SGProcessingManager, Task 2) — FOUND
- Commit `77077e3f` (SuperGenius, new regression test) — FOUND
- Commit `7e50d81e` (SuperGenius, SGProcessingManager pointer bump) — FOUND
- Commit `6a3a30c` (GeniusNetwork, SuperGenius pointer bump) — FOUND

---
*Phase: 03-renderprocessor-implementation-determinism*
*Completed: 2026-07-31*
