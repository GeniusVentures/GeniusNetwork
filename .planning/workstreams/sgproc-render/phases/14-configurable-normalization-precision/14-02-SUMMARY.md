---
phase: 14-configurable-normalization-precision
plan: 02
subsystem: infra
tags: [quantization, schema-config, cpp, processors]

# Dependency graph
requires:
  - phase: 14-configurable-normalization-precision
    plan: 01
    provides: "ResolveQuantScale/ResolveByteQuantMode free functions and the 3-arg QuantizeFloatBuffer/QuantizeByteBuffer signatures this plan wires into every call site"
provides:
  - "All 21 QuantizeFloatBuffer/QuantizeByteBuffer call sites across the 14 MNN/render processor files resolve scale/maskBits from the job's own schema instead of relying on the function's internal default"
  - "Zero vestigial (void)parameters; suppression statements remain in any of the 12 files that previously had one"
affects: [14-03-tex3d-empirical-precision]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Resolve-once-per-StartProcessing-call, thread-through-unchanged (scale/maskBits resolved via ResolveQuantScale/ResolveByteQuantMode immediately after the function signature, then passed as the new required 3rd argument at every existing Quantize*Buffer call site in that function)"

key-files:
  created: []
  modified:
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_float.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_buffer.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_bool.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_image.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_string.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_mat4.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_mat3.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_mat2.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_int.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_tensor.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_texture1d.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_texturecube.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_volume.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp

key-decisions:
  - "No deviations from the plan's literal recipe were needed -- every file's actual line content matched 14-RESEARCH.md/14-PATTERNS.md's grep-confirmed enumeration exactly (line numbers, suppression-statement text, call-site text), so each edit was applied verbatim as specified"

patterns-established:
  - "All 21 call sites are now compiler-enforced to have explicitly resolved a scale/maskBits value -- a future new call site that forgets this resolution step fails to compile (Plan 14-01's required, non-defaulted parameter design), closing RESEARCH.md Pitfall 1 by construction"

requirements-completed: [QUANT-CFG-01, QUANT-CFG-02]

coverage:
  - id: T-14-05
    description: "Every one of the 21 call sites across 14 processor files resolves scale/maskBits via ResolveQuantScale/ResolveByteQuantMode; no call site retains the old 2-arg signature"
    requirement: "QUANT-CFG-01"
    verification:
      - kind: other
        ref: "grep -c \"sgprocmanagerquant::ResolveQuantScale( parameters )\" across all 13 float-path files == 1 each; grep -c \"sgns::sgprocmanagerquant::ResolveByteQuantMode( parameters )\" render.cpp == 1; grep -c \"(void)parameters;\" == 0 across all 12 files that previously had one; total QuantizeFloatBuffer/QuantizeByteBuffer call-site count across all 14 files == 21, zero 2-arg calls remaining"
        status: pass
    human_judgment: false
  - id: T-14-06
    description: "render.cpp's byte path resolves ResolveByteQuantMode/maskBits (not ResolveQuantScale/scale); all 13 float-path files resolve ResolveQuantScale/scale (not ResolveByteQuantMode)"
    requirement: "QUANT-CFG-01"
    verification:
      - kind: other
        ref: "grep confirms render.cpp is the only file calling ResolveByteQuantMode/QuantizeByteBuffer; all other 13 files call ResolveQuantScale/QuantizeFloatBuffer"
        status: pass
    human_judgment: false
  - id: build-clean
    description: "SGProcessors CMake target (statically links all 14 modified processor files) compiles with zero errors against the new 3-arg signatures"
    requirement: "QUANT-CFG-02"
    verification:
      - kind: other
        ref: "cmake --build SuperGenius/build/Windows/Debug --target SGProcessors --config Debug"
        status: pass
    human_judgment: false

duration: 10min
completed: 2026-08-14
status: complete
---

# Phase 14 Plan 2: Quantization Call-Site Wiring Summary

**All 21 existing `QuantizeFloatBuffer`/`QuantizeByteBuffer` call sites across 14 MNN/render processor files now resolve their scale/maskBits value from the job's schema via Plan 14-01's `ResolveQuantScale`/`ResolveByteQuantMode`, closing the "missed call site" risk by construction (a bare 2-arg call no longer compiles anywhere in this codebase)**

## Performance

- **Duration:** ~10 min
- **Completed:** 2026-08-14
- **Tasks:** 3
- **Files modified:** 14 (SGProcessingManager processor files) + 2 submodule pointer bumps (SuperGenius, outer repo)

## Accomplishments

- **Task 1** wired `ResolveQuantScale` into the 5 single/no-precedent float processors — `mnn_float.cpp` (2 call sites), `mnn_buffer.cpp`, `mnn_bool.cpp`, `mnn_image.cpp` (1 call site each), and `mnn_string.cpp` (1 call site, inserted immediately before the existing `maxLength` lookup block since this file has no vestigial suppression statement). 6 call sites total.
- **Task 2** wired `ResolveQuantScale` into the 5 double-call-site matrix/tensor/int processors — `mnn_mat4.cpp`, `mnn_mat3.cpp`, `mnn_mat2.cpp`, `mnn_int.cpp`, `mnn_tensor.cpp` — each with a per-chunk-loop call and a stitched-output call (identical shape across all 5 files). 10 call sites total.
- **Task 3** wired the 3 `ParseLayout`-family processors (`mnn_volume.cpp`, `mnn_texture1d.cpp`, `mnn_texturecube.cpp` — all 3 already consumed `parameters` via an existing `ParseLayout` call, making the suppression statement genuinely redundant even before this plan) and `render.cpp`'s single byte-path call site, resolving `ResolveByteQuantMode`/`maskBits` immediately after the existing `ResolveUniforms` call succeeds. 4 float call sites + 1 byte call site = 5 call sites total.
- **Total: 21/21 call sites wired** across all 14 processor files, matching RESEARCH.md's grep-confirmed enumeration exactly. Every vestigial `(void)parameters;` suppression statement (12 of the 14 files had one) is now gone, replaced by the file's own `ResolveQuantScale`/`ResolveByteQuantMode` call.
- `SGProcessors` CMake target (which statically links all 14 modified files) compiles cleanly against Plan 14-01's new required 3-arg signatures — no defaulted overload exists anywhere, so a missed call site would have failed to compile rather than silently continuing on stale behavior. None were missed.

