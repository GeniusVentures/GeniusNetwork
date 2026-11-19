# Phase 17: Seal Growth Measurement & Decision - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-11-18
**Phase:** 17-Seal Growth Measurement & Decision
**Areas discussed:** Scale strategy (10⁶/10⁷/10⁸), Workload shape, Tiering & re-runnability, Decision record & triggers

---

## Scale strategy (10⁶/10⁷/10⁸)

| Option | Description | Selected |
|--------|-------------|----------|
| Hybrid (rec.) | Materialize 10⁶ + 10⁷ with real rows; 10⁸ extrapolated from measured per-row bytes + enumeration throughput curve, spot-checked against observed seeding rate | ✓ |
| Full materialize | Seed a real 10⁸-seal dataset (one-shot dev run; size unknown until per-seal bytes are measured — could be tens of GB). Maximum credibility, heaviest run | |
| Model-first | Only 10⁶ materialized; both 10⁷ and 10⁸ extrapolated. Fastest — weakest evidence for SC1's enumeration-at-scale claim | |

**User's choice:** Hybrid (rec.)
**Notes:** —

| Option | Description | Selected |
|--------|-------------|----------|
| Growing DB (rec.) | One dataset grown 10⁶ → 10⁷ in place. Reflects real cumulative growth — LSM levels, compaction state, fragmentation — what a long-lived archive node looks like | ✓ |
| Fresh per leg | Each scale leg gets a freshly-seeded DB. Isolates scale as the only variable; hides compaction effects | |
| Both + control | Growing DB for the main curve + one fresh-DB 10⁷ control leg separating scale effects from compaction effects | |

**User's choice:** Growing DB (rec.)
**Notes:** Fresh-DB control may be added later if the curve looks anomalous (captured in CONTEXT D-02).

| Option | Description | Selected |
|--------|-------------|----------|
| Full iteration (rec.) | Seek-to-prefix → iterate to exhaustion at each scale point; rows/sec + wall time + bytes scanned, warm and cold cache | ✓ |
| Sampled windows | Timed fixed-size windows at several offsets; throughput extrapolated. Exhaustion cost stays inferred | |
| Both cross-check | Full at 10⁶ + sampled at 10⁷ cross-checked against the curve; agreement feeds the 10⁸ extrapolation validation | |

**User's choice:** Full iteration (rec.)
**Notes:** —

---

## Workload shape

| Option | Description | Selected |
|--------|-------------|----------|
| Seed + fidelity (rec.) | Harness seeds seal keyspace directly (existing key builders, Phase 14 injection-kit precedent) for volume + one small real-walk leg proving seeded rows byte-identical to walk-produced seals (prefix-spy precedent) | ✓ |
| Real walks only | Every seal produced by actual recovery walks / TxPruner cycles. Most authentic — 10⁷ seals through real walks likely wall-clock infeasible | |
| Suite replay | Replay existing v1.1/v1.2 suite transaction patterns as generator. Real mix, volume still bounded by suite runtime | |

**User's choice:** Seed + fidelity (rec.)
**Notes:** —

| Option | Description | Selected |
|--------|-------------|----------|
| Knobbed spectrum (rec.) | Env-knobbed generator (chain depth × fan-out breadth × mix ratio); density measured across deep chain, wide fan-out, mixed | ✓ |
| Single canonical | One mixed DAG shape deemed representative; shape-dependence unquantified | |
| Spectrum + extremes | Knobbed spectrum plus pathological extremes to bound worst-case density | |

**User's choice:** Knobbed spectrum (rec.)
**Notes:** Extremes declined here; capacity math follows (spectrum endpoints serve as the band).

| Option | Description | Selected |
|--------|-------------|----------|
| Back-refs (rec.) | Density computed from Phase 15 D-02's /prune/blk back-reference records over the fixture DAGs — honors the recorded dependency directly | ✓ |
| Walk instrumentation | Counters inside the walk itself (visits-per-restore, ancestry hit-rate) during instrumented recovery runs | |
| Both cross-check | Back-ref static analysis primary + instrumented-walk cross-check leg | |

**User's choice:** Back-refs (rec.)
**Notes:** —

---

## Tiering & re-runnability

