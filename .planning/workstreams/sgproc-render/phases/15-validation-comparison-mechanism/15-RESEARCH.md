# Phase 15: Validation Comparison Mechanism - Research

**Researched:** 2026-08-14
**Domain:** C++ distributed-processing result validation (SGProcessingManager / SuperGenius `processing_service`)
**Confidence:** MEDIUM-HIGH (all code-location claims are `[VERIFIED: codebase]` via direct file reads; the tolerance-formula and byte-slicing recommendations are reasoned proposals from that code — `[ASSUMED]`, flagged in the Assumptions Log)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** On a chunk-hash mismatch, fetch both subtasks' underlying output data via the **existing** `ipfs_results_data_id`/output-URI mechanism — the same `FileManager`-based path `ProcessingManager::Process()` already uses to save (and IPFS-dual-cache) subtask output (`ProcessingManager.cpp:1585-1618`, keyed by each output's declared `source_uri_param` in the job schema JSON). **No new fetch mechanism, no `SGProcessing.proto` changes.** Rejected: extending `SubTaskResult` to carry raw chunk bytes inline (proto/wire-format change).
- **D-02:** Mismatch-path-only fetch — no I/O added to the trivial matching-hash case. `ValidateResults`/its caller only reaches into IPFS when a chunk-hash comparison actually disagrees.
- **Open research question (D-01):** subtask output is saved as one blob per subtask output; the tolerance fallback needs a single chunk's bytes within that blob. Slicing mechanism left to this research (see "Blob-to-Chunk Slicing" below).
- **D-03:** When a job declares `quantScale`/`byteQuantMode` (Phase 14), derive the numeric tolerance threshold from it (grid-step-based bound tied to `S`/`N`), not an unrelated fixed constant.
- **D-04:** When a job declares no precision at all, fall back to `capture_diff`'s existing fixed constants (`kDefaultFloatRelativeThreshold = 1e-4`, `kDefaultByteAbsoluteThreshold = 1`, `capture_diff.cpp:50,53`).
- **D-05:** SECV-02 mirrors SECV-01's methodology exactly — a full pipeline test (two complete jobs, correct vs. corrupted, run end-to-end through real subtask assignment), not a narrow unit test. Must exercise `ValidateResults`/`SubTaskResult`/subtask-queue plumbing (unlike SECV-01, which never touches this path).

### Claude's Discretion

