# Phase 3: Discovery, Rewards & Lifecycle - Context

**Gathered:** 2026-07-14
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase produces two design documents:
1. **Discovery & monitoring** — how the main wallet discovers registered children, what per-child information it aggregates, and what actions it can take (DISC-01..03).
2. **Reward policy + lifecycle/change flows** — per-child processing-reward policy for standalone and registered children, hold-time pinning, authenticated update rules, the lifecycle state machine, replace/remove/detach/revoke change-flows with replay-safe conflict resolution (RWD-01..03, LIFE-01..04).

Phase 2 already designed the CRDT `reg/` namespace, pubsub broadcast/subscription (D-15..D-18), consensus parent-child authority rules (D-19..D-23), and the certified-status two-tier model (D-26). Phase 3 builds on that foundation — it does not redesign how registration persists or how authority is enforced.

UI-level display (GeniusWallet Flutter app) is described conceptually only; concrete platform UI flows are v2 (PLAT-01, PLAT-02).
</domain>

<decisions>
## Implementation Decisions

### Discovery CRDT Layout & Polling (DISC-01)
- **D-27:** Discovery is **push-primary, poll-fallback**. The primary path is pubsub broadcast (Phase 2 D-15/D-16 — child publishes registration CID to main's address topic). If the main misses a broadcast (late join, network partition), it **polls** by sending a query on its own pubsub channel via `AccountMessenger`: "what child wallets do I have?" Any node with CRDT state (full node, the child itself, any peer that synced the reg/ namespace) can respond with the list of RegistrationTx records whose `main_address` matches the querying main. The main wallet caches discovered children in a **local JSON file** for persistence across restarts. No additional CRDT index namespace — discovery is peer-to-peer, not stored in consensus state.

### Per-Child Information (DISC-02)
- **D-28:** Per-child display information comes from multiple sources aggregated by the main's local logic:
  - **From reg/ CRDT:** child address, main_address, sequence, game_id, publisher_id, dev_wallet, peers_cut, registration timestamp, lifecycle status (certified/detached/revoked).
  - **From child's tx/ CRDT** (subscribed via Phase 2 D-17 `AddListenTopic(child_address)`): current balance, UTXO list, recent transaction activity.
  - **From local cache:** last-seen timestamp, any display preferences.
  - The design document specifies the aggregation logic and data sources for each field listed in DISC-02 — it does not define a new CRDT namespace for this aggregated view.

### Main-Wallet Actions (DISC-03)
- **D-29:** Main-wallet actions over discovered children re-use existing and Phase-2-designed mechanics:
  - **Fund** (main→child): Phase 2 CONS-01 — main-signed transfer, CheckParentChildAuthority validates reg/ record exists linking child to that main.
  - **Recover** (main-recover-from-child): Phase 2 CONS-02 — main-signed transfer FROM child address, destination hard-restricted to registered main_address (D-21).
  - **Inspect history / view assets:** Phase 2 SYNC-04 — main reads child's CRDT state via subscribed pubsub channel (D-17). Read-only, no signature needed (CRDT state is public).
  - **Revoke:** LIFE-01 — main-signed consensus transaction that sets the reg/ record's detached flag (see D-33). Destroys main's recovery authority over the child.
  - **Detach:** LIFE-01 — child-signed RegistrationTx with detach flag. Child initiates (D-33).
  - The Phase 3 design document for DISC-03 specifies these action→mechanism mappings, not new consensus rules.

### Standalone Child Reward Policy (RWD-01)
- **D-30:** For a **standalone child** (no reg/ record), the processing reward policy comes from the **SDK `DevConfig_st`** (`Addr`, `Cut`) at escrow-hold time — exactly the same mechanics as today. The `GeniusNode::HoldEscrow` call reads `dev_config_.Addr` and `dev_config_.Cut` to construct the `EscrowTransaction`. Standalone children get whatever dev_addr/peers_cut the game publisher configured in the SDK.
- **D-31:** When a standalone child **registers** with a main, the `RegistrationMetadata.dev_wallet` and `RegistrationMetadata.peers_cut` **supersede** the SDK DevConfig defaults for all **new** escrows created after the registration is certified. Existing escrows retain the policy pinned at their original HoldEscrow time (immutable — consistent with the existing EscrowTransaction model). This gives publishers a path: ship with default SDK config, then the connect/registration flow sets the per-child policy that takes effect going forward.

### Hold-Time Pinning (RWD-02)
- **D-32:** The reward policy (`dev_addr`, `peers_cut`) is **pinned at `HoldEscrow` time** — the `EscrowTransaction` stores these values in its own fields (`dev_addr_`, `peers_cut_`), NOT as a reference to a reg/ record that could change. This is the existing behavior and requires no design change. The `PayEscrow` path reads the escrow transaction's stored values, not the current reg/ state. Mid-flight policy changes (new RegistrationTx with different dev_wallet/peers_cut) do NOT affect in-progress escrows.

### Authenticated Policy Updates (RWD-03)
- **D-33:** Reward policy updates are **child-only** via a new `RegistrationTx` with a **higher `sequence`** number and updated `RegistrationMetadata` (dev_wallet, peers_cut). The child signs the updated RegistrationTx; consensus accepts it because the child's signature is valid over its own registration (same model as D-04/D-05). Publishers must trust the child not to redirect payouts — this is a UX/social contract, not a cryptographic constraint. The main cannot update the child's reward policy unilaterally. The publisher cannot update it without the child's cooperation. The `sequence` field provides the ordering: CRDT merges keep the highest-sequence RegistrationTx as authoritative, so the latest child-signed update wins.

### Lifecycle State Machine (LIFE-01)
- **D-34:** The lifecycle state machine has **four states** (not six — "registration-pending" and "closed" are removed per child-signed-only model):
  - **Unregistered (standalone):** No `reg/{child_addr}` record exists. Child operates independently. Reward policy from SDK DevConfig (D-30).
  - **Registered:** A certified `reg/{child_addr}` record exists with a non-empty `main_address` and no detached flag. Main has recovery authority, child broadcast is active, reward policy from RegistrationMetadata (or DevConfig fallback for escrows created before registration certification).
  - **Detached:** The `reg/{child_addr}` record exists with the detached flag set. The child signed the detachment (new RegistrationTx with detach flag, higher sequence). Main has read-only visibility (inspect history/balance), zero recovery authority. Child retains all UTXOs and operates as a standalone wallet with registration history.
  - **Revoked:** The `reg/{child_addr}` record exists with the detached flag set. The **main signed** the revocation (main-signed consensus transaction, see D-35). Same CRDT outcome as detached (same flag), but different initiator. Main has read-only visibility, zero recovery authority.
  - There is no "registration-pending" state — with child-signed-only (D-04), registration is immediate upon certification; there's no main-consent gate that would create a pending window.
  - There is no "closed" state — child wallets are accounts with keypairs; they don't "close." If the key is lost, funds are unrecoverable (inherent property of the keypair model, not a lifecycle transition).
  - **Transitions:**
    - Unregistered → Registered: child issues RegistrationTx (D-06).
    - Registered → Detached: child issues new RegistrationTx with detach flag (higher sequence).
    - Registered → Revoked: main issues main-signed revocation transaction.
    - Detached/Revoked → Registered: child issues new RegistrationTx with higher sequence (re-registration to same or different main per D-36).
    - Detached/Revoked do NOT transition back to Unregistered — the reg/ record is retained (D-35).

### Replace/Remove Main Flows (LIFE-02, LIFE-03)
- **D-35:** **Detach (child-initiated):** The child issues a new `RegistrationTx` with a higher `sequence` number and a **detach flag** (or equivalently, an empty/zero `main_address`). The reg/ CRDT record is updated in-place: the `main_address` is cleared (or set to zero-address) and a `detached` status field is set. The record is **retained** — it serves as an audit trail and lets the former main inspect history. The child retains all UTXOs and can transact independently. No main signature is required.
- **D-36:** **Revoke (main-initiated):** The main issues a **main-signed consensus transaction** that targets the child's reg/ record and sets the detached flag. This is the only main-signed lifecycle action. Consensus validates: (1) the main's signature is valid, (2) the reg/ record's `main_address` matches the signing main's address, (3) the reg/ record is currently in the Registered state (not already detached/revoked). After revocation, the main has zero recovery authority — revocation is final for that main. The child can re-register (to the same or a different main) at any time with a new RegistrationTx at higher sequence.
- **D-37:** **Main replacement (LIFE-03 fork):** When a child wants to change its registered main, it issues a new `RegistrationTx` with a higher `sequence`, a different `main_address`, and **no detach flag**. The replacement is **child-only** — no consent signature is required from the old main. This is consistent with D-04/D-05: registration is child-signed-only and grants the main zero authority over the child's UTXOs (recovery requires the main's own signature at spend time — D-21). The old main loses recovery rights over future balances; the new main gains recovery rights going forward. Rationale: requiring old-main consent would create a deadlock if the old main's key is lost; child-only replacement keeps the child in control of its own custody relationships.
- **D-38:** **"Supersedes seq N" linkage:** Every lifecycle-change RegistrationTx (replace main, detach) carries a `supersedes_sequence` field referencing the `sequence` of the registration it replaces. This creates an explicit chain-of-custody. The CRDT reg/ filter rejects any update whose `supersedes_sequence` does not match the current reg/ record's `sequence` — preventing race conditions where two competing updates fork from the same base. Combined with the nonce chain (D-24: RegistrationTx flows through `sgns.nonce.v1` consensus), this gives deterministic ordering: the first update to reach consensus at its nonce wins, and the second is rejected at the reg/ filter because its `supersedes_sequence` no longer matches the updated current record.

