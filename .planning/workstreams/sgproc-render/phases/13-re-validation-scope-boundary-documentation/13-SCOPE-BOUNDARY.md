---
phase: 13-re-validation-scope-boundary-documentation
captured: 2026-08-12
status: real-quantization re-validation of Phase 11's 2-machine dataset — MNN fixture shows an OPEN GAP against SC1
---

# Phase 13: Re-Validation & Scope Boundary Documentation — Results + Scope Boundary

**Phase Goal:** The milestone's literal acceptance criterion is empirically reconfirmed with real quantization active, and the milestone's scope boundary is written down explicitly: this milestone makes hash comparison cross-hardware tolerant, it does not fix `ProcessingValidationCore::ValidateResults`'s concatenation bug and does not build cross-node consensus/redundant-execution plumbing.
**Captured:** 2026-08-12
**Status:** This is the real-quantization (Phase 12) re-validation of Phase 11's 2-machine (Mac + Windows) dataset — Phase 11's own run measured raw divergence with quantization still a no-op stub; this run measures the same two fixtures with Phase 12's real `QuantizeFloatBuffer`/`QuantizeByteBuffer` active. This single document combines the re-validation results (SC1/SC2/SC4) and the explicit scope-boundary statement (SC3) per 13-CONTEXT.md's D-08/D-09.

**This document does not universally confirm SC1.** The render uint8 fixture confirms cross-hardware byte-identity as before. The MNN float32 fixture's fresh processor-level hash comparison reports `contentHashMatch: false` and 12 of 15 `chunkHashesMatch` entries `false` — an open gap, stated honestly below rather than rounded away.

## Re-Validation Scope

Phase 13 reuses the same accepted 2-machine dataset (Mac `Fuus-Mac-mini.local---macOS`, Windows `Mofu---Windows`) that Phase 11 established — no genuine 3rd physical machine has appeared since (D-01). This mirrors Phase 11's own D-01/D-03 precedent exactly; see `13-CONTEXT.md`'s D-01/D-02 for the full reconciliation record, and `11-CAPTURE-RESULTS.md`'s "Scope Decision" section for the original WSL/llvmpipe-software-rasterizer exclusion rationale this phase does not re-litigate.

The contrast against Phase 11's original run: Phase 11 captured raw cross-hardware divergence with quantization still a no-op stub (Phase 10/11 state) — its `contentHashMatch: false` for MNN was expected and uninformative about normalization efficacy, since no normalization was running. This phase's captures (Plan 13-01, 4 fresh `.cap` files, `captures/xhw-mnn-float_*.cap` and `captures/xhw-render_*.cap`, both dated 2026-08-12) were gathered with Phase 12's real quantization compiled in and active on both machines, so this run's `contentHashMatch`/`chunkHashesMatch` values are the actual empirical answer to "does the chosen normalization make the processor-level hash cross-hardware tolerant" — not a stub-era placeholder.

## SC1: Processor-Level Hash Re-Validation

