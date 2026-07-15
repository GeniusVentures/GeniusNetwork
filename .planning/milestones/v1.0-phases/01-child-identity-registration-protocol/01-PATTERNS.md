# Phase 01: Child Identity & Registration Protocol - Pattern Map

**Mapped:** 2026-07-13
**Files analyzed:** 9 new/modified/referenced files
**Analogs found:** 9 / 9

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `SGTransaction.proto` (append) | proto/schema | additive-schema | `SGTransaction.proto:81-87` TransferTx | exact — same file, same pattern |
| `Consensus.proto` (modify EmbeddedTransaction) | proto/dispatch | oneof-dispatch | `Consensus.proto:70-80` EmbeddedTransaction oneof | exact — same message |
| `RegistrationTransaction.hpp` (NEW) | GeniusTransaction subclass | request-response | `MintTransaction.hpp` | exact — same role, no UTXOs, simpler subclass |
| `RegistrationTransaction.cpp` (NEW) | GeniusTransaction subclass impl | request-response | `MintTransaction.cpp` | exact — same role and data flow |
| `TransactionManager.cpp` — RegisterDeserializer (modify) | tx-manager/registry | request-response | `TransactionManager.cpp:1434-1441` | exact — same registration site |
| `TransactionManager.cpp` — DeSerializeEmbeddedTransaction (modify) | tx-manager/dispatch | request-response | `TransactionManager.cpp:1446-1501` switch/case | exact — same dispatch site |
| Child-wallet identity model design doc | design-document | N/A | `GeniusAccount.hpp`, `GeniusNode.hpp` | design-reference |
| Registration protocol design doc | design-document | N/A | `SGTransaction.proto`, `GeniusTransaction.hpp`, `TransactionManager.cpp` | design-reference |
| Registration proto serialization (string fields) | tx/embedded-serialize | request-response | `EscrowTransaction.cpp:74-100` | role-match — has string member fields like RegistrationTx |

## Pattern Assignments

### 1. `SGTransaction.proto` — append `RegistrationMetadata` + `RegistrationTx` (proto, additive-schema)

**Analog:** `SGTransaction.proto:81-87` (TransferTx) + `SGTransaction.proto:120-127` (EscrowTx)

**Core pattern — every tx embeds DAGStruct dag_struct = 1** (lines 81-87):
```protobuf
message TransferTx
{
    DAGStruct dag_struct = 1;//
    bytes token_id = 2; //
    UTXOTxParams utxo_params = 3; //
}
```

**Core pattern — EscrowTx with string field + uint64 non-UTXO fields** (lines 120-127):
```protobuf
message EscrowTx
{
    DAGStruct dag_struct = 1;//
    UTXOTxParams utxo_params = 2; //
    uint64 amount = 3;
    bytes dev_addr = 4; //
    uint64 peers_cut = 5; //
}
```

**Pattern to copy — new messages appended at end of file (after line 136):**
```protobuf
message RegistrationMetadata
{
    string game_id = 1;        // publisher-assigned game identifier
    string publisher_id = 2;   // publisher identity
    string dev_wallet = 3;     // developer payout address (128-hex, no 0x prefix)
    uint64 peers_cut = 4;      // developer's share of processing rewards
}

message RegistrationTx
{
    DAGStruct dag_struct = 1;  // source_addr = child; carries nonce, timestamp, signature
    string main_address = 2;   // registered main wallet public key (128-hex, no 0x prefix)
    uint64 sequence = 3;       // monotonic per-child registration sequence
    RegistrationMetadata metadata = 4;  // optional game/publisher/dev metadata
}
```

**Key rules:**
- All new field numbers (1-4) are fresh within the new message scope — no conflict with existing messages
- `dag_struct = 1` matches ALL existing tx types (TransferTx, MintTx, EscrowTx, etc.)
- Proto3 `string` for addresses (UTF-8, variable-length, like `owner_address` in `UTXOEntryRecord:57`)
- `uint64` for `sequence` and `peers_cut` (consistent with EscrowTx.peers_cut)
- Never modify existing TransferTx, MintTx, EscrowTx, DAGStruct, or UTXOEntryRecord messages

---

### 2. `Consensus.proto` — add `registration = 8` to `EmbeddedTransaction` oneof (proto, oneof-dispatch)

**Analog:** `Consensus.proto:70-80`

