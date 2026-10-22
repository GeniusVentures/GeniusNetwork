---
phase: 01-blockstore-contract-memory-backend-conformance-kit
plan: 01
subsystem: infra
tags: [cmake, cid, libp2p, superbuild, externalproject, submodules]

requires: []
provides:
  - sgns-blockstore git repo skeleton (AsyncIOManager-mirrored bootstrap, namespaced export)
  - thirdparty superbuild ExternalProject target + .gitmodules gitlink (BUILD-01)
  - Public Cid alias + CidOf(bytes, codec) helper installed at include/sgns-blockstore/Cid.hpp (D-05/D-07)
  - C1 spike evidence: p2p_cid ADOPTED, 3/3 parts green (D-06)
affects: [01-02-contract-freeze, 01-03-conformance-kit, phase-02-local-block-store]

actuals:
  tokens: 4000   # chars/4 over realized diff (repo 14.7k chars + CommonTargets entry + .gitmodules row); plan estimate 38000 was ~9x high - bootstrap is config-boilerplate-heavy
  tasks: 3
  commits: 4     # 2 inner repo (d5ce30b, 5911343) + 1 thirdparty (47939d6) + 1 root (this SUMMARY commit)

tech-stack:
  added: [sgns-blockstore (new GNUS repo), p2p::p2p_cid consumer]
  patterns: [ExternalProject with explicit find_dependency config closure, TESTING-after-common-args ordering, namespaced install(EXPORT)]

key-files:
  created:
    - thirdparty/sgns-blockstore/CMakeLists.txt
    - thirdparty/sgns-blockstore/cmake/functions.cmake
    - thirdparty/sgns-blockstore/cmake/config.cmake.in
    - thirdparty/sgns-blockstore/.gitattributes
    - thirdparty/sgns-blockstore/src/CMakeLists.txt
    - thirdparty/sgns-blockstore/include/sgns-blockstore/Cid.hpp
    - thirdparty/sgns-blockstore/src/Cid.cpp
    - thirdparty/sgns-blockstore/test/CMakeLists.txt
    - thirdparty/sgns-blockstore/test/cid_spike_test.cpp
  modified:
    - thirdparty/.gitmodules
    - thirdparty/build/CommonTargets.cmake

key-decisions:
  - "C1 RESOLVED: p2p_cid ADOPTED per D-05/D-06 - all three spike parts green; the ipfs-lite-cpp granular cid fallback was NOT exercised"
  - "Known-vector constant corrected: research/plan literal had 'w' at position 33; runtime codec AND an independent from-scratch base32 computation of 0x01 0x55 0x12 0x20 || sha256(hello world) both give ...72ysco7... (final vector bafkreifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e)"
  - "outcome envelope published as namespace alias (namespace outcome = libp2p::outcome inside sgns::blockstore) - the vendored outcome declares libp2p::outcome, not outcome; D-01 signature text outcome::result<...> is preserved verbatim"
  - "Superbuild entry carries the full find_dependency config closure (absl/c-ares/fmt/Protobuf/soralog/spdlog/sqlite3/SQLiteModernCpp/tsl_hat_trie/utf8_range/yaml-cpp/Boost.DI/zlib) - libp2pConfig.cmake demands it; the plan's minimal arg list was insufficient"
  - "Developer follow-up (not a blocker): push the local sgns-blockstore repo to the ../sgns-blockstore.git GeniusVentures remote before any external consumption (T-01-SC)"

patterns-established:
  - "New-repo bootstrap recipe: mirror AsyncIOManager shape but name the test gate TESTING (superbuild forces BUILD_TESTING=OFF), add NAMESPACE to install(EXPORT), and carry BUILD_BYPRODUCTS the AsyncIOManager entry omits"
  - "Inner-vcxproj rebuild path for source edits after first superbuild build (outer wrapper no-ops on tlogs): build <name>/src/<name>-build directly, then its INSTALL target"

requirements-completed: [BUILD-01, CORE-04]

