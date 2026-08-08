---
gsd_state_version: 1.0
milestone: v2.1
milestone_name: Cross-Hardware Hash Tolerance
current_phase: 10
status: Roadmap created — ready to plan Phase 10
stopped_at: Roadmap created for v2.1 (Phases 10-13, 12/12 requirements mapped); no plans yet
last_updated: "2026-08-07T23:56:19.341Z"
last_activity: 2026-08-07
last_activity_desc: v2.1 roadmap created (Phases 10-13)
progress:
  total_phases: 4
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-03), workstream section "Workstream: sgproc-render"

**Core value:** Elevate SGProcessingManager from a "parse-and-hope" pipeline to a contract-driven execution engine — jobs are validated before work starts, execution is cancellable and budget-aware, results are typed artifacts with provenance, and every processor is covered by a common test suite.
**Current focus:** v2.1 — Cross-Hardware Hash Tolerance

## Current Position

Phase: 10 — Capture Harness & Diff Tool (Quantization Stub) — not started
Plan: —
Status: Roadmap created (Phases 10-13), awaiting `/gsd-plan-phase 10`
Last activity: 2026-08-07 — v2.1 roadmap created, REQUIREMENTS.md traceability updated (12/12 mapped)

## Performance Metrics

**Velocity:**

- Total plans completed: 8 (v2.0 milestone, this workstream)
- Previous milestone (v1.0): 24 plans across 5 phases
- v2.1 (current milestone): 0 plans so far — roadmap just created, no phase planned yet

**By Phase:**
| Phase | Plans | Status |
|-------|-------|--------|
| 06 — Capability & Validation Foundation | 4/4 | ✓ Complete |
| 07 — Cancellable Execution Context | 5/5 | ✓ Complete (tests pending HW verification) |
| 08 — Structured Artifacts & Manifests | 3/3 | ✓ Complete |
| 09 — Processor & Pass-Graph Conformance Suites | 15/15 | ✓ Complete (gap-closure round 3 done: 09-13, 09-14, 09-15) |
| 10 — Capture Harness & Diff Tool (Quantization Stub) | 0/TBD | Not started |
| 11 — Empirical Cross-Machine Capture Run | 0/TBD | Not started |
| 12 — Quantization / Normalization Implementation | 0/TBD | Not started |
| 13 — Re-Validation & Scope Boundary Documentation | 0/TBD | Not started |

*Updated after each plan completion*
| Phase 09 P08 | 25min | 2 tasks | 4 files |
| Phase 09 P09 | 35min | 2 tasks | 2 files |
| Phase 09 P10 | 20min | 2 tasks | 1 file |
| Phase 09 P11 | 68min | 3 tasks | 5 files |
| Phase 09 P12 | 22min | 3 tasks | 4 files |
| Phase 09 P13 | 25min | 2 tasks | 1 files |
| Phase 09 P14 | 20min | 2 tasks | 2 files |
| Phase 09 P15 | 40min | 3 tasks | 3 files |

## Accumulated Context

### Key Decisions (v1.0 + v2.0 Phase 06-07)

- Hand-rolled Vulkan (no bgfx, no OpenGL, no SwiftShader) — continues in v2.0
- Shared process-wide Vulkan init-lock (`VulkanInitMutex`) for MNN + RenderProcessor coexistence
- `shaderc` + SPIRV-Tools for GLSL→SPIR-V compilation and validation
- `vk-bootstrap` (MIT) for Vulkan instance/device creation
- Vulkan Validation Layers: best-effort, debug-only, CMake toggle, no vendoring (D-20, D-24)
- All MNN processors on Vulkan backend under the shared mutex
- Schema + quicktype regeneration workflow (never hand-edit `generated/`)
- `CapabilityValidator` — pre-execution capability gate, internally constructed by `ProcessingManager`
- Startup snapshot pattern — Vulkan device + MNN registry queried once at Init()
- Executor identity = SHA-256 hash of capability snapshot (D-08)

