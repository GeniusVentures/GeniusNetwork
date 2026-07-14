# Main-Wallet Discovery & Monitoring

**Version:** 1.0
**Status:** Draft — Phase 03, Plan 03-01
**Date:** 2026-07-13
**Depends on:** `docs/02-crdt-registry-pubsub.md` (Phase 02, Plan 02-01), `docs/02-consensus-parent-child-authority.md` (Phase 02, Plan 02-02), `01-01-SUMMARY.md` (Phase 01 RegistrationTx schema)

## 1. Overview

Discovery is **push-primary, poll-fallback**. The primary path is pubsub broadcast (Phase 2 D-15/D-16) — the child publishes the `RegistrationTx` CID to the main's address topic via `AddBroadcastTopic(main_address)`, and the main receives the CID notification via `AddListenTopic(main_address)`. The main resolves the CID from CRDT, checks certified status (D-26), and if certified, treats the child as discovered.

If the main misses a broadcast (late join, network partition), it polls by broadcasting a `ChildDiscoveryRequest` on `SGNUS.BC.Requests.comm` via `AccountMessenger`. Any node with CRDT state (full node, the child itself, any peer that synced `reg/`) can respond with a `ChildDiscoveryResponse` containing the list of `reg/{child_addr}` CIDs whose `main_address` matches.

Per D-27: **No additional CRDT index namespace** — discovery is peer-to-peer, not stored in consensus state. The main wallet caches discovered children in a local JSON file for persistence across restarts.

The poll path reuses the existing `AccountMessenger` request/response pattern (NOT `messaging_watcher` — see §3 for rationale). The `AccountMessenger` already has `OnRequest`/`OnResponse` dispatch, worker-thread queuing, timeout management, signed messages, and response collection via `InterfaceMethods::sign_`/`verify_signature_`. Extending it with a new `ChildDiscoveryRequest`/`ChildDiscoveryResponse` oneof arm requires 2 proto additions + 2 handler methods — no new infrastructure.

### Key SuperGenius Anchor Points

| Component | Path | Role |
|-----------|------|------|
| AccountMessenger topic constants | `AccountMessenger.hpp:199-202` | `ACCOUNT_COMM` (`.comm`), `REQUESTS_COMM` (`SGNUS.BC.Requests.comm`) |
| PubSub topic subscription | `pubsub_broadcaster_ext.hpp:68-75` | `AddBroadcastTopic`/`AddListenTopic` APIs |
| RegistrationTx CRDT key | `reg/{child_addr}` (D-12) | `TransactionManager.cpp:1356-1368` `GetBlockChainBase()` → `/bc-{net}/reg/{child_addr}` |
| SendTransactionItem topic collection | `TransactionManager.cpp:1127-1206` | Where CID gets published to `main_address` topic |
| Certified status | D-26, Phase 2 `docs/02-crdt-registry-pubsub.md` §6 | `tx_processed_m` CONFIRMED or `reg-cert/` CRDT backup |
| AccountMessage oneof dispatch | `SGAccountComm.proto:5-17` | Arms 1-9 consumed; 10/11 available for discovery |

### Requirements Covered

| ID | Description |
|----|-------------|
| DISC-01 | How a main wallet discovers all child wallets registered to it from consensus-visible CRDT state |
| DISC-02 | Per-child information a main wallet displays (balance, assets, game, publisher, dev wallet, cut ratio, registration date, activity, status) |
| DISC-03 | Main-wallet actions over discovered children mapped to consensus rules (see §6) |

---

## 2. Push Path — PubSub CID Notification (DISC-01 Primary)

The push path is the fast path: the main learns about new child registrations within seconds via pubsub broadcast. It requires zero polling and leverages the existing `PubSubBroadcasterExt` infrastructure.

### 2.1 End-to-End Flow

1. **Child creates RegistrationTx** (Phase 1 D-06). The `RegistrationTx` proto message (`docs/registration-protocol.md` §2) carries `dag_struct=1`, `main_address=2`, `sequence=3`, and `metadata=4` (`RegistrationMetadata` with `game_id`, `publisher_id`, `dev_wallet`, `peers_cut` per `01-01-SUMMARY.md`).

2. **CRDT writes RegistrationTx** to `reg/{child_addr}` at key `/bc-{net}/reg/{child_addr}` (Phase 2 D-11/D-12, `docs/02-crdt-registry-pubsub.md` §2). `FilterRegistration` validates the incoming delta (D-13, `docs/02-crdt-registry-pubsub.md` §3).

3. **`TransactionManager::SendTransactionItem` publishes the RegistrationTx CID** on `main_address` topic via `PubSubBroadcasterExt::Publish` (D-15). The topic collection logic at `TransactionManager.cpp:1127-1206` gathers the `main_address` topic along with the child's own broadcast topics.

4. **Main wallet receives CID notification** via `AddListenTopic(main_address)` (Phase 2 D-17, `pubsub_broadcaster_ext.hpp:74`). The main subscribed to its own address topic at initialization time. The notification payload is the CID only — not the full RegistrationTx (D-16).

5. **Main resolves CID from CRDT** via `GlobalDB::Get(HierarchicalKey(cid))`. CID resolution is **content-addressed** — the CID is a cryptographic hash of the RegistrationTx content, so the operation cannot produce wrong content for a given CID (T-03-01 mitigation).

6. **Main checks certified status** (Phase 2 D-26, `docs/02-crdt-registry-pubsub.md` §6): the registration must have reached `tx_processed_m` CONFIRMED status (or have a `reg-cert/` CRDT backup entry) before the main acts on it. Uncertified registrations are ignored — the main may retry on the next poll cycle (see §5.2).

7. **If certified**: the main adds the child to its local discovered-children cache. **If uncertified**: the main ignores the notification and discards the CID.

### 2.2 PubSub Topic Architecture

