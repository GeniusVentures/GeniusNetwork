---
phase: 15-evidence-aware-cold-serving-forced-walk-recovery
plan: 03
subsystem: testing
tags: [crdt, cold-storage, prune-evidence, erase-gate, graphsync, failover, gtest, value-parameterized]

requires:
  - phase: 15-01
    provides: "ColdReadFallback::LookupPruneEvidence single-predicate classification (SC3/D-04), /prune/blk marker staging in the erase WriteBatch (D-01/D-02), cold_evidence_matrix hermetic fixture"
  - phase: 15-02
    provides: "Forced-walk consult matrix + walk_gaps abort (D-05), kForcedWalkPeerFailoverPerCid bound + bounded getNode overload (D-06), node-level walk legs in node_startup_test"
provides:
  - "SC5/TEST-01 complete: the refusal matrix runs as a PRODUCT — 16 serve cells ({hot:2}×{cold:2}×{evidence:4}) + 5 walk-visit legs + the erase-gate column in the gate suite — every enumerated cell asserted, none skipped"
  - "SC2 masquerading counter-tests, both directions, red-first: cold-bytes+marker REFUSES; cold-bytes+no-marker SERVES + re-warms + archive posture holds"
  - "SC3 source-consistency flip-test (D-04): no-evidence → PRUNED → garbage flips move getNode classification, walk consult, and re-warm gate TOGETHER while the four-term bool presence check keeps answering TRUE for the cold-dir-resident pruned CID"
  - "D-01 atomicity proof at the erase gate: gated erase stages BOTH markers (/prune/tx + /prune/blk, record generation/hash asserted); interrupt steps 1/2/3 each abort with NEITHER marker NOR erase landed; deferral stages no marker; cold-off erase still stages the marker"
  - "SERVE-04/D-07 requester half on cold-enabled nodes: pruned-peer refusal fails over to the serving archive (ordered-route hermetic + mesh window), attempts bounded ≤ kForcedWalkPeerFailoverPerCid, IsOnBlackList false (CID-scoped accounting), storage-deterministic single-route refusal with hot absence preserved"
affects: [phase-16-audit, phase-17-probe, verify-work-uat, cold-serving, tx-pruner]

actuals:
  tokens: 21600   # chars/4 over the realized diffs (Task 1: 51,536 chars / Task 2: 35,014 chars = 86,550 chars total)
  tasks: 2
  commits: 2      # SuperGenius: f1f4c4768 (Task 1), af644481f (Task 2)

tech-stack:
  added: []
  patterns:
    - "Value-parameterized product legs (WithParamInterface + INSTANTIATE_TEST_SUITE_P) enumerating {hot}×{cold}×{evidence} cells — a dropped cell is a dropped leg in the gtest summary, enforcing TEST-01 no-silent-drop mechanically"
    - "Interrupt-step atomicity proof: SetEraseInterruptHookForTest aborts INSIDE the single WriteBatch window at steps 1/2/3; each leg asserts value-present + both-markers-absent, then a retry leg proves no poisoned state remains"
    - "Cold-enabled twin of an existing node factory (makeColdNode): identical pubsub/scheduler/graphsync wiring + hermetic ColdStorageOptions + SetColdStorageStackClientsForTesting injection window around GlobalDB::New, override cleared immediately after construction"
    - "A5 discipline in practice: refusal asserted only through public consequences (failover completed, no blacklist, bounded attempts, storage-deterministic refusal); observed transport posture recorded in code comments for the SUMMARY, never welded into an EXPECT"

key-files:
  created: []
  modified:
    - SuperGenius/test/src/crdt/cold_evidence_matrix_test.cpp
    - SuperGenius/test/src/crdt/cold_prune_gate_test.cpp
    - SuperGenius/test/src/crdt/globaldb_erase_test.cpp
    - SuperGenius/test/src/crdt/CMakeLists.txt

