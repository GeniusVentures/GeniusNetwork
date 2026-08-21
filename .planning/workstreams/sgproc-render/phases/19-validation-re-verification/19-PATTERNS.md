# Phase 19: Validation Re-Verification - Pattern Map

**Mapped:** 2026-08-21
**Files analyzed:** 2 (1 test file to extend, 1 new outcome doc)
**Analogs found:** 2 / 2

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|----------------|
| `SuperGenius/test/src/processing/processing_validation_core_test.cpp` (append new `TEST`/`TEST_F` case(s)) | test | request-response (direct unit call into production validation function) | Same file's existing `ProcessingValidationCoreTest`/free `TEST()` cases (`DifferingHashesWithinToleranceStillPass`, `DifferingHashesExceedsToleranceFail`) | exact |
| New re-verification outcome doc, e.g. `.planning/workstreams/sgproc-render/phases/19-validation-re-verification/19-REVERIFICATION.md` | test/doc (report) | batch (read fixture, run harness, record outcome) | `.planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/13-SCOPE-BOUNDARY.md` and `.../17-render-path-cross-hardware-tolerance/17-TOLERANCE-RESULTS.md` | exact |
| (helper) `.cap` file parsing logic inside the new test | utility / file-I/O | file-I/O (binary deserialize) | `SuperGenius/SGProcessingManager/tools/capture/capture_diff.cpp` (`DeserializeCaptureFile` + `rawRecordsPerArtifact` indexing loop, lines 152-298) | exact |

Note: per CONTEXT.md's "Claude's Discretion", the harness itself is not a new file by default — it is new `TEST`/`TEST_F` cases appended to the existing `processing_validation_core_test.cpp`. Only fall back to a dedicated tool (mirroring `capture_diff.cpp`'s CLI-tool shape) if the direct-call approach proves structurally insufficient (see D-02).

## Pattern Assignments

### `SuperGenius/test/src/processing/processing_validation_core_test.cpp` (test, request-response)

**Analog:** same file, existing `ProcessingValidationCoreTest`-style cases (`DifferingHashesWithinToleranceStillPass` lines 163-223, `DifferingHashesExceedsToleranceFail` lines 231-293)

**Imports pattern** (lines 1-13):
```cpp
#include <cstring>

#include <gtest/gtest.h>

#include "processing/processing_validation_core.hpp"
#include "ParameterType.hpp"

using namespace sgns::processing;
```
For the new re-verification case(s), additionally include the capture file format header and the diff utils header (both already used elsewhere in the codebase, not new dependencies):
```cpp
#include "capture/capture_file_format.hpp"      // sgns::sgproccapture::CaptureFile / DeserializeCaptureFile
#include "util/diff_utils.hpp"                  // sgns::sgprocmanagerdiff (only if cross-checking tolerance bound directly)
```

