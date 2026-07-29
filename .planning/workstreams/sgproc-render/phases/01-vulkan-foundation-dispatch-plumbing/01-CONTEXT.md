# Phase 1: Vulkan Foundation & Dispatch Plumbing - Context

**Gathered:** 2026-07-29
**Status:** Ready for planning

<domain>
## Phase Boundary

A headless Vulkan context can be created for `RenderProcessor` safely alongside MNN's existing Vulkan usage, and `ProcessingManager` can route render passes through a dedicated, non-crashing dispatch path. This phase delivers Vulkan mechanics and dispatch plumbing only — no schema extension (Phase 2), no actual pipeline/draw/readback (Phase 3), no CI wiring (Phase 4). Requirements: CTX-01, CTX-02, CTX-03, CTX-04, DISP-01, DISP-02, DISP-03.

</domain>

<decisions>
## Implementation Decisions

### Vulkan Bootstrap Approach
- **D-01:** Deferred to planning phase — user wants this decided with fuller information during `/gsd-plan-phase`, not locked here. Research recommends `vk-bootstrap` (MIT, new small vendored dependency) for the instance/device/queue boilerplate, specifically the `VK_KHR_portability_subset`/MoltenVK dance. Alternative is hand-rolling with zero new vendoring. **Planner/researcher should surface this trade-off explicitly rather than silently picking one.**

### Physical Device Selection (CTX-03)
- **D-02:** Deterministic scoring policy prioritizes: discrete GPU > integrated GPU > CPU/software, tie-broken by largest device-local VRAM heap size. Matches vk-bootstrap's default heuristic if D-01 lands on adopting it.
- **D-03:** CPU/software rasterizers (llvmpipe etc.) are explicitly rejected in the production selection path — consistent with issue #7's "no CPU/software fallback" constraint. (A software Vulkan ICD may still be used in the CI-only hardware-independent test tier per Phase 4/DETV-03 — that's a separate, test-only code path, never product selection logic.)

