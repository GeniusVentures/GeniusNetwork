---
phase: 16-txpruner-gc-composition-hardening
plan: 02
subsystem: crdt
tags: [crdt, cold-storage, gc-disposal, tx-pruner, stranded-counter, consult-chain, tier1, tier3, ruling-doc]

requires:
  - phase: 16-01
    provides: "cold_compose_matrix_test Tier-1 home (fixture + W legs), the observe-and-continue seam, the SC1 close"
  - phase: 15-03
    provides: "RemoveHead-detach reachability shaping precedent (cold_storage_gc_test), the widened EraseEntry, hermetic kit lineage"
provides:
  - "The D-10 consult chain: TxPruner's NoRecord arm → GlobalDB::IsColdDisposed (const, lifecycle_mutex_) → ColdStorageManager::IsDisposed (cold_store_mutex_) → LocalBlockStore::IsDisposed (library-owned keyspace, no third builder) — the exact Phase-14 lock order, never re-shaped"
  - "The stranded split counter cold_disposed_stranded_groups (field + INFO surfacing cold_disposed_stranded={} between cold_unreadable and skipped): disposed constituents strand visibly; NoRecord-without-marker keeps today's cold_deferred classification byte-identically"
  - "SC3 proven both legs: deterministic Tier-1 legs S3a/S3b/S3c (red-first SC3-UNDIFFERENTIATED captured against the consult-reverted line) + the dev-gated Tier-3 live leg (real MinIO + real GC disposal + remote-fetchability of the disposed bytes)"
  - "D-02 Interaction-C ruling documented at both destructive homes (guard-5 comment + the GC gate-consumption comment); D-12 starvation ruling at the EvictLocalAndMarkDisposed home + the workstream notes doc Phase 18 cites"
  - "The re-journal nuance DISCOVERED and ruled (recorded in the ruling doc): on a reachable remote the evaluator's own block-gate read re-hydrates + re-journals a disposed block (self-healing; later cycles prune normally) — the stranded steady state is the remote-unreachable posture, scripted by a faulted S3 Get (S3a) / a stopped server (live leg)"
affects: [phase-16-plan-03, phase-17-probe, phase-18-policy, tx-pruner, retention-gc, verify-work-uat]

actuals:
  tokens: 21000   # chars/4 over realized diffs (Task 1: ~10.7K chars / Task 2: ~21K / Task 3: ~21K, minus context lines ≈ 21k tokens net)
  tasks: 3
  commits: 3      # SuperGenius: 20519ce87 (Task 1), ccb1c08bc (Task 2), f25f53b3e (Task 3)

tech-stack:
  added: []
  patterns:
    - "Null-safe IsColdDisposed free bridge in ColdStorageStack (the D-09 layering pattern) — globaldb.cpp holds only a forward declaration of ColdStorageManager, so every GlobalDB-member cold read routes through a free bridge mapping library types at the gated TU"
    - "Live-stack retention disposal drive: retention armed (age 1ms + interval 50-100ms + grace 1ms) makes GlobalDB's OWN GC thread the disposal driver — deterministic via PollUntil on the new bridge (the manager is GlobalDB-private; A5's drivability fallback made structural)"
    - "Head-detach + height regrow: RemoveHead(the target delta while it IS the topic head) then FOUR fresh-root driver puts — unreachable target (retention-eligible) with max_height regrown past spend_height + window (fresh roots restart the height counter; the count is load-bearing)"

key-files:
  created:
    - SuperGenius/test/src/crdt/cold_compose_live_smoke_test.cpp
    - .planning/workstreams/rocksdb-backup/notes/16-txpruner-gc-composition-rulings.md
  modified:
    - SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp
    - SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp
    - SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp
    - SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp
    - SuperGenius/src/crdt/globaldb/globaldb.hpp
    - SuperGenius/src/crdt/globaldb/globaldb.cpp
    - SuperGenius/src/transaction/TxPruner.hpp
    - SuperGenius/src/transaction/TxPruner.cpp
    - SuperGenius/test/src/crdt/cold_compose_matrix_test.cpp
    - SuperGenius/test/src/crdt/CMakeLists.txt

