---
phase: 11-retention-gc-of-cold-eligible-crdt-data
plan: "04"
subsystem: database
tags: [s3d, sia, minio, live-e2e, garbage-collection, evidence, testing]

requires:
  - phase: 11-retention-gc-of-cold-eligible-crdt-data
    provides: "11-01..11-03's full GC vertical (timestamps, eviction primitive, retrievability) whose live behavior this plan evidences"
  - phase: 04-s3-blockstore-sia-s3d-roundtrip
    provides: "the v1.0 Tier-2/3 live-tier contract (env-gated loud skips, two-run E2E shape, evidence-commit discipline)"
provides:
  - s3d_gc_e2e (Tier3): two-run spill -> flush-gated/ceiling Durable -> evict -> CID-verified retrieval against real s3d
  - gc_minio_roundtrip_test (Tier2): MinIO-binary opt-in GC roundtrip (hermetic admin semantics, A7)
  - docs/evidence/gc-e2e/: README runbook + run-capture.md (live run numbers) + stats-capture.txt (s3d console corroboration)
affects: [future funded-rent Sia-leg rerun]

actuals:
  tokens: 26000
  tasks: 3
  commits: 6

tech-stack:
  added: []
  patterns:
    - "Checkpoint-ruled ceiling mode (SGNS_BLOCKSTORE_TEST_S3D_SKIP_FLUSH_EVIDENCE=1): documented, capture-recorded degradation when the live backend cannot evidence the durability gate"
    - "Client read budgets actively cancel server-side finalize - long budgets required for Sia-leg proofs (diagnostic recorded for reruns)"

key-files:
  created:
    - thirdparty/sgns-blockstore/test/s3d_gc_e2e.cpp
    - thirdparty/sgns-blockstore/test/gc_minio_roundtrip_test.cpp
    - thirdparty/sgns-blockstore/docs/evidence/gc-e2e/README.md
    - thirdparty/sgns-blockstore/docs/evidence/gc-e2e/run-capture.md
    - thirdparty/sgns-blockstore/docs/evidence/gc-e2e/stats-capture.txt
  modified:
    - thirdparty/sgns-blockstore/test/CMakeLists.txt

key-decisions:
  - "Human checkpoint ruling: the flush-evidence ceiling mode - s3d's /objects/flush blocks on Sia slot progression (every finalize attempt logged 'context canceled'), so SGNS_BLOCKSTORE_TEST_S3D_SKIP_FLUSH_EVIDENCE=1 drives the durable marks directly and records the mode in the capture; the E2E's proven claim (evict + CID-verified retrieval against the real backend) is unaffected"
  - "Log-corroborated honesty: the retrieval was served from s3d LOCAL STAGING (no backend.sia GET lines; finalization never completed, waste 100%) - the S3-API vertical is proven live, the Sia-cloud durability leg is NOT claimed this session; rerun instructions committed"
  - "The s3d console's 30s 'context canceled' cadence == the E2E client's flush read budget: short client budgets actively cancel s3d's in-flight finalize - recorded as the diagnostic for funded-wallet reruns"
  - "A7 held: the MinIO roundtrip uses the InMemoryS3AdminClient for flush semantics (real MinIO has no s3d admin listener) while the S3 tier is the real community binary"

patterns-established:
  - "Evidence trio for live tiers: run capture (test output) + backend console capture (independent corroboration) + runbook (env NAMES only)"

requirements-completed: [TEST-03]

coverage:
  - id: D1
    description: "Live-tier tooling - both targets build, env-gated with loud labelled skips naming every missing var, registered Tier3/Tier2 (never Tier1), Tier-1 lane stays hermetic green"
    requirement: TEST-03
    verification:
      - kind: automated
        ref: "loud-skip runs green (env unset) + SuperGenius/library Tier-1 lanes 8/8 and 14/14 after registration"
        status: pass
  - id: D2
    description: "LIVE s3d GC E2E - 3 real uploads per run, eviction (local absent, marker present), CID-verified retrieval (sha-256 match), reclaimed 1/58B; ceiling mode recorded; numbers human-confirmed at the blocking checkpoint"
    requirement: TEST-03
    verification:
      - kind: e2e
        ref: "thirdparty/sgns-blockstore/test/s3d_gc_e2e.cpp#S3dGcE2E.SpillRun,#S3dGcE2E.EvictRun (live, 2/2 PASSED; capture committed)"
        status: pass
      - kind: manual_procedural
        ref: "docs/evidence/gc-e2e/stats-capture.txt - s3d console corroboration (upload groups 3/173B per run, finalize cancels, no GET lines)"
        status: pass
  - id: D3
    description: "Evidence artifacts + runbook committed with the redaction discipline"
    requirement: TEST-03
    verification:
      - kind: automated
        ref: "credential-value-shape grep over docs/evidence/gc-e2e/*.md and stats-capture.txt counts zero"
        status: pass
