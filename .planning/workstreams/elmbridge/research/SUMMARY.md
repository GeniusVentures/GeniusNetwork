# Project Research Summary

**Project:** ELM Bridge — Single-Node ELM Job Execution (elmbridge workstream, milestone v1.0)
**Domain:** Batch LLM-inference job execution riding an existing decentralized processing grid (SuperGenius tasks/subtasks/escrow + SGProcessingManager runtime)
**Researched:** 2026-09-09
**Confidence:** HIGH (all API and integration claims verified by direct inspection of the vendored MNN fork and the `dev_elmruntime` branches of both repos; ecosystem analogies are MEDIUM)

## Executive Summary

The ELM bridge is **not a new architecture** — it is a new *job shape* (`job_type: "elm_processing"` with `elms[]` work items inside the existing `Task.json_data`) flowing through the existing single-node pipeline: submit → escrow → split → subtask queue → SGProcessingManager execution → results channel → payout. Exactly three components are new: (1) an ELM splitter plus hours-based cost branch on the SuperGenius side, (2) a content-addressed model cache + manifest resolver (`src/elmruntime/`) inside SGProcessingManager, and (3) an ELM processor family wrapping the vendored MNN LLM engine. Everything else — worker dispatch, results channel publishing, escrow mechanics, CRDT/pubsub — is unchanged, verified down to specific line-level integration points on both `dev_elmruntime` branches.

The recommended approach is **zero new dependencies**: the MNN 3.4.1 static library this checkout already builds has the full causal-LM runtime compiled in (`Llm::createLLM`/`load`, bundled tokenizers, in-engine Jinja chat templates, KV-cache prefill/decode, samplers via `set_config`, token counts via `LlmContext`, wall-clock `timeout_ms`). The work is integration code plus discipline: fail-closed sha256 verification behind a publish-time cache gate, per-job lock timeouts derived from funding, deterministic hours-based escrow, and a fresh `Llm` session per work item. A four-phase structure (Job Model & Funding → Manifest & Model Cache → ELM Processor → Grid Integration & E2E) follows the hard dependency chain and matches the submodule-first build order — SGProcessingManager must ship before SuperGenius consumes it.

Key risks: (1) the **15-second default subtask lock timeout** will cause duplicate execution and fund drain on any real ELM subtask — it must be derived per-job from `funding.maximum_processing_hours` in the first phase, not patched later; (2) **MNN's sampler has no seed API and no mid-generation cancel** — an explicit fork-patch-vs-degrade decision (greedy-only / timeout-bounded v1) is required before processor code is written; the fork is GNUS-owned with patch precedent; (3) the existing **cross-subtask byte-hash validation regime is wrong for generated text** (cross-hardware FP divergence is proven on this codebase) — v1.0 must scope validation to `none`/single-node in the schema rather than silently inheriting the tensor regime. All three have concrete, low-cost preventions if designed in early.

## Key Findings

### Recommended Stack

**Zero new dependencies.** Every capability the milestone needs — LLM session, tokenizer, chat template, KV cache, sampling, detokenization, token counts, sha256 verification — already exists in the vendored MNN fork (`MNN_Ultra_v2` @ `01b6f314`, MNN 3.4.1, LLM engine compiled into the static `MNN::MNN` already linked by SGProcessingManager) and the existing link set. Details in [STACK.md](STACK.md).

**Core technologies:**
- **MNN `MNN::Transformer::Llm` API** — the entire causal-LM runtime (create/load, tokenize, prefill, autoregressive decode with KV cache, `set_config()` sampling params, `LlmContext` token counts, `timeout_ms` bound) — mandated engine, already linked, already proven in-tree by `processing_processor_mnn_llm.cpp`
- **`sgns::sgprocmanagersha` (OpenSSL EVP)** — manifest + artifact sha256; optionally extended with a ~30-line incremental helper for hash-while-download
- **AsyncIOManager `FileManager`** — every artifact fetch (`ipfs://`/`https://`/`file://`), billable, cache-coordinated; never MNN's own HTTP downloader
- **`std::filesystem` + `cache/<model-manifest-hash>/`** — the cache directory doubles as `LlmConfig.base_dir`, so one directory serves as both cache key and loadable MNN bundle
- **nlohmann_json + quicktype regeneration** — ELM job schema in `Task.json_data`; zero hand-edits to `generated/` (SCHEMA-01..05 norm)

