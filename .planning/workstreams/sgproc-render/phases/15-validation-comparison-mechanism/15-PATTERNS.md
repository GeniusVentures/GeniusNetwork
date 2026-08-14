# Phase 15: Validation Comparison Mechanism - Pattern Map

**Mapped:** 2026-08-14
**Files analyzed:** 9 (5 edited existing, 4 new)
**Analogs found:** 9 / 9 (all in-repo; this phase is pure internal restructuring, no new external deps)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `SuperGenius/src/processing/processing_validation_core.cpp` (edit) | service (validation core) | CRUD-style compare/transform | itself (pre-fix version, same file) | exact — fixing in place |
| `SuperGenius/src/processing/processing_validation_core.hpp` (edit) | service header | request-response (signature) | itself | exact |
| `SGProcessingManager/include/util/diff_utils.hpp` (new) | utility (header) | transform | `SGProcessingManager/include/util/quantization.hpp` | exact (sibling schema-parsing utility) |
| `SGProcessingManager/src/util/diff_utils.cpp` (new) | utility (impl) | transform | `SGProcessingManager/tools/capture/capture_diff.cpp` lines 40-234 (unnamed-namespace diff primitives to extract) + `SGProcessingManager/src/util/quantization.cpp` (Parameter-lookup convention) | exact — literal extraction target |
| `SGProcessingManager/src/util/CMakeLists.txt` (edit) | config (CMake) | build-config | same file's existing `sgprocmanagerquant` target block | exact — copy the block verbatim, rename |
| `SGProcessingManager/src/processors/CMakeLists.txt` (edit) | config (CMake) | build-config | existing `sgprocmanagerquant` entry in this file's `PUBLIC` link list | exact |
| `SGProcessingManager/tools/capture/CMakeLists.txt` (edit) | config (CMake) | build-config | this file itself, `capture_diff`'s `target_link_libraries` block | exact |
| `SGProcessingManager/tools/capture/capture_diff.cpp` (edit) | utility (CLI) | transform | itself (pre-extraction) | exact |
| `SuperGenius/src/processing/processing_subtask_queue_accessor_impl.{hpp,cpp}` (edit) | service/orchestration | event-driven + request-response | `setMirrorResultCallback`/`setBitswap` (same file, existing setters) | exact — copy setter pattern |
| `SuperGenius/test/src/processing_conformance_security/secv02_counter_test.cpp` (new) | test | request-response (full pipeline) | `SuperGenius/test/src/processing_conformance_security/secv01_counter_test.cpp` | exact — explicit methodology mirror (D-05) |
| `SuperGenius/test/src/processing/processing_subtask_queue_manager_test.cpp` (optional extend) | test | CRUD/unit | same file, `TEST_F(ProcessingSubTaskQueueManagerTest, ValidateResults)` (lines 395-440) | exact — extend existing test |

## Pattern Assignments

### `SuperGenius/src/processing/processing_validation_core.cpp` / `.hpp` (service, fix + extend)

**Analog:** itself — this is an in-place bug fix + extension, not a from-scratch file. Full current content already read (201 lines cpp, 82 lines hpp).

**The bug being fixed** (`processing_validation_core.cpp:53-98`, exact defect at line 84):
```cpp
std::map<std::string, std::vector<uint8_t>> chunks;   // line 55 — flattened accumulator, THE structural defect

for ( int chunkIdx = 0; chunkIdx < subTask.chunkstoprocess_size(); ++chunkIdx )
{
    auto it = chunks.insert(
        std::make_pair( subTask.chunkstoprocess( chunkIdx ).SerializeAsString(),
                        std::vector<uint8_t>() ) );
    const std::string &chunkHashBytes = itResult->second.chunk_hashes( chunkIdx );
    it.first->second.insert( it.first->second.end(), chunkHashBytes.begin(), chunkHashBytes.end() );  // line 84 — BUG: appends, never compares
}
```
`chunks` is keyed on `subTask.chunkstoprocess(chunkIdx).SerializeAsString()` (chunk identity) — **this keying mechanism is correct and must be preserved**; only the value type/comparison behavior changes.

