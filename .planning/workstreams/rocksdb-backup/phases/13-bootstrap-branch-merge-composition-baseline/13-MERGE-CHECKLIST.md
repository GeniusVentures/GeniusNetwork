# 13-MERGE-CHECKLIST — Composition Merge of fix/trust-genesis-bootstrap (RECOVER-01 / D-13)

Status: **COMPLETE 2026-11-16** — merge executed and proven (13-02), SC2 zero-regression + SC3 evidence landed (13-03), gates re-run at final HEAD and checklist committed (13-04). Evidence tables below. The D-04 push section's as-run verification line is completed after the user push.

Composes `fix/trust-genesis-bootstrap` (validated bootstrap history recovery) onto
`dev_coldstorage_additions` (the v1.2 cold-storage line) as a **pure composition** —
recovery/bootstrap logic lands via merge, never re-derived. Hand-edits are sanctioned
ONLY inside the single `GeniusNode::ShutdownForDestruction()` conflict hunk (§3);
the D-15 gates (§5) make any other edit a loud, binary failure.

## 1. Topology (verified 2026-11-16 research; re-verify at execution — Pitfall 3)

| Ref | SHA | Note |
|-----|-----|------|
| `dev_coldstorage_additions` (ours, local HEAD) | `4ae8a9a4ec1dc9187f2eb7f498d0114c15f27026` | 7961ec264 + the 13-01 baseline resurrection-test fix (user-approved disposition b); `dev_blockstore` ≡ `origin/dev_blockstore` remain one behind at `7961ec264ab00d14efe99ceb857ec9796de8116b` (expected) |
| `fix/trust-genesis-bootstrap` (theirs) | `d556f86deab7fe78dead80fead1f333625b7a2ce` | ≡ `origin/fix/trust-genesis-bootstrap` |
| Merge base | `8ff74636bf21ad0bb4964574f2badcd42b17498c` | old develop PR #402 (unchanged by the fix commit) |
| Reference merge-tree OID (research, computed from 7961ec264) | `b91b84c94481ea542e567c951b83fe2f2057fee5` | regenerate at execution from `4ae8a9a4e` — the fresh OID DIFFERS by design (ours input carries the test fix); the conflict FILE-SET must stay identical |
| `origin/dev_coldstorage_additions` | does not exist | created by the D-04 push (§8) |

Branch commits (the 4 commits the merge carries, `8ff74636b..d556f86de`):

| SHA | Subject |
|-----|---------|
| `d556f86de` | fix: add validated bootstrap history recovery |
| `6acee9c9a` | fix: initialize UTXOs before certificate replay |
| `5c9b5fab9` | fix: register certificate slot rules before consensus startup |
| `3b337643d` | fix: fetch trust genesis before transaction startup |

Submodule pointers: this merge takes **ZERO** pointer takes — the merged tree keeps our
recorded values (`SGProcessingManager` `dc8a994cb`, `docs` `77f4fcfd5`); any gitlink delta
is a D-15a gate failure (Pitfall 2).

## 2. The predicted conflict, verbatim (single content conflict; merged-blob line 2795)

`git merge-tree --write-tree --name-only 7961ec264 d556f86de` reports exactly:

```
CONFLICT (content): Merge conflict in src/account/GeniusNode.cpp   ← the ONLY conflict
Auto-merging src/account/GeniusNode.hpp
Auto-merging src/crdt/globaldb/globaldb.cpp
Auto-merging src/crdt/globaldb/globaldb.hpp
Auto-merging src/crdt/graphsync_dagsyncer.hpp
Auto-merging src/crdt/impl/graphsync_dagsyncer.cpp
```

Inside `GeniusNode::ShutdownForDestruction()`, immediately after
`node_logger_->info( "GeniusNode shutdown start" )`:

```cpp
<<<<<<< 7961ec264
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
=======
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
>>>>>>> d556f86de
        }
```

## 3. Per-hunk compose rule (D-14 compose-don't-pick — hunk #1, the forecast's ONLY content hunk)

