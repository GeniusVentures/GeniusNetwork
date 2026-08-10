---
phase: 10-capture-harness-diff-tool-quantization-stub
plan: 06
subsystem: testing
tags: [cpp, cmake, ctest, gtest, sgprocessingmanager, capture]

# Dependency graph
requires:
  - phase: "10-05"
    provides: "capture_harness/capture_diff CLI tools + sgproccapture CMake static library wrapping capture_file_format.hpp/.cpp"
provides:
  - "SGProcessingManager/test/ wired into the main SuperGenius CMake build for the first time (via a new guarded add_subdirectory(test) in SGProcessingManager/CMakeLists.txt)"
  - "capture_smoke_test: CTest-registered smoke test proving capture_harness builds, runs, and produces a well-formed, round-trippable .cap file"
  - "Fix for a pre-existing CTest discovery ordering bug in SuperGenius/build/CommonBuildParameters.cmake (enable_testing() now runs before add_subdirectory(SGProcessingManager)), without which none of SGProcessingManager/test/'s registered tests (Phase 06-08's capability/execution/artifacts suites, plus this plan's new capture_smoke_test) were ever discoverable via ctest"
affects: [phase-11-empirical-cross-machine-capture-run]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "GTest smoke test invoking a sibling CLI tool as a std::system() subprocess, with all substituted paths (CAPTURE_HARNESS_PATH/FIXTURE_ROOT_PATH/OUTPUT_DIR_PATH) supplied at compile time via CMake generator expressions -- no untrusted input reaches the command line (T-10-12)"

key-files:
  created:
    - SuperGenius/SGProcessingManager/test/capture/CMakeLists.txt
    - SuperGenius/SGProcessingManager/test/capture/capture_smoke_test.cpp
  modified:
    - SuperGenius/SGProcessingManager/CMakeLists.txt
    - SuperGenius/SGProcessingManager/test/CMakeLists.txt
    - SuperGenius/build/CommonBuildParameters.cmake

key-decisions:
  - "Moved enable_testing() to run before add_subdirectory(ProofSystem)/add_subdirectory(SGProcessingManager)/add_subdirectory(evmrelay)/add_subdirectory(src) in SuperGenius/build/CommonBuildParameters.cmake, keeping the existing if(BUILD_TESTING) guard, rather than leaving it in its original position inside the later if(BUILD_TESTING) block that only preceded add_subdirectory(test) -- this was a genuine pre-existing bug (not introduced by this plan) that made every test registered inside SGProcessingManager/test/ permanently undiscoverable by ctest run from the build root, invisible until this plan's Task 1 wiring fix first gave that subtree any tests to discover at all"

requirements-completed: [CAPT-01]

coverage:
  - id: D1
    description: "SGProcessingManager/test/ (previously unwired into any build) is reachable from the main SuperGenius CMake build, and capture_smoke_test proves capture_harness builds, runs, and produces a well-formed, round-trippable .cap file via CTest -- without asserting cross-machine hash equality"
    requirement: "CAPT-01"
    verification:
      - kind: other
        ref: "cmake .. (Visual Studio 17 2022 generator, build/Windows/Debug) -- configure succeeds with the new if(BUILD_TESTING) add_subdirectory(test) endif() in place"
        status: pass
      - kind: other
        ref: "cmake --build . --target capture_smoke_test --config Debug -- builds with zero errors"
        status: pass
      - kind: other
        ref: "ctest -R CaptureSmokeTest -C Debug --output-on-failure -> Test #17: CaptureSmokeTest, Passed, 7.21 sec (real Vulkan device present on this host; GTEST_SKIP() path not exercised)"
        status: pass
      - kind: other
        ref: "ctest -R CapabilityValidatorTest -C Debug --output-on-failure -> Test #1: CapabilityValidatorTest, Passed, 0.72 sec -- confirms the pre-existing Phase 06-08 suites are now discoverable/passing as a side effect of Task 1's fix (ctest -N test count: 84 -> 101 after this plan's two CMake fixes)"
        status: pass
    human_judgment: false

