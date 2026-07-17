# Phase 05: CRDT Persistence, PubSub & Integration Test - Pattern Map

**Mapped:** 2026-07-16
**Files analyzed:** 8 new/modified files
**Analogs found:** 7 / 8 (one config-only file has no code analog)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `TransactionManager.cpp` — gate (d) | service | CRDT-element-filter | `FilterTransaction()` (same file, line 2708) | exact — same filter pattern |
| `TransactionManager.cpp` — `GetRegistrationsForMain` | service | CRDT-scan | `QueryTransactions()` (same file, line 1646) | exact — same QueryKeyValues pattern |
| `TransactionManager.cpp` — `RegisterChild` auto-derive | service | CRUD | `RegisterChild()` (same file, line 578) | exact — overload of existing method |
| `TransactionManager.cpp` — CID notification handler | service | pubsub-event | `NewElementCallback()` + `StartListeningTopics()` (same file, lines 364–377, 668) | role-match — callback registration + topic listen |
| `TransactionManager.hpp` | service (header) | — | Existing declarations (same file, lines 132–134, 587–610) | exact — same header conventions |
| `GeniusNode.cpp` — wrappers + CID handler | service/facade | request-response | `GeniusNode::RegisterChild()` (same file, line 2285) + `TransferFunds()` (line 2258) | exact — same two-layer wrapper pattern |
| `GeniusNode.hpp` — wrapper declarations | service/facade header | — | `GeniusNode::RegisterChild()` declaration (same file, line 520) | exact — same doxygen convention |
| `test/.../regtest/child_registration.cpp` | test | multi-node-integration | `multi_account_sync.cpp` (fixture/CreateNode) + `registration_transaction_test.cpp` (filter/E2E) | exact — composite of two analogs |
| `test/src/multiaccount/CMakeLists.txt` | config | — | `test/src/multiaccount/CMakeLists.txt` (line 1) | exact — identical addtest pattern |

---

## Pattern Assignments

### 1. `SuperGenius/src/account/TransactionManager.cpp` — Gate (d) Sequence Monotonicity in `FilterRegistration`

**Analog:** `FilterTransaction()` (same file, lines 2708–2768) + `KeyExistsInDB` (line 4862) + `FilterRegistration` gates a–c (lines 2770–2820)

**Imports already present — no new imports needed for gate (d).**

