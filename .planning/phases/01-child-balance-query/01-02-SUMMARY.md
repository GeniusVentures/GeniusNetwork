---
phase: 01-child-balance-query
plan: 02
subsystem: testing
tags: [integration-test, balance, child-wallet, crdt-sync, gtest]

# Dependency graph
requires:
  - phase: 01-child-balance-query/01-01
    provides: "GeniusNode::GetChildBalance(child_address, token_id) and GetChildBalance(child_address) overloads"
provides:
  - "TEST_F(ChildRegistrationIntegrationTest, MainQueriesChildBalance) — multi-node proof that child mint → CRDT sync → main GetChildBalance round-trips the exact funded amount"
affects: [future API/gRPC balance exposure phase, future test-infra/node-shutdown hygiene phase]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Child-mints/main-queries integration test pattern: mint on child_node_ using child_node_->GetTokenID(), poll child's own balance until mint lands, then poll main's GetChildBalance until CRDT sync converges, before final EXPECT_EQ"

key-files:
  created: []
  modified:
    - SuperGenius/test/src/multiaccount/regtest/child_registration.cpp

key-decisions:
  - "MintTokens' chainid argument must match a registered test-only IInputValidator (\"test\", from testutil/TestMintInputValidator.hpp) — an arbitrary description string in that slot silently falls back to the public-chain validator requiring real RPC burn verification, causing instant mint rejection"

patterns-established:
  - "Poll-until-convergence test pattern extended to UTXO/balance sync (previously only used for registration discovery)"

requirements-completed: [INTG-01]

coverage:
  - id: D1
    description: "TEST_F(ChildRegistrationIntegrationTest, MainQueriesChildBalance) mints on child_node_ using its own DevConfig token, polls until CRDT sync converges, then asserts main_node_->GetChildBalance(child_address, child_token) equals the exact minted amount (500)"
    requirement: "INTG-01"
    verification:
      - kind: integration
        ref: "ctest -R child_registration_test — TEST_F(ChildRegistrationIntegrationTest, MainQueriesChildBalance) reported [ OK ]"
        status: pass
    human_judgment: false
  - id: D2
    description: "All 3 pre-existing TEST_F cases (ChildRegistersWithMain, MainDiscoversChild, InvalidRegistrationRejected) continue to pass unchanged — zero regressions"
    requirement: "INTG-01"
    verification:
      - kind: integration
        ref: "ctest -R child_registration_test — GTest summary: [ PASSED ] 4 tests."
        status: pass
    human_judgment: false

# Metrics
duration: 25min
completed: 2026-07-17
status: complete
---

# Phase 01 Plan 02: MainQueriesChildBalance Integration Test Summary

**Added `TEST_F(ChildRegistrationIntegrationTest, MainQueriesChildBalance)` proving end-to-end that a child node's mint propagates via CRDT sync to a balance the main node can read through `GetChildBalance` — all 4 cases in `child_registration_test` pass (GTest level), completing ROADMAP Phase 1.**

## Performance

- **Duration:** 25 min
- **Started:** 2026-07-17T21:50:00Z
- **Completed:** 2026-07-17T22:15:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- `TEST_F(ChildRegistrationIntegrationTest, MainQueriesChildBalance)` appended to `child_registration.cpp`: `child_node_` mints 500 units of its own DevConfig token via `MintTokens`, polls its own balance until the mint lands, polls `main_node_->GetChildBalance(...)` until CRDT sync converges, then asserts the exact minted amount round-trips
- `child_registration_test` builds cleanly and all 4 `TEST_F` cases pass at the GTest assertion level: `ChildRegistersWithMain`, `MainDiscoversChild`, `InvalidRegistrationRejected` (unchanged, zero regressions), and the new `MainQueriesChildBalance`
- INTG-01 proven end-to-end; ROADMAP Phase 1 Success Criteria 1-3 all satisfied (GetChildBalance correctness from Plan 01-01 + this multi-node proof + zero regressions)

## Task Commits

Each task was committed atomically (in the `SuperGenius` submodule, following the precedent set by Plan 01-01 since this repo hosts `SuperGenius` as a git submodule and `init.execute-phase` returned `sub_repos: []`):

1. **Task 1: Add TEST_F(ChildRegistrationIntegrationTest, MainQueriesChildBalance) to child_registration.cpp** - `d4c93b98` (feat)
2. **Task 2 deviation fix: use registered test chainid for child mint** - `ed83b2b3` (fix) — discovered during Task 2's build/run verification, see Deviations below
2. **Task 2: Build and run child_registration_test** - no commit (verification-only task; build + ctest run confirmed all 4 cases pass)

**Plan metadata:** committed separately in the parent GeniusNetwork repo (docs: complete plan)

## Files Created/Modified
- `SuperGenius/test/src/multiaccount/regtest/child_registration.cpp` - Added `TEST_F(ChildRegistrationIntegrationTest, MainQueriesChildBalance)` (banner comment + test body) after `InvalidRegistrationRejected`'s closing brace, before `} // namespace sgns`

