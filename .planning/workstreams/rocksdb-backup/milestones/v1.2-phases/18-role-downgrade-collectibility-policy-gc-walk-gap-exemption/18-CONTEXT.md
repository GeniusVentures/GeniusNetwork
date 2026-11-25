# Phase 18: Role Downgrade, Collectibility Policy & GC Walk-Gap Exemption - Context

**Gathered:** 2026-11-19
**Status:** Ready for planning

<domain>
## Phase Boundary

POLICY-01 + POLICY-02 — the two-halves rule ships as one record AND as enforced code: the GC walk-gap evidence exemption (what may be absent = what may be collected) lands as production code with a red-first counter-test, the cold-permanence policy + v2 contract ask is recorded in the rulings chain, and an archive→light downgrade is E2E-proven along the full ARCHITECTURE §3.5 timeline with a mechanical interlock preventing silent downgrade.

1. **SC1** — a recorded policy decision documents: cold objects are permanent this milestone, the permanent-once-written invariant, collectibility machinery as an sgns-blockstore v2 contract ask, and — in the same record — the GC walk-gap evidence exemption
2. **SC2** — an archive→light downgrade is E2E-proven: after downgrade the node prunes under light rules, and the history it pruned remains fetchable from other archive nodes (compositional coverage per D-10)
3. **SC3** — existing Durable records from the archive era satisfy the prune gate after downgrade — no re-drain, no migration
4. **SC4** — the downgrade timeline is observable end-to-end: markers accumulate post-downgrade, refusal activates, and a config interlock prevents silent downgrade (operator-initiated, checklist-gated)

**What changes in this phase:** production code — the GC walk-gap exemption consult + walk-exempted counter, the downgrade interlock (persisted role fingerprint, ack config key, pruner-disarm gate, WARN line), and Light+cold posture logging; documentation — one rulings doc in the `notes/` chain; tests — the exemption red-first counter-test (hermetic + dev-gated) and the single-node downgrade timeline E2E (Tier-1 hermetic + dev-gated live). Zero new dependencies (workstream rule). No sgns-blockstore contract change (frozen v1); no collection executes.

Out of this phase: cold collectibility machinery / v2 `Remove` (contract-v2 ask — sketched in the record, never built), network-coordinated collection, bucket-lifecycle/S3-expiry paths (AF-2), automatic/watermark-driven downgrade (AF-7), cross-node downgrade E2E topology (covered compositionally — D-10), the cross-feature fault-race matrix + three-platform CI capstone (Phase 19).

Requirements: POLICY-01, POLICY-02.

**Status note:** Phase 17 is executed with verification `human_needed` (4 UAT items pending; SEAL-01 measured and decided 2026-11-19). This phase's code dependencies (14, 15, 16) are landed on `dev_coldstorage_additions`. Planning research MUST re-locate all code anchors against the final post-Phase-17 line (Phase 15 executed at `095c8c502`; Phase 16 anchors re-located at `af644481f`; Phase 17 landed the conditional walk-bounds re-tune as its only production touch).

</domain>

<decisions>
## Implementation Decisions

