# Phase 13: Bootstrap Branch Merge & Composition Baseline - Context

**Gathered:** 2026-11-16
**Status:** Ready for planning

<domain>
## Phase Boundary

RECOVER-01 — the gate for ALL v1.2 recovery/walk work. Merge `fix/trust-genesis-bootstrap` (at `d556f86de`, ≡ `origin/fix/trust-genesis-bootstrap`) into `dev_coldstorage_additions` (at `7961ec264`, ≡ `dev_blockstore` ≡ `origin/dev_blockstore`) as a **pure composition** — recovery/bootstrap logic lands via merge, never re-derived — then prove the merged line:

1. **SC1** — merged and pushed; conflicts resolved per the `GeniusNode.cpp` merge checklist
2. **SC2** — full existing test suite green on the merged line, zero regressions vs a pre-merge baseline
3. **SC3** — the four post-merge checks observably pass: 4-term `HasBlock`, cold-chained `GetNodeWithoutRequest`, GATE-03 seal permanence intact, cold-before-peer fetch ordering
4. **SC4** — a composition-only grep gate proves no recovery/bootstrap logic was re-derived (checklist + evidence committed)

Out of this phase: any new product capability, evidence-aware serving (Phase 15), durability gate (Phase 14), new Tier-1 CI contract entries, seal measurement (Phase 17).

Requirements: RECOVER-01.

</domain>

<decisions>
## Implementation Decisions

### Merge execution & push posture
- **D-01:** **Push target is a NEW `origin/dev_coldstorage_additions`** — the v1.2 line name becomes canonical on origin; `origin/dev_blockstore` is accepted as going stale by decision (it sits at the same SHA `7961ec264` today, so nothing is lost at push time) — **Reversibility:** costly — creates a second canonical remote line; unwinding means re-pointing the team's remote line and rewriting the v1.2 remote-branch convention
- **D-02:** **Dirty-tree disposition is investigate-first, then a human checkpoint** — the working tree has local-only drift exactly on paths the merge itself moves: `SGProcessingManager` pointer `dc8a994cb→89d161b08` (+ untracked `test/fixtures/` inside it), `docs` pointer `77f4fcfd5→c6d8c8342`, untracked `test-data/cold-read-freeze` at SuperGenius root. The executor inspects what `89d161b08`/`c6d8c8342` contain vs the recorded pointers, reports, and the user picks reset-vs-keep BEFORE any merge command. Untracked scratch is presumed ignorable unless the investigation says otherwise
- **D-03:** **The executor performs the merge, step-gated** — `git merge --no-commit` dry-run first, resolve `GeniusNode.cpp` per the checklist, gate each resolution, then commit. Never a blind ours/theirs
- **D-04:** **Single evidence-complete push after ALL SCs pass** — merge commit + SC4 checklist/evidence push together, after SC2/SC3 pass locally. The push itself is a human checkpoint (executor never pushes — v1.1 D-03 discipline)

### Pre-merge baseline & SC2 surface
- **D-05:** **SC2 is proven by a local Windows pre/post pair** — pre-merge run on `7961ec264` + post-merge run on the merge commit, same tree, same env, CloudflareWARP disconnected for network-dependent suites (documented environmental constraint, A/B-verified 2026-11-12). SC2's gate closes on local green; the origin CI run after the push is recorded as confirmation, not a gate — **Reversibility:** costly — this defines the zero-regression evidence contract for the gate phase of v1.2; loosening it re-opens what "zero regressions" means
- **D-06:** **"Full existing test suite" = full local, matched scope** — Tier-1+2+3 including dev-gated suites where they also ran pre-merge; identical scope on both sides of the pair; skips/failures-to-exclude listed explicitly side-by-side (the pairing is what makes the comparison honest)
- **D-07:** **Baseline = reuse a recent local run if suitable** — the executor verifies a recent full local run on exactly `7961ec264` exists (recency + suite completeness criteria are executor discretion); otherwise falls back to a fresh pre-merge full run
- **D-08:** **SC2 numbers are recorded in plan SUMMARY / commit messages only** — no standalone committed baseline artifact (deliberately lighter than v1.1 D-05). NOTE: this lightness applies to SC2 numbers ONLY — SC4's checklist + evidence remains a committed artifact per its own letter

### SC3 verification-gate evidence
- **D-09:** **No new tests this phase** — the four checks are evidenced by filtered re-runs of existing v1.1 suites + the bootstrap branch's own validation tests + the existing GATE-03 check output, each cited per item in the SC4 checklist doc. Deterministic cold-before-peer enforcement is consciously deferred to Phase 15's evidence work — **Reversibility:** reversible — evidence posture; Phase 15 builds the real suites
- **D-10:** **Nothing new enters the CI Tier-1 contract this phase** (Tier-2/local-first posture for anything that does land) — the merged-line invariants ride existing Tier-1 suites only
- **D-11:** **GATE-03 via the existing enforcement re-run on the merged tree** — develop Phase 16 shipped a grep + ctest gate (zero quoted `"sealed"` literals in `src/`); re-run it as-is and cite the pass in the SC4 checklist. No new machinery
- **D-12:** **Cold-before-peer ordering = log-based observation** — run a cold-miss scenario and parse the fetch order from logs; observable-but-not-enforced is accepted for this phase (deterministic barrier-based proof is Phase 15 scope)

