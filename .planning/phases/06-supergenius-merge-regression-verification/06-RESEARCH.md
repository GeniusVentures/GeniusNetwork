# Phase 6: SuperGenius Merge & Regression Verification - Research

**Researched:** 2026-07-23
**Domain:** Git merge conflict resolution (C++ monorepo submodule), CMake build verification, GTest regression suite
**Confidence:** HIGH

## Summary

This phase is a **git merge + regression verification** task, not a feature-build task. All investigation was done read-only against the SuperGenius submodule's actual git history — no working-tree or index state was left mutated (`git merge-tree` was used for conflict prediction; no trial merge was left open).

The headline finding: **`origin/develop` already performed the `DevConfig_st` -> `GeniusNodeConfig` rename itself**, inside the two shared files `src/account/GeniusNode.hpp`/`.cpp`. Because `dev_childwallet`'s own edits to those two files don't textually overlap develop's rename hunks, git's 3-way merge auto-resolves them cleanly (**no conflict markers**) and simply adopts develop's new name. The real work of "adapting ~17 files to `GeniusNodeConfig`" is **not** conflict resolution at all — it is a **post-merge global rename sweep** over the 15 *other* files (test fixtures + 1 example) that reference `DevConfig_st` by name but were never touched by develop's diff, so git has no way to know they need updating. These files will fail to compile immediately after the merge until the type name is swept.

Of the 9 confirmed shared files, **exactly 2 have genuine textual conflicts** (`git merge-tree` conflict markers): `src/account/CMakeLists.txt` and `src/account/TransactionManager.cpp` — both because `origin/develop` fully removed the deprecated `ProcessingTransaction`/`"process"` tx type (source file, include, dispatch registration, dispatch switch-case) at the same list/include positions where `dev_childwallet` inserted `RegistrationTransaction.cpp`/`RevokeTransaction.cpp` and their includes. The other 7 files (`GeniusNode.hpp`, `GeniusNode.cpp`, `TransactionManager.hpp`, `Blockchain.hpp`, `Blockchain.cpp`, `Consensus.proto`, `test/src/account/CMakeLists.txt`) merge automatically with zero conflict markers — but several carry large, semantically significant refactors (bridge catchup rewrite, escrow burn-fee logic, `EvaluateTransactionReplayProtection` restructuring, genesis validator registry changes) that warrant a manual read-through even though git doesn't flag them.

For MVER-04: `CheckParentChildAuthority`, `FilterRegistration`, and the `transaction_parsers` `"registration"`/`"revoke"` dispatch entries are **not touched by any develop hunk** — confirmed line-range-safe. The one area of genuine adjacency risk is `EvaluateTransactionReplayProtection` (called immediately after `CheckParentChildAuthority` in the same `ValidateTransactionForConsensus` pipeline), which develop substantially rewrites (extracts `GetOutgoingPreviousHash()` helper, adds a new own-address previous-hash consistency check). This function sits directly in the path exercised by registration/revoke/detach E2E tests and deserves the closest manual review post-merge.

**Primary recommendation:** Resolve conflicts in dependency order (proto -> Blockchain -> TransactionManager.hpp -> TransactionManager.cpp -> GeniusNode.hpp/cpp -> CMakeLists.txt pair), do the `DevConfig_st` -> `GeniusNodeConfig` sweep as a separate mechanical step immediately after conflict resolution (before first build attempt), then run the full `registration_transaction_test` (37 cases) + `child_registration_test` (4 cases) suites as the regression gate.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Merge conflict resolution (9 shared files) | Source tree / Build system | — | Pure C++/CMake/proto text-level work inside the SuperGenius submodule |
| `DevConfig_st`->`GeniusNodeConfig` rename sweep | Source tree | Test tier | Mechanical rename across 15 non-conflicting files (13 test + 1 example) once the 2 shared-file renames land |
| Build verification (MVER-01) | Build system (CMake/MSVC) | — | `cmake --build` against the existing `build/Windows/{Debug,Release}` config |
| Regression suite (MVER-03) | Test tier (GTest) | Consensus/TransactionManager tier | `registration_transaction_test` + `child_registration_test` exercise the real `ValidateTransactionForConsensus` pipeline end-to-end |
| Consensus gate compatibility (MVER-04) | Consensus/TransactionManager tier | Blockchain tier | `CheckParentChildAuthority`/`FilterRegistration` live in `TransactionManager.cpp`; `CheckCertifiedParent` lives in `Blockchain.cpp` |

## Project Constraints (from CLAUDE.md)

