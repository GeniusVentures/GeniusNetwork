---
status: passed
phase: 03-minio-cpp-integration-s3client-adapter
source: [03-VERIFICATION.md]
started: 2026-10-21T21:05:00Z
updated: 2026-10-21T23:26:00Z
---

## Current Test

number: 1
name: Live MinIO tier run (SC4a — bring-your-own-binary)
expected: |
  Install a MinIO server binary locally (no auto-download by design), set
  SGNS_BLOCKSTORE_TEST_MINIO_BIN to its path, then run:
    ctest --test-dir thirdparty/build/Windows/Debug/sgns-blockstore/src/sgns-blockstore-build -C Debug -R "minio_s3_client_test|minio_cpp_spike_test" --output-on-failure -VV
  Expected: the three [SGNS_BLOCKSTORE][MINIO-TIER] live cases execute (not skip):
  LivePutGetHeadDeleteRoundtrip (full roundtrip incl. Delete over the wire),
  LiveCreateOnlyDuplicateReportsAlreadyPresent (real 412 -> success slot
  alreadyPresent=true), and minio_cpp_spike_test's EnvGatedTlsOnSmoke (TLS
  handshake + one op over a self-signed cert; needs a resolvable openssl —
  the superbuild's install tree is picked up automatically).
awaiting: nothing - G-3-1 CLOSED 2026-10-21 (user-approved option (a): OpenSSL::SSL TLS health probe); all four [SGNS_BLOCKSTORE][MINIO-TIER] live cases executed green

## Tests

### 1. Live MinIO tier run (SC4a)
expected: see Current Test above
result: pass
reported: "PASS (final state, 2026-10-21 resumption run): all four [SGNS_BLOCKSTORE][MINIO-TIER] live cases execute green against community MinIO RELEASE.2025-04-22T22-12-26Z (W:\gnus\minio-community.exe): LivePutGetHeadDeleteRoundtrip, LiveCreateOnlyDuplicateReportsAlreadyPresent, LiveTlsOffIsPrimaryLane (minio_s3_client_test 11/11) and EnvGatedTlsOnSmoke (1343 ms - TLS handshake + MakeBucket + PutObject over the in-process self-signed cert, only SGNS_BLOCKSTORE_TEST_MINIO_BIN set). Historical partial-pass entries preserved in diagnosis below (std::system() quoting bug -> in-process cert gen -> TLS-only health probe -> option (a) closure)."
severity: minor
diagnosis: |
  (1) ENVIRONMENT (resolved): W:\gnus\minio.exe = RELEASE.2026-09-19 AIStor - "No valid
      license found, running in offline mode. All S3 operations are denied." dl.min.io
      no longer serves community releases at all (HTTP 410, archived). Last AGPL binary
      fetched from GitHub releases: minio/minio RELEASE.2025-04-22T22-12-26Z windows-amd64
      -> W:\gnus\minio-community.exe. With it, every live case in minio_s3_client_test
      passes (full roundtrip incl. Delete, real 412 -> alreadyPresent=true, TLS-off lane).
  (2) CODE BUG (Windows-only, test harness): MinioServerHarness::GenerateSelfSignedCert
      invokes openssl via std::system() with a QUOTED binary path. UCRT _spawnlp re-quotes
      the command for cmd.exe; cmd /c first/last-quote stripping mangles the target so
      nothing executes -> exit 1, stderr hidden by the trailing 2>nul. Empirically pinned
      2026-10-21: a noop marker-dropping .cmd set as SGNS_BLOCKSTORE_TEST_OPENSSL_BIN never
      runs from the test exe, while the byte-identical cmd /c string succeeds from
      PowerShell. The TLS-on smoke therefore can NEVER run live on Windows as built.
      Secondary: ResolveOpenssl() superbuild fallback ../../../../../openssl/bin/openssl.exe
      is off by one level (resolves to build\Windows\openssl; the superbuild root is
      build\Windows\Debug) and no openssl.exe exists in the install tree on Windows anyway.
environment_notes: |
  Working invocation (from repo root):
    $env:SGNS_BLOCKSTORE_TEST_MINIO_BIN   = "W:\gnus\minio-community.exe"
    $env:SGNS_BLOCKSTORE_TEST_OPENSSL_BIN  = "C:\Strawberry\c\bin\openssl.exe"
    $env:OPENSSL_CONF                      = "W:\gnus\openssl-test-fixture.cnf"
      (Strawberry openssl 3.3.0 ships NO .cnf; `req` exits 1 without one;
       minimal config created at W:\gnus\openssl-test-fixture.cnf)
    ctest --test-dir thirdparty/build/Windows/Debug/sgns-blockstore/src/sgns-blockstore-build -C Debug -R "minio_s3_client_test|minio_cpp_spike_test" --output-on-failure -VV

### 2. Gap-closure live run (G-3-1, plan 03-04 Task 2)
expected: |
  With ONLY SGNS_BLOCKSTORE_TEST_MINIO_BIN=W:\gnus\minio-community.exe set
  (SGNS_BLOCKSTORE_TEST_OPENSSL_BIN and OPENSSL_CONF deliberately unset),
  EnvGatedTlsOnSmoke executes live (TLS handshake + MakeBucket + PutObject
  over the in-process self-signed cert) and minio_s3_client_test stays 11/11.
