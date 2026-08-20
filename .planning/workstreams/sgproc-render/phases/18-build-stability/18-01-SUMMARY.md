---
phase: 18-build-stability
plan: 01
subsystem: testing
tags: [gtest, ctest, vulkan, cmake, sgprocessingmanager, mutex]

# Dependency graph
requires:
  - phase: 09-processor-pass-graph-conformance-suites
    provides: ctest discovery wiring for SGProcessingManager/test/ (enable_testing() ordering fix)
provides:
  - Fresh-session confirmation that 528a92a already fixed the VulkanInitMutex re-entrancy self-deadlock in CapabilityValidator::BuildSnapshot()
  - New persistent regression TEST_F pinning the D-03 scenario (ProcessingManager::Create() with a real Vulkan device present)
  - CMake fail-fast TIMEOUT property on the vulkan_init_concurrency_test ctest target
  - Documented BUILD-01 closure evidence trail (18-BUILD-STABILITY-EVIDENCE.md)
affects: [any future phase touching VulkanInitMutex, ProcessingManager::Create(), or the vulkan_init_concurrency_test target]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "GTEST_SKIP()-gated real-device regression test reusing an existing fixture's SetUpTestSuite/LoadAndPatchJson verbatim"
    - "CMake set_tests_properties(... PROPERTIES TIMEOUT N) fail-fast pattern, N derived from an observed local ctest run (not guessed)"

key-files:
  created:
    - .planning/workstreams/sgproc-render/phases/18-build-stability/18-BUILD-STABILITY-EVIDENCE.md
  modified:
    - SuperGenius/test/src/processing_vulkan_concurrency/vulkan_init_concurrency_test.cpp
    - SuperGenius/test/src/processing_vulkan_concurrency/CMakeLists.txt

key-decisions:
  - "TIMEOUT=12 derived from this session's own observed ctest wall-clock (2.99s rounded up to 3s, x4 margin within RESEARCH.md's 3-5x guidance) rather than reusing RESEARCH.md's illustrative placeholder"
  - "No code change to VulkanInitMutex()/BuildSnapshot()/InitializeContext() — this is a verify-and-close plan per D-03/D-04, not a new fix"

patterns-established:
  - "Verify-and-close bug closure: re-run the original ancestry proof fresh, add persistent regression coverage, document the evidence trail explicitly rather than silently asserting closure"

requirements-completed: [BUILD-01]

coverage:
  - id: D1
    description: "New TEST_F(VulkanConcurrentInitTest, CreateSucceedsWithRealVulkanDevicePresent) pins D-03's exact scenario and passes on a real-Vulkan-device host"
    requirement: "BUILD-01"
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/processing_vulkan_concurrency/vulkan_init_concurrency_test.cpp#VulkanConcurrentInitTest.CreateSucceedsWithRealVulkanDevicePresent"
        status: pass
    human_judgment: false
  - id: D2
    description: "vulkan_init_concurrency_test ctest target has a fail-fast TIMEOUT=12 property, and the target still passes comfortably within it after a fresh build"
    requirement: "BUILD-01"
    verification:
      - kind: integration
        ref: "ctest --test-dir build/Windows/Debug -R ^vulkan_init_concurrency_test$ -C Debug --verbose"
        status: pass
    human_judgment: false
  - id: D3
    description: "Fresh three-test regression gate (processing_datatypes_test, processing_dispatch_test, vulkan_init_concurrency_test) passes 100% clean against a real Vulkan device, evidence trail documented in 18-BUILD-STABILITY-EVIDENCE.md"
    requirement: "BUILD-01"
    verification:
      - kind: integration
        ref: 'ctest --test-dir build/Windows/Debug -R "processing_datatypes_test|processing_dispatch_test|vulkan_init_concurrency_test" -C Debug -j --verbose'
        status: pass
    human_judgment: false

# Metrics
duration: 20min
completed: 2026-08-20
status: complete
---

# Phase 18 Plan 01: Build Stability Summary

**Confirmed BUILD-01's Vulkan capability-probe deadlock was already fixed by 528a92a (predating the bug report), added a persistent regression TEST_F + CMake fail-fast TIMEOUT, and documented the fresh evidence trail closing the requirement.**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-08-20T20:34:39Z
- **Completed:** 2026-08-20T20:48:19Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- Added `TEST_F(VulkanConcurrentInitTest, CreateSucceedsWithRealVulkanDevicePresent)` to `vulkan_init_concurrency_test.cpp`, pinning D-03's exact scenario (single synchronous `ProcessingManager::Create()` call with a real Vulkan device present), gated by `HasUsableVulkanDevice()`/`GTEST_SKIP()`
- Added `set_tests_properties(vulkan_init_concurrency_test PROPERTIES TIMEOUT 12)`, derived from this session's own observed ctest wall-clock (2.99s x4 margin), so a future regression fails fast instead of hanging the suite
- Re-ran `git merge-base --is-ancestor 528a92a HEAD` fresh this session (exit 0) plus `git log` for `528a92a`'s subject/date, confirming the fix is a real, current ancestor — not stale evidence
- Ran the scoped three-test ctest gate fresh (`processing_datatypes_test`, `processing_dispatch_test`, `vulkan_init_concurrency_test`) and captured real "100% tests passed" output, documented verbatim in `18-BUILD-STABILITY-EVIDENCE.md`

