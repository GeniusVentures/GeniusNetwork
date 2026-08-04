# Phase 1: bgfx & SwiftShader Vendoring - Research

**Researched:** 2026-07-28
**Domain:** CMake superbuild vendoring (`ExternalProject_Add` convention) of two new third-party C++ dependencies — `bgfx.cmake` (which nests bgfx/bx/bimg) and `google/swiftshader` (scoped to its `vk_swiftshader` Vulkan ICD target)
**Confidence:** HIGH — every load-bearing claim below is grounded in a direct raw-source read of the actual upstream repos (`bkaradzic/bgfx.cmake`, `bkaradzic/bgfx`, `google/swiftshader`) fetched and grepped directly, plus GitHub REST API calls for exact commit SHAs — not search-snippet summaries. This continues the same evidentiary standard `BGFX-HEADLESS-VERIFICATION.md` already established for this workstream.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01 (revised 2026-07-28):** Adopt **`bgfx.cmake`** (vendored as one additional `thirdparty/` submodule) rather than wrapping bgfx's native GENie/bam build in a custom `ExternalProject_Add` `BUILD_COMMAND`. The correct, current repo is **`bkaradzic/bgfx.cmake`** (moved there from `widberg/bgfx.cmake`).
- **D-02 (revised 2026-07-28):** Confirm during research whether `bgfx.cmake` is added via `ExternalProject_Add` (matching every other `thirdparty/` dependency) or `add_subdirectory()` (bgfx.cmake's own documented in-tree usage). **Resolved by this research: see "Standard Stack" and "Architecture Patterns" below — `ExternalProject_Add` is viable and recommended.**
- **D-02b (settled):** bx and bimg do **not** need their own top-level `thirdparty/` submodule entries — `bkaradzic/bgfx.cmake` already carries bgfx, bx, and bimg as its own nested submodules. Adding **one** `thirdparty/.gitmodules` entry for `bgfx.cmake` (recursively initialized) is sufficient.
- **D-03:** Compile bgfx with **only** the Vulkan (all platforms) and OpenGL (Linux) backends — restrict via bgfx's compile-time renderer config (`BGFX_CONFIG_RENDERER_*` defines). D3D11/D3D12/Metal are never compiled in.
- **D-04:** Build **only** SwiftShader's Vulkan ICD target (`vk_swiftshader`) and its ICD manifest — not SwiftShader's full repo.
- **D-05:** Pin `bgfx.cmake` (which transitively pins bgfx/bx/bimg) and SwiftShader each to a **specific, tested commit SHA** — not tracking a default branch.
- **D-06:** No specific commits are mandated by the user. `gsd-phase-researcher` selects the latest `bkaradzic/bgfx.cmake` commit (and whatever bgfx/bx/bimg SHAs it pins) that builds cleanly and is consistent with `BGFX-HEADLESS-VERIFICATION.md`, plus a matching SwiftShader commit, and records the exact SHAs chosen (**done below — see "Standard Stack"**).
- **D-07:** The trivial bgfx API-call test target (`bgfx::getRendererName()`) is **kept permanently** in the tree, not deleted after Phase 1.

### Claude's Discretion

- Exact directory/target naming for the smoke-test target, and its precise location in the build tree (e.g. alongside `SuperGenius/example/*` or a new minimal location under `thirdparty/`) — planner's call.
- Exact `bkaradzic/bgfx.cmake` commit to pin — **research call, resolved below**.
- Whether bgfx (via `bgfx.cmake`) is wired in via `ExternalProject_Add` or `add_subdirectory()` (see D-02) — **research call, resolved below**.
- Exact `BGFX_CONFIG_RENDERER_*` / `bgfx.cmake`-equivalent CMake options needed to restrict compiled backends to Vulkan+GL per platform — planner's call, informed by the exact mechanism documented below.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope. Backend compile-scope questions that touch runtime tier *selection* (e.g. `BGFX_PCI_ID_SOFTWARE_RASTERIZER` forcing behavior) belong to Phase 3 and were not discussed here.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CTX-04 | bgfx and SwiftShader vendored as new `thirdparty/` git submodules via the existing `CommonBuildParameters.cmake`/`CommonTargets` convention, alongside already-vendored Vulkan-Headers/Vulkan-Loader/MoltenVK; bgfx's Vulkan backend confirmed to route through MoltenVK unchanged on macOS/iOS | This document's entire "Standard Stack", "Architecture Patterns", and "Code Examples" sections: exact commit SHAs, `ExternalProject_Add` wiring pattern reusing `CommonTargets.cmake` conventions, and the primary-source-verified proof that bgfx's Vulkan backend never build-time-links a Vulkan loader (runtime `dlopen`/`LoadLibrary` only) — so MoltenVK/Vulkan-Loader routing on every platform is a **runtime library-path** concern, not a CMake link-graph concern |

</phase_requirements>

## Summary

Both new dependencies are added the same way every other `thirdparty/` dependency is: `ExternalProject_Add` blocks in `thirdparty/build/CommonTargets.cmake`, following the exact `PREFIX`/`SOURCE_DIR`/`CMAKE_CACHE_ARGS`/`INSTALL_DIR` shape already used for Vulkan-Headers, Vulkan-Loader, and MNN. No exception to this repo's superbuild convention is needed for either dependency — a finding that revises the working assumption in `01-CONTEXT.md` D-02, which left open whether `bgfx.cmake` would require `add_subdirectory()`.

**bgfx.cmake** ships a full `install(EXPORT ...)` producing `bgfxConfig.cmake`/`bgfxTargets.cmake` (target `bgfx::bgfx`) when its own `BGFX_INSTALL` option is `ON` (the default) — so `ExternalProject_Add` + `find_package(bgfx CONFIG REQUIRED)` works cleanly. The one piece that looked like it might force `add_subdirectory()` — injecting the `BGFX_CONFIG_RENDERER_*` preprocessor defines needed for D-03's backend restriction — turns out to have its own dedicated escape hatch: `BGFX_CMAKE_USER_SCRIPT`, a cache variable bgfx.cmake's root `CMakeLists.txt` `include()`s before configuring the bx/bimg/bgfx subdirectories, and which the generated `bgfxConfig.cmake` re-includes on the consumer side too. Passing `-DBGFX_CMAKE_USER_SCRIPT:STRING=<path-to-a-small-.cmake-file>` as a `CMAKE_CACHE_ARGS` entry on the `ExternalProject_Add(bgfx)` call is the clean, idiomatic, in-superbuild-convention way to set `BGFX_CONFIG_RENDERER_VULKAN=1` (and, Linux-only, `BGFX_CONFIG_RENDERER_OPENGL=21`) globally for that build.

**bgfx's Vulkan backend never links a Vulkan loader at build time.** `renderer_vk.cpp` dynamically loads `vulkan-1.dll`/`libvulkan.so`/`libvulkan.so.1` at *runtime* via `bx::dlopen`/`bx::dlsym` — bgfx compiles against its own bundled Vulkan headers (`${BGFX_DIR}/3rdparty/khronos`), never `find_package(Vulkan)`. This resolves Success Criterion 3 and D-06 open item #6 directly: there is no possible build-time Vulkan header/link conflict between bgfx.cmake and this repo's vendored Vulkan-Headers/Vulkan-Loader, because bgfx never touches the project's Vulkan CMake target at all. The "single Vulkan dependency tree" requirement reduces to a **runtime library-path** concern — the project's already-built Vulkan-Loader shared library (or the SwiftShader ICD, once forced via `VK_ICD_FILENAMES`/`BGFX_PCI_ID_SOFTWARE_RASTERIZER` in Phase 3) must be discoverable by the OS loader (`LD_LIBRARY_PATH`/`PATH`/rpath) when the bgfx-linked executable runs — not a CMake-time problem this phase needs to solve, only one it must not accidentally block (e.g. by not shipping a second, conflicting `libvulkan.so` next to the smoke-test binary).

**SwiftShader has no CMake install() surface at all** — it is an in-tree-only CMake project. `vk_swiftshader` (a `SHARED` library target) is built unconditionally as part of `add_subdirectory(src/Vulkan)`, and its ICD JSON manifest is generated via `configure_file()` at CMake *configure* time (not build time) into `${CMAKE_BINARY_DIR}/${CMAKE_SYSTEM_NAME}/vk_swiftshader_icd.json`, referencing the shared lib via a relative path — the two files must stay side-by-side. Scoping the build to just `vk_swiftshader` (D-04) means: (a) turn off `SWIFTSHADER_BUILD_TESTS`/`SWIFTSHADER_BUILD_BENCHMARKS`/`SWIFTSHADER_BUILD_PVR`/`BUILD_VULKAN_WRAPPER` via `CMAKE_CACHE_ARGS` (this also skips several heavy nested submodules entirely — googletest, benchmark, PowerVR_Examples, glslang), and (b) point `ExternalProject_Add`'s `BUILD_COMMAND` at the specific `vk_swiftshader` target rather than the default "build everything configured" behavior. Because there's no `install()`, the `ExternalProject_Add`'s `INSTALL_COMMAND` must be a manual `${CMAKE_COMMAND} -E copy` of the built shared lib + generated ICD JSON into `<INSTALL_DIR>/lib` — mirroring the `STB` entry's already-existing custom-`INSTALL_COMMAND` pattern in `CommonTargets.cmake`, not the `CMAKE_CACHE_ARGS` pattern used for CMake-package-exporting deps.

**Primary recommendation:** Wire both dependencies into `CommonTargets.cmake` via `ExternalProject_Add`, matching the existing Vulkan-Headers/Vulkan-Loader/MNN block shape exactly — no exception to the established convention needed for either dependency. Pin `bgfx.cmake` at `5b418ad60dc4445a56e4b11f6cf5c8f27e137372` (2026-07-25) and SwiftShader at `a7c547b55474c3d8bde53711eae24ae0e28bbc0a` (2026-07-07), both current `master` HEAD at time of research.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| bgfx/SwiftShader source vendoring (git submodules) | Build System / thirdparty | — | Pure source-acquisition concern, lives entirely in `thirdparty/.gitmodules` |
| bgfx/SwiftShader compilation (CMake superbuild) | Build System / thirdparty | — | `ExternalProject_Add` blocks in `thirdparty/build/CommonTargets.cmake`, same tier as every other vendored dep |
| Renderer-backend compile-time restriction (`BGFX_CONFIG_RENDERER_*`) | Build System / thirdparty | — | Injected via `BGFX_CMAKE_USER_SCRIPT` at bgfx's own CMake configure time — a build-system concern, not application code |
| Vulkan loader discovery at runtime (dlopen of `libvulkan.so`/`vulkan-1.dll`) | Backend / Application runtime | Build System (must ship the artifact) | bgfx itself performs the `dlopen`; the build system's only job is ensuring the right `.so`/`.dll` ends up on the runtime search path — this is Phase 3's concern (headless init), not Phase 1's, beyond not breaking it |
| SGProcessingManager linking against `bgfx::bgfx` / `vk_swiftshader` artifacts | Backend / SGProcessingManager | Build System | `find_package(bgfx CONFIG)` resolution happens in `SGProcessingManager/cmake/CommonBuildParameters.cmake`, matching MNN's existing pattern |
| Smoke-test target (`bgfx::getRendererName()`) | Build System / thirdparty (or SuperGenius/example) | — | Proves CMake wiring end-to-end; no runtime backend-selection logic — stays at build-verification tier per D-07 |

## Standard Stack

### Core

| Library | Version (pinned commit) | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `bkaradzic/bgfx.cmake` | `5b418ad60dc4445a56e4b11f6cf5c8f27e137372` (master HEAD, 2026-07-25, "deps: bump bgfx, bimg, and bx") [VERIFIED: GitHub REST API `api.github.com/repos/bkaradzic/bgfx.cmake/commits/master`] | CMake wrapper build for bgfx, bx, bimg | Maintained by bgfx's own upstream author (bkaradzic) since the repo moved there from `widberg/bgfx.cmake`; only realistic CMake path for bgfx (upstream bgfx itself has no first-party CMake support, only GENie/bam) |
| `bkaradzic/bgfx` (nested submodule of bgfx.cmake) | `7551ac61c55aab31610a6c0c3ce1151678799415` [VERIFIED: GitHub contents API, submodule entry at bgfx.cmake HEAD] | Rendering abstraction library | Already the LOCKED architecture decision (`FINAL-BACKEND-DECISION.md`) |
| `bkaradzic/bx` (nested submodule) | `cd6720ce9a4555a083dd342925b29837149b1629` [VERIFIED: GitHub contents API] | bgfx's base/platform library | Required transitive dependency, pinned by bgfx.cmake itself |
| `bkaradzic/bimg` (nested submodule) | `0a64629d9fb3fffc5165388e0166661f581dfb68` [VERIFIED: GitHub contents API] | bgfx's image-processing library | Required transitive dependency, pinned by bgfx.cmake itself |
| `google/swiftshader` | `a7c547b55474c3d8bde53711eae24ae0e28bbc0a` (master HEAD, 2026-07-07) [VERIFIED: GitHub REST API `api.github.com/repos/google/swiftshader/commits/master`] | Software Vulkan ICD (CPU rasterizer) for the tertiary fallback tier | LOCKED architecture decision; only actively-maintained standalone-CMake CPU Vulkan ICD (vs. Mesa lavapipe's full Meson/Mesa-tree dependency, deferred to v2 `LAVAPIPE-01`) |

All four pins are single-source-of-truth verifiable: re-running the same GitHub API/contents calls against the pinned SHA will reproduce the identical nested-submodule tree, so "pin `bgfx.cmake`" transitively and reproducibly pins bgfx/bx/bimg too, satisfying D-02b/D-05 without any additional `thirdparty/.gitmodules` entries for bx/bimg.

**Note on pin freshness:** Both SHAs are `master`/HEAD at time of research (2026-07-28/29). Per D-05/D-06, these are commit-SHA pins (not floating branch tracking) — the planner should treat these as the exact SHAs to check out, and re-verify they still build cleanly against this project's toolchain during Phase 1 execution (neither repo has tagged releases, so there is no "latest stable tag" alternative to a HEAD pin).

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| (none new) | — | — | bgfx.cmake and SwiftShader are each fully self-contained CMake projects; no additional `thirdparty/` entries are required beyond the two new submodules |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `bgfx.cmake`'s `ExternalProject_Add` + `find_package(bgfx CONFIG)` | `add_subdirectory()` (bgfx.cmake's own primary documented usage) | Both work; `ExternalProject_Add` was chosen for convention-consistency with every other `thirdparty/` dep in this repo (Boost, MoltenVK, MNN, Vulkan-Headers/Loader) — see "Architecture Patterns" for the full reasoning, since this contradicts the initial "add_subdirectory may be required" assumption in D-02 |
| SwiftShader software Vulkan ICD | Mesa lavapipe | Explicitly deferred to v2 (`LAVAPIPE-01`) — lavapipe reportedly faster but requires vendoring the full Mesa/Meson build tree vs. SwiftShader's standalone CMake repo; not revisited in this phase |
| SwiftShader `REACTOR_BACKEND=LLVM` (default, prebuilt LLVM 16.0 vendored directly in-repo) | `REACTOR_BACKEND=LLVM-Submodule` (build full LLVM from source) or `REACTOR_BACKEND=Subzero` (Google's lighter in-house JIT) | Default `LLVM` avoids both the heaviest option (building LLVM from source) and the `llvm-project` submodule fetch entirely — recommended default; `Subzero` is a fallback worth testing only if the prebuilt LLVM tree proves incompatible with a target platform/compiler, not otherwise |

**Installation (conceptual — see Code Examples for the actual `CommonTargets.cmake` blocks):**
```bash
# thirdparty/.gitmodules gets ONE new entry (bgfx.cmake, recursively initialized)
# and ONE new entry (swiftshader) -- both are added as git submodules, not npm/pip installs.
git submodule add https://github.com/bkaradzic/bgfx.cmake.git thirdparty/bgfx.cmake
git -C thirdparty/bgfx.cmake checkout 5b418ad60dc4445a56e4b11f6cf5c8f27e137372
git -C thirdparty/bgfx.cmake submodule update --init --recursive   # pulls bgfx/bx/bimg at their pinned SHAs

git submodule add https://github.com/google/swiftshader.git thirdparty/swiftshader
git -C thirdparty/swiftshader checkout a7c547b55474c3d8bde53711eae24ae0e28bbc0a
# Do NOT recursively init all of SwiftShader's own submodules -- see Pitfall 3.
```

**Version verification performed:** Both commit SHAs were confirmed live against `api.github.com/repos/<org>/<repo>/commits/master` at research time (2026-07-28/29). No published/tagged releases exist for either repo (confirmed by absence of a `/releases` reference in either README and by D-05's own note that "bgfx has no tagged releases at all").

## Package Legitimacy Audit

> This phase vendors two **git submodules** (C++ source trees), not npm/PyPI/crates registry packages — `gsd-tools query package-legitimacy check` correctly returns `does-not-exist`/`SLOP` for both names when run against the `npm` ecosystem, since neither is a registry package at all. This is an ecosystem mismatch, not a legitimacy red flag; a manual git-provenance assessment substitutes for the registry-based gate below.

| Dependency | Registry check | Maintainer/org | Repo age & activity | Verdict | Disposition |
|---|---|---|---|---|---|
| `bkaradzic/bgfx.cmake` | N/A (not a registry package) [ASSUMED — package-legitimacy tool ecosystem mismatch, confirmed via manual `does-not-exist` run] | Owned by `bkaradzic` — bgfx's own upstream author/maintainer (per D-01's own note, and confirmed by the repo having moved there from a third-party fork `widberg/bgfx.cmake`) | Actively committed against — HEAD commit is dated 2026-07-25, days before this research | OK (manual assessment) | Approved |
| `google/swiftshader` | N/A (not a registry package) [ASSUMED — same tool ecosystem mismatch] | Owned by Google's official `google` GitHub org; also mirrored at `swiftshader.googlesource.com` (Google's internal Gerrit, referenced directly in its own README) | Actively committed — HEAD commit dated 2026-07-07 | OK (manual assessment) | Approved |
| `bkaradzic/bgfx` / `bkaradzic/bx` / `bkaradzic/bimg` (nested submodules, not separately vendored) | N/A — pulled transitively via bgfx.cmake's own pinned `.gitmodules`, not independently added to this project's `thirdparty/.gitmodules` | Same maintainer (`bkaradzic`) as bgfx.cmake | Locked to the exact SHAs bgfx.cmake itself pins at its HEAD (see Standard Stack table) | OK (manual assessment, inherited) | Approved — no separate vetting needed per D-02b |

**Packages removed due to `[SLOP]` verdict:** none — both raw `package-legitimacy check` runs against `npm` returned `does-not-exist`, which is an ecosystem-mismatch artifact (these are git submodules, never published to npm), not a genuine slopsquatting signal. Manual verification (maintainer identity, commit recency, official-org ownership) substitutes.
**Packages flagged as suspicious `[SUS]`:** none.

## Architecture Patterns

### System Architecture Diagram

```
                    thirdparty/.gitmodules (2 new entries)
                              |
          +-------------------+-------------------+
          |                                        |
   bgfx.cmake (submodule,                  swiftshader (submodule,
   recursively pins bgfx/bx/bimg)          pinned SHA, partial init)
          |                                        |
          v                                        v
  ExternalProject_Add(bgfx)                ExternalProject_Add(swiftshader)
  in CommonTargets.cmake                   in CommonTargets.cmake
          |                                        |
  CMAKE_CACHE_ARGS:                        CMAKE_CACHE_ARGS:
   -DBGFX_CMAKE_USER_SCRIPT=<path>           -DSWIFTSHADER_BUILD_TESTS=OFF
     (sets BGFX_CONFIG_RENDERER_VULKAN=1,    -DSWIFTSHADER_BUILD_BENCHMARKS=OFF
      +OPENGL=21 on Linux only)              -DSWIFTSHADER_BUILD_PVR=FALSE
   -DBGFX_BUILD_TESTS=OFF                    -DBUILD_VULKAN_WRAPPER=OFF
   -DBGFX_BUILD_EXAMPLES=OFF
   -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>     BUILD_COMMAND: explicit
          |                                  --target vk_swiftshader
          v                                        |
  install(EXPORT) -> bgfxConfig.cmake        INSTALL_COMMAND: manual
  exposes target bgfx::bgfx                  `cmake -E copy` of
          |                                  libvk_swiftshader.{so,dll}
          v                                  + vk_swiftshader_icd.json
  find_package(bgfx CONFIG)                  into <INSTALL_DIR>/lib
  in SGProcessingManager/cmake/                     |
  CommonBuildParameters.cmake                       v
          |                                  (consumed only by Phase 3's
          v                                   runtime ICD-forcing logic
  target_link_libraries(                       and Phase 5's CI —
    smoke_test_target                          NOT linked at build time
    PRIVATE bgfx::bgfx)                        by anything in Phase 1)
          |
          v
  smoke_test executable calls
  bgfx::getRendererName() --
  compiles + links, proving
  CMake wiring end-to-end
  (no bgfx::init() call, no
  headless context, no Vulkan-
  Loader linkage required)
```

### Recommended Project Structure
```
thirdparty/
├── .gitmodules                     # +2 entries: bgfx.cmake, swiftshader
├── bgfx.cmake/                     # new submodule (recursively pins bgfx/bx/bimg)
└── swiftshader/                    # new submodule (partial init — see Pitfall 3)

thirdparty/build/
├── CommonTargets.cmake             # +2 ExternalProject_Add blocks (bgfx, swiftshader)
└── bgfx-user-config.cmake          # NEW small file: sets BGFX_CONFIG_RENDERER_* defines,
                                     # referenced via BGFX_CMAKE_USER_SCRIPT cache arg

SuperGenius/SGProcessingManager/cmake/CommonBuildParameters.cmake
                                     # +find_package(bgfx CONFIG REQUIRED)
                                     # (SwiftShader/vk_swiftshader is NOT find_package'd --
                                     #  no CMake package config exists for it; Phase 3/5
                                     #  reference it by installed file path only)

<wherever the planner locates the smoke-test target per D-07/Claude's Discretion>
└── CMakeLists.txt                  # trivial executable calling bgfx::getRendererName(),
                                     # target_link_libraries(... PRIVATE bgfx::bgfx)
```

### Pattern 1: ExternalProject_Add for a CMake-package-exporting dependency (bgfx)
**What:** Standard superbuild block matching the existing Vulkan-Headers/Vulkan-Loader/MNN shape in `CommonTargets.cmake` — `PREFIX`, `SOURCE_DIR` pointing at the submodule, `CMAKE_CACHE_ARGS` with `CMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>`, then `set(_FINDPACKAGE_..._DIR ...)` for downstream `find_package()` resolution.
**When to use:** Any vendored dependency that itself produces an `install(EXPORT ...)` CMake package config (bgfx.cmake does — confirmed via direct read of its root `CMakeLists.txt`, `BGFX_INSTALL` defaults `ON`).
**Example:**
```cmake
# Source: bkaradzic/bgfx.cmake root CMakeLists.txt (direct raw-file read, master HEAD 5b418ad),
# adapted to this repo's existing CommonTargets.cmake conventions.
ExternalProject_Add(bgfx
    PREFIX bgfx
    SOURCE_DIR "${THIRDPARTY_DIR}/bgfx.cmake"
    CMAKE_CACHE_ARGS
    -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
    -DBGFX_BUILD_EXAMPLES:BOOL=OFF
    -DBGFX_BUILD_TESTS:BOOL=OFF
    -DBGFX_INSTALL:BOOL=ON
    -DBGFX_CMAKE_USER_SCRIPT:STRING=${CMAKE_CURRENT_LIST_DIR}/bgfx-user-config.cmake
    ${_CMAKE_COMMON_CACHE_ARGS}
)
ExternalProject_Get_Property(bgfx INSTALL_DIR)
set(_FINDPACKAGE_BGFX_CONFIG_DIR "${INSTALL_DIR}/lib/cmake/bgfx")
```

```cmake
# thirdparty/build/bgfx-user-config.cmake (NEW file)
# Source: bgfx's own src/config.h renderer-selection mechanism (direct raw-file read,
# bkaradzic/bgfx master, lines 22-162) -- defining ANY ONE BGFX_CONFIG_RENDERER_* macro
# flips ALL undefined renderer macros to explicit 0 via config.h's own #else branch.
add_compile_definitions(BGFX_CONFIG_RENDERER_VULKAN=1)
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    add_compile_definitions(BGFX_CONFIG_RENDERER_OPENGL=21)  # min GL 2.1; auto-clamped if <21
endif()
```

### Pattern 2: ExternalProject_Add with a manual INSTALL_COMMAND for a dependency with no install() rules (SwiftShader)
**What:** SwiftShader's root `CMakeLists.txt` has zero `install()` calls (confirmed via direct grep of the raw file) — this matches the existing `STB` entry's pattern in `CommonTargets.cmake` (custom `INSTALL_COMMAND` doing manual file copies), not the `CMAKE_CACHE_ARGS`-with-`find_package()` pattern used for CMake-package-exporting deps like Vulkan-Loader/MNN/bgfx.
**When to use:** Any vendored dependency with no CMake package config of its own.
**Example:**
```cmake
# Source: google/swiftshader src/Vulkan/CMakeLists.txt (direct raw-file read, master HEAD
# a7c547b), adapted to this repo's existing STB-entry INSTALL_COMMAND pattern.
ExternalProject_Add(swiftshader
    PREFIX swiftshader
    SOURCE_DIR "${THIRDPARTY_DIR}/swiftshader"
    CMAKE_CACHE_ARGS
    -DSWIFTSHADER_BUILD_TESTS:BOOL=OFF
    -DSWIFTSHADER_BUILD_BENCHMARKS:BOOL=OFF
    -DSWIFTSHADER_BUILD_PVR:BOOL=FALSE
    -DBUILD_VULKAN_WRAPPER:BOOL=OFF
    ${_CMAKE_COMMON_CACHE_ARGS}
    BUILD_COMMAND ${CMAKE_COMMAND} --build <BINARY_DIR> --target vk_swiftshader --config $<CONFIG>
    INSTALL_COMMAND ${CMAKE_COMMAND} -E make_directory <INSTALL_DIR>/lib
    COMMAND ${CMAKE_COMMAND} -E copy
        "<BINARY_DIR>/${CMAKE_SYSTEM_NAME}/${CMAKE_SHARED_LIBRARY_PREFIX}vk_swiftshader${CMAKE_SHARED_LIBRARY_SUFFIX}"
        <INSTALL_DIR>/lib/
    COMMAND ${CMAKE_COMMAND} -E copy
        "<BINARY_DIR>/${CMAKE_SYSTEM_NAME}/vk_swiftshader_icd.json"
        <INSTALL_DIR>/lib/
)
```
*(Exact `<BINARY_DIR>` path components, e.g. the literal `${CMAKE_SYSTEM_NAME}` subfolder, should be spot-checked against a real configure output during Phase 1 execution — confirmed present in source via `configure_file()` destination in `src/Vulkan/CMakeLists.txt`, but the planner should verify the resolved path on the actual CI platform before relying on it in a script.)*

### Pattern 3: Smoke-test target consuming `bgfx::bgfx` (D-07)
**What:** A trivial executable proving CMake wiring end-to-end, per Success Criterion 4.
**When to use:** Exactly once, in Phase 1, kept permanently per D-07.
**Example:**
```cpp
// Source: pattern matches bgfx's own examples/*/main.cpp include convention (not copied
// verbatim from any single example -- this is the minimal call D-07 specifies).
#include <bgfx/bgfx.h>
#include <cstdio>

int main() {
    // Deliberately NOT calling bgfx::init() -- Success Criterion 4 explicitly excludes
    // headless context bring-up from this phase's scope. This only proves link+compile.
    std::printf("bgfx smoke test built against renderer type enum size: %d\n",
                static_cast<int>(bgfx::RendererType::Count));
    return 0;
}
```
```cmake
add_executable(bgfx_smoke_test smoke_test.cpp)
target_link_libraries(bgfx_smoke_test PRIVATE bgfx::bgfx)
```

### Anti-Patterns to Avoid
- **Calling `bgfx::getRendererName(bgfx::RendererType::Count)` or any variant requiring `bgfx::init()` to have run first:** the roadmap's own wording says "a single bgfx API call... compiles and links successfully" — pick a call (or even just a symbol reference, as in the example above) that does not require runtime initialization, since Phase 1 explicitly excludes headless context bring-up.
- **Recursively `git submodule update --init --recursive` on SwiftShader's own `.gitmodules`:** pulls `PowerVR_Examples`, `benchmark`, `googletest`, `llvm-project` — none needed when `SWIFTSHADER_BUILD_TESTS`/`BENCHMARKS`/`PVR`/`BUILD_VULKAN_WRAPPER` are OFF (see Pitfall 3).
- **Assuming `find_package(SwiftShader)` or similar works:** it does not — SwiftShader has zero `install()` rules; Phase 3/5 must reference the manually-copied `.so`/`.dll` + `.json` by file path, not by CMake package.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| bgfx's own CMake build | A custom `ExternalProject_Add` `BUILD_COMMAND` wrapping GENie/bam | `bgfx.cmake`'s existing, upstream-author-maintained CMake port | Already decided (D-01); this research confirms it also produces a clean `install(EXPORT)` package, removing the last reason to hand-roll anything further |
| Restricting bgfx's compiled-in renderer backends | Patching bgfx source, or a hand-written post-configure `sed` over generated build files | `BGFX_CMAKE_USER_SCRIPT` cache arg + `BGFX_CONFIG_RENDERER_*` preprocessor defines (documented mechanism, both bgfx.cmake's own and bgfx's own `config.h`) | Fully supported, zero source patches, exactly matches bgfx's own documented external-configuration convention |
| Vulkan loader resolution for bgfx | Any custom CMake logic trying to `target_link_libraries(bgfx PUBLIC Vulkan::Vulkan)` or similar | Nothing — bgfx never links a Vulkan loader at build time at all (runtime `dlopen` only) | Attempting to force a build-time Vulkan link into `bgfx::bgfx` fights the library's actual architecture and would be pure wasted effort |
| SwiftShader ICD packaging | A hand-rolled ICD JSON manifest generator | SwiftShader's own `configure_file()`-generated `vk_swiftshader_icd.json` (already emitted automatically as part of its build) | Already produced automatically — copying it (Pattern 2) is sufficient, no need to reverse-engineer the ICD manifest schema |

**Key insight:** Both dependencies already ship exactly the CMake integration surface this phase needs (a real `install(EXPORT)` package for bgfx, an automatic ICD-manifest-generation step for SwiftShader) — the entire phase is wiring existing upstream mechanisms into this repo's existing superbuild convention, not building new abstraction.

## Common Pitfalls

### Pitfall 1: Assuming `add_subdirectory()` is required for bgfx.cmake because that's its "documented" usage
**What goes wrong:** bgfx.cmake's README emphasizes `add_subdirectory()` as the simplest path, and D-02 in `01-CONTEXT.md` explicitly left this open as a research question, implying it might have been necessary. Defaulting to `add_subdirectory()` would break this repo's 100%-`ExternalProject_Add` convention (confirmed via `grep -rn "add_subdirectory" thirdparty/build/` returning zero hits outside `SGProcessingManager/src` and the project's own `PROJECT_ROOT}/src` — every single vendored `thirdparty/` dependency uses `ExternalProject_Add`, no exceptions currently exist).
**Why it happens:** The README genuinely does present `add_subdirectory()` as the primary/first-listed option, and doesn't mention `BGFX_CMAKE_USER_SCRIPT` as an alternative to reaching into the target for custom compile definitions.
**How to avoid:** Use `ExternalProject_Add` + `find_package(bgfx CONFIG)`, and use `BGFX_CMAKE_USER_SCRIPT` (Pattern 1) for the renderer-restriction defines instead of direct `target_compile_definitions()` on a live in-tree target.
**Warning signs:** A plan that introduces the first-ever `add_subdirectory()` call for a `thirdparty/` dependency in this repo without an explicit justification for the exception.

### Pitfall 2: Defining only `BGFX_CONFIG_RENDERER_OPENGL` (or defining it before Vulkan) and expecting D3D/Metal to still get disabled
**What goes wrong:** bgfx's `config.h` opt-in mechanism is triggered by defining **any** `BGFX_CONFIG_RENDERER_*` macro externally — but each platform's defaults are otherwise independent per-macro `#ifndef` blocks. If a build script defines `BGFX_CONFIG_RENDERER_OPENGL=21` on Linux but never defines `BGFX_CONFIG_RENDERER_VULKAN` at all on Windows/macOS (because "Linux is where OpenGL matters"), the *Windows/macOS* compiles never trigger the opt-in block and silently keep their full default set (D3D11+D3D12+Vulkan all compiled in) — directly violating D-03.
**Why it happens:** The opt-in trigger is global to the whole `#if !defined(...)` chain (any one macro trips it for ALL of them), but it's easy to reason about the two defines (`VULKAN`, `OPENGL`) as independent, platform-scoped toggles when they are not.
**How to avoid:** Define `BGFX_CONFIG_RENDERER_VULKAN=1` **unconditionally, on every platform**, in `bgfx-user-config.cmake` — this alone triggers the opt-in `#else` branch and zeroes every other backend automatically. Only *additionally* and *conditionally* define `BGFX_CONFIG_RENDERER_OPENGL=21` on Linux.
**Warning signs:** A Windows or macOS build of the smoke-test target that still links D3D11/Metal symbols, or a build log showing `d3d11`/`Metal.framework` references when only Vulkan+GL were intended.

### Pitfall 3: Recursively initializing all of SwiftShader's own git submodules
**What goes wrong:** `git submodule update --init --recursive` on the vendored `swiftshader` submodule will pull `third_party/PowerVR_Examples` (a full PowerVR SDK mirror), `third_party/benchmark`, `third_party/googletest`, and `third_party/llvm-project` (the full upstream LLVM monorepo) — none of which are needed to build `vk_swiftshader` when `SWIFTSHADER_BUILD_TESTS`/`BENCHMARKS`/`PVR`/`BUILD_VULKAN_WRAPPER` are all OFF, per D-04's explicit "only the ICD target" scope. This can add gigabytes of unnecessary clone size/time to every fresh checkout and CI run.
**Why it happens:** "Recursively initialize submodules" is the reflexive default action for any new nested-submodule dependency, and SwiftShader's own `.gitmodules` doesn't distinguish "required for vk_swiftshader" from "required for tests/benchmarks/samples" at the submodule level.
**How to avoid:** Initialize the `swiftshader` submodule itself, but only selectively init the submodules actually needed (verify at implementation time which of `third_party/cppdap`/`json`/`libbacktrace` are unconditionally required by `vk_swiftshader`'s own dependency chain — `third_party/llvm-16.0`, needed by the default `REACTOR_BACKEND=LLVM`, is **not** a git submodule at all per SwiftShader's own `.gitmodules`, and ships as ordinary committed repo content, so it comes along automatically with a plain, non-recursive submodule checkout).
**Warning signs:** A `git submodule update --init --recursive` step in CI that takes disproportionately long, or a `.gitmodules`-driven clone pulling PowerVR SDK / full LLVM sources when only a CPU Vulkan ICD is needed.

### Pitfall 4: Treating SwiftShader's `configure_file()`-generated ICD manifest as a build-time (not configure-time) artifact
**What goes wrong:** `vk_swiftshader_icd.json` is generated via `configure_file()`, which CMake executes at **configure** time, not as part of `cmake --build`. If a build script assumes the manifest only exists after building `vk_swiftshader` (e.g. checks for it only after the `BUILD_COMMAND` step), it will actually already be present right after the CMake configure step — but if `INSTALL_COMMAND` runs `copy` before the manifest was ever generated (e.g. a fresh, never-configured tree), it will fail to find the file.
**Why it happens:** Most CMake-generated artifacts are build-time outputs; `configure_file()` is a comparatively less common configure-time mechanism, easy to mentally lump in with "stuff that appears after building."
**How to avoid:** In the `ExternalProject_Add` block, both the manifest and the shared library will exist by the time `INSTALL_COMMAND` runs (since `ExternalProject_Add`'s Configure step always precedes Build, which precedes Install) — this is a non-issue for the recommended wiring in Pattern 2, but worth knowing if the planner ever needs to reference the manifest path *before* a full build (e.g. in a dry-run/validation script).
**Warning signs:** A script that checks for `vk_swiftshader_icd.json` only inside a post-build hook and never accounts for it existing earlier in the pipeline.

### Pitfall 5: Confusing bgfx's own `shaderc` tool build (Phase 4 concern) with this phase's scope
**What goes wrong:** `BGFX_BUILD_TOOLS` (bgfx.cmake's own option) defaults `ON` and would build `shaderc`/`texturec`/`geometryc`/etc. alongside the `bgfx` library target. This isn't wrong to leave on, but a planner unfamiliar with the roadmap split might assume Phase 1 needs to configure shader-compilation tooling now.
**Why it happens:** bgfx.cmake bundles library + tools in one CMake project by default, and shader compilation (`RENDER-01`, Phase 4) is a closely related but explicitly later concern (`FINAL-BACKEND-DECISION.md`'s "Consequence for schema design" section).
**How to avoid:** Recommend explicitly setting `BGFX_BUILD_TOOLS:BOOL=OFF` in Phase 1 (matching D-03's build-footprint-minimization intent) and letting Phase 4 turn it back `ON` when `shaderc` is actually needed — or, if the planner prefers to build it once now to avoid a second full reconfigure later, explicitly note that decision as an intentional scope extension beyond CTX-04, not an oversight.
**Warning signs:** Phase 1 verification steps that reference `shaderc`/`texturec` binaries, which have no role in this phase's success criteria (only `bgfx::getRendererName()` compiling/linking, and `vk_swiftshader` + its manifest existing).

## Code Examples

See "Architecture Patterns" above (Patterns 1–3) for the complete, primary-source-grounded `CommonTargets.cmake` blocks, the new `bgfx-user-config.cmake` file, and the smoke-test target — these are the load-bearing code examples for this phase and are not duplicated here to avoid drift between two copies.

## State of the Art

| Old Approach (superseded within this workstream, not industry-wide) | Current Approach | When Changed | Impact |
|--------------------------------------------------------------------|------------------|---------------|--------|
| Hand-rolled Vulkan-only `RenderProcessor` (vk-bootstrap + VMA + Google's `shaderc`) | bgfx + explicit 3-tier fallback, vendored via `bgfx.cmake` | 2026-07-28, `FINAL-BACKEND-DECISION.md` | Already fully superseded before this phase began; not re-litigated here |
| Assumption that `bgfx.cmake` might require `add_subdirectory()` (D-02, open as of `01-CONTEXT.md`) | `ExternalProject_Add` + `find_package(bgfx CONFIG)`, using `BGFX_CMAKE_USER_SCRIPT` for renderer restriction | This research, 2026-07-28/29 | Removes the only open question that threatened to force an exception to this repo's superbuild convention |

**Deprecated/outdated:**
- `widberg/bgfx.cmake` (the original fork location) — superseded by `bkaradzic/bgfx.cmake` per D-01's own repo correction; do not vendor the old URL.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The exact `<BINARY_DIR>` subpath components in SwiftShader's `INSTALL_COMMAND` (e.g. the literal `${CMAKE_SYSTEM_NAME}` folder name matching CMake's own `CMAKE_SYSTEM_NAME` value on every target platform, including cross-compilation edge cases) — confirmed present in source but not spot-verified against a real configured build tree on Windows/macOS/Linux in this research session. | Architecture Patterns, Pattern 2 | Low — if the path differs slightly (e.g. casing), the `INSTALL_COMMAND` copy step fails loudly and immediately during first build, easy to fix; does not silently produce a broken artifact |
| A2 | Which of SwiftShader's remaining non-test/benchmark/PVR submodules (`third_party/cppdap`, `third_party/json`, `third_party/libbacktrace`) are unconditionally required to build `vk_swiftshader` itself (vs. only needed for tooling gated behind other options) was not exhaustively traced line-by-line for every conditional in the ~1000-line root `CMakeLists.txt` — the `glslang`/`googletest`/`benchmark`/`PowerVR_Examples`/`llvm-project` exclusions ARE confirmed gated behind options this phase turns off, but a full audit of every remaining `add_subdirectory()` call's necessity was not performed. | Pitfall 3 | Medium — worst case, the planner initializes one or two more submodules than strictly necessary; does not block the build, only adds modest extra clone size |
| A3 | Whether the SGProcessingManager side needs `Vulkan-Headers`/`Vulkan-Loader` to be built and its `VULKAN_SDK` env var set *before* bgfx's own configure step, given bgfx compiles against its own bundled `3rdparty/khronos` headers and never calls `find_package(Vulkan)` — this research concludes bgfx has NO ordering dependency on the project's Vulkan-Headers/Loader `ExternalProject_Add` targets at build time, only a *runtime* one (Phase 3). This has not been tested against an actual configure/build run of this repo. | Summary, Architecture Patterns | Medium — if wrong, the planner may need to add `DEPENDS Vulkan-Loader` to the `bgfx` `ExternalProject_Add` block defensively; low cost to add preemptively if uncertain |

## Open Questions

1. **Exact runtime library-path wiring for the Vulkan loader (and later, SwiftShader ICD) relative to the smoke-test executable**
   - What we know: bgfx dynamically loads `libvulkan.so`/`vulkan-1.dll` at runtime via `dlopen`, not build-time link — confirmed via direct source read.
   - What's unclear: Since the smoke-test target (D-07) deliberately does NOT call `bgfx::init()` (per this research's own Pattern 3 recommendation, matching Success Criterion 4's "no headless context bring-up" scope), this phase never actually exercises the runtime `dlopen` path at all — so this remains genuinely untested until Phase 3.
   - Recommendation: Explicitly note in the plan/verification that "compiles and links" is the full bar for Phase 1's smoke test — runtime Vulkan loader discovery is out of scope here and belongs to Phase 3's own verification.

2. **Whether `BGFX_BUILD_TOOLS=OFF` in Phase 1 creates rework for Phase 4**
   - What we know: Turning tools off now minimizes Phase 1 build footprint (Pitfall 5); Phase 4 needs `shaderc` for `RENDER-01`.
   - What's unclear: Whether Phase 4's plan will need to re-configure/rebuild the entire `bgfx` `ExternalProject_Add` target with `BGFX_BUILD_TOOLS=ON`, and whether that reconfigure is cheap (likely yes, since `ExternalProject_Add` steps are individually re-triggerable) or requires a full rebuild.
   - Recommendation: Leave as planner's discretion (already flagged as Pitfall 5) — either choice is defensible; document whichever is chosen so Phase 4's own research/planning isn't surprised.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| CMake | Both `ExternalProject_Add` blocks | Not probed in this research session (no shell access to the actual build machine was exercised for this check) [ASSUMED] | Repo requires ≥3.22 (`thirdparty/build/*/CMakeLists.txt`); bgfx.cmake requires ≥3.20; SwiftShader requires ≥**3.22.1** (one patch level above this repo's own floor — worth confirming CI images satisfy this exact patch level, not just 3.22.0) | If CI pins exactly 3.22.0, bump the minimum in CI config before this phase's build can succeed |
| Git (with submodule support) | Vendoring both new dependencies | Assumed present — every other `thirdparty/` dependency already requires this [ASSUMED] | — | — |
| C++20-capable compiler | bgfx.cmake (`CMAKE_CXX_STANDARD 20` set in its own root `CMakeLists.txt`) | Assumed present — this repo's own `CommonBuildParameters.cmake` already sets `CMAKE_CXX_STANDARD 20` project-wide | — | — |
| Vulkan SDK / Vulkan-Headers+Loader (already vendored) | bgfx's Vulkan backend — but only at **runtime**, not build time (see Summary) | Already vendored in this repo (`thirdparty/Vulkan-Headers`, `thirdparty/Vulkan-Loader`) | Existing pin, unchanged by this phase | N/A — no new requirement introduced |

**Missing dependencies with no fallback:** none identified — both new dependencies are self-contained CMake projects with no additional system-level packages beyond what this repo's toolchain already requires (a C++20 compiler and CMake ≥3.22, both already project-wide requirements).
**Missing dependencies with fallback:** none identified.

## Security Domain

`security_enforcement` is enabled project-wide (`security_asvs_level: 1`), but this phase is pure build-system plumbing with zero application/runtime logic (no auth, no input parsing, no network handling) — most ASVS categories are structurally not applicable to a submodule-vendoring phase.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | N/A — no auth surface in this phase |
| V3 Session Management | No | N/A |
| V4 Access Control | No | N/A |
| V5 Input Validation | No | N/A — no data parsing introduced |
| V6 Cryptography | No | N/A |
| V14 Configuration / Supply Chain | Yes | Commit-SHA pinning (D-05) of both new dependencies, rather than tracking a floating branch — this IS this phase's actual security-relevant control, functioning as the ASVS-equivalent of dependency-pinning/supply-chain-integrity practice for build-time third-party code |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Supply-chain compromise via an unpinned/floating third-party git submodule silently picking up a malicious upstream commit on next `git submodule update` | Tampering | Commit-SHA pinning (D-05, already locked) — never track `master`/a branch directly for either new submodule |
| A malicious or buggy `postinstall`-equivalent (CMake `INSTALL_COMMAND`/`configure_file()` side effects) executing during the superbuild | Tampering / Elevation of Privilege | Both `INSTALL_COMMAND`s introduced by this phase are simple, auditable `${CMAKE_COMMAND} -E copy`/`make_directory` calls with no shell-injection surface (no unescaped variable interpolation into a shell string) — reviewed directly in Pattern 2 above |

## Sources

### Primary (HIGH confidence — direct raw-source reads and GitHub REST/contents API calls)
- `https://api.github.com/repos/bkaradzic/bgfx.cmake/commits/master` — exact HEAD SHA + date
- `https://raw.githubusercontent.com/bkaradzic/bgfx.cmake/master/README.md` — integration guide, submodule requirements
- `https://raw.githubusercontent.com/bkaradzic/bgfx.cmake/master/CMakeLists.txt` — root project options, `BGFX_CMAKE_USER_SCRIPT`, `install(EXPORT)` block
- `https://raw.githubusercontent.com/bkaradzic/bgfx.cmake/master/.gitmodules` — confirms exactly 3 nested submodules (bgfx, bx, bimg)
- `https://raw.githubusercontent.com/bkaradzic/bgfx.cmake/master/cmake/bgfx/CMakeLists.txt` and `.../cmake/bgfx/bgfx.cmake` — bgfx target definition, `3rdparty/khronos` include path, `target_link_libraries(bgfx PRIVATE bx bimg)` (no Vulkan link)
- `https://raw.githubusercontent.com/bkaradzic/bgfx.cmake/master/cmake/Config.cmake.in` — confirms exported target name `bgfx::bgfx`
- `https://api.github.com/repos/bkaradzic/bgfx.cmake/contents/{bgfx,bx,bimg}?ref=master` — exact pinned submodule SHAs
- `https://raw.githubusercontent.com/bkaradzic/bgfx/master/src/config.h` — full renderer-selection macro logic (direct grep + read of lines 1-180)
- `https://raw.githubusercontent.com/bkaradzic/bgfx/master/src/renderer_vk.cpp` — confirmed runtime `bx::dlopen`/`bx::dlsym` loading of the Vulkan loader, no build-time link
- `https://api.github.com/repos/google/swiftshader/commits/master` — exact HEAD SHA + date
- `https://raw.githubusercontent.com/google/swiftshader/master/CMakeLists.txt` — full root CMakeLists (993 lines), options, `REACTOR_BACKEND`, `add_subdirectory` graph
- `https://raw.githubusercontent.com/google/swiftshader/master/src/Vulkan/CMakeLists.txt` — `vk_swiftshader` target definition, ICD manifest `configure_file()` generation
- `https://raw.githubusercontent.com/google/swiftshader/master/.gitmodules` — confirms `third_party/llvm-16.0` is NOT a submodule (ships as repo content)
- This workstream's own `BGFX-HEADLESS-VERIFICATION.md` and `FINAL-BACKEND-DECISION.md` — canonical prior research, read in full per the `<files_to_read>` instruction

### Secondary (MEDIUM confidence)
- `WebSearch: "google swiftshader CMakeLists.txt vk_swiftshader target build ICD json manifest SWIFTSHADER_BUILD_VULKAN"` — used only as an initial pointer to the primary sources actually cited above; superseded by the direct raw-file reads

### Tertiary (LOW confidence)
- None used as load-bearing evidence in this document.

## Metadata

**Confidence breakdown:**
- Standard stack (exact commit SHAs): HIGH — verified live against GitHub REST API at research time
- Architecture (ExternalProject_Add viability, BGFX_CMAKE_USER_SCRIPT mechanism, SwiftShader install-less build): HIGH — every claim traced to a specific, quoted line range in a directly-fetched raw source file
- Pitfalls: HIGH for Pitfalls 1, 2, 4, 5 (directly sourced); MEDIUM for Pitfall 3 (submodule-minimization claim is directionally correct and sourced from `.gitmodules`, but not exhaustively traced against every remaining `add_subdirectory()` call in SwiftShader's ~1000-line root CMakeLists — see Assumption A2)

**Research date:** 2026-07-28 / 2026-07-29
**Valid until:** ~14 days (both dependencies are pinned to specific, unreleased, actively-developed `master` HEAD commits with no tagged releases — re-verify the pinned SHAs still resolve and still build cleanly if Phase 1 execution is delayed more than ~2 weeks past this research date, since neither upstream provides a stable-tag alternative to re-anchor against)
