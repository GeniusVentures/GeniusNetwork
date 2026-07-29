# Architecture Research: Hand-Rolled Vulkan RenderProcessor Integration

**Domain:** Headless Vulkan render-pass execution inside SGProcessingManager's distributed processing pipeline
**Researched:** 2026-07-29
**Confidence:** HIGH for codebase findings (direct source reads with file:line citations); MEDIUM for cross-verified Vulkan spec/loader claims (external, cross-checked across 2+ sources, not primary-spec-text quoted verbatim)

## Standard Architecture

### System Overview (as it exists today, annotated with the new RENDER path)

```
┌──────────────────────────────────────────────────────────────────────────┐
│  ProcessingCoreImpl::ProcessSubTask()                                     │
│  (SuperGenius/src/processing/impl/processing_core_impl.cpp:55-140)        │
│  - loads Task json from CRDT, parses ModelNode from SubTask json          │
│  - calls ProcessingManager::Process(ioc, chunkhashes, model, out_locs)    │
└───────────────────────────────┬────────────────────────────────────────┘
                                 │
┌───────────────────────────────▼────────────────────────────────────────┐
│  ProcessingManager (SGProcessingManager/src/processingbase/)             │
│                                                                            │
│  CheckProcessValidity()  — pass.get_type() switch, RENDER currently a    │
│    no-op (ProcessingManager.cpp:151-152) — validated, never routed        │
│                                                                            │
│  Process(ioc, chunkhashes, model, out_locations)                         │
│   ├─ index = GetInputIndex(model.get_source())      [cpp:671]           │
│   ├─ NEW: pass = processing_.get_passes()[index]     ← same index today  │
│   │        is already (undocumented-ly) reused to index get_passes()      │
│   │        at cpp:840 inside GetCidForProc — see Integration Points       │
│   ├─ switch(pass.get_type())                                             │
│   │    ├─ RENDER  → NEW m_passFactories[PassType::RENDER] → RenderProcessor│
│   │    └─ default → existing m_processorFactories[DataType(...)] → MNN_*  │
│   └─ processResult = m_processor->StartProcessing(...) [cpp:689]         │
│        (same ProcessingResult contract for both paths)                   │
│                                                                            │
│   output_buffers → FileManager::SaveASync(...) [cpp:696-817]  — UNCHANGED │
└───────────────────────────────┬────────────────────────────────────────┘
                                 │
        ┌────────────────────────┴─────────────────────────┐
        │                                                    │
┌───────▼────────────────┐                     ┌────────────▼───────────────┐
│ MNN_* processor family  │                     │ RenderProcessor (NEW)       │
│ (processing_processor_  │                     │ processing_processor_       │
│  mnn_*.cpp, 17 classes) │                     │ render.cpp/.hpp             │
│ : public ProcessingProcessor                    │ : public ProcessingProcessor│
│ owns MNN::Interpreter   │                     │ owns OWN VkInstance/VkDevice│
│ (Vulkan fully internal   │                     │ (headless, no swapchain)    │
│  to MNN, never exposed) │                     │ own physical device pick,   │
│                          │                     │ own queue, own command pool │
└──────────────────────────┘                     └─────────────────────────────┘
        │                                                    │
        └──────────────────── same physical GPU ────────────┘
             (independent VkInstance/VkDevice each — see Coexistence Risk)
```

### Component Responsibilities