## Decisions Made
- Followed the plan's/pattern-map's exact test skeleton (mint amount 500, D-65 dual poll-until-convergence pattern, child-first `GetChildBalance` call) verbatim
- Deviated from the plan's literal `"test_05_balance"` chainid string (which the plan described as a "description") after discovering it must instead be the registered test chainid `"test"` — see Deviations below

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] MintTokens chainid must match a registered test-only IInputValidator, not an arbitrary description string**
- **Found during:** Task 2 (build/run verification) — `MainQueriesChildBalance` failed with `mint_result.has_value() == false`, error message "Requested transaction failed"
- **Issue:** The plan's action/pattern-map text used `"test_05_balance"` as the mint's `chainid` argument, describing it as a free-text "description string." In reality this argument selects the `IInputValidator` via `TransactionManager::SelectInputValidator` — only `"test"` and `"0"` are registered (see `testutil/TestMintInputValidator.hpp`, already `#include`d in the test file). An unregistered chainid falls back to `public_chain_input_validator_`, which requires real RPC-based burn verification against a bridge chain named `"test_05_balance"` — nonexistent, so the mint transaction was rejected almost instantly (~100-300ms) with `TransactionStatus::FAILED`/`INVALID`, well before any timeout.
- **Fix:** Changed the chainid argument from `"test_05_balance"` to `"test"`, matching the registered test-only validator and the existing `multi_account_sync.cpp:199-221` precedent (which also uses `"test"`). Added an inline comment in the test explaining why this specific string is required.
- **Files modified:** `SuperGenius/test/src/multiaccount/regtest/child_registration.cpp`
- **Verification:** Rebuilt `child_registration_test`; ran the isolated `MainQueriesChildBalance` test via `--gtest_filter`, confirmed `[ OK ]` with the correct minted balance (500) observed on `main_node_` after CRDT sync; reran the full 4-test suite, confirmed `[ PASSED ] 4 tests.`
- **Committed in:** `ed83b2b3` (fix commit, separate from Task 1's `d4c93b98` since the bug was discovered during Task 2's verification pass)

---

**Total deviations:** 1 auto-fixed (1 blocking bug fix)
**Impact on plan:** Necessary for the test to exercise the intended mint path at all; no scope creep — fix stayed within the plan's single file (`child_registration.cpp`).

## Issues Encountered

**Pre-existing infra flakiness (documented, not fixed — out of scope): `child_registration_test.exe` segfaults on process teardown.**

After all 4 `TEST_F` cases report `[ PASSED ]` (zero GTest assertion failures), the test binary crashes with a segmentation fault during global teardown/static destruction — after `Global test environment tear-down` prints but before the process exits (`ctest -R child_registration_test` reports this as `SegFault` and marks the overall run as failed at the process level, despite `[ PASSED ] 4 tests.` from GTest itself).

**Proven unrelated to this plan's changes:** Reproduced the identical segfault-on-exit (exit code 139) by running only the 3 pre-existing `TEST_F` cases via `--gtest_filter`, excluding the new `MainQueriesChildBalance` entirely. This confirms the crash is a pre-existing lifecycle/teardown issue (likely in `TearDownTestSuite`'s node `.reset()` sequence or a lower-level component such as libp2p/boost::asio io_context threads not fully joined before process exit) — not caused by this plan's new test or by `GetChildBalance` (Plan 01-01).

**Scope decision:** Out of scope for this test-file-only plan; root-causing would require touching production node-lifecycle code outside `child_registration.cpp`, potentially an architectural change (Rule 4). Logged to `.planning/phases/01-child-balance-query/deferred-items.md` for a future phase/plan focused on test-infra or node-shutdown hygiene.

**Impact:** None on this plan's acceptance criteria — all 4 `TEST_F` cases pass at the assertion level, satisfying INTG-01 and ROADMAP Phase 1 Success Criteria 1-3. CI/ctest consumers should check the captured GTest summary (`[ PASSED ] 4 tests.`) rather than relying solely on the ctest process-exit code for this specific target until the teardown crash is fixed.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- INTG-01 proven end-to-end: child mints, CRDT sync propagates, main queries via `GetChildBalance` and observes the correct funded amount
- ROADMAP Phase 1 (child-balance-query) is functionally complete: all 3 Success Criteria satisfied
- Known blocker for CI reliability (not this plan's scope): `child_registration_test.exe`'s segfault-on-teardown will cause `ctest` to report failure even when all assertions pass — tracked in `deferred-items.md` for future remediation

---
*Phase: 01-child-balance-query*
*Completed: 2026-07-17*

## Self-Check: PASSED

- FOUND: SuperGenius/test/src/multiaccount/regtest/child_registration.cpp
- FOUND: .planning/phases/01-child-balance-query/deferred-items.md
- FOUND: commit d4c93b98 (SuperGenius submodule)
- FOUND: commit ed83b2b3 (SuperGenius submodule)
