---
gsd_state_version: 1.0
milestone: v2.1
milestone_name: Cross-Hardware Hash Tolerance
current_phase: 11
current_phase_name: Empirical Cross-Machine Capture Run
status: verifying
stopped_at: Completed 10-05-PLAN.md
last_updated: "2026-08-11T21:47:20.752Z"
last_activity: 2026-08-11
last_activity_desc: Phase 10 complete, transitioned to Phase 11
progress:
  total_phases: 4
  completed_phases: 1
  total_plans: 6
  completed_plans: 6
  percent: 25
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-03), workstream section "Workstream: sgproc-render"

**Core value:** Elevate SGProcessingManager from a "parse-and-hope" pipeline to a contract-driven execution engine — jobs are validated before work starts, execution is cancellable and budget-aware, results are typed artifacts with provenance, and every processor is covered by a common test suite.
**Current focus:** Phase 10 — capture-harness-diff-tool-quantization-stub

## Current Position

Phase: 11 — Empirical Cross-Machine Capture Run
Plan: Not started
Status: Phase complete — ready for verification
Last activity: 2026-08-11 — Phase 10 complete, transitioned to Phase 11

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
| 10 — Capture Harness & Diff Tool (Quantization Stub) | 0/6 | Planned |
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
| Phase 10 P01 | 3min | 2 tasks | 5 files |
| Phase 10 P02 | 12min | 2 tasks | 6 files |
| Phase 10 P03 | 10min | 3 tasks | 7 files |
| Phase 10 P04 | 20min | 2 tasks | 3 files |
| Phase 10 P05 | 25min | 2 tasks | 5 files |
| Phase 10 P06 | 20min | 2 tasks | 5 files |

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

- Phase 11 data gathering already started ahead of formal phase kickoff: `capture_harness` run on Mac (Fuu's-Mac-mini, macOS) and Windows (Mofu, Windows) for both the MNN-float and render-happy-path fixtures; 4 `.cap` files + 2 `capture_diff` JSON reports live in `caps/` at repo root (not yet moved into a phase-owned location). Still need a third machine's captures for full v2.1 3-machine coverage.
- **Empirical finding for Phase 12 planning:** MNN float genuinely diverges cross-hardware (Mac vs Windows) — `maxAbsDelta≈1.04e-07`, `maxRelDelta≈7.27e-05`, `maxUlpDistance=768`, 0% over the fixed 1e-4 relative threshold. Render pass is bit-identical cross-hardware (`contentHashMatch: true`, 0 divergence) — `combinedHashMatch: false` on render is expected/by-design (manifest-level hash includes per-machine `executorIdentity`, not a content difference); Phase 11/12 tooling should key off `contentHashMatch`/numeric stats, not `combinedHashMatch`, for cross-machine equivalence.
- Next: formally kick off `/gsd-discuss-phase 11 --ws sgproc-render` (or fold the already-gathered 2-machine data in when it starts) once the third machine is available.

### Blockers/Concerns

- Phase 11 requires physical access to ≥3 distinct machines (user's Mac + PC + a third) — 2 of 3 already captured (see Pending Todos); still need the third machine before Phase 11 can be considered complete, but this gates Phase 12/13 from starting.
- Build verification pending on prior phases — C++ compilation not retested in this session
- Validation layers: system-level layer availability varies by platform (Vulkan SDK, NDK, MoltenVK)
- **Pre-existing bug found during Phase 10's regression gate (not caused by Phase 10 — confirmed via diff, none of the implicated files were touched by any of Phase 10's 6 plans):** `ProcessingDatatypesTest`/`ProcessingDispatchTest`/`vulkan_init_concurrency_test` all deadlock/crash in `ProcessingManager::Create()`'s Vulkan capability-probe path (`VulkanInitMutex()` re-entered on the same thread) whenever a real Vulkan device is present. Tracked at `.planning/todos/pending/2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md`. Does not block Phase 10 — `processing_conformance_hashing_test` (the most directly relevant regression check for Phase 10's changes) and `CaptureSmokeTest` both pass.

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

Last session: 2026-08-11
Stopped at: Phase 10 UAT complete (both D-05/CAPT-02 abort paths verified live via temporary patch-and-revert), phase marked complete, transitioned to Phase 11. Ad-hoc Phase 11 data gathering started (2/3 machines, see Pending Todos).
Resume file: None

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
- [Phase 10-01]: rawOutputCapture deliberately excluded from ExecutionContext::NoOp()'s assignments, unlike progressCallback, with an inline comment warning future readers not to fix this to match progressCallback's pattern
- [Phase 10-02]: Used unqualified sgprocmanagerquant::QuantizeFloatBuffer (not sgns::sgprocmanagerquant::...) to match each file's existing unqualified sgprocmanagersha::sha256 call convention

## Operator Next Steps

- Phase 10 complete. `/gsd-discuss-phase 11 --ws sgproc-render` when ready to formally scope Phase 11 (2 of 3 required machines already captured ad-hoc this session — see Pending Todos).
- Get the third machine's `.cap` files (MNN-float + render, `--repeat 2` minimum) before Phase 11 can close out.

## Decisions

- [Phase ?]: Used unqualified sgprocmanagerquant::QuantizeFloatBuffer (not sgns::sgprocmanagerquant::...) in the 7 chained-family MNN processors, matching Plan 10-02's precedent and each file's existing unqualified sgprocmanagersha::sha256 call convention
- [Phase 10-04]: combinedHash uses a 4-byte length prefix while per-record preQuantizeBytes/quantizedBytes use 8-byte length prefixes, matching the plan's exact wire-format spec — combinedHash is always exactly 32 bytes; capture records can plausibly hold megapixel-scale raw output
- [Phase 10-04]: Verified round-trip/truncation/oversized-length acceptance criteria via a standalone scratch CMake build rather than a permanent CTest target — this plan's files_modified scope is the .hpp/.cpp pair only; a permanent test/capture/ CMakeLists.txt + smoke test is assigned to a later wave per 10-PATTERNS.md
- [Phase ?]: capture_diff hard-exits on chunkHashCount mismatch between compared .cap files (incompatible comparison), but treats a quantizedBytes byte-length mismatch as non-fatal (sizeMismatch flag, skip numeric pass only)
- [Phase ?]: sgproccapture CMake target needed an added SGProcessingManager-root include dir so capture_file_format.cpp's root-relative include resolves through the real build
- [Phase 10-06]: Moved enable_testing() before add_subdirectory(ProofSystem/SGProcessingManager/evmrelay/src) in SuperGenius/build/CommonBuildParameters.cmake — Pre-existing ordering bug made every test under SGProcessingManager/test/ (Phase 06-08 suites + this plan's capture_smoke_test) permanently undiscoverable by ctest, since CTestTestfile.cmake generation requires testing to already be enabled in a directory's ancestor scope at configure time
