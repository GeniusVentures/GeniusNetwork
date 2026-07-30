---
phase: 02-schema-extension-shader-spir-v-validation-pipeline
plan: 02
subsystem: infra
tags: [cmake, git-submodule, shaderc, spirv-tools, spirv-headers, vulkan, vendoring, external-project-add]

# Dependency graph
requires:
  - phase: 02-schema-extension-shader-spir-v-validation-pipeline (plan 01)
    provides: Extended render-pass schema and quicktype headers (render_shader/render_target/vertex_layout/etc.) that plan 02-03's ShaderCompiler will consume
provides:
  - shaderc v2024.3 vendored as a pinned git submodule at thirdparty/shaderc
  - SPIRV-Tools and SPIRV-Headers vendored as separately-linkable, pinned git submodules at thirdparty/SPIRV-Tools and thirdparty/SPIRV-Headers (pinned to the exact commits shaderc's own v2024.3 DEPS file references)
  - shaderc::shaderc and SPIRV-Tools::SPIRV-Tools CMake IMPORTED targets in thirdparty/build/CommonTargets.cmake, both build-verified against a real local configure+build+install
affects: [02-03-shader-compiler-spirv-validation, 02-04-processingmanager-wiring]

# Tech tracking
tech-stack:
  added: [shaderc v2024.3, SPIRV-Tools (KhronosGroup, commit 01c8438e), SPIRV-Headers (KhronosGroup, commit 2a9b6f95)]
  patterns:
    - "SPIRV-Tools resolved via find_package(SPIRV-Tools CONFIG) + an ALIAS to a project-controlled namespaced target name (SPIRV-Tools::SPIRV-Tools), since the upstream config exports only the bare SPIRV-Tools-static/-shared targets, not a namespaced one -- with a hand-rolled IMPORTED fallback if the installed config is ever unavailable"
    - "shaderc has no installed CMake config at all -- hand-written IMPORTED target against the confirmed-real libshaderc_combined.a, matching this project's existing hardcoded .a-extension IMPORTED_LOCATION convention (see rocksdb/wallet-core/snappy blocks in the same file)"

key-files:
  created: []
  modified:
    - thirdparty/.gitmodules
    - thirdparty/build/CommonTargets.cmake
    - thirdparty (submodule pointer, GeniusNetwork superproject)

key-decisions:
  - "Corrected the SPIRV-Tools/SPIRV-Headers pinned commits from what 02-RESEARCH.md/02-PLAN.md cited (a665e21f / 29981f65, read from shaderc's *main*-branch DEPS file at research time) to the commits actually referenced by shaderc's own DEPS file AT THE v2024.3 TAG we vendor (01c8438e / 2a9b6f95) -- confirmed by reading the checked-out v2024.3 tag's own DEPS file directly. This is the exact re-confirmation Task 1's checkpoint asked for (\"re-confirm this commit is still what shaderc's DEPS references... since upstream may have moved\") and satisfies Pitfall 4's actual intent: matching the SPIR-V dialect shaderc v2024.3 itself emits, not main's current (newer, v2024.4+-track) dialect."
  - "shaderc's own third_party/{glslang,spirv-tools,spirv-headers,...} dependencies are NOT git submodules -- they are gclient-style DEPS-file dependencies fetched via shaderc's own ./utils/git-sync-deps Python script, and are gitignored inside shaderc's own repo. `git submodule update --init --recursive` (as the plan's Task 2 action text assumed) is a no-op for shaderc since it has no .gitmodules at all. Ran python utils/git-sync-deps instead to achieve the same practical outcome (shaderc's own build tree populated for its internal glslang+SPIRV-Tools+SPIRV-Headers copy)."
  - "SPIRV-Tools DOES install a real CMake package config by default (ENABLE_SPIRV_TOOLS_INSTALL defaults ON) -- contrary to the plan's flagged uncertainty -- but the exported target names are the bare, non-namespaced SPIRV-Tools-static/SPIRV-Tools-shared, since the upstream SPIRV-Tools ALIAS target is build-tree-only and CMake never exports ALIAS targets via install(EXPORT). Used find_package(SPIRV-Tools CONFIG) + add_library(SPIRV-Tools::SPIRV-Tools ALIAS SPIRV-Tools-static) to get the project-controlled namespaced name the plan's must_haves require, with a hand-rolled IMPORTED fallback retained for robustness."
  - "Used the environment's available MinGW GCC 13.2.0 + Ninja toolchain (Strawberry Perl's bundled gcc) for the real local build+install verification spike, rather than MSVC (cl.exe not on PATH without sourcing a VS dev-prompt environment this session). This matches the existing hardcoded .a static-library-extension convention already present elsewhere in this exact CommonTargets.cmake file (snappy/rocksdb/wallet-core blocks), so the IMPORTED_LOCATION paths written are not a deviation from established practice."

patterns-established:
  - "Non-namespaced upstream CMake config + project-controlled ALIAS: when an upstream package installs a real find_package-able CONFIG but exports bare (non ::-namespaced) targets, resolve via find_package(<Pkg> CONFIG) then add_library(<Pkg>::<Pkg> ALIAS <bare-target>) rather than assuming the namespaced target already exists or hand-rolling an IMPORTED target unnecessarily."

requirements-completed: [SHADER-01, SHADER-02]

coverage:
  - id: D1
    description: "A human (the orchestrator, per this project's yolo/auto_advance config) confirmed shaderc/SPIRV-Tools/SPIRV-Headers identity, license, and legitimacy via live GitHub lookups before any submodule was added"
    requirement: "SHADER-01"
    verification:
      - kind: other
        ref: "Orchestrator-performed live verification recorded in the executor's dispatch prompt: google/shaderc (official Google org, Apache-2.0), KhronosGroup/SPIRV-Tools (official Khronos org, Apache-2.0), KhronosGroup/SPIRV-Headers (official Khronos org, permissive MIT-like) -- all confirmed non-fork/non-mirror/non-typosquat"
        status: pass
    human_judgment: false
  - id: D2
    description: "shaderc v2024.3, SPIRV-Tools, and SPIRV-Headers are vendored as pinned git submodules under thirdparty/, matching the existing per-library ExternalProject_Add vendoring convention (same one that vendored vk-bootstrap in Phase 1)"
    requirement: "SHADER-01"
    verification:
      - kind: other
        ref: "cd thirdparty && git submodule status -- shaderc SPIRV-Tools SPIRV-Headers -> all three clean-checked-out (no leading '-' or '+'), shaderc at ff84893 (v2024.3), SPIRV-Tools at 01c8438e, SPIRV-Headers at 2a9b6f95 (both re-confirmed against shaderc v2024.3's own DEPS file, not main's)"
        status: pass
    human_judgment: false
  - id: D3
    description: "A CMake target named shaderc::shaderc and a CMake target named SPIRV-Tools::SPIRV-Tools both configure, build, and link successfully, with zero VkInstance/device dependency"
    requirement: "SHADER-01, SHADER-02"
    verification:
      - kind: other
        ref: "Real local configure+build+install of the SPIRV-Headers/SPIRV-Tools/shaderc ExternalProject_Add targets (MinGW GCC 13.2.0 + Ninja) plus a standalone consumer executable linking both shaderc::shaderc and SPIRV-Tools::SPIRV-Tools: compiled a trivial GLSL fragment shader to 100 words of SPIR-V via shaderc::Compiler::CompileGlslToSpv, then validated it via spvtools::SpirvTools::Validate() -- printed 'SPIRV-Tools validation result: VALID', exit code 0"
        status: pass
    human_judgment: false

duration: ~100min
completed: 2026-07-30
status: complete
---

# Phase 2 Plan 2: Vendor shaderc/SPIRV-Tools/SPIRV-Headers + CMake Targets Summary

**Vendored shaderc v2024.3 and a separately-linkable SPIRV-Tools/SPIRV-Headers as pinned git submodules, then added `shaderc::shaderc`/`SPIRV-Tools::SPIRV-Tools` CMake IMPORTED targets to `thirdparty/build/CommonTargets.cmake` — both build-verified end-to-end (GLSL compiled to SPIR-V via shaderc, then validated via SPIRV-Tools) against a real local configure+build+install, not left as illustrative guesses.**

## Performance

- **Duration:** ~100 min
- **Tasks:** 3 (Task 1 checkpoint pre-cleared by orchestrator; Tasks 2-3 executed)
- **Files modified:** 3 (thirdparty/.gitmodules, thirdparty/build/CommonTargets.cmake, thirdparty submodule pointer in the GeniusNetwork superproject) + 3 new submodule gitlinks (shaderc, SPIRV-Tools, SPIRV-Headers)

## Accomplishments

- **Task 1 (checkpoint, pre-cleared):** The orchestrator (running this project's configured autonomous "yolo" mode) performed live GitHub identity/license/legitimacy verification of `google/shaderc`, `KhronosGroup/SPIRV-Tools`, and `KhronosGroup/SPIRV-Headers` before dispatch — all three confirmed as official, non-fork/non-mirror/non-typosquat repos with permissive licenses. Recorded as satisfied per the executor's dispatch instructions; no further human input sought for Task 1.
- **Task 2:** Vendored `shaderc` (pinned `v2024.3`, commit `ff84893`), `SPIRV-Tools` (pinned `01c8438e`), and `SPIRV-Headers` (pinned `2a9b6f95`) as three new `[submodule ...]` entries in `thirdparty/.gitmodules`, matching the existing `path`/`url`-only shape used by every other submodule in the file.
- **Task 3:** Added `ExternalProject_Add` blocks for `SPIRV-Headers`, `SPIRV-Tools` (`DEPENDS SPIRV-Headers`), and `shaderc` to `thirdparty/build/CommonTargets.cmake`'s existing `if(NOT ANDROID)` block, immediately after the vk-bootstrap block. Added the `shaderc::shaderc` and `SPIRV-Tools::SPIRV-Tools` IMPORTED targets, both confirmed against a real local build+install (see Deviations for the two upstream-CMake-integration surprises this uncovered).
- Ran a genuine end-to-end functional proof beyond what Task 3 strictly required: a standalone executable linking both new targets compiled a trivial GLSL fragment shader to SPIR-V via `shaderc::Compiler::CompileGlslToSpv` and validated the result via `spvtools::SpirvTools::Validate()` — both succeeded (100 words of SPIR-V, `VALID`).

## Task Commits

Each task was committed atomically in `thirdparty`'s own repo, then the pointer was bumped in the GeniusNetwork superproject:

1. **Task 1: Confirm shaderc/SPIRV-Tools/SPIRV-Headers legitimacy before vendoring** — checkpoint pre-cleared by the orchestrator prior to dispatch (see `<checkpoint_pre_cleared>` reasoning in the executor's dispatch prompt); no commit (no file changes, per the task's own definition).
2. **Task 2: Vendor shaderc, SPIRV-Tools, and SPIRV-Headers as pinned git submodules** — `d1a47b3` (thirdparty repo, feat)
3. **Task 3: Add CMake vendoring targets for shaderc and SPIRV-Tools** — `3268248` (thirdparty repo, feat)

**Submodule pointer bump:** `6dc59e1` (GeniusNetwork superproject, chore: bump thirdparty pointer)

_Note: No TDD tasks in this plan — both executed tasks are vendoring/CMake-integration work, verified via a real local build+install spike rather than unit tests._

## Files Created/Modified

- `thirdparty/.gitmodules` — three new `[submodule "..."]` entries (`shaderc`, `SPIRV-Headers`, `SPIRV-Tools`), `path`/`url` only, matching the existing file's shape exactly
- `thirdparty/shaderc` (new submodule, gitlink) — pinned at `v2024.3` (`ff84893`)
- `thirdparty/SPIRV-Tools` (new submodule, gitlink) — pinned at `01c8438e`
- `thirdparty/SPIRV-Headers` (new submodule, gitlink) — pinned at `2a9b6f95`
- `thirdparty/build/CommonTargets.cmake` — adds `ExternalProject_Add(SPIRV-Headers ...)`, `ExternalProject_Add(SPIRV-Tools ... DEPENDS SPIRV-Headers)`, `ExternalProject_Add(shaderc ...)`, plus the `SPIRV-Tools::SPIRV-Tools` (find_package-CONFIG-then-ALIAS, with hand-rolled IMPORTED fallback) and `shaderc::shaderc` (unconditional hand-rolled IMPORTED, no upstream config exists) target definitions
- `thirdparty` (submodule pointer bump in the GeniusNetwork superproject) — so the top-level checkout actually references the two new `thirdparty`-repo commits above

## Confirmed Installed Artifact Paths (for plan 02-03)

Recorded here per this plan's `<output>` instruction, so plan 02-03 does not need to re-discover them. All paths are relative to `${CMAKE_CURRENT_BINARY_DIR}` (the same convention this file already uses for `vk-bootstrap`/`Vulkan-Loader`), confirmed via a real local `ExternalProject_Add` configure+build+install (MinGW GCC 13.2.0 + Ninja, this environment's available toolchain):

| Target | Library | Include dir |
|--------|---------|-------------|
| `shaderc::shaderc` | `${CMAKE_CURRENT_BINARY_DIR}/shaderc/lib/libshaderc_combined.a` | `${CMAKE_CURRENT_BINARY_DIR}/shaderc/include` (headers: `shaderc/shaderc.h`, `shaderc/shaderc.hpp`) |
| `SPIRV-Tools::SPIRV-Tools` | `${CMAKE_CURRENT_BINARY_DIR}/SPIRV-Tools/lib/libSPIRV-Tools.a` (via the aliased `SPIRV-Tools-static` target) | `${CMAKE_CURRENT_BINARY_DIR}/SPIRV-Tools/include` (headers: `spirv-tools/libspirv.hpp`, `spirv-tools/libspirv.h`) |

`SPIRV-Tools` also installs a real CMake package config at `${CMAKE_CURRENT_BINARY_DIR}/SPIRV-Tools/lib/cmake/SPIRV-Tools/SPIRV-ToolsConfig.cmake`, exporting bare `SPIRV-Tools-static`/`SPIRV-Tools-shared` targets (not namespaced) — this is what `CommonTargets.cmake`'s new block resolves via `find_package(... CONFIG QUIET ...)` before aliasing to the project-controlled `SPIRV-Tools::SPIRV-Tools` name. `shaderc` installs no CMake config at all (confirmed, matching Pitfall 3).

## Decisions Made

See frontmatter `key-decisions` for full detail. Summary:
- Corrected SPIRV-Tools/SPIRV-Headers pins to shaderc v2024.3's own DEPS-file-referenced commits (`01c8438e`/`2a9b6f95`), not the plan/research's cited commits (`a665e21f`/`29981f65`), which were read from shaderc `main`'s DEPS at research time and belong to a later shaderc version than what this plan actually vendors.
- shaderc's nested third_party dependencies are gclient-style (DEPS + `git-sync-deps` script), not git submodules; used the correct upstream-provided mechanism instead of `git submodule update --init --recursive` (a no-op for this repo).
- SPIRV-Tools does install a CONFIG file by default, but under bare (non-namespaced) target names — resolved via find_package + ALIAS rather than assuming a namespaced target or unconditionally hand-rolling.
- Used MinGW GCC 13.2.0 + Ninja (available in this environment) for the real build-verification spike rather than MSVC, consistent with this file's own pre-existing hardcoded `.a`-extension convention.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `git submodule update --init --recursive` was a no-op for shaderc's own third_party dependencies**
- **Found during:** Task 2
- **Issue:** The plan's Task 2 action text assumed shaderc vendors glslang/SPIRV-Tools/SPIRV-Headers as nested git submodules. shaderc actually has no `.gitmodules` at all — its `third_party/` dependencies are Chromium/gclient-style, driven by a `DEPS` file and populated via `./utils/git-sync-deps` (a Python script that does plain `git clone`+`git checkout` per dependency, then leaves them gitignored inside shaderc's own repo).
- **Fix:** Ran `python utils/git-sync-deps` (Python 3.13.4, available as `python`/`py` in this environment; `python3` alone was not resolvable) inside `thirdparty/shaderc`, achieving the same practical outcome the plan's Task 2 acceptance criteria required (`thirdparty/shaderc/third_party/` populated with `glslang`/`spirv-tools`/`spirv-headers`, confirming shaderc's own build can proceed).
- **Files modified:** None committed — these directories are gitignored inside shaderc's own repo (confirmed via `git status --short --ignored`), exactly matching the intent of "purely for its own internal build."
- **Verification:** `ls thirdparty/shaderc/third_party/` shows `glslang`, `spirv-tools`, `spirv-headers` populated at the exact commits shaderc's own (checked-out v2024.3) `DEPS` file specifies; `git status --short --ignored` inside `thirdparty/shaderc` shows them as `!!` (ignored), not untracked — no embedded-repo commit risk.
- **Committed in:** N/A (correctly gitignored, nothing to commit for this fix)

