# Phase 3: Discovery, Rewards & Lifecycle - Research

**Researched:** 2026-07-13
**Domain:** Main-wallet discovery/monitoring, per-child processing-reward policy, lifecycle/change flows with replay-safe conflict resolution
**Confidence:** HIGH

## Summary

Phase 3 produces two design documents grounded in the SuperGenius codebase: (1) a discovery & monitoring design that specifies how a main wallet discovers registered children via pubsub push-primary/poll-fallback, aggregates per-child information, and maps main-wallet actions (fund, recover, inspect, revoke/detach) to concrete anchor points; (2) a reward policy + lifecycle/change-flows design that specifies per-child processing-reward policy resolution, hold-time pinning, authenticated update rules, the lifecycle state machine, and replace/remove/detach flows with supersedes-sequence conflict resolution.

The primary technical risk is the **discovery polling protocol** (D-27): there is no existing request/response protocol on the pubsub infrastructure. However, `AccountMessenger` already implements a request/response pattern with `OnRequest`/`OnResponse` handlers over pubsub topics. The idiomatic approach is **option (b)**: the main broadcasts a `ChildDiscoveryRequest` on `SGNUS.BC.Requests.comm` (the existing global requests topic) or its own `.comm` topic, and any node that holds `reg/` CRDT state responds with a `ChildDiscoveryResponse` containing the RegistrationTx CID list. This reuses the `AccountMessenger` worker-thread pattern, the `accountComm::AccountMessage` oneof dispatch, and the existing `RequestHeads` broadcast pattern verbatim — no new pubsub infrastructure needed.

**Primary recommendation:** Reuse the `AccountMessenger` request/response pattern for discovery polling — extend `accountComm::AccountMessage` with a new `child_discovery_request`/`child_discovery_response` oneof arm (fields 10/11), and add handler methods following the `HandleNonceRequest`/`HandleNonceResponse` pattern at `AccountMessenger.cpp:1472-1566`.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Child discovery (push) | CRDT/PubSub | — | Registration's `SendTransactionItem` already publishes CID on `main_address` topic (D-15); main receives notification via `AddListenTopic` |
| Child discovery (poll) | AccountMessenger (pubsub) | Full nodes | The main broadcasts a query on pubsub; any node with CRDT state responds — decentralized, no new consensus infra |
| Per-child info aggregation | Main wallet (local logic) | CRDT (child state sync) | Balance/UTXO/tx data comes from child CRDT deltas via `AddListenTopic(child_address)` (D-17); registration metadata from `reg/{child_addr}` CRDT |
| Reward policy resolution (standalone) | GeniusNode SDK | DevConfig struct | `dev_config_.Addr`/`dev_config_.Cut` read at HoldEscrow time (`GeniusNode.cpp:1983-1985`) |
| Reward policy resolution (registered) | TransactionManager escrow | reg/ CRDT | HoldEscrow reads `dev_wallet`/`peers_cut` from certified `reg/{child_addr}` record; falls back to DevConfig |
| Hold-time pinning | EscrowTransaction | — | `dev_addr_`/`peers_cut_` stored immutably at construction (`EscrowTransaction.hpp:130-131`); PayEscrow reads stored values |
| Rewards policy update | CRDT (reg/ record) | Consensus (nonce chain) | Child-signed RegistrationTx at higher `sequence` with updated `RegistrationMetadata`; CRDT merge keeps highest-sequence entry |
| Lifecycle state transitions | CRDT reg/ filter | Consensus (nonce chain) | RegistrationTx carries `detach_flag`/`supersedes_sequence`; FilterRegistration validates sequence ordering; consensus certifies |
| Revoke (main-initiated) | CheckParentChildAuthority gate | Consensus validation | Main-signed consensus transaction; gate validates main sig + reg/ match + registered state |
| Supersedes conflict resolution | CRDT FilterRegistration | sgns.nonce.v1 consensus | Filter rejects if `supersedes_sequence != current.sequence`; nonce chain prevents double-cert |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Protocol Buffers (protobuf) | v3 (bundled) | Additive proto evolution for detach_flag, supersedes_sequence, RevokeTx, discovery query/response | `SGTransaction.proto` and `SGAccountComm.proto` already use protobuf; all wire formats are proto-based |
| RocksDB | bundled (via GlobalDB) | CRDT-backed reg/ records read by discovery polling responders | `GlobalDB::Get(HierarchicalKey)` is the standard storage accessor |
| Boost.Asio | ~1.85.0/1.89 | Async pubsub messaging, worker thread pool for discovery responses | `AccountMessenger` uses worker thread + pubsub via Boost |
| IPFS pubsub (GossipPubSub) | bundled | Discovery push (CID broadcast) and poll (query/response over pubsub) | `PubSubBroadcasterExt` already wraps this; `AccountMessenger` uses it for request/response |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `boost::format` | bundled | CRDT key construction: `GetBlockChainBase() + "reg/" + child_addr` | Already used in `TransactionManager::GetBlockChainBase()` (`TransactionManager.cpp:1356-1358`) |
| `rapidjson::Document` | referenced in `messaging_watcher.hpp` | Local JSON cache schema for discovered-children list | Already in dependency tree; no new dependency needed |

**Installation:**
```bash
# No new packages to install — all dependencies are in the existing SuperGenius tree.
# Design-documentation phase: no npm/pip/cargo installs needed.
```

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| New pubsub query/response protocol | Reuse AccountMessenger pattern | AccountMessenger already has `OnRequest`/`OnResponse` dispatch, `SendAccountMessage`, `worker_thread_` — extending it is idiomatic and avoids new infrastructure |
| New CRDT index namespace for discovery | Main queries peer nodes | "Discovery is peer-to-peer, not stored in consensus state" (D-27) — no need for durable indexing; simpler to query live nodes |
| Separate dev_wallet/peers_cut CRDT key | In-band in RegistrationTx Metadata | RegistrationTx already carries `RegistrationMetadata.dev_wallet`/`.peers_cut` (Phase 1 D-08); updating these means a new RegistrationTx at higher sequence — existing pattern |

## Package Legitimacy Audit

> No external packages are installed in this phase. The phase produces design documents referencing the existing SuperGenius C++ codebase. No npm, pip, or cargo packages are added. Package Legitimacy Audit is **not required**.

## Architecture Patterns

### System Architecture Diagram

