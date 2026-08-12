# Phase 12: Quantization / Normalization Implementation - Context

**Gathered:** 2026-08-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 12 replaces Phase 10's no-op `sgprocmanagerquant::QuantizeFloatBuffer`/`QuantizeByteBuffer` stubs with real IEEE-754 canonicalization plus fixed-precision quantization, using Phase 11's empirical Mac-vs-Windows divergence data to justify the constants — and builds the SECV-01 wrong-result-still-diverges counter-test alongside it, not deferred. The 20 call sites across 14 processor files are already wired (Phase 10); this phase's code surface is almost entirely `quantization.hpp`/`quantization.cpp`'s two function bodies, plus new SECV-01 test infrastructure. No manifest/artifact-level code changes (see D-01).

**A load-bearing finding from this discussion, not previously documented:** Phase 11's render capture showed `contentHashMatch: true` (pixel bytes byte-identical Mac vs. Windows) alongside `combinedHashMatch: false`. This is not a bug — `ProcessOutput.combinedHash` (`ExecutionManifest.manifestHash`, computed by `ComputeManifestHash`) bakes in `executorIdentity` (a SHA-256 of Vulkan device name/vendor/driver props, `capability_types.hpp`) and `gpuMemoryUsedBytes`, both genuinely machine-specific and structurally unfixable by any amount of output-data quantization. See D-01/D-02.

</domain>

<decisions>
## Implementation Decisions

