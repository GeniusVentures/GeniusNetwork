# Phase 14: Configurable Normalization Precision - Context

**Gathered:** 2026-08-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 14 makes SGProcessingManager's per-data-type normalization precision schema-configurable, replacing v2.1's single hardcoded `kScale` (S=2^15 for float32) and always-no-op byte path. A job schema declares its own precision via the existing generic `parameters` array; jobs that declare nothing keep v2.1's exact current behavior (additive, not breaking). The `tex3d`/`spleen_ct_seg` real workload — which showed all 25 chunk hashes mismatching cross-hardware at a divergence ~2-3 orders of magnitude larger than v2.1's tiny float fixture — gets its own empirically-derived value, plus (per this discussion) its own security counter-test proving that coarser precision still catches a genuinely corrupted result.

This phase does not touch `ProcessingValidationCore::ValidateResults`, the concatenation bug, or any numeric-tolerance comparison mechanism — that is Phase 15's scope (XNODE-01b, XNODE-02, SECV-02). Phase 14 is exclusively about how precision is declared and applied at quantization time, not how results are later compared.

</domain>

<decisions>
## Implementation Decisions

### Schema declaration mechanism
- **D-01:** Reuse the existing generic `parameters` array — no changes to `gnus-processing-schema.json` or the quicktype-generated headers. Mirrors the exact find-by-name-in-`parameters` convention `processing_processor_mnn_volume.cpp`'s `ParseLayout` already uses for `layout`/`volumeLayout`. Rejected: adding a new formal schema field, since it would require a quicktype regen across every consumer and REQUIREMENTS.md doesn't ask for a schema redesign.
- **D-02:** Parameter key names are `quantScale` (float32 path) and `byteQuantMode` (uint8 path) — distinct, type-specific names, not one shared key.

### Value semantics & bad input
- **D-03:** `quantScale` declares the raw scale `S` directly (not a grid-step/epsilon the code converts). Same `round(x * S) / S` formula Phase 12/13 already established — only `S` becomes a schema-declarable variable instead of a compile-time constant; the technique itself is not reopened.
- **D-04:** Any invalid declared `quantScale` (non-numeric, zero/negative, or not a power-of-two) silently falls back to v2.1's `S=2^15` constant — no warning logged, no job rejection. Same silent-fallback spirit as `ParseLayout`'s handling of an unrecognized value.
- **D-05:** "Must be a power-of-two" is an enforced code check, not just documented guidance — the config-resolution path validates the declared `S` is a positive power-of-two before using it; anything else triggers the same D-04 fallback. Guarantees the exact float round-trip property Phase 12's D-03 relies on can never be silently violated by a bad schema value.

### Byte-path technique
- **D-06:** `byteQuantMode` uses bit-masking of the low N bits (`value &= ~((1<<N)-1)`), not a scale-round-cast analog of the float path. No existing byte-divergence fixture data justifies porting the float technique verbatim; bit-masking is the cheaper, more directly analogous "coarsen the grid" operation for an integer byte value.
- **D-07:** `byteQuantMode`'s declared value literally is `N` (number of low bits to mask). `N=0` or absent is exactly today's byte-identity no-op — satisfies QUANT-CFG-02's additive requirement by construction, no separate on/off flag needed.
- **D-08:** Invalid `byteQuantMode` (negative, `N>8`, non-numeric) falls back to `N=0` (byte-identity) — same silent-fallback pattern as D-04/D-05.