| Component | Responsibility | File(s) |
|-----------|----------------|---------|
| `ProcessingManager` | Parses `SgnsProcessing` JSON, validates passes, dispatches one pass's execution to a `ProcessingProcessor` implementation, forwards output buffers to `FileManager` for save/IPFS-publish | `SGProcessingManager/src/processingbase/ProcessingManager.cpp` |
| `ProcessingProcessor` (base) | Generic one-shot "take chunk hashes + IoDeclaration + two raw byte buffers + optional parameters, return `ProcessingResult`" contract; no MNN- or Vulkan-specific assumptions baked in | `SGProcessingManager/include/processors/processing_processor.hpp:27-56` |
| `MNN_*` family (17 classes) | Bind an `MNN::Interpreter` model (fed via the "modelFile" buffer) against differently-shaped input data (fed via the "imageData" buffer), keyed by `DataType` of the model's designated input | `SGProcessingManager/src/processors/processing_processor_mnn_*.cpp` |
| `RenderProcessor` (NEW) | Own independent headless Vulkan instance/device; builds a graphics pipeline from schema `shader_config` + new render-target/buffer-binding fields; executes one offscreen render pass; reads back the color attachment into a host buffer | `SGProcessingManager/src/processors/processing_processor_render.cpp` (new) |
| `Vulkan::Vulkan` CMake target | Already-vendored Vulkan-Loader + Vulkan-Headers, resolved via standard `find_package(Vulkan)` against `VULKAN_SDK` pointed at the thirdparty-built loader | `thirdparty/build/CommonTargets.cmake:363-391`, consumed at `SGProcessingManager/src/processors/CMakeLists.txt:58` |
| MNN's internal Vulkan backend | `MNN::VulkanInstance`/`VulkanDevice` — fully private to MNN's `backend/vulkan/` implementation, never included by any header SGProcessingManager uses | `thirdparty/MNN/source/backend/vulkan/component/VulkanInstance.hpp:17-37` |

## Recommended Project Structure

```
SGProcessingManager/
├── gnus-processing-schema.json        # extend "pass" (render_target,
│                                       #   vertex/index buffer bindings,
│                                       #   vertex+fragment shader stages)
├── generated/                         # regenerate via quicktype — NEVER hand-edit
│   ├── PassType.hpp                   # unchanged (RENDER already exists)
│   ├── DataType.hpp                   # unchanged
│   └── SgnsProcessing.hpp             # new render-pass fields land here
├── include/processors/
│   ├── processing_processor.hpp       # unchanged base interface
│   └── processing_processor_render.hpp  # NEW — parallel to mnn_*.hpp siblings
├── include/processingbase/
│   └── ProcessingManager.hpp          # + m_passFactories, RegisterPassProcessorFactory,
│                                       #   SetProcessorByPassType (additive only)
└── src/
    ├── processingbase/ProcessingManager.cpp  # + PassType branch in Process(),
    │                                          #   guard in ParseBlockSize()
    └── processors/
        ├── CMakeLists.txt             # + processing_processor_render.cpp,
        │                              #   + link new SPIR-V compiler lib
        └── processing_processor_render.cpp   # NEW
```

### Structure Rationale

- `RenderProcessor` sits as a **sibling file next to the MNN family**, not a new module/library — it reuses the same `SGProcessors` static-library target, the same `ProcessingProcessor` base class, and the same `Vulkan::Vulkan` link dependency that target already declares (`CMakeLists.txt:58`) for MNN's sake. No new CMake target is needed for the class itself.
- Schema/generated separation is already enforced by convention (`generated/` is quicktype output) — the milestone's own scoping already states this, confirmed by the presence of `Generators.hpp`/`helper.hpp` boilerplate headers in every generated file.

## Architectural Patterns

### Pattern 1: PassType-keyed dispatch alongside DataType-keyed dispatch (additive, not replacing)

**What:** Add a second dispatch table, `m_passFactories: unordered_map<PassType, factory>`, checked in `Process()` before falling through to the existing `m_processorFactories` (DataType-keyed) path.

**Why a *separate* map is required, not reuse of `m_processorFactories`:** `RegisterProcessorFactory`/`SetProcessorByName` key on a plain `int` cast from `DataType` (`ProcessingManager.hpp:59-63`, `.cpp:72-103`). Casting `PassType` to the same `int` space collides directly:

```cpp
// generated/DataType.hpp:19
enum class DataType : int { BOOL, BUFFER, FLOAT, INT, MAT2, MAT3, MAT4, STRING, ... };
//                                                  ^ INT = 3

// generated/PassType.hpp:26
enum class PassType : int { COMPUTE, DATA_TRANSFORM, INFERENCE, RENDER, RETRAIN };
//                                                              ^ RENDER = 3
```

`static_cast<int>(PassType::RENDER) == static_cast<int>(DataType::INT) == 3`. Reusing `m_processorFactories` for both would silently dispatch a RENDER pass to whatever factory is registered for `DataType::INT` (currently `MNN_Int`). This is not a hypothetical risk — it is a confirmed, exact collision in the current generated enums. The new `m_passFactories` map must key on the `PassType` enum type itself (or an explicitly disjoint integer range), not on `static_cast<int>`.

