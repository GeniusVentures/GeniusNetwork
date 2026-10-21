---
phase: 03-minio-cpp-integration-s3client-adapter
plan: 04
subsystem: sgns-blockstore/test (MinIO harness)
tags: [gap-closure, G-3-1, tls, openssl, test-harness]
requires: [03-01 MinioServerHarness + spike, 03-UAT G-3-1 binding fix direction]
provides:
  - "MinioServerHarness::GenerateSelfSignedCert — public static, in-process OpenSSL C API (no binary/env/config/subprocess)"
  - "SelfSignedCertGeneratedHermetically — hermetic per-platform cert-gen proof (default CI lane)"
  - "explicit OpenSSL::Crypto link on both harness-compiling test targets"
affects: [thirdparty/sgns-blockstore test targets only; TLS-off lane byte-identical]
tech-stack:
  added:
    - "OpenSSL 3.0 C API: EVP_RSA_gen, X509 v3 build, X509V3_EXT_conf_nid (SAN), X509_sign(EVP_sha256), PEM_write_bio_* (OpenSSL::Crypto)"
  patterns:
    - "in-process fixture generation instead of subprocess shelling (kills Windows UCRT/cmd quote mangling by construction)"
key-files:
  created: []
  modified:
    - thirdparty/sgns-blockstore/test/MinioServerHarness.cpp
    - thirdparty/sgns-blockstore/test/MinioServerHarness.hpp
    - thirdparty/sgns-blockstore/test/minio_cpp_spike_test.cpp
    - thirdparty/sgns-blockstore/test/CMakeLists.txt
key-decisions:
  - "GenerateSelfSignedCert exposed as public static on the harness (hermetic lane exercises cert generation with no MinIO binary; internal call sites unchanged)"
  - "Random positive serial from std::random_device bytes via ASN1_INTEGER_set_uint64 (no BIGNUM lifecycle); -300s notBefore clock-skew margin; 24h validity matching the old '-days 1' fixture"
  - "Explicit find_package(OpenSSL REQUIRED) + OpenSSL::Crypto on minio_cpp_spike_test AND minio_s3_client_test — never miniocpp's transitive surface (binding fix direction)"
  - "BLOCKING FINDING: community MinIO RELEASE.2025-04-22T22-12-26Z serves TLS-ONLY on the API port when --certs-dir is configured; the plan's first-byte-sniffing assumption is falsified, so WaitUntilHealthy's plaintext probe can never pass and Start(tls=true) times out. Stopped per the plan's watch-for #3 (no pre-emptive change to WaitUntilHealthy)."
requirements-completed: [] # BACK-06 stays open: EnvGatedTlsOnSmoke not yet executed live
duration: 16 min
completed: 2026-10-21T23:30:00Z
status: blocked
plan_head_before: 806e939e2e0b1a2f0ecb6f8da52ee1f0f1b39c46
plan_head_after: 2942a17
commits: 1
actuals:
  tokens: 4041      # chars/4 over thirdparty/sgns-blockstore e4b45e7..639ccce (16,163 chars)
  tasks: 1          # of 2 (Task 2 verification-only, blocked at watch-for #3)
  commits: 1        # root-repo commits (chore pointer bump); code commits live in sub-repos below
---

# Phase 03 Plan 04: In-process self-signed cert generation (G-3-1) Summary

**One-liner:** Cert generation rewritten in-process on the OpenSSL C API (binary machinery deleted, hygiene gate green, hermetic case passing on MSVC) — but the live TLS smoke remains blocked because this MinIO release serves TLS-only, so the harness's plaintext health probe times out (plan watch-for #3; replan required).

## What Was Completed

### Task 1 — COMPLETE (TDD)

**RED** (sgns-blockstore `1ba0742`): added
`MinioCppSpikeTest.SelfSignedCertGeneratedHermetically` asserting
`MinioServerHarness::GenerateSelfSignedCert(dir, &error)` → true + empty error +
`<dir>/private.key` ("-----BEGIN PRIVATE KEY-----") and `<dir>/public.crt`
("-----BEGIN CERTIFICATE-----"), non-empty, zero env/binary/network. Build failed
with the plan-directed compile RED:

