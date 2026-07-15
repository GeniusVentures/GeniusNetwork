# Phase 04: Registration Proto & Transaction - Pattern Map

**Mapped:** 2026-07-15
**Files analyzed:** 11 (new + modified)
**Analogs found:** 11 / 11

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `SuperGenius/src/account/proto/SGTransaction.proto` | model (proto) | serialization | `TransferTx` / `EscrowTx` / `MintTxV2` messages (same file) | exact |
| `SuperGenius/src/blockchain/impl/proto/Consensus.proto` | model (proto) | serialization | `transfer = 1` through `escrow_release = 7` (same file) | exact |
| `SuperGenius/src/account/RegistrationTransaction.hpp` | model (tx subclass) | request-response | `TransferTransaction.hpp` | exact |
| `SuperGenius/src/account/RegistrationTransaction.cpp` | model (tx subclass) | request-response | `TransferTransaction.cpp` | exact |
| `SuperGenius/src/account/TransactionManager.hpp` | service (manager) | CRUD + event-driven | existing `TransferFunds`/`MintFunds` signatures + `FilterTransaction` signature | exact |
| `SuperGenius/src/account/TransactionManager.cpp` | service (manager) | CRUD + event-driven | `DeSerializeEmbeddedTransaction` switch, `SendTransactionItem`, `FilterTransaction`, `New()` filter registration | exact |
| `SuperGenius/src/account/GeniusNode.hpp` | controller (facade) | request-response | `TransferFunds`/`MintTokens` declarations | exact |
| `SuperGenius/src/account/GeniusNode.cpp` | controller (facade) | request-response | `TransferFunds`/`MintTokens` thin-wrapper impls | exact |
| `SuperGenius/src/account/CMakeLists.txt` | config (build) | N/A | existing `GENIUS_NODE_SOURCES` variable | exact |
| `SuperGenius/test/src/account/registration_transaction_test.cpp` | test | request-response | `account_signature_test.cpp` (structure) + `transaction_manager_pending_lifecycle_test.cpp` (linking) | role-match |
| `SuperGenius/test/src/account/CMakeLists.txt` | config (build) | N/A | existing `addtest(...)` + `target_link_libraries(... genius_node_test)` blocks | exact |

## Pattern Assignments

### 1. `SuperGenius/src/account/proto/SGTransaction.proto` (append)

**Analog:** `TransferTx` + `EscrowTx` patterns (lines 81-127 in same file)

**Additive-only field numbering pattern** — every tx message embeds `DAGStruct dag_struct = 1` as the first field, then declares type-specific fields at 2+:

```protobuf
// Pattern from TransferTx (lines 81-87):
message TransferTx
{
    DAGStruct dag_struct = 1;
    bytes token_id = 2;
    UTXOTxParams utxo_params = 3;
}

// Pattern from EscrowTx (lines 120-127) — no UTXOs, still dag_struct=1 first:
message EscrowTx
{
    DAGStruct dag_struct = 1;
    UTXOTxParams utxo_params = 2;
    uint64 amount = 3;
    bytes dev_addr = 4;
    uint64 peers_cut = 5;
}
```

**New proto messages to append** (field numbers 8+, additive only — fields 1-7 already used by TransferTx/MintTx/ProcessingTx/MintTxV2/MigrationTx/EscrowTx/EscrowReleaseTx):

```protobuf
message RegistrationMetadata
{
    string game_id = 1;      // optional
    string publisher_id = 2;  // optional
    bytes dev_wallet = 3;     // optional — 128-hex public key
    uint64 peers_cut = 4;     // optional
}

message RegistrationTx
{
    DAGStruct dag_struct = 1;              // standard DAG struct (child signature)
    bytes main_address = 2;                 // 128-hex public key of main wallet
    uint64 sequence = 3;                    // registration sequence number (monotonically increasing)
    RegistrationMetadata metadata = 4;      // optional metadata
}
```

---

### 2. `SuperGenius/src/blockchain/impl/proto/Consensus.proto` (modify)

