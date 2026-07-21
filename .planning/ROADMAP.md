# Roadmap: GNUS Child Wallet

## Milestones

- ✅ **v1.0 Child Wallet Design** — Phases 1-3 (shipped 2026-07-15)
- ✅ **v2.0 Registration Implementation** — Phases 1-2 (shipped 2026-07-17)
- ✅ **v2.1 Main Wallet Child Balance Query** — Phase 1 (shipped 2026-07-17)
- ✅ **v2.2 GeniusSDK Child Wallet Interfaces** — Phase 2 (shipped 2026-07-20)
- 📋 **v2.3 Child Wallet Transfers** — Phases 3-4 (planned)

## Phases

<details>
<summary>✅ v1.0 Child Wallet Design (Phases 1-3) — SHIPPED 2026-07-15</summary>

Archived: [`.planning/milestones/v1.0-ROADMAP.md`](milestones/v1.0-ROADMAP.md)

</details>

<details>
<summary>✅ v2.0 Registration Implementation (Phases 1-2) — SHIPPED 2026-07-17</summary>

Archived: [`.planning/milestones/v2.0-ROADMAP.md`](milestones/v2.0-ROADMAP.md)

</details>

<details>
<summary>✅ v2.1 Main Wallet Child Balance Query (Phase 1) — SHIPPED 2026-07-17</summary>

Archived: [`.planning/milestones/v2.1-ROADMAP.md`](milestones/v2.1-ROADMAP.md)

- [x] Phase 1: Child Balance Query (2/2 plans) — completed 2026-07-17

</details>

<details>
<summary>✅ v2.2 GeniusSDK Child Wallet Interfaces (Phase 2) — SHIPPED 2026-07-20</summary>

Archived: [`.planning/milestones/v2.2-ROADMAP.md`](milestones/v2.2-ROADMAP.md)

- [x] Phase 2: GeniusSDK Child Wallet Interfaces (1/1 plans) — completed 2026-07-18

</details>

### 📋 v2.3 Child Wallet Transfers (Planned)

**Milestone Goal:** Enable authorized main↔child fund transfers — main can fund a registered child (CONS-01) and recover funds back from it (CONS-02) — enforced by a new `CheckParentChildAuthority` consensus gate, exposed through GeniusNode and the public GeniusSDK C API.

- [x] **Phase 3: Parent-Child Transfer Authority** - New `CheckParentChildAuthority` consensus gate enabling main→child funding and main-recover-from-child, with regression coverage proving existing child-signed paths are unaffected (completed 2026-07-21)
- [ ] **Phase 4: GeniusSDK Transfer Wrappers** - Expose both transfer directions through the public GeniusSDK C API for external callers

## Phase Details

### Phase 3: Parent-Child Transfer Authority

**Goal**: Main wallet can fund a registered child wallet and recover funds back from it, enforced by a new consensus-level `CheckParentChildAuthority` gate — while every existing child-signed transfer path (child→arbitrary, child→main, child→dev, child-cannot-spend-main) continues to behave exactly as before
**Depends on**: v2.0 Registration Implementation (`reg/{child_addr}` CRDT records the gate reads; certified-status flag)
**Requirements**: CONS-01, CONS-02, CONS-06, REGR-01, REGR-02, REGR-03
**Success Criteria** (what must be TRUE):

  1. Main wallet can submit a `"transfer"` tx funding a registered child address, and the new `CheckParentChildAuthority` gate approves it as an ordinary transfer — an unregistered destination still succeeds unchanged (CONS-01)
  2. Main wallet can submit a `"transfer"` tx recovering funds from a registered child back to its own registered main address, and the gate approves it (CONS-02)
  3. A main-signed recovery transfer whose destination does not match the child's registered main address is rejected by the gate (D-21 destination restriction, CONS-02)
  4. Child-signed transfers to arbitrary addresses, to the registered main, and to the developer wallet via `PayDev` continue to pass through the gate unchanged, confirmed by regression tests (REGR-01, REGR-02)
  5. A child-signed transaction attempting to spend a main wallet's UTXOs is still rejected by the existing `ValidateWitness` owner-address check, confirmed by a new regression test — proving the new gate stays orthogonal to UTXO *ownership* checks specifically (the signature-acceptance layer gains one narrow CRDT-gated branch in `GeniusInputValidator.cpp`, verified during planning to be required by D-60; the owner-address check itself is untouched) (REGR-03, CONS-06)

**Plans**: 4/4 plans complete
**Wave 1**

- [x] 03-01-PLAN.md — Certified-parent lookup (Blockchain::CheckCertifiedParent) + signature primitive (GeniusTransaction::CheckSignatureAgainst)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 03-02-PLAN.md — CheckParentChildAuthority consensus gate + D-60 signature-acceptance extension (CheckTransactionAuthorization + GeniusInputValidator.cpp)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 03-03-PLAN.md — RecoverFromChild transaction construction (TransactionManager + GeniusNode layers)

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 03-04-PLAN.md — CONS-01/CONS-02/D-21 + REGR-01/02/03 test coverage (extends existing registration_transaction_test.cpp per D-65)

### Phase 4: GeniusSDK Transfer Wrappers

**Goal**: External games/apps can fund a registered child wallet and recover funds from it through the public GeniusSDK C API, without linking SuperGenius directly
**Depends on**: Phase 3 (`CheckParentChildAuthority` gate and the underlying GeniusNode-level transfer call(s) must exist first)
**Requirements**: SDKT-01, SDKT-02, SDKT-03
**Success Criteria** (what must be TRUE):

  1. External caller can invoke a GeniusSDK C function to fund a registered child wallet from the main wallet, wrapping the CONS-01 transfer path (SDKT-01)
  2. External caller can invoke a GeniusSDK C function to recover funds from a registered child wallet back to the main wallet, wrapping the CONS-02 transfer path (SDKT-02)
  3. Both transfer calls return existing `GeniusNodeReturnValue_t` status codes (not-initialized / invalid-argument / rejected), consistent with other GeniusSDK calls (SDKT-03)

**Plans**: 1 plan
**Wave 1**

- [ ] 04-01-PLAN.md — GeniusSDKFundChild/FundChildGNUS + GeniusSDKRecoverFromChild/RecoverFromChildGNUS C API wrappers (SDKT-01/02/03)

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|-----------------|--------|-----------|
| Child Balance Query | v2.1 | 2/2 | Complete | 2026-07-17 |
| GeniusSDK Child Wallet Interfaces | v2.2 | 1/1 | Complete | 2026-07-18 |
| Parent-Child Transfer Authority | v2.3 | 0/4 | Planned | - |
| GeniusSDK Transfer Wrappers | v2.3 | 0/1 | Planned | - |

---
*Roadmap updated: 2026-07-20 — v2.3 roadmap created (Phase 3: Parent-Child Transfer Authority, Phase 4: GeniusSDK Transfer Wrappers); 9/9 requirements mapped*
