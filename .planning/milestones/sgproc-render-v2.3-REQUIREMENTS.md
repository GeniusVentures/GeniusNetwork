# Requirements Archive: sgproc-render v2.3 — Deferred Gap Closure

**Status:** ✅ SHIPPED 2026-08-21
**Archived from:** `.planning/workstreams/sgproc-render/REQUIREMENTS.md`

**Core Value:** Elevate SGProcessingManager from a "parse-and-hope" pipeline to a contract-driven execution engine — jobs are validated before work starts, execution is cancellable and budget-aware, results are typed artifacts with provenance, and every processor is covered by a common test suite.

**Previously shipped:** v1.0 (Phases 01-05), v2.0 Execution Contracts & Quality Gates (Phases 06-09, closed with known gaps), v2.1 Cross-Hardware Hash Tolerance (Phases 10-13, closed with an accepted VALD-01 override), v2.2 Cross-Hardware Validation Tolerance (Phases 14-15, shipped clean). Full archives: `.planning/milestones/sgproc-render-v2.0-*.md` through `sgproc-render-v2.2-*.md`.

## v2.3 Requirements — Deferred Gap Closure

This milestone was not new feature work — it closed four real, previously-surfaced gaps that no prior milestone picked up: Phase 08's deferred manifest-evolution scope (2026-08-05), an untested cross-hardware risk on the render path flagged in v2.2's STATE.md, a pre-existing build-stability bug (2026-08-10), and an unverified assumption about whether v2.2's Phase 15 fix actually closes v2.1's VALD-01 finding.

### Manifest Evolution (Phase 08 deferred scope)