key-decisions:
  - "Matrix cell count actually enumerated: 32 gtest legs in cold_evidence_matrix_test (9 Matrix + 2 Rewarm + 16 ServeProduct + 5 WalkProduct); the walk-visit column carries 5 distinct-outcome legs with focused assertions referencing the 15-02 node legs for cells already proven there (the plan's locked no-silent-drop ruling — every cell appears in the enumeration, proof location recorded)"
  - "Erase-gate column lives in the Phase-14 gate suite (cold_prune_gate_test) riding its TxPruner/TransactionManager fixture; the failover extension lives in globaldb_erase_test riding its EraseNodeCollection multi-node recipe — the split follows each suite's fixture strengths (RESEARCH open question 4 ruling)"
  - "Evidence seeding on the failover nodes goes through direct PutRaw at PruneEligibility::PRUNE_BLOCK_MARKER_PREFIX, NOT WritePrunedBlockEntryForTest: the helper's body lives in genius_transaction_objs, which crdt-level test targets must NOT link (the layering ruling in src/crdt/globaldb/CMakeLists.txt — linking it inverts the crdt→transaction dependency); the row written is byte-identical to the helper's (same key home, same PrunedBlockRecord shape)"
  - "SC3 shape is a flip-test, explicitly SOURCE-consistency: all classifying surfaces re-classify together on re-seed while the bool presence check keeps its four-term TRUE answer (dedup posture, body unchanged) — proving one predicate, many shapes"
  - "A5 observed-transport record: the pruned responder's negative completion is the documented RS_NOT_FOUND honest don't-have posture (graphsync_dagsyncer.cpp in-source comment); the requester-side terminal error is the application-level HISTORY_PRUNED_LOCALLY — recorded here and in code comments, never an EXPECT on a wire constant"
  - "Budget observability resolved (15-02 carryover): the mesh-window bounded-attempts assertion names GraphsyncDAGSyncer::kForcedWalkPeerFailoverPerCid (= 8) directly — not deferred"

patterns-established:
  - "makeColdNode factory twin: hermetic cold posture for any multi-node GlobalDB suite (InMemory S3 fakes against a never-contacted endpoint, fake-client override scoped to the GlobalDB::New call)"
  - "Interrupt-leg retry epilogue: after an aborted-at-step-N erase, an uninterrupted re-run must complete with BOTH markers — proving the abort left no partial state behind"

requirements-completed: [SERVE-03, SERVE-04, TEST-01]

coverage:
  - id: D1
    description: "Serve-column product — 16 value-parameterized legs enumerating {hot: present/absent} × {cold: present/absent} × {evidence: none/PRUNED/malformed-garbage/malformed-zero-length}, each asserting its specified outcome"
    requirement: TEST-01
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/crdt/cold_evidence_matrix_test.cpp#ServeMatrixCells/ColdEvidenceServeProductTest (16/16 legs)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Walk-visit column — 5 legs over the same fixture composition: pruned skip, malformed (garbage + zero-length) bad_message, no-evidence+cold restore, no-evidence+no-cold gap; hot-present dedup documented"
    requirement: TEST-01
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/crdt/cold_evidence_matrix_test.cpp#WalkMatrixCells/ColdEvidenceWalkProductTest (5/5 legs)"
        status: pass
    human_judgment: false
  - id: D3
    description: "SC2 masquerading counter-tests, both directions, red-first: cold-bytes+marker REFUSES (resurrection-gap kill); cold-bytes+no-marker SERVES + re-warms + presence stays TRUE + subsequent read serves hot (conflation kill)"
    requirement: TEST-01
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/crdt/cold_evidence_matrix_test.cpp#Masquerad* counter-tests (in ColdEvidenceMatrixTest/RewarmTest families)"
        status: pass
    human_judgment: false
  - id: D4
    description: "SC3 source-consistency flip-test — no-evidence → PRUNED → garbage re-seeds move getNode classification, walk consult, and re-warm gate TOGETHER; bool presence check keeps TRUE for the cold-dir-resident pruned CID"
    requirement: SERVE-03
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/crdt/cold_evidence_matrix_test.cpp#*Consistency*Flip*"
        status: pass
    human_judgment: false
  - id: D5
    description: "D-01 erase-gate atomicity — gated erase stages BOTH markers (record generation + tx-hash asserted); interrupt steps 1/2/3 each land NEITHER marker NOR erase; deferred cycle stages no /prune/blk; cold-off erase still stages the marker"
    requirement: TEST-01
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/crdt/cold_prune_gate_test.cpp#EraseInterruptSteps/ColdPruneEraseInterruptTest (3/3 steps) + Gate_DurableAdmitsAndErases/Gate_PendingDefersWholeGroupAsCounter/Gate_ColdDisabledNodeVacuousBranch extensions"
        status: pass
    human_judgment: false
  - id: D6
    description: "SERVE-04/D-07 cold-enabled refusal failover — three-part proof: ordered-AddRoute hermetic failover to the serving archive, mesh-window bounded attempts naming kForcedWalkPeerFailoverPerCid, IsOnBlackList false (+ functional not-blacklisted); plus storage-deterministic single-route refusal with hot absence preserved on both ends"
    requirement: SERVE-04
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/crdt/globaldb_erase_test.cpp#GlobalDBEraseRefusalFailoverTest.ColdEnabledPrunedPeerRefusalFailsOverToServingPeer"
        status: pass
    human_judgment: false

