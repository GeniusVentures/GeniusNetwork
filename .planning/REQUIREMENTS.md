# Requirements: GNUS Child Wallet Design

**Defined:** 2026-07-13
**Core Value:** The design documents map every child-wallet behavior — registration, discovery, funding, recovery, and consensus authority — onto concrete SuperGenius anchor points so a future implementation can proceed directly without re-deriving how the existing system works.

> **Milestone type:** Design documentation. Each requirement is satisfied when a design document specifies the behavior, integrates it with named SuperGenius code, and is testable/reviewable against the proposal — not by shipping C++ code.

## v1 Requirements

Requirements for the initial design-document set. Each maps to a roadmap phase.

### Identity

- [x] **IDENT-01**: Design specifies the child-wallet identity model — independent secp256k1 keypair with its own address derivation — mapped to `GeniusAccount`/`EthereumKeyGenerator`
- [x] **IDENT-02**: Design specifies independent nonce/sequence tracking for a child wallet distinct from the main wallet
- [x] **IDENT-03**: Design specifies how a child wallet is created and loaded (standalone, no main required) mapped to `GeniusNode` `AccountSource`
- [x] **IDENT-04**: Design specifies UTXO ownership for child wallets so child-owned assets are distinguishable, mapped to `GeniusUTXO.owner_address`

### Registration

- [x] **REG-01**: Design specifies the registration record schema (child pubkey, main pubkey, both signatures, sequence number, timestamp, optional game/publisher/dev-wallet/split metadata)
- [x] **REG-02**: Design specifies the dual-signature registration protocol requiring both child and main signatures over the canonical record
- [x] **REG-03**: Design specifies additive Protocol Buffer schema changes (new `RegistrationTx`/`RegistrationRecord` messages/oneof arm) in `SGTransaction.proto` with a backward-compatibility matrix
- [x] **REG-04**: Design specifies the out-of-process main-wallet signing flow so the main private key never enters the game/child process
- [x] **REG-05**: Design specifies monotonic per-child sequence numbering and consensus-based replay/reorder protection

### Consensus

- [ ] **CONS-01**: Design specifies the main→child funding rule (main signature + child registered that main) integrated with `ValidateTransactionForConsensus`
- [ ] **CONS-02**: Design specifies main-recover-from-child with destination restricted to the registered main address, via a delegated-spend branch in `GeniusInputValidator`
- [ ] **CONS-03**: Design specifies child→arbitrary-address and child→main transfer rules (child signature + UTXO ownership) reusing existing validation
- [ ] **CONS-04**: Design specifies child→registered-developer-wallet payment rule (child signature + destination check)
- [ ] **CONS-05**: Design specifies the explicit rejection rule that a child key can never authorize spending main-wallet funds, plus its negative-test expectation
- [ ] **CONS-06**: Design specifies where the new hierarchical-authority layer slots into `CheckTransactionAuthorization` without conflating with UTXO ownership checks

### State Sync

- [ ] **SYNC-01**: Design specifies the consensus-visible CRDT namespace/key layout for the registration record in `globaldb`
- [ ] **SYNC-02**: Design specifies a CRDT element filter that validates and persists registration deltas, alongside existing `tx/`/`proof/` filters in `TransactionManager`
- [ ] **SYNC-03**: Design specifies registration broadcast over the main wallet's pubsub channel via `PubSubBroadcasterExt`
- [ ] **SYNC-04**: Design specifies the main wallet subscribing to child pubsub channel(s) and syncing CRDT to read child balances/assets without the child private key
- [ ] **SYNC-05**: Design specifies that discovery/monitoring data is trusted only after signature + consensus validation, never based on pubsub topic membership

### Discovery

- [x] **DISC-01**: Design specifies how a main wallet discovers all child wallets registered to it from consensus-visible CRDT state
- [x] **DISC-02**: Design specifies the per-child information a main wallet displays (balance, assets, game, publisher, developer wallet, cut ratio, registration date, activity, status)
- [x] **DISC-03**: Design specifies main-wallet actions over discovered children (fund, recover, inspect history, view assets, revoke/detach) mapped to consensus rules

