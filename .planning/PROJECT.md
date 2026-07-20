# GNUS Child Wallet

## What This Is

Child wallets (subwallets) for the GNUS SuperGenius node. Games integrating the GNUS SDK operate independent child wallets that can earn GNUS, hold and transfer assets, and optionally register a main wallet — without ever exposing the main wallet's private key.

## Core Value

The main wallet must be able to discover, monitor, and manage registered child wallets through consensus-visible state — every child-wallet behavior maps onto concrete SuperGenius anchor points (GeniusAccount, TransactionManager, CRDT/GlobalDB, PubSubBroadcasterExt, consensus validation).

## Current State

**Shipped:** v2.2 GeniusSDK Child Wallet Interfaces (2026-07-20) — external games/apps can register this node as a child wallet, discover a main wallet's registered children, and query child balances entirely through the public `GeniusSDK.h`/`.cpp` C API, without linking SuperGenius directly. Build-verified end-to-end after fixing a pre-existing evmrelay/Boost::coroutine CMake packaging gap.

## Next Milestone: v2.3 (planning)

**Requested goal:** Implement transferring to and from a child wallet from a main wallet — the transfer/spend path is not yet scoped. `/gsd-new-milestone` will define the concrete requirements (e.g. main→child funding, child→main withdrawal, transfer authorization/limits).

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

### Active

- [ ] Main wallet can transfer (fund) assets to a registered child wallet — v2.3 (candidate, to be scoped)
- [ ] Child wallet can transfer (withdraw/spend) assets back to its registered main wallet — v2.3 (candidate, to be scoped)

### Deferred (candidates for future milestones)

- MON-01/MON-02: Full monitoring dashboard — per-child balance, all assets/tokens, activity history, escrow status, lifecycle monitoring
- API-01: gRPC endpoint exposing child registration/balance to external callers (SDK wrapper covered in v2.2 instead)
- TOK-01: Multi-token balance query (GNUS, child tokens, NFTs) — v2.1/v2.2 covered child token only

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

## Known Issues

- `child_registration_test.exe` segfaults on process teardown (after all GTest assertions pass) — pre-existing lifecycle issue, likely unjoined libp2p/boost::asio threads during node `.reset()`, not caused by v2.1/v2.2 changes. Reproduces with only the 3 pre-v2.1 test cases. Tracked in `.planning/phases/01-child-balance-query/deferred-items.md`; candidate for a future test-infra/node-shutdown-hygiene phase.
- Phase 2 (v2.2) closed without a formal `VERIFICATION.md` — the verify step was never re-run after implementation. Coverage was manually cross-checked against source and later build-confirmed, but no verification artifact exists. Milestone closed via explicit user override; see STATE.md Deferred Items.

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
*Last updated: 2026-07-20 after shipping v2.2 milestone*
