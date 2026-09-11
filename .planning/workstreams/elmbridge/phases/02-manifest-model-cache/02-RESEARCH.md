# Phase 2: Manifest & Model Cache - Research

**Researched:** 2026-09-10
**Domain:** Content-addressed model cache + manifest resolution in SGProcessingManager `src/elmruntime/` (FileManager fetch, sha256 verify, atomic publish, single-flight, pin/LRU/quarantine, MNN bundle layout, loadability smoke check)
**Confidence:** HIGH (every code claim re-verified by direct inspection of the CURRENT `dev_elmruntime` working trees: SGProcessingManager @ `97bbd04`, SuperGenius @ `d459d45d8`; branches confirmed via `git branch --show-current`)

## Summary

Phase 2 is a greenfield library inside SGProcessingManager with **zero new dependencies** (workstream D-003). Every primitive it needs is verified in-tree: `FileManager` (AsyncIOManager singleton) provides all fetch I/O with a `file://` prefix that makes unit tests IPFS-free; `sgns::sgprocmanagersha::sha256` (OpenSSL EVP, one-shot) covers manifest+artifact verification because `FileManager::LoadASync` returns artifacts as **complete in-memory buffers** (no streaming — so a hash-while-download incremental helper is unnecessary for v1); `std::filesystem::rename` has an in-tree atomic-rename precedent (`GeniusNode::RotateLogFiles`); and MNN's `LlmConfig` resolves every bundle file relative to `base_dir`, so **the cache directory itself is directly loadable** by `Llm::createLLM(<cacheDir>)` — one directory serves as both cache key and runtime bundle.

Three findings materially shape the plan: **(F1)** `FileManager::getCacheDir()` returns the *bitswap* cache dir, set only when SuperGenius wires `setBitswap`/`setCacheDir` from `sgns_config.json` — it is **empty in unit tests and in any standalone process**, so D-03's fail-closed-on-empty rule is the *default* runtime state in tests and the cache root must be constructor-injectable (tests pass a temp dir; production passes `getCacheDir() + "/elmruntime"`). **(F2)** `FileManager::LoadASync` is callback-based and drained by the caller via `ioc->reset(); ioc->run();` (the exact `GetSubCidForProc`/output-save pattern) — the natural acquire path is *synchronous on the calling worker thread* with a per-acquire `io_context`, which satisfies Pitfall 14 for free; single-flight is then a `manifest-hash → shared_future` map where the second caller blocks on the first's thread. **(F3)** MNN's `LlmConfig` treats a path with no `.json`/`.mnn` suffix as a `base_dir` and then looks for `llm_config.json` inside it — meaning the manifest's artifacts must be materialized under MNN's **expected file names** (`llm_config.json`, `llm.mnn`, `llm.mnn.weight`, `tokenizer.txt`, optional `context.json`), not under their manifest `name`s, unless the manifest names are defined to *be* those keys.

**Primary recommendation:** Build `src/elmruntime/` as three hand-written components — `ElmManifest` (quicktype-generated types + parse/verify), `ElmArtifactFetcher` (injectable `std::function`-based fetch abstraction, production-backed by `FileManager::LoadASync`), and `ElmModelCache` (content-addressed store with staging/atomic-publish/pin/single-flight/quarantine/LRU + `SGPROC_HAS_MNN_LLM`-gated smoke check) — plus a new `sgprocmanagerelmruntime` CMake library and a `test/elmruntime/` suite that uses `file://` fetchers and injected temp cache roots. Wire `required_memory_bytes` into `CapabilityValidator` via a new ELM-specific check method (it currently only accepts `sgns::Pass`).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** **Size-first fast path** — on a cache hit, stat every artifact and compare against the manifest's declared `size_bytes` (instant). No sha256 re-hash on hit; content integrity is guaranteed by the publish-time gate on trusted local disk. Full re-verification deferred until the cache dir is ever shared/external
- **D-02:** **Quarantine + fail acquire on mismatch** — a size (or any verification) mismatch at reuse time renames the entry to `.bad-<hash>`, fails the acquire as a structured `RESOURCE_RESOLUTION` error, and the SAME acquire retried re-downloads cleanly. No auto-refetch inside the failing call; no outright delete
- **D-03:** **Reuse `FileManager::getCacheDir()`** — cache nests as `<cacheDir>/elmruntime/<manifest-hash>/`, consistent with the existing `results/` convention. Zero new configuration surface for the cache *location*. Fail closed if the cache dir is unset/empty — never guess a default
- **D-04:** **Fixed byte cap for eviction** — LRU eviction of unpinned entries triggers when total bytes exceed a configurable cap (sane default 10-20GB — planner picks). Manifest `size_bytes` drives the arithmetic. No free-space-threshold axis in v1.0
- **D-05:** **Quicktype regen** — the manifest shape (`schema_version`, `elm_type`, `model_format`, `quantization`, `artifacts[]` with `name`/`uri`/`sha256`/`size_bytes`, `runtime` block) joins `gnus-processing-schema.json` and regenerates into `generated/` — same pipeline, zero hand-edits (SCHEMA-01..05)
- **D-06:** **Directory-scan rebuild on restart** — LRU order and entry state reconstructed at startup by scanning `cache/<hash>/` dirs (order from directory mtimes); pin counts start at zero. No persisted index file
- **D-07:** **`.bad-<hash>` quarantine dirs kept forever** — forensic evidence; quarantine log line is the telemetry event. Ignored by cache-size accounting, never block re-download. No auto-clean in v1.0
- **D-08:** **Injectable fetch interface for tests** — `ElmArtifactFetcher` (and manifest fetch) takes an injectable fetch abstraction (function returning bytes for a URI); production wires `FileManager::LoadASync` exclusively (never raw sockets/curl); tests inject in-memory or `file://`-backed lambdas

### Carried Forward (locked by roadmap/research — not re-decided)
- Atomic publish: download to `cache/.tmp-<uuid>/` staging, verify sha256 of every artifact, same-filesystem `rename()` into place — publish-time gate is THE correctness mechanism (Pitfall 8)
- Single-flight per manifest hash: per-node map `manifest-hash → in-flight download (shared_future)`; second concurrent subtask awaits the first (SC-4)
- Smoke check gates usability: `createLLM` + `load()` + 1-token greedy generation before an entry is marked usable (Pitfall 7)
- Hashing and filesystem-heavy work runs on worker threads, never in asio handlers (Pitfall 14)
- Every new timer/callback captures `weak_from_this` (Pitfall 15.1)
- Manifest artifacts map onto MNN's expected bundle layout — the cache produces a *loadable directory*, not a file store (Pitfall 7)
- New test targets respect `SGPROC_TEST_DISCOVERY` gating and CTest `TIMEOUT` properties (Pitfall 15.2/15.3)