**Core pattern — CRDT element filter structure** (lines 2770–2820):
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

        // Gate (c): malformed main_address (not 128 hex chars)
        if ( reg_tx->GetMainAddress().size() != 128 )
        {
            m_logger->error( "Malformed main_address in registration {}", element.key() );
            break;
        }

        // Phase 5 adds: (d) sequence monotonicity check
        // INSERT GATE (d) HERE — see pattern below

        should_delete = false;
    } while ( 0 );

    if ( should_delete )
    {
        maybe_tombstones = std::vector<crdt::pb::Element>{};
    }
    return maybe_tombstones;
}
```

**Gate (d) pattern — CRDT value read + deserialize + compare** (based on `KeyExistsInDB` at lines 4862–4871 + `DeSerializeTransaction` at line 2778):
```cpp
// Gate (d): sequence monotonicity — read existing reg/ record, reject unless
// incoming sequence is strictly higher AND sequence > 0.
if ( reg_tx->GetSequence() == 0 )
{
    m_logger->error( "Zero sequence in registration {}", element.key() );
    break;
}
// Build the reg/ key for the same child: GetBlockChainBase() + "reg/" + child_addr
std::string reg_key = GetBlockChainBase() + "reg/" + reg_tx->GetSrcAddress();
auto existing_data = globaldb_m->Get( reg_key );   // GlobalDB::Get accepts string → HierarchicalKey implicit
if ( existing_data.has_value() )
{
    auto maybe_existing_tx = DeSerializeTransaction( existing_data.value() );
    if ( !maybe_existing_tx.has_error() )
    {
        auto existing_tx = maybe_existing_tx.value();
        if ( existing_tx->GetType() == "registration" )
        {
            auto existing_reg = std::dynamic_pointer_cast<RegistrationTransaction>( existing_tx );
            if ( existing_reg && reg_tx->GetSequence() <= existing_reg->GetSequence() )
            {
                m_logger->error(
                    "Non-monotonic sequence in registration {}: incoming={}, stored={}",
                    element.key(),
                    reg_tx->GetSequence(),
                    existing_reg->GetSequence() );
                break;
            }
        }
    }
}
```

**Key detail:** `globaldb_m->Get(reg_key)` on line 4864 passes a `std::string` which implicitly converts to `HierarchicalKey` (constructor at `hierarchical_key.hpp:32`). The `DeSerializeTransaction(string)` overload at line 1421 accepts `std::string`.

---

### 2. `SuperGenius/src/account/TransactionManager.cpp` — `RegisterChild` Auto-Derive Sequence Overload

**Analog:** Existing `RegisterChild()` (same file, lines 578–592)

**Existing base pattern:**
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

**New auto-derive overload — follow the same structure, read stored sequence from CRDT:**
```cpp
outcome::result<std::string> TransactionManager::RegisterChild(
    std::string                         main_address,
    SGTransaction::RegistrationMetadata metadata )
{
    if ( GetState() != State::READY )
    {
        return outcome::failure( boost::system::error_code{} );
    }

    // Auto-derive sequence: read reg/{child_addr} from CRDT, use stored + 1 (or 1 if none)
    uint64_t sequence = 1;
    std::string reg_key = GetBlockChainBase() + "reg/" + account_m->GetAddress();
    auto existing_data = globaldb_m->Get( reg_key );
    if ( existing_data.has_value() )
    {
        auto maybe_existing = DeSerializeTransaction( existing_data.value() );
        if ( !maybe_existing.has_error() )
        {
            auto existing = maybe_existing.value();
            if ( existing->GetType() == "registration" )
            {
                auto existing_reg = std::dynamic_pointer_cast<RegistrationTransaction>( existing );
                if ( existing_reg )
                {
                    sequence = existing_reg->GetSequence() + 1;
                }
            }
        }
    }

    return RegisterChild( std::move( main_address ), std::move( metadata ), sequence );
}
```

**Planner discretion item (D-47):** The above uses a two-arg overload delegating to the three-arg version. An alternative is a `std::optional<uint64_t>` single method — planner picks whichever is more idiomatic.

---

### 3. `SuperGenius/src/account/TransactionManager.cpp` — `GetRegistrationsForMain` (discovery read path)

**Analog:** `QueryTransactions()` (same file, lines 1646–1676) — CRDT scan via `QueryKeyValues`

**Scan pattern:**
```cpp
void TransactionManager::QueryTransactions()
{
    for ( auto network_id : GetMonitoredNetworkIDs() )
    {
        const std::string query_path = GetBlockChainBase( network_id ) + "tx";
        m_logger->trace( "Probing transactions on {}", query_path );
        auto transaction_list = globaldb_m->QueryKeyValues( query_path );
        if ( transaction_list.has_error() )
        {
            m_logger->error( "Unable to query transactions on {}", query_path );
            continue;
        }

        m_logger->trace( "Transaction list grabbed from CRDT with Size {}", transaction_list.value().size() );

        for ( const auto &[key, value] : transaction_list.value() )
        {
            auto transaction_key = globaldb_m->KeyToString( key );
            if ( !transaction_key.has_value() )
            {
                m_logger->error( "Unable to convert a key to string" );
                continue;
            }
            auto process_result = FetchAndProcessTransaction( transaction_key.value(), value );
            if ( process_result.has_error() )
            {
                m_logger->error( "Unable to fetch and process transaction {}", transaction_key.value() );
            }
        }
    }
}
```

**`GetRegistrationsForMain` — applying the same scan pattern to `reg/` namespace with filtering:**
```cpp
outcome::result<std::vector<RegistrationDiscoveryEntry>> TransactionManager::GetRegistrationsForMain(
    const std::string &main_address )
{
    std::vector<RegistrationDiscoveryEntry> results;
    for ( auto network_id : GetMonitoredNetworkIDs() )
    {
        const std::string query_path = GetBlockChainBase( network_id ) + "reg";
        auto reg_list = globaldb_m->QueryKeyValues( query_path );
        if ( !reg_list.has_value() )
        {
            continue;
        }

        for ( const auto &[key, value] : reg_list.value() )
        {
            auto maybe_tx = DeSerializeTransaction( value );  // string overload, line 1421
            if ( !maybe_tx.has_value() )
            {
                continue;
            }
            auto tx = maybe_tx.value();
            if ( tx->GetType() != "registration" )
            {
                continue;
            }
            auto reg_tx = std::dynamic_pointer_cast<RegistrationTransaction>( tx );
            if ( !reg_tx )
            {
                continue;
            }
            if ( reg_tx->GetMainAddress() != main_address )
            {
                continue;
            }

            RegistrationDiscoveryEntry entry;
            entry.child_addr  = reg_tx->GetSrcAddress();
            entry.main_addr   = reg_tx->GetMainAddress();
            entry.sequence    = reg_tx->GetSequence();
            entry.metadata    = reg_tx->GetMetadata();
            results.push_back( std::move( entry ) );
        }
    }
    return results;
}
```

**Key detail:** `globaldb_m->QueryKeyValues(query_path)` returns `outcome::result<QueryResult>` where `QueryResult = std::map<Buffer, Buffer>` (from `rocksdb.hpp:33`). The `value` in the loop is a `Buffer` which can be used directly with `DeSerializeTransaction(string)` after conversion, or passed as a `string` since `DeSerializeTransaction` at line 1421 accepts `std::string` and the `Buffer` has implicit conversion or a `.toString()` method.

**Return type:** The discovery struct should be at the top of `TransactionManager.hpp` (near line 36, after `EscrowDataPair`), following the existing type alias convention:
```cpp
struct RegistrationDiscoveryEntry
{
    std::string                         child_addr;  ///< Child wallet public address (128-hex)
    std::string                         main_addr;   ///< Main wallet public address (128-hex)
    uint64_t                            sequence;    ///< Registration sequence number
    SGTransaction::RegistrationMetadata metadata;    ///< Registration metadata
};
```

---

### 4. `SuperGenius/src/account/TransactionManager.hpp` — New Declarations

**Analog:** Existing declarations at lines 132–134 (RegisterChild), 587–610 (filter declarations), 717 (KeyExistsInDB)

**Header structure — insert new declarations after `RegisterChild` (line 134):**
```cpp
/**
 * @brief Creates and enqueues a child-wallet registration transaction with auto-derived sequence.
 *
 * Reads the existing reg/{child_addr} CRDT record and uses stored sequence + 1
 * (or 1 if no prior registration exists).
 *
 * @param[in] main_address Main wallet public address (128-hex).
 * @param[in] metadata      Optional registration metadata (game_id, publisher_id, dev_wallet, peers_cut).
 * @return Transaction hash on success.
 */
