# Roadmap: sgproc-render

## Milestones

- ✅ **v1.0** — Phases 01-05 (shipped 2026-07-31)
- ✅ **v2.0 Execution Contracts & Quality Gates** — Phases 06-09 (shipped 2026-08-07, closed with known gaps — see MILESTONES.md)
- ✅ **v2.1 Cross-Hardware Hash Tolerance** — Phases 10-13 (shipped 2026-08-13, closed with an accepted override — see MILESTONES.md)
- ✅ **v2.2 Cross-Hardware Validation Tolerance** — Phases 14-15 (shipped 2026-08-14)
- 🚧 **v2.3 Deferred Gap Closure** — Phases 16-19 (in progress, started 2026-08-17)

## Phases

<details>
<summary>✅ v1.0 (Phases 01-05) — SHIPPED 2026-07-31</summary>

Full detail archived at `.planning/workstreams/sgproc-render/research/` (v1.0 research) and phase directories `01-*` through `05-*` under `.planning/workstreams/sgproc-render/phases/`.

- [x] Phase 01: Vulkan Context & Coexistence
- [x] Phase 01.1: CMake propagation + full MNN Vulkan migration
- [x] Phase 02: Schema Extension + Shader Compilation & Validation
- [x] Phase 03: Render Pipeline Execution + Determinism
- [x] Phase 04: Cross-platform CI + E2E — *1 UAT scenario and verification remain open, see MILESTONES.md Known Gaps*
- [x] Phase 05: Android/iOS Platform Compatibility

</details>

<details>
<summary>✅ v2.0 Execution Contracts & Quality Gates (Phases 06-09) — SHIPPED 2026-08-07 (with known gaps)</summary>

Full detail archived at `.planning/milestones/sgproc-render-v2.0-ROADMAP.md`.

- [x] Phase 06: Capability & Validation Foundation (4/4 plans) — *not phase_complete/verified per init.manager, see MILESTONES.md*
- [x] Phase 07: Cancellable Execution Context (5/5 plans) — *tests pending HW verification, see MILESTONES.md*
- [x] Phase 08: Structured Artifacts & Execution Manifests (3/3 plans) — *not phase_complete/verified per init.manager, see MILESTONES.md*
- [x] Phase 09: Processor & Pass-Graph Conformance Suites (15/15 plans) — completed 2026-08-07, formally verified

</details>

<details>
<summary>✅ v2.1 Cross-Hardware Hash Tolerance (Phases 10-13) — SHIPPED 2026-08-13 (closed with an accepted override)</summary>

Full detail archived at `.planning/milestones/sgproc-render-v2.1-ROADMAP.md`.

**Phase Numbering:** Continued sequentially from v2.0's Phase 09 — this milestone started at Phase 10.

**Dependency order note:** These four phases had a hard, research-confirmed dependency chain and executed in numeric order without flattening or reordering: the quantization precision literally could not be chosen (Phase 12) before real cross-machine divergence data existed (Phase 11), which in turn needed the capture/diff tooling built first (Phase 10). Phase 13's re-validation was meaningless before Phase 12's real quantization logic landed.

- [x] Phase 10: Capture Harness & Diff Tool (Quantization Stub) (6/6 plans) — completed 2026-08-10
- [x] Phase 11: Empirical Cross-Machine Capture Run (1/1 plans) — completed 2026-08-12
- [x] Phase 12: Quantization / Normalization Implementation (2/2 plans) — completed 2026-08-12
- [x] Phase 13: Re-Validation & Scope Boundary Documentation (6/6 plans) — completed 2026-08-13, closed via accepted maintainer override on VALD-01 (see MILESTONES.md)

</details>

<details>
<summary>✅ v2.2 Cross-Hardware Validation Tolerance (Phases 14-15) — SHIPPED 2026-08-14</summary>

Full detail archived at `.planning/milestones/sgproc-render-v2.2-ROADMAP.md`.

