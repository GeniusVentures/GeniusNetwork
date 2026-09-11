# Phase 3: ELM Processor - Context

**Gathered:** 2026-09-11
**Status:** Ready for planning

<domain>
## Phase Boundary

The ELM processor executes one causal-LM work item end-to-end from a pinned Phase 2 cache bundle and emits a complete, work-item-tagged result envelope. This phase delivers, entirely in SGProcessingManager (`src/processors/processing_processor_elm.*` behind an `SGPROC_HAS_MNN_LLM`-style gate) plus two user-approved MNN fork patches:

1. **Generation loop** (GEN-01) — chat-template application + prompt tokenization, prefill, autoregressive KV-cache decode, sampling honoring `max_output_tokens`/`temperature`/`top_p`/`seed`, stop tokens and stop strings, detokenization; accurate executor-side (`LlmContext`-sourced) prompt/completion token counts
2. **MNN fork patches** (GEN-01/GEN-02, approved as D-002 pre-roadmap) — sampler seed support and a public `Llm::cancel()` mid-generation cancellation trigger; add `thirdparty/MNN` to the submodule pointer chain
3. **Mid-generation cancellation** (GEN-02) — deadline/cancel-token fires → `Llm::cancel()` → prompt unwind, deliberate thread join/detach, cache pin reaches zero
4. **Result envelope** (RES-01) — `work_item_id`, generated text, prompt/completion token counts, `finish_reason` ∈ {stop, max_tokens, cancelled, error}, `model_manifest_hash` provenance
5. **Processor-node hygiene** (GEN-03) — `VulkanInitMutex` scope narrowed to actual GPU init with a dedicated LLM load lock; the temp-dir materializer is **deleted** as the processor retargets the Phase 2 cache path; `CheckElmResources` call-site wiring (Phase 2's deferred item); fresh `Llm` session per work item with the order-permutation test

**Out of scope (Phase 4):** ELM splitter, submit wiring, results-channel payload convention (inline vs artifact — Pitfall 12), gossip publication path, empty-cache E2E, non-ELM regression gate, anti-scope audit.

Requirements: GEN-01, GEN-02, GEN-03, RES-01.

</domain>

<decisions>
## Implementation Decisions

### Model-Load Locking (VulkanInitMutex fix)
- **D-01:** **Dedicated `LlmLoadMutex`** — `VulkanInitMutex()` guards only the `createLLM()` context-creation window; a NEW dedicated `LlmLoadMutex()` serializes `load()` against other LLM loads but not against the rest of the grid. No claim that concurrent weight loads are safe (conservative), but render/MNN processors never wait on an LLM load; two concurrent ELM work items still serialize their loads
- **D-02:** **Both test legs, gated TU** — the fix is proven by (a) SC-5's leg: a non-ELM MNN/render subtask started before an LLM load completes within its normal time, and (b) an LLM-vs-LLM leg: two ELM loads serialize on `LlmLoadMutex` without deadlock. Real MNN link, behind the `SGPROC_HAS_MNN_LLM`-style gate
- **D-03:** **`LlmLoadMutex` lives as an `sgns::sgprocessing` free function** next to the existing `VulkanInitMutex()` — same discovery pattern; any future LLM processor finds it identically. Not a file-static, not on the model cache
- **D-04:** **The old `MNN_Llm` processor migrates and its temp-dir materializer is deleted** — `processing_processor_mnn_llm.cpp` moves to the same (createLLM under VulkanInitMutex) + (load under LlmLoadMutex) discipline, and `MaterializeModelToTempDir` is removed now that the ELM cache path exists (Pitfall 6: "the processor's private materializer is deleted, not reused"). One lock discipline for all LLM loads; the temp-dir leak class is eliminated in this phase

### Stop-String Semantics
- **D-05:** **Streambuf + `USER_CANCEL` early stop** — a custom `streambuf` on the `ostream` passed to `response()` buffers decoded text, scans for stop strings as tokens arrive, and on match triggers `Llm::cancel()` → generation unwinds within a step. Prompt stop, `finish_reason=stop`, counts from `output_tokens.size()` at cancel time — no truncation-only semantics, no wasted billed tokens
- **D-06:** **Incremental overlap scan** — check whether any stop string begins at a position within the last (len(stop)-1 + slack) characters of accumulated text, handling stop strings split across token boundaries. O(text × stops) worst case, trivially cheap for typical stop lists. Not a full per-token rescan, not periodic checkpoints
- **D-07:** **OpenAI convention: the stop string is NOT included** — envelope text ends at the stop string start; `completion_tokens` = `output_tokens.size()` at cancel. No inclusion flag in v1.0

### Finish-Reason Mapping
- **D-08:** **TIMEOUT → `error`** — MNN's internal `timeout_ms` firing maps to `error` with an error detail field, per Phase 1 D-03's split: deadline firing cancels via the job's cancel token → `cancelled`; TIMEOUT means our bound fired unexpectedly → an execution fault. No fifth enum value
- **D-09:** **The processor decides intent, not the mechanism** — `USER_CANCEL` now serves both stop-string matches and job cancellation, but the envelope reports the processor's *reason* for triggering it: stop-string match → `stop` with truncated text; cancel-token/deadline → `cancelled`. `LlmStatus` is just the unwind mechanism; no fork substatus, no envelope side-field
- **D-10:** **Cancelled/error envelopes include partial text** — plus measured prompt/completion token counts (Phase 1 D-03: "publishes finish_reason: cancelled with measured counts"). The requestor sees exactly what the budget bought. No size threshold knob in v1.0
- **D-11:** **Internal errors surface via an error detail field** — `INTERNAL_ERROR` (and TIMEOUT per D-08) → `error` with code + message from the `ElmRuntimeError`/`ProcessingError` categories; the subtask still finalizes on this published result — terminal, not re-grabbed (Pitfall 10's terminal-state mapping). Not a thrown `ProcessingError` (re-grab-loop risk), not a bare enum

### MNN Fork Patch Shape
- **D-12:** **Seed as a config key + asserted application** — `Sampler` reads a `seed` key in its constructor/config (seeding `std::mt19937 mRng`); the processor passes it via `set_config({"seed": N})` and tests ASSERT it landed via `dump_config()` round-trip (SC-2's "a seed key never silently no-ops" mechanism). Config-key style matches how `temperature`/`top_p` already flow; no explicit setter API, no additional getter beyond `dump_config()`
- **D-13:** **`Llm::cancel()` method** — a public one-liner setting `mContext->status = USER_CANCEL` (STACK.md's suggested shape), callable from any thread; generation loops unwind at the next per-step poll. No reason parameter (D-09 keeps intent processor-side), no general context status setter. Thread-safety note goes in the patch comment
- **D-14:** **Gated + compile-time marker** — patches land in `thirdparty/MNN` on a `dev_elmruntime`-compatible branch; ELM processor usage is guarded behind the existing `SGPROC_HAS_MNN_LLM`-style gate plus a compile-time marker (e.g. `SGPROC_MNN_HAS_LLM_CANCEL`) so a stock MNN still builds — degraded path documented. Not a hard require, not runtime weak-link detection. Four-level commit chain: MNN → SGProcessingManager → SuperGenius → root (innermost-first)

### Carried Forward (locked by roadmap/research — not re-decided here)
- D-002 (pre-roadmap): the two MNN fork patches are user-approved; PITFALLS 1/9 estimated ~20 lines each; Phase 3 planning carries the implementation details
- D-003: zero new dependencies — everything exists in the vendored MNN fork and existing link set
- Phase 1 D-03: deadline firing mid-generation cancels immediately, publishes `cancelled` with measured counts, refunds unused escrow
- Phase 1 D-04/D-05: generation settings default-fill (temperature=1.0, top_p=1.0) and reject-at-parse bounds — the processor consumes validated settings, never clamps
- Phase 2's cache contract: the processor calls `ElmModelCache::Acquire` (hit → size-verify + pin; miss → single-flight fetch) and loads from the pinned path; pin releases on all terminal paths
- One fresh `Llm` session per work item (Pitfall 13; SC-5's order-permutation test); backend is a manifest/`llm_config.json` property (CPU default for Qwen-0.5B-class), not a processor property
- Token counts come exclusively from executor-side `LlmContext` (`prompt_len`, `gen_seq_len` reconciled against `output_tokens.size()` on early-stop paths — the roadmap note's verification flag); no requestor-side equality assertions
- Per-work-item settings flow via `set_config()` — never baked into the cached `llm_config.json` (cache is shared per model; STACK.md's "What NOT to Use")
- Worker-thread discipline: `response()`/`load()` run on the per-subtask `std::thread`; asio handlers only coordinate (Pitfall 14); every new timer/callback captures `weak_from_this` (Pitfall 15.1)
- `PushTeardown` for session cleanup (existing MNN_Llm pattern); a cancelled-but-blocked thread must be joined or detached *deliberately* (Pitfall 9)
- `CheckElmResources` call-site wiring lands here via `ExtractElmResourceRequirements` (Phase 2's deferred item — the validator half already shipped)
- New test targets respect `SGPROC_TEST_DISCOVERY` gating and CTest `TIMEOUT` properties (Pitfall 15.2/15.3)

### Claude's Discretion
- The exact compile-time marker name/mechanism for fork-patch detection (D-14) — prefer whatever CMake convention `SGPROC_HAS_MNN_LLM` already established
- The streambuf implementation details (buffer sizing, flush cadence, UTF-8 boundary handling in the scan window)
- The slack margin in D-06's overlap window and the precise scan-loop structure
- Whether the order-permutation test uses two real gated sessions or a mock-Llm seam (must still prove isolation per SC-5)
- Internal structure of the envelope builder (struct shape, serialization to `SubTask.json_data`-compatible output buffers)
- Unit-test structure/file layout under `test/` for the processor (follow the sgproc-render conformance-test pattern)
- Where `LlmLoadMutex()` is declared (alongside `VulkanInitMutex()`'s header — exact file per existing convention)
- The fork-branch name and patch-commit message conventions in `thirdparty/MNN`

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream research (verified against `dev_elmruntime` branches)
- `.planning/workstreams/elmbridge/research/PITFALLS.md` — Pitfall 1 (no sampler seed — fork-patch vs own-sampler decision), 5 (VulkanInitMutex scope + the concurrency test), 6 (temp-dir materializer deleted, cache owns session lifecycle), 9 (USER_CANCEL never set — fork mechanism + thread hygiene), 10 (terminal-state mapping), 11 (token counts from LlmContext, gen_seq_len early-stop flag), 13 (fresh session per work item, order-permutation test), 14 (worker-thread rule), 15.1/15.2/15.3 (weak_from_this, CTest TIMEOUTs, test gating); "Technical Debt Patterns" and "Integration Gotchas" tables (set_config silent-ignore, cancel-token mapping)
- `.planning/workstreams/elmbridge/research/STACK.md` — `MNN::Transformer::Llm` API surface table (session create/load, response/generate, set_config keys incl. `timeout_ms`, LlmContext count fields, streaming ostream hook, status/finish-reason values); "What NOT to Use" (set_config vs baked config; minimal fork patch vs call-site contortions); "Stack Patterns by Variant" (greedy config, topP config, stop-string streambuf options, layered cancel bounds, CPU backend default); "Known Gaps" (no public cancel setter, const getContext, blocking response())
- `.planning/workstreams/elmbridge/research/ARCHITECTURE.md` — Pattern 3 (self-fetching processor + content-addressed cache; Acquire data flow), Recommended Project Structure (`processors/processing_processor_elm.*` placement), Integration Points 7-8 (factory registration, `SGPROC_HAS_MNN_LLM` gating precedent in `src/processors/CMakeLists.txt:24-46`), Build Order (two-repo submodule constraint)
- `.planning/workstreams/elmbridge/research/SUMMARY.md` — Phase 3 scope framing

### Planning artifacts
- `.planning/workstreams/elmbridge/REQUIREMENTS.md` — GEN-01, GEN-02, GEN-03, RES-01 definitions; Out of Scope list (binding)
- `.planning/workstreams/elmbridge/ROADMAP.md` — Phase 3 success criteria (SC-1..SC-5) and note (gen_seq_len verification flag, fork-patch approval, innermost-first commit discipline)
- `.planning/workstreams/elmbridge/phases/01-elm-job-model-funding/01-CONTEXT.md` — Phase 1 decisions consumed here: D-03 (cancel-at-deadline semantics), D-04/D-05 (settings defaults and bounds), D-13 (validation enum)
- `.planning/workstreams/elmbridge/phases/02-manifest-model-cache/02-CONTEXT.md` — cache contract this phase consumes (D-01 size-first hit, D-03 cache root, pin RAII); integration points (Acquire path)
- `.planning/workstreams/elmbridge/phases/02-manifest-model-cache/02-VERIFICATION.md` — deferred items landing in Phase 3: `CheckElmResources` call-site wiring; pinned-entry/load-path facts verified true
- `.planning/workstreams/elmbridge/phases/01-elm-job-model-funding/01-01-SUMMARY.md` — quicktype generated-type realities (boost::optional getters) for reading `ElmGeneration` settings

### Code anchors (verified)
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_llm.cpp` — the precedent processor: `MaterializeModelToTempDir` (deleted this phase), VulkanInitMutex across createLLM+load at :86-108 (the lock pattern D-01/D-04 rewrite), `ResolveMaxNewTokens` parameter-resolution precedent, pre/post cancel-token checks, `PushTeardown` session cleanup
- `SuperGenius/SGProcessingManager/src/elmruntime/` — Phase 2's shipped layer: `ElmModelCache` (Acquire/pin/single-flight), `ElmManifest`, `ElmArtifactFetcher`, `ElmSmokeCheck` (gated-TU precedent), `ElmRuntimeError` (error category D-11 reuses)
- `SuperGenius/SGProcessingManager/src/elmruntime/include/elmruntime/ElmResourcePreflight.hpp` — `ExtractElmResourceRequirements` (the call-site wiring this phase adds)
- `SuperGenius/SGProcessingManager/src/capability/capability_validator.cpp` — `CheckElmResources` (validator half, shipped Phase 2)
- `thirdparty/MNN/transformers/llm/engine/src/sampler.cpp:162` + `sampler.hpp:76` — unseeded `mRng` the seed patch (D-12) touches
- `thirdparty/MNN/transformers/llm/engine/src/llm.cpp` — `set_config` (:101, merges JSON, silently ignores unknown keys — why D-12 asserts), timeout check (:975-979), `is_stop` → NORMAL_FINISHED (:1317-1326)
- `thirdparty/MNN/transformers/llm/engine/src/speculative_decoding/generate.cpp` — ArGeneration loop: sample → stop → stream-detokenize → forward; USER_CANCEL/TIMEOUT per-step polls (what D-13's cancel() unwinds)
- `SuperGenius/SGProcessingManager/src/processors/CMakeLists.txt:24-46` — `SGPROC_HAS_MNN_LLM` gating precedent D-14 extends
- `SuperGenius/SGProcessingManager/src/processing/processing_engine.cpp:100` — per-subtask `std::thread` (where response()/load() run)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`ElmModelCache`** (Phase 2) — Acquire/pin/single-flight/quarantine; the processor's only model source; pin RAII releases on all terminal paths (SC-3's "cache pin reaches zero")
- **`ElmSmokeCheck`** — the gated-TU precedent for wrapping real MNN LLM calls behind a compile gate (D-02's tests and D-14's marker follow it)
- **`ElmRuntimeError` category** — structured error codes for D-11's error detail field
- **`ExtractElmResourceRequirements` + `CheckElmResources`** — preflight halves awaiting this phase's call-site wiring
- **`PushTeardown` + `CancellationToken`** (ExecutionContext) — existing session-cleanup and cancel machinery (pre/post checks already in MNN_Llm)
- **Generated `Elm`/`ElmGeneration` types** (Phase 1) — validated per-work-item settings the processor consumes

### Established Patterns
- **Processor family conventions** — `MNN_Llm` + `RenderProcessor` precedents: factory registration, parameter resolution, teardown discipline, gated builds
- **Submodule-first landing** — everything ships inside SGProcessingManager on `dev_elmruntime`; the MNN fork patch extends the chain to four levels (innermost-first: MNN → SGProcessingManager → SuperGenius → root)
- **`set_config()` for per-work-item settings** — never baked into the cached `llm_config.json` (shared per model)
- **Blocking work on worker threads** — generation/load on the per-subtask thread; asio handlers coordinate only

### Integration Points
- **Processor factory table** (`ProcessingManager.cpp:429-481`) — ELM executor registration behind the gate
- **`GetCidForProc` ELM branch** — routes manifest resolution through `ElmModelCache::Acquire` instead of the single-buffer path
- **`VulkanInitMutex()` / new `LlmLoadMutex()`** — lock acquisition around createLLM/load for both ELM and migrated MNN_Llm processors
- **Envelope output path** — the processor's result buffers feed Phase 4's results convention (this phase defines envelope *content*, not the transport)

</code_context>

<specifics>
## Specific Ideas

- The stop-string mechanism deliberately reuses the USER_CANCEL unwind the fork adds for job cancellation — one mechanism, two intents, disambiguated by the processor (D-05 + D-09 form a pair; downstream agents must not add fork substatus)
- D-04 means this phase leaves the tree with exactly one LLM lock discipline and zero temp-dir materializers — `%TEMP%` cleanliness (Phase 2 SC-5) becomes structural, not behavioral
- SC-2's determinism proof (same seed × 2 runs → byte-identical) is the acceptance leg for D-12; the dump_config round-trip is the no-silent-no-op guard PITFALLS' "warning signs" section asks for

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 3-ELM Processor*
*Context gathered: 2026-09-11*
