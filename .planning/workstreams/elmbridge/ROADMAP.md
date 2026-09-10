# Roadmap: elmbridge

## Milestones

- 🔄 **v1.0 ELM Bridge — Single-Node ELM Job Execution** — Phases 1-4 (active, started 2026-09-09)

**Phase numbering:** This is the elmbridge workstream's first milestone — numbering starts at 1 and is independent of the child-wallet track and of SuperGenius `.planning`'s ELM Phase 13/14 labels (deliberately not carried over).

## Phases

- [ ] **Phase 1: ELM Job Model & Funding** — ELM job schema in `Task.json_data`, deterministic hours-based escrow, schema-level validation mode, and the three-clock rule (lock ≈ deadline ≈ escrow max)
- [ ] **Phase 2: Manifest & Model Cache** — Fail-closed manifest resolution and content-addressed model cache in SGProcessingManager `src/elmruntime/`
- [ ] **Phase 3: ELM Processor** — Causal-LM work-item execution on MNN: generation loop, seeded sampling, stop conditions, token counts, mid-generation cancellation, result envelope
- [ ] **Phase 4: Grid Integration & E2E Proof** — ELM splitter + full submit wiring, results convention, empty-cache single-node E2E, non-ELM regression gate, anti-scope audit

## Phase Details

### Phase 1: ELM Job Model & Funding
**Goal**: An `elm_processing` job can be expressed, validated, priced, and escrowed entirely through job JSON — the contract every later phase consumes, with the make-or-break decisions (validation mode, per-job lock timeout, hour-based escrow, three-clock rule) fixed here rather than patched later
**Depends on**: Nothing (first phase)
**Requirements**: JOB-01, JOB-03, FUND-01, FUND-02, FUND-03
**Success Criteria** (what must be TRUE):
  1. A requestor can submit an `elm_processing` job whose `elms[]` work items (unique `work_item_id`, manifest `uri`+`hash`, input pointer, generation settings), funding block, and validation mode all live in the existing `Task.json_data`; malformed jobs (duplicate `work_item_id`, missing funding, unknown validation mode) are rejected at parse with a structured error — no protobuf change
  2. Escrow held for an ELM job equals `funding.maximum_processing_hours × $0.0003/hour` (minions at PRECISION=6), computed with no price lookup, with the USD→GNUS rate recorded in the escrow transaction at hold time
  3. Lock timeout, execution deadline, and escrow maximum for an ELM job all derive from `funding.maximum_processing_hours` in one place; an ELM subtask holding a valid lock at t>60s is NOT re-grabbed by another node
  4. An over-time ELM job reaches a terminal published state (e.g. `BUDGET_EXCEEDED`) and is never silently re-grabbed; settlement refunds unused escrow — declared maximum escrowed up front, settled by measured wall-clock (subtask grab → publication, model download included)
  5. A non-ELM job submitted through the same entry point follows the existing byte-based cost, 15s lock, and chunk-validation paths byte-for-byte — the ELM branch changes nothing observable for existing jobs
