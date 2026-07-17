# Phase 1: Child Balance Query - Context

**Gathered:** 2026-07-17
**Status:** Ready for planning

<domain>
## Phase Boundary

The main wallet node queries a child wallet's token balance from its locally-synced CRDT UTXO data, without gRPC or SDK involvement — purely node-internal. A multi-node integration test proves the end-to-end flow: child registers with main, child mints funds via its own DevConfig token, main queries balance after CRDT sync converges.

`GeniusNode::GetChildBalance` is a thin alias over the existing GetBalance family (`UTXOManager::GetBalance(token_id, address)`) targeting a different address. No new proto messages, no registration validation — the method sums READY UTXOs from the local view exactly as GetBalance does.

</domain>

<decisions>
## Implementation Decisions

### GetChildBalance API (BALT-01)
- **D-54:** No registration gate — `GetChildBalance` is a thin alias over the existing `GetBalance` path. There is no check for a `reg/` record, no validation that the child is registered to this main, and no scope to a subset of addresses. Any address works; unknown/unsynced addresses return 0.
- **D-55:** Returns plain `uint64_t` (not `outcome::result`). Consistent with the existing `GetBalance(TokenID, std::string)` overload family at `GeniusNode.hpp:406-428`. No failure path exists — the thin-alias has nothing to fail on.
- **D-56:** Parameter order is child-first: `GetChildBalance(const std::string &child_address, TokenID token_id)`. Matches the roadmap sketch despite `GetBalance` being token-first — child-centric semantics read more naturally.
- **D-57:** `token_id` refers to the **child wallet's registered token** (not the main's local `dev_config_.TokenID`). The child's token ID likely differs from the main's — each node has its own DevConfig. Caller supplies it out-of-band (e.g., the integration test reads `child_node_->GetTokenID()`).
- **D-58:** Token ID is **always explicit** — no defaulting to `dev_config_.TokenID`. Defaulting would silently hide which token was queried and could mask mismatches.
- **D-59:** Two overloads, mirroring the GetBalance family:
  1. `GetChildBalance(const std::string &child_address, TokenID token_id)` — filter by token
  2. `GetChildBalance(const std::string &child_address)` — sum ALL child UTXOs, returning GNUS base units (amounts are stored in minions; child-token display is a ratio-divide concern deferred to the API/formatting phase)
- **D-60:** **GeniusNode-only placement** — the method lives directly on `GeniusNode`, calling `account_->GetUTXOManager().GetBalance(...)` the same way the existing GetBalance family does (`GeniusNode.cpp:2430-2448`). Balance reads do not go through TransactionManager today, and GetChildBalance does not introduce a new layer.

### Sync Freshness
- **D-61:** Purely passive local read — returns whatever the local CRDT/UTXO view holds at call time. No sync triggering, no waiting for convergence, no AddListenTopic side effect. Consistent with the thin-alias design and the "no direct child query" scope boundary.
- **D-62:** A return value of 0 is ambiguous: could mean genuinely zero balance, or no UTXO data synced yet. This ambiguity is **accepted and documented** in the Doxygen `@return` notes. Callers who need distinction use `GetRegistrationsForMain` or poll. No sync-status helper in this milestone.

### Integration Test (INTG-01)
- **D-63:** Extend `SuperGenius/test/src/multiaccount/regtest/child_registration.cpp` — new `TEST_F` case using the existing shared 3-node fixture (`SetUpTestSuite` boots once, D-52/D-51 pattern). Isolate with a **distinct child address** so the balance case doesn't collide with existing registration test cases in shared CRDT state.
- **D-64:** **Child mints, main queries** — the child node calls `MintTokens` on itself (using its own DevConfig token), then CRDT sync propagates the UTXO to the main node. No TransferFunds cross-node dependency in this test case.
- **D-65:** Poll-until-sync assertion: poll `child_node_->GetBalance(child_token_id)` until non-zero (sync convergence), then assert `main_node_->GetChildBalance(child_addr, child_token_id) == expected_amount`. The poll guard eliminates flakiness from async CRDT propagation timing.

### the agent's Discretion
- Exact test case name, mint amount, and poll timeout — planner chooses reasonable defaults from existing test patterns.
- Whether the test uses `GetTokenID()` from `child_node_` or hardcodes the token ID from the fixture's DevConfig — both work; planner picks whichever reads cleanest against the shared-fixture isolation rules.
- Doxygen wording for the 0-ambiguity caveat — planner writes idiomatic `@return` notes matching the existing GetBalance documentation style.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design Docs
- `docs/03-01-discovery-monitoring.md` — D-28: per-child balance aggregation from child's tx/ CRDT; the balance query follows the same data-source model
- `docs/02-crdt-registry-pubsub.md` — reg/ namespace layout; D-49 RegElementCallback pubsub follow (child UTXOs sync to main via AddListenTopic)
- `docs/registration-protocol.md` — RegistrationTx schema, sequence semantics, RegistrationMetadata fields
- `docs/child-wallet-identity-model.md` — Independent keypair model, emergent child-ness (D-01), UTXO ownership (D-02)