**Critical version/API limits (plan around):** no sampling seed (sampler RNG seeded from `std::random_device`), no public cancel setter (`LlmStatus::USER_CANCEL` checked but unsettable), stop *strings* not native (token-based only), `response()` blocks, `set_config()` silently ignores unknown keys.

### Expected Features

Full landscape in [FEATURES.md](FEATURES.md).

**Must have (table stakes):**
- Job model JSON — `job_type`/`version`, `elms[]` with unique `work_item_id` (validated at parse time), per-work-item generation settings, funding block — riding `Task.json_data` with **no protobuf changes**
- One work item → one SubTask via a new ELM splitter, with the `work_item_id ↔ subtaskid` mapping embedded in task JSON for GCS aggregation
- Manifest resolution — immutable URI+hash pointer, per-artifact sha256, **fail-closed on every path** (fresh download, cache reuse, partial recovery)
- Content-addressed cache — dedup, verify-before-reuse, pin-while-processing, LRU eviction of unpinned, atomic partial-download recovery
- Generation contract — `temperature` (greedy @ 0.0)/`top_p`/`seed`/`max_output_tokens`, stop tokens AND stop strings, chat template as manifest artifact, accurate executor-side token counts, mid-generation cancellation
- Result envelope — `work_item_id`+`subtask_id` echo, text, `finish_reason ∈ {stop, max_tokens, cancelled}`, counts, `model_manifest_hash`; flat, one JSON per work item, **no SuperGenius-side aggregation**
- Funding — deterministic from job JSON at $0.0003/hour; model download is billable job work

**Binding anti-features (owner-corrected scope — must NOT reappear in the roadmap):** no streaming proto (ELM-09), no capability/cache advertising (ELM-03), no bidding/negotiation (ELM-02), no requester-side worker selection, no worker-side `/v1` endpoints, no node-side aggregation (ELM-07), no proto changes (ELM-01), no cross-node bit-identical output promises, no logits-processor suite beyond the contract four, no continuous batching, no token-based billing. AsyncIOManager#11 (`ipfspubsub://`) is explicitly out of scope.

**Defer (v1.x/v2+):** corrupted-artifact counter-test hardening, cache observability, extra sampling knobs, multi-node fan-out, cross-node validation, streaming events, throughput work.

### Architecture Approach

The feature rides the existing two-JSON split: `Task.json_data` carries the whole job (worker re-creates the `ProcessingManager` from it) while `SubTask.json_data` carries a `ModelNode` selecting the unit of work (`source: "input:<work_item_id>"`) — so worker dispatch (`processing_core_impl.cpp`) needs **zero changes**; JSON shape does the routing. Chunks degrade to one notional chunk per subtask so `ValidateIndividualResult` and `chunk_hashes` bookkeeping work unmodified. Full component map and 13 integration points in [ARCHITECTURE.md](ARCHITECTURE.md).

**Major components:**
1. **ELM job router + splitter + cost branch** (SuperGenius: `GeniusNode::ProcessImage` branch, new `processing_tasksplit_elm.*`) — `job_type` sniff at exactly two call sites; existing chunk path byte-for-byte unchanged
2. **`src/elmruntime/`** (SGProcessingManager, new) — manifest load/verify, content-addressed cache (pin/dedup/evict/quarantine), per-artifact fetch via `FileManager`
3. **ELM processor family** (SGProcessingManager: `processing_processor_elm.*`, gated like `SGPROC_HAS_MNN_LLM`) — generation loop, sampling, stops, counts, cancellation; follows the `MNN_Llm` + `RenderProcessor` precedents
4. **Unchanged**: results channel, `ProcessingEngine` worker threads, escrow hold/payout mechanics (only the amount computation changes)

**Structural constraint:** SGProcessingManager is a submodule of SuperGenius — submodule work must land and be pointer-bumped before SuperGenius-side code compiles against it; if the MNN fork is patched, `thirdparty/MNN` adds another pointer to the commit chain (innermost-first discipline every phase).

### Critical Pitfalls

Top 5 of 15 — full catalog with warning signs and recovery strategies in [PITFALLS.md](PITFALLS.md):