**Existing (correct, untouched) sibling check — `CheckSubTaskResultHashes`** (`cpp:173-198`) — shows the existing per-subtask iteration + `m_logger->error(...)` + `outcome::failure(Error::...)` idiom to replicate for the new comparison path:
```cpp
outcome::result<void> ProcessingValidationCore::CheckSubTaskResultHashes(
    const SGProcessing::SubTask &subTask,
    const std::map<std::string, std::vector<uint8_t>> &chunks ) const
{
    std::unordered_set<std::string> encounteredHashes;
    for ( int chunkIdx = 0; chunkIdx < subTask.chunkstoprocess_size(); ++chunkIdx )
    {
        const auto &chunk = subTask.chunkstoprocess( chunkIdx );
        auto it = chunks.find( chunk.SerializeAsString() );
        if ( it != chunks.end() ) { /* ... */ }
        else
        {
            m_logger->error( "NO_CHUNK_RESULT_FOUND [{}, {}]", subTask.subtaskid(), chunk.chunkid() );
            return outcome::failure( Error::MISSING_CHUNK_RESULT );
        }
    }
    return outcome::success();
}
```

**Error enum pattern to extend** (`hpp:30-40`) — add new enumerators here (e.g. `CHUNK_HASH_MISMATCH_UNTOLERATED`) following the existing style, and add a matching `case` + string in the `OUTCOME_CPP_DEFINE_CATEGORY_3` switch (`cpp:16-38`):
```cpp
enum class Error
{
    NO_RESULTS_FOR_SUBTASK = 0,
    WRONG_RESULT_HASHES_LENGTH,
    DUPLICATE_CHUNK_RESULT_HASH,
    EMPTY_CHUNK_RESULT_HASH,
    MISSING_CHUNK_RESULT,
    INVALID_CHUNK_RESULT_HASH,
    SUBTASK_ID_MISMATCH,
    INVALID_RESULTS_BATCH
};
```

**Recommended fix shape** (from RESEARCH.md, grounded in the above): replace `chunks`'s value type with a per-subtask map so genuine comparison becomes possible:
```cpp
std::map<std::string, std::map<std::string /*subtaskId*/, std::string /*chunkHashBytes*/>> chunksBySubtask;
// ...
chunksBySubtask[subTask.chunkstoprocess(chunkIdx).SerializeAsString()][subTask.subtaskid()] =
    itResult->second.chunk_hashes(chunkIdx);
```
Then a genuine comparison pass: for each chunk key with 2+ contributing subtasks, if all hash strings are byte-identical → OK; if they differ → invoke the tolerance fallback before deciding.