**Analog:** Existing oneof arms (lines 70-79 in same file)

**Pattern:** Add `registration = 8` to `EmbeddedTransaction.oneof transaction`. Field 8 is the next unused field number (fields 1-7 occupied by transfer, mint_v2, mint, processing, migration, escrow, escrow_release):

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
    // ADD HERE:
    SGTransaction.RegistrationTx registration = 8;
  }
}
```

---

### 3. `SuperGenius/src/account/RegistrationTransaction.hpp` (NEW)

**Analog:** `SuperGenius/src/account/TransferTransaction.hpp` (entire file, 101 lines)

**Full header pattern to replicate:**

```cpp
/**
 * @file       RegistrationTransaction.hpp
 * @brief      Transaction for child-wallet registration
 * @date       2026-07-15
 * @author     (Phase 4)
 */
#ifndef _REGISTRATION_TRANSACTION_HPP_
#define _REGISTRATION_TRANSACTION_HPP_

#include "account/GeniusTransaction.hpp"
#include "account/proto/SGTransaction.pb.h"

namespace sgns
{
    class RegistrationTransaction final : public GeniusTransaction
    {
    public:
        // Factory — mirrors TransferTransaction::New()
        static RegistrationTransaction New( std::string                    main_address,
                                            uint64_t                      sequence,
                                            SGTransaction::RegistrationMetadata metadata,
                                            SGTransaction::DAGStruct      dag );

        ~RegistrationTransaction() override = default;

        using GeniusTransaction::SerializeByteVector;
        std::vector<uint8_t> SerializeByteVector( const SGTransaction::DAGStruct &dag ) const override;

        using GeniusTransaction::SerializeToEmbeddedTransaction;
        EmbeddedTransaction SerializeToEmbeddedTransaction( const SGTransaction::DAGStruct &dag ) const override;

        static std::shared_ptr<RegistrationTransaction> DeSerializeByteVector( const std::vector<uint8_t> &data );

        // Accessors
        std::string                          GetMainAddress() const { return main_address_; }
        uint64_t                             GetSequence() const { return sequence_; }
        SGTransaction::RegistrationMetadata  GetMetadata() const { return metadata_; }

        // Path override — returns "registration" (tx type string)
        std::string GetTransactionSpecificPath() const override
        {
            return GetType();
        }

        std::unordered_set<std::string> GetTopics() const override;

    private:
        RegistrationTransaction( std::string                          main_address,
                                 uint64_t                             sequence,
                                 SGTransaction::RegistrationMetadata  metadata,
                                 SGTransaction::DAGStruct             dag );

        std::string                         main_address_;  // 128-hex main wallet pubkey
        uint64_t                            sequence_;      // registration sequence
        SGTransaction::RegistrationMetadata metadata_;      // optional metadata

        // Static self-registration — mirrors TransferTransaction::Register()
        static bool Register()
        {
            RegisterDeserializer( "registration", &RegistrationTransaction::DeSerializeByteVector );
            return true;
        }

        static inline bool registered = Register();
    };
}
#endif
```

**Key patterns extracted from TransferTransaction.hpp (full file, lines 1-101):**

- **Include guard:** `#ifndef _TRANSFER_TRANSACTION_HPP_` / `#define _TRANSFER_TRANSACTION_HPP_`
- **Includes:** `"account/GeniusTransaction.hpp"` + `"account/proto/SGTransaction.pb.h"`
- **Class declaration:** `class TransferTransaction final : public GeniusTransaction` (no namespace wrapping needed inside `namespace sgns`)
- **`public:`** section: `static New()` factory first, then destructor, then `using` declarations for `SerializeByteVector` and `SerializeToEmbeddedTransaction`, then `DeSerializeByteVector`, then accessors, then virtual overrides (`HasUTXOParameters`, `GetUTXOParametersOpt`, `GetTransactionSpecificPath`, `GetTopics`)
- **`private:`** section: constructor (takes concrete params + `SGTransaction::DAGStruct dag`), member variables, `static Register()` with `static inline bool registered = Register()`
- **`GetTransactionSpecificPath()`** overrides to return `GetType()` (line 62-65)

