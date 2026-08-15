# Milestone v2.2: Cross-Hardware Validation Tolerance — sgproc-render workstream

**Status:** ✅ SHIPPED 2026-08-14
**Phases:** 14-15
**Total Plans:** 7

## Overview

Directly motivated by v2.1's own closing findings: (1) the `tex3d`/`spleen_ct_seg` real workload proved a single global quantization scale cannot serve models with materially different cross-hardware divergence magnitudes, and (2) v2.1's chunk-10 finding proved that even a well-tuned scale can produce a *false* hash mismatch on a genuinely correct result (a boundary tie-break) — so a real validation mechanism needed tolerance, not just a better constant. v2.2 delivered both: schema-configurable normalization precision (Phase 14) and a fixed, tolerant `ValidateResults` comparison mechanism (Phase 15).

## Phases

### Phase 14: Configurable Normalization Precision

**Goal**: A processing job's schema can declare its own per-data-type normalization precision instead of being locked to v2.1's single hardcoded `kScale` constant — directly closing the `tex3d`/`spleen_ct_seg` gap, where one global scale could not serve a workload whose real cross-hardware divergence is 2-3 orders of magnitude larger than the tiny float fixture v2.1 tuned against. Existing jobs that declare nothing keep working unchanged.
**Depends on**: Phase 13 (v2.1, shipped) — first phase of v2.2
**Requirements**: QUANT-CFG-01, QUANT-CFG-02, QUANT-CFG-03
**Plans**: 3/3 plans complete

Plans:

- [x] 14-01: Quantization resolver infrastructure — `ResolveQuantScale`/`ResolveByteQuantMode` free functions, 3-arg required-parameter `QuantizeFloatBuffer`/`QuantizeByteBuffer` signatures, 18/18 passing unit tests
- [x] 14-02: Quantization call-site wiring — all 21 existing call sites across 14 MNN/render processor files resolve scale/maskBits from the job's own schema instead of relying on a hardcoded constant
- [x] 14-03: Tex3d empirical precision & SECV-01 counter-test — `tex3d`/`spleen_ct_seg` configured with its own empirically-derived `quantScale=128.0` (2^7), proven by a dedicated counter-test to still catch a genuinely corrupted model

**Details:**

Plan 14-01 centralized the D-01/D-02 find-by-name-in-`parameters` lookup with an exact silent-fallback contract (32768.0f for float, 0 for byte masking), replacing v2.1's hardcoded `kScale`. Plan 14-02 wired all 21 call sites across 14 processor files with zero deviations — every file matched the research's grep-confirmed enumeration exactly. Plan 14-03's binary search over power-of-two `quantScale` candidates (256, 128, 64, 2, 1) against a new corrupted-model counter-test found **no SECV-01 failure boundary** anywhere in the valid domain for this real ~19MB segmentation model — the final `quantScale=128.0` was instead chosen via the divergence-absorption constraint (grid step must exceed the real measured `0.005126953125` cross-hardware delta). Notable finding for future per-workload tuning: this style of corrupted-model counter-test doesn't always yield a precision ceiling.

### Phase 15: Validation Comparison Mechanism