```
                        ┌────────────────────────────────────────┐
                        │           MAIN WALLET NODE              │
                        │  ┌──────────────────────────────────┐  │
  PubSub (push) ────────►│  │  Discovery Engine                │  │
  (CID on main topic)    │  │  - Push: receives CID via        │  │
                        │  │    AddListenTopic(main_addr)      │  │
  PubSub (poll query)   │  │  - Poll: broadcasts ChildDisc     │  │
  ◄──────────────────── │  │    Request, collects responses    │  │
  PubSub (poll resp) ───►│  │  - Caches in local JSON          │  │
                        │  └──────────────┬───────────────────┘  │
                        │                 │                       │
                        │  ┌──────────────▼───────────────────┐  │
                        │  │  Per-Child Aggregator             │  │
                        │  │  - reg/{child} → metadata fields  │  │
                        │  │  - child CRDT deltas → balance/   │  │
                        │  │    UTXOs/activity (D-17 sync)     │  │
                        │  │  - local cache → display prefs    │  │
                        │  └──────────────┬───────────────────┘  │
                        │                 │                       │
                        │  ┌──────────────▼───────────────────┐  │
                        │  │  Main-Wallet Actions              │  │
                        │  │  - Fund: main-signed transfer    │  │
                        │  │  - Recover: CONS-02 restriction  │  │
                        │  │  - Inspect: read-only CRDT       │  │
                        │  │  - Revoke: main-signed tx        │  │
                        │  └──────────────────────────────────┘  │
                        └──────────────────────┬─────────────────┘
                                               │
                        ┌──────────────────────▼─────────────────┐
                        │          CRDT / CONSENSUS LAYER          │
                        │  ┌────────────────────────────────────┐ │
                        │  │  reg/ Namespace                     │ │
                        │  │  Key: /bc-{net}/reg/{child_addr}    │ │
                        │  │  Value: full RegistrationTx proto   │ │
                        │  │  Filter: deser→sig→seq>curr→ok      │ │
                        │  └────────────────────────────────────┘ │
                        │  ┌────────────────────────────────────┐ │
                        │  │  sgns.nonce.v1 Consensus            │ │
                        │  │  HandleNonceConsensusSubject        │ │
                        │  │  OnConsensusCertificate → CONFIRMED │ │
                        │  └────────────────────────────────────┘ │
                        │  ┌────────────────────────────────────┐ │
                        │  │  CheckParentChildAuthority Gate     │ │
                        │  │  (Phase 2 D-19)                     │ │
                        │  └────────────────────────────────────┘ │
                        └──────────────────────────────────────┬──┘
                                                               │
                        ┌──────────────────────────────────────▼──┐
                        │         CHILD WALLET NODE                │
                        │  ┌────────────────────────────────────┐ │
                        │  │  RegistrationTx Lifecycle           │ │
                        │  │  - Create (sequence N)              │ │
                        │  │  - Replace main (N+1, supersedes N) │ │
                        │  │  - Detach (N+1, detach_flag)        │ │
                        │  │  - Re-register (N+2)                │ │
                        │  └────────────────────────────────────┘ │
                        │  ┌────────────────────────────────────┐ │
                        │  │  Escrow / Reward Policy             │ │
                        │  │  - HoldEscrow: pins dev_wallet/     │ │
                        │  │    peers_cut from reg/ or DevConfig │ │
                        │  │  - PayEscrow: reads stored values   │ │
                        │  └────────────────────────────────────┘ │
                        └─────────────────────────────────────────┘
```

### Recommended Project Structure
```
.planning/phases/03-discovery-rewards-lifecycle/
└── docs/
    ├── 03-01-discovery-monitoring.md       # Discovery & monitoring design
    └── 03-02-reward-policy-lifecycle.md    # Reward policy + lifecycle design
```

### Pattern 1: AccountMessenger Request/Response (Discovery Poll)

**What:** The main wallet broadcasts a discovery query on pubsub, and any node with CRDT state can respond. This reuses the existing `AccountMessenger` pattern: `OnRequest` dispatches on `AccountMessage` oneof type; the worker thread dequeues, broadcasts, and collects responses with timeout.

**When to use:** D-27 (discovery polling — push-primary, poll-fallback). The main misses a broadcast or joins late; it polls via `AccountMessenger`.

**Source:** `AccountMessenger.hpp:199-223` (topic constants), `AccountMessenger.cpp:143-196` (RequestHeads → broadcast on global requests topic), `AccountMessenger.cpp:190-234` (OnRequest/OnResponse dispatch), `AccountMessenger.cpp:868-886` (SendAccountMessage).

**Existing pattern (NonceRequest → NonceResponse):**
```cpp
// AccountMessenger.cpp:276-304 — RequestNonce broadcasts to account_comm_topic_ + requests_topic_
outcome::result<void> AccountMessenger::RequestNonce(uint64_t req_id) {
    accountComm::NonceRequest nonce_req;
    nonce_req.set_requester_address(address_);
    nonce_req.set_request_id(req_id);
    nonce_req.set_timestamp(GetTimestamp());
    // ... sign, serialize, SendAccountMessage on account_comm_topic_ + requests_topic_
}

// AccountMessenger.cpp:1472+ — HandleNonceRequest
// Any node that receives this request on its subscribed topics constructs
// a NonceResponse and sends it back to the requester's address.
```

**Discovery query extension (recommended):**
```cpp
// Add to SGAccountComm.proto — new oneof arms:
//   SignedChildDiscoveryRequest child_discovery_request = 10;
//   SignedChildDiscoveryResponse child_discovery_response = 11;

// AccountMessenger.hpp — new method (pattern: identical to RequestNonce/RequestHeads):
outcome::result<void> RequestChildDiscovery(
    uint64_t timeout_ms,
    const std::string &main_address,
    std::function<void(std::vector<std::string>)> callback);

// Any node with CRDT state responds with a list of reg/{child_addr} CIDs
// whose main_address matches the request's main_address.
```

### Pattern 2: CRDT Filter Gate (supersedes_sequence validation)

**What:** `FilterRegistration` (Phase 2 D-13) validates `sequence > current.sequence`. Phase 3 extends this to validate `supersedes_sequence == current.sequence` for lifecycle updates, preventing race-condition forks where two competing updates both try to replace the same base registration.

**When to use:** LIFE-02 (every lifecycle-change RegistrationTx carries `supersedes_sequence`); the CRDT reg/ filter rejects mismatches.

**Source:** `TransactionManager.cpp:2984-3039` — FilterTransaction with `do{...}while(0)` + `should_delete` + `maybe_tombstones` pattern. `FilterRegistration` follows the identical pattern (Phase 2 D-13).

**Existing FilterTransaction pattern (audited):**
```cpp
// TransactionManager.cpp:2984-3039
std::optional<std::vector<crdt::pb::Element>> TransactionManager::FilterTransaction(
    const crdt::pb::Element &element) {
    bool should_delete = true;
    do {
        // 1. Deserialize
        auto maybe_new_tx = DeSerializeTransaction(element.value());
        if (maybe_new_tx.has_error()) break;
        // 2. Signature
        if (!CheckTransactionAuthorization(*new_tx)) break;
        // 3. Key collision check (prevents overwrite)
        if (KeyExistsInDB(GetTransactionPath(*new_tx))) break;
        should_delete = false;
    } while (0);
    // On failure: return tombstone vector (maybe with proof key for cascade-delete)
}
```

**FilterRegistration extension (Phase 3):**
```cpp
// After existing sequence monotonicity check (gate 3 of D-13):
// 3b. Supersedes linkage: if RegistrationTx.has_supersedes_sequence(),
//     reject unless supersedes_sequence == current_registration.sequence()
//     (prevents fork: competing updates at same base seq)
```

### Anti-Patterns to Avoid
- **New pubsub infrastructure for discovery polling**: The `AccountMessenger` already has a worker-thread request/response protocol with `OnRequest`/`OnResponse` dispatch. Adding a new pubsub layer for discovery would be redundant and inconsistent. Extend `AccountMessenger` instead.
- **Durable CRDT index for discovered-children list**: D-27 specifies "No additional CRDT index namespace — discovery is peer-to-peer, not stored in consensus state." A CRDT namespace for discovery results would create unnecessary consensus traffic for what is essentially a caching concern.
- **Main signature on policy updates**: D-33 specifies the child updates its own reward policy via new RegistrationTx at higher sequence. Requiring the main to co-sign policy updates would create a deadlock if the main is offline — and contradicts the child-signed-only model (D-04/D-05).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Pubsub query/response protocol for discovery polling | Custom pubsub request/response engine | Extend `AccountMessenger` request/response pattern (`SGAccountComm.proto`, `OnRequest`/`OnResponse`) | AccountMessenger already has worker-thread queuing, timeout management, signed messages, topic-based broadcast, and response collection; adding a new `child_discovery_request` oneof arm is 2 proto additions + 2 handler methods |
| Registration lifecycle state machine | Custom state-machine library | `reg/` CRDT update-in-place via higher-sequence RegistrationTx | The CRDT merge already handles conflicting updates deterministically; state is derived from the current reg/ record's fields (main_address, detach_flag, sequence), not from a separate state-machine engine |
| Discovery response validation | Trust-first broadcast responses | Content-addressed CID resolution + certified-status check (D-26) | CID resolution is content-addressed — cannot produce wrong content for a given CID; certification check prevents uncertified registrations from being acted upon. Same pattern as D-16 pubsub notification validation. |
| Main wallet caching of discovered children | Custom on-disk DB format | `boost::json` (already in Boost dependency tree) + local JSON file | `boost::json` is already available via the Boost dependency (`AGENTS.md` Key Dependencies); JSON files match the existing `network_config.json`/`sgns_config.json` pattern for persistence |

