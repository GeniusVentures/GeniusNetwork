---
status: complete
phase: 01-vulkan-foundation-dispatch-plumbing
source: 01-01-SUMMARY.md, 01-02-SUMMARY.md, 01-03-SUMMARY.md, 01-04-SUMMARY.md, 01-05-SUMMARY.md, 01-06-SUMMARY.md
started: 2026-07-29T22:33:34Z
updated: 2026-07-29T22:50:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Thirdparty Build + vk-bootstrap Compiles Cleanly on Windows MSVC
expected: CMake configure + build for the thirdparty tree compiles vk-bootstrap successfully. No MSVC compilation errors. vk-bootstrap finds vendored Vulkan-Headers and produces a linkable static library.
result: pass

### 2. No WSI / Surface / Swapchain Symbols in Render Path
expected: grep for VkSurfaceKHR, VkSwapchainKHR, VK_KHR_surface in all RenderProcessor .hpp/.cpp files returns zero matches — the headless Vulkan context has no window-system integration.
result: pass

### 3. Shared VulkanInitMutex Guards All 3 MNN Vulkan-Init Call Sites + RenderProcessor
expected: MNN_Image, MNN_String, MNN_Volume, and RenderProcessor all acquire sgns::sgprocessing::VulkanInitMutex() before any Vulkan init call. The old file-scoped mnn_vulkan_mutex no longer exists anywhere.
result: pass

### 4. ParseBlockSize() Does Not Crash on Model-Less (Render/Compute) Passes
expected: A pass definition with no `model` field (render or compute) goes through ParseBlockSize() without calling .value() on the empty optional. It contributes 0 to block_total_len instead of crashing.
result: pass

### 5. CheckProcessValidity() Requires Shader Config for RENDER Passes
expected: A render pass definition missing a shader config field is rejected by CheckProcessValidity() with PROCESS_INFO_MISSING error, mirroring how INFERENCE passes require a model.
result: pass

### 6. RENDER Pass Dispatches Through Separate PassType-Keyed Dispatch Map
expected: ProcessingManager::Process() routes PassType::RENDER through m_passFactories (PassType-keyed), not through m_processorFactories (DataType-keyed). RegisterPassProcessorFactory(PassType::RENDER, ...) is called in Init(). No static_cast mixing the two maps.
result: pass

### 7. Physical Device Selection Uses Deterministic Scoring, Not "Index 0"
expected: IsAcceptable() hard-rejects VK_PHYSICAL_DEVICE_TYPE_CPU and VK_PHYSICAL_DEVICE_TYPE_OTHER. Scoring ranks discrete (2) above integrated (1), tie-broken by LargestDeviceLocalHeap(). Same hardware always produces the same selected device.
result: pass

### 8. Concurrent Vulkan Init Stress Test (25 Iterations, 3 Threads)
expected: Test file vulkan_init_concurrency_test.cpp exercises MNN_String, MNN_Volume, and RenderProcessor Vulkan init concurrently across 25 iterations with a promise-based release gate. All threads serialize through the shared VulkanInitMutex().
result: pass

## Summary

total: 8
passed: 8
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

- truth: "CMake configure + build for the thirdparty tree compiles vk-bootstrap successfully with vendored Vulkan-Headers"
  status: resolved
  reason: "User reported: vk-bootstrap cmake in CommonTargets strikes me as incorrect, it also doesn't compile. VkBootstrapDispatch.h error C3646: 'fp_vkGetLatencyTimingsLegacyNV': unknown override specifier — plus additional C2059/C2238 errors."
  severity: blocker
  test: 1
  root_cause: "Two bugs: (1) vk-bootstrap v1.4.357 requires Vulkan 1.4 headers (PFN_vkGetLatencyTimingsLegacyNV etc.), but vendored Vulkan-Headers was v1.3.302 — bumped to v1.4.357. (2) VulkanHeaders_DIR:PATH=<INSTALL_DIR>/share/cmake/VulkanHeaders used the ExternalProject <INSTALL_DIR> placeholder which resolves to vk-bootstrap's own install prefix, not the Vulkan-Headers install location at ${CMAKE_CURRENT_BINARY_DIR}/Vulkan-Loader/share/cmake/VulkanHeaders."
  artifacts:
    - path: "thirdparty/Vulkan-Headers"
      issue: "Pinned at v1.3.302, needs v1.4.357"
    - path: "thirdparty/Vulkan-Loader"
      issue: "Bumped to v1.4.357 for header consistency"
    - path: "thirdparty/build/CommonTargets.cmake"
      issue: "<INSTALL_DIR>/share/cmake/VulkanHeaders did not resolve to the actual Vulkan-Headers install location"
  missing:
    - "Bump Vulkan-Headers to v1.4.357 ✓ (committed: thirdparty ee07ede)"
    - "Bump Vulkan-Loader to v1.4.357 ✓ (committed: thirdparty ee07ede)"
    - "Fix VulkanHeaders_DIR to use explicit path ✓ (committed: thirdparty 91d61d9)"
    - "Clean stale build artifacts ✓"
