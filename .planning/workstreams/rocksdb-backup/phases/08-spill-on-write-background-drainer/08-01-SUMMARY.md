---
phase: 08-spill-on-write-background-drainer
plan: 01
subsystem: database
tags: [sgns-blockstore, crdt, cold-storage, decorator, rocksdb, spill-journal]

requires:
  - phase: 07-supergenius-build-wiring-config-gate
    provides: SGNS_COLD_STORAGE option + find_package chain, strict ColdStorageOptions parser, Tier-1 fail-closed lane
provides:
  - Gated cold-storage stack factory (ColdStorageStack.hpp/.cpp/Stub.cpp) with loud OFF-build failure
  - BlockStoreBackedIpfsDatastore journal-spill decorator wired at the GlobalDB::New IpfsDatastore seam
  - ColdStorageBundle (data_store/manager/cold_store_mutex) the manager of 08-02 fills
  - First production link of sgns-blockstore into crdt_globaldb (SGNS_COLD_STORAGE=ON)
  - Hermetic Tier-1 spill journal suite (cold_storage_spill_test, 5 cases)
affects: [08-02, 08-03, 09-cold-read-fallback, 10-flush-gated-durability, 11-retention-gc]

actuals:
  tokens: 31000
  tasks: 2
  commits: 2

tech-stack:
  added: []  # no new external dependencies - sgns-blockstore linked, not added
  patterns:
    - gated factory/stub split (SKIP_UNITY_BUILD_INCLUSION for same-symbol TUs)
    - journal-first IpfsDatastore decorator at the single construction seam

key-files:
  created:
    - SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp
    - SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp
    - SuperGenius/src/crdt/globaldb/ColdStorageStackStub.cpp
    - SuperGenius/src/crdt/globaldb/BlockStoreBackedIpfsDatastore.hpp
    - SuperGenius/src/crdt/globaldb/BlockStoreBackedIpfsDatastore.cpp
    - SuperGenius/test/src/crdt/cold_storage_spill_test.cpp
  modified:
    - SuperGenius/src/crdt/globaldb/CMakeLists.txt
    - SuperGenius/src/crdt/globaldb/globaldb.hpp
    - SuperGenius/src/crdt/globaldb/globaldb.cpp
    - SuperGenius/test/src/crdt/CMakeLists.txt

key-decisions:
  - "Cold-store directory is the coldstore sibling under the database path - never inside backups (M3 D-09)"
  - "Decorator constructor takes the logger; factory passes a ColdStorage-named logger (rate-limited journal-failure lines carry BlockStatus codes only)"
  - "Unity-build collision between the real TU and the stub resolved with SKIP_UNITY_BUILD_INCLUSION on the three cold-storage TUs (plan-authorized response)"

patterns-established:
  - "Gated factory/stub: always-compiled header with zero library types + two .cpp variants selected by SGNS_COLD_STORAGE"
  - "Decorator forward-shape: journal-first set(), pure forwards for get/contains/seal/is_sealed, remove hot-only"

requirements-completed: [SPILL-01]

coverage:
  - id: D1
    description: "Gated cold-storage stack + journal-spill decorator wired at the GlobalDB::New seam; both build configurations link (OFF stub pristine, ON links sgns-blockstore)"
    requirement: SPILL-01
    verification:
      - kind: integration
        ref: "cmake --build SuperGenius/build/Windows/Debug --config Debug --target crdt_globaldb genius_node (OFF and ON passes, exit 0)"
        status: pass
      - kind: unit
        ref: "SuperGenius ctest cold_storage_link_proof_test + cold_storage_config_gate_test (100% passed, 2 tests)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Hermetic Tier-1 journal-contract suite: journal-write spills every put, re-put idempotency, remove hot-only, loud journal failure on hostile CID, zero-length block"
    requirement: SPILL-01
    verification:
      - kind: unit
        ref: "SuperGenius ctest cold_storage_spill_test (5 TESTs, Passed 1.61s first run)"
        status: pass
      - kind: unit
        ref: "SuperGenius ctest -L Tier1 --no-tests=error (3/3 passed; registration-vs-label parity 3==3)"
        status: pass
    human_judgment: false

duration: 70min
completed: 2026-10-24
status: complete
---

# Phase 8 Plan 01: Spill-on-Write Journal Half Summary

**Gated cold-storage stack + journal-first IpfsDatastore decorator at the single GlobalDB::New construction seam - every block Put spills to the durable local journal with zero remote I/O, proven by five hermetic Tier-1 tests.**

## Performance

- **Duration:** ~70 min
- **Completed:** 2026-10-24 (UTC)
- **Tasks:** 2
- **Files modified:** 10 (6 created, 4 modified)

