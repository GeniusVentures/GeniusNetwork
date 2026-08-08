# Stack Research

**Domain:** Cross-hardware deterministic hashing of SGProcessingManager job outputs — quantization/rounding step applied before SHA-256, tolerant of legitimate GPU-vendor/driver and CPU-vs-GPU floating-point divergence, still sensitive to genuinely wrong/malicious results
**Researched:** 2026-08-07
**Confidence:** MEDIUM (websearch-only research, cross-checked across 11 queries and 3 fetched papers; elevated from the seam's LOW baseline via `classify-confidence --verified` because multiple independent sources — Bruce Dawson/bitbashing.io canonical FP-comparison references, BOINC/Einstein@Home real production validator behavior, and 2025-2026 arxiv decentralized-GPU-verification papers — converge on the same conclusions; no Context7/library-docs lookup was applicable because the recommended technique is a from-scratch algorithm, not a versioned library)

## Context Recap (ground truth already established by direct code inspection, not re-derived from research)

- **Single generic hash function**, unchanged by this milestone's needs: `sgns::sgprocmanagersha::sha256(const void* data, size_t dataSize)` in `SGProcessingManager/src/util/sha256.cpp`, backed by OpenSSL `EVP_sha256` (pre-existing dependency, no version action needed this milestone).
- **~30 call sites** across `SGProcessingManager/src/processors/processing_processor_mnn_{float,mat2,mat3,mat4,tensor,vec2,vec3,vec4,bool,int,string,image,texture1d,texturecube,volume,buffer}.cpp` plus one in `processing_processor_render.cpp`. Every MNN processor — **including the semantically-integer/string/bool ones** (`mnn_bool.cpp`, `mnn_int.cpp`, `mnn_string.cpp`) — reads MNN's raw tensor output as `const float *data = procresults->host<float>()` **before** any per-type reinterpretation, confirmed by direct grep of every `host<...>()` call site. This means the hash input at every MNN call site is IEEE-754 `float32`, with zero exceptions, and a single shared quantization helper covers all of them.
- Each MNN processor hashes **twice**: once per-chunk on the raw patch output (`sha256(data, dataSize)`), and once on a **stitched/averaged** full-tensor buffer (`stitchedOutput`, built via float accumulation `+=` across overlapping patches then divided by accumulated weights) before `sha256(stitchedStr...)`. The stitching arithmetic itself is a second, independent source of cross-hardware association-order divergence (floating-point addition is not associative), so **both** hash inputs need quantization, not just the raw per-chunk one.
- The render path's hashed output (`processing_processor_render.cpp:2156`, `result.hash = sha256(readbackBytes.data(), readbackBytes.size())`) is **not raw float data**. `generated/ColorFormat.hpp` defines only `enum class ColorFormat { RGB8, RGBA8 }` — confirmed the only color-attachment formats the schema supports are 8-bit-per-channel UNORM (already-integer, already-quantized by the GPU's fixed-function output-merger/ROP stage). `Readback()` only copies the **color** attachment (`ColorFormatByteSize(target.get_color_format())`); the depth attachment (which *can* be `D32_SFLOAT`, a real float format, per `generated/DepthFormat.hpp`) is never read back or hashed. **This changes the render-path problem from "canonicalize IEEE-754 floats" to "tolerance-band 8-bit integers"** — the residual cross-hardware risk there is a fragment-shader float computation landing on a different side of the float→UNORM8 rounding boundary on different vendors' ROP hardware, not raw float bytes reaching the hash.

## Recommended Stack

### Core Technique — from-scratch algorithm, no external dependency