### Key Decisions (v2.1 Roadmap)

- Phase order 10→11→12→13 is a hard dependency, not a preference: quantization precision (Phase 12) literally cannot be chosen before real cross-machine divergence data exists (Phase 11), which needs the capture/diff tooling built first (Phase 10). Roadmap explicitly forbids flattening or reordering this sequence.
- Phase 11 (Empirical Cross-Machine Capture Run) intentionally maps to zero of the 12 v2.1 requirements — it is a hands-on data-gathering checkpoint using Phase 10's tooling, not a coding phase. Kept as its own phase per research's explicit recommendation rather than folded into Phase 10 or Phase 12.
- QUANT-01's normalization technique (rounding, fixed-point conversion, bit-masking, or another approach) is deliberately left open in both REQUIREMENTS.md and ROADMAP.md — it is a design decision for Phase 12's planning to resolve using Phase 11's empirical data, not fixed in advance.
- SECV-01 (wrong-result-still-diverges counter-test) is scoped into Phase 12 alongside the real quantization logic, not deferred to Phase 13 — research flags this as the milestone's central, non-optional risk.
- ProcessingValidationCore::ValidateResults's concatenation bug and cross-node consensus/redundant-execution plumbing remain explicitly out of scope for all 4 phases (XNODE-01b/c, tracked in REQUIREMENTS.md v2 Requirements + Out of Scope table); Phase 13 documents this boundary rather than closing it.

### Pending Todos

None — roadmap just created. Next: `/gsd-plan-phase 10`.

### Blockers/Concerns