### GC walk-gap exemption (the two-halves rule's v1.2 form)
- **D-01:** **Ship code + red-first counter-test** — the exemption lands as production code this phase, not a design record. GC's walk-gap abort site consults prune evidence: a prune-evidenced absent link is expected-absent (walk continues). A red-first counter-test fault-injects the v2 state (cold object deleted + evidence present) to prove the walk survives. This is the strongest form of SC1's "no collection can ever land without the exemption" — v2 collection cannot ship without the exemption already existing and tested. Design-record-only and tripwire-test alternatives were considered and rejected (documented-not-enforced; today's abort recorded as a future failure mode) — **Reversibility:** costly — the counter-test becomes part of the evidence chain any v2 collection milestone gates on; removing it re-opens the poisoned-GC-triangle prevention argument (PITFALLS Interaction A)
- **D-02:** **Consult routes through the Phase 15 role-aware GlobalDB evidence predicate** — the GC walk's gap site derives its verdict from the SAME single predicate the serving path and forced walk use; "pruned" ⇒ expected-absent. Extends the Phase 15 D-04 source-consistency ruling (every classifying surface projects from ONE predicate) to the GC walk. Keys built in `PruneEligibility` — no third builder (D-C1 discipline) — **Reversibility:** costly — a GC-local second consult surface would need consistency-by-test rather than by-construction
- **D-03:** **Counter-test tiered hermetic Tier-1 + dev-gated live** (Phase 16 D-11 both-legs precedent) — the deterministic Tier-1 leg uses the hermetic fake cold with test-side deletion (the fake can delete; production adapters cannot) + `/prune/blk` evidence seeded via the sanctioned marker writer; the dev-gated live leg proves the state on a real stack
- **D-04:** **Counted-continue** — each exempted gap increments a dedicated walk-exempted counter in the GC pass stats, surfaced in the per-pass INFO summary (Phase 14 D-03 / Phase 16 D-10 never-healthy-by-omission precedent). An operator can see how much of the walked graph the exemption is carrying

### Downgrade interlock (SC4 mechanics)
- **D-05:** **Hard gate + explicit ack config key** — a new deliberate config key (shape agent-discreet) must be set before a detected downgrade arms pruning; "operator-initiated, checklist-gated" becomes mechanically enforced, not advisory. WARN-only was considered and rejected (only as strong as log-review discipline). The new config surface is small and singular — Phase 14 D-04's no-config-knob posture applied to the durability gate and stays intact
- **D-06:** **Fire behavior = start, pruning disarmed** — on unacknowledged downgrade detection the node starts normally (serving, cold chain, sync all live) but the pruner stays disarmed with a loud WARN until acknowledged. Fail-toward-under-erase: a misconfigured node degrades to "keeps everything", never to "stops working" or "erases unacknowledged" — **Reversibility:** costly — this is the interlock's failure-mode contract; switching to refuse-to-start later changes the degradation story operators were told
- **D-07:** **Detection = persisted role fingerprint** — a small persisted meta record of the last-run role/config (node_type + pruning + cold-enabled) written at startup; archive-before → light+pruning-now = downgrade. Deterministic; cleanly distinguishes birth-tiered-light from downgraded-archive (the DB heuristic's false-positive — a birth-tiered-light's first prune cycle matches the same signature — is avoided); hermetically testable. One new tiny persisted state write
- **D-08:** **Operator checklist lives in the policy record** — the checklist (verify another archive replica exists, remote tier healthy, ack-key instructions) is a section of the Phase 18 rulings doc (D-13); the ack key's documentation references it by path. One canonical home, cited from code docs

### Downgrade E2E (SC2/SC3/SC4 evidence)
- **D-09:** **Single-node restart topology** — one node restarted as light (same DBs + cold config, `node_type` flipped; ARCHITECTURE §(f): config surfaces are independent today, downgrade = restart). The 2-node light+archive-peer topology was considered and declined for the E2E (real-pubsub N-node tests are the repo's flakiest class; cross-node semantics already proven on Phase 15's line) — **Reversibility:** costly — the SC2 compositional interpretation (D-10) is defined against this topology; adding a node later re-opens the E2E's evidence contract
- **D-10:** **SC2's cross-node letter = compositional coverage** — the E2E proves the downgraded node's half (prunes under light rules, its remote S3 objects remain intact/unchurned, refusal activates); the "fetchable from other archive nodes" claim rides on landed Phase 15 SERVE-04 semantics (distinct refusal → requesters fail over to serving archive nodes), cited as evidence. Recorded HERE so verification does not re-litigate it — **Reversibility:** costly — this defines SC2's evidence contract for the verifier
- **D-11:** **Hybrid tiering** — Tier-1 hermetic single-node re-open timeline (fake cold, deterministic t0→t3 mechanics, interlock fire/ack legs, marker accumulation, refusal activation) + a dev-gated live leg on the real S3 stack. Phase 15/16 D-11 hybrid discipline
- **D-12:** **Full t0→t3 timeline** — after markers + refusal + interlock legs, local cold copies of pruned data get retention-evicted and the test proves remote-backed serving still works for non-pruned cold data + walk health (D-01's exemption exercised in-band). Retention-age manipulation is deterministic in the hermetic tier (Phase 11 GC test precedent). Stopping at t2 was considered and declined (t3 is the capstone completeness — the steady state the policy record describes)

### Policy record (SC1 deliverable)
- **D-13:** **One rulings doc** — `notes/18-*.md` carries everything: the two-halves policy (cold permanent this milestone, permanent-once-written invariant, v2 contract ask), the GC walk-gap exemption record, the operator downgrade checklist (D-08), the tiered-node model writeup (archive vs tiered-light vs plain-light), and the downgrade timeline documentation. Joins the `notes/16-*` / `notes/17-*` rulings chain; STATE.md gets a one-liner (Phase 17 D-10 precedent) — **Reversibility:** costly — later phases cite this doc by location (the rulings-chain discipline); moving it breaks the citation chain
- **D-14:** **V2 contract ask = sketch, not pointer** — the record sketches the v2 `Remove` surface: what it must require (evidence-driven, node-local, per-CID — never age), why (the two-halves rule + poisoned-GC-triangle), and its preconditions (the exemption shipped — satisfied by D-01 — plus the Durable-then-`DisposedDurable` lifecycle pointer). REQUIREMENTS Future entries cross-referenced. Enough for a future milestone to plan against without re-deriving

### The Agent's Discretion
- Ack-key naming/shape and its config-file home (sgns_config.json vs the crdt config)
- Fingerprint record mechanics — which meta keyspace, what exactly is fingerprinted, when written, and its test seams
- Exemption consult mechanics at the GC walk-gap abort site — the exact seam, and how the Phase 15 predicate is exposed to the GC pass (GlobalDB injection per the `OpenColdStorageStack` precedent vs. an already-exposed surface on the post-17 line)
- Counter-test fixture shape — how the hermetic fake cold models test-side deletion; evidence seeding through the one sanctioned marker writer (testing-trap 1)
- Walk-exempted counter naming + INFO summary format
- E2E restart mechanics — in-process re-open of the same DBs (hermetic-friendly) vs. process restart; researcher confirms feasibility and picks
- SC3's no-re-drain observable — exact assertion shape (e.g. no new journal transitions / no drainer activity post-downgrade)
- Test file homes — sibling-file precedent (`cold_compose_matrix_test.cpp` / `cold_compose_live_smoke_test.cpp` pattern → e.g. a `cold_downgrade_e2e_test.cpp` family)
- Exact filename for `notes/18-*.md`
- Tier-1 floor/registration details for the new suites (label discipline, `ctest -L` contract)
- Anchor re-location strategy against the final post-Phase-17 line (see domain status note) — researcher rules exact procedure

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream planning
- `.planning/workstreams/rocksdb-backup/ROADMAP.md` — Phase 18 goal, 4 success criteria, dependencies (14, 15, 17 — "the downgrade E2E exercises exactly gate + refusal + cold availability")
- `.planning/workstreams/rocksdb-backup/REQUIREMENTS.md` — POLICY-01/02 letters; governing invariant 4 (two-halves rule); Future Requirements (collectibility machinery = v2 contract ask; `DisposedDurable`); out-of-scope table (executing cold collection)
- `.planning/workstreams/rocksdb-backup/STATE.md` — v1.2 key decisions (policy-only collectibility; two-halves shipped together; zero new dependencies; SEAL-01 decided 2026-11-19)
- `.planning/workstreams/rocksdb-backup/phases/15-evidence-aware-cold-serving-forced-walk-recovery/15-CONTEXT.md` — D-04 source-consistency ruling (D-02 extends it); D-05 walk decision matrix (`/prune/blk` → skip — the forced-walk half the GC exemption mirrors); D-07 SURV-04/SERV-02 refusal + failover semantics (D-10's compositional evidence)
- `.planning/workstreams/rocksdb-backup/phases/16-txpruner-gc-composition-hardening/16-CONTEXT.md` — D-10 split counters (D-04's observability precedent); D-11 both-legs test posture (D-03's precedent); D-12 rulings-doc code+doc discipline (D-13's shape)
- `.planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-CONTEXT.md` — D-10 rulings-doc + STATE.md one-liner precedent (D-13's chain); the post-17 anchor-relocation posture
- `.planning/workstreams/rocksdb-backup/notes/16-txpruner-gc-composition-rulings.md` — the rulings-doc pattern this phase's record joins
- `.planning/workstreams/rocksdb-backup/notes/17-seal-growth-decision.md` — D-11 numeric triggers + D-13 capacity math (the record the policy doc cites as its measurement neighbor)

### v1.2 research (2026-11-13)
- `.planning/research/ARCHITECTURE-v1.2-rocksdb-backup.md` — §(f) Role-downgrade data flow (config independence; the composed t0→t3 flow; the collectibility opinion); §3.5 Role downgrade timeline (the E2E blueprint); §2 modified-components (GeniusNode downgrade wiring notes + Light+cold WARN/INFO); §4 build-order item 6
- `.planning/research/PITFALLS-v1.2-rocksdb-backup.md` — Interaction A (the poisoned-GC triangle — D-01's motivating hazard); P4 encoding ("collect only against prune evidence, never age; downgrade is a one-way door, loudly documented; the exemption ships with or before the first collection capability"); AF-7 (auto-downgrade forbidden); testing traps 1 (sanctioned marker writer) and 5 (N-node portability landmines — why D-09 declined the 2-node E2E)
- `.planning/research/SUMMARY-v1.2-rocksdb-backup.md` — the frozen policy-only constraint; the two-halves ordering constraint; key decisions row 6 (phase scope); anti-features list
- `.planning/research/FEATURES-v1.2-rocksdb-backup.md` — D-2 (collectibility/downgrade as policy); AF-2 (no automatic cold deletion); AF-7 (no auto downgrade); the D-2 policy+interlock ships-now arc
- `.planning/research/STACK-v1.2-rocksdb-backup.md` — row 4 + collectibility rows (node-local policy + `S3Client::Delete` only-if-ever; no s3d/bucket-lifecycle dependency — the rejected alternatives D-14 sketches against)

### Develop-line artifacts (D-10's compositional evidence)
- `SuperGenius/.planning/REQUIREMENTS.md` — SURV-02 letter as completed on develop (distinct local refusal + clean standard peer refusal)
- `SuperGenius/.planning/phases/19-pruned-node-survival-recovery-hardening/19-07-PLAN.md` + `19-07-SUMMARY.md` — pruned-server refusal + requester failover, per-CID accounting (the semantics the cross-node claim composes onto)

### Code under change (anchors from prior CONTEXTs — RE-LOCATE on the post-Phase-17 line before editing)
- `SuperGenius/src/account/GeniusNode.cpp` — prune timer arming (~:4966+; Light check ~:4978) — the interlock's disarm gate + fingerprint wiring home
- `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp` — the GC pass / `RunHotCleanup` walk (the gap-abort site D-01's exemption consults from); `EvictLocalAndMarkDisposed`; retention/eviction surfaces the t3 leg drives
- `SuperGenius/src/transaction/PruneEligibility.cpp` / `.hpp` — marker statics home (`/prune/blk` key builders — no third builder); `LookupPrunedEntry` tri-state
- `SuperGenius/src/crdt/globaldb/globaldb.cpp` / `.hpp` — `OpenColdStorageStack` (Phase 15 predicate injection seam — D-02's exposure path); `EraseEntry` staging context
- `SuperGenius/src/transaction/TxPruner.cpp` / `.hpp` — `RunCycle` group filter (Phase 14 cold gate + Phase 16 disposed consult — what arms post-ack); `PruneCycleStats` (counter precedents)
- `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` — `ApplyColdPrecedence` / refusal classification (SC4's "refusal activates" observable surface)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Phase 15 role-aware evidence predicate + `/prune/blk` markers** — the single classifying source D-02 routes the GC consult through; markers already land atomically with every TxPruner erase
- **Phase 14 journal-injection test kit** — real GlobalDB + direct CF seeding, deterministic, no services; the E2E's archive-era state seeding and the counter-test's evidence seeding both extend it
- **Hermetic evidence-aware fakes (Phase 15 TEST-01)** — tri-state PrunedLookup fabric; the counter-test's fake cold adds test-side deletion
- **Interrupt seams** (`kInterruptBeforeErase`, `kInterruptAfterColdGate`, the Phase 16 sibling) — the deterministic interleave/inducement pattern for the interlock and timeline legs
- **`PruneCycleStats` + per-cycle INFO summary** — the counter home D-04 extends
- **Phase 11 GC/retention test machinery** — deterministic retention-eligibility manipulation for the t3 leg
- **Rulings-doc chain** (`notes/16-*`, `notes/17-*`) — the shape and citation discipline D-13 joins

### Established Patterns
- **Hermetic-first CI, dev-gated live evidence** — D-03/D-11's tiering
- **Red-first counter-tests** — D-01's counter-test written failing-first
- **Fail-toward-under-erase / fail-closed** — D-06's disarm posture; the interlock never enables destruction
- **One predicate, no third builder** — D-02's consult routing; keys only from `PruneEligibility`
- **Never-healthy-by-omission observability** — D-04's walk-exempted counter (D-03/D-10 Phase 14/16 precedent)
- **Rulings-doc + code-at-both-homes documentation** — D-13 (record) + code comments at the interlock/exemption sites (Phase 16 D-12 discipline)

### Integration Points
- GC walk-gap abort site (ColdStorageManager) — the exemption consult + counter
- Prune-timer arming (GeniusNode, Light check) — the interlock's disarm gate + WARN emission
- Config load path + persisted meta keyspace — the ack key and role fingerprint
- `OpenColdStorageStack` / GlobalDB — predicate exposure to the GC pass
- Tier-1 suite registration (`ctest -L` lane labels, label-count audit with teeth) — the new suites' contract entry; feeds the Phase 19 three-platform capstone
- `notes/` rulings tree — the policy record home

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond the recorded decisions — the discussion was decision-focused with no external references introduced by the user.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. (SC2's cross-node exercise was resolved compositional-within-phase by D-10, not deferred; the v2 collection machinery remains a REQUIREMENTS Future entry sketched by D-14, not a Phase 18 idea.)

</deferred>

---

*Phase: 18-Role Downgrade, Collectibility Policy & GC Walk-Gap Exemption*
