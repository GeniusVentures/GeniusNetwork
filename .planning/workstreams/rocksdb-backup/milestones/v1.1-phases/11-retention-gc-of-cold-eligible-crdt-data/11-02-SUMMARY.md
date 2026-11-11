---
phase: 11-retention-gc-of-cold-eligible-crdt-data
plan: "02"
subsystem: database
tags: [rocksdb, crdt, garbage-collection, eviction, disposed-markers, crash-consistency, dedup]

requires:
  - phase: 11-retention-gc-of-cold-eligible-crdt-data
    provides: "11-01's candidate identification (GcPassOnce eligibility intersection), spill-timestamp evidence, SC1 prefix-spy fixture, CIDv0 delta-spill fix"
  - phase: 09-cold-read-fallback-local-graphsync
    provides: "ColdReadService chain + ColdReadFallback hook (HasLocalCold shape), rehydrate path the re-learn reuses"
provides:
  - Library disposed-CID column family + D-16 half-1 primitive (EvictLocalAndMarkDisposed: one batch = 3 deletes + marker put), IsDisposed/GetDisposed/TrimDisposed dual bound
  - Manager two-phase eviction (EvictingMark with mark-time snapshot/rows/size/seal capture, defer-to-next-tick grace, D-14 delete-time heads-equality cancel, D-16 two-half composition, dry_run suppression)
  - FinishOrphanedHotCleanups crash-between-halves recovery (rows recomputed from the remote copy)
  - ColdReadFallback::HasDisposed hook + ColdReadService override + HasBlock fourth term (D-11 dedup, three call sites inherit with zero audits)
  - Elems-row derivation rule (elems namespace is the sibling of the k-namespace under the set root)
affects: [11-03 retrievability proofs, 11-04 live tier]

actuals:
  tokens: 48000
  tasks: 2
  commits: 7

tech-stack:
  added: []
  patterns:
    - "Two idempotent single-store halves as ONE policy unit (D-16 reconciliation) with an under-eviction-safe crash window"
    - "Mark-time full capture (snapshot + parsed rows + size + seal) so nothing is re-derived after the grace"
    - "Spy-wrapped hot batches: the keyspace proof covers batch commits, not just direct puts/removes"

key-files:
  created: []
  modified:
    - thirdparty/sgns-blockstore/include/sgns-blockstore/LocalBlockStore.hpp
    - thirdparty/sgns-blockstore/src/LocalBlockStore.cpp
    - thirdparty/sgns-blockstore/test/local_block_store_test.cpp
    - SuperGenius/src/crdt/cold_read_fallback.hpp
    - SuperGenius/src/crdt/globaldb/ColdReadService.hpp
    - SuperGenius/src/crdt/globaldb/ColdReadService.cpp
    - SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp
    - SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp
    - SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp
    - SuperGenius/test/src/crdt/cold_storage_gc_test.cpp

key-decisions:
  - "D-16 reconciled as two idempotent halves: the LIBRARY batch carries cold bytes + journal + spill timestamp + disposed marker; the seal text key and the block's own s-rows are hot-store keys in the hot-cleanup half - never one batch across stores (Pitfall 3)"
  - "The D-14 delete-time check compares CURRENT heads against the MARK'S OWN pass-start snapshot (stored in the mark) - the exactness evidence the eviction rests on, not the processing tick's snapshot"
  - "Orphan recovery recomputes the block's s-rows from the REMOTE copy (the cold-dir bytes are gone behind the committed library half); a remote-fetch failure leaves the hot bytes for the next pass (safe)"
  - "Elems-row derivation: GetKeysPrefix() carries NO trailing slash and the elems namespace is the SIBLING of the k-namespace under the set root ('<set>/s/k' -> '<set>/s/s/<key>/<cid>') - empirically pinned after the trailing-slash assumption failed"
  - "was_sealed is RECORDED in the marker; NO v1.1 code path restores it (rehydrate stays bytes-only, Phase-9 SC4 - documented deferral)"
  - "The fixture now mirrors production's shared-DB topology (one RocksDB wrapped twice: storage::rocksdb for the CRDT/manager face, ipfs_lite::rocksdb for the RocksdbDatastore inner) plus the real ColdReadService hook - the honest hot-bytes lifecycle"

