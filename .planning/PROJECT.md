# GNUS Child Wallet

## What This Is

Child wallets (subwallets) for the GNUS SuperGenius node. Games integrating the GNUS SDK operate independent child wallets that can earn GNUS, hold and transfer assets, and optionally register a main wallet — without ever exposing the main wallet's private key.

## Core Value

The main wallet must be able to discover, monitor, and manage registered child wallets through consensus-visible state — every child-wallet behavior maps onto concrete SuperGenius anchor points (GeniusAccount, TransactionManager, CRDT/GlobalDB, PubSubBroadcasterExt, consensus validation).

## Current State

**Shipped:** v2.4 Merge origin/develop into dev_childwallet (2026-07-24) — SuperGenius's `dev_childwallet` branch is current with `origin/develop` via merge commit `cb4e46da` (162 commits caught up, `DevConfig_st`→`GeniusNodeConfig` rename swept across ~17 files, zero regressions across the full child-wallet suite), pushed to `origin/dev_childwallet`. GeniusSDK's `dev_childwallet` is current with the same `origin/develop` baseline via merge commit `6969fac`, pushed, and confirmed building cleanly against the updated SuperGenius static lib. Phase 7 (GeniusSDK side) was completed directly by the user outside the formal GSD plan/execute workflow — see MILESTONES.md Known Gaps.

**Previously shipped:** v2.3 Phase 4 GeniusSDK Transfer Wrappers (2026-07-21) — external games/apps can fund a registered child wallet (`GeniusSDKFundChild`/`GeniusSDKFundChildGNUS`) and recover funds from it (`GeniusSDKRecoverFromChild`/`GeniusSDKRecoverFromChildGNUS`) entirely through the public GeniusSDK C API, wrapping Phase 3's `GeniusNode::TransferFunds`/`RecoverFromChild` calls with no new business logic.

## Current Milestone

Planning next milestone — run `/gsd-new-milestone` to define v2.5 scope.

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
- ✓ SuperGenius `dev_childwallet` merged with `origin/develop`, conflicts resolved incl. `DevConfig_st`→`GeniusNodeConfig` rename — v2.4, fulfilled MERGE-01
- ✓ GeniusSDK `dev_childwallet` merged with the remaining `origin/develop` commit — v2.4, fulfilled MERGE-02 (completed directly by user, no formal GSD phase artifacts)
- ✓ SuperGenius builds cleanly post-merge — v2.4, fulfilled MVER-01
- ✓ GeniusSDK builds cleanly against updated SuperGenius static lib — v2.4, fulfilled MVER-02 (user attestation only, no captured build log)
- ✓ Full existing child-wallet test suite passes with zero regressions post-merge — v2.4, fulfilled MVER-03
- ✓ `origin/develop`'s changes confirmed compatible with child-wallet consensus gates — v2.4, fulfilled MVER-04

### Active

(None yet — define next milestone's requirements via `/gsd-new-milestone`)

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
- v2.4 merged both SuperGenius and GeniusSDK `dev_childwallet` branches current with `origin/develop` (162 commits caught up on SuperGenius), resolving the `DevConfig_st`→`GeniusNodeConfig` rename across ~17 files with zero child-wallet regressions; an unrelated `thirdparty` submodule drift was root-caused as blocking some real-networked E2E fixtures (DI-06-01), not a regression from the merge itself

## Known Issues

- `child_registration_test.exe` segfaults on process teardown (after all GTest assertions pass) — pre-existing lifecycle issue, likely unjoined libp2p/boost::asio threads during node `.reset()`, not caused by v2.1/v2.2 changes. Reproduces with only the 3 pre-v2.1 test cases. Tracked in `.planning/phases/01-child-balance-query/deferred-items.md`; candidate for a future test-infra/node-shutdown-hygiene phase. Same class of issue also seen on `registration_transaction_test.exe` (exit 139 after GTest PASSED summary).
- Phase 2 (v2.2) closed without a formal `VERIFICATION.md` — the verify step was never re-run after implementation. Coverage was manually cross-checked against source and later build-confirmed, but no verification artifact exists. Milestone closed via explicit user override; see STATE.md Deferred Items.
- Phase 7 (v2.4, GeniusSDK Merge & Build Verification) has no formal GSD phase artifacts — MERGE-02 and MVER-02 were completed directly by the user. Merge commits independently confirmed via git history; MVER-02's build success rests on user attestation only, no build log captured. Milestone closed via explicit user override.
- An unrelated `thirdparty` submodule drift (fast-forwarded same-day during Phase 6 build troubleshooting) causes `registration_transaction_test.exe`/`child_registration_test.exe` to crash deterministically on real-networked E2E fixture `SetUp()` (BOOST_ASSERT in libp2p Kademlia `StorageImpl`), blocking most E2E cases in those binaries. Traced to a `gossip_pubsub.cpp`/`boost::di` config-lifetime change between the recorded and current `ipfs-pubsub` commits — not caused by the origin/develop merge. See `.planning/milestones/v2.4-phases/06-supergenius-merge-regression-verification/deferred-items.md` (DI-06-01).

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
| Merge commit over rebase for `dev_childwallet` (v2.4) | Both SuperGenius and GeniusSDK `dev_childwallet` branches already shared/pushed; rebase would rewrite shared history | ✓ Good |
| `CrdtSet::mutex_` reentrancy root cause over original DAG-broadcast hypothesis (Phase 5, revisited v2.4) | Live-debugger stack trace during Phase 6 regression testing confirmed the fix (`std::recursive_mutex`) held under the merged `origin/develop` code paths too | ✓ Good |
| Phase 7 (v2.4) completed outside formal GSD workflow, milestone closed via override | User completed the GeniusSDK merge/build verification directly; no `07-*` plan/verification artifacts exist, but git history independently confirms both merge commits are pushed | ⚠️ Revisit — same pattern as the v2.2 Phase 2 gap; consider running `/gsd-plan-phase`/`/gsd-execute-phase` retroactively if a future milestone needs a formal Phase 7 verification trail |

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
*Last updated: 2026-07-24 after v2.4 milestone*
