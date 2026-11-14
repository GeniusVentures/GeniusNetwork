# Domain Pitfalls: v1.2 Cold-Storage Archive Integration (rocksdb-backup)

**Domain:** Tiered archive/light-node semantics on an append-only CRDT ledger (SuperGenius GlobalDB + sgns-blockstore cold tier + develop's TxPruner)
**Researched:** 2026-11-13
**Mode:** Ecosystem/feasibility hybrid (pitfalls focus)
**Overall confidence:** HIGH for system-specific pitfalls (grounded in v1.0/v1.1 archived artifacts, develop v1.2 phase artifacts 16–20, and the 2026-11-13 develop-merge gap note); MEDIUM for external-precedent analogies (BIP-159, Kubo, go-ds-crdt upstream — verified against official sources)

**Scope of "phase" labels below** (suggested mapping for the roadmapper; work-item numbers from `develop-merge-erase-vs-cold-storage-gap.md`):

| Label | Work item |
|-------|-----------|
| P1 — Durability gate | #1 durability-gated TxPruner eligibility on cold nodes |
| P2 — Archive serving | #2 archive serving from cold (evidence refusal vs re-warm serve) |
| P2b — Forced-walk composition | #6 fix/trust-genesis-bootstrap merge (verify + test, don't build) |
| P3 — Pruner composition | #3 TxPruner × v1.1 GC composition |
| P4 — Cold collectibility | #4 cold-tier collectibility / role downgrade |
| P5 — Seals | #5 seal growth/capacity |
| P6 — Hardening | cross-cutting: fault races, soak, CI portability |

---

## Pitfall Table

| # | Pitfall | Warning sign | Prevention | Phase |
|---|---------|--------------|------------|-------|
| 1 | **Erase-then-serve evidence race** — serve path answers a CID from cold while local `/prune/` evidence says PRUNED (node masquerades as archive for data it declared irrelevant), or refuses data it should serve because evidence and bytes were read in the wrong order | Any serve/walk code calling `LocalBlockStore`/`S3BlockStore` `Get` directly instead of through the `CanRestoreElement`-guarded seam; flaky tests where served bytes exist after an erase crash-window; log line "served pruned CID" | ONE verdict function: hot presence → prune evidence (`PrunedLookup`, value-probe-before-marker per 19-05 Pitfall 8) → cold presence, with **evidence beats bytes**: PRUNED ⇒ clean history-pruned refusal (SURV-02 vocabulary) even if hot/cold bytes exist. `CanRestoreElement` is the only gate to re-warm. Red-first counter-test: cold-resident CID + PRUNED evidence MUST refuse | P2, P2b |
| 2 | **Durability-gate TOCTOU** — TxPruner marks a block erasable from evaluator-time reads; drainer/durability state changes underneath before the erase batch commits (or someone accepts `Accepted` as "durable enough"), leaving the only copy mid-upload | Eligibility code comparing durability via `<=`/numeric level or reading `GetPendingUploads` directly instead of the library's `kEvictionDurabilityGate`-gated accessor; tests that fake `Durable` by setting a status field without flush evidence | (a) Re-check `Durable` **inside the EraseEntry compose lock** immediately before staging (delete-time heads-recheck precedent, cancel-keep-bytes); (b) durability monotonicity invariant — `Durable` never regresses; re-verify after corruption heal must not downgrade; (c) fail toward **under-erase** (skip this cycle) on any doubt; (d) reuse the v1.1 enum exactly — no second gate | P1 |
| 3 | **GATE-01 loosening** — adding cold-node eligibility quietly widens `NodeType::Light`-only TxPruner gating; a misconfigured archive node erases history it exists to keep | The fail-closed enum check in the prune timer path accepting any node with a `blockstore` section; config-resolution code mapping "cold enabled" → "pruner eligible" without an explicit role policy knob | Keep GATE-01 fail-closed; the new rule is a named conjunct: `NodeType::Light OR (archive_role_enabled AND cold_durable_evidence AND stricter_policy)`, default off, resolved values INFO-logged (GATE-06 shape). Cold nodes get their own policy knob — never inherit Light's spend-recency window silently | P1 |
| 4 | **Double-prune interleavings** — TxPruner cycle and GC pass both touch set rows (`/crdt/s\|t/k`, `v/p`), block bytes, `DeleteCIDBlock` LRU, and map entries in overlapping windows; one system's crash-window analysis never modeled the other running concurrently (also: deleting RocksDB bytes without evicting the in-memory LRU leaves "erased" bytes servable from memory) | Two independent code paths both calling `StageBlockRemoval`/`removeNode` chain; a hot-cleanup helper that deletes store bytes but not the LRU entry (or vice versa); GC pass aborting on heads-change while TxPruner continues into the same keyspace | Single-writer discipline: either ONE shared hot-cleanup executor (owning set-rows+block+LRU+map in the sanctioned order, seals and both marker namespaces excluded) with two callers, or hard mutual exclusion of GC pass and TxPruner cycle (the 261029-uj0 GcPassOnce serialization fix is this exact class). Every half idempotent (D-16). Barrier-driven interleaving tests asserting legal end-states only | P3 |
| 5 | **Marker-namespace crossfire** — GC hot-cleanup sweeps disposed markers/tombstones into TxPruner's `/prune/` namespace (or the reverse); prefix scans with wrong granularity eat sibling namespaces (`GetKeysPrefix` carries no trailing slash; elems namespace is a SIBLING of the k-namespace under the set root — empirically pinned in 11-02) | Any new cleanup code building prefix strings by concatenation; tests asserting "only these rows touched" via substring match instead of exact prefix enumeration | One marker-key builder per namespace (marker-key homes are `PruneEligibility` and the GC module — no third); prefix-spy hot datastore (Phase 11 instrument) reused for exact-key assertions; GC-02 invariant test extended: tombstones, disposed markers, AND `/prune/` markers byte-identical across a TxPruner run | P3 |
| 6 | **Recovery storm / non-terminal failover** — forced walk re-fetches what peers pruned: per-CID failover rotates the whole peer set, every peer answers SURV-02 refusal, walk retries forever (or worse: silently SKIPS the missing ancestor and validates a partial history as complete) | Failover retry without an exhaustion budget; walk code that `continue`s past a missing-from-every-tier link; walk tests with only the happy mesh | (a) Per-CID peer-failover budget → terminal distinct error on exhaustion (18-01 terminality + 19-07 per-CID failover shapes); (b) walk-gap abort semantics imported from GC: any ancestry link missing from hot+cold+peers ⇒ abort the walk with zero decisions — **never skip-and-continue**; (c) bound concurrent re-warms with explicit backpressure (bounded queue, own thread — the twice-proven drainer pattern; never `io_`, never the pubsub context); (d) test: pruned mesh + archive node ⇒ walk completes via cold; pruned mesh + NO archive ⇒ walk aborts terminally (failover-counter assertion, no loop) | P2, P2b |
| 7 | **Role-downgrade data loss** — archive node GC-evicts hot (cold-backed), operator downgrades/removes `blockstore` config, TxPruner erases hot for spent history, later cold bucket is collected/deleted: this node — possibly the LAST archive node — permanently loses history it promised to keep | Cold collectibility keyed on retention age alone; a downgrade path that silently disables the durability gate (no cold store ⇒ gate passes vacuously); config removal orphaning a `LocalBlockStore` with no ledger of what it holds | (a) Cold objects are collectible ONLY against local `/prune/` evidence — never by age (Bitcoin pruned→full is a one-way door; Kubo `repo gc` unpinned deletion is permanent); (b) gate fails CLOSED on downgrade: no cold store reachable ⇒ no erase of data whose only copy was cold; (c) collect step refuses anything without prune evidence; (d) destructive-op warnings + one-way-door documentation (Kubo `repo verify --drop` precedent); (e) last-archive-node is unknowable locally — document as operational warning, not code | P4 |
| 8 | **Seal explosion at archive scale** — seals are O(all processed CIDs), hot forever, now ALSO the forced walk's ancestry index; billions of tiny keys degrade compaction, prefix scans, boot, and walk enumeration. Compounding: the deferred v1.1 eviction-storm crash was found only at soak scale (~2000 marks) — toy-scale conclusions about growth are untrustworthy | Capacity claims from fixtures with <10⁴ seals; any v1.2 phase proposing to spill/compact seals in the same milestone that makes them load-bearing for recovery; bulk seal sweeps holding locks shared with the erase compose lock | P5 is **measure-and-decide, not build**: quantify bytes/CID, growth vs block bytes, enumeration cost at 10⁶/10⁷/10⁸ seals; if compaction is needed it is a separate milestone, additive (sidecar/CF), never in-place `<cid>sealed` mutation; GATE-03 ban (`"sealed"` literal in production src/) stays intact; seals-are-the-index cost model feeds the walk's bound | P5 (bounds feed P2b) |
| 9 | **Responder freeze re-armed** — "the node has it cold, just serve it inline": any synchronous cold consult from the graphsync responder (single-threaded pubsub io_context) or any wait under `dagMutex_` in the serve path freezes the whole node | New cold-store `Get` calls reachable from `graphsync_impl.cpp` responder context; serve-path latency correlating with s3d state; the never-blocking guard test failing on outage cases | Archive serving MUST reuse the async re-warm executor pattern (09-02 D-05: never wait/sleep/lock-across-I/O on the pubsub context); the cold chain lives in `GraphsyncDAGSyncer` outside `dagMutex_`; re-pass the whole-node-freeze regression test on every serve-path change | P2 |
| 10 | **Rederiving instead of composing the bootstrap branch** — fix/trust-genesis-bootstrap composition is "nearly free" (`retained ? GetStoredNode : getNode` where `getNode` IS the Phase-9 cold seam); the trap is rebuilding walk logic, or resolving the forecast `GeniusNode.cpp` merge conflict by hand-editing and drifting | New walk/fetch logic outside the branch's own module; merge conflict in `GeniusNode.cpp` resolved by rewriting rather than taking both sides; tests that don't observe fetch ORDER | Composition-only guard: grep gate for new fetch orchestration outside the sanctioned seam; verify cold-before-peer ordering observably (S3 fake hit recorded before any peer dial); merge checklist for `GeniusNode.cpp` (the only forecast conflict) | P2b |
| 11 | **Under-erase direction confusion** — v1.1's safe direction was under-EVICTION (remote copy exists); the cold-node TxPruner inverts the risk: wrongly NOT erasing is merely disk; wrongly erasing non-durable data is data loss — but Light-node semantics (no cold) is safe-by-definition. One predicate must encode both roles explicitly | A single fused eligibility arithmetic mixing spend-recency window and durability conjuncts; test names that assert "bytes gone" without asserting which copy (hot vs cold) is gone | Named-arm predicate: erase eligible iff `prune_eligible(tx) AND (no_cold_tier OR cold_durable(cid))`; each arm's failure direction tested; when develop's Phase 17 (spend-recency window) lands, the cold conjunct stays separate, not folded into the window math | P1, P3 |
| 12 | **Crash-window drift across THREE stores** — erase used to be one hot WriteBatch (marker joins batch ⇒ evidence/bytes atomic). Durability-gated erase spans hot RocksDB + cold-tier evidence; cross-store is necessarily two idempotent halves (D-16), and the cold collect step adds a third step — every intermediate crash state must be enumerated and land on keep/under-erase | Tests that crash only at "mid-batch" of one store; a new cross-store write batch (forbidden — Pitfall 3 of 11-02); invariant-violation states (e.g., evidence PRUNED but value still present) treated as warnings instead of loud errors | Extend the 13-case barrier-driven fault-race matrix to the new seams; `VALUE_PRESENT_INVARIANT_VIOLATION` stays a loud error (17-05), never downgraded; boot-time reconciliation (journal crash-restart precedent; upstream go-ds-crdt added abnormal-shutdown repair for the same class) | P1, P4, P6 |

---

## Cross-Feature Interaction Risks

These are composition hazards no single feature's phase artifacts cover. Each needs an owner phase and a dedicated test.

### A. GC walk × TxPruner-erased blocks × cold collectibility (the poisoned-GC triangle) — **P3/P4, highest-severity interaction**

The GC pass computes reachability by a fresh full walk with **unconditional traversal** (11-01 D-05: no `isResolved` skips). On a mixed node (archive role, TxPruner active):

1. TxPruner erases a block's hot bytes (cold-Durable-backed) → GC walk reaches it → Phase-9 cold chain serves it → walk continues. **Works today.**
2. Role policy later makes that cold object collectible → cold deleted → next GC walk hits the same link missing from hot AND cold → **walk-gap abort with zero candidates** (11-02: "reachability is not computable") → **GC liveness permanently broken**, every future pass aborts.

Prevention: GC's walk-gap rule needs an evidence-carved exemption — a link with local prune evidence is *expected-absent*, not walk-blocking. This exemption must be designed with P4's collectibility policy (they are two halves of one rule: "what may be absent" must equal "what may be collected"). If P4 ships without the exemption, the first cold collection bricks GC on that node.

### B. Forced walk × serving × refusal verdict ordering (nondeterministic consultation order) — **P2/P2b**

A visited CID can now resolve four ways: hot-serve, cold-re-warm-serve, peer-fetch, history-pruned-refusal. If different call sites consult the tiers in different orders (walk vs graphsync responder vs local read), the same CID yields different behavior per path — flaky tests, unpredictable network traffic, and peers observing inconsistent answers from one node. Prevention: one total, deterministic consultation order documented at the `CanRestoreElement` home, all three call sites routed through it.

### C. Durability gate × GC eligibility sharing one evidence source — **P1/P3**

Both gates consume `GetDurableWithSpillTime`-class evidence under `cold_store_mutex_`. If TxPruner's re-check-at-erase (Pitfall 2) and GC's mark-time read race on the same record, the two destructive systems can hold contradictory beliefs about one CID simultaneously. Prevention: P3's single-writer/mutual-exclusion ruling must cover durability **reads** used for destructive decisions, not just writes.

### D. Re-delivery dedup × walk retrievability — **P2/P3**

GC's disposed-marker dedup drops re-delivered blocks at `HasBlock` with zero S3 traffic (correct for eviction). But a forced walk that *needs* that CID must not be short-circuited by the dedup marker ("we disposed this" ≠ "this is unobtainable" — cold still has it). Prevention: walk reads bypass/go below the dedup point, or dedup consults prune evidence (drop) vs disposed marker (consult cold). Test: disposed-marker present + walk requests the CID ⇒ cold restore happens.

### E. develop Phase 17 landing mid-milestone — **P1**

Eligibility dry-run/spend-recency window (PRUNE-01/03, GATE-01/04/06) is still Pending on develop. If it lands during v1.2, the evaluator's window arithmetic changes underneath P1's durability conjunct. Prevention: keep the cold-durability conjunct a separate predicate argument the evaluator composes, so 17's landing is a merge, not a rewrite; re-run the composition tests when it lands.

### F. Forced walk × seal enumeration at scale — **P2b/P5**

The walk's ancestry index is the seal set; at archive scale every step of the walk pays seal-enumeration cost. If P5's measurement shows bad scaling, the walk bound (already opt-in bounded) may need a tighter default and the walk must remain abortable per-step. Ordering recommendation: P5's measurement should land **before or with** P2b's walk tests so walk bounds are set against real numbers, not guesses.

---

## Testing Traps

1. **Fakes must model evidence and durability, not just bytes.** The existing `MemoryBlockStore`/S3 fake prove the bytes contract; evidence-based refusal needs a tri-state-aware fabric: tests must be able to place cold bytes and `/prune/` evidence **independently** (cold bytes + PRUNED = inert bytes; no evidence + cold bytes = restorable history; malformed marker = loud error, never silent — 17-05). Reuse `WritePrunedEntryForTest` verbatim as the one marker writer (19's hard invariant 2: no second enum, no hand-built marker keys). A naive bytes-only fake makes the wrong semantics *pass*.

2. **The refusal test matrix is a product, not a case list.** {hot present, absent} × {cold present, absent} × {evidence: none, PRUNED, malformed} × {serve request, walk visit, erase-gate check} — with assertions that refusal ≠ not-found (SURV-02 vocabulary) and evidence-beats-bytes in every cell. Ship the matrix in the tier that owns P2; cells that can't legally exist assert the invariant-violation path fires loudly.

3. **Crash-window tests must enumerate the new cross-store windows.** The single-store interrupt hook (`SetEraseInterruptHookForTest`, steps 1–3) covered one batch; durability-gated erase adds hot-vs-cold-evidence and collect steps. Use barrier latches (WindowGate/TimingS3Client pattern), not sleeps; every window lands keep/under-erase; assert sibling byte-identity (16-VERIFICATION pattern) and seal presence after every interruption.

4. **Race tests for the new interleavings, red-first.** erase×serve (Pitfall 1), TxPruner×GC (Pitfall 4), walk×prune-refusal (Pitfall 6) — write the counter-test failing-first (the v1.1 resurrection suite found a real `InElemsNotTombstoned` defect precisely because it was failing-first). Zero-Corrupt-from-race assertions must not weaken CID verification (`EquivalentCidClaim` stays in force; deltas are CIDv0/DAG_PB — fixtures must use real delta blocks).

5. **CI portability for recovery walks (Windows/macOS lanes).** N-node walk topologies are the flakiest class in the repo. Known landmines to design around: CloudflareWARP adapter (100.96.0.1) breaks local Windows pubsub suites (environmental, A/B-verified — document in the runbook so nobody chases it as a regression); zombie `cl.exe` and RocksDB `LOCK` fixture-dir contention on Windows (killed-stray hygiene + distinct base path per node per test — the existing `addNode` recipe); macOS needed explicit `GcPassOnce` serialization (the same discipline P3 formalizes); wall-clock waits (25 s) on starved runners — poll predicates, never fixed sleeps; gtest filter grammar is positive-negative with ONE dash (`*-A:B:C`).

6. **Tier discipline for network-dependent walk tests.** Hermetic (fake cold, Tier-1 fail-closed lane) vs real-pubsub N-node walks (labeled Tier-2 lane or dedicated integration lane with the tier-label audit). `ctest -L` never `-LE`, `--no-tests=error`, label-count audit with proven teeth — extend, don't invent.

7. **Env-knob reproducibility contract on every nondeterministic test** (jitter seeds, iteration counts, walk bounds) — the v1.1 norm; walk tests with peer-failover timing are nondeterministic by construction.

8. **Soak before capacity/scale conclusions.** The deferred v1.1 hardening item (GC eviction-storm crash at ~2000-mark scale, repro: retention ~1 ms + ~2000 Durable orphans) proves toy fixtures hide storm-class bugs. P5's seal conclusions and P6's composition claims need soak-scale evidence trios (runbook + run-capture + status-capture) before any "acceptable growth" verdict.

9. **Masquerading counter-tests both directions.** (a) Archive node with cold bytes + PRUNED evidence refuses (never serves inert bytes); (b) pruned-hot + cold-resident + NO evidence serves via re-warm (never refuses history it holds). BIP-159's no-masquerading rule (a pruned node MUST NOT signal/act as a full-history server) and its fingerprinting counter-measure (don't leak prune depth — refusal shape should not encode the watermark) both deserve named tests.

---

## Phase-Attributable Priorities (for requirements as negative constraints)

- **P1** must encode: never erase what isn't evidence-Durable (TOCTOU re-check under compose lock); gate fails closed on missing cold store; GATE-01 not loosened; under-erase is the safe direction.
- **P2/P2b** must encode: evidence beats bytes, one verdict path, `CanRestoreElement` is the only restore gate; responder never blocks; walk-gap ⇒ abort never skip; peer-failover is budgeted and terminal; composition-only for the bootstrap branch.
- **P3** must encode: single writer or mutual exclusion; seals never deleted by either pruner (GATE-03 + keep-seal `7961ec264`); both marker namespaces immune to the other's sweeps; every half idempotent.
- **P4** must encode: cold collectibility only against prune evidence, never age; downgrade is a one-way door, loudly documented; the GC walk-gap exemption (Interaction A) ships with or before the first collection capability.
- **P5** must encode: measure-and-decide; no in-place seal mutation; soak-scale evidence before verdicts.
- **P6** must encode: the extended fault-race matrix, three-platform fresh-clone CI proof with cold storage ON, and the Windows/macOS walk-lane portability list above.

## Sources

**Internal (HIGH confidence — archived phase artifacts and verified codebase seams):**
- `.planning/workstreams/rocksdb-backup/notes/develop-merge-erase-vs-cold-storage-gap.md` (2026-11-13) — tiered-node model, develop v1.2 erasure inventory, bootstrap-branch analysis (`CanRestoreElement`, forced walk), candidate work items 1–6, WARP environmental note
- `SuperGenius/.planning/REQUIREMENTS.md` — v1.2 light-node pruning requirements (PRUNE/GATE/SURV/RECL + non-goals table: no pruning on full/archive nodes, no light nodes serving historical sync, tombstone-deletion forbidden) and v1.3 out-of-scope boundary
- `SuperGenius/.planning/phases/17-*/` (PrunedLookup tri-state, marker contract, dry-run zero-write gates), `18-*` (compose-lock, sanctioned-caller-set greps, EraseEntry four-step), `19-*` (tri-state lookup value-before-marker ordering, refusal/failover/redelivery test shapes, SURV-02/03)
- `SuperGenius/test/src/crdt/globaldb_erase_test.cpp` — EraseNodeCollection topology, seal-key/block-key raw contracts, interrupt-hook crash windows, redelivery/refusal test shapes
- `.planning/workstreams/rocksdb-backup/milestones/v1.1-phases/08–12` — dagMutex_/io_context discipline (09-RESEARCH §1), D-16 two-half eviction, under-eviction direction, heads-recheck, `EquivalentCidClaim` CIDv0 tracer finding, GetKeysPrefix sibling-namespace pinning, 13-case fault-race matrix, disposed-marker dedup
- `.planning/workstreams/rocksdb-backup/RETROSPECTIVE.md` + `STATE.md` — v1.0/v1.1 lessons incl. Windows/macOS CI landmines, eviction-storm soak finding, GcPassOnce serialization quick-task

**External (verified against official sources):**
- BIP-159 `NODE_NETWORK_LIMITED` (bitcoin/bips, official) — pruned-peer signaling, 288-block guarantee, MUST-NOT-masquerade rule, prune-depth fingerprinting counter-measure, 144-block reorg buffer — **HIGH**
- IPFS/Kubo official docs (persistence/pinning; CLI `repo gc`, `repo verify`, `files --flush=false`) — GC removes unpinned content permanently; documented GC-vs-unflushed-write race; destructive-op warning shape — **HIGH**
- go-ds-crdt GitHub repo (official, v0.6.8 ~2026) — add-wins OR-set semantics; purge support only recently added (`PurgeDAG` #341) with an inverted-`ErrNotFound` bug fixed in `purgeKeyBlocks` (#344); abnormal-shutdown repair added — upstream purge paths are young and bug-prone; our erase must keep not-found idempotent-legal while malformed-evidence is loud — **MEDIUM**
- RocksDB wiki `DeleteRange` (official) — range tombstones reclaim space only via compaction; `bottommost_level_compaction=kForce` for real reclamation (RECL-01/RECL-02 shape) — **HIGH**
- geth freezer/snap-pruning TOCTOU — **not verified this pass** (docs page moved/404); treat any Ethereum-analogy claim in later phases as LOW until re-researched

**Gaps to address in phase-specific research:**
- Exact current durability-state machine transitions on `dev_blockstore` post-merge (can any path regress Durable→Accepted today? Needs code read in P1 planning, `AdvanceDurabilityOnce`)
- Whether develop's Phase 17 (eligibility dry-run/spend-recency) and Phase 20 (disk reclamation proof) land before v1.2 P1 — composition vs rebase decision
- Seal key/value sizes and current counts at real deployment scale (P5's first measurement task)
