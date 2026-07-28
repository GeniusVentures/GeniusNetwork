# Requirements: sgproc-render (Render Pass Execution)

**Defined:** 2026-07-28
**Revised:** 2026-07-28 — full bgfx pivot (see `research/FINAL-BACKEND-DECISION.md` for the reasoning trail: STACK.md → RENDER-BACKEND-DECISION.md → BGFX-HEADLESS-VERIFICATION.md)
**Core Value:** Make `PassType::RENDER` a real, executable graphics pipeline with MNN-style graceful backend fallback — extending the schema for render targets, vertex/index buffers, and multi-stage shaders, then wiring it end-to-end through bgfx with an explicit three-tier fallback chain (Vulkan hardware → OpenGL hardware on Linux → Vulkan-via-SwiftShader software).

## v1 Requirements

Requirements for milestone v1.0. Each maps to roadmap phases.

### Schema Extension

- [ ] **SCHEMA-01**: Render pass schema defines a render-target/framebuffer config (color+depth attachment formats/dimensions)
- [ ] **SCHEMA-02**: Render pass schema defines vertex/index buffer bindings
- [ ] **SCHEMA-03**: Render pass schema supports a multi-stage shader pipeline (vertex+fragment), replacing the single `shader_config` for render passes
- [ ] **SCHEMA-04** *(revised for bgfx)*: Render pass `ShaderType`/shader-source fields represent bgfx-dialect shader source (or precompiled bgfx shader binaries) rather than raw platform-native formats (`metal`/`hlsl`/`glsl`/`spirv` as separate author-selected targets) — job authors write once, bgfx's own toolchain cross-compiles per active backend. Exact field shape is an open design question for Phase 1, not a settled format.
- [ ] **SCHEMA-05**: quicktype-generated headers regenerated from the extended schema (`generated/` is never hand-edited)

### Dispatch & Validation Plumbing

- [ ] **DISP-01**: `ParseBlockSize()` no longer crashes on model-less (render/compute) passes — unconditional `pass.get_model().value()` replaced with a type guard
- [ ] **DISP-02**: `ProcessingManager::Process()` dispatches render passes via a `PassType`-keyed lookup (`m_passMap`), not the existing `DataType`-keyed factory path
- [ ] **DISP-03**: `CheckProcessValidity()` validates that a render pass has a shader config present (currently a silent no-op)

### Rendering Context & Backend Fallback

- [ ] **CTX-01**: A process-wide bgfx rendering context is initialized headless (`platformData.nwh = NULL`), with `bgfx::Init::fallback = false` and an explicit, application-driven three-tier sequence: Vulkan (hardware) → OpenGL (hardware) → Vulkan-via-SwiftShader (software) — never relying on bgfx's built-in fallback cascade
- [ ] **CTX-02**: The OpenGL tier is attempted only on Linux (genuine EGL pbuffer headless support); it is never attempted on Windows (WGL requires a real window/external context, no auto pbuffer fallback) or macOS (bgfx does not enable a default OpenGL backend there)
- [ ] **CTX-03**: A single process-wide Vulkan init lock serializes MNN's existing Vulkan call sites and bgfx's Vulkan-backend init (replacing the current function-local-static mutex, which doesn't cover all MNN Vulkan sites today)
- [ ] **CTX-04**: bgfx and SwiftShader vendored as new `thirdparty/` git submodules via the existing `CommonBuildParameters.cmake`/`CommonTargets` convention, alongside already-vendored Vulkan-Headers/Vulkan-Loader/MoltenVK; bgfx's Vulkan backend confirmed to route through MoltenVK unchanged on macOS/iOS
- [ ] **CTX-05**: The mechanism for forcing bgfx's Vulkan renderer onto the SwiftShader software ICD (e.g. `BGFX_PCI_ID_SOFTWARE_RASTERIZER` vendor-ID hint, or manual physical-device enumeration if that hint doesn't propagate as expected) is implemented and verified end-to-end — not assumed to work from documentation alone

### Render Pipeline Execution

- [ ] **RENDER-01** *(revised for bgfx)*: `RenderProcessor` builds a vertex+fragment bgfx program from schema-declared bgfx-dialect shader source, compiled via bgfx's own `shaderc` toolchain (distinct from Google's identically-named `shaderc`)
- [ ] **RENDER-02** *(revised for bgfx)*: `RenderProcessor` uploads vertex/index buffer data via bgfx's buffer API (`bgfx::createVertexBuffer`/`createIndexBuffer`) from `pass_io_binding`-resolved inputs
- [ ] **RENDER-03** *(revised for bgfx)*: `RenderProcessor` renders to an offscreen bgfx frame buffer (color+depth attachments) with depth testing, no swapchain
- [ ] **RENDER-04**: Pipeline state (topology, cull mode, winding order) is configurable via schema config, expressed through bgfx state flags
- [ ] **RENDER-05** *(revised for bgfx)*: `RenderProcessor` binds uniforms/parameters (e.g. MVP matrices) via `bgfx::setUniform`, sourced from the existing `shader_config.uniforms`/`parameter:` refs
- [ ] **RENDER-06** *(revised for bgfx)*: `RenderProcessor` reads back rendered output (`bgfx::blit`/`bgfx::readTexture`) and exposes it as `texture2D` through the existing `pass_io_binding` output mechanism
- [ ] **RENDER-07**: Rendered output can optionally flow through the existing `data_transform` post-processing step (resize/crop/color_convert/etc.)
- [ ] **RENDER-08**: `RenderProcessor` output feeds the existing `ProcessingResult` → `FileManager::SaveASync` → hash path unmodified, regardless of which of the 3 fallback tiers actually executed the pass

