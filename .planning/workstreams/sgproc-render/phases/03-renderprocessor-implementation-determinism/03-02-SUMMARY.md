---
phase: 03-renderprocessor-implementation-determinism
plan: 02
subsystem: SGProcessingManager (ProcessingManager)
tags: [vulkan, wire-format, render-pass, input-resolution, validation]

requires:
  - phase: 03-01
    provides: "ProcessingResult::error field, ProcessingManager::Error::PROCESSING_FAILED dispatch gate, SerializeCompiledStages(stages, entryPoints) two-parameter wire format"
provides:
  - "GetCidForProc()'s render branch independently resolving vertex_buffer/index_buffer via the 'input:name' prefix (not the coincidental single model-index input)"
  - "SerializeRenderPassConfig() wire-format helper -- the only channel render_target/pipeline_state/vertex_layout/uniforms/data_transform_count have to reach RenderProcessor under StartProcessing()'s fixed signature"
  - "CheckProcessValidity()'s RENDER case extended with source-prefix validation (vertex_buffer/index_buffer must use input:, uniforms must use parameter:)"
affects: [03-03-renderprocessor-parsing-and-pipeline, 03-04, 03-05]

tech-stack:
  added: []
  patterns:
    - "Length-prefixed little-endian wire format (matches SerializeCompiledStages precedent) for packing quicktype-generated schema objects (RenderTarget/PipelineState/VertexLayoutEntry/RenderShaderUniform) into a raw byte buffer"
    - "Copy-boost::optional-into-named-local-before-reference-bind pattern (established in 03-01/02-04) applied consistently to vertex_buffer/index_buffer/render_shader accessors"
    - "Shared error-message lambda to avoid duplicating literal log-message text across two near-identical call sites (vertex_buffer vs index_buffer validation)"

key-files:
  created: []
  modified:
    - SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp

key-decisions:
  - "vertexBuffer->empty() is checked explicitly after ioc->run() to preserve the pre-existing INPUT_UNAVAIL failure semantics -- mainbuffers->second is now always non-empty for a render pass (SerializeRenderPassConfig always writes the render_target header), so the old generic mainbuffers->second->size() <= 0 check alone would no longer catch a failed vertex-buffer fetch"
  - "index_buffer with an absent source is treated as 'no index buffer' (skip, not an error) per the schema's own optionality, not rejected by CheckProcessValidity()"
  - "Uniform iteration order is std::map's natural key-sorted order (no explicit sort step) -- matches plan 03-03's ResolveUniforms iteration-order decision referenced in the plan text"

requirements-completed: []

coverage: []

duration: ~55min
completed: 2026-07-31
status: complete
---

# Phase 3 Plan 2: Independent Vertex/Index Buffer Resolution + Render-Pass Config Wire Format Summary

**Closed RESEARCH.md's Pitfall 1/Open Question 1: `GetCidForProc()` now fetches `vertex_buffer`/`index_buffer` as independently-named `"input:"` references and packs `render_target`/`pipeline_state`/`vertex_layout`/`uniforms`/`data_transform_count` into a new `SerializeRenderPassConfig()` wire format -- the only channel this Pass-level data has to reach `RenderProcessor` under its fixed `StartProcessing()` signature.**

## Performance

- **Duration:** ~55 min
- **Completed:** 2026-07-31
- **Tasks:** 2
- **Files modified:** 1 (SGProcessingManager submodule) + 2 submodule-pointer bumps (SuperGenius, GeniusNetwork)

## Accomplishments

