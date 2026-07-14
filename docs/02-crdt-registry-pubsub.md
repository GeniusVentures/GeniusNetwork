# CRDT Registry Namespace, PubSub Broadcast & Sync

**Version:** 1.0
**Status:** Draft — Phase 02, Plan 02-01
**Date:** 2026-07-13

## 1. Overview

This design specifies how the `RegistrationTx` (defined in `docs/registration-protocol.md`) materializes into consensus-visible CRDT state, how the child broadcasts registration to the main via pubsub for low-latency discovery, and how the main syncs child CRDT state without the child's private key.

### End-to-End Flow Summary

1. **Child creates RegistrationTx** (Phase 1) → calls `SendTransactionItem`
2. **SendTransactionItem writes RegistrationTx to CRDT** at key `/bc-{net}/reg/{child_addr}` (D-12)
3. **FilterRegistration validates the incoming delta** (D-13), CRDT accepts pre-certificate (D-26)
4. **SendTransactionItem publishes CID** on `main_address` topic via `PubSubBroadcasterExt` (D-15)
5. **SendTransactionItem submits RegistrationTx to consensus** via `sgns.nonce.v1` subject (D-24)
6. **Main receives CID** on its own topic (D-16) → resolves CID from CRDT → validates certification → subscribes to `child_address` topic (D-17)
7. **Main receives child's CRDT deltas** via subscribed topic → merges into local CRDT for balance/asset monitoring

### Requirements Covered

| ID | Description |
|----|-------------|
| SYNC-01 | CRDT namespace/key layout for registration record in `globaldb` |
| SYNC-02 | CRDT element filter validates and persists registration deltas in `TransactionManager` |
| SYNC-03 | Registration broadcast on main wallet's pubsub channel via `PubSubBroadcasterExt` |
| SYNC-04 | Main wallet subscribes to child pubsub channels and syncs CRDT for balances |
| SYNC-05 | Authority derived from signatures+consensus, not from pubsub topic membership |

### Design Authority

This document is grounded in:

- **Phase 2 Context (`02-CONTEXT.md`)** — decisions D-11 through D-18, D-24 through D-26
- **Phase 2 Research (`02-RESEARCH.md`)** — architectural responsibility map, pitfalls 1-5 with mitigations, open question resolutions
- **Phase 2 Patterns (`02-PATTERNS.md`)** — FilterTransaction analog, CRDT key construction, pubsub API patterns, SendTransactionItem flow, certified-status patterns
- **`docs/registration-protocol.md`** §2 (RegistrationTx proto schema), §4 (C++ subclass), §6 (sequence numbering) — field names and structure cross-references
- **`GNUS_Subwallet_Architecture_Proposal.md`** §Main-Wallet Registration — conceptual registration flow
- **Phase 1 SKELETON (`01-child-identity-registration-protocol/SKELETON.md`)** — architectural decisions carried forward, key invariants

### Code Anchor Points Audited

Every claim about SuperGenius code in this document is grounded in a concrete file path and line number verified during the Phase 02 research audit:

| Component | File | Key Lines |
|-----------|------|-----------|
| CRDT filter registration block | `TransactionManager.cpp` | 187-213 |
| FilterTransaction (template) | `TransactionManager.cpp` | 2984-3039 |
| FilterProof (no-paired-namespace) | `TransactionManager.cpp` | 3041-3079 |
| SendTransactionItem flow | `TransactionManager.cpp` | 1127-1311 |
| GetBlockChainBase | `TransactionManager.cpp` | 1356-1368 |
| OnConsensusCertificate | `TransactionManager.cpp` | 3655-3752 |
| ValidateTransactionForConsensus | `TransactionManager.cpp` | 4234-4303 |
| ChangeTransactionState CONFIRMED | `TransactionManager.cpp` | 5110-5184 |
| GlobalDB topic API | `globaldb.hpp` | 152-154 |
| RegisterElementFilter | `globaldb.hpp` | 167 |
| PubSubBroadcasterExt | `pubsub_broadcaster_ext.hpp` | 48, 68-74 |
| ElementFilterCallback type | `crdt_data_filter.hpp` | 30 |
| HierarchicalKey | `hierarchical_key.hpp` | — |
| NONCE_SUBJECT_TYPE | `Consensus.hpp` | 37 |
| CreateNonceSubject | `Consensus.hpp` | 410-416 |