outcome::result<std::string> RegisterChild( std::string                          main_address,
                                            SGTransaction::RegistrationMetadata  metadata );
```

**Add after the public method section (~line 717, near `KeyExistsInDB`):**
```cpp
/**
 * @brief Enumerates child registrations naming a specific main wallet.
 *
 * Scans the reg/ CRDT namespace across all monitored networks and returns
 * entries whose main_address matches @p main_address.
 *
 * @param[in] main_address Main wallet public address (128-hex) to query for.
 * @return Vector of RegistrationDiscoveryEntry on success, or error on failure.
 */
outcome::result<std::vector<RegistrationDiscoveryEntry>> GetRegistrationsForMain(
    const std::string &main_address );
```

**Add the discovery struct near EscrowDataPair (line 38):**
```cpp
struct RegistrationDiscoveryEntry
{
    std::string                         child_addr;  ///< Child wallet public address (128-hex)
    std::string                         main_addr;   ///< Main wallet public address (128-hex)
    uint64_t                            sequence;    ///< Registration sequence number
    SGTransaction::RegistrationMetadata metadata;    ///< Registration metadata
};
```

---

### 5. `SuperGenius/src/account/GeniusNode.cpp` — Wrappers + CID Handler

**Analog:** `GeniusNode::RegisterChild()` (lines 2285–2298 — existing wrapper) + `GeniusNode::TransferFunds()` (lines 2258–2283 — two-layer pattern)

**Pattern for `RegisterChild` auto-derive wrapper** (follows existing RegisterChild wrapper exactly):
```cpp
outcome::result<std::string> GeniusNode::RegisterChild( const std::string                   &main_address,
                                                        SGTransaction::RegistrationMetadata  metadata )
{
    if ( GetTransactionManagerState() != TransactionManager::State::READY )
    {
        node_logger_->error( "{}: Transaction Manager is not ready", __func__ );
        return outcome::failure( Error::TRANSACTIONS_NOT_READY );
    }
    BOOST_OUTCOME_TRY( auto manager, GetTransactionManager() );
    BOOST_OUTCOME_TRY( auto tx_id, manager->RegisterChild( main_address, metadata ) );
    node_logger_->debug( "{}: registration transaction {} sent", __func__, tx_id );
    return tx_id;
}
```

**Pattern for `GetRegistrationsForMain` wrapper** (follows same two-layer pattern):
```cpp
outcome::result<std::vector<RegistrationDiscoveryEntry>> GeniusNode::GetRegistrationsForMain(
    const std::string &main_address )
{
    if ( GetTransactionManagerState() != TransactionManager::State::READY )
    {
        node_logger_->error( "{}: Transaction Manager is not ready", __func__ );
        return outcome::failure( Error::TRANSACTIONS_NOT_READY );
    }
    BOOST_OUTCOME_TRY( auto manager, GetTransactionManager() );
    BOOST_OUTCOME_TRY( auto entries, manager->GetRegistrationsForMain( main_address ) );
    node_logger_->debug( "{}: found {} registrations for main {}", __func__, entries.size(), main_address.substr(0, 16) );
    return entries;
}
```

**CID notification handler pattern — wiring a handler on own address topic:**

Reference how `StartListeningTopics()` (TransactionManager.cpp lines 364–377) registers a listen topic on the node's own address. The handler subscribes to messages landing on the local account address topic. When a CID notification arrives (payload is a CID string, per D-18), the handler resolves the full RegistrationTx from local CRDT, validates against FilterRegistration, and calls `AddListenTopic(child_addr)` to follow.

**Planner discretion item:** Handler wiring location (TransactionManager vs GeniusNode). The pattern suggests TransactionManager is the right place since it owns `globaldb_m` and filter logic, but the GeniusNode's existing CID notification wiring (via `AccountMessenger` pattern, lines 585, 1853 in GeniusNode.cpp using `tx_globaldb_->AddListenTopic(processing_channel_topic_)`) suggests GeniusNode-level is also valid.

**AddListenTopic follow pattern** (from TransactionManager.cpp line 371):
```cpp
globaldb_m->AddListenTopic( child_addr );
```

---

### 6. `SuperGenius/src/account/GeniusNode.hpp` — Wrapper Declarations

**Analog:** `GeniusNode::RegisterChild()` declaration (lines 520–522)

**Insert after existing RegisterChild declaration (line 522):**
```cpp
/**
 * @brief Registers this node as a child of main_address with auto-derived sequence.
 *
 * Reads the existing reg/ CRDT record for this node and increments the
 * sequence automatically. Caller-supplied sequence variant is available
 * for tests and replay scenarios.
 *
 * @param[in] main_address Main wallet public address (128-hex).
 * @param[in] metadata      Optional registration metadata.
 * @return Registration transaction hash on success.
 */
