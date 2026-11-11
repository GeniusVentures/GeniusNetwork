---
phase: 06-sgns-blockstore-v1-1-library-prerequisites-blake2b-256-cids
plan: "01"
subsystem: infra
tags: [blake2b, cid, multihash, cmake, superbuild, testing]

requires:
  - phase: 05-fault-injection-three-tier-hardening
    provides: v1.0 library with sha-256-only CidOf, Tier-1 ctest lane, header hygiene guard
provides:
  - 3-arg CidOf overload accepting exactly {sha-256, blake2b-256} (D-04, D-01, D-03)
  - blake2 build wiring end-to-end (root find_package + PRIVATE ipfs-lite-cpp::blake2 + superbuild hint/DEPENDS)
  - Committed D-02 cross-check evidence against the real producer sgns::common::getCidOf
  - Extended header-hygiene guard banning blake2 includes from installed headers
affects: [06-02 backend widening, 06-03 consumer proof, 07 SuperGenius build wiring]

actuals:
  tokens: 13000
  tasks: 2
  commits: 4

tech-stack:
  added: [ipfs-lite-cpp::blake2 (PRIVATE link; same object code as getCidOf)]
  patterns: [installed-free dependency widening (LINK_ONLY export entry + hygiene ban), two-source vector pinning with committed producer cross-check]

key-files:
  created:
    - thirdparty/sgns-blockstore/docs/evidence/blake2b-crosscheck/getcidof-crosscheck.log
  modified:
    - thirdparty/sgns-blockstore/include/sgns-blockstore/Cid.hpp
    - thirdparty/sgns-blockstore/src/Cid.cpp
    - thirdparty/sgns-blockstore/test/cid_spike_test.cpp
    - thirdparty/sgns-blockstore/test/header_hygiene_check.cmake
    - thirdparty/sgns-blockstore/CMakeLists.txt
    - thirdparty/sgns-blockstore/src/CMakeLists.txt
    - thirdparty/build/CommonTargets.cmake

key-decisions:
  - "blake2b linked via ipfs-lite-cpp::blake2 (never vendored) - byte-compatibility with getCidOf by construction; vendoring would collide unrenamed blake2b_* globals when SuperGenius links both archives"
  - "3-arg CidOf throws std::invalid_argument for any HashType outside {sha256, blake2b-256} (D-03); 2-arg body delegates pinned to sha-256, signature byte-identical"
  - "CID literals pinned ONLY from the committed cross-check log (never memory) after Python-hashlib/vendored-C two-source agreement"

patterns-established:
  - "PRIVATE-linked hash dependency + hygiene-guard ban + LINK_ONLY export entry: the shape for any future backend-only dependency"
  - "Dev-run evidence logs under docs/evidence/<topic>/ as the 'evidenced, not trusted' bridge for pinned test literals"

requirements-completed: [LIB-01]

coverage:
  - id: D1
    description: "blake2 build wiring (superbuild hint + DEPENDS, root find_package, PRIVATE link) with Tier-1 green and zero library source change in Task 1"
    requirement: LIB-01
    verification:
      - kind: command
        ref: "cmake --build thirdparty/build/Windows/Debug --config Debug --target sgns-blockstore"
        status: pass
      - kind: unit
        ref: "ctest -L Tier1 (12/12 passed, Task 1 commit 04abcc4/d957720)"
        status: pass
    human_judgment: false
  - id: D2
    description: "3-arg CidOf overload: pinned blake2b/DAG_CBOR vector equality, sha-256 2/3-arg equivalence, unsupported-hash throws"
    requirement: LIB-01
    verification:
      - kind: unit
        ref: "cid_spike_test (Blake2bDagCborKnownVector, ThreeArgSha256EqualsTwoArg, ThreeArgUnsupportedHashThrows) - Passed"
        status: pass
      - kind: unit
        ref: "header_hygiene with blake2 ban - Passed"
        status: pass
    human_judgment: false
  - id: D3
    description: "D-02 committed cross-check evidence: 3/3 verdict=MATCH lines + SUMMARY line in getcidof-crosscheck.log"
    requirement: LIB-01
    verification:
      - kind: command
        ref: "git grep -c verdict=MATCH -- docs/evidence/blake2b-crosscheck/getcidof-crosscheck.log -> 3"
        status: pass
    human_judgment: false

duration: 40min
completed: 2026-10-22
status: complete
---

# Phase 6 Plan 01: blake2b-256 Foundation Summary

**3-arg CidOf composes CIDv1/DAG_CBOR/blake2b-256 exactly as the real CRDT producer getCidOf does — linked against the same vendored blake2 object code, pinned by an independently derived + producer-cross-checked committed vector.**

## Performance

- **Duration:** ~40 min | **Tasks:** 2 | **Commits:** sgns-blockstore 04abcc4, c79bb17; thirdparty d957720, bfb179c

## Pinned vector literals + derivation provenance (D-02)

Payloads are RFC 8949 canonical CBOR maps (hand-derivable): `{}` = `a0`, `{"key":1}` = `a1636b657901`, `{"hello":"world"}` = `a16568656c6c6f65776f726c64`.

