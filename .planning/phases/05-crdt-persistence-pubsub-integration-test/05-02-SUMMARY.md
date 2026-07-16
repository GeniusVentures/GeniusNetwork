---
phase: 05-crdt-persistence-pubsub-integration-test
plan: 02
subsystem: account
tags: [crdt, registration, discovery, pubsub, cid-handler]

# Dependency graph
requires:
  - phase: 05-crdt-persistence-pubsub-integration-test
    plan: 01
    provides: FilterRegistration gate (d), RegisterChild auto-derive overload, SendTransactionItem hardening
provides:
  - RegistrationDiscoveryEntry struct for discovery results
  - GetRegistrationsForMain CRDT scan at TransactionManager layer (RIMPL-06)
  - GetRegistrationsForMain two-layer wrapper at GeniusNode layer (RIMPL-06)
  - RegElementCallback CID notification handler with AddListenTopic follow (RIMPL-05 reception)
  - reg/ RegisterNewElementCallback registration for automatic discovery push
affects: [05-03-integration-test]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "CRDT scan pattern: GetMonitoredNetworkIDs() + GetBlockChainBase(network_id) + QueryKeyValues + DeSerializeTransaction + dynamic_pointer_cast filter"
    - "Two-layer API wrapper: GeniusNode guards TRANSACTIONS_NOT_READY, BOOST_OUTCOME_TRY delegation to TransactionManager"
    - "CID notification handler: RegisterNewElementCallback for reg/ namespace → RegElementCallback → main_address check → AddListenTopic(child_addr)"
    - "Destructor cleanup: UnregisterNewElementCallback + UnregisterElementFilter for reg/ pattern"

key-files:
  created: []
  modified:
    - SuperGenius/src/account/TransactionManager.cpp
    - SuperGenius/src/account/TransactionManager.hpp
    - SuperGenius/src/account/GeniusNode.cpp
    - SuperGenius/src/account/GeniusNode.hpp
    - SuperGenius/test/src/account/registration_transaction_test.cpp

key-decisions:
  - "RegistrationDiscoveryEntry struct at namespace sgns scope follows EscrowDataPair convention"
  - "GetRegistrationsForMain scans via QueryKeyValues (not raw iteration) — matches QueryTransactions analog pattern"
  - "RegElementCallback uses new_data.second (Buffer value) directly with DeSerializeTransaction(Buffer) overload"
  - "CID handler is void-returning callback — silently skips deserialization/cast failures (element already passed FilterRegistration)"
  - "Destructor unregisters both NewElementCallback AND ElementFilter for reg/ pattern — matches tx/ cleanup dual-pattern"

patterns-established:
  - "Pattern 1: CRDT discovery scan — QueryKeyValues + DeSerializeTransaction(Buffer) + RegistrationTransaction cast + main_address filter"
  - "Pattern 2: CID notification handler — RegisterNewElementCallback weak_ptr lambda → void callback → deserialize + match + AddListenTopic"
  - "Pattern 3: Two-layer read API — same TRANSACTIONS_NOT_READY guard and BOOST_OUTCOME_TRY delegation as RegisterChild"

requirements-completed: [RIMPL-05, RIMPL-06]

# Metrics
duration: 13min
completed: 2026-07-16
---

# Phase 05 Plan 02: CRDT Discovery Read Path + CID Notification Handler Summary

**GetRegistrationsForMain CRDT scan with RegistrationDiscoveryEntry struct, GeniusNode two-layer wrapper, and RegElementCallback CID notification handler that auto-follows discovered child channels via AddListenTopic**

## Performance

- **Duration:** 13 min
- **Started:** 2026-07-16T20:20:58Z
- **Completed:** 2026-07-16T20:34:00Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- `RegistrationDiscoveryEntry` struct declared in TransactionManager.hpp with {child_addr, main_addr, sequence, metadata}
- `TransactionManager::GetRegistrationsForMain` scans reg/ CRDT across all monitored networks via QueryKeyValues, deserializes each value, filters by main_address match, returns vector of discovery entries (empty vector when no matches)
- `GeniusNode::GetRegistrationsForMain` two-layer wrapper with TRANSACTIONS_NOT_READY guard and BOOST_OUTCOME_TRY delegation pattern
- `RegisterNewElementCallback` for reg/ namespace registered in TransactionManager::New() — fires on every new reg/ element
- `RegElementCallback` deserializes incoming RegistrationTx, checks `main_address == account_m->GetAddress()`, and calls `globaldb_m->AddListenTopic(child_addr)` to auto-follow (D-49)
- Destructor cleanup unregisters both NewElementCallback and ElementFilter for reg/ pattern

