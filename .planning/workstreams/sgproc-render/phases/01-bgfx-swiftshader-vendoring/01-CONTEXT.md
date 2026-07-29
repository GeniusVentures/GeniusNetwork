# Phase 1: bgfx & SwiftShader Vendoring - Context

**Gathered:** 2026-07-28
**Status:** Ready for planning

<domain>
## Phase Boundary

bgfx and SwiftShader are vendored as new `thirdparty/` git submodules and made to build successfully through this repo's existing CMake vendoring convention — pure build-system plumbing. No runtime backend-selection logic, no headless context bring-up, no rendering logic is written or exercised in this phase (that's Phase 3). The only functional proof required is a trivial bgfx API call compiling and linking against the new submodule.

**Platform scope (already decided by prior research, not re-discussed here):** Windows, Linux, and macOS (via MoltenVK) only. Android/iOS are explicitly out of scope — `BGFX-HEADLESS-VERIFICATION.md` confirms this workstream targets SGProcessingManager's server/node deployment, never a mobile target, even though bgfx's Vulkan backend would technically build on Android too.

</domain>

<decisions>
## Implementation Decisions

### bgfx build integration
- **D-01:** bgfx has no official CMake build (it natively builds via GENie + bam/make). Wire it into the superbuild using `ExternalProject_Add` with a **custom `BUILD_COMMAND`** that invokes bgfx's own GENie/bam toolchain and stages the resulting static library — do **not** vendor the community `bgfx.cmake` wrapper as an additional submodule. This follows the same in-repo precedent already used for Boost (`thirdparty/build/Windows/CMakeLists.txt` — custom `b2` `BUILD_COMMAND`) and MoltenVK (`thirdparty/build/OSX/CMakeLists.txt` — custom `build.sh` wrapper).
- **D-02:** Whether the full `ExternalProject_Add(bgfx ...)` block is **duplicated per-platform** (the Boost pattern — each of `Windows/CMakeLists.txt`, `Linux/CMakeLists.txt`, `OSX/CMakeLists.txt` defines its own complete block because the build invocation differs meaningfully per platform) or **shared once in `CommonTargets.cmake`** with per-platform cache-arg variables set beforehand in each platform's own CMakeLists.txt (the MNN pattern — see `_MNN_EXTRA_PARAM` in `thirdparty/build/OSX/CMakeLists.txt` consumed by the single `ExternalProject_Add(MNN ...)` in `CommonTargets.cmake`) is **not decided here** — determine this empirically during research/planning by examining what bgfx's actual GENie/bam invocation needs per platform.

### Build footprint
- **D-03:** Compile bgfx with **only** the Vulkan (all platforms) and OpenGL (Linux) backends — restrict via bgfx's compile-time renderer config (`BGFX_CONFIG_RENDERER_*` defines). D3D11/D3D12/Metal are never compiled in. This is self-documenting alignment with the 3-tier design and keeps build time/binary size down.
- **D-04:** Build **only** SwiftShader's Vulkan ICD target (`vk_swiftshader`) and its ICD manifest — not SwiftShader's full repo. Confirmed with the user this loses no CPU-rendering capability: the 3-tier architecture (`FINAL-BACKEND-DECISION.md`) routes the software/CPU tier exclusively through SwiftShader's Vulkan ICD, never through its GL/D3D emulation layers, so those layers are architecturally unreachable in this design regardless.

### Submodule pinning strategy
- **D-05:** Pin bgfx, bx, bimg, and SwiftShader each to a **specific, tested commit SHA** — not tracking a default branch. Matches the reproducibility posture of existing `thirdparty/` submodules (MNN, libp2p, etc.); bgfx has no tagged releases at all, so a commit SHA is the only stable reference point regardless of preference.
- **D-06:** No specific commits are mandated by the user. `gsd-phase-researcher` selects the latest commit for each that builds cleanly and is consistent with the headless-Vulkan behavior already confirmed in `BGFX-HEADLESS-VERIFICATION.md`, and records the exact SHA chosen in RESEARCH.md/PLAN.md.