```
Child Node                           PubSub Layer                     Main Node
    │                                     │                               │
    │ 1. Create RegistrationTx             │                               │
    │    ──────────────────►              │                               │
    │ 2. CRDT write reg/{child_addr}       │                               │
    │ 3. PubSubBroadcasterExt::Publish     │                               │
    │    (main_address, CID)               │                               │
    │    ─────────────────────────────────►│                               │
    │                                     │  CID notification             │
    │                                     │  ──────────────────────────► │
    │                                     │  AddListenTopic(main_address) │
    │                                     │                               │ 4. Receive CID
    │                                     │                               │ 5. GlobalDB::Get(cid)
    │                                     │                               │ 6. Check certified (D-26)
    │                                     │                               │ 7. Cache in local JSON
```

### 2.3 Anchor Points

| Step | Anchor | Detail |
|------|--------|--------|
| RegistrationTx creation | `docs/registration-protocol.md` §2-4 | Child-signed, first-class `GeniusTransaction` subclass |
| RegistrationMetadata fields | `01-01-SUMMARY.md` | `game_id`, `publisher_id`, `dev_wallet`, `peers_cut` |
| CRDT write | `docs/02-crdt-registry-pubsub.md` §2 | Key `/bc-{net}/reg/{child_addr}`, value = full RegistrationTx |
| CID broadcast | `TransactionManager.cpp:1127-1206` | `SendTransactionItem` topic collection |
| `PubSubBroadcasterExt::Publish` | `pubsub_broadcaster_ext.hpp:48` | Serialize + publish to topic set |
| Main subscribes (push receive) | `pubsub_broadcaster_ext.hpp:74` | `AddListenTopic(main_address)` |
| CID resolution | `GlobalDB::Get(HierarchicalKey(cid))` | Content-addressed, cited in `docs/02-crdt-registry-pubsub.md` §2 |
| Certified check | `docs/02-crdt-registry-pubsub.md` §6 | `tx_processed_m` CONFIRMED or `reg-cert/` CRDT |
| FilterRegistration | `TransactionManager.cpp:2984-3039` (pattern) | deserialize → signature → sequence → accept |

### 2.4 Traceability

- **DISC-01**: The push path implements the primary discovery mechanism.
- **D-15**: `SendTransactionItem` publishes CID on `main_address` topic.
- **D-16**: Payload is CID only; main resolves from CRDT + checks certified.
- **D-17**: Main subscribes to child's address topic for state sync after discovery.
- **D-26**: Certified status check prevents acting on uncertified registrations.
- **D-27**: Push-primary path documented as the primary mechanism.

---

## 3. Poll Path — AccountMessenger Query/Response (DISC-01 Fallback)

The poll path is the fallback for when the main misses a broadcast (late join, network partition, node restart before JSON cache write). It reuses the existing `AccountMessenger` request/response pattern — NOT `messaging_watcher`.

### 3.1 Why AccountMessenger, Not `messaging_watcher`

The `messaging_watcher` class (`SuperGenius/src/watcher/messaging_watcher.hpp`) is a **broadcast-only** placeholder with a 1-second sleep loop. It has no request/response semantics, no response collection, no timeout management, no signature verification — it cannot support the query/response protocol that discovery polling requires.

The `AccountMessenger` already implements a full request/response protocol over pubsub:

- **`AccountMessenger.hpp:199-202`** — Two pubsub topics: `account_comm_topic_` = `address + ".comm"` (personal), `REQUESTS_COMM` = `"SGNUS.BC.Requests.comm"` (global)
- **`AccountMessenger.cpp:190-234`** — `OnRequest`/`OnResponse` dispatch based on `AccountMessage` oneof type
- **`AccountMessenger.cpp:868-886`** — `SendAccountMessage` publishes signed proto messages to topic set
- **`AccountMessenger.cpp:886-1010`** — `WorkerLoop` dequeues requests, broadcasts, and collects responses with timeout
- **`AccountMessenger.cpp:143-196`** — `RequestHeads` is an existing broadcast-style query that sends on multiple topics and expects responses from arbitrary peers
- **`AccountMessenger.cpp:1472-1566`** — `HandleNonceRequest`/`HandleNonceResponse` pair is the exact request/response template

Extending `AccountMessenger` requires 2 proto additions + 2 handler methods + 1 `RequestType` enum entry. Building a new protocol on `messaging_watcher` would require a new message bus, worker thread, timeout engine, and signing layer — hundreds of lines of new infrastructure for a pattern that already exists.

### 3.2 Proto Extension: `ChildDiscoveryRequest` / `ChildDiscoveryResponse`

The `AccountMessage` oneof in `SGAccountComm.proto:5-17` has arms 1-9 consumed. The next available arms are 10 and 11 for discovery request/response:

```protobuf
// SGAccountComm.proto — Phase 3 additions (appended additively, never renumber)

message AccountMessage {
    oneof payload {
        SignedNonceRequest nonce_request = 1;
        SignedNonceResponse nonce_response = 2;
        // ... arms 3-9 (block_request, block_response, head_request,
        //     block_cid_request, utxo_request, utxo_response, transaction_request) ...
        SignedChildDiscoveryRequest child_discovery_request = 10;    // Phase 3
        SignedChildDiscoveryResponse child_discovery_response = 11;  // Phase 3
    }
}

message ChildDiscoveryRequest {
    string requester_address = 1;    // main wallet address making the query
    uint64 request_id = 2;           // unique ID to correlate requests with responses
    uint64 timestamp = 3;            // Unix timestamp ms
    string main_address = 4;         // the main wallet to query children for
}

message ChildDiscoveryResponse {
    string responder_address = 1;    // address of the node that responded
    string requester_address = 2;    // address from the original request
    uint64 request_id = 3;           // matches the request's request_id
    uint64 timestamp = 4;            // Unix timestamp ms
    repeated string reg_cids = 5;    // CIDs of reg/{child_addr} records whose main_address matches
}

message SignedChildDiscoveryRequest {
    ChildDiscoveryRequest data = 1;
    bytes signature = 2;
}

message SignedChildDiscoveryResponse {
    ChildDiscoveryResponse data = 1;
    bytes signature = 2;
}
```

**Field numbering conventions:**
- `child_discovery_request = 10`, `child_discovery_response = 11` in `AccountMessage.payload` — next available after arms 1-9
- `ChildDiscoveryRequest.main_address = 4` — field 4 in the request message
- `ChildDiscoveryResponse.reg_cids = 5` — repeated string of CIDs

### 3.3 Handler Methods

