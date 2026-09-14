---
phase: 04-grid-integration-e2e-proof
plan: 02
subsystem: processing
tags: [worker-routing, elm, envelope-publication, ipfs, boost-asio, quicktype]

requires:
  - phase: 04-grid-integration-e2e-proof
    provides: get_stop() regenerated types, stamped ElmEnvelope (D-04), embedding_file role
  - phase: 03-elm-processor
    provides: StartProcessingElm contract, MakeErrorResult envelope-bearing failure shape
provides:
  - ProcessInternal ELM intercept (Pattern 1) — ELM jobs never reach pass-indexing
  - ProcessElmWorkItem — work-item resolution, prompt fetch, deadline, stop strings, stamps, publication
  - GetOrCreateElmCache — lazy construct-once production cache (first CreateProductionElmModelCache caller)
  - CheckElmValidity stop-array bounds gate (D-02 C++ half)
  - Terminal-envelope publication (Pattern 2) — envelope-bearing failures return success-shaped output
  - OQ2 two-digest inline convention — result_hash = envelope-minus-text digest, chunk_hashes[0] = full-envelope digest
  - ELM save branch — ipfs:// primary + local dual-save, output_locations[0] = ipfs://CID
affects: [04-03 splitter/submit, 04-05 e2e]

tech-stack:
  added: []
  patterns:
    - "Pattern 1: job_type sniff as ProcessInternal's first conditional; legacy path stays byte-identical"
    - "Pattern 2: envelope-presence test (hash + exactly 1 chunk + non-empty buffer) gates success-shape vs failure"

key-files:
  created:
    - SuperGenius/SGProcessingManager/test/processingbase/elm_worker_routing_test.cpp
  modified:
    - SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp
    - SuperGenius/SGProcessingManager/include/processingbase/ProcessingManager.hpp
    - SuperGenius/SGProcessingManager/test/processingbase/elm_job_schema_test.cpp
    - SuperGenius/SGProcessingManager/test/processingbase/CMakeLists.txt

key-decisions:
  - "Full-envelope digest recomputed after re-stamping (the processor's original hash predates stamp injection — stale by construction)"
  - "Cache construction failure maps to a terminal envelope built directly in ProcessElmWorkItem (not fed through StartProcessingElm, which would re-derive a different error shape) — per the plan's explicit NO"
  - "ModelNode source charset (^input:[a-zA-Z][a-zA-Z0-9_]*) forbids hyphens — test ids use w_1/w_2 (schema work_item_ids allow hyphens; the subtask-side ModelNode source is the tighter constraint 04-03's splitter must respect)"
  - "DEVIATION-RECORD (checker B1, carried per plan): D-07's inline payload nominally carries work_item_id/counts/finish_reason/manifest_hash/stamps inline, but SubTaskResult exposes NO arbitrary-payload field and proto changes are out of scope — the inline convention delivers the envelope-minus-text DIGEST on result_hash; remaining D-07 fields live on the content-addressed artifact at ipfs_results_data_id. AWAITS USER RATIFICATION — not full literal-inline D-07"

patterns-established:
  - "Envelope-presence test: hasEnvelope = output_buffers && hash non-empty && exactly 1 non-empty buffer"
  - "Construct-once-with-cached-failure for expensive singletons (queue drains instead of retry-looping)"

requirements-completed: [RES-02, E2E-01]

coverage:
  - id: D1
    description: "Stop-array bounds gate: >4 entries, empty entry, >128-byte entry reject at Create with ELM_GENERATION_SETTINGS_INVALID; 4-entry/128-byte/absent parse"
    requirement: E2E-01
    verification:
      - kind: unit
        ref: "SuperGenius/SGProcessingManager/test/processingbase/elm_job_schema_test.cpp#StopFourEntriesParse..StopAbsentParses (33/33 pass)"
        status: pass
    human_judgment: false
  - id: D2
    description: "ELM subtask routes to ProcessElmWorkItem before pass-indexing — never MISSING_INPUT for declared work items; unmatched ids get structured MISSING_INPUT from resolution"
    requirement: RES-02
    verification:
      - kind: unit
        ref: "SuperGenius/SGProcessingManager/test/processingbase/elm_worker_routing_test.cpp#ElmSubtaskNeverHitsMissingInput, #UnknownWorkItemIdFailsMissingInput (4/4 pass)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Terminal envelope publication: envelope-bearing failures (cache-missing error envelope) return success-shaped ProcessOutput with two distinct digests"
    requirement: RES-02
    verification:
      - kind: unit
        ref: "SuperGenius/SGProcessingManager/test/processingbase/elm_worker_routing_test.cpp#TerminalEnvelopePublishesSuccessShaped (combinedHash != chunkhashes[0] asserted)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Non-ELM path byte-identical (SC-4): git diff shows 0 deleted lines in ProcessingManager.cpp; legacy schema tests stay green"
    verification:
      - kind: unit
        ref: "git diff src/processingbase/ProcessingManager.cpp — 0 deletions; sgprocbase_elm_job_schema_test 33/33 (non-ELM parity legs included)"
        status: pass
    human_judgment: false
  - id: D5
    description: "ipfs:// artifact publication with ipfs_results_data_id CID return"
    requirement: RES-02
    verification: []
    human_judgment: true
    rationale: "CID fill requires a live bitswap instance — offline unit tests prove the save branch runs without crash and the slot contract; the real ipfs:// round-trip is 04-05's E2E (D-09) with a node's bitswap."

