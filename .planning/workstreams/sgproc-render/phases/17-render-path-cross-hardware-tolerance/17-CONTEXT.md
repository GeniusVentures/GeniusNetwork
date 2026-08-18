# Phase 17: Render-Path Cross-Hardware Tolerance - Context

**Gathered:** 2026-08-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 17 closes the untested risk STATE.md flagged: the render path's byte-identity claim was only ever measured against `render-pass-happy-path-definition.json`, an 8x8 solid-color, zero-computation fixture. This phase delivers three new non-trivial render fixtures (texturing, blending, lighting — one technique each, not combined) that actually exercise floating-point-heavy render computation, empirically captures real cross-hardware divergence on each via `capture_harness` (mirroring Phase 11's two-machine dataset), and derives/proves a real tolerance value for each fixture using the schema-configurable byte-quantization mechanism that already exists.

**Scope-narrowing finding (mirrors Phase 16's ARTF-07/08 reframe):** ROADMAP.md's Phase 17 wording ("replacing `QuantizeByteBuffer`'s current byte-identity no-op") is stale. Phase 14 already added a schema-configurable `byteQuantMode` bit-masking mechanism to `QuantizeByteBuffer` (`ResolveByteQuantMode`), already wired into the render call site (`processing_processor_render.cpp:2096,2209`). It currently falls back to `N=0` (identity) only because no job has ever declared a non-default `byteQuantMode` — not because the mechanism doesn't exist. **RENDTOL-02's real remaining work is deriving real non-zero `N` value(s) from this phase's own empirical data and proving via a new counter-test that each `N` isn't loose enough to mask corruption — not building a new mechanism from scratch.**

**Scope expansion (explicit user choice, confirmed as real added scope beyond the roadmap's "nothing beyond already-shipped foundations" framing):** the fixture work covers all three floating-point-heavy techniques the roadmap named as alternatives (texturing, blending, lighting) rather than picking one, as three separate fixtures. MSAA remains out of scope — see D-03.

**Depends on:** Nothing beyond already-shipped foundations for the byte-quant mechanism itself (Phase 14) and the capture/diff tooling (Phase 10) — but texturing and blending fixtures require genuinely new `RenderProcessor`/schema work this phase must do, not reuse. Independent of Phases 16, 18, 19.

</domain>

<decisions>
## Implementation Decisions

### RENDTOL-02 reframe
- **D-01:** The byte-quantization tolerance mechanism (`ResolveByteQuantMode`/`QuantizeByteBuffer`) already exists (Phase 14) and is already wired into the render path's call site. Phase 17 does not build a new mechanism — it (a) derives real `byteQuantMode` value(s) from this phase's own fixtures' empirical cross-hardware capture data, and (b) proves via a new counter-test that each derived value still catches a deliberately wrong/corrupted result (SC5). Confirmed explicitly by the user over the alternative of re-verifying the mechanism from scratch.

### Fixture technique selection
- **D-02:** All three roadmap-named techniques are in scope — texturing, blending, and lighting — not just one. User's explicit reasoning: "support as many types of rendering as reasonable."
- **D-03:** MSAA is excluded and stays excluded — not a user preference, an architectural hard-block. `processing_processor_render.cpp:1526` hardcodes `VkPipelineMultisampleStateCreateInfo::rasterizationSamples = VK_SAMPLE_COUNT_1_BIT` with the comment "ALWAYS -- DETV-02, never configurable" — a locked Phase 3 determinism decision (DETV-02, see `03-CONTEXT.md`/`03-RESEARCH.md`). This phase does not reopen DETV-02.
- **D-04:** The three techniques land as **separate fixtures**, not one combined fixture. User's explicit choice over combining all three into a single render pass/shader — trades more empirical/tuning overhead (independent `capture_harness`/tolerance-derivation work per fixture) for isolation (each technique's divergence and tolerance is independently attributable, not conflated).
- **D-05:** Per-technique implementation scope differs significantly, and research/planning must treat them as different-sized work items, not three equivalent tasks:
  - **Lighting** — zero `RenderProcessor` C++ or schema changes. Pure GLSL fragment-shader math (e.g. Phong/Lambertian: normals, light direction, dot products, `pow()` for specular) using uniform types already supported end-to-end (`VEC3`/`VEC4`/`MAT4` all already handled by `ResolveUniforms`, `processing_processor_render.cpp:760-799`).
  - **Blending** — needs a new `pipeline_state` schema field (or fields) plus real `VkPipelineColorBlendAttachmentState` wiring in `BuildPipeline()`. Currently hardcoded: `colorBlendAttachment.blendEnable = VK_FALSE` (`processing_processor_render.cpp:1531`), and `pipeline_state`'s schema definition (`gnus-processing-schema.json:549-574`) is explicitly documented as a "curated, minimal v1 fixed-function pipeline state subset (D-13)" with no blend field at all — this phase deliberately extends that curated set.
  - **Texturing** — the largest of the three: `RenderProcessor` currently has **zero** sampler/descriptor infrastructure for texture uniforms. `ResolveUniforms`'s dispatch explicitly rejects `TEXTURE1_D`/`TEXTURE2_D`/`TEXTURE3_D`/`TEXTURE_CUBE` uniform types (`processing_processor_render.cpp:800-809`, falls through to `return false`) — no `VkSampler`/`VkImageView` creation, no combined-image-sampler descriptor-set-layout entry, no image-upload path for a sampled input exists on the render side today (the schema's texture types are currently only consumed by MNN volume/texture processors, unrelated to render passes). This is genuinely new infrastructure, not a fixture-only change.

