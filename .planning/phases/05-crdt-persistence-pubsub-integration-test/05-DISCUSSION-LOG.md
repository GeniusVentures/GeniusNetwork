# Phase 5: CRDT Persistence, PubSub & Integration Test - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-16
**Phase:** 5-CRDT Persistence, PubSub & Integration Test
**Areas discussed:** Sequence derivation & gate d, Discovery read path shape, Main-node pubsub reception, Integration test topology & runtime

---

## Sequence Derivation & Gate (d)

### Q1: How should the filter read the current reg/{child_addr} record for the monotonicity comparison?

| Option | Description | Selected |
|--------|-------------|----------|
| Direct CRDT Get inside FilterRegistration | Fetch value at reg/{child_addr}, deserialize stored RegistrationTx, compare sequences; mirrors FilterTransaction's KeyExistsInDB pattern | ✓ |
| In-memory last-sequence cache | Faster, but drifts from CRDT after restart; needs rebuild-on-boot | |
| You decide | Planner picks | |

**User's choice:** Direct CRDT Get inside FilterRegistration (Recommended)

### Q2: How should the RegisterChild API handle sequence now that Phase 5 derives "last confirmed + 1"?

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-derive with explicit override kept | RegisterChild(main, metadata) reads reg/{child_addr}, uses stored+1 (or 1); caller-supplied variant stays for tests/replay | ✓ |
| Keep caller-supplied + helper only | Separate GetNextRegistrationSequence() helper; two-step dance for callers | |
| Fully automatic, no override | Cleanest API but makes TEST-04's non-monotonic negative test harder | |

**User's choice:** Auto-derive with explicit override kept (Recommended)

---

## Discovery Read Path Shape

| Option | Description | Selected |
|--------|-------------|----------|
| TM scan + GeniusNode wrapper, struct result | GetRegistrationsForMain(main_addr) scans reg/, filters by main_address, returns vector of {child_addr, main_addr, sequence, metadata}; matches RegisterChild two-layer convention | ✓ |
| Return raw RegistrationTransaction objects | More data but couples callers to tx internals | |
| Direct key lookup only | Insufficient — RIMPL-06/TEST-03 require enumerate-by-main | |

**User's choice:** TM scan + GeniusNode wrapper, struct result (Recommended)

---

## Main-Node PubSub Reception

### Q1 (initial): Passive vs active reception?

**User's choice:** Free-text — "It should request on accountmanager which child nodes it has, any node that is aware of a child node via checking crdt should report that. Main node should follow child node addlistentopic."

**Notes:** User's answer described the active D-16/D-17 model plus an AccountMessenger query/report protocol. The AccountMessenger portion is LATER-01 (deferred discovery push/poll). Follow-up asked to draw the scope line.

### Q2 (scope clarification): Which discovery mechanism belongs in Phase 5?

| Option | Description | Selected |
|--------|-------------|----------|
| CID handler + AddListenTopic follow | Node A handles CID notifications on its main_address topic, resolves from CRDT, validates, AddListenTopic(child); no new proto; roadmap SC2 | ✓ |
| Add AccountMessenger 'list children' request/response | Pulls LATER-01 into Phase 5; touches SGAccountComm.proto | |
| Both (push handler + poll fallback) | Fullest D-16 fidelity, largest scope | |

**User's choice:** CID handler + AddListenTopic follow (Recommended). AccountMessenger query/report model captured verbatim as a deferred idea for LATER-01.

---

## Integration Test Topology & Runtime

### Q1: How many nodes?

| Option | Description | Selected |
|--------|-------------|----------|
| 2 nodes: genesis A as main + child B | Minimal assertion coverage; matches scaffold note wording | |
| 3 nodes: genesis + main A + child B | Matches TEST-01 literal wording; proves propagation through a neutral node | ✓ |

**User's choice:** 3 nodes: genesis + main A + child B

### Q2: Suite structure given ~121s boot cost?

| Option | Description | Selected |
|--------|-------------|----------|
| Shared fixture, one boot, distinct child addrs | TEST-02/03/04 as separate TEST_F cases against one network; isolation via distinct child addresses | ✓ |
| Per-test fixtures, full isolation | 3-4x total runtime | |
| Single scripted scenario test | Fastest but one failure aborts all; coarse assertions | |

**User's choice:** Shared fixture, one boot, distinct child addrs (Recommended)

### Q3: How to inject invalid registrations for TEST-04?

| Option | Description | Selected |
|--------|-------------|----------|
| Inject via filter-level elements + assert absence on A | Build crdt::pb::Element objects, feed to FilterRegistration via RegistrationE2ETestAccess, assert absence in GetRegistrationsForMain | ✓ |
| True wire-level injection through CRDT sync | Strongest E2E proof but needs filter bypass on B and adds sync-wait flakiness | |
| You decide | Planner picks | |

**User's choice:** Inject via filter-level elements + assert absence on A (Recommended)

---

## the agent's Discretion

- Discovery result struct shape/naming
- CID-notification handler wiring point (TransactionManager vs GeniusNode level)
- RegisterChild auto-derive mechanism (overload vs defaulted param vs std::optional)
- reg/ scan mechanics (query-by-prefix vs key iteration)
- Test-infra tuning for the ~121s GossipPubSub boot bottleneck (discretionary, not required)

## Deferred Ideas

- AccountMessenger "list my children" request/response protocol (user's explicit design intent) — LATER-01
- Certified-status acting tier (main only acts on certified registrations) — CAUTH-02, authority milestone
- Wire-level byzantine-peer CRDT injection tests
- GossipPubSub timeout tuning as dedicated test-infra task
- GetTransactionFullPath() "tx/" hardcode refactor (carried from Phase 4)
