# Phase 3: ELM Processor - Research

**Researched:** 2026-09-11
**Domain:** MNN causal-LM generation loop + SGProcessingManager processor integration + two MNN fork patches (sampler seed, `Llm::cancel()`)
**Confidence:** HIGH (every code claim re-verified against the live `dev_elmruntime` tree this session: sampler.cpp/hpp, llm.cpp/hpp, generate.cpp, llmconfig.hpp, ElmSmokeCheck.cpp/hpp, ElmModelCache.cpp/hpp, ElmResourcePreflight.hpp, capability_validator.cpp, processing_processor_mnn_llm.cpp/hpp, processing_processor.hpp, execution_context.hpp, ProcessingManager.cpp/hpp, processing_core_impl.cpp, processing_engine.cpp, CMakeLists files, CommonTargets.cmake; git branch state of MNN/SGProcessingManager/SuperGenius/root confirmed live)

## Summary

Phase 3 builds one new processor (`processing_processor_elm.*`), migrates the old `MNN_Llm` processor to the new lock discipline, and lands two user-approved patches in the vendored MNN fork (`thirdparty/MNN`, branch `MNN_Ultra_v2` @ `01b6f314`, a submodule of `thirdparty` — making the commit chain FOUR levels: MNN → thirdparty → SGProcessingManager → SuperGenius → root, correcting the context's "MNN → SGProcessingManager → SuperGenius → root" to include the `thirdparty` hop). The entire generation loop already exists inside MNN's linked static library: `Llm::response(prompt, ostream*, end_with, max_new_tokens)` performs chat-template application → tokenization → prefill → KV-cache decode → sampling → detokenization, streaming each decoded token to the caller's `std::ostream` with a flush per token — the streambuf hook for stop-string detection is public API. The two fork patches are exactly as scoped: (a) `sampler.cpp:162` seeds `mRng(std::random_device{}())` with no config key — the patch adds a `seed` read in the `Sampler` constructor; (b) `LlmStatus::USER_CANCEL` is checked at the top of every `ArGeneration::generate` loop iteration (`generate.cpp:46`) but no public API ever sets it — the patch adds a one-line `Llm::cancel()`.

The critical engineering risk is **wiring, not invention**: the processor must run on the per-subtask `std::thread` (`processing_engine.cpp:100`), consume Phase 2's `ElmModelCache::Acquire` (pin RAII releases on all terminal paths), take `(VulkanInitMutex around createLLM) + (new LlmLoadMutex around load)` (D-01/D-03), reconcile `gen_seq_len` against `output_tokens.size()` on early-stop paths (verified: `updateContext(0,1)` fires per sampled token BUT the stop-token sample still increments `output_tokens` before the loop breaks — the stop token itself is counted; `gen_seq_len` and `output_tokens.size()` diverge by design on EOS paths), and map `LlmContext::status` onto the four-value `finish_reason` per D-08..D-11. Token counts come exclusively from `LlmContext` (`prompt_len` set from `input_ids.size()` at `llm.cpp:890` — post-chat-template tokens, matching Pitfall 11's warning).

**Primary recommendation:** Build the processor as a thin, testable orchestration shell (acquire → preflight → create session under locks → set_config → streambuf-wrapped response → envelope build) with every MNN touch behind `SGPROC_HAS_MNN_LLM` in dedicated TUs following the `ElmSmokeCheck.cpp` include-isolation pattern; land the two MNN patches FIRST (innermost-first commit discipline) so the processor compiles against patched MNN from its first commit.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
Copied verbatim from `03-CONTEXT.md` — D-01 through D-14 plus the Carried Forward block. The planner MUST honor all of these; see `03-CONTEXT.md` for the full text. Summary index:

- **D-01:** Dedicated `LlmLoadMutex`; `VulkanInitMutex()` guards only the `createLLM()` context-creation window; two concurrent ELM loads serialize; render/MNN never wait on an LLM load
- **D-02:** Both concurrency test legs, gated TU, real MNN link behind the gate
- **D-03:** `LlmLoadMutex` is an `sgns::sgprocessing` free function next to `VulkanInitMutex()` — not file-static, not on the model cache
- **D-04:** Old `MNN_Llm` processor migrates to the same lock discipline; `MaterializeModelToTempDir` deleted now that the cache path exists; one lock discipline, zero temp-dir materializers
- **D-05:** Streambuf + `USER_CANCEL` early stop for stop strings; counts from `output_tokens.size()` at cancel time; no truncation-only semantics
- **D-06:** Incremental overlap scan (last len(stop)-1 + slack chars); handles stop strings split across token boundaries; O(text × stops)
- **D-07:** OpenAI convention: stop string NOT included; `completion_tokens` = `output_tokens.size()` at cancel; no inclusion flag in v1.0
- **D-08:** TIMEOUT → `error` (with error detail field); deadline-firing → `cancelled`; no fifth enum value
- **D-09:** Processor decides intent: stop-string match → `stop` with truncated text; cancel-token/deadline → `cancelled`; no fork substatus
- **D-10:** Cancelled/error envelopes include partial text + measured counts; no size threshold knob
- **D-11:** INTERNAL_ERROR/TIMEOUT → `error` with code + message from `ElmRuntimeError`/`ProcessingError` categories; terminal published result, not thrown, not re-grabbed
- **D-12:** Seed as config key + asserted application via `dump_config()` round-trip; config-key style like temperature/top_p; no setter API
- **D-13:** `Llm::cancel()` public one-liner setting `mContext->status = USER_CANCEL`; callable from any thread; no reason parameter; thread-safety note in the patch comment
- **D-14:** Gated + compile-time marker (`SGPROC_HAS_MNN_LLM`-style + e.g. `SGPROC_MNN_HAS_LLM_CANCEL`); stock MNN still builds; four-level commit chain innermost-first