### Tolerance derivation methodology
- **D-06:** Each fixture's `byteQuantMode` value is derived independently via the same binary-search-against-a-counter-test discipline Phase 14's D-10 used for tex3d's `quantScale` — search the valid range, pick a value with one step of margin above the confirmed SECV-failure boundary. Adapted detail: `byteQuantMode` is a discrete `[0,8]` bit-count (9 possible values), not a continuous power-of-two float scale, so "one step of margin" means one integer step in `[0,8]`, not one power-of-two step.
- **D-07:** Each fixture gets its own independent tolerance value and its own new counter-test (mirrors `secv01_tex3d_counter_test.cpp`'s precedent of a dedicated file per newly-tuned fixture, not reusing/parameterizing the existing trivial-fixture `RenderWrongShaderConstantStillDiverges` test in `secv01_counter_test.cpp`). This falls out naturally from `byteQuantMode` being declared per-job via the existing generic `parameters` array (Phase 14's D-01/D-02 convention) — there is no shared global tolerance to reconcile across fixtures.
- **D-08:** Residual-gap honesty bar mirrors VALD-01/`13-SCOPE-BOUNDARY.md`'s convention (also the exact wording of this phase's own SC4): if no value in `byteQuantMode`'s valid `[0,8]` range closes a given fixture's real captured cross-hardware divergence, that gap is documented and characterized honestly — never silently declared passing to satisfy SC4's letter.

### Capture dataset
- **D-09:** Reuses Phase 11's exact two-machine dataset — Mac mini (`Fuus-Mac-mini.local`, macOS) and Windows (`Mofu`, Windows) — no new hardware. WSL's `llvmpipe` software rasterizer remains excluded per Phase 11's already-accepted D-0x rationale (not a real GPU). All three new fixtures get fresh `capture_harness` runs on both machines (mirroring the existing `xhw-render_*.cap` naming convention from `11-01-PLAN.md`/`11-CAPTURE-RESULTS.md`).

