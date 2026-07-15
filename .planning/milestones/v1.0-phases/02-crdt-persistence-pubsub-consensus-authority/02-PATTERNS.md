# Phase 02: CRDT Persistence, PubSub & Consensus Authority - Pattern Map

**Mapped:** 2026-07-13
**Files analyzed:** 10 (2 design docs + 8 code anchor points)
**Analogs found:** 10 / 10

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `docs/02-crdt-registry-pubsub.md` (Design Doc 1) | design-document | CRDT-persistence + event-driven-pubsub | `TransactionManager.cpp::FilterTransaction` + `FilterProof` + CRDT filter registration block | exact |
| `docs/02-consensus-parent-child-authority.md` (Design Doc 2) | design-document | consensus-validation + state-dependent-authorization | `TransactionManager.cpp::ValidateTransactionForConsensus` + `CheckTransactionAuthorization` | exact |
| `TransactionManager.hpp` (code mods referenced by docs) | controller/orchestrator | CRUD + consensus-pipeline | `TransactionManager.hpp:691-692` (existing gate declarations) | exact |
| `TransactionManager.cpp` (code mods referenced by docs) | controller/orchestrator | CRUD + consensus-pipeline | `TransactionManager.cpp` (all existing patterns) | exact |
| `GeniusInputValidator.cpp` (unchanged, documented) | validator | UTXO-ownership | `GeniusInputValidator.cpp:419-432` (ValidateWitness escrow exception) | exact |

## Pattern Assignments

---

### Design Doc 1 (§1): `FilterRegistration` — CRDT Element Filter for `reg/` Namespace

**Analog:** `TransactionManager::FilterTransaction` (TransactionManager.cpp:2984-3039)
**Analog:** `TransactionManager::FilterProof` (TransactionManager.cpp:3041-3079)

#### CRDT filter registration pattern (lines 187-213):

```cpp
// Source: TransactionManager.cpp::New(), lines 187-213
// Existing tx/ filter registration:
bool crdt_tx_filter_initialized = instance->globaldb_m->RegisterElementFilter(
    "^/?" + blockchain_base + "tx/[^/]+",
    [weak_ptr( std::weak_ptr<TransactionManager>( instance ) )](
        const crdt::pb::Element &element ) -> std::optional<std::vector<crdt::pb::Element>>
    {
        if ( auto strong = weak_ptr.lock() )
        {
            return strong->FilterTransaction( element );
        }
        return std::nullopt;
    } );

// Existing proof/ filter registration (same pattern, line 203-213):
bool crdt_proof_filter_initialized = instance->globaldb_m->RegisterElementFilter(
    "^/?" + blockchain_base + "proof/[^/]+",
    [weak_ptr( std::weak_ptr<TransactionManager>( instance ) )](
        const crdt::pb::Element &element ) -> std::optional<std::vector<crdt::pb::Element>>
    {
        if ( auto strong = weak_ptr.lock() )
        {
            return strong->FilterProof( element );
        }
        return std::nullopt;
    } );
```

**New reg/ filter (appended after proof/ filter in the same `for` loop):**
```cpp
// Pattern to follow — reg/ filter appended at line ~215:
bool crdt_reg_filter_initialized = instance->globaldb_m->RegisterElementFilter(
    "^/?" + blockchain_base + "reg/([^/]+)",
    [weak_ptr( std::weak_ptr<TransactionManager>( instance ) )](
        const crdt::pb::Element &element ) -> std::optional<std::vector<crdt::pb::Element>>
    {
        if ( auto strong = weak_ptr.lock() )
        {
            return strong->FilterRegistration( element );
        }
        return std::nullopt;
    } );
```

**CRITICAL:** The capture group `([^/]+)` in the regex must match the key so the child address can be extracted. The existing `tx/[^/]+` and `proof/[^/]+` patterns use Kleene star; `reg/` uses a capture group for post-filter key extraction per D-12/D-14.

#### FilterTransaction body pattern (lines 2984-3039):

