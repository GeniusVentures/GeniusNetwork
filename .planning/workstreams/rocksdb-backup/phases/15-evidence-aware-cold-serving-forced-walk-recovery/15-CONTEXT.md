# Phase 15: Evidence-Aware Cold Serving & Forced-Walk Recovery - Context

**Gathered:** 2026-11-17
**Status:** Ready for planning

<domain>
## Phase Boundary

SERVE-01/02/03/04 + RECOVER-02/03/04 + TEST-01 — evidence outranks bytes on every read path. The cold chain (Rehydrate path) consults prune evidence before serving, fixing the cold-chain resurrection gap; GC-evicted blocks re-warm from cold (evict ≈ DETACH); the tri-state answer (pruned / evicted-restorable / not-found) flows from a single role-aware evidence predicate owned by GlobalDB; pruned stays distinct from not-found so requesters fail over correctly; the forced walk restores GC-evicted ancestors from cold without ever conflating them with pruned, never resurrects TxPruner-erased elements, bounds peer failover per-CID, and aborts-never-skips on walk-gaps. Hermetic evidence-aware fakes model the PrunedLookup tri-state and back every SERVE/RECOVER suite.

1. **SC1** — a request for a TxPruner-erased CID answers pruned semantics even when cold bytes exist (cold chain consults evidence before serving; no resurrection)
2. **SC2** — a GC-evicted CID (no prune evidence) on a cold-enabled node serves through the cold chain and re-warms; evict ≈ DETACH; proven by masquerading counter-tests in both directions
3. **SC3** — the tri-state answer is consistent across `HasBlock`, `getNode`, and the cold chain via a single role-aware evidence predicate owned by GlobalDB; pruned distinct from not-found at the protocol surface
4. **SC4** — the forced walk restores GC-evicted ancestors from cold, never resurrects TxPruner-erased elements (`CanRestoreElement` terminal), bounds peer failover per-CID, aborts-never-skips on walk-gaps
5. **SC5** — hermetic evidence-aware fakes model the PrunedLookup tri-state (present / pruned / not-found) and back every SERVE/RECOVER/PRUNE suite; the refusal matrix runs as a product: {hot} × {cold} × {evidence: none/PRUNED/malformed} × {serve, walk visit, erase-gate}

Out of this phase: TxPruner×GC interleave hardening and the stale-LRU window close (Phase 16 — `EraseEntry` post-commit `DeleteCIDBlock` lands there, not here), seal growth measurement and the walk-bound probe (Phase 17 — it VALIDATES this phase's derived defaults), collectibility policy + role downgrade (Phase 18), cross-feature fault-race matrix + 3-platform CI (Phase 19).

Requirements: SERVE-01, SERVE-02, SERVE-03, SERVE-04, RECOVER-02, RECOVER-03, RECOVER-04, TEST-01.

</domain>

<decisions>
## Implementation Decisions

### `/prune/blk` marker staging (the ROADMAP-flagged research item)
- **D-01:** **Widen `EraseEntry`'s `extra_entry` to a vector** — the opaque pair parameter (`globaldb.hpp:489`, staged `globaldb.cpp:1462-1466`) becomes a vector of pairs; TxPruner passes both `/prune/tx` and `/prune/blk`; `EraseEntry` stays THE single atomic staging point, so marker-without-erase and erase-without-marker windows are impossible by construction. Key shapes are built in `PruneEligibility` (D-C1 precedent — callers never rebuild key shapes). Phase 14 D-01's single-CID removal-set ruling is the load-bearing premise: one block marker per group erase today — **Reversibility:** costly — signature change on the erase path Phase 16 also hardens (COMP-01 post-commit cleanup); unwinding touches `EraseEntry` plus every caller and re-opens the atomicity argument
- **D-02:** **`/prune/blk/<cid>` value carries a back-reference record** — erased-at generation + the `/prune/tx` hash back-reference (shape designed in `PruneEligibility` alongside the key builder). Presence remains the evidence signal; the record buys operator CID→tx traceability and feeds Phase 17's ancestry-density measurement
- **D-03:** **No backfill, no lookup fallback** — blocks erased under v1.1 have no CID-keyed evidence and that is ruled moot: v1.1 is this workstream's archived milestone, never deployed (user-confirmed 2026-11-17); `/prune/blk` evidence starts fresh from Phase 15 onward. Recorded as an explicit assumption so the audit trail shows the deployment premise was checked, not missed

### SC3 interpretation — HasBlock answer shape
- **D-04:** **Source-consistency ruling** — `HasBlock` stays bool and its body is UNCHANGED (cold-dir term 3 / disposed term 4 keep answering TRUE for erased CIDs — dedup-correct; the retained seal makes re-delivered deltas inert). SC3's "consistent across HasBlock, getNode, and the cold chain" means all surfaces derive from the ONE role-aware GlobalDB predicate: `getNode`/cold-chain/responder classify (pruned / evicted-restorable / not-found), `HasBlock` projects onto bool. SC3 evidence = a consistency test proving every classifying surface routes through the same predicate against the same fixture. Mirrors develop's SURV-02 posture (different surfaces, different shapes, one source) and Phase 14 D-01's SC-interpretation style — **Reversibility:** costly — this defines SC3's evidence contract; re-litigating shape-vs-source re-opens the consistency suite

### Walk decision matrix & bounds
- **D-05:** **Fourth quadrant = bounded peers, then loud abort** — for a walk visit that is sealed + not-retained + no local cold bytes + no prune evidence (unreachable in a healthy system; reachable via corruption/manual deletion/seal-only remnants): fall through to `getNode` (peers eligible — another archive node may hold it; this is recovery, not skipping), bounded by the per-CID failover budget; peers exhausted → abort the walk with a DISTINCT walk-gap error + counter (never a skip counter, never silently-validated partial history). Faithful to RECOVER-04: abort applies when recovery is exhausted
- **D-06:** **Failover-budget defaults derive from recorded v1.1 walk-recovery numbers** — named internal constants computed from the v1.1 recovery-suite evidence, rationale recorded here and in the plan; Phase 17 SC2's probe then validates/re-tunes them (derive-now, refine-later — both halves of the recorded dependency stay honored). No config knobs (Phase 14 D-04's no-new-config-surface posture). Research directive: locate the v1.1 walk-recovery numbers (see `<specifics>`)

