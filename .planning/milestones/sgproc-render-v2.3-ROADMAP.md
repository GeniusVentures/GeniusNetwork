# Milestone v2.3: Deferred Gap Closure — sgproc-render workstream

**Status:** ✅ SHIPPED 2026-08-21
**Phases:** 16-19
**Total Plans:** 14

## Overview

Not new feature work — this milestone closed four real, previously-surfaced gaps that no prior milestone had picked up: Phase 08's deferred manifest-evolution scope (deferred 2026-08-05), an untested cross-hardware risk on the render path flagged in v2.2's STATE.md, a pre-existing build-stability bug (found 2026-08-10), and an unverified assumption about whether v2.2's Phase 15 fix actually closed v2.1's VALD-01 finding. Unlike v2.1's hard-chained Phases 10-13 or v2.2's Phase 14→15 dependency, all four v2.3 phases were independent of one another and executed in requirements-list order rather than a dependency order.

## Phases

### Phase 16: Manifest Evolution

**Goal**: The execution manifest evolves from Phase 08's baseline shape to close two of its explicitly deferred gaps — structured errors carry a human-readable message string retrievable from the manifest artifact, and the binary format supports additive schema evolution proven in both compatibility directions (new-writer-old-reader and old-writer-new-reader).
**Depends on**: Phase 15 (v2.2, shipped) — first phase of v2.3; independent of Phases 17-19 in this milestone
**Requirements**: ARTF-07, ARTF-08, ARTF-09, ARTF-10
**Plans**: 3/3 plans complete

Plans:

- [x] 16-01: Corrected REQUIREMENTS.md/ROADMAP.md wording for ARTF-07/ARTF-08 to "Won't implement — not applicable"
- [x] 16-02: Added `ExecutionManifest::errorMessage` field + append-only schema-evolution trailer in `SerializeManifest`/`DeserializeManifest` (ARTF-09/ARTF-10)
- [x] 16-03: Built a manifest on every terminal path in `ProcessInternal()`; proved `GetLastManifest()` reachability against real CANCELLED/BUDGET_EXCEEDED fixtures (ARTF-09)

**Details:**

ARTF-07 (Merkle tree over chunk hashes) and ARTF-08 (content-defined chunking) were concluded "Won't implement — not applicable" during phase discussion (16-CONTEXT.md D-01..D-08): `Artifact::chunkHashes` already gives full per-chunk localization and graphsync/protobuf already deliver the complete chunk-hash list to every real verifier, so a root-only Merkle proof serves no scenario this system's actual verification flow has; `block_len` is a job-poster-owned schema parameter, not SGProcessingManager's to renegotiate. `errorMessage[256]` was appended as `ExecutionManifest`'s last member reusing `MAX_IDENTIFIER`, with `MANIFEST_V2_SERIALIZED_SIZE` expressed as an arithmetic expression anchored to `MANIFEST_SERIALIZED_SIZE` (never a hardcoded literal); `DeserializeManifest`'s two trailer bounds checks (schema-version presence, then errorMessage presence) were kept strictly sequential and independent. `ProcessingManager::ProcessInternal()` now builds and stores a minimal manifest on every terminal path via a new `GetLastManifest()` accessor, reusing the same fallback error-string literal already present at the generic-error log call so all four terminal states get real `ProcessingError::message` text.

### Phase 17: Render-Path Cross-Hardware Tolerance

