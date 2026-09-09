# Stack Research

**Domain:** ELM (Expert Language Model) job execution — causal-LM inference inside the SuperGenius processing grid / SGProcessingManager runtime
**Researched:** 2026-09-09
**Confidence:** HIGH (all API claims grounded in the vendored MNN source tree and SuperGenius/SGProcessingManager build files, not generic upstream docs)

## Recommended Stack

**Headline: zero new dependencies.** Every capability the ELM milestone needs — LLM session, tokenizer, chat template, KV cache, sampling, detokenization, token counts, sha256 artifact verification — is already present in the vendored MNN static library and the existing SGProcessingManager link set. The work is integration code (a new ELM processor + manifest/cache layer), not stack additions.

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| MNN (vendored fork) | 3.4.1 (`MNN_VERSION` in `thirdparty/MNN/include/MNN/MNNDefine.h:75-77`); git rev `01b6f314` on branch `MNN_Ultra_v2` (`v3.0-4-g01b6f314`, merged `origin/master` 2026-09-03) | The mandated inference engine; its built-in LLM engine provides the entire causal-LM runtime | Mandated by the milestone. Verified: the LLM engine (`transformers/llm/engine/`) is compiled **into** the single MNN static lib this checkout already builds — `thirdparty/build/CommonTargets.cmake:453-471` passes `MNN_BUILD_LLM:BOOL=ON`, `MNN_BUILD_LLM_OMNI:BOOL=ON`, `MNN_LOW_MEMORY:BOOL=ON`, `MNN_SUPPORT_TRANSFORMER_FUSE`, static (`MNN_BUILD_SHARED_LIBS=OFF`), which forces `MNN_SEP_BUILD=OFF` (`thirdparty/MNN/CMakeLists.txt:126-128`), so `llm` is an OBJECT library folded into `libMNN`. Linking `MNN::MNN` (already done in `SGProcessingManager/src/processors/CMakeLists.txt:114`) already links the LLM engine. |
| `MNN::Transformer::Llm` API | as vendored (`thirdparty/MNN/transformers/llm/engine/include/llm/llm.hpp`) | LLM session: load, tokenize, prefill, autoregressive generation with KV cache, sample, detokenize, token counts | Covers every runtime requirement in the milestone's "Real ELM processor" list (see API surface table below). Already proven in-tree: `processing_processor_mnn_llm.cpp` (PROC-01) calls `Llm::createLLM()` → `load()` → `response()` under `VulkanInitMutex()`. |
| `sgns::sgprocmanagersha::sha256` | existing (`SGProcessingManager/src/util/sha256.cpp`, OpenSSL EVP) | Manifest + artifact sha256 verification | Already linked into `SGProcessors` via the `sgprocmanagersha` target (`src/processors/CMakeLists.txt:120`). Same implementation already hashes render/MNN results. Nothing new needed for verification. |
| AsyncIOManager `FileManager` | existing (validated — not re-researched) | Fetch manifest + model artifacts (`ipfs://`, `https://`, `file://`), async, already caches URL loads (`ProcessingManager.cpp:1730` uses `getCacheDir()`) | Model download is billable job work flowing through the exact channel every other processor input uses (`GetSubCidForProc` at `ProcessingManager.cpp:2056`). |
| `std::filesystem` (C++17) | existing | Content-addressed model cache `cache/<model-manifest-hash>/` | The cache directory is simultaneously the `LlmConfig` `base_dir` — `Llm::createLLM(path)` expects a directory holding `config.json`/`llm_config.json`, `tokenizer.txt`, `llm.mnn`, `llm.mnn.weight` (`llmconfig.hpp:64-135`). One directory serves both cache key and runtime load path. No library required. |
| nlohmann_json | already linked (`SGProcessors` PUBLIC) | Manifest JSON parsing, `elms[]` work-item parsing from `Task.json_data` | Same library the whole SGProcessingManager job schema already uses. |

