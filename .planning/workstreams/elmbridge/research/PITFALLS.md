# Pitfalls Research

**Domain:** Adding ELM (Expert Language Model) job execution to the existing SuperGenius processing grid + SGProcessingManager
**Researched:** 2026-09-09
**Confidence:** HIGH (nearly all pitfalls verified directly against workspace source: `thirdparty/MNN/transformers/llm/engine/**`, `SuperGenius/src/processing/**`, `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_llm.cpp`; the few unverified items are flagged inline)

**Scope note:** The elmbridge roadmap does not exist yet (`workstreams/elmbridge/phases/` is empty). Phase attribution below uses the four logical build-order phases the milestone's feature list implies — **P1 Job Model & Funding**, **P2 Manifest & Model Cache**, **P3 ELM Processor**, **P4 Grid Integration & E2E** — ordered by hard dependency (schema → cache → processor → proof). The roadmap should adopt or refine these names and carry the mappings forward.

---

## Critical Pitfalls

### Pitfall 1: MNN's sampler has NO seed support — deterministic sampling cannot be "configured," it must be built

**What goes wrong:**
The design requires sampling with `temperature`/`top_p`/`seed`. The vendored MNN sampler is constructed `mRng(std::random_device{}())` (`thirdparty/MNN/transformers/llm/engine/src/sampler.cpp:162`) and reads sampler config keys (`sampler_type`, `temperature`, `topK`, `topP`, `penalty_sampler`, ...via `llmconfig.hpp:359-425`) — **there is no `seed` config key anywhere**. Every sampled generation is unseeded and unrepeatable, even on the same machine.

**Why it happens:**
MNN's LLM API targets interactive chat apps (see `apps/iOS/MNNLLMChat`), where reproducibility is a UI nicety exposed by re-instantiating the model, not a wire-level contract. `set_config()` (`llm.cpp:101`) merges arbitrary JSON but silently ignores unknown keys — so passing `{"seed": 12345}` *appears* to work and does nothing.

**How to avoid:**
- Treat seed plumbing as an MNN-fork change, not an SGProcessingManager change: add a `seed` key to `Sampler` construction (seed the `std::mt19937 mRng` member, `sampler.hpp:76`) or expose a `Sampler::seed(uint32_t)` setter, exactly like the fork already carries local patches (`LlmStatus::USER_CANCEL`/`TIMEOUT` additions are not upstream stock either).
- Alternatively implement sampling in SGProcessingManager: take raw logits from the MNN forward pass and run a project-owned, explicitly-seeded sampler. Higher effort but removes fork divergence risk.
- Either way, document that `temperature=0` (greedy) is the only *guaranteed*-deterministic mode without fork changes.

**Warning signs:**
Two runs of the same work item with identical `seed` produce different output text; a "seed" config key passes through `set_config()` with no error and no effect.

**Phase to address:**
**P3 (ELM Processor).** The decision (fork-patch vs own sampler) determines the processor's internal loop structure; it cannot be deferred past P3 planning.

---

### Pitfall 2: Cross-node result validation expects byte-exact hashes — LLM text breaks the validation regime in BOTH directions

**What goes wrong:**
The existing validation path (`ProcessingValidationCore::ValidateResults` + per-chunk hashes, hardened across sgproc-render v2.1–v2.3) compares quantized output hashes across subtasks. Text generation outputs discrete tokens — but the *logits* that select tokens are floats, and this project has already proven (v2.1–v2.3) that cross-hardware FP divergence is real and workload-dependent (`spleen_ct_seg`: all 25 chunk hashes mismatched; MNN float fixture chunk-10 residual gap). Near-tied logits under argmax can flip across GPUs — the exact same class as the S=2^15 tie-break boundary already characterized — producing genuinely different token streams on different hardware. With seeded sampling (Pitfall 1), RNG parity across platforms/libstdc++ versions is an *additional* divergence source.

Consequences in both directions:
1. **False invalidation:** redundant execution on a second node produces a legitimate-but-different text result; `ValidateResults` marks chunks mismatched → subtask invalidated → re-queued → re-billed.
2. **False confidence:** quantized hashing of text bytes is *stricter than float* (byte identity), so no quantScale setting can absorb a token-level divergence — a single flipped token changes the entire tail of the text.

**Why it happens:**
The validation core was designed for numeric tensor outputs where bounded divergence is meaningful and quantization grids can absorb it. Tokens are discrete; there is no "nearby token."

**How to avoid:**
- Decide the validation semantics for `elm_processing` subtasks explicitly in P1's job-model design: for v1.0 single-node E2E, redundant-execution comparison simply doesn't run — say so in the schema (per-work-item `validation: none | exact | redundant` with `none` the v1.0 default) rather than silently inheriting the tensor regime.
- If/when cross-node ELM validation is needed, validate *provenance* (manifest hash, input hash, work_item_id match) not output bytes; output equality can only be expected at `temperature=0`, and even then only same-backend.

**Warning signs:**
An E2E test that "helpfully" enables `addvalidationsubtask` for an ELM job and flakes with chunk-hash mismatches; a requirement that mentions "deterministic output across nodes" without restricting to greedy sampling on identical backends.

