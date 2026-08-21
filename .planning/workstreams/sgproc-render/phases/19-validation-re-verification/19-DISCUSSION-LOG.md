# Phase 19: Validation Re-Verification - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-21
**Phase:** 19-Validation Re-Verification
**Areas discussed:** Fixture data source, Chunk coverage, Still-open scope boundary

---

## Fixture data source

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse existing captures | Reuse Phase 13's exact S=2^15-round `.cap` pair (`xhw-mnn-float_Fuus-Mac-mini.local---macOS_20260812T232347.cap` vs `xhw-mnn-float_Mofu---Windows_20260812T232430.cap`) — no new hands-on capture session. | ✓ |
| Fresh 2-machine capture round | Re-run the MNN job live on both machines again for brand-new bytes. | |

**User's choice:** Reuse existing captures
**Notes:** These are the exact captured bytes behind Phase 13's "1/15 chunk still divergent" finding (chunk 10). Follows the precedent Phase 17-09 already set for reusing already-captured data.

| Option | Description | Selected |
|--------|-------------|----------|
| Full pipeline (SECV-02 style) | Real `ProcessTaskSplitter::SplitTask` two-subtask/one-chunk construction, real `SubTaskQueueAccessorImpl` API, captured bytes substituted in as the two subtasks' outputs. | |
| Direct unit-level call | Construct `ChunkContribution` structs directly from captured bytes/hashes and call `ValidateResults`/`AttemptToleranceFallback` directly, mirroring `ProcessingValidationCoreTest`. | ✓ |

**User's choice:** Direct unit-level call
**Notes:** Exercises the exact same unchanged production tolerance-fallback code; Phase 15's own verification treated this style as sufficient proof for SC1-SC4. Full-pipeline style noted in CONTEXT.md as a fallback if direct-call proves structurally insufficient.

---

## Chunk coverage

| Option | Description | Selected |
|--------|-------------|----------|
| All 15 chunks | Feed all 15 chunks of the fixture through `ValidateResults`, matching SC2's literal "which chunks match/mismatch" wording and mirroring production behavior. | ✓ |
| Chunk 10 only | Exercise only the one chunk Phase 13 found still divergent post-quantization. | |

**User's choice:** All 15 chunks
**Notes:** Other 14 chunks are expected to already match bit-for-bit per `13-SCOPE-BOUNDARY.md`, so this is expected to cost a loop/iteration, not new investigation.

---

## Still-open scope boundary

| Option | Description | Selected |
|--------|-------------|----------|
| Document only, no fix | If the re-run shows the gap is still not closed, stop at honest documentation — matches ROADMAP SC3 and the phase's "Re-Verification" (not "Fix") name. | ✓ |
| Attempt a quick fix if low-risk | If a clearly low-risk fix turns up, apply it inline rather than just reporting the gap. | |

**User's choice:** Document only, no fix
**Notes:** Any further tuning of S=2^15 would re-litigate Phase 13's already-documented SECV-01-margin tradeoff. Narrow exception carried into CONTEXT.md: a bug in the *test harness itself* (not production tolerance logic) may still be fixed inline.

---

## Claude's Discretion

- Exact harness file location/naming (extend `processing_validation_core_test.cpp` vs. a small dedicated tool).
- How to parse `.cap` file raw per-chunk bytes into `ChunkContribution` structs (via `capture_file_format.hpp`'s documented layout).
- Exact output document naming/format for the outcome (follow the `13-SCOPE-BOUNDARY.md` / `17-TOLERANCE-RESULTS.md` honest-reporting convention).

## Deferred Ideas

None — discussion stayed within phase scope.