### Detach Semantics (LIFE-04)
- **D-39:** Detaching (or being revoked) leaves the child wallet as a **valid standalone wallet**. The child's UTXOs, keypair, and nonce are unaffected — only the reg/ record's status changes. The child can continue creating transfers, receiving funds, and earning processing rewards independently. If the child later re-registers (to the same or a different main), the lifecycle continues from the current registration's sequence. The design document explicitly states that detach/revoke does NOT destroy the child wallet — it only severs the parent-child authority relationship.

### the agent's Discretion
- Exact proto field additions for the detached flag, `supersedes_sequence`, and the revoke transaction message — planner/researcher choose the idiomatic form matching existing proto conventions.
- The `AccountMessenger` mechanism for discovery polling — researcher identifies the existing message-bus pattern in `watcher/messaging_watcher` and extends it for the child-discovery query/response protocol.
- Local JSON cache schema and file location for the main wallet's discovered-children list — planner selects a format compatible with existing `boost::json` usage.
- The exact shape of the lifecycle state machine diagram and transition table — planner produces this from D-34/D-35/D-36.
- Naming of the revoke transaction subclass and its placement under `SuperGenius/src/account/` — follow existing `GeniusTransaction` subclass conventions.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Authoritative spec
- `GNUS_Subwallet_Architecture_Proposal.md` — Phase-3-relevant sections: §Wallet Discovery (main subscribes to child channels), §Rewards/Payments (per-child processing reward split), §Lifecycle States (standalone→pending→registered→detached→revoked→closed — NOTE: superseded by D-34 reducing to 4 states), §Security Model (main recovery authority, bounded compromise).
- `.planning/phases/01-child-identity-registration-protocol/docs/registration-protocol.md` — `RegistrationTx` schema (dag_struct, main_address, sequence, RegistrationMetadata with dev_wallet/peers_cut), additive proto rules, backward-compatibility matrix. This is the canonical field reference for all registration-related data.
- `.planning/phases/01-child-identity-registration-protocol/docs/child-wallet-identity-model.md` — Independent keypair model, emergent child-ness (D-01), UTXO ownership (D-02), nonce tracking (D-03).

