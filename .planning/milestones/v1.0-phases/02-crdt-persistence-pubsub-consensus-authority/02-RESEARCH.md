# Phase 2: CRDT Persistence, PubSub & Consensus Authority - Research

**Researched:** 2026-07-13
**Domain:** CRDT state persistence, libp2p pubsub messaging, and consensus-enforced parent-child authority on a C++17 UTXO blockchain node
**Confidence:** HIGH

## Summary

Phase 2 produces two design documents: (1) the CRDT registry namespace/key layout with pubsub broadcast/subscription for registration discovery and child-state sync, and (2) the six consensus parent-child authority rules with resolution of the CRDT eventual-consistency vs consensus-ordering tension. The phase is purely a **design-documentation milestone** — no implementation, no new packages, no new external dependencies.

The central insight is that `RegistrationTx` **already flows through full consensus** (D-24: `sgns.nonce.v1` subject, same `SubmitProposal → quorum → certificate` path as `TransferTx`). The design work is:

1. **CRDT persistence**: A new `reg/` namespace in the existing CRDT element filter system (`GlobalDB::RegisterElementFilter`) that validates and persists registration records in consensus-visible state — structurally identical to the existing `tx/` filter pattern but simpler (single-key per child, no paired namespace like `tx/`→`proof/`).

2. **PubSub**: The child broadcasts the `RegistrationTx` CID on the main's address topic (`AddBroadcastTopic(main_address)`) for low-latency discovery; the main subscribes to child address topics (`AddListenTopic(child_address)`) for ongoing CRDT state sync. Authority is always derived from signatures+consensus, never from topic membership (Pitfall 5).

3. **Consensus Authority**: A new `CheckParentChildAuthority` gate slots into `ValidateTransactionForConsensus` between the existing signature and timestamp checks. It reads from CRDT (`reg/{child_addr}`) to determine parent-child relationships and applies the six rules (CONS-01..06). This is the **first state-dependent authority check** — all prior authorization is purely cryptographic.

4. **CRDT vs Consensus Ordering**: The `reg/` CRDT filter accepts pre-certificate (optimistic storage), but a **certified status flag** distinguishes consensus-confirmed records. The main wallet **only acts on certified registrations**. This cleanly separates CRDT eventual consistency (storage/sync) from consensus total-ordering (authority).

**Primary recommendation:** Register a `FilterRegistration` callback on `^/?/bc-{net}/reg/([^/]+)` in the `TransactionManager::New` factory alongside existing `FilterTransaction`/`FilterProof`. Add `CheckParentChildAuthority` as a new public method on `TransactionManager` that reads `reg/{child_addr}` from CRDT and applies the six deterministic rules. Use the certified-status flag pattern (separate CRDT key or in-band field) to distinguish optimistic from authoritative registration state.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### CRDT Namespace & Key Layout (SYNC-01, SYNC-02)
- **D-11:** RegistrationTx lives in a **`reg/` namespace only** — it does NOT get a `tx/` entry. A new `FilterRegistration` method on TransactionManager gates incoming reg/ deltas, parallel to the existing `FilterTransaction` for `tx/` and `FilterProof` for `proof/`. The element filter regex pattern is `^/?/bc-{net}/reg/([^/]+)`.
- **D-12:** CRDT key structure: **`reg/{child_addr}`** — a single CRDT element per child wallet, updated in-place on each valid registration event (higher sequence). This matches the validator registry pattern (single key = current state). History is derived from the chain of RegistrationTx entries in the account's nonce chain.
- **D-13:** The reg/ element filter rejects on: (a) deserialization failure, (b) invalid child signature, (c) sequence not strictly higher than the current record's sequence, (d) malformed record. It accepts otherwise — the CRDT merge handles the update. No cascade-delete of paired keys (unlike tx/→proof/) since reg/ has no paired namespace.
- **D-14:** The CRDT element **value** at `reg/{child_addr}` is the **full RegistrationTx protobuf** (including DAGStruct, signature, nonce, sequence, main_address, and optional metadata). Self-contained — no cross-referencing needed for independent verification.

#### PubSub Channel Design (SYNC-03, SYNC-04, SYNC-05)
- **D-15:** Registration **broadcast**: the child publishes the RegistrationTx's **CID/hash** (IPLD CID or tx hash) on the **main wallet's address topic** via `AddBroadcastTopic(main_address)`, AND writes the RegistrationTx to its local CRDT under `reg/{child_addr}`. The CRDT DAG sync (graphsync/gossipsub) propagates it to all peers; the pubsub notification provides low-latency discovery.
- **D-16:** Main **discovery**: the pubsub notification on the main's topic triggers the main to call `AddListenTopic(child_address)`. The child address is extracted from the notification payload. No CRDT query is needed for initial discovery — pubsub IS the discovery trigger. However, authority is NEVER derived from topic membership (Pitfall 5); the main validates the registration against consensus-certified CRDT state before acting.
- **D-17:** Ongoing child **state sync**: the main subscribes to the child's address topic via `AddListenTopic(child_address)`. The child's node already broadcasts CRDT deltas on its own address topic. The main receives them and merges into its local CRDT.
- **D-18:** Pubsub notification **payload**: carries only the **RegistrationTx CID/hash** (content-addressed reference into the CRDT DAG), not the full RegistrationTx. The main resolves the CID to fetch the full record from CRDT. This avoids data duplication and forces CRDT validation before the main acts.

#### Consensus Authority Integration (CONS-01..06)
- **D-19:** A new **`CheckParentChildAuthority`** gate slots into `ValidateTransactionForConsensus` between the existing signature check and replay-protection check. The extended pipeline: null → well-formed → signature → **parent-child authority** → timestamp → replay → tx-type-rules → approve. This gate only fires for transaction types that involve delegated authority (main→child, main-recover); ordinary child transfers pass through unmodified.
- **D-20:** **Rule dispatch** reuses the existing `"transfer"` tx type — no new tx types are needed. The gate deterministically checks: (1) who signed the tx? (2) Is there a `reg/` record linking the source and destination addresses? (3) If the main signed and a reg/ record exists linking the child to that main → authority applies. The direction (fund vs recover) is determined by whether src or dst is the main address.
  - **CONS-01 (main→child fund):** main signature + child registered to that main (reg/ lookup confirms relationship).
  - **CONS-03 (child→arbitrary):** already handled by existing child signature check — passes through.
  - **CONS-04 (child→developer):** a normal child-signed transfer — no special consensus rule. The existing `PayDev` path handles it.
- **D-21:** **Main-recover-from-child (CONS-02):** hard destination restriction — the gate rejects any main-signed transfer FROM a child address if `dst != main_address` (from the reg/ record). Recovery destination is locked to the registered main address by consensus rule, implementing Pitfall 3 protection (recovery ≠ seizure).
- **D-22:** **Child-cannot-spend-main (CONS-05):** already enforced by the existing `GeniusInputValidator::ValidateWitness` owner_address check — a child key does not own main UTXOs. The design documents this as an explicit invariant with a negative test spec: "no child-signed tx can spend main UTXOs — verified by existing owner_address != src_address rejection (GeniusInputValidator.cpp:421)." No new code path needed.
- **D-23:** **CONS-06 (hierarchical authority vs UTXO ownership):** the new `CheckParentChildAuthority` gate keeps delegated authority separate from UTXO ownership checks. The existing `ValidateWitness` owner_address path is unchanged (the escrow exception remains the sole deviation). Parent-child authority is an orthogonal layer above UTXO ownership.

#### CRDT vs Consensus Ordering Resolution
- **D-24:** RegistrationTx flows through **full consensus** — the same `SubmitProposal → validator quorum → certificate` path as TransferTx. It reuses the existing **`sgns.nonce.v1`** consensus subject (no new subject type needed). The RegistrationTx's `DAGStruct.nonce` chains through the account's nonce sequence; the dedicated `sequence` field provides registration-specific lineage ordering within that chain.
- **D-25:** **Tie-break** for competing registrations: **first-to-consensus wins.** The nonce chain prevents two txs at the same nonce from both being certified. If two registrations with the same sequence but different nonces somehow arrive, the first to receive a consensus certificate at its nonce is authoritative. The reg/ filter then rejects any subsequent attempt with the same sequence (seq not strictly higher).
- **D-26:** The reg/ CRDT filter **accepts pre-certificate** (same pattern as tx/ — sig+seq+well-formed gates at the CRDT level). The RegistrationTx enters the local CRDT immediately. A separate **certified status/flag** marks whether consensus has confirmed it. The **main wallet only acts on certified registrations** — uncertified reg/ entries are optimistic storage, not authoritative state. This cleanly separates CRDT eventual-consistency (storage/sync) from consensus total-ordering (authority).

