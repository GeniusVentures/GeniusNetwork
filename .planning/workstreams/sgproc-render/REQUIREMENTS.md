# Requirements: sgproc-render

**Defined:** 2026-08-07
**Core Value:** Elevate SGProcessingManager from a "parse-and-hope" pipeline to a contract-driven execution engine — jobs are validated before work starts, execution is cancellable and budget-aware, results are typed artifacts with provenance, and every processor is covered by a common test suite.

## v2.1 Requirements — Cross-Hardware Hash Tolerance

Requirements for milestone v2.1. Each maps to roadmap phases.

### Capture Harness

- [x] **CAPT-01**: Capture harness runs Phase 09's existing render + MNN fixtures and records, per run: raw per-element output values, per-chunk hashes, and the combined hash, tagged with the executing machine's identity
- [x] **CAPT-02**: Capture harness reads the literal bytes passed into each existing hash call site (not a downstream copy), so captured data provably matches what production hashing actually saw
- [x] **CAPT-03**: Capture harness confirms same-node hash stability (N≥2 repeat runs) on each machine before that machine's capture is used for cross-machine comparison

### Diff Tool

- [x] **DIFF-01**: Diff tool reports, per output element, absolute delta, relative delta, and ULP distance between two or more capture files
- [x] **DIFF-02**: Diff tool reports whole-buffer summary stats: max absolute delta, max relative delta, max ULP distance, and percentage of elements exceeding a threshold
- [x] **DIFF-03**: Diff tool reports whether the combined hash and each chunk hash match across compared captures

### Quantization / Normalization

- [ ] **QUANT-01**: Render (uint8 RGBA8/RGB8) and MNN (float32 tensor) output are each normalized to a fixed precision before hashing, using whichever technique (rounding, fixed-point conversion, bit-masking, or another canonicalization approach) is determined during design to best balance cross-hardware tolerance against result integrity
- [ ] **QUANT-02**: The chosen normalization is applied identically before both the per-chunk hash and the combined hash, on both the render and MNN paths
- [ ] **QUANT-03**: IEEE-754 special values (NaN, +Inf, -Inf, denormals, signed zero) are canonicalized to one fixed representative bit pattern before normalization
- [ ] **QUANT-04**: Normalization parameters are fixed constants derived from CAPT/DIFF's empirical ≥3-machine data — not guessed a priori, not schema-configurable this milestone

### Security Validation

- [ ] **SECV-01**: A deliberately wrong/corrupted result still produces a post-normalization hash that differs from the correct result's hash — proving the chosen tolerance isn't loose enough to also accept wrong results

### Empirical Validation

- [ ] **VALD-01**: The same render fixture and the same MNN fixture, run on ≥3 different machines (including the user's Mac and PC), produce matching post-normalization combined hashes

## v2 Requirements

Deferred to future milestones. Tracked but not in current roadmap.

### Verification & Backend (carried forward from v2.0)

- **XNODE-01b**: `ProcessingValidationCore::ValidateResults`'s concatenation bug — it never actually diffs two subtasks' hashes for the same chunk, so a genuine cross-node mismatch would silently pass today. This milestone makes the hash itself tolerant but does not fix the comparison mechanism around it.
- **XNODE-01c**: Actual cross-node consensus/redundant-execution comparison plumbing — this milestone only proves the hash *can* be tolerant, not that production consensus uses that tolerance correctly.
- **QUANT-CFG-01**: Schema-configurable per-data-type normalization precision (per-job tuning exposed to job authors) — fixed constants only this milestone.

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Schema-configurable normalization precision | Deferred — see QUANT-CFG-01; fixed constants only this milestone |
| Fixing `ProcessingValidationCore::ValidateResults`'s concatenation bug | Separate, already-tracked gap in the production comparison path — this milestone's scope is the hash itself, not the comparison mechanism around it |
| Actual cross-node consensus/redundant-execution plumbing | This milestone proves the hash *can* be cross-hardware tolerant; wiring that into production multi-node job validation is future work |
| Per-channel/per-region diff breakdown for structured render output | Nice-to-have debuggability, not needed to hit the ≥3-machine success bar |
| Live/streaming telemetry capture pipeline | This milestone's workflow is offline capture files manually shared between the user's own machines, not production telemetry infrastructure |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CAPT-01 | Phase 10 | Complete |
| CAPT-02 | Phase 10 | Complete |
| CAPT-03 | Phase 10 | Complete |
| DIFF-01 | Phase 10 | Complete |
| DIFF-02 | Phase 10 | Complete |
| DIFF-03 | Phase 10 | Complete |
| QUANT-01 | Phase 12 | Pending |
| QUANT-02 | Phase 12 | Pending |
| QUANT-03 | Phase 12 | Pending |
| QUANT-04 | Phase 12 | Pending |
| SECV-01 | Phase 12 | Pending |
| VALD-01 | Phase 13 | Pending |

**Coverage:**

- v2.1 requirements: 12 total
- Mapped to phases: 12
- Unmapped: 0 ✓

**Note:** Phase 11 (Empirical Cross-Machine Capture Run) covers no requirement directly — it is a hands-on data-gathering checkpoint (run Phase 10's tooling on ≥3 real machines) that produces the empirical input Phase 12's QUANT-04 depends on. See ROADMAP.md Phase 11 for detail.

---
*Requirements defined: 2026-08-07*
*Last updated: 2026-08-07 — v2.1 roadmap created: 4 phases (10-13), 12/12 requirements mapped*
