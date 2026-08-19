---
phase: 17-render-path-cross-hardware-tolerance
plan: 02
subsystem: render-processing
tags: [vulkan, glsl, quicktype, schema, alpha-blending, capture-harness, sgprocessingmanager]

requires:
  - phase: 17-render-path-cross-hardware-tolerance
    provides: "Plan 01's lighting fixture and capture_harness --model-input-source convention"
  - phase: 02-schema-extension-shader-spir-v-validation-pipeline
    provides: "pipeline_state's curated-minimal fixed-function schema definition (D-13/D-14), quicktype regeneration workflow"
  - phase: 03-renderprocessor-implementation-determinism
    provides: "BuildPipeline()'s existing hardcoded colorBlendAttachment, ToVkCullMode/ToVkFrontFace/ToVkTopology mapping-function convention, SerializeRenderPassConfig/ParseRenderPassConfig wire format"
provides:
  - "pipeline_state schema gains blend_enable/blend_src_factor/blend_dst_factor (D-05 blending scope), regenerated into a real sgns::BlendFactor enum and extended PipelineState accessors"
  - "SerializeRenderPassConfig()/ParseRenderPassConfig() paired wire-format edit for the three new blend fields, closing RESEARCH.md Pitfall 2 in a single task/commit"
  - "BuildPipeline() now builds a real, schema-driven VkPipelineColorBlendAttachmentState instead of a hardcoded blendEnable = VK_FALSE, via a new ToVkBlendFactor() static mapping function"
  - "render-blending fixture (JSON job + 2 GLSL shaders + raw vertex data) exercising a real fractional-alpha (0.5) blend against a non-trivial clear color, empirically proven end-to-end via local capture_harness runs"
affects: [17-03-texturing-fixture, 17-05-cross-machine-capture, 17-06-tolerance-derivation]

tech-stack:
  added: []
  patterns: ["Schema-driven VkPipelineColorBlendAttachmentState wiring, mirroring the existing ToVkCullMode/ToVkFrontFace/ToVkTopology static-mapping-function convention", "Fractional-alpha fragment output as the load-bearing mechanism for forcing a real floating-point blend mix (not a no-op)"]

key-files:
  created:
    - SuperGenius/SGProcessingManager/generated/BlendFactor.hpp
    - SuperGenius/test/src/processing_dispatch/blending_vertex_shader.glsl
    - SuperGenius/test/src/processing_dispatch/blending_fragment_shader.glsl
    - SuperGenius/test/src/processing_dispatch/blending-vertex-data.raw
    - SuperGenius/test/src/processing_dispatch/blending-fixture-definition.json
  modified:
    - SuperGenius/SGProcessingManager/gnus-processing-schema.json
    - SuperGenius/SGProcessingManager/generated/PipelineState.hpp
    - SuperGenius/SGProcessingManager/generated/Generators.hpp
    - SuperGenius/SGProcessingManager/generated/Pass.hpp
    - SuperGenius/SGProcessingManager/generated/SGNSProcMain.hpp
    - SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp
    - SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp

key-decisions:
  - "Fixed pre-existing schema/generated-header drift found while regenerating headers: gnus-processing-schema.json's data_type enum was missing the 'llm' string even though DataType::LLM is used in production code (ProcessingManager.cpp:401) and tests -- added it back to the schema before regenerating, since a literal quicktype regen would have silently dropped the enum value and broken the build"

requirements-completed: [RENDTOL-01, RENDTOL-02]

