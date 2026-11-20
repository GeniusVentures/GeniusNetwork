# Roadmap: rocksdb-backup

## Milestones

- ✅ **v1.0 CRDT Cold-Storage BlockStore Library (Sia s3d backend)** — Phases 1-5, 21/21 requirements (shipped 2026-10-22) — archive: [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md)
- ✅ **v1.1 SuperGenius Cold-Storage Integration & CRDT Garbage Collection** — Phases 6-12, 21 plans, 3/3 TEST requirements (shipped 2026-11-10) — archive: [milestones/v1.1-ROADMAP.md](milestones/v1.1-ROADMAP.md)
- 🚧 **v1.2 SuperGenius Cold-Storage Archive Integration** — Phases 13-19, 20 requirements (started 2026-11-13)

<details>
<summary>✅ v1.0 CRDT Cold-Storage BlockStore Library (Phases 1-5) — SHIPPED 2026-10-22</summary>

- [x] Phase 1: BlockStore Contract, Memory Backend & Conformance Kit (3/3 plans) — completed 2026-10-20
- [x] Phase 2: LocalBlockStore (RocksDB Cold Tier) (3/3 plans) — completed 2026-10-20
- [x] Phase 3: minio-cpp Integration & S3Client Adapter (4/4 plans incl. 03-04 gap closure) — completed 2026-10-21
- [x] Phase 4: S3BlockStore & Sia s3d Roundtrip (3/3 plans) — completed 2026-10-22
- [x] Phase 5: Fault Injection & Three-Tier Hardening (3/3 plans) — completed 2026-10-22

Full phase details, plans, and success criteria: [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md)
Requirements (21/21 complete): [milestones/v1.0-REQUIREMENTS.md](milestones/v1.0-REQUIREMENTS.md)
Milestone audit (passed): [milestones/v1.0-MILESTONE-AUDIT.md](milestones/v1.0-MILESTONE-AUDIT.md)

</details>

<details>
<summary>✅ v1.1 SuperGenius Cold-Storage Integration & CRDT Garbage Collection (Phases 6-12) — SHIPPED 2026-11-10</summary>

- [x] **Phase 6: sgns-blockstore v1.1 Library Prerequisites — blake2b-256 CIDs & Installed S3 Client Factory** - Remove the two hard blockers additively: the CID hash gate widened to accept blake2b-256 (the shape of every CRDT DAG block) and an installed `OpenMinioS3Client` factory (completed 2026-10-22)
- [x] **Phase 7: SuperGenius Build Wiring & Config Gate** - Both `CommonBuildParameters.cmake` files resolve sgns-blockstore from the install tree; the `crdt_config.json` blockstore section defines the blank=disabled / malformed=loud contract; hermetic Tier-1 CI lane from day one (completed 2026-10-23)
- [x] **Phase 8: Spill-on-Write & Background Drainer** - Every CRDT block Put journals locally at the `IpfsDatastore` seam (no remote I/O under `dagMutex_`); a dedicated drainer thread uploads to S3 with crash-resume and an explicit backpressure policy (completed 2026-10-23)
- [x] **Phase 9: Cold Read Fallback — Local Reads & Graphsync Serving** - Hot-store misses fetch Local→S3 with CID-verify and re-cache; graphsync serves cold CIDs asynchronously off the responder's inline path; transport failure never surfaces as NotFound (completed 2026-10-26)
- [x] **Phase 10: Flush-Gated Durability Advancement** - `Durable` becomes an evidence-backed state (s3d `/objects/flush` + `pendingObjects==0` → `MarkUploadedDurable`), making the eviction durability gate real before anything deletes (completed 2026-10-26)
- [x] **Phase 11: Retention GC of Cold-Eligible CRDT Data** - Eviction-only GC behind durability + non-reachability gates with bounded disposed-CID markers; evicted CIDs stay retrievable end-to-end; live s3d spill→GC→retrieve evidence (dev-gated) (completed 2026-10-27)
- [x] **Phase 12: Integration Hardening, Fault Races & Fresh-Clone Proof** - Evict×serve×drain races, resurrection counter-test, s3d-down soak, and fresh-clone Tier-1 green on Windows/Linux/macOS with cold storage ON (completed 2026-11-10 — SC4 closed by tag-build run 42905264387: 153/153 Windows, 152/152 Linux, 155/155 OSX, cold storage ON, test_coldstorage_rtti)

