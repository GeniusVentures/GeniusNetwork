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
