# Phase 06: Capability & Validation Foundation - Research

**Researched:** 2026-08-04
**Domain:** Vulkan/MNN capability pre-validation + Vulkan validation layer best-effort toggle
**Confidence:** HIGH

## Summary

This phase introduces two independent sub-streams: (1) **CAP** — a `CapabilityValidator` class that checks whether the node CAN execute a job before claiming it, returning structured `UnmetRequirement` reasons; and (2) **VVAL** — a CMake-controlled best-effort toggle for Vulkan validation layers on `RenderProcessor`'s `VkInstance` only.

The `CapabilityValidator` is internally constructed by `ProcessingManager` at startup (D-04), queries Vulkan device properties + MNN backend registry + registered executors once and caches the result (D-09), and provides an async `CanExecute()` callback (D-03) that runs after `CheckProcessValidity()` (D-17/D-18). The validation-layer toggle uses vk-bootstrap's `request_validation_layers()` (best-effort, D-20), gated by a CMake `option(ENABLE_VULKAN_VALIDATION ...)` that defaults ON in Debug, OFF in Release (D-24).

**Primary recommendation:** Follow the existing `ProcessingManager` factory-map pattern for executor registration metadata, use `sgns::sgprocmanagersha::sha256()` for the capability-snapshot hash (D-08), and reuse the existing `VulkanInitMutex` + `VkPhysicalDevice` for capability queries (D-10). No new third-party dependencies are needed — everything is implementable with already-vendored libraries.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Vulkan device limit queries | SGProcessingManager (C++) | — | Queries the same `VkPhysicalDevice` `RenderProcessor` uses, under `VulkanInitMutex` |
| MNN backend capability discovery | SGProcessingManager (C++) | — | Registry-based: each registered MNN processor declares supported formats/quantizations at registration time |
| Executor identity hashing | SGProcessingManager (C++) | — | Pure computation; uses existing `sha256` utility, no I/O |
| GPU memory estimation | SGProcessingManager (C++) | — | Estimates from schema-declared dimensions/formats, checks against `VkPhysicalDeviceMemoryProperties` |
| Disk space check | SGProcessingManager (C++) | — | Platform-specific syscall; no existing abstraction in codebase |
| PassType validation | SGProcessingManager (C++) | — | Queries existing `m_passFactories` map |
| Validation layer toggle | CMake build system | SGProcessingManager (C++) | CMake `option()` gates `#ifdef` in `InitializeContext()` |
| Validation layer loading | Vulkan Loader (system) | vk-bootstrap | Layers loaded by name; Vulkan loader resolves path |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Vulkan (via vk-bootstrap) | 1.3+ (vendored) | Device property/limit/memory queries | Already vendored and wired; `RenderProcessor` uses same `VkPhysicalDevice` |
| vk-bootstrap | vendored (`thirdparty/vk-bootstrap/`) | `request_validation_layers()`, device enumeration | Already integrated in `RenderProcessor::InitializeContext()` [VERIFIED: thirdparty/vk-bootstrap/src/VkBootstrap.cpp:823] |
| `sgns::sgprocmanagersha::sha256` | existing | SHA-256 hashing for executor identity | Already used by all MNN processors + RenderProcessor [VERIFIED: SGProcessingManager/include/util/sha256.hpp:1-10] |
| `sgns::crypto::sha2_256` | existing (SuperGenius) | SHA-256 for capability snapshot | Available in `SuperGenius/src/crypto/hasher.hpp:20`; already linked by SGProcessingManager |
| Boost | ~1.85.0 (existing) | `boost::optional`, `boost::asio` for async callback | Already linked project-wide per `CommonBuildParameters.cmake:206` |
| MNN | vendored | Backend registry query | Already linked by all MNN processors [VERIFIED: 14 `MNN_FORWARD_VULKAN` call sites across processors] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `<sys/statvfs.h>` (POSIX) / `<windows.h>` `GetDiskFreeSpaceExW` | system | Disk space check (CAP-05/D-16) | Platform-specific; no existing abstraction in codebase [ASSUMED] |
| `<unordered_map>` (STL) | C++17 | Executor capability metadata registry | Follows existing `m_processorFactories`/`m_passFactories` pattern |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `sha256` (existing) | `sgns::crypto::blake2b_256` | SHA-256 is already the convention across all SGProcessingManager processors; blake2b would be inconsistent |
| `request_validation_layers()` (best-effort) | `enable_validation_layers()` (strict) | Strict mode blocks instance creation if layer not found — violates D-20's best-effort requirement |
| Manual VkPhysicalDevice query | vk-bootstrap `PhysicalDevice` wrapper | vk-bootstrap already provides `physical_device.physical_device` handle; hand-rolling would add unnecessary code |

