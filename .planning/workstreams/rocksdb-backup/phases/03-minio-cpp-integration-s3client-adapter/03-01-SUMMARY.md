---
phase: 03-minio-cpp-integration-s3client-adapter
plan: 01
subsystem: thirdparty-build/sgns-blockstore
tags: [build-integration, minio-cpp, superbuild, cmake, spike]
requires: [thirdparty superbuild tree (Windows/MSVC Debug), sgns-blockstore Phase-2 tree]
provides: [minio-cpp v1.0.0 superbuild target, pugixml v1.16 superbuild target, LoopbackHttpStub, MinioServerHarness, D-11 wire-evidence proof]
affects: [thirdparty/build/CommonTargets.cmake, thirdparty/.gitmodules, sgns-blockstore CMake linkage]
tech-stack:
  added:
    - "minio/minio-cpp @ v1.0.0 (upstream submodule; static lib minio.lib, config package miniocpp)"
    - "zeux/pugixml @ v1.16 (upstream submodule; Q1 letter amendment)"
  patterns:
    - "shaderc-style ExternalProject with short BINARY_DIR (mcb/src) for the miniocpp-deps _deps clone tree"
    - "superbuild-local FindZLIB module shim (import targets file directly, never execute ZLIBConfig.cmake in consumer chains)"
key-files:
  created:
    - thirdparty/minio-cpp (submodule @ v1.0.0, 78e1db4)
    - thirdparty/pugixml (submodule @ v1.16, c8033ce)
    - thirdparty/build/cmake/FindZLIB.cmake
    - thirdparty/sgns-blockstore/test/LoopbackHttpStub.hpp
    - thirdparty/sgns-blockstore/test/LoopbackHttpStub.cpp
    - thirdparty/sgns-blockstore/test/MinioServerHarness.hpp
    - thirdparty/sgns-blockstore/test/MinioServerHarness.cpp
    - thirdparty/sgns-blockstore/test/minio_cpp_spike_test.cpp
  modified:
    - thirdparty/.gitmodules
    - thirdparty/build/CommonTargets.cmake
    - thirdparty/sgns-blockstore/CMakeLists.txt
    - thirdparty/sgns-blockstore/src/CMakeLists.txt
    - thirdparty/sgns-blockstore/test/CMakeLists.txt
    - thirdparty/sgns-blockstore/test/api_hygiene_test.cpp
key-decisions:
  - "D-11 entrance criterion MET at the pinned tag: if-none-match: * observed in captured raw wire bytes via PutObjectArgs.headers; path-style request line; exactly one request per op with region us-east-1; extra_headers never used"
  - "THIRD 412 error-string shape discovered: unparseable/non-XML body yields 'invalid response received; status code: 412; content-type: ' alongside the known 'PreconditionFailed:' prefix (XML+Content-Type) and 'server failed with HTTP status code 412' (empty body) - 03-03's mapper must classify ALL THREE"
  - "Consumer-side miniocpp resolution requires: explicit find_package(httplib CONFIG REQUIRED) before miniocpp + httplib_DIR/nlohmann_json_DIR/pugixml_DIR hints + superbuild-local FindZLIB shim + PREFER_CONFIG=OFF after _CMAKE_COMMON_CACHE_ARGS (CMake >=3.26 hash-guarded find_dependency re-runs ZLIBConfig.cmake whose PACKAGE_INIT macros corrupt httplibConfig.cmake's header check)"
  - "OBSERVED install layouts (ground 03-02/03-03): miniocpp config at <prefix>/minio-cpp/lib/cmake/miniocpp/miniocpp-config.cmake, exported target miniocpp::miniocpp (+ miniocpp::miniocpp_inih reused by consumers); pugixml config at lib/cmake/pugixml (as planned); nlohmann_json at share/cmake/nlohmann_json (NOT lib/cmake - plan corrected)"
