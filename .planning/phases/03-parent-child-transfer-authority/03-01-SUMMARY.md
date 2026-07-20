---
phase: 03-parent-child-transfer-authority
plan: 01
subsystem: consensus
tags: [consensus, blockchain, signature, registration, crdt, cpp]

# Dependency graph
requires:
  - phase: 04-registration-proto-transaction (v2.0)
    provides: RegistrationTx proto schema, reg/{child_addr} CRDT storage path
provides:
  - "Blockchain::CheckCertifiedParent(child_addr) -> optional<main_addr> — D-63 certified-status lookup, no genius_node dependency"
  - "GeniusTransaction::CheckSignatureAgainst(address) — parameterized signature verification primitive"
affects: [03-02-parent-child-authority-gate, 03-03-recover-from-child]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Direct reg/{addr} CRDT read + raw proto ParseFromArray from a lower-tier library (blockchain_genesis), avoiding a circular dependency on genius_node's TransactionManager/RegistrationTransaction deserializers"
    - "Extract-and-delegate refactor for parameterized signature verification (CheckSignatureAgainst -> CheckSignature)"

key-files:
  created: []
  modified:
    - SuperGenius/src/blockchain/Blockchain.hpp
    - SuperGenius/src/blockchain/impl/Blockchain.cpp
    - SuperGenius/src/account/GeniusTransaction.hpp
    - SuperGenius/src/account/GeniusTransaction.cpp

key-decisions:
  - "CheckCertifiedParent implemented entirely with symbols already reachable from blockchain_genesis (SGTransaction::RegistrationTx proto, base::sgns_version, Blockchain's own db_) — no TransactionManager::/RegistrationTransaction:: reference, preserving the one-directional genius_node -> blockchain_genesis link dependency"
  - "Registration certified-status resolved via CheckCertificate(reg_tx.dag_struct().data_hash()), matching the exact value GeniusTransaction::GetHash() returns for a certified registration"

patterns-established:
  - "Lower-tier CRDT lookups that need to be reachable from multiple higher-tier consumers belong on Blockchain (which already holds db_ and is already a ValidateWitness dependency), not on TransactionManager"

requirements-completed: [CONS-06]

coverage:
  - id: D1
    description: "Blockchain::CheckCertifiedParent returns std::nullopt for absent/uncertified reg/ entries and the certified main_address otherwise, with zero genius_node-only symbol references"
    requirement: "CONS-06"
    verification:
      - kind: unit
        ref: "grep -c 'TransactionManager::|RegistrationTransaction::' SuperGenius/src/blockchain/impl/Blockchain.cpp == 0"
        status: pass
      - kind: integration
        ref: "cmake --build SuperGenius/build/Windows/Release --target blockchain_genesis --config Release"
        status: pass
    human_judgment: false
  - id: D2
    description: "GeniusTransaction::CheckSignatureAgainst(address) added; CheckSignature() delegates to it with dag_st.source_addr(), behavior-preserving"
    requirement: "CONS-06"
    verification:
      - kind: unit
        ref: "test_bin/Release/registration_transaction_test.exe --gtest_filter=RegistrationTransactionTest.ChildRegistrationTamperedSignatureRejected"
        status: pass
      - kind: unit
        ref: "test_bin/Release/account_signature_test.exe (GeniusAccountSignatureTest.*)"
        status: pass
    human_judgment: false

duration: 25min
completed: 2026-07-20
status: complete
---

# Phase 3 Plan 01: Certified-Parent Lookup + Parameterized Signature Verification Summary

**Added `Blockchain::CheckCertifiedParent` (D-63 CRDT certified-status lookup, zero `genius_node` dependency) and `GeniusTransaction::CheckSignatureAgainst` (parameterized signature verification `CheckSignature` now delegates to) — the two shared primitives Plan 02's gate and `CheckTransactionAuthorization` extension build on**

## Performance

- **Duration:** 25 min
- **Started:** 2026-07-20T22:43:54Z
- **Completed:** 2026-07-20T23:09:00Z (approx)
- **Tasks:** 2 completed
- **Files modified:** 4

## Accomplishments
- `Blockchain::CheckCertifiedParent(child_addr)` resolves a registered child's certified main address by reading `reg/{child_addr}` directly from the CRDT, parsing the raw `SGTransaction::RegistrationTx` proto, and gating on `CheckCertificate(reg_hash)` per D-26 — implemented entirely with symbols already linked into `blockchain_genesis`, with no accidental reference to `TransactionManager::`/`RegistrationTransaction::` (verified via grep and a standalone `blockchain_genesis` build)
- `GeniusTransaction::CheckSignatureAgainst(address)` extracted from `CheckSignature()`'s body — a pure behavior-preserving refactor. `CheckSignature()` is now `return CheckSignatureAgainst(dag_st.source_addr());`; `CheckDAGSignatureLegacy()` untouched

## Task Commits

Each task was committed atomically inside the `SuperGenius` submodule:

1. **Task 1: Add Blockchain::CheckCertifiedParent (D-63 certified-status lookup)** - `620c1749` (feat)
2. **Task 2: Refactor GeniusTransaction::CheckSignature to extract CheckSignatureAgainst(address)** - `3384b7ba` (refactor)