outcome::result<std::string> RegisterChild( const std::string                   &main_address,
                                            SGTransaction::RegistrationMetadata  metadata );

/**
 * @brief Enumerates child registrations naming a specific main wallet.
 *
 * Scans the reg/ CRDT namespace and returns entries whose main_address matches.
 *
 * @param[in] main_address Main wallet public address (128-hex) to query for.
 * @return Vector of RegistrationDiscoveryEntry on success.
 */
outcome::result<std::vector<RegistrationDiscoveryEntry>> GetRegistrationsForMain(
    const std::string &main_address );
```

---

### 7. `SuperGenius/test/src/multiaccount/regtest/child_registration.cpp` — Integration Test

**Analogs:**
- `multi_account_sync.cpp` — fixture/CreateNode/WaitForNodeSync patterns
- `registration_transaction_test.cpp` — RegistrationE2ETestAccess friend accessor, filter-level injection, CRDT element construction

**Test fixture — `MultiAccountTest` class pattern** (from `multi_account_sync.cpp` lines 60–169):
```cpp
class MultiAccountTest : public ::testing::Test
{
protected:
    static constexpr std::string_view FILE_PREFIX = "mat_";

    std::shared_ptr<sgns::GeniusNode> CreateNode( const std::string &self_address,
                                                  const std::string &dev_addr,
                                                  const std::string &tokenValue,
                                                  sgns::TokenID      tokenId,
                                                  bool               isFullNode          = false,
                                                  bool               isProcessor         = false,
                                                  bool               isGenesisAuthorized = false )
    {
        static std::atomic<int> nodeCounter{ 0 };
        int                     id = nodeCounter.fetch_add( 1 );

        auto binaryPath = boost::dll::program_location().parent_path();
        auto outPath    = binaryPath / ( std::string( FILE_PREFIX ) + std::to_string( id ) );
        auto outPathStr = outPath.generic_string() + '/';

        DevConfig_st devConfig = { dev_addr, "0.65", tokenValue, tokenId, outPathStr };

        std::filesystem::remove_all( devConfig.BaseWritePath );
        std::filesystem::create_directories( devConfig.BaseWritePath );
        {
            std::ofstream bridgeConfigFile( devConfig.BaseWritePath + "bridge_chains_config.json" );
            bridgeConfigFile << "{}";
        }

        // Generate deterministic key from self_address
        std::string key;
        key.reserve( 64 );
        std::hash<std::string> hasher;
        size_t                 address_hash = hasher( self_address );
        std::mt19937                    rng( static_cast<uint32_t>( address_hash ) );
        std::uniform_int_distribution<> dist( 0, 15 );
        std::generate_n( std::back_inserter( key ),
                         64,
                         [&]()
                         {
                             static constexpr std::string_view hexChars = "0123456789abcdef";
                             return hexChars[dist( rng )];
                         } );

        uint16_t uniquePort = static_cast<uint16_t>( 40001 + id );
        sgns::GeniusNode::WriteNetworkConfig( devConfig.BaseWritePath, uniquePort, /*auto_dht=*/false );
        sgns::GeniusNode::WriteSgnsConfig( devConfig.BaseWritePath,
                                           isFullNode ? "Full" : "Light",
                                           /*is_processor=*/isProcessor );
        auto node = sgns::GeniusNode::New( devConfig, sgns::FromPrivateKey{ key } );
        if ( isGenesisAuthorized )
        {
            sgns::Blockchain::SetAuthorizedFullNodeAddress( node->GetAddress() );
        }
        return node;
    }