### Which hash is the cross-hardware-tolerance target
- **D-01:** Quantization's job is to make the **processor-level** `ProcessingResult.hash` and its per-chunk hashes (set directly inside each processor's `StartProcessing()` — e.g. MNN's `subTaskResultHash`/`chunkhashes`, render's single readback hash) cross-hardware tolerant. This is the hash `ProcessingValidationCore` actually compares for cross-node consensus. `ProcessOutput.combinedHash`/`ExecutionManifest.manifestHash` (the manifest self-hash, which also folds in `executorIdentity` + `gpuMemoryUsedBytes`) is **not** touched in this phase — its cross-machine mismatch is expected and out of scope. No `ComputeManifestHash`/`ExecutionManifest` code changes.
- **D-02:** ROADMAP.md Phase 13 SC1 and REQUIREMENTS.md VALD-01 both say "matching combined hashes" across ≥3 machines — as literally worded, that's the manifest-level field, which D-01 establishes can never match cross-machine. **Phase 13's own discuss-phase/planning must reconcile this wording** (same pattern as Phase 11's D-03 fixing the "3 machines" wording) to mean the processor-level result/chunk hash, not `ProcessOutput.combinedHash`. Flagged here for Phase 13 to act on; not edited in this phase since Phase 12 doesn't own Phase 13's roadmap section.

### MNN float quantization technique (QUANT-01, QUANT-02, QUANT-04)
- **D-03:** `QuantizeFloatBuffer` uses fixed-point scale-round-cast to an integer grid: `q = round(x * S) / S`. Deterministic on any IEEE-754-compliant machine, no ambient-FPU rounding-mode dependency.
- **D-04:** One single, absolute (not magnitude-adaptive, not relative/ULP-based) epsilon, scoped to this milestone's actual fixtures — matches QUANT-04/REQUIREMENTS' "fixed constants … not schema-configurable" framing. (Note: divergence is magnitude-proportional in principle — 768 ULP but only ~1.043e-07 absolute — so an absolute grid could in theory be wrong-sized for a very different-magnitude fixture; explicitly not designed around speculatively. If a future fixture's data shows this doesn't hold, that's new empirical input for a later milestone.)
- **D-05:** Grid step ≈ `1e-6`, scale factor `S = 2^20` (power-of-two for exact round-trip in float arithmetic). This is ~10x margin above Phase 11's measured `maxAbsDelta ≈ 1.043e-07` (Mac vs. Windows, 512-element float32 tensor, `captures/diff-mnn-float.json`).

### IEEE-754 special-value canonicalization (QUANT-03)
- **D-06:** `+Inf` and `-Inf` canonicalize to **distinct** fixed patterns (`0x7F800000` / `0xFF800000`) — not collapsed to one value. A wrong-sign divergence must stay visible to SECV-01.
- **D-07:** Denormals are flushed to signed zero via an **explicit, auditable first branch** (checked before any rounding arithmetic runs — per PITFALLS.md's guidance, never as an assumed side effect of the rounding formula).
- **D-08:** `-0.0`/`+0.0` (and flushed denormals) collapse to **one** canonical zero bit pattern, sign discarded — matches IEEE-754's own equality semantics and QUANT-03's "one fixed representative bit pattern" wording.
- **D-09:** Canonical NaN is the **hardcoded** standard quiet-NaN bit pattern `0x7FC00000`. Any `std::isnan()`-detected input (regardless of payload/sign/signaling bit) is overwritten with this exact literal pattern, not a platform-native `quiet_NaN()` call.

### SECV-01 wrong-result counter-test
- **D-10:** Primary mechanism: corrupted MNN model weights — byte-flip/perturb a copy of the model file used by the MNN float fixture, re-run inference, assert the post-quantization hash differs from the correct run's.
- **D-11:** Counter-test covers **both** paths, not just MNN — a second case uses a wrong shader push-constant/uniform value in a copy of the render pass definition, re-runs the render fixture, asserts the post-quantization hash differs.
- **D-12:** Lands as a **new CTest target**, alongside Phase 09's conformance suites — runs automatically in CI, not a standalone manual tool like `capture_harness`.
- **D-13:** Assertion is **binary** — `ASSERT_NE` on the two post-quantization hashes. No secondary "divergence exceeds grid step" magnitude check; matches SECV-01/SC5's literal wording.

### Claude's Discretion
- Exact file/target names for the new SECV-01 CTest suite (e.g. `test/security/secv01_counter_test.cpp` or similar) — follow whatever convention Phase 09's conformance suites already established.
- Exact mechanics of "corrupting" the MNN model file and the render shader constant (which byte(s)/constant to perturb) — any change producing a materially different inference/render result satisfies D-10/D-11's intent.
- Whether the render SECV-01 case needs the `GTEST_SKIP()`-on-no-Vulkan-device pattern (Phase 09 D-05) — almost certainly yes, since it exercises the real render pipeline; follow the established pattern.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & Roadmap
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` — QUANT-01/02/03/04, SECV-01 locked requirements for this phase; VALD-01 (Phase 13) needs the D-02 wording note applied during Phase 13's own discussion
- `.planning/workstreams/sgproc-render/ROADMAP.md` (Phase 12 section) — goal, SC1-SC5; Phase 13 section SC1 needs the D-02 wording note

### Research (HIGH/MEDIUM confidence — architecture already specified, technique choice was this discussion's job)
- `.planning/workstreams/sgproc-render/research/SUMMARY.md` — recommended `sgprocmanagerquant` shape (`QuantizeFloatBuffer`/`QuantizeByteBuffer`), the 20 insertion points, the tolerance-vs-security central risk, NaN/Inf/denormal canonicalization pitfall
- `.planning/workstreams/sgproc-render/research/PITFALLS.md`, `ARCHITECTURE.md` — component-level detail backing SUMMARY.md's pitfalls/architecture claims

### Phase 11 empirical data (this phase's justification for D-05's constant)
- `.planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/11-CAPTURE-RESULTS.md` — the exact captured numbers (maxAbsDelta≈1.043e-07, maxRelDelta≈7.27e-05, maxUlpDistance=768 for MNN float32; contentHashMatch:true/combinedHashMatch:false for render uint8) that D-01 and D-05 are grounded in
- `.planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/captures/diff-mnn-float.json`, `diff-render.json` — raw diff data behind the above

### Prior Phase Context
- `.planning/workstreams/sgproc-render/phases/10-capture-harness-diff-tool-quantization-stub/10-CONTEXT.md` — capture file format, `ExecutionContext::rawOutputCapture` pattern, the exact 20-insertion-point wiring this phase's quantization bodies plug into
- `.planning/workstreams/sgproc-render/phases/09-processor-pass-graph-conformance-suites/09-CONTEXT.md` — `GTEST_SKIP()` + Vulkan device probe pattern (D-05), needed for the new SECV-01 render test case

### Existing Code (Source of Truth)
- `SuperGenius/SGProcessingManager/include/util/quantization.hpp`, `src/util/quantization.cpp` — the two no-op stub bodies this phase replaces; signatures are final, only the implementation changes
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_float.cpp:307-360` — the chunk-then-stitched two-layer call-site pattern (`QuantizeFloatBuffer` called at both layers); all 13 MNN processors follow this shape
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp:2207-2214` — render's single `QuantizeByteBuffer` call site immediately before its one `sha256()` call
- `SuperGenius/SGProcessingManager/include/artifacts/execution_manifest.hpp` — `ExecutionManifest` struct; `executorIdentity`/`gpuMemoryUsedBytes` fields D-01 identifies as out-of-scope machine-specific fields, NOT to be modified
- `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp:1500-1510` — where `ComputeManifestHash`/`ProcessOutput.combinedHash` is actually assembled (confirms D-01's "manifest hash, not output hash" finding)
- `SuperGenius/SGProcessingManager/include/capability/capability_types.hpp`, `src/capability/capability_validator.cpp:280` — `CapabilitySnapshot::identityHash`, confirms `executorIdentity` is a SHA-256 of real hardware-identifying Vulkan device properties (device name/vendor/driver), genuinely different Mac vs. Windows by design

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `sgprocmanagerquant::QuantizeFloatBuffer`/`QuantizeByteBuffer` stubs (`quantization.hpp`/`.cpp`) — already declared and called at all 20 sites; this phase only replaces the two function bodies, no call-site changes needed anywhere
- `sgprocmanagersha::sha256()` — stays completely unmodified, per established Phase 10 convention
- Phase 09's `GTEST_SKIP()` + Vulkan-probe pattern — reusable for the new render-path SECV-01 test case

### Established Patterns
- Chunk-then-stitched two-layer hashing (MNN) — quantization must run identically at both layers (already wired); QUANT-02 is satisfied by construction once the function bodies are real, no additional call-site work
- "Quantize-then-capture-then-hash" ordering at each site (Phase 10) — quantization happens before `execCtx.rawOutputCapture` fires and before the `sha256()` call, in that order, at every site

### Integration Points
- `quantization.cpp`'s two function bodies are the primary code change for QUANT-01/02/03 across both paths — essentially no other processor file needs touching
- New CTest target for SECV-01 (D-12), placed alongside Phase 09's conformance test suites in the existing test directory structure

</code_context>

<specifics>
## Specific Ideas

- Machine labels for traceability, matching Phase 11's `.cap`-filename convention: `Fuus-Mac-mini.local---macOS`, `Mofu---Windows`
- Concrete numbers to cite when documenting the derivation of D-05's constant: `maxAbsDelta ≈ 1.043081283569336e-07`, `maxRelDelta ≈ 7.269731577252969e-05`, `maxUlpDistance = 768` (MNN float32, 512 elements, Mac vs. Windows); render uint8 fixture (256 elements) showed `contentHashMatch: true` and all numeric deltas `0` on the same 2-machine pair

</specifics>

<deferred>
## Deferred Ideas

- **Modifying `ComputeManifestHash`/`ExecutionManifest` to exclude `executorIdentity`/`gpuMemoryUsedBytes` for a cross-machine-comparable manifest-level hash** — explored during discussion, then walked back once it became clear `ProcessingValidationCore` doesn't consume that field for consensus anyway (D-01). Would be a separate, future concern only if something downstream ever needs `ProcessOutput.combinedHash` itself to be cross-machine-comparable (e.g. a provenance dashboard) — not this milestone's problem.
- **Truncated/lower-precision inference run as the SECV-01 mechanism** — not chosen (D-10 uses model-weight corruption instead), but noted as a harder, more adversarial "plausible but wrong" test that could be added later if byte-flip corruption proves too easy to distinguish.
- **Relative/ULP-based (mantissa bit-masking) quantization** — not chosen for this milestone's fixed-constant scope (D-04 uses an absolute epsilon instead); would be the natural next step if a future fixture's data shows the absolute grid doesn't generalize across a wider magnitude range than this milestone's fixtures exercise.

### None further — discussion stayed within phase scope

</deferred>

---

*Phase: 12-Quantization / Normalization Implementation*
*Context gathered: 2026-08-12*
