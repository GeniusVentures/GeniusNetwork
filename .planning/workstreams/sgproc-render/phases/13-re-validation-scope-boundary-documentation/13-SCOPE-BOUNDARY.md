---
phase: 13-re-validation-scope-boundary-documentation
captured: 2026-08-12
status: real-quantization re-validation of Phase 11's 2-machine dataset — MNN fixture shows an OPEN GAP against SC1 (narrowed by Plan 13-05's S=2^15 Refit round to 1/15 divergent chunks, still not unconditionally clean)
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

## SC1 Refit: Widened-Grid Re-Measurement

Plan 13-04 widened `QuantizeFloatBuffer`'s fixed rounding grid in response to this document's own "Open Gap Against SC1" statement above. The **real, applied fix is S=2^15, not S=2^14** — the plan's original text proposed S=2^14 (grid step `6.103515625e-05`, 64x the old grid step), but Plan 13-04's Task 1 discovered a hard SECV-01 boundary during its local binary search: S=2^14 makes `Secv01CounterTest.MnnCorruptedModelStillDiverges` **fail deterministically** (the corrupted MNN model's post-quantization `artifactId` collides bit-for-bit with the correct model's — confirmed twice, not flaky). S=2^15 (grid step `3.0517578125e-05`) was chosen instead, keeping one full power-of-two step of margin above that confirmed failure boundary rather than sitting at its exact edge. S=2^15's grid step is **32x** the original S=2^20 grid step (`9.5367431640625e-07`) and **~292x** Phase 11's originally-measured `maxAbsDelta` (`1.043081283569336e-07`) — see `quantization.hpp`'s own doc comment (lines 32-63) for the full derivation trail, including the SECV-01 boundary discovery, cited here verbatim rather than re-derived.

Full verbatim contents of `captures/diff-mnn-float-refit.json` (fresh Mac `Fuus-Mac-mini.local---macOS_20260812T232347.cap` vs fresh Windows `Mofu---Windows_20260812T232430.cap`, both captured with the S=2^15 fix compiled in and active):

```json
{
  "chunkHashesMatch": [
    true,
    true,
    true,
    true,
    true,
    true,
    true,
    true,
    true,
    true,
    false,
    true,
    true,
    true,
    true
  ],
  "combinedHashMatch": false,
  "contentHashMatch": true,
  "elementCount": 512,
  "elementType": "float32",
  "maxAbsDelta": 0.0,
  "maxRelDelta": 0.0,
  "maxUlpDistance": 0,
  "percentExceedingThreshold": 0.0,
  "sizeMismatch": false
}
```

**Outcome: the gap persists, but it is dramatically narrowed, not merely relabeled.** `contentHashMatch` is `true` (up from `false` in the original round), and of the 15 `chunkHashesMatch` entries, only **1** is now `false` (`chunkHashesMatch[10]`) — down from **12** false entries in the original S=2^20 round. `maxAbsDelta`, `maxRelDelta`, and `maxUlpDistance` are all now exactly `0` (down from `9.5367431640625e-07` / `5.3748990467283875e-05` / `512` in the original round). This is **not** an unconditionally clean result per this plan's own must_haves bar (contentHashMatch true AND every chunkHashesMatch entry true) — `chunkHashesMatch[10]` remains `false` — so **SC1 is still not fully satisfied for the MNN float32 fixture**, exactly as honestly reported below rather than rounded into a pass. Do not read "still Partial" as "no progress was made": measured cross-hardware divergence for this fixture went from 12/15 divergent chunks with a non-zero measured delta to 1/15 divergent chunk with zero measured delta anywhere the numeric pass can see.

**Investigation note — the chunkHashesMatch[10]-despite-zero-delta anomaly is not a contradiction; it is a real, distinct scope limitation in `capture_diff`'s diagnostic coverage, inherited unmodified from Phase 10.** Reading `capture_diff.cpp`'s actual per-element numeric-diff logic (not assumed from the JSON field names alone):