---

### 4. `SuperGenius/src/account/RegistrationTransaction.cpp` (NEW)

**Analog:** `SuperGenius/src/account/TransferTransaction.cpp` (entire file, 151 lines)

**Full implementation pattern to replicate:**

**Constructor pattern** (lines 13-20):
```cpp
TransferTransaction::TransferTransaction( std::vector<OutputDestInfo> destinations,
                                          std::vector<InputUTXOInfo>  inputs,
                                          SGTransaction::DAGStruct    dag ) :
    GeniusTransaction( "transfer", SetDAGWithType( std::move( dag ), "transfer" ) ),
    input_tx_( std::move( inputs ) ),
    outputs_( std::move( destinations ) )
{
}
```

**New() factory** (lines 22-30):
```cpp
TransferTransaction TransferTransaction::New( std::vector<InputUTXOInfo>  inputs,
                                              std::vector<OutputDestInfo> destinations,
                                              SGTransaction::DAGStruct    dag )
{
    TransferTransaction instance( std::move( destinations ), std::move( inputs ), std::move( dag ) );
    instance.FillHash();
    return instance;
}
```

**SerializeByteVector** (lines 32-60) — populate proto, serialize to vector:
```cpp
std::vector<uint8_t> TransferTransaction::SerializeByteVector( const SGTransaction::DAGStruct &dag ) const
{
    SGTransaction::TransferTx tx_struct;
    tx_struct.mutable_dag_struct()->CopyFrom( dag );
    // ... populate type-specific fields ...
    size_t               size = tx_struct.ByteSizeLong();
    std::vector<uint8_t> serialized_proto( size );
    if ( !tx_struct.SerializeToArray( serialized_proto.data(), serialized_proto.size() ) )
    {
        std::cerr << "Failed to serialize transaction\n";
    }
    return serialized_proto;
}
```

**SerializeToEmbeddedTransaction** (lines 62-85) — populate proto, copy into EmbeddedTransaction oneof:
```cpp
EmbeddedTransaction TransferTransaction::SerializeToEmbeddedTransaction( const SGTransaction::DAGStruct &dag ) const
{
    EmbeddedTransaction embedded;
    SGTransaction::TransferTx tx_struct;
    tx_struct.mutable_dag_struct()->CopyFrom( dag );
    // ... populate type-specific fields ...
    *embedded.mutable_transfer() = tx_struct;  // sets the oneof field
    return embedded;
}
```

**DeSerializeByteVector (static)** (lines 87-118) — parse proto, construct via private constructor, return shared_ptr:
```cpp
std::shared_ptr<TransferTransaction> TransferTransaction::DeSerializeByteVector( const std::vector<uint8_t> &data )
{
    SGTransaction::TransferTx tx_struct;
    if ( !tx_struct.ParseFromArray( data.data(), data.size() ) )
    {
        std::cerr << "Failed to parse TransferTx from array.\n";
    }
    // ... extract fields from tx_struct ...
    return std::make_shared<TransferTransaction>( TransferTransaction( outputs, inputs, tx_struct.dag_struct() ) );
}
```

**RegistrationTransaction-specific adaptations:**
- Proto type: `SGTransaction::RegistrationTx` (not `TransferTx`)
- Constructor tag: `"registration"` (not `"transfer"`)
- Serialization: `*embedded.mutable_registration() = tx_struct;` (not `mutable_transfer()`)
- No UTXO parameters — `HasUTXOParameters()` returns `false` (base class default — no override needed)
- `GetTopics()`: include `main_address_` in topic set (like `TransferTransaction::GetTopics()` includes destination addresses at lines 140-150)

---

### 5. `SuperGenius/src/account/TransactionManager.hpp` (modify)

**Analog for `RegisterChild()` declaration:** `TransferFunds` declaration (lines 117-123)