**Installation:** No new packages needed. All dependencies are already vendored or system-provided.

**Version verification:** N/A — no new external packages introduced.

## Package Legitimacy Audit

> No new external packages are introduced by this phase. All dependencies (vk-bootstrap, MNN, Boost, Vulkan headers, OpenSSL/SHA-256) are already vendored in `thirdparty/` or system-provided.

## Architecture Patterns

### System Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                      ProcessingManager::Init()                       │
│                                                                      │
│  1. RegisterProcessorFactory()  ──► m_processorFactories             │
│  2. RegisterPassProcessorFactory() ──► m_passFactories               │
│  3. [NEW] CapabilityValidator::BuildSnapshot()  ──► cached snapshot  │
│     │                                                                │
│     ├── Vulkan: vkGetPhysicalDeviceProperties()  ──► VulkanLimits    │
│     ├── Vulkan: vkGetPhysicalDeviceMemoryProperties() ──► Heaps      │
│     ├── MNN:   Query registered executor metadata  ──► BackendInfo[] │
│     └── Hash:  sha256(all of above)               ──► identityHash   │
│                                                                      │
│  4. [IF ENABLE_VULKAN_VALIDATION]                                    │
│     RenderProcessor::InitializeContext() uses                         │
│     request_validation_layers(true)  (best-effort)                   │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│              Scheduler (SuperGenius processing node)                 │
│                                                                      │
│  Before claiming job:                                                │
│  ┌─────────────────────────────────────────────────────────────┐     │
│  │ CapabilityValidator::CanExecute(pass, callback)              │     │
│  │   │                                                          │     │
│  │   ├── Check PassType registered?  ──► UnmetRequirement       │     │
│  │   ├── Check Vulkan limits?        ──► UnmetRequirement[]     │     │
│  │   ├── Check MNN format/quant?     ──► UnmetRequirement[]     │     │
│  │   ├── Check GPU memory?           ──► UnmetRequirement[]     │     │
│  │   ├── Check disk space?           ──► UnmetRequirement[]     │     │
│  │   └── callback(CanExecuteResult)                             │     │
│  └─────────────────────────────────────────────────────────────┘     │
│                                                                      │
│  On success: claim job ──► Process() (trusts caller validated)       │
│  On failure: skip claim, log unmet requirements                      │
└──────────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure
```
SGProcessingManager/
├── include/
│   └── capability/
│       └── capability_validator.hpp      # CapabilityValidator class decl
├── src/
│   └── capability/
│       └── capability_validator.cpp      # Implementation
```

### Pattern 1: Factory-Map Registration with Metadata

**What:** Each registered executor also registers capability metadata (supported formats, quantizations, backend) at `ProcessingManager::Init()` time alongside the existing factory function.

**When to use:** CAP-03 (MNN format/quantization checks) and CAP-04 (PassType registration check).