## Task Commits

Each task was committed atomically inside the `SGProcessingManager` submodule, then its pointer bumped through `SuperGenius` and the outer repo:

1. **Task 1: Wire quantScale resolution into the 5 single/no-precedent float processors** — `d5caaba` (feat, in SGProcessingManager)
2. **Task 2: Wire quantScale resolution into the 5 double-call-site matrix/tensor/int processors** — `a9ae333` (feat, in SGProcessingManager)
3. **Task 3: Wire the 3 ParseLayout-family processors and render.cpp's byte-path call site** — `af6e324` (feat, in SGProcessingManager)

**Submodule pointer bumps:**
- SuperGenius: `eb2ee936` (chore: bump SGProcessingManager pointer)
- Outer repo: `617f24e` (chore: bump SuperGenius pointer)

## Files Created/Modified

- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_float.cpp` — resolves `scale` once, passes to both existing `QuantizeFloatBuffer` calls (per-chunk + stitched-output)
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_buffer.cpp` — resolves `scale`, passes to its single call site
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_bool.cpp` — resolves `scale`, passes to its single call site
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_image.cpp` — resolves `scale`, passes to its single call site
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_string.cpp` — resolves `scale` immediately before the existing `maxLength` lookup block (no suppression statement existed here); passes to its single call site
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_mat4.cpp` — resolves `scale`, passes to both call sites (per-chunk + stitched-output)
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_mat3.cpp` — same pattern as mat4
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_mat2.cpp` — same pattern as mat4
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_int.cpp` — same pattern as mat4
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_tensor.cpp` — same pattern as mat4
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_texture1d.cpp` — resolves `scale` (redundant-but-required alongside existing `ParseLayout` use), passes to its single call site
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_texturecube.cpp` — resolves `scale`, passes to both call sites (chunked-image branch + non-chunked float branch)
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_volume.cpp` — resolves `scale` (redundant-but-required alongside existing `ParseLayout` use), passes to its single call site
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp` — resolves `maskBits` via `ResolveByteQuantMode` right after the existing `ResolveUniforms` call succeeds, passes to its single `QuantizeByteBuffer` call site (the one byte-path call in this milestone)

## Decisions Made

- No deviations from the plan's literal recipe were needed. Every file's actual content (suppression-statement text and line position, call-site text and line position) matched 14-RESEARCH.md's and 14-PATTERNS.md's grep-confirmed enumeration exactly, verified by reading each file's relevant region before editing. Each of the plan's 3 tasks was applied verbatim.

## Deviations from Plan

None — plan executed exactly as written. All grep-confirmed line numbers, suppression-statement text, and call-site text matched the actual repository state precisely; no auto-fixes, blockers, or architectural questions arose.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration, no package-manager installs. All work is in-repo C++ source modification against existing CMake targets.

## Verification

- `grep -rc "(void)parameters;"` across all 12 files that previously had the vestigial suppression statement returns 0 for every file.
- Every one of the 21 grep-confirmed `QuantizeFloatBuffer`/`QuantizeByteBuffer` call sites across all 14 files now takes exactly 3 arguments (verified via grep for bare 2-arg call patterns — none found).
- `cmake --build SuperGenius/build/Windows/Debug --target SGProcessors --config Debug` succeeds with zero compile errors across all 14 modified files (only pre-existing, unrelated `libp2p`/`outcome.hpp` macro-redefinition warnings from the `thirdparty` submodule, untouched by this plan).

## Next Phase Readiness

- All 21 call sites across all 14 processor files are wired — this closes RESEARCH.md Pitfall 1's "missed call site" risk by construction (a bare 2-arg call no longer compiles anywhere in this codebase).
- `mnn_volume.cpp`'s newly-wired `ResolveQuantScale` call site is ready for Plan 14-03's tex3d/`spleen_ct_seg` binary search — Plan 14-03 can now declare a `quantScale` parameter in `texture3d-processing-definition.json` and have it flow through to this exact call site with no further infrastructure changes needed.
- No blockers identified for Plan 14-03.

---
*Phase: 14-configurable-normalization-precision*
*Completed: 2026-08-14*

## Self-Check: PASSED

- FOUND: all 14 modified processor files (SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_{float,buffer,bool,image,string,mat4,mat3,mat2,int,tensor,texture1d,texturecube,volume}.cpp, processing_processor_render.cpp)
- FOUND: 14-02-SUMMARY.md
- FOUND commit d5caaba (SGProcessingManager, Task 1)
- FOUND commit a9ae333 (SGProcessingManager, Task 2)
- FOUND commit af6e324 (SGProcessingManager, Task 3)
- FOUND commit eb2ee936 (SuperGenius, pointer bump)
- FOUND commit 617f24e (outer repo, pointer bump)
- FOUND commit ba29fb2 (outer repo, SUMMARY.md)
