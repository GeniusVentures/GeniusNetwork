---
phase: 02-manifest-model-cache
plan: 02
subsystem: capability
tags: [elm, capability, preflight, required-memory-bytes, host-ram, globalmemorystatusex, sysconf, sgcapability, sgprocessingmanager]

requires:
  - phase: 02-manifest-model-cache
    provides: plan 02-01 — generated ElmModelManifest/ElmModelRuntime types (generated/elmruntime-manifest/), TotalArtifactBytes arithmetic, by-value-optional materialization rule
provides:
  - "CapabilitySnapshot::availableMemoryBytes (uint64_t; 0 = query failed/degraded — same convention as availableDiskBytes)"
  - "QueryAvailableMemoryBytes() — GlobalMemoryStatusEx(ullTotalPhys) / sysconf(_SC_PHYS_PAGES * _SC_PAGE_SIZE); 0 on failure"
  - "CapabilityValidator::CheckElmResources(uint64_t requiredMemoryBytes, uint64_t totalArtifactBytes, const CanExecuteCallback&) — pass-free, manifest-free local ELM resource preflight (memory + disk legs)"
  - "sgns::elmruntime::ExtractElmResourceRequirements(manifest) -> ElmResourceRequirements{requiredMemoryBytes, totalArtifactBytes} — header-only bridge at the Phase 3 call site (include/elmruntime/ElmResourcePreflight.hpp)"
  - "sgproccapability_elm_resources_test — 18-case matrix, all green"
affects: [02-03 (acquire path), Phase 3 processor (CheckElmResources call site wiring via ExtractElmResourceRequirements), Phase 4 E2E]

tech-stack:
  added: []  # zero new dependencies (workstream D-003)
  patterns:
    - "generated-set isolation rule (hard constraint discovered): root generated/ quicktype set and generated/elmruntime-manifest/ fallback set BOTH define sgns::ClassMemberConstraints + sgns::ElmType under per-file #pragma once guards — a single TU including both is a class redefinition error; libraries must commit to one set and bridge via plain values"
    - "plain-values seam at library boundaries: CheckElmResources takes (uint64_t, uint64_t) so SGCapability never sees a manifest type and links nothing new; the elmruntime header extracts values at the call site"
    - "degraded-0 skip convention extended to host RAM: field==0 (query failed) skips the leg, identical to availableDiskBytes==0"
    - "clamp-before-cast for int64_t optionals: negative required_memory_bytes/size_bytes clamp to 0 before static_cast<uint64_t> (uint64 wraparound would create accidental impossible requirements)"

key-files:
  created:
    - SuperGenius/SGProcessingManager/include/elmruntime/ElmResourcePreflight.hpp
    - SuperGenius/SGProcessingManager/test/capability/elm_resources_test.cpp
    - SuperGenius/SGProcessingManager/test/capability/elm_resource_extraction_test.cpp
  modified:
    - SuperGenius/SGProcessingManager/include/capability/capability_types.hpp (availableMemoryBytes field)
    - SuperGenius/SGProcessingManager/include/capability/capability_validator.hpp (CheckElmResources declaration)
    - SuperGenius/SGProcessingManager/src/capability/capability_validator.cpp (QueryAvailableMemoryBytes + CheckElmResources impl + BuildSnapshot population)
    - SuperGenius/SGProcessingManager/src/elmruntime/CMakeLists.txt (registers ElmResourcePreflight.hpp header)
    - SuperGenius/SGProcessingManager/test/capability/CMakeLists.txt (sgproccapability_elm_resources_test target)

key-decisions:
  - "A3 resolved as RQ6 option (ii): host-RAM axis via GlobalMemoryStatusEx/sysconf (GPU-heap-only is wrong for CPU-backend models; disk-only leaves the field worthless)"
  - "Manifest-typed CheckElmResources overload DROPPED per the plan's pre-authorized fallback: the two quicktype generated sets cannot coexist in one TU (both define sgns::ClassMemberConstraints/ElmType) and capability headers transitively include the root set — the manifest overload would be a guaranteed redefinition error in every consumer TU. Plain-values overload only; extraction moved to sgns::elmruntime::ExtractElmResourceRequirements (header-only, fallback-set-only), which Phase 3 composes at the call site"
  - "Negative required_memory_bytes clamps to 0 at extraction (schema minimum does not survive codegen; int64→uint64 wraparound would fabricate a ~2^64 requirement)"
  - "Unmet-requirement details reuse FormatBytes and the Step-4 RESOURCE idiom: 'required_memory_bytes X exceeds available host memory Y' / 'Artifact bytes X exceed available disk space Y'"
  - "Exact-fit boundary is green: the comparison is strict > (a requirement equal to availability passes), mirroring the GPU-heap check"

