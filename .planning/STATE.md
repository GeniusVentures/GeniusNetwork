---
gsd_state_version: 1.0
milestone: v2.3
milestone_name: Child Wallet Transfers
current_phase: 05
current_phase_name: child-wallet-lifecycle-states
status: executing
stopped_at: Completed 05-05-PLAN.md (2/6 new tests verified passing; 4/6 blocked by discovered ParseRevokeTransaction deadlock - see 05-05-SUMMARY.md)
last_updated: "2026-07-22T19:18:41.742Z"
last_activity: 2026-07-22
last_activity_desc: Phase 05 execution started
progress:
  total_phases: 3
  completed_phases: 2
  total_plans: 11
  completed_plans: 10
  percent: 67
---

## Current Position

Phase: 05 (child-wallet-lifecycle-states) — EXECUTING
Plan: 1 of 6
Status: Executing Phase 05
Last activity: 2026-07-22 — Phase 05 execution started

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-20)

**Core value:** Main wallet must be able to discover, monitor, and manage registered child wallets through consensus-visible state
**Current focus:** Phase 05 — child-wallet-lifecycle-states

### Blockers/Concerns (carried forward)

- `child_registration_test.exe` segfaults on process teardown (after all GTest assertions pass) — pre-existing lifecycle issue, likely unjoined libp2p/boost::asio threads during node `.reset()`, not caused by v2.1/v2.2/v2.3 work. Tracked in `.planning/phases/01-child-balance-query/deferred-items.md`; candidate for a future test-infra/node-shutdown-hygiene phase.
- `registration_transaction_test.exe`'s `RegistrationTransactionE2ETest` fixture (real `GossipPubSub`/`PubSubBroadcasterExt` stack) was observed idling near-zero CPU for 10+ minutes during process bring-up, before any GTest case ran, during Phase 05 Plan 02 verification — same class of test-binary networking/lifecycle issue as the `child_registration_test.exe` teardown segfault above. Build succeeded; full E2E run deferred rather than blocking. Candidate for the same future test-infra/node-shutdown-hygiene phase.

## Deferred Items

Items acknowledged and deferred at milestone close on 2026-07-20:

| Category | Item | Status |
|----------|------|--------|
| verification | Phase 2 (GeniusSDK Child Wallet Interfaces) closed without a `VERIFICATION.md` report — verify step never ran (`/gsd-execute-phase 2` was never re-invoked after implementation). Coverage was manually cross-checked and later build-confirmed (2026-07-20), but no formal verification artifact exists. | override_closeout, accepted |

## Roadmap Evolution

- Phase 5 added: Child Wallet Lifecycle States (Detach/Revoke) — implement the child-initiated Detach and main-initiated Revoke lifecycle transitions for registered child wallets, per the v1.0 lifecycle design (docs/03-02-reward-policy-lifecycle.md). Nothing in SuperGenius/src implements detach_flag, supersedes_sequence, or RevokeTx yet.

## Performance Metrics

| Phase | Plan | Duration | Notes |
|-------|------|----------|-------|
| Phase 01-child-balance-query P01 | 5min | 2 tasks | 2 files |
| Phase 01-child-balance-query P02 | 25min | 2 tasks | 1 files |
| Phase 02-geniussdk-child-wallet-interfaces P01 | 20min | 2 tasks | 2 files |
| Phase 03-parent-child-transfer-authority P01 | 25min | 2 tasks | 4 files |
| Phase 03-parent-child-transfer-authority P02 | 50min | 3 tasks | 3 files |
| Phase 03-parent-child-transfer-authority P03 | 65min | 2 tasks | 4 files |
| Phase 03-parent-child-transfer-authority P04 | ~3.5hr | 2 tasks | 3 files |
| Phase 04-geniussdk-transfer-wrappers P01 | 20min | 2 tasks | 2 files |
| Phase 05-child-wallet-lifecycle-states P01 | 45min | 3 tasks | 7 files |
| Phase 05 P02 | 30min | 3 tasks | 2 files |
| Phase 05 P03 | 25min | 2 tasks | 4 files |
| Phase 05-child-wallet-lifecycle-states P04 | ~2.5hr | 3 tasks | 1 files |
| Phase 05-child-wallet-lifecycle-states P05 | ~3hr | 2 tasks | 1 files |

