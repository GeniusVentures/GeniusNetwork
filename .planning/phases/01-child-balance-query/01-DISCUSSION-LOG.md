# Phase 1: Child Balance Query - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-17
**Phase:** 01-child-balance-query
**Areas discussed:** Registration gate & errors, API surface & token default, Sync freshness semantics, Integration test design

---

## Registration Gate & Errors

| Option | Description | Selected |
|--------|-------------|----------|
| Strict gate: registered to THIS main | GetChildBalance checks reg/ CRDT for a record where main_address == this node's address. Unregistered → error. | |
| Exists-check: registered to anyone | Any reg/ record for the child address is enough — child must be registered, but not necessarily to this node. | |
| No gate: thin alias | No registration check — just sums UTXOs for the address like GetBalance(token_id, address). | ✓ |

**User's choice:** No gate: thin alias

---

| Option | Description | Selected |
|--------|-------------|----------|
| Plain uint64_t, 0 when unknown | Matches the GetBalance overload family. No failure mode exists since there's no gate. | ✓ |
| outcome::result<uint64_t> | Wraps in outcome::result to reserve room for future error cases without an API break. | |

**User's choice:** Plain uint64_t, 0 when unknown

---

## API Surface & Token Default

| Option | Description | Selected |
|--------|-------------|----------|
| GetChildBalance(child_address, token_id) | Child-first parameter order, as written in ROADMAP.md success criteria. | ✓ |
| GetChildBalance(token_id, child_address) | Matches existing GetBalance(TokenID, address) overload. | |
| You decide | Planner picks. | |

**User's choice:** GetChildBalance(child_address, token_id)

**Notes:** User clarified that `token_id` refers to the **child wallet's registered token** (not the main's local `dev_config_.TokenID`). The child's token ID likely differs from the main's — each node has its own DevConfig. Caller supplies it out-of-band (test reads from `child_node_->GetTokenID()`). Child token amounts derive from GNUS — the raw `uint64_t` is already in GNUS base units (minions); child-token display is a ratio-divide concern deferred to the API/formatting phase.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Caller supplies child's token_id | Caller passes the child's token ID it learned out-of-band (test knows it from the child's DevConfig). No proto change. | ✓ |
| Derive from synced UTXOs | Main scans the child's synced UTXOs and sums per whatever token IDs it finds there. | |
| From registration record (proto change) | Would put the child's token ID into RegistrationMetadata — deferred. | |

**User's choice:** Caller supplies child's token_id

---

| Option | Description | Selected |
|--------|-------------|----------|
| Add all-tokens overload too | Two overloads: token-filtered and all-tokens sum in GNUS base units. | ✓ |
| Token-filtered only | Only GetChildBalance(child_address, token_id) this milestone. | |

**User's choice:** Add all-tokens overload too

---

| Option | Description | Selected |
|--------|-------------|----------|
| GeniusNode-only, like GetBalance | GeniusNode method calls account_->GetUTXOManager().GetBalance(...) directly. | ✓ |
| Two-layer via TransactionManager | TransactionManager::GetChildBalance + thin GeniusNode wrapper. | |
| You decide | Planner picks. | |

**User's choice:** GeniusNode-only, like GetBalance

---

## Sync Freshness Semantics

| Option | Description | Selected |
|--------|-------------|----------|
| Purely passive local read | Returns whatever the local CRDT/UTXO view holds right now — no sync triggering, no waiting. | ✓ |
| Passive read + ensure-following | Additionally checks the main is subscribed to the child's topic and subscribes if not. | |

**User's choice:** Purely passive local read

---

| Option | Description | Selected |
|--------|-------------|----------|
| Accept ambiguity, document it | 0 means "no READY UTXOs in my local view" — could be not-synced-yet OR genuinely empty. Document in Doxygen. | ✓ |
| Add a sync-status helper | `HasSyncedDataFor(address)` or similar to distinguish the cases. | |

**User's choice:** Accept ambiguity, document it

---

## Integration Test Design

| Option | Description | Selected |
|--------|-------------|----------|
| Extend child_registration.cpp fixture | New TEST_F using shared 3-node SetUpTestSuite, distinct child address. | ✓ |
| New test file | Cleaner isolation but pays ~121s boot again. | |
| You decide | Planner picks. | |

**User's choice:** Extend child_registration.cpp fixture

---

| Option | Description | Selected |
|--------|-------------|----------|
| Child mints own token, main queries | MintTokens on child so it has a UTXO. Main queries after CRDT sync converges. | ✓ |
| Main mints + transfers to child | Main mints, then TransferFunds to child. Adds a transfer dependency. | |

**User's choice:** Child mints own token, main queries

---

| Option | Description | Selected |
|--------|-------------|----------|
| Poll-until-sync + value check | Poll child_node->GetBalance until non-zero, then assert main's GetChildBalance matches. | ✓ |
| Mint known amount + one-shot assert | One-shot assertion within a timeout — simpler but flakier. | |

**User's choice:** Poll-until-sync + value check

---

## the agent's Discretion

- Exact test case name, mint amount, and poll timeout — planner chooses reasonable defaults from existing test patterns.
- Whether the test uses `GetTokenID()` from `child_node_` or hardcodes the token ID — planner picks whichever reads cleanest for shared-fixture isolation.
- Doxygen wording for the 0-ambiguity caveat — planner writes idiomatic `@return` notes matching the existing GetBalance documentation style.

## Deferred Ideas

- **Child token ID in RegistrationMetadata** (proto field) so main can discover it — blocked by no-new-proto-fields constraint this milestone.
- **Sync-status helper** (HasSyncedDataFor or staleness signal) — deferred to API phase.
