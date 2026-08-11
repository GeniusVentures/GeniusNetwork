# Roadmap: sgproc-render

## Milestones

- ✅ **v1.0** — Phases 01-05 (shipped 2026-07-31)
- ✅ **v2.0 Execution Contracts & Quality Gates** — Phases 06-09 (shipped 2026-08-07, closed with known gaps — see MILESTONES.md)
- 🚧 **v2.1 Cross-Hardware Hash Tolerance** — Phases 10-13 (planning complete, execution not started)

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

### 🚧 v2.1 Cross-Hardware Hash Tolerance (Phases 10-13)

**Phase Numbering:** Continues sequentially from v2.0's Phase 09 — this milestone starts at Phase 10.

**Dependency order note:** These four phases have a hard, research-confirmed dependency chain and must execute in numeric order without flattening or reordering: the quantization precision literally cannot be chosen (Phase 12) before real cross-machine divergence data exists (Phase 11), which in turn needs the capture/diff tooling built first (Phase 10). Phase 13's re-validation is meaningless before Phase 12's real quantization logic lands.

- [x] **Phase 10: Capture Harness & Diff Tool (Quantization Stub)** - Build and validate the capture harness + diff tool plumbing (14 processor files + `ExecutionContext` capture field) against Phase 09's existing fixtures, with quantization wired in as a no-op/identity stub (completed 2026-08-10)
- [ ] **Phase 11: Empirical Cross-Machine Capture Run** - Hands-on data-gathering checkpoint: run Phase 10's tooling on the user's Mac + PC + a third machine to produce real cross-hardware divergence statistics
- [ ] **Phase 12: Quantization / Normalization Implementation** - Implement the real normalization logic (technique chosen from Phase 11's data, not fixed in advance) on both render and MNN paths, plus the SECV-01 wrong-result-still-diverges counter-test
- [ ] **Phase 13: Re-Validation & Scope Boundary Documentation** - Re-run the ≥3-machine capture/diff cycle with real quantization active to confirm VALD-01, re-confirm SECV-01 at the final precision, and document the milestone's scope boundary

## Phase Details

### Phase 10: Capture Harness & Diff Tool (Quantization Stub)

**Goal**: Developer tooling exists to capture, on any single machine, per-run raw output values, per-chunk hashes, and the combined hash from Phase 09's existing render + MNN fixtures, and to diff two or more such capture files with quantitative divergence stats — with quantization wired in as a no-op/identity stub so the full invasive plumbing (14 processor files + one new `ExecutionContext` field) is exercised and proven end-to-end once, without yet claiming a real cross-hardware precision.
**Depends on**: Nothing (continues from v2.0 Phase 09; first phase of v2.1)
**Requirements**: CAPT-01, CAPT-02, CAPT-03, DIFF-01, DIFF-02, DIFF-03
**Success Criteria** (what must be TRUE):

  1. Running `capture_harness` against Phase 09's existing render fixture and against its MNN fixture on one machine produces a capture file containing per-element raw output values, per-chunk hashes, the combined hash, and a machine-identity tag.
  2. The bytes a capture file records are provably the literal bytes passed into each existing `sha256()` call site (not a downstream copy of `output_buffers`/`Artifact` fields) — verified by a self-check that the captured buffer's independently computed hash equals the paired chunk/combined hash from the same run.
  3. Running `capture_harness` twice in a row on the same machine against the same fixture and diffing the two capture files with `capture_diff` reports 0 divergence across every output element, every chunk hash, and the combined hash.
  4. `capture_diff` run on two capture files reports, per output element, absolute delta, relative delta, and ULP distance, plus whole-buffer summary stats (max absolute delta, max relative delta, max ULP distance, and percentage of elements exceeding a threshold).
  5. `capture_diff` explicitly reports, as a separate boolean-style result, whether the combined hash and each chunk hash match or differ across the two compared captures.

**Plans**: 6/6 plans complete
Plans:
**Wave 1**

- [x] 10-01-PLAN.md — sgprocmanagerquant identity-stub library + ExecutionContext::rawOutputCapture field

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 10-02-PLAN.md — MNN stitched-family (Float/Int/Mat2/Mat3/Mat4/Tensor) quantize+capture wiring
- [x] 10-03-PLAN.md — MNN chained-family (Bool/Buffer/Image/String/Texture1D/TextureCube/Volume) quantize+capture wiring
- [x] 10-04-PLAN.md — RenderProcessor quantize+capture wiring + capture file binary format

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 10-05-PLAN.md — capture_harness + capture_diff standalone CLI tools

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 10-06-PLAN.md — test/capture CTest smoke test + SGProcessingManager/test build wiring fix

### Phase 11: Empirical Cross-Machine Capture Run

**Goal**: Real cross-hardware divergence statistics exist across the user's own machines (Mac + PC + a third), gathered using Phase 10's tooling with quantization still a no-op — this is a hands-on data-gathering step the whole milestone's precision decision depends on, not a coding or research activity, and it is deliberately kept as its own phase rather than folded into Phase 10 or Phase 12 per the milestone's confirmed hard dependency order.
**Depends on**: Phase 10
**Requirements**: None of the 12 v2.1 requirements map directly to this phase — it is a data-gathering checkpoint that exercises Phase 10's CAPT/DIFF tooling and produces the empirical input Phase 12's QUANT-04 requirement depends on. No code is written in this phase.
**Success Criteria** (what must be TRUE):

  1. `capture_harness` has been run against Phase 09's render fixture and its MNN fixture on at least 3 distinct physical machines, including the user's Mac and PC, producing one capture file per machine per fixture.
  2. Each machine's own same-node repeat-run stability has been confirmed (via Phase 10's N≥2 same-node check) before that machine's capture file is used in any cross-machine diff.
  3. `capture_diff` has been run pairwise across all captured machine combinations for both fixtures, producing real max-absolute-delta / max-relative-delta / max-ULP-distance / mantissa-bit-difference statistics, separately for the render (uint8) and MNN (float32) output types.
  4. The resulting divergence statistics are written down (not just observed ad hoc), so Phase 12's normalization design can cite specific captured numbers as its justification rather than a guessed constant.