**Where dispatch belongs in `Process()`:** immediately after `index = GetInputIndex(modelname)` at `ProcessingManager.cpp:671`. Today, that same `index` is *already* reused (undocumented, but present in the shipped code) to index `processing_.get_passes()` at `cpp:840`:

```cpp
// ProcessingManager.cpp:840 — inside GetCidForProc
std::string modelFile = processing_.get_passes()[index.value()].get_model().value().get_source_uri_param();
```

This confirms the existing implicit convention: **input array index == pass array index** (passes and inputs are expected to be positionally parallel). This is the cheapest, least-disruptive hook — no signature change to `Process()`, no change to `ProcessingCoreImpl`'s call site (`processing_core_impl.cpp:102`), no change to how subtasks are split today. The new code simply reads `processing_.get_passes()[index.value()].get_type()` and branches:

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

**Trade-off / flag for the roadmap:** this reuses a convention that is currently *implicit and untested* (passes[i] ↔ inputs[i] positional pairing). It is real and already load-bearing in shipped code (`cpp:840`), so relying on it is not introducing a new risk — but it means the schema/job-splitter must keep emitting passes and inputs in matching order for any pass type, render included. This is worth an explicit assertion/validation addition in `CheckProcessValidity()` (passes.size() == inputs.size(), or an explicit index field) as a small hardening step, not a blocker.

**`GetCidForProc` also needs a parallel branch:** it unconditionally calls `model.get_model().value().get_source_uri_param()`-equivalent logic assuming a `model_config` (`cpp:840`). For a RENDER pass there is no `model` at all (schema requires `shader` instead — `gnus-processing-schema.json:205-222`, the `allOf`/`if`/`then` block). The render branch must instead read `pass.get_shader().value().get_source()` for the shader URI and fetch the schema's new vertex/index buffer binding(s) the same way — reusing the exact same `FileManager`/`GetSubCidForProc` async-fetch machinery (`cpp:885-913`), just pointed at different fields.

### Pattern 2: `RenderProcessor` reuses the existing `ProcessingProcessor` interface — no new sibling hierarchy

**What:** `RenderProcessor : public sgns::sgprocessing::ProcessingProcessor`, implementing the same `StartProcessing(chunkhashes, proc, imageData, modelFile, parameters) -> ProcessingResult` signature as every `MNN_*` class.

**Why this fits without modification:** the interface (`processing_processor.hpp:37-41`) is already generic — two raw `std::vector<char>&` buffers plus an `IoDeclaration` plus optional parameters. Nothing in the signature is MNN-specific:
- `modelFile` buffer → reinterpreted as compiled SPIR-V bytes (or GLSL source bytes needing runtime compilation — see Pattern 3) instead of an MNN `.mnn` model blob.
- `imageData` buffer → reinterpreted as packed vertex/index buffer bytes instead of an input tensor/image.
- `ProcessingResult::output_buffers` (a `pair<vector<string>, vector<vector<char>>>`, same as every MNN processor already produces) → the readback-from-framebuffer bytes, flowing unchanged through `Process()`'s existing output-save path (`cpp:696-817`, `FileManager::SaveASync`).

