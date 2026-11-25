---
phase: 15-evidence-aware-cold-serving-forced-walk-recovery
verified: 2026-11-24T21:10:00Z
status: passed
score: 28/28 must-haves verified
covered_files:
  - .planning/workstreams/rocksdb-backup/phases/15-evidence-aware-cold-serving-forced-walk-recovery/15-01-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/15-evidence-aware-cold-serving-forced-walk-recovery/15-01-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/15-evidence-aware-cold-serving-forced-walk-recovery/15-02-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/15-evidence-aware-cold-serving-forced-walk-recovery/15-02-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/15-evidence-aware-cold-serving-forced-walk-recovery/15-03-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/15-evidence-aware-cold-serving-forced-walk-recovery/15-03-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/15-evidence-aware-cold-serving-forced-walk-recovery/15-REVIEW.md
  - .planning/workstreams/rocksdb-backup/phases/15-evidence-aware-cold-serving-forced-walk-recovery/15-REVIEW-DISPOSITION.md
  - .planning/workstreams/rocksdb-backup/phases/15-evidence-aware-cold-serving-forced-walk-recovery/15-UAT.md
  - SuperGenius/src/account/proto/SGTransaction.proto
  - SuperGenius/src/crdt/cold_read_fallback.hpp
  - SuperGenius/src/crdt/crdt_datastore.hpp
  - SuperGenius/src/crdt/globaldb/ColdReadService.cpp
  - SuperGenius/src/crdt/globaldb/ColdReadService.hpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStackStub.cpp
  - SuperGenius/src/crdt/globaldb/globaldb.cpp
  - SuperGenius/src/crdt/globaldb/globaldb.hpp
  - SuperGenius/src/crdt/graphsync_dagsyncer.hpp
  - SuperGenius/src/crdt/impl/crdt_datastore.cpp
  - SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp
  - SuperGenius/src/transaction/PruneEligibility.cpp
  - SuperGenius/src/transaction/PruneEligibility.hpp
  - SuperGenius/src/transaction/TransactionManager.cpp
  - SuperGenius/src/transaction/TransactionManager.hpp
  - SuperGenius/src/transaction/TxPruner.cpp
  - SuperGenius/test/src/blockchain/CMakeLists.txt
  - SuperGenius/test/src/blockchain/node_startup_test.cpp
  - SuperGenius/test/src/crdt/CMakeLists.txt
  - SuperGenius/test/src/crdt/cold_evidence_matrix_test.cpp
  - SuperGenius/test/src/crdt/cold_prune_gate_test.cpp
  - SuperGenius/test/src/crdt/globaldb_erase_test.cpp
covered_digest: "v2:sha256:eb370076e45012db1244be9939d6ca1b513f729c2707db0e6a9fe1472f32a382"
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: human_needed
  previous_score: 27/28
  gaps_closed:
    - "PROBE-LIFT SERVE-01 concurrency backstop: upgraded from PRESENT_BEHAVIOR_UNVERIFIED to VERIFIED — CR-01 fixed forward in phase 19 plan 19-01 (X1 re-consult before the cold Get, X2 re-consult before Rehydrate) and proven by the named X1/X2 fault legs re-run by this verifier (2/2 PASSED)"
    - "Human item 1 (CR-01 disposition): RESOLVED — 15-UAT.md test 1 pass (ruling (a): accept deferral, fix landed and proven in 19-01)"
    - "Human item 2 (executor-push posture): RESOLVED — 15-UAT.md test 2 pass (standing manual-push rule confirmed; commits local at verification time)"
  gaps_remaining: []
  regressions: []
---

# Phase 15: Evidence-Aware Cold Serving & Forced-Walk Recovery — Re-Verification Report (Regenerated)