patterns-established:
  - "generated-set isolation: a TU links itself to exactly ONE quicktype set (root generated/ OR generated/elmruntime-manifest/); cross-set communication happens through plain values extracted in a bridging header"
  - "two-TU test binary pattern: when a test matrix spans both generated sets, split into per-set TUs compiled into one gtest binary (elm_resources_test.cpp + elm_resource_extraction_test.cpp)"

requirements-completed: [MCHE-01]

coverage:
  - id: D1
    description: "Host-RAM snapshot field + platform query (Task 1)"
    requirement: MCHE-01
    verification:
      - kind: unit
        ref: "commit a63aa17; SGCapability builds clean; WMI confirms 68 GB phys RAM on host (query family nonzero)"
        status: pass
  - id: D2
    description: "CheckElmResources plain-values preflight (memory + disk legs, degraded-0 skip, log-then-fail) with CanExecute byte-untouched (Task 2)"
    requirement: MCHE-01
    verification:
      - kind: unit
        ref: "commit 99cdadc; git diff HEAD~2 -- src/capability/capability_validator.cpp shows 0 deletions (pure additions); SGCapability + sgprocmanagerelmruntime build clean"
        status: pass
  - id: D3
    description: "18-case mock-snapshot + manifest-extraction test matrix registered with sibling-matching gating (Task 3)"
    requirement: MCHE-01
    verification:
      - kind: unit
        ref: "commit 9f60a3a; sgproccapability_elm_resources_test 18/18 PASSED; ctest 20/20 from build/Windows/Release/test/capability; full standalone suite 17/17 binaries exit 0"
        status: pass

duration: 37min
completed: 2026-09-11
status: complete
---

# Phase 2 Plan 02: ELM Resource Preflight (CheckElmResources) Summary

**required_memory_bytes surfaced as a checked local preflight — CapabilitySnapshot gained a host-RAM axis (GlobalMemoryStatusEx/sysconf, degraded-0 convention) and CapabilityValidator gained a pass-free, manifest-free CheckElmResources(requiredMemoryBytes, totalArtifactBytes) with an elmruntime-side extraction bridge — 18/18 tests green, CanExecute byte-untouched.**

## Performance

- **Duration:** ~37 min
- **Started:** 2026-09-11T14:50Z
- **Completed:** 2026-09-11T15:07Z
- **Tasks:** 3/3
- **Files modified:** 8 (3 created, 5 modified)

## Exact Public Signatures (for plan 02-03 / Phase 3 wiring)

```cpp
// capability_validator.hpp — the ONLY new validator entry point (plain values):
void CapabilityValidator::CheckElmResources(
    uint64_t                  requiredMemoryBytes,  // runtime.required_memory_bytes; 0 = no requirement
    uint64_t                  totalArtifactBytes,   // sum of artifact size_bytes
    const CanExecuteCallback &callback );           // std::function<void(CanExecuteResult)>

// ElmResourcePreflight.hpp — the call-site bridge (header-only, inline):
namespace sgns::elmruntime {
struct ElmResourceRequirements {
    uint64_t requiredMemoryBytes = 0;
    uint64_t totalArtifactBytes  = 0;
};
ElmResourceRequirements ExtractElmResourceRequirements( const sgns::ElmModelManifest &manifest );
}

// capability_types.hpp — new snapshot field (populated by BuildSnapshot):
uint64_t availableMemoryBytes = 0;  // total physical host RAM; 0 = query failed (degraded)
```

**Unmet-requirement message formats** (category `UnmetRequirementCategory::RESOURCE`):
- Memory leg: `required_memory_bytes <Fmt> exceeds available host memory <Fmt>` (Fmt via existing FormatBytes, e.g. `2.0 GB`)
- Disk leg: `Artifact bytes <Fmt> exceed available disk space <Fmt>`
- Uninitialized validator: `CapabilityValidator not initialized`

