# Roadmap: sgproc-render v2.0 — Execution Contracts & Quality Gates

## Overview

Elevate SGProcessingManager from a "parse-and-hope" pipeline to a contract-driven execution engine. Four phases: (1) pre-execution validation — capability checks and Vulkan validation layers; (2) cancellable, budget-aware execution contexts; (3) typed artifact records and deterministic execution manifests; (4) a common conformance test suite covering every processor and every new contract. Each phase is independently verifiable and builds on the hand-rolled Vulkan foundation from v1.0.

## Phases

**Phase Numbering:** Continues from v1.0's last phase (05). v2.0 starts at Phase 06.

- [x] **Phase 06: Capability & Validation Foundation** — Jobs are validated against node capabilities before any work begins; Vulkan validation layers are toggleable (best-effort, no vendoring)
- [x] **Phase 07: Cancellable Execution Context** — Every processor receives a cancellation token, deadline, budgets, and progress callbacks; resources are safely cleaned up on termination
- [ ] **Phase 08: Structured Artifacts & Execution Manifests** — Results are typed artifact records with provenance; execution manifests serialize deterministically
- [x] **Phase 09: Processor & Pass-Graph Conformance Suites** — CTest targets cover every processor against a common contract; regression tests lock in known bug fixes (round-2 goal-backward verification found 5 further gaps 2026-08-06, closed by 09-11..09-13; UAT round found 3 further gaps 2026-08-06/07 — capability_validator_test PassType message, processing_dispatch_test ctest working-directory, render-pass happy-path combinedHash — plans 09-14..09-15 close them) (completed 2026-08-07)

## Phase Details

### Phase 06: Capability & Validation Foundation

**Goal**: Before a job is executed, the node validates whether it CAN execute it — across all pass types, Vulkan features, model formats, and resource requirements — returning specific unmet-requirement reasons. Vulkan validation layers are a best-effort, debug-only toggle (no vendoring).

**Depends on**: v1.0 foundation (Vulkan context, schema, RenderProcessor, shaderc/SPIRV-Tools)

**Requirements**: CAP-01, CAP-02, CAP-03, CAP-04, CAP-05, CAP-06, VVAL-01, VVAL-02, VVAL-03, VVAL-04

**Success Criteria** (what must be TRUE):

1. A job with unsupported Vulkan features returns a structured `CanExecute` rejection listing exactly which features/extensions/limits are unmet, not a generic "unsupported" message (CAP-02).
2. A job with an unsupported model format, quantization, or tokenizer for MNN inference returns specific unmet-requirement reasons identifying the mismatch (CAP-03).
3. A job with an unregistered `PassType` returns a rejection naming the pass type and listing available registered executors (CAP-04).
4. The selected executor identity is stable across repeated capability checks for the same job definition (CAP-06).
5. ~~Vulkan validation layers build as `thirdparty/` submodule(s)~~ **OVERRIDDEN by D-20:** Layers are best-effort only — loaded by name via vk-bootstrap if present on system; not vendored. See `06-CONTEXT.md` D-20 through D-25.
6. Validation layers can be toggled on/off for `RenderProcessor`'s `VkInstance` via the CMake option `ENABLE_VULKAN_VALIDATION` — ON by default in Debug, OFF in Release (VVAL-03).

**Plans**: 4 plans in 2 waves

**Plans:**

- [x] 06-01-PLAN.md — Capability data types + CapabilityValidator header + BuildSnapshot
- [x] 06-02-PLAN.md — CanExecute implementation: Vulkan/MNN/PassType/Resource validation + identity hash
- [x] 06-03-PLAN.md — ProcessingManager integration + unit tests covering all rejection categories
- [x] 06-04-PLAN.md — CMake option ENABLE_VULKAN_VALIDATION + #ifdef gate in RenderProcessor + build verification

| Plan | Wave | Requirements | Autonomous |
|------|------|-------------|------------|
| 06-01 | 1 (CAP) | CAP-01, CAP-06 | yes |
| 06-02 | 1 (CAP) | CAP-02, CAP-03, CAP-04, CAP-05 | yes |
| 06-03 | 1 (CAP) | CAP-01 | no (checkpoint:human-verify) |
| 06-04 | 2 (VVAL) | VVAL-01, VVAL-02, VVAL-03, VVAL-04 | yes |

### Phase 07: Cancellable Execution Context