| Technique | Applies To | Purpose | Why This Is The Right Choice For This Problem |
|-----------|-----------|---------|------------------------------------------------|
| **IEEE-754 canonicalization pre-pass** (`std::isnan`/`std::isinf`/`std::signbit` from `<cmath>`, C++17 — already the project's language standard) | All ~15 MNN float-output processors | Replace NaN with one fixed sentinel value, force `-0.0f → +0.0f`, clamp/flush subnormals to `0.0f`, before any rounding | GPUs commonly flush-to-zero (FTZ) subnormals in hardware while CPU paths (MNN's CPU backend, used for capability-check fallback comparisons) may not — this is a real, cheap-to-hit divergence source distinct from rounding noise. NaN bit-patterns are not unique (any nonzero mantissa with all-1s exponent qualifies) and `NaN != NaN`, so re-hashing a NaN's *raw* bits is not "canonical" in any useful sense — mapping to one sentinel value removes the ambiguity entirely rather than attempting to pick "the" canonical NaN encoding (there isn't one that's meaningfully more correct than a fixed sentinel for this use case). |
| **Fixed-point/integer quantization via scale-round-cast** — `int32_t q = static_cast<int32_t>(std::lround(x * scale))`, scale = a power-of-two or power-of-ten chosen empirically (see "Scale Selection" below) | Same ~15 MNN float-output processors, applied to **both** the per-chunk and the post-stitch buffer | Collapses float32's ~7-decimal-digit precision down to a coarser integer grid wide enough to absorb legitimate cross-hardware rounding noise (empirically ~1e-5 to 1e-3 relative, per BOINC/Einstein@Home and general HPC-reproducibility literature) while still being fine enough to flag a genuinely wrong/malicious result | This is the standard, well-understood technique for "make a float value tolerant to small deviations before it enters an exact-match comparison" — multiply into an integer grid, round, hash the integer. No widely-adopted OSS library exists specifically for "quantize-then-hash for verification" (searched; existing OSS quantization libraries — TensorRT PTQ, ONNX quantization tooling, etc. — target *model-weight compression for inference speed/size*, a completely different problem with different error tolerances and no relevance to output-hashing). Round-to-nearest (not truncation) must be used, and the rounding mode should be `round-half-away-from-zero` (`std::lround` behavior) applied consistently everywhere — `round-half-to-even` also works but the two must not be mixed. |
| **Coarser integer tolerance-banding** — `uint8_t q = (byte >> shiftBits) << shiftBits` or `uint8_t q = static_cast<uint8_t>(std::lround(byte / bandWidth) * bandWidth)` | The render path's `readbackBytes` (already-UNORM8 RGB8/RGBA8) | Absorbs ±1-2 LSB divergence in the fixed-function output-merger's float→UNORM8 rounding across GPU vendors, without touching IEEE-754 semantics at all (there are none left at this stage — it's already an 8-bit integer) | Because the render path's schema only ever supports RGB8/RGBA8 output, there is **no float parsing, no NaN/Inf/signed-zero/denormal concern, and no ULP concept** at this stage — it is a pure integer-domain problem, and needs a much simpler technique than the MNN float path. Treating it with the same quantize-float machinery as MNN would be over-engineering; a shift/mask or divide-round-multiply on the raw bytes is sufficient and keeps the two paths honestly reflecting their actual data types. |

### Supporting technique — used in the diff tool, not in the hash itself

| Technique | Applies To | Purpose | Why |
|-----------|-----------|---------|-----|
| **ULP (Unit-in-Last-Place) distance** | The "diff tool comparing capture files across machines" v2.1 target feature (per-element divergence stats: max delta, mantissa-bit differences) | Report *how far apart* two float values are in representable-value steps, as a debugging/tuning signal | ULP distance is a **comparison metric between two already-computed values**, not a deterministic single-value transform — it cannot itself produce a hashable canonical value, so it is the wrong tool for the hash-tolerance problem but exactly the right tool for the separate diff-tool deliverable. Use it there to empirically justify the scale-factor choice in the quantization step (see below), and note per the research that ULP tolerance is not uniform across operations — basic add/mul are typically within 0.5-2 ULP of the correctly-rounded result on modern GPUs/CPUs, but transcendentals (`sin`/`cos`/`exp`/`log`, used inside MNN activation functions) rely on vendor-specific polynomial/Remez approximations and can diverge by many more ULPs cross-vendor — so a fixed decimal-quantization scale is a safer, simpler tolerance mechanism for the hash than trying to track per-operation ULP budgets across an entire tensor. |

### Endianness — verified non-issue, not something to build for

| Concern | Finding |
|---------|---------|
| Byte order of `float*`/`uint8_t*` buffers fed to `sha256()` | Every currently-supported and roadmapped SGProcessingManager platform (Windows/Linux/macOS x86-64 and Apple-Silicon ARM64 desktop, per v1.0; Android arm64-v8a/armeabi-v7a and iOS arm64, per the in-flight MOBILE-01..06 requirements) is little-endian. `memcpy`-based native serialization of the quantized `int32_t`/`uint8_t` buffers is therefore safe today and does not need an explicit byte-swap/endian-normalization step. Flag this as verified-and-closed rather than adding defensive big-endian-safe serialization code that has no real target to protect against — that would be scope creep against a platform matrix that does not include any big-endian target. |

## What NOT to Add

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| A full deterministic-ML-inference framework (batch-invariant/order-invariant custom kernels, e.g. the Tree-Based Invariant Kernel pattern or vLLM/Thinking-Machines-Lab-style deterministic-inference work) | These achieve bit-exact reproducibility by **replacing MNN's actual compute kernels** to force a fixed reduction order — this means owning/forking MNN's `MNN_FORWARD_VULKAN` backend internals, which directly contradicts the "no new GPU backend, no duplicate platform setup" constraint this workstream has held since v1.0, and is a wildly disproportionate lift for a milestone whose actual goal is a *tolerant hash for job verification*, not bitwise ML reproducibility. Even when achieved, these techniques still only guarantee determinism within one vendor's kernel family, not literally cross-vendor (NVIDIA vs AMD vs Apple GPU vs CPU fallback) — so it wouldn't even fully solve this milestone's stated goal. | The lightweight post-hoc quantization pass above, applied to whatever float output MNN already produces, regardless of which kernel implementation produced it. |
| A TAO-style (arxiv 2510.16028) per-operator IEEE-754 error-bound + Merkle-anchored dispute-game verification framework, or a full trustless/probabilistic GPU-validation consensus framework (arxiv 2501.05374) | Both target the **cross-node comparison/consensus mechanism** — explicitly out of scope for this milestone per `PROJECT.md` ("the actual cross-node comparison plumbing is explicitly OUT of scope this milestone") and per the known `ProcessingValidationCore::ValidateResults` concatenation bug, which this milestone deliberately does not fix. These are the right shape of solution for a **future** milestone that actually builds the on-chain-style consensus check (successor to today's `XNODE-01`), not for making a single node's hash itself tolerant. | Ship the quantization step now (single-node, deterministic, cheap); revisit per-operator tolerance-region/dispute-game designs only once the cross-node comparison plumbing itself is scheduled. |
| BOINC/Einstein@Home-style redundant-computation-with-scalar-tolerance validators | Same reason as above — this is a **multi-node comparison mechanism** (run on ≥2 hosts, compare a derived scalar within an application-defined tolerance, escalate to a third host on disagreement), which is exactly the deferred cross-node plumbing, not a single-node hash-preprocessing technique. | N/A for this milestone; worth revisiting as a *design reference* (not a library — BOINC's validator logic isn't a reusable dependency) once cross-node comparison is actually built. |
| A general NN-quantization library or framework (TensorRT PTQ, ONNX Runtime quantization tooling, GPTQ/AWQ-style weight quantizers) | These quantize **model weights** for inference speed/memory, an entirely different problem (accuracy-vs-compression tradeoff on trained parameters) with different tolerance semantics than quantizing **output activations for hash-tolerance**. Pulling one in would add a large, wrong-shaped dependency for a ~20-line integer-rounding utility. | The from-scratch scale-round-cast function above. |
| Schema-configurable, per-data-type-tunable quantization precision | `PROJECT.md` v2.1 scope is explicit: "Quantization/rounding step applied before hashing (render + MNN output paths), fixed precision — not schema-configurable this milestone." Building a tunable system now is scope creep against an explicitly deferred requirement. | One fixed scale constant for the MNN float path, one fixed band-width constant for the render UNORM8 path, both chosen empirically per "Scale Selection" below and hard-coded, not schema-driven. |
| A dedicated "canonical IEEE-754 serialization" library | Searched specifically for this; no widely-adopted OSS library targets "canonicalize a float buffer for hash-stability" as its own product — this is a small enough primitive (NaN/Inf/signed-zero/denormal handling via `<cmath>` + the scale-round-cast step) that every real-world reference found (HPC reproducibility papers, GPU-verification arxiv papers, BOINC validators) implements it inline rather than depending on a shared library for it. | Implement the ~10-15 line canonicalization + quantization helper directly in `SGProcessingManager/src/util/`. |

## Integration With The Existing Single `sha256()` Call Site Pattern

The existing `sgns::sgprocmanagersha::sha256(const void*, size_t)` function **stays exactly as-is** — it remains a pure, generic byte hasher with zero float-awareness, preserving its reuse across every processor. The new capability is a small preprocessing utility inserted **before** each existing hash call, not a change to hashing itself:

```cpp
// New: SGProcessingManager/include/util/output_quantize.hpp + src/util/output_quantize.cpp
namespace sgns::sgprocquant
{
    // Canonicalizes NaN/Inf/signed-zero/denormals, then quantizes each float to a
    // fixed-point integer grid (scale is a milestone-fixed constant, not schema-configurable).
    // Returns a byte buffer safe to feed directly into sgprocmanagersha::sha256().
    std::vector<uint8_t> QuantizeFloatBuffer( const float *data, size_t count, float scale );

    // Coarser integer tolerance-banding for already-integer (UNORM8) render readback bytes.
    // No float canonicalization needed -- this is a pure integer-domain operation.
    std::vector<uint8_t> QuantizeUnorm8Buffer( const uint8_t *data, size_t size, uint8_t shiftBits );
}
```

Call-site change pattern (illustrative, applies identically at every MNN processor's **two** hash calls — the per-chunk one and the post-stitch one — and at the render processor's one hash call):

```cpp
// Before (current, e.g. processing_processor_mnn_float.cpp:307):
auto hash = sgprocmanagersha::sha256( data, dataSize );

// After:
auto quantized = sgprocquant::QuantizeFloatBuffer( data, procresults->elementSize(), kOutputQuantScale );
auto hash      = sgprocmanagersha::sha256( quantized.data(), quantized.size() );
```

```cpp
// Before (current, processing_processor_render.cpp:2156):
result.hash = sgns::sgprocmanagersha::sha256( readbackBytes.data(), readbackBytes.size() );

// After:
auto quantized = sgns::sgprocquant::QuantizeUnorm8Buffer( readbackBytes.data(), readbackBytes.size(), kRenderQuantShiftBits );
result.hash    = sgns::sgprocmanagersha::sha256( quantized.data(), quantized.size() );
```

This is a **~30-call-site mechanical change** (one new small utility library + a one-line insertion before every existing `sha256(...)` call in the MNN and render processors), not a redesign of the hashing/artifact/`ProcessingResult` pipeline. `ARTF-03`'s content-hash/chunk-hash shape and `RENDER-08`'s "feeds the existing `ProcessingResult` → hash path unmodified" guarantee both continue to hold — only the *bytes fed into* the existing hash path change, never the path's shape.

**Important correctness note surfaced by this integration review:** both hash calls at each MNN site must go through quantization, not just the raw per-chunk one — the `stitchedOutput` accumulation (`+=` across overlapping patches, then divided by `stitchedWeights`) is itself float arithmetic whose association order could plausibly differ by hardware/compiler, so skipping quantization on the second (`subTaskResultHash`) call would silently reintroduce the exact problem this milestone sets out to fix, just one level up.

## Scale Selection — Not A Research Question, An Empirical One

The exact scale constant (e.g. is 1e3, 1e4, or a power-of-two like 2^10/2^12 the right grid width) is **not resolvable by external research alone** — it is a hyperparameter that must be picked from the actual observed cross-hardware divergence on real GPUs, which is precisely what v2.1's *first two* target features already produce:

1. The **cross-hardware capture test harness** (dumps raw output values + hashes per run across machines) generates the actual divergence data.
2. The **diff tool** (per-element max delta, mantissa-bit/ULP differences) quantifies exactly how many bits/decimal-places of noise are present on real hardware (user's Mac + PC at minimum, per the v2.1 "Empirically validated" requirement).

Only after those two artifacts exist can the scale constant be chosen correctly: wide enough to swallow the measured noise floor (general HPC-reproducibility literature and BOINC/Einstein@Home production validators both report legitimate cross-hardware float divergence in the ~1e-5 to 1e-3 relative range for well-behaved numerical code — not itself proof of this project's actual number, but a reasonable prior to sanity-check the harness's measurements against), narrow enough that a genuinely wrong or malicious result (which would typically diverge by orders of magnitude more, not by rounding-noise amounts) still produces a different hash. Do not hard-code a scale from a research citation — validate it against this project's own captured data.

## Pitfalls To Design Around (feed into `PITFALLS.md`, flagged here for the integration point)

- **Rounding-boundary flips:** a value like `2.49999997` (GPU A) vs `2.50000003` (GPU B) rounds to different integers at a quantization boundary despite being effectively the same value — inherent to any quantize-then-compare scheme, not fully eliminable, only made statistically rare by picking a scale coarse enough relative to the real noise floor.
- **NaN/Inf handling must be decided once, not per-processor:** since all ~15 MNN processors share the same `host<float>()` pattern, the sentinel-value choice for NaN/Inf must live in the shared `QuantizeFloatBuffer` helper, not be reinvented per call site, or the "same-node determinism" guarantee already proven for `DETV-01` could regress if two processors canonicalize differently.
- **Do not let quantization mask genuinely wrong results:** the entire point of "sensitive enough to catch genuinely wrong/malicious results" is that the scale must stay tied to the *empirically measured* legitimate-noise floor (from the capture+diff harness), not be chosen generously "to be safe" — an overly coarse scale is a security regression (a wrong/malicious result within the (too-wide) tolerance band would silently hash-match).

## Sources

- Bruce Dawson, "Comparing Floating Point Numbers, 2012 Edition" (randomascii.wordpress.com) — canonical reference on ULP-based comparison and why naive epsilon tolerances are wrong (WebSearch, MEDIUM confidence)
- bitbashing.io, "Comparing Floating-Point Numbers Is Tricky" — corroborating reference on float-comparison pitfalls (WebSearch, MEDIUM confidence)
- Direct3D floating-point rules / Intel ULP documentation / MathWorks ULP docs — hardware ULP-tolerance standards (0.5-2 ULP for basic ops, wider for transcendentals) (WebSearch, MEDIUM confidence)
- BOINC/Einstein@Home validator behavior (via FTLOScience summary + arxiv 1207.7176) — real-world production redundant-computation tolerance-based validation, closest existing analog to this project's eventual cross-node consensus check (WebSearch, MEDIUM confidence)
- arxiv 2408.05148, "Impacts of floating-point non-associativity on reproducibility for HPC and deep learning applications" — confirms non-associativity as the root cause of cross-hardware/cross-run float divergence, with divergence magnitude data (WebSearch, MEDIUM confidence)
- arxiv 2501.05374, "Validation of GPU Computation in Decentralized, Trustless Networks" — confirms exact bit-exact recomputation fails across GPU nodes in production decentralized-compute systems; probabilistic/consensus verification is the current state of the art for the (out-of-scope-this-milestone) cross-node comparison problem (WebFetch, MEDIUM confidence)
- arxiv 2510.16028, "TAO: Tolerance-Aware Optimistic Verification for Floating-Point Neural Networks" — per-operator IEEE-754 error-bound + empirical-percentile + dispute-game approach; confirms no production system quantizes-then-hashes at the field level, informing the "what NOT to add" guidance (WebFetch, MEDIUM confidence)
- arxiv 2606.00279, "Bit-Exact AI Inference Verification Without Performance Tradeoffs" — confirms bitwise-exact reproduction is achievable via software FP emulation without special hardware, but only within a matched vendor/kernel path, not literally cross-vendor — informs scope boundary for "what NOT to add" (WebFetch, MEDIUM confidence)
- Direct repository inspection: `SGProcessingManager/src/util/sha256.cpp`, all ~17 `processing_processor_mnn_*.cpp` files, `processing_processor_render.cpp`, `generated/ColorFormat.hpp`, `generated/DepthFormat.hpp` (direct tool use, HIGHEST confidence — ground truth for this repo's actual integration surface)

---
*Stack research for: cross-hardware hash-tolerance quantization step, SGProcessingManager render + MNN output paths, workstream `sgproc-render` v2.1*
*Researched: 2026-08-07*
