# Requirements Archive: sgproc-render v2.2 — Cross-Hardware Validation Tolerance

**Status:** ✅ SHIPPED 2026-08-14
**Archived from:** `.planning/workstreams/sgproc-render/REQUIREMENTS.md`

**Core Value:** Elevate SGProcessingManager from a "parse-and-hope" pipeline to a contract-driven execution engine — jobs are validated before work starts, execution is cancellable and budget-aware, results are typed artifacts with provenance, and every processor is covered by a common test suite.

**Previously shipped:** v1.0 (Phases 01-05), v2.0 Execution Contracts & Quality Gates (Phases 06-09, closed with known gaps), v2.1 Cross-Hardware Hash Tolerance (Phases 10-13, closed with an accepted VALD-01 override). Full archives: `.planning/milestones/sgproc-render-v2.0-*.md`, `.planning/milestones/sgproc-render-v2.1-*.md`.

## v2.2 Requirements — Cross-Hardware Validation Tolerance

Directly motivated by v2.1's closing findings: (1) the `tex3d`/`spleen_ct_seg` real workload proved a single global quantization scale cannot serve models with materially different cross-hardware divergence magnitudes, and (2) v2.1's chunk-10 finding proved that even a well-tuned scale can produce a *false* hash mismatch on a genuinely correct result (a boundary tie-break) — so a real validation mechanism needed tolerance, not just a better constant.

### Configurable Normalization Precision

- [x] **QUANT-CFG-01**: A processing job's schema can declare a per-data-type normalization precision parameter (e.g. a quantization scale for float32 outputs), read by `QuantizeFloatBuffer`/`QuantizeByteBuffer` instead of the single hardcoded `kScale` constant from v2.1 — **Outcome: validated.** `ResolveQuantScale`/`ResolveByteQuantMode` resolve a schema-declared value at all 21 existing call sites across 14 processor files (Phase 14).
- [x] **QUANT-CFG-02**: When no precision is schema-declared, normalization falls back to v2.1's existing fixed constants (S=2^15 for float32, byte-identity for uint8) — additive, not a breaking change to existing jobs — **Outcome: validated.** Silent exact-fallback contract confirmed via 11 new unit test cases.
- [x] **QUANT-CFG-03**: A workload with materially different divergence characteristics from v2.1's float fixture (e.g. `tex3d`/`spleen_ct_seg`) can be configured with its own empirically-derived precision, citing real captured cross-machine divergence data for that specific workload — **Outcome: validated.** `quantScale=128.0` (2^7) chosen via the divergence-absorption constraint after a binary search found no SECV-01 failure boundary in the valid domain (a notable deviation from Phase 13's small-model search, which did find a boundary).

### Validation Comparison Mechanism

- [x] **XNODE-01b**: `ProcessingValidationCore::ValidateResults` actually diffs two subtasks' per-chunk hashes for the same chunk (fixing the concatenation bug where a genuine mismatch silently passes today) — **Outcome: validated.** `chunks` map restructured to `chunkKey -> {subtaskId -> hashBytes}` (Phase 15 Plan 2).
- [x] **XNODE-02**: On a chunk-hash mismatch, `ValidateResults` falls back to a bounded numeric comparison of the underlying chunk data before declaring a genuine divergence — **Outcome: validated.** New shared `sgprocmanagerdiff` library extracted from `capture_diff`'s per-chunk diff logic, quantScale-derived threshold when configured, fixed-constant fallback otherwise.
- [x] **SECV-02**: A deliberately wrong/corrupted subtask result is still caught by `ValidateResults` post-fix — proving XNODE-01b/XNODE-02 together aren't loose enough to also mask a genuine defect — **Outcome: validated.** Full-pipeline counter-test via `SubTaskQueueAccessorImpl`'s real public API, required a new dedicated corrupted-model fixture at single-window granularity.

## v2 Requirements

Deferred to future milestones. Not addressed this milestone.

### Verification & Backend

- **XNODE-01c**: Actual cross-node consensus/redundant-execution comparison plumbing — v2.2 made the comparison mechanism itself correct and tolerant; wiring it into real multi-node job orchestration remains future work.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Actual cross-node consensus/redundant-execution plumbing | Deferred — see XNODE-01c; v2.2's scope was the comparison mechanism itself, not multi-node orchestration |
| Fixing every MNN processor's quantization precision individually (hand-tuning all 13 processor types) | QUANT-CFG-01 made precision configurable; per-workload tuning happens as each workload is onboarded |
| Re-litigating v2.1's chunk-10 acceptance | That gap was formally accepted via override in `13-VERIFICATION.md`; v2.2 built the tolerance mechanism that would have absorbed it |

## Traceability (Final)

| Requirement | Phase | Status |
|-------------|-------|--------|
| QUANT-CFG-01 | Phase 14 | ✓ Complete |
| QUANT-CFG-02 | Phase 14 | ✓ Complete |
| QUANT-CFG-03 | Phase 14 | ✓ Complete |
| XNODE-01b | Phase 15 | ✓ Complete |
| XNODE-02 | Phase 15 | ✓ Complete |
| SECV-02 | Phase 15 | ✓ Complete |

**Coverage:**

- v2.2 requirements: 6 total, 6 shipped, 0 dropped, 0 adjusted
- All requirements mapped and delivered exactly as scoped — no requirement was invalidated or rescoped during execution

---
*Archived: 2026-08-14 at v2.2 milestone close*
