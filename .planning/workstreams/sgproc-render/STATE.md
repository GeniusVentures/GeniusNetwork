---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: Render Pass Execution (hand-rolled Vulkan)
current_phase: 3
current_phase_name: RenderProcessor Implementation & Determinism
status: executing
stopped_at: Completed 03-04-PLAN.md
last_updated: "2026-07-31T19:21:12.848Z"
last_activity: 2026-07-31
last_activity_desc: Phase 3 execution started
progress:
  total_phases: 5
  completed_phases: 3
  total_plans: 19
  completed_plans: 17
  percent: 60
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-29), workstream section "Workstream: sgproc-render"

**Core value:** Make SGProcessingManager's `render` PassType a real, executable graphics pipeline via hand-rolled Vulkan — headless/offscreen, own independent `VkInstance`/`VkDevice`, no new GPU backend/engine, no OpenGL or CPU/software fallback tier.
**Current focus:** Phase 3 — RenderProcessor Implementation & Determinism

## Current Position

Phase: 3 (RenderProcessor Implementation & Determinism) — EXECUTING
Plan: 5 of 6
Status: Ready to execute
Last activity: 2026-07-31 — Phase 3 execution started

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**

- Total plans completed: 7
- Average duration: N/A
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01.1 | 3 | - | - |
| 02 | 4 | - | - |

**Recent Trend:**

- Last 5 plans: N/A
- Trend: N/A

*Updated after each plan completion*
| Phase 01 P02 | 3min | 1 tasks | 0 files |
| Phase 01.1 P01 | 15min | 2 tasks | 2 files |
| Phase 01.1 P02 | 15min | 3 tasks | 13 files |
| Phase 01.1 P03 | 15min | 3 tasks | 3 files |
| Phase 02 P02 | ~100min | 3 tasks | 3 files |
| Phase 02 P03 | ~60min | 2 tasks | 13 files |
| Phase 02 P04 | ~45min | 2 tasks | 11 files |
| Phase 3 P03-01 | 35min | 2 tasks | 3 files |
| Phase 03 P02 | 55min | 2 tasks | 1 files |
| Phase 03 P03 | ~50min | 2 tasks | 2 files |
| Phase 03 P04 | 35min | 2 tasks | 2 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table (root project). Recent decisions affecting current work:

- Restart: hand-rolled Vulkan replaces the archived bgfx-based v1.0 attempt, which violated SGProcessingManager#7's "no new GPU backend, no duplicate platform setup" constraint (2026-07-29)
- Research reconciled: shared process-wide Vulkan init-lock (treating MNN's existing `mnn_vulkan_mutex` as stronger evidence than spec-only reasoning) — see research/SUMMARY.md Decision Flag #1
- Research reconciled: `shaderc` chosen over bare `glslang` for GLSL→SPIR-V, since `spirv-val`/SPIRV-Tools validation is mandatory regardless and shaderc bundles it — see research/SUMMARY.md Decision Flag #2
- Roadmap: Phase 2 (schema/shader validation) is independently developable and could run parallel to Phase 1 (Vulkan context); sequenced after Phase 1 for planning clarity only, not a hard dependency
- Roadmap: Dispatch plumbing (originally a separate research-suggested phase) folded into Phase 1 rather than standing alone — small/mechanical, no independent user-observable value on its own, and no hard ordering dependency on the rest of context setup
- [Phase 01-02]: D-01 resolved: adopt vk-bootstrap (charles-lunarg/vk-bootstrap, MIT), pinned at v1.4.357 — Confirmed live by orchestrating agent per auto_advance/yolo config; macOS/MoltenVK portability-subset risk outweighs zero-net-new-vendoring preference
- [Phase 01.1-01]: Bumped GeniusSDK/GeniusWallet submodule pointers after find_package(vk-bootstrap) fix, matching this project's chore(NN-NN): bump submodule pointer convention
- [Phase 01.1-02]: Migrated all 13 remaining CPU-backed MNN processors (14 createSession() call sites) to MNN_FORWARD_VULKAN, guarded by the shared VulkanInitMutex(); bumped SGProcessingManager and SuperGenius submodule pointers to reference the migration
- [Phase 01.1-03]: Fixed a third, previously-undiscovered vk-bootstrap CMake gap in SuperGenius/build/CommonBuildParameters.cmake (standalone build entry point) -- unblocked local build/run of ProcessingDatatypesTest and the concurrency stress test
- [Phase 02-01]: Confirmed via an actual quicktype v23.2.6 run that D-11 Amendment's design (new sibling `render_shader` property rather than re-typing `shader` per pass type) and D-16 Amendment's `vertex_buffer` addition both regenerate exactly as spike-verified — RenderTarget/VertexBuffer's required fields are plain (non-`boost::optional`) members, `Pass.hpp` gains all six new render-only accessors, and `ShaderSourceType` is shared correctly between `ShaderConfig`/`ShaderStage`
- [Phase 02-02]: Corrected SPIRV-Tools/SPIRV-Headers pins to the commits shaderc's own `v2024.3` tag's DEPS file references (`01c8438e`/`2a9b6f95`), not the plan's cited commits (read from shaderc `main`'s newer DEPS at research time); confirmed via a real local build+install that SPIRV-Tools installs a CMake CONFIG under bare (non-namespaced) target names, resolved via `find_package(SPIRV-Tools CONFIG)` + `add_library(SPIRV-Tools::SPIRV-Tools ALIAS SPIRV-Tools-static)`; shaderc confirmed to have no installed CMake config at all (hand-rolled IMPORTED target). Both `shaderc::shaderc`/`SPIRV-Tools::SPIRV-Tools` build-verified end-to-end (GLSL compiled to SPIR-V via shaderc, validated via SPIRV-Tools)
- [Phase 02-03]: Implemented `ShaderCompiler::CompileAndValidate()` with both the GLSL-compiled path and the direct-SPIR-V path each inlining their own `spvtools::SpirvTools::Validate()` call (not factored into a shared helper), so the plan's `grep -c "\.Validate("  == 2` acceptance criterion structurally proves neither path can skip the mandatory validation gate; build-verified end-to-end via a from-scratch MinGW+Ninja build of shaderc/SPIRV-Tools (this session's environment could not link against the MSVC-built project dependencies), all 6 unit tests passing including a mutated-valid-SPIR-V rejection test (the exact Pitfall 2 scenario)
- [Phase 02-04]: Wired `ShaderCompiler` into `ProcessingManager::GetCidForProc()`'s render-pass branch (per-stage fetch queued alongside the existing image fetch, single `ioc->run()` unchanged), extended `CheckProcessValidity()`'s render branch to plan 02-01's new schema fields, and closed a newly-live `std::runtime_error`-from-narrowed-enum crash vector in `Init()`'s JSON parsing; full MSBuild link-build was blocked by this working tree's missing installed vk-bootstrap/shaderc/SPIRV-Tools packages (same ephemeral-build-directory constraint as 02-03), substituted with a real MSVC `cl.exe /Zs` syntax+semantic check against the project's actual include paths -- both modified C++ files passed with 0 errors. Phase 02 is now fully complete (all 4 plans)
- [Phase 3]: ProcessingErrorStage/ProcessingError are plain (non-outcome::result) types on ProcessingResult per D-25's no-signature-change constraint
- [Phase 3]: D-28 MNN retroactive fix satisfied by treating empty ProcessingResult::hash as an additional failure signal -- zero changes to any of the 15 MNN processor files
- [Phase ?]: vertexBuffer->empty() explicit check preserves pre-existing INPUT_UNAVAIL semantics now that mainbuffers->second is always non-empty for render passes — Required to satisfy plan's own acceptance criterion (RenderPassValidGlslShadersCompileAndValidateEndToEnd must still fail with INPUT_UNAVAIL)
- [Phase ?]: index_buffer with absent source treated as no-index-buffer (skip), not an error — Schema permits index_type-only declarations; plan explicitly instructs treating this as unusable-here rather than rejecting
- [Phase 03-03]: MakeError() made static since it needs no instance state, letting also-static ParseCompiledStages()/ParseRenderPassConfig()/ResolveUniforms() call it directly — Avoids requiring an instance for wire-format-parsing helpers that don't otherwise touch RenderProcessor state
- [Phase 03-03]: ParseRenderPassConfig() wrapped in a function-try-block converting generated-setter constraint-violation exceptions (e.g. RenderTarget::set_width()'s minimum:1 check) into a structured RESOURCE_RESOLUTION error — a malformed/truncated wire-format buffer must never crash the process
- [Phase 03-04]: Added m_renderWidth/m_renderHeight member state so BuildPipeline() can build a mandatory fixed viewport/scissor -- the plan's signature never provided render-target dimensions to BuildPipeline() despite VkGraphicsPipelineCreateInfo requiring a concrete VkPipelineViewportStateCreateInfo when no dynamic viewport/scissor state is used
- [Phase 03-04]: Depth image view aspectMask conditionally ORs in VK_IMAGE_ASPECT_STENCIL_BIT for D24_UNORM_S8_UINT (a stencil component the schema never exposes/uses, but Vulkan's depth-stencil-attachment image-view rules require the view's aspectMask to reflect every physically-present aspect)

### Pending Todos

None yet.

### Blockers/Concerns

- Decision Flag #1 (Vulkan init synchronization) is not fully closed by research alone — Phase 1 must validate via an actual concurrent-init stress test, not assume the shared-lock design is correct from reasoning alone
- Decision Flag #2 (shaderc vs. glslang) is reconciled toward shaderc but should be explicitly confirmed during Phase 2 planning
- CI currently has zero real-GPU or software-Vulkan-ICD signal, and zero macOS CI signal for Vulkan at all — Phase 4 must resolve this, not assume it away
- Phase 02's full MSBuild link-build was never verified end-to-end in this working tree (Windows) — plans 02-02/02-03 relied on ephemeral from-source spike builds (MinGW) that no longer exist, and plan 02-04's verification was a real MSVC syntax+semantic check (`cl.exe /Zs`), not a full link. A real from-scratch (or restored ephemeral) build+test run of `ProcessingBase`/`processing_dispatch_test`/`shader_compiler_test` is recommended before or early in Phase 3

### Roadmap Evolution

- Phase 01.1 inserted after Phase 1: CMake vk-bootstrap discovery (find_package in CommonBuildParameters.cmake), MNN processors migrated from CPU to VULKAN backend using the shared vulkan mutex, plus coverage step (URGENT)

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none — this is a fresh milestone restart)* | | | |

## Session Continuity

Last session: 2026-07-31T19:21:12.842Z
Stopped at: Completed 03-04-PLAN.md
Resume file: None