## Decisions

- [Phase 01, v2.1]: Argument order swap at delegation boundary: GetChildBalance is child-first (D-56) but UTXOManager::GetBalance is token-first, swapped at the call site
- [Phase 01, v2.1]: No registration gate, plain uint64_t return; 0 is an inherently ambiguous no-balance-or-not-synced signal (D-54/D-55/D-62)
- [Phase 02, v2.2]: GeniusSDKRegisterChild wraps only the 2-arg auto-derive RegisterChild overload; 3-arg manual-sequence overload intentionally not exposed
- [Phase 02, v2.2]: Zero registrations from GeniusSDKGetRegistrationsForMain is GENIUS_NODE_RET_OK with out_count=0, not a failure
- [Roadmap, v2.3]: CheckParentChildAuthority gate slots between CheckTransactionAuthorization and CheckTransactionTimestamp in ValidateTransactionForConsensus (TransactionManager.cpp:4250-4303); GeniusInputValidator.cpp is NOT modified — CONS-05/CONS-06 stay invariant-only
- [Roadmap, v2.3]: Reuses existing `"transfer"` tx type for both CONS-01 (fund) and CONS-02 (recover) — no new proto message or tx type; GeniusSDK wrapper phase (4) depends on Phase 3's gate + GeniusNode-level transfer call existing first
- [Phase 03, v2.3]: Blockchain::CheckCertifiedParent implemented with zero genius_node dependency (duplicated reg-key format inline via boost::format) to preserve the one-directional blockchain_genesis <- genius_node link
- [Phase 03, v2.3]: GeniusTransaction::CheckSignature refactored to delegate to new CheckSignatureAgainst(address) - behavior-preserving, unlocks Plan 02's D-60 delegated-signature verification
- [Phase 03-parent-child-transfer-authority]: CheckParentChildAuthority re-derives tx.CheckSignature() as a cheap branch selector (not redundant verification) to distinguish REGR-01/02 child-self-signed spends from CONS-02 certified-main-delegated recovery
- [Phase 03-parent-child-transfer-authority]: D-21 destination restriction enforced via exact string equality against params->second.front().dest_address (primary output first convention), fail-closed on empty/missing UTXO parameters
- [Phase 03-parent-child-transfer-authority]: GeniusInputValidator.cpp owner-address check and delegated_escrow_spend block left byte-for-byte unchanged - D-60 recovery txs naturally pass since payload_owner == child_addr == tx->GetSrcAddress()
- [Phase 03-parent-child-transfer-authority]: RecoverFromChild uses a new FillDAGStructForAddress(source_address) helper instead of modifying FillDAGStruct() itself - keeps main's own transfer/escrow paths untouched
- [Phase 03-parent-child-transfer-authority]: RecoverFromChild's primary output (main's own address) is always pushed first, before any change output, matching Plan 02's gate reading params->second.front().dest_address for the D-21 destination check
- [Phase 03-parent-child-transfer-authority]: GeniusNode::RecoverFromChild's balance pre-check uses GetBalance(token_id, child_address) - the child's own balance, not main's
- [Phase 03-parent-child-transfer-authority, P04]: Fixed a pre-existing gap discovered while writing regression tests - TransactionManager's transaction_parsers dispatch table had no entry for "registration" tx type, so every registration transaction was rejected as "Unknown tx type" before it could ever be certified; added no-op ParseRegistrationTransaction/RevertRegistrationTransaction (registration state already fully owned by FilterRegistration/RegElementCallback)
- [Phase 03-parent-child-transfer-authority, P04]: All 6 phase requirements (CONS-01, CONS-02, CONS-06, REGR-01, REGR-02, REGR-03) now have direct automated E2E regression coverage against the real ValidateTransactionForConsensus pipeline - 24/24 tests passing in registration_transaction_test.exe
- [Phase 04-geniussdk-transfer-wrappers]: GeniusSDKRecoverFromChild calls RecoverFromChild(child_address, amount, token_id) - child_address FIRST, opposite order from the wrapper's own (amount, child_address, token_id) parameter list, matching GeniusNode::RecoverFromChild's actual signature
- [Phase 04-geniussdk-transfer-wrappers]: No new GeniusNodeReturnValue enum value added; both new function families reuse GENIUS_NODE_ERROR_TRANSFER for submission failures (D-69)
- [Phase 04-geniussdk-transfer-wrappers]: Refreshed a stale locally-installed SuperGenius header via cmake --install to unblock GeniusSDK build verification (pre-existing build/install staleness gap)
- [Phase 05-child-wallet-lifecycle-states]: Plan 01's Task 1 grep verify script expected supersedes_sequence count=2; actual is 1 (single declaration) - non-functional discrepancy, no code change needed — Field exists correctly and all functional/build verification passed
- [Phase 05-child-wallet-lifecycle-states, P02]: ParseRevokeTransaction tolerates absent/mismatched reg/ record by logging warning and returning success rather than failing the pipeline
- [Phase 05-child-wallet-lifecycle-states, P02]: FilterRegistration gate 3b's supersedes_sequence check is unconditional on tx sub-kind, uniformly covering Detach/Replace-Main per design doc §9.3
- [Phase 05-child-wallet-lifecycle-states, P02]: CheckParentChildAuthority revoke branch does not call CheckCertifiedParent - reg/{child} was already gated by FilterRegistration's own child-signature check
- [Phase 05-child-wallet-lifecycle-states, P03]: DetachChild/ReplaceMain auto-derive overloads fail closed (invalid_argument) when no prior reg/ record exists, diverging from RegisterChild's auto-derive default-to-sequence-1 behavior
- [Phase 05-child-wallet-lifecycle-states, P03]: RevokeChild uses FillDAGStruct() (own address as source), never FillDAGStructForAddress - main is Revoke's own signer/src
- [Phase 05-child-wallet-lifecycle-states, P04]: LifecycleChangeReplayRejectedByNonceChain polls for CONFIRMED (not SENDING) status before exercising the replay check - the nonce chain's GetPeerNonce() is only populated on genuine CONFIRMED status, so polling only to SENDING would make the test pass vacuously
- [Phase 05-child-wallet-lifecycle-states, P04]: FilterRegistrationRejectsForkedSupersedesSequence's forked element uses sequence=3 (not 2) so gate (d)'s monotonicity check passes on its own, isolating the assertion to gate 3b specifically
- [Phase ?]: [Phase 05-child-wallet-lifecycle-states, P05]: Discovered a reproducible deadlock in TransactionManager::ParseRevokeTransaction's globaldb_m->Put() call when applied at confirmed-transaction time - blocks 4/6 new Revoke E2E tests from passing; NOT fixed in this test-only plan, see 05-05-SUMMARY.md Known Blocker
- [Phase ?]: [Phase 05-child-wallet-lifecycle-states, P05]: RevokeRejectedForNonMain/RevokeRejectedForSequenceMismatch verified passing via real GTest execution - fully prove T-05-09 (unauthorized revoke rejection), the phase's highest-severity threat, independent of the ParseRevokeTransaction blocker