### Determinism & CI

- [ ] **DETV-01** *(revised for multi-tier)*: Render pass output is verified deterministic via same-node repeat execution (bit-exact hash match across repeated runs on the same node, using whichever single tier that node resolved to at startup — a node's tier is chosen once and does not change between runs); cross-node, cross-vendor, AND cross-tier tolerance-based verification are all explicitly out of scope for v1
- [ ] **DETV-02**: Job-supplied bgfx shader source is validated (via bgfx's `shaderc` compile step rejecting malformed shaders) before it reaches any GPU/software backend
- [ ] **DETV-03**: CI installs/uses the vendored SwiftShader software Vulkan ICD (per CTX-04) so the render path's tertiary (CPU) tier actually executes in CI even without real GPU hardware on Linux runners

### End-to-End Verification

- [ ] **E2E-01**: A real render pass definition executes end-to-end through the distributed processing pipeline and produces a verified output hash
- [ ] **E2E-02**: The render path is confirmed to actually execute (not just compile) on a MoltenVK/Apple target via bgfx's Vulkan backend, with the OpenGL tier never attempted there
- [ ] **E2E-03**: The full existing MNN inference/retrain test suite passes with zero regressions alongside the new render path, including a concurrent MNN-Vulkan-init + bgfx-Vulkan-init stress test proving CTX-03's shared init lock holds under real concurrent load
- [ ] **E2E-04**: All three fallback tiers (Vulkan hardware, OpenGL on Linux, Vulkan-via-SwiftShader software) are each exercised at least once in an end-to-end test with an actual draw-call-plus-readback round-trip (not just an `bgfx::init()` success check), proving the explicit tier-sequencing logic (CTX-01/CTX-02) works as designed

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
- **VVL-01**: Vulkan-ValidationLayers vendored for debug builds (explicit open decision, not required for v1 correctness)
- **LAVAPIPE-01**: Swap SwiftShader for Mesa lavapipe as the software tier if SwiftShader's CPU performance proves inadequate for real render-job SLAs (lavapipe is reported faster but is heavier to vendor — full Mesa/Meson tree vs. SwiftShader's standalone CMake repo)
- **D3D-01**: Windows D3D11/D3D12 tier as an additional fallback option (bgfx supports it natively; not adopted for v1 to keep the tier count/testing matrix scoped to the 3 tiers already committed)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Diligent Engine, Filament, VulkanSceneGraph (vsg), Ogre-Next, The Forge | Evaluated in `RENDER-BACKEND-DECISION.md` — none offer a genuine app-level CPU-rasterizer fallback (the actual gap being solved), and none demonstrated a compelling advantage over bgfx for this project's specific 3-tier-with-software-ICD design |
| An app-level "CPU rendering" engine backend | Does not exist as a mature option in this space (confirmed via research) — the genuine CPU-fallback equivalent lives at the Vulkan-ICD level (SwiftShader), not as an engine backend choice |
| Windowed/interactive rendering, swapchain, VSync | SGProcessingManager is a headless distributed compute node — there is no display surface, ever |
| Continuous frame-pacing render loop | This is a discrete batch job (submit-once-return-hash), like inference today — not a real-time render loop |
| Shader hot-reload | No development-time iteration workflow exists for job-supplied shaders; irrelevant to a distributed compute job |
| Full 3D-engine surface (skinning, PBR, scene graphs) | Out of scope for a single schema-declared render-to-texture pass; bgfx is used purely as a backend-abstraction layer, not for its higher-level engine features |
| MSAA enabled by default | Multi-sample resolution adds another source of cross-hardware non-determinism, directly conflicting with the DETV-01 same-node determinism goal |
| Cross-node/cross-vendor/cross-tier exact-hash verification | Vulkan/OpenGL do not guarantee bit-identical output across GPU vendors/drivers/backends — see DETV-01 and v2 XNODE-01 |
| OpenGL tier on Windows or macOS | Confirmed via `BGFX-HEADLESS-VERIFICATION.md`: genuinely non-headless on Windows (WGL requires a real window), not a default bgfx backend on macOS at all |
| D3D11/D3D12 tier | bgfx supports it, but adding a 4th tier expands the testing/verification matrix beyond this milestone's scope — deferred as v2 D3D-01 |

## Traceability

(Populated during roadmap creation.)

| Requirement | Phase | Status |
|-------------|-------|--------|
| SCHEMA-01 | TBD | Pending |
| SCHEMA-02 | TBD | Pending |
| SCHEMA-03 | TBD | Pending |
| SCHEMA-04 | TBD | Pending |
| SCHEMA-05 | TBD | Pending |
| DISP-01 | TBD | Pending |
| DISP-02 | TBD | Pending |
| DISP-03 | TBD | Pending |
| CTX-01 | TBD | Pending |
| CTX-02 | TBD | Pending |
| CTX-03 | TBD | Pending |
| CTX-04 | TBD | Pending |
| CTX-05 | TBD | Pending |
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
| E2E-04 | TBD | Pending |

**Coverage:**
- v1 requirements: 28 total
- Mapped to phases: 0 (pending roadmap re-creation)
- Unmapped: 28 ⚠️

---
*Requirements defined: 2026-07-28*
*Last updated: 2026-07-28 after bgfx backend pivot*
