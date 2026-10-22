---
phase: 03-minio-cpp-integration-s3client-adapter
reviewed: 2026-10-21
depth: standard
files: 10
status: complete
findings:
  critical: 0
  warning: 2
  info: 4
---

# Phase 3 Code Review

**Scope:** source files changed across 03-01/03-02/03-03 (inline reviewer, Copilot sequential mode; standard depth).

**Files reviewed:** CommonTargets.cmake, build/cmake/FindZLIB.cmake, sgns-blockstore/{CMakeLists.txt, src/CMakeLists.txt, test/CMakeLists.txt}, src/{S3Client.hpp, InMemoryS3Client.hpp/.cpp, MinioS3Client.hpp/.cpp}, test/{LoopbackHttpStub.hpp/.cpp, MinioServerHarness.hpp/.cpp, minio_cpp_spike_test.cpp, in_memory_s3_client_test.cpp, minio_s3_client_test.cpp, api_hygiene_test.cpp}.

## Findings

### W-1 — Uncaught `std::stoul` on garbage `Content-Length` (test utility crash vector)
**Severity:** Warning | **File:** test/LoopbackHttpStub.cpp (ReadFullRequest)
A malformed request carrying `Content-Length: <non-numeric>` would throw out of the stub's accept-loop thread and terminate the test process — precisely the hostile input class the stub exists to serve.
**Status: FIXED (this review).** Defensive try/catch added; garbage parses as 0. Rebuilt; full 9-suite battery green.

### W-2 — `volatile bool stop_requested_` without atomic (technically a data race)
**Severity:** Warning | **File:** test/LoopbackHttpStub.hpp
Written by Stop() (test thread), read by the accept loop. Benign in practice (the listen-socket close is the real wake mechanism), but `std::atomic<bool>` is the correct spelling.
**Status: open** (test-only; no observed misbehavior — the socket close unblocks accept deterministically).

### I-1 — `faults_` array size hardcoded to 4
**Severity:** Info | **File:** src/InMemoryS3Client.hpp
`std::array<S3FaultKind, 4>` silently depends on S3Op's member count. A `static_assert` tying them would prevent drift.
**Status: open** (maintainability note; enum frozen for the phase).

### I-2 — `WSAStartup` without matching `WSACleanup` in the health-poll loop
**Severity:** Info | **File:** test/MinioServerHarness.cpp
Each poll iteration calls WSAStartup; reference-counted, never released. Benign for a short-lived test process.
**Status: open** (test-only lifetime).

### I-3 — `std::system`-based openssl invocation with interpolated paths
**Severity:** Info | **File:** test/MinioServerHarness.cpp (GenerateSelfSignedCert)
Paths from env vars are quoted but a path containing a quote could inject shell text. Local dev-box, bring-your-own-binary tier only.
**Status: open** (accepted risk per D-09 trust model: the env var is set by the developer themselves).

### I-4 — Plain-Put alreadyPresent read-before-write is TOCTOU under concurrent callers
**Severity:** Info | **File:** src/MinioS3Client.cpp (Put)
The pre-Head + Put pair is not atomic; the seam's documented single-threaded Phase-3 contract covers this, and Phase-4 S3BlockStore uses createOnly (atomic via 412).
**Status: open** (documented contract; revisit if the seam ever goes concurrent).

## Security Notes

- T-3-01 (per-run creds): generated via `std::random_device`, ≥8 chars, env-only transport, never logged — verified.
- T-3-02 (TLS posture): `tlsVerify` defaults true; `IgnoreCertCheck(!tlsVerify)` is the sole control path, called exactly once — verified.
- T-3-03 (message composition): `MapMinioFailure` concatenates only SDK response text + op name; no config field enters any message — verified.
- T-3-05 (stub bind): `INADDR_LOOPBACK` only; `0.0.0.0` appears nowhere in stub sources — verified by grep.

## Verdict

No Critical findings. The adapter's containment guarantees (one-TU SDK confinement, never-NotFound default, install-rule absence) all re-verified during review. Advisory only — does not block phase completion.
