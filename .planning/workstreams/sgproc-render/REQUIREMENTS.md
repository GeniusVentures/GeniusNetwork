# Requirements: sgproc-render

**Last updated:** 2026-08-03
**Current milestone:** v2.0 — Execution Contracts & Quality Gates

## v1 Requirements (Shipped: 2026-07-31)

All v1.0 requirements shipped across 5 phases (24 plans). See `.planning/workstreams/sgproc-render/STATE.md` (v1.0 archive) for full details. Key categories: CTX (Vulkan context), SCHEMA (schema extension), SHADER (SPIR-V validation), DISP (dispatch plumbing), RENDER (RenderProcessor), DETV (determinism), E2E (end-to-end), CMAKE/MIGR/COV (CMake + MNN migration).

## v2.0 Requirements

Requirements for milestone v2.0. Each maps to roadmap phases.

### CAP — Capability Validation (#12)

- [ ] **CAP-01**: Node can validate whether it can execute a job (across all pass types) before downloading large inputs or claiming work — structured `CanExecute` result with unmet requirements when not executable
- [ ] **CAP-02**: Unsupported Vulkan features, extensions, device limits, descriptor types, image formats, buffer sizes, or memory requirements return specific unmet-requirement reasons (not a generic "unsupported")
- [ ] **CAP-03**: Unsupported model format, quantization, tokenizer/adapter, or model identity returns specific unmet-requirement reasons for MNN inference passes
- [ ] **CAP-04**: Unsupported pass type (`PassType`) or missing executor registration returns a specific reason with the pass type and available executors
- [ ] **CAP-05**: Input/output type, format, dimensions, and estimated memory/storage needs are validated against node capabilities; CPU architecture/instruction requirements checked for CPU processors
- [ ] **CAP-06**: The selected executor identity and key compatibility identities (model, shader, quantization, runtime) are stable and surfaced in capability-check result metadata for scheduler consumption

### EXEC — Execution Context (#13)

- [ ] **EXEC-01**: A cooperative cancellation token is passed through `ProcessingManager` to every executor's `StartProcessing()` call; a cancelled job does not publish a successful result
- [ ] **EXEC-02**: Per-pass deadlines produce distinct typed timeout failures (not a generic error) when the pass exceeds its time budget
- [ ] **EXEC-03**: CPU, GPU, RAM/VRAM, disk, network, runtime, and output-size budgets are defined in the execution context and enforced where the executor can control resource consumption
- [ ] **EXEC-04**: Structured progress events carry pass ID, stage identifier, completed work count, total work count, and a human-readable message — replacing the current single atomic float percentage
- [ ] **EXEC-05**: Processors that support checkpointing expose a partial-result/checkpoint callback; processors without checkpoint support clearly report that they do not support it
- [ ] **EXEC-06**: On cancellation, timeout, or budget-exceeded: Vulkan resources (pipelines, buffers, images, command pools), MNN sessions, loaded artifacts, and pending asynchronous saves are safely cleaned up without leaks
- [ ] **EXEC-07**: All existing MNN and Vulkan processors remain usable through an adapter or wrapper during the migration period — no existing processor is broken by the new execution context contract

### ARTF — Structured Artifacts & Manifests (#14)

- [ ] **ARTF-01**: Each output artifact carries a declared resource name, stable artifact ID, producing pass identity, and output binding reference
- [ ] **ARTF-02**: Each artifact includes data type, format, shape/dimensions, byte size, and media type
- [ ] **ARTF-03**: Each artifact includes a content hash and chunk hashes for integrity verification
- [ ] **ARTF-04**: The execution manifest includes: execution/attempt/task/subtask/pass IDs, selected executor and runtime compatibility identity, model/tokenizer/adapter/shader/quantization identities when used, input and output artifact hashes, start/end times, terminal state, error details, and resource-use summary
- [ ] **ARTF-05**: The execution manifest serializes deterministically (byte-identical across runs with identical inputs) for hashing, signing, caching, and verification
- [ ] **ARTF-06**: A migration adapter preserves the existing `ProcessingResult` shape and the SuperGenius newline-delimited output-location string for existing callers until the SuperGenius protobuf integration is updated

