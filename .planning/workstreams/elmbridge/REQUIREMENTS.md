# Requirements — elmbridge v1.0: ELM Bridge — Single-Node ELM Job Execution

**Workstream:** elmbridge (`--ws elmbridge`)
**Milestone:** v1.0
**Created:** 2026-09-09
**Source:** SuperGenius#369 / SGProcessingManager#17 (tracking) + research (`.planning/workstreams/elmbridge/research/SUMMARY.md`) + user questioning

**Goal:** A GCS-style requestor submits one funded `elm_processing` job (`elms[]` work items in existing `Task.json_data`); a single SuperGenius node distributes it through the existing processing grid and executes each ELM work item via SGProcessingManager — fetch model, verify, generate, publish work-item-tagged results. Single-node E2E.

---

## v1.0 Requirements

### Job Model (JOB)

- [ ] **JOB-01**: A requestor submits an `elm_processing` job whose `elms[]` work items (`work_item_id`, `elm_type`, model manifest `uri`+`hash`, input pointer, generation settings `max_output_tokens`/`temperature`/`top_p`/`seed`) live entirely in the existing `Task.json_data` — no main-protobuf change
- [ ] **JOB-02**: Each ELM work item becomes exactly one subtask via a new ELM splitter (work item → subtask 1:1, one notional chunk), leaving the existing chunk-based splitter and chunk-id↔hash validation semantics untouched for non-ELM jobs
- [ ] **JOB-03**: A schema-level validation mode (`none|exact|redundant`) on the `elm_processing` job governs how ELM subtask results are validated; text generation does not flow through the chunk-hash float-tolerance regime
- [ ] **JOB-04**: The removed scope stays removed: no capability/inventory/cache advertising, no bidding/negotiation, no requester-side selection, no claims/leases, no worker-side `/v1` — in code or schema

### Funding (FUND)

- [ ] **FUND-01**: ELM job funding is deterministic from job JSON (`funding.maximum_processing_hours` × $0.0003/hour) through existing `HoldEscrow`/`AsyncPayEscrow` mechanics — no negotiation, no price lookup
- [ ] **FUND-02**: Per-job clock alignment (lock timeout ≈ deadline ≈ escrow maximum) replaces the fixed 15s subtask lock timeout for ELM jobs, so a generation spanning model download + inference cannot expire its lock mid-flight and be re-grabbed/duplicate-billed
- [ ] **FUND-03**: Model download time is billable job work within the escrow bound; an over-time job reaches a terminal state (not a silent re-grab loop)

### Manifest & Cache (MCHE)

- [ ] **MCHE-01**: The node loads each referenced manifest, verifies its hash, fetches each artifact, and sha256-verifies every artifact — a node never executes a model whose manifest or artifacts fail verification (fail-closed, quarantined on failure)
- [ ] **MCHE-02**: Model bundles live in a content-addressed cache at `cache/<model-manifest-hash>/`, materialized in MNN's expected on-disk layout, with pin-while-processing and verify-before-reuse
- [ ] **MCHE-03**: Cache lifecycle is robust: duplicate downloads single-flighted, partial downloads recovered, LRU eviction under disk pressure, and a model-load smoke check after publish

### Generation (GEN)

- [ ] **GEN-01**: An ELM processor executes causal-LM work items end-to-end: tokenizer + chat-template application, prompt tokenization, prefill, autoregressive KV-cache decode, sampling honoring `temperature`/`top_p`/`seed` (same-node/same-build determinism), stop tokens/strings, detokenization, and accurate prompt/completion token counts
- [ ] **GEN-02**: Mid-generation cancellation aborts in-flight generation promptly when the job's deadline/cancel token fires (via MNN fork patch for `USER_CANCEL` or a documented bounded alternative)
- [ ] **GEN-03**: The ELM processor fits SGProcessingManager's processor family conventions — `VulkanInitMutex` scope narrowed to actual GPU init, temp-dir materialization replaced by the content-addressed cache as single materialization point, no per-execution leaks

### Results (RES)

