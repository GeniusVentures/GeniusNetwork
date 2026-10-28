---
phase: 12
plan: 01
subsystem: cold-storage
tags: [cold-storage, gc, fault-race, resurrection, testing]
requires: []
provides:
  - "D-11 fault-race matrix: deterministic barrier-driven evict/serve/drain crossings, zero Corrupt-from-race, D-12 audit walk"
  - "SC2 resurrection counter-tests: marker dedup, trimmed-marker tombstone dominance, full-wire two-GlobalDB re-delivery"
  - "D-16 GC test seams (between-halves, pre-mark-process, pre-half-one) + TimingS3Client decorator + stack client-override seam"
affects: []
tech-stack:
  added: []
  patterns:
  - "WindowGate enter/release latch for deterministic race parking (cv-based, no fixed sleeps)"
  - "TimingS3Client outermost S3Client decorator: latency + on-op barrier + seeded jitter outside every inner lock"
key-files:
  created:
  - SuperGenius/test/src/crdt/cold_storage_fault_race_test.cpp
  - SuperGenius/test/src/crdt/cold_storage_resurrection_test.cpp
  modified:
  - SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp
  - SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStackStub.cpp
  - SuperGenius/src/crdt/impl/crdt_set.cpp
  - SuperGenius/test/src/crdt/CMakeLists.txt
key-decisions:
  - "SC2 eviction shape carries the Phase-11 exactness lemma: the tombstone delta LINKS the put delta, so the detach (RemoveHead) is required to reach the evictable state - tombstone rows never purged keep the value dead"
  - "InElemsNotTombstoned empty-elems return-true was a production-reachable resurrection defect; fixed to not-in-set (go-ds-crdt semantics), SuperGenius-side only (no library tag re-cut)"
requirements-completed: []
duration: 165 min
completed: 2026-10-28T18:25:00Z
coverage:
  - description: "Tracer: barrier-driven evict-x-serve crossing resolves CID-verified from S3"
    verification: { kind: test, ref: "SuperGenius/test/src/crdt/cold_storage_fault_race_test.cpp#EvictServe_HalfWindowS3Fetch_ResolvesCidVerified", status: pass }
    human_judgment: false
  - description: "Nine D-11 crossings + knife edge deterministic green"
    verification: { kind: test, ref: "SuperGenius/test/src/crdt/cold_storage_fault_race_test.cpp#matrix", status: pass }
    human_judgment: false
  - description: "D-12 audit walk + zero-blacklist + byte-flip teeth"
    verification: { kind: test, ref: "SuperGenius/test/src/crdt/cold_storage_fault_race_test.cpp#SuiteEnd_AuditWalk_EveryCidInLegalState", status: pass }
    human_judgment: false
  - description: "Seeded jitter legs (SGNS_RACE_JITTER_SEED/_ITERS env knobs)"
    verification: { kind: test, ref: "SuperGenius/test/src/crdt/cold_storage_fault_race_test.cpp#Jitter_PairwiseSeededIterations_EndStateInvariants", status: pass }
    human_judgment: false
  - description: "SC2 marker-present dedup blocks reintegration with zero S3 Gets"
    verification: { kind: test, ref: "SuperGenius/test/src/crdt/cold_storage_resurrection_test.cpp#Resurrect_MarkerPresent_DedupBlocksReintegration", status: pass }
    human_judgment: false
  - description: "SC2 trimmed-marker tombstone dominance keeps value absent"
    verification: { kind: test, ref: "SuperGenius/test/src/crdt/cold_storage_resurrection_test.cpp#Resurrect_TrimmedMarker_TombstoneDominanceKeepsValueAbsent", status: pass }
    human_judgment: false
  - description: "SC2 full-wire two-GlobalDB re-delivery stays deleted (real gossip wire, background GC, hermetic fakes)"
    verification: { kind: test, ref: "SuperGenius/test/src/crdt/cold_storage_resurrection_test.cpp#Resurrect_FullWire_TwoGlobalDBRedeliveryStaysDeleted", status: pass }
    human_judgment: false
  - description: "Full Tier-1 lane stays green fail-closed with both new suites"
    verification: { kind: command, ref: "ctest -L Tier1 (10/10 passed, SuperGenius Windows Debug)", status: pass }
    human_judgment: false
