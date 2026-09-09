# Feature Research

**Domain:** Batch LLM-inference job execution riding an existing decentralized processing grid (SuperGenius tasks/subtasks/escrow + SGProcessingManager runtime)
**Researched:** 2026-09-09
**Confidence:** HIGH for scope/anti-features (grounded in upstream issues #369/#17 via `.planning/notes/ELM-bridging-gaps.md` and `SuperGenius/.planning/REQUIREMENTS.md` ELM-01..ELM-09); MEDIUM for ecosystem analogies (OpenAI Batch API, vLLM, Ollama, llama-server patterns — training-data knowledge, not re-verified today); HIGH for generation-semantics table stakes (verified against HuggingFace `GenerationConfig` official docs, 2026-09-09).

**Existing features assumed (NOT re-researched):** job submission (`GeniusNode::ProcessImage`), task splitting, escrow funding at fixed rates, results publication tagged `SubTask.subtaskid` over the gossip results channel, MNN chunked inference, execution manifests with error fields (`errorMessage`, ARTF-09), validation with quantization/tolerance.

---

## Feature Landscape

Scope anchor (ELM-01..ELM-08 + dropped ELM-09) fixes the architectural stance before any feature comparison:

- **The job model rides `Task.json_data`** — no protobuf change for the ELM job definition (ELM-01).
- **The existing grid owns scheduling** — no worker selection, bidding, quotes, intents, claims, leases, or capability/cache advertising (ELM-02, ELM-03).
- **Funding is a constant**, not a market — $0.0003/processing-hour, deterministic from job JSON (ELM-08).
- **Aggregation belongs to the requestor (GCS)**, keyed by `work_item_id` (ELM-07).
- **Streaming proto is dropped** (ELM-09) — streaming, if ever needed, rides seq-numbered JSON events on the existing `Task.results_channel`.

Everything below classifies features within that stance.

### Table Stakes (Users Expect These)

#### A. Job-model JSON shape (`elms[]` in `Task.json_data`)

| Feature | Why Expected | Complexity | Notes / Dependencies |
|---------|--------------|------------|----------------------|
| `job_type: "elm_processing"` discriminator + `version` | Dispatch/evolution without proto changes; every batch system has a request-type tag | LOW | Parse in `ProcessingManager` job-definition path; existing quicktype schema (`gnus-processing-schema.json`) may gain an ELM section OR ELM JSON lives beside the pass array — decide once, keep quicktype-generated (zero hand-edits per SCHEMA-01..05 precedent) |
| `elms[]` array with unique `work_item_id` | One job funding multiple generations is the core product premise (planner/critic/verifier pattern); OpenAI Batch API's `custom_id` is the direct analog — request-level IDs the caller uses to join results | LOW | Uniqueness must be validated at parse time (duplicate IDs → fail job early, not mid-subtask) |
| One work item → one subtask via existing splitter | ELM-01 explicitly: no new ownership protocol; splitter already mints UUID `subtaskid`s (`ProcessTaskSplitter::SplitTask`) | MEDIUM | Splitter currently iterates chunk arrays; needs an ELM branch mapping work item → subtask, and must embed the `work_item_id` ↔ `subtaskid` association in subtask JSON so results can carry it back (validation core and `UpdateResultsFromStorage` key on `subtaskid`) |
| Per-work-item generation settings block | `max_output_tokens`/`temperature`/`top_p`/`seed` are the OpenAI/vLLM/transformers standard four | LOW | See section C — the *contract* is the work, the field presence is trivial |
| Funding block (`funding.maximum_processing_hours`, `escrow_path`) | ELM-08: funding deterministic from job JSON | LOW | Reuses existing escrow plumbing wholesale; see section F |
| Input-by-reference (`input_uri`) | Grid already resolves inputs from IPFS; prompts as CID content keeps `json_data` small and hash-pinned | LOW | Existing input-resolution path (`source_uri_param` machinery) applies |

#### B. Manifest resolution (model bundles: weights/tokenizer/config)

| Feature | Why Expected | Complexity | Notes / Dependencies |
|---------|--------------|------------|----------------------|
| Immutable manifest pointer (URI + hash) in each work item | Content-addressed model distribution is the norm (Ollama sha256 blobs, HF revision pinning); on a trustless grid the hash is the *only* integrity guarantee — TLS-to-nothing, so verification is security-critical, not hygiene | MEDIUM | Manifest JSON: `schema_version`, `elm_type`, `model_format` (MNN), `quantization`, `artifacts[]` (`name`/`uri`/`sha256`/`size_bytes`), `runtime` (`minimum_version`, `required_memory_bytes`) — shape already drafted in ELM-bridging-gaps.md |
| Per-artifact sha256 verification, fail-closed | ELM-04: "a node never executes an unverified model" — this is the single hardest invariant; any verify-then-trust-toctou or skip-on-partial-cache path is a security hole | MEDIUM | Straightforward hashing; the discipline is enforcing it on *every* path (fresh download, cache reuse, partial recovery). Existing sha256 infra from render-path hashing reuses directly |
| Bundle completeness (weights + tokenizer + chat template + config as separate artifacts) | A causal-LM is not just weights: tokenizer vocab, chat template, generation defaults each fail differently; explicit per-artifact hashes let each fail independently and diagnosably | LOW | Note: MNN's LLM runtime bundles tokenizer/template inside the model directory layout — manifest `artifacts[]` must map onto MNN's expected on-disk layout (cache writer materializes MNN's expected structure); flag for phase-level design |
| `runtime.required_memory_bytes` preflight | Loading a 700MB+ model into a device that can't hold it wastes billable download time; capability validator already checks GPU memory/disk (`capability_validator.cpp` categories) | LOW | Feed manifest runtime block into the *existing* `CapabilityValidator` checks — no new advertising (that would violate ELM-03; this is local preflight against the assigned subtask, not eligibility broadcasting) |
| Artifact `size_bytes` in manifest | Enables disk-space preflight and progress/ETA before download; every package registry carries it | LOW | Also feeds cache eviction budgeting (section C) |

#### C. Content-addressed model cache

| Feature | Why Expected | Complexity | Notes / Dependencies |
|---------|--------------|------------|----------------------|
| `cache/<model-manifest-hash>/` keying | Content-addressing gives free dedup across jobs and trivially correct reuse; this is exactly Ollama's blob store and HF's snapshot-cache design | MEDIUM | Directory layout + lock coordination; two subtasks with the same model on one node must not double-download (dedup under concurrency = the real complexity) |
| Verify-before-reuse | Disk corruption/bitrot or a truncated prior run must never yield a silently-wrong model; ELM-05 lists it explicitly | MEDIUM | Cheaper than re-download (hash local files) but must be non-optional on every reuse path |
| Pin-while-processing (refcount) | Evicting a model mid-generation destroys the subtask; ELM-05 explicit | MEDIUM-HIGH | Pin/refcount + eviction interplay is the subtlest cache bug class (leaked pins = cache never shrinks; premature unpin = crash mid-decode). Needs a deterministic unpin on every terminal path incl. cancellation |
| Eviction under disk pressure (LRU over unpinned) | A node processing many different models will fill any disk; ELM-05 explicit | MEDIUM | Evict-only-unpinned rule; manifest `size_bytes` makes budget arithmetic trivial; `std::filesystem::space` or config cap |
| Partial-download recovery (atomic temp + rename) | IPFS fetches of 300MB+ artifacts will be interrupted; without staging, a half-file looks like a corrupted model and forces full re-download | LOW-MEDIUM | Standard pattern: download to `cache/.staging/<hash>.part`, verify, atomic rename into place. Recovery = resume or restart the .part, never trust it |
| Cold-cache node completes any assigned subtask | ELM-05: cache state "never advertised and never affects eligibility" — this is what keeps the grid flat | LOW | Falls out of fetch-on-miss + billable download; the E2E proof (empty cache → download → generate) is the acceptance test |

#### D. Generation-settings contract (determinism, stop conditions, token accounting)

| Feature | Why Expected | Complexity | Notes / Dependencies |
|---------|--------------|------------|----------------------|
| `temperature` with greedy at 0.0 | Universal contract (OpenAI, vLLM, transformers `do_sample`); `temperature=0` → greedy argmax is what makes planner-style work items reproducible | MEDIUM | Must define: `temperature`/`top_p` bounds validation at parse time (reject, don't clamp — deterministic funding wants deterministic jobs); HF defaults temperature=1.0, top_p=1.0 (verified) |
| `top_p` nucleus sampling | The standard companion knob (HF: smallest set with cumulative prob ≥ top_p, verified 2026-09-09) | MEDIUM | Define the nucleus *tie-break and ordering* rule precisely (sort by prob desc, stable tie-break by token id) or seeded determinism is illusory |
| `seed` → deterministic sampling | ELM asks for it; the contract that matters is: same model+prompt+settings+seed → same tokens **on the same runtime build**. This is per-work-item (integer in JSON), NOT the job-level `Task.random_seed` float (which exists in proto but is the wrong granularity/type — note and avoid) | HIGH | Requires an explicitly-specified seeded RNG for the sampling step (e.g., seed → per-step PRNG stream), independent of global state. **Scope nuance:** deterministic *procedure*, not cross-hardware bit-identity — sgproc-render v2.1/v2.2 proved cross-hardware FP divergence is real; do NOT promise cross-node identical generations in v1 (see Anti-Features) |
| `max_output_tokens` | HF `max_new_tokens` (recommended over `max_length` — verified); OpenAI `max_tokens`; the primary cost bound | LOW | Count is completion-only, excluding prompt (HF semantics, verified) |
| Stop tokens AND stop strings | HF has both `eos_token_id` (token-level) and `stop_strings` (string-level, verified); chat models need EOS from tokenizer config *plus* app-level stop strings ("```\n" etc.) | MEDIUM | String-level stop must be checked against detokenized text incrementally (a stop string can straddle token boundaries) — classic off-by-one; define whether the stop string itself is included in output (OpenAI: excluded) |
| Chat-template application | Modern causal LMs are instruction-tuned; raw prompt vs templated prompt produces garbage; template ships as a manifest artifact | MEDIUM | Template rendering (Jinja-subset in MNN's runtime or pre-rendered); must be deterministic and hash-pinned via manifest |
| Prompt tokenization + prefill + autoregressive decode with KV cache | The definition of causal-LM execution; KV cache is what makes decode not-O(n²) per token | HIGH | MNN LLM runtime provides tokenizer/prefill/decode/KV-cache primitives — the processor wraps and drives them; this is the single largest new-code surface (ELM-06) |
| Detokenization incl. UTF-8 boundary handling | Tokens are byte fragments; naive per-token decode corrupts multi-byte UTF-8 (CJK, emoji) split across tokens | MEDIUM | Incremental detokenizer with a pending-bytes buffer is the known-good pattern |
| Accurate `prompt_tokens`/`completion_tokens` counts | Feeds GCS aggregation, billing audit, and `max_output_tokens` enforcement; OpenAI usage object is the universal shape | LOW | Count from the tokenizer, never `text.length()/4` heuristics |
| Mid-generation cancellation | Long generations must be killable; existing cancellation machinery (budget/cancellation/timeout test suites) already exists in `ProcessingManager` | MEDIUM | Decode loop must poll the cancel token between steps AND the result must terminate cleanly with `finish_reason: "cancelled"` (not an error); manifest error path (ARTF-09) records it |

#### E. Result envelope (per work item)

| Feature | Why Expected | Complexity | Notes / Dependencies |
|---------|--------------|------------|----------------------|
| `work_item_id` + `subtask_id` echo | OpenAI Batch API pattern: output keyed by request's `custom_id`; GCS joins on `work_item_id` (ELM-07). The `subtaskid` tagging on the results channel already exists — the envelope adds the work-item join key | LOW | Splitter must persist the mapping (section A); result JSON carries both |
| Generated text (UTF-8) | The product output | LOW | Detokenized, stop-string-trimmed |
| `finish_reason` ∈ {`stop`, `max_tokens`, `cancelled`} | OpenAI's enum (stop/length) is table stakes; grid adds `cancelled` as a *terminal success-shaped* state so partially-funded work reports honestly | LOW | Distinct from error paths: model-load failure / manifest-verify failure / tokenizer error = structured *errors* via existing manifest `errorMessage` + error codes, not finish reasons. Keep the two axes separate (outcome vs failure) |
| Token counts (`prompt_tokens`, `completion_tokens`) | Usage/billing audit; pairs with section D | LOW | Same counters as enforced by `max_output_tokens` |
| Model provenance echo (`model_manifest_hash`) | On a grid, the requestor must be able to prove *which* model produced text; centralized APIs skip this because their model inventory is implicit | LOW | Copy from work item into result |
| Aggregation-friendly shape (flat, one JSON per work item, no SuperGenius-side rollup) | ELM-07: aggregation is GCS's job; each result must stand alone | LOW | No cross-work-item references, no job-level summaries from the node |

#### F. Funding

| Feature | Why Expected | Complexity | Notes / Dependencies |
|---------|--------------|------------|----------------------|
| Deterministic funding from job JSON at $0.0003/hour | ELM-08; no negotiation is the *simplification* this milestone bought by deleting the market layer | LOW | Compute-and-cap from `funding.maximum_processing_hours` through existing escrow; rate is a constant |
| Model download is billable job work | ELM-08 explicit; a node spending 20 min fetching a 300MB model must be paid or nobody serves cold-cache work | LOW-MEDIUM | Confirm existing accounting measures wall-time from subtask start (it should then naturally include fetch); if accounting only measures compute, the fetch phase needs explicit inclusion — verify in phase planning, don't assume |

### Differentiators (Competitive Advantage)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Fail-closed hash-verified model execution on a decentralized grid | Centralized inference guarantees integrity only via transport TLS; a content-hash-pinned manifest → verified-artifact chain gives cryptographic provenance from job JSON to executed weights — a genuinely stronger guarantee than OpenAI/vLLM deployments offer | (covered as table stakes B — the *differentiating* part is it being unconditional) | The E2E proof must demonstrate the negative path too: corrupted artifact → refusal to execute (SECV-01/02 counter-test precedent from sgproc-render) |
| Per-work-item seeded determinism | Reproducible generation on demand (same seed → same text, same node/build) — lets GCS re-run a planner step for audit, and makes single-node validation of re-executed work items meaningful | HIGH (already in table-stakes scope) | Deliberately scoped: determinism-of-procedure, not cross-hardware bit-identity |
| Any-node-eligibility with cold cache | Warm-cache preference (vLLM-style prefix caching affinity, scheduler model-locality) is deliberately rejected: flat eligibility keeps the provider pool open — a small-node-friendly differentiator vs centralized serving | (free — it's the absence of a feature) | Guard: nothing in assignment code may read cache state (ELM-03/ELM-05) |
| Work-item-granular escrow at a posted fixed rate | Per-call transparent pricing without a market — jobs are precomputable in cost from JSON alone (`hours × $0.0003`), unlike token-priced APIs | LOW | Deterministic quote = the job JSON itself |
| Content-addressed cache shared across jobs/tenants | One node serving many requestors dedups models by hash — the decentralized analog of an org-level HF/Triton model store, for free, via content addressing | (falls out of table-stakes C) | Cache directory sizing/ops guidance is the only add |

### Anti-Features (Commonly Requested, Often Problematic)

**Upstream-corrected (issue #369 revision, binding via ELM-02/ELM-03/ELM-09) — these stay removed:**

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Streaming token proto (`SGElmProcessing.proto`, `ElmTokenDelta`/`ElmProgress` events) | Feels necessary for chat UX | Dropped per ELM-09 (owner decision 2026-08-26): adds a proto surface + ordering/retransmission concerns the grid doesn't need for batch jobs | If ever needed: seq-numbered JSON events on the existing `Task.results_channel` gossip topic — zero proto change |
| Capability/inventory advertising (`NodeElmCapabilities`, model/cache/warm inventory broadcast) | "Route to the node that already has the model" | Duplicates the scheduler's job, leaks node state, and creates cache-state-dependent eligibility (violates ELM-03/ELM-05, penalizes new nodes) | Fetch-on-miss content-addressed cache; warm cache shows up as faster execution, nothing else |
| Bidding/negotiation (`ElmProcessingIntent`, per-node quotes, price-policy negotiation, resource bidding) | Market dynamics seem natural for a compute grid | Reimplements scheduling on top of the existing scheduler; the #369 correction is explicit: SuperGenius *is* the scheduler | Fixed posted rate ($0.0003/hour) + deterministic funding from job JSON (ELM-08) |
| Requester-side worker selection / GCS-managed claims & execution leases | Requestor control over placement | Breaks the grid's ownership/queue model; GCS becomes a scheduler-of-schedulers | Existing grid assigns subtasks; GCS only funds, publishes, and aggregates |
| Worker-side `/v1` OpenAI-compatible endpoints / named-model registration | "Every node an inference server" | Turns processor nodes into vertically-integrated services, inverts the funding flow, invites per-model pricing | GCS (requestor side) exposes `/v1`; workers execute funded grid jobs only |
| SuperGenius-side cross-work-item aggregation | "The network should return one tidy job result" | Couples grid to one consumer's semantics; GCS owns orchestration semantics (planner→critic→verifier chains are GCS policy) | Per-work-item envelopes; GCS joins by `work_item_id` (ELM-07) |
| Protobuf changes for the ELM job definition | "Real schemas belong in proto" | Breaks wire compatibility for a field that is already a bytes blob by design; quicktype-generated JSON schema already governs job definitions | `elms[]` in `Task.json_data`, schema-versioned in JSON (ELM-01) |

**Ecosystem-informed anti-features (avoid importing by reflex):**

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Cross-node bit-identical generation outputs (validation by re-execution compare) | Mirrors the render path's hash-compare validation | Cross-hardware FP divergence is proven real on this codebase (sgproc-render v2.1/v2.2's entire reason to exist); seeded sampling does not remove it; promising it creates an un-closeable verification gap in v1 | v1: single-node E2E, determinism scoped to same-node/same-build. If cross-node validation arrives later: compare via seeded re-execution with tolerance, or zk-proof direction — separate milestone, flagged in PITFALLS |
| Beam search / full logits-processor suite (repetition_penalty, min_p, typical_p, top_k, no_repeat_ngram...) | HF GenerationConfig exposes ~40 knobs | Each knob multiplies the determinism-spec surface and test matrix; GCS's planner/critic workloads need four (verified against HF docs: the requested four map exactly to temperature/top_p/max_new_tokens/seed + stop conditions) | Ship the contract four + stop tokens/strings; leave a versioned `generation` object to add knobs later without schema break |
| Continuous batching / speculative decoding / paged-KV tuning | vLLM-class throughput | Premature for one-work-item-per-subtask batch semantics; MNN runtime owns its KV-cache internals; adds enormous complexity for a single-node E2E milestone | Sequential per-subtask generation; batching belongs to future throughput milestones if grid volume justifies |
| Token-streaming billing (per-token metering) | Fine-grained cost attribution | Grid bills processing-hours via escrow — dual accounting invites drift | Wall-time through existing accounting incl. download (ELM-08); token counts are *reporting*, not billing |

## Feature Dependencies

```
[Job model: elms[] in Task.json_data]
    └──requires──> [Splitter: work_item_id ↔ subtaskid mapping]
                        └──requires──> [Existing subtask queue / results channel (unmodified)]

[Manifest resolution (load+hash-verify+fetch artifacts)]
    └──requires──> [Job model (manifest uri+hash per work item)]
    └──requires──> [Existing IPFS fetch path]
    └──requires──> [Content-addressed cache]

[Content-addressed cache]
    └──requires──> [Manifest resolution (hash = cache key)]
    └──enhances──> [Manifest resolution (dedup, partial recovery)]

[ELM runtime (tokenize → template → prefill → decode → sample → detokenize)]
    └──requires──> [Manifest resolution (verified tokenizer/weights/template)]
    └──requires──> [Generation-settings contract (validated settings block)]
    └──requires──> [Existing cancellation + budget machinery (poll between steps)]

[Work-item result envelope]
    └──requires──> [Splitter mapping (work_item_id echo)]
    └──requires──> [ELM runtime (text, counts, finish_reason)]
    └──requires──> [Existing SubTask.subtaskid tagging (unmodified)]

[Funding: deterministic from job JSON @ $0.0003/h]
    └──requires──> [Existing escrow/accounting (unmodified)]
    └──requires──> [Job model (funding block)]
    [Billable download] ──requires──> [Fetch counted in processing time — VERIFY existing accounting measures from subtask start]
```

### Dependency Notes

- **Runtime requires manifest+cache before any generation:** the E2E ordering (empty cache → download → verify → generate) is itself the acceptance test.
- **Result envelope depends on splitter mapping, not on runtime internals:** the envelope schema can be pinned (and GCS-side consumers mocked) before the runtime is complete — useful phase separation.
- **Cancellation spans cache and runtime:** a cancel during model fetch must release the cache pin and record a terminal manifest — the pin/refcount and cancellation paths must be designed together, not sequenced.
- **Validation interplay (flag for phase research):** the existing `ProcessingValidationCore` compares per-chunk hashes *across subtasks* — meaningful only when subtasks redundantly cover the same chunks. ELM work items are unique work (no redundant execution in v1), and the synthetic `subtask_validation` subtask assumes chunk semantics. ELM results likely bypass chunk-hash validation in v1; how the queue finalizes without it needs explicit phase-level design.

## MVP Definition

### Launch With (v1) — matches elmbridge v1.0 milestone scope

- [x] Job model — `job_type`/`elms[]`/unique `work_item_id`/settings block in `Task.json_data`; one work item → one subtask (ELM-01)
- [x] Deterministic funding from job JSON at $0.0003/h, download billable (ELM-08)
- [x] Manifest resolution — hash-verify manifest, sha256-verify every artifact, fail-closed (ELM-04)
- [x] Content-addressed cache — `cache/<manifest-hash>/`, dedup, pin, verify-reuse, evict, partial recovery (ELM-05)
- [x] ELM runtime — tokenize/template/prefill/decode+KV/sample (temp/top_p/seed, greedy@0)/stops/detokenize/counts/cancel (ELM-06)
- [x] Work-item result envelope — `work_item_id`+`subtask_id`, text, counts, `finish_reason` (stop/max_tokens/cancelled) (ELM-07)
- [x] Anti-feature guardrails held — no advertising/bidding/claims/leases/streaming-proto/proto-changes (ELM-02, ELM-03, ELM-09)
- [x] E2E proof — single node, empty cache, downloads a small MNN causal-LM (Qwen-0.5B-class), completes an assigned ELM subtask

### Add After Validation (v1.x)

- [ ] Corrupted-artifact counter-test (SECV-style: wrong hash → refusal, provably) — trigger: security review of the fail-closed invariant
- [ ] Cache observability (hit/miss/eviction stats surfaced locally) — trigger: node-operator demand
- [ ] Additional sampling knobs (`top_k`, `repetition_penalty`) behind the versioned `generation` object — trigger: GCS workload evidence
- [ ] Multi-work-item fan-out across >1 node — trigger: first multi-node milestone

### Future Consideration (v2+)

- [ ] Cross-node result validation (tolerance or proof-based) — blocked on the determinism scoping above; needs its own research pass
- [ ] Streaming events over the existing results channel (seq-numbered JSON) — only if an interactive consumer appears
- [ ] Continuous batching / throughput work — only with demonstrated grid volume

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Job model JSON + splitter mapping | HIGH | LOW-MEDIUM | P1 |
| Manifest resolution, fail-closed verification | HIGH | MEDIUM | P1 |
| Content-addressed cache (pin/verify/evict/recover) | HIGH | MEDIUM-HIGH | P1 |
| ELM runtime (generation semantics, all of section D) | HIGH | HIGH | P1 |
| Work-item result envelope | HIGH | LOW | P1 |
| Deterministic funding (reuse escrow) | HIGH | LOW | P1 |
| Chat-template artifact separation | MEDIUM | LOW-MEDIUM | P1 (needed by Qwen-class models) |
| Runtime preflight (memory/version from manifest) | MEDIUM | LOW | P2 |
| Cache stats/observability | LOW | LOW | P3 |
| Extra sampling knobs | LOW | MEDIUM (test matrix) | P3 |
| Streaming events on results channel | LOW | MEDIUM | P3 |

## Competitor / Ecosystem Feature Analysis

Ecosystem analogies (MEDIUM confidence, training-data based unless noted):

| Feature | OpenAI Batch API | vLLM / llama-server | Ollama | Our Approach |
|---------|------------------|---------------------|--------|--------------|
| Request→result join key | `custom_id` echoed per line | n/a (synchronous server) | n/a | `work_item_id` ↔ `subtaskid` in envelope (ELM-07) |
| Result envelope | JSONL: id, status, usage, finishReason-like | OpenAI-shaped usage/finish_reason | final response object | JSON: work_item_id, text, counts, finish_reason + provenance hash |
| Sampling contract | temperature/top_p/seed/max_tokens/stop | SamplingParams incl. stop_token_ids | Modelfile PARAMETERs | Same four + stop tokens/strings, per-work-item in job JSON (HF GenerationConfig semantics verified 2026-09-09) |
| Model distribution/integrity | opaque, server-side | local files, no hash pinning | sha256 content-addressed blob store (closest analog) | Manifest (URI+hash) → sha256-verified artifacts, fail-closed — strongest integrity chain of the set |
| Caching | n/a | prefix/KV cache (performance) | blob store, dedup by hash | `cache/<manifest-hash>/` with pin/evict/recovery — Ollama-style addressing + grid lifetime semantics |
| Scheduling/pricing | platform-set | self-hosted | local | Grid-assigned, posted fixed rate $0.0003/h, no market (ELM-08) |
| Determinism | seed honored (same infra) | seed per request | seed param | Seeded per work item; explicitly same-node/same-build scoped |

## Sources

- **Authoritative scope:** `SuperGenius/.planning/notes/ELM-bridging-gaps.md` (issue #369/#17 analysis: removed scope, manifest/cache/runtime design, funding model) — HIGH
- **Requirements:** `SuperGenius/.planning/REQUIREMENTS.md` ELM-01..ELM-08 + dropped ELM-09 (rate resolved $0.0003/h by owner) — HIGH
- **Existing behavior verified in-repo:** `SuperGenius/src/processing/processing_tasksplit.cpp` (UUID subtaskids, `subtask_validation`), `processing_subtask_queue_accessor_impl.cpp` (results keyed by subtaskid), `processing_validation_core.cpp` (cross-subtask chunk-hash validation), `SGProcessingManager/src/processingbase/ProcessingManager.cpp` + `generated/PassType.hpp` (quicktype schema, pass-type recognition), `include/artifacts/execution_manifest.hpp` (subtaskId, ARTF-09 errorMessage) — HIGH
- **Generation semantics:** HuggingFace Transformers `GenerationConfig` official docs (temperature/top_p/max_new_tokens/stop_strings/eos_token_id semantics; greedy vs sampling mode selection) — fetched 2026-09-09 — HIGH
- **Ecosystem analogies** (OpenAI Batch API `custom_id`/usage/finish_reason; vLLM SamplingParams; Ollama sha256 blob store): training-data knowledge, consistent with verified HF semantics — MEDIUM

---
*Feature research for: ELM (Expert Language Model) job execution on the SuperGenius processing grid*
*Researched: 2026-09-09*
