# Phase 14: Durability-Gated TxPruner Eligibility - Pattern Map

**Mapped:** 2026-11-16
**Files analyzed:** 9 (4 modified source, 1 verified-untouched anchor, 3 new tests, 1 build config)
**Analogs found:** 9 / 9 (every file has an in-repo analog — this is a composition phase; re-derivation is the failure mode)

**Tracked-source gate:** every analog below verified `git ls-files` non-empty in its submodule this session. SuperGenius HEAD = `2af184fa1` on `dev_coldstorage_additions` (the merged line). sgns-blockstore paths live in the vendored `thirdparty/sgns-blockstore` submodule (frozen v1) — READ-ONLY reference for codec/fault-shape, do not modify.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `SuperGenius/src/transaction/TxPruner.cpp` | service (cycle orchestration) | batch (group filter → per-tx erase) | `src/crdt/globaldb/ColdStorageManager.cpp:1069-1077` (GC exact-state gate) + self (`:141-176` group filter) | exact (role+flow precedent) |
| `SuperGenius/src/transaction/TxPruner.hpp` | model + service contract | batch | self (`:68-117` `PruneCycleStats`; `:240-249` interrupt steps) | exact (in-place extension) |
| `SuperGenius/src/crdt/globaldb/globaldb.hpp` | store facade contract | CRUD (destructive compose) | self (`:310-320` `Error` enum; `:576` `GetColdUploadState` decl) | exact (in-place extension) |
| `SuperGenius/src/crdt/globaldb/globaldb.cpp` | store facade impl | CRUD (destructive compose, guard→staging→commit) | self (`:1401-1492` `EraseEntry`; `:1024-1037` active-accessor) | exact (in-place extension) |
| `SuperGenius/src/transaction/PruneEligibility.{hpp,cpp}` | pure evaluator (anchor) | request-response (read-only) | NONE — **deliberately untouched** | n/a (contract anchor) |
| `SuperGenius/test/src/crdt/cold_prune_gate_test.cpp` (name at planner discretion) | test (journal-injection state matrix) | state-driven CRUD (journal CF seed → assert gate) | `test/src/crdt/cold_storage_resurrection_test.cpp:765-806` + `test/src/crdt/cold_storage_durability_test.cpp:246-332` | exact (two fixture families, both proven) |
| `SuperGenius/test/src/crdt/cold_prune_toctou_test.cpp` | test (red-first TOCTOU counter-test) | event-driven (seam-fired journal flip) | `test/src/account/tx_pruner_test.cpp:2310-2345` + `test/src/crdt/globaldb_erase_test.cpp:394-436` | exact (dual-seam + instantiation shapes) |
| live-stack E2E smoke (dev-gated Tier-2/3; name/vehicle at planner discretion) | test (live smoke) | streaming (real drainer transitions) | `test/src/crdt/cold_storage_resurrection_test.cpp:745-815` (full-wire two-node topology) | role-match (deterministic stand-in; live leg stays dev-gated) |
| `SuperGenius/test/src/crdt/CMakeLists.txt` | config (test registration) | n/a | self (`:168-175` `cold_storage_durability_test` block) | exact (audit-checked convention) |

## Pattern Assignments

### `SuperGenius/src/transaction/TxPruner.cpp` (service, batch cycle)

