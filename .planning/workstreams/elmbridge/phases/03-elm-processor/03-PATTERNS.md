# Phase 3: ELM Processor - Pattern Map

**Mapped:** 2026-09-11
**Files analyzed:** 12 (7 new, 5 modified)
**Analogs found:** 12 / 12

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `SuperGenius/SGProcessingManager/include/processors/processing_processor_elm.hpp` (NEW) | component (processor header) | request-response | `include/processors/processing_processor_mnn_llm.hpp` | exact |
| `SuperGenius/SGProcessingManager/src/processors/processing_processor_elm.cpp` (NEW) | service (gated processor TU) | request-response + streaming | `src/processors/processing_processor_mnn_llm.cpp` + `src/elmruntime/ElmSmokeCheck.cpp` | exact (both halves) |
| `include/processingbase/vulkan_init_guard.hpp` (MODIFY — add `LlmLoadMutex()`) | utility (sync primitive) | n/a (cross-cutting) | `VulkanInitMutex()` in the same file | exact |
| `src/processors/processing_processor_mnn_llm.cpp` (MODIFY — D-04 migration) | service | request-response | itself + ElmSmokeCheck lock sequence | exact |
| `thirdparty/MNN/transformers/llm/engine/src/sampler.cpp` + `sampler.hpp` (PATCH — D-12) | library (fork patch) | transform | existing `configSampler` config reads in the same file | exact |
| `thirdparty/MNN/transformers/llm/engine/include/llm/llm.hpp` (+ `.cpp` if needed) (PATCH — D-13) | library (fork patch) | event-driven (cancel) | `getContext()` inline accessor in the same header | exact |
| `src/processors/CMakeLists.txt` (MODIFY — D-14 gate/marker) | config (build) | n/a | existing `SGPROC_HAS_MNN_LLM` block, lines 24-68 | exact |
| `src/processingbase/ProcessingManager.cpp` (MODIFY — factory registration) | route (factory table) | request-response | existing `#ifdef SGPROC_HAS_MNN_LLM` registration, lines 453-460 | exact |
| `test/processors/elm_processor_test.cpp` + `test/processors/CMakeLists.txt` (NEW) | test | request-response | `test/processors/mnn_llm_test.cpp` + `test/elmruntime/CMakeLists.txt` | exact |
| Envelope builder (inside ELM processor TU or a separate no-MNN TU) | model (result struct + serialization) | transform | `ProcessingResult` construction in `processing_processor_mnn_llm.cpp:245-252` | role-match |
| Stop-string streambuf (inside ELM processor TU) | utility (observer) | streaming | no codebase analog — see "No Analog Found" | none |
| `CheckElmResources` call-site wiring (inside ELM processor) | middleware (preflight) | request-response | `ElmResourcePreflight.hpp` + `capability_validator.cpp:518-585` | exact (compose both halves) |

---

## Pattern Assignments

### `include/processors/processing_processor_elm.hpp` (processor header)

**Analog:** `SuperGenius/SGProcessingManager/include/processors/processing_processor_mnn_llm.hpp`

**Forward-declaration / include-isolation pattern** (lines 16-29) — the header must contain ZERO MNN includes so ProcessingManager.hpp (which names the class for factory registration) never needs `<llm/llm.hpp>`:

```cpp
namespace MNN
{
    namespace Transformer
    {
        class Llm;
    } // namespace Transformer
} // namespace MNN

namespace sgns::sgprocessing
{
    class MNN_Llm : public ProcessingProcessor
    {
    public:
        MNN_Llm() {}
        ~MNN_Llm() override {};

        ProcessingResult StartProcessing( std::vector<std::vector<uint8_t>> &chunkhashes,
                           const sgns::IoDeclaration         &proc,
                           std::vector<char>                 &promptData,
                           std::vector<char>                 &modelFile,
                           const std::vector<sgns::Parameter> *parameters,
                           const ExecutionContext            &execCtx ) override;
    };
}
```

