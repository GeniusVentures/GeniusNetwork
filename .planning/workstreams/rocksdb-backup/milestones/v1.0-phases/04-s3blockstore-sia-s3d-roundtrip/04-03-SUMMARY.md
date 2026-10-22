---
phase: 04-s3blockstore-sia-s3d-roundtrip
plan: 03
subsystem: database
tags: [s3, minio, sia, s3d, e2e, cold-retrieval, evidence, c++]

requires:
  - phase: 04-s3blockstore-sia-s3d-roundtrip/04-01
    provides: S3BlockStore + UploadDrainer (the composition under live test)
  - phase: 04-s3blockstore-sia-s3d-roundtrip/04-02
    provides: spike-proven s3d semantics (412 shape 1, native HEAD absence) + the dev endpoint/bucket/env surface
provides:
  - s3_block_store_minio_test (S3D-01/SC3 opt-in MinIO-binary tier, executor-proven live)
  - s3d_roundtrip_e2e (S3D-02/SC4 two-run fresh-process E2E binary + committed two-run evidence)
  - The milestone's end-to-end story proven live: local Put -> journal -> drain -> s3d -> fresh-process CID-verified cold retrieval
affects: [Phase 5 fault matrix, future durability polling]

actuals:
  tokens: 9000
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Two-run fresh-process proof: one binary, two GTest cases, --gtest_filter per invocation - the process boundary IS the proof"
    - "Run-state handoff file: plain-text cid/key/size/timestamp/digest, env-provided path, zero shared state between runs"

key-files:
  created:
    - thirdparty/sgns-blockstore/test/s3_block_store_minio_test.cpp
    - thirdparty/sgns-blockstore/test/s3d_roundtrip_e2e.cpp
    - thirdparty/sgns-blockstore/docs/evidence/s3d-spike/e2e-stats-captures.txt
    - .planning/workstreams/rocksdb-backup/phases/04-s3blockstore-sia-s3d-roundtrip/04-03-live-run-evidence.log
  modified:
    - thirdparty/sgns-blockstore/test/CMakeLists.txt (two tier registrations)

key-decisions:
  - "MinIO tier proven live by the executor (binary precondition held): skip label ABSENT from the run output per the plan's negative gate"
  - "Run B constructs zero local state by construction (structural source gate: no LocalBlockStore token in the VerifyRun body)"
  - "E2E journal assertion stays Accepted-level only; flush/stats captures labeled observations, never durability claims (D-04)"

patterns-established:
  - "gsl::span parameter for hex helpers (libp2p sha256 returns std::array, vectors come from bytes - one span covers both)"

requirements-completed: [S3D-01, S3D-02]

coverage:
  - id: D1
    description: "MinIO-binary store roundtrip (S3D-01/SC3): four live cases green against the community binary - CID-verified roundtrip through two independent store/client pairs, conditional re-put alreadyPresent, derived-key Head observability, Has/GetSize with authoritative-absence false"
    requirement: S3D-01
    verification:
      - kind: integration
        ref: "ctest -R s3_block_store_minio_test with SGNS_BLOCKSTORE_TEST_MINIO_BIN=W:\\gnus\\minio-community.exe (Passed 2.87s, skip label ABSENT)"
        status: pass
      - kind: automated
        ref: "Unset-env lane loud-skip check + source token gates (all pass)"
        status: pass
  - id: D2
    description: "Two-run E2E instrument (S3D-02/SC4 mechanics): builds, loud-skips unset-env, source-clean of process tokens, VerifyRun structurally local-state-free (automated shape gate)"
    requirement: S3D-02
    verification:
      - kind: automated
        ref: "Task-2 gates: unset-env ctest skip label, forbidden-token scan, VerifyRun count==1 + no LocalBlockStore in body (all pass)"
        status: pass
  - id: D3
    description: "Live two-run E2E session (S3D-02/SC4 proof): run A and run B each PASSED as separate process invocations against dev-managed s3d v0.2.1; evidence log committed with both runs' output in order, run-state contents, s3d version banner; stats captures carry before/after-drain + after-flush bodies; ASCII throughout; secret scan clean over both files"
    requirement: S3D-02
    verification:
      - kind: e2e
        ref: "04-03-live-run-evidence.log: UploadRun PASSED + VerifyRun PASSED + IDENTITY_PROVEN_TWO_FRESH_PROCESSES verdict (runA_ok=True runB_ok=True verdict=True)"
        status: pass
      - kind: automated
        ref: "Log gates (tokens/order/BOM 61,61) + credential .Contains scan over log and captures (all clean)"
        status: pass

duration: 45min
completed: 2026-10-22
status: complete
---

# Phase 4 Plan 03: Live Tiers — MinIO Roundtrip + Two-Run s3d E2E Summary

**The milestone story proven live end to end: real MinioS3Client→S3BlockStore green against the MinIO binary, and local Put → drain → s3d → fresh-process CID-verified cold retrieval green as two genuinely separate processes with committed evidence.**

## Performance

- **Duration:** ~45 min (3 tasks)
- **Commits:** 3 (sgns-blockstore: dcbd917, f207437, ac0023f; root: 3f522c2)

## Accomplishments

- s3_block_store_minio_test: four live cases green against RELEASE.2025-04-22 community binary (roundtrip via two independent client pairs, live 412→alreadyPresent, derived-key Head at the real server, Has/GetSize)
- s3d_roundtrip_e2e: run A green (journal UploadedAccepted, pending empty, run-state written); run B green (zero local state, cold retrieval, digest-proven byte identity) — the IDENTITY_PROVEN_TWO_FRESH_PROCESSES verdict
- Evidence: 04-03-live-run-evidence.log (ASCII, both runs in order, run-state contents, version banner) + e2e-stats-captures.txt (before/after-drain, after-flush observations)
- All gates green: source tokens, forbidden process tokens, structural D-09 shape, encoding, credential scan

## Deviations from Plan

**[Rule 2 - Compile fix] libp2p sha256 returns std::array<uint8_t,32>** - Hex(vector&) rejected array digests | Fix: Hex(gsl::span<const uint8_t>) — one signature covers both

**[Rule 3 - Session tooling] s3d version banner captured via direct binary invocation** (`W:\gnus\s3d_windows_amd64\s3d.exe version` — located during the 04-02 session) rather than "via the dev's terminal" — same evidence, agent-executable

**Total deviations:** 2 (one Rule-2 compile fix, one Rule-3 capture path). **Impact:** none on plan truths.

## Issues Encountered

None - all gates green. (Process note: one verify-battery formatting mistake echoed credential values into the terminal transcript only — a definitive .Contains rescan proved both committed files clean; recorded here for transparency.)

## Next Phase Readiness

Phase 4 complete: SC1-hermetic, SC2-hermetic, SC3, SC4, SC5/S3D-03 all closed. Phase 5 (Fault Injection & Three-Tier Hardening) can plan against the full three-tier surface: fake, MinIO binary, and live s3d.
