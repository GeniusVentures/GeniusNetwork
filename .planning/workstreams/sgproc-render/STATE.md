---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: Render Pass Execution
current_phase: 1
current_phase_name: bgfx & SwiftShader Vendoring
status: Ready to plan
stopped_at: Roadmap restructured to split bgfx/SwiftShader vendoring into its own Phase 1, all 28 v1 requirements remapped across 5 phases
last_updated: "2026-07-28T23:00:00.000Z"
last_activity: 2026-07-28
last_activity_desc: ROADMAP.md restructured (4 phases -> 5 phases) to separate bgfx/SwiftShader vendoring (CTX-04, new Phase 1, pure build-system plumbing) from the runtime three-tier backend-context/fallback logic (CTX-01/02/03/05, now Phase 3); REQUIREMENTS.md traceability updated to match
progress:
  total_phases: 5
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Current Position

Phase: 1 of 5 (bgfx & SwiftShader Vendoring)
Plan: — (not yet planned)
Status: Ready to plan
Last activity: 2026-07-28 — ROADMAP.md restructured into 5 phases; bgfx/SwiftShader vendoring split out as its own earliest phase, all 28 v1 requirements remapped

Progress: [░░░░░░░░░░] 0%

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-28), "Workstream: sgproc-render" section

**Core value:** Make `PassType::RENDER` a real, executable graphics pipeline with MNN-style graceful backend fallback — extending the schema for render targets, vertex/index buffers, and multi-stage shaders, then wiring it end-to-end through bgfx with an explicit three-tier fallback chain (Vulkan hardware → OpenGL hardware on Linux → Vulkan-via-SwiftShader software).
**Current focus:** Phase 1 — bgfx & SwiftShader Vendoring (pure build-system plumbing: add both as `thirdparty/` git submodules, wire into `CommonBuildParameters.cmake`/`CommonTargets`, confirm they build and link — no runtime backend-selection logic yet, that lands in Phase 3)

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: N/A
- Total execution time: N/A

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table (sgproc-render workstream) and this workstream's research/ documents.

- **Full architecture pivot to bgfx (2026-07-28), superseding the prior raw-Vulkan-only roadmap.** See `research/FINAL-BACKEND-DECISION.md` for the full reasoning trail (STACK.md → RENDER-BACKEND-DECISION.md → BGFX-HEADLESS-VERIFICATION.md → this decision). The pre-bgfx 4-phase roadmap (vk-bootstrap+VMA+Google-shaderc, hand-rolled `RenderProcessor`, `VKCTX-01..03`) was discarded entirely — REQUIREMENTS.md was rewritten first (28 v1 reqs, up from 24/25), and a roadmap was regenerated from scratch against the new requirement set.
- **Roadmap restructured a second time (2026-07-28, same day) to split bgfx/SwiftShader vendoring out of the former Phase 2.** The former Phase 2 ("bgfx Vendoring & Three-Tier Backend Context") bundled build-system plumbing (`CTX-04`: vendor bgfx/SwiftShader as `thirdparty/` submodules, wire into CMake) together with runtime backend-selection logic (`CTX-01/02/03/05`: headless init, tier sequencing, shared Vulkan lock, SwiftShader ICD forcing). The user asked for these to be separate phases — vendoring is foundational build-system work that should land first and independently, before any code depends on bgfx/SwiftShader actually being buildable. Result: 5 phases total. New Phase 1 (vendoring, `CTX-04` only, build-system-level success criteria — e.g. a trivial bgfx API call compiles/links, SwiftShader produces its ICD artifact — explicitly NOT runtime behavior). Former Phase 1 (schema/dispatch) becomes Phase 2, content unchanged. Former Phase 2's runtime requirements become Phase 3 ("Three-Tier Backend Context & Fallback Sequencing"), now depending on Phase 1, independent of Phase 2. Former Phase 3/4 (`RenderProcessor`, determinism/CI/E2E) become Phase 4/5 verbatim, dependency lines renumbered.
- Roadmap was originally compressed to 4 phases per `granularity: coarse`; the vendoring split above is a targeted user-directed exception to that compression, not a reversal of the general coarse-granularity approach — no other phase boundaries changed.
- Phase 3 (bgfx/SwiftShader runtime context & fallback) has a hard dependency on Phase 1 (needs bgfx/SwiftShader vendored and buildable first) but no dependency on Phase 2 (schema/dispatch) — architecturally independent, can be developed/smoke-tested concurrently with Phase 2. Both Phase 2 and Phase 3 must land before Phase 4 (`RenderProcessor`) starts. Phase 3 carries this milestone's highest-severity pitfalls: Windows-OpenGL-tier exclusion (WGL has no headless pbuffer path), unverified `BGFX_PCI_ID_SOFTWARE_RASTERIZER` propagation to Vulkan physical-device selection, and the shared Vulkan-init lock needed against MNN's existing (function-local-static, insufficient) mutex.
- `SCHEMA-04` is an explicitly open design question carried into Phase 2 (was Phase 1 pre-restructure), not a settled format: whether the render-pass shader field represents raw bgfx-dialect source text or precompiled bgfx shader binaries. Must be resolved during Phase 2 planning/implementation, not deferred further.
- `DETV-01`'s same-node-only determinism scope (a node's fallback tier is chosen once at startup and pinned for that node's lifetime — never re-evaluated mid-operation, per `FINAL-BACKEND-DECISION.md`'s open-questions section) carries forward unchanged; cross-node/cross-vendor/cross-tier verification remains explicitly out of scope for v1 (v2 `XNODE-01`).

### Pending Todos

None yet.

### Blockers/Concerns

- Cross-node/cross-vendor/cross-tier render-output verification policy is explicitly out of scope for v1 (same-node determinism only, DETV-01) — a real, unresolved industry-wide tradeoff, not a gap in this roadmap. Revisit only if a future milestone needs heterogeneous-hardware verification (v2 XNODE-01).
- `BGFX_PCI_ID_SOFTWARE_RASTERIZER`'s end-to-end effect on Vulkan physical-device selection has not been traced past the constant's existence/documentation (per `BGFX-HEADLESS-VERIFICATION.md` Pitfall 3) — flagged as an implementation-time spike for Phase 3 (was Phase 2 pre-restructure), not assumed to work from docs alone (CTX-05).
- Whether to vendor Vulkan-ValidationLayers (VVL) for debug builds remains an explicit open decision, not resolved by research — flagged for Phase 1 or Phase 3 planning to make and document (v2 VVL-01 tracks the deferred alternative).
- Whether SwiftShader's CPU performance is adequate for real render-job SLAs is unverified — Mesa lavapipe is reported faster but heavier to vendor (full Mesa/Meson tree vs. SwiftShader's standalone CMake repo); tracked as v2 LAVAPIPE-01 if SwiftShader proves inadequate.
- Descriptor/sampler binding infrastructure needed for multi-pass chains and external-texture sampling does not exist yet and is deliberately out of scope for this milestone — flagged for a future milestone (v2 MPASS-01/TEXIN-01), not built speculatively now.

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none — this is the first milestone for this workstream)* | | | |

## Session Continuity

Last session: 2026-07-28T23:00:00.000Z
Stopped at: ROADMAP.md restructured into 5 phases (bgfx/SwiftShader vendoring split into new Phase 1, ahead of the runtime three-tier backend-context work now in Phase 3); all 28 v1 requirements remapped; REQUIREMENTS.md traceability table updated
Resume file: None

## Operator Next Steps

- Run `/gsd-plan-phase 1` to plan the bgfx & SwiftShader Vendoring phase.
