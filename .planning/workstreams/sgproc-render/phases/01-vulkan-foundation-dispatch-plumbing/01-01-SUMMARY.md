---
phase: 01-vulkan-foundation-dispatch-plumbing
plan: 01
subsystem: infra
tags: [vulkan, mnn, concurrency, mutex, cxx]

# Dependency graph
requires: []
provides:
  - "sgns::sgprocessing::VulkanInitMutex() — shared, process-wide, header-declared Vulkan-init synchronization primitive"
  - "MNN_Image migrated off its old file-scoped mnn_vulkan_mutex onto the shared guard"
  - "MNN_String and MNN_Volume newly guarded around their previously-unsynchronized createSession(MNN_FORWARD_VULKAN) calls"
affects: [01-04-render-processor-context-creation, 01-06-concurrent-init-stress-test]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Magic-static (function-local static std::mutex, C++11+) shared synchronization primitive, header-declared in include/processingbase/vulkan_init_guard.hpp"
    - "Hoist a raw MNN::Session* declaration outside a lock_guard-scoped block so an existing post-call failure check (if (!session)) is unaffected by the new lock scope"

key-files:
  created:
    - SuperGenius/SGProcessingManager/include/processingbase/vulkan_init_guard.hpp
  modified:
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_image.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_string.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_volume.cpp

key-decisions:
  - "Used a magic-static std::mutex& accessor (not std::call_once/std::once_flag) since the guard must be acquired repeatedly, once per Vulkan-init call, for the process's lifetime"
  - "In MNN_String/MNN_Volume, only createSession() itself is placed under the lock; MNN::ScheduleConfig construction and MNN::Interpreter::createFromBuffer are left outside the lock since only createSession triggers MNN's internal Vulkan device init"
  - "MNN::Session* declared outside the new lock-guarded block (createSession's actual return type is a raw MNN::Session* owned/managed by the interpreter) so the existing if (!session) failure check continues to operate on the same variable unchanged"

patterns-established:
  - "Pattern 3 from 01-RESEARCH.md (shared VulkanInitGuard, magic-static, not call_once) is now implemented in code, ready for reuse by plan 01-04's RenderProcessor lazy-init path"

requirements-completed: [CTX-02]

coverage:
  - id: D1
    description: "New shared header include/processingbase/vulkan_init_guard.hpp exposing sgns::sgprocessing::VulkanInitMutex(), a magic-static mutex accessor with zero call_once/once_flag usage"
    requirement: "CTX-02"
    verification:
      - kind: unit
        ref: "grep -c 'static std::mutex vulkan_init_mutex' vulkan_init_guard.hpp == 1; grep -c 'call_once' vulkan_init_guard.hpp == 0"
        status: pass
    human_judgment: false
  - id: D2
    description: "MNN_Image::Process() migrated from its old file-scoped mnn_vulkan_mutex to the shared VulkanInitMutex(), preserving the original lock span (whole function body)"
    requirement: "CTX-02"
    verification:
      - kind: unit
        ref: "grep -c 'mnn_vulkan_mutex' processing_processor_mnn_image.cpp == 0; grep -c 'VulkanInitMutex' processing_processor_mnn_image.cpp >= 1"
        status: pass
    human_judgment: false
  - id: D3
    description: "MNN_String and MNN_Volume's previously-unguarded createSession(MNN_FORWARD_VULKAN) call sites now acquire the shared VulkanInitMutex() before calling createSession, closing the pre-existing zero-synchronization gap"
    requirement: "CTX-02"
    verification:
      - kind: unit
        ref: "grep -c 'VulkanInitMutex' processing_processor_mnn_string.cpp processing_processor_mnn_volume.cpp -> 1 each"
        status: pass
    human_judgment: true
    rationale: "Grep confirms the guard is present and wraps the createSession call textually, but this repo has no local MNN header/build environment available to compile-verify the change (thirdparty MNN submodule not checked out in this working copy) — a build/compile pass against the actual SGProcessors CMake target is recommended before relying on this in production, and is exactly what plan 01-06's concurrent-init stress test is designed to prove at runtime."

# Metrics
duration: 12min
completed: 2026-07-29
status: complete
---

# Phase 01 Plan 01: Shared Vulkan Init Guard Summary

**Replaced MNN_Image's file-scoped `mnn_vulkan_mutex` with a shared, header-declared `sgns::sgprocessing::VulkanInitMutex()` magic-static mutex, and newly guarded MNN_String's and MNN_Volume's previously-unsynchronized `createSession(MNN_FORWARD_VULKAN)` call sites with the same primitive.**

## Performance

- **Duration:** 12 min
- **Started:** 2026-07-29T19:41:10Z
- **Completed:** 2026-07-29T19:49:14Z
- **Tasks:** 3
- **Files modified:** 4 (1 created, 3 modified)

