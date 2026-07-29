# Roadmap: sgproc-render (v1.0 Render Pass Execution)

## Overview

**This roadmap restructures the prior 4-phase bgfx-pivot roadmap — it is not a from-scratch regeneration.** The prior structure bundled two conceptually different kinds of work into Phase 2 ("bgfx Vendoring & Three-Tier Backend Context"): (a) vendoring bgfx and SwiftShader as new `thirdparty/` git submodules and wiring them into the existing `CommonBuildParameters.cmake`/`CommonTargets` convention (`CTX-04`), and (b) the actual runtime three-tier backend-selection/fallback logic (`CTX-01`, `CTX-02`, `CTX-03`, `CTX-05`). The user asked for these to be split: a dedicated, earliest phase purely for getting bgfx/SwiftShader vendored and building — foundational build-system plumbing with no runtime logic — landing before any phase that writes code depending on those libraries being available.

The split adds a new Phase 1 (bgfx & SwiftShader vendoring, `CTX-04` only, build-system-level success criteria) ahead of everything else. The former Phase 1 (schema/dispatch) becomes Phase 2, unchanged in content. The former Phase 2 keeps only its runtime backend-selection requirements (`CTX-01`, `CTX-02`, `CTX-03`, `CTX-05`), is renamed to "Three-Tier Backend Context & Fallback Sequencing," and now depends on the new Phase 1 (it needs bgfx/SwiftShader actually buildable first) while remaining independent of Phase 2's schema work. The former Phase 3 (`RenderProcessor` on bgfx) and Phase 4 (determinism/CI/E2E) carry forward verbatim as Phase 4 and Phase 5, with dependency lines renumbered. All 28 v1 requirements remain covered; none were added, removed, or reworded — only regrouped and, in the vendoring/context split, given new phase-appropriate success criteria.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3, 4, 5): Planned milestone work
- This is the first milestone for the sgproc-render workstream — numbering starts at Phase 1

- [ ] **Phase 1: bgfx & SwiftShader Vendoring** - bgfx and SwiftShader are vendored as new `thirdparty/` git submodules, buildable through the existing CMake convention and linkable against already-vendored Vulkan-Headers/Vulkan-Loader/MoltenVK — pure build-system plumbing, no runtime backend logic
- [ ] **Phase 2: Schema Extension & Dispatch Foundation** - Render pass definitions are schema-valid for bgfx (render target, vertex/index buffers, multi-stage bgfx-dialect shaders) and route safely through `ProcessingManager` without crashing or silently passing invalid configs
- [ ] **Phase 3: Three-Tier Backend Context & Fallback Sequencing** - A process-wide, headless bgfx rendering context is available, explicitly resolving to one of Vulkan (hardware) / OpenGL (Linux hardware) / Vulkan-via-SwiftShader (software) at startup, and safely coexists with MNN's existing Vulkan usage
- [ ] **Phase 4: RenderProcessor Implementation on bgfx** - A schema-declared render pass actually executes through bgfx's API and produces real texture output through the existing output pipeline
- [ ] **Phase 5: Determinism, CI & Cross-Tier End-to-End Verification** - A real render job runs through the full distributed pipeline on each of the 3 fallback tiers, produces a trustworthy hash, and existing inference behavior is provably unaffected

## Phase Details

### Phase 1: bgfx & SwiftShader Vendoring
**Goal**: bgfx and SwiftShader are vendored as new, buildable `thirdparty/` git submodules, wired into the existing CMake convention — pure build-system plumbing, with no runtime backend-selection logic and no dependency on schema or dispatch work.
**Depends on**: Nothing (first phase)
**Requirements**: CTX-04
**Success Criteria** (what must be TRUE):
  1. bgfx is added as a new `thirdparty/` git submodule and builds successfully through the existing `CommonBuildParameters.cmake`/`CommonTargets` convention, producing a linkable bgfx library target.
  2. SwiftShader is added as a new `thirdparty/` git submodule and builds successfully as its own CMake target within the same convention, producing its software Vulkan ICD artifact (e.g. `vk_swiftshader.{dll,so,dylib}` plus its ICD manifest).
  3. bgfx's Vulkan backend links against the already-vendored Vulkan-Headers/Vulkan-Loader (and MoltenVK on macOS/iOS) without introducing a second or conflicting Vulkan dependency tree.
  4. A trivial, throwaway test target that makes a single bgfx API call (e.g. `bgfx::getRendererName()`) compiles and links successfully against the new submodule on every supported platform, proving the CMake wiring end-to-end — no runtime backend-selection, headless context bring-up, or rendering logic is exercised or required at this stage.
