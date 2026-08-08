# Project Research Summary

**Project:** sgproc-render workstream v2.1 Cross-Hardware Hash Tolerance
**Domain:** Deterministic-output verification engineering -- quantization-before-hashing for cross-GPU-vendor/cross-driver/CPU-vs-GPU floating-point divergence in SGProcessingManager render + MNN inference job pipelines
**Researched:** 2026-08-07
**Confidence:** MEDIUM-HIGH (architecture/pitfalls grounded in direct repo reads at HIGH confidence; stack/features technique choices at MEDIUM confidence via cross-checked web sources -- no GNUS-specific prior art exists for this exact problem)

## Executive Summary

This is not a pick-a-library milestone -- it is a from-scratch, small-surface-area correctness problem: make sha256()-based job-result hashes tolerant of legitimate cross-hardware floating-point noise (different GPU vendors, drivers, CPU-vs-GPU MNN backends) while staying sensitive enough to reject a genuinely wrong or substituted result. All four research passes converge on the same shape of solution: a small quantization/canonicalization pre-pass, inserted immediately before each of the existing sha256() call sites, using a fixed (not schema-configurable) precision derived empirically from real cross-machine capture data -- not guessed from general floating-point intuition. There is no external dependency to add; this is a roughly 20-line utility library mirroring the existing sgprocmanagersha pattern.

The architecture research corrects the milestone own framing: there are not one but around 27 sha256() call sites, and the cross-node-authoritative hash (chunkhashes / SubTaskResult::chunk_hashes(), consumed by ProcessingValidationCore) is populated deep inside each of 14 processor classes during StartProcessing(), not in ProcessingManager.cpp later artifact-building code. Quantization must be inserted at the point where each processor already knows its own output true type -- float32 for all 13 MNN processors (regardless of their declared DataType label) and uint8 RGBA8/RGB8 for the render path (which has no float color-attachment format reachable today). This is a bimodal problem (float canonicalization plus quantization vs. integer tolerance-banding), not a 13-way or metadata-dispatched one, and the correct build order is: capture harness (with quantization as a no-op stub), then diff tool, then run on 3 or more real machines, then derive the tolerance from that data, then implement real quantization, then re-validate.

The single most important risk, surfaced independently by both PITFALLS and STACK research, is that a tolerance loose enough to absorb real cross-hardware noise is, by construction, loose enough to also absorb a wrong or adversarially-crafted result -- this is the central design tension of the milestone, not a side effect. The milestone literal acceptance criterion (hashes match across 3 or more machines) only proves the tolerance is not too tight; it says nothing about whether it is too loose. A second, independent wrong-result-still-diverges counter-test is required and must not be treated as optional. Secondary risks: forgetting that quantization must cover both the per-chunk hash and the post-stitch/combined hash (stitching arithmetic is itself non-associative float math and re-introduces the exact problem one level up), and reusing the codebase existing but unrelated ProcessingDatatypesTest CPU-vs-Vulkan tolerance (1e-3/1e-2) as if it answers this cross-machine question -- it does not, it was tuned for a different divergence source.

## Key Findings

### Recommended Stack

No external library is being added. The recommended approach is a from-scratch, roughly 20-line quantization utility (sgprocmanagerquant, mirroring the existing sgprocmanagersha CMake/namespace pattern exactly) with two functions: QuantizeFloatBuffer (IEEE-754 canonicalization of NaN/Inf/signed-zero/denormals, then scale-round-cast to a fixed-precision integer grid, for all MNN float output) and QuantizeUnorm8Buffer/QuantizeByteBuffer (simple integer shift/mask or divide-round-multiply tolerance-banding, for render already-8-bit-UNORM readback bytes). Both existing 8-bit render formats mean the render path has zero float/NaN/denormal concerns -- it is a pure integer-domain problem and must not be routed through the float-quantization machinery. ULP (Unit-in-Last-Place) distance is the right metric for the diff tool (reporting how far apart two values are) but is explicitly the wrong tool for the hash transform itself, since it is a comparison metric between two values, not a canonicalizing single-value function. Endianness is a verified non-issue -- every current and roadmapped platform is little-endian.

**Core technologies:**
- sgprocmanagerquant (new, from-scratch utility library): float canonicalization plus scale-round-cast quantization -- purpose-built for hash-tolerance, no existing OSS library targets this exact problem (ML-quantization libraries like TensorRT PTQ target model-weight compression, a different problem with different tolerance semantics)
- cmath (std::isnan/std::isinf/std::signbit, std::lround), already C++17 project standard -- used for the canonicalization/rounding primitives, no new dependency
- Existing sgprocmanagersha::sha256() -- stays completely unmodified; quantization is a pre-processing step, not a hash-function change
- Existing artifact_serializer.hpp/.cpp (SerializeArtifact/SerializeManifest) -- directly reused as the capture file metadata plus hash format, avoiding a second serialization convention