```cpp
// Pattern from TransferFunds (lines 117-123):
outcome::result<std::string> TransferFunds( uint64_t amount, std::string destination, TokenID token_id );
```

**New declaration to add:**
```cpp
/**
 * @brief Creates and enqueues a child-wallet registration transaction.
 * @param[in] main_address  Main wallet public address (128-hex).
 * @param[in] metadata      Optional registration metadata (game_id, publisher_id, dev_wallet, peers_cut).
 * @param[in] sequence      Registration sequence number.
 * @return Transaction hash on success.
 */
outcome::result<std::string> RegisterChild( std::string                          main_address,
                                            SGTransaction::RegistrationMetadata  metadata,
                                            uint64_t                             sequence );
```

**Analog for `FilterRegistration` declaration:** `FilterTransaction` declaration (lines 564-575 in header)

```cpp
// Pattern from FilterTransaction (lines 564-575):
/**
 * @brief CRDT element filter for incoming transactions.
 *
 * Deserializes the element, verifies its signature,
 * and checks for nonce conflicts. ...
 *
 * @return nullopt to accept, or a vector of tombstone elements to reject.
 */
std::optional<std::vector<crdt::pb::Element>> FilterTransaction( const crdt::pb::Element &element );
```

Add `FilterRegistration` declaration with same signature:
```cpp
std::optional<std::vector<crdt::pb::Element>> FilterRegistration( const crdt::pb::Element &element );
```

---

### 6. `SuperGenius/src/account/TransactionManager.cpp` (modify)

Four integration points — each with a clear analog pattern.

#### 6a. `RegisterChild()` implementation — analog: `TransferFunds` (lines 539-562)

```cpp
// Pattern from TransferFunds (lines 539-562):
outcome::result<std::string> TransactionManager::TransferFunds( uint64_t    amount,
                                                                std::string destination,
                                                                TokenID     token_id )
{
    if ( GetState() != State::READY )
    {
        return outcome::failure( boost::system::error_code{} );
    }
    BOOST_OUTCOME_TRY(
        auto params,
        account_m->GetUTXOManager().CreateTxParameter( amount, std::move( destination ), token_id ) );
    auto [inputs, outputs] = params;

    auto transfer_transaction = std::make_shared<TransferTransaction>(
        TransferTransaction::New( inputs, outputs, FillDAGStruct() ) );

    transfer_transaction->MakeSignature( *account_m );
    account_m->GetUTXOManager().ReserveUTXOs( inputs, transfer_transaction->GetHash() );
    EnqueueTransaction( std::make_pair( transfer_transaction, std::nullopt ) );

    return transfer_transaction->GetHash();
}
```

**RegistrationTransaction version** — no UTXO reservations, simpler:
```cpp
outcome::result<std::string> TransactionManager::RegisterChild(
    std::string                         main_address,
    SGTransaction::RegistrationMetadata metadata,
    uint64_t                            sequence )
{
    if ( GetState() != State::READY )
    {
        return outcome::failure( boost::system::error_code{} );
    }
    auto tx = std::make_shared<RegistrationTransaction>(
        RegistrationTransaction::New( std::move( main_address ), sequence, std::move( metadata ), FillDAGStruct() ) );
    tx->MakeSignature( *account_m );
    EnqueueTransaction( std::make_pair( tx, std::nullopt ) );
    return tx->GetHash();
}
```

#### 6b. `DeSerializeEmbeddedTransaction` — add `case EmbeddedTransaction::kRegistration:` arm (lines 1395-1469)

**Analog: existing case arms (lines 1416-1463):**

```cpp
// Pattern — every case arm does the same thing:
case EmbeddedTransaction::kTransfer:
{
    std::string bytes;
    embedded.transfer().SerializeToString( &bytes );
    return GeniusTransaction::GetDeSerializers().at( "transfer" )(
        std::vector<uint8_t>( bytes.begin(), bytes.end() ) );
}
```

