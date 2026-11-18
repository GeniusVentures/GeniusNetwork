# Phase 16: TxPruner × GC Composition Hardening - Context

**Gathered:** 2026-11-18
**Status:** Ready for planning

<domain>
## Phase Boundary

COMP-01/02/03 — concurrent TxPruner and GC passes are proven safe on the gated, evidence-aware line: sequenced (never unified), with the stale-LRU erase window closed, the interleave matrix proven, and the GC-disposal starvation interplay ruled fail-safe.

1. **SC1 (COMP-01)** — `EraseEntry`'s post-commit cleanup is hardened to GC's parity — a concurrent `GrabCIDBlock` insert between compose-start and commit cannot leave a stale LRU entry (post-commit `DeleteCIDBlock` closes the window)
2. **SC2 (COMP-02)** — an interleave matrix crossing concurrent TxPruner and GC passes — overlapping set rows, seal rows, and the block LRU — proves both idempotent on absent keys, seals untouched by both, and both erase orders converging to one fixed point
3. **SC3 (COMP-03)** — the GC-disposal starvation interplay (journal record deleted → gate reads NoRecord while remote S3 still serves) is ruled and documented with its fail-safe direction asserted by test: the observable outcome is under-prune, never destruction of the last copy

Out of this phase: `DisposedDurable` journal terminal state (v2 — REQUIREMENTS Future), erase-on-disposed with remote-presence verification (rejected for v1.2), seal growth measurement (Phase 17), collectibility policy + role downgrade (Phase 18), cross-feature fault-race matrix + three-platform CI capstone (Phase 19 — though this phase's Tier-1 entries feed it).

Requirements: COMP-01, COMP-02, COMP-03.

**Status note:** Phase 15 shows 3/3 plans executed with verification `human_needed` (UAT pending) at gather time. This phase depends on Phase 15's landed marker infrastructure (`/prune/blk`, widened `EraseEntry`) — planning research MUST re-locate anchors against the final post-Phase-15 state (research docs cite merge `2af184fa1`; Phase 15 executed at `095c8c502`).

</domain>

<decisions>
## Implementation Decisions

### Sequencing ruling (Interaction C form)
- **D-01:** **Convergence-proof — no new mutual exclusion** — TxPruner cycles and GC passes remain free to run concurrently; the interleave matrix proves both erase orders converge to one fixed point. Matches SC2's letter ("concurrent TxPruner and GC passes") and the research lean ("no coordination needed" for the reverse order; row-level idempotence already safe). Hard mutex serialization (the 261029-uj0 GcPassOnce class) was explicitly considered and rejected — it would add coupling the "never unify" decision resists and weaken what SC2 proves — **Reversibility:** costly — the matrix evidence contract is built against the concurrency claim; switching to a mutex later re-opens SC2's meaning and orphans the barrier-driven suites
- **D-02:** **Interaction-C read ruling = existing locks suffice** — the ruling asserts both destructive durability readers (GC mark-time `kEvictionDurabilityGate`, TxPruner in-compose re-check from Phase 14 D-06) already serialize on existing locks (`cold_store_mutex_` / compose lock). Verify on the post-Phase-15 line, document at both destructive homes, race-test the invariant. No new gate, no symmetric GC re-check machinery — remote S3 is never deleted in v1.2, so contradictory beliefs cannot destroy the last copy
- **D-03:** **Fix-forward on divergence** — if a red-first matrix test finds a legal interleave that does NOT converge, it is treated as an idempotence-contract bug in one pruner: repair the half and keep concurrency. Divergences are not design-level signals requiring escalation or a fallback lock

### Stale-LRU close (SC1 mechanics)
- **D-04:** **Cleanup lives in `EraseEntry`, unconditional for every caller** — the post-commit `DeleteCIDBlock` over the removal-set CIDs executes for all erase paths through `EraseEntry` (single home, extending Phase 15's "EraseEntry stays THE single staging point" philosophy). GC's own A6 `DeleteCIDBlock` in `RunHotCleanup` stays untouched — idempotent double-delete is harmless, and GC's sanctioned hot-cleanup order is never edited by this phase — **Reversibility:** costly — the single-home placement is the load-bearing fix for the window; unwinding it re-opens the bug class for future `EraseEntry` callers
- **D-05:** **Guard 3 stays; post-commit delete only closes the race window** — the compose-start LRU rejection (guard 3, `globaldb.cpp:1428-1432`) keeps deferring erases of LRU-resident CIDs; admission semantics are unchanged (compose-don't-pick; smallest behavioral delta). Full GC parity (removing guard 3 so cached CIDs erase immediately) was considered and rejected — a bigger admission change than SC1's letter demands, touching the compose-path guards Phase 14 built evidence against

### Interleave matrix (SC2 evidence shape)
- **D-06:** **Both test layers** — real-thread barrier-driven races for true-concurrency claims (v1.1 discipline: barriers, never sleeps, env-knob reproducibility on every nondeterministic test) PLUS deterministic seam-stepped interleavings for exact repro of specific orderings (Phase 14 D-07 interrupt-seam precedent). Each covers what the other can't — the 261029-uj0 OSX faults were real-thread timing seams can't reproduce; SC1's exact window (insert between guard-check and commit) can't be forced reliably by real threads
- **D-07:** **Marker-namespace crossfire folded into the matrix** — one matrix product crosses {TxPruner erase × GC hot-cleanup × `GrabCIDBlock` insert} over ALL shared surfaces: set rows, block bytes, LRU, seal rows, AND both marker namespaces — with Pitfall 5's crossfire invariants (tombstones, disposed markers, `/prune/` markers byte-identical across each run) asserted as matrix rows. One product proves SC2 and the crossfire guard together
- **D-08:** **Fixed point = rows + answers** — "both erase orders converging to one fixed point" is asserted at BOTH layers: (a) byte-level row convergence via exact prefix enumeration of every touched keyspace (Phase 11's prefix-spy hot datastore instrument); AND (b) observable equivalence — `HasBlock` / `getNode` / evidence predicate answer identically from either order's end state — **Reversibility:** costly — this is the mechanical definition of SC2's "one fixed point"; weakening either layer re-opens what convergence means
- **D-09:** **Tier-1 entry, no soak leg** — the deterministic matrix suites (seam-stepped + barrier-driven on real RocksDB/GlobalDB, no services) enter the CI Tier-1 contract this phase (Phase 14 D-09 fresh-clone-safe precedent; feeds the Phase 19 three-platform capstone). No soak-scale leg — SC2 is a correctness claim, not a capacity claim; scale evidence belongs to Phase 17/19

### Starvation ruling (SC3 disposition)
- **D-10:** **Cross-marker skip — explicit deferral with split counters, still under-prune** — TxPruner's gate consults GC's disposed-marker keyspace for NoRecord constituents: disposed → explicit deferral surfaced by a SPLIT counter (cold_deferred vs stranded-by-disposal), never an erase. Operators can see stranded prune mass (matters for Phase 17 measurement and Phase 18 policy; MI-02 never-healthy-by-omission precedent from Phase 14 D-03). Marker reads go through the GC module's key builder — no third builder (Pitfall 5). Erase-on-disposed (remote-presence verification) was considered and rejected — adds S3 GET I/O to the prune cycle and weakens the fail-closed posture; research recommended against it for v1.2 — **Reversibility:** costly — the split counter becomes an operator-facing contract Phase 17/18 evidence cites; collapsing it back into one undifferentiated mass loses the stranded-rows observability
- **D-11:** **SC3 fail-safe test = both legs** — (a) deterministic Tier-1 leg via the Phase 14 D-08 journal-injection kit (delete the journal record directly = disposal simulation; assert defer + split counter, written red-first); PLUS (b) one dev-gated live leg where a real GC pass disposes and a subsequent TxPruner cycle defers with the stranded counter — mirroring the 14-D-08 hybrid posture (the injection alone might model the wrong post-disposal state)
- **D-12:** **Ruling documentation = code + doc** — code comments at both destructive homes (the TxPruner gate site + `ColdStorageManager`'s `EvictLocalAndMarkDisposed`) stating the interplay and the under-prune ruling, PLUS a workstream planning doc carrying the full ruled analysis (options considered, v2 `DisposedDurable` pointer, stranded-rows lifecycle). The planning doc is what Phase 18's policy record cites; the sequencing/Interaction-C ruling (D-02) gets the same code-at-both-homes treatment

### The Agent's Discretion
- Exact interrupt-seam placement/naming for the SC1 window counter-test (sibling of `kInterruptBeforeErase` / Phase 14's `kInterruptAfterColdGate`)
- Barrier design and env-knob scheme for the real-thread legs (flake containment on the Windows/macOS lanes — poll predicates, never fixed sleeps)
- Prefix-spy reuse specifics: which keyspaces the exact-key enumeration covers per fixture
- Counter naming for the D-10 split (e.g. `cold_deferred_groups` vs a stranded-disposed companion) and how it surfaces in the per-cycle INFO summary
- Matrix fixture design — which CIDs overlap across the two pruners' sets, seal row fixtures, both marker namespaces in play
- Home and name for the workstream ruling doc (phase dir vs `notes/`)
- Whether `EraseEntry`'s post-commit delete iterates the removal-set vector mechanically or reuses a helper (implementation shape)
- Anchor re-location strategy against the final post-Phase-15 state (see domain status note) — researcher rules exact procedure

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream planning
- `.planning/workstreams/rocksdb-backup/ROADMAP.md` — Phase 16 goal, 3 success criteria, dependencies (14, 15 — "the gate defines the disposal interplay; marker infrastructure from Phase 15")
- `.planning/workstreams/rocksdb-backup/REQUIREMENTS.md` — COMP-01/02/03 letters; governing invariants 1-4; Future Requirements (`DisposedDurable` = the v2 answer); out-of-scope table
- `.planning/workstreams/rocksdb-backup/STATE.md` — v1.2 key decisions (never unify the pruners — sequence + close the LRU window; zero new dependencies)
- `.planning/workstreams/rocksdb-backup/phases/14-durability-gated-txpruner-eligibility/14-CONTEXT.md` — D-02 NoRecord-defers-forever premise this phase refines; D-06 in-compose re-check that "must not contradict Phase 16's Interaction-C ruling" (satisfied by D-02 here); D-08 journal-injection kit; D-09 Tier-1 precedent; D-03 dedicated-counter precedent
- `.planning/workstreams/rocksdb-backup/phases/15-evidence-aware-cold-serving-forced-walk-recovery/15-CONTEXT.md` — D-01 widened `extra_entry` vector + `/prune/blk` markers (the EraseEntry this phase hardens); D-04 HasBlock-body-unchanged posture; interrupt-seam siblings; the walk surfaces the matrix must stay consistent with

### v1.2 research (2026-11-13)
- `.planning/research/ARCHITECTURE-v1.2-rocksdb-backup.md` — §(c) "TxPruner hot cleanup × GC `RunHotCleanup`" — THE overlap inventory table (CID key / set rows / LRU / seal / cold tier per path) and the three work items: post-commit `DeleteCIDBlock` (SC1), disposal-starves-TxPruner document-don't-fix (SC3), reverse-order safe by construction (D-01's basis)
- `.planning/research/SUMMARY-v1.2-rocksdb-backup.md` — key decision "DO NOT unify — sequence + close the LRU window"; the stale-LRU discovery note; phase-4 row (this phase's scope incl. the Interaction-C ruling and cross-marker skip optionality)
- `.planning/research/PITFALLS-v1.2-rocksdb-backup.md` — Pitfall 4 (double-prune interleavings; single-writer-or-mutex prevention menu — the mutex arm is REJECTED by D-01), Pitfall 5 (marker-namespace crossfire; prefix granularity landmines), Pitfall 11 (under-erase direction), Interaction C (durability reads shared by destructive systems — D-02's ruling target), test-guidance items 4/6/7 (red-first races, tier discipline, env-knob reproducibility)
- `.planning/research/STACK-v1.2-rocksdb-backup.md` — row 5 seams: `GlobalDB::EraseEntry`, `StageBlockRemoval`, GC's `DeleteCIDBlock` + disposed markers — "unify or explicitly sequence" (ruled: sequence, D-01)
- `.planning/research/FEATURES-v1.2-rocksdb-backup.md` — TS-3 (seals survive both pruners; overlap surface enumeration)

### Prior-phase test infrastructure (reused, not rebuilt)
- `.planning/workstreams/rocksdb-backup/milestones/v1.1-phases/11-retention-gc-cold-eligible-crdt-data/` — the prefix-spy hot datastore instrument (D-08's exact-key assertions) and GC-02 invariant test (crossfire extension point)
- `.planning/workstreams/rocksdb-backup/milestones/v1.1-phases/12-integration-hardening-fault-races-fresh-clone-proof/` — the 13-case barrier-driven fault-race matrix pattern SC2's suites extend
- `.planning/workstreams/rocksdb-backup/quick/261029-uj0-debug-failing-supergenius-cold-storage-t/` — the GcPassOnce serialization fix (the mutex class D-01 explicitly did NOT choose — read to understand what was rejected and why OSX real-thread timing matters to D-06)

### Code under change (anchors from research at merge `2af184fa1` — RE-LOCATE on the post-Phase-15 line before editing)
- `SuperGenius/src/crdt/globaldb/globaldb.cpp` — `EraseEntry` (~:1374-1451, the compose path D-04's cleanup joins); guard 3 (:1428-1432, stays per D-05); `extra_entry` staging (:1462-1466 — now the widened vector from Phase 15); post-commit seal re-assert (:1471-1485 — the ordering context for the new post-commit delete)
- `SuperGenius/src/crdt/globaldb/globaldb.hpp` — :489 `extra_entry` (widened signature)
- `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` — `StageBlockRemoval` (:618-633); `DeleteCIDBlock` / `GrabCIDBlock` / `getNode` LRU insert sites (the SC1 window's inserter)
- `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp` — `RunHotCleanup` (:1317-1345, A6 `DeleteCIDBlock` :1346-1348 — stays untouched per D-04); seal retention comment (:1327-1333); delete-time heads re-check (:1253-1261); `EvictLocalAndMarkDisposed` (journal deletion — the D-10 consult source and D-12 comment home); `kEvictionDurabilityGate` consumption (:1072-1076, D-02's GC reader)
- `SuperGenius/src/transaction/TxPruner.cpp` — `RunCycle` block-group filter (:141-176 — where the D-10 cross-marker consult composes with the Phase 14 gate); interrupt seams (:198 `kInterruptBeforeErase` + Phase 14's `kInterruptAfterColdGate`)
- `SuperGenius/src/transaction/TxPruner.hpp` — :68 `PruneCycleStats` (where the D-10 split counter lands)
- `SuperGenius/src/transaction/PruneEligibility.cpp` / `.hpp` — marker statics home (D-C1 — no third builder)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Phase 14 journal-injection test kit** — real GlobalDB + direct CF seeding, deterministic, no services; D-11's Tier-1 leg deletes a journal record directly to simulate GC disposal
- **Interrupt seams** (`kInterruptBeforeErase`, `kInterruptAfterColdGate`) — the deterministic-interleaving layer D-06 extends with a new sibling for the SC1 window
- **Phase 11's prefix-spy hot datastore** — exact-key enumeration instrument for D-08's row-convergence assertions and D-07's crossfire invariants
- **`PruneCycleStats` + per-cycle INFO summary** — the existing counter home the D-10 split joins (Phase 14 already added `cold_deferred_groups` / `cold_unreadable_groups`)
- **v1.1 fault-race matrix pattern** — 13-case barrier-driven suite; SC2's matrix extends this discipline
- **Phase 15's widened `EraseEntry` + `/prune/blk` markers** — the exact erase path SC1 hardens; both marker namespaces already flow through one atomic staging point

### Established Patterns
- **Hermetic-first CI, dev-gated live evidence** — deterministic suites in Tier-1 (D-09); the one live SC3 leg stays dev-gated (D-11)
- **Red-first counter-tests** — the SC1 window test and SC3 defer test are written failing-first
- **Barrier-driven, never sleeps; env-knob reproducibility on every nondeterministic test** — the v1.1 norm for D-06's real-thread layer
- **Compose-don't-pick** — GC's sanctioned order is never edited (D-04); guard 3 admission semantics unchanged (D-05); the gate composes at `RunCycle`, evaluator stays pure
- **Idempotent on absent keys** — the load-bearing property D-01's convergence-proof and D-03's fix-forward posture rely on
- **Fail-closed + group-or-defer + dedicated counters for distinct unhealthy states** — D-10's split counter extends the D-03 (Phase 14) observability precedent

### Integration Points
- `EraseEntry` post-commit path (after seal re-assert) — D-04's `DeleteCIDBlock` home
- `RunCycle`'s group filter NoRecord branch — D-10's disposed-marker consult composes with the Phase 14 cold gate
- `ColdStorageManager`'s disposed-marker keyspace — read via the GC module's key builder (no third builder)
- Tier-1 suite registration (`ctest -L` lane labels, label-count audit with teeth) — D-09's contract entry; feeds Phase 19's three-platform capstone
- Both marker namespaces + seal rows — D-07's matrix fixture surfaces

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond the recorded decisions — the discussion was decision-focused with no external references introduced by the user.

</specifics>

<deferred>
## Deferred Ideas

- **`DisposedDurable` journal terminal state** — the v2 answer to the starvation interplay (preserve terminal evidence instead of deleting the journal record); already recorded in REQUIREMENTS Future — touches the frozen-ish LocalBlockStore journal schema
- **Erase-on-disposed (disposed marker + verified remote presence as erase-sufficient)** — research option (ii), rejected this phase (adds S3 GET I/O to the prune cycle, weakens fail-closed); revisit only alongside v2 collection machinery
- **Hard mutual exclusion of TxPruner cycle × GC pass** — the 261029-uj0 mutex class, explicitly rejected by D-01 in favor of convergence-proof; recorded here so future readers know it was considered, not missed
- **Removing guard 3 for full GC parity** — considered and rejected by D-05; if LRU-residency deferral ever proves costly, that's a measured trigger for a future phase
- **Soak-scale composition evidence** — correctness claims only this phase (D-09); scale belongs to Phase 17 measurement and Phase 19's capstone

</deferred>

---

*Phase: 16-TxPruner × GC Composition Hardening*