```
minio_cpp_spike_test.cpp(224,5): error C2039: 'GenerateSelfSignedCert':
  is not a member of 'sgns::blockstore::testsupport::MinioServerHarness'
minio_cpp_spike_test.cpp(224,5): error C3861: 'GenerateSelfSignedCert':
  identifier not found
EXIT=1
```

(Compiled-language API-TDD: the named target test fails precisely because the
planned public static API is absent — not a syntax error, not an unrelated failure.)

**GREEN** (sgns-blockstore `639ccce`):
- `GenerateSelfSignedCert` public static on the harness: `EVP_RSA_gen(2048)`,
  X509 v3 (random positive serial, `X509_gmtime_adj(notBefore, -300)` skew margin,
  24h notAfter, CN=127.0.0.1 self-signed, SAN `IP:127.0.0.1` via
  `X509V3_EXT_conf_nid`, `X509_sign` SHA-256), `PEM_write_bio_PrivateKey` /
  `PEM_write_bio_X509` into `<certs_dir>/private.key` + `public.crt`. Every failure
  path frees its objects and composes `"cert generation failed: <reason>"`.
- DELETED: `ResolveOpenssl()`, `SGNS_BLOCKSTORE_TEST_OPENSSL_BIN` override,
  superbuild relative-path fallback, `std::system()` shell-out.
- `Start(tls=true)` branch: certs dir + generator; `--certs-dir` flag string
  byte-identical; SpawnChild/TerminateChild untouched.
- `test/CMakeLists.txt`: `find_package(OpenSSL REQUIRED)` +
  `OpenSSL::Crypto` on both targets compiling the harness.
- Hermetic lane (no env gates): both suites **Passed**;
  `SelfSignedCertGeneratedHermetically` **OK (694 ms)**; `EnvGatedTlsOnSmoke`
  skips loudly `[SGNS_BLOCKSTORE][MINIO-TIER] binary not provided`.

**Hygiene gate** (from inside the submodule, post-fix):

```
git -C thirdparty/sgns-blockstore grep -n -E 'SGNS_BLOCKSTORE_TEST_OPENSSL_BIN|
  ResolveOpenssl|std::system|openssl/bin/openssl|req -x509' --
  test/MinioServerHarness.cpp test/MinioServerHarness.hpp
GREP_EXIT=1   (no matches — machinery fully deleted)
```

**Build:** `cmake --build ...sgns-blockstore-build --target minio_cpp_spike_test
minio_s3_client_test --config Debug` → reconfigure OK, both exes linked, EXIT=0.

### Task 2 — BLOCKED at watch-for #3 (verification-only; no code changes made)

Live closure run with ONLY `SGNS_BLOCKSTORE_TEST_MINIO_BIN=W:\gnus\minio-community.exe`
set (`SGNS_BLOCKSTORE_TEST_OPENSSL_BIN` and `OPENSSL_CONF` explicitly removed;
`OPENSSL_BIN_TEST=False OPENSSL_CONF_TEST=False` confirmed in-run):

```
ctest -R "minio_cpp_spike_test|minio_s3_client_test" -C Debug --output-on-failure -VV
→ 100% tests passed, 0 tests failed out of 2
```

**Live evidence — minio_s3_client_test 11/11 (TLS-off primary lane unchanged):**

```
8: [ RUN      ] MinioS3ClientLiveTest.LivePutGetHeadDeleteRoundtrip
8: [       OK ] MinioS3ClientLiveTest.LivePutGetHeadDeleteRoundtrip (613 ms)
8: [ RUN      ] MinioS3ClientLiveTest.LiveCreateOnlyDuplicateReportsAlreadyPresent
8: [       OK ] MinioS3ClientLiveTest.LiveCreateOnlyDuplicateReportsAlreadyPresent (555 ms)
8: [ RUN      ] MinioS3ClientLiveTest.LiveTlsOffIsPrimaryLane
8: [       OK ] MinioS3ClientLiveTest.LiveTlsOffIsPrimaryLane (531 ms)
8: 2/2 Test #8: minio_s3_client_test .............   Passed   3.87 sec
```

