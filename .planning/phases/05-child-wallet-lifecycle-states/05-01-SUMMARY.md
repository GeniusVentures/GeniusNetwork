---
phase: 05-child-wallet-lifecycle-states
plan: 01
subsystem: account/proto
tags: [proto, model, registration, revoke]
dependency-graph:
  requires: []
  provides:
    - "SGTransaction::RegistrationTx.detach_flag (field 5, bool)"
    - "SGTransaction::RegistrationTx.supersedes_sequence (field 6, uint64)"
    - "SGTransaction::RevokeTx (dag_struct=1, child_address=2, registration_sequence=3)"
    - "EmbeddedTransaction.revoke oneof arm 9"
    - "RegistrationTransaction::GetDetachFlag()/GetSupersedesSequence()"
    - "RevokeTransaction class (hpp/cpp)"
  affects:
    - "SuperGenius/src/account/proto/SGTransaction.proto"
    - "SuperGenius/src/blockchain/impl/proto/Consensus.proto"
    - "SuperGenius/src/account/RegistrationTransaction.hpp"
    - "SuperGenius/src/account/RegistrationTransaction.cpp"
    - "SuperGenius/src/account/RevokeTransaction.hpp (new)"
    - "SuperGenius/src/account/RevokeTransaction.cpp (new)"
    - "SuperGenius/src/account/CMakeLists.txt"
tech-stack:
  added: []
  patterns:
    - "Additive-only proto evolution (new fields/oneof arms appended, existing ones untouched)"
    - "Self-registering GeniusTransaction subclass idiom (RegisterDeserializer + static inline bool registered)"
    - "Two-parameter New() factory with trailing defaulted params for backward-compatible signature extension"
key-files:
  created:
    - SuperGenius/src/account/RevokeTransaction.hpp
    - SuperGenius/src/account/RevokeTransaction.cpp
  modified:
    - SuperGenius/src/account/proto/SGTransaction.proto
    - SuperGenius/src/blockchain/impl/proto/Consensus.proto
    - SuperGenius/src/account/RegistrationTransaction.hpp
    - SuperGenius/src/account/RegistrationTransaction.cpp
    - SuperGenius/src/account/CMakeLists.txt
decisions: []
metrics:
  duration: ~45min
  completed: 2026-07-21
status: complete
---

# Phase 5 Plan 1: Proto Schema + Transaction Class Primitives Summary

Extended `RegistrationTx` with `detach_flag`/`supersedes_sequence`, added a new first-class `RevokeTx` proto message and `EmbeddedTransaction` oneof arm 9, plus a new `RevokeTransaction` C++ class mirroring `RegistrationTransaction` field-for-field — all additive, zero behavior change to existing callers.

## What Was Built

**Task 1 — Proto schema evolution:**
- `SGTransaction.proto`: `RegistrationTx` gained `bool detach_flag = 5;` and `uint64 supersedes_sequence = 6;`, appended after the existing 4 fields (unchanged). New top-level `RevokeTx` message added with `DAGStruct dag_struct = 1;`, `bytes child_address = 2;`, `uint64 registration_sequence = 3;`.
- `Consensus.proto`: `EmbeddedTransaction` oneof gained `SGTransaction.RevokeTx revoke = 9;`, appended after `registration = 8` (arms 1-8 unchanged).
- Both `SGTransactionProto` and `ConsensusProto` CMake targets build cleanly with the additive changes.

**Task 2 — RegistrationTransaction extension:**
- Added `GetDetachFlag() const -> bool` and `GetSupersedesSequence() const -> uint64_t` getters.
- Extended `New(...)`'s signature with two trailing parameters defaulted at the declaration site: `bool detach_flag = false, uint64_t supersedes_sequence = 0`.
- Private constructor now takes both new fields (no defaults, since New() is the only call site plus DeSerializeByteVector).
- `SerializeByteVector`/`SerializeToEmbeddedTransaction` now call `set_detach_flag`/`set_supersedes_sequence`; `DeSerializeByteVector` reads both fields off the wire and reconstructs correctly.
- Every pre-existing 4-arg `RegistrationTransaction::New(...)` call site (in `TransactionManager.cpp` and `registration_transaction_test.cpp`) compiles unmodified.

