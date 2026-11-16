# Phase 13: Bootstrap Branch Merge & Composition Baseline - Pattern Map

**Mapped:** 2026-11-16
**Files analyzed:** 5 (1 hand-resolved code file, 2 phase-dir document artifacts, 1 conditional test-file set, 1 bookkeeping commit)
**Analogs found:** 5 / 5

> **This is a git-merge composition phase, not a feature build.** The "pattern" surface is: (1) the single hand-resolved conflict in `GeniusNode::ShutdownForDestruction()`, (2) the D-13 checklist + SC4 evidence documents in this phase dir, (3) branch test files that land via merge and *may* need Windows handling. Every analog below was read this session and verified git-tracked (`git ls-files` non-empty in its owning repo). All line numbers for working-tree files are from the current checkout at `7961ec264`.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `SuperGenius/src/account/GeniusNode.cpp` (conflict resolution inside `ShutdownForDestruction()`, working tree :2572-2640) | service (node lifecycle teardown) | event-driven (shutdown ordering / cancellation) | in-file: same-function timer/handle cancellation blocks :2598-2620 | exact (in-file) |
| `.planning/workstreams/rocksdb-backup/phases/13-bootstrap-branch-merge-composition-baseline/13-MERGE-CHECKLIST.md` (D-13 checklist + SC4 gate evidence; name at planner discretion) | config (process checklist/evidence doc) | file-I/O (authored pre-merge, amended as-run) | `.../v1.1-phases/12-integration-hardening-fault-races-fresh-clone-proof/12-FRESH-CLONE-CHECKLIST.md` | exact (role + lifecycle) |
| SC3/SC4 per-item verification record (same doc or companion; D-09/D-11 citations) | config (verification record) | file-I/O (evidence tables) | `12-VERIFICATION.md`; `SuperGenius/.planning/phases/16-erasure-primitives-bookkeeping-hardening/16-VERIFICATION.md` | exact (role) |
| Branch test files landing via merge (9 `M` files, e.g. `test/src/blockchain/node_startup_test.cpp`, `test/src/account/prune_eligibility_test.cpp`, `test/src/account/tx_pruner_test.cpp`) — conditional Windows handling only | test | event-driven (node-lifecycle E2E) | `node_startup_test.cpp:307-313` (`#ifdef _WIN32` budget pattern); `test/testutil/local_trust_setup.hpp` (fixture kit) | role-match (conditional) |
| Root-repo bookkeeping: SuperGenius pointer bump + evidence commit (single root commit) | config (bookkeeping commit) | batch | develop-merge precedent root bump `53a77a7` (process, cited in 13-RESEARCH) | role-match (process-only) |

**Important negative space for the planner:** NO new SuperGenius source/test/CMake files are authored this phase (D-09: no new tests; D-10: nothing new enters CI Tier-1). The branch's 29 `M` paths land as merge blobs or auto-merges — byte-identity/hunk-preservation gates (D-15) *prohibit* hand-edits anywhere except `GeniusNode.cpp`. Any Windows gating of landed test files is therefore **post-merge-commit scope**, and the recommended default is **no gating** (fail-open default lane; they were green on develop — see 13-RESEARCH "Branch validation tests landing via the merge").

## Pattern Assignments

### `SuperGenius/src/account/GeniusNode.cpp` (service, event-driven — THE only hand-resolved file)

**Analog:** in-file — the cancellation blocks of `ShutdownForDestruction()` itself. The branch's insertion is structurally identical to three blocks already in the function; the resolution introduces zero novel shapes.