- `capture_diff.cpp:295-296`'s own comment states the numeric pass runs "over the LAST CaptureRecord's quantizedBytes -- the same bytes that fed each run's contentHash" — a deliberate, documented restriction, not an oversight.
- `capture_diff.cpp:308-319` confirms this in code: `lastRecordA`/`lastRecordB` are taken from `captureA.rawRecordsPerArtifact[0].back()` / `captureB.rawRecordsPerArtifact[0].back()` — the single **trailing** raw capture record — and only that one record's bytes feed `ComputeFloat32Diff` (and therefore `maxAbsDelta`/`maxRelDelta`/`maxUlpDistance`/`percentExceedingThreshold`/`elementCount`).
- `capture_diff.cpp:283-291` computes `chunkHashesMatch[j]` completely independently, by comparing `artifactA.chunkHashes[j]` against `artifactB.chunkHashes[j]` — pre-computed `Artifact`-level SHA-256 fields, not derived from any raw byte buffer this tool itself re-diffs.
- `capture_file_format.hpp:52-59`'s `CaptureRecord` doc comment states each record is "either a per-chunk capture (paired with one entry of `Artifact::chunkHashes`) or the trailing combined-hash capture (paired with `Artifact::contentHash`), in call order" — i.e. the trailing record and each per-chunk record are genuinely **different byte buffers**, not aliases of the same data.
- `capture_file_format.hpp:73-78`'s `rawRecordsPerArtifact` doc confirms the index mapping: `records[0 .. chunkHashCount - 1]` correspond 1:1 to `chunkHashes[0 .. chunkHashCount - 1]`, and the optional trailing record (`records[chunkHashCount]`, i.e. `.back()` when present) corresponds to `contentHash` — exactly the record `capture_diff.cpp` numeric-diffs.
- `capture_harness.cpp:276-315` (`SelfCheckCapturedBytes`) independently re-hashes `records[j]` for `j < chunkHashCount` against `artifact.chunkHashes[j]`, and separately re-hashes `records.back()` against `artifact.contentHash` only when `records.size() == chunkHashCount + 1` — confirming at capture time that these are distinct, individually self-checked buffers, not a single buffer serving double duty.

**Conclusion:** `contentHashMatch: true` and `maxAbsDelta`/`maxRelDelta`/`maxUlpDistance: 0` all describe the *same* trailing combined-hash record, which is genuinely bit-identical Mac vs Windows under the S=2^15 fix. `chunkHashesMatch[10]: false` describes a *different* byte buffer — chunk 10's own individual raw capture — that `capture_diff`'s numeric pass never examines at all, by design, unchanged since Phase 10. There is no logical contradiction and no new defect introduced by this fix: `capture_diff` simply reports *that* chunk 10 still diverges (via the independent hash comparison) without ever reporting *by how much*, because its numeric per-element pass has never covered any per-chunk record, only the trailing one. Fully diagnosing chunk 10's remaining divergence (e.g. confirming whether one of its elements sits closer to a grid boundary than S=2^15's margin absorbs) would require extending `capture_diff` to also numeric-diff each `rawRecordsPerArtifact[0][j]` record individually — out of scope for this plan, and flagged here as a follow-up for whoever next picks up VALD-01's remaining chunk-10 gap.