**New arm to add (after `case EmbeddedTransaction::kEscrowRelease:` at line 1464):**
```cpp
case EmbeddedTransaction::kRegistration:
{
    std::string bytes;
    embedded.registration().SerializeToString( &bytes );
    return GeniusTransaction::GetDeSerializers().at( "registration" )(
        std::vector<uint8_t>( bytes.begin(), bytes.end() ) );
}
```

**Also add to the static registration lambda** (lines 1400-1410):
```cpp
GeniusTransaction::RegisterDeserializer( "registration", &RegistrationTransaction::DeSerializeByteVector );
```

#### 6c. `SendTransactionItem` — divert CRDT write for RegistrationTx to `reg/{child_addr}` (lines 1130-1210)

**Analog: existing path logic (lines 1184-1191):**

```cpp
// Current untyped path (lines 1184-1191):
auto                   transaction_path = GetTransactionPath( *transaction );
crdt::HierarchicalKey  tx_key( transaction_path );
crdt::GlobalDB::Buffer data_transaction;
m_logger->debug( "Recording the transaction on {}", tx_key.GetKey() );
data_transaction.put( transaction->SerializeByteVector() );
BOOST_OUTCOME_TRY( crdt_transaction->Put( std::move( tx_key ), std::move( data_transaction ) ) );
```

**`GetTransactionPath` uses `GetBlockChainBase() + GeniusTransaction::GetTransactionFullPath()`** (lines 1296-1298, 174-177 of GeniusTransaction.hpp):
```cpp
// GetTransactionPath (lines 1296-1299):
std::string TransactionManager::GetTransactionPath( const GeniusTransaction &element )
{
    return GetBlockChainBase() + element.GetTransactionFullPath();
}

// GeniusTransaction::GetTransactionFullPath() (GeniusTransaction.hpp lines 174-177):
std::string GetTransactionFullPath() const
{
    return "tx/" + GetHash();
}
```

