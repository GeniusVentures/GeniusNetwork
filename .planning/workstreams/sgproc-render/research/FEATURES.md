# Feature Research

**Domain:** Cross-hardware hash-tolerance tooling for `SGProcessingManager` job outputs (render + MNN inference) — capture harness, diff tool, quantization step
**Researched:** 2026-08-07
**Confidence:** MEDIUM (cross-checked against Vulkan CTS, ONNX Runtime/ONNX spec, FLiT/float-determinism literature, and standard image-diff tooling; no GNUS-specific prior art exists for this exact problem)

This is not a consumer feature landscape — it's an engineering capability landscape for three internal tools: (1) a capture harness that dumps raw values + hashes per run on a given machine, (2) a diff tool that compares captures across machines and characterizes divergence, and (3) a quantization/rounding step that collapses float noise before hashing. "Table stakes" = required for the v2.1 success bar ("post-quantization hashes match across ≥3 machines on the test fixtures") to be achievable and trustworthy. "Differentiators" = correctness/debuggability value beyond the minimum. "Anti-features" = things that look useful but re-open scope this milestone explicitly deferred (schema-configurable precision, `ValidateResults` bug fix, cross-node consensus plumbing) or that duplicate infrastructure Phase 09 already built.

**Load-bearing dependency:** Phase 09 (`.planning/workstreams/sgproc-render/phases/09-processor-pass-graph-conformance-suites/`) already built the conformance fixture/harness conventions this milestone must reuse, not reinvent:
- Fixture pattern: pre-baked `.mnn` models, `.raw` input/output, JSON processing definitions, GLSL/SPIR-V shader pairs, POST_BUILD-copied into the build tree (`processing_datatypes_test`, `processing_conformance_*` targets)
- `addtest()` CMake macro (`SuperGenius/cmake/functions.cmake`) for CTest registration inside `SuperGenius/test/src/`
- `vulkan_gpu_probe.hpp`'s `HasUsableVulkanDevice()` + `GTEST_SKIP()` pattern for GPU-dependent tests
- `sgprocmanagersha` SHA-256 hashing library — already the hash primitive `ProcessingResult.hash` and `ARTF-03` chunk hashes use
- `ARTF-03`: artifacts already carry a content hash **and chunk hashes** — the capture harness's "chunk hashes per run" requirement is not new plumbing, it's exercising an existing `Artifact`/`ExecutionManifest` field that Phase 08/09 already implemented and tested

## Feature Landscape

### 1. Capture / Logging Harness

Table stakes vs. differentiator for what a cross-hardware determinism capture harness dumps and how it structures output for later diffing.

#### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Per-run raw output dump (full element array, not just a summary) | A diff tool cannot localize a divergent element from a statistical summary alone — every serious cross-platform float-consistency tool (FLiT, ONNX backend tests, Vulkan CTS reference-image comparison) keeps the raw buffer, not just a checksum, precisely so a failure can be traced to *which* element diverged | LOW | Already partially built: `RenderProcessor` output is `texture2D` bytes, MNN output is a tensor buffer — both already exist in-memory pre-hash. The harness only needs to persist them to a file instead of discarding after hashing. Reuse the existing raw-byte buffer, do not re-derive it. |
| Per-run combined hash (SHA-256 over the full output) | This is the exact quantity DETV-01 already proves is same-node stable; the harness's job is to capture it per-machine so cross-machine equality can be checked without re-deriving hashing logic | LOW | Direct reuse of `sgprocmanagersha` — no new hash implementation. |
| Per-run chunk hashes (fixed-size sub-ranges of the output, each independently hashed) | Localizes *where* in a large buffer (e.g. a full-resolution render target or a large tensor) a mismatch starts, without needing the raw dump for a first pass — this is exactly what `ARTF-03`'s chunk-hash field already models | LOW | Reuses `ARTF-03`/`ExecutionManifest` chunk-hash mechanism verbatim — the capture harness's job is to *invoke* the existing artifact-hashing path on capture, not add a new chunking scheme. Chunk boundary/size should match whatever Phase 08 already fixed for `ARTF-03`, for consistency with production artifact hashing. |
| Batch (whole-run) dump, not streaming/incremental | This is a discrete submit-once-return-hash batch job (same framing as the render/MNN pipeline itself) — there is no "streaming" concept in the pipeline to hook into, and CTS/ONNX-style conformance harnesses uniformly dump complete tensors/images per test case, not incremental deltas | LOW | Matches existing pipeline shape; no new async/streaming capture machinery needed. |
| Machine/environment identity tagged on each capture (hostname or user-supplied label, OS, GPU vendor/model, driver version, MNN backend) | Cross-machine diffing is meaningless without knowing which capture came from which machine/config — Vulkan CTS's `.qpa` logs and ONNX backend-test reports both tag results with the executing environment for this reason | LOW | Simple metadata header on the capture file; no live device enumeration beyond what `CanExecute`/`vulkan_gpu_probe.hpp` already surface. |
| Deterministic, versioned capture file format (fixed field order/layout, format-version tag) | The diff tool in section 2 depends on being able to parse two captures produced by (potentially) different builds of the harness; ARTF-05 already establishes the precedent that manifest-shaped output must serialize deterministically for hashing/comparison — the capture file inherits that same requirement | LOW-MEDIUM | Reuse whatever serialization convention `ExecutionManifest` (ARTF-05) already uses rather than inventing a second one. |
| Fixture reuse from Phase 09 (small deterministic render + MNN jobs, not new production-scale fixtures) | The success bar is "hashes match across ≥3 machines on the *test fixtures*" — Phase 09 already has minimal deterministic render (GLSL/SPIR-V pass-through) and MNN (per-datatype) fixtures wired into CTest with POST_BUILD fixture copy | LOW | Building new fixtures duplicates Phase 09's fixture-generation Python scripts and `.mnn`/`.raw` assets for no benefit — capture harness should run *against* the same fixtures, just with capture-dump enabled instead of (or alongside) assertion-based pass/fail. |

#### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Capture harness runnable as a standalone CLI/CTest target (not only invoked implicitly inside another test) | Lets the user manually run the harness on their Mac and PC outside of a full CI cycle and hand the two output files to the diff tool — directly matches the stated workflow ("dumps... for the user's own Mac and PC") | LOW-MEDIUM | A thin executable/CTest entry that runs one fixture through `ProcessingManager::Process()` and writes the capture file; no new orchestration framework needed. |
| Per-element metadata alongside raw values (index/coordinate, e.g. pixel (x,y,channel) for render output, tensor flat-index for MNN) | Makes outlier localization (section 2) actionable — "element 4,213 diverges" is more useful debugging output than a flat byte offset, echoing how image-diff tools report pixel coordinates and ONNX debugging tools report tensor indices | LOW | Straightforward since output shape/dimensions are already known from the schema (`io_declaration.dimensions`) — no new shape-inference needed. |
| Multiple repeat captures per machine bundled in one invocation (reuses DETV-01's N-repeat pattern) | Lets a single capture run also re-confirm same-node determinism (DETV-01) hasn't regressed before the cross-machine comparison is even attempted — cheap insurance against blaming cross-hardware noise for what's actually a same-node regression | LOW | Optional flag on top of the existing DETV-01 N≥10 repeat-run test; not required for the milestone's success bar but low-cost to add given the test already exists. |

#### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|------------------|-------------|
| Live/streaming telemetry pipeline (e.g. push captures to a central server in real time) | Feels like the "production-ready" way to eventually support N-machine consensus checking | This milestone is validating hash-tolerance logic on ≤3 machines the user personally controls — a telemetry service is cross-node consensus/redundancy plumbing, which is explicitly deferred (`XNODE-01`'s actual comparison plumbing is out of scope) | Flat capture files, manually copied/shared between machines (matches the user's stated workflow) |
| New chunking/hashing scheme distinct from `ARTF-03` | Might seem cleaner to design chunk boundaries specifically for diff-friendliness | Diverges the capture harness's hash semantics from the production artifact-hashing path it's supposed to validate — if the capture harness hashes differently than production, a "hashes match" result doesn't actually prove anything about production `ValidateResults`/artifact hashing | Reuse `ARTF-03`'s existing chunk-hash mechanism as-is |
| Automatic schema-configurable capture granularity (per-data-type dump verbosity settings) | Feels like natural symmetry with the quantization step's future schema-configurable precision | Explicitly the same kind of scope creep the milestone locked out for quantization ("schema-configurable precision explicitly deferred") — no reason to introduce configurability in the capture harness that the quantization step itself isn't allowed to have yet | Fixed capture format for this milestone; revisit only if/when quantization itself becomes configurable |

### 2. Diff / Comparison Tooling

Table stakes vs. differentiator for "is this divergence normal float noise or a real bug."

#### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Per-element absolute delta (`|a - b|`) | The baseline metric every float-comparison approach in the research starts from (ONNX Backend Tests' `atol`, FLiT's absolute-check-first hybrid comparator) | LOW | Trivial once both capture files are parsed into aligned arrays. |
| Per-element relative delta (`|a - b| / max(|a|, |b|, eps)`) | Absolute delta alone is misleading across value magnitudes (a 1e-3 absolute diff is noise on a value of 1000 but catastrophic on a value of 1e-4) — ONNX Backend Test's combined `atol`+`rtol` convention exists specifically for this reason | LOW | Needs an epsilon floor to avoid divide-by-zero near zero-valued elements; standard practice (`numpy.allclose`-style formula). |
| Max absolute delta + max relative delta (whole-buffer summary) | This is explicitly named in the milestone's target features ("max delta") — the single number a human uses to answer "is this within normal float noise" at a glance | LOW | Direct reduction over the per-element deltas already computed. |
| ULP (Units-in-the-Last-Place) distance per element, plus max-ULP summary | Explicitly named in the milestone's target features ("mantissa-bit differences"); ULP distance is the standard way to express "how many representable floats apart" two values are, independent of magnitude — this is exactly the second half of the FLiT/Bruce-Dawson hybrid-comparator pattern (absolute check, then ULP check) | LOW-MEDIUM | Requires reinterpreting the float bit pattern as an integer and computing the signed/unsigned integer distance (well-established bit-trick; no external library required for IEEE-754 float32/float64). |
| Pass/fail verdict driven by the *same* thresholds the quantization step is tuned against | The diff tool's real job this milestone is validating whether quantization (section 3) actually closes the gap — its thresholds must be legible in the same units the quantization step rounds to, or "is this now within tolerance" can't be answered | LOW | Not a new concept, just consistency: report deltas in the same precision units the quantization step targets. |
| Element-count / percentage of elements exceeding a given delta threshold | A single max-delta outlier is a different failure mode than 40% of elements drifting — both the ONNX ecosystem and image-diff tools (PerceptualDiff's "N pixels differ" threshold) report an exceeding-count/percentage, not just a max, because "one weird pixel" and "systemic drift" need different responses | LOW | Simple counting pass alongside the max/histogram computation. |

#### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Histogram of per-element differences (delta magnitude buckets) | Distinguishes "normal float noise" (tight unimodal histogram near zero) from "a real bug" (bimodal, or a long tail of large outliers) at a glance — this is the diagnostic signal the milestone question explicitly asks about; standard practice in float-consistency literature (FLiT-style variability studies) and image-diff tooling | LOW-MEDIUM | Straightforward bucketed count over already-computed per-element deltas; no new data collection needed. |
| Outlier localization (report the top-N divergent element indices/coordinates, not just aggregate stats) | Turns "something's wrong" into "here's exactly which pixel/tensor-index/channel to look at" — directly actionable for debugging a real bug vs. noise, and depends on the capture harness having tagged per-element coordinates (section 1 differentiator) | LOW-MEDIUM | Sort-and-truncate over per-element deltas; coordinate mapping only works if the harness captured shape/index metadata. |
| Per-region/per-channel breakdown for structured outputs (e.g. separate stats for R/G/B/A channels on render output, or per-layer stats for a multi-layer MNN tensor) | A single flat max-delta can hide "channel A is fine, channel B is systematically off" — matches how per-channel quantization research treats channels as having independently-varying dynamic range/error characteristics | MEDIUM | Requires the diff tool to understand output *shape* (already known from schema `io_declaration.dimensions`), not just a flat byte buffer — moderate but bounded complexity. |
| Machine-readable diff report (JSON) in addition to human-readable summary | Enables the diff tool's output to be asserted against in a future CTest (e.g. "max ULP distance ≤ N passes"), matching Phase 09's existing pattern of asserting on structured results rather than parsing text | LOW | Straightforward serialization of the same stats already computed; no new comparison logic. |

#### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|------------------|-------------|
| Full statistical test suite (Kolmogorov-Smirnov, chi-squared, etc.) for "is this distribution significantly different" | Sounds rigorous for distinguishing noise from bugs | Massive overkill for small deterministic test fixtures with a handful of known output elements; adds a statistics-library dependency for a decision ("does max-ULP/max-delta exceed threshold") that a simple threshold already answers correctly at this scale | Max delta / max ULP / percentage-exceeding-threshold, as already scoped |
| Automatic bug-vs-noise classification (ML-based or heuristic auto-verdict) | Would remove the human from the "is this expected" decision entirely | The milestone's actual open question ("is this divergence normal float noise or a real bug") is a judgment call this milestone is explicitly trying to give the *user* better data for — automating the verdict pre-empts the exact investigation this tooling exists to support, and risks hiding a genuine cross-vendor bug behind a false "it's just noise" classification | Rich stats (max/relative/ULP/histogram/outliers) presented for human judgment; no auto-verdict |
| Fixing `ProcessingValidationCore::ValidateResults`'s concatenation bug as part of the diff tool | The diff tool and `ValidateResults` are solving superficially similar problems ("compare two chunk-hash sets") | Explicitly out of scope this milestone — `ValidateResults` is a separate, already-tracked gap in the *production* cross-node comparison path; the diff tool is a *developer-facing offline* tool for this milestone's manual Mac/PC validation, not a replacement for or fix to the production path | Leave `ValidateResults` untouched; diff tool is a standalone CLI, not wired into the consensus/validation path |

### 3. Quantization / Rounding Step

Table stakes vs. differentiator for what's genuinely needed in the pre-hash quantization step, at fixed (non-schema-configurable) precision.

#### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Fixed decimal-places (or fixed-bit-width) rounding applied uniformly to all float elements before hashing | This is the core mechanism the milestone scopes ("quantization/rounding step... FIXED precision") — the research confirms this is a standard, well-established mitigation (round to canonical decimal representation, or truncate mantissa bits) for exactly this class of problem (hashing near-equal floats that should collapse to one hash) | LOW-MEDIUM | A single global rounding rule (e.g. round to N significant decimal digits, or mask/round the mantissa to K bits) applied identically to render output and MNN tensor output — "fixed precision, not schema-configurable" is explicitly the locked scope, so one constant, not a table of constants. |
| Applied identically on both the render output path and the MNN inference output path | Both are named explicitly in the milestone target features ("render + MNN output paths") — the success bar requires both pipelines' outputs to be quantization-then-hash-tolerant, not just one | LOW | Same rounding function, invoked at the same point (immediately pre-hash) in both `RenderProcessor` and MNN processor output handling — a shared utility, not two independent implementations. |
| Applied before both the combined hash and the chunk hashes | If quantization only touched the combined-hash input but chunk hashes still hashed raw values (or vice versa), the two hash layers would disagree on whether two runs "match," undermining `ARTF-03`'s dual-hash design | LOW | Quantization is a pre-processing step on the buffer that both the combined-hash and chunk-hash computation read from — apply once, hash the already-quantized buffer at both granularities. |
| Deterministic rounding mode (e.g. round-half-to-even, applied via a fixed, documented rule — not the platform's ambient FPU rounding mode) | The research on ULP/reproducibility explicitly flags rounding-mode inconsistency as an error-accumulation source; if the quantization step itself uses a platform-dependent rounding mode, it reintroduces the exact class of cross-hardware non-determinism it exists to eliminate | LOW-MEDIUM | Implement rounding as an explicit arithmetic operation (e.g. `round(x * scale) / scale` with a specified libc/standard rounding function), not by relying on compiler/FPU default rounding behavior, which is what the "deterministic cross-platform floating point" research warns against. |
| Value-range/type awareness limited to "is this a normalized color/texture value (0–1 or 0–255) vs. an arbitrary-range numeric tensor value" — enough to pick one sane fixed precision, not a full per-type precision table | Render output (image/texture data, typically normalized or 8-bit-per-channel) and MNN tensor output (arbitrary-range floats) have genuinely different natural precision needs — a single global decimal-places constant tuned for tensor magnitudes might quantize a 0–1 color value into visually/numerically meaningless buckets, or vice versa | LOW-MEDIUM | This is the one place a *little* differentiation is justified even under "fixed precision, not schema-configurable" — a small fixed number of hardcoded precision constants (e.g. one for texture/image output, one for numeric tensor output), decided once by the implementer, is different from *schema-configurable per-data-type tuning* (which requires the schema to expose a knob per job). Keep this distinction explicit in the roadmap/plan so it isn't mistaken for the deferred scope. |

#### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Per-channel handling for multi-channel image/texture output (e.g. treat R/G/B/A identically today, but structure the code so a future per-channel scale could slot in) | Per-channel vs. per-tensor quantization research shows real accuracy/consistency differences when channels have different dynamic ranges — not needed for the milestone's fixed-precision bar, but designing the rounding function to take a channel index (even if it currently applies the same constant to every channel) avoids a rewrite if a future milestone needs per-channel tuning | LOW | Purely a code-shape choice (parameterize by channel/tensor-role now, even with one shared constant) — zero behavior change, avoids foreclosing future work without doing that future work now. |
| Distinguish "image/texture-shaped" output from "numeric tensor" output at the quantization call site (rather than one blanket function invoked blindly on any float buffer) | Keeps the one legitimate scope carve-out (table-stakes row above) clean and auditable — a reviewer can see exactly which fixed constant applies to which output kind, rather than a single opaque constant whose applicability to both kinds is assumed | LOW | This is mostly about code organization/clarity, not new logic — two thin call sites (render path, MNN path) each calling the shared rounding utility with their own already-decided constant. |

#### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|------------------|-------------|
| Schema-configurable precision (per-data-type or per-job quantization tuning exposed to job authors) | Feels like the "complete" version of the fixed-precision quantization step, and the schema already has precedent for job-author-configurable fields elsewhere | Explicitly, verbatim deferred by this milestone's scope ("Schema-configurable precision explicitly deferred to a future milestone") — building the schema plumbing now duplicates work if a future milestone designs it differently, and risks the exact "should have asked before building" trap | Fixed, hardcoded precision constant(s) this milestone; schema knob is a named future-milestone candidate |
| Per-vertex/per-draw-call adaptive quantization (choosing precision based on geometry complexity or scene content) | Sounds like it would better preserve visual fidelity while still being deterministic | Adds job-content-dependent branching logic to what should be a simple, auditable, fixed rounding step — directly conflicts with "FIXED precision" and massively complicates verifying the ≥3-machine success bar (now two machines could disagree because they took different adaptive branches, not because of real float noise) | One fixed constant per output kind (image vs. tensor), as scoped above |
| INT8/compression-style quantization (actual bit-width reduction / lossy compression of stored values, not just rounding before hash) | "Quantization" in ML usually means this (per-channel/per-tensor scale+zero-point, INT8 storage) — the term overlaps with the milestone's "quantization/rounding step" language | This milestone's quantization is a *hash-input normalization* technique (round values so noise-equivalent runs hash identically), not a *model/data compression* technique (reduce storage/compute cost) — conflating the two would mean changing the actual output data users receive, not just what gets hashed for comparison, which is a much larger and riskier change than intended | Round-then-hash only; the actual `ProcessingResult`/artifact output bytes remain full precision — only the hash-input copy is quantized (confirm this exact boundary during phase discussion) |
| Fixing `ProcessingValidationCore::ValidateResults` as a side effect of adding quantization | Quantization changes what "matching hash" means, which is conceptually adjacent to the comparison logic `ValidateResults` implements | Explicitly out of scope — the milestone makes the *hash itself* tolerant, and the pre-existing concatenation bug in `ValidateResults` is tracked separately; touching it here expands blast radius into production consensus code this milestone isn't testing against real multi-node consensus at all | Leave `ValidateResults` untouched; quantization lands in the render/MNN output-hashing path only |

## Feature Dependencies

```
[Capture Harness: raw dump + combined hash] (table stakes)
    └──requires──> [Phase 09 fixtures: render + MNN deterministic test fixtures]
    └──requires──> [sgprocmanagersha: SHA-256 hashing primitive] (existing)

[Capture Harness: chunk hashes] (table stakes)
    └──requires──> [ARTF-03: existing Artifact/ExecutionManifest chunk-hash field] (existing, Phase 08/09)

[Capture Harness: standalone CLI/CTest invocation] (differentiator)
    └──requires──> [addtest() CMake macro / vulkan_gpu_probe.hpp GPU-skip pattern] (existing, Phase 09)

[Diff Tool: max/relative delta, ULP distance] (table stakes)
    └──requires──> [Capture Harness: raw per-element dump]
    └──enhances──> [Quantization Step] (diff tool is how you *validate* quantization closed the gap)

[Diff Tool: outlier localization, per-region breakdown] (differentiators)
    └──requires──> [Capture Harness: per-element coordinate/shape metadata] (differentiator)

[Quantization Step: fixed rounding, render+MNN paths] (table stakes)
    └──requires──> [Capture Harness + Diff Tool] (needed to prove quantization actually closes cross-machine gaps — you cannot validate the success bar without both)
    └──feeds──> [Combined hash + chunk hashes] (quantized buffer is what gets hashed, both granularities)

[Quantization Step: per-image-vs-tensor fixed constants] (table stakes, narrow carve-out)
    └──conflicts──> [Schema-configurable precision] (explicitly deferred — do not let this carve-out grow into that)

[Diff Tool / Capture Harness] ──conflicts──> [ProcessingValidationCore::ValidateResults fix]
[Quantization Step] ──conflicts──> [Cross-node consensus/redundant-execution plumbing]
```

### Dependency Notes

- **Capture harness requires Phase 09 fixtures:** The milestone's success bar is measured "on the test fixtures" — there is no requirement (and no time budget implied) to build new production-scale fixtures. Reusing Phase 09's small deterministic render (GLSL/SPIR-V pass-through triangle) and MNN (per-datatype) fixtures is both correct scope and the path of least implementation risk.
- **Capture harness's chunk-hash feature requires `ARTF-03`:** This is not new plumbing — it's the first real *exercise* of the chunk-hash field Phase 08 built and Phase 09's conformance suite already asserts exists. If chunk hashing doesn't already work end-to-end per `ARTF-03`, that's a pre-existing gap to surface, not a new feature to build here.
- **Diff tool enhances (validates) the quantization step:** The two are not independent deliverables — the diff tool is the instrument that proves the quantization step's fixed precision actually collapses cross-machine noise below the "matching hash" bar. Plan them so the diff tool exists and works *before* declaring the quantization step's precision constants final.
- **Quantization's per-image-vs-tensor carve-out conflicts with (must not grow into) schema-configurable precision:** The one legitimate "table stakes" differentiation this research recommends (one constant for image/texture output, one for numeric tensor output) must stay as hardcoded implementation constants, not schema fields. Any plan/design surfacing this as a schema knob has silently re-opened deferred scope.
- **Everything in this milestone conflicts with `ValidateResults`'s fix and with actual cross-node consensus plumbing:** Both are explicitly out of scope; the capture harness and diff tool are offline/manual developer tools (used by the user across their own machines), not wiring into the production multi-node comparison path.

## MVP Definition

### Launch With (v2.1 — this milestone)

Minimum viable to hit the stated success bar ("post-quantization hashes match across ≥3 machines on the test fixtures").

- [ ] Capture harness: raw dump + combined hash + chunk hashes + machine-identity tag, run against Phase 09's existing render + MNN fixtures — essential, this is the data the whole milestone depends on
- [ ] Diff tool: max absolute delta, max relative delta, max ULP distance, percentage-of-elements-exceeding-threshold, over two (or more) capture files — essential, this is the "is quantization working" instrument
- [ ] Quantization step: one fixed rounding rule for image/texture output, one fixed rounding rule for numeric tensor output, applied identically pre-hash on render and MNN paths, deterministic rounding mode — essential, this is the actual fix being validated
- [ ] Empirical validation run across ≥3 machines (user's Mac + PC + one more) confirming post-quantization combined-hash match on the test fixtures — essential, this is the literal success bar

### Add After Validation (v2.1.x, if the MVP reveals gaps)

- [ ] Histogram of per-element differences — valuable if the raw max/relative/ULP numbers alone don't make "noise vs. bug" obvious on the first real cross-machine run
- [ ] Outlier localization (top-N divergent element coordinates) — valuable if a first cross-machine run shows a real mismatch and needs debugging, not just confirmation
- [ ] Standalone CLI/CTest-invokable capture harness (vs. only invoked from within a single combined test) — valuable for repeat manual runs across the user's machines without a full CI cycle

### Future Consideration (v2.2+)

- [ ] Per-channel/per-region breakdown for structured render output — defer until a real cross-machine mismatch actually needs channel-level attribution
- [ ] Schema-configurable per-data-type precision — explicitly deferred by this milestone; revisit only once fixed-precision quantization is proven on real hardware
- [ ] Actual cross-node consensus/redundant-execution comparison plumbing (fixing `ValidateResults`'s diff logic, wiring the tolerant hash into production job validation) — explicitly deferred; this milestone only proves the hash *can* be tolerant, not that production consensus *uses* that tolerance correctly

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|----------------------|----------|
| Capture harness (raw dump + combined hash + chunk hash, reusing Phase 09 fixtures) | HIGH | LOW | P1 |
| Diff tool: max/relative delta + ULP distance + exceeding-count | HIGH | LOW | P1 |
| Quantization step (fixed precision, render+MNN paths, deterministic rounding) | HIGH | MEDIUM | P1 |
| Machine-identity tagging on captures | MEDIUM | LOW | P1 |
| Standalone CLI/CTest capture invocation | MEDIUM | LOW-MEDIUM | P2 |
| Histogram of differences | MEDIUM | LOW-MEDIUM | P2 |
| Outlier localization (per-element coordinates) | MEDIUM | LOW-MEDIUM | P2 |
| Per-channel/per-region diff breakdown | LOW-MEDIUM | MEDIUM | P3 |
| Repeat-capture bundling (re-validate DETV-01 alongside cross-machine capture) | LOW | LOW | P3 |

**Priority key:**
- P1: Must have to hit the ≥3-machine success bar
- P2: Should have, adds debuggability if the first cross-machine run isn't clean
- P3: Nice to have, future consideration — do not let these expand this milestone's scope

## Reference Systems Analyzed

| System | How it handles cross-hardware output verification | Applicability here |
|--------|------------------------------------------------|---------------------|
| Vulkan/OpenGL CTS (Khronos) | Reference-rendering + round-trip + cross-verification strategies; configurable per-test pixel-comparison thresholds; results logged with embedded images for visual inspection | Confirms "keep raw pixels + a tunable numeric threshold" over pure checksum-only comparison is the graphics-conformance norm — informs the capture harness's raw-dump requirement |
| ONNX / ONNX Runtime backend tests | No bit-exact cross-backend guarantee by design; combined absolute+relative tolerance (`atol`/`rtol`) applied per-element, values like `atol=1e-7, rtol=1e-3` common | Directly informs the diff tool's max-absolute/max-relative delta metrics and the general framing that cross-hardware float equality is inherently a tolerance question, not a bit-exactness one |
| FLiT (Floating-point Litmus Test framework) / Bruce Dawson's float-determinism writing | Hybrid comparator: absolute-difference check first, then ULP-distance check (e.g. max 4 ULP) if absolute check fails; either passing = "equal" | Directly informs the diff tool's ULP-distance metric and the general two-stage (absolute-then-ULP) comparison pattern worth adopting for the pass/fail verdict |
| PerceptualDiff / ImageMagick `compare` / DSSIM | Perceptual/statistical image-diff metrics (AE, RMSE, PSNR, DSSIM, pixel-exceeding-count) for renderer regression testing across versions/hardware; PSNR/RMSE noted as weak, DSSIM/perceptual preferred | Informs render-output-specific diff handling (image/texture output is a structured, coordinate-addressable case distinct from a flat numeric tensor) — supports the "image vs. tensor need different fixed precision" table-stakes carve-out |
| Per-channel vs. per-tensor ML quantization literature | Per-tensor = one scale/zero-point, cheaper, more accuracy loss on divergent channel ranges; per-channel = per-channel scale/zero-point, better accuracy, more state; rounding-mode choice affects error accumulation | Informs the quantization step's scope boundary — validates that "one fixed constant per output kind" is a reasonable minimal middle ground between "one global constant" (too coarse for image vs. tensor) and "per-channel/per-job configurable" (the explicitly deferred scope) |
| Deterministic-hashing-of-floats practice (reproducible-builds literature) | Hashing raw floats is unreliable because near-equal values don't map to equal hashes; standard mitigations are fixed-point conversion, canonical decimal round-trip serialization, or explicit rounding before hashing | Directly validates the milestone's chosen approach (quantize/round, then hash) as the standard fix rather than an ad hoc one |

## Sources

- [VK-GL-CTS (Khronos Conformance Test Suite)](https://github.com/KhronosGroup/VK-GL-CTS) — MEDIUM confidence (web search, cross-referenced with DeepWiki summary; general architecture confirmed, exact tolerance values not publicly itemized)
- [Vulkan CTS :: Vulkan Documentation Project](https://docs.vulkan.org/guide/latest/vulkan_cts.html) — MEDIUM confidence
- [ONNX Backend Test / numerical precision discussion — emmtrix Wiki](https://www.emmtrix.com/wiki/Numerical_Precision_in_ONNX_and_AI_Inference) — MEDIUM confidence
- [onnx-mlir: Debugging Numerical Error](https://onnx.ai/onnx-mlir/DebuggingNumericalError.html) — MEDIUM confidence
- [FLiT: Cross-Platform Floating-Point Result-Consistency Tester and Workload](https://pruners.github.io/pdf/iiswc2017-final43.pdf) — MEDIUM confidence
- [Floating-Point Determinism — Random ASCII (Bruce Dawson)](https://randomascii.wordpress.com/2013/07/16/floating-point-determinism/) — MEDIUM confidence
- [Floating Point Determinism — Gaffer On Games](https://gafferongames.com/post/floating_point_determinism/) — MEDIUM confidence
- [Per-Tensor, Per-Channel, Per-Group Quantization — apxml.com](https://apxml.com/courses/practical-llm-quantization/chapter-1-foundations-model-quantization/quantization-granularity) — MEDIUM confidence
- [Quantization — MLIR/LLVM docs](https://mlir.llvm.org/docs/Quantization/) — MEDIUM confidence
- [PerceptualDiff](https://github.com/myint/perceptualdiff) / [pdiff.sourceforge.net](https://pdiff.sourceforge.net/) — MEDIUM confidence
- [ImageMagick `compare` man page](https://linuxcommandlibrary.com/man/magick-compare) — MEDIUM confidence
- [Comparing Image Comparison Algorithms — Programming Sanity](https://blog.jeffterrace.com/2012/09/comparing-image-comparison-algorithms.html) — MEDIUM confidence
- [Using Floating Point Numbers as Hash Keys — Read after Write](https://readafterwrite.wordpress.com/2017/03/23/how-to-hash-floating-point-numbers/) — MEDIUM confidence
- [Reproducible Floating-Point Aggregation in RDBMSs (arXiv)](https://arxiv.org/pdf/1802.09883) — MEDIUM confidence
- Internal: `.planning/workstreams/sgproc-render/phases/09-processor-pass-graph-conformance-suites/09-RESEARCH.md` — HIGH confidence (primary codebase source, ground truth for existing fixture/harness/hashing infra)
- Internal: `.planning/workstreams/sgproc-render/REQUIREMENTS.md` (ARTF-01..06, TEST-01..10, DETV-01..03) — HIGH confidence (existing shipped requirements, ground truth)
- Internal: `.planning/PROJECT.md` (v2.1 target features, deferred candidates) — HIGH confidence (milestone scope, ground truth)

---
*Feature research for: Cross-hardware deterministic hashing of SGProcessingManager job outputs (v2.1 sgproc-render)*
*Researched: 2026-08-07*
