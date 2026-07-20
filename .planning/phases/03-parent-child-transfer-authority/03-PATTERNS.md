# Phase 3: Parent-Child Transfer Authority - Pattern Map

**Mapped:** 2026-07-20
**Files analyzed:** 7 (all modifications to existing files; no new files)
**Analogs found:** 7 / 7 (all within the same files being modified — this phase extends existing functions rather than creating new file types)

## File Classification

| File to Modify | Role | Data Flow | Closest Analog (same-file, adjacent function) | Match Quality |
|---|---|---|---|---|
| `SuperGenius/src/account/TransactionManager.cpp` — new `CheckParentChildAuthority` gate | service (consensus gate) | request-response (validation) | `CheckTransactionAuthorization` (same file, lines 4066-4076) | exact (same gate-list pattern) |
| `SuperGenius/src/account/TransactionManager.cpp` — extend `CheckTransactionAuthorization` | service (consensus gate) | request-response | itself, lines 4066-4076 (extend in place) | exact |
| `SuperGenius/src/account/TransactionManager.cpp` — new `RecoverFromChild` | service (tx construction, CRUD-create) | request-response | `TransferFunds` (lines 566-589) | exact (two-layer convention) |
| `SuperGenius/src/account/TransactionManager.hpp` — declarations | model/interface | n/a | existing `TransferFunds`/`CheckTransactionAuthorization` declarations | exact |
| `SuperGenius/src/account/GeniusInputValidator.cpp` — extend per-input signature check | middleware (validation) | request-response | `delegated_escrow_spend` exception block (lines 421-432) — precedent for *shape only*, not the mechanism | role-match (shape precedent, different mismatch direction) |
| `SuperGenius/src/account/GeniusTransaction.cpp`/`.hpp` — new `CheckSignatureAgainst(address)` | utility (crypto verification) | transform | `CheckSignature()` (lines 72-81, refactor target) | exact |
| `SuperGenius/src/blockchain/Blockchain.hpp`/`.cpp` — new `CheckCertifiedParent(child_addr)` | service (CRDT lookup) | CRUD (read) | `CheckCertificate(subject_hash)` (`Blockchain.hpp:252`) + reg/ key-read patterns at `TransactionManager.cpp:618-619`, `:2873-2874` | role-match |
| `SuperGenius/src/account/GeniusNode.cpp`/`.hpp` — new `RecoverFromChild` (two overloads) | controller (thin wrapper) | request-response | `TransferFunds` two-overload pair (lines 2237-2256, 2258-2283) | exact |
| `SuperGenius/test/src/account/registration_transaction_test.cpp` — extend with REGR-01/02/03 + CONS-01/02 tests | test | request-response (E2E) | `RegistrationTransactionE2ETest` fixture (lines 200-254) | exact (extend in place per D-65) |

## Pattern Assignments

### `TransactionManager::CheckParentChildAuthority` (new gate, service/request-response)

**Analog:** `TransactionManager::CheckTransactionAuthorization`, `TransactionManager.cpp:4066-4076` (verified current):
```cpp
bool TransactionManager::CheckTransactionAuthorization( const GeniusTransaction &tx ) const
{
    m_logger->debug( "{}: Checking authorization tx={}", __func__, tx.GetHash() );
    if ( tx.CheckSignature() || tx.CheckDAGSignatureLegacy() )
    {
        m_logger->debug( "{}: Authorization ok tx={}", __func__, tx.GetHash() );
        return true;
    }
    m_logger->error( "{}: Authorization failed tx={}", __func__, tx.GetHash() );
    return false;
}
```
**Pattern to copy:** private `const` bool-returning method, `m_logger->debug` on entry, `m_logger->error` on failure only — matches every gate's logging shape. `CheckParentChildAuthority` must follow this exact log-message style (`"{}: <verb> tx={}"`).