coverage:
  - id: D1
    description: "sgns-blockstore repo + thirdparty superbuild entry + install tree (lib + public header + package config)"
    requirement: BUILD-01
    verification:
      - kind: other
        ref: "cmake --build ... --target sgns-blockstore (Task 2, real compile+install output) + Test-Path install-tree checks (lib/sgns-blockstore.lib, include/sgns-blockstore/Cid.hpp) - pass"
      - kind: other
        ref: "standalone smoke configure+build against install tree (Task 1, VS generator) - pass"
    human_judgment: false
  - id: D2
    description: "C1 CID spike, three-part entrance criterion - p2p_cid adopted (D-06)"
    requirement: CORE-04
    verification:
      - kind: unit
        ref: "thirdparty/sgns-blockstore/test/cid_spike_test.cpp#Part1RoundTripCidV0AndV1, #Part2CidOfKnownVectors, #Part3StandaloneConsumerLinkBar - ctest 100% (3 tests, failures=0, xunit)"
    human_judgment: false
  - id: D3
    description: "ipfs-lite dependency ban holds in dependency shapes (target refs, find_package, include directives)"
    requirement: CORE-01
    verification:
      - kind: other
        ref: "git grep -nE 'ipfs-lite-cpp::|find_package\\(ipfs-lite-cpp|#include.*ipfs_lite/' in sgns-blockstore - exit 1 (no matches), run after Tasks 1 and 3 - pass"
    human_judgment: false

duration: 22min
completed: 2026-10-20
status: complete
---

# Phase 1 Plan 01: Tracer Slice Summary

**sgns-blockstore repo bootstrapped, wired into the thirdparty superbuild end-to-end (repo → ExternalProject → install tree), and the C1 CID spike is 3/3 green — `p2p_cid` adopted per D-05/D-06 with the public sha-256-only `CidOf` helper shipped.**

## Performance

- **Duration:** ~22 min
- **Started:** 2026-10-20T17:05Z (approx)
- **Completed:** 2026-10-20T17:27Z
- **Tasks:** 3/3
- **Files modified:** 11 (9 created in new repo, 2 superproject files)

## Accomplishments
- New GNUS repo `thirdparty/sgns-blockstore` (branch `main`, 2 commits) mirrors the AsyncIOManager bootstrap with the deliberate deviations: `option(TESTING)` gate (never BUILD_TESTING), `NAMESPACE sgns-blockstore::` export, CRLF-hygiene `.gitattributes` from commit one
- Superbuild wiring: `.gitmodules` row + gitlink (`5911343`) + `ExternalProject_Add(sgns-blockstore ...)` at CommonTargets.cmake:778 with `-DTESTING:BOOL=ON` positioned AFTER `_CMAKE_COMMON_CACHE_ARGS` (verified: entry-relative lines 24 < 30), `DEPENDS libp2p`, `BUILD_BYPRODUCTS`, `_FINDPACKAGE_SGNS_BLOCKSTORE_CONFIG_DIR` exported
- C1 spike: Part 1 round-trips (CIDv0 base58 `Qm` + 34-byte `0x12 0x20` wire, CIDv1 base32 known vector), Part 2 `CidOf` pinned to manual `Multihash::create` + 3-arg ctor construction for RAW and DAG_PB (32-byte digest, V1, sha256 multihash always), Part 3 standalone-consumer link bar with the pre-refined Pitfall-1 wording — `p2p_cid` link closure (`p2p_cid → p2p_uvarint → p2p_logger → soralog/yaml-cpp/Boost.DI`) recorded as accepted libp2p-family overhead, fallback documented as strictly heavier (links c-ares/fmt/blake2 directly)
- Install tree proven: `lib/sgns-blockstore.lib` + `include/sgns-blockstore/Cid.hpp` + full `lib/cmake/sgns-blockstore/` package config (Targets/Targets-debug/Config/ConfigVersion)

## Task Commits

Each task was committed atomically (innermost-first: repo → thirdparty):

