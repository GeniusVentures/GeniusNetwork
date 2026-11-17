# Phase 14: Durability-Gated TxPruner Eligibility - Context

**Gathered:** 2026-11-16
**Status:** Ready for planning

<domain>
## Phase Boundary

PRUNE-01/02/03 — the durability gate on TxPruner erase eligibility for cold-enabled nodes. A cold-enabled node's TxPruner erases hot data only when every constituent block is evidence-Durable in cold — the gate fails closed, survives durability races (TOCTOU re-check at erase-commit under the compose lock), composes with (not into) `PruneEligibility::Evaluate`, and is vacuous on nodes with no cold tier (`prune_eligible(tx) AND (no_cold_tier OR cold_durable(cid))`).

1. **SC1** — erase proceeds only when every constituent block is `Durable` in cold; NoRecord, Pending, Accepted, and Unreadable journal states all defer loudly (fail closed — deferrals surface as a `cold_deferred_groups` counter, not a failure reason; next cycle re-evaluates)
2. **SC2** — an induced durability-state regression between evaluation and erase-commit cannot enable a destroying erase — evidence re-checked at erase-commit time under the compose lock (TOCTOU counter-test proves the last copy is never destroyed)
3. **SC3** — gate injected at `RunCycle`'s cycle/group filter while `PruneEligibility::Evaluate` stays contractually pure — composition test proves the cold-durability conjunct composes with the evaluator (develop Phase 17 landing remains a merge, not a rewrite)
4. **SC4** — on a node with no cold tier, TxPruner behavior is unchanged from today (gate vacuous)

Out of this phase: evidence-aware serving and the resurrection-gap fix (Phase 15), TxPruner×GC composition hardening incl. the Interaction-C mutual-exclusion ruling (Phase 16), `/prune/blk` marker staging (Phase 15), seal measurement (Phase 17), role-downgrade interlocks (Phase 18).

Requirements: PRUNE-01, PRUNE-02, PRUNE-03.

</domain>

<decisions>
## Implementation Decisions

### Constituent-block scope (gate rule)
- **D-01:** **Removal-set rule** — the gate checks exactly the CIDs whose bytes the erase physically deletes; today that is the group's single delta-block CID (`EraseTransactionEntryWithMarker` resolves the tx→CID map to ONE cid, and `EraseEntry` deletes that block's bytes + CRDT entries + marker atomically). SC1's "every constituent block" is ruled to MEAN the removal set, not every block the tx references. The researcher verifies `EraseEntry`'s removal set stays single-CID on the merged line — **Reversibility:** costly — the TOCTOU counter-test and audit evidence are built against this interpretation; widening the gate scope later re-opens SC1/SC2 evidence
- **D-02:** **NoRecord → defer-forever accepted** — a block with no journal record (never spilled, or journal deleted by GC disposal) defers its whole group, re-evaluated next cycle. Under-prune is the safe direction; distinguishing disposed vs not-yet-spelled (cross-marker skip) stays Phase 16 scope per research
- **D-03:** **Unreadable = dedicated `cold_unreadable_groups` counter + WARN line** — journal corruption gets visibility distinct from `cold_deferred_groups` (MI-02: never healthy-by-omission), but is NOT a permanent-stop class error (a single corrupt record must not brick pruning)

### GATE-01 widening (activation posture)
- **D-04:** **Automatic activation, no knob** — the gate is active whenever a Light node has cold storage enabled. Light+cold today IS the unsafe posture this phase fixes, so no operator opt-in and no new config surface; the `NodeType::Light`-only check is untouched (Pitfall 3 moot — nothing widens). SC4's vacuous branch covers Light+no-cold; Archive/Full remain never-prune
- **D-05:** **Named conjunct in the fail-closed factory** — the activation ruling lives inside the existing fail-closed factory + per-cycle evaluator construction (NodeType::Light AND cold-gate wiring) as a named conjunct — NOT a policy matrix in the evaluator. The evaluator stays contractually pure; wiring stays the single policy owner — **Reversibility:** costly — moving the ruling into the evaluator would violate the D-C6 purity contract PRUNE-03 protects and re-open the Pitfall-3 quiet-widening risk

