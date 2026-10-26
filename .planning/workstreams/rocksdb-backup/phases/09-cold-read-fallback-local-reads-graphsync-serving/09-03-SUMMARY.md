---
phase: 09-cold-read-fallback-local-reads-graphsync-serving
plan: 03
subsystem: testing
tags: [cold-storage, fault-injection, sc1-sc5, evidence, tier1]

requires:
  - phase: 09-cold-read-fallback-local-reads-graphsync-serving (plans 01-02)
    provides: chain + taxonomy + MapColdReadStatus (09-01), re-warm executor + ColdServeDagService wrapper + SC2 harness (09-02)
provides:
  - SC1/SC3 fault-injection honesty matrix (no-NotFound-escape, Corrupt tier attribution both tiers, Unauthorized own class, D-03 fall-through) at both classification layers
  - SC3 no-peer-blame proof (exhaustive mapping safety net + scoped structural audit)
  - SC4 rehydrate-silence spy proofs (bytes-only, pre-sealed untouched)
  - D-07 re-warm fault recovery (coalescing map never wedges)
  - SC2 outage freeze regression (faulted fail-fast with churning queue + slow-500 ms saturated queue)
  - Consolidated evidence banners matching implemented case names (SC1-SC5 citable)
affects: [11-retention-gc, 12-integration-hardening]

actuals:
  tokens: 12000
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - Decision-ID-addressable test naming (SC1_*/SC2_*/SC3_*/SC4_*/D-0N_*) so phase verification cites cases directly
    - Evidence-banner-as-document discipline (banners describe what runs)

key-files:
  created: []
  modified:
    - SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp
    - SuperGenius/test/src/crdt/cold_read_freeze_latency_test.cpp

key-decisions:
  - "Existing cases renamed to decision-ID form (banner citability); no behavioral change in any renamed case"
  - "The D-03 fall-through case asserts success-by-bytes; the SC1 property is asserted on failure-shape cases only (the success-path status payload is the documented default)"

patterns-established:
  - "Two-layer taxonomy assertion: every fault case checks ColdReadStatus AND MapColdReadStatus so escape-proofing is proven at the seam and the Error surface"

requirements-completed: [READ-01, READ-02]

coverage:
  - id: D1
    description: "SC1 fault-injected proof: no transport-shaped failure can produce a NotFound-shaped result at either classification layer; definitive absence is the only NotFound"
    requirement: READ-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#SC1_NoNotFoundEscape_S3Unavailable"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#D03_DefinitiveAbsenceIsTheOnlyNotFound"
        status: pass
    human_judgment: false
  - id: D2
    description: "SC3 honest taxonomy under fault: Corrupt attribution both tiers, good-S3-serves-after-local-corruption, Unauthorized own class, no peer blame (mapping safety net + structural audit)"
    requirement: READ-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#SC3_CorruptAttributesRemoteTier"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#SC3_CorruptAttributesLocalTier"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#SC3_LocalCorruptServesGoodS3Copy"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#SC3_UnauthorizedSurfacesOwnClass"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#SC3_NoPeerBlameMappingSafetyNet"
        status: pass
      - kind: other
        ref: "git grep -E 'RecordCIDFailure|BlackListPeer' over the three cold-read sources: zero matches (structural audit)"
        status: pass
    human_judgment: false
  - id: D3
    description: "SC4 rehydrate silence: exactly one bytes-write, zero marker writes for never-sealed blocks; pre-sealed blocks gain no second marker"
    requirement: READ-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#SC4_RehydrateSilence_BytesOnlyNoMarkers"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#SC4_PreSealedBlockGainsNoMarker"
        status: pass
    human_judgment: false
  - id: D4
    description: "SC2 freeze regression under outage: hot serve < 50 ms with 16+ cold misses in flight, both faulted fail-fast and slow-500 ms; miss path fail-fast"
    requirement: READ-02
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_read_freeze_latency_test.cpp#SC2_HotServeUnderOutageFailFastQueueChurning"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_read_freeze_latency_test.cpp#SC2_HotServeUnderSaturatedSlowQueue"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_read_freeze_latency_test.cpp#SC2_OutageMissReturnsImmediately_FailFast"
        status: pass
    human_judgment: false
  - id: D5
    description: "D-07 re-warm fault recovery and SC5 lane posture: coalescing map never wedges on a failed fetch; whole Tier-1 lane fail-closed green with 5==5 registration/label parity"
    requirement: READ-02
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#D07_RewarmFaultRecoveryMapNeverWedges"
        status: pass
      - kind: other
        ref: "ctest -L Tier1 --no-tests=error (5/5 green) + addtest(cold_) vs LABELS parity 5==5"
        status: pass
    human_judgment: false