## Accomplishments
- New `include/processingbase/vulkan_init_guard.hpp` header exposing `sgns::sgprocessing::VulkanInitMutex()`, a process-wide magic-static mutex accessor — the single shared synchronization primitive CTX-02/D-04 requires
- `MNN_Image::Process()` migrated off its old inline `static std::mutex mnn_vulkan_mutex` onto the shared guard, at the exact same point in the function (top of `Process()`), preserving the original lock span across the entire function body
- `MNN_String::Process()` and `MNN_Volume::Process()` — both previously had **zero synchronization** around `createSession(MNN_FORWARD_VULKAN)` — now acquire the same shared mutex immediately before that call, closing a real pre-existing race condition in production code

## Task Commits

Each task was committed atomically, inside the `SuperGenius/SGProcessingManager` nested submodule (branch `dev_rendering`):

1. **Task 1: Create the shared VulkanInitGuard header** - `9c52433` (feat)
2. **Task 2: Migrate MNN_Image's inline mutex to the shared guard** - `6974444` (refactor)
3. **Task 3: Add the shared guard to MNN_String's and MNN_Volume's unguarded createSession calls** - `8880990` (fix)

**Submodule pointer-bump chain** (per repo topology — no independent per-task diffs, these bump gitlinks only):
- SuperGenius (branch `dev_childwallet`): `5e4e799d` — `chore(01-01): bump SGProcessingManager submodule pointer`
- GeniusNetwork root (branch `dev_persisprocresults`): `b66d266` — `chore(01-01): bump SuperGenius submodule pointer`

**Plan metadata:** (this SUMMARY.md + STATE.md/ROADMAP.md commit, see below)

## Files Created/Modified
- `SuperGenius/SGProcessingManager/include/processingbase/vulkan_init_guard.hpp` - New shared header; `sgns::sgprocessing::VulkanInitMutex()` magic-static mutex accessor
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_image.cpp` - Removed old file-scoped `mnn_vulkan_mutex`, now acquires the shared guard at the same point/span
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_string.cpp` - Added shared-guard include and lock around the previously-unguarded `createSession` call
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_volume.cpp` - Added shared-guard include and lock around the previously-unguarded `createSession` call

## Decisions Made
- Chose a magic-static `std::mutex&` accessor over `std::call_once`/`std::once_flag` per the plan's explicit instruction — the guard must serialize *every* Vulkan-init call across the process's lifetime, not run a callable exactly once
- In `MNN_String`/`MNN_Volume`, only wrapped the `createSession(config)` call itself in the lock, not the preceding `MNN::ScheduleConfig` construction or `MNN::Interpreter::createFromBuffer` — matches the plan's guidance that only `createSession` triggers MNN's internal Vulkan device init
- Declared `MNN::Session *session = nullptr;` (raw pointer, matching MNN's actual `createSession` return type) outside the new lock-scoped block, assigning inside the block — keeps the existing `if (!session)` failure check working unchanged against the now-outer-scoped variable

## Deviations from Plan

None - plan executed exactly as written. One minor self-correction during Task 1: the header's first draft included an inline comment mentioning "std::call_once" (explaining why it was *not* used), which tripped the plan's own automated `grep -c "call_once"` acceptance check (substring match, not symbol-aware). Reworded the comment to avoid the substring while preserving the same explanation — no functional change, verified `grep -c "call_once"` now returns 0.

## Issues Encountered
- This working copy does not have the `MNN` thirdparty headers/submodule checked out locally, so the `MNN::Session*` return-type assumption for `createSession()` (used in Task 3's hoisted declaration) could not be compile-verified in this session. This matches standard MNN API knowledge (`Interpreter::createSession` returns a raw `MNN::Session*` owned by the interpreter) and is textually consistent with the surrounding code, but a real build against the `SGProcessors` CMake target is recommended before this is fully trusted — flagged in this SUMMARY's `coverage` block (D3, `human_judgment: true`) rather than silently claimed as build-verified.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- The shared `VulkanInitMutex()` primitive is now in place and consumed by all 3 existing MNN Vulkan-init call sites — plan 01-04's `RenderProcessor` lazy-init path can acquire the same `sgns::sgprocessing::VulkanInitMutex()` from this header without introducing a second, uncoordinated lock
- Plan 01-06's concurrent-init stress test is the mechanism that will runtime-verify this plan's synchronization guarantee end-to-end (this plan only delivers the primitive and its 3 existing call-site migrations, per its own success criteria)
- Recommend a real compile/build pass against the `SGProcessors` target at the next opportunity a full MNN-vendored environment is available, to confirm the `MNN::Session*` type assumption and overall compile-cleanliness (verification bullet 4 in the plan's own `<verification>` section: "SGProcessors target still builds cleanly")

---
*Phase: 01-vulkan-foundation-dispatch-plumbing*
*Completed: 2026-07-29*
