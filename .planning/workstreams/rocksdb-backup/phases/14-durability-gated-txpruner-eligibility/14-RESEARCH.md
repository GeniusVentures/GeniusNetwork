# Phase 14: Durability-Gated TxPruner Eligibility - Research

**Researched:** 2026-11-16
**Domain:** TxPruner erase eligibility × cold-storage durability evidence (C++17, SuperGenius CRDT/transaction layer, RocksDB, sgns-blockstore journal)
**Confidence:** HIGH (every load-bearing claim re-verified by direct source read on the merged line `dev_coldstorage_additions` @ `2af184fa1` this session)

## Summary

This phase adds one conjunct — "every CID whose bytes the erase deletes must be evidence-`Durable` in cold" — to `TxPruner::RunCycle`'s block-group work-list filter, plus a re-check of that evidence inside `GlobalDB::EraseEntry`'s compose critical section. The merged line already carries every mechanism this needs: the lifecycle-safe `GlobalDB::GetColdUploadState` bridge (null-safe → vacuous when cold is off), the compose critical section in `EraseEntry` acquired as the compose's FIRST act with an existing test-only interrupt seam at three mid-compose positions, the GC's `kEvictionDurabilityGate` consumption precedent to mirror, and a real-store `tx_pruner_test` fixture family that already drives BOTH the TxPruner cycle seam and GlobalDB's erase seam.