---

# Phase 12 Plan 01: Fault-Race Matrix & Resurrection Counter-Test Summary

SC1+SC2 of TEST-02 proven executable: 13 fault-race tests (deterministic barrier-driven evict-x-serve-x-drain matrix, seeded jitter, D-12 audit walk) and 3 resurrection counter-tests (marker dedup, tombstone dominance, full-wire two-GlobalDB) — plus a production resurrection defect found and fixed.

## Accomplishments

- **D-16 GC test seams** (SetGcBetweenHalvesHookForTesting, SetGcPreMarkProcessHookForTesting, SetGcPreHalfOneHookForTesting) in the exact SetGcMidPassHookForTesting shape: swap under gc_hook_mutex_, null in production, invoked OUTSIDE cold_store_mutex_ at the named ProcessDueMarks anchors (HALF2 structure unchanged — Pitfall 6 respected).
- **TimingS3Client** test-local decorator (outermost around the counting wrapper): bounded per-op latency, on-op barrier hooks fired outside every inner lock (Pitfall 7), seeded bounded jitter — zero library change, no D-14 re-cut.
- **Tracer green**: GC parked in the HALF1-committed/HALF2-not-started window while the serve's S3 fetch was held mid-flight; fetch released FIRST resolves CID-verified with original bytes; end state disposed-with-remote-copy; second read zero S3 Gets.
- **Full D-11 matrix** (13 TEST_F total): hot-cleanup-window reader never torn; re-warm attach vs mark never loses a block; eligibility never evicts non-Durable (compile-time gate held under a parked drain Put); drain snapshot never holds evicted bytes (HALF1 atomic); remote-lock latency fetch inside the 4 s re-warm budget with honest COLD-classified decline; triple crossings (reachable-again cancel keeps bytes; delete-batch mid-flight re-delivery drops at the marker with drain unaffected); cancel-vs-commit knife edge whole-never-torn; seeded jitter legs (default 200 iters, env-reproducible); D-12 audit walk (every published CID in exactly one legal state); zero storage-attributed blacklist writes; byte-flip control keeps the zero-Corrupt assertions honest.
- **SC2 three lines**: (1) 25 pubsub-path re-deliveries drop at the disposed marker with zero S3 Gets and zero re-journal; (2) after TrimDisposed erases the dedup line, the merge runs and tombstone dominance keeps the value absent (the re-learn re-journals per the documented contract); (3) the full-wire two-GlobalDB case over the real in-process libp2p+graphsync wire with cold storage ON on the receiver through the new hermetic stack-override seam — background GC eviction proven via GetColdStorageStatus disposed markers, node-1 re-broadcast of the original CID announcement drops on the receiver with zero S3 Gets / zero pending, value absent on both nodes.
- **Production defect fixed (failing-first)**: InElemsNotTombstoned returned true on an EMPTY elems enumeration; once the retention GC's hot cleanup deleted the last elems row of a CRDT-deleted key, queries listed the protected value row and the deleted key resurfaced as present (the surviving tombstone row was never consulted). Both single-node legs were RED against the unfixed tree; fixed to not-in-set (go-ds-crdt semantics), full Tier-1 lane green after.

## Task Execution

| Task | Commit | Files | Tests |
|------|--------|-------|-------|
| 1 tracer (seam + decorator + crossing) | e2fb50709 | 4 | EvictServe_HalfWindowS3Fetch_ResolvesCidVerified green |
| 2 matrix + jitter + audit | 0b3a4a46f | 3 | 13/13 green, Tier-1 10/10 |
| 3 resurrection suite + defect fix | f35895fca, d8a7371c9 | 7 | 3/3 green, combined 2/2, Tier-1 10/10 |