**Pattern to copy** (insert after line 78):
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
    SGTransaction.RegistrationTx registration = 8;   // ← NEW, additive only
  }
}
```

**Key rules:**
- Field 8 is verified available (fields 1-7 used: transfer=1, mint_v2=2, mint=3, processing=4, migration=5, escrow=6, escrow_release=7)
- Additive only — never renumber existing arms 1-7
- Proto3 auto-generates `kRegistration` enum value for the switch dispatch

---

### 3. `RegistrationTransaction.hpp` (NEW) — GeniusTransaction subclass header (C++ header, request-response)

**Analog:** `MintTransaction.hpp` (simplest existing subclass — no UTXOs, just scalar + string fields)

**Include guard pattern** (line 7):
```cpp
#ifndef _MINT_TRANSACTION_HPP_
#define _MINT_TRANSACTION_HPP_
```

**Import pattern** (lines 10-14):
```cpp
#include <vector>
#include <cstdint>
#include "account/GeniusTransaction.hpp"
#include "account/TokenID.hpp"
```

**Class declaration pattern** (lines 21-116):
```cpp
class MintTransaction final : public GeniusTransaction
{
public:
    ~MintTransaction() override = default;

    // Deserializer (static)
    static std::shared_ptr<MintTransaction> DeSerializeByteVector( const std::vector<uint8_t> &data );

    // Factory: constructs + fills hash
    static MintTransaction New( uint64_t new_amount, std::string chain_id,
                                TokenID token_id, SGTransaction::DAGStruct dag );

    // Serialization (using declarations + overrides)
    using GeniusTransaction::SerializeByteVector;
    using GeniusTransaction::SerializeToEmbeddedTransaction;
    EmbeddedTransaction SerializeToEmbeddedTransaction( const SGTransaction::DAGStruct &dag ) const override;
    std::vector<uint8_t> SerializeByteVector( const SGTransaction::DAGStruct &dag ) const override;

    // Accessors
    uint64_t GetAmount() const;
    TokenID GetTokenID() const;
    std::string GetChainId() const override;

    std::string GetTransactionSpecificPath() const override
    {
        return GetType();   // returns transaction_type from base ("mint" etc.)
    }

private:
    // Constructor (private — use New() factory)
    MintTransaction( uint64_t new_amount, std::string chain_id, TokenID token_id,
                     SGTransaction::DAGStruct dag );

    // Member variables (trailing underscore per Coding Standards.md)
    uint64_t    amount;
    std::string chain_id;
    TokenID     token_id;

    // Static registration (inline, fires on translation unit load)
    static bool Register()
    {
        RegisterDeserializer( "mint", &MintTransaction::DeSerializeByteVector );
        return true;
    }
    static inline bool registered = Register();
};
```

**RegistrationTx adaptation — what to copy:**
- PascalCase: `RegistrationTransaction.hpp` (follows `MintTransaction.hpp` not `TransferTransaction.hpp`)
- Include guard: `#define _REGISTRATION_TRANSACTION_HPP_` or `#ifndef SGNS_REGISTRATION_TRANSACTION_HPP` per Coding Standards.md
- Constructor chain: `GeniusTransaction( "registration", SetDAGWithType( std::move( dag ), "registration" ) )`
- `GetTransactionSpecificPath()` return `"reg/" + GetHash()` or follow GetType() pattern — agent's discretion (A4, A5)
- Member naming: `main_address_`, `sequence_`, `metadata_` (trailing underscore)
- `[[nodiscard]]` on getters: `GetMainAddress()`, `GetSequence()`, `GetMetadata()`
- Deserializer type string: `"registration"` (consistent with existing convention of lowercase hyphen-free nouns: "transfer", "mint", "process", "migration", "escrow-hold", "escrow-release")

---

### 4. `RegistrationTransaction.cpp` (NEW) — GeniusTransaction subclass implementation (C++ source, request-response)

**Analog:** `MintTransaction.cpp` (lines 1-94)

**Constructor pattern** (lines 11-20):
```cpp
MintTransaction::MintTransaction( uint64_t new_amount, std::string chain_id,
                                  TokenID token_id, SGTransaction::DAGStruct dag ) :
    GeniusTransaction( "mint", SetDAGWithType( std::move( dag ), "mint" ) ),
    amount( new_amount ),
    chain_id( std::move( chain_id ) ),
    token_id( std::move( token_id ) )
{
}
```

**SerializeByteVector pattern** (lines 22-39):
```cpp
std::vector<uint8_t> MintTransaction::SerializeByteVector( const SGTransaction::DAGStruct &dag ) const
{
    SGTransaction::MintTx tx_struct;
    tx_struct.mutable_dag_struct()->CopyFrom( dag );
    tx_struct.set_amount( amount );
    tx_struct.set_chain_id( chain_id );
    tx_struct.set_token_id( token_id.bytes().data(), token_id.size() );

    size_t               size = tx_struct.ByteSizeLong();
    std::vector<uint8_t> serialized_proto( size );

    if ( !tx_struct.SerializeToArray( serialized_proto.data(), serialized_proto.size() ) )
    {
        std::cerr << "Failed to serialize transaction\n";
    }
    return serialized_proto;
}
```