    void SetUp() override
    {
        GeniusAccount::SetSecureStorageFactory( []( const std::string &identifier ) -> std::shared_ptr<ISecureStorage>
                                                { return std::make_shared<MemorySecureStorage>( identifier ); } );
        // Clean up previous test runs
        auto binaryPath = boost::dll::program_location().parent_path();
        for ( auto &entry : boost::filesystem::directory_iterator( binaryPath ) )
        {
            if ( entry.is_directory() && entry.path().filename().string().find( FILE_PREFIX ) != std::string::npos )
            {
                std::error_code ec;
                std::filesystem::remove_all( entry.path(), ec );
            }
        }
    }
};
```

**Integration test structure — three-node topology (D-51, D-52):**

Following the shared-fixture pattern from multi_account_sync.cpp, but with a class-static fixture (`SetUpTestSuite`) to amortize the ~121s GossipPubSub boot:

```cpp
class ChildRegistrationIntegrationTest : public ::testing::Test
{
protected:
    static constexpr std::string_view FILE_PREFIX = "cri_";
    static const sgns::TokenID kTestTokenId;

    // Static — all TEST_F cases share this 3-node network
    static std::shared_ptr<sgns::GeniusNode> genesis_node_;
    static std::shared_ptr<sgns::GeniusNode> main_node_;     // node A
    static std::shared_ptr<sgns::GeniusNode> child_node_;    // node B

