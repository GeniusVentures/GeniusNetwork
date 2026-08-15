# Retrospective: GNUS Child Wallet Design

## Milestone: v1.0 — Child Wallet Design

**Shipped:** 2026-07-15
**Phases:** 3 | **Plans:** 6

### What Was Built

- Child-wallet identity model design (independent secp256k1 keypair, emergent identity, nonce isolation, address-based UTXO ownership) — `docs/child-wallet-identity-model.md`
- Registration protocol design (RegistrationTx proto schema, child-signed-only protocol, dual-counter sequence numbering, backward-compat matrix) — `docs/registration-protocol.md`
- CRDT registry & pubsub design (reg/ namespace, four-gate FilterRegistration, CID-only broadcast, certified-status two-tier model) — `docs/02-crdt-registry-pubsub.md`
- Parent-child consensus authority design (CheckParentChildAuthority gate, 6 CONS rules) — `docs/02-consensus-parent-child-authority.md`
- Discovery & monitoring design (push-primary/poll-fallback via AccountMessenger) — `docs/03-01-discovery-monitoring.md`
- Reward policy & lifecycle design (dual-source policy resolution, hold-time pinning, 4-state lifecycle, supersedes-sequence conflict resolution) — `docs/03-02-reward-policy-lifecycle.md`

### What Worked

- Grounding every design decision in concrete file:line anchor points made verification objective (11/11 truths verified in Phase 2)
- Reusing existing SuperGenius machinery (AccountMessenger, escrow immutability, CRDT filters) instead of inventing new infrastructure kept designs additive
- Decision log (D-01..D-37) carried across phases prevented re-litigating settled questions

### What Was Inefficient

- REQUIREMENTS.md traceability for Phase 2 (CONS/SYNC) was left stale at Pending despite passed verification — caught at milestone close
- Phase 03 code review flagged a critical child-address proto field mapping finding that remained advisory-open at close (carried into v2.0 implementation)

### Patterns Established

- Child-ness is emergent from consensus-visible registration records — no schema flags on accounts
- Registration is child-signed-only; main key never enters child process
- Two-tier trust: CRDT optimistic, consensus certified; act only on certified state

### Key Lessons

- Design-doc milestones benefit from the same verification rigor as code — anchor points + traceability tables made review tractable
- Update requirement checkboxes at phase transition, not milestone close

### Cost Observations

- Sessions: 3 phase cycles over 2 days
- Notable: coarse granularity (3 phases, 2 plans each) fit a docs-only milestone well

## Milestone: v2.0 — Registration Implementation

**Shipped:** 2026-07-17
**Phases:** 2 | **Plans:** 6

### What Was Built

- `RegistrationTx`/`RegistrationMetadata` proto messages (additive) + `registration = 8` oneof arm; `RegistrationTransaction` C++ subclass with factory, serialization round-trip, deserializer registration — Phase 4
- `RegisterChild` two-layer API (TransactionManager + GeniusNode) with sequence auto-derive overload; `reg/{child_addr}` CRDT path diversion in `SendTransactionItem` — Phases 4-5
- Four-gate `FilterRegistration` element filter (deserialization, child signature, well-formed address, sequence monotonicity via direct CRDT Get) — Phases 4-5
- Discovery read path: `GetRegistrationsForMain` CRDT scan + `RegistrationDiscoveryEntry`; `RegElementCallback` CID notification handler with `AddListenTopic` auto-follow — Phase 5
- 3-node integration test (`child_registration_test`): register, discover, reject-invalid — all passing alongside 18 Phase 4 regression tests — Phase 5

### What Worked

- v1.0 design docs paid off exactly as intended — implementation proceeded directly from `docs/registration-protocol.md`/`docs/02-crdt-registry-pubsub.md` anchor points with no re-derivation
- Mirroring existing conventions (TransferTransaction subclass pattern, FilterTransaction do-while(0) tombstone pattern, friend accessor test classes) kept changes idiomatic and reviewable
- Gap-closure plan (05-04) inserted cleanly to fix compile blockers and flaky tests without disturbing completed waves
- Phase 4 advisory code-review warnings were folded into the next phase's first plan (05-01) instead of a separate fix cycle

