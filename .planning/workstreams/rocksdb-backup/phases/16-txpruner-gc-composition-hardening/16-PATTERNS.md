# Phase 16: TxPruner × GC Composition Hardening - Pattern Map

**Mapped:** 2026-11-18
**Files analyzed:** 9 (5 production modifications, 3 new test/config files, 1 planning doc)
**Analogs found:** 9 / 9 (every deliverable has an in-tree analog; 1 partial — the fire-and-continue seam contract, see "No Analog Found")

**Anchor basis:** all line numbers below re-verified by direct reads this session against SuperGenius HEAD `af644481f` (matches 16-RESEARCH.md's Anchor Re-Location Record). The v1.2-research numbers (`2af184fa1`) and the 16-CONTEXT numbers are STALE — do not cite them in plans.

**Tracked-source gate:** every analog named below verified via `git -C SuperGenius ls-files -- <path>` (non-empty) at HEAD `af644481f` on `dev_coldstorage_additions`. No gitignored/mirror paths appear in this document.

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `SuperGenius/src/crdt/globaldb/globaldb.cpp` | service (CRDT facade compose path) | batch (single-commit erase) | self-anchor + GC's A6 ordering `ColdStorageManager.cpp:1346-1352`; existing hook fire sites `globaldb.cpp:1637-1650` | exact |
| `SuperGenius/src/crdt/globaldb/globaldb.hpp` | interface (test-seam + bridge declarations) | declaration | `SetEraseInterruptHookForTest` decl `:527-534`; `SetColdUploadStateHookForTest` decl `:543-553` | exact |
| `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp` / `.hpp` | service (GC manager point-lookup pass-through + D-12 comments) | request-response | `ColdStorageManager::GetUploadState` `ColdStorageManager.cpp:727-731` | exact |
| `SuperGenius/src/transaction/TxPruner.cpp` | service (prune-cycle admission gate arm) | batch + policy gate | `ColdGateAdmitsGroup` arm structure `TxPruner.cpp:67-130` | exact |
| `SuperGenius/src/transaction/TxPruner.hpp` | model (cycle stats struct) | n/a | `cold_unreadable_groups` field + doc `TxPruner.hpp:98-103` | exact |
| `SuperGenius/test/src/crdt/cold_compose_matrix_test.cpp` (NEW) | test (SC2 matrix + SC1 counter-test + SC3 deterministic leg) | event-driven (barrier races) + deterministic seam-stepped | `cold_storage_fault_race_test.cpp` + `cold_prune_toctou_test.cpp` + `cold_prune_gate_test.cpp` + `cold_storage_gc_test.cpp` (compound analog — each contributes one layer) | exact (compound) |
| `SuperGenius/test/src/crdt/CMakeLists.txt` | config (ctest registration) | n/a | `cold_prune_gate_test` block `:309-345` (Tier1); `cold_prune_live_smoke_test` block `:439-470` (Tier3) | exact |
| `SuperGenius/test/src/crdt/cold_compose_live_smoke_test.cpp` (NEW — Tier-3 live SC3 leg; home per Agent's Discretion) | test (dev-gated live leg) | request-response (live stack) | `cold_prune_live_smoke_test.cpp:533-575` | exact |
| `.planning/workstreams/rocksdb-backup/notes/<16-starvation-ruling>.md` (NEW — D-12 ruling doc; home per Agent's Discretion) | documentation | n/a | `.planning/workstreams/rocksdb-backup/notes/develop-merge-erase-vs-cold-storage-gap.md` | role-match |

**Layering pre-classification (governs the test wiring):** `cold_compose_matrix_test` is a crdt-scoped suite. If it links `genius_node_test` whole-archive (the `cold_prune_gate_test` recipe) it may use `sgns::PruneEligibility::WritePrunedBlockEntryForTest`; if it stays at the `globaldb_erase_test` link level it must seed markers via direct `PutRaw`. Pick ONE posture per target and keep the marker-seeding mechanism consistent with the link set (Pitfall 5 in 16-RESEARCH).

---

## Pattern Assignments

### 1. `SuperGenius/src/crdt/globaldb/globaldb.cpp` (service, batch — SC1 post-commit close + new seam fire + optional IsColdDisposed bridge)

**Analog A (the ordering being mirrored):** GC's A6 in `ColdStorageManager.cpp:1317-1352`

```cpp
    void ColdStorageManager::RunHotCleanup( const sgns::blockstore::Cid  &cid,
                                            const std::vector<std::string> &row_keys )
    {
        ...
        (void)batch->commit();
        // A6: LRU invalidation AFTER the hot deletes - post-cleanup the
        // hot and LRU HasBlock terms miss and the disposed-marker term
        // answers (HasBlock stays honest through the whole window).
        (void)gc_dag_syncer_->DeleteCIDBlock( cid_key );
    }
```

**Analog B (the insertion site — current tail of `EraseEntry`, `globaldb.cpp:1664-1684`):**

```cpp
        BOOST_OUTCOME_TRY( batch->commit() );

        // The seal marker is never staged for removal above; if it is gone
        // now, something erased it out-of-band -- fail loudly with a
        // DISTINCT error: ...
        BOOST_OUTCOME_TRY( auto still_resolved, m_dagSyncer->isResolved( cid ) );
        if ( !still_resolved )
        {
            m_logger->error( "{}: seal marker vanished after erase - seal-addressing bug (erase already committed)",
                             __func__ );
            return outcome::failure( Error::POST_COMMIT_ERASE_ANOMALY );
        }

        return outcome::success();
    }
```

The D-04 `DeleteCIDBlock` slots between the re-assert block and `return outcome::success();`. **Planner must rule the anomaly-path ordering** (research Open Question 3): the `POST_COMMIT_ERASE_ANOMALY` return at `:1678` also follows a landed commit — place the delete before the failure return or duplicate it there, and document either way.

**The primitive being called** (`graphsync_dagsyncer.cpp:1258-1265`) — idempotent, lock-free (assumption A2: do NOT introduce `dagMutex_` into the call):

```cpp
    outcome::result<void> GraphsyncDAGSyncer::DeleteCIDBlock( const CID &cid )
    {
        if ( lru_cid_cache_.remove( cid ) )
        {
            logger_->debug( "Block removed from LRU cache: CID {}", cid.toString().value() );
        }
        return outcome::success();
    }
```

`m_dagSyncer` is the concrete type (`globaldb.hpp:769`) — no interface change needed. Guard 3 (`globaldb.cpp:1567-1573`) stays untouched (D-05).

**Analog C (the seam fire pattern to extend — steps 1-3 abort contract, `globaldb.cpp:1636-1650`):**

```cpp
        BOOST_OUTCOME_TRY( crdt_datastore->StageEraseElement( batch, key ) );
        if ( erase_interrupt_hook_for_test_ && erase_interrupt_hook_for_test_( 1 ) )
        {
            return outcome::failure( Error::INVALID_PARAMETERS );
        }
```

The NEW seam (SC1 window counter-test, Agent's Discretion naming) fires AFTER guard evaluation and BEFORE `batch->commit()` (`:1664`) with a **continue** contract — the hook performs `AddCIDBlock( cid, node )` mid-window and the erase proceeds. See "No Analog Found" for the contract nuance. Static storage precedent: `erase_interrupt_hook_for_test_` at `globaldb.cpp:810-812`.

**Analog D (the bridge shape, if `IsColdDisposed` lands here):** `GlobalDB::GetColdUploadState` (`globaldb.cpp:1486-1509`) — lifecycle-mutex-scoped, null-safe manager delegation:

```cpp
    ColdUploadState GlobalDB::GetColdUploadState( const CID &cid ) const
    {
        ...
        std::lock_guard<std::mutex> lock( lifecycle_mutex_ );
        if ( shutdown_started_.load() )
        {
            return ColdUploadState::NoRecord;
        }
        // Explicit qualification: this member hides the free bridge name.
        return sgns::crdt::GetColdUploadState( cold_manager_, cid );
    }
```

**D-02 comment home:** guard 5's existing comment already names "Phase 16's Interaction-C ruling surface" (`globaldb.cpp:1625-1633`) — extend at that site and at the GC reader (`ColdStorageManager.cpp:1075-1077`), no lock changes.

---

### 2. `SuperGenius/src/crdt/globaldb/globaldb.hpp` (interface — seam + bridge declarations)

**Analog:** the two existing hook declarations (`globaldb.hpp:527-553`):

```cpp
        /**
         * @brief Test-only interruption seam for EraseEntry's compose window.
         * @param hook invoked after each staging step (1 = after CRDT-entry
         *        staging, 2 = after block staging, 3 = after raw-map staging);
         *        a @c true return aborts the erase WITHOUT committing, so the
         *        dying batch proves all-or-nothing. Pass nullptr to clear.
         * @note No production caller may invoke this method.
         */
        static void SetEraseInterruptHookForTest( std::function<bool( int step )> hook );
```

Copy the Doxygen shape verbatim (`@brief`/`@param`/`@note`, TEST-ONLY emphasis, "Pass nullptr to clear", fixture-clear discipline note). The new sibling must document that it is **NOT an abort seam** (observe-and-continue) so the abort contract of steps 1-3 stays honest (research Open Question 1 recommendation).

---

### 3. `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp` / `.hpp` (service, request-response — `IsDisposed` pass-through + D-12 comments)

**Analog:** `ColdStorageManager::GetUploadState` (`ColdStorageManager.cpp:727-731`) — the exact three-line pass-through shape under the shared mutex (research assumption A3 budgets this accessor):

```cpp
    sgns::blockstore::result<sgns::blockstore::UploadState, sgns::blockstore::BlockStatus>
    ColdStorageManager::GetUploadState( const sgns::blockstore::Cid &cid )
    {
        std::lock_guard<std::mutex> lock( *cold_store_mutex_ );
        return local_block_store_->GetUploadState( cid );
    }
```

The new `IsDisposed(cid)` mirrors this: `std::lock_guard<std::mutex> lock( *cold_store_mutex_ ); return local_block_store_->IsDisposed( cid );`. The keyspace is owned by the library (`LocalBlockStore::IsDisposed`, consumed at `ColdReadService.cpp:286`) — never hand-build marker keys (Pitfall 5, one-builder-per-namespace).

**D-12 comment home** (`ColdStorageManager.cpp:1273-1287`, the starvation source):

```cpp
            {
                std::lock_guard<std::mutex> lock( *cold_store_mutex_ );
                auto evicted = local_block_store_->EvictLocalAndMarkDisposed( mark.cid, record );
```

State the interplay + under-prune ruling here and at the TxPruner gate site (D-12 both-homes rule).

---

### 4. `SuperGenius/src/transaction/TxPruner.cpp` (service — D-10 NoRecord-arm split + INFO line)

**Analog:** the arm being split, `ColdGateAdmitsGroup` (`TxPruner.cpp:118-128`):

```cpp
                case crdt::ColdUploadState::NoRecord:
                case crdt::ColdUploadState::Pending:
                case crdt::ColdUploadState::Accepted:
                default:
                    // Includes the default arm (T-14-01): an unknown
                    // future enum value can never admit.
                    ++stats.cold_deferred_groups;
                    return false;
```

Split rule: `NoRecord` breaks out of the fallthrough chain and consults the disposed marker through the GlobalDB bridge; `Pending`/`Accepted`/default NEVER consult (journal record exists — not disposed). Match the surrounding comment density (every arm carries its decision record). Note the function signature receives `const crdt::GlobalDB &globaldb` — the consult composes there; evaluator purity (`PruneEligibility`) is untouched (Pattern 1 in 16-RESEARCH; phase-level purity gate `git diff --exit-code 2af184fa1` on `PruneEligibility.{hpp,cpp}`).

**INFO summary to extend** (`TxPruner.cpp:396-413`):

```cpp
        logger_->info( "Prune cycle [generation {}]: examined={}, eligible={}, erased={}, held_blocks={}, "
                       "cold_deferred={}, cold_unreadable={}, skipped={}, errors={}, duration_ms={}, "
                       "watermark={} — bytes reclaimed: not measured until Phase 20",
                       stats.generation,
                       ...
                       stats.cold_deferred_groups,
                       stats.cold_unreadable_groups,
```

Add the stranded counter between `cold_unreadable` and `skipped` (keep the "counters, never failure reasons" posture; counter name is Agent's Discretion).

---

### 5. `SuperGenius/src/transaction/TxPruner.hpp` (model — stranded counter field)

**Analog:** the dedicated-counter field pattern (`TxPruner.hpp:92-103` inside `PruneCycleStats`):

```cpp
        /// Erasable block groups DEFERRED because the cold-journal read
        /// itself failed (ColdUploadState::Unreadable) — additionally
        /// WARN-logged once per group (D-03). Never a permanent-stop
        /// class error: a single unreadable record must not brick
        /// pruning; the group retries next cycle.
        uint64_t cold_unreadable_groups = 0;
```

Copy the shape: `uint64_t` + default 0 + a doc comment naming the deferral semantics, the D-decision, and the retry posture. The stranded counter sits beside `cold_deferred_groups` (`:92`) / `cold_unreadable_groups` (`:102`).

---

### 6. `SuperGenius/test/src/crdt/cold_compose_matrix_test.cpp` (NEW test — SC2 matrix, SC1 window counter-test, SC3 deterministic leg)

This suite composes FOUR analog layers. File header must carry the same brief style as the sibling suites (phase/plan/decision provenance, fixture posture, leg inventory, tier declaration — see `cold_prune_gate_test.cpp:1-64` for the canonical header).

**Layer 1 — hermetic fixture + journal-injection kit. Analog:** `cold_prune_gate_test.cpp`.

Fixture posture (header `:10-22`): "a REAL cold-enabled GlobalDB (real RocksDB hot store + real coldstore journal) over SetColdStorageStackClientsForTesting-injected InMemoryS3Client/InMemoryS3AdminClient fakes with endpoint `hermetic.invalid` (never contacted), hygiene-cleared immediately after construction" + the tx_pruner_test construction pattern (real GeniusAccount + Blockchain + TransactionManager + TxPruner, friend-seam tick-gate drive) + the per-binary friend seam (`:107-122`):

```cpp
namespace sgns
{
    /**
     * Per-binary friend-seam definition (the tx_pruner_test shape): the
     * TxPruner tick gate requires State::READY, which no public API reaches
     * deterministically. This definition carries only ChangeState.
     */
    class TransactionManagerPendingLifecycleTestAccess
    {
    public:
        static void ChangeState( TransactionManager &manager, TransactionManager::State state )
        {
            manager.ChangeState( state );
        }
    };
} // namespace sgns
```

The journal-injection instrument (`cold_prune_gate_test.cpp:723-812`) already supports **deletion** — the SC3 deterministic leg's disposal simulation is `SeedJournalRecord( dir, cid, std::nullopt )` (nullopt → `db->Delete`):

```cpp
    /**
     * @brief  Rewrites (or deletes, when @p value_bytes is nullopt) one
     *         CID's record in the coldstore's upload_journal CF. Asserts
     *         the record EXISTS first ... Requires the GlobalDB over @p
     *         coldstore_dir's hot dir to be CLOSED (RocksDB dir lock).
     */
    bool SeedJournalRecord( const std::string &coldstore_dir,
                            const std::string &cid_string,
                            std::optional<std::string> value_bytes )
```

Copy this helper (and `JournalKeyOf`) verbatim into the new suite; the sequence for the SC3 leg is: populate → TeardownStack → delete record → reopen → drive one cycle → assert defer + stranded counter + value still present (red-first per D-11).

**Layer 2 — deterministic seam-stepped legs + red-first posture. Analog:** `cold_prune_toctou_test.cpp`.

Copy the POSITION DISCIPLINE header discipline (`:18-26`): the flip/observation is armed at a NAMED seam only, every assertion failure message carries an identifying literal token (TOCTOU there; pick one for SC1, e.g. the window name), and the suite is authored red-first. Copy the bounded poll helper (`:137-148`, never fixed sleeps) and the lane-scoped dir discipline (`NextUniqueDir`/`FreshDir` with `test-data/cold-prune-toctou/`-style prefixes — use a new `cold-compose-matrix/` lane):

```cpp
    /// Bounded poll loop with deadline - never a fixed sleep (Tier-1 audit).
    bool PollUntil( const std::function<bool()> &predicate,
                    std::chrono::milliseconds       deadline,
                    std::chrono::milliseconds       step = std::chrono::milliseconds( 10 ) )
```

**Layer 3 — barrier-driven real-thread legs. Analog:** `cold_storage_fault_race_test.cpp`.

The deterministic barrier is `WindowGate` (`:237-289`) — one-shot enter/release latch, cv-wait based, destructor-releases (leak-proofing against ASSERT-aborted bodies):

```cpp
    class WindowGate
    {
    public:
        ~WindowGate() { Release(); }
        /// Actor side: mark inside + block until released.
        void Enter()
        {
            std::unique_lock<std::mutex> lock( mutex_ );
            inside_ = true;
            cv_.notify_all();
            cv_.wait( lock, [this] { return released_; } );
        }
        /// Test side: bounded wait until the actor sits inside the window.
        bool WaitInside( std::chrono::milliseconds deadline ) { ... }
        /// Test side: let the actor (and every later Enter) proceed.
        void Release() { ... }
    };
```

Leg shape (from `EvictServe_HotCleanupWindow_ReaderNeverTorn`, `:1141-1177`) — arm hook → spawn thread → `WaitInside(10s)` → mid-window assertions → `Release()` → `join()` → post-state assertions:

```cpp
    WindowGate gc_window;
    manager->SetGcBetweenHalvesHookForTesting( [&] { gc_window.Enter(); } );
    std::thread gc_thread( [&] { (void)manager->GcPassOnce(); } );
    const bool in_window = gc_window.WaitInside( std::chrono::milliseconds( 10000 ) );
    EXPECT_TRUE( in_window ) << "GC never parked inside the between-halves window";
    ...
    gc_window.Release();
    gc_thread.join();
```

GC park points already exist: `gc_pre_half_one_hook_` (`:1256-1267`), `gc_between_halves_hook_` (`:1288-1301`), `GcPassOnce()` is public for driving passes. Env-knob reproducibility via `EnvOr` (`:229-235`) and the seeded-jitter precedent `Jitter_PairwiseSeededIterations` (`:1616-1632`, knobs `SGNS_RACE_JITTER_SEED`/`SGNS_RACE_JITTER_ITERS`). The `PrefixSpyHotStore` ops-tally instrument (`:568-683`, wired at `:731`) is available for per-op footprint rows.

**Layer 4 — byte-level fixed-point convergence (D-08a). Analog:** `cold_storage_gc_test.cpp` `NeverPurgedEndStateAcrossAggressivePasses` (`:1766-1858`).

Exact-prefix enumeration via `GetKeysPrefix()` + `real_hot_->query(prefix)` and `EXPECT_EQ(before, after)` on the full key→value maps:

```cpp
    using HotQueryResult = sgns::storage::rocksdb::QueryResult;
    auto snapshot_keys = [&]( HotQueryResult &out ) {
        out.clear();
        const std::string keys_prefix = crdt_->GetKeysPrefix(); // "<ns>/s/k"
        const std::string set_root    = keys_prefix.substr( 0, keys_prefix.size() - 1 ); // "<ns>/s/"
        const std::array<std::string, 3> prefixes = {
            set_root + "t/", set_root + "k/", "/" + std::string( "namespace" ) + "/h/",
        };
        for ( const auto &prefix : prefixes )
        {
            sgns::storage::Buffer p;
            p.put( prefix );
            auto found = real_hot_->query( p );
            ASSERT_TRUE( found.has_value() );
            for ( const auto &[k, v] : found.value() ) { out[k] = v; }
        }
    };
    ...
    HotQueryResult after;
    snapshot_keys( after );
    EXPECT_EQ( before, after ) << "tombstones/current-values/heads are never purged";
```

Extend the prefix set with `/prune/tx/`, `/prune/blk/`, binary CID keys, and seal rows (via `isResolved`, never the `"sealed"` literal — GATE-03 bans it in production src/). Critical companion: the elems-sibling row-key rule (`cold_storage_gc_test.cpp:1244-1252`) — `GetKeysPrefix()` carries NO trailing slash; the elems namespace is a SIBLING under the set root:

```cpp
std::string ElemRowKeyOf( const std::string &keys_prefix, const std::string &elem_key,
                          const std::string &cid_string )
{
    return keys_prefix.substr( 0, keys_prefix.size() - 1 ) + "s/" + elem_key + "/" + cid_string;
}
```

Disposed-marker enumeration goes through `GetDisposed()` under `cold_store_mutex_` (`cold_storage_gc_test.cpp:1837-1847` shape). Observable-equivalence (D-08b) asserts `HasBlock`/`getNode`/`GetNodeWithoutRequest`/evidence predicate answer identically from both order end-states.

**Layer 5 (optional wiring) — layering-safe marker seeding.** If any leg stays at the crdt link level (no `genius_node_test` whole-archive), seed `/prune/blk` rows via direct `PutRaw` — `globaldb_erase_test.cpp:1490-1516`:

```cpp
    // Direct PutRaw, NOT WritePrunedBlockEntryForTest: the helper's body lives in
    // genius_transaction_objs, which this crdt-level target must NOT
    // link (the layering ruling in src/crdt/globaldb/CMakeLists.txt - ...
    // the row written is byte-identical to the helper's (same key home,
    // same record shape).
    {
        SGTransaction::PrunedBlockRecord record;
        record.set_pruning_tx_hash( "coldfail-pruner" );
        record.set_has_erased_at_generation( true );
        record.set_erased_at_generation( 3 );
        ASSERT_TRUE( l_db.PutRaw(
                         sgns::base::Buffer{}.put( std::string( sgns::PruneEligibility::PRUNE_BLOCK_MARKER_PREFIX )
                                                   + entry_a.cid.toString().value() ),
                         sgns::base::Buffer{}.put( record.SerializeAsString() ) )
                         .has_value() );
    }
```

Prefix constants live at `PruneEligibility.hpp:415` (`PRUNE_MARKER_PREFIX = "/prune/tx/"`) and `:421` (`PRUNE_BLOCK_MARKER_PREFIX = "/prune/blk/"`).

---

### 7. `SuperGenius/test/src/crdt/CMakeLists.txt` (config — Tier-1 registration)

**Analog:** the `cold_prune_gate_test` block (`:309-345`) — copy verbatim, substitute names:

```cmake
# ... provenance comment ...
if(SGNS_COLD_STORAGE)
addtest(cold_compose_matrix_test
    cold_compose_matrix_test.cpp
)

target_include_directories(cold_compose_matrix_test PRIVATE
    ${AsyncIOManager_INCLUDE_DIR}
)

target_link_libraries(cold_compose_matrix_test
    sgns-blockstore::sgns-blockstore
    crdt_globaldb
    crdt_datastore
    rocksdb
    genius_node_test
    p2p::p2p_logger
    logger
)

if(MSVC)
    target_link_options(cold_compose_matrix_test PUBLIC /WHOLEARCHIVE:$<TARGET_FILE:genius_node_test>)
elseif(APPLE)
    target_link_options(cold_compose_matrix_test PUBLIC -force_load "$<TARGET_FILE:genius_node_test>")
else()
    target_link_options(cold_compose_matrix_test PUBLIC
        "-Wl,--whole-archive"
        "$<TARGET_FILE:genius_node_test>"
        "-Wl,--no-whole-archive"
    )
endif()

set_tests_properties(cold_compose_matrix_test PROPERTIES LABELS "Tier1")
endif()
```

Non-negotiables (documented at `:88-91`): `addtest` has NO LABELS support — `set_tests_properties(... PROPERTIES LABELS "Tier1")` is mandatory; registered ONLY under `if(SGNS_COLD_STORAGE)` because it links `sgns-blockstore::sgns-blockstore`; the label-count audit contract applies. For the Tier-3 leg use the `cold_prune_live_smoke_test` block (`:439-470`): same link set, `set_tests_properties(cold_compose_live_smoke_test PROPERTIES LABELS "Tier3")`.

**ctest registration names (Pitfall 6 — verify steps must use THESE, never source filenames):** `cold_compose_matrix_test` (new), `cold_prune_gate_test`, `cold_prune_toctou_test`, `cold_evidence_matrix_test`, `cold_storage_fault_race_test`, `cold_storage_gc_test`, `globaldb_erase_test`, `globaldb_integration_test`, `crdt_test`, `node_startup_test`.

---

### 8. `SuperGenius/test/src/crdt/cold_compose_live_smoke_test.cpp` (NEW — Tier-3 live SC3 leg, D-11b)

**Analog:** `cold_prune_live_smoke_test.cpp:533-575` — env-gated opt-in with LOUD skip carrying the deterministic stand-in pointer and runbook reference:

```cpp
        const char *binary = std::getenv( "SGNS_BLOCKSTORE_TEST_MINIO_BIN" );
        if ( binary == nullptr || std::string( binary ).empty() )
        {
            GTEST_SKIP() << "[SGNS_COLD_PRUNE][LIVE-SMOKE] MinIO binary not provided (set "
                            "SGNS_BLOCKSTORE_TEST_MINIO_BIN; COMMUNITY build — never the license-gated "
                            "minio.exe; runbook: thirdparty/sgns-blockstore/docs/testing-tiers.md). "
                            "Deterministic stand-in: cold_prune_gate_test LEG 1 (Tier-1, real drainer "
                            "transitions over injected clients).";
        }
```

Leg shape: real MinIO child process (`MinioChildProcess server; server.Start(binary, data_dir, &spawn_error)`), `PollUntil(TcpPortAnswers(...), 30s)`, then the live stack build and the real GC-pass-disposes → TxPruner-defers sequence asserting the stranded counter (D-11b: a real GC pass disposes, a subsequent cycle defers). Use a distinct `test-data/cold-compose-live/` dir lane.

---

### 9. `.planning/workstreams/rocksdb-backup/notes/<starvation-ruling>.md` (NEW — D-12 ruling doc)

**Analog:** `.planning/workstreams/rocksdb-backup/notes/develop-merge-erase-vs-cold-storage-gap.md` — workstream-level analysis note: dated header with context commits, ruled model sections with decision provenance, options-considered framing, and forward pointers (v2 `DisposedDurable` in REQUIREMENTS Future, Phase 17 measurement, Phase 18 policy). The planning doc must carry: the full starvation analysis (journal deleted → NoRecord → defer forever), the D-10 split-counter ruling, the one-cycle observability lag (research Pitfall 4), the rejected erase-on-disposed option, and the v2 pointer. Home is Agent's Discretion (`notes/` has exactly this precedent).

---

## Shared Patterns

### Barrier discipline — never sleeps
**Source:** `cold_storage_fault_race_test.cpp:237-289` (`WindowGate`), `:229-235` (`EnvOr`), `cold_prune_toctou_test.cpp:137-148` (`PollUntil`)
**Apply to:** every real-thread leg in `cold_compose_matrix_test` and the live leg. cv-wait barriers, poll predicates with deadlines, env knobs on every nondeterministic test, destructor-release so failing ASSERTs never hang teardown.

### Dedicated counter, never a failure reason
**Source:** `TxPruner.hpp:92-103` (counter fields with deferral-semantics doc comments) + `TxPruner.cpp:396-413` (INFO surfacing)
**Apply to:** the D-10 stranded counter — field beside the existing cold counters, surfaced in the INFO line, never an error return.

### TEST-ONLY hook declaration + fixture-clear discipline
**Source:** `globaldb.hpp:527-553`, `TxPruner.hpp:282-302`, statics at `globaldb.cpp:810-812` / `TxPruner.cpp:132`
**Apply to:** the new observe-and-continue seam. Doxygen `@brief`/`@param`/`@note` with "PRODUCTION CODE MUST NEVER CALL" + "Pass nullptr to clear"; fixtures clear hooks in teardown.

### Hermetic cold fixture recipe
**Source:** `cold_prune_gate_test.cpp:10-22` (header contract), `cold_storage_fault_race_test.cpp:712-760` (SetUp: real hot RocksDB + LocalBlockStore + fake←counting←timing S3 chain + `cold_store_mutex_`)
**Apply to:** every Tier-1 leg — real RocksDB/GlobalDB, InMemory S3 fakes at `hermetic.invalid`, zero network/services, distinct dir lanes per fixture.

### Exact-prefix enumeration — never substring matching
**Source:** `cold_storage_gc_test.cpp:1794-1814` (snapshot lambda), `:1244-1252` (`ElemRowKeyOf` no-trailing-slash rule)
**Apply to:** every D-07/D-08 keyspace assertion (set rows, tombstones, heads, both marker namespaces, binary CID keys, disposed markers via `GetDisposed()`).

### Red-first counter-tests
**Source:** `cold_prune_toctou_test.cpp:15-33` (authored-against-observable-failing + identifiable failure tokens)
**Apply to:** the SC1 window counter-test and the SC3 defer test (D-11): author against the pre-fix line, observe the stale-serve/undifferentiated-counter signature, then land the fix.

## No Analog Found

| Item | Role | Why no exact analog | Nearest substitute |
|------|------|---------------------|--------------------|
| Fire-and-continue hook contract (SC1 window seam) | test seam in `globaldb.cpp/.hpp` | Every existing GlobalDB seam hook is abort-on-`true` (`SetEraseInterruptHookForTest` steps 1-3); none returns-and-continues mid-compose. The contract itself is NEW (research Open Question 1 recommends a sibling hook, documented as NOT an abort seam) | `kInterruptAfterColdGate`'s observe-only usage (`TxPruner.cpp:273-283` — hook returns false, observation only) for the usage pattern; `SetEraseInterruptHookForTest` for the declaration/static/plumbing shape |

## Metadata

**Analog search scope:** `SuperGenius/src/crdt/globaldb/`, `SuperGenius/src/crdt/impl/`, `SuperGenius/src/transaction/`, `SuperGenius/test/src/crdt/`, `.planning/workstreams/rocksdb-backup/notes/`
**Files scanned:** 14 read in full-or-targeted ranges; all cross-checked against 16-RESEARCH.md's Anchor Re-Location Record (supersets agree; no conflicts found)
**Tracked-source verification:** `git -C SuperGenius ls-files` at HEAD `af644481f` — all 9 code analogs tracked
**Pattern extraction date:** 2026-11-18
**Staleness horizon:** Phase 16's own edits will re-drift `EraseEntry`, `ColdGateAdmitsGroup`, and the hook families — executors must re-grep anchors before editing (16-RESEARCH.md expiry rule)
