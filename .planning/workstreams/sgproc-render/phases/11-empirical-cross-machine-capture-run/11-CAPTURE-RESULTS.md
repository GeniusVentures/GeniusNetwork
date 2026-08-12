---
phase: 11-empirical-cross-machine-capture-run
captured: 2026-08-11
status: 2-machine dataset (Mac + Windows)
---

# Phase 11: Empirical Cross-Machine Capture Run — Capture Results

**Phase Goal:** Real cross-hardware divergence statistics, gathered via Phase 10's `capture_harness`/`capture_diff` tooling with quantization still a no-op stub, written down in a form Phase 12's normalization design can cite directly.
**Captured:** 2026-08-11
**Status:** 2-machine dataset (Mac + Windows) — see Scope Decision below.

## Scope Decision

Phase 11 closes with **2 distinct real machines** — the user's Mac (`Fuus-Mac-mini.local---macOS`) and PC (`Mofu---Windows`) — not the 3 originally stated in the roadmap.

WSL was attempted as a candidate third machine. Its only available Vulkan device is `llvmpipe` (a Mesa software rasterizer, `type=CPU`) — not real hardware, and exactly the same software-Vulkan-ICD tier Phase 4's D-31 already excludes project-wide via `RenderProcessor::IsAcceptable()`'s device-type gate. Loosening `IsAcceptable()` to admit it was explicitly rejected as out of scope for this phase, because that gate is not phase-local — it affects `CanExecute()`, CI, and production everywhere, not just this one box.

This decision is recorded as D-01 (2-machine scope), D-02 (STATE.md's prior "get the third machine" operator instruction is stale, superseded by D-01), and D-03 (ROADMAP.md/REQUIREMENTS.md's literal "3 machines" wording must be reconciled) in `11-CONTEXT.md`.

## Dropped WSL/MNN Capture

A WSL/llvmpipe MNN-float capture (`xhw-mnn-float_Mofu---Linux_20260811T230448.cap`) was gathered ad hoc this session but is excluded from this phase's dataset entirely — it was not relocated into `captures/` and is not cited below as measured data.

Rationale (D-04): MNN has no device-type filter, so it silently ran on the same software rasterizer that `RenderProcessor::IsAcceptable()` already excludes project-wide for the render path. Comparing a software-rasterizer run against real GPU hardware would not be an apples-to-apples hardware comparison, so it does not belong in the 2-machine hardware dataset Phase 12's normalization design depends on. Its disposal (deletion) was left to executor discretion per D-09; it was deleted along with the rest of repo-root `caps/` once the surviving 6 files were relocated.

## Machines and Fixtures

Both surviving machines are identified using their exact `.cap`-filename labels:

- `Fuus-Mac-mini.local---macOS`
- `Mofu---Windows`

Both Phase 09 fixtures were captured on each machine:

- **MNN float32** (`xhw-mnn-float_*.cap`) — 512-element float32 tensor output
- **Render uint8** (`xhw-render_*.cap`) — 256-element uint8 RGBA/RGB pixel output

With WSL dropped, the complete pairwise diff set is exactly 1 diff per fixture (Mac vs Windows) — already produced and relocated into `captures/`: `diff-mnn-float.json`, `diff-render.json` (D-06). No further captures or diffs are needed to close this phase.

## MNN Float32 Fixture

Full verbatim contents of `captures/diff-mnn-float.json` (Mac vs Windows):

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
    false,
    false,
    false,
    false,
    false,
    false,
    false
  ],
  "combinedHashMatch": false,
  "contentHashMatch": false,
  "elementCount": 512,
  "elementType": "float32",
  "maxAbsDelta": 1.043081283569336e-07,
  "maxRelDelta": 7.269731577252969e-05,
  "maxUlpDistance": 768,
  "percentExceedingThreshold": 0.0,
  "sizeMismatch": false
}
```

**Interpretation:** `elementCount` is 512. Every one of the 15 `chunkHashesMatch` entries is `false`, and both `combinedHashMatch` and `contentHashMatch` are `false` — expected, since Phase 10/11's quantization is still a no-op stub, so this measures raw cross-hardware float divergence rather than a normalization failure. The concrete numbers Phase 12's normalization design should cite are:

- `maxAbsDelta`: approximately `1.043e-07` (exact: `1.043081283569336e-07`)
- `maxRelDelta`: approximately `7.27e-05` (exact: `7.269731577252969e-05`)
- `maxUlpDistance`: `768`
- `percentExceedingThreshold`: `0.0` (Phase 10's stub relative-threshold default — see "Implications for Phase 12" below)
- `sizeMismatch`: `false`

## Render Uint8 Fixture

Full verbatim contents of `captures/diff-render.json` (Mac vs Windows):

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

**Interpretation:** `elementCount` is 256. `contentHashMatch` is `true` — the raw output bytes matched byte-for-byte across Mac and Windows — alongside `combinedHashMatch` being `false`. This pairing is reported exactly as `capture_diff` structures it: two separate named booleans, not one flattened yes/no. This nuance is flagged here for Phase 12's attention without asserting an unverified explanation for why they diverge; resolving that mechanism is out of this phase's scope.

`chunkHashesMatch` is an empty array for this fixture (render has no chunking, only the trailing combined-level hash — consistent with Phase 10's own verification notes). `maxAbsDelta`, `maxRelDelta`, `maxUlpDistance`, and `percentExceedingThreshold` are all `0` — the raw pixel bytes are identical, consistent with `contentHashMatch: true`. `sizeMismatch` is `false`.

## Implications for Phase 12

This data is the empirical 2-machine dataset Phase 12's normalization design must cite rather than a guessed constant (satisfies QUANT-04):

- **MNN float32:** cross-hardware float divergence on real GPU hardware (Mac vs Windows) tops out at `maxAbsDelta ≈ 1.043e-07`, `maxRelDelta ≈ 7.27e-05`, `maxUlpDistance = 768`. These are the numbers Phase 12's chosen normalization technique (rounding, fixed-point conversion, bit-masking, or another approach) should be justified against.
- **Render uint8:** raw pixel bytes matched exactly across Mac and Windows (`contentHashMatch: true`, all numeric deltas `0`), yet `combinedHashMatch` is `false` — a nuance worth Phase 12's attention, not resolved here.
- The MNN float-side `percentExceedingThreshold` value recorded in the JSON (`0.0`) still uses Phase 10's stub relative-threshold default. Phase 12 will revisit that constant, not this document — this document only records what was measured under the current stub threshold.