## Task Commits

Each task was committed atomically in the SuperGenius submodule (branch `dev_childwallet`):

1. **Task 1 (RED): RegistrationDiscoveryEntry struct + GetRegistrationsForMain declarations + tests** — `2e105f97` (test)
2. **Task 1 (GREEN): GetRegistrationsForMain CRDT scan implementation** — `f1452540` (feat)
3. **Task 2 (RED): GeniusNode wrapper declaration + RegElementCallback declaration** — `e2451ffb` (test)
4. **Task 2 (GREEN): GeniusNode wrapper implementation + RegElementCallback + callback registration** — `9adfc134` (feat)

## Files Created/Modified
- `SuperGenius/src/account/TransactionManager.hpp` — RegistrationDiscoveryEntry struct at namespace sgns scope; GetRegistrationsForMain doxygen declaration; RegElementCallback doxygen declaration
- `SuperGenius/src/account/TransactionManager.cpp` — GetRegistrationsForMain implementation (QueryKeyValues scan, deserialize, filter, build entries); RegisterNewElementCallback for reg/ namespace in New(); RegElementCallback implementation (main_address match → AddListenTopic); destructor unregister of reg/ patterns
- `SuperGenius/src/account/GeniusNode.hpp` — GetRegistrationsForMain doxygen declaration (two-layer API pattern)
- `SuperGenius/src/account/GeniusNode.cpp` — GetRegistrationsForMain wrapper with TRANSACTIONS_NOT_READY guard and BOOST_OUTCOME_TRY delegation
- `SuperGenius/test/src/account/registration_transaction_test.cpp` — RegistrationE2ETestAccess::GetRegistrationsForMain accessor; 3 test cases (empty-result, returns-matching, filters-by-main-address)

## Decisions Made
- **RegistrationDiscoveryEntry at namespace scope:** Placed after EscrowDataPair per existing struct convention — visible to both TransactionManager and GeniusNode headers without forward-declaration complexity
- **QueryKeyValues over raw iteration:** Matches QueryTransactions() CRDT scan pattern exactly — same error handling (log + continue) and iteration style
- **Buffer overload for DeSerializeTransaction:** The CRDTCallbackManager::NewDataPair provides `pair<string, Buffer>` — RegElementCallback passes `new_data.second` directly to DeSerializeTransaction(Buffer) overload
- **Void callback, no error return:** RegElementCallback silently skips deserialization/cast failures — the element already passed FilterRegistration validation upstream; failures in the callback path indicate transient data issues, not actionable errors
- **Dual unregister in destructor:** Both UnregisterNewElementCallback and UnregisterElementFilter called for reg/ pattern — matches the tx/ cleanup pattern (both callback and filter are unregistered)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None — all tasks completed without blockers. The C++ TDD cycle followed RED (declaration + test accessor commit) → GREEN (implementation commit) pattern, adapted for the compilation-unit constraint where declarations must exist before test code can reference them.

## Known Stubs

None — all implementations are fully wired. The test cases in registration_transaction_test.cpp are written as real GTest cases that exercise the complete flow (TM start → READY wait → RegisterChild → GetRegistrationsForMain → assert). They depend on the test infrastructure that Phase 05-01 established (RegistrationTransactionE2ETest fixture with CRDTFixture + io_context worker thread).

## Next Phase Readiness
- GetRegistrationsForMain provides the discovery read path for Plan 03's integration test (TEST-03: MainDiscoversChild assertion)
- RegElementCallback provides the automatic follow trigger for the CID notification handler — Plan 03's multi-node test can verify that after registration propagation, the main node is subscribed to the child's topic
- RegistrationDiscoveryEntry struct is ready for integration test assertions (checking child_addr, main_addr, sequence, metadata in propagation tests)
- Ready for Plan 03 (multi-node integration test: genesis + main A + child B)

---
*Phase: 05-crdt-persistence-pubsub-integration-test*
*Plan: 02*
*Completed: 2026-07-16*
