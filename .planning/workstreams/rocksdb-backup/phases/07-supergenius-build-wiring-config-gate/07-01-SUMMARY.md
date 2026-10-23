---
phase: 07-supergenius-build-wiring-config-gate
plan: 01
subsystem: infra
tags: [cmake, sgns-blockstore, cold-storage, find_package, windows, msvc]

requires:
  - phase: 06-sgns-blockstore-v1-1-library-prerequisites-blake2b-256-cids
    provides: installed sgns-blockstore/minio-cpp/pugixml/json install trees + OpenMinioS3Client factory
provides:
  - SGNS_COLD_STORAGE CMake option (default OFF, FORCE-off mobile) in both CommonBuildParameters.cmake files
  - Gated httplib -> miniocpp -> sgns-blockstore find chain against the superbuild install tree
  - cold_storage_link_proof_test (Tier1-labeled, gated registration) — the Windows one-binary link proof
  - Committed evidence bundle: ON/OFF configure logs, SDK ON log, dual-RocksDB reinterpretation, CI-readiness verdict=stale
affects: [08-spill-on-write, 09-cold-read-fallback, 07-03 CI lane, GeniusSDK builds, mobile legs (OFF)]

actuals:
  tokens: 28000
  tasks: 2
  commits: 7

tech-stack:
  added: []
  patterns:
    - "Gated consumption block: option + FORCE-off mobile + hinted CONFIG finds outside the PREFER_CONFIG window"
    - "Explicit found-message inside gated block (silent package configs cannot evidence themselves in logs)"

key-files:
  created:
    - SuperGenius/test/src/crdt/cold_storage_link_proof_test.cpp
    - SuperGenius/docs/evidence/cold-storage/windows-on-link-proof.log
    - SuperGenius/docs/evidence/cold-storage/windows-off-configure.log
    - SuperGenius/docs/evidence/cold-storage/genius-sdk-on-configure.log
    - SuperGenius/docs/evidence/cold-storage/dual-rocksdb-link-evidence.md
    - SuperGenius/docs/evidence/cold-storage/cold-storage-ci-readiness.md
  modified:
    - SuperGenius/build/CommonBuildParameters.cmake
    - GeniusSDK/cmake/CommonBuildParameters.cmake
    - SuperGenius/test/src/crdt/CMakeLists.txt

key-decisions:
  - "CI-readiness verdict=stale (tag test_tokenprice 2026-10-05 predates Phase-6 install trees; tarball listing observed) — 07-03 documents the ON-lane as blocked-on-release-cut with local evidence standing in"
  - "Dual-RocksDB proven as one archive: single rocksdb.lib in the proof-test vcxproj link inputs + clean MSVC link; RocksDB_DIR cache entries are shadowed by normal-variable hints, so the link line is the ground truth"
  - "Explicit message(STATUS) added inside both gated blocks — the installed sgns-blockstore config is silent on success, which made the plan's log-match verify impossible without it"

patterns-established:
  - "Gated consumption block shape (option + mobile FORCE-off + self-contained hints + httplib-first ordering + no version args) — the template for every future gated thirdparty consumption"
  - "Multi-level submodule commit chain for SuperGenius evidence: docs submodule -> SuperGenius -> root pointer"

requirements-completed: [INTG-01]

