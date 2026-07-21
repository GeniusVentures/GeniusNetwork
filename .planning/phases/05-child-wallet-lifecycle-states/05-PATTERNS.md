# Phase 5: Child Wallet Lifecycle States - Pattern Map

**Mapped:** 2026-07-21
**Files analyzed:** 6 (2 proto, 2 TransactionManager, 2 GeniusNode, plus 1 new tx-class pair)
**Analogs found:** 6 / 6 (all files have a strong same-repo analog; this is additive work on existing files, not new files, except the new `RevokeTransaction` class which mirrors `RegistrationTransaction`)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `SuperGenius/src/account/proto/SGTransaction.proto` (add `detach_flag`/`supersedes_sequence` to `RegistrationTx`; add `RevokeTx` message) | model/schema | CRUD (append-only proto evolution) | same file, `RegistrationTx` (146-152) / `EscrowReleaseTx` (129-136) | exact |
| `SuperGenius/src/blockchain/impl/proto/Consensus.proto` (add `revoke = 9` oneof arm) | model/schema | CRUD | same file, `EmbeddedTransaction` oneof (70-81) | exact |
| `SuperGenius/src/account/RevokeTransaction.hpp/.cpp` (new class) | model | transform (tx (de)serialization) | `SuperGenius/src/account/RegistrationTransaction.hpp/.cpp` | exact |
| `SuperGenius/src/account/TransactionManager.cpp` — `FilterRegistration` gate 3b (`supersedes_sequence`) | middleware (CRDT element filter) | event-driven | same function, gate (d) sequence-monotonicity (`TransactionManager.cpp:3025-3054`) | exact |
| `SuperGenius/src/account/TransactionManager.cpp` — `CheckParentChildAuthority` new `"revoke"` branch | middleware (consensus gate) | request-response | same function's existing `"transfer"` branch (`TransactionManager.cpp:4255-4287`) | exact |
| `SuperGenius/src/account/TransactionManager.cpp/.hpp` — `DetachChild`/`RevokeChild`/`ReplaceMain` methods | service | request-response (enqueue tx) | `RecoverFromChild` (`TransactionManager.cpp:594-649`) for `RevokeChild`; `RegisterChild` (`TransactionManager.cpp:651-698`) for `DetachChild`/`ReplaceMain` | exact |
| `SuperGenius/src/account/GeniusNode.cpp/.hpp` — `DetachChild`/`RevokeChild`/`ReplaceMain` wrappers | service (thin wrapper) | request-response | `GeniusNode::RecoverFromChild` (`GeniusNode.cpp:2285-2332`) / `GeniusNode::RegisterChild` (`GeniusNode.cpp:2334-2361`) | exact |
| `transaction_parsers` dispatch-table entry for `"revoke"` | config (static map) | CRUD | existing `"registration"` entry (`TransactionManager.cpp:118-120`) | exact |

## Pattern Assignments

### `SuperGenius/src/account/proto/SGTransaction.proto` — `RegistrationTx` + new `RevokeTx`

**Analog:** same file, `RegistrationTx` (lines 146-152) and `EscrowReleaseTx` (lines 129-136) as the "message with dag_struct=1 + payload fields" template.

**Current shape** (lines 146-152):
```protobuf
message RegistrationTx
{
    DAGStruct dag_struct = 1;
    bytes main_address = 2;
    uint64 sequence = 3;
    RegistrationMetadata metadata = 4;
}
```

**Additive change needed** (append only — fields 1-4 untouched):
```protobuf
message RegistrationTx
{
    DAGStruct dag_struct = 1;
    bytes main_address = 2;
    uint64 sequence = 3;
    RegistrationMetadata metadata = 4;
    bool detach_flag = 5;
    uint64 supersedes_sequence = 6;
}

message RevokeTx
{
    DAGStruct dag_struct = 1;
    bytes child_address = 2;
    uint64 registration_sequence = 3;
}
```
Per CONTEXT.md, `detach_flag`/`supersedes_sequence` and `RevokeTx`'s 3 fields are confirmed free — use exactly these numbers. `EscrowReleaseTx` (129-136) is the template for "how a new sibling message with a `DAGStruct dag_struct = 1` leading field is shaped" if `RevokeTx` needs to be modeled as an independent top-level message (it does).

---