**SerializeToEmbeddedTransaction pattern** (lines 41-52):
```cpp
EmbeddedTransaction MintTransaction::SerializeToEmbeddedTransaction( const SGTransaction::DAGStruct &dag ) const
{
    EmbeddedTransaction embedded;
    SGTransaction::MintTx tx_struct;
    tx_struct.mutable_dag_struct()->CopyFrom( dag );
    tx_struct.set_amount( amount );
    tx_struct.set_chain_id( chain_id );
    tx_struct.set_token_id( token_id.bytes().data(), token_id.size() );

    *embedded.mutable_mint() = tx_struct;
    return embedded;
}
```

**DeSerializeByteVector pattern** (lines 54-68):
```cpp
std::shared_ptr<MintTransaction> MintTransaction::DeSerializeByteVector( const std::vector<uint8_t> &data )
{
    SGTransaction::MintTx tx_struct;
    if ( !tx_struct.ParseFromArray( data.data(), data.size() ) )
    {
        std::cerr << "Failed to parse TransferTx from array\n";
        return nullptr;
    }
    uint64_t    amount  = tx_struct.amount();
    std::string chainid = tx_struct.chain_id();
    TokenID     tokenid = TokenID::FromBytes( tx_struct.token_id().data(), tx_struct.token_id().size() );

    return std::make_shared<MintTransaction>(
        MintTransaction( amount, chainid, tokenid, tx_struct.dag_struct() ) );
}
```

**New() factory pattern** (lines 85-93):
```cpp
MintTransaction MintTransaction::New( uint64_t new_amount, std::string chain_id,
                                      TokenID token_id, SGTransaction::DAGStruct dag )
{
    MintTransaction instance( new_amount, std::move( chain_id ), std::move( token_id ), std::move( dag ) );
    instance.FillHash();
    return instance;
}
```

**RegistrationTx adaptation — what to copy:**
- For `SerializeToEmbeddedTransaction`: call `tx_struct.set_main_address( main_address_ )`, `tx_struct.set_sequence( sequence_ )`, `*tx_struct.mutable_metadata()->CopyFrom( metadata_ )` — then `*embedded.mutable_registration() = tx_struct`
- For `DeSerializeByteVector`: parse `tx_struct.main_address()`, `tx_struct.sequence()`, `tx_struct.metadata()` from the proto
- `ParseFromArray` failure → returns `nullptr` (consistent with all existing subclasses)
- `FillHash()` called inside `New()` factory

---

### 5. EscrowTransaction.cpp — string + uint64 field serialization pattern (C++ source, request-response)

**Analog:** `EscrowTransaction.cpp:40-72, 74-100`

**Why EscrowTx instead of MintTx:** RegistrationTx has `string main_address` and `uint64 sequence` fields — EscrowTx has `string dev_addr` and `uint64 peers_cut`, making it the closest analog for string field proto serialization.

**SerializeByteVector with string field** (lines 60-62):
```cpp
tx_struct.set_amount( amount_ );
tx_struct.set_dev_addr( dev_addr_ );
tx_struct.set_peers_cut( peers_cut_ );
```

**SerializeToEmbeddedTransaction with string field** (lines 95-98):
```cpp
tx_struct.set_amount( amount_ );
tx_struct.set_dev_addr( dev_addr_ );
tx_struct.set_peers_cut( peers_cut_ );
*embedded.mutable_escrow() = tx_struct;
```

**DeSerializeByteVector with string field** (lines 132-136):
```cpp
uint64_t amount    = tx_struct.amount();
uint64_t peers_cut = tx_struct.peers_cut();
return std::make_shared<EscrowTransaction>( EscrowTransaction( UTXOTxParameters{ inputs, outputs },
                                                               amount,
                                                               tx_struct.dev_addr(),
                                                               peers_cut,
                                                               tx_struct.dag_struct() ) );
```

**RegistrationTx adaptation — what to copy:**
- `tx_struct.set_main_address( main_address_ )` — directly mirrors `set_dev_addr( dev_addr_ )`
- `tx_struct.set_sequence( sequence_ )` — directly mirrors `set_peers_cut( peers_cut_ )`
- `tx_struct.mutable_metadata()->CopyFrom( metadata_ )` — for the nested `RegistrationMetadata` sub-message
- For deserialization: `tx_struct.main_address()` (returns `const std::string&`), `tx_struct.sequence()` (returns `uint64`)