**Phase to address:**
**P1 (Job Model)** for the schema-level validation-mode decision; **P4** for the E2E test that must *not* enable redundant validation.

---

### Pitfall 3: The 15-second subtask lock timeout will kill every real ELM subtask — and the re-grab loop duplicates work and burns funds

**What goes wrong:**
`ProcessingSubTaskQueueManager` defaults `m_processingTimeout( std::chrono::seconds( 15 ) )` (`processing_subtask_queue_manager.cpp:21`), and **`SetProcessingTimeout()` has zero production callers** (verified: only its definition and header declaration exist). Locked subtasks whose lock expires are unlocked (`ProcessingSubTaskQueue::UnlockExpiredItems`) and re-grabbed by another node. A 300MB model download plus multi-minute prefill/decode takes *minutes*. Sequence on an empty-cache grid: node A grabs ELM subtask → downloads model → at 15s the lock expires → node B grabs the same subtask → starts its own download → at 30s… every participant downloads the model repeatedly, nobody finishes before expiry, results race, and the job either never completes or pays multiple nodes for the same work.

**Why it happens:**
15s is calibrated for the existing millisecond-to-seconds MNN/Vulkan inference subtasks. ELM subtasks introduce two new duration classes (download, generation) that never existed in the queue.

**How to avoid:**
- In P1, derive the subtask lock timeout from the job's `funding.maximum_processing_hours` (converted with margin, floor-bounded), and wire it through `SetProcessingTimeout()` / `processing_timeout_length` (`SGProcessing.proto:61`) when the ELM task is enqueued — per-job, not global.
- Keep the two duration classes separate in accounting: download is bounded by content length; generation is bounded by `max_output_tokens` × worst-case per-token time. The lock timeout must cover both plus margin.
- Add an integration test that asserts a subtask still holding a valid lock at t=60s is NOT re-grabbed when the ELM timeout is configured.

**Warning signs:**
E2E test logs showing `[GRABBED]` for the same `subtaskid` from two node IDs; `Recovered expired-locked task` debug lines during a healthy ELM run; subtask results arriving from multiple nodes.

**Phase to address:**
**P1 (Job Model & Funding)** — the funding struct is where `maximum_processing_hours` lives, and the timeout derivation is part of enqueueing. **P4** verifies it end-to-end.

---

### Pitfall 4: `GetProcessCost` is byte-based — the $0.0003/hour model is new accounting, not a parameter change

**What goes wrong:**
`GeniusNode::GetProcessCost` (`GeniusNode.cpp:2381`) computes escrow from `ParseBlockSize()` (input bytes) × GNUS price via `CalculateCostMinions`. The ELM design prices by `maximum_processing_hours` at a fixed $0.0003/hour, and additionally declares model *download* to be billable job work. Reusing the existing path silently prices ELM jobs by input JSON size — a 2KB prompt with a 300MB model and an hour of generation would escrow essentially nothing, and the escrow would run out mid-generation with no accounting for the download that already happened.

**Why it happens:**
The existing cost model predates time-based work. Hours-based funding touches `HoldEscrow`, `CreateEscrowInfoCRDTTransaction`, payout on completion — a chain, not a constant.

**How to avoid:**
- P1 adds an `elm_processing` branch in cost computation: `funding.maximum_processing_hours` (hard upper bound, escrowed up front) with actual settlement by measured wall-clock (start of subtask grab → result publication, download included). Escrow the declared maximum; refund the unused remainder — never the reverse (pay-as-you-go would allow underfunded infinite jobs).
- Define *when the clock runs* precisely: from subtask grab (before download) to result publication, per subtask. Model-cache hits therefore cost the requestor less — which is fine and matches "warm cache improves execution time" without changing assignment policy.
- Cross-check the GNUS price fetch (`GetGNUSPrice`) failure path: today it returns 0 cost → job rejected. For ELM, a fixed USD rate must convert to GNUS at escrow time and the rate must be recorded in the escrow transaction, or settlement disputes arise when the price moves.

**Warning signs:**
An ELM job posting succeeds with an escrow balance that is obviously below one hour at the advertised rate; settlement code that divides hours by a price fetched at *payout* time instead of escrow time.

**Phase to address:**
**P1 (Job Model & Funding).**

---

### Pitfall 5: `VulkanInitMutex` is held across the entire model load — one ELM subtask stalls every other processor on the node

**What goes wrong:**
`MNN_Llm::LoadModel` takes the process-wide `sgns::sgprocessing::VulkanInitMutex()` and holds it across `createLLM()` **and `llm->load()`** (`processing_processor_mnn_llm.cpp:100-108`) — i.e., across the full multi-hundred-MB weight load. Every other MNN processor and the RenderProcessor share this mutex (the whole 21-processor migration runs under it, sgproc-render MIGR-01). While an ELM subtask loads a 300MB model, all inference on that node blocks — heartbeats aside, subtask grabs and result publications queue behind the asio work that needs the lock. Worse: two concurrent ELM subtasks on the same node serialize their loads behind the mutex.

