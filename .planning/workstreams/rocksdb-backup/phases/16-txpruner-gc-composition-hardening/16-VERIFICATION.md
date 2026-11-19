---
phase: 16-txpruner-gc-composition-hardening
status: passed_with_uat
verified: 2026-11-18
verifier: inline-executor (Copilot sequential mode)
requirements: [COMP-01, COMP-02, COMP-03]
---

# Phase 16 Verification Report

**Phase goal (ROADMAP):** concurrent TxPruner and GC passes proven safe on the gated, evidence-aware line — sequenced (never unified), with the stale-LRU erase window closed (SC1/COMP-01), the interleave matrix proven (SC2/COMP-02), and the GC-disposal starvation interplay ruled fail-safe (SC3/COMP-03).

## Method

Goal-backward check of the three plans' SUMMARYs against the codebase and the Tier-1 lane (run twice, green), plus the per-plan verification gates recorded in each SUMMARY (ordering probes, zero-diff windows, purity gates, red-first signatures).

## SC1 / COMP-01 — VERIFIED (automated)

- The post-commit `DeleteCIDBlock` sits strictly between the batch commit and the seal re-assert (`globaldb.cpp`, ordering probe commit=1666 < delete=1682 < seal=1690 at review time) — both committed exits covered, unconditional for every caller (D-04).
- Guard 3 and `RunHotCleanup`/A6 carry ZERO diff lines vs `af644481f` (probes returned 0 hunks).
- Proven red→green at both D-06 layers: W1 (deterministic, `SC1-STALE-SERVE` red signature captured pre-fix) and W2 (real-thread barrier); W3/W4 rule the abort-path and absent-key edges.
- Evidence: `cold_compose_matrix_test` legs W1-W4; commits `5f6ff19d9`, `88283905e`.

## SC2 / COMP-02 — VERIFIED (automated), with the recorded semantic re-scoping

- The matrix product exists and is green: M1-M8 (deterministic) + R1-R3 (races) over all shared surfaces (set rows, block bytes, LRU, seals, both marker namespaces, disposed markers).
- **Re-scoping (16-03 deviation #1, accepted):** literal one-fixed-point convergence is unattainable because two DESIGNED order-dependences intervene — the post-erase walk-gap abort (under-eviction) and the D-10 stranding. The proven contract: the order-INVARIANT projection converges (byte-level where constructively possible; class-state vectors elsewhere) + the explicit per-order divergence table. No idempotence-contract bug found (D-03 never triggered); no lock added (D-01 holds); seals survive every run (M7); re-runs change nothing (M8); crossfire key-identity holds (M5/M6).
- D-02's Interaction-C invariant race-tested in all three straddle orderings with last-copy survival asserted through the library remote read (R3).
- Evidence: commits `84391b372`, `741980f5d`; knobs `SGNS_COMPOSE_RACE_JITTER_SEED/_ITERS`.

## SC3 / COMP-03 — VERIFIED (deterministic automated; live leg loud-skipped → UAT)

- The D-10 consult chain (`GlobalDB::IsColdDisposed` → manager → library) rides the proven lock order; `PruneEligibility` zero-diff vs `af644481f`; the stranded counter surfaces as `cold_disposed_stranded={}`; only the NoRecord arm consults (S3c).
- Fail-safe direction asserted by test both ways: S3a (hermetic real disposal → stranded == 1, erased == 0, value survives; red-first `SC3-UNDIFFERENTIATED` captured against the consult-reverted line) and the live MinIO leg (D-11b).
- Rulings documented at both destructive homes + the workstream doc `notes/16-txpruner-gc-composition-rulings.md` (probe anchors all present).
- **Human item:** the Tier-3 live leg (real MinIO + real GC disposal → stranded cycle + remote fetchability) is env-gated and ran as its labelled loud skip in this environment — the deterministic stand-in (S3a) is the CI evidence; a developer run with `SGNS_BLOCKSTORE_TEST_MINIO_BIN` remains the live confirmation.

## Requirement traceability

| ID | Letter | Plans | Status |
|----|--------|-------|--------|
| COMP-01 | SC1 stale-LRU window closed | 16-01 | Complete (verified automated) |
| COMP-02 | SC2 interleave matrix | 16-03 | Complete (verified automated, re-scoped contract recorded) |
| COMP-03 | SC3 starvation fail-safe | 16-02 | Complete (deterministic verified; live leg → UAT) |

## Gaps

None blocking. Registered deferred items (documented in the ruling doc + 16-02 SUMMARY): the coldstore handle leak after retention-GC shutdown (hardening; test-posture-only impact), TEST-03-style live MinIO confirmation (UAT), and the standing PollUntil sleep-count probe-letter deviation.

## human_verification

1. Live SC3 leg: with a MinIO COMMUNITY binary, run `cold_compose_live_smoke_test` (env `SGNS_BLOCKSTORE_TEST_MINIO_BIN`; runbook `thirdparty/sgns-blockstore/docs/testing-tiers.md`; one-time `mc mb compose-smoke/compose-smoke` on 127.0.0.1:19793) — expect: real disposal strands the cycle (`cold_disposed_stranded_groups == 1`, erased 0) and the disposed block's bytes answer from the remote.