Include `processing_processor.hpp` (base), keep the same 6-arg `StartProcessing` override signature. Doxygen `@brief/@param/@return` comments per conventions. Note: the ELM processor will need a seam to receive the `Elm` work item / manifest URI+hash (the fixed signature carries prompt/model buffers) — follow the header's doc-comment style to explain the entry convention.

---

### `src/processors/processing_processor_elm.cpp` (gated processor TU)

**Analogs:** `src/elmruntime/ElmSmokeCheck.cpp` (gated-TU + load sequence) and `src/processors/processing_processor_mnn_llm.cpp` (full processor flow).

#### Gate + include isolation (`ElmSmokeCheck.cpp:8-27`)

The ENTIRE MNN surface lives inside the gate; no header reachable from the ELM header names an MNN type:

```cpp
#if defined( SGPROC_HAS_MNN_LLM )
#include "processingbase/vulkan_init_guard.hpp"
#include <llm/llm.hpp>
// ... real implementation
#else // !SGPROC_HAS_MNN_LLM
// Fail-closed fallback: processor always errors (never silently no-ops)
#endif // SGPROC_HAS_MNN_LLM
```

#### Lock-split load sequence (D-01/D-04) — rewrite of `mnn_llm.cpp:86-93`

Current combined lock (what both processors move away from):

```cpp
MNN::Transformer::Llm *llm = nullptr;
{
    std::lock_guard<std::mutex> lock( sgns::sgprocessing::VulkanInitMutex() );
    llm = MNN::Transformer::Llm::createLLM( tempDir );
    if ( llm && !llm->load() )
    {
        MNN::Transformer::Llm::destroy( llm );
        llm = nullptr;
    }
}
```

Target shape: `createLLM` stays under `VulkanInitMutex()` (scoped block); `load()` moves under the NEW `LlmLoadMutex()` (separate scoped block); destroy-on-failure on every path — mirror `ElmSmokeCheck.cpp:54-77`'s destroy-on-every-error discipline.

#### set_config BEFORE load (Pitfall 3 — hard ordering requirement)

`ElmSmokeCheck.cpp:68-71` is the verified precedent with the exact comment convention:

```cpp
// Greedy = deterministic probe (no RNG); 1 new token = minimal work.
// set_config before load so the sampler config applies to the probe.
if ( !llm->set_config( R"({"sampler_type":"greedy","max_new_tokens":1})" ) )
```

