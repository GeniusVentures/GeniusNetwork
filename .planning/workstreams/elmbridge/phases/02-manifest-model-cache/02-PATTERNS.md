# Phase 2: Manifest & Model Cache - Pattern Map

**Mapped:** 2026-09-10
**Files analyzed:** 19 (13 new, 6 modified)
**Analogs found:** 19 / 19 (3 via partial/out-of-submodule precedents — flagged per file)

All paths relative to `SuperGenius/SGProcessingManager/` unless prefixed `SuperGenius/` or `thirdparty/`. Line numbers verified against the live `dev_elmruntime` trees (SGProcessingManager @ `97bbd04`).

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `include/elmruntime/ElmManifest.hpp` + `src/elmruntime/ElmManifest.cpp` | model (parse/verify/gate) | transform (bytes → validated manifest) | `src/processingbase/ProcessingManager.cpp:630-763` (`CheckElmValidity`) + `generated/Elm.hpp:60-99` | exact |
| `include/elmruntime/ElmArtifactFetcher.hpp` + `.cpp` | service (fetch abstraction) | request-response | `thirdparty/AsyncIOManager/include/FileManager.hpp:97-104` + ioc drain at `ProcessingManager.cpp:2167-2168` | exact |
| `include/elmruntime/ElmModelCache.hpp` + `src/elmruntime/ElmModelCache.cpp` | service/store (content-addressed cache) | file-I/O + single-flight | `src/processors/processing_processor_mnn_llm.cpp:27-63` (staging) + `SuperGenius/src/account/GeniusNode.cpp:3336-3360` (rename) + `SuperGenius/src/account/AccountMessenger.hpp:234-236` (`shared_future`) | composite (no single in-submodule analog — see No Analog Found) |
| `src/elmruntime/ElmSmokeCheck.cpp` (+ minimal fwd-decl header) | utility (loadability probe) | request-response | `src/processors/processing_processor_mnn_llm.cpp:71-93` (`LoadModel`) | exact |
| `gnus-processing-schema.json` (modified) + `generated/ElmModelManifest.hpp` et al. (regen) | model (schema/codegen) | — | `gnus-processing-schema.json:117-175` (Phase 1 `Elm`/`ElmGeneration`/`ElmFunding` definitions) | exact |
| `src/elmruntime/CMakeLists.txt` | config (build) | — | `src/capability/CMakeLists.txt:8-36` | exact |
| `src/CMakeLists.txt` (modified, +`elmruntime`) | config | — | `src/CMakeLists.txt:1-8` | exact |
| `test/elmruntime/CMakeLists.txt` | config (test gating) | — | `test/processingbase/CMakeLists.txt:14-19` (Phase 1 pattern) | exact |
| `test/CMakeLists.txt` (modified, +`elmruntime`) | config | — | `test/CMakeLists.txt:1-8` | exact |
| `test/elmruntime/elm_manifest_test.cpp` | test | — | `test/processingbase/elm_job_schema_test.cpp:1-60` | exact |
| `test/elmruntime/elm_model_cache_test.cpp` | test | — | `test/processingbase/elm_job_schema_test.cpp` (structure) + `test/capability/capability_validator_test.cpp` (injection, per RESEARCH A16) | role-match |
| `include/capability/capability_types.hpp` (modified, +host-RAM field) | model | — | same file, `availableDiskBytes` at `:55-62` | exact |
| `include/capability/capability_validator.hpp` (modified, +`CheckElmResources`) | service | request-response | same file, `CanExecute` at `:88-92` | exact |
| `src/capability/capability_validator.cpp` (modified, +`QueryAvailableMemoryBytes` + `CheckElmResources`) | service | request-response | same file, `QueryAvailableDiskBytes` `:95-113` + disk check `:453-471` | exact |
| `test/capability/` ELM-resource tests (extend or new file) | test | — | `test/capability/capability_validator_test.cpp:99,163,194` (`SetSnapshotForTest`) | exact |

---

## Pattern Assignments

### 1. `ElmManifest.hpp/.cpp` — manifest parse, hash-verify, semantic gates

**Analog:** `src/processingbase/ProcessingManager.cpp:630-763` (`CheckElmValidity`) — the Phase 1 gate function this file generalizes.

**Optional-lifetime rule — copy verbatim as the file's first comment** (`ProcessingManager.cpp:636-641`):

