# Phase 3: Discovery, Rewards & Lifecycle - Pattern Map

**Mapped:** 2026-07-14
**Files analyzed:** 12 code touchpoints across 10 source files
**Analogs found:** 12 / 12

## File Classification

| Code Touchpoint (design doc will describe) | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `SGAccountComm.proto` — `ChildDiscoveryRequest` / `ChildDiscoveryResponse` (arms 10/11) | proto | request-response | `NonceRequest`/`NonceResponse` (arms 1/2) in same file | exact |
| `AccountMessenger::RequestChildDiscovery` + `HandleChildDiscovery{Request,Response}` | handler | request-response | `HandleNonceRequest`/`HandleNonceResponse` pair | exact |
| `SGTransaction.proto` — `RegistrationTx` fields 5 (`detach_flag`), 6 (`supersedes_sequence`) | proto | additive | `EscrowTx` fields 4 (`dev_addr`), 5 (`peers_cut`) appended to DAGStruct=1 | exact |
| `Consensus.proto` `EmbeddedTransaction` — oneof arm 9 (`RevokeTx`) | proto | additive | Oneof arms 6 (`EscrowTx`), 7 (`EscrowReleaseTx`) | exact |
| `SGTransaction.proto` — new `RevokeTx` message | proto | additive | `EscrowTx` message (fields 1-5) | exact |
| `TransactionManager::HoldEscrow` — read policy from reg/ CRDT | service | CRUD | `GeniusNode::ProcessImage` reads `dev_config_.Addr`/`.Cut` (GeniusNode.cpp:1977-1985) | role-match |
| `GeniusNode::PayDev` — read target addr from reg/ CRDT | service | request-response | `PayDev` reads `dev_config_.Addr` (GeniusNode.cpp:2261-2264) | exact |
| `TransactionManager::ValidateTransactionForConsensus` — revoke gate path | middleware | request-response | Same function: 5-gate pipeline (TransactionManager.cpp:4234-4304) | exact |
| `TransactionManager::FilterRegistration` — supersedes_sequence validation | filter | event-driven | `FilterTransaction` `do{}while(0)` + `should_delete` + tombstone pattern (TransactionManager.cpp:2984-3039) | exact |
| `TransactionManager::New` — `reg/` namespace `RegisterElementFilter` | filter | event-driven | `tx/` namespace filter registration (TransactionManager.cpp:187-201) | exact |
| `EscrowTransaction` hold-time pinning (no Phase 3 change) | model | CRUD | Same file: constructor pins `dev_addr_`/`peers_cut_` (EscrowTransaction.hpp:122-131) | exact |
| `Consensus.hpp` `NONCE_SUBJECT_TYPE` — for revoke tx consensus | config | event-driven | Same constant: `"sgns.nonce.v1"` (Consensus.hpp:37) | exact |

## Pattern Assignments

---

### 1. AccountMessenger Request/Response — `ChildDiscovery{Request,Response}`

**Analog:** `HandleNonceRequest` / `HandleNonceResponse` (AccountMessenger.cpp:1472-1564 / 1566-1614)
Also: `HandleHeadRequest` (AccountMessenger.cpp:1746-1785) — broadcast-style query

**Proto pattern — NonceRequest message (SGAccountComm.proto:29-42):**
```protobuf
// SGAccountComm.proto:29-42 — request with requester_address + request_id + timestamp
message NonceRequest {
  string requester_address = 1;
  uint64 request_id = 2;
  uint64 timestamp = 3;
}

message NonceResponse {
  string responder_address = 1;
  string requester_address = 2;
  uint64 request_id = 3;
  uint64 known_nonce = 4;
  uint64 timestamp = 5;
  bool has_nonce = 6;
}
```

**Proto pattern — Signed wrapper + oneof arm (SGAccountComm.proto:19-27, 5-17):**
```protobuf
// SGAccountComm.proto:19-22 — signed wrapper: data=1, signature=2
message SignedNonceRequest {
  NonceRequest data = 1;
  bytes signature = 2;
}

// SGAccountComm.proto:5-17 — oneof dispatch hub
message AccountMessage {
  oneof payload {
    SignedNonceRequest nonce_request = 1;
    SignedNonceResponse nonce_response = 2;
    SignedBlockRequest block_request = 3;
    SignedBlockResponse block_response = 4;
    SignedHeadRequest head_request = 5;
    SignedBlockCidRequest block_cid_request = 6;
    SignedUTXORequest utxo_request = 7;
    SignedUTXOResponse utxo_response = 8;
    SignedTransactionRequest transaction_request = 9;
    // Phase 3 additions (arms 10/11):
    // SignedChildDiscoveryRequest child_discovery_request = 10;
    // SignedChildDiscoveryResponse child_discovery_response = 11;
  }
}
```

