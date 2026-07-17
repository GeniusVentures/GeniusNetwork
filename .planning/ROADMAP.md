# Roadmap: GNUS Child Wallet v2.1

**Milestone:** v2.1 Main Wallet Child Balance Query
**Created:** 2026-07-17
**Phase numbering:** Start at Phase 1 (first GSD-tracked milestone)

## Phase Overview

| # | Phase | Goal | Requirements | Success Criteria |
|---|-------|------|--------------|------------------|
| 1 | Child Balance Query | 1/2 | In Progress|  |

## Phase 1: Child Balance Query

**Goal:** Allow the main wallet to query a registered child wallet's child token balance from locally-synced CRDT UTXO data, and prove it works with a multi-node integration test.

**Requirements:**

- **BALT-01**: `GeniusNode::GetChildBalance(child_address, token_id)` wraps existing `UTXOManager::GetBalance(token_id, address)` to compute child token balance from synced CRDT
- **INTG-01**: Multi-node integration test validates end-to-end balance query after registration and funding

**Success Criteria:**

1. `GeniusNode::GetChildBalance(child_address, token_id)` returns correct child token balance computed from locally-synced CRDT UTXOs
2. Multi-node integration test passes: child registers with main, receives child token funds, main calls GetChildBalance, returned balance matches the funded amount
3. All existing registration tests (unit + multi-node integration) continue to pass — no regressions

**Plans:** 1/2 plans executed

Plans:
**Wave 1**

- [x] 01-01-PLAN.md — Add GetChildBalance overloads (GeniusNode.hpp/.cpp), mirroring the GetBalance family per D-54–D-60

**Wave 2** *(blocked on Wave 1 completion)*

- [ ] 01-02-PLAN.md — Add multi-node integration test (child_registration.cpp) proving BALT-01 end-to-end per D-63–D-65

**Depends on:**

- v2.0 registration infrastructure (RegistrationTransaction, reg/ CRDT filter, D-49 RegElementCallback pubsub follow)
- Existing `UTXOManager::GetBalance(token_id, address)` pattern in `GeniusNode`

### Implementation Notes

- **No new proto messages needed** — balance is computed in-memory from existing UTXO data synced via CRDT
- **No gRPC endpoint** — node-internal only; API layer deferred
- **Follow existing pattern**: `GeniusNode::GetBalance(token_id, address)` already delegates to `UTXOManager::GetBalance(token_id, address)` — `GetChildBalance` just targets a different address
- **Integration test pattern**: Follow existing `child_registration.cpp` multi-node test structure — spin up 3 nodes, register child with main, fund child, query balance, assert
- **CRDT sync is already active**: D-49 RegElementCallback subscribes main to child's pubsub topic on registration arrival, so child UTXOs are already syncing to main's local CRDT

---
*Roadmap created: 2026-07-17*