Following the `HandleNonceRequest`/`HandleNonceResponse` pattern at `AccountMessenger.cpp:1472-1614`, the discovery handlers are:

#### 3.3.1 `AccountMessenger::RequestChildDiscovery`

**Position:** New public method in `AccountMessenger.hpp`, following the `RequestHeads`/`RequestNonce` pattern at `AccountMessenger.cpp:143-196` / `AccountMessenger.cpp:276-303`.

**Signature:**
```cpp
outcome::result<void> RequestChildDiscovery(
    const std::string &main_address,
    uint64_t timeout_ms,
    std::function<void(std::vector<std::string>)> callback);
```

**Flow:**
1. Construct `ChildDiscoveryRequest` proto with `requester_address = address_`, a new `request_id`, current `timestamp`, and the `main_address` to query
2. Serialize and sign via `InterfaceMethods::sign_` (pattern at `AccountMessenger.cpp:95-99`)
3. Wrap in `SignedChildDiscoveryRequest` with `data` + `signature` (pattern at `AccountMessenger.cpp:97-99`)
4. Wrap in `AccountMessage` with `child_discovery_request` oneof (pattern at `AccountMessenger.cpp:102`)
5. Enqueue via `EnqueueTask(RequestType::ChildDiscovery, ...)` for the worker thread (pattern at `AccountMessenger.cpp:1011-1018`)
6. Worker thread broadcasts on `account_comm_topic_` + `REQUESTS_COMM` via `SendAccountMessage` (pattern at `AccountMessenger.cpp:886-1008`)
7. Worker thread starts timeout timer; on expiry, calls `callback` with all CIDs collected from `HandleChildDiscoveryResponse`

#### 3.3.2 `HandleChildDiscoveryRequest`

**Position:** New private handler dispatched from `OnRequest` switch at `AccountMessenger.cpp:190-231`.

**Flow (following `HandleNonceRequest` at `AccountMessenger.cpp:1472-1564`):**
1. Deserialize `SignedChildDiscoveryRequest` from the `AccountMessage`
2. **Verify requester signature** — serialize the `ChildDiscoveryRequest` data, call `methods_.verify_signature_(requester_address, signature, serialized_data)` (pattern at `AccountMessenger.cpp:1478-1499`). If invalid, discard silently.
3. **Scan local CRDT `reg/` namespace** — iterate CRDT keys matching the requested `main_address`:
   - For each `reg/{child_addr}` record, deserialize the `RegistrationTx` protobuf
   - Extract `RegistrationTx.main_address` (field 2)
   - **Certified-status filter (D-26):** Check that the registration is certified — verify `tx_processed_m` CONFIRMED status or `reg-cert/` entry exists (per `docs/02-crdt-registry-pubsub.md` §6). **Uncertified registrations are excluded from the response** (T-03-02 / RESEARCH.md Pitfall 2 mitigation).
   - If `main_address == request.main_address` AND certified → include the CID in the response
4. Build `ChildDiscoveryResponse` with:
   - `responder_address = address_`
   - `requester_address = request.requester_address`
   - `request_id = request.request_id`
   - `timestamp = GetTimestamp()`
   - `reg_cids = {list of matching certified CIDs}`
5. Sign the response via `methods_.sign_` (pattern at `AccountMessenger.cpp:139-148`)
6. Send response back to requester's `.comm` topic via `SendAccountMessage(msg, {requester_address + ".comm"})` (pattern at `AccountMessenger.cpp:148-152`)

#### 3.3.3 `HandleChildDiscoveryResponse`

**Position:** New private handler dispatched from `OnResponse` switch at `AccountMessenger.cpp:190-231`.

**Flow (following `HandleNonceResponse` at `AccountMessenger.cpp:1566-1614`):**
1. Deserialize `SignedChildDiscoveryResponse`
2. **Verify responder signature** — serialize response data, call `methods_.verify_signature_(responder_address, signature, serialized)` (pattern at `AccountMessenger.cpp:1585-1599`)
3. Extract `requester_address`, `request_id`, `reg_cids`
4. Under `child_discovery_responses_mutex_`, merge CIDs into `child_discovery_responses_[request_id]` set — keyed by `request_id` to allow multiple responders to contribute CIDs

#### 3.3.4 `WorkerLoop` Integration

**Position:** New case in the `WorkerLoop` switch at `AccountMessenger.cpp:886-1008`.

Add `case RequestType::ChildDiscovery:` — following the nonce request pattern:
1. Broadcast `ChildDiscoveryRequest` on `account_comm_topic_` + `REQUESTS_COMM`
2. Set timeout timer
3. On timeout or collection threshold: invoke stored callback with merged CID list

#### 3.3.5 `RequestType` Enum

**Position:** `AccountMessenger.hpp:270-277` — append `ChildDiscovery` to the `RequestType` enum:
```cpp
enum class RequestType : std::uint8_t {
    Nonce, Genesis, AccountCreation, ValidatorRegistry, BlockByCid, UTXO, Transaction,
    ChildDiscovery  // Phase 3
};
```

### 3.4 GlobalDB CRDT Scan for `reg/` Namespace

The `HandleChildDiscoveryRequest` handler must efficiently scan the `reg/` CRDT namespace for records matching a specific `main_address`.

**Key format:** `/bc-{net}/reg/{child_addr}` — constructed by `GetBlockChainBase()` at `TransactionManager.cpp:1356-1368` using format string `"/bc-%hu/"` (`TransactionManager.hpp:296`).

**Approach:**
1. **Prefix scan (preferred):** If `GlobalDB` supports prefix iteration on `HierarchicalKey`, issue a prefix scan for `/bc-{net}/reg/` and filter by `main_address` in the response handler. This is the efficient path for large child registries.
2. **Full CRDT iteration (fallback):** If prefix scan is not available, iterate all CRDT elements matching the regex `^/?/bc-{net}/reg/([^/]+)` (matching the `FilterRegistration` regex pattern at `TransactionManager.cpp:187-213`) and filter by `main_address`. Acceptable because `reg/` records are sparse — one per child wallet.
3. **Optimization:** For large registries, `GlobalDB` could register a secondary index on `RegistrationTx.main_address` within the `reg/` namespace — but this is deferred to v2 (ADV-02).