### `MNN::Transformer::Llm` API surface in the vendored revision (all in `llm.hpp`, verified)

| ELM requirement | API in vendored MNN 3.4.1 | Notes |
|---|---|---|
| Session create/load | `Llm::createLLM(const std::string& config_path)` (directory or `config.json` path), `Llm::destroy(Llm*)`, `virtual bool load()` | `load()` validates tokenizer/model/weight files exist (`llm.cpp:847-857`), builds module pool, sets `LlmStatus::RUNNING`. |
| Tokenizer loading | automatic inside `load()` via `Tokenizer::createTokenizer(tokenizer_file)` | `tokenizer.txt` custom format, magic 430. Types: `SENTENCEPIECE=0, TIKTOIKEN=1, BERT=2, HUGGINGFACE=3, PIPELINE=4` (`tokenizer.cpp:73-131`) — all implementations bundled in-tree, no external sentencepiece/tiktoken libs. |
| Prompt tokenization | `tokenizer_encode(const std::string&) → std::vector<int>` | Public on `Llm`. |
| Chat template | `apply_chat_template(user_content)` / `apply_chat_template(ChatMessages)`; `ChatMessage = pair<role, content>` | Two mechanisms, both in-engine: (a) Jinja — header-only `src/tokenizer/jinja.hpp`, unconditionally enabled (`LLM_USE_JINJA`, `transformers/llm/engine/CMakeLists.txt:46`), template from `jinja.chat_template` config key or `context.json` file; (b) legacy `%s`-style `system/user/assistant_prompt_template` config keys (`llmconfig.hpp:334-348`). Default template is Qwen-style `<|im_start|>`. |
| Prefill + autoregressive generation with KV cache | `response(prompt, ostream*, end_with, max_new_tokens)`; or `generate(input_ids, max_tokens)` returning `std::vector<int>` output token ids | KV cache fully internal (`KVMeta`, module pool prefill/decode split at `llm.cpp:395-405`). `ArGeneration::generate` (`speculative_decoding/generate.cpp:34-77`) is the canonical loop: sample → `is_stop` → detokenize-and-stream → forward one token. |
| Sampling params | `set_config(const std::string& json)` merges into `LlmConfig` at runtime (`llm.cpp:101`) | Supported keys (verified in `llmconfig.hpp:353-445` + `sampler.cpp`): `temperature`, `top_p`/`topP`, `top_k`/`topK`, `min_p`, `tfs_z`, `typical`, `repetition_penalty`, `presence_penalty`, `frequency_penalty`, `logit_bias`, `banned_tokens`, `sampler_type` (`greedy`/`temperature`/`topP`/`mixed`/…), `max_new_tokens`, `max_all_tokens`, `timeout_ms`. |
| Stop tokens | `is_stop(int token)` public; stop tokens loaded from `tokenizer.txt` header (`tokenizer.cpp:143,167`) | Token-based only — see Gaps for stop *strings*. |
| Detokenization | `tokenizer_decode(int) → std::string` | Public on `Llm`. |
| Token counts | `getContext() → const LlmContext*`: `prompt_len`, `output_tokens.size()`, `all_seq_len`, `history_tokens` | Accurate counts without re-tokenizing. Also perf fields `prefill_us`/`decode_us`/`sample_us` for billing-relevant timing. |
| Streaming (per-token text) | `response(..., std::ostream* os, ...)` — `ArGeneration` writes each decoded token to `*os` with flush per token (`generate.cpp:60-63`) | Pass a custom `std::ostream` with your own `streambuf` to observe tokens as they are produced — this is the hook for stop-string detection and progress reporting without touching MNN internals. |
| Generation-loop bounds | `max_new_tokens` (arg or config, default 512), `timeout_ms` (config; checked in the ArGeneration loop → `LlmStatus::TIMEOUT`, `generate.cpp:42-44`) | `timeout_ms` is a real wall-clock bound on prefill+decode already enforced inside MNN. |
| KV cache management | `reset()`, `setKVCacheInfo(add, remove, …)`, `eraseHistory(begin, end)`, `getCurrentHistory()`, `reuse_kv()` config, prefix-cache file API `setPrefixCacheFile()` | One-shot ELM work items need none of this (fresh `Llm` per work item); available if multi-turn ELM types arrive later. |
| Status/finish reason | `getContext()->status`: `NORMAL_FINISHED / MAX_TOKENS_FINISHED / USER_CANCEL / INTERNAL_ERROR / TIMEOUT / RUNNING` | Maps directly onto the milestone's `finish_reason` output field. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| OpenSSL EVP (`EVP_MD_CTX`/`EVP_sha256`) | already vendored, `OpenSSL::Crypto` linked to `SGProcessors` | Artifact hash verification while streaming downloads | The existing `sha256()` helper is one-shot over a full buffer. For multi-hundred-MB weight files, add a small incremental wrapper (`EVP_DigestInit_ex/Update/Final`) inside `sgprocmanagersha` so artifacts are hashed as they download — same dependency, ~30 lines, avoids a second full read of the file. |
| GTest | vendored, already used (`mnn_llm_test` exists) | ELM processor + manifest/cache unit tests | Extend the existing `SGPROC_HAS_MNN_LLM`-gated test target pattern (`test/processors/CMakeLists.txt:26-28`). |
| quicktype-generated job schema | existing pipeline | `elms[]` work-item schema in `Task.json_data` | Same route the render pass schema took (SCHEMA-01..05) — no protobuf change, per milestone decision. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| MNN LLM header gate | `SGPROC_HAS_MNN_LLM` configure-time check (`src/processors/CMakeLists.txt:30-41`) | Already TRUE in this checkout (headers confirmed at `MNN_INCLUDE_DIR/llm/llm.hpp`, a sibling of `MNN_INCLUDE_DIR/MNN/`, on Windows and macOS). The ELM processor should sit behind this same gate so builds against an LLM-less MNN still configure. |
| `Llm::set_config()` JSON probe | Runtime sanity tool during development | `dump_config()` echoes the merged config — useful in tests to assert the processor's generation settings actually landed in the sampler. |

