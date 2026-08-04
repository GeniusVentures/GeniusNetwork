# Phase 06: Capability & Validation Foundation - Context

**Gathered:** 2026-08-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Before a job is executed, the node validates whether it CAN execute it — across all pass types, Vulkan features, model formats, and resource requirements — returning specific unmet-requirement reasons via a new standalone `CapabilityValidator` class. Vulkan validation layers are a best-effort, debug-only toggle (no vendoring). Two sub-streams: CAP (Capability Validation, CAP-01..06) and VVAL (Vulkan Validation Layers, VVAL-01..04).

**Depends on:** v1.0 foundation (Vulkan context, schema, RenderProcessor, shaderc/SPIRV-Tools, MNN Vulkan migration from Phase 01.1).

</domain>

<decisions>
## Implementation Decisions

### CAP — CanExecute Architecture
- **D-01:** `CapabilityValidator` — new standalone class, internally constructed by `ProcessingManager` (not injected). Own header/impl in `SGProcessingManager/src/`.
- **D-02:** Validate **before claiming work** from the network — prevents a node from claiming jobs it cannot execute.
- **D-03:** **Async with callback** pattern — matches `ProcessingManager`'s existing async conventions.
- **D-04:** Internally constructed by `ProcessingManager` (not injected).

### CAP — Result Shape
- **D-05:** **C++ struct only** — no protobuf message in SGProcessingManager. Caller (SuperGenius/gRPC layer) serializes for wire if needed.
- **D-06:** **Flat list** of `UnmetRequirement` structs, each tagged with a category enum (`Vulkan`, `MNN`, `PassType`, `Resource`). Simple and flexible.
- **D-07:** Acceptance returns **minimal**: `executable=true` + selected executor ID. Full capability snapshot is not returned on success.
- **D-08:** Executor identity = **hash of capability snapshot** (Vulkan device properties + driver version + MNN backend info) — deterministic stability guarantee for CAP-06.

### CAP — Capability Discovery
- **D-09:** **Startup query + cache** — query Vulkan device props, MNN backend registry, and registered executors once at startup. `CanExecute` checks against the cached snapshot.
- **D-10:** **Reuse existing `VkPhysicalDevice`** — no temporary Vulkan instance. `CapabilityValidator` queries the same device used by `RenderProcessor`/MNN, under the shared `VulkanInitMutex`.
- **D-11:** **Registry-based** MNN capability discovery — each registered MNN processor declares its supported formats/quantizations at registration time. `CapabilityValidator` queries the registry, not MNN's internal API directly.
- **D-12:** **Startup only** — no runtime refresh. Matches CAP-06's stable-identity requirement. If hardware changes, the node restarts.

### CAP — Resource Validation Depth (CAP-05)
- **D-13:** **No CPU instruction checks** — all MNN processors are on Vulkan backend after Phase 01.1 (MIGR-01). No current consumer for CPU feature checks.
- **D-14:** **Critical Vulkan limits subset** — validate against limits that would actually cause job failure: `maxImageDimension2D`, `maxBufferSize`, `maxPushConstantsSize`, `maxUniformBufferRange`, `maxColorAttachments`, `maxPerStageResources`, `maxMemoryAllocationCount`.
- **D-15:** **Estimate and check GPU memory** against `VkPhysicalDeviceMemoryProperties` heap sizes — prevents OOM mid-job. Render target + buffer + pipeline memory estimated from declared dimensions and formats.
- **D-16:** **Check estimated disk space** for output artifacts — prevents job failure mid-write on a full disk.

### CAP — Relationship to CheckProcessValidity
- **D-17:** **Sits alongside** `CheckProcessValidity()` — structural validation stays as-is. `CanExecute` is a separate, later step. Both must pass.
- **D-18:** **Structure first, then capability** — cheap `CheckProcessValidity` (schema fields) runs before expensive `CanExecute` (hardware queries).
- **D-19:** **Caller's responsibility** to call `CanExecute` before `Process()`. The scheduler validates before claiming work; `Process()` trusts the caller validated.

### VVAL — Validation Layer Source (VVAL-01, VVAL-02, VVAL-04)
- **D-20:** **Debug-only, best-effort** — validation layers enabled if available on the system, silently skipped if not. **No vendoring.** Overrides VVAL-01's literal "vendored as thirdparty/ submodule(s)" wording. Rationale: layers are a development tool, not a runtime requirement; Android NDK ships them, desktop requires Vulkan SDK, iOS uses MoltenVK's built-in logging.
- **D-21:** **Load by name** via vk-bootstrap's `enable_validation_layers()` — standard `VK_LAYER_KHRONOS_validation`. Vulkan loader resolves the layer if installed.
- **D-25 (VVAL-04):** Decision documented **in this CONTEXT.md** — closes the CTX-04 deferral from Phase 1. No separate ADR needed.

