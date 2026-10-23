---
phase: 06-sgns-blockstore-v1-1-library-prerequisites-blake2b-256-cids
plan: "03"
subsystem: infra
tags: [s3, minio, factory, cmake, package-config, consumer, testing]

requires:
  - phase: 06-02 (same phase)
    provides: widened library (blake2b LINK_ONLY export entry) + green Tier-1 lane
provides:
  - OpenMinioS3Client installed factory (D-05) with documented D-06 eager-validation / zero-network-I/O contract
  - Out-of-tree install-tree consumer proof project (test/out_of_tree_consumer) as a Tier-1 hermetic ctest (D-08)
  - Hardened config.cmake.in: exactly 4 find_dependency lines (RocksDB pre-existing + libp2p + ipfs-lite-cpp + miniocpp), forced by the proof (D-07)
affects: [07 SuperGenius build wiring, genius-tube consumption]

actuals:
  tokens: 18000
  tasks: 2
  commits: 4

tech-stack:
  added: []
  patterns: [prove-first config hardening (consumer failure drives exact find_dependency lines), script-mode ctest driver with escaped-semicolon hint forwarding]

key-files:
  created:
    - thirdparty/sgns-blockstore/test/out_of_tree_consumer/CMakeLists.txt
    - thirdparty/sgns-blockstore/test/out_of_tree_consumer/consumer_main.cpp
    - thirdparty/sgns-blockstore/test/out_of_tree_consumer/run_consumer_proof.cmake
  modified:
    - thirdparty/sgns-blockstore/include/sgns-blockstore/S3Client.hpp
    - thirdparty/sgns-blockstore/src/MinioS3Client.cpp
    - thirdparty/sgns-blockstore/test/s3_block_store_test.cpp
    - thirdparty/sgns-blockstore/test/CMakeLists.txt
    - thirdparty/sgns-blockstore/cmake/config.cmake.in

key-decisions:
  - "Consumer finds httplib CONFIG REQUIRED explicitly before the package chain - the documented Phase-3 QUIET-find trap fix belongs consumer-side, never in config.cmake.in (RESEARCH Risk 5)"
  - "Consumer cmake_minimum_required is 3.20, not the plan's 3.5: CMAKE_MSVC_RUNTIME_LIBRARY requires CMP0091 (NEW from 3.15+) or the TU silently builds MDd against the MTd superbuild libs (LNK2038)"
  - "Boost.DI rides CMAKE_PREFIX_PATH (composed in the registration from the resolved cache) because cmake CLI -D rejects dotted cache names"

patterns-established:
  - "Out-of-tree consumer proof as a living Tier-1 ctest: any future export-surface change that breaks standalone consumption fails CI loudly at the exact missing link"

requirements-completed: [LIB-02]

coverage:
  - id: D1
    description: "OpenMinioS3Client declared in installed S3Client.hpp returning result<shared_ptr<S3Client>, BlockStatus> with the D-06 Doxygen contract; defined as a thin wrapper over MinioS3Client::Open"
    requirement: LIB-02
    verification:
      - kind: unit
        ref: "s3_block_store_test: OpenMinioS3ClientConstructsWithoutNetworkIO / ThrowsOnEmptyEndpoint / ThrowsOnEmptyBucket all [ OK ]"
        status: pass
      - kind: command
        ref: "installed S3Client.hpp grep OpenMinioS3Client -> line 211; install tree contains no MinioS3Client.hpp"
        status: pass
    human_judgment: false
  - id: D2
    description: "Out-of-tree consumer TU compiles+links against only sgns-blockstore::sgns-blockstore from the install tree and constructs the production client against a dead endpoint - hermetic Tier-1 ctest"
    requirement: LIB-02
    verification:
      - kind: integration
        ref: "ctest -R out_of_tree_consumer_proof -> Passed (6.6s); full Tier-1 lane 13/13"
        status: pass
    human_judgment: false
  - id: D3
    description: "config.cmake.in hardened exactly as forced: 4 find_dependency lines (RocksDB + libp2p + ipfs-lite-cpp + miniocpp), pre-hardening failure recorded verbatim"
    requirement: LIB-02
    verification:
      - kind: command
        ref: "git grep -c find_dependency -- cmake/config.cmake.in -> 4"
        status: pass
    human_judgment: false

duration: 60min
completed: 2026-10-22
status: complete
---

# Phase 6 Plan 03: Installed S3 Factory + Consumer Proof Summary

**Any out-of-tree consumer can now construct the production S3 client from the install tree alone - proven by a hermetic Tier-1 ctest whose original forced failure drove exactly three new find_dependency lines into the package config.**

## Performance

- **Duration:** ~60 min | **Tasks:** 2 | **Commits:** sgns-blockstore 8a11326, ad07cab; thirdparty c38f105 (+1 pointer)

## D-07 evidence: verbatim pre-hardening forced failure

With the consumer registered but config.cmake.in still carrying only `find_dependency(RocksDB CONFIG)`, `ctest -R out_of_tree_consumer_proof` failed at the CONFIGURE step with (captured from the ctest output, `consumer-red2.log`):

