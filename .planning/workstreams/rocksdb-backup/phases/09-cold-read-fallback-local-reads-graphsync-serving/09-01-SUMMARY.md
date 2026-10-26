---
phase: 09-cold-read-fallback-local-reads-graphsync-serving
plan: 01
subsystem: database
tags: [cold-storage, blockstore, ipfs, graphsync, crdt, s3, read-fallback]

requires:
  - phase: 08-spill-on-write-background-drainer
    provides: BlockStoreBackedIpfsDatastore decorator (rehydrate write path), ColdStorageStack factory/bundle, ColdStorageManager drainer, shared cold_store_mutex_ discipline
provides:
  - Ungated ColdReadFallback hook interface (cold_read_fallback.hpp) with the ColdReadStatus seam taxonomy and MapColdReadStatus mapping
  - Gated ColdReadService implementing the D-01/D-02 chain (LocalBlockStore -> S3BlockStore, CID-verified, D-04 rehydrate bytes-only)
  - GraphsyncDAGSyncer Error values COLD_STORAGE_TEMPORARILY_UNAVAILABLE / _CORRUPT / _UNAUTHORIZED (+ category cases)
  - FetchNodeFromColdStorage helper wired into GetNodeWithoutRequest and getNode (cold-before-peers, D-01) with D-03 cold-precedence at failure returns
  - HasBlock gated local-only cold-dir presence check (D-08/D-09)
  - Shared remote_store_mutex_ serializing chain S3 Gets against drainer S3 Puts
  - Tier-1 cold_storage_fallback_test (happy-path e2e, null-hook no-op, taxonomy matrix, exhaustive 4x2 mapping)
affects: [10-flush-gated-durability, 11-retention-gc, 12-integration-hardening, cold-read-responder-serve-09-02, fault-injection-suite-09-03]

actuals:
  tokens: 23000
  tasks: 3
  commits: 4

tech-stack:
  added: []
  patterns:
    - Ungated-hook/gated-impl injection at the single DAGSyncer construction site (mirror of the Phase-8 bridge discipline)
    - Cold-precedence error aggregation over not-found-shaped peer terminals (D-03)

key-files:
  created:
    - SuperGenius/src/crdt/cold_read_fallback.hpp
    - SuperGenius/src/crdt/globaldb/ColdReadService.hpp
    - SuperGenius/src/crdt/globaldb/ColdReadService.cpp
    - SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp
  modified:
    - SuperGenius/src/crdt/graphsync_dagsyncer.hpp
    - SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp
    - SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp
    - SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp
    - SuperGenius/src/crdt/globaldb/ColdStorageStackStub.cpp
    - SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp
    - SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp
    - SuperGenius/src/crdt/globaldb/globaldb.hpp
    - SuperGenius/src/crdt/globaldb/globaldb.cpp
    - SuperGenius/src/crdt/globaldb/CMakeLists.txt
    - SuperGenius/test/src/crdt/CMakeLists.txt
    - SuperGenius/test/src/crdt/cold_storage_spill_test.cpp

key-decisions:
  - "Hook-level success signal is the non-empty out buffer: ColdReadStatus mirrors only the library's failure taxonomy (per plan letter); DAG blocks are never empty, so Get's success/failure discriminator is documented in the header contract"
  - "D-03 cold-precedence fires on the not-found-shaped peer terminals {CID_NOT_FOUND, ROUTE_NOT_FOUND} - the behavior spec requires COLD_STORAGE_TEMPORARILY_UNAVAILABLE to surface with s3d down AND no peer route (a cold NotFound never overrides anything)"
  - "Within the chain, a remembered non-NotFound Local-tier classification outranks a Remote-tier NotFound (a non-authoritative tier can never license a definitive-absence claim - SC1 envelope rule)"
  - "EnqueueRewarm is a real try-op returning false until 09-02 lands the bounded executor (documented in the @note)"

patterns-established:
  - "Cold-read hook seam: ungated interface header + gated final service up-cast in the bundle - no library type crosses the boundary (Phase-7/8 discipline extended to the read path)"
  - "Precedence aggregation helper (ApplyColdPrecedence) at the DAGSyncer's not-found-shaped failure returns"

requirements-completed: [READ-01]