1. **Task 1: repo skeleton + public CidOf helper** — `d5ce30b` (feat, sgns-blockstore repo; amended once to fold in the two compile fixes found by the smoke build)
2. **Task 2 (tracer): superbuild .gitmodules + CommonTargets entry** — `47939d6` (build, thirdparty repo; .gitmodules + gitlink + CommonTargets.cmake, 3 files)
3. **Task 3: C1 CID spike** — `5911343` (test, sgns-blockstore repo; amended once to fold in the known-vector constant correction)

**Plan metadata:** root-repo commit (this SUMMARY + tracking files + thirdparty pointer bump)

## Files Created/Modified
- `thirdparty/sgns-blockstore/CMakeLists.txt` — root bootstrap: TESTING gate, namespaced install/export, package config
- `thirdparty/sgns-blockstore/cmake/functions.cmake` — addtest/addtest_part/disable_clang_tidy verbatim from AsyncIOManager
- `thirdparty/sgns-blockstore/cmake/config.cmake.in` — @PACKAGE_INIT@ + Targets include
- `thirdparty/sgns-blockstore/.gitattributes` — CRLF hygiene
- `thirdparty/sgns-blockstore/src/CMakeLists.txt` — static lib, PUBLIC p2p::p2p_cid, BUILD_INTERFACE/INSTALL_INTERFACE includes
- `thirdparty/sgns-blockstore/include/sgns-blockstore/Cid.hpp` — Cid alias + CidOf declaration, D-08 sha-256-only + blake2b CRDT boundary documented
- `thirdparty/sgns-blockstore/src/Cid.cpp` — pure composition: sha256 → Multihash::create → CIDv1 ctor
- `thirdparty/sgns-blockstore/test/CMakeLists.txt` — addtest(cid_spike_test) linking exactly sgns-blockstore + p2p::p2p_cid
- `thirdparty/sgns-blockstore/test/cid_spike_test.cpp` — the three-part spike
- `thirdparty/.gitmodules` — sgns-blockstore row (../sgns-blockstore.git)
- `thirdparty/build/CommonTargets.cmake` — ExternalProject entry + config-closure args + _FINDPACKAGE_SGNS_BLOCKSTORE_CONFIG_DIR