**Sender pattern (AccountMessenger.cpp:276-303, RequestNonce):**
```cpp
// AccountMessenger.cpp:276-303 — 1. Construct proto, 2. Sign, 3. Wrap in AccountMessage, 4. SendAccountMessage
outcome::result<void> AccountMessenger::RequestNonce(uint64_t req_id) {
    accountComm::NonceRequest req;
    req.set_requester_address(address_);
    req.set_request_id(req_id);
    req.set_timestamp(
        std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count());

    std::string encoded;
    if (!req.SerializeToString(&encoded)) {
        return outcome::failure(Error::PROTO_DESERIALIZATION);
    }

    std::vector<uint8_t> serialized_vec(encoded.begin(), encoded.end());
    BOOST_OUTCOME_TRY(auto signature, methods_.sign_(serialized_vec));
    accountComm::SignedNonceRequest signed_req;
    *signed_req.mutable_data() = req;
    signed_req.set_signature(signature.data(), signature.size());

    accountComm::AccountMessage envelope;
    *envelope.mutable_nonce_request() = signed_req;

    auto send_ret = SendAccountMessage(envelope, {requests_topic_});
    return send_ret;
}
```

**Request handler pattern (AccountMessenger.cpp:1472-1564, HandleNonceRequest):**
```cpp
// AccountMessenger.cpp:1472-1564 — 1. Verify requester signature, 2. Gather data, 3. Build SignedResponse, 4. Send via SendAccountMessage
void AccountMessenger::HandleNonceRequest(const accountComm::SignedNonceRequest &signed_req) {
    const auto &req = signed_req.data();

    // Verify requester's signature over serialized request data
    std::string serialized;
    if (!req.SerializeToString(&serialized)) { return; }
    std::vector<uint8_t> serialized_vec(serialized.begin(), serialized.end());
    auto verify_sig = methods_.verify_signature_(req.requester_address(),
                                                  signed_req.signature(), serialized_vec);
    if (verify_sig.has_error() || !verify_sig.value()) { return; }

    // Gather local data
    auto local_nonce_result = methods_.get_local_nonce_(req.requester_address());

    // Build response
    accountComm::NonceResponse resp;
    resp.set_responder_address(address_);
    resp.set_requester_address(req.requester_address());
    resp.set_request_id(req.request_id());
    resp.set_timestamp(...);
    resp.set_has_nonce(!local_nonce_result.has_error());
    resp.set_known_nonce(local_nonce_result.has_value() ? local_nonce_result.value() : 0);

    // Sign + wrap response
    std::string resp_serialized;
    resp.SerializeToString(&resp_serialized);
    std::vector<uint8_t> resp_bytes(resp_serialized.begin(), resp_serialized.end());
    auto signature_result = methods_.sign_(resp_bytes);
    // ...
    accountComm::SignedNonceResponse signed_resp;
    *signed_resp.mutable_data() = resp;
    signed_resp.set_signature(signature.data(), signature.size());

    accountComm::AccountMessage msg;
    *msg.mutable_nonce_response() = signed_resp;

    // Send response to requester's .comm topic
    auto account_topic = req.requester_address() + std::string(ACCOUNT_COMM) +
                         sgns::version::GetNetAndVersionAppendix();
    auto send_ret = SendAccountMessage(msg, {account_topic});
}
```

**Response collector pattern (AccountMessenger.cpp:1566-1614, HandleNonceResponse):**
```cpp
// AccountMessenger.cpp:1566-1614 — 1. Verify responder sig, 2. Extract data, 3. Merge into response map keyed by request_id
void AccountMessenger::HandleNonceResponse(const accountComm::SignedNonceResponse &signed_resp) {
    const auto &resp = signed_resp.data();

    // Verify responder signature
    std::string serialized;
    resp.SerializeToString(&serialized);
    std::vector<uint8_t> data_vec(serialized.begin(), serialized.end());
    auto verify_sig = methods_.verify_signature_(resp.responder_address(),
                                                  signed_resp.signature(), data_vec);
    if (verify_sig.has_error() || !verify_sig.value()) { return; }

    // Collect into map keyed by request_id
    std::lock_guard lock(nonce_responses_mutex_);
    if (resp.has_nonce()) {
        nonce_responses_[resp.request_id()].insert(resp.known_nonce());
    } else {
        no_nonce_responses_[resp.request_id()].insert(resp.responder_address());
    }
}
```