**2. [Rule 1 - Bug] Corrected the SPIRV-Tools/SPIRV-Headers pinned commits**
- **Found during:** Task 2 (before running `git submodule add`)
- **Issue:** 02-RESEARCH.md and 02-PLAN.md's Task 1 cited `SPIRV-Tools@a665e21f`/`SPIRV-Headers@29981f65` as "the exact commits shaderc's own DEPS file references." Cross-checked against the actual checked-out `v2024.3` tag's own committed `DEPS` file (not shaderc `main`'s current `DEPS`, which is what the research had fetched) and found the v2024.3-pinned commits are actually `SPIRV-Tools@01c8438e`/`SPIRV-Headers@2a9b6f95` — shaderc's `main` branch had moved on to newer pins by research time (2026-07-30), post-dating the `v2024.3` tag being vendored.
- **Fix:** Pinned this project's top-level `SPIRV-Tools`/`SPIRV-Headers` submodules to the v2024.3-tag-correct commits (`01c8438e`/`2a9b6f95`) instead of the plan's cited ones, satisfying Pitfall 4's actual intent (matching shaderc's *own vendored version's* SPIR-V dialect, not `main`'s newer one) more precisely than a literal reading of the plan's cited hashes would have.
- **Files modified:** `thirdparty/.gitmodules`, `thirdparty/SPIRV-Tools` (gitlink), `thirdparty/SPIRV-Headers` (gitlink)
- **Verification:** Read `thirdparty/shaderc/DEPS` directly after checking out `v2024.3` — confirmed `spirv_tools_revision`/`spirv_headers_revision` match the commits actually vendored.
- **Committed in:** `d1a47b3` (Task 2 commit)