1. Keep OUR drain-barrier comment block **verbatim**.
2. Keep the lock-scope opening `{ std::lock_guard<std::recursive_mutex> lifecycle_lock( lifecycle_mutex_ ); }` (identical on both sides).
3. Insert THEIR two if-blocks **inside the lock scope**:
   - `if ( bootstrap_walk_timer_ )` containing `boost::system::error_code ignored;` and `bootstrap_walk_timer_->cancel( ignored );`
   - `if ( trust_bootstrap_sync_handle_ )` containing `trust_bootstrap_sync_handle_->cancel();` and `trust_bootstrap_sync_handle_.reset();`
4. Keep the closing `}`.
5. Optional: append one comment line noting walk-timer cancellation also happens under the barrier.

Shapes match the sibling `gc_timer_` / `prune_dry_run_timer_` / `health_check_handle_`
cancellation blocks already in the function (Ullman braces, trailing-underscore members).
**Hand-edits anywhere else in the tree are prohibited by D-15a** (§5).

## 4. Both-side hunk maps of `src/account/GeniusNode.cpp` (since merge base `8ff74636b`)

OUR side (`git diff 8ff74636b 7961ec264 -- src/account/GeniusNode.cpp`), 8 hunks — all cold-storage wiring:

| Base line | Region | Content |
|---|---|---|
| @376 | startup/logging | address logging (`Account Address {}`) |
| @581 | `LoadCrdtConfig()` | config load ordering comment |
| @593 | config parsing | `ParseColdStorageConfig` → `cold_storage_config_`, throws on error, `LogSummary()`, retention-without-enabled check |
| @636 | constructor/init | `crdt_backup_config_` + `cold_storage_config_` to GlobalDB ctor (widened arg) |
| @708 | lifecycle lock area | runtime-member release logging |
| @2158 | ctor wiring | cold-stack ctor arg additions (`scheduler_, generator_, nullptr`) |
| @2530 | **`ShutdownForDestruction()`** | **drain-barrier lock scope + comment (THE conflict)** |
| @3156 | `DeleteAccount` area | `return DeleteAccount( previous_address )` context |

THEIR side (`git diff 8ff74636b d556f86de -- src/account/GeniusNode.cpp`), 12 hunks — all bootstrap/walk machinery:

| Base line | Content (symbols) |
|---|---|
| @60 | includes (MigrationManager.hpp + walk-related) |
| @433 (+44) | config: `force_bootstrap_walk` (must-be-boolean), `bootstrap_walk_max_blocks`, `bootstrap_walk_max_retries` via `read_walk_limit`, INFO log |
| @718 | `transition_in_progress_`/`transition_epoch_` bookkeeping |
| @796 | `private_network_id_` area |
| @804 | `blockchain_` guards |
| @866 | `blockchain_` guards (2nd) |
| @1047 | early-return guard |
| @1155 | return guard |
| @1437 | `NodeState::WAITING_FOR_TRUST_GENESIS` / `WAITING_FOR_BURN_GENESIS` handling |
| @1453 (+149) | **`RequestBootstrapWalk()` implementation** (timer cancel, force/retry guards, `PruneEligibility::CanRestoreElement` guard during replay) |
| @1837 | `trust_bootstrap_sync_interval_` scheduling (`trust_bootstrap_sync_handle_.emplace(...)`) |
| @2530 | **`ShutdownForDestruction()` walk-timer/trust-handle cancellation (THE conflict)** |

Base line 2530 is the **only overlap**; every other hunk pair is disjoint → one conflict.

Overlap files (6 paths, all auto-merge except the conflict file):
`src/account/GeniusNode.cpp` (conflict), `src/account/GeniusNode.hpp`, `src/crdt/globaldb/globaldb.cpp`, `src/crdt/globaldb/globaldb.hpp`, `src/crdt/graphsync_dagsyncer.hpp`, `src/crdt/impl/graphsync_dagsyncer.cpp`.