**Example (from existing codebase):**
```cpp
// Existing pattern in ProcessingManager::Init() —
// ProcessingManager.cpp:1012-1013
RegisterPassProcessorFactory( PassType::RENDER,
    [] { return std::make_unique<sgprocessing::RenderProcessor>(); } );

// Extension for capability metadata:
struct ExecutorCapability {
    PassType passType;
    std::vector<std::string> supportedModelFormats;   // e.g. ".mnn", ".caffemodel"
    std::vector<std::string> supportedQuantizations;  // e.g. "FP32", "FP16", "INT8"
    std::string backend;                              // "VULKAN", "CPU"
};

// New alongside RegisterPassProcessorFactory:
void RegisterExecutorCapability(PassType type, ExecutorCapability caps) {
    m_executorCapabilities[type] = std::move(caps);
}
```

### Pattern 2: Async Callback (matching ProcessingManager conventions)

**What:** `CanExecute` uses an async callback pattern consistent with `ProcessingManager::Process()`'s use of `boost::asio::io_context`.

**When to use:** CAP-01/D-03 — `CanExecute` must be async.

**Example (derived from ProcessingManager::Process signature):**
```cpp
// Signature proposal matching existing async patterns:
// ProcessingManager.hpp:55-58 (existing Process signature)
// Process() uses boost::asio::io_context for async I/O internally;
// CanExecute similarly async.

struct CanExecuteResult {
    bool executable;
    std::string executorId;           // Only populated if executable=true
    std::vector<UnmetRequirement> unmet;  // Only populated if executable=false
};

using CanExecuteCallback = std::function<void(CanExecuteResult)>;

void CanExecute(const sgns::SgnsPass& pass,
                CanExecuteCallback callback);
```

### Pattern 3: Structured Error Following ProcessingResult Convention

**What:** `UnmetRequirement` follows the same per-category enum + message string pattern as `ProcessingError` (Phase 3, D-25/D-26).

**When to use:** CAP-02, CAP-03, CAP-04 — all unmet-requirement reporting.

**Example (derived from existing ProcessingError):**
```cpp
// Existing pattern — processing_processor.hpp:34-49
enum class ProcessingErrorStage {
    UNSPECIFIED = 0,
    CONTEXT_INIT_FAILED,
    // ...
};
struct ProcessingError {
    ProcessingErrorStage stage;
    std::string          message;
};

// New — follows same pattern:
enum class UnmetRequirementCategory {
    VULKAN = 0,
    MNN,
    PASS_TYPE,
    RESOURCE
};
struct UnmetRequirement {
    UnmetRequirementCategory category;
    std::string              detail;  // e.g. "maxImageDimension2D: need 16384, have 8192"
};
```

### Pattern 4: Startup Snapshot + Cache (D-09)

**What:** All capability data is queried once at `ProcessingManager::Init()` time (after processor registration) and cached for the process lifetime. No runtime refresh (D-12).

**When to use:** CAP-01, CAP-02, CAP-03, CAP-05 — all `CanExecute` checks read from the cached snapshot.

**Example:**
```cpp
// In CapabilityValidator.hpp
struct CapabilitySnapshot {
    VkPhysicalDeviceProperties      vulkanProps;
    VkPhysicalDeviceMemoryProperties memProps;
    std::vector<ExecutorCapability> executorCaps;
    uint64_t                        availableDiskBytes;
    std::vector<uint8_t>            identityHash;  // sha256 of above
};

// Built once in CapabilityValidator::BuildSnapshot(),
// called from ProcessingManager::Init() after all Register* calls.
```