### What Was Inefficient

- Integration test compile blockers (friend-declaration namespace mismatch, wrong proto include paths) only surfaced at the 05-04 build checkpoint — earlier build verification per wave would have caught them sooner
- E2E tests run ~121s each due to GossipPubSub internal timeouts — test-infra tuning deferred
- Phase 04 human-verification items (regression run, clean rebuild) lingered until milestone close before being confirmed

### Patterns Established

- CRDT path diversion by transaction type-check in `SendTransactionItem` (reg/ never lands in tx/)
- Element-filter sequence gate: CRDT Get + DeSerialize + dynamic_pointer_cast + compare
- Two-layer API convention (TM method + GeniusNode thin wrapper) extended to registration read/write paths
- Test-access pattern: `XxxTestAccess` friend classes inside `namespace sgns` with static accessors (avoids namespace coupling)
- Proto-level DAG signature tampering for deterministic negative tests (never byte-offset)

### Key Lessons

- Ship design docs first, then implement: the anchor-point discipline in v1.0 made v2.0 execution near-mechanical (6 plans, ~2,235 LOC, 2 days)
- Add a build-and-run checkpoint per wave for C++ test targets — static inspection misses namespace/include/link issues
- Close human-verification items at phase end, not milestone end

### Cost Observations

- Sessions: 2 phase cycles + 1 debug session + gap-closure plan over 2 days
- Notable: plan durations 5-13 min each; longest cost was the 26-min integration test execution in 05-04

## Milestone: v2.1 — Main Wallet Child Balance Query

**Shipped:** 2026-07-17
**Phases:** 1 | **Plans:** 2

### What Was Built

- `GeniusNode::GetChildBalance` (token-filtered + all-tokens overloads) as thin aliases over the existing `UTXOManager::GetBalance` family, with the child-first/token-first argument-order swap at the delegation boundary — Phase 1, Plan 01
- `TEST_F(ChildRegistrationIntegrationTest, MainQueriesChildBalance)` proving end-to-end that a child node's mint propagates via CRDT sync to a balance the main node can read via `GetChildBalance` — Phase 1, Plan 02

### What Worked

- v2.0's already-active D-49 CRDT/pubsub sync meant balance query needed zero new sync infrastructure — pure delegation to the existing `UTXOManager::GetBalance` pattern, done in 5 minutes
- Poll-until-convergence test pattern (previously used only for registration discovery) extended cleanly to UTXO/balance sync

### What Was Inefficient

- The plan's mint `chainid` argument (`"test_05_balance"`) was described as a free-text description but actually selects an `IInputValidator` — cost a full build/run/diagnose cycle to discover it must be the registered `"test"` chainid instead

### Patterns Established

- Balance-family additions stay `GeniusNode`-only, bypassing `TransactionManager`, matching the existing `GetBalance` precedent
- Child-mints/main-queries integration test pattern: mint via `child_node_`, poll child's own balance, then poll main's `GetChildBalance` until CRDT convergence, before final assertion

### Key Lessons

- When a plan describes a test parameter as a "description string," verify against the actual validator/dispatch code before assuming it's free text — chainid-style arguments are frequently dispatch keys in disguise
- `child_registration_test.exe` has a pre-existing segfault-on-teardown (after all assertions pass) unrelated to this milestone's changes — reproduces with only pre-v2.1 tests; deferred to a future test-infra/node-shutdown-hygiene phase

### Cost Observations

- Sessions: 1 phase cycle, single day
- Notable: Plan 01 took 5 min (pure delegation), Plan 02 took 25 min (integration test + one bug-fix cycle)

