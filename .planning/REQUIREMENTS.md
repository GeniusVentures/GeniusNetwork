# Requirements: GNUS Child Wallet — v2.0 Registration Implementation

**Defined:** 2026-07-15
**Core Value:** A game's child wallet can register a main wallet on a live SuperGenius network — child-signed-only, consensus-visible, main key never leaving the main process — proven by a multi-node integration test.

> **Milestone type:** Implementation. Each requirement is satisfied when working C++ code lands in SuperGenius, builds on supported platforms, and is covered by the milestone's tests. Implementation follows the shipped v1.0 design docs (`docs/registration-protocol.md`, `docs/02-crdt-registry-pubsub.md`, `docs/child-wallet-identity-model.md`).

## v1 Requirements

Requirements for this milestone. Each maps to a roadmap phase.

### Registration Implementation

- [x] **RIMPL-01**: `RegistrationTx` and `RegistrationMetadata` proto messages are added additively to `SGTransaction.proto`, and a `registration = 8` oneof arm is added to `EmbeddedTransaction` in `Consensus.proto`, per `docs/registration-protocol.md` §2–3, without modifying any existing message or breaking existing SuperGenius/GeniusSDK builds
- [x] **RIMPL-02**: `RegistrationTransaction` C++ subclass of `GeniusTransaction` exists (`New()` factory, `SerializeToEmbeddedTransaction`, `SerializeByteVector`, static `DeSerializeByteVector`), registered via `RegisterDeserializer("registration", ...)` with `case EmbeddedTransaction::kRegistration` dispatch in `TransactionManager::DeSerializeEmbeddedTransaction`, per `docs/registration-protocol.md` §4
- [x] **RIMPL-03**: A child node can create, child-sign, and submit a registration naming a main wallet address through the existing `TransactionManager` path, consuming a `DAGStruct.nonce` and carrying a monotonic per-child `sequence`, per `docs/registration-protocol.md` §5–6
- [ ] **RIMPL-04**: Accepted registrations are persisted in the consensus-visible `reg/` CRDT namespace with a validating `FilterRegistration` element filter alongside the existing `tx/` filters in `TransactionManager`, per `docs/02-crdt-registry-pubsub.md`
- [ ] **RIMPL-05**: A registration is broadcast on the main wallet's pubsub channel via `PubSubBroadcasterExt` so the main node's CRDT syncs the registration record without the child's private key
- [ ] **RIMPL-06**: A main node can enumerate and read the child registrations naming it from CRDT state (discovery read path returning child address, main address, sequence, metadata)
- [ ] **RIMPL-07**: Invalid registrations — bad child signature, malformed `main_address`, or non-monotonic `sequence` — are rejected by the validating filter and never persisted to `reg/`

### Multi-Node Integration Test

- [ ] **TEST-01**: Test harness creates a genesis-authorized node plus two peer nodes on an isolated network (following the `multi_account_sync.cpp` `CreateNode` pattern), all reaching ready state
- [ ] **TEST-02**: Test registers node B as a child of node A via the registration API and asserts the `RegistrationTx` is accepted and processed
- [ ] **TEST-03**: Test asserts the registration propagates via CRDT/pubsub and node A discovers node B as its registered child (correct child address, main address, sequence)
- [ ] **TEST-04**: Negative tests assert an invalid registration (tampered signature, replayed/non-monotonic sequence) is rejected and does not appear in node A's discovery view

## v2 Requirements

Deferred to future milestones. Tracked but not in the current roadmap.

### Consensus Authority

- **CAUTH-01**: `CheckParentChildAuthority` gate in `ValidateTransactionForConsensus` enforcing CONS-01..06 rules (`docs/02-consensus-parent-child-authority.md`)
- **CAUTH-02**: Certified-status two-tier model (`OnConsensusCertificate` marking registrations CONFIRMED) — v2.0 uses filter-validated CRDT state only

### Later Slices

- **LATER-01**: Discovery push/poll via `AccountMessenger` proto extension (`docs/03-01-discovery-monitoring.md`)
- **LATER-02**: Reward policy resolution and lifecycle/change flows (`docs/03-02-reward-policy-lifecycle.md`)
- **LATER-03**: Platform "Connect GNUS Wallet" UI flows and GeniusWallet app changes

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Consensus authority rules (CONS-01..06 gate) | Designed in v1.0; separate milestone — registration must land first |
| Main→child funding, recovery, revoke/detach flows | Depend on the authority gate; later milestones |
| Connect-flow platform UI (main pubkey delivery) | Test supplies the main address directly; UI deferred (PLAT-01/02) |
| Main counter-signature on registration | REVERSED by D-04/D-05 — registration is child-signed-only |
| Changes to existing token economics / reward math | Reuse existing escrow mechanics unchanged |
| GeniusWallet Flutter app changes | Node-level implementation only in v2.0 |

## Traceability

Which phases cover which requirements. Populated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| RIMPL-01 | Phase 4 | Complete |
| RIMPL-02 | Phase 4 | Complete |
| RIMPL-03 | Phase 4 | Complete |
| RIMPL-04 | Phase 5 | Pending |
| RIMPL-05 | Phase 5 | Pending |
| RIMPL-06 | Phase 5 | Pending |
| RIMPL-07 | Phase 5 | Pending |
| TEST-01 | Phase 5 | Pending |
| TEST-02 | Phase 5 | Pending |
| TEST-03 | Phase 5 | Pending |
| TEST-04 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 11 total
- Mapped to phases: 11 ✓
- Unmapped: 0

---
*Requirements defined: 2026-07-15*
*Last updated: 2026-07-15 — roadmap created, Phase 4/5 assignments populated*
