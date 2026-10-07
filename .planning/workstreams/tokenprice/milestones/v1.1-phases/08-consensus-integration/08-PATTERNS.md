# Phase 8: Consensus Integration - Pattern Map

**Mapped:** 2026-10-06
**Files analyzed:** 8 (7 modified + 1 optional new)
**Analogs found:** 8 / 8 (7 exact, 1 partial)

> **Repo layout note:** `SuperGenius/` is a **nested git submodule** (parent tracks it as `160000`). All analog paths below are git-tracked **from within `SuperGenius/`** (verified via `git -C SuperGenius ls-files`). Never name paths under `.gsd/capabilities/` mirrors.

**Conventions (all new code):** Ullman braces (braces on own line, Standard 10), PascalCase types, `m_`/`trailing_underscore` members, space inside parens `f( x )`, Doxygen `@file/@brief/@date/@author` headers, `BOOST_OUTCOME_TRY` + `outcome::failure( std::errc::... )` error style, `base::createLogger( "Name" )` loggers, `logger->debug/error( "{}: ...", __func__, ... )` log format. Source: `Coding Standards.md` (repo root) §4.1, §5; observed in every analog below.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `SuperGenius/src/transaction/TransactionConsensusHandler.{hpp,cpp}` (modify) | consensus validation handler | event-driven (subject validation) | itself — check chain + migration-allowlist `Pending()` precedent | exact |
| `SuperGenius/src/blockchain/impl/proto/Consensus.proto` (modify) | config (protocol contract) | event-driven (pub-sub subject) | `TaskResultSubject` message in same file | exact |
| `SuperGenius/src/blockchain/Consensus.{hpp,cpp}` (modify) | service (consensus machinery) | event-driven | `TASK_RESULT_SUBJECT_TYPE` constant + `CheckSubject` branch + `CreateTaskResultSubject` | exact |
| `SuperGenius/src/transaction/TransactionManager.{hpp,cpp}` (modify) | service | CRUD + event-driven | `PayEscrow` (1219), cert-handler registration (147–180), FAILED branch (4893–4933) | exact |
| `SuperGenius/src/processing/impl/TaskQueueImpl.{hpp,cpp}` (modify) | service (queue) | batch (claim scan) | itself — `GrabTask` `IsProcessingValid` → `MarkTaskBad` skip (123–180, 215) | exact |
| `SuperGenius/src/account/GeniusNode.cpp` (modify) | facade/wiring | request-response | `ProcessImage` claimed_price stamping (2694–2720) + `QueryHistory` seam | exact |
| `SuperGenius/test/src/processing_nodes/processing_nodes_test.cpp` (modify) | test (multi-node integration) | request-response | itself — `ProcessingNodesTest` fixture (25–140) | exact |
| `SuperGenius/src/transaction/EscrowReleaseTransaction.{hpp,cpp}` (optional new) | model (tx class) | CRUD (UTXO spend) | `EscrowTransaction` + `transaction_parsers` registration map (110–118) | partial — no release parser entry exists today (RESEARCH Open Q3 recommends plain `TransferTransaction` spend instead) |

## Pattern Assignments

### `TransactionConsensusHandler.cpp` — price gate in the check chain (D-08-01/D-08-02)

**Analog:** the same file's existing chain and Pending precedent.