### TEST — Conformance Test Suites (#15)

- [ ] **TEST-01**: CTest targets (`ctest`) run from the standalone SGProcessingManager build AND when consumed as a submodule by `SuperGenius/develop` — tests use small deterministic fixtures
- [x] **TEST-02**: Schema parsing and pass-specific validation tests cover every `PassType` (including the render path from v1.0) with both valid and invalid inputs
- [x] **TEST-03**: Executor selection by pass type and backend is tested for every registered executor (MNN inference, Vulkan compute, Vulkan render)
- [ ] **TEST-04**: Every existing MNN processor runs the same core conformance contract (pass-through or adapted) — no backend-specific drift
- [x] **TEST-05**: Native Vulkan compute/render and the existing MoltenVK path run equivalent fixtures where CI hardware permits; unsupported CI environments skip with an explicit reason
- [x] **TEST-06**: Output hashing, artifact metadata construction, persistence round-trip, and deterministic serialization are tested end-to-end
- [ ] **TEST-07**: Cancellation, deadline expiry, budget exceeded, progress event emission, partial result delivery, and resource cleanup are each tested with at least one processor type
- [x] **TEST-08**: Capability acceptance cases (executable jobs) and rejection cases (unsupported features/formats/pass types) are both covered
- [ ] **TEST-09**: The migration adapter from ARTF-06 is tested — existing callers' `ProcessingResult` shape and output-location string behavior is preserved
- [ ] **TEST-10**: Regression tests cover the four concrete known bugs: (a) index mismatch in pass/input indexing, (b) model-only assumption crash in `ParseBlockSize()`, (c) output-buffer-zero fallback producing incorrect results, (d) unsupported pass type silently falling through without error

### VVAL — Vulkan Validation Layers (CTX-04 carryover from v1.0)

- [ ] **VVAL-01**: Vulkan validation layers (LunarG VK_LAYER_KHRONOS_validation or equivalent) are vendored as new `thirdparty/` git submodule(s), following the existing permissive-license convention (Apache-2.0/MIT)
- [ ] **VVAL-02**: Validation layers are wired into the existing `CommonBuildParameters.cmake`/`CommonTargets` convention, producing linkable/loadable layer artifacts for all supported platforms (Windows, Linux, macOS)
- [ ] **VVAL-03**: Validation layers can be enabled or disabled at runtime for `RenderProcessor`'s `VkInstance` (and any other SGProcessingManager-owned Vulkan instance) via a configuration flag — disabled by default in production, enabled in debug/test
- [ ] **VVAL-04**: A documented decision replaces v1.0 CTX-04's written deferral, recording: which layer set was chosen, why, CMake integration pattern, and the runtime toggle mechanism

## Traceability

| REQ-ID | Phase | Status |
|--------|-------|--------|
| *(to be filled by roadmap)* | | |

---
*Requirements defined: 2026-08-03 — v2.0 Execution Contracts & Quality Gates*

- [x] **CMAKE-01**: `find_package(vk-bootstrap CONFIG REQUIRED)` propagated to `GeniusSDK/cmake/CommonBuildParameters.cmake` and `GeniusWallet/cmake/CommonBuildParameters.cmake`, mirroring the existing per-consumer convention (not `find_dependency()` propagation), so both downstream consumers resolve `SGProcessingManager`'s PUBLIC-linked `vk-bootstrap::vk-bootstrap` transitive dependency at configure time
- [x] **MIGR-01**: All 13 remaining CPU-backed MNN processors (14 `createSession()` call sites) migrated from `MNN_FORWARD_CPU` to `MNN_FORWARD_VULKAN`, each wrapped in the existing shared `sgns::sgprocessing::VulkanInitMutex()` guard from Phase 1's CTX-02 — bringing all MNN processors in `SGProcessingManager` onto the Vulkan backend
- [x] **MIGR-02**: `vulkan_init_guard.hpp`'s doc comment and `vulkan_init_concurrency_test.cpp`'s scope documentation updated to reflect the true, larger set of Vulkan-init call sites sharing the mutex post-migration (no longer hardcoding the stale "3 MNN + RenderProcessor" figure)
- [x] **COV-01**: The existing `ProcessingDatatypesTest` suite's 13 migration-candidate `*ProcessingTest` cases re-verified against the newly-Vulkan-backed processors within their existing tolerance bounds (`mean_abs_diff < 1e-3`, `max_abs_diff < 1e-2`) — resolving "coverage" as test/verification-suite extension, not new code-coverage tooling (no gcov/lcov/OpenCppCoverage introduced)

