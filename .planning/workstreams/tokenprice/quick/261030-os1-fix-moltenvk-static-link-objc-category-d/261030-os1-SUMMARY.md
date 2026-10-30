---
phase: quick-261030-os1
plan: 261030-os1
subsystem: build (CMake / MoltenVK static link)
tags: [moltenvk, vulkan, objc-categories, linker-flag, cmake, macos, conformance-tests]
requires:
  - "thirdparty moltenvk static install (libMoltenVK.a + headers) at _THIRDPARTY_BUILD_DIR/moltenvk"
  - "configured SuperGenius/build/OSX/Release tree with processing_conformance_* test targets"
provides:
  - "Vulkan::Vulkan INTERFACE_LINK_OPTIONS carries -Wl,-ObjC on Apple at all 5 consumer sites, so static-archive linking pulls MoltenVK's ObjC categories and MNN Vulkan inference initializes"
affects:
  - SuperGenius/build/OSX/CMakeLists.txt
  - SuperGenius/build/iOS/CMakeLists.txt
  - SuperGenius/SGProcessingManager/cmake/CommonBuildParameters.cmake
  - GeniusSDK/cmake/CommonBuildParameters.cmake
  - GeniusWallet/cmake/CommonBuildParameters.cmake
tech-stack:
  added: []
  patterns:
    - "set_property(TARGET Vulkan::Vulkan APPEND PROPERTY INTERFACE_LINK_OPTIONS \"-Wl,-ObjC\") — flag propagates to every consumer of the imported target, scoped Apple-only via Apple-only platform files or if(APPLE) guards"
key-files:
  created: []
  modified:
    - SuperGenius/build/OSX/CMakeLists.txt
    - SuperGenius/build/iOS/CMakeLists.txt
    - SuperGenius/SGProcessingManager/cmake/CommonBuildParameters.cmake
    - GeniusSDK/cmake/CommonBuildParameters.cmake
    - GeniusWallet/cmake/CommonBuildParameters.cmake
decisions:
  - "Used empirically validated driver form -Wl,-ObjC (not LINKER: prefix, not -force_load — the latter duplicates libshaderc_combined.a symbols)"
  - "Flag attached to the Vulkan::Vulkan imported target as INTERFACE_LINK_OPTIONS so every Apple consumer inherits it; non-Apple link lines byte-identical"
metrics:
  duration: ~5.4 min (2026-10-30T21:56:53Z → 22:02:16Z UTC)
  completed: 2026-10-30
  tests: 36/36 passed across 5 processing_conformance suites
actuals:
  tokens: ~600   # chars/4 over the realized diff: 29 inserted CMake lines across 5 files
  tasks: 2
  commits: 4     # nested-repo commits (SuperGenius, SGPM, GeniusSDK, GeniusWallet); parent repo: 0 by design
status: complete
---

# Quick Task 261030-os1: Fix MoltenVK static-link ObjC category drop Summary

**One-liner:** Appended `set_property(TARGET Vulkan::Vulkan APPEND PROPERTY INTERFACE_LINK_OPTIONS "-Wl,-ObjC")` at all 5 Vulkan consumer CMake sites (Apple-scoped), restoring MoltenVK's ObjC categories under static-archive linking — processing_conformance went from `doesNotRecognizeSelector: setBorderColorMVK:` crashes to **36/36 PASS**.

## What Was Done

- **Task 1** — Inserted the 3-line comment + one `set_property` line at 5 exact sites:
  1. `SuperGenius/build/OSX/CMakeLists.txt` — after the final `include(../CommonBuildParameters.cmake)`; no guard (Apple-only file)
  2. `SuperGenius/build/iOS/CMakeLists.txt` — same pattern; no guard (iOS-only file)
  3. `SuperGenius/SGProcessingManager/cmake/CommonBuildParameters.cmake` — inside `if(APPLE)` → `if(NOT TARGET Vulkan::Vulkan)`, after the AppKit/UIKit framework `target_link_libraries`, before the block's `endif()` (SGPM standalone builds only; as a SuperGenius subdirectory SuperGenius's own site provides the flag)
  4. `GeniusSDK/cmake/CommonBuildParameters.cmake` — `if(APPLE)`-guarded, directly after the `set_target_properties(Vulkan::Vulkan ... INTERFACE_INCLUDE_DIRECTORIES ...)` block
  5. `GeniusWallet/cmake/CommonBuildParameters.cmake` — `if(APPLE)`-guarded, directly after the `endif()` closing the `if(NOT TARGET Vulkan::Vulkan)` fallback block