**Per RESEARCH.md Open Question #2:** The design specifies a prefix-scan approach if `GlobalDB` supports it; falls back to full CRDT iteration if not.

### 3.5 Anchor Points

| Component | Anchor | Pattern Reference |
|-----------|--------|-------------------|
| AccountMessenger topics | `AccountMessenger.hpp:199-202` | `ACCOUNT_COMM = ".comm"`, `REQUESTS_COMM = "SGNUS.BC.Requests.comm"` |
| Proto oneof extension | `SGAccountComm.proto:5-17` | Arms 10/11 — additive, arms 1-9 consumed |
| RequestHeads broadcast pattern | `AccountMessenger.cpp:143-196` | Template for `RequestChildDiscovery` |
| RequestNonce sender | `AccountMessenger.cpp:276-303` | Construct proto → sign → wrap → enqueue |
| HandleNonceRequest | `AccountMessenger.cpp:1472-1564` | Verify sig → gather data → sign response → `SendAccountMessage` |
| HandleNonceResponse | `AccountMessenger.cpp:1566-1614` | Verify sig → extract data → merge into response map |
| OnRequest/OnResponse dispatch | `AccountMessenger.cpp:190-231` | `switch(acc_msg.payload_case())` arms |
| SendAccountMessage | `AccountMessenger.cpp:868-884` | Serialize proto → `pubsub_->Publish(topic, data)` |
| WorkerLoop + EnqueueTask | `AccountMessenger.cpp:886-1018` | Broadcast + timeout + callback |
| RequestType enum | `AccountMessenger.hpp:270-277` | Add `ChildDiscovery` entry |
| GetBlockChainBase | `TransactionManager.cpp:1356-1368` | Key format: `"/bc-{net}/"` → full path: `/bc-{net}/reg/{child_addr}` |
| GlobalDB::Get | `globaldb.hpp` | Single-key read for CID resolution |
| GlobalDB::RegisterElementFilter | `globaldb.hpp:162-167` | Filter registration pattern for `reg/` namespace |
| Certified status | `docs/02-crdt-registry-pubsub.md` §6 | D-26 — `tx_processed_m` CONFIRMED or `reg-cert/` CRDT |

### 3.6 Traceability

- **DISC-01**: The poll path provides the fallback discovery mechanism — main broadcasts query, any node responds.
- **D-27**: "Any node with CRDT state can respond" — decentralized poll architecture confirmed.
- **D-26**: Certified-status filter in `HandleChildDiscoveryRequest` excludes uncertified registrations.
- **T-03-02**: Responder signature verification + CID resolution + certified-status check mitigate discovery response spoofing.

---

## 4. Per-Child Information Aggregation (DISC-02)

Per D-28: "Per-child display information comes from three sources aggregated by the main's local logic — no new CRDT namespace is created."

The main wallet aggregates per-child information from:
1. **`reg/{child_addr}` CRDT** (Phase 2 D-12/D-14) — registration metadata: child address, main_address, sequence, game/publisher/dev info, registration timestamp, lifecycle status
2. **Child CRDT deltas** (subscribed via Phase 2 D-17 `AddListenTopic(child_address)` at `pubsub_broadcaster_ext.hpp:74`) — balance, UTXO list, recent transaction activity
3. **Local JSON cache** — last-seen timestamp, display preferences

### 4.1 Display Field → Data Source Mapping

| Display Field | Data Source | Anchor Point |
|---------------|-------------|--------------|
| Child address | `RegistrationTx.main_address` (field 2) — the child wallet's address | `reg/{child_addr}` CRDT, `SGTransaction.proto` RegistrationTx |
| Main address | `RegistrationTx.main_address` (field 2) — the registered parent | `reg/{child_addr}` CRDT |
| Registration sequence | `RegistrationTx.sequence` (field 3) | `reg/{child_addr}` CRDT |
| Game ID | `RegistrationMetadata.game_id` | `reg/{child_addr}` CRDT, Phase 1 `01-01-SUMMARY.md` RegistrationMetadata fields |
| Publisher ID | `RegistrationMetadata.publisher_id` | `reg/{child_addr}` CRDT, `01-01-SUMMARY.md` |
| Developer wallet | `RegistrationMetadata.dev_wallet` | `reg/{child_addr}` CRDT, `01-01-SUMMARY.md` |
| Peer cut ratio | `RegistrationMetadata.peers_cut` | `reg/{child_addr}` CRDT, `01-01-SUMMARY.md` |
| Registration date | CRDT element timestamp or `dag_struct` timestamp from DAGStruct header | `reg/{child_addr}` CRDT element metadata |
| Lifecycle status | Derived from `reg/{child_addr}` fields: `main_address` present + `detach_flag == false` = Registered; `detach_flag == true` = Detached/Revoked (initiator distinguished from which key signed); no `reg/{child_addr}` record = Unregistered (standalone) | Lifecycle state machine (`docs/03-02-reward-policy-lifecycle.md` §Lifecycle State Machine, D-34) |
| Balance | Sum of child UTXO amounts where `owner_address == child_address` | Child CRDT deltas via `AddListenTopic(child_address)` (D-17, `pubsub_broadcaster_ext.hpp:74`); `UTXOEntryRecord.owner_address` from `SGTransaction.proto` |
| UTXO list | `UTXOEntryRecord` entries where `owner_address == child_address` | `SGTransaction.proto` `UTXOEntryRecord` via child CRDT sync |
| Recent activity | Child transaction history (RegistrationTx, TransferTx, EscrowTx events) | Child CRDT deltas from subscribed topic |
| Last seen | Local timestamp | Main wallet's local JSON cache (`discovered_children.json`, see §5) |

### 4.2 Aggregation Logic

The main wallet's Per-Child Aggregator performs these steps for each discovered child:

1. **Read registration metadata** from `reg/{child_addr}` CRDT (authoritative source)
2. **Read balance and UTXOs** from local CRDT state synced via `AddListenTopic(child_address)` (D-17)
3. **Read lifecycle status** derived from the `reg/{child_addr}` record fields
4. **Merge with local cache** for display preferences and last-seen timestamp
5. **Present the aggregated view** — no new CRDT namespace, no consensus traffic for aggregation