**Phase 3 composition:**
```cpp
const auto reqs = sgns::elmruntime::ExtractElmResourceRequirements( manifest );
m_capabilityValidator->CheckElmResources(
    reqs.requiredMemoryBytes, reqs.totalArtifactBytes,
    [cb]( CanExecuteResult r ){ /* refuse acquire if !r.executable */ } );
```

## Accomplishments

- **Pitfall 13 / ELM-13 closed:** a node now refuses an ELM acquire whose model cannot fit BEFORE downloading hundreds of MB — memory leg (manifest requirement vs host RAM) + disk leg (artifact bytes vs free disk), both fail-closed as RESOURCE-category UnmetRequirements
- **A3 resolved:** host-RAM axis (RQ6 option ii) implemented with the same degraded-0 convention as disk — query failure skips the leg, never a false failure
- **CanExecute untouched:** `git diff` across the plan shows zero modified/deleted lines inside its body (purely additive changes elsewhere in the file) — zero regression surface for non-ELM capability checks
- **Zero new link dependencies:** SGCapability's CMakeLists untouched; the extraction bridge is a header registered in sgprocmanagerelmruntime's sources

## Task Commits

Each task was committed atomically (inside SuperGenius/SGProcessingManager on `dev_elmruntime`):

1. **Task 1: Host-RAM snapshot field + platform query** — `a63aa17` (feat)
2. **Task 2: CheckElmResources preflight + manifest value extraction** — `99cdadc` (feat)
3. **Task 3: Mock-snapshot ELM resource tests (18 cases)** — `9f60a3a` (test)

## Files Created/Modified

- `include/capability/capability_types.hpp` — `availableMemoryBytes` field appended (no existing field reordered; no positional aggregate-init found anywhere)
- `include/capability/capability_validator.hpp` — `CheckElmResources` declaration with Doxygen (local-only, no network advertising)
- `src/capability/capability_validator.cpp` — `QueryAvailableMemoryBytes()` beside the disk query; `BuildSnapshot` population; `CheckElmResources` implementation mirroring the Step-4 disk-check idiom
- `include/elmruntime/ElmResourcePreflight.hpp` — **new**: `ElmResourceRequirements` + `ExtractElmResourceRequirements` (by-value optionals materialized; negative clamps; inline artifact sum)
- `src/elmruntime/CMakeLists.txt` — registers the new header
- `test/capability/elm_resources_test.cpp` — **new**: 11 validator-leg cases (root generated set)
- `test/capability/elm_resource_extraction_test.cpp` — **new**: 7 extraction cases (fallback generated set, generated setters only)
- `test/capability/CMakeLists.txt` — `sgproccapability_elm_resources_test` target with sibling-matching gating

## Decisions Made

- **Manifest overload dropped via the plan's pre-authorized fallback** — see key-decisions; the plan explicitly said: *"if build friction appears, keep only the plain-values overload and let the call site extract values."* The friction is structural (generated-set redefinition), not incidental, so the fallback is permanent, not temporary
- **Two-TU test binary** instead of two test targets — one ctest registration, per-set TU isolation
- **Exact-fit is green** (strict `>` comparison) — mirrors the GPU-heap check's comparison semantics

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing functionality] Negative required_memory_bytes clamp**
- **Found during:** Task 2 (while implementing extraction)
- **Issue:** `ElmModelRuntime.hpp`'s schema comment promises "the C++ gate re-checks >= 0" but 02-01's `ElmManifest.cpp` gate never checks the runtime block; a negative value parsed into `int64_t` then cast to `uint64_t` wraps to ~2^64 — an accidental impossible requirement (fail-closed but misleading)
- **Fix:** `ExtractElmResourceRequirements` clamps negatives to 0; test-pinned (`NegativeRequiredMemoryClampsToZero`, `NegativeArtifactSizesExcludedFromSum`)
- **Files modified:** `include/elmruntime/ElmResourcePreflight.hpp`
- **Committed in:** `99cdadc`