**When a new sibling hierarchy would have been justified (and isn't here):** if the render pass needed a fundamentally different return shape (e.g., streaming partial results, or a different progress-reporting contract) or if it needed to bypass the "chunkhashes" concept entirely. Neither is true — `RenderProcessor` produces exactly one shot of output bytes per invocation, identical in shape to what `MNN_Image`/`MNN_Buffer` already produce. Reusing the base class keeps `m_processor` (the single polymorphic `unique_ptr<ProcessingProcessor>` member in `ProcessingManager.hpp:129`) uniform across both dispatch paths — no second processor-holder member needed.

**Trade-off:** the buffer-repurposing (shader bytes in the "model" slot, vertex/index bytes in the "image" slot) is a naming/semantic stretch on the base interface's parameter names. This is acceptable for a "least-disruptive" v1 but is worth a documentation comment on `RenderProcessor::StartProcessing` explaining the reinterpretation, since a future reader skimming `processing_processor.hpp`'s doc comments (which say "Reference to task to get image split data") would otherwise be confused.

### Pattern 3: Runtime GLSL→SPIR-V compilation, not a build-time-only CLI step

**What:** shader source (`pass.get_shader().get_source()`, per schema `shader_config.source` at `gnus-processing-schema.json:326-356`) is fetched at job-execution time via the same IPFS/file/URL `source_uri_param` mechanism every other input already uses (`ProcessingManager.cpp:885-913`). This means the shader's GLSL text is not known until runtime — it arrives as fetched bytes per-subtask, exactly like a model file does today.

**Confirmed gap — no reusable GLSL→SPIR-V toolchain currently exists in this repo:**
- `thirdparty/Vulkan-Headers` and `thirdparty/Vulkan-Loader` are vendored and already wired via `find_package(Vulkan)` → `Vulkan::Vulkan` (`thirdparty/build/CommonTargets.cmake:363-391`; consumed at `SGProcessingManager/src/processors/CMakeLists.txt:58`). These provide the Vulkan API/loader only — no shader compiler.
- `thirdparty/MoltenVK/MoltenVKShaderConverter/glslang` exists, but it is a **nested submodule scoped to MoltenVK's own SPIR-V→Metal shader converter build**, not an exposed, independently linkable `glslang` target usable from `SGProcessingManager`.
- MNN's own Vulkan backend (`thirdparty/MNN/source/backend/vulkan/.../compiler/VulkanCodeGen.py`) is a code-generation scaffold for MNN's *own* precompiled operator shaders (baked into `AllShader.h` at MNN build time) — not a general-purpose runtime compiler, and not exposed outside MNN's internal backend.
- No standalone `glslang`, `shaderc`, or `SPIRV-Tools` submodule exists at `thirdparty/` top level.

**Implication:** since shader source arrives as runtime-fetched bytes (not a build-time artifact), a build-time-only `glslangValidator`/`glslc` CLI invocation does not fit the existing fetch pattern — `RenderProcessor` needs an **in-process, linkable** GLSL→SPIR-V compiler library, called at `StartProcessing()` time on the fetched bytes. This points to vendoring `glslang` (Khronos, BSD-3/MIT-style permissive — compatible with the project's all-permissive `thirdparty/` policy) as its own top-level submodule, built through the same ExternalProject/ImportedTarget pattern already used for Vulkan-Headers/Vulkan-Loader in `thirdparty/build/CommonTargets.cmake`. `shaderc` (Apache-2.0, also permissive) is the alternative — it wraps `glslang` + `SPIRV-Tools` behind a friendlier single-call C API (`shaderc_compile_into_spv`) and is the more common choice specifically because callers want "compile this GLSL string to SPIR-V bytes right now" rather than driving `glslang`'s own multi-step C++ API. Recommend `shaderc` for the smaller integration surface, unless the added `SPIRV-Tools`/`glslang` transitive dependency weight is a concern, in which case bare `glslang` is workable with more integration code.

**Trade-off:** compiling shaders at runtime, per-job, adds latency (glslang/shaderc compilation of a small vertex+fragment pair is typically single-digit milliseconds, negligible next to network/IPFS fetch time already in the critical path) and a new attack surface (untrusted GLSL source from job definitions reaching a compiler) — worth flagging for a later security-review pass, out of scope for this architecture research.

## Data Flow

### Render Pass Execution Flow

```
SubTask.json_data() (contains RENDER pass reference)
    ↓
ProcessingCoreImpl::ProcessSubTask (processing_core_impl.cpp:55-140, UNCHANGED)
    ↓
ProcessingManager::Process(ioc, chunkhashes, model, output_locations)
    ↓
index = GetInputIndex(...)  →  pass = get_passes()[index]  →  pass.get_type() == RENDER
    ↓
GetCidForProc — NEW branch: fetch shader source bytes + vertex/index buffer bytes
  via FileManager::LoadASync (cpp:885-913, reused verbatim)
    ↓
SetProcessorByPassType(RENDER) → m_processor = RenderProcessor
    ↓
RenderProcessor::StartProcessing(chunkhashes, proc, vertexIndexBytes, shaderBytes, parameters)
    ├─ compile GLSL → SPIR-V (shaderc/glslang, runtime)
    ├─ build pipeline from schema render_target/framebuffer config
    ├─ record + submit command buffer (own VkDevice, own queue)
    ├─ vkQueueWaitIdle / fence wait
    └─ copy color attachment → host-visible staging buffer → ProcessingResult.output_buffers
    ↓
Process() output-save path (cpp:696-817, UNCHANGED) — FileManager::SaveASync,
  IPFS dual-save, output_locations populated exactly as MNN passes already do
```

### Key Data Flows

1. **Schema → pipeline config:** the extended `shader_config`/new render fields drive Vulkan `VkGraphicsPipelineCreateInfo` construction directly inside `RenderProcessor` — no intermediate abstraction layer, since this milestone explicitly prohibits a new rendering engine.
2. **Output → existing save infra:** render output rides the exact same `ProcessingResult::output_buffers` → `FileManager::SaveASync` → IPFS/file path that MNN inference output already uses. This is the "bridge into `pass_io_binding`" the question asks about — it does not require new plumbing in `Process()`'s output section at all, only in how `RenderProcessor` populates the `output_buffers` pair.

## Scaling Considerations

Not meaningfully applicable in the traditional "N users" sense — this is a single-process compute-node executing one pass per `Process()` call, synchronously, per subtask. The relevant "scale" axis is **passes-per-job and concurrent-subtasks-per-node**, addressed under Coexistence Risk below rather than a user-scale table.

## Integration Points — Coexistence Risk Verdict

**Question:** does genuinely independent `VkInstance`/`VkDevice` ownership (RenderProcessor's own vs. MNN's fully-internal one) require any explicit synchronization/locking?

**Verdict: NO. No explicit synchronization or locking mechanism is required.** This is evidence-based, not a cautious guess:

1. **Vulkan has no instance-spanning global state by design.** Per-application state lives entirely inside a `VkInstance`; objects allocated from a `VkDevice` are private to that device and must not be used on any other device ([Vulkan Documentation Project — Fundamentals](https://docs.vulkan.org/spec/latest/chapters/fundamentals.html)). Two independent `VkInstance`/`VkDevice` pairs in one process do not share any handle, memory allocation, or dispatch state by construction — there is nothing to race over unless the application itself hands the same handle to two threads, which does not happen here (MNN never exposes its instance/device; `RenderProcessor` owns and never shares its own).
2. **Confirmed no exposure path exists today.** `MNN::VulkanInstance` (`thirdparty/MNN/source/backend/vulkan/component/VulkanInstance.hpp:17-37`) is a private implementation type inside MNN's internal `backend/vulkan/` tree — not included by, or reachable from, any public MNN header SGProcessingManager consumes (`MNN::MNN` target only). There is no code path today, and none planned, by which `RenderProcessor` and MNN could accidentally end up sharing a `VkInstance`/`VkDevice`/`VkQueue` handle.
3. **The Vulkan Loader's own global bookkeeping (ICD discovery/enumeration, per-instance dispatch table construction) is documented as internally thread-safe.** The loader "uses multiple mutexes to ensure thread-safe access to global instance and device state" ([KhronosGroup/Vulkan-Loader — LoaderInterfaceArchitecture.md](https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderInterfaceArchitecture.md)). This is the exact loader vendored at `thirdparty/Vulkan-Loader` and already linked as `Vulkan::Vulkan`. Even if MNN's lazy Vulkan-backend init and `RenderProcessor`'s init were ever called concurrently from separate threads (they are not, today — see point 4), the loader itself already serializes the shared bookkeeping (ICD enumeration cache, layer chain construction) internally; the application does not need to add its own lock around `vkCreateInstance`/`vkCreateDevice`.
4. **No concurrency exists today that would even exercise this.** `ProcessingManager::Process()` is called synchronously, once per subtask, from `ProcessingCoreImpl::ProcessSubTask` (`processing_core_impl.cpp:55-140`); the only asynchronous work in the current pipeline is network/file IO via `boost::asio::io_context::run()` (`cpp:805-806`, `855-856`), not the Vulkan-touching compute/render call itself. There is no code path in the current architecture where MNN's Vulkan init and a render pass's Vulkan init race on separate threads.

**Real coexistence considerations — operational, not correctness/synchronization:**

| Concern | Nature | Mitigation |
|---------|--------|------------|
| GPU scheduling contention | Two independent `VkDevice`s on the same physical GPU compete for compute units/VRAM bandwidth at the driver level if ever run concurrently — same as any two independent Vulkan applications sharing a GPU today | Document as expected; not a correctness bug. No code-level fix needed at v1 scope (today's pipeline doesn't run MNN inference and a render pass concurrently anyway) |
| Physical device selection consistency | If the host has multiple GPUs, MNN's backend and `RenderProcessor`'s own `vkEnumeratePhysicalDevices` selection logic could independently pick *different* physical devices | Policy/config decision (e.g., prefer device index 0, or make it explicitly configurable), not a threading bug — flag for RenderProcessor's headless-init design, not for this dispatch-plumbing work |
| Teardown ordering | Each owns full RAII lifecycle (`vkDestroyDevice`→`vkDestroyInstance`) independently; Vulkan has no process-wide instance-teardown handshake requirement | None needed — standard RAII destructor ordering suffices |
| Validation layers (if `VK_INSTANCE_LAYERS` env var set) | Loader inserts requested layers into **each** instance's own dispatch chain independently | Non-issue — per-instance, not shared |

**One nuance surfaced by direct source read (not disqualifying the verdict):** `MNN::VulkanInstance` has an `explicit VulkanInstance(VkInstance instance)` constructor (`VulkanInstance.hpp:20`), meaning MNN's *internal* implementation is technically capable of accepting an externally-supplied instance — but this constructor is not reachable through any public MNN API/header, and this milestone explicitly does not intend to patch MNN itself. Mentioned only to close the loop on "is MNN's Vulkan use *truly* unreachable" — yes, in practice, via the public surface this project links against.

## Anti-Patterns

### Anti-Pattern 1: Keying the new render dispatch on the same `int`-cast `m_processorFactories` map

**What people would do:** add `RegisterProcessorFactory(static_cast<int>(PassType::RENDER), ...)` because it looks like the path of least resistance (one map, one registration call style already established).
**Why it's wrong:** confirmed collision — `static_cast<int>(PassType::RENDER) == 3 == static_cast<int>(DataType::INT)` (see Pattern 1 above). This would silently misroute.
**Do this instead:** a separate `m_passFactories` map keyed on `PassType` directly (or an explicit `SetProcessorByPassType`/`RegisterPassProcessorFactory` pair mirroring the existing method names but operating on the new map).

### Anti-Pattern 2: Trying to fix `ParseBlockSize()` and add render-pass block-size computation as a single change

**What people would do:** while fixing the `pass.get_model().value()` crash (`cpp:649`), also try to make `ParseBlockSize()` return a meaningful value for render passes' vertex/index buffer sizes in the same patch.
**Why it's wrong:** the crash fix (guard against model-less passes) is a pure bug fix, independent of whatever the "block size" concept should mean for a render pass (likely vertex/index buffer byte length, not input-tensor block length) — conflating them risks under-scoping the crash fix or over-scoping a schema decision that hasn't been made yet.
**Do this instead:** fix the crash first (treat model-less passes as contributing 0 to `block_total_len`, or `continue`), land it independently, then decide render block-size semantics once the schema extension (render_target/buffer bindings) is finalized.

### Anti-Pattern 3: Reaching for `VK_EXT_headless_surface` or any WSI extension

**What people would do (carried over from bgfx-era thinking):** request `VK_KHR_surface`/`VK_KHR_win32_surface`/`VK_EXT_headless_surface` to "do headless properly," by analogy with how OpenGL/EGL needs a headless context extension.
**Why it's wrong:** `VK_EXT_headless_surface` exists only for tools that still want to exercise the `VkSurfaceKHR`/swapchain code path without a real window (e.g., CI systems testing swapchain logic). Since this milestone creates **no swapchain and no `VkSurfaceKHR` at all** — the render target is a plain `VkImage` with `VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT`, read back via a host-visible staging buffer — no WSI extension of any kind is needed on any platform.
**Do this instead:** request zero WSI/surface extensions; instance/device creation only needs core Vulkan (+ whatever debug/validation extensions are desired).

## Integration Points — Platform Scope

**Confirmed: genuinely headless/offscreen Vulkan (no `VkSurfaceKHR`, no swapchain, ever) is platform-agnostic in the way that matters here, and the prior bgfx research's WGL/EGL/GLX concerns do not carry over.**

- WGL (Windows), GLX/EGL (Linux), and NSOpenGL/EAGL context creation are OpenGL-specific windowing-system integration concerns — they exist because OpenGL contexts are inherently tied to a native window/pixel-format handle even for "hidden window" offscreen tricks. Vulkan's WSI layer (`VK_KHR_surface` + platform surface extensions) is **additive and optional** — a `VkInstance`/`VkDevice` created without requesting any `VK_KHR_*_surface` extension never touches platform windowing APIs at all.
- The prior bgfx-based research's platform considerations applied specifically to bgfx's **three-tier fallback** design, where the OpenGL tier needed a real (even if hidden/dummy) native window/context per platform. That entire class of concern is inapplicable here: this milestone has no OpenGL tier and no swapchain.
- **macOS/MoltenVK:** already vendored at `thirdparty/MoltenVK`. MoltenVK acts as a Vulkan ICD (translating Vulkan calls to Metal) and supports headless rendering to a plain `VkImage`-backed render target without requiring a `CAMetalLayer`/`NSView` — a Metal-backed surface is only needed if the caller explicitly creates a `VK_EXT_metal_surface`/`VK_MVK_macos_surface`, which this design does not do. So MoltenVK's presence in `thirdparty/` is sufficient; no additional macOS-specific windowing shim is required beyond what's already vendored.
- **Windows/Linux:** the vendored `Vulkan-Loader` (`thirdparty/Vulkan-Loader`, wired via `find_package(Vulkan)` → `Vulkan::Vulkan`, already linked at `SGProcessingManager/src/processors/CMakeLists.txt:58`) discovers whatever ICD driver is present on the host (NVIDIA/AMD/Intel/Mesa) exactly the same way regardless of windowing — again, no surface extension requested, no platform branch needed in `RenderProcessor` itself.
- **Net effect:** `RenderProcessor`'s Vulkan init code can be written once, with zero `#ifdef _WIN32`/`#ifdef __APPLE__` branches for windowing purposes. Any platform `#ifdef`s that do end up needed (if any) would be incidental build/link concerns already handled by the existing `SGProcessors` CMakeLists.txt's `if(APPLE)` framework-linking block (`CMakeLists.txt:63-84`), not new Vulkan-surface-related branching.

## Sources

- Direct source reads (HIGH confidence, primary source):
  - `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` (full file)
  - `SuperGenius/SGProcessingManager/include/processingbase/ProcessingManager.hpp` (full file)
  - `SuperGenius/SGProcessingManager/include/processors/processing_processor.hpp` (full file)
  - `SuperGenius/SGProcessingManager/src/processors/CMakeLists.txt` (full file)
  - `SuperGenius/SGProcessingManager/generated/PassType.hpp`, `DataType.hpp`
  - `SuperGenius/SGProcessingManager/gnus-processing-schema.json` (full file)
  - `SuperGenius/src/processing/impl/processing_core_impl.cpp:1-140`
  - `thirdparty/MNN/source/backend/vulkan/component/VulkanInstance.hpp` (full file)
  - `thirdparty/build/CommonTargets.cmake:363-391`, `thirdparty/build/cmake/kompute-fix.cmake`
  - `GeniusWallet/cmake/CommonBuildParameters.cmake:102-104`, `GeniusSDK/cmake/CommonBuildParameters.cmake:24-26`, `SuperGenius/build/CommonBuildParameters.cmake:253-255` (confirming `Vulkan::Vulkan` resolution path)
  - `thirdparty/` submodule inventory (`git submodule status`) confirming `Vulkan-Headers`, `Vulkan-Loader`, `MoltenVK` present at top level; no standalone `glslang`/`shaderc`/`SPIRV-Tools`
- External, cross-checked (MEDIUM confidence):
  - [Vulkan Documentation Project — Fundamentals](https://docs.vulkan.org/spec/latest/chapters/fundamentals.html) — object/device scoping, no cross-device handle sharing
  - [KhronosGroup/Vulkan-Loader — LoaderInterfaceArchitecture.md](https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderInterfaceArchitecture.md) — loader-internal mutex-guarded global instance/device bookkeeping
  - [Vulkan Documentation Project — Initialization](https://docs.vulkan.org/spec/latest/chapters/initialization.html) — `vkCreateInstance`/multi-instance behavior

---
*Architecture research for: sgproc-render workstream (hand-rolled headless Vulkan RenderProcessor)*
*Researched: 2026-07-29*
