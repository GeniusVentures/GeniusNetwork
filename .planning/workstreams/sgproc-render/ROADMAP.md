# Roadmap: sgproc-render (Render Pass Execution, hand-rolled Vulkan)

## Overview

This is a full restart of the archived bgfx-based v1.0 attempt (`.planning/milestones/ws-sgproc-render-2026-07-29/`), which never actually satisfied `GeniusVentures/SGProcessingManager#7`'s "no new GPU backend, no duplicate platform setup" constraint. The journey: first make it possible to stand up a headless Vulkan context safely alongside MNN's existing Vulkan usage and route render passes to it without crashing (Phase 1); then teach the processing schema to describe a full render pass and make every piece of SPIR-V provably safe before it reaches the driver (Phase 2); then build the actual `RenderProcessor` that executes a schema-declared pipeline and produces bit-exact repeatable output (Phase 3); then prove the whole path end-to-end across platforms, in CI, with zero regressions to existing MNN behavior (Phase 4). Each phase produces something independently verifiable — this is Vulkan mechanics against a well-understood target, not exploratory feature work.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Vulkan Foundation & Dispatch Plumbing** - Headless, coexistence-safe Vulkan context creation plus a non-crashing, dedicated dispatch path for render passes
- [ ] **Phase 2: Schema Extension & Shader/SPIR-V Validation Pipeline** - Schema describes a full render pass; all SPIR-V is validated before it can reach the driver
- [ ] **Phase 3: RenderProcessor Implementation & Determinism** - A schema-declared render pass actually executes and produces bit-exact repeatable output
- [ ] **Phase 4: Cross-Platform Build, CI & End-to-End Verification** - The render path is proven end-to-end, cross-platform, in CI, with zero regressions

## Phase Details

### Phase 1: Vulkan Foundation & Dispatch Plumbing

**Goal**: A headless Vulkan context can be created for `RenderProcessor` safely alongside MNN's existing Vulkan usage, and `ProcessingManager` can route render passes through a dedicated, non-crashing dispatch path.
**Depends on**: Nothing (first phase)
**Requirements**: CTX-01, CTX-02, CTX-03, CTX-04, DISP-01, DISP-02, DISP-03
**Success Criteria** (what must be TRUE):

  1. A headless `VkInstance`/`VkDevice`/`VkQueue` can be created for `RenderProcessor` with no `VkSurfaceKHR`, swapchain, or WSI extension present, on Windows, Linux, and macOS via MoltenVK (CTX-01)
  2. A concurrent-init stress test demonstrates MNN's existing 3 Vulkan-instance-creation call sites and `RenderProcessor`'s new call site all serialize through one shared, process-wide synchronization primitive with zero crashes or races across repeated concurrent runs, replacing MNN's file-scoped `mnn_vulkan_mutex` (CTX-02)
  3. Physical-device selection for `RenderProcessor` follows a documented, deterministic scoring policy — not "pick index 0" — and the same hardware always yields the same selected device across repeated runs (CTX-03)
  4. A written decision documents Vulkan-ValidationLayers vendoring as explicitly deferred to v1.x, not silently dropped (CTX-04)
  5. Submitting a render or compute pass (no `model` field) through `ParseBlockSize()` no longer crashes; `ProcessingManager::Process()` routes render passes through a new, separate `PassType`-keyed dispatch map (confirmed not colliding with the existing `DataType`-keyed map); and `CheckProcessValidity()` requires a shader config to be present for render passes (DISP-01, DISP-02, DISP-03)

**Plans**: 6/6 plans executed

Plans:
**Wave 1**

- [x] 01-01-PLAN.md — Vulkan init guard & MNN Vulkan call-site migration (CTX-02/D-04)
- [x] 01-02-PLAN.md — vk-bootstrap dependency legitimacy checkpoint (D-01 vendoring gate)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 01-03-PLAN.md — vk-bootstrap vendoring & validation-layers deferral decision (CTX-01/CTX-04)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 01-04-PLAN.md — RenderProcessor headless Vulkan context (CTX-01/CTX-03)

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 01-05-PLAN.md — ProcessingManager dispatch plumbing (DISP-01/02/03)

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 01-06-PLAN.md — Concurrent Vulkan init stress test (CTX-02/D-05)

### Phase 01.1: CMake vk-bootstrap discovery, MNN CPU-to-VULKAN processor migration, and coverage (INSERTED)