- `GetCidForProc()`'s `isRender` branch resolves `vertex_buffer.source` (and, if present, `index_buffer.source`) independently via the existing `GetInputIndex()`/`m_inputMap` mechanism, instead of relying on the coincidental single model-index input the current test fixture happens to reuse.
- New `SerializeRenderPassConfig()` wire-format helper packs `render_target` + `pipeline_state` + `vertex_layout` + `uniforms` + vertex/index buffer bytes + `data_transform_count` into the buffer `GetCidForProc()` places at `mainbuffers->second` for a render pass -- this data has no other channel to reach `RenderProcessor`, since `StartProcessing()`'s signature never carries the `Pass` or `RenderShaderConfig` object itself.
- The old unconditional `GetSubCidForProc(ioc, imageUrl, mainbuffers->second)` fetch is now guarded by `if (!isRender)`, since `mainbuffers->second` is populated by `SerializeRenderPassConfig()` for render passes instead.
- `CheckProcessValidity()`'s `PassType::RENDER` case now rejects (at `Create()` time, before any pass is ever dispatched) a `vertex_buffer`/`index_buffer` source that isn't `"input:"`-prefixed, and a uniform `source` that isn't `"parameter:"`-prefixed -- closing threat register entries T-03-02-01/T-03-02-02.

## Task Commits

Each task was committed atomically (SGProcessingManager submodule):

1. **Task 1: Resolve vertex_buffer/index_buffer independently + serialize render_target/pipeline_state/vertex_layout in GetCidForProc()** - `0a5fac9` (feat)
2. **Task 2: CheckProcessValidity() source-prefix validation (vertex_buffer/index_buffer/uniforms)** - `a720323` (feat)

**Submodule pointer bumps:**
- SuperGenius: `c97dee2b` (chore) -- points to SGProcessingManager `a720323`, encompassing both tasks
- GeniusNetwork: `4979bc8` (chore) -- points to SuperGenius `c97dee2b`

_Note: both pointer-bump commits were made once, after both SGProcessingManager task commits existed, rather than once per task (see Deviations)._

## Files Created/Modified

- `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` - `SerializeRenderPassConfig()` helper (anonymous namespace, alongside `SerializeCompiledStages`); `GetCidForProc()`'s `isRender` branch extended with independent vertex/index buffer resolution + the new serialize call; `CheckProcessValidity()`'s `RENDER` case extended with three source-prefix checks.

## Final Wire Format (for plan 03-03's `RenderProcessor` parser to reference verbatim)

This is the byte-for-byte format `GetCidForProc()` writes into `mainbuffers->second` for a render pass. All integers little-endian, native width. `clear_color`/`clear_depth` are narrowed from the schema's `double` to `float` on write.

```
uint32_t width
uint32_t height
uint32_t color_format_tag        (static_cast<uint32_t>(sgns::ColorFormat))
uint32_t depth_format_tag        (static_cast<uint32_t>(sgns::DepthFormat))
float    clear_color[4]          (narrowed from double; 0.0f if schema array shorter than 4)
float    clear_depth             (narrowed from double)

uint8_t  has_pipeline_state
if has_pipeline_state:
  uint8_t  has_topology     + [uint32_t topology_tag]    (static_cast<uint32_t>(sgns::Topology))
  uint8_t  has_cull_mode    + [uint32_t cull_mode_tag]    (static_cast<uint32_t>(sgns::CullMode))
  uint8_t  has_front_face   + [uint32_t front_face_tag]   (static_cast<uint32_t>(sgns::FrontFace))
  uint8_t  has_depth_test   + [uint32_t depth_test_tag]   (static_cast<uint32_t>(sgns::DepthTest))

uint32_t vertex_layout_count
per entry:
  uint32_t name_len + name bytes (raw UTF-8, no null terminator)
  uint32_t format_tag            (static_cast<uint32_t>(sgns::VertexLayoutFormat))
  uint32_t offset

uint8_t  has_uniforms
if has_uniforms:
  uint32_t uniform_count
  per entry (std::map's natural key-sorted iteration order):
    uint32_t name_len + name bytes
    uint8_t  has_source + [uint32_t source_len + source bytes]
    uint8_t  has_type   + [uint32_t type_tag]   (static_cast<uint32_t>(sgns::DataType))
    uint32_t value_json_len + value bytes       (nlohmann::json::dump() UTF-8;
                                                  empty string if get_value().is_null())

uint32_t vertex_len + vertex bytes

uint8_t  has_index
if has_index:
  uint32_t index_type_tag   (static_cast<uint32_t>(sgns::IndexType))
  uint32_t index_len + index bytes

uint32_t data_transform_count
```