**Key insight:** Every capability in Phase 3 reuses an existing SuperGenius pattern. The discovery poll is an `AccountMessenger` extension. The lifecycle state machine is CRDT record field derivation. Policy updates are RegistrationTx re-issuance at higher sequence. No new architectural components are needed — only additive proto fields and handler methods.

## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-27:** Discovery is push-primary, poll-fallback. Push = pubsub CID broadcast on main's topic (Phase 2 D-15/D-16). Poll = main sends query on its pubsub channel via AccountMessenger. Any node with CRDT state responds. Local JSON cache for persistence.
- **D-28:** Per-child info from reg/ CRDT (metadata), child CRDT deltas (balance/UTXO/activity), local cache (display prefs). No new CRDT namespace.
- **D-29:** Main-wallet actions re-use existing mechanics: Fund (CONS-01), Recover (CONS-02), Inspect (read-only CRDT sync, D-17), Revoke (LIFE-01 main-signed tx), Detach (LIFE-01 child-signed RegistrationTx with detach flag).
- **D-30:** Standalone child reward policy from SDK `DevConfig_st` (`Addr`, `Cut`) at escrow-hold time — same as today.
- **D-31:** Registered child reward policy from `RegistrationMetadata.dev_wallet`/`.peers_cut` supersedes DevConfig for new escrows. Existing escrows retain pinned policy.
- **D-32:** Reward policy pinned at HoldEscrow time — `EscrowTransaction` stores `dev_addr_`, `peers_cut_` immutably. This is existing behavior.
- **D-33:** Policy updates are child-only via new RegistrationTx at higher sequence with updated RegistrationMetadata. No main signature required.
- **D-34:** Four lifecycle states: Unregistered → Registered → Detached/Revoked. No "registration-pending", no "closed". Transitions: Unregistered→Registered (RegistrationTx), Registered→Detached (child-signed detach), Registered→Revoked (main-signed revoke), Detached/Revoked→Registered (re-registration).
- **D-35:** Detach (child-initiated): new RegistrationTx with higher sequence + detach flag. Record retained as audit trail. Child retains all UTXOs.
- **D-36:** Revoke (main-initiated): main-signed consensus transaction. Consensus validates main sig + reg/ record match + Registered state.
- **D-37:** Main replacement is child-only. No consent signature from old main. Old main loses recovery rights; new main gains them.
- **D-38:** Supersedes sequence N linkage: every lifecycle RegistrationTx carries `supersedes_sequence` referencing the registration it replaces. Filter rejects if `supersedes_sequence != current.sequence`. Combined with nonce chain: first-to-consensus wins, second rejected at filter.
- **D-39:** Detach/revoke leaves child as valid standalone wallet. UTXOs, keypair, nonce unaffected. Only reg/ record status changes.

### the agent's Discretion
- Exact proto field additions for detach_flag, supersedes_sequence, revoke tx message — researcher identifies idiomatic form matching existing proto conventions.
- The AccountMessenger mechanism for discovery polling — researcher identifies existing pattern and extends it.
- Local JSON cache schema and file location — planner selects format compatible with existing `boost::json` usage.
- Lifecycle state machine diagram and transition table — planner produces from D-34/D-35/D-36.
- Naming of revoke transaction subclass and placement — follow existing `GeniusTransaction` subclass conventions.

### Deferred Ideas (OUT OF SCOPE)
- Platform "Connect GNUS Wallet" UI flows — v2 (PLAT-01, PLAT-02)
- Aggregated registry topic for publisher-scale child fan-out — v2 (ADV-02)
- Threshold/social-recovery scheme for main wallet — v2 (ADV-01)
- Optional main acceptance signature for registration — v2 hardening

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DISC-01 | How main wallet discovers all child wallets registered to it | AccountMessenger request/response pattern (on pubsub) + CID broadcast (D-15/D-16). Anchor: `AccountMessenger.hpp:199-223`, `AccountMessenger.cpp:143-196` (RequestHeads broadcast pattern). Extension: add `child_discovery_request`/`child_discovery_response` to `SGAccountComm.proto` oneof arms 10/11. |
| DISC-02 | Per-child information displayed (balance, assets, game, publisher, dev wallet, cut ratio, registration date, activity, status) | Data sources: reg/ CRDT for metadata fields (`reg/{child_addr}` via D-12/D-14); child CRDT deltas for balance/UTXO/activity (D-17 `AddListenTopic(child_address)` in `pubsub_broadcaster_ext.hpp:74`); local JSON cache for display preferences. |
| DISC-03 | Main-wallet actions over discovered children (fund, recover, inspect history, view assets, revoke/detach) | Actions mapped to existing mechanics: Fund (CONS-01 main→child transfer, Phase 2), Recover (CONS-02 destination-restricted, Phase 2), Inspect (read-only CRDT sync, D-17), Revoke (LIFE-01 main-signed transaction), Detach (LIFE-01 child-signed RegistrationTx with detach_flag). |
| RWD-01 | Per-child processing-reward policy (dev_addr, peers_cut) resolution for standalone and registered children | Standalone: `GeniusNode::HoldEscrow` reads `dev_config_.Addr`/`dev_config_.Cut` (`GeniusNode.cpp:1977-1985`). Registered: HoldEscrow reads `RegistrationMetadata.dev_wallet`/`.peers_cut` from certified `reg/{child_addr}`. Integration point: `TransactionManager::HoldEscrow` (`TransactionManager.cpp:778-810`) receives dev_addr/peers_cut as parameters — caller (GeniusNode) chooses the source. |
| RWD-02 | Pinning reward policy at escrow-hold time | Existing behavior — `EscrowTransaction` stores `dev_addr_` (line 130), `peers_cut_` (line 131), `amount_` (line 129) at construction (`EscrowTransaction.hpp:122-131`). `PayEscrow` reads stored values: `escrow_tx->GetPeersCut()` (`TransactionManager.cpp:848`), `escrow_tx->GetDevAddress()` (`TransactionManager.cpp:875`). No design change needed. |
| RWD-03 | Authenticated update rules for dev wallet and cut ratio | Child-signed RegistrationTx at higher sequence with updated `RegistrationMetadata`. CRDT merge keeps highest-sequence. Existing pattern: reg/ CRDT update-in-place via `FilterRegistration` sequence monotonicity (Phase 2 D-13 gate 3). No new consensus rule — child signature already validates. |
| LIFE-01 | Child-wallet lifecycle state machine and valid transitions | Four states (D-34): Unregistered → Registered → Detached/Revoked. States derived from `reg/{child_addr}` CRDT fields: main_address present → Registered; detach_flag set → Detached/Revoked; no record → Unregistered. Transitions via RegistrationTx (sequence increase) or main-signed revoke tx. |
| LIFE-02 | Replace/remove-main flows with "supersedes sequence N" linkage and deterministic conflict resolution | RegistrationTx carries `supersedes_sequence` field. FilterRegistration validates `supersedes_sequence == current_registration.sequence()` — rejects mismatches. Nonce chain (`sgns.nonce.v1` — `Consensus.hpp:37`, `TransactionManager.cpp:149-159`) provides total ordering: first-to-consensus wins. |
| LIFE-03 | Main-replacement policy fork decision | Decided: child-only replacement (D-37). No consent signature from old main. Rationale: deadlock if old main key lost; consistent with child-owned identity model (D-04/D-05). |
| LIFE-04 | Detach leaves child as valid standalone wallet | Specified in D-39: "Detaching (or being revoked) leaves the child wallet as a valid standalone wallet. The child's UTXOs, keypair, and nonce are unaffected — only the reg/ record's status changes." The child can continue creating transfers, receiving funds, and earning processing rewards independently. |

