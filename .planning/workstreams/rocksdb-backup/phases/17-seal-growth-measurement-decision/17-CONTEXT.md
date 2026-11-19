# Phase 17: Seal Growth Measurement & Decision - Context

**Gathered:** 2026-11-18
**Status:** Ready for planning

<domain>
## Phase Boundary

SEAL-01 — measure-and-decide only. A measurement probe (this phase's FIRST plan, per SC2's ordering constraint) quantifies seal growth at representative workloads: row counts + bytes per seal, enumeration cost at 10⁶/10⁷/10⁸ seals scale, and recovery-walk ancestry density. Its numbers validate (or re-tune) Phase 15 D-06's derived walk-bound defaults — honoring the derive-now/refine-later contract. Then an explicit accept-hot-growth-vs-future-design decision is recorded with capacity math citing real walk-recovery numbers.

1. **SC1** — seal growth measured at representative workloads — row counts + bytes per seal, enumeration cost at 10⁶/10⁷/10⁸ seals scale, recovery-walk ancestry density — with committed evidence
2. **SC2** — the measurement probe runs as this phase's first plan and its numbers feed the walk-bounds work: Phase 15's walk-bound defaults are validated (or re-tuned) against the probe's real numbers — the recorded dependency is honored
3. **SC3** — an explicit decision — accept hot growth vs. future design — is documented with capacity math citing real walk-recovery numbers; any spill/compaction/sidecar redesign is a measured trigger deferred to a future milestone

**What changes in this phase:** additive measurement/test/benchmark code (probe harness, Tier-1 floor leg, fidelity leg) + planning/rulings documentation. The ONLY production-code touch is the conditional walk-bounds constant re-tune (SC2, if numbers land outside the tolerance band). Zero new dependencies (workstream rule). Seal semantics are untouched — seals are read, counted, and timed; never deleted, never re-shaped.

