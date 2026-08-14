# Requirements: sgproc-render

**Defined:** 2026-08-13
**Core Value:** Elevate SGProcessingManager from a "parse-and-hope" pipeline to a contract-driven execution engine — jobs are validated before work starts, execution is cancellable and budget-aware, results are typed artifacts with provenance, and every processor is covered by a common test suite.

**Previously shipped:** v1.0 (Phases 01-05), v2.0 Execution Contracts & Quality Gates (Phases 06-09, closed with known gaps), v2.1 Cross-Hardware Hash Tolerance (Phases 10-13, closed with an accepted VALD-01 override). Full archives: `.planning/milestones/sgproc-render-v2.0-*.md`, `.planning/milestones/sgproc-render-v2.1-*.md`. See `.planning/MILESTONES.md` for shipped summaries.

## v2.2 Requirements — Cross-Hardware Validation Tolerance

Requirements for milestone v2.2. Each maps to roadmap phases. Directly motivated by v2.1's closing findings: (1) the `tex3d`/`spleen_ct_seg` real workload proved a single global quantization scale cannot serve models with materially different cross-hardware divergence magnitudes, and (2) v2.1's chunk-10 finding proved that even a well-tuned scale can produce a *false* hash mismatch on a genuinely correct result (a boundary tie-break) — so a real validation mechanism needs tolerance, not just a better constant.

### Configurable Normalization Precision

- [x] **QUANT-CFG-01**: A processing job's schema can declare a per-data-type normalization precision parameter (e.g. a quantization scale for float32 outputs), read by `QuantizeFloatBuffer`/`QuantizeByteBuffer` instead of the single hardcoded `kScale` constant from v2.1
- [x] **QUANT-CFG-02**: When no precision is schema-declared, normalization falls back to v2.1's existing fixed constants (S=2^15 for float32, byte-identity for uint8) — additive, not a breaking change to existing jobs
- [x] **QUANT-CFG-03**: A workload with materially different divergence characteristics from v2.1's float fixture (e.g. `tex3d`/`spleen_ct_seg`) can be configured with its own empirically-derived precision, citing real captured cross-machine divergence data for that specific workload — not guessed a priori (mirrors QUANT-04's discipline)

### Validation Comparison Mechanism

- [ ] **XNODE-01b**: `ProcessingValidationCore::ValidateResults` actually diffs two subtasks' per-chunk hashes for the same chunk (fixing the concatenation bug where a genuine mismatch silently passes today)
- [x] **XNODE-02**: On a chunk-hash mismatch, `ValidateResults` falls back to a bounded numeric comparison of the underlying chunk data (reusing `capture_diff`'s per-chunk diff logic from v2.1 Phase 13) before declaring a genuine divergence — a chunk within configured tolerance is not treated as a mismatch
- [ ] **SECV-02**: A deliberately wrong/corrupted subtask result is still caught by `ValidateResults` post-fix — proving XNODE-01b/XNODE-02 together aren't loose enough to also mask a genuine defect (counter-test, mirrors v2.1's SECV-01 discipline for this new mechanism)

## v2 Requirements

Deferred to future milestones. Tracked but not in current roadmap.

### Verification & Backend

- **XNODE-01c**: Actual cross-node consensus/redundant-execution comparison plumbing — v2.2 makes the comparison mechanism itself correct and tolerant; wiring it into real multi-node job orchestration is future work.

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Actual cross-node consensus/redundant-execution plumbing | Deferred — see XNODE-01c; v2.2's scope is the comparison mechanism itself, not multi-node orchestration |
| Fixing every MNN processor's quantization precision individually (e.g. hand-tuning all 13 processor types) | QUANT-CFG-01 makes precision configurable; per-workload tuning happens as each workload is onboarded, not as a one-time bulk exercise this milestone |
| Re-litigating v2.1's chunk-10 acceptance | That gap was formally accepted via override in `13-VERIFICATION.md`; v2.2 builds the tolerance mechanism that would have absorbed it, not a re-investigation of the same fixture |

## Traceability

Which phases cover which requirements. Filled during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| QUANT-CFG-01 | Phase 14 | Not started |
| QUANT-CFG-02 | Phase 14 | Not started |
| QUANT-CFG-03 | Phase 14 | Not started |
| XNODE-01b | Phase 15 | Not started |
| XNODE-02 | Phase 15 | Not started |
| SECV-02 | Phase 15 | Not started |

**Coverage:**

- v2.2 requirements: 6 total
- Mapped to phases: 6 (Phase 14: QUANT-CFG-01/02/03; Phase 15: XNODE-01b, XNODE-02, SECV-02)
- Unmapped: 0

---
*Requirements defined: 2026-08-13*
