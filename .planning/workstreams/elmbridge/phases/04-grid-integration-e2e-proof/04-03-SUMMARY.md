---
phase: 04-grid-integration-e2e-proof
plan: 03
subsystem: processing
tags: [task-splitter, submit, escrow, crdt, protobuf, grid]

requires:
  - phase: 04-grid-integration-e2e-proof
    provides: worker routing (ProcessElmWorkItem), stamped envelope, publication
  - phase: 01-elm-job-model-funding
    provides: GetElmProcessCost, DeriveElmClocks/ElmEscrowMinions, elm_rate record helper
provides:
  - ProcessTaskSplitterELM — 1:1 split, notional chunk, elm_subtask_map (01-DESIGN-SUBTASK-MAPPING verbatim)
  - GeniusNode::ProcessImage ELM submit branch — split → cost → balance → HoldEscrow → composed txn → EnqueueTask
  - CreateElmRateRecordCRDTTransaction composing overload (P4-9: elm_rate rides the escrow-info transaction; ONE commit)
  - ModelNode.source charset extension (letter/digit-first + hyphens — user-ratified)
  - ELM_SUBMIT_UNAVAILABLE retired (enum value kept for stability)
  - Processing engine worker-thread exception hardening
affects: [04-04 settlement, 04-05 e2e]

tech-stack:
  added: []
  patterns:
    - "Compose-then-commit: extra CRDT Puts ride the escrow-info transaction; EnqueueTask is the single Commit"
    - "Splitter-writes-then-serialize: elm_subtask_map enters task JSON before set_json_data (requestor maps never survive)"

key-files:
  created:
    - SuperGenius/src/processing/processing_tasksplit_elm.hpp
    - SuperGenius/src/processing/processing_tasksplit_elm.cpp
    - SuperGenius/test/src/processing/elm_splitter_test.cpp
  modified:
    - SuperGenius/src/account/GeniusNode.cpp
    - SuperGenius/src/account/GeniusNode.hpp
    - SuperGenius/src/processing/CMakeLists.txt
    - SuperGenius/src/processing/processing_engine.cpp
    - SuperGenius/test/src/processing/CMakeLists.txt
    - SuperGenius/test/src/account/elm_cost_clocks_test.cpp
    - SuperGenius/SGProcessingManager/gnus-processing-schema.json (+regen; charset fix)

key-decisions:
  - "ModelNode.source charset extended to ^(input|output|internal|parameter):[a-zA-Z0-9][A-Za-z0-9_-]*$ (USER-RATIFIED at execution): work_item_id admits hyphens (Phase 1 fixtures use w-1) but the generated source pattern rejected them — input:w-1 threw at set_source (proven in 04-02); legacy ids remain valid (superset); target_constraint unchanged"
  - "Splitter ModelNode sets name (= work_item_id) and type (= LLM): model_node's generated from_json requires name+type (j.at) — source-only nodes cannot round-trip"
  - "ELM_SUBMIT_UNAVAILABLE enum member kept, comment marked RETIRED (API stability; zero live references)"
  - "Balance assertion semantics: HoldEscrow's ReserveUTXOs moves WHOLE UTXOs out of READY — spendable balance drops by AT LEAST the escrow (single-mint wallet: to 0); the plan's exact-delta form holds only for granular-UTXO wallets"

patterns-established:
  - "Node-fixture isolation: a node that has processed a submission starves later fixtures' startup in the same process — submit legs run last AND per-leg isolated --gtest_filter (elm_lock_timeout_test convention)"
  - "Worker threads never let core exceptions escape: engine wraps ProcessSubTask; queue timeout owns retry"

requirements-completed: [JOB-02, E2E-02]

coverage:
  - id: D1
    description: "Splitter mapping: N elms → N subtasks, 1 notional chunk each, unique chunk/subtask ids, ModelNode round-trip, map size/order/keys, requestor-map overwrite"
    requirement: JOB-02
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/processing/elm_splitter_test.cpp#ThreeWorkItemsSplitOneToOne, #RequestorSuppliedMapIsOverwritten (PASS, isolated)"
        status: pass
    human_judgment: false
  - id: D2
    description: "elm_subtask_map tolerance: job JSON carrying the map parses; ProcessingData to_json round-trips without throwing"
    requirement: JOB-02
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/processing/elm_splitter_test.cpp#MapKeyInJobJsonStillParses, #ProcessingDataToJsonRoundTrips (PASS, isolated)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Funded ELM submit succeeds through ProcessImage: tx id returned, escrow held (balance drops ≥ deterministic 300), task id in GetMyTaskIds"
    requirement: JOB-02
    verification:
      - kind: integration
        ref: "elm_splitter_test#FundedElmSubmitSucceeds + elm_cost_clocks_test#ElmSubmitRejectedBeforeEscrow (flipped; both PASS isolated)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Composed transaction: escrow info + elm_rate sibling key on ONE transaction; EnqueueTask commits once (P4-9); 2-arg helper delegates (Phase 1 rate-record leg stays green)"
    requirement: JOB-02
    verification:
      - kind: unit
        ref: "elm_cost_clocks_test#ElmRateRecordPutsSiblingKey (PASS isolated); code review: branch composes before EnqueueTask, no standalone commit"
        status: pass
    human_judgment: false
  - id: D5
    description: "Non-ELM path byte-identical (E2E-02 seam)"
    requirement: E2E-02
    verification:
      - kind: unit
        ref: "git diff ProcessImage: ELM block replaced + overload added; non-ELM flow lines unmodified (only the interim return + moved BeginTransaction line removed)"
        status: pass
    human_judgment: false