### Vulkan Context & Coexistence

- [ ] **CTX-01**: Headless Vulkan instance/device/queue created for `RenderProcessor` — no `VkSurfaceKHR`, no swapchain, no WSI extensions on any platform (Windows, Linux, macOS via MoltenVK)
- [ ] **CTX-02**: A shared, process-wide Vulkan init-time synchronization primitive guards ALL Vulkan instance/device creation call sites in the process (MNN's existing 3 call sites + `RenderProcessor`'s new one), replacing MNN's current single-file-scoped `mnn_vulkan_mutex`
- [ ] **CTX-03**: Explicit, deterministic physical-device selection policy for `RenderProcessor` (not "pick index 0")
- [ ] **CTX-04**: Vulkan-ValidationLayers vendoring is explicitly deferred to v1.x (documented decision, not silently dropped)

### Schema Extension

- [x] **SCHEMA-01**: Render pass schema defines a render-target/framebuffer config (color+depth attachment formats/dimensions/clear values)
- [x] **SCHEMA-02**: Render pass schema defines vertex/index buffer bindings + layout
- [x] **SCHEMA-03**: Render pass schema supports a multi-stage shader pipeline (vertex+fragment), replacing the single `shader_config` for render passes
- [x] **SCHEMA-04**: Render pass schema defines pipeline state (topology, cull mode, winding order, depth-test) configurable via schema
- [x] **SCHEMA-05**: quicktype-generated headers regenerated from the extended schema (`generated/` is never hand-edited)

### Shader Compilation & Validation

- [x] **SHADER-01**: GLSL shader source is compiled to SPIR-V in-process via a vendored `shaderc` toolchain, at job-load time, before any GPU call
- [x] **SHADER-02**: All SPIR-V reaching `vkCreateShaderModule` (whether compiled from GLSL or submitted directly as `shader_config.type: "spirv"`) passes a mandatory `spirv-val` validation gate — malformed/invalid SPIR-V is rejected with a clean error, never reaches the driver
- [x] **SHADER-03**: `shader_config.type: "spirv"` is explicitly accepted for render passes, subject to SHADER-02's validation gate

### Dispatch & Validation Plumbing

- [ ] **DISP-01**: `ParseBlockSize()` no longer crashes on model-less (render/compute) passes — unconditional `pass.get_model().value()` replaced with a type guard
- [ ] **DISP-02**: `ProcessingManager::Process()` dispatches render passes via a new, separate `PassType`-keyed factory map — NOT the existing `DataType`-keyed map (confirmed enum collision: `static_cast<int>(PassType::RENDER) == static_cast<int>(DataType::INT)`)
- [ ] **DISP-03**: `CheckProcessValidity()` validates that a render pass has a shader config present and enforces SHADER-03's accept-with-validation decision (currently a silent no-op)

### Render Pipeline Execution

- [x] **RENDER-01**: `RenderProcessor` builds a vertex+fragment pipeline from schema-declared, validated SPIR-V
- [x] **RENDER-02**: `RenderProcessor` uploads vertex/index buffer data from `pass_io_binding`-resolved inputs via direct Vulkan buffer APIs
- [x] **RENDER-03**: `RenderProcessor` renders to an offscreen framebuffer (color+depth attachments) with depth testing, no swapchain
- [x] **RENDER-04**: Pipeline state (topology, cull mode, winding order) is configurable via schema config (SCHEMA-04)
- [x] **RENDER-05**: `RenderProcessor` binds uniforms/parameters (e.g. MVP matrices) via push constants, sourced from `shader_config.uniforms`/`parameter:` refs, falling back to descriptor-set uniforms where push-constant size limits are exceeded
- [x] **RENDER-06**: `RenderProcessor` reads back rendered output (`vkCmdCopyImageToBuffer`) and exposes it as `texture2D` through the existing `pass_io_binding` output mechanism
- [x] **RENDER-07**: Rendered output can optionally flow through the existing `data_transform` post-processing step
- [x] **RENDER-08**: `RenderProcessor` output feeds the existing `ProcessingResult` → `FileManager::SaveASync` → hash path unmodified
- [x] **RENDER-09**: `VkResult` failures map to structured `ProcessingManager::Error` values with clear per-failure-point messages

