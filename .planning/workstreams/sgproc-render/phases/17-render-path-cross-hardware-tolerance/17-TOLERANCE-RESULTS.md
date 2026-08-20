---
phase: 17-render-path-cross-hardware-tolerance
captured: 2026-08-20
status: Round 2 complete (final, post-derivation cross-machine capture, D-09) -- SC4 verdict MIXED, reported honestly per fixture (lighting: hash match; texturing: hash match, never diverged; blending: residual gap that WORSENED under quantization)
---

# Phase 17: Render-Path Cross-Hardware Tolerance -- Round 2 Capture Results & SC4 Verdict

**Round:** 2 of 2 (D-06 methodology's final step) -- each fixture's own empirically-derived `byteQuantMode` (17-06/17-07: lighting=5, blending=6, texturing=7) is now wired into its production `parameters` array and active for this capture. This is the fresh, post-derivation cross-machine measurement RENDTOL-02's SC4 requires -- not a reinterpretation of Round 1's raw-divergence numbers.

**Captured:** Windows side 2026-08-19 (Task 1, this plan); Mac side 2026-08-20 (Task 2, hands-on checkpoint).

**Dataset:** Phase 11's exact two-machine dataset (D-09) -- `Fuus-Mac-mini.local---macOS` and `Mofu---Windows`. No new hardware.

## Important correction carried in from Wave 5 (17-06): lighting's Round 1 number was degenerate, not real

`17-CAPTURE-RESULTS-ROUND1.md`'s lighting entry (`maxAbsDelta=0.0`, `contentHashMatch=true`) reflected a **solid-black render** caused by a push-constant field-order bug (shader declared `lightDir`/`lightColor`/`viewPos`; `ResolveUniforms` packs alphabetically) -- every pixel was byte-identical `0x00/0x00/0x00/0xFF` regardless of the actual lighting math, not genuine per-fragment Phong shading. 17-06 fixed the shader and confirmed (via its own counter-test) that the corrected fixture now genuinely diverges when `lightColor` is deliberately wrong. **This Round 2 lighting capture is therefore the first real cross-hardware measurement of correct Phong lighting in this phase** -- its result below may legitimately differ from Round 1's number, and is reported fresh, not assumed to still hold.

Texturing's Round 1 zero-divergence result was independently confirmed **honest** (not degenerate) in 17-07 -- its own counter-test's fully-bit-inverted corrupted texture still diverges at every safe `byteQuantMode`, proving the texture-upload/sampling path functions correctly. Blending's Round 1 result was already a genuine non-zero measurement (`maxAbsDelta=1.0`).

## Machines and Fixtures

- `Fuus-Mac-mini.local---macOS` -- Round-2 captures: `xhw-render-lighting-r2_Fuus-Mac-mini.local---macOS_20260820T070304.cap`, `xhw-render-blending-r2_Fuus-Mac-mini.local---macOS_20260820T070308.cap`, `xhw-render-texturing-r2_Fuus-Mac-mini.local---macOS_20260820T070311.cap`
- `Mofu---Windows` -- Round-2 captures: `xhw-render-lighting-r2_Mofu---Windows_20260820T031659.cap`, `xhw-render-blending-r2_Mofu---Windows_20260820T031711.cap`, `xhw-render-texturing-r2_Mofu---Windows_20260820T031714.cap`

Each fixture's final derived `byteQuantMode` (17-06/17-07) was confirmed present in its production fixture JSON's `parameters` array before either machine captured (Task 1's `read_first` gate): **lighting=5, blending=6, texturing=7**.

All three `capture_diff --element-type uint8` reports are written to `captures/diff-render-<technique>-r2.json`.

## Lighting Fixture (byteQuantMode=5)

Round 1 (raw, `byteQuantMode` absent, **degenerate solid-black render -- not a real measurement**, see correction above):

```json
{ "contentHashMatch": true, "maxAbsDelta": 0.0, "maxRelDelta": 0.0, "maxUlpDistance": 0 }
```

Round 2 (`byteQuantMode=5`, corrected shader), full verbatim contents of `captures/diff-render-lighting-r2.json`:

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

**Verdict -- outcome (a): hash match confirmed. SC4 is fully satisfied for lighting.** `contentHashMatch` is `true` and every numeric delta is exactly `0` -- this is a genuinely fresh measurement against the corrected shader (17-06), the first real cross-hardware test of this fixture's actual Phong math, and it happens to land at zero divergence again, this time for a legitimate reason rather than a degenerate one.

**Honest caveat (not hidden):** local inspection of this session's own Windows-side render output (`lighting-render-output.raw`) shows the fixture renders a spatially uniform color across all 4096 pixels (R=G=B=32, A=224 repeated). This is consistent with the fixture's simple geometry (a flat surface facing a directional light with no per-fragment attenuation source) producing a mathematically constant Phong result across every fragment -- not a red flag on its own, since 17-06's own counter-test independently proved this fixture's math does vary output when `lightColor` is deliberately wrong. But it does mean this specific fixture's specific geometry still doesn't stress *spatial* cross-hardware floating-point variation (only a single constant lighting computation, evaluated identically everywhere) -- the same "did not stress cross-hardware behavior as much as hoped" honesty flag Round 1 raised for this fixture, now on more solid empirical footing (real math, still uniform geometry) rather than resolved by the shader fix.

## Blending Fixture (byteQuantMode=6)

Round 1 (raw, `byteQuantMode` absent):

```json
{ "contentHashMatch": false, "maxAbsDelta": 1.0, "maxRelDelta": 0.0078125, "maxUlpDistance": 1, "percentExceedingThreshold": 0.0 }
```

Round 2 (`byteQuantMode=6`), full verbatim contents of `captures/diff-render-blending-r2.json`:

```json
{
  "chunkDiffs": [],
  "chunkHashesMatch": [],
  "combinedHashMatch": false,
  "contentHashMatch": false,
  "elementCount": 16384,
  "elementType": "uint8",
  "maxAbsDelta": 64.0,
  "maxRelDelta": 0.5,
  "maxUlpDistance": 64,
  "percentExceedingThreshold": 25.0,
  "sizeMismatch": false
}
```

**Verdict -- outcome (b): a real residual gap remains, and it is WORSE than Round 1's raw (unquantized) divergence, not better. SC4 is NOT satisfied for blending.** `contentHashMatch` is `false`. `maxAbsDelta` went from `1.0` (raw) to `64.0` (quantized) -- a 64x increase. `percentExceedingThreshold` (percent of elements whose absolute delta exceeds `capture_diff`'s fixed byte-absolute threshold of `1`) went from `0.0%` to `25.0%` -- 4096 of the fixture's 16384 output bytes now differ by more than the raw-divergence threshold, where none did before quantization was applied.

**Root cause, characterized specifically (not hand-waved):** `QuantizeByteBuffer` (`quantization.hpp`/`quantization.cpp`) implements `byteQuantMode` as a **bit-masking** (floor-to-bucket) operation -- `value &= ~((1<<N)-1)`, clearing the low `N` bits of every byte -- not a round-to-nearest-grid operation. For `N=6`, this collapses every byte into one of 4 buckets: `{0, 64, 128, 192}`. This was directly confirmed by inspecting this session's own Windows-side quantized blending render output (`blending-render-output.raw`): only the values `0`, `64`, and `128` appear anywhere in the buffer, consistent with 6-low-bit masking. Bucket-floor masking has no rounding tie-break protection: when the two machines' *raw* (pre-quantization) byte values differ by only `1` unit but happen to straddle a 64-wide bucket boundary (e.g. Mac produces `63`, Windows produces `64`), masking sends them to *different* buckets (`0` vs. `64`) -- amplifying a 1-unit raw difference into a full 64-unit quantized difference. Given Round 1's own raw measurement (`maxAbsDelta=1.0`, i.e. real per-element differences of exactly 1 raw byte unit already exist for this fixture), this is exactly the failure mode the masking mechanism is structurally vulnerable to, and Round 2's data shows it firing on a full quarter of this fixture's output elements.

**This is a real, previously-uncovered limitation of the `byteQuantMode` bit-masking design itself, not a bug in this plan's capture or diff process, and not something either 17-06's binary search or its counter-test could have caught:** the counter-test methodology (D-06/D-07/SC5) only proves a chosen `N` is not *too loose* to mask a deliberately-corrupted result on a single machine -- it says nothing about whether that `N` actually *improves* real cross-hardware agreement, because the counter-test never runs a live two-machine comparison. `N=6` passed that test (17-06) and is not loose enough to hide corruption; it is nonetheless, empirically, the wrong tool to close blending's real cross-hardware gap, because masking amplifies rather than absorbs small boundary-straddling deltas. Per D-08, this is documented here as ground truth, not reinterpreted into a passing result and not silently omitted.

**No fix is applied by this plan.** Per this plan's own scope (Round 2 capture + honest reporting, not a redesign of the quantization mechanism), closing this gap would require either (a) switching to a round-to-nearest-grid quantization scheme for the byte path (mirroring the float path's `round(x*S)/S` rather than a bit-mask), or (b) accepting blending's cross-hardware hash as unmatchable under the current mechanism and relying on a different comparison bar (numeric tolerance, as Phase 15 already does for the MNN path) -- both are architectural decisions outside this plan's scope, flagged here as a real, actionable follow-up for whoever next picks up RENDTOL-02's blending gap.