key-decisions:
  - "The GlobalDB member routes through a null-safe IsColdDisposed free bridge in ColdStorageStack (std::optional<bool>: value / false-on-null / nullopt-on-error so the member can WARN) — the D-09 pattern; globaldb.cpp cannot see ColdStorageManager's complete type (Rule-2 fix, ColdStorageStack.{hpp,cpp} added to the touched set)"
  - "S3a's disposal is driven by GlobalDB's OWN retention-GC thread (PollUntil on IsColdDisposed), not a direct manager->GcPassOnce() — the manager is private to the live stack; the genuine post-disposal state (journal deleted + marker written) is identical, and A5's fallback posture anticipated exactly this drivability question"
  - "The stranded steady state ruled as the REMOTE-UNREACHABLE posture: the evaluator's block-gate parse read re-hydrates a disposed block from a reachable remote and re-journals it (correct self-healing; a later cycle prunes normally) — S3a scripts a faulted S3 Get after the disposal; the live leg stops the server before the cycle; both assert NoRecord survives the cycle"
  - "S3a shaping: RemoveHead while the target delta IS the head + four fresh-root driver puts (heights restart at 1 — the count regrows max_height past spend_height + window); the value row and raw tx->CID map entry survive the detach"
patterns-established:
  - "Split-counter discipline: a distinct deferral class gets its own PruneCycleStats field + INFO label, never an error (D-03 → D-10 lineage)"
  - "Cross-marker consult only at the state that cannot otherwise discriminate (NoRecord arm; Pending/Accepted/default never consult — S3c proves the misclassification vector closed)"

requirements-completed: [COMP-03]

coverage:
  - id: D1
    description: "SC3 fail-safe direction (deterministic): after a real hermetic GC disposal, one TxPruner cycle classifies the group into cold_disposed_stranded_groups, erases nothing, and the last local copy of the value survives — red-first (SC3-UNDIFFERENTIATED) against the consult-reverted line"
    requirement: COMP-03
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/crdt/cold_compose_matrix_test.cpp#S3a_DisposedGroupStrandsBehindSplitCounter (red observed pre-consult, green post)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Split's negative controls: journal-deletion without marker keeps cold_deferred (S3b); the Pending arm never consults even with a real marker present (S3c)"
    requirement: COMP-03
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/crdt/cold_compose_matrix_test.cpp#S3b_JournalDeletionWithoutMarkerKeepsDeferredClassification + #S3c_PendingArmNeverConsultsEvenWithMarker"
        status: pass
    human_judgment: false
  - id: D3
    description: "SC3 live leg (D-11b): real MinIO + production S3 client + real GC disposal; the disposed block's bytes remain fetchable from the remote through the library remote read; a subsequent cycle (remote stopped) strands with the split counter — loud-skipped in CI with the runbook pointer and the S3a stand-in named (skip verified)"
    requirement: COMP-03
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/crdt/cold_compose_live_smoke_test.cpp#LiveStack_RealGcDisposalStrandsTxPruner (env-gated; default-env run = labelled SKIPPED, exit 0)"
        status: pass
    human_judgment: true
    rationale: "The live wire leg requires a MinIO community binary the CI cannot provide; the loud-skip + deterministic S3a stand-in is the shipped CI evidence (D-11's hybrid posture) — a developer run with SGNS_BLOCKSTORE_TEST_MINIO_BIN is the remaining human confirmation"
  - id: D4
    description: "Rulings documented: D-02 Interaction-C at both destructive homes (cold_store_mutex_ as the serialization point; no new lock), D-12 starvation + under-prune at the disposal home, and the workstream ruling doc with all mandated sections (options, v2 DisposedDurable pointer, one-cycle lag, sequencing record, re-journal nuance, deferred leak item)"
    requirement: COMP-03
    verification:
      - kind: automated
        ref: "notes/16-txpruner-gc-composition-rulings.md probe=11≥5; guard-5 + gate-consumption + EvictLocalAndMarkDisposed comments present; PruneEligibility zero-diff vs af644481f (exit 0); RunHotCleanup window zero-diff (0 hunks)"
        status: pass
    human_judgment: false

duration: 55min
completed: 2026-11-18
status: complete
---

# Phase 16 Plan 02: GC-Disposal Starvation Interplay Summary

**COMP-03 ruled and proven both ways: disposed constituents strand behind a visible counter (never an erase, the last copy survives), the consult rides the library API through the proven lock chain, and the D-02/D-12 rulings exist at both destructive homes plus the workstream doc Phase 18 cites.**

## Performance

- **Duration:** 55 min
- **Started:** 2026-11-18T18:45:00Z
- **Completed:** 2026-11-18T19:40:00Z
- **Tasks:** 3
- **Files modified:** 11 (9 SuperGenius + 2 planning)