### Anti-Patterns to Avoid
- **Calling VkPhysicalDevice queries without VulkanInitMutex:** The `VulkanInitMutex` guards ALL Vulkan init call sites. Capability queries on the same `VkPhysicalDevice` must also acquire it (D-10).
- **Creating a temporary VkInstance for capability queries:** D-10 requires reusing the existing `VkPhysicalDevice`. A temporary instance would add unnecessary resource overhead.
- **Hardcoding MNN capabilities:** D-11 requires registry-based discovery. Each executor declares its own capabilities at registration time; do not hardcode a list of "all MNN formats."

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SHA-256 hashing | Custom SHA-256 impl | `sgns::sgprocmanagersha::sha256()` (already in SGProcessingManager) or `sgns::crypto::sha2_256()` (SuperGenius) | Both already linked, tested, and used across the codebase |
| Vulkan device enumeration | Manual `vkEnumeratePhysicalDevices` + property queries | vk-bootstrap `PhysicalDeviceSelector` + direct `vkGetPhysicalDeviceProperties()` on `m_physicalDevice` | vk-bootstrap already integrated; `m_physicalDevice` already cached by `RenderProcessor::InitializeContext()` |
| Vulkan layer enumeration | Manual `vkEnumerateInstanceLayerProperties` | vk-bootstrap's `SystemInfo::validation_layers_available` or `request_validation_layers()` | vk-bootstrap already queries layer availability in `SystemInfo::get_system_info()` [VERIFIED: VkBootstrap.cpp:750-755] |
| Validation layer loading | Manual `vkCreateInstance` with layer extension | vk-bootstrap's `InstanceBuilder::request_validation_layers()` | Best-effort semantics built-in: only adds layer if available [VERIFIED: VkBootstrap.cpp:823] |
| Mutex for Vulkan queries | New mutex | `VulkanInitMutex()` (`vulkan_init_guard.hpp`) | Already guards all Vulkan init; capability queries on same device use same mutex (D-10) |

**Key insight:** The existing codebase already provides all the primitives this phase needs — SHA-256, Vulkan device access, mutex guards, factory-map registration, and structured error types. The phase is primarily about composing these into a new `CapabilityValidator` class with the correct async callback interface.

## Runtime State Inventory

> Phase 06 is greenfield backend infrastructure (new `CapabilityValidator` class + CMake option). No rename/refactor/migration. This section is omitted per the research output format spec.

## Common Pitfalls

### Pitfall 1: VkPhysicalDeviceLimits Field Confusion
**What goes wrong:** Assuming `maxPerStageResources` is in `VkPhysicalDeviceLimits` when it is actually `maxPerStageDescriptorSamplers`, `maxPerStageDescriptorUniformBuffers`, etc. — or confusing `maxMemoryAllocationCount` (total allocations) with per-heap size.

**Why it happens:** The Vulkan spec has many similarly-named limits; the seven critical limits named in D-14 must be verified against the actual `VkPhysicalDeviceLimits` struct.

**How to avoid:** Use the exact struct member names:
```cpp
// Exact fields in VkPhysicalDeviceLimits (Vulkan 1.3 spec):
// limits.maxImageDimension2D         — D-14 ✓
// limits.maxBufferSize              — D-14 ✓ (VkDeviceSize, min 65536)
// limits.maxPushConstantsSize       — D-14 ✓ (min 128 bytes)
// limits.maxUniformBufferRange      — D-14 ✓ (VkDeviceSize, min 16384)
// limits.maxColorAttachments        — D-14 ✓ (min 4)
// limits.maxPerStageResources       — D-14 ✓ (min 128)
// limits.maxMemoryAllocationCount   — D-14 ✓ (min 4096)
```
[VERIFIED: Vulkan 1.3 spec, VkPhysicalDeviceLimits]

**Warning signs:** Compiler error about missing struct member — check the exact name against `vulkan_core.h`.

### Pitfall 2: GPU Memory Estimation Error
**What goes wrong:** Estimating render-target memory as `width * height * 4` (assuming RGBA8) when the actual format may be R32G32B32A32_SFLOAT (16 bytes/pixel) or depth/stencil has different sizes.

**Why it happens:** Different `VkFormat` values have different texel sizes. A naive bytes-per-pixel table gets out of sync with the format enum.

**How to avoid:** Use `vkGetPhysicalDeviceFormatProperties()` to verify format support (already done by `RenderProcessor::CheckFormatSupport()`), then compute bytes-per-pixel from the format enum. The conservative estimate approach: compute the worst-case byte size for all declared formats, then add pipeline overhead (fixed ~64 MB for descriptor pools, pipeline cache, command pools).

**Warning signs:** `VK_ERROR_OUT_OF_DEVICE_MEMORY` at draw time despite "estimation said it would fit."