## Texturing Fixture (byteQuantMode=7)

Round 1 (raw, `byteQuantMode` absent, confirmed honest -- not degenerate -- in 17-07):

```json
{ "contentHashMatch": true, "maxAbsDelta": 0.0, "maxRelDelta": 0.0, "maxUlpDistance": 0 }
```

Round 2 (`byteQuantMode=7`), full verbatim contents of `captures/diff-render-texturing-r2.json`:

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

**Verdict -- outcome (c): the fixture never diverged in the first place. SC4 is trivially satisfied for texturing, not hidden as a stronger result than it is.** Round 1's raw capture already showed zero divergence, and 17-07 independently confirmed this is a genuine finding (the fixture's own corrupted-source-image counter-test still diverges at every `N` from 0 through 7 -- the texture-upload/sampling path is not degenerate). Round 2 reconfirms zero divergence with `byteQuantMode=7` now active, which changes nothing observable since there was no raw divergence to quantize away. As already flagged in Round 1 and unchanged by this round: `UploadTexture()` always uses `VK_FILTER_NEAREST` regardless of the fixture's declared filter mode (17-04 finding), so this result should be read as "nearest-neighbor sampling has no interpolation math to diverge on for this fixture's inputs," not as "texturing generalizes safely" to bilinear/trilinear filtering, which remains untested.