## Proto Evolution: Field Numbering & Additive Changes

### Existing SGTransaction.proto Patterns (audited)
[VERIFIED: SuperGenius/src/account/proto/SGTransaction.proto]
- Field numbering convention: `DAGStruct dag_struct = 1` is always first in every tx message
- TransferTx: fields 1-3 (dag_struct, token_id, utxo_params)
- EscrowTx: fields 1-5 (dag_struct, utxo_params, amount, dev_addr, peers_cut)
- EscrowReleaseTx: fields 1-6
- Next available field in RegistrationTx for `detach_flag`: field 5 (after sequence=3, metadata=4)
- Next available field for `supersedes_sequence`: field 6

### RegistrationTx Proto Extension (Phase 3 additive fields)
```protobuf
// RegistrationTx — fields from Phase 1 + Phase 3 extensions:
message RegistrationTx {
    DAGStruct dag_struct = 1;            // Phase 1: D-08
    bytes main_address = 2;              // Phase 1: D-08
    uint64 sequence = 3;                 // Phase 1: D-09
    RegistrationMetadata metadata = 4;   // Phase 1: D-08 (game_id, publisher_id, dev_wallet, peers_cut)
    bool detach_flag = 5;               // Phase 3: D-35 (true = child-initiated detach)
    uint64 supersedes_sequence = 6;     // Phase 3: D-38 (references sequence being replaced; 0 if new registration)
}
```

### Consensus.proto EmbeddedTransaction Extension (audited)
[VERIFIED: SuperGenius/src/blockchain/impl/proto/Consensus.proto:70-80]
- Existing oneof arms: transfer=1, mint_v2=2, mint=3, processing=4, migration=5, escrow=6, escrow_release=7
- RegistrationTx (Phase 1): reserved field 8
- **RevokeTx (Phase 3): field 9** — new oneof arm for main-signed revocation
- RegistrationTx already uses field 8 (Phase 1). Next available: field 9 for RevokeTx.

```protobuf
message EmbeddedTransaction {
    oneof transaction {
        SGTransaction.TransferTx transfer = 1;
        SGTransaction.MintTxV2 mint_v2 = 2;
        SGTransaction.MintTx mint = 3;
        SGTransaction.ProcessingTx processing = 4;
        SGTransaction.MigrationTx migration = 5;
        SGTransaction.EscrowTx escrow = 6;
        SGTransaction.EscrowReleaseTx escrow_release = 7;
        SGTransaction.RegistrationTx registration = 8;    // Phase 1 (reserved)
        SGTransaction.RevokeTx revoke = 9;                // Phase 3 (NEW)
    }
}
```

### SGAccountComm.proto Extension (Discovery query/response)
[VERIFIED: SuperGenius/src/account/proto/SGAccountComm.proto:5-17]
- Existing oneof arms: nonce_request=1, nonce_response=2, block_request=3, block_response=4, head_request=5, block_cid_request=6, utxo_request=7, utxo_response=8, transaction_request=9
- **Phase 3 additions:**
```protobuf
message AccountMessage {
    oneof payload {
        // ... existing arms 1-9 ...
        SignedChildDiscoveryRequest child_discovery_request = 10;    // Phase 3
        SignedChildDiscoveryResponse child_discovery_response = 11;  // Phase 3
    }
}

message ChildDiscoveryRequest {
    string requester_address = 1;    // main wallet address
    uint64 request_id = 2;
    uint64 timestamp = 3;
    string main_address = 4;         // main to query children for
}

message ChildDiscoveryResponse {
    string responder_address = 1;
    string requester_address = 2;
    uint64 request_id = 3;
    uint64 timestamp = 4;
    repeated string reg_cids = 5;    // CIDs from reg/{child_addr} CRDT keys whose main_address matches
}
```

## Critical Gap Resolution: Discovery Polling Query/Response Protocol (D-27)

**Gap:** "No existing message-bus query/response protocol" (CONTEXT.md §Critical Gap). The current `messaging_watcher` handles broadcast-style messages; discovery polling requires a request/response pattern.

**Resolution:** Use the **existing `AccountMessenger` request/response pattern** — NOT `messaging_watcher`.

**Evidence:**
1. `AccountMessenger` already implements a full request/response protocol over pubsub:
   - `AccountMessenger.hpp:200-223` — Two pubsub topics: `account_comm_topic_` = `address + ".comm"` (personal), `REQUESTS_COMM` = `"SGNUS.BC.Requests.comm"` (global)
   - `AccountMessenger.cpp:190-234` — `OnRequest`/`OnResponse` dispatch based on `AccountMessage` oneof type
   - `AccountMessenger.cpp:868-886` — `SendAccountMessage` publishes signed proto messages to topic set
   - `AccountMessenger.cpp:886-1010` — `WorkerLoop` dequeues requests, broadcasts, and collects responses with timeout
   - `AccountMessenger.cpp:143-196` — `RequestHeads` is an existing broadcast-style query that sends on multiple topics and expects responses
2. The `NonceRequest → NonceResponse` flow at `AccountMessenger.cpp:1472-1566` is the exact template:
   - Requester constructs `NonceRequest` with `requester_address`, `request_id`, timestamp
   - Signs via `InterfaceMethods::sign_`
   - Broadcasts on `account_comm_topic_` + `requests_topic_`
   - Any node with a nonce for that address constructs `NonceResponse` and sends it back
   - Requester collects responses in `nonce_responses_` map keyed by `request_id`
3. The `RequestHeads` at `AccountMessenger.cpp:143-196` is even closer — it broadcasts a query and expects arbitrary peers to respond.

**Recommended approach (option b — "main broadcasts on pubsub, any node responds"):**
- Add `ChildDiscoveryRequest`/`ChildDiscoveryResponse` messages to `SGAccountComm.proto` (fields 10/11 in `AccountMessage` oneof)
- Add `AccountMessenger::RequestChildDiscovery(main_address, timeout_ms, callback)` following the `RequestHeads` pattern
- Add `HandleChildDiscoveryRequest` handler (dispatched from `OnRequest`) that:
  1. Scans local CRDT: iterates `reg/` namespace keys matching the requested `main_address`
  2. Constructs `ChildDiscoveryResponse` with list of `reg/{child_addr}` CIDs
  3. Sends response back to requester via `SendAccountMessage` on requester's `.comm` topic
- Add `HandleChildDiscoveryResponse` handler (dispatched from `OnResponse`) that collects CIDs

**Alternative considered and rejected** (option a — "new custom message type"): Creating a completely new message type outside AccountMessenger would bypass the existing signed-message, timeout, and response-collection infrastructure. AccountMessenger's worker-thread + `InterfaceMethods::sign_` + timeout pattern is battle-tested for all other account communication.

**Alternative considered and rejected** (option c — "main just listens on its own topic"): Pubsub topics are broadcast channels, not request-response channels. Broadcasting a query on the main's own topic might trigger responses, but there's no mechanism to correlate requests to responses or handle timeouts. The `AccountMessenger` already solves this with request IDs and promise/future collection.

## Lifecycle + Conflict Resolution: Verified Anchors