```cpp
// Source: TransactionManager.cpp:2984-3039
// Template for FilterRegistration — structural pattern:
std::optional<std::vector<crdt::pb::Element>> TransactionManager::FilterTransaction(
    const crdt::pb::Element &element )
{
    std::optional<std::vector<crdt::pb::Element>> maybe_tombstones;
    bool                                          should_delete = true;
    std::shared_ptr<GeniusTransaction>            new_tx;
    do
    {
        auto maybe_new_tx = DeSerializeTransaction( element.value() );
        if ( maybe_new_tx.has_error() )
        {
            TransactionManagerLogger()->error( "[{} - full: {}] Failed to deserialize incoming transaction {}",
                                               account_m->GetAddress().substr( 0, 8 ),
                                               full_node_m,
                                               element.key() );
            break;  // (a) deserialization failure → reject
        }
        new_tx = maybe_new_tx.value();

        if ( !CheckTransactionAuthorization( *new_tx ) )
        {
            TransactionManagerLogger()->error( "[{} - full: {}] Could not validate signature of transaction {}",
                                               account_m->GetAddress().substr( 0, 8 ),
                                               full_node_m,
                                               element.key() );
            break;  // (b) invalid signature → reject
        }
        if ( KeyExistsInDB( GetTransactionPath( *new_tx ) ) )
        {
            TransactionManagerLogger()->debug(
                "[{} - full: {}] New transaction {} would overwrite an existing one. Preventing that",
                account_m->GetAddress().substr( 0, 8 ),
                full_node_m,
                new_tx->GetHash() );
            break;  // (c) key collision → reject
        }
        should_delete = false;

    } while ( 0 );

    if ( should_delete )
    {
        // Cascade-delete paired proof key (tx/ → proof/)
        std::vector<crdt::pb::Element> additional_elements_to_delete;
        auto maybe_proof_key = GetExpectedProofKey( element.key(), new_tx );
        if ( maybe_proof_key.has_value() )
        {
            crdt::pb::Element proof_element;
            proof_element.set_key( maybe_proof_key.value() );
            additional_elements_to_delete.push_back( proof_element );
        }
        maybe_tombstones = additional_elements_to_delete;  // tombstone(s) → REJECT
    }

    return maybe_tombstones;  // std::nullopt → ACCEPT
}
```

#### FilterRegistration differences from FilterTransaction:

| Aspect | FilterTransaction | FilterRegistration |
|--------|-------------------|-------------------|
| Deserialization | `DeSerializeTransaction` (generic dispatch) | `DeSerializeTransaction` or RegistrationTx-specific path |
| Signature check | `CheckTransactionAuthorization( *new_tx )` | `tx.CheckSignature()` **OR** `CheckTransactionAuthorization( *new_tx )` if RegistrationTx inherits the existing path |
| Key collision check | `KeyExistsInDB( GetTransactionPath( *new_tx ) )` — rejects if key exists | Read current `reg/{child_addr}`, check `new_tx.sequence > current.sequence` (D-13). First registration: accept. Lower/equal sequence: reject. |
| Cascade-delete | Deletes paired `proof/` key | **None** — `reg/` has no paired namespace (D-13). Return `{{element}}` for tombstone rejection only. |
| Well-formed check | Implicit via `transaction_parsers` lookup | Explicit: `main_address` is valid public key, `sequence > 0` (D-13) |
| Return semantics | `std::nullopt` = accept, non-empty vector = tombstone-delete | Same (`std::nullopt` = accept, `{{element}}` = reject) |

#### FilterProof body pattern (lines 3041-3079) — reference for no-paired-namespace filter:

```cpp
// Source: TransactionManager.cpp:3041-3079
// FilterProof: standalone filter with no paired namespace deletion (parallel to reg/):
std::optional<std::vector<crdt::pb::Element>> TransactionManager::FilterProof(
    const crdt::pb::Element &element )
{
    std::optional<std::vector<crdt::pb::Element>> maybe_tombstones;
    bool                                          valid_proof = false;
    do
    {
        valid_proof = true;
        break;
        // ... actual proof verification (currently short-circuited) ...
    } while ( 0 );

    if ( !valid_proof )
    {
        std::vector<crdt::pb::Element> tombstones;
        tombstones.push_back( element );  // tombstone self-only (no paired key)
        auto maybe_tx_key = GetExpectedTxKey( element.key() );
        if ( maybe_tx_key.has_value() )
        {
            crdt::pb::Element tx_tombstone;
            tx_tombstone.set_key( maybe_tx_key.value() );
            tombstones.push_back( tx_tombstone );
        }
        maybe_tombstones = tombstones;
    }
    return maybe_tombstones;
}
```

**Key insight for Design Doc 1:** `FilterRegistration` borrows `FilterTransaction`'s `do { ... } while(0)` + `should_delete` pattern for the rejection path, and `FilterProof`'s "self-tombstone-only, no paired-key cascade" when rejecting. The sequence-monotonicity check is a new validation step unique to `FilterRegistration`.

---

### Design Doc 1 (§2): CRDT Key Construction for `reg/{child_addr}`