### Pitfall 3: Disk Space Check Portability
**What goes wrong:** Using `statvfs` on Windows or `GetDiskFreeSpaceEx` on Linux — platform-specific APIs that don't compile cross-platform.

**Why it happens:** No existing disk-space abstraction exists in the SGProcessingManager or GeniusSDK codebase.

**How to avoid:** Wrap in a small platform-specific helper:
```cpp
// capability_validator.cpp
#ifdef _WIN32
#include <windows.h>
uint64_t GetAvailableDiskBytes(const std::string& path) {
    ULARGE_INTEGER freeBytes;
    if (GetDiskFreeSpaceExA(path.c_str(), &freeBytes, nullptr, nullptr)) {
        return freeBytes.QuadPart;
    }
    return 0;
}
#else
#include <sys/statvfs.h>
uint64_t GetAvailableDiskBytes(const std::string& path) {
    struct statvfs stat;
    if (statvfs(path.c_str(), &stat) == 0) {
        return stat.f_bavail * stat.f_frsize;
    }
    return 0;
}
#endif
```
[ASSUMED: No existing portable disk-space abstraction in the codebase — verified by grep across SGProcessingManager and GeniusSDK]

**Warning signs:** Compilation errors on the non-primary platform.

### Pitfall 4: vk-bootstrap request_validation_layers vs enable_validation_layers
**What goes wrong:** Using `enable_validation_layers()` (strict) instead of `request_validation_layers()` (best-effort), causing `VkInstance` creation to fail on systems without the Vulkan SDK.

**Why it happens:** The names are confusingly similar. `enable_validation_layers()` sets `info.enable_validation_layers = true` which makes layers required. `request_validation_layers()` sets `info.request_validation_layers = true` which makes them optional.

**How to avoid:** Always use `request_validation_layers(true)` (best-effort, per D-20). The current code in `RenderProcessor::InitializeContext()` already uses `request_validation_layers(false)` — change to the CMake-gated value.

```cpp
// VkBootstrap.cpp:823 — the key logic:
// if (info.enable_validation_layers || 
//     (info.request_validation_layers && system.validation_layers_available)) {
//     layers.push_back(detail::validation_layer_name);
// }
```
[VERIFIED: thirdparty/vk-bootstrap/src/VkBootstrap.cpp:823]

**Warning signs:** Instance creation fails with "requested_layers_not_present" on a system without Vulkan SDK.

### Pitfall 5: Forgetting VulkanInitMutex on Capability Queries
**What goes wrong:** Calling `vkGetPhysicalDeviceProperties()` or `vkGetPhysicalDeviceMemoryProperties()` without acquiring `VulkanInitMutex`, causing a data race with `RenderProcessor::InitializeContext()` or MNN `createSession()` calls.

**Why it happens:** The capability snapshot is built during `ProcessingManager::Init()`, but `RenderProcessor`'s Vulkan context is lazily initialized (Phase 1 D-06). If both happen concurrently, the mutex prevents races.

**How to avoid:** Wrap ALL `VkPhysicalDevice` queries in the capability snapshot builder with `std::lock_guard<std::mutex> lock(VulkanInitMutex())`, matching the pattern in `RenderProcessor::InitializeContext()` at `processing_processor_render.cpp:45`.

**Warning signs:** Intermittent segfaults or corrupted device property values during concurrent init.

## Code Examples

Verified patterns from the existing codebase:

### Vulkan Device Property Query (for CAP-02)
```cpp
// Source: existing RenderProcessor pattern — processing_processor_render.cpp:27-35
// Adapted for capability snapshot:

VkPhysicalDeviceProperties props;
vkGetPhysicalDeviceProperties(m_physicalDevice, &props);

// The seven critical limits (D-14):
uint32_t maxImageDim2D        = props.limits.maxImageDimension2D;
VkDeviceSize maxBufSize       = props.limits.maxBufferSize;
uint32_t maxPushConstSize     = props.limits.maxPushConstantsSize;
uint32_t maxUniformBufRange   = props.limits.maxUniformBufferRange;  // VkDeviceSize, truncated for UBO
uint32_t maxColorAttach       = props.limits.maxColorAttachments;
uint32_t maxPerStageRes       = props.limits.maxPerStageResources;
uint32_t maxMemAllocCount     = props.limits.maxMemoryAllocationCount;
```

