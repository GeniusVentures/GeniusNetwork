# Phase 4: Grid Integration & E2E Proof - Pattern Map

**Mapped:** 2026-09-14
**Files analyzed:** 14 (new + modified, across both repos)
**Analogs found:** 14 / 14 (every file has an in-codebase analog — this phase is wiring, not invention)

> All line anchors below were verified against the live `dev_elmruntime` trees (SGProcessingManager `7ffc911`, SuperGenius `d919363b1`) on 2026-09-14, same session as RESEARCH.md.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `SuperGenius/src/processing/processing_tasksplit_elm.hpp/.cpp` (NEW) | utility (splitter) | transform | `src/processing/processing_tasksplit.cpp` + `.hpp` | exact (sibling-by-design) |
| `SuperGenius/src/processing/CMakeLists.txt` (MODIFY) | config (build) | — | same file, `processing_tasksplit.cpp` entry | exact |
| `SuperGenius/src/account/GeniusNode.cpp` — `ProcessImage` ELM branch (MODIFY) | service (submit orchestration) | request-response | in-file: non-ELM loop `:2296-2361` + interim ELM block `:2272-2290` being replaced | exact (in-file) |
| `SuperGenius/src/account/GeniusNode.cpp` — rate-record composition (MODIFY) | service (CRDT write) | batch (multi-Put atomic) | in-file: `CreateElmRateRecordCRDTTransaction :3270-3305` + `CreateEscrowInfoCRDTTransaction :3258-3268` | exact (in-file) |
| `SuperGenius/src/account/TransactionManager.cpp/.hpp` — `BuildPayoutOutputs`/`PayEscrow` ELM branch (MODIFY) | service (settlement) | transform (arithmetic) | in-file: even-split `BuildPayoutOutputs :1104-1202`; integer path `processing_clocks_elm.hpp` | exact (in-file) |
| `SuperGenius/src/account/GeniusNode.cpp` — `ProcessingDone` envelope-fetch orchestration (MODIFY) | service (settlement read) | request-response (fetch) | `fetchOutputData` lambda, `processing_subtask_queue_accessor_impl.cpp:379-411` | exact |
| `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` — `ProcessInternal` ELM branch (MODIFY) | service (worker dispatch) | request-response | in-file: non-ELM `ProcessInternal :1489-1668` (the branch is its first conditional) | exact (in-file) |
| `ProcessingManager.cpp` — `CheckElmValidity` stop-array bounds (MODIFY) | middleware (validation gate) | transform | in-file: generation-settings gates `:704-746` | exact (in-file) |
| `ProcessingManager.cpp` — production-cache call site + save-loop ELM branch (MODIFY) | service (cache + artifact publish) | file-I/O / pub-sub | in-file: dual-save loop `:1847-1965`; `ElmModelCache.cpp:295-316` factory | exact (in-file) |
| `SGProcessingManager/gnus-processing-schema.json` — `ElmGeneration.stop` (MODIFY) | config (schema) | — | in-file: `ElmGeneration :161-184`; root `tags` array-of-string `:29-34` | exact (in-file) |
| `SGProcessingManager/elm-model-manifest-schema.json` + `generated/` regen (MODIFY/REGEN) | config (schema) + generated | — | in-file: role pattern `:16-17`; `ElmModelArtifact` def in `gnus-processing-schema.json :188-195` | exact (in-file) |
| `SGProcessingManager/include/elmruntime/ElmEnvelope.hpp` + `src/elmruntime/ElmEnvelope.cpp` — stamps (MODIFY) | model | transform | in-file: six-key envelope + `ElmEnvelopeToJson` (`ElmEnvelope.cpp:43-56`) | exact (in-file) |
| `SGProcessingManager/src/elmruntime/ElmManifest.cpp` — `embedding_file` role (MODIFY) | utility (role table) | transform | in-file: `kRoleFilenames/kRequiredRoles :36-48` (`context_file` = the optional-role precedent) | exact (in-file) |
| `SuperGenius/test/src/…/elm_*_test.cpp` — splitter/settlement/E2E (NEW) | test | event-driven (wait-condition) | `test/src/account/elm_cost_clocks_test.cpp` (node fixture + JSON builder) + `test/src/processing_multi/processing_multi_test.cpp` (both-roles topology) | exact |

---

## Pattern Assignments

### `SuperGenius/src/processing/processing_tasksplit_elm.hpp/.cpp` (utility, transform)

**Analog:** `SuperGenius/src/processing/processing_tasksplit.{hpp,cpp}` — the sibling-by-design precedent (research anti-pattern: do NOT modify `ProcessTaskSplitter::SplitTask` itself).