- [x] **ARTF-07**: Chunk integrity is verifiable via a Merkle tree over chunk hashes, not just the existing flat content hash — **Outcome: Won't implement, not applicable** (16-CONTEXT.md D-01..D-04: `Artifact::chunkHashes` already gives full per-chunk localization; graphsync/protobuf already deliver the complete chunk-hash list to every real verifier, so a root-only Merkle proof serves no scenario this system's actual verification flow has).
- [x] **ARTF-08**: Chunking uses content-defined boundaries instead of fixed-size, so a small edit doesn't invalidate every downstream chunk hash — **Outcome: Won't implement, not applicable** (16-CONTEXT.md D-05..D-08: `block_len` is a job-poster-owned schema parameter, not SGProcessingManager's to renegotiate).
- [x] **ARTF-09**: The execution manifest's error details carry a human-readable message string alongside the existing structured error code — **Outcome: validated.** `ExecutionManifest::errorMessage[256]` delivered via a bounds-checked, append-only binary trailer; `ProcessInternal()` builds a manifest with real error text on every terminal path.
- [x] **ARTF-10**: The manifest's binary format supports schema evolution (new optional fields) without breaking older readers — **Outcome: validated.** `SerializeManifest`/`DeserializeManifest`'s append-only trailer proven in both compatibility directions (new-writer-old-reader via a test-local base-fields-only proxy, old-writer-new-reader via absent-field defaulting).

### Render-Path Cross-Hardware Tolerance

- [x] **RENDTOL-01**: Three non-trivial render fixtures exist (texturing, blending, and lighting — MSAA excluded per D-03's architectural hard-block), each exercising real floating-point-heavy render computation — **Outcome: validated.** All 3 fixtures built; Round 2 (17-08) proved via real two-machine capture that each exercises genuine non-trivial computation.
- [x] **RENDTOL-02**: The render output path has a real schema-configurable tolerance mechanism (mirroring Phase 14's `ResolveQuantScale`/`ResolveByteQuantMode` pattern), replacing `QuantizeByteBuffer`'s current byte-identity no-op — **Outcome: validated.** Mechanism exists and `byteQuantMode` values (lighting=5, blending=6, texturing=7) are derived and counter-test-proven not-too-loose; lighting+texturing hash-matched in Round 2; blending closed via a numeric-tolerance-fallback path (D-10/D-11) — `capture_diff`'s `--byte-quant-mode` raw-tolerance check confirms blending's real raw cross-hardware delta (1.0) is within `byteQuantMode=6`'s tolerance bound (63) against Round 2's already-captured `preQuantizeBytes`, mirroring production's `AttemptToleranceFallback` exactly. The strict quantized-hash mismatch (`maxAbsDelta=64.0`) remains true and is documented side by side, not reinterpreted.

### Build Stability

- [x] **BUILD-01**: `ProcessingManager::Create()`'s Vulkan capability-probe no longer deadlocks `ProcessingDatatypesTest`/`ProcessingDispatchTest`/`vulkan_init_concurrency_test` when a real Vulkan device is present — **Outcome: validated (verify-and-close).** Confirmed already fixed by pre-existing commit `528a92a`, predating the bug report; closed with a persistent regression `TEST_F` + fail-fast CMake `TIMEOUT` and a documented evidence trail.

### Validation Re-Verification

- [x] **VALD-02**: The original VALD-01 MNN float32 fixture is re-run through Phase 15's `ValidateResults` tolerance-fallback mechanism, with the outcome documented with evidence — **Outcome: CLOSED.** `AttemptToleranceFallback` genuinely engages for chunk 10 (`maxAbsDelta=3.0517578125e-05`, within the `2.0/32768.0=6.103515625e-05` D-03 bound) and resolves it as a match; `ValidateResults` reports no error and invalidates zero subtasks across the full 15-chunk fixture. Re-run against a fresh 2-machine capture (D-01-REVISED) after Phase 13's original archived `.cap` files were found unreadable by current tooling — an unrelated pre-existing regression, documented in `19-REVERIFICATION.md`, not fixed this phase.

## v2 Requirements

Deferred to future milestones. Not addressed this milestone.

### Cross-Node Orchestration

- **XNODE-01c**: Actual cross-node consensus/redundant-execution comparison plumbing — the comparison mechanism itself (XNODE-01b/XNODE-02) is correct and tolerant as of v2.2; wiring it into real multi-node job orchestration remains future work. Considered CI-verification scope, not application-level work for this workstream.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Phase 04 (v1.0) pending UAT scenario + `human_needed` verification | Pre-existing carryover, re-acknowledged unchanged at v2.0, v2.2, and now v2.3 close; unrelated to this milestone's gap set |
| Semantic/output-level comparison (e.g. Dice/overlap score) for segmentation-style workloads | Raised as a design note in v2.2's STATE.md but is a larger architectural question than a single-milestone fix |
| `DeserializeCaptureFile`'s pre-Phase-16 `.cap` backward-compatibility regression (discovered during Phase 19) | Out of Phase 19's declared scope (D-04); flagged as a new deferred item, not yet queued to a specific future phase |

## Traceability (Final)

| Requirement | Phase | Status |
|-------------|-------|--------|
| ARTF-07 | Phase 16 | Won't implement — not applicable (D-01..D-04) |
| ARTF-08 | Phase 16 | Won't implement — not applicable (D-05..D-08) |
| ARTF-09 | Phase 16 | ✓ Complete |
| ARTF-10 | Phase 16 | ✓ Complete |
| RENDTOL-01 | Phase 17 | ✓ Complete |
| RENDTOL-02 | Phase 17 | ✓ Complete — numeric-tolerance fallback proven (17-TOLERANCE-RESULTS.md Gap Closure Addendum) |
| BUILD-01 | Phase 18 | ✓ Complete |
| VALD-02 | Phase 19 | ✓ Complete — CLOSED (19-REVERIFICATION.md) |

**Coverage:**

- v2.3 requirements: 8 total, 8 shipped (6 delivered, 2 formally concluded won't-implement-not-applicable), 0 dropped
- All requirements mapped and resolved exactly as scoped — no requirement was invalidated or rescoped during execution

---
*Archived: 2026-08-21 at v2.3 milestone close*
