# Phase 1: ELM Job Model & Funding - Pattern Map

**Mapped:** 2026-09-10
**Files analyzed:** 14 (new/modified)
**Analogs found:** 14 / 14 (12 strong, 2 partial — greenfield utility/design deliverables)

All excerpts verified against the CURRENT working tree (SuperGenius `dev_elmruntime` @ `7f498073a`, SGProcessingManager `dev_elmruntime` @ `8fcd2be`). Line numbers drift-checked against RESEARCH.md F10 (±5 lines, no semantic drift).

---

## File Classification

| # | New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|-------------------|------|-----------|----------------|---------------|
| 1 | `SGProcessingManager/gnus-processing-schema.json` | model (schema) | transform (schema → generated parsers) | existing budget-field + enum + pattern entries in the same file (`:235-253`, `:117`, `:12`) | exact |
| 2 | `SGProcessingManager/generated/*.hpp` (Elm.hpp, ElmFunding.hpp, …) | generated model | transform | `generated/SgnsProcessing.hpp` (constraint members `:27-36`, `:73`) | exact (regen, zero hand edits) |
| 3 | `SGProcessingManager/include/processingbase/ProcessingManager.hpp` | model (error contract) | n/a | same file's `Error` enum (`:82-95`) | exact |
| 4 | `SGProcessingManager/src/processingbase/ProcessingManager.cpp` — Init gates + default-fill + `CheckElmValidity` | service (parse/validate) | request-response | `Init` pre-parse interception (`:523-561`) + `CheckProcessValidity` (`:586+`) + budget `value_or` (`:1311-1313`) | exact |
| 5 | `SGProcessingManager/test/<new>/elm_schema_test.cpp` + `CMakeLists.txt` | test | n/a | `test/execution/CMakeLists.txt:14-22` gating pattern; `token_amount_test.cpp` TEST_P matrix | exact |
| 6 | `SuperGenius/src/processing/processing_clocks_elm.hpp` (+ `.cpp` if non-header-only) | utility | transform (hours → 3 clocks + escrow minions) | `TokenAmount` static-utility class (`TokenAmount.hpp/.cpp`) | partial (new file; pattern precedent exists) |
| 7 | `SuperGenius/src/account/GeniusNode.hpp` — `GetElmProcessCost` declaration | service (cost) | request-response | `GetProcessCost` declaration (`GeniusNode.hpp:367`) | exact |
| 8 | `SuperGenius/src/account/GeniusNode.cpp` — `ProcessImage` ELM sniff branch + `GetElmProcessCost` + rate-record helper | service (cost/submit) | request-response | `GetProcessCost` (`GeniusNode.cpp:2381-2410`); branch site `:2265` | exact |
| 9 | `SuperGenius/src/account/GeniusNode.cpp` — rate-record sibling CRDT Put (extend `CreateEscrowInfoCRDTTransaction` or sibling helper) | service (persistence) | CRUD (atomic transaction) | `TaskQueueImpl::EnqueueTask` multi-Put (`impl/TaskQueueImpl.cpp:32-67`); `CreateEscrowInfoCRDTTransaction` (`GeniusNode.cpp:3206-3219`) | exact |
| 10 | `SuperGenius/src/processing/processing_node.cpp` (+ `processing_service.cpp` feed) — `SetProcessingTimeout(derived)` before `CreateSubTaskQueue` | config/wiring | event-driven | `ProcessingNode::New` queue-creation flow (`processing_node.cpp:11-46`); `CreateQueue` timeout write (`processing_subtask_queue_manager.cpp:76`) | exact |
| 11 | `SuperGenius/src/processing/processing_subtask_queue_accessor_impl.cpp` — ELM validation-mode defensive assertion at `FinalizeQueueProcessing` | middleware (gate) | event-driven | existing task-JSON parse at `FinalizeQueueProcessing` (`accessor_impl.cpp:337-375`) | exact |
| 12 | Settlement extension (measured wall-clock + refund output) — **design pinned Phase 1, implemented Phase 4** | service (settlement) | transform | `BuildPayoutOutputs` (`TransactionManager.cpp:1097-1197`) | exact analog for the Phase-4 extension; Phase 1 ships design + rate-record only |
| 13 | `SuperGenius/test/src/…` — clocks + cost unit tests | test | n/a | `token_amount_test.cpp` (parameterized `TEST_P`, `:19-64`); `account_management_test.cpp:308` direct `GetProcessCost` call | exact |
| 14 | `SuperGenius/test/src/processing/…` — lock-timeout wiring test | test | n/a | `processing_subtask_queue_manager_test.cpp:44-89` (`QueueCreating`, mock channel + snapshot asserts) | exact |

