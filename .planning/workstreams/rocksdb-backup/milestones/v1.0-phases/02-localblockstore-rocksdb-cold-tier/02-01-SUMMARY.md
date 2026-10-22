---
phase: 02-localblockstore-rocksdb-cold-tier
plan: 01
subsystem: database
tags: [rocksdb, blockstore, wal, durability, write-batch, restart-recovery]

# Dependency graph
requires:
  - phase: 01-blockstore-contract-memory-backend-conformance-kit
    provides: frozen BlockStore/FaultController/BlockStoreTooling contract, result<R,BlockStatus> policy::terminate alias, conformance kit
provides:
  - LocalBlockStore durable backend (own RocksDB instance, pimpl, zero rocksdb in installed headers)
  - One-atomic-WriteBatch Put: block bytes + conditional PendingUpload journal record, WriteOptions::sync=true
  - BlockStoreTooling::GetPendingUploads pure virtual (D-05 additive) + LocalBlockStore::ForEach implementation
  - Build wiring: no-version find_package(RocksDB CONFIG), RocksDB::rocksdb PUBLIC link, superbuild DEPENDS libp2p rocksdb + RocksDB_DIR/Snappy_DIR, package-config find_dependency
  - Restart-durability proof: close-without-flush + reopen (WAL replay) recovers blocks AND journal
affects: [02-localblockstore-rocksdb-cold-tier, 03-minio-cpp-integration-s3client-adapter, 04-s3blockstore-sia-s3d-roundtrip]

actuals:
  tokens: 12000
  tasks: 2
  commits: 3

tech-stack:
  added: [RocksDB::rocksdb (9.4 pinned in-tree, static, consumed via CONFIG package - no new external fetch)]
  patterns: [pimpl backend over RocksDB (Pattern 1), one-mutation-one-batch + teardown discipline (Pattern 3), factory Open + explicit idempotent Close (Pattern 4)]

key-files:
  created:
    - thirdparty/sgns-blockstore/include/sgns-blockstore/LocalBlockStore.hpp
    - thirdparty/sgns-blockstore/src/LocalBlockStore.cpp
    - thirdparty/sgns-blockstore/test/local_block_store_test.cpp
  modified:
    - thirdparty/sgns-blockstore/include/sgns-blockstore/BlockStoreTooling.hpp
    - thirdparty/sgns-blockstore/CMakeLists.txt
    - thirdparty/sgns-blockstore/src/CMakeLists.txt
    - thirdparty/sgns-blockstore/cmake/config.cmake.in
    - thirdparty/sgns-blockstore/test/CMakeLists.txt
    - thirdparty/sgns-blockstore/test/api_hygiene_test.cpp
    - thirdparty/build/CommonTargets.cmake

key-decisions:
  - "Default CF addressed via default-constructed ColumnFamilyDescriptor (this RocksDB tree exposes GetDefaultColumnFamilyName(), not kDefaultColumnFamilyName)"
  - "ForEach implemented on LocalBlockStore even though no plan listed it: BlockStoreTooling::ForEach is a frozen pure virtual, so the triple-inheritance class cannot instantiate without it (plan defect, Rule 2 auto-fix)"
  - "Conservative journal decode: unknown version/state bytes decode to PendingUpload so a mangled record is re-uploaded, never silently acknowledged (T-02-03)"

patterns-established:
  - "One-WriteBatch mutation: block bytes + conditional journal record commit atomically via DB::Write(sync=true) - the WAL IS BACK-03's (temp + fsync + rename)"
  - "Close sequence releases the Windows LOCK: destroy CF handles (never default) -> Close() -> delete db_; same-process reopen works"

requirements-completed: [BACK-03, BACK-04]

coverage:
  - id: D1
    description: "Durable LocalBlockStore slice: own RocksDB instance/directory, one-batch Put+journal, WAL-replay restart proof, all build wiring"
    requirement: BACK-03
    verification:
      - kind: unit
        ref: "test/local_block_store_test.cpp#RestartDurabilityPreservesBlocksAndJournal"
        status: pass
      - kind: unit
        ref: "test/local_block_store_test.cpp#PutGetRoundTrip"
        status: pass
      - kind: command
        ref: "git grep rocksdb include/ (pimpl negative gate) + no-version find_package grep + CommonTargets shape checks"
        status: pass
    human_judgment: false
  - id: D2
    description: "Kit-ready fault seam: Unavailable/Unauthorized gate before storage, CorruptData corrupts returned copy only, non-sticky"
    requirement: BACK-03
    verification:
      - kind: unit
        ref: "test/local_block_store_test.cpp#FaultUnavailableSurfacesTemporarilyUnavailableBeforeStorage / #FaultUnauthorizedSurfacesUnauthorized / #FaultCorruptDataCorruptsReturnedCopyNotStorage"
        status: pass
    human_judgment: false
  - id: D3
    description: "Standalone-header hygiene: api_hygiene include-everything TU covers LocalBlockStore.hpp with zero consumer-side RocksDB exposure"
    requirement: BACK-03
    verification:
      - kind: unit
        ref: "test/api_hygiene_test.cpp#HygieneShell (eleven public headers, links exactly sgns-blockstore + p2p::p2p_cid)"
        status: pass
      - kind: command
        ref: "ctest header_hygiene (banned-include gate)"
        status: pass
    human_judgment: false
