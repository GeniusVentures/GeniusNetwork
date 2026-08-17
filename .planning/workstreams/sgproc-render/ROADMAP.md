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

- [ ] **Phase 16: Manifest Evolution** - Merkle-tree chunk integrity, content-defined chunking, human-readable error messages, and a schema-evolvable binary manifest format — closing Phase 08's deferred scope
- [ ] **Phase 17: Render-Path Cross-Hardware Tolerance** - A non-trivial render fixture plus a real schema-configurable tolerance mechanism, replacing `QuantizeByteBuffer`'s byte-identity no-op
- [ ] **Phase 18: Build Stability** - Fixes the `VulkanInitMutex` re-entrancy deadlock in `ProcessingManager::Create()`'s capability probe
- [ ] **Phase 19: Validation Re-Verification** - Re-runs VALD-01's MNN fixture through Phase 15's tolerance-fallback mechanism and documents whether the gap is actually closed

## Phase Details

### Phase 16: Manifest Evolution

**Goal**: The execution manifest evolves from Phase 08's baseline shape to close its explicitly deferred gaps — chunk integrity is verifiable via a Merkle tree over chunk hashes (not just the flat content hash), chunking uses content-defined boundaries so a small edit doesn't invalidate every downstream chunk hash, structured errors carry a human-readable message string, and the binary format supports additive schema evolution without breaking older readers.
**Depends on**: Phase 15 (v2.2, shipped) — first phase of v2.3; independent of Phases 17-19 in this milestone
**Requirements**: ARTF-07, ARTF-08, ARTF-09, ARTF-10
**Success Criteria** (what must be TRUE):

  1. A Merkle tree built over chunk hashes detects a corrupted/perturbed chunk even in a scenario deliberately constructed so the existing flat content hash alone would be insufficient to localize (or, if crafted to coincide, mask) the corruption — proving the Merkle layer is a real additional integrity check, not a redundant one.
  2. Content-defined chunking (not fixed-size) is used for chunk boundary derivation; re-chunking an input after a small localized edit produces the same chunk hashes for every chunk outside the edited region, and only the chunk(s) actually covering the edit differ — proven against a real fixture diffing an edited vs. unedited chunk-hash set.
  3. A processing error captured in the execution manifest exposes a human-readable message string alongside its existing structured error code, retrievable from the manifest artifact by a caller that only has the manifest (not the original error site).
  4. A manifest written by the updated (schema-evolved) writer, containing new optional fields, is still successfully parsed by an unmodified older reader (new fields ignored, no parse failure); and a manifest written before the new fields existed is still successfully parsed by the updated reader (fields default/absent) — both directions proven, not just one.

**Plans**: TBD

### Phase 17: Render-Path Cross-Hardware Tolerance

**Goal**: The render path gains both a non-trivial fixture that actually exercises floating-point-heavy render computation (texturing, blending, or MSAA/lighting) and a real, schema-configurable tolerance mechanism for its output comparison — replacing `QuantizeByteBuffer`'s current byte-identity no-op — closing the untested risk v2.2's STATE.md flagged: that the render path's byte-identity claim was only ever measured against a near-zero-computation 8x8 solid-color fixture.
**Depends on**: Nothing beyond already-shipped foundations (Phase 10's capture/diff tooling, Phase 14's `ResolveQuantScale`/`ResolveByteQuantMode` pattern) — independent of Phases 16, 18, 19 in this milestone
**Requirements**: RENDTOL-01, RENDTOL-02
**Success Criteria** (what must be TRUE):

  1. A new render fixture definition exists that exercises texturing, blending, or MSAA/lighting — producing measurably more floating-point computation than `render-pass-happy-path-definition.json`'s constant-color 8x8 point-list case.
  2. Running the new fixture through `capture_harness` on two distinct real-hardware machines (mirroring Phase 11's dataset) produces a real, non-zero captured divergence in the raw render output — evidence the fixture actually stresses cross-hardware floating-point behavior, unlike the trivial case.
  3. A schema-configurable tolerance parameter (mirroring Phase 14's `ResolveQuantScale`/`ResolveByteQuantMode` pattern) governs `QuantizeByteBuffer`'s behavior, with a silent fallback to the existing byte-identity behavior when unconfigured — proving the change is additive, not a breaking change to the existing trivial fixture.
  4. With the new tolerance mechanism configured against RENDTOL-01's fixture, a fresh two-machine `capture_diff` run shows the fixture's processor-level output hash matching cross-hardware (or, if a residual gap remains, it is characterized with the same honesty as VALD-01/`13-SCOPE-BOUNDARY.md` rather than silently declared passing).
  5. A SECV-01-style counter-test proves the new render tolerance is not loose enough to also mask a deliberately wrong/corrupted render result on the new fixture.

**Plans**: TBD

### Phase 18: Build Stability

**Goal**: `ProcessingManager::Create()`'s Vulkan capability probe no longer deadlocks when a real Vulkan device is present, closing the `VulkanInitMutex` re-entrancy bug that currently blocks `ProcessingDatatypesTest`, `ProcessingDispatchTest`, and `vulkan_init_concurrency_test`.
**Depends on**: Nothing — an independent, pre-existing build-stability bug unrelated to manifest or render-path work; may execute in any order relative to Phases 16, 17, 19
**Requirements**: BUILD-01
**Success Criteria** (what must be TRUE):

  1. `ProcessingDatatypesTest` completes (no hang, no deadlock) end-to-end when run against a real Vulkan device.
  2. `ProcessingDispatchTest` completes (no hang, no deadlock) end-to-end under the same real-device condition.
  3. `vulkan_init_concurrency_test` completes (no hang, no deadlock) and its existing concurrent-init assertions still pass.
  4. The shared `VulkanInitMutex()` coexistence contract (MNN + RenderProcessor sharing one process-wide init lock, established in Phase 1) is unchanged in observable behavior for every other caller — only the re-entrancy defect is fixed, not the locking model itself.

**Plans**: TBD

### Phase 19: Validation Re-Verification

**Goal**: Determine, with real evidence rather than assumption, whether Phase 15's `ValidateResults` tolerance-fallback mechanism actually closes VALD-01's original MNN float32 gap (Phase 13's 12/15 chunk-hash mismatch finding) — and document the outcome honestly, whichever way it lands.
**Depends on**: Phase 15 (v2.2, shipped) — re-runs its tolerance-fallback mechanism against pre-existing Phase 13 fixture data; independent of Phases 16-18 in this milestone
**Requirements**: VALD-02
**Success Criteria** (what must be TRUE):

  1. The original VALD-01 MNN float32 fixture (the exact fixture behind Phase 13's 12/15 chunk-hash-mismatch finding) is re-run end-to-end through the current `ValidateResults` tolerance-fallback path, not a re-derived or substitute fixture.
  2. The re-run's outcome is captured as concrete evidence — which chunks match/mismatch post-fallback, and whether the numeric-tolerance fallback actually engaged — not inferred from Phase 14/15's general test suite passing.
  3. The outcome is documented as explicitly closed, partially closed, or still open (mirroring Phase 13's own honest-reporting convention), with any remaining gap characterized rather than left implicit.

**Plans**: TBD

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
| 16. Manifest Evolution | v2.3 | 0/TBD | Not started | - |
| 17. Render-Path Cross-Hardware Tolerance | v2.3 | 0/TBD | Not started | - |
| 18. Build Stability | v2.3 | 0/TBD | Not started | - |
| 19. Validation Re-Verification | v2.3 | 0/TBD | Not started | - |