**Header shape** (`processing_tasksplit.hpp:1-35` — copy include guard style, `boost/format`, proto include, namespace, class-with-factory-free-ctor):
```cpp
#ifndef _PROCESSING_TASKSPLIT_HPP_
#define _PROCESSING_TASKSPLIT_HPP_
#include <cstdlib>
#include <list>

#include <boost/format.hpp>

#include "processing/proto/SGProcessing.pb.h"

namespace sgns
{
    namespace processing
    {
        class ProcessTaskSplitter
        {
        public:
            ProcessTaskSplitter();

            void SplitTask( const SGProcessing::Task         &task,
                            std::list<SGProcessing::SubTask> &subTasks,
                            std::string                       json_data,
                            uint32_t                          numchunks,
                            bool                              addvalidationsubtask,
                            std::string                       ipfsid );
        };
    }
}
#endif
```

**UUID minting — reuse, do not re-invent** (`processing_tasksplit.cpp:31-49`; already non-member, callable from the new TU):
```cpp
std::string generate_uuid_with_ipfs_id(const std::string& ipfs_id) {
    // Hash the IPFS ID
    std::hash<std::string> hasher;
    uint64_t id_hash = hasher(ipfs_id);
    ...
    std::mt19937 gen(seed);
    boost::uuids::basic_random_generator<std::mt19937> uuid_gen(gen);
    boost::uuids::uuid uuid = uuid_gen();
    return boost::uuids::to_string(uuid);
}
```