No `CLAUDE.md` found in this repo — skipped per protocol.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MERGE-01 | Merge `origin/develop` into `dev_childwallet` via merge commit, resolve all conflicts in the 9 shared files including the `DevConfig_st`->`GeniusNodeConfig` rename, push merge commit | See "Refreshed Git State", "Per-File Conflict Analysis", and "The DevConfig_st -> GeniusNodeConfig Rename" sections — exact conflict locations and resolution content identified for both genuinely-conflicting files; rename sweep target list of 15 files enumerated |
| MVER-01 | SuperGenius builds cleanly (all targets) post-merge, no new compiler/linker errors | See "Build Environment" — existing `build/Windows/{Debug,Release}` CMake config confirmed present and configured with `TESTING=ON`; build commands documented |
| MVER-03 | Full child-wallet test suite passes with zero regressions (v2.0-v2.3, Phase 5) | See "Regression Test Inventory" — `registration_transaction_test` (37 cases) and `child_registration_test` (4 cases) enumerated by name; confirmed these are the sole regression-proof vehicles (no dedicated GeniusSDK tests, per project memory) |
| MVER-04 | `CheckParentChildAuthority`, `FilterRegistration`, `CheckCertifiedParent`, `transaction_parsers` registration-tx dispatch all still function after merge | See "MVER-04: Consensus Gate Compatibility Analysis" — exact file:line locations given, confirmed zero direct textual overlap with develop's diff hunks in all 4 targets; one adjacency risk flagged (`EvaluateTransactionReplayProtection`) |
</phase_requirements>

## Refreshed Git State

Ran `git fetch origin develop` inside `SuperGenius/` at research time. **No change from the scoping-time snapshot:**

| Metric | Value | Note |
|--------|-------|------|
| `origin/develop` | `2981cd83abb08aba6fdb594103fddb89f8b5dd64` | Identical to the 2026-07-20 snapshot fetch — no new upstream commits landed |
| `dev_childwallet` HEAD | `5fd137dcd13475114b070e070cda374850f8e699` | Matches outer-repo's recorded submodule pointer |
| merge-base | `7940aea7c660f509aa6bd63e163324b3feb74bd7` | Identical to prior figure |
| Ahead/behind (`git rev-list --left-right --count HEAD...origin/develop`) | `52  162` | `dev_childwallet` has 52 unique commits since merge-base; `origin/develop` has 162 — the REQUIREMENTS.md figure is exact, unchanged |

[VERIFIED: git fetch/rev-list against origin]