result: pass
reported: "PASS. With ONLY SGNS_BLOCKSTORE_TEST_MINIO_BIN=W:\gnus\minio-community.exe set (SGNS_BLOCKSTORE_TEST_OPENSSL_BIN and OPENSSL_CONF proven unset in-session: OPENSSL_BIN_TEST=False OPENSSL_CONF_TEST=False), EnvGatedTlsOnSmoke EXECUTED live and passed (1343 ms): MinioCppSpikeTest 4/4, minio_s3_client_test 11/11, 100% tests passed, 0 failed out of 2, zero skips. First-ever execution surfaced one test-body bug (fixed inline, Rule 1): the smoke created bucket 'spike-tls' while MakePutArgs targets the shared 'spike-bucket' fixture -> NoSuchBucket; now creates spike-bucket."
severity: minor
diagnosis: |
  PLAN WATCH-FOR #3 FIRED (03-04-PLAN.md Task 2 step 3). Direct run with
  child stderr visible shows the full MinIO banner:
    API: https://127.0.0.1:50267
  i.e. community RELEASE.2025-04-22T22-12-26Z serves TLS-ONLY on the API
  port when --certs-dir is configured - the plan's "both protocols on one
  port via first-byte sniffing" assumption is FALSIFIED for this release.
  WaitUntilHealthy sends a PLAINTEXT 'GET /minio/health/live HTTP/1.0' -
  against the TLS-only listener this can never yield ' 200 ', so the
  deadline expires and Start(tls=true) fails. The harness itself, the
  --certs-dir contract, and the cert bytes are all fine (server came up).
  Per the plan's binding instruction, NO pre-emptive code change was made
  to WaitUntilHealthy; stopped for replan.
  RESOLVED 2026-10-21 (USER DECISION, option (a)): TlsHealthExchange
  (OpenSSL::SSL, SSL_VERIFY_NONE mirroring IgnoreCertCheck(true))
  TLS-wraps the health exchange when tls=true; plaintext probe path
  unchanged. Live proof: EnvGatedTlsOnSmoke OK (1343 ms).
evidence: 03-04-live-run-evidence.log (full ctest -VV of BOTH runs - the blocked run AND the G-3-1 closure resumption run).

## Summary

total: 2
passed: 2
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

- gap_id: G-3-1
  truth: "EnvGatedTlsOnSmoke executes live (TLS handshake + one op over an in-process self-signed cert) when a MinIO binary is provided - nothing else set, on Windows"
  status: closed
  reason: "CLOSED 2026-10-21. Mechanism half: in-process cert generation (OpenSSL C API; no binary/env/config anywhere; hygiene gate exits 1). Execution half: user-approved option (a) added TlsHealthExchange (OpenSSL::SSL) so WaitUntilHealthy speaks TLS when the API port is TLS-only; plaintext path unchanged. Live proof with ONLY the MinIO gate set (OPENSSL_BIN_TEST=False, OPENSSL_CONF_TEST=False): EnvGatedTlsOnSmoke EXECUTED and passed (1343 ms), MinioCppSpikeTest 4/4, minio_s3_client_test 11/11, 100% tests passed 0 failed of 2, zero skips. One test-body bug surfaced on first live execution, fixed inline: bucket 'spike-tls' vs the shared 'spike-bucket' fixture (NoSuchBucket)."
  severity: minor
  test: 2
  artifacts:
    - thirdparty/sgns-blockstore/test/MinioServerHarness.cpp (in-process GenerateSelfSignedCert + TlsHealthExchange TLS readiness probe)
    - thirdparty/sgns-blockstore/test/CMakeLists.txt (OpenSSL::Crypto + OpenSSL::SSL on both harness targets)
    - thirdparty/sgns-blockstore/test/minio_cpp_spike_test.cpp (bucket-name fix on first live execution)
  missing: []
  fix_direction: |
    TASK 1 OF 03-04 IS DONE AND COMMITTED (sgns-blockstore 1ba0742 RED,
    639ccce GREEN; thirdparty 092e582; root 2942a17). Remaining decision
    (replan 03-04 or a small 03-05): make the readiness check TLS-capable
    when tls=true. Options: (a) link OpenSSL::SSL (superbuild has libssl;
    only OpenSSL::Crypto is linked today) and do SSL_connect + write/read
    in WaitUntilHealthy's probe - mirrors the raw-socket style; (b) probe
    with the already-linked minio-cpp client + IgnoreCertCheck(true) in a
    deadline-bounded retry; (c) any equivalent that keeps the TLS-off lane
    byte-identical. The 03-04 plan explicitly forbade doing this without a
    replan, so the choice is the planner's/user's.
    RESOLVED 2026-10-21: user chose option (a); executed and verified
    same day (sgns-blockstore b1240b0, thirdparty 957afe2, root 4e7ca95).
  fix_direction: |
    USER DECISION (2026-10-21): generate the self-signed cert IN-PROCESS via the
    OpenSSL C API instead of shelling out to openssl.exe. The test targets already
    link miniocpp::miniocpp whose static libminio is built against superbuild
    OpenSSL 3.0.x, so libcrypto is already on the final link line. Rewrite
    GenerateSelfSignedCert to use EVP_RSA_gen(2048) + X509 (programmatically built
    X509_NAME, X509V3_EXT_conf_nid for SAN "IP:127.0.0.1", X509_sign EVP_sha256)
    + PEM_write_bio_PrivateKey/PEM_write_bio_X509. DELETE ResolveOpenssl(),
    SGNS_BLOCKSTORE_TEST_OPENSSL_BIN handling, the PATH/superbuild fallbacks, and
    the std::system() invocation (kills the Windows quote-mangling bug by
    construction; also moots the OPENSSL_CONF problem - the C API needs no config
    file). CMake: add explicit find_package(OpenSSL REQUIRED) + OpenSSL::Crypto
    link on minio_cpp_spike_test and minio_s3_client_test (the two targets that
    compile MinioServerHarness.cpp) instead of relying on miniocpp's transitive
    surface. Keep SpawnChild for the MinIO server child itself (that path works -
    the live tier ran).