- Blob-to-chunk slicing/offset mechanism for the fetched output data (D-01's open research question).
- Exact `quantScale`/`byteQuantMode` → numeric-tolerance-threshold formula (D-03).
- Physical location for the extracted `capture_diff` comparison logic (shared lib, header-only, etc.).
- Exact SECV-02 test file name/location, and precisely how the two-job pipeline is wired to produce two `SubTaskResult`s that reach `ValidateResults` with a genuine chunk mismatch.
- Whether the fetch-on-mismatch path is synchronous/blocking inside `ValidateResults` or dispatched by its caller — treated as a normal implementation choice.

### Deferred Ideas (OUT OF SCOPE)

- Blob-to-chunk slicing mechanism is NOT deferred (it's in-scope, just not pre-decided).
- Actual cross-node consensus/redundant-execution orchestration plumbing (XNODE-01c) — explicitly out of scope for v2.2, deferred to a future milestone. **Confirmed by this research:** the only real production call site of `ProcessTaskSplitter::SplitTask` (`GeniusNode.cpp:2023`) passes `addvalidationsubtask=false`, so no code path in this codebase currently produces two subtasks sharing one chunk. SECV-02 must synthesize this scenario.
- Extracting `capture_diff`'s comparison logic to a shared library is in-scope mechanical work (not deferred).

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| XNODE-01b | `ValidateResults` actually diffs two subtasks' per-chunk hashes for the same chunk (fixing the concatenation bug) | "The Concatenation Bug" section pinpoints the exact defective line and explains why `CheckSubTaskResultHashes` never actually compares; "Recommended Fix Shape" gives a concrete replacement algorithm |
| XNODE-02 | On a chunk-hash mismatch, fall back to a bounded numeric comparison of the underlying chunk data before declaring a genuine divergence | "Blob-to-Chunk Slicing", "Tolerance Threshold Formula", "Extracting capture_diff's Comparison Logic" sections give the fetch mechanism, slicing approach, threshold formula, and shared-lib target |
| SECV-02 | A deliberately wrong/corrupted subtask result is still caught post-fix (counter-test) | "SECV-02 Counter-Test Wiring" section gives the concrete two-job pipeline construction, reusing SECV-01's fixture pattern plus the existing `ValidateResults` unit test's two-subtask/one-chunk structure |

</phase_requirements>

## Summary

Phase 15's three requirements are tightly coupled around one class, `ProcessingValidationCore`, and one call site, `SubTaskQueueAccessorImpl::FinalizeQueueProcessing`. The "concatenation bug" (XNODE-01b) is real and precisely located: `processing_validation_core.cpp` line 84 appends each subtask's chunk-hash bytes onto a shared per-chunk-key buffer instead of comparing them, so `CheckSubTaskResultHashes` only ever detects an intra-subtask hash collision against an already-merged blob — it structurally cannot detect "subtask A's chunk hash differs from subtask B's chunk hash for the same chunk," because by the time the check runs, A's and B's hash bytes have already been concatenated into one indistinguishable buffer.

The bounded numeric-tolerance fallback (XNODE-02) has three real sub-problems, all now traced through the code: (1) fetching the mismatched subtasks' output data, for which D-01 already locks the mechanism (`FileManager` load, same class used to save — confirmed a `LoadASync` precedent already exists at `ProcessingManager::GetSubCidForProc`, `ProcessingManager.cpp:1890-1918`); (2) recovering one chunk's byte range from the fetched blob, which this research found is **not uniformly possible** — output blobs are the *stitched* result of a (possibly overlapping) sliding-window loop internal to each processor (`processing_processor_mnn_float.cpp`, `processing_processor_mnn_volume.cpp`), and the wire protocol (`ProcessingChunk`) carries no offset/length field (the commented-out `offset`/`stride` fields in `SGProcessing.proto` were removed, not just unused); (3) deriving a tolerance threshold from Phase 14's `quantScale`/`byteQuantMode`, for which this research proposes a concrete formula below. `capture_diff.cpp`'s comparison primitives (`ComputeFloat32Diff`/`ComputeUint8Diff`) are cleanly extractable — this research traced the CMake link graph and found `processing_service` (which owns `ProcessingValidationCore`) already has a **zero-change transitive PUBLIC link path** to `sgprocmanagerquant` (`processing_service → ProcessingBase → SGProcessors → sgprocmanagerquant`, all PUBLIC), which is the exact template to replicate for a new diff-utility library.

SECV-02's counter-test is genuinely new territory, confirmed by grep: no production code path currently produces two subtasks sharing one chunk (`addvalidationsubtask=false` at the only real call site), so the test must synthesize this scenario itself, following the existing `ValidateResults` unit test's exact two-subtask/one-`ProcessingChunk` construction (`processing_subtask_queue_manager_test.cpp:395-440`) combined with SECV-01's exact correct-vs-corrupted job-pair pattern (`secv01_counter_test.cpp`).

**Primary recommendation:** Fix the concatenation bug by keying `chunks` on `chunkKey -> map<subtaskId, hashBytes>` (not a flattened byte vector) so genuine cross-subtask comparison becomes possible; extract `capture_diff`'s diff primitives into a new `sgprocmanagerdiff` static library colocated with `sgprocmanagerquant` and linked the same way; scope the tolerance fallback's byte-slicing to the tractable cases (single-chunk subtasks, and non-overlapping multi-chunk subtasks via uniform division) and explicitly document the overlapping-window case as an accepted limitation, mirroring the project's own VALD-01 override precedent; build SECV-02 as a new file that drives two real `ProcessingManager::Process()` runs (correct vs. corrupted, reusing SECV-01's exact fixture shape) and manually assembles two `SubTask`/`SubTaskResult` pairs sharing one `ProcessingChunk`, fed through `SubTaskQueueAccessorImpl`'s real public API.

## Architectural Responsibility Map

This is a C++ backend/distributed-processing system, not a web app — tiers are mapped to this project's own architectural layers.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Cross-subtask chunk-hash comparison (XNODE-01b) | Validation Core (`ProcessingValidationCore`) | Orchestration (`SubTaskQueueAccessorImpl`) | `ValidateResults` is the sole comparison authority; the accessor only calls it and acts on the outcome |
| Numeric-tolerance fallback comparison (XNODE-02) | Validation Core | Storage/Transport (`FileManager`/IPFS) | Comparison logic belongs in Validation Core; fetching bytes is a storage-tier concern the Validation Core must be handed a capability for, not perform itself |
| Tolerance threshold derivation from job schema | Validation Core (new helper) | Job Schema (`sgns::Parameter`) | Same schema-parsing convention as `ResolveQuantScale`/`ResolveByteQuantMode`, but a distinct concern (tolerance policy vs. quantization behavior) |
| Chunk-hash mismatch data fetch | Orchestration (`SubTaskQueueAccessorImpl`, already owns `m_localContext` io_context) | Storage/Transport (`FileManager::LoadASync`) | The accessor already owns a background io_context thread; Validation Core should be handed a fetch capability/context rather than construct its own I/O primitives |
| Counter-test pipeline (SECV-02) | Test harness (`test/src/processing_conformance_security`) | Orchestration | Must exercise the real `SubTaskQueueAccessorImpl` API surface, not bypass to `ValidateResults` directly, per D-05 |

## Standard Stack

No new external dependencies are introduced by this phase — it is entirely internal C++ restructuring within the existing `SuperGenius`/`SGProcessingManager` codebase. All "stack" items are existing in-repo libraries/targets.

### Core (existing, reused)

| Component | Location | Purpose | Why Standard (for this repo) |
|-----------|----------|---------|-------------------------------|
| `ProcessingValidationCore` | `SuperGenius/src/processing/processing_validation_core.{hpp,cpp}` | Owns `ValidateResults`, the fix target | Only comparison authority in the codebase |
| `FileManager` | referenced via `#include "FileManager.hpp"` in `ProcessingManager.cpp` | Async load/save of output blobs (local + IPFS dual-cache) | Already the sole save mechanism (`SaveASync`) and has a proven `LoadASync` precedent (`ProcessingManager::GetSubCidForProc`, lines 1890-1918) |
| `sgprocmanagerquant` (static lib) | `SGProcessingManager/src/util/quantization.{hpp,cpp}` | `ResolveQuantScale`/`ResolveByteQuantMode` (Phase 14) | Tolerance derivation must read the exact same schema `parameters` these already parse |
| `capture_diff`'s diff primitives | `SGProcessingManager/tools/capture/capture_diff.cpp:40-234` (unnamed namespace, CLI-only today) | `ComputeFloat32Diff`/`ComputeUint8Diff`/`ElementDiffStats` | The exact numeric-diff technique XNODE-02 must reuse, per D-03/D-04 |
| `boost::asio::io_context` | `SubTaskQueueAccessorImpl::m_localContext` (already a member, `processing_subtask_queue_accessor_impl.hpp:100-104`) | Background thread already running for this class | Reuse instead of adding a new io_context/thread |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Extending `SGProcessing.proto` to carry raw chunk bytes inline | Fetch via existing IPFS/`FileManager` path (D-01, locked) | Proto change is a wire-format break affecting every node in the network; explicitly rejected in CONTEXT.md |
| Reimplementing float/byte diff logic inside `processing_validation_core.cpp` | Extract `capture_diff`'s existing primitives into a shared lib | Reimplementing risks behavioral drift between the CLI tool's and the validator's notion of "close enough"; a shared lib guarantees they stay identical |
| Per-processor-type byte-slicing (deriving each MNN processor's stitching math) | Uniform-division slicing scoped to non-overlapping-window subtasks; document overlapping case as a known limitation | Full per-processor support is a large, open-ended effort disproportionate to this phase's pairwise scope; see "Blob-to-Chunk Slicing" |

## Package Legitimacy Audit

**Not applicable.** This phase adds zero new external packages/dependencies (npm, PyPI, Conan, vcpkg, or otherwise). All work is internal restructuring of existing C++ targets already present in the repository (`sgprocmanagerquant`, `SGProcessors`, `ProcessingBase`, `processing_service`, `sgproccapture`, `capture_diff`). The only new build artifact this research recommends is a new **internal** static library (tentatively `sgprocmanagerdiff`) built from code moved out of `capture_diff.cpp` — not a third-party package.

## The Concatenation Bug (XNODE-01b) — Exact Current Behavior

**Confirmed current content**, `SuperGenius/src/processing/processing_validation_core.cpp`, lines 76-86 (inside `ValidateResults`):

```cpp
for ( int chunkIdx = 0; chunkIdx < subTask.chunkstoprocess_size(); ++chunkIdx )
{
    auto it = chunks.insert(
        std::make_pair( subTask.chunkstoprocess( chunkIdx ).SerializeAsString(),
                        std::vector<uint8_t>() ) );
    const std::string &chunkHashBytes = itResult->second.chunk_hashes( chunkIdx );
    //it.first->second.push_back(itResult->second.chunk_hashes(chunkIdx));   // <- dead code, wrong types (would not compile: push_back of a std::string onto vector<uint8_t>)
    it.first->second.insert( it.first->second.end(), chunkHashBytes.begin(), chunkHashBytes.end() );  // <- line 84, the actual bug
}
```

**Why this silently passes a genuine mismatch:** `chunks` is `std::map<std::string, std::vector<uint8_t>>`, keyed by the serialized `ProcessingChunk` descriptor (chunk identity). When two different subtasks both reference the same chunk key, `chunks.insert(...)` on the second subtask finds the **existing** entry (insert on an existing key is a no-op for the value, `it.first` still points at the shared vector), and line 84 **appends** subtask B's chunk-hash bytes onto the end of the vector that already holds subtask A's chunk-hash bytes. The two hashes are never compared to each other at this point — they are concatenated into one longer, meaningless byte blob.

Then in `CheckSubTaskResultHashes` (lines 173-198), for **each subtask separately**, the (already-merged, already-corrupted) blob is turned into a single `std::string chunkHash` and inserted into a **per-call, per-subtask-scoped** `encounteredHashes` set (declared fresh inside the function each call). This only detects the case where the *same subtask* references two different chunk keys whose already-merged blobs happen to collide as strings — it can never catch "chunk X's hash from subtask A differs from chunk X's hash from subtask B," because both subtasks read from the exact same merged vector at that key. `[VERIFIED: codebase — SuperGenius/src/processing/processing_validation_core.cpp:53-98,173-198]`

**Confirming test that reproduces (and currently masks) this exactly:** `processing_subtask_queue_manager_test.cpp:395-440`'s `ValidateResults` test sets up two subtasks sharing one `ProcessingChunk` ("CHUNK_1"), but reuses **the same** `SGProcessing::SubTaskResult subTaskResult` object for both subtasks (`add_chunk_hashes("1")` once, then only `set_subtaskid("SUBTASK_2")` before re-emplacing) — so both subtasks report the literal identical hash string `"1"`. The test only proves the identical-hash case passes; it contains no case where the two subtasks report *different* hash bytes for the same chunk. `[VERIFIED: codebase]`

### Recommended Fix Shape

Change `chunks`'s value type from a flattened byte accumulator to a per-subtask map so genuine comparison becomes possible:

```cpp
// Before: std::map<std::string, std::vector<uint8_t>> chunks;
// After:
std::map<std::string, std::map<std::string /*subtaskId*/, std::string /*chunkHashBytes*/>> chunksBySubtask;
// ...
chunksBySubtask[subTask.chunkstoprocess(chunkIdx).SerializeAsString()][subTask.subtaskid()] =
    itResult->second.chunk_hashes(chunkIdx);
```

Then a genuine comparison pass over `chunksBySubtask`: for each chunk key with 2+ contributing subtasks, if all contributed hash strings are byte-identical, the chunk is valid; if they differ, invoke the numeric-tolerance fallback (XNODE-02) before deciding; if the fallback also fails, mark **all** contributing subtasks invalid (or use whatever tie-break policy the planner chooses — not specified in CONTEXT.md, flag as an open question below). This preserves the existing single-subtask-per-chunk case (map of size 1, trivially "valid") and adds the genuinely new multi-subtask-per-chunk comparison path XNODE-01b requires.

## Blob-to-Chunk Slicing (D-01's Open Research Question)

**What is actually saved:** `ProcessingManager.cpp:1514-1636`'s save loop operates per **output** (`outputs[outputIndex]`, one `source_uri_param` per declared job output), not per chunk. `bufferData[dataIndex]` is the processor's full output buffer for that output — already fully assembled/stitched. There is **no separate save-per-chunk** anywhere in this code path. `[VERIFIED: codebase — ProcessingManager.cpp:1514-1636]`

**What "chunk" means at the point chunk hashes are computed:** In `MNN_Float::StartProcessing` (`processing_processor_mnn_float.cpp:168-360`, representative of the MNN processor family), the processor computes a set of sliding-window "patches" via `ComputeWindowStarts(length, patchLength, stride)`, and emits **one chunk hash per window** (`chunkhashes.emplace_back(...)`, line 321) computed from that window's own raw output (`data`, `dataSize` bytes) — **before** stitching. But the final saved buffer (`stitchedOutput`) is a **weighted average of overlapping windows** (`stride` defaults to `patchLength` when `chunk_stride` is omitted from the job schema, i.e. **non-overlapping is the schema default**, but overlapping is fully supported and is exactly what the existing SECV-01 MNN fixture uses: `"dimensions": {"width": 512, "block_len": 64, "chunk_stride": 32}` — stride 32 < patch length 64, genuinely overlapping). `[VERIFIED: codebase — processing_processor_mnn_float.cpp:168-360; secv01_counter_test.cpp:52]`

`processing_processor_mnn_volume.cpp` (the `tex3d`/`spleen_ct_seg` processor STATE.md's "New evidence for QUANT-CFG-01" paragraph discusses) uses the same weighted-stitching pattern (`stitchedOutput`/`stitchedWeights`, lines 432-572). `[VERIFIED: codebase]`

**Consequence:** a chunk's bytes cannot be generically recovered from the final saved blob when windows overlap — the final blob has already blended adjacent chunks' contributions via `stitchedOutput[dstIdx] += data[...]` followed by `/= weight`. The wire protocol offers no help either: `ProcessingChunk` (`SGProcessing.proto:39-48`) has only `chunkid` and `n_subchunks`; the `offset`/`subchunk_width`/`subchunk_height`/`stride`/`line_stride` fields exist **only as comments** — they were designed for and then removed/never implemented, confirming no offset metadata is available on the wire today. `[VERIFIED: codebase — SGProcessing.proto:39-48]`

**Recommendation — scope the slicing to tractable cases, document the rest as a known limitation:**

1. **Single-chunk subtasks** (`subTask.chunkstoprocess_size() == 1`): the entire fetched blob *is* the chunk's data — no slicing needed at all. This is the simplest, lowest-risk case and should be the primary target for this phase's fixtures (including SECV-02's).
2. **Multi-chunk, non-overlapping subtasks** (`chunk_stride` unset, or `chunk_stride >= block_len`): windows don't overlap, so — for single-channel outputs — chunk `i`'s bytes are the contiguous range `[i * (blobBytes / numChunks), (i+1) * (blobBytes / numChunks))` (uniform division). **Caveat (flag to planner):** if `outputChannels > 1`, the MNN stitching layout is channel-major (`dstIdx = c*length + outIndex`), so a single chunk's data for a multi-channel output is **not one contiguous range** but `outputChannels` separate contiguous sub-ranges (one per channel, each `patchLength` elements at `channel*length + chunkIndex*patchLength`). The uniform-division formula above is only exactly correct for single-channel outputs; document this explicitly rather than silently mis-slicing multi-channel data.
3. **Overlapping-window subtasks** (`chunk_stride < block_len`): exact single-chunk byte recovery from the final stitched blob is **not generally possible** without re-deriving each processor's own stitching math. Recommend the planner either (a) scope SECV-02's/XNODE-02's fixtures to case 1 or 2 above (this phase's own SC framing is pairwise/synthetic, not a live multi-node fixture, so this is a legitimate scope choice), or (b) explicitly accept and document this as an out-of-scope gap for overlapping-window jobs, mirroring the project's own precedent of accepting a partial gap with a written override (VALD-01/13-VERIFICATION.md).

This is genuinely the least-certain area of this research — flagged in Open Questions and the Assumptions Log below.

## Tolerance Threshold Formula (D-03/D-04)

**The problem:** `ResolveQuantScale`/`ResolveByteQuantMode` (`quantization.cpp:32-84`) return a value in **both** the "job declared a valid value" and "nothing valid was declared, using the fallback" cases — the function's return type cannot distinguish them. D-04 requires different tolerance-derivation behavior in each case (grid-derived vs. fixed-constant), so `ValidateResults` needs a way to tell them apart. **Recommendation:** do not modify `ResolveQuantScale`/`ResolveByteQuantMode` (Phase 14 code with 21 already-wired call sites per STATE.md) — instead add two new, additive helper functions in the new diff-utility location (see next section) that replicate the same parameter-lookup loop but return the **derived threshold directly**, encapsulating the D-03/D-04 branch internally:

```cpp
// Proposed additions, e.g. SGProcessingManager/include/util/diff_utils.hpp
namespace sgns::sgprocmanagerdiff
{
    // D-03: if "quantScale" is validly declared, derive a grid-step-based bound.
    // D-04: otherwise fall back to capture_diff's kDefaultFloatRelativeThreshold (1e-4).
    double ResolveFloatToleranceRelative( const std::vector<sgns::Parameter> *parameters );

    // D-03: if "byteQuantMode" is validly declared (N in [0,8]), derive (1<<N)-1.
    // D-04: otherwise fall back to capture_diff's kDefaultByteAbsoluteThreshold (1).
    int ResolveByteToleranceAbsolute( const std::vector<sgns::Parameter> *parameters );
}
```

**Proposed formula — float (grid-step-based, per D-03's own wording):** `QuantizeFloatBuffer` rounds via `q = round(x*S)/S`, so the quantization grid step is `1/S`. Two independently-quantized values from different machines can, in the worst case, land on adjacent grid cells (the exact chunk-10 boundary-tie-break scenario v2.1 diagnosed), so an absolute-tolerance bound of **one full grid step, `1.0f/S`,** is the minimum defensible margin; this research proposes **`floatTolerance = 2.0f / S`** (two grid steps) as a slightly safer default, mirroring the project's own established practice of keeping "one full step of margin above the confirmed boundary" (the same philosophy Phase 13 used when choosing `S=2^15` over the failing `S=2^14`, per `quantization.cpp`'s own doc comments). **This multiplier (2x vs 1x) is `[ASSUMED]`** — the planner should treat it as a tunable starting point, not a locked value, and ideally validate it against a chunk-10-style boundary case if one becomes available. When `quantScale` is not validly declared, fall back to `capture_diff`'s existing `kDefaultFloatRelativeThreshold = 1e-4` **relative** threshold (matching `ComputeFloat32Diff`'s existing relative-delta check, not an absolute one — the fallback formula and the derived formula use different metrics, which is consistent with D-04's framing that the fallback is `capture_diff`'s pre-existing, already-relative-based check).

**Proposed formula — byte (`byteQuantMode`/`maskBits`):** `QuantizeByteBuffer` masks the low `N` bits of every byte to zero, so two values that quantize to the same masked value can differ by up to `(1 << N) - 1` in their raw (unmasked) form. This research proposes **`byteTolerance = (1 << maskBits) - 1`** when `maskBits > 0` is validly declared, falling back to `capture_diff`'s existing `kDefaultByteAbsoluteThreshold = 1` when `byteQuantMode` is absent/invalid (matching `ComputeUint8Diff`'s existing absolute-delta check). `[ASSUMED — reasoned from QuantizeByteBuffer's masking semantics, not empirically validated this session]`

**Comparison policy — recommend "any exceeding element still fails," not an averaged/percentage bar:** `capture_diff`'s `ElementDiffStats::percentExceedingThreshold` computes a *percentage* of elements exceeding threshold, for reporting. For a pass/fail gate feeding `ValidateResults`, this research recommends treating a chunk as tolerant-equal **only if zero elements exceed the derived threshold** (i.e., `percentExceedingThreshold == 0.0`, equivalently `maxAbsDelta`/`maxRelDelta` ≤ threshold) — not "most elements agree." A percentage-based bar risks the exact failure mode SECV-02 exists to catch: a corrupted result differing substantially in a small fraction of elements could otherwise slip through. This is a conservative default the planner can loosen later if empirical data warrants it.

## Extracting `capture_diff`'s Comparison Logic (Shared Lib Location)

**Current state, verified:** `ComputeFloat32Diff`/`ComputeUint8Diff`/`ElementDiffStats`/`UlpDistanceFloat`/`OrderedFloatBits` live in an unnamed namespace inside `capture_diff.cpp` (lines 40-234), which CMake builds only as `add_executable(capture_diff ...)` (`tools/capture/CMakeLists.txt:38-46`) — not a linkable target. `[VERIFIED: codebase]`

**Recommended target — a new static library colocated with `sgprocmanagerquant`,** since this research traced the exact CMake link graph `ProcessingValidationCore` needs to reach:

```
processing_service  (owns processing_validation_core.cpp; SuperGenius/src/processing/CMakeLists.txt)
  --PUBLIC--> ProcessingBase        (SGProcessingManager/src/processingbase/CMakeLists.txt)
    --PUBLIC--> SGProcessors        (SGProcessingManager/src/processors/CMakeLists.txt)
      --PUBLIC--> sgprocmanagerquant  (SGProcessingManager/src/util/CMakeLists.txt)  <- already reachable, zero changes needed
```

This chain is **already fully PUBLIC end-to-end** — `processing_validation_core.cpp` can `#include "util/quantization.hpp"` today with **no CMakeLists.txt changes at all** (confirmed by reading all four CMakeLists.txt files in the chain). The identical mechanism should be used for the new diff-utility library:

1. **New files:** `SGProcessingManager/include/util/diff_utils.hpp` + `SGProcessingManager/src/util/diff_utils.cpp` (same directory as `quantization.hpp`/`.cpp`).
2. **New CMake target**, added to the existing `SGProcessingManager/src/util/CMakeLists.txt` (same file that already declares `sgprocmanagerquant`):
   ```cmake
   add_library(sgprocmanagerdiff
       diff_utils.cpp
       ../../include/util/diff_utils.hpp
   )
   target_include_directories(sgprocmanagerdiff PUBLIC
       $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/../../include>
       $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/../../generated>
       $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/SGProcessingManager/generated>
   )
   target_link_libraries(sgprocmanagerdiff
       PUBLIC
       nlohmann_json::nlohmann_json   # only if the Parameter-lookup helpers need it; core diff math needs no deps
   )
   sgnus_install(sgprocmanagerdiff)
   ```
3. **Wire into `SGProcessors`** (`SGProcessingManager/src/processors/CMakeLists.txt`): add `sgprocmanagerdiff` to the existing `PUBLIC` link list (same list that already contains `sgprocmanagerquant`) — this makes it transitively reachable by `processing_service`/`ProcessingValidationCore` via the exact chain verified above, with no other CMakeLists.txt touched.
4. **Update `capture_diff`'s CMakeLists.txt** (`tools/capture/CMakeLists.txt:38-46`): add `sgprocmanagerdiff` to `capture_diff`'s `target_link_libraries`, and replace the unnamed-namespace definitions in `capture_diff.cpp` with calls into the new shared functions (`#include "util/diff_utils.hpp"`), removing the duplicated logic so both consumers share one implementation.

**Why `SGProcessors` and not `ProcessingBase` directly:** `sgprocmanagerquant` is already wired through `SGProcessors` (not `ProcessingBase` directly), so following the same wiring point for `sgprocmanagerdiff` keeps the two schema-parameter-driven utilities (quantization, tolerance-diff) consistent in how they're exposed, and avoids introducing a second, differently-shaped dependency path for what is conceptually a sibling utility.

## `ValidateResults` Signature/Threading Change

**Current signature** (`processing_validation_core.hpp:47-49`):
```cpp
outcome::result<void> ValidateResults( const SGProcessing::SubTaskCollection &subTasks,
                                       const std::map<std::string, SGProcessing::SubTaskResult> &results,
                                       std::set<std::string> &invalidSubTaskIds );
```

**Sole call site** (`processing_subtask_queue_accessor_impl.cpp:327`, inside `FinalizeQueueProcessing`):
```cpp
auto validate_res = m_validationCore.ValidateResults( subTasks, m_results, invalidSubTaskIds );
```

**Two new capabilities `ValidateResults` needs, and where they can come from:**

1. **Job schema `parameters` access** (for D-03/D-04's `quantScale`/`byteQuantMode` lookup). **Problem confirmed by this research:** the parsed job schema (`sgns::SgnsProcessing processing_`, with `.get_parameters()`) lives only inside `ProcessingManager` (`ProcessingManager.cpp:1231-1232`, `831-837`) — a **different class**, in a **different module** (`SGProcessingManager`), than `SubTaskQueueAccessorImpl`/`ProcessingValidationCore` (`SuperGenius/src/processing`). Neither `SubTaskQueueAccessorImpl` nor `ProcessingValidationCore` has ever needed access to job-level `parameters` before this phase. **Recommendation:** rather than threading the raw `std::vector<sgns::Parameter>*` across this module boundary (which would require `ProcessingValidationCore`/`SubTaskQueueAccessorImpl` to newly depend on `Parameter.hpp`/`ParameterType.hpp` and on whoever owns the parsed job schema at accessor-construction time), resolve the two primitives (`float scale`, `int maskBits`) **once**, wherever the caller already has access to the job's parsed schema (this is `ProcessingManager`-adjacent code, e.g. `ProcessingNode`/`GeniusNode.cpp`, which already constructs `SubTaskQueueAccessorImpl` — see `processing_node.cpp:144`), and pass the two resolved primitives into `SubTaskQueueAccessorImpl` via a **new setter mirroring the existing `setMirrorResultCallback`/`setBitswap` pattern** (`processing_subtask_queue_accessor_impl.hpp:58,61`; `processing_node.cpp:107-130` shows the exact forwarding pattern already used for both). This keeps `ProcessingValidationCore` free of any new dependency on `sgns::Parameter` — it only ever sees plain `float`/`int` tolerance inputs.
2. **A data-fetch capability** (for D-01's mismatch-path IPFS fetch). **Reuse `SubTaskQueueAccessorImpl::m_localContext`** — already a `std::shared_ptr<boost::asio::io_context>` member with its own dedicated background thread (`m_localThread`/`m_localWorkGuard`, `processing_subtask_queue_accessor_impl.hpp:100-104`), used today for periodic state broadcasting. Pass this `io_context` (or a small fetch-capability struct wrapping it + a `FileManager`-based load function) into `ValidateResults` as a new parameter, and inside the mismatch path call `FileManager::GetInstance().LoadASync(url, ...)` — **directly precedented** by `ProcessingManager::GetSubCidForProc` (`ProcessingManager.cpp:1890-1918`), which already does exactly this kind of "fire an async `LoadASync`, then block until the callback populates a caller-owned buffer" pattern. The existing **synchronous-wait-for-async** convention already used in `ProcessingManager.cpp`'s own save loop (`ioc->reset(); ioc->run();` after firing `SaveASync`, lines 1621-1634) is the established idiom to mirror for a *blocking* mismatch-path fetch inside an otherwise-synchronous `ValidateResults` call (this repo's convention favors blocking-on-a-dedicated-io_context over making the whole call chain asynchronous) — consistent with CONTEXT.md's note that sync-vs-async is "a normal implementation choice," not a locked decision.

**Proposed new signature (illustrative — exact shape is Claude's Discretion per CONTEXT.md):**
```cpp
outcome::result<void> ValidateResults(
    const SGProcessing::SubTaskCollection &subTasks,
    const std::map<std::string, SGProcessing::SubTaskResult> &results,
    std::set<std::string> &invalidSubTaskIds,
    float floatQuantScale,                              // resolved once by the caller (D-03/D-04)
    int   byteQuantMaskBits,                             // resolved once by the caller (D-03/D-04)
    std::shared_ptr<boost::asio::io_context> fetchContext // for mismatch-path IPFS fetch (D-01/D-02); may be nullptr to skip tolerance fallback entirely (fail-closed on mismatch, current behavior)
);
```

`FinalizeQueueProcessing` (the sole call site) would pass `m_localContext` and the two new member fields the accessor gains from the new setter above.

## SECV-02 Counter-Test Wiring (D-05)

**Confirmed: no production code path exercises the two-subtasks-share-one-chunk scenario today.** `ProcessTaskSplitter::SplitTask`'s `addvalidationsubtask` parameter (`processing_tasksplit.cpp:44-98`) is the only code that ever creates a second subtask sharing a chunk (it copies chunk 0 of the main subtask into a `validationSubtask`), but its **sole real call site**, `GeniusNode.cpp:2023-2028`, always passes `addvalidationsubtask=false`. `[VERIFIED: codebase — grep confirms no other call sites pass `true`]` This directly corroborates XNODE-01c being out of scope: the orchestration to actually produce redundant same-chunk assignments doesn't exist yet.

**Two existing patterns to combine:**

1. **`secv01_counter_test.cpp`'s job-pair pattern** (lines 34-198): two inline JSON job definitions, identical except the model file pointed to (correct `float_model.mnn` vs. a byte-perturbed corrupted copy fixture), each run through a full `ProcessingManager::Create()` + `Process()` call, each producing its own `chunkhashes` vector (populated by the processor itself, one hash per processing window) and `output_locations`.
2. **`processing_subtask_queue_manager_test.cpp:395-440`'s two-subtask/one-chunk `SubTaskCollection`+`results` construction** — proves the minimal protobuf shape needed to reach `ValidateResults` with "two subtasks, one shared `ProcessingChunk` key."

**Recommended construction for SECV-02 (new file, e.g. `SuperGenius/test/src/processing_conformance_security/secv02_counter_test.cpp`):**

1. Run the correct job and the corrupted job exactly as `secv01_counter_test.cpp` does (`ProcessingManager::Create()` + `Process()` twice), capturing each run's real `chunkhashes` output vector (not synthetic strings) — this keeps the test's mismatch bytes genuine, not fabricated, exercising the real quantization+hashing pipeline SECV-01 already trusts.
2. Build two synthetic `SGProcessing::SubTask` protobuf objects (`SUBTASK_CORRECT`, `SUBTASK_CORRUPTED`) that both reference the **same single `ProcessingChunk`** (same `chunkid`/`n_subchunks`, so `SerializeAsString()` produces the identical map key) — mirroring `processing_subtask_queue_manager_test.cpp`'s exact chunk-sharing setup, but this time giving each subtask a **different, real** chunk_hash pulled from its own run's `chunkhashes[0]`.
3. Feed these through `SubTaskQueueAccessorImpl`'s real public API (D-05 requires exercising the actual subtask-result validation path, not calling `ValidateResults` directly): construct a `SubTaskQueueAccessorImpl` locally (mirroring how `processing_subtask_queue_manager_test.cpp`'s other tests instantiate `ProcessingSubTaskQueueManager` directly with a local `io_context` and stub channel, no real P2P pubsub needed), call `AssignSubTasks`/`CompleteSubTask` (or whatever the finalized public surface is after this phase's signature change) with each subtask's real result, and assert that `ValidateResults`'s fixed comparison — hash-compare (XNODE-01b) plus tolerance fallback (XNODE-02) acting together — still flags the corrupted subtask (`invalidSubTaskIds` non-empty, `validate_res.has_error()`), proving the combined mechanism isn't loose enough to also mask the genuine corruption.
4. **Keep this fixture in the single-chunk or non-overlapping-multi-chunk case** (per "Blob-to-Chunk Slicing" above) so the tolerance fallback's byte-slicing is exact, not approximated — e.g., a 1-chunk MNN float job (`block_len == width`, no `chunk_stride`), distinct from SECV-01's own overlapping-window fixture.

**Separately (smaller, additive):** consider also extending the existing `processing_subtask_queue_manager_test.cpp:395-440` `ValidateResults` test with one more case where `SUBTASK_2` reports a **different** `chunk_hashes` string than `SUBTASK_1` (today's test only covers identical hashes) and asserting the fixed code now flags it — this is a fast, narrow regression test for XNODE-01b's fix in isolation, complementary to (not a replacement for) SECV-02's full-pipeline test.

## Architecture Patterns

### System Architecture Diagram

```
 Two SubTaskResults arrive (one per subtask, real network or synthesized in test)
        │
        ▼
 SubTaskQueueAccessorImpl::OnResultReceived / CompleteSubTask
        │  (accumulates into m_results map)
        ▼
 SubTaskQueueAccessorImpl::FinalizeQueueProcessing   (all subtasks processed)
        │
        ▼
 ProcessingValidationCore::ValidateResults( subTasks, results, invalidSubTaskIds,
                                             floatScale, byteMaskBits, fetchContext )
        │
        ├─ Build chunksBySubtask: chunkKey -> { subtaskId -> chunkHashBytes }   (fixed, no concatenation)
        │
        ├─ For each chunk key with 2+ contributing subtasks:
        │     ├─ hashes identical across subtasks?  ──yes──▶  chunk OK
        │     └─ hashes differ                        │
        │           ▼
        │     Mismatch path (D-02: only reached here, not on the happy path)
        │           │
        │           ├─ Resolve tolerance (ResolveFloatToleranceRelative /
        │           │   ResolveByteToleranceAbsolute — D-03 grid-derived or D-04 fixed fallback)
        │           │
        │           ├─ Fetch each subtask's output blob via FileManager::LoadASync
        │           │   (keyed by ipfs_results_data_id / source_uri_param, D-01) — using
        │           │   fetchContext (SubTaskQueueAccessorImpl's existing m_localContext)
        │           │
        │           ├─ Slice this chunk's byte range out of each blob
        │           │   (trivial if 1-chunk subtask; uniform-division if non-overlapping
        │           │    multi-chunk; documented limitation if overlapping windows)
        │           │
        │           └─ ComputeFloat32Diff / ComputeUint8Diff (extracted from capture_diff,
        │               now in sgprocmanagerdiff) within tolerance?
        │                   ├─ yes ──▶ chunk OK (tolerant match)
        │                   └─ no  ──▶ mark contributing subtasks invalid
        ▼
 invalidSubTaskIds populated  →  FinalizeQueueProcessing rejects/re-queues invalid subtasks,
                                  or finalizes TaskResult if all valid
```

### Recommended Project Structure (new files only; existing structure unchanged)

```
SGProcessingManager/
├── include/util/
│   ├── quantization.hpp        # existing (Phase 14, unmodified)
│   └── diff_utils.hpp          # NEW — ComputeFloat32Diff/ComputeUint8Diff (moved from capture_diff.cpp)
│                                #        + ResolveFloatToleranceRelative/ResolveByteToleranceAbsolute (new)
├── src/util/
│   ├── quantization.cpp        # existing, unmodified
│   ├── diff_utils.cpp          # NEW
│   └── CMakeLists.txt          # add sgprocmanagerdiff target here (existing file, edited)
├── src/processors/
│   └── CMakeLists.txt          # add sgprocmanagerdiff to SGProcessors' PUBLIC link list (existing file, edited)
└── tools/capture/
    ├── capture_diff.cpp        # edited: remove unnamed-namespace defs, #include "util/diff_utils.hpp"
    └── CMakeLists.txt          # add sgprocmanagerdiff to capture_diff's link list (existing file, edited)

SuperGenius/src/processing/
├── processing_validation_core.hpp   # edited: new ValidateResults signature
├── processing_validation_core.cpp   # edited: fix concatenation bug, add tolerance fallback
└── processing_subtask_queue_accessor_impl.{hpp,cpp}  # edited: new setter for resolved
                                                       #  scale/maskBits, forward m_localContext

SuperGenius/test/src/processing_conformance_security/
└── secv02_counter_test.cpp     # NEW — full pipeline counter-test (D-05)

SuperGenius/test/src/processing/
└── processing_subtask_queue_manager_test.cpp  # optionally extended with a genuine-mismatch case
```

### Anti-Patterns to Avoid

- **Comparing already-merged/concatenated data:** the exact bug being fixed. Any refactor must ensure each subtask's contribution to a shared chunk key stays independently addressable until the comparison actually runs.
- **Silently mis-slicing multi-channel output data:** applying the single-channel uniform-division formula to a multi-channel buffer without the channel-major correction will silently compare the wrong bytes and could mask or manufacture mismatches. Document the channel-count assumption explicitly wherever slicing is implemented.
- **Fetching on the happy path:** D-02 is explicit — only reach into IPFS when a hash comparison already disagrees. Don't restructure `ValidateResults` in a way that fetches unconditionally "to be safe."
- **Modifying `ResolveQuantScale`/`ResolveByteQuantMode`'s existing signatures:** these have 21 already-wired call sites per STATE.md's Phase 14 history; add new, separate functions for tolerance-threshold derivation instead of changing return types/adding out-params to the existing resolvers.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Float/byte numeric divergence measurement | A new ad hoc diff routine inside `processing_validation_core.cpp` | Extracted `ComputeFloat32Diff`/`ComputeUint8Diff` from `capture_diff.cpp` | Guarantees the validator's notion of "close enough" never silently diverges from the CLI tool's (`capture_diff`) — both v2.1's empirical validation work and this phase's runtime check must agree |
| Fetching subtask output data | A new IPFS client call, a new CID-parsing routine | `FileManager::GetInstance().LoadASync(...)`, precedented at `ProcessingManager::GetSubCidForProc` | D-01 explicitly locks this; a second fetch mechanism would duplicate `ValidateResultData`'s existing scheme validation and the dual-cache save logic's assumptions |
| Async-to-sync bridging inside a synchronous validation call | A custom promise/future or busy-wait loop | The existing `ioc->reset(); ioc->run();` blocking-drain idiom already used in `ProcessingManager.cpp`'s save loop | Established, already-reviewed pattern in this exact codebase for "fire async I/O, then block until it completes" from synchronous code |

**Key insight:** every piece of numeric-comparison and data-fetch machinery this phase needs already exists somewhere in the codebase (v2.1's `capture_diff`, `ProcessingManager`'s save/load paths) — the actual work is almost entirely *plumbing and extraction*, not new algorithm design. The one genuinely new algorithmic risk is the tolerance-threshold formula (D-03), which has no existing precedent to copy and is flagged `[ASSUMED]` throughout.

## Common Pitfalls

### Pitfall 1: Fixing the comparison but not the underlying data structure

**What goes wrong:** Patching line 84 in isolation (e.g., changing `insert` to a comparison against the existing accumulated bytes) without restructuring `chunks`'s value type risks a partial fix that still can't cleanly attribute "which subtask contributed which hash" when more than 2 subtasks eventually share a chunk (XNODE-01c's future N-way case).
**Why it happens:** The flattened `vector<uint8_t>` accumulator was presumably intended as a append-once buffer for a single subtask's multiple hash bytes, and reused (incorrectly) across subtasks.
**How to avoid:** Restructure to `chunkKey -> {subtaskId -> hashBytes}` (see "Recommended Fix Shape") rather than patching the accumulation logic in place.
**Warning signs:** Any fix that still touches a single shared `vector<uint8_t>` per chunk key across multiple subtasks.

### Pitfall 2: Treating `ipfs_results_data_id` as always populated

**What goes wrong:** The mismatch-path fetch assumes `ipfs_results_data_id` is always a valid `ipfs://` CID list, but `ValidateResultData` (`processing_subtask_queue_accessor_impl.cpp:515-524`) already handles the case where it's empty (`return true; // No IPFS data to validate`) — meaning some results may have no fetchable data at all (e.g., non-IPFS local-only outputs).
**Why it happens:** Not every job output necessarily uses the `ipfs://` scheme; `outputUrl` could be `file://` or another scheme (`ProcessingManager.cpp:1540-1544`'s `IsUrl`/`urlPrefix` checks already handle multiple schemes).
**How to avoid:** The tolerance fallback must handle "no fetchable data" by failing closed (treat as genuine mismatch, current/safe behavior) rather than crashing or silently passing.
**Warning signs:** Any implementation that dereferences `ipfs_results_data_id` without an empty/scheme check mirroring `ValidateResultData`'s existing pattern.

### Pitfall 3: Overlapping-window chunk slicing silently producing wrong comparisons

**What goes wrong:** Applying uniform-division slicing to an overlapping-window subtask (`chunk_stride < block_len`) will extract the wrong bytes (a mix of two adjacent windows' stitched-and-averaged contributions), potentially making a genuinely different chunk look "tolerant" or a genuinely-matching chunk look different.
**Why it happens:** The stitching math (`stitchedOutput[dstIdx] += data[srcIdx]`, then `/= weight`) is not invertible to recover a single window's contribution once averaged.
**How to avoid:** Detect the overlapping case (`chunk_stride < block_len` in the job schema) and explicitly skip/degrade to fail-closed (or document as an accepted gap) rather than attempt slicing.
**Warning signs:** SECV-02 or XNODE-02 fixtures reusing SECV-01's own overlapping-window fixture (`chunk_stride: 32, block_len: 64`) without adjusting for this.

## Code Examples

### Existing `LoadASync` precedent for the mismatch-path fetch

```cpp
// Source: SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp:1890-1918
void ProcessingManager::GetSubCidForProc( std::shared_ptr<boost::asio::io_context> ioc,
                                          std::string                              url,
                                          std::shared_ptr<std::vector<char>>       results )
{
    auto modeldata = FileManager::GetInstance().LoadASync(
        url,
        false,
        false,
        ioc,
        [this, results]( outcome::result<std::shared_ptr<std::pair<std::vector<std::string>,
                                                                    std::vector<std::vector<char>>>>> buffers )
        {
            if ( buffers )
            {
                if ( results )
                {
                    results->insert( results->end(), buffers.value()->second[0].begin(),
                                     buffers.value()->second[0].end() );
                }
            }
            else
            {
                m_logger->error( "Failed to obtain processing source: {}", buffers.error().message() );
            }
        },
        "file" );
}
```

### Existing blocking-drain idiom (fire async I/O from synchronous code, then block)

```cpp
// Source: SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp:1621-1634
if ( hasSaves )
{
    ioc->reset();
    ioc->run();
    // After async IO completes, collect the save locations
    for ( size_t i = 0; i < locationPtrs.size(); ++i )
    {
        if ( locationPtrs[i] && !locationPtrs[i]->empty() )
        {
            output_locations[i] = *locationPtrs[i];
        }
    }
}
```

### Existing setter pattern to mirror for threading resolved scale/maskBits into the accessor

```cpp
// Source: SuperGenius/src/processing/processing_node.cpp:107-130
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

## State of the Art

| Old Approach | Current/Recommended Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Concatenate chunk-hash bytes across subtasks into one shared buffer | Keep per-subtask hash bytes independently addressable per chunk key, compare explicitly | This phase (XNODE-01b) | Cross-node hash mismatches will finally be detected instead of silently passing |
| Bit-exact hash equality as the sole correctness bar | Hash equality with a bounded numeric-tolerance fallback | This phase (XNODE-02) | Absorbs the exact chunk-10-style boundary tie-break v2.1 diagnosed, without loosening enough to mask genuine corruption (proven by SECV-02) |
| `capture_diff`'s diff logic as a CLI-only, non-reusable tool | Shared static library (`sgprocmanagerdiff`) linkable from both the CLI tool and runtime validation | This phase | One implementation, no behavioral drift between offline diagnostic tooling and runtime validation |

**Deprecated/outdated:** none — this phase extends rather than replaces prior mechanisms; `capture_diff.cpp`'s CLI entry point (`main()`) and its JSON-report behavior remain unchanged, only its internal helper functions move to a shared location.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Float tolerance formula `2.0f / S` (two grid steps) is an adequate margin | Tolerance Threshold Formula | If too tight, genuine cross-hardware boundary ties could still be misclassified as mismatches (re-creating the original chunk-10 problem); if too loose, could reduce SECV-02's ability to catch subtle corruption. Should be validated against a real boundary-tie fixture if one becomes available, similar to how Phase 13 bracketed `S` via `SECV-01`. |
| A2 | Byte tolerance formula `(1 << maskBits) - 1` | Tolerance Threshold Formula | If wrong, byte-quantized jobs' tolerance fallback could be too strict (false mismatches) or too loose (masking corruption); no empirical byte-quantized fixture currently exercises this formula |
| A3 | Uniform-division byte-slicing is exact only for single-channel, non-overlapping-window outputs; overlapping-window slicing is not generally possible without per-processor stitching math | Blob-to-Chunk Slicing | If the planner scopes XNODE-02/SECV-02 fixtures to overlapping-window jobs anyway, the tolerance fallback could silently compare the wrong bytes, invalidating the whole mechanism's correctness guarantee |
| A4 | Comparison policy should be "zero elements may exceed threshold" (not a percentage-based bar) | Tolerance Threshold Formula | If the planner instead adopts a percentage-based bar, SECV-02's corrupted-result detection could become less reliable depending on how localized the corruption is within a chunk |
| A5 | Resolving `quantScale`/`byteQuantMode` once at `SubTaskQueueAccessorImpl` construction time (via a new setter) is sufficient, rather than per-`ValidateResults`-call re-resolution | `ValidateResults` Signature/Threading Change | If a job's parameters can change mid-processing (not observed in this codebase, but not proven impossible), a construction-time-only resolution could go stale; low risk given jobs are immutable once split into subtasks in the current architecture |

**If this table is empty:** N/A — see entries above; all are reasoned proposals from verified code, not verified against an authoritative external source, since this is bespoke in-repo protocol/algorithm design with no external "standard" to cite.

## Open Questions

1. **Tie-break policy when a chunk mismatch survives the tolerance fallback with more than 2 contributing subtasks.**
   - What we know: this phase's scope is explicitly pairwise (2 subtasks per chunk); CONTEXT.md and ROADMAP SC1-5 never discuss 3+.
   - What's unclear: whether the fix should hard-code a 2-subtask assumption or leave room for N-way (deferred to XNODE-01c).
   - Recommendation: implement the comparison generically over however many subtasks share a chunk key (a map, not a fixed pair), but only test the pairwise case this phase — avoids over-engineering while not foreclosing XNODE-01c's future needs.

2. **Whether the overlapping-window slicing limitation (Pitfall 3) needs an explicit written override in a VERIFICATION.md, mirroring VALD-01's precedent.**
   - What we know: the project has an established pattern of explicitly documenting accepted gaps (VALD-01's MNN 12/15-chunk override).
   - What's unclear: whether this phase's planner/verifier will consider the overlapping-window gap material enough to require the same treatment, or whether scoping fixtures to non-overlapping cases sidesteps the need entirely.
   - Recommendation: plan should explicitly state which case(s) SECV-02's and XNODE-02's fixtures exercise (recommend non-overlapping/single-chunk, per Pitfall 3), and if overlapping windows are ever later required, treat it as a follow-up phase rather than silently extending this phase's guarantee.

3. **Exact wiring point for resolving `quantScale`/`byteQuantMode` and calling the new `SubTaskQueueAccessorImpl` setter.**
   - What we know: `SubTaskQueueAccessorImpl` is constructed at `ProcessingNode::Initialize()` (`processing_node.cpp:144`); the parsed job schema (`processing_.get_parameters()`) lives inside `ProcessingManager`, a different object with no obvious existing reference from `ProcessingNode`.
   - What's unclear: whether `ProcessingNode`/`GeniusNode.cpp` already has (or can easily obtain) a reference to the same `sgns::SgnsProcessing`/`ProcessingManager` instance at the point `Initialize()` runs, or whether this requires additional constructor-parameter threading through `GeniusNode.cpp`.
   - Recommendation: the planner should trace `GeniusNode.cpp`'s full call sequence around `taskSplitter.SplitTask`/`ProcessingNode::Initialize` (both appear to run in the same function, `GeniusNode.cpp:1990-2030` region and nearby) to confirm the job schema/parameters are in scope at that point — this research did not trace that specific call sequence exhaustively.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| CMake | Build system for all new/edited targets | ✓ | 3.29.2 | — |
| Git | Version control | ✓ | 2.48.1 | — |
| Existing SuperGenius/SGProcessingManager build tree | Compiling the new `sgprocmanagerdiff` target and edited files | ✓ (build/ directory present with Windows/OSX/Linux/Android/iOS subdirs) | — | Follow existing `Thirdparty/SuperGenius` build convention: build in `build/<PLATFORM>/<BUILDTYPE>` via CMake, no isolated scratch build |

No new external tools/services are required — this phase is pure C++ source/CMake work within an already-configured build tree.

## Security Domain

`security_enforcement` is enabled in `.planning/config.json` (`security_asvs_level: 1`, `security_block_on: "high"`), so this section is required.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V1 Architecture (trust boundaries) | yes | Subtask results originate from other (potentially untrusted/Byzantine) nodes — `ValidateResults` is exactly the trust boundary that must not assume a submitted result is correct; this phase strengthens, not weakens, that boundary |
| V5 Input Validation | yes | `chunk_hashes`/`ipfs_results_data_id` are attacker-influenced fields (a malicious node controls its own `SubTaskResult`); the existing `ValidateResultData` scheme/availability checks (`processing_subtask_queue_accessor_impl.cpp:515-575`) already validate the `ipfs://` scheme before any fetch — the new mismatch-path fetch must reuse this validation, not bypass it |
| V6 Cryptography | no direct change | SHA-256 hashing (`sgprocmanagersha`) is unchanged by this phase; the comparison logic operates on already-computed hashes/raw bytes, not cryptographic primitives themselves |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| A malicious/faulty node submits a corrupted `SubTaskResult` with a hash matching its own (but wrong) data, hoping the loosened tolerance fallback masks the corruption | Tampering | SECV-02's counter-test is exactly this mitigation — proves the tolerance fallback isn't loose enough to accept a genuinely wrong result; the "zero elements may exceed threshold" comparison policy (not percentage-based) directly defends against partial/localized corruption slipping through |
| A malicious node's `ipfs_results_data_id` points to an unfetchable, malformed, or non-`ipfs://` CID to force a validator crash or hang on the mismatch-path fetch | Denial of Service | Reuse `ValidateResultData`'s existing scheme validation before fetching; the fetch must fail closed (treat as genuine mismatch) on any fetch error, not throw/hang |
| Overlapping-window byte-slicing miscalculation causes the validator to compare the wrong bytes, potentially always agreeing (false negative) or always disagreeing (false positive/DoS-by-false-rejection) | Tampering / Denial of Service | Scope this phase's fixtures to the tractable slicing cases (Pitfall 3); document the overlapping-window gap explicitly rather than silently shipping an incorrect comparison |

## Sources

### Primary (HIGH confidence — direct codebase reads, this session)

- `SuperGenius/src/processing/processing_validation_core.{hpp,cpp}` — full read, exact bug location and mechanism
- `SuperGenius/src/processing/processing_subtask_queue_accessor_impl.{hpp,cpp}` — sole call site, existing io_context member, existing setter pattern, existing IPFS validation
- `SuperGenius/src/processing/proto/SGProcessing.proto` — full read, confirms no offset metadata on `ProcessingChunk`
- `SuperGenius/src/processing/processing_tasksplit.cpp` + `GeniusNode.cpp` (relevant excerpt) — confirms `addvalidationsubtask=false` at the only real call site
- `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` (multiple excerpts: 1490-1650, 1270-1450, 1870-1940) — save loop, `chunkhashes` origin, `LoadASync`/`GetSubCidForProc` precedent
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_float.cpp` (lines 160-360) — sliding-window/stitching mechanism, per-window chunk hash computation
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_volume.cpp` (grep + targeted read) — confirms same stitching pattern in the `tex3d`/volume processor
- `SuperGenius/SGProcessingManager/include/util/quantization.hpp` + `src/util/quantization.cpp` — full read, `ResolveQuantScale`/`ResolveByteQuantMode`/`QuantizeFloatBuffer`/`QuantizeByteBuffer` exact semantics
- `SuperGenius/SGProcessingManager/tools/capture/capture_diff.cpp` (lines 1-260) — exact diff primitives and constants
- `SuperGenius/SGProcessingManager/tools/capture/CMakeLists.txt` — confirms CLI-only linkage today
- `SuperGenius/src/processing/CMakeLists.txt`, `SGProcessingManager/src/processingbase/CMakeLists.txt`, `SGProcessingManager/src/processors/CMakeLists.txt`, `SGProcessingManager/src/util/CMakeLists.txt` — full CMake link-graph trace confirming the zero-change transitive PUBLIC path
- `SuperGenius/test/src/processing_conformance_security/secv01_counter_test.cpp` — full read, exact job-pair pattern
- `SuperGenius/test/src/processing/processing_subtask_queue_manager_test.cpp` (lines 370-460) — the only existing `ValidateResults` test, confirms identical-hash-only coverage today

### Secondary (project-internal, MEDIUM confidence)

- `.planning/workstreams/sgproc-render/STATE.md` — Phase 13/14 decision history (S=2^15 derivation, VALD-01 override precedent, "New evidence for QUANT-CFG-01" segmentation/Dice-overlap nuance)
- `.planning/workstreams/sgproc-render/phases/15-validation-comparison-mechanism/15-CONTEXT.md` — locked decisions and canonical references (this research's starting map)

### Tertiary (LOW confidence — none)

No WebSearch-only or unverified external claims were used in this research; the domain is entirely internal/bespoke protocol and algorithm design specific to this codebase, with no applicable external standard to cite.

## Metadata

**Confidence breakdown:**
- Standard stack / existing code locations: HIGH — every file/line reference in this document was read directly this session
- Architecture (fix shape, shared-lib wiring, signature change): MEDIUM-HIGH — the wiring recommendations are grounded in verified CMake link graphs and existing precedent patterns in this exact codebase, but represent this research's proposed design, not a locked/tested implementation
- Tolerance formula (A1/A2 in Assumptions Log): LOW-MEDIUM — reasoned from `QuantizeFloatBuffer`/`QuantizeByteBuffer`'s documented semantics, but not empirically validated against real cross-hardware data this session (unlike Phase 13's `S=2^15` choice, which was validated against `SECV-01`)
- Pitfalls: HIGH — all three pitfalls are grounded in directly-observed code behavior (stitching math, `ValidateResultData`'s existing empty/scheme handling, the concatenation bug's exact mechanism)

**Research date:** 2026-08-14
**Valid until:** Effectively indefinite for the code-location claims (stable, versioned in-repo source) unless Phase 15's own implementation changes them first; the tolerance-formula assumptions (A1/A2) should be re-validated empirically once real fixtures exist, similar to how Phase 13 re-validated Phase 12's original `S` choice.
