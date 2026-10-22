---
phase: 03-minio-cpp-integration-s3client-adapter
plan: 04
subsystem: sgns-blockstore/test (MinIO harness)
tags: [gap-closure, G-3-1, tls, openssl, test-harness]
requires: [03-01 MinioServerHarness + spike, 03-UAT G-3-1 binding fix direction]
provides:
  - "MinioServerHarness::GenerateSelfSignedCert — public static, in-process OpenSSL C API (no binary/env/config/subprocess)"
  - "SelfSignedCertGeneratedHermetically — hermetic per-platform cert-gen proof (default CI lane)"
  - "TLS-capable readiness probe (TlsHealthExchange, OpenSSL::SSL) — Start(tls=true) works against this release's TLS-only API listener"
  - "explicit OpenSSL::Crypto + OpenSSL::SSL links on both harness-compiling test targets"
affects: [thirdparty/sgns-blockstore test targets only; TLS-off lane byte-identical]
tech-stack:
  added:
    - "OpenSSL 3.0 C API: EVP_RSA_gen, X509 v3 build, X509V3_EXT_conf_nid (SAN), X509_sign(EVP_sha256), PEM_write_bio_* (OpenSSL::Crypto)"
    - "OpenSSL SSL API: TLS_client_method + SSL_connect/SSL_write/SSL_read readiness probe with SSL_VERIFY_NONE (OpenSSL::SSL)"
  patterns:
    - "in-process fixture generation instead of subprocess shelling (kills Windows UCRT/cmd quote mangling by construction)"
    - "probe speaking the protocol the server actually serves (TLS-only API port when --certs-dir is set)"
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
  - "USER DECISION (2026-10-21) option (a), recorded as an approved Task-2 amendment: TLS-wrap the readiness probe when tls=true — TlsHealthExchange over OpenSSL::SSL with SSL_VERIFY_NONE (mirrors IgnoreCertCheck(true)); plaintext probe path unchanged"
  - "First live execution of the smoke exposed a bucket-name mismatch (created 'spike-tls', MakePutArgs targets the shared 'spike-bucket' → NoSuchBucket) — Rule 1 inline fix: create spike-bucket"
requirements-completed: [BACK-06]
duration: 16 min + 40 min resumption
completed: 2026-10-21T23:26:00Z
status: complete
plan_head_before: 806e9396dc67faa4e9f29bdd047b06b4b38d6b93
plan_head_after: 4e7ca9527b3c23594d3d9d016508803186615363
commits: 3
actuals:
  tokens: 8800      # chars/4: session 1 measured 4041 over sgns-blockstore e4b45e7..639ccce + session 2 ~4750 over sgns-blockstore 639ccce..b1240b0 and the planning record edits
  tasks: 2          # of 2 (Task 2 spanned two sessions: blocked run + option-(a) resumption)
  commits: 3        # root-repo commits measured from the ledger (2942a17, f4ccbe1, 4e7ca95); code commits live in sub-repos below
---

# Phase 03 Plan 04: In-process self-signed cert generation (G-3-1) Summary

**One-liner:** G-3-1 closed — in-process cert generation (OpenSSL C API) plus a TLS-wrapped readiness probe (user-approved option (a)); EnvGatedTlsOnSmoke executed live and passed (1343 ms) with only the MinIO gate set, minio_s3_client_test 11/11, zero skips, hygiene gate green.

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

### Task 2 — COMPLETE (blocked session + option-(a) resumption)