    static void SetUpTestSuite()
    {
        GeniusAccount::SetSecureStorageFactory(
            []( const std::string &id ) { return std::make_shared<MemorySecureStorage>( id ); } );

        // Genesis-authorized node
        genesis_node_ = CreateNode( "regtest_genesis", "0xcafe", "1.0",
                                    kTestTokenId, true, true, true );
        ASSERT_TRUE( WaitForNodeSync( genesis_node_, std::chrono::milliseconds( 180000 ) ) );

        // Main wallet node A
        main_node_ = CreateNode( "regtest_main", "0xcafe", "1.0", kTestTokenId );
        main_node_->GetPubSub()->AddPeers( { genesis_node_->GetPubSub()->GetInterfaceAddress() } );
        ASSERT_TRUE( WaitForNodeSync( main_node_, std::chrono::milliseconds( 180000 ) ) );

        // Child wallet node B
        child_node_ = CreateNode( "regtest_child", "0xcafe", "1.0", kTestTokenId );
        child_node_->GetPubSub()->AddPeers( { genesis_node_->GetPubSub()->GetInterfaceAddress() } );
        ASSERT_TRUE( WaitForNodeSync( child_node_, std::chrono::milliseconds( 180000 ) ) );
    }

    static void TearDownTestSuite()
    {
        child_node_.reset();
        main_node_.reset();
        genesis_node_.reset();
        GeniusAccount::SetSecureStorageFactory( nullptr );
    }
};
```

**TEST-02 — positive registration** (follows `ChildRegistrationEndToEnd` from `registration_transaction_test.cpp` lines 254–328):
```cpp
TEST_F( ChildRegistrationIntegrationTest, ChildRegistersWithMain )
{
    std::string main_address = main_node_->GetAddress();
    SGTransaction::RegistrationMetadata metadata;
    metadata.set_game_id( "integration_test" );

    auto result = child_node_->RegisterChild( main_address, metadata, 1 );
    ASSERT_TRUE( result.has_value() ) << "Registration submission failed";
    std::string tx_hash = result.value();
    EXPECT_FALSE( tx_hash.empty() );
}
```

**TEST-03 — discovery propagation** (uses `GetRegistrationsForMain`):
```cpp
TEST_F( ChildRegistrationIntegrationTest, MainDiscoversChild )
{
    // Use a distinct child address per D-52
    std::string main_address = main_node_->GetAddress();
    SGTransaction::RegistrationMetadata metadata;
    metadata.set_game_id( "discovery_test" );

    auto result = child_node_->RegisterChild( main_address, metadata, 1 );
    ASSERT_TRUE( result.has_value() );

    // Poll for discovery — wait for CRDT/pubsub propagation
    ASSERT_OUTCOME_SUCCESS( auto entries,
        WaitForRegistrations( main_node_, main_address, 1, std::chrono::seconds( 30 ) ) );
    ASSERT_EQ( entries.size(), 1 );
    EXPECT_EQ( entries[0].main_addr, main_address );
    EXPECT_EQ( entries[0].child_addr, child_node_->GetAddress() );
    EXPECT_EQ( entries[0].sequence, 1 );
}
```

**TEST-04 — negative rejection at filter level** (follows `FilterRegistrationRejectsTamperedSignature` from `registration_transaction_test.cpp` lines 465–496 + `FilterRegistrationRejectsBadMainAddress` lines 430–460):

Uses `RegistrationE2ETestAccess` (friend accessor at `registration_transaction_test.cpp` lines 164–181) to inject invalid CRDT elements directly into `FilterRegistration`:
```cpp
// Reuse RegistrationE2ETestAccess from registration_transaction_test.cpp or define locally
class ChildRegTestAccess
{
public:
    static std::optional<std::vector<crdt::pb::Element>> FilterRegistration(
        TransactionManager      &tm,
        const crdt::pb::Element &element )
    {
        return tm.FilterRegistration( element );
    }
};

