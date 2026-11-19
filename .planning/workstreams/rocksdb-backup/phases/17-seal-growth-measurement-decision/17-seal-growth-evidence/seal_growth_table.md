# Seal Growth — Measured Evidence Table (SEAL-01 / SC1, v1.2 Phase 17 plans 17-01 + 17-02)

**Canonical run:** one gated process (`SGNS_SEAL_BIG_ENABLE=1`), 2026-11-19T04:57–04:58Z, host `MOFU`, windows, release build.
**Machine-readable source of record:** `seal_growth_evidence.json` (this directory). Every number below cites it; no prose-only numbers.
**RocksDB posture (all legs):** the seven production options (`options.*` in the JSON), WAL on.

## Volume + enumeration (D-01/D-02/D-03)

| Leg | Seals | Per-row bytes | Warm rows/sec | Warm max-dev / CV | Cold rows/sec | Wall (full sweep) |
|---|---|---|---|---|---|---|
| Floor (Tier-1, wiped root) | 1,000,000 | 52.000 | 6,797,531 | 5.24% / — | — | ~147 ms |
| Grow @ 10⁶ (persistent root) | 1,000,000 | 52.000 | 7,254,963 | 4.74% / 3.35% | 7,839,226 (fill_cache=false) | ~138 ms |
| Grow @ 10⁷ (grown in place) | 10,000,000 | 52.000 | 6,250,308 | 22.79% / 16.15% | 6,898,710 (fill_cache=false) · **5,227,098 (fresh reopen — cold point of record)** | 1,913 ms (reopen) |
| **10⁸ — EXTRAPOLATED** | 100,000,000 | 52.000 | 6,250,308 | — | — | **16.0 s (EXTRAPOLATED)** |

- Seeding rates: 143,313 seals/sec (floor, generation-inclusive) · 118,498/sec (grow to 10⁶) · 130,306/sec (10⁶→10⁷ increment).
- **10⁸ extrapolation (flagged, never presented as measured):** total bytes ≈ **5.2 GB**; full-sweep enumeration ≈ **16.0 s**; seeding time ≈ **767 s (~12.8 min)**. Derivation: per-row bytes × 10⁸; 10⁸ ÷ the slower 10⁷ warm rate (conservative); 10⁸ ÷ the measured increment rate. Seeding-rate spot-check: the 10⁶-rate prediction of the 10⁶→10⁷ increment deviates **−9.06%** from measured (the rate is near-flat in scale; the projection is anchored).
- Enumeration slows ~14% from 10⁶ to 10⁷ (7.25M → 6.25M rows/sec) — the dataset outgrows cache; the 10⁸ projection uses the 10⁷ rate.

## Fidelity (D-04) — direct seeding is admissible evidence

| Shape | Ancestry | Max depth | Max breadth | Byte-identity |
|---|---|---|---|---|
| deep | 64 | 63 | 1 | ✅ identical key sets, values empty |
| wide | 73 | 2 | 8 | ✅ |
| mixed | 41 | 32 | 9 | ✅ |

Real-walk chain: 64 puts → walk **Completed**, visited 64, skipped_existing 64, fetched/restored/walk_gaps/errors/deferred 0. Compared seal keys: **242 = 242, byte-identical** (walk-produced vs directly-seeded through the one vendored seal home). Topology: datastore-level drive + W3 syncer-alias for the shape sets.

## Ancestry density (D-05/D-06) — `/prune/blk` back-references across the spectrum

| Shape | 25% marked | 50% marked | 100% marked |
|---|---|---|---|
| deep (64) | 16 → 0.250 | 32 → 0.500 | 64 → 1.000 |
| wide (73) | 18 → 0.247 | 37 → 0.507 | 73 → 1.000 |
| mixed (41) | 10 → 0.244 | 21 → 0.512 | 41 → 1.000 |

All reads through `LookupPrunedBlockEntry` (tri-state + record round-trip: tx hash + erased-at generation — every cell `roundtrip_ok: true`). Shared-CF context on the populated fixture: **8 seals vs 211 non-seal rows** (CRDT + heads + markers).

## Tier-1 lane contract (D-07)

Floor leg asserts (CI, every run): seals == scale, others == 0, rows/sec ≥ 480,000 (measured/10), per-row bytes ∈ [46, 60] (mean ±8 clamped inside the [46, 90] shape envelope). Big legs skip loudly without `SGNS_SEAL_BIG_ENABLE`.