**Why it happens:**
The mutex exists to serialize MNN/Vulkan *context creation*. The existing call sites take it for short init windows; model loading was folded into that window because `createLLM` + `load` is one API sequence.

**How to avoid:**
- P3/P2 must split the critical section: take `VulkanInitMutex()` only for the shortest MNN runtime/context-creation window that is actually required, verify (by test) that `load()` of weights does not need the global lock, or introduce a dedicated `LlmLoadMutex` that serializes LLM loads against each other but not against the rest of the grid. If the vendored MNN requires the executor-scope lock for load, then bound the damage: load once per cache entry, not per subtask (Pitfall 6), so the lock is held once per model per node, not per work item.
- Add a concurrency test: start a render/MNN subtask, then begin an LLM model load, assert the first completes within its normal time.

**Warning signs:**
Node logs showing a long gap between `LOAD_MODEL` progress events on any processor whenever an ELM subtask starts; E2E throughput dropping to serial when two ELM subtasks run on one node.

**Phase to address:**
**P2 (cache = load-once-per-model, which bounds lock frequency)** and **P3 (lock-scope fix)** — the test belongs to P3.

---

### Pitfall 6: Per-subtask model materialization leaks temp dirs AND re-loads the model per work item — the cache must own the MNN session lifecycle

**What goes wrong:**
The current LLM processor materializes model bytes to `sgproc_mnn_llm_<timestamp>/` under the temp directory and **never deletes it** (verified: `remove_all`/`filesystem::remove` appear nowhere in SGProcessingManager source; the only `temp_directory_path` use is the materializer itself). Every subtask = one full model copy on disk, forever. Combined with the design's per-work-item subtasks (`elms[]` → N subtasks), a 3-work-item job on a cold node writes the model 3 times. Also note the timestamp-based directory name is not concurrency-safe (`high_resolution_clock` collisions under thread contention) and not namespaced per process.

**Why it happens:**
`MNN::Transformer::Llm::createLLM()` structurally requires a *directory path* (expects `llm_config.json` + weights on disk); the in-memory `createFromBuffer` path used by the other 21 processors doesn't exist for LLM. The materializer was written for a single-pass processor with no cache concept.

**How to avoid:**
- P2's content-addressed cache (`cache/<model-manifest-hash>/`) becomes the *single* materialization point: the cache layer fetches + verifies + lays out the full MNN bundle directory (model + tokenizer + `llm_config.json` — see Pitfall 7) atomically (download to `cache/.tmp-<uuid>/`, verify sha256 of every artifact, `rename()` into place — same-filesystem rename is atomic), and the processor loads from the cache path. The processor's private materializer is deleted, not reused.
- Cache pinning: refcount per manifest-hash while subtasks are executing; eviction (when eventually added) must refuse to delete a pinned entry, and on Windows must handle locked-file failure (POSIX unlink-while-open succeeds; Windows doesn't).
- Generation must run against the *pinned* path for its entire duration — a second subtask arriving mid-generation shares the same entry via refcount, not a second copy.

**Warning signs:**
`%TEMP%` filling with `sgproc_mnn_llm_*` directories during a test run; two concurrent subtasks producing two cache directories for the same manifest hash.

**Phase to address:**
**P2 (Manifest & Model Cache)** for the atomic layout + pinning; **P3** retargets the processor at the cache path and removes the private materializer.

---

### Pitfall 7: MNN LLM expects a *bundle directory*, not a single model blob — tokenizer/config mismatch is the default failure, not an edge case

**What goes wrong:**
The existing processor writes one `model.mnn` file and passes the directory to `createLLM()`. MNN's LLM engine expects the directory to contain `llm_config.json` and tokenizer assets alongside weights (`llm.hpp` createLLM(config_path); tokenizer/chat-template loading in `llm.cpp` `setChatTemplate()` reads the config's `chat_template`/jinja block). A single-blob flow either fails to load outright or silently skips chat-template/tokenizer setup, producing garbage tokenization. Separately: a manifest whose `tokenizer` artifact belongs to a *different model revision* than the weights produces plausible-looking but wrong output — token ID shifts turn generation into noise with no error anywhere.

**Why it happens:**
Every other MNN processor in this repo takes a single `.mnn` buffer, so the natural instinct is to treat LLM the same. LLM is architecturally multi-file.

**How to avoid:**
- P2's manifest schema must enumerate artifacts exactly as the design does (`model`, `tokenizer`, `chat_template`) **and** specify the on-disk bundle layout MNN expects (`llm_config.json` naming, vocab file names) — the cache layer's job is producing a *loadable directory*, not storing files.
- Verification is per-artifact sha256 (already in the design) plus one *loadability smoke check*: after materialization, `createLLM` + `load()` + a 1-token greedy generation must succeed before the entry is marked usable. This converts "wrong tokenizer" from silent garbage into a structured `RESOURCE_RESOLUTION` error.
- Fail closed on any manifest artifact missing from the directory — never execute an unverified model (the design already mandates this; the smoke check enforces it).