**Session 1 (stopped at the plan's watch-for #3):** live closure run with
ONLY `SGNS_BLOCKSTORE_TEST_MINIO_BIN=W:\gnus\minio-community.exe`
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

Per the plan's binding step 3, NO pre-emptive change was made to
`WaitUntilHealthy`; stopped for replan. Session-1 -VV preserved in
`03-04-live-run-evidence.log` (phase dir).

**Session 2 (resumption — USER DECISION option (a), 2026-10-21):** the probe
now speaks the protocol the server actually serves. `TlsHealthExchange`
(OpenSSL::SSL; `TLS_client_method`, `SSL_set_fd`, `SSL_connect`,
`SSL_write`/`SSL_read`, `SSL_shutdown`, `SSL_free`, `SSL_CTX_free`;
`SSL_VERIFY_NONE` mirroring the client-side `IgnoreCertCheck(true)`
posture) wraps the SAME `GET /minio/health/live` + ` 200 ` check when
`tls=true`; the `(void)tls` cast is gone; the plaintext path is unchanged;
`OpenSSL::SSL` was linked beside `OpenSSL::Crypto` on both harness targets
(sgns-blockstore `b1240b0`). Amendment constraints honored: every
SSL/SSL_CTX handle freed on every path (the probe loops every 250 ms for
up to 30 s — no leaks), Ullman braces, PascalCase, Doxygen on the new
helper, no exceptions, loud-skip semantics untouched.

**Closure run (same gate posture — only the MinIO binary set,
`OPENSSL_BIN_TEST=False` / `OPENSSL_CONF_TEST=False`):**

```
6: [ RUN      ] MinioCppSpikeTest.EnvGatedTlsOnSmoke
6: [       OK ] MinioCppSpikeTest.EnvGatedTlsOnSmoke (1343 ms)
6: [  PASSED  ] 4 tests.
1/2 Test #6: minio_cpp_spike_test .............   Passed    2.35 sec
8: [  PASSED  ] 11 tests.
2/2 Test #8: minio_s3_client_test .............   Passed    3.79 sec
100% tests passed, 0 tests failed out of 2
CTEST_EXIT=0
```

`EnvGatedTlsOnSmoke` **EXECUTED** (an `[ OK ]` line, NOT `[  SKIPPED ]`):
TLS handshake + MakeBucket + PutObject over the in-process self-signed
cert with `IgnoreCertCheck`. Zero skips across both suites (binary gate
satisfied). Hygiene gate re-verified post-amendment: exits 1 (no matches).
Evidence appended to `03-04-live-run-evidence.log`.

## Commits (innermost-first)

| Repo | Commit | Message |
|------|--------|---------|
| thirdparty/sgns-blockstore | `1ba0742` | test(03-04): add failing hermetic cert-generation test for in-process API |
| thirdparty/sgns-blockstore | `639ccce` | feat(03-04): generate self-signed cert in-process via OpenSSL C API |
| thirdparty (root of sgns-blockstore) | `092e582` | chore(03-04): bump sgns-blockstore - in-process self-signed cert generation (G-3-1) |
| GeniusNetwork (root) | `2942a17` | chore(03-04): bump thirdparty - in-process cert generation; TLS smoke blocked on health probe (replan pending) |
| GeniusNetwork (root) | `f4ccbe1` | docs(03-04): session-1 blocked-state record (superseded by this summary) |
| thirdparty/sgns-blockstore | `b1240b0` | fix(03-04): TLS-wrap the readiness probe when the server runs TLS-on |
| thirdparty (root of sgns-blockstore) | `957afe2` | chore(03-04): bump sgns-blockstore - TLS health probe closes G-3-1 |
| GeniusNetwork (root) | `4e7ca95` | chore(03-04): bump thirdparty - TLS health probe; EnvGatedTlsOnSmoke green live (G-3-1 closed) |

## Deviations from Plan

### User-Approved Amendment (recorded, not scope creep)

**Option (a) — OpenSSL::SSL readiness probe** (approved 2026-10-21 after
session 1 stopped at the plan's watch-for #3). `WaitUntilHealthy` now
TLS-wraps the health exchange when `tls=true` (`TlsHealthExchange`);
plaintext path unchanged; `OpenSSL::SSL` linked on both harness targets.
All five amendment constraints from the decision were honored (TLS probe
semantics, byte-identical plaintext path, link wiring, coding standard +
RAII-style cleanup, unchanged loud-skip semantics).

### Auto-fixed Issues

**1. [Rule 1 - Bug] EnvGatedTlsOnSmoke bucket-name mismatch**
- **Found during:** Task 2 closure run — the smoke's first-ever live execution
- **Issue:** the test created bucket `spike-tls` via `harness.MakeBucket` but
  `PutObject` (via the shared `MakePutArgs`) targets the hardcoded
  `spike-bucket` fixture — the real server correctly returned `NoSuchBucket`
- **Fix:** the smoke now creates `spike-bucket` (the shared fixture name;
  the hermetic stub lane never enforces bucket existence, the real server
  does)
- **Files modified:** `thirdparty/sgns-blockstore/test/minio_cpp_spike_test.cpp`
- **Commit:** `b1240b0` (same commit as the approved amendment)

## Threat Register

- **T-3-07 (low, mitigate) — applied:** per-run ephemeral RSA-2048 pair (EVP_RSA_gen
  CSPRNG), written only into the per-test temp dir `Stop()` removes; child-process
  exposure of the generation step eliminated (in-process now). No new surface beyond
  the plan's register.
- **T-3-07 note (option (a)):** the TLS probe uses `SSL_VERIFY_NONE` against the
  loopback self-signed fixture — the same trust posture as the minio-cpp client's
  `IgnoreCertCheck(true)` (Q2); test-surface-only, no production code path.

## G-3-1 Disposition

**CLOSED.** The plan's truth — "EnvGatedTlsOnSmoke executes live (TLS handshake +
one op over a self-signed cert) when a MinIO binary is provided" — is restored
and strengthened: nothing but the MinIO binary gate is needed (no openssl binary,
no `OPENSSL_CONF`, no config file, no subprocess). BACK-06 live evidence complete;
see `03-UAT.md` (both tests pass, gap closed) and `03-04-live-run-evidence.log`.

## Self-Check: PASSED

All 7 files FOUND; all 8 commits FOUND (sgns-blockstore 1ba0742 + 639ccce + b1240b0;
thirdparty 092e582 + 957afe2; root 2942a17 + f4ccbe1 + 4e7ca95). Root commit count
from the plan ledger (806e939..4e7ca95) = 3, matching the frontmatter.
