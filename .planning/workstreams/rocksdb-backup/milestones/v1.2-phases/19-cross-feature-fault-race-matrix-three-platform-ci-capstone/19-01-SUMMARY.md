---
plan: 19-01
phase: 19-cross-feature-fault-race-matrix-three-platform-ci-capstone
completed: 2026-11-20
requirements: [TEST-02]
status: complete
---

# Plan 19-01 Summary: Serve Interrupt Seam + Cross-Feature Fault-Race Sibling Born Red (X1/X2)

## What Was Built

The phase tracer, live end-to-end: the serve path on `GraphsyncDAGSyncer` is now interruptible at three named, documented, production-null boundaries (the TxPruner `kInterrupt*` seam family mirrored onto the evidence-aware cold serve path), and the D-02 sibling suite `cold_cross_feature_fault_race_test` exists, is Tier-1 registered with the resurrection link set, and hosts the serve pair X1/X2 complete — deterministic seam legs, NoEvidence controls, red-by-design fault arms, and real-thread barrier legs (D-03 two-layer discipline). Plans 19-02 through 19-04 only add cases to a proven harness.

**The red-first find the plan anticipated landed as expected:** the X1 seam leg observed the unguarded consult→Get window on the unmodified line (single-consult serve path, SERVE-01/02) — an erase marker committing mid-serve resurrected the CID through the cold chain (served + rehydrated hot + LRU-cached). Fixed forward as `fix(19-01)` with the minimal guard-5-shaped re-checks (one re-consult before the cold Get, one before Rehydrate) — the Phase 16 D-03 repair-the-half precedent. X2's window (Get→Rehydrate) was closed by the same guard; its seam leg proves that site exactly.

## Key Changes

### Production (test-only seam, production-null)
- `SuperGenius/src/crdt/graphsync_dagsyncer.hpp` — `kInterruptAfterEvidenceConsult = 1`, `kInterruptBeforeRehydrate = 2`, `kInterruptAfterColdFetch = 3`, `static SetColdServeInterruptForTest(std::function<bool(int)>)` (true = abort semantics per step, "no production caller" doc contract, fixture leak-discipline note), private hook storage + dispatcher.
- `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` — three wired sites with boundary-named comments (X1 consult-to-Get gap inside `FetchNodeFromColdStorage`; X2 Get-to-Rehydrate gap inside `FetchNodeFromColdStorage`; X9 terminality point in `GetNodeWithRouteBudget` before the SERVE-04 check — exercised by plan 19-03). **Plus the fix(19-01) re-checks**: one `LookupPruneEvidence` re-consult after each of the step-1/step-2 seams (before the cold Get, before Rehydrate), same terminal semantics as the top consult (Pruned → `HISTORY_PRUNED_LOCALLY` with bytes discarded; Malformed → `PRUNE_EVIDENCE_CORRUPT`; no peer fall-through). Hooks fire outside `dagMutex_` by construction; the parked-Get barrier sits under `remote_store_mutex_` which the evidence writer never touches.

### Test
- `SuperGenius/test/src/crdt/cold_cross_feature_fault_race_test.cpp` (NEW, ~1170 lines) — Doxygen header with the D-01..D-08 case grammar (X1..X11 table), the per-case red-first declaration, and the `notes/19-*` matrix-table pointer; the 18-01 hermetic fixture verbatim (real hot RocksDB + LocalBlockStore cold dir + InMemoryS3*/S3BlockStore + real ColdReadService/GraphsyncDAGSyncer with the sanctioned-builder evidence lookup + real CrdtDatastore + AttachGcDependencies, gc_interval_ms=0); in-file kit re-declared (PollUntil, leak-proof WindowGate, TimingS3Client with suite-local per-op counters, EnvOr/KnobEnabled); all four `SGNS_CROSS_RACE_*` knobs declared with the print-values first-log-line convention; suppression-capable lookup (fault arms only, knob-gated); TearDown clears the seam hook first (leak discipline). Four cases:
  - `Cross_EraseCommitVsServe_EvidenceLandsMidConsult` (X1): seam leg (evidence at step 1 → refusal, no hot re-add, no peer fall-through) + NoEvidence control (serves verbatim, rehydrates hot) + fault arm (blinded lookup → resurrection → audit fails RED).
  - `Cross_EraseCommitVsServe_InflightColdGetNoRehydrateAfterEvidence` (X2): step-2 seam leg (evidence after cold Get returns bytes → bytes discarded, refusal) + control (rehydrates) + fault arm (RED).
  - `Cross_EraseCommitVsServe_EvidenceLandsMidConsult_RealThreadBarrier` (X1 layer two): real serve thread vs real evidence-writer thread, parked inside the S3-tier Get via the TimingS3Client op-barrier (local cold evicted so the read crosses S3); WindowGate forces the collision ordering; end-state invariant asserted (refusal, no evidenced CID hot, S3 crossing proven via op counts, no torn serve).
  - `Cross_EraseCommitVsServe_InflightColdGetNoRehydrateAfterEvidence_RealThreadBarrier` (X2 layer two): the same collision iterated under seeded jitter (`SGNS_CROSS_RACE_JITTER_ITERS`, default 3) with per-iteration seeds.
