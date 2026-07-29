---
phase: 01-vulkan-foundation-dispatch-plumbing
plan: 03
subsystem: infra
tags: [vulkan, vk-bootstrap, vendoring, cmake, decision-doc]

# Dependency graph
requires: ["01-02"]
provides:
  - "thirdparty/vk-bootstrap git submodule pinned at v1.4.357"
  - "ExternalProject_Add(vk-bootstrap) CMake build wiring"
  - "find_package(vk-bootstrap CONFIG) in SGProcessingManager cmake config"
  - "CTX-04 written decision (Vulkan-ValidationLayers deferral to v1.x)"
affects: [01-04-render-processor-context-creation]

# Tech tracking
tech-stack:
  added: ["vk-bootstrap v1.4.357 (MIT, charles-lunarg/vk-bootstrap)"]
  patterns:
    - "VulkanHeaders_DIR passed via CMAKE_CACHE_ARGS to ExternalProject_Add, reusing vendored Vulkan-Headers package — no second Vulkan-Headers copy"
    - "v1.3.302 is compatible with vk-bootstrap v1.4.357 — no bump needed"

key-files:
  modified:
    - thirdparty/.gitmodules
    - thirdparty/build/CommonTargets.cmake
    - SuperGenius/SGProcessingManager/cmake/CommonBuildParameters.cmake
  created:
    - SuperGenius/SGProcessingManager/doc/vulkan-validation-layers-decision.md
  vendored:
    - thirdparty/vk-bootstrap (git submodule)

key-decisions:
  - "vk-bootstrap pinned at tag v1.4.357 from plan 01-02's checkpoint verification"
  - "Used VulkanHeaders_DIR CMake package approach (not VK_BOOTSTRAP_VULKAN_HEADER_DIR raw include path) to let vk-bootstrap find vendored Vulkan-Headers without disabling its own install target — confirmed this path in vk-bootstrap's CMakeLists.txt lines 28-33"
  - "No Vulkan-Headers version bump required: vk-bootstrap minimum is Vulkan 1.1, current pin is v1.3.302"
  - "VK_BOOTSTRAP_TEST set to OFF to avoid vendoring Catch2 — tests not needed for a build dependency"

patterns-established:
  - "Thirdparty vendoring follows the existing ExternalProject_Add + find_package pattern already used by libp2p, spdlog, yaml-cpp, etc."

requirements-completed: [CTX-04]

coverage:
  - id: D1
    description: "vk-bootstrap is vendored at confirmed tag v1.4.357"
    requirement: "CTX-01"
    verification:
      - kind: unit
        ref: "git -C thirdparty submodule status vk-bootstrap == 556b79b165386f6c1a18362d30f2a076fdaa2778 vk-bootstrap (v1.4.357)"
        status: pass
    human_judgment: false
  - id: D2
    description: "ExternalProject_Add(vk-bootstrap) exists in CommonTargets.cmake with correct VulkanHeaders_DIR and DEPENDS"
    requirement: "CTX-01"
    verification:
      - kind: unit
        ref: "Select-String CommonTargets.cmake 'ExternalProject_Add(vk-bootstrap' and 'DEPENDS Vulkan-Headers' both present"
        status: pass
    human_judgment: false
  - id: D3
    description: "find_package(vk-bootstrap CONFIG) in SGProcessingManager's CommonBuildParameters.cmake"
    requirement: "CTX-01"
    verification:
      - kind: unit
        ref: "Select-String CommonBuildParameters.cmake 'find_package(vk-bootstrap CONFIG' == 1"
        status: pass
    human_judgment: false
  - id: D4
    description: "CTX-04 decision doc exists, names VALLAYER-01 tracking reference"
    requirement: "CTX-04"
    verification:
      - kind: unit
        ref: "test -f doc/vulkan-validation-layers-decision.md && Select-String doc 'VALLAYER-01' exists"
        status: pass
    human_judgment: false
  - id: D5
    description: "Build wiring is structurally correct — real build test deferred to environment with full thirdparty toolchain"
    requirement: "CTX-01"
    verification:
      - kind: manual
        ref: "CMake configure for the thirdparty build tree should succeed with DEPENDS Vulkan-Headers; SGProcessors target should resolve vk-bootstrap::vk-bootstrap"
        status: unverified
    human_judgment: true
    rationale: "This working copy does not have the full thirdparty build environment configured (Vulkan-Headers/Loader build dirs exist but cmake/configure-chain requires MSVC toolchain + full submodule checkout). A real cmake configure + build pass is recommended at the next build-enabled opportunity — plan 01-04's Task 3 (wiring RenderProcessor into SGProcessors CMakeLists.txt) provides a natural verification point."

duration: 18min
completed: 2026-07-29
status: complete
---

# Phase 01 Plan 03: vk-bootstrap Vendoring & Validation-Layers Deferral Summary

**Vendored vk-bootstrap v1.4.357 (MIT) as a git submodule with CMake ExternalProject_Add wiring, and documented Vulkan-ValidationLayers deferral (CTX-04). Plan 01-04's `RenderProcessor` can now link against `vk-bootstrap::vk-bootstrap`.**

## Performance

- **Duration:** 18 min
- **Started:** 2026-07-29
- **Completed:** 2026-07-29
- **Tasks:** 3
- **Files modified:** 3 (2 modified, 1 created)
- **New vendoring:** 1 submodule (vk-bootstrap)

## Accomplishments