**Current signature to extend** (`hpp:47-49`):
```cpp
outcome::result<void> ValidateResults( const SGProcessing::SubTaskCollection &subTasks,
                                       const std::map<std::string, SGProcessing::SubTaskResult> &results,
                                       std::set<std::string> &invalidSubTaskIds );
```
Proposed additions (illustrative, exact shape is Claude's Discretion per CONTEXT.md/RESEARCH.md): `float floatQuantScale`, `int byteQuantMaskBits`, `std::shared_ptr<boost::asio::io_context> fetchContext`.

**Sole call site to update** — `SuperGenius/src/processing/processing_subtask_queue_accessor_impl.cpp:327` (inside `FinalizeQueueProcessing`):
```cpp
auto validate_res = m_validationCore.ValidateResults( subTasks, m_results, invalidSubTaskIds );
```

---

### `SGProcessingManager/include/util/diff_utils.hpp` + `src/util/diff_utils.cpp` (new utility)

**Analog:** `SGProcessingManager/include/util/quantization.hpp` (header-doc/namespace convention) + `SGProcessingManager/tools/capture/capture_diff.cpp` lines 40-234 (the actual logic to move).

**Namespace/header convention to copy** (`quantization.hpp:1-11`):
```cpp
#ifndef SGPROCMGR_QUANTIZATION_HPP
#define SGPROCMGR_QUANTIZATION_HPP

#include <cstddef>
#include <cstdint>
#include <vector>

#include "Parameter.hpp"
#include "ParameterType.hpp"

namespace sgns::sgprocmanagerquant
{
    float ResolveQuantScale( const std::vector<sgns::Parameter> *parameters );
    int ResolveByteQuantMode( const std::vector<sgns::Parameter> *parameters );
    void QuantizeFloatBuffer( float *data, size_t count, float scale );
    void QuantizeByteBuffer( uint8_t *data, size_t count, int maskBits );
}
#endif
```
New file should mirror this exactly: `sgns::sgprocmanagerdiff` namespace, doc-comments explaining D-03/D-04 branch semantics inline (per Phase 14's own commenting discipline), `Parameter.hpp`/`ParameterType.hpp` include for the `ResolveFloatToleranceRelative`/`ResolveByteToleranceAbsolute` parameter-lookup helpers.

**Diff primitives to extract verbatim** (`capture_diff.cpp:40-234`, currently `namespace { ... }`, CLI-only):
```cpp
constexpr float kRelativeDeltaEpsilonFloor = 1e-6f;
constexpr double kDefaultFloatRelativeThreshold = 1e-4;   // capture_diff.cpp:50
constexpr int kDefaultByteAbsoluteThreshold = 1;          // capture_diff.cpp:53

struct ElementDiffStats
{
    size_t  elementCount              = 0;
    double  maxAbsDelta                = 0.0;
    double  maxRelDelta                = 0.0;
    int64_t maxUlpDistance             = 0;
    double  percentExceedingThreshold  = 0.0;
    bool    sizeMismatch               = false;
};

ElementDiffStats ComputeFloat32Diff( const std::vector<uint8_t> &a, const std::vector<uint8_t> &b )
{
    ElementDiffStats stats;
    if ( a.size() != b.size() ) { stats.sizeMismatch = true; return stats; }
    stats.elementCount = a.size() / sizeof( float );
    size_t exceedingCount = 0;
    for ( size_t idx = 0; idx < stats.elementCount; ++idx )
    {
        float valA, valB;
        std::memcpy( &valA, a.data() + idx * sizeof( float ), sizeof( float ) );
        std::memcpy( &valB, b.data() + idx * sizeof( float ), sizeof( float ) );
        float absDelta = std::fabs( valA - valB );
        float denom    = std::max( { std::fabs( valA ), std::fabs( valB ), kRelativeDeltaEpsilonFloor } );
        float relDelta = absDelta / denom;
        int64_t ulp    = UlpDistanceFloat( valA, valB );
        if ( relDelta > kDefaultFloatRelativeThreshold ) { ++exceedingCount; }
        stats.maxAbsDelta = std::max( stats.maxAbsDelta, (double)absDelta );
        stats.maxRelDelta = std::max( stats.maxRelDelta, (double)relDelta );
        stats.maxUlpDistance = std::max( stats.maxUlpDistance, ulp );
    }
    stats.percentExceedingThreshold = stats.elementCount == 0 ? 0.0
        : 100.0 * (double)exceedingCount / (double)stats.elementCount;
    return stats;
}
// ComputeUint8Diff mirrors this exactly for uint8 (capture_diff.cpp:196-232)
// UlpDistanceFloat/OrderedFloatBits (capture_diff.cpp:127-143) also move verbatim
```
**Important:** `kDefaultFloatRelativeThreshold`/`kDefaultByteAbsoluteThreshold` are the D-04 fallback constants — move them as **named exported constants** in `diff_utils.hpp`, not left as file-local `constexpr` in the new `.cpp`, since `capture_diff.cpp` will need to reference the identical constants post-extraction (`ComputeFloat32Diff`'s `relDelta > kDefaultFloatRelativeThreshold` check currently reads the file-local one; both call sites — CLI and validator — must read the *same* symbol to guarantee zero behavioral drift, per RESEARCH.md's core rationale for this extraction).

**Parameter-lookup convention to mirror for D-03/D-04's new `ResolveFloatToleranceRelative`/`ResolveByteToleranceAbsolute`:** same find-by-name-in-`parameters`-array convention as `ResolveQuantScale`/`ResolveByteQuantMode` (declared `quantization.hpp:29,45`) — read `SGProcessingManager/src/util/quantization.cpp:32-84` (not yet read this session, but referenced/summarized in RESEARCH.md) for the exact loop body to replicate; do not modify the existing resolvers, add new sibling functions only.

---

### `SGProcessingManager/src/util/CMakeLists.txt` (edit — new `sgprocmanagerdiff` target)

**Analog:** the existing `sgprocmanagerquant` block in this exact file (lines 28-41):
```cmake
add_library(sgprocmanagerquant
    quantization.cpp
	../../include/util/quantization.hpp
)
target_include_directories(sgprocmanagerquant PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/../../include>
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/../../generated>
    $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/SGProcessingManager/generated>
)
target_link_libraries(sgprocmanagerquant
    PUBLIC
    nlohmann_json::nlohmann_json
)
sgnus_install(sgprocmanagerquant)
```
Copy verbatim, rename `sgprocmanagerquant` → `sgprocmanagerdiff`, `quantization.cpp`/`.hpp` → `diff_utils.cpp`/`.hpp`.

---

### `SGProcessingManager/src/processors/CMakeLists.txt` (edit — link new lib into `SGProcessors`)

**Analog:** this file's existing `PUBLIC` link entry for `sgprocmanagerquant` (not re-read this session — already verified present by RESEARCH.md's CMake link-graph trace: `processing_service → ProcessingBase → SGProcessors → sgprocmanagerquant`, all PUBLIC). Add `sgprocmanagerdiff` alongside `sgprocmanagerquant` in the same `target_link_libraries(SGProcessors PUBLIC ...)` list — no other CMakeLists.txt needs touching; this chain is already fully PUBLIC end-to-end so `processing_validation_core.cpp` can `#include "util/diff_utils.hpp"` with zero further changes.

---

### `SGProcessingManager/tools/capture/CMakeLists.txt` (edit — wire `capture_diff` to shared lib)

**Analog:** this file itself, lines 38-46 (full file already read):
```cmake
add_executable(capture_diff
    capture_diff.cpp
)

target_link_libraries(capture_diff
    PRIVATE
    sgproccapture
    nlohmann_json::nlohmann_json
)
```
Add `sgprocmanagerdiff` to this `target_link_libraries` list. Confirms `capture_diff` is `add_executable`-only today (no `add_library`) — this is expected and unchanged; only its link list gains one entry.

---

### `SGProcessingManager/tools/capture/capture_diff.cpp` (edit — remove duplicated logic)

**Analog:** itself, the unnamed-namespace block (lines 40-234, fully read above). Replace the `ComputeFloat32Diff`/`ComputeUint8Diff`/`ElementDiffStats`/`UlpDistanceFloat`/`OrderedFloatBits`/`kDefaultFloatRelativeThreshold`/`kDefaultByteAbsoluteThreshold` definitions with `#include "util/diff_utils.hpp"` and calls into `sgns::sgprocmanagerdiff::...`. `main()` (line 236 onward) and the JSON-report logic are unchanged — only the unnamed-namespace helper block is removed/replaced.

---

### `SuperGenius/src/processing/processing_subtask_queue_accessor_impl.{hpp,cpp}` (edit — new setter + fetch context)

**Analog:** the existing `setMirrorResultCallback`/`setBitswap` setters in the **same file** (`hpp:57-61`):
```cpp
/// @brief Set callback invoked when a mirrored result arrives. The callback receives the ipfs_results_data_id string.
void setMirrorResultCallback( std::function<void( const std::string & )> callback );

/// @brief Set bitswap instance for data availability checks on IPFS results.
void setBitswap( std::shared_ptr<sgns::ipfs_bitswap::Bitswap> bitswap );
```
New setter (e.g. `setValidationTolerance(float floatScale, int byteMaskBits)`) should follow this exact doc-comment + signature style, storing into new private members alongside the existing ones (`hpp:95-109` shows the member-variable block to extend — `m_gossipPubSub`, `m_subTaskQueueManager`, ..., `m_localContext` (already present, reusable for the fetch — no new io_context needed), `m_mirrorResultCallback`, `m_mutexMirrorCallback`).

**Existing io_context member to reuse for the mismatch-path fetch** (`hpp:100-104`, already present — no new member needed):
```cpp
std::shared_ptr<boost::asio::io_context> m_localContext;
using WorkGuard = boost::asio::executor_work_guard<boost::asio::io_context::executor_type>;
std::optional<WorkGuard>                   m_localWorkGuard;
std::thread                                m_localThread;
```

**Existing forwarding pattern from `ProcessingNode` to mirror** (`SuperGenius/src/processing/processing_node.cpp:107-130` — matches RESEARCH.md excerpt exactly, not re-read since research already verified it):
```cpp
void ProcessingNode::setMirrorResultCallback( std::function<void( const std::string & )> callback )
{
    if ( m_subTaskQueueAccessor )
    {
        auto accessor = std::dynamic_pointer_cast<SubTaskQueueAccessorImpl>( m_subTaskQueueAccessor );
        if ( accessor )
        {
            accessor->setMirrorResultCallback( std::move( callback ) );
        }
    }
}
```
Add a matching `ProcessingNode::setValidationTolerance(...)` forwarder using the identical `dynamic_pointer_cast` + null-check idiom.

**Private-method declaration convention to extend** (`hpp:75-93`) — add the mismatch-path fetch helper here if it's a private method on this class (vs. living inside `ValidateResults` itself):
```cpp
bool ValidateResultData( const SGProcessing::SubTaskResult &result, bool requireAvailable ) const;
```
This existing method (`processing_subtask_queue_accessor_impl.cpp:515+`, not re-read — already fully described by RESEARCH.md) is the direct precedent for scheme-validating (`ipfs://`) before any fetch — the new mismatch-path fetch must reuse this same validation discipline (Pitfall 2 in RESEARCH.md), not bypass it.

**`FinalizeQueueProcessing` call site to update** (`hpp:80-81` declares it; body at `cpp:323-341` per CONTEXT.md, not re-read this session):
```cpp
FinalizationRetVal FinalizeQueueProcessing( const SGProcessing::SubTaskCollection &subTasks,
                                            std::set<std::string>                 &invalidSubTaskIds );
```
This is the sole call site that must pass the new `floatQuantScale`/`byteQuantMaskBits`/`fetchContext` (or `m_localContext` directly) into `ValidateResults`.

---

### `SuperGenius/test/src/processing_conformance_security/secv02_counter_test.cpp` (new)

**Analog:** `SuperGenius/test/src/processing_conformance_security/secv01_counter_test.cpp` (job-pair pattern, D-05 explicit mirror) combined with `processing_subtask_queue_manager_test.cpp`'s `ValidateResults` test (two-subtask/one-chunk protobuf construction, shown in full below).

**Two-subtask/one-chunk construction to mirror exactly** (`processing_subtask_queue_manager_test.cpp:395-440`, full test already read):
```cpp
TEST_F(ProcessingSubTaskQueueManagerTest, ValidateResults)
{
    SGProcessing::SubTaskCollection subTasks;
    // A single chunk is added to 2 subtasks
    SGProcessing::ProcessingChunk chunk1;
    chunk1.set_chunkid("CHUNK_1");
    chunk1.set_n_subchunks(1);

    {
        auto subtask = subTasks.add_items();
        subtask->set_subtaskid("SUBTASK_1");
        auto chunk = subtask->add_chunkstoprocess();
        chunk->CopyFrom(chunk1);
    }
    {
        auto subtask = subTasks.add_items();
        subtask->set_subtaskid("SUBTASK_2");
        auto chunk = subtask->add_chunkstoprocess();
        chunk->CopyFrom(chunk1);
    }

    std::map<std::string, SGProcessing::SubTaskResult> results;
    SGProcessing::SubTaskResult subTaskResult;
    subTaskResult.add_chunk_hashes("1");
    subTaskResult.set_subtaskid("SUBTASK_1");
    results.emplace(subTaskResult.subtaskid(), subTaskResult);

    ProcessingValidationCore validationCore;
    {
        std::set<std::string> invalidSubTaskIds;
        auto validate_res = validationCore.ValidateResults(subTasks, results, invalidSubTaskIds);
        ASSERT_TRUE(validate_res.has_error());
    }

    subTaskResult.set_subtaskid("SUBTASK_2");
    results.emplace(subTaskResult.subtaskid(), subTaskResult);

    {
        std::set<std::string> invalidSubTaskIds;
        auto validate_res = validationCore.ValidateResults(subTasks, results, invalidSubTaskIds);
        ASSERT_FALSE(validate_res.has_error());
        ASSERT_EQ(0, invalidSubTaskIds.size());
    }
}
```
**Critical gap this exact test exposes (and this phase closes):** both subtasks reuse the **same** `subTaskResult` object (`add_chunk_hashes("1")` called once, only `set_subtaskid` changes) — both report the literal identical hash `"1"`. There is **no existing case where the two subtasks report different hash bytes for the same chunk.** SECV-02 (and/or an extension of this exact test, per RESEARCH.md's "Separately" note) must add that case.

**Two-job correct-vs-corrupted pipeline pattern to mirror** — `secv01_counter_test.cpp` (referenced extensively in RESEARCH.md, not re-read directly this session since RESEARCH.md already quotes/describes it verified: lines 34-198 give two inline-JSON job definitions differing only in a model-file fixture swap, each run through `ProcessingManager::Create()` + `Process()`, producing real `chunkhashes` output). Combine: run both jobs for real (not synthetic hashes), then build two `SGProcessing::SubTask` objects referencing the **same single `ProcessingChunk`** (mirroring the test above), each populated with its own run's **real, different** `chunkhashes[0]` value — feed through `SubTaskQueueAccessorImpl`'s real public API (`AssignSubTasks`/`CompleteSubTask`, `hpp:52,54`) per D-05, not `ValidateResults` directly.

**Scope note (Pitfall 3 in RESEARCH.md):** keep this fixture in the single-chunk case (`block_len == width`, no `chunk_stride`) — distinct from SECV-01's own overlapping-window fixture (`chunk_stride: 32 < block_len: 64`) — so the tolerance fallback's byte-slicing stays exact, not approximated.

---

### `SuperGenius/test/src/processing/processing_subtask_queue_manager_test.cpp` (optional extend)

**Analog:** the same file's existing `ValidateResults` test (shown in full above). Recommended additive case (per RESEARCH.md's "Separately" note): add a `SUBTASK_2` that reports a **different** `chunk_hashes` string than `SUBTASK_1` for the same shared `CHUNK_1`, and assert the fixed code flags it (`invalidSubTaskIds` non-empty or the tolerance path is exercised) — a fast, narrow regression test for XNODE-01b in isolation, complementary to SECV-02's full-pipeline test.

## Shared Patterns

### Async-fetch-then-block idiom (D-01's mismatch-path fetch)
**Source:** `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp:1890-1918` (`GetSubCidForProc`, direct `LoadASync` precedent) and `ProcessingManager.cpp:1621-1634` (blocking-drain idiom).
**Apply to:** the new mismatch-path fetch inside `ValidateResults`/`FinalizeQueueProcessing`.
```cpp
// Fire-and-block idiom (ProcessingManager.cpp:1621-1634)
if ( hasSaves )
{
    ioc->reset();
    ioc->run();
    // After async IO completes, collect the save locations
}

// LoadASync precedent (ProcessingManager.cpp:1890-1918)
auto modeldata = FileManager::GetInstance().LoadASync(
    url, false, false, ioc,
    [this, results]( outcome::result<std::shared_ptr<std::pair<std::vector<std::string>,
                                                                std::vector<std::vector<char>>>>> buffers )
    {
        if ( buffers )
        {
            if ( results ) { results->insert( results->end(), buffers.value()->second[0].begin(),
                                              buffers.value()->second[0].end() ); }
        }
        else { m_logger->error( "Failed to obtain processing source: {}", buffers.error().message() ); }
    },
    "file" );
```
This repo's established convention favors blocking-on-a-dedicated-io_context (reusing `SubTaskQueueAccessorImpl::m_localContext`) over making the whole `ValidateResults` call chain asynchronous.

### Scheme/availability validation before any IPFS fetch (V5 Input Validation / Pitfall 2)
**Source:** `SuperGenius/src/processing/processing_subtask_queue_accessor_impl.cpp:515+` (`ValidateResultData`) — not re-read directly this session but confirmed present/described in both CONTEXT.md and RESEARCH.md as already handling the empty-`ipfs_results_data_id` case (`return true; // No IPFS data to validate`).
**Apply to:** the new mismatch-path fetch — must reuse this same scheme-validation/empty-check discipline and fail closed (treat unfetchable data as a genuine mismatch) rather than crash/hang on a malformed or missing `ipfs_results_data_id` (an attacker-influenced field).

### Error enum + `outcome::result` idiom
**Source:** `processing_validation_core.hpp:30-40` (enum) + `processing_validation_core.cpp:15-38` (`OUTCOME_CPP_DEFINE_CATEGORY_3` string switch) + `cpp:69-72,93-96,112-117` (usage: `invalidSubTaskIds.insert(...)`, `if (!error) { error = make_error_code(Error::X); }`).
**Apply to:** any new error case this phase introduces (chunk-hash mismatch beyond tolerance, fetch failure, unsliceable overlapping-window chunk) — add a new `Error` enumerator + matching switch case, and follow the exact `if (!error) { error = ...; }` first-error-wins accumulation pattern already used throughout `ValidateResults`.

### Setter-mirrors-existing-setter pattern for threading new capabilities into `SubTaskQueueAccessorImpl`
**Source:** `processing_subtask_queue_accessor_impl.hpp:57-61` (`setMirrorResultCallback`/`setBitswap`) + `processing_node.cpp:107-130` (forwarding wrapper on `ProcessingNode`).
**Apply to:** the new `setValidationTolerance(float floatScale, int byteMaskBits)` (or equivalent) setter and its `ProcessingNode` forwarder — copy the doc-comment style, the `dynamic_pointer_cast<SubTaskQueueAccessorImpl>` + null-check idiom, and the private-member storage convention verbatim.

### New static-library wiring (zero-CMake-surface-area addition)
**Source:** `SGProcessingManager/src/util/CMakeLists.txt:28-41` (`sgprocmanagerquant` target) and the already-fully-PUBLIC link chain `processing_service → ProcessingBase → SGProcessors → sgprocmanagerquant`.
**Apply to:** the new `sgprocmanagerdiff` target — copy the `sgprocmanagerquant` CMake block verbatim (rename only), add one `PUBLIC` link-list entry in `SGProcessingManager/src/processors/CMakeLists.txt`, and one entry in `tools/capture/CMakeLists.txt`. No other CMakeLists.txt in the chain needs touching — this is a verified zero-additional-plumbing pattern.

## No Analog Found

None — every file this phase creates/edits has a strong, directly-verified in-repo analog (this phase is explicitly framed by RESEARCH.md as "almost entirely plumbing and extraction, not new algorithm design"). The one genuinely novel piece — the `quantScale`/`byteQuantMode` → numeric-tolerance-threshold formula (D-03/D-04) — has no existing formula to copy (flagged `[ASSUMED]` in RESEARCH.md's Assumptions Log, A1/A2) but does reuse the exact `capture_diff` comparison mechanics and Phase 14's `ResolveQuantScale`/`ResolveByteQuantMode` lookup convention as its building blocks, so it is not analog-less at the mechanism level, only at the formula-constant level.

## Metadata

**Analog search scope:** `SuperGenius/src/processing/`, `SuperGenius/SGProcessingManager/src/util/`, `SuperGenius/SGProcessingManager/tools/capture/`, `SuperGenius/SGProcessingManager/src/processors/`, `SuperGenius/test/src/processing_conformance_security/`, `SuperGenius/test/src/processing/`
**Files scanned/read this session:** `processing_validation_core.hpp`, `processing_validation_core.cpp`, `processing_subtask_queue_accessor_impl.hpp` (partial, lines 40-109), `quantization.hpp` (full), `capture_diff.cpp` (lines 1-240), `capture_diff`'s `CMakeLists.txt` (full), `util/CMakeLists.txt` (full), `processing_subtask_queue_manager_test.cpp` (lines 390-440) — plus extensive prior verification already captured in RESEARCH.md/CONTEXT.md for files not re-read here (`ProcessingManager.cpp`, `processing_node.cpp`, `secv01_counter_test.cpp`, `SGProcessing.proto`, `processing_processor_mnn_float.cpp`/`_volume.cpp`, `quantization.cpp`) to avoid redundant re-reads per no-re-read constraint.
**Pattern extraction date:** 2026-08-14
