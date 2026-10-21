---
phase: 03-minio-cpp-integration-s3client-adapter
verified: 2026-10-21
status: human_needed
score: "3/4 success criteria fully proven; 1 criterion proven on the in-phase lane with its designed opt-in half awaiting a human run"
requirements: BUILD-02, BUILD-03, BACK-05, BACK-06
human_verification:
  - "Live MinIO tier run (SC4a): install a MinIO server binary locally, set SGNS_BLOCKSTORE_TEST_MINIO_BIN, and run ctest -R 'minio_s3_client_test|minio_cpp_spike_test' -C Debug --output-on-failure -VV - exercises LivePutGetHeadDeleteRoundtrip (incl. Delete over the wire), LiveCreateOnlyDuplicateReportsAlreadyPresent (real 412), and the TLS-on smoke"
---

# Phase 3 Verification

**Goal:** S3 client capability exists behind an internal adapter — minio-cpp at the pinned upstream tag builds through the superbuild, and the adapter interface plus in-memory fake make S3 behavior testable hermetically.

**Method:** goal-backward check of every SC against the actual codebase + executed tests (evidence cited per item); requirement IDs cross-referenced against REQUIREMENTS.md (all four marked complete with traceability).

## Success Criteria

### SC1 — minio-cpp pinned tag, shaderc-style, builds via CommonTargets orchestration
**VERIFIED (proof lane; five-lane evidence per Q3 posture).**
- Pinned tags: `git describe` → `v1.0.0` (minio-cpp), `v1.16` (pugixml); upstream absolute URLs verified by `.gitmodules` grep (no fork, no relative GNUS form).
- Shaderc-style integration: short `BINARY_DIR mcb/src`, upstream `miniocpp-deps.cmake` ran AS-IS at configure time (cpp-httplib v0.53.1 + inih r58 cloned by upstream's own pins — zero GNUS forks, D-12); static artifact `minio.lib` + `miniocpp-config.cmake` installed (03-01 SUMMARY evidence).
- Statically linked, non-exported: PRIVATE `miniocpp::miniocpp` on the library; no install rule references any SDK piece.
- Build green on the Windows/MSVC Debug lane (the Q3-designated in-phase proof lane). The four non-Windows lanes are a recorded backstop truth (03-01 must_haves, Q3 resolution: per-lane build-log evidence from the existing five lanes) — follow-up evidence, not a phase blocker by design.

### SC2 — internal S3Client interface; no SDK type in any installed header
**VERIFIED.**
- Interface exists in `src/S3Client.hpp` (put/get/head/delete + `S3ClientConfig`), absent from every install rule (grep).
- Compile-time proof chain green: `api_hygiene_test` compiles every installed header + runs linking exactly `sgns-blockstore + p2p::p2p_cid` WITH the SDK and `MinioS3Client` compiled into the library; `header_hygiene` green (bans `minio` includes); `git grep '#include <(miniocpp|minio)/' -- include/` exits 1. All SDK namespace tokens in `src/` confined to `MinioS3Client.cpp` (grep guard).

### SC3 — InMemoryS3Client fake drives hermetic tests for every op incl. 200/404/error
**VERIFIED.**
- 12 cases green, zero skips, no env gate, no network includes, no sleeps: round trips, createOnly duplicate (success slot `alreadyPresent=true`, original bytes intact), overwrite, Get-missing NotFound, Head hit/miss, idempotent Delete, all three fault classes (NOT-NotFound asserted), no-sticky-negative-cache, per-op independence. Full 9-suite battery 100% on Windows/MSVC Debug.

### SC4 — MinioS3Client ops against a local endpoint; one-place mapping; never-NotFound
**VERIFIED (mapping half fully; live half wired, opt-in run pending).**
- One-place mapping: `MapMinioFailure` (anonymous namespace, Doxygen) classifies every SDK error string; precondition shapes return the D-02 success slot BEFORE the mapper; grep-proven single classification point.
- Never-NotFound: proven per wire shape — connection-refused, bare-500, truncated-body, and garbage responses each assert `TemporarilyUnavailable` AND explicitly NOT `NotFound` through the real adapter (D-08 matrix, 8 cases green in the default CI lane); 404 `NoSuchKey` XML is the only NotFound.
- Local-endpoint ops: Put/Get/(Head via the plain-Put pre-check) exercised against the local loopback stub; the MinIO-binary tier (`LivePutGetHeadDeleteRoundtrip` — including Delete over the wire — and the real-412 duplicate) is wired, skips loudly per D-07/D-09, and awaits one bring-your-own-binary run (human-verification item above). This opt-in posture is the designed SC4a evidence plan (D-06/D-07, Q3).

## Requirements Traceability

| ID | Description | Status | Evidence |
|----|-------------|--------|----------|
| BUILD-02 | minio-cpp @ upstream tag, shaderc-style, own dep mechanism, static, non-exported, no fork | complete | SC1 + Q1 amendment recorded in CommonTargets comments |
| BUILD-03 | sgns-blockstore + minio-cpp wired into CommonTargets ExternalProject orchestration | complete | wiring guards green; TESTING-last rule intact; consumer-side resolution chain documented |
| BACK-05 | internal S3Client interface + InMemoryS3Client fake | complete | SC2/SC3; 12/12 hermetic cases |
| BACK-06 | MinioS3Client via minio-cpp; SDK types never leak | complete | SC2 confinement chain + SC4 mapping |

## Verdict

Phase goal achieved on the in-phase proof lane. One human-verification item remains (the opt-in live MinIO run — by design, D-07); the four non-Windows lane builds remain recorded backstop evidence per the Q3 resolution. Phase completion is handled by verify-work after the UAT item passes or is consciously accepted.
