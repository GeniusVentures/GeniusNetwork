---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Execution Contracts & Quality Gates
current_phase: 09
current_phase_name: Processor & Pass-Graph Conformance Suites
status: context-complete
stopped_at: Phase 09 context gathered — 6 decisions across 5 areas (fixtures, CTest layout, GPU tiers, conformance scope, regression, test location)
last_updated: "2026-08-05T00:00:00.000Z"
last_activity: 2026-08-05
last_activity_desc: Phase 09 discuss — Processor & Pass-Graph Conformance Suites: 6 decisions captured (fixtures follow processing_datatypes, per-category CTest, GTEST_SKIP GPU probe, full-pipeline conformance, synthetic regression triggers, tests in SuperGenius/test/src/)
progress:
  total_phases: 4
  completed_phases: 3
  total_plans: 15
  completed_plans: 15
  percent: 75
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-03), workstream section "Workstream: sgproc-render"

**Core value:** Elevate SGProcessingManager from a "parse-and-hope" pipeline to a contract-driven execution engine — jobs are validated before work starts, execution is cancellable and budget-aware, results are typed artifacts with provenance, and every processor is covered by a common test suite.
**Current focus:** Defining requirements and roadmap for v2.0

## Current Position

Phase: 09 — Processor & Pass-Graph Conformance Suites
Status: Context gathered — 8 decisions across 6 areas; ready for planning
Last activity: 2026-08-05 — Phase 09 discuss (test fixtures, CTest granularity, GPU tiers, conformance contract, regression triggers, test location)

Progress: [████████░░] 75% (4/4 Phase 06; 5/5 Phase 07; 3/3 Phase 08; Phase 09 context ready)

## Performance Metrics

**Velocity:**

- Total plans completed: 4 (this milestone)
- Previous milestone (v1.0): 24 plans across 5 phases

**By Phase:**
| Phase | Plans | Status |
|-------|-------|--------|
| 06 — Capability & Validation Foundation | 4/4 | ✓ Complete |
| 07 — Cancellable Execution Context | 5/5 | ✓ Complete (tests pending HW verification) |
| 08 — Structured Artifacts & Manifests | 3/3 | ✓ Complete |
| 09 — Processor & Pass-Graph Conformance Suites | TBD | ◌ Pending |

*Updated after each plan completion*

## Accumulated Context

### Key Decisions (v1.0 + v2.0 Phase 06-07)

- Hand-rolled Vulkan (no bgfx, no OpenGL, no SwiftShader) — continues in v2.0
- Shared process-wide Vulkan init-lock (`VulkanInitMutex`) for MNN + RenderProcessor coexistence
- `shaderc` + SPIRV-Tools for GLSL→SPIR-V compilation and validation
- `vk-bootstrap` (MIT) for Vulkan instance/device creation
- Vulkan Validation Layers: best-effort, debug-only, CMake toggle, no vendoring (D-20, D-24)
- All MNN processors on Vulkan backend under the shared mutex
- Schema + quicktype regeneration workflow (never hand-edit `generated/`)
- **NEW:** `CapabilityValidator` — pre-execution capability gate, internally constructed by `ProcessingManager`
- **NEW:** Startup snapshot pattern — Vulkan device + MNN registry queried once at Init()
- **NEW:** Executor identity = SHA-256 hash of capability snapshot (D-08)

### Pending Todos

None — Phase 06 complete.

### Blockers/Concerns

- Build verification pending — C++ compilation not tested in this session
- Unit tests need GTest framework available at build time
- Validation layers: system-level layer availability varies by platform (Vulkan SDK, NDK, MoltenVK)

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Phase 08 | Merkle tree over chunks | Deferred | 2026-08-05 |
| Phase 08 | Content-defined chunking | Deferred | 2026-08-05 |
| Phase 08 | Error message strings in manifest | Deferred | 2026-08-05 |
| Phase 08 | Schema evolution for binary format | Deferred | 2026-08-05 |

## Session Continuity

Last session: 2026-08-05
Stopped at: Phase 08 executed
Resume file: .planning/workstreams/sgproc-render/phases/08-structured-artifacts-execution-manifests/