**Analog:** `TransactionManager::GetBlockChainBase` + `GetTransactionPath` (TransactionManager.cpp:1356-1368, 1323-1340)

#### Key base (lines 1356-1368):

```cpp
// Source: TransactionManager.cpp:1356-1368
static constexpr std::string_view TRANSACTION_BASE_FORMAT = "/bc-%hu/";  // line 296 in .hpp

std::string TransactionManager::GetBlockChainBase( uint16_t network_id )
{
    boost::format tx_key{ std::string( TRANSACTION_BASE_FORMAT ) };
    tx_key % network_id;
    return tx_key.str();
    // Result: "/bc-963/" (TestNet), "/bc-369/" (MainNet), etc.
}

std::string TransactionManager::GetBlockChainBase()
{
    return GetBlockChainBase( version::GetNetworkID() );
}
```

#### Transaction path construction (lines 1323-1340):

```cpp
// Source: TransactionManager.cpp:1323-1340
// tx/ key construction:
std::string TransactionManager::GetTransactionPath( uint16_t base, const std::string &tx_hash )
{
    return GetBlockChainBase( base ) + GeniusTransaction::GetTransactionFullPath( tx_hash );
    // Result: "/bc-963/tx/<tx_hash>"
}

std::string TransactionManager::GetTransactionPath( const GeniusTransaction &element )
{
    return GetBlockChainBase() + element.GetTransactionFullPath();
    // Result: "/bc-963/tx/<tx_hash>"
}
```

**Registration key construction pattern (reg/):**
```cpp
// Design Doc 1 specifies:
// Key = GetBlockChainBase(network_id) + "reg/" + child_addr
// Result: "/bc-963/reg/<child_addr_hex>"

// Analogous utility method pattern:
static std::string GetRegistrationPath( const std::string &child_addr )
{
    return GetBlockChainBase() + "reg/" + child_addr;
}
```

#### HierarchicalKey usage (hierarchical_key.hpp):

```cpp
// Source: hierarchical_key.hpp
// CRDT keys use HierarchicalKey for namespace-aware storage:
crdt::HierarchicalKey tx_key( GetBlockChainBase() + "tx/" + tx_hash );
crdt::HierarchicalKey reg_key( GetBlockChainBase() + "reg/" + child_addr );

// Key namespace convention: /bc-{net}/{type}/{identifier}
//   tx/   → /bc-963/tx/<tx_hash>
//   proof/ → /bc-963/proof/<tx_hash>
//   reg/  → /bc-963/reg/<child_addr>
```

---

### Design Doc 1 (§3): PubSub Broadcast & Subscription (SYNC-03..05)

**Analog:** `GlobalDB::AddBroadcastTopic` / `AddListenTopic` (globaldb.hpp:152-154)
**Analog:** `PubSubBroadcasterExt` API (pubsub_broadcaster_ext.hpp)

#### GlobalDB topic API (globaldb.hpp:152-154):

```cpp
// Source: globaldb.hpp:152-154
outcome::result<void> AddBroadcastTopic( const std::string &topicName );
void                  AddTopicName( const std::string &topicName );
void                  AddListenTopic( const std::string &topicName );
```

#### PubSubBroadcasterExt API (pubsub_broadcaster_ext.hpp:68-74):

```cpp
// Source: pubsub_broadcaster_ext.hpp:68-74
/**
 * @brief Adds a new topic by name
 * @param topicName Name of the topic to add.
 * @return outcome::success() on success (or if topic already existed), outcome::failure() on error.
 */
outcome::result<void> AddBroadcastTopic( const std::string &topicName );

/**
 * @brief  Subscribe to a given topic and store its future.
 * @param  topic  Name of the topic to listen to.
 */
void AddListenTopic( std::string topic );
```

#### Existing usage pattern — StartListeningTopics in TransactionManager:

```cpp
// Source: TransactionManager pattern (referenced in research, lines ~350-360)
// The TransactionManager already listens on its own address:
globaldb_m->AddListenTopic( account_m->GetAddress() );
globaldb_m->AddTopicName( account_m->GetAddress() );

// For RegistrationTx:
// Child calls (SYNC-03):
globaldb_m->AddBroadcastTopic( main_address );  // publish CID on main's topic

// Main calls upon pubsub notification (SYNC-04):
globaldb_m->AddListenTopic( child_address );     // subscribe to child's CRDT deltas
```

#### PubSubBroadcasterExt::Broadcast (pubsub_broadcaster_ext.hpp:48):