```cpp
// CRITICAL lifetime note: the quicktype getters (get_elms etc.) return
// boost::optional<T> BY VALUE. Dereferencing the call result directly
// (*data.get_elms()) yields a reference into a temporary optional that
// dies at the end of the full expression -- iterating it is UB. Always
// materialize the optional into a named local first.
```

**Gate pattern — log-then-structured-error, per check** (`ProcessingManager.cpp:652-658`):

```cpp
// quicktype drops minItems (Pitfall 6): enforce non-empty elms here.
const auto elmsOpt = data.get_elms();
if ( !elmsOpt || elmsOpt->empty() )
{
    m_logger->error( "elm_processing job declares no elms work items" );
    return outcome::failure( Error::ELM_WORK_ITEMS_MISSING );
}
```

Adapt for: non-empty `artifacts[]`, unique roles/names, required MNN roles present (`llm_config`, `llm_model`, `llm_weight`, `tokenizer_file`), `size_bytes ≥ 0`, non-empty `uri`, artifact-count/byte ceilings (DoS bound per RESEARCH security table).

**Uniqueness via `std::set::insert` return** (`ProcessingManager.cpp:661-670`):

```cpp
std::set<std::string> seenWorkItemIds;
for ( const auto &elm : *elmsOpt )
{
    if ( !seenWorkItemIds.insert( elm.get_work_item_id() ).second )
    {
        m_logger->error( "elm_processing job has duplicate work_item_id: " + elm.get_work_item_id() );
        return outcome::failure( Error::DUPLICATE_WORK_ITEM_ID );
    }
}
```

**Own error category — NOT an extension of `ProcessingManager::Error`** (ends at 18, `include/processingbase/ProcessingManager.hpp:82-104`; extending recompiles the world). Copy the `OUTCOME_CPP_DEFINE_CATEGORY_3` shape from `ProcessingManager.cpp:8-45`:

```cpp
OUTCOME_CPP_DEFINE_CATEGORY_3( sgns::sgprocessing, ProcessingManager::Error, e )
{
    switch ( e )
    {
        case sgns::sgprocessing::ProcessingManager::Error::PROCESS_INFO_MISSING:
            return "Processing information missing on JSON file";
        // ...
    }
    return "Unknown error";
}
```

New enum (`ElmRuntimeError`): `MANIFEST_FETCH_FAILED`, `MANIFEST_HASH_MISMATCH`, `ARTIFACT_FETCH_FAILED`, `ARTIFACT_HASH_MISMATCH`, `ARTIFACT_SIZE_MISMATCH`, `CACHE_DIR_UNSET`, `SMOKE_CHECK_FAILED`, `MANIFEST_INVALID`… Map to `ProcessingErrorStage::RESOURCE_RESOLUTION` only at the Phase 3 processor boundary.

**Hash verification:** one-shot `sgns::sgprocmanagersha::sha256` (`include/util/sha256.hpp:8` — the entire API):

```cpp
namespace sgns::sgprocmanagersha
{
  std::vector<uint8_t> sha256(const void* data, size_t dataSize);
}
```

Usage precedent: `processing_processor_mnn_llm.cpp:222` — `sgprocmanagersha::sha256( outputText.c_str(), outputText.size() )`. Hex formatting for digest comparison/logging: copy the manual `%02x` loop from `DeriveExecutorId`, `src/capability/capability_validator.cpp:168-178`:

```cpp
std::ostringstream oss;
oss << "sgproc-";
size_t n = (std::min)( size_t( 8 ), identityHash.size() );
for ( size_t i = 0; i < n; ++i )
{
    char hex[3];
    std::snprintf( hex, sizeof( hex ), "%02x", identityHash[i] );
    oss << hex;
}
```

**P2-4 rule:** the dir name is the computed 64-hex digest of the fetched manifest bytes — the schema-declared `model_manifest_hash` (`"sha256:abc"` in fixtures, `generated/Elm.hpp:82-84`) is only ever *compared* after normalization, never interpolated into a path.

**Notes:** what to change — gates operate on the new generated manifest types (below), not `SgnsProcessing`; quicktype will drop `minItems`/`uniqueItems`/cross-field rules and optional-number bounds again (P2-6) — budget gate code exactly like `CheckElmValidity`.

---

### 2. `ElmArtifactFetcher.hpp/.cpp` — injectable fetch (D-08)