**Topic constants (AccountMessenger.hpp:199-202):**
```cpp
// AccountMessenger.hpp:199-202 — two-pubsub-topic architecture
static constexpr std::string_view ACCOUNT_COMM  = ".comm";               // personal: address + ".comm"
static constexpr std::string_view REQUESTS_COMM = "SGNUS.BC.Requests.comm"; // global broadcast
```

**OnRequest dispatch pattern (AccountMessenger.cpp:190-231):**
```cpp
// AccountMessenger.cpp:190-231 — switch on payload_case(), add child_discovery_request arm
void AccountMessenger::OnRequest(boost::optional<const ipfs_pubsub::GossipPubSub::Message &> message) {
    // ... parse acc_msg ...
    switch (acc_msg.payload_case()) {
        case accountComm::AccountMessage::kNonceRequest:
            HandleNonceRequest(acc_msg.nonce_request()); break;
        // ... existing arms ...
        // Phase 3: case ...::kChildDiscoveryRequest:  HandleChildDiscoveryRequest(...); break;
        case ...: /* unexpected */ break;
    }
}
```

**SendAccountMessage (AccountMessenger.cpp:868-884):**
```cpp
// AccountMessenger.cpp:868-884 — serialize + Publish to each topic in set
outcome::result<void> AccountMessenger::SendAccountMessage(
    const accountComm::AccountMessage &msg, const std::set<std::string> &topics) {
    size_t size = msg.ByteSizeLong();
    std::vector<uint8_t> serialized_proto(size);
    if (!msg.SerializeToArray(serialized_proto.data(), serialized_proto.size())) {
        return outcome::failure(Error::PROTO_SERIALIZATION);
    }
    for (auto &topic : topics) {
        pubsub_->Publish(topic, serialized_proto);
    }
    return outcome::success();
}
```

**WorkerLoop + EnqueueTask pattern (AccountMessenger.cpp:886-1008, 1011-1018):**
```cpp
// AccountMessenger.cpp:886-1008 — worker thread dequeues, dispatches by RequestType:: enum
void AccountMessenger::WorkerLoop() {
    while (true) {
        RequestTask task;
        { /* dequeue with cv wait */ }
        switch (task.type) {
            case RequestType::Nonce: { /* PerformNonceRequest with timeout */ break; }
            case RequestType::Genesis: { /* PerformBlockRequest with callback */ break; }
            // Phase 3: case RequestType::ChildDiscovery: { /* ... */ break; }
        }
    }
}
// AccountMessenger.hpp:270-277 — RequestType enum
enum class RequestType : std::uint8_t {
    Nonce, Genesis, AccountCreation, ValidatorRegistry, BlockByCid, UTXO, Transaction
    // Phase 3: ChildDiscovery
};
```

**Exact discovery extension blueprint:**
1. Add `ChildDiscoveryRequest`/`ChildDiscoveryResponse` + signed wrappers to `SGAccountComm.proto`
2. Add oneof arms 10/11 in `AccountMessage.payload`
3. Add `HandleChildDiscoveryRequest` (sent to `OnRequest` switch) — scan local CRDT `reg/` namespace, filter by `main_address`, respond with CID list
4. Add `HandleChildDiscoveryResponse` (sent to `OnResponse` switch) — collect CIDs, merge into map
5. Add public `RequestChildDiscovery(main_address, timeout_ms, callback)` method following `RequestGenesis`/`RequestHeads` pattern
6. Add `RequestType::ChildDiscovery` to the enum

---

### 2. Proto Additive-Field Numbering — `RegistrationTx` + `RevokeTx` + `EmbeddedTransaction`

**Analog 2a: `EscrowTx` fields appended after `dag_struct = 1` (SGTransaction.proto:120-127):**
```protobuf
// SGTransaction.proto:120-127 — all tx messages: dag_struct=1 always first, then payload fields
message EscrowTx {
    DAGStruct dag_struct = 1;
    UTXOTxParams utxo_params = 2;
    uint64 amount = 3;
    bytes dev_addr = 4;       // additive field appended after existing fields
    uint64 peers_cut = 5;     // additive field appended after existing fields
}
```

