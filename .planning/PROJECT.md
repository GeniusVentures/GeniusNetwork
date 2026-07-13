# GNUS Child Wallet Design

## What This Is

A design-documentation effort that produces implementation-ready design documents for **child wallets** (subwallets) in the GNUS SuperGenius node, grounded in the current SuperGenius codebase. Games integrating the GNUS SDK will operate independent child wallets that can earn GNUS, hold and transfer assets, and optionally register a main wallet — without ever exposing the main wallet's private key. The documents detail how a child-wallet registration broadcasts to the main wallet's pubsub channel, how CRDT backing persists the registration for consensus-visible parent-child authority, and how the main wallet subscribes to child pubsub channels to sync CRDT state and read child balances.

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

### Active

<!-- Design documents to produce. Each is a hypothesis until reviewed and adopted. -->

- [ ] Design doc: child-wallet identity & keypair model (independent keypair, nonce tracking, address derivation) mapped to `GeniusAccount`/`GeniusNode`
- [ ] Design doc: main-wallet registration protocol (dual-signature registration record, nonce/sequence, lifecycle states) with proto schema additions to `SGTransaction.proto`/`SGAccountComm.proto`
- [ ] Design doc: registration broadcast over the main wallet's pubsub channel and CRDT namespace/key layout that persists the registration record
- [ ] Design doc: main-wallet discovery & monitoring — subscribing to child pubsub channels, CRDT sync, and reading child balances/assets without the child private key
- [ ] Design doc: consensus rules for parent-child authority (main→child fund, main-recover-from-child, child→arbitrary, child→developer, reject child-spends-main) mapped to `ValidateTransactionForConsensus`/`ValidateWitnessForConsensus`
- [ ] Design doc: processing-reward policy for child wallets (per-child `dev_addr`/`peers_cut`, standalone vs registered) mapped to escrow HoldEscrow/PayEscrow
- [ ] Design doc: lifecycle & registration-change flows (standalone → pending → registered → detached/revoked/closed; replace/remove main wallet; replay protection)

### Out of Scope

<!-- Explicit boundaries. -->

- Implementation of the child-wallet feature in C++ — this milestone produces design docs only; implementation follows separately
- Platform "Connect GNUS Wallet" UI flows (Android/iOS/desktop) — referenced as integration context, not designed here
- GeniusWallet Flutter app changes — main-wallet UI display is described conceptually, not designed
- Cross-application shared child wallets (one key across multiple apps) — noted as an anti-pattern; safe default is one child wallet per application
- Changes to the existing token economics or reward math — reuse existing escrow split mechanics
- ipfs-bitswap thread-safety work — separate, completed project (archived under `.planning-archive/bitswap/`)

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
| Deliverable is design documents, not implementation | User intent: produce docs grounded in current code for future implementation | — Pending |
| Child wallet is a fully independent keypair (not derived from main) | Matches proposal; bounds compromise scope; child usable standalone | — Pending |
| Registration recorded in consensus-visible CRDT state | Enables main-wallet discovery/monitoring and consensus-enforced authority | — Pending |
| Dual-signature (child + main) required for registration | Prevents unsolicited/fraudulent parent-child associations | — Pending |
| Main wallet subscribes to child pubsub channels for CRDT balance sync | User-specified sync model; reuses existing PubSubBroadcasterExt/GlobalDB | — Pending |
| Reuse escrow reward-split mechanics for child processing rewards | Avoids new token economics; per-child `dev_addr`/`peers_cut` config | — Pending |

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
*Last updated: 2026-07-13 after initialization*