### Agent's Discretion

- Exact proto field numbers and the mechanical shape of the reg/ filter registration call in `TransactionManager` — planner/researcher choose the idiomatic form matching existing `tx/`/`proof/` filter patterns.
- Naming of the `FilterRegistration` method, `CheckParentChildAuthority` method, and their placement within the TransactionManager class — follow existing naming conventions.
- The certified status flag implementation (separate CRDT key, in-band field, or in-memory map) — planner selects the approach that matches existing certificate tracking patterns for `tx/` entries.

### Deferred Ideas (OUT OF SCOPE)

- Main-replacement policy fork (require existing-main consent vs child-only) — Phase 3 (LIFE-03).
- Lifecycle state machine + replace/detach/revoke/close change-flows ("supersedes seq N" mechanics) — Phase 3 (LIFE-01..04).
- Main-wallet discovery/monitoring display (per-child balance, assets, game, publisher, dev wallet, cut ratio, activity, status) — Phase 3 (DISC-01..03).
- Per-child processing-reward policy (dev_addr/peers_cut resolution, hold-time pinning, authenticated update rules) — Phase 3 (RWD-01..03).
- Platform "Connect GNUS Wallet" UI flows — v2 (PLAT-01, PLAT-02).
- Cross-application shared child keys — anti-feature, explicitly excluded.
- Aggregated registry topic for publisher-scale child fan-out — v2 (ADV-02).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SYNC-01 | CRDT namespace/key layout for registration record in `globaldb` | Verified: D-11/D-12 specify `reg/{child_addr}` single-key layout with regex `^/?/bc-{net}/reg/([^/]+)`. Existing `tx/` filter registered at line 191, `proof/` at line 203 of `TransactionManager.cpp`. New `reg/` filter follows identical `RegisterElementFilter` invocation pattern. CRDT key format is `/bc-{network_id}/reg/{child_addr}` derived from `GetBlockChainBase()` (line 1356) + `"reg/" + child_addr`. |
| SYNC-02 | CRDT element filter validates and persists registration deltas in `TransactionManager` | Verified: `FilterTransaction` (line 2984) provides the template: deserialize → signature check → accept/reject. `FilterRegistration` follows same pattern with sequence validation added. Return semantics: `std::nullopt` = accept, non-empty vector = tombstone (reject). D-13 specifies rejection gates: (a) deserialization failure, (b) invalid child sig, (c) sequence not strictly higher, (d) malformed record. No cascade-delete (reg/ has no paired namespace unlike tx/→proof/). |
| SYNC-03 | Registration broadcast on main wallet's pubsub channel via `PubSubBroadcasterExt` | Verified: D-15 specifies child calls `AddBroadcastTopic(main_address)` to publish RegistrationTx CID on main's address topic. Existing pattern: `TransactionManager::StartListeningTopics` (line 355) calls `globaldb_m->AddListenTopic(account_m->GetAddress())` for own address. D-18 constrains payload to CID/hash only. The child's CRDT write triggers DAG sync (graphsync propagation); pubsub notification is discovery shortcut. |
| SYNC-04 | Main wallet subscribes to child pubsub channels and syncs CRDT for balances without child private key | Verified: D-16 specifies pubsub notification triggers `AddListenTopic(child_address)`. Existing pattern: `AddListenTopic(processing_channel_topic_)` called in `GeniusNode.cpp:586`. D-17 specifies ongoing sync — child's node already broadcasts CRDT deltas on own address topic; main receives and merges locally. No private key needed for read-only sync. |
| SYNC-05 | Authority derived from signatures+consensus, not from pubsub topic membership | Verified: D-16 explicitly states this constraint. Pitfall 5 documented in research/PITFALLS.md. The validation flow is: pubsub notification → CID resolution → CRDT fetch → consensus certificate check → authority gate. Topic membership gates nothing — all authority derives from cryptographic signatures validated by consensus. |
| CONS-01 | Main→child funding rule (main signature + child registered to that main) | Verified: D-20 specifies rule dispatch: check who signed (main), check reg/ record links child to that main, allow if both match. Uses existing `"transfer"` tx type — no new tx type. The `CheckParentChildAuthority` gate reads `reg/{child_addr}` from CRDT to verify the relationship exists and is certified. |
| CONS-02 | Main-recover-from-child with destination restricted to registered main address | Verified: D-21 specifies hard destination restriction: `dst != main_address` → reject. The gate identifies a recovery transaction by (a) main signature, (b) src = child address from reg/ record. Recovery destination locked to registered main — implements Pitfall 3 protection. Uses existing `"transfer"` tx type. |
| CONS-03 | Child→arbitrary-address and child→main transfer rules | Verified: D-20 specifies these pass through `CheckParentChildAuthority` unmodified. Existing child signature check in `CheckTransactionAuthorization` (line 4361) handles authorization. UTXO ownership verified by `GeniusInputValidator::ValidateWitness`. No new rules needed. |
| CONS-04 | Child→registered-developer-wallet payment rule | Verified: D-20 specifies no special consensus rule. The existing `PayDev` path handles child→developer payments. Developer wallet address comes from `DevConfig_st` (existing), not from reg/ metadata. Child signature is sufficient authorization. |
| CONS-05 | Explicit rejection: child key cannot authorize spending main-wallet funds | Verified: D-22 specifies this is already enforced by existing `ValidateWitness` owner_address check (GeniusInputValidator.cpp:421-431). The `delegated_escrow_spend` exception (line 421) is the only place `payload_owner != src_address` is allowed. Design doc documents this as invariant + negative test spec. No new code needed. |
| CONS-06 | Hierarchical authority layer in `CheckTransactionAuthorization` without conflating with UTXO ownership | Verified: D-23 specifies orthogonal design. `CheckParentChildAuthority` is a separate gate (not modifying `CheckTransactionAuthorization`). The existing `ValidateWitness` owner_address path is unchanged. Delegated authority authorizes the main to act ON a child's UTXOs; does NOT authorize a child to act AS the main. |

</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| CRDT element filter registration (reg/) | API / Backend | Database / Storage | `GlobalDB::RegisterElementFilter` executed in `TransactionManager::New`; filter stores data in RocksDB-backed CRDT datastore |
| Registration record persistence (reg/{child_addr}) | Database / Storage | API / Backend | `GlobalDB::Put` writes to RocksDB via CRDT datastore layer; CRDT DAG sync propagates via IPFS graphsync |
| Registration sequence validation (seq strictly higher) | API / Backend | Database / Storage | `FilterRegistration` reads current record from CRDT, validates sequence; filter runs in CRDT intake path |
| Certified status tracking | API / Backend | Database / Storage | Status flag must be accessible during `CheckParentChildAuthority` — either in-band field in CRDT value, separate CRDT key, or `OnConsensusCertificate` callback path |
| PubSub broadcast (child→main notification) | API / Backend | — | `PubSubBroadcasterExt::AddBroadcastTopic(main_address)` called from child's `TransactionManager` |
| PubSub subscription (main→child sync) | API / Backend | — | `PubSubBroadcasterExt::AddListenTopic(child_address)` called from main's `TransactionManager` upon registration discovery |
| Parent-child authority gate (CheckParentChildAuthority) | API / Backend | — | Runs in `ValidateTransactionForConsensus` pipeline during consensus validation; reads reg/ CRDT state |
| Main→child fund authorization | API / Backend | Database / Storage | Gate checks main signature + reg/ record; uses existing `"transfer"` tx type |
| Main-recover-from-child (destination-restricted) | API / Backend | Database / Storage | Gate checks main signature + reg/ record + dst == main_address; enforces Pitfall 3 |
| Child-cannot-spend-main rejection | API / Backend | — | Existing `ValidateWitness` owner_address check; documented as invariant, no new code |
| CRDT eventual-consistency vs consensus ordering resolution | API / Backend | Database / Storage | Certified status flag separates optimistic CRDT storage from authoritative consensus state; nonce chain prevents double-certification |

