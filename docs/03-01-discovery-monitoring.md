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