Their-side-only files (24, land as pure branch blobs — incl. the D-15b targets
`src/crdt/impl/crdt_datastore.cpp`, `src/transaction/PruneEligibility.cpp`); our-side-only
files (43, incl. CI workflows, cold-storage stack, 13 `A` cold test files). Their 9 test
files (`node_startup_test`, `prune_eligibility_test`, `tx_pruner_test`, `tx_lookup_tri_state_test`,
`transaction_manager_*_test`, `crdt_datastore_test`, `globaldb_erase_test`) land via merge.

## 5. D-15 gates (exact commands + expected results; run pre-commit AND re-run post-commit)

**D-15a assertion 1 — nothing outside the sanctioned hunk differs from the auto-merge:**

```
git diff --exit-code <fresh-merge-tree-OID> HEAD -- . ':!src/account/GeniusNode.cpp'
```

Expected: **exit 0, no output**. Regenerate the OID first:
`git merge-tree --write-tree 7961ec264 d556f86de` (deterministic; should equal the research
reference `b91b84c94481ea542e567c951b83fe2f2057fee5` on the same git 2.48.1 — a different OID
or any different conflict file-set = EDGE-empty halt, D-14 escalation). NOTE: this merge takes
**no submodule pointers** — ANY gitlink delta (e.g. recording the stale merge-base checkouts)
is a gate failure (Pitfall 2).

**D-15a assertion 2 — the GeniusNode.cpp delta IS exactly the conflict resolution (review artifact):**

```
git diff <fresh-merge-tree-OID> HEAD -- src/account/GeniusNode.cpp
```

Expected: exactly the §3 compose resolution.

**D-15b — theirs-only walk-bearing files byte-identical to the branch blobs:**

```
git diff --exit-code d556f86de HEAD -- src/crdt/impl/crdt_datastore.cpp src/transaction/PruneEligibility.cpp
```

Expected: **exit 0**.

**graphsync_dagsyncer.cpp (both-sides-touched) — symbol preservation + hunk review:**

```
git show HEAD:src/crdt/impl/graphsync_dagsyncer.cpp | Select-String 'GraphsyncDAGSyncer::(HasStoredBlock|GetStoredNode|InheritRoutes)'
```

Expected: **3 matches**. Plus review `git diff d556f86de HEAD -- src/crdt/impl/graphsync_dagsyncer.cpp`
— diff confined to our cold-chain regions.

**Parent check:** `git rev-parse HEAD^1 HEAD^2` → `7961ec264ab00d14efe99ceb857ec9796de8116b` / `d556f86deab7fe78dead80fead1f333625b7a2ce`.

## 6. SC3 evidence-map skeleton (amended as-run by 13-03)