### TOCTOU re-check strictness
- **D-06:** **In-compose re-check** — the journal state read happens inside the same critical section that composes/commits the destructive WriteBatch (a gate hook in `EraseEntry`'s compose path, or equivalent lock composition). No window between re-check and commit. The exact mechanism (hook vs lock-order) is research/planner work, and must not contradict Phase 16's Interaction-C mutual-exclusion ruling (durability reads used for destructive decisions) — **Reversibility:** costly — a weaker placement rework ripples into Phase 16's ruling and re-opens SC2's letter
- **D-07:** **Induced regression, red-first** — the TOCTOU counter-test flips the journal Durable→Accepted (or Durable→NoRecord) between gate admission and erase-commit via the existing interrupt-seam pattern (a new interrupt point, sibling of `kInterruptBeforeErase` at `TxPruner.cpp:198`), written red-first, proving the in-compose re-check reads fresh state and refuses the destroying erase. Staleness-only testing + a monotonicity doc was explicitly rejected — SC2's letter requires induced regression

### Test evidence posture
- **D-08:** **Hybrid state driving** — (a) journal-injection state matrix: pre-seed the journal column family directly into each of the 5 states (NoRecord/Pending/Accepted/Durable/Unreadable) against a real GlobalDB, no live remote, deterministic, Unreadable trivially inducible; (b) the red-first in-compose TOCTOU counter-test; (c) ONE dev-gated live-stack E2E smoke proving real drainer transitions (Accepted→Durable via flush) pass the gate. Mirrors v1.1 hermetic-first discipline; the gate reads the journal, not the bytes, so injection is faithful
- **D-09:** **Tier-1 now for the deterministic suite** — the journal-injection suite + TOCTOU counter-test enter the CI Tier-1 contract this phase (fresh-clone-safe: real RocksDB, no services; v1.1 already runs cold-storage Tier-1 suites). The live E2E smoke stays dev-gated Tier-2/3 — **Reversibility:** costly — Tier-1 is a contract surface the Phase 19 three-platform capstone builds on; removing entries mid-milestone re-opens the Tier-1 definition

### The Agent's Discretion
- Exact in-compose mechanism (gate hook inside `EraseEntry` vs TxPruner-side lock composition) — researcher rules, planner shapes
- Interrupt-point naming/placement for the TOCTOU counter-test
- Whether the in-compose re-check executes per-tx (vacuous after a group's first destructive erase) or is short-circuited per-group — mechanical, both safe if inside the compose
- Journal pre-seeding test helpers and fixture reuse specifics from the v1.1 GC/cold suites
- The Light+cold posture log line and how gate counters surface in the per-cycle INFO summary
- Additional `PruneCycleStats` counter naming beyond `cold_deferred_groups` / `cold_unreadable_groups` (e.g. a permitted/checked counter)
- Composition-test shape proving the cold conjunct composes with the evaluator (SC3)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream planning
- `.planning/workstreams/rocksdb-backup/ROADMAP.md` — Phase 14 goal, 4 success criteria, soft dependency on Phase 13 (evidence finalizes on the merged line), research flag
- `.planning/workstreams/rocksdb-backup/REQUIREMENTS.md` — PRUNE-01/02/03 (lines 21-23); milestone out-of-scope table
- `.planning/workstreams/rocksdb-backup/STATE.md` — v1.2 key decisions (gate location, evaluator purity, pruner sequencing, external gates)
- `.planning/workstreams/rocksdb-backup/phases/13-bootstrap-branch-merge-composition-baseline/13-CONTEXT.md` — the merged-line baseline this phase builds on; Tier discipline and evidence-posture precedents
- `.planning/workstreams/rocksdb-backup/notes/develop-merge-erase-vs-cold-storage-gap.md` — the erase-vs-cold gap analysis; tiered-node model

### v1.2 research (2026-11-13)
- `.planning/research/SUMMARY-v1.2-rocksdb-backup.md` — phase-2 row (gate letter + external gate: keep the cold conjunct separate); key-decisions section (gate location, counter, deferral semantics)
- `.planning/research/ARCHITECTURE-v1.2-rocksdb-backup.md` — §"(a) Durability-gated TxPruner eligibility" (gate location, journal-state handling, `GetColdUploadState` bridge, counter); §3.3 TxPruner×GC composition (sequence, not unify)
- `.planning/research/PITFALLS-v1.2-rocksdb-backup.md` — Pitfall 2 (durability-gate TOCTOU), Pitfall 3 (GATE-01 loosening), Pitfall 11 (under-erase direction), Interaction C (durability reads shared by destructive systems — Phase 16 ruling this phase must not contradict)
- `.planning/research/STACK-v1.2-rocksdb-backup.md` — row 1 (zero new dependencies; GATE-01 widened by config, not code rework); seams list
- `.planning/research/FEATURES-v1.2-rocksdb-backup.md` — TS-1 (durability-gated eligibility), AF-5 (the erasing-hot-on-undurable failure this phase kills)

### Develop-line artifacts (the other side of the composition)
- `SuperGenius/.planning/ROADMAP.md` — develop's own phase numbering; Phase 17 (eligibility dry-run) PENDING — the external gate whose landing must stay a merge
- `SuperGenius/.planning/phases/18-txpruner-service-first-real-prune/18-01-PLAN.md` — the TxPruner service + fixed-point + observability that landed (PruneCycleStats home)

### Code under change (merged line `dev_coldstorage_additions` @ `2af184fa1`)
- `SuperGenius/src/transaction/TxPruner.cpp` — :70-79 GATE-01 fail-closed role gate; :141-176 block-group work-list filter (THE gate insertion point); :198 interrupt seam (`kInterruptBeforeErase`); :203 `EraseTransactionEntryPruned` call; :285 per-cycle INFO summary
- `SuperGenius/src/transaction/TxPruner.hpp` — :68 `PruneCycleStats` (counter home); :210 `RunCycle` contract; :225 permanent-stop classification
- `SuperGenius/src/transaction/TransactionManager.cpp` — :4718 `EraseTransactionEntryWithMarker` (single-CID removal set, atomic two-level erase + marker pair in one WriteBatch); :4775 `EraseTransactionEntryPruned`
- `SuperGenius/src/crdt/globaldb/globaldb.hpp` — :576 `GetColdUploadState(const CID&)`; :43 `ColdUploadState` forward decl
- `SuperGenius/src/crdt/globaldb/globaldb.cpp` — `GetColdUploadState` impl (~:1035 pre-merge; re-locate on merged line)
- `SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp` — :60-74 ungated upload-state enum; :222 null-safe bridge (cold-disabled → gate vacuous)
- `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp` — :1072-1076 GC's `kEvictionDurabilityGate` consumption precedent (the gate mirrors this shape); `AdvanceDurabilityOnce` (durability monotonicity research target — researcher locates exact home)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`PruneCycleStats`** (`TxPruner.hpp:68`) — existing counter struct (examined/eligible/erased/held_blocks/skipped/errors/duration_ms/generation); `cold_deferred_groups` + `cold_unreadable_groups` join it; the per-cycle INFO line and `PruneStatus` already aggregate it
- **`GlobalDB::GetColdUploadState` bridge** — lifecycle-safe, null-safe through `ColdStorageStack` (cold-disabled node returns the vacuous path); mirrors GC's consumption of `kEvictionDurabilityGate`
- **Interrupt seam** (`InterruptRequested` / `kInterruptBeforeErase`, `TxPruner.cpp:198`) — the established injection pattern the TOCTOU counter-test extends with a sibling interrupt point
- **v1.1 cold-storage/GC test fixtures** — GlobalDB+ColdStorageManager construction kit the journal pre-seeding helpers build on
- **`EraseTransactionEntryWithMarker`** — atomic two-level erase + marker pair (value-XOR-marker holds in-batch); the compose path the re-check joins

### Established Patterns
- **Group-or-defer discipline** (develop D-04) — the cold gate reuses the same whole-group semantics: one non-Durable block defers its entire group
- **Fail-closed factory + per-cycle re-check** (GATE-01) — the named activation conjunct extends this pattern in place rather than replacing it
- **Hermetic-first CI + dev-gated live evidence** (v1.1 discipline) — D-08/D-09 apply it: deterministic injection in Tier-1, live smoke dev-gated
- **Red-first counter-tests** (v1.1 resurrection-suite precedent) — D-07's TOCTOU test is written failing-first
- **Fresh spent-ness re-verify before erase** (`TxPruner.cpp:326`) — the existing pre-erase re-verify pattern the durability re-check parallels

### Integration Points
- `RunCycle` step (3), the block-group work-list filter — gate admission point (group enters work list iff erasable AND cold-Durable)
- `EraseEntry`'s WriteBatch compose path — the in-compose durability re-check home (SC2)
- `ColdUploadState` mapping — Durable permits; NoRecord/Pending/Accepted/Unreadable defer (Unreadable additionally WARNs + dedicated counter)
- Per-cycle INFO summary + `PruneStatus` — gate counters surface to operators
- The cold conjunct stays a separate predicate argument so develop's Phase 17 evaluator lands as a merge (v1.2 converged decision)

</code_context>

<specifics>
## Specific Ideas

- Merged-line state verified: `dev_coldstorage_additions` @ `2af184fa1` ≡ `origin/dev_coldstorage_additions` (Phase 13 merge pushed) — all Phase 14 evidence lands directly on this line
- Research directives (plan with `--research-phase`): (1) durability monotonicity — can ANY path regress `Durable`→`Accepted` post-merge? Read `AdvanceDurabilityOnce` end-to-end; the answer determines whether the in-compose re-check is belt-and-braces or load-bearing, but SC2 mandates the re-check either way; (2) develop Phase 17 (eligibility dry-run) landing status — keep the cold conjunct separate so its landing remains a merge
- The user ruling interpreting SC1: "constituent block" = the removal set of the erase driver (one delta-block CID per group today)
- Reversibility ratings on D-01/D-05/D-06/D-09 mark the audit-facing contract decisions; the rest are plainly reversible

</specifics>

<deferred>
## Deferred Ideas

### Reviewed Todos (not folded)
- "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" (`.planning/todos/2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md`) — keyword-only match (score 0.2 on 'path'), zero topical overlap; same ruling as Phase 13 (reviewed 2026-11-16, not folded)

None — no other deferred ideas; discussion stayed within phase scope.

</deferred>

---

*Phase: 14-Durability-Gated TxPruner Eligibility*