coverage:
  - id: D1
    description: "SuperGenius gated consumption block with Windows ON configure/build/ctest green and default-OFF configure proving zero new finds"
    requirement: INTG-01
    verification:
      - kind: unit
        ref: "tests: ctest -R cold_storage_link_proof_test (Test #92 Passed, 1/1)"
        status: pass
      - kind: other
        ref: "command: Select-String windows-off-configure.log 'sgns-blockstore|miniocpp|httplib' -> zero matches"
        status: pass
    human_judgment: false
  - id: D2
    description: "GeniusSDK mirrored block strictly before find_package(SuperGenius), ON configure resolving sgns-blockstore with exit 0"
    requirement: INTG-01
    verification:
      - kind: other
        ref: "command: Select-String genius-sdk-on-configure.log 'sgns-blockstore' -> 1 match (found via ...sgns-blockstore/lib/cmake/sgns-blockstore), exit 0"
        status: pass
    human_judgment: false
  - id: D3
    description: "Dual-RocksDB no-pin/no-second-archive evidence bundle (version.h 9.4.0, single rocksdb.lib in link, clean MSVC link, reinterpretation sentence)"
    requirement: INTG-01
    verification:
      - kind: other
        ref: "command: Select-String both CommonBuildParameters.cmake 'find_package\\s*\\(\\s*RocksDB\\s+[0-9]' -> zero matches; vcxproj unique rocksdb.lib scan -> 1 path"
        status: pass
    human_judgment: false
  - id: D4
    description: "Thirdparty-tarball CI-readiness verdict committed with observed evidence (verdict=stale)"
    requirement: INTG-01
    verification:
      - kind: other
        ref: "command: gh release view --repo GeniusVentures/thirdparty (tag test_tokenprice, 2026-10-05) + tar -tzf listing (no sgns-blockstore/minio-cpp/pugixml)"
        status: pass
    human_judgment: false

duration: 75 min
completed: 2026-10-23
status: complete
---

# Phase 7 Plan 01: SuperGenius Build Wiring — Windows Link Proof Summary

**Gated `SGNS_COLD_STORAGE` find_package wiring in SuperGenius + GeniusSDK proven on Windows end-to-end (configure → find → link → construct → test green), with the dual-RocksDB reinterpretation and a committed `verdict=stale` CI-readiness decision for 07-03.**

## Performance

- **Duration:** ~75 min
- **Started:** 2026-10-23 (after phase-7 context/planning session)
- **Completed:** 2026-10-23T16:02:42-04:00
- **Tasks:** 2
- **Files modified/created:** 8 (2 cmake, 1 test TU, 1 test CMakeLists, 5 evidence — 2 logs in Task 1 + 3 in Task 2)

## Accomplishments
- SuperGenius ON configure + build + ctest green against the Phase-6 install tree: `cold_storage_link_proof_test` 1/1 Passed, linking `sgns-blockstore::sgns-blockstore` in one binary with zero duplicate-symbol diagnostics
- Default-OFF configure proven byte-clean: zero new-find lines in the OFF log; ON→OFF→ON→OFF cache re-entry all green
- GeniusSDK mirrored block placed strictly before `find_package(SuperGenius CONFIG REQUIRED)` with the missing-imported-target ordering comment; SDK ON configure resolves sgns-blockstore (exit 0)
- `verdict=stale` committed with observed tarball listing: `test_tokenprice` (2026-10-05) predates the 10-20/10-21 superbuild entries — 07-03's ON-lane branches to blocked-on-release-cut
- CMake cache re-entry must-have proven: ON configure re-ran successfully after the OFF restore on the same tree

## Task Commits

1. **Task 1: SuperGenius gated consumption block + Windows ON link proof (tracer)** — docs `f0a1a02`, SuperGenius `9f20ad184`, root `aae32db` (feat)
2. **Task 2: GeniusSDK mirrored block + dual-RocksDB evidence + CI-readiness verdict** — GeniusSDK `1a4e322`, docs `4fc7a76`, SuperGenius `12c39bc94`, root `6b383d2` (feat/docs)

**Plan metadata:** this commit (docs)

## Files Created/Modified
- `SuperGenius/build/CommonBuildParameters.cmake` — gated block after AsyncIOManager, outside the PREFER_CONFIG window + found-message
- `GeniusSDK/cmake/CommonBuildParameters.cmake` — mirrored block after gnus_upnp, before the SuperGenius find
- `SuperGenius/test/src/crdt/CMakeLists.txt` — gated Tier1 registration
- `SuperGenius/test/src/crdt/cold_storage_link_proof_test.cpp` — hermetic construct-only proof (installed headers only)
- `SuperGenius/docs/evidence/cold-storage/*.log|*.md` — 5-file evidence bundle (committed in the docs submodule)

