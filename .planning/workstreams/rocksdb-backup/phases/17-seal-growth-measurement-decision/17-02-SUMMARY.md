---
phase: 17-seal-growth-measurement-decision
plan: 02
subsystem: crdt/cold-storage
tags: [seal-growth, fidelity, density, big-legs, evidence-trio, tier1]
key-files:
  modified:
    - SuperGenius/test/src/crdt/cold_seal_growth_test.cpp
  created:
    - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-seal-growth-evidence/seal_growth_evidence.json
    - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-seal-growth-evidence/seal_growth_table.md
    - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-seal-growth-evidence/README.md
    - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-seal-growth-evidence/run-capture.md
metrics:
  identity_equal: true
  seal_keys_compared: 242
  warm_10e7_rows_per_sec: 6250308
  reopen_cold_10e7_rows_per_sec: 5227098
  extrapolated_10e8_bytes: 5.2e9
  extrapolated_10e8_enum_wall_ms: 15999
  spot_check_deviation_pct: -9.06
---

# Plan 17-02 Summary: Fidelity + Density + Big Legs + Committed Evidence Trio

## What Was Built

SC1's full measurement surface on the 17-01 harness:

- **Spectrum generator (D-05)**: knobbed (`SGNS_SEAL_DEPTH/64`, `SGNS_SEAL_FANOUT/8`, `SGNS_SEAL_MIX/50`) three-shape DAG fixtures — deep (64 nodes, depth 63), wide (73 = 1+8+64, depth 2, breadth 8), mixed (41 = root + 32-chain + 8-fan, depth 32) — deterministic from the seed, exact ancestry by construction (the Pitfall-7 denominator), per-node generation tags.
- **Fidelity leg (D-04)**: a real GlobalDB-stack CRDT chain (64 real-topic puts → DAG jobs → `UpdateCRDTHeads` → `markResolved` → vendored seal) driven through the **public walk surface** (`RequestForcedWalk` + `GetForcedWalkStatus` poll — the evidence-matrix drive idiom): walk **Completed, visited=64, skipped_existing=64, zero errors/gaps**. The three shape CID sets seeded through the syncer's public `markResolved` (the W3 ghost-CID surface). Twin minimal-stack store seeded via vendored `seal()`. **Byte-identity proven: 242 = 242 key sets identical, all values empty** — direct volume seeding is admissible evidence.
- **Density legs (D-06)**: 3 shapes × 3 fractions (¼/½/1) matrix — writes ONLY through `PruneEligibility::WritePrunedBlockEntryForTest`, reads ONLY through `LookupPrunedBlockEntry` (tri-state + record round-trip: tx hash + erased-at generation — every cell `roundtrip_ok: true`); density == fraction within rounding slack, never > 1. Shared-CF context row on the populated fixture: **8 seals vs 211 non-seal rows**.
- **Big legs (D-01/D-02/D-03, dev-gated)**: `SGNS_SEAL_BIG_ENABLE` gates with a loud labelled skip (lane runtime unchanged — proven). The persistent grow root seeded 10⁶ then grown **in place** to 10⁷; warm + cold(`fill_cache=false`) + fresh-**reopen** (cold point of record) enumeration at both scale points; variance (max-dev + CV) recorded; **10⁸ extrapolated** from per-row bytes + the 10⁷ rate + the measured increment rate — every 10⁸ entry flagged `extrapolated: true`, seeding-rate spot-check **−9.06%**.
- **Committed evidence trio (D-09)**: `17-seal-growth-evidence/` — nested `seal_growth_evidence.json` (real booleans for the extrapolation flags), rendered `seal_growth_table.md`, `README.md` runbook (binary/build/working-dir/env-NAMES/reproduce/redaction), `run-capture.md` transcript. Redaction grep clean before commit.

## Canonical Numbers (committed JSON is the source of record)

| Point | Seals | Warm rows/sec | Cold (reopen) | Per-row B |
|---|---|---|---|---|
| 10⁶ floor (Tier-1) | 1,000,000 | 6,797,531 (max-dev 5.2%) | — | 52.000 |
| 10⁶ grow point | 1,000,000 | 7,254,963 (CV 3.4%) | 7,839,226 (fill_cache=false) | 52.000 |
| 10⁷ grow point | 10,000,000 | 6,250,308 (CV 16.2%) | **5,227,098** | 52.000 |
| 10⁸ — EXTRAPOLATED | 100,000,000 | 6,250,308 (basis) | — | 52.000 |