duration: 30min
completed: 2026-10-26
status: complete
---

# Phase 9 Plan 03: Fault-Injection Honesty Suite Summary

**The SC1-SC5 invariants are now disproof-proven under induced failure: no transport fault escapes as NotFound, cold blips never blame peers, rehydrate writes bytes and nothing else, and the responder stays sub-50 ms hot while a faulted or slow s3d churns cold misses.**

## Performance

- **Duration:** 30 min
- **Started:** 2026-10-26T23:50Z (approx)
- **Completed:** 2026-10-27T00:20Z (approx)
- **Tasks:** 3/3
- **Files modified:** 2 (test-only; no production symbols)

## Accomplishments
- SC1/SC3 fault matrix green at BOTH classification layers (ColdReadStatus + MapColdReadStatus): no-NotFound-escape, Corrupt(local)/Corrupt(remote) attribution, corrupt-local-serves-good-S3, Unauthorized own class, exhaustive 4x2 table, no-peer-blame safety net
- SC4 silence spy-proven at the exact decorator write target: exactly one set, zero marker writes; pre-sealed blocks untouched (§2.4 ruling enforced by test)
- SC2 freeze regression completed both halves: faulted fail-fast with 16 churning misses AND slow-500 ms saturated queue - hot serve < 50 ms in both
- D-07 recovery: a failed re-warm under Unavailable never wedges the coalescing map (re-enqueue accepted, warms after fault-clear)
- Lane posture: Tier-1 fail-closed green (5/5), registration/label parity 5==5, regression suites green, evidence banners match implemented case names

## Task Commits

Each task was committed atomically (SuperGenius submodule, branch dev_blockstore):

1. **Task 1: SC1/SC3 taxonomy fault matrix + decision-ID renames** - `b08fc9cc4` (test)
2. **Task 2: no-peer-blame + SC4 silence + D-07 recovery + SC2 outage regression** - `70e17d501` (test)
3. **Task 3: evidence banners + lane consolidation** - `b17643b5a` (test)

**Plan metadata:** (docs commit follows)

## Files Created/Modified
- `SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp` - fault matrix cases, SC4 spy cases, no-peer-blame net, fault-recovery case, decision-ID renames, evidence banner
- `SuperGenius/test/src/crdt/cold_read_freeze_latency_test.cpp` - outage freeze-regression scenario, SC2 renames, banner case-list update

## Decisions Made
- Renamed existing cases to decision-ID form (banner citability for phase verification); zero behavioral change in renamed cases
- The D-03 fall-through case asserts success by bytes; SC1 escape-proofing is asserted on failure-shape cases only (the success-path status payload is the documented default)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Contract nuance] D-03 fall-through case initial assertion**
- **Found during:** Task 1 (test run)
- **Issue:** The case asserted status.cls != NotFound on a SUCCESSFUL fetch - but the success-path status payload is the documented default (meaningful only on failure)
- **Fix:** Dropped the misdirected assertion with an explanatory comment; the SC1 property remains asserted on the failure-shape cases
- **Files modified:** SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp
- **Verification:** suite green
- **Commit hash:** b08fc9cc4

**Total deviations:** 1 auto-fixed. **Impact:** none.

## Issues Encountered

None.

## Next Plan Readiness

Phase 9 is complete: all three plans landed, the SC1-SC5 matrix is green in the fail-closed Tier-1 lane, and READ-01/READ-02 evidence is citable by case name. Ready for phase verification.