**Goal**: Every processor receives a cooperative cancellation token, per-pass deadline, resource budgets, and structured progress callbacks. On any terminal condition (cancel, timeout, budget exceeded, failure), all Vulkan/MNN resources and pending async saves are safely cleaned up. Existing processors work through an adapter during migration.

**Depends on**: Phase 06 (CAP — execution context design needs to know what capability information is available)

**Requirements**: EXEC-01, EXEC-02, EXEC-03, EXEC-04, EXEC-05, EXEC-06, EXEC-07

**Success Criteria** (what must be TRUE):

1. A running MNN or Vulkan render job can be cancelled via the cancellation token; the job does NOT publish a successful result, and all Vulkan resources (pipelines, buffers, images, command pools), MNN sessions, and pending `FileManager::SaveASync` calls are cleaned up with zero leaks confirmed by a repeat-run leak detector (EXEC-01, EXEC-06).
2. A per-pass deadline that expires mid-execution produces a distinct typed timeout failure, not a generic error, and the output distinguishes timeout from cancellation and from budget-exceeded (EXEC-02).
3. An output-size budget that is exceeded before the pass completes produces a distinct budget-exceeded failure, and the partial output is NOT published as a successful result (EXEC-03).
4. Progress events during a multi-stage render pass carry the pass ID, stage name, and percent (0–100 float) — verified by capturing progress callbacks in a test (EXEC-04, D-11).
5. A processor that does not support checkpointing returns a clear "checkpoint not supported" response when the checkpoint callback is queried, rather than silently ignoring it (EXEC-05).
6. All existing MNN inference processors and the v1.0 `RenderProcessor` pass their existing test suites through the new execution-context adapter with zero behavior changes (EXEC-07).

**Plans**: 4 plans in 3 waves

**Plans:**

- [x] 07-01-PLAN.md — ExecutionContext type system + teardown stack + schema budgets + registry checkpointing flag
- [x] 07-02-PLAN.md — ProcessingManager integration: try/catch, ExecutionContext lifecycle, deadline timer, adapter removal
- [x] 07-03-PLAN.md — All 15 processors: cancel checks, progress events, MNN teardown stack adoption
- [x] 07-04-PLAN.md — Integration tests: cancel, timeout, budget, progress, leak detection, migration adapter

| Plan | Wave | Requirements | Autonomous |
|------|------|-------------|------------|
| 07-01 | 1 (Types) | EXEC-01, EXEC-02, EXEC-03, EXEC-04, EXEC-05 | yes |
| 07-02 | 2 (Integration) | EXEC-06, EXEC-07 | yes |
| 07-03 | 2 (Processors) | EXEC-01, EXEC-02, EXEC-03, EXEC-04 | yes |
| 07-04 | 3 (Tests) | EXEC-01, EXEC-02, EXEC-03, EXEC-04, EXEC-05, EXEC-06, EXEC-07 | no (checkpoint:human-verify) |

### Phase 08: Structured Artifacts & Execution Manifests

**Goal**: Output artifacts are typed records with resource identity, format, dimensions, hashes, and producing-pass provenance — not loose byte buffers and newline-delimited strings. The execution manifest captures everything needed for deterministic hashing, signing, caching, and verification. Existing callers have a migration adapter.

**Depends on**: Phase 07 (EXEC — artifacts need execution context for manifest fields like timings, terminal state, executor identity)

**Requirements**: ARTF-01, ARTF-02, ARTF-03, ARTF-04, ARTF-05, ARTF-06

**Success Criteria** (what must be TRUE):

1. A multi-output render job returns independently typed artifact records, each with its own resource name, artifact ID, producing pass, output binding, format, dimensions, byte size, and media type — no newline parsing required to discover individual outputs (ARTF-01, ARTF-02).
2. Each artifact carries a content hash and chunk hashes; modifying one byte of the output changes the content hash while leaving chunk hashes of unmodified chunks intact (ARTF-03).
3. The execution manifest includes: all IDs (execution/attempt/task/subtask/pass), executor identity, model/shader/quantization identities when used, input and output artifact hashes, start/end times, terminal state, error details, and resource-use summary — and serializes to byte-identical output across two runs with identical inputs (ARTF-04, ARTF-05).
4. Existing callers consuming the old `ProcessingResult` shape (hash + output names + byte buffers + output-location string) continue to work through the migration adapter with zero changes to their code (ARTF-06).

**Plans**: 3 plans in 3 waves

**Plans:**

