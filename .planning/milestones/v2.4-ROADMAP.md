# Roadmap: GNUS Child Wallet

## Milestones

- ✅ **v1.0 Child Wallet Design** — Phases 1-3 (shipped 2026-07-15)
- ✅ **v2.0 Registration Implementation** — Phases 1-2 (shipped 2026-07-17)
- ✅ **v2.1 Main Wallet Child Balance Query** — Phase 1 (shipped 2026-07-17)
- ✅ **v2.2 GeniusSDK Child Wallet Interfaces** — Phase 2 (shipped 2026-07-20)
- ✅ **v2.3 Child Wallet Transfers** — Phases 3-4 (shipped 2026-07-21)
- 🚧 **v2.4 Merge origin/develop into dev_childwallet** — Phases 6-7 (in progress)

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
| Child Wallet Lifecycle States (Detach/Revoke) | v2.3 | 6/6 | Complete | 2026-07-23 |
| SuperGenius Merge & Regression Verification | v2.4 | 0/TBD | Not started | - |
| GeniusSDK Merge & Build Verification | v2.4 | 0/TBD | Not started | - |

### Phase 5: Child Wallet Lifecycle States (Detach/Revoke) — ✅ COMPLETE

**Goal:** Implement the child-initiated Detach and main-initiated Revoke lifecycle transitions for registered child wallets, per the v1.0 lifecycle design (`docs/03-02-reward-policy-lifecycle.md`, archived at `.planning/milestones/v1.0-phases/03-discovery-rewards-lifecycle/`): `reg/{child_addr}` CRDT fields `detach_flag` + `supersedes_sequence`, a new `RevokeTx` transaction type (`EmbeddedTransaction` oneof arm 9), a `FilterRegistration` gate extension checking `supersedes_sequence`, and reuse of `CheckParentChildAuthority` for revoke validation (main sig + Registered state). Nothing in `SuperGenius/src` implements this yet — only Unregistered/Registered exist today.
**Requirements**: [LIFE-01, LIFE-02, LIFE-03, LIFE-04]
**Depends on:** Phase 4
**Plans:** 6/6 plans complete — gap closure done, all Revoke/Detach/Replace-Main tests pass, zero regressions (see 05-06-SUMMARY.md)

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

### 🚧 v2.4 Merge origin/develop into dev_childwallet (In Progress)

**Milestone Goal:** Bring SuperGenius and GeniusSDK `dev_childwallet` branches current with `origin/develop` — including the `DevConfig_st`→`GeniusNodeConfig` rename — with zero regressions to child-wallet functionality.

### Phase 6: SuperGenius Merge & Regression Verification

**Goal:** Bring SuperGenius's `dev_childwallet` branch current with `origin/develop` via a merge commit (not a rebase — the branch is already shared/pushed), resolving all conflicts in the 9 confirmed shared files including the `DevConfig_st`→`GeniusNodeConfig` rename, with the merged branch building cleanly and every pre-existing child-wallet capability confirmed regression-free.
**Requirements**: [MERGE-01, MVER-01, MVER-03, MVER-04]
**Depends on:** Phase 5
**Success Criteria** (what must be TRUE):

  1. SuperGenius's `dev_childwallet` branch has a merge commit with `origin/develop` as a parent (two-parent merge commit visible in `git log`), pushed to `origin/dev_childwallet`.
  2. All 9 confirmed shared files (`src/account/GeniusNode.{hpp,cpp}`, `src/account/TransactionManager.{hpp,cpp}`, `src/blockchain/Blockchain.hpp`, `src/blockchain/impl/Blockchain.cpp`, `src/blockchain/impl/proto/Consensus.proto`, `src/account/CMakeLists.txt`, `test/src/account/CMakeLists.txt`) are conflict-free with no leftover conflict markers, and zero `DevConfig_st` references remain anywhere in `src/`, `test/`, or `example/` (all ~17 replaced by `GeniusNodeConfig`, struct fields unchanged).
  3. SuperGenius builds cleanly across all targets post-merge, with no new compiler/linker errors introduced by conflict resolution.
  4. The full pre-existing child-wallet test suite — registration (v2.0), balance query (v2.1), GeniusSDK wrapper interfaces (v2.2), transfer authority CONS-01/CONS-02 (v2.3 Phase 3), transfer wrappers (v2.3 Phase 4), and lifecycle Detach/Revoke/ReplaceMain (Phase 5) — passes with zero regressions.
  5. `CheckParentChildAuthority`, `FilterRegistration`, `CheckCertifiedParent`, and the `transaction_parsers` registration-tx dispatch entry all still function as designed against the `origin/develop` changes merged into the 9 shared files.

**Plans:** 5/5 plans complete

Plans:
**Wave 1**

- [x] 06-01-PLAN.md — Start the merge (no-commit) and resolve the 2 real conflicts (retire ProcessingTransaction consistently in TransactionManager.cpp + CMakeLists.txt)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 06-02-PLAN.md — DevConfig_st -> GeniusNodeConfig mechanical rename sweep across the 15 non-conflicting files

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 06-03-PLAN.md — Build all targets post-merge (MVER-01) + manual read-through of the 4 large auto-merged files

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 06-04-PLAN.md — Full regression suite (MVER-03) + targeted MVER-04 consensus-gate verification

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 06-05-PLAN.md — Finalize + push the merge commit, bump outer-repo SuperGenius submodule pointer

### Phase 7: GeniusSDK Merge & Build Verification

**Goal:** Bring GeniusSDK's `dev_childwallet` branch current with the 1 remaining `origin/develop` commit (already merged once at `6f05025`) and confirm it builds cleanly against the SuperGenius static lib/headers updated in Phase 6.
**Requirements**: [MERGE-02, MVER-02]
**Depends on:** Phase 6
**Success Criteria** (what must be TRUE):

  1. GeniusSDK's `dev_childwallet` branch has a merge commit with `origin/develop` as a parent, pushed to `origin/dev_childwallet`.
  2. GeniusSDK builds cleanly against the Phase-6-updated SuperGenius static lib and headers, with no new compiler/linker errors.

**Plans**: TBD

---
*Roadmap updated: 2026-07-23 — v2.4 roadmap created: Phase 6 (SuperGenius Merge & Regression Verification) and Phase 7 (GeniusSDK Merge & Build Verification) defined, continuing numbering from Phase 5. All 6 v2.4 requirements (MERGE-01, MERGE-02, MVER-01..04) mapped with zero orphans.*