coverage:
  - id: D1
    description: "End-to-end cold read chain: hot miss resolves LocalBlockStore -> S3BlockStore with CID verification and re-caches through the decorator set() before returning (D-01/D-02/D-04)"
    requirement: READ-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#LocalTierHitEndToEnd"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#S3TierHitEndToEnd"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#LocalTierHitPerformsZeroS3Gets"
        status: pass
    human_judgment: false
  - id: D2
    description: "Honest taxonomy at the seam: four-class classification with tier attribution, no transport-shaped NotFound escape (SC1), Corrupt source attribution (SC3), exhaustive MapColdReadStatus table"
    requirement: READ-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#S3UnavailableNeverSurfacesAsNotFound"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#DefinitiveAbsenceClassifiesNotFound"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#RemoteCorruptionAttributesToRemoteTier"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#LocalCorruptionAttributesToLocalTier"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#MapColdReadStatusExhaustiveTable"
        status: pass
    human_judgment: false
  - id: D3
    description: "Rehydrate silence: bytes-only writes (exactly one set, zero seal/marker writes, no pubsub/routing) and HasLocalCold bool contract under injected fault (SC4/D-08)"
    requirement: READ-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#HasLocalColdBoolContractUnderFault"
        status: pass
    human_judgment: false
  - id: D4
    description: "DAGSyncer read-path wiring without regression: GetNodeWithoutRequest/getNode cold legs, null-hook disabled bar byte-identical, existing read paths green"
    requirement: READ-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#NullHookNoOpReturnsHotErrorUnchanged"
        status: pass
      - kind: integration
        ref: "ctest -R 'crdt_test|globaldb_integration_test|cold_storage_config_gate_test' (all passed post-wiring)"
        status: pass
      - kind: integration
        ref: "ctest -L Tier1 --no-tests=error (4/4 passed, fail-closed lane)"
        status: pass
    human_judgment: false

duration: 75min
completed: 2026-10-26
status: complete
---

# Phase 9 Plan 01: Cold Read Fallback Tracer Summary

**Hot-store misses now resolve through the CID-verifying Local->S3 cold chain with an honest four-class taxonomy at the GraphsyncDAGSyncer seam, re-caching bytes through the Phase-8 decorator before returning.**

## Performance

- **Duration:** 75 min
- **Started:** 2026-10-26T21:30Z (approx)
- **Completed:** 2026-10-26T22:45Z (approx)
- **Tasks:** 3/3
- **Files modified:** 17 (4 created, 13 modified)

## Accomplishments
- End-to-end cold read tracer: a journal-only (Local-tier) block and an S3-only block both resolve through the chain and are served from the hot store after a decorator-set re-cache (D-01/D-02/D-04) - proven with zero S3 Gets on a Local hit
- Honest taxonomy: three new Error values with category cases; SC1 no-NotFound-escape under scripted s3d Unavailable; SC3 Corrupt attribution per tier; exhaustive 4x2 MapColdReadStatus table
- getNode gained the cold-before-peers leg with D-03 cold-precedence (Corrupt > Unauthorized > TemporarilyUnavailable over not-found-shaped peer terminals); HasBlock gained the gated local-only cold-dir check (D-08/D-09)
- remote_store_mutex_ now serializes chain S3 Gets against drainer S3 Puts (MinioS3Client single-threaded-use contract)

## Task Commits

Each task was committed atomically (SuperGenius submodule, branch dev_blockstore):

1. **Task 1: hook interface + gated chain + DAGSyncer injection + happy-path tests** - `76e813710` (feat) + `157d7e1ce` (test)
2. **Task 2: getNode pre-peer leg (D-01) + D-03 precedence + HasBlock (D-08/D-09)** - `f9236a5c4` (feat)
3. **Task 3: taxonomy breadth at the hook seam** - `1a6fd18ea` (test)

**Plan metadata:** (docs commit follows)