## Standard Stack

> This is a **design-documentation phase.** No new packages, libraries, or dependencies are installed. All technologies are in the existing SuperGenius stack. The "stack" here is the set of existing components the design documents must reference and integrate with.

### Core (Existing — What the Design Maps To)

| Component | Version / Location | Purpose in Phase 2 | Confidence |
|-----------|-------------------|-------------------|------------|
| GlobalDB | `SuperGenius/src/crdt/globaldb/globaldb.hpp` | Element filter registration (`RegisterElementFilter`), key-value storage (`Put`/`Get`), pubsub topic management (`AddBroadcastTopic`/`AddListenTopic`/`AddTopicName`) | HIGH [VERIFIED: code audit this session] |
| PubSubBroadcasterExt | `SuperGenius/src/crdt/globaldb/pubsub_broadcaster_ext.hpp` | Topic-based PubSub messaging over libp2p GossipSub — `Broadcast`, `AddListenTopic`, `AddBroadcastTopic` | HIGH [VERIFIED: code audit this session] |
| CRDT DataStore / CrdtDatastore | `SuperGenius/src/crdt/crdt_datastore.hpp` | Delta-based CRDT storage with element filter callbacks (`CRDTElementFilterCallback` = `std::function<std::optional<std::vector<pb::Element>>(const pb::Element&)>`) | HIGH [VERIFIED: code audit this session] |
| TransactionManager | `SuperGenius/src/account/TransactionManager.cpp` | `ValidateTransactionForConsensus` (7-gate pipeline), `CheckTransactionAuthorization`, `CheckTransactionTypeRules`, `HandleNonceConsensusSubject`, `SendTransactionItem`, `FilterTransaction`/`FilterProof` (filter templates), `transaction_parsers` map | HIGH [VERIFIED: code audit this session] |
| ConsensusManager | `SuperGenius/src/blockchain/Consensus.hpp` | `sgns.nonce.v1` subject type, `SubmitProposal`, `RegisterSubjectHandler`, `RegisterCertificateHandler`, `CreateNonceSubject`, `DecodeNonceSubject` | HIGH [VERIFIED: code audit this session] |
| GeniusInputValidator | `SuperGenius/src/account/GeniusInputValidator.cpp` | `ValidateWitness` (owner_address check + escrow exception at line 421), `ValidateUTXOParameters` | HIGH [VERIFIED: code audit this session] |
| GeniusTransaction | `SuperGenius/src/account/GeniusTransaction.hpp` | Base class for `RegistrationTx` — `GetHash()`, `GetSrcAddress()`, `GetNonce()`, `CheckSignature()`, `SerializeToEmbeddedTransaction()`, `GetTransactionFullPath()` returns `"tx/" + hash` | HIGH [VERIFIED: code audit this session] |
| RegistrationTx | Phase 1 design (`docs/registration-protocol.md`) | Proto message with `dag_struct` (field 1), `main_address` (2), `sequence` (3), `RegistrationMetadata` (4). New `GeniusTransaction` subclass. | HIGH [CITED: docs/registration-protocol.md — Phase 1 output] |
| SGTransaction.proto | `SuperGenius/src/account/proto/SGTransaction.proto` | Proto definitions for `DAGStruct`, all tx variants. RegistrationTx appended additively in Phase 1. | HIGH [VERIFIED: this session] |
| Consensus.proto | `SuperGenius/src/blockchain/impl/proto/Consensus.proto` | `EmbeddedTransaction` oneof (RegistrationTx gets field 8), `NonceSubject`, `ConsensusSubject`, `ConsensusCertificate` | HIGH [VERIFIED: this session] |
| HierarchicalKey | `SuperGenius/src/crdt/hierarchical_key.hpp` | CRDT key type — `SetKey(string)`, `GetKey()` returns the key string. Keys follow `/bc-{net}/{type}/{id}` convention | HIGH [VERIFIED: code audit this session] |

### Supporting (Pattern Reference)

| Pattern | Location | Purpose | When Referenced |
|---------|----------|---------|-----------------|
| FilterTransaction | `TransactionManager.cpp:2984` | Template for `FilterRegistration`: deserialize → sig check → key-collision check → accept/reject | Exact structural pattern for reg/ filter |
| FilterProof | `TransactionManager.cpp:3041` | Template for no-paired-namespace filter (proof/ accepts standalone; reg/ is similar) | Parallel filter registration pattern |
| CRDT filter registration | `TransactionManager.cpp:187-213` | `RegisterElementFilter(regex, lambda)` — `tx/` from line 191, `proof/` from line 203 | Add `reg/` filter inline at this block |
| SendTransactionItem | `TransactionManager.cpp:1127` | Write CRDT → `Commit(topicSet)` → `CreateConsensusProposal` → `SubmitProposal` | RegistrationTx follows identical path |
| HandleNonceConsensusSubject | `TransactionManager.cpp:3901` | Deserialize → hash binding → nonce match → account match → witness validation → `ValidateTransactionForConsensus` | Called via registered `sgns.nonce.v1` subject handler |
| OnConsensusCertificate | `TransactionManager.cpp:3768` | Certificate handler callback — `ChangeTransactionState(tx, CONFIRMED)`. Pattern for marking reg/ entries as certified. | Template for certified-status flag update |
| GetBlockChainBase | `TransactionManager.cpp:1356-1368` | Returns `/bc-{network_id}/` key prefix. Used to construct CRDT key paths. | reg/ key construction: `GetBlockChainBase(net) + "reg/" + child_addr` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| reg/ CRDT namespace (single-key per child) | Store RegistrationTx in `tx/` namespace alongside normal transactions | Would require RegistrationTx to carry UTXO parameters → bloated tx that mutates no UTXOs. D-11 specifically forbids this. |
| In-line registration authority check (modify `CheckTransactionAuthorization`) | Separate `CheckParentChildAuthority` gate | D-19/D-23 specify separate gate for separation of concerns; modifying `CheckTransactionAuthorization` would conflate cryptographic auth with state-dependent auth |
| New consensus subject type for RegistrationTx | Reuse `sgns.nonce.v1` | D-24 selects reuse — new subject type would require new handler, new slot-key handler, new certificate handler. Reuse is lower-risk and passes through existing validation pipeline. |
| Full RegistrationTx in pubsub notification payload | CID/hash only | D-18 selects CID-only — avoids data duplication in pubsub layer, forces CRDT resolution, enables content-addressed verification. |

### Installation

No packages to install. This is a design-documentation phase using the existing C++ codebase.

## Package Legitimacy Audit