The aggregation is performed by the main wallet's local logic at display time. It does NOT create a new CRDT namespace, does NOT generate consensus traffic, and does NOT require the child's private key (all data is from public CRDT state).

### 4.3 Data Freshness

| Data Source | Freshness Mechanism | Latency |
|-------------|---------------------|---------|
| `reg/{child_addr}` CRDT | Pull on cache miss or on poll cycle; DAG-synced via IPFS Graphsync | Eventual consistency (seconds to minutes) |
| Child CRDT deltas | Push via `AddListenTopic(child_address)` — real-time pubsub | Sub-second for online children |
| Local JSON cache | Write-through on discovery, updated on push/poll events | Instant from cache; cache updated on events |

### 4.4 Traceability

- **DISC-02**: All per-child display fields mapped to data sources with concrete anchor points.
- **D-28**: Three-source aggregation — `reg/` CRDT + child CRDT deltas + local JSON — no new CRDT namespace.
- **D-17**: Main subscribes to child address topic for state sync (Phase 2, `docs/02-crdt-registry-pubsub.md` §4).
- **D-12/D-14**: `reg/{child_addr}` CRDT key + full RegistrationTx value as authoritative metadata source.

---

## 5. Local JSON Cache Schema

Per D-27, the main wallet caches discovered children in a local JSON file for persistence across restarts. The cache is best-effort, not authoritative — authoritative state is always `reg/` CRDT.

### 5.1 JSON Schema

**File location:** `{data_dir}/discovered_children.json` (alongside `sgns_config.json`, `network_config.json` — following existing config file patterns).

**Library:** `boost::json` (available in the Boost dependency tree per `AGENTS.md` Key Dependencies) or `rapidjson` (referenced at `SuperGenius/src/watcher/messaging_watcher.hpp:6` — already in the dependency tree). The implementation chooses whichever is already linked in the main wallet process.

**Schema:**

