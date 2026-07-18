# Roadmap: GNUS Child Wallet

## Milestones

- ✅ **v1.0 Child Wallet Design** — Phases 1-3 (shipped 2026-07-15)
- ✅ **v2.0 Registration Implementation** — Phases 1-2 (shipped 2026-07-17)
- ✅ **v2.1 Main Wallet Child Balance Query** — Phase 1 (shipped 2026-07-17)
- 🚧 **v2.2 GeniusSDK Child Wallet Interfaces** — Phase 2 (in progress)

## Phases

<details>
<summary>✅ v1.0 Child Wallet Design (Phases 1-3) — SHIPPED 2026-07-15</summary>

Archived: [`.planning/milestones/v1.0-ROADMAP.md`](milestones/v1.0-ROADMAP.md)

</details>

<details>
<summary>✅ v2.0 Registration Implementation (Phases 1-2) — SHIPPED 2026-07-17</summary>

Archived: [`.planning/milestones/v2.0-ROADMAP.md`](milestones/v2.0-ROADMAP.md)

</details>

<details>
<summary>✅ v2.1 Main Wallet Child Balance Query (Phase 1) — SHIPPED 2026-07-17</summary>

Archived: [`.planning/milestones/v2.1-ROADMAP.md`](milestones/v2.1-ROADMAP.md)

- [x] Phase 1: Child Balance Query (2/2 plans) — completed 2026-07-17

</details>

### 🚧 v2.2 GeniusSDK Child Wallet Interfaces (In Progress)

**Milestone Goal:** Expose `GeniusNode::RegisterChild`, `GetRegistrationsForMain`, and `GetChildBalance` through the public C SDK (`GeniusSDK.h`/`.cpp`) so external games/apps can register a child wallet and query its balance without linking SuperGenius directly.

- [ ] **Phase 2: GeniusSDK Child Wallet Interfaces** - Wrap child registration, discovery, and balance query in the public GeniusSDK C API

## Phase Details

### Phase 2: GeniusSDK Child Wallet Interfaces
**Goal**: External callers (games/apps linking only `GeniusSDK.h`) can register this node as a child wallet, discover a main wallet's registered children, and query child balances — entirely through the public C SDK, without linking SuperGenius directly
**Depends on**: v2.0 (`RegisterChild`, `GetRegistrationsForMain`), v2.1 Phase 1 (`GetChildBalance`)
**Requirements**: SDKR-01, SDKR-02, SDKR-03, SDKR-04, SDKB-01, SDKB-02
**Success Criteria** (what must be TRUE):
  1. External caller can register this node as a child wallet under a main wallet address via a GeniusSDK C function, supplying registration metadata (game_id, publisher_id, dev_wallet, peers_cut) through a new `GeniusRegistrationMetadata` C struct, without linking SuperGenius directly
  2. A main-side caller can enumerate its registered children (address, sequence, metadata) via a GeniusSDK C function that wraps `GetRegistrationsForMain`
  3. External caller can query a child wallet's balance for a specific token, and separately its total balance across all tokens, via GeniusSDK C functions that wrap the two `GetChildBalance` overloads
  4. Registration, discovery, and balance calls all return existing `GeniusNodeReturnValue_t` status codes for not-initialized and invalid-argument conditions, consistent with other GeniusSDK calls
**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|-----------------|--------|-----------|
| Child Balance Query | v2.1 | 2/2 | Complete | 2026-07-17 |
| GeniusSDK Child Wallet Interfaces | v2.2 | 0/TBD | Not started | - |

---
*Roadmap updated: 2026-07-17 after dropping TEST-01 (GeniusSDK/test coverage) from Phase 2 scope*