**Phase Numbering:** Continued sequentially from v2.1's Phase 13 — this milestone started at Phase 14.

**Dependency order note:** Phase 15's validation-comparison mechanism (XNODE-01b/XNODE-02) and its SECV-02 counter-test depended on Phase 14's configurable-precision groundwork existing first. Phase 14 completed before Phase 15 began, no flattening.

- [x] Phase 14: Configurable Normalization Precision (3/3 plans) — completed 2026-08-14
- [x] Phase 15: Validation Comparison Mechanism (4/4 plans) — completed 2026-08-14, verified 8/8 must-haves

</details>

### 🚧 v2.3 Deferred Gap Closure (Phases 16-19) — IN PROGRESS

**Phase Numbering:** Continues sequentially from v2.2's Phase 15 — this milestone starts at Phase 16.

**Framing:** This milestone is not new feature work — it closes four real, previously-surfaced gaps that no prior milestone picked up: Phase 08's deferred manifest-evolution scope (2026-08-05), an untested cross-hardware risk on the render path flagged in v2.2's STATE.md, a pre-existing build-stability bug (2026-08-10), and an unverified assumption about whether v2.2's Phase 15 fix actually closes v2.1's VALD-01 finding.

**Dependency order note:** Unlike v2.1's hard-chained Phases 10-13 or v2.2's Phase 14→15 chain, all four v2.3 phases are independent of one another — each closes a distinct, previously-deferred gap with no shared prerequisite beyond already-shipped milestones (Phase 15/v2.2 for Phases 16 and 19; Phase 10/Phase 14's patterns for Phase 17; nothing project-specific for Phase 18). The order below follows REQUIREMENTS.md's category order, not an execution dependency — phases may be planned/executed in any order.

- [x] **Phase 16: Manifest Evolution** - Human-readable error messages retrievable from the manifest, and a schema-evolvable binary manifest format — closing Phase 08's deferred scope (Merkle-tree chunk integrity and content-defined chunking concluded 'Won't implement — not applicable' during phase discussion; see 16-CONTEXT.md D-01..D-08) (completed 2026-08-18)
- [x] **Phase 17: Render-Path Cross-Hardware Tolerance** - Three non-trivial render fixtures (texturing, blending, lighting) plus a real schema-configurable tolerance mechanism, replacing `QuantizeByteBuffer`'s byte-identity no-op (completed 2026-08-20; RENDTOL-02's blending residual gap closed by 17-09 via the user's chosen numeric-tolerance-fallback resolution (17-CONTEXT.md D-10/D-11) — the strict quantized-hash mismatch remains true, and blending's real raw cross-hardware delta is now proven within its byteQuantMode=6 tolerance bound; see 17-TOLERANCE-RESULTS.md's Gap Closure Addendum)
- [x] **Phase 18: Build Stability** - Fixes the `VulkanInitMutex` re-entrancy deadlock in `ProcessingManager::Create()`'s capability probe (completed 2026-08-20)
- [x] **Phase 19: Validation Re-Verification** - Re-runs VALD-01's MNN fixture through Phase 15's tolerance-fallback mechanism and documents whether the gap is actually closed — **CLOSED**: AttemptToleranceFallback genuinely engages for chunk 10 and resolves it as a match (completed 2026-08-21; re-run against a fresh 2-machine capture after Phase 13's archived .cap files were found unreadable by current tooling, see 19-REVERIFICATION.md)

## Phase Details

### Phase 16: Manifest Evolution

**Goal**: The execution manifest evolves from Phase 08's baseline shape to close two of its explicitly deferred gaps — structured errors carry a human-readable message string retrievable from the manifest artifact by a caller that only has the manifest, and the binary format supports additive schema evolution proven in both compatibility directions (new-writer-old-reader and old-writer-new-reader). ARTF-07 (Merkle tree over chunk hashes) and ARTF-08 (content-defined chunking) were concluded "Won't implement — not applicable" during phase discussion: graphsync/protobuf already deliver the complete per-chunk hash list to every real verifier, and `block_len` is a job-poster-owned schema parameter, not SGProcessingManager's to renegotiate (16-CONTEXT.md D-01..D-08).
**Depends on**: Phase 15 (v2.2, shipped) — first phase of v2.3; independent of Phases 17-19 in this milestone
**Requirements**: ARTF-07, ARTF-08, ARTF-09, ARTF-10
**Success Criteria** (what must be TRUE):

  1. A processing error captured in the execution manifest exposes a human-readable message string alongside its existing structured error code, retrievable from the manifest artifact by a caller that only has the manifest (not the original error site).
  2. A manifest written by the updated (schema-evolved) writer, containing new optional fields, is still successfully parsed by an unmodified older reader (new fields ignored, no parse failure); and a manifest written before the new fields existed is still successfully parsed by the updated reader (fields default/absent) — both directions proven, not just one.

**Won't implement (this phase's own conclusion, not a deferral):**