```cpp
// Source: pubsub_broadcaster_ext.hpp:48
outcome::result<void> Broadcast( const base::Buffer &buff, std::string topic,
    boost::optional<libp2p::peer::PeerInfo> peerInfo = boost::none ) override;
```

---

### Design Doc 1 (§4): CRDT Write → SubmitProposal Flow for RegistrationTx

**Analog:** `TransactionManager::SendTransactionItem` (TransactionManager.cpp:1127-1311)

#### CRDT write pattern (lines 1200-1210):

```cpp
// Source: TransactionManager.cpp:1200-1210
auto                   transaction_path = GetTransactionPath( *transaction );
crdt::HierarchicalKey  tx_key( transaction_path );
crdt::GlobalDB::Buffer data_transaction;

data_transaction.put( transaction->SerializeByteVector() );
BOOST_OUTCOME_TRY( crdt_transaction->Put( std::move( tx_key ), std::move( data_transaction ) ) );
```

#### Topic collection pattern (lines 1163-1166):

```cpp
// Source: TransactionManager.cpp:1163-1166
std::unordered_set<std::string> topicSet;
topicSet.emplace( full_node_topic_m );
topicSet.emplace( account_m->GetAddress() );
```

#### Consensus proposal submission pattern (lines 1299-1307):

```cpp
// Source: TransactionManager.cpp:1299-1307
BOOST_OUTCOME_TRY( auto &&proposal,
    blockchain_->CreateConsensusProposal( transaction->GetSrcAddress(),
                                          transaction->GetNonce(),
                                          transaction->GetHash(),
                                          embedded_tx,
                                          utxo_commitment,   // std::nullopt for RegistrationTx
                                          utxo_witness ) );  // std::nullopt for RegistrationTx
BOOST_OUTCOME_TRY( ChangeTransactionState( transaction, TransactionStatus::SENDING ) );
BOOST_OUTCOME_TRY( blockchain_->SubmitProposal( proposal ) );
```

**RegistrationTx flow differences from TransferTx:**
- RegistrationTx key is `GetBlockChainBase() + "reg/" + child_addr` (NOT `tx/` path)
- Topics include `full_node_topic_m` + `account_m->GetAddress()` + `main_address` (pubsub notification destination)
- `utxo_commitment` and `utxo_witness` are always `std::nullopt` (RegistrationTx has no UTXOs)
- The `crdt_transaction->Commit(topicSet)` call publishes the CRDT delta on all topics

---

### Design Doc 1 (§5): Certified Status Flag Pattern (D-26)

**Analog:** `TransactionManager::OnConsensusCertificate` (lines 3655-3852) + `ChangeTransactionState` (lines 5110-5184)

#### OnConsensusCertificate pattern (line 3655):

```cpp
// Source: TransactionManager.cpp:3655-3752
outcome::result<ConsensusManager::Check> TransactionManager::OnConsensusCertificate(
    const std::string          &tx_hash,
    const ConsensusCertificate &certificate )
{
    auto tx = GetTransactionByHash( tx_hash );
    if ( !tx )
    {
        // CONFLICT-01 / NONCE-01: Standalone validator without local transaction state.
        // Deserialize from the certificate's embedded proposal.
        auto nonce_subject_result = ConsensusManager::DecodeNonceSubject(
            certificate.proposal().subject() );
        // ... fallback deserialization from certificate ...
        auto result = ChangeTransactionState( tx, TransactionStatus::CONFIRMED );
        // ...
    }
    else
    {
        // TRACK-01: Confirm via ChangeTransactionState lifecycle
        auto result = ChangeTransactionState( tx, TransactionStatus::CONFIRMED );
        // ...
    }
    // Returns ConsensusManager::Check::Approve (consensus passes)
}
```

#### ChangeTransactionState CONFIRMED pattern (lines 5150+):

```cpp
// Source: TransactionManager.cpp:5110-5184
// The CONFIRMED state transition is the canonical "certification" marker.
// OnConsensusCertificate calls ChangeTransactionState(tx, CONFIRMED).
// This updates tx_processed_m with status=CONFIRMED.

// For RegistrationTx (D-26):
// Option A: separate CRDT key — "/bc-963/reg-cert/{child_addr}" = certificate CID
// Option B: in-band field — add "certified" field to RegistrationTx proto, re-write on certificate
// Option C (existing pattern): in-memory map — tx_processed_m keyed by registration path,
//   populated by OnConsensusCertificate when the nonce subject carrying the RegistrationTx
//   receives a certificate. This is the simplest match to the existing CONFIRMED pattern.
```

---

### Design Doc 2 (§1): `CheckParentChildAuthority` — New Consensus Gate

