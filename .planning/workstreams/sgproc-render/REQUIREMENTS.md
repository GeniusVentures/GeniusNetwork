# Requirements: sgproc-render (Render Pass Execution)

**Defined:** 2026-07-28
**Core Value:** Make `PassType::RENDER` a real, executable graphics pipeline — extending the schema for render targets, vertex/index buffers, and multi-stage shaders, then wiring it end-to-end through a vendored permissive-license (non-GPL) Vulkan rendering library.

## v1 Requirements

Requirements for milestone v1.0. Each maps to roadmap phases.

### Schema Extension

- [ ] **SCHEMA-01**: Render pass schema defines a render-target/framebuffer config (color+depth attachment formats/dimensions)
- [ ] **SCHEMA-02**: Render pass schema defines vertex/index buffer bindings
- [ ] **SCHEMA-03**: Render pass schema supports a multi-stage shader pipeline (vertex+fragment), replacing the single `shader_config` for render passes
- [ ] **SCHEMA-04**: Render passes are restricted to SPIR-V `ShaderType` only (`metal`/`hlsl` rejected for render passes)
- [ ] **SCHEMA-05**: quicktype-generated headers regenerated from the extended schema (`generated/` is never hand-edited)

### Dispatch & Validation Plumbing

- [ ] **DISP-01**: `ParseBlockSize()` no longer crashes on model-less (render/compute) passes — unconditional `pass.get_model().value()` replaced with a type guard
- [ ] **DISP-02**: `ProcessingManager::Process()` dispatches render passes via a `PassType`-keyed lookup (`m_passMap`), not the existing `DataType`-keyed factory path
- [ ] **DISP-03**: `CheckProcessValidity()` validates that a render pass has a shader config present (currently a silent no-op)

### Vulkan Render Context

- [ ] **VKCTX-01**: A process-wide `VulkanRenderContext` owns `VkInstance`/`VkPhysicalDevice`/`VkDevice`/`VkQueue`, created headless (no `VkSurfaceKHR`/`VkSwapchainKHR`), fully independent of MNN's internal Vulkan context
- [ ] **VKCTX-02**: A single process-wide Vulkan init lock serializes MNN's 3 existing Vulkan call sites and the new render context (replacing the current function-local-static mutex, which doesn't cover all MNN Vulkan sites today)
- [ ] **VKCTX-03**: vk-bootstrap, VMA, and shaderc vendored as new `thirdparty/` git submodules following the existing convention; glslang's legacy GPL-with-Bison-exception clause explicitly signed off in the decisions log rather than silently waved through

### Render Pipeline Execution

- [ ] **RENDER-01**: `RenderProcessor` builds a vertex+fragment graphics pipeline from schema-declared shader source, compiled at runtime via shaderc
- [ ] **RENDER-02**: `RenderProcessor` uploads vertex/index buffer data (staging → device-local, VMA-backed) from `pass_io_binding`-resolved inputs
- [ ] **RENDER-03**: `RenderProcessor` renders to an offscreen color+depth target with depth testing, no swapchain
- [ ] **RENDER-04**: Pipeline state (topology, cull mode, winding order) is configurable via schema config
- [ ] **RENDER-05**: `RenderProcessor` binds uniforms/parameters (e.g. MVP matrices) via the existing `shader_config.uniforms`/`parameter:` refs
- [ ] **RENDER-06**: `RenderProcessor` reads back rendered output (`vkCmdCopyImageToBuffer`) and exposes it as `texture2D` through the existing `pass_io_binding` output mechanism
- [ ] **RENDER-07**: Rendered output can optionally flow through the existing `data_transform` post-processing step (resize/crop/color_convert/etc.)
- [ ] **RENDER-08**: `RenderProcessor` output feeds the existing `ProcessingResult` → `FileManager::SaveASync` → hash path unmodified

### Determinism & CI

- [ ] **DETV-01**: Render pass output is verified deterministic via same-node repeat execution (bit-exact hash match across repeated runs on the same node); cross-node/cross-vendor tolerance-based verification is explicitly out of scope for v1
- [ ] **DETV-02**: Job-supplied SPIR-V shaders are validated before `vkCreateShaderModule` (mitigates malformed/malicious shader bytecode)
- [ ] **DETV-03**: CI installs a software Vulkan driver (e.g. `mesa-vulkan-drivers`/lavapipe) so the render path's device-creation-through-readback flow actually executes in CI

