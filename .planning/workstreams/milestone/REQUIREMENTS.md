# Requirements: GNUS Child Wallet — v2.5 node_example Child Wallet Commands

**Defined:** 2026-07-27
**Core Value:** Main wallet must be able to discover, monitor, and manage registered child wallets through consensus-visible state

## v1 Requirements

Requirements for this milestone. Each maps to roadmap phases.

### Node Example CLI

- [ ] **NEXC-01**: User can run `registerchild <main_address>` in `node_example` to register the running node as a child wallet of the given main address — `dev_wallet` is derived from `dev_config_.Addr`, `peers_cut` is the fraction-complement of `dev_config_.Cut` (`1.0 - dev_cut_fraction`) expressed in the same fixed-point scale `TokenAmount::ParseMinions` produces, and `game_id`/`publisher_id` use mock placeholder values (not consumed downstream today)
- [ ] **NEXC-02**: User can run `listchildren <main_address>` in `node_example` to list all children registered to a main wallet, showing each child's address and current balance
- [ ] **NEXC-03**: User can run `childbalance <child_address> [token_id]` in `node_example` to query a single child's balance — a specific token if `token_id` is given, or the all-tokens total when omitted

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap. Carried forward from prior child-wallet milestones (see PROJECT.md).

### Monitoring

- **MON-01**: Full monitoring dashboard — per-child balance, all assets/tokens, activity history
- **MON-02**: Escrow status and lifecycle monitoring for registered children

### API

- **API-01**: gRPC endpoint exposing child registration/balance to external callers

### Tokens

- **TOK-01**: Multi-token balance query (GNUS, child tokens, NFTs) beyond single-token/all-tokens total

### Policy

- **POL-01**: Transfer amount limits/policy beyond existing CONS-01/CONS-02 consensus gates (e.g. per-child caps, rate limiting)

### UI

- **UI-01**: GeniusWallet Flutter UI wiring for child-wallet transfers and monitoring

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| GeniusSDK / SDKExample changes | Milestone targets `node_example`'s `sgns::GeniusNode`-direct REPL only; the SDK C API already exposes equivalent wrappers (`GeniusSDKRegisterChild` etc.) from v2.2, unchanged here |
| GeniusWallet Flutter UI wiring | UI-01, deferred — node/SDK-layer milestones only so far |
| Real (non-mock) `game_id`/`publisher_id` values or a config source for them | Nothing downstream consumes these fields yet; mock values are sufficient until a consumer exists |
| Persisting or configuring the main wallet address across sessions | `registerchild`/`listchildren` take `<main_address>` as a per-invocation argument; no session/config state introduced |
| Transfer commands (fund/recover) for children in `node_example` | Already exposed via GeniusSDK (`GeniusSDKFundChild`/`GeniusSDKRecoverFromChild`, v2.3); not requested for `node_example` this milestone |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| NEXC-01 | TBD | Pending |
| NEXC-02 | TBD | Pending |
| NEXC-03 | TBD | Pending |

**Coverage:**
- v1 requirements: 3 total
- Mapped to phases: 0
- Unmapped: 3 ⚠️ (pending roadmap creation)

---
*Requirements defined: 2026-07-27*
*Last updated: 2026-07-27 after initial definition*