### Protocol refusal surface (SERVE-04)
- **D-07:** **Mirror develop's SURV-02 exactly** — local tri-state classification via the GlobalDB predicate maps to a distinct `GraphsyncDAGSyncer::Error` ("history pruned on this node", BIP-159-NOPRUNE-style, never folded into `CID_NOT_FOUND`); the responder (`ColdServeDagService`) refuses cleanly with the standard status; requesters fail over through the EXISTING per-CID failure accounting (`RecordCIDFailure` — CID-scoped, never connection-blacklisting). ZERO wire/proto changes — the compatibility constraint stays untouched. SERVE-04's "protocol surface" = the syncer-layer error classification. Failover evidence extends develop's 19-07 RefusalFailover suite pattern to cold-enabled nodes — **Reversibility:** costly — a later wire-level signal would touch proto compatibility and re-open SERVE-04's meaning; staying at the syncer layer is the recorded shape

### The Agent's Discretion
- **TEST-01 fake architecture** (held in reserve, not discussed) — seeded real-RocksDB markers against a real GlobalDB (Phase 14 D-08 journal-injection precedent) vs. in-memory `PrunedLookup` fake; researcher/planner shape it within the hermetic-first discipline. The refusal matrix runs as a product either way: {hot} × {cold} × {evidence: none/PRUNED/malformed} × {serve, walk visit, erase-gate}
- Predicate injection mechanics — research direction is GlobalDB-injected at the `OpenColdStorageStack` seam (`globaldb.cpp:819-846`), interface shape (extend `ColdReadFallback` vs. separate role flag) is research/planner work
- Cold-present probe mechanics in the walk (local cold dir / disposed marker / cold-chain probe — which signal)
- `Error` enum naming/placement in `ApplyColdPrecedence`; walk-gap error + counter naming in walk stats
- Consistency-test shape proving SC3's source-consistency (D-04)
- Tier placement of new deterministic suites (Tier-1 expected per Phase 14 D-09 precedent — fresh-clone-safe, no services)
- Interrupt-seam extensions for induced-evidence tests (sibling of `kInterruptBeforeErase` / the Phase 14 `kInterruptAfterColdGate` seam)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream planning
- `.planning/workstreams/rocksdb-backup/ROADMAP.md` — Phase 15 goal, 5 success criteria, dependencies (13, 14), the `/prune/blk` staging research flag
- `.planning/workstreams/rocksdb-backup/REQUIREMENTS.md` — SERVE-01..04, RECOVER-02..04, TEST-01 letters; governing invariants 1-4; out-of-scope table
- `.planning/workstreams/rocksdb-backup/STATE.md` — v1.2 key decisions (evidence-outranks-bytes, zero new dependencies, converged phase order, SEAL-probe dependency direction)
- `.planning/workstreams/rocksdb-backup/phases/13-bootstrap-branch-merge-composition-baseline/13-CONTEXT.md` — merged-line baseline; the walk symbols that landed via merge; D-12's "deterministic barrier-based proof is Phase 15 scope" hand-off (cold-before-peer enforcement becomes provable here)
- `.planning/workstreams/rocksdb-backup/phases/14-durability-gated-txpruner-eligibility/14-CONTEXT.md` — D-01 removal-set ruling (single-CID premise for D-01 here), D-04 no-config-knob posture, D-08/D-09 test-tier precedents, interrupt-seam pattern