TEST_F( ChildRegistrationIntegrationTest, InvalidRegistrationRejected )
{
    // Build a tampered registration element
    crdt::pb::Element element;
    element.set_key( "/bc/0/reg/" + child_node_->GetAddress() );
    // ... construct tampered protobuf bytes ...
    element.set_value( tampered_bytes_str );

    // Access the main node's TransactionManager FilterRegistration directly
    auto manager_result = main_node_->GetTransactionManager();
    ASSERT_TRUE( manager_result.has_value() );
    auto &tm = *manager_result.value();

    auto filter_result = ChildRegTestAccess::FilterRegistration( tm, element );
    EXPECT_TRUE( filter_result.has_value() ) << "Invalid registration should be tombstoned";

    // Assert it never appears in discovery
    ASSERT_OUTCOME_SUCCESS( auto entries,
        main_node_->GetRegistrationsForMain( main_node_->GetAddress() ) );
    // The tampered child address should NOT appear in entries
    for ( const auto &e : entries )
    {
        EXPECT_NE( e.child_addr, child_node_->GetAddress() )
            << "Rejected registration should not appear in discovery";
    }
}
```

---

### 8. `SuperGenius/test/src/multiaccount/CMakeLists.txt` — Test Registration

**Analog:** Existing `addtest()` pattern (lines 1–3 of CMakeLists.txt):

```cmake
addtest(multi_account_test
    multi_account_sync.cpp
)

target_include_directories(multi_account_test PRIVATE ${AsyncIOManager_INCLUDE_DIR})

target_link_libraries(multi_account_test
    genius_node_test
    json_secure_storage
)

if(WIN32)
    target_link_options(multi_account_test PUBLIC /WHOLEARCHIVE:$<TARGET_FILE:genius_node_test>)
...
```

**New test entry** — copy the exact same structure. Either:
- **Option A:** Add `child_registration.cpp` to the existing `multi_account_test` target
- **Option B (preferred per D-51):** Create a new target in a new `regtest/CMakeLists.txt` that is `add_subdirectory()`-d from the parent

**If Option B** — create `.planning/phases/05-crdt-persistence-pubsub-integration-test/CMakeLists.txt`:
```cmake
addtest(child_registration_test
    child_registration.cpp
)

target_include_directories(child_registration_test PRIVATE ${AsyncIOManager_INCLUDE_DIR})

target_link_libraries(child_registration_test
    genius_node_test
    json_secure_storage
)

if(WIN32)
    target_link_options(child_registration_test PUBLIC /WHOLEARCHIVE:$<TARGET_FILE:genius_node_test>)
elseif(APPLE)
    target_link_options(child_registration_test PUBLIC -force_load "$<TARGET_FILE:genius_node_test>")
else()
    target_link_options(child_registration_test PUBLIC
        "-Wl,--whole-archive"
        "$<TARGET_FILE:genius_node_test>"
        "-Wl,--no-whole-archive"
    )
endif()
```

**Planner must also add `add_subdirectory(regtest)` to `SuperGenius/test/src/multiaccount/CMakeLists.txt`.**

---

## Shared Patterns

### Error Handling
**Source:** `outcome::result<T>`, `BOOST_OUTCOME_TRY`, `ASSERT_OUTCOME_SUCCESS` / `EXPECT_OUTCOME_TRUE`
**Apply to:** All new/modified TransactionManager methods, GeniusNode wrappers, and integration tests

```cpp
// Production code pattern (TransactionManager.cpp:583-592):
BOOST_OUTCOME_TRY( auto crdt_transaction->Put( std::move( tx_key ), std::move( data_transaction ) ) );
BOOST_OUTCOME_TRY( crdt_transaction->Commit( topicSet ) );

// Test code pattern (registration_transaction_test.cpp:286-287):
ASSERT_TRUE( result.has_value() );
std::string tx_hash = result.value();

// Or with outcome macros (testutil/outcome.hpp:134):
ASSERT_OUTCOME_SUCCESS( auto tx_id, manager->RegisterChild( main_address, metadata, 1 ) );
```

**Include:** `#include "outcome/outcome.hpp"` (already present in TransactionManager.hpp)

### Two-Layer API Convention
**Source:** `GeniusNode.cpp:2258–2298` (TransferFunds + RegisterChild wrappers)
**Apply to:** All new GeniusNode wrappers

```cpp
// Pattern for every GeniusNode wrapper:
outcome::result<ReturnType> GeniusNode::NewMethod( params... )
{
    if ( GetTransactionManagerState() != TransactionManager::State::READY )
    {
        node_logger_->error( "{}: Transaction Manager is not ready", __func__ );
        return outcome::failure( Error::TRANSACTIONS_NOT_READY );
    }
    BOOST_OUTCOME_TRY( auto manager, GetTransactionManager() );
    BOOST_OUTCOME_TRY( auto result, manager->NewMethod( params... ) );
    node_logger_->debug( "{}: new method completed", __func__ );
    return result;
}
```

