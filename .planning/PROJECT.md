# GNUS Child Wallet

## What This Is

Child wallets (subwallets) for the GNUS SuperGenius node. Games integrating the GNUS SDK operate independent child wallets that can earn GNUS, hold and transfer assets, and optionally register a main wallet — without ever exposing the main wallet's private key.

## Core Value

The main wallet must be able to discover, monitor, and manage registered child wallets through consensus-visible state — every child-wallet behavior maps onto concrete SuperGenius anchor points (GeniusAccount, TransactionManager, CRDT/GlobalDB, PubSubBroadcasterExt, consensus validation).

## Current State

**Shipped:** v2.4 Merge origin/develop into dev_childwallet (2026-07-24) — SuperGenius's `dev_childwallet` branch is current with `origin/develop` via merge commit `cb4e46da` (162 commits caught up, `DevConfig_st`→`GeniusNodeConfig` rename swept across ~17 files, zero regressions across the full child-wallet suite), pushed to `origin/dev_childwallet`. GeniusSDK's `dev_childwallet` is current with the same `origin/develop` baseline via merge commit `6969fac`, pushed, and confirmed building cleanly against the updated SuperGenius static lib. Phase 7 (GeniusSDK side) was completed directly by the user outside the formal GSD plan/execute workflow — see MILESTONES.md Known Gaps.

**Previously shipped:** v2.3 Phase 4 GeniusSDK Transfer Wrappers (2026-07-21) — external games/apps can fund a registered child wallet (`GeniusSDKFundChild`/`GeniusSDKFundChildGNUS`) and recover funds from it (`GeniusSDKRecoverFromChild`/`GeniusSDKRecoverFromChildGNUS`) entirely through the public GeniusSDK C API, wrapping Phase 3's `GeniusNode::TransferFunds`/`RecoverFromChild` calls with no new business logic.

## Current Milestone

This project now runs parallel workstreams (see `.planning/workstreams/`). Each tracks its own milestone independently.

### Workstream: milestone (child-wallet track)

**Goal:** Give `node_example`'s interactive REPL commands to register the node as a child wallet, list children registered to a main wallet, and query child balances — using `GeniusNode`'s existing `RegisterChild`/`GetRegistrationsForMain`/`GetChildBalance` C++ methods directly (no GeniusSDK C API changes, no GeniusWallet UI this milestone).

**Target features (v2.5):**
- `registerchild <main_address>` — registers this node as a child of the given main wallet; derives `dev_wallet` from `dev_config_.Addr`, `peers_cut` as `1,000,000 - ParseMinions(dev_config_.Cut)` (10^6 fixed-point scale), and mock placeholder values for `game_id`/`publisher_id` (unused downstream today)
- `listchildren <main_address>` — lists all children registered to a main wallet, including each child's balance
- `childbalance <child_address> [token_id]` — queries a single child's balance (specific token, or all-tokens total when omitted)

**Deferred candidates carried forward from prior milestones** (see Requirements > Deferred below):
- MON-01/MON-02: Full monitoring dashboard (per-child balance, all assets/tokens, activity history, escrow status, lifecycle monitoring)
- API-01: gRPC endpoint exposing child registration/balance to external callers
- TOK-01: Multi-token balance query (GNUS, child tokens, NFTs)
- POL-01: Transfer amount limits/policy beyond CONS-01/CONS-02
- UI-01: GeniusWallet Flutter UI wiring for child-wallet transfers

### Workstream: sgproc-render

**Goal:** Make SGProcessingManager's `render` PassType a real, executable graphics pipeline via hand-rolled Vulkan — headless/offscreen, own independent `VkInstance`/`VkDevice`, no new GPU backend/engine, no OpenGL or CPU/software fallback tier. Directly scoped to `GeniusVentures/SGProcessingManager#7`.

**Target features (next milestone):**
(None yet — define via `/gsd-new-milestone --ws sgproc-render`)

