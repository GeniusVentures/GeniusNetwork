---
phase: 10-capture-harness-diff-tool-quantization-stub
plan: 03
subsystem: processors
tags: [cpp, mnn, quantization, capture, sgprocessingmanager]

# Dependency graph
requires: ["10-01"]
provides:
  - "7 chained-family MNN processors (Bool, Buffer, Image, String, Texture1D, TextureCube, Volume) quantize (identity stub) and offer raw bytes to rawOutputCapture at their chunk-level hash call site(s)"
affects: [10-05, 10-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Quantize-then-capture-then-hash: locally-owned copy of MNN-owned tensor memory at each chunk-hash site; rolling combined-hash call sites left untouched since they hash already-quantized-chunk-hash bytes concatenated with a hex string, not a re-quantizable float buffer"

key-files:
  modified:
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_bool.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_buffer.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_image.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_string.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_texture1d.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_texturecube.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_volume.cpp

key-decisions:
  - "Used unqualified `sgprocmanagerquant::QuantizeFloatBuffer` (not `sgns::sgprocmanagerquant::...`) to match each file's existing unqualified `sgprocmanagersha::sha256` call convention -- same decision made in Plan 10-02, applied consistently here"

patterns-established:
  - "Chunk-only insertion for the 7 'chained' MNN types: copy MNN-owned const float* into a locally-owned std::vector<float>, quantize+capture, redirect the chunk-hash sha256 call's first argument to the copy; leave the rolling combined-hash call site (hash-of-previous-hash-plus-current-hex-string) completely untouched"
  - "TextureCube's two independent code branches (interpreter-session path and Process()-helper path) each get their own localCopy/quantize/capture insertion using that branch's own data/dataSize locals, since the two branches never share a chunk-hash call site"

requirements-completed: [CAPT-02]

coverage:
  - id: D1
    description: "Each of Bool/Buffer/Image/String/Texture1D/Volume contains exactly 1 QuantizeFloatBuffer call and 1 rawOutputCapture-guarded block at its chunk-hash site; TextureCube contains exactly 2 of each, one per branch"
    requirement: "CAPT-02"
    verification:
      - kind: other
        ref: "grep -c QuantizeFloatBuffer across all 7 files: 6 files == 1, texturecube.cpp == 2"
        status: pass
      - kind: other
        ref: "grep -n \"QuantizeFloatBuffer( data\" across all 7 files returns no matches (never quantizes the raw MNN pointer)"
        status: pass
      - kind: other
        ref: "cmake --build build/Windows/Debug --target SGProcessors --config Debug (SuperGenius/build/Windows/Debug, MSBuild)"
        status: pass
  - id: D2
    description: "No file adds a second insertion at its rolling combined-hash call site; all combinedHash/subTaskResultHash lines are byte-for-byte unmodified"
    requirement: "CAPT-02"
    verification:
      - kind: other
        ref: "grep -n \"subTaskResultHash = sgprocmanagersha::sha256( combinedHash\" across all 7 files -- present, unchanged text, no QuantizeFloatBuffer call nearby"
        status: pass
    human_judgment: false

# Metrics
duration: 10min
completed: 2026-08-10
status: complete
---

# Phase 10 Plan 03: Wire Quantize+Capture Into Chained-Family MNN Processors (Bool/Buffer/Image/String/Texture1D/TextureCube/Volume) Summary

**Wired the quantize-then-capture-then-hash pattern into all 7 chained-family MNN processors at their chunk-level hash call site(s) only (8 insertion points total: 6 single-branch files + TextureCube's 2 branches), explicitly leaving all 8 rolling combined-hash call sites untouched since they hash already-quantized-hash bytes, not re-quantizable float data.**

## Performance

- **Duration:** ~10 min
- **Completed:** 2026-08-10
- **Tasks:** 3
- **Files modified:** 7

## Accomplishments
- Bool, Buffer, Image, String, Texture1D, and Volume each now copy MNN-owned tensor memory into a locally-owned `std::vector<float>` before calling `QuantizeFloatBuffer` at their single chunk-hash site, then hash the (quantized, currently identity) copy instead of the raw MNN pointer
- TextureCube's two independent code branches (interpreter-session path and `Process()`-helper path) each got their own `localCopy`/`QuantizeFloatBuffer`/`rawOutputCapture` insertion, using that branch's own `data`/`dataSize` locals
- `rawOutputCapture` is invoked with (quantized bytes, pre-quantize bytes) in that order at every insertion point, matching Plan 10-01's callback signature and Plan 10-02's established convention exactly
- Verified via grep that no file ever calls `QuantizeFloatBuffer` directly on the raw MNN `data` pointer, and that every rolling combined-hash call site (`subTaskResultHash = sgprocmanagersha::sha256( combinedHash... )`) remains textually unmodified across all 7 files
- Confirmed `SGProcessors` target builds cleanly (`SuperGenius/build/Windows/Debug`, MSBuild) after each of the 3 tasks

## Task Commits

Each task was committed atomically in the `SGProcessingManager` submodule (branch `dev_rendering`):

1. **Task 1: Wire Bool, Buffer, Image (chunk-only insertion)** - `b7b0a12` (feat)
2. **Task 2: Wire String, Texture1D, Volume (chunk-only insertion)** - `24756eb` (feat)
3. **Task 3: Wire TextureCube (two chunk-only insertion points)** - `15fb9fe` (feat)

_Note: commits landed in the nested `SGProcessingManager` git submodule (`W:\gnus\GeniusNetwork\SuperGenius\SGProcessingManager`), not the top-level repo or the `SuperGenius` submodule pointer directly -- following the same pattern established in Plans 10-01/10-02._

## Files Created/Modified
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_bool.cpp` - Added `#include "util/quantization.hpp"`, chunk-site `localCopy`+`QuantizeFloatBuffer`+`rawOutputCapture` guard immediately before the chunk-hash sha256 call; combined-hash call site untouched
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_buffer.cpp` - Same pattern as Bool
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_image.cpp` - Same pattern, adapted to this file's pre-declared `shahash` variable (assignment rather than declaration)
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_string.cpp` - Same pattern, adapted to this file's single-Process-call (no chunk loop) structure and pre-declared `shahash`
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_texture1d.cpp` - Same pattern as Bool
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_texturecube.cpp` - Two insertions, one per independent code branch (interpreter-session path using `outputUserTensor->host<float>()`, and `Process()`-helper path using `outputTensor->host<float>()`); both combined-hash call sites untouched
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_volume.cpp` - Same pattern, adapted to this file's pre-declared `shahash`

## Decisions Made
- Used the unqualified `sgprocmanagerquant::QuantizeFloatBuffer(...)` call form (matching Plan 10-02's precedent) rather than the fully-qualified `sgns::sgprocmanagerquant::QuantizeFloatBuffer(...)` shown illustratively in the plan text -- both resolve identically via C++ enclosing-namespace lookup from within `sgns::sgprocessing`, and the unqualified form keeps the new lines visually consistent with each file's surrounding `sgprocmanagersha::sha256(...)` calls.

## Deviations from Plan

None - plan executed exactly as written. All line-number estimates in the plan were approximate ("re-confirm against each live file before editing"); actual insertion points were located by reading each file fresh and matching the documented code shapes, exactly as the plan instructed. Two of the six single-branch files (Image, Volume) and String use a pre-declared `shahash` variable with a bare assignment (`shahash = sgprocmanagersha::sha256(...)`) rather than Bool/Buffer/Texture1D's `std::vector<uint8_t> shahash = sgprocmanagersha::sha256(...)` declaration form -- the insertion was adapted to each file's actual local-variable shape rather than assuming one canonical form, per the plan's own instruction to re-verify against the live file.

## Issues Encountered

None. `SGProcessors` built successfully (exit code 0) after each of the 3 tasks using the pre-existing `SuperGenius/build/Windows/Debug` MSBuild directory, per this workstream's established build convention. The only warning emitted (`C4117` on a reserved macro name in a third-party `libp2p` header) is pre-existing and unrelated to this plan's changes.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

All 7 chained-family processors are wired, joining Plan 10-02's 6 stitched-family processors (13 of 14 total MNN processor types now wired; the render processor is Plan 10-04's scope in this same wave). Wave 3 (`capture_harness.cpp`, `capture_diff.cpp`, `artifact_serializer` extension) can now set `rawOutputCapture` on a real `ExecutionContext` and receive real quantized/pre-quantize byte pairs from all 7 of these processor types. No blockers identified.

---
*Phase: 10-capture-harness-diff-tool-quantization-stub*
*Completed: 2026-08-10*

## Self-Check: PASSED

- FOUND: SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_bool.cpp
- FOUND: SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_buffer.cpp
- FOUND: SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_image.cpp
- FOUND: SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_string.cpp
- FOUND: SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_texture1d.cpp
- FOUND: SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_texturecube.cpp
- FOUND: SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_volume.cpp
- FOUND: .planning/workstreams/sgproc-render/phases/10-capture-harness-diff-tool-quantization-stub/10-03-SUMMARY.md
- FOUND: commit b7b0a12 (SGProcessingManager submodule)
- FOUND: commit 24756eb (SGProcessingManager submodule)
- FOUND: commit 15fb9fe (SGProcessingManager submodule)