This is the exact byte-for-byte format `RenderProcessor`'s inverse parser (plan 03-03) must implement -- the full docblock comment sits directly above `SerializeRenderPassConfig()`'s definition in `ProcessingManager.cpp` for cross-reference.

## Decisions Made

- **`vertexBuffer->empty()` explicit check preserves INPUT_UNAVAIL semantics**: previously, a render pass's `mainbuffers->second` WAS the raw vertex/model fetch buffer, so a failed fetch (bogus file URI) surfaced via the generic `mainbuffers->second->size() <= 0` check at the end of `GetCidForProc()`. Now that `mainbuffers->second` is always populated by `SerializeRenderPassConfig()` (which always writes at least the `render_target` header, regardless of fetch success), that generic check would never catch a failed vertex fetch on its own. Added an explicit `if (vertexBuffer->empty()) return outcome::failure(Error::INPUT_UNAVAIL);` immediately after the compiled-stages serialization, before calling `SerializeRenderPassConfig()`, to preserve the exact existing failure mode/error code for the `RenderPassValidGlslShadersCompileAndValidateEndToEnd` test.
- **index_buffer with absent source = "no index buffer", not an error**: the schema permits `index_buffer` to declare only `index_type` without a `source`; per the plan's explicit instruction, this is treated as "no usable index buffer" (silently skipped), not rejected by `CheckProcessValidity()` or `GetCidForProc()`.
- **Shared error-message lambda in `CheckProcessValidity()`**: `rejectUnsupportedBufferSourcePrefix` is defined once and called for both the `vertex_buffer` and `index_buffer` checks, so the literal message text `"only input: is resolvable..."` appears exactly once in source (verified via `grep -c`), even though the check itself effectively runs twice (once per field).
- **Submodule pointer bumps batched per level, not per task**: unlike plan 03-01 (which bumped SuperGenius's pointer once per SGProcessingManager task commit), this plan's SuperGenius/GeniusNetwork pointer bumps were each done once, after both SGProcessingManager task commits already existed. Purely a process/granularity difference for supplementary pointer-only commits -- the two load-bearing SGProcessingManager task commits (`0a5fac9`, `a720323`) remain fully atomic and individually revertable.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added explicit `vertexBuffer->empty()` check to preserve INPUT_UNAVAIL failure semantics**
- **Found during:** Task 1 implementation, before running the existing test suite.
- **Issue:** The plan's Task 1 acceptance criteria requires `RenderPassValidGlslShadersCompileAndValidateEndToEnd` to still pass unmodified (asserting `Error::INPUT_UNAVAIL` when `renderInput`'s file URI is bogus). Once `mainbuffers->second` is always populated by `SerializeRenderPassConfig()` (non-empty header even on fetch failure), the pre-existing generic `mainbuffers->second->size() <= 0` check at the end of `GetCidForProc()` would no longer detect a failed vertex-buffer fetch, silently changing this test's expected failure mode.
- **Fix:** Added an explicit `if (vertexBuffer->empty()) return outcome::failure(Error::INPUT_UNAVAIL);` check right after `SerializeCompiledStages()` and before `SerializeRenderPassConfig()`, restoring the exact original failure point/error code.
- **Files modified:** `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp`
- **Verification:** Full CMake link-build of `ProcessingBase`/`processing_dispatch_test`; ran `processing_dispatch_test.exe` -- all 8/8 tests pass, including `RenderPassValidGlslShadersCompileAndValidateEndToEnd` asserting `INPUT_UNAVAIL` specifically.
- **Committed in:** `0a5fac9` (Task 1 commit)

### Out-of-Scope Observation (not a deviation)

