---
phase: 17-render-path-cross-hardware-tolerance
captured: 2026-08-19/2026-08-20
status: Round 1 complete (2-machine dataset, Mac + Windows, D-09) -- all three fixtures
---

# Phase 17: Render-Path Cross-Hardware Tolerance -- Round 1 Capture Results

**Round:** 1 of 2 (D-06 methodology step 1) -- raw, `byteQuantMode`-absent divergence. None of the three fixture JSON definitions declares a `byteQuantMode` parameter, so `ResolveByteQuantMode`'s `N=0` identity fallback applied automatically for every capture in this round; `QuantizeByteBuffer` therefore ran as a no-op pass-through, measuring genuine unquantized cross-hardware divergence. Round 2 (with each fixture's derived non-zero `byteQuantMode`, Wave 6) is separate future work -- this document reports Round 1 only.

**Captured:** Windows side 2026-08-19 (Task 1, this plan); Mac side 2026-08-19/20 (Task 2, hands-on checkpoint).

**Dataset:** Phase 11's exact two-machine dataset (D-09) -- `Fuus-Mac-mini.local---macOS` and `Mofu---Windows`. No new hardware.

## Machines and Fixtures

Both machines are identified using their exact `.cap`-filename labels, mirroring `11-CAPTURE-RESULTS.md`'s convention:

- `Fuus-Mac-mini.local---macOS`
- `Mofu---Windows`

All three of this phase's new fixtures were captured on each machine, `--repeat 3`, no `capture_harness` instability reported on either machine for any of the six runs:

- **Lighting** (`xhw-render-lighting_*.cap`) -- Phong/Lambertian fragment-shader math (VEC3/VEC4/MAT4 uniforms, no new C++/schema infrastructure, D-05)
- **Blending** (`xhw-render-blending_*.cap`) -- new `pipeline_state` blend-state schema fields + real `VkPipelineColorBlendAttachmentState` wiring (D-05)
- **Texturing** (`xhw-render-texturing_*.cap`) -- new sampler/descriptor-set-layout infrastructure, `TEXTURE2_D` uniform support (D-05, the largest of the three)

The complete pairwise diff set is exactly 1 diff per fixture (Mac vs Windows), 3 diffs total -- already produced and present in `captures/`: `diff-render-lighting.json`, `diff-render-blending.json`, `diff-render-texturing.json` (all run with `--element-type uint8`, matching Phase 11's `xhw-render_*` convention -- render output is always raw RGBA/RGB pixel bytes).

## Lighting Fixture

Full verbatim contents of `captures/diff-render-lighting.json` (Mac vs Windows):

```json
{
  "chunkDiffs": [],
  "chunkHashesMatch": [],
  "combinedHashMatch": false,
  "contentHashMatch": true,
  "elementCount": 16384,
  "elementType": "uint8",
  "maxAbsDelta": 0.0,
  "maxRelDelta": 0.0,
  "maxUlpDistance": 0,
  "percentExceedingThreshold": 0.0,
  "sizeMismatch": false
}
```

**Interpretation:** `elementCount` is 16384. `contentHashMatch` is `true` -- the raw output bytes matched byte-for-byte across Mac and Windows -- alongside `combinedHashMatch` being `false` (expected: `combinedHashMatch` covers the whole manifest, which bakes in machine-specific fields like `executorIdentity`/`gpuMemoryUsedBytes` by design, mirroring the same `contentHashMatch`/`combinedHashMatch` split already documented in `11-CAPTURE-RESULTS.md`). `maxAbsDelta`, `maxRelDelta`, `maxUlpDistance`, and `percentExceedingThreshold` are all `0` -- the raw pixel bytes are identical. `chunkHashesMatch`/`chunkDiffs` are both empty arrays for this fixture, same as Phase 11's render fixture (no chunking, only the trailing combined-level hash). `sizeMismatch` is `false`.

Reported plainly, not reinterpreted: lighting's Phong/Lambertian fragment-shader math produced **zero measured cross-hardware divergence** on this dataset, mirroring the original trivial happy-path fixture's own zero-divergence surprise from Phase 11. This is a real finding, not a favorable rounding -- see "Zero-Divergence Flag" below.

## Blending Fixture

Full verbatim contents of `captures/diff-render-blending.json` (Mac vs Windows):

```json
{
  "chunkDiffs": [],
  "chunkHashesMatch": [],
  "combinedHashMatch": false,
  "contentHashMatch": false,
  "elementCount": 16384,
  "elementType": "uint8",
  "maxAbsDelta": 1.0,
  "maxRelDelta": 0.0078125,
  "maxUlpDistance": 1,
  "percentExceedingThreshold": 0.0,
  "sizeMismatch": false
}
```

**Interpretation:** `elementCount` is 16384. `contentHashMatch` is `false` -- unlike lighting and texturing, blending's raw output bytes do **not** match byte-for-byte across Mac and Windows. `combinedHashMatch` is also `false` (same manifest-level expectation as above). The concrete divergence numbers: `maxAbsDelta` is exactly `1.0` (one raw uint8 unit, out of a 0-255 range), `maxRelDelta` is `0.0078125` (= 1/128), `maxUlpDistance` is `1`. `percentExceedingThreshold` is `0.0` (still Phase 10's stub relative-threshold default, unrelated to `byteQuantMode`). `sizeMismatch` is `false`.