### GPU Memory Query (for D-15)
```cpp
// Source: existing RenderProcessor::LargestDeviceLocalHeap() —
// processing_processor_render.cpp:27-35
// Adapted for total available check:

VkPhysicalDeviceMemoryProperties memProps;
vkGetPhysicalDeviceMemoryProperties(m_physicalDevice, &memProps);

VkDeviceSize totalDeviceLocal = 0;
for (uint32_t i = 0; i < memProps.memoryHeapCount; ++i) {
    if (memProps.memoryHeaps[i].flags & VK_MEMORY_HEAP_DEVICE_LOCAL_BIT) {
        totalDeviceLocal += memProps.memoryHeaps[i].size;
    }
}
```

### SHA-256 Hash for Executor Identity (D-08)
```cpp
// Source: SGProcessingManager/include/util/sha256.hpp:8
// Used across all MNN processors — e.g. processing_processor_mnn_bool.cpp:10

#include "util/sha256.hpp"

// Build a deterministic byte buffer from capability snapshot fields,
// then hash:
std::vector<uint8_t> BuildIdentityHash(const CapabilitySnapshot& snap) {
    std::vector<uint8_t> buf;
    // Append VkPhysicalDeviceProperties fields in deterministic order
    // Append VkPhysicalDeviceMemoryProperties heap sizes
    // Append MNN backend info strings
    // ...
    return sgns::sgprocmanagersha::sha256(buf.data(), buf.size());
}
```

### vk-bootstrap Validation Layer Toggle (VVAL)
```cpp
// Source: existing RenderProcessor::InitializeContext() —
// processing_processor_render.cpp:50-53
// Modified for CMake-gated validation layers:

vkb::InstanceBuilder instance_builder;
auto inst_ret = instance_builder
    .set_app_name("SGProcessingManager RenderProcessor")
    .set_app_version(1, 0, 0)
#ifdef ENABLE_VULKAN_VALIDATION
    .request_validation_layers(true)   // best-effort (D-20)
#else
    .request_validation_layers(false)
#endif
    .build();
```

### CMake Option Pattern (VVAL-03/D-24)
```cmake
# Source: existing CMake option pattern —
# GeniusSDK/cmake/CommonBuildParameters.cmake:446-448
option(TESTING "Build tests" OFF)
option(BUILD_EXAMPLES "Build examples" OFF)

# New — follows same pattern:
option(ENABLE_VULKAN_VALIDATION "Enable Vulkan validation layers (best-effort)" OFF)

# Conditional definition for Debug builds:
if(CMAKE_BUILD_TYPE MATCHES "[Dd][Ee][Bb][Uu][Gg]")
    set(ENABLE_VULKAN_VALIDATION_DEFAULT ON)
else()
    set(ENABLE_VULKAN_VALIDATION_DEFAULT OFF)
endif()
option(ENABLE_VULKAN_VALIDATION "Enable Vulkan validation layers" ${ENABLE_VULKAN_VALIDATION_DEFAULT})
```