### Claude's Discretion
- Exact new `pipeline_state` schema field name(s)/shape for blend state (e.g. `blend_enable` plus source/dest factor enums) — extending the "curated, minimal" D-13 set is this phase's job; the exact shape is not decided here.
- Exact new schema mechanism for declaring a sampled-image render input (new input `type`, descriptor-set-layout shape, `VkSampler` creation parameters/filtering mode) — genuinely new design surface, left to research/planning.
- Exact GLSL lighting model (Phong vs. Lambertian-only) and uniform naming.
- Exact new counter-test file names (mirror `secv01_tex3d_counter_test.cpp`'s naming convention — three new files expected, one per fixture).
- Whether ROADMAP.md's Phase 17 Success Criteria wording (currently written around "a fixture," singular) should be updated to reflect three fixtures — a documentation-correction task, similar to Phase 16's own SC-wording correction, left to planning to decide when to do.
- Whether all three fixtures ship in one wave or are sequenced (texturing's larger infra work vs. lighting's zero-infra work suggests they may not be equal-sized plan units) — a planning-level sequencing decision, not fixed here.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & Roadmap
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` — RENDTOL-01, RENDTOL-02, the locked requirements for this phase
- `.planning/workstreams/sgproc-render/ROADMAP.md` (Phase 17 section) — goal, SC1-SC5; note SC1-SC2's "a fixture" (singular) wording predates this discussion's D-02/D-04 three-separate-fixtures decision (see Claude's Discretion above)
- `.planning/workstreams/sgproc-render/STATE.md` — the "Untested risk" paragraph this phase closes (render path's byte-identity claim only measured against the trivial 8x8 fixture); the Phase 11 two-machine (Mac+Windows, WSL/llvmpipe excluded) dataset decision this phase's D-09 reuses

### Prior Phase Context (source of the patterns this phase extends)
- `.planning/workstreams/sgproc-render/phases/14-configurable-normalization-precision/14-CONTEXT.md` — D-01/D-02 (generic `parameters`-array lookup convention this phase's per-fixture `byteQuantMode` declarations reuse), D-06/D-07/D-08 (the `byteQuantMode` bit-masking mechanism itself, already shipped), D-09/D-10 (the binary-search-against-a-counter-test methodology D-06 of this phase's context replicates)
- `.planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/11-CONTEXT.md` and `11-CAPTURE-RESULTS.md` — the two-machine dataset scope/rationale D-09 reuses verbatim; `captures/xhw-render_*.cap` naming precedent
- `.planning/workstreams/sgproc-render/phases/03-renderprocessor-implementation-determinism/03-CONTEXT.md` and `03-RESEARCH.md` — DETV-02's architectural guards (explicit clears, fixed sample count, fixed shader precision, no unordered reduction) that D-03 confirms this phase does not reopen
- `.planning/workstreams/sgproc-render/phases/02-schema-extension-shader-spir-v-validation-pipeline/02-CONTEXT.md` — D-13 ("curated, minimal v1 fixed-function pipeline state subset") and D-14 (fixed depth-compare-op) — the existing minimalism philosophy D-05's blend-state addition deliberately extends

### Existing Code (Source of Truth)
- `SuperGenius/SGProcessingManager/include/util/quantization.hpp`, `src/util/quantization.cpp` — `ResolveByteQuantMode`/`QuantizeByteBuffer`, the already-existing mechanism this phase tunes (not builds)
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp:2096,2209` — the render path's existing `ResolveByteQuantMode`/`QuantizeByteBuffer` call site
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp:1526` — `DETV-02`'s hardcoded `VK_SAMPLE_COUNT_1_BIT`, grounds D-03
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp:1528-1536` — hardcoded `blendEnable = VK_FALSE`/single-attachment color-blend state, the code D-05's blending work must extend
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp:760-809` — `ResolveUniforms`'s per-`DataType` dispatch; lines 760-799 show the already-working `VEC3`/`VEC4`/`MAT4` path lighting reuses as-is, lines 800-809 show the `TEXTURE*` rejection texturing must remove/replace
- `SuperGenius/SGProcessingManager/gnus-processing-schema.json:549-574` — `pipeline_state`'s current "curated, minimal" definition (D-13/D-14), to be extended for blending
- `SuperGenius/test/src/processing_dispatch/render-pass-happy-path-definition.json` — the existing trivial 8x8/solid-color/point-list fixture this phase's three new fixtures contrast against
- `SuperGenius/test/src/processing_conformance_security/secv01_counter_test.cpp` — existing `RenderWrongShaderConstantStillDiverges` test (trivial fixture, `byteQuantMode` unset/falls back to 0) — pattern to extend, not the fixture to reuse
- `SuperGenius/test/src/processing_conformance_security/secv01_tex3d_counter_test.cpp` — the exact "new dedicated counter-test file per newly-tuned fixture" naming precedent D-07's three new files should mirror
- `SuperGenius/SGProcessingManager/tools/capture/capture_harness.cpp`, `capture_diff.cpp` — existing capture/diff tooling (Phase 10) this phase's empirical runs reuse as-is

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ResolveByteQuantMode`/`QuantizeByteBuffer` (Phase 14) — fully wired to the render call site already; this phase only needs to get a real non-zero, empirically-justified value into each fixture's `parameters` array
- Generic `parameters`-array find-by-name lookup convention (Phase 14 D-01/D-02) — each new fixture declares its own `byteQuantMode` entry the same way
- `capture_harness`/`capture_diff` (Phase 10) — reused as-is for all three fixtures' empirical two-machine runs
- `secv01_tex3d_counter_test.cpp` — direct structural template for the three new per-fixture counter-tests
- `ResolveUniforms`'s existing `VEC3`/`VEC4`/`MAT4` handling — lighting's fixture needs no new uniform-type plumbing at all

### Established Patterns
- DETV-02's architectural determinism guards (explicit clears, `VK_SAMPLE_COUNT_1_BIT`, fixed shader precision, no unordered reduction) — untouched; every new fixture's shaders must still satisfy these (precision qualifiers, no loop/reduction math), same as the existing happy-path fixture
- Binary-search-against-a-counter-test tolerance derivation (Phase 13/14 precedent) — reused per-fixture for `byteQuantMode`
- "Won't force a pass" honesty convention (VALD-01/13-SCOPE-BOUNDARY.md) — applies per-fixture to SC4/D-08

### Integration Points
- `BuildPipeline()` (`processing_processor_render.cpp`, Phase 3 plan 03-04's implementation) — blending's `VkPipelineColorBlendAttachmentState` change and texturing's new descriptor-set-layout entry both land here
- `ResolveUniforms()` — texturing's new uniform-type handling and lighting's reuse of existing vector/matrix handling both live here
- Schema `pipeline_state`/uniform definitions (`gnus-processing-schema.json`) — blending and texturing both need new schema surface; lighting needs none

</code_context>

<specifics>
## Specific Ideas

- User's own framing for the technique-scope decision: "support as many types of rendering as reasonable" — explicit preference for breadth (all three techniques) over doing one well, accepted with the tradeoff made explicit (texturing/blending are real new infrastructure, not fixture-only work)
- Three independent fixtures, three independent capture/diff/tolerance-derivation cycles, three independent new counter-tests — no shared combined fixture, no shared global tolerance value

</specifics>

<deferred>
## Deferred Ideas

- **MSAA as a fixture technique** — considered (it was one of the roadmap's three named options), not chosen. Not merely deprioritized: DETV-02 architecturally hard-blocks it (`VK_SAMPLE_COUNT_1_BIT` unconditional, "never configurable"). Reopening it would mean revisiting a locked Phase 3 determinism decision — out of scope for this phase and not requested by the user.
- **Combining all three techniques into one fixture** — considered, not chosen (D-04 picked separate fixtures instead).

### None further — discussion stayed within phase scope

</deferred>

---

*Phase: 17-Render-Path Cross-Hardware Tolerance*
*Context gathered: 2026-08-18*
