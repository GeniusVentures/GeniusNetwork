---
phase: 10-capture-harness-diff-tool-quantization-stub
plan: 04
subsystem: rendering
tags: [cpp, sgprocessingmanager, render-processor, capture-format, quantization]

# Dependency graph
requires: ["10-01"]
provides:
  - "RenderProcessor quantize-then-capture wiring before its single combined-hash call"
  - "sgns::sgproccapture::CaptureRecord/CaptureFile + SerializeCaptureFile/DeserializeCaptureFile capture file binary format"
affects: [10-05, 10-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Locally-owned buffer quantize-in-place (readbackBytes is a std::vector<uint8_t>, not foreign MNN tensor memory) — no copy-before-mutate needed, unlike every MNN processor"
    - "Length-prefixed variable-length binary section appended after two unmodified fixed-layout SerializeArtifact/SerializeManifest calls, matching D-01's 'do not invent a second serialization convention' constraint"
    - "Bounded-count guard (CountFitsRemaining) rejecting a declared item count before any per-item reserve/allocation, closing the unbounded-allocation DoS risk for length-prefixed sections"

key-files:
  created:
    - SuperGenius/SGProcessingManager/tools/capture/capture_file_format.hpp
    - SuperGenius/SGProcessingManager/tools/capture/capture_file_format.cpp
  modified:
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp

key-decisions:
  - "combinedHash uses a 4-byte (uint32) length prefix while per-record preQuantizeBytes/quantizedBytes use 8-byte (uint64) length prefixes, matching the plan's exact wire-format spec (records can plausibly hold megapixel raw output; combinedHash is always exactly 32 bytes)"
  - "Verified round-trip/truncation/oversized-length behavior via a standalone scratch CMake build (compiling capture_file_format.cpp + artifact_serializer.cpp + a throwaway main.cpp) rather than adding a permanent test target — this plan's files_modified scope is the .hpp/.cpp pair only; Wave 3/4's test/capture/ CMakeLists.txt is the sanctioned place for a permanent CTest-registered version of this same round-trip check"

requirements-completed: [CAPT-02]

coverage:
  - id: D1
    description: "RenderProcessor contains exactly 1 QuantizeByteBuffer call on readbackBytes.data(), and exactly 1 execCtx.rawOutputCapture-guarded block invoking it with (quantized bytes, pre-quantize snapshot), both immediately before the unchanged combined-hash call"
    requirement: "CAPT-02"
    verification:
      - kind: other
        ref: "grep -c QuantizeByteBuffer SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp -> 1"
        status: pass
      - kind: other
        ref: "cmake --build build/Windows/Release --target SGProcessors --config Release"
        status: pass
    human_judgment: false
  - id: D2
    description: "capture_file_format.hpp/.cpp declare sgns::sgproccapture::CaptureRecord/CaptureFile/SerializeCaptureFile/DeserializeCaptureFile, call SerializeArtifact/SerializeManifest unmodified, and round-trip correctly while rejecting truncated/oversized malformed input"
    requirement: "CAPT-01"
    verification:
      - kind: other
        ref: "Standalone scratch build (capture_file_format.cpp + artifact_serializer.cpp + throwaway main.cpp): serialize/deserialize round-trip on a CaptureFile with 1 artifact (chunkHashCount=2) and 2 CaptureRecords reproduced every field exactly"
        status: pass
      - kind: other
        ref: "Same scratch build: DeserializeCaptureFile returned false (never crashed) on 4 truncated byte-buffer lengths (0, 2, half, len-1) and on a forged 0xFFFFFFFF machineIdTag length prefix"
        status: pass
    human_judgment: false

# Metrics
duration: 20min
completed: 2026-08-10
status: complete
---

# Phase 10 Plan 04: RenderProcessor Wiring & Capture File Format Summary

**Wired the quantize-then-capture-then-hash pattern into RenderProcessor's single (non-chunked) combined-hash call site, and created the new `sgns::sgproccapture` capture file binary format that reuses `SerializeArtifact`/`SerializeManifest` unmodified and appends a bounds-checked, length-prefixed raw-bytes section.**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-08-10
- **Tasks:** 2
- **Files modified:** 3 (2 created, 1 modified)

## Accomplishments

- `RenderProcessor::StartProcessing` now quantizes `readbackBytes` in place (identity no-op via `sgns::sgprocmanagerquant::QuantizeByteBuffer`) and, if `execCtx.rawOutputCapture` is set, offers the callback the quantized bytes plus a pre-quantize snapshot — inserted immediately before the existing, unchanged `sgns::sgprocmanagersha::sha256(readbackBytes.data(), readbackBytes.size())` call. Since `readbackBytes` is a locally-owned `std::vector<uint8_t>` (not foreign MNN tensor memory), no copy-before-mutate step was needed before quantization itself — only before the capture callback fires, since the callback's contract expects a genuine pre-quantize snapshot.
- New `SuperGenius/SGProcessingManager/tools/capture/` directory with `capture_file_format.hpp`/`.cpp`: `sgns::sgproccapture::CaptureRecord` (one `rawOutputCapture` invocation's pre-/post-quantize byte pair) and `CaptureFile` (machine ID tag, fixture label, artifacts, index-aligned per-artifact capture records, manifest, combined hash).
- `SerializeCaptureFile`/`DeserializeCaptureFile` call `sgns::sgprocessing::SerializeArtifact`/`SerializeManifest`/`DeserializeArtifact`/`DeserializeManifest` unmodified for the metadata+hash portion (D-01) and append one new little-endian, length-prefixed raw-bytes section per capture record plus a trailing `combinedHash` section.
- `DeserializeCaptureFile` validates every declared length/count against bytes actually remaining in the buffer and a 1 GiB cap (`kMaxSectionBytes`) *before* any allocation — including a dedicated `CountFitsRemaining` guard applied to both `artifactCount` and each artifact's per-record `recordCount`, so a forged huge count cannot trigger an oversized `reserve()` before the first real bounds check runs. Returns `false` (never throws, never partially populates `out`) on any malformed/truncated/oversized input.
- Verified both properties empirically via a standalone scratch build (see Deviations): round-trip equality on a `CaptureFile` with 1 artifact (`chunkHashCount = 2`) and 2 `CaptureRecord`s reproduced every field exactly; 4 truncated-length variants and 1 forged-oversized-length-prefix variant all returned `false` without crashing.
- `SGProcessors` CMake target (which now includes the modified `processing_processor_render.cpp`) built successfully with `cmake --build build/Windows/Release --target SGProcessors --config Release`.

## Task Commits

Each task was committed atomically in the `SGProcessingManager` submodule (branch `dev_rendering`):

1. **Task 1: Wire RenderProcessor (single insertion point)** - `8536f89` (feat)
2. **Task 2: Create capture file binary format (capture_file_format.hpp/.cpp)** - `26ba594` (feat)

_Note: commits landed in the nested `SGProcessingManager` git submodule (`W:\gnus\GeniusNetwork\SuperGenius\SGProcessingManager`), not the top-level repo or the `SuperGenius` submodule directly — `SGProcessingManager` is itself a submodule of `SuperGenius`. Consistent with 10-01/10-02/10-03's precedent, the `SuperGenius` submodule pointer and top-level repo were not re-committed as part of this plan; that bump is deferred to a later checkpoint._

## Files Created/Modified

- `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp` - Added `#include "util/quantization.hpp"`; inserted a `preQuantizeSnapshot` local, one `QuantizeByteBuffer` call, and one `rawOutputCapture`-guarded callback invocation immediately before the unchanged `result.hash = sha256(...)` line
- `SuperGenius/SGProcessingManager/tools/capture/capture_file_format.hpp` - New file: `sgns::sgproccapture::CaptureRecord`/`CaptureFile` structs, `SerializeCaptureFile`/`DeserializeCaptureFile` declarations, full binary-layout doc comment
- `SuperGenius/SGProcessingManager/tools/capture/capture_file_format.cpp` - New file: implementation, including bounds-checked read helpers (`ReadU32`/`ReadU64`/`ReadString`/`ReadBytesU64`/`ReadBytesU32`/`ReadFixedRegion`) and the `CountFitsRemaining` unbounded-allocation guard

## Decisions Made

- `combinedHash` uses a 4-byte (uint32) length prefix while per-record `preQuantizeBytes`/`quantizedBytes` use 8-byte (uint64) length prefixes — followed the plan's exact wire-format spec verbatim rather than using one prefix width everywhere, since `combinedHash` is always exactly 32 bytes while capture records can plausibly hold megapixel-scale raw render/MNN output.
- Verified this plan's round-trip/truncation/oversized-length acceptance criteria via a standalone scratch CMake build (`capture_file_format.cpp` + `artifact_serializer.cpp` + a throwaway `main.cpp`, built and run in the session scratchpad, not committed anywhere) instead of adding a permanent CTest target — this plan's `files_modified` scope is explicitly the `.hpp`/`.cpp` pair only; `10-PATTERNS.md` already assigns a permanent `test/capture/CMakeLists.txt` + `capture_smoke_test.cpp` to a later wave, which is the sanctioned home for a committed version of this same check.

## Deviations from Plan

None — plan executed exactly as written. The only executor-initiated addition beyond the plan's literal file list was a temporary, uncommitted scratch build used purely to empirically verify Task 2's acceptance criteria (round-trip equality; `false`-not-crash on truncated/oversized input) before committing — no project files outside the plan's declared scope were touched.

## Issues Encountered

None. `SGProcessors` built cleanly (`build/Windows/Release`, MSVC/Visual Studio 17 2022 generator, matching this workstream's build convention) with zero new warnings; the only warning emitted (`C4117` on a reserved macro name in a third-party `libp2p` header) is pre-existing and unrelated to this plan's changes.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

`RenderProcessor` is now fully wired (the 14th and final processor file across Wave 2's three plans), and the capture file binary format is ready for Wave 3's `capture_harness`/`capture_diff` (Plan 10-05) to build against. No blockers identified.

---
*Phase: 10-capture-harness-diff-tool-quantization-stub*
*Completed: 2026-08-10*

## Self-Check: PASSED

- FOUND: SuperGenius/SGProcessingManager/tools/capture/capture_file_format.hpp
- FOUND: SuperGenius/SGProcessingManager/tools/capture/capture_file_format.cpp
- FOUND: SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp
- FOUND: .planning/workstreams/sgproc-render/phases/10-capture-harness-diff-tool-quantization-stub/10-04-SUMMARY.md
- FOUND: commit 8536f89 (SGProcessingManager submodule)
- FOUND: commit 26ba594 (SGProcessingManager submodule)