**Task 3 — RevokeTransaction class:**
- New `RevokeTransaction.hpp`/`.cpp`, mirroring `RegistrationTransaction`'s structure: `New(child_address, registration_sequence, dag)` factory, `Serialize`/`DeSerialize` pair, `GetTransactionSpecificPath()`, `GetTopics()` override (adds `child_address_`), private ctor calling `GeniusTransaction("revoke", SetDAGWithType(...))`, self-registering `Register()`/`registered` idiom calling `RegisterDeserializer("revoke", &RevokeTransaction::DeSerializeByteVector)`.
- `SerializeToEmbeddedTransaction()` assigns via `*embedded.mutable_revoke() = tx_struct;`, correctly setting oneof arm `kRevoke`.
- Added `RevokeTransaction.cpp` to `GENIUS_NODE_SOURCES` in `SuperGenius/src/account/CMakeLists.txt`, immediately after `RegistrationTransaction.cpp`.

## Verification Performed

- `cmake --build ... --target SGTransactionProto` and `ConsensusProto` — both succeed.
- `cmake --build ... --target genius_node_test` — succeeds with `RevokeTransaction.cpp` compiled in.
- `cmake --build ... --target registration_transaction_test` — succeeds; all 5 pre-existing `RegistrationTransactionTest.*` cases pass unchanged (`RoundTripSerialization`, `FactoryFillHash`, `SerializeToEmbeddedTransaction`, `GetTopics`, `ChildRegistrationTamperedSignatureRejected` — one more test than the plan's stated 4, added in a prior phase, unaffected by this work).
- `grep` confirms `RegistrationTx` fields 1-4 (`main_address = 2`, `sequence = 3`, `metadata = 4`) and `EmbeddedTransaction`'s `registration = 8` remain unchanged.
- Manual scratch-test verification (added temporarily to `registration_transaction_test.cpp`, run, then reverted via `git checkout --` — not committed, since dedicated test coverage for lifecycle features belongs to Plans 04/05 per the phase's stated test-ownership convention):
  - `RegistrationTransaction::New(..., true, 1)` round-trips `detach_flag=true`/`supersedes_sequence=1` through `SerializeByteVector`/`DeSerializeByteVector`.
  - The 4-arg default-parameter call path still yields `detach_flag=false`/`supersedes_sequence=0`.
  - `RevokeTransaction::New(child_address, 3, dag)` round-trips `child_address`/`registration_sequence` through serialize/deserialize; `GetTopics()` includes `child_address`; `SerializeToEmbeddedTransaction()` sets `embedded.transaction_case() == EmbeddedTransaction::kRevoke`.

## Deviations from Plan

### Auto-fixed Issues

None - plan executed exactly as written.

### Minor Note

The plan's Task 1 `<verify>` automated check expected `grep -c "supersedes_sequence" SGTransaction.proto` to return 2; the actual count is 1 (a single field declaration — there is no second comment-free occurrence in this codebase's proto style). This did not affect the acceptance criteria: the field exists correctly, and all functional/build verification passed. No code change was needed; this is a discrepancy in the plan's verify-script expectation, not a defect.

## Known Stubs

None. All artifacts (`RegistrationTx.detach_flag`/`supersedes_sequence`, `RevokeTx`, `EmbeddedTransaction.revoke`, `RegistrationTransaction::GetDetachFlag()`/`GetSupersedesSequence()`, `RevokeTransaction`) are fully implemented and verified — no placeholders.

## Threat Flags

None. This plan's threat model (T-05-01 tampering on proto parse, T-05-02 wire-compatibility) is already covered: both new deserializers (`RegistrationTransaction::DeSerializeByteVector`, `RevokeTransaction::DeSerializeByteVector`) return `nullptr` on `ParseFromArray` failure, matching every existing deserializer in this file family. No new network endpoints, auth paths, or trust-boundary changes beyond what the threat model already documents.

## Self-Check: PASSED

- FOUND: SuperGenius/src/account/proto/SGTransaction.proto (modified, additive changes present)
- FOUND: SuperGenius/src/blockchain/impl/proto/Consensus.proto (modified, additive changes present)
- FOUND: SuperGenius/src/account/RegistrationTransaction.hpp (modified)
- FOUND: SuperGenius/src/account/RegistrationTransaction.cpp (modified)
- FOUND: SuperGenius/src/account/RevokeTransaction.hpp (created)
- FOUND: SuperGenius/src/account/RevokeTransaction.cpp (created)
- FOUND: SuperGenius/src/account/CMakeLists.txt (modified)
- FOUND: commit ef976116 (Task 1)
- FOUND: commit 20124c60 (Task 2)
- FOUND: commit 09680244 (Task 3)
