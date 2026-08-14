---
phase: 14-configurable-normalization-precision
plan: 01
subsystem: infra
tags: [quantization, schema-config, cpp, cmake, nlohmann-json, gtest]

# Dependency graph
requires:
  - phase: 12-quantization-normalization-implementation
    provides: QuantizeFloatBuffer/QuantizeByteBuffer real implementations (D-03 through D-09 canonicalization + fixed-grid rounding), the S=2^15 constant this phase makes schema-overridable
  - phase: 13-re-validation-scope-boundary-documentation
    provides: S=2^15 as the confirmed-safe fallback constant (binary-search-against-SECV-01 methodology)
provides:
  - "sgns::sgprocmanagerquant::ResolveQuantScale/ResolveByteQuantMode free functions, centralized in quantization.hpp/.cpp"
  - "QuantizeFloatBuffer/QuantizeByteBuffer 3-arg required-parameter signatures (scale/maskBits), no 2-arg overload remains"
  - "sgprocmanagerquant CMake target now links nlohmann_json::nlohmann_json and exposes generated/ include path"
  - "18/18 passing quantization_test.cpp cases (7 pre-existing signature-migrated + 11 new fallback/boundary cases)"
affects: [14-02-call-site-wiring, 14-03-tex3d-empirical-precision]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Centralized find-by-name-in-parameters resolver (ResolveQuantScale/ResolveByteQuantMode) mirroring ParseLayout/mnn_string.cpp's maxLength convention, but single fixed key name (D-02) not a multi-key list"
    - "Integer bit-trick power-of-two validation (floor-equality + asInt & (asInt-1)==0), never log2/pow (Pitfall 2)"
    - "Required (non-defaulted) function parameters force every call site to explicitly resolve before calling (A2) -- a missed 14-02 call site fails to compile rather than silently using stale behavior"

key-files:
  created: []
  modified:
    - SuperGenius/SGProcessingManager/include/util/quantization.hpp
    - SuperGenius/SGProcessingManager/src/util/quantization.cpp
    - SuperGenius/SGProcessingManager/src/util/CMakeLists.txt
    - SuperGenius/SGProcessingManager/test/util/quantization_test.cpp

key-decisions:
  - "Included bare Parameter.hpp/ParameterType.hpp (matching the codebase's established convention, e.g. util/InputTypes.hpp's bare InputFormat.hpp) instead of the plan's literally-worded #include \"generated/Parameter.hpp\" -- the generated/ CMake include entry points directly at the generated directory itself (mirroring sgprocmanagertypes's identical pattern), so a generated/-prefixed include path would not resolve"
  - "Added ParameterType.hpp explicitly (plan named only Parameter.hpp) -- Parameter.hpp only forward-declares enum class ParameterType; the full enum definition with FLOAT/INT values is required at the point of comparison (param.get_type() == sgns::ParameterType::FLOAT)"

patterns-established:
  - "Quantization resolver fallback contract (D-04/D-05/D-07/D-08) is now the single source of truth every one of Plan 14-02's 21 call sites must call before invoking Quantize*Buffer"

requirements-completed: [QUANT-CFG-01, QUANT-CFG-02]

coverage:
  - id: D1
    description: "ResolveQuantScale/ResolveByteQuantMode resolve a schema-declared quantScale/byteQuantMode with the exact D-04/D-05/D-07/D-08 silent-fallback semantics (32768.0f / 0)"
    requirement: "QUANT-CFG-01"
    verification:
      - kind: unit
        ref: "SuperGenius/SGProcessingManager/test/util/quantization_test.cpp#QuantizationTest.ResolveQuantScale* (7 cases) / ResolveByteQuantMode* (5 cases)"
        status: pass
    human_judgment: false
  - id: D2
    description: "N=8 is a valid non-fallback byteQuantMode boundary (masks all 8 bits); N=9 falls back to 0"
    requirement: "QUANT-CFG-01"
    verification:
      - kind: unit
        ref: "SuperGenius/SGProcessingManager/test/util/quantization_test.cpp#QuantizationTest.ResolveByteQuantModeAcceptsBoundaryEight / ResolveByteQuantModeFallsBackJustAboveBoundary"
        status: pass
    human_judgment: false
  - id: D3
    description: "QuantizeFloatBuffer/QuantizeByteBuffer take the resolved value as a new required (non-defaulted) third parameter; no 2-arg overload remains; power-of-two check never uses log2/pow"
    requirement: "QUANT-CFG-02"
    verification:
      - kind: unit
        ref: "SuperGenius/SGProcessingManager/test/util/quantization_test.cpp (all 18 TEST_F cases build+pass against the new 3-arg signatures)"
        status: pass
      - kind: other
        ref: "grep -c \"log2|std::pow\" src/util/quantization.cpp returns 0 real usages (1 hit is a comment warning against them)"
        status: pass
    human_judgment: false