**"Ours" side, verbatim** (working tree :2582-2596 — the conflict region's our-side content):

```cpp
        // Drain barrier: an in-flight StateTransition body (e.g. the detached
        // migration thread's INITIALIZING_DATABASE -> InitDatabase) may have
        // passed the shutdown gate before shutdown_started_ was set. Acquiring
        // lifecycle_mutex_ here waits for that body to finish so every member
        // read below -- tx_globaldb_ in particular -- observes final state, and
        // the tx_globaldb_->ShutdownNow() below stops/joins the CRDT rebroadcast
        // worker instead of leaking it to process exit (run 41936126485 exit-time
        // SegFault). Pairs with the post-lock shutdown re-check in
        // StateTransition: after this barrier no body is running and none can
        // start. Recursive mutex: safe if teardown is ever reached from a body
        // thread. Sits BEFORE io teardown so a blocked body can still complete;
        // bounded by one state body.
        {
            std::lock_guard<std::recursive_mutex> lifecycle_lock( lifecycle_mutex_ );
        }
```

**"Theirs" side, verbatim** (branch blob `d556f86de`, from the merge-tree result @ merged-blob line 2795; verified read-only in 13-RESEARCH):

```cpp
        {
            std::lock_guard<std::recursive_mutex> lifecycle_lock( lifecycle_mutex_ );
            if ( bootstrap_walk_timer_ )
            {
                boost::system::error_code ignored;
                bootstrap_walk_timer_->cancel( ignored );
            }
            if ( trust_bootstrap_sync_handle_ )
            {
                trust_bootstrap_sync_handle_->cancel();
                trust_bootstrap_sync_handle_.reset();
            }
        }
```

**In-function precedent the insertion copies** (working tree :2605-2620 — the *established* cancellation shapes in this exact function; note `bootstrap_walk_timer_->cancel( ignored )` is byte-for-byte the `gc_timer_`/`prune_dry_run_timer_` shape, and `trust_bootstrap_sync_handle_->cancel()` is the `health_check_handle_->cancel()` shape):

```cpp
        // Cancel bootstrap health check timer
        if ( health_check_handle_ )
        {
            health_check_handle_->cancel();
        }

        if ( gc_timer_ )
        {
            boost::system::error_code ignored;
            gc_timer_->cancel( ignored );
        }
        if ( prune_dry_run_timer_ )
        {
            boost::system::error_code ignored;
            prune_dry_run_timer_->cancel( ignored );
        }
```

**Compose rule (D-14 style, mechanical — encode verbatim in the D-13 checklist):** keep OUR comment block :2582-2593 verbatim; keep the lock-scope opening `{ std::lock_guard<std::recursive_mutex> lifecycle_lock( lifecycle_mutex_ ); }` (identical on both sides); insert THEIR two `if` blocks *inside* the lock scope; keep the closing `}`. Optional: amend the comment's last line to note walk-timer cancellation also happens under the barrier. No semantic collision — both sides want the lock acquired before member teardown; theirs adds member cleanup inside it.

**Coding-standard anchors** (the only authored lines this phase): Ullman braces, `m_`/trailing-underscore members (`bootstrap_walk_timer_`, `trust_bootstrap_sync_handle_` — already branch-named, keep as-is), `ignored` error-code locals match the sibling blocks.

**Gate constraint:** this is the ONLY file where `merge --no-commit` result → committed result may differ (D-15a assertion 2 reviews exactly this delta; assertion 1 requires an empty diff everywhere else).

---

### `13-MERGE-CHECKLIST.md` — D-13 checklist + SC4 evidence (config doc, file-I/O; committed per D-16, `commit_docs: true`)

**Analog:** `.planning/workstreams/rocksdb-backup/milestones/v1.1-phases/12-integration-hardening-fault-races-fresh-clone-proof/12-FRESH-CLONE-CHECKLIST.md` (tracked, root repo) — the workstream's proven "checklist that becomes evidence" shape: authored as a runbook, status header flipped to COMPLETE, tables filled as-run, committed in the phase dir.

**Status-header pattern** (12-FRESH-CLONE-CHECKLIST :3-5 → phase 13 opens PREDICTED pre-merge, amended to COMPLETE as-run):

```markdown
Status: **COMPLETE 2026-11-10** — all three SC4 legs green in SuperGenius Tag
Build run 42905264387 (workflow_dispatch, dev_blockstore @ 9994718ce,
thirdparty tag `test_coldstorage_rtti`, run_tests=true, cold_storage=true,
all 15 jobs success). Evidence tables below.
```

**Fail-closed topology/SHA table pattern** (:7-12 → phase 13 records branch tips, merge base `8ff74636b`, merge-tree OID regenerated at execution time):

```markdown
| Repo | Branch | Local SHA | Remote SHA | Pushed? |
|------|--------|-----------|------------|---------|
| SuperGenius | dev_blockstore | 6ed70cd999... | 6ed70cd999... | YES (user pushed 2026-10-28; ...) |
```

**Human-checkpoint section pattern** ("## User actions (the D-03 checkpoint)", :44+) — numbered imperative steps for the *user* (push/dispatch), matching phase 13's D-02 (submodule reset-vs-keep) and D-04 (single evidence-complete push creating `origin/dev_coldstorage_additions`) checkpoints. The executor-never-pushes split (steps executed by user vs. verified by executor) is exactly the v1.1 D-03 discipline D-04 restates.

**Evidence-table pattern** ("Platform results", "Audit result" sections) — per-leg result lines with run URLs/counts and configure-evidence quotes; phase 13's analog legs are SC2 pre/post pairs, SC3 four-check citations, D-15a/D-15b gate outputs.

---

### SC3/SC4 verification record (config doc, file-I/O)

**Analog 1:** `.../12-integration-hardening.../12-VERIFICATION.md` (tracked, root repo) — frontmatter + per-criterion evidence tables.

**Frontmatter pattern** (:1-9):

```markdown
---
phase: 12-integration-hardening-fault-races-fresh-clone-proof
workstream: rocksdb-backup
requirement: TEST-02
verdict: VERIFIED
date: 2026-11-10
status: passed
score: 4/4 success criteria verified
verification_method: goal-backward, evidence-based (...)
---
```

(Phase 13's requirement is RECOVER-01; score denominator = 4 success criteria SC1-SC4.)

**Per-criterion table pattern** (:20-31):

```markdown
| Evidence inspected | Detail | Status |
|---|---|---|
| `SuperGenius/test/src/crdt/cold_storage_fault_race_test.cpp` | Exists; **13 TEST_F cases counted** — exactly as claimed: ... | ✓ |
```

→ phase 13 rows: SC3 item 1 (4-term `HasBlock` — `cold_storage_fallback_test` filtered re-run + code quote), item 2 (`GetNodeWithoutRequest` cold chain — `D01`/`D03`/`SC4_RehydrateSilence_BytesOnlyNoMarkers`), item 3 (GATE-03 grep 0 matches + `EraseSurfaceGateTest.SealKeyHasNoProductionHome`), item 4 (D-12 log-ordering observation citing the `"cold read: rehydrated CID {} through the cold chain"` / `"cold read: chain miss for CID {}"` parse).

**Analog 2:** `SuperGenius/.planning/phases/16-erasure-primitives-bookkeeping-hardening/16-VERIFICATION.md` (tracked, in-submodule) — the GATE-03 record whose re-run D-11 cites. Copy its **verifier-command-with-count evidence style**: `"sealed"` quoted literal count in src/ = 0 (verifier grep); and its "Behavioral Spot-Checks" table shape (`| Behavior | Command | Result | Status |`) for the quote-safe PowerShell invocation (13-RESEARCH Pitfall 1: `git grep -n sealed -- src/ | Select-String -SimpleMatch '"sealed"'` — naive quoting produced a false 49-match count).

---

### Branch test files landing via merge (test, event-driven — conditional handling only)

**Files:** the 9 their-side `M` test files (full list in 13-RESEARCH file inventory): `test/src/blockchain/node_startup_test.cpp`; `test/src/account/{prune_eligibility_test, transaction_manager_certificate_fallback_test, transaction_manager_pending_lifecycle_test, tx_lookup_tri_state_test, tx_pruner_test}.cpp`; `test/src/crdt/{crdt_datastore_test, globaldb_erase_test}.cpp`; `test/testutil/genius_node_test_access.hpp`.

**Analog 1 (Windows in-file gating):** `node_startup_test.cpp:301-313` (tracked) — the branch-modified file *already carries* the repo's Windows-budget pattern; if any walk case flakes on Windows, this is the shape (NOT a skip — an order-of-magnitude budget relaxation with an explanatory comment):

```cpp
    // ... READY is
    // gated on the trust lifecycle, which is replication-bound: the node must
    // fetch the reviewed-genesis approval CID over graphsync and activate the
    // initial-burn quorum before it may report READY. A quorum cannot skip
    // those round trips, so the budget reflects the platform's replication
    // floor — Windows CI runners need an order of magnitude more than the
    // 10s the other platforms hold.
#ifdef _WIN32
    constexpr int kRegularReadyBudgetMs   = 60000;
    constexpr int kRegularReadyPollTimeMs = 90000;
#else
    constexpr int kRegularReadyBudgetMs   = 10000;
    constexpr int kRegularReadyPollTimeMs = kReadyPollTimeoutMs;
#endif
```

**Analog 2 (fixture fallout):** `test/testutil/local_trust_setup.hpp` (tracked) — the canonical_ref migration kit. If legacy fixtures break on merged trust-genesis flows, the proven recipe is `WriteLocalTrustSgnsConfig` (:69-79 — single-node self-trust policy: node's own derived account as sole trusted peer + bootstrapper, thresholds 1/1, no ASSERT_* in helpers) composed with `MakeNodeReadyWithLocalTrust` (:86-120+ — waits for `WAITING_FOR_TRUST_GENESIS`/`WAITING_FOR_BURN_GENESIS`/`READY`, submits the bootstrapper's approval via `GeniusNodeTestAccess::ApproveConfiguredTrustGenesis`, tolerates `DUPLICATE_CANDIDATE_APPROVAL` only).

**Analog 3 (CMake-level, only if post-merge registration edits ever become necessary — none are expected since all 9 files are `M` with pre-existing registration):** `test/src/account/CMakeLists.txt:23-33` — the `if(MSVC) /WHOLEARCHIVE:$<TARGET_FILE:genius_node_test>` / `elseif(APPLE) -force_load` / `else()` `--whole-archive` wrapper pattern (identical block at `test/src/crdt/CMakeLists.txt:270-283`).

**Hard constraint to encode in the plan:** any edit to these files inside the merge commit fails D-15a by construction (`git diff --exit-code <merge-tree-OID> HEAD -- . ':!src/account/GeniusNode.cpp'` must be empty). Gating decisions ride SC2 observation → escalate → post-merge-commit scope, or defer.

---

### Root-repo bookkeeping (config, batch)

**Analog:** process precedent only — the develop-merge root bump (`53a77a7`, cited in 13-RESEARCH "Root repo posture"): one root commit advancing the SuperGenius pointer to the merge SHA *plus* the phase-dir evidence, acceptable in a single commit (D-16). Post-merge `git diff SuperGenius` from the root must show exactly old→new SHA, no `-dirty` (13-RESEARCH Pitfall 7). No file-level analog needed — this is a commit-shape pattern.

## Shared Patterns

### Compose-don't-pick merge arbitration (D-14)
**Source:** 2026-09 develop-merge precedent ("keep our 6-arg `BuildPayoutOutputs` but pass develop's local burn value" — recorded in 13-CONTEXT D-14 and 13-RESEARCH); mechanical form for this phase is the verbatim conflict + compose rule in the first Pattern Assignment above.
**Apply to:** the single `GeniusNode.cpp` hunk; the D-13 checklist's per-hunk resolution rules are authored from it pre-merge (D-13).

### Evidence-doc lifecycle: runbook → as-run record → committed artifact
**Source:** `12-FRESH-CLONE-CHECKLIST.md` (status header, fail-closed SHA tables, user-checkpoint section, evidence tables).
**Apply to:** the D-13 checklist + SC4 evidence doc(s) in this phase dir (D-16, `commit_docs: true`, root repo). SC2 *numbers* stay in SUMMARY/commit messages only (D-08) — do NOT create a standalone SC2 baseline artifact.

### Fail-closed verification commands with recorded counts
**Source:** `16-VERIFICATION.md` (Behavioral Spot-Checks table; verifier greps with exact counts); ctest lane rule from v1.1 artifacts: `ctest -L Tier1 --no-tests=error` (never `-LE`).
**Apply to:** GATE-03 re-run record (quote-safe grep — 13-RESEARCH Pitfall 1), Tier-1 lane runs, D-15a/D-15b gate outputs (`git diff --exit-code` with expected-empty/expected-0 results recorded verbatim).

### Human checkpoints for one-way doors
**Source:** `12-FRESH-CLONE-CHECKLIST.md` "User actions (the D-03 checkpoint)" numbered-steps shape.
**Apply to:** D-02 (submodule reset-vs-keep, evidence table from 13-RESEARCH attached) and D-04/D-01 (single evidence-complete push creating `origin/dev_coldstorage_additions` — executor never pushes).

## No Analog Found

None — every file/commit this phase produces has a tracked analog. One shape-adaptation note: the D-13 *pre-merge predicted-hunk* checklist (authored before execution, amended as-run) has no literal precedent — v1.1 checklists were authored at execution time. The adaptation is mechanical: open with `Status: **PREDICTED**` + the hunk map from 13-RESEARCH (both-side `GeniusNode.cpp` hunk tables), then amend per-hunk as-run outcomes and flip status to COMPLETE. The per-hunk prediction material is already enumerated in 13-RESEARCH ("Both-side hunk maps") — copy it, don't re-derive.

## Metadata

**Analog search scope:** `.planning/workstreams/rocksdb-backup/milestones/v1.1-phases/12-*/` (checklist, verification, soak-evidence artifacts); `SuperGenius/src/account/`; `SuperGenius/test/` (blockchain/account/crdt test sources + CMakeLists, testutil); `SuperGenius/.planning/phases/16-*/` (GATE-03 record)
**Files scanned:** 12 (6 analogs read in full or targeted, 8 tracked-verified)
**Tracked-source gate (#3645):** all 8 named analog paths verified via `git ls-files` (root repo: 12-FRESH-CLONE-CHECKLIST.md, 12-VERIFICATION.md, 12-soak-evidence/README.md; submodule: GeniusNode.cpp, node_startup_test.cpp, test/src/{account,crdt}/CMakeLists.txt, local_trust_setup.hpp, 16-VERIFICATION.md) — zero gitignored-mirror paths
**Pattern extraction date:** 2026-11-16