**Phase Goal:** Evidence outranks bytes on every path — fixes the cold-chain resurrection gap and the forced-walk GC-evicted conflation; hermetic tri-state evidence fakes land here.
**Verified:** 2026-11-24T21:10:00Z
**Status:** passed
**Re-verification:** Yes — full regeneration against current HEAD (prior 2026-11-17 report was stale: phases 16–19 legitimately modified the same files after it)

**Codebase under verification:** SuperGenius submodule, branch `dev_coldstorage_additions`, HEAD `41776b0c03ea715d36e871ed9471f6ac529fa23f` (`41776b0c0`, verified via `git rev-parse HEAD`; tree clean apart from untracked `test-data/`). This is the final lineage after phases 16 (TxPruner×GC hardening), 17 (seal measurement), 18 (downgrade interlock + GC walk-gap exemption), and 19 (cross-feature fault-race matrix + 3-platform CI) — all of which built forward on this phase's files. Source drift since the prior verification was treated as legitimate forward work and NOT regression, EXCEPT where a phase-15 must-have no longer holds — none was found to fail.

## Re-Verification Scope

Per the re-verification protocol, the previously-unverified/failed item received full 3-level verification and the 27 previously-passed truths received quick regression checks (existence + wiring + semantic spot re-reads) at current HEAD. Both prior human-verification items were checked against the completed UAT record (`15-UAT.md`, status `complete`, 2/2 passed, updated 2026-11-24T20:07:00Z, commit `0855164`).

## Goal Achievement

### Observable Truths

Full truth definitions per plan are unchanged from the 2026-11-17 verification (15-01: 13 truths, 15-02: 7, 15-03: 8 — reloaded from the three PLAN frontmatters). Statuses below are AT CURRENT HEAD `41776b0c0`.

#### Plan 15-01 (13 truths) — the serving tracer