duration: 28min
completed: 2026-08-14
status: complete
---

# Phase 14 Plan 1: Quantization Resolver Infrastructure Summary

**Schema-configurable `quantScale`/`byteQuantMode` resolvers with silent v2.1-exact fallback (32768.0f / 0), threaded into `QuantizeFloatBuffer`/`QuantizeByteBuffer` as new required parameters, backed by 18/18 passing unit tests**

## Performance

- **Duration:** 28 min
- **Started:** 2026-08-14T01:00:00Z (approx.)
- **Completed:** 2026-08-14T01:28:00Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Added `ResolveQuantScale`/`ResolveByteQuantMode` free functions to `quantization.hpp`/`.cpp`, centralizing the D-01/D-02 find-by-name-in-`parameters` lookup with D-04/D-05/D-07/D-08's exact silent-fallback contract (32768.0f for any invalid/missing `quantScale`, 0 for any invalid/missing `byteQuantMode`)
- `IsPositivePowerOfTwo` validates `quantScale` using only the integer bit-trick (`floor` equality + `asInt & (asInt-1) == 0`), never `log2`/`pow`, per D-05/Pitfall 2 — deterministic across platforms
- `QuantizeFloatBuffer`/`QuantizeByteBuffer` now take a required third parameter (`scale`/`maskBits`); no defaulted overload exists anywhere, so Plan 14-02's 21 downstream call sites must all explicitly resolve or fail to compile
- `QuantizeByteBuffer` implements real D-06/D-07 bit-masking (`value &= ~((1<<N)-1)`), replacing the prior literal no-op; `maskBits<=0` preserves the exact v2.1 identity behavior
- `sgprocmanagerquant` CMake target gained the `generated/` include path and `nlohmann_json::nlohmann_json` link needed to compile against the new `Parameter.hpp`/`ParameterType.hpp` dependency
- Extended `quantization_test.cpp` from 7 to 18 `TEST_F` cases: all 7 pre-existing cases updated to the new 3-arg signatures, plus 11 new cases proving every fallback path and the explicit N=8 (valid)/N=9 (fallback) boundary

## Task Commits

Each task was committed atomically inside the `SGProcessingManager` submodule, then its pointer bumped through `SuperGenius` and the outer repo:

1. **Task 1: Add ResolveQuantScale/ResolveByteQuantMode and thread scale/maskBits through Quantize*Buffer** - `a71bfec` (feat, in SGProcessingManager)
2. **Task 2: Prove every fallback and boundary case with new quantization_test.cpp cases** - `1a46bfe` (test, in SGProcessingManager)

**Submodule pointer bumps:**
- SuperGenius: `006a95e3` (chore: bump SGProcessingManager pointer)
- Outer repo: `5305f5c` (chore: bump SuperGenius pointer)

_Note: both tasks carry `tdd="true"`; Task 1's commit also carries the 7 pre-existing tests migrated to the new 3-arg signature (their behavior/assertions are unchanged, only the call signature), and Task 2 adds the 11 new Resolve* fallback/boundary cases as its own atomic commit._

## Files Created/Modified
- `SuperGenius/SGProcessingManager/include/util/quantization.hpp` - Declares `ResolveQuantScale`/`ResolveByteQuantMode`; `QuantizeFloatBuffer`/`QuantizeByteBuffer` now take a required 3rd parameter; doc comments extended (not replaced) with the Phase 14 schema-configurability paragraph
- `SuperGenius/SGProcessingManager/src/util/quantization.cpp` - Implements both resolvers + `IsPositivePowerOfTwo`; `QuantizeFloatBuffer`'s final rounding branch now uses the `scale` parameter instead of a `kScale` constant; `QuantizeByteBuffer` implements real low-N-bit masking instead of a no-op
- `SuperGenius/SGProcessingManager/src/util/CMakeLists.txt` - `sgprocmanagerquant` target gains `generated/` include path (BUILD_INTERFACE + INSTALL_INTERFACE, mirroring `sgprocmanagertypes`) and `nlohmann_json::nlohmann_json` link
- `SuperGenius/SGProcessingManager/test/util/quantization_test.cpp` - All 7 pre-existing `TEST_F` cases updated to 3-arg calls; 11 new `TEST_F` cases + a `MakeParameters` test helper added