| # | Item | Evidence vehicle (existing tests only — D-09) | As-run result |
|---|------|-----------------------------------------------|---------------|
| 1 | 4-term `HasBlock` observable (`GetNodeFromMerkleDAG`, `GrabCIDBlock`, `HasLocalCold`, `HasDisposed`) | `cold_storage_fallback_test` filtered re-run (incl. `ColdStorageFallbackTest.D08_HasLocalColdBoolContractUnderFault`, `ColdStorageFallbackTest.D02_LocalTierHitPerformsZeroS3Gets`) + `cold_storage_gc_test` / `cold_storage_gc_retrievability_test` (disposed term) + 4-term source check on merged HEAD | **GREEN 2026-11-16**: filtered lane 6/6 100% exit 0 (fallback 21 cases incl. D08+D02, gc, gc_retrievability); source check `term-count=16` (all four symbols present, ≥4) |
| 2 | Cold-chained `GetNodeWithoutRequest` observable | `ColdStorageFallbackTest.D01_S3TierHitEndToEnd`, `ColdStorageFallbackTest.D03_LocalUnavailableFallsThroughToS3`, `ColdStorageFallbackTest.SC4_RehydrateSilence_BytesOnlyNoMarkers` + branch suites `node_startup_test` (walk cases) / `prune_eligibility_test` (four `CanRestoreElement` cases) | **GREEN 2026-11-16**: D01/D03/SC4_RehydrateSilence green in the fallback lane run (post-leg full suite + filtered re-run); walk cases named-green via binary: `NodeStartupTest.BootstrapRecoverySettingsAreLoadedStrictlyFromSgnsConfig` OK (1026ms), `NodeStartupTest.ForcedBootstrapWalkRunsBeforeBlockchainIsReady` OK (8131ms); `node_startup_test` + `prune_eligibility_test` green in both the post full-leg and the filtered lane; no vacuous-config failures, no fixture migration needed |
| 3 | GATE-03 intact (D-11 — re-run as-is) | Quote-safe piped grep (expected **0** matches; PowerShell 5.1 eats embedded quotes — the naive form produced a false 49-match count live in research) + `EraseSurfaceGateTest.SealKeyHasNoProductionHome` via `crdt_erase_test` | **GREEN 2026-11-16**: quote-safe piped grep `grep-matches=0` on merged src/; runtime half via the `crdt_test` target (which compiles `crdt_erase_test.cpp` — there is no standalone `crdt_erase_test` ctest target; plan regex corrected, deviation recorded): `EraseSurfaceGateTest.SealKeyHasNoProductionHome` **[ OK ]** (36ms) + full `crdt_test` green in the post leg (30.05s) |
| 4 | D-12 cold-before-peer fetch ordering (observed, not enforced) | Parse `cold read: rehydrated CID` (`graphsync_dagsyncer.cpp:780`) / `cold read: chain miss for CID` (:802) — rehydrate line precedes peer-fetch activity for the same CID | **ESCALATED-DEFERRED to Phase 15 (user-ruled 2026-11-16)** — structurally unobservable via logs this phase, proven from source: (1) both lines are `logger_->debug` on the `"GraphsyncDAGSyncer"` spdlog logger (merged-HEAD `:810`/`:832`); (2) `base::createLogger` sets patterns only, NEVER a level → spdlog default `info` → runtime-filtered in ALL build types (Release attempt captured 0 lines; the Debug rebuild was stopped as structurally futile); (3) vendored spdlog 1.12.0 has no env-var level hook; (4) the only debug-raisers don't pair with a cold miss (branch `crdt_datastore_test` raises `CrdtDatastore` only, no S3 cold miss; `GeniusNode` SGNS_DEBUGLOGS raises `GraphsyncDAGSyncer`→debug but no node-boot scenario drives a cold S3 miss). Compensating evidence on the merged line: the seam is cold-first BY CONSTRUCTION (source-cited — `FetchNodeFromColdStorage` resolves after hot misses, before/outside any peer request) and `ColdStorageFallbackTest.D01_S3TierHitEndToEnd` + `SC4_RehydrateSilence_BytesOnlyNoMarkers` are green — the cold chain serves with zero peer involvement. Phase 15 owns the deterministic cold-before-peer enforcement and lands the observation harness with it |

## 7. As-run sections (amend below)

### 7.1 D-02 disposition record — CLOSED 2026-11-16

- User pick (verbatim from `$env:TEMP\p13-d02-pick.txt`): **`reset`**
- User qualification (verbatim): "I believe procmanager should be at dc8a994cb7705e6b4e78969fada233a488e6b5ee to work with our moltenvk setup."
- Evidence re-verified live at the checkpoint: working-tree `SGProcessingManager` @ `89d161b08` and `docs` @ `c6d8c8342` are both merge-base values AND ancestors of the recorded pointers (`merge-base --is-ancestor` exit 0 both); `git ls-files test-data/` empty; no merge command had run.
- Executed: `git submodule update SGProcessingManager docs` → checkouts re-synced to `dc8a994cb` / `77f4fcfd5`; pointer equality verified (`ls-tree HEAD` == `rev-parse HEAD` in each nested repo); post-disposition verify: `reset-clean-ok`.
- Deviation note: the plan's drift verify initially flagged ` M SGProcessingManager (untracked content)` — caused by the nested repo's untracked `test/fixtures/` scratch (D-02-ignorable, "scratch left in place unless user says otherwise"), NOT pointer drift. Resolved with a local, uncommitted `git config submodule.SGProcessingManager.ignore untracked` (scoped: tracked modifications still surface). User scratch preserved.
- Untracked `?? test-data/` at SuperGenius root remains — ignorable per D-02's presumption (neither line tracks those paths).

