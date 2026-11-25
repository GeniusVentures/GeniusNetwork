---
plan: 19-03
phase: 19-cross-feature-fault-race-matrix-three-platform-ci-capstone
completed: 2026-11-20
requirements: [TEST-02]
status: complete
---

# Plan 19-03 Summary: The Recovery Arm Crossed — X4/X6 (Task 1) + X7/X9 (Task 2)

## What Was Built

The recovery arm of the fault-race matrix is crossed, four cases at the boundaries where recovery-side work meets eviction, the downgrade interlock, the exemption consult, and the failover budget: X4 (GC eviction mid-walk-restore — the walk's restore of a sealed cold-resident NoEvidence ancestor either completes whole or aborts cleanly, never partial history, while a real GC pass parks between its D-16 halves on its own thread), X6 (the Phase 18 interlock timeline holds across a mid-flight walk — unack'd fires and preserves, the ack lands mid-walk, post-walk the disarm latches), X7 (the exemption consult's NoEvidence/Malformed fail-closed controls abort green-and-stay-green while a real sanctioned /prune/blk write lands on a different cid mid-pass — exactly one exemption), and X9 (budget-boundary classification at exactly `kForcedWalkPeerFailoverPerCid` — read by symbol — one step either side, evidence terminality outranking the full budget, the walk-gap vocabulary distinct from skip, seeded jitter iterations of the budget-armed serve vs the evidence writer). Every case carries red-by-design fault arms observed RED under the knob with signatures recorded; production is untouched (zero src diff — both finds were fixture-level).

## Key Changes

### Test (one file, +1214 lines over two commits)

- `SuperGenius/test/src/crdt/cold_cross_feature_fault_race_test.cpp`:
  - `Cross_GcEvictionMidWalkRestore_RestoreCompletesOrAborts` (X4 seam, Task 1 `6abd028cf`): COMPLETE arm (walk parked at the serve seam via an entered-once guard; GC pass 1 nominates the orphan canary — the linked ancestor is reachability-pinned, asserted; pass 2 parks between halves on a real GC thread; release order walk-then-GC; every CID ends legal: ancestor hot+Durable, head hot, canary reclaimed) + ABORT arm (Malformed value at the ancestor's sanctioned key → the walk ends Incomplete with errors, nothing partial) + fault arm (evidence lands mid-park + the blinded lookup → the evidenced ancestor restores → detector RED).
  - `..._LegB` (X4 barrier): the same choreography iterated under seeded jitter (`SGNS_CROSS_RACE_JITTER_*`), the ancestor S3-only so the fetch really crosses the remote tier (S3 Get op-count asserted).
  - `Cross_DowngradeArmsMidWalk_InterlockHoldsTimeline` (X6 seam, gw tx world): `SeedX5Graph` + walk parked mid-fetch; the FULL interlock timeline through the sanctioned `RoleFingerprint::CheckAndRewrite` writer: (a) mid-walk unack'd → `DowngradeUnacknowledged` + record preserved as Archive, (b) zero `/prune` markers, (c) ack → `DowngradeAcknowledged`, walk releases and completes whole, (d) post-walk re-check → `NoDowngrade` (the disarm latches). Fault arm: torn-ack landing (corrupt value at the production `PRUNE_ROLE_FINGERPRINT_KEY` constant — the 18-01 corrupt-value grammar, never a hand-built key) flips the verdict to `UnreadableDisarm` — detector RED.
  - `Cross_ExemptionConsultVsConcurrentPrune_FailClosedControlsStay` (X7 seam + embedded controls, Task 2 `bdeb9e95c`): NoEvidence and Malformed controls abort green inside the case and re-run green after the fault arm; the seam leg parks the GC pass mid-walk (head forced S3-only, `TimingS3Client` op-barrier) while a real sanctioned write lands on a different cid — `gc_last_pass_exempted == 1` exactly, canary nominated. Fault arm: `forge_pruned_` (the knob-scoped forged-verdict injection in the installed lookup) — the NoEvidence gap wrongly exempts and nominates — detector RED.
  - `Cross_PeerBudgetVsEvidenceTerminality_RefusalNotNotfound` (X9 seam + jitter): budget legs at M ∈ {budget−1, budget, budget+1} via `RegisterFailingRoutes` (deterministic `PeerId::fromHash` + null-graphsync synchronous failures) → `ROUTE_NOT_FOUND` at exactly the symbol-read constant and one step either side; evidence terminality (`HISTORY_PRUNED_LOCALLY`) at the full budget, never the peer leg; step-3 observe leg (a resolved node serves); walk leg (exhaustion → `walk_gaps ≥ 1`, `skipped_pruned == 0` — gap ≠ skip); seeded jitter iterations through the barrier helper's new `failover_budget` parameter; fault arm: blinded consult at the seam point — the evidenced cid serves, the vocabulary lost — detector RED.
  - Fixture additions: `SetOrphan`/`BackdateCid` (the 18-01 shapes, in-file per D-05), `RegisterFailingRoutes`, `MakeManager(grace_ms)`, the `forge_pruned_` fault-arm flag, and the optional budget on `RunServeVsEvidenceWriterBarrier`.

## Key Files

**Modified:** `SuperGenius/test/src/crdt/cold_cross_feature_fault_race_test.cpp` (+683 then +531)
**Production:** zero diff — `git -C SuperGenius status --porcelain -- src` empty at both commit times.

## Finds (fixture-level, no fix-forward needed)

1. **The grace zero-sentinel (run3, Task 1):** `RetentionDormant`'s "explicit zero grace" posture never evicts — `ColdStorageManager`'s ctor rewrites `grace_ms == 0` to `kDefaultGraceMs = 60000`. Diagnosed with a temporary unhooked probe pass (evicting-count 1, reclaimed 0), fixed by `MakeManager(grace_ms)` passing the v1.1 evict-serve recipe's 1 ms + the 3 ms elapse wait. The 18-01 suite never exercised `ProcessDueMarks`, so the misleading zero had gone unnoticed.
2. **The walk topic guard (run1, Task 1):** the hermetic `crdt_->RequestForcedWalk` rejects unenrolled topics (`invalid_argument`) — the gw stack had enrolled via `AddListenTopic`; the hermetic cases now call `AddTopicName`.
3. **The S3-park collision (design-time, Task 1):** the plan's S3 op-barrier park for the walk's fetch collides with the GC pass's own `WalkReachable` reads of the same cold-resident CID; the entered-once serve-seam park separates them exactly (the walk's `GetNodeWithRouteBudget` parks; the GC's `GetNodeWithoutRequest` firings pass through after the first).
4. **The one-fixture-many-passes GC walk universe (Task 2):** `GcPassOnce`'s walk starts from EVERY topic's heads, so an unhealed gap from an earlier block aborts every later pass in the same fixture — X7's blocks heal their gaps (republish; the journal is monotone-Durable so nothing re-journals) and rejuvenate their canaries (`SetSpilledAt(now)`).

## Red-First Evidence Trail

1. **run1:** X6 green first-try; X4/X4-B failed at walk queue (`invalid_argument` — find 2).
2. **run2:** the topic fix landed the walk park; both failed at the GC between-halves park (pass completed without parking).
3. **run3/run4 (probe):** `evicting=1, reclaimed=0` with no cancel/failure logs — the unhooked probe pass proved the mark never came due → the grace zero-sentinel (find 1).
4. **run5:** X4/X4-B green — the eviction lands ("gc: evicted - reclaimed N local byte(s)"), the walk completes whole across it.
5. **run6 (knob-OFF):** 13/13 PASSED. **run7 (knob-ON):** RED-OBSERVED, 7/7 carriers (X1, X2, X3-B, X8-B, X5-B + the new X4, X6).
6. **run9 (knob-OFF, full):** 15/15 PASSED (13.9 s). **run10 (knob-ON):** RED-OBSERVED, **9/9 carriers** — X7 ("the wrongly-exempted gap let the pass complete and nominate") and X9 ("the blinded consult let the evidenced cid SERVE") added. **run11:** Tier-1 20/20, exit 0.
7. Scratch evidence: `.gsd/x4-run1..5.txt`, `.gsd/run6..run11*.txt` (untracked scratch, the 19-01 convention).

## Verification Results

- Build: `cmake --build … --target cold_cross_feature_fault_race_test --parallel 8` — exit 0 (the pre-existing C4834 warning, line-shifted only).
- Suite knob-OFF: **15/15 PASSED** (run9b per-case listing).
- Suite knob-ON: **RED-OBSERVED** (exit 8; `VIOLATION-fault-arm-toothless` NOT emitted; 9/9 arms fire).
- Full Tier-1 lane: `ctest -L Tier1` — **20/20, exit 0**.
- Source gates (Task 1): X4/X6 case names 5 (≥2); `SetGcBetweenHalvesHookForTesting|SetGcPreHalfOneHookForTesting` 7 (≥1); src diff 0. (Task 2): X7/X9 case names 4 (≥2); `SGNS_CROSS_RACE_JITTER_SEED|kForcedWalkPeerFailoverPerCid` 9 (≥2); hand-built `/prune/*` concatenations **0** (`clean`); src diff 0.

## Deviations from Plan

**[Rule 1 — X4's eviction target and park instrument]** The plan's S3 op-barrier park for the walk's restore fetch collides with the GC pass's own walk reads (find 3); the entered-once serve-seam park replaces it. The same-CID eviction is architecturally impossible on the landed line for a LEGAL eviction (a linked ancestor is reachability-pinned — heads by construction, transitive links unconditionally traversed); the case therefore PROVES the pin (candidates == [canary] asserted, the ancestor never nominated) and carries the same-CID half-evicted state only in the fault arm. The plan's own prohibition discipline ("never relax production to make a leg green") cuts symmetrically against unpinning reachability to force an eviction.

**[Rule 1 — X4 abort arm via Malformed]** The "cleanly ABORTED" half of the dichotomy is exercised through the Malformed consult (fail-closed error → Incomplete with errors), the strongest deterministic abort arm available at the walk's own boundary; the evidence-skip arm is X5's landed seam leg.

**[Rule 1 — X6 arm shape]** The fault arm's torn-ack landing is a corrupt-VALUE at the production key constant (the sanctioned corrupt-input grammar) rather than a row delete: the delete has no sanctioned surface, and `UnreadableDisarm`-vs-`DowngradeUnacknowledged` is the sharper detector anyway (the verdict distinguishes them, proving the timeline teeth).

**[Rule 1 — X9 route fabrication]** M-exact budget legs need M distinct failing routes; hermetic fabrication via `PeerId::fromHash` + `Multiaddress::create` on the null-graphsync syncer (each route fails synchronously at `RequestNode`, blacklists, advances the ladder). The blacklist persists per peer — fresh salts per leg keep the M counts exact.

**[Rule 3 — X7/X9 in two commits]** One commit per task per the plan's commit granularity (the 19-02 collapsed-commit deviation did not recur).

**Total deviations:** 5 (4 recorded-design, 1 granularity-avoided). **Impact:** none beyond plan intent — every must-have truth is asserted; the four cases carry seam + real-thread/jitter layers with teeth on record.

## Issues Encountered

None open. The two fixture finds (grace zero-sentinel, topic guard) are recorded above and in the commit messages.

## Self-Check: PASSED

- Both tasks executed and committed atomically (`6abd028cf`, `bdeb9e95c`).
- All acceptance criteria re-run and passing (see Verification Results).
- SUMMARY created in plan directory; STATE/ROADMAP updated by the orchestrator close-out.
