---
status: testing
phase: 03-minio-cpp-integration-s3client-adapter
source: [03-VERIFICATION.md]
started: 2026-10-21T21:05:00Z
updated: 2026-10-21T21:05:00Z
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
awaiting: user response

## Tests

### 1. Live MinIO tier run (SC4a)
expected: see Current Test above
result: [pending]

## Summary

total: 1
passed: 0
issues: 0
pending: 1
skipped: 0
blocked: 0

## Gaps