**Analog:** `TransactionManager::CheckTransactionAuthorization` (TransactionManager.cpp:4361-4383)
**Analog:** `TransactionManager::ValidateTransactionForConsensus` pipeline (lines 4234-4303)

#### CheckTransactionAuthorization — the "gate template" (lines 4361-4383):

```cpp
// Source: TransactionManager.cpp:4361-4383
bool TransactionManager::CheckTransactionAuthorization( const GeniusTransaction &tx ) const
{
    TransactionManagerLogger()->debug( "[{} - full: {}] {}: Checking authorization tx={}",
                                       account_m->GetAddress().substr( 0, 8 ),
                                       full_node_m,
                                       __func__,
                                       tx.GetHash() );
    if ( tx.CheckSignature() || tx.CheckDAGSignatureLegacy() )
    {
        TransactionManagerLogger()->debug( "[{} - full: {}] {}: Authorization ok tx={}",
                                           account_m->GetAddress().substr( 0, 8 ),
                                           full_node_m,
                                           __func__,
                                           tx.GetHash() );
        return true;
    }
    TransactionManagerLogger()->error( "[{} - full: {}] {}: Authorization failed tx={}",
                                       account_m->GetAddress().substr( 0, 8 ),
                                       full_node_m,
                                       __func__,
                                       tx.GetHash() );
    return false;
}
```

**CheckParentChildAuthority declaration pattern** (from CheckTransactionAuthorization in .hpp:691):
```cpp
// Source: TransactionManager.hpp:691
bool CheckTransactionAuthorization( const GeniusTransaction &tx ) const;

// New declaration (add after line 691, before CheckTransactionTimestamp at line 692):
ConsensusManager::ValidationResult CheckParentChildAuthority(
    const GeniusTransaction &tx ) const;
```

#### ValidateTransactionForConsensus — gate insertion point (lines 4234-4303):

```cpp
// Source: TransactionManager.cpp:4234-4303
ConsensusManager::ValidationResult TransactionManager::ValidateTransactionForConsensus(
    const std::shared_ptr<GeniusTransaction> &tx ) const
{
    if ( !tx ) return ConsensusManager::ValidationResult::Reject();

    if ( !CheckTransactionWellFormed( *tx ) )      // Gate 1
        return ConsensusManager::ValidationResult::Reject();
    if ( !CheckTransactionAuthorization( *tx ) )    // Gate 2: signature only
        return ConsensusManager::ValidationResult::Reject();
    // ★★★ INSERT CheckParentChildAuthority HERE (D-19) ★★★
    // Gate 2.5: parent-child authority (between authorization and timestamp)
    if ( !CheckTransactionTimestamp( *tx ) )        // Gate 3
        return ConsensusManager::ValidationResult::Reject();
    auto replay_result = EvaluateTransactionReplayProtection( *tx ); // Gate 4
    if ( replay_result.validation.check != ConsensusManager::Check::Approve )
        return replay_result.validation;
    if ( !CheckTransactionTypeRules( tx ) )         // Gate 5
        return ConsensusManager::ValidationResult::Reject();

    return ConsensusManager::ValidationResult::Approve();
}
```

**CheckParentChildAuthority return type** — uses `ConsensusManager::ValidationResult` not `bool` to support `Pending` state for CRDT dependency resolution:

```cpp
// Source: Consensus.hpp:145-180
struct ValidationResult
{
    Check check{ Check::Reject };

    static ValidationResult Approve() { return ValidationResult{ Check::Approve }; }
    static ValidationResult Reject()  { return ValidationResult{ Check::Reject }; }
    static ValidationResult Pending( std::vector<PendingDependencyKey> deps = {},
        std::optional<std::chrono::milliseconds> retry = std::nullopt );
};
```

---

### Design Doc 2 (§2): `CheckParentChildAuthority` — Six Rules Reference Implementation

#### Auxiliary: Fetch CRDT `reg/{child_addr}` record:

```cpp
// Pattern: Fetch from CRDT using GlobalDB::Get
// Source: globaldb.hpp:115
outcome::result<Buffer> Get( const HierarchicalKey &key );

// Usage in CheckParentChildAuthority:
auto reg_result = globaldb_m->Get( HierarchicalKey( reg_key ) );
if ( reg_result.has_error() ) { /* no registration → no parent-child authority */ }
```

#### Auxiliary: Certified status check (D-26):