duration: 75min
completed: 2026-09-14
status: complete
---

# Phase 4 Plan 02: ELM Worker Path Summary

**The worker half of grid routing: ELM subtasks route past pass-indexing into prompt-resolved, stamped, published envelope execution — terminal errors included (no re-grab), non-ELM path byte-identical.**

## Performance

- **Duration:** ~75 min
- **Completed:** 2026-09-14 (commits b054306, da46fa1)
- **Tasks:** 3 (all auto)
- **Files modified:** 4 created/modified, +742 lines

## Accomplishments

- `ProcessElmWorkItem` live: resolution → grab stamp → deadline → prompt fetch → stop strings → lazy cache → `StartProcessingElm` → finish stamp + re-serialize → two-digest output → ipfs:// dual-save publication
- Stop-array bounds gate (D-02's C++ half) with 6 new schema-test legs
- Terminal-envelope publication: envelope-bearing error results return success-shaped `ProcessOutput`; only envelope-absent failures map to `outcome::failure`
- `sgprocbase_elm_routing_test` (4 legs) proving Pattern 1 (never MISSING_INPUT), resolution failures, terminal publication + digest distinctness, and cache-failure drain

## Task Commits

1. **Task 1: Stop-array bounds gate** — `b054306` (feat)
2. **Tasks 2+3: ProcessElmWorkItem + publication + tests** — `da46fa1` (feat)

## Files Created/Modified

- `src/processingbase/ProcessingManager.cpp` — intercept + ProcessElmWorkItem + ResolveElmWorkItem + GetOrCreateElmCache (+348, 0 deletions)
- `include/processingbase/ProcessingManager.hpp` — declarations + m_elmCache/m_elmCacheAttempted members
- `test/processingbase/elm_job_schema_test.cpp` — 6 stop-bounds legs
- `test/processingbase/elm_worker_routing_test.cpp` — NEW, 4 legs
- `test/processingbase/CMakeLists.txt` — sgprocbase_elm_routing_test registration (TIMEOUT 120)

## Decisions Made

- Full-envelope digest recomputed post-stamp (processor's hash is stale after stamp injection)
- Cache-failure terminal envelope built directly in ProcessElmWorkItem (not via StartProcessingElm — per the plan's explicit direction)
- ModelNode source charset forbids hyphens: subtask ids are `w_1`-style; 04-03's splitter must emit underscore-safe ids (schema-side work_item_ids still allow hyphens)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Test correctness] Routing-test charset + JSON escaping**
- **Found during:** Task 3 verification
- **Issue:** `w-1` violates ModelNode's generated source pattern (`^(input|...):[a-zA-Z][a-zA-Z0-9_]*$` — no hyphens); Windows prompt paths broke hand-built JSON (unescaped backslashes); one bulk-replace miss left a `w-1` in the hand-built leg
- **Fix:** `w_1`/`w_2` ids, `EscapeJson()` helper, corrected the missed literal
- **Files modified:** test file only
- **Verification:** 4/4 routing legs green
- **Committed in:** `da46fa1`

---

**Total deviations:** 1 auto-fixed (Rule 1)
**Impact on plan:** None — the charset finding is recorded as a decision for 04-03.

## Issues Encountered

- The plan's test-design note anticipated needing `setBitswap` for the dual-save leg; without a bitswap the local dual-save is opportunistic (cacheDir is empty) and `output_locations[0]` stays empty — the legs assert what the offline contract guarantees, and the real CID fill belongs to 04-05's E2E (D-09). Recorded in coverage D5 as human-judgment.

## User Setup Required

None.

## Next Phase Readiness

- 04-03 (splitter + submit branch) starts with the SuperGenius pointer bump to SGProcessingManager's current dev_elmruntime HEAD (`da46fa1`) — solely owned there per checker W3
- The splitter must emit ModelNode sources with underscore-safe ids (the generated charset constraint)
- D-07 residual ratification (digest-only inline) carried to the user with this SUMMARY

---
*Phase: 04-grid-integration-e2e-proof*
*Completed: 2026-09-14*
