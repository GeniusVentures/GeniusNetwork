# Phase 1: Vulkan Foundation & Dispatch Plumbing - Pattern Map

**Mapped:** 2026-07-29
**Files analyzed:** 9
**Analogs found:** 9 / 9

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp` | component (processor) | request-response | `SuperGenius/SGProcessingManager/include/processors/processing_processor_mnn_image.hpp` | exact (sibling `ProcessingProcessor` subclass) |
| `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp` | component (processor) | request-response | `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_image.cpp` | role-match (Vulkan init/session pattern lives here) |
| `SuperGenius/SGProcessingManager/include/processingbase/vulkan_init_guard.hpp` | utility | event-driven (shared lock) | `processing_processor_mnn_image.cpp:112-115` (inline `mnn_vulkan_mutex`) | partial — no header-declared singleton analog exists yet; this is a new pattern extracted from an inline one |
| `SuperGenius/SGProcessingManager/include/processingbase/ProcessingManager.hpp` | service/dispatcher | request-response | itself (existing `m_processorFactories`/`RegisterProcessorFactory`/`SetProcessorByName`) | exact (additive to existing pattern) |
| `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` | service/dispatcher | request-response | itself (`CheckProcessValidity`, `ParseBlockSize`, `Process`, `GetCidForProc`) | exact (additive/guard fixes to existing functions) |
| `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_image.cpp` | component (processor) | request-response | itself (migrate `mnn_vulkan_mutex` to shared guard) | exact (modification, not new pattern) |
| `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_string.cpp` | component (processor) | request-response | `processing_processor_mnn_image.cpp` (post-migration guard usage) | role-match |
| `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_volume.cpp` | component (processor) | request-response | `processing_processor_mnn_image.cpp` (post-migration guard usage) | role-match |
| `SuperGenius/SGProcessingManager/src/processors/CMakeLists.txt` | config (build) | n/a | itself (existing `add_library(SGProcessors ...)` list + `Vulkan::Vulkan` link) | exact (additive entries) |

## Pattern Assignments

### `processing_processor_render.hpp` (component, request-response)

**Analog:** `SuperGenius/SGProcessingManager/include/processors/processing_processor_mnn_image.hpp`

**Base interface to implement** (`SuperGenius/SGProcessingManager/include/processors/processing_processor.hpp:27-56`):
```cpp
class ProcessingProcessor
{
public:
    virtual ~ProcessingProcessor() = default;
    virtual ProcessingResult StartProcessing( std::vector<std::vector<uint8_t>> &chunkhashes,
                           const sgns::IoDeclaration         &proc,
                           std::vector<char>                 &imageData,
                           std::vector<char>                 &modelFile,
                           const std::vector<sgns::Parameter> *parameters ) = 0;
    virtual float GetProgress() const { return m_progress; }

protected:
    std::atomic<float> m_progress{0.0f};
    sgns::sgprocmanager::Logger m_logger = sgns::sgprocmanager::createLogger( "SGProcessor" );
};
```

**Class shape pattern** (`processing_processor_mnn_image.hpp:34-87`):
```cpp
namespace sgns::sgprocessing
{
    class MNN_Image : public ProcessingProcessor
    {
    public:
        MNN_Image() {}
        ~MNN_Image() override {};
        ProcessingResult StartProcessing( std::vector<std::vector<uint8_t>> &chunkhashes,
                           const sgns::IoDeclaration         &proc,
                           std::vector<char>                 &imageData,
                           std::vector<char>                 &modelFile,
                           const std::vector<sgns::Parameter> *parameters ) override;
    private:
        // processor-specific private helper(s), e.g. Process(...)
    };
}
```
`RenderProcessor` should follow this exact shape: `class RenderProcessor : public ProcessingProcessor`, override `StartProcessing`, and keep Vulkan instance/device/queue members private (lazily constructed per D-06 — do not create them in the constructor). Naming convention for headers/loggers uses `sgns::sgprocmanager::createLogger("<Name>")`; use e.g. `"RenderProcessor"` for the logger tag override if a custom logger name is desired (base class already provides `m_logger`/`m_progress`, no need to redeclare).

Include convention: quoted relative include of the base header (`#include "processing_processor.hpp"`), `#pragma once` guard (image.hpp) — note `processing_processor.hpp` itself uses `#ifndef`/`#define` guards; either is acceptable, follow whichever the immediate sibling files use (image.hpp uses `#pragma once`).

---

### `processing_processor_render.cpp` (component, request-response)

**Analog:** `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_image.cpp`