## Task Commits

Each task was committed atomically (SuperGenius submodule + outer-repo submodule-pointer bumps):

1. **Task 1: Add D-03's regression TEST_F** - `d4270c79` (SuperGenius, feat) / `c91f0df` (outer repo, chore: bump pointer)
2. **Task 2: Measure real run time and add fail-fast CMake TIMEOUT** - `e902ae2e` (SuperGenius, feat) / `eec3b51` (outer repo, chore: bump pointer)
3. **Task 3: Run scoped regression gate + document evidence trail** - `689b915` (outer repo, docs — no SuperGenius change this task)

**Plan metadata:** committed after this SUMMARY via the standard final-commit step.

## Files Created/Modified
- `SuperGenius/test/src/processing_vulkan_concurrency/vulkan_init_concurrency_test.cpp` - new `#include <processors/vulkan_gpu_probe.hpp>` and new `TEST_F(VulkanConcurrentInitTest, CreateSucceedsWithRealVulkanDevicePresent)`; `RepeatedConcurrentInitNoRaceOrCrash` byte-for-byte unchanged
- `SuperGenius/test/src/processing_vulkan_concurrency/CMakeLists.txt` - new `set_tests_properties(vulkan_init_concurrency_test PROPERTIES TIMEOUT 12)` line with a citing comment
- `.planning/workstreams/sgproc-render/phases/18-build-stability/18-BUILD-STABILITY-EVIDENCE.md` - new closure-evidence document (D-02 fresh ancestry proof, fresh three-test ctest output, closure verdict)

## Decisions Made
- Derived `TIMEOUT=12` from this session's own observed wall-clock run (2.99s rounded up to 3s, x4 margin), not RESEARCH.md's illustrative placeholder value, per the plan's explicit instruction
- Did not modify `VulkanInitMutex()`, `CapabilityValidator::BuildSnapshot()`, or `RenderProcessor::InitializeContext()` — reference-only per D-03/D-04, matching ROADMAP SC4's locked constraint
- Kept the new regression test single-threaded/synchronous (no `std::thread`), matching D-03's exact scenario and avoiding duplication of `RepeatedConcurrentInitNoRaceOrCrash`'s existing concurrency coverage

## Deviations from Plan

None - plan executed exactly as written. All three tasks completed per their literal `<action>` text; no auto-fixes, no architectural decisions needed, no auth gates encountered.

## Issues Encountered

None. The D-05 flaky `processing_dispatch_test` CWD-relative failure noted in 18-CONTEXT.md did not recur during this session's fresh three-test gate — recorded as an observation in `18-BUILD-STABILITY-EVIDENCE.md`, not investigated (explicitly out of scope per the locked user decision).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- BUILD-01 is closed. `ProcessingManager::Create()`'s Vulkan capability probe no longer deadlocks the three named test suites on a real-Vulkan-device host, backed by a persistent, re-runnable regression test rather than a one-time manual repro.
- The `GeniusCognitiveSystem`/neoswarm workstream's stale skip-guard (`Fp4UltraFormat_DispatchesToTensorProcessor`/`LlmDataType_JobReachesRegisteredProcessor`, both preemptively `GTEST_SKIP()`ing to dodge this exact bug) is now a strong, evidence-backed candidate for removal in a future cross-repo todo/phase — explicitly out of this phase's SuperGenius-only scope (D-04), flagged here for visibility only.
- No blockers for Phase 19 (Validation Re-Verification) or any other remaining v2.3 phase.

---
*Phase: 18-build-stability*
*Completed: 2026-08-20*

## Self-Check: PASSED

All created/modified files confirmed present on disk (`vulkan_init_concurrency_test.cpp`, `CMakeLists.txt`, `18-BUILD-STABILITY-EVIDENCE.md`, `18-01-SUMMARY.md`). All commit hashes confirmed present in git history (`d4270c79`, `e902ae2e` in `SuperGenius`; `c91f0df`, `eec3b51`, `689b915`, `825ef32` in the outer repo).
