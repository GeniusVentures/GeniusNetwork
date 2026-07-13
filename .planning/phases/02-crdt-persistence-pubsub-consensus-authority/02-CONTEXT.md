# Phase 2: CRDT Persistence, PubSub & Consensus Authority - Context

**Gathered:** 2026-07-13
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase produces two design documents:
1. **CRDT registry namespace + pubsub broadcast/subscription** — how the RegistrationTx persists in consensus-visible CRDT state, how the child broadcasts to the main, and how the main subscribes to child channels for ongoing balance/asset sync (SYNC-01..05).
2. **Consensus parent-child authority rules** — the 6 spend rules: main→child fund, destination-restricted main-recover-from-child, child→arbitrary (existing), child→developer (existing normal transfer), child→main (existing), and the explicit child-cannot-spend-main rejection invariant (CONS-01..06). Plus the resolution of the CRDT eventual-consistency vs consensus-ordering tension.

Discovery/monitoring UI, reward policy, lifecycle state machine, and replace/detach/revoke change-flows are **out of scope** — they are Phase 3.
</domain>

<decisions>
## Implementation Decisions

### CRDT Namespace & Key Layout (SYNC-01, SYNC-02)
- **D-11:** RegistrationTx lives in a **`reg/` namespace only** — it does NOT get a `tx/` entry. A new `FilterRegistration` method on TransactionManager gates incoming reg/ deltas, parallel to the existing `FilterTransaction` for `tx/` and `FilterProof` for `proof/`. The element filter regex pattern is `^/?/bc-{net}/reg/([^/]+)`.
- **D-12:** CRDT key structure: **`reg/{child_addr}`** — a single CRDT element per child wallet, updated in-place on each valid registration event (higher sequence). This matches the validator registry pattern (single key = current state). History is derived from the chain of RegistrationTx entries in the account's nonce chain.
- **D-13:** The reg/ element filter rejects on: (a) deserialization failure, (b) invalid child signature, (c) sequence not strictly higher than the current record's sequence, (d) malformed record. It accepts otherwise — the CRDT merge handles the update. No cascade-delete of paired keys (unlike tx/→proof/) since reg/ has no paired namespace.
- **D-14:** The CRDT element **value** at `reg/{child_addr}` is the **full RegistrationTx protobuf** (including DAGStruct, signature, nonce, sequence, main_address, and optional metadata). Self-contained — no cross-referencing needed for independent verification.

### PubSub Channel Design (SYNC-03, SYNC-04, SYNC-05)
- **D-15:** Registration **broadcast**: the child publishes the RegistrationTx's **CID/hash** (IPLD CID or tx hash) on the **main wallet's address topic** via `AddBroadcastTopic(main_address)`, AND writes the RegistrationTx to its local CRDT under `reg/{child_addr}`. The CRDT DAG sync (graphsync/gossipsub) propagates it to all peers; the pubsub notification provides low-latency discovery.
- **D-16:** Main **discovery**: the pubsub notification on the main's topic triggers the main to call `AddListenTopic(child_address)`. The child address is extracted from the notification payload. No CRDT query is needed for initial discovery — pubsub IS the discovery trigger. However, authority is NEVER derived from topic membership (Pitfall 5); the main validates the registration against consensus-certified CRDT state before acting.
- **D-17:** Ongoing child **state sync**: the main subscribes to the child's address topic via `AddListenTopic(child_address)`. The child's node already broadcasts CRDT deltas on its own address topic. The main receives them and merges into its local CRDT.
- **D-18:** Pubsub notification **payload**: carries only the **RegistrationTx CID/hash** (content-addressed reference into the CRDT DAG), not the full RegistrationTx. The main resolves the CID to fetch the full record from CRDT. This avoids data duplication and forces CRDT validation before the main acts.