### CRDT Scan Pattern
**Source:** `TransactionManager.cpp:1646–1676` (QueryTransactions)
**Apply to:** `GetRegistrationsForMain`

Key constants and method signatures:
- `GetBlockChainBase()` → `"/bc-{network_id}/"` (TransactionManager.hpp:300)
- `GetBlockChainBase( network_id )` → same but with explicit network
- `globaldb_m->QueryKeyValues( prefix )` → `outcome::result<std::map<Buffer, Buffer>>`
- `globaldb_m->Get( key )` → `outcome::result<Buffer>` (key implicitly converts from string via HierarchicalKey)
- `globaldb_m->KeyToString( key )` → `outcome::result<std::string>`
- `DeSerializeTransaction( string )` → `outcome::result<std::shared_ptr<GeniusTransaction>>` (accepts `std::string`, also has `Buffer` variant)

### PubSub Listen/Broadcast Pattern
**Source:** `TransactionManager.cpp:371,376` (StartListeningTopics) + `SendTransactionItem` line 1245 (topic merge)
**Apply to:** CID notification handler

```cpp
// Subscribing to own address topic:
globaldb_m->AddListenTopic( account_m->GetAddress() );

// Following a child's channel after discovering via CID notification:
globaldb_m->AddListenTopic( child_addr );

// RegistrationTransaction::GetTopics() already includes main_address_ (line 102 of RegistrationTransaction.hpp)
// so SendTransactionItem's topicSet.merge( transaction->GetTopics() ) at line 1245
// already broadcasts on the main's channel — RIMPL-05 broadcast half is done.
```

### Filter Registration Pattern
**Source:** `TransactionManager.cpp:195–233` (New() filter registration)
**Apply to:** Understanding reg/ filter is already active — no changes needed

```cpp
// Already registered in New() at line 222-233:
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

### Doxygen Documentation Pattern
**Source:** TransactionManager.hpp lines 125–134
**Apply to:** All new method/struct declarations

```cpp
/**
 * @brief Short description of what this does.
 *
 * Longer description if needed.
 *
 * @param[in] param_name Description.
 * @return Description of return value.
 */
```

---

## No Analog Found

Files with no close match in the codebase (planner should use RESEARCH.md patterns or general C++ conventions):

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| (none) | — | — | All new files have strong analogs in the existing codebase |

All new files have exact or strong role-matched analogs. The closest gap is the CID notification handler wiring — whether the handler lives in TransactionManager or GeniusNode is planner discretion (D-49), but the individual patterns (topic subscription, CRDT read, AddListenTopic follow) all have established analogs.

---

## Opportunistic Fixes (Phase 4 Advisory Warnings)

**Source:** 04-REVIEW.md, CONTEXT.md line 103

Two Phase 4 issues touch code modified in Phase 5:

1. **Unchecked `dynamic_pointer_cast` in `SendTransactionItem`** (TransactionManager.cpp line 1217):
   - Current code: `auto reg_tx = std::dynamic_pointer_cast<RegistrationTransaction>( transaction );`
   - Fix: Add a null check after the cast, similar to the pattern in `FilterRegistration` at line 2789–2793

2. **Silent `SerializeByteVector` failure** — registration serialization in the SendTransactionItem path at line 1229 may silently produce empty bytes. Add an explicit check or BOOST_OUTCOME_TRY.

---

## Metadata

**Analog search scope:** `SuperGenius/src/account/`, `SuperGenius/src/crdt/globaldb/`, `SuperGenius/test/src/multiaccount/`, `SuperGenius/test/src/account/`, `SuperGenius/test/testutil/`
**Files scanned:** 14 files (TransactionManager.cpp/hpp, GeniusNode.cpp/hpp, RegistrationTransaction.hpp, globaldb.hpp, pubsub_broadcaster_ext.hpp, hierarchical_key.hpp, rocksdb.hpp, multi_account_sync.cpp, registration_transaction_test.cpp, outcome.hpp, CMakeLists.txt)
**Pattern extraction date:** 2026-07-16