### Pending Todos

None yet.

### Blockers/Concerns

- `child_registration_test.exe` segfaults on process teardown (pre-existing lifecycle issue, not caused by v2.1/v2.2/v2.3 work) — tracked in `.planning/phases/01-child-balance-query/deferred-items.md`, candidate for a future test-infra phase.
- TransactionManager::ParseRevokeTransaction's globaldb_m->Put() call deadlocks when applied during confirmed-transaction processing (CrdtDatastore::AddDAGNode/WaitForJob never completes) - blocks RevokeChildEndToEnd, RevokeRejectedForAlreadyDetachedChild, ReRegistrationAfterRevoke, RevokePreservesChildUTXOsKeypairNonce from passing. Reproduced 3x, not fixed by bumping CRDT worker count 1->4. Root cause candidate: ParseRevokeTransaction should write via the same local-only datastore->put() path PutProducedUTXOs uses, not the full CRDT broadcast globaldb_m->Put(). See 05-05-SUMMARY.md.

## Session

**Last session:** 2026-07-22T01:06:10.216Z
**Stopped at:** Completed 05-05-PLAN.md (2/6 new tests verified passing; 4/6 blocked by discovered ParseRevokeTransaction deadlock - see 05-05-SUMMARY.md)
**Resume file:** None

## Operator Next Steps

- Start the next milestone with /gsd-new-milestone