**Core logic (from RESEARCH.md, HIGH confidence on the "what's broken" analysis, MEDIUM on exact fix shape — not yet written):**
```cpp
bool TransactionManager::CheckParentChildAuthority( const GeniusTransaction &tx ) const
{
    if ( tx.GetType() != "transfer" ) { return true; }             // Approve — not relevant
    auto certified_main = blockchain_->CheckCertifiedParent( tx.GetSrcAddress() );
    if ( !certified_main ) { return true; }                        // D-64: not found/not certified -> Approve
    if ( tx.CheckSignature() ) { return true; }                    // child's own key verified -> REGR-01/02
    return GetDestinationAddress( tx ) == *certified_main;         // D-21 destination restriction
}
```

**Insertion point (verified current, `TransactionManager.cpp:3988-3997`):**
```cpp
if ( !CheckTransactionAuthorization( *tx ) )
{
    TransactionManagerLogger()->error( "[{} - full: {}] {}: Authorization check failed tx={}",
                                       account_m->GetAddress().substr( 0, 8 ), full_node_m, __func__, tx->GetHash() );
    return ConsensusManager::ValidationResult::Reject();
}
// <<< INSERT CheckParentChildAuthority CALL HERE, same if/reject shape >>>
if ( !CheckTransactionTimestamp( *tx ) )
{
    ...
}
```
Copy the exact `if (!Check...(*tx)) { ...error log...; return ConsensusManager::ValidationResult::Reject(); }` block shape used by every neighboring gate call in `ValidateTransactionForConsensus` (lines 3966-4033).

---

### `CheckTransactionAuthorization` extension (D-60 whole-tx signature acceptance)

**Analog:** itself (extend in place), plus `GeniusTransaction::CheckSignature()` (`GeniusTransaction.cpp:72-81`, verified):
```cpp
bool GeniusTransaction::CheckSignature() const
{
    auto str_signature = dag_st.signature();
    SGTransaction::DAGStruct dag_copy = dag_st;
    dag_copy.clear_signature();
    auto serialized = SerializeByteVector(dag_copy);
    return GeniusAccount::VerifySignature( dag_st.source_addr(), str_signature, serialized );
}
```
**Required refactor:** extract a parameterized `CheckSignatureAgainst(const std::string &address)` from this body, have `CheckSignature()` call it with `dag_st.source_addr()`. Then `CheckTransactionAuthorization` gains:
```cpp
bool TransactionManager::CheckTransactionAuthorization( const GeniusTransaction &tx ) const
{
    if ( tx.CheckSignature() || tx.CheckDAGSignatureLegacy() ) { return true; }
    if ( tx.GetType() == "transfer" )
    {
        if ( auto certified_main = blockchain_->CheckCertifiedParent( tx.GetSrcAddress() ) )
        {
            if ( tx.CheckSignatureAgainst( *certified_main ) ) { return true; }
        }
    }
    return false;
}
```
This is additive — preserves the existing `if (...) return true;` early-return shape already in the function.

---

### `GeniusInputValidator.cpp` per-input signature check extension

**Analog (current code to extend), `GeniusInputValidator.cpp:357-366`, verified this session:**
```cpp
if ( !GeniusAccount::VerifySignature(
         tx->GetSrcAddress(),
         std::string_view( reinterpret_cast<const char *>( input.signature_.data() ),
                           input.signature_.size() ),
         input.SerializeForSigning() ) )
{
    logger->debug( "ValidateWitness(Genius) signature verification failed for tx={} input_index={}",
                   PreviewValue( tx->GetHash() ), input.output_idx_ );
    return false;
}
```
**Required new OR-branch (additive fallback, gated by tx type + certified lookup):**
```cpp
const bool sig_ok = GeniusAccount::VerifySignature( tx->GetSrcAddress(), sig_view, input.SerializeForSigning() );
bool delegated_sig_ok = false;
if ( !sig_ok && tx->GetType() == TRANSFER_TX_TYPE )
{
    if ( auto certified_main = blockchain->CheckCertifiedParent( tx->GetSrcAddress() ) )
    {
        delegated_sig_ok = GeniusAccount::VerifySignature( *certified_main, sig_view, input.SerializeForSigning() );
    }
}
if ( !sig_ok && !delegated_sig_ok ) { logger->debug(...); return false; }
```