### Explicitly Deferred to Phase 3

The following concerns are **out of scope** for Phase 2 and are explicitly deferred to Phase 3:

| Category | IDs | Description |
|----------|-----|-------------|
| Discovery & Monitoring UI | DISC-01, DISC-02, DISC-03 | Per-child balance display, asset view, game/publisher grouping; main wallet dashboard |
| Reward Policy | RWD-01, RWD-02, RWD-03 | Per-child `dev_addr`/`peers_cut` resolution, hold-time pinning, authenticated update rules |
| Lifecycle State Machine | LIFE-01, LIFE-02, LIFE-03, LIFE-04 | Standalone → pending → registered → detached/revoked/closed; replace/remove main wallet; "supersedes seq N" linkage |
| Platform UI | PLAT-01, PLAT-02 | "Connect GNUS Wallet" UI flows on Android/iOS/desktop (v2) |
| Aggregated Registry Topic | ADV-02 | Publisher-scale child fan-out for monitoring (v2) |

---

## 2. CRDT Namespace & Key Layout (SYNC-01)

### D-11: Dedicated `reg/` Namespace

RegistrationTx lives in a **`reg/` namespace only** — it does NOT get a `tx/` entry. A new `FilterRegistration` method on TransactionManager gates incoming `reg/` deltas, parallel to the existing `FilterTransaction` for `tx/` and `FilterProof` for `proof/`.

The filter is registered in the `TransactionManager::New()` constructor, in the same block as the existing `tx/` and `proof/` filter registrations (`TransactionManager.cpp:187-213`):

```cpp
// Existing tx/ filter (lines 191-201):
bool crdt_tx_filter_initialized = instance->globaldb_m->RegisterElementFilter(
    "^/?" + blockchain_base + "tx/[^/]+",
    [weak_ptr(...)](const crdt::pb::Element &element) -> std::optional<std::vector<crdt::pb::Element>>
    { if (auto strong = weak_ptr.lock()) return strong->FilterTransaction(element); return std::nullopt; });

// Existing proof/ filter (lines 203-213):
bool crdt_proof_filter_initialized = instance->globaldb_m->RegisterElementFilter(
    "^/?" + blockchain_base + "proof/[^/]+",
    [weak_ptr(...)](const crdt::pb::Element &element) -> std::optional<std::vector<crdt::pb::Element>>
    { if (auto strong = weak_ptr.lock()) return strong->FilterProof(element); return std::nullopt; });

// New reg/ filter (appended at ~line 215):
bool crdt_reg_filter_initialized = instance->globaldb_m->RegisterElementFilter(
    "^/?" + blockchain_base + "reg/([^/]+)",
    [weak_ptr(...)](const crdt::pb::Element &element) -> std::optional<std::vector<crdt::pb::Element>>
    { if (auto strong = weak_ptr.lock()) return strong->FilterRegistration(element); return std::nullopt; });
```

The element filter regex pattern is:

```
^/?/bc-{net}/reg/([^/]+)
```

The capture group `([^/]+)` extracts the child address. This differs from the `tx/[^/]+` and `proof/[^/]+` patterns (which use Kleene star) because the `reg/` filter needs to extract the child address from the key for post-filter operations per D-12/D-14.

### D-12: Single Key Per Child

CRDT key structure: **`reg/{child_addr}`** — a single CRDT element per child wallet, updated in-place on each valid registration event with a higher sequence. This matches the validator registry pattern (single key = current state). History is derived from the chain of RegistrationTx entries traversed through the account's nonce chain.

There is **no paired namespace** for `reg/`. Unlike `tx/` → `proof/` (which cascade-delete each other), `reg/` entries are standalone. A tombstone rejection returns `{{element}}` (self-only), not a cascade-delete vector.

### Key Construction Formula

The full CRDT key is constructed as:

```
Key = GetBlockChainBase() + "reg/" + child_addr
```

Where `GetBlockChainBase()` (`TransactionManager.cpp:1356-1368`) resolves to `/bc-{network_id}/`:

```cpp
// Source: TransactionManager.cpp:1356-1368
// Constant: TRANSACTION_BASE_FORMAT = "/bc-%hu/" (from TransactionManager.hpp:296)
std::string TransactionManager::GetBlockChainBase(uint16_t network_id) {
    boost::format tx_key{ std::string(TRANSACTION_BASE_FORMAT) };
    tx_key % network_id;
    return tx_key.str();
    // Result: "/bc-963/" (TestNet), "/bc-369/" (MainNet)
}
```

Concrete key examples:

| Network | Network ID | Full CRDT Key |
|---------|-----------|---------------|
| TestNet | 963 | `/bc-963/reg/<child_addr_hex>` |
| MainNet | 369 | `/bc-369/reg/<child_addr_hex>` |

The key is stored using `HierarchicalKey` from `SuperGenius/src/crdt/hierarchical_key.hpp`:

```cpp
crdt::HierarchicalKey reg_key(GetBlockChainBase() + "reg/" + child_addr);
```

### D-14: CRDT Value = Full RegistrationTx Protobuf

The CRDT element **value** at `reg/{child_addr}` is the **full RegistrationTx protobuf** — including all fields:

| Field | Contents |
|-------|----------|
| `dag_struct` (field 1) | Source address (child), nonce, timestamp, signature |
| `main_address` (field 2) | Registered main wallet public key (128-hex, no "0x" prefix) |
| `sequence` (field 3) | Monotonic per-child registration sequence number |
| `metadata` (field 4) | Optional `RegistrationMetadata`: `game_id`, `publisher_id`, `dev_wallet`, `peers_cut` |

The value is self-contained — no cross-referencing needed for independent verification. The protobuf is stored as a CRDT `Buffer` via `GlobalDB::Put` (`globaldb.hpp:115`):

```cpp
crdt::GlobalDB::Buffer data_transaction;
data_transaction.put(registration_tx.SerializeByteVector());
crdt_transaction->Put(std::move(reg_key), std::move(data_transaction));
```

### Three-Namespace Comparison

| Namespace | Key Pattern | Key Type | Paired Namespace | Purpose |
|-----------|-------------|----------|------------------|---------|
| `tx/` | `/bc-{net}/tx/{hash}` | Transaction hash | `proof/` (cascade-delete) | Transfer/Mint/Escrow records |
| `proof/` | `/bc-{net}/proof/{hash}` | Transaction hash | `tx/` (reverse cascade) | Proof-of-work records |
| `reg/` | `/bc-{net}/reg/{child_addr}` | Child address | None (standalone) | Registration records |

### Element Filter Regex Pattern

The regex for the element filter is:

```
^/?/bc-{net}/reg/([^/]+)
```

The capture group `([^/]+)` extracts the child address from the matched key. This differs from the `tx/` and `proof/` patterns:

| Namespace | Regex Pattern | Capture Group |
|-----------|--------------|--------------|
| `tx/` | `^/?/bc-{net}/tx/[^/]+` | None (Kleene star) |
| `proof/` | `^/?/bc-{net}/proof/[^/]+` | None (Kleene star) |
| `reg/` | `^/?/bc-{net}/reg/([^/]+)` | `([^/]+)` extracts child address |

The `reg/` capture group is necessary because the filter needs to:
1. Extract the child address for sequence-monotonicity lookup (gate 3)
2. Extract the child address for well-formed validation (gate 4)
3. Potentially extract the child address for certified-status queries downstream

---

## 3. FilterRegistration Design (SYNC-02)

### D-13: Four Rejection Gates

`FilterRegistration` validates incoming CRDT deltas on the `reg/` pattern through four sequential rejection gates. An element that passes all four gates is **accepted**; failure at any gate causes the element to be **tombstoned**. The filter uses the `do { ... } while(0)` + `should_delete` pattern established by `FilterTransaction` (`TransactionManager.cpp:2984-3039`).