---

### 6. `TransactionManager.cpp` — RegisterDeserializer (modify, lines 1434-1441)

**Analog:** `TransactionManager.cpp:1432-1442`

**Pattern to copy — add ONE line:**
```cpp
static const bool registered = []
{
    GeniusTransaction::RegisterDeserializer( "transfer", &TransferTransaction::DeSerializeByteVector );
    GeniusTransaction::RegisterDeserializer( "mint-v2", &MintTransactionV2::DeSerializeByteVector );
    GeniusTransaction::RegisterDeserializer( "mint", &MintTransaction::DeSerializeByteVector );
    GeniusTransaction::RegisterDeserializer( "process", &ProcessingTransaction::DeSerializeByteVector );
    GeniusTransaction::RegisterDeserializer( "migration", &MigrationTransaction::DeSerializeByteVector );
    GeniusTransaction::RegisterDeserializer( "escrow-hold", &EscrowTransaction::DeSerializeByteVector );
    GeniusTransaction::RegisterDeserializer( "escrow-release", &EscrowTransaction::DeSerializeByteVector );
    // NEW — append after escrow-release:
    GeniusTransaction::RegisterDeserializer( "registration", &RegistrationTransaction::DeSerializeByteVector );
    return true;
}();
```

**Key rule:** Type string `"registration"` — consistent with existing naming: lowercase, hyphen-free, noun. The type string in the constructor must match exactly: `GeniusTransaction( "registration", ... )`.

---

### 7. `TransactionManager.cpp` — DeSerializeEmbeddedTransaction switch (modify, lines 1445-1501)

**Analog:** `TransactionManager.cpp:1446-1501`

**Pattern to copy — add case before `TRANSACTION_NOT_SET` default (after line 1496):**
```cpp
case EmbeddedTransaction::kRegistration:
{
    std::string bytes;
    embedded.registration().SerializeToString( &bytes );
    return GeniusTransaction::GetDeSerializers().at( "registration" )(
        std::vector<uint8_t>( bytes.begin(), bytes.end() ) );
}
```

**Key rules:**
- Follows identical pattern to all existing cases (lines 1448-1496)
- Proto3 auto-generates `EmbeddedTransaction::kRegistration` when you add `registration = 8` to the oneof
- `embedded.registration()` returns `const SGTransaction::RegistrationTx&` (auto-generated accessor)
- The switch `default: case TRANSACTION_NOT_SET: return std::errc::invalid_argument` already handles old nodes gracefully — no RegistrationTx → falls through

---

### 8. `GeniusAccount.hpp` — identity/keypair/nonce patterns (C++ header, identity)

**Analog:** `GeniusAccount.hpp`

No code changes needed for Phase 1 (D-01, D-02, D-03). This file is a **design-document reference**. The design doc must document how RegistrationTx uses:

**Key identity methods (for design doc reference):**
```cpp
// Key generation — child created via existing factory (line 83-85)
static std::shared_ptr<GeniusAccount> New( TokenID token_id,
    const boost::filesystem::path &base_path, bool full_node = false );

// Address validation for main_address field (line 152)
static bool IsValidPublicKey( std::string_view key ) noexcept;  // 128-hex, no prefix

// Address normalization (line 144)
static std::string_view NormalizeAddress( std::string_view address ) noexcept;  // strips "0x"

// Nonce machinery — child account has independent nonce (lines 279-291)
uint64_t GetProposedNonce() const;    // next available nonce without reserving
uint64_t ReserveNextNonce();          // reserve + return next nonce
void ReleaseNonce( uint64_t nonce );  // release a reserved nonce

// Signing — child signs its own RegistrationTx (lines 216, 256)
std::vector<uint8_t> Sign( const std::vector<uint8_t> &data ) const;       // GeniusAccount::Sign
std::vector<uint8_t> MakeSignature( GeniusAccount &account );              // GeniusTransaction::MakeSignature

// Verification (line 207)
static bool VerifySignature( const std::string &address, std::string_view sig,
                             const std::vector<uint8_t> &data );

// Ethereum keypair member (line 391)
std::shared_ptr<ethereum::EthereumKeyGenerator> eth_keypair_;
```

**What the design doc must state:**
- `GeniusAccount.hpp` is NOT modified — child identity is emergent (D-01)
- `main_address` is validated via `GeniusAccount::IsValidPublicKey()` — 128-hex, no "0x" prefix
- Child nonce (`GetProposedNonce`/`ReserveNextNonce`) is naturally independent — separate account = separate nonce counter (D-03)
- Child signs RegistrationTx via `tx.MakeSignature( *child_account )` — same flow as all existing tx types