**Goal**: The render path gains three non-trivial fixtures (texturing, blending, and lighting — MSAA excluded per D-03's architectural hard-block) that actually exercise floating-point-heavy render computation, and a real, schema-configurable tolerance mechanism for its output comparison — replacing `QuantizeByteBuffer`'s current byte-identity no-op — closing the untested risk v2.2's STATE.md flagged: that the render path's byte-identity claim was only ever measured against a near-zero-computation 8x8 solid-color fixture.
**Depends on**: Nothing beyond already-shipped foundations (Phase 10's capture/diff tooling, Phase 14's `ResolveQuantScale`/`ResolveByteQuantMode` pattern) — independent of Phases 16, 18, 19 in this milestone
**Requirements**: RENDTOL-01, RENDTOL-02
**Plans**: 9/9 plans complete (17-09 is a gap-closure plan that closed RENDTOL-02's blending residual gap)

Plans:

- [x] 17-01: Lighting fixture (shaders, vertex data, job JSON)
- [x] 17-02: Blend-state schema extension + wire-format pairing + `BuildPipeline` wiring + blending fixture
- [x] 17-03: `texture_buffer` schema/wire-format/validation contract
- [x] 17-04: Texture upload/sampler/descriptor Vulkan infrastructure + texturing fixture
- [x] 17-05: Round 1 cross-machine capture (raw, byteQuantMode-absent divergence), all three fixtures
- [x] 17-06: Binary-search `byteQuantMode` + counter-test for lighting and blending
- [x] 17-07: Binary-search `byteQuantMode` + counter-test for texturing
- [x] 17-08: Round 2 cross-machine capture with final tolerances, SC4 verdict, ROADMAP close-out
- [x] 17-09: Gap-closure — extended `capture_diff` with a raw-buffer numeric-tolerance check to prove blending's `byteQuantMode=6` against already-captured Round 2 data

**Details:**

All three fixtures were confirmed to exercise genuine per-fixture floating-point computation — 17-06 found and fixed a real push-constant field-order bug in `lighting_fragment_shader.glsl` that had made the lighting fixture render solid black (a degenerate zero-divergence artifact, not proof of tolerance), and 17-07 confirmed texturing's zero divergence is honest, not a hidden defect, via a corrupted-source-image counter-test. Round 1 capture confirmed real cross-hardware divergence in blending (`maxAbsDelta=1.0`) while lighting and texturing measured zero divergence. `byteQuantMode` values were derived via binary search against dedicated SECV-01-style counter-tests: lighting=5, blending=6, texturing=7 — each proven one step below a confirmed corruption-masking boundary. Round 2's final capture hash-matched lighting (fresh measurement against the corrected shader) and texturing (confirmed never diverging), but blending's quantized divergence got *worse* than raw (`maxAbsDelta` 1.0 → 64.0), root-caused to `QuantizeByteBuffer`'s bit-masking (no rounding tie-break) amplifying boundary-straddling raw deltas — a real architectural limitation, escalated as a human decision. The user chose a numeric-tolerance-fallback resolution (D-10/D-11) over redesigning `QuantizeByteBuffer`: grounding research found production's `AttemptToleranceFallback` already runs `IsByteChunkWithinTolerance` on raw pre-quantization bytes and would already accept blending's real divergence — the actual gap was that `capture_diff`'s own offline verification tool never called that function. Gap-closure Plan 17-09 wired an opt-in `--byte-quant-mode` raw-tolerance check into `capture_diff`, reusing `IsByteChunkWithinTolerance` unmodified, proving blending's real raw delta (1.0) is within `byteQuantMode=6`'s tolerance bound (63) against already-captured Round 2 `preQuantizeBytes` — no new hardware capture round, no production code changed. The strict quantized-hash mismatch remains true and is documented side by side with the passing tolerance-fallback result, not reinterpreted.

### Phase 18: Build Stability

**Goal**: `ProcessingManager::Create()`'s Vulkan capability probe no longer deadlocks when a real Vulkan device is present, closing the `VulkanInitMutex` re-entrancy bug that currently blocks `ProcessingDatatypesTest`, `ProcessingDispatchTest`, and `vulkan_init_concurrency_test`.
**Depends on**: Nothing — an independent, pre-existing build-stability bug unrelated to manifest or render-path work
**Requirements**: BUILD-01
**Plans**: 1/1 plans complete

Plans:

- [x] 18-01: Added D-03's regression `TEST_F` + CMake `TIMEOUT` to `vulkan_init_concurrency_test`, then ran the scoped 3-test gate and documented the BUILD-01 closure evidence trail

**Details:**

Independent re-verification (both a dedicated research pass and the verifier) confirmed the `VulkanInitMutex` re-entrancy self-deadlock was already fixed by pre-existing `SGProcessingManager` commit `528a92a`, predating the bug's 2026-08-10 todo filing — the described deadlock did not reproduce on current HEAD (4/4 clean runs). Closed as verify-and-close rather than a new fix: added `TEST_F(VulkanConcurrentInitTest, CreateSucceedsWithRealVulkanDevicePresent)` pinning the exact no-hang scenario against a real Vulkan device, plus a CMake `set_tests_properties(... TIMEOUT 12)` fail-fast bound (derived from an observed 2.99s run, ×4 margin) so a future regression fails fast in CI instead of hanging the suite. No changes to `VulkanInitMutex()`, `CapabilityValidator::BuildSnapshot()`, or `RenderProcessor::InitializeContext()` — the locking model itself was explicitly out of scope.

### Phase 19: Validation Re-Verification

**Goal**: Determine, with real evidence rather than assumption, whether Phase 15's `ValidateResults` tolerance-fallback mechanism actually closes VALD-01's original MNN float32 gap (Phase 13's 12/15 chunk-hash mismatch finding) — and document the outcome honestly, whichever way it lands.
**Depends on**: Phase 15 (v2.2, shipped) — re-runs its tolerance-fallback mechanism against pre-existing Phase 13 fixture data
**Requirements**: VALD-02
**Plans**: 1/1 plans complete

Plans:

- [x] 19-01: Added 2 new TEST cases to `processing_validation_core_test.cpp` feeding a real `.cap` fixture pair through `ValidateResults`/`AttemptToleranceFallback`, and documented the honest closed/partially-closed/still-open outcome in `19-REVERIFICATION.md`

**Details:**

Discovered mid-phase that Phase 13's archived `.cap` fixture pair (the exact fixture behind the original 12/15 chunk-hash-mismatch finding) is unreadable by current tooling — `SGProcessingManager` commit `bf7e694` (Phase 17) made `DeserializeCaptureFile` unconditionally require the post-Phase-16 `MANIFEST_V2_SERIALIZED_SIZE` region, silently breaking backward compatibility with every pre-Phase-16 `.cap` file. Presented as a 3-way checkpoint; the user chose a fresh 2-machine capture over touching production code or leaving VALD-02 unresolved. The fresh capture (Mac + Windows, 2026-08-21) independently reproduced Phase 13's exact original signature (chunk 10, `maxAbsDelta=3.0517578125e-05`, `maxUlpDistance=2048`) via an unmodified `capture_diff` cross-check. `ValidateResults`/`AttemptToleranceFallback` (unmodified since Phase 15) genuinely engages for chunk 10 and resolves it as a tolerant match — no error, zero subtasks invalidated across the full 15-chunk fixture — captured via `AttemptToleranceFallback`'s own debug log line (`maxAbsDelta=3.0517578125e-05 maxRelDelta=0.00015477479610126466 withinTolerance=true`). **VALD-02 classified CLOSED**: the underlying cross-hardware numeric divergence still physically exists and is not eliminated — what closes is whether the comparison mechanism correctly absorbs it, which it does. No production code was modified (D-04); the newly-discovered `DeserializeCaptureFile` backward-compatibility regression is filed as a new deferred item, not fixed.

---

## Milestone Summary

**Key Decisions:**

- Phase structure is 4 phases (16-19), one per REQUIREMENTS.md category — coarse granularity per config.json, at the upper end of the preferred 3-4 phase range because all four categories are genuinely independent delivery units.
- Unlike v2.1's hard-chained Phases 10-13 or v2.2's Phase 14→15 chain, all four v2.3 phases are independent of one another — no phase blocks or is blocked by another within this milestone; phase numbering (16-19) follows REQUIREMENTS.md's listed order, not an execution dependency.
- BUILD-01 (Phase 18) and VALD-02 (Phase 19) kept as their own single-requirement phases rather than folded into a neighbor: both were explicitly scoped as independent gap-closure units at requirements time, each with its own clear, testable success bar.
- RENDTOL-02's blending residual gap closed via numeric-tolerance fallback (reusing Phase 15's `IsByteChunkWithinTolerance` unmodified) rather than redesigning `QuantizeByteBuffer` or accepting a documented override — the lowest-risk fix, reusing already-proven production code.
- VALD-02 re-run against a fresh 2-machine capture (not Phase 13's original archived fixture) after that fixture was found unreadable by current tooling — an explicit user choice over fixing the unrelated parsing regression or leaving the requirement unresolved.

**Issues Resolved:**

- Phase 08's deferred manifest-evolution scope (ARTF-09/ARTF-10): the manifest now carries human-readable error text and supports additive schema evolution proven in both compatibility directions. ARTF-07/ARTF-08 formally concluded "Won't implement — not applicable" rather than left as stale pending items.
- The untested render-path cross-hardware risk flagged in v2.2's STATE.md: three non-trivial render fixtures now exist and are cross-hardware proven (lighting/texturing via strict hash-match, blending via a production-proven numeric-tolerance fallback).
- The pre-existing `VulkanInitMutex` re-entrancy deadlock report (BUILD-01) — confirmed already fixed by a pre-existing commit, closed with a persistent regression test rather than left as an open, unverified todo.
- VALD-01's residual MNN float32 chunk-10 gap — confirmed, with real re-run evidence, that Phase 15's tolerance-fallback mechanism genuinely absorbs it.

**Issues Deferred:**

- XNODE-01c (actual cross-node consensus/redundant-execution plumbing) — still explicitly out of scope; considered CI-verification scope, not application-level work for this workstream.
- Phase 04 (v1.0) carryover UAT/verification gap — re-surfaced by the pre-close artifact audit for the third milestone running (v2.0, v2.2, now v2.3), unrelated to this milestone's own work, acknowledged again rather than resolved.

**Technical Debt Incurred:**

- `DeserializeCaptureFile`'s backward-compatibility regression (Phase 17's commit `bf7e694` cannot parse any pre-Phase-16 `.cap` file) — discovered during Phase 19, explicitly left unfixed (out of that phase's scope), not yet queued to a specific future phase.
- `QuantizeByteBuffer`'s bit-masking design has no rounding tie-break and can amplify boundary-straddling raw deltas (proven for blending in Phase 17) — worked around via a numeric-tolerance fallback rather than a redesign; the underlying bit-masking behavior is unchanged.

**Milestone-Archive Naming Note:** This project runs parallel GSD workstreams (`sgproc-render`, `gnus-subnets`, and the child-wallet track at root `.planning/`). The child-wallet workstream independently owns its own bare `v2.3-ROADMAP.md`/`v2.3-REQUIREMENTS.md`/git tag `v2.3` ("Child Wallet Transfers", still planned/unshipped at the time this milestone closed). This archive and its companion `sgproc-render-v2.3-REQUIREMENTS.md` are workstream-qualified filenames (matching the `sgproc-render-v2.0-*` through `sgproc-render-v2.2-*` precedent) to avoid overwriting the child-wallet workstream's own v2.3 archive; the git tag for this milestone is `sgproc-render-v2.3`, not bare `v2.3`. (An initial `gsd-tools.cjs milestone complete v2.3` run without `--ws`/qualified naming did briefly overwrite the child-wallet workstream's bare `v2.3-ROADMAP.md`/`v2.3-REQUIREMENTS.md` and appended a garbled entry to `MILESTONES.md`/`STATE.md` — caught immediately via `git status`/`git diff` before any commit, fully reverted via `git checkout --`, and re-archived by hand under the qualified names below. Same collision class already flagged after v2.0/v2.2's closes; the CLI tool itself still has no workstream-namespacing for archive output.)

---

_For current project status, see `.planning/workstreams/sgproc-render/ROADMAP.md`_