| Option | Description | Selected |
|--------|-------------|----------|
| T1 smoke + big (rec.) | Bounded 10⁶ leg in Tier-1 asserting floors (rows/sec, per-row bytes band); 10⁷ growing-DB run and 10⁸ extrapolation dev-gated one-shot with committed numbers | ✓ |
| All one-shot | Every leg dev-run once; numbers committed as artifacts; nothing recurring. Seal-cost regressions invisible until manual re-run | |
| T1 + dev-gated 10⁷ | Tier-1 10⁶ floor leg plus 10⁷ wired into the dev-gated lane (Phase 16 D-11 live-leg pattern), re-runnable on demand | |

**User's choice:** T1 smoke + big (rec.)
**Notes:** —

| Option | Description | Selected |
|--------|-------------|----------|
| Reusable harness (rec.) | Env-knobbed benchmark target (scale, DAG-shape, cache-state knobs) checked in as a first-class tool; decision record documents re-runs | ✓ |
| One-shot generator | Scripts produce the committed evidence once, archived with artifacts. Re-measuring means reconstructing | |

**User's choice:** Reusable harness (rec.)
**Notes:** —

| Option | Description | Selected |
|--------|-------------|----------|
| JSON + MD table (rec.) | Machine-readable JSON (raw numbers, hardware/OS/build fingerprint, RocksDB options, dataset fingerprint) beside a rendered human table | ✓ |
| MD table only | Human-readable tables only; programmatic consumers scrape prose | |
| JSON only | Raw JSON committed, rendered on demand | |

**User's choice:** JSON + MD table (rec.)
**Notes:** —

---

## Decision record & triggers

| Option | Description | Selected |
|--------|-------------|----------|
| Rulings doc (rec.) | Dedicated decision record in the workstream planning tree with full capacity math, options considered, triggers (Phase 16 D-12 precedent) + STATE.md key-decisions one-liner | ✓ |
| Phase-dir record | 17-DECISION.md-style artifact inside the phase directory only; less discoverable for Phase 18+ citations | |
| STATE.md only | Key-decisions entry only; capacity math and triggers have no auditable home | |

**User's choice:** Rulings doc (rec.)
**Notes:** Exact filename/home left to agent discretion.

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit numeric (rec.) | Concrete thresholds (e.g. seal bytes > X% of projected hot store at 10⁸; warm-cache enumeration > Y s at 10⁷ on reference hardware), each citing committed JSON numbers | ✓ |
| Qualitative | Prose conditions; future milestone re-judges. "Demands it" stays subjective | |
| Numeric + auto-eval | Thresholds plus periodic re-measure cadence with automatic re-evaluation — starts building policy machinery Phase 18 owns | |

**User's choice:** Explicit numeric (rec.)
**Notes:** —

| Option | Description | Selected |
|--------|-------------|----------|
| Band + re-tune (rec.) | Within a recorded tolerance band of Phase 15 D-06's defaults → validated; outside → constants re-tuned, amendment recorded at constants' home AND decision doc. Band derives from measured run-to-run variance | ✓ |
| Order-of-magnitude | ~10× agreement counts as validated; loose, weak evidence | |
| Exact match | Any deviation re-tunes; measurement noise guarantees spurious re-tunes | |

**User's choice:** Band + re-tune (rec.)
**Notes:** —

| Option | Description | Selected |
|--------|-------------|----------|
| Spectrum band (rec.) | Project from representative mix with spectrum endpoints as the uncertainty band; no separate pathological modeling | ✓ |
| Point estimate | Single representative-mix projection; hides shape-dependence the spectrum exposes | |
| Worst-case bound | Explicit pathological shapes beyond endpoints — re-introduces extremes the workload decision declined | |

**User's choice:** Spectrum band (rec.)
**Notes:** —

---

## the agent's Discretion

Benchmark target home/name and CLI shape; seeding mechanics (builder home, batch sizing, WAL posture); fidelity-leg fixture size and prefix-spy keyspaces; Tier-1 floor values (derived from measured numbers); extrapolation model specifics; tolerance-band computation; numeric trigger values; cold-cache leg mechanics; dataset fingerprint scheme; re-tune sequencing (same plan vs. follow-up); anchor re-location procedure post-Phase-16.

## Deferred Ideas

None — discussion stayed within phase scope. One todo reviewed and not folded (Vulkan capability-probe deadlock — keyword false-positive, unrelated).