**Owner-address check — verified UNCHANGED, do not touch** (`GeniusInputValidator.cpp:419-432`, verified this session):
```cpp
const bool delegated_escrow_spend =
    payload_owner != tx->GetSrcAddress() && tx->GetType() == TRANSFER_TX_TYPE &&
    input.output_idx_ == ESCROW_LOCK_OUTPUT_INDEX &&
    utxo_address::IsEscrowLockAddress( payload_owner ) && tx->GetUncleHash() == payload_owner;
if ( payload_owner != tx->GetSrcAddress() && !delegated_escrow_spend )
{
    logger->debug( "ValidateWitness(Genius) owner mismatch for tx={} owner={} src={}", ... );
    return false;
}
```
This `delegated_escrow_spend` block is the shape precedent cited in CONTEXT.md, but it solves the *inverse* mismatch (signer==src, owner≠src) vs D-60's (signer≠src, owner==src). Do NOT add a new exception here — for D-60's recovery tx, `payload_owner == child_addr == tx->GetSrcAddress()` naturally passes this check unmodified. The real fix goes only in the signature block above.

---

### `TransactionManager::RecoverFromChild` (new, service/CRUD-create)

**Analog:** `TransactionManager::TransferFunds`, `TransactionManager.cpp:566-589` verified:
```cpp
outcome::result<std::string> TransactionManager::TransferFunds( uint64_t amount, std::string destination, TokenID token_id )
{
    if ( GetState() != State::READY ) { return outcome::failure( boost::system::error_code{} ); }
    BOOST_OUTCOME_TRY( auto params, account_m->GetUTXOManager().CreateTxParameter( amount, std::move( destination ), token_id ) );
    auto [inputs, outputs] = params;
    auto transfer_transaction = std::make_shared<TransferTransaction>( TransferTransaction::New( inputs, outputs, FillDAGStruct() ) );
    transfer_transaction->MakeSignature( *account_m );
    account_m->GetUTXOManager().ReserveUTXOs( inputs, transfer_transaction->GetHash() );
    EnqueueTransaction( std::make_pair( transfer_transaction, std::nullopt ) );
    return transfer_transaction->GetHash();
}
```
**Do NOT reuse verbatim:**
- `CreateTxParameter`/`SelectUTXOs` only select from `address_outpoints_[address_]` (main's own bound address, `UTXOManager.cpp:1030`) — cannot select child's UTXOs. Build `InputUTXOInfo`s directly from `account_m->GetUTXOManager().GetUnconsumedUTXOs(child_addr)` and sign each with `account_m->Sign(input.SerializeForSigning())`.
- `FillDAGStruct()` hardcodes `source_addr = account_m->GetAddress()` and calls `account_m->ReserveNextNonce()` (main's own nonce) — build a `DAGStruct` (or overload) with `source_addr = child_addr` and nonce = `account_m->GetPeerNonce(child_addr) + 1`.
- `MakeSignature(*account_m)` — this line is reusable as-is (main signs, per D-60).

---

### `GeniusNode::RecoverFromChild` (new, controller/thin-wrapper)

**Analog:** `GeniusNode::TransferFunds`, two overloads, `GeniusNode.cpp:2237-2283` verified:
```cpp
outcome::result<std::string> GeniusNode::TransferFunds( uint64_t amount, const std::string &destination, TokenID token_id )
{
    if ( GetTransactionManagerState() != TransactionManager::State::READY )
    {
        node_logger_->error( "{}: Transaction Manager is not ready", __func__ );
        return outcome::failure( Error::TRANSACTIONS_NOT_READY );
    }
    auto available_balance = account_->GetUTXOManager().GetBalance( token_id );   // NOTE: no-arg = own address
    if ( available_balance < amount )
    {
        node_logger_->error( "{}: insufficient local funds: requested={}, available={}", __func__, amount, available_balance );
        return outcome::failure( Error::INSUFFICIENT_FUNDS );
    }
    BOOST_OUTCOME_TRY( auto manager, GetTransactionManager() );
    BOOST_OUTCOME_TRY( auto tx_id, manager->TransferFunds( amount, destination, token_id ) );
    node_logger_->debug( "{}: transaction {} sent", __func__, tx_id );
    return tx_id;
}
```
Plus the timeout-overload wrapper at lines 2237-2256 (calls the fire-and-return overload + `WaitForFinalized`).

**Critical deviation for `RecoverFromChild`:** the balance pre-check MUST use `account_->GetUTXOManager().GetBalance( token_id, child_addr )` (address-parameterized overload, already used by Phase 1's `GetChildBalance`) — NOT the no-arg overload shown above, which checks main's own balance instead of the child's.

Mirror `RegisterChild`'s two-overload declaration pattern (`GeniusNode.cpp:2285-2312`) for parameter-naming conventions if `RecoverFromChild` needs an explicit-vs-auto variant (not required here — `RecoverFromChild` mirrors `TransferFunds`'s fire-and-wait pair, not `RegisterChild`'s sequence pair).

---

### `Blockchain::CheckCertifiedParent` (new, service/CRUD-read)

**Analog:** `Blockchain::CheckCertificate` (`Blockchain.hpp:252`) — existing single-hash certificate lookup, already used in `EvaluateTransactionReplayProtection` (`TransactionManager.cpp:4128`). Reg/-key-read precedent at `TransactionManager.cpp:618-619` (`RegisterChild`'s sequence lookup) and `:2873-2874` (`FilterRegistration`'s existing-registration check) — both single-key `Get`, not scans.

**Shape (recommended, not yet in repo):**
```cpp
std::optional<std::string> Blockchain::CheckCertifiedParent( const std::string &child_addr ) const
{
    std::string reg_key = /* GetBlockChainBase() format */ + "reg/" + child_addr;
    auto existing_data = db_->Get( reg_key );
    if ( !existing_data.has_value() ) { return std::nullopt; }
    auto maybe_tx = /* shared deserializer, e.g. TransactionManager::DeSerializeTransaction */ ( existing_data.value() );
    if ( maybe_tx.has_error() || maybe_tx.value()->GetType() != "registration" ) { return std::nullopt; }
    auto reg_tx = std::dynamic_pointer_cast<RegistrationTransaction>( maybe_tx.value() );
    if ( !reg_tx ) { return std::nullopt; }
    if ( !CheckCertificate( reg_tx->GetHash() ) ) { return std::nullopt; }   // D-26: must be certified
    return reg_tx->GetMainAddress();
}
```
**Open plumbing issue (flagged in RESEARCH.md, Claude's discretion at implementation):** `GetBlockChainBase()`/`TRANSACTION_BASE_FORMAT` are currently `TransactionManager`-private (`TransactionManager.hpp:327`). Expose as a shared free function/static utility rather than duplicating the format string in `Blockchain.cpp`.

---

### Test file extension (D-65)

**Analog:** `RegistrationTransactionE2ETest` fixture, `test/src/account/registration_transaction_test.cpp:200-254` verified:
```cpp
class RegistrationTransactionE2ETest : public test::CRDTFixture
{
public:
    RegistrationTransactionE2ETest() : CRDTFixture( "reg_tx_e2e_test" )
    {
        account_ = GeniusAccount::New( kTestTokenId, base_path / "account" );
        blockchain_ = Blockchain::New( db_, account_, pubs_, []( outcome::result<void> ) {} );
        tm_ = TransactionManager::New( db_, io_, account_, blockchain_, true, 0, kTimestampTolerance, kMutabilityWindow );
        // ... io_context worker thread drives TickOnce() to READY
    }
    std::shared_ptr<GeniusAccount>      account_;
    std::shared_ptr<Blockchain>         blockchain_;
    std::shared_ptr<TransactionManager> tm_;
};
```
**Required extension:** this fixture currently has exactly ONE `GeniusAccount`/`TransactionManager` pair. CONS-01/CONS-02/REGR-01/02/03 tests need a SECOND real `GeniusAccount` (genuine "main" keypair) sharing the same `db_`. Per RESEARCH.md's Open Question recommendation: start with single-`TransactionManager` (main's) + bare second `GeniusAccount` (child, keypair-only, no own `TransactionManager` loop) — simpler, avoids two-node threading complexity, and sufficient since gates are called directly on whatever `tx` object is passed to `ValidateTransactionForConsensus`.

## Shared Patterns

### Gate-list logging/error shape
**Source:** `TransactionManager.cpp:3966-4033` (`ValidateTransactionForConsensus`)
**Apply to:** `CheckParentChildAuthority`'s call-site insertion and internal logging
```cpp
if ( !CheckXxx( *tx ) )
{
    TransactionManagerLogger()->error( "[{} - full: {}] {}: Xxx check failed tx={}",
                                       account_m->GetAddress().substr( 0, 8 ), full_node_m, __func__, tx->GetHash() );
    return ConsensusManager::ValidationResult::Reject();
}
```

### Two-layer method convention
**Source:** `TransactionManager.cpp:566-589` + `GeniusNode.cpp:2258-2283` (`TransferFunds`), `GeniusNode.cpp:2285-2312` (`RegisterChild`)
**Apply to:** `RecoverFromChild` at both `TransactionManager` and `GeniusNode` layers — `TransactionManager::X()` builds/signs/enqueues, `GeniusNode::X()` checks READY state + balance pre-check + delegates.

### Signature verification primitive (never hand-roll)
**Source:** `GeniusAccount::VerifySignature` (`GeniusAccount.cpp:790-815`) — unhexes `address` directly as the secp256k1 public key.
**Apply to:** all three D-60 extension points (`CheckTransactionAuthorization`, `ValidateWitness`'s per-input check, `Blockchain::CheckCertifiedParent`'s eventual signature-adjacent callers) — always pass a different *address* argument, never build a new verification routine.

### Certified-registration lookup, single-key not scan
**Source:** `TransactionManager.cpp:618-619` (`RegisterChild` sequence lookup), `:2873-2874` (`FilterRegistration`)
**Apply to:** `Blockchain::CheckCertifiedParent` — direct `db_->Get("reg/" + child_addr)`, not a `QueryKeyValues` prefix scan like `GetRegistrationsForMain` (`TransactionManager.cpp:4983-5031`, explicitly the wrong shape for this need per RESEARCH.md).

## No Analog Found

None — every file this phase touches already exists and has a directly analogous function/section in the same file or a sibling file to model from. No new file types are introduced in this phase.

## Metadata

**Analog search scope:** `SuperGenius/src/account/` (TransactionManager.cpp/.hpp, GeniusInputValidator.cpp, GeniusTransaction.cpp/.hpp, GeniusNode.cpp/.hpp, UTXOManager.cpp/.hpp, GeniusAccount.cpp/.hpp), `SuperGenius/src/blockchain/` (Blockchain.hpp/.cpp), `SuperGenius/test/src/account/registration_transaction_test.cpp`
**Files scanned:** 10 (all read directly this session or in RESEARCH.md's prior session, cross-verified against current line numbers for the two highest-risk excerpts: `ValidateTransactionForConsensus` gate pipeline and `GeniusInputValidator.cpp`'s signature/owner checks)
**Pattern extraction date:** 2026-07-20