---

## Pattern Assignments

### 1. `gnus-processing-schema.json` (model/schema, transform)

**Analog:** the same file's existing field definitions — budget fields with `minimum`+`default`, enum fields, pattern-constrained strings.

**Bounds-bearing numeric field** (`:237-241` — the pattern `CheckConstraint` turns into `min/max_int_value` at parse):
```json
"estimated_gpu_memory_bytes": {
  "type": "integer",
  "minimum": 0,
  "default": 0,
  "description": "Estimated GPU memory needed for this pass in bytes. 0 means no estimate provided."
},
```

**Enum field** (`:117` — unknown strings throw in generated `from_json`, caught as `INVALID_JSON`):
```json
"format": {
  "type": "string",
  "description": "Data format (e.g., RGBA8, FLOAT32)",
  "enum": ["RGBA8", "RGB8", "FLOAT32", "FLOAT16", "INT32", "INT16", "INT8", "FP4_ULTRA"]
}
```

**Pattern-constrained id** (`:12` — copy this charset for `work_item_id`; Security Domain requires it):
```json
"name": {
  "type": "string",
  "description": "Unique name for this processing definition",
  "pattern": "^[A-Za-z0-9_-]+$"
}
```

**Root `required` to relax** (`:7` — remove `passes`/`inputs`/`outputs` for D-04's minimal ELM job; enforce for non-ELM in C++ gate, file #4):
```json
"required": ["name", "version", "gnus_spec_version", "passes", "inputs", "outputs"],
```

**Regen command** (`README.md:22-38`; run locally — CI workflow fires only on `main`):
```bash
quicktype --src-lang schema --lang cpp --top-level SGNSProcessing \
  --code-format with-getter-setter --const-style west-const \
  --namespace sgns --type-style pascal-case --member-style underscore-case \
  --boost --source-style multi-source --include-location global-include \
  --out generated/SGNSProcMain.hpp gnus-processing-schema.json
```
New headers auto-join the build via `target_include_directories(ProcessingBase ... ../../generated)` (`src/processingbase/CMakeLists.txt:8`) — no CMake edits.

**Verified limits (Pitfall 6):** `minItems`, `uniqueItems`, `if/then/else`, `default`-application do NOT survive codegen. Bounds/pattern/enum are free; everything else is a C++ gate.

---

### 2. `generated/*.hpp` (generated model)

**Analog:** `generated/SgnsProcessing.hpp:25-36` — constraint members wired in the constructor; `:73` shows the live `gnus_spec_version == 1` check (D-06 basis):
```cpp
SgnsProcessing() :
    gnus_spec_version_constraint(boost::none, boost::none, 1, 1, boost::none, boost::none, boost::none),
    name_constraint(boost::none, boost::none, boost::none, boost::none, boost::none, boost::none, std::string("^[A-Za-z0-9_-]+$")),
    version_constraint(boost::none, boost::none, boost::none, boost::none, boost::none, boost::none, std::string("^\\d+\\.\\d+(\\.\\d+)?$"))
{}
```
NEVER hand-edit — regen wipes. The `CheckConstraint` machinery that makes bounds free lives in `generated/helper.hpp:84-140` (throws `ValueTooLowException` / `ValueTooHighException` / `InvalidPatternException` from `set_*` during `from_json`).

---

### 3. `ProcessingManager.hpp` Error enum (model/error contract)

**Analog:** the hand-written enum itself (`include/processingbase/ProcessingManager.hpp:82-95`). New ELM values start at 14 (`DUPLICATE_WORK_ITEM_ID`, `ELM_VALIDATION_UNIMPLEMENTED`, `ELM_SUBMIT_UNAVAILABLE`, …):
```cpp
enum class Error
{
    PROCESS_INFO_MISSING     = 1,
    INVALID_JSON             = 2,
    // …
    RENDER_SHADER_MISSING    = 12,
    UNKNOWN_PASS_TYPE        = 13,
};
```
This enum is NOT generated — hand-edits here are sanctioned.

---

### 4. `ProcessingManager.cpp` — Init gates + default-fill (service, request-response)

**Analog A — pre-parse raw-JSON interception** (`:523-561`): recognized-set loops over raw `nlohmann::json` BEFORE `sgns::from_json`, returning dedicated `Error` codes. Use this shape for unknown `validation`/`elm_type` strings (Pitfall 7) and any raw-JSON context the generic catch would collapse:
```cpp
if ( data.contains( "passes" ) && data[ "passes" ].is_array() )
{
    static const std::set<std::string> kRecognizedPassTypes    = { "compute", "data_transform",
                                                                    "inference", "render", "retrain" };
    // …
    if ( kRecognizedPassTypes.find( passType ) == kRecognizedPassTypes.end() )
    {
        m_logger->error( "Job definition references an unrecognized pass type: " + passType );
        return outcome::failure( Error::UNKNOWN_PASS_TYPE );
    }
}
```

**Analog B — catch ladder** (`:566-578`): bounds/enum throws from quicktype land here as `INVALID_JSON` — free for schema-declared constraints:
```cpp
catch ( const nlohmann::json::exception &e )
{
    return outcome::failure( Error::INVALID_JSON );
}
catch ( const std::exception &e )
{
    // quicktype-generated enum from_json functions … throw a plain std::runtime_error
    return outcome::failure( Error::INVALID_JSON );
}
```

**Analog C — typed post-parse checks** (`:586+`, `CheckProcessValidity`): per-pass `m_logger->error` + `outcome::failure` with specific codes. Use for duplicate `work_item_id` (D-07), non-ELM-requires-passes (root-`required` relaxation guard), `exact|redundant` unimplemented (D-13, post-parse — they parse fine, refused by policy):
```cpp
case PassType::INFERENCE:
{
    if ( !pass.get_model() )
    {
        m_logger->error( "Inference json has no model" );
        return outcome::failure( Error::MODEL_MISSING );
    }
```

**Analog D — default-fill at consumption** (`:1311-1313`): quicktype does NOT apply schema `default`s; optionals arrive as `boost::none` and defaults are `value_or` at the read site. Build ONE normalization helper (e.g. `GetElmJobNormalized()`) so clocks + cost read exactly one defaulted view:
```cpp
uint64_t gpuMemoryBudget      = pass.get_estimated_gpu_memory_bytes().value_or( 0 );
uint64_t outputArtifactBudget = pass.get_max_output_artifact_bytes().value_or( 0 );
uint64_t deadlineMs           = pass.get_per_pass_deadline_ms().value_or( 0 );
```

---

### 5. SGProcessingManager parse-rejection test (test)

**Analog A — CMake gating** (`test/execution/CMakeLists.txt:14-22`): unconditional `add_test` + `gtest_discover_tests` gated on `SGPROC_TEST_DISCOVERY` (defined only by the standalone build) and `NOT CMAKE_CROSSCOMPILING`:
```cmake
add_executable(sgprocmanagerexec_cancellation_test cancellation_test.cpp)
target_link_libraries(sgprocmanagerexec_cancellation_test PRIVATE GTest::gtest_main SGExecution)
add_test(NAME sgprocmanagerexec_cancellation_test COMMAND sgprocmanagerexec_cancellation_test)
if(SGPROC_TEST_DISCOVERY AND NOT CMAKE_CROSSCOMPILING)
    gtest_discover_tests(sgprocmanagerexec_cancellation_test DISCOVERY_TIMEOUT 60)
endif()
```
Register the new `test/<dir>/` via `add_subdirectory` in `SGProcessingManager/test/CMakeLists.txt` (existing list: capability, execution, artifacts, capture, util, processors).

**Analog B — parameterized matrix** (`SuperGenius/test/src/account/token_amount_test.cpp:19-64`): `TestWithParam<struct>` + `std::variant<uint64_t, std::errc>` expected + `INSTANTIATE_TEST_SUITE_P` — the exact shape for the parse-rejection matrix (bounds, duplicates, unknown enums, unimplemented modes):
```cpp
struct ParseMinionsParam
{
    std::string                       input;
    std::variant<uint64_t, std::errc> expected;
};

class ParseMinionsTest : public ::testing::TestWithParam<ParseMinionsParam> {};

TEST_P( ParseMinionsTest, HandlesValidAndInvalidStrings )
{
    auto [input, expected] = GetParam();
    auto r                 = TokenAmount::ParseMinions( input );
    if ( std::holds_alternative<uint64_t>( expected ) )
    {
        EXPECT_TRUE( r.has_value() );
        EXPECT_EQ( r.value(), std::get<uint64_t>( expected ) );
    }
    else
    {
        EXPECT_TRUE( r.has_error() );
        EXPECT_EQ( r.error(), std::make_error_code( std::get<std::errc>( expected ) ) );
    }
}

INSTANTIATE_TEST_SUITE_P( ParseMinionsCases, ParseMinionsTest, ::testing::Values(
    ParseMinionsParam{ "0.000001", 1ULL },
    ParseMinionsParam{ "invalid", std::errc::invalid_argument } ) );
```

---

### 6. `processing_clocks_elm.hpp` (utility, transform) — NEW FILE

**Closest analog:** `TokenAmount` static-utility class (`SuperGenius/src/account/TokenAmount.hpp:24-31`, `.cpp:14-19`) — namespaced constants + static factory functions + `outcome::result` returns:
```cpp
namespace sgns
{
    class TokenAmount
    {
    public:
        /// Fixed-point precision (1 minion = 10^-6 GNUS)
        static constexpr uint64_t PRECISION = 6;
        // …
        static outcome::result<std::shared_ptr<TokenAmount>> New( uint64_t raw_minions );
```
Follow its constants-first shape (`kLockGraceSeconds`, `kUsdPerHour`, rate constant) and RESEARCH's sketch:
```cpp
namespace sgns::processing
{
    struct ElmClocks
    {
        std::chrono::milliseconds deadline;      // = maximum_processing_hours, exact (D-08)
        std::chrono::milliseconds lockTimeout;   // = deadline + kLockGrace (60s, tunable)
        uint64_t                  escrowMinions; // = llround(hours*1000) * 3 / 10 at rate 1.0
    };
    ElmClocks DeriveElmClocks( double maximum_processing_hours );
}
```
**Integer-math rule (Pitfall 3):** `std::llround(hours * 1000.0)` for escrow-at-hold (round UP deterministically); never bare `uint64_t(hours*1000)` — `1.3 × 1000 == 1299.99…`.

---

### 7-8. `GeniusNode` cost branch (service, request-response)

**Analog — `GetProcessCost`** (`GeniusNode.cpp:2381-2410`, public, unit-testable without a node): parse input from `procmgr`, log-and-return-0 on failure. `GetElmProcessCost` mirrors this signature but **never calls `GetGNUSPrice()`** (FUND-01):
```cpp
uint64_t GeniusNode::GetProcessCost( const sgns::sgprocessing::ProcessingManager &procmgr )
{
    auto blockLen = procmgr.ParseBlockSize();
    if ( !blockLen )
    {
        node_logger_->error( "ParseBlockSize failed" );
        return 0;
    }
    auto maybeGnusPrice = GetGNUSPrice();
    if ( !maybeGnusPrice )
    {
        node_logger_->error( "GetGNUSPrice failed: {}", maybeGnusPrice.error().message() );
        return 0;
    }
    // … CalculateCostMinions …
}
```
**Declaration site** (`GeniusNode.hpp:367`): place `GetElmProcessCost` directly beside it with a Doxygen `@brief/@param/@return` block (header convention):
```cpp
uint64_t GetProcessCost( const sgns::sgprocessing::ProcessingManager &procmgr );
```

**Branch point** (`GeniusNode.cpp:2263-2270` in `ProcessImage`): the ELM sniff wraps ONLY the cost selection; `GetProcessCost` body stays byte-for-byte unchanged (SC-5):
```cpp
BOOST_OUTCOME_TRY( auto procmgr, sgns::sgprocessing::ProcessingManager::Create( jsondata ) );

auto funds = GetProcessCost( *procmgr );
if ( funds <= 0 )
{
    return outcome::failure( Error::PROCESS_COST_ERROR );
}
```
Interim ELM behavior: structured not-yet-splittable error before `HoldEscrow` (`:2320`) — holding without a completable task strands reserved UTXOs (Open Question 1; confirm at plan review).

---

### 9. Rate-record sibling CRDT Put (service/persistence, transactional)

**Analog A — multi-Put atomic transaction** (`impl/TaskQueueImpl.cpp:40-67`): N sibling keys in ONE `AtomicTransaction`, single `Commit` — the atomicity pattern the rate record rides:
```cpp
if ( !crdt_transaction )
{
    crdt_transaction = db_->BeginTransaction();
}
// … per-subTask Put( HierarchicalKey( TaskKeys::SubTaskKey( … ) ), value ) …
BOOST_OUTCOME_TRY(
    crdt_transaction->Put( sgns::crdt::HierarchicalKey( TaskKeys::TaskKey( task.ipfs_block_id() ) ),
                           std::move( taskValue ) ) );
BOOST_OUTCOME_TRY(
    crdt_transaction->Put( sgns::crdt::HierarchicalKey( TaskKeys::ClaimableTaskKey( task.ipfs_block_id() ) ),
                           std::move( claimableValue ) ) );
BOOST_OUTCOME_TRY( crdt_transaction->Commit( { processing_topic_ } ) );
```

**Analog B — the escrow record itself** (`GeniusNode.cpp:3206-3219`): extend this helper (or add a sibling call in the same transaction at `ProcessImage:2330`) with `HierarchicalKey(escrow_path + "/elm_rate")`:
```cpp
outcome::result<std::shared_ptr<crdt::AtomicTransaction>> GeniusNode::CreateEscrowInfoCRDTTransaction(
    std::string        path,
    sgns::base::Buffer value )
{
    auto crdt_transaction = tx_globaldb_->BeginTransaction();
    sgns::crdt::HierarchicalKey key( path );
    BOOST_OUTCOME_TRY( crdt_transaction->Put( std::move( key ), std::move( value ) ) );
    return crdt_transaction;
}
```
`EscrowTx` proto has NO metadata field (`SGTransaction.proto:120-125`) — sibling key is the only no-proto-change option. Committed atomically when `EnqueueTask` commits.

---

### 10. `SetProcessingTimeout` wiring (config/wiring, event-driven)

**Analog A — the wire target** (`processing_subtask_queue_manager.cpp:76` inside `CreateQueue`, `:39-118`): the timeout is written into the queue proto ONCE at creation; peers inherit it via gossip. `SetProcessingTimeout` (`:27-31`) called later only changes the local member — call it BEFORE `CreateSubTaskQueue`:
```cpp
processingQueue->set_processing_timeout_length( m_processingTimeout.count() );
```
Constructor default is 15s (`:21`) — do NOT touch globally:
```cpp
m_processingTimeout( std::chrono::seconds( 15 ) ),
```

**Analog B — the wiring site** (`processing_node.cpp:11-46`, `ProcessingNode::New`): `CreateSubTaskQueue` runs at the end of `New`; thread the derived timeout (or parsed funding) into this constructor chain — task JSON is reachable via `m_pendingTask` / `EnqueueSubTasks` return (`processing_service.cpp:526-535, 667-700`):
```cpp
node->Initialize( processingQueueChannelId, msSubscriptionWaitingDuration );
node->InitTTL();
if ( !node->AttachTo( processingQueueChannelId ) )
{
    node = nullptr;
}
else
{
    if ( !subTasks.empty() )
    {
        if ( !node->CreateSubTaskQueue( std::move( subTasks ) ) )
        {
            node = nullptr;
        }
    }
}
```
**Lock semantics the derived value feeds** (`processing_subtask_queue.cpp:38-56`): `LockItem` sets expiration from the queue's proto field — the unit-testable no-re-grab property (SC-3):
```cpp
mItem->set_lock_node_id(m_localNodeId);
mItem->set_lock_timestamp( now );
mItem->set_lock_expiration_timestamp( now + m_queue->processing_timeout_length());
```

---

### 11. `FinalizeQueueProcessing` validation-mode assertion (middleware/gate, event-driven)

**Analog — the existing task-JSON parse** (`processing_subtask_queue_accessor_impl.cpp:337-375`): the D-12 read-from-schema site already exists; reading `validation` from the same `parsedProcessing` is a three-line extension. Copy the fail-safe catch exactly (adversarial `json_data` must never crash the validating node):
```cpp
try
{
    auto json = nlohmann::json::parse( taskResult.value().json_data() );
    sgns::from_json( json, parsedProcessing );
    auto params = parsedProcessing.get_parameters();
    if ( params )
    {
        jobParametersStorage = params.value();
        jobParameters        = &jobParametersStorage;
    }
}
catch ( const std::exception &e )
{
    // T-15-08: malformed/adversarial Task.json_data() must never crash the
    // validating node -- log and fall through …
    m_logger->warn( "FinalizeQueueProcessing: failed to resolve job parameters from "
                    "Task.json_data(): {}", e.what() );
    jobParametersStorage.clear();
    jobParameters = nullptr;
}
```

---

### 12. Settlement extension — design deliverable (transform; Phase-4 implementation)

**Analog — `BuildPayoutOutputs`** (`TransactionManager.cpp:1097-1197`): the shape the Phase-4 refund extension modifies. Key mechanics to preserve: `uint128_t` money math, malformed-entry filter (warn + skip, never block), total-conservation check:
```cpp
const auto burn      = ( static_cast<uint128_t>( escrow_amount ) * burn_basis_points ) / BASIS_POINTS_TOTAL;
const auto available = static_cast<uint128_t>( escrow_amount ) - burn;

const bool valid = !result.subtaskid().empty() && !result.developer_address().empty() &&
                   base::IsHexAddress( result.node_address() ) &&
                   result.token_id().size() == std::tuple_size_v<TokenID::ByteArray> &&
                   result.developer_cut() <= DEVELOPER_CUT_SCALE &&
                   seen_subtask_ids.insert( result.subtaskid() ).second;
```
```cpp
const auto per_result = available / valid_results.size();
const auto dust       = available % valid_results.size();
```
```cpp
const auto total = std::accumulate( outputs.cbegin(), outputs.cend(), uint128_t{ 0 },
    []( const uint128_t sum, const OutputDestInfo &output )
    { return sum + output.encrypted_amount; } );
if ( total != escrow_amount )
{
    return std::errc::result_out_of_range;
}
```
Refund source address available at `PayEscrow` (`:1240` region — `escrow_tx->GetSrcAddress()` already read for the CRDT topic). Phase 1 delivers: design note + rate-record (file #9) + `ElmClocks.escrowMinions` (file #6); `BuildPayoutOutputs` itself is untouched this phase.

---

### 13. Cost/clocks unit tests (test)

**Analog A** — parameterized math matrix: `token_amount_test.cpp:19-64` (excerpted in #5B); instantiate with hours→minions cases (`1.0h→300`, `24h→7200`, sub-milli-hour→0 via D-02 truncation, `1.3h` milli-hour rounding per Pitfall 3).
**Analog B** — direct public-method call, no node needed: `account_management_test.cpp:296-308` builds a `ProcessingManager::Create(json_data)` then calls cost directly:
```cpp
auto        procmgr   = sgns::sgprocessing::ProcessingManager::Create( json_data );
auto        cost      = node_requester->GetProcessCost( *procmgr.value() );
```
**CMake** — SuperGenius `addtest` wrapper (`cmake/functions.cmake:8-28`) auto-links GTest, adds xunit output, sets `TIMEOUT 600`, and sets output dirs; per-test registration follows `test/src/account/CMakeLists.txt:5-12`:
```cmake
addtest(token_amount_test
    token_amount_test.cpp
)

target_link_libraries(token_amount_test
    genius_node_test
)
```

---

### 14. Lock-timeout wiring test (test)

**Analog — `QueueCreating`** (`test/src/processing/processing_subtask_queue_manager_test.cpp:44-89`): mock `ProcessingSubTaskQueueChannelImpl` with lambda sinks, `CreateQueue`, assert on the published snapshot. Extend the shape: `SetProcessingTimeout(derived)` before `CreateQueue`, then assert `queueSnapshot.processing_queue().processing_timeout_length() == derived_ms` (the `:76` write), and at queue level `LockItem` + `UnlockExpiredItems(now+60s)` keeps the lock:
```cpp
auto queueSubTaskChannel = std::make_shared<ProcessingSubTaskQueueChannelImpl>();
queueSubTaskChannel->queuePublishingSink = [&queueSnapshotSet](std::shared_ptr<SGProcessing::SubTaskQueue> queue) {
        queueSnapshotSet.push_back(*queue);
};
// … build subTasks with chunkstoprocess …
ProcessingSubTaskQueueManager queueManager(queueSubTaskChannel, context, nodeId1,[](const std::string &){});
queueManager.CreateQueue(subTasks);
ASSERT_EQ(1, queueSnapshotSet.size());
EXPECT_EQ(nodeId1, queueSnapshotSet[0].processing_queue().owner_node_id());
```
Note: subtasks need ≥1 chunk or `CreateQueue` returns false (`processing_subtask_queue_manager.cpp:43-53`).

---

## Shared Patterns

### Error handling — `outcome::result` + typed `Error` codes
**Sources:** `ProcessingManager.cpp:523-578` (gates + catch ladder), `GeniusNode.cpp:2265-2270` (cost failure → `PROCESS_COST_ERROR`), `TokenAmount.cpp:65+` (`outcome::result<uint64_t>`).
**Apply to:** every new gate, helper, and branch. Pattern: `m_logger->error(...)` context first, then `return outcome::failure( Error::SPECIFIC_CODE )`; fallible helpers return `outcome::result<T>`; callers use `BOOST_OUTCOME_TRY`. No exceptions escape public entry points.

### Structured parse rejection = schema bounds (free) + C++ gates (explicit)
**Source:** `generated/helper.hpp:84-140` (`CheckConstraint` throws typed exceptions from `set_*` during `from_json`) + `ProcessingManager.cpp:523-561` (pre-parse) and `:586+` (post-parse).
**Apply to:** the D-05/D-07 rejection matrix. Bounds/pattern/enum → schema only (temperature ∈ [0,2], hours ∈ (0,24], `work_item_id` pattern). Duplicates, conditional-required, unimplemented modes, `top_p > 0` (exclusiveMinimum likely dropped by codegen — A3) → C++ gates. Test BOTH legs.

### Money math — integer path, uint128, deterministic rounding
**Source:** `TransactionManager.cpp:1101-1103` (`uint128_t` scaling), `TokenAmount.cpp:65+` (`CalculateCostMinions` integer chain, `MIN_MINION_UNITS` floor).
**Apply to:** `GetElmProcessCost` + `ElmClocks.escrowMinions`. Pure `uint64_t` at rate 1.0: `llround(hours*1000) * 3 / 10` (Pitfall 3 — `llround` never bare truncation). `ScaledInteger`/`TokenAmount` only if R becomes configurable non-1 (A1 — confirm R=1.0 at plan review).

### Logging — `m_logger`/`node_logger_` + spdlog format strings
**Source:** every analog above (`m_logger->error( "...: {}", x )`).
**Apply to:** all new gates and branches; error-level for rejections, warn for recoverable skips.

### Test registration — repo-specific CMake
**Sources:** SGProcessingManager `test/execution/CMakeLists.txt:14-22` (gated discovery); SuperGenius `cmake/functions.cmake:8-28` (`addtest`, `TIMEOUT 600`).
**Apply to:** files #5, #13, #14. Wrong-repo pattern breaks the parent build (PITFALLS: `SGPROC_TEST_DISCOVERY` gating is mandatory for SGProcessingManager targets). Long waits use the `assertWaitForCondition` helper (`test/src/processing_nodes/processing_nodes_test.cpp:530`).

### Commit order — submodule-first
**Apply to:** the whole phase. Schema+gates land in SGProcessingManager (`dev_elmruntime`) → commit → SuperGenius pointer bump → SuperGenius work compiles against the committed submodule state. SuperGenius code must never compile against uncommitted submodule state.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `processing_clocks_elm.hpp` (file #6) | utility | transform | Greenfield — no existing clocks/deadline utility. `TokenAmount` static-utility shape + RESEARCH sketch are the seed; planner should treat the struct + single derivation function as new code following Shared Patterns |
| Settlement wall-clock measurement (file #12, measurement leg) | service | event-driven | NO wall-clock measurement exists anywhere in the result chain today (F1: `SubTaskResult` has no time fields; manifest timing excludes fetch). Phase 1 pins design only — envelope stamps land Phase 3/4 |

Everything else has an in-tree analog with verified line numbers.

## Metadata

**Analog search scope:** `SuperGenius/src/{account,processing}/`, `SuperGenius/test/src/{account,processing}/`, `SuperGenius/cmake/`, `SGProcessingManager/{src,include,generated,test}/`, `SGProcessingManager/gnus-processing-schema.json`
**Files scanned:** ~25 (14 analog files read; glob/grep across both test trees)
**Pattern extraction date:** 2026-09-10
**Tree state:** SuperGenius `dev_elmruntime` @ `7f498073a`, SGProcessingManager `dev_elmruntime` @ `8fcd2be`