**Phase 3 RegistrationTx extension (assuming Phase 1 fields 1-4 exist):**
```protobuf
// Phase 1 fields: dag_struct=1, main_address=2, sequence=3, metadata=4
// Phase 3 additions:
message RegistrationTx {
    DAGStruct dag_struct = 1;            // Phase 1
    bytes main_address = 2;              // Phase 1
    uint64 sequence = 3;                 // Phase 1
    RegistrationMetadata metadata = 4;   // Phase 1 (game_id, publisher_id, dev_wallet, peers_cut)
    bool detach_flag = 5;               // Phase 3: D-35 (true = child-initiated detach)
    uint64 supersedes_sequence = 6;     // Phase 3: D-38 (refs sequence being replaced; 0 = new reg)
}
```

**Analog 2b: `EmbeddedTransaction` oneof field numbering (Consensus.proto:70-80):**
```protobuf
// Consensus.proto:70-80 — field numbers 1-7 consumed, 8+ available for new tx types
message EmbeddedTransaction {
    oneof transaction {
        SGTransaction.TransferTx transfer = 1;
        SGTransaction.MintTxV2 mint_v2 = 2;
        SGTransaction.MintTx mint = 3;
        SGTransaction.ProcessingTx processing = 4;
        SGTransaction.MigrationTx migration = 5;
        SGTransaction.EscrowTx escrow = 6;
        SGTransaction.EscrowReleaseTx escrow_release = 7;
        // Phase 1 reserve:  SGTransaction.RegistrationTx registration = 8;
        // Phase 3:          SGTransaction.RevokeTx revoke = 9;
    }
}
```

**Analog 2c: New `RevokeTx` proto message — follow `EscrowTx` shape:**
```protobuf
// Pattern: DAGStruct dag_struct = 1; // always first, then typed payload fields
message RevokeTx {
    DAGStruct dag_struct = 1;
    bytes child_address = 2;        // address of the child wallet being revoked
    uint64 registration_sequence = 3; // sequence of the reg/ record being revoked
    // No UTXOTxParams — revoke is a lifecycle tx, not a value-transfer tx
}
```

**Analog 2d: `SGAccountComm.proto` oneof arms → additive convention (lines 5-17):**
```protobuf
// SGAccountComm.proto:5-17 — arms 1-9 consumed; next = 10, 11
message AccountMessage {
    oneof payload {
        SignedNonceRequest nonce_request = 1;
        // ... arms 2-9 ...
        // Phase 3: SignedChildDiscoveryRequest child_discovery_request = 10;
        // Phase 3: SignedChildDiscoveryResponse child_discovery_response = 11;
    }
}
```

---

### 3. Reward-Source Integration — `HoldEscrow` reads from reg/ CRDT vs DevConfig

**Analog 3a: `GeniusNode` caller reads `dev_config_` (GeniusNode.cpp:1977-1985):**
```cpp
// GeniusNode.cpp:1977-1985 — current path: dev_config_ → HoldEscrow params
auto cut = sgns::TokenAmount::ParseMinions(dev_config_.Cut);
if (!cut) { return outcome::failure(cut.error()); }

BOOST_OUTCOME_TRY(auto manager, GetTransactionManager());
BOOST_OUTCOME_TRY(auto result_pair,
                   manager->HoldEscrow(funds,
                                       std::string(dev_config_.Addr),  // dev_addr
                                       cut.value(),                     // peers_cut
                                       uuidstring));                    // job_id
```

**Phase 3 integration point — policy-source selection before HoldEscrow:**
```cpp
// Pseudocode: the Phase 3 design doc describes this GeniusNode-level change:
// Before calling manager->HoldEscrow(), resolve the reward policy source:
//
//   1. Look up certified reg/{child_addr} CRDT record
//   2. If found (registered child): use RegistrationMetadata.dev_wallet / .peers_cut
//   3. If NOT found (standalone child): use dev_config_.Addr / dev_config_.Cut  (current behavior)
//
// Then call HoldEscrow with the resolved dev_addr and peers_cut.
```

