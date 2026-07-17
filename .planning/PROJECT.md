# GNUS Child Wallet

## What This Is

Child wallets (subwallets) for the GNUS SuperGenius node. Games integrating the GNUS SDK operate independent child wallets that can earn GNUS, hold and transfer assets, and optionally register a main wallet — without ever exposing the main wallet's private key. v1.0 shipped implementation-ready design documents (`docs/`) grounded in SuperGenius anchor points; v2.0 shipped the first implemented slice — child-signed registration (`RegistrationTx` proto + `RegistrationTransaction` class), consensus-visible `reg/` CRDT persistence behind a four-gate `FilterRegistration`, pubsub CID broadcast, main-node discovery (`GetRegistrationsForMain`), all proven by a passing multi-node integration test.

## Core Value

The design documents must map every child-wallet behavior — registration, discovery, funding, recovery, and consensus authority — onto concrete SuperGenius anchor points (GeniusAccount, TransactionManager, CRDT/GlobalDB, PubSubBroadcasterExt, consensus validation) so a future implementation can proceed directly from the docs without re-deriving how the existing system works.

## Requirements

### Validated

<!-- Inferred from existing SuperGenius code — the infrastructure the design builds on. -->

- ✓ Accounts are secp256k1 (Ethereum) keypairs with independent signing (`GeniusAccount.hpp`) — existing
- ✓ UTXO-based token model with per-UTXO `owner_address` (`GeniusUTXO.hpp`, `UTXOStructs.hpp`) — existing
- ✓ Transaction types extend `GeniusTransaction`/`DAGStruct` with nonce + signature (`SGTransaction.proto`) — existing
- ✓ CRDT state stored in RocksDB, replicated as IPLD Merkle DAG deltas over pubsub (`crdt_datastore`, `globaldb`) — existing
- ✓ Topic-based subscription via `PubSubBroadcasterExt` (`AddListenTopic`/`AddBroadcastTopic`) over libp2p GossipSub — existing
- ✓ CRDT element filters gate incoming transactions by key pattern (`TransactionManager::FilterTransaction`) — existing
- ✓ Cryptographic-only transaction authorization via `CheckSignature`/`CheckTransactionAuthorization` — existing
- ✓ Escrow-based processing reward split (`peers_cut` + `dev_addr`) via HoldEscrow/PayEscrow — existing
- ✓ Design doc: child-wallet identity & keypair model (independent keypair, nonce tracking, address derivation) mapped to `GeniusAccount`/`GeniusNode` — validated in Phase 1 (`docs/child-wallet-identity-model.md`, IDENT-01..04)
- ✓ Design doc: child-signed registration protocol (child-signed-only registration record per D-04/D-05, sequence numbering, additive proto schema) with proto additions to `SGTransaction.proto`/`Consensus.proto` — validated in Phase 1 (`docs/registration-protocol.md`, REG-01..05)
- ✓ Design doc: main-wallet discovery & monitoring (push-primary/poll-fallback via `AccountMessenger`, per-child information aggregation, main-wallet action mappings) — validated in Phase 3 (`docs/03-01-discovery-monitoring.md`, DISC-01..03)
- ✓ Design doc: processing-reward policy for child wallets (dual-source resolution, hold-time pinning via existing escrow immutability, child-authenticated policy updates) — validated in Phase 3 (`docs/03-02-reward-policy-lifecycle.md`, RWD-01..03)
- ✓ Design doc: lifecycle & registration-change flows (4-state machine, child-initiated detach, first-class `RevokeTx`, child-only replace-main, supersedes-sequence conflict resolution) — validated in Phase 3 (`docs/03-02-reward-policy-lifecycle.md`, LIFE-01..04)
- ✓ Design doc: CRDT registry namespace/key layout, `FilterRegistration` element filter, pubsub broadcast/subscription, certified-status two-tier model, ordering resolution — validated in Phase 2 (`docs/02-crdt-registry-pubsub.md`, SYNC-01..05)
- ✓ Design doc: parent-child consensus authority (`CheckParentChildAuthority` gate, 6 authority rules, child-cannot-spend-main invariant) mapped to `ValidateTransactionForConsensus`/`GeniusInputValidator` — validated in Phase 2 (`docs/02-consensus-parent-child-authority.md`, CONS-01..06)
- ✓ Child-wallet registration implemented in SuperGenius per `docs/registration-protocol.md` (RegistrationTx proto, C++ transaction class, child-signed-only protocol, sequence numbering) — v2.0 (Phase 4, RIMPL-01..03)
- ✓ Registration persisted in consensus-visible `reg/` CRDT namespace with validating element filter (`FilterRegistration`, gates a-d), broadcast on the main wallet's pubsub channel, discoverable via `GetRegistrationsForMain` — v2.0 (Phase 5, RIMPL-04..07)
- ✓ Multi-node integration test: genesis node + main node A + child node B; registration propagates via CRDT/pubsub, main discovers child, invalid registrations rejected — v2.0 (Phase 5, TEST-01..04; `child_registration_test` 3/3 pass, Phase 4 regression suite 18/18 pass)