## Decisions Made
- Used bare `#include "Parameter.hpp"`/`#include "ParameterType.hpp"` instead of the plan's literally-worded `#include "generated/Parameter.hpp"` — confirmed via reading `sgprocmanagertypes`'s existing CMake target and `util/InputTypes.cpp`'s existing bare-include convention that the `generated/` CMake include-directory entry points directly at the `generated/` directory itself, so a `generated/`-prefixed include path would not resolve. This is the exact same include-path shape the plan's own CMakeLists.txt instructions specify (mirroring `sgprocmanagertypes`), just corrected to the include-statement style that path shape actually requires.
- Added `#include "ParameterType.hpp"` (plan named only `Parameter.hpp`) — `Parameter.hpp` only forward-declares `enum class ParameterType : int`; the full enum definition (with `FLOAT`/`INT` values) must be visible at the `param.get_type() == sgns::ParameterType::FLOAT` comparison sites inside `ResolveQuantScale`/`ResolveByteQuantMode`.
- Also added the `$<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/SGProcessingManager/generated>` entry to `sgprocmanagerquant`'s CMakeLists.txt (plan only explicitly required the `BUILD_INTERFACE` entry + the `nlohmann_json` link) — mirrors `sgprocmanagertypes`'s and `processors/CMakeLists.txt`'s complete pattern for consistency with the rest of the codebase's install-interface convention.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Corrected `generated/Parameter.hpp` include path to bare `Parameter.hpp`/`ParameterType.hpp`**
- **Found during:** Task 1 (writing `quantization.hpp`'s new includes)
- **Issue:** The plan's action text specifies `#include "generated/Parameter.hpp"`, but the plan's own CMakeLists.txt instruction adds `$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/../../generated>` as the include directory — this path points directly at the `generated/` folder itself (confirmed via `sgprocmanagertypes`'s identical existing pattern and `util/InputTypes.cpp`'s bare `#include <InputFormat.hpp>` convention), so a `generated/`-prefixed include statement would try to resolve `generated/generated/Parameter.hpp`, which does not exist.
- **Fix:** Used `#include "Parameter.hpp"` and `#include "ParameterType.hpp"` (the latter needed for the full `ParameterType` enum definition, not just `Parameter.hpp`'s forward declaration) — matching every other file in this codebase that consumes a `generated/` header via this exact CMake include-directory shape.
- **Files modified:** `SuperGenius/SGProcessingManager/include/util/quantization.hpp`
- **Verification:** `cmake --build` compiles cleanly; `ctest -R QuantizationTest` 18/18 pass.
- **Committed in:** `a71bfec` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 3 - blocking compile-path correction)
**Impact on plan:** Purely a correction to match the plan's own CMakeLists.txt instruction to the include-statement style that instruction's path shape requires. No scope creep — the resolved functions, fallback semantics, and file set are exactly as the plan specified.

## Issues Encountered
None beyond the include-path correction documented above.

## User Setup Required
None - no external service configuration required. No package-manager installs occurred (`nlohmann_json::nlohmann_json` is an existing project-vendored CMake imported target already used elsewhere in this repository, per the plan's threat model note).

## Next Phase Readiness
- `ResolveQuantScale`/`ResolveByteQuantMode` and the 3-arg `QuantizeFloatBuffer`/`QuantizeByteBuffer` signatures are ready for Plan 14-02 to wire into all 21 existing call sites across 14 processor files — every missed call site will fail to compile (by design, per A2), giving Plan 14-02 a hard compiler-enforced completeness check.
- Plan 14-03's tex3d/spleen_ct_seg empirical binary search can now declare a `quantScale` parameter in `texture3d-processing-definition.json` and have it flow through `ResolveQuantScale` with no further infrastructure changes needed.
- No blockers identified for Plan 14-02 or 14-03.

---
*Phase: 14-configurable-normalization-precision*
*Completed: 2026-08-14*

## Self-Check: PASSED

- FOUND: SuperGenius/SGProcessingManager/include/util/quantization.hpp
- FOUND: SuperGenius/SGProcessingManager/src/util/quantization.cpp
- FOUND: SuperGenius/SGProcessingManager/src/util/CMakeLists.txt
- FOUND: SuperGenius/SGProcessingManager/test/util/quantization_test.cpp
- FOUND commit a71bfec (SGProcessingManager, Task 1)
- FOUND commit 1a46bfe (SGProcessingManager, Task 2)
- FOUND commit 006a95e3 (SuperGenius, pointer bump)
- FOUND commit 5305f5c (outer repo, pointer bump)