**Pre-flight housekeeping note:** `SuperGenius/` currently has one uncommitted, unrelated local change: the nested `docs` submodule pointer (`git diff -- docs` shows a pointer bump from `b68034b0` to `3293bb6a`, pre-existing, not part of this phase's scope). The planner should have the execution plan either commit this separately first or explicitly leave it untouched — **do not** run `git checkout .` / `git reset --hard` inside `SuperGenius/` without stashing this first, or it will be silently discarded. [VERIFIED: git status/diff]

## Per-File Conflict Analysis (9 Shared Files)

Conflict prediction was generated via `git merge-tree 7940aea7c660f509aa6bd63e163324b3feb74bd7 HEAD origin/develop` (modern 3-arg read-only form — no working tree or index touched). [VERIFIED: git merge-tree, git 2.48.1]

| File | Conflict markers? | Scope of develop's change | Risk |
|------|---|---|---|
| `src/blockchain/impl/proto/Consensus.proto` | **No** | Purely additive: adds 3 new `bytes` fields (`slot_0_hash`/`slot_1_hash`/`slot_2_hash`, tags 6/7/8) to the existing `ConsensusVote` message for a new slot-based RPC-hash voting feature (develop's own "Phase 6, D-01" — unrelated to child-wallet's D-01 numbering; a naming coincidence only). Confirmed no field-tag collision with `EmbeddedTransaction`'s `registration = 8` / `revoke = 9` (separate message, separate tag space). | LOW |
| `src/blockchain/Blockchain.hpp` | No | Additive: `SetAdditionalGenesisValidatorAddresses`/`GetAdditionalGenesisValidatorAddresses` (multi-validator genesis registry support), `SetSlotHashPopulator` (wires the new proto fields into vote creation), new `start_deferred_` member. | LOW |
| `src/blockchain/impl/Blockchain.cpp` | No | `StoreGenesisRegistry` call sites change from a single address string to a `vector<string>` of genesis IDs (authorized full node + additional validators); adds deferred-start retry logic and a genesis-creator fast-path for `RequestAccountCreation`. `CheckCertifiedParent` (line 1777) sits well outside every touched hunk (all hunks end by line ~1750). | LOW |
| `src/account/TransactionManager.hpp` | No | Additive: `BURN_BASIS_POINTS`/`BASIS_POINTS_TOTAL` constants (escrow burn-fee feature), `last_nonce_request_time_` member, `k_init_tx_request_cooldown_ms` type change (`uint64_t` -> `std::chrono::milliseconds`). | LOW |
| `src/account/TransactionManager.cpp` | **YES** | See "Real Conflict 1" below. Also contains the large `EvaluateTransactionReplayProtection` rewrite and escrow burn-fee logic (both auto-merge cleanly, no markers, but are non-trivial and adjacent to consensus gates — see MVER-04 section). | **MEDIUM-HIGH** |
| `src/account/GeniusNode.hpp` | No | Source of the `DevConfig_st` -> `GeniusNodeConfig` struct/typedef rename. Also relocates `GetTransactionManager()` from private to public, removes `INITIALIZING_RPC_CATCH_UP` state and `PerformStartupCatchupScan()` (replaced by a new `evmwatcher::BridgeCatchupWatcher` class), adds `SetChainlistFetcher` test-injection hook. | LOW (auto-merges) but review recommended (semantic surface change to `GeniusNode` construction) |
| `src/account/GeniusNode.cpp` | No | Large refactor (~28 hunks across ~3900 lines): moves the entire `PerformStartupCatchupScan` implementation (a 322-line block) out into the new `BridgeCatchupWatcher` service, updates `New()`/constructor signatures to `GeniusNodeConfig`, adds burn-basis-point accessors. Entirely bridge/RPC-catchup-focused — no textual touch on registration/transfer/lifecycle code paths. | LOW (auto-merges) but large diff — flag for a build-then-diff-review pass rather than blind trust |
| `src/account/CMakeLists.txt` | **YES** | See "Real Conflict 2" below. | **MEDIUM** |
| `test/src/account/CMakeLists.txt` | No | Purely additive: registers a new `public_chain_input_validator_slot_test` target (develop's own slot-hash feature test). No interaction with `registration_transaction_test`'s existing target block. | LOW |

### Real Conflict 1 — `src/account/TransactionManager.cpp`

Location: the top-of-file include block (around old-line 22-28).

```
 #include "EscrowTransaction.hpp"
+<<<<<<< .our
 #include "ProcessingTransaction.hpp"
 #include "RegistrationTransaction.hpp"
 #include "RevokeTransaction.hpp"
+=======
+>>>>>>> .their
 #include "UTXOMerkle.hpp"
```

**Why it conflicts:** `dev_childwallet` (ours) added `RegistrationTransaction.hpp`/`RevokeTransaction.hpp` includes alongside the pre-existing `ProcessingTransaction.hpp`. `origin/develop` (theirs) deleted the `ProcessingTransaction.hpp` include entirely (upstream deprecated the `"process"` tx type — confirmed `ProcessingTransaction.{hpp,cpp}` were deleted outright in `origin/develop`, verified via `git show origin/develop:src/account/ProcessingTransaction.cpp` returning "does not exist"). Git can't auto-resolve because both sides touched the same 3-line span.

**Resolution:** drop the `ProcessingTransaction.hpp` include, keep `RegistrationTransaction.hpp`/`RevokeTransaction.hpp`. This is mechanically identical to the resolution needed in `src/account/CMakeLists.txt` below — the same feature (ProcessingTransaction) is being retired everywhere by the same upstream decision.

Two more (non-conflicting, auto-merged) removals in the same file complete the retirement and must be preserved as-is post-merge (git handles these correctly on its own — flagged here only for the plan's build-verification checklist):
- Old-line ~1784: `GeniusTransaction::RegisterDeserializer( "process", &ProcessingTransaction::DeSerializeByteVector );` — removed by develop, no impact on `"registration"`/`"revoke"` deserializer registrations 4 lines below (untouched, confirmed at current lines 1788-1789).
- Old-line ~1815: the `case EmbeddedTransaction::kProcessing:` dispatch arm — removed by develop, no impact on `kRegistration`/`kRevoke` arms (untouched, confirmed at current lines 1846/1853).

Confirmed via `grep -rln "ProcessingTransaction"` across `src/`, `test/`, `example/`: the only remaining references outside `ProcessingTransaction.{hpp,cpp}` themselves are in `TransactionManager.cpp` (the conflict above) — no other file needs touching for this retirement. [VERIFIED: grep + git show against origin/develop]

### Real Conflict 2 — `src/account/CMakeLists.txt`

Location: `GENIUS_NODE_SOURCES` list.

```
     MigrationTransaction.cpp
+<<<<<<< .our
     ProcessingTransaction.cpp
     RegistrationTransaction.cpp
     RevokeTransaction.cpp
+=======
+>>>>>>> .their
     EscrowTransaction.cpp
```

Confirmed via `git diff <merge-base>..origin/develop -- src/account/CMakeLists.txt`: develop's only change to this list is `- ProcessingTransaction.cpp` (clean single-line removal). **Resolution:** keep `RegistrationTransaction.cpp`/`RevokeTransaction.cpp`, drop `ProcessingTransaction.cpp`.

The rest of the file (outside this hunk) merges cleanly and is purely additive from develop: an `evm_watcher_service` library dependency, and a new opt-in `find_contract_creation_blocks` custom target (unrelated utility script, not built by default). No action needed there.

## The `DevConfig_st` -> `GeniusNodeConfig` Rename

`origin/develop` renamed the struct itself (and every reference to it *within the two shared files*) inside `GeniusNode.hpp`/`GeniusNode.cpp` — confirmed via the merge-tree diff:

```cpp
// GeniusNode.hpp — struct tag + extern
-} DevConfig_st;
+} GeniusNodeConfig;
-extern DevConfig_st DEV_CONFIG;
+extern GeniusNodeConfig DEV_CONFIG;
// ...GeniusNode::New(), constructor signature, dev_config_ member type — all renamed
```

Field layout is unchanged (matches REQUIREMENTS.md's "fields unchanged" note) — only the type name changes.

Because these hunks don't overlap `dev_childwallet`'s own edits to the same 2 files, **git auto-merges and the rename lands with zero conflict markers.** After the merge, the type is named `GeniusNodeConfig` everywhere in the codebase — except in the 15 files below, which reference the old name `DevConfig_st` but were never part of develop's diff (git has no reason to touch them), so they will fail to compile until manually swept.

**Full enumeration (current `dev_childwallet` tree, `grep -rln "DevConfig_st" --include=*.hpp --include=*.cpp --include=*.h --include=*.cc src/ test/ example/`, 17 total matches):** [VERIFIED: grep against current tree]

| # | File | Category |
|---|------|----------|
| 1 | `src/account/GeniusNode.cpp` | Shared file — renamed automatically by the merge itself |
| 2 | `src/account/GeniusNode.hpp` | Shared file — renamed automatically by the merge itself |
| 3 | `test/src/account/network_config_precedence_test.cpp` | Rename sweep target |
| 4 | `test/src/account/node_type_derivation_test.cpp` | Rename sweep target |
| 5 | `test/src/blockchain/blockchain_genesis_test.cpp` | Rename sweep target |
| 6 | `test/src/blockchain/consensus_subject_test.cpp` | Rename sweep target |
| 7 | `test/src/bridge_e2e/bridge_e2e_test.cpp` | Rename sweep target |
| 8 | `test/src/multiaccount/multi_account_sync.cpp` | Rename sweep target |
| 9 | `test/src/multiaccount/regtest/child_registration.cpp` | Rename sweep target — **this is the v2.1 balance-query / v2.0 registration regression test** |
| 10 | `test/src/processing_multi/processing_multi_test.cpp` | Rename sweep target |
| 11 | `test/src/processing_nodes/child_tokens_test.cpp` | Rename sweep target |
| 12 | `test/src/processing_nodes/full_node_test.cpp` | Rename sweep target |
| 13 | `test/src/processing_nodes/processing_nodes_test.cpp` | Rename sweep target |
| 14 | `test/src/transaction_sync/migration_sync_test.cpp` | Rename sweep target |
| 15 | `test/src/transaction_sync/transaction_crash_test.cpp` | Rename sweep target |
| 16 | `test/src/transaction_sync/transaction_sync_test.cpp` | Rename sweep target |
| 17 | `example/node_test/NodeExample.cpp` | Rename sweep target |

Note `registration_transaction_test.cpp` (the 37-case CONS-01/CONS-02/lifecycle suite) is **not** in this list — it must already construct its config through a fixture helper that doesn't spell out `DevConfig_st` by name, so it needs no rename-sweep edit. Confirm this at execution time regardless (a quick post-sweep `grep` across the whole tree should return zero hits).

**Recommended sweep mechanism:** a project-wide search-and-replace of the bare identifier `DevConfig_st` -> `GeniusNodeConfig` across the 15 target files (word-boundary match to avoid touching `DEV_CONFIG` the variable, which is unaffected). This is safe as a single mechanical pass since fields are unchanged and it's a pure type rename — no semantic reasoning required, just execute after the merge commit lands and before the first build attempt.

## MVER-04: Consensus Gate Compatibility Analysis

Exact locations in the current `dev_childwallet` tree: [VERIFIED: grep against current tree]

| Symbol | File:Line | Touched by develop's diff? |
|--------|-----------|----------------------------|
| `TransactionManager::CheckParentChildAuthority` | `src/account/TransactionManager.cpp:4492` (called at `:4393` inside `ValidateTransactionForConsensus`) | **No** — outside every hunk range in develop's diff (hunks max out around old-line 4700, and the function body itself at 4492-4530ish has zero overlap with any `@@` hunk header) |
| `TransactionManager::FilterRegistration` | `src/account/TransactionManager.cpp:3206` (registered as CRDT filter callback at `:236`) | **No** — outside every hunk range |
| `Blockchain::CheckCertifiedParent` | `src/blockchain/impl/Blockchain.cpp:1777` (declared `Blockchain.hpp:259`) | **No** — all of develop's Blockchain.cpp hunks end by old-line ~1750 |
| `transaction_parsers` `"registration"`/`"revoke"` dispatch entries | `TransactionManager.cpp:1788-1789` (register), `:1846`,`:1853` (switch-case) | **No direct touch** — develop's only edit in this vicinity is the *removal* of the adjacent `"process"`/`kProcessing` entries (see Real Conflict 1), which sit textually above/around but not on top of the registration/revoke lines |

**Adjacency risk (the one item requiring manual verification beyond "no conflict marker"):** `EvaluateTransactionReplayProtection` (called immediately after `CheckParentChildAuthority` in the same `ValidateTransactionForConsensus` pipeline, per the existing `[Roadmap, v2.3]` decision log entry placing the gate "between `CheckTransactionAuthorization` and `CheckTransactionTimestamp`") is **heavily rewritten** by develop:
- Extracts the previous-hash-lookup lambda into a new `GetOutgoingPreviousHash(nonce)` member helper (used at both send-time and validate-time).
- Adds a **new check**: when `tx.GetSrcAddress() == account_m->GetAddress()`, compare the tx's declared `previous_hash` against `GetOutgoingPreviousHash(tx.GetNonce())` and reject on mismatch.
- Strips per-call `[{} - full: {}]` address/role prefixes from log lines (cosmetic).

This new own-address previous-hash consistency check runs on **every** transaction type, including `registration`/`revoke`/detach transactions from a child or main address. Per the existing decision log (`[Phase 05-child-wallet-lifecycle-states, P06]`), `EvaluateTransactionReplayProtection` already had a subtle requirement that `previous_hash` resolve to a certified tx once `nonce>0` — the P06 gap-closure plan fixed two real bugs here (nonce collision, missing `previous_hash`). Because develop is independently hardening this exact function with a new consistency check, there is a **realistic chance of a semantic (not textual) conflict**: the merged function could reject a legitimate lifecycle transaction if the previous-hash bookkeeping child-wallet relies on doesn't line up with develop's new expected-previous-hash computation. **This is the single highest-value manual review target post-merge** — recommend running the full `LifecycleChangeReplayRejectedByNonceChain`, `DetachChildEndToEnd`, `ReplaceMainEndToEnd`, `RevokeChildEndToEnd`, `ReRegistrationAfterDetachViaReplaceMain`, and `ReRegistrationAfterRevoke` test cases specifically (not just "did the suite pass") to build confidence here.

**Conclusion:** all 4 MVER-04 targets are textually safe from the merge; the recommended verification is targeted test execution around `EvaluateTransactionReplayProtection`, not conflict resolution.

## Regression Test Inventory

Two test binaries constitute the full pre-existing child-wallet regression surface. No dedicated GeniusSDK-layer tests exist (confirmed by project memory: `feedback_geniussdk_no_dedicated_tests.md` — SuperGenius already covers the wrapper logic, and this matches STATE.md's `[Roadmap, v2.4]` decision to fold MVER-01/03/04 into Phase 6 without waiting for GeniusSDK's own merge).

### `registration_transaction_test` (target defined `test/src/account/CMakeLists.txt:90-110`)
File: `test/src/account/registration_transaction_test.cpp` (2456 lines, 37 `TEST_F` cases). Covers CONS-01/CONS-02 (transfer authority, v2.3 Phase 3), registration E2E (v2.0), all Detach/ReplaceMain/Revoke lifecycle transitions (Phase 5). Representative case names: `RoundTripSerialization`, `FilterRegistrationAcceptsValid`, `FilterRegistrationRejectsForkedSupersedesSequence`, `MainFundsChildApprovedByGate`, `MainRecoversFromChildApproved`, `DetachChildEndToEnd`, `ReplaceMainEndToEnd`, `RevokeChildEndToEnd`, `RevokeRejectedForNonMain`, `LifecycleChangeReplayRejectedByNonceChain`, `ReRegistrationAfterRevoke`. [VERIFIED: file read + grep against current tree]

Build/run:
```
cmake --build build/Windows/Debug --target registration_transaction_test --config Debug
./build/Windows/Debug/test_bin/Debug/registration_transaction_test.exe
```

**Known pre-existing issue (not a regression target):** exits with code 139 (segfault) *after* GTest prints its PASSED summary, during process teardown — tracked in STATE.md as a pre-existing libp2p/boost::asio thread-join lifecycle issue, unrelated to this merge. Treat a 139 exit *after* a clean "OK"/"PASSED" GTest summary as a pass; do not treat it as a new regression unless the GTest summary itself shows failures.

### `child_registration_test` (target defined `test/src/multiaccount/regtest/CMakeLists.txt:1`)
File: `test/src/multiaccount/regtest/child_registration.cpp` (461 lines, 4 `TEST_F` cases): `ChildRegistersWithMain`, `MainDiscoversChild`, `InvalidRegistrationRejected`, `MainQueriesChildBalance`. This is the v2.0 registration + **v2.1 balance query** regression vehicle (`MainQueriesChildBalance` directly proves `GetChildBalance`). [VERIFIED: file read]

Build/run:
```
cmake --build build/Windows/Debug --target child_registration_test --config Debug
./build/Windows/Debug/test_bin/Debug/child_registration_test.exe
```

Same pre-existing teardown-segfault caveat applies here (STATE.md confirms this pattern was also observed on this binary's class of test).

### Existing built artifacts
Both `.exe` files already exist at `build/Windows/Debug/test_bin/Debug/` from a prior build — post-merge these must be rebuilt (stale binaries predate the merge and will not reflect conflict-resolution changes).

## Build Environment

| Item | Status |
|------|--------|
| CMake | 3.29.2 present [VERIFIED] |
| Generator | Visual Studio 17 2022 (per existing `build/Windows/Debug/CMakeCache.txt`) [VERIFIED] |
| Existing build configs | `build/Windows/Debug` and `build/Windows/Release` both already configured (`CMakeCache.txt` present in both) [VERIFIED] |
| `TESTING` / `BUILD_TESTING` | Both `ON` in the existing Debug cache [VERIFIED] |
| `THIRDPARTY_DIR` | Sibling directory `../thirdparty` (relative to `SuperGenius/`) exists and is populated [VERIFIED] |
| protoc | Not on PATH directly — vendored/built via the thirdparty/CMake protobuf integration; the existing build already regenerates proto bindings as part of its build graph, so the `Consensus.proto` change requires no manual protoc invocation, just a normal `cmake --build` |

Standard build/verify commands (Windows, per `Readme.md`):
```
cmake --build build/Windows/Debug --target genius_node --config Debug     # core lib, all targets
cmake --build build/Windows/Debug --target registration_transaction_test --config Debug
cmake --build build/Windows/Debug --target child_registration_test --config Debug
```

**Stale-install risk (per `[Phase 04-geniussdk-transfer-wrappers]` decision log entry):** Phase 4 hit a stale locally-installed SuperGenius header that blocked GeniusSDK's build verification, resolved via a `cmake --install` refresh. That specific risk is a **Phase 7 concern** (GeniusSDK build verification depends on SuperGenius's installed headers/static lib), not this phase's — but if this phase's plan includes any step that installs SuperGenius artifacts locally (e.g., to unblock a downstream smoke test), the same class of staleness could recur. Recommend the Phase 6 plan explicitly note "no `cmake --install` performed in this phase; Phase 7 owns the install-refresh step" to avoid ambiguity, unless the plan discovers GeniusSDK build verification needs to happen inline.

## Conflict-Resolution Order (Recommended)

Ordered to resolve foundational/lower-risk files first, so later files' manual review can rely on the earlier ones already being correct:

1. **`src/blockchain/impl/proto/Consensus.proto`** — no conflict, purely additive. Do first; nothing downstream depends on resolving this before the others, but proto regeneration is a build-graph prerequisite for anything referencing `ConsensusVote`.
2. **`src/blockchain/Blockchain.hpp`** then **`src/blockchain/impl/Blockchain.cpp`** — no conflicts, additive genesis/slot methods. `CheckCertifiedParent` untouched; safe.
3. **`src/account/TransactionManager.hpp`** — no conflict, additive constants only. Do before the `.cpp` since the `.cpp` will reference these.
4. **`src/account/TransactionManager.cpp`** — **contains Real Conflict 1** (include block). Resolve by dropping the `ProcessingTransaction.hpp` include, keeping `RegistrationTransaction.hpp`/`RevokeTransaction.hpp`. This is the file requiring the most manual attention — also review (don't just trust auto-merge) the `EvaluateTransactionReplayProtection` rewrite per the MVER-04 adjacency risk above.
5. **`src/account/GeniusNode.hpp`** then **`src/account/GeniusNode.cpp`** — no conflicts, but this is where the `DevConfig_st`->`GeniusNodeConfig` rename actually lands. Do a manual read-through given the scale of the auto-merged refactor (bridge-catchup rewrite), even though git accepted it cleanly.
6. **`src/account/CMakeLists.txt`** — **contains Real Conflict 2** (source file list), mirrors the resolution in step 4 exactly (drop `ProcessingTransaction.cpp`, keep `RegistrationTransaction.cpp`/`RevokeTransaction.cpp`).
7. **`test/src/account/CMakeLists.txt`** — no conflict, additive test target. Lowest risk, do last or anytime.
8. **Global rename sweep** — after all 9 files are resolved and staged (but before the merge commit, or as a follow-up commit within the same merge work — either is acceptable since it's mechanical), sweep the 15 files enumerated above from `DevConfig_st` to `GeniusNodeConfig`.
9. **Build, then run the two regression suites.**

**Highest-risk files, in order:** `TransactionManager.cpp` (real conflict + adjacent consensus-critical rewrite) > `src/account/CMakeLists.txt` (real conflict, but mechanically simple once understood) > `GeniusNode.hpp`/`GeniusNode.cpp` (no conflict, but largest total diff surface).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Conflict prediction before touching the working tree | A trial merge left open for manual inspection | `git merge-tree <merge-base> <ours> <theirs>` (3-arg form) | Fully read-only; never mutates the index or working tree, so it's safe to run repeatedly during planning without an `abort` step |
| Enumerating rename-sweep targets | Manual file-by-file inspection | `grep -rln "DevConfig_st" --include=*.hpp --include=*.cpp --include=*.h --include=*.cc src/ test/ example/` | Exhaustive, fast, and self-verifying (rerun after the sweep to confirm zero hits) |
| Confirming a file's upstream fate (deleted vs. modified) | Guessing from the diff alone | `git show origin/develop:<path>` (non-zero exit = file does not exist on that ref) | Distinguishes "develop kept this file but changed it" from "develop deleted this file entirely" — directly determined the `ProcessingTransaction.cpp` retirement in this research |

**Key insight:** every conflict-resolution decision in this phase was determinable *before* touching the working tree, using only `git fetch`, `git merge-tree`, `git diff <ref>..<ref> -- <path>`, `git show <ref>:<path>`, and `grep` against the current tree. The plan should not need a "figure out what changed" task — only "apply the known resolution" tasks.

## Common Pitfalls

### Pitfall 1: Treating "no conflict markers" as "no review needed"
**What goes wrong:** `GeniusNode.cpp`, `GeniusNode.hpp`, `Blockchain.cpp`, and `TransactionManager.cpp`'s `EvaluateTransactionReplayProtection` section all auto-merge without conflict markers, but carry substantial semantic refactors from develop. A plan that only greps for `<<<<<<<` after merging and calls it done will miss silent behavioral regressions.
**Why it happens:** Git's line-based 3-way merge only flags *textual* overlap, not *semantic* interaction between non-overlapping hunks in the same function/pipeline.
**How to avoid:** Explicitly schedule a manual diff read-through of these 4 files against their pre-merge (`dev_childwallet` HEAD) state as part of verification, not just a conflict-marker grep.
**Warning signs:** Registration/lifecycle E2E tests pass at the unit level but exhibit intermittent nonce/previous-hash rejection under real network timing (would surface as flaky, not deterministic, failures).

### Pitfall 2: Resolving the two real conflicts inconsistently
**What goes wrong:** `TransactionManager.cpp`'s include-block conflict and `CMakeLists.txt`'s source-list conflict are two views of the *same* underlying decision (retire `ProcessingTransaction`). Resolving one by keeping `ProcessingTransaction` (e.g., via a naive `git checkout --ours`) while resolving the other by dropping it (matching develop) creates an inconsistent build: either a CMake source list references a header no longer included, or vice versa — likely a compile/link error, not a merge-tool-visible conflict.
**Why it happens:** The two conflicts are physically distant and easy to resolve in isolation without noticing the connection.
**How to avoid:** Resolve both by fully adopting develop's retirement decision (drop all `ProcessingTransaction` references in both files) — this is a one-directional, one-time removal, not something to preserve "our" side of.
**Warning signs:** Post-merge build fails with "file not found" (`ProcessingTransaction.hpp`) or an unused-file linker complaint.

### Pitfall 3: Running the rename sweep before conflict resolution
**What goes wrong:** If the `DevConfig_st`->`GeniusNodeConfig` sweep is run against the pre-merge tree (or mid-merge with conflict markers still present), the sweep will touch `GeniusNode.hpp`/`GeniusNode.cpp` redundantly or corrupt the conflict markers.
**Why it happens:** The two tasks (merge conflict resolution, rename sweep) look similar (both are "fix DevConfig_st stuff") and could be conflated into one task.
**How to avoid:** Sequence strictly: finish and stage all 9 file resolutions first (including the two shared files' auto-merged rename), confirm zero `<<<<<<<` markers remain repo-wide, *then* run the 15-file sweep as a distinct step.
**Warning signs:** The sweep script reports "0 matches" in `GeniusNode.hpp`/`.cpp` (expected — already renamed by the merge) but the plan's checklist doesn't distinguish that from an actual completed step.

## Code Examples

### Confirming a shared file's real conflict status (read-only, safe to rerun)
```bash
# From SuperGenius/ working directory
git fetch origin develop
git merge-tree 7940aea7c660f509aa6bd63e163324b3feb74bd7 HEAD origin/develop > /tmp/preview.txt
grep -c '<<<<<<<' /tmp/preview.txt   # count of files with real conflicts
```

### Post-sweep verification (should return nothing)
```bash
grep -rln "DevConfig_st" --include="*.hpp" --include="*.cpp" --include="*.h" --include="*.cc" src/ test/ example/
```

### Confirming a file was deleted (not just modified) upstream
```bash
git show origin/develop:src/account/ProcessingTransaction.cpp > /dev/null 2>&1 \
  && echo "EXISTS in develop" || echo "REMOVED in develop"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| `DevConfig_st` struct name | `GeniusNodeConfig` typedef (fields unchanged) | `origin/develop`, within the 162-commit window since merge-base | Cosmetic rename at the type level; mechanical sweep required across 15 non-shared files post-merge |
| `"process"` tx type / `ProcessingTransaction` class | Removed entirely | `origin/develop`, same window | `dev_childwallet` never used this tx type for child-wallet features — pure retirement, no functional loss for this project |
| Manual `PerformStartupCatchupScan()` polling | `evmwatcher::BridgeCatchupWatcher` service class | `origin/develop`, same window | Unrelated to child-wallet scope; large diff footprint in `GeniusNode.{hpp,cpp}` but zero interaction with registration/transfer/lifecycle logic |
| Single-address `StoreGenesisRegistry` | Multi-address (`vector<string>`) genesis validator registry | `origin/develop`, same window | Unrelated to child-wallet's `CheckCertifiedParent`, which reads the registry by address lookup, not by registry-construction signature |
| Inline previous-hash lookup lambda in send-path | Extracted `GetOutgoingPreviousHash()` helper, reused in both send-path and `EvaluateTransactionReplayProtection` | `origin/develop`, same window | **Highest MVER-04 relevance** — see "Adjacency risk" above |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `registration_transaction_test.cpp`'s 37 test cases collectively provide adequate regression coverage for all of MVER-03's listed capabilities (v2.0-v2.3, Phase 5) without needing new tests | Regression Test Inventory | If a capability gap exists (e.g., an untested edge case), MVER-03 could report "zero regressions" while actually missing coverage — mitigated by this being the same suite that closed out Phase 3-5 with 100% pass rate per STATE.md |
| A2 | The `EvaluateTransactionReplayProtection` rewrite's new own-address previous-hash check will not reject any existing lifecycle transaction pattern | MVER-04 Consensus Gate Compatibility Analysis | If wrong, some or all of `DetachChildEndToEnd`/`ReplaceMainEndToEnd`/`RevokeChildEndToEnd`/`ReRegistrationAfter*` tests could start failing post-merge — this is exactly why targeted (not just aggregate) test execution is recommended for this function |
| A3 | No GeniusSDK-side build step is needed within Phase 6 (Phase 7 owns GeniusSDK's own merge/build) | Build Environment | If a plan step inadvertently needs a SuperGenius install refresh to validate something, and skips it citing "Phase 7's job," a stale-header class of failure (per Phase 4's precedent) could surface downstream instead of being caught here |

**If this table is empty:** N/A — see entries above, all are calculated risk assessments from directly-observed git state, not speculative claims.

## Open Questions

1. **Should the `DevConfig_st` -> `GeniusNodeConfig` rename sweep be its own commit, or folded into the merge commit?**
   - What we know: REQUIREMENTS.md's MERGE-01 describes the rename as part of "ordinary conflict resolution" for the merge commit itself.
   - What's unclear: Whether git conventions here favor a single merge commit containing the sweep, vs. merge commit + a small mechanical follow-up commit.
   - Recommendation: Fold the sweep into the merge commit (single merge commit, as REQUIREMENTS.md implies) unless the plan finds a reason to split it — either satisfies MERGE-01's "pushed" requirement equally well.

2. **Does `test/src/multiaccount/regtest/CMakeLists.txt` (the `child_registration_test` target file) need any changes from this merge?**
   - What we know: It is not one of the 9 confirmed shared files, and no hunk in the merge-tree preview touches it.
   - What's unclear: Whether it references anything (e.g., `AsyncIOManager_INCLUDE_DIR`) that shifts due to changes elsewhere in the tree.
   - Recommendation: No special handling needed based on current evidence; standard build verification (MVER-01) will catch any issue.

## Package Legitimacy Audit

Not applicable — this phase performs a git merge and C++ build/test verification only. No new external packages, npm/pip/cargo dependencies, or registry installs are introduced.

## Sources

### Primary (HIGH confidence)
- `git fetch`/`git rev-list`/`git merge-tree`/`git diff`/`git show` against the live SuperGenius submodule and its `origin` remote — all findings in this document are derived directly from the actual repository state, not external documentation.
- Direct file reads: `src/account/TransactionManager.cpp`, `test/src/account/CMakeLists.txt`, `test/src/multiaccount/regtest/CMakeLists.txt`, `test/src/account/registration_transaction_test.cpp`, `test/src/multiaccount/regtest/child_registration.cpp`, `Readme.md`, `build/Windows/Debug/CMakeCache.txt`.
- Project's own `.planning/STATE.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md` (this project's prior decision log, especially the `[Phase 03-parent-child-transfer-authority]`, `[Phase 05-child-wallet-lifecycle-states]`, and `[Phase 04-geniussdk-transfer-wrappers]` entries).

### Secondary (MEDIUM confidence)
None — no external/web sources were needed; this phase is entirely internal-repository investigation.

### Tertiary (LOW confidence)
None.

## Metadata

**Confidence breakdown:**
- Standard stack: N/A — this phase uses the project's existing git/CMake/GTest toolchain exclusively, no new libraries
- Architecture (conflict analysis): HIGH — every claim verified directly against live git state with reproducible, read-only commands
- Pitfalls: HIGH — derived from direct diff inspection, not speculation
- MVER-04 adjacency risk (`EvaluateTransactionReplayProtection`): MEDIUM — the textual non-overlap is verified HIGH confidence, but the semantic-interaction risk assessment is a reasoned judgment call, not something provable without actually running the merge and tests

**Research date:** 2026-07-23
**Valid until:** Short shelf life — recommend re-running `git fetch origin develop` immediately before execution begins, since `origin/develop` could advance again between planning and execution. If it does, the specific line numbers/hunks cited here will need re-verification, though the overall resolution *strategy* (drop `ProcessingTransaction`, sweep `DevConfig_st`, review `EvaluateTransactionReplayProtection`) should remain valid since it reflects an already-landed upstream decision, not a moving target.
