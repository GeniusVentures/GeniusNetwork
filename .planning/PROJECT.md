# GNUS Child Wallet

## What This Is

Child wallets (subwallets) for the GNUS SuperGenius node. Games integrating the GNUS SDK operate independent child wallets that can earn GNUS, hold and transfer assets, and optionally register a main wallet — without ever exposing the main wallet's private key.

## Core Value

The main wallet must be able to discover, monitor, and manage registered child wallets through consensus-visible state — every child-wallet behavior maps onto concrete SuperGenius anchor points (GeniusAccount, TransactionManager, CRDT/GlobalDB, PubSubBroadcasterExt, consensus validation).

## Current State

**Shipped:** v2.1 Main Wallet Child Balance Query (2026-07-17) — main wallet can now read a registered child wallet's token balance from locally-synced CRDT UTXO data via `GeniusNode::GetChildBalance`, proven end-to-end by a multi-node integration test (child mints → CRDT sync → main queries).

**Next milestone:** Not yet defined — run `/gsd-new-milestone`. Candidates from the deferred backlog below: gRPC/SDK exposure of the balance query (API-01/API-02), multi-token balance (TOK-01), or the full monitoring dashboard (MON-01/MON-02).

## Requirements

### Validated

- ✓ Child-wallet identity model (emergent identity, independent keypair) — v2.0
- ✓ RegistrationTransaction — proto schema, C++ class, CRDT filter with 4 gates — v2.0
- ✓ Registration sequence numbering and monotonicity enforcement — v2.0
- ✓ PubSub broadcast and CRDT sync (reg/ namespace, D-49 RegElementCallback) — v2.0
- ✓ GetRegistrationsForMain — scans reg/ CRDT and returns discovered children — v2.0
- ✓ Main wallet queries child token balance from synced CRDT UTXOs (`GeniusNode::GetChildBalance`) — v2.1 Phase 1
- ✓ Integration test validates balance query after registration + funding (`MainQueriesChildBalance`) — v2.1 Phase 1

### Active

None — awaiting next milestone's requirements (`/gsd-new-milestone`).

### Deferred (candidates for next milestone)

- MON-01/MON-02: Full monitoring dashboard — per-child balance, all assets/tokens, activity history, escrow status, lifecycle monitoring
- API-01/API-02: gRPC endpoint + GeniusSDK wrapper exposing child balance query to external callers
- TOK-01: Multi-token balance query (GNUS, child tokens, NFTs) — v2.1 covered child token only

### Out of Scope

- Balance display formatting (FormatTokens/ConvertToChildToken) — deferred to API phase
- Direct child query (request/response) — balance computed from synced CRDT only, no live query to child node

## Context

- v1.0 shipped implementation-ready design documents covering identity, registration, CRDT/registry, pubsub sync, consensus authority, discovery/monitoring, and reward policy
- v2.0 implemented the first slice: child-signed registration with CRDT persistence, pubsub broadcast, and multi-node integration tests
- The main node already subscribes to child pubsub topics via D-49 RegElementCallback and syncs the child's CRDT deltas — the UTXO data is already present locally
- The existing `GeniusNode::GetBalance(token_id, address)` → `UTXOManager::GetBalance(token_id, address)` pattern sums UTXOs filtered by address and token ID — the same mechanism can target a child address
- v2.1 shipped `GeniusNode::GetChildBalance` (token-filtered + all-tokens overloads) as a thin alias over this pattern, plus a multi-node integration test proving the child-mint → CRDT-sync → main-query round-trip

## Known Issues

- `child_registration_test.exe` segfaults on process teardown (after all GTest assertions pass) — pre-existing lifecycle issue, likely unjoined libp2p/boost::asio threads during node `.reset()`, not caused by v2.1 changes. Reproduces with only the 3 pre-v2.1 test cases. Tracked in `.planning/phases/01-child-balance-query/deferred-items.md`; candidate for a future test-infra/node-shutdown-hygiene phase.

## Constraints

- **Tech stack**: C++17/C++20, CMake, Boost.Asio, libp2p, Protocol Buffers — must match existing SuperGenius conventions
- **Coding standard**: Corelinux-derived C++ style — Ullman braces, PascalCase types, `m_`/trailing-underscore member prefix
- **Compatibility**: Must not break existing SuperGenius, GeniusSDK, or GeniusWallet builds
- **Security**: Main-wallet private key must never enter the child process; child balance is read-only from consensus-visible state
- **Serialization**: No new proto messages needed this milestone — balance is computed in-memory from existing UTXO data

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Emergent child identity (D-01) | Child-ness derived from registration record, not creation-time flag | ✓ Good |
| Child-signed-only registration (D-04/D-05) | Main does not counter-sign; compromise bounded to child | ✓ Good |
| RegistrationTx as first-class transaction (D-06) | Reuses TransactionManager path identically to TransferTx | ✓ Good |
| CRDT reg/ namespace (D-11/D-12) | Registration records in `/bc-{net}/reg/{child_addr}`, not `tx/` | ✓ Good |
| D-49 main follows child's pubsub | RegElementCallback subscribes on reg/ delta arrival | ✓ Good |
| Balance from synced CRDT (this milestone) | No direct query; use UTXOManager on locally-synced data | ✓ Good |

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
*Last updated: 2026-07-17 after v2.1 milestone completion*