## Decisions Made
- CI ON-lane for 07-03 = blocked-on-release-cut (verdict=stale with observed listing, not assumed)
- Added explicit `message(STATUS "SGNS_COLD_STORAGE: sgns-blockstore found via ...")` inside both gated blocks (prints only when ON) — see Deviation 2
- Multi-level commit chain (docs → SuperGenius → GeniusSDK → root) discovered and used: `SuperGenius/docs` is itself a submodule

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Plan/struct mismatch] Test case (c) named a nonexistent `prefix` field**
- **Found during:** Task 1 (test authoring)
- **Issue:** Plan's case (c) lists `prefix` among S3ClientConfig fields; S3ClientConfig has no `prefix` (it is a v1.1 `ColdStorageOptions`/config-gate field per D-02, landing in 07-02)
- **Fix:** Implemented the subset that exists (endpoint, bucket, accessKey, secretKey, pathStyle, useTls) + pinned defaults (port/region/tlsVerify); documented the mapping in the test's doc comment
- **Files:** cold_storage_link_proof_test.cpp
- **Verification:** compiles + passes; no field invented
- **Commit:** 9f20ad184

**2. [Rule 3 - Blocking] Silent package config could not satisfy the plan's log-match verify**
- **Found during:** Task 2 (SDK ON proof)
- **Issue:** `Select-String genius-sdk-on-configure.log "sgns-blockstore"` requires ≥1 match, but the installed sgns-blockstore config prints nothing on success (only FATAL_ERROR on failure)
- **Fix:** Added a gated `message(STATUS "SGNS_COLD_STORAGE: sgns-blockstore found via ${sgns-blockstore_DIR}")` in BOTH blocks (ON-only output; OFF logs unaffected — re-verified CLEAN), re-ran both ON proofs
- **Files:** both CommonBuildParameters.cmake
- **Verification:** V1 = 1 match; SuperGenius ON log now shows the same line; OFF scan still zero
- **Commit:** 12c39bc94, 1a4e322

**3. [Rule 1 - Warning] C4834 [[nodiscard]] discard inside EXPECT_THROW**
- **Found during:** Task 1 (first build)
- **Fix:** `static_cast<void>(...)` around the factory call in the throw-expectation
- **Verification:** rebuild warning-clean
- **Commit:** 9f20ad184 (fixed before commit; first-build warning retained in log history)

### Observations (no fix required, recorded for later phases)

- **ZLIB module-mode residue (Pitfall 2 warning sign, bounded):** the ON configure's httplib chain ran a module-mode `find_package(ZLIB)` that cached `ZLIB_LIBRARY_RELEASE=C:/Strawberry/c/lib/libz.a`. The config-mode `ZLIB::ZLIB` target (established at file top, thirdparty tree) shields the actual link — proof: clean link with the correct single zlib. Cache residue persists in the local build tree only; nothing in SuperGenius/GeniusSDK consumes `ZLIB_LIBRARY_RELEASE`. Flag for Linux/macOS ON lanes in 07-03: if an ON-lane linker error mentioning zlib appears, clear `ZLIB_LIBRARY_*` cache entries before configuring.
- **`RocksDB_DIR` absent from CMakeCache.txt:** both files set it as a normal variable (shadowing), so the plan's "Select-String CMakeCache RocksDB_DIR" evidence was replaced by the stronger link-line ground truth (see dual-rocksdb-link-evidence.md §b).

**Total deviations:** 3 auto-fixed (2× Rule 1, 1× Rule 3) + 2 observations. **Impact:** none on gate semantics; evidence bundle is stronger than planned (link-line vs cache).

## Self-Check: PASSED

- All 6 Task-1 acceptance criteria verified (placement/order/hints/no-version-args/installed-headers-only/Tier1-label/log lines)
- All 5 Task-2 acceptance criteria verified (placement+comment/SDK log/verdict line/dual-RocksDB contents/negative gate)
- Plan-level <verification>: Windows ON green, OFF clean, no version pins, verdict committed; Linux/macOS legs remain user-push-dependent (user_setup) — flagged, not silently dropped