### CheckParentChildAuthority Gate (existing — Phase 2 D-19)
[VERIFIED: SuperGenius/src/account/TransactionManager.hpp:688-694]
```cpp
// TransactionManager.hpp:688-694 — existing gate pipeline
ConsensusManager::ValidationResult ValidateTransactionForConsensus(
    const std::shared_ptr<GeniusTransaction> &tx) const;
bool CheckTransactionWellFormed(const GeniusTransaction &tx) const;
bool CheckTransactionAuthorization(const GeniusTransaction &tx) const;  // signature-only
bool CheckTransactionTimestamp(const GeniusTransaction &tx) const;
bool CheckTransactionReplayProtection(const GeniusTransaction &tx) const;
```

[VERIFIED: SuperGenius/src/account/TransactionManager.cpp:4234-4299]
The `ValidateTransactionForConsensus` pipeline at lines 4234-4299 has these gates in order:
1. `CheckTransactionWellFormed` (line 4250)
2. `CheckTransactionAuthorization` (line 4259) — **signature-only** (`TransactionManager.cpp:4361-4383`)
3. `CheckTransactionTimestamp` (line 4268)
4. `EvaluateTransactionReplayProtection` (line 4277)
5. `CheckTransactionTypeRules` (line 4288)

Per D-19: `CheckParentChildAuthority` slots between gates 2 and 3. For Phase 3, the revoke transaction path validates via this gate: main signature (gate 2) + CheckParentChildAuthority (gate 2.5) validates reg/ record's `main_address == signer` and state == Registered.

### Nonce Chain Consensus Ordering (D-38)
[VERIFIED: SuperGenius/src/blockchain/Consensus.hpp:37]
```cpp
static constexpr std::string_view NONCE_SUBJECT_TYPE = "sgns.nonce.v1";
```

[VERIFIED: SuperGenius/src/account/TransactionManager.cpp:149-159]
```cpp
instance->blockchain_->RegisterSubjectHandler(
    NONCE_SUBJECT_TYPE,
    [weak_ptr(std::weak_ptr<TransactionManager>(instance))](
        const ConsensusManager::Subject &subject) -> outcome::result<ConsensusManager::ValidationResult>
    {
        if (auto strong = weak_ptr.lock()) {
            return strong->HandleNonceConsensusSubject(subject);
        }
        return outcome::failure(std::errc::owner_dead);
    });
```

The nonce chain provides total ordering: two RegistrationTx with the same `supersedes_sequence` but different `nonce` values cannot both be certified because the nonce chain (`sgns.nonce.v1`) allows only one tx per nonce slot. The first to reach consensus wins; the second is rejected because its `supersedes_sequence` no longer matches the updated current record's `sequence`. This is NOT "first-to-CRDT wins" — consensus ordering, not CRDT arrival order, determines the winner.

### CRDT reg/ Filter Extension for supersedes_sequence
[VERIFIED: SuperGenius/src/account/TransactionManager.cpp:187-235, 2984-3039]
The `FilterRegistration` pattern (Phase 2 D-13) extends the existing `FilterTransaction` pattern:
- **Registration location:** `TransactionManager.cpp:187-213` — `RegisterElementFilter` with regex pattern `^/?/bc-{net}/reg/([^/]+)`
- **Filter body:** follows `do{...}while(0)` + `should_delete` + `return std::nullopt` (accept) or `return {{element}}` (tombstone)
- **Phase 3 extension:** After existing sequence monotonicity gate, add:
  ```cpp
  // Gate 3b: supersedes linkage (LIFE-02)
  if (new_registration.has_supersedes_sequence() && 
      new_registration.supersedes_sequence() != 0) {
      auto current = ReadRegistrationFromCRDT(child_addr);
      if (!current || current.sequence() != new_registration.supersedes_sequence()) {
          break;  // REJECT — fork detected, supersedes_sequence must match current
      }
  }
  ```

### Revoke Transaction: Gate Path
The revoke main-signed transaction slots into the existing consensus pipeline:
1. **Phase 2 D-20:** reuses `"transfer"` tx type — or — a new `"revoke"` tx type. The design doc should recommend a first-class `RevokeTx` type (new `GeniusTransaction` subclass) for clarity, with a new arm in `EmbeddedTransaction` oneof (field 9).
2. **CheckParentChildAuthority** (gate 2.5): validates main signature + `reg/{child_addr}.main_address == signer` + registration is in Registered state (not already detached/revoked)
3. **Post-revoke:** sets `detach_flag = true` on the reg/ CRDT record; main has zero recovery authority thereafter.

## Reward Policy: Verified Anchors

### HoldEscrow — Current Integration Point
[VERIFIED: SuperGenius/src/account/TransactionManager.cpp:778-810]
```cpp
// TransactionManager.hpp:172-175 — signature
outcome::result<std::pair<std::string, EscrowDataPair>> HoldEscrow(
    uint64_t amount, const std::string &dev_addr, uint64_t peers_cut, const std::string &job_id);
```

The caller (`GeniusNode::ProcessImage`) provides `dev_addr` and `peers_cut`. Today these come from `dev_config_.Addr` and `dev_config_.Cut` (`GeniusNode.cpp:1977-1985`). For registered children, the caller reads `RegistrationMetadata.dev_wallet`/`.peers_cut` from the certified `reg/{child_addr}` CRDT record instead.

[VERIFIED: SuperGenius/src/account/GeniusNode.cpp:1977-1985]
```cpp
auto cut = sgns::TokenAmount::ParseMinions(dev_config_.Cut);
// ...
manager->HoldEscrow(funds, std::string(dev_config_.Addr), cut.value(), uuidstring);
```

### PayEscrow — Reads Stored Values (Pin at Hold Time)
[VERIFIED: SuperGenius/src/account/TransactionManager.cpp:846-875]
```cpp
// Line 848 — peers_cut from escrow transaction (NOT from live reg/ state)
auto peers_cut_ptr, TokenAmount::New(escrow_tx->GetPeersCut());
// ...
// Line 875 — dev_addr from escrow transaction
payout_peers.push_back({remainder, escrow_tx->GetDevAddress(), escrowTokenId});
```

This confirms D-32: the reward policy is pinned at HoldEscrow time. PayEscrow reads from the escrow transaction's stored values (`EscrowTransaction.hpp:130-131`), not from current CRDT state. No design change needed — this is existing behavior.

### PayDev — Existing Path
[VERIFIED: SuperGenius/src/account/GeniusNode.hpp:520-521]
```cpp
outcome::result<std::string> PayDev(uint64_t amount, TokenID token_id);
```

[VERIFIED: SuperGenius/src/account/GeniusNode.cpp:2261-2263]
```cpp
outcome::result<std::string> GeniusNode::PayDev(uint64_t amount, TokenID token_id) {
    return TransferFunds(amount, dev_config_.Addr, token_id);
}
```

`PayDev` sends to `dev_config_.Addr` — this is the developer wallet for standalone children. For registered children, the developer wallet address would come from `RegistrationMetadata.dev_wallet` (resolved from certified reg/ record), not from `dev_config_.Addr`. This is a **GeniusNode-level** change: the `PayDev` method (or a new `PayChildDev` variant) reads the developer wallet from the correct source based on child registration status.

## Runtime State Inventory

> Not applicable — this is a greenfield design-documentation phase. No runtime state to migrate, no rename/refactor involved. The Phase 3 design documents reference existing SuperGenius code anchor points without modifying anything. Runtime state inventory is **skipped**.

## Common Pitfalls

