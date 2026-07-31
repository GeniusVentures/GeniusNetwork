---
phase: 03-renderprocessor-implementation-determinism
plan: 06
subsystem: SGProcessingManager (RenderProcessor / test fixtures)
tags: [vulkan, determinism, vk-bootstrap, empirical-proof, dispatch-test]

requires:
  - phase: 03-05
    provides: "Fully-wired RenderProcessor::StartProcessing() (parse -> resolve -> build -> upload -> draw -> readback -> hash -> teardown), the target this plan's repeat-run test actually exercises end-to-end for the first time"
provides:
  - "render-pass-happy-path-definition.json / scalar_position_vertex_shader.glsl / solid_red_fragment_shader.glsl -- a new, additional, actually-renderable fixture (scalar vertex attribute, point_list topology, 8x8 framebuffer, no uniforms/index buffer/data_transforms), Phase 2's dummy_shader.glsl/dummy_fragment_shader.glsl and their tests left untouched"
  - "ProcessingDispatchTest::WriteHappyPathVertexData() -- test-runtime binary vertex-data file generation, following LoadJson's exact path-construction convention"
  - "TEST_F(ProcessingDispatchTest, RenderPassSameNodeRepeatedExecutionProducesBitExactHash) -- DETV-01's literal empirical proof: 10 full Create()+Process() cycles on real hardware, all resulting hashes byte-identical"
  - "RenderProcessor::InitializeContext() fix: vkb::PhysicalDeviceSelector::require_present(false) -- headless/offscreen rendering has no VkSurfaceKHR, and vk-bootstrap's require_present defaults to true, which previously rejected every physical device with no_surface_provided the moment a real fixture's fetch stage actually succeeded and dispatch reached StartProcessing() for the first time in this codebase"
affects: []

tech-stack:
  added: []
  patterns:
    - "Test-runtime binary fixture generation (WriteHappyPathVertexData()) instead of a hand-authored checked-in binary file -- avoids the unreliability of hand-writing exact binary bytes via a text-based file-write tool"
    - "vkb::PhysicalDeviceSelector::require_present(false) for any future headless/offscreen Vulkan context bootstrap in this codebase -- the same class of gap would recur if InitializeContext() is ever copied as a template elsewhere"

key-files:
  created:
    - SuperGenius/test/src/processing_dispatch/scalar_position_vertex_shader.glsl
    - SuperGenius/test/src/processing_dispatch/solid_red_fragment_shader.glsl
    - SuperGenius/test/src/processing_dispatch/render-pass-happy-path-definition.json
  modified:
    - SuperGenius/test/src/processing_dispatch/CMakeLists.txt
    - SuperGenius/test/src/processing_dispatch/processing_dispatch_test.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp

key-decisions:
  - "Added vkb::PhysicalDeviceSelector::require_present(false) to InitializeContext() (Rule 1 bug fix) -- headless rendering has no swapchain/surface (CTX-01/D-23), so vk-bootstrap's default require_present=true was rejecting every physical device with no_surface_provided; this bug existed since Phase 1 but was never triggered because no fixture before this plan ever got past the fetch-stage failure (INPUT_UNAVAIL) far enough to actually call InitializeContext() with a real, fetchable render pass"
  - "8x8 framebuffer (not 64x64 like Phase 2's dummy fixture) -- this test only needs to prove repeatability across 10 iterations, not visual fidelity; a small framebuffer keeps the repeat-run loop fast"
  - "depth_test: disabled, point_list topology, no index buffer, no uniforms -- removes every variable not load-bearing for the determinism claim itself"

requirements-completed: [DETV-01, DETV-02]

metrics:
  duration: "~50 min"
  completed: "2026-07-31"
status: complete
---

# Phase 3 Plan 6: DETV-01 Empirical Determinism Proof Summary

**The same render pass definition, executed 10 times on real hardware in this working tree via `ProcessingManager::Process()`, produced a bit-exact matching SHA-256 output hash every time -- DETV-01 is empirically confirmed, not merely architecturally argued. Along the way, a real, previously-undiscovered vk-bootstrap `require_present` bug in `RenderProcessor::InitializeContext()` was found and fixed -- this plan's fixture is the first in the entire phase to actually reach that code path with a real, fetchable render pass.**

## Performance

- **Duration:** ~50 min
- **Completed:** 2026-07-31
- **Tasks:** 2
- **Files modified:** 3 new fixtures + 3 modified files (2 in SGProcessingManager submodule, 1 in SuperGenius)

## Accomplishments