### Conflict resolution & the SC4 grep gate
- **D-13:** **The `GeniusNode.cpp` checklist is authored pre-merge and amended as-run** — predicted conflict hunks + per-hunk resolution rules from branch-diff analysis BEFORE the merge; as-run outcomes amend it after
- **D-14:** **Arbitration = compose-by-default, escalate collisions** — cold-storage wiring is ours, bootstrap/walk logic is theirs, and `getNode` (the Phase-9 cold-read seam) is the composition point. True semantic collisions → user checkpoint. Same escalation if the conflict surface exceeds the "only `GeniusNode.cpp`" forecast (MEDIUM confidence until executed). Prior precedent: the develop-merge's "keep our 6-arg `BuildPayoutOutputs` but pass develop's local burn value" compose-don't-pick style
- **D-15:** **The grep gate makes two mechanical assertions** — (a) *auto-merge snapshot comparison*: `merge --no-commit` auto-result vs the committed result; hand-edits are allowed ONLY in `GeniusNode.cpp` (+ legitimately expected submodule pointer takes); (b) *symbol identity*: walk-bearing files (`crdt_datastore.cpp`, `PruneEligibility.cpp`, `graphsync_dagsyncer.cpp`) are byte-identical to the branch blobs wherever our side hadn't also touched them — **Reversibility:** costly — this is the mechanical definition of "composition-only" that SC4's evidence cites; weakening it post-hoc re-opens the re-derivation question
- **D-16:** **SC4 checklist + evidence live in the workstream phase dir** — `.planning/workstreams/rocksdb-backup/phases/13-bootstrap-branch-merge-composition-baseline/` (root repo; `commit_docs: true`). Process evidence stays with the workstream (v1.1 D-05 precedent), not in the SuperGenius product repo