### v1.2 research (2026-11-13)
- `.planning/research/ARCHITECTURE-v1.2-rocksdb-backup.md` — §(b) the serving gap + predicate design (GlobalDB-owned, injected at `OpenColdStorageStack`; `/prune/blk` marker rationale; SURV-02/03 answer shape); §(d) forced-walk conflation bug + refinement + the five verified re-warm ordering guarantees; §3.1 evidence-aware read path; §3.4 refined walk flow; §"3. Phase sequencing" item 3 (this phase's scope in the build order)
- `.planning/research/SUMMARY-v1.2-rocksdb-backup.md` — phase-3 row; key-decisions (evidence outranks bytes node-locally; two discovered bugs this phase fixes)
- `.planning/research/PITFALLS-v1.2-rocksdb-backup.md` — resurrection-gap and conflation rows; marker-staging pitfall context; Interaction C boundary with Phase 16
- `.planning/research/FEATURES-v1.2-rocksdb-backup.md` — TS rows for evidence-aware serving/walk; AF rows for the two failure modes this phase kills

### Develop-line artifacts (the SURV-02 posture being extended)
- `SuperGenius/.planning/REQUIREMENTS.md` — SURV-02 letter as completed on develop (local distinct + clean standard peer refusal)
- `SuperGenius/.planning/phases/19-pruned-node-survival-recovery-hardening/19-05-PLAN.md` + `19-05-SUMMARY.md` — the LOCAL half: tri-state `LookupTransaction`, `PrunedLookup` vocabulary (PRUNED / NOT_FOUND / VALUE_PRESENT_INVARIANT_VIOLATION)
- `SuperGenius/.planning/phases/19-pruned-node-survival-recovery-hardening/19-07-PLAN.md` + `19-07-SUMMARY.md` — the PEER half: pruned-server refusal + requester failover, per-CID accounting, `EraseNodeCollection` 3-node topology; A5 caveat (wire status value plumbing-verified, not exercised — re-verify on the merged line)
- `SuperGenius/.planning/phases/17-eligibility-policy-gating-dry-run/17-CONTEXT.md` — D-04 marker design (`/prune/tx/<hash>` hash-keyed, record = tx path + erased CID — the back-reference source for D-02); marker-home-in-PruneEligibility precedent

### v1.1 prior phases (failover-budget derivation + seam discipline)
- `.planning/workstreams/rocksdb-backup/milestones/v1.1-phases/09-cold-read-fallback-local-reads-graphsync-serving/09-CONTEXT.md` — the cold-read seam contract; D-08 HasBlock local-only semantics; Rehydrate bytes-only ruling (§2.4 of its research)
- v1.1 recovery-walk suite artifacts under `.planning/workstreams/rocksdb-backup/milestones/v1.1-phases/` — the recorded walk-recovery numbers D-06 derives from (researcher locates the exact SUMMARYs)

### Code under change (anchors from research at merge `2af184fa1` — RE-LOCATE on the current merged line before editing)
- `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` — :41-67 `ApplyColdPrecedence` (classification surface); :324-614 `getNode` (route walk + `RecordCIDFailure`); :686-723 `HasBlock` (4-term; STAYS unchanged per D-04); :725-806 `GetNodeWithoutRequest` + `FetchNodeFromColdStorage` (predicate insertion: after cold Get, before Rehydrate); :108-124 `ColdServeDagService` (responder refusal); :618-633 `StageBlockRemoval`; :1083-1092 seal accessors
- `SuperGenius/src/crdt/cold_read_fallback.hpp` — hook interface; D-12 split; Rehydrate bytes-only ruling
- `SuperGenius/src/crdt/globaldb/globaldb.hpp` — :489 `extra_entry` (the D-01 widening point); :576 `GetColdUploadState`; :43 `ColdUploadState`
- `SuperGenius/src/crdt/globaldb/globaldb.cpp` — :819-846 `OpenColdStorageStack` (predicate injection seam); :1462-1466 `extra_entry` staging; :1428-1432 guard 3
- `SuperGenius/src/crdt/impl/crdt_datastore.cpp` — walk code that landed via merge (:212-470 `RequestForcedWalk` / `ProcessForcedWalkStep` / `ProcessForcedWalkCID` / `QueueForcedWalkLinks`; `forcedWalkStepActive_` :336-435) — the D-05 matrix refinement site
- `SuperGenius/src/transaction/PruneEligibility.cpp` / `.hpp` — :156-170 `CanRestoreElement`; `LookupPrunedEntry` tri-state; marker statics home (D-C1)
- `SuperGenius/src/transaction/TransactionManager.cpp` — :4718 `EraseTransactionEntryWithMarker` (single-CID removal set; the caller that passes the widened marker vector)
- `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp` — GC parity surfaces (`kEvictionDurabilityGate` consumption :1072-1076; `RunHotCleanup` :1317-1345) — what the cold chain must stay consistent with

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`LookupPrunedEntry` + `PrunedLookup` tri-state** — already on the merged line via the bootstrap-branch merge; the walk's element guard consumes it; `/prune/blk` extends the same vocabulary to CID-keyed refusal
- **`EraseEntry`'s atomic staging discipline** — one compose-locked WriteBatch carries erase + `/prune/tx` pair today; D-01 widens the slot, not the discipline
- **Develop's `EraseNodeCollection` + RefusalFailover suite pattern** (19-07) — the topology and per-CID accounting assertions D-07's failover evidence extends to cold-enabled nodes
- **Phase 14's journal-injection test kit** — real GlobalDB + direct CF seeding, deterministic, no services; the precedent for TEST-01's fake architecture
- **Interrupt seams** (`kInterruptBeforeErase`, Phase 14's `kInterruptAfterColdGate`) — the induced-evidence pattern for red-first counter-tests

### Established Patterns
- **Hermetic-first CI, dev-gated live evidence** (v1.1 discipline, Phase 14 D-08/D-09) — deterministic tri-state suites in Tier-1; anything needing live S3 stays dev-gated
- **Red-first counter-tests** — masquerading counter-tests in both directions (SC2) written failing-first
- **Fail-closed + group-or-defer** — the predicate refuses on malformed evidence (`VALUE_PRESENT_INVARIANT_VIOLATION` → hard error), never silently serves
- **Compose-don't-pick** — the predicate composes onto the cold chain at the existing seam; `HasBlock`'s body is not re-derived (D-04)
- **Rehydrate bytes-only, walk owns sealing** — preserved verbatim when the walk restores from cold (09-RESEARCH §2.4)

### Integration Points
- `FetchNodeFromColdStorage`: after successful cold `Get`, before `Rehydrate` — predicate consult (SC1/SC2 fork)
- `ApplyColdPrecedence` / `GraphsyncDAGSyncer::Error` — the refusal classification home (D-07)
- `ProcessForcedWalkCID`'s `!retained && sealed` branch — the D-05 matrix (cold-present → fetch; `/prune/blk` → skip; neither → bounded peers → abort)
- `EraseEntry`'s `extra_entry` — the D-01 widening; TxPruner passes the marker vector
- `OpenColdStorageStack` — GlobalDB injects the role-aware predicate into `ColdReadService`
- `CanRestoreElement` — stays terminal authority at element level; block-level `/prune/blk` skip bounds the walk (both layers needed, research §d)

</code_context>

<specifics>
## Specific Ideas

- User-confirmed premise (D-03): v1.1 = this workstream's archived milestone, never deployed — no production node carries pre-`/prune/blk` erases
- D-06 coherence note: derive defaults from v1.1 recorded numbers NOW; Phase 17's probe VALIDATES/re-tunes LATER — the recorded Phase 15↔17 dependency reads in both directions without conflict
- Research directives for `--research-phase`: (1) locate the v1.1 walk-recovery numbers (v1.1 phase SUMMARYs / recovery suites) that D-06's constants derive from, and record the derivation; (2) re-verify develop's A5 caveat on the merged line (the wire status value the responder emits for refusal — plumbing-verified on develop, exercise it here); (3) re-locate all code anchors on the current merged line (research anchors were taken at `2af184fa1`); (4) verify Phase 14 D-01's single-CID removal set still holds (D-01's one-block-marker-per-erase premise)

</specifics>

<deferred>
## Deferred Ideas

### Reviewed Todos (not folded)
- "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" (`.planning/todos/2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md`) — keyword-only match (score 0.2 on 'path'), zero topical overlap; same ruling as Phases 13 and 14 (third consecutive review, not folded)

### Rejected this phase (on record)
- Wire-level graphsync "pruned" signal — rejected per D-07 (develop rejected the same shape; proto compatibility constraint); if ever wanted, it is its own future phase
- `/prune/blk` backfill migration or `/prune/tx`-scan lookup fallback — moot per D-03; revisit only if the deployment premise changes

</deferred>

---

*Phase: 15-Evidence-Aware Cold Serving & Forced-Walk Recovery*