**Deferred candidates carried forward:**
- Actual cross-node consensus/redundant-execution comparison plumbing (`XNODE-01c`) — v2.2 made the comparison mechanism itself correct and tolerant; wiring it into real multi-node job orchestration remains future work
- Phase 04 (v1.0) carryover: 1 pending UAT scenario + a `human_needed` verification gap — re-acknowledged at v2.0, v2.2, and now v2.3 close; still unresolved
- `DeserializeCaptureFile` cannot parse any pre-Phase-16 `.cap` file (Phase 17's commit `bf7e694` unconditionally requires the newer `MANIFEST_V2_SERIALIZED_SIZE` region) — discovered during v2.3 Phase 19, left unfixed, not yet queued to a specific future phase

**Shipped (v1.0 + v2.0):** v1.0 — all 5 phases, 24 plans complete (2026-07-31): headless Vulkan context + shared init-lock + dispatch plumbing; schema extension + shaderc/SPIRV-Tools + mandatory spirv-val gate; RenderProcessor (pipeline build, offscreen draw, readback, SHA-256 hash); cross-platform CI + E2E; Android/iOS platform compatibility. v2.0 — Phase 09 (issue #15, conformance test suites) complete (2026-08-07), 15/15 plans across three gap-closure rounds; this was the last roadmapped phase for v2.0. Full v2.0 milestone completion was never formally asserted via `/gsd-complete-milestone`: Phase 07's `EXEC-*` and Phase 08's `ARTF-*` requirement checkboxes in `.planning/milestones/sgproc-render-v2.0-REQUIREMENTS.md` remain unchecked, and STATE.md notes Phase 07 tests are "pending HW verification". See `.planning/workstreams/sgproc-render/STATE.md` for details.

**v2.1 Cross-Hardware Hash Tolerance — SHIPPED 2026-08-13** (4 phases, 15 plans): capture/diff tooling (Phase 10), empirical 2-machine capture (Phase 11), real quantization/normalization + SECV-01 counter-test (Phase 12), re-validation + scope-boundary documentation (Phase 13). Closed via an accepted maintainer override on VALD-01: the render fixture fully matches cross-hardware; the MNN float32 fixture retains one residual, exhaustively-characterized gap (chunk 10, exactly one S=2^15 grid-step boundary tie-break, FP16 backend opportunism ruled out) accepted as this milestone's final stopping point rather than left open pending architecture-level work. Full archive: `.planning/milestones/sgproc-render-v2.1-ROADMAP.md`/`REQUIREMENTS.md`. See `13-VERIFICATION.md` for the override and `13-SCOPE-BOUNDARY.md` for the full diagnostic trail.

**v2.2 Cross-Hardware Validation Tolerance — SHIPPED 2026-08-14** (2 phases, 7 plans): kicked off 2026-08-13, directly motivated by v2.1's closing findings (the tex3d/spleen_ct_seg per-workload divergence evidence, and the recognition that a real `ValidateResults` fix needs tolerance for bounded/characterized divergence, not just bit-exact hash equality). Phase 14 (Configurable Normalization Precision) — QUANT-CFG-01/02/03 all validated: schema-configurable `quantScale`/`byteQuantMode` wired into all 21 existing call sites across 14 processor files, silent fallback to v2.1's exact constants when unconfigured, and `tex3d`/`spleen_ct_seg` given its own empirically-derived `quantScale=128.0`. Phase 15 (Validation Comparison Mechanism) — XNODE-01b/XNODE-02/SECV-02 all validated: fixed the `ValidateResults` concatenation bug (chunk hashes were being appended instead of compared), added a quantScale-derived numeric-tolerance fallback with fixed-constant fallback (new `sgprocmanagerdiff` shared library extracted from `capture_diff`), wired real production IPFS-fetch/job-schema-resolution capabilities, and proved the combined mechanism still catches a genuinely corrupted result via a new full-pipeline SECV-02 counter-test. Verified, 8/8 must-haves passed. Closed via an acknowledged carryover: the pre-close artifact audit re-surfaced the same Phase 04 (v1.0) UAT/verification gap already accepted at v2.0 close, unrelated to and unchanged by this milestone's own work. Full archive: `.planning/milestones/sgproc-render-v2.2-ROADMAP.md`/`REQUIREMENTS.md` (workstream-qualified filenames — see Key Decisions table for why).

**v2.3 Phase 16 (Manifest Evolution) — COMPLETE 2026-08-18, 3/3 plans.** Closed two of Phase 08's explicitly deferred gaps: `ExecutionManifest` gained a new `errorMessage[256]` field (ARTF-09) delivered via a bounds-checked, append-only binary trailer mechanism (ARTF-10) that lets `SerializeManifest`/`DeserializeManifest` grow the format without breaking any existing fixed-offset field, proven in both new-writer-old-reader and old-writer-new-reader directions. `ProcessingManager::ProcessInternal()` now builds and stores a minimal manifest (with real, non-empty error text) on every terminal path via a new `GetLastManifest()` accessor, proven against real CANCELLED/BUDGET_EXCEEDED/Success fixtures. ARTF-07 (Merkle tree over chunk hashes) and ARTF-08 (content-defined chunking) were formally concluded "Won't implement — not applicable" (16-CONTEXT.md D-01..D-08): `Artifact::chunkHashes` already gives full per-chunk localization to every real verifier, and `block_len` is a job-poster-owned schema parameter, not SGProcessingManager's to renegotiate.

**v2.3 Phase 17 (Render-Path Cross-Hardware Tolerance) — COMPLETE 2026-08-20, verified 5/5 must-haves, 9/9 plans.** Added three non-trivial render fixtures (lighting, blending, texturing — MSAA excluded per D-03) exercising real floating-point-heavy computation, replacing the trivial 8x8 solid-color fixture's byte-identity-only coverage. Cross-machine capture (2 rounds) proved lighting/texturing hash-match cleanly; blending's `QuantizeByteBuffer` bit-masking (no rounding tie-break) instead amplified its real raw divergence (`maxAbsDelta=1.0`) into a worse quantized divergence (`maxAbsDelta=64.0`) — escalated as a human decision, resolved via gap-closure Phase 17-09: extended `capture_diff`'s own SC4 methodology with an opt-in raw-buffer tolerance check reusing production's existing `IsByteChunkWithinTolerance` (from Phase 15's `AttemptToleranceFallback`) unmodified, proving blending's real divergence was already within the production-proven bound — no change to `QuantizeByteBuffer`/`IsByteChunkWithinTolerance`/`ValidateResults`, and the strict quantized-hash mismatch stays honestly documented alongside the new passing result. RENDTOL-01/RENDTOL-02 both fully satisfied.

**v2.3 Phase 18 (Build Stability) — COMPLETE 2026-08-20, verified 4/4 must-haves, 1/1 plan.** Independent re-verification (both a dedicated research pass and the verifier) confirmed BUILD-01's `VulkanInitMutex` re-entrancy self-deadlock in `ProcessingManager::Create()`'s capability probe was already fixed by pre-existing `SGProcessingManager` commit `528a92a`, predating the bug's 2026-08-10 todo filing — the described deadlock does not reproduce on current HEAD. Closed as verify-and-close rather than a new fix: added `TEST_F(VulkanConcurrentInitTest, CreateSucceedsWithRealVulkanDevicePresent)` to `vulkan_init_concurrency_test.cpp` pinning the exact no-hang scenario against a real Vulkan device, a CMake `set_tests_properties(... TIMEOUT 12)` fail-fast bound (derived from an observed 2.99s run, ×4 margin) so a future regression fails fast in CI instead of hanging the suite, and a documented evidence trail (`18-BUILD-STABILITY-EVIDENCE.md`). No changes to `VulkanInitMutex()`, `CapabilityValidator::BuildSnapshot()`, or `RenderProcessor::InitializeContext()` — the locking model itself was explicitly out of scope (ROADMAP SC4).

**v2.3 Phase 19 (Validation Re-Verification) — COMPLETE 2026-08-21, verified 6/6 must-haves, 1/1 plan.** Re-ran VALD-01's original MNN float32 fixture through Phase 15's already-shipped `ValidateResults`/`AttemptToleranceFallback` tolerance-fallback mechanism and confirmed it genuinely engages for chunk 10 and resolves it as a tolerant match (`maxAbsDelta=3.0517578125e-05`, within the `2.0/32768.0=6.103515625e-05` D-03 bound; no error, zero subtasks invalidated across all 15 chunks) — VALD-02 classified **CLOSED**. Mid-execution, Phase 13's original archived `.cap` fixture pair was found unreadable by current tooling (a genuine `DeserializeCaptureFile` backward-compatibility regression from Phase 17's commit `bf7e694`, unrelated to this phase); resolved by running a fresh 2-machine capture (Mac + Windows) that independently reproduced Phase 13's exact original numeric signature. No production code modified (D-04) — only a test-layer harness addition. The newly-discovered parsing regression is filed as a new deferred item, not fixed (out of scope). All 8 v2.3 (Deferred Gap Closure) requirements are now complete — ready for `/gsd-complete-milestone`.

**v2.3 Deferred Gap Closure — SHIPPED 2026-08-21** (4 phases, 14 plans, 35 tasks): closed four real, previously-surfaced gaps that no prior milestone had picked up — Phase 08's deferred manifest-evolution scope (Phase 16), the untested render-path cross-hardware risk flagged in v2.2's STATE.md (Phase 17), a pre-existing Vulkan capability-probe deadlock report (Phase 18), and an unverified assumption about whether v2.2's Phase 15 fix actually closes v2.1's VALD-01 finding (Phase 19). All 8 v2.3 requirements resolved (6 delivered, 2 formally concluded won't-implement-not-applicable), 0 dropped. Closed via an acknowledged carryover: the pre-close artifact audit re-surfaced the same Phase 04 (v1.0) UAT/verification gap already accepted at v2.0/v2.2 close, unrelated to this milestone's own work (all 4 phases fully complete and verification-passed with no gaps of their own). Full archive: `.planning/milestones/sgproc-render-v2.3-ROADMAP.md`/`REQUIREMENTS.md` (workstream-qualified filenames — the child-wallet workstream independently owns bare `v2.3-*`/git tag `v2.3` for its own, still-unshipped "Child Wallet Transfers" milestone). No v2.4 requirements defined yet for this workstream.

**Context:** All v2.0 work on the SGProcessingManager branch consumed by `SuperGenius/develop`. Issues #12/#13/#14 support GCS/EIS integration. Issue #15 tracks issues #7–#14. No new GPU backend — continues the hand-rolled Vulkan approach from v1.0. Vulkan Validation Layers were explicitly deferred from v1.0 CTX-04.

### Workstream: gnus-subnets

**Goal:** Produce design documentation defining how isolated GNUS subnets (e.g. `144.100` under main net `144`) address, communicate, bridge tokens, and isolate job/consensus processing — no implementation this milestone.

**Target deliverables (v1.0, docs-only, one phase each):**
- Subnet addressing scheme — `net_id.subnet_id` composition, `config_json` placement, validation/allocation
- PubSub channel namespacing — how `subnet_id` folds into topic names for traffic isolation
- Bridge/gateway design — GNUS token movement between main net and subnet, trust model
- Job isolation & consensus impact — subnet-scoped job scheduling, CRDT/registration/validation-gate subnet-awareness

## Requirements

### Validated

- ✓ Child-wallet identity model (emergent identity, independent keypair) — v2.0
- ✓ RegistrationTransaction — proto schema, C++ class, CRDT filter with 4 gates — v2.0
- ✓ Registration sequence numbering and monotonicity enforcement — v2.0
- ✓ PubSub broadcast and CRDT sync (reg/ namespace, D-49 RegElementCallback) — v2.0
- ✓ GetRegistrationsForMain — scans reg/ CRDT and returns discovered children — v2.0
- ✓ Main wallet queries child token balance from synced CRDT UTXOs (`GeniusNode::GetChildBalance`) — v2.1 Phase 1
- ✓ Integration test validates balance query after registration + funding (`MainQueriesChildBalance`) — v2.1 Phase 1
- ✓ GeniusSDK wrapper exposes child registration (`GeniusSDKRegisterChild`, wraps `RegisterChild` auto-derive overload) — v2.2
- ✓ GeniusSDK wrapper exposes child discovery (`GeniusSDKGetRegistrationsForMain`) — v2.2
- ✓ GeniusSDK wrapper exposes child balance query (`GeniusSDKGetChildBalance`/`GeniusSDKGetChildBalanceAll`) — v2.2, fulfilled API-02
- ✓ `CheckParentChildAuthority` consensus gate enforces CONS-01 (main→child fund) — v2.3 Phase 3
- ✓ `CheckParentChildAuthority` consensus gate enforces CONS-02 (main-recover-from-child, destination-restricted per D-21) — v2.3 Phase 3
- ✓ Regression coverage confirms CONS-03/04/05 invariants (child→arbitrary, child→main, child→dev, child-cannot-spend-main) hold unchanged with the new gate in place — v2.3 Phase 3 (REGR-01/02/03)
- ✓ GeniusSDK wrapper exposes main→child fund transfer (`GeniusSDKFundChild`/`GeniusSDKFundChildGNUS`) — v2.3 Phase 4, fulfilled SDKT-01
- ✓ GeniusSDK wrapper exposes main-recover-from-child transfer (`GeniusSDKRecoverFromChild`/`GeniusSDKRecoverFromChildGNUS`) — v2.3 Phase 4, fulfilled SDKT-02
- ✓ Both transfer wrappers return existing `GeniusNodeReturnValue_t` codes with no new enum value added — v2.3 Phase 4, fulfilled SDKT-03
- ✓ SuperGenius `dev_childwallet` merged with `origin/develop`, conflicts resolved incl. `DevConfig_st`→`GeniusNodeConfig` rename — v2.4, fulfilled MERGE-01
- ✓ GeniusSDK `dev_childwallet` merged with the remaining `origin/develop` commit — v2.4, fulfilled MERGE-02 (completed directly by user, no formal GSD phase artifacts)
- ✓ SuperGenius builds cleanly post-merge — v2.4, fulfilled MVER-01
- ✓ GeniusSDK builds cleanly against updated SuperGenius static lib — v2.4, fulfilled MVER-02 (user attestation only, no captured build log)
- ✓ Full existing child-wallet test suite passes with zero regressions post-merge — v2.4, fulfilled MVER-03
- ✓ `origin/develop`'s changes confirmed compatible with child-wallet consensus gates — v2.4, fulfilled MVER-04
- ✓ `GeniusSDK`/`GeniusWallet` resolve `vk-bootstrap::vk-bootstrap` transitively via mirrored `find_package(vk-bootstrap CONFIG REQUIRED)` — sgproc-render Phase 01.1, fulfilled CMAKE-01
- ✓ All 13 remaining CPU-backed MNN processors migrated to `MNN_FORWARD_VULKAN` under the existing shared `VulkanInitMutex()` — sgproc-render Phase 01.1, fulfilled MIGR-01
- ✓ Vulkan-init call-site documentation/tests updated to describe the full post-migration caller set instead of a stale count — sgproc-render Phase 01.1, fulfilled MIGR-02
- ✓ Migration correctness proven via the existing `ProcessingDatatypesTest` suite + concurrent-init stress test — no new coverage tooling introduced — sgproc-render Phase 01.1, fulfilled COV-01
- ✓ Processing schema fully describes a render pass (render_target/vertex+index buffers/multi-stage shaders/pipeline state), quicktype-regenerated with zero hand-edits — sgproc-render Phase 2, fulfilled SCHEMA-01..05
- ✓ GLSL compiled to SPIR-V via vendored `shaderc`; all SPIR-V (compiled or directly submitted) validated via mandatory `spirv-val` gate before reaching `vkCreateShaderModule` — sgproc-render Phase 2, fulfilled SHADER-01/02/03
- ✓ `RenderProcessor` builds a vertex+fragment graphics pipeline from schema-declared, validated SPIR-V with schema-configurable pipeline state — sgproc-render Phase 3, fulfilled RENDER-01/04
- ✓ Vertex/index buffers resolved and uploaded via direct Vulkan buffer APIs, rendering offscreen (no swapchain) with push-constant/descriptor-set uniform fallback at the 128-byte threshold — sgproc-render Phase 3, fulfilled RENDER-02/03/05
- ✓ Rendered output read back via `vkCmdCopyImageToBuffer`, exposed as `texture2D` output, feeding the unmodified `ProcessingResult` → hash path — sgproc-render Phase 3, fulfilled RENDER-06/07/08
- ✓ `VkResult` failures map to structured `ProcessingManager::Error` values with clear per-stage messages, for both the new render path and (per broadened scope) the pre-existing MNN dispatch path — sgproc-render Phase 3, fulfilled RENDER-09
- ✓ Same render pass definition executed 10x on the same node produces a bit-exact matching output hash every time, empirically proven against real hardware — sgproc-render Phase 3, fulfilled DETV-01/02
- ✓ CTest conformance suites cover every registered executor against a common contract — schema parsing, executor selection, output hashing, cancellation, capability checks, backward-compat adapters, and regression locks for all four known v1.0 bugs — sgproc-render Phase 09, fulfilled TEST-01..10 (round 3 gap closure: capability_validator PassType rejection message, processing_dispatch_test ctest working-directory, render-pass happy-path combinedHash)
- ✓ Real fixed-precision normalization on both render (uint8, byte-identity) and MNN (float32, fixed-point scale-round-cast) output paths, applied identically before per-chunk and combined hash calls, constants cited directly to Phase 11's captured data — sgproc-render Phase 12, fulfilled QUANT-01/02/03/04
- ✓ SECV-01 wrong-result-still-diverges counter-test (corrupted MNN model + wrong render shader constant, both binary `ASSERT_NE` on post-quantization hash) — sgproc-render Phase 12, fulfilled SECV-01
- ✓ Schema-configurable per-data-type normalization precision (`quantScale`/`byteQuantMode` via the existing generic `parameters` array), read by `QuantizeFloatBuffer`/`QuantizeByteBuffer` at all 21 existing call sites instead of the hardcoded v2.1 constant, with a silent exact-v2.1-behavior fallback on absent/invalid input — sgproc-render Phase 14, fulfilled QUANT-CFG-01/02
- ✓ `tex3d`/`spleen_ct_seg` configured with its own empirically-derived `quantScale=128.0`, proven by a dedicated SECV-01-style counter-test to still catch a genuinely corrupted model, cited against real captured cross-machine divergence data (`0.005126953125`) — sgproc-render Phase 14, fulfilled QUANT-CFG-03
- ✓ `ProcessingValidationCore::ValidateResults` actually compares same-chunk hashes across subtasks instead of concatenating them, with a bounded quantScale-derived numeric-tolerance fallback (fixed-constant fallback when unconfigured) built on a new shared `sgprocmanagerdiff` library extracted from `capture_diff` — sgproc-render Phase 15, fulfilled XNODE-01b/XNODE-02
- ✓ SECV-02 full-pipeline counter-test proves the fixed `ValidateResults` + tolerance fallback acting together still catch a genuinely corrupted subtask result via `SubTaskQueueAccessorImpl`'s real public API — sgproc-render Phase 15, fulfilled SECV-02
- ✓ Three non-trivial render fixtures (lighting, blending, texturing) exercising real FP-heavy computation, cross-hardware proven via two capture rounds — sgproc-render Phase 17, fulfilled RENDTOL-01
- ✓ Real schema-configurable render-output tolerance mechanism, proven independently against all three RENDTOL-01 fixtures (lighting/texturing via strict hash-match, blending via a new production-proven numeric-tolerance fallback) — sgproc-render Phase 17 (+ gap-closure Phase 17-09), fulfilled RENDTOL-02
- ✓ `ProcessingManager::Create()`'s Vulkan capability-probe no longer deadlocks with a real Vulkan device present, closed via a persistent regression `TEST_F` + fail-fast CMake `TIMEOUT` pinning the scenario, plus a documented evidence trail (the underlying `VulkanInitMutex` re-entrancy was already fixed by pre-existing commit `528a92a`, predating the bug report) — sgproc-render Phase 18, fulfilled BUILD-01
- ✓ `ExecutionManifest`'s structured error details carry a human-readable message string alongside the existing structured error code, built on every terminal path of `ProcessInternal()` via a new `GetLastManifest()` accessor — sgproc-render Phase 16, fulfilled ARTF-09
- ✓ The manifest's binary format supports additive schema evolution (new optional fields) without breaking older readers, proven in both new-writer-old-reader and old-writer-new-reader directions via an append-only bounds-checked trailer — sgproc-render Phase 16, fulfilled ARTF-10
- ✓ Merkle tree over chunk hashes / content-defined chunking — **Won't implement, not applicable** (`Artifact::chunkHashes` already gives full per-chunk localization to every real verifier; `block_len` is a job-poster-owned schema parameter, not SGProcessingManager's to renegotiate) — sgproc-render Phase 16, resolved ARTF-07/ARTF-08
- ✓ The original VALD-01 MNN float32 fixture re-run through `ValidateResults`/`AttemptToleranceFallback`, confirmed to genuinely engage for the residual chunk-10 gap and resolve it as a tolerant match (no error, zero subtasks invalidated) — sgproc-render Phase 19, fulfilled VALD-02, classified CLOSED

### Active

(None yet — define next milestone's requirements via `/gsd-new-milestone`)

### Deferred (candidates for future milestones)

- MON-01/MON-02: Full monitoring dashboard — per-child balance, all assets/tokens, activity history, escrow status, lifecycle monitoring
- API-01: gRPC endpoint exposing child registration/balance to external callers (SDK wrapper covered in v2.2 instead)
- TOK-01: Multi-token balance query (GNUS, child tokens, NFTs) — v2.1/v2.2 covered child token only
- POL-01: Transfer amount limits/policy beyond CONS-01/CONS-02 (e.g. per-child caps, rate limiting)
- UI-01: GeniusWallet Flutter UI wiring for child-wallet transfers

### Out of Scope

- Balance display formatting (FormatTokens/ConvertToChildToken) — deferred to API phase
- Direct child query (request/response) — balance computed from synced CRDT only, no live query to child node
- gRPC endpoint exposure (API-01) — SDK wrapper is the direct-link path for v2.2; gRPC still deferred
- GeniusWallet Flutter UI wiring — SDK/node-layer milestones only so far; UI consumption is a future milestone
- New proto messages/schema changes for registration — `RegistrationMetadata`/`RegistrationTx` already cover v2.0-v2.2 needs
- Dedicated `GeniusSDK/test` unit tests — GeniusSDK is a thin C FFI wrapper; SuperGenius already covers the underlying `GeniusNode`/`TransactionManager` logic (see project memory)

## Context

- v1.0 shipped implementation-ready design documents covering identity, registration, CRDT/registry, pubsub sync, consensus authority, discovery/monitoring, and reward policy
- v2.0 implemented the first slice: child-signed registration with CRDT persistence, pubsub broadcast, and multi-node integration tests
- The main node already subscribes to child pubsub topics via D-49 RegElementCallback and syncs the child's CRDT deltas — the UTXO data is already present locally
- The existing `GeniusNode::GetBalance(token_id, address)` → `UTXOManager::GetBalance(token_id, address)` pattern sums UTXOs filtered by address and token ID — the same mechanism can target a child address
- v2.1 shipped `GeniusNode::GetChildBalance` (token-filtered + all-tokens overloads) as a thin alias over this pattern, plus a multi-node integration test proving the child-mint → CRDT-sync → main-query round-trip
- v2.2 exposed `RegisterChild`/`GetRegistrationsForMain`/`GetChildBalance` through the public `GeniusSDK.h`/`.cpp` C API (4 wrapper functions, 2 new C structs), so external games/apps no longer need to link SuperGenius directly
- Fixed a pre-existing SuperGenius/evmrelay CMake packaging gap (missing `find_dependency(evmrelay)`/`evmrelayTargets.cmake` include) plus a Boost::coroutine MSVC template-instantiation error that had blocked full GeniusSDK static-lib builds — full build now confirmed green
- No dedicated `GeniusSDK/test` unit tests exist for the v2.2 wrapper functions — SuperGenius's existing `GeniusNode`/`TransactionManager` tests already cover the wrapped logic
- v2.3 Phase 3 added `Blockchain::CheckCertifiedParent` (D-63 certified-parent lookup, zero `genius_node` dependency to preserve the one-directional `blockchain_genesis` ← `genius_node` library link) and a narrow D-60 signature-acceptance branch in `CheckTransactionAuthorization`/`ValidateWitness`, so a certified main's signature is accepted on a child-sourced recovery transaction without weakening any other signature check
- While building Phase 3's regression tests, found and fixed a pre-existing gap: `TransactionManager`'s `transaction_parsers` dispatch table had no entry for the `"registration"` tx type, so every registration transaction was rejected as "Unknown tx type" before it could ever reach a certified state — the certified-parent mechanism this milestone depends on could never have worked without this fix
- v2.4 merged both SuperGenius and GeniusSDK `dev_childwallet` branches current with `origin/develop` (162 commits caught up on SuperGenius), resolving the `DevConfig_st`→`GeniusNodeConfig` rename across ~17 files with zero child-wallet regressions; an unrelated `thirdparty` submodule drift was root-caused as blocking some real-networked E2E fixtures (DI-06-01), not a regression from the merge itself
- sgproc-render Phase 3's final plan (03-06, the empirical N≥10 determinism test) discovered a real, previously-unknown bug on its first run: `RenderProcessor::InitializeContext()`'s `vkb::PhysicalDeviceSelector` defaults `require_present=true`, which rejects every physical device when no `VkSurfaceKHR` exists — invisible until this plan's fixture became the first render-pass definition to actually reach device selection with fetchable input data. Fixed via `selector.require_present(false)`; after the fix, 10/10 repeat runs produced byte-identical SHA-256 hashes and the full regression suite (31/31 MNN + 9 pre-existing dispatch tests) stayed green
- sgproc-render Phase 11 (data-gathering checkpoint, no code) closed out this session's ad-hoc capture run as the milestone's formal empirical input: real cross-hardware divergence stats now exist for both fixtures (MNN float32 max ULP distance 768; render uint8 byte-identical content hash but a combined-hash mismatch worth Phase 12's attention) across the accepted 2-machine dataset (D-01), written to `11-CAPTURE-RESULTS.md` for Phase 12's normalization design to cite directly
- sgproc-render Phase 14 (Configurable Normalization Precision) wired all 21 existing `QuantizeFloatBuffer`/`QuantizeByteBuffer` call sites across 14 processor files to resolve a schema-declared `quantScale`/`byteQuantMode` value, falling back to v2.1's exact constants when absent/invalid. The new tex3d-specific SECV-01 counter-test's binary search found no failure boundary in the valid power-of-two domain for a real single-byte-corrupted `spleen_ct_seg.mnn` (256 down to 1 all passed) — the final `quantScale=128.0` was instead chosen via the divergence-absorption constraint (grid step must exceed the real measured `0.005126953125` cross-hardware delta), a notable finding for future per-workload precision tuning: this style of corrupted-model counter-test does not always yield a precision ceiling
- sgproc-render Phase 15 (Validation Comparison Mechanism) fixed `ValidateResults`'s concatenation bug by restructuring its internal `chunks` map to `chunkKey -> {subtaskId -> hashBytes}`, added a bounded numeric-tolerance fallback (extracting `capture_diff`'s comparison primitives into a new shared `sgprocmanagerdiff` library plus new D-03/D-04 tolerance-derivation functions), and wired real production capabilities (`ProcessingCore::GetTaskQueue()` for job-schema lookup, real `FileManager`-backed IPFS fetch on hash mismatch only). The final SECV-02 counter-test plan found two test-design bugs while building the harness (not production bugs): SECV-01's existing corrupted-model fixture produced a bit-identical post-quantization chunk hash at the required single-window granularity (needed a new dedicated `secv02-corrupted-float_model.mnn` fixture), and the two test jobs' outputs collided on the same file path (masking the tolerance-fallback's fetch) until given distinct output filenames
- sgproc-render Phase 17 (Render-Path Cross-Hardware Tolerance) verification found blending's `QuantizeByteBuffer` bit-masking (no rounding tie-break) amplifies a real 1-unit raw cross-hardware delta into a full-bucket-width (64-unit) quantized delta when the two raw values straddle a `2^N`-aligned boundary — the tolerance mechanism made divergence worse, not better, for this one fixture (lighting/texturing were unaffected, zero raw divergence). Escalated as a human decision (redesign `QuantizeByteBuffer` / numeric-tolerance fallback / accept as override); user chose numeric-tolerance fallback. Grounding research found Phase 15's production `AttemptToleranceFallback` already runs `IsByteChunkWithinTolerance` on raw pre-quantization bytes and would already accept blending's real divergence — the actual gap was that Phase 17's own offline `capture_diff` verification tool never called that function, only compared strict quantized-hash bytes. Gap-closure Phase 17-09 wired an opt-in `--byte-quant-mode` raw-tolerance check into `capture_diff` reusing the existing function unmodified, proving the gap closed using already-captured Round 2 data — no new hardware capture round, no production code changed. Worth remembering for any future byte-quantized fixture: an offline/CLI verification tool's pass bar can silently drift stricter than what production actually enforces if the two aren't kept in sync.

## Known Issues

- `child_registration_test.exe` segfaults on process teardown (after all GTest assertions pass) — pre-existing lifecycle issue, likely unjoined libp2p/boost::asio threads during node `.reset()`, not caused by v2.1/v2.2 changes. Reproduces with only the 3 pre-v2.1 test cases. Tracked in `.planning/phases/01-child-balance-query/deferred-items.md`; candidate for a future test-infra/node-shutdown-hygiene phase. Same class of issue also seen on `registration_transaction_test.exe` (exit 139 after GTest PASSED summary).
- Phase 2 (v2.2) closed without a formal `VERIFICATION.md` — the verify step was never re-run after implementation. Coverage was manually cross-checked against source and later build-confirmed, but no verification artifact exists. Milestone closed via explicit user override; see STATE.md Deferred Items.
- Phase 7 (v2.4, GeniusSDK Merge & Build Verification) has no formal GSD phase artifacts — MERGE-02 and MVER-02 were completed directly by the user. Merge commits independently confirmed via git history; MVER-02's build success rests on user attestation only, no build log captured. Milestone closed via explicit user override.
- An unrelated `thirdparty` submodule drift (fast-forwarded same-day during Phase 6 build troubleshooting) causes `registration_transaction_test.exe`/`child_registration_test.exe` to crash deterministically on real-networked E2E fixture `SetUp()` (BOOST_ASSERT in libp2p Kademlia `StorageImpl`), blocking most E2E cases in those binaries. Traced to a `gossip_pubsub.cpp`/`boost::di` config-lifetime change between the recorded and current `ipfs-pubsub` commits — not caused by the origin/develop merge. See `.planning/milestones/v2.4-phases/06-supergenius-merge-regression-verification/deferred-items.md` (DI-06-01).
- sgproc-render v2.0 (Execution Contracts & Quality Gates) closed via explicit user override on 2026-08-07: Phase 04 (v1.0 carryover) has 1 pending UAT scenario and a `human_needed` verification gap never formally resolved; Phases 06-08 are not `phase_complete`/verification-passed per `init.manager` (only Phase 09 is), with Phase 07's tests specifically pending HW verification. See MILESTONES.md's v2.0 Known Gaps and STATE.md Deferred Items for full detail.

## Constraints

- **Tech stack**: C++17/C++20, CMake, Boost.Asio, libp2p, Protocol Buffers — must match existing SuperGenius conventions
- **Coding standard**: Corelinux-derived C++ style — Ullman braces, PascalCase types, `m_`/trailing-underscore member prefix
- **Compatibility**: Must not break existing SuperGenius, GeniusSDK, or GeniusWallet builds
- **Security**: Main-wallet private key must never enter the child process; child balance is read-only from consensus-visible state; a future transfer path must preserve this (child signs its own spends, main cannot spend on the child's behalf)
- **Serialization**: No new proto messages needed through v2.2 — registration and balance query reused existing `RegistrationTx`/UTXO wire formats; a transfer feature will likely need `TransferTransaction` reuse rather than a new proto message, to be confirmed during v2.3 scoping

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Emergent child identity (D-01) | Child-ness derived from registration record, not creation-time flag | ✓ Good |
| Child-signed-only registration (D-04/D-05) | Main does not counter-sign; compromise bounded to child | ✓ Good |
| RegistrationTx as first-class transaction (D-06) | Reuses TransactionManager path identically to TransferTx | ✓ Good |
| CRDT reg/ namespace (D-11/D-12) | Registration records in `/bc-{net}/reg/{child_addr}`, not `tx/` | ✓ Good |
| D-49 main follows child's pubsub | RegElementCallback subscribes on reg/ delta arrival | ✓ Good |
| Balance from synced CRDT (v2.1) | No direct query; use UTXOManager on locally-synced data | ✓ Good |
| GeniusSDK wraps only auto-derive RegisterChild overload (v2.2) | Manual-sequence overload stays C++-internal (tests/replay), keeps public C API surface minimal | ✓ Good |
| No dedicated GeniusSDK/test unit tests (v2.2) | Thin FFI wrapper; SuperGenius already covers the wrapped GeniusNode/TransactionManager logic | ✓ Good |
| Milestone v2.2 closed via verification override | Phase 2 implementation was manually cross-checked and build-confirmed, but formal VERIFICATION.md was never generated; user chose to proceed rather than backfill it | ⚠️ Revisit — consider closing this gap before v2.3 if it recurs |
| D-60: certified-main signature accepted on child-sourced tx via CRDT registration, not cryptographic delegation (Phase 3) | Verified against current code that main's signature cannot verify against a child's address under a literal-delegation model; CRDT-derived authority was the user's directional call | ✓ Good — narrowly scoped, owner-address check left untouched |
| Registration-dispatch no-op fix (Phase 3) | Discovered mid-implementation that registration txs could never be certified without a `transaction_parsers` entry; fixed with a narrowly-scoped no-op rather than touching `FilterRegistration`/`RegElementCallback` | ✓ Good |
| Merge commit over rebase for `dev_childwallet` (v2.4) | Both SuperGenius and GeniusSDK `dev_childwallet` branches already shared/pushed; rebase would rewrite shared history | ✓ Good |
| `CrdtSet::mutex_` reentrancy root cause over original DAG-broadcast hypothesis (Phase 5, revisited v2.4) | Live-debugger stack trace during Phase 6 regression testing confirmed the fix (`std::recursive_mutex`) held under the merged `origin/develop` code paths too | ✓ Good |
| Phase 7 (v2.4) completed outside formal GSD workflow, milestone closed via override | User completed the GeniusSDK merge/build verification directly; no `07-*` plan/verification artifacts exist, but git history independently confirms both merge commits are pushed | ⚠️ Revisit — same pattern as the v2.2 Phase 2 gap; consider running `/gsd-plan-phase`/`/gsd-execute-phase` retroactively if a future milestone needs a formal Phase 7 verification trail |
| Fresh build + full teardown per `StartProcessing()` call, no cross-job Vulkan object caching (sgproc-render Phase 3, D-22) | Zero shared mutable GPU state between jobs gives the simplest possible story for DETV-01's determinism claim | ✓ Good — empirically confirmed: 10/10 repeat runs bit-exact |
| Synchronous `vkDeviceWaitIdle` + full teardown before `StartProcessing()` returns, no deferred/async cleanup (sgproc-render Phase 3, D-23) | User raised a host-game-coexistence concern; resolved because RenderProcessor uses its own independent `VkInstance`/`VkDevice`/`VkQueue` (Phase 1, CTX-01), so this can only block RenderProcessor's own device, never a host application's separate one | ✓ Good — explicitly re-confirmed with the user, not silently revisited |
| sgproc-render v2.0 closed via override despite Phases 06-08 not `phase_complete`/verified and Phase 04's carryover UAT/verification gap | User chose to close now and defer HW/formal verification to a future checkpoint (v2.1 or v3.0) rather than block the new milestone on it — same override pattern as v2.2/v2.4 | ⚠️ Revisit — verification for Phases 06-08 and Phase 04 remains outstanding |
| sgproc-render's v2.0 milestone archive filenames workstream-qualified (`sgproc-render-v2.0-*` instead of bare `v2.0-*`) | The generic `milestone.complete` CLI archives to shared `.planning/milestones/v[X.Y]-*` paths with no workstream namespacing; child-wallet had already used bare `v2.0-ROADMAP.md`/`v2.0-REQUIREMENTS.md` for its own v2.0 milestone, and the first invocation silently overwrote them (caught before commit, restored from git, re-archived under a qualified name) | ⚠️ Revisit — any future `/gsd-complete-milestone` run in a multi-workstream project must pass a workstream-qualified version string or immediately rename the archive output to avoid the same collision |
| Phase 11 accepts a 2-machine cross-hardware dataset (Mac + Windows), not the literal "≥3 machines" in v2.1's original target wording / QUANT-04 (sgproc-render D-01) | WSL's only available Vulkan device is `llvmpipe`, a software rasterizer already excluded project-wide by Phase 4's D-31; a third real machine wasn't available, and loosening the device-acceptance gate just for this one box was rejected as project-wide scope creep | ✓ Good — ROADMAP.md Phase 11 SC1/Goal and REQUIREMENTS.md QUANT-04 reconciled to 2-machine wording; Phase 12/13's own "3-machine" wording deliberately left untouched pending their own planning |
| No SECV-01 failure boundary found for tex3d/spleen_ct_seg's corrupted-model counter-test down to S=1; final `quantScale=128` chosen via the divergence-absorption constraint instead (sgproc-render Phase 14, D-10) | A single severe byte corruption in this much larger real segmentation model propagates into divergence larger than any power-of-two grid in the valid domain could mask — unlike the small MNN model's Phase 13 search, which found a real S=2^14 boundary | ✓ Good — still empirically grounded (real measured delta cited, real counter-test re-run at the chosen value); worth remembering this style of counter-test doesn't always yield a precision ceiling |
| sgproc-render's v2.2 milestone archive filenames workstream-qualified (`sgproc-render-v2.2-*` instead of bare `v2.2-*`) | Same shared-namespace collision as v2.0/v2.1: the child-wallet workstream already owns bare `v2.2-ROADMAP.md`/`v2.2-REQUIREMENTS.md`/git tag `v2.2` (GeniusSDK Child Wallet Interfaces) | ✓ Good — caught proactively this time by checking `.planning/milestones/` and `git tag -l` before archiving, no working-tree collision occurred |
| sgproc-render v2.2 closed via acknowledged carryover (Phase 04 gap, unrelated to Phase 14/15) rather than blocking on a fresh `/gsd-audit-milestone` run | Phase 04's gap was already accepted at v2.0 close and is unchanged; both v2.2 phases themselves are fully complete/verified with no open gaps of their own | ✓ Good — narrowly scoped override, doesn't touch this milestone's actual deliverables |
| RENDTOL-02's blending residual gap closed via numeric-tolerance fallback (reusing Phase 15's `IsByteChunkWithinTolerance` unmodified) rather than redesigning `QuantizeByteBuffer` or accepting a documented override (sgproc-render Phase 17, D-10/D-11) | Grounding research found production's `AttemptToleranceFallback` already applies this exact check to raw bytes and would already accept blending's real divergence; the actual gap was `capture_diff`'s own offline verification tool never calling it — lowest-risk fix, reuses proven code, no change to `QuantizeByteBuffer`/`ValidateResults` | ✓ Good — proven against already-captured data, no new hardware capture round needed |
| BUILD-01 treated as verify-and-close, not a new fix (sgproc-render Phase 18, D-03) | Direct repro (4/4 clean runs) plus git-archaeology (`528a92a` predates the todo filing) both showed the described deadlock already fixed; re-fixing already-fixed code would have been wasted, riskier work | ✓ Good — closure backed by a persistent regression test + evidence trail, not just a manual repro or a re-citation of stale claims |
| ARTF-07/ARTF-08 concluded "Won't implement — not applicable" rather than deferred again (sgproc-render Phase 16, D-01..D-08) | `Artifact::chunkHashes`/graphsync/protobuf already deliver everything a root-only Merkle proof would add; `block_len` is a job-poster-owned schema parameter this system has no business renegotiating | ✓ Good — closes a 2026-08-05 deferral with an explicit "not applicable" rather than letting it silently re-surface at every future milestone close |
| VALD-02 re-run against a fresh 2-machine capture instead of Phase 13's original archived fixture (sgproc-render Phase 19, D-01-REVISED) | Phase 13's original `.cap` files were found unreadable by current tooling (an unrelated `DeserializeCaptureFile` backward-compat regression from Phase 17); user chose a fresh capture over fixing that regression or leaving VALD-02 unresolved | ✓ Good — fresh capture independently reproduced Phase 13's exact original signature, so the re-verification rests on equivalent evidence |
| sgproc-render's v2.3 milestone archive filenames workstream-qualified (`sgproc-render-v2.3-*` instead of bare `v2.3-*`) | Same shared-namespace collision as v2.0/v2.1/v2.2: the child-wallet workstream already owns bare `v2.3-ROADMAP.md`/`v2.3-REQUIREMENTS.md`/git tag `v2.3` (still-unshipped "Child Wallet Transfers"). This time an initial `gsd-tools.cjs milestone complete v2.3` run without workstream-qualified naming briefly overwrote the child-wallet files and appended a garbled MILESTONES.md/STATE.md entry — caught via `git status`/`git diff` before any commit, fully reverted, re-archived by hand under the qualified names | ⚠️ Revisit — the `milestone.complete` CLI still has no built-in workstream-namespacing for archive output; every future close in this repo must either pass a pre-qualified version string or immediately check `git status` before trusting its output |
| sgproc-render v2.3 closed via acknowledged carryover (Phase 04 gap, unrelated to Phases 16-19) for the third milestone running | Phase 04's gap was already accepted at v2.0/v2.2 close and is unchanged; all four v2.3 phases are fully complete/verified with no open gaps of their own | ✓ Good — narrowly scoped override, doesn't touch this milestone's actual deliverables; still genuinely unresolved and worth a dedicated closure phase eventually |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-08-21 — sgproc-render v2.3 (Deferred Gap Closure) milestone complete and archived: all 4 phases (16-19) shipped, 8/8 requirements resolved, closed via an acknowledged Phase 04 carryover. Full archive: `.planning/milestones/sgproc-render-v2.3-*.md`, git tag `sgproc-render-v2.3`. No v2.4 requirements defined yet for this workstream.*