### The Agent's Discretion
- Mechanics of capturing the auto-merge snapshot (stash-of-result vs temporary worktree vs diff-to-expected)
- Recency/completeness criteria for the "suitable recent local run" check (D-07)
- Log-parsing approach for D-12 (grep patterns, which existing scenario drives the cold miss)
- Investigation report format and depth for the D-02 checkpoint
- Checklist hunk granularity (per-function vs per-region predictions)
- Whether the branch's own test files need Windows-specific gating when they land via merge
- Whether the pre-merge baseline run must precede the submodule-pointer disposition (ordering of D-02 vs D-07 — pointers affect what "on 7961ec264" means)
- Merge-commit message shape (how the as-run summary references the checklist)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream planning
- `.planning/workstreams/rocksdb-backup/ROADMAP.md` — Phase 13 goal, 4 success criteria, dependency gates
- `.planning/workstreams/rocksdb-backup/REQUIREMENTS.md` — RECOVER-01 (the phase's letter); milestone out-of-scope table
- `.planning/workstreams/rocksdb-backup/notes/develop-merge-erase-vs-cold-storage-gap.md` — the branch analysis @ `d556f86de` (forced walk = `retained ? GetStoredNode : getNode`; `CanRestoreElement`), merge forecast ("only `GeniusNode.cpp` conflicts; all CRDT seams auto-merge"), tiered-node model, WARP environmental note
- `.planning/workstreams/rocksdb-backup/STATE.md` — v1.2 key decisions; external-gate watch (develop Phase 17/20 timing)

### v1.2 research (2026-11-13)
- `.planning/research/SUMMARY-v1.2-rocksdb-backup.md` — external gate #2 (this merge) spec: the four post-merge verification items; the rederiving-the-bootstrap-branch pitfall → grep-gate rationale; "verify + test, don't build" (TS-6)
- `.planning/research/PITFALLS-v1.2-rocksdb-backup.md` — composition-only grep gate + merge checklist pitfall row; Windows walk-lane landmines (WARP is environmental — document, don't chase)
- `.planning/research/ARCHITECTURE-v1.2-rocksdb-backup.md` — "Forced walk post-merge" section (Rehydrate is bytes-only, never seals; the walk owns sealing after replay); seam file:line detail

### Prior phase context (binding decisions this phase composes onto)
- `.planning/workstreams/rocksdb-backup/milestones/v1.1-phases/09-cold-read-fallback-local-reads-graphsync-serving/09-CONTEXT.md` — the cold-read seam (`getNode` = cold-before-peers, offline-capable, CID-verified) the walk composes with; D-08 HasBlock local-only semantics
- `.planning/workstreams/rocksdb-backup/milestones/v1.1-phases/12-integration-hardening-fault-races-fresh-clone-proof/12-CONTEXT.md` — D-03 executor-never-pushes/human-checkpoint precedent; D-05 minimal-evidence precedent; Tier discipline and `ctest -L` lane rules

### Develop-line artifacts (the other side of the merge)
- `SuperGenius/.planning/phases/16-erasure-primitives-bookkeeping-hardening/16-VERIFICATION.md` — GATE-03 satisfaction record: zero quoted `"sealed"` literals in `src/` (grep + ctest gate) — the existing check D-11 re-runs
- `SuperGenius/.planning/phases/18-txpruner-service-first-real-prune/18-01-PLAN.md` — seal markers written at head-processing time (`crdt_datastore.cpp` :2136/:2179/:2187), never reverted by deletion — context for what the merge must not disturb
- `SuperGenius/test/testutil/local_trust_setup.hpp` — the trust-gate test migration surface (`WriteLocalTrustSgnsConfig` + `MakeNodeReadyWithLocalTrust`); the bootstrap branch is trust-genesis work, so any fixture fallout from the merge routes through this precedent
- `SuperGenius/.planning/ROADMAP.md` — develop's own v1.2 phase numbering (16-20): 16/18/19 complete, 17 (eligibility dry-run) + 20 (reclamation) pending — the external gate this phase must not disturb

### Code under merge (read before resolving anything)
- `SuperGenius/src/account/GeniusNode.cpp` — THE forecast conflict file (both sides touched it: our cold-storage wiring vs their `RequestBootstrapWalk`)
- Branch `fix/trust-genesis-bootstrap` blobs (read via `git show d556f86de:<path>`): `SuperGenius/src/crdt/impl/crdt_datastore.cpp` (forced walk), `SuperGenius/src/` `PruneEligibility.cpp` (`CanRestoreElement`), `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` (`HasStoredBlock`/`GetStoredNode`) — the symbol-identity targets of D-15b
- `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` (working tree, `FetchNodeFromColdStorage` :750-806) — our side of the seam the branch composes onto

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **The branch's own validation tests** — `fix/trust-genesis-bootstrap` ships its validated-recovery tests; they land via the merge and are cited per SC3 item (D-09)
- **Existing GATE-03 enforcement** (grep + ctest gate, develop Phase 16) — re-run as-is (D-11)
- **`local_trust_setup.hpp` migration kit** — if any legacy fixtures break on the merged trust-genesis flows, the proven recipe is `WriteLocalTrustSgnsConfig` + `MakeNodeReadyWithLocalTrust` (no ASSERT_* in fixture ctors — MSVC C2534)
- **v1.1 Tier-1 cold-storage suites** (`cold_storage_fallback_test`, cold-read/freeze, GC suites) — the filtered re-runs that evidence SC3 items and the SC2 post-merge leg

### Established Patterns
- **Compose-don't-pick merge resolution** (2026-09 develop-merge precedent): keep both sides' logic; when a hunk truly collides, wire theirs through our seam
- **Submodule pointer discipline**: detached HEAD at a submodule is normal; the pointer is the source of truth; the merge legitimately moves `SGProcessingManager`/`docs` pointers (verified: both differ between `7961ec264` and `d556f86de`)
- **Human checkpoints for pushes and one-way doors** (v1.1 D-03/D-15) — executor pauses with findings + options

### Integration Points
- `getNode` / `GetNodeWithoutRequest` → `FetchNodeFromColdStorage` — the Phase-9 cold-read seam; the walk's `getNode` fetch IS this seam, which is why composition is "nearly free"
- `markResolved`/`isResolved` — the only sanctioned seal access (GATE-03); untouched by the merge by construction
- Merge base is `8ff74636b` (old develop PR #402) — the merge carries the branch's own commits + pointer updates; our line already contains develop through `e28cdca1f`

</code_context>

<specifics>
## Specific Ideas

- Branch topology verified 2026-11-16: `dev_coldstorage_additions` (local HEAD) ≡ `dev_blockstore` ≡ `origin/dev_blockstore` @ `7961ec264`; `fix/trust-genesis-bootstrap` ≡ `origin/fix/trust-genesis-bootstrap` @ `d556f86de` — no drift between analysis commit and today's tips
- The user explicitly wants the v1.2 line name (`dev_coldstorage_additions`) canonical on origin, accepting that `origin/dev_blockstore` goes stale from this point
- Local Windows network-dependent suites require CloudflareWARP disconnected — environmental, not a code issue; document in evidence, don't chase

</specifics>

<deferred>
## Deferred Ideas

### Reviewed Todos (not folded)
- "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" (`.planning/todos/2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md`) — reviewed 2026-11-16, NOT folded: keyword-only match (score 0.6 on 'fix, cpp'), zero topical overlap with the merge phase

None — no other deferred ideas; discussion stayed within phase scope.

</deferred>

---

*Phase: 13-Bootstrap Branch Merge & Composition Baseline*