```
┌─────────────────────────────────────────────────────────────────┐
│ FilterRegistration(element) → std::optional<vector<Element>>     │
│                                                                  │
│  1. Deserialize element.value() → RegistrationTx                 │
│     │ FAIL → return {{tombstone}}                                │
│                                                                  │
│  2. Validate child signature (tx.CheckSignature())               │
│     │ FAIL → return {{tombstone}}                                │
│                                                                  │
│  3. Check current record exists?                                 │
│     │ YES → deserialize current record                           │
│     │       └─ new_tx.sequence > current.sequence?               │
│     │           NO → return {{tombstone}}                        │
│     │ NO → accept (first registration)                           │
│                                                                  │
│  4. Well-formed check (main_address valid, sequence > 0)         │
│     │ FAIL → return {{tombstone}}                                │
│                                                                  │
│  5. return std::nullopt  (ACCEPT)                                │
│                                                                  │
│  Note: No cascade-delete — reg/ has no paired namespace.         │
└─────────────────────────────────────────────────────────────────┘
```

### Gate 1: Deserialization

The incoming element's value (protobuf bytes) is deserialized into a `RegistrationTx`:

```cpp
auto maybe_tx = DeSerializeTransaction(element.value());
// Or: RegistrationTx::DeSerializeByteVector(element.value())
if (maybe_tx.has_error()) {
    break; // should_delete=true, return {{element}} tombstone
}
```

Deserialization failure produces an error log and a tombstone. The existing `DeSerializeTransaction` dispatch path (`TransactionManager.cpp` deserializer registry) or a RegistrationTx-specific `DeSerializeByteVector` can be used — both paths are available.

### Gate 2: Signature Validation

The child's signature on the `RegistrationTx` is validated:

```cpp
if (!tx.CheckSignature()) {
    // Or: !CheckTransactionAuthorization(*tx)
    break; // should_delete=true, return {{element}} tombstone
}
```