# Metrics
duration: 20min
completed: 2026-08-10
status: complete
---

# Phase 10 Plan 06: Capture Smoke Test & Build Wiring Summary

**Wired SGProcessingManager/test/ into the main SuperGenius build for the first time and added a CTest-registered `capture_smoke_test` proving `capture_harness` produces a well-formed, round-trippable `.cap` file -- plus a root-cause fix for a pre-existing `enable_testing()` ordering bug that had silently made every test under `SGProcessingManager/test/` undiscoverable by `ctest`.**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-08-10T19:59:40Z
- **Completed:** 2026-08-10T20:15:09Z
- **Tasks:** 2
- **Files modified:** 5 (2 created, 3 modified)

## Accomplishments

- `SGProcessingManager/CMakeLists.txt` now calls `if(BUILD_TESTING) add_subdirectory(test) endif()` immediately after the existing `add_subdirectory(src)` -- `SGProcessingManager/test/` (containing the pre-existing Phase 06-08 `capability`/`execution`/`artifacts` suites) is reachable from the main build for the first time
- `SGProcessingManager/test/CMakeLists.txt` gained `add_subdirectory(capture)` alongside its 3 existing `add_subdirectory` calls
- New `test/capture/CMakeLists.txt`: `capture_smoke_test` GTest executable linked against `SGProcessors` (for `HasUsableVulkanDevice()`) and `sgproccapture` (for `DeserializeCaptureFile`), with `CAPTURE_HARNESS_PATH`/`FIXTURE_ROOT_PATH`/`OUTPUT_DIR_PATH` supplied via CMake generator expressions, registered via `add_test(NAME CaptureSmokeTest COMMAND capture_smoke_test)`
- New `test/capture/capture_smoke_test.cpp`: `GTEST_SKIP()`s (mirroring the Phase 09 `HasUsableVulkanDevice()` convention) when no usable Vulkan device is present; otherwise invokes `capture_harness` as a subprocess against the `mnn-float` fixture (`--repeat 2`), asserts exit 0, exactly one well-formed `smoke-mnn-float_*.cap` output file, and a successful `DeserializeCaptureFile` round-trip (`artifacts.size()==1`, `combinedHash.size()==32`) -- deliberately asserts no specific hash value or cross-machine equality, per ARCHITECTURE.md Anti-Pattern 4
- **Root-cause fix discovered during Task 1 verification:** re-ran `cmake ..` and confirmed both `SGProcessingManager/CMakeLists.txt` changes configured cleanly and both `capture_smoke_test`/`capability_validator_test` built with zero errors -- but `ctest -N` reported "No tests were found!!!" for both. Traced to `SuperGenius/build/CommonBuildParameters.cmake` calling `enable_testing()` only inside the later `if(BUILD_TESTING)` block guarding `add_subdirectory(test)`, i.e. *after* `add_subdirectory(SGProcessingManager)` (and `ProofSystem`/`evmrelay`/`src`) had already been fully configured. CTest's per-directory `CTestTestfile.cmake` chain can only be generated for directories processed after testing is enabled in their ancestor scope, so the build root's own `CTestTestfile.cmake` had a dangling `subdirs("SGProcessingManager")` entry pointing at a directory that never got its own `CTestTestfile.cmake` written -- silently swallowing every test registered anywhere under `SGProcessingManager/test/`, even though the leaf `CMakeLists.txt` files call `enable_testing()`/`add_test()` themselves. Fixed by moving `enable_testing()` (still under the existing `BUILD_TESTING` guard) to run before the four `add_subdirectory()` calls; `add_subdirectory(test)` keeps its own guard. After the fix: `ctest -N`'s total test count went from 84 to 101, `CapabilityValidatorTest` and `CaptureSmokeTest` both appear in the list, and both pass when run individually
- End-to-end verified on this machine (a real Vulkan device is present, so the `GTEST_SKIP()` path was not exercised): `ctest -R CaptureSmokeTest -C Debug` passed in 7.21s; `ctest -R CapabilityValidatorTest -C Debug` passed in 0.72s, confirming the pre-existing Phase 06-08 suites are also now reachable as Task 1 predicted