```cpp
// Pattern: Check tx_processed_m for CONFIRMED status
// Source: OnConsensusCertificate + ChangeTransactionState → CONFIRMED
// The gate must verify the registration is certified before acting.
// Uncached lookup: query CRDT for cert marker, or check if certificate exists.
```

#### Auxiliary: Classify signer — who signed the transaction?

```cpp
// Pattern: CheckTransactionAuthorization already verifies signature.
// But we need to identify WHO signed (main or child) for rule dispatch.
// CheckSignature() returns true if signature matches source_addr.
// The tx source_addr tells us who signed; the reg/ record tells us the relationship.
//
// If tx.GetSrcAddress() == registered_main → main signed.
// If tx.GetSrcAddress() == child_addr (found in reg/ record) → child signed.
```

---

### Design Doc 2 (§3): CONS-05 Invariant — Child-Cannot-Spend-Main

**Analog:** `GeniusInputValidator::ValidateWitness` (GeniusInputValidator.cpp:419-432)

```cpp
// Source: GeniusInputValidator.cpp:419-432
// This is where CONS-05 (child-cannot-spend-main) is already enforced today.
// The design doc documents this as an invariant — NO NEW CODE needed.
const std::string payload_owner( payload.data() + OWNER_ADDRESS_OFFSET,
                                 payload.data() + OWNER_ADDRESS_OFFSET + owner_len );

// The ONLY place where payload_owner != tx->GetSrcAddress() is allowed:
const bool delegated_escrow_spend =
    payload_owner != tx->GetSrcAddress() &&
    tx->GetType() == TRANSFER_TX_TYPE &&
    input.output_idx_ == ESCROW_LOCK_OUTPUT_INDEX &&
    utxo_address::IsEscrowLockAddress( payload_owner ) &&
    tx->GetUncleHash() == payload_owner;

// This is where CONS-05 is enforced today:
if ( payload_owner != tx->GetSrcAddress() && !delegated_escrow_spend )
{
    logger->debug( "ValidateWitness(Genius) owner mismatch for tx={} owner={} src={}",
                   PreviewValue( tx->GetHash() ),
                   PreviewValue( payload_owner ),
                   PreviewValue( tx->GetSrcAddress() ) );
    return false;  // REJECT: child can't spend main's UTXOs
}
```

**Key insight:** `ValidateWitness` already enforces `payload_owner == src_address` (with escrow exception at line 421-424). A child key does NOT own main UTXOs, so any child-signed transfer attempting to spend a main UTXO fails this check. The design doc adds a **negative test spec** verifying this property; no code change to this file.

---

### Design Doc 2 (§4): `CheckTransactionTypeRules` — RegistrationTx Field Validation

**Analog:** `TransactionManager::CheckTransactionTypeRules` (lines 4558-4593)
**Analog:** `TransactionManager::CheckTransactionWellFormed` (lines 4306-4358)

#### CheckTransactionTypeRules pattern (lines 4558-4593):

```cpp
// Source: TransactionManager.cpp:4558-4593
bool TransactionManager::CheckTransactionTypeRules(
    const std::shared_ptr<GeniusTransaction> &tx ) const
{
    if ( !tx )
    {
        TransactionManagerLogger()->error( "[{} - full: {}] {}: Null transaction",
                                           account_m->GetAddress().substr( 0, 8 ),
                                           full_node_m, __func__ );
        return false;
    }

    if ( tx->HasUTXOParameters() )
    {
        auto params_opt = tx->GetUTXOParametersOpt();
        if ( !params_opt.has_value() )
        {
            TransactionManagerLogger()->error(
                "[{} - full: {}] {}: Missing UTXO parameters for tx={}",
                account_m->GetAddress().substr( 0, 8 ), full_node_m, __func__,
                tx->GetHash() );
            return false;
        }
        const auto  chain_id  = GetValidationChainId( tx );
        const auto &validator = GetInputValidator( chain_id );
        return validator.ValidateUTXOParameters( params_opt.value(),
                                                  tx->GetSrcAddress(),
                                                  account_m->GetUTXOManager() );
    }

    return true;  // Non-UTXO txs (like RegistrationTx) pass by default
}
```

#### CheckTransactionWellFormed — type registration check (lines 4306-4358):

```cpp
// Source: TransactionManager.cpp:4306-4358
bool TransactionManager::CheckTransactionWellFormed( const GeniusTransaction &tx ) const
{
    if ( tx.GetHash().empty() || !tx.CheckHash() ) return false;
    if ( tx.GetSrcAddress().empty() ) return false;
    if ( tx.GetTimestamp() == 0 ) return false;

    // Type must be registered in transaction_parsers:
    if ( transaction_parsers.find( tx.GetType() ) == transaction_parsers.end() )
    {
        TransactionManagerLogger()->error( "[{} - full: {}] {}: Unknown tx type {}",
                                           account_m->GetAddress().substr( 0, 8 ),
                                           full_node_m, __func__, tx.GetType() );
        return false;
    }
    return true;
}
```