> Not applicable — this phase installs no external packages. The phase produces design documents referencing the existing SuperGenius C++ codebase only.

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            PHASE 2: Data Flow                                    │
│                                                                                  │
│  ┌──────────────┐                                       ┌──────────────┐         │
│  │ CHILD NODE   │                                       │ MAIN NODE    │         │
│  │ (game/app)   │                                       │ (wallet)     │         │
│  └──────┬───────┘                                       └──────┬───────┘         │
│         │                                                      │                 │
│         │ 1. Create RegistrationTx                              │                 │
│         │    (child-signed, sequence N)                         │                 │
│         │                                                      │                 │
│         │ 2. SendTransactionItem:                               │                 │
│         │    ┌─────────────────────────┐                       │                 │
│         │    │ Write CRDT:             │                       │                 │
│         │    │ key=/bc-963/reg/        │                       │                 │
│         │    │     {child_addr}        │                       │                 │
│         │    │ value=RegistrationTx    │                       │                 │
│         │    │    protobuf             │                       │                 │
│         │    │ topic=child_addr,       │                       │                 │
│         │    │   full_node_topic       │                       │                 │
│         │    └────────┬────────────────┘                       │                 │
│         │             │                                        │                 │
│         │    ┌────────▼────────────────┐                       │                 │
│         │    │ SubmitProposal(         │                       │                 │
│         │    │   nonce subject,        │                       │                 │
│         │    │   sgns.nonce.v1)        │                       │                 │
│         │    └────────┬────────────────┘                       │                 │
│         │             │                                        │                 │
│         │ 3. PubSub broadcast:                                 │                 │
│         │    AddBroadcastTopic(         │                       │                 │
│         │      main_address)           │                       │                 │
│         │    → publish CID on           │                       │                 │
│         │      main's topic             │    ┌─────────┐       │                 │
│         │             │                 └───►│  PubSub  │───────┼────────►        │
│         │             │                      │  Network │       │ 4. Receive      │
│         │             │                      └─────────┘       │    CID on       │
│         │             │                                        │    own topic    │
│         │             │                                        │                 │
│         │             │                                        │ 5. CID →        │
│         │             │                                        │    CRDT resolve │
│         │             │                                        │    (fetch full  │
│         │             │                                        │     Registration│
│         │             │                                        │     Tx)         │
│         │             │                                        │                 │
│         │             │                                        │ 6. Validate:    │
│         │             │                                        │    registration │
│         │             │                                        │    certified by │
│         │             │                                        │    consensus?   │
│         │             │                                        │         │       │
│         │             │                                        │    ┌────▼────┐  │
│         │             │                                        │    │  YES    │  │
│         │             │                                        │    └────┬────┘  │
│         │             │                                        │         │       │
│         │             │                                        │ 7. AddListen-  │
│         │             │                                        │    Topic(      │
│         │             │    ┌─────────┐                         │    child_addr)  │
│         │ 9. Receive  │◄───│  PubSub  │◄────────────────────────│                 │
│         │    CRDT deltas   │  Network │    8. Child broadcasts  │                 │
│         │    from main     └─────────┘    CRDT deltas on own    │                 │
│         │                                address topic         │                 │
│         │             │                                        │                 │
│         ▼             │                                        │                 │
│  ┌──────────────┐     │                                        │                 │
│  │ CRDT MERGE   │     │                                        │    ┌─────────┐ │
│  │ (sync both   │     │                                        │    │ MAIN UI │ │
│  │  directions) │     │                                        │    │ (Phase3)│ │
│  └──────────────┘     │                                        │    └─────────┘ │
│                       │                                        │                 │
└───────────────────────┼────────────────────────────────────────┼─────────────────┘
                        │                                        │
                        │         CONSENSUS LAYER                 │
                        │    (validators, quorum, certificate)    │
                        │                                        │
                        │  HandleNonceConsensusSubject            │
                        │    → ValidateWitnessForConsensus        │
                        │    → ValidateTransactionForConsensus    │
                        │       → CheckTransactionWellFormed      │
                        │       → CheckTransactionAuthorization   │
                        │       → ★ CheckParentChildAuthority  ★  │
                        │       → CheckTransactionTimestamp       │
                        │       → EvaluateTransactionReplayProtection│
                        │       → CheckTransactionTypeRules       │
                        │    → OnConsensusCertificate             │
                        │       → Mark reg/{child_addr} certified │
                        └────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────────┐
│              CRDT Namespace Layout & Filter Architecture                         │
│                                                                                  │
│  CRDT Key: /bc-{network_id}/reg/{child_addr}                                    │
│  CRDT Value: RegistrationTx protobuf (DAGStruct + main_address + sequence        │
│              + RegistrationMetadata)                                             │
│                                                                                  │
│  Element Filter Regex: ^/?/bc-{net}/reg/([^/]+)                                  │
│  Filter Registration: TransactionManager::New(), alongside tx/ and proof/        │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐            │
│  │ FilterRegistration(element) → std::optional<vector<Element>>     │            │
│  │                                                                  │            │
│  │  1. Deserialize element.value() → RegistrationTx                 │            │
│  │     │ FAIL → return {{tombstone}}                                │            │
│  │                                                                  │            │
│  │  2. Validate child signature (tx.CheckSignature())               │            │
│  │     │ FAIL → return {{tombstone}}                                │            │
│  │                                                                  │            │
│  │  3. Check current record exists?                                 │            │
│  │     │ YES → deserialize current record                           │            │
│  │     │       └─ new_tx.sequence > current.sequence?               │            │
│  │     │           NO → return {{tombstone}}                        │            │
│  │     │ NO → accept (first registration)                           │            │
│  │                                                                  │            │
│  │  4. Well-formed check (main_address valid, etc.)                 │            │
│  │     │ FAIL → return {{tombstone}}                                │            │
│  │                                                                  │            │
│  │  5. return std::nullopt  (ACCEPT)                                │            │
│  │                                                                  │            │
│  │  Note: No cascade-delete — reg/ has no paired namespace.         │            │
│  └─────────────────────────────────────────────────────────────────┘            │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐            │
│  │ Certified Status Decision Matrix (D-26)                          │            │
│  │                                                                  │            │
│  │  Option A: Separate CRDT key /bc-{net}/reg-cert/{child_addr}    │            │
│  │    value = certificate CID; needs cleanup on detach              │            │
│  │                                                                  │            │
│  │  Option B: In-band field in RegistrationTx value                 │            │
│  │    "certified = true" flag in a new proto field                  │            │
│  │    requires re-serialization on certificate                     │            │
│  │                                                                  │            │
│  │  Option C: In-memory map keyed by child_addr                    │            │
│  │    populated by OnConsensusCertificate callback                  │            │
│  │    matches existing tx confirmed-status tracking pattern         │            │
│  │    lost on restart — must rebuild from CRDT certificates         │            │
│  └─────────────────────────────────────────────────────────────────┘            │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

```
SuperGenius/src/account/
├── TransactionManager.hpp              # +CheckParentChildAuthority decl
├── TransactionManager.cpp              # +FilterRegistration impl (new method)
│                                       # +CheckParentChildAuthority impl (new method)
│                                       # +FilterRegistration registered in New()
│                                       # +CheckParentChildAuthority called in
│                                       #    ValidateTransactionForConsensus
├── GeniusInputValidator.cpp            # (unchanged — CON-05 documented as invariant)
└── proto/
    └── SGTransaction.proto             # RegistrationTx already added in Phase 1
```

### Pattern 1: CRDT Element Filter Registration (reg/ namespace)

**What:** Register a `FilterRegistration` callback on the `reg/` key pattern in `TransactionManager::New`, structurally identical to the existing `FilterTransaction`/`FilterProof` registration block.

**When to use:** This is the canonical integration point. All three filters (`tx/`, `proof/`, `reg/`) are registered in the same constructor block.

**Example:**
```cpp
// Source: TransactionManager.cpp:187-235 (verified this session)
// Existing pattern — lines 191-201 for tx/ filter:
bool crdt_tx_filter_initialized = instance->globaldb_m->RegisterElementFilter(
    "^/?" + blockchain_base + "tx/[^/]+",
    [weak_ptr(...)](const crdt::pb::Element &element) -> std::optional<std::vector<crdt::pb::Element>>
    {
        if (auto strong = weak_ptr.lock()) { return strong->FilterTransaction(element); }
        return std::nullopt;
    });

// New reg/ filter — appended after proof/ filter registration:
bool crdt_reg_filter_initialized = instance->globaldb_m->RegisterElementFilter(
    "^/?" + blockchain_base + "reg/([^/]+)",
    [weak_ptr( std::weak_ptr<TransactionManager>( instance ) )](
        const crdt::pb::Element &element) -> std::optional<std::vector<crdt::pb::Element>>
    {
        if (auto strong = weak_ptr.lock()) { return strong->FilterRegistration(element); }
        return std::nullopt;
    });
```

### Pattern 2: Consensus Validation Pipeline Extension

**What:** Insert `CheckParentChildAuthority` between `CheckTransactionAuthorization` and `CheckTransactionTimestamp` in `ValidateTransactionForConsensus`.

**When to use:** The extended pipeline sequence is: well-formed → authorization → **parent-child-authority** → timestamp → replay → tx-type-rules → approve. The gate only fires for `"transfer"` tx type; all other types (including `RegistrationTx` itself) pass through unmodified.