### VVAL — Toggle Granularity (VVAL-03)
- **D-22:** **RenderProcessor only** — validation layers apply only to `RenderProcessor`'s `VkInstance`. MNN's Vulkan instances are untouched.
- **D-23:** **Global flag** — one flag controls all SGProcessingManager validation layer usage.

### VVAL — Toggle Mechanism (VVAL-03)
- **D-24:** **CMake option** `-DENABLE_VULKAN_VALIDATION` — defaults ON in Debug builds, OFF in Release. No runtime toggle without rebuild.

### Claude's Discretion
- Exact `UnmetRequirement` struct field layout and category enum member names.
- Exact Vulkan device limit fields to query (beyond the critical subset named in D-14).
- GPU memory estimation formula (render target bytes + buffer bytes + pipeline overhead).
- Disk space check implementation (platform-specific `statvfs`/`GetDiskFreeSpace` or portable abstraction).
- `CapabilityValidator`'s exact async callback signature and integration with `ProcessingManager`'s initialization sequence.
- Hash function for executor identity snapshot (SHA-256 vs. a lighter hash — consistency with existing hashing conventions).
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & Roadmap
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` — CAP-01..06, VVAL-01..04 locked requirements for this phase
- `.planning/workstreams/sgproc-render/ROADMAP.md` — Phase 06 success criteria. **Note:** VVAL-01's literal "vendored as thirdparty/ submodule(s)" wording is superseded by D-20 above (best-effort, no vendoring).

### Prior Phase Context (v1.0)
- `.planning/workstreams/sgproc-render/phases/01-vulkan-foundation-dispatch-plumbing/01-CONTEXT.md` — CTX-01 (RenderProcessor's independent VkInstance/VkDevice — D-10's reuse-of-existing-device relies on this), CTX-02 (shared `VulkanInitMutex` — D-10's capability queries acquire this), CTX-03 (deterministic device selection — capability queries use same policy), CTX-04 (validation layers deferred — closed by D-25), D-04/D-05 (mutex + concurrent-init stress test)
- `.planning/workstreams/sgproc-render/phases/01.1-cmake-vk-bootstrap-discovery-mnn-cpu-to-vulkan-processor-mig/01.1-CONTEXT.md` — MIGR-01 (all MNN processors on Vulkan — grounds D-13's no-CPU-checks decision)
- `.planning/workstreams/sgproc-render/phases/02-schema-extension-shader-spir-v-validation-pipeline/02-CONTEXT.md` — SHADER-01/02 (shaderc + spirv-val — capability checks must be aware of shader compilation requirements)
- `.planning/workstreams/sgproc-render/phases/03-renderprocessor-implementation-determinism/03-CONTEXT.md` — D-18..D-24 (memory allocation, lifecycle, D-25..D-28 error handling — capability checks must know what resources a render pass consumes to estimate memory per D-15)
- `.planning/workstreams/sgproc-render/phases/04-cross-platform-build-ci-end-to-end-verification/04-CONTEXT.md` — D-32 (GPU-probe pattern — D-09/D-10 follow the same "discover, don't assume" philosophy)
- `.planning/workstreams/sgproc-render/phases/05-android-ios-platform-compatibility-thirdparty-library-builds/05-CONTEXT.md` — D-01..D-04 (library builds for mobile — validation layers need to be considered in the same build matrix but are best-effort per D-20)

### Source of Truth (current state, pre-this-phase)
- `SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp:19-23` — `RenderProcessor::IsAcceptable`'s existing device-type filter (DISCRETE_GPU/INTEGRATED_GPU) — capability checks must use the same device selection policy
- `SuperGenius/SGProcessingManager/src/processing_manager.cpp` — `CheckProcessValidity()` and `Process()` dispatch — the code paths D-17/D-18/D-19 sit alongside
- `SuperGenius/SGProcessingManager/include/processors/processing_processor.hpp:19-25` — `ProcessingResult` struct (gained error field in Phase 3, D-25) — `CanExecute` result shape should follow similar structured-error conventions
- `SuperGenius/SGProcessingManager/include/processingbase/vulkan_init_guard.hpp` — `VulkanInitMutex()` — D-10's capability queries must acquire this
- `thirdparty/vk-bootstrap/` — vk-bootstrap API for `enable_validation_layers()` — D-21 uses this
- `thirdparty/shaderc/`, `thirdparty/SPIRV-Tools/` — shaderc and spirv-val (Phase 2) — capability checks must be aware that shader compilation/validation requirements exist
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`RenderProcessor::IsAcceptable`** (`processing_processor_render.cpp:19-23`) — existing device-type filter (DISCRETE_GPU/INTEGRATED_GPU only). `CapabilityValidator`'s Vulkan queries use the same filter.
- **`VulkanInitMutex`** (`vulkan_init_guard.hpp`) — shared mutex for Vulkan init. `CapabilityValidator`'s startup queries acquire this mutex to safely access the VkPhysicalDevice.
- **`CheckProcessValidity()`** in `ProcessingManager` — existing structural validation. Remains unchanged; `CanExecute` is a separate gate (D-17).
- **vk-bootstrap** (`thirdparty/vk-bootstrap/`) — already vendored and wired. `enable_validation_layers()` API used for D-21.
- **ShaderCompiler** from Phase 2 — capability checks must account for shaderc/spirv-val requirements when validating render pass executability.

### Established Patterns
- **`ProcessingResult` error field** (Phase 3, D-25..D-28) — per-stage enum + message string pattern. `UnmetRequirement` in `CanExecute` result should follow similar structured-error conventions.
- **Async callback pattern** — `ProcessingManager::Process()` and other SGProcessingManager APIs use async callbacks. `CanExecute` follows the same pattern (D-03).
- **Registry-based executor registration** — Phase 1's DISP-02 established a `PassType`-keyed factory map. `CapabilityValidator` extends this pattern with capability metadata per registered executor (D-11).
- **Config via CMake options** — existing convention for build-time feature flags (e.g., `TESTING`, `BUILD_EXAMPLES`). `ENABLE_VULKAN_VALIDATION` follows the same pattern (D-24).

### Integration Points
- **`ProcessingManager` initialization** — `CapabilityValidator` is internally constructed during `ProcessingManager` startup. The startup capability snapshot query (D-09) happens during init, under the `VulkanInitMutex`.
- **Job claim flow** — the scheduler (SuperGenius processing node) calls `CapabilityValidator::CanExecute()` before claiming a job. On rejection, the unmet requirements are surfaced to the scheduler for routing/logging.
- **Vulkan instance creation** — `RenderProcessor::InitializeContext()` (via vk-bootstrap) checks the `ENABLE_VULKAN_VALIDATION` CMake flag (D-24) and calls `enable_validation_layers()` if ON. Best-effort — if the layer isn't found, instance creation proceeds without it (D-20).
</code_context>

<specifics>
## Specific Ideas

No UI/UX references — this is backend validation infrastructure.

Key domain context from discussion:
- **No vendoring of validation layers** — the user explicitly chose best-effort over vendoring. Validation layers are a development convenience, not a runtime requirement. This deliberately overrides VVAL-01's literal wording.
- **Caller-responsibility model** — the capability check is the scheduler's gate before claiming work, not a guard inside `Process()`. This keeps `Process()` lean and gives the scheduler control over when/how to validate.
- **Minimal acceptance** — `CanExecute` returns only `executable=true` + executor ID on success, not a full capability dump. The scheduler needs to know "can I run this?" — not "here's every Vulkan limit on this node."
- **Hash-based identity** — executor identity stability is guaranteed by hashing the capability snapshot, not by trusting version strings. Deterministic and tamper-evident.
</specifics>

<deferred>
## Deferred Ideas

- **Vulkan validation layer vendoring** — explicitly dropped in favor of best-effort (D-20). Revisit if a future milestone needs guaranteed validation layer availability on all platforms without SDK dependency.
- **CPU instruction set validation (CAP-05)** — skipped since all MNN processors are on Vulkan (D-13). Revisit if CPU-backed processors are reintroduced.
- **Runtime capability refresh** — skipped in favor of startup-only snapshot (D-12). Revisit if hot-pluggable GPU support or driver updates without node restart become requirements.
- **Per-instance validation layer toggle** — skipped in favor of global flag (D-23). Revisit if MNN instances or other Vulkan consumers need independent validation control.
</deferred>

---

*Phase: 06-Capability & Validation Foundation*
*Context gathered: 2026-08-03*
