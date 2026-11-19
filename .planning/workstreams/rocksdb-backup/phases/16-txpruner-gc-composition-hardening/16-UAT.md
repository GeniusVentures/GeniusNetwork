---
status: testing
phase: 16-txpruner-gc-composition-hardening
source: [16-VERIFICATION.md]
started: 2026-11-18T21:20:00Z
updated: 2026-11-18T21:20:00Z
---

## Current Test

number: 1
name: Live SC3 leg - real MinIO GC disposal strands the TxPruner cycle
expected: |
  With SGNS_BLOCKSTORE_TEST_MINIO_BIN set to a MinIO COMMUNITY binary
  (never the license-gated minio.exe) and the bucket compose-smoke
  created once (mc alias set compose-smoke http://127.0.0.1:19793
  minio-dev minio-dev-secret && mc mb --ignore-existing
  compose-smoke/compose-smoke), cold_compose_live_smoke_test runs LIVE:
  a real GC disposal over the wire, the disposed block's bytes still
  fetchable from the remote through the library remote read, and the
  subsequent TxPruner cycle (remote stopped) strands the group -
  stats.erased == 0, cold_disposed_stranded_groups == 1, the local
  value row survives, journal NoRecord preserved.
awaiting: user response

## Tests

### 1. Live SC3 leg - real MinIO GC disposal strands the TxPruner cycle
expected: See Current Test above.
result: [pending]

## Summary

total: 1
passed: 0
issues: 0
pending: 1
skipped: 0
blocked: 0

## Gaps