- Added `thirdparty/vk-bootstrap` git submodule pinned to tag `v1.4.357` (confirmed by plan 01-02's checkpoint)
- Wired vk-bootstrap into the build pipeline: `ExternalProject_Add(vk-bootstrap ...)` in `thirdparty/build/CommonTargets.cmake` (inside the `if(NOT ANDROID)` block, after Vulkan-Loader), `find_package(vk-bootstrap CONFIG REQUIRED)` in `SuperGenius/SGProcessingManager/cmake/CommonBuildParameters.cmake`
- Confirmed vk-bootstrap's minimum Vulkan-Headers requirement is Vulkan 1.1 — no bump needed from current `v1.3.302` Vulkan-Headers pin
- Used `VulkanHeaders_DIR` CMake package approach (not `VK_BOOTSTRAP_VULKAN_HEADER_DIR` raw include path) to let vk-bootstrap find vendored Vulkan-Headers without disabling its own install target
- Created CTX-04 decision doc at `SuperGenius/SGProcessingManager/doc/vulkan-validation-layers-decision.md` tracking `VALLAYER-01` for v1.x

## Task Commits

Each task was committed atomically:

1. **Task 1: Vendor vk-bootstrap as pinned git submodule** — `df65f15` (thirdparty, `dev_rendering`)
2. **Task 2: Add CMake build wiring** — `f2546b6` (thirdparty, `dev_rendering`) + `1acc6c6` (SGProcessingManager, `dev_rendering`)
3. **Task 3: Document CTX-04 validation-layers deferral** — `f71e5e6` (SGProcessingManager, `dev_rendering`)

**Submodule pointer-bump chain:**
- SuperGenius (branch `dev_childwallet`): `7405c12c` — `chore(01-03): bump SGProcessingManager submodule pointer`
- GeniusNetwork root (branch `dev_persisprocresults`): `ed2ed06` — `chore(01-03): bump SuperGenius submodule pointer`

## Files Created/Modified

- `thirdparty/.gitmodules` — Added `[submodule "vk-bootstrap"]` block
- `thirdparty/build/CommonTargets.cmake` — Added `ExternalProject_Add(vk-bootstrap)` block with `DEPENDS Vulkan-Headers`
- `SuperGenius/SGProcessingManager/cmake/CommonBuildParameters.cmake` — Added `find_package(vk-bootstrap CONFIG REQUIRED)`
- `SuperGenius/SGProcessingManager/doc/vulkan-validation-layers-decision.md` — CTX-04 decision document (created)

## Decisions Made

- **VulkanHeaders_DIR approach chosen over VK_BOOTSTRAP_VULKAN_HEADER_DIR:** The raw-include-path option in vk-bootstrap's CMakeLists.txt (line 21-26) disables vk-bootstrap's `VK_BOOTSTRAP_INSTALL`, which would prevent `find_package(vk-bootstrap CONFIG)` from working. Using `VulkanHeaders_DIR:PATH=<INSTALL_DIR>/share/cmake/VulkanHeaders` lets vk-bootstrap's `find_package(VulkanHeaders CONFIG)` succeed, keeps install enabled, and requires zero changes to the vendored vk-bootstrap source.
- **No Vulkan-Headers version bump needed:** Verified vk-bootstrap's minimum requirement is Vulkan 1.1 (from README and CMakeLists.txt), and our pinned Vulkan-Headers is v1.3.302 — well within range.
- **VK_BOOTSTRAP_TEST=OFF:** Avoids vendoring Catch2 as a transitive test dependency — vk-bootstrap is a build dependency here, not a development target.

## Deviations from Plan

None — plan executed as written. The CMake approach (VulkanHeaders_DIR vs VK_BOOTSTRAP_VULKAN_HEADER_DIR) was confirmed by reading the live `vk-bootstrap/CMakeLists.txt` during implementation rather than relying on research speculation, but the plan itself instructed: "Set that variable via `CMAKE_CACHE_ARGS` ... matching whatever form the discovered option expects."

## Issues Encountered

- First `git submodule add` attempt created `thirdparty/thirdparty/vk-bootstrap` (nested path) because the command was run from GeniusNetwork root with a target path relative to wrong repo. Corrected by deinitializing, removing, and re-adding with path `vk-bootstrap` (relative to thirdparty repo root). No lasting damage.
- This working copy does not have the full thirdparty build environment configured — actual CMake configure/build verification deferred to plan 01-04's Task 3 (wiring RenderProcessor into SGProcessors) which requires a buildable environment.

## Next Phase Readiness

- Plan 01-04 (RenderProcessor headless Vulkan context) can now:
  - `#include <VkBootstrap.h>` from the vendored submodule
  - Link against `vk-bootstrap::vk-bootstrap` via the `find_package` in CommonBuildParameters.cmake
  - Acquire `sgns::sgprocessing::VulkanInitMutex()` from plan 01-01's header before any vkb::InstanceBuilder/DeviceBuilder calls

---

*Phase: 01-vulkan-foundation-dispatch-plumbing*
*Completed: 2026-07-29*

## Self-Check: PASSED

- FOUND: `thirdparty/vk-bootstrap/` submodule at tag v1.4.357
- FOUND: `ExternalProject_Add(vk-bootstrap` in `thirdparty/build/CommonTargets.cmake`
- FOUND: `find_package(vk-bootstrap` in `SuperGenius/SGProcessingManager/cmake/CommonBuildParameters.cmake`
- FOUND: `SuperGenius/SGProcessingManager/doc/vulkan-validation-layers-decision.md` with VALLAYER-01 reference