**Warning signs:**
Generated text that is fluent-ish but subtly wrong in a way that differs between two cache entries for "the same" model; `createLLM` succeeding but `tokenizer_encode` returning unexpected token counts; the processor's fallback path writing only `model.mnn`.

**Phase to address:**
**P2 (Manifest & Model Cache)** for layout + smoke check; **P3** consumes it.

---

### Pitfall 8: TOCTOU on cache verification — verify-then-use must be verify-at-rest plus atomic publish

**What goes wrong:**
The naive sequence — "on cache hit, re-verify sha256, then load" — has two holes. (a) A crash mid-download in P2's predecessor style (partial directory at the final path) means later "hits" verify a corrupt artifact, fail, and if the failure path doesn't *quarantine* the entry, every subsequent subtask re-verifies the same 300MB and re-fails (grid livelock on a poisoned cache entry). (b) Two subtasks on the same node wanting the same model simultaneously both see "missing," both download (bandwidth ×2, escrow billed ×2 under download-is-billable), then race writing the same directory.

**Why it happens:**
Verification is usually bolted on as a read-time check instead of a publish-time gate, and single-node concurrency is forgotten because the old processors had no shared cache.

**How to avoid:**
- Publish-time gate (Pitfall 6's atomic rename): an entry at its final path is by construction complete and verified; a `.tmp-` staging name is never loaded. Then read-time re-verification is a *cheap integrity option*, not the correctness mechanism — mark it optional for trusted-local-disk v1.0, mandatory when the cache dir is shared/external.
- Single-flight per manifest hash: a per-node map `manifest-hash → in-flight download (shared_future)` so the second subtask awaits the first download; plus a poison quarantine (rename to `.bad-<hash>` on failed verification) so a corrupt entry can't livelock the queue — and log/telemetry the quarantine event.
- Corollary: kill the "re-verify before reuse" requirement's cost by verifying sizes first (`size_bytes` is in the manifest design) — a mismatch is an instant quarantine without hashing 300MB.

**Warning signs:**
Duplicate concurrent downloads of the same hash in node logs; a subtask failing repeatedly with verification errors without the cache entry ever being evicted; bandwidth spikes ×N on an N-work-item job.

**Phase to address:**
**P2 (Manifest & Model Cache)** — this IS P2's core deliverable; the concurrency test (two subtasks, one model, one download) belongs in P2's verification.

---

### Pitfall 9: There is no mid-generation cancellation in MNN — `USER_CANCEL` exists in the enum and is set nowhere

**What goes wrong:**
The design requires cancellation. Verified in the vendored MNN: `LlmStatus::USER_CANCEL` is *checked* (speculative-decoding paths) but **never assigned anywhere** — there is no public API to cancel a running generation. `TIMEOUT` is real (checked after prefill and per-step in generate loops via `mGenerateParam->timeout_ms`), but the plain `response()` path used by the current processor returns via max_new_tokens or EOS only. The existing processor already documents this honestly ("single blocking call with no cancellation hook") and only post-checks the token after generation completes — meaning a cancelled subtask still burns the full generation time (and billable hours) before reporting CANCELLED.

**Why it happens:**
Upstream MNN's cancellation strategy is "stop reading the stream" in interactive apps; server-style cancellation was never wired.

**How to avoid:**
- P3 uses the fork: set `mContext->status = LlmStatus::USER_CANCEL` from the `CancellationToken` callback (the context is reachable; the fork pattern already exists for TIMEOUT) — the per-step checks in generate loops then unwind. This is a small, contained fork patch consistent with the fork's existing local additions. Fallback if patching is rejected: rely on `timeout_ms` mapped from the execution deadline, and treat post-completion cancellation as the accepted v1.0 semantics (documented deviation like the current processor's).
- Thread hygiene: the generation runs on the per-subtask `std::thread` spawned by `ProcessingEngine::ProcessSubTask` (`processing_engine.cpp:100`); a cancelled-but-blocked thread must still be joined or detached *deliberately* — an unjoinable zombie generator pins the model cache entry (Pitfall 6 refcount) forever.

**Warning signs:**
Cancel-latency test showing CANCELLED returned only after `max_output_tokens` is exhausted; cache entries never reaching zero refcount after a cancelled job.

**Phase to address:**
**P3 (ELM Processor)** for the mechanism; **P4** proves cancel-vs-escrow interplay end to end.

---

### Pitfall 10: Escrow/deadline interplay — underfunded or overtime generation must end in a *structured* terminal state, not a re-grab loop

**What goes wrong:**
Three clocks interact: the subtask lock timeout (Pitfall 3), the escrow's `maximum_processing_hours`, and MNN's internal `timeout_ms`. If they disagree, the failure modes are ugly: lock expiry < generation length → duplicate execution (Pitfall 3); escrow exhaustion mid-generation with no check → node computes for free then can't publish; deadline fires but the blocked thread keeps generating (Pitfall 9) → next subtask starts late, cascading. The `ExecutionContext` already has the right shape (deadline → unified cancel path, D-09; `BUDGET_EXCEEDED` stage; `maxOutputArtifactBytes` check exists in the current LLM processor) — the pitfall is purely in *wiring* the funding-derived values in.

