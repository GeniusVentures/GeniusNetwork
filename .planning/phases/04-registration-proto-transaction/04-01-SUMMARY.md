---
phase: 04-registration-proto-transaction
plan: 01
subsystem: account
tags: [registration, proto, transaction, serialization, protobuf, gtest]

# Dependency graph
requires:
  - phase: 01-child-identity-registration-protocol
    provides: "RegistrationTx schema design, DAGStruct convention, child-signed-only model (D-04/D-05)"
provides:
  - "RegistrationTx + RegistrationMetadata proto messages in SGTransaction.proto"
  - "registration = 8 oneof arm in Consensus.proto EmbeddedTransaction"
  - "RegistrationTransaction C++ class with factory, FullHash, serialization, deserialization, deserializer registration"
  - "GTest unit test proving round-trip serialization correctness"
affects: ["04-02-transactionmanager-wiring", "05-crdt-registry-pubsub"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Proto3 additive-only message evolution (append after EscrowReleaseTx, fresh field numbers)"
    - "GeniusTransaction subclass with static Register() + inline registered for auto-deserializer registration"
    - "SerializeToEmbeddedTransaction sets oneof arm via *embedded.mutable_registration() = tx_struct"
    - "DeSerializeByteVector returns nullptr on ParseFromArray failure per existing convention"

key-files:
  created:
    - "SuperGenius/src/account/RegistrationTransaction.hpp"
    - "SuperGenius/src/account/RegistrationTransaction.cpp"
    - "SuperGenius/test/src/account/registration_transaction_test.cpp"
  modified:
    - "SuperGenius/src/account/proto/SGTransaction.proto"
    - "SuperGenius/src/blockchain/impl/proto/Consensus.proto"
    - "SuperGenius/src/account/CMakeLists.txt"
    - "SuperGenius/test/src/account/CMakeLists.txt"

key-decisions:
  - "main_address stored as proto bytes field (not string) matching DAGStruct.source_addr convention"
  - "dev_wallet in RegistrationMetadata stored as bytes field matching EscrowTx.dev_addr convention"
  - "GetTopics includes main_address_ in addition to base topics for future pubsub discovery"
  - "All proto changes purely additive — no existing message or field number modified"

patterns-established:
  - "RegistrationTx: dag_struct=1 (DAGStruct), main_address=2 (bytes), sequence=3 (uint64), metadata=4 (RegistrationMetadata)"
  - "RegistrationMetadata: game_id=1 (string), publisher_id=2 (string), dev_wallet=3 (bytes), peers_cut=4 (uint64)"
  - "RegistrationTransaction follows TransferTransaction/MintTransaction subclass pattern exactly"

requirements-completed: [RIMPL-01, RIMPL-02]

# Metrics
duration: 5min
completed: 2026-07-15
---

# Phase 4 Plan 01: Proto Schema + RegistrationTransaction C++ Class with Round-Trip Serialization

**Additive RegistrationTx/RegistrationMetadata proto messages, registration=8 oneof arm, RegistrationTransaction C++ subclass, and passing GTest unit test — proven serialization round-trip from wire bytes through factory to embedded transaction and back.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-07-15T18:59:34Z
- **Completed:** 2026-07-15T19:04:00Z
- **Tasks:** 3
- **Files modified:** 6

## Accomplishments
- SGTransaction.proto extended with two additive messages (RegistrationMetadata + RegistrationTx) — 0 deletions, existing messages untouched
- Consensus.proto EmbeddedTransaction oneof extended with `registration = 8` arm — field 8 verified available (fields 1-7 in use)
- RegistrationTransaction.hpp/.cpp subclass with factory (New → FillHash), serialization (SerializeByteVector, SerializeToEmbeddedTransaction), deserialization (DeSerializeByteVector), deserializer auto-registration (static Register + inline registered)
- 4 GTest cases all pass: RoundTripSerialization, FactoryFillHash, SerializeToEmbeddedTransaction, GetTopics
- Existing tests (token_id_test) continue to pass — no regression

## Task Commits

Each task was committed atomically in the **SuperGenius** submodule:

1. **Task 1: Proto additions** — `ccc95eae` (feat(04-01): add RegistrationTx and RegistrationMetadata proto messages)
2. **Task 2: C++ class** — `555a1167` (feat(04-01): add RegistrationTransaction C++ class)
3. **Task 3: CMake + tests** — `f9756e72` (test(04-01): add RegistrationTransaction to CMakeLists, create unit tests)

## Files Created/Modified

| File | Action | Purpose |
|------|--------|---------|
| `SuperGenius/src/account/proto/SGTransaction.proto` | Modified (+16 lines) | RegistrationMetadata + RegistrationTx messages appended after EscrowReleaseTx |
| `SuperGenius/src/blockchain/impl/proto/Consensus.proto` | Modified (+1 line) | `registration = 8` oneof arm in EmbeddedTransaction |
| `SuperGenius/src/account/RegistrationTransaction.hpp` | Created (130 lines) | Class declaration: New(), serializers, deserializer, accessors, Register() |
| `SuperGenius/src/account/RegistrationTransaction.cpp` | Created (113 lines) | Implementation: constructor, factory, serialization, deserialization, topics |
| `SuperGenius/src/account/CMakeLists.txt` | Modified (+1 line) | RegistrationTransaction.cpp added to GENIUS_NODE_SOURCES |
| `SuperGenius/test/src/account/registration_transaction_test.cpp` | Created (138 lines) | 4 GTest cases: round-trip, factory hash, embedded tx, topics |
| `SuperGenius/test/src/account/CMakeLists.txt` | Modified (+21 lines) | Test target with genius_node_test link + WHOLEARCHIVE |

## Decisions Made
- **main_address as proto bytes**: Followed plan specification — stored as `bytes` type matching DAGStruct.source_addr convention (128-hex public key encoded as proto bytes)
- **dev_wallet as proto bytes**: Followed plan specification — stored as `bytes` matching EscrowTx.dev_addr convention
- **GetTopics includes main_address_**: Extends base GetTopics() (which returns {src_address}) with main_address_ for future Phase 5 pubsub discovery
- **Build in Release config**: Release build directory already configured; Debug directory would require separate CMake configuration. Release mode build and test execution verified correctness

## Deviations from Plan

None — plan executed exactly as written. All 3 tasks completed with the exact files, patterns, and verification steps specified.

## Issues Encountered

None — build succeeded on first attempt, all 4 tests passed on first run.

## Test Results

```
[==========] 4 tests from 1 test suite ran. (0 ms total)
[  PASSED  ] 4 tests.

- RoundTripSerialization:       SerializeByteVector → DeSerializeByteVector preserves all fields
- FactoryFillHash:              New() produces non-empty hash, GetType() = "registration"
- SerializeToEmbeddedTransaction: oneof registration() set with correct values
- GetTopics:                     main_address_ included in topic set
```

## Next Phase Readiness

- RegistrationTx proto schema and RegistrationTransaction C++ class are complete and compile
- Deserializer is registered ("registration") and dispatched through the oneof switch arm
- Ready for Phase 4 Plan 02: TransactionManager wiring (RegisterChild API, FilterRegistration element filter, CRDT path diversion to reg/{child_addr})
- No blockers — proto is additive-only, C++ subclass follows TransferTransaction/MintTransaction patterns exactly

---

*Phase: 04-registration-proto-transaction*
*Completed: 2026-07-15*