RegistrationTx inherits from `GeniusTransaction`, which provides `CheckSignature()` (`GeniusTransaction.hpp`). The signature is validated against `DAGStruct.source_addr` (the child's public key). This mirrors the `CheckTransactionAuthorization` call in `FilterTransaction` (`TransactionManager.cpp:2998`).

### Gate 3: Sequence Monotonicity

This is the **unique** gate not present in `FilterTransaction` or `FilterProof`. The filter reads the current `reg/{child_addr}` record from CRDT and validates that the new registration's `sequence` is strictly higher:

```cpp
// Read current registration record
auto current_result = globaldb_m->Get(HierarchicalKey(element.key()));
if (current_result.has_value()) {
    // Existing record found — deserialize and compare sequences
    auto current_tx = DeSerializeRegistration(current_result.value());
    if (current_tx.has_value()) {
        if (new_tx.sequence() <= current_tx.value().sequence()) {
            // Sequence not strictly higher — reject
            break; // should_delete=true, return {{element}} tombstone
        }
    }
}
// No existing record → first registration → accept (continue to gate 4)
```

**First registration** (no existing `reg/{child_addr}` entry) passes this gate unconditionally.

**Subsequent registrations** require `new_tx.sequence() > current.sequence()`. Equal or lower sequences are rejected.

> **Best-effort optimization:** The sequence check at the CRDT filter level is a best-effort gate (Pitfall 1 from `02-RESEARCH.md`). The CRDT is eventually consistent — a peer may not yet have the latest delta, and the filter runs on local CRDT state. Authoritative sequence enforcement happens at the **consensus level** through the nonce chain (D-25: first-to-consensus wins).

### Gate 4: Well-Formed Validation

The RegistrationTx must carry well-formed fields:

```cpp
// Validate main_address is a valid 128-hex public key
if (!GeniusAccount::IsValidPublicKey(tx.main_address())) {
    break; // should_delete=true, return {{element}} tombstone
}
// Validate sequence > 0
if (tx.sequence() == 0) {
    break; // should_delete=true, return {{element}} tombstone
}
```

- `NumAccounts::numAccounts::IsValidPublicKey` (`GeniusAccount.hpp:152`): confirms the string is exactly 128 hex characters
- `sequence > 0`: ensures the field carries a meaningful monotonic counter (0 = default/unspecified per proto3)

This well-formed check is more explicit than `FilterTransaction`'s approach. `FilterTransaction` relies on the implicit validation of `transaction_parsers` lookup (type must be registered) and the hash/key validation within `DeSerializeTransaction`. `FilterRegistration` explicitly validates its unique fields because those fields are not covered by the generic transaction validation path.

### No Cascade-Delete

Unlike `FilterTransaction` (which cascade-deletes the paired `proof/` key on rejection), `FilterRegistration` performs **no cascade-delete**. The `reg/` namespace has no paired namespace (there is no `reg-proof/` or similar). When rejecting, the filter returns `{{element}}` — a tombstone for the element itself only. This matches `FilterProof`'s "self-tombstone-only" pattern (`TransactionManager.cpp:3041-3079`).

```cpp
if (should_delete) {
    // No cascade-delete — reg/ has no paired namespace (D-13)
    std::vector<crdt::pb::Element> tombstones;
    tombstones.push_back(element); // tombstone self only
    maybe_tombstones = tombstones;
    return maybe_tombstones;
}
// On success:
should_delete = false;
return std::nullopt; // ACCEPT
```

### FilterRegistration vs FilterTransaction Comparison

| Aspect | FilterTransaction | FilterRegistration |
|--------|-------------------|-------------------|
| Deserialization | `DeSerializeTransaction` (generic dispatch) | `DeSerializeTransaction` or RegistrationTx-specific path |
| Signature check | `CheckTransactionAuthorization(*new_tx)` | `tx.CheckSignature()` (child-signed per D-04) |
| Key collision / sequence | `KeyExistsInDB(GetTransactionPath(*new_tx))` — rejects if key exists | Read current `reg/{child_addr}`, check `new_tx.sequence > current.sequence`. First registration: accept. Lower/equal sequence: reject. |
| Cascade-delete | Deletes paired `proof/` key on rejection | **None** — `reg/` has no paired namespace (D-13). Return `{{element}}` for tombstone rejection only. |
| Well-formed check | Implicit via `transaction_parsers` lookup | Explicit: `main_address` is valid public key via `GeniusAccount::IsValidPublicKey`, `sequence > 0` |
| Return semantics | `std::nullopt` = accept, non-empty vector = tombstone-delete | Same: `std::nullopt` = accept, `{{element}}` = reject |

### Design Authority

The FilterRegistration design is grounded in:

- **`FilterTransaction`** (`TransactionManager.cpp:2984-3039`) — structural template: `do { ... } while(0)`, `should_delete` flag, `break` on fail gates, tombstone return on rejection
- **`FilterProof`** (`TransactionManager.cpp:3041-3079`) — self-tombstone-only pattern for no-paired-namespace filters
- **D-13** (`02-CONTEXT.md`) — the four rejection gate specification
- **Pitfall 1** (`02-RESEARCH.md` lines 441-449) — best-effort sequence validation, authoritative ordering at consensus level

---

## 4. PubSub Broadcast & Subscription (SYNC-03, SYNC-04, SYNC-05)

### PubSub API Surface

The pubsub channel API is provided by `PubSubBroadcasterExt` (`pubsub_broadcaster_ext.hpp`), wrapped by `GlobalDB` (`globaldb.hpp:152-154`). Three methods are relevant:

| Method | Signature | Purpose |
|--------|-----------|---------|
| `AddBroadcastTopic` | `outcome::result<void> AddBroadcastTopic(const std::string &topicName)` | Publish CRDT deltas on a topic |
| `AddListenTopic` | `void AddListenTopic(std::string topic)` | Subscribe to a topic for incoming CRDT deltas |
| `Broadcast` | `outcome::result<void> Broadcast(const base::Buffer &buff, std::string topic, boost::optional<libp2p::peer::PeerInfo> peerInfo = boost::none)` | Send a payload on a topic |

```cpp
// Source: pubsub_broadcaster_ext.hpp:68-74
outcome::result<void> AddBroadcastTopic(const std::string &topicName);
void AddListenTopic(std::string topic);

// Source: pubsub_broadcaster_ext.hpp:48
outcome::result<void> Broadcast(const base::Buffer &buff, std::string topic,
    boost::optional<libp2p::peer::PeerInfo> peerInfo = boost::none);
```

### SYNC-03: Child's Broadcast Flow (D-15)

When a child creates a `RegistrationTx`, `SendTransactionItem` (`TransactionManager.cpp:1127-1311`) handles both CRDT persistence and pubsub notification. The flow is:

1. **Serialization & CRDT write:**
   ```cpp
   auto tx_data = transaction->SerializeByteVector();
   HierarchicalKey reg_key(GetBlockChainBase() + "reg/" + child_addr);
   crdt::GlobalDB::Buffer buffer;
   buffer.put(tx_data);
   crdt_transaction->Put(std::move(reg_key), std::move(buffer));
   ```

2. **Topic collection** — `SendTransactionItem` collects topics before commit (`TransactionManager.cpp:1163-1166`):
   ```cpp
   std::unordered_set<std::string> topicSet;
   topicSet.emplace(full_node_topic_m);       // existing: all full nodes
   topicSet.emplace(account_m->GetAddress()); // existing: own address
   topicSet.emplace(main_address);            // NEW (D-15): main's address topic
   ```
   The `main_address` topic is a new addition specific to `RegistrationTx`. It ensures the RegistrationTx CID is published on the main wallet's address topic as a **discovery shortcut**.

3. **CRDT commit** — publishes the delta on all topics in the set:
   ```cpp
   crdt_transaction->Commit(topicSet);
   ```
   This triggers three propagation paths:
   - **CRDT DAG sync** (graphsync/gossipsub): propagates the `reg/` element to all peers independently of pubsub
   - **Own address topic**: publishes on the child's own address topic (existing behavior)
   - **Main address topic**: publishes on the main's address topic (new, per D-15) — this is a **discovery shortcut**, not the primary propagation mechanism

4. **Consensus submission** — described in §5 (Section 5).

The pubsub notification on `main_address` topic is a **discovery shortcut** — the CRDT DAG sync (graphsync) propagates the RegistrationTx to all peers regardless of pubsub topic subscriptions. The notification provides low-latency discovery for the specific main wallet named in the registration.

### D-18: CID-Only Payload Constraint

The pubsub notification payload carries **only the RegistrationTx CID/hash** (the CRDT IPLD CID returned from `GlobalDB::Put`), NOT the full RegistrationTx protobuf.

**Rationale:**
- Avoids data duplication between the pubsub channel and the CRDT DAG
- Forces CRDT resolution for full content — enabling content-addressed verification
- The CID is the canonical content-addressed reference into the CRDT DAG; resolving the CID cannot produce wrong content for a given CID

**CID selection:** Use the **CRDT CID** (IPLD CID) returned from `GlobalDB::Put`, not the transaction hash (`tx.GetHash()`). The CRDT CID is the canonical content-addressed reference into the CRDT DAG. The transaction hash (`DAGStruct` hash) is a different identifier — it identifies the transaction payload, not its position in the CRDT Merkle DAG.

### SYNC-04: Main's Discovery Flow (D-16)

The main wallet receives discovery notifications through the pubsub channel, then validates and monitors:

```
┌─────────────────────────────────────────────────────────────────┐
│ Main Discovery Flow                                              │
│                                                                  │
│ 1. PubSub notification on own topic                              │
│    → receives RegistrationTx CID                                 │
│                                                                  │
│ 2. Resolve CID from CRDT                                         │
│    → Get( HierarchicalKey("/bc-{net}/reg/" + child_addr) )      │
│    → or CID-specific resolution                                  │
│                                                                  │
│ 3. Validate certification                                        │
│    → Is the registration certified by consensus? (D-26)          │
│    → NO → silently discard (Pitfall 2)                           │
│    → YES → proceed                                               │
│                                                                  │
│ 4. Subscribe to child's CRDT delta stream                        │
│    → AddListenTopic(child_address)                               │
│                                                                  │
│ 5. Merge child's CRDT deltas into local CRDT                     │
│    → read child balances, assets, transaction history            │
│    → NO child private key needed                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Step 1 — PubSub notification:** The main receives a CID on its own address topic. Any peer can publish on any topic — the notification is intrinsically untrusted.

**Step 2 — CID resolution:** The main resolves the CID from CRDT. The CID is content-addressed — resolving it cannot produce wrong content. Two resolution paths are available:
- Direct key lookup: `globaldb_m->Get(HierarchicalKey(GetBlockChainBase() + "reg/" + child_addr))`
- CID-based resolution through the graphsync DAG syncer

**Step 3 — Certification validation (critical):** Before acting on a registration, the main MUST verify the registration is **certified by consensus** (D-26). Uncertified registrations are silently discarded. This is the authorization gate between pubsub discovery and authoritative registration state. See §6 for the certified status flag design.

**Step 4 — Subscribe to child's topic:** On confirmed certified registration, the main calls `AddListenTopic(child_address)` to subscribe to the child's CRDT delta stream:

```cpp
// Follows existing pattern from TransactionManager::StartListeningTopics (line ~355):
globaldb_m->AddListenTopic(child_address);
```

**Step 5 — Merge child CRDT deltas:** The child's node already broadcasts CRDT deltas on its own address topic (via `SendTransactionItem` topic set including `account_m->GetAddress()`). The main receives these deltas through its `AddListenTopic(child_address)` subscription and merges them into its local CRDT. This provides:
- Child balance monitoring (read-only)
- Child asset tracking
- Child transaction history visibility

No child private key is needed — the main reads public CRDT state only.

### SYNC-04: Ongoing Child State Sync (D-17)

After initial discovery, the ongoing sync flow is:

1. The child's node publishes CRDT deltas on its own address topic as part of normal operation (existing behavior — `SendTransactionItem` always includes `account_m->GetAddress()` in the topic set)
2. The main receives these deltas through its `AddListenTopic(child_address)` subscription
3. The main merges received deltas into its local CRDT — no child private key needed for read-only sync
4. The main can display child balances, assets, and transaction history to the user (Phase 3 DISC-01..03)

### SYNC-05: Authority from Signatures + Consensus, NOT Topic Membership (D-16)

> **"Authority is NEVER derived from topic membership."**

The validation flow establishes a strict chain of trust:

```
PubSub notification (untrusted)
  → CID resolution from CRDT (content-addressed)
    → Consensus certificate check (authoritative)
      → Authority gate acts (D-26 certified status)
```

| Trust Level | Component | Trust Basis |
|-------------|-----------|-------------|
| Untrusted | PubSub notification | Any peer can publish on any topic |
| Content-addressed | CID resolution | CRDT CID cannot produce wrong content for a given hash |
| Authoritative | Consensus certificate | Validated by the validator quorum; nonce chain provides total ordering |
| Actionable | Certified status flag | Only certified registrations are acted upon; uncertified entries are optimistic storage |

**Key invariants:**
- Topic membership gates **nothing** — all authority derives from cryptographic signatures validated by consensus
- A malicious peer publishing on the main's topic can produce only a discovery notification; the CID must resolve to a valid RegistrationTx that passed consensus certification for any authority to apply
- The pubsub channel is a discovery mechanism, not an authorization mechanism

### Pitfall 3: CID Resolution Failure

**What goes wrong:** The main receives a pubsub notification with a CID, but the CID cannot be resolved from CRDT (the DAG sync hasn't propagated it yet, or it was fabricated).

**Mitigation:** The main handles CID resolution failure gracefully:
1. Retry with exponential backoff (up to a configurable timeout)
2. Silently discard unresolvable CIDs after timeout exhaustion
3. Never block waiting for CID resolution

An unresolvable pubsub notification is silently discarded — it does not create a phantom registration. CRDT DAG sync (graphsync) propagates the full record independently of pubsub; if the CID can't be resolved, the registration will eventually arrive through standard CRDT sync.