```
CMake Error at
W:/gnus/GeniusNetwork/thirdparty/build/Windows/Debug/sgns-blockstore/lib/cmake/sgns-blockstore/sgns-blockstoreTargets.cmake:61
(set_target_properties):
  The link interface of target "sgns-blockstore::sgns-blockstore" contains:
      p2p::p2p_cid
    but the target was not found.  Possible reasons include:
      * There is a typo in the target name.
```

Hardening applied exactly as forced (commit ad07cab): `find_dependency(libp2p CONFIG)`, `find_dependency(ipfs-lite-cpp CONFIG)`, `find_dependency(miniocpp CONFIG)` — each before the targets include, beside the pre-existing RocksDB line; count gate = 4. Nothing else added (D-07).

## Exact find_dependency lines added

`find_dependency(libp2p CONFIG)` / `find_dependency(ipfs-lite-cpp CONFIG)` / `find_dependency(miniocpp CONFIG)` (order: after RocksDB, before the sgns-blockstoreTargets.cmake include).

## Forwarded *_DIR hint set

sgns-blockstore_DIR (install config), libp2p_DIR, RocksDB_DIR, Snappy_DIR, miniocpp_DIR, httplib_DIR, nlohmann_json_DIR, pugixml_DIR, ipfs-lite-cpp_DIR, Boost_DIR, Protobuf_DIR, c-ares_DIR, fmt_DIR, yaml-cpp_DIR, soralog_DIR, spdlog_DIR, tsl_hat_trie_DIR, SQLiteModernCpp_DIR, sqlite3_DIR (mapped from the sub-build's lowercase `sqlite3_dir`), absl_DIR, utf8_range_DIR, OPENSSL_ROOT_DIR, OPENSSL_USE_STATIC_LIBS, OPENSSL_MSVC_STATIC_RT, GSL_INCLUDE_DIR, CMAKE_MSVC_RUNTIME_LIBRARY, Boost_USE_STATIC_RUNTIME, CMAKE_MODULE_PATH (FindZLIB shim) + ZLIB_SUPERBUILD_TARGETS_FILE, CMAKE_PREFIX_PATH (zlib prefix + Boost.DI root, composed in the registration because cmake CLI -D rejects dotted names).

## Consumer-proof ctest

`out_of_tree_consumer_proof` — `LABELS "Tier1"` (tier1_static_audit-visible), driven by script-mode `run_consumer_proof.cmake` (configure → build → execute; VS generator pinned on WIN32 only, so non-Windows lanes keep their default generator). Zero network: the TU constructs against 127.0.0.1:1 — success IS the D-06 no-I/O proof at the consumer boundary.

## Deviations from Plan

1. **[Rule 1 - documented contingency] Explicit `find_package(httplib CONFIG REQUIRED)` in the consumer CMakeLists** (plan said "NO other find_package") — Found during: prove-first iteration 3 (miniocpp_FOUND FALSE, "imported targets are referenced, but are missing: httplib::httplib") | Fix: consumer-side explicit find, exactly the library root's own precedent and RESEARCH Risk 5's prescribed placement (never config.cmake.in) | Verification: configure green.
2. **[Rule 1 - technical floor] Consumer `cmake_minimum_required(VERSION 3.20)` instead of the plan's 3.5** — Found during: iteration 5 (LNK2038 MTd/MDd mismatch) | Fix: 3.20 (library root's floor) activates CMP0091 so the forwarded CMAKE_MSVC_RUNTIME_LIBRARY takes effect | Verification: link green.
3. **[Rule 1 - hint completion] Snappy_DIR added to the forwarded hint set** — Found during: iteration 1 (find_dependency(Snappy) from RocksDB's config re-run in consumer context) | Fix: forward the sub-build's resolved Snappy_DIR | Verification: configure advanced to the real D-07 failure.

Driver robustness fixes made during iteration (all pre-commit, inside ad07cab): escaped-semicolon hint forwarding (list-valued CMAKE_PREFIX_PATH re-splitting), CMAKE_EXECUTABLE_SUFFIX default (undefined in script mode), Boost_DIR case + sqlite3_DIR mapping.

**Total deviations:** 3 auto-fixed (all documented-contingency or floor corrections, none touching library code) + driver iteration. **Impact:** the consumer proof is green, hermetic, and reproducible; every fix is precedented in RESEARCH/PATTERNS.

## Self-Check: PASSED

- Task 1 ACs: installed declaration + Doxygen D-06 contract; no-I/O construction proven in-tree; empty endpoint/bucket throw; no logging/credential printing on the factory path; hygiene green in lane.
- Task 2 ACs: consumer links ONLY sgns-blockstore::sgns-blockstore from the install tree (single library include = installed S3Client.hpp); Tier-1 lane 13/13 including out_of_tree_consumer_proof; consumer configure resolves httplib/nlohmann_json/pugixml via pinned config dirs (no clone fallback, no pkg-config probe - every hint is a superbuild install tree); config.cmake.in count = 4; pre-hardening failure recorded above; install tree has no MinioS3Client.hpp.
- Superbuild target build exit 0; no changes under SuperGenius/ or GeniusSDK/ and neither CommonBuildParameters.cmake touched.