duration: 90min
completed: 2026-11-17
status: complete
---

# Phase 15 Plan 03: Evidence Product Matrix, Counter-Tests & Erase-Gate Atomicity Summary

The phase's verification surface is complete: the refusal matrix runs as a full product (16 serve cells + 5 walk legs + the erase-gate column), masquerading is disproven in both directions, source-consistency is flip-test proven, erase-gate atomicity holds across both markers at every interrupt step, and cold-enabled refusal fails over through the existing CID-scoped machinery — all hermetic, all Tier-1 green.

## Performance

- **Duration:** ≈90 min total (initial executor run + crash-recovery continuation; continuation alone ≈40 min)
- **Completed:** 2026-11-17
- **Tasks:** 2/2
- **Files modified:** 4 (SuperGenius)

## Accomplishments

- **SC5/TEST-01 product matrix** — `cold_evidence_matrix_test.cpp` grew from 11 to 32 legs: 16 value-parameterized serve cells covering every {hot}×{cold}×{evidence} combination (malformed family includes the zero-length value), 5 walk-visit legs, the red-first masquerade counter-tests in both directions, and the SC3 consistency flip-test with the D-04 bool-presence projection assertion.
- **D-01 erase-gate atomicity** — `cold_prune_gate_test.cpp`: the gated-erase leg now asserts BOTH marker rows (raw prefix-parity + parsed PrunedBlockRecord with generation and tx-hash); a new `ColdPruneEraseInterruptTest` parameterized over interrupt steps 1/2/3 proves the dying WriteBatch stages nothing (value present, both markers absent) and a retry completes cleanly; the deferral leg stages no block marker; the cold-off vacuous leg still stages it (markers are node-local, cold-independent).
- **SERVE-04/D-07 cold-enabled failover** — `globaldb_erase_test.cpp`: `ColdEnabledPrunedPeerRefusalFailsOverToServingPeer` proves the requester half on cold-enabled nodes — ordered-route deterministic failover from a PRUNED light peer (Durable cold bytes + seeded evidence, hot absent) to the serving archive, mesh-window convergence with attempts ≤ `kForcedWalkPeerFailoverPerCid`, no connection blacklist (functional proof: the light peer still serves its fresh puts), and a storage-deterministic single-route refusal preserving hot absence on both ends. A5 discipline throughout — zero wire-status constants in EXPECTs.

## Task Commits

1. **Task 1: Full refusal-matrix product + red-first masquerade counter-tests + SC3 consistency flip-test** — `f1f4c4768` (test, SuperGenius: 929 insertions in cold_evidence_matrix_test.cpp)
2. **Task 2: Erase-gate both-marker atomicity legs + cold-enabled refusal-failover extension** — `af644481f` (test, SuperGenius: 559 insertions across cold_prune_gate_test.cpp, globaldb_erase_test.cpp, CMakeLists.txt)

## Verification Results (re-run in full by the continuation executor)

| Lane | Result |
|---|---|
| `cmake --build SuperGenius/build/Windows/Release --config Release --parallel 8` | exit 0, no `error C`/LNK diagnostics |
| `ctest -R "cold_prune_gate_test\|globaldb_integration_test"` (both touched suites) | 2/2 passed (globaldb_integration 88.35 s, cold_prune_gate 18.58 s) |
| New gate legs direct run (`--gtest_filter=*EraseInterrupt*`) | 3/3 OK (steps 1/2/3) |
| New failover leg direct run (`--gtest_filter=*ColdEnabledPrunedPeer*`) | 1/1 OK (2.0 s) |
| Structural probes | gate file: 11 matches (≥5 required); erase file: 10 matches (≥3 required) |
| `ctest -L Tier1` | **15/15 passed** |
| Phase-13/14/15 regression set (plan regex, 10 matched suites) | **10/10 passed** |
| `crdt_test` (ctest home of `crdt_erase_test.cpp`, closing the plan-regex name gap) | 1/1 passed (31.42 s) |
| Full matrix suite | 32/32 legs passed across 4 suites |

