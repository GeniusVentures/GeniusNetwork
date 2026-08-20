# Requirements: sgproc-render v2.3 — Deferred Gap Closure

**Defined:** 2026-08-17
**Core Value:** Elevate SGProcessingManager from a "parse-and-hope" pipeline to a contract-driven execution engine — jobs are validated before work starts, execution is cancellable and budget-aware, results are typed artifacts with provenance, and every processor is covered by a common test suite.

**Previously shipped:** v1.0 (Phases 01-05), v2.0 Execution Contracts & Quality Gates (Phases 06-09, closed with known gaps), v2.1 Cross-Hardware Hash Tolerance (Phases 10-13, closed with an accepted VALD-01 override), v2.2 Cross-Hardware Validation Tolerance (Phases 14-15, shipped clean). Full archives: `.planning/milestones/sgproc-render-v2.0-*.md` through `sgproc-render-v2.2-*.md`.

## v2.3 Requirements — Deferred Gap Closure

This milestone is not new feature work — it closes four real, previously-surfaced gaps that no prior milestone picked up: Phase 08's deferred manifest-evolution scope (2026-08-05), an untested cross-hardware risk on the render path flagged in v2.2's STATE.md, a pre-existing build-stability bug (2026-08-10), and an unverified assumption about whether v2.2's Phase 15 fix actually closes v2.1's VALD-01 finding.

### Manifest Evolution (Phase 08 deferred scope)

- [x] **ARTF-07**: Chunk integrity is verifiable via a Merkle tree over chunk hashes, not just the existing flat content hash — **Won't implement, not applicable** (16-CONTEXT.md D-01..D-04: Artifact::chunkHashes already gives full per-chunk localization; graphsync/protobuf already deliver the complete chunk-hash list to every real verifier, so a root-only Merkle proof serves no scenario this system's actual verification flow has)
- [x] **ARTF-08**: Chunking uses content-defined boundaries instead of fixed-size, so a small edit doesn't invalidate every downstream chunk hash — **Won't implement, not applicable** (16-CONTEXT.md D-05..D-08: block_len is a job-poster-owned schema parameter (Dimensions.hpp); a source-data/block_len mismatch is a bad-job failure to surface, not a chunking gap for SGProcessingManager to reconcile)
- [x] **ARTF-09**: The execution manifest's error details carry a human-readable message string alongside the existing structured error code
- [x] **ARTF-10**: The manifest's binary format supports schema evolution (new optional fields) without breaking older readers

### Render-Path Cross-Hardware Tolerance

- [x] **RENDTOL-01**: Three non-trivial render fixtures exist (texturing, blending, and lighting — MSAA excluded per D-03's architectural hard-block), each exercising real floating-point-heavy render computation — not just the existing trivial 8x8 solid-color fixture (`render-pass-happy-path-definition.json`) — **complete: all 3 fixtures built, and Round 2 (17-08) proved via real two-machine capture that each exercises genuine non-trivial computation**
- [ ] **RENDTOL-02**: The render output path has a real schema-configurable tolerance mechanism (mirroring Phase 14's `ResolveQuantScale`/`ResolveByteQuantMode` pattern for MNN), replacing `QuantizeByteBuffer`'s current byte-identity no-op — proven independently against real cross-hardware capture data from each of RENDTOL-01's three fixtures — **partially satisfied (17-VERIFICATION.md gap #1): mechanism exists and byteQuantMode values (lighting=5, blending=6, texturing=7) are derived and counter-test-proven not-too-loose, and Round 2 hash-matched for lighting+texturing — but blending's Round 2 capture shows the quantization made cross-hardware divergence WORSE (raw maxAbsDelta=1.0 → quantized 64.0), a real architectural gap in `QuantizeByteBuffer`'s bit-masking (no rounding tie-break), not yet resolved. Requires a human decision: redesign the quantization, fall back to numeric-tolerance comparison for blending, or accept as a documented override (VALD-01 precedent).**

### Build Stability

- [ ] **BUILD-01**: `ProcessingManager::Create()`'s Vulkan capability-probe no longer deadlocks `ProcessingDatatypesTest`/`ProcessingDispatchTest`/`vulkan_init_concurrency_test` when a real Vulkan device is present (fix the `VulkanInitMutex` re-entrancy bug tracked in `.planning/todos/pending/2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md`)

### Validation Re-Verification

- [ ] **VALD-02**: The original VALD-01 MNN float32 fixture (Phase 13's 12/15 chunk-hash mismatch finding) is re-run through Phase 15's `ValidateResults` tolerance-fallback mechanism, with the outcome (closed vs. still-open) documented with evidence — not assumed

## v2 Requirements

Deferred to future milestones. Not addressed this milestone.

### Cross-Node Orchestration

- **XNODE-01c**: Actual cross-node consensus/redundant-execution comparison plumbing — the comparison mechanism itself (XNODE-01b/XNODE-02) is correct and tolerant as of v2.2; wiring it into real multi-node job orchestration remains future work. User considers this CI-verification scope, not application-level work for this workstream.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Phase 04 (v1.0) pending UAT scenario + `human_needed` verification | Pre-existing carryover, re-acknowledged unchanged at both v2.0 and v2.2 close; unrelated to this milestone's gap set |
| Semantic/output-level comparison (e.g. Dice/overlap score) for segmentation-style workloads | Raised as a design note in v2.2's STATE.md (bit-exact hash may be the wrong correctness bar for `spleen_ct_seg`-style outputs) but is a larger architectural question than a single-milestone fix |
| STATE.md/REQUIREMENTS.md stale-bookkeeping cleanup (QUANT-CFG-01/XNODE-01b rows, traceability table wording) | Corrected directly as part of this milestone's kickoff, not tracked as a requirement |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| ARTF-07 | Phase 16 | Won't implement — not applicable (D-01..D-04) |
| ARTF-08 | Phase 16 | Won't implement — not applicable (D-05..D-08) |
| ARTF-09 | Phase 16 | Complete |
| ARTF-10 | Phase 16 | Complete |
| RENDTOL-01 | Phase 17 | Complete |
| RENDTOL-02 | Phase 17 | Partial — blending residual gap open (17-VERIFICATION.md gap #1), human decision needed |
| BUILD-01 | Phase 18 | Pending |
| VALD-02 | Phase 19 | Pending |

**Coverage:**

- v2.3 requirements: 8 total
- Mapped to phases: 8 ✓
- Unmapped: 0

---
*Requirements defined: 2026-08-17*
*Last updated: 2026-08-17 — roadmap created (Phases 16-19), all 8 requirements mapped*