### Determinism & CI

- [x] **DETV-01**: Render pass output is verified deterministic via same-node repeat execution (bit-exact hash match across N≥10 repeated runs on the same node/hardware); cross-node, cross-vendor, cross-driver tolerance-based verification is explicitly out of scope for v1
- [x] **DETV-02**: Determinism guards are architectural: explicit clear ops (never `DONT_CARE`) on hashed regions, `VK_SAMPLE_COUNT_1_BIT` always, fixed shader precision qualifiers, no unordered parallel-reduction shader math
- [x] **DETV-03**: CI exercises a hardware-independent tier (schema validation, shader compile, `spirv-val`, pipeline construction via a software Vulkan ICD, test-only — never product code) alongside a hardware-dependent tier (real draw+readback, the repeat-run determinism test) on a real-GPU runner

### End-to-End Verification

- [x] **E2E-01**: A real render pass definition executes end-to-end through the distributed processing pipeline and produces a verified output hash
- [x] **E2E-02**: The render path actually executes (not just compiles) on a MoltenVK/macOS target
- [x] **E2E-03**: The full existing MNN inference/retrain test suite passes with zero regressions alongside the new render path, including a concurrent-init stress test proving CTX-02's shared lock holds under real concurrent MNN-Vulkan-init + RenderProcessor-Vulkan-init load

### Mobile Platform Thirdparty Library Builds (Phase 5)

- [ ] **MOBILE-01**: SPIRV-Headers, SPIRV-Tools, shaderc, and vk-bootstrap ExternalProject_Add blocks in `thirdparty/build/CommonTargets.cmake` are unconditional — they build for all platforms including Android (arm64-v8a, armeabi-v7a) and iOS (arm64 device)
- [ ] **MOBILE-02**: Vulkan-Headers and Vulkan-Loader ExternalProject_Add blocks remain inside the `if(NOT ANDROID)` guard — desktop only; Android uses NDK's Vulkan loader, iOS uses MoltenVK
- [ ] **MOBILE-03**: vk-bootstrap's `VulkanHeaders_DIR` CMAKE_CACHE_ARG resolves correctly for all three platform groups: desktop (locally-built Vulkan-Headers via Vulkan-Loader install), Android (NDK-provided Vulkan headers), and iOS (MoltenVK-provided Vulkan headers)
- [ ] **MOBILE-04**: SGShaderCompiler's `target_link_libraries` resolves `shaderc::shaderc` and `SPIRV-Tools::SPIRV-Tools` when building for Android and iOS — no platform guards needed (targets are unconditional after MOBILE-01)
- [ ] **MOBILE-05**: SGProcessors' `target_link_libraries` resolves `Vulkan::Vulkan` and `vk-bootstrap::vk-bootstrap` when building for Android and iOS — no platform guards needed
- [ ] **MOBILE-06**: Build documentation exists at `thirdparty/build/mobile/README.md` with exact cmake invocations for Android NDK and iOS Xcode thirdparty library builds, expected output artifacts, and troubleshooting guidance

## v2 Requirements

Deferred to future milestones. Tracked but not in current roadmap.

### Advanced Rendering

- **MPASS-01**: Multi-pass/post-processing shader chains
- **MRT-01**: Multiple render targets (MRT)
- **INTEROP-01**: Compute/inference ↔ render interop (MNN-tensor-to-Vulkan-buffer bridging)
- **INST-01**: Instancing support
- **TEXIN-01**: Texture sampling from external input (shares descriptor/sampler infra with MPASS-01)
- **BLEND-01**: Alpha blending/transparency (order-dependent — conflicts with determinism goals, needs its own design)