**Analog 3b: `HoldEscrow` receives params — no change needed (TransactionManager.cpp:778-810):**
```cpp
// TransactionManager.cpp:778-810 — receives dev_addr and peers_cut as parameters
// The caller (GeniusNode) chooses the source; TransactionManager is policy-agnostic
outcome::result<std::pair<std::string, EscrowDataPair>> TransactionManager::HoldEscrow(
    uint64_t amount, const std::string &dev_addr, uint64_t peers_cut, const std::string &job_id)
{
    if (GetState() != State::READY) { return outcome::failure(boost::system::error_code{}); }

    auto hash_data = hasher_m->blake2b_256(std::vector<uint8_t>{job_id.begin(), job_id.end()});
    const std::string lock_id = "0x" + hash_data.toReadableString();

    BOOST_OUTCOME_TRY(auto params,
                      account_m->GetUTXOManager().CreateTxParameter(amount, lock_id,
                                                                     TokenID::FromBytes({0x00})));
    auto [inputs, outputs] = params;
    auto escrow_transaction = std::make_shared<EscrowTransaction>(
        EscrowTransaction::New(params, amount, dev_addr, peers_cut, FillDAGStruct(lock_id)));

    escrow_transaction->MakeSignature(*account_m);
    account_m->GetUTXOManager().ReserveUTXOs(inputs, escrow_transaction->GetHash());

    auto txId = escrow_transaction->GetHash();
    EnqueueTransaction(std::make_pair(escrow_transaction, std::nullopt));

    crdt::GlobalDB::Buffer data_transaction;
    data_transaction.put(escrow_transaction->SerializeByteVector());

    return std::make_pair(txId, std::make_pair(lock_id, std::move(data_transaction)));
}
```

**Analog 3c: `PayDev` reads from `dev_config_.Addr` (GeniusNode.cpp:2261-2264):**
```cpp
// GeniusNode.cpp:2261-2264 — current: always reads dev_config_.Addr
outcome::result<std::string> GeniusNode::PayDev(uint64_t amount, TokenID token_id) {
    return TransferFunds(amount, dev_config_.Addr, token_id);
}
// Phase 3 integration: for registered children, read RegistrationMetadata.dev_wallet
// from certified reg/{child_addr} CRDT record instead of dev_config_.Addr.
// If not registered, fall back to dev_config_.Addr (standalone child).
```

**Analog 3d: `EscrowTransaction` constructor pins values immutably (EscrowTransaction.hpp:122-131):**
```cpp
// EscrowTransaction.hpp:122-131 — values stored at construction, NEVER re-read from reg/ CRDT
EscrowTransaction(UTXOTxParameters         params,
                  uint64_t                 amount,
                  std::string              dev_addr,
                  uint64_t                 peers_cut,
                  SGTransaction::DAGStruct dag);

UTXOTxParameters utxo_params_; ///< Signed inputs and outputs for the escrow hold.
uint64_t         amount_;      ///< Total amount locked in escrow.
std::string      dev_addr_;    ///< Developer payout address for escrow remainder.  // PINNED
uint64_t         peers_cut_;   ///< Peer payout multiplier used during escrow release. // PINNED
```

**Analog 3e: `PayEscrow` reads stored values, NOT live CRDT (TransactionManager.cpp:846-875):**
```cpp
// TransactionManager.cpp:846-875 — reads from escrow_tx (immutable), not from reg/ CRDT
BOOST_OUTCOME_TRY(auto escrow_amount_ptr, TokenAmount::New(escrow_tx->GetAmount()));
BOOST_OUTCOME_TRY(auto peers_cut_ptr, TokenAmount::New(escrow_tx->GetPeersCut()));    // line 848
// ...
// line 875: developer remainder from stored dev_addr_
payout_peers.push_back({remainder, escrow_tx->GetDevAddress(), escrowTokenId});
```

---

### 4. Consensus-Gate Path — `ValidateTransactionForConsensus` (RevokeTx)

**Analog: 5-gate pipeline (TransactionManager.cpp:4234-4304):**
```cpp
// TransactionManager.cpp:4234-4304 — the full consensus validation pipeline
// Each gate returns ConsensusManager::ValidationResult::Reject() on failure
ConsensusManager::ValidationResult TransactionManager::ValidateTransactionForConsensus(
    const std::shared_ptr<GeniusTransaction> &tx) const
{
    // Gate 0: Null check
    if (!tx) { return ConsensusManager::ValidationResult::Reject(); }

    // Gate 1: Well-formed (proto deserialization, required fields present)
    if (!CheckTransactionWellFormed(*tx)) {
        return ConsensusManager::ValidationResult::Reject();
    }

    // Gate 2: Authorization — SIGNATURE-ONLY (TransactionManager.cpp:4361-4383)
    if (!CheckTransactionAuthorization(*tx)) {
        return ConsensusManager::ValidationResult::Reject();
    }
    // CheckTransactionAuthorization (TransactionManager.cpp:4361-4383):
    //   return tx.CheckSignature() || tx.CheckDAGSignatureLegacy();

    // GATE 2.5 (Phase 2 D-19): CheckParentChildAuthority
    //   - For child→main / main→child transfers: validates reg/{child_addr} exists
    //   - For Phase 3 RevokeTx: validates reg/{child_addr}.main_address == signer
    //                         AND reg/{child_addr} is in Registered state (not detached/revoked)
    //   - This is a NEW gate in the Phase 3 revoke path — extends existing gate pattern

    // Gate 3: Timestamp within drift tolerance
    if (!CheckTransactionTimestamp(*tx)) {
        return ConsensusManager::ValidationResult::Reject();
    }

    // Gate 4: Replay protection (nonce chain, UTXO double-spend)
    auto replay_result = EvaluateTransactionReplayProtection(*tx);
    if (replay_result.validation.check != ConsensusManager::Check::Approve) {
        return replay_result.validation;
    }

    // Gate 5: Type-specific rules (e.g., escrow-hold requires >= 1 peer_payout)
    if (!CheckTransactionTypeRules(tx)) {
        return ConsensusManager::ValidationResult::Reject();
    }

    return ConsensusManager::ValidationResult::Approve();
}
```