**3. [Rule 1 - Bug] `SPIRV-Tools::SPIRV-Tools` needed via find_package+ALIAS, not an unconditional hand-rolled IMPORTED target**
- **Found during:** Task 3 (real local build+install spike)
- **Issue:** The plan flagged genuine uncertainty over whether `find_package(SPIRV-Tools CONFIG)` would produce a usable `SPIRV-Tools::SPIRV-Tools` target. A real build+install confirmed SPIRV-Tools DOES install a CMake CONFIG by default, but the exported targets are bare `SPIRV-Tools-static`/`SPIRV-Tools-shared` (no `::` namespace) — the upstream `SPIRV-Tools` ALIAS target exists only in the original build tree and is never exported via `install(EXPORT)`.
- **Fix:** Implemented the plan's own two-tier contingency exactly as specified: `find_package(SPIRV-Tools CONFIG QUIET ...)` first, then `add_library(SPIRV-Tools::SPIRV-Tools ALIAS SPIRV-Tools-static)` (or `-shared`) if that resolves; hand-rolled `IMPORTED` target retained as the final fallback if the installed config is ever unavailable.
- **Files modified:** `thirdparty/build/CommonTargets.cmake`
- **Verification:** Standalone consumer executable resolved `SPIRV-Tools::SPIRV-Tools` via the `find_package`+`ALIAS` path (confirmed via `message(STATUS "RESOLVED: ... via find_package CONFIG")` during configure) and linked/ran successfully.
- **Committed in:** `3268248` (Task 3 commit)