**Goal**: `ProcessingValidationCore::ValidateResults` is fixed to actually compare same-chunk hashes across subtasks (today's concatenation bug silently passes a genuine cross-node mismatch), and extended with a bounded numeric-tolerance fallback so a hash mismatch is not automatically treated as a genuine divergence — directly closing the false-mismatch risk v2.1's chunk-10 diagnostic exposed. A counter-test proves the combined mechanism still catches genuinely wrong results, not just tolerant ones.
**Depends on**: Phase 14 — the numeric-tolerance fallback compares against configured precision/tolerance values, and SECV-02 needs both the concatenation-bug fix and the tolerance fallback in place to meaningfully prove neither is jointly too loose
**Requirements**: XNODE-01b, XNODE-02, SECV-02
**Plans**: 4/4 plans complete

Plans:

- [x] 15-01: Extract `capture_diff`'s numeric-diff primitives into a new shared `sgprocmanagerdiff` library, plus new D-03/D-04 tolerance-derivation functions
- [x] 15-02: Fix `ValidateResults`'s concatenation bug (chunks map restructured to `chunkKey -> {subtaskId -> hashBytes}`) + numeric-tolerance fallback, proven by a new live test covering SC1-SC4
- [x] 15-03: Wire real production capabilities — `ProcessingCore::GetTaskQueue()` for job-schema lookup, real `FileManager::LoadASync`-based IPFS fetch on hash-mismatch only
- [x] 15-04: SECV-02 full-pipeline counter-test proving the combined mechanism still catches a genuinely corrupted subtask result

**Details:**

Fixed XNODE-01b by restructuring `ValidateResults`'s internal `chunks` map from a single shared-buffer concatenation to `chunkKey -> {subtaskId -> hashBytes}`, so same-chunk hashes across subtasks are actually compared instead of silently passing. Added XNODE-02: a bounded numeric-tolerance fallback via the new `sgprocmanagerdiff` static library (colocated with Phase 14's `sgprocmanagerquant`), quantScale-derived threshold when configured, fixed-constant fallback otherwise. Wired real production capabilities instead of stubs: a new `ProcessingCore::GetTaskQueue()` interface method and a real `FileManager`-backed IPFS fetch on hash-mismatch only (no new I/O on the trivial matching-hash path). SECV-02 proved via a genuine full-pipeline run (not a narrow unit test) that the fixed mechanism still catches real corruption — required a new dedicated fixture (`secv02-corrupted-float_model.mnn`, since SECV-01's existing fixture wasn't divergent enough at the required single-window granularity) and a fix for an output-path collision between the two test jobs (both test-only issues, no production bugs found). All 4 plans sequential (each built on the prior); touched the `SuperGenius` submodule throughout, so worktree isolation was disabled project-wide for this phase.

---

## Milestone Summary

**Key Decisions:**

- Phase structure is 2 phases (14, 15), not 6 (one per requirement) — coarse granularity per config.json, and the two categories already named in REQUIREMENTS.md mapped cleanly onto two coherent, independently-verifiable delivery boundaries
- Phase 14 hard-ordered before Phase 15: the numeric-tolerance fallback conceptually needs configured tolerance values to exist first, and SECV-02's counter-test needs both fixes in place before it can prove neither is jointly too loose
- No SECV-01 failure boundary found for tex3d/spleen_ct_seg's corrupted-model counter-test down to the domain floor; final `quantScale=128.0` chosen via the divergence-absorption constraint instead (D-10) — unlike Phase 13's small-model search, which found a genuine S=2^14 boundary
- XNODE-01c (actual cross-node consensus/redundant-execution plumbing) stays explicitly out of scope — v2.2 makes the comparison mechanism itself correct and tolerant; wiring it into real multi-node orchestration remains future work

**Issues Resolved:**

- `ProcessingValidationCore::ValidateResults`'s concatenation bug (never actually diffed two subtasks' hashes for the same chunk) — a real, previously-silent cross-node validation gap
- A single global quantization scale could not serve models with materially different cross-hardware divergence magnitudes (proven by the `tex3d`/`spleen_ct_seg` real workload showing all 25 chunk hashes diverging)

**Issues Deferred:**

- XNODE-01c: actual cross-node consensus/redundant-execution comparison plumbing — v2.2 makes the comparison mechanism itself correct and tolerant; wiring it into real multi-node job orchestration is future work
- Fixing every MNN processor's quantization precision individually — QUANT-CFG-01 makes precision configurable; per-workload tuning happens as each workload is onboarded, not as a one-time bulk exercise

**Technical Debt Incurred:**

- None new this milestone. Pre-existing Phase 04 (v1.0 carryover) UAT/verification gap re-surfaced by the pre-close artifact audit and acknowledged again (unchanged since v2.0 close) — see MILESTONES.md Known Gaps and STATE.md Deferred Items.

**Milestone-Archive Naming Note:** This project runs parallel GSD workstreams (`sgproc-render`, `gnus-subnets`, and the child-wallet track at root `.planning/`). The child-wallet workstream independently reached its own "v2.2" (GeniusSDK Child Wallet Interfaces, shipped 2026-07-something) — a bare `v2.2-ROADMAP.md`/`v2.2-REQUIREMENTS.md`/`v2.2` git tag already existed for that workstream. This archive and its companion `sgproc-render-v2.2-REQUIREMENTS.md` are workstream-qualified filenames (matching the `sgproc-render-v2.0-*`/`sgproc-render-v2.1-*` precedent) to avoid overwriting the child-wallet workstream's own v2.2 archive; the git tag for this milestone is `sgproc-render-v2.2`, not bare `v2.2`.

---

_For current project status, see `.planning/workstreams/sgproc-render/ROADMAP.md`_