**Example:**
```cpp
// Source: TransactionManager.cpp:4234-4303 (verified this session)
// Current pipeline (lines 4250-4303):
ConsensusManager::ValidationResult TransactionManager::ValidateTransactionForConsensus(
    const std::shared_ptr<GeniusTransaction> &tx) const
{
    if (!CheckTransactionWellFormed(*tx)) return Reject();
    if (!CheckTransactionAuthorization(*tx)) return Reject();
    // ★ NEW GATE INSERTED HERE (D-19) ★
    // auto parent_child_result = CheckParentChildAuthority(*tx);
    // if (parent_child_result.check != Check::Approve) return parent_child_result;
    if (!CheckTransactionTimestamp(*tx)) return Reject();
    // ... rest unchanged ...
}
```

### Pattern 3: Parent-Child Authority Gate (Six Rules)

**What:** A deterministic method `CheckParentChildAuthority` that reads `reg/` CRDT records and applies the six CONS rules. Returns `Approve` for all non-delegated transactions, `Reject` for unauthorized delegated transactions.

**When to use:** Called by `ValidateTransactionForConsensus` for any `"transfer"` tx type.

**Example:**
```cpp
// Design pattern for CheckParentChildAuthority
// Source: Derived from D-19/D-20/D-21/D-23 and verified code audit this session

ConsensusManager::ValidationResult TransactionManager::CheckParentChildAuthority(
    const GeniusTransaction &tx) const
{
    // Gate only applies to transfer transactions
    if (tx.GetType() != "transfer") { return ConsensusManager::ValidationResult::Approve(); }

    const auto &src = tx.GetSrcAddress();
    const auto &dst = tx.GetDstAddress();

    // Check if src is a registered child wallet
    auto reg_result = FetchRegisteredMain(src);
    if (reg_result.has_error()) { return ConsensusManager::ValidationResult::Approve(); }
    const auto &main_from_reg = reg_result.value();

    // Check if registration is certified (D-26)
    if (!IsRegistrationCertified(src)) { return ConsensusManager::ValidationResult::Approve(); }

    // Who signed the transaction?
    bool signed_by_main = (main_from_reg == src) || /* main is src */;
    bool main_signed_the_tx = /* check signature against main key */;

    // CONS-01: Main → Child fund
    // Main signature + src is main address + dst is registered child
    // → Already handled: main signing its own tx passes existing auth check

    // CONS-02: Main-recover-from-child
    // Main signed + src is a child registered to that main
    // DESTINATION RESTRICTION: dst MUST be the registered main
    if (main_signed_the_tx && main_from_reg != src) { // main signed, src=child
        if (dst != main_from_reg) {
            return ConsensusManager::ValidationResult::Reject();
        }
        return ConsensusManager::ValidationResult::Approve();
    }

    // CONS-03/04/05: Child→* transfers pass through (existing auth handles them)
    return ConsensusManager::ValidationResult::Approve();
}
```

### Anti-Patterns to Avoid

- **Calling `CheckParentChildAuthority` from `FilterRegistration`:** The CRDT filter should validate only signature+sequence+well-formedness (D-13). Authority checks belong in the consensus validation pipeline, not the CRDT intake filter. Conflating these creates a split-brain where a tx passes CRDT filter but fails consensus.
- **Reading CRDT without certified-status check during authority gate:** The gate must verify `IsRegistrationCertified(src)` before acting on a `reg/` record. Uncertified registrations are optimistic storage only (D-26).
- **Symmetric authority check (child-as-main direction):** The gate must be directional — main signature authorizes main→child actions; child signature NEVER authorizes child→main UTXO spending. The existing `ValidateWitness` owner_address check already enforces this; the new gate must not weaken it.
- **New consensus subject type for RegistrationTx:** RegistrationTx reuses `sgns.nonce.v1` (D-24). Creating a new subject type would require a new subject handler registration, new slot-key handler, and new certificate handler — all unnecessary.
- **Deriving parent-child authority from pubsub topic membership:** Authority is ALWAYS derived from signatures validated by consensus, never from "arrived on the right topic" (Pitfall 5, D-16).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CRDT element validation/filtering | Custom validation pipeline | `GlobalDB::RegisterElementFilter` with `FilterRegistration` callback | Existing filter system handles deserialization, key-matching, tombstone application, and conflict detection. `FilterTransaction`/`FilterProof` provide the proven template. |
| PubSub message transport for registration notification | Custom gossip protocol or direct connection | `PubSubBroadcasterExt::AddBroadcastTopic`/`AddListenTopic` | Existing libp2p GossipSub infrastructure handles peer discovery, message routing, and network resilience. Already in use for `tx/` data. |
| Consensus ordering for registration events | New consensus subject type or custom ordering mechanism | `sgns.nonce.v1` subject + `SubmitProposal` → certificate path | Existing nonce-chain consensus handles total ordering, quorum voting, and certificate finality. `RegistrationTx` carries a nonce in its `DAGStruct` — the nonce chain already provides ordering. |
| Signature verification for RegistrationTx | Re-implement secp256k1 signature check | `GeniusTransaction::CheckSignature()` (inherited by RegistrationTx) | RegistrationTx extends GeniusTransaction which already has `FillHash`/`MakeSignature`/`CheckSignature`. Reusing avoids crypto bugs. |
| UTXO ownership enforcement (CONS-05) | New ownership check path | Existing `GeniusInputValidator::ValidateWitness` owner_address check (line 421) | Already enforces `payload_owner != src_address` rejection (with escrow exception). Document this as invariant — no new code needed. |
| Transaction type dispatch | New switch/if-else chain | Existing `transaction_parsers` unordered_map + `tx.GetType()` lookup | `TransactionManager::CheckTransactionWellFormed` already validates against this map (line 4343). `CheckTransactionTypeRules` dispatches via it. |
| Certificate tracking (certified status) | New persistence mechanism | `OnConsensusCertificate` callback + existing `ChangeTransactionState(tx, CONFIRMED)` pattern | The certificate handler fires when consensus certifies the nonce subject. RegistrationTx is tracked by the same `tx_processed_m` map. Extend `OnConsensusCertificate` to update certified status. |

**Key insight:** The SuperGenius codebase already has all the infrastructure for Phase 2. The design work is integration — plugging a new filter into the existing filter registration block, adding a gate to the existing validation pipeline, and extending the existing certificate handler. No new subsystems, no new libraries, no new proto message types (beyond the RegistrationTx added in Phase 1).

## Common Pitfalls

### Pitfall 1: CRDT filter sequence validation stale reads

**What goes wrong:** `FilterRegistration` reads the current `reg/{child_addr}` record to validate `new_tx.sequence > current.sequence`, but the read returns a stale (uncertified) value. An attacker replays a sequence N registration after sequence N+1 was already written to CRDT but not yet merged locally.

**Why it happens:** CRDT is eventually consistent — a peer may not yet have the latest delta. The filter runs on local CRDT state.

**How to avoid:** The sequence check at the CRDT filter level is a **best-effort gate** (D-13). The authoritative sequence enforcement happens at the **consensus level** — the nonce chain prevents two registrations at different nonces from both being certified (first-to-consensus wins per D-25). The CRDT filter rejection for equal/lower sequence is an optimization that prevents redundant CRDT storage, not a security boundary.

**Warning signs:** Sequence validation failing to prevent a registration with a stale sequence from being stored in CRDT. The filter correctly rejects it given current local state; but if state is stale, it may accept. This is expected — consensus provides the authoritative ordering.

### Pitfall 2: CheckParentChildAuthority reads from uncertified CRDT

**What goes wrong:** The authority gate reads `reg/{child_addr}`, gets a pre-certificate entry (optimistic storage), and authorizes a parent-child action based on an unconfirmed registration.

**Why it happens:** The reg/ filter accepts pre-certificate entries (D-26); the CRDT stores them immediately. A validator reading CRDT during consensus validation may see an uncertified record.

**How to avoid:** The authority gate MUST check the certified-status flag before acting. Per D-26: "The main wallet only acts on certified registrations." The design document must specify the gate's certified-status check and its behavior when encountering an uncertified record (treat as no relationship → the transaction proceeds without parent-child authority; if the tx requires parent-child authority, it will fail downstream).