**Why it happens:**
Each mechanism was built in a different milestone; ELM is the first work type where all three are simultaneously tight.

**How to avoid:**
- One rule in P1: for `elm_processing`, lock timeout ≈ deadline ≈ escrow maximum (with a small fixed margin, e.g. deadline = escrow-max − margin, lock = escrow-max + margin) so generation can always finish-or-cancel *before* the lock expires. All three derive from `funding.maximum_processing_hours` in one place.
- Map terminal states explicitly: budget exhausted → `BUDGET_EXCEEDED` result (billable time up to that point, per Pitfall 4 settlement); deadline → `TIMED_OUT`; requestor cancel → `CANCELLED`; and ensure each is publishable as a result so the queue doesn't re-grab (a terminal-state result must satisfy the queue's completion path, `CompleteSubTask`, the same way success does).

**Warning signs:**
A BUDGET_EXCEEDED subtask being re-grabbed after publication; escrow settlement events for more wall-clock hours than `maximum_processing_hours`.

**Phase to address:**
**P1** (derivation rule), **P3** (terminal-state mapping), **P4** (E2E proof includes an overtime job that terminates cleanly).

---

### Pitfall 11: Token-count accounting must come from the executor's tokenizer, not the requestor's — and chat-template tokens are invisible to naive counting

**What goes wrong:**
The design requires accurate `prompt_tokens`/`completion_tokens`. MNN's `LlmContext` exposes `prompt_len`, `gen_seq_len`, `all_seq_len` and `history_tokens`/`output_tokens` — but `prompt_len` counts the **post-chat-template** token sequence, not the raw user input. If the requestor estimates cost with their own tokenizer (or an OpenAI-compatible client does), counts will differ; if billing uses one side and reporting the other, every reconciliation mismatches. Second-order: `completion_tokens` vs `max_output_tokens` — if generation stops via a stop *string* mid-token or hits EOS early, naive "tokens requested" accounting overbills.

**Why it happens:**
Token counts look like a simple counter; the chat template (and any system prompt the template injects) silently adds tokens that neither party "wrote."

**How to avoid:**
- P3 reports counts exclusively from the executor's `LlmContext` (`prompt_len`, `gen_seq_len` after generation — note `gen_seq_len` accounting on early-stop paths must be verified against `output_tokens.size()`), and the result artifact records the *tokenizer identity* (manifest hash covers it — a count is only meaningful relative to a tokenizer).
- P1/P4: billing is hour-based (Pitfall 4), so token counts are *reporting*, not billing — keep it that way for v1.0 and token-based billing becomes a future, explicit change. That removes the worst reconciliation pressure.

**Warning signs:**
A result whose `prompt_tokens` doesn't match what the requestor's local tokenizer computes for the raw input (expected — template tokens); asserting equality between requestor-side and executor-side counts in tests (wrong assertion).

**Phase to address:**
**P3 (counts from LlmContext)**, schema fields in **P1**.

---

### Pitfall 12: Results-channel payload size — inline text in gossip messages vs content-addressed results

**What goes wrong:**
Subtask results flow through `CompleteSubTask` → result storage/gossip (`processing_service.cpp` `OnQueueProcessingCompleted`, results channel per `Task.results_channel`). Existing tensor results are chunk-hashed with data on IPFS/bitswap; the current LLM processor stuffs the *entire* output text into `output_buffers` inline. A 512-token generation is fine; a future `max_output_tokens` of 8k–32k with the default settings is multi-hundred-KB of UTF-8 traveling through gossip pubsub — where libp2p gossip message size limits and per-message overhead make large payloads unreliable/slow (exact default limit unverified for this stack — flagged LOW confidence, but the direction is unambiguous).

**Why it happens:**
The single-shot processor was built for tests where the output is small.

**How to avoid:**
- P4 establishes the result convention: publish the text as a content-addressed artifact (existing chunk-hash + IPFS path machinery) and put only hashes + token counts + finish reason + `work_item_id` inline in the `SubTaskResult` — matching how every other processor's data already travels. Cap inline text at a small threshold (e.g. 4KB) with a graceful switch to artifact-only.

**Warning signs:**
E2E result publication succeeding at 256 tokens but timing out at 4k; gossip subscribe errors or dropped results under load.

**Phase to address:**
**P4 (Grid Integration & E2E)**, schema fields for hashes/counts in **P1**.

---

### Pitfall 13: Per-work-item isolation — KV cache and MNN session state must never leak between work items

**What goes wrong:**
MNN's `Llm` keeps conversation state: `history_tokens`, KV cache meta, and `reuse_kv()`. If an implementation "optimizes" by reusing one `Llm` instance across the `elms[]` work items of a job (or across subtasks), work item 2's generation is conditioned on work item 1's history — outputs are contaminated, and non-deterministically so (depends on execution order on the grid). The same hazard exists inside a single work item if `response()` is called twice (the current processor creates a fresh `Llm` per call — correct today).

