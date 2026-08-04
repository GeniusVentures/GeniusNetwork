# Roadmap: GNUS Child Wallet

## Milestones

- ✅ **v1.0 Child Wallet Design** — Phases 1-3 (shipped 2026-07-15)
- ✅ **v2.0 Registration Implementation** — Phases 1-2 (shipped 2026-07-17)
- ✅ **v2.1 Main Wallet Child Balance Query** — Phase 1 (shipped 2026-07-17)
- ✅ **v2.2 GeniusSDK Child Wallet Interfaces** — Phase 2 (shipped 2026-07-20)
- ✅ **v2.3 Child Wallet Transfers** — Phases 3-4 (shipped 2026-07-21)
- ✅ **v2.4 Merge origin/develop into dev_childwallet** — Phases 6-7 (shipped 2026-07-24)
- 🚧 **v2.5 node_example Child Wallet Commands** — Phase 8 (in progress)

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

<details>
<summary>✅ v2.4 Merge origin/develop into dev_childwallet (Phases 6-7) — SHIPPED 2026-07-24</summary>

Archived: [`.planning/milestones/v2.4-ROADMAP.md`](milestones/v2.4-ROADMAP.md)

- [x] Phase 6: SuperGenius Merge & Regression Verification (5/5 plans) — completed 2026-07-23
- [x] Phase 7: GeniusSDK Merge & Build Verification (completed directly by user, no formal GSD plans) — completed 2026-07-24

</details>

### 🚧 v2.5 node_example Child Wallet Commands (In Progress)

**Milestone Goal:** Give `node_example`'s interactive REPL commands to register the node as a child wallet, list children registered to a main wallet, and query child balances — using `GeniusNode`'s existing `RegisterChild`/`GetRegistrationsForMain`/`GetChildBalance` C++ methods directly (no GeniusSDK C API changes, no GeniusWallet UI this milestone).

- [x] **Phase 8: node_example Child Wallet Commands** - Add `registerchild`, `listchildren`, and `childbalance` REPL commands to `node_example` (completed 2026-07-27)

## Phase Details

### Phase 8: node_example Child Wallet Commands

**Goal**: Users can register the running `node_example` instance as a child wallet, discover all children registered to a given main wallet, and query any child's balance — all from the `node_example` interactive REPL (`SuperGenius/example/node_test/NodeExample.cpp`), reusing `GeniusNode::RegisterChild`/`GetRegistrationsForMain`/`GetChildBalance` with no new proto, consensus, or GeniusSDK work.
**Depends on**: None — all three underlying `GeniusNode` methods already exist and are unchanged (`RegisterChild`/`GetRegistrationsForMain` from v2.0, `GetChildBalance` from v2.1)
**Requirements**: NEXC-01, NEXC-02, NEXC-03
**Success Criteria** (what must be TRUE):

  1. Running `registerchild <main_address>` at the `node_example` REPL returns a success message, and the registration is discoverable via `listchildren <main_address>` immediately after
  2. Running `listchildren <main_address>` at the REPL lists every child currently registered to that main address, showing each child's address AND its current balance (not address alone)
  3. Running `childbalance <child_address>` (no `token_id`) at the REPL prints that child's all-tokens total balance
  4. Running `childbalance <child_address> <token_id>` at the REPL prints the balance for just the specified token

**Plans**: 1/1 plans complete

Plans:

- [x] 08-01-PLAN.md — Add `childbalance`, `listchildren`, `registerchild` REPL commands to `node_example` (NEXC-01/02/03)

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|-----------------|--------|-----------|
| Child Balance Query | v2.1 | 2/2 | Complete | 2026-07-17 |
| GeniusSDK Child Wallet Interfaces | v2.2 | 1/1 | Complete | 2026-07-18 |
| Parent-Child Transfer Authority | v2.3 | 4/4 | Complete | 2026-07-21 |
| GeniusSDK Transfer Wrappers | v2.3 | 1/1 | Complete | 2026-07-21 |
| Child Wallet Lifecycle States (Detach/Revoke) | v2.3 | 6/6 | Complete | 2026-07-23 |
| node_example Child Wallet Commands | v2.5 | 0/1 | Not started | - |

### Phase 5: Child Wallet Lifecycle States (Detach/Revoke) — ✅ COMPLETE

**Goal:** Implement the child-initiated Detach and main-initiated Revoke lifecycle transitions for registered child wallets, per the v1.0 lifecycle design (`docs/03-02-reward-policy-lifecycle.md`, archived at `.planning/milestones/v1.0-phases/03-discovery-rewards-lifecycle/`): `reg/{child_addr}` CRDT fields `detach_flag` + `supersedes_sequence`, a new `RevokeTx` transaction type (`EmbeddedTransaction` oneof arm 9), a `FilterRegistration` gate extension checking `supersedes_sequence`, and reuse of `CheckParentChildAuthority` for revoke validation (main sig + Registered state). Nothing in `SuperGenius/src` implements this yet — only Unregistered/Registered exist today.
**Requirements**: [LIFE-01, LIFE-02, LIFE-03, LIFE-04]
**Depends on:** Phase 4
**Plans:** 1/1 plans complete

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

**Wave 6** *(gap closure — blocked on Wave 5 completion; found by 05-VERIFICATION.md)*

- [x] 05-06-PLAN.md — Fixed ParseRevokeTransaction's CRDT-write deadlock. Root cause diverged from the plan's own hypothesis: not the DAG-broadcast path, but CrdtSet::mutex_ reentrancy (fixed via std::recursive_mutex, found through live debugging). PutKeyLocal/GlobalDB::PutLocal kept as the correct local-write mechanism. Also fixed two pre-existing test bugs (nonce collision, missing previous_hash) blocking verification. All 6 Revoke tests pass; zero regressions.

---
*Roadmap updated: 2026-07-27 — v2.5 roadmap created: Phase 8 (node_example Child Wallet Commands) added, covering NEXC-01/NEXC-02/NEXC-03 (3/3 requirements mapped, 100% coverage). Continues phase numbering from v2.4's Phase 7 per this workstream's no-reset convention.*
*Roadmap updated: 2026-07-27 — Phase 8 planned: 1 plan (08-01-PLAN.md, single wave, 3 sequential tasks — childbalance → listchildren → registerchild, all three touching only `SuperGenius/example/node_test/NodeExample.cpp`). No mid-flight checkpoint tasks emitted (`workflow.human_verify_mode = end-of-phase`); behavioral verification against the four success criteria is embedded as `<verify><human-check>` blocks, harvested at end-of-phase into `08-UAT.md`.*