**Analog A (the gate's state-handling shape):** `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp:1069-1077` — GC's `kEvictionDurabilityGate` consumption. THE precedent the TxPruner conjunct mirrors verbatim in shape:

```cpp
// Durability gate (MI-02): the journal state must be
// EXACTLY kEvictionDurabilityGate - anything else
// (NoRecord/Pending/Accepted) or an unreadable read is not
// eligible.
auto state = local_block_store_->GetUploadState( entry.cid );
if ( !state.has_value() || state.value() != kEvictionDurabilityGate )
{
    ++gc_elig_state_;
    continue;
}
```

Note the shape's three properties to preserve: exact-equality (never a `<=` level comparison), a dedicated counter (`gc_elig_state_`) rather than an error, `continue` (defer), never abort.

**Analog B (where the conjunct slots — the group filter):** `TxPruner.cpp:141-176`. The cold conjunct extends admission in the group-assembly loop (`:156-176`), keyed on `globaldb.HasColdStorage()` (SC4 vacuous branch) and `globaldb.GetColdUploadState(cid)` per group CID (single CID per group — D-01 removal-set rule):

```cpp
// (3) Block-grouped work list (D-04 / PRUNE-03): eligible candidates
// grouped by their delta-block CID; only groups whose block report
// is ERASABLE are this cycle's work -- a gate-held block keeps its
// whole group (erasing a tx value whose block survives a
// non-eligible sibling would strand the sibling's history). Group
// order is the evaluation's first-appearance order (deterministic).
std::set<std::string> erasable_cids;
for ( const auto &report : result.block_reports )
{
    if ( report.erasable )
    {
        erasable_cids.insert( report.cid );
    }
}

std::vector<std::string>                                         group_order;
std::map<std::string, std::vector<const PruneCandidateResult *>> groups;
for ( const auto &candidate : result.candidates )
{
    if ( !candidate.eligible || !candidate.cid.has_value() )
    {
        continue;
    }
    const std::string &cid = candidate.cid.value();
    if ( erasable_cids.find( cid ) == erasable_cids.end() )
    {
        continue;
    }
    const auto inserted = groups.try_emplace( cid );
    if ( inserted.second )
    {
        group_order.push_back( cid );
    }
    inserted.first->second.push_back( &candidate );
}
```

Gate at the GROUP level here (Pitfall 4: per-tx gating strands same-block siblings). The conjunct reads like GC's Analog A translated through the ungated enum — `ColdStorageStack.hpp:59-76`:

```cpp
// enum class ColdUploadState { NoRecord, Pending, Accepted, Durable, Unreadable };
switch ( globaldb.GetColdUploadState( cid ) )
{
    case ColdUploadState::Durable:
        admitted = true;                 // the ONLY permit
        break;
    case ColdUploadState::Unreadable:
        ++stats.cold_unreadable_groups;  // D-03: loud, dedicated counter + WARN
        break;
    case ColdUploadState::NoRecord:
    case ColdUploadState::Pending:
    case ColdUploadState::Accepted:
    default:
        ++stats.cold_deferred_groups;    // SC1: defer loudly, re-evaluate next cycle
        break;
}
```

**Analog C (interrupt seam — the D-07 sibling):** existing firing shape at `TxPruner.cpp:195-205`:

```cpp
if ( InterruptRequested( kInterruptBeforeErase ) )
{
    interrupted = true;
    break;
}
auto erase = transaction_manager.EraseTransactionEntryPruned( TxHashFromPath( candidate->tx_path ) );
```

The new sibling (`kInterruptAfterColdGate = 5`, naming at planner discretion per CONTEXT Discretion) fires after the cold conjunct admits a group, BEFORE the per-tx erase loop. Semantics note: the hook contract is "true = abort" — the TOCTOU test's flip-and-observe usage returns **false** (observe, not abort), which the existing seam already supports without change.

**Analog D (per-tx failure accounting — the deferral mapping target):** `TxPruner.cpp:203-213` shows the ONLY existing per-tx failure path (`++stats.errors` + WARN). Pitfall 1 guard: a guard-5 refusal must NOT land here — map the distinct refusal signal (see globaldb assignment) to `++stats.cold_deferred_groups` instead, so "counter, not a failure reason" holds on the re-check path too.

**Analog E (INFO summary extension point):** `TxPruner.cpp:285-296`:

```cpp
logger_->info( "Prune cycle [generation {}]: examined={}, eligible={}, erased={}, held_blocks={}, "
               "skipped={}, errors={}, duration_ms={}, watermark={} — bytes reclaimed: not measured "
               "until Phase 20",
               stats.generation,
               stats.examined,
               ...
```

New counters join this line (exact formatting/phrasing at planner discretion per CONTEXT Discretion). Do not fabricate reclaimed-bytes numbers — the existing "not measured until Phase 20" clause stays.

---

### `SuperGenius/src/transaction/TxPruner.hpp` (model + service contract)

**Analog (counter home):** `TxPruner.hpp:68-117` — `PruneCycleStats`. Copy the field style exactly (uint64_t + Doxygen `///` comment stating semantics and retry posture):

```cpp
struct PruneCycleStats
{
    /// Candidates the evaluator enumerated this cycle (eligible + ineligible).
    uint64_t examined = 0;
    ...
    /// Erasable block groups DEFERRED whole because the remaining K
    /// budget could not fit the group (D-04 group-or-defer — the
    /// stranding edge, Pitfall 1). Deferred groups retry next cycle.
    uint64_t held_blocks = 0;
    ...
    /// Per-tx erase failures inside taken groups (recorded and skipped
    /// past — the cycle continues; the tx stays enumerated for a later
    /// cycle). Per-tx failures are NOT hard errors: the cycle still ran
    /// to completion.
    uint64_t errors = 0;
```

`cold_deferred_groups` / `cold_unreadable_groups` slot beside `held_blocks` (:83) with the same "deferred … retry next cycle" doc posture (Unreadable's doc must additionally say WARN + never-permanent-stop, D-03).

**Analog (interrupt constants):** `TxPruner.hpp:240-249`:

```cpp
/// Interrupt seam step: after Evaluate(), before grouping.
static constexpr int kInterruptAfterEvaluation = 1;
/// Interrupt seam step: immediately before EACH per-tx erase call ...
static constexpr int kInterruptBeforeErase = 2;
/// Interrupt seam step: after the erase loop, before the status update.
static constexpr int kInterruptBeforeStatus = 3;
/// Interrupt seam step: after the status update, before the INFO
/// summary (the status IS updated at this point).
static constexpr int kInterruptAfterStatus = 4;
```

The new sibling constant (`= 5`) follows this numbered-step convention with an equivalent one-line contract comment. Also update the `RunCycle` contract block (:~137-180) and the `SetCycleInterruptHookForTest` doc (:~250-265) to name the new step — the crash-matrix contract surface is documented in the header, so a new step MUST be documented there too.

---

### `SuperGenius/src/crdt/globaldb/globaldb.cpp` (store facade impl)

**Analog A (guard 5's home — compose critical section):** `globaldb.cpp:1401-1492` — `EraseEntry`. Guard 5 slots AFTER guard (4) (`:1451-1460`), BEFORE the first staging (`:1462-1465`), mirroring the fail-closed posture and the documented rationale:

```cpp
// Guards (fail-closed, before any staging): a CID that is in use
// anywhere in the live DAG machinery is not erased. Guard
// evaluation runs INSIDE the compose critical section, so a
// concurrent PutElems cannot interleave between these checks and
// the commit (WR-02 closed by construction; see the header
// contract).
// ...
// (4) The seal marker must exist before erasing (unresolved CID means
//     nothing certifies this node ever completed the block).
BOOST_OUTCOME_TRY( auto resolved, m_dagSyncer->isResolved( cid ) );
if ( !resolved )
{
    m_logger->error( "{}: cid {} is unresolved, refusing erase", __func__,
                     cid.toString().value() );
    return outcome::failure( Error::INVALID_PARAMETERS );
}

// Compose: one batch, three owner stagings, one commit. Key-layout
// knowledge stays in the owners -- this facade only composes.
auto batch = datastore->batch();
```

Guard 5's read path: `HasColdStorage()` first (vacuous branch), else `GetColdUploadState( cid )` — permit only `Durable`, else REFUSE with the distinct error (below). **Lock discipline (Pitfall 3):** the guard calls ONLY `GetColdUploadState`-shaped reads (path: compose lock → `lifecycle_mutex_` → `cold_store_mutex_` → journal). Nothing that re-enters the datastore. The compose→`lifecycle_mutex_` edge already exists (guard 1 calls `GetCRDTHeadList` inside the lock); verified safe — do not add any other edge.

**Analog B (distinct-error precedent — the refusal signal shape):** guards 1-4 all return `Error::INVALID_PARAMETERS`, but `EraseEntry` ALREADY distinguishes a semantic refusal class via a dedicated enum value — the post-commit anomaly at `globaldb.cpp:~1495-1510`:

```cpp
// The seal marker is never staged for removal above; if it is gone
// now, something erased it out-of-band -- fail loudly with a
// DISTINCT error: unlike the pre-staging guard rejections
// (Error::INVALID_PARAMETERS -- nothing erased), the commit has
// ALREADY landed here, so callers can tell "erased, then anomaly"
// apart from "nothing erased".
...
return outcome::failure( Error::POST_COMMIT_ERASE_ANOMALY );
```

Guard 5 copies this pattern: a NEW distinct `GlobalDB::Error` value (name at planner discretion) meaning "refused: cold evidence not Durable — nothing erased, defer". Research open-question 1 recommends the distinct-value form; TxPruner maps it to `cold_deferred_groups`, never `stats.errors`.

**Analog C (the accessor impl shape — `HasColdStorage()`):** `globaldb.cpp:1024-1037` — `GetColdUploadState`, the active-accessor pattern to clone:

```cpp
ColdUploadState GlobalDB::GetColdUploadState( const CID &cid ) const
{
    // The same active-accessor shape: NoRecord once shutdown has
    // started; otherwise the null-safe ungated bridge over the
    // manager's D-09 pass-through (never a library type here).
    std::lock_guard<std::mutex> lock( lifecycle_mutex_ );
    if ( shutdown_started_.load() )
    {
        return ColdUploadState::NoRecord;
    }
    // Explicit qualification: this member hides the free bridge name.
    return sgns::crdt::GetColdUploadState( cold_manager_, cid );
}
```

`HasColdStorage()` mirrors this: `lock(lifecycle_mutex_)` → `return !shutdown_started_.load() && cold_manager_ != nullptr;`. Do NOT infer tier presence from `GetColdStorageStatus()` defaults (Pitfall 7 — ambiguous on a fresh cold node). Shutdown-time `GetColdUploadState → NoRecord` already defers — leave that mapping as-is (Pitfall 8).

---

### `SuperGenius/src/crdt/globaldb/globaldb.hpp` (store facade contract)

**Analog A (Error enum extension):** `globaldb.hpp:310-320` — `enum class Error : uint8_t` with `POST_COMMIT_ERASE_ANOMALY` at `:320` (its doc comment `/// Erase already committed; post-commit seal re-check failed` is the style). New refusal value appends here.

**Analog B (accessor decl):** `globaldb.hpp:576` — `ColdUploadState GetColdUploadState( const CID &cid ) const;`. `bool HasColdStorage() const;` decl joins it with the same Doxygen block style (`@brief/@details/@return`), including the "vacuous when cold disabled / OFF build" contract.

**Analog C (guard-5 contract docs):** the `EraseEntry` contract block around `:470-497` (which already documents `POST_COMMIT_ERASE_ANOMALY`'s committed-erase semantics at `:470/:497`) — extend it with guard 5's refusal contract ("nothing erased; defer; TxPruner maps to `cold_deferred_groups`").

**Ungated-enum discipline (hard constraint):** `ColdStorageStack.hpp:59-76` defines `ColdUploadState` precisely so "no sgns-blockstore type crosses this always-compiled header" — guard 5, the accessor, and the Error value reference ONLY the ungated enum, never `sgns::blockstore::UploadState`.

---

### `SuperGenius/src/transaction/PruneEligibility.{hpp,cpp}` — **UNTOUCHED (verify-only anchor)**

Both files exist on the merged line. The purity contract that PRUNE-03/D-05 protect, verbatim at `PruneEligibility.hpp:275-281`:

```cpp
/**
 * @brief       Read-only prune-eligibility evaluator (PRUNE-01, GATE-01).
 * @details     PURE evaluator (D-C6): it runs on committed state only —
 *              driven from a timer cycle by the caller, NEVER from CRDT
 *              element callbacks (they fire pre-batch-commit). It performs
 *              ZERO writes: no Put, no Erase, no staging, no hooks. The
 *              Phase-18 TxPruner is the reuse seam — it calls Evaluate()
 *              verbatim and owns every mutation.
```

The SC3 composition test (shape at planner discretion) asserts the cold conjunct composes WITH `Evaluate()` verdicts at the TxPruner filter — no evaluator edit may appear in any plan. If a plan diff touches these files, the plan is wrong.

---

### `SuperGenius/test/src/crdt/cold_prune_gate_test.cpp` (NEW — journal-injection 5-state matrix, Tier-1)

**Analog A (fixture family 2 — full-fidelity hermetic cold GlobalDB):** `cold_storage_resurrection_test.cpp:765-806`:

```cpp
// --- Node 2's cold-storage posture: ON, tiny-positive retention so
// the real background GC thread evicts naturally ..., hermetic fakes
// via the TEST-ONLY override.
GlobalDB::ColdStorageOptions cold;
cold.enabled   = true;
cold.endpoint  = "hermetic.invalid"; // overridden below - never contacted
cold.bucket    = "resurrect";
cold.accessKey = "test";
cold.secretKey = "test";
...
sgns::crdt::SetColdStorageStackClientsForTesting(
    std::static_pointer_cast<S3Client>( counting2 ),
    std::static_pointer_cast<S3AdminClient>( fake2_admin ) );
...
auto gdb2_ret = GlobalDB::New( io_context2, n2_path, pubs2,
                               CrdtOptions::DefaultOptions(), network2, scheduler2,
                               generator2, nullptr, GlobalDB::BackupOptions{ false, 15, 12, true },
                               cold );
...
// Hygiene: the process-global override has served its purpose.
sgns::crdt::SetColdStorageStackClientsForTesting( nullptr, nullptr );
```

Copy: options block + `"hermetic.invalid"` endpoint + TEST-ONLY client injection + immediate hygiene clear. Real RocksDB hot store + real coldstore journal, zero network. `SetColdStorageStackClientsForTesting` declared at `ColdStorageStack.hpp:~280-293` ("PRODUCTION CODE MUST NEVER CALL …" — test-binary only, process-global).

**Analog B (fixture family 1 — direct construction for the Unreadable leg):** `cold_storage_durability_test.cpp:246-332`. The fixture OWNS the `LocalBlockStore` handle (needed to arm `FaultController`; a second `Open` on the same dir hits RocksDB's lock — Pitfall 5):

```cpp
class ColdStorageDurabilityTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        shared_local_dir_ = FreshDir();
        auto opened_local = LocalBlockStore::Open( LocalBlockStoreOptions{ shared_local_dir_ } );
        ASSERT_TRUE( opened_local.has_value() );
        shared_local_ = std::shared_ptr<LocalBlockStore>( std::move( opened_local.value() ) );
        ...
        fake_admin_ = std::make_shared<InMemoryS3AdminClient>();
        cold_store_mutex_ = std::make_shared<std::mutex>();
    }
    ...
    /// Construct a manager directly over the fixture stores with the
    /// fake admin (D-10). ...
    std::shared_ptr<ColdStorageManager> MakeManager( ... )
    {
        auto remote_store_mutex = std::make_shared<std::mutex>();
        manager_ = std::make_shared<ColdStorageManager>(
            shared_local_, remote_, cold_store_mutex_, remote_store_mutex,
            backpressure, durability, fake_admin_ );
        return manager_;
    }
    /// Journal n blocks directly into the local store (Put-born
    /// PendingUpload records ...)
    std::vector<Cid> JournalBlocks( size_t n ) { ... }
    /// True when every CID's journal record reads the requested state
    /// through the manager's D-09 pass-through.
    bool AllInState( const std::vector<Cid> &cids, UploadState state ) const { ... }
```

**Journal seed codec (value states; verified `thirdparty/sgns-blockstore/src/LocalBlockStore.cpp:159-166`):** `[version-byte 0x01][state-byte]` with `0x00=PendingUpload, 0x01=UploadedAccepted, 0x02=UploadedDurable`; absent key = NoRecord. `Unreadable` is NOT a value — induce via `FaultController` `SetFault(FaultKind::Unavailable)` (enum at `FaultController.hpp:14-19`) on a directly-held store → bridge maps non-NotFound failure to `Unreadable` (`ColdStorageStack.cpp:344-354` per research). A garbage journal value decodes to Pending, never Unreadable (Pitfall 5a). Direct CF writes seed only the 4 value-states; the removal set (D-01) needs the hot-side tx present too — the resurrection GlobalDB supplies the erase path, the durability fixture supplies the fault arm; research open-question 2 sanctions splitting the Unreadable leg onto family 1.

---

### `SuperGenius/test/src/crdt/cold_prune_toctou_test.cpp` (NEW — red-first TOCTOU counter-test, Tier-1)

**Analog A (dual-seam driving):** `tx_pruner_test.cpp:2310-2345` — the CrashKillPoint dispatcher that already routes between the two seams:

```cpp
/// One kill point of the crash matrix: which seam, which step, and which
/// visit of that step aborts (the GlobalDB seam fires three step visits
/// per erase compose; the cycle seam's BeforeErase visit repeats per tx).
struct CrashKillPoint
{
    const char *name;
    /// true: the TxPruner cycle seam; false: GlobalDB's compose seam.
    bool use_cycle_seam;
    /// The seam's step constant (GlobalDB steps are literal 1/2/3).
    int step;
    /// 1-based visit of @p step that aborts.
    int invocation;
    ...
};
const std::vector<CrashKillPoint> kCrashKillPoints = {
    { "CycleAfterEvaluation", true, sgns::TxPruner::kInterruptAfterEvaluation, 1, false },
    { "CycleBeforeFirstErase", true, sgns::TxPruner::kInterruptBeforeErase, 1, false },
    ...
    { "ComposeStep2MidProgress", false, 2, 2, true },
```

The counter-test arms the NEW TxPruner-side step (after cold-gate admission, before the erase call), flips the journal `Durable→Accepted` (or `→NoRecord`) via direct CF write inside the hook, returns false (observe), then asserts: erase REFUSED, value still present, `cold_deferred_groups` grew, `errors` did NOT (Pitfall 1 warning sign). **Position discipline (Pitfall 2):** do NOT arm GlobalDB hook steps 2/3 for the flip — mid-compose is after the re-check and unprovable; the post-re-check window is closed by monotonicity + Phase 16, not this test.

**Analog B (hook arm/clear hygiene + parameterized shape):** `globaldb_erase_test.cpp:394-436`:

```cpp
class GlobalDBEraseInterruptTest : public GlobalDBEraseTest, public ::testing::WithParamInterface<int>
{
};

TEST_P( GlobalDBEraseInterruptTest, InterruptedEraseIsAllOrNothing )
{
    const int step_target = GetParam(); // 1 = after CRDT staging, ...
    ...
    sgns::crdt::GlobalDB::SetEraseInterruptHookForTest( [step_target]( int step ) { return step == step_target; } );
    auto erased = db.EraseEntry( entry_a.tx_path, entry_a.cid );
    EXPECT_TRUE( erased.has_error() );
    sgns::crdt::GlobalDB::SetEraseInterruptHookForTest( nullptr );
    ...
}

INSTANTIATE_TEST_SUITE_P( EraseInterruptSteps, GlobalDBEraseInterruptTest, ::testing::Values( 1, 2, 3 ) );
```

Copy the arm → act → immediately-clear sequence and the `INSTANTIATE_TEST_SUITE_P` shape (instantiate over the regression vector: Accepted / NoRecord flips). `TxPruner::SetCycleInterruptHookForTest` (`TxPruner.hpp:264`) is the cycle-side twin; fixture destructor clears hooks (the documented fixture discipline). Red-first per D-07: write the test against a gate WITHOUT the in-compose re-check, watch it fail, then implement guard 5.

---

### Live-stack E2E smoke (NEW — dev-gated Tier-2/3)

**Analog:** `cold_storage_resurrection_test.cpp:745-815` full-wire topology — two GlobalDBs over real pubsub/graphsync, one cold-ON via hermetic injection, `Put` propagates over the wire; drive real drainer transitions (`Accepted→Durable` via `InMemoryS3AdminClient` flush evidence) and assert the gate admits. Deterministic stand-in = the resurrection recipe itself; the LIVE leg (s3d/MinIO) stays dev-gated Tier-2/3 per D-08c/D-09 (research A2 — exact vehicle is planner's choice). `cold_storage_wallclock_soak` is the registration shape to AVOID for Tier-1 (env-gated Tier-3 by design).

---

### `SuperGenius/test/src/crdt/CMakeLists.txt` (config — Tier-1 registration)

**Analog (the exact block to replicate):** `:157-175` — the `cold_storage_durability_test` registration, inside the gate, with the LABELS line:

```cmake
# Flush-gated durability advancement tests (DUR-01, v1.1 Phase 10 plan
# 10-01). Registered ONLY under SGNS_COLD_STORAGE: links
# sgns-blockstore::sgns-blockstore plus the InMemoryS3Client and
# InMemoryS3AdminClient fakes (library-installed headers). The Tier-1
# lane stays non-empty on OFF builds via the unconditional config-gate test.
if(SGNS_COLD_STORAGE)
addtest(cold_storage_durability_test
    cold_storage_durability_test.cpp
)

target_link_libraries(cold_storage_durability_test
    sgns-blockstore::sgns-blockstore
    crdt_globaldb
)


set_tests_properties(cold_storage_durability_test PROPERTIES LABELS "Tier1")
endif()
```

Rules encoded here (audit-enforced by `test/tier1_audit_check.cmake:44-132`, per research): (1) `cold_`-prefixed suite names in `test/src/crdt`; (2) registration INSIDE `if(SGNS_COLD_STORAGE)` — any `sgns-blockstore::sgns-blockstore` link outside the gate trips audit Check 2; (3) mandatory `set_tests_properties(... LABELS "Tier1")` — a `cold_*` registration without it breaks `tier1_static_audit` for everyone (Check 1 parity); (4) never the wallclock-soak env-gated pattern for these (Check 3). The Tier-1 lane stays non-empty on OFF builds via the existing unconditional `cold_storage_config_gate_test` (`:83-95`) — do not change that suite's contract. The live E2E smoke does NOT get a Tier1 label.

## Shared Patterns

### 1. Exact-equality durability gate
**Source:** `ColdStorageManager.hpp:134-138` (`kEvictionDurabilityGate = UploadState::UploadedDurable`, compile-time, "no config knob can lower it") + consumption at `ColdStorageManager.cpp:1069-1077`.
**Apply to:** TxPruner cold conjunct AND GlobalDB guard 5. Never a numeric level comparison; never accept-is-durable.

### 2. Fail-closed guard inside the compose critical section
**Source:** `globaldb.cpp:1419-1460` (compose lock first act; guards before staging; "WR-02 closed by construction").
**Apply to:** guard 5 — same critical section, same before-any-staging position, lock discipline per Pitfall 3 (compose → lifecycle → cold_store mutex order only).

### 3. Active-accessor shape under `lifecycle_mutex_`
**Source:** `globaldb.cpp:1024-1037` (`GetColdUploadState`) and `:1010-1023` (`GetColdStorageStatus`).
**Apply to:** `HasColdStorage()` impl + decl (`globaldb.hpp:576` style). Shutdown-aware, null-safe, no journal scan under the lock.

### 4. Counter-not-failure observability
**Source:** GC's `gc_elig_state_` counter + `continue` (`ColdStorageManager.cpp:1069-1077`); `PruneCycleStats` doc style (`TxPruner.hpp:68-117`).
**Apply to:** both `cold_deferred_groups` paths (filter defer and guard-5 refusal mapping). `stats.errors` must not grow on deferrals — the composition/TOCTOU tests assert this.

### 5. Ungated-enum boundary
**Source:** `ColdStorageStack.hpp:59-76` (ColdUploadState) + bridge decl `:225-236` + null-safe bridge impl (`ColdStorageStack.cpp:333-366` per research).
**Apply to:** every new signature across `globaldb.hpp`, `TxPruner.*`, and tests — only the ungated enum crosses always-compiled headers.

### 6. Test-seam hygiene
**Source:** `globaldb_erase_test.cpp:421-425` (arm → act → clear inline) + `TxPruner.hpp` fixture-discipline note on `SetCycleInterruptHookForTest` (:~250-265) + resurrection's immediate `SetColdStorageStackClientsForTesting(nullptr, nullptr)`.
**Apply to:** all three suites; process-global seams never leak past a case.

### 7. Group-or-defer whole-group semantics
**Source:** `TxPruner.cpp:160-192` (`held_blocks` deferral) — develop D-04 precedent restated in CONTEXT's Established Patterns.
**Apply to:** the cold conjunct — one non-Durable CID defers the entire group; matrix tests assert whole-group deferral.

### 8. Fail-to-defer direction (conservative reads)
**Source:** journal decode fallback (`LocalBlockStore.cpp:166-172, 1227-1230` — unknown bytes → Pending, per research); shutdown → NoRecord (`globaldb.cpp:1029-1033`).
**Apply to:** gate semantics — corruption and shutdown both land on defer; never "fix" into a permit (Pitfall 8).

## No Analog Found

None — every file-to-touch has a tracked in-repo analog. Two shapes are NEW but have close structural precedent (noted in assignments): (a) the guard-5 distinct refusal `Error` value (precedent: `POST_COMMIT_ERASE_ANOMALY`, `globaldb.hpp:320`); (b) direct journal-CF seeding helpers (codec precedent `LocalBlockStore.cpp:159-166`; helper shape precedent `JournalBlocks`, `cold_storage_durability_test.cpp:287-303`). The SC3 composition-test shape has no dedicated precedent suite — model it on the dual-seam parameterization in `tx_pruner_test.cpp:2310-2345` with the evaluator exercised verbatim (purity contract `PruneEligibility.hpp:275-281`).

## Metadata

**Analog search scope:** `SuperGenius/src/transaction/`, `SuperGenius/src/crdt/globaldb/`, `SuperGenius/test/src/crdt/`, `SuperGenius/test/src/account/`, `SuperGenius/test/`, `thirdparty/sgns-blockstore/` (read-only reference)
**Line anchors:** re-verified by direct read on `dev_coldstorage_additions` @ `2af184fa1` this session (git-tracked confirmed per path)
**Pattern extraction date:** 2026-11-16