- Authored a new, additional, actually-renderable happy-path fixture: `scalar_position_vertex_shader.glsl` (`float inPosition`, explicit `precision highp float;`, `gl_PointSize` set for `point_list` topology), `solid_red_fragment_shader.glsl` (trivial single-assignment, no loop/reduction), and `render-pass-happy-path-definition.json` (8x8 framebuffer, `point_list` topology, no uniforms/index buffer/data_transforms) -- Phase 2's `dummy_shader.glsl`/`dummy_fragment_shader.glsl` (vec3-based, never meant to be pipeline-executed) and their tests remain completely untouched.
- Added `ProcessingDispatchTest::WriteHappyPathVertexData()`, writing 3 scalar `float` vertices (`-0.5f, 0.0f, 0.5f`) as a real binary file at test-runtime, at the exact path `file://processing_dispatch/happy-path-vertex-data.raw` resolves to -- following `LoadJson`'s exact path-construction convention rather than hand-authoring a checked-in binary fixture.
- Added `TEST_F(ProcessingDispatchTest, RenderPassSameNodeRepeatedExecutionProducesBitExactHash)`: 10 iterations, each with a fresh `ProcessingManager`/`ModelNode`/`io_context`, asserting `Process()` succeeds and collecting all 10 resulting hashes; a final loop asserts every hash equals the first, with a per-iteration failure message identifying the first divergence if any occurred.
- **Ran the test for real** against this working tree's actual hardware/driver: **first run failed** with `no_surface_provided` inside `InitializeContext()` -- a genuine, previously-undiscovered bug (see Deviations), not a fixture or test-authoring problem. After the fix, **the test passed: all 10 iterations produced byte-identical SHA-256 hashes.**
- Full regression: `processing_dispatch_test.exe` **10/10 PASSED** (9 pre-existing cases from plans 03-01/03-05 unmodified in outcome + this 1 new case); `processing_datatypes_test.exe` (MNN/non-render suite) **31/31 PASSED** -- the `require_present(false)` fix and the new fixture introduce zero regressions anywhere else.

## Task Commits

Each task was committed atomically:

1. **Task 1: New happy-path fixture** - `1a22674f` (feat, SuperGenius repo, SGProcessingManager submodule's sibling test tree)
2. **Task 2: Repeat-run determinism test + `require_present` fix**:
   - `1c13354` (fix, SGProcessingManager submodule) -- `require_present(false)`
   - `9db765b6` (test, SuperGenius repo) -- the new test + SGProcessingManager pointer bump

**Submodule pointer bump:**
- SuperGenius: `f76686f` (chore, GeniusNetwork repo) -- points to SuperGenius `9db765b6`, which points to SGProcessingManager `1c13354`

## Files Created/Modified

- `SuperGenius/test/src/processing_dispatch/scalar_position_vertex_shader.glsl` - new vertex shader fixture (scalar `float inPosition`).
- `SuperGenius/test/src/processing_dispatch/solid_red_fragment_shader.glsl` - new fragment shader fixture (trivial solid-red output).
- `SuperGenius/test/src/processing_dispatch/render-pass-happy-path-definition.json` - new, schema-valid, actually-renderable render pass definition.
- `SuperGenius/test/src/processing_dispatch/CMakeLists.txt` - fixture-copy list extended with the three new files.
- `SuperGenius/test/src/processing_dispatch/processing_dispatch_test.cpp` - `WriteHappyPathVertexData()` helper + `RenderPassSameNodeRepeatedExecutionProducesBitExactHash` test.
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp` - `InitializeContext()`'s `PhysicalDeviceSelector` now calls `require_present(false)`.

## Decisions Made

See frontmatter `key-decisions`. In summary: the `require_present(false)` fix was the single most consequential finding of this plan -- it is a real bug that has existed in `InitializeContext()` since Phase 1, invisible until now because every prior render-pass fixture in this phase failed earlier, at the fetch stage (`GetCidForProc()`'s `INPUT_UNAVAIL`), before dispatch ever reached `StartProcessing()`/`InitializeContext()`. This plan's happy-path fixture is the first one in the entire phase whose `vertex_buffer.source` actually resolves to real, loadable data, which is precisely why it's also the first to have ever exercised this code path against real hardware.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `RenderProcessor::InitializeContext()` rejected every physical device with `no_surface_provided`**
- **Found during:** Task 2, first real-hardware run of the new repeat-run test.
- **Issue:** `vkb::PhysicalDeviceSelector`'s `require_present` defaults to `true` in vk-bootstrap. `RenderProcessor` is a headless/offscreen renderer with no `VkSurfaceKHR`/swapchain (CTX-01/D-23) and never sets a surface, so `selector.select_devices()` returned `vkb::PhysicalDeviceError::no_surface_provided` for every device, and `InitializeContext()` failed with "no acceptable physical device found" (surfaced as `CONTEXT_INIT_FAILED`) before any pipeline/buffer code ever ran.
- **Fix:** Added `selector.require_present( false )` immediately after constructing the `PhysicalDeviceSelector`, with an explanatory comment referencing CTX-01/D-23.
- **Files modified:** `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp`
- **Verification:** Rebuilt `processing_dispatch_test` and re-ran the new test: went from failing with `CONTEXT_INIT_FAILED`/`no_surface_provided` to **passing** (10/10 iterations, all hashes byte-identical). Re-ran the full `processing_dispatch_test.exe` suite (10/10 PASSED) and `processing_datatypes_test.exe` (31/31 PASSED) to confirm zero regressions.
- **Committed in:** `1c13354` (SGProcessingManager submodule, dedicated fix commit).

### Out-of-Scope Notes (not deviations)

- This is the first plan in Phase 3 whose fixture actually succeeds past `GetCidForProc()`'s fetch stage into `RenderProcessor::StartProcessing()`/`InitializeContext()` with real, present render-input data. Every prior plan's dispatch tests (03-01 through 03-05) deliberately or incidentally stopped short of this point (bogus/missing data URIs, malformed shaders, invalid SPIR-V, or the fetch-level `INPUT_UNAVAIL` regression check) -- none of them were positioned to discover the `require_present` gap, and this is not a gap in those plans' own scope or acceptance criteria.

---

**Total deviations:** 1 auto-fixed (Rule 1 bug fix, found via real-hardware execution, fixed before the task's commit, full regression-verified, no scope creep).

## Issues Encountered

None beyond the deviation above -- and finding that exact issue via a real repeat-run test against real hardware is precisely what this plan exists to do.

## User Setup Required

None - no external service configuration required.

## Verification

- **Real-hardware execution** (this working tree's actual GPU/driver, no software fallback): `RenderPassSameNodeRepeatedExecutionProducesBitExactHash` -- **PASSED**. All 10 `Create()`+`Process()` cycles succeeded; all 10 resulting SHA-256 hashes were byte-identical to the first. **DETV-01 is empirically confirmed on this node's hardware, not merely architecturally argued.**
- **Full CMake link-build** of `processing_dispatch_test` succeeded (`cmake --build "SuperGenius/build/Windows/Release" --target processing_dispatch_test --config Release`), consistent with plans 03-01 through 03-05's established build convention.
- `processing_dispatch_test.exe`: **10/10 PASSED** (9 pre-existing cases from plans 03-01/03-05 unmodified in outcome + this 1 new case).
- `processing_datatypes_test.exe` (31 tests, the MNN/non-render regression suite): **31/31 PASSED** -- confirms the `require_present(false)` fix introduces no regression to the non-render dispatch path.
- `grep -c "happy-path\|scalar_position_vertex_shader\|solid_red_fragment_shader" CMakeLists.txt` -> 3 (all three new fixture entries present).

### Requirements Marked Complete

`DETV-01, DETV-02` -- DETV-01 is satisfied by this plan's own literal, empirical repeat-run proof (the one claim RESEARCH.md flagged as unverifiable by architecture/reasoning alone). DETV-02 (explicit shader precision qualifiers, no unordered parallel-reduction shader math) is satisfied by this plan's own fixture shaders (`precision highp float;` in both stages, trivial single-assignment math with no loop/reduction) -- the only requirement-owning artifact for DETV-02 that this phase's own C++ code cannot itself enforce on arbitrary job-supplied GLSL (per the plan's threat model, T-03-06-02 accepted as out of scope).

## Next Phase Readiness

Phase 3 (RENDER-01..09, DETV-01, DETV-02) is now **complete**: `RenderProcessor::StartProcessing()` is a fully working, real Vulkan render-pass execution (plans 03-01 through 03-05), and this plan's own empirical repeat-run test confirms the phase's entire architectural determinism story actually holds on real hardware in this working tree -- not just in the abstract. The `require_present(false)` fix this plan found and fixed is a permanent correctness fix to `InitializeContext()`, not a workaround scoped to this test alone; it benefits every future caller of `RenderProcessor` in this codebase. No blockers identified for Phase 4 (CI wiring / cross-platform verification).

## Self-Check: PASSED

- `SuperGenius/test/src/processing_dispatch/scalar_position_vertex_shader.glsl` — FOUND
- `SuperGenius/test/src/processing_dispatch/solid_red_fragment_shader.glsl` — FOUND
- `SuperGenius/test/src/processing_dispatch/render-pass-happy-path-definition.json` — FOUND
- Commit `1a22674f` (SuperGenius, Task 1) — FOUND
- Commit `1c13354` (SGProcessingManager, `require_present` fix) — FOUND
- Commit `9db765b6` (SuperGenius, Task 2 test + pointer bump) — FOUND
- Commit `f76686f` (GeniusNetwork, SuperGenius pointer bump) — FOUND

---
*Phase: 03-renderprocessor-implementation-determinism*
*Completed: 2026-07-31*