### End-to-End Verification

- [ ] **E2E-01**: A real render pass definition executes end-to-end through the distributed processing pipeline and produces a verified output hash
- [ ] **E2E-02**: The render path is confirmed to actually run (not just compile) on a MoltenVK/Apple target, never creating a `VkSurfaceKHR`/`VkSwapchainKHR`
- [ ] **E2E-03**: Full existing MNN inference/retrain test suite passes with zero regressions alongside the new render path (including a concurrent MNN-Vulkan-init + render-context-init stress test)

## v2 Requirements

Deferred to future milestones. Tracked but not in current roadmap.

### Advanced Rendering

- **MPASS-01**: Multi-pass/post-processing shader chains
- **MRT-01**: Multiple render targets (MRT)
- **INTEROP-01**: Compute/inference ↔ render interop (MNN-tensor-to-Vulkan-buffer bridging)
- **INST-01**: Instancing support
- **TEXIN-01**: Texture sampling from external input (shares descriptor/sampler infra with MPASS-01)
- **BLEND-01**: Alpha blending/transparency (order-dependent — conflicts with determinism goals, needs its own design)

### Verification

- **XNODE-01**: Cross-node tolerance/redundancy-based verification (only needed once heterogeneous-hardware verification is actually required)
- **VVL-01**: Vulkan-ValidationLayers vendored for debug builds (explicit open decision, not required for v1 correctness)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Rendering engine (bgfx, Diligent Engine, Filament, VulkanSceneGraph) | Evaluated and rejected — each imposes an abstraction, large dependency surface, or unconfirmed/rougher headless-Vulkan support this single-pipeline, schema-declared job doesn't need. A thin custom `RenderProcessor` on raw Vulkan is sufficient. |
| Windowed/interactive rendering, swapchain, VSync | SGProcessingManager is a headless distributed compute node — there is no display surface, ever. |
| Continuous frame-pacing render loop | This is a discrete batch job (submit-once-return-hash), like inference today — not a real-time render loop. |
| Shader hot-reload | No development-time iteration workflow exists for job-supplied shaders; irrelevant to a distributed compute job. |
| Full 3D-engine surface (skinning, PBR, scene graphs) | Out of scope for a single schema-declared render-to-texture pass; would require a rendering engine, which is itself out of scope. |
| MSAA enabled by default | Multi-sample resolution adds another source of cross-hardware non-determinism, directly conflicting with the DETV-01 same-node determinism goal. |
| Cross-node/cross-vendor exact-hash verification | Vulkan does not guarantee bit-identical output across GPU vendors/drivers — see DETV-01 and v2 XNODE-01. |

## Traceability

(Populated during roadmap creation.)

| Requirement | Phase | Status |
|-------------|-------|--------|
| DISP-01 | TBD | Pending |
| DISP-02 | TBD | Pending |
| DISP-03 | TBD | Pending |
| SCHEMA-01 | TBD | Pending |
| SCHEMA-02 | TBD | Pending |
| SCHEMA-03 | TBD | Pending |
| SCHEMA-04 | TBD | Pending |
| SCHEMA-05 | TBD | Pending |
| VKCTX-01 | TBD | Pending |
| VKCTX-02 | TBD | Pending |
| VKCTX-03 | TBD | Pending |
| RENDER-01 | TBD | Pending |
| RENDER-02 | TBD | Pending |
| RENDER-03 | TBD | Pending |
| RENDER-04 | TBD | Pending |
| RENDER-05 | TBD | Pending |
| RENDER-06 | TBD | Pending |
| RENDER-07 | TBD | Pending |
| RENDER-08 | TBD | Pending |
| DETV-01 | TBD | Pending |
| DETV-02 | TBD | Pending |
| DETV-03 | TBD | Pending |
| E2E-01 | TBD | Pending |
| E2E-02 | TBD | Pending |
| E2E-03 | TBD | Pending |

**Coverage:**
- v1 requirements: 24 total
- Mapped to phases: 0 (pending roadmap creation)
- Unmapped: 24 ⚠️

---
*Requirements defined: 2026-07-28*
*Last updated: 2026-07-28 after initial definition*