1. **15s subtask lock timeout kills every real ELM subtask** (download + generation takes minutes; expired locks → duplicate grabs → repeated downloads → fund drain) — derive lock timeout per-job from `funding.maximum_processing_hours` via `SetProcessingTimeout()` at enqueue; add a >60s-not-re-grabbed test
2. **No sampler seed, no mid-generation cancel in MNN** — decide in P3 planning: minimal GNUS-fork patch (~20 lines each, precedent exists) vs. greedy-only + `timeout_ms`-bounded v1 with schema fields reserved; never let a `seed` key silently no-op through `set_config()`
3. **Byte-hash validation regime breaks for text in both directions** (false invalidation on legitimate divergence; stricter-than-float byte identity) — schema-level `validation: none | exact | redundant` with `none` the v1.0 default; E2E must NOT enable redundant validation
4. **`GetProcessCost` is byte-based; hours-based funding is new accounting, not a parameter change** — escrow the declared maximum up front, settle by measured wall-clock (grab → publication, download included), refund the remainder; record the USD→GNUS rate at escrow time
5. **Model lifecycle traps: `VulkanInitMutex` held across full model load stalls all node processors; MNN LLM needs a bundle *directory* (tokenizer mismatch = silent garbage, not an error); per-subtask materialization leaks temp dirs** — cache owns the session lifecycle: atomic publish (stage → verify → rename), loadability smoke check (createLLM + load + 1-token greedy) before marking usable, single-flight per manifest hash, quarantine poisoned entries, delete the private materializer

## Implications for Roadmap

Both ARCHITECTURE's build order and PITFALLS' phase mapping independently converge on four phases ordered by hard dependency (schema → cache → processor → proof).

### Phase 1: ELM Job Model & Funding
**Rationale:** The schema is the contract every later phase consumes, and the three-clock rule (lock ≈ deadline ≈ escrow-max, all derived from `funding.maximum_processing_hours` in one place) plus the validation-mode field must exist before any execution code. Cheapest phase, highest leverage — four critical pitfalls are prevented here for the price of JSON fields and one cost branch.
**Delivers:** Quicktype-regenerated ELM schema (`job_type`, `elms[]`, unique `work_item_id`, generation settings incl. seed + stop tokens/strings, funding block, `validation` mode field, result-envelope fields incl. token counts + provenance hash); `GeniusNode::ProcessImage` `job_type` branch + `GetElmProcessCost` (hours × $0.0003 → minions at PRECISION=6, no CoinGecko); per-job subtask lock timeout derivation; the `work_item_id ↔ subtaskid` mapping design; escrow-settlement semantics (escrow max, refund unused).
**Addresses:** FEATURES sections A (job model), F (funding), envelope schema fields from E.
**Avoids:** Pitfalls 2 (validation mode), 3 (lock timeout), 4 (byte-based cost), 10 (three-clock rule), 12 (schema fields), 11 (count fields).
**Note:** Schema lands in SGProcessingManager first (quicktype regen); the SuperGenius cost/submit branch needs the submodule pointer bump.

### Phase 2: Manifest & Model Cache (SGProcessingManager `src/elmruntime/`)
**Rationale:** The runtime cannot load a model without a verified bundle; the cache is load-bearing for both performance (300–500MB models, load-once) and security (fail-closed invariant), and it is fully unit-testable without any SuperGenius dependency — ideal submodule-first work.
**Delivers:** Manifest load + hash verify + artifact enumeration mapping onto MNN's expected on-disk bundle layout; per-artifact fetch through `FileManager` with sha256; `cache/<manifest-hash>/` with atomic publish (staging dir → verify → rename), single-flight dedup for concurrent subtasks, pin-refcount, size-first fast path, poison quarantine (`.bad-<hash>`), eviction of unpinned entries, partial-download recovery; loadability smoke check (post-verify `createLLM`+`load`+1-token greedy); `required_memory_bytes` preflight fed to the existing `CapabilityValidator`.
**Uses:** `sgprocmanagersha` (+ optional incremental EVP), `std::filesystem`, AsyncIOManager `FileManager`.
**Avoids:** Pitfalls 5 (load-once-per-entry), 6 (temp-dir leak / materializer deletion), 7 (bundle-vs-blob, wrong-tokenizer detection), 8 (TOCTOU / duplicate downloads), 14 (hashing on worker threads, never asio handlers), 15.1 (`weak_from_this` in every new timer/callback).
**Verification:** corrupt artifact → refusal + quarantine; tampered manifest → rejection; two concurrent subtasks → one download; `%TEMP%` stays clean.