The `RenderPassValidGlslShadersCompileAndValidateEndToEnd` test, flagged in 03-01-SUMMARY.md's deferred-items.md (DI-03-01-01) as pre-existing-failing due to a working-directory-relative `file://` fixture URL resolution issue, **passed cleanly in this plan's test runs** (both before and after this plan's changes, run from `test_bin/Release` as the working directory). This appears to have been an environment/cwd artifact of the prior session, not a code defect -- no fix was needed or attempted here, and DI-03-01-01 is left as-is in deferred-items.md for a future plan to formally close if it recurs.

---

**Total deviations:** 1 auto-fixed (1 bug-preservation fix, Rule 1)
**Impact on plan:** The fix was necessary to satisfy the plan's own explicit acceptance criterion (preserving `RenderPassValidGlslShadersCompileAndValidateEndToEnd`'s pass/fail behavior). No scope creep.

## Issues Encountered

None beyond the deviation above.

### Requirements Marking Deferred

This plan's frontmatter lists `requirements: [RENDER-02, RENDER-05]`, but both are multi-plan requirements in this phase's ROADMAP -- plan 03-03's frontmatter also lists `RENDER-02`/`RENDER-05` (alongside `RENDER-09`), since RENDER-02's actual Vulkan buffer *upload* and RENDER-05's actual push-constant/UBO *packing* are built there, not here. This plan only resolves/fetches the bytes and adds defensive validation. Running `requirements mark-complete` now would incorrectly flip both to "Complete" in `REQUIREMENTS.md` while the functionality they describe remains unbuilt. Deliberately skipped; the last plan to touch each ID should perform the mark-complete call (per 03-01-SUMMARY.md's identical precedent for RENDER-09/RENDER-01).

## User Setup Required

None - no external service configuration required.

## Verification

- **Full CMake link-build** of `ProcessingBase` succeeded twice in this working tree (once after Task 1 alone, once after both tasks combined) -- `cmake --build "SuperGenius/build/Windows/Release" --target ProcessingBase --config Release`.
- **Full CMake link-build** of `processing_dispatch_test` succeeded -- `cmake --build "SuperGenius/build/Windows/Release" --target processing_dispatch_test --config Release`.
- `processing_dispatch_test.exe` (all 8 tests, no filter): **8/8 PASSED**, including both render-pass validity tests and the end-to-end GLSL compile+validate test.
- `processing_datatypes_test.exe` (31 tests, the MNN/non-render dispatch regression suite): **31/31 PASSED** -- confirms the `if (!isRender)` guard around the old unconditional `imageUrl` fetch introduced no regression to the non-render dispatch path.
- `grep -c "SerializeRenderPassConfig" ProcessingManager.cpp` → 4 (1 definition + 1 call site + 2 explanatory comments referencing the function by name).
- `grep -c "only input: is resolvable\|only parameter: is resolvable" ProcessingManager.cpp` → 2 (each message string appears exactly once, per Task 2's acceptance criteria).

## Next Phase Readiness

Plan 03-03's `RenderProcessor` now has a real, working, independently-fetched vertex/index buffer wire format to parse (documented byte-for-byte above), plus the only channel through which `render_target`/`pipeline_state`/`vertex_layout`/`uniforms`/`data_transform_count` can ever reach it. `CheckProcessValidity()` fails closed on any unsupported source prefix before a pass is ever dispatched. No blockers for 03-03.

## Self-Check: PASSED

- `.planning/workstreams/sgproc-render/phases/03-renderprocessor-implementation-determinism/03-02-SUMMARY.md` — FOUND
- Commit `0a5fac9` (SGProcessingManager, Task 1) — FOUND
- Commit `a720323` (SGProcessingManager, Task 2) — FOUND
- Commit `c97dee2b` (SuperGenius, pointer bump) — FOUND
- Commit `4979bc8` (GeniusNetwork, pointer bump) — FOUND

---
*Phase: 03-renderprocessor-implementation-determinism*
*Completed: 2026-07-31*