**Imports pattern** (lines 1-8):
```cpp
#include "processors/processing_processor_mnn_image.hpp"
#include "datasplitter/ImageSplitter.hpp"
#include <functional>
#include <mutex>
#include <thread>
#include <openssl/sha.h> // For SHA256_DIGEST_LENGTH
#include "util/sha256.hpp"
#include "util/InputTypes.hpp"
```
For `processing_processor_render.cpp`, swap MNN/image-specific includes for `#include "processors/processing_processor_render.hpp"`, `#include "processingbase/vulkan_init_guard.hpp"`, and raw Vulkan headers (`<vulkan/vulkan.h>`, or vk-bootstrap's header if D-01 adopts it) — no `MNN/*` includes needed for this phase's stub.

**Vulkan-init-under-lock pattern** (lines 105-151, the part to mirror, not the MNN-specific preprocessing below it):
```cpp
std::unique_ptr<MNN::Tensor> MNN_Image::Process(...)
{
    // ponytail: MNN's Vulkan backend is not safe to initialize concurrently. Keep the
    // process-wide lock until MNN exposes a shareable runtime/session API.
    static std::mutex mnn_vulkan_mutex;
    std::lock_guard lock( mnn_vulkan_mutex );

    // ... createFromBuffer / createSession(MNN_FORWARD_VULKAN) calls follow, all under the lock
}
```
`RenderProcessor`'s lazy context-creation path must reproduce this exact shape but use the **shared** `VulkanInitMutex()` (not a new local static — this is precisely what D-04 requires migrating away from):
```cpp
ProcessingResult RenderProcessor::StartProcessing( ... )
{
    if ( !m_contextInitialized )
    {
        std::lock_guard<std::mutex> lock( sgns::sgprocessing::VulkanInitMutex() );
        if ( !m_contextInitialized ) // re-check inside lock
        {
            // vkCreateInstance / vkEnumeratePhysicalDevices (+ deterministic scoring,
            // Pattern 4 in RESEARCH.md) / vkCreateDevice / vkGetDeviceQueue
            m_contextInitialized = true;
        }
    }
    ProcessingResult result;
    result.hash = /* placeholder — pipeline/draw/readback is Phase 3 */;
    return result;
}
```

**Error handling pattern** (mirrors MNN_Image's style throughout — early-return with `m_logger->error(...)` + placeholder/empty return value, not exceptions):
```cpp
if ( !mnnNet )
{
    m_logger->error( "Failed to create MNN image interpreter" );
    return std::make_unique<MNN::Tensor>();
}
```
`RenderProcessor` should mirror this: log via `m_logger->error(...)` and return an empty/default `ProcessingResult{}` on any Vulkan call failure (`VkResult != VK_SUCCESS`), never throw.

**Progress reporting pattern** (lines 63, 94, base class `m_progress`):
```cpp
m_progress = 0.0f; // Reset progress at start
...
m_progress = std::round(((chunkIdx + 1) * 100.0f / totalChunks) * 100.0f) / 100.0f;
```
Not required for this phase's minimal stub (no chunk loop exists yet), but keep `m_progress` semantics consistent (0.0f until "done", set once at the end) if the stub reports any progress at all.

---

### `include/processingbase/vulkan_init_guard.hpp` (utility, shared lock — NEW FILE)

**Analog:** the inline mutex at `processing_processor_mnn_image.cpp:112-115` (being migrated out of this file into the new shared header) — this is the one file in this phase with no direct structural analog elsewhere in the codebase (no other header-declared "magic static" accessor exists in this project today); the pattern is taken from RESEARCH.md Pattern 3, grounded against this exact inline precedent.

**Current pattern being replaced** (`processing_processor_mnn_image.cpp:112-115`):
```cpp
// ponytail: MNN's Vulkan backend is not safe to initialize concurrently. Keep the
// process-wide lock until MNN exposes a shareable runtime/session API.
static std::mutex mnn_vulkan_mutex;
std::lock_guard lock( mnn_vulkan_mutex );
```

**New shared header shape** (RESEARCH.md Pattern 3, ready to implement as-is):
```cpp
// include/processingbase/vulkan_init_guard.hpp
#pragma once
#include <mutex>

namespace sgns::sgprocessing
{
    inline std::mutex &VulkanInitMutex()
    {
        static std::mutex vulkan_init_mutex;   // magic static — thread-safe init, C++11+
        return vulkan_init_mutex;
    }
}
```
Namespace convention (`sgns::sgprocessing`) and header-guard style (`#pragma once`) both match this codebase's established conventions (see `processing_processor_mnn_image.hpp:5`, `ProcessingManager.hpp` uses `#ifndef` guards instead — either style already coexists in this codebase; `#pragma once` is the more common choice among the processor-family headers and is recommended for the new file).

---

### `include/processingbase/ProcessingManager.hpp` (service/dispatcher, modified)

**Analog:** itself — existing `DataType`-keyed factory-map pattern to mirror structurally for the new `PassType`-keyed map.

**Existing pattern to mirror** (lines 55-63, 105-125, 130):
```cpp
void RegisterProcessorFactory( const int &name,
                               std::function<std::unique_ptr<ProcessingProcessor>()> factoryFunction )
{
    m_processorFactories[name] = std::move( factoryFunction );
}
...
bool SetProcessorByName( const int &name )
{
    auto factoryFunction = m_processorFactories.find( name );
    if ( factoryFunction != m_processorFactories.end() )
    {
        m_processor = factoryFunction->second();
        return true;
    }
    std::cerr << "Unknown processor name: " << name << std::endl;
    return false;
}
...
std::unordered_map<int, std::function<std::unique_ptr<ProcessingProcessor>()>> m_processorFactories;
```

**New addition** (DISP-02, structurally parallel, keyed on `PassType` not `int`, per RESEARCH.md's explicit collision warning — `PassType::RENDER == 3 == DataType::INT`):
```cpp
void RegisterPassProcessorFactory( PassType type,
                                   std::function<std::unique_ptr<ProcessingProcessor>()> factoryFunction )
{
    m_passFactories[type] = std::move( factoryFunction );
}

bool SetProcessorByPassType( PassType type )
{
    auto factoryFunction = m_passFactories.find( type );
    if ( factoryFunction != m_passFactories.end() )
    {
        m_processor = factoryFunction->second();
        return true;
    }
    std::cerr << "Unknown pass type: " << static_cast<int>( type ) << std::endl;
    return false;
}
...
std::unordered_map<PassType, std::function<std::unique_ptr<ProcessingProcessor>()>> m_passFactories;
```
Note: `PassType` needs a `std::hash` specialization or an `enum class`-safe wrapper for `unordered_map` keying (standard C++ requires this for scoped enums) — mirror however the codebase's other enum-keyed maps handle this, or add `struct PassTypeHash { size_t operator()(PassType p) const { return static_cast<size_t>(p); } };` and pass it as the map's third template argument, matching the terse style seen in this header.

**New include needed:** `#include <processors/processing_processor_render.hpp>` alongside the existing MNN processor includes (lines 8-23).

---

### `src/processingbase/ProcessingManager.cpp` (service/dispatcher, modified — 3 separate mechanical changes)

**Analog:** itself — three existing functions to extend in place, each with a directly-adjacent existing case/branch to mirror.

**1. `CheckProcessValidity()` shader-presence check (DISP-03)** — mirrors the `INFERENCE` case immediately above it (lines 138-146):
```cpp
case PassType::INFERENCE:
{
    if ( !pass.get_model() )
    {
        m_logger->error( "Inference json has no model" );
        return outcome::failure( Error::PROCESS_INFO_MISSING );
    }
    break;
}
```
Replace the current no-op at lines 151-152 (`case PassType::RENDER: break;`) with:
```cpp
case PassType::RENDER:
{
    if ( !pass.get_shader() )
    {
        m_logger->error( "Render pass has no shader config" );
        return outcome::failure( Error::PROCESS_INFO_MISSING );
    }
    break;
}
```

**2. `ParseBlockSize()` type-guard fix (DISP-01)** — line 649, currently unconditional:
```cpp
// BEFORE (crashes on model-less passes):
auto input_nodes = pass.get_model().value().get_input_nodes();
```
```cpp
// AFTER:
if ( !pass.get_model() )
{
    continue;   // render/compute passes contribute 0 — block-size semantics
                // for their vertex/index buffers is a Phase 2 schema decision
}
auto input_nodes = pass.get_model().value().get_input_nodes();
```

**3. `Process()` dispatch branch (DISP-02)** — lines 669-693, existing `DataType`-keyed dispatch to branch around:
```cpp
auto modelname = model.get_source().value();
auto index     = GetInputIndex( modelname );
if ( !index )
{
    return outcome::failure( Error::MISSING_INPUT );
}
auto maybe_buffers = GetCidForProc( ioc, model );
...
if ( !SetProcessorByName( static_cast<int>( processing_.get_inputs()[index.value()].get_type() ) ) )
{
    return outcome::failure( Error::NO_PROCESSOR );
}
```
Insert a `pass.get_type()` branch immediately after `index` is resolved (RESEARCH.md Pattern 1, illustrative shape — exact structure is Claude's Discretion per CONTEXT.md):
```cpp
const auto &pass = processing_.get_passes()[index.value()];
if ( pass.get_type() == PassType::RENDER )
{
    if ( !SetProcessorByPassType( PassType::RENDER ) )
        return outcome::failure( Error::NO_PROCESSOR );
}
else
{
    if ( !SetProcessorByName( static_cast<int>( processing_.get_inputs()[index.value()].get_type() ) ) )
        return outcome::failure( Error::NO_PROCESSOR );
}
```
`GetCidForProc()` (lines 823-849) needs a parallel branch too — line 840 currently unconditionally reads `.get_model().value().get_source_uri_param()`; for a RENDER pass, read `pass.get_shader().value().get_source()` instead (reusing the same `GetSubCidForProc`/`FileManager` async-fetch machinery at lines 845-849).

**Constructor/registration site** (lines 100-103, existing factory-registration block in `Init`/constructor) — mirror this exact call shape for registering `RenderProcessor`:
```cpp
RegisterProcessorFactory( static_cast<int>( DataType::TEXTURE_CUBE ),
                          [] { return std::make_unique<sgprocessing::MNN_TextureCube>(); } );
```
New registration (via the new `PassType`-keyed method, not `RegisterProcessorFactory`):
```cpp
RegisterPassProcessorFactory( PassType::RENDER,
                              [] { return std::make_unique<sgprocessing::RenderProcessor>(); } );
```

---

### `processing_processor_mnn_image.cpp` (modified — migrate mutex to shared guard)

**Analog:** itself, before/after diff.

**Before** (lines 112-115):
```cpp
static std::mutex mnn_vulkan_mutex;
std::lock_guard lock( mnn_vulkan_mutex );
```
**After:**
```cpp
std::lock_guard<std::mutex> lock( sgns::sgprocessing::VulkanInitMutex() );
```
Add `#include "processingbase/vulkan_init_guard.hpp"` to this file's includes (alongside the existing `#include <mutex>` at line 4, which can now be removed if unused elsewhere in the file — verify no other direct `std::mutex` use exists before removing).

---

### `processing_processor_mnn_string.cpp` / `processing_processor_mnn_volume.cpp` (modified — add guard where none exists today)

**Analog:** `processing_processor_mnn_string.cpp:150-155` (currently unguarded) and the post-migration `processing_processor_mnn_image.cpp` pattern above.

**Current unguarded pattern** (`processing_processor_mnn_string.cpp:150-155`, `_volume.cpp:582-586` is structurally identical):
```cpp
// Configure session
MNN::ScheduleConfig config;
config.type = MNN_FORWARD_VULKAN;  // Use Vulkan backend as requested
config.numThread = 4;

auto session = interpreter->createSession(config);
```
**Required change** — wrap the `createSession` call (and, per D-04's "before any vkCreate*" scope, the config/interpreter construction immediately preceding it is fine to leave outside the lock since only `createSession` triggers MNN's internal Vulkan device init — match whatever exact boundary `processing_processor_mnn_image.cpp`'s migrated version uses for consistency):
```cpp
MNN::ScheduleConfig config;
config.type = MNN_FORWARD_VULKAN;
config.numThread = 4;

std::unique_ptr<MNN::Session> session;
{
    std::lock_guard<std::mutex> lock( sgns::sgprocessing::VulkanInitMutex() );
    session = interpreter->createSession(config);
}
```
Add `#include "processingbase/vulkan_init_guard.hpp"` to both files.

---

### `src/processors/CMakeLists.txt` (config, modified)

**Analog:** itself — existing `add_library(SGProcessors STATIC ...)` source list (lines 1-39) and existing `Vulkan::Vulkan` link (line 58).

**Pattern to extend:**
```cmake
add_library(SGProcessors STATIC 
	processing_processor_mnn_image.cpp
	...
	processing_processor_mnn_volume.cpp
	../../include/processors/processing_processor.hpp
	...
	../../include/processors/processing_processor_mnn_volume.hpp
)
```
Add `processing_processor_render.cpp` to the source list and `../../include/processors/processing_processor_render.hpp` to the header list, following the exact same relative-path convention. If D-01 adopts vk-bootstrap, add `vk-bootstrap` (or its resolved CMake target name) to the existing `target_link_libraries(SGProcessors PUBLIC ...)` block (line 50-61) alongside `Vulkan::Vulkan` — no new `target_include_directories` entry should be needed if vk-bootstrap is consumed as a proper CMake target with `INTERFACE`/`PUBLIC` include dirs of its own (verify against vk-bootstrap's actual `CMakeLists.txt` at implementation time per RESEARCH.md Open Question #1).

If vk-bootstrap is adopted, a **separate** file — `thirdparty/build/CommonTargets.cmake` — also needs an `ExternalProject_Add` block mirroring the existing Vulkan-Headers/Vulkan-Loader block at lines 363-391 of that file (not analyzed in depth here since it's outside `SGProcessingManager` proper; RESEARCH.md's Decision Point section already gives the illustrative shape), and `thirdparty/.gitmodules` needs a new `[submodule "vk-bootstrap"]` entry mirroring the existing Vulkan-Headers/Vulkan-Loader/MoltenVK entries at lines 70-78.

## Shared Patterns

### Vulkan init synchronization (CTX-02/D-04)
**Source:** New `include/processingbase/vulkan_init_guard.hpp` (`VulkanInitMutex()` magic-static accessor)
**Apply to:** All 4 Vulkan instance/device-creation call sites — `processing_processor_mnn_image.cpp` (migrate), `processing_processor_mnn_string.cpp` (add), `processing_processor_mnn_volume.cpp` (add), `processing_processor_render.cpp` (new, lazy-init path)
```cpp
std::lock_guard<std::mutex> lock( sgns::sgprocessing::VulkanInitMutex() );
// vkCreateInstance / vkCreateDevice / vkEnumeratePhysicalDevices / MNN createSession(MNN_FORWARD_VULKAN)
```
Do **not** use `std::call_once` — the guard must be acquired on every init call, not run once ever (see RESEARCH.md Pattern 3 and Anti-Patterns).

### Error handling / logging (existing project convention)
**Source:** `processing_processor_mnn_image.cpp` throughout (e.g. lines 44-47, 78-82, 131-135)
**Apply to:** `processing_processor_render.cpp`, any modified `ProcessingManager.cpp` branches
```cpp
if ( !someCondition )
{
    m_logger->error( "Descriptive message" );
    return ProcessingResult{};   // or outcome::failure(Error::...) in ProcessingManager
}
```
No exceptions for expected-failure paths; `m_logger` (base class, spdlog-backed via `sgns::sgprocmanager::createLogger`) + early-return is the house style. `ProcessingManager`-level functions use `outcome::result<T>`/`outcome::failure(Error::...)` instead of `ProcessingResult{}`.

### Enum-keyed dispatch map, kept structurally separate from unrelated enums
**Source:** `ProcessingManager.hpp` existing `m_processorFactories` (`DataType`-keyed) vs. new `m_passFactories` (`PassType`-keyed)
**Apply to:** `ProcessingManager.hpp`/`.cpp` DISP-02 changes only
Never cast a differently-typed enum into the same `int`-keyed map — the confirmed `PassType::RENDER == 3 == DataType::INT` collision is the concrete reason this project needs two maps, not one.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `include/processingbase/vulkan_init_guard.hpp` | utility | event-driven (shared lock) | No existing header-declared, process-wide synchronization primitive exists in this codebase today — the only precedent is the inline, file-scoped `mnn_vulkan_mutex` being migrated out of `processing_processor_mnn_image.cpp` in this same phase. Pattern is taken directly from RESEARCH.md Pattern 3 (magic-static, cross-checked against general C++ concurrency references), not an in-repo analog. |
| Physical-device selection scoring logic (CTX-03/D-02/D-03, likely landing inside `processing_processor_render.cpp` or a small helper) | utility | transform | No existing device-enumeration/scoring code exists anywhere in this codebase (MNN's own Vulkan backend is fully internal/unexposed) — use RESEARCH.md Pattern 4's `IsAcceptable`/`LargestDeviceLocalHeap` code directly as the starting point instead of searching for an in-repo analog. |

## Metadata

**Analog search scope:** `SuperGenius/SGProcessingManager/include/processors/`, `SuperGenius/SGProcessingManager/src/processors/`, `SuperGenius/SGProcessingManager/include/processingbase/`, `SuperGenius/SGProcessingManager/src/processingbase/`
**Files scanned:** ~35 processor header/source files (glob), `ProcessingManager.hpp`/`.cpp` (full relevant sections), `processing_processor.hpp` (full), `processing_processor_mnn_image.hpp/.cpp` (full), `processing_processor_mnn_string.cpp`/`processing_processor_mnn_volume.cpp` (targeted grep + read around `createSession`), `src/processors/CMakeLists.txt` (full)
**Pattern extraction date:** 2026-07-29