### 7.2 Merge execution record (13-02) — CLOSED 2026-11-16

- Topology re-verified at execution: HEAD ≡ `dev_coldstorage_additions` = `4ae8a9a4e`; `dev_blockstore` ≡ `origin/dev_blockstore` = `7961ec264` (one behind, expected); both bootstrap refs = `d556f86de`; merge-base = `8ff74636b`; tree clean (untracked `?? test-data/` only).
- Fresh merge-tree OID: **`08bffc1e87a268132c28bfe45d37d244a99747a1`** (differs from the research reference `b91b84c94` by design — the ours input carries the 13-01 test fix). Conflict file-set identical to the forecast: single conflict `src/account/GeniusNode.cpp` + auto-merging `GeniusNode.hpp`, `globaldb.cpp`, `globaldb.hpp`, `graphsync_dagsyncer.hpp`, `impl/graphsync_dagsyncer.cpp`.
- Merge SHA: **`2af184fa1db04b5832ce5432a3ae2108c4e2e2ab`** (parents verified `4ae8a9a4e` + `d556f86de`).
- Resolution rule applied: the checklist §3 compose rule verbatim — our drain-barrier comment kept (+ the sanctioned one-line barrier note appended), their `bootstrap_walk_timer_` / `trust_bootstrap_sync_handle_` cancellation inserted inside the shared `lifecycle_mutex_` scope. No other edit.
- D-15 gate outputs (verbatim):
  - D-15a assertion 1 pre-commit: `d15a1-exit=0` (no output) — vs working state
  - D-15a assertion 1 post-commit: `d15a1-exit=0` (no output) — `git diff --exit-code 08bffc1e8 HEAD -- . ':!src/account/GeniusNode.cpp'`
  - D-15a assertion 2 (review artifact): diff confined to the conflict region — markers removed, comment amended, their two if-blocks inside the lock scope (captured in the 13-02 SUMMARY)
  - D-15b pre- and post-commit: `d15b-exit=0` on `src/crdt/impl/crdt_datastore.cpp` + `src/transaction/PruneEligibility.cpp` (byte-identical to `d556f86de` blobs)
  - Symbol check (staged and HEAD): `symbol-count=3` (`InheritRoutes`, `HasStoredBlock`, `GetStoredNode`)
  - Gitlink check: `gitlink-diff-empty=True` — zero submodule pointer takes
  - `graphsync_dagsyncer.cpp` hunk-preservation review: diff vs branch blob = +269/−8 — our cold-chain regions on top of their preserved content