- Phase 11 requires physical access to ≥3 distinct machines (user's Mac + PC + a third) — this is a real-world logistical dependency, not a code blocker, but it gates Phase 12/13 from starting.
- Build verification pending on prior phases — C++ compilation not retested in this session
- Validation layers: system-level layer availability varies by platform (Vulkan SDK, NDK, MoltenVK)

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Phase 08 | Merkle tree over chunks | Deferred | 2026-08-05 |
| Phase 08 | Content-defined chunking | Deferred | 2026-08-05 |
| Phase 08 | Error message strings in manifest | Deferred | 2026-08-05 |
| Phase 08 | Schema evolution for binary format | Deferred | 2026-08-05 |
| v2.1 | Schema-configurable normalization precision (QUANT-CFG-01) | Deferred to future milestone | 2026-08-07 |
| v2.1 | ProcessingValidationCore::ValidateResults concatenation bug fix (XNODE-01b) | Deferred to future milestone | 2026-08-07 |
| v2.1 | Cross-node consensus/redundant-execution plumbing (XNODE-01c) | Deferred to future milestone | 2026-08-07 |

Items acknowledged and deferred at milestone v2.0 close on 2026-08-07:

| Category | Item | Status |
|----------|------|--------|
| uat | Phase 04: 04-UAT.md — 1 pending scenario | testing |
| verification | Phase 04: 04-VERIFICATION.md | human_needed |
| verification | Phase 06 (Capability & Validation Foundation) — `phase_complete=false` per init.manager | override_closeout |
| verification | Phase 07 (Cancellable Execution Context) — `phase_complete=false` per init.manager; tests pending HW verification | override_closeout |
| verification | Phase 08 (Structured Artifacts & Manifests) — `phase_complete=false` per init.manager | override_closeout |

## Session Continuity

Last session: 2026-08-07T03:26:34.255Z
Stopped at: v2.1 roadmap created (Phases 10-13), REQUIREMENTS.md traceability updated to 12/12 mapped, no plans created yet
Resume file: None

## Decisions

- [Phase ?]: Used DataType::FLOAT (not TENSOR) for corrected inference-input fixtures/literals, matching the [1,16] model shape and float-processing-definition.json precedent
- [Phase 09 P09]: Model-format rejection split across two layers — unrecognized format strings caught pre-parse in Init() as MODEL_FORMAT_UNSUPPORTED; recognized-but-non-MNN formats (ONNX/PyTorch/TensorFlow) caught post-parse in CheckProcessValidity()'s explicit ModelFormat::MNN check, same error/message
- [Phase 09 P10]: combinedHash/manifest.manifestHash computed over a timing-zeroed ExecutionManifest copy rather than modifying SerializeManifest()/ComputeManifestHash() themselves — preserves byte-for-byte compatibility with Phase 08's artifact_serializer_test.cpp round-trip tests over real timestamps
- [Phase 09 P11]: InferenceCanExecuteReflectsPassTypeRegistryGap documents (not fixes) that INFERENCE passes are schema-valid but not capability-registered — registering INFERENCE/RETRAIN into the capability registry is a separate, larger cross-phase change, deferred as a follow-up item
- [Phase 09 P11]: Fixed a genuine pre-existing crash in ProcessOutput's artifact-metadata builder (procInput.get_format().value() on an optional BUFFER-type inputs may omit) via value_or(INT8), mirroring CheckProcessValidity()'s existing default — newly exposed by the first-ever Process() call for a render pass
- [Phase 09 P12]: ProcessingManager::Process() gained a backward-compatible 5-arg overload accepting a caller-owned ExecutionContext (Gap 2/TEST-07); both overloads delegate to a shared private ProcessInternal(). Schema-derived budget fields AND progressCallback now apply only when the caller left the field unset — extended beyond the plan's literal text (which named only the 3 numeric fields) because the pre-existing unconditional progressCallback overwrite would have silently defeated the plan's own ProgressEventsEmitted test
- [Phase 09 P13]: MNN_String's per-tensor resize target derived from the job's schema-declared maxLength parameter (16 tiny embedding model / 128 legacy BERT model) instead of the plan's literally-specified tokenIds.size() -- both fixtures share a 12-token test_input.txt, so a token-count-driven resize breaks the tiny model's fixed-shape FC layer regardless; reading the already-present maxLength schema parameter (mirroring the existing tokenizerMode/vocabUri find-by-name pattern) satisfies the plan's actual must_haves
- [Phase 09 P14]: PassTypeToString() has no default: case (relies on -Wswitch for future unhandled enum values) but retains a post-switch numeric-string fallback for runtime safety; rejection message keeps raw int alongside the new name for existing log/debug consumers
- [Phase 09]: [Phase 09 P15]: Fixed processing_dispatch_test's ctest WORKING_DIRECTORY via a single-target set_tests_properties() override rather than modifying cmake/functions.cmake's shared addtest() helper, so the other ~60 SuperGenius ctest targets are unaffected
- [Phase 09]: [Phase 09 P15]: Gave render-pass-happy-path-definition.json a real outputs[0] entry mirroring regression-b-parseblocksize-model-only.json's already-proven pattern, rather than modifying ProcessingManager.cpp's already-correct !outputs.empty() gate
- [Phase 09]: [Phase 09 P15]: RenderPassSameNodeRepeatedExecutionProducesBitExactHash now asserts each iteration's combinedHash.size()==32 via a named iterHash local before pushing it, closing the vacuous-pass-on-empty-hashes gap
- [v2.1 Roadmap]: Phase structure (10-13) mirrors research/SUMMARY.md's "Implications for Roadmap" section verbatim in dependency order — capture+diff tooling, then empirical multi-machine run, then real quantization+security counter-test, then re-validation+scope documentation. No requirements were reassigned or reordered from the research's suggested sequence.

## Operator Next Steps

- Run `/gsd-plan-phase 10` to begin planning Phase 10: Capture Harness & Diff Tool (Quantization Stub)
- Phase 11 will require coordinating access to ≥3 physical machines (user's Mac + PC + a third) before it can execute — worth flagging early since it gates Phase 12/13
