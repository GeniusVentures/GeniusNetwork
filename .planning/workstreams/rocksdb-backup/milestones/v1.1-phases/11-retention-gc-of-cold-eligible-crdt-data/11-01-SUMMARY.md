---
phase: 11-retention-gc-of-cold-eligible-crdt-data
plan: "01"
subsystem: database
tags: [rocksdb, crdt, garbage-collection, retention, cold-storage, column-family, cid]

requires:
  - phase: 10-flush-gated-durability-advancement
    provides: AdvanceDurabilityOnce evidence chain, RefreshStagingStats + staging_healthy_ predicate, kEvictionDurabilityGate, status-atomics discipline
  - phase: 08-spill-on-write-background-drainer
    provides: ColdStorageManager own-thread lifecycle shape, BlockStoreBackedIpfsDatastore spill decorator, cold_store_mutex_ contract
  - phase: 09-cold-read-fallback-local-graphsync
    provides: GetNodeWithoutRequest hot-first-then-cold read path the GC walk reuses
provides:
  - Library spill-timestamp age evidence (spill_times side CF, birth-atomic in Put's batch; GetSpilledAt/SetSpilledAt/GetDurableWithSpillTime; pre-Phase-11 stores extend in place via create_missing_column_families)
  - CIDv0 dag-pb verify equivalence (EquivalentCidClaim) across LocalBlockStore + S3BlockStore Put/Get verify paths - CRDT delta nodes can now spill at all
  - RetentionOptions config surface (blockstore.retention strict parse, required positive age D-04, per-knob 0-default cadence) + retention-inert WARN in GeniusNode
  - ColdStorageManager GC thread (own thread/cv/stop-flag D-06) + GcPassOnce fixed tick order (staging gate -> heads snapshot -> fresh unconditional walk -> eligibility -> heads-equality abort -> status) - observe-only, ends at the reported candidate set
  - SC5 epoch watermark record under the pinned /crdt/gc/ prefix (per-topic min-head floor/max height/computed-at, node-local, advisory-only)
  - gc_* plain status fields + ColdUploadState::Unreadable (MI-02) + AttachColdStorageGc bridge with OFF-build ODR twin
  - cold_storage_gc_test hermetic Tier-1 suite (real CrdtDatastore + GraphsyncDAGSyncer + decorator fixture, SC1 prefix-spy hot datastore)
affects: [11-02 destructive eviction, 11-03 retrievability proofs, 11-04 live tier, gc-e2e evidence]

actuals:
  tokens: 54000
  tasks: 3
  commits: 7

tech-stack:
  added: []
  patterns:
    - "Post-construction dependency attach (AttachGcDependencies between Init's m_crdtDatastore creation and Start)"
    - "Prefix-spy hot-store decorator as the SC1 provably-never instrument"
    - "Heads-equality exactness abort (immutable content-addressed blocks => reachability is a pure function of the head set)"
    - "Every GC failure mode steered to under-eviction (abort/skip/backfill, never guess)"

key-files:
  created:
    - SuperGenius/test/src/crdt/cold_storage_gc_test.cpp
  modified:
    - thirdparty/sgns-blockstore/include/sgns-blockstore/LocalBlockStore.hpp
    - thirdparty/sgns-blockstore/include/sgns-blockstore/Cid.hpp
    - thirdparty/sgns-blockstore/src/LocalBlockStore.cpp
    - thirdparty/sgns-blockstore/src/S3BlockStore.cpp
    - thirdparty/sgns-blockstore/test/local_block_store_test.cpp
    - SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp
    - SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp
    - SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp
    - SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp
    - SuperGenius/src/crdt/globaldb/ColdStorageStackStub.cpp
    - SuperGenius/src/crdt/globaldb/globaldb.hpp
    - SuperGenius/src/crdt/globaldb/globaldb.cpp
    - SuperGenius/src/account/GeniusNode.cpp
    - SuperGenius/test/src/crdt/cold_storage_config_gate_test.cpp
    - SuperGenius/test/src/crdt/CMakeLists.txt

key-decisions:
  - "D-01 landed as the side column family (planner ruling #2): spill_times written in Put's EXISTING !already_present WriteBatch - birth-atomic, no second Write, no re-Put churn; pre-Phase-11 records backfill to now and wait one full retention period"
  - "TRACER DISCOVERY: every CRDT delta node is CIDv0/DAG_PB/sha256 (IPLDNodeImpl getType), but the library's verify-at-facade compared against CidOf's always-CIDv1 output - real deltas were rejected Corrupt at BOTH the decorator and S3 seams and could never spill. Fixed with EquivalentCidClaim (identical multihash + codec + hash type; only the version encoding may differ - the IPLD spec position). This empirically contradicts 11-RESEARCH's CIDv1/DAG_CBOR/blake2b claim for the delta path"
  - "Walk-gap semantics (unspecified in the plan): a head-reachable link missing from every tier aborts the pass with zero candidates - reachability is not computable, and the only safe direction is under-eviction"
  - "Retention cadence normalization mirrors the durability discipline at BOTH the parse layer (config-gate assertions observe 600000/60000 through Parse) and the manager ctor (programmatic-config defense)"
  - "Explicit retention_age_ms: 0 fails loud as 'positive uint required' alongside the absent case - presence tracked separately from value (D-04); a 0-threshold would arm immediate eviction"

patterns-established:
  - "SC1 instrument: test-local BufferStorage spy wrapping the REAL hot face; the GC is its only client, so tallies observe exactly the GC's hot-store footprint (every GC hot op after Task 3 is a /crdt/gc/ watermark write; protected prefixes stay at zero)"
  - "Mid-pass test hook (SetGcMidPassHookForTesting, the library SetCrashPointForTesting precedent) - fires between walk and the heads-equality re-check, the seam for the heads-change abort proof"
  - "Watermark record layout: LE [u64 computed_at][u32 topic_count] then per topic [u16 name_len][name][u64 min_height][u64 max_height] - node-local, non-replicated, internal"

requirements-completed: [GC-01]

coverage:
  - id: D1
    description: "Library spill-timestamp age evidence - side CF, birth-atomic batch write, absent-vs-unreadable distinct, old-store in-place extension (A1), backfill surface"
    requirement: GC-01
    verification:
      - kind: unit
        ref: "thirdparty/sgns-blockstore/test/local_block_store_test.cpp#SpillTimestampBirthAtomicAndRePutStable"
        status: pass
      - kind: unit
        ref: "thirdparty/sgns-blockstore/test/local_block_store_test.cpp#OldStoreReopenCreatesSpillTimesAndBackfills"
        status: pass
      - kind: unit
        ref: "thirdparty/sgns-blockstore/test/local_block_store_test.cpp#CidV0DagPbClaimAcceptedAndStillVerifies"
        status: pass
  - id: D2
    description: "Strict blockstore.retention config surface (required positive age, unknown/wrong-type loud, 0-default cadence knobs), retention-inert WARN, Unreadable enum + gc status plumbing across the ungated boundary, wallet asset untouched"
    requirement: GC-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_config_gate_test.cpp#Retention* (7 cases)"
        status: pass
      - kind: automated
        ref: "negative gates: wallet-asset retention count == 0; ColdStorageStack.hpp gated includes == 0"
        status: pass
  - id: D3
    description: "GC thread + GcPassOnce observe-only pass - fresh unconditional-link walk from the heads snapshot, eligibility intersection (Durable exactly, strictly-past age, unreachable, unpinned), staging inhibition, empty pass, fail-closed unattached posture, e2e candidate set exactness with the SC1 prefix-spy proving zero protected-prefix operations"
    requirement: GC-01
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/crdt/cold_storage_gc_test.cpp#EndToEndRetentionPassIdentifiesExactCandidateSet"
        status: pass
      - kind: integration
        ref: "SuperGenius/test/src/crdt/cold_storage_gc_test.cpp#StagingInhibitionSkipsTick,#EmptyJournalZeroCandidatePass,#UnattachedDependenciesFailClosed,#DurabilityGateRequiresExactlyDurable,#AgeAtOrBelowThresholdNotEligible"
        status: pass
  - id: D4
    description: "Honesty proofs - resolved-but-reachable never eligible (Pitfall 1 regression), heads-change mid-pass abort + recovery, backfill fairness regardless of true age"
    requirement: GC-01
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/crdt/cold_storage_gc_test.cpp#ResolvedOldSubtreeNeverEligible,#HeadsChangeDuringPassAborts,#BackfillFairnessWaitsFullPeriod"
        status: pass
  - id: D5
    description: "SC5 epoch watermark - computed + stored per pass under the pinned /crdt/gc/ prefix, rewritten fresh, pinned across passes, nothing deletion-gated on it"
    requirement: GC-01
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/crdt/cold_storage_gc_test.cpp#EpochWatermarkWrittenPerPassAndPinned"
        status: pass
      - kind: integration
        ref: "SuperGenius/test/src/crdt/cold_storage_gc_test.cpp#PerPassMetricsTrackEachPass"
        status: pass
---

# Phase 11 Plan 01: Retention GC of Cold-Eligible CRDT Data (Observe-Only Foundation) Summary

One-liner: spill-timestamp age evidence + strict retention config + a dedicated observe-only GC thread whose fresh reachability walk and four-way eligibility gate identify cold-eligible CIDs with provable keyspace discipline - plus the CIDv0 delta-spill defect the tracer surfaced and fixed.

Duration: ~90 min | Tasks: 3/3 | Files: 16 (1 new suite)

## Accomplishments

- **Library (D-01)**: `spill_times` side column family (8-byte LE unix-ms) written inside Put's existing `!already_present` WriteBatch - birth-atomic, single fsync, no re-Put churn; `GetSpilledAt` (NotFound absence vs mapped unreadable), `SetSpilledAt` (backfill + test seam), `GetDurableWithSpillTime` (journal-CF scan filtering Durable with point reads, encoded-byte order, 0 = absent never fabricated). Old 3-CF stores extend in place (`create_missing_column_families`, A1 proven by the raw-crafted reopen test).
- **CIDv0 delta-spill fix (tracer discovery)**: `EquivalentCidClaim` in `Cid.hpp`, applied at all four verify sites (LocalBlockStore Put/Get, S3BlockStore Put/Get). CRDT delta nodes are CIDv0 (Qm...) and were universally rejected Corrupt by the V1-only comparison - no real delta had ever spilled through the decorator. Digest/codec/hash-type equality still required; wrong bytes still Corrupt.
- **Config (D-02/D-03/D-04/D-07/D-13)**: strict `blockstore.retention` sub-object parse (required positive `retention_age_ms` - absent AND explicit-0 both loud; `dry_run` bool; `gc_interval_ms`/`grace_ms` 0-default to 600000/60000 at parse + manager), unknown-key/wrong-type loud, retention-only never activates (gate (e) inheritance) with `retention_configured` driving GeniusNode's one-line inert WARN. LogSummary renders the four non-secret knobs only when configured.
- **Manager GC (D-05/D-06/D-08)**: `RetentionOptions` as trailing ctor default (all Phase-8/10 call sites compile unchanged); `AttachGcDependencies` post-construction seam (complete-set-or-nothing); GC thread with own cv/stop-flag (never io_, never pubsub), Stop joins AFTER the drainer join + Phase-10 final flush; `GcPassOnce` fixed tick order ending at the reported candidate set; `SetGcMidPassHookForTesting` seam.
- **Ungated boundary**: nine `gc_*` plain status fields, `ColdUploadState::Unreadable` (MI-02 - NotFound maps NoRecord, every other read failure maps Unreadable), `AttachColdStorageGc` bridge + OFF-build ODR twin, `globaldb.cpp` Init attaches after `m_crdtDatastore` creation before `Start()`.
- **SC5**: `WriteEpochWatermark` - per-topic min-head floor/max height/computed-at, one node-local record under the pinned `/crdt/gc/` prefix via the hot face, advisory-only.
- **Suites**: `cold_storage_gc_test` (11 cases over a real CrdtDatastore + GraphsyncDAGSyncer + decorator fixture with the prefix-spy hot store) + 7 `Retention*` config-gate cases + 3 library cases.

## Verification Evidence

- Library build green; `local_block_store_test` + `s3_block_store_test` green; full library Tier-1 battery 14/14.
- SuperGenius `crdt_globaldb` + `genius_node` + both test targets build green; cold-storage regression lane 7/7 (`cold_storage*` + `cold_read*`), config gate + GC suite green.
- Negative gates: wallet asset `retention` count 0; `ColdStorageStack.hpp` gated includes 0; `ColdStorageManager.cpp` CRDT-enumerator calls 0 (`QueryElements|TombsPrefix`).

## Deviations from Plan

1. **[Rule 3 - blocker auto-fixed] CIDv0 dag-pb verify equivalence** - Found during: Task 1 (tracer). Every CRDT delta node (IPLDNodeImpl: V0/DAG_PB/sha256) was rejected `Corrupt` by the V1-only `CidOf` comparison at the decorator and S3 Put/Get verify paths - the plan's "seed a mini-DAG through the decorator so blocks journal" was impossible for real deltas (a latent v1.1 integration defect; no prior phase exercised deltas through the decorator). Fix: `EquivalentCidClaim` (multihash + codec + hash-type equality; only version encoding may differ) at all four sites + regression case. Files: Cid.hpp, LocalBlockStore.cpp, S3BlockStore.cpp, local_block_store_test.cpp. Verification: `CidV0DagPbClaimAcceptedAndStillVerifies` + the e2e (deltas spill, drain, advance to Durable). Commits: c08629e. Note: empirically contradicts 11-RESEARCH's "CRDT DAG blocks are CIDv1/DAG_CBOR/blake2b-256" for the delta path.
2. **[Rule 2 - footprint addition] Task 1 also touched `ColdStorageStack.hpp`** (gc_* status fields were required by Task 1's e2e status assertions; Task 2 re-touched the file as planned) **and `local_block_store_test.cpp`** (the V0 regression case rode the fix commit; Task 2 re-touched as planned).
3. **[Rule 2 - normalization site] Retention cadence knobs normalize at the parse layer as well as the manager ctor** (the durability precedent) so the config-gate matrix can observe 600000/60000 through `Parse`; the plan's "at the Stack layer" wording is satisfied by the manager-side normalization being the effective site for programmatic configs.
4. **[Rule 2 - unspecified case resolved] Walk-gap abort**: a head-reachable link missing from every tier aborts the pass (distinct rate-limited `gc: pass-aborted-walk-gap` line) - the plan specified the walk but not the total-miss case; under-eviction is the only safe direction.
5. **[Deferred detail] Relearn-during-walk success-path detection** is not observable from the manager seam (a successful `GetNodeWithoutRequest` does not reveal which tier served it); the distinct `gc:` line fires on the walk-gap/cold-failure shapes, and success-path relearn detection lands naturally with 11-02's disposed-marker plumbing. No test asserts it.

**Total deviations:** 4 auto-fixed + 1 documented deferral. **Impact:** the CIDv0 fix is load-bearing for the entire milestone (without it no delta block can spill); everything else is placement/scope bookkeeping.

## Issues Encountered

None open. The CIDv0 discovery is captured as deviation 1 and should be reflected in the phase record (it invalidates the research's delta-CID claim for Waves 2-4 planning assumptions).

## Self-Check: PASSED

- All 3 tasks executed, each committed atomically (RED 1193943b4; GREEN ce15afdb3 / 8c2feb456 / 8cce567ae in SuperGenius; c08629e / f287f3e in sgns-blockstore; ace4a7f / 375c7dc thirdparty bumps).
- All `<verification>` commands green (builds, three suites, three negative gates).
- SUMMARY created in the plan directory.

## Next

Ready for 11-02 (the destructive half consumes exactly this candidate set).
