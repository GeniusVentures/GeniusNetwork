# Milestones

## v2.3 Deferred Gap Closure — sgproc-render workstream (Shipped: 2026-08-21)

**Phases completed:** 4 phases, 14 plans, 35 tasks

Full archive: `.planning/milestones/sgproc-render-v2.3-ROADMAP.md`, `.planning/milestones/sgproc-render-v2.3-REQUIREMENTS.md` (filenames workstream-qualified — the child-wallet workstream already owns bare `v2.3-ROADMAP.md`/`v2.3-REQUIREMENTS.md`/git tag `v2.3` for its own, still-unshipped "Child Wallet Transfers" milestone; same collision class as v2.0/v2.1/v2.2).

**Key accomplishments:**

- REQUIREMENTS.md and ROADMAP.md's Phase 16 bookkeeping now shows ARTF-07 (Merkle tree) and ARTF-08 (content-defined chunking) as "Won't implement — not applicable," citing 16-CONTEXT.md D-01..D-08, instead of a stale "Pending"/Merkle-CDC goal.
- `ExecutionManifest` gains a new `errorMessage[256]` field (ARTF-09) delivered via a bounds-checked, append-only binary trailer mechanism (ARTF-10) that lets `SerializeManifest`/`DeserializeManifest` grow the format without breaking any existing fixed-offset field or hardcoded-literal test.
- `ProcessingManager::ProcessInternal()` now builds and stores a minimal `ExecutionManifest` (with a real, non-empty `errorMessage`) on every terminal path via a new `GetLastManifest()` accessor, proven against real CANCELLED/BUDGET_EXCEEDED/Success fixtures.
- Three non-trivial render fixtures (lighting, blending, texturing) proven to exercise genuine floating-point-heavy render computation via real two-machine capture — replacing the render path's only-ever-tested trivial 8x8 solid-color fixture.
- A real schema-configurable render-output tolerance mechanism (`byteQuantMode`, mirroring Phase 14's `ResolveQuantScale` pattern) replaces `QuantizeByteBuffer`'s byte-identity no-op; lighting/texturing hash-match cross-hardware, and blending's residual gap (quantization made its real divergence *worse*, not better) is closed via a numeric-tolerance-fallback proof reusing production's `IsByteChunkWithinTolerance` unmodified — no new hardware capture, no production code changed.
- Confirmed BUILD-01's Vulkan capability-probe deadlock was already fixed by pre-existing commit `528a92a`, closed verify-and-close with a persistent regression `TEST_F` + CMake fail-fast `TIMEOUT`.
- Two new gtest cases prove `ProcessingValidationCore::ValidateResults`/`AttemptToleranceFallback` genuinely closes VALD-01's residual chunk-10 MNN float32 gap (`maxAbsDelta=3.0517578125e-05`, within the `2.0/32768.0` bound), re-run against a fresh 2-machine capture after Phase 13's archived fixture was found unreadable by current tooling — VALD-02 classified CLOSED.

### Known Gaps

- **Phase 04 (v1.0 carryover) re-surfaced, unresolved**: the pre-close artifact audit found the same `04-UAT.md` (1 pending scenario) and `04-VERIFICATION.md` (`human_needed`) gaps already acknowledged at v2.0 and v2.2 close — still open, unrelated to and unchanged by this milestone's own work (all 4 v2.3 phases are fully complete and verification-passed with no gaps of their own).
- **New this milestone**: `DeserializeCaptureFile` cannot parse any pre-Phase-16 `.cap` file (a Phase 17 commit, `bf7e694`, unconditionally requires the newer `MANIFEST_V2_SERIALIZED_SIZE` region) — discovered during Phase 19 (VALD-02), explicitly left unfixed as out of that phase's scope, not yet queued to a specific future phase.
- Milestone closed via acknowledged carryover (`closeout_type=override_closeout` on the Phase 04 item only) — same pattern as this workstream's v2.0/v2.1/v2.2 closeouts. See STATE.md Deferred Items for the full acknowledgment record.

---

## v2.2 Cross-Hardware Validation Tolerance — sgproc-render workstream (Shipped: 2026-08-14)

**Phases completed:** 2 phases, 7 plans, 14 tasks

Full archive: `.planning/milestones/sgproc-render-v2.2-ROADMAP.md`, `.planning/milestones/sgproc-render-v2.2-REQUIREMENTS.md` (filenames workstream-qualified — the child-wallet workstream already owns bare `v2.2-ROADMAP.md`/`v2.2-REQUIREMENTS.md`/git tag `v2.2` for its own "GeniusSDK Child Wallet Interfaces" milestone; same collision class as v2.0/v2.1, this time checked for and avoided proactively before writing anything).

**Key accomplishments:**

- `ResolveQuantScale`/`ResolveByteQuantMode` free functions centralize schema-declared `quantScale`/`byteQuantMode` lookup with an exact silent-fallback contract (32768.0f / 0, matching v2.1's constants byte-for-byte when unconfigured); `QuantizeFloatBuffer`/`QuantizeByteBuffer` gain a new required (non-defaulted) parameter so a missed call site fails to compile rather than silently using stale behavior.
- All 21 existing `QuantizeFloatBuffer`/`QuantizeByteBuffer` call sites across 14 MNN/render processor files wired to the new resolvers with zero deviations — every file matched the research's grep-confirmed enumeration exactly (line numbers, suppression-statement text, call-site text).
- `tex3d`/`spleen_ct_seg` (a real ~19.3MB medical CT segmentation model) configured with its own empirically-derived `quantScale=128.0` (2^7): a binary search over power-of-two candidates against a new dedicated SECV-01-style counter-test found **no failure boundary** anywhere in the valid domain (256 down to 1 all passed) — a notable finding, unlike Phase 13's small-model search which found a genuine boundary — so the final value was instead chosen via the divergence-absorption constraint (grid step must exceed the real measured `0.005126953125` cross-hardware delta).
- `ProcessingValidationCore::ValidateResults`'s `chunks` map restructured from a single shared-buffer concatenation to `chunkKey -> {subtaskId -> hashBytes}`, fixing a real bug where same-chunk hashes across subtasks were being appended instead of compared — a genuine cross-node mismatch would have silently passed before this fix.
- New bounded numeric-tolerance fallback for chunk-hash mismatches, via a new shared `sgprocmanagerdiff` static library extracted from `capture_diff`'s comparison primitives (colocated with Phase 14's `sgprocmanagerquant`) — quantScale-derived threshold when configured, fixed-constant fallback otherwise.
- Wired real production capabilities in place of stubs: a new `ProcessingCore::GetTaskQueue()` interface method for job-schema lookup, and a real `FileManager::LoadASync`-based IPFS fetch on hash-mismatch only (no new I/O on the trivial matching-hash path).
- SECV-02 full-pipeline counter-test proved the combined fix (concatenation-bug fix + tolerance fallback) still catches a genuinely corrupted subtask result via `SubTaskQueueAccessorImpl`'s real public API — required a new dedicated corrupted-model fixture (`secv02-corrupted-float_model.mnn`) since SECV-01's existing fixture wasn't divergent enough at the required single-window granularity, plus a fix for an output-path collision between the two test jobs (both test-design issues found while building the harness, not production bugs).

### Known Gaps

- **Phase 04 (v1.0 carryover) re-surfaced, unresolved**: the pre-close artifact audit found the same `04-UAT.md` (1 pending scenario) and `04-VERIFICATION.md` (`human_needed`) gaps already acknowledged at v2.0 close (2026-08-07) — still open, unrelated to and unchanged by this milestone's own work (both v2.2 phases are fully complete and verified with no gaps of their own).
- Milestone closed via acknowledged carryover (`closeout_type=override_closeout`) on the Phase 04 item only — same pattern as this workstream's v2.0/v2.1 closeouts. See STATE.md Deferred Items for the full acknowledgment record.

---

## v2.1 Cross-Hardware Hash Tolerance — sgproc-render workstream (Shipped: 2026-08-13)

**Phases completed:** 4 phases, 15 plans, 32 tasks

**Closed with an accepted override:** VALD-01's MNN fixture retains a residual 1/15-chunk cross-hardware divergence (chunk 10, exactly one S=2^15 grid step, confirmed a rounding-boundary tie-break with FP16 backend opportunism ruled out) — accepted as this milestone's final stopping point via the maintainer override in `13-VERIFICATION.md` rather than left open pending an architecture-level fix. A real fix requires per-workload configurable tolerance (QUANT-CFG-01) and/or a numeric-tolerance-fallback comparison mechanism in `ProcessingValidationCore::ValidateResults` (XNODE-01b), both scoped to the new v2.2 milestone.

Full archive: `.planning/milestones/sgproc-render-v2.1-ROADMAP.md`, `.planning/milestones/sgproc-render-v2.1-REQUIREMENTS.md` (filenames workstream-qualified to avoid colliding with the child-wallet workstream's own pre-existing v2.1 milestone archive).

**Key accomplishments:**

- Added the `sgprocmanagerquant` identity-stub library (mirrors `sgprocmanagersha`) and `ExecutionContext::rawOutputCapture`, the two foundation pieces every Wave 2/3 plan in this phase builds on.
- Wired the quantize-then-capture-then-hash pattern into all 6 stitched-family MNN processors (Float, Int, Mat2, Mat3, Mat4, Tensor) at both their per-chunk and stitched-combined hash call sites, exercising Plan 10-01's `sgprocmanagerquant`/`rawOutputCapture` foundation for the first time at real call sites.
- Wired the quantize-then-capture-then-hash pattern into all 7 chained-family MNN processors at their chunk-level hash call site(s) only (8 insertion points total: 6 single-branch files + TextureCube's 2 branches), explicitly leaving all 8 rolling combined-hash call sites untouched since they hash already-quantized-hash bytes, not re-quantizable float data.
- Wired the quantize-then-capture-then-hash pattern into RenderProcessor's single (non-chunked) combined-hash call site, and created the new `sgns::sgproccapture` capture file binary format that reuses `SerializeArtifact`/`SerializeManifest` unmodified and appends a bounds-checked, length-prefixed raw-bytes section.
- Built `capture_harness` (runs a fixture N times, self-checks CAPT-02/CAPT-03, writes a `.cap` file) and `capture_diff` (reports DIFF-01/02 numeric divergence plus DIFF-03 hash-match booleans to console+JSON), wired into a new non-CTest-gated `tools/` CMake tree -- Phase 10's literal deliverable.
- Wired SGProcessingManager/test/ into the main SuperGenius build for the first time and added a CTest-registered `capture_smoke_test` proving `capture_harness` produces a well-formed, round-trippable `.cap` file -- plus a root-cause fix for a pre-existing `enable_testing()` ordering bug that had silently made every test under `SGProcessingManager/test/` undiscoverable by `ctest`.
- Formalized this session's ad-hoc Mac+Windows capture run as Phase 11's deliverable: relocated 6 evidence files into a phase-owned `captures/` directory, wrote `11-CAPTURE-RESULTS.md` citing the exact diff-JSON numbers (maxAbsDelta ≈1.043e-07, maxRelDelta ≈7.27e-05, maxUlpDistance 768 for MNN-float; contentHashMatch true / combinedHashMatch false for render), and reconciled ROADMAP.md/REQUIREMENTS.md/STATE.md's stale "3-machine" wording to the accepted 2-machine scope.
- Replaced Phase 10's no-op quantization stubs with real IEEE-754 canonicalization + fixed-point 2^20-grid rounding for MNN float output, kept the render byte path deliberately identity, and added a dedicated CTest suite plus an integration test proving the two independent hash layers agree.
- New `processing_conformance_security_test` CTest target proves, for both the MNN inference path and the render path, that a deliberately corrupted/wrong result still produces a different post-quantization artifact hash than the correct result -- confirming Plan 12-01's real quantization tolerance is not loose enough to also mask a substituted model or shader constant.
- 4 fresh xhw-mnn-float/xhw-render .cap files captured on Mac + Windows against Phase 12's real QuantizeFloatBuffer/QuantizeByteBuffer logic, verified distinct in content from Phase 11's stub-era captures.
- Incremental rebuild + verbose ctest re-run proves SECV-01's existing counter-test still diverges correctly at Phase 12's final quantization precision (both sub-tests genuinely PASSED, not skipped, on this machine's real RTX 4070 Ti SUPER), and REQUIREMENTS.md/ROADMAP.md's stale "≥3 machines"/"combined hash" wording is corrected to the accepted 2-machine scope and processor-level hash target via scoped edits.
- Fresh Mac-vs-Windows `capture_diff` re-run under Phase 12's real quantization shows the render fixture's processor-level hash now matches cross-hardware, but the MNN float32 fixture's still does not (12/15 chunk hashes diverge) — recorded honestly in `13-SCOPE-BOUNDARY.md` as an open gap against VALD-01/SC1, alongside the milestone's explicit scope-boundary statement and SC4's final normalization-constant derivation.
- QuantizeFloatBuffer's MNN float32 rounding grid widened to S=2^15 (32768.0f) -- not the plan's originally-specified S=2^14 -- after S=2^14 was found to deterministically regress SECV-01's corrupted-model counter-test; a local binary search over power-of-two values found S=2^15 the widest value still safe, and 2 fresh cross-machine captures were taken with the fix active.
- Fresh capture_diff on the correct (newest) Mac-vs-Windows MNN capture pair under the S=2^15 quantization fix: contentHashMatch flipped false→true and chunk divergence narrowed from 12/15 to 1/15, but VALD-01/SC1 correctly stays Partial since chunkHashesMatch[10] is still false.
- Extended capture_diff to numeric-diff every per-chunk raw record, revealing chunk 10's cross-hardware divergence is exactly one S=2^15 grid step on 1 of 64 elements -- a rounding-boundary tie-break, not a scaling error, characterized honestly in 13-SCOPE-BOUNDARY.md without proposing further grid-widening.

---

## v2.0 Execution Contracts & Quality Gates — sgproc-render workstream (Shipped: 2026-08-07)

**Phases completed:** 4 phases, 27 plans, 39 tasks

**Key accomplishments:**

- 06-01-PLAN.md
- 06-02-PLAN.md
- 06-03-PLAN.md
- 06-04-PLAN.md
- 07-01-PLAN.md
- 07-02-PLAN.md
- 07-03-PLAN.md
- 07-04-PLAN.md
- 07-05-PLAN.md
- 09-01 — Shared infrastructure for Phase 09 conformance tests
- 09-02 — Extend processing_datatypes_test for 5 remaining MNN types
- 09-03 — Schema validation + executor selection test executables
- 09-04 — Output hashing & migration adapter test executables
- 09-05 — Cancellation & capability conformance test executables
- 09-06 — Regression tests + RenderProcessor GPU conformance test executable
- 09-07 — Wire all conformance tests into CTest build
- Corrected 2 shared schema fixtures + 4 duplicated inline JSON literals across 2 test files to use ProcessingManager's real Pass/DataType field names (render_shader/render_target/vertex_buffer/vertex_layout, DataType::FLOAT+dimensions), fixing all 6 named UAT-reported acceptance-test failures.
- Added 4 new `ProcessingManager::Error` values with field-specific messages, an explicit `ModelFormat::MNN` executability check in `CheckProcessValidity()`, and a pre-parse raw-JSON scan in `Init()` that intercepts unrecognized `passes[].type`/`passes[].model.format` strings before quicktype's `from_json()` discards their context — closing UAT Gaps 2, 4, and 5.
- Fixed two concrete, unrelated-to-MNN causes of non-deterministic `combinedHash`: brace-initialize `ProcessOutput` so `ExecutionManifest`'s char/uint8_t array fields no longer leak indeterminate stack memory into the hash, and compute the manifest self-hash over a timing-zeroed copy so legitimate per-run wall-clock provenance data no longer varies the content-identity hash.
- Closed 3 goal-backward verification gaps (Gap 1/3/4) by wiring capability_conformance_test to real ProcessingManager::CanExecute() calls, RenderConformanceTest to a real Vulkan device probe + Process() execution, and output_hashing_test to cover artifact metadata + manifest-serialization determinism — plus fixed a genuine pre-existing crash in artifact-metadata building that this work newly exposed.
- Added a backward-compatible 5-arg `ProcessingManager::Process()` overload accepting a caller-owned `ExecutionContext`, then rewrote `cancellation_conformance_test.cpp`'s 5 hollow cases into 6 genuine ones that cancel a real MNN run and a real Vulkan RenderProcessor run mid-flight, enforce a 1-byte output budget, and capture real `ProgressEvent`s — closing Gap 2 (TEST-07), the last confirmed cross-phase production gap from `09-VERIFICATION.md`.
- Schema-driven `maxLength` parameter (16 vs. 128, read from the job's declared parameters) replaces a hardcoded resize literal in `MNN_String::Process()`, fixing the tiny embedding model's reshape error while keeping the legacy BERT model passing, plus a checked `runSession()` return code that now surfaces failures as structured `ProcessingResult.error` instead of reading garbage tensor memory.
- Added a `PassTypeToString()` helper so `CanExecute()`'s PASS_TYPE rejection message and `ListAvailablePassTypes()` embed the human-readable pass-type name alongside the raw int, fixing a stale numeric assumption in `RejectUnregisteredPassType` that broke when quicktype's alphabetized `PassType` enum made `INFERENCE == 2` instead of the assumed `1`.
- Fixed two independent, pre-existing bugs in `processing_dispatch_test`: a CTest working-directory mismatch that caused spurious GLSL `#version` errors on 4 sub-tests, and an empty `outputs: []` declaration on the happy-path render fixture that kept `combinedHash` perpetually empty — closing TEST-01's "full suite passes under ctest" gap and eliminating a vacuous-pass mode in the bit-exact repeat-run test.

### Known Gaps

- **Phase 04 (v1.0 carryover) never formally closed**: `04-UAT.md` has 1 pending scenario and `04-VERIFICATION.md` is marked `human_needed` — pre-existing gaps that predate v2.0, surfaced by the pre-close artifact audit and acknowledged rather than resolved at this milestone's close.
- **Phases 06, 07, 08 are not `phase_complete`/verification-passed per `init.manager`**: only Phase 09 (conformance suites) is formally complete and verified. `EXEC-*` (Phase 07) and `ARTF-*` (Phase 08) requirement checkboxes remain unchecked in the archived requirements. Phase 07's tests are specifically noted as "pending HW verification" in STATE.md history.
- Milestone closed via explicit user override (`closeout_type=override_closeout`) rather than blocking on the above — same pattern as this project's v2.2/v2.4 closeouts. HW/formal verification for Phases 06-08 is deferred to a future checkpoint (v2.1 or v3.0), not resolved here.
- Full archive: `.planning/milestones/sgproc-render-v2.0-ROADMAP.md`, `.planning/milestones/sgproc-render-v2.0-REQUIREMENTS.md` (filenames workstream-qualified to avoid colliding with the child-wallet workstream's own v2.0 milestone archive).

---

## v2.4 Merge origin/develop into dev_childwallet (Shipped: 2026-07-24)

**Phases completed:** 2 phases (6 formally planned/executed via GSD, 7 completed directly by the user), 5 plans, 2 tasks

**Key accomplishments:**

- Two-parent merge commit (SuperGenius `cb4e46da`, parents `5fd137dc` + `2981cd83`) finalizing origin/develop into dev_childwallet, resolving both real conflicts (retired `ProcessingTransaction` consistently) and sweeping the `DevConfig_st`→`GeniusNodeConfig` rename across all ~17 affected files. Push to `origin/dev_childwallet` (initially withheld per explicit user instruction) later confirmed complete — `dev_childwallet` HEAD `500b1969` matches `origin/dev_childwallet` exactly.
- SuperGenius builds cleanly across all targets (`genius_node`, `registration_transaction_test`, `child_registration_test`) post-merge, zero new compiler/linker errors (MVER-01).
- Full pre-existing child-wallet regression suite confirmed zero regressions post-merge — registration, balance query, transfer authority (CONS-01/02), transfer wrappers, and lifecycle Detach/Revoke/ReplaceMain all still pass; consensus gates (`CheckParentChildAuthority`, `FilterRegistration`, `CheckCertifiedParent`, registration-tx dispatch) confirmed compatible with `origin/develop`'s merged changes (MVER-03/MVER-04). An unrelated `thirdparty` submodule drift blocking some real-networked E2E fixtures was root-caused and logged separately (DI-06-01), not a regression from this merge.
- GeniusSDK `dev_childwallet` merged with the 1 remaining `origin/develop` commit via merge commit `6969fac`, pushed to `origin/dev_childwallet` (MERGE-02), and confirmed building cleanly against the Phase-6-updated SuperGenius static lib (MVER-02) — completed directly by the user outside the formal GSD plan/execute workflow, no `07-*` phase artifacts generated.

### Known Gaps

- **Phase 7 has no formal GSD artifacts**: MERGE-02 and MVER-02 were completed and confirmed by the user directly, not through `/gsd-discuss-phase`/`/gsd-plan-phase`/`/gsd-execute-phase`. Git history independently confirms both merge commits exist and are pushed; MVER-02's build success rests on user attestation only, with no captured build log.
- Milestone closed via `--force` override on `gsd-tools.cjs query milestone.complete` since the ROADMAP listed Phase 7 as having 0 plans — see REQUIREMENTS.md archive and STATE.md Deferred Items for full context.

---

## v2.3 Child Wallet Transfers (Shipped: 2026-07-21)

**Phases completed:** 2 phases, 5 plans, 11 tasks

**Key accomplishments:**

- Added `Blockchain::CheckCertifiedParent` (D-63 CRDT certified-status lookup, zero `genius_node` dependency) and `GeniusTransaction::CheckSignatureAgainst` (parameterized signature verification `CheckSignature` now delegates to) — the two shared primitives Plan 02's gate and `CheckTransactionAuthorization` extension build on
- Extended `CheckTransactionAuthorization` and `GeniusInputValidator::ValidateWitness`'s per-input signature check with the narrow D-60 certified-main OR-branch, and added the new `CheckParentChildAuthority` gate enforcing D-21's destination restriction — all three call sites additive, zero behavior change for non-certified-child transactions
- Added `TransactionManager::RecoverFromChild` and `GeniusNode::RecoverFromChild` — the one new transfer-construction method this phase introduces (D-62), building a `TransferTransaction` with `src = child_address`, `dst = main's own address`, spending only the child's own UTXOs, and signed with main's own key so Plan 02's `CheckParentChildAuthority`/`CheckTransactionAuthorization`/`ValidateWitness` extensions can approve it
- Proves, with automated E2E tests against the real consensus pipeline, that CONS-01 and CONS-02 work correctly and that REGR-01/02/03 confirm every existing child-signed path is unaffected by Plans 01-03 — the phase's final empirical closeout.
- 4 new thin C-API wrappers (GeniusSDKFundChild/GNUS, GeniusSDKRecoverFromChild/GNUS) expose Phase 3's TransferFunds/RecoverFromChild to external callers, reusing all existing GeniusNodeReturnValue_t codes

---

## v2.2 GeniusSDK Child Wallet Interfaces (Shipped: 2026-07-20)

**Phases completed:** 1 phases, 1 plans, 2 tasks

**Key accomplishments:**

- Added GeniusSDKRegisterChild, GeniusSDKGetRegistrationsForMain, GeniusSDKGetChildBalance, and GeniusSDKGetChildBalanceAll to the public GeniusSDK C API, wrapping the existing GeniusNode::RegisterChild/GetRegistrationsForMain/GetChildBalance logic with strnlen-bounded proto conversion and a malloc'd/GeniusSDKFree discovery-array pattern.

### Known Gaps

- **Verification override**: Phase 2 has no formal `VERIFICATION.md` on record (`/gsd-execute-phase 2`'s verify step never completed, per `init.manager`). Coverage D1-D3 in `02-01-SUMMARY.md` were verified by manual line-by-line signature cross-check against `GeniusNode.hpp`/`TransactionManager.hpp`/`SGTransaction.proto`, then build-confirmed end-to-end on 2026-07-20 once the evmrelay/coroutine CMake blocker was fixed — but no dedicated verification report exists. Milestone closed with user override rather than running `/gsd-execute-phase 2` to backfill it.

---

## v2.1 Main Wallet Child Balance Query (Shipped: 2026-07-17)

**Phases completed:** 1 phases, 2 plans, 4 tasks

**Key accomplishments:**

- Added `GeniusNode::GetChildBalance` (token-filtered and all-tokens overloads) as thin aliases over the existing `UTXOManager::GetBalance` family, with the child-first/token-first argument-order swap at the delegation boundary — verified by a clean `genius_node_test` build.
- Added `TEST_F(ChildRegistrationIntegrationTest, MainQueriesChildBalance)` proving end-to-end that a child node's mint propagates via CRDT sync to a balance the main node can read through `GetChildBalance` — all 4 cases in `child_registration_test` pass (GTest level), completing ROADMAP Phase 1.

---

## v2.0 Registration Implementation (Shipped: 2026-07-17)

**Phases completed:** 2 phases, 6 plans, 14 tasks

**Key accomplishments:**

- Additive RegistrationTx/RegistrationMetadata proto messages, registration=8 oneof arm, RegistrationTransaction C++ subclass, and passing GTest unit test — proven serialization round-trip from wire bytes through factory to embedded transaction and back.
- Full vertical slice: RegistrationTransaction wired into TransactionManager deserializer dispatch, reg/{child_addr} CRDT path diversion, FilterRegistration element filter with Phase 4 gates, GeniusNode wrapper, and end-to-end GTest proving child-signed registration through the full TM pipeline.
- FilterRegistration sequence monotonicity gate, RegisterChild auto-derive overload, and Phase 4 advisory fixes in the SendTransactionItem reg/ diversion path
- GetRegistrationsForMain CRDT scan with RegistrationDiscoveryEntry struct, GeniusNode two-layer wrapper, and RegElementCallback CID notification handler that auto-follows discovered child channels via AddListenTopic
- Capstone integration test proving child-wallet registration propagates through CRDT/pubsub and is discovered by the main wallet, with negative rejection at the filter level
- Two friend declarations and proto-level signature tampering unblock the multi-node integration test build; all 3 TEST_F cases pass alongside 18 Phase 4 regression tests.

---

## v1.0 Child Wallet Design (Shipped: 2026-07-15)

**Phases completed:** 3 phases, 6 plans, 13 tasks

**Key accomplishments:**

- Complete child-wallet identity model design document specifying independent secp256k1 keypair creation, emergent identity derived from consensus registration state, per-account nonce isolation, and address-based UTXO ownership — all mapped to concrete GeniusAccount/GeniusNode/GeniusUTXO anchor points.
- Complete registration protocol design document specifying the RegistrationTx proto schema, additive proto changes to SGTransaction.proto and Consensus.proto, C++ RegistrationTransaction subclass design, child-signed-only signing protocol with REG-02 reversal documentation, connect flow for main-pubkey delivery, dual-counter sequence numbering for replay protection, and 7-scenario backward-compatibility matrix — all with concrete SuperGenius anchor points.
- CRDT reg/ namespace with four-gate FilterRegistration, CID-only pubsub broadcast, and two-tier certified-status model resolving eventual-consistency vs consensus-ordering tension — all anchored to 27+ concrete SuperGenius code points.
- Complete design document specifying how parent-child authority is enforced by consensus through a new `CheckParentChildAuthority` gate in `ValidateTransactionForConsensus`, with all six CONS rules mapped to concrete SuperGenius pipeline stages and anchor points.
- Complete discovery & monitoring design document specifying push-primary/poll-fallback discovery via AccountMessenger proto extension, three-source per-child information aggregation from reg/ CRDT + child deltas + local JSON, and all five main-wallet actions (Fund, Recover, Inspect, Revoke, Detach) mapped to concrete Phase 2/3 consensus mechanics with file:line anchor points — all without creating any new CRDT namespace.
- Complete reward policy & lifecycle design document specifying dual-source per-child reward policy resolution (DevConfig_st vs reg/ CRDT RegistrationMetadata), hold-time pinning via existing EscrowTransaction immutability, child-only authenticated policy updates, four-state lifecycle model with all valid transitions, detach/revoke/replace-main change-flows with supersedes-sequence + nonce-chain conflict resolution, and main-replacement policy fork decision — all mapped to concrete SuperGenius anchor points with file:line references.

---