```json
{
  "version": 1,
  "last_poll_timestamp": 1750000000000,
  "poll_backoff_seconds": 30,
  "children": {
    "<child_hex_address>": {
      "last_seen": 1750000000000,
      "status": "registered",
      "cached_metadata": {
        "main_address": "<hex>",
        "sequence": 1,
        "game_id": "com.example.shooter",
        "publisher_id": "pub_abc123",
        "dev_wallet": "<hex>",
        "peers_cut": 5000,
        "registration_cid": "bafy..."
      }
    }
  }
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `version` | int | Schema version for forward compatibility |
| `last_poll_timestamp` | uint64 | Unix timestamp ms of last poll cycle |
| `poll_backoff_seconds` | uint64 | Current poll interval (for exponential backoff, see §5.3) |
| `children.{addr}.last_seen` | uint64 | Last time this child was seen (push or poll) |
| `children.{addr}.status` | string | Derived lifecycle status: `"registered"`, `"detached"`, `"revoked"`, `"unregistered"` |
| `children.{addr}.cached_metadata` | object | Last known metadata snapshot from `reg/{child_addr}` CRDT — used for display when CRDT read is slow |

### 5.2 Cache Update Policy

- **On push notification** → update cache entry: store CID, update `last_seen`, update `status` to `"registered"`, refresh `cached_metadata` from CRDT resolution. Reset poll backoff to minimum (30s).
- **On poll response** → merge with existing cache: add newly discovered children, update `last_seen` and `cached_metadata` for existing children that appear in responses, retain children not mentioned in responses (they may be offline — do not remove from cache). Update `last_poll_timestamp`.
- **Cache is best-effort** — authoritative state is always `reg/` CRDT. If the cache file is corrupted or missing, the main falls back to a full poll cycle and rebuilds the cache from CRDT.
- **Cache does not drive authorization** — main-wallet actions (fund, recover, revoke) always re-validate against live CRDT state via `CheckParentChildAuthority` before executing.

### 5.3 Polling Policy with Exponential Backoff

Per RESEARCH.md Pitfall 1 (Discovery Poll Flooding): "Implement exponential backoff on discovery polling to prevent excessive pubsub traffic."

**Policy:**
- **Initial interval:** 30 seconds
- **Backoff sequence:** 30s → 60s → 120s → 300s → 600s (cap)
- **Push notification resets the timer:** When a push notification (CID broadcast on `main_address` topic) is received, the poll timer is reset to the minimum interval (30s) — push is the primary mechanism; poll is the fallback for missed broadcasts
- **Implementation:** The poll timer is managed by the main wallet's discovery engine, using the existing Boost.Asio timer infrastructure
- **Rationale:** Without backoff, a main wallet that polls every few seconds generates excessive pubsub traffic and triggers unnecessary CRDT scans on responding nodes (per RESEARCH.md Pitfall 1). Exponential backoff bounds this while ensuring the main eventually discovers children if it misses broadcasts.

### 5.4 Traceability

- **D-27**: Local JSON cache specified as the persistence mechanism — no new CRDT namespace.
- **T-03-04**: Exponential backoff mitigates discovery poll flooding denial-of-service.
- **Pattern:** JSON config files follow existing `sgns_config.json`/`network_config.json` persistence patterns.

---

## 6. Main-Wallet Actions (DISC-03)

Per D-29: "Every main-wallet action reuses an existing Phase 2 or Phase 3 mechanic. No new consensus rules are introduced for discovery — the discovery layer provides the UI/API that invokes existing mechanics."

The main wallet can perform five actions over discovered children. Each action maps to a concrete Phase 2 consensus rule or Phase 3 lifecycle mechanic, with all validation enforced by the existing `ValidateTransactionForConsensus` pipeline (`TransactionManager.cpp:4234-4304`) and the `CheckParentChildAuthority` gate (Phase 2 D-19, `docs/02-consensus-parent-child-authority.md` §3).

### 6.1 Fund (Main→Child Transfer)

**Mechanic:** CONS-01 (Phase 2, `docs/02-consensus-parent-child-authority.md` §4.1).

**Description:** The main wallet sends GNUS tokens to a registered child wallet via a standard main-signed transfer transaction.

**Validation flow:**
1. Main wallet constructs a `TransferTx` with `child_address` as destination
2. Main signs the transaction with its private key (standard `MakeSignature` path)
3. `ValidateTransactionForConsensus` at `TransactionManager.cpp:4234-4304` processes the transaction through the standard gate pipeline:
   - **Gate 1** (`CheckTransactionWellFormed`, line 4250): validates proto deserialization and required fields
   - **Gate 2** (`CheckTransactionAuthorization`, line 4259, `TransactionManager.cpp:4361-4383`): validates main's signature
   - **Gate 2.5** (`CheckParentChildAuthority`, Phase 2 D-19, `docs/02-consensus-parent-child-authority.md` §3): validates that a certified `reg/{child_addr}` record exists linking the child to the sending main (`reg/{child_addr}.main_address == signer`)
   - **Gate 3** (`CheckTransactionTimestamp`, line 4268): timestamp within drift tolerance
   - **Gate 4** (`EvaluateTransactionReplayProtection`, line 4277): nonce chain + UTXO double-spend check
   - **Gate 5** (`CheckTransactionTypeRules`, line 4288): type-specific validation

**Restriction:** The main must have sufficient UTXOs owned by `main_address` — standard transfer validation, unchanged by parent-child authority.

**Anchor:** `TransactionManager.cpp:4234-4304` (pipeline), Phase 2 `docs/02-consensus-parent-child-authority.md` §4.1 (CONS-01).

### 6.2 Recover (Main-Recover-From-Child)

**Mechanic:** CONS-02 (Phase 2, `docs/02-consensus-parent-child-authority.md` §4.2).

**Description:** The main wallet recovers funds FROM a child wallet — a delegated-spend where the main signs a transfer that moves child-owned UTXOs.

**Validation flow:**
1. Main wallet constructs a `TransferTx` spending child-owned UTXOs, with destination `dst`
2. **Destination restriction (D-21):** `dst` is HARD-RESTRICTED to the registered `main_address` from the `reg/{child_addr}` CRDT record. The `CheckParentChildAuthority` gate validates `dst == reg/{child_addr}.main_address` — any other destination is REJECTED.
3. Gate 2 (`CheckTransactionAuthorization`): main's signature is validated
4. Gate 2.5 (`CheckParentChildAuthority`): validates reg/ record existence + main address match + registered state
5. Standard UTXO ownership check (`ValidateWitness`, `GeniusInputValidator.cpp:419`) validates the UTXOs belong to the child — preserved unchanged (CONS-06: delegated authority is orthogonal to UTXO ownership)
6. Gates 3-5 proceed normally

**Security note:** Recovery requires the main's private key to sign. Per REG-04, the recovery flow must happen in the main wallet process — out-of-process from the child, same security boundary as the registration signing flow. The main private key never enters the game/child process.

**Anchor:** Phase 2 `docs/02-consensus-parent-child-authority.md` §4.2 (CONS-02), `TransactionManager.cpp:4234-4304` (`ValidateTransactionForConsensus`).

### 6.3 Inspect History / View Assets

**Mechanic:** SYNC-04 (Phase 2 D-17, `docs/02-crdt-registry-pubsub.md` §4).

**Description:** The main wallet reads a child's balance, UTXO list, and transaction history — read-only, no signature required.

**Data path:**
1. Main subscribes to `child_address` topic via `AddListenTopic(child_address)` (D-17, `pubsub_broadcaster_ext.hpp:74`). This subscription is established at discovery time per §2.1 step 6.
2. Main receives CRDT deltas from the child's topic — UTXO changes, transaction entries, balance updates — via the standard DAG sync mechanism (IPFS Graphsync, `crdt_datastore`).
3. Main merges deltas into its local CRDT replica — read-only access to public state.
4. Main displays aggregated view per §4: balance (sum of UTXO amounts where `owner_address == child_address`), UTXO list (`UTXOEntryRecord` entries), transaction history (CRDT deltas from child's topic).

**Security:** CRDT state is publicly readable by design — no signature needed to read it. The child's private key is not required for read access (T-03-05: information disclosure is accepted — CRDT state is public).

**Anchor:** `pubsub_broadcaster_ext.hpp:74` (`AddListenTopic`), Phase 2 `docs/02-crdt-registry-pubsub.md` §4 (SYNC-04).

### 6.4 Revoke (Main-Initiated)

**Mechanic:** LIFE-01 (Phase 3 D-36, `docs/03-02-reward-policy-lifecycle.md` §Revoke Flow).

**Description:** The main wallet permanently severs its parent-child authority over a registered child via a main-signed `RevokeTx` consensus transaction. After revocation, the main has zero recovery authority over the child.

**First-class RevokeTx recommendation:** Per RESEARCH.md Open Question #3, this document recommends a **first-class `RevokeTx` as a new `GeniusTransaction` subclass** (following the `RegistrationTx` Phase 1 D-06 pattern), NOT a flagged transfer transaction. Rationale:
- **Cleaner audit trail:** A distinct transaction type creates an unambiguous on-chain record of authority revocation
- **No transfer type overloading:** Using a flagged transfer conflates fund movement with authority revocation — two semantically distinct operations
- **Simpler validation:** The `CheckParentChildAuthority` gate can handle `RevokeTx` with a dedicated validation path instead of checking flags on a generic transfer
- **Pattern consistency:** `RegistrationTx` is already a first-class subclass; `RevokeTx` follows the same pattern

**RevokeTx proto schema** (new message in `SGTransaction.proto`, following the `EscrowTx` pattern at `EscrowTx` fields 1-5):

```protobuf
message RevokeTx {
    DAGStruct dag_struct = 1;
    bytes child_address = 2;           // address of the child wallet being revoked
    uint64 registration_sequence = 3;  // sequence of the reg/ record being revoked
}
```

**EmbeddedTransaction oneof arm:** `revoke = 9` in `Consensus.proto:70-80` `EmbeddedTransaction` oneof (arms 1-7 consumed, 8 = RegistrationTx).

**Consensus gate path** — the `RevokeTx` flows through the existing `ValidateTransactionForConsensus` pipeline at `TransactionManager.cpp:4234-4304`:

1. **Gate 1** (`CheckTransactionWellFormed`, line 4250): validates `RevokeTx` proto fields (`dag_struct`, `child_address`, `registration_sequence`)
2. **Gate 2** (`CheckTransactionAuthorization`, line 4259, `TransactionManager.cpp:4361-4383`): validates **main's signature** — the main wallet signs the `RevokeTx`
3. **Gate 2.5** (`CheckParentChildAuthority`, Phase 2 D-19, `docs/02-consensus-parent-child-authority.md` §3) — extended for RevokeTx:
   - Validates `reg/{child_addr}.main_address == signer` (the main is the registered parent of this child)
   - Validates `reg/{child_addr}` is in **Registered state** (`detach_flag == false`, `main_address != empty`) — cannot revoke an already-detached/revoked child
   - Validates `registration_sequence` matches the current `reg/{child_addr}.sequence` — prevents race conditions where the child re-registers between the main signing and the tx reaching consensus
4. **Gate 3** (`CheckTransactionTimestamp`, line 4268): timestamp validation
5. **Gate 4** (`EvaluateTransactionReplayProtection`, line 4277): **nonce chain** (`sgns.nonce.v1` — `Consensus.hpp:37`, `TransactionManager.cpp:149-159`) prevents double-revoke — the main can only issue one `RevokeTx` per nonce slot
6. **Post-validation:** `RevokeTx` sets `detach_flag = true` on the `reg/{child_addr}` CRDT record. Main has zero recovery authority thereafter. The child retains all UTXOs and can continue operating as a standalone wallet (D-39) or re-register to a new main at higher sequence.

**Cross-reference:** The `RevokeTx` is fully specified in `docs/03-02-reward-policy-lifecycle.md` §Revoke Flow. This section cross-references it as a discoverable action from the main wallet's perspective.

### 6.5 Detach (Child-Initiated)

**Mechanic:** LIFE-01 (Phase 3 D-35, `docs/03-02-reward-policy-lifecycle.md` §Detach Flow).

**Description:** The child wallet voluntarily severs its parent-child relationship by issuing a new `RegistrationTx` with `detach_flag = true` at a higher `sequence`. This is a CHILD-initiated action — the main wallet displays "Detach" as a discoverable status but cannot trigger it. The main's equivalent is Revoke (§6.4).

**Validation flow:**
1. Child constructs a new `RegistrationTx` with:
   - `dag_struct` = new DAGStruct
   - `main_address` = empty/zero-address (indicating detached state)
   - `sequence` = `current_registration.sequence + 1`
   - `metadata` = current `RegistrationMetadata`
   - `detach_flag = 5` = `true`
   - `supersedes_sequence = 6` = `current_registration.sequence` (D-38 — explicit chain-of-custody)
2. Child signs the `RegistrationTx`
3. `FilterRegistration` (Phase 2 D-13, `docs/02-crdt-registry-pubsub.md` §3) validates:
   - **Signature:** child's signature over the new RegistrationTx (gate 1)
   - **Sequence monotonicity:** `new.sequence > current.sequence` (gate 3)
   - **Supersedes linkage (D-38):** `new.supersedes_sequence == current.sequence` — rejects fork races where two competing updates fork from the same base
4. Nonce chain (`sgns.nonce.v1`) provides total ordering: first to reach consensus wins; second rejected at filter because `supersedes_sequence` no longer matches the (now-updated) current record
5. Post-certification: `reg/{child_addr}` CRDT record updated with `detach_flag = true`, `main_address` cleared. Child retains all UTXOs and continues as a valid standalone wallet (D-39). Main has read-only visibility, zero recovery authority.

**Main's perspective:** The main discovers the detach event on the next push notification (child broadcasts updated RegistrationTx CID) or poll cycle. The main's local cache updates the child's `status` to `"detached"`. The main can still inspect history and view assets (read-only, §6.3) but can no longer fund (CONS-01 gate rejects — no active reg/ record), recover (CONS-02 rejects), or revoke (already detached).

**Cross-reference:** `docs/03-02-reward-policy-lifecycle.md` §Detach Flow for the full lifecycle specification.

### 6.6 Action-to-Mechanic Summary

| Action | Initiator | Mechanic | Phase 2/3 Rule | Validation Gate | Requires Main Key |
|--------|-----------|----------|----------------|-----------------|-------------------|
| Fund | Main | Main-signed TransferTx → child | CONS-01 | Gate 2 (sig) + Gate 2.5 (CheckParentChildAuthority) | Yes |
| Recover | Main | Main-signed TransferTx FROM child, dst=main | CONS-02 | Gate 2 + Gate 2.5 (reg/ match + dst restriction) | Yes |
| Inspect | Main | Read child CRDT state via subscribed pubsub | SYNC-04 (D-17) | None (read-only, public CRDT) | No |
| Revoke | Main | Main-signed RevokeTx (first-class tx) | LIFE-01 (D-36) | Gates 1-4 + Gate 2.5 (main_address match + Registered state) | Yes |
| Detach | Child | Child-signed RegistrationTx with detach_flag | LIFE-01 (D-35) | FilterRegistration (sig + seq + supersedes) | No (child signs) |

### 6.7 Traceability

- **DISC-03**: All five main-wallet actions mapped to Phase 2/3 mechanics with concrete gate references.
- **D-29**: Fund → CONS-01, Recover → CONS-02, Inspect → SYNC-04/D-17, Revoke → LIFE-01/D-36, Detach → LIFE-01/D-35.
- **D-19**: `CheckParentChildAuthority` gate validates fund, recover, and revoke paths.
- **D-21**: Recovery destination hard-restricted to registered `main_address`.
- **D-35**: Detach is child-initiated — main cannot trigger it; main's equivalent is Revoke.
- **D-36**: Revoke is main-initiated — first-class `RevokeTx` recommended.
- **D-38**: `supersedes_sequence` linkage prevents fork races on lifecycle updates.
- **D-39**: Detach/revoke leaves child as a valid standalone wallet.

---

## 7. Requirement Traceability

| Requirement | Section | Anchor Points | Status |
|-------------|---------|---------------|--------|
| **DISC-01** | §2 Push Path, §3 Poll Path | `AccountMessenger.hpp:199-223` (topic constants), `pubsub_broadcaster_ext.hpp:68-75` (AddListenTopic/AddBroadcastTopic), `SGAccountComm.proto:5-17` (oneof arms 10/11), `TransactionManager.cpp:1127-1206` (SendTransactionItem topic collection), `AccountMessenger.cpp:1472-1566` (HandleNonceRequest/Response pattern) | ✓ |
| **DISC-02** | §4 Per-Child Info, §5 JSON Cache | `reg/{child_addr}` CRDT (D-12, `docs/02-crdt-registry-pubsub.md` §2), `SGTransaction.proto` RegistrationTx (field 2: main_address, field 3: sequence), `UTXOEntryRecord.owner_address` (Phase 1 IDENT-04), `01-01-SUMMARY.md` (RegistrationMetadata: game_id, publisher_id, dev_wallet, peers_cut), `pubsub_broadcaster_ext.hpp:74` (AddListenTopic for child state sync) | ✓ |
| **DISC-03** | §6 Main-Wallet Actions | CONS-01/CONS-02 (`docs/02-consensus-parent-child-authority.md` §4.1/§4.2), SYNC-04 (`docs/02-crdt-registry-pubsub.md` §4), LIFE-01/D-35/D-36 (`docs/03-02-reward-policy-lifecycle.md` §Detach/Revoke Flows), `TransactionManager.cpp:4234-4304` (ValidateTransactionForConsensus pipeline), `TransactionManager.cpp:4361-4383` (CheckTransactionAuthorization), `Consensus.hpp:37` (sgns.nonce.v1) | ✓ |

### Decisions Reflected

| Decision | How Reflected | Section |
|----------|---------------|---------|
| D-27: Push-primary, poll-fallback | Documented end-to-end push flow (§2) and poll flow (§3); local JSON cache (§5) | §2, §3, §5 |
| D-28: Three-source per-child info | Per-child info table (§4.1) maps every field to reg/ CRDT, child deltas, or local cache | §4 |
| D-29: Action→mechanism mappings | Action-to-mechanic summary table (§6.6) maps all 5 actions to Phase 2/3 rules | §6 |
| D-26: Certified status check | Required in push path (§2.1 step 6) and poll path (§3.3.2 Handler scan) | §2, §3 |

---

## 8. Phase Hand-Offs

### 8.1 Dependencies

This document assumes the following Phase 1 and Phase 2 designs are complete and authoritative:

| Phase | Document | What This Document Uses |
|-------|----------|------------------------|
| Phase 1 | `01-01-SUMMARY.md` | `RegistrationTx` schema (dag_struct, main_address, sequence, metadata), `RegistrationMetadata` fields (game_id, publisher_id, dev_wallet, peers_cut) |
| Phase 1 | `docs/child-wallet-identity-model.md` | Independent keypair model (D-01), UTXO ownership via `owner_address` (D-02), per-account nonce (D-03) |
| Phase 1 | `docs/registration-protocol.md` | `RegistrationTx` proto definition (§2), first-class tx subclass (§4), child-signed-only (D-04/D-05) |
| Phase 2 | `docs/02-crdt-registry-pubsub.md` | `reg/` namespace key layout (§2), `FilterRegistration` design (§3), pubsub broadcast/subscription (§4-5), certified status (§6) |
| Phase 2 | `docs/02-consensus-parent-child-authority.md` | `CheckParentChildAuthority` gate (§3), CONS-01/CONS-02 rules (§4), gate pipeline insertion (§2) |
| Phase 3 | `docs/03-02-reward-policy-lifecycle.md` | Lifecycle state machine (D-34), detach/revoke flows (D-35/D-36), reward policy resolution |

### 8.2 Deferrals (v2)

The following concerns are explicitly deferred to a future version and are NOT designed in this document:

| Concern | Deferred ID | Reason |
|---------|-------------|--------|
| Platform "Connect GNUS Wallet" UI flows (Android/iOS/desktop) | PLAT-01, PLAT-02 | UI implementation is out of scope for the design-document milestone; this document describes the protocol conceptually |
| Aggregated registry topic for publisher-scale child fan-out (hundreds/thousands of children) | ADV-02 | The current discovery mechanism supports many children per main; an optimized aggregation layer is a scaling optimization for a later version |
| Threshold/social-recovery scheme for the main wallet | ADV-01 | Recovery scheme design is a separate security concern; child wallets use the existing keypair model |
| Optional main acceptance signature for registration (pending→confirmed upgrade) | v2 hardening | Rejected in Phase 1 (D-04/D-05) for the child-signed-only model; could be revisited as a v2 hardening layer if discovery-spam becomes a problem |
| Secondary CRDT index on `RegistrationTx.main_address` for prefix-scan optimization | ADV-02 | Current full-CRDT-iteration fallback is acceptable for sparse `reg/` records; a secondary index is a performance optimization |

### 8.3 Integration Surface for 03-02

The companion Phase 3 document (`docs/03-02-reward-policy-lifecycle.md`) specifies the following mechanisms that this discovery document cross-references:

| 03-02 Section | Mechanism | Referenced In Discovery Doc |
|---------------|-----------|----------------------------|
| §Reward Policy Resolution | RWD-01 (standalone vs registered policy source) | §4 Per-Child Info (dev_wallet/peers_cut in metadata table) |
| §Hold-Time Pinning | RWD-02 (EscrowTransaction immutability) | §4 (balance/UTXO from child CRDT deltas) |
| §Lifecycle State Machine | D-34 (4 states: Unregistered, Registered, Detached, Revoked) | §4 Per-Child Info (lifecycle status derivation) |
| §Revoke Flow | D-36 (main-signed RevokeTx, first-class subclass) | §6.4 (Revoke action — this doc recommends first-class RevokeTx) |
| §Detach Flow | D-35 (child-signed RegistrationTx with detach_flag) | §6.5 (Detach action — child-initiated, main view-only) |
| §Main Replacement | D-37 (child-only main replacement, no old-main consent) | §6.5 (implied — child re-registers after detach) |
| §Supersedes Conflict Resolution | D-38 (supersedes_sequence + nonce chain) | §6.5 (Detach validation flow) |

---

*Version: 1.0 — Phase 03, Plan 03-01*
*Date: 2026-07-13*