requirements-completed: [BUILD-02, BUILD-03]
duration: 55 min
completed: 2026-10-21T19:48:34Z
coverage:
  - deliverable: "minio-cpp + pugixml superbuild integration (BUILD-02)"
    verification:
      - kind: command
        ref: "cmake --build thirdparty/build/Windows/Debug --target pugixml minio-cpp --config Debug (exit 0; minio.lib + miniocpp-config.cmake installed)"
        status: pass
      - kind: command
        ref: "git describe pins v1.0.0 / v1.16; upstream URL greps; CommonTargets wiring guard battery"
        status: pass
    human_judgment: false
  - deliverable: "sgns-blockstore minio PRIVATE linkage with TESTING-last rule (BUILD-03)"
    verification:
      - kind: command
        ref: "wiring guard battery (miniocpp_DIR hint, DEPENDS minio-cpp, TESTING after _CMAKE_COMMON_CACHE_ARGS)"
        status: pass
    human_judgment: false
  - deliverable: "D-11 spike proof (trio) + test utilities"
    verification:
      - kind: tests
        ref: "thirdparty/build/Windows/Debug/sgns-blockstore/src/sgns-blockstore-build#minio_cpp_spike_test (Passed)"
        status: pass
      - kind: command
        ref: "-VV gate-discipline check: [SGNS_BLOCKSTORE][MINIO-TIER] skip label present with env unset"
        status: pass
    human_judgment: false
  - deliverable: "Regression-clean Phase-1/2 behavior + SC2 containment"
    verification:
      - kind: tests
        ref: "inner-tree ctest battery 7/7 (memory/local/crash/api_hygiene/cid_spike/minio_cpp_spike/header_hygiene)"
        status: pass
      - kind: command
        ref: "git grep '#include <(miniocpp|minio)/' -- include/ exits 1 (installed headers minio-free)"
        status: pass
    human_judgment: false
  - deliverable: "TLS-on smoke against live MinIO (backstop truth)"
    verification: []
    human_judgment: true
    rationale: "env-gated behind SGNS_BLOCKSTORE_TEST_MINIO_BIN (D-07/D-09); no MinIO binary on this dev box - lane skips loudly by design; needs a bring-your-own-binary run to exercise"
  - deliverable: "Four non-Windows platform lanes build (backstop truth, Q3)"
    verification: []
    human_judgment: true
    rationale: "Windows/MSVC is the in-phase proof lane; Linux/macOS/iOS/Android evidence is per-lane build-log follow-up per Q3 resolution"
---

# Phase 3 Plan 01: minio-cpp Integration & S3Client Adapter — Build Integration + D-11 Spike Summary

One-liner: minio-cpp v1.0.0 + pugixml v1.16 integrated through the superbuild (shaderc-style, upstream dep mechanism as-is per D-12) with the D-11 entrance criterion proven on the wire, the LoopbackHttpStub/MinioServerHarness test utilities landed, and a 7/7 regression battery green on Windows/MSVC Debug.

Duration: 55 min | Tasks: 3 | Files: 13 | Start ~18:53Z, end 2026-10-21T19:48:34Z

## Spike Verdict (Task 3 record requirement)

**D-11 entrance criterion: MET.**

- (a) Conditional header: `if-none-match: *` observed in the stub-captured raw request bytes, sent through `PutObjectArgs.headers` (the `ObjectWriteArgs::headers` Multimap). `extra_headers` never used. Bonus evidence: the header is listed in the SigV4 `SignedHeaders=...;if-none-match;...` authorization header.
- (b) BaseUrl trio: path-style `PUT /spike-bucket/spike-object HTTP/1.1` request line (`virtual_style=false` default); region pin `us-east-1` yields exactly ONE captured request per op (no `?location` roundtrip); HTTPS field exercised by the env-gated TLS smoke (skips loudly when `SGNS_BLOCKSTORE_TEST_MINIO_BIN` unset — no binary on this box, by design D-07/D-09).
- (c) TLS-off plain-HTTP loopback is the primary lane, asserted by every hermetic test; TLS-on smoke wired and gated.

**Grounding facts for 03-02/03-03** (all observed on this lane):
- Installed miniocpp config: `thirdparty/build/Windows/Debug/minio-cpp/lib/cmake/miniocpp/miniocpp-config.cmake`
- Exported target spelling: `miniocpp::miniocpp` (plus `miniocpp::miniocpp_inih`, reused by the consumer config); artifact `minio.lib` (OUTPUT_NAME minio)
- pugixml config dir: `lib/cmake/pugixml` (as planned)
- nlohmann_json config dir: `share/cmake/nlohmann_json` (OBSERVED — NOT lib/cmake; export var corrected)
- New: consumer-side resolution recipe (explicit `find_package(httplib CONFIG REQUIRED)` before miniocpp + hints + FindZLIB shim) — see Deviation 3

## Accomplishments

- Upstream submodules `thirdparty/minio-cpp` @ v1.0.0 and `thirdparty/pugixml` @ v1.16 (absolute upstream URLs; Q1 letter amendment recorded in CommonTargets comments). Note: upstream's `latest` tag aliases the v1.16 commit in pugixml — deleted from the local clone so `describe --tags` prints `v1.16`.
- `ExternalProject_Add(pugixml)` + `ExternalProject_Add(minio-cpp)` (short `BINARY_DIR mcb/src`, no PATCH_COMMAND — upstream `miniocpp-deps.cmake` ran as-is and cloned cpp-httplib v0.53.1 + inih r58 at configure time, D-12 honored with zero forks).
- sgns-blockstore: `find_package(httplib CONFIG REQUIRED)` + `find_package(miniocpp CONFIG REQUIRED)`; PRIVATE `miniocpp::miniocpp` link; TESTING-last cache-arg rule intact.
- Test utilities: `LoopbackHttpStub` (127.0.0.1-only raw-socket scripted server with byte capture; `0.0.0.0` appears nowhere) and `MinioServerHarness` (env-gated, no-download, per-run random creds, deadline health poll, ordered teardown).
- `minio_cpp_spike_test`: 3 TESTs; hermetic pair green in CI, TLS smoke loud-skips.
- `api_hygiene_test` include-everything block documented as the SC2 proof with minio linked; `header_hygiene` unmodified (already bans `minio`).
- Full regression battery 7/7 green with the minio linkage present.

