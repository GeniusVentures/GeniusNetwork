# Project Research Summary (v1.2 Cold-Storage Archive Integration)

**Workstream:** rocksdb-backup · **Milestone:** v1.2 "SuperGenius Cold-Storage Archive Integration"
**Researched / Synthesized:** 2026-11-13
**Inputs:** `.planning/research/{STACK,FEATURES,ARCHITECTURE,PITFALLS}-v1.2-rocksdb-backup.md` + seed note `.planning/workstreams/rocksdb-backup/notes/develop-merge-erase-vs-cold-storage-gap.md`

v1.2 layers **tiered-node archive semantics** onto the validated v1.0/v1.1 cold-storage stack: archive/cold nodes (hot RocksDB working set + S3/s3d cold tier, complete history, never erase) and light/pruned nodes (TxPruner local hot erase with node-local `/prune/` evidence), joined by one availability invariant — anything a light node prunes must always remain obtainable from archive/cold nodes (BIP-159 precedent). Prior art does not have our shape: a node-local second tier makes hot erasure *reversible in bytes but not in semantics*. That inversion yields the milestone's governing principle, which no prior system supplies and all four research files converge on: **evidence outranks bytes, node-locally** — prune markers decide serve-vs-refuse and restore-vs-skip; cold bytes alone are never authoritative.

