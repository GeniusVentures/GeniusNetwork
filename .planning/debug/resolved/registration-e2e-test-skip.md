---
status: verifying
trigger: "Fix ChildRegistrationEndToEnd test skip — io_context never run + full_node=false blocks isolated boot"
created: 2026-07-15T00:00:00Z
updated: 2026-07-15T00:00:00Z
---

## Current Focus

hypothesis: CONFIRMED. io_context worker thread + full_node=true allows TM to reach READY. Nonce starts at 0 for fresh account.
test: All 9 tests pass, 0 skipped
expecting: PASS
next_action: Commit fix in SuperGenius submodule

## Symptoms

expected: ChildRegistrationEndToEnd test should reach READY, register child, and verify transaction
actual: TM never reached READY, test GTEST_SKIP'd after 10s
errors: none (silent skip)
reproduction: Build and run registration_transaction_test.exe — ChildRegistrationEndToEnd always skipped
started: Since test was written (2026-07-15)

## Eliminated

## Evidence

- timestamp: 2026-07-15T00:00:00Z
  checked: base_crdt_test.cpp line 61
  found: io_ = std::make_shared<io_context>() created but never run
  implication: TM's TickOnce() posted to io_ never executes → TM stays in INITIALIZING forever

- timestamp: 2026-07-15T00:00:00Z
  checked: TransactionManager.cpp line 2356-2362
  found: CheckNonce() returns false when FetchNetworkNonce fails unless full_node_m is true
  implication: With full_node=false and no network, InitTransactions never reaches READY

- timestamp: 2026-07-15T00:00:00Z
  checked: TransactionManager.hpp line 230
  found: void Stop() exists — idempotent stop
  implication: Can call tm_->Stop() before stopping io_context

- timestamp: 2026-07-15T00:00:00Z
  checked: Test run output
  found: TM reached READY in ~5s with io_context running + full_node=true
  implication: Both fixes work as diagnosed

- timestamp: 2026-07-15T00:00:00Z
  checked: GeniusAccount.cpp line 985-992
  found: GetNextNonceLocked() returns 0 when local_confirmed_nonce_ is nullopt (fresh account)
  implication: EXPECT_GT(GetNonce(), 0) is incorrect for a new account; genesis nonce is 0

- timestamp: 2026-07-15T00:00:00Z
  checked: Full test run — 9/9 passed, 0 skipped
  found: ChildRegistrationEndToEnd OK (121255 ms)
  implication: Fix verified

## Resolution

root_cause: Two defects: (1) CRDTFixture creates io_ but never runs it, so TickOnce() never executes — TM state machine stalls in INITIALIZING. (2) full_node=false causes CheckNonce() to fail in isolated test (FetchNetworkNonce returns no_such_device) → InitTransactions never reaches READY. Additionally, EXPECT_GT(GetNonce(), 0) was incorrect for a fresh account (genesis nonce = 0).
fix: (1) Added worker thread running io_->run() with executor_work_guard to keep it alive; clean stop/join in TearDown via tm_->Stop() + work_guard_.reset() + io_thread_.join(). (2) Constructed TM with full_node=true so CheckNonce() permits isolated boot. (3) Changed EXPECT_GT(GetNonce(), 0) to EXPECT_EQ(GetNonce(), 0) — genesis nonce for fresh account. (4) Replaced GTEST_SKIP with ASSERT_EQ(READY) with 60s timeout. (5) Added brief poll for SENDING status.
verification: 9/9 tests pass, 0 skipped. ChildRegistrationEndToEnd OK.
files_changed: [SuperGenius/test/src/account/registration_transaction_test.cpp]