**Honest closing caveat (restating this phase's own core caveat, per `quantization.hpp`'s doc comment and this gap-closure round's objective):** a fixed rounding grid is a probabilistic engineering mitigation, not a mathematical guarantee, for arbitrary per-element cross-hardware deltas that happen to land close to a rounding boundary. S=2^15 substantially reduced (from 12/15 to 1/15 divergent chunks) but did not eliminate that probability for this fixture's actual values.

## SC1 Diagnostic: Chunk 10 Per-Element Numeric Characterization

Plan 13-06 closed the exact blind spot the "Investigation note" above flagged as a follow-up: `capture_diff` previously could report only *that* chunk 10 diverges (`chunkHashesMatch[10]: false`), never *by how much*, because its numeric per-element pass only ever examined the trailing combined-hash record, never any individual per-chunk raw record. Plan 13-06's Task 1 extended `capture_diff.cpp` with a new `chunkDiffs` JSON array that numeric-diffs every `rawRecordsPerArtifact[0][j]` record individually (the same `ComputeFloat32Diff` function already used for the trailing record, applied per-chunk), rebuilt the tool, and re-ran it against the already-existing S=2^15-era Mac vs Windows MNN capture pair from Plan 13-04's hands-on session (`xhw-mnn-float_Fuus-Mac-mini.local---macOS_20260812T232347.cap` vs `xhw-mnn-float_Mofu---Windows_20260812T232430.cap`) — the exact pair the SC1 Refit section above already diffed at the trailing-record level.

**Diagnostic source and provenance (Task 2 checkpoint resolution):** the operator reviewed Task 1's diagnostic output and explicitly replied "confirmed" at Task 2's blocking checkpoint, choosing to treat this existing-capture re-run as authoritative rather than performing an optional fresh hands-on recapture. Per `capture_harness.cpp:495-501` (`captureFile.rawRecordsPerArtifact = { iterations[0].records }`), every already-committed `.cap` file from that session already stored all 15 per-chunk raw records plus the trailing one — only `capture_diff`'s own comparison logic lacked the ability to numeric-diff them individually, which Task 1 fixed. No new hardware capture was required or performed; the diagnostic below reflects a fresh *analysis* of the same bytes the SC1 Refit section's trailing-record result already cites, not a fresh *capture*. The authoritative diagnostic JSON is `captures/diff-mnn-float-refit-chunkdiag.json`.

Verbatim `chunkDiffs[10]` from that JSON (the chunk `chunkHashesMatch[10]` reports as `false`; all other 14 `chunkDiffs` entries report `maxAbsDelta: 0.0`, `maxRelDelta: 0.0`, `maxUlpDistance: 0`, `percentExceedingThreshold: 0.0`, `sizeMismatch: false` — i.e. this diagnostic is entirely isolated to chunk 10):

```json
{
  "chunkIndex": 10,
  "elementCount": 64,
  "maxAbsDelta": 3.0517578125e-05,
  "maxRelDelta": 0.00015477479610126466,
  "maxUlpDistance": 2048,
  "percentExceedingThreshold": 1.5625,
  "sizeMismatch": false
}
```

**Grid-step ratio.** `quantization.hpp`'s current S=2^15 grid step is `3.0517578125e-05` (lines 32-63). Chunk 10's `maxAbsDelta` (`3.0517578125e-05`) divided by that grid step is:

`3.0517578125e-05 / 3.0517578125e-05 = 1.0` (exactly)

**Honest characterization.** Chunk 10's real, previously-invisible divergence is exactly **one** S=2^15 grid step — not a fraction of a step, and not multiple steps. `percentExceedingThreshold: 1.5625` corresponds to exactly `1` of the chunk's `64` elements (`1/64 = 1.5625%`); the other 63 elements in this chunk, and every element in the other 14 chunks, show zero measured delta anywhere this diagnostic pass can see. This pattern — a single element, in a single chunk, diverging by precisely one grid step, with everything else bit-identical — is consistent with a genuine rounding-boundary tie-break: that one element's true (pre-quantization) value sits close enough to a grid boundary that Mac's and Windows' independent floating-point evaluations round it into adjacent grid buckets, while every other element across both fixtures' 512 total elements lands unambiguously inside a single bucket on both machines. It is not consistent with a scaling error, a systematically miscalibrated grid, or a broader divergence than already understood: a scaling or calibration defect would be expected to produce errors proportional to element magnitude or spread across more than one element/chunk, and this data shows neither. The `maxUlpDistance` of `2048` looks large in raw ULP terms, but ULP spacing is magnitude-dependent for IEEE-754 floats — a single one-grid-step jump for a value in this element's magnitude range corresponds to exactly this ULP count; it is not independent evidence of a larger divergence than the `maxAbsDelta` ratio (exactly `1.0`) already shows.

**This diagnostic does not, by itself, close VALD-01's residual gap.** Per this plan's hard constraint, no further grid-widening beyond the current S=2^15 scale is proposed as a fix — S=2^15 was already chosen via a confirmed local binary search with exactly one power-of-two step of margin above a confirmed SECV-01 failure boundary (the next-smaller power-of-two scale makes `Secv01CounterTest.MnnCorruptedModelStillDiverges` fail deterministically; see `quantization.hpp` lines 32-63 and 13-04-SUMMARY.md), and going any coarser than S=2^15 is not a safe option this plan's scope permits revisiting.

**No further mitigation is recommended here.** This data does not surface a new, clearly-safe follow-on fix beyond what the SC1 Refit section's own closing caveat already states: a fixed rounding grid is a probabilistic engineering mitigation, not a mathematical guarantee, and this fixture's real values include exactly one element whose true cross-hardware delta happens to straddle a grid boundary at the current S=2^15 scale. Isolating and inspecting that single element's exact pre-quantization value (e.g. via targeted per-element logging) could in principle confirm the tie-break theory with certainty, but implementing that instrumentation is optional future diagnostic work, not a fix, and is left for whoever next picks up VALD-01's remaining 1/15-chunk gap.

**Follow-up tested 2026-08-13 (post-Plan-13-06, outside the plan's own scope): FP16 backend opportunism ruled out.** `processing_processor_mnn_float.cpp` had never set an explicit `MNN::BackendConfig` (`config.backendConfig = nullptr`), leaving MNN at its default `Precision_Normal`, which permits GPU backends discretion to use FP16 internally for some ops even on FP32-declared tensors. This was a plausible candidate mechanism for chunk 10's divergence (different Vulkan implementations making different FP16-vs-FP32 choices), and cheap to test. Result: forcing `backendConfig.precision = Precision_High` and re-running against the same S=2^15-era Mac vs Windows capture pair produced a **bit-for-bit identical** `chunkDiffs[10]` (`maxAbsDelta: 3.0517578125e-05`, `maxRelDelta: 0.00015477479610126466`, `maxUlpDistance: 2048`, `percentExceedingThreshold: 1.5625` — every field unchanged from the diagnostic above). This rules out FP16 opportunism as the source: MNN's Vulkan backend was evidently already computing this op sequence in full FP32 regardless of the precision flag. The change was reverted (commented out, dated, with this citation) since it had no correctness benefit and only a potential performance cost. This strengthens the case that the remaining divergence is genuine FP32-level hardware/driver non-associativity between the two GPU vendors (NVIDIA on Windows, Apple Silicon via MoltenVK on Mac) — a source no MNN precision setting can address, since both sides are already at full precision.

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

**Update (this phase's own gap-closure round, Plan 13-04): the constant below is no longer S=2^20.** The empirical derivation immediately following this note (S=2^20, D-05, ~10x margin over Phase 11's original `maxAbsDelta`) describes what was true at the time Plan 13-03 originally wrote this SC4 section — it remains historically accurate as a record of that original round's derivation and is preserved unedited below. But Plan 13-04, responding to this same document's "Open Gap Against SC1" finding (12/15 MNN chunks still diverging at S=2^20), subsequently changed the live constant to **S = 2^15 (32768.0f)** — chosen via a local binary search over power-of-two values after the plan's originally-proposed S=2^14 was found to regress `Secv01CounterTest.MnnCorruptedModelStillDiverges`. **S=2^15 is the actual current, final constant as of this phase's close**, not S=2^20. See the "SC1 Refit: Widened-Grid Re-Measurement" section above for the full S=2^15 derivation (grid step `3.0517578125e-05`, 32x the S=2^20 grid step, ~292x Phase 11's original `maxAbsDelta`, and the SECV-01-boundary discovery that motivated it), and `quantization.hpp`'s own doc comment (lines 32-63) for the permanent source-of-truth citation trail. The two sections do not disagree: SC1 Refit and this note both correctly state S=2^15 is current; only the empirical-derivation prose immediately below is a historical snapshot of the original S=2^20 round, not a claim about what is current today.

Quoting `quantization.hpp`'s constants **as they stood after Plan 13-03's original re-validation round** (prior to Plan 13-04's subsequent S=2^15 gap-closure change noted above):

- **MNN float32 path (`QuantizeFloatBuffer`):**
  - Canonicalization (evaluated strictly before rounding, D-07): denormals (both signs) flush to `0x00000000`; NaN (any payload/sign/signaling bit) canonicalizes to the hardcoded quiet-NaN pattern `0x7FC00000` (D-09); `+Inf`/`-Inf` canonicalize to two **distinct** fixed patterns, `0x7F800000`/`0xFF800000` respectively (D-06, so a wrong-sign divergence stays visible to SECV-01); `-0.0`/`+0.0` both collapse to the single canonical zero bit pattern `0x00000000` (D-08). **This canonicalization logic is untouched by Plan 13-04's later change and remains accurate today.**
  - Rounding (original Phase 12 value, superseded by Plan 13-04 — see the update note above): `q = round(x * S) / S`, with scale factor `S = 2^20` = `1048576.0f` (D-05), a power-of-two chosen for exact float round-tripping. This gave a grid step of approximately `1e-6`.
  - This is a single fixed absolute epsilon (D-04) — not magnitude-adaptive, not relative/ULP-based, not schema-configurable this milestone. (This design property also still holds for the current S=2^15 constant — only the specific scale value changed.)
- **Render uint8 path (`QuantizeByteBuffer`):** deliberate identity pass-through — byte-identity, no lossy tolerance band applied. **Unchanged by Plan 13-04, still current.**

**Empirical derivation of the original S=2^20 choice**, citing Phase 11's exact captured numbers verbatim (`11-CAPTURE-RESULTS.md`, MNN float32, 512 elements, Mac vs Windows, pre-quantization/no-op-stub era):

- `maxAbsDelta`: exact `1.043081283569336e-07` (≈`1.043e-07`)
- `maxRelDelta`: exact `7.269731577252969e-05` (≈`7.27e-05`)
- `maxUlpDistance`: `768`

`quantization.hpp`'s own doc comment states the chosen `~1e-6` grid step provides "roughly 10x margin over Phase 11's measured cross-machine (Mac vs Windows) MNN float32 divergence" — i.e. the grid step is sized approximately 10x larger than the pre-quantization `maxAbsDelta ≈ 1.043e-07` Phase 11 measured, intended to absorb that divergence within a single quantization bucket. This document's own fresh Phase 13 measurement (see SC1 above) shows this margin does not fully close the gap for every element of the MNN fixture: this run's post-quantization `maxAbsDelta` (`9.5367431640625e-07`) is itself close to the ~1e-6 grid step, and 12 of 15 chunk hashes still diverge — meaning at least some elements' actual cross-hardware delta is landing close enough to (or in some elements' case, apparently exceeding what a single rounding step absorbs for) the grid boundary that the round-to-grid outcome differs Mac vs Windows for those elements. This is exactly the "open gap" flagged in the SC1 section above, not resolved by re-deriving the constant here.

For the render uint8 path, Phase 11's `contentHashMatch: true` finding (all deltas `0.0`, same fixture, same 2-machine pair) is cited as the empirical justification for `quantization.hpp`'s deliberate byte-identity (no lossy tolerance) design choice: no observed cross-hardware divergence in the uint8 render path this milestone's fixtures exercise, so applying a lossy tolerance band here would only enlarge the space of results indistinguishable from a correct one with no empirical justification. This phase's fresh SC1 render result (above) reconfirms `contentHashMatch: true` with quantization active, consistent with that original justification.

## Traceability

`REQUIREMENTS.md`'s VALD-01 and `ROADMAP.md`'s Phase 13 SC1 now read "≥2 distinct physical machines" and "processor-level result/chunk hash(es)" (Plan 13-02's edit) — the wording-reconciliation half of this phase's closeout is complete. This document is the empirical re-validation those corrected words point to. Of the v2.1 milestone's 12/12 requirements, `VALD-01` is the last, and per the SC1 section above it was **partially, not fully, satisfied** as of this document's original round: the render fixture's processor-level hash matched cross-hardware as required; the MNN fixture's did not, for 12 of 15 chunks.

**Update (this same phase's own gap-closure round, Plans 13-04/13-05):** that gap was picked up without leaving this phase — see the "SC1 Refit" section above. Widening the quantization grid to S=2^15 narrowed the MNN fixture's divergence from 12/15 to 1/15 chunks, but did not eliminate it; VALD-01 remains **Partial** in REQUIREMENTS.md/ROADMAP.md, now citing both this document's original round and the fresh Refit evidence (`captures/diff-mnn-float-refit.json`). Any future work on VALD-01's remaining 1-chunk gap should start from the SC1 Refit section's honest closing caveat, not from this original round's now-superseded 12/15 figure.