### Active

<!-- Next milestone scope — to be defined via /gsd-new-milestone. -->

- [ ] Consensus authority gate (`CheckParentChildAuthority`, CONS-01..06) — designed in v1.0, deferred from v2.0 (CAUTH-01/02)
- [ ] Discovery push/poll via `AccountMessenger` proto extension (`docs/03-01-discovery-monitoring.md`, LATER-01)
- [ ] Reward policy resolution and lifecycle/change flows (`docs/03-02-reward-policy-lifecycle.md`, LATER-02)
- [ ] Platform "Connect GNUS Wallet" UI flows and GeniusWallet app changes (LATER-03)

### Out of Scope

<!-- Explicit boundaries. -->

- Consensus authority rules (CONS-01..06 `CheckParentChildAuthority` gate) — designed in v1.0, implementation deferred to a later milestone; v2.0 delivers registration only
- Discovery UI, reward-policy, and lifecycle/change-flow implementation — later milestones per `docs/03-*.md`
- Platform "Connect GNUS Wallet" UI flows (Android/iOS/desktop) — referenced as integration context, not built here
- GeniusWallet Flutter app changes — main-wallet UI display is described conceptually, not built
- Cross-application shared child wallets (one key across multiple apps) — noted as an anti-pattern; safe default is one child wallet per application
- Changes to the existing token economics or reward math — reuse existing escrow split mechanics
- ipfs-bitswap thread-safety work — separate, completed project (archived under `.planning-archive/bitswap/`)

## Current State

**v2.0 Registration Implementation shipped 2026-07-17.**

- SuperGenius (`dev_childwallet` branch) carries the full child-registration vertical slice: `RegistrationTx`/`RegistrationMetadata` proto messages, `RegistrationTransaction` class, `RegisterChild` two-layer API (TM + GeniusNode) with sequence auto-derive, `reg/{child_addr}` CRDT persistence behind four-gate `FilterRegistration`, pubsub CID notification with `AddListenTopic` auto-follow, and `GetRegistrationsForMain` discovery scan
- ~2,235 LOC C++ added across 17 files (src + test); all proto changes additive with zero regressions to existing transaction types
- Test coverage: `registration_transaction_test` (18 unit/E2E cases) and `child_registration_test` (3-node integration: register, discover, reject-invalid)
- Known deferred: consensus authority gate NOT installed — registration validity is filter-enforced CRDT state only, not consensus-certified

## Next Milestone Goals

To be defined via `/gsd-new-milestone`. Leading candidates from the deferred backlog:

- **Consensus authority** (CAUTH-01/02): `CheckParentChildAuthority` gate in `ValidateTransactionForConsensus` enforcing CONS-01..06; certified-status two-tier model via `OnConsensusCertificate`
- **Discovery push/poll** (LATER-01): `AccountMessenger` proto extension per `docs/03-01-discovery-monitoring.md`
- **Reward policy & lifecycle** (LATER-02): dual-source policy resolution and detach/revoke/replace-main flows per `docs/03-02-reward-policy-lifecycle.md`

<details>
<summary>v2.0 Milestone Goal (shipped 2026-07-17)</summary>

**Goal:** Implement the first phase of the child-wallet design — child-signed registration — in the SuperGenius node, proven by a multi-node integration test.

**Target features:**
- Additive `RegistrationTx` proto schema and `RegistrationTransaction` C++ class per `docs/registration-protocol.md`
- Child-side registration API (create, sign child-only, submit) with monotonic per-child sequence numbering
- `reg/` CRDT namespace persistence with `FilterRegistration` validation gate and pubsub broadcast on the main wallet's channel
- Main-node read path: discover a child registration from consensus-visible CRDT state
- Integration test: genesis node + two nodes; node B registers as child of node A; registration propagates and validates (plus negative tests)

</details>

## Context