- [ ] **RES-01**: Every result identifies its originating work item via the existing `SubTask.subtaskid` mapping (subtaskid↔work_item_id map embedded in task JSON); the result envelope carries `work_item_id`, generated text, prompt/completion token counts, and finish reason (`stop|max_tokens|cancelled|error`)
- [ ] **RES-02**: Results flow through the existing gossip results channel and IPFS artifact path unchanged — no SuperGenius-side aggregation; GCS reconstructs the job result by aggregating envelopes by `work_item_id`

### E2E Proof (E2E)

- [ ] **E2E-01**: A single node with an empty cache completes an assigned ELM subtask by downloading a small MNN causal-LM (Qwen-0.5B-class) as part of the phase, generating text honoring settings and stop conditions, and publishing a work-item-tagged result
- [ ] **E2E-02**: Existing (non-ELM) processing jobs remain byte-identical in behavior — splitter, funding, validation, and results paths regress nothing (regression gate in the E2E phase)
- [ ] **E2E-03**: New code carries ≥80% coverage; tests use wait-condition patterns (no sleep-based tests); no breakage of existing SuperGenius/GeniusSDK/GeniusWallet builds

---

## Future Requirements (deferred)

- **Multi-node partitioning / verifier groups** — upstream #369 explicitly defers multi-node ELM partitioning; single-node first
- **Streaming token events** — dropped upstream 2026-08-26; if ever needed, rides existing gossip results channel as seq-numbered JSON events; no `SGElmProcessing.proto`
- **`ipfspubsub://` URL prefix (AsyncIOManager#11)** — out of scope; existing `GossipPubSubTopic` results channel (`RESULT_CHANNEL_ID_<task_id>`) already delivers results natively; verified against code (CreateResultsChannel/OnResultChannelMessage), issue's "blocker" framing stale
- **GCS-side job submission UX** — GCS repo's own planning tracks the requestor side (GCS workstream `app` Phase 6 GCS Bot / ELM routing); this milestone only makes SuperGenius ready to receive and execute
- **Cross-node bit-identical generation** — anti-feature given sgproc-render v2.1/v2.2's proven FP divergence; seeded determinism is scoped to same-node/same-build
- **Escrow wall-clock semantics overhaul** — targeted verification of existing escrow accounting lands in Phase 1 (P1 research flag); any deeper overhaul deferred

## Out of Scope

- **AsyncIOManager#11 (`ipfspubsub://`)** — results channel exists natively; a second URL-ified mechanism adds no SuperGenius-side value this milestone. Owner expressed doubts; code inspection confirms existing delivery suffices
- **No new inference engines** — llama.cpp, ONNX Runtime, etc. excluded; MNN is mandated (vendored fork already ships full LLM engine)
- **No OpenAI `/v1` HTTP surface on worker nodes** — GCS owns the external API; workers expose none
- **No proto changes** — everything rides `Task.json_data`/`SubTask.json_data` exactly as chunked jobs do today
- **No SuperGenius-side aggregation** — GCS aggregates by `work_item_id`; SuperGenius only tags
- **Multi-node tensor/layer partitioning, distributed KV cache, speculative decoding** — explicitly non-goals upstream
- **Existing-build breakage** — SuperGenius/GeniusSDK/GeniusWallet builds must stay green

## Traceability

| REQ-ID | Phase | Status |
|--------|-------|--------|
| JOB-01 | TBD | Pending |
| JOB-02 | TBD | Pending |
| JOB-03 | TBD | Pending |
| JOB-04 | TBD | Pending |
| FUND-01 | TBD | Pending |
| FUND-02 | TBD | Pending |
| FUND-03 | TBD | Pending |
| MCHE-01 | TBD | Pending |
| MCHE-02 | TBD | Pending |
| MCHE-03 | TBD | Pending |
| GEN-01 | TBD | Pending |
| GEN-02 | TBD | Pending |
| GEN-03 | TBD | Pending |
| RES-01 | TBD | Pending |
| RES-02 | TBD | Pending |
| E2E-01 | TBD | Pending |
| E2E-02 | TBD | Pending |
| E2E-03 | TBD | Pending |