## Decisions Made

- Recorded in frontmatter `key-decisions`: the 32-leg enumeration split, the suite placement ruling, the layering-driven seeding choice, the source-consistency shape, the A5 observed-transport record (RS_NOT_FOUND honest don't-have posture, HISTORY_PRUNED_LOCALLY terminal), and the budget-observability resolution (bound named directly in the assertion).

## Deviations from Plan

### Executor crash + continuation (factual record)

The initial executor crashed at the moment it reported "Committing Task 2" — Task 1 was committed (`f1f4c4768`), Task 2's code was written but uncommitted, and its claimed verification was unproven narration. This continuation verified the uncommitted diff against the Task 2 spec line-by-line, reconciled one seeding-shape question (below), re-ran every verify lane from scratch (results above), and landed the commit as `af644481f`. No uncommitted work was discarded.

### Auto-fixed / reconciled issues

**1. [Rule 3 - blocking] Evidence seeding shape on the failover nodes**
- **Found during:** Task 2 reconciliation (continuation)
- **Issue:** The plan's action prose names `WritePrunedBlockEntryForTest` for the `/prune/blk` seeding. A reconcile attempt to that helper produced `LNK2019` — the helper's body lives in `genius_transaction_objs`, and `globaldb_integration_test` must not link it (the layering ruling in `src/crdt/globaldb/CMakeLists.txt`: linking it inverts the crdt→transaction dependency). The gate suites pull it via the `genius_node_test` whole-archive; this target deliberately doesn't.
- **Fix:** Kept the direct `PutRaw` seeding at `PruneEligibility::PRUNE_BLOCK_MARKER_PREFIX` with a byte-identical `PrunedBlockRecord` (same key home, same shape as `BuildPruneBlockMarkerEntry`), with a code comment recording why the helper is not used.
- **Verification:** clean build + all suites green.
- **Committed in:** `af644481f`

**2. [Rule 3 - missing build wiring] `CMakeLists.txt` modified though absent from the plan's `files_modified`**
- **Found during:** Task 2 (initial executor, verified by continuation)
- **Issue:** The cold-enabled failover legs need the InMemory S3 fakes (`sgns-blockstore`), `rapidjson`, and `SGTransactionProto` linked into `globaldb_integration_test` under `SGNS_COLD_STORAGE`.
- **Fix:** Guarded CMake block adds the compile definition + the three links; the OFF build keeps the suite's pre-15-03 shape.
- **Committed in:** `af644481f`

**3. [Rule 1 - verification correctness] Plan verify-command test-name mismatches**
- **Found during:** Task 2 verification (continuation)
- **Issue:** The plan's verify regexes name `globaldb_erase_test`, `crdt_erase_test`, and `cold_walk_recovery_test` — none is a ctest registration name. `globaldb_erase_test.cpp` compiles into `globaldb_integration_test`; `crdt_erase_test.cpp` into `crdt_test`; `cold_walk_recovery_test` does not exist (15-02's walk legs live in `node_startup_test`, per 15-02's SUMMARY verification table). Run literally, the suites-verify regex would silently skip the failover legs — exactly the no-silent-drop failure TEST-01 prohibits.
- **Fix:** Ran the corrected homes: `-R "cold_prune_gate_test|globaldb_erase_test|globaldb_integration_test"` (2/2) and `^crdt_test$` (1/1); the regression set already included `node_startup_test` (green).
- **Verification:** all lanes green, leg-level evidence captured via direct gtest filters.

---

**Total deviations:** 3 auto-fixed/reconciled + 1 factual crash record
**Impact on plan:** None on scope — all acceptance criteria met; the deviations are build/verification plumbing and shape reconciliation, each with the plan's intent preserved.

## Issues Encountered

- The crashed executor's unverified "all green" claim was treated as unproven; every lane above was re-run from scratch by the continuation and is backed by output captured in this session.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- The phase's full verification surface (SC2/SC3/SC5, D-01, SERVE-04, TEST-01) is green and hermetic in Tier-1; phase-level verification (verify-work) can route off the `coverage:` block above deterministically.
- No stubs, no skipped legs, no `#ifdef`-dropped cells: every parameterized leg runs in the Tier-1 lane (probe counts and gtest summaries recorded above).

---
*Phase: 15-evidence-aware-cold-serving-forced-walk-recovery — Plan 03*
*Completed: 2026-11-17*