### tex3d/spleen_ct_seg's value & security coverage
- **D-09:** Phase 14 adds a **new** SECV-01-style corrupted-model counter-test specifically for tex3d/spleen_ct_seg's own (much coarser) precision. The existing `secv01_counter_test.cpp` only exercises the small MNN float fixture at `S=2^15` — it does not prove a substantially coarser grid (~`S=2^7`-`2^8`) still catches a genuinely corrupted result. This goes beyond REQUIREMENTS.md's literal QUANT-CFG-01/02/03 wording, but stays within this phase's own tex3d-precision deliverable (mirrors QUANT-CFG-03's explicit "mirrors QUANT-04's empirical-derivation discipline" framing) — not scope creep into unrelated work.
- **D-10:** tex3d's actual `quantScale` value is derived via the same binary-search-against-a-counter-test methodology Phase 12/13 already used for the small model (`13-04-PLAN.md`'s process): start from the STATE.md estimate (~`S=2^7`-`2^8`, since the measured real delta `0.005126953125` is ~168x the current `S=2^15` grid step of `3.0517578125e-05`), binary-search power-of-two `S` values against the new D-09 counter-test, and pick the widest `S` that still passes with one power-of-two step of margin above the first confirmed failure boundary — identical discipline to how `S=2^15` was chosen for the small model.