**SubTask + notional chunk construction** (`processing_tasksplit.cpp:64-96` — the ELM version mints ONE chunk per subtask with `chunkIdx` fixed at 0, per `01-DESIGN-SUBTASK-MAPPING` §2):
```cpp
SGProcessing::SubTask subtask;
//IPFS Block is the task ID for lookup
subtask.set_ipfsblock( task.ipfs_block_id() );
subtask.set_json_data( json_data );              // ELM: ModelNode { "source": "input:<work_item_id>" }
auto uuidstring = generate_uuid_with_ipfs_id(ipfsid);
subtask.set_subtaskid(uuidstring);

SGProcessing::ProcessingChunk chunk;
chunk.set_chunkid( ( boost::format( "CHUNK_%d_%d" ) % uuidstring % chunkId ).str() );
chunk.set_n_subchunks( 1 );
auto chunkToProcess = subtask.add_chunkstoprocess();
chunkToProcess->CopyFrom( chunk );
...
subTasks.push_back( std::move( subtask ) );
```
ELM deltas: exactly ONE `add_chunkstoprocess()` per subtask (1:1 with the result's single hash); `json_data` = serialized `sgns::ModelNode` whose `source` selects the work item; the splitter ALSO writes `elm_subtask_map` into the task's `json_data` root (unknown-key tolerance — see Shared Patterns).

**CMake registration** (`src/processing/CMakeLists.txt:1-19` — append the new source beside its sibling):
```cmake
add_library(processing_service
    impl/processing_core_impl.cpp
    processing_tasksplit.cpp
    processing_tasksplit_elm.cpp      # <-- add, same position convention
    processing_clocks_elm.cpp
    ...
)
set_target_properties(processing_service PROPERTIES UNITY_BUILD ON)
```

---

### `GeniusNode::ProcessImage` ELM branch (service, request-response)

**Analog:** in-file — the interim ELM block being replaced (`GeniusNode.cpp:2272-2290`) plus the non-ELM flow it sits beside (`:2296-2361`). The non-ELM loop below stays **byte-identical** (SC-4).

**The block being replaced** (`GeniusNode.cpp:2272-2290` — keep the sniff shape, delete the early return, extend the body):
```cpp
{
    // Materialize the by-value optional (quicktype getters return
    // boost::optional<T> by value -- see plan 01-01 SUMMARY lifetime note).
    const auto jobTypeOpt = procmgr->GetProcessingData().get_job_type();
    if ( jobTypeOpt && jobTypeOpt.value() == sgns::JobType::ELM_PROCESSING )
    {
        auto elmFunds = GetElmProcessCost( *procmgr );
        if ( elmFunds <= 0 )
        {
            return outcome::failure( Error::PROCESS_COST_ERROR );
        }
        return outcome::failure( Error::ELM_SUBMIT_UNAVAILABLE );   // <-- Phase 4 replaces this
    }
}
```

**The flow to mirror** (`GeniusNode.cpp:2296-2361` — cost → balance → task JSON → split → escrow → CRDT txn → enqueue):
```cpp
auto funds = GetProcessCost( *procmgr );
if ( funds <= 0 ) { return outcome::failure( Error::PROCESS_COST_ERROR ); }
if ( account_->GetUTXOManager().GetBalance() < funds )
{ return outcome::failure( Error::INSUFFICIENT_FUNDS ); }

SGProcessing::Task task;
auto uuidstring = generate_uuid_with_ipfs_id( pubsub_->GetHost()->getId().toBase58() );
json smalljson;
sgns::to_json( smalljson, procmgr->GetProcessingData() );
task.set_ipfs_block_id( uuidstring );
task.set_json_data( smalljson.dump( -1 ) );
task.set_random_seed( 0 );
task.set_results_channel( ( boost::format( "RESULT_CHANNEL_ID_%1%" ) % ( 1 ) ).str() );

processing::ProcessTaskSplitter  taskSplitter;
std::list<SGProcessing::SubTask> subTasks;
... // per-pass loop -- ELM branch replaces with the elms[] loop + elm_subtask_map write

BOOST_OUTCOME_TRY( auto manager, GetTransactionManager() );
BOOST_OUTCOME_TRY( auto result_pair, manager->HoldEscrow( funds, uuidstring ) );
auto [tx_id, escrow_data_pair] = result_pair;
auto [escrow_path, escrow_data] = escrow_data_pair;
task.set_escrow_path( escrow_path );
BOOST_OUTCOME_TRY( auto crdt_transaction,
                   CreateEscrowInfoCRDTTransaction( escrow_path, std::move( escrow_data ) ) );
auto enqueue_task_return = task_queue_->EnqueueTask( task, subTasks, crdt_transaction );
if ( enqueue_task_return.has_failure() ) { return outcome::failure( Error::DATABASE_WRITE_ERROR ); }

my_task_ids_.push_back( uuidstring );
...
return tx_id;
```

---

### Rate-record composition in `ProcessImage` (service, batch/multi-Put atomic)

**Analog:** in-file — `GeniusNode.cpp:3258-3305`. The helper's own comment prescribes the exact composition Phase 4 implements:
```cpp
outcome::result<std::shared_ptr<crdt::AtomicTransaction>> GeniusNode::CreateElmRateRecordCRDTTransaction(
    const std::string &escrow_path,
    double             maximum_processing_hours )
{
    // OD-2: record the rate actually used at hold time as a SIBLING key of
    // the escrow record (the escrow itself stays at the plain escrow_path).
    auto crdt_transaction = tx_globaldb_->BeginTransaction();

    const json rateRecord = {
        { "usd_per_hour", sgns::processing::kUsdPerHourElm },
        { "usd_per_gnus", sgns::processing::kUsdPerGnusRate },
        { "minions", sgns::processing::ElmEscrowMinions( maximum_processing_hours ) },
        { "maximum_processing_hours", maximum_processing_hours },
    };
    sgns::crdt::HierarchicalKey key( escrow_path + "/elm_rate" );
    BOOST_OUTCOME_TRY( crdt_transaction->Put(
        std::move( key ),
        sgns::base::Buffer( std::vector<uint8_t>( rateRecord.dump().begin(), rateRecord.dump().end() ) ) ) );

    // Phase 4: the production caller wires this into ProcessImage inside the
    // same CRDT transaction as CreateEscrowInfoCRDTTransaction (multi-Put
    // atomic transaction precedent: impl/TaskQueueImpl.cpp:32-67). ...
    return crdt_transaction;
}
```
**Composition rule (P4-9):** do NOT call this as a second standalone transaction. Either (a) add an overload accepting the existing `crdt_transaction` from `CreateEscrowInfoCRDTTransaction`, or (b) inline the `escrow_path + "/elm_rate"` Put onto that transaction — then `EnqueueTask(task, subTasks, crdt_transaction)` extends and commits it once. Exactly one CRDT commit per ELM submit.

---

### `TransactionManager::BuildPayoutOutputs` ELM branch (service, transform)

**Analog:** in-file — the existing even-split implementation, `TransactionManager.cpp:1104-1202`. The ELM branch keeps the same output contract (`std::vector<OutputDestInfo>`, conservation check) and adds: proportional-by-window shares, a refund output to `escrow_tx->GetSrcAddress()` (readable at the `PayEscrow` layer, `:1205+`), and an additive defaulted settlement-data parameter.

**Malformed-entry filter to keep** (`TransactionManager.cpp:1127-1147`):
```cpp
std::unordered_set<std::string>                   seen_subtask_ids;
std::vector<const SGProcessing::SubTaskResult *> valid_results;
for ( const auto &result : task_result.subtask_results() )
{
    const bool valid = !result.subtaskid().empty() && !result.developer_address().empty() &&
                       base::IsHexAddress( result.node_address() ) &&
                       result.token_id().size() == std::tuple_size_v<TokenID::ByteArray> &&
                       result.developer_cut() <= DEVELOPER_CUT_SCALE &&
                       seen_subtask_ids.insert( result.subtaskid() ).second;
    ...
}
```

**Conservation check to keep** (`TransactionManager.cpp:1186-1195` — the ELM refund output makes it hold for Σoutputs == escrow_amount):
```cpp
const auto total = std::accumulate( outputs.cbegin(), outputs.cend(), uint128_t{ 0 },
    []( const uint128_t sum, const OutputDestInfo &output )
    { return sum + output.encrypted_amount; } );
if ( total != escrow_amount )
{
    return std::errc::result_out_of_range;
}
return outputs;
```

**Arithmetic authority** (`processing_clocks_elm.hpp:45-53` — the shared integer path; mirror its conventions exactly, per `01-DESIGN-SETTLEMENT` §2):
```cpp
/// milli-hours = std::llround(hours * 1000.0); minions = milli_hours * 3 / 10
/// ($0.0003/hour x 10^6 minions/$ at kUsdPerGnusRate == 1.0, floored).
/// llround guards against 1299.999... -> 1299 truncation (Pitfall 3); the
/// final /10 floor is requestor-favorable (D-02).
uint64_t ElmEscrowMinions( double maximum_processing_hours );
```
Use `boost::multiprecision::uint128_t` for shares (already the file's idiom, `TransactionManager.cpp:1113`).

**Refund target + additive-parameter seam** (`TransactionManager.cpp:1205+` `PayEscrow` — has `escrow_tx`, calls the static builder; extend the chain `AsyncPayEscrow → PayEscrow → BuildPayoutOutputs` with a defaulted optional settlement argument so the one existing caller (`GeniusNode.cpp:2973`) stays source-compatible — assumption A1).

---

### `GeniusNode::ProcessingDone` envelope-fetch orchestration (service, fetch)

**Analog:** the `fetchOutputData` lambda, `processing_subtask_queue_accessor_impl.cpp:379-411` — the fresh-call-scoped-io_context `FileManager::LoadASync` pattern (deliberately NOT a shared running ioc):
```cpp
auto fetchOutputData =
    [this]( const std::string &outputUri ) -> outcome::result<std::vector<uint8_t>>
{
    auto        freshContext = std::make_shared<boost::asio::io_context>();
    std::vector<char> collected;
    bool        fetchSucceeded = false;

    FileManager::GetInstance().LoadASync(
        outputUri, false, false, freshContext,
        [this, &collected, &fetchSucceeded, &outputUri]( FileManager::ResultType buffers )
        {
            if ( buffers )
            {
                collected.insert( collected.end(),
                                  buffers.value()->second[0].begin(),
                                  buffers.value()->second[0].end() );
                fetchSucceeded = true;
            }
            else { m_logger->error( "FinalizeQueueProcessing fetchOutputData: failed to obtain {}: {}",
                                    outputUri, buffers.error().message() ); }
        },
        "file" );

    // No reset() needed -- this context is used exactly once (fresh per call).
    freshContext->run();
    if ( !fetchSucceeded || collected.empty() )
    {
        return outcome::failure( std::make_error_code( std::errc::io_error ) );
    }
    return std::vector<uint8_t>( collected.begin(), collected.end() );
};
```
**Call site to extend** (`GeniusNode.cpp:2908-2973` `ProcessingDone`): holds `maybe_task` (task JSON → job-type sniff) and already calls `manager_result.value()->AsyncPayEscrow( maybe_task.value().escrow_path(), taskresult, … )` — insert the ELM leg (sniff → fetch each result's envelope via the pattern above → extract `{subtaskid → window_millihours}` → pass down) before that call. `FileManager.hpp` is already included in `GeniusNode.cpp`.

---

### `ProcessingManager::ProcessInternal` ELM branch (service, request-response)

**Analog:** in-file — the non-ELM `ProcessInternal`, `ProcessingManager.cpp:1489-1668`. **The ELM branch MUST be the first conditional** (P4-1): the pass-indexing below runs immediately today and ELM jobs have no `inputs[]`:
```cpp
outcome::result<ProcessOutput> ProcessingManager::ProcessInternal( ... )
{
    //Get input index
    auto modelname = model.get_source().value();
    auto index     = GetInputIndex( modelname );
    if ( !index )
    {
        return outcome::failure( Error::MISSING_INPUT );   // <-- ELM jobs hit this TODAY
    }
    ...
    const auto passesVec = processing_.get_passes().value_or( std::vector<sgns::Pass>{} );
    const auto inputsVec = processing_.get_inputs().value_or( std::vector<sgns::IoDeclaration>{} );
    const auto &pass     = passesVec[index.value()];
```
ELM intercept shape (RESEARCH Pattern 1):
```cpp
const auto jobTypeOpt = processing_.get_job_type();   // materialize by-value optional (UB rule)
if ( jobTypeOpt && jobTypeOpt.value() == sgns::JobType::ELM_PROCESSING )
{
    return ProcessElmWorkItem( ioc, chunkhashes, model, output_locations, execCtx );
}
// ... existing pass-indexed path, byte-identical ...
```

**Deadline timer + start/end stamping to mirror** (`ProcessingManager.cpp:1545-1640` — the ELM branch sets `execCtx.deadlineMs` from funding BEFORE this point (P4-8) and stamps grab/finish around its own fetch+execute):
```cpp
boost::asio::deadline_timer deadlineTimer( *ioc );
if ( deadlineMs > 0 )
{
    deadlineTimer.expires_from_now( boost::posix_time::milliseconds( deadlineMs ) );
    deadlineTimer.async_wait( [&execCtx]( const boost::system::error_code &ec )
    {
        if ( !ec ) { execCtx.cancelToken.Cancel(); }   // D-09: deadline → unified cancel path
    } );
}
execCtx.cancelToken.SetCallback( [&deadlineTimer]() { deadlineTimer.cancel(); } );

auto startTimeUsec = std::chrono::duration_cast<std::chrono::microseconds>(
    std::chrono::system_clock::now().time_since_epoch() ).count();
...
auto endTimeUsec = std::chrono::duration_cast<std::chrono::microseconds>(
    std::chrono::system_clock::now().time_since_epoch() ).count();
```

**The failure mapping the ELM wrapper must NOT apply to envelope-bearing results** (`ProcessingManager.cpp:1648-1668` + P4-2/Pattern 2 — `CANCELLED`/`TIMED_OUT`/`BUDGET_EXCEEDED` all `return outcome::failure( Error::PROCESSING_FAILED )`, which routes to the error sink WITHOUT `CompleteSubTask` → re-grab):
```cpp
if ( processResult.error )
{
    if ( processResult.error->stage == ProcessingErrorStage::CANCELLED )
    {
        m_logger->error( "Processing cancelled" );
        buildFailureManifest();
        return outcome::failure( Error::PROCESSING_FAILED );   // <-- ELM: envelope present? publish as
    }                                                           //     success-shaped SubTaskResult instead
    ...
}
```
Envelope-present test: `!processResult.hash.empty() && chunkhashes.size() == 1` (the processor's `MakeErrorResult` already sets all three — `processing_processor_elm.cpp:44-76`).

**Processor entry consumed as-is** (`processing_processor_elm.cpp:118-140` — the fail-closed base + the ELM seam; note pre-cancel check and by-value optional materialization idiom to copy):
```cpp
ProcessingResult ElmProcessor::StartProcessingElm( std::vector<std::vector<uint8_t>> &chunkhashes,
                                                    const std::string                 &promptText,
                                                    const std::vector<std::string>    &stopStrings,
                                                    const sgns::Elm                   &elm,
                                                    const ExecutionContext            &execCtx,
                                                    std::shared_ptr<sgns::elmruntime::ElmModelCache> cache,
                                                    CapabilityValidator               *capabilityValidator )
{
    const std::string passId = elm.get_work_item_id();
    if ( execCtx.cancelToken.IsCancelled() ) { ... CANCELLED ... }
    // (b) Materialize the by-value quicktype optionals into named locals ONCE ...
    const auto generationOpt    = elm.get_generation();
    ...
```

---

### `ProcessingManager::CheckElmValidity` stop-array bounds (middleware, transform)

**Analog:** in-file — the generation-settings gate loop, `ProcessingManager.cpp:704-746` (bounds live HERE because quicktype drops `maxItems`/`minLength`/`maxLength` — P4-5):
```cpp
// Generation settings (A3 belt-and-braces): schema bounds did not
// survive codegen for optional numbers, so enforce them all here.
for ( const auto &elm : *elmsOpt )
{
    const auto generationOpt = elm.get_generation();
    if ( generationOpt )
    {
        const auto &generation = *generationOpt;
        if ( auto topP = generation.get_top_p() )
        {
            if ( *topP <= 0.0 || *topP > 1.0 )
            {
                m_logger->error( "elm generation.top_p out of range (0, 1]" );
                return outcome::failure( Error::ELM_GENERATION_SETTINGS_INVALID );
            }
        }
        ...
    }
}
```
Copy this style verbatim for `stop` (D-02): reject-at-parse with `ELM_GENERATION_SETTINGS_INVALID` on >4 entries, any entry empty or >128 UTF-8 bytes; never clamp. The function's CRITICAL lifetime note header (`:596-604`) — materialize `boost::optional<T>` into named locals — applies to the new `get_stop()` reads.

---

### Save-loop ELM branch + production-cache call site (service, file-I/O)

**Analog (save loop):** in-file — `ProcessingManager.cpp:1847-1965`. The existing guard skips jobs with no `outputs[]` (P4-4), so the ELM branch synthesizes the URL and feeds the SAME mechanics:
```cpp
if ( processResult.output_buffers && !outputs.empty() )
{
    ...
    FileManager::GetInstance().InitializeSingletons();
    ...
    FileManager::GetInstance().SaveASync( outputUrl,
                                          outcome::success( saveBuffers ),
                                          ioc,
                                          [this, outputUrl]( const FileManager::ResultType &result ) { ... },
                                          saveLocation );
    // Dual-save: persist a local copy when output is IPFS
    getURLComponents( outputUrl, urlPrefix, urlPath, urlExt );
    if ( urlPrefix == "ipfs" )
    {
        auto cacheDir = FileManager::GetInstance().getCacheDir();
        if ( !cacheDir.empty() )
        {
            auto localUrl = "file://" + cacheDir + "/results/" + output.get_name() + outputFileName;
            FileManager::GetInstance().SaveASync( localUrl, outcome::success( saveBuffers ),
                                                  ioc, nullptr, nullptr );
        }
    }
    ...
    if ( hasSaves ) { ioc->reset(); ioc->run(); /* collect locationPtrs → output_locations */ }
}
```
ELM branch: synthesize `outputUrl` under `cacheDir + "/results/"` with an `ipfs://` primary save (D-06/D-09), same `saveLocation` shared_ptr collection so `ipfs_results_data_id` carries `ipfs://CID` back (the scheme gate at `ValidateResultData :638-672` enforces it downstream).

**Analog (cache):** `ElmModelCache.cpp:295-316` — the fail-closed factory with ZERO callers today:
```cpp
outcome::result<std::shared_ptr<ElmModelCache>> ElmModelCache::CreateProductionElmModelCache( SmokeCheckFn smokeCheck )
{
    const auto  logger    = CacheLogger();
    std::string cacheDir;
    try { cacheDir = FileManager::GetInstance().getCacheDir(); }
    catch ( const std::exception &e ) { ...; return outcome::failure( ElmRuntimeError::CACHE_DIR_UNSET ); }
    if ( cacheDir.empty() )
    {
        // D-03 / P2-1: empty in every standalone process (set only via
        // setBitswap) -- NEVER guess a default.
        logger->error( "ElmModelCache: FileManager cache dir is unset -- failing closed (D-03)" );
        return outcome::failure( ElmRuntimeError::CACHE_DIR_UNSET );
    }
    return Create( ( fs::path( cacheDir ) / "elmruntime" ).string(), MakeFileManagerFetchFn(), std::move( smokeCheck ) );
}
```
Construction rule (P4-7): lazily at FIRST ELM subtask (after node startup's `setBitswap`, `GeniusNode.cpp:1436-1437`), cache the `shared_ptr`, map construction failure to a terminal error envelope (Pattern 2) — never at static/init time.

---

### Schema amendments + regen (config)

**Analog (stop array):** in-file — `gnus-processing-schema.json:161-184` (`ElmGeneration` — add `stop` beside these) and the root `tags` array-of-string precedent `:29-34`:
```json
"tags": {
  "type": "array",
  "description": "Tags for categorizing this definition",
  "items": { "type": "string" }
},
```
`stop` shape: `{"type": "array", "items": {"type": "string", "minLength": 1, "maxLength": 128}, "maxItems": 4}` — the description notes the C++ gate (`CheckElmValidity`) enforces the bounds because codegen drops them. Expect getter `boost::optional<std::vector<std::string>> get_stop()` (A4 — follows the `tags` precedent, `SgnsProcessing.hpp:63`).

**Analog (embedding_file role):** in-file — the closed role pattern, `elm-model-manifest-schema.json:16-17`:
```json
"description": "Artifact role: llm_config, llm_model, llm_weight, tokenizer_file, or context_file",
"pattern": "^(llm_config|llm_model|llm_weight|tokenizer_file|context_file)$"
```
becomes `…|context_file|embedding_file)$`. Mirror the same edit in `gnus-processing-schema.json`'s `ElmModelArtifact` def (`:188-195`). Regen BOTH generated sets via the quicktype pipeline (`README.md` + `.github/workflows/generate-headers.yml` commands); **zero hand-edits** to `generated/`. Optional-role precedent: `context_file` is in `kRoleFilenames` but NOT `kRequiredRoles` — `embedding_file` follows identically.

---

### `ElmEnvelope` stamps (model)

**Analog:** in-file — the six-key envelope, `ElmEnvelope.hpp:47-63` + `ElmEnvelopeToJson` `ElmEnvelope.cpp:43-56`:
```cpp
struct ElmEnvelope
{
    std::string                     work_item_id;       ///< schema-charset id, carried as data
    std::string                     text;               ///< VisibleText on stop-string match (D-07), else full
    int64_t                         prompt_tokens = 0;  ///< LlmContext::prompt_len
    int64_t                         completion_tokens = 0; ///< LlmContext::output_tokens.size() (the authority)
    ElmFinishReason                 finish_reason = ElmFinishReason::Error;
    std::string                     model_manifest_hash; ///< provenance: ElmCachePin::GetHash() (SC-4)
    std::optional<ElmEnvelopeError> error;              ///< present only when finish_reason == Error
};

std::string ElmEnvelopeToJson( const ElmEnvelope &envelope )
{
    nlohmann::json doc;
    doc["work_item_id"]        = envelope.work_item_id;
    ...
    doc["model_manifest_hash"] = envelope.model_manifest_hash;
    if ( envelope.finish_reason == ElmFinishReason::Error && envelope.error.has_value() ) { ... }
    return doc.dump();
}
```
Add `grab_time_usec`/`finish_time_usec` as additive `int64_t` fields (defaulted `= 0`) + two `doc[...]` lines — key-addition-compatible, Doxygen comments per field, keep the zero-MNN-includes rule stated in the header's banner.

---

### `ElmManifest.cpp` role table (utility)

**Analog:** in-file — `ElmManifest.cpp:36-48`:
```cpp
const char *const kRoleFilenames[] = {
    "llm_config", "llm_config.json",   //
    "llm_model", "llm.mnn",            //
    "llm_weight", "llm.mnn.weight",    //
    "tokenizer_file", "tokenizer.txt", //
    "context_file", "context.json",    //
};

/// The roles MNN's Llm::load() requires unconditionally (llm.cpp:265-283);
/// context_file is optional extra material.
const char *const kRequiredRoles[] = { "llm_config", "llm_model", "llm_weight", "tokenizer_file" };
```
Add one interleaved pair `"embedding_file", "embeddings_bf16.bin"` to `kRoleFilenames` ONLY (D-03 — NOT to `kRequiredRoles`). Note `IsValidRole`'s even-index-only comparison (`:52-63`) — the pair structure keeps it correct automatically.

---

### Test files (test, event-driven wait-condition)

**Analog A — node fixture + ELM JSON builder + flip-to-acceptance:** `SuperGenius/test/src/account/elm_cost_clocks_test.cpp`:
```cpp
// Valid minimal elm_processing job (D-04) -- matches the plan 01-01 contract.
// Escaped-string composition: multi-line raw strings corrupt on CRLF checkouts.
static std::string BuildElmJobJson( const std::string &extras = "" )
{
    const std::string elm = "{"                          //
                            "\"work_item_id\": \"w-1\","  //
                            "\"elm_type\": \"causal_lm\","
                            "\"model_manifest_uri\": \"ipfs://m1\","
                            "\"model_manifest_hash\": \"sha256:aaa\","
                            "\"input_uri\": \"ipfs://i1\"}";
    return "{"                                       //
           "\"name\": \"elm-job\","                  //
           ...
           "\"elms\": [" + elm + "]" + extras + "}";
}
```
Fixture pattern (`:117-165`): `removeAllWithRetry` → `create_directories` → `WriteNetworkConfig`/`WriteSgnsConfig(is_processor=true)` → `MemorySecureStorage` factory → `GeniusNode::New(…, sgns::FromPrivateKey{…})` → `SetChainlistFetcher(OfflineChainlistFetcher())` → `Blockchain::SetAuthorizedFullNodeAddress(node_->GetAddress())` → `test::assertWaitForCondition( node READY, 4000000ms )`. The E2E (D-08) reuses exactly this single-node shape; the interim-rejection test leg is the model for the flip-to-acceptance assertion (Phase 4 inverts it: submit now SUCCEEDS).

**Analog B — both-roles topology / MintTokens / PostJobs idioms:** `SuperGenius/test/src/processing_multi/processing_multi_test.cpp` (startup, config, teardown).

**Test CMake (SuperGenius side)** — `test/src/account/CMakeLists.txt:25-42`:
```cmake
addtest(elm_cost_clocks_test
    elm_cost_clocks_test.cpp
)

target_link_libraries(elm_cost_clocks_test
    genius_node_test
    json_secure_storage
)

if(MSVC)
    target_link_options(elm_cost_clocks_test PUBLIC /WHOLEARCHIVE:$<TARGET_FILE:genius_node_test>)
elseif(APPLE)
    target_link_options(elm_cost_clocks_test PUBLIC -force_load "$<TARGET_FILE:genius_node_test>")
else()
    target_link_options(elm_cost_clocks_test PUBLIC
        "-Wl,--whole-archive"
        "$<TARGET_FILE:genius_node_test>"
        "-Wl,--no-whole-archive"
    )
endif()
```

**Test CMake (SGProcessingManager side)** — gating + TIMEOUT precedent, e.g. `test/elmruntime/CMakeLists.txt`:
```cmake
if(SGPROC_TEST_DISCOVERY AND NOT CMAKE_CROSSCOMPILING)
    gtest_discover_tests(sgprocelmruntime_cache_test DISCOVERY_TIMEOUT 60)
endif()
set_tests_properties(sgprocelmruntime_cache_test PROPERTIES TIMEOUT 300)
```
E2E budget: TIMEOUT ≥ 1800s for the empty-cache leg (×4 over observed; the ~557MB model download is the long pole — P4-10). Overtime leg as a separate CASE in the same binary, after the cache is warm (RESEARCH Open Question 3). Set `SGPROC_ELM_TEST_MODEL_DIR` before CTest; `GTEST_SKIP` when unset (existing convention). Wait-conditions only — `testutil/wait_condition.hpp` (`assertWaitForCondition`), never `sleep_for`.

---

## Shared Patterns

### Job-type sniffing + optional materialization (apply to EVERY new read site)
**Source:** `GeniusNode.cpp:2274-2278`, `ProcessingManager.cpp:596-604`, `ElmManifest.cpp:13-21`
```cpp
// Materialize the by-value optional (quicktype getters return
// boost::optional<T> by value -- dereferencing the call result directly
// yields a reference into a temporary that dies at end of full expression: UB).
const auto jobTypeOpt = procmgr->GetProcessingData().get_job_type();
if ( jobTypeOpt && jobTypeOpt.value() == sgns::JobType::ELM_PROCESSING ) { ... }
```
Exactly two submit-side sniff call sites by design (splitter + cost in `ProcessImage`); one worker-side (`ProcessInternal`); one settlement-side (`ProcessingDone`).

### Error handling (apply to all new/modified C++)
**Source:** repo-wide idiom — `BOOST_OUTCOME_TRY` + structured `Error::` / `ElmRuntimeError` enums; log-then-return-failure (see `CheckElmValidity` gates, `CreateProductionElmModelCache`). No exceptions on expected-failure paths; the `ProcessInternal` catch-all (`ProcessingManager.cpp:1968-1976`) is the backstop, not the pattern.

### Cross-generated-set TU isolation (D-P3-2 / P4-6)
**Source:** `processing_processor_elm.cpp:9-14, 133-137`, `ElmManifest.cpp:13-27`
Root `generated/` set (`sgns::Elm`) and `generated/elmruntime-manifest/` must NEVER appear in one TU (`ClassMemberConstraints`/`ElmType` redefinition). Splitter/routing/settlement code includes the ROOT set only; manifest-set access stays behind `ElmEntryPreflight`'s plain-value bridge.

### Worker-thread / callback discipline
**Source:** RESEARCH Carried Forward + `ProcessInternal`'s timer lambda shape
Model download/hash/generation never on asio handlers; `weak_from_this()` in every new timer/callback in `GeniusNode`; capture-by-ref only where the scope provably outlives the async op (the `fetchOutputData` lambda's fresh-ioc pattern is the safe template).

### Non-ELM parity invariant (SC-4, applies to every modified file)
Every ELM addition is an additive conditional beside the existing path; the non-ELM path stays byte-identical. The in-file analogs above double as the regression baseline — the E2E-02 gate diffs behavior, not intent.

### Submodule landing order (Pattern 5)
SGProcessingManager (schema + regen + envelope + manifest + ProcessInternal/cache/save-loop) → SuperGenius pointer bump (splitter + ProcessImage + settlement + tests) → root. Innermost-first commits; MNN untouched.

## No Analog Found

None — every file has an in-codebase analog (this phase is integration of shipped Phase 1–3 components; the RESEARCH.md "Code Examples" sketches cover the small genuinely-new seams: the `elm_subtask_map` JSON write and the ELM save-branch URL synthesis, both of which follow the in-file conventions cited above).

## Metadata

**Analog search scope:** `SuperGenius/src/{processing,account}`, `SuperGenius/SGProcessingManager/src/{processingbase,elmruntime,processors}`, `SGProcessingManager/{include/elmruntime,schemas,generated}`, both test trees, both CMake sets
**Files scanned:** ~20 (14 classified + supporting headers/CMake/schema)
**Pattern extraction date:** 2026-09-14
