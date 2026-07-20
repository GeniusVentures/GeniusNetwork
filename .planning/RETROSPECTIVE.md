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

## Cross-Milestone Trends

| Milestone | Phases | Plans | Duration | Notes |
|-----------|--------|-------|----------|-------|
| v1.0 Child Wallet Design | 3 | 6 | 2 days | Design docs only |
| v2.0 Registration Implementation | 2 | 6 | 2 days | First implementation slice; +2,235/-47 LOC C++ |
| v2.1 Main Wallet Child Balance Query | 1 | 2 | 1 day | Thin delegation + integration test; segfault-on-teardown flake deferred |
| v2.2 GeniusSDK Child Wallet Interfaces | 1 | 1 | 3 days (20min impl + 2-day build-blocker fix) | Verification override: no formal VERIFICATION.md; segfault-on-teardown flake still deferred |
