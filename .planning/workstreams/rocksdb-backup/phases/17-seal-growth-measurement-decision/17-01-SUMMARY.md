---
phase: 17-seal-growth-measurement-decision
plan: 01
subsystem: crdt/cold-storage
tags: [seal-growth, probe-harness, tier1, rocksdb, evidence]
key-files:
  created:
    - SuperGenius/test/src/crdt/cold_seal_growth_test.cpp
  modified:
    - SuperGenius/test/src/crdt/CMakeLists.txt
metrics:
  seeded_seals: 1000000
  seeding_rate_per_sec: 137252.6
  warm_enum_rows_per_sec_mean: 4831882.2
  enum_max_deviation_pct: 0.447
  per_row_bytes_mean: 52.0
  derived_floor_rows_per_sec: 480000
  derived_bytes_band: "[46, 60]"
---

# Plan 17-01 Summary: Seal-Growth Probe Harness Core + Tier-1 Floor Leg

## What Was Built

The phase's measurement instrument (D-08): `cold_seal_growth_test` — a first-class env-knobbed gtest harness in `SuperGenius/test/src/crdt/` proving the whole measurement architecture end-to-end before any evidence leg lands (17-02) or any decision is recorded (17-03).

- **Minimal-stack hot store**: plain `storage::rocksdb` → vendored `IpfsRocksDb::create(getDB())` → vendored `RocksdbDatastore`, with the seven production RocksDB options from `globaldb.cpp:690-697` set verbatim — no GlobalDB, no node.
- **Sanctioned seal seeding (GATE-03/D-C1)**: N distinct content-addressed CIDs via `IPLDNodeImpl::createFromString` (ghost-CID precedent — bytes exist nowhere), each sealed ONLY through the vendored `seal()` surface. The seal-suffix literal appears in the harness exactly once — inside the enumeration suffix comparison (source-gated).
- **Raw-iterator suffix-filter enumeration (D-03 warm half)**: streaming `NewIterator` over `getDB()` (the wrapper's `query(prefix)` materializes a `std::map` and is never used), counting seal rows, non-seal shared-CF rows, per-row bytes, and rows/sec across `SGNS_SEAL_REPEATS` passes with max-deviation variance capture.
- **Flat JSON evidence (D-09)**: hand-rolled emitter (~90 lines, dotted-key pairs, string escaping) writing `evidence-floor.json` under the floor root and echoing to stdout beside the status lines — meta (host/os/build/utc/dataset fingerprint over seed+scale+first/last CID), the seven options, and every `leg.volume_10e6.*` number.
- **Tier-1 registration (D-07 wiring half)**: `cold_seal_growth_test` block copied from the `cold_compose_matrix_test` shape, inside `if(SGNS_COLD_STORAGE)`, `LABELS "Tier1"`, whole-archive triad intact.
- **Fixture roots (D-02 scope)**: `test-data/cold-seal-growth/floor` wiped before creation per run (Tier-1 determinism); `test-data/cold-seal-growth/grow` created empty, never wiped, asserted untouched by the floor leg (17-02's persistent growing dataset).
- **Env knobs (V5 integer-only posture)**: `SGNS_SEAL_SCALE` (1000000), `SGNS_SEAL_REPEATS` (3), `SGNS_SEAL_SEED` (20261118).

## Measured Numbers (SC1 evidence start — cited by 17-02/17-03)

| Metric | Measured (MOFU / windows / release, 2026-11-19) |
|---|---|
| Seeded seals | 1,000,000 (exact-count edge: seals == N, others == 0 — the PROBE-LIFT empty-intersection row) |
| Seeding wall / rate | 7,285.8 ms / 137,252.6 seals/sec (generation-inclusive — a conservative floor of the pure seal rate) |
| Warm enumeration | pass₁ 4,852,532 · pass₂ 4,832,849 · pass₃ 4,810,266 rows/sec; mean **4,831,882 rows/sec** (~207 ms/full-sweep) |
| Run-to-run variance | max deviation **0.447%** across 3 passes (D-12 band input) |
| Per-row bytes | **52.000** mean (52,000,000 B over 10⁶ rows — 46-char CIDv0 text key + 6-char suffix, empty value; A1 confirmed) |
| Derived Tier-1 floors (D-07) | rows/sec ≥ **480,000** (measured/10, rounded down); per-row bytes band **[46, 60]** (mean ±8 clamped inside [46, 90]) |

## Commits

| Task | Commit | Description |
|---|---|---|
| 1 | `0284d75c7` | feat(17-01): seal-growth probe harness core — sanctioned seeding, suffix enumeration, JSON evidence, Tier-1 registration (D-03/D-07/D-08/D-09, SEAL-01) |
| 2 | `4f0ff1731` | test(17-01): derive + assert Tier-1 seal floors (rows/sec, per-row bytes band) from measured 10^6 numbers (D-07, SEAL-01) — amended to carry the fourth floor assertion (mean-pass rows/sec) |

## Verification Evidence

- Incremental Release build: green (`cold_seal_growth_test.exe` produced; zero `error C`).
- `ctest -R cold_seal_growth_test`: **Passed 7.97s** at default 10⁶ scale with derived floors; `tier1_static_audit`: **Passed** (label parity + gating + soak containment all hold).
- `ctest -L Tier1 -N` lists `Test #116: cold_seal_growth_test`.
- Full Tier-1 lane: **17/17 passed** (16 cold suites + audit) — zero regression to the existing 15.
- Posture source gates: suffix-append pattern count 0; deletion/compaction call count 0; primitives count 11 (EnvOr/EnvSet/NewIterator/getDB).
- Production no-touch: `git -C SuperGenius diff --exit-code 741980f5d -- src` → exit 0.
- Grow root untouched: 0 entries after the floor leg.

## Deviations from Plan

**[Rule 1 - API-shape correction] `createFromString` returns `std::shared_ptr<IPLDNode>`, not `outcome::result`** — Found during: Task 1 | Issue: first compile failed (C2512/C2039) treating the return as a result type | Fix: `ASSERT_TRUE(node != nullptr)` + `node->getCID()` (the W3 precedent's own shape) | Files: cold_seal_growth_test.cpp | Verification: build green | Commit: `0284d75c7`

**[Rule 1 - acceptance-gate fix] Floor-assertion count initially 3 (< 4 gate)** — Found during: Task 2 | Issue: rows/sec floor + bytes band lower/upper = 3 `EXPECT_GE/LE`, tripping the vacuity gate | Fix: added the repeat-**mean** rows/sec floor assertion (semantically the right fourth bound), amended the not-yet-pushed task commit | Files: cold_seal_growth_test.cpp | Verification: count 4, suite green | Commit: `4f0ff1731`

**Total deviations:** 2 auto-fixed (API-shape, gate-fix). **Impact:** none on contracts — both are local to the harness and verified green.

## Self-Check: PASSED

- All tasks executed; each committed individually (SuperGenius submodule, innermost first).
- SUMMARY.md created in plan directory; STATE.md/ROADMAP.md updated by the orchestrator close-out.
- Acceptance criteria re-verified post-commit: header/knobs/defaults present; seven production options verbatim; sanctioned-only seeding; floor-root wipe + grow-root never-wipe asserts; seals==N/others==0/per-row band; registration inside `if(SGNS_COLD_STORAGE)` with Tier1 label + whole-archive triad; suffix-append and deletion gates zero; production diff zero.