Full phase details, plans, and success criteria: [milestones/v1.1-ROADMAP.md](milestones/v1.1-ROADMAP.md)
Requirements (3/3 TEST requirements complete): [milestones/v1.1-REQUIREMENTS.md](milestones/v1.1-REQUIREMENTS.md)
Milestone audit (passed — 3/3 requirements, 7/7 phases, 5/5 integration seams, 1/1 E2E flow): [milestones/v1.1-MILESTONE-AUDIT.md](milestones/v1.1-MILESTONE-AUDIT.md)

</details>

## Phases

**Phase Numbering:** Continuous across milestones — v1.0: Phases 1-5 · v1.1: Phases 6-12 · v1.2: Phases 13-19.

- [x] **Phase 13: Bootstrap Branch Merge & Composition Baseline** - Merge `fix/trust-genesis-bootstrap` into `dev_coldstorage_additions` with the full existing suite green — the gate for all v1.2 recovery/walk work (completed 2026-11-16 — merge `2af184fa1` pushed by user as `origin/dev_coldstorage_additions`; SC2 zero-regression 167/167 post vs composed pre baseline; SC3 items 1-3 green, item 4 D-12 escalated-deferred to Phase 15 per user ruling; SC4 checklist COMPLETE with fresh final-HEAD D-15 gate outputs)
- [x] **Phase 14: Durability-Gated TxPruner Eligibility** - A cold-enabled node never erases hot data that is not evidence-Durable in cold — fail closed, TOCTOU re-checked under the compose lock, gate composes with (not into) the eligibility evaluator (completed 2026-11-16)
- [ ] **Phase 15: Evidence-Aware Cold Serving & Forced-Walk Recovery** - Evidence outranks bytes on every path — fixes the cold-chain resurrection gap and the forced-walk GC-evicted conflation; hermetic tri-state evidence fakes land here
- [ ] **Phase 16: TxPruner × GC Composition Hardening** - Close the stale-LRU erase window, prove the TxPruner×GC interleave matrix, rule the disposal-starvation interplay fail-safe (under-prune)
- [ ] **Phase 17: Seal Growth Measurement & Decision** - Measure seal growth at representative workloads (probe first — it feeds Phase 15's walk bounds) and record the accept-vs-redesign decision with capacity math
- [x] **Phase 18: Role Downgrade, Collectibility Policy & GC Walk-Gap Exemption** - The two-halves rule recorded as one policy (cold permanent this milestone + GC walk-gap exemption); archive→light downgrade E2E-proven (completed 2026-11-19)
- [ ] **Phase 19: Cross-Feature Fault-Race Matrix & Three-Platform CI Capstone** - Induced failures across erase × serve × recovery cannot resurrect, partially validate, or lose last copies; recovery-walk suites green on Windows/macOS/Linux with cold storage ON

*Deferred signals carried forward (see STATE.md `## Deferred Items` and the v1.1 audit's tech-debt section): soak-scale GC eviction-storm hardening; TEST-03 MinIO-binary live leg (runbook); permanent cmake.yml ON-leg baseline (activates at develop merge).*

## Phase Details

### Phase 13: Bootstrap Branch Merge & Composition Baseline

**Goal**: The `fix/trust-genesis-bootstrap` forced-walk work lands on `dev_coldstorage_additions` as a pure merge — no cold-storage/recovery logic re-derived — establishing the merged-line baseline on which every recovery/walk requirement becomes testable.
**Depends on**: Nothing (first v1.2 phase; builds on shipped v1.1 phases 6-12)
**Requirements**: RECOVER-01
**Success Criteria** (what must be TRUE):
  1. `fix/trust-genesis-bootstrap` is merged into `dev_coldstorage_additions` and pushed — conflicts resolved per the `GeniusNode.cpp` merge checklist, recovery logic composed (not rebuilt).
  2. The full existing test suite runs green on the merged line — zero regressions against the pre-merge baseline.
  3. The post-merge verification gate passes observably: 4-term `HasBlock`, cold-chained `GetNodeWithoutRequest`, GATE-03 seal permanence intact, and cold-before-peer fetch ordering observable.
  4. A composition-only grep gate proves no recovery/bootstrap logic was re-derived or rewritten in the merge (checklist + evidence committed).

**Plans**: 4/4 plans executed

Plans:
**Wave 1**
- [x] 13-01-PLAN.md — D-02 dirty-tree checkpoint (blocking human), D-13 pre-merge checklist authored, SC2 pre-merge baseline leg on 7961ec264

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 13-02-PLAN.md — TRACER: the step-gated composition merge (topology re-verify, merge --no-commit, single-hunk compose, D-15a/D-15b gates, commit) + incremental Release rebuild

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 13-03-PLAN.md — SC2 post-merge leg + zero-regression comparison; SC3 four-check evidence (HasBlock terms, cold chain, GATE-03 as-is, D-12 log ordering)

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 13-04-PLAN.md — SC4 checklist finalized/committed, root pointer bump, D-04/D-01 human-gated push creating origin/dev_coldstorage_additions

### Phase 14: Durability-Gated TxPruner Eligibility

**Goal**: A cold-enabled node's TxPruner erases hot data only when every constituent block is evidence-Durable in cold — the gate fails closed, survives durability races, and composes with (not conflicts with) develop's Phase 17 evaluator.
**Depends on**: Phase 13 (soft — implementation parallel-startable on different files; final test evidence on the merged line)
**Requirements**: PRUNE-01, PRUNE-02, PRUNE-03
**Success Criteria** (what must be TRUE):
  1. A TxPruner erase proceeds only when every constituent block of the transaction is `Durable` in cold; NoRecord, Pending, Accepted, and Unreadable journal states all defer the erase loudly (fail closed — deferrals surface as a `cold_deferred_groups` counter, not a failure reason, so the next cycle re-evaluates).
  2. An induced durability-state regression between evaluation and erase-commit cannot enable a destroying erase — evidence is re-checked at erase-commit time under the compose lock (TOCTOU counter-test proves the last copy is never destroyed).
  3. The gate is injected at `RunCycle`'s cycle/group filter while `PruneEligibility::Evaluate` stays contractually pure — proven by a composition test in which the cold-durability conjunct composes with the evaluator (develop Phase 17 landing remains a merge, not a rewrite).
  4. On a node with no cold tier, TxPruner behavior is unchanged from today (gate vacuous — `prune_eligible(tx) AND (no_cold_tier OR cold_durable(cid))`).

**Plans**: 3/3 plans complete defined (research complete 2026-11-16 — monotonicity answered NO in-process regression; develop Phase 17 confirmed LANDED, evaluator purity stays the defense)

Plans:
**Wave 1**
- [x] 14-01-PLAN.md — TRACER: cold-durability admission conjunct at RunCycle's group filter (HasColdStorage accessor, cold_deferred/cold_unreadable counters, INFO extension) + Tier-1 gate suite (Durable-erases / Pending-defers-whole-group / cold-off-vacuuous)

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 14-02-PLAN.md — guard 5 in-compose durability re-check (Error::COLD_NOT_DURABLE + TxPruner counter mapping, Pitfall 1) + red-first TOCTOU counter-test at the new kInterruptAfterColdGate step-5 seam

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 14-03-PLAN.md — five-state journal matrix completion (CF seeding, adjacency/empty/ordering edges, Unreadable bridge+gate legs) + SC3 composition & purity gates + dev-gated live smoke + full Tier-1 contract

### Phase 15: Evidence-Aware Cold Serving & Forced-Walk Recovery

**Goal**: Evidence outranks bytes on every read path — serving and the forced walk distinguish pruned (terminal refusal) from evicted (restorable from cold), fixing both research-discovered bugs, with hermetic evidence-aware fakes backing every suite.
**Depends on**: Phase 13, Phase 14
**Requirements**: SERVE-01, SERVE-02, SERVE-03, SERVE-04, RECOVER-02, RECOVER-03, RECOVER-04, TEST-01
**Success Criteria** (what must be TRUE):
  1. A request for a TxPruner-erased CID is answered with pruned semantics even when cold bytes still exist — the cold chain (Rehydrate path) consults prune evidence before serving; no resurrection of deliberately erased bytes (kills the cold-chain resurrection gap).
  2. A request for a GC-evicted CID (no prune evidence) on a cold-enabled node is served through the cold chain and re-warmed — evict ≈ DETACH; the node stays an archive node, proven by masquerading counter-tests in both directions.
  3. The three-way answer (pruned / evicted-restorable / not-found) is consistent across `HasBlock`, `getNode`, and the cold chain via a single role-aware evidence predicate owned by GlobalDB — and pruned stays distinct from not-found at the protocol surface so requesters fail over to serving archive nodes correctly.
  4. The forced walk restores GC-evicted ancestors from cold (never conflating GC-evicted with pruned), never resurrects TxPruner-erased elements (`CanRestoreElement` composition is terminal), bounds peer failover per-CID, and aborts-never-skips on walk-gaps — no infinite failover loops, no silently-validated partial history.
  5. Hermetic evidence-aware test fakes model the PrunedLookup tri-state (present / pruned / not-found) and back every SERVE / RECOVER / PRUNE suite without live services — with the refusal matrix running as a product: {hot} × {cold} × {evidence: none/PRUNED/malformed} × {serve, walk visit, erase-gate}.

**Plans**: 3/3 plans executed defined (research + patterns complete 2026-11-17 — anchors re-located at `095c8c502`; D-01 widening ruled feasible, layering fact recorded: the predicate lambda goes GlobalDB-native)

Plans:
**Wave 1**
- [x] 15-01-PLAN.md — TRACER: /prune/blk evidence production (D-01 vector widening + D-02 record) → single PruneEvidenceClass predicate (SC3) → cold-chain consult + refusal taxonomy + re-warm gate (SC1/SC2, SERVE-01/02/04 mechanism) + hermetic Tier-1 matrix suite legs S1-S5

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 15-02-PLAN.md — D-05 walk evidence matrix (RECOVER-02/03) + walk_gaps abort-never-skip + D-06 per-CID failover budget (kForcedWalkPeerFailoverPerCid=8, walk-passed) + node-level walk suites (RECOVER-04)

**Wave 3** *(blocked on Waves 1-2 completion)*
- [x] 15-03-PLAN.md — full refusal matrix as a product (SC5/TEST-01) + red-first masquerading counter-tests (SC2) + SC3 source-consistency flip-test (D-04) + erase-gate both-marker atomicity (D-01) + cold-enabled refusal failover with A5 discipline (SERVE-04)

**Research flag**: light/optional — `/prune/blk` marker staging mechanism (widen `EraseEntry`'s `extra_entry` vs. staging via `TransactionManager`).

### Phase 16: TxPruner × GC Composition Hardening

**Goal**: Concurrent TxPruner and GC passes are proven safe on the gated, evidence-aware line — sequenced, not unified — with the stale-LRU window closed, interleavings matrix-proven, and the disposal-starvation interplay ruled fail-safe.
**Depends on**: Phase 14, Phase 15 (the gate defines the disposal interplay; marker infrastructure from Phase 15)
**Requirements**: COMP-01, COMP-02, COMP-03
**Success Criteria** (what must be TRUE):
  1. `EraseEntry`'s post-commit cleanup is hardened to GC's parity — a concurrent `GrabCIDBlock` insert between compose-start and commit cannot leave a stale LRU entry (post-commit `DeleteCIDBlock` closes the window).
  2. An interleave matrix crossing concurrent TxPruner and GC passes — overlapping set rows, seal rows, and the block LRU — proves both idempotent on absent keys, seals untouched by both, and both erase orders converging to one fixed point.
  3. The GC-disposal starvation interplay (journal record deleted → gate reads NoRecord while remote S3 still serves) is ruled and documented with its fail-safe direction asserted by test: the observable outcome is under-prune, never destruction of the last copy.

**Plans**: 3/3 plans executed defined (research + patterns complete 2026-11-18 — anchors re-located at `af644481f` post-Phase-15; open questions ruled: sibling observe-and-continue seam `SetEraseWindowObserverForTest`, Tier-3 leg in a new `cold_compose_live_smoke_test.cpp` sibling file, anomaly-exit coverage via a single pre-re-assert call site)

Plans:
**Wave 1**
- [x] 16-01-PLAN.md — TRACER: SC1 stale-LRU close (observe-and-continue seam + post-commit `DeleteCIDBlock` covering both committed exits, red-first window counter-test both D-06 layers, `cold_compose_matrix_test` Tier-1 suite born)

**Wave 2** *(blocked on Wave 1 — shared files: globaldb.cpp/.hpp, the suite, CMakeLists)*
- [x] 16-02-PLAN.md — SC3 starvation ruling (`IsColdDisposed` consult chain + `cold_disposed_stranded_groups` split counter + deterministic Tier-1 + dev-gated Tier-3 live leg + D-02/D-12 ruling comments at both homes + the workstream rulings doc)

**Wave 3** *(blocked on Wave 2 — same suite file; matrix rows assert the stranded classification)*
- [x] 16-03-PLAN.md — SC2 interleave matrix (order-A/order-B + seam-stepped + barrier-driven legs, D-08 two-layer fixed-point convergence, D-07 crossfire rows, seals-untouched, Interaction-C durability-flip race row)

### Phase 17: Seal Growth Measurement & Decision

**Goal**: Seal growth at representative workloads is measured and an explicit accept-hot-growth-vs-future-design decision is recorded with capacity math — measure-and-decide only; no seal spill/redesign this milestone.
**Depends on**: Phase 15 (its walk-bound defaults consume this phase's probe numbers), Phase 16
**Requirements**: SEAL-01
**Success Criteria** (what must be TRUE):
  1. Seal growth is measured at representative workloads — row counts + bytes per seal, enumeration cost at 10⁶/10⁷/10⁸ seals scale, and recovery-walk ancestry density — with committed evidence.
  2. The measurement probe runs as this phase's first plan and its numbers feed the walk-bounds work: Phase 15's walk-bound defaults are validated (or re-tuned) against the probe's real numbers — the recorded dependency is honored.
  3. An explicit decision — accept hot growth vs. future design — is documented with capacity math citing real walk-recovery numbers; any spill/compaction/sidecar redesign is a measured trigger deferred to a future milestone.

**Plans**: 3/3 plans executed defined (research + patterns complete 2026-11-18 — anchors verified at SuperGenius `741980f5d`; probe-first ordering per SC2)

Plans:
**Wave 1**
- [x] 17-01-PLAN.md — TRACER: the probe harness itself — sanctioned seal seeding, raw-iterator suffix enumeration, flat JSON evidence, Tier-1 floor registration with derived floors (D-03/D-07/D-08/D-09)

**Wave 2** *(blocked on Wave 1 — shared files: the harness + its registration)*
- [x] 17-02-PLAN.md — SC1 completion: fidelity byte-identity leg (D-04), knobbed DAG-spectrum density legs over /prune/blk (D-05/D-06), dev-gated growing 10⁶→10⁷ big legs + flagged 10⁸ extrapolation, committed evidence trio (D-01/D-02/D-09)

**Wave 3** *(blocked on Wave 2 — the verdict and capacity math consume the committed numbers)*
- [x] 17-03-PLAN.md — SC2/SC3 closure: D-12 band + walk-bounds verdict + conditional both-homes re-tune (the phase's only production touch), the D-10 decision record with D-11 triggers + D-13 capacity math, STATE.md one-liner

### Phase 18: Role Downgrade, Collectibility Policy & GC Walk-Gap Exemption

**Goal**: Cold collectibility ships as the two-halves rule — permanent-cold-this-milestone policy and the GC walk-gap evidence exemption recorded together — and an archive→light downgrade is E2E-proven as the composed flow.
**Depends on**: Phase 14, Phase 15 (the downgrade E2E exercises exactly gate + refusal + cold availability), Phase 17
**Requirements**: POLICY-01, POLICY-02
**Success Criteria** (what must be TRUE):
  1. A recorded policy decision documents: cold objects are permanent this milestone, the permanent-once-written invariant, collectibility machinery as an sgns-blockstore v2 contract ask (frozen v1 forbids Remove), and — in the same record — the GC walk-gap evidence exemption (what may be absent = what may be collected; no collection can ever land without the exemption).
  2. An archive→light downgrade is E2E-proven: after downgrade the node prunes under light rules, and the history it pruned remains fetchable from other archive nodes.
  3. Existing Durable records from the archive era satisfy the prune gate after downgrade — no re-drain, no migration.
  4. The downgrade timeline is observable end-to-end: markers accumulate post-downgrade, refusal activates, and a config interlock prevents silent downgrade (operator-initiated, checklist-gated).

**Plans**: 4/4 plans complete defined (research + patterns complete 2026-11-19 — anchors verified at SuperGenius `84d87d462`; red-first tracer per D-01)

Plans:
**Wave 1**
- [x] 18-01-PLAN.md — TRACER: the GC walk-gap exemption red-first — LEG-1 poisoned-triangle/LEG-2 deleted-cold counter-test observed RED, then the one-predicate consult + counted-continue counter turning it green (D-01/D-02/D-03-hermetic/D-04)

**Wave 2** *(blocked on Wave 1 — shared file: test/src/crdt/CMakeLists.txt)*
- [x] 18-02-PLAN.md — SC4 mechanics: `downgrade_acknowledged` ack key + persisted role fingerprint + the GeniusNode start-normally/disarm gate + tiered-light posture line + the Tier-1 verdict matrix incl. birth-light control (D-05/D-06/D-07)

**Wave 3** *(blocked on Wave 2 — shared files: cold_downgrade_e2e_test.cpp + CMakeLists.txt; t3 consumes the 18-01 exemption in-band)*
- [x] 18-03-PLAN.md — SC2/SC3/SC4 evidence: the t0→t3 single-node re-open timeline (held-drainer no-re-drain, markers, refusal, t3 retention + exemption in-band) + the Tier-3 MinIO live leg (D-09/D-10/D-11/D-12)

**Wave 4** *(blocked on Wave 3 — the record cites all committed evidence)*
- [x] 18-04-PLAN.md — SC1 closure: the `notes/18-*` rulings record (two-halves policy + exemption record + v2 contract-ask sketch + operator checklist) + STATE.md one-liner (D-08/D-13/D-14)

### Phase 19: Cross-Feature Fault-Race Matrix & Three-Platform CI Capstone

**Goal**: The composed v1.2 system — erase × serve × recovery — is disproof-proven under induced failure at every phase boundary, and recovery-walk suites run green on all three platform CI lanes with cold storage ON.
**Depends on**: Phases 13-18 (all semantics settled)
**Requirements**: TEST-02, TEST-03
**Success Criteria** (what must be TRUE):
  1. The extended fault-race matrix (extending v1.1's 13-case matrix) crosses erase × serve × recovery — induced failures at each phase boundary cannot produce resurrection, partial-history validation, or lost last copies (`VALUE_PRESENT_INVARIANT_VIOLATION` stays loud); race tests are barrier-driven (no sleeps) and red-first proven, with env-knob reproducibility on every nondeterministic test.
  2. Recovery-walk suites run green on Windows, macOS, and Linux CI lanes — fresh-clone, cold storage ON, tier labels intact.
  3. The Windows/macOS walk-lane portability list is documented (CloudflareWARP adapter = environmental, distinct per-node base paths, poll predicates, gtest filter grammar) so the three-platform lanes stay reproducible run over run.

**Plans**: 1/5 plans executed defined (research + patterns complete 2026-11-19 — anchors verified at SuperGenius `d2f2a7dec`; 11-case matrix X1–X11 adopted within D-03's budget; B2 push-topology default with checkpoint veto)

Plans:
**Wave 1**
- [x] 19-01-PLAN.md — TRACER: the serve-side interrupt seam (`kInterruptAfterEvidenceConsult`/`kInterruptBeforeRehydrate`/`kInterruptAfterColdFetch` on GraphsyncDAGSyncer, TxPruner-family shape) + the `cold_cross_feature_fault_race_test` sibling born red — X1 evidence-lands-mid-consult + X2 in-flight-cold-get, fault arms + NoEvidence controls + real-thread barrier legs, resurrection-test link set, Tier-1 registration (D-01/D-02/D-03/D-04/D-05/D-07)

**Wave 2** *(blocked on Wave 1 — shared file: test/src/crdt/cold_cross_feature_fault_race_test.cpp)*
- [ ] 19-02-PLAN.md — the erase arm: X3 durability-flip vs cold gate + X8 rehydrate-vs-second-erase (the lost-last-copy pair) + X5 erase-mid-walk-visit (skip-never-partial, no peer re-fetch), all on landed TxPruner seams (D-01/D-03/D-04/D-05/D-08)

**Wave 3** *(blocked on Wave 2 — shared suite file)*
- [ ] 19-03-PLAN.md — the recovery arm: X4 GC-eviction mid-restore + X6 downgrade-arms mid-walk + X7 exemption-vs-concurrent-prune with embedded fail-closed controls + X9 budget-vs-terminality asserted at exactly `kForcedWalkPeerFailoverPerCid` and one past, under seeded jitter (D-01/D-03/D-04/D-07/D-08)

**Wave 4** *(blocked on Wave 3 — shared suite file; X10 audits all prior cases)*
- [ ] 19-04-PLAN.md — X10 suite-end audit walk + counter teeth (byte-flip) + zero-CID baseline + X11 the ONE full-wire two-GlobalDB refusal-failover-under-concurrent-erase leg, Tier-1 default with the two-green-dispatch promotion contract armed (D-01/D-03/D-04/D-06/D-10)

**Wave 5** *(blocked on Wave 4 — evidence cites the complete matrix; blocking user checkpoint)*
- [ ] 19-05-PLAN.md — TEST-03 closure: Tier-1 fail-closed lane steps in build-release-tags.yml (shape A; B2 push-topology posture — cmake.yml untouched, B1 recorded as declined with veto offered) + the `notes/19-cross-feature-fault-race-three-platform-capstone.md` rulings doc (matrix table, quarantine table Q1–Q7, D-14 portability runbook, D-11 both-lanes reading, X11 promotion record) + the refreshed `19-FRESH-CLONE-CHECKLIST.md` + the D-15/D-16 per-platform evidence checkpoint (D-09/D-10/D-11/D-12/D-13/D-14/D-15/D-16)

## Progress

**Execution Order:** Phases 13 → 14 → 15 → 16 → 17 → 18 → 19 (Phase 14 implementation may start in parallel with Phase 13 — different files; test evidence finalizes on the merged line)

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 13. Bootstrap Branch Merge & Composition Baseline | 4/4 | In Progress|  |
| 14. Durability-Gated TxPruner Eligibility | 3/3 | Complete    | 2026-11-16 |
| 15. Evidence-Aware Cold Serving & Forced-Walk Recovery | 3/3 | In Progress|  |
| 16. TxPruner × GC Composition Hardening | 3/3 | In Progress|  |
| 17. Seal Growth Measurement & Decision | 3/3 | In Progress|  |
| 18. Role Downgrade, Collectibility Policy & GC Walk-Gap Exemption | 4/4 | Complete    | 2026-11-19 |
| 19. Cross-Feature Fault-Race Matrix & Three-Platform CI Capstone | 1/5 | In Progress|  |

---
*Roadmap created: 2026-10-19 (v1.0) — v1.1 phases added 2026-10-22, shipped & archived 2026-11-10 — v1.2 phases added 2026-11-13 — rocksdb-backup workstream*