---

# Phase 11 Plan 04: Live s3d GC E2E + MinIO Opt-In Roundtrip (TEST-03) Summary

One-liner: the GC vertical proven against the real s3d backend — spill (real uploads), evict (local copy gone, marker present), retrieve (CID-verified digest match) — with the Sia-cloud ceiling honestly documented and corroborated by s3d's own console.

Duration: ~75 min (incl. the live session) | Tasks: 3/3 | Files: 6 (5 new)

## Accomplishments

- **Tier3 `s3d_gc_e2e`**: two-run shape (SpillRun: 3 blocks -> drain -> flush-evidence poll -> Durable; EvictRun: reopen same store, backdate, `EvictLocalAndMarkDisposed`, S3-tier GET digest-matched). Env-gated loud skips naming all six vars; ceiling mode per the checkpoint ruling.
- **Live run (human checkpoint)**: 2/2 PASSED in 10.3s — `blocks=3 reclaimed_count=1 reclaimed_bytes=58`, retrieval digest `af945662...` CID-verified, `verdict=SPILL_GC_RETRIEVE_PROVEN_LIVE`. Numbers confirmed by the operator.
- **Corroboration**: the s3d console (committed as stats-capture.txt) independently shows the upload groups (3 objects/173 bytes per run — matching our byte counts), the 30s/5s finalize-cancel cadence (== our client flush budgets), and zero GET lines (retrieval served from staging).
- **Tier2 `gc_minio_roundtrip_test`**: MinIO-binary opt-in roundtrip (A7: hermetic admin semantics), loud skip verified.
- **Evidence dir**: README runbook (env NAMES only, binary inventory, node-level operator section, artifact inventory, redaction rule) + run-capture.md + stats-capture.txt.

## Verification Evidence

- Live run green with capture block (not the skip line); loud skips green with env unset; Tier-1 lanes hermetic (SuperGenius 8/8, library 14/14) after registration; parity gate 8==8.
- Redaction: credential-value shapes = 0 across the evidence dir.

## Deviations from Plan

1. **[Rule 4 - checkpoint-ruled] Ceiling mode added** (`SGNS_BLOCKSTORE_TEST_S3D_SKIP_FLUSH_EVIDENCE=1`): the plan's flush-evidence poll dead-ends on unfunded rent (each `/objects/flush` blocks until canceled by the client budget — 900s observed). Per the operator's explicit ruling at the blocking checkpoint, the marks are driven directly and the mode is recorded in both captures.
2. **[Documented honesty] The Sia-cloud leg is unproven this session**: retrieval was served from s3d's local staging (log-corroborated). The committed claim is the S3-API vertical only; the Sia leg needs funded rent + a long flush budget (instructions in the capture).
3. **[Rule 2 - scope note] The MinIO Tier-2 live binary leg was not executed** (only the build + loud-skip path + registration verified; `SGNS_BLOCKSTORE_TEST_MINIO_BIN` never set this session). Available per the runbook.
4. **[Rule 2-lite] The ctest path runs both cases in one process** (each case still constructs a fresh `LocalBlockStore::Open` over the same dir); the strict two-fresh-process form is documented in the runbook and supported via `--gtest_filter`.

**Total deviations:** 1 checkpoint ruling + 3 documented notes. **Impact:** the evidence's claims are narrower than the plan's letter where the live backend couldn't support them — deliberately, and recorded in the artifacts themselves.

## Issues Encountered

None open. The 900s first attempt was the diagnostic that surfaced the flush-blocking behavior (root-caused via the s3d console, recorded for future reruns).

## Self-Check: PASSED

- All 3 tasks done: tooling committed (5591c39), live evidence committed (ee397fc), corroboration committed (3584f89); thirdparty bumps (b8b7219, c9dacfa, 3f955a1).
- Task-3 acceptance: live run exit 0 with capture block; artifacts committed; redaction zero; numbers human-confirmed.

## Next

Phase 11 complete — phase verification + close-out.