**SuperGenius submodule pointer bump (outer repo):** `52fbf0e` (chore)

**Plan metadata:** committed separately after this SUMMARY (docs: complete plan)

_Note: this is a sequential (non-worktree) executor because the plan touches the `SuperGenius` git submodule — each task commit is a real commit inside `SuperGenius`, and the outer `GeniusNetwork` repo tracks the resulting submodule pointer with its own dedicated commit._

## Files Created/Modified
- `SuperGenius/src/blockchain/Blockchain.hpp` - declares `CheckCertifiedParent(const std::string &child_addr) const -> std::optional<std::string>` in the public section, after `CheckCertificate`
- `SuperGenius/src/blockchain/impl/Blockchain.cpp` - implements `CheckCertifiedParent`: builds the `/bc-{net}/reg/{addr}` key inline (no `TransactionManager::GetBlockChainBase()` call), reads via `db_->Get`, parses `SGTransaction::RegistrationTx` directly via `ParseFromArray`, checks `dag_struct().type() == "registration"`, gates on `CheckCertificate(dag_struct().data_hash())`, returns `main_address()`
- `SuperGenius/src/account/GeniusTransaction.hpp` - declares `CheckSignatureAgainst(const std::string &address) const` after `CheckSignature()`
- `SuperGenius/src/account/GeniusTransaction.cpp` - `CheckSignatureAgainst` holds the clear-signature/serialize/`VerifySignature` sequence formerly inline in `CheckSignature()`; `CheckSignature()` now delegates

## Decisions Made
- Followed the plan's explicit constraint: `CheckCertifiedParent`'s implementation must not call `TransactionManager::GetBlockChainBase()`, `TransactionManager::DeSerializeTransaction()`, or `RegistrationTransaction::DeSerializeByteVector()` (all compiled only into `genius_node`/`genius_node_test`, which links `blockchain_genesis` — not the reverse). Duplicated the trivial `"/bc-%hu/"` format string inline via `boost::format` rather than exposing a shared free function, matching the plan's explicit instruction (task 1, action step 1) and RESEARCH.md's Open Question #2 (exact home for the reg-key-format helper left to implementation discretion, low risk either way since the format string is simple/stable)
- Used `dag_struct().data_hash()` (not the child address) as the certification-gate key, per the plan's explicit derivation matching `GeniusTransaction::GetHash()`'s `dag_st.data_hash()` return value

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reworded an inline comment to avoid tripping the plan's own literal-grep verification gate**
- **Found during:** Task 1, immediately after implementing `CheckCertifiedParent`
- **Issue:** The plan's acceptance criteria requires `grep -c "TransactionManager::" SuperGenius/src/blockchain/impl/Blockchain.cpp` to return 0. My first draft included a code comment referencing `TransactionManager::GetBlockChainBase()` by name for documentation purposes — this is not an actual symbol dependency (comments don't affect linkage), but it did make the literal grep match count 1, failing the plan's own automated check.
- **Fix:** Reworded the comment to describe the reg-key format without literally spelling `TransactionManager::` (referenced the file/line instead: `account/TransactionManager.cpp:618-619`).
- **Files modified:** `SuperGenius/src/blockchain/impl/Blockchain.cpp`
- **Verification:** `grep -c "TransactionManager::\|RegistrationTransaction::" SuperGenius/src/blockchain/impl/Blockchain.cpp` now returns 0
- **Committed in:** `620c1749` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking — cosmetic, no functional/security impact)
**Impact on plan:** No scope creep; purely a wording fix to satisfy the plan's own automated verification command.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `Blockchain::CheckCertifiedParent` and `GeniusTransaction::CheckSignatureAgainst` are both compiled and test-verified (standalone `blockchain_genesis` build + `genius_node_test`/`registration_transaction_test` build, plus targeted signature regression tests)
- Plan 02 can now implement `CheckTransactionAuthorization`'s D-60 OR-branch (`tx.CheckSignatureAgainst(*certified_main)`), the new `CheckParentChildAuthority` gate, and the `GeniusInputValidator.cpp` per-input signature OR-branch — all three call sites depend only on symbols this plan added
- Known pre-existing issue unaffected by this plan: `child_registration_test.exe`/similar test binaries in this suite segfault on process teardown after all GTest assertions pass (unjoined libp2p/boost::asio threads) — not exercised or triggered by this plan's targeted test runs, which used `registration_transaction_test.exe` (single filtered case) and `account_signature_test.exe`, both of which exited cleanly (exit code 0)

---
*Phase: 03-parent-child-transfer-authority*
*Completed: 2026-07-20*

## Self-Check: PASSED

- FOUND: `.planning/phases/03-parent-child-transfer-authority/03-01-SUMMARY.md`
- FOUND: SuperGenius commit `620c1749` (Task 1)
- FOUND: SuperGenius commit `3384b7ba` (Task 2)
- FOUND: GeniusNetwork commit `52fbf0e` (submodule pointer bump)
