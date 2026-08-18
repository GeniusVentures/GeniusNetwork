# Phase 17: Render-Path Cross-Hardware Tolerance - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-18
**Phase:** 17-Render-Path Cross-Hardware Tolerance
**Areas discussed:** RENDTOL-02 scope framing, Fixture technique selection, Tolerance derivation methodology, Capture dataset, Fixture composition

---

## RENDTOL-02 scope framing

| Option | Description | Selected |
|--------|-------------|----------|
| Mechanism exists, just needs tuning + proof | Phase 14's `ResolveByteQuantMode`/`QuantizeByteBuffer` already wired to the render call site; phase's real work is deriving a real N + counter-test | ✓ |
| Treat it as if no mechanism exists yet | Re-verify from scratch as if Phase 14 hadn't already wired this in | |

**User's choice:** Mechanism exists, just needs tuning + proof (recommended option accepted as-is).
**Notes:** Confirmed via direct scout of `quantization.hpp/cpp` and `processing_processor_render.cpp:2096,2209` before asking — the mechanism was already live, just unconfigured (falls back to N=0).

---

## Fixture technique selection

| Option | Description | Selected |
|--------|-------------|----------|
| Lighting math only | Phong/Lambertian shader math, zero RenderProcessor/schema changes | |
| Add blending support | New schema field + pipeline color-blend wiring | |
| Add texture-sampling support | New sampler/descriptor infrastructure — largest scope | |
| Combine lighting + one other technique | e.g. lighting + blending together | |

**User's choice:** "I feel like we should support as many types of rendering as reasonable, so maybe all." (free text, interpreted as: texturing + blending + lighting, all three)
**Notes:** MSAA was flagged as architecturally hard-blocked (DETV-02) regardless of this choice and stays excluded. User's answer expanded scope beyond all four listed options — captured as D-02 in CONTEXT.md, with the real implementation-size differences between the three techniques (D-05) made explicit as a tradeoff, not silently absorbed.

---

## Fixture composition (follow-up)

| Option | Description | Selected |
|--------|-------------|----------|
| One combined fixture | Single render pass/shader doing texturing + lighting + blending together | |
| Separate fixtures per technique | Three distinct fixture JSONs, each with its own capture/diff/tolerance cycle | ✓ |

**User's choice:** Separate fixtures per technique.
**Notes:** Asked as a direct follow-up once "all three techniques" was confirmed, since combined-vs-separate has real empirical-workload implications (1x vs 3x capture/tuning cycles per D-06/D-07).

---

## Tolerance derivation methodology

| Option | Description | Selected |
|--------|-------------|----------|
| Binary-search N against the new SECV counter-test | Same discipline as Phase 14's D-10 tex3d derivation | ✓ |
| Pick N from raw captured delta magnitude only | Faster, less empirically rigorous | |
| Try a fixed small N first, escalate only if it fails | Biases toward tightest tolerance | |

**User's choice:** Binary-search N against the new SECV counter-test (recommended option accepted as-is).
**Notes:** Adapted in CONTEXT.md D-06 to `byteQuantMode`'s discrete `[0,8]` range (9 values) rather than a continuous power-of-two scale, since that's a real mechanical difference from Phase 14's float-path precedent.

---

## Capture dataset

| Option | Description | Selected |
|--------|-------------|----------|
| Same 2 machines as Phase 11 | Mac mini + Windows (Mofu), no new hardware | ✓ |
| A third real machine is now available | Would change SC2/SC4's evidence base | |

**User's choice:** Same 2 machines as Phase 11 (recommended option accepted as-is).
**Notes:** No new hardware surfaced during discussion; Phase 11's WSL/llvmpipe exclusion rationale still applies unchanged.

---

## Claude's Discretion

- Exact new `pipeline_state` schema field name(s)/shape for blend state
- Exact new schema mechanism for declaring a sampled-image render input (descriptor-set-layout shape, sampler creation parameters)
- Exact GLSL lighting model (Phong vs. Lambertian-only) and uniform naming
- Exact new counter-test file names (mirroring `secv01_tex3d_counter_test.cpp`'s naming convention)
- Whether/when to correct ROADMAP.md's Phase 17 Success Criteria wording (currently written around "a fixture," singular) to reflect three fixtures
- Whether the three fixtures ship in one wave or are sequenced across waves

## Deferred Ideas

- **MSAA as a fixture technique** — architecturally hard-blocked by DETV-02 (Phase 3's locked determinism decision, `VK_SAMPLE_COUNT_1_BIT` unconditional). Not reopened.
- **Combining all three techniques into one fixture** — considered via the Fixture Composition question, not chosen.