## Milestone: v2.2 — GeniusSDK Child Wallet Interfaces

**Shipped:** 2026-07-20
**Phases:** 1 | **Plans:** 1

### What Was Built

- `GeniusSDKRegisterChild`, `GeniusSDKGetRegistrationsForMain`, `GeniusSDKGetChildBalance`, and `GeniusSDKGetChildBalanceAll` added to the public `GeniusSDK.h`/`.cpp` C API, wrapping the existing `GeniusNode::RegisterChild`/`GetRegistrationsForMain`/`GetChildBalance` logic — Phase 2, Plan 01
- `GeniusRegistrationMetadata`/`GeniusRegistrationDiscoveryEntry` C structs and a new `GENIUS_NODE_ERROR_REGISTRATION` status code
- Fixed a pre-existing SuperGenius/evmrelay CMake packaging gap (missing `find_dependency(evmrelay)` + Boost::coroutine MSVC error) that had blocked full `GeniusSDK` static-lib builds — full build confirmed green (2026-07-20, 2 days after the wrapper code landed)

### What Worked

- Mirroring the existing `do/while(0)`-guarded status-code wrapper pattern (`GeniusSDKMint`/`GeniusSDKTransfer`/`GeniusSDKPayDev`) kept the 4 new functions idiomatic and reviewable with zero new conventions invented
- `strnlen`-bounded string construction from fixed-size caller buffers, and the malloc'd/`GeniusSDKFree` ownership-handoff pattern for the variable-length discovery array, both extended existing SDK conventions cleanly to a new C-struct/array shape

### What Was Inefficient

- The SDK wrapper code could not be build-verified at the time it was written — a pre-existing, unrelated evmrelay/Boost::coroutine CMake packaging bug blocked the full `GeniusSDK` static-lib build. Verification fell back to manual line-by-line signature cross-check against `GeniusNode.hpp`/`TransactionManager.hpp`/`SGTransaction.proto`, and a formal `VERIFICATION.md` was never generated even after the build blocker was fixed 2 days later — milestone closed via explicit verification override rather than backfilling it with `/gsd-execute-phase 2`

### Patterns Established

- Two-layer API convention (`GeniusNode` method → thin `GeniusSDK` C wrapper) now extended from node-level calls to the public C FFI boundary
- Malloc'd output array + `GeniusSDKFree` ownership-handoff pattern for variable-length discovery results, reusable for any future SDK call returning an unbounded collection

### Key Lessons

- When a build-environment blocker prevents compiled verification, manual signature cross-check is an acceptable stopgap — but it needs an explicit follow-up task to backfill real verification once the blocker clears, or the gap silently survives to milestone close (as it did here)
- Pre-existing CMake/`find_package` transitive-include gaps (like the evmrelay one) can block downstream SDK consumers for an extended period without surfacing until someone tries a fresh build — worth a proactive `find_package(SuperGenius)` smoke build when adding new SDK-facing wrappers, not just header inspection

### Cost Observations

- Sessions: 1 session for the wrapper implementation (20 min), 1 separate later session (2026-07-20) to diagnose and fix the CMake/coroutine build blocker
- Notable: implementation was fast (thin wrapper over already-shipped v2.0/v2.1 logic); the bulk of elapsed calendar time (2 days) was the build-verification blocker, not the SDK code itself

## Milestone: v2.3 — Child Wallet Transfers

**Shipped:** 2026-07-21
**Phases:** 2 | **Plans:** 5

### What Was Built