**2. [Rule 3 - Blocking] Manifest-typed overload structurally unbuildable**
- **Found during:** Task 2 (pre-implementation analysis)
- **Issue:** Both quicktype sets define `sgns::ClassMemberConstraints` + `sgns::ElmType`; capability headers transitively include the root set — the overload's declaration and implementation TUs would need both sets simultaneously
- **Fix:** Plain-values overload only + `ExtractElmResourceRequirements` bridge in elmruntime (exactly the plan's pre-authorized fallback path); deviation is the *shape* (free function vs member overload), the *capability* (one-call composition) is preserved for Phase 3
- **Files modified:** `include/capability/capability_validator.hpp` (doc references the bridge), `include/elmruntime/ElmResourcePreflight.hpp`
- **Committed in:** `99cdadc`

**3. [Rule 1 - Bug] Test typo**
- **Found during:** Task 3 (compile)
- **Issue:** `100 * kTiBBytesForTest() )` — nonexistent constant + stray paren
- **Fix:** Added `kTiB` constant, fixed expression
- **Committed in:** `9f60a3a` (fixed before commit; never landed)

**4. [Rule 3 - Blocking] ElmType undefined in extraction test TU**
- **Found during:** Task 3 (compile)
- **Issue:** `ElmModelManifest.hpp` only forward-declares `sgns::ElmType`; the test sets the enum (02-01's `ElmManifest.cpp` gets the definition transitively via `Generators.hpp`)
- **Fix:** Explicit `#include "elmruntime-manifest/ElmType.hpp"` in the test TU
- **Committed in:** `9f60a3a`

**5. [Rule 1 - Cleanup] C4005 macro-redefinition warning in new test**
- **Found during:** Task 3 (build)
- **Issue:** `#define SGPROCMGR_TEST_FRIEND` duplicated the target_compile_definitions flag
- **Fix:** Removed the in-file define (comment documents where it comes from)
- **Committed in:** `9f60a3a`

---

**Total deviations:** 5 auto-fixed (1× Rule 2, 2× Rule 3, 2× Rule 1)
**Impact on plan:** All fixes necessary for correctness/buildability. The one shape deviation (manifest overload → extraction function) follows the plan's own pre-authorized fallback and preserves Phase 3's one-call composition. No scope creep.

## Issues Encountered

- Root `ctest --test-dir build/Windows/Release` reports "No tests were found!!!" — pre-existing condition (plan 02-01 hit the same); tests run per-directory (`ctest -C Release` from `build/Windows/Release/test/capability` → 20/20) or as direct binaries (17/17 exit 0)
- `cl` not on PATH in this shell — the Task 1 host-RAM sanity check used WMI instead (`Win32_ComputerSystem.TotalPhysicalMemory` = 68241707008 ≈ 63.6 GiB, same kernel query family, nonzero)

## Verification Results

| Check | Result |
|-------|--------|
| `SGCapability` build (Release) | clean, 0 errors |
| `sgprocmanagerelmruntime` build | clean |
| `sgproccapability_elm_resources_test` build | clean (after ElmType fix) |
| New test binary direct run | **18/18 PASSED**, exit 0 |
| ctest from `test/capability` | **20/20** (18 new per-case + 2 whole-binary, incl. pre-existing CapabilityValidatorTest) |
| Full standalone suite | **17/17 binaries exit 0** |
| CanExecute body untouched | git diff: **0 deleted lines** in `capability_validator.cpp` across the plan (99 insertions, 0 deletions) |
| Snapshot struct additive | 1 line added to `capability_types.hpp`, no reordering |
| Host-RAM query nonzero on host | 68 GB physical (WMI) |
| Test gating matches sibling | `SGPROC_TEST_DISCOVERY AND NOT CMAKE_CROSSCOMPILING` present |
| Injection-only tests | zero BuildSnapshot/Vulkan/network calls (grep: comment-only matches) |
| Manifest test cases via setters only | yes (no JSON parsing in extraction TU) |

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **For plan 02-03 (ElmModelCache):** the preflight is ready to call from the acquire path — compose `ExtractElmResourceRequirements` + `CheckElmResources` as shown above; refusal blocks the download before any bytes move
- **For Phase 3 (processor):** the validator half ships complete; wiring is two lines at the acquire decision point
- **Generated-set isolation rule** is now a hard documented constraint — any future code mixing the root and elmruntime-manifest quicktype sets in one TU will fail to compile; bridge via plain values (pattern established in `ElmResourcePreflight.hpp`)
- No blockers

## Self-Check: PASSED

- All 3 task commits exist on `dev_elmruntime`: a63aa17, 99cdadc, 9f60a3a (verified via `git log`)
- All 8 created/modified files exist on disk (verified via `git status` clean + files tracked)
- All acceptance criteria re-verified post-commit (see Verification Results)

---
*Phase: 02-manifest-model-cache*
*Plan: 02*
*Completed: 2026-09-11*
