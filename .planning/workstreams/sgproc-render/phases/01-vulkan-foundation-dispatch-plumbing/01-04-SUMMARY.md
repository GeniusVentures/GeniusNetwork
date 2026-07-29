---
phase: 01-vulkan-foundation-dispatch-plumbing
plan: 04
subsystem: infra
tags: [vulkan, render-processor, vk-bootstrap, context-creation, device-selection]

# Dependency graph
requires: ["01-01", "01-03"]
provides:
  - "sgns::sgprocessing::RenderProcessor — new ProcessingProcessor subclass"
  - "RenderProcessor::InitializeContext() — lazy headless Vulkan context creation via vk-bootstrap"
  - "IsAcceptable / LargestDeviceLocalHeap — deterministic device-selection scoring"
  - "Wired into SGProcessors CMake target, linking vk-bootstrap::vk-bootstrap"
affects: [01-05-dispatch-plumbing, 01-06-concurrent-stress-test]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Double-checked lazy init: fast-path m_contextInitialized check outside lock, re-check inside VulkanInitMutex() guard"
    - "vkb::PhysicalDeviceSelector::select_devices() + custom sort/filter replaces vk-bootstrap's default select() + allow_any_gpu_device_type fallback"
    - "All Vulkan handle ownership follows vk-bootstrap's destroy_* API for cleanup on init failure, not raw vkDestroy*"

key-files:
  created:
    - SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp
  modified:
    - SuperGenius/SGProcessingManager/src/processors/CMakeLists.txt

key-decisions:
  - "Used vkb's PhysicalDevice struct (properties/memory_properties already populated) instead of calling vkGetPhysicalDeviceProperties/MemoryProperties directly"
  - "select_devices() with custom sorting, not select() — avoids vk-bootstrap's allow_any_gpu_device_type default that conflicts with D-03"
  - "VkSurfaceKHR/VkSwapchainKHR absent from all RenderProcessor code — confirmed via zero-WSI grep"

patterns-established:
  - "RenderProcessor is the first non-MNN ProcessingProcessor in this codebase — demonstrates the interface can be implemented without any MNN dependency"

requirements-completed: [CTX-01, CTX-03]

coverage:
  - id: D1
    description: "RenderProcessor header exists, inherits ProcessingProcessor, no WSI symbols"
    requirement: "CTX-01"
    verification:
      - kind: unit
        ref: "grep -c 'class RenderProcessor' processing_processor_render.hpp == 1; grep -c 'VkSurfaceKHR|VkSwapchainKHR' == 0"
        status: pass
    human_judgment: false
  - id: D2
    description: "InitializeContext() acquires VulkanInitMutex() before vk-bootstrap calls"
    requirement: "CTX-02"
    verification:
      - kind: unit
        ref: "grep -c 'VulkanInitMutex' processing_processor_render.cpp == 1 inside InitializeContext()"
        status: pass
    human_judgment: false
  - id: D3
    description: "Device selection rejects CPU/software types, uses discrete > integrated ranking, VRAM-heap tie-break"
    requirement: "CTX-03"
    verification:
      - kind: unit
        ref: "IsAcceptable() hard-rejects VK_PHYSICAL_DEVICE_TYPE_CPU/VK_PHYSICAL_DEVICE_TYPE_OTHER; sort uses deviceType rank (2/1) + LargestDeviceLocalHeap tie-break"
        status: pass
    human_judgment: false
  - id: D4
    description: "RenderProcessor wired into SGProcessors CMake target"
    requirement: "CTX-01"
    verification:
      - kind: unit
        ref: "grep -c 'processing_processor_render.cpp' src/processors/CMakeLists.txt == 1; grep -c 'vk-bootstrap::vk-bootstrap' == 1"
        status: pass
    human_judgment: false
  - id: D5
    description: "Zero WSI/surface/swapchain symbols in any RenderProcessor file"
    requirement: "CTX-01"
    verification:
      - kind: unit
        ref: "grep -c 'VK_KHR_surface|VkSurfaceKHR|VkSwapchainKHR' .hpp + .cpp both 0"
        status: pass
    human_judgment: false

duration: 12min
completed: 2026-07-29
status: complete
---

# Phase 01 Plan 04: RenderProcessor Headless Vulkan Context Summary

**Implemented `sgns::sgprocessing::RenderProcessor`, a new `ProcessingProcessor` subclass that lazily creates a headless Vulkan context via vk-bootstrap, applies deterministic device-selection scoring, and serializes its init through the shared `VulkanInitMutex()`. Wired into the SGProcessors CMake target.**

## Performance

- **Duration:** 12 min
- **Started:** 2026-07-29
- **Completed:** 2026-07-29
- **Tasks:** 3
- **Files modified:** 3 (2 created, 1 modified)

## Accomplishments

