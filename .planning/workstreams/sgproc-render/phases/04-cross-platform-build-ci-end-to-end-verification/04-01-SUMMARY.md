---
phase: 04-cross-platform-build-ci-end-to-end-verification
plan: 01
subsystem: testing
tags: [vulkan, vk-bootstrap, gtest, gtest-skip, render-processor, gpu-probe]

requires:
  - phase: 03-renderprocessor-implementation-determinism
    provides: "Fully-wired RenderProcessor::StartProcessing() and the render-pass-happy-path-definition.json / scalar_position_vertex_shader.glsl / solid_red_fragment_shader.glsl fixture this plan's new E2E-01 test reuses"
provides:
  - "sgns::sgprocessing::HasUsableVulkanDevice() -- runtime GPU probe (throwaway VkInstance, headless device enumeration, DISCRETE_GPU/INTEGRATED_GPU filter via the now-public RenderProcessor::IsAcceptable(), shared-lock-safe under VulkanInitMutex(), never throws)"
  - "RenderProcessor::IsAcceptable() moved from private to public -- reusable by any future Vulkan-device-dependent probe/test without duplicating the device-type filter"
  - "GTEST_SKIP() retrofit on RenderPassSameNodeRepeatedExecutionProducesBitExactHash -- skips cleanly (not a hard fail) on GPU-less hosts, emitting the exact literal substring plan 04-02's CI annotation step will grep for"
  - "New TEST_F(ProcessingDispatchTest, RenderPassEndToEndProducesVerifiedOutputHash) -- E2E-01's single-run real-job-definition-to-verified-hash proof, gated by the same skip guard, conceptually distinct from the 10x DETV-01 repeat-run test"
affects: [04-02, 04-03]

tech-stack:
  added: []
  patterns:
    - "GTEST_SKIP() gating idiom for GPU-dependent tests -- first use of this idiom in the codebase; probe-and-skip lives inside the test binary, not at the CMake/CTest level (addtest() unmodified)"
    - "Direct-exe test invocation for local verification -- CTest's default per-directory WORKING_DIRECTORY does not contain the post-build fixture copies (they land next to the exe via boost::dll::program_location()), so ctest run from the build root fails to find file:// fixtures; running the .exe directly from its own bin directory is the established verification pattern for this test file (matches Phase 03-06's own verification approach)"

key-files:
  created:
    - SuperGenius/SGProcessingManager/include/processors/vulkan_gpu_probe.hpp
    - SuperGenius/SGProcessingManager/src/processors/vulkan_gpu_probe.cpp
  modified:
    - SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp
    - SuperGenius/SGProcessingManager/src/processors/CMakeLists.txt
    - SuperGenius/test/src/processing_dispatch/processing_dispatch_test.cpp

key-decisions:
  - "HasUsableVulkanDevice() wrapped in a try/catch (catch (...) -> false) even though vk-bootstrap's own API is result-based, not exception-based -- the plan's own 'must never throw' requirement is a hard invariant for a probe that gates test execution, so this is defense-in-depth rather than a response to an observed throw"

requirements-completed: [DETV-03, E2E-01]

coverage:
  - id: D1
    description: "A GPU-dependent render test skips cleanly (GTEST_SKIP, not silent pass, not hard fail) when no usable Vulkan device is present"
    requirement: "DETV-03"
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/processing_dispatch/processing_dispatch_test.cpp#ProcessingDispatchTest.RenderPassSameNodeRepeatedExecutionProducesBitExactHash"
        status: pass
    human_judgment: false
  - id: D2
    description: "A real render-pass job definition submitted end-to-end through ProcessingManager::Process() produces a verified 32-byte output hash on real GPU hardware (E2E-01)"
    requirement: "E2E-01"
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/processing_dispatch/processing_dispatch_test.cpp#ProcessingDispatchTest.RenderPassEndToEndProducesVerifiedOutputHash"
        status: pass
    human_judgment: false

duration: 60min
completed: 2026-07-31
status: complete
---

# Phase 4 Plan 1: GPU Probe + Skip Guard + E2E-01 Single-Run Test Summary

**Added `sgns::sgprocessing::HasUsableVulkanDevice()` (a headless throwaway-VkInstance probe reusing the now-public `RenderProcessor::IsAcceptable` filter), retrofitted a clean `GTEST_SKIP()` onto the existing hard-failing determinism test, and added a new single-run `RenderPassEndToEndProducesVerifiedOutputHash` test proving E2E-01 -- verified end-to-end on this host's real GPU (11/11 dispatch tests, 31/31 MNN regression tests, zero regressions).**

## Performance

- **Duration:** ~60 min
- **Tasks:** 2
- **Files modified:** 5 (2 new, 3 modified)

## Accomplishments