**Building `SubTaskCollection`/`SubTaskResult` + `ChunkContribution` inputs** (lines 47-86, 163-198):
`ValidateResults` is driven purely by protobuf `SGProcessing::SubTaskCollection`/`SGProcessing::SubTaskResult` objects — there is no public way to construct `ChunkContribution` directly since it is a private nested struct built internally by `ValidateResults` from `chunk_hashes()`. The existing tests always go through the public two-subtask-sharing-one-chunk pattern:
```cpp
SGProcessing::SubTaskCollection subTasks;
SGProcessing::ProcessingChunk   chunk1;
chunk1.set_chunkid( "CHUNK_1" );
chunk1.set_n_subchunks( 1 );

{
    auto subtask = subTasks.add_items();
    subtask->set_subtaskid( "SUBTASK_1" );
    auto chunk = subtask->add_chunkstoprocess();
    chunk->CopyFrom( chunk1 );
}
{
    auto subtask = subTasks.add_items();
    subtask->set_subtaskid( "SUBTASK_2" );
    auto chunk = subtask->add_chunkstoprocess();
    chunk->CopyFrom( chunk1 );
}

std::map<std::string, SGProcessing::SubTaskResult> results;
{
    SGProcessing::SubTaskResult subTaskResult;
    subTaskResult.add_chunk_hashes( "1" );                       // real: put captured chunk hash bytes here
    subTaskResult.set_subtaskid( "SUBTASK_1" );
    subTaskResult.set_ipfs_results_data_id( "stub://a" );        // real: identify fetch source per subtask
    results.emplace( subTaskResult.subtaskid(), subTaskResult );
}
// ... SUBTASK_2 analogous with chunk_hashes("2") and "stub://b"
```
For the 15-chunk re-verification (D-03), this must be extended to a loop: `n_subchunks` set to 15 (or one `ProcessingChunk` per chunk index, matching however the real fixture's subtask was structured), with per-chunk hash bytes taken from the two `.cap` files' `artifacts[0].chunkHashes[j]` (via `DeserializeCaptureFile`), and `fetchOutputData` returning each chunk's raw bytes sliced out of `rawRecordsPerArtifact[0][j].quantizedBytes` (see capture-parsing excerpt below) keyed by a `chunkIdx`-aware URI, since `ChunkContribution::chunkIdx`/`totalChunksForSubtask` (declared in `processing_validation_core.hpp` lines 86-91) is what `AttemptToleranceFallback` uses internally to slice a multi-chunk blob.

**`jobParameters` (quantScale) pattern** (lines 146-153, 199):
```cpp
std::vector<sgns::Parameter> MakeQuantScaleParameters( double quantScale )
{
    sgns::Parameter param;
    param.set_name( "quantScale" );
    param.set_type( sgns::ParameterType::FLOAT );
    param.set_parameter_default( quantScale );
    return std::vector<sgns::Parameter>{ param };
}
// ...
auto jobParameters = MakeQuantScaleParameters( 32768.0 );  // Phase 19: use S=2^15 (32768.0), quantization.hpp's shipped constant
```

**`fetchOutputData` capability + 5-arg `ValidateResults` call pattern** (lines 201-221):
```cpp
const std::vector<uint8_t> bufferA = FloatToBytes( 1.0f );
const std::vector<uint8_t> bufferB = FloatToBytes( 1.0f + 1e-6f );

auto fetchOutputData = [&]( const std::string &uri ) -> outcome::result<std::vector<uint8_t>>
{
    if ( uri == "stub://a" ) { return bufferA; }
    if ( uri == "stub://b" ) { return bufferB; }
    return outcome::failure( std::make_error_code( std::errc::io_error ) );
};

ProcessingValidationCore validationCore;
std::set<std::string>    invalidSubTaskIds;
auto                     validate_res =
    validationCore.ValidateResults( subTasks, results, invalidSubTaskIds, &jobParameters, fetchOutputData );
ASSERT_FALSE( validate_res.has_error() );
ASSERT_TRUE( invalidSubTaskIds.empty() );
```
For Phase 19: `bufferA`/`bufferB` must be the real captured buffers loaded from the two `.cap` files (see below) rather than synthetic `FloatToBytes` values, and the assertion should record — not assume — the outcome per chunk (D-04: may legitimately assert a mismatch for chunk 10 if the gap is still open; the harness must not force a pass).

**Error/outcome check pattern** (lines 289-292, mirrored for the "still fails" case):
```cpp
ASSERT_TRUE( validate_res.has_error() );
ASSERT_EQ( 2u, invalidSubTaskIds.size() );
ASSERT_TRUE( invalidSubTaskIds.find( "SUBTASK_1" ) != invalidSubTaskIds.end() );
ASSERT_TRUE( invalidSubTaskIds.find( "SUBTASK_2" ) != invalidSubTaskIds.end() );
```

---

### `.cap` file parsing (utility, file-I/O) — feeds the harness above

**Analog:** `SuperGenius/SGProcessingManager/tools/capture/capture_diff.cpp` lines 145-298

**Struct layout to target** (`SuperGenius/SGProcessingManager/tools/capture/capture_file_format.hpp` lines 55-84):
```cpp
struct CaptureRecord
{
    std::vector<uint8_t> preQuantizeBytes;  // Bytes offered to rawOutputCapture before Quantize*Buffer ran
    std::vector<uint8_t> quantizedBytes;    // Bytes offered to rawOutputCapture after Quantize*Buffer ran
};

struct CaptureFile
{
    std::string machineIdTag;
    std::string fixtureLabel;
    std::vector<sgns::sgprocessing::Artifact> artifacts;

    // Index-aligned with `artifacts`: rawRecordsPerArtifact[i] is the ordered
    // list of every rawOutputCapture call that fed hashes for artifacts[i].
    // records[0 .. artifacts[i].chunkHashCount - 1] correspond 1:1 to
    // artifacts[i].chunkHashes[0 .. chunkHashCount - 1]; an optional trailing
    // record (if present) corresponds to artifacts[i].contentHash.
    std::vector<std::vector<CaptureRecord>> rawRecordsPerArtifact;

    sgns::sgprocessing::ExecutionManifest manifest;
    std::vector<uint8_t> combinedHash;
};

bool DeserializeCaptureFile( const std::vector<uint8_t> &bytes, CaptureFile &out );
```

**Load + validate pattern** (`capture_diff.cpp` lines 145-184):
```cpp
std::vector<uint8_t> bytesA, bytesB;
ReadFileBytes( args.pathA, bytesA );   // capture_diff.cpp has its own ReadFileBytes helper; harness may reuse or reimplement
ReadFileBytes( args.pathB, bytesB );

sgns::sgproccapture::CaptureFile captureA, captureB;
if ( !sgns::sgproccapture::DeserializeCaptureFile( bytesA, captureA ) ) { /* fail loudly */ }
if ( !sgns::sgproccapture::DeserializeCaptureFile( bytesB, captureB ) ) { /* fail loudly */ }

if ( captureA.artifacts.size() != 1 || captureB.artifacts.size() != 1 ) { /* Phase 10 scope: exactly one artifact */ }

const auto &artifactA = captureA.artifacts[0];
const auto &artifactB = captureB.artifacts[0];
if ( artifactA.chunkHashCount != artifactB.chunkHashCount ) { /* structural mismatch, distinct from numeric divergence */ }
```

**Per-chunk indexing pattern** (`capture_diff.cpp` lines 264-298 — this is the D-03 "loop over all 15 chunks" precedent):
```cpp
bool haveArtifactZeroRecords = !captureA.rawRecordsPerArtifact.empty() && !captureB.rawRecordsPerArtifact.empty();
for ( size_t j = 0; j < chunkHashesMatch.size(); ++j )   // j == chunk index, 0..14 for the Phase 19 fixture
{
    bool haveChunkRecords = haveArtifactZeroRecords && captureA.rawRecordsPerArtifact[0].size() > j &&
                             captureB.rawRecordsPerArtifact[0].size() > j;
    if ( !haveChunkRecords ) { /* skip / report missing record for chunk j */ continue; }

    const auto &chunkRecordA = captureA.rawRecordsPerArtifact[0][j];
    const auto &chunkRecordB = captureB.rawRecordsPerArtifact[0][j];
    // chunkRecordA.quantizedBytes / chunkRecordB.quantizedBytes are the raw
    // per-chunk float32 buffers to feed into fetchOutputData for chunk j.
}
```
This is exactly the layout the new harness must replicate to slice out chunk 10's (and the other 14 chunks') `quantizedBytes` and hand them to `ValidateResults` via `fetchOutputData`, and to cross-check against `diff-mnn-float-refit-chunkdiag.json`'s pre-computed per-chunk numbers (per CONTEXT.md's Reusable Assets note).