### `SuperGenius/src/blockchain/impl/proto/Consensus.proto` — `EmbeddedTransaction` oneof

**Analog:** same file, lines 70-81.

**Current:**
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
    SGTransaction.RegistrationTx registration = 8;
  }
}
```
**Change:** append `SGTransaction.RevokeTx revoke = 9;` — arm 9 confirmed free, arms 1-8 untouched.

---

### `SuperGenius/src/account/RevokeTransaction.hpp/.cpp` (new class)

**Analog:** `SuperGenius/src/account/RegistrationTransaction.hpp` (full file, 135 lines) — this is the closest existing "small standalone GeniusTransaction subclass with 2-3 scalar payload fields, no UTXO logic" template.

**Structure to mirror** (from `RegistrationTransaction.hpp`):
- Static `New(...)` factory (line 34) building the DAGStruct-tagged transaction and computing hash.
- `SerializeByteVector` / `SerializeToEmbeddedTransaction` overrides (lines 44-48).
- `DeSerializeByteVector` static (line 55).
- Plain getters returning private fields by const ref (lines 61-82, e.g. `GetMainAddress()`/`GetSequence()`/`GetMetadata()`) — for `RevokeTransaction`: `GetChildAddress()`, `GetRegistrationSequence()`.
- `GetTransactionSpecificPath()` override returning `GetType()` (lines 88-91).
- `GetTopics()` override (declared line 97) — for Revoke, topics should include the target child's address so the revoke is discoverable/routable the same way registration is (per `RegistrationTransaction.cpp`'s topic derivation — read that .cpp before implementing).
- Private constructor + `main_address_`/`sequence_`/`metadata_` fields (lines 107-114) → analogous `child_address_`/`registration_sequence_` fields for Revoke.
- Self-registering static `Register()`/`registered` idiom (lines 120-129) calling `RegisterDeserializer( "revoke", &RevokeTransaction::DeSerializeByteVector )` — this is also the mechanism that makes `GeniusTransaction::GetDeSerializers().at("revoke")` work at `TransactionManager.cpp:1646`/`1707` style call sites.

**GetType() convention:** `RegistrationTransaction` uses type string `"registration"` (matches proto oneof field name `registration`); `RevokeTransaction`'s `GetType()` must return `"revoke"` to match the new oneof arm name and all the string-keyed dispatch (`transaction_parsers`, `RegisterDeserializer`, `CheckParentChildAuthority` branch, `FilterRegistration`'s `new_tx->GetType() != "registration"` guard pattern).

---

### `TransactionManager::FilterRegistration` — new gate 3b (`supersedes_sequence`)

**Analog:** same function, gate (d) sequence-monotonicity, `TransactionManager.cpp:3025-3054`.

**Full current function** (`TransactionManager.cpp:2986-3065`):
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
        if ( maybe_new_tx.has_error() ) { ... break; }
        auto new_tx = maybe_new_tx.value();
        if ( new_tx->GetType() != "registration" ) { break; }
        auto reg_tx = std::dynamic_pointer_cast<RegistrationTransaction>( new_tx );
        if ( !reg_tx ) { break; }

        // Gate (b): invalid child signature
        if ( !CheckTransactionAuthorization( *reg_tx ) ) { ... break; }

        // Gate (c): malformed main_address (not 128 hex chars)
        if ( reg_tx->GetMainAddress().size() != 128 ) { ... break; }

        // Gate (d): sequence monotonicity
        if ( reg_tx->GetSequence() == 0 ) { ... break; }
        std::string reg_key = GetBlockChainBase() + "reg/" + reg_tx->GetSrcAddress();
        auto existing_data = globaldb_m->Get( reg_key );
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
                        m_logger->error( "Non-monotonic sequence in registration {}: incoming={}, stored={}",
                                         element.key(), reg_tx->GetSequence(), existing_reg->GetSequence() );
                        break;
                    }
                }
            }
        }

        should_delete = false;
    } while ( 0 );

    if ( should_delete )
    {
        maybe_tombstones = std::vector<crdt::pb::Element>{};
    }
    return maybe_tombstones;
}
```