**For RegistrationTx (Design Doc 2):**
- `CheckTransactionWellFormed` already rejects unknown tx types — `"registration"` must be in `transaction_parsers` (Phase 1 hand-off, added alongside Phase 1 deserializer registration)
- `CheckTransactionTypeRules` currently passes ALL non-UTXO txs by default (line 4592: `return true`). The design doc should recommend adding a RegistrationTx case: validate `main_address` is a valid public key (128-hex) and `sequence > 0` for defense-in-depth.

---

### Design Doc 2 (§5): Consensus Subject Handler — RegistrationTx Reuses `sgns.nonce.v1`

**Analog:** Subject handler registration in TransactionManager::New() (lines 149-168)

```cpp
// Source: TransactionManager.cpp:149-168
// RegistrationTx reuses the SAME sgns.nonce.v1 handler (D-24):
instance->blockchain_->RegisterSubjectHandler(
    NONCE_SUBJECT_TYPE,  // "sgns.nonce.v1" — line 37 of Consensus.hpp
    [weak_ptr( std::weak_ptr<TransactionManager>( instance ) )](
        const ConsensusManager::Subject &subject )
        -> outcome::result<ConsensusManager::ValidationResult>
    {
        if ( auto strong = weak_ptr.lock() )
        {
            return strong->HandleNonceConsensusSubject( subject );
        }
        return outcome::failure( std::errc::owner_dead );
    } );

instance->blockchain_->RegisterCertificateHandler(
    NONCE_SUBJECT_TYPE,
    [weak_ptr( std::weak_ptr<TransactionManager>( instance ) )](
        const std::string          &subject_hash,
        const ConsensusCertificate &certificate )
        -> outcome::result<ConsensusManager::Check>
    {
        if ( auto strong = weak_ptr.lock() )
        {
            auto process_result = strong->OnConsensusCertificate( subject_hash, certificate );
            // ... error logging ...
            return process_result;
        }
        return outcome::failure( std::errc::owner_dead );
    } );

instance->blockchain_->RegisterProposalCleanupHandler(
    NONCE_SUBJECT_TYPE,
    [weak_ptr(...)]( const std::string &tx_hash ) { /* OnProposalTimeoutCleanup */ } );

instance->blockchain_->RegisterSlotKeyHandler(
    NONCE_SUBJECT_TYPE,
    []( const ConsensusManager::Subject &subject ) -> std::string
    {
        auto nonce = ConsensusManager::DecodeNonceSubject( subject );
        if ( nonce.has_value() && nonce.value().transaction().transaction_case()
            != EmbeddedTransaction::TRANSACTION_NOT_SET )
        {
            auto tx = TransactionManager::DeSerializeEmbeddedTransaction( nonce.value().transaction() );
            if ( tx.has_value() ) { return tx.value()->GetSlotID(); }
        }
        return subject.account_id() + ":" + std::to_string(
            nonce.has_value() ? nonce.value().nonce() : 0ULL );
    } );
```

**RegistrationTx flow through HandleNonceConsensusSubject** (line 3901):
- Deserialize from `EmbeddedTransaction` oneof → RegistrationTx
- Hash binding check: `tx->GetHash() == subject.tx_hash`
- Nonce match: `tracked_nonce == subject.nonce`
- Account match: `tx->GetSrcAddress() == subject.account_id`
- Then: `ValidateTransactionForConsensus( tx )` → which now includes `CheckParentChildAuthority`

---

## Shared Patterns

### CRDT Element Filter Callback Type

**Source:** `CRDTDataFilter::ElementFilterCallback` (crdt_data_filter.hpp:30)

```cpp
// Source: crdt_data_filter.hpp:30
using ElementFilterCallback =
    std::function<std::optional<std::vector<pb::Element>>( const pb::Element & )>;
// std::nullopt = ACCEPT, non-empty vector = tombstone-delete
```

### GlobalDB::RegisterElementFilter Registration

**Source:** `globaldb.hpp:167`

```cpp
// Source: globaldb.hpp:167
bool RegisterElementFilter( const std::string &pattern, GlobalDBFilterCallback filter );
// GlobalDBFilterCallback = CrdtDatastore::CRDTElementFilterCallback
//   = CRDTDataFilter::ElementFilterCallback
```