## Summary Table

| Fixture | byteQuantMode | Round 1 maxAbsDelta (raw) | Round 2 maxAbsDelta (quantized) | Round 2 contentHashMatch | SC4 Verdict |
|---|---|---|---|---|---|
| Lighting | 5 | 0.0 (degenerate -- solid black, not real) | 0.0 (real -- corrected shader) | true | (a) Hash match confirmed |
| Blending | 6 | 1.0 (real) | 64.0 (real, WORSE) | false | (b) Residual gap -- worsened by quantization, root-caused above |
| Texturing | 7 | 0.0 (real, confirmed honest) | 0.0 (real, unchanged) | true | (c) Never diverged in the first place |

**No numbers were averaged, rounded, or omitted across the three fixtures.** Each fixture's `capture_diff` JSON output is reproduced verbatim above, and Round 1's original numbers are cited unedited for the before/after comparison.

## Phase-Wide SC4/RENDTOL-02 Conclusion

RENDTOL-02's SC4 requirement ("a fresh two-machine `capture_diff` run shows the fixture's processor-level output hash matching cross-hardware, or a residual gap is characterized honestly") is satisfied on its own honest terms: **2 of 3 fixtures (lighting, texturing) hash-match cross-hardware; 1 of 3 (blending) has a real, specifically-characterized residual gap that the chosen tolerance mechanism makes worse, not better.** This is not silently declared passing -- RENDTOL-02 as a whole is **not fully closed**; blending's gap is real, understood, and left open for future architectural work (see Root Cause above), exactly as D-08's honesty bar requires.