Out of this phase: seal spill/compaction/sidecar redesign (a measured trigger deferred to a future milestone — REQUIREMENTS Future), collectibility policy + role downgrade + walk-gap exemption (Phase 18), cross-feature fault-race matrix + three-platform CI capstone (Phase 19 — though this phase's Tier-1 leg feeds its lane contract).

Requirements: SEAL-01.

**Status note:** Phases 15 and 16 are executed (16 verified `passed_with_uat`; one Phase 16 UAT item — the live MinIO SC3 leg — remains outstanding and does NOT block planning here; both phases' code is landed on `dev_coldstorage_additions`). Planning research MUST re-locate all code anchors against the final post-Phase-16 line (research docs cite merge `2af184fa1`; Phase 15 executed at `095c8c502`; Phase 16 anchors were re-located at `af644481f`).

</domain>

<decisions>
## Implementation Decisions

### Scale strategy (SC1 coverage)
- **D-01:** **Hybrid coverage — materialize 10⁶ + 10⁷, extrapolate 10⁸** — the two smaller scales get real materialized rows; the 10⁸ number derives from measured per-row bytes + the enumeration throughput curve, spot-checked against the observed seeding rate. Tractable runs, defensible 10⁸ math. Full materialization of 10⁸ was considered and declined (size unknown until per-seal bytes are measured; likely tens of GB + a long one-shot seed for one data point); model-only-at-scale was declined (weakest evidence for SC1's enumeration-at-scale claim)
- **D-02:** **Growing DB — one dataset grown 10⁶ → 10⁷ in place** — cumulative growth (LSM levels, compaction state, fragmentation) is exactly what a long-lived archive node looks like; fresh-per-leg hides it. A fresh-DB control leg can be added later if the curve looks anomalous
- **D-03:** **Full-iteration enumeration measurement** — seek-to-prefix → iterate to exhaustion at each scale point; record rows/sec + wall time + bytes scanned, warm AND cold cache. Direct evidence for SC1's enumeration-cost claim (sampled windows leave the exhaustion cost — the number a maintenance sweep pays — inferred)

### Workload shape (what "representative" means)
- **D-04:** **Seed + fidelity leg — direct seal-keyspace seeding for volume, one real-walk leg for row-shape proof** — the harness seeds seal rows directly (existing key builders; Phase 14 D-08 journal-injection precedent) for the volume legs, PLUS one small real-walk leg proving seeded rows are byte-identical to walk-produced seals (Phase 11 prefix-spy instrument). Decouples scale from walk speed; the fidelity leg is what makes direct seeding admissible evidence — **Reversibility:** costly — dropping the fidelity leg later re-opens the "seeded rows ≠ real seals" objection that the whole evidence chain rests on
- **D-05:** **Knobbed DAG spectrum** — env-knobbed generator (chain depth × fan-out breadth × mix ratio); ancestry density is measured across a controlled spectrum (deep chain, wide fan-out, mixed), not one arbitrary shape. Pathological extremes beyond the spectrum endpoints were declined (re-introduces worst-case modeling the capacity math does not need — see D-13)
- **D-06:** **Ancestry-density source = `/prune/blk` back-references** — density computed from Phase 15 D-02's back-reference records (erased-at generation + `/prune/tx` hash) over the fixture DAGs. Honors the recorded cross-phase dependency directly (D-02's stated purpose: "feeds Phase 17's ancestry-density measurement") — **Reversibility:** costly — switching the density source (e.g. to walk instrumentation) re-opens the Phase 15 D-02 contract and orphans the back-reference record's stated justification

### Evidence tiering & re-runnability
- **D-07:** **Tier-1 10⁶ floor-smoke leg + dev-gated one-shot big legs** — a bounded 10⁶-scale leg enters the Tier-1 CI contract asserting floors (enumeration rows/sec, per-row bytes band) so seal-shape/size regressions get caught by CI; the 10⁷ growing-DB run and the 10⁸ extrapolation stay dev-gated one-shot with committed numbers. Extends the Phase 14 D-09 / Phase 16 D-09 fresh-clone-safe Tier-1 precedent and feeds the Phase 19 three-platform capstone — **Reversibility:** costly — a Tier-1 suite entry becomes part of the lane contract the Phase 19 capstone proves green on three platforms
- **D-08:** **Reusable harness, not one-shot scripts** — env-knobbed benchmark target (scale, DAG-shape, cache-state knobs) checked in as a first-class tool; the decision record documents how to re-run it, so a fired redesign trigger can be re-verified and future milestones can re-measure without rebuilding
- **D-09:** **JSON + rendered MD table evidence** — machine-readable JSON (raw numbers, hardware/OS/build fingerprint, RocksDB options, dataset fingerprint) beside a human-readable table. The numeric triggers (D-11) cite the JSON; future automation can consume it without scraping prose

### Decision record & triggers (SC3)
- **D-10:** **Workstream rulings doc + STATE.md one-liner** — a dedicated decision record in the workstream planning tree carries the full capacity math, options considered, and triggers (Phase 16 D-12 rulings-doc precedent — the doc Phase 18's policy record cites), plus a one-line key-decisions entry in STATE.md. Exact filename/home is agent discretion — **Reversibility:** costly — Phase 18's policy record and any future redesign milestone cite this doc by location; moving it later breaks the citation chain
- **D-11:** **Explicit numeric redesign triggers** — concrete recorded thresholds (e.g. seal bytes exceed X% of projected hot store at 10⁸; warm-cache enumeration wall-time exceeds Y s at 10⁷ on the reference hardware fingerprint), each citing the committed JSON numbers. Gives REQUIREMENTS' "only if SEAL-01 measurement demands it" clause its operational definition — "demands it" becomes checkable — **Reversibility:** costly — future redesign milestones gate on these numbers; rewriting them later re-opens what "demands" meant at decision time
- **D-12:** **SC2 semantics = tolerance band + re-tune** — probe numbers within a recorded tolerance band of Phase 15 D-06's derived defaults → validated; outside the band → constants re-tuned and the amendment recorded at the constants' home AND in the decision doc (both halves of the derive-now/refine-later contract honored). Band width derives from measured run-to-run variance — **Reversibility:** costly — this defines SC2's evidence contract; loosening it later re-opens what "validated" meant
- **D-13:** **Spectrum-band capacity math** — bytes/node (and enumeration cost) projected from the spectrum's representative mix, with the spectrum endpoints (deep-chain / wide-fan-out) as the uncertainty band. Consistent with D-05; no separate pathological-extreme modeling

### The Agent's Discretion
- Benchmark target home/name and CLI shape (test target vs. example; knob syntax)
- Seeding mechanics — direct CF writes via the existing key builders (which builder home), batch sizing, WAL posture for seed speed vs. realism
- Fidelity-leg fixture size and which keyspaces the prefix-spy byte-identity enumeration covers
- Tier-1 floor values (rows/sec floor, per-row bytes band) — derived from the probe's own measured numbers
- Extrapolation model specifics — how the throughput curve is fit; how the seeding-rate spot-check validates the 10⁸ number
- Tolerance-band computation from run-to-run variance (repetition count, variance statistic)
- The numeric trigger values themselves (X%, Y s) — proposed from measured numbers, recorded in the rulings doc
- Cold-cache leg mechanics (RocksDB cache reset vs. fresh process)
- Dataset fingerprint scheme for the evidence JSON
- Whether the walk-bounds re-tune (if triggered) lands as a constant amendment in the same plan or a follow-up plan — planner sequences it
- Anchor re-location strategy against the final post-Phase-16 line (see domain status note) — researcher rules exact procedure

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream planning
- `.planning/workstreams/rocksdb-backup/ROADMAP.md` — Phase 17 goal, 3 success criteria, dependencies (15, 16 — "its walk-bound defaults consume this phase's probe numbers"), the probe-first-plan ordering constraint
- `.planning/workstreams/rocksdb-backup/REQUIREMENTS.md` — SEAL-01 letter; Future Requirements ("Seal storage redesign (spill / compaction / sidecar) — only if SEAL-01 measurement demands it; seals are not DAG blocks, blockstore spill does not apply"); out-of-scope table (seal spill/migration this milestone); governing invariant 3 (seals never deleted by any path)
- `.planning/workstreams/rocksdb-backup/STATE.md` — v1.2 key decisions (SEAL probe = first plan of Phase 17; the recorded decision closes citing real walk-recovery numbers; zero new dependencies)
- `.planning/workstreams/rocksdb-backup/phases/15-evidence-aware-cold-serving-forced-walk-recovery/15-CONTEXT.md` — D-02 `/prune/blk` back-reference record (D-06's density source here); D-06 derive-now/refine-later walk-bound contract (SC2's validation target — constants derived from v1.1 recovery-suite numbers)
- `.planning/workstreams/rocksdb-backup/phases/16-txpruner-gc-composition-hardening/16-CONTEXT.md` — D-10 split counters (stranded-by-disposal mass — seal-relevant prune observability); D-12 rulings-doc precedent (D-10's shape here); D-09 Tier-1 contract precedent (D-07's shape here)
- `.planning/workstreams/rocksdb-backup/phases/14-durability-gated-txpruner-eligibility/14-CONTEXT.md` — D-08 journal-injection kit (direct-CF-seeding precedent for D-04); D-09 fresh-clone-safe Tier-1 precedent

### v1.2 research (2026-11-13)
- `.planning/research/SUMMARY-v1.2-rocksdb-backup.md` — seals-measurement phase row; key decisions (probe = first plan; zero new dependencies; collectibility policy-only)
- `.planning/research/ARCHITECTURE-v1.2-rocksdb-backup.md` — §(c) overlap inventory (seal rows as a shared surface across TxPruner/GC/LRU — the keyspace being measured)
- `.planning/research/PITFALLS-v1.2-rocksdb-backup.md` — seals-never-deleted invariant context; test-guidance tier discipline
- `.planning/research/FEATURES-v1.2-rocksdb-backup.md` — TS-3 (seals survive both pruners — the growth this phase measures is monotone by construction)

### v1.1 prior phases (evidence + numbers this phase cites)
- `.planning/workstreams/rocksdb-backup/milestones/v1.1-phases/` — recovery-walk suite artifacts: the recorded walk-recovery numbers Phase 15 D-06 derived from and SC3's capacity math must cite (researcher locates the exact SUMMARYs — same directive Phase 15 carried)
- `.planning/workstreams/rocksdb-backup/milestones/v1.1-phases/11-retention-gc-cold-eligible-crdt-data/` — the prefix-spy hot datastore instrument (D-04's fidelity-leg byte-identity assertions)

### Code under measurement (anchors from prior CONTEXTs — RE-LOCATE on the post-Phase-16 line before editing)
- `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` — :1083-1092 seal accessors (the walk owns sealing — the fidelity leg drives real walks through these surfaces)
- `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp` — `RunHotCleanup` (:1317-1345) + seal retention comment (:1327-1333 — the never-delete-seals ruling this phase measures the consequence of)
- `SuperGenius/src/transaction/PruneEligibility.cpp` / `.hpp` — marker statics home (`/prune/blk` key builder — the seeding key source and D-06's density read; D-C1 no-third-builder rule applies to the harness too)
- `SuperGenius/src/transaction/TxPruner.hpp` — :68 `PruneCycleStats` (Phase 16 D-10 split counters — prune-mass observability relevant to the measurement's interpretation)
- `SuperGenius/src/crdt/globaldb/globaldb.cpp` / `.hpp` — seal row keyspace + `EraseEntry` staging context (post-Phase-16 line; re-locate)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Phase 14 journal-injection test kit** — real GlobalDB + direct CF seeding, deterministic, no services; the direct-seeding precedent D-04's volume legs extend to the seal keyspace
- **Phase 11 prefix-spy hot datastore** — exact-key enumeration instrument; D-04's fidelity leg asserts seeded-vs-walked byte identity through it, and the enumeration-cost measurement (D-03) follows its iteration discipline
- **Phase 15 `/prune/blk` back-reference records** — already landing with every TxPruner erase; D-06's density source needs no new production writes
- **Phase 16 `PruneCycleStats` split counters** — stranded-vs-deferred prune mass already surfaces per-cycle; the probe interprets seal growth alongside it
- **Root-level cold-storage soak/wallclock harnesses** (`cold_storage_soak_test.cpp`, `cold_storage_wallclock_soak.cpp`, `test-data/cold-*`) — prior wall-clock measurement precedents for harness shape and artifact handling

### Established Patterns
- **Hermetic-first CI, dev-gated live evidence** — Tier-1 gets the bounded deterministic 10⁶ floor leg (D-07); the 10⁷/10⁸ legs are dev-gated one-shot committed evidence
- **Env-knobbed reproducibility on every nondeterministic/measurement run** — the harness (D-08) follows the v1.1 env-knob norm
- **Compose-don't-pick / read-only posture** — this phase adds no production semantics; seal keyspace is read, counted, timed
- **Evidence artifacts with environment fingerprints** — D-09's JSON shape extends the committed-evidence discipline the workstream already uses for gate outputs

### Integration Points
- Seal keyspace prefix enumeration (existing iterators — no new iterator machinery expected)
- `PruneEligibility` key builders — the harness seeds through them (no third builder)
- Tier-1 suite registration (`ctest -L` lane labels, label-count audit with teeth) — D-07's contract entry
- Walk-bound constants' home (wherever Phase 15 D-06 landed them — re-locate) — D-12's amendment site if re-tune triggers
- Workstream rulings-doc tree (Phase 16 D-12's doc's neighborhood) — D-10's record home

</code_context>

<specifics>
## Specific Ideas

None beyond the decisions above — no external examples or "make it like X" references were cited during discussion.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

### Reviewed Todos (not folded)
- "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" (quick task 261029-uj0) — surfaced by todo.match-phase on the keyword "probe" (score 0.2); unrelated to seal measurement (ProcessingManager/Vulkan vs CRDT seal keyspace). Reviewed and left alone.

</deferred>

---

*Phase: 17-Seal Growth Measurement & Decision*
*Context gathered: 2026-11-18*