- [ ] 08-01-PLAN.md — Artifact & Manifest type system + SHA-256 content hashing (TerminalState, Artifact, ExecutionManifest structs)
- [ ] 08-02-PLAN.md — Deterministic binary serialization (fixed-field LE layout) + unit tests
- [ ] 08-03-PLAN.md — ProcessingManager integration + ProcessOutput + migration adapter + SuperGenius caller update

| Plan | Wave | Requirements | Autonomous |
|------|------|-------------|------------|
| 08-01 | 1 (Types) | ARTF-01, ARTF-02, ARTF-03, ARTF-04 | yes |
| 08-02 | 2 (Serialization) | ARTF-05 | yes |
| 08-03 | 3 (Integration) | ARTF-01, ARTF-02, ARTF-03, ARTF-06 | no (checkpoint:human-verify) |

### Phase 09: Processor & Pass-Graph Conformance Suites

**Goal**: Every registered executor runs the same core conformance contract via CTest targets. Schema parsing, executor selection, output hashing, cancellation, capability checks, and backward-compat adapters are all tested. Regression tests lock in fixes for the four known bugs from v1.0.

**Depends on**: Phase 06, Phase 07, Phase 08 (TEST tests everything those phases build)

**Requirements**: TEST-01, TEST-02, TEST-03, TEST-04, TEST-05, TEST-06, TEST-07, TEST-08, TEST-09, TEST-10

**Success Criteria** (what must be TRUE):

1. `ctest` runs from the standalone `SGProcessingManager` build and passes; the same tests run and pass when `SGProcessingManager` is consumed as a submodule by `SuperGenius/develop` (TEST-01).
2. Every registered executor type (MNN inference, Vulkan compute, Vulkan render) runs the same core conformance contract — schema parsing, executor selection, basic execution, output validation — with no backend-specific test divergence (TEST-02, TEST-03, TEST-04).
3. Native Vulkan and MoltenVK paths run equivalent render fixtures where CI hardware permits; CI environments without GPU support skip those tests with an explicit "SKIPPED: no Vulkan device" reason rather than silently passing or hanging (TEST-05).
4. A dedicated cancellation test starts a job, cancels it mid-execution, and asserts: no successful result published, progress events show the cancellation stage, resources cleaned up — for at least one MNN and one Vulkan processor (TEST-07).
5. Capability rejection tests cover: unsupported Vulkan feature, unsupported model format, unsupported pass type, missing executor — each produces a distinct, human-readable rejection reason (TEST-08).
6. The four regression tests pass: (a) index mismatch produces correct error, (b) model-only pass no longer crashes in `ParseBlockSize()`, (c) output-buffer-zero produces correct result, (d) unsupported pass type produces error instead of silent fallthrough (TEST-10).

**Plans**: 15/15 plans complete

Plans:
**Wave 1**

- [x] 09-01-PLAN.md — Shared infrastructure: ProcessorConformanceFixture, Python MNN model scripts, SPIR-V fixtures
- [x] 09-08-PLAN.md — Gap closure: fix JSON fixture/inline-literal field-name mismatches (Gap 1)
- [x] 09-09-PLAN.md — Gap closure: granular error propagation, model-format, pass-type validation (Gaps 2/4/5)
- [x] 09-11-PLAN.md — Gap closure round 2: wire capability_conformance_test to real CanExecute(), RenderConformanceTest to real Vulkan pipeline, output_hashing_test's missing artifact/manifest cases
- [x] 09-12-PLAN.md — Gap closure round 2: ExecutionContext-accepting Process() overload + real cancellation/budget/progress conformance tests (MNN + Vulkan)
- [x] 09-13-PLAN.md — Gap closure round 2: fix MNN string processor reshape/resize bug (StringInputProcessingTest + StringConformanceProcessingTest)
- [x] 09-14-PLAN.md — Gap closure round 3 (UAT): capability_validator_test PassType rejection message name (Gap 1, standalone build only)
- [x] 09-15-PLAN.md — Gap closure round 3 (UAT): processing_dispatch_test ctest working-directory fix + happy-path render fixture combinedHash (Gaps 2/3)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 09-02-PLAN.md — Extend processing_datatypes_test for 5 remaining MNN types (audio, image, ml, string, volume)
- [x] 09-03-PLAN.md — Schema validation + executor selection test executables
- [x] 09-04-PLAN.md — Output hashing + migration adapter test executables
- [x] 09-05-PLAN.md — Cancellation + capability conformance test executables
- [x] 09-06-PLAN.md — Regression tests + RenderProcessor GPU conformance
- [x] 09-10-PLAN.md — Gap closure: deterministic ProcessOutput.combinedHash + full regression sweep (Gap 3)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 09-07-PLAN.md — CMake integration: add_subdirectory entries + CTest verification

