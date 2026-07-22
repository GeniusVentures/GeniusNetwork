# Roadmap: GNUS Child Wallet

## Milestones

- ✅ **v1.0 Child Wallet Design** — Phases 1-3 (shipped 2026-07-15)
- ✅ **v2.0 Registration Implementation** — Phases 1-2 (shipped 2026-07-17)
- ✅ **v2.1 Main Wallet Child Balance Query** — Phase 1 (shipped 2026-07-17)
- ✅ **v2.2 GeniusSDK Child Wallet Interfaces** — Phase 2 (shipped 2026-07-20)
- ✅ **v2.3 Child Wallet Transfers** — Phases 3-4 (shipped 2026-07-21)

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

<details>
<summary>✅ v2.3 Child Wallet Transfers (Phases 3-4) — SHIPPED 2026-07-21</summary>

Archived: [`.planning/milestones/v2.3-ROADMAP.md`](milestones/v2.3-ROADMAP.md)

- [x] Phase 3: Parent-Child Transfer Authority (4/4 plans) — completed 2026-07-21
- [x] Phase 4: GeniusSDK Transfer Wrappers (1/1 plans) — completed 2026-07-21

</details>

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|-----------------|--------|-----------|
| Child Balance Query | v2.1 | 2/2 | Complete | 2026-07-17 |
| GeniusSDK Child Wallet Interfaces | v2.2 | 1/1 | Complete | 2026-07-18 |
| Parent-Child Transfer Authority | v2.3 | 4/4 | Complete | 2026-07-21 |
| GeniusSDK Transfer Wrappers | v2.3 | 1/1 | Complete | 2026-07-21 |

### Phase 5: Child Wallet Lifecycle States (Detach/Revoke)

**Goal:** Implement the child-initiated Detach and main-initiated Revoke lifecycle transitions for registered child wallets, per the v1.0 lifecycle design (`docs/03-02-reward-policy-lifecycle.md`, archived at `.planning/milestones/v1.0-phases/03-discovery-rewards-lifecycle/`): `reg/{child_addr}` CRDT fields `detach_flag` + `supersedes_sequence`, a new `RevokeTx` transaction type (`EmbeddedTransaction` oneof arm 9), a `FilterRegistration` gate extension checking `supersedes_sequence`, and reuse of `CheckParentChildAuthority` for revoke validation (main sig + Registered state). Nothing in `SuperGenius/src` implements this yet — only Unregistered/Registered exist today.
**Requirements**: [LIFE-01, LIFE-02, LIFE-03, LIFE-04]
**Depends on:** Phase 4
**Plans:** 5/5 plans complete

Plans:
**Wave 1**

- [x] 05-01-PLAN.md — Proto schema evolution (RegistrationTx detach_flag/supersedes_sequence, new RevokeTx message) + RevokeTransaction C++ class

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 05-02-PLAN.md — Dispatch wiring ("revoke" tx type, ParseRevokeTransaction reg/ mutation), FilterRegistration gate 3b (fork prevention), CheckParentChildAuthority revoke branch

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 05-03-PLAN.md — DetachChild/ReplaceMain/RevokeChild methods (TransactionManager + GeniusNode two-layer)

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 05-04-PLAN.md — Detach/Replace-Main adversarial tests (fork detection, re-registration, invariants)

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 05-05-PLAN.md — Revoke adversarial tests (unauthorized revoke, sequence mismatch, re-registration, invariants)

---
*Roadmap updated: 2026-07-21 — Phase 5 (Child Wallet Lifecycle States) planned: 5 plans across proto/consensus-gate/CRDT-filter/GeniusNode/test layers*
