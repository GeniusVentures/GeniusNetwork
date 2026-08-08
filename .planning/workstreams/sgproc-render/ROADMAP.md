# Roadmap: sgproc-render

## Milestones

- ✅ **v1.0** — Phases 01-05 (shipped 2026-07-31)
- ✅ **v2.0 Execution Contracts & Quality Gates** — Phases 06-09 (shipped 2026-08-07, closed with known gaps — see MILESTONES.md)
- 🚧 **v2.1 Cross-Hardware Hash Tolerance** — planning in progress

## Phases

<details>
<summary>✅ v1.0 (Phases 01-05) — SHIPPED 2026-07-31</summary>

Full detail archived at `.planning/workstreams/sgproc-render/research/` (v1.0 research) and phase directories `01-*` through `05-*` under `.planning/workstreams/sgproc-render/phases/`.

- [x] Phase 01: Vulkan Context & Coexistence
- [x] Phase 01.1: CMake propagation + full MNN Vulkan migration
- [x] Phase 02: Schema Extension + Shader Compilation & Validation
- [x] Phase 03: Render Pipeline Execution + Determinism
- [x] Phase 04: Cross-platform CI + E2E — *1 UAT scenario and verification remain open, see MILESTONES.md Known Gaps*
- [x] Phase 05: Android/iOS Platform Compatibility

</details>

<details>
<summary>✅ v2.0 Execution Contracts & Quality Gates (Phases 06-09) — SHIPPED 2026-08-07 (with known gaps)</summary>

Full detail archived at `.planning/milestones/sgproc-render-v2.0-ROADMAP.md`.

- [x] Phase 06: Capability & Validation Foundation (4/4 plans) — *not phase_complete/verified per init.manager, see MILESTONES.md*
- [x] Phase 07: Cancellable Execution Context (5/5 plans) — *tests pending HW verification, see MILESTONES.md*
- [x] Phase 08: Structured Artifacts & Execution Manifests (3/3 plans) — *not phase_complete/verified per init.manager, see MILESTONES.md*
- [x] Phase 09: Processor & Pass-Graph Conformance Suites (15/15 plans) — completed 2026-08-07, formally verified

</details>

### 🚧 v2.1 Cross-Hardware Hash Tolerance (Planning)

Requirements and phase breakdown not yet defined — in progress via `/gsd-new-milestone`.

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|-----------------|--------|-----------|
| 01. Vulkan Context & Coexistence | v1.0 | — | Complete | 2026-07 |
| 01.1. CMake + MNN Vulkan migration | v1.0 | — | Complete | 2026-07 |
| 02. Schema Extension & Shader Validation | v1.0 | — | Complete | 2026-07 |
| 03. Render Pipeline Execution & Determinism | v1.0 | — | Complete | 2026-07 |
| 04. Cross-platform CI + E2E | v1.0 | — | Complete (gaps open) | 2026-07-31 |
| 05. Android/iOS Platform Compatibility | v1.0 | — | Complete | 2026-07-31 |
| 06. Capability & Validation Foundation | v2.0 | 4/4 | Complete (override) | 2026-08-05 |
| 07. Cancellable Execution Context | v2.0 | 5/5 | Complete (override, HW verification pending) | 2026-08-05 |
| 08. Structured Artifacts & Manifests | v2.0 | 3/3 | Complete (override) | 2026-08-05 |
| 09. Processor & Pass-Graph Conformance Suites | v2.0 | 15/15 | Complete, verified | 2026-08-07 |