## Installation

```bash
# Nothing to install. Everything is vendored and already built:
# - MNN with LLM engine: thirdparty/build/CommonTargets.cmake:453-471
#     (MNN_BUILD_LLM=ON, MNN_BUILD_LLM_OMNI=ON, MNN_VULKAN=ON, static)
# - Header location consumed by SGProcessingManager: ${MNN_INCLUDE_DIR}/llm/llm.hpp
#   (SGProcessingManager/cmake/CommonBuildParameters.cmake:279-290 resolves MNN::MNN)
# - sha256: sgprocmanagersha target (OpenSSL::Crypto)
# - FileManager: AsyncIOManager (ipfs:// https:// file:// prefixes)
```

No CMake dependency-graph changes are expected beyond adding the new ELM processor source to the existing `SGProcessors` target (optionally behind `SGPROC_HAS_MNN_LLM`).

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| MNN `Llm::response()` / `generate()` | Hand-rolled loop over `forward()` + own sampling | Only if a need emerges that the loop can't express (e.g. structured/logit-bias decoding mid-stream). Even then prefer `Llm::sample()` (public) over reimplementing samplers. The existing MNN_Llm processor already made this call correctly ("port MNN's own native autoregressive API … NOT a hand-rolled sampling loop"). |
| `set_config()` for generation params | Writing params into the cached `llm_config.json` at cache-materialization time | Use `set_config()` for per-work-item settings (temperature/top_p/max tokens vary per work item; cache is shared per model). Bake only model-invariant settings (backend, threads) into the cached config file. |
| Greedy sampler for `temperature == 0` | Seeded RNG | MNN has **no seed API** (see Gaps). `sampler_type: "greedy"` is genuinely deterministic (argmax). |
| Minimal fork patch in `MNN_Ultra_v2` for seed + cancel | Working around in processor layer | The vendored MNN is GNUS's own fork branch (already carries custom work, e.g. the SGFP4 v2 converter per tag `v3.0`). If seeded sampling or true mid-generation cancel is a hard requirement, a ~20-line patch (seed key read in `Sampler::Sampler`; a public `Llm::cancel()` setting `mContext->status = USER_CANCEL`) is lower-risk than contortions at the call site — but ship v1.0 without it if greedy/timeout bounds suffice. Decision point for planning. |
| Custom `std::ostream`/`streambuf` observing the token stream | Patching MNN for a callback API | The ostream hook is public API and flushes per token — sufficient for stop-string detection, progress, and token counting. |
| `timeout_ms` + `max_new_tokens` as the cancellation bound | Thread-kill / process isolation | MNN checks `timeout_ms` inside the generation loop and exits cleanly with `LlmStatus::TIMEOUT`; combine with the existing pattern in `processing_processor_mnn_llm.cpp` (cancel-token re-check after `response()` returns, teardown via `PushTeardown`). |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| llama.cpp / ggml | Explicitly excluded by mandate; would add a second inference engine, second model format, second tokenizer stack to verify | MNN LLM engine (already linked) |
| ONNX Runtime | Same mandate; also pulls a large dependency and its own execution providers that duplicate MNN's backends | MNN LLM engine |
| Standalone sentencepiece / HF `tokenizers` / tiktoken libs | Redundant — MNN bundles SentencePiece (BPE, `tokenizer.cpp:282` implements the sentencepiece BPE algorithm), Tiktoken, BERT, HF, and Pipeline (`.mtok`) tokenizers behind one `tokenizer.txt` format | MNN's bundled tokenizer loaded from the cached `tokenizer.txt` artifact |
| Separate Jinja2/Jinja2CPP library | `LLM_USE_JINJA` is unconditionally ON in this MNN build; the engine bundles a header-only jinja renderer for `chat_template` | MNN's in-engine jinja + `context.json` |
| New crypto/hash dependency (picosha256, Crypto++, Botan) | sha256 already exists three ways in-tree: `sgprocmanagersha` (OpenSSL EVP), SuperGenius `Hasher`, raw `openssl/sha.h` includes | `sgprocmanagersha` — extend with an incremental helper only if streaming-hash-while-download is wanted |
| MNN's own HTTP model downloader (`LLM_SUPPORT_HTTP_RESOURCE`, `hf_api_client.hpp`, `remote_model_downloader.hpp`) | Fetching belongs to the job's FileManager path (ipfs://, billable, hash-verified, cache-coordinated) — MNN's downloader bypasses all of that; also drags cpp-httplib into the link | `FileManager::LoadASync` for every artifact named in the manifest |
| New protobuf messages for ELM job definition | Milestone decision: `elms[]` lives in `Task.json_data`; splitter maps work items to existing `SubTask.subtaskid` | Existing `Task.json_data` + quicktype schema |
| Enabling `MNN_SEP_BUILD` | Forces a separate `llm` lib; MNN itself warns and turns it OFF for static builds | Keep single static `MNN::MNN` |
| `MNN_LLM_BUILD_DEMO=ON` | Builds demo executables into the thirdparty tree for no benefit | Keep the existing `OFF` (`CommonTargets.cmake:470`) |

## Stack Patterns by Variant

**If `generation.temperature == 0` (deterministic work item):**
- `set_config(R"({"sampler_type": "greedy"})")`
- Argmax select is bit-deterministic; cross-node validation of the result hash stays meaningful.

**If `0 < temperature ≤ 2` with `top_p`:**
- `set_config(R"({"sampler_type": "topP", "temperature": T, "top_p": P})")` (or default `mixed` pipeline)
- **Non-deterministic across runs** — MNN's `Sampler` seeds `std::mt19937` from `std::random_device` at construction (`sampler.cpp:162`); the `seed` field from the job JSON cannot be honored by public API in this revision. v1.0 should either document `seed` as best-effort/ignored-for-sampling (still useful as the task-level `random_seed`), or take the minimal fork patch. Flag for the planning phase.

**If stop *strings* (not just stop tokens) are required:**
- Wrap a custom `streambuf` in the `std::ostream` passed to `response()`; buffer decoded text, scan for stop strings, and stop generation by `set_config({"max_new_tokens": 0})`-style early bound — or simpler and robust for v1.0: run to completion and truncate output at the stop string, reporting `finish_reason: "stop"` and the truncated token count from `getContext()->output_tokens.size()`. The `end_with` parameter only controls text emitted after a *token* stop; it is not a stop-string mechanism.

**If mid-generation cancellation is required (job cancelled / budget exceeded):**
- Layered bound: `timeout_ms` (config, enforced inside MNN's loop) + `max_new_tokens` + cancel-token re-checks before load and after `response()` returns (the existing MNN_Llm processor's exact pattern). Note `getContext()` returns a **const** pointer and no public API sets `LlmStatus::USER_CANCEL` — the enum value is checked inside the loop but cannot be triggered externally in this revision. True interrupt needs the small fork patch or is deferred.

**If the model's `llm_config.json` declares `"backend_type": "vulkan"`:**
- MNN sets `shapeMutable=false` for vulkan/opencl/npu (`llm.cpp:377-381`); fine for fixed-shape causal-LM prefill/decode. Follow the existing `VulkanInitMutex()` discipline around `createLLM()`/`load()` exactly as `processing_processor_mnn_llm.cpp` does. `"cpu"` (default, `thread_num` 4) is the safe default for the Qwen-0.5B-class E2E model; make backend a model-manifest/`llm_config.json` property, not a processor property.

**If the E2E model is Qwen-0.5B-class:**
- Its tokenizer is BPE/tiktoken-style → `TIKTOIKEN` type is supported; Qwen chat template matches MNN's default `<|im_start|>` templates. No special-casing needed in the processor.

## Version Compatibility

| Item | Compatible With | Notes |
|------|-----------------|-------|
| MNN 3.4.1 fork (`MNN_Ultra_v2` @ `01b6f314`) | SGProcessingManager `MNN::MNN` link (already consumed) | LLM engine compiled into the static lib; headers installed at `MNN_INCLUDE_DIR/llm/llm.hpp` — the non-nested path `src/processors/CMakeLists.txt:16-19` documents |
| `llm/llm.hpp` include | C++17 (SGProcessingManager standalone sets 17; `CommonBuildParameters.cmake` defaults 20 only when undefined) | Header is C++11-compatible; no language bump |
| MNN LLM engine | Vulkan backend (`MNN_VULKAN=ON`, `MNN_VULKAN_IMAGE=OFF` in the thirdparty build) | `shapeMutable=false` path for GPU; CPU path default |
| `Llm::createLLM(dir)` | the content-addressed cache layout `cache/<model-manifest-hash>/` | `LlmConfig` resolves `config.json`/`llm_config.json`, `tokenizer.txt`, `llm.mnn`(+`.weight`) relative to `base_dir` — manifest artifact names should map onto these keys (`llm_model`, `llm_weight`, `tokenizer_file`) so the cache dir is directly loadable |
| `sgprocmanagersha` | `OpenSSL::Crypto` static (vendored, MSVC static RT) | Same EVP used everywhere in-tree |
| Manifest `quantization: "SGFP4"` | the fork's own SGFP4 v2 converter work (tag `v3.0`) | The vendored fork was extended *for* SGFP4 — quantization handling is in-engine; no converter dependency for execution |

## Known Gaps (honest limits of the vendored API — plan around these)

1. **No sampling seed API.** `Sampler::Sampler` unconditionally seeds `mRng(std::random_device{}())` (`sampler.cpp:162`); no config key reaches it. `generation.seed` cannot be honored for stochastic sampling in this revision. Options: greedy-when-temperature-0, ignore-and-document, or a minimal fork patch (the fork is GNUS-owned, precedent exists).
2. **No public cancellation setter.** `LlmStatus::USER_CANCEL` is polled inside every generation strategy (`generate.cpp:46`) but `getContext()` is const and no setter exists. Practical cancellation = `timeout_ms` + `max_new_tokens` + post-hoc cancel-token check; true interrupt requires a one-line fork patch.
3. **Stop strings are not native.** Stopping is token-based (`is_stop`, tokenizer-file stop tokens). Stop-string handling is a processor-layer concern (ostream observation or post-truncation).
4. **`response()` blocks.** Run it on a worker thread (as the current processor does implicitly via the processing pipeline); the per-token `ostream` flush is the only streaming observation point.
5. **`LlmConfig` file-shape requirements.** The engine reads files from disk by name; the ELM cache layer must materialize manifest artifacts under the names/keys the engine expects. This is exactly why the content-addressed cache directory is the right integration point.

## Sources

All claims verified by direct inspection of the vendored workspace (HIGH confidence):

- `thirdparty/MNN/include/MNN/MNNDefine.h:75-78` — MNN 3.4.1 version macros
- `git -C thirdparty/MNN describe` → `v3.0-4-g01b6f314`, branch `MNN_Ultra_v2` (run 2026-09-09)
- `thirdparty/build/CommonTargets.cmake:453-482` — MNN ExternalProject args (LLM ON, static, Vulkan)
- `thirdparty/MNN/transformers/llm/engine/include/llm/llm.hpp` — full `Llm`/`LlmContext`/`LlmStatus` public API
- `thirdparty/MNN/transformers/llm/engine/src/llm.cpp` — `set_config` (101), `load()` file checks (847+), timeout check (975-979), `is_stop` → `NORMAL_FINISHED` (1317-1326)
- `thirdparty/MNN/transformers/llm/engine/src/llmconfig.hpp` — all generation/sampler/backend config keys
- `thirdparty/MNN/transformers/llm/engine/src/sampler.cpp/hpp` — sampler types, penalties, `mRng(std::random_device{}())` seed gap
- `thirdparty/MNN/transformers/llm/engine/src/tokenizer/tokenizer.cpp/hpp` — tokenizer types (SentencePiece/Tiktoken/BERT/HF/Pipeline), stop/special tokens, chat-template API
- `thirdparty/MNN/transformers/llm/engine/src/speculative_decoding/generate.cpp` — `ArGeneration` loop: sample → stop → stream-detokenize → forward; USER_CANCEL/TIMEOUT polls
- `thirdparty/MNN/transformers/llm/engine/CMakeLists.txt` — `LLM_USE_JINJA` unconditional, OBJECT-lib folding, `LLM_SUPPORT_HTTP_RESOURCE` (unused by us)
- `SuperGenius/SGProcessingManager/cmake/CommonBuildParameters.cmake:279-290` — MNN::MNN resolution
- `SuperGenius/SGProcessingManager/src/processors/CMakeLists.txt:12-41,107-122` — `SGPROC_HAS_MNN_LLM` gate, existing link set
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_llm.cpp` — existing `createLLM`/`response` integration pattern, temp-dir materialization, teardown/cancel discipline
- `SuperGenius/SGProcessingManager/src/util/sha256.cpp` — OpenSSL EVP sha256 helper
- `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp:2056` — `FileManager::LoadASync` input-fetch pattern

---
*Stack research for: ELM job execution (elmbridge workstream)*
*Researched: 2026-09-09*