patterns-established:
  - "Prefix-spy batch wrapper: every put/remove key tallies as a write before forwarding, so batch-committed deletes stay inside the SC1 proof"
  - "Counting S3 client probe for zero-network-traffic proofs (dedup at HasBlock)"

requirements-completed: [GC-02]

coverage:
  - id: D1
    description: "Library disposed-marker surface - single-batch destructive primitive, point lookup, ordered enumeration, dual-bound trim, all-or-nothing under the entry-gate fault"
    requirement: GC-02
    verification:
      - kind: unit
        ref: "thirdparty/sgns-blockstore/test/local_block_store_test.cpp#EvictLocalAndMarkDisposedSingleBatchAndIdempotent"
        status: pass
      - kind: unit
        ref: "thirdparty/sgns-blockstore/test/local_block_store_test.cpp#TrimDisposedDualBoundOldestFirst"
        status: pass
      - kind: unit
        ref: "thirdparty/sgns-blockstore/test/local_block_store_test.cpp#EvictLocalAndMarkDisposedAllOrNothingUnderFault"
        status: pass
  - id: D2
    description: "Two-phase eviction e2e - mark, defer-to-next-tick grace, heads re-check, one library batch, idempotent hot cleanup + LRU invalidation, marker present, keyspace boundary, HasBlock honesty, direct-read D-12 resolution"
    requirement: GC-02
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/crdt/cold_storage_gc_test.cpp#EvictionEndToEndTwoHalvesUnitAtomic,#GraceDeferToNextTickNotProcessedEarly"
        status: pass
  - id: D3
    description: "Crash/fault honesty - mid-grace destroy deletes nothing and re-marks; between-halves orphan re-scan completes half 2 with no re-spill; delete-time heads-change cancels keeping all bytes; dry-run suppresses both halves with identical evidence and zero writes"
    requirement: GC-02
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/crdt/cold_storage_gc_test.cpp#CrashMidGraceDeletesNothingAndReMarks,#CrashBetweenHalvesOrphanRescanCompletesHotCleanup,#DeleteTimeHeadsChangeCancelsMark,#DryRunSuppressesBothHalvesEntirely"
        status: pass
  - id: D4
    description: "Marker lifecycle + evidence honesty - trimmed marker re-learns (re-journal PendingUpload, bytes-only), unreadable evidence maps Unreadable at the bridge and never evicts, re-delivery dedup drops at HasBlock with zero S3 Gets"
    requirement: GC-02
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/crdt/cold_storage_gc_test.cpp#TrimmedMarkerRelearnRejournalsOnRedelivery,#UnreadableEvidenceNeverEvicts,#RedeliveryDedupDropsAtHasBlockWithZeroS3Gets"
        status: pass
---

# Phase 11 Plan 02: The Destructive Half (Two-Phase Eviction) Summary

One-liner: retention candidates become evictable through two idempotent single-store halves (library batch + hot cleanup) behind a mark/grace/heads-recheck window where every crash lands on under-eviction, with disposed-marker dedup at HasBlock and bounded marker memory.

Duration: ~105 min | Tasks: 2/2 | Files: 10

## Accomplishments