**New gate 3b insertion point:** immediately after gate (d)'s existing-record lookup (i.e., reuse the same `existing_data`/`existing_reg` already fetched for monotonicity — do not re-fetch), add: when `reg_tx` carries `detach_flag == true` OR a changed `main_address` (Replace-Main) — i.e. any "lifecycle-change" `RegistrationTx` — require `reg_tx->GetSupersedesSequence() == existing_reg->GetSequence()` if an existing record is present, else reject (a lifecycle-change tx with no prior record to supersede is malformed). Follow the exact same `do { ... break; }` gate style, same `m_logger->error(...)` format string convention (`"<Condition> in registration {}: incoming={}, stored={}"`), and set `should_delete = true` (default) on any break.

---

### `TransactionManager::CheckParentChildAuthority` — new `"revoke"` branch

**Analog:** same function's existing `"transfer"` branch, `TransactionManager.cpp:4255-4287`.

**Full current function:**
```cpp
bool TransactionManager::CheckParentChildAuthority( const GeniusTransaction &tx ) const
{
    m_logger->debug( "{}: Checking parent-child authority tx={}", __func__, tx.GetHash() );
    if ( tx.GetType() != "transfer" )
    {
        m_logger->debug( "{}: Parent-child authority ok tx={}", __func__, tx.GetHash() );
        return true;
    }
    auto certified_main = blockchain_->CheckCertifiedParent( tx.GetSrcAddress() );
    if ( !certified_main.has_value() )
    {
        m_logger->debug( "{}: Parent-child authority ok tx={}", __func__, tx.GetHash() );
        return true;
    }
    if ( tx.CheckSignature() )
    {
        m_logger->debug( "{}: Parent-child authority ok tx={}", __func__, tx.GetHash() );
        return true;
    }
    auto params = tx.GetUTXOParametersOpt();
    if ( !params.has_value() || params->second.empty() )
    {
        m_logger->error( "{}: Parent-child authority failed tx={}", __func__, tx.GetHash() );
        return false;
    }
    if ( params->second.front().dest_address == *certified_main )
    {
        m_logger->debug( "{}: Parent-child authority ok tx={}", __func__, tx.GetHash() );
        return true;
    }
    m_logger->error( "{}: Parent-child authority failed tx={}", __func__, tx.GetHash() );
    return false;
}
```

**Change shape (per CONTEXT.md discretion note):** the `tx.GetType() != "transfer"` early-return-true must become a dispatch: keep the transfer branch as-is, add a sibling `if ( tx.GetType() == "revoke" ) { ... }` branch, and fall through to `return true` only for tx types that are neither. New branch logic (per CONTEXT.md's explicit spec — do NOT touch `CheckTransactionAuthorization`/signature verification, ordinary sig-check already covers Revoke since main is tx's own signer):
```cpp
if ( tx.GetType() == "revoke" )
{
    auto revoke_tx = dynamic_cast<const RevokeTransaction *>( &tx );
    if ( !revoke_tx )
    {
        m_logger->error( "{}: Parent-child authority failed tx={}", __func__, tx.GetHash() );
        return false;
    }
    std::string reg_key       = GetBlockChainBase() + "reg/" + revoke_tx->GetChildAddress();
    auto        existing_data = globaldb_m->Get( reg_key );
    if ( !existing_data.has_value() )
    {
        m_logger->error( "{}: Parent-child authority failed tx={}", __func__, tx.GetHash() );
        return false;
    }
    auto maybe_existing_tx = DeSerializeTransaction( existing_data.value() );
    if ( maybe_existing_tx.has_error() || maybe_existing_tx.value()->GetType() != "registration" )
    {
        m_logger->error( "{}: Parent-child authority failed tx={}", __func__, tx.GetHash() );
        return false;
    }
    auto existing_reg = std::dynamic_pointer_cast<RegistrationTransaction>( maybe_existing_tx.value() );
    if ( !existing_reg || existing_reg->GetDetachFlag() ||
         existing_reg->GetMainAddress() != tx.GetSrcAddress() )
    {
        m_logger->error( "{}: Parent-child authority failed tx={}", __func__, tx.GetHash() );
        return false;
    }
    m_logger->debug( "{}: Parent-child authority ok tx={}", __func__, tx.GetHash() );
    return true;
}
```
This mirrors the existing `maybe_tx.has_error() || maybe_tx.value()->GetType() != "registration"` idiom already used elsewhere in this file (`TransactionManager.cpp:3408`), and reuses the exact `reg_key`/`globaldb_m->Get`/`DeSerializeTransaction` triad already used three times in this file (`FilterRegistration` gate d, `RegisterChild` overload, `RegElementCallback`) — this is the file's established "look up a `reg/` record" idiom.