### Expected Features

Three internal developer tools, not consumer features: (1) capture harness, (2) diff tool, (3) quantization step. Table stakes here means what is required for the literal success bar -- post-quantization hashes matching across 3 or more machines on Phase 09 existing test fixtures -- to be achievable and trustworthy.

**Must have (table stakes):**
- Capture harness: full raw per-element output dump plus combined hash plus chunk hashes plus machine-identity tag, run against Phase 09 existing render/MNN fixtures (do not build new fixtures)
- Diff tool: max absolute delta, max relative delta, max ULP distance, percentage-of-elements-exceeding-threshold, over two or more capture files
- Quantization step: one fixed rounding rule for image/texture (uint8) output, one fixed rounding rule for numeric tensor (float) output, applied identically pre-hash on both the per-chunk and post-stitch/combined hash inputs on both render and MNN paths, using a deterministic (not ambient-FPU) rounding mode
- Empirical validation run across 3 or more real machines (user Mac plus PC plus one more) confirming post-quantization combined-hash match on the test fixtures -- this is the literal success bar

**Should have (competitive/debuggability):**
- Standalone CLI/CTest-invokable capture harness, runnable manually outside a full CI cycle
- Histogram of per-element differences plus outlier localization (top-N divergent element coordinates) -- valuable once a first real cross-machine run needs debugging, not just confirmation
- Machine-readable (JSON) diff report alongside human-readable summary

**Defer (v2.2+):**
- Schema-configurable per-data-type quantization precision -- explicitly locked out of this milestone scope; the one legitimate carve-out (one constant for image output, one for tensor output) must stay hardcoded, not become a schema knob
- Per-channel/per-region diff breakdown for structured render output
- Any fix to ProcessingValidationCore::ValidateResults known concatenation bug, or actual cross-node consensus/redundant-execution plumbing -- this milestone only proves the hash itself can be tolerant; it explicitly does not wire that tolerance into production multi-node comparison

### Architecture Approach

Quantization must be inserted inside each of the 14 processor classes (13 MNN plus 1 render), immediately before their existing sha256() calls -- not centrally in ProcessingManager.cpp later artifact-building code, because the cross-node-authoritative chunkhashes field is already finalized before that code ever runs. The problem is bimodal (float canonicalization plus quantization for all MNN types, since every MNN processor reads its tensor via host<float>() regardless of declared DataType; integer tolerance-banding for render uint8 RGBA8/RGB8 readback), not a 13-way per-DataType or metadata-dispatched problem. Within MNN, 6 stitched types (Float/Int/Mat2/Mat3/Mat4/Tensor) need 2 quantization insertion points (chunk plus post-average combined hash); 7 chained types need only 1 (their combined hash is a pure hash-of-hashes downstream of the already-quantized chunk hash) -- 20 total insertion points, not 26.

**Major components:**
1. sgprocmanagerquant (new utility library, include/util/quantization.hpp plus src/util/quantization.cpp) -- the one shared quantization logic, called at all 20 insertion points; mirrors sgprocmanagersha existing structure exactly
2. ExecutionContext (existing, gets one new optional field) -- the extension point for a new opt-in rawOutputCapture callback, following the same no-op-by-default pattern already used for progressCallback; avoids touching the stable 6-argument StartProcessing() virtual interface implemented by 14 classes
3. tools/capture/ (new top-level dir, NOT under test/) -- capture_harness and capture_diff standalone CLI executables, not CTest-gated (a meaningful pass/fail requires 2 or more physical machines, which CTest cannot express); reuses SerializeArtifact/SerializeManifest for the capture file metadata plus hash section, appending one new raw-bytes section that does not exist anywhere in the codebase today
4. test/capture/ (new, thin GTest smoke test) -- asserts only that the harness runs and produces a well-formed, round-trippable file; explicitly does not assert cross-machine hash equality

### Critical Pitfalls