### PassType Validation (CAP-04)
```cpp
// Source: existing m_passFactories pattern —
// ProcessingManager.hpp:81-89 (SetProcessorByPassType)

bool CapabilityValidator::IsPassTypeRegistered(PassType type) const {
    return m_passFactories.find(type) != m_passFactories.end();
}

// Returns available PassTypes (for error messages):
std::vector<PassType> CapabilityValidator::GetRegisteredPassTypes() const {
    std::vector<PassType> types;
    for (const auto& [type, _] : m_passFactories) {
        types.push_back(type);
    }
    return types;
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No pre-execution validation | `CapabilityValidator::CanExecute()` before claiming work | Phase 06 (this phase) | Prevents nodes from claiming jobs they cannot execute |
| MNN uses `MNN_FORWARD_CPU` | All 14 processors on `MNN_FORWARD_VULKAN` | Phase 01.1 (MIGR-01) | D-13: no CPU instruction checks needed |
| `request_validation_layers(false)` hardcoded | CMake-gated `request_validation_layers(ENABLE_VULKAN_VALIDATION)` | Phase 06 | Debug builds get validation layers when available |
| `ProcessingResult` no error field | `std::optional<ProcessingError> error` | Phase 3 (D-25) | Structured per-stage errors — `UnmetRequirement` follows same pattern |

**Deprecated/outdated:**
- `vk-bootstrap` `enable_validation_layers()` (strict mode): use `request_validation_layers()` instead for best-effort per D-20.
- Hardcoded `request_validation_layers(false)` in `RenderProcessor::InitializeContext()`: will be replaced by CMake-gated `#ifdef ENABLE_VULKAN_VALIDATION`.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | No existing portable disk-space abstraction in SGProcessingManager or GeniusSDK | Common Pitfalls #3 | Low — grep confirmed absence; a `#ifdef` wrapper is trivial |
| A2 | `sgns::sgprocmanagersha::sha256()` is the appropriate hash for executor identity | Code Examples | Low — already used by ALL MNN processors and RenderProcessor for output hashing |
| A3 | `m_passFactories` is accessible from `CapabilityValidator` for PassType registration check | Code Examples | Low — `CapabilityValidator` is internally constructed by `ProcessingManager`, which owns both maps |
| A4 | The `CapabilityValidator` does not need its own `VkInstance` — it reuses `RenderProcessor`'s `m_physicalDevice` | Architecture Patterns | Medium — if `RenderProcessor` hasn't lazily initialized yet when snapshot is built, the snapshot must trigger lazy init first |

## Open Questions (RESOLVED)

1. **When exactly does `CapabilityValidator::BuildSnapshot()` run relative to `RenderProcessor`'s lazy init?** — **RESOLVED:** `BuildSnapshot` receives a `std::function<VkPhysicalDevice()> ensureVulkanDevice` callable from `ProcessingManager`. This lambda calls `RenderProcessor::InitializeContext()` under `VulkanInitMutex` if not yet initialized, then returns the device handle. The planner incorporated this in Plan 06-01 Task 2/3 with the `ensureVulkanDevice` parameter. **No temporary VkInstance is created** (D-10).

2. **Disk space: which directory to check?** — **RESOLVED:** Check `FileManager::getCacheDir()` as the conservative default. The planner has discretion to use `"."` (CWD) as a fallback if the cache dir is unavailable at snapshot-build time. The disk space check is advisory (TOCTOU acknowledged by D-16).

3. **Async callback: which `io_context`?** — **RESOLVED:** `CanExecute()` checks are synchronous (cached data reads). The "async" in D-03 refers to the callback pattern, not async I/O. The callback is invoked synchronously. If the scheduler needs async dispatch, it wraps the call via its own `io_context::post()`. The planner has discretion on the exact signature.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Vulkan Loader | CAP-02 (device queries), VVAL (validation layers) | ✓ | 1.3+ (system) | — |
| Vulkan SDK (validation layers) | VVAL (best-effort, D-20) | ✗ (not on all systems) | N/A | `request_validation_layers()` silently skips if layer not found |
| MNN | CAP-03 (backend registry) | ✓ | vendored | — |
| OpenSSL (SHA-256) | CAP-06 (executor identity hash) | ✓ | vendored (~3.0.x) | — |
| `<sys/statvfs.h>` / `<windows.h>` | CAP-05 (disk space) | ✓ | system | — |
| CMake | VVAL-03 (ENABLE_VULKAN_VALIDATION option) | ✓ | ^3.5 | — |

