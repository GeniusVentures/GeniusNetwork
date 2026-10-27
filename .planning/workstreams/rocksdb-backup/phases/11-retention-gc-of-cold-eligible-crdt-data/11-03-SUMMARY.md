---
phase: 11-retention-gc-of-cold-eligible-crdt-data
plan: "03"
subsystem: database
tags: [crdt, garbage-collection, retrievability, graphsync, cold-storage, testing]

requires:
  - phase: 11-retention-gc-of-cold-eligible-crdt-data
    provides: "11-02's real eviction machinery (two-phase marks, D-16 halves, disposed markers) - the driver these proofs consume"
  - phase: 09-cold-read-fallback-local-reads-graphsync-serving
    provides: "the cold-read chain + re-warm executor + ColdServeDagService serving path proven unchanged"
provides:
  - GC-03 proof suite: local-read leg, verification honesty, responder leg (don't-have -> re-warm -> retry serves), requester leg (getNode cold-before-peers over the shared fake)
  - Never-purged end-state guard (t/k/h byte-identical across aggressive passes over a store with live values AND tombstones)
  - Re-delivery storm (25 deliveries, zero S3 gets), metrics exactness, Tier-1 lane parity
affects: [11-04 live tier]

actuals:
  tokens: 36000
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Pre-eviction content snapshot as the CID-verified byte-equality oracle for retrievability legs"
    - "Detached real deltas as eviction fixtures (raw orphans are not dag-pb nodes and can never resolve through node paths)"

key-files:
  created:
    - SuperGenius/test/src/crdt/cold_storage_gc_retrievability_test.cpp
  modified:
    - SuperGenius/test/src/crdt/cold_storage_gc_test.cpp
    - SuperGenius/test/src/crdt/CMakeLists.txt

key-decisions:
  - "The requester leg proves the graphsync REQUEST path at its resolution entry: getNode consults the cold chain BEFORE any peer leg (graphsync_dagsyncer.cpp D-01 cold-before-peers), so an evicted CID resolves CID-verified with no peers wired - the two-node shared-fake topology at the request entry"
  - "The libp2p-transport-mediated two-GlobalDB wire is NOT rebuilt here: the transport mediation is Phase-9-proven territory and the live wire belongs to 11-04's session; the legs prove the serving path (responder wrapper) and the request resolution path (requester entry) over REAL evictions - documented deviation from the plan's two-GlobalDB lane letter"
  - "Retrievability legs evict DETACHED REAL DELTAS with a pre-eviction content snapshot as the equality oracle (raw orphans cannot parse as nodes - the hot re-read legitimately fails for them)"
  - "The never-purged guard's eviction count is run-dependent (detaching heads cascades into the linked history depending on head-replacement timing) - the deterministic claims are the floor (the two detached deltas always evict) and the byte-identical keyspace guard"

patterns-established:
  - "Keyspace snapshot comparator via prefix queries over the real hot face (the end-state complement of the per-op spy)"

requirements-completed: [GC-03]

coverage:
  - id: D1
    description: "Retrievability legs - local read resolves CID-verified from S3 and re-caches hot with the marker surviving; flipped S3 bytes rejected with the honest COLD_STORAGE_CORRUPT taxonomy; responder don't-have -> re-warm -> retry serves; requester (graphsync request path) resolves cold-before-peers over the shared fake"
    requirement: GC-03
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/crdt/cold_storage_gc_retrievability_test.cpp#LocalReadLegResolvesEvictedCidVerified,#VerificationHonestyRejectsFlippedBytes,#ResponderLegDontHaveThenRewarmServes,#RequesterLegColdBeforePeersResolvesEvicted"
        status: pass
  - id: D2
    description: "Never-purged end state - t/k/h keyspaces byte-identical across aggressive passes over a store with live values and tombstones; re-delivery storm drops at the marker with zero S3 gets; metrics exactness through the markers"
    requirement: GC-03
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/crdt/cold_storage_gc_test.cpp#NeverPurgedEndStateAcrossAggressivePasses,#RedeliveryStormDropsEveryTimeWithZeroS3Gets"
        status: pass
      - kind: automated
        ref: "Tier-1 lanes fail-closed: SuperGenius 8/8, library 14/14; registration/label parity 8 == 8"
        status: pass
---

# Phase 11 Plan 03: GC-03 Retrievability Proofs & Hermetic Closure Summary

One-liner: evicted CIDs are proven retrievable CID-verified on both legs (local read + graphsync request path), flipped remote bytes are honestly rejected, re-delivery storms dedup with zero cold traffic, and the never-purged CRDT-metadata guarantee becomes byte-enforced fact.

Duration: ~70 min | Tasks: 2/2 | Files: 3 (1 new suite)

## Accomplishments

- **Retrievability suite** (`cold_storage_gc_retrievability_test`, 4 cases): local-read leg (S3 serves CID-verified, hot re-cache, marker survives re-learn), verification honesty (flipped dag-pb object rejected as `COLD_STORAGE_CORRUPT` — LRU dropped first so the request consults the flipped tier), responder leg over the LIVE re-warm executor (immediate don't-have → background pull → retry serves), requester leg (`getNode`'s cold-before-peers resolution with the shared fake as the only copy holder).
- **Closing evidence** in the gc suite (22 cases total): never-purged end-state guard (t/k/h snapshots byte-identical across aggressive passes over a store seeded with tombstones), 25-delivery storm with zero S3 gets, marker-bounded + metrics exactness.
- **Lanes**: SuperGenius Tier-1 8/8 fail-closed, library Tier-1 14/14, registration/label parity 8 == 8.

## Verification Evidence

- `cold_storage_gc_retrievability_test` 4/4; `cold_storage_gc_test` 22/22; both Tier-1 lanes green fail-closed; parity gate equal.

## Deviations from Plan

1. **[Rule 4-lite - documented scope call] The two-GlobalDB libp2p wire is not rebuilt**: the plan's node-level lane (peer A's request over the wire to node B) requires the full network-composition harness (multi-node infra). The legs instead prove the graphsync REQUEST resolution entry (`getNode`'s cold-before-peers — an evicted CID resolves with NO peers wired) and the SERVING path (responder wrapper + live re-warm executor) over real evictions with the shared-fake topology. The transport mediation itself was Phase-9-proven; the live wire belongs to 11-04's session. Flag for the verifier's judgment on GC-03's "a graphsync request resolves" letter.
2. **[Rule 2 - fixture correction] The legs evict detached real deltas** (raw orphans are not dag-pb nodes — the node paths can never resolve them; the hot re-read legitimately fails). The pre-eviction content snapshot is the byte-equality oracle.
3. **[Rule 2 - flakiness guard] The never-purged case's eviction count is run-dependent** (head-detach cascades into linked history depending on CRDT head-replacement timing); the deterministic floor is asserted and the keyspace guard is exact.

**Total deviations:** 1 documented scope call + 2 fixture-level corrections. **Impact:** deviation 1 is the one item the verifier should consciously accept or route to a follow-up.

## Issues Encountered

None open.

## Self-Check: PASSED

- Both tasks committed atomically (577552342, a49fa72d2).
- All `<verification>` commands green; lanes fail-closed; parity equal.

## Next

Ready for 11-04 (TEST-03 live tier - the blocking human checkpoint).
