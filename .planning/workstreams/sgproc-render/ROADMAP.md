# Roadmap: sgproc-render

## Milestones

- ✅ **v1.0** — Phases 01-05 (shipped 2026-07-31)
- ✅ **v2.0 Execution Contracts & Quality Gates** — Phases 06-09 (shipped 2026-08-07, closed with known gaps — see MILESTONES.md)
- ✅ **v2.1 Cross-Hardware Hash Tolerance** — Phases 10-13 (shipped 2026-08-13, closed with an accepted override — see MILESTONES.md)
- 🚧 **v2.2 Cross-Hardware Validation Tolerance** — Phases 14-15 (in progress, started 2026-08-13)

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

### 🚧 v2.2 Cross-Hardware Validation Tolerance (Phases 14-15) — IN PROGRESS

**Phase Numbering:** Continues sequentially from v2.1's Phase 13 — this milestone starts at Phase 14.

**Framing:** This milestone exists because v2.1 closed with two unresolved findings, not a clean pass: (a) the post-milestone `tex3d`/`spleen_ct_seg` real workload proved a single global quantization scale cannot serve workloads with wildly different cross-hardware divergence magnitudes, and (b) the accepted chunk-10 diagnostic proved a well-tuned scale can still produce a *false* hash mismatch on a genuinely correct result (a rounding-boundary tie-break). The fix isn't a better constant — it's configurable precision (Phase 14) plus a comparison mechanism that tolerates known-bounded numeric divergence instead of requiring bit-exact hash equality (Phase 15).

**Dependency order note:** Phase 15's validation-comparison mechanism (XNODE-01b/XNODE-02) and its SECV-02 counter-test depend on Phase 14's configurable-precision groundwork existing first — the numeric-tolerance fallback needs configured tolerance values to compare against, and SECV-02 needs both the concatenation-bug fix and the tolerance fallback in place before it can meaningfully prove they aren't jointly too loose. Phase 14 completes before Phase 15 begins.

- [ ] **Phase 14: Configurable Normalization Precision** - Job schemas can declare per-data-type precision, replacing v2.1's single hardcoded scale, with backward-compatible fallback and a real empirically-derived precision for the `tex3d`/`spleen_ct_seg` workload
- [ ] **Phase 15: Validation Comparison Mechanism** - `ValidateResults` actually diffs same-chunk hashes across subtasks and falls back to a bounded numeric comparison on mismatch, proven still strict enough by a wrong-result counter-test

## Phase Details

### Phase 14: Configurable Normalization Precision

**Goal**: A processing job's schema can declare its own per-data-type normalization precision instead of being locked to v2.1's single hardcoded `kScale` constant — directly closing the `tex3d`/`spleen_ct_seg` gap, where one global scale could not serve a workload whose real cross-hardware divergence is 2-3 orders of magnitude larger than the tiny float fixture v2.1 tuned against. Existing jobs that declare nothing keep working unchanged.
**Depends on**: Phase 13 (v2.1, shipped) — this is the first phase of v2.2
**Requirements**: QUANT-CFG-01, QUANT-CFG-02, QUANT-CFG-03
**Success Criteria** (what must be TRUE):

  1. A job schema declaring a custom float32 normalization precision (e.g. a quantization scale) produces a `QuantizeFloatBuffer` call that uses the declared value, not the hardcoded S=2^15 constant from v2.1.
  2. A job schema declaring a custom byte/uint8 normalization precision parameter is read by `QuantizeByteBuffer` instead of being silently ignored by the existing no-op byte path.
  3. A job schema that declares no precision parameter at all still normalizes using v2.1's existing fixed constants (S=2^15 for float32, byte-identity for uint8) — proving the schema extension is additive, not a breaking change to any existing job.
  4. The `tex3d`/`spleen_ct_seg` MNN volume workload is configured with its own precision value, and that value is documented with direct citation to real captured cross-machine divergence numbers for that specific workload (not guessed a priori) — mirroring QUANT-04's empirical-derivation discipline from v2.1.

**Plans**: 3 plans

Plans:
**Wave 1**

- [ ] 14-01-PLAN.md — Core resolver infrastructure: `ResolveQuantScale`/`ResolveByteQuantMode` + 3-arg `QuantizeFloatBuffer`/`QuantizeByteBuffer` (Wave 1)

**Wave 2** *(blocked on Wave 1 completion)*

- [ ] 14-02-PLAN.md — Wire all 21 call sites across 14 processor files to the new resolvers (Wave 2, depends on 14-01)

**Wave 3** *(blocked on Wave 2 completion)*

- [ ] 14-03-PLAN.md — tex3d/spleen_ct_seg SECV-01-style counter-test + binary-searched empirical `quantScale` (Wave 3, depends on 14-02)

### Phase 15: Validation Comparison Mechanism

**Goal**: `ProcessingValidationCore::ValidateResults` is fixed to actually compare same-chunk hashes across subtasks (today's concatenation bug silently passes a genuine cross-node mismatch), and extended with a bounded numeric-tolerance fallback so a hash mismatch is not automatically treated as a genuine divergence — directly closing the false-mismatch risk v2.1's chunk-10 diagnostic exposed, where a correct result can still fail bit-exact hash equality on a boundary tie-break. A counter-test proves the combined mechanism still catches genuinely wrong results, not just tolerant ones.
**Depends on**: Phase 14 — the numeric-tolerance fallback compares against configured precision/tolerance values, and SECV-02 needs both the concatenation-bug fix and the tolerance fallback in place to meaningfully prove neither is jointly too loose
**Requirements**: XNODE-01b, XNODE-02, SECV-02
**Success Criteria** (what must be TRUE):

  1. Given two subtasks with genuinely different hashes for the same chunk, `ValidateResults` reports a mismatch — fixing the concatenation bug where the two hashes were concatenated instead of compared, so a real divergence always silently passed.
  2. Given two subtasks with identical hashes for the same chunk, `ValidateResults` still reports a match — confirming the fix doesn't regress the trivial already-working case.
  3. Given two subtasks whose chunk hashes differ but whose underlying chunk data falls within configured tolerance (using `capture_diff`'s per-chunk numeric comparison from v2.1 Phase 13), `ValidateResults` reports a match rather than a mismatch.
  4. Given two subtasks whose chunk hashes differ and whose underlying data exceeds configured tolerance, `ValidateResults` still reports a genuine mismatch — proving the fallback doesn't mask every divergence, only bounded ones.
  5. A deliberately wrong/corrupted subtask result (mirroring v2.1's SECV-01 methodology) is still caught as a mismatch by the fixed `ValidateResults` plus numeric-tolerance fallback acting together — proving XNODE-01b and XNODE-02 aren't jointly loose enough to also mask a genuine defect.

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
| 10. Capture Harness & Diff Tool (Quantization Stub) | v2.1 | 6/6 | Complete | 2026-08-10 |
| 11. Empirical Cross-Machine Capture Run | v2.1 | 1/1 | Complete | 2026-08-12 |
| 12. Quantization / Normalization Implementation | v2.1 | 2/2 | Complete | 2026-08-12 |
| 13. Re-Validation & Scope Boundary Documentation | v2.1 | 6/6 | Complete (override — VALD-01 MNN 1/15-chunk gap accepted, see 13-VERIFICATION.md) | 2026-08-13 |
| 14. Configurable Normalization Precision | v2.2 | 0/TBD | Not started | - |
| 15. Validation Comparison Mechanism | v2.2 | 0/TBD | Not started | - |