### Rewards

- [ ] **RWD-01**: Design specifies per-child processing-reward policy (`dev_addr`, `peers_cut`) resolution for both standalone and registered children, reusing escrow `HoldEscrow`/`PayEscrow`
- [ ] **RWD-02**: Design specifies pinning the reward policy at escrow-hold time so mid-flight policy changes do not affect in-progress payouts
- [ ] **RWD-03**: Design specifies authenticated update rules for the developer wallet and cut ratio

### Lifecycle

- [ ] **LIFE-01**: Design specifies the child-wallet lifecycle state machine (standalone, registration-pending, registered, detached, revoked, closed) and valid transitions
- [ ] **LIFE-02**: Design specifies replace/remove-main flows with a "supersedes sequence N" linkage and deterministic (seq, tie-break) conflict resolution to prevent split-brain
- [ ] **LIFE-03**: Design decides and documents the main-replacement policy fork (require existing-main consent vs allow child-only replacement) with rationale
- [ ] **LIFE-04**: Design specifies that detaching a main wallet leaves the child a valid standalone wallet unless explicitly defined otherwise

## v2 Requirements

Deferred to a future milestone. Tracked but not in the current roadmap.

### Platform

- **PLAT-01**: "Connect GNUS Wallet" platform UI flows (Android/iOS/Windows/macOS/Linux) design
- **PLAT-02**: GeniusWallet Flutter app changes for child-wallet display

### Advanced

- **ADV-01**: Threshold/social-recovery scheme for the main wallet
- **ADV-02**: Aggregated registry topic design for publisher-scale child fan-out

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| C++ implementation of the feature | This milestone produces design docs only; implementation follows separately |
| Cross-application shared child keys | Anti-feature — compromise of any app compromises all shared assets (proposal §Sharing); safe default is one child per app |
| Changes to existing token economics / reward math | Reuse existing escrow split mechanics |
| Main-wallet UI implementation | Described conceptually only; UI build is out of scope |
| ipfs-bitswap thread-safety work | Separate completed project (archived at `.planning-archive/bitswap/`) |
| HD-derived child keys from the main seed | Rejected — couples compromise, violates bounded-compromise goal |

## Traceability

Which phases cover which requirements. Populated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| IDENT-01 | Phase 1 | Complete |
| IDENT-02 | Phase 1 | Complete |
| IDENT-03 | Phase 1 | Complete |
| IDENT-04 | Phase 1 | Complete |
| REG-01 | Phase 1 | Complete |
| REG-02 | Phase 1 | Complete |
| REG-03 | Phase 1 | Complete |
| REG-04 | Phase 1 | Complete |
| REG-05 | Phase 1 | Complete |
| CONS-01 | Phase 2 | Pending |
| CONS-02 | Phase 2 | Pending |
| CONS-03 | Phase 2 | Pending |
| CONS-04 | Phase 2 | Pending |
| CONS-05 | Phase 2 | Pending |
| CONS-06 | Phase 2 | Pending |
| SYNC-01 | Phase 2 | Pending |
| SYNC-02 | Phase 2 | Pending |
| SYNC-03 | Phase 2 | Pending |
| SYNC-04 | Phase 2 | Pending |
| SYNC-05 | Phase 2 | Pending |
| DISC-01 | Phase 3 | Complete |
| DISC-02 | Phase 3 | Complete |
| DISC-03 | Phase 3 | Complete |
| RWD-01 | Phase 3 | Pending |
| RWD-02 | Phase 3 | Pending |
| RWD-03 | Phase 3 | Pending |
| LIFE-01 | Phase 3 | Pending |
| LIFE-02 | Phase 3 | Pending |
| LIFE-03 | Phase 3 | Pending |
| LIFE-04 | Phase 3 | Pending |

**Coverage:**
- v1 requirements: 30 total
- Mapped to phases: 30
- Unmapped: 0 ✓

---
*Requirements defined: 2026-07-13*
*Last updated: 2026-07-13 after initial definition*