**RevokeTx gate path — exact insertion point:**
```cpp
// Phase 2 CheckParentChildAuthority already slots between gates 2 and 3.
// For a RevokeTx the gate validates:
//   1. Main's signature is valid (gate 2 — CheckTransactionAuthorization)
//   2. reg/{child_addr} CRDT record exists (gate 2.5 — CheckParentChildAuthority)
//   3. reg/{child_addr}.main_address == signer's address
//   4. reg/{child_addr} is in Registered state (detach_flag == false)
//
// Post-validation: RevokeTx sets detach_flag = true on the reg/ CRDT record.
// The nonce chain (sgns.nonce.v1 — Consensus.hpp:37) prevents double-revoke.
```

**Nonce chain consensus (Consensus.hpp:37, TransactionManager.cpp:149-159):**
```cpp
// Consensus.hpp:37 — subject type constant
static constexpr std::string_view NONCE_SUBJECT_TYPE = "sgns.nonce.v1";

// TransactionManager.cpp:149-159 — subject handler registration
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

---

### 5. CRDT Filter — `FilterRegistration` + `supersedes_sequence`

**Analog 5a: `FilterTransaction` `do{}while(0)` + `should_delete` + tombstone pattern (TransactionManager.cpp:2984-3039):**
```cpp
// TransactionManager.cpp:2984-3039 — THE standard CRDT filter pattern
// RETURN VALUES:
//   std::nullopt                           = ACCEPT (element passes filter)
//   std::vector<crdt::pb::Element>{...}    = REJECT (return tombstones for deletion)
std::optional<std::vector<crdt::pb::Element>> TransactionManager::FilterTransaction(
    const crdt::pb::Element &element)
{
    std::optional<std::vector<crdt::pb::Element>> maybe_tombstones;
    bool                                          should_delete = true;
    std::shared_ptr<GeniusTransaction>            new_tx;
    do
    {
        // Gate 1: Deserialize
        auto maybe_new_tx = DeSerializeTransaction(element.value());
        if (maybe_new_tx.has_error()) { break; }
        new_tx = maybe_new_tx.value();

        // Gate 2: Signature
        if (!CheckTransactionAuthorization(*new_tx)) { break; }

        // Gate 3: Key collision (prevent overwrite)
        if (KeyExistsInDB(GetTransactionPath(*new_tx))) { break; }

        should_delete = false;  // ALL GATES PASSED — accept

    } while (0);

    if (should_delete)
    {
        // Build tombstone vector for cascade-delete (e.g., proof key for tx)
        std::vector<crdt::pb::Element> additional_elements_to_delete;
        auto maybe_proof_key = GetExpectedProofKey(element.key(), new_tx);
        if (maybe_proof_key.has_value()) {
            crdt::pb::Element proof_element;
            proof_element.set_key(maybe_proof_key.value());
            additional_elements_to_delete.push_back(proof_element);
        }
        maybe_tombstones = additional_elements_to_delete;
    }

    return maybe_tombstones;
}
```

**Analog 5b: RegisterElementFilter with regex — reg/ namespace registration (TransactionManager.cpp:187-201):**
```cpp
// TransactionManager.cpp:187-201 — filter registration pattern for tx/ namespace
// The reg/ filter follows the IDENTICAL pattern, just with "reg/([^/]+)" regex
auto monitored_networks = GetMonitoredNetworkIDs();
for (auto network_id : monitored_networks)
{
    std::string blockchain_base = GetBlockChainBase(network_id);
    bool crdt_tx_filter_initialized = instance->globaldb_m->RegisterElementFilter(
        "^/?" + blockchain_base + "tx/[^/]+",                    // regex pattern
        [weak_ptr(std::weak_ptr<TransactionManager>(instance))](
            const crdt::pb::Element &element) -> std::optional<std::vector<crdt::pb::Element>>
        {
            if (auto strong = weak_ptr.lock()) {
                return strong->FilterTransaction(element);       // handler that follows do{}while(0)
            }
            return std::nullopt;
        });
}
// For reg/ namespace (Phase 2 D-11), the pattern is:
//   "^/?" + blockchain_base + "reg/([^/]+)"
//   → handler: FilterRegistration(element)
```

**CRDT key construction pattern (TransactionManager.cpp:1356-1368):**
```cpp
// TransactionManager.cpp:1356-1368 — GetBlockChainBase builds "/bc-{net}/" prefix
std::string TransactionManager::GetBlockChainBase(uint16_t network_id) {
    boost::format tx_key{std::string(TRANSACTION_BASE_FORMAT)};  // "/bc-%hu/"
    tx_key % network_id;
    return tx_key.str();
}
// Result: "/bc-{net_id}/reg/{child_addr}" for reg/ namespace keys
```

**Analog 5c: `GlobalDB::RegisterElementFilter` signature (globaldb.hpp:162-167):**
```cpp
// globaldb.hpp:162-167 — standard filter registration API
/** Registers a filter callback for elements matching a pattern.
 * @param pattern The pattern to match elements against.
 * @param filter  The callback to invoke for matching elements.
 * @return true if the filter was successfully registered, false otherwise.
 */