**Goal**: `GeniusSDK`/`GeniusWallet` configure cleanly against a `SGProcessingManager` submodule pointer that includes Phase 1's vk-bootstrap vendoring; every MNN processor in `SGProcessingManager` runs on the Vulkan backend under the existing shared init-time mutex with zero new races; and the migration's correctness is proven via the existing local regression-test suite, not new coverage tooling.
**Depends on**: Phase 1 (complete)
**Requirements**: CMAKE-01, MIGR-01, MIGR-02, COV-01
**Success Criteria** (what must be TRUE):

  1. `GeniusSDK/cmake/CommonBuildParameters.cmake` and `GeniusWallet/cmake/CommonBuildParameters.cmake` both resolve `vk-bootstrap::vk-bootstrap` via `find_package(vk-bootstrap CONFIG REQUIRED)`, mirroring `SGProcessingManager`'s own established per-consumer convention (CMAKE-01)
  2. All 13 remaining CPU-backed MNN processors (14 `createSession()` call sites) request `MNN_FORWARD_VULKAN` and are guarded by the existing shared `VulkanInitMutex()` — matching the already-migrated `image`/`string`/`volume` processors, with zero new synchronization primitives (MIGR-01)
  3. `vulkan_init_guard.hpp`'s doc comment and `vulkan_init_concurrency_test.cpp`'s scope note no longer undercount the real, post-migration set of Vulkan-init call sites sharing the mutex (MIGR-02)
  4. The existing `ProcessingDatatypesTest` suite's 13 migration-candidate `*ProcessingTest` cases are re-verified against the newly-Vulkan-backed processors within their existing tolerance bounds — no gcov/lcov/OpenCppCoverage or other new coverage tooling is introduced (COV-01)

**Plans**: 3/3 plans complete

Plans:
**Wave 1**

- [x] 01.1-01-PLAN.md — CMake vk-bootstrap find_package propagation to GeniusSDK/GeniusWallet (CMAKE-01)
- [x] 01.1-02-PLAN.md — MNN CPU-to-VULKAN processor migration, 13 files/14 call sites (MIGR-01)

**Wave 2** *(blocked on 01.1-02 completion)*

- [x] 01.1-03-PLAN.md — Doc-comment accuracy update + ProcessingDatatypesTest coverage re-verification (MIGR-02/COV-01)

### Phase 2: Schema Extension & Shader/SPIR-V Validation Pipeline

