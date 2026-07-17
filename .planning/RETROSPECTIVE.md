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

## Cross-Milestone Trends

| Milestone | Phases | Plans | Duration | Notes |
|-----------|--------|-------|----------|-------|
| v1.0 Child Wallet Design | 3 | 6 | 2 days | Design docs only |
| v2.0 Registration Implementation | 2 | 6 | 2 days | First implementation slice; +2,235/-47 LOC C++ |
| v2.1 Main Wallet Child Balance Query | 1 | 2 | 1 day | Thin delegation + integration test; segfault-on-teardown flake deferred |
