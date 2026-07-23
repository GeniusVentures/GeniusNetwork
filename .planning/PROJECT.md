# GNUS Child Wallet

## What This Is

Child wallets (subwallets) for the GNUS SuperGenius node. Games integrating the GNUS SDK operate independent child wallets that can earn GNUS, hold and transfer assets, and optionally register a main wallet — without ever exposing the main wallet's private key.

## Core Value

The main wallet must be able to discover, monitor, and manage registered child wallets through consensus-visible state — every child-wallet behavior maps onto concrete SuperGenius anchor points (GeniusAccount, TransactionManager, CRDT/GlobalDB, PubSubBroadcasterExt, consensus validation).

## Current State

**Shipped:** v2.3 Phase 4 GeniusSDK Transfer Wrappers (2026-07-21) — external games/apps can fund a registered child wallet (`GeniusSDKFundChild`/`GeniusSDKFundChildGNUS`) and recover funds from it (`GeniusSDKRecoverFromChild`/`GeniusSDKRecoverFromChildGNUS`) entirely through the public GeniusSDK C API, wrapping Phase 3's `GeniusNode::TransferFunds`/`RecoverFromChild` calls with no new business logic. This completes v2.3 Child Wallet Transfers — all milestone phases are done.

**Previously shipped:** v2.3 Phase 3 Parent-Child Transfer Authority (2026-07-21) — the `CheckParentChildAuthority` consensus gate is live: main can fund a registered child via an ordinary transfer (CONS-01) and recover funds back from it via the new `TransactionManager::RecoverFromChild`/`GeniusNode::RecoverFromChild` (CONS-02, destination-restricted per D-21), while every existing child-signed path (child→arbitrary, child→main, child→dev, child-cannot-spend-main) is confirmed unaffected by 24 passing E2E regression tests.

## Current Milestone: v2.4 Merge origin/develop into dev_childwallet

**Goal:** Bring SuperGenius and GeniusSDK `dev_childwallet` branches current with `origin/develop` — including the `DevConfig_st`→`GeniusNodeConfig` rename — with zero regressions to child-wallet functionality.

**Target features:**
- SuperGenius `dev_childwallet` merged with `origin/develop` (162 commits behind at scoping time; merge commit, not rebase — branch is shared/pushed), conflicts resolved in the 9 confirmed shared files: `src/account/GeniusNode.{hpp,cpp}`, `src/account/TransactionManager.{hpp,cpp}`, `src/blockchain/Blockchain.hpp`, `src/blockchain/impl/Blockchain.cpp`, `src/blockchain/impl/proto/Consensus.proto`, `src/account/CMakeLists.txt`, `test/src/account/CMakeLists.txt`
- GeniusSDK `dev_childwallet` caught up with the 1 remaining `origin/develop` commit (already merged once at `6f05025`)
- All `DevConfig_st` references (~17 files in `src/`/`test/`/`example/`) adapted to `GeniusNodeConfig` as part of conflict resolution — typedef rename only, struct fields unchanged
- Full child-wallet regression suite (registration, balance query, transfer authority, transfer wrappers, lifecycle states/Detach/Revoke) passes post-merge with zero regressions
- SuperGenius, GeniusSDK, and dependent submodule builds stay green

**Explicitly out of scope this milestone:**
- GeniusWallet — currently on `dev_mergeandroidbg`, not a `dev_childwallet` branch; untouched
- thirdparty — already tracks `develop` directly, no separate child-wallet branch to merge