**Plans**: TBD

### Phase 2: Schema Extension & Dispatch Foundation
**Goal**: Render pass definitions are schema-valid for bgfx and route safely through `ProcessingManager` without crashing or silently passing invalid configs.
**Depends on**: Nothing (architecturally independent of Phase 1's vendoring work — schema/dispatch changes don't require bgfx/SwiftShader to be buildable; can be developed and verified concurrently with Phase 1)
**Requirements**: SCHEMA-01, SCHEMA-02, SCHEMA-03, SCHEMA-04, SCHEMA-05, DISP-01, DISP-02, DISP-03
**Success Criteria** (what must be TRUE):
  1. A render pass definition with render-target/framebuffer config (color+depth attachments), vertex/index buffer bindings, and a multi-stage (vertex+fragment) shader pipeline validates against the extended schema.
  2. The schema's render-pass shader field represents bgfx-dialect shader source (or precompiled bgfx shader binaries) rather than a per-backend format the author must pick (`metal`/`hlsl`/`glsl`/`spirv` as separate targets) — a concrete field shape is settled and documented, resolving the open design question flagged in `FINAL-BACKEND-DECISION.md`.
  3. `generated/*.hpp` headers reflect the extended schema, produced via quicktype regeneration (never hand-edited).
  4. Submitting any model-less pass (render or compute) to `ProcessingManager::Process()` no longer crashes in `ParseBlockSize()` — the unconditional `pass.get_model().value()` is replaced with a type guard.
  5. `ProcessingManager::Process()` routes a render-type pass through a distinct `PassType`-keyed handler (`m_passMap`), never through the existing `DataType`-keyed MNN factory path, and `CheckProcessValidity()` rejects a render pass definition with no shader config present instead of silently passing it through as it does today.
**Plans**: TBD

### Phase 3: Three-Tier Backend Context & Fallback Sequencing
**Goal**: A process-wide, headless bgfx rendering context is available, explicitly resolving to one of the three fallback tiers at startup, and safely coexists with MNN's existing Vulkan usage.
**Depends on**: Phase 1 (needs bgfx and SwiftShader actually vendored and buildable before any runtime context/fallback code can be written or tested); independent of Phase 2 — can be developed concurrently with it
**Requirements**: CTX-01, CTX-02, CTX-03, CTX-05
**Success Criteria** (what must be TRUE):
  1. On a machine with a real GPU, the process initializes bgfx headless (`platformData.nwh = NULL`) directly on the Vulkan hardware tier as the first explicit attempt, with `bgfx::Init::fallback = false` — never relying on bgfx's built-in per-platform scored fallback cascade.
  2. On Linux only, when Vulkan hardware is unavailable, the process explicitly attempts the OpenGL hardware tier via a genuine EGL pbuffer headless context; this tier is never attempted on Windows (WGL has no auto pbuffer fallback) or macOS (not a default bgfx backend there).
  3. When no hardware Vulkan or (Linux) OpenGL device is found, the process forces bgfx's Vulkan renderer onto the SwiftShader software ICD vendored in Phase 1, and the active physical device is confirmed end-to-end to actually be the software rasterizer — not assumed to work from `BGFX_PCI_ID_SOFTWARE_RASTERIZER`'s documentation alone.
  4. MNN's existing Vulkan call sites and bgfx's Vulkan-backend init share one process-wide init lock (replacing the current function-local-static mutex that doesn't cover all MNN Vulkan sites today); a concurrent MNN-Vulkan-init + bgfx-Vulkan-init stress test completes with no race or crash.
**Plans**: TBD

### Phase 4: RenderProcessor Implementation on bgfx
**Goal**: A schema-declared render pass actually executes through bgfx's API and produces real texture output through the same output pipeline inference results use today.
**Depends on**: Phase 2, Phase 3
**Requirements**: RENDER-01, RENDER-02, RENDER-03, RENDER-04, RENDER-05, RENDER-06, RENDER-07, RENDER-08
**Success Criteria** (what must be TRUE):
  1. `RenderProcessor` compiles a schema-declared vertex+fragment bgfx-dialect shader pair through bgfx's own `shaderc` toolchain (distinct from Google's identically-named tool) into a working bgfx program.
  2. `RenderProcessor` uploads vertex/index buffer data resolved from `pass_io_binding` inputs via bgfx's buffer API (`bgfx::createVertexBuffer`/`createIndexBuffer`) and issues a draw call whose topology, cull mode, and winding order are controlled entirely by schema config, expressed through bgfx state flags.
  3. The render executes into an offscreen bgfx frame buffer (color+depth attachments) with depth testing enabled, with uniforms/parameters (e.g. MVP matrices) bound via `bgfx::setUniform` from `shader_config.uniforms`/`parameter:` refs — no swapchain ever created.
  4. The rendered output is read back (`bgfx::blit`/`bgfx::readTexture`) and exposed as a `texture2D` through the existing `pass_io_binding` output mechanism, optionally passed through the existing `data_transform` post-processing step (resize/crop/color_convert/etc.).
  5. The rendered output flows unmodified through `ProcessingResult` → `FileManager::SaveASync` → hash path, regardless of which of the 3 fallback tiers actually executed the pass.