- **Library (D-09/D-10)**: `disposed_cids` CF + `DisposedRecord` (26-byte LE codec, five fields incl. `was_sealed`); `EvictLocalAndMarkDisposed` (ONE WriteBatch: delete blocks/journal/spill_times + put marker); `IsDisposed` (bool contract), `GetDisposed` (iterator discipline), `TrimDisposed` (dual bound, one batch, oldest-first overflow); defaults cap 100000 / age 30 days.
- **Manager (D-13/D-14/D-15/D-16)**: `EvictingMark` in-memory state capturing the mark-time heads snapshot, parsed delta row keys, size, and seal state; `EvaluatePass`/`ProcessDueMarks` split with defer-to-next-tick grace; delete-time heads-equality against the mark's own snapshot with cancel-keep-bytes; half-1 under `cold_store_mutex_`, half-2 as one hot batch (binary key + `<cid>sealed` + exactly the block's own s-rows) then `DeleteCIDBlock` (A6 ordering); `FinishOrphanedHotCleanups` first step of every pass (rows recomputed from the remote copy); `TrimDisposedMarkers`; dry_run suppresses both halves while marks cycle.
- **Dedup (D-11/D-12)**: `ColdReadFallback::HasDisposed` pure virtual (freeze-safe bool contract), `ColdReadService` override, `HasBlock` fourth term - the three pubsub call sites inherit re-delivery dedup with zero audits; reads never consult the marker as absence (proven: direct read of a disposed CID resolves CID-verified through S3, then legitimately re-journals).
- **Fixture honesty**: production shared-DB topology (one RocksDB, two wrappers), real `ColdReadService` hook, counting S3 client, and a spy batch wrapper so hot-cleanup deletes are inside the keyspace proof.
- **Suites**: 7 new fault cases + 2 eviction cases (20 total in the GC suite); 2 new library units; regression lane 9/9 incl. `crdt_test` + `globaldb_integration_test`.

## Verification Evidence

- Library + SuperGenius builds green; `local_block_store_test` green; `cold_storage_gc_test` 20/20; `cold_storage_config_gate_test` green.
- Full regression lane (`cold_storage*|cold_read*|crdt_test|globaldb_integration_test`): 9/9 passed.
- Keyspace discipline across the whole eviction: zero ops under `/t/`, `/h/`, `/k/`, and zero on any s-row other than the block's own (spy, batch-inclusive).

## Deviations from Plan

1. **[Rule 2 - derivation corrected] Elems-row key derivation**: the plan cited `ElemsPrefix(key).ChildString(cid)`; empirically `GetKeysPrefix()` carries NO trailing slash and the elems namespace is the sibling of the k-namespace under the set root (`<set>/s/k` -> `<set>/s/s/<key>/<cid>`). The manager and test derive accordingly (pinned by the e2e's row precondition + post-state).
2. **[Rule 2 - crash seam] The primitive's crash-atomicity case uses the FaultController entry gate** rather than `CrashPoint::BeforeCommit`: the crash-point seam exists only on the Put path; the eviction primitive's single Write has no mid-commit window, so the meaningful pair is gate-reject (all-nothing) vs success (all-present) - both asserted.
3. **[Rule 2 - fixture] The plan's file list did not include fixture wiring changes inside `cold_storage_gc_test.cpp`** (real `ColdReadService` hook + `RocksdbDatastore` inner over the shared DB + counting client) - required for HasBlock's 3rd/4th terms and the cold chain to exist at all in the hermetic harness; all inside the listed test file.
4. **[Rule 2-lite] Unreadable-gate scope**: with the fault armed the journal ENUMERATION fails first (pass aborts) - the per-candidate unreadable branch is unreachable by construction (enumeration errors abort earlier), so the case proves the two observable claims: the bridge maps Unreadable and the pass evicts nothing.

**Total deviations:** 4 auto-fixed/placement. **Impact:** none architectural; the derivation fix is load-bearing correctness for the s-row deletes.

## Issues Encountered

None open.

## Self-Check: PASSED

- Both tasks executed and committed atomically (RED 4761009c6/71e39d5; GREEN 1c121c547/5efb8d486 SuperGenius, d8a1327/1dd8c66 library, 1b32c26/f2c4e2f thirdparty bumps).
- All `<verification>` commands green; regression lane green.

## Next

Ready for 11-03 (GC-03 retrievability proofs over both legs).