Source B (independent implementation, RFC 7693-conformant): `python -c "import hashlib; print(hashlib.blake2b(bytes.fromhex('<hex>'), digest_size=32).hexdigest())"` (Python 3.13):

| payload | python blake2b-256 | getCidOf CID (pinned) |
|---|---|---|
| a0 | d36a2619a672494604e11bb447cbcf5231e9f2ba25c2169177edc941bd50ad6c | bafy2bzacedjwujqzuzzesrqe4en3ir6lz5jdd2psxis4efuro7w4sqn5kcwwy |
| a1636b657901 | 5cd0f4e9ecd356e911fc8560515f9a77547bdcb77b8e6c607825b16640a32438 | bafy2bzacebonb5hj5tjvn2ir7scwauk7tj3vi664w55y43dapas3czsaumsdq |
| a16568656c6c6f65776f726c64 | e7785feaf7bd4317ac600d1d16ec0bcad104494752537683a0292307dac6c15e | bafy2bzacedtxqx7k666ugf5mmagr2fxmbpfncbcji5jfg5uduausgb62y3av4 |

Agreement bar: Python stdlib vs the vendored reference C exercised through the real producer (two independent codebases), verdict computed in the dev TU by comparing the digest embedded in the produced CID (plus type/codec/version checks). Log: `docs/evidence/blake2b-crosscheck/getcidof-crosscheck.log` (UTF-8, `SUMMARY: 3/3 MATCH`).

## Cross-check dev-run commands (throwaway project, never committed)

Project at `thirdparty/build/Windows/Debug/cid-crosscheck-dev/` (gitignored build tree): `find_package(libp2p CONFIG REQUIRED)` then `find_package(ipfs-lite-cpp CONFIG REQUIRED)`, TU links `ipfs-lite-cpp::cid`, includes `primitives/cid/cid.hpp` + `crypto/blake2/blake2b160.hpp` from the superbuild install tree. Configure required the full hint closure (`Boost/OpenSSL/Protobuf/c-ares/fmt/yaml-cpp/soralog/spdlog/tsl_hat_trie/SQLiteModernCpp/sqlite3/libp2p/ipfs-lite-cpp` `*_DIR` + `absl_DIR`/`utf8_range_DIR` from the protobuf install + `CMAKE_PREFIX_PATH=<superbuild>/Boost.DI` (CMake CLI `-D` rejects dotted names) + the superbuild FindZLIB shim args `CMAKE_MODULE_PATH=thirdparty/build/cmake` and `ZLIB_SUPERBUILD_TARGETS_FILE` (protobuf::libprotobuf references ZLIB::ZLIBSTATIC) + `CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDebug` + `Boost_USE_STATIC_RUNTIME=ON` + `GSL_INCLUDE_DIR`). Run output: 3/3 MATCH above.

## Drift vs RESEARCH line anchors

- RESEARCH A3 assumed DAG_CBOR CIDv1 strings start `bafyre...` — actual pinned strings start `bafy2bzace...` (base32 of the 0x71+varint(0xb220) prefix renders differently; A3 was flagged cosmetic/unverified — literals pinned from the run, never the assumption).
- getCidOf at `primitives/cid/cid.cpp:129-136`, blake2b160.hpp signature, CommonTargets anchors (ipfs-lite-cpp entry ~498-533, sgns-blockstore entry ~862-918), cid_spike_test pinning comment ~66-73: all accurate, no material drift.
- CMake CLI landmine (not in RESEARCH): `-DBoost.DI_DIR=...` is rejected by cmake argument parsing ("Parse error in command line argument: Boost") — dotted cache names must ride CMAKE_PREFIX_PATH on the command line.

## Deviations from Plan

**[Rule 1 - environment] CMake CLI rejects dotted -D names** — Found during: Task 2 cross-check dev configure | Fix: resolved Boost.DI via `-DCMAKE_PREFIX_PATH=<superbuild>/Boost.DI` (smoke-configure precedent) | Files: none (throwaway project) | Verification: configure green, 3/3 MATCH | Commit: n/a (throwaway).

**Total deviations:** 1 auto-fixed. **Impact:** none on production code; hint-closure recipe recorded above for the 06-03 consumer driver.

## Self-Check: PASSED

- Task 1 ACs: superbuild hint line present (CommonTargets.cmake:875), DEPENDS ends `ipfs-lite-cpp` (:916), TESTING still last -D, PRIVATE blake2 beside miniocpp, Tier-1 12/12 green with zero source change, sub-build cache carries `ipfs-lite-cpp_DIR`.
- Task 2 ACs: 3-arg overload declared beside byte-identical 2-arg (diff shows only `+` signature lines); sha512/blake2s128 throw pinned; blake2b vector equality pinned from the committed log; 3-arg sha256 == 2-arg; blake2b160.hpp only in src/Cid.cpp + hygiene green with ban; log UTF-8 with 3 MATCH + SUMMARY; Tier-1 12/12 with v1.0 suite unchanged.
- Plan verification block: build exit 0; Tier-1 lane green; `git grep -c verdict=MATCH` = 3; no changes under SuperGenius/ or GeniusSDK/.