| # | Truth (abbreviated) | Status | Evidence at current HEAD |
|---|---------------------|--------|--------------------------|
| 1 | SC1: getNode/GetNodeWithoutRequest refuse `/prune/blk`-marked CIDs (`HISTORY_PRUNED_LOCALLY`) even with cold bytes; consult precedes cold Get AND Rehydrate; re-warm skips | ✓ VERIFIED | Initial consult at top of hooked path (`graphsync_dagsyncer.cpp:907-916`) before the cold Get; NoEvidence-only path reaches `Rehydrate` (`:991`); `GetNodeWithoutRequest` returns the cold-leg result (`:871-874`); re-warm consult skips Pruned/Malformed (`ColdReadService.cpp:439-445`); S1 + `Rewarm_PrunedEvidenceSkipsRewarmWorker` + `Masquerade_PrunedMarkerWithColdBytesStillRefuses` in the suite (32/32 green, re-run this session) |
| 2 | SC2: no-evidence CID with cold bytes serves verbatim (evict ≈ DETACH) | ✓ VERIFIED | NoEvidence `break` into the v1.1 serve body (`:917-918`, comment "SC2: the existing v1.1 serve path, unchanged"); S2, `NoHot_Cold_None` cell, `Masquerade_EvictedColdBytesNoMarkerServesAndStaysArchive` |
| 3 | Node-local terminality: refusals never fall through to the peer leg (before GetRouteKeys) | ✓ VERIFIED | `:466` early-returns both refusal values; stub leg `StubPredicate_ClassifiesConsultAndServeTerminalityTableDriven` (:1948); every re-consult arm also returns terminal refusals with "never a peer fall-through (SERVE-04)" comments (`:960-983`) |
| 4 | Distinctness: appended Error values with own string cases; never folded into CID_NOT_FOUND | ✓ VERIFIED | Enum appended after `COLD_STORAGE_UNAUTHORIZED` (`graphsync_dagsyncer.hpp:103-110`); string cases (`graphsync_dagsyncer.cpp:94-96`); proto `PrunedBlockRecord` node-local (`SGTransaction.proto:85-89`, "NEVER a wire format") |
| 5 | Fail-closed malformed (incl. zero-length) on both decode surfaces | ✓ VERIFIED | `globaldb.cpp:902-911` (`marker.value().empty()` → Malformed, "failing closed"); `PruneEligibility.cpp:328` (same check in the walk/gate decoder); S4 + Garbage/Empty product cells |
| 6 | D-01 atomic staging: one erase = ONE WriteBatch with both marker pairs; widening touches parameter + staging loop only | ✓ VERIFIED | Vector signature `globaldb.cpp:1586`; staging loop `:1722-1724`; post-phase-15 commits did not alter EraseEntry internals (4f7281b1f inserted only the additive test-only `SetGcMidPassHookForTest` immediately before it); `ColdPruneEraseInterruptTest` steps 1/2/3 in the gate suite |
| 7 | D-02 record shape: PrunedBlockRecord with tx-hash back-reference + erased-at generation threaded from RunCycle | ✓ VERIFIED | `BuildPruneBlockMarkerEntry` (`PruneEligibility.cpp:349-371`); proto fields 1-3 confirmed; TxPruner generation threading (unchanged since phase 15); S3 + gate legs assert hash + generation |
| 8 | D-03 fresh start: no backfill, no /prune/tx-scan fallback | ✓ VERIFIED | Production consult remains a single GetRaw point lookup inside the GlobalDB lambda (`globaldb.cpp:870-911`, NOT_FOUND → NoEvidence at `:885-887`); no scan code anywhere in the consult path |
| 9 | D-04: HasBlock four-term bool byte-preserved; one predicate at the OpenColdStorageStack seam | ✓ VERIFIED | `HasBlock` still `outcome::result<bool>` at `:812`; single predicate = the GlobalDB lambda via `SetPruneEvidenceLookupOnColdReadService` (`globaldb.cpp:870`); flip-legs `ConsistencyFlip_EveryClassifyingSurfaceMovesTogether` + `Rewarm_ConsistencyFlipMirrorsServeSurfaces` green |
| 10 | Disabled-build bar: null hook → no consult, byte-identical reads | ✓ VERIFIED | Null-hook early return before any consult (`graphsync_dagsyncer.cpp:892-896`); S5 `Evidence_ColdDisabledNeverConsultsEvidence`; walk-side nullopt leg (`crdt_datastore.cpp:492-503`) + W4 |
| 11 | PROBE-LIFT: matrix boundary cells stay distinct ({hot}×{cold}×{evidence}) | ✓ VERIFIED | Both `INSTANTIATE_TEST_SUITE_P` blocks (`:1449`, `:1667`) with per-cell outcome assertions; hot-present-serves-hot and evidence-refuses-without-cold cells enumerated |
| 12 | PROBE-LIFT: empty value is Malformed, not NoEvidence | ✓ VERIFIED | Empty variant in serve product; `EmptyBadMessage` walk cell; zero-length checks in both production decoders |
| 13 | PROBE-LIFT SERVE-01 concurrency backstop (stateless consult; no resurrection under concurrent erase commit) | ✓ VERIFIED (upgraded this round) | The CR-01 TOCTOU window is now CLOSED at HEAD: X1 re-consult before the cold Get (`graphsync_dagsyncer.cpp:940-956`) and X2 re-consult before Rehydrate (`:974-986`), landed as the accepted disposition fix in phase 19 plan 19-01 with the `kInterruptAfterEvidenceConsult`/`kInterruptBeforeRehydrate` observation seams (`:919`, `:958`). Behavioral proof re-run by this verifier: `Cross_EraseCommitVsServe_EvidenceLandsMidConsult` (X1) and `Cross_EraseCommitVsServe_InflightColdGetNoRehydrateAfterEvidence` (X2) — 2/2 PASSED (1198 ms, fault-race binary built 2026-11-24 13:21 at current lineage); red-first fault arms + real-thread barrier legs present in `cold_cross_feature_fault_race_test.cpp:1457-1849`; 3-platform CI green recorded in the 19-05 close-out commits |

