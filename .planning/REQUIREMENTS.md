# Requirements: GNUS Child Wallet — v2.4

**Defined:** 2026-07-23
**Core Value:** The main wallet must be able to discover, monitor, and manage registered child wallets through consensus-visible state

## v1 Requirements

Requirements for milestone v2.4 (Merge origin/develop into dev_childwallet). Each maps to roadmap phases.

### Submodule Merges

- [ ] **MERGE-01**: SuperGenius `dev_childwallet` is merged with `origin/develop` (162 commits behind at scoping time) via a merge commit — not a rebase, since the branch is already shared/pushed — with all conflicts resolved in the 9 confirmed shared files (`src/account/GeniusNode.{hpp,cpp}`, `src/account/TransactionManager.{hpp,cpp}`, `src/blockchain/Blockchain.hpp`, `src/blockchain/impl/Blockchain.cpp`, `src/blockchain/impl/proto/Consensus.proto`, `src/account/CMakeLists.txt`, `test/src/account/CMakeLists.txt`), including adapting all `DevConfig_st` references (~17 files) to the renamed `GeniusNodeConfig` typedef (fields unchanged), and the merge commit pushed to `origin/dev_childwallet` — **merge commit `cb4e46da` created and fully verified (2 parents, conflicts resolved, rename swept, build clean, zero regressions); push to `origin/dev_childwallet` deliberately withheld per explicit user instruction ("Commit it, don't push anything") — outstanding action: `git push origin dev_childwallet` from within `SuperGenius/`**
- [ ] **MERGE-02**: GeniusSDK `dev_childwallet` is merged with the 1 remaining `origin/develop` commit (already merged once at `6f05025`), merge commit pushed to `origin/dev_childwallet`

### Build & Regression Verification

- [x] **MVER-01**: SuperGenius builds cleanly (all targets) after MERGE-01, with no new compiler/linker errors introduced by conflict resolution
- [ ] **MVER-02**: GeniusSDK builds cleanly against the updated SuperGenius static lib after MERGE-01 and MERGE-02
- [x] **MVER-03**: Full existing child-wallet test suite passes with zero regressions post-merge — registration (v2.0), balance query (v2.1), GeniusSDK wrapper interfaces (v2.2), transfer authority CONS-01/CONS-02 (v2.3 Phase 3), transfer wrappers (v2.3 Phase 4), and lifecycle states Detach/Revoke/ReplaceMain (Phase 5)
- [x] **MVER-04**: `origin/develop`'s changes in the 9 shared files are confirmed compatible with child-wallet consensus gates — `CheckParentChildAuthority`, `FilterRegistration`, `CheckCertifiedParent`, and the `transaction_parsers` registration-tx dispatch entry all still function as designed after the merge

## v2 Requirements

None — this milestone is scoped entirely to merge integration.

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| GeniusWallet merge/update | Currently on `dev_mergeandroidbg`, not a `dev_childwallet` branch — untouched this milestone |
| thirdparty submodule merge | Already tracks `develop` directly; no separate child-wallet branch exists to merge |
| Rebasing `dev_childwallet` onto `develop` | Branch is already pushed/shared on origin; rebase would rewrite shared history — merge commit chosen instead |
| Separate REQ-ID for the `DevConfig_st`→`GeniusNodeConfig` rename | Folded into MERGE-01 as part of ordinary conflict resolution, not tracked independently |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| MERGE-01 | Phase 6 | Partial — committed (`cb4e46da`), push withheld per user instruction |
| MERGE-02 | Phase 7 | Pending |
| MVER-01 | Phase 6 | Complete |
| MVER-02 | Phase 7 | Pending |
| MVER-03 | Phase 6 | Complete |
| MVER-04 | Phase 6 | Complete |

**Coverage:**

- v1 requirements: 6 total
- Mapped to phases: 6/6 ✓
- Unmapped: 0

---
*Requirements defined: 2026-07-23*
*Last updated: 2026-07-23 after roadmap creation — all 6 requirements mapped to Phase 6 (SuperGenius Merge & Regression Verification) and Phase 7 (GeniusSDK Merge & Build Verification)*