**Goal**: The processing schema can fully describe a render pass, and every piece of SPIR-V that could reach the GPU — compiled from job-supplied GLSL or submitted directly — is validated before it ever reaches the driver.
**Depends on**: None structurally (independently developable in parallel with Phase 1 — GLSL/SPIR-V validation needs no `VkInstance`; sequenced second here for planning clarity only, per research's phase-ordering rationale)
**Requirements**: SCHEMA-01, SCHEMA-02, SCHEMA-03, SCHEMA-04, SCHEMA-05, SHADER-01, SHADER-02, SHADER-03
**Success Criteria** (what must be TRUE):

  1. A render pass definition in `gnus-processing-schema.json` can declare a render-target/framebuffer config (color+depth attachment formats, dimensions, clear values), vertex/index buffer bindings with per-attribute strides and offsets, a multi-stage (vertex+fragment) shader array, and pipeline state (topology, cull mode, winding order, depth-test) (SCHEMA-01, SCHEMA-02, SCHEMA-03, SCHEMA-04)
  2. All of the above is consumable through quicktype-regenerated headers with zero hand-edits to `generated/` (SCHEMA-05)
  3. GLSL shader source supplied by a job is compiled to SPIR-V in-process via a vendored `shaderc` toolchain at job-load time, before any GPU call is made (SHADER-01)
  4. Malformed or invalid SPIR-V — whether produced by GLSL compilation or submitted directly via `shader_config.type: "spirv"` — is rejected by a mandatory `spirv-val` gate with a clean error and never reaches `vkCreateShaderModule` (SHADER-02)
  5. `shader_config.type: "spirv"` is explicitly accepted for render passes as a validated input path, subject to the `spirv-val` gate — not silently rejected or silently trusted (SHADER-03)

**Plans**: 1/4 plans executed

Plans:
**Wave 1**

- [x] 02-01-PLAN.md — Fix blocking schema JSON bug, extend gnus-processing-schema.json (render_target/render_shader/vertex_layout/index_buffer/pipeline_state), regenerate quicktype headers (SCHEMA-01/02/03/04/05, SHADER-03)
- [ ] 02-02-PLAN.md — Vendor shaderc + SPIRV-Tools + SPIRV-Headers as pinned git submodules with CMake IMPORTED targets (SHADER-01/02 vendoring)

**Wave 2** *(blocked on 02-01/02-02 completion)*

- [ ] 02-03-PLAN.md — ShaderCompiler component (shaderc compile + SPIRV-Tools validate) with unit tests (SHADER-01/02/03)

**Wave 3** *(blocked on 02-03 completion)*

- [ ] 02-04-PLAN.md — Wire ShaderCompiler into ProcessingManager (CheckProcessValidity/GetCidForProc), end-to-end dispatch tests (SCHEMA-01/02/03/04, SHADER-01/02/03)

### Phase 3: RenderProcessor Implementation & Determinism

**Goal**: A schema-declared render pass actually executes on the headless Vulkan context — pipeline built, buffers uploaded, offscreen draw performed, output read back — and produces bit-exact repeatable output on the same node.
**Depends on**: Phase 1, Phase 2 (needs a working, coexistence-safe Vulkan context and dispatch path, plus validated SPIR-V, before a pipeline can be built and executed)
**Requirements**: RENDER-01, RENDER-02, RENDER-03, RENDER-04, RENDER-05, RENDER-06, RENDER-07, RENDER-08, RENDER-09, DETV-01, DETV-02
**Success Criteria** (what must be TRUE):

  1. `RenderProcessor` builds a vertex+fragment graphics pipeline from schema-declared, validated SPIR-V, with pipeline state (topology, cull mode, winding order) configurable via schema (RENDER-01, RENDER-04)
  2. Vertex/index buffer data resolved from `pass_io_binding` inputs uploads via direct Vulkan buffer APIs and renders to an offscreen, depth-tested framebuffer with no swapchain, with uniforms/parameters bound via push constants and falling back to descriptor-set uniforms when push-constant size limits are exceeded (RENDER-02, RENDER-03, RENDER-05)
  3. Rendered output is read back via `vkCmdCopyImageToBuffer` and exposed as `texture2D` through the existing `pass_io_binding` output mechanism, optionally flows through the existing `data_transform` post-processing step, and feeds the unmodified `ProcessingResult` → `FileManager::SaveASync` → hash path (RENDER-06, RENDER-07, RENDER-08)
  4. `VkResult` failures at any stage map to structured `ProcessingManager::Error` values with clear per-failure-point messages (RENDER-09)
  5. The same render pass definition executed N≥10 times on the same node/hardware produces a bit-exact matching output hash every time, achieved through architectural guards — explicit clear ops (never `DONT_CARE`) on hashed regions, `VK_SAMPLE_COUNT_1_BIT` always, fixed shader precision qualifiers, no unordered parallel-reduction shader math — rather than incidental behavior (DETV-01, DETV-02)

**Plans**: TBD

### Phase 4: Cross-Platform Build, CI & End-to-End Verification

**Goal**: The render path is proven end-to-end across target platforms (including macOS/MoltenVK) and continuously verified in CI, with zero regressions to existing MNN inference/retrain behavior.
**Depends on**: Phase 3 (needs a working `RenderProcessor` before end-to-end execution, cross-platform runs, and CI tiers can be meaningfully validated)
**Requirements**: DETV-03, E2E-01, E2E-02, E2E-03
**Success Criteria** (what must be TRUE):

  1. CI runs a hardware-independent tier — schema validation, shader compile, `spirv-val`, pipeline construction via a software Vulkan ICD — on every build, test-only and never exercised from product code (DETV-03)
  2. CI runs a hardware-dependent tier — real draw+readback, the N≥10 repeat-run determinism test — on a real-GPU runner (DETV-03)
  3. A real render pass definition executes end-to-end through the actual distributed processing pipeline and produces a verified output hash (E2E-01)
  4. The render path actually executes — not just compiles — on a MoltenVK/macOS target (E2E-02)
  5. The full existing MNN inference/retrain test suite passes with zero regressions alongside the new render path, including a concurrent-init stress test proving Phase 1's shared Vulkan-init lock holds under real concurrent MNN-Vulkan-init + `RenderProcessor`-Vulkan-init load (E2E-03)

**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 01.1 → 2 → 3 → 4 (Phase 01.1 is an urgent insertion between 1 and 2; Phase 2 is independently developable and could run in parallel with Phase 1 if desired; sequenced here for planning clarity)

| Phase | Plans Complete | Status | Completed |
|-------|-----------------|--------|-----------|
| 1. Vulkan Foundation & Dispatch Plumbing | 6/6 | Complete | 2026-07-29 |
| 01.1. CMake vk-bootstrap discovery, MNN CPU-to-VULKAN processor migration, and coverage (INSERTED) | 3/3 | Complete    | 2026-07-30 |
| 2. Schema Extension & Shader/SPIR-V Validation Pipeline | 1/4 | In Progress|  |
| 3. RenderProcessor Implementation & Determinism | 0/TBD | Not started | - |
| 4. Cross-Platform Build, CI & End-to-End Verification | 0/TBD | Not started | - |

---
*Roadmap created: 2026-07-29*
*Granularity: coarse (4 phases)*
