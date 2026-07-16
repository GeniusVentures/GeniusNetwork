# Phase 5: CRDT Persistence, PubSub & Integration Test - Context

**Gathered:** 2026-07-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Accepted registrations persist in the consensus-visible `reg/` CRDT namespace behind the *complete* `FilterRegistration` (Phase 4 shipped gates a–c: deserialization, child signature, malformed `main_address`; Phase 5 adds gate d: sequence monotonicity plus `sequence > 0`), the child's registration broadcast reaches the main node's pubsub topic, the main node discovers and follows children registered to it, and a multi-node GTest integration test (genesis + main A + child B) proves acceptance, propagation, discovery, and negative rejection — RIMPL-04..07, TEST-01..04.

Consensus authority gate (`CheckParentChildAuthority`, CONS-01..06), certified-status two-tier acting model (CAUTH-02), AccountMessenger discovery push/poll proto extension (LATER-01), reward policy, and lifecycle change-flows are **out of scope** — later milestones.
</domain>

<decisions>
## Implementation Decisions

### Sequence derivation & gate (d) — completing FilterRegistration (RIMPL-04, RIMPL-07)
- **D-46:** Gate (d) reads the current record via a **direct CRDT Get** inside `FilterRegistration` — fetch the value at `GetBlockChainBase() + "reg/" + child_addr`, deserialize the stored `RegistrationTx`, and reject unless the incoming `sequence` is strictly higher (and `sequence > 0`). No in-memory last-sequence cache; the filter is always consistent with what the CRDT merge would overwrite. Mirrors the existing `KeyExistsInDB` pattern in `FilterTransaction` (TransactionManager.cpp:2729) but with a value read. Gate (d) is added to the **same** `FilterRegistration` method per D-44.
- **D-47:** `RegisterChild` **auto-derives** the sequence: a call without an explicit sequence reads `reg/{child_addr}` and uses stored sequence + 1 (or 1 if no record exists). The **caller-supplied variant is kept** (overload or defaulted param) for tests and replay scenarios — TEST-04's non-monotonic negative test depends on being able to force a stale sequence. Applies at both layers (`TransactionManager::RegisterChild` and the `GeniusNode` wrapper).