### Smoke-test target
- **D-07:** The trivial bgfx API-call test target (calls `bgfx::getRendererName()`, proves CMake wiring end-to-end per the roadmap's Success Criterion 4) is **kept permanently** in the tree, not deleted after Phase 1 — despite the roadmap's "throwaway" wording. It's cheap to maintain as a minimal CI build-health check, and gives Phase 5's `DETV-03` (CI installs/exercises the vendored SwiftShader ICD) a pre-existing hook to extend rather than building a smoke-test asset from scratch.

### Claude's Discretion
- Exact directory/target naming for the smoke-test target, and its precise location in the build tree (e.g. alongside `SuperGenius/example/*` or a new minimal location under `thirdparty/`) — planner's call.
- Whether bx/bimg are vendored as their own separate `thirdparty/` submodules (matching bgfx's expected sibling-repo layout) or nested some other way — research/planning call, informed by whatever the chosen bgfx commit's build actually expects.
- Exact `BGFX_CONFIG_RENDERER_*` define set needed to restrict compiled backends to Vulkan+GL per platform — planner's call, informed by bgfx's `src/config.h`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Architecture decision & research trail
- `.planning/workstreams/sgproc-render/research/FINAL-BACKEND-DECISION.md` — LOCKED decision to adopt bgfx + explicit 3-tier fallback (Vulkan hw → OpenGL Linux-only → Vulkan-via-SwiftShader); vendoring convention stated in its "Vendoring" section
- `.planning/workstreams/sgproc-render/research/BGFX-HEADLESS-VERIFICATION.md` — primary-source-grounded verification of bgfx's headless support per backend/platform; §"Per-Platform / Per-Backend Matrix" confirms Android/iOS are out of scope for this workstream's server/node deployment target
- `.planning/workstreams/sgproc-render/research/RENDER-BACKEND-DECISION.md` — prior reasoning step (superseded in part by FINAL-BACKEND-DECISION.md, but documents why raw-Vulkan-only was initially preferred before bgfx's app-level tier switching was reconsidered)
- `.planning/workstreams/sgproc-render/research/STACK.md` — original stack evaluation (superseded, kept for reasoning-trail context)

### Existing CMake vendoring convention (precedent to follow)
- `thirdparty/build/CommonTargets.cmake` — shared cross-platform `ExternalProject_Add` superbuild; see the existing Vulkan-Headers/Vulkan-Loader block (lines ~362-392) and the MNN block (lines ~394-416) as the "shared target, per-platform cache-arg vars" pattern
- `thirdparty/build/OSX/CMakeLists.txt` — MoltenVK's custom `BUILD_COMMAND`-wrapped `ExternalProject_Add` (non-CMake-native upstream build wrapped the same way bgfx will need to be); also defines `_MNN_EXTRA_PARAM`/`_MNN_DEPENDS` consumed by `CommonTargets.cmake`
- `thirdparty/build/Windows/CMakeLists.txt` — Boost's fully per-platform-duplicated `ExternalProject_Add` with custom `b2` `BUILD_COMMAND` (the "duplicate per platform" alternative pattern)
- `SuperGenius/SGProcessingManager/cmake/CommonBuildParameters.cmake` — how `find_package(Vulkan)` resolves against the vendored Vulkan-Loader via `VULKAN_SDK` env var; the pattern bgfx's own Vulkan backend must slot into without introducing a second Vulkan dependency tree (Success Criterion 3)
- `thirdparty/.gitmodules` — where new bgfx/bx/bimg/SwiftShader submodule entries get added (`thirdparty` is itself a nested git submodule of this repo — adding new submodules means committing inside `thirdparty`'s own repo first, then bumping this repo's `thirdparty` pointer)

### Requirements & roadmap
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` — CTX-04 (this phase's sole requirement)
- `.planning/workstreams/sgproc-render/ROADMAP.md` — Phase 1 goal, success criteria, and its explicit note that this phase has no dependency on Phase 2/3 schema or runtime work

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `thirdparty/build/OSX/CMakeLists.txt`'s MoltenVK `ExternalProject_Add` block — direct template for wrapping bgfx's non-CMake-native build with a custom `BUILD_COMMAND`.
- `thirdparty/build/CommonTargets.cmake`'s MNN block (`_MNN_EXTRA_PARAM`, `_MNN_DEPENDS` pattern) — template if bgfx's build turns out uniform enough per platform to share one `ExternalProject_Add`.

### Established Patterns
- Every existing `thirdparty/` dependency with a non-standard build (Boost, MoltenVK) is wrapped via `ExternalProject_Add` + custom `BUILD_COMMAND`/`PATCH_COMMAND`, installing into `${CMAKE_CURRENT_BINARY_DIR}/<name>` — never a raw `add_subdirectory()`. bgfx and SwiftShader should follow this same superbuild-via-install-prefix shape.
- Platform-conditional guards already exist at the top of `CommonTargets.cmake` (e.g. `if(NOT ANDROID)` around the Vulkan-Headers/Vulkan-Loader block) — the same mechanism applies for skipping Android/iOS entirely for bgfx/SwiftShader.

### Integration Points
- `find_package(Vulkan)` / `VULKAN_SDK` env var resolution in `SuperGenius/SGProcessingManager/cmake/CommonBuildParameters.cmake` is the exact point bgfx's Vulkan backend must resolve through, to satisfy Success Criterion 3 (no second/conflicting Vulkan dependency tree).
- `thirdparty/.gitmodules` is where the new submodule entries for bgfx, bx, bimg, and SwiftShader are added.

</code_context>

<specifics>
## Specific Ideas

No specific commits, versions, or exact file layouts were mandated — the user deferred those choices to the researcher/planner, with two firm constraints: (1) follow the existing `ExternalProject_Add`-based vendoring convention rather than adopting an external CMake wrapper project, and (2) don't let build-footprint restriction reduce actual CPU-rendering capability (confirmed it doesn't, given the architecture's SwiftShader usage is Vulkan-ICD-only).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. (Backend compile-scope questions that touch runtime tier *selection*, e.g. `BGFX_PCI_ID_SOFTWARE_RASTERIZER` forcing behavior, belong to Phase 3 per the roadmap and were not discussed here.)

</deferred>

---

*Phase: 1-bgfx-swiftshader-vendoring*
*Context gathered: 2026-07-28*
