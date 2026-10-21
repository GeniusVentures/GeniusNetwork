---
phase: 03-minio-cpp-integration-s3client-adapter
plan: 02
subsystem: sgns-blockstore/src
tags: [adapter, s3-client, fake, hermetic-tests]
requires: [Phase-1 frozen types (result alias, BlockStatus), 03-01 grounding facts]
provides: [internal S3Client interface, InMemoryS3Client fake, per-op fault scripting seam (Phase-5 seed)]
affects: [sgns-blockstore static library source list, test target registry]
tech-stack:
  added: []
  patterns:
    - "internal adapter seam in src/ (never installed - D-04)"
    - "per-op fault table (S3Op x S3FaultKind) extending FaultController's per-backend-kind philosophy"
key-files:
  created:
    - thirdparty/sgns-blockstore/src/S3Client.hpp
    - thirdparty/sgns-blockstore/src/InMemoryS3Client.hpp
    - thirdparty/sgns-blockstore/src/InMemoryS3Client.cpp
    - thirdparty/sgns-blockstore/test/in_memory_s3_client_test.cpp
  modified:
    - thirdparty/sgns-blockstore/src/CMakeLists.txt
    - thirdparty/sgns-blockstore/test/CMakeLists.txt
key-decisions:
  - "S3PutResult mirrors PutOutcome's two-field shape (achieved/alreadyPresent) so Phase-4 SC2 maps 1:1 with zero re-freeze (D-02)"
  - "Head authoritative miss = SUCCESS slot exists=false; Get authoritative miss = ERROR slot NotFound - decided at the interface, never re-derived per backend"
  - "Delete idempotent (missing key succeeds, S3 RemoveObject semantics); delete never climbs to BlockStore (D-03)"
  - "Fake faults map to taxonomy OUTCOMES (Remote source), not raw wire bytes - wire-level faults stay with LoopbackHttpStub against MinioS3Client (D-05/D-08 split)"
requirements-completed: [BACK-05]
duration: 20 min
completed: 2026-10-21T20:10:00Z
coverage:
  - deliverable: "Internal S3Client interface (4 ops + config, SDK-free, HTTP-free)"
    verification:
      - kind: command
        ref: "git grep SDK-include guard exits 1; token battery (createOnly/alreadyPresent/S3ClientConfig/tlsVerify/us-east-1); HTTP-ism literal check; no install rule references S3Client"
        status: pass
    human_judgment: false
  - deliverable: "InMemoryS3Client fake with createOnly enforcement + per-op faults"
    verification:
      - kind: tests
        ref: "inner-tree ctest#in_memory_s3_client_test (Passed, 12 cases, zero skips)"
        status: pass
      - kind: command
        ref: "cmake --build target sgns-blockstore (fake compiled into the lib)"
        status: pass
    human_judgment: false
  - deliverable: "No regression in prior suites with the new sources linked"
    verification:
      - kind: tests
        ref: "full 8-suite battery 100% passed (memory/local/crash/api_hygiene/cid_spike/minio_cpp_spike/in_memory_s3_client/header_hygiene)"
        status: pass
    human_judgment: false
---

# Phase 3 Plan 02: S3Client Interface + InMemoryS3Client Fake Summary

One-liner: the internal S3 adapter seam (put/get/head/delete + config) lands in src/ with the D-01/D-02/D-03/D-04 shapes exactly as locked, and the stateful per-op-fault-scriptable fake proves all of them hermetically (12 cases, zero skips).

Duration: 20 min | Tasks: 2 | Files: 6

## Accomplishments

- `src/S3Client.hpp` (internal, no install rule): `S3ClientConfig` (tlsVerify defaults TRUE per T-3-02; region pinned `us-east-1`), `PutObjectOptions{createOnly}` (D-01), `S3PutResult{achieved, alreadyPresent}` (D-02 mirror), `S3Object`, `S3HeadResult` (miss = success slot `exists=false`), `S3Op`/`S3FaultKind` enums, pure-virtual `Put/Get/Head/Delete`. All results via the Cid.hpp `result<R,S,policy::terminate>` alias; sync-blocking Phase-3 threading contract documented in the header; zero SDK types, zero HTTP-ism literals (verified by grep).
- `InMemoryS3Client` fake: stateful map; createOnly duplicate returns the SUCCESS slot `alreadyPresent=true` without writing; plain Put computes alreadyPresent pre-write; faults scripted per-op (`SetFault(S3Op, S3FaultKind)` / `ClearFaults()`, production-must-not-call notes) mapping to taxonomy outcomes with `BlockSource::Remote`.
- `in_memory_s3_client_test` (12 cases) green with zero skips; target links exactly `sgns-blockstore + p2p::p2p_cid`; all five anchor case names present verbatim; no outcome macros.
- Full 8-suite battery green (Phase-1/2 + 03-01 suites unaffected by the new library sources).

## Deviations from Plan

**[Rule 1 - build wiring detail] test target needs the src/ include path** — Found during: Task 2 | Issue: the internal headers are deliberately absent from every public include path (D-04), so the test TU's quoted includes failed | Fix: `target_include_directories(in_memory_s3_client_test PRIVATE ${CMAKE_SOURCE_DIR}/src)` with the test-surface-only-privilege comment (crash-suite precedent) | Files: test/CMakeLists.txt | Verification: suite builds and passes | Commit: 3af8dc9

Total deviations: 1 auto-fixed. **Impact:** none on frozen shapes; keeps D-04 intact.

## Issues Encountered

None.

## Authentication Gates

None.

## Commits

- sgns-blockstore: d1ca679 (feat interface + fake), 3af8dc9 (test suite)
- thirdparty: 540dfbd (pointer bump)
- root: 435233a (pointer bump)

## Self-Check: PASSED