**Plans**: TBD

### Phase 5: Determinism, CI & Cross-Tier End-to-End Verification
**Goal**: A real render job runs through the full distributed processing pipeline on each of the 3 fallback tiers, produces a hash a validator can trust, and existing inference behavior is provably unaffected.
**Depends on**: Phase 4
**Requirements**: DETV-01, DETV-02, DETV-03, E2E-01, E2E-02, E2E-03, E2E-04
**Success Criteria** (what must be TRUE):
  1. Executing the same render pass definition twice on the same node produces a bit-exact identical output hash, using whichever single tier that node resolved to at startup (a node's tier is chosen once and never changes between runs); cross-node, cross-vendor, and cross-tier tolerance verification are explicitly documented as out of scope for v1.
  2. A malformed/invalid job-supplied bgfx shader is rejected by bgfx's `shaderc` compile step before it reaches any GPU/software backend, with a clear validation failure rather than a crash.
  3. CI installs and exercises the vendored SwiftShader software Vulkan ICD, so the render path's tertiary (CPU) tier actually executes and is verified in CI, not skipped for lack of GPU hardware on Linux runners.
  4. A real render pass definition executes end-to-end through the distributed processing pipeline (task split → processing → result) and returns a verified output hash, including a run that actually executes — not merely compiles — on a MoltenVK/Apple target, with the OpenGL tier never attempted there.
  5. Each of the three fallback tiers (Vulkan hardware, OpenGL on Linux, Vulkan-via-SwiftShader software) is independently exercised in an end-to-end test with an actual draw-call-plus-readback round trip (not just a `bgfx::init()` success check), proving the explicit tier-sequencing logic (CTX-01/CTX-02) works as designed; the full existing MNN inference/retrain test suite passes with zero regressions alongside, including the concurrent MNN-Vulkan-init + bgfx-Vulkan-init stress test from Phase 3.
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 (Phase 2 may be developed concurrently with Phase 1; Phase 3 may be developed concurrently with Phase 2, but Phase 3 requires Phase 1 to land first; both Phase 2 and Phase 3 must land before Phase 4 starts)

| Phase | Plans Complete | Status | Completed |
|-------|-----------------|--------|-----------|
| 1. bgfx & SwiftShader Vendoring | 0/TBD | Not started | - |
| 2. Schema Extension & Dispatch Foundation | 0/TBD | Not started | - |
| 3. Three-Tier Backend Context & Fallback Sequencing | 0/TBD | Not started | - |
| 4. RenderProcessor Implementation on bgfx | 0/TBD | Not started | - |
| 5. Determinism, CI & Cross-Tier End-to-End Verification | 0/TBD | Not started | - |