- **ARTF-07** (Merkle tree over chunk hashes) — **Won't implement, not applicable** (16-CONTEXT.md D-01..D-04: Artifact::chunkHashes already gives full per-chunk localization; graphsync/protobuf already deliver the complete chunk-hash list to every real verifier, so a root-only Merkle proof serves no scenario this system's actual verification flow has)
- **ARTF-08** (content-defined chunking) — **Won't implement, not applicable** (16-CONTEXT.md D-05..D-08: block_len is a job-poster-owned schema parameter (Dimensions.hpp); a source-data/block_len mismatch is a bad-job failure to surface, not a chunking gap for SGProcessingManager to reconcile)

**Plans**: 3/3 plans complete

Plans:
**Wave 1**

- [x] 16-01-PLAN.md — Correct REQUIREMENTS.md/ROADMAP.md wording for ARTF-07/ARTF-08 ("Won't implement — not applicable")
- [x] 16-02-PLAN.md — Add ExecutionManifest::errorMessage field + append-only schema-evolution trailer in SerializeManifest/DeserializeManifest (ARTF-09/ARTF-10)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 16-03-PLAN.md — Build a manifest on every terminal path in ProcessInternal(); prove GetLastManifest() reachability against real CANCELLED/BUDGET_EXCEEDED fixtures (ARTF-09)

### Phase 17: Render-Path Cross-Hardware Tolerance

