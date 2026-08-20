---
phase: 18-build-stability
captured: 2026-08-20
status: BUILD-01 closed — pre-existing fix (528a92a) confirmed present at HEAD, fresh regression test added, fresh three-test ctest gate passes clean
---

# Phase 18: Build Stability — BUILD-01 Closure Evidence

**Phase Goal:** `ProcessingManager::Create()`'s Vulkan capability probe no longer deadlocks `ProcessingDatatypesTest`, `ProcessingDispatchTest`, or `vulkan_init_concurrency_test` when a real Vulkan device is present, and this closure is backed by re-runnable proof, not a one-time manual repro.

**Approach:** This is a verify-and-close plan, not a new fix. Per 18-CONTEXT.md D-01/D-02, the `VulkanInitMutex` self-deadlock the original todo describes was already fixed by commit `528a92a` in the `SGProcessingManager` submodule, predating both the todo's filing (2026-08-10) and this phase's creation (2026-08-17). This document re-runs that ancestry check fresh this session (not a re-citation of CONTEXT.md's prior claim), adds one persistent regression `TEST_F` pinning the exact scenario, and captures a fresh three-test ctest pass as the closure evidence trail — mirroring `13-SCOPE-BOUNDARY.md`'s honest-reporting convention.

## D-02 Evidence Trail: Fresh Ancestry Check (this session)

Re-run from `SuperGenius/SGProcessingManager` this session (2026-08-20), not reused from CONTEXT.md/RESEARCH.md:

```
$ git merge-base --is-ancestor 528a92a HEAD
$ echo "exit status: $?"
exit status: 0

$ git log -1 --format="%H %ad %s" --date=iso 528a92a
528a92a5a331781fcf2576d5d382d84eec23a39f 2026-08-06 16:12:34 -0400 Fix hang on OSX
```

**Interpretation:** `git merge-base --is-ancestor 528a92a HEAD` exits `0`, confirming `528a92a` ("Fix hang on OSX", authored 2026-08-06) is a genuine ancestor of the current `SGProcessingManager` submodule HEAD as of this session. This fix predates the original bug report's filing date (2026-08-10) by four days — the todo was filed against stale, not-yet-rebuilt test binaries, and the fix has been present at HEAD the entire time this project's `STATE.md`/`ROADMAP.md` carried BUILD-01 forward as still-open.

The fix itself (`CapabilityValidator::BuildSnapshot()`, `src/capability/capability_validator.cpp:211-235`) restructures the capability probe so `ensureVulkanDevice()` is called *outside* `VulkanInitMutex()`'s lock — `ensureVulkanDevice()` itself acquires the same mutex internally via `RenderProcessor::InitializeContext()`'s double-checked-locking pattern, so holding the lock across that call would self-deadlock on the same thread. This is exactly the re-entrancy pattern the original todo describes. `VulkanInitMutex()`'s locking model/type itself was not touched by that fix and is not touched by this phase either (per D-03/ROADMAP SC4).

## New Regression Test (Task 1) + TIMEOUT (Task 2)

Added `TEST_F(VulkanConcurrentInitTest, CreateSucceedsWithRealVulkanDevicePresent)` to `SuperGenius/test/src/processing_vulkan_concurrency/vulkan_init_concurrency_test.cpp`. This test pins D-03's exact scenario — a single, synchronous `ProcessingManager::Create()` call on the main test thread (no concurrency; `RepeatedConcurrentInitNoRaceOrCrash` already covers concurrent access) — gated by `HasUsableVulkanDevice()`/`GTEST_SKIP()` mirroring `capture_smoke_test.cpp`'s precedent, so it degrades gracefully on GPU-less hosts instead of failing. The existing `RepeatedConcurrentInitNoRaceOrCrash` test body is unchanged; only additive lines were introduced.

Added a fail-fast CMake `TIMEOUT` property to the same ctest target in `SuperGenius/test/src/processing_vulkan_concurrency/CMakeLists.txt`:

```cmake
set_tests_properties( vulkan_init_concurrency_test PROPERTIES TIMEOUT 12 )
```

**Derivation:** A fresh, dedicated ctest run of this target alone (both `TEST_F` cases, including the new regression test) on this real-Vulkan-device host reported:

```
1/1 Test #111: vulkan_init_concurrency_test .....   Passed    2.99 sec
```

`2.99s` rounded up to `3s`, multiplied by `4` (within RESEARCH.md's suggested 3-5x margin) gives `TIMEOUT=12`. A subsequent fresh build + re-run after the CMakeLists.txt edit still reported `Passed` well within this bound (`5.64 sec`), confirming the timeout is generous, not tight. If `VulkanInitMutex()`'s re-entrancy bug is ever reintroduced, this target will now report a bounded ctest `Timeout` failure at 12 seconds instead of hanging the suite indefinitely.

## Fresh Three-Test Regression Gate (this session)

Per the project's established test-scoping convention (not the full ~65-minute SuperGenius suite), ran the scoped three-test gate from `SuperGenius/`:

```
ctest --test-dir build/Windows/Debug -R "processing_datatypes_test|processing_dispatch_test|vulkan_init_concurrency_test" -C Debug -j --verbose
```

Real captured summary output (verbatim, not paraphrased):

```
111: [----------] 2 tests from VulkanConcurrentInitTest
111: [ RUN      ] VulkanConcurrentInitTest.RepeatedConcurrentInitNoRaceOrCrash
111: [       OK ] VulkanConcurrentInitTest.RepeatedConcurrentInitNoRaceOrCrash (2879 ms)
111: [ RUN      ] VulkanConcurrentInitTest.CreateSucceedsWithRealVulkanDevicePresent
111: [       OK ] VulkanConcurrentInitTest.CreateSucceedsWithRealVulkanDevicePresent (22 ms)
111: [----------] 2 tests from VulkanConcurrentInitTest (2902 ms total)
111: [  PASSED  ] 2 tests.
1/3 Test #111: vulkan_init_concurrency_test .....   Passed    4.04 sec
106: [  PASSED  ] 12 tests.
2/3 Test #106: processing_dispatch_test .........   Passed   18.81 sec
105: [  PASSED  ] 41 tests.
3/3 Test #105: processing_datatypes_test ........   Passed  106.44 sec

100% tests passed, 0 tests failed out of 3

Total Test time (real) = 106.46 sec
```

Both `VulkanConcurrentInitTest.CreateSucceedsWithRealVulkanDevicePresent` (new, Task 1) and `VulkanConcurrentInitTest.RepeatedConcurrentInitNoRaceOrCrash` (pre-existing) show `[ OK ]` / passed in the captured output above. All three named ctest targets (`processing_datatypes_test`, `processing_dispatch_test`, `vulkan_init_concurrency_test`) report `Passed`, and the run's own summary line confirms `100% tests passed, 0 tests failed out of 3`.

## D-05: Flaky `processing_dispatch_test` CWD-Relative Failure — Did Not Recur

18-CONTEXT.md's D-05 notes that one of four `ctest` repro runs during discussion hit a flaky, non-reproducing `processing_dispatch_test` failure (`Failed to open file (Windows): The system cannot find the file specified`), explicitly ruled out of scope by the user (a CWD-relative fixture-path difference between direct `.exe` invocation and `ctest`, unrelated to `VulkanInitMutex`). **This session's own fresh three-test ctest run above did not reproduce that flake** — `processing_dispatch_test` passed cleanly (`12/12`, `18.81 sec`). Whether or not it recurs, D-05 remains explicitly out of scope for this phase per the locked user decision; this note records only this run's own observed outcome, not a claim that the flake is resolved.

## Closure Verdict

**BUILD-01 is closed.** The evidence is two-part, both pieces cited directly rather than merely asserted:

1. **The pre-existing fix (`528a92a`, "Fix hang on OSX", 2026-08-06)** is confirmed a real ancestor of the current `SGProcessingManager` submodule HEAD via this session's own fresh `git merge-base --is-ancestor` check (exit `0`), and its restructuring of `CapabilityValidator::BuildSnapshot()` to call `ensureVulkanDevice()` outside `VulkanInitMutex()`'s lock is confirmed still present and unmodified in the current source.
2. **A new, persistent regression test** (`VulkanConcurrentInitTest.CreateSucceedsWithRealVulkanDevicePresent`) now exists in `vulkan_init_concurrency_test.cpp`, pinning the exact D-03 scenario (`ProcessingManager::Create()` with a real Vulkan device present must return without hanging or throwing), backed by a fail-fast CMake `TIMEOUT` property so a future regression of this fix produces a bounded, reported ctest `Timeout` failure instead of hanging the suite indefinitely.

This session's fresh three-test ctest gate (`processing_datatypes_test`, `processing_dispatch_test`, `vulkan_init_concurrency_test` — including the new regression case) passed 100% clean against a real NVIDIA GeForce RTX 4070 Ti SUPER device. `VulkanInitMutex()`'s locking model/type, `CapabilityValidator::BuildSnapshot()`, and `RenderProcessor::InitializeContext()` were not modified by this phase (per D-03/D-04/ROADMAP SC4) — only additive test coverage and a CMake timeout property were added. No downstream consumer needs to treat this as a new fix; it is proof that an already-landed fix is real, current, and now has re-runnable regression coverage that did not previously exist.