**Plans**: 3 plans
Plans:
- [ ] 01-01-PLAN.md — ELM job schema + quicktype regen + parse gates + rejection matrix (SGProcessingManager, submodule-first)
- [ ] 01-02-PLAN.md — Three-clock derivation + GetElmProcessCost + interim ELM submit rejection + rate-record CRDT helper (SuperGenius, after pointer bump)
- [ ] 01-03-PLAN.md — Derived lock-timeout wiring + validation-mode assertion + settlement/subtask-mapping design artifacts + SC-5 regression legs
**Note**: Schema lands in SGProcessingManager first (quicktype regen, zero hand-edits to `generated/`); the SuperGenius cost/submit branch follows the submodule pointer bump. Includes the `work_item_id ↔ subtaskid` mapping *design* (implementation is Phase 4's splitter). Research flags resolved in 01-RESEARCH.md: (a) escrow wall-clock accounting measures NOTHING today — refund-by-measured-wall-clock designed in 01-DESIGN-SETTLEMENT.md, built Phase 4; (b) subtask queue finalization needs no `ValidateResults` change — D-11 corrected to a defensive assertion at `FinalizeQueueProcessing`.

### Phase 2: Manifest & Model Cache
**Goal**: A node can turn a manifest `uri`+`hash` into a verified, loadable MNN model bundle on disk — fail-closed, downloaded once, safely reusable
**Depends on**: Phase 1
**Requirements**: MCHE-01, MCHE-02, MCHE-03
**Success Criteria** (what must be TRUE):
  1. Every referenced manifest is loaded and hash-verified, and every artifact is fetched (via `FileManager`) and sha256-verified before use — a node never executes a model whose manifest or artifacts fail verification, with no debug bypass
  2. Verified bundles materialize in MNN's expected on-disk layout under `cache/<model-manifest-hash>/` via atomic publish (stage → verify → rename); an entry is marked usable only after a loadability smoke check (createLLM + load + 1-token greedy), so a wrong-tokenizer bundle fails as a structured error instead of silent garbage
  3. A corrupted artifact or tampered manifest results in refusal + quarantine (`.bad-<hash>`) — a poisoned entry cannot livelock the queue, and the next attempt re-downloads cleanly
  4. Two concurrent subtasks requesting the same model trigger exactly one download (single-flight); both pin and load the same cache entry; a pinned entry is never evicted mid-use
  5. Partial downloads recover; unpinned entries evict LRU under disk pressure; `%TEMP%` stays clean across runs (no per-execution materialization — the cache is the single materialization point)
**Plans**: TBD
**Note**: Ships entirely in SGProcessingManager (`src/elmruntime/`) on `dev_elmruntime` — fully unit-testable with no SuperGenius dependency. Hashing/filesystem-heavy work runs on worker threads, never in asio handlers; every new timer/callback captures `weak_from_this`.

### Phase 3: ELM Processor
**Goal**: The ELM processor executes one causal-LM work item end-to-end from a pinned cache bundle and emits a complete, work-item-tagged result envelope
**Depends on**: Phase 2
**Requirements**: GEN-01, GEN-02, GEN-03, RES-01
**Success Criteria** (what must be TRUE):
  1. A work item executes end-to-end — chat-template application + prompt tokenization, prefill, autoregressive KV-cache decode, sampling honoring `max_output_tokens`/`temperature`/`top_p`/`seed`, stop tokens and stop strings, detokenization — and reports accurate executor-side (`LlmContext`-sourced) prompt/completion token counts with `finish_reason` ∈ {stop, max_tokens, cancelled, error}
  2. Two runs of the same work item with identical `seed` on the same node/build produce byte-identical output; a `seed` key never silently no-ops (config application asserted, e.g. via `dump_config()`)
  3. A cancel/deadline firing mid-generation aborts promptly (cancel latency ≪ full generation time — via the user-approved MNN fork patch for `USER_CANCEL`), the generation thread is joined/detached deliberately, and the cache pin reaches zero
  4. Every result envelope carries `work_item_id`, generated text, prompt/completion token counts, finish reason, and `model_manifest_hash` provenance
  5. An LLM model load does not stall other processors on the node (`VulkanInitMutex` scope narrowed to actual GPU init / dedicated LLM load lock); a fresh `Llm` session per work item means the same work items executed in either order produce identical outputs; no per-execution leaks
**Plans**: TBD
**Note**: Ships in SGProcessingManager (`processors/processing_processor_elm.*`) behind an MNN_LLM-style gate. The sampler-seed and `USER_CANCEL` MNN fork patches are user-approved (GEN-01/GEN-02) — they add `thirdparty/MNN` to the pointer chain (innermost-first commit discipline). `gen_seq_len` early-stop accounting must be verified against `output_tokens.size()` before trusting reported counts.

### Phase 4: Grid Integration & E2E Proof
**Goal**: A funded ELM job flows through the real single-node grid — split into per-work-item subtasks, executed, published on the existing results path — proven by the empty-cache E2E that is this milestone's acceptance criterion, with non-ELM behavior regressively unchanged
**Depends on**: Phase 3
**Requirements**: JOB-02, JOB-04, RES-02, E2E-01, E2E-02, E2E-03
**Success Criteria** (what must be TRUE):
  1. Each `elms[]` work item becomes exactly one subtask via the new ELM splitter (one notional chunk; `subtaskid↔work_item_id` map embedded in task JSON), leaving the existing chunk-based splitter and chunk-id↔hash validation semantics untouched for non-ELM jobs
  2. A single node with an empty cache completes an assigned ELM job end-to-end: it downloads a Qwen-0.5B-class MNN causal-LM as billable job work, generates text honoring settings and stop conditions, publishes work-item-tagged results, and escrow pays out by measured wall-clock with the unused remainder refunded
  3. ELM results travel the existing gossip results channel and IPFS artifact path unchanged (hashes + counts + finish reason inline, text as content-addressed artifact via `FileManager::SaveASync`); the requestor reconstructs the job result by aggregating envelopes by `work_item_id` — no SuperGenius-side aggregation exists
  4. Existing chunk-based jobs behave byte-identically before/after across splitter, funding, validation, and results paths — the regression gate passes
  5. The removed scope stays removed — no capability/inventory/cache advertising, bidding/negotiation, requester-side selection, claims/leases, or worker-side `/v1` in code or schema; new code carries ≥80% coverage with wait-condition (non-sleep) tests; SuperGenius/GeniusSDK/GeniusWallet builds all stay green
**Plans**: TBD
**Note**: Spans both repos — splitter + submit wiring in SuperGenius (`processing_tasksplit_elm.*`, `GeniusNode::ProcessImage` fully wired); consumes Phases 2-3 via submodule pointer bump. The E2E must run with `validation: none` (never enable redundant validation for text — Pitfall 2). New test targets respect `SGPROC_TEST_DISCOVERY` gating and CTest `TIMEOUT` properties.

## Phase Ordering Rationale

- **Hard dependency chain:** the runtime requires a verified manifest+cache before any generation; the result envelope depends on the splitter mapping; the E2E proof requires everything — the order cannot be shuffled
- **Submodule constraint:** Phases 2-3 ship entirely inside SGProcessingManager (no SuperGenius dependency); Phase 1's schema part likewise lands submodule-first; SuperGenius-consuming work (Phase 1's cost branch, Phase 4) follows pointer bumps — mirrors ARCHITECTURE's six-step build order collapsed into four roadmap phases
- **Pitfall convergence:** PITFALLS' P1-P4 attribution matches this structure exactly; every critical pitfall (15s lock timeout, validation regime, byte-based cost, cache TOCTOU, seed/cancel, session isolation) has its prevention phase assigned and its verification leg in Phase 4

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. ELM Job Model & Funding | 0/3 | Planned | - |
| 2. Manifest & Model Cache | 0/? | Not started | - |
| 3. ELM Processor | 0/? | Not started | - |
| 4. Grid Integration & E2E Proof | 0/? | Not started | - |