bool RegisterElementFilter(const std::string &pattern, GlobalDBFilterCallback filter);
```

**Phase 3 FilterRegistration extension — superseedes_sequence gate:**
```cpp
// Pseudocode for the Phase 3 design doc — insert AFTER existing sequence monotonicity gate:
//
// Gate 3b: Supersedes linkage (LIFE-02)
// Only applies when RegistrationTx.has_supersedes_sequence() && supersedes_sequence != 0
// (0 means "new registration" — no supersedes check needed)
//
// if (new_registration.has_supersedes_sequence() &&
//     new_registration.supersedes_sequence() != 0) {
//     auto current = ReadRegistrationFromCRDT(child_addr);
//     if (!current || current.sequence() != new_registration.supersedes_sequence()) {
//         break;  // REJECT — fork detected: supersedes_sequence must match current record
//     }
// }
//
// Combined with nonce chain (sgns.nonce.v1): first update to reach consensus wins.
// The second competing update fails at this filter because supersedes_sequence
// no longer matches the (now-updated) current record.
```

---

## Shared Patterns

### Signature Verification (cross-cutting)
**Source:** `AccountMessenger.cpp:1478-1499` (HandleNonceRequest), `TransactionManager.cpp:4361-4383` (CheckTransactionAuthorization)
**Apply to:** All handler methods (HandleChildDiscoveryRequest, HandleChildDiscoveryResponse), all tx validation paths (CheckTransactionAuthorization for RevokeTx)

**Pattern:**
```cpp
// AccountMessenger message handlers: verify requester signature over serialized data
std::string serialized;
if (!req.SerializeToString(&serialized)) { return; }
std::vector<uint8_t> serialized_vec(serialized.begin(), serialized.end());
auto verify_sig = methods_.verify_signature_(req.requester_address(),
                                              signed_req.signature(), serialized_vec);
if (verify_sig.has_error() || !verify_sig.value()) {
    logger_->error("Invalid signature on ... from {}", req.requester_address());
    return;
}

// TransactionManager: verify tx signature
bool TransactionManager::CheckTransactionAuthorization(const GeniusTransaction &tx) const {
    return tx.CheckSignature() || tx.CheckDAGSignatureLegacy();
}
```

### Logging Pattern
**Source:** `AccountMessenger.cpp`, `TransactionManager.cpp` — ubiquitous pattern
**Apply to:** All new handler methods
**Pattern:**
```cpp
// logger_->debug / error / trace with [short_addr] prefix
logger_->debug("[{}] Received a Nonce request req_id {}", address_.substr(0, 8), req.request_id());
TransactionManagerLogger()->error("[{} - full: {}] Authorization failed tx={}",
    account_m->GetAddress().substr(0, 8), full_node_m, tx.GetHash());