| Plan | Wave | Requirements | Autonomous |
|------|------|-------------|------------|
| 09-01 | 1 (Infra) | TEST-04, TEST-05 | yes |
| 09-02 | 2 (Tests) | TEST-04 | yes |
| 09-03 | 2 (Tests) | TEST-02, TEST-03 | yes |
| 09-04 | 2 (Tests) | TEST-06, TEST-09 | yes |
| 09-05 | 2 (Tests) | TEST-07, TEST-08 | yes |
| 09-06 | 2 (Tests) | TEST-10, TEST-04, TEST-05 | yes |
| 09-07 | 3 (Integration) | TEST-01 | yes |
| 09-11 | 1 (Gap closure R2) | TEST-08, TEST-05, TEST-06 | yes |
| 09-12 | 1 (Gap closure R2) | TEST-07 | yes |
| 09-13 | 1 (Gap closure R2) | TEST-04 | yes |
| 09-14 | 1 (Gap closure R3) | TEST-01 | yes |
| 09-15 | 1 (Gap closure R3) | TEST-01 | yes |

## Progress

**Execution Order:**
Phases execute in numeric order: 06 → 07 → 08 → 09. Phase 06's CAP and VVAL sub-streams are independently developable and may be planned as separate waves within the phase.

| Phase | Plans Complete | Status | Completed |
|-------|-----------------|--------|-----------|
| 06. Capability & Validation Foundation | 4/4 | Executed | 2026-08-05 |
| 07. Cancellable Execution Context | 5/5 | Executed | 2026-08-05 |
| 08. Structured Artifacts & Manifests | 3/3 | Executed | 2026-08-05 |
| 09. Conformance Test Suites | 15/15 | Complete    | 2026-08-07 |

## Requirement Coverage

| REQ-ID | Phase | Category |
|--------|-------|----------|
| CAP-01 | 06 | Capability — executability gate |
| CAP-02 | 06 | Capability — Vulkan feature reasons |
| CAP-03 | 06 | Capability — model format reasons |
| CAP-04 | 06 | Capability — pass type reasons |
| CAP-05 | 06 | Capability — resource validation |
| CAP-06 | 06 | Capability — executor identity |
| VVAL-01 | 06 | Vulkan layers — vendoring |
| VVAL-02 | 06 | Vulkan layers — CMake wiring |
| VVAL-03 | 06 | Vulkan layers — runtime toggle |
| VVAL-04 | 06 | Vulkan layers — documented decision |
| EXEC-01 | 07 | Execution — cancellation token |
| EXEC-02 | 07 | Execution — deadline failures |
| EXEC-03 | 07 | Execution — resource budgets |
| EXEC-04 | 07 | Execution — progress events |
| EXEC-05 | 07 | Execution — checkpoint support |
| EXEC-06 | 07 | Execution — safe cleanup |
| EXEC-07 | 07 | Execution — migration adapter |
| ARTF-01 | 08 | Artifacts — typed records |
| ARTF-02 | 08 | Artifacts — format metadata |
| ARTF-03 | 08 | Artifacts — content hashes |
| ARTF-04 | 08 | Artifacts — execution manifest |
| ARTF-05 | 08 | Artifacts — deterministic serialization |
| ARTF-06 | 08 | Artifacts — migration adapter |
| TEST-01 | 09 | Tests — CTest targets |
| TEST-02 | 09 | Tests — schema parsing |
| TEST-03 | 09 | Tests — executor selection |
| TEST-04 | 09 | Tests — MNN conformance |
| TEST-05 | 09 | Tests — Vulkan/MoltenVK |
| TEST-06 | 09 | Tests — hashing/serialization |
| TEST-07 | 09 | Tests — cancellation/budgets |
| TEST-08 | 09 | Tests — capability cases |
| TEST-09 | 09 | Tests — backward compat |
| TEST-10 | 09 | Tests — regression bugs |

**Coverage:** 29/29 requirements mapped ✓

---
*Roadmap created: 2026-08-03 — v2.0 Execution Contracts & Quality Gates*