## Files Created/Modified
- `SuperGenius/src/crdt/cold_read_fallback.hpp` - ungated hook interface: ColdReadStatus, ColdReadFallback (Get/HasLocalCold/EnqueueRewarm/Rehydrate), MapColdReadStatus
- `SuperGenius/src/crdt/globaldb/ColdReadService.hpp/.cpp` - gated chain service (D-01/D-02 chain, D-04 rehydrate, D-08 HasLocalCold, rate-limited+counted failure logging)
- `SuperGenius/src/crdt/graphsync_dagsyncer.hpp` / `impl/graphsync_dagsyncer.cpp` - +3 Error values with cases, trailing hook ctor param, FetchNodeFromColdStorage helper, GetNodeWithoutRequest/getNode cold legs, D-03 precedence helper, HasBlock third check
- `SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp/.cpp` + `ColdStorageStackStub.cpp` - bundle gains remote_store_mutex/cold_read_service/cold_read_hook; factory constructs the service; stub nulls the new fields (ODR twin intact)
- `SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp/.cpp` - ctor takes the shared remote-store mutex; per-Put-item lock scope in the drainer remote phase
- `SuperGenius/src/crdt/globaldb/globaldb.hpp/.cpp` - cold_read_service_ member (fwd-declared); hook injected at the single make_shared site only inside the enabled block
- `SuperGenius/src/crdt/globaldb/CMakeLists.txt` - ColdReadService.cpp in the gated TU list + SKIP_UNITY_BUILD_INCLUSION
- `SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp` + `test/src/crdt/CMakeLists.txt` - Tier-1 suite + registration (gated, fake include dir, set_tests_properties LABELS)
- `SuperGenius/test/src/crdt/cold_storage_spill_test.cpp` - MakeManager updated for the new manager ctor parameter (compile ripple)

## Decisions Made
- Success discriminator for `ColdReadFallback::Get` is the non-empty out buffer (the struct stays exactly as planned - a failure-taxonomy mirror with no found flag); documented in the header @return
- D-03 precedence applies to both CID_NOT_FOUND and ROUTE_NOT_FOUND peer terminals (the no-peer-route case must still surface COLD_STORAGE_TEMPORARILY_UNAVAILABLE per the behavior spec); TIMED_OUT / PEER_BLACKLISTED / DAGSYNCER_NOT_STARTED keep their meanings
- Local-tier Unauthorized stops the chain immediately (§3.2); Local-tier Corrupt/TemporarilyUnavailable continue to S3 with the remembered classification outranking a later Remote NotFound

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Compile ripple] cold_storage_spill_test.cpp MakeManager ctor update**
- **Found during:** Task 1 (build)
- **Issue:** ColdStorageManager ctor gained the shared remote_store_mutex parameter; the Phase-8 spill suite's direct-construction helper no longer compiled
- **Fix:** MakeManager creates a fixture-local remote_store_mutex and passes it (the spill suite has no chain to share with)
- **Files modified:** SuperGenius/test/src/crdt/cold_storage_spill_test.cpp
- **Verification:** cold_storage_spill_test green in the Tier-1 lane (4/4)
- **Commit hash:** 76e813710

**2. [Rule 3 - Underspecified interface] Get success signal**
- **Found during:** Task 1 (implementation)
- **Issue:** The planned ColdReadStatus (Class + fromRemoteTier only) cannot express success; "on bytes" needed a decidable contract
- **Fix:** Documented non-empty-buffer-as-success in the header contract (DAG blocks are never empty); no struct change
- **Files modified:** SuperGenius/src/crdt/cold_read_fallback.hpp
- **Verification:** all hook tests pass on the contract
- **Commit hash:** 76e813710

**3. [Rule 3 - Plan-text gap] D-03 precedence on the no-route path**
- **Found during:** Task 2 (implementation)
- **Issue:** The action text scopes the precedence rule to "peer leg ends in CID_NOT_FOUND", but getNode's no-route failure is ROUTE_NOT_FOUND (via GetRouteKeys) - the behavior spec ("s3d Unavailable + no peer route -> COLD_STORAGE_TEMPORARILY_UNAVAILABLE") requires precedence there too
- **Fix:** ApplyColdPrecedence fires on {CID_NOT_FOUND, ROUTE_NOT_FOUND}; BOOST_OUTCOME_TRY(GetRouteKeys) replaced by a manual check to intercept the no-route path
- **Files modified:** SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp
- **Verification:** regression lane green; 09-03's fault suite owns the behavioral proof
- **Commit hash:** f9236a5c4

**Total deviations:** 3 auto-fixed (1 compile ripple, 2 specification gaps). **Impact:** none on must_haves; all three are narrow, documented, and covered by the green lane.

## Issues Encountered

None.

## Next Plan Readiness

Ready for 09-02 - the hook, chain, Error values, bundle fields, and remote_store_mutex_ that the responder cold-serve and re-warm executor build on are landed and green.