coverage:
  - id: D1
    description: "pipeline_state schema extended with blend_enable/blend_src_factor/blend_dst_factor, regenerated (no hand-edits) into a real sgns::BlendFactor enum and PipelineState get_blend_*/set_blend_* accessors"
    requirement: RENDTOL-01
    verification:
      - kind: other
        ref: "grep-verified: generated/BlendFactor.hpp declares enum class BlendFactor : int { ONE, ONE_MINUS_SRC_ALPHA, SRC_ALPHA, ZERO }; generated/PipelineState.hpp declares get_blend_enable/get_blend_src_factor/get_blend_dst_factor"
        status: pass
    human_judgment: false
  - id: D2
    description: "SerializeRenderPassConfig() and ParseRenderPassConfig() both append/read the three new blend fields in the same order, in the same task/commit, closing RESEARCH.md Pitfall 2's wire-format-pairing risk"
    requirement: RENDTOL-01
    verification:
      - kind: other
        ref: "grep -c blend_ on both ProcessingManager.cpp and processing_processor_render.cpp both return 9 (>= 3 required); ProcessingBase target builds cleanly with these edits"
        status: pass
    human_judgment: false
  - id: D3
    description: "BuildPipeline() replaces the hardcoded colorBlendAttachment.blendEnable = VK_FALSE with real schema-driven blend wiring via a new ToVkBlendFactor() mapping function"
    requirement: RENDTOL-01
    verification:
      - kind: other
        ref: "grep -c 'blendEnable = VK_FALSE;' over the BuildPipeline()-to-colorBlending region returns 0 (was previously an unconditional literal); ProcessingBase target builds cleanly"
        status: pass
    human_judgment: false
  - id: D4
    description: "render-blending fixture (fractional-alpha fragment output, blend_enable:true, non-trivial clear color) builds and renders end-to-end on real Vulkan hardware via capture_harness"
    requirement: RENDTOL-01
    verification:
      - kind: e2e
        ref: "capture_harness.exe --fixture-root SuperGenius/test/src --fixture processing_dispatch/blending-fixture-definition.json --label smoke-blending --repeat 2 --model-input-source input:blendingVertexInput -- exit 0, 'wrote ... 2/2 stable runs' on NVIDIA RTX 4070 Ti SUPER; re-run at label smoke-blending-verify also passed"
        status: pass
    human_judgment: false
  - id: D5
    description: "The render path's byte-quantization tolerance mechanism (ResolveByteQuantMode/QuantizeByteBuffer, Phase 14) remains unmodified and still applies to this fixture -- no parameters/byteQuantMode declared, preserving the N=0 identity fallback for Wave 4's raw-divergence capture"
    requirement: RENDTOL-02
    verification:
      - kind: other
        ref: "grep -c parameters/byteQuantMode over blending-fixture-definition.json returns 0 matches"
        status: pass
    human_judgment: false
duration: 20min
completed: 2026-08-19
status: complete
---

# Phase 17 Plan 2: Blending Render Fixture Summary

**Real schema-driven alpha blending (blend_enable/blend_src_factor/blend_dst_factor) replaces BuildPipeline()'s hardcoded VK_FALSE colorBlendAttachment, wired end-to-end through the schema, the hand-rolled wire format, and a new fractional-alpha blending fixture proven on real Vulkan hardware.**

## Performance