### Claude's Discretion
- Exact mechanism for threading the resolved `S`/`N` value into `QuantizeFloatBuffer`/`QuantizeByteBuffer` (new function parameter, overload, or a small resolver invoked at each of the ~20 existing call sites before the unchanged function call) — left to research/planning.
- Exact file/test names for the new tex3d SECV counter-test — follow whatever convention `secv01_counter_test.cpp` already established.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & Roadmap
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` — QUANT-CFG-01/02/03, the locked requirements for this phase
- `.planning/workstreams/sgproc-render/ROADMAP.md` (Phase 14 section) — goal, SC1-SC4

### Prior Phase Context (source of the technique/pattern this phase extends)
- `.planning/workstreams/sgproc-render/phases/12-quantization-normalization-implementation/12-CONTEXT.md` — D-03 (`round(x*S)/S` technique, kept unchanged by this phase), D-06 through D-09 (IEEE-754 canonicalization, untouched — always runs regardless of configured S), D-01 (byte-identity no-op reasoning this phase's D-06/D-07 reopen)
- `.planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/13-CONTEXT.md` — the S=2^15 binary-search-against-SECV-01 methodology this phase's D-10 replicates for tex3d
- `.planning/workstreams/sgproc-render/STATE.md` — "New evidence for QUANT-CFG-01" paragraph: the real captured tex3d/spleen_ct_seg divergence data (all 25 chunk hashes mismatch, delta `0.005126953125` = 168x current grid step, ~2-3 orders of magnitude bigger than the float fixture) that D-10 is grounded in. Also documents a semantic/Dice-overlap correctness-bar nuance relevant to Phase 15, not this phase's scope.

### Existing Code (Source of Truth)
- `SuperGenius/SGProcessingManager/include/util/quantization.hpp`, `src/util/quantization.cpp` — the current hardcoded-`S=2^15` float implementation and byte-identity no-op this phase makes configurable
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_volume.cpp:40-71` — `ParseLayout`, the exact find-by-name-in-`parameters` convention D-01/D-02 replicate
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp:2207` — `QuantizeByteBuffer`'s single call site (render path); `~865-873` — `ResolveUniforms`'s existing parameter-lookup-by-name pattern
- `SuperGenius/SGProcessingManager/gnus-processing-schema.json:56-62,123-152` — the existing generic `parameters`/`parameter` schema definitions (type float/int/bool/string/uri/array/object, default, constraints with min/max/enum/pattern) that D-01 reuses as-is; no schema edits needed
- `SuperGenius/SGProcessingManager/generated/Parameter.hpp` — the quicktype-generated accessor API (`get_name()`, `get_parameter_default()` returning `nlohmann::json`, `get_type()`) every lookup uses
- `SuperGenius/test/src/processing_datatypes/texture3d-processing-definition.json` — the existing tex3d/spleen_ct_seg job definition fixture this phase's D-09/D-10 configure with a `quantScale` parameter entry
- `SuperGenius/test/src/processing_conformance_security/secv01_counter_test.cpp` (Phase 12) — the existing corrupted-MNN-model methodology D-09's new tex3d counter-test replicates
- `SuperGenius/SGProcessingManager/test/util/quantization_test.cpp` — existing unit test structure/conventions for `QuantizeFloatBuffer`/`QuantizeByteBuffer`; this phase's new fallback/config-path tests extend it rather than starting a new file
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_float.cpp` — currently `(void)parameters;`-ignores the parameter it already receives; representative of most of the 20 existing `QuantizeFloatBuffer` call sites across 14 processor files that need the new lookup wired in

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ParseLayout`-style find-by-name-in-`parameters` lookup (`processing_processor_mnn_volume.cpp`) — direct template for the new `quantScale`/`byteQuantMode` lookup helper
- Existing `quantization_test.cpp` structure — extend with new fallback/config-path test cases rather than a new test file
- Existing `secv01_counter_test.cpp` corrupted-model methodology — direct template for the new tex3d-specific counter-test (D-09)

### Established Patterns
- Quantize-then-capture-then-hash ordering at each of the ~20 already-wired call sites (Phase 10) — unaffected; only the `S`/`N` value fed into the existing calls becomes variable
- IEEE-754 canonicalization branch order (denormal/NaN/Inf/zero checked before rounding, Phase 12 D-06 through D-09) — untouched, always runs regardless of configured `S`
- Binary-search-against-a-counter-test methodology for choosing `S` (Phase 13's exact process, `13-04-PLAN.md`) — reused verbatim for tex3d's own value (D-10)

### Integration Points
- `QuantizeFloatBuffer`/`QuantizeByteBuffer` signatures currently take no configuration argument at all — need a way to receive the resolved `S`/`N` value; exact threading mechanism is Claude's Discretion above, not decided here
- 20 existing call sites across 14 processor files (all already receive `parameters` via their `StartProcessing` signature; several currently `(void)parameters;` no-op it) — each needs the new `quantScale`/`byteQuantMode` lookup wired in
- `texture3d-processing-definition.json` needs a `quantScale` entry added to its `parameters` array once D-10's binary search produces a final value

</code_context>

<specifics>
## Specific Ideas

- STATE.md's tex3d finding: `spleen_ct_seg` via `processing_processor_mnn_volume.cpp`, all 25 chunk hashes mismatching Mac vs Windows, delta `0.005126953125` = exactly 168x the current `S=2^15` (`3.0517578125e-05`) grid step
- STATE.md's own estimated tex3d `S` range: ~`2^7`-`2^8`, to be confirmed via D-10's binary search against the new D-09 counter-test
- Locked parameter names: `quantScale` (float, raw power-of-two `S`), `byteQuantMode` (uint8, integer `N` low-bits-to-mask)

</specifics>

<deferred>
## Deferred Ideas

- **Relative/ULP-based (mantissa-bit-masking) quantization technique for the float path** — still not chosen; Phase 12's own deferred item stands unchanged. This phase makes the existing absolute-epsilon technique's `S` configurable, it does not reopen the technique choice itself.
- **Scale-round-cast analog for the byte path** — considered during this discussion, not chosen (D-06 picked bit-masking instead). Could be revisited if a future byte fixture's real divergence data shows bit-masking doesn't generalize.
- **New formal schema field / quicktype schema changes for precision declaration** — considered, not chosen (D-01 reuses the generic `parameters` array instead).
- **Modifying `ComputeManifestHash`/`ExecutionManifest` for a cross-machine-comparable manifest-level hash** — reaffirmed out of scope again (same recurring deferred item from Phase 12/13), unrelated to this phase's precision work.
- **Actual cross-node consensus/redundant-execution plumbing (XNODE-01c)** — explicitly out of scope per REQUIREMENTS.md, unrelated to this phase.

### None further — discussion stayed within phase scope

</deferred>

---

*Phase: 14-Configurable Normalization Precision*
*Context gathered: 2026-08-13*