### Consensus Nonce Subject Type

**Source:** `Consensus.hpp:37`

```cpp
// Source: Consensus.hpp:37
static constexpr std::string_view NONCE_SUBJECT_TYPE = "sgns.nonce.v1";
```

### Consensus Subject Handler Signature

**Source:** `Consensus.hpp:199, 227`

```cpp
// Source: Consensus.hpp:199, 227
using SubjectHandler = std::function<outcome::result<ValidationResult>( const Subject &subject )>;
bool RegisterSubjectHandler( std::string_view subject_type, SubjectHandler handler );
```

### Consensus Certificate Handler Signature

**Source:** `Consensus.hpp:239`

```cpp
using CertificateSubjectHandler =
    std::function<outcome::result<Check>( const std::string &subject_hash,
                                          const Certificate &certificate )>;
bool RegisterCertificateHandler( std::string_view subject_type, CertificateSubjectHandler handler );
```

### Consensus CreateConsensusProposal

**Source:** `Consensus.hpp:410-416`

```cpp
static outcome::result<Subject> CreateNonceSubject(
    const std::string                             &account_id,
    uint64_t                                       nonce,
    const std::string                             &tx_hash,
    const EmbeddedTransaction                     &transaction,
    const std::optional<UTXOTransitionCommitment> &utxo_commitment,  // nullopt for RegistrationTx
    const std::optional<UTXOWitness>              &utxo_witness );   // nullopt for RegistrationTx
```

### Logging Pattern

**All methods** follow this exact log format:

```cpp
TransactionManagerLogger()->debug( "[{} - full: {}] {}: message tx={}",
    account_m->GetAddress().substr( 0, 8 ), full_node_m, __func__, tx.GetHash() );

TransactionManagerLogger()->error( "[{} - full: {}] {}: error message tx={}",
    account_m->GetAddress().substr( 0, 8 ), full_node_m, __func__, tx.GetHash() );
```

Logger is obtained via: `base::createLogger( "TransactionManager" )` (line 87).

### Error Handling — BOOST_OUTCOME_TRY Macro

**Source:** TransactionManager.cpp:1210+
```cpp
BOOST_OUTCOME_TRY( crdt_transaction->Put( /* ... */ ) );
BOOST_OUTCOME_TRY( auto &&proposal, blockchain_->CreateConsensusProposal( /* ... */ ) );
BOOST_OUTCOME_TRY( blockchain_->SubmitProposal( proposal ) );
```
All fallible operations use `outcome::result<T>` with `BOOST_OUTCOME_TRY` for propagation.

### Transaction Status State Machine

**Source:** `TransactionManager.hpp:71-80`

```cpp
enum class TransactionStatus : uint8_t
{
    CREATED,     // Transaction created but not yet sent
    SENDING,     // Transaction is being sent
    CONFIRMED,   // Transaction confirmed (consensus certificate received)
    VERIFYING,   // Transaction being verified
    UNCONFIRMED, // Local outgoing transaction expired inconclusively
    FAILED,      // Transaction failed
    INVALID      // Invalid transaction
};
```

**State transitions relevant to RegistrationTx:**
- `CREATED` → `SENDING` → `VERIFYING` → `CONFIRMED` (normal path)
- `CREATED` → `FAILED` (pre-consensus rejection by FilterRegistration or signature check)
- `VERIFYING` → `CONFIRMED` (OnConsensusCertificate callback)
- `VERIFYING` → `FAILED` (consensus rejection)
- `VERIFYING` → `UNCONFIRMED` (proposal timeout)

**CRITICAL:** `CONFIRMED` status in `tx_processed_m` IS the certified-status flag for all transaction types including RegistrationTx (D-26). The `OnConsensusCertificate` callback transitions to `CONFIRMED`. `CheckParentChildAuthority` must verify `CONFIRMED` before acting on `reg/` records.

---

## No Analog Found

No files lacking analogs. Every design-document section maps to an existing concrete code pattern audited in the current codebase.

---

## Metadata

**Analog search scope:** `SuperGenius/src/account/`, `SuperGenius/src/crdt/`, `SuperGenius/src/blockchain/`
**Files scanned:** TransactionManager.{hpp,cpp}, GeniusInputValidator.{hpp,cpp}, GeniusTransaction.hpp, globaldb.hpp, pubsub_broadcaster_ext.hpp, crdt_datastore.hpp, crdt_data_filter.hpp, hierarchical_key.hpp, Consensus.hpp
**Pattern extraction date:** 2026-07-13