### Consensus Authority Integration (CONS-01..06)
- **D-19:** A new **`CheckParentChildAuthority`** gate slots into `ValidateTransactionForConsensus` between the existing signature check and replay-protection check. The extended pipeline: null → well-formed → signature → **parent-child authority** → timestamp → replay → tx-type-rules → approve. This gate only fires for transaction types that involve delegated authority (main→child, main-recover); ordinary child transfers pass through unmodified.
- **D-20:** **Rule dispatch** reuses the existing `"transfer"` tx type — no new tx types are needed. The gate deterministically checks: (1) who signed the tx? (2) Is there a `reg/` record linking the source and destination addresses? (3) If the main signed and a reg/ record exists linking the child to that main → authority applies. The direction (fund vs recover) is determined by whether src or dst is the main address.
  - **CONS-01 (main→child fund):** main signature + child registered to that main (reg/ lookup confirms relationship).
  - **CONS-03 (child→arbitrary):** already handled by existing child signature check — passes through.
  - **CONS-04 (child→developer):** a normal child-signed transfer — no special consensus rule. The existing `PayDev` path handles it.
- **D-21:** **Main-recover-from-child (CONS-02):** hard destination restriction — the gate rejects any main-signed transfer FROM a child address if `dst != main_address` (from the reg/ record). Recovery destination is locked to the registered main address by consensus rule, implementing Pitfall 3 protection (recovery ≠ seizure).
- **D-22:** **Child-cannot-spend-main (CONS-05):** already enforced by the existing `GeniusInputValidator::ValidateWitness` owner_address check — a child key does not own main UTXOs. The design documents this as an explicit invariant with a negative test spec: "no child-signed tx can spend main UTXOs — verified by existing owner_address != src_address rejection (GeniusInputValidator.cpp:421)." No new code path needed.
- **D-23:** **CONS-06 (hierarchical authority vs UTXO ownership):** the new `CheckParentChildAuthority` gate keeps delegated authority separate from UTXO ownership checks. The existing `ValidateWitness` owner_address path is unchanged (the escrow exception remains the sole deviation). Parent-child authority is an orthogonal layer above UTXO ownership.

### CRDT vs Consensus Ordering Resolution
- **D-24:** RegistrationTx flows through **full consensus** — the same `SubmitProposal → validator quorum → certificate` path as TransferTx. It reuses the existing **`sgns.nonce.v1`** consensus subject (no new subject type needed). The RegistrationTx's `DAGStruct.nonce` chains through the account's nonce sequence; the dedicated `sequence` field provides registration-specific lineage ordering within that chain.
- **D-25:** **Tie-break** for competing registrations: **first-to-consensus wins.** The nonce chain prevents two txs at the same nonce from both being certified. If two registrations with the same sequence but different nonces somehow arrive, the first to receive a consensus certificate at its nonce is authoritative. The reg/ filter then rejects any subsequent attempt with the same sequence (seq not strictly higher).
- **D-26:** The reg/ CRDT filter **accepts pre-certificate** (same pattern as tx/ — sig+seq+well-formed gates at the CRDT level). The RegistrationTx enters the local CRDT immediately. A separate **certified status/flag** marks whether consensus has confirmed it. The **main wallet only acts on certified registrations** — uncertified reg/ entries are optimistic storage, not authoritative state. This cleanly separates CRDT eventual-consistency (storage/sync) from consensus total-ordering (authority).

### the agent's Discretion
- Exact proto field numbers and the mechanical shape of the reg/ filter registration call in `TransactionManager` — planner/researcher choose the idiomatic form matching existing `tx/`/`proof/` filter patterns.
- Naming of the `FilterRegistration` method, `CheckParentChildAuthority` method, and their placement within the TransactionManager class — follow existing naming conventions.
- The certified status flag implementation (separate CRDT key, in-band field, or in-memory map) — planner selects the approach that matches existing certificate tracking patterns for `tx/` entries.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Authoritative spec
- `GNUS_Subwallet_Architecture_Proposal.md` — Phase-2-relevant sections: §Consensus Rules (all 6 rules), §Main-Wallet Registration (registration flow, record fields), §Security Model, §Wallet Discovery (main subscribes to child channels). NOTE: proposal §Registration Flow step 4 assumes main counter-signature; decision D-04/D-05 from Phase 1 supersedes this to child-signed-only.