**Plans**: TBD

### Phase 12: Quantization / Normalization Implementation

**Goal**: Real normalization logic is implemented for both the render (uint8 RGBA8/RGB8) and MNN (float32) output paths, applied identically before every per-chunk and combined hash call on both paths, with IEEE-754 special values canonicalized first. The exact technique (rounding, fixed-point conversion, bit-masking, or another canonicalization approach) is an open design question resolved during this phase's planning from Phase 11's empirical data — it is explicitly not fixed in advance as "rounding" or any other single technique. This phase also builds the SECV-01 wrong-result-still-diverges counter-test, which research flags as the milestone's central, non-optional risk — it must land in this phase alongside the real normalization logic, not be deferred or treated as a stretch goal.
**Depends on**: Phase 11
**Requirements**: QUANT-01, QUANT-02, QUANT-03, QUANT-04, SECV-01
**Success Criteria** (what must be TRUE):

  1. Render (uint8 RGBA8/RGB8) and MNN (float32) output are each normalized to a fixed precision before hashing, using whichever technique was determined during this phase's design work to best balance cross-hardware tolerance against result integrity, justified by Phase 11's captured data.
  2. The chosen normalization is applied identically before both the per-chunk hash and the combined hash, on both the render and MNN paths — verified by confirming a processor's own result hash and `ComputeArtifactIdentity()`'s independent re-hash of the same bytes agree with each other on a single run on a single machine.
  3. Feeding NaN, +Inf, -Inf, a denormal, and both +0.0/-0.0 through the normalization function produces one fixed, canonical output bit pattern for each — verified before any rounding/scaling arithmetic runs, not as an assumed side effect of it.
  4. The normalization's fixed constants are documented with direct reference to Phase 11's captured max-delta/ULP/mantissa-bit-difference statistics — not guessed a priori, not reused from the unrelated pre-existing `ProcessingDatatypesTest` (COV-01) tolerance, and not exposed as a schema-configurable parameter.
  5. A test run using a deliberately wrong/corrupted result (e.g. a corrupted model file, a wrong shader constant, or a truncated/lower-precision inference run) produces a post-normalization hash that differs from the correct run's hash — proving the chosen tolerance is not loose enough to also accept wrong results.

**Plans**: TBD

### Phase 13: Re-Validation & Scope Boundary Documentation

**Goal**: The milestone's literal acceptance criterion is empirically reconfirmed with real quantization active, and the milestone's scope boundary is written down explicitly: this milestone makes hash comparison cross-hardware tolerant, it does not fix `ProcessingValidationCore::ValidateResults`'s concatenation bug and does not build cross-node consensus/redundant-execution plumbing — both stay explicitly out of scope per REQUIREMENTS.md's Out of Scope table.
**Depends on**: Phase 12
**Requirements**: VALD-01
**Success Criteria** (what must be TRUE):

  1. Re-running `capture_harness` + `capture_diff` with real quantization active across ≥3 different machines (including the user's Mac and PC) confirms matching post-normalization combined hashes for both the render fixture and the MNN fixture.
  2. The wrong-result-still-diverges counter-test (SECV-01) is re-run at the final chosen precision and still passes, reported alongside the ≥3-machine match result — not assumed to still hold from Phase 12 alone.
  3. A written document records the milestone's scope boundary in plain terms: hash comparison is now cross-hardware tolerant; `ProcessingValidationCore::ValidateResults`'s comparison-mechanism bug remains unfixed; no cross-node consensus/redundant-execution plumbing was built. No downstream consumer should read this milestone's output as "verification" or "consensus-ready."
  4. The final chosen normalization constants and their empirical derivation (citing Phase 11's captured numbers) are documented alongside the re-validation result, closing the milestone's traceability loop.

**Plans**: TBD

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
| 10. Capture Harness & Diff Tool (Quantization Stub) | v2.1 | 6/6 | Complete    | 2026-08-10 |
| 11. Empirical Cross-Machine Capture Run | v2.1 | 0/TBD | Not started | - |
| 12. Quantization / Normalization Implementation | v2.1 | 0/TBD | Not started | - |
| 13. Re-Validation & Scope Boundary Documentation | v2.1 | 0/TBD | Not started | - |