**Warning signs:** Authority gate reads `reg/` entry and immediately uses it without checking certification. Missing `IsRegistrationCertified()` call.

### Pitfall 3: Registration CID in pubsub payload not resolving

**What goes wrong:** The main receives a pubsub notification with a RegistrationTx CID, but the CID cannot be resolved from CRDT (the DAG sync hasn't propagated it yet, or it was malicious/hallucinated).

**Why it happens:** PubSub is a low-latency notification channel; CRDT DAG sync (graphsync) may lag behind. A malicious peer could publish a fabricated CID.

**How to avoid:** The main must handle CID resolution failure gracefully: retry with backoff, ignore unresolvable CIDs after a timeout, and never block waiting for CID resolution. Per D-16: "authority is NEVER derived from topic membership." An unresolvable pubsub notification is silently discarded — it does not create a phantom registration.

**Warning signs:** Main blocks on CID resolution; main treats an unresolvable CID as evidence of a registration; no timeout or retry logic.

### Pitfall 4: Over-writing the CheckTransactionAuthorization path

**What goes wrong:** Adding parent-child authority logic directly into `CheckTransactionAuthorization` (currently signature-only) conflates cryptographic authorization with state-dependent authorization.

**Why it happens:** The temptation to modify the existing gate rather than add a new one — fewer lines changed, "simpler."

**How to avoid:** D-19/D-23 explicitly require a **separate** `CheckParentChildAuthority` gate. `CheckTransactionAuthorization` remains purely cryptographic. The new gate reads CRDT state; the old gate does not. Keeping them separate allows independent testing, clear audit trail, and avoids the risk of state-dependent logic interfering with signature verification.

**Warning signs:** Code modifying `CheckTransactionAuthorization` to read `reg/` entries. Missing `CheckParentChildAuthority` method.

### Pitfall 5: Forgetting to handle RegistrationTx in the consensus pipeline

**What goes wrong:** `RegistrationTx` flows through the nonce subject handler → `ValidateTransactionForConsensus`, but `CheckTransactionTypeRules` calls `tx->HasUTXOParameters()` which returns false for RegistrationTx, returning true → passes. However, nothing explicitly validates the RegistrationTx contents (main_address format, sequence > 0).

**Why it happens:** RegistrationTx is a new tx type that passes through `CheckTransactionWellFormed` (type exists in `transaction_parsers`), passes `CheckTransactionAuthorization` (child signature), and passes `CheckTransactionTypeRules` (no UTXO parameters to validate). Its semantic validation — `main_address` is a valid public key, `sequence > 0` — is not covered by existing gates.

**How to avoid:** The design document must specify that `CheckTransactionWellFormed` or a new `CheckTransactionTypeRules` branch explicitly validates RegistrationTx fields: (1) `main_address` is a valid 128-hex public key via `GeniusAccount::IsValidPublicKey`, (2) `sequence > 0`. This validation already exists in `FilterRegistration` (D-13), but should also be present in the consensus pipeline for defense-in-depth.

**Warning signs:** `FilterRegistration` validates fields but `ValidateTransactionForConsensus` does not. No explicit `RegistrationTx` field validation in the consensus path.

## Code Examples

Verified patterns from the codebase that the design documents must reference:

### FilterTransaction (Template for FilterRegistration)

```cpp
// Source: TransactionManager.cpp:2984-3039 (verified this session)
std::optional<std::vector<crdt::pb::Element>> TransactionManager::FilterTransaction(
    const crdt::pb::Element &element)
{
    bool should_delete = true;
    std::shared_ptr<GeniusTransaction> new_tx;
    do
    {
        auto maybe_new_tx = DeSerializeTransaction(element.value());
        if (maybe_new_tx.has_error()) break;  // (a) deserialization failure
        
        new_tx = maybe_new_tx.value();
        if (!CheckTransactionAuthorization(*new_tx)) break;  // (b) invalid signature
        
        if (KeyExistsInDB(GetTransactionPath(*new_tx))) break;  // (c) key collision
        
        should_delete = false;
    } while (0);

    if (should_delete)
    {
        // Cascade-delete paired proof key (tx/ → proof/)
        std::vector<crdt::pb::Element> additional_elements_to_delete;
        auto maybe_proof_key = GetExpectedProofKey(element.key(), new_tx);
        if (maybe_proof_key.has_value())
        {
            crdt::pb::Element proof_element;
            proof_element.set_key(maybe_proof_key.value());
            additional_elements_to_delete.push_back(proof_element);
        }
        return additional_elements_to_delete;  // tombstone(s) → REJECT
    }
    return std::nullopt;  // ACCEPT
}
```

### ValidateTransactionForConsensus (Current Pipeline)

```cpp
// Source: TransactionManager.cpp:4234-4303 (verified this session)
ConsensusManager::ValidationResult TransactionManager::ValidateTransactionForConsensus(
    const std::shared_ptr<GeniusTransaction> &tx) const
{
    if (!tx) return ConsensusManager::ValidationResult::Reject();

    if (!CheckTransactionWellFormed(*tx)) return ConsensusManager::ValidationResult::Reject();
    if (!CheckTransactionAuthorization(*tx)) return ConsensusManager::ValidationResult::Reject();
    // ★ Insert CheckParentChildAuthority here (D-19) ★
    if (!CheckTransactionTimestamp(*tx)) return ConsensusManager::ValidationResult::Reject();
    auto replay_result = EvaluateTransactionReplayProtection(*tx);
    if (replay_result.validation.check != ConsensusManager::Check::Approve)
        return replay_result.validation;
    if (!CheckTransactionTypeRules(tx)) return ConsensusManager::ValidationResult::Reject();

    return ConsensusManager::ValidationResult::Approve();
}
```

### GenesisInputValidator — Escrow Exception (CONS-05 Anchor)

```cpp
// Source: GenesisInputValidator.cpp:419-432 (verified this session)
const std::string payload_owner(payload.data() + OWNER_ADDRESS_OFFSET,
                                 payload.data() + OWNER_ADDRESS_OFFSET + owner_len);

// The ONLY place where payload_owner != tx->GetSrcAddress() is allowed:
const bool delegated_escrow_spend =
    payload_owner != tx->GetSrcAddress() &&
    tx->GetType() == TRANSFER_TX_TYPE &&
    input.output_idx_ == ESCROW_LOCK_OUTPUT_INDEX &&
    utxo_address::IsEscrowLockAddress(payload_owner) &&
    tx->GetUncleHash() == payload_owner;

// This is where CONS-05 is enforced today:
if (payload_owner != tx->GetSrcAddress() && !delegated_escrow_spend)
{
    logger->debug("ValidateWitness(Genius) owner mismatch for tx={} owner={} src={}",
                   PreviewValue(tx->GetHash()),
                   PreviewValue(payload_owner),
                   PreviewValue(tx->GetSrcAddress()));
    return false;  // REJECT: child can't spend main's UTXOs
}
```

### Consensus Subject Handler Registration

```cpp
// Source: TransactionManager.cpp:149-159 (verified this session)
// RegistrationTx reuses the same sgns.nonce.v1 handler:
instance->blockchain_->RegisterSubjectHandler(
    NONCE_SUBJECT_TYPE,  // "sgns.nonce.v1"
    [weak_ptr(...)](const ConsensusManager::Subject &subject)
        -> outcome::result<ConsensusManager::ValidationResult>
    {
        if (auto strong = weak_ptr.lock())
            return strong->HandleNonceConsensusSubject(subject);
        return outcome::failure(std::errc::owner_dead);
    });

// Certificate handler registered at line 127-148
instance->blockchain_->RegisterCertificateHandler(
    NONCE_SUBJECT_TYPE,
    [weak_ptr(...)](const std::string &subject_hash, const ConsensusCertificate &certificate)
        -> outcome::result<ConsensusManager::Check>
    {
        if (auto strong = weak_ptr.lock())
            return strong->OnConsensusCertificate(subject_hash, certificate);
        return outcome::failure(std::errc::owner_dead);
    });
```

### SendTransactionItem — Write CRDT → SubmitProposal Flow

```cpp
// Source: TransactionManager.cpp:1127-1311 (verified this session)
// RegistrationTx follows this exact flow:
// 1. Serialize tx to bytes
auto transaction_path = GetTransactionPath(*transaction);
// For RegistrationTx: GetBlockChainBase() + "reg/" + child_addr
crdt::HierarchicalKey tx_key(transaction_path);
crdt::GlobalDB::Buffer data_transaction;
data_transaction.put(transaction->SerializeByteVector());

// 2. Write to CRDT (within atomic transaction)
BOOST_OUTCOME_TRY(crdt_transaction->Put(std::move(tx_key), std::move(data_transaction)));
// ... (no proof key for RegistrationTx — reg/ has no paired namespace)

// 3. Collect topics (full_node_topic + own_address)
topicSet.emplace(full_node_topic_m);
topicSet.emplace(account_m->GetAddress());

// 4. Commit CRDT transaction with topics
BOOST_OUTCOME_TRY(crdt_transaction->Commit(topicSet));

// 5. Submit to consensus
BOOST_OUTCOME_TRY(auto &&proposal,
    blockchain_->CreateConsensusProposal(/* ... */));
BOOST_OUTCOME_TRY(blockchain_->SubmitProposal(proposal));
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Authorization = signature only (no hierarchical authority) | Signature + parent-child authority gate (consensus-enforced) | Phase 2 design | First time consensus enforces a non-cryptographic authority relationship. `CheckParentChildAuthority` reads CRDT state during consensus validation — a new dependency. |
| CRDT = authoritative state (no certification gating) | CRDT = optimistic storage; certified flag = authoritative | Phase 2 design | Two-tier model: CRDT stores pre-certificate; consensus certificate marks authoritative. Required to resolve eventual-consistency vs ordering tension. |
| Registration recorded only in tx/ namespace (implicit) | Registration recorded in dedicated reg/ namespace (single-key per child) | Phase 2 design | Enables O(1) lookup of registration by child address. Separates registration state from transaction history. |
| PubSub topics = node address + full-node only | Add child→main and main→child pubsub topics | Phase 2 design | Enables low-latency discovery and ongoing state sync. Authority derived from consensus, not topic membership. |

**Deprecated/outdated:**
- **Implicit child-ness detection:** No longer hypothetical after Phase 1 — D-01 establishes emergent child-ness. Phase 2 builds on this by providing the `reg/` lookup mechanism for `CheckParentChildAuthority`.

## Assumptions Log

> List all claims tagged `[ASSUMED]` in this research. The planner and discuss-phase use this section to identify decisions that need user confirmation before execution.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `RegistrationTx` protobuf can be deserialized from the CRDT `reg/{child_addr}` value using the existing `DeSerializeTransaction` or a new `DeSerializeRegistration` path | Standard Stack, Architecture Patterns | LOW — Phase 1 design defines `RegistrationTx` as a proto3 message. Deserialization follows existing patterns. If proto layout changes, filter must be updated. |
| A2 | `GetBlockChainBase()` (returns `/bc-{network_id}/`) provides the correct prefix for `reg/` keys across all monitored networks | Standard Stack, Architecture Patterns | LOW — The function is used by `tx/` and `proof/` paths today (line 1356). Same prefix convention applies to `reg/`. Verified in this session. |
| A3 | The `OnConsensusCertificate` callback (line 3768) can be extended to mark `reg/{child_addr}` as certified without structural changes to the certificate handler dispatch | Architecture Patterns, Don't Hand-Roll | LOW — The callback already dispatches on subject type hash. RegistrationTx shares the `sgns.nonce.v1` subject type. Adding registration-specific handling is a code path within the existing handler. |
| A4 | The certified status flag implementation choice (Option A: separate CRDT key, B: in-band field, C: in-memory map) does not affect the consensus authority gate's correctness — all three provide a boolean "is certified" check | Architecture Patterns | MEDIUM — Option C (in-memory map) requires rebuild-on-restart, which may introduce a window where a certified registration appears un-certified. Planner should select Option A or B for durability. |
| A5 | `AddListenTopic(child_address)` on the main node will successfully subscribe to CRDT deltas published on the child's address topic | Architecture Patterns | LOW — The child's `TransactionManager::SendTransactionItem` already publishes to `account_m->GetAddress()` (line 1166). The main subscribing to the same topic will receive those deltas. Verified in this session. |
| A6 | The `GeniusTransaction::CheckSignature()` path (inherited by RegistrationTx) correctly validates child-signed-only registrations per D-04 | Standard Stack | LOW — RegistrationTx embeds `DAGStruct dag_struct = 1` which carries `source_addr` and `signature`. `CheckSignature` verifies the signature against `source_addr`. The child's signature is the only signature on the tx. Verified in this session. |

## Open Questions (RESOLVED)

1. **Certified status flag implementation**
   - What we know: D-26 requires a certified status/flag to distinguish consensus-confirmed registrations from optimistic CRDT entries. Three options exist (separate CRDT key, in-band field, in-memory map).
   - What's unclear: Which approach best matches the existing certificate tracking patterns for `tx/` entries. Existing `OnConsensusCertificate` calls `ChangeTransactionState(tx, CONFIRMED)` — an in-memory status update keyed by tx hash.
   - Recommendation: Follow the existing pattern — extend `OnConsensusCertificate` to set a certified flag in `tx_processed_m` for RegistrationTx entries. Option C (in-memory map) is simplest and matches the existing pattern. If durability across restarts is required (main node restart should not forget certified registrations), augment with Option A (separate CRDT key) as a queryable backup.

2. **RegistrationTx field validation in consensus pipeline**
   - What we know: `FilterRegistration` validates `main_address` and `sequence > 0` at the CRDT filter level (D-13). `ValidateTransactionForConsensus` currently has no explicit RegistrationTx semantic validation beyond `CheckTransactionWellFormed` (type exists in `transaction_parsers`).
   - What's unclear: Whether to add explicit RegistrationTx field validation in `CheckTransactionTypeRules` or `CheckTransactionWellFormed` for defense-in-depth.
   - Recommendation: Add a `RegistrationTx` case to `CheckTransactionTypeRules` that validates `main_address` is a valid public key (`GeniusAccount::IsValidPublicKey`) and `sequence > 0`. This provides defense-in-depth — the CRDT filter may run on stale state, but consensus validation always runs on the current state.

3. **Full-node topic for RegistrationTx broadcast**
   - What we know: `SendTransactionItem` publishes to `full_node_topic_m` and `account_m->GetAddress()` (line 1165-1166). For RegistrationTx, the child additionally broadcasts on `main_address` topic (D-15).
   - What's unclear: Whether the full-node topic is needed for registration propagation, or if the reg/ CRDT DAG sync (graphsync) suffices. Full nodes already sync `tx/` and `proof/` CRDT deltas.
   - Recommendation: Include `full_node_topic_m` in the RegistrationTx broadcast topics. This ensures full nodes receive the registration delta via CRDT sync regardless of whether they subscribe to the specific main address topic. The reg/ filter accepts the delta on all nodes; the pubsub notification on main's topic is a **discovery shortcut** for the main, not the primary propagation mechanism.

4. **PubSub notification payload format (CID representation)**
   - What we know: D-18 specifies the notification payload carries the RegistrationTx **CID/hash** only, not the full protobuf. The main resolves the CID from CRDT to fetch the full record.
   - What's unclear: Whether to use the IPLD CID (content-addressed Merkle DAG hash) or the transaction hash (`tx.GetHash()`). The CRDT `Put` returns a CID.
   - Recommendation: Use the **CRDT CID** returned from `GlobalDB::Put`. This is content-addressed and the main can resolve it via `GlobalDB::GetCIDContent` or the Graphsync DAG syncer. The transaction hash (`tx.GetHash()`) is the DAGStruct hash, which is different from the CRDT IPLD CID. The CID is the canonical reference into the CRDT DAG.

## Environment Availability

> This phase has no external dependencies beyond the existing SuperGenius C++ codebase. No new tools, services, or runtimes are required.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| SuperGenius codebase | Design document reference | ✓ | current HEAD | — |
| Phase 1 design docs | RegistrationTx schema reference | ✓ | `docs/registration-protocol.md`, `docs/child-wallet-identity-model.md` | — |
| C++17 compiler | (not required — design docs only) | — | — | — |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** None.

## Security Domain

> Required: `security_enforcement: true` in config. ASVS Level 1.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | Yes | Cryptographic signature verification (`CheckTransactionAuthorization`, `CheckSignature`). Parent-child authority gate adds state-dependent authorization on top. |
| V3 Session Management | No | Wallet/node model — no traditional session management. Account nonce chains provide ordering; consensus certificates provide finality. |
| V4 Access Control | Yes | **Primary concern.** `CheckParentChildAuthority` is an access control gate: (a) main→child: main signature + registration, (b) main-recover: main signature + destination restriction, (c) child→*: child signature only, (d) child-spends-main: explicitly rejected. Authorization is enforced by consensus, not local metadata. |
| V5 Input Validation | Yes | `FilterRegistration`: deserialization validation, signature verification, sequence monotonicity, well-formedness check. `CheckTransactionWellFormed`: type registration, hash validity, source address non-empty, timestamp non-zero. Proto validation via protobuf library. |
| V6 Cryptography | Yes | secp256k1 ECDSA signatures via `GeniusAccount::CheckSignature`. Never hand-roll crypto — reuse existing `CheckSignature`/`CheckDAGSignatureLegacy`. |
| V7 Error Handling & Logging | N/A | Design phase — implementation-level concern. Existing `TransactionManager` uses structured logging via `spdlog`. |

### Known Threat Patterns for CRDT + PubSub + Consensus Authority

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Registration replay (old seq registration replayed, re-asserting stale relationship) | Spoofing / Tampering | Per-child monotonic `sequence` field (D-09). `FilterRegistration` rejects lower-or-equal sequences (D-13). First-to-consensus wins for equal sequences (D-25). |
| PubSub topic spoofing (malicious peer publishes on main's topic, claiming to be a registered child) | Spoofing | PubSub notification carries only a CID/hash (D-18). Main resolves CID from CRDT and validates the registration has a consensus certificate (D-16, D-26). Authority never derived from topic membership. |
| Main-to-child funding without registration (main funds an address that never registered as a child) | Elevation of Privilege | This is a normal transfer — no registration needed to send funds to an address. `CheckParentChildAuthority` only fires when a main claims delegated authority (recovery). Funding is an unrestricted transfer. |
| Recovery destination hijack (main-compromise scenario: attacker recovers to attacker's address instead of main's) | Tampering | D-21 hard destination restriction: `dst != main_address` → reject. The registered main's address is recorded in the consensus-certified `reg/{child_addr}` entry. An attacker cannot change it without a new certified registration at a higher sequence. |
| Pre-certificate registration used for authority (uncertified reg/ entry authorizes main→child action) | Elevation of Privilege | D-26 certified status flag. `CheckParentChildAuthority` must verify `IsRegistrationCertified(src)` before applying parent-child authority rules. Uncertified entries are treated as non-existent for authority purposes. |
| CRDT delta reordering (child's CRDT deltas arrive after main's, causing stale balance display) | Information Disclosure | D-26 two-tier model: the main reads certified registration state and syncs CRDT for balances. Balance is derived from UTXO state, not CRDT registration state. Registration is a binary relationship; balances are computed from the tx/ namespace. |
| RegistrationTx nonce collision (two RegistrationTx at same nonce, different sequence) | Denial of Service | D-25: first-to-consensus wins. Nonce chain prevents both from being certified. The losing tx must be retried at a higher nonce. The CRDT filter accepts the first one that clears consensus; the second is rejected by the nonce-chain replay protection. |

## Sources

### Primary (HIGH confidence)
- `SuperGenius/src/crdt/globaldb/globaldb.hpp` — `RegisterElementFilter`, `Put`, `Get`, `AddBroadcastTopic`, `AddListenTopic`, `AddTopicName` [VERIFIED: code audit this session]
- `SuperGenius/src/crdt/globaldb/pubsub_broadcaster_ext.hpp` — `PubSubBroadcasterExt` API: `AddListenTopic`, `AddBroadcastTopic`, `Broadcast` [VERIFIED: code audit this session]
- `SuperGenius/src/crdt/crdt_datastore.hpp` — `CRDTElementFilterCallback` type [VERIFIED: code audit this session]
- `SuperGenius/src/crdt/crdt_data_filter.hpp` — `ElementFilterCallback = std::function<std::optional<std::vector<pb::Element>>(const pb::Element&)>` [VERIFIED: code audit this session]
- `SuperGenius/src/account/TransactionManager.cpp` — Complete audit of:
  - `FilterTransaction` (line 2984): template for `FilterRegistration`
  - `FilterProof` (line 3041): no-paired-namespace filter pattern
  - `ValidateTransactionForConsensus` (line 4234): 7-gate pipeline
  - `CheckTransactionAuthorization` (line 4361): signature-only today
  - `HandleNonceConsensusSubject` (line 3901): consensus subject handler
  - `SendTransactionItem` (line 1127): Write CRDT → SubmitProposal flow
  - `OnConsensusCertificate` (line 3768): certificate handler
  - `transaction_parsers` map (line 95): RegistrationTx registration point
  - `FilterRegistration`/`FilterProof` registration block (line 187-213): reg/ filter insertion point
  - `GetBlockChainBase` (line 1356): CRDT key prefix construction
- `SuperGenius/src/account/GeniusInputValidator.cpp` — `ValidateWitness` owner_address check + escrow exception (lines 419-432) [VERIFIED: code audit this session]
- `SuperGenius/src/account/GeniusTransaction.hpp` — `GetTransactionFullPath()` returns `"tx/" + hash`, `CheckSignature()` [VERIFIED: code audit this session]
- `SuperGenius/src/blockchain/Consensus.hpp` — `sgns.nonce.v1` subject type, `SubmitProposal`, `RegisterSubjectHandler`, `RegisterCertificateHandler` [VERIFIED: code audit this session]
- `SuperGenius/src/blockchain/impl/proto/Consensus.proto` — `EmbeddedTransaction` oneof, `NonceSubject` [VERIFIED: code audit this session]
- `.planning/phases/02-crdt-persistence-pubsub-consensus-authority/02-CONTEXT.md` — All locked decisions D-11 through D-26 [CITED: authoritative context]
- `docs/registration-protocol.md` — RegistrationTx schema and `DeSerializeByteVector` / `SerializeToEmbeddedTransaction` wiring from Phase 1 [CITED: Phase 1 output]
- `GNUS_Subwallet_Architecture_Proposal.md` — §Consensus Rules (all 6 rules), §Main-Wallet Registration, §Wallet Discovery [CITED: authoritative spec]

### Secondary (MEDIUM confidence)
- `.planning/research/SUMMARY.md` — Stack/feature/architecture grounding. Phase 2 flagged as "Deep research needed" for CRDT eventual-consistency vs consensus ordering. [CITED: prior research, this session validates the ordering resolution]
- `.planning/research/PITFALLS.md` — Pitfall 1 (replay/reorder), Pitfall 3 (recovery-as-seizure), Pitfall 4 (child-spends-main), Pitfall 5 (pubsub trust) — all addressed by Phase 2 decisions [CITED: prior research, this session confirms mitigations]
- `.planning/phases/01-child-identity-registration-protocol/01-CONTEXT.md` — Phase 1 decisions carried forward (D-01 through D-10) [CITED: upstream context]

### Tertiary (LOW confidence)
- None — all claims in this research are verified against the codebase or cited from authoritative documents.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All components audited in this session. The existing SuperGenius stack provides all needed infrastructure.
- Architecture: HIGH — Integration points verified in code. CRDT filter registration pattern, consensus pipeline gate insertion, and pubsub topic API are all proven patterns.
- Pitfalls: HIGH — Pitfall 1-5 from research/PITFALLS.md explicitly addressed by decisions D-24/D-25/D-26 (ordering), D-21 (recovery-seizure), D-22 (child-spends-main), D-16 (pubsub-trust). New pitfalls identified and mitigated.

**Research date:** 2026-07-13
**Valid until:** 2026-08-12 (30 days — stable SuperGenius codebase, no anticipated breaking changes)