### Phase 3: ELM Processor
**Rationale:** Depends on cache + schema; the largest new-code surface; the seed/cancel decision determines the loop's internal structure and cannot be deferred past this phase's planning.
**Delivers:** `processing_processor_elm.*` behind an `SGPROC_HAS_MNN_LLM`-style gate; generation loop (tokenize → chat template → prefill → decode+KV → sample → stop → detokenize → counts); `set_config()` for per-work-item settings (assert via `dump_config()` — unknown keys are silently ignored); stop-string handling via custom `ostream`/`streambuf` observation or post-truncation; fresh `Llm` session per work item (order-permutation isolation test); cancellation via fork-patch `USER_CANCEL` or `timeout_ms` fallback; token counts exclusively from `LlmContext`; work-item result envelope writer; `VulkanInitMutex` scope fix (dedicated LLM load lock or narrowed window).
**Addresses:** FEATURES section D (generation-settings contract), E (result envelope).
**Avoids:** Pitfalls 1 (seed decision), 9 (cancel mechanism + thread hygiene), 11 (counts source), 13 (session/KV isolation), 5 (lock scope).
**Research flag:** needs deeper research during planning — see below.

### Phase 4: Grid Integration & E2E Proof
**Rationale:** Consumes everything; the milestone's acceptance criterion *is* the empty-cache single-node E2E, so it must be the final phase.
**Delivers:** `processing_tasksplit_elm.*` (one work item → one SubTask, notional single chunk, mapping into task JSON); `ProcessImage` ELM submit branch fully wired (escrow hold → enqueue); escrow settlement by measured wall-clock with refund; results convention (hashes + counts + finish_reason inline; text as content-addressed artifact via `FileManager::SaveASync`, small inline cap); **the E2E proof**: single node, empty cache, downloads a Qwen-0.5B-class MNN causal LM mid-job, completes all `elms[]`, results publish, escrow pays out; regression proof that existing chunk-based jobs behave byte-identically; overtime job → `BUDGET_EXCEEDED` published, not re-grabbed; anti-feature guardrail audit (nothing reads cache state in assignment).
**Addresses:** E2E proof (MVP launch checklist), all "Add After Validation" triggers armed.
**Avoids (verification legs):** Pitfalls 2, 3, 9, 10, 12 end-to-end; 15.2/15.3/15.4 (CTest TIMEOUT properties, `SGPROC_TEST_DISCOVERY` gating, full pointer chain: SGProcessingManager → SuperGenius → root, plus `thirdparty/MNN` if patched).

### Phase Ordering Rationale

- **Hard dependency chain:** runtime requires verified manifest+cache before any generation; the result envelope depends on the splitter mapping, not runtime internals; E2E requires all of the above — the order cannot be shuffled
- **Submodule constraint:** Phases 2–3 ship entirely inside SGProcessingManager (no SuperGenius dependency); Phase 1's schema part likewise; SuperGenius-consuming work (Phase 1 branch, Phase 4) follows pointer bumps — this mirrors ARCHITECTURE's six-step build order collapsed into four roadmap phases
- **Pitfall convergence:** PITFALLS' P1–P4 attribution matches this structure exactly; every critical pitfall has its prevention phase assigned and its verification leg in P4

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 3 (ELM Processor):** the fork-vs-degrade decision (MNN seed patch + `USER_CANCEL` patch vs. greedy-only/timeout-bounded v1) has cross-platform build impact on the `thirdparty/MNN` fork and changes the processor's loop structure — recommend `--research-phase` or an explicit owner decision before planning
- **Phase 1 (targeted verification only):** (a) escrow wall-clock accounting semantics — does existing accounting measure from subtask grab (thus including fetch)? Do not assume; (b) how the subtask queue finalizes ELM subtasks without chunk-hash validation (`ProcessingValidationCore` bypass design) — flagged in FEATURES as needing explicit phase-level design

