---
phase: 04-s3blockstore-sia-s3d-roundtrip
verified: 2026-10-22T19:30:00Z
status: passed
score: 5/5 success criteria verified
covered_files:
  - .planning/workstreams/rocksdb-backup/phases/04-s3blockstore-sia-s3d-roundtrip/04-01-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/04-s3blockstore-sia-s3d-roundtrip/04-01-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/04-s3blockstore-sia-s3d-roundtrip/04-02-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/04-s3blockstore-sia-s3d-roundtrip/04-02-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/04-s3blockstore-sia-s3d-roundtrip/04-03-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/04-s3blockstore-sia-s3d-roundtrip/04-03-SUMMARY.md
---

# Phase 4 Verification: S3BlockStore & Sia s3d Roundtrip

**Verified:** 2026-10-22 (inline verifier, Copilot runtime)
**Goal:** The terminal cold-storage tier ships — S3BlockStore composed over the adapter with the codec-preserving key layout and conditional writes, accepted end-to-end against real MinIO (opt-in) and live Sia s3d (dev-gated), with s3d's staged-vs-durable semantics characterized.
**Result: VERIFIED — all 5 success criteria TRUE on committed evidence.**

## Success Criteria

### SC1 — Conformance kit green against S3BlockStore; v1/blocks layout observable ✅

- `s3_block_store_test` Passed (ctest, default CI lane): full Phase-1 kit over a fresh InMemoryS3Client per case — 16 cases OK + 9 designed fault-conformance skips (kit contract for non-FaultController backends).
- Key layout observable in the fake's key set: `KeyLayoutKnownVectorHelloWorld` pins `v1/blocks/raw/b9/bafkreifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e` (known vector, derived in-test AND literal-pinned).
- Fan-out proven digest-byte-derived (`FanoutComponentIsFirstDigestByteHex`, ≥2 distinct components).
- Commits: 40ab363, 8d4e4bc (sgns-blockstore).

### SC2 — Has/HEAD mapping + conditional create-only PUTs, 412 → AlreadyExists-as-success ✅

- Adapter level (Phase 3, still green in the 14/14 battery): `minio_s3_client_test` — three-shape 412 classifier, authoritative-absence Head.
- Store level: `HeadFaultIsTemporarilyUnavailableNeverAbsent` (never false/NotFound under unavailability), `GetSizeAndHasHeadMapping`, `RePutSameCidIsAlreadyPresentSingleObject`, `PutFaultPropagationAndNoStickyFailure`.
- Live: `ConditionalRePutIdempotent` green against the real MinIO binary; at s3d v0.2.1 the 412 renders as mapper shape 1 and is absorbed to `alreadyPresent=true` (sdk-error-shapes.txt).

### SC3 — Opt-in MinIO-binary roundtrip: Put → Get → CID-verify ✅

- `s3_block_store_minio_test` executed LIVE with `SGNS_BLOCKSTORE_TEST_MINIO_BIN=W:\gnus\minio-community.exe`: Passed 2.87s, **skip label ABSENT from output** (the plan's negative gate). Roundtrip goes through TWO independently constructed store/client pairs (no caching shortcut); derived-key Head observability at the real server. Unset-env lane loud-skips (CI-safe).
- Commit: dcbd917.

### SC4 — Dev-gated live s3d E2E, fresh-instance CID-verified retrieval, committed evidence, never CI ✅

- Two fresh process invocations (run A `--gtest_filter=S3dE2E.UploadRun`, run B `--gtest_filter=S3dE2E.VerifyRun`) both PASSED against dev-managed s3d v0.2.1; run B constructed zero local state (structural source gate) and proved digest-level byte identity.
- Evidence committed: `04-03-live-run-evidence.log` (ASCII, both runs in order, run-state contents, version banner) + `e2e-stats-captures.txt`; credential scan clean over both.
- Never CI: unset-env lane loud-skips `[SGNS_BLOCKSTORE][S3D-TIER]` (proven for both s3d-tier binaries in the 14/14 battery).
- Commits: f207437, ac0023f, 3f522c2.

### SC5 — s3d staged-vs-durable characterized with a documented finding ✅

- `docs/s3d-durability.md`: six-section characterization from the pinned tag's openapi.yml + five committed live artifacts; **finding: no per-object durability signal at v0.2.1** (pipeline-global counters, transient activeUploads) → accepted-is-max-provable IS the documented fallback; blocking `/objects/flush` documented as the staged-to-durable primitive. All 7 evidence citations resolve on disk (automated check).
- `Durability.hpp` ObjectStoreAccepted cites the finding (D-12); hygiene guards green post-edit.
- D-05 contingency not needed (HEAD-missing classifies natively). Commits: 43ee95d, a1c2cc9, 950356c.

## Regression Gate

Full battery **14/14 passed** on the final tree (CI lane): all Phase 1-3 suites + the five new Phase-4 targets. Zero regressions.

## Requirements

BACK-07, S3D-01, S3D-02, S3D-03 — all marked Complete (REQUIREMENTS.md).

## Deviations Ledger (from plan SUMMARIES)

04-01: 6 (2 Rule-2 include/member-name fixes, 4 Rule-3 test-shape/verify adjustments — all truths pinned).
04-02: 4 (Rule-3 environment adaptations: S3-API bucket creation via mc, mc-debug staged reads, host:port split, ASCII conversion).
04-03: 2 (Rule-2 span compile fix, Rule-3 capture path).
None weaken any success criterion.

## Human Verification Items

None pending — both live sessions (spike, E2E) executed in-session with committed evidence; the MinIO tier was executor-proven live. No UAT deferrals (contrast: Phase 3's live-tier UAT).
