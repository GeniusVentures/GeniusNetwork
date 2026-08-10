---
created: 2026-08-10T21:00:00.000Z
title: Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path
area: testing
files:
  - SuperGenius/SGProcessingManager/src/capability/capability_validator.cpp:211-235
  - SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp:419-448
  - SuperGenius/SGProcessingManager/src/processors/vulkan_gpu_probe.cpp:10-66
  - SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp:39-47 (InitializeContext, unmodified by Phase 10)
  - SuperGenius/test/src/processing_datatypes/processing_datatypes_test.cpp
  - SuperGenius/test/src/processing_vulkan_concurrency/vulkan_init_concurrency_test.cpp
---

## Problem

Discovered during Phase 10 (capture-harness-diff-tool-quantization-stub)'s
post-execution regression gate, running the CTest suite on a machine with a
real Vulkan device present (dev host, 2026-08-10):

- Every `ProcessingDatatypesTest` subtest (31/31) fails with
  `C++ exception with description "resource deadlock would occur"` — thrown
  almost instantly (0-2ms), consistent with a non-recursive `std::mutex`
  being locked twice by the same thread before any real Vulkan work runs.
- `ProcessingDispatchTest` fails the same way.
- `vulkan_init_concurrency_test` (`VulkanConcurrentInitTest.RepeatedConcurrentInitNoRaceOrCrash`)
  aborts with exit code 3 (no gtest failure message — looks like an
  unhandled exception/terminate, not a clean assertion).

All three sit on the same code path: `ProcessingManager::Create()` →
`CapabilityValidator::BuildSnapshot()` → its `ensureVulkanDevice` lambda →
`RenderProcessor::InitializeContext()`, plus the separate
`HasUsableVulkanDevice()` probe in `vulkan_gpu_probe.cpp` — all of which
lock the same `VulkanInitMutex()` (`vulkan_init_guard.hpp`). One of these
call paths is very likely re-entering the mutex on the same thread.
`capability_validator.cpp:220-226` has an explicit comment describing and
avoiding exactly this self-deadlock risk for one specific call
(`ensureVulkanDevice()` is called *outside* the lock precisely because
"holding the mutex here ... would cause a self-deadlock") — so the fix is
probably close by, either a second call path that doesn't yet have the same
care, or a case the existing double-check-locking comment didn't anticipate
(e.g. `HasUsableVulkanDevice()` being reachable from inside an
already-locked scope in some code path not yet identified).

**Confirmed NOT caused by Phase 10:** `git diff --stat` between the commit
before Phase 10 started and Phase 10's final commit in the
`SGProcessingManager` submodule touches none of `capability_validator.cpp`,
`ProcessingManager.cpp`, `vulkan_gpu_probe.cpp`, or
`RenderProcessor::InitializeContext()` (Phase 10 only added small,
surgical insertions inside `StartProcessing()`/quantize call sites in the
14 processor files — confirmed via `git show <commit>` per file). The
deadlock reproduces on a single isolated `--gtest_filter` run of
`FloatValidationTest`, which never reaches any Phase-10-touched code
(it fails during `ProcessingManager::Create()`, before any processor's
`StartProcessing()` runs). This is pre-existing, just never previously
exercised via `ctest` in this exact configuration — `SGProcessingManager/test/`
was entirely unwired from the CMake build until Phase 10 Plan 10-06 fixed a
separate `enable_testing()` ordering bug, and `ctest -N` had never
previously reported real coverage for this subsystem.

**Also newly discovered while investigating:** `ArtifactSerializerTest`,
`processing_conformance_hashing_test`, and `processing_conformance_schema_test`
were CMake-configured but never compiled before (their `.exe` files didn't
exist on disk) — not a regression, just never built; building them now and
they pass cleanly. `processing_conformance_hashing_test` in particular
(the single most relevant regression check for Phase 10's changes) passes.

## Solution

TBD. Likely needs a careful audit of every call site that can reach
`VulkanInitMutex()` (grep `VulkanInitMutex()` across
`SGProcessingManager/src/`) to find the one that's reachable from inside
another lock's scope on the same thread. Reproduce with:

```
cd SuperGenius/build/Windows/Debug/test_bin/Debug
./processing_datatypes_test.exe --gtest_filter=ProcessingDatatypesTest.FloatValidationTest
```

(fails in ~2ms with "resource deadlock would occur" on a host with a real
Vulkan device present). Once fixed, re-run the full `ctest` suite as a
proper regression gate — it hasn't had a clean full pass recorded in
STATE.md for several phases (Blockers/Concerns already notes "Build
verification pending on prior phases — C++ compilation not retested").