**Deferred candidates carried forward from prior milestones** (see Requirements > Deferred below):
- MON-01/MON-02: Full monitoring dashboard (per-child balance, all assets/tokens, activity history, escrow status, lifecycle monitoring)
- API-01: gRPC endpoint exposing child registration/balance to external callers
- TOK-01: Multi-token balance query (GNUS, child tokens, NFTs)
- POL-01: Transfer amount limits/policy beyond CONS-01/CONS-02
- UI-01: GeniusWallet Flutter UI wiring for child-wallet transfers

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
- ✓ `CheckParentChildAuthority` consensus gate enforces CONS-01 (main→child fund) — v2.3 Phase 3
- ✓ `CheckParentChildAuthority` consensus gate enforces CONS-02 (main-recover-from-child, destination-restricted per D-21) — v2.3 Phase 3
- ✓ Regression coverage confirms CONS-03/04/05 invariants (child→arbitrary, child→main, child→dev, child-cannot-spend-main) hold unchanged with the new gate in place — v2.3 Phase 3 (REGR-01/02/03)
- ✓ GeniusSDK wrapper exposes main→child fund transfer (`GeniusSDKFundChild`/`GeniusSDKFundChildGNUS`) — v2.3 Phase 4, fulfilled SDKT-01
- ✓ GeniusSDK wrapper exposes main-recover-from-child transfer (`GeniusSDKRecoverFromChild`/`GeniusSDKRecoverFromChildGNUS`) — v2.3 Phase 4, fulfilled SDKT-02
- ✓ Both transfer wrappers return existing `GeniusNodeReturnValue_t` codes with no new enum value added — v2.3 Phase 4, fulfilled SDKT-03

### Active

- [ ] MERGE-01: SuperGenius `dev_childwallet` merged with `origin/develop`, conflicts resolved incl. `DevConfig_st`→`GeniusNodeConfig` rename
- [ ] MERGE-02: GeniusSDK `dev_childwallet` merged with the remaining `origin/develop` commit
- [ ] MVER-01: SuperGenius builds cleanly post-merge
- [ ] MVER-02: GeniusSDK builds cleanly against updated SuperGenius static lib
- [ ] MVER-03: Full existing child-wallet test suite passes with zero regressions
- [ ] MVER-04: `origin/develop`'s changes confirmed compatible with child-wallet consensus gates

### Deferred (candidates for future milestones)

- MON-01/MON-02: Full monitoring dashboard — per-child balance, all assets/tokens, activity history, escrow status, lifecycle monitoring
- API-01: gRPC endpoint exposing child registration/balance to external callers (SDK wrapper covered in v2.2 instead)
- TOK-01: Multi-token balance query (GNUS, child tokens, NFTs) — v2.1/v2.2 covered child token only
- POL-01: Transfer amount limits/policy beyond CONS-01/CONS-02 (e.g. per-child caps, rate limiting)
- UI-01: GeniusWallet Flutter UI wiring for child-wallet transfers

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
- v2.3 Phase 3 added `Blockchain::CheckCertifiedParent` (D-63 certified-parent lookup, zero `genius_node` dependency to preserve the one-directional `blockchain_genesis` ← `genius_node` library link) and a narrow D-60 signature-acceptance branch in `CheckTransactionAuthorization`/`ValidateWitness`, so a certified main's signature is accepted on a child-sourced recovery transaction without weakening any other signature check
- While building Phase 3's regression tests, found and fixed a pre-existing gap: `TransactionManager`'s `transaction_parsers` dispatch table had no entry for the `"registration"` tx type, so every registration transaction was rejected as "Unknown tx type" before it could ever reach a certified state — the certified-parent mechanism this milestone depends on could never have worked without this fix

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
| D-60: certified-main signature accepted on child-sourced tx via CRDT registration, not cryptographic delegation (Phase 3) | Verified against current code that main's signature cannot verify against a child's address under a literal-delegation model; CRDT-derived authority was the user's directional call | ✓ Good — narrowly scoped, owner-address check left untouched |
| Registration-dispatch no-op fix (Phase 3) | Discovered mid-implementation that registration txs could never be certified without a `transaction_parsers` entry; fixed with a narrowly-scoped no-op rather than touching `FilterRegistration`/`RegElementCallback` | ✓ Good |

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
*Last updated: 2026-07-23 after starting v2.4 Merge origin/develop into dev_childwallet milestone*
