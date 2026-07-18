# Requirements: GNUS Child Wallet — Milestone v2.2

**Defined:** 2026-07-17
**Core Value:** The main wallet must be able to discover, monitor, and manage registered child wallets through consensus-visible state

## v2.2 Requirements

Requirements for the GeniusSDK Child Wallet Interfaces milestone. Each maps to roadmap phases.

### SDK Registration (SDKR)

- [ ] **SDKR-01**: External caller can register this node as a child wallet under a main wallet address via a GeniusSDK C function (wraps `GeniusNode::RegisterChild`, auto-derived sequence overload)
- [ ] **SDKR-02**: Caller can supply registration metadata (game_id, publisher_id, dev_wallet, peers_cut) via a new `GeniusRegistrationMetadata` C struct passed to the registration call
- [ ] **SDKR-03**: A main-side caller can enumerate its registered children via a GeniusSDK C function (wraps `GeniusNode::GetRegistrationsForMain`), receiving each child's address, sequence, and metadata
- [ ] **SDKR-04**: Registration and discovery calls return existing `GeniusNodeReturnValue_t` status codes (not initialized / invalid argument / registration failure) consistent with other GeniusSDK calls

### SDK Balance (SDKB)

- [ ] **SDKB-01**: External caller can query a child wallet's balance for a specific token via a GeniusSDK C function (wraps `GeniusNode::GetChildBalance` token-filtered overload)
- [ ] **SDKB-02**: External caller can query a child wallet's total balance across all tokens via a GeniusSDK C function (wraps `GeniusNode::GetChildBalance` all-tokens overload)

### Tests (TEST)

- [ ] **TEST-01**: `GeniusSDK/test` unit tests cover the new registration, discovery, and balance SDK calls against a running GeniusNode instance, including not-initialized and invalid-argument error paths

## Future Requirements

Deferred to future release. Tracked but not in current roadmap.

### API

- **API-01**: gRPC endpoint exposing child registration/balance to external callers (SDK wrapper covers direct-link callers in v2.2; gRPC serves callers that can't link the SDK)

### Monitoring

- **MON-01**: Full monitoring dashboard — per-child balance, all assets/tokens, activity history, escrow status
- **MON-02**: Lifecycle monitoring — registration state transitions, revoke/detach visibility

### Tokens

- **TOK-01**: Multi-token balance query (GNUS, child tokens, NFTs) — v2.1/v2.2 cover child token only

## Out of Scope

Explicitly excluded from v2.2. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| gRPC endpoint exposure | Separate transport concern (API-01) — SDK wrapper is the direct-link path; gRPC deferred |
| GeniusWallet Flutter UI wiring | This milestone is SDK-layer only; UI consumption is a future milestone |
| New proto messages/schema changes | `RegistrationMetadata`/`RegistrationTx` already exist from v2.0 — no new wire format needed |
| Manual-sequence `RegisterChild` overload | SDK exposes only the auto-derive overload for v1; manual sequence stays C++-internal (tests/replay) |
| Balance display formatting (FormatTokens/ConvertToChildToken) | Carried over from v2.1 out-of-scope — still deferred |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SDKR-01 | TBD | Pending |
| SDKR-02 | TBD | Pending |
| SDKR-03 | TBD | Pending |
| SDKR-04 | TBD | Pending |
| SDKB-01 | TBD | Pending |
| SDKB-02 | TBD | Pending |
| TEST-01 | TBD | Pending |

**Coverage:**
- v2.2 requirements: 7 total
- Mapped to phases: 0 (pending roadmap creation)
- Unmapped: 7 ⚠️ (resolved by roadmapper)

---
*Requirements defined: 2026-07-17*
*Last updated: 2026-07-17 after initial milestone v2.2 definition*