- `SuperGenius/test/src/crdt/CMakeLists.txt` — the `cold_cross_feature_fault_race_test` registration inside `if(SGNS_COLD_STORAGE)`: resurrection link set copied verbatim (`crdt_mirror_broadcaster.cpp` second source, `genius_node_test` whole-archive triad, `p2p_logger`, AsyncIOManager include), `LABELS "Tier1"` (joins the label set — no new label name; D-11).

## Key Files

**Created:** `SuperGenius/test/src/crdt/cold_cross_feature_fault_race_test.cpp`
**Modified:** `SuperGenius/src/crdt/graphsync_dagsyncer.hpp`, `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp`, `SuperGenius/test/src/crdt/CMakeLists.txt`

## Red-First Evidence Trail

1. **X1 fault arm teeth (knob ON, pre- and post-fix):** all three detector assertions fired — serve completed under the blinded lookup, evidenced CID in LRU, evidenced CID hot (`RED-OBSERVED`, ctest exit 8).
2. **X1 seam leg find (knob OFF, pre-fix):** `X1 seam leg: evidence landing mid-consult must refuse the serve` Actual:false; evidenced CID hot Actual:true — the red-first find (commit `3e3e970e4`).
3. **Post-fix:** knob OFF 1/1 PASSED (seam legs refuse; controls serve verbatim); knob ON RED-OBSERVED with both X1+X2 fault arms failing and both barrier legs green (commit `7748752c1` state).

## Verification Results

- Build: `cmake --build SuperGenius/build/Windows/Release --config Release --target cold_cross_feature_fault_race_test --parallel 8` — exit 0.
- Suite knob-OFF: `ctest -R cold_cross_feature_fault_race_test --no-tests=error` — 1/1 (4 cases, 2.74s), exit 0.
- Suite knob-ON: RED-OBSERVED (exit 8; `VIOLATION-fault-arm-toothless` did NOT fire).
- Full Tier-1 lane: `ctest -L Tier1 --no-tests=error` — **20/20, exit 0** (was 19/19 pre-phase; the new suite joined as Test #108), incl. `tier1_static_audit` (label parity + gated-link parity held).
- `ctest -L Tier1 -N` lists the suite; hpp 8 symbol hits; cpp 3 wired sites; CMakeLists 8 refs; frozen v1.1 `cold_storage_fault_race_test.cpp` zero diff; 0 hand-built `/prune/*` concatenations; `sleep_for` count = 1 (PollUntil body only).
- Production-file commit audit: only `test(19-01)`/`fix(19-01)` touched the seam files (in contract).

## Deviations from Plan

**[Rule 1 - red-first find, expected by the plan's escape clause] X1/X2 serve TOCTOU windows unguarded on the landed line** — Found during: Task 1 RED observation. The single-consult serve path left both the consult→Get and Get→Rehydrate windows open (evidence committing mid-serve resurrected the CID). Fix: `fix(19-01)` minimal re-checks at the two seam sites (guard-5 precedent — repair the half, keep the design). Files: `graphsync_dagsyncer.cpp`. Verification: knob-OFF green, knob-ON teeth intact, full Tier-1 20/20. Commit `723189461`.

**[Rule 2 - compile fixes] Kit type aliases** — the in-file TimingS3Client copy needed `using` declarations for `result`, `S3PutResult`, `S3Object`, `S3HeadResult`, `PutObjectOptions` from `sgns::blockstore` (the v1.1 original relied on its own file-local alias set). Two build iterations. No design change.

**[Rule 3 - scan compliance] Comment wording vs the sleep_for≤1 scan** — the plan's automated check counts textual `sleep_for`; four comment mentions tripped it. Reworded the comments (the single PollUntil-body call remains the only occurrence). No behavior change.

**Total deviations:** 3 (1 expected red-first find + fix, 2 mechanical). **Impact:** none beyond plan intent — the fix-forward was the plan's own escape clause; the suite and lane contract hold exactly as specified.

## Issues Encountered

None open. (PS 5.1 quoting required running the acceptance scans from a script file — `.gsd/verify-1901.ps1`, untracked scratch.)

## Self-Check: PASSED

- All tasks executed (Task 1 tracer + Task 2), each committed individually (`3e3e970e4`, `723189461`, `7748752c1`)
- All acceptance criteria re-run and passing (see Verification Results)
- SUMMARY created in plan directory; STATE/ROADMAP updated by the orchestrator close-out
