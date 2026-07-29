# Phase 1: Vulkan Foundation & Dispatch Plumbing - Research

**Researched:** 2026-07-29
**Domain:** Headless Vulkan context creation/coexistence in a distributed batch-processing node (C++, CMake, git-submodule vendoring); `PassType`-keyed dispatch plumbing in `ProcessingManager`
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01 (Vulkan Bootstrap Approach):** Deferred to this planning step — user wants this decided with fuller information during `/gsd-plan-phase`, not locked at discussion time. Research recommends `vk-bootstrap` (MIT, new small vendored dependency) for the instance/device/queue boilerplate, specifically the `VK_KHR_portability_subset`/MoltenVK dance. Alternative is hand-rolling with zero new vendoring. Planner/researcher must surface this trade-off explicitly rather than silently picking one (see this document's Decision Point section).
- **D-02 (Physical Device Selection):** Deterministic scoring policy prioritizes: discrete GPU > integrated GPU > CPU/software, tie-broken by largest device-local VRAM heap size. Matches vk-bootstrap's default heuristic if D-01 lands on adopting it.
- **D-03 (No CPU/Software Fallback):** CPU/software rasterizers (llvmpipe etc.) are explicitly rejected in the production selection path — consistent with issue #7's "no CPU/software fallback" constraint. (A software Vulkan ICD may still be used in the CI-only hardware-independent test tier per Phase 4/DETV-03 — that's a separate, test-only code path, never product selection logic.)
- **D-04 (Concurrent Vulkan Init Synchronization — CTX-02):** Fix all 3 existing MNN Vulkan call sites, not just introduce a new lock for RenderProcessor. Only `MNN_Image` currently has a mutex (`mnn_vulkan_mutex`, function-local-static) guarding `createSession(MNN_FORWARD_VULKAN)`; `MNN_String` and `MNN_Volume` call `createSession(MNN_FORWARD_VULKAN)` with no synchronization at all today. This phase migrates `MNN_Image`'s existing mutex into a shared, process-wide, header-declared synchronization primitive and adds the same guard to `MNN_String`/`MNN_Volume`'s init paths plus `RenderProcessor`'s new init path. User confirmed this scope explicitly (recommended option).
- **D-05 (Verification via Stress Test):** Verify via an actual concurrent-init stress test (construct the render context and trigger MNN Vulkan inference concurrently from multiple threads, repeated enough to catch a race) — not just code review. This is not fully closed by research reasoning alone; the stress test is part of this phase's deliverable, not optional.
- **D-06 (RenderProcessor Context Lifecycle):** Lazy initialization — the headless Vulkan instance/device/queue for `RenderProcessor` is created on first render-type job arrival, not eagerly at `ProcessingManager`/node startup.
- **D-07 (Validation Layers — CTX-04):** Vulkan-ValidationLayers vendoring is explicitly deferred to v1.x — write this as a documented decision (not silently dropped), per REQUIREMENTS.md CTX-04. Locked at the requirements level; not re-discussed as a gray area.

### Claude's Discretion

- Exact shape/naming of the shared synchronization primitive (e.g. `VulkanInitGuard` singleton), where it's header-declared, and how `MNN_String`/`MNN_Volume` are refactored to use it — left to planner/researcher, as long as it satisfies D-04/D-05.
- Exact form of the `ParseBlockSize()` type-guard fix (DISP-01) and how block-length accounting behaves for model-less passes — mechanical crash fix, no vision-level ambiguity raised by user.
- Exact shape of the new `PassType`-keyed dispatch map (DISP-02) alongside the existing `DataType`-keyed `m_processorFactories` map — implementation detail, not user-facing.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within Phase 1 scope. (Vulkan bootstrap approach, D-01, is not deferred to a later *phase* — it's deferred to the *planning* step within this same phase, at the user's request, for more information before deciding.)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CTX-01 | Headless Vulkan instance/device/queue created for `RenderProcessor` — no `VkSurfaceKHR`, no swapchain, no WSI extensions on any platform (Windows, Linux, macOS via MoltenVK) | Standard Stack (Decision Point, both options), Architecture Pattern 2, Pitfall 2, Environment Availability (Vulkan loader/driver confirmed present on dev machine) |
| CTX-02 | A shared, process-wide Vulkan init-time synchronization primitive guards ALL Vulkan instance/device creation call sites in the process (MNN's existing 3 + `RenderProcessor`'s new one) | Architecture Pattern 3 (`VulkanInitGuard`), Pitfall 1, Don't Hand-Roll table, Security Domain (DoS mitigation) |
| CTX-03 | Explicit, deterministic physical-device selection policy for `RenderProcessor` (not "pick index 0") | Architecture Pattern 4, Pitfall 3, Decision Point (vk-bootstrap default selector gap) |
| CTX-04 | Vulkan-ValidationLayers vendoring is explicitly deferred to v1.x (documented decision, not silently dropped) | Standard Stack "Explicitly NOT Added" precedent from workstream STACK.md; this phase only needs the written decision, no new code |
| DISP-01 | `ParseBlockSize()` no longer crashes on model-less (render/compute) passes | Code Examples (`ParseBlockSize()` type-guard fix), Pitfall 4 |
| DISP-02 | `ProcessingManager::Process()` dispatches render passes via a new, separate `PassType`-keyed factory map — NOT the existing `DataType`-keyed map | Architecture Pattern 1, confirmed enum collision re-verified this session |
| DISP-03 | `CheckProcessValidity()` validates that a render pass has a shader config present | Code Examples (`CheckProcessValidity()` shader-presence check), Security Domain (V5 Input Validation) |
</phase_requirements>

## Summary

This phase does not require novel Vulkan-mechanics research — the workstream-level research (`research/SUMMARY.md`, `ARCHITECTURE.md`, `PITFALLS.md`, `STACK.md`) already did that work with file:line grounding, and this session re-verified every cited line number and code fact directly against the current `SuperGenius` submodule checkout (2026-07-29) — all citations still match exactly (`ProcessingManager.cpp:151` `case PassType::RENDER: break;`, `:649` unconditional `pass.get_model().value()`, `:671`/`:840` the `index` reuse pattern, `processing_processor_mnn_image.cpp:114-115` the file-scoped `mnn_vulkan_mutex`, `_string.cpp:152/155` and `_volume.cpp:582/586` the two unguarded MNN Vulkan call sites, `generated/PassType.hpp`/`DataType.hpp` the confirmed `RENDER==3==INT` enum collision, and `gnus-processing-schema.json:205-222` the existing `allOf`/`if`/`then` block that already requires a `shader` field for `compute`/`render` passes today). What remains for planning is: (1) resolve D-01 (vk-bootstrap vs. hand-rolled bootstrap) with concrete trade-off data, since CONTEXT.md explicitly deferred that call to planning time; (2) give the planner a concrete, implementable shape for the shared `VulkanInitGuard` synchronization primitive (D-04) and the concurrent-init stress test (D-05); and (3) confirm the dispatch-map and validity-check code shapes are mechanical, low-risk changes (they are).

This machine (the dev environment this research ran in) has a real Vulkan 1.4 loader and driver installed (`vulkaninfo` succeeds, reports a working ICD) — useful as a first manual smoke-test target for CTX-01 and the D-05 stress test before relying on CI.

**Primary recommendation:** Adopt **vk-bootstrap** (MIT, `charles-lunarg/vk-bootstrap`) for the `RenderProcessor` instance/device/queue bootstrap. It is a thin builder that hands back raw `VkInstance`/`VkPhysicalDevice`/`VkDevice`/`VkQueue` — it does not replace or abstract the Vulkan API surface, so it does not reopen the "no new GPU backend" concern that killed the prior bgfx attempt — and it already automates the exact `VK_KHR_portability_enumeration`/`VK_KHR_portability_subset` MoltenVK dance that is the highest-risk, easiest-to-silently-get-wrong part of CTX-01's cross-platform requirement. Implement the shared Vulkan init lock (D-04) as a function-local-static (`Meyers singleton` / "magic static") `std::mutex&` accessor in a new shared header, acquired via plain `std::lock_guard` at all 4 call sites — not `std::call_once`, since the guard must serialize every init call, not run once ever.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Headless Vulkan instance/device/queue creation (CTX-01) | Backend / Compute-node process | — | `RenderProcessor` is a sibling processor inside the same single-process distributed compute node as MNN — no client/server split, no browser/CDN tier applies |
| Vulkan init synchronization primitive (CTX-02) | Backend / Compute-node process | — | Process-wide, in-process concern; shared by MNN's 3 existing call sites and `RenderProcessor`'s new one, all in the same `SGProcessors` static library |
| Physical device selection policy (CTX-03) | Backend / Compute-node process | — | Pure local-machine hardware-enumeration logic, no external service involved |
| Validation-layers deferral decision (CTX-04) | Backend / Build system (CMake) | — | A documentation + build-flag decision, not a runtime-tier concern |
| `PassType`-keyed dispatch map (DISP-02) | Backend / `ProcessingManager` | — | `ProcessingManager` is the existing dispatch/orchestration layer; this is additive to its existing `DataType`-keyed dispatch |
| `ParseBlockSize()` crash fix (DISP-01) | Backend / `ProcessingManager` | — | Same component, pre-existing bug fix |
| `CheckProcessValidity()` shader-presence check (DISP-03) | Backend / `ProcessingManager` | — | Same component; schema-level validation already partially enforced (`gnus-processing-schema.json` `allOf`/`if`/`then` requires `shader` for `render`/`compute` passes) — this phase adds the matching C++-side runtime check |

No Browser/Client, Frontend-Server/SSR, or CDN/Static tiers exist in this project's architecture for this phase — `SGProcessingManager` is a headless backend library linked into a distributed compute-node binary.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Vulkan-Headers | `v1.3.302` (pinned, already vendored at `thirdparty/Vulkan-Headers`) [VERIFIED: direct repo read, `git describe` on submodule] | Vulkan API headers | Already vendored, already consumed via `Vulkan::Vulkan` CMake target — reuse, do not add a second copy |
| Vulkan-Loader | `v1.3.302` (pinned, already vendored at `thirdparty/Vulkan-Loader`) [VERIFIED: direct repo read] | ICD discovery/dispatch loader | Same target; `CommonTargets.cmake:363-391` already builds it with `BUILD_WSI_XCB_SUPPORT`/`XLIB`/`WAYLAND`/`DIRECTFB`/`SCREEN_QNX` all `OFF` — the loader is already built with most WSI surface backends disabled, reinforcing that this project's Vulkan usage is not meant to touch windowing surfaces [VERIFIED: direct repo read, `CommonTargets.cmake:373-388`] |
| MoltenVK | `v1.2.8`-adjacent (pinned, already vendored at `thirdparty/MoltenVK`) [VERIFIED: direct repo read] | Vulkan-over-Metal ICD for macOS | Already vendored for MNN's sake; acts as a normal ICD the loader discovers — no MoltenVK-specific code needed in `RenderProcessor` beyond the portability-subset dance |
| `Vulkan::Vulkan` CMake target | n/a (already exists) [VERIFIED: `SGProcessingManager/src/processors/CMakeLists.txt:58`, confirmed still present] | Already-resolved Vulkan headers+loader link target | `RenderProcessor` should link against this exact target, already used by the `SGProcessors` static library alongside `MNN::MNN` |

### Supporting (this phase's one candidate net-new dependency — see Decision Point below)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| vk-bootstrap | any recent `v1.3.3xx`/`v1.4.3xx`-line tag (MIT; upstream `HEAD` is `1.4.350` as of a May 2026 MSYS2 packaging snapshot) [CITED: github.com/charles-lunarg/vk-bootstrap, cross-checked against MSYS2/Conan Center listings — MEDIUM confidence, WebSearch-sourced, not yet registry-audited] | Instance/physical-device/device/queue bootstrap boilerplate, including the MoltenVK portability-subset dance | If D-01 is decided in favor of vk-bootstrap (recommended — see Decision Point) |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| vk-bootstrap | Hand-rolled `~150-250` line bootstrap code, zero new vendored dependency | Legitimate if the team wants to hold `thirdparty/` submodule count at zero net-new for this phase, or wants to control every line of MoltenVK-portability handling directly — but this is exactly the "gets silently missed and only breaks on macOS" surface (see Decision Point below) |
| vk-bootstrap's default `PreferredDeviceType::discrete` scoring | A fully custom scoring function (discrete > integrated > CPU/software, tie-broken by VRAM heap size, per D-02) | Required regardless of the D-01 outcome — vk-bootstrap's built-in selector does **not** implement VRAM-heap tie-breaking or explicitly reject CPU/software (`lavapipe`) devices by default; **CTX-03/D-02/D-03's scoring policy must be hand-written either way**, either as a custom `select_devices`/manual filter pass on top of vk-bootstrap's enumeration, or as fully custom code if D-01 goes hand-rolled |

### Decision Point: Vulkan Bootstrap Approach (D-01 — deferred by CONTEXT.md to this planning step)

CONTEXT.md explicitly defers this to planning with the instruction: *"Planner/researcher should surface this trade-off explicitly rather than silently picking one."* Concrete trade-off data follows so the planner can make an informed, written call (this is not re-litigating the decision — it is providing the specificity CONTEXT.md asked for).

**Option A: Adopt vk-bootstrap**

- **What it is:** A single header + single source file, MIT-licensed, dependency-free beyond Vulkan-Headers (already vendored) and C++17 (already the project baseline). It provides `vkb::InstanceBuilder`/`vkb::PhysicalDeviceSelector`/`vkb::DeviceBuilder` fluent builders that terminate in plain `VkInstance`/`VkPhysicalDevice`/`VkDevice`/`VkQueue` handles — `RenderProcessor` then uses ordinary `vkCreate*`/`vkCmd*` calls with those handles; no vk-bootstrap object appears anywhere in the render/command-recording path. [CITED: github.com/charles-lunarg/vk-bootstrap — MEDIUM confidence, WebSearch cross-checked against `STACK.md`'s prior direct-repo research pass]
- **What it automates that's genuinely risky to hand-roll:** MoltenVK requires the loader to be told, at `vkCreateInstance` time, to enumerate portability-conformant (non-fully-conformant) devices via `VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR` + the `VK_KHR_portability_enumeration` instance extension — MoltenVK's `VkPhysicalDevice` simply does not appear in `vkEnumeratePhysicalDevices()` without this flag. Then, if the selected physical device reports `VK_KHR_portability_subset` support, that device extension must also be enabled at `vkCreateDevice` time. [CITED: docs.vulkan.org VK_KHR_portability_subset refpage, cross-checked against KhronosGroup/Vulkan-Samples portability sample — MEDIUM confidence] vk-bootstrap's `InstanceBuilder`/`PhysicalDeviceSelector` check for and enable both automatically when building against a portability-only ICD; a hand-rolled implementation must replicate this exact two-step dance correctly on **Windows and Linux too** (the flag/extension check is unconditional, it just no-ops when the loader finds a fully-conformant native ICD) — the realistic failure mode of getting this wrong is "compiles and works on Windows/Linux, silently fails device creation only on macOS," which is expensive to catch without CI running on real macOS/MoltenVK hardware (a gap Phase 4/CI explicitly has to close separately).
- **Cost:** One new `thirdparty/` git submodule, one new `ExternalProject_Add` block in `CommonTargets.cmake` (a near-identical, small pattern to the existing Vulkan-Headers/Vulkan-Loader block at lines 363-391 [VERIFIED: direct repo read]) — no exotic build requirements, no additional transitive dependencies beyond what's already vendored. License MIT — no conflict with the project's permissive-only `thirdparty/` policy.
- **What it does NOT solve for this phase:** vk-bootstrap's `PhysicalDeviceSelector` defaults to `PreferredDeviceType::discrete` with `allow_any_gpu_device_type()` defaulting to `true` (falls back to any suitable type, including CPU/software, if no discrete GPU qualifies) [CITED: charles-lunarg/vk-bootstrap docs/getting_started.md — MEDIUM confidence, WebSearch]. This does **not** implement D-02's VRAM-heap-size tie-break between multiple discrete GPUs, and does **not** implement D-03's hard rejection of CPU/software rasterizers — both must be layered on top regardless of the D-01 outcome, either via vk-bootstrap's `select_devices()` (returns all suitable candidates for custom scoring) or fully custom `vkEnumeratePhysicalDevices` + `vkGetPhysicalDeviceProperties`/`vkGetPhysicalDeviceMemoryProperties` code if hand-rolled.

**Option B: Hand-roll instance/device/queue creation**

- **What it is:** Direct `vkCreateInstance`/`vkEnumeratePhysicalDevices`/`vkCreateDevice`/`vkGetDeviceQueue` calls against the already-vendored Vulkan-Headers/Vulkan-Loader, with the team writing the portability-subset/MoltenVK handling, extension/layer enumeration, and queue-family selection by hand.
- **Cost:** Zero new `thirdparty/` submodules, zero new CMake vendoring work this phase. Full control over every code path — easier to audit exhaustively in one place if the team's priority is minimizing `thirdparty/` submodule count (the project already vendors ~15+ submodules; this is a legitimate "hold the line" position, not an unreasonable one).
- **Risk:** The MoltenVK portability-subset dance (above) is the single most commonly-missed piece of hand-rolled Vulkan bootstrap code in cross-platform projects, specifically because it only matters on the one platform (macOS) most contributors don't build/test on day-to-day, and this project's CI has **zero macOS Vulkan signal today** [VERIFIED: `SuperGenius/.github/workflows/cmake.yml` — direct repo read via PITFALLS.md's original grounding, re-confirmed premise unchanged]. A missed portability flag manifests as `vkCreateInstance`/`vkEnumeratePhysicalDevices` returning zero suitable devices on macOS only, likely not caught until Phase 4's CI wiring work, or later.

**Recommendation:** Option A (vk-bootstrap), specifically *because* CTX-01 mandates macOS/MoltenVK support as a hard requirement and CI cannot yet verify that path (Phase 4 territory) — the failure mode Option B risks is silent and platform-specific in exactly the platform this project has the least test signal for today. This is a narrow, single-purpose addition (not a rendering-abstraction engine), so it does not reopen the "no new GPU backend" concern that disqualified bgfx. If the team weighs "zero net-new `thirdparty/` submodules" more heavily than this risk, Option B is legitimate — but should be paired with an explicit, early manual macOS build+run smoke test (not deferred entirely to Phase 4) to de-risk the silent-failure mode.

**This is not a locked decision — it is Decision D-01, explicitly deferred by CONTEXT.md to be decided during this planning step with the above information.**

**Installation (if Option A is chosen):**
```
# thirdparty/.gitmodules addition
[submodule "vk-bootstrap"]
    path = vk-bootstrap
    url = https://github.com/charles-lunarg/vk-bootstrap.git
```
```cmake
# thirdparty/build/CommonTargets.cmake addition — mirrors the existing
# Vulkan-Headers/Vulkan-Loader ExternalProject_Add block at lines 363-391
ExternalProject_Add(
    vk-bootstrap
    PREFIX vk-bootstrap
    SOURCE_DIR "${THIRDPARTY_DIR}/vk-bootstrap"
    CMAKE_CACHE_ARGS
    -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
    -DVulkanHeaders_DIR:PATH=<Vulkan-Headers install path>
    ${_CMAKE_COMMON_CACHE_ARGS}
    DEPENDS Vulkan-Headers
)
```
Exact `CMAKE_CACHE_ARGS` should be finalized against vk-bootstrap's actual `CMakeLists.txt` options during implementation — this is illustrative, following the established pattern.

## Package Legitimacy Audit

> This phase's only candidate net-new dependency is **vk-bootstrap**, and only if D-01 is decided in its favor. This is a C++ project using **git submodule vendoring**, not npm/pypi/crates — the automated `package-legitimacy check` registry gate (npm/pypi/crates only) does not apply to this ecosystem. Manual verification substitutes below, using GitHub-native trust signals (stars/forks/license/maintenance cadence/official-ecosystem cross-references) as the equivalent of registry download counts.

| Package | Registry | Age/Activity | Stars/Forks | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| vk-bootstrap | GitHub (git submodule, not a package registry) | Actively maintained; releases through `v1.4.350` per a May 2026 MSYS2 packaging snapshot [CITED: WebSearch, cross-checked against MSYS2/Conan Center — not independently re-verified against the GitHub API this session] | ~1.1k stars / 109 forks [CITED: WebSearch] | `github.com/charles-lunarg/vk-bootstrap` (individual maintainer, but the library is the de-facto standard bootstrap helper widely referenced across the Vulkan tutorial/sample ecosystem, incl. vulkan-tutorial.com and Khronos-adjacent community resources) | OK (with caveat) | Approved for planner consideration, gated behind a `checkpoint:human-verify` before the submodule is actually added — this session's verification is WebSearch-sourced (MEDIUM confidence per the source hierarchy), not a direct GitHub-API/registry check |

**Packages removed due to [SLOP] verdict:** none.
**Packages flagged as suspicious [SUS]:** none — vk-bootstrap is a well-established, widely-referenced library, but its GitHub-native trust signals were only WebSearch-verified this session (not cross-checked against the live GitHub API or a fresh `git clone`/tag list), so it is tagged `[ASSUMED]`-adjacent pending a direct check at implementation time. The planner should add a `checkpoint:human-verify` task before the `vk-bootstrap` submodule is actually vendored, confirming current release tag, license file contents, and that the upstream repo (not a fork/typosquat) is the one being pinned.

## Architecture Patterns

### System Architecture Diagram

```
SubTask.json_data() (contains a RENDER-type Pass)
        |
        v
ProcessingCoreImpl::ProcessSubTask()            [UNCHANGED this phase]
        |
        v
ProcessingManager::CheckProcessValidity()
   - switch(pass.get_type())
   - case RENDER: [DISP-03 THIS PHASE] require pass.get_shader() present,
                   fail with Error::PROCESS_INFO_MISSING if absent
        |
        v
ProcessingManager::ParseBlockSize()
   - [DISP-01 THIS PHASE] guard pass.get_model() before .value() —
     model-less (render/compute) passes contribute 0, do not crash
        |
        v
ProcessingManager::Process(ioc, chunkhashes, model, output_locations)
   - index = GetInputIndex(model.get_source())
   - pass  = processing_.get_passes()[index]          (existing positional
                                                          convention, cpp:840)
   - switch(pass.get_type())
        |                                    |
        | RENDER                             | everything else (existing path)
        v                                    v
   [DISP-02 THIS PHASE]                m_processorFactories[DataType(...)]
   NEW m_passFactories                  -> MNN_* processor family
   [PassType]-keyed map                 (owns MNN::Interpreter, Vulkan
   -> RenderProcessor (NEW)              fully internal, never exposed)
        |                                    |
        v                                    v
   RenderProcessor::StartProcessing()   MNN_*::StartProcessing()
   - [CTX-01 THIS PHASE] lazy-init      - createSession(MNN_FORWARD_VULKAN)
     own headless VkInstance/            guarded today only in _image.cpp
     VkPhysicalDevice/VkDevice/          by a FILE-SCOPED mnn_vulkan_mutex;
     VkQueue on first render job          _string.cpp/_volume.cpp UNGUARDED
   - [CTX-02 THIS PHASE] acquire        - [CTX-02 THIS PHASE] migrate to
     shared VulkanInitGuard before        acquire the SAME shared
     vkCreateInstance/vkCreateDevice/     VulkanInitGuard before their
     vkEnumeratePhysicalDevices           createSession(MNN_FORWARD_VULKAN)
   - [CTX-03 THIS PHASE] deterministic
     device-selection scoring
        |                                    |
        +------------- both return ----------+
                        |
                        v
        ProcessingResult { hash, output_buffers, output_locations }
                        |
                        v
        Process() output-save path (cpp:696-817) — FileManager::SaveASync,
        IPFS dual-save                                    [UNCHANGED this phase]
```

This phase delivers everything above marked `THIS PHASE`. Pipeline construction, draw calls, buffer upload, and readback (the rest of `RenderProcessor::StartProcessing`'s body) are explicitly out of scope — Phase 3 territory per REQUIREMENTS.md's traceability table. This phase's `RenderProcessor` only needs to prove context creation + coexistence + dispatch-reachability; a minimal stub `StartProcessing` (e.g., returning an empty/placeholder `ProcessingResult` once the context is confirmed created) is sufficient to satisfy CTX-01..04/DISP-01..03's success criteria.

### Recommended Project Structure

```
SuperGenius/SGProcessingManager/
├── include/
│   ├── processors/
│   │   └── processing_processor_render.hpp     # NEW — RenderProcessor decl,
│   │                                            #   sibling to mnn_*.hpp
│   └── processingbase/
│       ├── ProcessingManager.hpp                # + m_passFactories,
│       │                                        #   RegisterPassProcessorFactory,
│       │                                        #   SetProcessorByPassType
│       └── vulkan_init_guard.hpp                # NEW — shared process-wide
│                                                 #   VulkanInitGuard header
├── src/
│   ├── processingbase/
│   │   └── ProcessingManager.cpp                # + PassType branch in
│   │                                            #   Process()/GetCidForProc(),
│   │                                            #   guard in ParseBlockSize(),
│   │                                            #   shader-presence check in
│   │                                            #   CheckProcessValidity()
│   └── processors/
│       ├── processing_processor_render.cpp      # NEW — headless Vulkan
│       │                                        #   context creation/coexistence
│       ├── processing_processor_mnn_image.cpp   # migrate mnn_vulkan_mutex ->
│       │                                        #   shared VulkanInitGuard
│       ├── processing_processor_mnn_string.cpp  # ADD guard around existing
│       │                                        #   unguarded createSession call
│       ├── processing_processor_mnn_volume.cpp  # ADD guard around existing
│       │                                        #   unguarded createSession call
│       └── CMakeLists.txt                       # + processing_processor_render.cpp,
│                                                 #   (+ vk-bootstrap link if D-01
│                                                 #   adopts it)
```

### Pattern 1: `PassType`-keyed dispatch alongside `DataType`-keyed dispatch (additive)

**What:** Add `m_passFactories: unordered_map<PassType, factory>`, checked in `Process()` immediately after `index = GetInputIndex(...)` ([VERIFIED: `ProcessingManager.cpp:671`]), before falling through to the existing `m_processorFactories` (`DataType`-keyed) path.
**When to use:** Whenever `pass.get_type() == PassType::RENDER` (this phase); the pattern generalizes to any future non-`DataType`-driven pass type.
**Why a separate map, not reuse:** confirmed exact collision — `static_cast<int>(PassType::RENDER) == 3 == static_cast<int>(DataType::INT)` [VERIFIED: `generated/PassType.hpp` `enum class PassType : int { COMPUTE, DATA_TRANSFORM, INFERENCE, RENDER, RETRAIN }`, `generated/DataType.hpp` `enum class DataType : int { BOOL, BUFFER, FLOAT, INT, ... }` — both re-read directly this session, unchanged from prior research]. Reusing `m_processorFactories` with an `int`-cast `PassType` key would silently dispatch a RENDER pass into whatever's registered for `DataType::INT` (`MNN_Int` today).

**Example:**
```cpp
// Source: pattern derived directly from existing ProcessingManager.cpp:671-684,
// keeping the existing SetProcessorByName() call shape but adding a
// PassType-keyed branch ahead of it (illustrative — exact structure is
// Claude's Discretion per CONTEXT.md)
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

`GetCidForProc` ([VERIFIED: `ProcessingManager.cpp:824-840`]) needs a parallel branch: it currently unconditionally reads `.get_model().value().get_source_uri_param()` at line 840. For a RENDER pass there is no `model` — the schema requires `shader` instead ([VERIFIED: `gnus-processing-schema.json:205-222`, the `allOf`/`if`/`then` block requiring `["shader"]` for `type` in `["compute", "render"]`; `generated/Pass.hpp:91` `get_shader()` accessor confirmed present]). The render branch should read `pass.get_shader().value().get_source()` instead, reusing the same `FileManager`/`GetSubCidForProc` async-fetch machinery.

### Pattern 2: `RenderProcessor` implements the existing `ProcessingProcessor` interface — no new class hierarchy

**What:** `RenderProcessor : public sgns::sgprocessing::ProcessingProcessor`, implementing `StartProcessing(chunkhashes, proc, imageData, modelFile, parameters) -> ProcessingResult` [VERIFIED: `include/processors/processing_processor.hpp:37-41`, full interface re-read this session, unchanged].
**When to use:** Now — for this phase, a minimal `RenderProcessor::StartProcessing` only needs to (a) lazily create/reuse the headless Vulkan context on first call (CTX-01/D-06), (b) prove coexistence safety via the shared init guard (CTX-02), and (c) return a valid (even if placeholder/empty) `ProcessingResult` so the dispatch plumbing (DISP-02) has something real to route to. Pipeline/draw/readback logic is Phase 3.
**Example:**
```cpp
// Source: SGProcessingManager/include/processors/processing_processor.hpp:27-56 (interface, re-read 2026-07-29)
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
};
```

### Pattern 3: Shared `VulkanInitGuard` — a magic-static mutex, not `std::call_once`

**What:** One process-wide, header-declared synchronization primitive acquired via `std::lock_guard` at all 4 Vulkan instance/device-creation call sites (3 existing MNN + 1 new `RenderProcessor`), before any `vkCreateInstance`/`vkCreateDevice`/`vkEnumeratePhysicalDevices` call. Steady-state work (`vkQueueSubmit` on an already-created device/queue) does not need this lock.
**Why a magic static, not `std::call_once`:** `std::call_once`/`std::once_flag` guarantee a callable runs exactly once ever — that is the wrong primitive here, because the guard must be **acquired repeatedly**, once per Vulkan-init call, for the lifetime of the process (every MNN session creation and the one `RenderProcessor` context creation). The correct C++11+ pattern is a function-local `static std::mutex` (thread-safe-by-construction per the standard's "magic statics" guarantee — no double-checked locking needed) returned by reference, then a plain `std::lock_guard` at each call site. [CITED: cross-checked across multiple C++ concurrency references (modernescpp.com, softwarepatternslexicon.com, runebook.dev) — MEDIUM confidence, WebSearch, general C++ guidance not GNUS-specific]

**Example:**
```cpp
// Source: pattern synthesized from C++11 magic-static guarantees + this
// project's existing mnn_vulkan_mutex precedent (processing_processor_mnn_image.cpp:114-115)
// New header: include/processingbase/vulkan_init_guard.hpp
namespace sgns::sgprocessing
{
    inline std::mutex &VulkanInitMutex()
    {
        static std::mutex vulkan_init_mutex;   // magic static — thread-safe init, C++11+
        return vulkan_init_mutex;
    }
}

// Call site (processing_processor_mnn_image.cpp — migrated from the
// existing file-scoped mnn_vulkan_mutex):
{
    std::lock_guard<std::mutex> lock( sgns::sgprocessing::VulkanInitMutex() );
    auto session = mnnNet->createSession( netConfig );   // MNN_FORWARD_VULKAN
}

// Call site (processing_processor_mnn_string.cpp / _volume.cpp — NEW,
// these currently have zero synchronization around the identical call):
{
    std::lock_guard<std::mutex> lock( sgns::sgprocessing::VulkanInitMutex() );
    auto session = interpreter->createSession( config );  // MNN_FORWARD_VULKAN
}

// Call site (processing_processor_render.cpp — NEW, RenderProcessor's
// lazy-init path):
{
    std::lock_guard<std::mutex> lock( sgns::sgprocessing::VulkanInitMutex() );
    // vk-bootstrap (or hand-rolled) vkCreateInstance / vkEnumeratePhysicalDevices /
    // vkCreateDevice calls here
}
```

**Concurrent-init stress test (D-05) shape:** spawn N threads (N ≥ number of call sites, repeated across many iterations — "a single passing run proves nothing" per the workstream research), where some threads trigger `MNN_Image`/`MNN_String`/`MNN_Volume`'s `StartProcessing` (forcing `createSession(MNN_FORWARD_VULKAN)`) and others trigger `RenderProcessor`'s context creation, all launched near-simultaneously (e.g., a barrier/latch releasing all threads at once), repeated across many runs (tens to low hundreds, given this is a cheap in-process test with no GPU-work cost, only init cost). Assert zero crashes, zero `VK_ERROR_INITIALIZATION_FAILED`/`VK_ERROR_DEVICE_LOST`, across all repeats. This is a genuine test deliverable for this phase (D-05), not a design-only exercise.

### Pattern 4: Deterministic physical-device selection (CTX-03/D-02/D-03)

**What:** discrete GPU > integrated GPU > (CPU/software explicitly rejected in the production path), tie-broken by largest device-local VRAM heap size, via `vkGetPhysicalDeviceProperties().deviceType` and `vkGetPhysicalDeviceMemoryProperties()` heap enumeration (`VK_MEMORY_HEAP_DEVICE_LOCAL_BIT`).
**Why not vk-bootstrap's default selector alone:** vk-bootstrap's `PhysicalDeviceSelector` defaults to `PreferredDeviceType::discrete` but `allow_any_gpu_device_type()` defaults to `true` (silently falls back to CPU/software if no discrete/integrated GPU qualifies) [CITED: WebSearch, cross-checked against vk-bootstrap docs — MEDIUM confidence] — this directly conflicts with D-03's hard rejection requirement. If D-01 adopts vk-bootstrap, either call `require_dedicated_transfer_queue`-style strict filters plus `allow_any_gpu_device_type(false)`, or use `select_devices()` (returns all suitable candidates unranked) and apply this phase's own scoring/rejection function on top — do not rely on the builder's single `select()` call's default fallback behavior.
**Example (selection logic, bootstrap-agnostic):**
```cpp
// Source: pattern derived from Vulkan core API (vkGetPhysicalDeviceProperties,
// vkGetPhysicalDeviceMemoryProperties) — standard, not library-specific
bool IsAcceptable( VkPhysicalDeviceType type )
{
    // D-03: reject CPU/software rasterizers in the production path
    return type == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU
        || type == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU;
}

VkDeviceSize LargestDeviceLocalHeap( VkPhysicalDevice device )
{
    VkPhysicalDeviceMemoryProperties memProps;
    vkGetPhysicalDeviceMemoryProperties( device, &memProps );
    VkDeviceSize largest = 0;
    for ( uint32_t i = 0; i < memProps.memoryHeapCount; ++i )
        if ( memProps.memoryHeaps[i].flags & VK_MEMORY_HEAP_DEVICE_LOCAL_BIT )
            largest = std::max( largest, memProps.memoryHeaps[i].size );
    return largest;
}
// Scoring: discrete (rank 2) > integrated (rank 1); within same rank,
// larger LargestDeviceLocalHeap() wins; software/CPU/other = rejected outright.
```

### Anti-Patterns to Avoid

- **Keying the new render dispatch on the same `int`-cast `m_processorFactories` map:** confirmed collision (`PassType::RENDER == DataType::INT == 3`) — use a structurally separate `m_passFactories` map keyed on `PassType` itself.
- **Fixing `ParseBlockSize()` and defining render-pass block-size semantics in the same change:** the crash fix (guard against model-less passes, e.g. treat as contributing 0 or `continue`) is independent of what "block size" should mean for a render pass's vertex/index buffers — that's a Phase 2 schema decision, not this phase's concern.
- **Reaching for `VK_EXT_headless_surface`/`VK_KHR_surface`/any WSI extension:** not needed. Zero swapchain, zero surface, on any platform, ever. `VK_EXT_headless_surface` still transitively depends on `VK_KHR_surface` and exists for a different purpose (driver-conformance testing of the swapchain code path).
- **Leaving `mnn_vulkan_mutex` in place and adding a second, uncoordinated lock just for `RenderProcessor`:** this is the one shortcut the workstream research explicitly flags as "never acceptable" — it reintroduces the exact hazard the existing mutex was created to prevent, just at a new boundary, and does not close the `_string.cpp`/`_volume.cpp` gap D-04 requires closing.
- **Using `std::call_once` for the shared init guard:** wrong primitive — see Pattern 3. `call_once` runs its callable exactly once ever; the guard here must serialize *every* init call across the process's lifetime.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| MoltenVK `VK_KHR_portability_subset`/enumeration flag handling | Custom platform-detection + manual extension-string checks reimplemented from scratch | vk-bootstrap (if D-01 adopts it) — already implements this exact check-and-enable dance | This is the single most commonly missed piece of cross-platform Vulkan bootstrap code (see Decision Point) — a solved problem, not worth re-solving under this project's current CI blind spot for macOS |
| Thread-safe one-time static construction | Manual double-checked-locking mutex pattern | C++11+ magic-static (function-local `static`) | Double-checked locking is explicitly discouraged as unnecessary since C++11 — the language guarantees thread-safe static-local initialization already |
| Physical-device enumeration bookkeeping / ICD discovery thread-safety | A custom instance-creation serialization scheme beyond what's needed | Trust the Vulkan Loader's own internal mutex-guarded global bookkeeping for the *loader's* bookkeeping — but still add the app-level `VulkanInitGuard` for the *driver-level* concurrent-init hazard MNN's existing mutex defends against (these are two different concerns; loader-safety does not imply driver-safety, per the reconciled Decision Flag #1 finding) | Conflating "the loader is internally thread-safe" with "concurrent vkCreateInstance/vkCreateDevice across two independent Vulkan clients in one process is safe" is exactly the reasoning gap the workstream research's two architecture passes disagreed on — treat MNN's existing defensive mutex as the stronger, empirically-grounded signal |

**Key insight:** Nothing in this phase requires a general-purpose abstraction (allocator, rendering engine, cross-platform windowing shim). The two areas with real "don't hand-roll" value are narrowly scoped (MoltenVK bootstrap edge case, C++ static-init correctness) — everything else (dispatch map, validity checks, device-selection scoring) is direct, small, auditable code against APIs already vendored in this repo.

## Common Pitfalls

### Pitfall 1: Treating "independent VkInstance" as "isolated from MNN"
**What goes wrong:** Assuming `RenderProcessor`'s own `VkInstance`/`VkDevice` can't interfere with MNN's separate Vulkan context because the handles are independently owned. `vkCreateInstance`/`vkCreateDevice`/`vkEnumeratePhysicalDevices` are exactly the calls MNN's own `mnn_vulkan_mutex` already exists to guard — but that mutex is a function-local static in one file (`processing_processor_mnn_image.cpp:114-115`), so it does not protect `RenderProcessor`'s new init path, nor MNN's own unguarded `_string.cpp`/`_volume.cpp` call sites, against each other.
**Why it happens:** The existing mutex is undiscoverable from a render-feature vantage point — nobody adding `RenderProcessor` has a natural reason to go find it, and its own comment frames it as a stopgap.
**How to avoid:** Introduce the shared `VulkanInitGuard` (Pattern 3) and migrate all 4 call sites to it — this is D-04, already locked by CONTEXT.md, not optional.
**Warning signs:** Intermittent `VK_ERROR_INITIALIZATION_FAILED`/`VK_ERROR_DEVICE_LOST` only under concurrent load; driver-specific (NVIDIA/AMD/Mesa) crashes that don't reproduce in isolation.

### Pitfall 2: Reflexively pulling in WSI/swapchain machinery
**What goes wrong:** Reaching for `VK_KHR_surface`/`VK_KHR_swapchain`/`VK_EXT_headless_surface` "to do headless properly," by analogy with OpenGL/EGL patterns. `VK_EXT_headless_surface` is a narrower mechanism for driver-conformance testing that still depends on `VK_KHR_surface` — the exact WSI dependency a true offscreen job should avoid.
**Why it happens:** Nearly all public Vulkan tutorials/sample code are window/swapchain-first; MoltenVK's WSI-adjacent code paths have historically been its weakest area.
**How to avoid:** Never create a `VkSurfaceKHR`/`VkSwapchainKHR` on any platform. This phase only needs instance/device/queue creation — no image/framebuffer work yet (Phase 3) — so the risk surface this phase is limited to instance/device-extension requests: request zero WSI/surface extensions.
**Warning signs:** Any `Swapchain`/`SurfaceKHR` symbol appearing anywhere in new `RenderProcessor` code; `VK_KHR_surface` in the enabled-extensions list.

### Pitfall 3: Both Vulkan clients independently "auto-pick the best GPU" with no coordination
**What goes wrong:** `vkEnumeratePhysicalDevices` device ordering is not guaranteed stable across systems. If MNN's internal device selection and `RenderProcessor`'s own selection each independently implement "index 0" or diverge, on a multi-GPU node they can pick different physical devices, contending for VRAM/queue resources with neither side aware of the other.
**How to avoid:** Implement CTX-03's explicit, deterministic scoring function (Pattern 4) rather than "index 0" — this alone makes `RenderProcessor`'s choice reproducible run-to-run, independent of whether MNN's own selection is inspectable/alignable.
**Warning signs:** `VK_ERROR_OUT_OF_DEVICE_MEMORY` under concurrent load that doesn't reproduce with either workload alone; render/inference selecting different GPUs on a multi-GPU test machine.

### Pitfall 4: Reintroducing the `.value()`-on-unchecked-`boost::optional` crash shape
**What goes wrong:** `ParseBlockSize()`'s existing crash (`pass.get_model().value()` at `cpp:649`, unconditional) is one instance of a bug class — any new code touching this phase's own new/existing render-specific optional accessors (e.g. `pass.get_shader()`) that calls `.value()` without first checking `pass.get_type() == PassType::RENDER` will crash identically for a different field.
**Why it happens:** The generated `get_X()` accessors returning `boost::optional<T>` look like ordinary accessor usage; the crash only manifests when a pass of a *different* type reaches code assuming a specific type's fields are present.
**How to avoid:** Every new function touching `pass.get_shader()` or other render-specific fields must be inside a `case PassType::RENDER:` branch or explicitly check the type first — this applies to DISP-01's fix itself and DISP-03's new `CheckProcessValidity()` shader-presence check.
**Warning signs:** Any `.value()` call on a render-specific optional outside a type-checked branch; crashes on non-render passes after this phase's changes land.

## Code Examples

### `CheckProcessValidity()` shader-presence check (DISP-03)
```cpp
// Source: existing case block at ProcessingManager.cpp:151-152 (currently a
// silent no-op), pattern mirrors the existing INFERENCE case immediately above it
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
Note: `gnus-processing-schema.json`'s own `allOf`/`if`/`then` block already requires `shader` for `render`/`compute` passes at the JSON-schema level [VERIFIED: `gnus-processing-schema.json:205-222`] — this C++-side check is defense-in-depth against any path that bypasses schema validation (e.g. a hand-constructed `SgnsProcessing` object in a test), matching the existing `INFERENCE` case's same belt-and-suspenders pattern.

### `ParseBlockSize()` type-guard fix (DISP-01)
```cpp
// Source: existing unconditional code at ProcessingManager.cpp:649
for ( const auto &pass : passes )
{
    if ( !pass.get_model() )
    {
        continue;   // render/compute passes contribute 0 — block-size semantics
                    // for their vertex/index buffers is a Phase 2 schema decision
    }
    auto input_nodes = pass.get_model().value().get_input_nodes();
    // ... unchanged
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| MNN's Vulkan init guarded only by a file-scoped `mnn_vulkan_mutex` in one of three call sites | One process-wide, header-declared `VulkanInitGuard` shared by all 4 Vulkan-init call sites (3 MNN + `RenderProcessor`) | This phase (CTX-02/D-04) | Closes a pre-existing gap in MNN's own coverage, not just adding coverage for the new renderer |
| "Pick physical device index 0" (the naive default in most Vulkan tutorials, and MNN's likely internal behavior) | Explicit, deterministic scoring (discrete > integrated > reject CPU/software, VRAM-heap tie-break) for `RenderProcessor` | This phase (CTX-03/D-02/D-03) | Makes device selection reproducible across runs on the same hardware — a testable property, not "works on my machine" |
| `case PassType::RENDER: break;` silent no-op validation | Explicit shader-presence validation matching the `INFERENCE` case's pattern | This phase (DISP-03) | Render passes can no longer silently proceed with no shader config |

**Deprecated/outdated:** N/A — no prior version of this render path exists to deprecate (this is the v1.0 restart after the archived bgfx attempt, which is fully superseded, not partially).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | vk-bootstrap is MIT-licensed, ~1.1k stars, actively maintained through `v1.4.350` (May 2026 snapshot), and is the `charles-lunarg/vk-bootstrap` repo specifically (not a fork/typosquat) | Standard Stack, Package Legitimacy Audit | If wrong (e.g. license changed, repo is stale/abandoned, or a different repo is accidentally pinned), the planner's D-01 decision and vendoring plan would need revisiting — mitigated by the `checkpoint:human-verify` gate already flagged in the Package Legitimacy Audit |
| A2 | vk-bootstrap's `PhysicalDeviceSelector` defaults to `PreferredDeviceType::discrete` with `allow_any_gpu_device_type()` defaulting to `true` | Pattern 4, Decision Point Option A | If the actual default differs (e.g. `allow_any_gpu_device_type()` defaults to `false`, or the API has been renamed in a version newer than what was searched), D-03's "must layer custom rejection logic on top" guidance would need re-verification against the actual vendored version's headers at implementation time — low risk either way since the recommendation (write custom scoring regardless) holds under both defaults |
| A3 | Modern C++ (post-C++11) magic-static function-local `static std::mutex` is the correct primitive for a repeatedly-acquired shared lock, and `std::call_once` is the wrong tool for this use case | Pattern 3 | Low risk — this is well-established, widely cross-checked general C++ guidance, not a GNUS-specific or Vulkan-specific claim; multiple independent sources agree |
| A4 | The Vulkan Loader's own internal thread-safety does not extend to guaranteeing safety of concurrent `vkCreateInstance` calls at the ICD/driver level (i.e., loader-level thread-safety and the driver-level hazard MNN's mutex defends against are two different concerns) | Don't Hand-Roll table, Pitfall 1 | This is the crux of the workstream research's own unresolved "Decision Flag #1" — reconciled toward "trust MNN's existing defensive mutex over spec-only reasoning," but genuinely not closed by research alone. This is exactly why D-05's concurrent-init stress test is a required *test* deliverable this phase, not just a design decision — the stress test is the actual verification for this assumption |

## Open Questions

1. **Exact vk-bootstrap version/tag to pin, and its actual current `CMakeLists.txt` options**
   - What we know: MIT-licensed, upstream `HEAD` around `v1.4.350` as of a May 2026 snapshot, only requires Vulkan-Headers ≥1.1 (compatible with this repo's pinned 1.3.302).
   - What's unclear: The exact `CMAKE_CACHE_ARGS` needed for the `ExternalProject_Add` block (e.g. whether it needs a `VulkanHeaders_DIR` hint or discovers Vulkan-Headers differently) — this was not directly verified against a live checkout of vk-bootstrap's actual `CMakeLists.txt` this session.
   - Recommendation: Verify directly against a `git clone`/tag checkout at implementation time, immediately before writing the `CommonTargets.cmake` block — this is a 5-minute check, not a research gap that blocks planning.

2. **Whether MNN's own internal device-selection logic is inspectable/alignable with `RenderProcessor`'s scoring policy**
   - What we know: MNN's Vulkan backend (`thirdparty/MNN/source/backend/vulkan/`) is fully internal, not exposed via any public header this project consumes.
   - What's unclear: Whether MNN exposes any config surface (e.g. a device-index override) that could be set to align its selection with `RenderProcessor`'s scoring, avoiding the "two independent auto-pickers land on different GPUs" pitfall on multi-GPU nodes.
   - Recommendation: Not a blocker for this phase (CTX-03 only requires `RenderProcessor`'s own selection to be deterministic, not synchronized with MNN's) — worth a quick check during implementation if multi-GPU test hardware becomes available, otherwise document as a known limitation per the workstream research's own guidance.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| CMake | Build system for the whole project, incl. any new `vk-bootstrap` `ExternalProject_Add` block | Yes [VERIFIED: `cmake --version` run this session] | 3.29.2 | — |
| Git (submodule support) | Vendoring vk-bootstrap (if D-01 adopts it) | Yes [VERIFIED: `git --version` run this session] | 2.48.1 | — |
| Vulkan loader + a working ICD/driver | CTX-01 headless context creation, D-05 concurrent-init stress test — local manual smoke testing on this dev machine | Yes [VERIFIED: `vulkaninfo --summary` run this session, succeeded, reports Vulkan Instance Version 1.4.321 and a working ICD] | 1.4.321 (system-installed, separate from the project's vendored 1.3.302 loader — the project links its own vendored loader at build time, this is just confirming a real GPU/driver exists on this dev machine for manual testing) | If a given CI runner lacks a real GPU, Phase 4 (per workstream research) plans a software-ICD tier (Lavapipe/SwiftShader) for hardware-independent pipeline-construction testing only — not applicable to this phase's own deliverables, which don't touch pipeline/draw code yet |
| `thirdparty/Vulkan-Headers`, `Vulkan-Loader`, `MoltenVK` submodules | CTX-01 (all platforms) | Yes [VERIFIED: `git submodule status` run this session — all 3 present and checked out at the versions cited in `STACK.md`] | Vulkan-Headers `v1.3.302`, Vulkan-Loader `sdk-0.1.0` line at the same commit, MoltenVK `v1.0.28`-adjacent | — |
| vk-bootstrap submodule | CTX-01 (only if D-01 adopts it) | No — not yet vendored [VERIFIED: `git submodule status` shows no `vk-bootstrap` entry] | — | If D-01 lands on hand-rolled (Option B), no fallback needed — this dependency simply isn't introduced |
| macOS build/CI environment | CTX-01's MoltenVK requirement, D-01's portability-subset risk | Not verified this session (research ran on Windows) | — | Per workstream research, this is a known, pre-existing CI gap (Phase 4 territory, not this phase's to close) — this phase's own success criteria (CTX-01) require the headless context to *compile and be architecturally correct* for macOS/MoltenVK; an actual macOS build+run is Phase 4's explicit deliverable |

**Missing dependencies with no fallback:**
- None that block this phase's own deliverables — the macOS CI gap is a documented, pre-existing, explicitly-deferred-to-Phase-4 item, not a blocker for writing/reviewing the headless-context code this phase.

**Missing dependencies with fallback:**
- vk-bootstrap submodule (not yet vendored) — only needed if D-01 adopts Option A; trivially added following the existing Vulkan-Headers/Vulkan-Loader vendoring pattern.

## Security Domain

`security_enforcement` is enabled (ASVS Level 1, block on `high`) per `.planning/config.json`. This phase's scope (Vulkan context creation, dispatch plumbing) has a narrow security surface — the higher-risk surface (untrusted job-supplied GLSL/SPIR-V reaching `vkCreateShaderModule`) is explicitly Phase 2 territory (SHADER-01/02/03), not this phase.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | This phase has no auth surface — internal compute-node dispatch logic |
| V3 Session Management | No | N/A |
| V4 Access Control | No | N/A |
| V5 Input Validation | Yes | DISP-03's `CheckProcessValidity()` shader-presence check and DISP-01's model-presence guard are both input-validation controls against the schema-declared `Pass` structure — reject malformed/incomplete passes before they reach dispatch, consistent with the existing `INFERENCE` case's pattern. No new validation library needed; this is direct field-presence checking against already-parsed, schema-validated JSON. |
| V6 Cryptography | No | This phase introduces no cryptographic operations (hashing of render output is Phase 3/E2E territory, reusing the existing `sha256` convention already established for MNN output) |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Concurrent Vulkan instance/device creation causing driver-level corruption or crash (a Denial-of-Service-shaped risk against the compute node itself, not an external attacker surface) | Denial of Service | The shared `VulkanInitGuard` (CTX-02/D-04) — this is this phase's primary "threat" in the STRIDE sense, and it's already the phase's core deliverable, not an add-on |
| A render/compute pass with a missing/malformed `shader` field reaching `RenderProcessor` and causing an unguarded crash deep in Phase 3's future pipeline-construction code | Denial of Service | DISP-03's explicit `CheckProcessValidity()` shader-presence check, rejecting the job cleanly at validation time rather than letting it reach processor code |
| Job-supplied shader source/raw SPIR-V reaching `vkCreateShaderModule` without validation | Tampering / Denial of Service | **Explicitly out of scope for this phase** — `shader_config.type` already allows `"spirv"` today at the schema level [VERIFIED: `gnus-processing-schema.json:326-356`], but this phase does not compile or load shader bytes at all (no `vkCreateShaderModule` call exists yet). Flagging here only so the planner does not mistakenly believe this phase's shader-presence check (DISP-03) is a substitute for Phase 2's mandatory `spirv-val` gate — it is not; DISP-03 only checks that a `shader` field is *present*, not that its contents are safe. |

## Sources

### Primary (HIGH confidence)
- Direct repository reads, all re-verified 2026-07-29 against the current `SuperGenius` submodule checkout in this session: `SGProcessingManager/src/processingbase/ProcessingManager.cpp` (lines 116, 131-159, 643-662, 664-695, 824-840 — all confirmed unchanged from prior workstream research), `SGProcessingManager/include/processingbase/ProcessingManager.hpp` (full file), `SGProcessingManager/include/processors/processing_processor.hpp` (full file), `SGProcessingManager/generated/PassType.hpp`, `DataType.hpp`, `Pass.hpp` (confirmed `get_shader()` accessor present), `SGProcessingManager/gnus-processing-schema.json` (lines 195-230, 320-356), `SGProcessingManager/src/processors/CMakeLists.txt` (full file, confirmed `Vulkan::Vulkan`/`MNN::MNN` link), `SGProcessingManager/src/processors/processing_processor_mnn_image.cpp` (lines 100-120, confirmed `mnn_vulkan_mutex` at 114-115), `_string.cpp` (lines 150-156, confirmed unguarded), `_volume.cpp` (lines 580-588, confirmed unguarded), `thirdparty/.gitmodules` (Vulkan-Headers/Vulkan-Loader/MoltenVK entries), `thirdparty/build/CommonTargets.cmake` (lines 355-395, confirmed existing ExternalProject_Add pattern and WSI-disabled Vulkan-Loader build flags), `git submodule status`/`git describe` on `Vulkan-Headers`/`Vulkan-Loader`/`MoltenVK` (confirmed pinned versions), `vulkaninfo --summary` (confirmed a working Vulkan 1.4.321 loader/ICD on this dev machine)
- `.planning/workstreams/sgproc-render/research/{SUMMARY,ARCHITECTURE,PITFALLS,STACK}.md` — prior workstream-level research, all file:line citations cross-checked and confirmed accurate this session

### Secondary (MEDIUM confidence)
- https://github.com/charles-lunarg/vk-bootstrap — repo/license/star-count verification (WebSearch, cross-checked against MSYS2 packaging and Conan Center listings)
- https://docs.vulkan.org/refpages/latest/refpages/source/VK_KHR_portability_subset.html — portability-subset extension semantics
- https://github.com/KhronosGroup/Vulkan-Samples/tree/main/samples/extensions/portability — canonical portability-enumeration usage pattern
- https://github.com/charles-lunarg/vk-bootstrap/blob/main/docs/getting_started.md — `PhysicalDeviceSelector` default behavior (`PreferredDeviceType::discrete`, `allow_any_gpu_device_type()` default `true`)
- Vulkan-Loader `LoaderInterfaceArchitecture.md` (github.com/KhronosGroup/Vulkan-Loader) — loader-internal mutex-guarded global state (re-confirmed, cross-referenced against a real-world NVIDIA-driver repeated-instance-creation forum report, showing loader-level thread-safety does not by itself guarantee driver-level safety under repeated/concurrent init)
- Multiple independent C++ concurrency references (modernescpp.com, softwarepatternslexicon.com, runebook.dev) — magic-static vs. `std::call_once` guidance, cross-checked, general C++ knowledge not GNUS-specific

### Tertiary (LOW confidence)
- None — every claim in this document is either a direct repo read (re-verified this session) or a WebSearch claim cross-checked against at least one additional independent source, per the Assumptions Log above where residual uncertainty remains.

## Metadata

**Confidence breakdown:**
- Standard stack / Decision Point (D-01): HIGH for what's already vendored (Vulkan-Headers/Loader/MoltenVK, direct repo reads); MEDIUM for vk-bootstrap's own trade-off specifics (WebSearch-sourced, cross-checked, not yet registry/API-verified — see Package Legitimacy Audit gate)
- Architecture (dispatch map, RenderProcessor pattern, shared init guard): HIGH — every integration point re-verified against current source this session, all line numbers match the prior workstream research exactly
- Pitfalls: HIGH for repo-grounded findings (re-verified); MEDIUM for general Vulkan-loader/driver ecosystem claims (cross-checked web sources)

**Research date:** 2026-07-29
**Valid until:** 2026-08-28 (30 days — this phase's Vulkan/C++ domain is stable; re-verify if `SuperGenius` submodule pointer moves significantly, or if vk-bootstrap's upstream version drifts materially before implementation)