### Concurrent Vulkan Init Synchronization (CTX-02)
- **D-04:** Fix all 3 existing MNN Vulkan call sites, not just introduce a new lock for RenderProcessor. Codebase check during discussion found only `MNN_Image` (`processing_processor_mnn_image.cpp:114-115`) currently has a mutex (`mnn_vulkan_mutex`, function-local-static) guarding `createSession(MNN_FORWARD_VULKAN)`; `MNN_String` (`processing_processor_mnn_string.cpp:155`) and `MNN_Volume` (`processing_processor_mnn_volume.cpp:586`) call `createSession(MNN_FORWARD_VULKAN)` with **no synchronization at all** today. This phase migrates `MNN_Image`'s existing mutex into a shared, process-wide, header-declared synchronization primitive (per research's `VulkanInitGuard`-style recommendation) and adds the same guard to `MNN_String`/`MNN_Volume`'s init paths plus `RenderProcessor`'s new init path. This is a wider blast radius than "just add RenderProcessor" — it touches 2 existing production MNN processor files to close a pre-existing gap. User confirmed this scope explicitly (recommended option).
- **D-05:** Verify via an actual concurrent-init stress test (construct the render context and trigger MNN Vulkan inference concurrently from multiple threads, repeated enough to catch a race) — not just code review. This is not fully closed by research reasoning alone (research's Decision Flag #1); the stress test is part of this phase's deliverable, not optional.

### RenderProcessor Context Lifecycle
- **D-06:** Lazy initialization — the headless Vulkan instance/device/queue for `RenderProcessor` is created on first render-type job arrival, not eagerly at `ProcessingManager`/node startup. Rationale: most distributed compute nodes spend their time on MNN inference/retrain jobs and may never see a render pass; lazy init avoids holding GPU resources idle on those nodes.

### Validation Layers (CTX-04)
- **D-07:** Vulkan-ValidationLayers vendoring is explicitly deferred to v1.x — write this as a documented decision (not silently dropped), per REQUIREMENTS.md CTX-04. This was locked at the requirements level; not re-discussed as a gray area.

### Claude's Discretion
- Exact shape/naming of the shared synchronization primitive (e.g. `VulkanInitGuard` singleton), where it's header-declared, and how `MNN_String`/`MNN_Volume` are refactored to use it — left to planner/researcher, as long as it satisfies D-04/D-05.
- Exact form of the `ParseBlockSize()` type-guard fix (DISP-01) and how block-length accounting behaves for model-less passes — mechanical crash fix, no vision-level ambiguity raised by user.
- Exact shape of the new `PassType`-keyed dispatch map (DISP-02) alongside the existing `DataType`-keyed `m_processorFactories` map — implementation detail, not user-facing.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & Roadmap
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` — CTX-01..04, DISP-01..03 locked requirements for this phase
- `.planning/workstreams/sgproc-render/ROADMAP.md` — Phase 1 success criteria, phase ordering rationale

### Research
- `.planning/workstreams/sgproc-render/research/SUMMARY.md` — Decision Flags #1 (init sync) and #2 (shaderc vs glslang, Phase 2 concern but background-relevant); Phase 1 rationale, pitfalls 1-3, sources
- `.planning/workstreams/sgproc-render/research/ARCHITECTURE.md` — coexistence/dispatch integration point detail (file:line grounding)
- `.planning/workstreams/sgproc-render/research/PITFALLS.md` — `mnn_vulkan_mutex` finding, MNN-vs-MNN concurrent-init gap
- `.planning/workstreams/sgproc-render/research/STACK.md` — vk-bootstrap/Vulkan-Headers/Loader/MoltenVK version and license grounding

### Project Context
- `.planning/PROJECT.md` §"Workstream: sgproc-render" — restart rationale (bgfx superseded), issue #7 constraint framing
- `.planning/milestones/ws-sgproc-render-2026-07-29/` — archived bgfx-based v1.0 attempt (superseded, not to be reused, but documents why bgfx failed the "no new GPU backend" constraint)

No external ADRs/specs beyond the above — requirements fully captured in REQUIREMENTS.md and this discussion.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Vulkan::Vulkan` CMake target (already linked in `SuperGenius/SGProcessingManager/src/processors/CMakeLists.txt`) — reuse directly, do not add a second Vulkan loader/headers copy
- Already-vendored `thirdparty/Vulkan-Headers`, `thirdparty/Vulkan-Loader`, `thirdparty/MoltenVK` submodules (`thirdparty/.gitmodules:70-78`)
- Existing `ProcessingProcessor` base interface (`include/processors/processing_processor.hpp`) — `RenderProcessor` should implement this same interface as a sibling to the MNN processor family

### Established Patterns
- `RegisterProcessorFactory(int, factory_fn)` / `SetProcessorByName(int)` in `ProcessingManager.hpp:59-120` — existing `DataType`-keyed factory-map dispatch pattern. **Confirmed enum collision**: `PassType::RENDER == 3` (`generated/PassType.hpp:26`, `enum class PassType : int { COMPUTE, DATA_TRANSFORM, INFERENCE, RENDER, RETRAIN }`) equals `DataType::INT == 3` (`generated/DataType.hpp:19`) — DISP-02's new `PassType`-keyed map MUST be structurally separate from `m_processorFactories`, not reuse it.
- MNN Vulkan usage pattern: `config.type = MNN_FORWARD_VULKAN; interpreter->createSession(config);` — appears in `processing_processor_mnn_image.cpp:152/155`, `processing_processor_mnn_string.cpp` (~line 152/155), `processing_processor_mnn_volume.cpp` (~line 582/586). Only the image path currently has `static std::mutex mnn_vulkan_mutex; std::lock_guard lock(mnn_vulkan_mutex);` immediately before session creation — a function-local static mutex, not process-wide.

### Integration Points
- `ProcessingManager::CheckProcessValidity()` (`ProcessingManager.cpp:131-159`) — `case PassType::RENDER: break;` is currently a silent no-op (line 151-152); DISP-03 requires this to validate shader-config presence
- `ProcessingManager::ParseBlockSize()` (`ProcessingManager.cpp:643-662`) — line 649 `pass.get_model().value()` is unconditional; crashes on any render/compute pass with no model. DISP-01's type-guard fix goes here.
- `ProcessingManager::Process()` (`ProcessingManager.cpp:664+`) — currently dispatches purely by input `DataType` via `SetProcessorByName(static_cast<int>(processing_.get_inputs()[index.value()].get_type()))` (line 682); DISP-02 adds a new, separate `PassType`-keyed dispatch path here, routed by `pass.get_type()` rather than input `DataType`

</code_context>

<specifics>
## Specific Ideas

No particular UI/UX-style references — this is backend infrastructure. The specific, concrete grounding facts captured during discussion (mutex-guard gap, enum collision value, dispatch map structure) are recorded above in `<code_context>` and `<decisions>`.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within Phase 1 scope. (Vulkan bootstrap approach, D-01, is not deferred to a later *phase* — it's deferred to the *planning* step within this same phase, at the user's request, for more information before deciding.)

</deferred>

---

*Phase: 1-Vulkan Foundation & Dispatch Plumbing*
*Context gathered: 2026-07-29*
