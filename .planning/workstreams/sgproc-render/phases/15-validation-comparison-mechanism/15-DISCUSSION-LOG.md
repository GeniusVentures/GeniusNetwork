# Phase 15: Validation Comparison Mechanism - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-14
**Phase:** 15-Validation Comparison Mechanism
**Areas discussed:** Data source for numeric fallback, Tolerance threshold source, SECV-02 counter-test shape

---

## Data source for numeric-tolerance fallback

| Option | Description | Selected |
|--------|-------------|----------|
| Fetch on mismatch via IPFS | Fetch raw chunk data via `ipfs_results_data_id` only when hashes mismatch — no proto changes | ✓ (refined) |
| Carry data with the result | Extend `SubTaskResult` (or a side-channel) to carry raw/quantized chunk bytes inline | |
| Injectable provider, defer real wiring | Pluggable chunk-data-provider interface; real production wiring deferred | |

**User's choice:** "IPFS is the right track, but really from the job result uri which is determined by output uri in json."

**Notes:** Investigated `ProcessingManager.cpp:1585-1618` — confirmed `ipfs_results_data_id` is populated from the same `FileManager::SaveASync(outputUrl, ...)` mechanism keyed on each output's declared `source_uri_param` in the job schema JSON. Locked as: reuse this existing mechanism exactly (no new fetch path, no proto change), fetch only on hash mismatch.

---

## Tolerance threshold source

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse capture_diff's fixed constants | Literal reuse of hardcoded 1e-4 relative / 1 absolute thresholds, same for every job | |
| Derive from Phase 14's quantScale | Tolerance computed per-job from configured quantScale/byteQuantMode | ✓ (hybrid) |
| quantScale-derived, with fixed fallback | Use quantScale-derived tolerance when declared; fixed default otherwise | ✓ |

**User's choice:** "quantScale-derived, with fixed fallback"

**Notes:** Mirrors Phase 14's own additive-fallback discipline (D-04/D-08 in 14-CONTEXT.md). Exact formula converting quantScale/byteQuantMode into a threshold left to research/planning.

---

## SECV-02 counter-test shape

| Option | Description | Selected |
|--------|-------------|----------|
| Unit-level at ValidateResults | Construct two SubTaskResult objects directly, assert ValidateResults flags the corrupted one | |
| Full pipeline, like SECV-01 | Mirror SECV-01 exactly: two complete jobs end-to-end, assert corruption surfaces through validation | ✓ |
| Both | Unit-level test plus one end-to-end case | |

**User's choice:** "Full pipeline, like SECV-01"

**Notes:** Existing `secv01_counter_test.cpp`/`secv01_tex3d_counter_test.cpp` operate at the single-node `ProcessingManager::Process()` level and never exercise `ValidateResults`/subtask-queue plumbing — SECV-02 is structurally new territory, not a literal copy-paste, even though it mirrors the same "correct vs. corrupted, assert divergence still caught" spirit at the pipeline level.

---

## Wrap-up check

Recap of all three decisions presented together with the open blob-slicing question; user confirmed "Looks right, leave slicing to research (Recommended)" — proceeded directly to writing CONTEXT.md without further rounds.

## Claude's Discretion

- Blob-to-chunk slicing/offset mechanism for fetched output data (explicitly deferred to research by user's own choice)
- Exact quantScale/byteQuantMode → numeric-tolerance-threshold formula
- Physical location for extracted `capture_diff` comparison logic (shared lib vs. header-only, etc.)
- Exact SECV-02 test file name/location
- Whether the fetch-on-mismatch path is synchronous/blocking inside `ValidateResults` or dispatched by its caller

## Deferred Ideas

None — discussion stayed within phase scope. XNODE-01c (cross-node consensus/redundant-execution plumbing) was referenced as existing out-of-scope context, not raised as new scope creep during this discussion.