Phases with standard patterns (skip research-phase):
- **Phase 2:** atomic-rename publishing, single-flight, refcounted pins are well-documented patterns; the design is already drafted in `ELM-bridging-gaps.md`
- **Phase 4:** splitter precedent (`processing_tasksplit.cpp`), E2E harness + ctest conformance patterns, and teardown/timeout discipline all come from sgproc-render history

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Every API claim verified against the vendored MNN source tree and build files; version pinned (`MNN_Ultra_v2` @ `01b6f314`) |
| Features | HIGH | Scope grounded in REQUIREMENTS.md ELM-01..ELM-08 + ELM-bridging-gaps.md; generation semantics verified against HF GenerationConfig docs; ecosystem analogies (OpenAI Batch/vLLM/Ollama) MEDIUM |
| Architecture | HIGH | All 13 integration points verified by direct source inspection of both `dev_elmruntime` branches |
| Pitfalls | HIGH | Nearly all pitfalls source-verified (incl. exhaustive `USER_CANCEL` search, zero `SetProcessingTimeout` callers); one LOW item flagged inline (gossip max message size) |

**Overall confidence:** HIGH

### Gaps to Address

- **Sampler seed & cancellation (Phase 3):** no public MNN API for either — resolve fork-patch vs. greedy-only-v1 during Phase 3 planning; schema already reserves the fields so no wire break either way
- **Escrow wall-clock semantics (Phase 1):** verify accounting measures from subtask grab (download included); if compute-only, fetch must be explicitly included — verify, don't assume
- **Validation finalization (Phases 1/4):** how the queue completes ELM subtasks without the chunk-hash cross-subtask comparison — needs explicit design, not silent inheritance
- **`gen_seq_len` early-stop accounting (Phase 3):** verify against `output_tokens.size()` on stop-string/EOS paths before trusting reported counts
- **`VulkanInitMutex` necessity for `load()` (Phase 3):** whether weight-loading truly needs the global lock requires a concurrency test; if yes, bound damage via load-once-per-cache-entry
- **Gossip message size limit (Phase 4):** exact libp2p gossip max for this stack unverified (LOW confidence) — direction is unambiguous, and the mitigation (text-as-artifact + inline hashes) is the default convention anyway; verify the number during Phase 4 planning

## Sources

### Primary (HIGH confidence)
- Vendored workspace source — `thirdparty/MNN/transformers/llm/engine/**` (llm.hpp/llm.cpp, sampler.cpp, tokenizer.cpp, llmconfig.hpp, generate.cpp), `thirdparty/build/CommonTargets.cmake:453-482`
- `SuperGenius/src/` — `account/GeniusNode.cpp` (ProcessImage:2257, GetProcessCost:2388, HoldEscrow:2320), `processing/processing_tasksplit.cpp:44`, `processing/impl/processing_core_impl.cpp:67`, `processing_engine.cpp:84-137`, `processing_subtask_queue_accessor_impl.cpp`, `processing_subtask_queue_manager.cpp:21` (15s default), `account/TokenAmount.cpp:65`
- `SGProcessingManager/src/` — `processingbase/ProcessingManager.cpp` (Create:419, GetCidForProc:1802, GetSubCidForProc:2057, output save:1637-1755), `processors/processing_processor_mnn_llm.cpp`, `util/sha256.cpp`, `processors/CMakeLists.txt` (SGPROC_HAS_MNN_LLM gate)
- Scope/design docs — `SuperGenius/.planning/REQUIREMENTS.md` (ELM-01..ELM-09), `SuperGenius/.planning/notes/ELM-bridging-gaps.md`, `.planning/PROJECT.md` elmbridge section, sgproc-render milestone history

### Secondary (MEDIUM-HIGH confidence)
- HuggingFace Transformers `GenerationConfig` official docs — temperature/top_p/max_new_tokens/stop_strings semantics (fetched 2026-09-09, HIGH)

### Tertiary (MEDIUM confidence)
- Ecosystem analogies from training data — OpenAI Batch API (`custom_id`, usage, finish_reason), vLLM `SamplingParams`, Ollama sha256 blob store — consistent with verified HF semantics; used for feature-shape validation only, not for implementation claims

---
*Research completed: 2026-09-09*
*Ready for roadmap: yes*