### Claude's Discretion
- Exact compile-time marker name/mechanism for fork-patch detection (D-14)
- Streambuf implementation details (buffer sizing, flush cadence, UTF-8 boundary handling in the scan window)
- Slack margin in D-06's overlap window and the precise scan-loop structure
- Whether the order-permutation test uses two real gated sessions or a mock-Llm seam (must still prove isolation per SC-5)
- Internal structure of the envelope builder (struct shape, serialization to `SubTask.json_data`-compatible output)
- Unit-test structure/file layout under `test/` (follow the sgproc-render conformance-test pattern)
- Where `LlmLoadMutex()` is declared (alongside `VulkanInitMutex()`'s header)
- Fork-branch name and patch-commit message conventions in `thirdparty/MNN`

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope. Phase 4 owns: splitter, submit wiring, results transport convention (inline vs artifact), gossip publication, empty-cache E2E, non-ELM regression gate.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| GEN-01 | End-to-end causal-LM execution: chat template, tokenization, prefill, KV-cache decode, sampling honoring `temperature`/`top_p`/`seed` (same-node determinism), stop tokens/strings, detokenization, accurate counts | `Llm::response()` covers the whole loop natively (verified API table below); seed needs the D-12 fork patch (sampler.cpp:162 confirmed unseeded); stop strings need the D-05 streambuf (MNN has token-stop only via `is_stop`, llm.cpp:1317-1326); counts from `LlmContext::prompt_len`/`output_tokens` |
| GEN-02 | Mid-generation cancellation via MNN fork patch (`USER_CANCEL`) | `USER_CANCEL` checked per-step (generate.cpp:46) but never settable — D-13's `Llm::cancel()` one-liner closes the gap; CancellationToken callback (`execution_context.hpp:96-117`) is the existing trigger mechanism |
| GEN-03 | Processor conventions: `VulkanInitMutex` narrowed to GPU init, temp-dir materialization replaced by cache, no per-execution leaks | Current mutex held across createLLM+load (mnn_llm.cpp:86-108) — D-01/D-03/D-04 split; `MaterializeModelToTempDir` (mnn_llm.cpp:35-77) deleted; `ElmCachePin` RAII (ElmModelCache.hpp:41-88) owns the no-leak pin lifecycle |
| RES-01 | Result envelope: `work_item_id`, text, prompt/completion counts, `finish_reason` ∈ {stop, max_tokens, cancelled, error}, `model_manifest_hash` | Envelope builder detail below; `ElmCachePin::GetHash()` supplies the provenance hash; finish-reason mapping table (D-08..D-11) maps `LlmStatus` + processor intent onto the four values |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Generation loop (prefill/decode/sample/detokenize) | MNN fork (vendored engine) | — | The loop exists and is linked; the processor orchestrates it, never reimplements it (STACK.md "What NOT to Use") |
| Sampler seeding | MNN fork patch (sampler.cpp) | Processor (passes seed via `set_config`) | D-12: config-key style; the RNG lives inside `Sampler::mRng` — only the fork can reach it |
| Mid-generation cancel trigger | MNN fork patch (`Llm::cancel()`) | Processor (CancellationToken callback → `cancel()`) | Status field is `protected mContext`; only a member can set it |
| Stop-string detection | Processor (streambuf on the response ostream) | MNN (provides the per-token flush hook) | D-05: public-API hook, no fork needed |
| Cache acquire/pin | Phase 2 `ElmModelCache` (shipped) | Processor (caller) | Pin RAII releases on all terminal paths — processor just holds it |
| Resource preflight | Processor call site | `CapabilityValidator::CheckElmResources` + `ExtractElmResourceRequirements` (shipped halves) | Phase 2's deferred wiring item — compose the two shipped halves |
| Lock discipline | `vulkan_init_guard.hpp` (+ new `LlmLoadMutex` there) | Both LLM processors | D-03: free function, same discovery pattern |
| Envelope construction | Processor (new builder) | `SubTask.json_data` (transport is Phase 4) | RES-01 content only this phase |
| Thread discipline | Existing per-subtask `std::thread` (processing_engine.cpp:100) | Processor (must never block asio) | Pitfall 14: asio handlers only coordinate |
| Factory registration | `ProcessingManager::Init` | ELM processor class | Existing `RegisterProcessorFactory`/`RegisterPassProcessorFactory` pattern |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `MNN::Transformer::Llm` | vendored fork, `MNN_Ultra_v2` @ `01b6f314` (3.4.1) | The entire generation loop | Mandated; LLM engine compiled into the static `MNN::MNN` already linked by `SGProcessors` (`CommonTargets.cmake:453-471`, `MNN_BUILD_LLM=ON`) [VERIFIED: live tree] |
| `sgns::elmruntime` (Phase 2 layer) | shipped @ `dev_elmruntime` `c9ccff8` | `ElmModelCache::Acquire`, `ElmCachePin`, `ElmRuntimeError`, `MakeMnnLlmSmokeCheck` | The processor's only model source; pin RAII is the leak-proof handle [VERIFIED: live tree] |
| `sgns::sgprocmanagersha` | existing | Output-text sha256 (chunkhashes entry) | Same as every processor [VERIFIED: live tree] |
| nlohmann_json | already linked (SGProcessors PUBLIC) | Envelope serialization, `set_config` payload | Zero new deps [VERIFIED: live tree] |
| GTest (vendored) | existing | Unit/gated tests | `mnn_llm_test` / `sgprocelmruntime_*_test` precedents [VERIFIED: live tree] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `std::streambuf`/`std::ostream` | C++17 stdlib | D-05 stop-string observer | Wrapping the `ostream*` handed to `response()` — per-token flush makes the sync scan trivial |
| boost::optional accessors (quicktype generated) | existing | Reading `Elm`/`ElmGeneration` settings | Materialize by-value optionals into named locals — the Phase 1 UB lesson |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Fork-patch sampler seed | Own sampler over raw logits | Higher effort, fork divergence risk both ways; D-12 already locked config-key style [DECIDED] |
| Fork-patch `cancel()` | `timeout_ms` mapping only | Degrades cancel latency to the timeout bound; D-13 approved; keep `timeout_ms` as a belt-and-braces bound anyway |
| `response()` + streambuf | `generate(input_ids)` + own detokenize loop | `generate()` returns only token IDs — loses the streaming hook D-05 needs; `response()` is the higher-level, already-proven path |

**Installation:** Nothing to install. The only "new" code is the two MNN fork patches inside `thirdparty/MNN` (D-003: zero new dependencies holds).

## Package Legitimacy Audit

Not applicable — this phase installs no external packages. All code lands in the vendored MNN fork (2 patches), SGProcessingManager (processor + tests), and existing headers.

## Architecture Patterns

### System Architecture Diagram

```mermaid
flowchart TD
    subgraph WorkerThread["Per-SubTask std::thread (processing_engine.cpp:100)"]
        A[ProcessSubTask → ProcessingManager::Process<br/>→ StartProcessing on ELM processor] --> B{cancelToken<br/>IsCancelled?}
        B -- yes --> Z1[EnvelopE finish_reason=cancelled<br/>pin RAII releases]
        B -- no --> C[ElmModelCache::Acquire uri+hash<br/>hit: size-verify+pin / miss: single-flight fetch]
        C -- ElmRuntimeError --> Z2[Envelope finish_reason=error<br/>code+message, pin never taken]
        C -- pin --> D[ExtractElmResourceRequirements →<br/>CheckElmResources mem+disk]
        D -- unmet --> Z2
        D -- ok --> E[createLLM pin.GetDir<br/>under VulkanInitMutex]
        E --> F[set_config seed/temp/top_p/max_new_tokens/<br/>timeout_ms + dump_config assert]
        F --> G[load under LlmLoadMutex]
        G -- fail --> Z2
        G --> H{cancelToken<br/>IsCancelled?}
        H -- yes --> Z1
        H -- no --> I[PushTeardown destroy llm +<br/>cancel-callback registration]
        I --> J["response(prompt, &stopStreambuf,<br/>nullptr, max_output_tokens)"]
        J --> K{Per-token in streambuf}
        K -- stop-string match --> L["llm->cancel() → USER_CANCEL"]
        K -- token streams --> J
        L --> M[response returns]
        J -- EOS/max_tokens/timeout --> M
        N["CancellationToken.Cancel()<br/>(deadline timer or job cancel)"] -.->|callback: llm->cancel| J
        M --> O["Reconcile: LlmContext status,<br/>prompt_len, output_tokens.size,<br/>gen_seq_len cross-check"]
        O --> P[Envelope: work_item_id, text,<br/>counts, finish_reason, manifest hash]
        P --> Q[ProcessingResult: output_buffers +<br/>chunkhashes sha256; RunTeardown]
    end
    Q --> R[SubTaskResult → CompleteSubTask<br/>(Phase 4 wires transport)]
```

Trace: work item in → envelope out, with every early exit (Z1/Z2) still releasing the pin via RAII and running teardown.

### Recommended Project Structure
```
SGProcessingManager/
├── include/processors/
│   ├── processing_processor_elm.hpp        # NEW — forward-declares Llm (mnn_llm.hpp pattern)
│   └── vulkan_init_guard.hpp               # MODIFIED — add LlmLoadMutex() beside VulkanInitMutex()
├── src/processors/
│   ├── processing_processor_elm.cpp        # NEW — gated TU(s); MNN surface isolated
│   ├── processing_processor_mnn_llm.cpp    # MODIFIED — D-04 migration; MaterializeModelToTempDir deleted
│   └── CMakeLists.txt                      # MODIFIED — ELM sources behind SGPROC_HAS_MNN_LLM; cancel marker
├── src/processingbase/
│   └── ProcessingManager.cpp               # MODIFIED — ELM executor factory registration behind gate
├── test/processors/
│   └── elm_processor_test.cpp (+CMakeLists)# NEW — gated; determinism/cancel/order/lock legs
thirdparty/MNN/transformers/llm/engine/
├── src/sampler.cpp + src/sampler.hpp       # PATCH — seed config key (D-12)
├── src/llm.cpp + include/llm/llm.hpp       # PATCH — Llm::cancel() (D-13)
```

### Pattern 1: Gated TU with include isolation (ElmSmokeCheck pattern)
**What:** All MNN-touching code lives in TUs whose headers contain zero MNN includes; the whole MNN surface sits inside `#if defined(SGPROC_HAS_MNN_LLM)`.
**When to use:** Every new file that names `MNN::Transformer::Llm`.
**Example:**
```cpp
// processing_processor_elm.hpp — forward-declare only (processing_processor_mnn_llm.hpp:16-29 pattern)
namespace MNN { namespace Transformer { class Llm; } }
// processing_processor_elm.cpp
#if defined( SGPROC_HAS_MNN_LLM )
#include <llm/llm.hpp>
// ... real implementation
#endif
```
[VERIFIED: `ElmSmokeCheck.cpp:8-27`, `processing_processor_mnn_llm.hpp:16-29`]

### Pattern 2: Lock-split load sequence (D-01/D-03/D-04)
**What:** `createLLM` under `VulkanInitMutex()`; `load()` under the new `LlmLoadMutex()`.
**When to use:** Both ELM processor and migrated MNN_Llm.
```cpp
MNN::Transformer::Llm *llm = nullptr;
{
    std::lock_guard<std::mutex> gpuInit( sgns::sgprocessing::VulkanInitMutex() );
    llm = MNN::Transformer::Llm::createLLM( dir );
    if ( !llm ) return /* error */;
}
{
    std::lock_guard<std::mutex> llmLoad( sgns::sgprocessing::LlmLoadMutex() );
    if ( !llm->load() ) { MNN::Transformer::Llm::destroy( llm ); return /* error */; }
}
```
[VERIFIED: current combined lock at `processing_processor_mnn_llm.cpp:86-93`; `vulkan_init_guard.hpp:18` free-function precedent]

### Pattern 3: Cancel wiring via CancellationToken callback
**What:** The token's callback (fired by `Cancel()`, `execution_context.hpp:96-117`) triggers `llm->cancel()`; the processor keeps an atomic `cancelIntent` flag to disambiguate D-09 intent.
```cpp
execCtx.cancelToken.SetCallback( [llm, &stopStringMatched]() {
    stopStringMatched.store( false );   // this callback = job/deadline cancel, not stop-string
    llm->cancel();
} );
```
**Caution:** `ProcessInternal` ALREADY calls `SetCallback` for the deadline timer (`ProcessingManager.cpp:1594-1599`) — the processor must chain or replace it deliberately, or the deadline-timer cancel gets clobbered. Verify the interaction at implementation time (see Open Questions Q1).

### Pattern 4: Stop-string streambuf (D-05/D-06/D-07)
**What:** Custom `streambuf` whose `sync()`/`xsputn()` appends to an accumulated string, then scans the incremental overlap window.
```cpp
class StopStringStreamBuf : public std::streambuf {
    // accumulate into text_; per flush: for each stop s, search text_ from
    // max(0, text_.size() - s.size() + 1 - kSlack) — if found at pos p:
    //   matched_ = p; llm->cancel(); (processor-side stop intent flag set)
};
```
MNN flushes the ostream after every token (`generate.cpp:60-63`), so the scan sees each token's decoded text incrementally. On match: envelope text = `text_.substr(0, p)` (D-07 exclusion), `completion_tokens` = `output_tokens.size()` at cancel (D-05).

### Anti-Patterns to Avoid
- **Baking per-work-item settings into the cached `llm_config.json`** — the cache is shared per model; settings flow via `set_config()` only (STACK.md "What NOT to Use"; carried-forward decision)
- **Hand-rolled sampling loop** — port MNN's native API (the mnn_llm.cpp comment already made this call)
- **Reusing one `Llm` session across work items** — Pitfall 13; SC-5's order-permutation test exists to prove this never happens
- **Throwing `ProcessingError` for internal errors** — D-11: published terminal result, not a re-grab-loop-inducing throw
- **Dereferencing quicktype getter results in-place** — `*data.get_elms()` UB (Phase 1 lesson, restated in `CheckElmValidity`'s comment)

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|------|
| Generation loop | Custom prefill/decode loop | `Llm::response()` | KV cache, sampling, stopping criteria, detokenization all internal and battle-tested |
| Tokenization/chat template | Own tokenizer/template engine | MNN bundled tokenizer + jinja (unconditionally compiled, `LLM_USE_JINJA`) | 5 tokenizer types in-tree; no external sentencepiece/tiktoken needed |
| Model fetch/verify/cache | Any processor-side fetching | `ElmModelCache::Acquire` | Phase 2 shipped it all: single-flight, pin, quarantine, smoke check |
| Resource preflight | New checks | `ExtractElmResourceRequirements` → `CheckElmResources` | Both halves shipped in Phase 2; wiring only |
| Output hashing | New hash | `sgprocmanagersha::sha256` | Same as every processor |
| Seed RNG in processor | Own distribution machinery | Fork-patch config key → `std::mt19937` seed | Sampler's `stepSelect` already consumes `mRng` (`sampler.cpp:530-531`); seeding the member is the minimal change |

**Key insight:** every deceptively complex piece (KV cache, sampling pipeline, cache lifecycle, cancel plumbing) already exists in a shipped layer; Phase 3 is integration discipline.

## Runtime State Inventory

> Not a rename/refactor/migration phase in the store-migration sense — but D-04's deletion has state fallout the planner must schedule:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — the cache layer is content-addressed and unaffected | None |
| Live service config | None | None |
| OS-registered state | **Old temp dirs** `sgproc_mnn_llm_<timestamp>/` already leaked in `%TEMP%` from prior runs (Pitfall 6: never cleaned) | None required (out of scope to sweep user temp); the deletion stops NEW leaks — Phase 2 SC-5's `%TEMP%` cleanliness becomes structural |
| Secrets/env vars | None | None |
| Build artifacts | **`mnn_llm_test.cpp` exercises `MaterializeModelToTempDir` behavior indirectly** (empty-buffer/pre-cancel legs only — verified: no test materializes a real model); MNN fork rebuild required after patches (ExternalProject `BUILD_BYPRODUCTS` handles it) | Test audit at deletion time: the two existing cases (empty model → RESOURCE_RESOLUTION; pre-cancel → CANCELLED) survive the migration unchanged — both short-circuit before LoadModel. Add no new MNN_Llm tests; its coverage is the migrated lock path |

**The canonical question:** after every file is updated, what still carries the old behavior? Answer: (a) MNN static lib must be rebuilt for the two patches to link — CMake byproduct tracking triggers this automatically; (b) the SuperGenius parent build consumes SGProcessingManager via `add_subdirectory` — the ungated-test-target hazard (Pitfall 15.3) is the one regression class to check on every new target.

## Common Pitfalls

### Pitfall 1: `gen_seq_len` vs `output_tokens.size()` divergence on early-stop paths
**What goes wrong:** The roadmap note flags this explicitly. Verified mechanics: `ArGeneration::generate` pushes the sampled token into `output_tokens` and calls `updateContext(0,1)` (incrementing `gen_seq_len`) BEFORE `is_stop()` breaks the loop (`generate.cpp:55-66`) — so both counts INCLUDE the stop token. But when `USER_CANCEL` fires, the loop breaks at the TOP of the next iteration: the last sampled token is in both counters; conversely a cancel arriving mid-forward leaves the counters consistent. The REAL divergence: `Llm::generate(input_ids, ...)` sets `prompt_len = input_ids.size()` AFTER the generation call returns (`llm.cpp:890`), and `MAX_TOKENS_FINISHED` is set when `len >= max_token` where `len` counts decode steps, not pushed tokens. On speculative paths (lookahead/mtp/eagle — not used for Qwen-0.5B-class) the relationship is looser still.
**How to avoid:** Report `completion_tokens = output_tokens.size()` (the concrete produced tokens) as the envelope's authority; treat `gen_seq_len` as a cross-check that MUST be reconciled (log a warning on mismatch; assert equality in the determinism test where the path is deterministic). Never average or pick max.
**Warning signs:** envelope counts differing between a stop-token run and a max-token run by one.

### Pitfall 2: `set_config` silently ignores unknown keys — the seed no-op trap
**What goes wrong:** `set_config` merges JSON into `LlmConfig::config_` (`llm.cpp:101-125`) and returns true unconditionally; a `seed` key that the fork patch doesn't read looks identical to one that landed. PITFALLS.md flags this as THE warning sign for D-12.
**How to avoid:** The processor asserts application post-`set_config` via `dump_config()` containing the expected `seed` value (SC-2's mechanism); the determinism test (same seed ×2 → byte-identical) is the behavioral backstop.
**Warning signs:** determinism test flaking; `dump_config()` missing the key.

### Pitfall 3: Sampler construction timing — seed must flow through `LlmConfig`, not a post-load setter
**What goes wrong:** The `Sampler` is constructed inside `Llm::load()` (`llm.cpp:306`: `mSampler.reset(Sampler::createSampler(mContext, mConfig))`), and its constructor seeds `mRng(std::random_device{}())` (`sampler.cpp:162`). A seed applied via `set_config` AFTER `load()` never reaches the already-constructed sampler's RNG (only a re-read in the constructor would).
**How to avoid:** The fork patch reads the `seed` key in the `Sampler` constructor from the passed `LlmConfig` — therefore the processor MUST call `set_config(seed...)` BEFORE `load()`. The `ElmSmokeCheck.cpp:68-71` sequence (set_config before load, comment says exactly this) is the precedent. This ordering is a hard requirement, not a style choice.
**Warning signs:** determinism test failing while `dump_config()` shows the seed present.

### Pitfall 4: `SetCallback` collision with ProcessInternal's deadline-timer wiring
**What goes wrong:** `ProcessingManager::ProcessInternal` registers `execCtx.cancelToken.SetCallback([&deadlineTimer](){...})` (ProcessingManager.cpp:1594-1599). If the ELM processor registers its own callback (to call `llm->cancel()`), one clobbers the other — the token holds ONE callback (`std::function`, last-set-wins).
**How to avoid:** Options for the planner: (a) the processor's callback ALSO cancels nothing timer-related (deadline already fired by then — the timer callback is for the OTHER direction: explicit cancel → cancel timer); analyze the exact semantics: token callback fires when Cancel() is called; ProcessInternal's lambda cancels the deadline timer; the processor's needs to call `llm->cancel()`. The combined callback must do both. Cleanest: the processor captures/extends — but the deadlineTimer is a stack local inside ProcessInternal, unreachable from the processor. Realistic resolution: the processor's callback wraps/chains is impossible with last-set-wins — so either (i) ProcessInternal is adjusted to chain (ELM branch or generic fix — capture the previous callback), or (ii) the deadline timer remains the only cancel path for deadlines and the processor polls `IsCancelled()` at loop granularity via the streambuf scan (each token flush checks the flag — cancel latency ≈ one token, which is ≪ full generation and satisfies SC-3's "promptly"). Option (ii) requires no ProcessManager change: the streambuf's per-token check of an atomic cancel flag IS the poll.
**Warning signs:** cancel-latency test showing generation running to max_tokens despite Cancel() at t=0.

### Pitfall 5: `end_with` default emits `"\n"` into the output stream
**What goes wrong:** `response()` defaults `end_with` to `"\n"` (`llm.cpp:988`) and writes `end_with` to the ostream when a STOP TOKEN ends generation (`generate.cpp:63-65`: `*mContext->os << mContext->end_with << std::flush`). The envelope text would carry a spurious newline not produced by the model.
**How to avoid:** Pass an explicit short `end_with` (e.g. `""` — empty is allowed; nullptr means default "\n") and/or strip nothing — verify empty-string behavior at implementation; the streambuf can simply ignore `end_with`-sourced writes if distinguishable, but simplest is `end_with=""`.
**Warning signs:** byte-identity failures in the determinism test; trailing-newline diffs between runs.

### Pitfall 6: Chat-template tokens inflate `prompt_len` vs requestor expectations
**What goes wrong:** `response(const std::string&)` applies the chat template when `use_template()` is true, then `prompt_len` counts post-template tokens (`llm.cpp:1005-1011`) — Pitfall 11's verified warning. Also `std::cout << "prompt: "` debug line at `llm.cpp:1008` prints every prompt to stdout (noise, not correctness — but note it).
**How to avoid:** Executor-side counts are the contract; no requestor-side equality assertions anywhere (D-carried). Document in the envelope that counts are tokenizer-relative to the manifest hash.

### Pitfall 7: MNN rebuild propagation after fork patches
**What goes wrong:** Patching `thirdparty/MNN` sources without rebuilding leaves the OLD static lib linked — the processor compiles against new headers but links old behavior (seed no-ops, `cancel()` unresolved symbol or silently absent).
**How to avoid:** MNN is an ExternalProject (`CommonTargets.cmake:457-476`) with `BUILD_BYPRODUCTS` on the static lib — touching `sampler.cpp`/`llm.cpp` in the source dir triggers rebuild on the next thirdparty build. The plan must include an explicit rebuild+verify step (run a determinism smoke) before wiring SGProcessingManager against it. Note the MNN build directory is `thirdparty/build/<Platform>/.../MNN/` — innermost-first commit discipline starts at the MNN submodule itself.

### Pitfall 8: Ungated test targets re-break the SuperGenius parent build
**What goes wrong:** Pitfall 15.3 — `gtest_discover_tests` executes binaries at build time; cross-compiled/unavailable hosts hang.
**How to avoid:** Follow `test/elmruntime/CMakeLists.txt` verbatim: `if(SGPROC_TEST_DISCOVERY AND NOT CMAKE_CROSSCOMPILING)` gating, whole-binary `add_test`, `set_tests_properties(... PROPERTIES TIMEOUT N)` (120 for fast, 300 for MNN-touching legs — generation tests want the generous bound).

### Pitfall 9: The old MNN_Llm processor's two-buffers contract still feeds it a model buffer
**What goes wrong:** `MNN_Llm::StartProcessing` receives `modelFile` bytes fetched by `GetCidForProc`; after D-04 deletes the materializer, the migrated processor still needs A source for `createLLM` — but its job shape (non-ELM, DataType::LLM passes) has no manifest/cache. Deleting the materializer without a replacement load path breaks the processor entirely.
**How to avoid:** D-04's precise scope: migrate to the (createLLM under VulkanInitMutex) + (load under LlmLoadMutex) discipline. The materializer deletion is justified by "now that the ELM cache path exists" — i.e., the ELM path replaces the USE CASE, and the old MNN_Llm processor was a single-buffer test-shaped processor (PITFALLS: "built for tests"). Two viable shapes for the planner (discretion): (a) MNN_Llm's LoadModel takes a directory-creating minimal path (temp materializer replaced by a trivial write, contradicting D-04's "zero temp-dir materializers" end-state), or (b) the MNN_Llm processor itself becomes a thin deprecated shim that fails closed or routes through the cache. Re-read D-04: "moves to the same lock discipline... and MaterializeModelToTempDir is removed now that the ELM cache path exists... the temp-dir leak class is eliminated in this phase". The honest reading: the leak-class elimination means MNN_Llm must stop materializing — planner should decide whether MNN_Llm (a) writes to a managed per-session dir cleaned in teardown, or (b) is reduced to fail-closed (its DataType::LLM shape has no production caller today; ELM jobs don't route through it). Flag for the plan-checker: this is the one D-04 ambiguity (see Open Questions Q2).

### Pitfall 10: `CHECK_LLM_RUNNING` macro returns early on stale error status
**What goes wrong:** `response()` begins with `CHECK_LLM_RUNNING(mContext)` — if `mContext->status` is NOT_LOADED/INTERNAL_ERROR/TIMEOUT/USER_CANCEL, the call RETURNS without generating and without error signaling (void return). A session whose status wasn't reset (e.g. a reused session) silently produces empty output.
**How to avoid:** Fresh `Llm` per work item (Pitfall 13 policy) makes this unreachable in practice — `generate_init` resets status to RUNNING on a fresh call when not NOT_LOADED (`llm.cpp:766-768`). The processor must still check post-generation status (never assume response() ran) and map an early-return-with-empty-output to `error`, not `stop`-with-empty-text.

## Code Examples

### Fork patch D-12: sampler seed (exact insertion points)
```cpp
// thirdparty/MNN/transformers/llm/engine/src/sampler.cpp — constructor (currently :161-168)
Sampler::Sampler(std::shared_ptr<LlmContext> context, std::shared_ptr<LlmConfig> config)
    : mContext(context), mRng(std::random_device{}()) {   // ← line 162: the unseeded ctor
    mConfig.max_all_tokens = config->max_all_tokens();
    ...
// PATCH: seed from config when present, e.g.
//   if (config->config_.contains("seed")) {
//       mRng.seed(static_cast<std::mt19937::result_type>(
//           config->config_["seed"].get<int64_t>() & 0xFFFFFFFFull));
//   }
// (mRng is std::mt19937 — sampler.hpp:76; seed fits uint32; int64 from ElmGeneration)
```
Config read must be from the merged `config_` (which `set_config` merges into, `llm.cpp:101`) — not a new `LlmConfig` accessor (though adding one mirrors `timeout_ms()` style; either is ~5 lines). [VERIFIED: sampler.cpp:160-168, llmconfig.hpp pattern]

### Fork patch D-13: Llm::cancel()
```cpp
// thirdparty/MNN/transformers/llm/engine/include/llm/llm.hpp — public section (~line 152)
/// Request mid-generation cancellation from any thread. Sets the context
/// status to USER_CANCEL; running generation loops unwind at their next
/// per-step poll (ArGeneration::generate loop head). Thread-safety: the
/// status field is a plain enum written here and read per-step by the
/// generation thread — benign race by design (same pattern as TIMEOUT).
void cancel() { mContext->status = LlmStatus::USER_CANCEL; }
```
The loop checks at `generate.cpp:46` (`if(mContext->status == LlmStatus::USER_CANCEL || ... INTERNAL_ERROR) break;`) — unwinding is one step. [VERIFIED: generate.cpp:44-48, llm.hpp mContext protected member]

### Processor generation call shape
```cpp
// After acquire + preflight + createLLM + set_config + load (Patterns above)
StopStringStreamBuf stopBuf( stopStrings, /*slack=*/8 );
std::ostream         os( &stopBuf );
llm->response( promptText, &os, "", maxOutputTokens );  // end_with="" (Pitfall 5)
const auto *ctx = llm->getContext();
// ctx->prompt_len, ctx->output_tokens.size(), ctx->status, ctx->gen_seq_len
```

### Finish-reason mapping (D-08/D-09/D-10/D-11 — the complete table)
| Trigger | LlmContext::status | Processor intent flag | finish_reason | Text | completion_tokens |
|---|---|---|---|---|---|
| Stop token (EOS) | NORMAL_FINISHED | — | `stop` | full text | output_tokens.size() (includes stop token) |
| Stop string match | USER_CANCEL (set by processor) | stop-string | `stop` | truncated at match start (D-07) | output_tokens.size() at cancel |
| max_output_tokens exhausted | MAX_TOKENS_FINISHED | — | `max_tokens` | full text | == max_output_tokens |
| Job cancel / deadline (token fired) | USER_CANCEL | cancel | `cancelled` | partial text (D-10) | output_tokens.size() |
| MNN internal timeout_ms | TIMEOUT | — | `error` (D-08) + detail | partial text (D-10) | output_tokens.size() |
| load/generation internal failure | INTERNAL_ERROR or early-return-empty | — | `error` + code/message | none/partial | measured |
| Cache/preflight failure (pre-generation) | — (no session) | — | `error` + ElmRuntimeError code | none | 0 |

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| MNN_Llm post-hoc cancel check only | Fork `Llm::cancel()` + per-token streambuf poll | This phase (D-13) | Cancel latency ≪ full generation (SC-3) |
| VulkanInitMutex across createLLM+load | Split locks (D-01/D-03) | This phase | Non-LLM processors never wait on weight loads (SC-5) |
| Temp-dir materialization | Content-addressed cache (Phase 2) | Phase 2 shipped; D-04 deletes the old path now | `%TEMP%` cleanliness structural |

**Deprecated/outdated:** none in the live tree beyond what D-04 removes.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | MNN fork patches land on `MNN_Ultra_v2` (or a branch off it) in the GNUS-owned `../MNN.git` remote — branch is pushable | Commit discipline | If the fork remote rejects new branches, patch commits need a different home; planner should confirm push rights or commit on the checked-out branch |
| A2 | `end_with=""` suppresses the stop-token newline emission (empty string written instead of `"\n"`) | Pitfall 5 | If MNN treats empty as "use default", pass a single space or strip in the streambuf — one-line fix either way |
| A3 | The ELM processor registers via `RegisterPassProcessorFactory`-style or a DataType-keyed factory — exact key (new PassType? DataType::LLM reuse? a string key) is unspecified in the context; ELM jobs have NO passes[] (schema-optional) so the existing `SetProcessorByName(GetInputIndex...)` routing cannot reach it unchanged | Processor integration | Routing ELM subtasks to the processor likely needs a ProcessInternal ELM branch (like GetCidForProc's) — planner must design this leg; this is the largest unplanned-surface finding (see Q3) |
| A4 | `sgns::ElmGeneration.seed` (int64) → JSON number → `set_config` round-trip preserves full value | Fork patch | int64 > 2^53 loses precision in some JSON paths; nlohmann handles int64 natively; MNN's `ujson` is nlohmann-derived [ASSUMED — verify at implementation] |
| A5 | Determinism scope is same-node/same-build (locked upstream); `std::mt19937` + `uniform_real_distribution<float>` are deterministic given identical seed AND identical libstdc++/MSVC runtime — the determinism test runs on one build only | Test strategy | None for this phase; cross-node bit-identity is an explicit anti-feature |

## Open Questions

1. **CancellationToken callback collision (Pitfall 4)**
   - What we know: ProcessInternal sets the token callback to cancel the deadline timer; the token holds one callback; the processor needs `llm->cancel()` on cancel.
   - What's unclear: chain vs. streambuf-poll (`IsCancelled()` per token flush — latency ≈ 1 token, satisfies SC-3, zero ProcessManager changes).
   - Recommendation: streambuf-poll as primary (no ProcessManager modification, no callback ownership fight); `Llm::cancel()` invoked from the poll when the flag is observed. Planner picks; both honor D-09.
2. **D-04's exact MNN_Llm end-state (Pitfall 9)**
   - What we know: lock migration + materializer deletion are locked; the old processor's model-buffer input has no cache path.
   - What's unclear: fail-closed shim vs. teardown-cleaned session dir.
   - Recommendation: fail-closed for non-test use is cleanest (zero materializers, literally), but the two existing mnn_llm_test cases must still pass — they short-circuit before LoadModel, so both options keep them green. Planner decides within D-04's "zero temp-dir materializers" end-state.
3. **ELM subtask → processor routing key (A3)**
   - What we know: ELM jobs carry no `passes[]`; `ProcessInternal` resolves processors via input-type lookup; `GetCidForProc` has an ELM-parity comment anticipating an ELM branch.
   - What's unclear: whether Phase 3 wires the full routing (processor factory + ProcessInternal branch + GetCidForProc bypass) or only the processor + registration behind the gate, with routing completed in Phase 4's splitter/submit wiring.
   - Recommendation: Phase 3 ships the processor + factory registration + a Process()-level ELM entry path testable standalone (conformance-test style, not full-grid); full grid routing is Phase 4 by roadmap. The phase boundary says "ships in SGProcessingManager... processor factory registration point" — registration yes, grid routing no.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| MNN (vendored, patched) | Generation | ✓ | 3.4.1 fork @ `01b6f314`, `MNN_Ultra_v2` | — |
| Vulkan SDK/loader | MNN Vulkan backend + lock targets | ✓ | thirdparty-built | CPU backend default for Qwen-0.5B-class anyway |
| GTest | Tests | ✓ | thirdparty-built | — |
| Standalone SGProcessingManager build | Test execution | ✓ | `dev_elmruntime` @ `c9ccff8` | — |
| Real Qwen-0.5B-class model fixture | Determinism/cancel-latency legs | ✗ (none in repo) | — | Gated tests that need a real model: mark `GTEST_SKIP` with cross-reference (the cancellation_test.cpp precedent) OR fetch in-test — Phase 4's E2E owns the download path; Phase 3's real-model legs may need a small local fixture fetched manually. Flagged: this is the main test-asset gap (see Wave 0) |

**Missing dependencies with fallback:** the real-model fixture — determinism (SC-2), cancel-latency (SC-3), and order-permutation (SC-5) legs all NEED a real model. Options: (a) tests download via `file://` from a locally staged bundle (test-injectable FetchFn precedent), (b) GTEST_SKIP without the fixture, (c) mock-Llm seam for order-permutation only (context-sanctioned discretion). Planner must decide which legs are fixture-gated vs. always-run.

## Validation Architecture

> `workflow.nyquist_validation: false` in `.planning/config.json` — section included per template for test-planning value; no per-req sampling contract imposed.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | GTest (vendored, `GTest::gtest_main`) |
| Config file | Per-target CMakeLists (`test/processors/CMakeLists.txt` extension) |
| Quick run command | `sgproc_elm_processor_test.exe` (binary direct — BUILD_TESTING cache was OFF in the local tree per 01-01 SUMMARY) |
| Full suite command | All 15+ SGProcessingManager test binaries exit 0 |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| GEN-01 | Settings flow via set_config; seed asserted via dump_config | unit (real MNN, gated) | test binary `ElmProcessorTest.ConfigRoundTrip` | ❌ Wave 0 |
| GEN-01 | Determinism: same seed ×2 → byte-identical | integration (real model, gated + fixture) | `ElmProcessorTest.SameSeedByteIdentical` | ❌ Wave 0 |
| GEN-01 | Stop string truncates + excludes + counts at cancel | unit (mock streambuf) + gated real | `ElmProcessorTest.StopString*` | ❌ Wave 0 |
| GEN-02 | Cancel latency ≪ full generation; thread joined deliberately | integration (real model, fixture) | `ElmProcessorTest.CancelLatency` | ❌ Wave 0 |
| GEN-02 | Pin reaches zero after cancel | unit (cache + processor) | `ElmProcessorTest.PinReleasedOnCancel` | ❌ Wave 0 |
| GEN-03 | MNN_Llm migrated: load under LlmLoadMutex, not VulkanInitMutex | unit (existing 2 cases stay green) | `mnn_llm_test.exe` | ✅ (must stay green) |
| GEN-03 | No `MaterializeModelToTempDir` anywhere | grep gate | `grep -r MaterializeModelToTempDir` → 0 hits | ❌ (verification step) |
| GEN-03/SC-5 | Non-ELM MNN subtask unblocked during LLM load | integration (gated) | `ElmProcessorTest.LlmLoadDoesNotStallMnn` | ❌ Wave 0 |
| GEN-03/SC-5 | Two ELM loads serialize on LlmLoadMutex, no deadlock | integration (gated) | `ElmProcessorTest.TwoLlmLoadsSerialize` | ❌ Wave 0 |
| RES-01 | Envelope fields complete on all four finish_reasons | unit (envelope builder, no MNN) | `ElmEnvelopeTest.*` | ❌ Wave 0 |
| RES-01 | Order permutation: A,B then B,A → identical outputs | integration (fixture or mock seam) | `ElmProcessorTest.OrderPermutation` | ❌ Wave 0 |
| fork | Seed landed: `dump_config()` contains seed after set_config | unit (gated) | `ElmProcessorTest.SeedNoSilentNoOp` | ❌ Wave 0 |

### Sampling Rate
- Per task commit: run the new test binary + `mnn_llm_test.exe`
- Per wave merge: all SGProcessingManager test binaries exit 0
- Phase gate: full suite green + grep gates (no materializer; no ungated test targets)

### Wave 0 Gaps
- [ ] `test/processors/elm_processor_test.cpp` — gated TU(s); real-model legs fixture-gated or GTEST_SKIP-cross-referenced
- [ ] `test/processors/CMakeLists.txt` — new target with `SGPROC_TEST_DISCOVERY` gating + `TIMEOUT 300` (MNN-touching)
- [ ] Envelope-builder pure-unit TU (no MNN include) for the RES-01 matrix — split TU if generated-set isolation requires it
- [ ] Decision recorded: real-model fixture acquisition strategy (staged `file://` bundle vs. skip)

## Security Domain

> `security_enforcement: true`, ASVS level 1, block on high. This phase executes verified-model code shapes on the node — the fail-closed posture is inherited from Phase 2 and maintained.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V5 Input Validation | yes | Quicktype `CheckConstraint` + Phase 1 `CheckElmValidity` bounds (temperature [0,2], top_p (0,1], seed ≥0, max_output_tokens ≥1) — processor consumes VALIDATED settings, never clamps (Phase 1 D-05) |
| V6 Cryptography | yes (verification leg only) | `sgprocmanagersha` sha256 — already the model/artifact verification mechanism (Phase 2); envelope provenance hash is `ElmCachePin::GetHash()` |
| V4 Access Control | yes (scope) | No debug bypass for cache/preflight failures (Phase 2's grep-clean posture); work_item_id charset `^[A-Za-z0-9_-]+$` (schema) never interpolated into paths |
| V2/V3 | no | No authn/session surface in this phase |

### Known Threat Patterns for {stack}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Executing an unverified model (MNN graphs are executable) | Tampering/Elevation | Fail-closed acquire (Phase 2 shipped); processor NEVER loads outside a pinned entry |
| Prompt injection into result paths (`work_item_id` in filenames) | Tampering | Charset-constrained id; envelope carries it as data; cache keys are hex digests only |
| Set_config injection via generation settings | Tampering | Settings validated at parse (Phase 1); processor serializes typed values via nlohmann (no string interpolation into JSON) |
| Seed as a covert channel / DoS | Repudiation/DoS | seed ≥0 int64 bound; no unbounded RNG work |
| Temp-dir path traversal via materializer | — | ELIMINATED by D-04 (class removal, not mitigation) |

## Sources

### Primary (HIGH confidence — live-tree verification this session)
- `thirdparty/MNN/transformers/llm/engine/src/sampler.cpp:160-168,515-545` — unseeded ctor; `stepSelect` RNG consumption
- `thirdparty/MNN/transformers/llm/engine/src/llm.cpp:71-125` (createLLM/set_config/dump_config), `:265-330` (load + sampler construction at :306), `:724-775` (updateContext/generate_init), `:875-915` (generate + prompt_len), `:975-1015` (timeout + response paths), `:1317-1326` (is_stop → NORMAL_FINISHED)
- `thirdparty/MNN/transformers/llm/engine/src/speculative_decoding/generate.cpp:34-90` — ArGeneration loop, USER_CANCEL/TIMEOUT polls, MAX_TOKENS_FINISHED, per-token ostream flush
- `thirdparty/MNN/transformers/llm/engine/include/llm/llm.hpp` — full public API, LlmContext fields, LlmStatus enum, CHECK_LLM_RUNNING macros
- `thirdparty/MNN/transformers/llm/engine/src/llmconfig.hpp:48-100` — base_dir resolution, config merge, `max_new_tokens`/`timeout_ms` accessors
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_llm.cpp` — full precedent (materializer :35-77, locks :86-93, ResolveMaxNewTokens, cancel checks, PushTeardown)
- `SuperGenius/SGProcessingManager/include/elmruntime/*` + `src/elmruntime/*` — Phase 2 shipped layer (cache, pin, preflight, smoke check, error category)
- `SuperGenius/SGProcessingManager/src/capability/capability_validator.cpp:518-585` — CheckElmResources
- `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp:429-481` (factory table), `:1484-1690` (ProcessInternal incl. deadline-timer/SetCallback at :1594), `:2003-2260` (GetCidForProc)
- `SuperGenius/SGProcessingManager/include/execution/execution_context.hpp:77-175` — CancellationToken/ExecutionContext
- `SuperGenius/src/processing/processing_engine.cpp:84-150` — per-subtask thread
- `SuperGenius/src/processing/impl/processing_core_impl.cpp:67-140` — worker-side ProcessSubTask flow
- `thirdparty/build/CommonTargets.cmake:453-476` — MNN LLM build flags
- Git state (live): MNN `MNN_Ultra_v2` @ `01b6f314`; SGProcessingManager `dev_elmruntime` @ `c9ccff8`; SuperGenius `dev_elmruntime` @ `d459d45d8`; root `dev_persisprocresults`; MNN is a submodule of `thirdparty` (url `../MNN.git`)

### Secondary (MEDIUM confidence)
- `.planning/workstreams/elmbridge/research/{STACK,PITFALLS,ARCHITECTURE}.md` — workstream research (verified 2026-09-09; re-checked key claims against live tree this session — all held)

### Tertiary (LOW confidence)
- None — no WebSearch/external claims used; everything is workspace-verified

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new deps; every API claim re-verified in the live tree
- Architecture: HIGH — patterns shipped in Phase 2 (gated TU, pin RAII) verified working; routing-key question (A3/Q3) is a known-open design surface, not uncertainty about existing code
- Pitfalls: HIGH — all mechanics verified at exact line level this session

**Research date:** 2026-09-11
**Valid until:** 2026-10-11 (stable vendored-fork domain; only MNN branch movement would invalidate)