### Phase 1 context (locked decisions)
- `.planning/phases/01-child-identity-registration-protocol/01-CONTEXT.md` — D-01 through D-10. Relevant to Phase 3: D-01 (emergent child-ness — no account-type field), D-04/D-05 (child-signed-only registration, no main counter-signature, grants zero authority), D-06 (first-class RegistrationTx), D-08 (RegistrationTx + RegistrationMetadata schema), D-09 (nonce + sequence).

### Phase 2 context (locked decisions)
- `.planning/phases/02-crdt-persistence-pubsub-consensus-authority/02-CONTEXT.md` — D-11 through D-26. Relevant to Phase 3: D-11 (reg/ namespace), D-12 (CRDT key `reg/{child_addr}`), D-14 (CRDT value = full RegistrationTx protobuf), D-15/D-16 (pubsub broadcast + discovery trigger), D-17 (main subscribes to child channels for state sync), D-18 (pubsub notification payload = CID only), D-19/D-20/D-21/D-22/D-23 (CheckParentChildAuthority gate + 6 consensus rules), D-26 (certified status flag — main only acts on certified registrations).
- `.planning/phases/02-crdt-persistence-pubsub-consensus-authority/02-01-PLAN.md` — CRDT namespace/key layout, FilterRegistration design, pubsub broadcast/sub, certified status.
- `.planning/phases/02-crdt-persistence-pubsub-consensus-authority/02-02-PLAN.md` — CheckParentChildAuthority gate, 6 consensus rules, field validation.