## Accomplishments
- Factory/stub split keeps default SGNS_COLD_STORAGE=OFF builds pristine (stub links zero sgns-blockstore symbols) while an enabled config on an OFF build fails loudly with the exact rebuild message; the ON tree now links sgns-blockstore::sgns-blockstore into crdt_globaldb for the first time in production
- BlockStoreBackedIpfsDatastore journals block bytes + PendingUpload record as one atomic sync RocksDB WriteBatch BEFORE the inner hot write (D-04), under the shared cold-store mutex, with a defensive std::invalid_argument catch so a hostile out-of-set-multihash CID yields a loud failure instead of node termination
- GlobalDB::New hands the decorator (not the inner store) to GraphsyncDAGSyncer only when cold_storage_options_.enabled - the disabled path stays byte-identical; new Error::COLD_STORAGE_INIT_FAILED surfaces factory failures loudly
- Five journal-contract TESTs green in the fail-closed Tier-1 lane on the reconfigured ON tree

## Task Commits

1. **Task 1: Gated cold-storage stack (factory/stub) + journal-spill decorator wired at the GlobalDB::New seam** - `f26f97e56` (feat)
2. **Task 2: Hermetic Tier-1 spill journal tests** - `ff05a89e0` (test)

## Files Created/Modified
- `SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp` - always-compiled factory declaration, ColdStorageStatus/Watermark/Bundle, four lifecycle bridges (zero sgns-blockstore includes - hygiene gate CLEAN)
- `SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp` - real assembly: coldstore sibling dir, LocalBlockStore::Open, OpenMinioS3Client (eager validation, zero network I/O), S3BlockStore::Open (v1/blocks), decorator wrap
- `SuperGenius/src/crdt/globaldb/ColdStorageStackStub.cpp` - OFF-build stub: loud SGNS_COLD_STORAGE failure for enabled config, pure passthrough bundle for disabled
- `SuperGenius/src/crdt/globaldb/BlockStoreBackedIpfsDatastore.hpp/.cpp` - journal-first decorator (six IpfsDatastore virtuals; remove hot-only; rate-limited failure logging)
- `SuperGenius/src/crdt/globaldb/globaldb.hpp` - ColdStorageManager forward declaration, cold bundle members (declaration order preserves Pitfall-5 teardown), Error::COLD_STORAGE_INIT_FAILED
- `SuperGenius/src/crdt/globaldb/globaldb.cpp` - seam wiring: OpenColdStorageStack only inside the enabled branch; decorator to GraphsyncDAGSyncer
- `SuperGenius/src/crdt/globaldb/CMakeLists.txt` - unconditional stub + gated real TUs/link, SKIP_UNITY_BUILD_INCLUSION
- `SuperGenius/test/src/crdt/cold_storage_spill_test.cpp` + `SuperGenius/test/src/crdt/CMakeLists.txt` - five-case suite, gated registration, Tier1 label, fake include-dir workaround

## Decisions Made
- Decorator failure mapping returns IpfsDatastoreError::UNKNOWN (the enum carries only NOT_FOUND/UNKNOWN) per the plan; the BlockStatus code rides the rate-limited log line
- Out-of-set multihash fixture uses blake2s-256 (HashType::blake2s256) - the vendored libp2p HashType set carries no sha3 member; blake2s-256 is equally outside the library's accepted set (plan named sha3-512 as an example)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Build] UNITY_BUILD collision between the gated TU and the stub**
- **Found during:** Task 1 (ON-build verify)
- **Issue:** ColdStorageStack.cpp and ColdStorageStackStub.cpp merged into one unity blob - duplicate function bodies (C2084)
- **Fix:** set_source_files_properties(... SKIP_UNITY_BUILD_INCLUSION ON) for the three cold-storage TUs - the exact response the plan pre-authorized
- **Files modified:** SuperGenius/src/crdt/globaldb/CMakeLists.txt
- **Verification:** ON build exit 0, no error C/LNK
- **Committed in:** f26f97e56

**2. [Rule 2 - Environment] Plan's literal reconfigure command lacked -S**
- **Found during:** Task 1 (verify step 2)
- **Issue:** this repo has no root CMakeLists; the build entry point is SuperGenius/build/Windows (CMAKE_HOME_DIRECTORY in the cache)
- **Fix:** cmake -S SuperGenius/build/Windows -B SuperGenius/build/Windows/Debug -DSGNS_COLD_STORAGE=ON
- **Verification:** configure exit 0, "sgns-blockstore found via" status line
- **Committed in:** n/a (command-line only)

**Total deviations:** 2 auto-fixed (1 build, 1 environment)
**Impact on plan:** None - both were pre-anticipated by the plan text or purely local command-shape adjustments.

## Issues Encountered
None beyond the deviations above. Intermediate MSVC type-resolution errors (shared_ptr downcast via auto, IPFS outcome namespace qualification, Buffer gsl::span constructor, Version::V1 enum casing) were routine implementation corrections inside the task commits.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Tree reconfigured SGNS_COLD_STORAGE=ON and Tier-1 lane green (3/3) - the working state for 08-02
- ColdStorageBundle.manager is null with null-safe bridges - 08-02 constructs ColdStorageManager and fills the factory + bridges
- The shared cold_store_mutex instance owned by the bundle is the one the 08-02 manager must lock

---
*Phase: 08-spill-on-write-background-drainer*
*Completed: 2026-10-24*
