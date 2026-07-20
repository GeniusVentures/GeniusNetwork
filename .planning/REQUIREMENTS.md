# Requirements: GNUS Child Wallet — Milestone v2.3

**Defined:** 2026-07-20
**Core Value:** The main wallet must be able to discover, monitor, and manage registered child wallets through consensus-visible state

## v2.3 Requirements

Requirements for the Child Wallet Transfers milestone. Each maps to roadmap phases. REQ-IDs reuse the rule numbers from `docs/02-consensus-parent-child-authority.md` directly (CONS-01/02/06) for traceability back to the original design.

### Consensus Authority (CONS)

- [ ] **CONS-01**: Main wallet can fund a registered child wallet via an ordinary `"transfer"` transaction; the new `CheckParentChildAuthority` gate treats the `reg/` check as a consistency validation, not access control — an unregistered destination still succeeds as a normal transfer
- [ ] **CONS-02**: Main wallet can recover funds from a registered child wallet, restricted to sending back to its own registered main address; the gate rejects a main-signed recovery transfer whose destination doesn't match the `reg/` record's `main_address` (D-21)
- [ ] **CONS-06**: `CheckParentChildAuthority` is inserted as an independent gate between `CheckTransactionAuthorization` and `CheckTransactionTimestamp` in `ValidateTransactionForConsensus`, orthogonal to existing UTXO-ownership (`ValidateWitness`) checks — no modification to `GeniusInputValidator.cpp`

### Regression Coverage (REGR)

- [ ] **REGR-01**: Child-signed transfers to main or arbitrary addresses (CONS-03) continue to pass through the new gate unchanged (short-circuit `Approve()`)
- [ ] **REGR-02**: Child-signed transfers to the developer wallet via `PayDev` (CONS-04) continue to work unchanged
- [ ] **REGR-03**: A child cannot spend a main wallet's UTXOs even when claiming delegated authority — `ValidateWitness` owner_address check still rejects (CONS-05 invariant) — covered by a new regression test

### SDK Transfer (SDKT)

- [ ] **SDKT-01**: GeniusSDK C API exposes a call for external callers to fund a registered child wallet from the main wallet (wraps the CONS-01 transfer path)
- [ ] **SDKT-02**: GeniusSDK C API exposes a call for external callers to recover funds from a registered child wallet back to the main wallet (wraps the CONS-02 transfer path)
- [ ] **SDKT-03**: Both transfer calls return existing `GeniusNodeReturnValue_t` status codes (not-initialized / invalid-argument / rejected), consistent with other GeniusSDK calls

## Future Requirements

Deferred to future release. Tracked but not in current roadmap.

### Policy

- **POL-01**: Transfer amount limits/policy beyond CONS-01/CONS-02 (e.g. per-child caps, rate limiting)

### UI

- **UI-01**: GeniusWallet Flutter UI wiring for child-wallet transfers

## Out of Scope

Explicitly excluded from v2.3. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| New proto messages / new transaction type | Reuses the existing `"transfer"` tx type per D-20 — no new wire format needed |
| GeniusWallet Flutter UI wiring | This milestone is SDK/node-layer only; UI consumption is a future milestone |
| Transfer amount limits/policy beyond CONS-01/CONS-02 | Not part of the spec'd consensus rules; a future policy milestone if needed |
| Dedicated `GeniusSDK/test` unit tests | GeniusSDK is a thin C FFI wrapper; the underlying `GeniusNode`/`TransactionManager` logic is covered by SuperGenius tests — duplicating coverage at the shim layer adds no value |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CONS-01 | TBD | Pending |
| CONS-02 | TBD | Pending |
| CONS-06 | TBD | Pending |
| REGR-01 | TBD | Pending |
| REGR-02 | TBD | Pending |
| REGR-03 | TBD | Pending |
| SDKT-01 | TBD | Pending |
| SDKT-02 | TBD | Pending |
| SDKT-03 | TBD | Pending |

**Coverage:**
- v2.3 requirements: 9 total
- Mapped to phases: 0 (pending roadmap creation)
- Unmapped: 9 ⚠️ (will be resolved by gsd-roadmapper)

---
*Requirements defined: 2026-07-20*
*Last updated: 2026-07-20 after initial definition*