---

### 9. `GeniusNode.hpp` — child creation patterns (C++ header, factory)

**Analog:** `GeniusNode.hpp:88-127`

**AccountSource variant (lines 88-107):**
```cpp
struct NewAccount {};                                    // Generate a new identity
struct FromPrivateKey { std::string eth_private_key; }; // Restore from private key
struct FromMnemonic { std::string mnemonic; };          // Restore from BIP39 mnemonic
struct FromPublicKey { std::string public_address; };   // Load from storage (read-only)

using AccountSource = std::variant<NewAccount, FromPrivateKey, FromMnemonic, FromPublicKey>;
```

**Canonical node factory (lines 126):**
```cpp
static std::shared_ptr<GeniusNode> New( const DevConfig_st &dev_config, AccountSource source );
```

**What the design doc must state:**
- Child wallet created via `GeniusNode::New( dev_config, AccountSource{NewAccount{}} )` — identical to any other wallet (D-01, IDENT-03)
- No `AccountSource` variant changes needed — `NewAccount` generates independent secp256k1 keypair via `EthereumKeyGenerator` internally
- `GeniusNode.hpp` stays untouched for Phase 1

---

## Shared Patterns

### Tx Lifecycle (create → sign → submit)

**Source:** `MintTransaction.cpp:85-93` (`New()` factory + caller workflow)
**Apply to:** `RegistrationTransaction.cpp` design

```cpp
// 1. Create — child obtains main_address from connect flow (D-10, transport-agnostic)
auto dag = CreateDAGStruct( child_address, nonce, prev_hash );
// 2. Build via factory — FillHash() called inside New()
auto tx = RegistrationTransaction::New( main_address, sequence, metadata, std::move( dag ) );
// 3. Sign — child signs with its own private key (D-04)
auto sig = tx.MakeSignature( *child_account );
// 4. Submit through existing TransactionManager path (D-06)
```

### Proto Additive Evolution (backward-compatibility)

**Source:** `SGTransaction.proto` + `Consensus.proto`
**Apply to:** Both proto modifications

| Scenario | Compatible? | Why |
|----------|-------------|-----|
| Old node receives new RegistrationTx | ✓ | proto3 ignores unknown message types in oneof; falls through switch to TRANSACTION_NOT_SET |
| New node receives old message (no RegistrationTx) | ✓ | Missing oneof arm → TRANSACTION_NOT_SET case; no crash |
| Old wallet parses new RegistrationMetadata | ✓ | Unknown fields ignored by proto3 |
| New node reads old CRDT state (no registration records) | ✓ | No registration → no child; emergent identity works correctly |
| Renumber DAGStruct fields inside RegistrationTx | ✗ | DAGStruct is shared — changing it breaks all tx types |
| Change existing TransferTx/MintTx field numbers | ✗ | Breaks all deployed nodes |

### Error Handling Conventions

**Source:** `TransferTransaction.cpp`, `EscrowTransaction.cpp`
**Apply to:** `RegistrationTransaction.cpp`

- `ParseFromArray` failure → `std::cerr` + return `nullptr` (not an exception)
- Serialization failure → `std::cerr` + continue (non-fatal, logged)
- No `outcome::result` wrapping in serialization (returns bare vector/shared_ptr)
- No `try/catch` blocks in serialization path — protobuf APIs don't throw by default

### Include Convention

**Source:** All existing tx subclasses
**Apply to:** `RegistrationTransaction.hpp/.cpp`

```cpp
#include "account/GeniusTransaction.hpp"        // base class
#include "account/proto/SGTransaction.pb.h"     // proto messages (RegistrationTx, RegistrationMetadata, DAGStruct)
#include "base/blob.hpp"                         // if using Hash256 (for hashing, typically not needed for RegistrationTx)
```

### File Naming & Placement

**Source:** Existing `account/` directory structure
**Apply to:** New RegistrationTransaction files

```
SuperGenius/src/account/
├── RegistrationTransaction.hpp    # PascalCase header
├── RegistrationTransaction.cpp    # PascalCase source
```

---

## No Analog Found

None — every pattern needed for Phase 1 has an exact or role-match analog in the existing codebase. The design documents map child-wallet concepts onto existing SuperGenius primitives that are all battle-tested in the TransferTx/EscrowTx/MintTx paths.

---

## Metadata

**Analog search scope:** `SuperGenius/src/account/`, `SuperGenius/src/blockchain/impl/proto/`
**Files scanned:** 9 (6 read fully, 2 read partially, 1 grepped)
**Pattern extraction date:** 2026-07-13
**Confidence:** HIGH — all analogs verified by reading actual source; proto field numbers audited