- **Duration:** 20 min
- **Started:** 2026-08-19T20:40:37Z (per prior plan's final commit timestamp)
- **Completed:** 2026-08-19T20:49:33Z (final capture verification/commit)
- **Tasks:** 2
- **Files modified:** 13 (8 in SuperGenius/SGProcessingManager nested submodule, 5 fixture/capture files in SuperGenius, plus submodule pointer bumps)

## Accomplishments
- Extended `pipeline_state`'s curated-minimal fixed-function subset (D-13) with `blend_enable`/`blend_src_factor`/`blend_dst_factor`, regenerated via quicktype (never hand-edited) into a real `sgns::BlendFactor` enum (`ONE`/`ONE_MINUS_SRC_ALPHA`/`SRC_ALPHA`/`ZERO`) and extended `PipelineState` accessors.
- Paired `SerializeRenderPassConfig()`'s new append block with `ParseRenderPassConfig()`'s exact inverse bounds-checked read, in the same task/commit, in the same field order, closing RESEARCH.md's Pitfall 2 (producer/consumer wire-format drift).
- Replaced `BuildPipeline()`'s hardcoded `colorBlendAttachment.blendEnable = VK_FALSE` with real schema-driven wiring: a new `ToVkBlendFactor()` static mapping function (mirroring `ToVkCullMode`/`ToVkFrontFace`/`ToVkTopology`'s existing convention) resolves `blend_src_factor`/`blend_dst_factor` into real `VkBlendFactor` values, with a defensive `VK_BLEND_FACTOR_ONE` fallback on any unmapped tag.
- Authored the `render-blending` fixture: a 3-vertex full-screen-triangle draw whose fragment shader outputs a fractional alpha (0.5), forcing a real `src*0.5 + dst*0.5` floating-point mix against a non-trivial clear color (`[0.2, 0.4, 0.6, 1.0]`) when `blend_enable:true` -- proven end-to-end via `capture_harness` (2/2 stable runs on an NVIDIA RTX 4070 Ti SUPER, both the smoke run and the plan's literal verification command).
- **Found and fixed a pre-existing bug while regenerating headers:** `gnus-processing-schema.json`'s `data_type` enum was missing `"llm"` even though `DataType::LLM` is used in production code (`ProcessingManager.cpp:401`) and tests (`mnn_llm_test.cpp`, `mnn_tensor_fp4_test.cpp`) -- the committed `generated/DataType.hpp` had drifted out of sync with the schema at some point prior to this plan. Fixed by adding `"llm"` back to the schema before regenerating, preventing a silent build break.

## Task Commits

Each task was committed atomically (submodule-first, then outer-repo pointer bump, per this project's convention):

1. **Task 1: Extend the pipeline_state schema with blend fields and pair the wire-format edit across both Serialize/Parse**
   - `7fb6572` (SGProcessingManager nested submodule, feat) — schema blend fields, regenerated headers (BlendFactor.hpp, PipelineState.hpp, Generators.hpp, Pass.hpp, SGNSProcMain.hpp), the pre-existing `llm` schema-drift fix, and the paired Serialize/Parse wire-format edit
   - `2c842d50` (SuperGenius submodule, chore) — bump SGProcessingManager submodule pointer to `7fb6572`
   - `ff65b42` (outer repo, chore) — bump SuperGenius submodule pointer to `2c842d50`
2. **Task 2: Wire real blend state into BuildPipeline(), then author and smoke-verify the blending fixture**
   - `b81b9e9` (SGProcessingManager nested submodule, feat) — `ToVkBlendFactor()` mapping function + real `BuildPipeline()` blend wiring
   - `49796665` (SuperGenius submodule, feat) — blending fixture shaders/vertex data/job JSON, plus bump SGProcessingManager submodule pointer to `b81b9e9`
   - `bd9ed90` (outer repo, chore) — bump SuperGenius submodule pointer to `49796665`, add the two smoke-verification `.cap` files

**Plan metadata:** committed via the standard `docs({phase}-{plan}): complete [plan-name] plan` final commit (see below)

_Note: no TDD tasks in this plan (schema/wire-format/pipeline extension plus fixture authoring + local verification only, mirroring 17-01's fixture-only precedent)._

## Files Created/Modified
- `SuperGenius/SGProcessingManager/gnus-processing-schema.json` - `pipeline_state.blend_enable`/`blend_src_factor`/`blend_dst_factor` added after `depth_test`; `data_type` enum's pre-existing missing `"llm"` value restored
- `SuperGenius/SGProcessingManager/generated/BlendFactor.hpp` - new quicktype-regenerated enum `sgns::BlendFactor { ONE, ONE_MINUS_SRC_ALPHA, SRC_ALPHA, ZERO }`
- `SuperGenius/SGProcessingManager/generated/PipelineState.hpp` - new `get_blend_enable`/`set_blend_enable`/`get_blend_src_factor`/`set_blend_src_factor`/`get_blend_dst_factor`/`set_blend_dst_factor` accessors
- `SuperGenius/SGProcessingManager/generated/Generators.hpp`, `generated/Pass.hpp`, `generated/SGNSProcMain.hpp` - regenerated to reference the new `BlendFactor.hpp` include and JSON (de)serialization for the new fields (plus incidental, schema-faithful `CheckConstraint` enforcement on `Pass`'s `estimated_gpu_memory_bytes`/`max_output_artifact_bytes`/`per_pass_deadline_ms` fields that the previously-committed generated file lacked)
- `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` - `SerializeRenderPassConfig()` appends the three new blend fields after `depth_test`, doc comment updated
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp` - `ParseRenderPassConfig()`'s exact inverse read block; new `ToVkBlendFactor()` static mapping function; `BuildPipeline()`'s real schema-driven blend wiring
- `SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp` - `ToVkBlendFactor()` declaration alongside `ToVkCullMode`/`ToVkFrontFace`/`ToVkTopology`
- `SuperGenius/test/src/processing_dispatch/blending_vertex_shader.glsl` - GLSL vertex stage, 2 scalar inputs (`inPosX`/`inPosY`)
- `SuperGenius/test/src/processing_dispatch/blending_fragment_shader.glsl` - GLSL fragment stage, constant `vec4(1.0, 0.0, 0.0, 0.5)` output (fractional alpha, load-bearing)
- `SuperGenius/test/src/processing_dispatch/blending-vertex-data.raw` - 24-byte raw float32 vertex buffer: 3 vertices, 2 components each, full-screen-triangle NDC coordinates
- `SuperGenius/test/src/processing_dispatch/blending-fixture-definition.json` - `render-blending` job: 64x64 render target, `triangle_list` topology, `blend_enable:true`/`blend_src_factor:"src_alpha"`/`blend_dst_factor:"one_minus_src_alpha"`, non-trivial clear color `[0.2, 0.4, 0.6, 1.0]`, no `parameters`/`byteQuantMode`

## Decisions Made
- **[Rule 1 - Bug] Fixed pre-existing schema/generated-header drift (`data_type` missing `"llm"`).** Confirmed via direct grep that `DataType::LLM` is referenced in production code (`ProcessingManager.cpp:401`, registering a factory for it) and two test files, but the schema's `data_type` enum never listed `"llm"` as a valid string. This is why the previously-committed `generated/DataType.hpp` had an `LLM` member the schema itself couldn't produce -- a real, pre-existing drift (likely from a hand-patch or an out-of-band regeneration at some point), not something introduced by this plan. Running the plan's mandated quicktype regeneration command literally would have silently dropped `DataType::LLM` from the regenerated header, breaking the build. Fixed by adding `"llm"` back to the schema's `data_type` enum before regenerating; confirmed via `git diff` that the second regeneration left `DataType.hpp` byte-identical to its pre-existing committed state (no other unintended changes), while still landing the new `BlendFactor` enum and blend accessors cleanly.
- Chose the full-screen-triangle NDC trick (3 vertices covering the entire 64x64 target, mirroring 17-01's lighting fixture) so blending is exercised across the whole target rather than a sub-region.
- Used a constant, non-parameterized fragment color (`vec4(1.0, 0.0, 0.0, 0.5)`) rather than a texture/uniform-driven color, since the fixture's purpose is to exercise the blend *pipeline state* (fixed-function `VkPipelineColorBlendAttachmentState` math), not shader-side color computation -- keeping the fixture minimal and isolating blending as the sole new floating-point-heavy mechanism under test, per D-04's separate-fixtures philosophy.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed pre-existing `data_type` schema/generated-header drift (missing `"llm"`)**
- **Found during:** Task 1 (regenerating C++ headers via quicktype after the schema edit)
- **Issue:** `gnus-processing-schema.json`'s `data_type` enum did not include `"llm"`, but the already-committed `generated/DataType.hpp` declared `DataType::LLM` (used by `ProcessingManager.cpp:401` and two test files). A literal quicktype regeneration silently dropped the `LLM` member on the first run, which would have broken the build for any code referencing `DataType::LLM`.
- **Fix:** Added `"llm"` to the schema's `data_type` enum list, then re-ran quicktype. Confirmed via `git diff` that `DataType.hpp` was then byte-identical to its pre-existing committed version (no regression), while `BlendFactor.hpp`/`PipelineState.hpp` still picked up the new blend fields correctly.
- **Files modified:** `SuperGenius/SGProcessingManager/gnus-processing-schema.json`
- **Verification:** `git diff -- generated/DataType.hpp` showed zero changes after the fix (previously showed `LLM` being dropped); `ProcessingBase` target built cleanly afterward.
- **Committed in:** `7fb6572` (Task 1 commit, part of the same schema-edit commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** No scope creep -- a one-line schema addition restoring a pre-existing, load-bearing enum value that the plan's mandated regeneration step would otherwise have silently broken. The blend-field work itself landed exactly as planned.

## Issues Encountered
None beyond the schema-drift fix documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The `render-blending` fixture is real, builds, and renders correctly on this machine's Vulkan device -- ready for Wave 4's cross-machine capture (17-05) alongside the lighting (17-01) and texturing (17-03/17-04) fixtures.
- `pipeline_state`'s blend fields and the paired wire-format edit are the first genuinely new render-path schema/C++ surface this phase adds (lighting needed none) -- the wire-format-pairing discipline (RESEARCH.md Pitfall 2) is proven working end-to-end for this phase's remaining texturing fixture (17-03/17-04), which needs a similar (larger) wire-format extension.
- This plan's smoke run only exercised one machine (Windows/`Mofu`); the Mac-mini leg of Phase 11's two-machine dataset remains out of scope for this plan, belonging to Wave 4 (17-05).
- The `data_type` schema/generated-header drift fix is a genuinely separate, pre-existing correctness fix -- worth flagging to any future phase touching `gnus-processing-schema.json`/`generated/` that hand-patches of generated files (if any occurred previously) must be back-ported into the schema itself, or a future regeneration will silently regress them again.

---
*Phase: 17-render-path-cross-hardware-tolerance*
*Completed: 2026-08-19*

## Self-Check: PASSED

All 5 created artifact files exist on disk (BlendFactor.hpp, blending_vertex_shader.glsl, blending_fragment_shader.glsl, blending-vertex-data.raw, blending-fixture-definition.json), the SUMMARY.md file exists, and all 6 task commit hashes (7fb6572, 2c842d50, ff65b42 for Task 1; b81b9e9, 49796665, bd9ed90 for Task 2) are present in their respective git histories.