## Deviations from Plan

**[Rule 1 - plan-fact correction] nlohmann_json config-dir layout** — Found during: Task 1 | Issue: plan/PATTERNS specified `lib/cmake/nlohmann_json`; observed install is `share/cmake/nlohmann_json` (GNUInstallDirs datadir) | Fix: `_FINDPACKAGE_JSON_CONFIG_DIR` points at the observed path, comment records it | Files: CommonTargets.cmake | Verification: minio-cpp configure green | Commit: a2461c4

**[Rule 1 - missing build-order edge] minio-cpp needs `DEPENDS json`** — Found during: Task 1 | Issue: first configure failed `find_package(nlohmann_json)` (json install tree existed but no build-order dep); adding DEPENDS then exposed that the json ExternalProject target is defined AFTER the minio-cpp entry (CMake requires DEPENDS targets to exist) | Fix: relocated the json entry above the pugixml/minio-cpp block | Files: CommonTargets.cmake | Verification: configure+build green | Commit: a2461c4

**[Rule 2 - missing critical wiring] consumer-side miniocpp resolution chain** — Found during: Task 2 | Issue: `find_package(miniocpp)` in sgns-blockstore failed three ways: (1) `miniocpp-config.cmake` re-runs `miniocpp-deps.cmake` in the CONSUMER context so httplib/nlohmann_json/pugixml hints must be passed to the sgns-blockstore entry too (plan said "not needed here"); (2) `_ZLIB_PACKAGE_ARGS`' `CMAKE_FIND_PACKAGE_PREFER_CONFIG` routes httplib's internal `find_dependency(ZLIB)` into `ZLIBConfig.cmake`, whose `@PACKAGE_INIT@` macros corrupt httplibConfig.cmake's own `set_and_check` with the zlib prefix (CMake >= 3.26 find_dependency is hash-guarded, so `_FOUND` does not short-circuit) — isolated via a standalone probe project; (3) even with httplib resolving, the QUIET find inside miniocpp-deps.cmake leaves `httplib::httplib` invisible to find_package's imported-target-reference verification → `miniocpp_FOUND=FALSE` | Fix: superbuild-local `FindZLIB.cmake` module shim (imports the zlib targets file directly), `CMAKE_MODULE_PATH` + `ZLIB_SUPERBUILD_TARGETS_FILE` + `PREFER_CONFIG=OFF` (positioned AFTER `_CMAKE_COMMON_CACHE_ARGS` whose own FORCE would win) + `httplib_DIR`/`nlohmann_json_DIR`/`pugixml_DIR` hints on the sgns-blockstore entry, and explicit `find_package(httplib CONFIG REQUIRED)` before the miniocpp find in sgns-blockstore's CMakeLists | Files: CommonTargets.cmake, build/cmake/FindZLIB.cmake, sgns-blockstore/CMakeLists.txt | Verification: configure+build+ctest green; --trace proved the full chain | Commits: b453e4b, 2c0249c

**[Rule 1 - test-fixture fidelity] XML 412 needed `Content-Type: application/xml`** — Found during: Task 2 | Issue: scripted XML-body 412 without a content-type header produced a THIRD error-string shape (`invalid response received; status code: 412; content-type: `) instead of the research-predicted `PreconditionFailed:` prefix | Fix: real-MinIO-faithful content-type added; classifier extended to all three shapes; finding recorded for 03-03's mapper | Files: minio_cpp_spike_test.cpp | Verification: PreconditionEvidenceShapes green | Commit: b453e4b

**[Rule 1 - tag alias] pugixml `latest` tag aliases v1.16** — Found during: Task 1 | Issue: `git -C pugixml describe --tags` printed `latest` (same commit c8033ce), failing the plan's exact-output verify | Fix: deleted the moving alias tag from the local clone (superproject pins by SHA regardless) | Verification: describe prints `v1.16` | Commit: (clone-local, rides the submodule SHA)

Total deviations: 5 auto-fixed (3× Rule 1, 1× Rule 2, 1× Rule 1 fixture). **Impact:** all fixes are inside the plan's file set, zero forks (D-12 intact), red lines (upstream URLs, static, non-exported, TESTING-last) verified green after the fixes.

## Issues Encountered

None blocking. Noted: the outer superbuild has no top-level `minio_cpp_spike_test` target (test targets live in the inner tree — MSB1009 when passed to the outer build; build/run via `thirdparty/build/Windows/Debug/sgns-blockstore/src/sgns-blockstore-build`, per the established workstream recipe).

## Authentication Gates

None.

## Commits

- sgns-blockstore: b679c9e (feat linkage), b453e4b (test spike+utilities), 0628ff5 (test SC2 note)
- thirdparty: a2461c4 (build superbuild integration), 2c0249c (build consumer-side resolution), d2cc423 (chore bump)
- root: 65b16d3, c907d62, cc41090 (pointer bumps)

## Self-Check: PASSED