---

# Phase 02 Plan 01: LocalBlockStore Durable Slice Summary

**One-liner:** Durable RocksDB cold-tier backend where one atomic WriteBatch (block bytes + day-one PendingUpload journal record, sync=true) survives close-without-flush and replays from the WAL on reopen - byte-identical, CID-verified, journal enumerable.

Duration: ~35 min | Tasks: 2 | Files: 10 | Commits: sgns-blockstore `b12ffd3` + `95c19ee`, thirdparty `9657d06`

## Accomplishments

- **Durable slice (Task 1, tracer):** `LocalBlockStore` opens its OWN RocksDB instance in a consumer-provided directory (CF-vector DB::Open, create-if-missing both directions, avoid_flush_during_shutdown=true, info_log_level=ERROR_LEVEL); every Put commits ONE WriteBatch carrying block bytes (blocks CF) and - only for new blocks - the PendingUpload journal record (upload_journal CF) via WriteOptions::sync=true; read-before-write computes alreadyPresent so a re-Put never regresses journal state (Pitfall 6). The tracer crown `RestartDurabilityPreservesBlocksAndJournal` proves close-without-flush + reopen recovers both blocks byte-identical/CID-verified and the exact two-CID pending set through `GetPendingUploads()`.
- **Build wiring landed atomically with the slice:** no-version `find_package(RocksDB CONFIG REQUIRED)` (SameMajorVersion dual-compat), `RocksDB::rocksdb` PUBLIC on the library link line, `find_dependency(RocksDB CONFIG)` in the package config, superbuild entry gains `DEPENDS libp2p rocksdb` + `RocksDB_DIR`/`Snappy_DIR` cache args (TESTING:BOOL=ON still last).
- **Frozen-header additive change (D-05):** `BlockStoreTooling::GetPendingUploads()` pure virtual with the ordering-contract docstring; LocalBlockStore is the named v1 implementer.
- **Fault seam kit-ready (Task 2):** Unavailable/Unauthorized fail their taxonomy classes with BlockSource::Local BEFORE any RocksDB access; CorruptData flips a byte on the returned copy only - cleared fault returns ORIGINAL bytes, nothing evicted (non-sticky), journal untouched.
- **Hygiene proof extended:** api_hygiene include-everything TU now covers all eleven public headers and still links exactly sgns-blockstore + p2p::p2p_cid - the pimpl kept installed headers standalone-compilable; RocksDB resolves transitively through the package config.

## Task Execution Table

| Task | Name | Result | Commit |
|------|------|--------|--------|
| 1 | LocalBlockStore durable slice + all build wiring | Done - all gates green | b12ffd3 / 9657d06 |
| 2 | Kit-ready fault seam + standalone-header hygiene | Done - 3/3 ctest targets pass | 95c19ee |

## Deviations from Plan

**[Rule 1 - API mismatch] libp2p codec decode name** — Found during: Task 1 build. RESEARCH code examples used `ContentIdentifierCodec::fromBytes`; this tree's libp2p exposes `decode(gsl::span<const uint8_t>)` (content_identifier_codec.hpp). Fix: used `decode` in GetPendingUploads and ForEach. Files: src/LocalBlockStore.cpp. Verification: full ctest green. Commit: b12ffd3.

**[Rule 1 - API mismatch] rocksdb::kDefaultColumnFamilyName absent** — Found during: Task 1 build. This RocksDB 9.4 tree's public headers expose `GetDefaultColumnFamilyName()` (db.h:68) and the default-constructed `ColumnFamilyDescriptor` names the default CF via it (db.h:74), not the upstream constant. Fix: `rocksdb::ColumnFamilyDescriptor{}` for the default CF descriptor entry. Files: src/LocalBlockStore.cpp. Verification: compile + restart test green. Commit: b12ffd3.

**[Rule 2 - missing critical piece] ForEach unlisted in plan's method set** — Found during: Task 1 build (C2259 abstract class). LocalBlockStore triple-inherits BlockStoreTooling whose `ForEach` is a frozen Phase-1 pure virtual; no plan in the phase lists a ForEach implementation, so the class cannot instantiate. Fix: implemented `ForEach` override (blocks-CF snapshot scan, BytewiseComparator order = frozen ordering contract, fault gate first, undecodable keys skipped) and declared it beside GetPendingUploads. Files: LocalBlockStore.hpp/.cpp. Verification: class concrete, ctest green; not touching any frozen header. Commit: b12ffd3.

**Total deviations:** 3 auto-fixed (2 API mismatches, 1 plan omission). **Impact:** none on architecture - all additive within plan intent; ForEach now has a tested v1 implementer one plan early.

## Issues Encountered

None.

## Next Phase Readiness

Plan 02-02 builds directly on this slice: journal transition methods (MarkUploadedAccepted/MarkUploadedDurable/GetUploadState), unconditional EvictLocal, re-Put no-regression proof, and the Phase-1 conformance kit instantiation - breadth only, no architecture change.