**Planner decision point — path diversion:** In `SendTransactionItem`, before the path construction at line ~1184, insert a type check. When the transaction type is `"registration"`, build the path as `GetBlockChainBase() + "reg/" + child_addr` instead of `GetTransactionPath(*transaction)`. Extract `child_addr` from `registration_transaction->GetSrcAddress()` (the child's public key, which is the `dag_struct.source_addr()`).

#### 6d. `FilterRegistration` — new CRDT element filter (analog: `FilterTransaction`, lines 2661-2721)

**Analog: `FilterTransaction` (lines 2661-2721):**
```cpp
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
            m_logger->error( "Failed to deserialize incoming transaction {}", element.key() );
            break;
        }
        new_tx = maybe_new_tx.value();

        if ( !CheckTransactionAuthorization( *new_tx ) )
        {
            m_logger->error( "Could not validate signature of transaction {}", element.key() );
            break;
        }
        if ( KeyExistsInDB( GetTransactionPath( *new_tx ) ) )
        {
            m_logger->debug( "New transaction {} would overwrite an existing one. Preventing that",
                             new_tx->GetHash() );
            break;
        }
        should_delete = false;
    } while ( 0 );

    if ( should_delete )
    {
        std::vector<crdt::pb::Element> additional_elements_to_delete;
        // ... tombstone construction ...
        maybe_tombstones = additional_elements_to_delete;
    }
    return maybe_tombstones;
}
```

**Phase 4 `FilterRegistration` (minimal — gates a-c):**
```cpp
std::optional<std::vector<crdt::pb::Element>> TransactionManager::FilterRegistration(
    const crdt::pb::Element &element )
{
    std::optional<std::vector<crdt::pb::Element>> maybe_tombstones;
    bool                                          should_delete = true;
    do
    {
        // Gate (a): deserialization failure
        auto maybe_new_tx = DeSerializeTransaction( element.value() );
        if ( maybe_new_tx.has_error() )
        {
            m_logger->error( "Failed to deserialize registration {}", element.key() );
            break;
        }
        auto new_tx = maybe_new_tx.value();
        if ( new_tx->GetType() != "registration" )
        {
            break;
        }
        auto reg_tx = std::dynamic_pointer_cast<RegistrationTransaction>( new_tx );
        if ( !reg_tx )
        {
            break;
        }

        // Gate (b): invalid child signature
        if ( !CheckTransactionAuthorization( *reg_tx ) )
        {
            m_logger->error( "Invalid signature on registration {}", element.key() );
            break;
        }

        // Gate (c): malformed main_address (not 128-hex pubkey)
        // 128 hex chars = 64 bytes => check length == 128
        if ( reg_tx->GetMainAddress().size() != 128 )
        {
            m_logger->error( "Malformed main_address in registration {}", element.key() );
            break;
        }

        // Phase 5 adds: sequence monotonicity gate here

        should_delete = false;
    } while ( 0 );

    if ( should_delete )
    {
        // Return tombstone to reject the element
        maybe_tombstones = std::vector<crdt::pb::Element>{};
    }
    return maybe_tombstones;
}
```

#### 6e. Register `FilterRegistration` in `TransactionManager::New()` (lines 196-219)

**Analog: tx/ and proof/ filter registration in `New()` (lines 197-219):**

```cpp
// Pattern from tx/ filter (lines 197-207):
std::string blockchain_base = GetBlockChainBase( network_id );
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
```

**New reg/ filter registration (same `New()` method, after the `proof/` filter block):**
```cpp
// Register the reg/ element filter for child-wallet registrations
bool crdt_reg_filter_initialized = instance->globaldb_m->RegisterElementFilter(
    "^/?" + blockchain_base + "reg/[^/]+",
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

---

### 7. `SuperGenius/src/account/GeniusNode.hpp` (modify)

**Analog: `TransferFunds` / `MintTokens` declarations (lines 367-389 in GeniusNode.hpp)**

```cpp
// Pattern from MintTokens declaration (lines 367-371):
outcome::result<std::string> MintTokens( uint64_t           amount,
                                         const std::string &transaction_hash,
                                         const std::string &chainid,
                                         TokenID            tokenid,
                                         std::string        destination = "" );

// Pattern from TransferFunds declaration (lines 504-511):
outcome::result<std::string> TransferFunds( uint64_t amount, const std::string &destination, TokenID token_id );
```

**New declaration to add:**
```cpp
/**
 * @brief Registers a child wallet under a main wallet address.
 * @param[in] main_address Main wallet public address (128-hex).
 * @param[in] metadata      Optional registration metadata.
 * @param[in] sequence      Registration sequence number.
 * @return Registration transaction hash on success.
 */
outcome::result<std::string> RegisterChild( const std::string                   &main_address,
                                            SGTransaction::RegistrationMetadata  metadata,
                                            uint64_t                             sequence );
```

---

### 8. `SuperGenius/src/account/GeniusNode.cpp` (modify)

**Analog: `TransferFunds` thin wrapper (lines 2258-2283) and `MintTokens` thin wrapper (lines 2116-2137)**

```cpp
// Pattern from TransferFunds thin wrapper (lines 2258-2283):
outcome::result<std::string> GeniusNode::TransferFunds( uint64_t           amount,
                                                        const std::string &destination,
                                                        TokenID            token_id )
{
    if ( GetTransactionManagerState() != TransactionManager::State::READY )
    {
        node_logger_->error( "{}: Transaction Manager is not ready", __func__ );
        return outcome::failure( Error::TRANSACTIONS_NOT_READY );
    }
    // ... local validation (balance check for TransferFunds) ...
    BOOST_OUTCOME_TRY( auto manager, GetTransactionManager() );
    BOOST_OUTCOME_TRY( auto tx_id, manager->TransferFunds( amount, destination, token_id ) );
    node_logger_->debug( "{}: transaction {} sent", __func__, tx_id );
    return tx_id;
}
```

**Registration version — minimal wrapper:**
```cpp
outcome::result<std::string> GeniusNode::RegisterChild( const std::string                   &main_address,
                                                        SGTransaction::RegistrationMetadata  metadata,
                                                        uint64_t                             sequence )
{
    if ( GetTransactionManagerState() != TransactionManager::State::READY )
    {
        node_logger_->error( "{}: Transaction Manager is not ready", __func__ );
        return outcome::failure( Error::TRANSACTIONS_NOT_READY );
    }
    BOOST_OUTCOME_TRY( auto manager, GetTransactionManager() );
    BOOST_OUTCOME_TRY( auto tx_id, manager->RegisterChild( main_address, metadata, sequence ) );
    node_logger_->debug( "{}: registration transaction {} sent", __func__, tx_id );
    return tx_id;
}
```

---

### 9. `SuperGenius/src/account/CMakeLists.txt` (modify)

**Analog: `GENIUS_NODE_SOURCES` variable (lines 57-74)**

**Pattern:** Add `RegistrationTransaction.cpp` to the list:

```cmake
# Existing (lines 57-74):
set(GENIUS_NODE_SOURCES
    GeniusTransaction.cpp
    TransferTransaction.cpp
    MintTransaction.cpp
    MintTransactionV2.cpp
    MigrationTransaction.cpp
    ProcessingTransaction.cpp
    EscrowTransaction.cpp
    GeniusInputValidator.cpp
    MigrationInputValidator.cpp
    InputValidators.cpp
    PublicChainInputValidator.cpp
    TransactionManager.cpp
    TokenAmount.cpp
    GeniusNode.cpp
    ChainRpcEndpointProvider.cpp
    BridgeRelayer.cpp
)

# Add RegistrationTransaction.cpp alphabetically:
    RegistrationTransaction.cpp
```

**Add after `ProcessingTransaction.cpp`** (alphabetical by type — `R` after `P`):
```cmake
    RegistrationTransaction.cpp       # <-- NEW
```

---

### 10. `SuperGenius/test/src/account/registration_transaction_test.cpp` (NEW)

**Analog 1 (structure):** `SuperGenius/test/src/account/account_signature_test.cpp` (112 lines)

**Test fixture pattern** (lines 55-73):
```cpp
class GeniusAccountSignatureTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        GeniusAccount::SetSecureStorageFactory(
            []( const std::string &identifier ) -> std::shared_ptr<ISecureStorage>
            { return std::make_shared<MemorySecureStorage>( identifier ); } );
        path_ = boost::filesystem::temp_directory_path() / boost::filesystem::unique_path();
    }
    void TearDown() override
    {
        GeniusAccount::SetSecureStorageFactory( nullptr );
        boost::filesystem::remove_all( path_ );
    }
    boost::filesystem::path path_;
};
```

**Include pattern** (lines 1-10):
```cpp
#include <gtest/gtest.h>
#include <boost/filesystem/operations.hpp>
#include "account/GeniusAccount.hpp"
#include "local_secure_storage/impl/MemorySecureStorage.hpp"
```

**Analog 2 (linking):** `transaction_manager_pending_lifecycle_test.cpp` in test CMakeLists.txt (lines 110-131):
```cmake
addtest(transaction_manager_pending_lifecycle_test
    transaction_manager_pending_lifecycle_test.cpp
)
target_link_libraries(transaction_manager_pending_lifecycle_test
    genius_node_test
    json_secure_storage
    base_crdt_test
)
```

---

### 11. `SuperGenius/test/src/account/CMakeLists.txt` (modify)

**Analog: `addtest(...)` + `target_link_libraries(...)` for test targets needing `genius_node_test`**

```cmake
# Pattern from bridge_relayer_test (lines 70-88):
addtest(registration_transaction_test
    registration_transaction_test.cpp
)
target_link_libraries(registration_transaction_test
    genius_node_test
    json_secure_storage
)