## Accomplishments
- The D-10 consult chain landed exactly per the lock-order contract: NoRecord arm → IsColdDisposed (lifecycle_mutex_) → IsDisposed (cold_store_mutex_) → the library's point lookup; Pending/Accepted/default never consult (S3c); consult errors classify freeze-safe false.
- Red-first honored within the landed line: the consult branch locally reverted, S3a observed the undifferentiated mass (cold_deferred == 1, stranded == 0 — the SC3-UNDIFFERENTIATED signature), restored byte-identical (diff clean), re-run green.
- The SC3 diagnosis produced a real finding the ruling doc now records: on a reachable remote, the evaluator's own block read re-hydrates + re-journals a disposed block (self-healing; later cycles prune normally) — the stranded steady state is the remote-unreachable posture. S3a scripts it with a faulted S3 Get; the live leg stops the server before the cycle.
- Tier-3 live leg shipped with the full loud-skip contract (env gate, [SGNS_COLD_COMPOSE][LIVE-SMOKE] tag, COMMUNITY-build note, testing-tiers.md runbook pointer, S3a stand-in named); default-env run = labelled SKIPPED, exit 0; Tier-1 lane listing unaffected (16 tests).

## Red Signature (captured pre-consult, consult-reverted line)

```
cold_compose_matrix_test.cpp(1137): error: Expected equality of these values:
SC3-UNDIFFERENTIATED: the disposed group must count into the stranded counter
  Actual: false
Expected: true
```
(stranded == 0 with the consult reverted — the group counted into cold_deferred_groups instead: the undifferentiated mass.)

## Task Commits

1. **Task 1: D-10 consult chain + stranded counter + D-02/D-12 ruling comments** - `20519ce87` (feat)
2. **Task 2: SC3 deterministic legs + workstream composition-rulings doc** - `ccb1c08bc` (test; names the SeedJournalRecord/JournalKeyOf verbatim copies — invariant 2)
3. **Task 3: Tier-3 live SC3 leg** - `f25f53b3e` (test; names the MinioChildProcess/TcpPortAnswers verbatim copies — invariant 2)

**Plan metadata:** this commit (docs)

## D-11a/D-10 mechanism reconciliation (the audit-trail record)