1. A tolerance loose enough for legitimate cross-hardware noise is loose enough for a wrong/malicious result -- the central risk of the milestone, not a side effect. Prevention: always pair the matches-across-3-or-more-machines empirical test with an explicit deliberately-wrong-result-still-diverges counter-test; never accept a tolerance validated only against the first test.
2. Naive decimal-rounding corrupts NaN/Inf/denormals/signed-zero in hardware/compiler-dependent ways, silently reintroducing the exact cross-machine divergence quantization exists to eliminate. Prevention: canonicalize these special values to one fixed representative bit pattern before any rounding arithmetic, as an explicit first branch -- never as an assumed side effect of the rounding formula.
3. Quantizing only the most visible hash call site (e.g. only the final combined hash) while leaving per-chunk hashes and/or ComputeArtifactIdentity() independent re-hash of the same bytes unquantized. Prevention: enumerate all roughly 4 structurally distinct hash-call-site layers as a mandatory checklist (chunk hash, per-processor final hash, ComputeArtifactIdentity, plus deliberately-excluded model-identity/manifest hashes that must stay exact) and cover every one, using identical quantization logic wherever two layers re-hash the same logical bytes.
4. Treating uint8 image bytes and float32 tensor bytes with the same quantization logic -- a category error in both directions (decimal rounding is meaningless on already-integer UNORM8 data; integer-delta tolerance is meaningless on tensors spanning many orders of magnitude). Prevention: branch quantization strategy explicitly on declared data type/format, decided inside each processor where the type is already known.
5. Choosing the quantization constant before real capture data exists (guessing eight decimal places should be safe from general float knowledge), or reusing the pre-existing but unrelated ProcessingDatatypesTest COV-01 tolerance (1e-3/1e-2, tuned for same-machine CPU-vs-Vulkan divergence, a different phenomenon). Prevention: sequence capture-harness-first, derive the constant solely from that tool actual cross-machine max-delta/mantissa-bit-diff output, and document the derivation with reference to real captured numbers.

## Implications for Roadmap

Based on research, suggested phase structure (research strongly implies a specific dependency order -- quantization precision literally cannot be chosen before capture data exists):

### Phase 1: Capture Harness plus Diff Tool (quantization as no-op stub)
**Rationale:** The quantization constant is an empirical hyperparameter, not a research-resolvable question -- it must be derived from real Mac/PC/third-machine divergence data. Building the harness plus diff tool first (with quantization wired in as an identity/placeholder function) validates all the invasive plumbing (14 processor files plus ExecutionContext field) once, in a form that will not need to be revisited when the real precision constant lands later.
**Delivers:** tools/capture/capture_harness.cpp, tools/capture/capture_diff.cpp, ExecutionContext::rawOutputCapture field, capture file format (existing SerializeArtifact/SerializeManifest plus new raw-bytes section), thin CTest smoke test.
**Addresses:** Capture Harness plus Diff Tool table-stakes features from FEATURES.md (raw dump, combined hash, chunk hashes, machine-identity tag, max/relative/ULP delta, exceeding-count).
**Avoids:** Pitfall 6 (capture harness must hook the literal pre-hash bytes, not output_buffers/Artifact copies made downstream of the hash call) and Pitfall 7 (must re-verify same-node stability on each machine before any cross-machine diff data is trusted).

### Phase 2: Empirical Cross-Machine Capture Run
**Rationale:** This is the actual data-gathering step the whole milestone precision decision depends on -- not a research activity but a required, hands-on step (run harness on user Mac plus PC plus a third machine, diff pairwise).
**Delivers:** Real max-delta/relative-delta/ULP-distance/mantissa-bit-difference statistics per output type (render uint8, MNN float/tensor), confirmed same-node stability per machine.
**Uses:** Phase 1 harness/diff tool exclusively; no new code.

### Phase 3: Quantization Implementation (real precision, both paths)
**Rationale:** Only now is there real data to justify a fixed precision constant. This phase both implements the real QuantizeFloatBuffer/QuantizeByteBuffer logic and, critically, must add the wrong-result-still-diverges security counter-test alongside the cross-machine match validation, since research flags this as the milestone central, non-optional risk.
**Delivers:** sgprocmanagerquant library (canonicalization plus scale-round-cast for MNN float paths; integer tolerance-banding for render), inserted at all 20 identified call sites (13 MNN chunk plus 6 MNN stitched-combined plus 1 render), with unit tests covering NaN/Inf/denormal/signed-zero edge cases.
**Implements:** ARCHITECTURE.md Pattern 2/3 (quantize inside each processor at existing hash call sites; one shared utility, not N bespoke implementations).

### Phase 4: Re-Validation plus Documentation of Scope Boundary
**Rationale:** The milestone acceptance criterion is explicitly the last step, not assumed from source-level reasoning -- re-run the full 3-or-more-machine capture plus diff cycle with real quantization active to confirm hashes now match, and re-run the wrong-result counter-test at the final chosen precision.
**Delivers:** Confirmed 3-or-more-machine matching post-quantization hashes on test fixtures; documented, capture-data-cited precision constant; explicit written boundary that this milestone makes hash comparison tolerant, not verification or consensus (the ValidateResults bug and cross-node plumbing remain out of scope and unfixed).

### Phase Ordering Rationale

