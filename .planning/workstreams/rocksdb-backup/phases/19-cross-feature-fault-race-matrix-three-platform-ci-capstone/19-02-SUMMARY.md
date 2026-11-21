---
plan: 19-02
phase: 19-cross-feature-fault-race-matrix-three-platform-ci-capstone
completed: 2026-11-20
requirements: [TEST-02]
status: complete
---

# Plan 19-02 Summary: The Erase Arm Crossed — X3/X8 (lost-last-copy gate pair) + X5 (erase-mid-walk skip)

## What Was Built

The erase arm of the matrix is crossed, three cases on the boundaries where the erase cycle's decisions meet durability truth and the recovery walk: X3 (durability flip at the cold gate vs concurrent serves — a serving or state-flipped CID never unlocks an erase that loses the last copy), X8 (rehydrate's re-journaled PendingUpload vs the next cycle's gate — the gate defers, no double-erase; the legal-admission side erases and the post-erase serve is terminally refused), and X5 (erase landing before the walk's visit — evidence means skip, never partial history, never restore). Every case carries its deterministic seam leg plus a real-thread leg, a red-by-design fault arm observed RED under the knob, and fail-closed controls. Production is untouched (zero src diff — no fix-forward was needed; every find was fixture-side).

**The run6 "LegB SEH" is root-caused and closed:** not GossipPubSub/static teardown residue (the prior session's hypothesis) — every `_LegB` case seeded on the tx stack it never built (`gw_account_`/`gw_db_` null; the first `MakeXTransfer`/`SeedX5Graph` dereferenced null, 0xc0000005 ~600 ms in, right after the knobs print). The GossipPubSub timer lines in the logs were the *previous A-case's teardown* — a red herring. Fix: `BuildTxStack()` at the top of X3-B/X8-B/X5-B.

## Key Changes

### Test (one file, +1256 lines)

- `SuperGenius/test/src/crdt/cold_cross_feature_fault_race_test.cpp` — six new cases in the 19-01 grammar:
  - `Cross_DurabilityFlipVsColdGate_ServeNeverUnlocksErase` (X3 seam): shared-block pair reaches real Durable; the `SetColdUploadStateHookForTest` flip arms Pending at the shared consult before the cycle; the gate defers (`cold_deferred_groups ≥ 1`), hot value + raw map survive; no erase batch contains the CID.
  - `Cross_DurabilityFlipVsColdGate_ServeNeverUnlocksErase_LegB` (X3 real-thread + fault arm): leg 1 — the serve COMPLETED on its own thread (cold body, re-warm hot), then the flip defers the cycle (a completed serve never unlocks the erase); leg 2 — the read is PROVABLY in flight across the flip (parked at `kInterruptAfterEvidenceConsult` via `SetColdServeInterruptForTest` + WindowGate; the flip arms while parked), released and joined, then the cycle defers; fault arm (knob) — journal truthful-Durable + remote object deleted → the erase admits and loses the last remote copy → detector RED.
  - `Cross_RehydrateVsSecondErase_GateDefersOnRejournaledPending` (X8 seam): the S3 fake's Put faulted so a re-journal holds at Pending; the twin's marker-less eviction makes the block cold-resident; a cold serve rehydrates (re-journals PendingUpload); the NEXT cycle's gate defers (COLD_NOT_DURABLE) — no second erase of the re-warmed CID.
  - `Cross_RehydrateVsSecondErase_GateDefersOnRejournaledPending_LegB` (X8 real-thread + fault arm): the re-warm completed on the real serve path → the next cycle's LEGAL admission erases (journal monotone: Durable) → the post-erase serve is REFUSED with `HISTORY_PRUNED_LOCALLY` (all-or-nothing on the completed side of the window); fault arm (knob) — journal Pending + gate read flipped to Durable → double-erase of the re-warmed CID with its remote copy gone → detector RED.
  - `Cross_EraseMidWalkVisit_EvidenceSkipsNeverPartial` (X5 seam): deterministic erase-then-walk ordering — the real cycle erases (evidence markers via the real `EraseTransactionEntryPruned` path), then the forced walk completes against the erased state: `skipped_pruned ≥ 1`, zero gaps/errors, the evidenced block never lands hot, `CanRestoreElement` stays false.
  - `Cross_EraseMidWalkVisit_EvidenceSkipsNeverPartial_LegB` (X5 real-thread + fault arm): the walk driven on its own real thread against the same erased state — the skip invariants hold under the real walk; fault arm (knob) — the marker-less erase (plain `EraseEntry`, no `/prune` rows) → the walk RESTORES the erased history → detector RED.
- Fixture/kit shared with 19-01 (hermetic fixture, sanctioned builders, D-08 journal surfaces, `TxRunCycle` settled-cycle discriminator, `SeedX5Graph`, seeding helpers) — zero new knobs, labels, or targets.

## Key Files

**Modified:** `SuperGenius/test/src/crdt/cold_cross_feature_fault_race_test.cpp` (+1256)
**Production:** zero diff — `git -C SuperGenius status --porcelain -- src` empty at commit time.

## Red-First Evidence Trail

1. **run6 (pre-fix baseline):** 6/10 green; X3-B/X8-B/X5-B SEH 0xc0000005; X5A `skipped_pruned` 0-vs-1.
2. **run7:** X3-B leg-1 defer proven live (`erased=0, cold_deferred=1`) but leg 2 wedged — the parked serve inside the cycle deadlocks the erase path (7 min silence, killed).
3. **run8/run9:** the LRU-guard find — `EraseEntry` guard (3) refuses erases of cold-rehydrate re-warmed blocks ("cid … is in the block cache", cycle `errors=1, erased=0`).
4. **run12 (knob ON, pre-arm-fix):** RED-OBSERVED at suite level (4 cases fail) but X8-B's fault arm passed vacuously — the arm's erase was guard-refused, so `erased=0` looked green (toothless-arm find).
5. **run13 (knob ON, final):** RED-OBSERVED with **5/5 fault-arm carriers failing** — X1, X2, X3-B (`the erase landed on a gone-remote CID — the lost-last-copy violation`), X8-B (`the double-erase landed on the re-warmed CID with its remote copy gone`), X5-B (`the erased block was restored hot` / `the erased element became restorable`). Signatures in `.gsd/run13-red-knobon.txt`.

## Verification Results

- Build: `cmake --build … --target cold_cross_feature_fault_race_test --parallel 8` — exit 0 (one pre-existing C4834 warning at L1100, unchanged from 19-01).
- Suite knob-OFF: **10/10 PASSED** (13.0 s; `.gsd/run14-knoboff.txt`).
- Suite knob-ON: **RED-OBSERVED** (exit 1; `VIOLATION-fault-arm-toothless` NOT emitted; 5/5 arms fire; `.gsd/run13-red-knobon.txt`).
- Full Tier-1 lane: `ctest -L Tier1` — **20/20, exit 0** (211.6 s).
- Source gates: X3/X8 case names 6 (≥2); `kInterruptAfterColdGate|SetCycleInterruptHookForTest` 7 (≥2); X5 name 3 (≥1); `kInterruptBeforeErase` 5 (≥1 — now real code, not comments); hand-built `/prune/*` concatenations 0; src diff 0.
- Production untouched: no `fix(19-02)` needed — both the LRU-guard and park-wedge behaviors are in-contract fixture choreography, not defects (guard 3 refusing LRU-resident erases is EraseEntry's designed fail-closed posture).

## Deviations from Plan

**[Rule 1 — per-TEST_F leg split]** X3/X8/X5 were planned as three cases; landed as six (each seam case + a `_LegB` real-thread sibling carrying the barrier-class legs and the fault arms). Rationale: gtest TEST_F bodies cannot restart a wedged leg, and the real-thread legs must die independently of the seam legs. Recorded in the resume plan; carried through.

**[Rule 1 — no-thread GlobalDB legs]** The X3/X8/X5 barrier legs run their real threads to COMPLETION against the shared stack rather than parking a GlobalDB-world serve/walk inside the cycle: parking inside the cycle's erase path deadlocks (run7 evidence — the erase path blocks on the cold-chain locks the parked serve holds). The window-CROSSING park proofs live in the X1/X2 barrier legs (19-01, the same serve path); the completed-side invariants are what X3-B/X8-B/X5-B prove here. In-flight-across-the-flip is still proven (X3-B leg 2 parks the read, arms the flip while parked, releases before the cycle).

**[Rule 1 — monotone journal]** X8 leg B's legal-admission leg relies on the journal staying Durable across the re-warm serve (research Q1: no in-process Durable→Accepted regression) rather than re-journaling to Pending — the re-journal deferral is the SEAM leg's claim (X8A via the faulted-put flip); the leg-B claim is the completed-re-warm + legal-admission + terminal-refusal chain.

**[Rule 2 — the LegB SEH root cause]** All three `_LegB` cases were missing `BuildTxStack()` (null `gw_account_` deref — run6's 0xc0000005). Fixed; the prior session's GossipPubSub/teardown-residue hypothesis is disproven and recorded.

**[Rule 2 — X5 ordering restructure]** X5A's planned mid-visit park (walk fetch parked while the erase commits) wedges in the GlobalDB world (same class as above); the interim walk-then-erase queue race was timing-dependent (run6: local walk always won, `skipped_pruned=0`). Final shape: deterministic erase-then-walk (X5A) + real-thread walk against the erased state (X5B); boundary precision carried by the X1/X2 parks on the same serve path.

**[Rule 2 — park-wedge restructure (X3-B leg 2)]** See above; plus a leak-proof failure path (release+join before the ASSERT returns) so a failed park can never wedge TearDown.

**[Rule 2 — LRU-guard hygiene]** Cold-rehydrate re-warms land in the LRU block cache; `EraseEntry` guard (3) then refuses erases (`errors=1, erased=0`). Three drops added: a quiesce poll at the end of `SeedX5Graph` (covers the fault arms' plain `EraseEntry`), the sanctioned `kInterruptBeforeErase` seam observer in the X5 green legs (inside the cycle, after the READY-announcement traversal re-warms, before the erase — this also satisfies the plan's real-seam requirement), and an LRU drop in the X8 fault arm (run12 toothless-arm find: the arm's cold-serve re-warm cached the block; the refused erase made the detector see the green outcome vacuously).

**[Rule 3 — commit granularity]** The plan specified one commit per task; the interrupted interleaved session (fixture-level fixes spanning both tasks' regions of one file) collapsed them into a single `test(19-02)` commit carrying the full evidence message.

**Total deviations:** 7 (4 recorded-design [per-TEST_F split, no-thread legs, monotone journal, ordering restructure], 3 mechanical/root-cause [SEH fix, park-wedge+leak-proof, LRU hygiene, commit granularity]). **Impact:** none beyond plan intent — every must-have truth is asserted somewhere in the six cases, all observable through the dedicated counters/refusals the plan names.

## Issues Encountered

None open. Scratch evidence: `.gsd/run7..run14*.txt`, `.gsd/commit-1902.txt` (untracked scratch, per the 19-01 convention).

## Self-Check: PASSED

- Both tasks executed (Task 1 X3+X8, Task 2 X5); single collapsed commit `50ad85673` (deviation recorded above).
- All acceptance criteria re-run and passing (see Verification Results).
- SUMMARY created in plan directory; STATE/ROADMAP updated by the orchestrator close-out.