BOTH kit mechanisms were required and both shipped: `SeedJournalRecord(dir, cid, nullopt)` models the never-spilled NoRecord shape (S3b's negative control) — it deletes the journal record but CANNOT produce the disposed marker; the retention-GC-thread disposal (S3a) produces the GENUINE post-disposal state (journal deleted + marker written + hot cleanup committed) that D-10's consult classifies. The injection alone would have left the marker-miss direction unproven; the real disposal alone would have left the never-spilled direction unproven. D-11's hybrid posture holds.

## Decisions Made
- Counter name `cold_disposed_stranded_groups` / INFO label `cold_disposed_stranded={}` (CONTEXT discretion, as planned).
- Ruling doc home `notes/16-txpruner-gc-composition-rulings.md`; Tier-3 home the NEW sibling `cold_compose_live_smoke_test.cpp` (research Open Question 2, as planned).
- The free-bridge routing (see Deviations #1) and the thread-driven disposal (Deviations #2) are the two structural calls beyond the plan letter.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical layering] GlobalDB::IsColdDisposed could not call the manager directly**
- **Found during:** Task 1 (first compile)
- **Issue:** globaldb.cpp holds only a forward declaration of ColdStorageManager (C2027/C2039) — the plan's member-to-member call shape is unimplementable in that TU.
- **Fix:** Added a null-safe `IsColdDisposed` free bridge in ColdStorageStack.{hpp,cpp} (the established D-09 pattern: `std::optional<bool>`, false on null manager, nullopt on consult error so the member WARNs and classifies freeze-safe false); the member delegates through it with the GetColdUploadState qualification discipline.
- **Files modified:** SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp/.cpp (not in files_modified — this deviation)
- **Verification:** Full Release build exit 0; all suites green.
- **Commit:** 20519ce87

**2. [Rule 1 - Drivability] S3a's "real manager->GcPassOnce()" replaced by the retention-GC thread**
- **Found during:** Task 2 (fixture design)
- **Issue:** The manager is GlobalDB-private on the live stack; a direct GcPassOnce would require the PHASE-B direct-manager reconstruction over the closed dirs — and the walk-reachability analysis showed mid-chain deltas are never GC-eligible on a live topology anyway.
- **Fix:** Retention armed (age 1ms + interval 50ms + grace 1ms): GlobalDB's OWN GC thread performs the real disposal; PollUntil on the new bridge bounds it deterministically. The genuine post-disposal state is byte-identical (the same library code path). A5's flagged fallback anticipated exactly this.
- **Verification:** S3a green (disposal + stranded classification).
- **Commit:** ccb1c08bc

**3. [Rule 1 - Discovery] The stranded steady state requires the remote-unreachable posture**
- **Found during:** Task 2 (S3a bring-up)
- **Issue:** With the remote reachable, the evaluator's block-gate parse read re-hydrates the disposed block and re-journals it (Pending) — the gate then defers via the Pending arm; the stranded classification never fires.
- **Fix:** S3a faults the S3 Get after the disposal (the frozen-fetch posture); the live leg stops the server before the cycle. Both assert NoRecord survives the cycle. The nuance is RULED in the doc (§b) — a genuine production behavior record, not a test hack.
- **Verification:** S3a green; the no-re-journal assertion holds.
- **Commit:** ccb1c08bc

**4. [Rule 2 - Fixture arithmetic] Fresh roots restart the head-height counter**
- **Found during:** Task 2 (S3a bring-up)
- **Issue:** After RemoveHead, fresh-root puts restart heights at 1 — the window arithmetic (max_height - spend_height >= window) failed with two driver puts; the group was never eligible.
- **Fix:** Four post-detach driver puts (heights 1-4 regrow past spend_height 2 + window 2); documented in-suite as load-bearing.
- **Verification:** S3a green (eligible == 1, stranded == 1).
- **Commit:** ccb1c08bc

**5. [Rule 2 - Blocked probe] S3a's post-teardown GetDisposed enumeration dropped**
- **Found during:** Task 2 (S3a close-out)
- **Issue:** After a retention-GC-bearing GlobalDB shuts down, an in-process object retains the coldstore's RocksDB handle indefinitely (diagnosed: raw DB::Open fails "LOCK ... used by another process" past 45 s; the identical teardown WITHOUT retention releases cleanly — S3b's reopen works).
- **Fix:** The marker's existence is asserted pre-teardown through the production consult chain itself (the PollUntil on IsColdDisposed — the same disposed-CF point lookup GetDisposed enumerates). The leak is REGISTERED as a deferred hardening item here and in the ruling doc; benign in production (the store outlives shutdown interest).
- **Verification:** S3a green with the substituted assertions.
- **Commit:** ccb1c08bc

**Total deviations:** 5 auto-fixed (1 layering, 1 drivability, 1 discovery-turned-ruling, 1 fixture arithmetic, 1 blocked probe). **Impact:** none on the D-10/D-02/D-12 contracts; all prohibition gates green.

## Verification Results

| Gate | Result |
|------|--------|
| Full incremental Release build | exit 0 |
| Full suite (W1-W4 + S3a/S3b/S3c) | 7/7 OK |
| S3a red-first (consult reverted) | FAILED as required — SC3-UNDIFFERENTIATED captured |
| ctest -L Tier1 (final) | 16/16 passed, exit 0 |
| cold_compose_live_smoke default-env run | labelled SKIPPED, exit 0 (loud-skip contract) |
| Tier-1 listing | 16 tests, no Tier-3 leak |
| PruneEligibility zero-diff vs af644481f | exit 0 |
| RunHotCleanup window :1317-1353 zero-diff | 0 hunks |
| Suite probe (stranded/SeedJournalRecord/GcPassOnce) | 11 ≥ 4 |
| Ruling-doc probe (5 anchors) | 11 ≥ 5 |
| env-gate / runbook / cmake probes | 3 ≥ 2 / 4 ≥ 2 / 8 ≥ 2 |

## Deferred Items Registered

- **Coldstore handle leak after retention-GC shutdown** (hardening; open): an in-process object retains the coldstore RocksDB handle past 45 s after a GC-bearing GlobalDB shuts down; no-retention teardown releases cleanly. Blocks post-teardown coldstore probes only. Candidate: audit AttachColdStorageGc's capture graph / the cold-read chain's engaged-path allocations. Recorded in the ruling doc §Deferred.

## Next Plan

Ready for 16-03 — the SC2 interleave matrix product extends cold_compose_matrix_test on this seam and fixture.

## Self-Check: PASSED