---

**Total deviations:** 3 auto-fixed (1 blocking-mechanism correction, 1 correctness/pin fix, 1 build-verified design confirmation)
**Impact on plan:** All three were necessary to make the vendoring actually correct and buildable, not scope creep — each was already anticipated as a possibility by the plan's own flagged uncertainties (Task 1's "re-confirm... since upstream may have moved," Task 2's recursive-init assumption, Task 3's find_package-vs-hand-rolled contingency) and resolved by direct verification rather than assumption.

## Issues Encountered

- The first local build+install verification attempt (in a deeply-nested scratchpad temp directory) hit intermittent MinGW GCC `-MF` dependency-file write failures ("No such file or directory") for `SPIRV-Tools-reduce`'s longer-named source files — root-caused to the Windows `MAX_PATH` (260-character) limit, since the deep scratchpad path pushed several `.obj.d` paths past 260 characters. Not a shaderc/SPIRV-Tools code or vendoring-design issue. Resolved by re-running the same verification build in a short path (`C:/ssbuild`); the real `thirdparty/build/CommonTargets.cmake` build tree (nested under an existing project build dir, not this scratchpad) will not have this same depth problem, but this is worth flagging: consumers building this vendoring on Windows with very deep build-directory paths could hit the same `MAX_PATH` issue on `SPIRV-Tools-reduce` specifically (a component this project does not even need — only the core `SPIRV-Tools` validator library is consumed).
- `cl.exe`/MSVC was not available on `PATH` without sourcing a Visual Studio developer environment this session; used the environment's MinGW GCC 13.2.0 + Ninja instead for the real build-verification spike. This is consistent with this exact file's own pre-existing hardcoded `.a`-extension convention (see `rocksdb`/`wallet-core`/`snappy` `IMPORTED_LOCATION` entries elsewhere in `CommonTargets.cmake`), so no generator-specific assumption was introduced that isn't already present in the file.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- SHADER-01's vendoring half is satisfied: `shaderc::shaderc` is a real, buildable, build-verified CMake target
- SHADER-02's vendoring half is satisfied: `SPIRV-Tools::SPIRV-Tools` is a real, buildable, build-verified CMake target with a directly-callable `spvtools::SpirvTools::Validate()` — confirmed functionally correct via an actual GLSL-compile-then-validate round-trip
- Plan 02-03 (`ShaderCompiler`/SPIR-V validation component) can link directly against `shaderc::shaderc` and `SPIRV-Tools::SPIRV-Tools` with zero `VkInstance`/device dependency, using the confirmed installed artifact paths recorded above
- No blockers

---
*Phase: 02-schema-extension-shader-spir-v-validation-pipeline*
*Completed: 2026-07-30*

## Self-Check: PASSED