#### Plan 15-02 (7 truths) — the forced walk

| # | Truth (abbreviated) | Status | Evidence at current HEAD |
|---|---------------------|--------|--------------------------|
| 14 | RECOVER-02: GC-evicted ancestor (no evidence) restored via cold-before-peers chain; no conflation with pruned | ✓ VERIFIED | NoEvidence fall-through to fetch (`crdt_datastore.cpp:520-524`); fetch rides `getNode(cid, kForcedWalkPeerFailoverPerCid)` (`:537-547`); W1 `ForcedWalkRestoresColdResidentAncestor` (`node_startup_test.cpp:825`, counters :926-928) |
| 15 | RECOVER-03: evidence-bearing ancestor skipped with ++skipped_pruned; CanRestoreElement terminal | ✓ VERIFIED | Pruned skip branch (`crdt_datastore.cpp:504-513`, "block-level skip … element-level CanRestoreElement guard stays terminal authority"); `CanRestoreElement` at `PruneEligibility.cpp:167`; W2 (:1043-1044) + element-level assertion |
| 16 | RECOVER-04 abort-never-skip: true gap → ++walk_gaps, distinct FORCED_WALK_GAP, Incomplete, frontier cleared | ✓ VERIFIED | Gap branch (`crdt_datastore.cpp:554-568`); `FORCED_WALK_GAP` enum + category (`crdt_datastore.hpp`, `crdt_datastore.cpp:38`); W3 (:1182-1205: Incomplete, walk_gaps≥1, skipped_pruned==0) |
| 17 | RECOVER-04 per-CID budget = 8, named constant, no knob; 1-arg callers unchanged | ✓ VERIFIED | `kForcedWalkPeerFailoverPerCid{8}` (`graphsync_dagsyncer.hpp:83`); budget named in the abort log (:563-566) |
| 18 | Cold-disabled walk posture: null hook preserves legacy skip | ✓ VERIFIED | nullopt leg (`crdt_datastore.cpp:492-503`); W4 `ColdDisabledWalkPreservesLegacyPruneBoundarySkip` (:1216, counters :1276-1277) |
| 19 | Malformed evidence in the walk fails closed (bad_message, errors, Incomplete) | ✓ VERIFIED | `crdt_datastore.cpp:514-519`; Garbage/EmptyBadMessage walk cells |
| 20 | Walk ordering unchanged (FIFO frontier + dedup) | ✓ VERIFIED | No ordering change in the consult/fetch region; W1/W2 shapes unchanged at HEAD |

#### Plan 15-03 (8 truths) — the verification surface

| # | Truth (abbreviated) | Status | Evidence at current HEAD |
|---|---------------------|--------|--------------------------|
| 21 | SC5 product: full {hot}×{cold}×{evidence}×{serve, walk, erase-gate} asserted | ✓ VERIFIED | Test inventory re-counted: 15 TEST_F/TEST_P + 2 INSTANTIATE blocks = 32 legs in `cold_evidence_matrix_test.cpp`; erase-gate column in `cold_prune_gate_test.cpp`; 32/32 PASSED re-run this session (15405 ms) |
| 22 | SC2 masquerade counter-tests both directions, red-first | ✓ VERIFIED | `Masquerade_PrunedMarkerWithColdBytesStillRefuses` (:1684) + `Masquerade_EvictedColdBytesNoMarkerServesAndStaysArchive` (:1728), green |
| 23 | SC3 source-consistency: one predicate moves every surface together; HasBlock keeps TRUE | ✓ VERIFIED | Flip legs (:1778, :1824) green; single-predicate wiring unchanged (`globaldb.cpp:870`) |
| 24 | D-01 atomicity at the erase gate (interrupt steps, deferral) | ✓ VERIFIED | `ColdPruneEraseInterruptTest` + deferral legs in `cold_prune_gate_test.cpp` (registered Tier-1, CMake :391) |
| 25 | SERVE-04 requester failover on cold-enabled nodes; bounded; no blacklist | ✓ VERIFIED | `ColdEnabledPrunedPeerRefusalFailsOverToServingPeer` in `globaldb_erase_test.cpp` (three-part proof); budget constant intact |
| 26 | A5 discipline: no assertions on guessed wire-status constants | ✓ VERIFIED | Failover leg unchanged in shape; only public-consequence EXPECTs |
| 27 | PROBE-LIFT boundary cells (hot+PRUNED serves hot; evidence+no-cold refuses; cold+no-evidence restores) | ✓ VERIFIED | Product cells enumerated in both INSTANTIATE blocks; suite green |
| 28 | PROBE-LIFT zero-length in walk-visit and erase-gate columns | ✓ VERIFIED | EmptyBadMessage walk cell; staged-record assertions pin nonzero serialization |