The recommended approach is unambiguous: **zero new dependencies**. Every v1.2 feature (durability-gated TxPruner eligibility, evidence-aware archive serving, TxPruner×GC composition, policy-only cold collectibility, seal growth assessment, the `fix/trust-genesis-bootstrap` merge) composes capabilities already in the pinned stack (RocksDB 9.4.0, vendored ipfs-lite-cpp graphsync + extensions, libp2p fork identify, minio-cpp 1.0.0 / s3d v0.2.1, protobuf 7.34.0). The work is contract/protocol-shape and policy decisions at existing seams, not dependency decisions. Key risks are semantic rather than technological — masquerading, durability TOCTOU, pruner-vs-pruner interleavings, responder freezes — and every one has a concrete, source-verified prevention. Posture throughout: fail toward under-erase, keep evidence node-local, never block the pubsub responder, sequence (don't unify) the two pruners.

---

## Key Findings

### Stack Additions

**Zero new libraries.** Every NEW v1.2 need maps to an existing pinned mechanism:

| Feature | Mechanism (all existing, source-verified) |
|---|---|
| Durability-gated TxPruner eligibility | `ColdStorageManager::GetUploadState` + `kEvictionDurabilityGate` consulted from `RunCycle`'s block-group filter; hot erase via the existing atomic `EraseEntry` WriteBatch |
| Archive serving + evidence refusal | `FetchNodeFromColdStorage` / `ColdServeDagService` policy refinement + existing graphsync `ResponseStatusCode` vocabulary + **extensions** wire map (metadata-extension precedent); role advertisement = second protocol string in the existing `setProtocolHandler` list + libp2p identify (BIP-159 analog) |
| TxPruner × GC composition + reclamation | Same hot RocksDB 9.4.0 `CompactRange` (`bottommost_level_compaction = kForce`) already specified by RECL-01/02; sequencing coordination in ColdStorageManager/GlobalDB |
| Cold-tier collectibility | Node-local policy + (only if ever permitted) explicit `S3Client::Delete` (SPI already exists); **no** s3d/S3 lifecycle dependency |
| Seal growth / capacity | Measurement probe + accept-and-document; seals stay in vendored hot RocksDB (`<cid>sealed` string keys, never deleted per GATE-03) |
| fix/trust-genesis-bootstrap merge | Pure git merge; lands on the existing Phase-9 cold-read seam |

**Critical version holds:** RocksDB stays pinned **9.4.0** (full `CompactRangeOptions` surface already in-tree; a bump invalidates v1.0/v1.1 evidence for zero gain); s3d stays **v0.2.1** (upstream lifecycle/Object Lock unverified at our pin and cannot express evidence-driven per-CID collectibility); **no vendored ipfs-lite-cpp edits** (seal CF rework / `removeSeal` / seal spill are the out-of-scope boundary); **no compaction-filter deletion and no `DeleteRange`** — evidence-driven point deletes in one atomic batch + janitor compaction only.

### Feature Table Stakes

Must-ship (FEATURES TS-1..TS-8 — the tiered model is broken or dishonest without them):

| ID | Feature | Complexity |
|---|---|---|
| TS-1 | Durability-gated TxPruner eligibility on cold nodes — "never erase what isn't evidence-Durable in cold"; fail closed; markers written atomically with the hot erase | MEDIUM |
| TS-2 | Pruned-vs-evicted serving semantics (`CanRestoreElement` composition — **the milestone's semantic core**: evidence outranks bytes) | MEDIUM-HIGH |
| TS-3 | Seals survive both pruners; both erase orders converge to one fixed point | MEDIUM |
| TS-4 | Role-consistent uniform serving (never "sometimes gone depending on local disk state") | LOW-MEDIUM |
| TS-5 | Availability-invariant E2E: pruned light node bootstrap/sync served by a cold archive node (mesh test) — the headline safety claim | MEDIUM |
| TS-6 | Bootstrap composition: verify + test the forced-walk merge, don't build | LOW |
| TS-7 | Role/policy coherence in config (tri-state discipline; cold nodes get their own knob — never inherit Light's spend-recency window silently) | LOW |
| TS-8 | Per-cycle observability for the new gates (durability deferrals, evicted-vs-erased answers, re-warm-on-serve, seal rows) | LOW |

Differentiators (choose deliberately): **D-1** seal measure+model+decide (recommended in scope; compaction is a future milestone); **D-2** cold collectibility as policy+guardrails only (machinery = contract-v2); **D-3** cold health spot-audit, PoSt analog (strong candidate this milestone or next); **D-4** revocable-prune invariant (design in now — evidence revocable only by local operator act — ship the restore operation later).

Anti-features (do NOT build): network-wide CRDT tombstone deletion (AF-1); automatic cold-tier deletion via S3 lifecycle (AF-2); network-authoritative prune evidence (AF-3); light nodes serving historical sync (AF-4); ungated hot erase on cold nodes (AF-5); seal spill/compaction through the blockstore or seal deletion ever (AF-6); auto role-downgrade / watermark-driven collection (AF-7); trust-bytes-if-present restore bypass (AF-8).

### Architecture Integration Map

Source-verified seams (file:line detail in ARCHITECTURE research):

- **Durability gate** lives in `TxPruner::RunCycle`'s block-group work-list filter (`TxPruner.cpp:147-185`) — **not** in `PruneEligibility::Evaluate` (contractually pure, D-C6). The `GlobalDB::GetColdUploadState` bridge is lifecycle-safe and already exists. Gate shape mirrors GC's consumption of `kEvictionDurabilityGate`: **Durable permits; NoRecord/Pending/Accepted defer; Unreadable defers loudly (MI-02 — never healthy-by-omission)**. Report as a `cold_deferred_groups` counter, not a failure reason (the journal can advance to Durable and the next cycle re-evaluates).
- **Evidence-aware cold chain**: refusal predicate sits in `FetchNodeFromColdStorage` (`graphsync_dagsyncer.cpp:750-806`) after the cold `Get`, before `Rehydrate`; owned by **GlobalDB** (which owns both the raw store and the marker namespace) and injected into `ColdReadService` at the existing `OpenColdStorageStack` seam. Refusal must be a distinct classification (SURV-02: history-pruned ≠ not-found), never folded into `CID_NOT_FOUND`. New but small: per-block **`/prune/blk/<cid>` markers** staged in the same erase batch (tx markers are per-`<hash>`; refusal points are per-CID) — key-shape home in `PruneEligibility` (D-C1). Archive/Full nodes never have markers (GATE-01), so the predicate is vacuously false there — serving unchanged.
- **Pruner composition: DO NOT unify — sequence + close the LRU window.** The two pruners have different guards, evidence, and recovery semantics; both are idempotent on absent keys; the reverse order (TxPruner-then-GC) is safe by construction (heads re-check D-14). Concrete items: post-commit `DeleteCIDBlock` in `EraseEntry`; document that GC-disposal starves TxPruner (journal gone → `NoRecord` → group deferred forever — under-prune, the safe direction for v1.2; a `DisposedDurable` journal state is the v2 option).
- **Forced walk post-merge**: fetch is `retained ? GetStoredNode : getNode`, and `getNode` IS the Phase-9 cold chain (cold before peers, offline-capable, CID-verified). Rehydrate is bytes-only — **never seals** (a crash-window block must stay re-mergeable); the walk owns sealing after successful replay. Re-warm re-journals `PendingUpload` → the drainer converges `alreadyPresent` (harmless; assert in recovery-at-scale tests).
- **Role model**: cold storage is gated by the `blockstore` config section, independent of `NodeType` — a Light+cold node is constructible today, exactly the tiered-light role v1.2 formalizes. Downgrade = restart with `node_type=light`; the composed flow (archive-era Durable records → gate permits → markers accumulate → refusal activates) is already buildable from shipped pieces.
- ARCHITECTURE §3's five data-flow diagrams (evidence-aware read, gated erase cycle, pruner interleavings, forced walk on cold, downgrade timeline) should be used directly as plan-phase verification blueprints.

### Watch Out For

**⛔ Two discovered bugs (verified against source; v1.2 must fix both):**

1. **Cold-chain resurrection gap.** `getNode`/`GetNodeWithoutRequest` → `FetchNodeFromColdStorage` consults **no prune evidence anywhere**. On a Light+cold node, a TxPruner-erased CID is served + rehydrated from cold — the node *resurrects, hot, bytes it chose to erase*, undoing the light-node semantics the evidence encodes (AF-8 realized). Evidence-based refusal exists today only in the walk's element guard (`CanRestoreElement`, branch). Fix: make the general read path evidence-aware at the cold hook.
2. **Forced-walk GC-evicted conflation.** The branch's block-level skip rule `!retained && sealed` treats *any* missing sealed block as a prune boundary — conflating TxPruner-erased with GC-evicted. On a cold node, a **GC-evicted** ancestor (cold bytes present, remote Durable) is skipped as if pruned — exactly the history an archive node must restore from cold. Fix: split by evidence — cold-present (local cold / disposed marker / probe) → fetch via `getNode`; `/prune/blk` evidence → skip. Block-level skip bounds the walk; element-level `CanRestoreElement` remains the authority.

*(A third, smaller defect found during research, folded into composition hardening: the **stale-LRU window** in `EraseEntry` — guard 3 checks the LRU only at compose start while `GrabCIDBlock` can insert concurrently; fix is post-commit `DeleteCIDBlock`, mirroring GC's A6 ordering.)*

**⛔ Frozen constraint — cold collectibility is POLICY-ONLY this milestone.** The frozen sgns-blockstore v1 contract has **no Remove/Delete, ever** (CORE-05/06 permanence). Cold collectibility machinery is impossible without a library contract v2. v1.2 ships the *decision + guardrails* only: operator-initiated, checklist-gated role downgrade; config interlock preventing silent downgrade; the permanent-once-written invariant documented. Any deletion API is deferred to v2 alongside epoch-based deletion compaction.

**⛔ Poisoned-GC-triangle ordering constraint — collectibility and the GC walk-gap exemption SHIP TOGETHER.** GC computes reachability by unconditional full walk; a link missing from hot AND cold aborts the pass with zero candidates ("reachability is not computable"). TxPruner-erased + cold-collected + GC-walked = **permanently broken GC liveness**. The exemption (a link with local prune evidence is *expected-absent*, not walk-blocking) is two halves of one rule with collectibility: **"what may be absent" must equal "what may be collected."** No collection capability may land before the exemption (PITFALLS Interaction A — highest-severity cross-feature risk).

**⛔ Two external gates:**

1. **develop Phase 17 evaluator** (eligibility dry-run, spend-recency window) — still pending. TS-1/TS-3 composition is *designable* now but *executable* only against 17's evaluator shape. Mitigation: keep the cold-durability conjunct a separate predicate argument so 17's landing is a merge, not a rewrite (Interaction E); re-run composition tests when it lands. (Phase 20 reclamation timing matters to Phase 4 sequencing.)
2. **fix/trust-genesis-bootstrap merge** — still pending. All walk-related composition work depends on it landing first. Forecast: only `GeniusNode.cpp` conflicts (MEDIUM confidence until executed); CRDT seams auto-merge keeping our 4-term `HasBlock` and cold-chained reads. Post-merge verification gate: 4-term `HasBlock`, cold-chained `GetNodeWithoutRequest`, GATE-03 intact, cold-before-peer ordering observably.

**Top pitfalls with preventions** (full 12-row table + 9 testing traps in PITFALLS): erase-then-serve evidence race → ONE verdict function (hot → evidence → cold; evidence beats bytes) + red-first counter-test; durability-gate TOCTOU → re-check `Durable` inside the compose lock, monotonicity invariant, under-erase on doubt; GATE-01 loosening → named conjunct, default off, resolved-values logging, cold-node-specific policy knob; double-prune interleavings → single-writer or hard mutual exclusion, every half idempotent; marker-namespace crossfire → one key-builder per namespace, prefix-spy exact-key assertions; recovery storm → per-CID failover budget → terminal error, walk-gap ⇒ abort never skip-and-continue, bounded re-warm queue never on `io_`; role-downgrade data loss → collect only against prune evidence never age, gate fails closed on missing cold store, one-way-door docs; seal explosion → measure-and-decide not build, soak-scale evidence (the v1.1 eviction-storm crash appeared only at ~2000-mark scale); responder freeze → async re-warm executor only, never wait/lock-across-I/O on the pubsub context; under-erase direction confusion → named-arm predicate `prune_eligible(tx) AND (no_cold_tier OR cold_durable(cid))`; crash windows across three stores → extend the 13-case barrier-driven fault-race matrix, `VALUE_PRESENT_INVARIANT_VIOLATION` stays loud; rederiving the bootstrap branch → composition-only grep gate + `GeniusNode.cpp` merge checklist.

**Testing traps (condensed):** fakes must model evidence and durability, not just bytes — place cold bytes and `/prune/` evidence *independently* (cold+PRUNED = inert bytes; no-evidence+cold = restorable history; malformed = loud error); one marker writer (`WritePrunedEntryForTest`); the refusal matrix is a **product** — {hot} × {cold} × {evidence: none/PRUNED/malformed} × {serve, walk visit, erase-gate} — with refusal ≠ not-found in every cell; barrier latches not sleeps; red-first race tests; Windows/macOS walk-lane landmines (CloudflareWARP adapter is environmental — document, don't chase; distinct base path per node; poll predicates; gtest filter grammar one dash); tier discipline (`ctest -L`, never `-LE`, label audits with teeth); env-knob reproducibility on every nondeterministic test; masquerading counter-tests **both directions** (cold bytes + PRUNED evidence ⇒ refuses; pruned-hot + cold-resident + no evidence ⇒ serves via re-warm).

### Confidence Assessment

| Area | Confidence | Notes |
|---|---|---|
| Stack | HIGH | Every in-tree claim verified against pinned sources; MEDIUM only for upstream s3d lifecycle claims (not needed at our pin) |
| Features | HIGH (internal) / MEDIUM (external fetched) | BIP-159, ethereum.org, docs.ipfs.tech, docs.filecoin.io, postgresql.org fetched first-party and cross-checked; BitTorrent + EIP-4444 training-only (LOW, flagged); nothing LOW presented as authoritative |
| Architecture | HIGH | Every integration point verified against working tree or branch blob; only the merge-conflict forecast is MEDIUM (merge not yet executed) |
| Pitfalls | HIGH (system-specific) / MEDIUM (external precedents) | Grounded in archived v1.0/v1.1 artifacts + develop phases 16–20 + seed note; geth freezer analogy LOW-flagged (source 404 — re-verify before citing) |

---

## Implications for Roadmap

### Converged Phase Order

ARCHITECTURE's 6-step build order and PITFALLS' P1→P6 labels agree on substance. Two deltas to reconcile: (a) PITFALLS separates forced-walk composition (P2b) from archive serving (P2), where ARCHITECTURE splits it into "merge first, walk-refinement with serving"; (b) PITFALLS makes hardening an explicit phase (P6) where ARCHITECTURE distributes it. Converged proposal — **6 delivery phases with hardening woven in as exit criteria plus an explicit closing soak/CI gate** (make it a 7th phase if discrete phases are preferred):

| # | Phase | Converges | Delivers | Dependency gates |
|---|---|---|---|---|
| 1 | **Bootstrap branch merge + composition baseline** | ARCH-1 + P2b (first half) | Merge `fix/trust-genesis-bootstrap`; post-merge invariant verification (4-term `HasBlock`, cold-chained `GetNodeWithoutRequest`, GATE-03, cold-before-peer ordering observable); `GeniusNode.cpp` merge checklist; composition-only grep gate | **External gate: the branch itself.** Nothing walk-related is testable before this |
| 2 | **Durability-gated TxPruner eligibility** | ARCH-2 + P1 | Gate in `RunCycle` group filter via `GetColdUploadState`; TOCTOU re-check under the compose lock; GATE-01 widened as a named conjunct/policy matrix (cold nodes get their own knob, default off); `cold_deferred_groups` stats; Light+cold posture log | Code can start parallel to Phase 1 (different files) but tests finalize after it. **External gate: develop Phase 17 shape** — keep the cold conjunct separate so 17 landing is a merge, not a rewrite |
| 3 | **Evidence-aware serving + walk split — fixes BOTH discovered bugs** | ARCH-3 + P2 + P2b (refinement) | `/prune/blk/<cid>` markers in the erase batch; GlobalDB evidence predicate at the cold hook (kills the resurrection gap); distinct history-pruned refusal classification on read path + responder; walk `!retained && sealed` split into cold-restorable vs prune-evidenced (kills the conflation bug); refusal test matrix as a product; masquerading counter-tests both directions; deterministic consultation order (one total verdict order across walk/responder/local-read) | Phases 1 + 2 (walk present; tiered-light model established) |
| 4 | **TxPruner × GC composition hardening** | ARCH-4 + P3 | Post-commit LRU invalidation in `EraseEntry` (stale-LRU window); single-writer/mutual-exclusion ruling **covering durability reads used for destructive decisions** (Interaction C); interleave test matrix; marker-namespace crossfire guards; stranded-group documentation (under-prune accepted; `DisposedDurable` = v2) | Phase 2 (the gate defines the disposal-starvation interplay); marker infra from Phase 3 |
| 5 | **Seal growth: measurement + decision** | ARCH-5 + P5 | **Early probe** (bytes/CID, counts, enumeration cost at 10⁶/10⁷/10⁸ seals) feeding Phase 3's walk-bound defaults (Interaction F); **late decision record** citing real walk-recovery numbers; expected outcome: accept + document; CF/sidecar migration only as a measured trigger; soak-scale evidence before any verdict | Probe lands before/with Phase 3's walk tests; record closes the milestone — this reconciles ARCHITECTURE's "schedule late" with PITFALLS' "before walk bounds are set" |
| 6 | **Role downgrade + cold collectibility policy + GC walk-gap exemption** | ARCH-6 + P4 | Downgrade flow docs + E2E (archive-era Durable → gate permits → markers accumulate → refusal activates); collectibility = **policy + interlock only** (frozen BlockStore v1 contract); permanent-once-written invariant documented; **GC walk-gap evidence exemption designed/shipped here — collectibility and the exemption are two halves of one rule and ship together** | Phases 2 + 3 semantics settled (the downgrade E2E exercises exactly gate + refusal + cold availability) |
| — | **Cross-cutting hardening** (P6) | PITFALLS P6 | Extend the 13-case fault-race matrix to the new seams; three-platform fresh-clone CI with cold storage ON; Windows/macOS walk-lane portability list (WARP note, per-node base paths, poll predicates, filter grammar, tier labels, env knobs); soak before any scale verdict | Woven into each phase's exit criteria; explicit final soak/CI gate closes the milestone |

**Rationale for the order:** the merge unlocks all walk-related composition tests (nothing recovery-shaped can be tested before it lands); the durability gate establishes "never erase what isn't in cold," the precondition that makes archive-serve semantics honest on tiered-light nodes; evidence-aware serving then composes both primitives (and fixes both bugs); composition hardening needs both pruners in final shape; the policy phase needs Phases 2+3 settled because the downgrade E2E exercises exactly their semantics. The poisoned-GC-triangle constraint is honored by construction: no collection capability exists in v1.2, and Phase 6 ships the exemption design alongside the collectibility policy so contract-v2 work can never land collection without the exemption.

### Research Flags

- **Needs `--research-phase`: Phase 2** — durability state machine (can any path regress `Durable`→`Accepted` post-merge? code read of `AdvanceDurabilityOnce`); develop Phase 17 landing status and the composition-vs-rebase decision.
- **Light/optional: Phase 3** — the `/prune/blk` marker staging mechanism (widen `EraseEntry`'s `extra_entry` to a vector vs TxPruner staging via `TransactionManager`); ARCHITECTURE already maps every seam, so standard patterns likely suffice.
- **Standard patterns (skip research): Phases 1, 4, 5** — merge checklist, the sequence+LRU-fix ruling, and measure-and-decide are fully specified in the research.
- **Phase 6** — policy drafting has all precedents cited (Kubo destructive-op warnings, PG/Filecoin explicit transitions); no new research needed.

---

## Open Questions

1. **Durability monotonicity** — can any path regress `Durable`→`Accepted` on the merged line today? Needs a code read of `AdvanceDurabilityOnce` during Phase 2 planning (PITFALLS gap).
2. **develop Phase 17/20 timing** — if 17 (eligibility dry-run, spend-recency) or 20 (reclamation proof) land mid-milestone, composition-vs-rebase must be decided; the separate-conjunct design makes 17 a merge either way.
3. **Bootstrap-merge timing/conflict surface** — "only `GeniusNode.cpp` conflicts" is MEDIUM confidence until the merge is executed; when does the branch land on develop?
4. **Seal sizes/counts at real deployment scale** — unknown until Phase 5's probe; the first measurement gates the walk-bound defaults (Interaction F).
5. **GC-disposal starvation** — ratify "accept under-prune + document" for v1.2 vs the `DisposedDurable` journal-state option (touches the frozen-ish LocalBlockStore journal schema — v2).
6. **Block-marker staging mechanism** — widen `EraseEntry`'s `extra_entry` to a vector, or stage `/prune/blk` from `EraseTransactionEntryWithMarker` on group completion (Phase 3 design choice).
7. **Cold-node pruning policy default** — never-erase default vs opt-in durability-gated erase (TS-7 / seed item 6); confirm composition when 17 lands.
8. **D-3 cold spot-audit scheduling** — this milestone's hardening wave or the next? (FEATURES: strong candidate, bounded cost.)
9. **Hardening as phase vs exit criteria** — roadmapper decides whether P6 becomes a discrete Phase 7 or woven exit criteria + a final soak gate.

---

## Sources

Aggregated from the four research files; per-item confidence ratings live there.

**Internal (HIGH):**
- `.planning/research/{STACK,FEATURES,ARCHITECTURE,PITFALLS}-v1.2-rocksdb-backup.md` (2026-11-13) — inputs to this synthesis
- `.planning/workstreams/rocksdb-backup/notes/develop-merge-erase-vs-cold-storage-gap.md` (2026-11-13 seed — tiered-node model, candidate work items 1–6, merge forecast, WARP environmental note)
- `SuperGenius/.planning/REQUIREMENTS.md` (v1.2 PRUNE/GATE/SURV/RECL + out-of-scope table), `SuperGenius/.planning/ROADMAP.md` phases 16–20, phase-17/18/19 artifacts (marker contract, compose-lock, tri-state lookup ordering)
- `.planning/workstreams/rocksdb-backup/{STATE.md,RETROSPECTIVE.md}`, v1.1 phases 08–12 (D-16 two-half eviction, 13-case fault-race matrix, dagMutex_/io_context discipline, disposed-marker dedup, sibling-namespace pinning, CIDv0 tracer finding)
- Code, working tree `dev_coldstorage_additions`: `globaldb.cpp/.hpp`, `ColdStorageManager.{hpp,cpp}`, `ColdStorageStack.hpp`, `BlockStoreBackedIpfsDatastore.hpp`, `cold_read_fallback.hpp`, `ColdReadService.{hpp,cpp}`, `graphsync_dagsyncer.cpp`, `TxPruner.cpp`, `PruneEligibility.{hpp,cpp}`, `TransactionManager.cpp`, `GeniusNode.cpp`, `NodeType.hpp`, `test/src/crdt/globaldb_erase_test.cpp`
- Code, branch `fix/trust-genesis-bootstrap` @ `d556f86de`: `crdt_datastore.cpp` (forced walk), `PruneEligibility.cpp` (`CanRestoreElement`), `graphsync_dagsyncer.cpp` (`HasStoredBlock`/`GetStoredNode`), `GeniusNode.cpp` (`RequestBootstrapWalk`)
- Thirdparty (pins authoritative): RocksDB 9.4.0 headers (`options.h`, `version.h`), ipfs-lite-cpp (graphsync enum/extensions/`<cid>sealed` keys), libp2p identify, sgns-blockstore (CORE-05/06 contract, `S3Client.hpp:182`, `Durability.hpp`, s3d v0.2.1 pin), minio-cpp 1.0.0, protobuf 7.34.0

**External:**
- BIP-159 `NODE_NETWORK_LIMITED` (bitcoin/bips, fetched) — HIGH
- RocksDB manual-compaction + `DeleteRange` wikis (official; in-tree 9.4 header authoritative on defaults) — HIGH
- ethereum.org nodes-and-clients; docs.ipfs.tech persistence/pinning; docs.filecoin.io deals/sectors; postgresql.org §5.12 partitioning (all fetched 2026-11-13, cross-checked) — MEDIUM
- s3d README compatibility matrix (master/v0.3.0; unverified at pinned v0.2.1 — and not needed) — MEDIUM
- go-ds-crdt repo (purge-path youth/bugs precedent) — MEDIUM; Kubo docs (`repo gc`/`repo verify` destructive-op shape) — HIGH
- BitTorrent seeding semantics; EIP-4444 (training data only) — LOW, flagged; geth freezer/snap-pruning TOCTOU analogy — LOW (source moved/404; re-verify before citing in phase planning)