if(MSVC)
    target_link_options(registration_transaction_test PUBLIC /WHOLEARCHIVE:$<TARGET_FILE:genius_node_test>)
elseif(APPLE)
    target_link_options(registration_transaction_test PUBLIC -force_load "$<TARGET_FILE:genius_node_test>")
else()
    target_link_options(registration_transaction_test PUBLIC
        "-Wl,--whole-archive"
        "$<TARGET_FILE:genius_node_test>"
        "-Wl,--no-whole-archive"
    )
endif()
```

---

## Shared Patterns

### Deserializer Registration (applies to RegistrationTransaction.cpp + TransactionManager.cpp)

Two-level registration — the `static inline bool registered` in the header ensures static-init registration; the lambda in `DeSerializeEmbeddedTransaction` is a forced re-registration for safety:

**Level 1 — RegistrationTransaction.hpp (line 87-91 of TransferTransaction.hpp pattern):**
```cpp
static bool Register()
{
    RegisterDeserializer( "registration", &RegistrationTransaction::DeSerializeByteVector );
    return true;
}
static inline bool registered = Register();
```

**Level 2 — TransactionManager.cpp DeSerializeEmbeddedTransaction (lines 1400-1410):**
```cpp
static const bool registered = []
{
    // ... existing registrations ...
    GeniusTransaction::RegisterDeserializer( "registration", &RegistrationTransaction::DeSerializeByteVector );
    return true;
}();
```

### Proto Build (applies to all proto modifications)

Proto files under `SuperGenius/src/account/proto/` are built via `add_proto_library` in CMakeLists.txt line 1. No CMakeLists.txt changes needed for proto changes — the proto library is already built from `SGTransaction.proto`.

### Error Handling (applies to all C++ files)

All factory methods return `outcome::result<T>`. Use `BOOST_OUTCOME_TRY` for propagation:
```cpp
// Pattern from TransferFunds:
BOOST_OUTCOME_TRY( auto manager, GetTransactionManager() );
BOOST_OUTCOME_TRY( auto tx_id, manager->TransferFunds( amount, destination, token_id ) );
```

### Signing Pattern (applies to RegistrationTransaction::New() flow)

```cpp
// From TransferFunds (lines 552-555):
auto transfer_transaction = std::make_shared<TransferTransaction>(
    TransferTransaction::New( inputs, outputs, FillDAGStruct() ) );