### Discovery read path (RIMPL-06)
- **D-48:** Two-layer read path following the `RegisterChild`/`TransferFunds` convention: `TransactionManager::GetRegistrationsForMain(main_addr)` performs the `reg/` namespace scan and filters records whose `main_address` matches, with a thin `GeniusNode` wrapper exposing it. Returns a **vector of a small struct** `{child_addr, main_addr, sequence, metadata}` — not raw `RegistrationTransaction` objects — keeping the discovery surface decoupled from tx internals. The integration test asserts via this helper (roadmap SC3's `GetRegistrationsForMain` expectation).

### Main-node pubsub reception (RIMPL-05)
- **D-49:** **CID-notification handler + AddListenTopic follow** (active model within Phase 5 scope): node A registers a handler on its own `main_address` topic; when child B's `SendTransactionItem` broadcast lands there (the topic set already includes `main_address` via `RegistrationTransaction::GetTopics()`, shipped in Phase 4), A resolves the CID from its local CRDT (D-18: payload is CID-only, never full protobuf), validates the record came through `FilterRegistration`, and calls `AddListenTopic(child_addr)` to follow the child's channel (D-16/D-17). Uses existing `PubSubBroadcasterExt` — **no new proto messages**.
- **D-50:** The user's fuller vision — main queries peers via AccountMessenger ("which children do I have?"), any CRDT-aware node reports — is **LATER-01 (deferred)**. Phase 5 delivers only the pubsub-push trigger + CRDT-scan discovery; the AccountMessenger request/response extension stays out (see Deferred Ideas).

### Integration test topology & structure (TEST-01..04)
- **D-51:** **Three nodes**: genesis-authorized node + main node A + child node B, matching TEST-01's literal wording ("genesis-authorized node plus two peer nodes"). Registration flows B → A while the genesis node proves propagation through a peer that is neither child nor main. Follows the `multi_account_sync.cpp` `CreateNode` pattern; test file at `SuperGenius/test/src/multiaccount/regtest/child_registration.cpp`.
- **D-52:** **Shared fixture, one network boot**: the 3-node network boots once (GTest shared fixture / `SetUpTestSuite`); TEST-02/03/04 run as separate `TEST_F` cases against it using **distinct child addresses** so cases don't collide in shared CRDT state. Amortizes the ~121s GossipPubSub boot cost. Planner must order/isolate cases so shared state doesn't create inter-test dependencies.
- **D-53:** **Negative injection at filter level**: TEST-04's invalid registrations (tampered signature, malformed `main_address`, replayed/non-monotonic sequence) are built as `crdt::pb::Element` objects and fed to `FilterRegistration` via the Phase 4 friend-accessor pattern (`RegistrationE2ETestAccess`), then the test asserts the registration **never appears in node A's `GetRegistrationsForMain` view**. No wire-level malicious-peer injection machinery in this phase.

### the agent's Discretion
- Exact shape of the discovery result struct (name, header placement) — follow existing account-layer struct conventions.
- Where the CID-notification handler wires in (TransactionManager topic subscription vs GeniusNode-level) — pick the point that matches how the node already processes its own address-topic messages.
- Whether `RegisterChild` auto-derive is an overload, a defaulted parameter, or a `std::optional<uint64_t>` — planner picks the idiomatic form.
- `reg/` scan mechanics (CRDT query-by-prefix API vs key iteration) — use whatever GlobalDB/CRDT datastore exposes; match existing scan patterns.
- Test-infra tuning for the ~121s GossipPubSub boot bottleneck (address-refresh/connection-manager timeouts) — improve if cheap, but not a phase requirement.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Authoritative design docs
- `docs/02-crdt-registry-pubsub.md` — `reg/` namespace/key layout, full `FilterRegistration` gate list (deserialization, signature, sequence monotonicity, well-formed), pubsub broadcast/subscription design, CID-only payload, certified-status two-tier model (acting tier deferred). **Primary spec for this phase.**
- `docs/registration-protocol.md` — RegistrationTx schema (§2–3), submission path (§5–6), sequence semantics.
- `docs/child-wallet-identity-model.md` — Independent keypair, emergent child-ness, nonce vs sequence distinction.

### Architecture proposal
- `GNUS_Subwallet_Architecture_Proposal.md` — §Wallet Discovery (main subscribes to child channels). NOTE: §Registration Flow step 4 (main counter-signature) superseded by D-04/D-05 child-signed-only.

### Planning docs
- `.planning/PROJECT.md` — locked decisions; v2.0 milestone scope (registration only, no authority gate).
- `.planning/REQUIREMENTS.md` — RIMPL-04..07, TEST-01..04 (this phase's 8 requirements).
- `.planning/ROADMAP.md` §Phase 5 — goal + 4 success criteria + test scaffold reference note.
- `.planning/STATE.md` — blockers relevant here: `reg/` path constraint (never `tx/`), CID-only pubsub payload (D-18), ~121s E2E runtime, Phase 4 advisory review warnings (unchecked `dynamic_pointer_cast` in `SendTransactionItem` diversion — Phase 5 touches this code, fix opportunistically).

### Prior phase context (locked decisions)
- `.planning/milestones/v1.0-phases/02-crdt-persistence-pubsub-consensus-authority/02-CONTEXT.md` — D-11..D-18 (reg/ layout, filter gates, pubsub design), D-24..D-26 (consensus ordering, first-to-consensus tie-break, certified two-tier).
- `.planning/phases/04-registration-proto-transaction/04-CONTEXT.md` — D-40..D-45 (RegisterChild API shape, caller-supplied sequence, reg/ path diversion, minimal filter gates a–c, filter naming convention).

### Code anchor points (exist today — Phase 4 delivered several)
- `SuperGenius/src/account/TransactionManager.cpp` — `FilterRegistration` (line ~2770, gates a–c implemented, comment marks gate d insertion point at line 2809); reg/ filter registration (line ~222); `SendTransactionItem` reg/ path diversion (line ~1218); `FilterTransaction` `KeyExistsInDB` lookup pattern (line 2729); `RegisterChild`.
- `SuperGenius/src/account/RegistrationTransaction.hpp`/`.cpp` — `GetTopics()` already includes `main_address_` (line 102–107); `GetMainAddress`, `GetSequence`, serialization.
- `SuperGenius/src/account/GeniusNode.hpp`/`.cpp` — `RegisterChild` wrapper (GeniusNode.cpp:2285); where the discovery wrapper and CID handler may live.
- `SuperGenius/src/crdt/globaldb/globaldb.hpp` — `RegisterElementFilter`, CRDT Get/query API for the gate-d read and reg/ scan.
- `SuperGenius/src/crdt/globaldb/pubsub_broadcaster_ext.hpp` — `AddListenTopic`/`AddBroadcastTopic` for the follow behavior.
- `SuperGenius/test/src/multiaccount/multi_account_sync.cpp` — `CreateNode` pattern, `WaitForNodeSync`, `FILE_PREFIX` test-dir isolation. Integration test scaffold template.
- `SuperGenius/test/src/account/registration_transaction_test.cpp` — Phase 4 E2E test; `RegistrationE2ETestAccess` friend-accessor (line 164) reused for TEST-04 filter-level injection; unique-port-per-fixture pattern.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`FilterRegistration` (gates a–c)** — already registered on `^/?{bc-base}reg/[^/]+` in `TransactionManager::New()`; Phase 5 only adds gate (d) inside the existing method. The `// Phase 5 adds: (d) sequence monotonicity check` comment marks the exact insertion point.
- **`RegistrationTransaction::GetTopics()`** — already emits `main_address_`, so `SendTransactionItem`'s topic merge (line ~1245) already broadcasts on the main's channel. RIMPL-05's broadcast half is effectively done; Phase 5 adds the *reception* side.
- **`reg/` path diversion in `SendTransactionItem`** — RegistrationTx already writes to `GetBlockChainBase() + "reg/" + child_addr` (line ~1218). Read path uses the same key formula.
- **`RegistrationE2ETestAccess` friend accessor** — Phase 4's test hook exposes `FilterRegistration` and internals; TEST-04 negative injection reuses it directly.
- **`multi_account_sync.cpp` harness** — `CreateNode(self, dev, token, id, isFullNode, isProcessor, isGenesisAuthorized)`, `WaitForNodeSync`, per-fixture unique libp2p ports (40001 + fixture_id % 1000 pattern from Phase 4 debug).
- **`AccountMessenger` OnRequest/OnResponse pubsub message plumbing** — reference for how per-address topic handlers are wired (pattern only; no AccountMessenger proto changes in this phase).

### Established Patterns
- **Two-layer API convention** — `TransactionManager` method + thin `GeniusNode` wrapper (RegisterChild, TransferFunds). `GetRegistrationsForMain` follows it.
- **Filter reads DB during validation** — `FilterTransaction` calls `KeyExistsInDB(GetTransactionPath(...))`; gate (d) extends this to a value read + deserialize + compare.
- **outcome::result error handling** — all new APIs return `outcome::result<T>`; test assertions use `ASSERT_OUTCOME_SUCCESS` / `EXPECT_OUTCOME_*` macros from `test/testutil/outcome.hpp`.
- **Test structure** — GTest fixtures with `SetUp`/`TearDown`, `addtest()` CMake macro, tests under `test/src/<module>/` mirroring source.

### Integration Points
- `TransactionManager::FilterRegistration` — gate (d) insertion at the marked comment (line ~2809).
- `TransactionManager::RegisterChild` + `GeniusNode::RegisterChild` — auto-derive sequence overload.
- New `TransactionManager::GetRegistrationsForMain` + `GeniusNode` wrapper — reg/ scan over GlobalDB.
- Main-node CID handler — subscribes/handles messages on own address topic, triggers `AddListenTopic(child_addr)` after CRDT validation.
- `SuperGenius/test/src/multiaccount/regtest/child_registration.cpp` — new integration test + CMakeLists registration via `addtest()`.

### Critical Gaps / Risks
- **Shared-fixture state coupling** — one 3-node boot serving TEST-02/03/04 means CRDT state accumulates across cases; distinct child addresses per case is the isolation mechanism. Planner must verify no case depends on another's ordering.
- **Gate (d) CRDT read during filter execution** — the filter runs in the CRDT merge path; a synchronous Get on the same datastore must not deadlock or re-enter the merge. Researcher should confirm the datastore supports reads from within an element-filter callback (FilterTransaction's `KeyExistsInDB` suggests yes).
- **Phase 4 advisory warnings touch this code** — unchecked `dynamic_pointer_cast` in `SendTransactionItem` diversion and silent `SerializeByteVector` failure (04-REVIEW.md); Phase 5 modifies adjacent code and should fix opportunistically.
- **~121s GossipPubSub boot per network** — even amortized, a 3-node boot may exceed 121s; `WaitForNodeSync` timeouts need headroom, and CI runtime budget should be checked.
</code_context>

<specifics>
## Specific Ideas

- **User's discovery vision (captured, partially deferred):** "Main should request via AccountMessenger which child nodes it has; any node aware of a child via CRDT should report it; main follows the child with AddListenTopic." The *follow* behavior (CID handler → `AddListenTopic`) is in Phase 5; the AccountMessenger query/report protocol is LATER-01. When LATER-01 lands, it should implement exactly this request/report model.
- **User chose the 3-node topology deliberately** — propagation must be proven through a node that is neither the child nor the main, not just direct A↔B gossip.
</specifics>

<deferred>
## Deferred Ideas

- **AccountMessenger "list my children" request/response** — main polls peers, CRDT-aware nodes report known children (user's explicit design intent, this discussion). Belongs to LATER-01 (`docs/03-01-discovery-monitoring.md` push/poll). Carry the user's model forward verbatim.
- **Consensus authority gate `CheckParentChildAuthority`** (CONS-01..06, CAUTH-01) — later milestone.
- **Certified-status acting tier** (CAUTH-02) — v2.0 discovery reads filter-validated CRDT state only; "main only acts on certified registrations" enforcement comes with the authority milestone.
- **Wire-level malicious-peer injection tests** — TEST-04 uses filter-level injection; true byzantine-peer CRDT sync poisoning tests deferred.
- **Test-infra tuning of GossipPubSub timeouts** (~121s boot) — noted as discretionary improvement, not a phase requirement; consider a dedicated test-infra task if it blocks CI.
- **`GetTransactionFullPath()` refactor** — hardcoded `"tx/"` prefix technical debt carried from Phase 4.

</deferred>

---

*Phase: 5-CRDT Persistence, PubSub & Integration Test*
*Context gathered: 2026-07-16*
