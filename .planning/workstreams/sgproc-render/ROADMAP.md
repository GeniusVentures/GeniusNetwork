# Roadmap: sgproc-render

## Milestones

- ✅ **v1.0** — Phases 01-05 (shipped 2026-07-31)
- ✅ **v2.0 Execution Contracts & Quality Gates** — Phases 06-09 (shipped 2026-08-07, closed with known gaps — see MILESTONES.md)
- ✅ **v2.1 Cross-Hardware Hash Tolerance** — Phases 10-13 (shipped 2026-08-13, closed with an accepted override — see MILESTONES.md)
- ✅ **v2.2 Cross-Hardware Validation Tolerance** — Phases 14-15 (shipped 2026-08-14)

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

<details>
<summary>✅ v2.1 Cross-Hardware Hash Tolerance (Phases 10-13) — SHIPPED 2026-08-13 (closed with an accepted override)</summary>

Full detail archived at `.planning/milestones/sgproc-render-v2.1-ROADMAP.md`.

**Phase Numbering:** Continued sequentially from v2.0's Phase 09 — this milestone started at Phase 10.

**Dependency order note:** These four phases had a hard, research-confirmed dependency chain and executed in numeric order without flattening or reordering: the quantization precision literally could not be chosen (Phase 12) before real cross-machine divergence data existed (Phase 11), which in turn needed the capture/diff tooling built first (Phase 10). Phase 13's re-validation was meaningless before Phase 12's real quantization logic landed.

- [x] Phase 10: Capture Harness & Diff Tool (Quantization Stub) (6/6 plans) — completed 2026-08-10
- [x] Phase 11: Empirical Cross-Machine Capture Run (1/1 plans) — completed 2026-08-12
- [x] Phase 12: Quantization / Normalization Implementation (2/2 plans) — completed 2026-08-12
- [x] Phase 13: Re-Validation & Scope Boundary Documentation (6/6 plans) — completed 2026-08-13, closed via accepted maintainer override on VALD-01 (see MILESTONES.md)

</details>

<details>
<summary>✅ v2.2 Cross-Hardware Validation Tolerance (Phases 14-15) — SHIPPED 2026-08-14</summary>

Full detail archived at `.planning/milestones/sgproc-render-v2.2-ROADMAP.md`.

**Phase Numbering:** Continued sequentially from v2.1's Phase 13 — this milestone started at Phase 14.

**Dependency order note:** Phase 15's validation-comparison mechanism (XNODE-01b/XNODE-02) and its SECV-02 counter-test depended on Phase 14's configurable-precision groundwork existing first. Phase 14 completed before Phase 15 began, no flattening.

- [x] Phase 14: Configurable Normalization Precision (3/3 plans) — completed 2026-08-14
- [x] Phase 15: Validation Comparison Mechanism (4/4 plans) — completed 2026-08-14, verified 8/8 must-haves

</details>

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
| 10. Capture Harness & Diff Tool (Quantization Stub) | v2.1 | 6/6 | Complete | 2026-08-10 |
| 11. Empirical Cross-Machine Capture Run | v2.1 | 1/1 | Complete | 2026-08-12 |
| 12. Quantization / Normalization Implementation | v2.1 | 2/2 | Complete | 2026-08-12 |
| 13. Re-Validation & Scope Boundary Documentation | v2.1 | 6/6 | Complete (override — VALD-01 MNN 1/15-chunk gap accepted, see 13-VERIFICATION.md) | 2026-08-13 |
| 14. Configurable Normalization Precision | v2.2 | 3/3 | Complete    | 2026-08-14 |
| 15. Validation Comparison Mechanism | v2.2 | 4/4 | Complete    | 2026-08-14 |