## Task Commits

Each task was committed atomically. Tasks 1-2 landed in the nested `SGProcessingManager` git submodule (branch `dev_rendering`); the ordering-bug fix landed in the `SuperGenius` submodule itself (a separate git repository, branch `dev_childwallet`), since `build/CommonBuildParameters.cmake` lives there, not inside `SGProcessingManager`:

1. **Task 1: Wire SGProcessingManager/test into the main build** - `d2d8ff2` (feat, `SGProcessingManager` submodule)
2. **Task 2: Create test/capture/CMakeLists.txt and capture_smoke_test.cpp** - `36ec12f` (feat, `SGProcessingManager` submodule)
3. **Deviation fix: enable_testing() ordering bug** - `393de4e3` (fix, `SuperGenius` submodule)
4. **Submodule pointer bump** - `3e83ea39` (chore, `SuperGenius` submodule, records the `SGProcessingManager` pointer advancing past commits 1-2 above)

_Note: this is the fourth plan in this phase's wave sequence to land commits in the nested `SGProcessingManager` git submodule (`W:\gnus\GeniusNetwork\SuperGenius\SGProcessingManager`) rather than the top-level repo, consistent with Plans 10-01 through 10-05's precedent. This plan additionally required one commit directly in the `SuperGenius` submodule itself (a distinct git repository one level up), which prior Phase 10 plans did not need to touch._

## Files Created/Modified

- `SuperGenius/SGProcessingManager/CMakeLists.txt` - Added `if(BUILD_TESTING) add_subdirectory(test) endif()` after `add_subdirectory(src)`
- `SuperGenius/SGProcessingManager/test/CMakeLists.txt` - Added `add_subdirectory(capture)`
- `SuperGenius/SGProcessingManager/test/capture/CMakeLists.txt` - New: `capture_smoke_test` GTest executable + `add_test(NAME CaptureSmokeTest ...)`
- `SuperGenius/SGProcessingManager/test/capture/capture_smoke_test.cpp` - New: GTest smoke test running `capture_harness` as a subprocess and round-tripping its output via `DeserializeCaptureFile`
- `SuperGenius/build/CommonBuildParameters.cmake` - Moved `enable_testing()` to run before `add_subdirectory(ProofSystem/SGProcessingManager/evmrelay/src)` (Rule 3 auto-fix; see Deviations)

## Decisions Made