**Core check-chain pattern** — `ValidateTransactionForConsensus` (chain at ~510–555; entry call at ~494):
```cpp
// SuperGenius/src/transaction/TransactionConsensusHandler.cpp:510-555 (verbatim shape, verified)
ConsensusManager::ValidationResult TransactionConsensusHandler::ValidateTransactionForConsensus(
    const GeniusTransaction &tx ) const
{
    logger_->debug( "{}: Validating transaction", __func__ );
    if ( !CheckTransactionWellFormed( tx ) )
    {
        logger_->error( "{}: Well-formed check failed tx={}", __func__, tx.GetHash() );
        return ConsensusManager::ValidationResult::Reject();
    }
    if ( !owner_.CheckTransactionAuthorization( tx ) ) { return ...Reject(); }
    if ( !CheckTransactionTimestamp( tx ) )            { return ...Reject(); }
    if ( !owner_.CheckParentChildAuthority( tx ) )     { return ...Reject(); }
    auto replay_result = EvaluateTransactionReplayProtection( tx );
    if ( replay_result.validation.check != ConsensusManager::Check::Approve ) { return replay_result.validation; }
    if ( !CheckTransactionTypeRules( tx ) )            { return ...Reject(); }
    return ConsensusManager::ValidationResult::Approve();
}
```
The gate slots in as an escrow-typed branch before final Approve: `tx.GetType() == "escrow-hold"` (the registered parser key — see Shared Patterns #3), `dynamic_pointer_cast<EscrowTransaction>`-style dispatch mirroring the migration branch below.

**Pending precedent** — migration allowlist (~472–491, verbatim):
```cpp
if ( auto migration_tx = std::dynamic_pointer_cast<MigrationTransaction>( tx ) )
{
    MigrationAllowList allow_list( owner_.globaldb_m->GetDataStore(), migration_tx->GetFromVersion() );
    auto eligibility_result = allow_list.IsEligible( migration_tx->GetSrcAddress(), migration_tx->GetAmount() );
    if ( eligibility_result.has_error() )
    {
        logger_->warn( "{}: Failed to evaluate local migration allowlist tx={} src={} err={}, pending",
                        __func__, tx_hash, migration_tx->GetSrcAddress(), eligibility_result.error().message() );
        return ConsensusManager::ValidationResult::Pending();
    }
    ...
}
```
D-08-02: missing task record ⇒ return `Pending()` exactly like this. Pending retry machinery is already built (`Consensus.cpp:1036 AddPendingProposal`, `1169 RetryPendingProposal` re-invokes the subject handler, `1243 WakePendingDependency`, `1297 ProcessDuePendingRetries` — grep-verified).

**Reject wiring** — `HandleNonceConsensusSubject` tail (~494–510, verbatim):
```cpp
auto validate_result = ValidateTransactionForConsensus( *tx );
if ( validate_result.check == ConsensusManager::Check::Pending )
{
    return validate_result;
}
if ( validate_result.check != ConsensusManager::Check::Approve )
{
    return reject_and_maybe_fail_local( "transaction validation failed" );
}
metrics_validation_approve_.fetch_add( 1, std::memory_order_relaxed );
return ConsensusManager::ValidationResult::Approve();
```

**Error handling / logging pattern:** every check logs `logger_->error( "{}: <what> failed tx={}", __func__, tx.GetHash() )` before Reject; metrics counters use `fetch_add( 1, std::memory_order_relaxed )` (`metrics_validation_reject_` for gate rejects — add alongside, per Metrics struct in the .hpp).

**Certificates apply WITHOUT the gate** — `OnConsensusCertificate` (`TransactionConsensusHandler.cpp:61-145`) deserializes the embedded tx and calls `ChangeTransactionState( tx, TransactionStatus::CONFIRMED )` directly. Gate = prevent certification; backstop = prevent processing (RESEARCH Pitfall 3).

---

### `Consensus.proto` + `Consensus.{hpp,cpp}` — new rejection subject (D-08-06)

**Analog:** the existing typed-subject trio (proto message → type constant → `CheckSubject` branch → Create/Decode helpers).

**Proto pattern** — `TaskResultSubject` in `SuperGenius/src/blockchain/impl/proto/Consensus.proto` (message directly after the `EmbeddedTransaction` oneof, which already carries `SGTransaction.EscrowReleaseTx escrow_release = 7;`):
```protobuf
// verbatim
message TaskResultSubject {
  string escrow_path = 1;
  bytes task_result_hash = 2;
  uint64 result_epoch = 3;
}
```
Add `TaskRejectionSubject` beside it (agent's discretion on exact name/fields/numbers per CONTEXT): `escrow_path`, `task_id`, typed `reject_reason` (`PriceValidationReason` value), `original_escrow_hash`. New field numbers only — one-way protocol change (D-08-06).

**Type-constant pattern** — `SuperGenius/src/blockchain/Consensus.hpp:38-40` (verbatim, grep-verified):
```cpp
static constexpr std::string_view NONCE_SUBJECT_TYPE          = "sgns.nonce.v1";
static constexpr std::string_view TASK_RESULT_SUBJECT_TYPE    = "sgns.task_result.v1";
static constexpr std::string_view REGISTRY_BATCH_SUBJECT_TYPE = "sgns.registry_batch.v1";
```

**CheckSubject branch pattern** — `SuperGenius/src/blockchain/Consensus.cpp:4348-4400` (verbatim shape):
```cpp
if ( SubjectTypeMatches( subject, NONCE_SUBJECT_TYPE ) )
{
    auto payload = DecodeNonceSubject( subject );
    if ( payload.has_error() || payload.value().tx_hash().empty() )
    {
        ConsensusManagerLogger()->error( "{}: subject nonce tx_hash is empty", __func__ );
        return false;
    }
    return true;
}
if ( SubjectTypeMatches( subject, TASK_RESULT_SUBJECT_TYPE ) )
{
    auto payload = DecodeTaskResultSubject( subject );
    if ( payload.has_error() || payload.value().escrow_path().empty() ) { ... return false; }
}
```
(Dispatch switch also at `Consensus.cpp:800/809/818` and `4278/4291/4296` — grep-verified; add the new type to every `SubjectTypeMatches` switch.) The rejection branch validates refs non-empty (V4/V5 security control: refs present; verdict re-derived independently by the subject handler).

**Subject-construction pattern** — `CreateTaskResultSubject`, `Consensus.cpp:4104-4131` (verbatim core):
```cpp
Subject subject;
subject.set_account_id( account_id );
TaskResultSubject payload;
payload.set_escrow_path( escrow_path );
payload.set_task_result_hash( task_result_hash.data(), task_result_hash.size() );
payload.set_result_epoch( result_epoch );
auto type_hash = ComputeSubjectTypeHash( TASK_RESULT_SUBJECT_TYPE );
if ( type_hash.has_error() || !SetSubjectPayload( &subject, type_hash.value(), payload ) )
{
    return outcome::failure( std::errc::invalid_argument );
}
subject.mutable_subject_type_hash()->set_hash( type_hash.value().data(), type_hash.value().size() );
return subject;
```
Mirror as `CreateTaskRejectionSubject`; add a `DecodeTaskRejectionSubject` beside `DecodeTaskResultSubject` (declared `Consensus.hpp:488`, next to `ComputeSubjectTypeHash` at :486).

---

### `TransactionManager.cpp` — cert-handler registration, poster refund, release construction

**Analog:** `TransactionManager::New` registrations + `PayEscrow` + the FAILED state branch.

**Handler registration pattern** — `SuperGenius/src/transaction/TransactionManager.cpp:147-180` (verbatim shape, grep-verified anchors):
```cpp
instance->blockchain_->RegisterCertificateHandler(
    NONCE_SUBJECT_TYPE,
    [weak_ptr( std::weak_ptr<TransactionManager>( instance ) )](
        const std::string &subject_hash, const ConsensusCertificate &certificate )
        -> outcome::result<ConsensusManager::Check>
    {
        if ( auto strong = weak_ptr.lock() )
        {
            auto process_result = strong->consensus_m_->OnConsensusCertificate( subject_hash, certificate );
            if ( process_result.has_error() )
            {
                strong->m_logger->error( "Failed to process certificate proposal_id={} error={}",
                                         certificate.proposal_id(), process_result.error().message() );
            }
            return process_result;
        }
        return outcome::failure( std::errc::owner_dead );
    } );
instance->blockchain_->RegisterSubjectHandler(
    NONCE_SUBJECT_TYPE,
    [weak_ptr( std::weak_ptr<TransactionManager>( instance ) )]( const ConsensusManager::Subject &subject )
        -> outcome::result<ConsensusManager::ValidationResult>
    { ... } );
```
Copy this weak-ptr-capture + `std::errc::owner_dead` shape verbatim for `TASK_REJECTION_SUBJECT_TYPE`: the **subject handler re-runs the price gate on the referenced task+escrow** (that IS D-08-06's independent verification); the **certificate handler drives the poster's escrow → FAILED**.

**Poster-side refund (regime 1)** — target the existing FAILED branch, `TransactionManager.cpp:4893-4933` (verbatim core):
```cpp
case TransactionStatus::INVALID:
case TransactionStatus::FAILED:
{
    ...
    else if ( tx->GetSrcAddress() == account_m->GetAddress() && tx->HasUTXOParameters() )
    {
        // Local outgoing tx failed before confirmation: release locally reserved inputs.
        auto params_opt = tx->GetUTXOParametersOpt();
        if ( params_opt.has_value() )
        {
            ...
            account_m->GetUTXOManager().RollbackUTXOs( params_opt->first, tx->GetHash() );
        }
    }
    tx_processed_m[key] = TrackedTx{ tx, TransactionStatus::FAILED, tx->GetNonce() };
```
Do NOT touch the `UNCONFIRMED` branch (4869-4890: `ReleaseNonce` + `ReleaseBridgeMintReservation` only — it deliberately does not roll back escrow reservations; the cert handler reaches rollback via `ChangeTransactionState( escrow_tx, FAILED )`).

**Release construction (regime 2, D-08-05)** — `PayEscrow`, `TransactionManager.cpp:1219-1305` (verbatim core; async wrapper `AsyncPayEscrow` at 1309):
```cpp
BOOST_OUTCOME_TRY( auto transaction, FetchTransaction( *globaldb_m, escrow_path ) );   // :1256
auto escrow_tx = std::dynamic_pointer_cast<EscrowTransaction>( transaction );          // :1259
...
InputUTXOInfo escrow_utxo_input;                                                        // :1277-1280
escrow_utxo_input.txid_hash_  = base::Hash256::fromReadableString( escrow_tx->GetHash() ).value();
escrow_utxo_input.output_idx_ = 0;
escrow_utxo_input.signature_  = account_m->Sign( escrow_utxo_input.SerializeForSigning() );
std::string lock_id = escrow_tx->GetUncleHash();                                        // :1284 + empty fallback
...
auto transfer_transaction = std::make_shared<TransferTransaction>(
    TransferTransaction::New( std::vector{ escrow_utxo_input }, payout_peers, FillDAGStruct( lock_id ) ) );
transfer_transaction->MakeSignature( *account_m );
EnqueueTransaction( TransactionItem{ TransactionBatch{ { transfer_transaction, std::nullopt } },
                                     std::move( crdt_transaction ) } );
```
D-08-07 divergence: **do not call `BuildPayoutOutputs`** (it always emits a burn output); the rejection release is a single full-amount output to the poster's `release_address`. Gate construction on `escrow status == CONFIRMED` (regime 2 only — Pitfall 1: an uncertified escrow has no UTXO to spend). `FetchTransaction` seam: `TransactionManager.cpp:2428`. `WaitForEscrowRelease` at 3062.

---

### `TaskQueueImpl.cpp` — claim-time backstop (D-08-04)

**Analog:** the `GrabTask` scan's existing `IsProcessingValid` → `MarkTaskBad` skip.

**Insertion point** — `SuperGenius/src/processing/impl/TaskQueueImpl.cpp:158-168` (verbatim):
```cpp
BOOST_OUTCOME_TRY( auto task, GetTask( taskId ) );
if ( !sgns::sgprocessing::ProcessingManager::IsProcessingValid( task.json_data() ) )
{
    TaskQueueImplLogger()->error( "Task with ID: {} has invalid processing data", taskId );
    MarkTaskBad( taskId );
    continue;
}
return std::make_pair( taskId, task );
```
Insert the `ValidatePrice` backstop in exactly this shape (after `GetTask`, before `return`): on reject → `MarkTaskBad( taskId ); continue;` (D-08-04/D-08-10).

**Skip semantics** — `TaskQueueImpl.cpp:215-219` (verbatim):
```cpp
void TaskQueueImpl::MarkTaskBad( const std::string &taskKey )
{
    incompatible_jobs_.insert( taskKey );
    TaskQueueImplLogger()->debug( "Marked task with ID: {} as incompatible", taskKey );
}
```
Per-node in-memory `std::unordered_set` member (`TaskQueueImpl.hpp` tail: `incompatible_jobs_`) — no CRDT write. If a price-verdict callback is injected, follow the header's existing style: interface override in `processing_task_queue.hpp` lineage, private member with trailing underscore.

**Imports/namespace pattern** (`TaskQueueImpl.cpp:1-10`): `namespace sgns::processing`, `base::createLogger( "TaskQueueImpl" )` free function, `BOOST_OUTCOME_TRY` over `db_->QueryKeyValues( TaskKeys::ClaimableListKey() )`.

**blockSize warning (Pitfall 7):** the backstop must recompute blockSize exactly as the poster did — `procmgr.ParseBlockSize()` over `task.json_data()` (see `GetProcessCost`, `GeniusNode.cpp:2816-2821`) — else honest jobs false-reject with `CostMismatch`.

---

### `GeniusNode.cpp` — evidence-provider wiring

**Analog:** `ProcessImage`'s claimed_price stamping and the `LocalPriceManager` seam.

**Stamping precedent** — `SuperGenius/src/account/GeniusNode.cpp:2694-2720` (verbatim):
```cpp
auto cost = GetProcessCost( *procmgr );          // :2694
...
task.set_claimed_price( cost.quote.price );      // :2720 (comment at :2719 — single quote fetch, D-06-01)
```
and `GetProcessCost` at 2816: `auto blockLen = procmgr.ParseBlockSize();` → `TokenAmount::CalculateCostMinions( blockLen.value(), gnusPrice )`.

**Evidence seam** — `SuperGenius/src/coinprices/LocalPriceManager.hpp:131`:
```cpp
PriceHistoryStats QueryHistory( std::chrono::system_clock::time_point from,
                                std::chrono::system_clock::time_point to );
```
**BLOCKING** (post+future onto the manager's strand) — must never be called from the manager's own runner thread. Wire `priceManager_` (GeniusNode owns it) into gate/backstop via an injected callback/interface at node construction (RESEARCH: TransactionManager must NOT own the price manager).

**Input assembly (gate + backstop share one helper)** — field-for-field from `PriceValidator.hpp` (~57-110, verbatim struct):
```cpp
struct PriceValidationInput
{
    double claimedPrice = 0.0;                       // task.claimed_price()
    uint64_t escrowAmount = 0;                       // escrow_tx->GetAmount()
    std::chrono::system_clock::time_point dagTimestamp{}; // escrow DAGStruct.timestamp
    uint64_t blockSize = 0;                          // ProcessingManager ParseBlockSize(task.json_data())
    std::chrono::system_clock::time_point now{};     // INJECTED — purity contract
    LocalPriceManager::PriceHistoryStats stats{};    // QueryHistory(window.from, window.to)
};
```
Use `PriceObservationWindow( dagTimestamp, config )` (`PriceValidator.hpp` ~113-121 — the ONE window formula), `ResolvePriceValidatorConfig()` (~:240), then `ValidatePrice( in, cfg )`; reason taxonomy at ~46-55: `Accepted, LegacyNoPrice, TimestampFuture, TimestampStale, CostMismatch, AboveBand, BelowBand, NoCoverage`. Refetch self-heal via `ShouldTriggerRefetch( result.reason )` (D-07-06).

---

### `processing_nodes_test.cpp` — TEST-02 (D-08-11..13)

**Analog:** the existing `ProcessingNodesTest` fixture (do not build a new harness).

**Fixture pattern** — `SuperGenius/test/src/processing_nodes/processing_nodes_test.cpp:25-140` (verbatim anchors):
- 3 static nodes: `node_main` (Light, `is_processor=false`), `node_proc1`/`node_proc2` (Full, processors) — `WriteLocalTrustSgnsConfig(...)` + `GeniusNode::New( cfg, sgns::FromPrivateKey{...} )`.
- Hermetic price stub (~:52-56): `price_stub_.OnPath( "/api/v3/simple/price", { 200, "application/json", R"({"genius-ai":{"usd":1.0}})" } );` + `ScopedEnvVar( "SGNS_COINGECKO_URL", base )` / `SGNS_PRICE_FALLBACK_URL` — D-08-12 flips via a second `OnPath` call to the same stub (single-process shared env; no per-node env).
- Wait helpers: `testutil/wait_condition.hpp`; teardown: ordered `GeniusNodeTestAccess::StopNode(...)` then `.reset()` (port-reuse landmine, ~:113-135).
- New cases are self-contained `TEST_F( ProcessingNodesTest, ... )` — the existing `PostProcessing` case ends truncated at line 540 (`auto balance_main = node_main->GetBalance();` is the file's last line — Pitfall 8).
- Assert economics: `GetBalance()` counts only `UTXO_READY` outpoints, so reservations reduce it (D-08-13 grounding); poster-side release confirmation via `WaitForEscrowRelease` — `GeniusNode.hpp:241-246`: `TIMEOUT_ESCROW_PAY{ 50000 }` (SGNS_DEBUG) / `{ 30000 }` (release).

**Hermetic validator-test pattern** (if unit cases needed): `SuperGenius/test/src/price_validator/price_validator_test.cpp` — pure-function tests, zero mocks, injected clock. RAII env guards: `SuperGenius/test/src/testutil/scoped_env.hpp`.

---

### `EscrowReleaseTransaction.{hpp,cpp}` (optional new — only if typed release chosen)

**Analog (partial):** new tx class = header style of `EscrowTransaction` + registration in the parser map, `SuperGenius/src/transaction/TransactionManager.cpp:110-118` (verbatim):
```cpp
TransactionManager::transaction_parsers = {
    { "transfer", { &TransactionManager::ParseTransferTransaction, &TransactionManager::RevertTransferTransaction } },
    ...
    { "escrow-hold", { &TransactionManager::ParseEscrowTransaction, &TransactionManager::RevertEscrowTransaction } },  // :117
    ... };
```
No release entry exists today. Proto fields already on the wire: `SGTransaction.proto:126` `message EscrowReleaseTx` (`release_amount = 3, release_address = 4, escrow_source = 5, original_escrow_hash = 6`) and `EmbeddedTransaction.escrow_release = 7`. **RESEARCH Open Q3 recommends the plain `TransferTransaction` spend (PayEscrow shape) instead** — planner decides within D-08-05/D-08-06.

## Shared Patterns

### 1. Typed check chain with Pending escape hatch
**Source:** `TransactionConsensusHandler.cpp` ~472-555. **Apply to:** the price gate. Fail-fast ordered checks; "can't decide yet" ⇒ `ValidationResult::Pending()` (never Reject on absence — D-08-02); Reject ⇒ `reject_and_maybe_fail_local( "reason" )` + `metrics_validation_reject_.fetch_add(1, relaxed)`.

### 2. Typed consensus subject trio + handler registration
**Source:** `Consensus.hpp:38-40` constants; `Consensus.proto` `TaskResultSubject`; `Consensus.cpp:4104` Create / `:4348` CheckSubject / every `SubjectTypeMatches` switch (800/809/818, 4278/4291/4296, 4383); `TransactionManager.cpp:147-180` Register{Certificate,Subject}Handler with `weak_ptr` capture + `std::errc::owner_dead`. **Apply to:** `TaskRejectionSubject` end-to-end.

### 3. Transaction-type dispatch by string key
**Source:** `transaction_parsers` map (`TransactionManager.cpp:110-118`) + `CheckTransactionWellFormed`'s lookup (`TransactionConsensusHandler.cpp` ~575-580). **Apply to:** the gate's escrow branch (`tx.GetType() == "escrow-hold"`) and any new tx type.

### 4. Escrow spend construction
**Source:** `PayEscrow` (`TransactionManager.cpp:1219-1305`): `FetchTransaction` → `dynamic_pointer_cast<EscrowTransaction>` → `InputUTXOInfo` (txid_hash, idx 0, `account_m->Sign(SerializeForSigning())`) → `TransferTransaction::New(... FillDAGStruct(lock_id))` → `MakeSignature` → `EnqueueTransaction`. **Apply to:** regime-2 release; full-amount single output, NO `BuildPayoutOutputs` (D-08-07).

### 5. Error handling & logging
**Source:** all analogs. `BOOST_OUTCOME_TRY` propagation; `outcome::failure( std::errc::invalid_argument / owner_dead / operation_canceled )`; per-component logger via `base::createLogger( "Name" )`; `"{}: msg arg={}", __func__, arg` format; `logger_->warn` + `Pending()` for retryable conditions.

### 6. Validator purity + env config
**Source:** `PriceValidator.hpp` (purity contract header comment; `ResolvePriceValidatorConfig` `SGNS_PRICEVAL_*`, non-cached `ReadEnvDoubleInRange`/`ReadEnvPositiveSeconds`). **Apply to:** every gate/backstop call site — all I/O (QueryHistory, escrow fetch, `now`) at the caller, injected into `PriceValidationInput`.

### 7. Test hermeticity
**Source:** `processing_nodes_test.cpp` fixture + `testutil/` (`HttpStubServer`, `ScopedEnvVar`, `wait_condition`). **Apply to:** TEST-02 — flip stub price between quote and vote; assert balance restoration + no processing.

## No Analog Found

None — every file has at least a role-match analog in tracked source. Closest-to-greenfield is the optional typed `EscrowReleaseTransaction` C++ class (wire format exists at `SGTransaction.proto:126`; no parser entry, builder, or class — use RESEARCH.md Pattern 4 / Open Q3 guidance if built).

## Metadata

**Analog search scope:** `SuperGenius/src/{transaction,blockchain,processing/impl,account,coinprices}`, `SuperGenius/src/account/proto`, `SuperGenius/src/blockchain/impl/proto`, `SuperGenius/test/src/{processing_nodes,price_validator,testutil}` (all inside the `SuperGenius` nested submodule; tracked verified via `git -C SuperGenius ls-files`).
**Files scanned:** 19 tracked candidates read/grepped; 9 read in excerpt.
**Pattern extraction date:** 2026-10-06