**Analog A (interface shape):** small `std::function`-based abstraction; no in-repo interface file to copy — model on `FinalCallback` at `thirdparty/AsyncIOManager/include/FileManager.hpp:74`:

```cpp
using FinalCallback = std::function<void( ResultType buffers )>;
```

Recommended: `using FetchFn = std::function<outcome::result<std::vector<uint8_t>>( const std::string &uri )>;`

**Analog B (production wiring + drain):** `ProcessingManager.cpp:1900-1955` shows the full queue-then-drain pattern (SaveASync here; LoadASync identical shape at `:2167-2168`):

```cpp
FileManager::GetInstance().SaveASync( outputUrl,
                                      outcome::success( saveBuffers ),
                                      ioc,
                                      [this, outputUrl]( const FileManager::ResultType &result )
                                      {
                                          if ( !result )
                                          {
                                              m_logger->error( "Failed to save output to {}: {}",
                                                               outputUrl,
                                                               result.error().message() );
                                          }
                                      },
                                      saveLocation );
// ...
if ( hasSaves )
{
    ioc->reset();
    ioc->run();
```

Production `FetchFn`: `FileManager::GetInstance().InitializeSingletons()` (idempotent — see `GeniusNode.cpp:1434`, and note `InitializeSingletons` registers the `file` prefix at `thirdparty/AsyncIOManager/src/FileManager.cpp:31-41`), fresh `io_context`, `LoadASync(url, /*parse=*/false, /*save=*/false, ioc, cb, "file")`, `ioc->reset(); ioc->run();`, return bytes from the `ResultType` pair.

**LoadASync signature** (`thirdparty/AsyncIOManager/include/FileManager.hpp:97-104`):

```cpp
shared_ptr<void> LoadASync( const std::string                       &url,
                            bool                                     parse,
                            bool                                     save,
                            std::shared_ptr<boost::asio::io_context> ioc,
                            FinalCallback                            finalcall,
                            std::string                              savetype );
```

**Gotcha — it throws:** `thirdparty/AsyncIOManager/src/FileManager.cpp:57-60`:

```cpp
auto loaderIter = loaders.find( prefix );
if ( loaderIter == loaders.end() )
{
    throw std::range_error( "No loader registered for prefix " + prefix );
}
```

The production FetchFn MUST wrap the call in try/catch and convert to a structured `ARTIFACT_FETCH_FAILED`/`MANIFEST_FETCH_FAILED` — the throw never crosses the acquire boundary.

**Notes:** tests inject in-memory lambdas or `file://` URIs through the real FileManager (zero network, zero IPFS). CMake: only this one TU needs `AsyncIOManager` — link it PRIVATE on the elmruntime target (resolves via `cmake/CommonBuildParameters.cmake:318-321`) or place the TU in ProcessingBase (already links `AsyncIOManager`, `src/processingbase/CMakeLists.txt:26`); keep the library core clean.

---

### 3. `ElmModelCache.hpp/.cpp` — content-addressed store

**Analog A (staging-dir creation + fs discipline):** `src/processors/processing_processor_mnn_llm.cpp:27-63` (`MaterializeModelToTempDir`) — the exact code being superseded; copy its `std::error_code` style, REPLACE its timestamp naming (collision-prone) with UUID:

```cpp
bool MaterializeModelToTempDir( const std::vector<uint8_t> &modelBytes, std::string &outDir )
{
    namespace fs = std::filesystem;

    std::error_code ec;
    fs::path        base = fs::temp_directory_path( ec );
    if ( ec )
    {
        return false;
    }

    const auto stamp = std::chrono::high_resolution_clock::now().time_since_epoch().count();
    fs::path   dir   = base / ( "sgproc_mnn_llm_" + std::to_string( stamp ) );
    fs::create_directories( dir, ec );
    if ( ec )
    {
        return false;
    }

    fs::path      modelPath = dir / "model.mnn";
    std::ofstream out( modelPath, std::ios::binary );
    if ( !out )
    {
        return false;
    }
    out.write( reinterpret_cast<const char *>( modelBytes.data() ),
               static_cast<std::streamsize>( modelBytes.size() ) );
    out.close();
    if ( !out )
    {
        return false;
    }
```

**Trailing-slash normalization — REQUIRED for the smoke check and Phase 3 loads** (`processing_processor_mnn_llm.cpp:59-63`):