**Tolerance bound being exercised** (`SuperGenius/SGProcessingManager/include/util/diff_utils.hpp` lines 92-117):
```cpp
/// D-03: when the job validly declares "quantScale" = S, the bound is
/// derived from the quantization grid step (2/S, two grid steps of margin)
/// and compared against ComputeFloat32Diff's maxAbsDelta.
bool IsFloatChunkWithinTolerance( const std::vector<uint8_t>          &a,
                                  const std::vector<uint8_t>          &b,
                                  const std::vector<sgns::Parameter>  *parameters,
                                  ElementDiffStats                    &statsOut );
```
This is the exact function `AttemptToleranceFallback` calls internally (via `ValidateResults`'s 5-arg overload) — the new harness does not call it directly; it exercises it indirectly through `ValidateResults`/`AttemptToleranceFallback` per D-02.

---

## Shared Patterns

### Direct-unit-call harness convention (no new test binary)
**Source:** `SuperGenius/test/src/processing/processing_validation_core_test.cpp` (entire file — plain `TEST()` free functions, not `TEST_F` fixtures; no shared fixture class exists today despite the "ProcessingValidationCoreTest" naming)
**Apply to:** the new Phase 19 test case(s)
Each existing case constructs a fresh `ProcessingValidationCore validationCore;` locally and does not share state across tests — follow this (no need to introduce a `TEST_F` fixture class unless setup becomes heavy, e.g. loading both `.cap` files once via `SetUp()`).

### Honest-outcome-reporting doc convention
**Source:** `.planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/13-SCOPE-BOUNDARY.md` and `.planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/17-09-SUMMARY.md`
**Apply to:** the new `19-REVERIFICATION.md` (or similarly named) outcome doc
Both source docs state results plainly, including partial/still-open framing (e.g., Phase 13's "1/15 chunks divergent... exactly one S=2^15 grid step" language), rather than rounding a partial result into a pass. Phase 19's outcome doc must follow the same structure: state chunk-by-chunk pass/fail post-fallback, and explicitly classify the overall VALD-01 gap as closed / partially closed / still open (D-04), citing exact `maxAbsDelta`/tolerance-bound numbers the same way `13-SCOPE-BOUNDARY.md` does.

### Reusing already-captured fixture data instead of a new capture round
**Source:** `.planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/17-TOLERANCE-RESULTS.md` (Gap Closure Addendum)
**Apply to:** phase framing / no new `.cap` capture session needed — the harness reads Phase 13's existing files at `.planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/captures/xhw-mnn-float_Fuus-Mac-mini.local---macOS_20260812T232347.cap` and `.../xhw-mnn-float_Mofu---Windows_20260812T232430.cap` directly (D-01).

## No Analog Found

None. Both the test-harness extension and the outcome doc have exact analogs in-repo (existing test file style; existing Phase 13/17 outcome-doc style).

## Metadata

**Analog search scope:** `SuperGenius/test/src/processing/`, `SuperGenius/SGProcessingManager/tools/capture/`, `SuperGenius/SGProcessingManager/include/util/`, `SuperGenius/src/processing/`, `.planning/workstreams/sgproc-render/phases/13-*`, `.planning/workstreams/sgproc-render/phases/17-*`
**Files scanned:** `processing_validation_core_test.cpp`, `processing_validation_core.hpp`, `capture_file_format.hpp`, `capture_diff.cpp`, `diff_utils.hpp`
**Pattern extraction date:** 2026-08-21
