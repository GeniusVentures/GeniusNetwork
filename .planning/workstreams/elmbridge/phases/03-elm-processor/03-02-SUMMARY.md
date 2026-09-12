---
phase: 03-elm-processor
plan: 02
subsystem: sgprocmanager-processors
tags: [llm, lock-discipline, fail-closed, temp-dir-elimination]
provides: [sgns::sgprocessing::LlmLoadMutex, fail-closed MNN_Llm shim]
affects: [MNN_Llm processor, vulkan_init_guard.hpp]
requires: [03-01]
tech-stack:
  added: []
  patterns: [two-lock discipline (VulkanInitMutex=createLLM, LlmLoadMutex=load), fail-closed shim retirement]
key-files:
  created: []
  modified:
    - SuperGenius/SGProcessingManager/include/processingbase/vulkan_init_guard.hpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_llm.cpp
    - SuperGenius/SGProcessingManager/include/processors/processing_processor_mnn_llm.hpp
key-decisions:
  - "D-01/D-03: LlmLoadMutex() inline free function beside VulkanInitMutex() in sgns::sgprocessing; two-lock discipline documented in header comment"
  - "D-04: MNN_Llm is now a fail-closed shim — pre-cancel + empty-model legs preserved byte-for-byte, non-empty model returns structured RESOURCE_RESOLUTION retirement message"
  - "MaterializeModelToTempDir and LoadModel deleted — zero temp-dir materializers in SGProcessingManager (grep: only the shim's own retirement comment references the name)"
requirements-completed: [GEN-03]
coverage:
  - deliverable: "LlmLoadMutex() exists header-only beside VulkanInitMutex() with two-lock discipline documented"
    verification:
      - kind: command
        ref: "Select-String vulkan_init_guard.hpp 'LlmLoadMutex' matches; SGProcessors.lib built clean"
        status: pass
    human_judgment: false
  - deliverable: "Zero temp-dir materializers; shim is lock-free with no MNN includes"
    verification:
      - kind: command
        ref: "grep MaterializeModelToTempDir src/** → 1 hit (shim comment only); VulkanInitMutex|LlmLoadMutex|llm.hpp in shim → comment lines only"
        status: pass
    human_judgment: false
  - deliverable: "Both legacy mnn_llm_test legs green"
    verification:
      - kind: tests
        ref: "mnn_llm_test.exe EmptyModelFileFailsClosedWithResourceResolution + PreCancelledTokenFailsClosedWithCancelled (0 ms each, PASSED 2 tests)"
        status: pass
    human_judgment: false
  - deliverable: "D-02 concurrency legs (two loads serialize; non-LLM not stalled)"
    human_judgment: true
    rationale: "Requires real-model fixture + full processor — executed by plan 03-04 lock legs"
duration: 25 min
completed: 2026-09-11T20:45:00-04:00
---

# Phase 3 Plan 2: LLM Lock Discipline + MNN_Llm Shim Summary

Split the single LLM lock into the D-01/D-03 two-lock discipline and retired the old MNN_Llm processor to a fail-closed shim with the temp-dir materializer class eliminated — 254 lines removed, 88 added, both legacy test legs green.

## Accomplishments

- **LlmLoadMutex() (Task 1)** — inline free function in `vulkan_init_guard.hpp` beside `VulkanInitMutex()`, identical magic-static idiom; header comment now documents the two-lock discipline (VulkanInitMutex = createLLM/GPU-init window ONLY; LlmLoadMutex = Llm::load() serialization, render/MNN never wait on a weight load; two concurrent ELM loads serialize conservatively) with the same call-site-convention/re-verify density as the original.
- **Fail-closed shim (Task 2)** — `processing_processor_mnn_llm.cpp` rewritten to a 64-line shim: pre-cancel check preserved byte-for-byte as the first statement, empty-model check preserved byte-for-byte, and any non-empty model buffer returns the structured retirement message ("MNN_Llm processor retired (elmbridge Phase 3 D-04)..."). `MaterializeModelToTempDir`, `LoadModel`, and `ResolveMaxNewTokens` deleted from both .cpp and .hpp; unused includes removed (chrono/filesystem/fstream/mutex/llm.hpp/vulkan_init_guard.hpp/sha256/sstream all gone). Doxygen headers on both files document the retirement.
- **Factory registration untouched** (per plan — plan 03-03 Task 3 repoints it to ElmProcessor).
- **Verification** — SGProcessors built clean; `mnn_llm_test.exe`: 2/2 PASSED at 0 ms each (proves no lock/load attempt on the short-circuit legs); grep gates: `MaterializeModelToTempDir` 0 functional hits, shim contains no lock acquisition and no MNN include.

## Commits

| Repo | SHA | Message |
|------|-----|---------|
| SuperGenius/SGProcessingManager | `07223ec` | feat(processors): retire MNN_Llm to fail-closed shim, add LlmLoadMutex (elmbridge 03-02, D-01/D-03/D-04) — 3 files, +88/−254 |

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Next Phase Readiness

Wave 2 unblocked: the ELM processor TU (03-03) compiles against the final lock discipline from its first commit; SC-5's structural half (non-LLM processors never wait on LLM loads) is now in place.