**Live evidence — cert generation WORKS live, but the smoke cannot execute:**

```
6: [ RUN      ] MinioCppSpikeTest.EnvGatedTlsOnSmoke
6: [SGNS_BLOCKSTORE][MINIO-TIER] TLS fixture unavailable: MinIO did not become healthy within 30s
6: [  SKIPPED ] MinioCppSpikeTest.EnvGatedTlsOnSmoke (31036 ms)
```

Direct re-run with the child's stderr visible (diagnostic only, no code change):

```
MinIO Object Storage Server
Copyright: 2015-2026 MinIO, Inc.
Version: RELEASE.2025-04-22T22-12-26Z (go1.24.2 windows/amd64)
API: https://127.0.0.1:50267
WebUI: https://192.168.46.124:50269 https://127.0.0.1:50269
```

**Root cause:** MinIO loaded the in-process generated cert pair and brought its API
up on **TLS only**. This release does NOT serve plaintext HTTP on the TLS port (the
plan's first-byte-sniffing assumption is falsified), so `WaitUntilHealthy`'s
plaintext `GET /minio/health/live` can never yield ` 200 ` → `Start(tls=true)`
times out → the smoke skips loudly. The harness, the `--certs-dir` contract, and the
cert bytes are all fine — the server came up healthy on https.

Per the plan's binding step 3, NO pre-emptive change was made to `WaitUntilHealthy`;
stopped for replan. Full -VV log preserved at
`03-04-live-run-evidence.log` (phase dir).

## Commits (innermost-first)

| Repo | Commit | Message |
|------|--------|---------|
| thirdparty/sgns-blockstore | `1ba0742` | test(03-04): add failing hermetic cert-generation test for in-process API |
| thirdparty/sgns-blockstore | `639ccce` | feat(03-04): generate self-signed cert in-process via OpenSSL C API |
| thirdparty (root of sgns-blockstore) | `092e582` | chore(03-04): bump sgns-blockstore - in-process self-signed cert generation (G-3-1) |
| GeniusNetwork (root) | `2942a17` | chore(03-04): bump thirdparty - in-process cert generation; TLS smoke blocked on health probe (replan pending) |

## Deviations from Plan

None. The blocker is the plan's own pre-declared watch-for #3 (Task 2, step 3),
which mandates capture-and-stop rather than scope widening. No rules 1–4 fixes were
applicable: the failing component (`WaitUntilHealthy`) is exactly the one the plan
forbade touching without a replan.

## Threat Register

- **T-3-07 (low, mitigate) — applied:** per-run ephemeral RSA-2048 pair (EVP_RSA_gen
  CSPRNG), written only into the per-test temp dir `Stop()` removes; child-process
  exposure of the generation step eliminated (in-process now). No new surface beyond
  the plan's register.

## Remaining Work (replan input)

G-3-1 truth after this plan: cert generation needs **nothing but the library**; the
only blocker is the readiness probe. Options for the planner/user:

| Option | Change | Notes |
|--------|--------|-------|
| a | Link `OpenSSL::SSL` and make `WaitUntilHealthy`'s probe do `SSL_connect` + write/read when `tls=true` | mirrors existing raw-socket style; superbuild has libssl (only Crypto linked today) |
| b | Probe with the already-linked minio-cpp client + `IgnoreCertCheck(true)` in a deadline-bounded retry | no new link deps; heavier probe |
| c | Equivalent that keeps the TLS-off lane byte-identical | planner's discretion |

## Self-Check: PASSED

All 6 files FOUND; all 4 commits FOUND (1ba0742 + 639ccce in sgns-blockstore,
092e582 in thirdparty, 2942a17 in root).