### Claude's Discretion
- Exact default byte cap value (10-20GB suggested) and its configuration mechanism
- The exact quicktype spelling of manifest types (record actual generated names, don't assume)
- Internal structure of the single-flight map, pin-refcount RAII handle, quarantine rename mechanics
- Precise staging-directory naming and cleanup discipline for partial downloads
- Unit-test structure/file layout under `test/elmruntime/`
- Whether the smoke check runs inside the acquire path or as a post-publish step (must complete before usable)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope. (Out-of-scope boundary from the domain section: ELM processor, session lifecycle, `VulkanInitMutex` scope fix (P3), splitter, submit wiring, E2E, temp-dir materializer deletion (P3).)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MCHE-01 | Node loads each referenced manifest, verifies its hash, fetches each artifact via `FileManager`, sha256-verifies every artifact — never executes a model whose manifest/artifacts fail verification (fail-closed, quarantined) | RQ1 (FileManager API + `file://` in tests), RQ4 (sha256 one-shot sufficient — buffers arrive whole), F3 (MNN bundle layout), F4 (atomic publish mechanics), F5 (hash normalization) |
| MCHE-02 | Bundles live in content-addressed cache at `cache/<model-manifest-hash>/`, materialized in MNN's expected on-disk layout, pin-while-processing, verify-before-reuse | F3 (cache dir = `LlmConfig.base_dir`), RQ7 (pin RAII + rename patterns), D-01 size-first fast path (entry stores its own verified manifest for reuse checks — Rec. 4) |
| MCHE-03 | Cache lifecycle robust: duplicate downloads single-flighted, partial downloads recovered, LRU eviction under disk pressure, model-load smoke check after publish | RQ2/RQ7 (single-flight via `shared_future`; no in-repo precedent in SGProcessingManager but SuperGenius precedent exists), RQ3 (CMake/test gating), F2 (smoke check mechanics + `SGPROC_HAS_MNN_LLM` gate), F6 (Windows eviction hazard) |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Manifest schema types (parse/serialize) | `generated/` (quicktype from `gnus-processing-schema.json`) | — | D-05: one schema authority; `CheckConstraint` bounds for free |
| Manifest semantic gates (non-empty artifacts, unique names, known format/quantization, MNN-layout mapping completeness) | `src/elmruntime/` hand-written C++ | — | Quicktype drops `minItems`/cross-field rules (Phase 1 Pitfall 6 — verified again) |
| Manifest + artifact fetch | `ElmArtifactFetcher` (injectable abstraction) | `FileManager::LoadASync` (production only) | D-08; issue #17 mandate |
| Hash verification | `sgprocmanagersha` (existing one-shot EVP) | — | Buffers arrive whole (F1); no incremental helper needed for v1 |
| Content-addressed store (stage/publish/pin/evict/quarantine/single-flight) | `ElmModelCache` (`src/elmruntime/`) | `std::filesystem` | New code; no in-repo cache precedent exists to reuse |
| Loadability smoke check | `ElmModelCache` publish path (gated on `SGPROC_HAS_MNN_LLM`) | MNN `Llm::createLLM/load/response` | SC-2; engine is linked into `MNN::MNN` already |
| `required_memory_bytes` preflight | `CapabilityValidator` (existing snapshot machinery) | manifest runtime block | ELM-03: local check, no advertising; validator owns resource checks today |
| Cache byte cap config | `ElmModelCache` constructor param + named constant | — | No config-file mechanism exists in SGProcessingManager (verified — see RQ8) |
| Cache root provisioning | SuperGenius node wiring (`getCacheDir` from bitswap) | `ElmModelCache` fail-closed check | D-03; root is runtime state, not library config |

## Verified Code Anchors (live `dev_elmruntime` trees)

| # | Anchor | File : line | What it proves |
|---|--------|-------------|----------------|
| A1 | `FileManager::GetInstance().getCacheDir()` precedent | `SGProcessingManager/src/processingbase/ProcessingManager.cpp:1931` | D-03's cache root; dual-save writes `file://<cacheDir>/results/...` |
| A2 | `getCacheDir()` implementation | `thirdparty/AsyncIOManager/src/FileManager.cpp:323-327`; set at `:248` from `bitswap->getCacheDir()` | Returns empty unless `setBitswap` wired a bitswap with a cache dir — **empty in unit tests/standalone** |
| A3 | Bitswap cache dir provisioning | `SuperGenius/src/account/GeniusNode.cpp:1432-1437` (`bitswap_->setCacheDir(write_base_path_ + "/" + ipfs_cache_dir_)` then `FileManager::setBitswap`); `sgns_config.json` `ipfs_cache_dir` at `GeniusNode.cpp:443-446`; example value `"ipfs_cache"` at `SuperGenius/example/node_test/sgns_config.json:17` | Production cache root = `<write_base>/ipfs_cache`; cache nests as `.../ipfs_cache/elmruntime/<hash>/` |
| A4 | `LoadASync` signature | `thirdparty/AsyncIOManager/include/FileManager.hpp:97-104`; impl `src/FileManager.cpp:43-110` | `(url, parse, save, ioc, FinalCallback, savetype)` → throws `range_error` for unregistered prefix; callback delivers `ResultType` |
| A5 | `ResultType` shape | `FileManager.hpp:64-65` | `outcome::result<shared_ptr<pair<vector<string>, vector<vector<char>>>>>` — whole file(s) in memory |
| A6 | `SaveASync` signature | `FileManager.hpp:113-119`; local-save usage `ProcessingManager.cpp:1920-1943` | `(url, ResultType data, ioc, FinalCallback, save_location)` — the dual-save shows the exact production write pattern |
| A7 | The temp-dir materializer being replaced | `SGProcessingManager/src/processors/processing_processor_mnn_llm.cpp:27-63` (`MaterializeModelToTempDir`), `:86-93` (`VulkanInitMutex` held across `createLLM`+`load`) | `fs::temp_directory_path()`, timestamp-named, never cleaned; trailing-slash normalization of the dir string before `createLLM` |
| A8 | MNN bundle layout resolution | `thirdparty/MNN/transformers/llm/engine/src/llmconfig.hpp:64-160` | Path without `.json`/`.mnn` suffix → `base_dir_ = path`; files resolved as `base_dir + config.value("llm_config","llm_config.json")`, `"llm.mnn"`, `"llm.mnn.weight"`, `"tokenizer_file"→"tokenizer.txt"`, `"context_file"→"context.json"` |
| A9 | `Llm::load()` file checks | `thirdparty/MNN/transformers/llm/engine/src/llm.cpp:265-283` | Fails if tokenizer/model/weight files missing — `llm.mnn.weight` is checked even when weights are embedded (see Risk R5) |
| A10 | `createLLM` / `destroy` / `response` | `thirdparty/MNN/transformers/llm/engine/include/llm/llm.hpp:134-158` | Public session API; `response(user_content, os, end_with, max_new_tokens)` |
| A11 | sha256 utility | `SGProcessingManager/include/util/sha256.hpp:8`; `src/util/sha256.cpp` (EVP one-shot) | `std::vector<uint8_t> sha256(const void*, size_t)` — only API; linked via `sgprocmanagersha` (`src/util/CMakeLists.txt:23-35`) |
| A12 | sha256 usage precedent | `processing_processor_mnn_llm.cpp:222` (`sgprocmanagersha::sha256(outputText.c_str(), size)`) | Same helper hashes results today |
| A13 | Quicktype regen command | `SGProcessingManager/README.md:22-38`; `.github/workflows/generate-headers.yml:29-43` (CI fires **only on `main`** → local regen on `dev_elmruntime`) | Exact flags; quicktype 23.2.6 + node 24.16.0 verified installed (Phase 1 research, same machine) |
| A14 | Phase 1 generated ELM types | `generated/Elm.hpp:60-99` (`get_model_manifest_uri()`/`get_model_manifest_hash()`), `generated/Validation.hpp:22` (enum named from property — the naming lesson), `generated/Generators.hpp:229-246` (`from_json(Elm&)` requires all five fields) | The fields this phase consumes; quicktype naming/bounds realities |
| A15 | CapabilityValidator machinery | `include/capability/capability_validator.hpp:59-92`; `src/capability/capability_validator.cpp:273-355` (BuildSnapshot: Vulkan props, memProps, `QueryAvailableDiskBytes`), `:357-490` (CanExecute: 5 check categories) | Snapshot has Vulkan heaps + disk bytes; **no host-RAM field**; `CanExecute` accepts only `sgns::Pass` |
| A16 | Capability test injection | `src/capability/CMakeLists.txt:16` (`SGPROCMGR_TEST_FRIEND` PUBLIC); `test/capability/capability_validator_test.cpp:99,163,194` (`SetSnapshotForTest`) | The pattern the memory-preflight test copies |
| A17 | Test gating pattern | `test/processingbase/CMakeLists.txt:14-19`; `cmake/CommonBuildParameters.cmake:33-43` (`SGPROC_TEST_DISCOVERY` defined only by the standalone build) | Unconditional `add_test` + gated `gtest_discover_tests(... DISCOVERY_TIMEOUT 60)` — the exact Phase 1 pattern to copy |
| A18 | `SGPROC_HAS_MNN_LLM` gate | `src/processors/CMakeLists.txt:30-56` (configure-time `EXISTS "${MNN_INCLUDE_DIR}/llm/llm.hpp"` → `CACHE INTERNAL`), consumed by tests at `test/processors/CMakeLists.txt:28-48` | The gate the smoke-check component rides; **currently TRUE on this Windows checkout** (build logs show `/D SGPROC_HAS_MNN_LLM`) |
| A19 | Atomic rename precedent | `SuperGenius/src/account/GeniusNode.cpp:3336-3360` (`RotateLogFiles`: remove-then-rename under try/catch) | In-tree `std::filesystem::rename` discipline; **no rename usage anywhere in SGProcessingManager** (verified — this is new code) |
| A20 | ioc drain pattern | `ProcessingManager.cpp:1948-1949`, `:2167-2168` (`ioc->reset(); ioc->run();` after queueing async IO) | How fetch completions are awaited synchronously on the calling thread |
| A21 | Per-subtask worker thread | `SuperGenius/src/processing/processing_engine.cpp:100-159` (detached `std::thread` per subtask) | The cache's `Acquire` runs on this thread — hashing/fs work is off-asio by construction |
| A22 | weak_from_this discipline | `SuperGenius/src/processing/processing_service.cpp:136,160` etc.; **zero occurrences in SGProcessingManager** (verified grep) | New elmruntime classes with posted callbacks must add `enable_shared_from_this` themselves |
| A23 | shared_future precedent | `SuperGenius/src/account/AccountMessenger.hpp:234-236`, `processing_subtask_queue_channel_pubsub.cpp:22-62` | `std::shared_future` is an established codebase tool (for gossip futures); none in SGProcessingManager yet |
| A24 | UUID generation | `SuperGenius/src/processing/processing_tasksplit.cpp:37-41` (`boost::uuids::basic_random_generator<std::mt19937>`) | Pattern for staging-dir names (boost::uuids available via existing includes; SGProcessingManager links Boost) |
| A25 | ProcessingErrorStage surface | `processing_processor_mnn_llm.cpp:135,160,180,192` (`ProcessingErrorStage::RESOURCE_RESOLUTION`, `CANCELLED`, `BUDGET_EXCEEDED`) | D-02's "structured `RESOURCE_RESOLUTION` error" maps onto the existing enum |
| A26 | Error enum headroom | `include/processingbase/ProcessingManager.hpp:82-104` (ends at `ELM_GENERATION_SETTINGS_INVALID = 18`) | If elmruntime reuses ProcessingManager::Error it extends from 19 — but see Rec. 2 (own category preferred) |
| A27 | Root schema ELM block | `gnus-processing-schema.json:64-87` (`job_type`, `elms[]`, `funding`, `validation` as root properties) + `definitions.Elm/ElmGeneration/ElmFunding:117-175` | Where the manifest definitions join (D-05) — and the reachability question (Risk R1) |
| A28 | MNN LLM engine linked into `MNN::MNN` | (workstream STACK.md, verified 2026-09-09; unchanged — `SGProcessors` links `MNN::MNN` at `src/processors/CMakeLists.txt:114`) | Smoke check needs no new link dependency beyond `MNN::MNN` + `Vulkan::Vulkan` context |

## Research Question Answers

### RQ1 — FileManager API surface

**Signatures (verified, `thirdparty/AsyncIOManager/include/FileManager.hpp`):**

```cpp
shared_ptr<void> LoadASync( const std::string& url, bool parse, bool save,
                            std::shared_ptr<boost::asio::io_context> ioc,
                            FinalCallback finalcall, std::string savetype );       // :97-104
void SaveASync( const std::string& url, ResultType data,
                std::shared_ptr<boost::asio::io_context> ioc,
                FinalCallback finalcall,
                std::shared_ptr<std::string> save_location = nullptr );           // :113-119
std::string getCacheDir() const;                                                  // :163-165
using ResultType = outcome::result<std::shared_ptr<std::pair<
    std::vector<std::string>, std::vector<std::vector<char>>>>>;                   // :64-65
using FinalCallback = std::function<void( ResultType buffers )>;                   // :74
```

**Behavior (verified, `src/FileManager.cpp`):**
- `LoadASync` splits the URL via `getURLComponents`, dispatches on prefix, **throws `std::range_error` for an unregistered prefix** (`:57-60`) — the fetch abstraction must catch this and convert to a structured error, never let it cross the acquire boundary.
- Registered loaders after `InitializeSingletons()` (`FileManager.cpp:30-41`, each `*Loader.cpp` constructor): **`file`** (MNNLoader — plain local-file reads), **`https`** (HTTPLoader — note: plain `http` is commented out), **`ipfs`** (IPFSLoader — uses external bitswap when wired), `wss`, `sftp`. Savers: `file`/`mnn` (MNNSaver), `ipfs` (IPFSSaver), `sftp`.
- The callback fires exactly once with success or `outcome::failure` (e.g. `FILE_OPEN_FAIL`, `READ_ERROR` for `file://`; `BAD_CID`/`CANNOT_LISTEN`/`INVALID_URL` for ipfs). `MNNLoader::LoadASync` reads the **entire file into a streambuf** and delivers it whole (`MNNLoader.cpp:82-104`).
- **Drain pattern:** queue `LoadASync` calls, then `ioc->reset(); ioc->run();` on the calling thread — exactly `GetSubCidForProc`'s caller (`ProcessingManager.cpp:2167-2168`) and the output-save loop (`:1948-1949`). The run() returns when `DecrementOutstandingOperations` stops the context.
- **Threading:** completions arrive on the ioc thread *you run* — if the cache runs its own io_context on the acquire (worker) thread and calls `ioc->run()` itself, the "handler" and the worker are the same thread and Pitfall 14 is satisfied structurally. This is the recommended shape (Rec. 3).
- **getCacheDir semantics:** returns `cacheDir_`, set ONLY by `setBitswap` (`FileManager.cpp:248`) from `bitswap->getCacheDir()`; cleared by `clearBitswap` (`:319`). GeniusNode sets it in `InitContentExchange` (`GeniusNode.cpp:1432-1437`). **In unit tests or any standalone SGProcessingManager process it is `""`** — D-03's fail-closed rule is the natural test default, and the positive-path tests must inject a root dir.

**Production wiring (D-08):** one TU implements the fetch interface as: `FileManager::GetInstance().InitializeSingletons()` (idempotent), build a fresh `io_context`, capture a `promise`/flag, call `LoadASync(url, /*parse=*/false, /*save=*/false, ioc, cb, "file")`, run/drain, return bytes or error. `parse=false, save=false` — the cache does its own writing.

### RQ2 — MNN LLM bundle layout; cache dir as base_dir

**Confirmed: the cache directory serves directly as `LlmConfig.base_dir`.** `LlmConfig(const std::string& path)` (`llmconfig.hpp:64-108`): a path with no `.json` suffix and no `.mnn` suffix → `config_ = {}`, `base_dir_ = path`. It then opens `base_dir + config.value("llm_config", "llm_config.json")` and merges it. All bundle files resolve as `base_dir_ + key`:

| Config key (llm_config.json) | Default filename | Set by |
|------------------------------|------------------|--------|
| `llm_config` | `llm_config.json` | `llmconfig.hpp:110-113` |
| `llm_model` | `llm.mnn` | `:115-118` |
| `llm_weight` | `llm.mnn.weight` | `:120-123` |
| `tokenizer_file` | `tokenizer.txt` | `:146-149` |
| `context_file` | `context.json` (chat-template context, optional) | `:153-156` |

`Llm::load()` (`llm.cpp:265-283`) hard-fails if `tokenizer.txt`, `llm.mnn`, and `llm.mnn.weight` are not all present and openable — **the smoke check inherits this fail-closed behavior for free**. Two consequences for the manifest→layout mapping:
1. The manifest's `artifacts[]` must either use MNN's key names as `name`s, or carry an explicit mapping (e.g., artifact `name` = the *role*: `llm_config`/`llm_model`/`llm_weight`/`tokenizer_file`/`context_file`, materialized at the default filename). Recommend roles-with-default-filenames (Rec. 5) — simplest, and the generated manifest types stay stable if MNN adds keys.
2. The existing materializer appends a trailing `/` to the dir string before `createLLM` (`processing_processor_mnn_llm.cpp:59-63`) — because `base_dir_` is used verbatim as a path prefix on Windows too (`base_dir()` in `llmconfig.hpp:30-37` keeps the separator; but the *no-suffix* branch assigns the raw string). **Always pass a trailing-slash-terminated absolute path.**

### RQ3 — CMake structure for `src/elmruntime/` + tests

**Library:** `src/CMakeLists.txt:1-8` currently `add_subdirectory`s `util, datasplitter, processors, processingbase, shaders, capability, execution, artifacts`. Add `elmruntime`. New `src/elmruntime/CMakeLists.txt` mirrors `src/capability/CMakeLists.txt` (smallest precedent, `src/capability/CMakeLists.txt:8-36`):

```cmake
add_library(sgprocmanagerelmruntime STATIC <sources> <headers>)
target_include_directories(sgprocmanagerelmruntime PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/../../include>
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/../../generated>
    $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/SGProcessingManager/generated>
    $<BUILD_INTERFACE:${Boost_INCLUDE_DIRS}>
    $<BUILD_INTERFACE:${OPENSSL_INCLUDE_DIR}>)
target_link_libraries(sgprocmanagerelmruntime PUBLIC
    sgprocmanagerlogger sgprocmanagersha nlohmann_json::nlohmann_json spdlog::spdlog)
sgnus_install(sgprocmanagerelmruntime)
```

Decisions embedded there: (a) link `sgprocmanagersha` (sha256), NOT `AsyncIOManager` — the fetch is behind D-08's injectable interface, so only the one production-wiring TU needs FileManager, and that TU can live in `ProcessingBase` (which already links `AsyncIOManager`, `src/processingbase/CMakeLists.txt:26`) or elmruntime links `AsyncIOManager` PRIVATE for that TU (it resolves via `cmake/CommonBuildParameters.cmake:318-321`); (b) the smoke-check TU additionally needs `MNN::MNN` + `Vulkan::Vulkan` and should compile only when `SGPROC_HAS_MNN_LLM` (CACHE INTERNAL — readable from a sibling directory, exactly as `test/processors/CMakeLists.txt` reads it); the gate is set in `src/processors/CMakeLists.txt:30-56`, **before** `src/CMakeLists.txt` reaches `elmruntime` only if the subdirectory order keeps `processors` first — it does (`src/CMakeLists.txt:3`), but safer: move the `EXISTS` detection up or duplicate it (flag for planner; a duplicated 4-line check is harmless).

**Tests:** new `test/elmruntime/` + one line in `test/CMakeLists.txt`. Copy the Phase 1 gating pattern verbatim (`test/processingbase/CMakeLists.txt:14-19`):

```cmake
add_executable(sgprocelmruntime_cache_test elm_model_cache_test.cpp)
target_link_libraries(sgprocelmruntime_cache_test PRIVATE GTest::gtest_main sgprocmanagerelmruntime)
add_test(NAME sgprocelmruntime_cache_test COMMAND sgprocelmruntime_cache_test)
if(SGPROC_TEST_DISCOVERY AND NOT CMAKE_CROSSCOMPILING)
    gtest_discover_tests(sgprocelmruntime_cache_test DISCOVERY_TIMEOUT 60)
endif()
```

CTest `TIMEOUT` properties: the workstream pitfall 15.2 asks for them on new long tests; the smoke-check tests are the only long ones (real model load) — but v1 unit tests should NOT load a real 300MB model (no fixture exists in-repo — see Open Question Q2), so timeouts likely unneeded; add `set_tests_properties(... TIMEOUT 120)` on any test that does touch MNN.

### RQ4 — sha256 API; what hash-while-download needs

**Exact API (`include/util/sha256.hpp:8`):** one function — `std::vector<uint8_t> sha256(const void* data, size_t dataSize)`. One-shot over a full buffer (EVP_MD_CTX new → Init → Update → Final → free, `src/util/sha256.cpp`). Nothing incremental exists.

**Hash-while-download helper: NOT needed for v1.** `FileManager::LoadASync` delivers each artifact as a complete in-memory buffer (`ResultType` carries `vector<vector<char>>`; `MNNLoader` reads the whole file; IPFS blocks assemble before delivery). There is no streaming boundary at which to hash incrementally. The acquire pipeline is therefore: **fetch (whole buffer, ~300-500MB resident — same memory profile the existing single-buffer path already has) → one-shot `sha256(buffer)` → verify → write verified bytes to staging file → fsync-ish close → rename**. This avoids STACK.md's optional 30-line EVP incremental helper entirely; add it only if a future streaming fetch lands. (Hex encoding for comparison/logging: no in-repo helper in SGProcessingManager — `DeriveExecutorId` in `capability_validator.cpp:168-178` does manual `%02x` formatting; copy that pattern.)

### RQ5 — Quicktype manifest regen: command, pipeline, naming conventions

**Command (README.md:22-38 — run locally on `dev_elmruntime`; CI auto-PR fires only on `main`):**

```bash
quicktype --src-lang schema --lang cpp --top-level SGNSProcessing \
  --code-format with-getter-setter --const-style west-const \
  --namespace sgns --type-style pascal-case --member-style underscore-case \
  --boost --source-style multi-source --include-location global-include \
  --out generated/SGNSProcMain.hpp gnus-processing-schema.json
```

Toolchain verified installed on this machine (Phase 1 research, 2026-09-09): quicktype 23.2.6, node 24.16.0.

**Naming conventions OBSERVED in Phase 1 (binds this phase — record actuals at regen, never assume):**
- Enums are named from the **property**, not the semantic: `validation` → `sgns::Validation` (NOT `ElmValidationMode`); `elm_type` → `sgns::ElmType::CAUSAL_LM` (single-member enum from a 1-value schema enum, `generated/ElmType.hpp:22`).
- Optional number/integer bounds are **dropped** (`boost::none` everywhere in `ElmGeneration`); only `pattern`/`minLength` on strings and bounds on *required* fields survive. All manifest numeric validation (e.g., `size_bytes ≥ 0`) must be C++ gates.
- `minItems`/`uniqueItems`/cross-field rules: never generated. Non-empty `artifacts[]`, unique artifact names, "artifact set covers MNN's required keys" = C++ gates (the `CheckElmValidity` pattern, `ProcessingManager.cpp:630-763`).
- Getters return `boost::optional<T>` **by value** — materialize into named locals before dereferencing (Phase 1's UB lesson, documented at `ProcessingManager.cpp:636-641`).
- Manifest type names will follow the schema definition names: e.g. definitions `ElmModelManifest`/`ElmModelArtifact`/`ElmModelRuntime` → `sgns::ElmModelManifest` etc. **Verify actual spellings after regen** (discretion).

**⚠ Reachability risk (R1):** Phase 1's generated types were all reachable from root properties (`elms[]` → `Elm` → ...). The manifest is fetched at runtime, not part of `Task.json_data` — if its definitions hang unreferenced in `definitions`, quicktype may not emit them. Verify at regen time; if dropped, options: (a) reference them from an optional root property (pollutes the job schema), or (b) run the same quicktype command a second time against a small `elm-model-manifest-schema.json` with `--top-level ElmModelManifest` into `generated/` (still zero hand-edits, same pipeline — arguably cleaner authority separation). Recommend trying (a-in-schema-only) first to honor D-05's letter, with (b) as the sanctioned fallback.

### RQ6 — CapabilityValidator: surfacing `required_memory_bytes`

**Current shape:** `CapabilityValidator::CanExecute(const sgns::Pass&, CanExecuteCallback)` (`capability_validator.hpp:88-92`) — pass-shaped. ELM jobs have no passes, so the preflight needs a **new entry point**, not an extension of `CanExecute`. The snapshot (`capability_types.hpp:55-62`) has: Vulkan `memProps` (heaps incl. DEVICE_LOCAL sizes), `availableDiskBytes`, executor caps, identity hash — **no host-RAM field**.

**Recommended:** add `void CheckElmResources(const ElmModelManifest&, uint64_t totalArtifactBytes, CanExecuteCallback)` (or return-style) performing:
1. **Disk:** `totalArtifactBytes` (sum of manifest `size_bytes`) + working margin vs `snapshot.availableDiskBytes` — mirrors the existing Step-4 disk check (`capability_validator.cpp:453-471`; `availableDiskBytes == 0` means query-failed/degraded → skip, same as today).
2. **Memory:** `runtime.required_memory_bytes` vs the largest DEVICE_LOCAL heap when the model targets a GPU backend, vs a new host-RAM figure for CPU backend. Since the snapshot lacks host RAM, v1 options: (i) compare against largest Vulkan heap always (conservative; wrong for pure-CPU models), (ii) add a host-RAM query to `BuildSnapshot` (platform call — `GlobalMemoryStatusEx`/`sysconf(_SC_PHYS_PAGES)`; ~15 lines beside `QueryAvailableDiskBytes` at `capability_validator.cpp:95-113`), (iii) v1 checks disk only and treats `required_memory_bytes` as advisory logging. **Recommend (ii)** — the manifest field exists precisely to prevent loading 700MB onto a device that can't hold it (Pitfall 13), and the field is worthless unchecked. Planner confirms.
3. Unmet → `UnmetRequirement{RESOURCE, "required_memory_bytes X exceeds ..."}` — same category/detail idiom as existing checks; `SGPROCMGR_TEST_FRIEND`/`SetSnapshotForTest` (A16) makes it unit-testable with mock snapshots, no GPU.

Note the `elmruntime` library should NOT link `SGCapability` (keep it dependency-free); the natural home for the call is wherever the acquire path integrates with ProcessingManager (Phase 3 wiring), or `CheckElmResources` lives on the validator and the cache exposes manifest accessors. Keep the cache library pure.

### RQ7 — Existing patterns: atomic rename, single-flight, weak_from_this

**Atomic rename (same filesystem):**
- `std::filesystem::rename(old, new)`: POSIX = atomic replace-even-if-exists; **Windows (MSVC) fails if the target exists**. In-tree precedent handles it by remove-first (`GeniusNode::RotateLogFiles`, A19). For cache publish the target `<hash>/` should never exist (single-flight guarantees one publisher; a leftover from a crashed prior run is removed before publish starts — D-02 quarantine handles the verified-bad case, crash-orphan staging cleanup handles the rest). Belt-and-braces: `std::error_code` overloads + if target exists → quarantine it, then rename.
- **Windows directory-rename caveat:** `fs::rename` on a *directory* works within the same volume; both staging (`.tmp-<uuid>/`) and final (`<hash>/`) live under `<cacheDir>/elmruntime/` → same volume by construction. Use the `std::error_code` overloads everywhere (the materializer's silent-`ec` style is the precedent; prefer logging failures).
- Durability: after writing artifacts, close streams and (optionally) flush; full fsync is not required for the correctness argument (verification is hash-based at publish; a torn post-rename entry fails D-01's size check → quarantine).

**Single-flight (no precedent in SGProcessingManager; SuperGenius precedent is gossip-futures):**
- Map `std::unordered_map<std::string, std::shared_future<AcquireResult>>` guarded by one mutex (the map itself is the only shared mutable state; downloads run on caller threads). First caller: insert a `shared_future` from a `std::promise` *before* starting the fetch, run fetch+verify+publish on its own thread, fulfill the promise, erase the map entry (under mutex) on completion. Second caller: finds the future, `.wait()`s, reads the result — both then pin the same entry (SC-4: both pin and load the same cache entry). Exceptions: never throw through the future — encode failures in `AcquireResult` (outcome-style) so the awaiting caller gets the same structured `RESOURCE_RESOLUTION` error.
- Promise/future + `enable_shared_from_this`: if any callback captures `this` (fetch completion posted to an ioc), the cache object must outlive it — but with the synchronous drain shape (RQ1) no callback outlives the call, so `weak_from_this` is a *defensive* discipline (roadmap requires it for every new timer/callback — state that the synchronous design has no cross-thread callbacks in v1; any future async timer, e.g. idle-eviction sweep, must capture `weak_from_this` per `processing_service.cpp:136`).

**Pin-refcount RAII:**
- `Acquire` returns an `ElmCachePin` (move-only RAII: entry path + hash + `shared_ptr` back-reference or raw cache* + destructor decrementing the refcount under mutex; also update entry's LRU timestamp on release). Every terminal path (success, structured error, exception between pin and return) runs the destructor — this is the "deterministic unpin on every terminal path incl. cancellation" requirement. Test: pinned entry survives an eviction pass; refcount returns to zero after cancel.

**LRU (D-06):** startup scan of `<cacheRoot>/` for entries; order by `fs::last_write_time(entryDir)`; entry byte-size = **sum of manifest `size_bytes`** (requires the verified manifest to be readable per entry — see Rec. 4). Eviction pass after each publish and on startup: while `total > cap`, evict oldest unpinned via `fs::remove_all` (worker thread, never asio — Pitfall 14). `.bad-*` and `.tmp-*` are excluded from accounting; `.tmp-*` orphans from crashed runs are swept at startup (worker thread).

### RQ8 — Config surface for the byte cap

**Verified: SGProcessingManager has NO runtime config-file or env-var mechanism** (grep across `src/` finds none; yaml-cpp is linked only via `ProcessingBase`'s transitive include dirs, and no `yaml::` usage exists in the submodule's own sources). The only precedent for tunables is CMake options (`SGPROC_TEST_DISCOVERY`) — a build-time knob, wrong shape for a runtime byte cap.

**Recommendation:** constructor parameter with a named-constant default, e.g. `inline constexpr uint64_t kDefaultElmCacheByteCap = 15ULL * 1024 * 1024 * 1024;` (mid-range of D-04's 10-20GB; a 0.5B model ≈ 300-500MB → ~30-50 entries), plus a `SetByteCap()` no-op-if-lower-than-current-usage (next eviction pass trims). Production wiring passes nothing (default); tests pass small caps to exercise eviction without gigabytes. Zero new configuration surface — consistent with D-03's philosophy for the location. If the owner later wants operator control, the SuperGenius `sgns_config.json` reader (`GeniusNode.cpp:296+`, the `ipfs_cache_dir` pattern at `:443-446`) is the natural Phase 4 wiring point — out of scope now.

## Recommended Implementation Approach

*(How to implement the locked decisions — not re-deciding them.)*

1. **Three hand-written components under `src/elmruntime/` + `include/elmruntime/`** (PascalCase headers per conventions):
   - `ElmManifest` — parse via generated types; verify manifest bytes against the work item's `model_manifest_hash` (normalized — see F5); semantic gates (non-empty artifacts, unique roles/names, required MNN roles present, size_bytes ≥ 0, uri non-empty). Own small error category (Rec. 2).
   - `ElmArtifactFetcher` — `using FetchFn = std::function<outcome::result<std::vector<uint8_t>>(const std::string& uri)>;` (or a tiny interface struct). Production impl wraps `FileManager::LoadASync` with the drain pattern (RQ1); tests inject in-memory lambdas or `file://` via the real FileManager against fixture files (`file` prefix is registered by `InitializeSingletons` — works with zero network).
   - `ElmModelCache` — the store (constructor: root dir, FetchFn, byte cap; `enable_shared_from_this`). API shape: `Acquire(manifestUri, manifestHash) → outcome::result<ElmCachePin>`; internal states per entry: `Downloading (single-flight) / Published+Unverified / Usable`; only post-smoke-check entries are Acquire-able hits.
2. **Own outcome error category for elmruntime** (e.g. `ElmRuntimeError { MANIFEST_FETCH_FAILED, MANIFEST_HASH_MISMATCH, ARTIFACT_FETCH_FAILED, ARTIFACT_HASH_MISMATCH, ARTIFACT_SIZE_MISMATCH, CACHE_DIR_UNSET, SMOKE_CHECK_FAILED, ... }`) following the `OUTCOME_CPP_DEFINE_CATEGORY` pattern (`ProcessingManager.cpp:8-45`). Map to `ProcessingErrorStage::RESOURCE_RESOLUTION` at the (Phase 3) processor boundary — D-02's structured-error language. Do NOT extend `ProcessingManager::Error` (keeps elmruntime standalone, avoids recompiling the world; enum currently ends at 18, A26).
3. **Synchronous acquire on the caller's (worker) thread with a per-acquire `boost::asio::io_context`** — the `GetSubCidForProc`/output-save drain pattern (A20). All hashing, staging writes, rename, and (if on this thread) the smoke check run on the subtask thread `ProcessingEngine` spawned (A21) — Pitfall 14 satisfied structurally; the only asio work is the fetch itself, which is I/O, not hashing.
4. **Entry layout — store the verified manifest inside the entry:**
   ```
   <cacheRoot>/elmruntime/
     ├── <manifest-hash-hex>/          # published entry; doubles as LlmConfig base_dir
     │   ├── elm_manifest.json         # copy of the hash-verified manifest bytes (reuse-time D-01 size table; D-06 restart accounting; NOT read by MNN — extra files are ignored)
     │   ├── llm_config.json           # MNN role: llm_config
     │   ├── llm.mnn                   # llm_model
     │   ├── llm.mnn.weight            # llm_weight
     │   ├── tokenizer.txt             # tokenizer_file
     │   └── [context.json]            # optional context_file
     ├── .tmp-<uuid>/                  # staging (never loaded; swept at startup)
     └── .bad-<hash>/                  # quarantine (kept forever; excluded from accounting)
   ```
   The manifest copy is the key enabler for D-01 (size-check-on-hit needs the declared sizes without a re-fetch) and D-06 (restart rebuild needs per-entry byte totals). MNN ignores extra files in base_dir (it opens only its named keys — A9).
5. **Manifest→MNN mapping:** manifest `artifacts[].name` ∈ a closed role enum (`llm_config`, `llm_model`, `llm_weight`, `tokenizer_file`, `context_file`, future `visual_model` etc.); each role materializes at MNN's default filename (RQ2 table). Required roles for v1: `llm_config`, `llm_model`, `tokenizer_file`; `llm_weight` required iff the model uses an external weight file — **make the C++ gate require llm_weight unless `llm_config.json` declares none** … simpler and fail-closed: require all four and let manifest authors ship an empty/embedded-weight bundle accordingly (MNN's own `load()` checks all three files anyway, A9 — see Risk R5 for the embedded-weights edge).
6. **Publish path (cache miss):** single-flight insert → create `.tmp-<uuid>/` → fetch manifest bytes → verify vs `model_manifest_hash` → parse+gates → per artifact: fetch (whole buffer) → one-shot sha256 verify → write to staging at its role filename → write `elm_manifest.json` → smoke check (below) → `fs::rename` staging → `<hash>/` (remove/quarantine pre-existing target first — Windows) → mark Usable → eviction pass → fulfill future. Any failure: `remove_all` staging (or quarantine if the failure is a *verification* failure at a would-be-final path — staging failures are just cleaned; D-02 quarantine applies to entries that fail **reuse-time** verification, and to publish-time verification failures the planner may treat either way — staging-level verify failures never reach a final path, so cleanup suffices; keep quarantine for reuse-mismatch per D-02's letter).
7. **Hit path (D-01/D-02):** dir exists & marked Usable → read `elm_manifest.json` → stat each artifact → sizes match → touch mtime (LRU) → pin → return. Any mismatch (or unreadable manifest) → `rename` entry → `.bad-<hash>` (log the telemetry line, D-07) → return structured `RESOURCE_RESOLUTION`-mapping error. **No auto-refetch in the failing call** — the caller retries and the next acquire sees no entry → clean re-download (D-02).
8. **Smoke check (SC-2), gated `SGPROC_HAS_MNN_LLM`:** in the publish path before the rename (discretion says placement is free; pre-rename means a failed check never leaves a final-path entry — but the check must load from a *directory path*, and staging IS one: run it against the staging dir, then rename — one load per publish, zero garbage): trailing-slash dir string → `VulkanInitMutex` lock_guard → `Llm::createLLM(dir)` → `load()` → `set_config(R"({"sampler_type":"greedy","max_new_tokens":1})")` (greedy = deterministic check, no RNG) → `response("<smoke prompt>", &oss, nullptr, 1)` → non-empty status/text → `Llm::destroy`. Wrap MNN headers in ONE TU behind the gate (mirror `processing_processor_mnn_llm.cpp`'s include isolation, `include/processors/processing_processor_mnn_llm.hpp:16-29` forward-declares Llm so consumers need no MNN headers). The mutex hold is once per entry — Pitfall 5's "load-once-per-entry bounds its damage" is exactly this.
9. **Tests (`test/elmruntime/`, all gated per RQ3; no IPFS, no real model):** manifest parse/verify matrix (tampered manifest, bad hash format, missing roles, dup roles, size<0); publish flow with in-memory fetcher (happy path → entry at final path with expected layout); artifact-hash mismatch → refusal + no final-path entry; reuse: size tamper → quarantine + structured error; retry → clean re-download (SC-3); single-flight: two threads, one fetcher-call count, both pins valid (SC-4); pin: pinned entry survives eviction pressure, unpinned evicts LRU under a tiny injected cap (SC-5); partial-download recovery: pre-created `.tmp-` orphan swept at startup, acquire proceeds (SC-5); `%TEMP%` cleanliness: cache writes only under injected root (SC-5 — the *old* materializer is P3's to delete); quarantine: `.bad-` excluded from accounting, never loaded; restart rebuild: pre-populated dirs re-scanned, mtime-ordered (D-06). Smoke-check unit tests without a real model: assert the *gating and failure paths* only (a garbage staging dir → SMOKE_CHECK_FAILED structured error, `createLLM` on a dir with no `llm_config.json` fails inside `load()`) — a real Qwen-0.5B fixture is Phase 4's E2E (see Q2).
10. **`required_memory_bytes`:** implement `CheckElmResources` on CapabilityValidator (RQ6, option ii) + host-RAM snapshot field + mock-snapshot tests (A16 pattern). The elmruntime library itself only *exposes* the runtime block from the manifest; the check call-site lands where the processor integrates (Phase 3) — ship the validator half now (MCHE preflight requirement), wire the call in P3/P4.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Artifact/manifest fetching | Raw sockets, curl, cpp-httplib, MNN's `remote_model_downloader` | `FileManager::LoadASync` behind D-08's injectable fn | Issue #17 mandate; MNN's downloader bypasses billable/hash-verified path and drags httplib (STACK.md "What NOT to Use") |
| sha256 | New hash code or a second crypto dep | `sgns::sgprocmanagersha::sha256` | Already linked (`sgprocmanagersha` target); same EVP used everywhere |
| Incremental streaming hash | EVP_Update wrapper now | One-shot over the fetched buffer | Buffers arrive whole (RQ4) — the helper solves a problem v1 doesn't have |
| Manifest JSON types | Hand-written parse structs | Quicktype regen (D-05) | SCHEMA-01..05; constraints/patterns free; Phase 1 pipeline proven |
| Staging-dir uniqueness | Timestamps (the materializer's collision-prone idiom, A7) | UUID via `boost::uuids` (A24) or `std::random_device` hex | Pitfall 6's concurrency-collision note |
| Byte-cap arithmetic | float GB math | `uint64_t` bytes throughout | Trivial and exact; manifest `size_bytes` are integers |
| Worker-thread dispatch | A new thread pool in elmruntime | Run on the caller's thread (A21) | The acquire is called from `ProcessingEngine`'s per-subtask thread; adding threads adds teardown hazards (Pitfall 15.2) |

## Common Pitfalls (phase-specific, beyond the workstream catalog)

### Pitfall P2-1: assuming `getCacheDir()` is ever non-empty in tests
**What goes wrong:** cache code reads `FileManager::getCacheDir()` directly; every unit test gets `""` → fail-closed fires → tests can't exercise anything. **Avoid:** root is a constructor param (tests inject); only the production wiring reads `getCacheDir()` and fails closed on empty (D-03).

### Pitfall P2-2: Windows `rename` onto an existing directory
**What goes wrong:** POSIX habits — `fs::rename(staging, final)` throws when `final` exists on MSVC. **Avoid:** remove-or-quarantine the target first (A19 pattern); use `std::error_code` overloads; same-volume guarantee by keeping staging beside the final path.

### Pitfall P2-3: Windows locked files during eviction
**What goes wrong:** `remove_all` on an entry whose weight file MNN still has mapped/open fails on Windows (POSIX unlink-while-open succeeds). Pins prevent in-use eviction, but a *recently*-released entry can still be locked briefly. **Avoid:** tolerate per-entry eviction failure (log, skip, retry next pass) — never let eviction errors fail the acquire.

### Pitfall P2-4: manifest-hash string used directly as a directory name
**What goes wrong:** `model_manifest_hash` is schema-wise any non-empty string (Phase 1 test fixtures use `"sha256:abc"`); interpolating it into paths is the path-traversal hazard the security table names. **Avoid:** the cache computes sha256 of the fetched manifest bytes itself and uses the 64-hex digest as the dir name; the *declared* hash is only ever compared (after normalization, F5) — never used as a path component.

### Pitfall P2-5: smoke check loads from a path without a trailing separator
`LlmConfig` uses the passed string verbatim as a prefix (RQ2) — copy the materializer's trailing-slash normalization (A7) or paths become `<dir>llm_config.json` on Windows.

### Pitfall P2-6: quicktype drops everything semantic (again)
Non-empty `artifacts[]`, unique roles, runtime bounds → all C++ gates (RQ5). Budget the gate code like Phase 1's `CheckElmValidity`, and pin the by-value-optional lifetime rule (`const auto m = manifest.get_artifacts(); if (m && !m->empty())`).

### Pitfall P2-7: promise/future exceptions
Never `set_exception` on the single-flight future — awaiting callers would face a `std::exception_ptr` instead of the structured error. Encode failure in the result type; the future always resolves normally.

## Security Domain

**ASVS level 1 (`security_enforcement: true`, `security_asvs_level: 1`)** — this phase is the milestone's security core (fail-closed unverified-model execution).

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | no | no auth surfaces |
| V3 Session Management | no | — |
| V4 Access Control | no | cache is node-local, single-process |
| V5 Input Validation | **yes** | Manifest = untrusted remote input: schema bounds + C++ gates; hash-format normalization (F5); artifact-count/size ceilings (DoS bound on manifest size and artifact count); URI prefix allowlist implicitly via FileManager loaders |
| V6 Cryptography | **yes (use-only)** | sha256 via existing OpenSSL EVP — never hand-rolled; manifest hash pins trust chain from job JSON (escrow/CRDT-provenanced) → manifest → artifacts |

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malicious manifest swaps artifact URIs (tampered manifest) | Tampering | manifest bytes hash-verified against job-declared `model_manifest_hash` BEFORE parse; artifacts verified against manifest; publish-time gate; no debug bypass (SC-1) — the smoke check runs only post-verify |
| Path traversal via manifest fields (artifact names, hash) | Tampering | roles are a closed enum mapped to fixed filenames; dir name = computed hex digest (P2-4); artifact `name` never used as a path |
| Unbounded manifest / artifact-count DoS | DoS | reject manifests above a byte ceiling and artifact counts above a small cap at parse; artifact `size_bytes` cap per entry (cache byte bound enforces implicitly) |
| TOCTOU between verify and load | Tampering/EoP | atomic publish (stage → verify → smoke → rename); final-path entries are verified-by-construction; trusted-local-disk assumption documented (D-01 defers shared-dir re-verification) |
| Executable model graphs from unverified sources | Elevation | fail-closed everywhere — refusal + quarantine, never execute-then-check (SC-1) |

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| quicktype CLI | manifest schema regen (D-05) | ✓ (verified 2026-09-09, this machine) | 23.2.6 | — |
| Node.js / npm | quicktype runtime | ✓ | 24.16.0 / 11.15.0 | — |
| CMake + MSVC 2022 | builds | ✓ (existing presets) | — | — |
| GTest | unit tests | ✓ (thirdparty ~1.14) | — | — |
| OpenSSL (EVP) | sha256 | ✓ vendored/linked (`sgprocmanagersha`) | 3.0.x | — |
| MNN with `MNN_BUILD_LLM` | smoke check | ✓ (`SGPROC_HAS_MNN_LLM` TRUE in this checkout's build logs) | 3.4.1 fork | smoke-check TU compiles out; cache still usable for non-LLM testing but entries can't be marked Usable (fail-closed) |
| bitswap/IPFS | production ipfs:// fetch | not needed for unit tests | — | tests use `file://`/in-memory (D-08) |

**Missing dependencies with no fallback:** none. **With fallback:** none.

## Package Legitimacy Audit

No packages installed by this phase (zero-new-dependency workstream, D-003). quicktype 23.2.6 already present and previously verified. **No audit applicable.**

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Quicktype emits types for schema `definitions` NOT referenced by root properties | RQ5 / Rec. 1 | If it drops them, use fallback (b): second quicktype run against a manifest-specific schema file into `generated/` — zero hand-edits preserved either way; verify at regen time |
| A2 | `Llm::load()` requires `llm.mnn.weight` to exist even for embedded-weight models (it unconditionally checks all three files, A9) — manifests must ship a weight artifact (possibly small/stub) | RQ2 / Rec. 5 | If some MNN models legitimately lack `.weight`, the required-roles gate needs `llm_config.json`-conditional logic; verify with the Phase 4 Qwen fixture; low impact (gate relaxation) |
| A3 | Host-RAM snapshot field (RQ6 option ii) is the right preflight axis for CPU-backend models | RQ6 | If owner prefers disk-only v1, drop the `GlobalMemoryStatusEx`/`sysconf` addition — `required_memory_bytes` becomes advisory log line; planner/owner confirms |
| A4 | Default byte cap 15GB (mid D-04 range) as a named constant + setter, no config file | RQ8 | If owner wants operator config, defer to Phase 4 `sgns_config.json` wiring; constant remains the default |
| A5 | Smoke-check placement pre-rename (against staging dir) satisfies "complete before usable" | Rec. 8 | If post-rename placement is preferred, a failed check must quarantine the just-published entry instead — equivalent safety, slightly more states; planner's call (explicitly discretionary) |

## Open Questions

1. **Quicktype reachability of unreferenced definitions (R1/A1)**
   - What we know: Phase 1's types were all root-reachable; quicktype's multi-source output generally covers all named definitions, but this is unverified for 23.2.6 against this schema.
   - Recommendation: first regen attempt tells you in 30 seconds; the sanctioned fallback (second `--top-level ElmModelManifest` invocation from a dedicated manifest schema file) is equally D-05-compliant. Record the actual generated type names in the plan (discretion).

2. **Real-model smoke-check coverage in Phase 2 vs Phase 4**
   - What we know: no MNN LLM model fixture exists in the repo (`mnn_llm_test.cpp` deliberately avoids real loads); the Qwen-0.5B-class model is Phase 4's E2E download.
   - What's unclear: whether the owner wants a Phase 2 test that downloads/loads a real (tiny) model — cost: fixture provisioning + slow test + network.
   - Recommendation: keep Phase 2 smoke tests to failure-path + gating assertions; the first real end-to-end load is Phase 4's empty-cache E2E (which is precisely its acceptance criterion). If a cheap tiny model artifact can be committed (< a few MB), one real-load test would materially de-risk P3 — owner's call.

3. **`required_memory_bytes` axis (A3)** — GPU heap vs host RAM vs disk-only; recommendation (ii) host-RAM field; confirm at plan review.

4. **Staging-level verification failure: cleanup vs quarantine (Rec. 6)**
   - D-02 mandates quarantine for *reuse-time* mismatch. Publish-time failures happen on a `.tmp-` path that nothing can ever load — cleanup suffices and keeps `.bad-` meaning "was published, went bad". If the owner wants publish-failures quarantined too (forensics for bad *sources* rather than bad *disks*), the rename target `.bad-<hash>` would collide across retries (second failure finds the name taken) — needs a suffix rule. Recommendation: cleanup for staging failures; quarantine only for reuse-time mismatches (D-02's letter).

## State of the Art (in-tree drift check)

| Old Approach | Current Approach | Status | Impact |
|--------------|------------------|--------|--------|
| Per-execution temp-dir materialization (`MaterializeModelToTempDir`) | Content-addressed cache (this phase) | Materializer still present (A7) — deletion is Phase 3 per CONTEXT | P2 must NOT touch it (SC-5 `%TEMP%` cleanliness for P2 = "new code never writes to temp") |
| Single-buffer model fetch via `GetCidForProc` | Manifest + per-artifact fetch | `GetCidForProc` unchanged in P2 | ELM branch lands in P3/P4 (`GetCidForProc` ELM branch per ARCHITECTURE step [5]) |
| `Validation` enum named from property | (naming lesson) | Confirmed again at `generated/Validation.hpp:22` | Manifest enums will surprise the same way — record actuals post-regen |

Workstream research docs (SUMMARY/STACK/ARCHITECTURE/PITFALLS/FEATURES) re-checked against the live tree: all anchors held (`ProcessingManager.cpp:1931`, `processing_processor_mnn_llm.cpp`, `capability_validator.cpp`, `sha256.hpp`, `llmconfig.hpp`, `FileManager.hpp/.cpp`); line numbers cited in this document are the current ones.

## Sources

### Primary (HIGH confidence — verified in the current working trees, 2026-09-10)
- `SuperGenius/SGProcessingManager/` @ `97bbd04` (`dev_elmruntime`): `include/util/sha256.hpp`; `src/util/sha256.cpp`; `src/util/CMakeLists.txt`; `src/processors/processing_processor_mnn_llm.cpp` + `include/...hpp`; `src/processors/CMakeLists.txt` (LLM gate); `src/processingbase/ProcessingManager.cpp` (1931, 2167, 2266, 1567-1590 deadline timer, 630-763 CheckElmValidity); `include/processingbase/ProcessingManager.hpp` (Error enum); `include/processingbase/vulkan_init_guard.hpp`; `src/capability/capability_validator.cpp` + `include/...hpp` + `include/capability/capability_types.hpp`; `src/capability/CMakeLists.txt`; `test/processingbase/CMakeLists.txt`; `test/processors/CMakeLists.txt` + `mnn_llm_test.cpp`; `test/execution/CMakeLists.txt`; `test/capability/capability_validator_test.cpp`; `gnus-processing-schema.json`; `generated/{Elm,ElmType,ElmFunding,Validation,SgnsProcessing,Generators,helper,ModelFormat}.hpp`; `README.md`; `.github/workflows/generate-headers.yml`; `cmake/CommonBuildParameters.cmake`; `cmake/functions.cmake`; `src/CMakeLists.txt`; `CMakeLists.txt`
- `thirdparty/AsyncIOManager/`: `include/FileManager.hpp`; `src/FileManager.cpp`; `include/FileLoader.hpp`; `include/ASIOSingleton.hpp`; `src/MNNLoader.cpp`; `src/IPFSLoader.cpp`; `src/HTTPLoader.cpp` (prefix registrations)
- `thirdparty/MNN/transformers/llm/engine/`: `include/llm/llm.hpp` (134-158, LlmContext); `src/llm.cpp` (71-83 createLLM, 253-283 checkFile/load, 975-979 timeout, 1323 NORMAL_FINISHED); `src/llmconfig.hpp` (30-37 base_dir, 64-108 ctor, 110-160 file keys); `src/sampler.cpp` (greedy select); `CMakeLists.txt`
- `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp:1930-1965` (cacheDir get/set)
- `SuperGenius/` @ `d459d45d8` (`dev_elmruntime`): `src/account/GeniusNode.cpp` (425-450 config read, 1425-1440 InitContentExchange, 2257-2290 ELM interim branch, 3320-3365 RotateLogFiles); `src/account/GeniusNode.hpp:383`; `src/processing/processing_engine.cpp:84-160`; `src/processing/processing_tasksplit.cpp:37-41`; `src/processing/processing_clocks_elm.hpp`; `example/node_test/sgns_config.json`
- Planning artifacts: `.planning/workstreams/elmbridge/{REQUIREMENTS,ROADMAP,STATE}.md`; `phases/02-manifest-model-cache/02-CONTEXT.md`; `phases/01-.../{01-CONTEXT,01-RESEARCH,01-01-SUMMARY}.md`; `research/{SUMMARY,STACK,ARCHITECTURE,PITFALLS,FEATURES}.md`; `SuperGenius/.planning/notes/ELM-bridging-gaps.md`; `.planning/config.json` (`nyquist_validation: false` — Validation Architecture section skipped)

### Secondary / Tertiary
- None — zero external dependencies; every claim is in-tree.

## Metadata

**Confidence breakdown:**
- FileManager/cache-root mechanics (F1, RQ1): HIGH — read line-level incl. the empty-in-tests consequence
- MNN bundle layout / base_dir (F3, RQ2): HIGH — constructor + `load()` file checks read directly
- CMake/test gating (RQ3): HIGH — Phase 1's own target copied; gate value confirmed in build logs
- sha256 sufficiency (RQ4): HIGH — whole-buffer delivery verified in MNNLoader/IPFSLoader
- Quicktype (RQ5): HIGH for the pipeline/naming lessons (Phase 1 artifacts), MEDIUM for unreferenced-definition emission (A1 — flagged, cheap to resolve at regen)
- CapabilityValidator extension (RQ6): HIGH for current shape; the axis choice is a flagged assumption (A3)
- Single-flight/pin/rename patterns (RQ7): HIGH for the primitives' behavior; codebase has no in-module precedent (new code by design)

**Research date:** 2026-09-10
**Valid until:** 2026-10-10 (stable internal codebase; re-verify line numbers if `dev_elmruntime` advances past `97bbd04` / `d459d45d8`)