- Post-merge incremental Release rebuild: exit 0, 3m37s, zero errors; branch test targets resolve fail-closed (`ctest -N`: `prune_eligibility_test` #30, `tx_pruner_test` #37, `node_startup_test` #95).

### 7.3 SC2 pre/post table (13-03) — VERDICT 2026-11-16

- **VERDICT: ZERO REGRESSIONS — post-merge failure set is EMPTY (subset-ok).** Post leg @ merge `2af184fa1`: **167/167, 100% passed, ctest exit 0** (wall-clock 36m13s, serial, same Windows Release tree/config as the pre leg; WARP ABSENT both legs). Tier-1 fail-closed lane: **12/12, exit 0**. Pre-leg denominator (composed, per user ruling — see 13-01 SUMMARY): 166 carried results + resurrection green at `4ae8a9a4e` = 0 failures at the baseline tip. Subset verify ran against the post log; the pre-leg `%TEMP%` log file is no longer on disk (the cancelled re-run's `Remove-Item` fired before cancellation) — the pre-leg numbers are carried by the committed 13-01 SUMMARY record per the composed-denominator ruling.
- Shared exclusion names: **NONE** — the `requires_foundry` family passed locally on both legs (9 tests, both runs); no isolated re-runs were needed on the post leg.
- Counts live in the 13-01/13-03 SUMMARYs per D-08 (not duplicated here beyond the verdict).
- Notable durations (not gates — names are the gate): `node_startup_test` 37.4s post vs 10.8s pre = the branch's walk cases now executing on the merged line (landed via merge; Windows #ifdef 60s/90s in-file budgets respected); `multi_account_test` 458s vs 318s = load variance, green both legs.

**Pre-leg record (13-01 Task 3, CLOSED 2026-11-16):** full suite ran on binaries freshly rebuilt at `7961ec264` (5m44s incremental; provenance verified) — **167 total, 166 passed, 1 failed**: `cold_storage_resurrection_test` (`Resurrect_TrimmedMarker_TombstoneDominanceKeepsValueAbsent`), deterministic in isolation. Root cause (user-verified against CI history — last green run `9994718ce` Nov 10; both behavior-changing commits `55fca03f8`+`7961ec264` landed Nov 12 with the suite never run after): the keep-seal retention makes the seal marker the walk terminator, so the case's S3-refetch evidence-wait can never fire — a stale test expectation, not a product regression. **User disposition (b): fix the test on the baseline** → `4ae8a9a4e` rewrites the case to the retention contract (mirrors the marker-present sibling: zero S3 Gets, no re-journal, value stays absent). Re-verification at `4ae8a9a4e`: resurrection suite green (all cases), Tier-1 lane **12/12 exit 0**. **User-approved composed denominator** (full re-run declined as unnecessary — one test file changed, all other binaries byte-identical): 166 carried results + the fixed target green at the tip. The `requires_foundry` family PASSED locally both legs' scope — the shared exclusion set is EMPTY. WARP adapter ABSENT. Pre-leg wall-clock: **33m34s** (serial, 2014.41s ctest total). The pre-leg comparison log (`%TEMP%\p13-sc2-pre-full.log`) is the `7961ec264` run; its single failed name is the already-root-caused-and-fixed case, so the 13-03 subset gate compares post-leg failures against a denominator whose only entry is fixed on the merge line.

### 7.4 Status flip (13-04) — CLOSED 2026-11-16

- Fresh final-HEAD gate re-runs (2026-11-16, verbatim): fresh merge-tree OID regenerated deterministically `08bffc1e87a268132c28bfe45d37d244a99747a1`; D-15a assertion-1 `d15a1-final-exit=0` (no output); D-15b `d15b-final-exit=0`; symbol check `symbol-count=3`; parents `4ae8a9a4e` + `d556f86de`; GATE-03 quote-safe grep `gate03-final-matches=0`. Assertion-2 review artifact unchanged from §7.2 (same OID, same HEAD).
- Status flipped **PREDICTED → COMPLETE** with this record.

## 8. D-04 push checkpoint (filled by 13-04 — user actions)

1. Review the six evidence items presented by 13-04 Task 3 (merge SHA + parents; SC2 verdict; SC3 four rows; committed COMPLETE checklist; root pointer-bump commit; exact push command).
2. **User runs, from the SuperGenius root:** `git push origin dev_coldstorage_additions` — this CREATES the new canonical v1.2 remote line (D-01; verified during research: the ref does not exist on origin). The executor never pushes (D-04 / v1.1 D-03 discipline).
3. `origin/dev_blockstore` goes stale at `7961ec264` **by decision** (D-01).
4. Executor verifies read-only: `git ls-remote origin refs/heads/dev_coldstorage_additions` == merge SHA; records the push (timestamp, remote SHA, pushed-by-user) in this section; commits the amendment.
5. Note: the origin CI run on the new line is CONFIRMATION, not a gate — SC2's gate closed locally per D-05.
6. Optional, separate, user's call: root-repo push (`dev_persisprocresults`, ahead of origin + this phase's docs commits) — not part of this gate.

**AS-RUN (2026-11-16):** user confirmed the push (`pushed`). Read-only verification: `git ls-remote origin refs/heads/dev_coldstorage_additions` → `2af184fa1db04b5832ce5432a3ae2108c4e2e2ab` — **equals the local merge commit** (`remote-equals-merge-sha`). The new canonical v1.2 remote line exists; `origin/dev_blockstore` stale at `7961ec264` by decision (D-01). Pushed-by: user (executor ran no push command — D-04/v1.1 D-03 discipline held). The origin CI run on the new line is CONFIRMATION, not a gate — SC2's gate closed locally per D-05.