This is the phase's clearest confirmation of RENDTOL-01's SC2 hypothesis: blending's new `VkPipelineColorBlendAttachmentState` math (source/dest blend-factor combination) is genuinely floating-point-sensitive across GPU vendors/drivers in a way the trivial happy-path fixture never exercised. A `maxAbsDelta` of 1 raw byte is real, non-zero, captured cross-hardware divergence -- exactly the empirical signal Wave 5's `byteQuantMode` binary-search derivation (17-06/17-07) needs to search against for this fixture.

## Texturing Fixture

Full verbatim contents of `captures/diff-render-texturing.json` (Mac vs Windows):

```json
{
  "chunkDiffs": [],
  "chunkHashesMatch": [],
  "combinedHashMatch": false,
  "contentHashMatch": true,
  "elementCount": 16384,
  "elementType": "uint8",
  "maxAbsDelta": 0.0,
  "maxRelDelta": 0.0,
  "maxUlpDistance": 0,
  "percentExceedingThreshold": 0.0,
  "sizeMismatch": false
}
```

**Interpretation:** `elementCount` is 16384. `contentHashMatch` is `true` -- raw output bytes matched byte-for-byte across Mac and Windows, same pattern as lighting. `combinedHashMatch` is `false` (same manifest-level expectation). All numeric deltas (`maxAbsDelta`, `maxRelDelta`, `maxUlpDistance`, `percentExceedingThreshold`) are `0`. `chunkHashesMatch`/`chunkDiffs` empty, `sizeMismatch` is `false`.

Reported plainly: the new sampler/descriptor-set-layout infrastructure and `TEXTURE2_D` uniform path (D-05's largest-scope item) produced **zero measured cross-hardware divergence** on this dataset with the fixture's current `filter:nearest` sampling mode (17-04's SUMMARY notes the per-texture filter field is not yet functionally threaded through `UploadTexture()`, which always uses `NEAREST` regardless of the schema's declared value -- nearest-neighbor sampling has no interpolation math to diverge on, which plausibly explains this zero result more than a general property of texturing). This is a real finding, not a favorable rounding -- see "Zero-Divergence Flag" below.

## Zero-Divergence Flag (D-08 honest-gap handling)

Two of the three fixtures (lighting, texturing) measured **zero** cross-hardware divergence in this round, same as Phase 11's original trivial happy-path fixture. Per D-08's honesty bar (mirrored from VALD-01/`13-SCOPE-BOUNDARY.md`), this is flagged plainly rather than silently interpreted as either "the fixture doesn't stress floating-point behavior" or "the byte-identity claim generalizes":

- **Lighting:** GLSL Phong/Lambertian math (normals, light direction, dot products, `pow()`) is real floating-point computation, and DETV-02's guards (fixed shader precision, no unordered reduction, `VK_SAMPLE_COUNT_1_BIT`) were explicitly designed to constrain exactly this kind of divergence. A zero result is plausible under those guards, but it is not proof the guards generalize to all lighting models/parameter ranges -- it is the honest result for this specific fixture's specific inputs.
- **Texturing:** the observed zero result has a more concrete explanation available (nearest-neighbor sampling, per above) than lighting's does, but the fixture's filter field not being functionally wired end-to-end (17-04 finding) means this round's texturing result should not be read as "texturing generalizes safely" -- a future round with real bilinear/trilinear filtering wired through would need its own fresh capture, not an inference from this data.
- **Blending** is the one fixture in this round that did stress real cross-hardware floating-point divergence (`maxAbsDelta: 1`), confirming SC2's hypothesis is achievable with the right technique, even though it didn't happen to be all three techniques.

**No numbers were averaged, rounded, or omitted across the three fixtures.** Each fixture's `capture_diff` JSON output is reproduced verbatim above.

## Implications for Wave 5 (Tolerance Derivation, 17-06/17-07)

This is the empirical two-machine dataset Wave 5's `byteQuantMode` binary-search derivation must cite rather than a guessed value (satisfies this plan's key_link to 17-06/17-07):

- **Blending** has a real, non-zero raw divergence to search a tolerance against: `maxAbsDelta = 1.0` (`maxUlpDistance = 1`) on this dataset. Wave 5's binary search for blending's `byteQuantMode` should be justified against this number.
- **Lighting** and **texturing** measured zero divergence in this round. Wave 5 should not invent a non-zero `byteQuantMode` search target for either fixture where none was empirically observed -- per D-08, if no real divergence exists to derive a tolerance from, that absence must be documented honestly in Wave 5's own output rather than manufacturing a target number here. This document does not decide that question; it only reports what Round 1 measured.
- All three fixtures' `elementType` is `uint8`, `elementCount` is `16384` (128x128, larger than Phase 11's 256-element 16x16 happy-path fixture, consistent with these being non-trivial render targets), and `chunkHashesMatch`/`chunkDiffs` are empty arrays for all three (render fixtures have no chunking, matching Phase 11's own observation).