### Verification & Backend

- **XNODE-01**: Cross-node tolerance/redundancy-based verification (only needed once heterogeneous-hardware verification is actually required)
- **VALLAYER-01**: Vulkan-ValidationLayers wired into debug/CI builds (deferred per CTX-04)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Any third-party rendering engine/new GPU backend (bgfx or otherwise) | `GeniusVentures/SGProcessingManager#7` explicitly prohibits adding another GPU backend or duplicate platform setup — the archived bgfx-based v1.0 attempt violated this directly |
| OpenGL tier | Not mandated by issue #7; Vulkan (+ MoltenVK on Apple) only |
| SwiftShader / any CPU-software rendering fallback | Explicitly prohibited by issue #7 — Vulkan hardware only, hard-fail if unavailable |
| Windowed/interactive rendering, swapchain, VSync | SGProcessingManager is a headless distributed compute node — there is no display surface, ever |
| Continuous frame-pacing render loop | This is a discrete batch job (submit-once-return-hash), like inference today — not a real-time render loop |
| Shader hot-reload | No development-time iteration workflow exists for job-supplied shaders; irrelevant to a distributed compute job |
| Full 3D-engine surface (skinning, PBR, scene graphs) | Out of scope for a single schema-declared render-to-texture pass |
| MSAA enabled by default | Multi-sample resolution adds another source of cross-hardware non-determinism, directly conflicting with DETV-01's same-node determinism goal |
| Cross-node/cross-vendor/cross-driver exact-hash verification | Vulkan does not guarantee bit-identical output across GPU vendors/drivers — see DETV-01 and v2 XNODE-01 |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CMAKE-01 | Phase 01.1 | Complete |
| MIGR-01 | Phase 01.1 | Complete |
| MIGR-02 | Phase 01.1 | Complete |
| COV-01 | Phase 01.1 | Complete |
| CTX-01 | Phase 1 | Pending |
| CTX-02 | Phase 1 | Pending |
| CTX-03 | Phase 1 | Pending |
| CTX-04 | Phase 1 | Pending |
| DISP-01 | Phase 1 | Pending |
| DISP-02 | Phase 1 | Pending |
| DISP-03 | Phase 1 | Pending |
| SCHEMA-01 | Phase 2 | Complete |
| SCHEMA-02 | Phase 2 | Complete |
| SCHEMA-03 | Phase 2 | Complete |
| SCHEMA-04 | Phase 2 | Complete |
| SCHEMA-05 | Phase 2 | Complete |
| SHADER-01 | Phase 2 | Complete |
| SHADER-02 | Phase 2 | Complete |
| SHADER-03 | Phase 2 | Complete |
| RENDER-01 | Phase 3 | Complete |
| RENDER-02 | Phase 3 | Complete |
| RENDER-03 | Phase 3 | Complete |
| RENDER-04 | Phase 3 | Complete |
| RENDER-05 | Phase 3 | Complete |
| RENDER-06 | Phase 3 | Complete |
| RENDER-07 | Phase 3 | Complete |
| RENDER-08 | Phase 3 | Complete |
| RENDER-09 | Phase 3 | Complete |
| DETV-01 | Phase 3 | Complete |
| DETV-02 | Phase 3 | Complete |
| DETV-03 | Phase 4 | Complete |
| E2E-01 | Phase 4 | Complete |
| E2E-02 | Phase 4 | Complete |
| E2E-03 | Phase 4 | Complete |
| MOBILE-01 | Phase 5 | Pending |
| MOBILE-02 | Phase 5 | Pending |
| MOBILE-03 | Phase 5 | Pending |
| MOBILE-04 | Phase 5 | Pending |
| MOBILE-05 | Phase 5 | Pending |
| MOBILE-06 | Phase 5 | Pending |

**Coverage:**

- v1 requirements: 40 total
- Mapped to phases: 40
- Unmapped: 0 ✓

---
*Requirements defined: 2026-07-29*
*Last updated: 2026-07-31 — Phase 5 (Android/iOS Platform Compatibility) added MOBILE-01 through MOBILE-06; 40/40 v1 requirements mapped (0 unmapped)*