## Decisions Made
- **C1 adoption recorded**: spike green on all three parts → D-05 alias stands as written; fallback not needed
- **Vector correction**: the known sha-256 CIDv1 RAW vector for "hello world" is `bafkreifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e` — the research/plan literal contained a transcription error at position 33 (`w` → `y`), proven by two independent sources (runtime codec, from-scratch base32 computation); plan's regenerate-and-cross-check instruction exercised as designed
- **Developer follow-up**: push sgns-blockstore to the GeniusVentures remote (../sgns-blockstore.git) before external consumption (threat T-01-SC mitigation); the superbuild consumes SOURCE_DIR, so nothing is blocked

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Environment] Smoke build used VS generator + full config-hint closure**
- **Found during:** Task 1 (verify)
- **Issue:** `-GNinja` impossible (cl.exe not on PATH); bare configure failed on Boost/OpenSSL (libp2p's config carries a find_dependency closure); Boost rejected dynamic-runtime variants
- **Fix:** `-G "Visual Studio 17 2022"` + `CMAKE_PREFIX_PATH` closure + `-DBoost_DIR=.../boost/build/lib/cmake/Boost-1.85.0` + `-DOPENSSL_ROOT_DIR=.../openssl/build` + `-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDebug` + `-DBoost_USE_STATIC_RUNTIME=ON` — all within the plan's explicit fails_when guidance ("add -DBoost_DIR / -DOpenSSL_DIR pointing into thirdparty/build/Windows/Debug")
- **Files:** none (build-tree args only)
- **Verification:** configure + build green; sgns-blockstore.lib produced
- **Commit:** n/a (build args)

**2. [Rule 1 - Bug] outcome namespace alias**
- **Found during:** Task 1 (smoke build)
- **Issue:** vendored outcome declares `namespace libp2p::outcome`, so plan-spelled `outcome::result` is unresolvable from `sgns::blockstore`
- **Fix:** `namespace outcome = libp2p::outcome;` inside `sgns::blockstore` (Cid.hpp) — published signature text preserved verbatim; establishes the D-01 envelope for Phase 2 headers
- **Files:** include/sgns-blockstore/Cid.hpp
- **Verification:** compiles; alias also asserted by Part-3 static_assert
- **Commit:** folded into d5ce30b

**3. [Rule 1 - Bug] OUTCOME_TRY macro arity**
- **Found during:** Task 1 (smoke build)
- **Issue:** vendored wrapper injects `auto` itself (`OUTCOME_TRY_2 → BOOST_OUTCOME_TRY(auto ...)`); `OUTCOME_TRY(auto x, ...)` is a double-auto C3530
- **Fix:** bare-name form `OUTCOME_TRY(digest, ...)`
- **Files:** src/Cid.cpp
- **Verification:** compiles green
- **Commit:** folded into d5ce30b

**4. [Rule 3 - Blocking] Superbuild entry needed the full find_dependency closure**
- **Found during:** Task 2 (entry authoring, pre-verified against libp2pConfig.cmake)
- **Issue:** plan's arg list (GSL/GTest/libp2p + boost/openssl/common) cannot satisfy libp2pConfig.cmake's find_dependency(Protobuf/c-ares/fmt/yaml-cpp/soralog/tsl_hat_trie/Boost.DI/SQLiteModernCpp) — sub-build has no prefix path
- **Fix:** added the ipfs-pubsub-style closure args (absl_DIR, Boost.DI_DIR, c-ares_DIR, fmt_DIR, Protobuf_DIR, soralog_DIR, spdlog_DIR, sqlite3_dir, SQLiteModernCpp_DIR, tsl_hat_trie_DIR, utf8_range_DIR, yaml-cpp_DIR, _ZLIB_PACKAGE_ARGS)
- **Files:** thirdparty/build/CommonTargets.cmake
- **Verification:** superbuild configure + build + install green first try
- **Commit:** 47939d6

**5. [Rule 1 - Data] Known-vector constant corrected**
- **Found during:** Task 3 (first ctest run)
- **Issue:** plan/research literal differs from runtime at position 33
- **Fix:** corrected to `...72ysco7...` after independent verification (from-scratch base32 of 0x01 0x55 0x12 0x20 || b94d27b9... digest agrees with the codec); comment in-file records the regeneration
- **Files:** test/cid_spike_test.cpp
- **Verification:** ctest 3/3 green
- **Commit:** folded into 5911343

**6. [Rule 3 - Build system] Outer wrapper no-op after source edits**
- **Found during:** Task 3 (rebuild)
- **Issue:** `cmake --build --target sgns-blockstore` no-ops after first build (ExternalProject stamps/tlogs; repo-documented wrapper-vcxproj trap — also in repo memory)
- **Fix:** built the inner sub-build tree directly (`.../sgns-blockstore/src/sgns-blockstore-build` ALL_BUILD + INSTALL), per the documented recipe; plan's fails_when explicitly directs investigating the inner vcxproj
- **Files:** none (build-tree procedure)
- **Verification:** real compile output for cid_spike_test; ctest green in the same tree
- **Commit:** n/a

**Total deviations:** 6 auto-fixed (3 Rule 1, 3 Rule 3). **Impact:** none architectural — every fix stays inside the plan's anticipated failure modes; the frozen decisions D-05..D-08 are untouched.

## Authentication Gates

None encountered.

## Self-Check: PASSED

- All 3 tasks executed; acceptance criteria verified per task (Task 1: 8/8, Task 2: 6/6, Task 3: 5/5 + SUMMARY recording)
- Plan-level verification: sub-build ctest 3/3 green (xunit failures="0"), install-tree artifacts present with fresh mtimes, innermost-first commit chain verified (5911343 → 47939d6 gitlink)
- Ready for 01-02 (contract freeze + MemoryBlockStore builds on this repo skeleton and the adopted CID alias)