- One atomic commit per nested repo, on each repo's current branch; submodule guard run after every `git add` (per-repo `.gitmodules`); nothing pushed, no branches created, no parent-repo staging.
- **Task 2** — Reconfigured `SuperGenius/build/OSX/Release` (Unix Makefiles, exit 0), confirmed `-ObjC` in every conformance link line, relinked the 5 test targets (`-j8`, exit 0), verified the category symbol in the hashing binary, ran all 5 binaries from `test_bin/`.

## Verification Results

| Check | Result |
|---|---|
| `-Wl,-ObjC` grep in all 5 edited CMake files | PASS (5/5 files) |
| Each of 4 nested repos has one new ObjC-mentioning commit on current branch | PASS |
| Parent repo index free of staged submodule pointers | PASS (`M SuperGenius`/`GeniusSDK`/`GeniusWallet` unstaged only) |
| Reconfigure `cmake -S SuperGenius/build/OSX -B SuperGenius/build/OSX/Release` | exit 0, `Configuring done (2.0s)` / `Generating done (2.8s)` |
| `-ObjC` in regenerated link.txt (hashing) | PASS — count = 1 |
| Relink 5 conformance targets | exit 0 |
| `nm -arch arm64 …hashing_test \| grep -c CATEGORY_MTLSamplerDescriptor` | **1** (≥ 1 required; was 0 pre-fix) |
| `processing_conformance_hashing_test` | **8/8 PASSED**, exit 0 (523 ms) |
| `processing_conformance_security_test` | **7/7 PASSED**, exit 0 (8492 ms) |
| `processing_conformance_cancellation_test` | **8/8 PASSED**, exit 0 (289 ms) |
| `processing_conformance_migration_test` | **4/4 PASSED**, exit 0 (66 ms) |
| `processing_conformance_regression_test` | **9/9 PASSED**, exit 0 (70 ms) |
| **Total** | **36/36 tests, all exit 0** (pre-fix: "Unknown C++ exception thrown in the test body" from `doesNotRecognizeSelector: setBorderColorMVK:`) |

## Commits (one per nested repo, current branches, not pushed)

| Repo | Branch | Commit | Files | Diff |
|---|---|---|---|---|
| SuperGenius | dev_blockstore | `6888b9ca` | build/OSX/CMakeLists.txt, build/iOS/CMakeLists.txt | 2 files, +10 |
| SuperGenius/SGProcessingManager | develop | `37d1e7b` | cmake/CommonBuildParameters.cmake | 1 file, +5 |
| GeniusSDK | dev_ipfs_p0_sdkverify | `b44abab` | cmake/CommonBuildParameters.cmake | 1 file, +7 |
| GeniusWallet | dev_diskspacecheck | `55df4d80` | cmake/CommonBuildParameters.cmake | 1 file, +7 |

Parent GeniusNetwork repo: **no commits made** (per plan). `git -C SuperGenius status` shows the expected unstaged `SGProcessingManager` pointer bump (SGPM HEAD moved) — deliberately left for the SuperGenius maintainer's normal flow.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking path] link.txt located in per-suite subdirectory, not at CMakeFiles root**
- **Found during:** Task 2, step 1
- **Issue:** The plan's verification path `SuperGenius/build/OSX/Release/CMakeFiles/processing_conformance_hashing_test.dir/link.txt` does not exist; with the Unix Makefiles generator the conformance targets are defined under `test/src/<suite>/`, so link.txt lives at `SuperGenius/build/OSX/Release/test/src/processing_conformance_hashing/CMakeFiles/processing_conformance_hashing_test.dir/link.txt`.
- **Fix:** Verified `-ObjC` at the actual per-suite link.txt paths for all 5 suites (count = 1 each). No code change needed — path bookkeeping only; configure itself succeeded on the first run.
- **Files modified:** none
- **Commit:** n/a

Otherwise: plan executed exactly as written.

## Known Stubs

None — pure build-system change; no runtime code touched.

## Threat Flags

None. Change matches the plan's threat model disposition (T-os1-01 mitigate): flag reaches link lines only via Apple-only platform files (sites 1–2) or `if(APPLE)` guards (sites 3–5); verified zero ObjC members in other archives per plan's diagnosis; `-force_load` avoided (duplicate symbols vs libshaderc_combined.a).

## Self-Check: PASSED

- All 5 modified files exist and contain `-Wl,-ObjC` (grep verified)
- All 4 nested-repo commits exist and are HEAD of their branches: SuperGenius `6888b9ca`, SGPM `37d1e7b`, GeniusSDK `b44abab`, GeniusWallet `55df4d80` (verified via `git log -1`)
- No deletions in any commit; no untracked files left in nested repos