---

### `TransactionManager::DetachChild` / `RevokeChild` / `ReplaceMain` — new methods

**Analog for `RevokeChild`:** `RecoverFromChild` (`TransactionManager.cpp:594-649`) — main-initiated action targeting a child, two-layer method, `State::READY` guard, builds tx, signs with `account_m`, enqueues.

**Analog for `DetachChild`/`ReplaceMain`:** `RegisterChild` (both overloads, `TransactionManager.cpp:651-698`) — child-initiated `RegistrationTx`-family constructor + auto-sequence-derivation overload pattern.

**Core pattern to copy (`RecoverFromChild`, full body):**
```cpp
outcome::result<std::string> TransactionManager::RecoverFromChild( std::string child_address,
                                                                   uint64_t    amount,
                                                                   TokenID     token_id )
{
    if ( GetState() != State::READY )
    {
        return outcome::failure( boost::system::error_code{} );
    }
    // ... build inputs/outputs specific to transfer ...
    auto recover_transaction = std::make_shared<TransferTransaction>(
        TransferTransaction::New( inputs, outputs, FillDAGStructForAddress( child_address ) ) );
    recover_transaction->MakeSignature( *account_m );
    account_m->GetUTXOManager().ReserveUTXOs( inputs, recover_transaction->GetHash() );
    EnqueueTransaction( std::make_pair( recover_transaction, std::nullopt ) );
    return recover_transaction->GetHash();
}
```

**`RevokeChild` shape (adapt from above, no UTXO involvement, uses `FillDAGStructForAddress` scoped to *this account* since main is the signer/src, not the child — verify against `FillDAGStructForAddress`'s doc comment at TransactionManager.hpp:391-395 which says it's for when tx's declared src is the child; Revoke's src is the main itself, so likely `FillDAGStruct()` — the plain, no-arg variant used by `RegisterChild` — is correct here, not `FillDAGStructForAddress`):**
```cpp
outcome::result<std::string> TransactionManager::RevokeChild( std::string child_address,
                                                               uint64_t    registration_sequence )
{
    if ( GetState() != State::READY )
    {
        return outcome::failure( boost::system::error_code{} );
    }
    auto tx = std::make_shared<RevokeTransaction>(
        RevokeTransaction::New( std::move( child_address ), registration_sequence, FillDAGStruct() ) );
    tx->MakeSignature( *account_m );
    EnqueueTransaction( std::make_pair( tx, std::nullopt ) );
    return tx->GetHash();
}
```

**`RegisterChild` two-overload pattern to copy for `DetachChild`/`ReplaceMain`** (explicit-sequence + auto-derive-sequence overload, full text):
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