```

### PubSub Topic Subscription (cross-cutting)
**Source:** `pubsub_broadcaster_ext.hpp:68-75` — AddBroadcastTopic / AddListenTopic
**Apply to:** Discovery push (AddListenTopic on main_address topic), child state sync (AddListenTopic on child_address)
**Pattern:**
```cpp
// pubsub_broadcaster_ext.hpp:68-75
outcome::result<void> AddBroadcastTopic(const std::string &topicName);
void                  AddListenTopic(std::string topic);

// Usage pattern (from Phase 2 D-17):
// main subscribes to child's topics via AddListenTopic(child_address)
// to receive CRDT deltas for balance/UTXO/transaction monitoring
```

### Outcome Error Handling (cross-cutting)
**Source:** Ubiquitous across codebase — `BOOST_OUTCOME_TRY`, `outcome::result<T>`, `outcome::failure()`
**Apply to:** All new methods with fallible operations
**Pattern:**
```cpp
BOOST_OUTCOME_TRY(auto value, someFallibleOperation());
// On error: outcome::failure(boost::system::error_code{}) or named error codes
```

### Proto Serialization Convention (cross-cutting)
**Source:** All `.proto` files — field 1 = identifying struct (DAGStruct for txs, data for signed wrappers)
**Apply to:** `RevokeTx` proto, `ChildDiscovery{Request,Response}` protos
**Pattern:**
```protobuf
// Transaction proto: DAGStruct dag_struct = 1; // always first
// Signed wrapper: <Type> data = 1; bytes signature = 2; // always first/second
// Response message: responder_address = 1; requester_address = 2; request_id = 3; timestamp = ...;
```

---

## No Analog Found

All code touchpoints have strong analogs in the existing codebase. No touchpoint requires a novel pattern.

| Touchpoint | Closest Analog | Match Quality | Notes |
|---|---|---|---|
| (none) | — | — | All 12 touchpoints map to existing patterns |

## Metadata

**Analog search scope:**
- `SuperGenius/src/account/proto/` — SGTransaction.proto, SGAccountComm.proto
- `SuperGenius/src/blockchain/impl/proto/` — Consensus.proto
- `SuperGenius/src/account/` — AccountMessenger.{hpp,cpp}, TransactionManager.{hpp,cpp}, GeniusNode.{hpp,cpp}, EscrowTransaction.{hpp,cpp}, GeniusTransaction.hpp
- `SuperGenius/src/blockchain/` — Consensus.hpp
- `SuperGenius/src/crdt/globaldb/` — globaldb.hpp, pubsub_broadcaster_ext.hpp

**Files scanned:** 22
**Key files read (concrete excerpts extracted):** 14
**Pattern extraction date:** 2026-07-14

## PATTERN MAPPING COMPLETE

**Phase:** 3 - Discovery, Rewards & Lifecycle
**Files classified:** 12
**Analogs found:** 12 / 12

### Coverage
- Files with exact analog: 10
- Files with role-match analog: 2
- Files with no analog: 0

### Key Patterns Identified
- **AccountMessenger request/response:** `HandleNonceRequest`/`HandleNonceResponse` (AccountMessenger.cpp:1472-1614) → exact template for `HandleChildDiscovery{Request,Response}` — signed proto, signature verify, build response, SendAccountMessage on requester's `.comm` topic, collect responses in map keyed by `request_id`
- **Proto additive evolution:** `EscrowTx` fields 4-5 appended after DAGStruct=1 (SGTransaction.proto:120-127); `EmbeddedTransaction` oneof arms 1-7 (Consensus.proto:70-80); `AccountMessage` oneof arms 1-9 (SGAccountComm.proto:5-17) — new fields/arms appended at next available number, never renumber
- **CRDT filter `do{}while(0)` pattern:** `FilterTransaction` (TransactionManager.cpp:2984-3039) — deserialize→signature→collision→accept, with `should_delete=true` default and `break` on rejection, tombstone vector on failure
- **Consensus gate pipeline:** `ValidateTransactionForConsensus` (TransactionManager.cpp:4234-4304) — 5 sequential gates: well-formed → authorization → timestamp → replay-protection → type-rules, each returns `Reject()` on failure
- **Escrow hold-time pinning:** `EscrowTransaction` constructor (EscrowTransaction.hpp:122-131) stores `dev_addr_`/`peers_cut_` immutably; `PayEscrow` reads stored values (TransactionManager.cpp:848,875), NOT live CRDT — zero Phase 3 changes needed

### File Created
`.planning/phases/03-discovery-rewards-lifecycle/03-PATTERNS.md`

### Ready for Planning
Pattern mapping complete. Planner can now reference analog patterns with exact file:line anchors in PLAN.md files.