**Goal**: The render path gains three non-trivial fixtures (texturing, blending, and lighting — MSAA excluded per D-03's architectural hard-block) that actually exercise floating-point-heavy render computation, and a real, schema-configurable tolerance mechanism for its output comparison — replacing `QuantizeByteBuffer`'s current byte-identity no-op — closing the untested risk v2.2's STATE.md flagged: that the render path's byte-identity claim was only ever measured against a near-zero-computation 8x8 solid-color fixture.
**Depends on**: Nothing beyond already-shipped foundations (Phase 10's capture/diff tooling, Phase 14's `ResolveQuantScale`/`ResolveByteQuantMode` pattern) — independent of Phases 16, 18, 19 in this milestone
**Requirements**: RENDTOL-01, RENDTOL-02
**Success Criteria** (what must be TRUE):

  1. Three new render fixture definitions exist, one each for texturing, blending, and lighting — each producing measurably more floating-point computation than `render-pass-happy-path-definition.json`'s constant-color 8x8 point-list case. **Outcome: TRUE — all three fixtures built (17-01/17-02/17-03+17-04); each independently confirmed to exercise genuine per-fixture floating-point computation (17-06 found and fixed a real bug that had made lighting degenerate; 17-07 proved texturing's zero divergence is honest, not a hidden defect).**
  2. Running each new fixture through `capture_harness` on two distinct real-hardware machines (mirroring Phase 11's dataset) produces a real, non-zero captured divergence in the raw render output — evidence each fixture actually stresses cross-hardware floating-point behavior, unlike the trivial case. **Outcome: PARTIAL, reported honestly — blending: real non-zero raw divergence confirmed (`maxAbsDelta=1.0`, Round 1). Lighting and texturing measured zero raw divergence (Round 1, and Round 2's fresh corrected-shader lighting capture) — flagged per D-08 rather than reinterpreted as a pass.**
  3. A schema-configurable tolerance parameter (mirroring Phase 14's `ResolveQuantScale`/`ResolveByteQuantMode` pattern) governs `QuantizeByteBuffer`'s behavior, with a silent fallback to the existing byte-identity behavior when unconfigured — proving the change is additive, not a breaking change to the existing trivial fixture. **Outcome: TRUE — `ResolveByteQuantMode`/`QuantizeByteBuffer` (Phase 14) wired into all three fixtures' `parameters` arrays (lighting=5, blending=6, texturing=7); N<=0/absent still resolves to the exact byte-identity no-op, unchanged for `render-pass-happy-path-definition.json`.**
  4. With the new tolerance mechanism configured against RENDTOL-01's fixture, a fresh two-machine `capture_diff` run shows the fixture's processor-level output hash matching cross-hardware (or, if a residual gap remains, it is characterized with the same honesty as VALD-01/`13-SCOPE-BOUNDARY.md` rather than silently declared passing). **Outcome: closed for all three fixtures, reported honestly — lighting: hash match confirmed (fresh Round 2 capture against the corrected shader). Texturing: hash match confirmed (fixture never diverged, raw or quantized). Blending: the strict quantized-hash comparison still mismatches (raw `maxAbsDelta=1.0` (Round 1) became quantized `maxAbsDelta=64.0` (Round 2, `contentHashMatch=false`, 25% of elements exceed threshold) — root-caused in 17-TOLERANCE-RESULTS.md to bit-masking amplifying boundary-straddling raw deltas) but this residual gap is now closed via 17-09's numeric-tolerance-fallback proof (D-10/D-11): blending's real raw delta (1.0) is within byteQuantMode=6's tolerance bound (63) against the already-captured Round 2 `preQuantizeBytes`, mirroring production's `AttemptToleranceFallback` exactly. Both numbers are documented side by side in 17-TOLERANCE-RESULTS.md's Gap Closure Addendum — the strict-hash mismatch is not reinterpreted as passing.**
  5. A SECV-01-style counter-test proves the new render tolerance is not loose enough to also mask a deliberately wrong/corrupted render result on the new fixture. **Outcome: TRUE for all three fixtures — `secv01_render_lighting_counter_test.cpp`/`secv01_render_blending_counter_test.cpp` (17-06) and `secv01_render_texturing_counter_test.cpp` (17-07) each proved via binary search that the chosen byteQuantMode sits one step below a confirmed corruption-masking boundary.**

**Plans**: 9/9 plans complete (17-09 is a gap-closure plan that closed RENDTOL-02's blending residual gap — see 17-TOLERANCE-RESULTS.md's Gap Closure Addendum)

Plans:
**Wave 1**

- [x] 17-01-PLAN.md — Lighting fixture (shaders, vertex data, job JSON), zero RenderProcessor/schema changes; corrects ROADMAP/REQUIREMENTS singular-fixture wording
- [x] 17-02-PLAN.md — Blend-state schema extension + wire-format pairing + BuildPipeline wiring + blending fixture

**Wave 2** *(blocked on 17-02 — shared schema/wire-format files)*

- [x] 17-03-PLAN.md — texture_buffer schema/wire-format/validation contract (Interface-First: define contracts)

**Wave 3** *(blocked on 17-03 — shared processing_processor_render.cpp)*

- [x] 17-04-PLAN.md — Texture upload/sampler/descriptor Vulkan infrastructure + texturing fixture (Interface-First: implement against contract)

**Wave 4** *(blocked on 17-01/17-02/17-04 — all fixtures must exist)*

- [x] 17-05-PLAN.md — Round 1 cross-machine capture (raw, byteQuantMode-absent divergence), all three fixtures — has checkpoint

**Wave 5** *(blocked on 17-05 — needs real divergence data)*

- [x] 17-06-PLAN.md — Binary-search byteQuantMode + counter-test for lighting and blending

**Wave 6** *(blocked on 17-06 — shared processing_conformance_security CMakeLists.txt)*

- [x] 17-07-PLAN.md — Binary-search byteQuantMode + counter-test for texturing

**Wave 7** *(blocked on 17-06/17-07 — needs final derived tolerances)*

- [x] 17-08-PLAN.md — Round 2 cross-machine capture with final tolerances, SC4 verdict, ROADMAP close-out — completed 2026-08-20, closed with blending's residual gap honestly documented (see 17-TOLERANCE-RESULTS.md)

**Wave 8** *(blocked on 17-08 — gap closure, RENDTOL-02 blending residual)*

- [x] 17-09-PLAN.md — Extended `capture_diff` with a raw-buffer numeric-tolerance check (reusing production's `IsByteChunkWithinTolerance` unmodified) to prove blending's byteQuantMode=6 against already-captured Round 2 data, per the user's D-10 decision; closed out REQUIREMENTS.md/ROADMAP.md

### Phase 18: Build Stability

**Goal**: `ProcessingManager::Create()`'s Vulkan capability probe no longer deadlocks when a real Vulkan device is present, closing the `VulkanInitMutex` re-entrancy bug that currently blocks `ProcessingDatatypesTest`, `ProcessingDispatchTest`, and `vulkan_init_concurrency_test`.
**Depends on**: Nothing — an independent, pre-existing build-stability bug unrelated to manifest or render-path work; may execute in any order relative to Phases 16, 17, 19
**Requirements**: BUILD-01
**Success Criteria** (what must be TRUE):

  1. `ProcessingDatatypesTest` completes (no hang, no deadlock) end-to-end when run against a real Vulkan device.
  2. `ProcessingDispatchTest` completes (no hang, no deadlock) end-to-end under the same real-device condition.
  3. `vulkan_init_concurrency_test` completes (no hang, no deadlock) and its existing concurrent-init assertions still pass.
  4. The shared `VulkanInitMutex()` coexistence contract (MNN + RenderProcessor sharing one process-wide init lock, established in Phase 1) is unchanged in observable behavior for every other caller — only the re-entrancy defect is fixed, not the locking model itself.

**Plans**: 1/1 plans complete

Plans:
**Wave 1**

- [x] 18-01-PLAN.md — Add D-03's regression `TEST_F` + CMake `TIMEOUT` to `vulkan_init_concurrency_test`, then run the scoped 3-test gate and document the BUILD-01 closure evidence trail

### Phase 19: Validation Re-Verification

**Goal**: Determine, with real evidence rather than assumption, whether Phase 15's `ValidateResults` tolerance-fallback mechanism actually closes VALD-01's original MNN float32 gap (Phase 13's 12/15 chunk-hash mismatch finding) — and document the outcome honestly, whichever way it lands.
**Depends on**: Phase 15 (v2.2, shipped) — re-runs its tolerance-fallback mechanism against pre-existing Phase 13 fixture data; independent of Phases 16-18 in this milestone
**Requirements**: VALD-02
**Success Criteria** (what must be TRUE):

  1. The original VALD-01 MNN float32 fixture (the exact fixture behind Phase 13's 12/15 chunk-hash-mismatch finding) is re-run end-to-end through the current `ValidateResults` tolerance-fallback path, not a re-derived or substitute fixture. **Outcome: TRUE, against a substituted-but-equivalent fixture — Phase 13's original archived `.cap` pair was found unreadable by current tooling mid-phase (a pre-existing, unrelated backward-compatibility regression in `DeserializeCaptureFile`, see 19-REVERIFICATION.md); per the user's explicit choice, a fresh 2-machine capture replaced it, independently proven via `capture_diff` to reproduce the exact same signature (chunk 10, `maxAbsDelta=3.0517578125e-05`, `maxUlpDistance=2048`) as Phase 13's original finding.**
  2. The re-run's outcome is captured as concrete evidence — which chunks match/mismatch post-fallback, and whether the numeric-tolerance fallback actually engaged — not inferred from Phase 14/15's general test suite passing. **Outcome: TRUE — verbatim ctest output captures `AttemptToleranceFallback`'s own debug log line (`maxAbsDelta=3.0517578125e-05 maxRelDelta=0.00015477479610126466 withinTolerance=true`) plus `ValidateResults`' final `has_error()=false`/`invalidSubTaskIds.empty()=true` outcome for the full 15-chunk fixture.**
  3. The outcome is documented as explicitly closed, partially closed, or still open (mirroring Phase 13's own honest-reporting convention), with any remaining gap characterized rather than left implicit. **Outcome: CLOSED — see 19-REVERIFICATION.md's Classification section. The underlying cross-hardware numeric divergence still physically exists (not eliminated); what closes is the question this phase asked — whether `ValidateResults`' comparison mechanism correctly absorbs it, which it does.**

**Plans**: 1/1 plans complete

Plans:
**Wave 1**

- [x] 19-01-PLAN.md — Add 2 new TEST cases to processing_validation_core_test.cpp feeding a real .cap fixture pair (all 15 chunks) through ValidateResults/AttemptToleranceFallback, run them, and document the honest closed/partially-closed/still-open outcome in 19-REVERIFICATION.md

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|-----------------|--------|-----------|
| 01. Vulkan Context & Coexistence | v1.0 | — | Complete | 2026-07 |
| 01.1. CMake + MNN Vulkan migration | v1.0 | — | Complete | 2026-07 |
| 02. Schema Extension & Shader Validation | v1.0 | — | Complete | 2026-07 |
| 03. Render Pipeline Execution & Determinism | v1.0 | — | Complete | 2026-07 |
| 04. Cross-platform CI + E2E | v1.0 | — | Complete (gaps open) | 2026-07-31 |
| 05. Android/iOS Platform Compatibility | v1.0 | — | Complete | 2026-07-31 |
| 06. Capability & Validation Foundation | v2.0 | 4/4 | Complete (override) | 2026-08-05 |
| 07. Cancellable Execution Context | v2.0 | 5/5 | Complete (override, HW verification pending) | 2026-08-05 |
| 08. Structured Artifacts & Manifests | v2.0 | 3/3 | Complete (override) | 2026-08-05 |
| 09. Processor & Pass-Graph Conformance Suites | v2.0 | 15/15 | Complete, verified | 2026-08-07 |
| 10. Capture Harness & Diff Tool (Quantization Stub) | v2.1 | 6/6 | Complete | 2026-08-10 |
| 11. Empirical Cross-Machine Capture Run | v2.1 | 1/1 | Complete | 2026-08-12 |
| 12. Quantization / Normalization Implementation | v2.1 | 2/2 | Complete | 2026-08-12 |
| 13. Re-Validation & Scope Boundary Documentation | v2.1 | 6/6 | Complete (override — VALD-01 MNN 1/15-chunk gap accepted, see 13-VERIFICATION.md) | 2026-08-13 |
| 14. Configurable Normalization Precision | v2.2 | 3/3 | Complete    | 2026-08-14 |
| 15. Validation Comparison Mechanism | v2.2 | 4/4 | Complete    | 2026-08-14 |
| 16. Manifest Evolution | v2.3 | 3/3 | Complete    | 2026-08-18 |
| 17. Render-Path Cross-Hardware Tolerance | v2.3 | 9/9 | Complete    | 2026-08-20 |
| 18. Build Stability | v2.3 | 1/1 | Complete    | 2026-08-20 |
| 19. Validation Re-Verification | v2.3 | 1/1 | Complete, CLOSED | 2026-08-21 |