### Planning docs
- `.planning/PROJECT.md` — locked decisions (independent keypair, consensus-enforced authority, CRDT persistence). Phase-2-relevant key decisions: "Registration recorded in consensus-visible CRDT state" and "Main wallet subscribes to child pubsub channels."
- `.planning/REQUIREMENTS.md` — SYNC-01..05, CONS-01..06. These are the 11 requirements this phase must satisfy.
- `.planning/ROADMAP.md` §Phase 2 — goal + 4 success criteria this context must satisfy.
- `.planning/phases/01-child-identity-registration-protocol/01-CONTEXT.md` — Phase 1 decisions carried forward: D-01 (emergent child-ness), D-02 (UTXO ownership via owner_address), D-03 (independent nonce), D-04/D-05 (child-signed-only registration), D-06 (first-class RegistrationTx), D-07 (CRDT layout = Phase 2 hand-off), D-08 (RegistrationTx schema), D-09 (nonce + sequence), D-10 (pubkey-delivery handshake).

### Research
- `.planning/research/SUMMARY.md` — stack/feature/architecture grounding (HIGH confidence). Phase 2 is flagged as "Deep research needed" for CRDT eventual-consistency vs consensus ordering.
- `.planning/research/PITFALLS.md` — Phase-2-relevant pitfalls: Pitfall 1 (replay/reorder — addressed by D-24/D-25/D-26 seq+consensus), Pitfall 3 (recovery-as-seizure — addressed by D-21 destination restriction), Pitfall 4 (child-spends-main — addressed by D-22 invariant + existing ownership check), Pitfall 5 (pubsub trust — addressed by D-16 validation-before-action).