- Created `include/processors/processing_processor_render.hpp` — `RenderProcessor` publicly inherits `ProcessingProcessor`, overrides `StartProcessing`, and holds private `VkInstance`/`VkPhysicalDevice`/`VkDevice`/`VkQueue` members with zero WSI/surface handles
- Implemented `src/processors/processing_processor_render.cpp` with lazy headless context creation (`InitializeContext()`) using vk-bootstrap's `InstanceBuilder` (zero WSI extensions, `request_validation_layers(false)`), `PhysicalDeviceSelector::select_devices()` (not the default `select()`), and `DeviceBuilder`
- Device selection implemented per D-02/D-03: `IsAcceptable()` hard-rejects `VK_PHYSICAL_DEVICE_TYPE_CPU`/`VK_PHYSICAL_DEVICE_TYPE_OTHER`; scoring ranks discrete (2) above integrated (1), tie-broken by `LargestDeviceLocalHeap()` summing `VK_MEMORY_HEAP_DEVICE_LOCAL_BIT`-flagged heaps
- All Vulkan init serialized through `sgns::sgprocessing::VulkanInitMutex()` (plan 01-01) with double-checked lazy init pattern
- Wired into `src/processors/CMakeLists.txt`: source list, header list, and `target_link_libraries(SGProcessors PUBLIC ... vk-bootstrap::vk-bootstrap)`

## Task Commits

1. **Task 1: Create RenderProcessor header** — `9812f86` (SGProcessingManager, `dev_rendering`, incl. Tasks 2+3 in same commit)
2. **Task 2: Implement lazy headless context creation** — (combined with Task 1)
3. **Task 3: Wire into SGProcessors build target** — (combined with Task 1)

**Submodule pointer-bump chain:**
- SuperGenius (branch `dev_childwallet`): `d723c8b9` — `chore(01-04): bump SGProcessingManager submodule pointer`
- GeniusNetwork root (branch `dev_persisprocresults`): `56be48e` — `chore(01-04): bump SuperGenius submodule pointer`

## Files Created/Modified

- `SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp` — New RenderProcessor class: 3 public members (ctor, dtor, StartProcessing), 4 private Vulkan handle members, 1 private `InitializeContext()` helper, 2 static scoring helpers
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp` — Full implementation: `InitializeContext()` (lazy, double-checked, mutex-guarded, vk-bootstrap instance → device → queue with deterministic scoring), `StartProcessing()` (calls InitializeContext, returns placeholder ProcessingResult)
- `SuperGenius/SGProcessingManager/src/processors/CMakeLists.txt` — Added source file, header file, and `vk-bootstrap::vk-bootstrap` link dependency

## Decisions Made

- **Double-checked locking pattern:** Fast-path `m_contextInitialized` check outside lock, re-check inside `VulkanInitMutex()` guard — correct for the current per-call processor-instantiation pattern and cheap enough to not matter if a future codepath changes the instantiation pattern
- **vkb::PhysicalDevice struct properties used directly:** vk-bootstrap's `select_devices()` already populates `properties` and `memory_properties` on the returned struct — no need for additional `vkGetPhysicalDevice*` calls for scoring. `LargestDeviceLocalHeap()` still uses raw `vkGetPhysicalDeviceMemoryProperties` for the tie-break (called on the embedded `VkPhysicalDevice` handle), since the function signature was designed as a standalone helper.

## Deviations from Plan

None — plan executed as written.

## Issues Encountered

- This working copy does not have a full Vulkan-capable build environment configured — the code was verified structurally (correct includes, correct vk-bootstrap API usage based on reading the live vendored headers, zero WSI symbols per grep) but no compile/build/run verification was possible in this session. The code is structurally sound: all vk-bootstrap API calls match the live header shapes (`InstanceBuilder::build()` returns `Result<Instance>`, `PhysicalDeviceSelector::select_devices()` returns `Result<std::vector<PhysicalDevice>>`, `PhysicalDevice::properties.deviceType` and `physical_device` are public members per VkBootstrap.h lines 501-508/570). Plan 01-06's concurrent-init stress test is the first code path that will runtime-exercise `RenderProcessor::InitializeContext()`.

## Next Phase Readiness

- Plan 01-05 (ProcessingManager dispatch plumbing) can now:
  - Register `RenderProcessor` in `ProcessingManager::Init()` via `RegisterPassProcessorFactory(PassType::RENDER, ...)`
  - Route RENDER passes through the new `m_passFactories` map to `RenderProcessor::StartProcessing()`
- Plan 01-06 (concurrent-init stress test) can:
  - Construct `RenderProcessor` directly and call `StartProcessing()` to exercise the lazy Vulkan init path concurrently with MNN_String/MNN_Volume

---

*Phase: 01-vulkan-foundation-dispatch-plumbing*
*Completed: 2026-07-29*

## Self-Check: PASSED

- FOUND: `SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp` — class RenderProcessor inherits ProcessingProcessor
- FOUND: `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp` — InitializeContext with VulkanInitMutex guard + vk-bootstrap + deterministic selection
- FOUND: `src/processors/CMakeLists.txt` — processing_processor_render.cpp + .hpp entries + vk-bootstrap::vk-bootstrap link
- FOUND: Zero VkSurfaceKHR/VkSwapchainKHR/VK_KHR_surface symbols in both .hpp and .cpp