### Planning docs
- `.planning/PROJECT.md` — locked project-level decisions: independent keypair, consensus-enforced authority, CRDT persistence, child-signed-only. Key decisions for Phase 3: "Reuse escrow reward-split mechanics for child processing rewards."
- `.planning/REQUIREMENTS.md` — DISC-01..03, RWD-01..03, LIFE-01..04. These are the 10 requirements this phase must satisfy.
- `.planning/ROADMAP.md` §Phase 3 — goal + 4 success criteria this context must satisfy.

### Research
- `.planning/research/SUMMARY.md` — stack/feature/architecture grounding (HIGH confidence).
- `.planning/research/PITFALLS.md` — Phase-3-relevant pitfalls: Pitfall 3 (recovery-as-seizure — addressed by D-21 destination restriction + D-36 revoke as main action), Pitfall 5 (pubsub trust — addressed by D-27 validation-before-action), Pitfall 6 (child-key blast radius — bounded by independent keypair).

### Code anchor points (audited, exist today)
- `SuperGenius/src/account/GeniusNode.hpp` + `.cpp` — `DevConfig_st` (Addr, Cut, TokenID), `HoldEscrow` (reads dev_config_ for dev_addr/peers_cut), `PayEscrow` (reads escrow transaction's stored values), `PayDev` (child→developer transfer path). These are the reward-policy anchors.
- `SuperGenius/src/account/EscrowTransaction.hpp` + `.cpp` — `escrow-hold`/`escrow-release` tx types, `dev_addr_`/`peers_cut_`/`amount_` fields pinned at construction. Pattern for "hold-time pinning" (D-32).
- `SuperGenius/src/account/TransactionManager.hpp` + `.cpp` — `HoldEscrow`, `PayEscrow`, `ValidateTransactionForConsensus` (where revoke transaction would slot), `CheckParentChildAuthority` gate (Phase 2 D-19 — extended in Phase 3 for revoke path).
- `SuperGenius/src/crdt/globaldb/globaldb.hpp` — `RegisterElementFilter` pattern for new revoke tx filter if a separate filter is needed.
- `SuperGenius/src/crdt/globaldb/pubsub_broadcaster_ext.hpp` — `AddListenTopic`/`AddBroadcastTopic` — the pubsub channel API for discovery push and poll (D-27).
- `SuperGenius/src/account/proto/SGTransaction.proto` — where new fields (detach flag, supersedes_sequence, revoke tx message) are appended additively.
- `SuperGenius/src/account/proto/Consensus.proto` — `EmbeddedTransaction` oneof where new revoke arm would be added.
- `SuperGenius/src/watcher/messaging_watcher` — existing message-bus pattern. Reference for the `AccountMessenger` query/response protocol for discovery polling (D-27).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **EscrowTransaction model** — stores `dev_addr_`, `peers_cut_`, `amount_` at construction time. `HoldEscrow` reads these from the current context (SDK config or reg/ record). `PayEscrow` reads from the stored escrow transaction, providing automatic hold-time pinning. Zero Phase 3 changes to EscrowTransaction needed.
- **RegistrationTx + RegistrationMetadata** (Phase 1 design) — already carries `dev_wallet` and `peers_cut`. Phase 3 only needs to add `detach_flag` and `supersedes_sequence` fields to the RegistrationTx message — additive proto change.
- **CheckParentChildAuthority gate** (Phase 2 D-19) — already slots into `ValidateTransactionForConsensus`. The revoke main-signed transaction uses this gate to validate: (1) main signature, (2) reg/ record's main_address matches signer, (3) reg/ record is in Registered state. No new gate needed — just a new path within the existing gate.
- **PubSubBroadcasterExt topic API** — already used for registration broadcast (D-15) and child state sync (D-17). Discovery polling via AccountMessenger reuses the same pubsub infrastructure with a query/response message type instead of a broadcast.
- **`sgns.nonce.v1` consensus subject** — RegistrationTx already flows through this (D-24). The revoke transaction would use the same subject (if it's a tx type) or a new subject if it's a different consensus path.

### Established Patterns
- **CRDT element filter pattern** — `FilterRegistration` (Phase 2 D-11/D-13) handles reg/ namespace. Phase 3 extends the filter to validate `supersedes_sequence` ordering: reject if the incoming tx's `supersedes_sequence` != current record's `sequence`.
- **Additive proto evolution** — new fields (detach_flag, supersedes_sequence) appended to RegistrationTx; new revoke tx message appended to SGTransaction.proto. No renumbering, no breaking changes.
- **Escrow immutability** — escrow transactions are created once and never modified. `PayEscrow` reads stored values, not live state. This pattern extends naturally to per-child reward policy: escrow pins at hold time, policy changes only affect future escrows.
- **RegistrationTx as state carrier** — the reg/ CRDT value IS the complete RegistrationTx (D-14). Lifecycle transitions (detach, replace main, update metadata) are all new RegistrationTx entries at higher sequence — the existing update-in-place CRDT merge handles them uniformly.

### Integration Points
- `TransactionManager::FilterRegistration` — extend to validate `supersedes_sequence` linkage and reject competing updates.
- `TransactionManager::ValidateTransactionForConsensus` — add revoke transaction path to `CheckParentChildAuthority` gate (main signature + reg/ match + state check).
- `SGTransaction.proto` — append `detach_flag` (bool), `supersedes_sequence` (uint64) to RegistrationTx; add new `RevokeTx` message if revoke is a first-class tx type.
- `Consensus.proto` `EmbeddedTransaction` oneof — add revoke arm if revoke is a new tx type.
- `GeniusNode::HoldEscrow` — add logic to read `dev_wallet`/`peers_cut` from certified reg/ record (if registered) falling back to `DevConfig_st` (if standalone). This is a Phase 3 integration: escrow construction reads the reward policy from the correct source.
- `watcher/messaging_watcher` — extend with child-discovery query/response message type for AccountMessenger polling (D-27).

### Critical Gap
- **No existing message-bus query/response protocol.** The current `messaging_watcher` handles broadcast-style messages. Discovery polling (D-27) requires a request/response pattern where the main asks "who are my children?" and any node can answer. This may need a new message type and handler — or it can be simpler: the main just listens on its own topic for responses after broadcasting the query. The researcher must determine the idiomatic way to add point-to-point or query-response messaging in the existing pubsub infrastructure.
</code_context>

<specifics>
## Specific Ideas

- **User's discovery model:** "Main wallet will know children through pubsub broadcasts, but there is a chance it may miss this. Wallet should occasionally poll on its channel, through AccountMessenger, 'what child wallets do I have'. A child wallet, or full node, or anyone that happens to know, can respond to this. The main wallet should probably keep this information in a JSON or something." This establishes the push-primary/poll-fallback architecture with decentralized responders and local caching.
- **User's design philosophy across all phases:** The child controls its own registration lifecycle — registration is child-signed-only, reward policy is child-updatable, main replacement is child-only, detach is child-initiated. The main's only authority actions are funding (main-signed) and revoking (main-signed). This is consistently applied: the child owns its identity; the main is a privileged observer with specific, bounded powers.
</specifics>

<deferred>
## Deferred Ideas

- **Platform "Connect GNUS Wallet" UI flows** — v2 (PLAT-01, PLAT-02). Phase 3 describes the protocol conceptually; concrete UI wiring is deferred.
- **Aggregated registry topic for publisher-scale child fan-out** — v2 (ADV-02). The discovery mechanism in D-27 supports many children per main, but an optimized aggregation layer for hundreds/thousands of children is a separate concern.
- **Threshold/social-recovery scheme for the main wallet** — v2 (ADV-01).
- **Optional main acceptance signature for registration** (pending→confirmed upgrade) — considered and rejected in Phase 1 (D-04/D-05); could be revisited as a v2 hardening layer if discovery-spam becomes a real problem.

</deferred>

---

*Phase: 3-Discovery, Rewards & Lifecycle*
*Context gathered: 2026-07-14*