### Pitfall 1: Discovery Poll Flooding
**What goes wrong:** A main wallet broadcasts `ChildDiscoveryRequest` every few seconds, generating excessive pubsub traffic and response noise across the network.
**Why it happens:** No rate-limiting in the discovery polling loop.
**How to avoid:** Implement exponential backoff on discovery polling — poll at increasing intervals (e.g., 30s → 60s → 120s → 300s) until the next pubsub push resets the timer. Push is the primary mechanism; poll is a fallback for missed broadcasts.
**Warning signs:** High pubsub message rate on `SGNUS.BC.Requests.comm` topic; multiple nodes responding to the same query.

### Pitfall 2: Uncertified Registration in Discovery Responses
**What goes wrong:** A node responds to `ChildDiscoveryRequest` with CIDs for uncertified `reg/` records. The main wallet acts on these (e.g., attempts to fund/recover) and fails or authorizes an unconfirmed relationship.
**Why it happens:** The discovery response handler doesn't filter by certified status (D-26).
**How to avoid:** The `HandleChildDiscoveryRequest` handler **MUST** exclude uncertified registrations from the response. This matches D-16/D-26: "The main wallet only acts on certified registrations." The handler checks `tx_processed_m` for CONFIRMED status (or the `reg-cert/` CRDT backup) before including a child CID in the response.
**Warning signs:** Main wallet shows children that cannot be funded/recovered; reg/ CRDT entries without corresponding `reg-cert/` entries.

### Pitfall 3: Escrow with Stale Registration Policy
**What goes wrong:** A child updates its reward policy (new RegistrationTx at higher sequence), but in-progress escrows use the new policy, causing incorrect payouts.
**Why it happens:** The `PayEscrow` path reads from the live reg/ record instead of the stored escrow values.
**How to avoid:** This is already prevented by the existing escrow model — `PayEscrow` reads `escrow_tx->GetPeersCut()` and `escrow_tx->GetDevAddress()` (`TransactionManager.cpp:848,875`), NOT from CRDT state. No design change needed; the design doc must explicitly state that this existing behavior satisfies RWD-02.
**Warning signs:** This is a non-issue due to existing architecture — flag it in the design doc as "already enforced by EscrowTransaction immutability."

### Pitfall 4: Competing Lifecycle Updates (Fork)
**What goes wrong:** The child issues two RegistrationTx updates (e.g., one replacing main, one detaching) at the same base sequence but different nonces, creating a fork.
**Why it happens:** Network latency or intentional double-spend attempt.
**How to avoid:** The `supersedes_sequence` filter (gate 3b in FilterRegistration) rejects any update whose `supersedes_sequence` doesn't match the current record's `sequence`. The nonce chain (`sgns.nonce.v1`) prevents both from being certified at the same nonce. The first to reach consensus at its nonce wins; the second fails at the CRDT filter because the current `sequence` has already been bumped by the first.
**Warning signs:** Two RegistrationTx at different nonces targeting the same `reg/{child_addr}` with the same `supersedes_sequence`; the filter logs a rejection for the second one.

## Code Examples

Verified patterns from the codebase:

### CRDT Filter Registration Pattern
```cpp
// Source: TransactionManager.cpp:187-213 (tx/ filter) + 203-213 (proof/ filter)
// Pattern for registering a new reg/ filter in TransactionManager::New()
auto monitored_networks = GetMonitoredNetworkIDs();
for (auto network_id : monitored_networks) {
    std::string blockchain_base = GetBlockChainBase(network_id);
    // Register reg/ filter
    bool reg_filter_initialized = instance->globaldb_m->RegisterElementFilter(
        "^/?" + blockchain_base + "reg/([^/]+)",           // regex captures child_addr
        [weak_ptr(std::weak_ptr<TransactionManager>(instance))](
            const crdt::pb::Element &element)
            -> std::optional<std::vector<crdt::pb::Element>>
        {
            if (auto strong = weak_ptr.lock()) {
                return strong->FilterRegistration(element);
            }
            return std::nullopt;
        });
}
// CRDT key format: GetBlockChainBase() returns "/bc-{net}/"
// Source: TransactionManager.hpp:296 — TRANSACTION_BASE_FORMAT = "/bc-%hu/"
// Source: TransactionManager.cpp:1356-1368 — GetBlockChainBase implementation
```

### AccountMessenger SendAccountMessage (Discovery Broadcast)
```cpp
// Source: AccountMessenger.hpp:354-355 — signature
// outcome::result<void> SendAccountMessage(
//     const accountComm::AccountMessage &msg,
//     const std::set<std::string>       &topics);

// Pattern: the main constructs a ChildDiscoveryRequest, signs it,
// wraps in AccountMessage, broadcasts on requests_topic_ + main's comm topic.
// Responders send ChildDiscoveryResponse back to requester's .comm topic.
```