10⁸: ≈5.2 GB total, ≈16.0 s full sweep, ≈767 s seeding. Seeding rates: 143k/s (floor) · 118k/s (grow→10⁶) · 130k/s (10⁶→10⁷).

## Commits

| Task | Commit | Description |
|---|---|---|
| 1 | `a93305eac` | test(17-02): DAG-spectrum generator + real-walk fidelity leg — seeded/walked seal byte-identity (D-04/D-05, SEAL-01) |
| 2 | `f6c9535f2` | test(17-02): /prune/blk ancestry-density spectrum legs via the one marker home (D-06, SEAL-01) |
| 3 | `84d87d462` | test(17-02): dev-gated growing-DB big legs + committed seal-growth evidence trio with JSON layer (D-01/D-02/D-03/D-09, SEAL-01) |
| 3 (root) | `705fc9d` | docs(17-02): committed seal-growth evidence trio (JSON + table + runbook + capture) |

## Verification Evidence

- Suite green ungated (floor + fidelity + density + loud big-leg skip naming `SGNS_SEAL_BIG_ENABLE`); gated run: **4/4 PASSED**.
- Full Tier-1 lane: **17/17 green** after the flake fixes below.
- JSON gates: `$j.leg.volume_10e7.enum_warm.rows_per_s` ✓, `leg.fidelity`/`leg.density`/`options` ✓, 10⁸ member with `extrapolated: true` ✓; README gate 7 ≥ 3 ✓; redaction 0 hits ✓.
- Source gates: no concatenated `/prune/*` keys; no suffix-append; no deletion/compaction; production no-touch diff vs `741980f5d` exit 0.

## Deviations from Plan

**[Rule 1 - API-shape] `KeyPairFileStorage` requires a nonexistent FILE path** — a pre-created directory sends it down the load path against a directory. Fix: key file inside the wiped dir. Commit `a93305eac`.

**[Rule 1 - namespace] `PruneEligibility` lives in `sgns`, not `sgns::transaction`** — compile fix. Commit `f6c9535f2`.

**[Rule 1 - formula bug] 10⁸ spot-check used the enumeration rate instead of the seeding rate** (3630% deviation was the tell) — fixed to the phase-1 seeding-rate prediction; grow dataset regenerated once for the canonical run (README documents regeneration as an operator act). Commit `84d87d462`.

**[Rule 1 - assertion generalization] Floor-leg grow-root assert "empty → untouched-snapshot"** — 17-02's big legs legitimately populate the persistent root; 17-01's emptiness form was only correct pre-17-02. The untouched-by-this-leg contract is preserved via before/after listing comparison. Commit `84d87d462`.

**[Rule 4 - user-approved] Phase-16 `cold_compose_matrix_test` flake fixes** — during Task 3's lane verify the suite flaked ~30-50% (rotating legs, unchanged binary). User-directed investigation: **M3** between-halves fire budget 4→32 (hook fires per eviction; budget must outlast non-overlap evictions); **R3(a)** pragmatic re-scope (the state hook only covers `GlobalDB::GetColdUploadState` — the erase's guard — never the GC's mark-time journal read; the variant now pins the mechanically-guaranteed half: erase defers COLD_NOT_DURABLE + value row survives). Standalone commit `f758356fe` (not part of 17-02's scoped files). Post-fix: compose 8/8 green, full lane 17/17.

**Topology ruling (recorded per plan)**: fidelity = datastore-level walk drive for the chain + W3 syncer-alias for the shape sets — recorded in `leg.fidelity.topology` and the run capture.

**Total deviations:** 5 auto-fixed + 1 user-approved cross-plan fix. **Impact:** none on evidence contracts — all numbers on record are from the final canonical gated run.

## Self-Check: PASSED

- All tasks executed and committed; SUMMARY created; tracking updated by the orchestrator close-out.
- Acceptance criteria re-verified: loud skips ungated; committed JSON complete + parseable + extrapolation-flagged; 10⁸ math checkable from the JSON alone; README/runbook + capture committed, redaction clean; zero production diff.
