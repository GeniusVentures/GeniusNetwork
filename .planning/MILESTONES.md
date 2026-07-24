# Milestones

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