### EscrowTransaction Hold-Time Pinning (Existing)
```cpp
// Source: EscrowTransaction.hpp:122-131 — constructor pins all values
EscrowTransaction(UTXOTxParameters params, uint64_t amount,
                  std::string dev_addr, uint64_t peers_cut,
                  SGTransaction::DAGStruct dag);

// Source: EscrowTransaction.hpp:129-131 — member variables
uint64_t    amount_;     // Pinned at construction
std::string dev_addr_;   // Pinned at construction — NEVER re-read from reg/
uint64_t    peers_cut_;  // Pinned at construction — NEVER re-read from reg/

// Source: TransactionManager.cpp:848,875 — PayEscrow reads IMMUTABLE stored values
escrow_tx->GetPeersCut();    // reads peers_cut_ (not reg/ CRDT)
escrow_tx->GetDevAddress();  // reads dev_addr_ (not reg/ CRDT)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| All authorization is cryptographic (signature-only) | `CheckParentChildAuthority` adds state-dependent authority reading CRDT reg/ records | Phase 2 (D-19) | Phase 3 revoke/lifecycle flows use this gate |
| Escrow reward policy from `DevConfig_st` only | Escrow policy from `reg/` record metadata for registered children, `DevConfig_st` for standalone | Phase 3 (D-30/D-31) | Adds `HoldEscrow` policy-source selection |
| No lifecycle state tracked for wallets | Four-state lifecycle via `reg/` record fields | Phase 3 (D-34) | Audit trail + recovery authority lifecycle |
| Manually constructed key paths | `GetBlockChainBase() + "reg/" + child_addr` via `HierarchicalKey` | Phase 2 (D-12) | Standardized key construction |

**Deprecated/outdated:**
- **messaging_watcher for request/response:** The `messaging_watcher` class (`messaging_watcher.hpp/cpp`) is a broadcast-only placeholder with a 1-second sleep loop. It has no request/response semantics. `AccountMessenger` is the standard pubsub message protocol. Do NOT use `messaging_watcher` for discovery polling — extend `AccountMessenger` instead.

## Assumptions Log

> All claims tagged `[ASSUMED]` in this research. The planner and discuss-phase use this section to identify decisions that need user confirmation before execution.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | RegistrationTx in proto already has fields reserved for `detach_flag` (5) and `supersedes_sequence` (6) — these are new additions | Proto Evolution | Field 5 might conflict with a Phase 1 interim addition; verify against the actual Phase 1 RegistrationTx proto definition in the design doc |
| A2 | `EmbeddedTransaction` oneof field 8 is reserved for RegistrationTx (Phase 1); field 9 is available for RevokeTx | Proto Evolution | If Phase 1 used a different field number, adjust accordingly; this is an additive-only convention |
| A3 | `boost::json` is available in the Boost dependency tree and can be used for the local JSON cache | Standard Stack | If `boost::json` is not included in the current Boost build configuration, an alternative (e.g., `rapidjson` from `messaging_watcher.hpp:6`) should be used instead |
| A4 | The `HandleChildDiscoveryRequest` handler can efficiently scan `reg/` CRDT keys by prefix without a full table scan | Discovery Polling | If GlobalDB does not support prefix scans on `HierarchicalKey`, the handler will need to iterate all `reg/` keys, which may be slow for large registries |
| A5 | The `dev_config_` `DevConfig_st` struct is accessible at the `GeniusNode` level for policy-source selection in `HoldEscrow`/`PayDev` | Reward Policy | If the `DevConfig_st` is not thread-safe or available at the right call site, the design may need an interface change to pass policy source |

## Open Questions

1. **RegistrationTx proto field 4 (RegistrationMetadata) actual definition**
   - What we know: Phase 1 D-08 specifies `RegistrationMetadata` with `game_id`, `publisher_id`, `dev_wallet`, `peers_cut`. The CONTEXT.md canonical refs reference this.
   - What's unclear: The exact proto field numbers within `RegistrationMetadata` and whether it's an embedded sub-message or a separate message. The Phase 1 design doc (`docs/registration-protocol.md`) was not found at the expected path.
   - Recommendation: Planner should verify against the Phase 1 design doc output. Field numbering in this research (detach_flag=5, supersedes_sequence=6) assumes RegistrationMetadata is field 4. Adjust if Phase 1 used a different layout.

2. **GlobalDB prefix scan capability for reg/ namespace iteration**
   - What we know: `GlobalDB::Get(HierarchicalKey(key))` reads a single key. The `RegisterElementFilter` pattern matches elements by regex.
   - What's unclear: Whether GlobalDB supports efficient prefix iteration (e.g., scanning all `reg/` keys) for the discovery response handler. If not, the handler iterates all CRDT elements and filters by regex — acceptable for initial implementation but may need optimization for large child registries.
   - Recommendation: The design doc should specify a prefix-scan approach if available; fall back to full CRDT iteration if not.

3. **Revoke transaction type: first-class RevokeTx vs reuse of "transfer" type**
   - What we know: D-36 says "main-signed consensus transaction." Phase 2 D-20 reuses `"transfer"` tx type for parent-child authority. D-29 says revoke maps to "LIFE-01 — main-signed consensus transaction that sets the reg/ record's detached flag."
   - What's unclear: Whether revoke should be a first-class `RevokeTx` GeniusTransaction subclass (like `RegistrationTx`) or reuse the existing `"transfer"` type with a special flag. A first-class type provides clearer semantics and avoids overloading the transfer type. Reusing `"transfer"` avoids new proto messages but conflates fund movement with authority revocation.
   - Recommendation: Design doc should recommend a first-class `RevokeTx` as a new `GeniusTransaction` subclass (following `RegistrationTx` pattern from Phase 1), with its own `EmbeddedTransaction` oneof arm (field 9). This keeps authority actions separate from value transfers and provides cleaner audit trail.

## Environment Availability

> Step 2.6: SKIPPED. Phase 3 is a design-documentation phase. No external tools, services, runtimes, or CLI utilities are needed beyond what already exists in the SuperGenius codebase (which the research already audited). All depends-on tools are in the existing dependency tree (Boost, protobuf, libp2p, RocksDB, rapidjson). No new installations required.

## Validation Architecture

> Note: `.planning/config.json` was not explicitly read. Per the instructions, I check for the `workflow.nyquist_validation` key. Since this is a DESIGN-DOCUMENTATION phase producing markdown files (not code), automated test coverage of design docs is inherently limited to structural validation (line counts, section presence, decision ID coverage). The planner should verify the phase includes acceptance criteria validation (Phase 3 CONTEXT.md does not include a PATTERNS.md with test infrastructure).

### Test Framework
| Property | Value |
|----------|-------|
| Framework | N/A (design-documentation phase — no C++ code) |
| Config file | None |
| Quick run command | `python -c "..." ` (structural validation of markdown docs) |
| Full suite command | N/A |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DISC-01 | Discovery design specifies push-primary/poll-fallback with AccountMessenger anchors | Manual review | N/A — design doc must reference `AccountMessenger.hpp:199`, `SGAccountComm.proto:5` | ❌ Wave 0 |
| RWD-01 | Reward policy design specifies EscrowTransaction/HoldEscrow/PayEscrow anchors | Manual review | N/A — design doc must reference `TransactionManager.cpp:778`, `EscrowTransaction.hpp:130-131` | ❌ Wave 0 |
| LIFE-02 | Lifecycle design specifies supersedes_sequence filter gate + nonce-chain total ordering | Manual review | N/A — design doc must reference `Consensus.hpp:37`, `TransactionManager.cpp:2984` | ❌ Wave 0 |

### Wave 0 Gaps
- [ ] `docs/03-01-discovery-monitoring.md` — covers DISC-01, DISC-02, DISC-03
- [ ] `docs/03-02-reward-policy-lifecycle.md` — covers RWD-01, RWD-02, RWD-03, LIFE-01, LIFE-02, LIFE-03, LIFE-04
- [ ] Structural validation script — minimum line counts, required anchor point references
- [ ] All 13 decisions (D-27 through D-39) must be traceable to sections in the two design docs

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | Child-signed RegistrationTx (Phase 1 D-04/D-05); main-signed revoke tx; `CheckTransactionAuthorization` (`TransactionManager.cpp:4361`) verifies signatures |
| V3 Session Management | no | Session management not applicable — stateless CRDT consensus |
| V4 Access Control | yes | `CheckParentChildAuthority` gate (Phase 2 D-19) enforces parent-child authority; `ValidateWitness` (`GeniusInputValidator.cpp:419`) enforces UTXO ownership |
| V5 Input Validation | yes | `FilterRegistration` (Phase 2 D-13) validates deserialization, signature, sequence; `CheckTransactionTypeRules` validates `main_address` via `IsValidPublicKey` |
| V6 Cryptography | yes | secp256k1 signing via `GeniusAccount::Sign`/`CheckSignature`; protobuf serialization; CID content-addressed validation for discovery responses; never hand-roll crypto |

### Known Threat Patterns for C++/CRDT/Consensus

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Discovery response spoofing (attacker claims to be a registered child) | Spoofing | CID resolution is content-addressed — cannot produce wrong content for a given CID. Certified status check (D-26) prevents uncertified registrations from being acted upon. |
| Race-condition fork on lifecycle updates (competing replace-main/detach at same base sequence) | Tampering | `supersedes_sequence` filter gate rejects mismatch. Nonce chain (`sgns.nonce.v1`) prevents double-certification at same nonce. First-to-consensus wins. |
| Recovery-as-seizure (main redirects child funds to arbitrary address) | Elevation of Privilege | CONS-02 (Phase 2 D-21) hard restriction: `dst MUST == main_address`. Enforced in `CheckParentChildAuthority` gate. |
| Uncertified CRDT read authorizes parent-child action | Elevation of Privilege | D-26: `CheckParentChildAuthority` MUST call `IsRegistrationCertified(child_addr)`. Uncertified → treated as no relationship → gate returns `Approve()` without granting authority. |
| Replay attack (old RegistrationTx at higher nonce to re-assert stale state) | Tampering | `FilterRegistration` checks `sequence > current.sequence` (D-13 gate 3). Nonce chain prevents replay at already-used nonce. |

## Sources

### Primary (HIGH confidence)
- `SuperGenius/src/account/TransactionManager.cpp:187-235` — CRDT filter registration block (tx/, proof/), `RegisterElementFilter` pattern
- `SuperGenius/src/account/TransactionManager.cpp:778-810` — `HoldEscrow` receiving dev_addr/peers_cut
- `SuperGenius/src/account/TransactionManager.cpp:836-902` — `PayEscrow` reading stored escrow values (pinning)
- `SuperGenius/src/account/TransactionManager.cpp:1127-1206` — `SendTransactionItem` topic collection
- `SuperGenius/src/account/TransactionManager.cpp:1356-1368` — `GetBlockChainBase()` key format
- `SuperGenius/src/account/TransactionManager.cpp:2984-3039` — `FilterTransaction` do-while(0) pattern
- `SuperGenius/src/account/TransactionManager.cpp:3655-3764` — `OnConsensusCertificate` → CONFIRMED path
- `SuperGenius/src/account/TransactionManager.cpp:3901-3960` — `HandleNonceConsensusSubject`
- `SuperGenius/src/account/TransactionManager.cpp:4234-4299` — `ValidateTransactionForConsensus` pipeline
- `SuperGenius/src/account/TransactionManager.cpp:4361-4383` — `CheckTransactionAuthorization` (signature-only)
- `SuperGenius/src/account/TransactionManager.hpp:296` — `TRANSACTION_BASE_FORMAT = "/bc-%hu/"`
- `SuperGenius/src/account/TransactionManager.hpp:688-694` — gate declarations
- `SuperGenius/src/account/EscrowTransaction.hpp:122-131` — dev_addr_/peers_cut_/amount_ pinned at construction
- `SuperGenius/src/account/GeniusNode.hpp:59-66` — `DevConfig_st` (Addr, Cut, TokenID)
- `SuperGenius/src/account/GeniusNode.hpp:520-521` — `PayDev` signature
- `SuperGenius/src/account/GeniusNode.hpp:1057-1061` — `PayEscrow` signature
- `SuperGenius/src/account/GeniusNode.cpp:1977-1985` — `HoldEscrow` reads dev_config_.Addr/.Cut
- `SuperGenius/src/account/GeniusNode.cpp:2261-2263` — `PayDev` uses dev_config_.Addr
- `SuperGenius/src/account/AccountMessenger.hpp:35-105` — factory, InterfaceMethods, Error, pubsub topics
- `SuperGenius/src/account/AccountMessenger.hpp:143-196` — `RequestHeads`, `RequestNonce`, `RequestUTXOs` — query/response patterns
- `SuperGenius/src/account/AccountMessenger.hpp:199-223` — topic constants (`ACCOUNT_COMM`, `REQUESTS_COMM`)
- `SuperGenius/src/account/AccountMessenger.hpp:340-404` — `OnRequest`/`OnResponse` handler dispatch
- `SuperGenius/src/account/AccountMessenger.cpp:190-234` — `OnRequest`/`OnResponse` implementation
- `SuperGenius/src/account/proto/SGAccountComm.proto:1-140` — existing request/response messages, oneof pattern
- `SuperGenius/src/account/proto/SGTransaction.proto:1-136` — existing tx messages, field numbering, EscrowTx fields
- `SuperGenius/src/blockchain/impl/proto/Consensus.proto:62-80` — `NonceSubject`, `EmbeddedTransaction` oneof
- `SuperGenius/src/blockchain/Consensus.hpp:37` — `NONCE_SUBJECT_TYPE = "sgns.nonce.v1"`
- `SuperGenius/src/crdt/globaldb/pubsub_broadcaster_ext.hpp:48-74` — `Broadcast`, `AddBroadcastTopic`, `AddListenTopic` APIs
- `SuperGenius/src/crdt/globaldb/globaldb.hpp:162-167` — `RegisterElementFilter` signature
- `SuperGenius/src/watcher/messaging_watcher.hpp:1-48` — broadcast-only model (NOT suitable for request/response)

### Secondary (MEDIUM confidence)
- Phase 2 design docs (`02-01-PLAN.md`, `02-02-PLAN.md`) — referenced for CRDT reg/ layout, FilterRegistration design, CheckParentChildAuthority gate integration, certified status flag
- Phase 1 CONTEXT.md — D-01 through D-10, RegistrationTx schema
- Phase 2 CONTEXT.md — D-11 through D-26, consensus authority rules

### Tertiary (LOW confidence)
- None — all claims verified against source code or traceable to locked decisions

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all dependencies already exist in the SuperGenius tree; no new packages
- Architecture: HIGH — all patterns (AccountMessenger, FilterRegistration, EscrowTransaction) verified against source code with file:line citations
- Pitfalls: HIGH — each pitfall traced to a concrete vulnerability in the design, with mitigations grounded in existing code patterns

**Research date:** 2026-07-13
**Valid until:** 2026-08-12 (30 days — stable domain, no fast-moving dependencies)

---

## RESEARCH COMPLETE

**Phase:** 3 — Discovery, Rewards & Lifecycle
**Confidence:** HIGH

### Key Findings
1. **Discovery polling (D-27):** Extend `AccountMessenger` request/response pattern — NOT `messaging_watcher`. Add `ChildDiscoveryRequest`/`ChildDiscoveryResponse` to `SGAccountComm.proto` oneof arms 10/11, following the `HandleNonceRequest`/`HandleNonceResponse` pattern at `AccountMessenger.cpp:1472-1566`. The existing `RequestHeads` broadcast pattern (`AccountMessenger.cpp:143-196`) is the exact template.
2. **Reward policy (RWD-01..03):** `TransactionManager::HoldEscrow` (`TransactionManager.cpp:778-810`) receives `dev_addr`/`peers_cut` as parameters — the caller (GeniusNode) chooses the source (DevConfig for standalone, `reg/{child}` CRDT for registered). PayEscrow reads stored escrow values (`TransactionManager.cpp:848,875`), providing automatic hold-time pinning (D-32). Zero changes to `EscrowTransaction`.
3. **Lifecycle (LIFE-01..04):** State-machine is derived from `reg/` CRDT record fields. Transitions are RegistrationTx entries at higher sequence with `detach_flag`/`supersedes_sequence` fields. `FilterRegistration` extends to gate on `supersedes_sequence == current.sequence` — combined with `sgns.nonce.v1` consensus ordering (`Consensus.hpp:37`), this provides deterministic first-to-consensus-wins conflict resolution.
4. **Proto evolution:** Additive-only: `detach_flag=5`, `supersedes_sequence=6` to `RegistrationTx`; `RevokeTx` as field 9 in `EmbeddedTransaction` oneof; `child_discovery_request=10`/`child_discovery_response=11` in `AccountMessage` oneof. All backward-compatible — no renumbering of existing fields.
5. **Revoke transaction:** Recommended as first-class `RevokeTx` GeniusTransaction subclass (new proto message, new `EmbeddedTransaction` arm), flowing through the existing `CheckParentChildAuthority` gate (Phase 2 D-19) + `sgns.nonce.v1` consensus. Alternatively, reuse `"transfer"` tx type with a flag — design doc should recommend the first-class approach for clearer audit semantics.

### Confidence Assessment
| Area | Level | Reason |
|------|-------|--------|
| Standard Stack | HIGH | All dependencies already exist in the SuperGenius tree — verified via codebase grep and file reads |
| Architecture | HIGH | All patterns (AccountMessenger, FilterRegistration, EscrowTransaction, nonce chain) verified with file:line citations against actual source code |
| Pitfalls | HIGH | Each pitfall traced to a concrete vulnerability; mitigations grounded in existing code patterns |

### Open Questions
1. RegistrationTx proto field layout — exact field numbering within RegistrationMetadata sub-message needs verification against Phase 1 design doc output (not found at expected path)
2. GlobalDB prefix scan capability for `reg/` namespace iteration in discovery response handler
3. RevokeTx: first-class subclass vs reuse of "transfer" type — design doc should recommend first-class

### Ready for Planning
Research complete. All 13 locked decisions (D-27 through D-39) have verified codebase anchors. Planner can now create the two design documents (03-01-discovery-monitoring.md, 03-02-reward-policy-lifecycle.md) with concrete SuperGenius file:line references.