The Sampler is constructed inside `Llm::load()` (`llm.cpp:306`) and reads config in its ctor — the D-12 seed key MUST be in `config_` before `load()` fires. After `set_config`, assert via `dump_config()` round-trip (D-12's no-silent-no-op guard; `dump_config()` is `llm.cpp:85-87`: `return mConfig->config_.dump();`).

#### Full processor flow (`mnn_llm.cpp:128-262`)

Ordered skeleton to replicate (with ELM substitutions):

```cpp
// 1. Pre-cancel check BEFORE any work (mnn_llm.cpp:137-143)
if ( execCtx.cancelToken.IsCancelled() )
{
    return ProcessingResult{ {}, nullptr, {},
        ProcessingError{ ProcessingErrorStage::CANCELLED, "..." } };
}
// 2. Cache acquire (replaces empty-model check): ElmModelCache::Acquire(manifestUri, manifestHash)
//    -> outcome::result<ElmCachePin>; hold pin by value in this scope = RAII release on ALL returns
// 3. Preflight: ExtractElmResourceRequirements(manifest) -> CheckElmResources (see below)
// 4. Progress event LOAD_MODEL (mnn_llm.cpp:159-162)
// 5. createLLM(pin.GetDir()) under VulkanInitMutex; set_config(seed/temperature/top_p/max_new_tokens) + dump_config assert; load() under LlmLoadMutex
// 6. PushTeardown immediately after successful load (mnn_llm.cpp:172-175):
PushTeardown( [llm]() { MNN::Transformer::Llm::destroy( llm ); } );
// 7. Post-load cancel re-check -> RunTeardown() + CANCELLED (mnn_llm.cpp:177-183)
// 8. Generation: response(prompt, &stopStream, "", maxOutputTokens)
// 9. Reconcile LlmContext counts/status; build envelope; sha256 output; budget check
// 10. RunTeardown(); return result
```

#### Progress events + structured error returns (`mnn_llm.cpp:159-162, 191-196`)

```cpp
if ( execCtx.progressCallback )
{
    execCtx.progressCallback( ProgressEvent::ForMNN( passId, MNNStage::LOAD_MODEL, 10.0f ) );
}
// errors:
return ProcessingResult{ {}, nullptr, {},
    ProcessingError{ ProcessingErrorStage::RESOURCE_RESOLUTION, "MNN LLM model failed to load" } };
```

#### Output construction (`mnn_llm.cpp:239-252`)

```cpp
const std::string outputText = oss.str();
const auto        subTaskResultHash =
    sgprocmanagersha::sha256( outputText.c_str(), outputText.size() );
chunkhashes.push_back( subTaskResultHash );
// budget check (mnn_llm.cpp:255-263) then:
ProcessingResult result;
result.hash            = subTaskResultHash;
result.output_buffers  = std::make_shared<std::pair<std::vector<std::string>, std::vector<std::vector<char>>>>();
result.output_buffers->first.push_back( "" );
result.output_buffers->second.push_back( std::vector<char>( outputText.begin(), outputText.end() ) );
```

The ELM envelope (JSON with `work_item_id`, counts, `finish_reason`, `model_manifest_hash`) becomes this output buffer; hash = sha256 of the envelope bytes. Provenance hash comes from `ElmCachePin::GetHash()`.

---

### `vulkan_init_guard.hpp` — add `LlmLoadMutex()` (D-03)

**Analog:** `VulkanInitMutex()` in `SuperGenius/SGProcessingManager/include/processingbase/vulkan_init_guard.hpp:18-23`

Copy the free-function + magic-static idiom verbatim, directly beside it, with the same documentation density (the existing comment explains scope, call-site convention, and re-verification discipline):

```cpp
inline std::mutex &VulkanInitMutex()
{
    static std::mutex vulkan_init_mutex; // magic static -- thread-safe init, C++11+
    return vulkan_init_mutex;
}
```

`LlmLoadMutex()` is an `inline` free function in `namespace sgns::sgprocessing`, header-declared (D-03: not a file-static, not on the model cache). Update the header's comment block to state the two-lock discipline: VulkanInitMutex = createLLM/GPU-init window only; LlmLoadMutex = `Llm::load()` serialization.

---

### `processing_processor_mnn_llm.cpp` — D-04 migration

**Analog:** itself + `ElmSmokeCheck.cpp` lock sequence.

- **Delete** `MaterializeModelToTempDir` (lines 35-77) and its anonymous-namespace block; `LoadModel`'s materialize call (lines 60-66) goes with it.
- **Rewrite** `LoadModel` (or its replacement) to the split-lock sequence (pattern above).
- The two existing test legs (`mnn_llm_test.cpp`: empty model → RESOURCE_RESOLUTION; pre-cancel → CANCELLED) short-circuit BEFORE LoadModel — they survive unchanged. Verify no other caller references the materializer (grep gate: 0 hits).
- See RESEARCH Pitfall 9 / Open Question Q2: planner decides the MNN_Llm end-state (fail-closed shim vs. teardown-cleaned dir) within D-04's "zero temp-dir materializers" end-state.

---

### MNN fork patch D-12: sampler seed

**Analog:** existing config reads in `thirdparty/MNN/transformers/llm/engine/src/sampler.cpp` ctor (lines 160-168) and `configSampler`'s `llmConfig->...()` accessor style.

Exact current state to patch (`sampler.cpp:160-168`):

```cpp
Sampler::Sampler(std::shared_ptr<LlmContext> context, std::shared_ptr<LlmConfig> config)
    : mContext(context), mRng(std::random_device{}()) {
    mConfig.max_all_tokens = config->max_all_tokens();
    mConfig.max_new_tokens = config->max_new_tokens();
    mConfig.type = config->sampler_type();
    mConfig.configSampler(mConfig.type, config);
    buildPipeline();
}
```

Patch shape (read the merged `config_` — the same JSON `set_config` merges into at `llm.cpp:101`):

```cpp
// in the ctor body:
if (config->config_.contains("seed")) {
    mRng.seed(static_cast<std::mt19937::result_type>(
        config->config_["seed"].get<int64_t>() & 0xFFFFFFFFull));
}
```

`mRng` is `std::mt19937` (`sampler.hpp:76`), so a uint32 seed width is correct. `sampler.hpp` needs no change for the config-key route (optional: an `LlmConfig` accessor mirroring `timeout_ms()` style — either is ~5 lines). Config must land BEFORE `load()` (Sampler is constructed at `llm.cpp:306` inside `load()`).

---

### MNN fork patch D-13: `Llm::cancel()`

**Analog:** `getContext()` inline accessor in `thirdparty/MNN/transformers/llm/engine/include/llm/llm.hpp` (public section, ~line 164):

```cpp
const LlmContext* getContext() const {
    return mContext.get();
}
```

Patch shape (public one-liner in the same public section; comment carries the thread-safety note):

```cpp
void cancel() { mContext->status = LlmStatus::USER_CANCEL; }
```

The unwind target is verified: `generate.cpp:46` polls `if(mContext->status == LlmStatus::USER_CANCEL || ... INTERNAL_ERROR) break;` at the top of every loop iteration — unwinding is one step. `mContext` is `protected` (`llm.hpp`, `std::shared_ptr<LlmContext> mContext`), so only a member can set it. No reason parameter (D-09).

---

### `src/processors/CMakeLists.txt` — D-14 gate + marker

**Analog:** the existing `SGPROC_HAS_MNN_LLM` block, `SuperGenius/SGProcessingManager/src/processors/CMakeLists.txt:24-68`.

Three elements to extend:

**1. Configure-time detection (lines 30-40) — reuse as-is** (the `if(EXISTS "${MNN_INCLUDE_DIR}/llm/llm.hpp")` + `CACHE INTERNAL` pattern; the CACHE INTERNAL is what lets sibling test dirs read the result).

**2. Conditional source list (lines 42-48):**

```cmake
set(_SGPROC_LLM_SOURCES "")
set(_SGPROC_LLM_HEADERS "")
if(SGPROC_HAS_MNN_LLM)
    list(APPEND _SGPROC_LLM_SOURCES processing_processor_mnn_llm.cpp)
    list(APPEND _SGPROC_LLM_HEADERS ../../include/processors/processing_processor_mnn_llm.hpp)
endif()
```

→ append `processing_processor_elm.cpp/.hpp` to the same gated lists.

**3. Compile-time marker (lines 66-69):**

```cmake
if(SGPROC_HAS_MNN_LLM)
    target_compile_definitions(SGProcessors PUBLIC SGPROC_HAS_MNN_LLM)
endif()
```

→ add a second detection (e.g. `SGPROC_MNN_HAS_LLM_CANCEL`, grepping the vendored header for `void cancel()` at configure time, same `EXISTS`/`file(READ ...)` idiom or equivalent CMake convention already established) so stock MNN still builds with a degraded path documented. Marker name/mechanism is discretion; prefer whatever convention this block already established.

---

### `src/processingbase/ProcessingManager.cpp` — factory registration

**Analog:** the gated `MNN_Llm` registration, `ProcessingManager.cpp:453-460`:

```cpp
#ifdef SGPROC_HAS_MNN_LLM
        // PROC-01: only registered when the vendored MNN was built with MNN_BUILD_LLM=ON
        // (see ProcessingManager.hpp's include guard and src/processors/CMakeLists.txt's
        // configure-time detection). In checkouts without LLM support (like this one),
        // DataType::LLM has no registered factory and SetProcessorByName() returns false,
        // so ProcessInternal() fails closed with the existing Error::NO_PROCESSOR path --
        // the same behavior any other unregistered DataType already has.
        RegisterProcessorFactory( static_cast<int>( DataType::LLM ),
                                  [] { return std::make_unique<sgprocessing::MNN_Llm>(); } );
#endif
```

Register the ELM executor with the same `#ifdef` + explanatory-comment discipline (exact key/routing leg is RESEARCH Open Question Q3 — Phase 3 ships registration + a standalone-testable entry path; full grid routing is Phase 4).

**Critical collision to respect (Pitfall 4):** `ProcessInternal` already owns the token callback at lines 1582-1586:

```cpp
// Register cancel callback: if explicit cancel happens first, cancel the timer
execCtx.cancelToken.SetCallback( [&deadlineTimer]()
{
    deadlineTimer.cancel();
} );
```

`CancellationToken` holds ONE `std::function` (last-set-wins, `execution_context.hpp:107-112`). The processor must NOT blindly call `SetCallback` — RESEARCH recommends the streambuf-poll of `IsCancelled()` per token flush as primary (zero ProcessManager changes; latency ≈ 1 token), invoking `llm->cancel()` from the poll.

---

### `test/processors/elm_processor_test.cpp` + `test/processors/CMakeLists.txt`

**Analogs:** `test/processors/mnn_llm_test.cpp` (direct-call processor test), `test/elmruntime/CMakeLists.txt` (gating + TIMEOUT), `test/elmruntime/elm_model_cache_test.cpp` (fixture + injection seams), `test/execution/cancellation_test.cpp` (GTEST_SKIP precedent).

**Test-call pattern** (`mnn_llm_test.cpp:19-37, 43-74`) — call `StartProcessing` directly, never via `ProcessingManager::Create()`:

```cpp
MNN_Llm                           processor;
std::vector<std::vector<uint8_t>> chunkhashes;
sgns::IoDeclaration               decl = MakeLlmDeclaration();
auto                               execCtx = ExecutionContext::NoOp();
if ( preCancel )
{
    execCtx->cancelToken.Cancel();
}
auto result = processor.StartProcessing( chunkhashes, decl, promptData, modelFile, nullptr, *execCtx );
```

Follow its elapsed-time assertion idiom (`EXPECT_LT( callResult.elapsedMs, 1000.0 )`) to prove short-circuit paths never entered a real load, and its comment style explaining why legs avoid fixtures.

**Fixture/skip patterns** (`elm_model_cache_test.cpp:46-80`): `TempCacheRoot` RAII fixture with uuid-suffixed temp dir (`sgproc_elm_cache_test_<uuid>`), in-memory counting FetchFn, stub smoke lambda — the model for any ELM test needing a cache without a network. Real-model legs (determinism/cancel-latency/order-permutation) follow `cancellation_test.cpp`'s `GTEST_SKIP() << "..."` precedent with cross-references when the fixture is absent.

**Test CMake gating** (`test/elmruntime/CMakeLists.txt:29-41` — the verbatim template):

```cmake
add_executable(sgprocelmruntime_cache_test elm_model_cache_test.cpp)
target_link_libraries(sgprocelmruntime_cache_test PRIVATE GTest::gtest_main sgprocmanagerelmruntime)
if(SGPROC_HAS_MNN_LLM)
    target_compile_definitions(sgprocelmruntime_cache_test PRIVATE SGPROC_HAS_MNN_LLM)
    target_link_libraries(sgprocelmruntime_cache_test PRIVATE MNN::MNN Vulkan::Vulkan)
endif()
add_test(NAME sgprocelmruntime_cache_test COMMAND sgprocelmruntime_cache_test)
if(SGPROC_TEST_DISCOVERY AND NOT CMAKE_CROSSCOMPILING)
    gtest_discover_tests(sgprocelmruntime_cache_test DISCOVERY_TIMEOUT 60)
endif()
set_tests_properties(sgprocelmruntime_cache_test PROPERTIES TIMEOUT 300)
```

Whole-binary `add_test` always; `gtest_discover_tests` only under `SGPROC_TEST_DISCOVERY AND NOT CMAKE_CROSSCOMPILING` (Pitfall 15.3 — wrong gating re-breaks the SuperGenius parent build); `TIMEOUT 300` for MNN-touching legs, 120 for fast legs. Target gating via `if(SGPROC_HAS_MNN_LLM)` around the whole `add_executable` when every leg needs the engine (`test/processors/CMakeLists.txt:28-48`), or compile-definition gating when only some legs do.

---

### `CheckElmResources` call-site wiring (inside the ELM processor)

**Analogs:** both shipped halves — compose them.

**Half 1 — extract** (`include/elmruntime/ElmResourcePreflight.hpp:44-76`, `sgns::elmruntime::ExtractElmResourceRequirements(const sgns::ElmModelManifest&)` returns `ElmResourceRequirements{requiredMemoryBytes, totalArtifactBytes}`): call it on the gate-passed manifest from the Acquire flow; it already follows the materialize-by-value-optionals UB rule.

**Half 2 — check** (`src/capability/capability_validator.cpp:518-585`):

```cpp
void CapabilityValidator::CheckElmResources( uint64_t                  requiredMemoryBytes,
                                             uint64_t                  totalArtifactBytes,
                                             const CanExecuteCallback &callback )
```

Callback-based, log-then-fail idiom; `snapshotBuilt == false` → not executable; 0-valued snapshot fields mean "query failed, skip leg" (never fail spuriously). The processor obtains the validator, calls `ExtractElmResourceRequirements` → `CheckElmResources`, and maps `executable == false` to the `error` envelope with the unmet-requirement details (D-11) — before session creation.

---

### Envelope builder (struct + serialization)

**Analog:** `ProcessingResult` construction (`mnn_llm.cpp:245-252` above) + `serialize` helpers in `ProcessingManager.cpp:2036-2102` (the `appendU32`/`appendBytes`/`appendString` lambda idiom) if a binary wire format is chosen; nlohmann JSON (already linked PUBLIC to SGProcessors) is the natural choice for a `SubTask.json_data`-compatible envelope. Internal struct shape is discretion; finish-reason mapping table (D-08..D-11) from RESEARCH is the authoritative content spec. A pure-unit TU with NO MNN include should host the RES-01 matrix tests (RESEARCH Wave 0 gap).

---

## Shared Patterns

### Gated TU / include isolation
**Source:** `src/elmruntime/ElmSmokeCheck.cpp:8-27` + `include/elmruntime/ElmSmokeCheck.hpp` (zero-MNN header)
**Apply to:** `processing_processor_elm.cpp`, both MNN fork patch guards, all new test TUs touching MNN.
Every MNN-naming symbol sits inside `#if defined( SGPROC_HAS_MNN_LLM )`; headers forward-declare `MNN::Transformer::Llm` only; a fail-closed `#else` branch keeps the no-LLM checkout building.

### Structured processor errors (never throw, never bare enums)
**Source:** `include/processors/processing_processor.hpp:25-60`
**Apply to:** every return path in the ELM processor.
```cpp
enum class ProcessingErrorStage { UNSPECIFIED = 0, ..., CANCELLED = 12, TIMED_OUT = 13, BUDGET_EXCEEDED = 14 };
struct ProcessingError { ProcessingErrorStage stage; std::string message; };
struct ProcessingResult { std::vector<uint8_t> hash; ...; std::optional<ProcessingError> error; };
```
D-11: internal errors are published terminal results (envelope `finish_reason=error` with code+message from `ElmRuntimeError`/`ProcessingErrorStage`), not thrown `ProcessingError` (re-grab-loop risk).

### PushTeardown / RunTeardown session hygiene
**Source:** `include/processors/processing_processor.hpp:101-135` (LIFO stack, noexcept-safe) + `mnn_llm.cpp:172-175`
**Apply to:** ELM processor — `PushTeardown([llm](){ MNN::Transformer::Llm::destroy( llm ); })` immediately after successful load; `RunTeardown()` on every return below that point.

### ElmRuntimeError category
**Source:** `include/elmruntime/ElmRuntimeError.hpp` (fail-closed enum + `OUTCOME_HPP_DECLARE_ERROR_2`; the `.cpp` half holds `OUTCOME_CPP_DEFINE_CATEGORY_3` — never in a multi-TU header)
**Apply to:** cache/preflight failure legs of the D-11 error envelope.

### Quicktype optional-materialization UB rule
**Source:** `ProcessingManager.cpp:636-640` comment + `ElmResourcePreflight.hpp:59-63`
**Apply to:** every read of `get_generation()`, `get_elms()`, `get_runtime()` etc.
```cpp
// Materialize the by-value optionals into named locals (UB rule).
const auto generationOpt = elm.get_generation();  // boost::optional<ElmGeneration> BY VALUE
```
Generated accessors: `Elm.hpp:68,81,88,95` (`get_generation`, `get_model_manifest_hash/uri`, `get_work_item_id`), `ElmGeneration.hpp:57-80` (`get_max_output_tokens/get_seed/get_temperature/get_top_p`, all optional).

### Trailing-slash bundle dir
**Source:** `ElmSmokeCheck.cpp:30-41` (`EnsureTrailingSlash`) + `ElmCachePin::GetDir()` contract (`ElmModelCache.hpp:57-63` — already trailing-slash terminated, "hand this string directly to createLLM")
**Apply to:** the ELM processor's createLLM argument; keep the defensive normalization only if cheap.

### end_with must be explicit
**Source:** `llm.cpp:988` — `if (!end_with) { end_with = "\n"; }` — the stop-token path writes `end_with` into the ostream (`generate.cpp:63-65`)
**Apply to:** the ELM generation call: pass `""` explicitly (Pitfall 5) so the envelope never carries a spurious model-unproduced newline.

---

## No Analog Found

| File/Element | Role | Data Flow | Reason |
|------|------|-----------|--------|
| Stop-string `std::streambuf` subclass (D-05/D-06/D-07) | utility (streaming observer) | streaming | No `std::streambuf` subclass exists anywhere in SGProcessingManager (grep: 0 hits). Implement per RESEARCH Pattern 4: accumulate decoded text in `xsputn`/`sync`, incremental overlap scan over the last `len(stop)-1 + slack` chars, on match set stop-intent flag + `llm->cancel()`. Also poll `cancelToken.IsCancelled()` in the same per-token hook (Pitfall 4 resolution). |
| `LlmLoadMutex()` itself | utility | n/a | No existing second lock — but the free-function analog in the same header is exact, so this is a copy of `VulkanInitMutex()`'s shape, not a novel pattern. |

---

## Metadata

**Analog search scope:** `SuperGenius/SGProcessingManager/{include,src,test,generated}`, `thirdparty/MNN/transformers/llm/engine`, `.planning/workstreams/elmbridge/research/` (claims cross-checked, all held)
**Files scanned:** ~25 (12 analog files read in full or targeted; grep surveys over processors/, elmruntime/, generated/, MNN llm engine/)
**Pattern extraction date:** 2026-09-11
**Key line references verified this session:** `vulkan_init_guard.hpp:18-23`; `ElmSmokeCheck.cpp:8-27,54-77`; `mnn_llm.cpp:35-77,86-93,128-262`; `mnn_llm.hpp:16-29`; `sampler.cpp:160-168`; `sampler.hpp:76`; `llm.hpp` public API + `getContext()`; `llm.cpp:85-87,101-125,988,1005-1011`; `generate.cpp:44-66`; `processors/CMakeLists.txt:24-69`; `ProcessingManager.cpp:429-481,1582-1586`; `test/elmruntime/CMakeLists.txt` (full); `test/processors/CMakeLists.txt:28-48`; `mnn_llm_test.cpp` (full); `elm_model_cache_test.cpp:1-80`; `ElmResourcePreflight.hpp` (full); `capability_validator.cpp:518-585`; `ElmModelCache.hpp:41-160`; `ElmRuntimeError.hpp` (full); `execution_context.hpp:77-175`
