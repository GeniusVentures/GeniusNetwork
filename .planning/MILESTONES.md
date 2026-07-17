# Milestones

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