- Capture-before-quantize is not a preference, it is a hard dependency the STACK, ARCHITECTURE, and PITFALLS research all independently converge on (PITFALLS Pitfall 8 explicitly warns against reversing or blurring this order under implementation pressure).
- The wrong-result-still-diverges counter-test must be built into Phase 3/4, not treated as a stretch goal -- PITFALLS research frames this as the single most important thing to get right, not a nice-to-have.
- Grouping all 20 processor-file insertion points into one phase (rather than splitting MNN vs. render across phases) matches ARCHITECTURE finding that this is fundamentally one mechanical change pattern (one shared utility, many call sites) rather than two separately-evolving subsystems.

### Research Flags

Phases likely needing deeper research during planning:
- Phase 3 (Quantization Implementation): exact scale/precision constant is not resolvable from Phase 2 data alone in a purely mechanical way -- deciding the image-vs-tensor precision split and the rounding-mode implementation details will benefit from a research-phase pass focused specifically on the NaN/Inf/denormal canonicalization unit-test design and the wrong-result counter-test construction.

Phases with standard patterns (skip research-phase):
- Phase 1 (Capture Harness plus Diff Tool): architecture is fully specified already (file:line level) by this milestone own research -- mirrors existing sgprocmanagersha/artifact_serializer conventions closely enough that no further research is needed.
- Phase 2 (Empirical Capture Run): an execution/data-gathering step, not a design question.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM | Web-search-only for the quantization technique itself (no library exists to verify against); elevated from LOW via cross-checking 11 queries and 3 papers converging on the same conclusion. Repo-integration facts (call sites, existing hash function) are HIGH via direct source read. |
| Features | MEDIUM | Cross-checked against Vulkan CTS, ONNX Runtime, FLiT literature and standard image-diff tooling; no GNUS-specific or exact-domain prior art exists, so feature landscape is inferred by analogy rather than verified against an identical precedent. |
| Architecture | HIGH | Every claim is a direct source read with file:line citations against the current tree; no external sources were needed for this section. |
| Pitfalls | HIGH (repo-grounded) / MEDIUM (general FP/GPU-determinism findings) | Repo call-site enumeration and existing tolerance-convention findings are direct-source-read HIGH confidence; general floating-point/security-tension findings are web-search MEDIUM confidence, cross-checked across independent sources. |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address

- Exact quantization scale/precision constant: genuinely not resolvable by research -- explicitly deferred to Phase 2 empirical capture data by design, not a gap to close before roadmap creation.
- Whether MNN_Bool float-encoded 0.0/1.0 output needs any rounding at all (it may already be quantization-tolerant by construction, unlike genuinely continuous MNN_Float/MNN_Tensor outputs) -- STACK/ARCHITECTURE flag this as worth empirically checking via the capture harness rather than assuming a priori; not a blocker, just something Phase 2 data should confirm.
- Whether any MNN backend/thread-pool configuration introduces same-node nondeterminism not yet proven under DETV-01/02 original (render-specific) guarantee -- PITFALLS Pitfall 7 flags this as unverified for MNN specifically; Phase 1/2 should extend the existing N-greater-or-equal-10 same-node repeat-run check to the MNN path before trusting any cross-machine diff data involving it.

## Sources

### Primary (HIGH confidence)
- Direct repository reads: SGProcessingManager/src/util/sha256.cpp, all around 17 processing_processor_mnn star cpp files, processing_processor_render.cpp, ProcessingManager.cpp, artifact_types.hpp, artifact_serializer.hpp, execution_context.hpp, ProcessingValidationCore (SuperGenius/src/processing/processing_validation_core.cpp), generated/ColorFormat.hpp, generated/DepthFormat.hpp, ProcessingDatatypesTest (COV-01)
- .planning/workstreams/sgproc-render/phases/09-processor-pass-graph-conformance-suites/09-RESEARCH.md, .planning/workstreams/sgproc-render/REQUIREMENTS.md, .planning/PROJECT.md -- milestone scope, deferred candidates, existing requirements ground truth

### Secondary (MEDIUM confidence)
- Bruce Dawson (randomascii.wordpress.com), bitbashing.io -- canonical ULP-based float-comparison references
- arXiv 2408.05148 (FP non-associativity/reproducibility), arXiv 2501.05374 (decentralized GPU validation), arXiv 2510.16028 (TAO tolerance-aware optimistic verification), arXiv 2606.00279 (bit-exact AI inference verification) -- cross-hardware divergence mechanisms and the tolerance-vs-security tension
- BOINC / Einstein at Home validator behavior (FTLOScience summary, arXiv 1207.7176) -- real-world redundant-computation tolerance precedent
- Vulkan/OpenGL CTS, ONNX Runtime backend tests, FLiT framework, PerceptualDiff/ImageMagick -- reference systems for capture/diff tool design patterns

### Tertiary (LOW confidence)
- None flagged -- all research sources were cross-checked to at least MEDIUM confidence; no single-source, unverified claims were used as load-bearing conclusions.

---
*Research completed: 2026-08-07*
*Ready for roadmap: yes*