### Code anchor points (audited, exist today)
- `SuperGenius/src/crdt/globaldb/globaldb.hpp` — CRDT element filter registration (`RegisterElementFilter` with regex pattern + callback), namespace/key conventions (`/bc-{net}/{type}/{hash}`).
- `SuperGenius/src/crdt/globaldb/pubsub_broadcaster_ext.hpp` — `AddListenTopic`/`AddBroadcastTopic`/`AddTopicName` — the pubsub channel API.
- `SuperGenius/src/account/TransactionManager.hpp` + `.cpp` — `FilterTransaction` (pattern for `FilterRegistration`), `CheckTransactionAuthorization` (signature-only today — extended by new `CheckParentChildAuthority` gate), `ValidateTransactionForConsensus` (7-gate pipeline where new gate slots), `transaction_parsers` map (where RegistrationTx's parser registers).
- `SuperGenius/src/account/GeniusInputValidator.hpp` + `.cpp` — `ValidateUTXOParameters`, `ValidateWitness` (owner_address check + escrow exception — the existing pattern for delegated authority when src ≠ owner).
- `SuperGenius/src/account/proto/SGTransaction.proto` — where RegistrationTx was added in Phase 1.
- `SuperGenius/src/blockchain/Consensus.hpp` — `sgns.nonce.v1` subject type that RegistrationTx reuses (D-24).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **CRDT element filter system** — `RegisterElementFilter(regex, callback)` with nullopt=accept/empty-vector=reject/non-empty=cascade-tombstone semantics. `FilterRegistration` follows the identical pattern as `FilterTransaction` (deserialize → check sig → check condition → accept/reject).
- **PubSubBroadcasterExt topic API** — `AddListenTopic(child_address)` for main→child subscription, `AddBroadcastTopic(main_address)` for child→main notification. Both are already used by TransactionManager for its own address topic.
- **`sgns.nonce.v1` consensus subject** — RegistrationTx reuses the existing nonce-chain subject (no new subject handler to register). The `SubmitProposal → quorum → certificate` path is already built.
- **`ValidateTransactionForConsensus` pipeline** — the new `CheckParentChildAuthority` gate slots between existing steps; no restructuring needed.

### Established Patterns
- **`/bc-{net}/{type}/{identifier}` key convention** — `tr_/` extends this with `reg/{child_addr}` using the same base and separator conventions.
- **FilterTransaction as filter template** — the existing `FilterTransaction` method (deserialize, signature check, key-collision check, cascade-delete proof) is the exact pattern for `FilterRegistration`.
- **`transaction_parsers` map** — RegistrationTx registers its parser here (Phase 1 hand-off), giving it `CheckTransactionWellFormed` validation for free.
- **Authorization today is purely cryptographic** — there is NO hierarchical authority. `CheckParentChildAuthority` is the first non-cryptographic authority gate. It reads from CRDT state (reg/ records) rather than checking signatures.
- **Escrow exception in ValidateWitness** — the only place where `src_address != owner_address` is allowed today. The new parent-child authority is orthogonal — it authorizes the main to act ON a child's UTXOs, not the child to act as the main.

### Integration Points
- `TransactionManager::FilterTransaction` registration block (lines ~187-213) — add `FilterRegistration` callback for `^/?/bc-{net}/reg/` pattern.
- `TransactionManager::ValidateTransactionForConsensus` (lines ~4234-4304) — insert `CheckParentChildAuthority` between `CheckTransactionAuthorization` and `CheckTransactionTimestamp`.
- `TransactionManager::SendTransactionItem` — RegistrationTx follows the same `write CRDT → SubmitProposal` path as TransferTx.
- `GlobalDB::RegisterElementFilter` — register the reg/ filter alongside existing tx/ and proof/ filters.
- `PubSubBroadcasterExt` — the child calls `AddBroadcastTopic(main_address)` for notification; the main calls `AddListenTopic(child_address)` for state sync.
- Consensus subject `sgns.nonce.v1` — RegistrationTx participates in the existing nonce chain; no new SubjectHandler needed.

### Critical Gap
- **No hierarchical authority exists today.** `CheckTransactionAuthorization` is signature-only. `CheckParentChildAuthority` is the first state-dependent authority check in the pipeline — it must read from CRDT (`reg/{child_addr}`) during consensus validation. This introduces a new dependency: consensus validation → CRDT state read. The design document must specify how the gate accesses the reg/ record efficiently during validation (cached lookup vs direct CRDT query).
</code_context>

<specifics>
## Specific Ideas

- **User's framing of the reg/ → consensus → authority flow:** "RegistrationTx goes through full consensus like txs. The reg/ CRDT record is only authoritative after a consensus certificate. Main wallet only acts on certified records." This establishes the two-tier model: CRDT stores optimistically, consensus certifies authoritatively.
- **Existing PayDev pattern:** the user confirmed that `GeniusNode::PayDev` (existing transfer-to-developer) handles child→developer payments — no new consensus rule needed for CONS-04. The developer wallet address comes from `DevConfig_st` (existing), not from the reg/ record metadata.
- **Reuse of transfer type:** parent-child authority transactions (main→child fund, main-recover-from-child) are ordinary `"transfer"` tx type — the authority gate determines whether they're allowed, not the tx type string.
</specifics>

<deferred>
## Deferred Ideas

- **Main-replacement policy fork** (require existing-main consent vs child-only) — Phase 3 (LIFE-03).
- **Lifecycle state machine + replace/detach/revoke/close change-flows** ("supersedes seq N" mechanics) — Phase 3 (LIFE-01..04).
- **Main-wallet discovery/monitoring display** (per-child balance, assets, game, publisher, dev wallet, cut ratio, activity, status) — Phase 3 (DISC-01..03).
- **Per-child processing-reward policy** (dev_addr/peers_cut resolution, hold-time pinning, authenticated update rules) — Phase 3 (RWD-01..03).
- **Platform "Connect GNUS Wallet" UI flows** — v2 (PLAT-01, PLAT-02).
- **Cross-application shared child keys** — anti-feature, explicitly excluded.
- **Aggregated registry topic** for publisher-scale child fan-out — v2 (ADV-02).

</deferred>

---

*Phase: 2-CRDT Persistence, PubSub & Consensus Authority*
*Context gathered: 2026-07-13*