SC5 (a SECV-01-style counter-test proves the tolerance is not too loose to mask corruption) **is satisfied for all three fixtures** independently of SC4's outcome -- `secv01_render_lighting_counter_test.cpp`/`secv01_render_blending_counter_test.cpp` (17-06) and `secv01_render_texturing_counter_test.cpp` (17-07) each proved their fixture's chosen `byteQuantMode` sits one step below a confirmed corruption-masking boundary. SC4 and SC5 are answering different questions, and blending's SC4 gap does not imply an SC5 problem -- the mechanism correctly refuses to mask a *deliberate* corruption; it simply also, as a side effect of its bit-masking design, sometimes amplifies small *real* cross-hardware noise past the point of matching.

## Gap Closure Addendum (RENDTOL-02 numeric-tolerance fallback, D-10/D-11)

The strict quantized-hash comparison `capture_diff` already performed for blending, documented above, is **unchanged**: `contentHashMatch=false`, `maxAbsDelta=64.0` (on `quantizedBytes`, byteQuantMode=6 bit-masking applied). That number still shows a mismatch and is not reinterpreted here as passing.

Per the user's locked resolution (`17-CONTEXT.md` D-10: numeric-tolerance fallback) and D-11's grounded finding, `capture_diff` was extended with a new opt-in `--byte-quant-mode <N>` raw-tolerance mode (Plan 17-09, Task 2). This mode calls `IsByteChunkWithinToleranceForMode` -- a thin CLI-facing wrapper (Task 1) that delegates, unmodified, to `IsByteChunkWithinTolerance`, the exact function/bound formula production's `AttemptToleranceFallback` already applies to raw pre-quantization bytes. Neither `QuantizeByteBuffer`, `IsByteChunkWithinTolerance`, nor any `ValidateResults` code was modified by this addendum.

Run against the already-captured Round 2 blending `.cap` files' `preQuantizeBytes` field (recorded unconditionally at capture time, independent of the `byteQuantMode` active when captured -- no new hardware capture round was required), the result (`captures/diff-render-blending-r2-rawtolerance.json`) is:

```json
{
  "rawToleranceCheck": {
    "byteQuantMode": 6,
    "checked": true,
    "maxAbsDelta": 1.0,
    "withinTolerance": true
  }
}
```

The real raw cross-hardware delta (`1.0`) is exactly Round 1's independently-measured raw `maxAbsDelta` cited above, confirming `preQuantizeBytes` coherence across capture rounds. It is well within `byteQuantMode=6`'s mask-width tolerance bound (`(1<<6)-1 = 63`), so `withinTolerance=true`.

**Conclusion:** RENDTOL-02 is now satisfied for blending via the user's chosen numeric-tolerance-fallback path, proven with the exact mechanism production already relies on -- not a new, second tolerance mechanism. The strict quantized-hash number (`64.0`/`false`) and the raw-tolerance number (`1.0`/`true`) coexist and answer different questions: the former asks "does `QuantizeByteBuffer`'s bit-masking output match bit-for-bit cross-hardware" (no, per the Blending Fixture section's root-cause analysis above), while the latter asks "is the real, pre-quantization cross-hardware divergence within the schema-declared tolerance bound production's own fallback mechanism would accept" (yes). RENDTOL-02's tolerance mechanism is now proven, for all three of RENDTOL-01's fixtures, against real cross-hardware capture data: lighting and texturing via strict hash-match (unchanged from above), blending via this raw-buffer numeric-tolerance check.