## Deviations from Plan

- **[Rule 1 - Missing critical enabler] Stack fake-injection factory did not exist.** Found during: Task 3. The plan's full-wire case assumed "the ColdStorageOptions stack factory the spill suites already use" — no such seam existed (OpenColdStorageStack hard-builds OpenMinioS3Client/OpenS3dAdminClient; spill suites construct the stack directly). Fix: added the TEST-ONLY SetColdStorageStackClientsForTesting override (null default = production path byte-identical; forward-decl-only in the always-compiled header, statics in the gated TU, no-op stub on OFF builds). Files: ColdStorageStack.hpp/.cpp/Stub.cpp. Verification: full-wire leg green hermetically (zero network). Commit d8a7371c9.
- **[Rule 1 - Plan bug] put+delete+evict sequence unreachable as written.** Found during: Task 3. The tombstone delta LINKS the pre-delete delta (every Publish points at previous heads), so GC-01's reachability walk correctly pinned BOTH — GcPassOnce would nominate nothing. Fix: DeleteAndEvict adds the RemoveHead detach after the delete (the Phase-11 EvictDetachedDelta mechanics; tombstone ROWS are never purged so the value stays dead) and expects two candidates. Verification: both legs + full-wire leg green. Commit d8a7371c9.
- **[Rule 1 - REAL DEFECT, failing-first] InElemsNotTombstoned empty→true resurrection.** Found during: Task 3 legs 1/2 (RED with zero S3 Gets + zero re-journal yet value visible). Root cause: GC hot cleanup deletes an evicted delta's own elems rows; with the key's last elems row gone, the empty enumeration returned "not tombstoned" and QueryElements listed the protected value row. Production-reachable through ordinary history eviction. Fix: empty enumeration returns not-in-set (upstream semantics), guarded comment on the SC2 contract. Files: SuperGenius/src/crdt/impl/crdt_set.cpp. Verification: legs green; full Tier-1 10/10 (no regressions). Commit f35895fca. SuperGenius-side only — NO library change, no D-03 tag re-cut note for 12-03.
- **[Rule 3 - Environment] Zombie compiler processes locked the new test file** (three orphaned cl.exe from interrupted builds held an exclusive handle; editor saves silently failed while a stale on-disk copy kept compiling). Fix: killed the orphans, patched on disk, verified by grep before rebuilding. No product impact.
- **[Rule 3 - Flake, non-reproducing] cold_storage_durability_test failed once in the first full-lane run** (passed standalone and in the lane rerun; order/load-dependent timing on this dev box). Logged for the 12-02 soak work; no code change.

**Total deviations:** 5 (2 enabler fixes, 1 defect fix, 2 environmental). **Impact:** the full-wire case is hermetic as the prohibitions demand; the resurrection defect is closed at the exact layer D-13 named; SC1/SC2 evidence is deterministic and reproducible.

## Issues Encountered

None open. The durability-flake observation above is recorded, not blocking.

## Next Phase Readiness

Ready for 12-02 (s3d-unavailable soak) — the TimingS3Client decorator and WindowGate instruments are committed and reusable; the stack-override seam enables any future full-stack hermetic scenario.

## Self-Check: PASSED

- All 12-01 verify commands re-run green: builds (both targets), ctest -R per suite, ctest -R combined (2/2), ctest -L Tier1 (10/10), seam greps (3 refs between-halves; pre-mark/pre-half-one declared + invoked; RunHotCleanup call-site count 1), TEST_F count 13, sleep_for confined to PollUntil.
- Acceptance criteria per task: 6/6, 5/5, 5/5.
- Commits: SuperGenius dev_blockstore e2fb50709, 0b3a4a46f, f35895fca, d8a7371c9; root pointer bumps 7feaa26, 5ddbe73, d97ef23.