outcome::result<std::string> TransactionManager::RegisterChild(
    std::string                         main_address,
    SGTransaction::RegistrationMetadata metadata )
{
    if ( GetState() != State::READY )
    {
        return outcome::failure( boost::system::error_code{} );
    }
    uint64_t    sequence = 1;
    std::string reg_key  = GetBlockChainBase() + "reg/" + account_m->GetAddress();
    auto        existing_data = globaldb_m->Get( reg_key );
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
`DetachChild(main_address="", metadata, sequence, supersedes_sequence)` and `ReplaceMain(new_main_address, metadata, sequence, supersedes_sequence)` should extend `RegistrationTransaction::New(...)`'s signature to also accept `detach_flag` + `supersedes_sequence` (both new proto fields), and both new methods should mirror this exact auto-sequence-derivation overload for caller convenience, reusing the identical `reg_key`/`globaldb_m->Get`/cast idiom shown above — this is the file's single most-repeated idiom (appears 3+ times already) and should be copied verbatim rather than reinvented.

---

### `SuperGenius/src/account/TransactionManager.hpp` — declarations

**Analog placement:** `RecoverFromChild` declared inline before `RegisterChild` overloads, doc-commented with `@param`/`@return` Doxygen blocks (grep hit at `TransactionManager.hpp:141-178`). New `DetachChild`/`RevokeChild`/`ReplaceMain` declarations should sit adjacent to these three existing declarations, same Doxygen style, referencing the D-numbers relevant to Phase 5 in the brief (mirroring how the `RegisterChild` doc comments cite "D-42" and `RecoverFromChild`'s doc/FillDAGStructForAddress comment cites "D-60").

`FilterRegistration`'s doc comment (`TransactionManager.hpp:675-685`) already has a "Phase 4: ... Phase 5 adds: (d) sequence monotonicity" trailing note — extend this same comment with a "Phase 5 also adds: (e) supersedes_sequence fork-prevention gate" line rather than replacing it, matching the incremental-annotation convention already established there.

---

### `SuperGenius/src/account/GeniusNode.cpp/.hpp` — `DetachChild`/`RevokeChild`/`ReplaceMain` wrappers

**Analog:** `GeniusNode::RecoverFromChild` (two overloads: fire-and-forget `TransactionManager` call + polling/timeout wrapper, `GeniusNode.cpp:2285-2332`) and `GeniusNode::RegisterChild` (two overloads mirroring the manager's, `GeniusNode.cpp:2334-2361`).

**Pattern to copy verbatim (state-check → delegate → log), e.g. `RegisterChild` wrapper:**
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
`GeniusNode::DetachChild`/`ReplaceMain` should follow this exact shape (thin delegation, no business logic duplicated at this layer). `GeniusNode::RevokeChild` should follow `RecoverFromChild`'s shape instead, including its `WaitForFinalized`-based `(..., std::chrono::milliseconds timeout)` overload (`GeniusNode.cpp:2285-2305`) if a synchronous/confirmed-wait variant is desired — CONTEXT.md doesn't mandate this explicitly, but it's the established sibling-overload convention for main-initiated actions on children (`RecoverFromChild` has it, `RegisterChild` does not — because Registration is child-initiated/self-referential, Revoke and Recover are both main-acting-on-child).

Declarations for these three live in `GeniusNode.hpp` near lines 141-178 (per grep), same Doxygen block convention (`@param[in]`, `@return`).

---

### `transaction_parsers` dispatch-table entry for `"revoke"`

**Analog:** existing `"registration"` entry, `TransactionManager.cpp:107-120` (full static map):
```cpp
const std::unordered_map<
    std::string,
    std::pair<TransactionManager::TransactionParserFn, TransactionManager::TransactionParserFn>>
    TransactionManager::transaction_parsers = {
        { "transfer",
          { &TransactionManager::ParseTransferTransaction, &TransactionManager::RevertTransferTransaction } },
        { "mint", { &TransactionManager::ParseMintTransaction, &TransactionManager::RevertMintTransaction } },
        { "mint-v2", { &TransactionManager::ParseMintTransaction, &TransactionManager::RevertMintTransaction } },
        { "migration", { &TransactionManager::ParseMintTransaction, &TransactionManager::RevertMintTransaction } },
        { "escrow-hold",
          { &TransactionManager::ParseEscrowTransaction, &TransactionManager::RevertEscrowTransaction } },
        { "registration",
          { &TransactionManager::ParseRegistrationTransaction,
            &TransactionManager::RevertRegistrationTransaction } } };
```
**CRITICAL per CONTEXT.md D-65-adjacent warning:** add `{ "revoke", { &TransactionManager::ParseRevokeTransaction, &TransactionManager::RevertRevokeTransaction } }` here from day one. Phase 3 previously discovered a near-miss bug where `"registration"` was missing from this table, causing `CheckTransactionWellFormed` (`TransactionManager.cpp:4224-4228`, which does `transaction_parsers.find(tx.GetType()) == transaction_parsers.end()` → reject "Unknown tx type") to reject registration txs before `CheckParentChildAuthority` ever ran. New `ParseRevokeTransaction`/`RevertRevokeTransaction` private methods must be added mirroring `ParseRegistrationTransaction`/`RevertRegistrationTransaction`'s signatures (grep those two functions' bodies before implementing — not excerpted here as they were not in the primary read range, but the analog pairing is confirmed via the `transaction_parsers` table structure itself).

Also required: `RegisterDeserializer( "revoke", &RevokeTransaction::DeSerializeByteVector )` inside `RevokeTransaction`'s self-registering `Register()` static (mirrors `RegistrationTransaction.hpp:120-124`), and the same registration idiom used at `TransactionManager.cpp:1646` (`GeniusTransaction::RegisterDeserializer( "registration", &RegistrationTransaction::DeSerializeByteVector );`) if a second registration site exists there too — check both registration points before assuming the class's own static suffices.

## Shared Patterns

### "Look up a `reg/{addr}` record" idiom
**Source:** `TransactionManager.cpp:3032-3054` (`FilterRegistration` gate d), `TransactionManager.cpp:678-695` (`RegisterChild` auto-sequence overload), `TransactionManager.cpp:3408` (compact one-liner variant).
**Apply to:** the new `supersedes_sequence` gate in `FilterRegistration`, the new `"revoke"` branch in `CheckParentChildAuthority`, and any `DetachChild`/`ReplaceMain` auto-sequence-derivation overloads.
```cpp
std::string reg_key = GetBlockChainBase() + "reg/" + <address>;
auto existing_data = globaldb_m->Get( reg_key );
if ( existing_data.has_value() )
{
    auto maybe_existing_tx = DeSerializeTransaction( existing_data.value() );
    if ( !maybe_existing_tx.has_error() )
    {
        auto existing_tx = maybe_existing_tx.value();
        if ( existing_tx->GetType() == "registration" )
        {
            auto existing_reg = std::dynamic_pointer_cast<RegistrationTransaction>( existing_tx );
            // ... use existing_reg->GetSequence() / GetMainAddress() / (new) GetDetachFlag() ...
        }
    }
}
```

### Two-layer method convention (`TransactionManager::X` + `GeniusNode::X`)
**Source:** `RecoverFromChild` (`TransactionManager.cpp:594-649` + `GeniusNode.cpp:2285-2332`), `RegisterChild` (`TransactionManager.cpp:651-698` + `GeniusNode.cpp:2334-2361`).
**Apply to:** `DetachChild`, `RevokeChild`, `ReplaceMain` in both files. Manager layer: `State::READY` guard → build/sign tx → `EnqueueTransaction`. Node layer: `GetTransactionManagerState() != State::READY` guard with `Error::TRANSACTIONS_NOT_READY` → `BOOST_OUTCOME_TRY` delegate to manager → `node_logger_->debug` log → return tx hash (or the `RecoverFromChild`-style `(tx_id, duration)` pair if a wait-for-finalized overload is added for `RevokeChild`).

### Gate-list / `do { ... break; }` style in CRDT element filters
**Source:** `FilterRegistration` (`TransactionManager.cpp:2986-3065`).
**Apply to:** the new gate 3b. Each gate is one `if (...) { m_logger->error(...); break; }` inside a `do { ... } while(0)`, with `should_delete` defaulting `true` and only flipped to `false` once every gate passes.

### Consensus-gate dispatch-by-type style in `CheckParentChildAuthority`/`ValidateTransactionForConsensus`
**Source:** `CheckParentChildAuthority` (`TransactionManager.cpp:4255-4287`), called from `ValidateTransactionForConsensus` (`TransactionManager.cpp:4156-4164`) between `CheckTransactionAuthorization` and `CheckTransactionTimestamp`.
**Apply to:** the new `"revoke"` branch — same `m_logger->debug/error( "{}: Parent-child authority ok/failed tx={}", __func__, tx.GetHash() )` log-message convention, same early-return-true default for unrelated tx types.

### Self-registering transaction-class idiom
**Source:** `RegistrationTransaction.hpp:117-129`.
**Apply to:** new `RevokeTransaction` class — static `Register()` calling `RegisterDeserializer("revoke", &RevokeTransaction::DeSerializeByteVector)`, invoked via `static inline bool registered = Register();`.

## No Analog Found

None. Every file/change in this phase is either an additive modification to an existing file (proto messages, `TransactionManager.cpp`/`.hpp`, `GeniusNode.cpp`/`.hpp`) or a new class (`RevokeTransaction`) with a near-identical existing sibling (`RegistrationTransaction`) to mirror field-for-field.

## Metadata

**Analog search scope:** `SuperGenius/src/account/`, `SuperGenius/src/blockchain/impl/proto/`
**Files scanned:** `SGTransaction.proto`, `Consensus.proto`, `TransactionManager.cpp`, `TransactionManager.hpp`, `RegistrationTransaction.hpp`, `GeniusNode.cpp`
**Pattern extraction date:** 2026-07-21