transfer_transaction->MakeSignature( *account_m );
```

### FillDAGStruct (applies to TransactionManager::RegisterChild)

```cpp
// FillDAGStruct populates the DAG with src addr, nonce, timestamp etc.
// Pattern from TransferFunds (line 553):
TransferTransaction::New( inputs, outputs, FillDAGStruct() )
```

### Base64/Blob types — note that main_address is stored as proto `bytes`, not `string`

Proto field for `main_address` should be `bytes main_address = 2` (matching binary key format used by `GeniusAccount::GetAddress()` which produces hex strings). The `CheckSignature()` + `CheckTransactionAuthorization` patterns use the DAG's `source_addr` field which is a `bytes` field for the public key.

---

## No Analog Found

All 11 files have close existing analogs in the codebase. No files require fallback to RESEARCH.md patterns.

---

## Metadata

**Analog search scope:** `SuperGenius/src/account/`, `SuperGenius/src/crdt/globaldb/`, `SuperGenius/src/blockchain/impl/proto/`, `SuperGenius/test/src/account/`
**Files scanned:** ~25 source files (analogs + cross-references)
**Pattern extraction date:** 2026-07-15
**Key library dependencies confirmed:**
- Protobuf `SGTransaction::` namespace (RegistrationTx, RegistrationMetadata, DAGStruct)
- `EmbeddedTransaction` from `Consensus.pb.h`
- `GeniusTransaction::RegisterDeserializer()`, `SetDAGWithType()`, `FillHash()`, `MakeSignature()`, `CheckSignature()` 
- `TransactionManager::FillDAGStruct()`, `EnqueueTransaction()`, `GetState()`, `DeSerializeEmbeddedTransaction()`
- `crdt::GlobalDB::RegisterElementFilter(regex, callback)` returning `bool`
- `crdt::pb::Element` with `.key()` and `.value()` accessors
- `GeniusAccount::MakeSignature()` / `CheckSignature()` / `IsValidPublicKey()` / `NormalizeAddress()`