**Why it happens:**
Model load is the expensive step (seconds to tens of seconds); session reuse across work items is the obvious optimization once P2's cache exists.

**How to avoid:**
- P3 policy: one fresh `Llm` session per work item, loaded from the pinned cache path (weights mapped/read from disk; MNN re-instantiation from a warm cache is much cheaper than a cold fetch). If session reuse is ever introduced, it must call `reset()`/`eraseHistory` and prove isolation with an order-permutation test (same two work items executed in both orders → identical outputs).
- Concurrent work items on one node: each holds its own `Llm` (memory = weights-shared-by-OS-page-cache + per-session KV). Check the manifest's `required_memory_bytes` against availability *before* grabbing (P2 exposes it; the capability gate consumes it) — two concurrent 0.5B sessions plus KV must fit or the second must wait, not OOM the node.

**Warning signs:**
Work item outputs that differ depending on sibling work items' presence; memory climb proportional to concurrent work items beyond KV expectations.

**Phase to address:**
**P3** (session lifecycle), **P2** (`required_memory_bytes` surfaced), **P4** (multi-work-item E2E with order permutation).

---

### Pitfall 14: Blocking the grid's event loop — mostly a *non*-issue, with two specific exceptions

**What goes wrong:**
The grid already runs each subtask on its own `std::thread` (`processing_engine.cpp:100`), and generation blocks only that thread — so "LLM inference blocks asio" is largely a false fear. The two real exceptions: (a) the `VulkanInitMutex` load window (Pitfall 5) which blocks *all* processors; (b) any new code in the ELM path that runs *on* the asio io_context — e.g. a cache-cleanup timer or download-completion handler that does sha256 of 300MB inline on the io thread. Bitswap download callbacks arrive on asio threads; verification must be posted to a worker, not run in the handler.

**Why it happens:**
The threading split (asio for queue/pubsub, worker threads for execution) is implicit; new cache code naturally writes handlers without checking which executor they run on.

**How to avoid:**
- P2 rule: hashing and filesystem-heavy work runs on worker threads; asio handlers only coordinate. A code-review checklist item: "no `sha256`, no `remove_all`, no model `load()` inside an asio post."

**Warning signs:**
Pubsub message latency spikes during model verification; channel-list request timeouts (`QUEUE_REQUEST_TIMEOUT`) correlating with cache activity.

**Phase to address:**
**P2 (cache workers)**, verified in **P4**.

---

### Pitfall 15: Known project hazards, re-verified for the ELM path

These were flagged in workstream memory; status after source verification:

1. **Async-timer UAF pattern (BitswapRequestContext, fixed d2ec18a):** the raw-`this` capture in `async_wait` is the project's recurring crash class. `ProcessingServiceImpl` correctly uses `weak_from_this` (`processing_service.cpp` Listen/SendChannelListRequest). **ELM exposure:** model-download timers/completion callbacks in P2 are exactly the shape where this regresses. *Prevention:* every new timer/callback captures `weak_from_this` (or equivalent); P2 review checks this line-by-line. *Phase: P2.*
2. **Test teardown hangs / dangling threads:** known pre-existing (`child_registration_test` teardown segfaults). ELM adds long-lived generation threads + cache pins; a test that tears down mid-generation must join or detach deliberately (Pitfall 9). Use the existing fail-fast pattern: CTest `TIMEOUT` properties (as sgproc-render Phase 18 did, ×4 margin over observed runtime). *Phase: P3/P4 test infra.*
3. **`SGPROC_TEST_DISCOVERY` gating:** SGProcessingManager test discovery is gated to standalone builds (commit on `dev_elmruntime`, "gate test discovery to standalone builds") so SuperGenius builds don't break. Every new ELM test target must respect the gate or it re-breaks the parent build. Verified in build tree (`SKIP_REGULAR_EXPRESSION`, gated targets). *Phase: all phases' test work.*
4. **Multi-level submodule nesting (root → SuperGenius → SGProcessingManager):** commit innermost first, then SuperGenius pointer, then root. ELM touches SGProcessingManager (processor/cache), SuperGenius (job model/funding), and possibly MNN (fork patches — Pitfalls 1/9) — making it a *four*-level chain if MNN is patched. *Phase: every phase's commit discipline.*
5. **Cross-hardware FP divergence:** re-verified as a *different regime* for text (Pitfall 2) — the float tolerance machinery does not transfer; the decision is schema-level validation mode, not quantScale tuning.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Post-hoc cancellation check only (current processor's approach) | No MNN fork changes | Cancelled jobs burn full generation time + billable hours; escrow overdraws | v1.0 E2E only if documented as a deviation; never once billing is real |
| No seed; restrict to `temperature=0` | No MNN fork changes; deterministic same-machine | Feature gap vs design (`seed` in generation settings) | v1.0 if schema reserves the field and greedy is the default; fix in v1.1 |
| Single global processing timeout raised for ELM jobs | One-line fix vs per-job timeout | Every non-ELM subtask now waits longer to be re-grabbed after real failures | Never — per-job timeout from `funding` is barely more work |
| Verify-on-every-cache-hit (no publish-time gate) | Correctness feels immediate | 300MB hash per subtask; livelock on poisoned entries | Only as an *addition* to publish-time gating, never the sole mechanism |
| Inline text in result messages | Trivial E2E | Size-limit failures at scale, no dedup of identical outputs | v1.0 E2E with small `max_output_tokens`; artifact path by default in P4 |
| Timestamp-named temp dirs (current materializer) | Already written | Disk exhaustion, collision under concurrency | Never — replaced by content-addressed cache in P2 |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| MNN `createLLM` | Passing a dir with only `model.mnn` (single-blob habit from 21 other processors) | Materialize the full bundle (`llm_config.json` + tokenizer + weights) from manifest artifacts; smoke-load before use |
| MNN `set_config` | Assuming unknown keys error | They're silently ignored — assert config took effect (e.g. re-read via `dump_config()`) in tests |
| `CancellationToken` → MNN | Expecting an API that doesn't exist | Fork-patch `USER_CANCEL` (pattern exists for TIMEOUT) or map deadline→`timeout_ms` |
| Bitswap/IPFS downloads | sha256 verification inside the asio handler | Verify on a worker thread; publish atomically (Pitfall 8/14) |
| SubTask queue lock | Assuming lock lifetime covers work | It's 15s by default and never overridden in production — derive per-job (Pitfall 3) |
| Escrow/`GetProcessCost` | Reusing byte-based cost | Hour-based branch from `funding` (Pitfall 4) |
| Gossip results channel | Inline payload of any size | Hashes + counts inline; text as artifact (Pitfall 12) |
| SuperGenius build (parent) | Adding SGProcessingManager test targets ungated | Respect `SGPROC_TEST_DISCOVERY` (Pitfall 15.3) |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Model load under `VulkanInitMutex` | All processors on node stall during load | Narrow lock scope; load-once-per-cache-entry | First concurrent ELM + any other job |
| Per-subtask re-load (no cache) | Each work item pays full load seconds | P2 cache + pinned load path | ≥2 work items or ≥2 subtasks per model |
| Duplicate concurrent downloads | Bandwidth ×N, billing ×N | Single-flight per manifest hash | First multi-work-item job on a cold node |
| Re-verify 300MB per hit | Seconds of hashing per subtask | Publish-time gate; size-check fast path | First cached run |
| KV/session reuse across work items | Order-dependent contamination | Fresh session per work item | Any multi-ELM job |
| Subtask lock expiry during generation | Duplicate execution, fund drain | Per-job timeout from funding hours | First generation >15s (i.e., every real one) |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Executing a model that skipped verification "just to test" | Unverified code-shaped data (MNN graphs are executable) on node GPUs | Fail closed — the design's "never execute an unverified model" must have no debug bypass; smoke-load happens only post-verify |
| Manifest fetched without hash-checking the manifest itself | Malicious manifest swaps artifact URIs | Manifest hash comes from the job (trusted via escrow/CRDT provenance); artifacts hash-checked against manifest; both recorded in result provenance |
| Cache directory on a shared/world-writable path | TOCTOU swap between verify and load | Per-node private cache dir; atomic rename publish; optional load-time re-verify for shared dirs |
| Prompt injection into result paths (`work_item_id` used in filenames) | Path traversal | Validate `work_item_id` charset; never interpolate into paths — cache keys are hex manifest hashes only |

## UX Pitfalls

(Operator/requestor-facing, since there's no end-user UI in this milestone.)

| Pitfall | User Impact | Better Approach |
|---------|-------------|------------------|
| Result has text but no provenance | Requestor can't tell which model/inputs produced it | `model_manifest_hash`/`input_hash`/`work_item_id` in every result (design already has these — keep them mandatory) |
| Silent defaulting of generation params | Outputs differ from requestor expectations | Echo *effective* settings in the result (esp. if seed/temperature were constrained by v1.0 limits) |
| Counts that don't match requestor-side tokenizers | Support burden, "wrong billing" complaints | Counts are executor-side by definition; document + include tokenizer identity via manifest hash |

## "Looks Done But Isn't" Checklist

- [ ] **Model cache:** Often missing quarantine of poisoned entries — verify a corrupt-artifact test exists and the entry is evicted, not just failed
- [ ] **Model cache:** Often missing the concurrent second-subtask case — verify one download, two loaders, no duplicate dirs
- [ ] **Manifest verification:** Often missing verification of the *manifest itself* vs its hash from the job — verify tampered-manifest test
- [ ] **Cancellation:** Often only post-completion check (looks cancelled, burns full time) — verify cancel latency ≪ full generation
- [ ] **Funding:** Often escrows maximum but settles full amount regardless of actual time — verify refund path with a short actual run
- [ ] **Lock timeout:** Often raised globally instead of per-job — verify non-ELM subtask re-grab timing unchanged
- [ ] **Token counts:** Often asserted against requestor-side tokenization — verify counts come from `LlmContext` and early-stop paths are covered
- [ ] **Temp/materialization:** Often leaves the old materializer in place alongside the cache — verify `%TEMP%` stays clean across a full E2E run
- [ ] **Submodule pointers:** Often only innermost committed — verify root/SuperGenius/SGProcessingManager (and MNN if patched) all have consistent pointers after each phase
- [ ] **Test gating:** Often adds ungated test targets — verify a standalone SGProcessingManager build AND a SuperGenius build both configure cleanly

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Sampler has no seed (discovered late in P3) | MEDIUM | Ship greedy-only for the milestone; schema field reserved; fork patch queued next milestone — schema was designed ahead so no wire break |
| Lock timeout duplicated execution in production-like E2E | LOW | Derive per-job timeout; add idempotent-result check (first published result for a subtaskid wins) as backstop |
| Cache poisoned entry livelock | LOW | Quarantine rename + re-download on next grab; add `.bad-*` sweep on startup |
| VulkanInitMutex stalls observed | MEDIUM | Short-term: load-once-per-entry reduces frequency; long-term: dedicated LLM load lock (requires MNN load-path concurrency proof) |
| USER_CANCEL fork patch rejected upstream | MEDIUM | Fallback to `timeout_ms` mapping; document cancellation-latency deviation |
| Inline result payload too large in E2E | LOW | Switch to artifact + hashes (P4's default anyway); cap inline threshold |
| Temp-dir leak discovered post-ship | LOW | Delete materializer when cache lands (P2/P3 order prevents this class entirely) |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1. No sampler seed | P3 | Same-seed same-machine byte-identical output ×2 runs; fork patch builds on all platforms |
| 2. Byte-hash validation vs text | P1 (schema mode), P4 (test doesn't enable redundant validation) | E2E completes with `validation: none`; schema round-trips the field |
| 3. 15s lock timeout | P1 (derive), P4 (E2E) | Long generation (>60s) not re-grabbed; no duplicate `[GRABBED]` for one subtaskid |
| 4. Byte-based cost | P1 | Escrow = f(maximum_processing_hours); refund of unused time proven |
| 5. Load under global mutex | P2 (load-once), P3 (scope) | Concurrent non-ELM subtask unaffected during LLM load |
| 6. Per-subtask materialization/leak | P2 (cache), P3 (retarget) | `%TEMP%` clean after full E2E; one dir per manifest hash |
| 7. Bundle-vs-blob, tokenizer mismatch | P2 | Loadability smoke check; wrong-tokenizer fixture fails closed with structured error |
| 8. Cache TOCTOU/duplicate downloads | P2 | Two concurrent subtasks → one download; corrupt artifact quarantined |
| 9. No mid-generation cancel | P3 (mechanism), P4 (proof) | Cancel latency ≪ full generation; refcount reaches zero post-cancel |
| 10. Three-clock interplay | P1 (rule), P3 (states), P4 (overtime job) | Overtime job ends in BUDGET_EXCEEDED, published, not re-grabbed |
| 11. Token counts | P1 (fields), P3 (source) | Counts from LlmContext incl. early-stop; no requestor-side equality assertions |
| 12. Result payload size | P1 (schema), P4 (convention) | Large generation publishes artifact + inline hashes only |
| 13. Session/KV isolation | P3 | Order-permutation test: same work items, both orders, identical outputs |
| 14. asio-thread work | P2 (workers), P4 (latency) | No pubsub latency spike during verification |
| 15. Known hazards (UAF pattern, teardown, gating, submodules) | All phases | weak_from_this in every new timer; CTest TIMEOUTs; gated targets; pointer-bump checklist per commit |

## Sources

- Workspace source (HIGH confidence, primary): `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_llm.cpp` (materializer, mutex scope, post-hoc cancel); `thirdparty/MNN/transformers/llm/engine/src/sampler.cpp:162` + `sampler.hpp:76` (unseeded RNG); `llm.hpp` / `llm.cpp` (USER_CANCEL never set — verified via exhaustive `status = LlmStatus::` search; TIMEOUT real; `set_config` ignores unknown keys); `SuperGenius/src/processing/processing_subtask_queue_manager.cpp:21` (15s default) + zero `SetProcessingTimeout` callers; `processing_engine.cpp:100` (per-subtask thread); `processing_tasksplit.cpp` (splitter shape); `GeniusNode.cpp:2265/2381` (byte-based escrow); `processing_service.cpp` (weak_from_this pattern, error/blacklist path)
- Project history (HIGH): `.planning/PROJECT.md` (v2.1–v2.3 cross-hardware divergence record, VulkanInitMutex migration, SGPROC gating), `workstreams/sgproc-render/STATE.md` (teardown/timeout test patterns, Phase 18 TIMEOUT pinning), `SuperGenius/.planning/notes/ELM-bridging-gaps.md` (design intent)
- LOW confidence / flagged inline: exact libp2p gossip max-message-size for this stack's defaults (Pitfall 12 — direction certain, number unverified)

---
*Pitfalls research for: ELM job execution on the SuperGenius processing grid (elmbridge v1.0)*
*Researched: 2026-09-09*
