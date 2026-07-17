---
phase: 05-crdt-persistence-pubsub-integration-test
plan: 01
subsystem: account
tags: [crdt, registration, filter, sequence-monotonicity, auto-derive]

# Dependency graph
requires:
  - phase: 04-registration-proto-transaction
    provides: RegistrationTx proto, RegistrationTransaction class, FilterRegistration gates a-c, SendTransactionItem reg/ diversion
provides:
  - FilterRegistration gate (d) — sequence monotonicity + zero-sequence well-formed check
  - RegisterChild 2-arg auto-derive overload (TM + GeniusNode layers)
  - SendTransactionItem reg/ path hardening (null-check + serialization error handling)
affects: [05-02-pubsub-discovery, 05-03-integration-test]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Gate (d) CRDT read during element filter: globaldb_m->Get(reg_key) + DeSerializeTransaction + dynamic_pointer_cast + compare"
    - "Two-arg overload delegation pattern: auto-derive overload reads CRDT, computes sequence, delegates to 3-arg variant"
    - "SendTransactionItem error pattern: early return outcome::failure(invalid_argument) for null-cast and empty-serialization"

key-files:
  created: []
  modified:
    - SuperGenius/src/account/TransactionManager.cpp
    - SuperGenius/src/account/TransactionManager.hpp
    - SuperGenius/src/account/GeniusNode.cpp
    - SuperGenius/src/account/GeniusNode.hpp
    - SuperGenius/test/src/account/registration_transaction_test.cpp

key-decisions:
  - "Gate (d) reads stored record via direct CRDT Get inside FilterRegistration (no in-memory cache) per D-46"
  - "2-arg overload chosen for RegisterChild auto-derive (vs std::optional) — matches existing codebase overloading convention per D-47"
  - "Graceful skip on corrupt stored CRDT record — gate (d) accepts when deserialization fails (defense-in-depth, not a security escape)"

patterns-established:
  - "Pattern 1: CRDT element filter sequence gate — Get + DeSerialize + dynamic_pointer_cast + compare"
  - "Pattern 2: Two-layer API convention extended — RegisterChild auto-derive at both TM and GeniusNode"
  - "Pattern 3: SendTransactionItem hardening — null-check after dynamic_pointer_cast, non-empty check on SerializeByteVector"

requirements-completed: [RIMPL-04, RIMPL-07]

# Metrics
duration: 11min
completed: 2026-07-16
---

# Phase 05 Plan 01: FilterRegistration Gate (d) + RegisterChild Auto-Derive Summary

**FilterRegistration sequence monotonicity gate, RegisterChild auto-derive overload, and Phase 4 advisory fixes in the SendTransactionItem reg/ diversion path**

## Performance

- **Duration:** 11 min
- **Started:** 2026-07-16T19:59:24Z
- **Completed:** 2026-07-16T20:09:55Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments
- Gate (d) sequence monotonicity implemented in FilterRegistration — rejects zero sequences and non-monotonic (incoming <= stored) registrations per D-46
- RegisterChild 2-arg auto-derive overload at both TransactionManager and GeniusNode layers — reads stored reg/ record from CRDT and uses sequence+1 (or 1 for first registration) per D-47
- SendTransactionItem reg/ path hardened with null-check after dynamic_pointer_cast and explicit non-empty check on SerializeByteVector output (Phase 4 advisory fixes)

## Task Commits

Each task was committed atomically in the SuperGenius submodule (branch `dev_childwallet`):

1. **Task 1 (RED): Gate (d) failing tests** — `83d4d7c7` (test)
2. **Task 1 (GREEN): Gate (d) implementation** — `2810e1c4` (feat)
3. **Task 2 (RED): RegisterChild auto-derive failing tests + declarations** — `d3c71f61` (test)
4. **Task 2 (GREEN): RegisterChild auto-derive implementation** — `b036b122` (feat)
5. **Task 3: Phase 4 advisory fixes** — `a4f8efc2` (fix)

## Files Created/Modified
- `SuperGenius/src/account/TransactionManager.cpp` — Gate (d) in FilterRegistration (sequence==0 + non-monotonic rejection); 2-arg RegisterChild auto-derive overload; SendTransactionItem null-check + serialization error handling
- `SuperGenius/src/account/TransactionManager.hpp` — 2-arg RegisterChild doxygen declaration; FilterRegistration gate (d) doxygen update
- `SuperGenius/src/account/GeniusNode.cpp` — 2-arg RegisterChild wrapper (two-layer pattern)
- `SuperGenius/src/account/GeniusNode.hpp` — 2-arg RegisterChild wrapper doxygen declaration
- `SuperGenius/test/src/account/registration_transaction_test.cpp` — Gate (d) tests (zero-seq, non-monotonic, higher-seq) and auto-derive tests (first-reg, increment-from-stored, preserve-caller-seq)

## Decisions Made
- **Gate (d) CRDT read:** Uses direct `globaldb_m->Get(reg_key)` inside FilterRegistration — no in-memory cache, always consistent with CRDT merge state per D-46
- **Auto-derive shape:** 2-arg overload (not `std::optional<uint64_t>`) — matches existing TransferFunds/RegisterChild overloading convention per planner discretion (D-47)
- **Graceful CRDT read failure:** If stored reg/ record fails deserialization, gate (d) skips the sequence check and accepts — defense-in-depth, not a security bypass (the element still passes gates a-c)
- **Advisory fix error codes:** Both SendTransactionItem fixes return `boost::system::errc::invalid_argument` via `make_error_code` — matches the existing early-return pattern at lines 1210-1212

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None — all tasks completed without blockers. The C++ TDD cycle for tasks 1 and 2 followed RED (test+declaration commit) → GREEN (implementation commit) pattern adapted for the compilation-unit constraint (C++ requires declarations to exist before test code can reference them).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Gate (d) completes the FilterRegistration element filter (all four gates a-d per D-46)
- RegisterChild auto-derive removes caller burden of tracking sequences per D-47
- SendTransactionItem reg/ path is hardened against two Phase 4 advisory warnings
- Ready for Plan 02 (pubsub CID-notification handler + GetRegistrationsForMain discovery read path) and Plan 03 (multi-node integration test)

---
*Phase: 05-crdt-persistence-pubsub-integration-test*
*Completed: 2026-07-16*