- `Blockchain::CheckCertifiedParent` (D-63 CRDT certified-status lookup, zero `genius_node` dependency) and `GeniusTransaction::CheckSignatureAgainst(address)` (parameterized signature verification `CheckSignature` now delegates to) — Phase 3, Plan 01
- `CheckParentChildAuthority` consensus gate enforcing CONS-01 (main→child fund) and CONS-02 (main-recover-from-child, D-21 destination-restricted), slotted between `CheckTransactionAuthorization` and `CheckTransactionTimestamp` — Phase 3, Plan 02
- `TransactionManager::RecoverFromChild`/`GeniusNode::RecoverFromChild` — new transfer-construction method spending only the child's own UTXOs, signed with main's own key — Phase 3, Plan 03
- 24/24 passing E2E regression tests proving CONS-01/CONS-02 work and REGR-01/02/03 (every existing child-signed path) are unaffected — Phase 3, Plan 04
- 4 new GeniusSDK C-API wrappers (`GeniusSDKFundChild`/`GNUS`, `GeniusSDKRecoverFromChild`/`GNUS`) exposing Phase 3's transfer calls, reusing existing `GeniusNodeReturnValue_t` codes — Phase 4

### What Worked

- Reusing the existing `"transfer"` tx type for both fund and recover avoided any new proto message or tx type
- Found and fixed a pre-existing gap while writing regression tests: `transaction_parsers` had no dispatch entry for `"registration"` tx type — registration transactions could never have been certified without this fix, and the certified-parent mechanism this milestone depends on would have silently failed

### What Was Inefficient

- Plan 04 (regression test authoring) took ~3.5hr, the longest single plan in the milestone — E2E test authoring against the real consensus pipeline is inherently slower than unit-level verification

### Patterns Established

- D-60: certified-main signature accepted on child-sourced tx via CRDT registration lookup, not cryptographic delegation — `CheckParentChildAuthority` re-derives `tx.CheckSignature()` as a cheap branch selector to distinguish child-self-signed spends from certified-main-delegated recovery
- `FillDAGStructForAddress(source_address)` helper added alongside `FillDAGStruct()` to keep main's own transfer/escrow paths untouched while supporting recovery-from-child construction

### Key Lessons

- When adding a new consensus gate, grep the dispatch tables (`transaction_parsers` and similar) for the transaction types the new logic depends on — a missing entry can silently block the entire feature at the tx-type level, upstream of the new gate itself

### Cost Observations

- Sessions: 2 phase cycles over 1 day (Phase 3: 4 plans, ~25min-3.5hr each; Phase 4: 1 plan, 20min)
- Notable: Phase 3 Plan 04's regression-test authoring dominated wall-clock time; the actual gate/transfer implementation (Plans 01-03) was comparatively fast

## Milestone: v2.4 — Merge origin/develop into dev_childwallet

**Shipped:** 2026-07-24
**Phases:** 2 (Phase 6 via formal GSD workflow; Phase 7 completed directly by the user) | **Plans:** 5

### What Was Built

- Two-parent merge commit (SuperGenius `cb4e46da`) bringing `dev_childwallet` current with `origin/develop` (162 commits), resolving the 2 real conflicts (retiring `ProcessingTransaction` consistently) and auto-merging the other 7 of 9 confirmed shared files cleanly
- `DevConfig_st`→`GeniusNodeConfig` rename swept across all ~17 affected files — 14 of 15 plan-enumerated files had already auto-merged correctly; only `child_registration.cpp` needed a manual edit
- All SuperGenius targets (`genius_node`, `registration_transaction_test`, `child_registration_test`) confirmed building cleanly post-merge, zero new compiler/linker errors
- Full pre-existing child-wallet regression suite (registration, balance query, transfer authority, transfer wrappers, lifecycle Detach/Revoke/ReplaceMain) confirmed zero regressions; consensus gates confirmed compatible with `origin/develop`'s merged changes via static verification (byte-identical function-body diff)
- GeniusSDK `dev_childwallet` merged with the 1 remaining `origin/develop` commit (merge commit `6969fac`), pushed, and confirmed building against the updated SuperGenius static lib — completed directly by the user, no formal `07-*` phase artifacts

### What Worked