```cpp
std::string dirStr = dir.string();
if ( !dirStr.empty() && dirStr.back() != '/' && dirStr.back() != '\\' )
{
    dirStr += '/';
}
outDir = dirStr;
return true;
```

(P2-5: `LlmConfig` uses the string verbatim as a path prefix on Windows too — without this, paths become `<dir>llm_config.json`.)

**Analog B (atomic rename, remove-first for Windows):** `SuperGenius/src/account/GeniusNode.cpp:3336-3360` (`RotateLogFiles`) — the only in-tree `fs::rename` precedent:

```cpp
try
{
    // Handle sgnslog.log rotation
    if ( std::filesystem::exists( sgnslog_path ) )
    {
        // Delete old backup if it exists
        if ( std::filesystem::exists( sgnslog_old_path ) )
        {
            std::filesystem::remove( sgnslog_old_path );
        }
        // Rename current log to backup
        std::filesystem::rename( sgnslog_path, sgnslog_old_path );
    }
}
catch ( const std::filesystem::filesystem_error &e )
{
    std::cerr << "Log rotation error: " << e.what() << std::endl;
    // Continue execution - don't let log rotation failure stop the application
```

**Windows gotchas (P2-2/P2-3):** MSVC `fs::rename` on a directory FAILS if the target exists (POSIX replaces) — remove-or-quarantine the target first; both staging (`.tmp-<uuid>/`) and final (`<hash>/`) live under `<cacheDir>/elmruntime/` → same volume by construction. Prefer `std::error_code` overloads + logging (the materializer's silent-`ec` style loses diagnostics). Tolerate per-entry eviction failure on Windows locked files (log, skip, retry next pass) — never let eviction fail the acquire.

**Analog C (single-flight `shared_future`):** `SuperGenius/src/account/AccountMessenger.hpp:234-236` — established codebase tool, none yet in SGProcessingManager:

```cpp
/// Future of the subscription to the receiving topic
std::shared_future<std::shared_ptr<ipfs_pubsub::GossipPubSub::Subscription>> subs_acc_future_;
/// Future of the subscription to the requests topic
std::shared_future<std::shared_ptr<ipfs_pubsub::GossipPubSub::Subscription>> subs_requests_future_;
```

Shape: `std::unordered_map<std::string, std::shared_future<AcquireResult>>` + one mutex; first caller inserts the future BEFORE fetching, fulfills with an outcome-style result (P2-7: never `set_exception` — awaiting callers must see the structured error, not an `exception_ptr`), erases under mutex on completion; second caller `.wait()`s then pins the same entry.

**Analog D (UUID for staging names):** `SuperGenius/src/processing/processing_tasksplit.cpp:31-41`:

```cpp
uint64_t seed = id_hash ^ static_cast<uint64_t>(timestamp);
std::mt19937 gen(seed);
boost::uuids::basic_random_generator<std::mt19937> uuid_gen(gen);
boost::uuids::uuid uuid = uuid_gen();
return boost::uuids::to_string(uuid);
```

(Boost is already linked; seed from `std::random_device` rather than timestamp-only.)

**Analog E (cache root / D-03):** `ProcessingManager.cpp:1927-1931` — the `getCacheDir()` precedent:

```cpp
auto cacheDir = FileManager::GetInstance().getCacheDir();
if ( !cacheDir.empty() )
{
    auto localUrl = "file://" + cacheDir + "/results/" + output.get_name() + outputFileName;
```

Copy the fail-closed `!cacheDir.empty()` guard. Cache nests `<cacheDir>/elmruntime/<hex-digest>/`. **P2-1:** `getCacheDir()` is `""` in every unit test/standalone process (set only via `setBitswap`, `FileManager.cpp:248`, wired at `GeniusNode.cpp:1432-1437`) — root dir MUST be a constructor param (tests inject temp dir), never read from FileManager inside the library.

**Pin RAII / LRU scan / quarantine:** no in-repo analog — new code (see No Analog Found). Entry layout (stores `elm_manifest.json` beside MNN-role files so D-01 size checks and D-06 restart accounting never re-fetch) and byte-cap-as-`uint64_t`-constructor-param are specified in `02-RESEARCH.md` Rec. 4 / RQ8.

---

### 4. `ElmSmokeCheck.cpp` — loadability probe (SC-2)

**Analog:** `src/processors/processing_processor_mnn_llm.cpp:71-93` (`LoadModel`) — the exact createLLM/load/mutex sequence, verbatim reuse:

```cpp
MNN::Transformer::Llm *MNN_Llm::LoadModel( const std::vector<uint8_t> &modelFileBytes )
{
    // ...materialize...
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
    return llm;
}
```

Run against the *staging dir* (trailing slash per Analog A) pre-rename; add `set_config(R"({"sampler_type":"greedy","max_new_tokens":1})")` + `response(prompt, &oss, nullptr, 1)` + `Llm::destroy` per RESEARCH Rec. 8. `response()` signature: `thirdparty/MNN/transformers/llm/engine/include/llm/llm.hpp:134-158`.

**Include isolation — copy this header pattern:** `include/processors/processing_processor_mnn_llm.hpp:16-29` forward-declares `MNN::Transformer::Llm` so no consumer needs `<llm/llm.hpp>`:

```cpp
namespace MNN
{
    namespace Transformer
    {
        class Llm;
    } // namespace Transformer
} // namespace MNN
```

Wrap ALL MNN includes in the ONE `.cpp`, compiled only when `SGPROC_HAS_MNN_LLM` (gate below). `Llm::load()` hard-fails if `tokenizer.txt`/`llm.mnn`/`llm.mnn.weight` are missing (`thirdparty/MNN/transformers/llm/engine/src/llm.cpp:265-283`) — the smoke check inherits fail-closed for free; a garbage staging dir yields `SMOKE_CHECK_FAILED`, never silent garbage.

---

### 5. `gnus-processing-schema.json` (modified) + `generated/` (regen)

**Analog:** the Phase 1 ELM block — root properties at `gnus-processing-schema.json:64-87` (`job_type`/`elms[]`/`funding`/`validation`), definitions at `:117-175`. New definitions join `definitions` with the same style: `$ref`, `required` arrays, `pattern`/`minLength` on strings (these survive codegen; number bounds on optionals do NOT):

```json
"Elm": {
  "type": "object",
  "description": "One ELM (causal-LM) work item...",
  "required": ["work_item_id", "elm_type", "model_manifest_uri", "model_manifest_hash", "input_uri"],
  "properties": {
    "work_item_id": { "type": "string", "pattern": "^[A-Za-z0-9_-]+$" },
    "elm_type": { "type": "string", "enum": ["causal_lm"] },
    ...
```

**Generated-type reality** (`generated/Elm.hpp:75-99`) — getters return `boost::optional<T>` by value for optionals, `const T&` for required; `CheckConstraint` on patterned strings:

```cpp
boost::optional<ElmGeneration> get_generation() const { return generation; }
const std::string & get_model_manifest_hash() const { return model_manifest_hash; }
void set_model_manifest_hash(const std::string & value) { CheckConstraint("model_manifest_hash", model_manifest_hash_constraint, value); this->model_manifest_hash = value; }
```

**Regen command** (README.md:22-38; CI fires only on `main` → run locally on `dev_elmruntime`; quicktype 23.2.6 verified installed):

```bash
quicktype --src-lang schema --lang cpp --top-level SGNSProcessing \
  --code-format with-getter-setter --const-style west-const \
  --boost --source-style multi-source --include-location global-include \
  --namespace sgns --type-style pascal-case --member-style underscore-case \
  --out generated/SGNSProcMain.hpp gnus-processing-schema.json
```

**Naming lesson (binds):** enums name from the *property* (`validation` → `sgns::Validation`, `generated/Validation.hpp:22`; `elm_type` → `sgns::ElmType`) — record actual generated names post-regen; never assume `ElmModelArtifactRole` etc. **Reachability risk R1:** if quicktype drops definitions not referenced from root properties, sanctioned fallback = second quicktype run against a dedicated `elm-model-manifest-schema.json` with `--top-level ElmModelManifest` into `generated/` (still zero hand-edits). ZERO hand-edits to `generated/` (SCHEMA-01..05).

---

### 6. `src/elmruntime/CMakeLists.txt` — new library

**Analog:** `src/capability/CMakeLists.txt:8-36` (smallest precedent; Ullman-brace-free CMake formatting matches file):

```cmake
add_library(SGCapability STATIC
    capability_validator.cpp
    ../../include/capability/capability_validator.hpp
    ../../include/capability/capability_types.hpp
)

target_compile_definitions(SGCapability PUBLIC SGPROCMGR_TEST_FRIEND)

target_include_directories(SGCapability PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/../../include>
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/../../generated>
    $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/SGProcessingManager/generated>
    $<BUILD_INTERFACE:${Boost_INCLUDE_DIRS}>
    $<BUILD_INTERFACE:${OPENSSL_INCLUDE_DIR}>
)

target_link_libraries(SGCapability
    PUBLIC
    sgprocmanagerlogger
    sgprocmanagersha
    sgprocmanagertypes
    Vulkan::Vulkan
    OpenSSL::Crypto
)

sgnus_install(SGCapability)
```

Adapt: target `sgprocmanagerelmruntime`; link `sgprocmanagerlogger sgprocmanagersha nlohmann_json::nlohmann_json spdlog` PUBLIC; `AsyncIOManager` PRIVATE (fetch TU only — see `src/util/CMakeLists.txt:23-35` for the PRIVATE-link precedent on `sgprocmanagersha`); smoke-check TU + `MNN::MNN` + `Vulkan::Vulkan` appended only under the LLM gate. Register: one line in `src/CMakeLists.txt:1-8` (`add_subdirectory(elmruntime)` — note `processors` is already first, so the CACHE INTERNAL gate is set before elmruntime is reached; belt-and-braces, duplicate the 4-line `EXISTS` detection per RESEARCH RQ3).

**LLM gate analog:** `src/processors/CMakeLists.txt:30-56` — configure-time detection, `CACHE INTERNAL` so sibling test dirs read it:

```cmake
if(EXISTS "${MNN_INCLUDE_DIR}/llm/llm.hpp")
    set(SGPROC_HAS_MNN_LLM TRUE CACHE INTERNAL "MNN vendored build has MNN_BUILD_LLM support (PROC-01)")
else()
    set(SGPROC_HAS_MNN_LLM FALSE CACHE INTERNAL "...")
endif()
```

---

### 7. Tests — `test/elmruntime/` + gating

**Analog A (gating — copy verbatim):** `test/processingbase/CMakeLists.txt:14-19` (Phase 1's exact pattern; wrong gating re-breaks the SuperGenius parent build):

```cmake
add_executable(sgprocbase_elm_job_schema_test elm_job_schema_test.cpp)
target_link_libraries(sgprocbase_elm_job_schema_test PRIVATE GTest::gtest_main ProcessingBase)
add_test(NAME sgprocbase_elm_job_schema_test COMMAND sgprocbase_elm_job_schema_test)
if(SGPROC_TEST_DISCOVERY AND NOT CMAKE_CROSSCOMPILING)
    gtest_discover_tests(sgprocbase_elm_job_schema_test DISCOVERY_TIMEOUT 60)
endif()
```

`test/CMakeLists.txt:1-8` gains `add_subdirectory(elmruntime)`. Smoke-check tests ride `if(SGPROC_HAS_MNN_LLM)` exactly as `test/processors/CMakeLists.txt:28-48` does. `set_tests_properties(... TIMEOUT 120)` only on any test that touches a real MNN load (none planned — failure-path/gating assertions only, no 300MB fixture).

**Analog B (test structure — pure injected data, no network):** `test/processingbase/elm_job_schema_test.cpp:1-60`: file-purpose comment block naming plan/task/decision IDs, anonymous-namespace JSON-builder helpers, `ExpectCreateFailure`-style structured-error assertion helpers:

```cpp
// Helper: run Create() and return the error code (fails the test with a
// readable message if the job unexpectedly parses).
Error ExpectCreateFailure( const std::string &json )
{
    auto result = sgns::sgprocessing::ProcessingManager::Create( json );
    if ( result )
    {
        ADD_FAILURE() << "Expected Create() to reject the job, but it succeeded";
        return Error::INVALID_JSON; // unreachable in practice
    }
    return static_cast<Error>( result.error().value() );
}
```

Cache tests follow the same shape with an injected temp cache root + in-memory `FetchFn` (D-08) — matrix per RESEARCH Rec. 9: tamper→quarantine+structured error, retry→clean re-download, two-thread single-flight with fetch-count==1, pin-survives-eviction, `.tmp-` orphan sweep, `%TEMP%` cleanliness, D-06 restart rescan.

**Capability test injection:** `SGPROCMGR_TEST_FRIEND` PUBLIC define (`src/capability/CMakeLists.txt:16`) + `SetSnapshotForTest` (`capability_validator.hpp:100-104`, used at `test/capability/capability_validator_test.cpp:99,163,194`) — the `CheckElmResources` tests copy this: mock snapshots with fake `availableMemoryBytes`/`availableDiskBytes`, no GPU, no Vulkan.

---

### 8. `CapabilityValidator` mods — `required_memory_bytes` preflight

**Analog A (platform query — copy shape for host RAM):** `src/capability/capability_validator.cpp:95-113`:

```cpp
uint64_t QueryAvailableDiskBytes( const std::string &path )
{
#ifdef _WIN32
    ULARGE_INTEGER freeBytesAvailable;
    if ( GetDiskFreeSpaceExA( path.empty() ? "." : path.c_str(),
                              &freeBytesAvailable, nullptr, nullptr ) )
        return freeBytesAvailable.QuadPart;
    return 0;
#else
    struct statvfs stat;
    if ( statvfs( path.empty() ? "." : path.c_str(), &stat ) == 0 )
        return static_cast<uint64_t>( stat.f_bavail ) * stat.f_frsize;
    return 0;
#endif
}
```

New `QueryAvailableMemoryBytes()`: `GlobalMemoryStatusEx` (`ullTotalPhys`) / `sysconf(_SC_PHYS_PAGES) * _SC_PAGESIZE)`; 0 = query-failed → skip check (same degraded convention as disk, `capability_types.hpp:60`: "`0 = query failed (degraded)`").

**Analog B (check + result shape):** the Step-4 disk check, `capability_validator.cpp:453-471`:

```cpp
// —— Step 4: Disk space check (CAP-05/D-16) ——
if ( snapshot.availableDiskBytes > 0 )
{
    // ...estimate...
    if ( estimatedOutputSize > snapshot.availableDiskBytes )
        unmet.push_back(
            { UnmetRequirementCategory::RESOURCE,
              "Estimated output size " + FormatBytes( estimatedOutputSize )
                  + " exceeds available disk space "
                  + FormatBytes( snapshot.availableDiskBytes ) } );
}
```

`CheckElmResources(manifest, totalArtifactBytes, callback)` mirrors this: disk leg = `totalArtifactBytes` + margin vs `availableDiskBytes`; memory leg = `runtime.required_memory_bytes` vs new `availableMemoryBytes` snapshot field; failures as `{ UnmetRequirementCategory::RESOURCE, "required_memory_bytes X exceeds ..." }`. `CanExecute` stays untouched (it accepts only `sgns::Pass`; ELM has none — new entry point, not an extension). elmruntime does NOT link SGCapability — the validator method reads plain values/structs the caller passes in.

---

## Shared Patterns

### Outcome error category (every elmruntime fallible API)
**Source:** `ProcessingManager.cpp:8-45` (`OUTCOME_CPP_DEFINE_CATEGORY_3`) — new `ElmRuntimeError` enum + category in elmruntime; never throw across the acquire boundary, never extend `ProcessingManager::Error`.

### Worker-thread discipline (Pitfall 14)
**Source:** ioc drain `ProcessingManager.cpp:1948-1949`/`2167-2168` run ON the calling thread. Acquire is synchronous on the caller's (subtask worker) thread with a per-acquire `io_context` — hashing/staging/rename/evict never run in asio handlers. No new thread pool.

### `weak_from_this` (Pitfall 15.1 — defensive for v1)
**Source:** `SuperGenius/src/processing/processing_service.cpp:133-137,158-163`:

```cpp
m_gridChannel->Subscribe(
    [weakSelf = weak_from_this()]( boost::optional<const ipfs_pubsub::GossipPubSub::Message &> message )
    {
        if ( auto self = weakSelf.lock() ) // Check if object still exists
        {
            self->OnMessage( message );
        }
    } );
```

v1's synchronous design has no cross-thread callbacks; ANY future posted callback/timer (e.g. idle-eviction sweep) must capture `weak_from_this` exactly this way (`enable_shared_from_this` on `ElmModelCache` now so it's not a retrofit).

### Logging
`m_logger` spdlog handle via `sgprocmanagerlogger` (`src/util/CMakeLists.txt:1-14`); log-then-fail at every gate (`CheckElmValidity` idiom); the quarantine rename emits the telemetry line (D-07).

### Filesystem
`std::error_code` overloads everywhere; remove/quarantine-before-rename on Windows (P2-2); tolerate eviction failure on locked files (P2-3); trailing slash on any dir handed to `createLLM` (P2-5); UUID staging names (P2-4 analog D).

---

## No Analog Found

| Mechanism | File | Reason | Guidance for planner |
|-----------|------|--------|----------------------|
| Pin-refcount RAII handle (`ElmCachePin`) | `src/elmruntime/ElmModelCache.hpp` | No RAII-pin pattern exists in SGProcessingManager | Move-only handle: entry path + hash + cache back-ref; destructor decrements under mutex + refreshes LRU mtime. Deterministic unpin on every terminal path incl. cancellation (SC-5) |
| LRU directory-scan rebuild | `src/elmruntime/ElmModelCache.cpp` | No cache-index/lifecycle code in submodule | D-06: startup scan of `cache/<hash>/` dirs ordered by `fs::last_write_time`; byte totals from each entry's `elm_manifest.json` (`size_bytes` sum); pin counts start at 0; `.bad-*`/`.tmp-*` excluded; sweep `.tmp-` orphans on a worker thread |
| Single-flight download map | `src/elmruntime/ElmModelCache.cpp` | None in SGProcessingManager | Closest cross-submodule precedent: `AccountMessenger.hpp:234-236` `shared_future` (Analog C above); shape fully specified in RESEARCH RQ7 |

---

## Metadata

**Analog search scope:** `SuperGenius/SGProcessingManager/{src,include,test,generated,gnus-processing-schema.json}`, `thirdparty/AsyncIOManager/{include,src}`, `thirdparty/MNN/transformers/llm/engine` (API-shape citations from RESEARCH, re-verified anchors), `SuperGenius/src/{account,processing}` for cross-submodule precedents (rename, UUID, shared_future, weak_from_this, cache-dir wiring).
**Files scanned:** ~25 read directly; RESEARCH anchor table (A1-A28) cross-checked.
**Pattern extraction date:** 2026-09-10

---

## PATTERN MAPPING COMPLETE

**Phase:** 2 - manifest-model-cache
**Files classified:** 19
**Analogs found:** 19 / 19

### Coverage
- Files with exact analog: 16 (manifest gates, fetch+drain, smoke check, schema/codegen, CMake library, test gating, capability mods, tests)
- Files with role-match/composite analog: 3 (cache core — assembled from staging + rename + shared_future precedents; cache tests; fetcher interface header)
- Files with no analog: 3 internal mechanisms (pin RAII, LRU scan, single-flight map) — all fully specified in RESEARCH RQ7 with cross-submodule precedents cited; none planned blind

### Key Patterns Identified
- Quicktype getters return `boost::optional<T>` **by value** — materialize into named locals (Phase 1 UB lesson, `ProcessingManager.cpp:636-641`); semantic gates live in C++ (`CheckElmValidity` idiom), never in codegen
- Fetch = `FileManager::LoadASync` behind an injectable `FetchFn`, drained synchronously via `ioc->reset(); ioc->run();` on the caller's thread — Pitfall 14 satisfied structurally; `LoadASync` **throws** `range_error` on unknown prefix — catch and convert
- Atomic publish = stage (`.tmp-<uuid>/`) → sha256-verify → smoke-check → `fs::rename`; **Windows rename fails onto an existing target** — remove/quarantine first (`RotateLogFiles` precedent); trailing slash before `createLLM` (P2-5); computed hex digest as dir name, never the declared hash string (P2-4)
- `getCacheDir()` is empty in all tests/standalone — cache root is a constructor param; fail closed on empty (D-03, P2-1)
- Own `ElmRuntimeError` outcome category; map to `ProcessingErrorStage::RESOURCE_RESOLUTION` only at the Phase 3 boundary; errors ride the single-flight future's *value*, never `set_exception` (P2-7)
- Test gating: unconditional `add_test` + `gtest_discover_tests` under `SGPROC_TEST_DISCOVERY`; smoke tests under `SGPROC_HAS_MNN_LLM`; injection via constructor params and `SetSnapshotForTest` — no IPFS, no real model, no network in unit tests

### File Created
`.planning/workstreams/elmbridge/phases/02-manifest-model-cache/02-PATTERNS.md`

### Ready for Planning
Pattern mapping complete. Every new/modified file has an identified analog or a RESEARCH-specified mechanism with cited precedents — the planner can copy excerpts directly into PLAN.md actions.