### Planning Docs
- `.planning/PROJECT.md` — Milestone v2.1 scope; locked decisions: balance from synced CRDT only, no gRPC/SDK, child token only, no new proto
- `.planning/REQUIREMENTS.md` — BALT-01, INTG-01 (this phase's 2 requirements)
- `.planning/ROADMAP.md` — Phase 1 goal + 3 success criteria + implementation notes
- `.planning/STATE.md` — Current milestone v2.1, phase status, core value

### Prior Phase Context (locked decisions)
- `.planning/milestones/v2.0-phases/05-crdt-persistence-pubsub-integration-test/05-CONTEXT.md` — D-48 (GetRegistrationsForMain two-layer API), D-49 (CID-notification handler + AddListenTopic follow), D-51/D-52 (3-node integration test fixture pattern)
- `.planning/milestones/v2.0-phases/04-registration-proto-transaction/04-CONTEXT.md` — D-40/D-41 (RegisterChild two-layer convention), D-43 (reg/ path divergence)
- `.planning/milestones/v1.0-phases/03-discovery-rewards-lifecycle/03-CONTEXT.md` — D-28 (per-child balance from child's tx/ CRDT subscription)

### Code Anchor Points (exist today)
- `SuperGenius/src/account/GeniusNode.hpp:406-428` — GetBalance overload family (no-arg, token-only, address-only, token+address) — the pattern GetChildBalance mirrors
- `SuperGenius/src/account/GeniusNode.hpp:466-469` — `GetTokenID()` returning `dev_config_.TokenID`
- `SuperGenius/src/account/GeniusNode.cpp:2430-2448` — GetBalance implementations (direct UTXOManager delegation)
- `SuperGenius/src/account/UTXOManager.hpp:129-151` — GetBalance signatures (account-owning, address-filtered, token-filtered)
- `SuperGenius/src/account/UTXOManager.cpp:86-147` — GetBalance implementations with D-17 foreign-address guard already removed; `address_outpoints_` iterates any address's UTXOs
- `SuperGenius/test/src/multiaccount/regtest/child_registration.cpp` — Shared 3-node fixture (SetUpTestSuite line 111), `CreateNode` helper (line 154), existing TEST_F cases (line 220+) — integration test scaffold to extend
- `SuperGenius/test/src/multiaccount/multi_account_sync.cpp` — `MintTokens` usage pattern (line 199-221), `WaitForNodeSync`, poll-until-match patterns
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`GeniusNode::GetBalance` overload family** — 4 overloads (no-arg, token, address, token+address) at `GeniusNode.hpp:406-428` and `GeniusNode.cpp:2430-2448`. All delegates to `UTXOManager`. GetChildBalance mirrors the token+address overload targeting a different address.
- **`UTXOManager::GetBalance(token_id, address)`** — D-17 foreign-address guard already removed. Iterates `address_outpoints_[address]`, filtering by state==READY and token match. Same logic applies to any address, including child addresses.
- **`GeniusNode::MintTokens`** — Available on all nodes for funding the test child without cross-node transfer dependency. Pattern from `multi_account_sync.cpp:199`.
- **3-node shared fixture in child_registration.cpp** — `SetUpTestSuite` boots genesis + main + child once; `TEST_F` cases reuse. Amortizes ~121s GossipPubSub boot.

### Established Patterns
- **Balance reads are GeniusNode-only** — `GetBalance` family never goes through TransactionManager. GetChildBalance follows this directly.
- **Poll-until-convergence test pattern** — `multi_account_sync.cpp` uses lambdas polling until a condition is met (sync convergence). The balance test uses the same pattern to wait for CRDT sync.
- **`WaitForNodeSync` + `AddPeer`** — existing synchronization primitives for the integration test.
- **Distinct address per test case** — Phase 5 D-52 isolation rule: each TEST_F uses a distinct child address to avoid CRDT state collisions in the shared fixture.

### Integration Points
- `GeniusNode.hpp` (near line 428) — new `GetChildBalance` declarations placed adjacent to existing GetBalance overloads
- `GeniusNode.cpp` (near line 2448) — implementations delegating to `account_->GetUTXOManager().GetBalance(...)`
- `child_registration.cpp` (near line 277) — new `TEST_F(ChildRegistrationIntegrationTest, MainQueriesChildBalance)` appended after existing tests
- `SuperGenius/test/src/multiaccount/regtest/CMakeLists.txt` — `addtest()` registration for the new test case already covered (test file already registered)

### Critical Gap
- **Zero-ambiguity is inherent and accepted** — GetChildBalance cannot distinguish "unsynced" from "empty" with its current interface. This is a documented limitation, not a bug. The test addresses it by polling until non-zero before asserting.
</code_context>

<specifics>
## Specific Ideas

- **User's token ID model:** The child's token ID is separate from the main's — each node has its own `DevConfig.TokenID`. The main doesn't need the child's token ID to be discoverable from the registration record; the caller knows it out-of-band (tests read `child_node_->GetTokenID()`). Storing the child's token ID in `RegistrationMetadata` was considered but rejected this milestone due to the no-new-proto-fields constraint.
- **UTXO amounts are GNUS base units** — the raw `uint64_t` returned by `UTXOManager::GetBalance` is already in minions (GNUS base units). Child-token display formatting (`TokenAmount::ConvertToChildToken`) is a ratio-divide concern deferred to the API phase. The all-tokens overload `GetChildBalance(child_address)` returns the sum of all child UTXOs without token filtering — total GNUS-denominated holdings.
</specifics>

<deferred>
## Deferred Ideas

- **Child token ID in RegistrationMetadata** — adding a `token_id` field to the registration proto so the main can discover the child's configured token without out-of-band knowledge. Blocked by the no-new-proto-fields constraint this milestone. Belongs in a future milestone (likely the API multi-token phase).
- **Sync-status helper** (`HasSyncedDataFor` or staleness signal) — allowing callers to distinguish "no data synced yet" from "genuinely zero balance." Deferred to API phase.
- **gRPC/GeniusSDK balance endpoint** — node-internal only this milestone; external API layer deferred per REQUIREMENTS.md.
- **Balance display formatting** (FormatTokens, ConvertToChildToken) — deferred to API phase.
- **Multi-token balance** (GNUS, NFTs, other tokens) — this milestone is child token only.

</deferred>

---

*Phase: 1-Child Balance Query*
*Context gathered: 2026-07-17*
