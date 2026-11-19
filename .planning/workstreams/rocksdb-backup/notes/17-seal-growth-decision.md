# Seal-Growth Decision Record (v1.2 Phase 17)

**Ruled:** 2026-11-19
**Context commits:** SuperGenius `741980f5d` (Phase 16 close / the ruled anchor) → `0284d75c7`/`4f0ff1731` (17-01 harness + floors) → `a93305eac`/`f6c9535f2`/`84d87d462` (17-02 fidelity/density/big legs) on `dev_coldstorage_additions`; evidence trio committed at root `705fc9d`
**Requirements:** SEAL-01 (SC2 walk-bounds validation, SC3 decision record; SC1's measurement closed in 17-01/17-02)
**Decisions ruled here:** D-10, D-11, D-12, D-13 (17-CONTEXT); D-01/D-02/D-03/D-04/D-05/D-06/D-07/D-08/D-09 executed in 17-01/17-02 and recorded in their SUMMARYs

This is the workstream planning doc Phase 18's policy record and any future seal-redesign milestone cite by location. The committed machine-readable source of record for every number is `phases/17-seal-growth-measurement-decision/17-seal-growth-evidence/seal_growth_evidence.json` (keys cited inline below).

---

## (c) The D-12 tolerance-band derivation (recorded BEFORE the verdict — Pitfall 6)

**Variance inputs (committed JSON):**

| Leg | Statistic | Value | JSON key |
|---|---|---|---|
| 10⁶ floor (Tier-1) | warm max deviation | 5.239% | `leg.volume_10e6_floor.enum_max_deviation_pct` |
| 10⁶ grow point | warm max-dev / CV | 4.743% / 3.354% | `leg.volume_10e6.enum_warm.max_deviation_pct` / `.cv_pct` |
| 10⁷ grow point | warm max-dev / CV | 22.792% / 16.152% | `leg.volume_10e7.enum_warm.max_deviation_pct` / `.cv_pct` |

The largest measured repeat statistic is the 10⁷ warm CV of **16.152%** (dominated by the first pass's cache warm-up — passes 2-3 agree within ~1-2%).

**Band width = ±25%** — the larger of the measured variance (16.152%) and the recorded absolute slack of **25%**, whose rationale: cross-run/day-to-day spread of warm enumeration means observed on this hardware across the phase's runs (floor-leg means ranged ≈6.80M–7.25M rows/sec ≈ 6.5% day-to-day; the 10⁷ first-pass outlier reached 22.8% in-run). 25% subsumes both observed regimes with margin while staying far inside the envelope's structural 2× headroom (bound 8 vs healthy [1,4]).

**Comparison metric (the D-12 definition):** the probe's walk-recovery profile — per-spectrum-shape `ForcedWalkStatus` (visited/fetched/restored/skipped_pruned/walk_gaps/deferred/errors, `leg.fidelity.walk.*`) plus attempts-per-CID where the walk topology exposes them — compared against `kForcedWalkPeerFailoverPerCid = 8`'s derivation envelope: healthy attempts in [1,4], bound 8 with 2× headroom (the in-code derivation, `graphsync_dagsyncer.hpp:58-82`).

**Out-of-band means EITHER** (i) *bound-binding*: a healthy shape shows `walk_gaps > 0` attributable to per-CID budget exhaustion, **OR** (ii) *dead weight*: measured attempts sit so far below the envelope that the bound is demonstrably dead weight beyond the ±25% band.

**Symmetric reduced-observability clause (part of the metric definition):** the dead-weight (below-envelope) disjunct is reachable ONLY from comparison inputs that observed the bounded behavior — peer-failover attempts actually exercised in the measured walk topology. A below-envelope reading under a topology that could not exercise peer failover (17-02's hermetic datastore-level walk) is a topology artifact and records as **in-band-with-noted-limitation** — never as dead-weight evidence, and never an authorizer of the production edit. The bound-binding disjunct carries its own observability requirement (the walk-gap attribution). The clause binds both verdict branches symmetrically: an in-band verdict under reduced observability is likewise recorded as such.

## (d) SC2 verdict

**Verdict: VALIDATED — in-band, with noted limitation. No production touch.**

**Inputs (committed JSON keys):**

| Input | Value | JSON key |
|---|---|---|
| Walk state | Completed | `leg.fidelity.walk.state` |
| visited / skipped_existing | 64 / 64 | `leg.fidelity.walk.visited` / `.skipped_existing` |
| fetched / restored | 0 / 0 | `leg.fidelity.walk.fetched` / `.restored` |
| skipped_pruned / deferred / errors | 0 / 0 / 0 | `leg.fidelity.walk.skipped_pruned` / `.deferred` / `.errors` |
| **walk_gaps** | **0** | `leg.fidelity.walk.walk_gaps` |
| Topology | datastore-level (GlobalDB RequestForcedWalk) + W3 syncer-alias — hermetic, no peers | `leg.fidelity.topology` |
| Attempts-per-CID | not observable (zero recovery fetches occurred) | — |

**Comparison:** against the derivation envelope (healthy [1,4], bound 8, 2× headroom) through the ±25% band recorded in (c).

- *Bound-binding disjunct:* `walk_gaps = 0` across the walk and every shape — the per-CID budget was never approached, let alone exhausted. **Not triggered.**
- *Dead-weight disjunct:* the measured profile sits entirely at the zero-attempt point (`fetched = restored = 0`: a fully-retained hermetic ancestry exercises no recovery fetches and therefore zero peer-failover attempts). **Reduced observability:** the topology could not exercise peer failover, so the symmetric clause engages — the below-envelope reading is a **topology artifact**, recorded as **in-band-with-noted-limitation**, not dead-weight evidence. **Not triggered.**

**Noted limitation:** this verdict validates the bound's *non-interference* (the walk completes cleanly, zero gaps/errors/deferrals, at budget-free operation) but cannot speak to the bound's *tightness* — attempts-per-CID was unobservable under the hermetic datastore-level topology. The tightness question keeps its answer from the envelope's recorded sources (the in-code derivation and the develop-line 19-07 observations, cited in the Sources section); a peer-exercising topology leg is a natural addition for a future milestone that revisits the constant.

**Branch executed:** IN-BAND — `SuperGenius/src` carries **zero diff** vs the phase anchor `741980f5d` (the diff gate is this branch's evidence). The Phase 15 ↔ 17 derive-now/refine-later contract is closed with both halves honored: derived in Phase 15 (D-06), validated here against the probe's real walk-recovery numbers.

**Verdict date:** 2026-11-19. Chronology: band commit `de04874` precedes this verdict commit; no constant amendment follows (in-band branch).

---

## (a) The growth being accepted

The seal row is a **monotone, never-deleted text key** in the hot store's shared default column family: `<cid-string> + "sealed"`, empty value, written by the one vendored constructor (`RocksdbDatastore::seal`, GATE-03's single home) and retained by BOTH pruners (governing invariant 3 — verified end-to-end by Phase 16's interleave matrix). Growth is O(processed CIDs): every resolved walk node and every replaced head accumulates a row; no path deletes one.

Measured anatomy (committed JSON):

- **Per-row bytes: 52.000 at every scale point** (`leg.volume_10e6.per_row_bytes`, `leg.volume_10e7.per_row_bytes`) — a 46-char CIDv0 text key plus the 6-char suffix. The spectrum collapses to a point here: the row depends only on CID string length, and all three shapes (deep/wide/mixed) emit CIDv0 keys, so the D-13 uncertainty band on bytes/node is the Tier-1 shape band [46, 60] (`leg.volume_10e6_floor.derived_tier1_bytes_band`), not a shape spread.
- **Shared-CF posture:** seals share the default CF with block keys and CRDT rows — the density fixture's empirical mix measured **8 seals vs 211 non-seal rows** (`leg.density.shared_cf.*`); a maintenance sweep pays the FULL-CF suffix scan (Pitfall 1's finding — that cost is what the enumeration numbers measure).
- **Recovery-walk ancestry density** (the workload axis, D-05/D-06): measured across the spectrum from `/prune/blk` back-references at ¼/½/1 erase fractions — every cell exact and round-trip-verified (`leg.density.<shape>.frac_*.*`), so the density curve the capacity math interpolates over is on record.

## (b) The SC3 ruling — accept hot growth; redesign deferred to measured triggers

**ACCEPT.** The measured costs are small, flat, and far from any service-impact threshold on the recorded hardware fingerprint (MOFU / windows / release):

**Spectrum-band capacity math (D-13)** — representative mix with the deep/wide endpoints as the uncertainty band; the bytes axis collapses (see (a)), the cost axis carries the band:

| Scale | Seal bytes | Warm full-sweep | Cold (reopen) | Basis | JSON keys |
|---|---|---|---|---|---|
| 10⁶ | 52.0 MB (52.000 B × 10⁶) | ≈138–147 ms (7.25M rows/s) | 7.84M rows/s (fill_cache=false) | **measured** | `leg.volume_10e6.*` |
| 10⁷ | 520 MB | ≈1.6 s (6.25M rows/s) | **5.23M rows/s** (fresh reopen — the cold point of record) | **measured** | `leg.volume_10e7.*` |
| 10⁸ | **5.2 GB** | **≈16.0 s** | — | **EXTRAPOLATED** (flagged) | `leg.volume_10e8_extrapolated.*` |

Enumeration degrades ~14% from 10⁶ to 10⁷ (7.25M → 6.25M rows/s — the dataset outgrows cache; the 10⁸ projection uses the slower 10⁷ point, conservative). Seeding rates: 143k/s floor, 118k/s grow-to-10⁶, 130k/s 10⁶→10⁷ increment (`leg.volume_10e6_floor.seeding_rate_per_sec`, `leg.volume_10e6.grow_seed_rate_per_sec`, `leg.volume_10e7.grow_increment_rate_per_sec`); 10⁸ seeding ≈ 767 s EXTRAPOLATED with the spot-check anchored at **−9.06%** (`leg.volume_10e8_extrapolated.spot_check_deviation_pct`).

Even at 10⁸ CIDs — a scale no node in this milestone's envelope approaches — the entire seal keyspace costs ~5.2 GB and a full maintenance sweep ~16 s. The redesign machinery (spill/compaction/sidecar) would spend complexity and new failure modes on a problem this size does not have.

## D-11 numeric triggers ("demands it", operationalized)

Each trigger is checkable against the committed JSON alone (re-measure per the re-run instructions below, then compare):

| # | Trigger | Threshold | Cited key (measured value) | Derivation note |
|---|---|---|---|---|
| T1 | Per-row shape change | re-measured `per_row_bytes` outside **[46, 60]** | `leg.volume_10e7.per_row_bytes` = 52.000 | The committed Tier-1 band (mean ±8 clamped inside the [46, 90] envelope) — any exit is a CID-scheme or row-shape change, far outside the ±25% D-12 band |
| T2 | Enumeration service impact | warm 10⁷ full-sweep (10⁷ ÷ `enum_warm.rows_per_s`) exceeds **10 s** | `leg.volume_10e7.enum_warm.rows_per_s` = 6,250,308 (≈1.6 s measured) | ≈6× measured — beyond the 22.8% worst in-run deviation AND the day-to-day spread; a real regression, not variance |
| T3 | Bytes share at scale | extrapolated 10⁸ `total_bytes` exceeds **20 GB** | `leg.volume_10e8_extrapolated.total_bytes` = 5.2×10⁹ | ≈4× the measured-shape projection — reachable only by a row-shape or CID-scheme change (T1's territory at scale); crossing it re-opens the redesign question with a material number |

## Options considered and rejected

| Option | Verdict | Why |
|---|---|---|
| **Accept hot growth** (status quo: seals stay in the shared CF, read/count/time only) | **ACCEPTED (this ruling)** | Measured costs flat and small (above); zero new dependencies; invariant 3 untouched. |
| **Seal spill to cold storage** | **Rejected — deferred to triggers** | Seals are not DAG blocks; blockstore spill does not apply (REQUIREMENTS Future, line: "Seal storage redesign (spill / compaction / sidecar) — only if SEAL-01 measurement demands it"). The measurement says it does not (T1–T3 all far from tripping). |
| **Compaction-filter deletion / DeleteRange cleanup** | **Rejected** | Violates governing invariant 3 (seals never deleted by any path) and the v1.2 zero-new-mechanism budget (no compaction-filter deletion, no DeleteRange — STATE key decisions). |
| **Sidecar keyspace / dedicated CF** | **Rejected — deferred to triggers** | A redesign of the vendored, GATE-03-pinned key scheme ("Out of Scope: redesign doubles risk on the load-bearing recovery index"); only a tripped trigger re-opens it. |

## Evidence

- Volume + enumeration at 10⁶/10⁷ measured and 10⁸ extrapolated-and-flagged: `leg.volume_10e6_floor.*`, `leg.volume_10e6.*`, `leg.volume_10e7.*`, `leg.volume_10e8_extrapolated.*` in `phases/17-seal-growth-measurement-decision/17-seal-growth-evidence/seal_growth_evidence.json`
- Fidelity (D-04 — direct seeding admissible): `leg.fidelity.*` (242/242 byte-identical keys, walk Completed/64 visited/0 gaps)
- Density spectrum (D-05/D-06): `leg.density.*` (3 shapes × 3 fractions, all round-trips green, shared-CF context 8/211)
- Variance (D-12 band inputs): the max-deviation/CV keys cited in (c)
- Run transcript + runbook: `17-seal-growth-evidence/run-capture.md`, `17-seal-growth-evidence/README.md`

## D-08 re-run instructions

See `17-seal-growth-evidence/README.md` (the full runbook). Summary: build target `cold_seal_growth_test` (`cmake --build SuperGenius/build/Windows/Release --config Release --target cold_seal_growth_test --parallel 8`), run from `SuperGenius/build/Windows/Release/test/src/crdt` (the `test-data/...` fixture roots are relative to it), set `SGNS_SEAL_BIG_ENABLE` for the big legs (loud labelled skip otherwise). Knobs (NAMES only): `SGNS_SEAL_SCALE`, `SGNS_SEAL_BIG_SCALE`, `SGNS_SEAL_REPEATS`, `SGNS_SEAL_SEED`, `SGNS_SEAL_DEPTH`, `SGNS_SEAL_FANOUT`, `SGNS_SEAL_MIX`. The Tier-1 lane runs the bounded floor leg ungated on every CI pass.

## Sources (the four resolvable citations — per the research's ruling)

1. The in-code derivation comment: `SuperGenius/src/crdt/graphsync_dagsyncer.hpp:58-82` (the three-8-bounds derivation, PrunedMesh [1,4], composition with CID_FAILURE_SUPPRESSION 4 s and kTotalFetchTimeout 20 s, and the in-code Phase 17 SC2 contract).
2. The sibling bounds: `SuperGenius/src/crdt/crdt_datastore.hpp:743` (`MAX_FAILED_ROOT_RETRIES = 8`) and `SuperGenius/src/account/GeniusNode.hpp:1225` (`bootstrap_walk_max_retries_ = 8`).
3. The develop-line observations: `SuperGenius/.planning/phases/19-pruned-node-survival-recovery-hardening/19-07-SUMMARY.md` (T-19-0701: attempts bounded **≤8 RefusalFailover**, **≤4 PrunedMesh Phase B**; PrunedMesh Phase B attempts in **[1,4]**).
4. This phase's own probe numbers: `phases/17-seal-growth-measurement-decision/17-seal-growth-evidence/seal_growth_evidence.json` (the keys cited throughout this doc).

## Forward pointers

- **Phase 18** (policy/downgrade capstone): its policy record cites this doc's D-11 triggers as the seal-side "demands it" gate and the D-12 verdict as the walk-bounds closure.
- **Phase 19** (fault-race + 3-platform CI capstone): the Tier-1 floor leg (`cold_seal_growth_test`, LABELS Tier1, derived floors 480k rows/s and [46, 60] bytes) joins the three-platform lane contract it proves.
- **Future seal-redesign milestone** (if ever convened): gates on T1–T3 above; re-opens the spill/compaction/sidecar options table with material numbers; honors GATE-03's single-home rule in any migration.