**Score:** 28/28 truths verified (0 present-but-behavior-unverified)

### Required Artifacts (regression status at HEAD)

All 15 previously-verified artifacts re-checked: exists ✓, substantive ✓, wired ✓, data flowing ✓. Key confirmations (current line anchors): `PruneEligibility.hpp:430` PRUNE_BLOCK_MARKER_PREFIX + the four block-marker functions (`:526/:549/:574/:592` declarations; cpp `:297/:306/:349/:373`); `globaldb.cpp:1586/:1722-1724` widened EraseEntry + staging loop; `ColdReadService.cpp:473/:483` setter + override, `:439-445` re-warm consult; `graphsync_dagsyncer.hpp:103-110` error values; `TransactionManager.cpp:4756-4765` 2-element marker vector → widened EraseEntry; `SGTransaction.proto:85-89` PrunedBlockRecord fields 1-3; `ColdStorageStack` SetPruneEvidenceLookupOnColdReadService bridge family intact across the .cpp/.hpp/stub triple (extended by phase 19 with the test-only mid-pass hook — additive, no ODDR break: OFF-build stub twin present).

### Key Link Verification

| From | To | Via | Status |
|----|----|----|--------|
| TxPruner::RunCycle(generation) | ONE WriteBatch (erase + /prune/tx + /prune/blk) | BuildPruneMarkerEntry + BuildPruneBlockMarkerEntry → EraseEntry(vector) | ✓ WIRED (`TransactionManager.cpp:4756-4765` → `globaldb.cpp:1722-1724`) |
| GlobalDB ctor | Every classifying surface | SetPruneEvidenceLookupOnColdReadService → consult + re-consults + walk consult + re-warm gate | ✓ WIRED (single-predicate fan-out; flip-legs green) |
| FetchNodeFromColdStorage refusal | Requester failover | early-return before GetRouteKeys → serving peer | ✓ WIRED (`:466`; failover leg green) |
| ProcessForcedWalkCID | Bounded recovery + abort | LookupPruneEvidence → getNode(cid, budget) → walk_gaps → Incomplete | ✓ WIRED (`crdt_datastore.cpp:490-568`) |

### Data-Flow Trace (Level 4)

No static/hollow returns anywhere in the chain: every classification derives from a real GetRaw over production-written or seeded marker rows (`globaldb.cpp:870-911`); serves/rehydrations flow from real cold Get results (`graphsync_dagsyncer.cpp:957-1001`); walk outcomes from real fetch results and counters (`crdt_datastore.cpp:525-575`). ✓ FLOWING.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Phase's own suite (TEST-01 product) | `cold_evidence_matrix_test.exe` (full suite — the single named suite for this phase) | `[ PASSED ] 32 tests` in 15405 ms (this verifier, 2026-11-24 21:04) | ✓ PASS |
| CR-01 concurrency invariant, X1 arm | `cold_cross_feature_fault_race_test.exe --gtest_filter='*Cross_EraseCommitVsServe_EvidenceLandsMidConsult'` (run together with X2) | `[ PASSED ]` | ✓ PASS |
| CR-01 concurrency invariant, X2 arm | `…'*Cross_EraseCommitVsServe_InflightColdGetNoRehydrateAfterEvidence'` | 2/2 PASSED, 1198 ms (this verifier, 2026-11-24 21:06; binary built 2026-11-24 13:21 at current lineage) | ✓ PASS |
| Today's cited regression run | Tier-1 cold lanes, local (per user context + phase-13 close-out; 18/18 green incl. this suite at 15.37s) | consistent with the verifier's own 15.4s run | ✓ PASS |