- `HasUsableVulkanDevice()`: builds a throwaway `VkInstance` under `VulkanInitMutex()`, enumerates physical devices headlessly (`require_present(false)`), filters via `RenderProcessor::IsAcceptable()` (now public, no duplicated filter), always destroys the instance, never throws.
- `RenderProcessor::IsAcceptable()` moved from `private:` to `public:` -- a pure stateless predicate, zero behavior change, unlocks direct reuse.
- Both new files registered in `SGProcessors`'s CMake source list; incremental build of the `SGProcessors` target compiled with 0 errors.
- `RenderPassSameNodeRepeatedExecutionProducesBitExactHash` now `GTEST_SKIP()`s with the exact literal substring "No usable Vulkan device" when no usable device is found, instead of hard-failing.
- New `TEST_F(ProcessingDispatchTest, RenderPassEndToEndProducesVerifiedOutputHash)`: single-run `Create()` + `Process()` against the same happy-path fixture, asserting a real 32-byte SHA-256 hash that is not the all-zero sentinel -- proves E2E-01 without duplicating the 10x DETV-01 repeat-run concern.
- Verified on real hardware: both GPU-gated tests ran to completion (not skipped -- a usable Vulkan device is present on this host) and passed; full `processing_dispatch_test.exe` suite 11/11 PASSED; `processing_datatypes_test.exe` (MNN suite) 31/31 PASSED -- zero regressions.

## Task Commits

Each task was committed atomically (this is a nested-submodule project: `SGProcessingManager` -> `SuperGenius` -> `GeniusNetwork`):

1. **Task 1: GPU probe helper + widen IsAcceptable visibility** - `aaed093` (feat, SGProcessingManager submodule)
2. **Task 2: Retrofit GTEST_SKIP guard + add E2E-01 test**:
   - `c3770e1d` (test, SuperGenius repo) -- new test + skip guard + SGProcessingManager pointer bump
   - `778d278` (chore, GeniusNetwork repo) -- SuperGenius pointer bump

## Files Created/Modified

- `SuperGenius/SGProcessingManager/include/processors/vulkan_gpu_probe.hpp` - declares `HasUsableVulkanDevice()`
- `SuperGenius/SGProcessingManager/src/processors/vulkan_gpu_probe.cpp` - implements the probe
- `SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp` - `IsAcceptable` moved to `public:`
- `SuperGenius/SGProcessingManager/src/processors/CMakeLists.txt` - registers the two new files in `SGProcessors`
- `SuperGenius/test/src/processing_dispatch/processing_dispatch_test.cpp` - skip guard retrofit + new E2E-01 test case

## Decisions Made

- Wrapped `HasUsableVulkanDevice()`'s body in `try { ... } catch (...) { return false; }` -- the plan's action explicitly requires the function "must never throw"; vk-bootstrap's API itself is result-based (no exceptions expected in normal operation), so this is a defensive belt-and-suspenders measure, not a response to an observed exception.
- No other deviations -- plan executed exactly as written otherwise.

## Deviations from Plan

None - plan executed exactly as written. (The try/catch above is an implementation-detail elaboration of the plan's own explicit "must never throw" requirement, not a deviation from it.)

## Issues Encountered

- Running `ctest . -C Release -R "^processing_dispatch_test$"` from the build root (`SuperGenius/build/Windows/Release`) fails to find the test's `file://processing_dispatch/...` fixtures, because CTest's default per-test `WORKING_DIRECTORY` is the test's own build subdirectory (`build/Windows/Release/test/src/processing_dispatch`), which does not contain the post-build fixture copies -- those land next to the compiled `.exe` (`test_bin/Release/processing_dispatch/`) via the `POST_BUILD` custom command, and are resolved by the test code via `boost::dll::program_location()`, not the process's current working directory. This is a pre-existing environment/CWD mismatch affecting every test in this file that reads a `file://` fixture (confirmed: `RenderPassValidGlslShadersCompileAndValidateEndToEnd`, which this plan did not touch, fails identically under `ctest` for the same reason) -- not something introduced by this plan's changes, and not in scope to fix (would require changing `addtest()`'s CMake registration for every test in the codebase). Phase 03-06's own SUMMARY documents the same established workaround: run the compiled test binary directly from its own `test_bin/Release/` directory. Doing so here: **11/11 `processing_dispatch_test.exe` PASSED**, **31/31 `processing_datatypes_test.exe` PASSED** -- confirms both new/modified GPU-gated tests pass on real hardware and zero regressions occurred elsewhere.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `HasUsableVulkanDevice()` and its exact skip-message literal ("No usable Vulkan device") are ready for plan 04-02's CI annotation step to grep for.
- E2E-01 is satisfied end-to-end on real hardware in this working tree; E2E-02 (macOS/MoltenVK GPU passthrough) remains open per STATE.md's existing blocker note and is out of this plan's scope.
- No blockers identified for plan 04-02 (CI wiring) or 04-03 (regression confirmation).

---
*Phase: 04-cross-platform-build-ci-end-to-end-verification*
*Completed: 2026-07-31*

## Self-Check: PASSED

- `.planning/workstreams/sgproc-render/phases/04-cross-platform-build-ci-end-to-end-verification/04-01-SUMMARY.md` — FOUND
- `SuperGenius/SGProcessingManager/include/processors/vulkan_gpu_probe.hpp` — FOUND
- `SuperGenius/SGProcessingManager/src/processors/vulkan_gpu_probe.cpp` — FOUND
- Commit `aaed093` (SGProcessingManager, Task 1) — FOUND
- Commit `c3770e1d` (SuperGenius, Task 2) — FOUND
- Commit `778d278` (GeniusNetwork, submodule pointer bump) — FOUND