**Missing dependencies with no fallback:** None — all dependencies are system-provided or already vendored.

**Missing dependencies with fallback:**
- Vulkan SDK validation layers: best-effort per D-20 — silently skipped if not installed.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | yes | Capability checks are input validation: rejecting jobs with unsupported formats/limits before execution prevents DoS and resource exhaustion |
| V6 Cryptography | yes | `sha256` for executor identity hash — already a codebase convention; uses existing OpenSSL-backed implementation |

### Known Threat Patterns for Vulkan/C++ Capability Validation

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malicious job claiming impossible dimensions to trigger OOM | Denial of Service | CAP-05: GPU memory estimation + VkPhysicalDeviceMemoryProperties check rejects job before any allocation |
| Job specifying unsupported format to trigger driver crash | Denial of Service | CAP-02: Vulkan limit/format checks reject unsupported configurations |
| Disk-filling attack via large output artifacts | Denial of Service | CAP-05/D-16: disk space check before job acceptance |
| Validation layer message injection (if layers enabled) | Information Disclosure | VVAL: layers are debug-only, disabled in Release (D-24); `request_validation_layers()` best-effort (D-20) |
| Executor identity spoofing via crafted version strings | Spoofing | CAP-06/D-08: identity is SHA-256 hash of actual capability data, not trust-based version strings |

## Sources

### Primary (HIGH confidence)
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp:1-170` — `InitializeContext()`, `LargestDeviceLocalHeap()`, `IsAcceptable()`, `MakeError()` patterns
- `SuperGenius/SGProcessingManager/include/processors/processing_processor.hpp:1-85` — `ProcessingResult`, `ProcessingError`, `ProcessingErrorStage` structs
- `SuperGenius/SGProcessingManager/include/processingbase/vulkan_init_guard.hpp:1-20` — `VulkanInitMutex()` pattern
- `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp:1008-1035` — `Init()` factory registration pattern
- `SuperGenius/SGProcessingManager/include/processingbase/ProcessingManager.hpp:50-150` — `RegisterProcessorFactory`, `RegisterPassProcessorFactory`, `SetProcessorByPassType`, `m_passFactories`
- `thirdparty/vk-bootstrap/src/VkBootstrap.cpp:823` — validation layer resolution logic
- `thirdparty/vk-bootstrap/src/VkBootstrap.cpp:978-980` — `enable_validation_layers()` vs `request_validation_layers()` API
- `thirdparty/vk-bootstrap/src/VkBootstrap.h:410,481` — `InstanceBuilder` API declarations
- `SuperGenius/SGProcessingManager/include/util/sha256.hpp:1-10` — SHA-256 utility
- `SuperGenius/src/crypto/hasher.hpp:1-25` — SuperGenius hasher (sha2_256, blake2b_256, etc.)
- `GeniusSDK/cmake/CommonBuildParameters.cmake:446-448` — existing CMake `option()` patterns
- `.planning/config.json` — `workflow.nyquist_validation: false`, `workflow.security_enforcement: true`

### Secondary (MEDIUM confidence)
- Vulkan 1.3 Specification §36.2 — `VkPhysicalDeviceLimits` struct member names
- vk-bootstrap `docs/getting_started.md:103` — validation layer usage example
- `.planning/workstreams/sgproc-render/phases/06-capability-validation-foundation/06-CONTEXT.md` — all D-01 through D-25 decisions

### Tertiary (LOW confidence)
- None — all claims verified against codebase or official Vulkan specification.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all dependencies are already vendored; no new packages needed
- Architecture: HIGH — clear patterns from existing `ProcessingManager`, `RenderProcessor`, and `ProcessingResult` code
- Pitfalls: HIGH — all pitfalls grounded in specific codebase findings or Vulkan spec details
- Security: MEDIUM — ASVS mapping is straightforward; threat patterns are standard for Vulkan validation

**Research date:** 2026-08-04
**Valid until:** 2026-09-04 (stable — no fast-moving external dependencies)
