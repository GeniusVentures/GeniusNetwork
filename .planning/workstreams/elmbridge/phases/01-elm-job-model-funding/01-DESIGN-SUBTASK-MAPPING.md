# 01-DESIGN-SUBTASK-MAPPING: work_item_id ↔ subtaskid

**Phase 1 design deliverable.** Pins the splitter mapping Phase 4 implements. Phase 1 reality: `ProcessImage` rejects ELM submissions before splitting (OD-1, plan 01-02), so nothing here changes Phase 1/2/3 code — this is consumed first by the Phase 4 ELM splitter.

---

## 1. Rule: one work item → one subtask (1:1)

Each `elms[]` entry (schema `Elm`, plan 01-01) becomes exactly one `SGProcessing::SubTask`. No work item is ever split across subtasks, and no subtask ever carries two work items.

**Why:** generation is per-work-item atomic — one prompt in, one completion out. Splitting a single generation across workers buys nothing (no parallelism within one forward pass in v1.0) and would complicate result attribution, billing windows (01-DESIGN-SETTLEMENT §2 measures *per subtask*), and the OD-3 proportional split (§3 there needs a clean window↔work-item correspondence).

## 2. Chunk id: one notional chunk per subtask, subtask-unique

Each subtask carries **one** `ProcessingChunk` whose `chunkid` is minted subtask-unique (the existing `ProcessTaskSplitter::SplitTask` chunk-id minting pattern, `src/processing/processing_tasksplit.cpp:44-96`, emits per-subtask ids today — the ELM splitter reuses that discipline).

**Why (research F2):** `ValidateResults`' cross-subtask comparison is keyed on chunk ids. Subtask-unique ids mean the comparison is structurally *inert* for ELM (no two subtasks share a chunk, so there is nothing to cross-compare) — which is exactly why D-11 was corrected to a defensive assertion (plan 01-03 Task 2) instead of a behavioral gate. The notional chunk is also what the terminal envelope's `chunk_hash` field reports (01-DESIGN-SETTLEMENT §4).

## 3. Map placement: embedded in Task.json_data, beside `elms[]`

```
Task.json_data =
{ ...job schema (name/version/gnus_spec_version/job_type/elms/funding/validation)
, "elm_subtask_map": [ { "work_item_id": "w-1", "subtaskid": "<uuid>" }
                     , { "work_item_id": "w-2", "subtaskid": "<uuid>" } ... ] }
```

- Rides the **existing** `Task.json_data` transport (the same bytes `FinalizeQueueProcessing` re-parses today, `processing_subtask_queue_accessor_impl.cpp:343-375`) — no proto change, no new CRDT key.
- Written by the Phase 4 ELM splitter at split time (the splitter is the only writer; the map is immutable after publish).
- Validation-phase read: any node resolving a subtaskid back to a work item parses the map from the task JSON it already holds.

## 4. Result keying: envelopes echo work_item_id through `subtaskid`

Result envelopes stay keyed on `SubTask.subtaskid` — the keying `ValidateResults` and `UpdateResultsFromStorage` already use. Each envelope additionally echoes its `work_item_id` (one field in the envelope JSON), resolved to the map at read time.

**Anti-aggregation guardrail (RES-02):** mapping resolves **at the GCS/requestor side only** — no SuperGenius-side aggregation of per-work-item results into a job-level blob. Each work item's result is independently addressable; the requestor (or the SDK on its behalf) stitches. This keeps SuperGenius generic (it never learns what an "ELM" is beyond the schema) and preserves per-item retry/retrieval.

## 5. Uniqueness inheritance

`work_item_id` uniqueness (schema pattern `^[A-Za-z0-9_-]+$`, plan 01-01 gate `DUPLICATE_WORK_ITEM_ID`) + 1:1 mapping + subtask-unique chunk ids ⇒ all three identifiers (`work_item_id`, `subtaskid`, `chunkid`) are pairwise-unique domains. Billing windows, OD-3 splits, and terminal envelopes can key on whichever is most convenient without collision.