Per D-03/D-04 (12-CONTEXT.md D-01, 13-CONTEXT.md D-03/D-04), VALD-01/ROADMAP SC1's "matching hashes" target is the **processor-level** `ProcessingResult.hash`/chunk-hash — surfaced here by `capture_diff`'s `contentHashMatch`/`chunkHashesMatch` fields, which are computed directly from each capture's `Artifact.contentHash`/`Artifact.chunkHashes` (`capture_diff.cpp` DIFF-03 logic). This is explicitly **not** `ProcessOutput.combinedHash`/`ExecutionManifest.manifestHash` (`capture_diff`'s separate `combinedHashMatch` field) — that manifest-level hash bakes in machine-specific `executorIdentity` (a SHA-256 over each machine's real Vulkan device name/vendor/driver properties, `capability_types.hpp`) and `gpuMemoryUsedBytes` by construction (`ProcessingManager.cpp:1500-1510`, `ComputeManifestHash`), and is expected to stay cross-machine-mismatched regardless of any output-data normalization. **A `false` `combinedHashMatch` below is not a Phase 13 failure — it is explained here, not silently omitted.**

### MNN Float32 Fixture

Full verbatim contents of `captures/diff-mnn-float.json` (Mac `Fuus-Mac-mini.local---macOS_20260812T212550.cap` vs Windows `Mofu---Windows_20260812T212019.cap`):

```json
{
  "chunkHashesMatch": [
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    true,
    false,
    true,
    false,
    false,
    false,
    true
  ],
  "combinedHashMatch": false,
  "contentHashMatch": false,
  "elementCount": 512,
  "elementType": "float32",
  "maxAbsDelta": 9.5367431640625e-07,
  "maxRelDelta": 5.3748990467283875e-05,
  "maxUlpDistance": 512,
  "percentExceedingThreshold": 0.0,
  "sizeMismatch": false
}
```

**Interpretation:** `elementCount` is 512 (unchanged from Phase 11's fixture shape). This is the **processor-level** comparison SC1 requires: `contentHashMatch` (the `Artifact.contentHash` field, i.e. the processor's post-quantization result hash) is `false`, and of the 15 `chunkHashesMatch` entries (each an `Artifact.chunkHashes[j]` comparison), 12 are `false` and only 3 (`chunkHashesMatch[8]`, `[10]`, `[14]`) are `true`. `combinedHashMatch` is also `false`, exactly as expected per D-03 — this field is the manifest-level hash and is not the SC1 target; its `false` value here carries no additional information beyond what `contentHashMatch` already shows and is not itself a new failure.

**Open Gap Against SC1 (honest statement, per this plan's must_haves and the Task 2 acceptance criteria):** The MNN fixture's fresh post-quantization processor-level hash does **not** match cross-hardware. `maxAbsDelta` (`9.5367431640625e-07`) and `maxRelDelta` (`5.3748990467283875e-05`) are both within `quantization.hpp`'s documented ~1e-6 grid step, and are in fact smaller than Phase 11's own pre-quantization measurement (`maxAbsDelta ≈ 1.043081283569336e-07`... — see the SC4 section below for why this comparison itself needs care) — yet the resulting quantized hash still does not match bit-for-bit across all 15 chunks. This is recorded here as ground truth, not reinterpreted into a passing result: **SC1 is not fully satisfied for the MNN float32 fixture as of this re-validation.** The render uint8 fixture (below) does satisfy the processor-level hash-match target. Resolving why 12/15 MNN chunks still diverge post-quantization (e.g. whether the round-to-grid step is landing elements exactly on a grid boundary where a ±1 ULP tie-break differs Mac vs Windows, or whether some elements' pre-quantization delta exceeds the grid step in ways Phase 11's smaller sample didn't surface) is not resolved by this document — it is flagged as an open item for whoever picks up VALD-01's remaining gap.

### Render Uint8 Fixture

Full verbatim contents of `captures/diff-render.json` (Mac `Fuus-Mac-mini.local---macOS_20260812T212610.cap` vs Windows `Mofu---Windows_20260812T212117.cap`):

```json
{
  "chunkHashesMatch": [],
  "combinedHashMatch": false,
  "contentHashMatch": true,
  "elementCount": 256,
  "elementType": "uint8",
  "maxAbsDelta": 0.0,
  "maxRelDelta": 0.0,
  "maxUlpDistance": 0,
  "percentExceedingThreshold": 0.0,
  "sizeMismatch": false
}
```

**Interpretation:** `elementCount` is 256. `contentHashMatch` (the processor-level `Artifact.contentHash` comparison SC1 targets) is `true` — the render path's post-quantization result hash matches bit-for-bit across Mac and Windows. `chunkHashesMatch` is an empty array for this fixture (render has no chunking, consistent with Phase 11's own finding and Phase 10's capture format). All numeric deltas (`maxAbsDelta`, `maxRelDelta`, `maxUlpDistance`, `percentExceedingThreshold`) are `0` — the raw pixel bytes are identical across machines, matching `quantization.hpp`'s deliberate byte-identity design for this path (see SC4 below). `combinedHashMatch` is `false`, exactly as expected per D-03 (manifest-level hash, not the SC1 target — see the SC1 preamble above) and consistent with Phase 11's own identical finding (`contentHashMatch: true` / `combinedHashMatch: false` pairing).

**SC1 is satisfied for the render uint8 fixture.**

## SC2: SECV-01 Re-Confirmation

Per D-07, this section only cites the fresh CTest re-run's actual output (`13-SECV01-RERUN.txt`, Plan 13-02) — no new test logic was written; Phase 12's constants are the final precision and nothing changed on the SECV-01 side between Phase 12 and Phase 13.

Verbatim result lines from `13-SECV01-RERUN.txt`:

```
92: [ RUN      ] Secv01CounterTest.MnnCorruptedModelStillDiverges
92: MnnCorruptedModelStillDiverges: correct and corrupted-model artifactId hashes differ as required
92: [       OK ] Secv01CounterTest.MnnCorruptedModelStillDiverges (5843 ms)
92: [ RUN      ] Secv01CounterTest.RenderWrongShaderConstantStillDiverges
92: RenderWrongShaderConstantStillDiverges: correct and wrong-color artifactId hashes differ as required
92: [       OK ] Secv01CounterTest.RenderWrongShaderConstantStillDiverges (580 ms)
92: [----------] 2 tests from Secv01CounterTest (6433 ms total)
92: [==========] 2 tests from 1 test suite ran. (6433 ms total)
92: [  PASSED  ] 2 tests.
1/1 Test #92: processing_conformance_security_test ...   Passed    8.43 sec
100% tests passed, 0 tests failed out of 1
```

**SC2 is satisfied.** Both `Secv01CounterTest` cases — the MNN corrupted-model-weights path (D-10) and the render wrong-shader-push-constant path (D-11) — passed at the final chosen precision, confirming the chosen quantization tolerance is not loose enough to also accept a deliberately wrong result, reported here alongside (not assumed independently of) the SC1 re-validation above.

## Scope Boundary

Per ROADMAP SC3 and 13-CONTEXT.md D-09, quoting `REQUIREMENTS.md`'s own `## Out of Scope` table wording verbatim (not paraphrased):

1. **Hash comparison is now cross-hardware tolerant** — this milestone's actual delivered scope. `QUANT-01`/`QUANT-02`/`QUANT-03`/`QUANT-04`/`SECV-01` are all complete (per `REQUIREMENTS.md`'s traceability table); the render path's processor-level hash is confirmed cross-hardware matching above, and the MNN path's is confirmed cross-hardware tolerant to within the documented grid step even where the resulting hash does not yet fully match (see the Open Gap statement above).
2. **`ProcessingValidationCore::ValidateResults`'s concatenation bug remains unfixed** — quoting `REQUIREMENTS.md`'s Out of Scope table verbatim: *"Fixing `ProcessingValidationCore::ValidateResults`'s concatenation bug | Separate, already-tracked gap in the production comparison path — this milestone's scope is the hash itself, not the comparison mechanism around it"*. It never actually diffs two subtasks' hashes for the same chunk (tracked as `XNODE-01b`), so a genuine cross-node mismatch would silently pass in production today, independent of anything this milestone changed.
3. **No cross-node consensus/redundant-execution plumbing was built** — quoting `REQUIREMENTS.md`'s Out of Scope table verbatim: *"Actual cross-node consensus/redundant-execution plumbing | This milestone proves the hash *can* be cross-hardware tolerant; wiring that into production multi-node job validation is future work"* (tracked as `XNODE-01c`).

**No downstream consumer should read this milestone's output as "verification" or "consensus-ready"** — this is ROADMAP SC3's own literal wording. This milestone proves the processor-level hash *can* be made cross-hardware tolerant (with one open gap on the MNN fixture, stated above); it does not fix the comparison mechanism that would consume that tolerance in a genuine multi-node consensus scenario, and it does not build that consensus/redundant-execution plumbing at all.

## SC4: Final Normalization Constants

Quoting `quantization.hpp`'s actual final constants (unmodified this phase, read as source of truth):

- **MNN float32 path (`QuantizeFloatBuffer`):**
  - Canonicalization (evaluated strictly before rounding, D-07): denormals (both signs) flush to `0x00000000`; NaN (any payload/sign/signaling bit) canonicalizes to the hardcoded quiet-NaN pattern `0x7FC00000` (D-09); `+Inf`/`-Inf` canonicalize to two **distinct** fixed patterns, `0x7F800000`/`0xFF800000` respectively (D-06, so a wrong-sign divergence stays visible to SECV-01); `-0.0`/`+0.0` both collapse to the single canonical zero bit pattern `0x00000000` (D-08).
  - Rounding: `q = round(x * S) / S`, with scale factor `S = 2^20` = `1048576.0f` (D-05), a power-of-two chosen for exact float round-tripping. This gives a grid step of approximately `1e-6`.
  - This is a single fixed absolute epsilon (D-04) — not magnitude-adaptive, not relative/ULP-based, not schema-configurable this milestone.
- **Render uint8 path (`QuantizeByteBuffer`):** deliberate identity pass-through — byte-identity, no lossy tolerance band applied.

**Empirical derivation**, citing Phase 11's exact captured numbers verbatim (`11-CAPTURE-RESULTS.md`, MNN float32, 512 elements, Mac vs Windows, pre-quantization/no-op-stub era):

- `maxAbsDelta`: exact `1.043081283569336e-07` (≈`1.043e-07`)
- `maxRelDelta`: exact `7.269731577252969e-05` (≈`7.27e-05`)
- `maxUlpDistance`: `768`

`quantization.hpp`'s own doc comment states the chosen `~1e-6` grid step provides "roughly 10x margin over Phase 11's measured cross-machine (Mac vs Windows) MNN float32 divergence" — i.e. the grid step is sized approximately 10x larger than the pre-quantization `maxAbsDelta ≈ 1.043e-07` Phase 11 measured, intended to absorb that divergence within a single quantization bucket. This document's own fresh Phase 13 measurement (see SC1 above) shows this margin does not fully close the gap for every element of the MNN fixture: this run's post-quantization `maxAbsDelta` (`9.5367431640625e-07`) is itself close to the ~1e-6 grid step, and 12 of 15 chunk hashes still diverge — meaning at least some elements' actual cross-hardware delta is landing close enough to (or in some elements' case, apparently exceeding what a single rounding step absorbs for) the grid boundary that the round-to-grid outcome differs Mac vs Windows for those elements. This is exactly the "open gap" flagged in the SC1 section above, not resolved by re-deriving the constant here.

For the render uint8 path, Phase 11's `contentHashMatch: true` finding (all deltas `0.0`, same fixture, same 2-machine pair) is cited as the empirical justification for `quantization.hpp`'s deliberate byte-identity (no lossy tolerance) design choice: no observed cross-hardware divergence in the uint8 render path this milestone's fixtures exercise, so applying a lossy tolerance band here would only enlarge the space of results indistinguishable from a correct one with no empirical justification. This phase's fresh SC1 render result (above) reconfirms `contentHashMatch: true` with quantization active, consistent with that original justification.

## Traceability

`REQUIREMENTS.md`'s VALD-01 and `ROADMAP.md`'s Phase 13 SC1 now read "≥2 distinct physical machines" and "processor-level result/chunk hash(es)" (Plan 13-02's edit) — the wording-reconciliation half of this phase's closeout is complete. This document is the empirical re-validation those corrected words point to. Of the v2.1 milestone's 12/12 requirements, `VALD-01` is the last, and per the SC1 section above it is **partially, not fully, satisfied**: the render fixture's processor-level hash matches cross-hardware as required; the MNN fixture's does not yet, for 12 of 15 chunks, and that gap is recorded here rather than closed by this document. Any future phase picking up VALD-01's remaining MNN gap should start from this document's Open Gap statement and the fresh `captures/diff-mnn-float.json` this phase produced.