duration: 150min
completed: 2026-09-14
status: complete
---

# Phase 4 Plan 03: ELM Splitter + Submit Branch Summary

**JOB-02 delivered: 1 work item = 1 subtask through the real grid submit path — split, deterministic escrow, atomic rate record, single-commit enqueue; the Phase 1 interim rejection retired with its predicted test flip.**

## Performance

- **Duration:** ~150 min
- **Completed:** 2026-09-14 (commits 417bddc83..e4dc4b307 in SuperGenius; 2e7791f in SGProcessingManager)
- **Tasks:** 3 (all auto) + user-ratified charset fix
- **Files:** 10 modified/created

## Accomplishments

- `ProcessTaskSplitterELM`: 1:1 split with subtask-unique notional chunks, `elm_subtask_map` written unconditionally into task JSON (§1–§3 verbatim; T-04-03-01 overwrite)
- `ProcessImage` ELM branch: full submit pipeline mirroring non-ELM, with the elm_rate record composed onto the escrow-info transaction (exactly one commit — P4-9)
- Phase 1's `ElmSubmitRejectedBeforeEscrow` flipped to acceptance exactly as its comment predicted; `ELM_SUBMIT_UNAVAILABLE` retired
- Blocking charset conflict found, escalated, and fixed per user ratification (ModelNode.source + regen)
- Engine worker threads hardened against core exceptions (was: std::terminate on any worker throw)

## Task Commits

1. **Charset fix (user-ratified)** — SGProcessingManager `2e7791f`
2. **Pointer bump (solely owned here per checker W3)** — `417bddc83`
3. **Task 1: ProcessTaskSplitterELM** — `08050760d`
4. **Task 2: ProcessImage ELM branch** — `74f1fe6d7`
5. **Task 3: tests + flip + hardening** — `336140fc3`
6. **Test ordering/isolation fix** — `e4dc4b307`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] ModelNode.source charset vs work_item_id charset**
- **Found during:** Task 1 (proven empirically in 04-02: `input:w-1` throws at set_source)
- **Fix:** ESCALATED per Rule 4 (schema/codegen change) → user ratified "Extend source pattern"; all 5 source-bearing definitions + quicktype regen; legacy ids unaffected
- **Committed in:** `2e7791f`

**2. [Rule 1 - Test correctness] Splitter ModelNode required fields**
- **Issue:** generated from_json requires name+type (j.at); source-only nodes threw
- **Fix:** name = work_item_id, type = LLM
- **Committed in:** `336140fc3`

**3. [Rule 1 - Test semantics] Exact-delta balance assertion**
- **Issue:** plan said "balance decreased by ElmEscrowMinions(hours)"; HoldEscrow reserves WHOLE UTXOs (single-mint wallet → 0)
- **Fix:** assertion is `≤ balanceBefore − escrow` with the semantics documented
- **Committed in:** `336140fc3`

**4. [Rule 2 - Robustness] Worker-thread exception escape**
- **Issue:** engine's core ProcessSubTask call had no try — any worker throw std::terminate'd the node
- **Fix:** catch + log + error sink (queue timeout owns retry)
- **Committed in:** `336140fc3`

---

**Total deviations:** 4 (1 user-ratified schema fix, 3 auto)
**Impact:** Necessary for correctness; no scope creep.

## Issues Encountered

- **Node-fixture interference (environmental):** a node that has processed a submission keeps grid machinery live, starving a later fixture's startup in the same process (full-binary runs hang at next-node-READY). Mitigation: submit leg runs last + per-leg isolated `--gtest_filter` runs (the repo's established convention). All legs verified PASS in isolation.
- **Force-kill residue:** stale RocksDB locks from killed runs reproduce as "vector too long" at next startup — fixture-dir cleanup resolves it. Several misleading failure signatures during diagnosis traced to this, not code.
- The `"vector too long"`/`"DataType: 88"` startup throws observed mid-diagnosis were all environmental (locked/corrupted fixture dirs); after cleanup, zero reproduction across all legs.

## Next Phase Readiness

- 04-04 (settlement arithmetic, pure unit) builds directly on the composed-transaction + elm_rate record here; SuperGenius pointer already bumped
- 04-05's E2E will need the fixture-isolation discipline documented above
- The D-07 digest-only-inline ratification (from 04-02) remains open for the user

---
*Phase: 04-grid-integration-e2e-proof*
*Completed: 2026-09-14*