- **Brownfield:** Built on the existing SuperGenius node (`SuperGenius/src/`). A prior codebase map exists at `.planning/codebase/`.
- **Source proposal:** `GNUS_Subwallet_Architecture_Proposal.md` (root) defines the intended child-wallet architecture, consensus rules, security model, and lifecycle.
- **Key anchor points from code audit:**
  - Account/keys: `SuperGenius/src/account/GeniusAccount.hpp`, `GeniusNode.hpp`
  - UTXO model: `SuperGenius/src/account/GeniusUTXO.hpp`, `UTXOStructs.hpp`
  - Transactions/protos: `SuperGenius/src/account/GeniusTransaction.hpp`, `proto/SGTransaction.proto`, `proto/SGAccountComm.proto`
  - CRDT: `SuperGenius/src/crdt/crdt_datastore.hpp`, `globaldb/globaldb.hpp`, `globaldb/pubsub_broadcaster_ext.hpp`
  - Consensus/validation: `SuperGenius/src/account/TransactionManager.cpp` (`CheckTransactionAuthorization`, `FilterTransaction`, `ValidateTransactionForConsensus`), `GeniusInputValidator.cpp`
  - Rewards/escrow: `SuperGenius/src/account/TransactionManager.cpp` (`HoldEscrow`, `PayEscrow`), `EscrowTransaction.hpp`
- **Critical gap identified:** SuperGenius currently has **no hierarchical/role-based account authority** — authorization is purely cryptographic signature verification. The design must add a parent-child authority layer to the consensus validation path.

## Constraints

- **Tech stack**: C++17/C++20, CMake, Boost.Asio, libp2p, Protocol Buffers — must match existing SuperGenius conventions
- **Coding standard**: Corelinux-derived C++ style per `Coding Standards.md` — Ullman braces, PascalCase types, `m_`/trailing-underscore member prefix; PascalCase headers
- **Compatibility**: Proposed proto/API changes must not break existing SuperGenius, GeniusSDK, or GeniusWallet builds on any supported platform
- **Security**: Main-wallet private key must never enter the game/child process; compromise of a child wallet must be bounded to that child's assets
- **Consensus**: Parent-child authority must be enforced by consensus, not only by wallet UI or local metadata
- **Serialization**: All wire formats use Protocol Buffers; new records extend existing `.proto` files with backward compatibility

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Deliverable is design documents, not implementation | User intent: produce docs grounded in current code for future implementation | ✓ Good — 6 design docs shipped in v1.0 |
| Child wallet is a fully independent keypair (not derived from main) | Matches proposal; bounds compromise scope; child usable standalone | ✓ Adopted (Phase 1) |
| Registration recorded in consensus-visible CRDT state | Enables main-wallet discovery/monitoring and consensus-enforced authority | ✓ Adopted (Phase 2) — reg/ namespace + certified-status two-tier model |
| Registration is child-signed-only (dual-signature REVERSED by D-04/D-05) | Main private key never enters child process; unsolicited claims bounded to discovery spam, grant zero authority | ✓ Adopted (Phase 1) |
| Main wallet subscribes to child pubsub channels for CRDT balance sync | User-specified sync model; reuses existing PubSubBroadcasterExt/GlobalDB | ✓ Adopted (Phase 3) — push-primary/poll-fallback via `AccountMessenger` |
| Reuse escrow reward-split mechanics for child processing rewards | Avoids new token economics; per-child `dev_addr`/`peers_cut` config | ✓ Adopted (Phase 3) — hold-time pinning via existing escrow immutability |
| v2.0 excludes consensus authority gate (CONS-01..06) | Registration must land first; authority gate is a separable slice | ✓ Good — v2.0 shipped registration-only; gate deferred to next milestone |
| `reg/` CRDT path diversion via type-check in `SendTransactionItem` | RegistrationTx must never land in `tx/` namespace; minimal-invasive if-check beats virtual override | ✓ Good (Phase 4) |
| `FilterRegistration` private with friend accessor test classes | Mirrors `FilterTransaction`/`FilterProof` convention; keeps filter out of public API | ✓ Good (Phases 4-5) — `RegistrationE2ETestAccess`, `RegTestAccess`, `ChildRegTestAccess` |
| Gate (d) sequence monotonicity reads stored record via direct CRDT Get (D-46) | No in-memory cache to invalidate; CRDT is the source of truth | ✓ Good (Phase 5) |
| RegisterChild 2-arg auto-derive overload (D-47) | Matches existing codebase overloading convention vs std::optional | ✓ Good (Phase 5) |
| CID-only pubsub payload (D-18) | Notification carries RegistrationTx CID, not full protobuf; forces CRDT resolution for content | ✓ Good (Phase 5) — `RegElementCallback` + `AddListenTopic` follow |
| Proto-level DAG signature tampering in negative tests | Byte-offset tampering was flaky/non-deterministic | ✓ Good (Phase 5 gap closure) — deterministic rejection tests |

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
*Last updated: 2026-07-17 after v2.0 Registration Implementation milestone — child-signed registration, reg/ CRDT persistence, pubsub discovery, and multi-node integration test shipped; next milestone to be defined via /gsd-new-milestone*