- `enable_testing()` reordering fix applied directly (Rule 3 -- blocking issue preventing the plan's own literal verification requirement `ctest -R CaptureSmokeTest passes`) rather than deferred/asked-about, since it is a minimal (10-line), purely-additive-ordering change confined to one file, with no behavior change for any existing test and no new functionality -- it only makes previously-registered-but-undiscoverable tests discoverable
- `FIXTURE_ROOT_PATH` points at `SuperGenius/test/src` (three levels up from `test/capture/`), matching `capture_harness`'s own fixture-root convention from Plan 10-05 -- no fixture-copying `add_custom_command` needed

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed pre-existing `enable_testing()` ordering bug in `SuperGenius/build/CommonBuildParameters.cmake`**
- **Found during:** Task 2 verification (running `ctest -R CaptureSmokeTest` per the plan's own `<verification>` step 2)
- **Issue:** `enable_testing()` was only called inside the `if(BUILD_TESTING)` block immediately preceding `add_subdirectory(test)`, which runs *after* `add_subdirectory(ProofSystem)`, `add_subdirectory(SGProcessingManager)`, `add_subdirectory(evmrelay)`, and `add_subdirectory(src)`. Since CTest can only generate a directory's `CTestTestfile.cmake` if testing was already enabled in that directory's ancestor scope by the time it was configured, `SGProcessingManager` and `SGProcessingManager/test/` never got their own `CTestTestfile.cmake` files, even though their leaf `CMakeLists.txt` files (`test/capability`, `test/capture`, etc.) call `enable_testing()`/`add_test()` themselves. The build root's own `CTestTestfile.cmake` still listed `subdirs("SGProcessingManager")` (added unconditionally regardless of test-enablement timing), but that entry pointed at a directory with no matching file on the other end -- so `ctest -N`/`ctest -R CaptureSmokeTest` silently reported zero tests, with no error. This bug was invisible before this plan because `SGProcessingManager/test/` had never been wired into the build at all until Task 1.
- **Fix:** Added `if(BUILD_TESTING) enable_testing() endif()` immediately before the four `add_subdirectory()` calls in `build/CommonBuildParameters.cmake`; the pre-existing `add_subdirectory(test)` block keeps its own `if(BUILD_TESTING)` guard (calling `enable_testing()` a second time is idempotent).
- **Files modified:** `SuperGenius/build/CommonBuildParameters.cmake`
- **Verification:** Re-ran `cmake ..`; `ctest -N` total test count went from 84 to 101 (adds `CapabilityValidatorTest`, `CaptureSmokeTest`, and the Phase 07 execution-suite placeholder entries). `ctest -R CaptureSmokeTest -C Debug` passed (7.21s); `ctest -R CapabilityValidatorTest -C Debug` passed (0.72s).
- **Committed in:** `393de4e3` (in the `SuperGenius` submodule, not `SGProcessingManager`)

---

**Total deviations:** 1 auto-fixed (1 blocking build-config fix)
**Impact on plan:** Necessary to satisfy the plan's own literal verification requirement (`ctest -R CaptureSmokeTest` actually passing, not just the target building). The fix is a 10-line, purely-additive reordering with zero behavior change for any pre-existing test; no scope creep into unrelated build configuration.

## Issues Encountered

- `capability_validator_test.cpp` emits a pre-existing `C4005: 'SGPROCMGR_TEST_FRIEND': macro redefinition` warning when built (the file both defines the macro via a `#define` at line 8 and receives it again via `target_compile_definitions`). This is unrelated to this plan's files and out of scope per the SCOPE BOUNDARY rule -- not fixed, only observed while confirming the Task 1 side-effect build.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 10 is now complete: all 6 plans across 4 waves have landed. `capture_harness`/`capture_diff` (Plan 10-05) are built and wired into the real CMake tree; `SGProcessingManager/test/` is reachable from the main build for the first time, with `capture_smoke_test` proving `capture_harness` produces a well-formed, round-trippable capture file in ordinary CI, and the pre-existing Phase 06-08 suites now discoverable as a side effect. Phase 11 (Empirical Cross-Machine Capture Run) can proceed using `capture_harness`/`capture_diff` as-is on the user's Mac + PC + a third machine -- no further tooling work required before that phase's manual capture/copy/diff workflow can begin. No blockers identified.

---
*Phase: 10-capture-harness-diff-tool-quantization-stub*
*Completed: 2026-08-10*

## Self-Check: PASSED

- FOUND: SuperGenius/SGProcessingManager/test/capture/CMakeLists.txt
- FOUND: SuperGenius/SGProcessingManager/test/capture/capture_smoke_test.cpp
- FOUND: SuperGenius/SGProcessingManager/CMakeLists.txt
- FOUND: SuperGenius/SGProcessingManager/test/CMakeLists.txt
- FOUND: SuperGenius/build/CommonBuildParameters.cmake
- FOUND: commit d2d8ff2 (SGProcessingManager submodule)
- FOUND: commit 36ec12f (SGProcessingManager submodule)
- FOUND: commit 393de4e3 (SuperGenius submodule)
- FOUND: commit 3e83ea39 (SuperGenius submodule)