Binary-freshness note (recorded for auditability): the matrix-suite binary was linked 2026-11-23 13:30, before commit `4f7281b1f` (2026-11-23 22:19). That commit's only `src/` delta was verified by this verifier to be the additive, test-only `SetGcMidPassHookForTest` scaffolding (used solely by `cold_compose_matrix_test`; not referenced by the matrix suite), so the run constitutes valid behavioral evidence at the current lineage. The fault-race binary is same-day current.

### Probe Execution

Not applicable — no `probe-*.sh` scripts declared by the plans (unchanged from the prior report).

### Requirements Coverage

| Requirement | Source Plan | Status | Evidence at HEAD |
|-------------|------------|--------|------------------|
| SERVE-01 | 15-01 | ✓ SATISFIED | Truths 1, 5, 10-13 — incl. the concurrency backstop now behaviorally proven (X1/X2 legs) |
| SERVE-02 | 15-01 | ✓ SATISFIED | Truths 2, 22 |
| SERVE-03 | 15-01, 15-03 | ✓ SATISFIED | Truths 9, 23 |
| TEST-01 | 15-01, 15-03 | ✓ SATISFIED | Hermetic tri-state fakes + full product matrix; 32/32 green |

(Phase-declared IDs only, per the re-verification request. SERVE-04/RECOVER-02/03/04 were also re-confirmed incidentally — see truths 3-4, 14-20, 25.)

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| (none new) | — | Debt-marker scan (`TBD\|FIXME\|XXX`) over `SuperGenius/src/crdt/**`: zero matches | — | — |
| `graphsync_dagsyncer.cpp` | (was 866-895) | CR-01 serve-side TOCTOU — **CLOSED** by the phase-19 fix-forward (X1/X2 re-consults, :940/:974) and proven by the fault legs re-run this session | resolved | Headline invariant now holds under concurrent erase commit |
| `globaldb.cpp` / `PruneEligibility.cpp` | — | WR-01/WR-02/IN-01/IN-02/IN-03 from the prior report: advisory warnings/info only — unchanged status, none block; IN-01's parallel-decoder parity remains test-pinned | ℹ️ Info | Carried as advisory debt; no phase-15 must-have affected |

### Human Verification Required

None. Both items from the 2026-11-17 report are resolved by the completed UAT record (`15-UAT.md`, 2/2 passed, 2026-11-24): (1) CR-01 disposition — ruling (a) accepted, with the fix landed AND proven (19-01; X1/X2 legs re-run green by this verifier); (2) executor-push posture — confirmed as the standing manual-push rule. No behavior-unverified truths remain.

### Gaps Summary

No must-have failed at current HEAD. All 28 truths verified — including the one previously-present-but-unverified concurrency truth, now backed by a directly re-run behavioral test. All artifacts exist, are substantive, wired, and flowing. All four phase requirement IDs (SERVE-01/02/03, TEST-01) are satisfied at `41776b0c0`. The phases 16-19 source drift was inspected where it touched this phase's seams (re-consults added to `FetchNodeFromColdStorage`; additive test-only hooks near `EraseEntry`; walk consult region extended by the phase-18 exemption) and every drift either strengthened or preserved the phase-15 contract — no regression found. Phase goal achieved.

---

_Verified: 2026-11-24T21:10:00Z (regenerated against HEAD 41776b0c0)_
_Verifier: the agent (gsd-verifier)_
