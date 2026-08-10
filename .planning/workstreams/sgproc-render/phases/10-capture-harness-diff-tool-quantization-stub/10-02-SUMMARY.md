---
phase: 10-capture-harness-diff-tool-quantization-stub
plan: 02
subsystem: processors
tags: [cpp, mnn, quantization, capture, sgprocessingmanager]

# Dependency graph
requires: ["10-01"]
provides:
  - "6 stitched-family MNN processors (Float, Int, Mat2, Mat3, Mat4, Tensor) quantize (identity stub) and offer raw bytes to rawOutputCapture at both chunk-level and stitched-combined-level hash call sites"
affects: [10-05, 10-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Quantize-then-capture-then-hash: locally-owned copy of MNN-owned tensor memory at chunk sites, in-place mutation with pre-quantize snapshot at stitched-combined sites"

key-files:
  modified:
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_float.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_int.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_mat2.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_mat3.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_mat4.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_tensor.cpp

key-decisions:
  - "Used unqualified `sgprocmanagerquant::QuantizeFloatBuffer` (not `sgns::sgprocmanagerquant::...`) to match each file's existing unqualified `sgprocmanagersha::sha256` call convention -- both resolve identically via enclosing-namespace lookup from within `sgns::sgprocessing`"

patterns-established:
  - "Per-chunk site: copy MNN-owned const float* into a locally-owned std::vector<float> before quantizing/capturing, never mutate the MNN tensor buffer in place"
  - "Stitched-combined site: snapshot pre-quantize bytes only when rawOutputCapture is set, then quantize stitchedOutput in place unconditionally (it's already locally owned)"

requirements-completed: [CAPT-02]

coverage:
  - id: D1
    description: "Each of the 6 stitched-family files contains exactly 2 QuantizeFloatBuffer calls and 2 rawOutputCapture-guarded blocks, and the per-chunk sha256 call now hashes a locally-owned copy instead of the raw MNN data pointer"
    requirement: "CAPT-02"
    verification:
      - kind: other
        ref: "grep -c QuantizeFloatBuffer on all 6 files == 2 each"
        status: pass
      - kind: other
        ref: "grep -n \"QuantizeFloatBuffer( data\" across all 6 files returns no matches (never quantizes the raw MNN pointer)"
        status: pass
      - kind: other
        ref: "cmake --build build/Windows/Debug --target SGProcessors --config Debug"
        status: pass
    human_judgment: false

# Metrics
duration: 12min
completed: 2026-08-10
status: complete
---

# Phase 10 Plan 02: Wire Quantize+Capture Into Stitched-Family MNN Processors Summary

**Wired the quantize-then-capture-then-hash pattern into all 6 stitched-family MNN processors (Float, Int, Mat2, Mat3, Mat4, Tensor) at both their per-chunk and stitched-combined hash call sites, exercising Plan 10-01's `sgprocmanagerquant`/`rawOutputCapture` foundation for the first time at real call sites.**

## Performance

- **Duration:** 12 min
- **Started:** 2026-08-10T19:08:08Z
- **Completed:** 2026-08-10T19:20:00Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Each of the 6 stitched-family files now copies MNN-owned tensor memory into a locally-owned `std::vector<float>` before calling `QuantizeFloatBuffer` at its per-chunk hash site, then hashes the (quantized, currently identity) copy instead of the raw MNN pointer
- Each file's stitched-combined hash site snapshots pre-quantize bytes (only when `rawOutputCapture` is set) then quantizes `stitchedOutput` in place before the existing `stitchedStr`/combined-hash computation
- `rawOutputCapture` is invoked with (quantized bytes, pre-quantize bytes) in that order at both insertion points, matching Plan 10-01's callback signature exactly
- Verified via grep that no file ever calls `QuantizeFloatBuffer` directly on the raw MNN `data` pointer -- the copy-before-mutate discipline (ARCHITECTURE.md Anti-Pattern 2) holds across all 6 files
- Confirmed `SGProcessors` target builds cleanly (`build/Windows/Debug`, MSBuild) after all 6 files were modified

## Task Commits

Each task was committed atomically in the `SGProcessingManager` submodule (branch `dev_rendering`):

1. **Task 1: Wire Float, Int, Mat2 (chunk + stitched-combined insertion points)** - `e05c456` (feat)
2. **Task 2: Wire Mat3, Mat4, Tensor (chunk + stitched-combined insertion points)** - `46947b1` (feat)

_Note: commits landed in the nested `SGProcessingManager` git submodule (`W:\gnus\GeniusNetwork\SuperGenius\SGProcessingManager`), not the top-level repo or the `SuperGenius` submodule pointer directly -- following the same pattern established in Plan 10-01._

## Files Created/Modified
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_float.cpp` - Added `#include "util/quantization.hpp"`, chunk-site `localCopy`+`QuantizeFloatBuffer`+`rawOutputCapture` guard, stitched-combined-site `preQuantizeSnapshot`+in-place `QuantizeFloatBuffer`+`rawOutputCapture` guard
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_int.cpp` - Same pattern as Float
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_mat2.cpp` - Same pattern as Float
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_mat3.cpp` - Same pattern as Float
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_mat4.cpp` - Same pattern as Float
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_tensor.cpp` - Same pattern as Float

## Decisions Made
- Used the unqualified `sgprocmanagerquant::QuantizeFloatBuffer(...)` call form (rather than the fully-qualified `sgns::sgprocmanagerquant::QuantizeFloatBuffer(...)` shown illustratively in the plan text) to match each file's pre-existing unqualified `sgprocmanagersha::sha256(...)` convention. Both forms resolve to the same function via C++ enclosing-namespace lookup from within `sgns::sgprocessing`; the unqualified form keeps the new lines visually consistent with the surrounding code.

## Deviations from Plan

None - plan executed exactly as written. All line-number estimates in the plan/pattern map were approximate ("re-verify against live file"); actual insertion points were located by reading each file fresh and matching the documented code shapes (chunk-hash call inside the per-window loop, stitched-combined hash call immediately after the weight-division loop), which is exactly what the plan instructed.

## Issues Encountered

None. `SGProcessors` built successfully (exit code 0) on the first attempt using the pre-existing `build/Windows/Debug` MSBuild directory, per this workstream's established build convention.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

All 6 stitched-family processors are wired. Plans 10-03 and 10-04 (same wave) wire the remaining 8 "chained" MNN processors (chunk-only insertion, per ARCHITECTURE.md Anti-Pattern 3) and the render processor. Wave 3 (capture_harness, capture_diff, artifact_serializer extension) can now set `rawOutputCapture` on a real `ExecutionContext` and receive real quantized/pre-quantize byte pairs from these 6 processors. No blockers identified.

---
*Phase: 10-capture-harness-diff-tool-quantization-stub*
*Completed: 2026-08-10*

## Self-Check: PASSED

- FOUND: .planning/workstreams/sgproc-render/phases/10-capture-harness-diff-tool-quantization-stub/10-02-SUMMARY.md
- FOUND: commit e05c456 (SGProcessingManager submodule)
- FOUND: commit 46947b1 (SGProcessingManager submodule)