- Doing careful pre-merge research (recorded in 06-RESEARCH.md) meant the actual `git merge --no-ff --no-commit` produced exactly the predicted conflict set — no surprises during Plan 01
- Root-causing test crashes via live debugger stack trace (Phase 5's `CrdtSet::mutex_` reentrancy fix) rather than accepting the plan's original hypothesis, then confirming that same fix held under the newly-merged `origin/develop` code paths during Phase 6 regression testing
- Distinguishing an unrelated `thirdparty` submodule drift (accidentally fast-forwarded during this session's build troubleshooting) from an actual merge regression — root-caused via a non-rebuilt baseline binary comparison rather than assuming the merge was at fault

### What Was Inefficient

- Full E2E regression execution (MVER-03) was only partially completed (5/37 + 0/4 test cases) because of the `thirdparty` drift crash — static/structural verification had to substitute for live test execution on the affected fixtures
- Phase 7 was completed entirely outside the GSD discuss/plan/execute workflow, leaving no `PLAN.md`/`SUMMARY.md`/build-log artifact — milestone close required independently reconstructing MERGE-02/MVER-02 evidence from git history and user attestation, and required a `--force` override on `gsd-tools.cjs query milestone.complete` since the roadmap showed Phase 7 with 0 plans

### Patterns Established

- Merge commit (not rebase) is the correct choice whenever a `dev_*` branch is already shared/pushed — rebase would rewrite shared history
- When troubleshooting a Windows build blocker, check sibling submodules (`thirdparty` in this case) for accidental fast-forwards before assuming the change under test caused a new failure

### Key Lessons

- A phase completed outside the formal workflow is still closeable, but costs real verification effort at milestone-close time to reconstruct what would have been captured automatically by `/gsd-execute-phase` — worth running the formal workflow even for "simple" merge-only phases
- When a milestone-close tool refuses due to an unstarted phase, `--force` is appropriate only after independently verifying the actual work through an out-of-band source (here: git history) — never take the user's word alone as sufficient for requirements marked complete

### Cost Observations

- Sessions: entirely same-day (2026-07-23 for Phase 6, 2026-07-23/24 for Phase 7's manual completion)
- Notable: Phase 6's 5 plans ran efficiently (10min-70min each) except the deferred-items root-cause investigation in Plan 04; Phase 7 had zero GSD-tracked cost since it bypassed the workflow entirely

## Milestone: sgproc-render v2.0 — Execution Contracts & Quality Gates

**Shipped:** 2026-08-07 (closed via override, known gaps)
**Phases:** 4 (06-09) | **Plans:** 27 | **Tasks:** 39

### What Was Built

Capability-validation contract (CAP-*, pre-execution `CanExecute` gate), cancellable/budget-aware execution contexts (EXEC-*, cooperative cancellation, deadlines, resource budgets, structured progress), typed artifacts + deterministic execution manifests (ARTF-*), and a full CTest conformance suite (TEST-01..10) covering every registered executor with regression locks for all four known v1.0 bugs. Phase 09 alone absorbed 15 plans across three gap-closure rounds (goal-backward verification found further gaps twice, UAT found a third round).

### What Worked

- Gap-closure rounds caught real, previously-invisible bugs (e.g. a genuine crash in artifact-metadata building, a non-deterministic `combinedHash` from uninitialized struct padding, a CTest working-directory bug masking 4 sub-tests as failing) that a single verification pass would have missed.
- Reusing the existing `sha256`/artifact-serialization conventions kept Phase 08/09 additive rather than requiring rework of Phases 06-07.

### What Was Inefficient

- Phase 04 (v1.0 carryover) was never formally closed — 1 pending UAT scenario and a `human_needed` verification gap sat unresolved through the entire v2.0 milestone and only surfaced again at v2.0's own close via the pre-close artifact audit.
- Phases 06-08 were never run through a formal verification pass — `init.manager` reports all three as `phase_complete: false` at milestone close, with Phase 07 specifically noted as "tests pending HW verification." Only Phase 09 (the last phase) got real verification, which retroactively also validated most of 06-08 by exercising them, but the formal artifacts for 06-08 individually don't exist.

### Patterns Established

- Milestone close in a multi-workstream project must pass a **workstream-qualified** version/name to any archival step that writes to shared paths — `gsd-tools.cjs query milestone.complete "v2.0" --ws sgproc-render` archives to the shared `.planning/milestones/v2.0-*` paths with no workstream namespacing in the filename itself, and this collided with the child-wallet workstream's own pre-existing `v2.0-ROADMAP.md`/`v2.0-REQUIREMENTS.md` (both workstreams reached "v2.0" independently). Caught before commit via `git status`/`git diff` showing unexpected modifications to already-tracked files; recovered via `git checkout --` on the two collided files, then re-archived sgproc-render's content under `sgproc-render-v2.0-*` filenames instead. **Lesson: before running `milestone.complete` in a multi-workstream repo, check `.planning/milestones/` for an existing file at the exact version string being archived, regardless of which workstream "owns" that version number.**

### Key Lessons

- `init.manager`'s `phase_complete`/`verification_status` fields are the authoritative readiness signal for milestone close — PROJECT.md's own prose claims about phase completeness should be cross-checked against this before trusting them.
- The pre-close artifact audit (`audit-open`) surfaces gaps that predate the milestone being closed (here, a v1.0 Phase 04 gap) — always run it fresh rather than assuming only the current milestone's phases could have open items.

### Cost Observations

- Model mix: not tracked separately for this milestone
- Sessions: spans 2026-08-04 through 2026-08-07
- Notable: Phase 09's three gap-closure rounds (15 plans total) dwarfed the other three phases' combined plan count (12) — conformance testing surfaced more real work than the phases it was testing

## Milestone: sgproc-render v2.2 — Cross-Hardware Validation Tolerance

**Shipped:** 2026-08-14 (closed with an acknowledged carryover — Phase 04 gap, unrelated to this milestone's own phases)
**Phases:** 2 (14-15) | **Plans:** 7 | **Tasks:** 14

### What Was Built

Schema-configurable per-data-type normalization precision (QUANT-CFG-01/02/03) replacing v2.1's single hardcoded quantization scale, with silent fallback to v2.1's exact constants when unconfigured, plus an empirically-derived `quantScale=128.0` for the `tex3d`/`spleen_ct_seg` real workload. And a fixed, tolerant `ProcessingValidationCore::ValidateResults` (XNODE-01b/XNODE-02): the concatenation bug that let genuine cross-node mismatches silently pass is fixed, and a bounded numeric-tolerance fallback (new `sgprocmanagerdiff` library) absorbs boundary-tie-break-style false mismatches without masking real corruption (SECV-02).

### What Worked

- The Phase 14 → Phase 15 dependency ordering (configurable precision before the tolerance-fallback mechanism that consumes it) was encoded directly as a roadmap phase dependency rather than an internal wave split, and held cleanly — no rework needed when Phase 15 began.
- Required (non-defaulted) function parameters in `QuantizeFloatBuffer`/`QuantizeByteBuffer` (Plan 14-01) turned "did we miss a call site" into a compiler-enforced question — Plan 14-02's 21-call-site wiring across 14 files needed zero follow-up fixes because a missed site simply wouldn't compile.
- SECV-02's full-pipeline counter-test caught two genuine test-design bugs (an insufficiently-divergent reused fixture, an output-path collision between two test jobs) before they could mask the very defect the test existed to catch — worth the extra fixture-creation effort.

### What Was Inefficient

- Phase 14 Plan 3's binary search for `tex3d`/`spleen_ct_seg`'s SECV-01 boundary found no failure boundary at all in the valid domain (256 down to 1 all passed) — the search itself cost real wall-clock time (~2.5 min/iteration against a real ~19MB model) for a negative result, though the divergence-absorption fallback constraint was already anticipated by the plan.
- The pre-close artifact audit re-surfaced the same Phase 04 (v1.0) carryover gap for the third milestone running (v2.0, v2.1 implicitly, now v2.2) — it has never been resolved, only re-acknowledged, and will keep resurfacing at every future close until someone actually runs a phase to close it.

### Patterns Established

- When a security counter-test's binary search finds no failure boundary within the valid parameter domain, fall back to a divergence-absorption constraint (grid step must exceed the real measured cross-hardware delta) to choose the final value, rather than guessing or leaving the parameter unset — document both the absent boundary and the absorption calculation in the fixture's citation trail for future auditability.
- Milestone-archive filename collisions in this multi-workstream project are now checked for *before* writing archive files (via `.planning/milestones/` listing + `git tag -l`), not discovered after the fact via `git status` — this is the first sgproc-render close where the collision was caught proactively rather than after an accidental overwrite.

### Key Lessons

- A `phase_complete`-verified, requirements-fully-checked milestone can still surface pre-close audit gaps that have nothing to do with the milestone itself — always distinguish "gaps this milestone introduced" from "carryover gaps this milestone's audit happened to re-surface" before deciding how to close.
- Required-parameter API changes (no defaulted overload) are a cheap, durable way to make "every call site was updated" a compile-time guarantee instead of a manual audit — worth reaching for whenever a schema/config threading change must hit every existing call site.

### Cost Observations

- Model mix: not tracked separately for this milestone
- Sessions: single session, 2026-08-13 evening through 2026-08-14
- Notable: Phase 14 Plan 3's empirical binary search (5 rebuild+run iterations against a real ~19MB model) was the single most wall-clock-expensive step in either phase, despite yielding a negative result

## Cross-Milestone Trends

| Milestone | Phases | Plans | Duration | Notes |
|-----------|--------|-------|----------|-------|
| v1.0 Child Wallet Design | 3 | 6 | 2 days | Design docs only |
| v2.0 Registration Implementation | 2 | 6 | 2 days | First implementation slice; +2,235/-47 LOC C++ |
| v2.1 Main Wallet Child Balance Query | 1 | 2 | 1 day | Thin delegation + integration test; segfault-on-teardown flake deferred |
| v2.2 GeniusSDK Child Wallet Interfaces | 1 | 1 | 3 days (20min impl + 2-day build-blocker fix) | Verification override: no formal VERIFICATION.md; segfault-on-teardown flake still deferred |
| v2.3 Child Wallet Transfers | 2 | 5 | 1 day | CheckParentChildAuthority consensus gate; found/fixed missing registration-tx dispatch entry |
| v2.4 Merge origin/develop into dev_childwallet | 2 | 5 | 2 days | Phase 7 completed outside GSD workflow; verification override on milestone close (--force) |
| sgproc-render v2.0 Execution Contracts & Quality Gates | 4 | 27 | 4 days (2026-08-04 to 08-07) | Verification override: Phases 06-08 not phase_complete/verified, Phase 04 carryover gap; milestone-archive filename collision with child-wallet's own v2.0 caught and fixed before commit |
| sgproc-render v2.1 Cross-Hardware Hash Tolerance | 4 | 15 | ~4 days (2026-08-10 to 08-13) | Accepted override: VALD-01 MNN fixture retains 1/15-chunk boundary tie-break (chunk 10, S=2^15 grid step); render fixture fully matched cross-hardware |
| sgproc-render v2.2 Cross-Hardware Validation Tolerance | 2 | 7 | 2 days (2026-08-13 to 08-14) | QUANT-CFG-* configurable precision + XNODE-01b/02 ValidateResults fix, both requirements 6/6 shipped clean; only gap was the recurring Phase 04 (v1.0) carryover, unrelated to this milestone; filename collision with child-wallet's own v2.2 checked and avoided proactively |