The two mandated research questions resolved decisively. **(1) Monotonicity:** no in-process path regresses `Durable`→`Accepted` — the journal has exactly three writers (Put-birth writes `Pending` only when block bytes are absent; the drain loop marks `Accepted` only on CIDs snapshotted from the `Pending` set under `cold_store_mutex_`; `MarkUploadedDurable[Many]` writes only `Durable`), and the only `Durable`-record removal is GC disposal (record deleted → `NoRecord` → defer, exactly D-02's ruling). The nuance: `TransitionJournal` itself is a blind existence-gated write — monotonicity is enforced by caller discipline (snapshot-then-mark), not by a state machine, which is precisely why SC2's in-compose re-check stays mandated. **(2) Develop Phase 17:** it LANDED — all six plan+SUMMARY artifacts exist and the evaluator, block gate, marker design, and config knobs are all in-tree and consumed verbatim by TxPruner; `SuperGenius/.planning/ROADMAP.md`'s status row ("0/6 Planned") is stale bookkeeping. There is no pending external evaluator rework to compose against; keeping the cold conjunct in `RunCycle`'s filter still honors the "merge, not rewrite" invariant against any future develop-side dry-run/reporting work.

Two gaps the plan must cover: GlobalDB exposes **no public cold-enabled accessor** today (`cold_storage_options_.enabled` is private; `GetColdStorageStatus()`'s default triple is not a clean discriminator), so SC4's vacuous branch needs one small new accessor; and the Tier-1 static audit (`tier1_static_audit`) polices label parity only for `cold_*` registrations in `test/src/crdt/CMakeLists.txt`, so D-09's new suites should register there, inside `if(SGNS_COLD_STORAGE)`, with explicit `set_tests_properties(... LABELS Tier1)` lines.

**Primary recommendation:** Implement the gate as (a) a named conjunct in `RunCycle`'s group filter (`TxPruner.cpp:141-176`) reading `globaldb.GetColdUploadState(cid)` per group CID via a new tiny `GlobalDB` cold-active accessor, counted into new `PruneCycleStats::cold_deferred_groups` / `cold_unreadable_groups` fields; and (b) a durability re-check as a new guard (5) inside `EraseEntry`'s compose critical section (after the existing four guards, before staging), reading the journal under `cold_store_mutex_` through the same bridge — lock-safe because the compose→`lifecycle_mutex_` edge already exists (guard 1) and no path acquires the compose lock under `cold_store_mutex_`. Drive the TOCTOU counter-test from the TxPruner-side seam position between gate admission and the erase call.

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Constituent-block scope (gate rule)**
- **D-01:** **Removal-set rule** — the gate checks exactly the CIDs whose bytes the erase physically deletes; today that is the group's single delta-block CID (`EraseTransactionEntryWithMarker` resolves the tx→CID map to ONE cid, and `EraseEntry` deletes that block's bytes + CRDT entries + marker atomically). SC1's "every constituent block" is ruled to MEAN the removal set, not every block the tx references. The researcher verifies `EraseEntry`'s removal set stays single-CID on the merged line — **Reversibility:** costly
- **D-02:** **NoRecord → defer-forever accepted** — a block with no journal record defers its whole group, re-evaluated next cycle. Under-prune is the safe direction; distinguishing disposed vs not-yet-spilled stays Phase 16 scope
- **D-03:** **Unreadable = dedicated `cold_unreadable_groups` counter + WARN line** — NOT a permanent-stop class error

**GATE-01 widening (activation posture)**
- **D-04:** **Automatic activation, no knob** — gate active whenever a Light node has cold storage enabled; no operator opt-in, no new config surface; `NodeType::Light`-only check untouched; SC4's vacuous branch covers Light+no-cold; Archive/Full remain never-prune
- **D-05:** **Named conjunct in the fail-closed factory** — activation ruling lives inside the existing fail-closed factory + per-cycle evaluator construction as a named conjunct — NOT a policy matrix in the evaluator. The evaluator stays contractually pure — **Reversibility:** costly

**TOCTOU re-check strictness**
- **D-06:** **In-compose re-check** — the journal state read happens inside the same critical section that composes/commits the destructive WriteBatch (a gate hook in `EraseEntry`'s compose path, or equivalent lock composition). No window between re-check and commit. Must not contradict Phase 16's Interaction-C ruling — **Reversibility:** costly
- **D-07:** **Induced regression, red-first** — the TOCTOU counter-test flips the journal `Durable`→`Accepted` (or `Durable`→`NoRecord`) between gate admission and erase-commit via the existing interrupt-seam pattern (a new interrupt point, sibling of `kInterruptBeforeErase` at `TxPruner.cpp:198`), written red-first. Staleness-only testing + a monotonicity doc was explicitly rejected

**Test evidence posture**
- **D-08:** **Hybrid state driving** — (a) journal-injection state matrix (5 states, real GlobalDB, no live remote, deterministic); (b) the red-first in-compose TOCTOU counter-test; (c) ONE dev-gated live-stack E2E smoke proving real drainer transitions (`Accepted`→`Durable` via flush) pass the gate
- **D-09:** **Tier-1 now for the deterministic suite** — journal-injection suite + TOCTOU counter-test enter CI Tier-1 this phase (fresh-clone-safe: real RocksDB, no services); live E2E smoke stays dev-gated Tier-2/3 — **Reversibility:** costly

### The Agent's Discretion
- Exact in-compose mechanism (gate hook inside `EraseEntry` vs TxPruner-side lock composition) — researcher rules, planner shapes
- Interrupt-point naming/placement for the TOCTOU counter-test
- Whether the in-compose re-check executes per-tx or is short-circuited per-group — mechanical, both safe if inside the compose
- Journal pre-seeding test helpers and fixture reuse specifics from the v1.1 GC/cold suites
- The Light+cold posture log line and how gate counters surface in the per-cycle INFO summary
- Additional `PruneCycleStats` counter naming beyond `cold_deferred_groups` / `cold_unreadable_groups`
- Composition-test shape proving the cold conjunct composes with the evaluator (SC3)

### Deferred Ideas (OUT OF SCOPE)
- Vulkan capability-probe deadlock todo — keyword-only match, zero topical overlap (reviewed 2026-11-16, not folded)

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PRUNE-01 | Cold-enabled node's TxPruner erases a tx's hot data only when every constituent block is `Durable` in cold; NoRecord/Pending/Accepted/Unreadable defer loudly (fail closed) | Single-CID removal set verified end-to-end (D-01); `GetColdUploadState` bridge + 5-state enum verified; `PruneCycleStats` counter home verified; group-or-defer precedent in `RunCycle` |
| PRUNE-02 | Gate re-checks evidence at erase-commit under the compose lock; a durability change after evaluation cannot enable a destroying erase (TOCTOU) | `EraseEntry` compose critical section + existing mid-compose test seam located; lock-order safety of an in-compose `GetColdUploadState` read established; monotonicity analysis bounds the residual window; counter-test position identified |
| PRUNE-03 | Gate injected at TxPruner's cycle filter, evaluator stays contractually pure; composes with develop's evaluator | Purity contract verified verbatim; develop Phase 17 confirmed landed (no pending rework); filter insertion point verified at `TxPruner.cpp:141-176` |

</phase_requirements>

## Answers to the Two Mandated Research Questions

### Q1 — Durability monotonicity: can ANY path regress `Durable`→`Accepted` post-merge?

**Answer: NO in-process regression path exists on `2af184fa1`.** The journal (`upload_journal` CF, coldstore RocksDB) has exactly three writers, each verified end-to-end:

1. **Put-birth** (`LocalBlockStore::Put`, `thirdparty/sgns-blockstore/src/LocalBlockStore.cpp:430-517`): writes a `PendingUpload` journal record ONLY when the block's bytes are absent — verbatim: *"Read-before-write (Pitfall 6): a RocksDB Put overwrites silently, so alreadyPresent must be computed before the batch - and the journal record is written only for NEW blocks, so a re-Put never regresses an UploadedDurable state."* [VERIFIED: LocalBlockStore.cpp:459-463, enforced at :496-507 (`if (!already_present)` guards the journal + spill-time Puts)]. A re-spill of still-present bytes touches nothing.
2. **Drain mark** (`ColdStorageManager::DrainOnce` step iii, `ColdStorageManager.cpp:557-577`): `MarkUploadedAccepted(cid)` fires ONLY on the `succeeded` list, which is populated exclusively from the cycle's snapshot of `GetUploadsInState(PendingUpload)` taken under `cold_store_mutex_` (:527-531 area). A `Durable` record is never in the Pending snapshot, so it is never re-marked. Comment verbatim: *"MarkUploadedAccepted ONLY for remote-present outcomes. The UploadedDurable transition is owned exclusively by AdvanceDurabilityOnce below."* [VERIFIED: ColdStorageManager.cpp:557-565]
3. **Durability mark** (`AdvanceDurabilityOnce`, `ColdStorageManager.cpp:595-726`, plus the Stop-final-flush twin at :378-379): marks EXACTLY the pre-flush `UploadedAccepted` snapshot via one batched `MarkUploadedDurableMany` — writes only `Durable`, per-item existence-gated, skip-and-continue on vanished records (`LocalBlockStore.cpp:1104-1158`). [VERIFIED]

**Snapshot disjointness closes the race:** the drain snapshot (Pending set) and the durability snapshot (Accepted set) are both enumerated under `cold_store_mutex_`; the sets are disjoint at snapshot time, so a CID can never be marked by both phases of concurrent cycles in a regressing order. A record's only in-process trajectory is `Pending → Accepted → Durable`, or birth-after-disposal `NoRecord → Pending → …` (rebirth, monotone).

**The only `Durable`-record removals:** `EvictLocalAndMarkDisposed` (GC disposal: one sync WriteBatch deletes bytes + journal + spill-time and writes the disposed marker — verbatim *"three Deletes + one Put, all-or-nothing"*, [VERIFIED: LocalBlockStore.cpp:862-889]) and plain `EvictLocal` (unconditional, deletes journal + bytes, [VERIFIED: LocalBlockStore.cpp:1237-1263]). Both yield `NoRecord` — which the gate DEFERS (D-02). Remote S3 is never deleted (POLICY-01), so even that window never destroys the last copy.

**Critical nuance the plan must carry:** `TransitionJournal` (`LocalBlockStore.cpp:1166-1204`) is a blind write of the target state gated only on record EXISTENCE ("Read-journal-first (T-02-08)") — there is no state-machine precondition inside the library. Monotonicity is a property of CALLER discipline (snapshot-then-mark), not of the storage layer. Consequences:
- The in-compose re-check is **load-bearing for pre-admission staleness** (state changed between the evaluator's cycle and the erase) and **belt-and-braces for the post-read window**, which is closed by monotonicity rather than by the lock (see Lock-Order Analysis).
- Conservative decode is a further safety net, not a regression: any undecodable journal value decodes to `PendingUpload` — verbatim *"ANY unknown version or state byte decodes to PendingUpload - idempotent re-upload is the safe direction"* [VERIFIED: LocalBlockStore.cpp:166-172, applied at :1227-1230]. A corrupted record therefore gates as Pending → defer (never as Durable, never silently dropped).
- Out-of-process regression vectors (restore-from-backup of an older coldstore journal) yield Pending/Accepted → defer → safe under-erase direction. No action needed this phase.

### Q2 — Develop Phase 17 landing status

**Answer: LANDED — the stale roadmap row overstates the risk.** Evidence:
- `SuperGenius/.planning/phases/17-eligibility-policy-gating-dry-run/` contains all six `17-0N-PLAN.md` AND `17-0N-SUMMARY.md` files plus CONTEXT/RESEARCH/VALIDATION artifacts [VERIFIED: directory listing this session].
- Its substance is in-tree on `2af184fa1`: `PruneEligibility` (evaluator, Light+allowlist gates, spend-recency window, `PruningConfig`), the multi-element block-parse gate (`EvaluateDeltaBlockErasable`), the `/prune/` marker contract, and the `pruning.*` config knobs (`GeniusNode.cpp:518-536` reads them; `StartPruneTimerIfConfigured` at :5194).
- `SuperGenius/.planning/ROADMAP.md:363` still reads `| 17. Eligibility, Policy & Gating (Dry-Run) | v1.2 (this branch) | 0/6 | Planned (planning complete) | — |` while rows 18/19 show Complete — the table is stale, not the work. [VERIFIED: ROADMAP.md:358-363]
- The only remaining develop-side phase touching this area is Phase 20 (reclamation proof: `CompactRange kForce` + measured bytes) — it does not touch the evaluator or the erase path's admission logic.

**Composition consequence (SC3):** the "external gate" is effectively resolved; PRUNE-03's placement rule (gate in `RunCycle`'s filter, evaluator pure) remains the correct defense against any future develop-side dry-run/reporting change. `PruneEligibility.hpp`'s last modification is the Phase-13 merge commit `d556f86de` (bootstrap branch) — the merge itself touched the evaluator file; the purity contract survived intact. [VERIFIED: git log --follow]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Cold-durability gate admission (which groups may erase) | TxPruner service (`RunCycle` filter) | — | TxPruner owns cycle mutation policy; the evaluator must stay pure (PRUNE-03, D-C6) |
| Journal-state evidence read | GlobalDB facade → ColdStorageStack bridge → ColdStorageManager | sgns-blockstore `LocalBlockStore` | Lifecycle-safe null-safe bridge already exists (`globaldb.cpp:1024-1036`); no domain type crosses the ungated header |
| In-compose re-check (SC2) | `GlobalDB::EraseEntry` compose critical section | — | The compose lock is the only critical section spanning guard→staging→commit; a TxPruner-side lock cannot cover the commit |
| Cold-tier presence signal (SC4 vacuous branch) | GlobalDB | — | `cold_manager_` null ⇔ no cold tier; needs a new public accessor (gap identified) |
| Deferral observability (`cold_deferred_groups` / `cold_unreadable_groups`) | `PruneCycleStats` + per-cycle INFO + `PruneStatus` | — | Existing counter home (`TxPruner.hpp:68`), already aggregated |
| Activation wiring + posture log (D-04/D-05) | `GeniusNode::StartPruneTimerIfConfigured` + `TxPruner` per-cycle construction | — | Wiring is the single policy owner; factory stays fail-closed Light-only |
| Journal-state driving in tests | Test fixtures (real GlobalDB + hermetic cold clients / direct LocalBlockStore) | — | D-08 hermetic-first; no live remote in Tier-1 |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| sgns-blockstore (vendored, `thirdparty/sgns-blockstore`) | frozen v1 (v1.1-pinned) | Journal (`upload_journal` CF), `LocalBlockStore::GetUploadState`, `FaultController` test seam | The only journal source of truth; v1.2 research row 1: zero new dependencies |
| RocksDB (via sgns-blockstore + SuperGenius datastore) | 9.4.0 (v1.1-pinned) | Hot store WriteBatch compose; coldstore journal CF | Existing atomicity boundary — no new store |
| GTest + ctest labels | ~1.14.0 | Tier-1 suites; `tier1_static_audit` parity | Existing CI contract surface |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `InMemoryS3AdminClient` (sgns-blockstore test kit) | vendored | Fake admin facade for flush-evidence driving in hermetic fixtures | Driving `Accepted`→`Durable` without network (durability-test precedent) |
| `SetColdStorageStackClientsForTesting` (`ColdStorageStack.hpp:286-292`) | in-repo | Process-global TEST-ONLY override injecting hermetic S3/admin clients into `OpenColdStorageStack` | Building a REAL cold-enabled GlobalDB hermetically (resurrection-test precedent, `cold_storage_resurrection_test.cpp:767-806`) |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| In-compose re-check inside `EraseEntry` | TxPruner-side lock composition (hold compose lock from caller) | Rejected: the compose lock is owner-vended (`MakeComposeLock`) and scoped to one compose; a caller-side scheme cannot span the commit and would duplicate the D-01 discipline |
| New guard inside `EraseEntry`'s existing guard block | A wrapper layer above `EraseEntry` | Rejected: every other erase driver (`EraseTransactionEntry` plain driver) would bypass a wrapper; the guard must live where ALL erases compose |

**Installation:** none — zero new dependencies (v1.2 STACK row 1, re-confirmed: this phase composes only in-repo mechanisms).

**Version verification:** not applicable — no external packages introduced. No registry lookups performed (none needed); no package-legitimacy surface.

## Package Legitimacy Audit

**Not applicable — this phase installs zero external packages.** All mechanisms are in-repo (`SuperGenius/src/**`, `thirdparty/sgns-blockstore` vendored frozen v1). No `npm`/`pip`/`cargo`-style additions; no new thirdparty build entries.

## Architecture Patterns

### System Architecture Diagram

```text
                        TxPruner::RunCycle (TxPruner.cpp:76-241)
                                      |
        (1) tick gate  (2) PruneEligibility::New + Evaluate()  <-- PURE (D-C6), no changes
                                      |
        (3) block-group work-list filter (:141-176)  <<== GATE INSERTION POINT (PRUNE-01/03)
                |  group admitted iff erasable AND (no_cold_tier OR GetColdUploadState(cid)==Durable)
                |  NoRecord/Pending/Accepted -> ++cold_deferred_groups (whole group deferred)
                |  Unreadable                -> ++cold_unreadable_groups + WARN (D-03)
                v
        (4) per-tx: fresh spent-ness re-verify (:198 kInterruptBeforeErase seam)
                |      <<== TOCTOU COUNTER-TEST fires here: flip journal Durable->Accepted/NoRecord
                v
        EraseTransactionEntryPruned (TransactionManager.cpp:4775)
                |
        EraseTransactionEntryWithMarker (:4718)  -- resolves tx -> ONE (path, cid)  [D-01 verified]
                |
        GlobalDB::EraseEntry(path, cid, marker)  (globaldb.cpp:1400)
                |
        +======= compose critical section (MakeComposeLock, :1419) =======+
        | guard 1 head list (:1434)          -- already takes lifecycle_mutex_  |
        | guard 2 pending root job (:1441)                                             |
        | guard 3 LRU cache (:1446)                                                     |
        | guard 4 resolved/seal (:1451)                                                |
        | guard 5 [NEW] cold-durability re-check (PRUNE-02):                          |
        |         no_cold_tier OR GetColdUploadState(cid)==Durable, else REFUSE       |
        |         (read path: lifecycle_mutex_ -> cold_store_mutex_ -> journal)       |
        | staging: StageEraseElement / [hook 1] StageBlockRemoval / [hook 2]          |
        |          raw remove / [hook 3] marker put -> ONE batch commit (:1492)       |
        +==============================================================================+
                |
        hot bytes GONE (single CID) + /prune/tx marker present (atomic)

  Concurrent writers to the journal (all under cold_store_mutex_):
    drainer:  Pending --Put-ack--> Accepted          (ColdStorageManager.cpp:527-577)
    AdvanceDurabilityOnce: Accepted --flush+pendingObjects==0--> Durable  (:595-726)
    GC disposal: Durable --EvictLocalAndMarkDisposed--> NoRecord (record deleted)
  => monotone in-process; regression only by test-forced direct CF write (D-07's probe)
```

### Recommended Project Structure

```text
SuperGenius/src/transaction/TxPruner.hpp          # PruneCycleStats: +cold_deferred_groups, +cold_unreadable_groups
SuperGenius/src/transaction/TxPruner.cpp          # named conjunct in group filter; counters; INFO clause; [new sibling interrupt step]
SuperGenius/src/transaction/TransactionManager.*  # (likely unchanged; erase drivers stay)
SuperGenius/src/crdt/globaldb/globaldb.hpp        # +public cold-active accessor; guard-5 contract on EraseEntry
SuperGenius/src/crdt/globaldb/globaldb.cpp        # +guard 5 inside compose; +accessor impl
SuperGenius/test/src/crdt/cold_prune_gate_test.cpp       # journal-injection matrix (Tier-1)  [name at planner discretion]
SuperGenius/test/src/crdt/cold_prune_toctou_test.cpp     # red-first counter-test (Tier-1)   [or one suite, two families]
SuperGenius/test/src/crdt/CMakeLists.txt          # registrations INSIDE if(SGNS_COLD_STORAGE) + LABELS Tier1 lines
```

### Pattern 1: Named conjunct at the cycle filter (PRUNE-03)

**What:** the cold gate is an additional admission condition in `RunCycle` step (3), beside `erasable_cids` membership — never inside `PruneEligibility::Evaluate`.
**When to use:** exactly here; this is the locked shape.
**Why (contract, verbatim):** *"PURE evaluator (D-C6): it runs on committed state only — driven from a timer cycle by the caller, NEVER from CRDT element callbacks (they fire pre-batch-commit). It performs ZERO writes: no Put, no Erase, no staging, no hooks. The Phase-18 TxPruner is the reuse seam — it calls Evaluate() verbatim and owns every mutation."* [VERIFIED: PruneEligibility.hpp:276-281]

```cpp
// Source: TxPruner.cpp:144-176 (existing shape the conjunct extends)
std::set<std::string> erasable_cids;
for ( const auto &report : result.block_reports )
{
    if ( report.erasable )
    {
        erasable_cids.insert( report.cid );
    }
}
// COLD CONJUNCT (D-04/D-05): when the node's GlobalDB has a cold tier,
// admit only groups whose delta-block CID is evidence-Durable.
// NoRecord/Pending/Accepted defer the whole group (cold_deferred_groups);
// Unreadable additionally WARNs and counts cold_unreadable_groups (D-03).
```

### Pattern 2: Guard inside the compose critical section (PRUNE-02)

**What:** the durability re-check is a new guard AFTER the existing four guards and BEFORE the first staging, mirroring their fail-closed posture — verbatim precedent: *"Guard evaluation runs INSIDE the compose critical section, so a concurrent PutElems cannot interleave between these checks and the commit (WR-02 closed by construction)"* [VERIFIED: globaldb.cpp:1426-1430].
**When to use:** whenever a destructive decision needs fresh evidence at commit time.
**Note on error shape:** guards 1-4 return `Error::INVALID_PARAMETERS` (nothing erased). A durability refusal is a DEFERRAL, not a policy violation — the planner should pick a distinguishable signal (distinct `GlobalDB::Error` value, or mapping at the TxPruner side into `cold_deferred_groups` instead of `stats.errors`) so SC1's "counter, not a failure reason" holds on the re-check path too. SC3's composition test then asserts the counter, not a warn-only path.

### Pattern 3: Hermetic cold-enabled GlobalDB (D-08a fixture)

**What:** real `GlobalDB::New(..., cold_options)` with TEST-ONLY client injection — the resurrection-test recipe [VERIFIED: cold_storage_resurrection_test.cpp:767-806]: `cold.endpoint = "hermetic.invalid"` ("overridden below - never contacted"), `SetColdStorageStackClientsForTesting(counting_s3, fake_admin)`, then clear the override immediately after construction. Real RocksDB hot store + real coldstore journal; zero network.

### Pattern 4: Dual-seam interrupt driving (D-07)

**What:** the counter-test needs the journal flipped BETWEEN gate admission (step 3) and the in-compose re-check. The established pattern is the two-seam dispatcher already in `tx_pruner_test.cpp:2327-2345` — verbatim: *"true: the TxPruner cycle seam; false: GlobalDB's compose seam"* — plus `globaldb_erase_test.cpp:436`'s `INSTANTIATE_TEST_SUITE_P(EraseInterruptSteps, ..., ::testing::Values(1, 2, 3))`. The new sibling TxPruner interrupt step (D-07's letter) occupies the admission→erase gap; GlobalDB's hook steps 1/2/3 stay available for compose-window tests (NOT the TOCTOU position — see Pitfall 2).

### Anti-Patterns to Avoid

- **Putting the conjunct inside `PruneEligibility::Evaluate`** — violates D-C6 purity, re-opens the Pitfall-3 quiet-widening risk, converts develop-side landings into rewrites (D-05 reversibility: costly).
- **Treating `NoRecord` as "no cold tier"** — a cold-enabled node with a not-yet-spilled CID also reads `NoRecord`; the two MUST be distinguished (SC4 needs a tier-presence signal, not a state value).
- **Keying gate semantics on journal-value corruption** — an undecodable journal value decodes conservatively to `Pending` [VERIFIED: LocalBlockStore.cpp:1227-1230]; corruption is NOT `Unreadable`. `Unreadable` is a read-path failure only (see Pitfall 5).
- **A new cross-store WriteBatch** — forbidden (Pitfall 3 of 11-02); the erase stays ONE hot WriteBatch; the journal is read, never written, by the gate.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Durability evidence read | A second journal accessor / re-parsed journal | `GlobalDB::GetColdUploadState` → `ColdStorageStack` bridge → `ColdStorageManager::GetUploadState` | Lifecycle-safe, null-safe, MI-02-correct mapping already proven in v1.1 Phases 10-11 [VERIFIED: ColdStorageStack.cpp:333-366] |
| Durability threshold semantics | A `<=`/numeric level comparison | Exact equality: `state == kEvictionDurabilityGate` where `kEvictionDurabilityGate = sgns::blockstore::UploadState::UploadedDurable` [VERIFIED: ColdStorageManager.hpp:135-138] | GC precedent [VERIFIED: ColdStorageManager.cpp:1072-1077]: verbatim *"the journal state must be EXACTLY kEvictionDurabilityGate - anything else (NoRecord/Pending/Accepted) or an unreadable read is not eligible"* — the gate mirrors this |
| Compose-lock discipline | A caller-side lock scheme | `crdt_datastore->MakeComposeLock()` (owner-vended `std::unique_lock<std::recursive_mutex>`, crdt_set.hpp:319 / crdt_datastore.hpp:385) | The D-01 bounded-hold discipline is already encoded; a second scheme forks the invariant |
| Hermetic S3/admin in tests | Local MinIO or recorded HTTP | `SetColdStorageStackClientsForTesting` + `InMemoryS3AdminClient` | Tier-1 fresh-clone-safe contract (no services); proven in resurrection/durability suites |
| Crash-window test positions | New ad-hoc pause points | The two existing seams (`TxPruner` cycle steps 1-4; GlobalDB erase hook steps 1-3) + ONE new sibling step per D-07 | The seams are the 18-06 crash-matrix contract surface; more seams dilute it |

**Key insight:** every load-bearing mechanism already shipped in v1.1/develop-18. This phase is a composition phase — the failure mode to avoid is RE-DERIVING any of them.

## Common Pitfalls

### Pitfall 1: Deferral counted as error (SC1's letter)
**What goes wrong:** the in-compose re-check refuses the erase → `EraseTransactionEntryPruned` returns failure → `RunCycle` counts `stats.errors` + WARN "Prune erase failed" — deferrals surface as failures, violating "counter, not a failure reason".
**Why it happens:** the per-tx erase loop's only outcomes today are success / log-and-continue error.
**How to avoid:** distinguishable refusal signal from guard 5 (distinct error code or an outcome the TxPruner maps to `cold_deferred_groups`); composition test asserts the counter AND that `errors` did not grow.
**Warning signs:** TOCTOU counter-test passing while `stats.errors` increments.

### Pitfall 2: Counter-test placed mid-compose (unprovable position)
**What goes wrong:** inducing the regression at GlobalDB's erase-hook step 2/3 (AFTER the re-check, BEFORE commit) defeats ANY read-then-commit implementation — the journal write is not excluded by the compose lock (different mutex, different RocksDB). Such a test is red forever and proves nothing implementable.
**Why it happens:** the mid-compose seam looks like the tightest TOCTOU probe.
**How to avoid:** the D-07 position is between gate admission and the erase call (the TxPruner-side seam — existing `kInterruptBeforeErase` position or the mandated new sibling). The post-re-check window is closed by MONOTONICITY (Q1) + Phase 16's Interaction-C ruling, not by this phase's lock — encode that two-layer story in the plan and the test names.
**Warning signs:** a counter-test that arms GlobalDB hook step 2 to flip the journal.

### Pitfall 3: Lock-order inversion introduced by the in-compose read
**What goes wrong:** the re-check inside the compose lock acquires `lifecycle_mutex_` then `cold_store_mutex_`; any path acquiring those in the opposite order (or `cold_store_mutex_` → compose lock) deadlocks.
**Why it happens:** silent ordering drift when a new read joins an established critical section.
**How to avoid:** verified safe today — the compose→`lifecycle_mutex_` edge ALREADY exists (guard 1: `GetCRDTHeadList` → `ActiveCRDTDataStore()` takes `lifecycle_mutex_` at globaldb.cpp:646-648, called at :1434 inside the lock); `ColdStorageManager` never calls GlobalDB/CrdtDatastore under `cold_store_mutex_` (`RunHotCleanup` runs OUTSIDE it on the raw `BufferStoreFace` batch, [VERIFIED: ColdStorageManager.cpp:1232-1315 comment + body]; GC's documented order is verbatim *"gc_pass_mutex_ -> gc_hook_mutex_ -> *cold_store_mutex_."* [VERIFIED: ColdStorageManager.hpp:637]). Keep it that way: the guard must call ONLY `GetColdUploadState`-shaped reads, nothing that re-enters the datastore.
**Warning signs:** any new call under `cold_store_mutex_` that touches the hot store; a test that parks a thread holding `cold_store_mutex_` while another composes.

### Pitfall 4: Group semantics drift (one non-Durable block must defer the whole group)
**What goes wrong:** per-tx gating inside the erase loop strands same-block siblings behind a partially-erased block.
**Why it happens:** the per-tx loop is the natural place to add a check.
**How to avoid:** gate at the GROUP level in step (3) — the existing group-or-defer discipline (`held_blocks`, D-04 precedent). With the single-CID removal set (D-01) one CID per group is checked; the matrix tests assert whole-group deferral (e.g., a 2-tx group with journal Pending ⇒ zero erases, both txs re-enumerated next cycle).

### Pitfall 5: Unreadable induction assumptions (D-08 matrix)
**What goes wrong:** (a) seeding a "corrupt" journal value expecting `Unreadable` — it decodes to `Pending`; (b) expecting a full-GlobalDB fixture can arm the library fault seam — it can't reach the `LocalBlockStore` handle (the manager owns it; a second `LocalBlockStore::Open` on the same dir hits RocksDB's lock).
**How to avoid:** seed the four VALUE states directly through the journal CF (`upload_journal`, published name [VERIFIED: LocalBlockStore.hpp:29-31]) with the 2-byte codec — verbatim: *"[version-byte 0x01] [state-byte] with 0x00=PendingUpload, 0x01=UploadedAccepted, 0x02=UploadedDurable"* [VERIFIED: LocalBlockStore.cpp:161-166]; absence = NoRecord. Induce `Unreadable` via the library's `FaultController` — verbatim enum: *"None, Unavailable, CorruptData, Unauthorized"* with `Unavailable` = *"all ops fail TemporarilyUnavailable (never NotFound, never false)"* [VERIFIED: FaultController.hpp:14-19] — arming `SetFault(FaultKind::Unavailable)` makes `GetUploadState` fail non-NotFound → bridge maps to `Unreadable` [VERIFIED: ColdStorageStack.cpp:344-354]. That arm needs a handle: either the matrix drives the Unreadable leg on a directly-constructed `ColdStorageManager` (durability-test fixture shape, where the fixture HOLDS the `LocalBlockStore`), or the plan adds a narrow test-only fault passthrough. Alternatively drive real states via `InMemoryS3AdminClient` flush evidence (Pending→Accepted→Durable naturally).
**Warning signs:** a matrix test asserting `Unreadable` from a garbage journal value.

### Pitfall 6: Tier-1 registration misses the static audit's contract
**What goes wrong:** new suites registered without labels (like today's `prune_eligibility_test`/`tx_pruner_test` — both unlabeled [VERIFIED: test/src/account/CMakeLists.txt:254, :401; absent from `-L Tier1` output]) never run in the fail-closed lane; or a `cold_*` registration without a `set_tests_properties` line breaks `tier1_static_audit` for EVERYONE.
**Why it happens:** the audit enforces parity mechanically.
**How to avoid:** register the new suites in `test/src/crdt/CMakeLists.txt` with a `cold_` prefix, inside `if(SGNS_COLD_STORAGE)` (any link of `sgns-blockstore::sgns-blockstore` outside the gate trips Check 2), each with `set_tests_properties(<name> PROPERTIES LABELS "Tier1")` (Check 1 parity). Never label them on the wallclock-soak pattern (Check 3 containment only bars `cold_storage_wallclock_soak`). [VERIFIED: tier1_audit_check.cmake:55-128]
**Warning signs:** `tier1_static_audit` failing in CI; `ctest -L Tier1` not listing the new suites.

### Pitfall 7: SC4 vacuous-branch discrimination via status triple
**What goes wrong:** inferring "no cold tier" from `GetColdStorageStatus()` defaults — a freshly started cold node can also report zeros/`drainer_healthy=false` briefly; ambiguous signal produces a flaky vacuous branch.
**How to avoid:** one new tiny public accessor on GlobalDB in the active-accessor shape (e.g. `bool HasColdStorage() const` — under `lifecycle_mutex_`: `cold_manager_ != nullptr && !shutdown_started_.load()`), mirroring `GetColdUploadState`'s shape at globaldb.cpp:1024-1036. Both the gate and guard 5 key the vacuous branch on it. [VERIFIED gap: `cold_storage_options_` private at globaldb.hpp:710; no public accessor exists]

### Pitfall 8: Gate reads during shutdown
**What goes wrong:** a cycle racing GlobalDB shutdown reads a tearing journal state.
**Why it happens:** `GetColdUploadState` already handles this — returns `NoRecord` once `shutdown_started_` — but `NoRecord` DEFERS, which is the safe direction; no change needed. Do NOT "fix" this into a permit.
**How to avoid:** keep the shutdown mapping as-is; document that shutdown-time NoRecord defers (under-prune). [VERIFIED: globaldb.cpp:1029-1033]

## Code Examples

### The exact-state gate shape (mirrors GC's precedent)

```cpp
// Source: ColdStorageManager.cpp:1072-1077 (GC's consumption — the shape to mirror)
auto state = local_block_store_->GetUploadState( entry.cid );
if ( !state.has_value() || state.value() != kEvictionDurabilityGate )
{
    ++gc_elig_state_;
    continue;
}
```

TxPruner-side translation (through the UNGATED enum — never the library type):

```cpp
// The five-value ungated enum, verbatim [VERIFIED: ColdStorageStack.hpp:60-74]:
// enum class ColdUploadState { NoRecord, Pending, Accepted, Durable, Unreadable };
switch ( globaldb.GetColdUploadState( cid ) )
{
    case ColdUploadState::Durable:
        admitted = true;                 // the ONLY permit
        break;
    case ColdUploadState::Unreadable:
        ++stats.cold_unreadable_groups;  // D-03: loud, dedicated counter + WARN
        break;
    case ColdUploadState::NoRecord:
    case ColdUploadState::Pending:
    case ColdUploadState::Accepted:
    default:
        ++stats.cold_deferred_groups;    // SC1: defer loudly, re-evaluate next cycle
        break;
}
```

### The interrupt seam (D-07's sibling)

```cpp
// Existing steps, verbatim [VERIFIED: TxPruner.hpp:241-248]:
// static constexpr int kInterruptAfterEvaluation = 1;
// static constexpr int kInterruptBeforeErase      = 2;  // aborts when hook returns true
// static constexpr int kInterruptBeforeStatus     = 3;
// static constexpr int kInterruptAfterStatus      = 4;
// D-07: a NEW sibling (e.g. kInterruptAfterColdGate = 5) firing after the
// cold conjunct admits a group, BEFORE the per-tx erase loop — the hook
// flips the journal (direct CF write) and returns false (observe, not abort),
// then the in-compose re-check must refuse the destroying erase.
```

### The journal CF seed codec (D-08 matrix)

```cpp
// Verbatim codec [VERIFIED: LocalBlockStore.cpp:159-166]:
//   [version-byte 0x01][state-byte]  0x00=PendingUpload, 0x01=UploadedAccepted,
//                                    0x02=UploadedDurable
// NoRecord  = NO record (absent key) — or EvictLocalAndMarkDisposed's delete
// Unreadable = NOT a value — read-path failure (FaultKind::Unavailable), see Pitfall 5
const std::string kJournalPending  = std::string{ '\x01', '\x00' };
const std::string kJournalAccepted = std::string{ '\x01', '\x01' };
const std::string kJournalDurable  = std::string{ '\x01', '\x02' };
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| TxPruner erases on spend-recency eligibility alone (network redundancy assumed) | Eligibility AND cold-durability evidence (this phase) | v1.2 | Closes AF-5 (erasing hot on undurable — the archive-node data-loss failure) |
| Gate question "is it durable enough?" (level arithmetic) | Exact-equality against `kEvictionDurabilityGate` | v1.1 Phase 11 | Never accept-is-durable; compile-time constant, no knob |
| Pre-merge anchors (`EraseEntry` ~:1374-1451, `GetColdUploadState` impl ~:1035, filter :147-185) | Re-located merged-line anchors (this doc) | Phase 13 merge `2af184fa1` | All pre-merge line cites in v1.2 research are stale; use this doc's anchors |

**Deprecated/outdated:** `SuperGenius/.planning/ROADMAP.md`'s Phase-17 status row (stale — see Q2). The v1.2 ARCHITECTURE doc's pre-merge file:line anchors (superseded by the table above).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `PruneCycleStats` consumers (INFO summary at TxPruner.cpp:282-296, `PruneStatus` aggregation, any UI/status JSON) tolerate two new fields without serialization breakage | Standard Stack / Patterns | Low — plain struct, counters only; if a proto/JSON surface serializes it, additive fields needed |
| A2 | The live-stack E2E smoke (D-08c) can reuse the resurrection-test full-wire topology (two GlobalDBs, injected clients) or the dev-gated MinIO runbook — exact vehicle is planner's choice | Test evidence | Low — worst case the smoke stays dev-gated Tier-2/3 either way |
| A3 | A `cold_`-prefixed suite name in `test/src/crdt/CMakeLists.txt` is the right registration home (vs. labeling the account-side `tx_pruner_test` extension) | Pitfall 6 | Low — audit only polices `test/src/crdt`; both work, but `cold_`+crdt home gets audit enforcement for free |
| A4 | No caller of `GlobalDB::EraseEntry` other than the pruned drivers exists that would be surprised by guard 5 refusing on non-Durable cold nodes | Pattern 2 | Medium — plain `EraseTransactionEntry` driver and any ops/tooling erase paths would also refuse; that IS fail-correct (they too must not destroy undurable hot data), but the plan should enumerate call sites and assert each one's posture |

**All other claims in this research are `[VERIFIED: file:lines]` from direct reads on `2af184fa1` this session.** No external documentation providers were consulted — the phase's domain is entirely in-repo (zero new dependencies, per STACK-v1.2 row 1, re-confirmed), and both mandated research questions are code-read questions answered above.

## Open Questions (RESOLVED)

1. **Guard-5 refusal signal shape**
   - What we know: guards 1-4 return `Error::INVALID_PARAMETERS`; SC1 wants deferrals as counters, not failure reasons.
   - What's unclear: distinct `GlobalDB::Error` value vs. TxPruner-side mapping of the existing code.
   - Recommendation: distinct error value (auditable at the GlobalDB surface), mapped to `cold_deferred_groups` in `RunCycle` — keeps `errors` semantics clean.
   - RESOLVED: Adopted by 14-02 — guard 5 returns a distinct `GlobalDB::Error::COLD_NOT_DURABLE` (Task 2(1)) and TxPruner maps exactly that error to `cold_deferred_groups` in the per-tx failure path (Task 2(3)), never to `stats.errors`.
2. **Unreadable-leg vehicle in the full-GlobalDB matrix**
   - What we know: value-seeding covers 4 states; `Unreadable` needs the fault seam, which needs a `LocalBlockStore` handle (Pitfall 5).
   - What's unclear: narrow test-only fault passthrough vs. driving the leg on a directly-constructed manager.
   - Recommendation: drive the leg on the durability-test fixture shape (manager held directly) for the bridge mapping + a gate-level assertion via the passthrough only if the planner finds the fixture split awkward.
   - RESOLVED: Adopted by 14-03 Task 1(4) with both legs — family-1 bridge leg (directly-held `LocalBlockStore` + `FaultKind::Unavailable` fault mapping) and gate-level hook leg (`cold_unreadable_groups` counter + one WARN, cycle continues).
3. **Per-tx vs per-group short-circuit of the in-compose re-check** (the agent's Discretion)
   - What we know: after a group's first erase commits, the block bytes are gone; later re-checks in the same group re-read a journal record that GC disposal could have deleted mid-group (→ NoRecord → refuse → remaining txs counted deferred; safe but noisy).
   - Recommendation: per-tx re-check (simple, always-safe); revisit only if the matrix shows mid-group deferral noise matters.
   - RESOLVED: CONTEXT agent's Discretion — resolved structurally by 14-02's per-erase guard-5 placement inside `EraseEntry`'s compose critical section (the re-check executes per-tx; the recommendation's posture holds).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| CMake build tree `SuperGenius/build/Windows/Release` | building tests | ✓ | populated (ctest enumerated 109+ tests) | — |
| `ctest -L Tier1 -C Release` | D-9 evidence | ✓ | 12 Tier-1 tests currently green-lane | — |
| GTest | all new suites | ✓ | ~1.14.0 (v1.1-pinned) | — |
| s3d/MinIO live stack | D-08c live smoke only | dev-gated (not probed this session) | — | Hermetic full-wire topology (resurrection-test recipe) as the deterministic stand-in; live leg stays Tier-2/3 |
| Node + gsd-tools | research/planning tooling | ✓ | working (this session) | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** live S3 stack (dev-gated smoke only — not a blocker; D-09 keeps it out of Tier-1).

## Tier-1 Fixture Posture (D-09 verification)

What v1.1 Tier-1 cold suites actually construct, verified this session:
- **Current Tier-1 lane** (`ctest -L Tier1`, 12 tests): `tier1_static_audit` + 11 cold suites (`cold_storage_link_proof/config_gate/spill/fallback/read_freeze_latency/durability/gc/gc_retrievability/fault_race/resurrection/soak`). `cold_storage_wallclock_soak` is deliberately excluded (dev-gated, audit-enforced). [VERIFIED: ctest -N -L Tier1 output]
- **Two fixture families to reuse:** (1) direct-construction — real `LocalBlockStore::Open` on a fresh temp dir + `ColdStorageManager` + `InMemoryS3AdminClient`, no GlobalDB (`cold_storage_durability_test.cpp:248-332`, `MakeManager` helper); (2) full-fidelity — real cold-enabled `GlobalDB::New` via `SetColdStorageStackClientsForTesting` + `endpoint="hermetic.invalid"` (`cold_storage_resurrection_test.cpp:767-806`). D-08's "real GlobalDB" requirement points at family (2); journal pre-seeding and the fault arm need family (1)'s handle ownership.
- **`prune_eligibility_test` (#30) and `tx_pruner_test` (#37) are NOT Tier-1 today** — registered without labels in `test/src/account/CMakeLists.txt` [VERIFIED: :254-269, :401-416]. D-09's "enter the Tier-1 contract" means NEW labeled registrations (the audit-compatible path in Pitfall 6), not a label change to the existing account-side suites (that would alter an existing suite's CI contract — a bigger move than this phase needs).

## Security Domain

`security_enforcement: true`, ASVS level 1, block-on-high (config verified).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | unchanged surfaces |
| V3 Session Management | no | unchanged surfaces |
| V4 Access Control | yes (role-gated destructive path) | GATE-01 fail-closed factory (`NodeType::Light`-only, `TxPruner.cpp:70-79`) stays untouched (D-04: nothing widens); the cold conjunct ADDS a restriction, never relaxes |
| V5 Input Validation | yes | Conservative journal decode (unknown bytes → `PendingUpload`, never Durable) [VERIFIED: LocalBlockStore.cpp:166-172]; `Unreadable` never conflated with absence (MI-02) |
| V6 Cryptography | no | no new crypto; CID verification paths untouched |
| V8 Data Protection (L1: integrity) | yes | The whole phase IS a last-copy integrity control: fail-closed destructive gating + atomic evidence/marker batch |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Destructive action on stale evidence (TOCTOU) | Tampering/Elevation | In-compose re-check under the compose lock (D-06) + monotonic journal (Q1) + fail-to-defer |
| Journal corruption silently permitting erase | Tampering | Conservative decode → Pending → defer; Unreadable → dedicated counter + WARN, never a permit |
| Role confusion (archive node erasing history) | Elevation | GATE-01 untouched; named conjunct only narrows Light's erase set further |
| Log-based evidence fabrication | Repudiation | Deferrals surface as named counters in the per-cycle INFO summary (RECL-03 discipline); no fabricated `bytes_reclaimed`-style numbers |

## Sources

### Primary (HIGH confidence — all direct reads on `dev_coldstorage_additions` @ `2af184fa1`, this session)
- `SuperGenius/src/transaction/TxPruner.cpp` — :70-79 factory; :105 per-cycle evaluator; :141-176 group filter; :198 interrupt; :203 erase call; :243-296 INFO summary
- `SuperGenius/src/transaction/TxPruner.hpp` — :68-117 `PruneCycleStats`; :241-248 interrupt steps
- `SuperGenius/src/transaction/TransactionManager.cpp` — :4718-4775 erase drivers; :5010-5039 `ResolveTransactionPathAndCID` (single-pair contract)
- `SuperGenius/src/transaction/PruneEligibility.hpp` — :275-298 purity contract (verbatim)
- `SuperGenius/src/crdt/globaldb/globaldb.cpp` — :1024-1036 `GetColdUploadState`; :1400-1500 `EraseEntry` (compose lock :1419, guards :1426-1460, hooks :1473-1483, commit :1492)
- `SuperGenius/src/crdt/globaldb/globaldb.hpp` — :576 decl; :710 private `cold_storage_options_` (accessor gap)
- `SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp` — :60-74 enum (verbatim); :286-292 test-client injection
- `SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp` — :333-366 bridge mapping (verbatim)
- `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp` — :378-379, :527-577 drain marks; :595-726 `AdvanceDurabilityOnce`; :727-731 `GetUploadState`; :1021-1090 GC gate; :1232-1315 hot-cleanup lock discipline; :1317-1362 `RunHotCleanup`
- `SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp` — :135-138 `kEvictionDurabilityGate` (verbatim); :637 lock-order doc (verbatim)
- `thirdparty/sgns-blockstore/src/LocalBlockStore.cpp` — :159-200 codec; :430-517 Put no-regress (verbatim :459-463); :862-889 disposal batch; :1104-1158 `MarkUploadedDurableMany`; :1166-1204 `TransitionJournal`; :1206-1235 `GetUploadState` + decode fallback; :1237-1263 `EvictLocal`
- `thirdparty/sgns-blockstore/include/sgns-blockstore/LocalBlockStore.hpp` — :29-43 CF names; :164-173 FaultController base
- `thirdparty/sgns-blockstore/include/sgns-blockstore/FaultController.hpp` — :14-19 `FaultKind` (verbatim)
- `SuperGenius/src/crdt/crdt_set.hpp` :319 / `crdt_datastore.hpp` :385 — `MakeComposeLock` (`std::unique_lock<std::recursive_mutex>`)
- `SuperGenius/src/account/GeniusNode.cpp` — :518-536 pruning config; :5194-5220 wiring; :700-703 cold posture INFO
- `SuperGenius/test/tier1_audit_check.cmake` — :44-132 all three checks
- `SuperGenius/test/src/account/CMakeLists.txt` — :254, :401 (unlabeled registrations)
- `SuperGenius/test/src/account/tx_pruner_test.cpp` — fixture family; :2327-2345 dual seam; :2392+ crash fixed-point
- `SuperGenius/test/src/crdt/globaldb_erase_test.cpp` — :394-436 interrupt-steps instantiation
- `SuperGenius/test/src/crdt/cold_storage_durability_test.cpp` — :248-332 direct-construction fixture
- `SuperGenius/test/src/crdt/cold_storage_resurrection_test.cpp` — :767-806 hermetic cold-GlobalDB recipe
- `SuperGenius/.planning/ROADMAP.md` — :358-363 stale status row; phase-17 artifacts directory listing
- ctest enumerations (build tree, this session)

### Secondary (MEDIUM confidence — prior milestone research, built on, anchors superseded)
- `.planning/research/SUMMARY-v1.2-rocksdb-backup.md` — phase-2 row; key decisions (gate location, counter, deferral semantics)
- `.planning/research/ARCHITECTURE-v1.2-rocksdb-backup.md` §(a), §3.3 — pre-merge anchors re-verified/shifted (documented in State of the Art)
- `.planning/research/PITFALLS-v1.2-rocksdb-backup.md` — Pitfalls 2/3/11, Interaction C, E
- `.planning/research/STACK-v1.2-rocksdb-backup.md` — row 1 (zero new dependencies)
- `.planning/research/FEATURES-v1.2-rocksdb-backup.md` — TS-1, AF-5

### Tertiary (LOW confidence)
- none

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new deps; all mechanisms read in-source this session
- Architecture: HIGH — gate placement, compose path, lock graph, and both test seams read end-to-end on the merged line
- Pitfalls: HIGH — each grounded in a verified code fact (audit rules, decode fallback, seam semantics, unlabeled registrations)

**Research date:** 2026-11-16
**Valid until:** 2026-12-16 (stable while `dev_coldstorage_additions` HEAD stays `2af184fa1`; any develop-side Phase-20 landing or evaluator change re-opens Q2's composition note)
