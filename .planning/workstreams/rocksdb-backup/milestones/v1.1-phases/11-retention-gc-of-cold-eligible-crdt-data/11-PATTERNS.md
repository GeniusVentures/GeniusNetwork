# Phase 11: Retention GC of Cold-Eligible CRDT Data - Pattern Map

**Mapped:** 2026-10-27
**Files analyzed:** 16 (2 new test suites + 1 live-tier binary/evidence set + 13 modified)
**Analogs found:** 14 / 16 (2 genuinely novel artifacts, both flagged with nearest-mechanics analogs)

All analog paths below were verified git-tracked (`git ls-files` run inside each submodule: `SuperGenius`, `thirdparty/sgns-blockstore`, `GeniusWallet`). No mirror or install-tree paths are cited.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `thirdparty/sgns-blockstore/src/LocalBlockStore.cpp` | store implementation | batch (atomic WriteBatch) | itself — `EvictLocal` (:800-824), `Put` batch (:356-366), `MarkUploadedDurableMany` (:655-720) | exact |
| `thirdparty/sgns-blockstore/include/sgns-blockstore/LocalBlockStore.hpp` | store interface | request-response | itself — concrete-backend-only section (`MarkUploadedDurableMany`/`GetUploadsInState`/`EvictLocal` decls) | exact |
| `SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp` | service (background thread decl) | event-driven | itself — drainer lifecycle decls (`Start`/`Stop`/`kEvictionDurabilityGate`/status atomics) | exact |
| `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp` | service (background thread impl) | event-driven + batch | itself — `Start` (:79-152), `Stop` (:153-200), `AdvanceDurabilityOnce` (:411), `RefreshStagingStats` (:549) | exact |
| `SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp` | status/config boundary types | request-response | itself — `ColdStorageStatus` plain-type fields + `ColdUploadState` enum | exact |
| `SuperGenius/src/crdt/globaldb/globaldb.hpp` | factory/options types | request-response | itself — `ColdStorageOptions::BackpressureOptions`/`DurabilityOptions` nested structs | exact |
| `SuperGenius/src/crdt/globaldb/globaldb.cpp` | controller (config parse + lifecycle) | file-I/O transform + request-response | itself — `ParseColdStorageConfig` `(d1b)` durability block (~:254-289) + `StartBackupLoop`/`StopBackupLoop` (:835-883) | exact |
| `SuperGenius/src/crdt/cold_read_fallback.hpp` | hook interface | request-response | itself — `HasLocalCold` virtual (~:82-96) | exact |
| `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` | component (dedup/read path) | request-response | itself — `HasBlock` cold-dir term (:680-685), `DeleteCIDBlock` (:1102-1110) | exact |
| `SuperGenius/src/account/GeniusNode.cpp` | config bootstrap | file-I/O | itself — `LoadCrdtConfig` (:557-640) | exact |
| `SuperGenius/test/src/crdt/cold_storage_config_gate_test.cpp` | test | transform | itself — `Durability*` matrix (:374-436) | exact |
| `SuperGenius/test/src/crdt/cold_storage_gc_test.cpp` (NEW) | test (SC1/SC2 guard + faults) | event-driven + batch | `SuperGenius/test/src/crdt/cold_storage_durability_test.cpp` | exact-shape |
| `SuperGenius/test/src/crdt/cold_storage_gc_retrievability_test.cpp` (NEW) | test (GC-03 legs) | request-response | `SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp` (Phase-9 harness) | role-match |
| `SuperGenius/test/src/crdt/CMakeLists.txt` | build config | — | itself — `cold_storage_durability_test` registration block (end of file) | exact |
| `thirdparty/sgns-blockstore/test/local_block_store_test.cpp` (+ `test/CMakeLists.txt`) | test (library slice) | batch | itself + `local_block_store_crash_test.cpp` | exact |
| Live-tier GC E2E binary + evidence/runbook (NEW, e.g. `thirdparty/sgns-blockstore/test/s3d_gc_e2e.cpp` + `docs/evidence/gc-e2e/`) | test (dev-gated live) | streaming E2E | `thirdparty/sgns-blockstore/test/s3d_roundtrip_e2e.cpp` | role-match |
| `GeniusWallet/assets/crdt_config.json` | config asset | file-I/O | Phase-7 blank-form precedent — **INVERTED: must NOT change** (Pitfall 5) | guard |

## Pattern Assignments

### `thirdparty/sgns-blockstore/src/LocalBlockStore.cpp` (store implementation, batch)

**Analog:** itself — `EvictLocal` (:800-824) is the destructive-batch shape the D-16 primitive (`EvictLocalAndMarkDisposed`) composes; `Put` (:356-366) is the birth-atomic batch the spill-timestamp side CF rides; `MarkUploadedDurableMany` (:655-720) is the read-gate-then-one-batch shape.

**Destructive batch pattern** (EvictLocal, :800-824 — copy verbatim, extend with `spill_times` delete + `disposed_cids` Put):
```cpp
result<void, BlockStatus> LocalBlockStore::EvictLocal(const Cid& cid)
{
    ValidateCidHash(cid);
    if (auto gate = FaultGate(fault_))
    {
        return gate.value();
    }
    auto key = MakeKey(cid);
    if (!key)
    {
        return key.error();
    }
    // Unconditional (D-10): journal state is NEVER consulted, and
    // deleting absent keys succeeds - the post-state (no local bytes
    // remain) holds whether or not anything existed, which is exactly
    // the idempotence contract.
    rocksdb::WriteBatch batch;
    batch.Delete(impl_->blocks_, KeySlice(key.value()));
    batch.Delete(impl_->journal_, KeySlice(key.value()));
    const auto committed = impl_->db_->Write(impl_->wo_, &batch);
    if (!committed.ok())
    {
        return MapStatus(committed, "EvictLocal: removal commit failed");
    }
    return outcome::success();
}
```

**Birth-atomic batch pattern** (Put, :356-366 — add `batch.Put(impl_->spill_times_, ...)` inside the `!already_present` guard so the timestamp is written in the SAME WriteBatch):
```cpp
    rocksdb::WriteBatch batch;
    batch.Put(impl_->blocks_, KeySlice(key.value()),
              rocksdb::Slice(reinterpret_cast<const char*>(bytes.data()),
                             bytes.size()));
    if (!already_present)
    {
        batch.Put(impl_->journal_, KeySlice(key.value()),
                  JournalRecord::Encode(UploadState::PendingUpload));
    }
    const auto committed = impl_->db_->Write(impl_->wo_, &batch);
```

**CF-descriptor extension pattern** (Open, ~:217-273 — `create_missing_column_families = true` is already set; add the two new CFs as descriptor entries + `handles[N]` assignment):
```cpp
        rocksdb::DBOptions db_options;
        db_options.create_if_missing = true;
        db_options.create_missing_column_families = true;
        // ...
        const std::vector<rocksdb::ColumnFamilyDescriptor> cf_descriptors = {
            rocksdb::ColumnFamilyDescriptor{},
            {kBlocksColumnFamilyName, rocksdb::ColumnFamilyOptions()},
            {kUploadJournalColumnFamilyName, rocksdb::ColumnFamilyOptions()},
        };
```

**Enumeration pattern** (GetUploadsInState, :559-594 — the retention scan and `GetDisposed()` trim enumeration copy this iterator loop: snapshot-consistent CF iterator, byte-lexicographic order, undecodable keys skipped): see file; the body iterates `impl_->db_->NewIterator(impl_->ro_, impl_->journal_)`, decodes state, decodes CID key, skips failures, and maps iterator status at the end.

**Error handling:** every RocksDB status goes through `MapStatus(status, context)` (:160+) — IO/lock/busy map to `TemporarilyUnavailable`, never `NotFound`. Preserve for `Unreadable`-vs-`NoRecord` distinction (MI-02).

---

### `thirdparty/sgns-blockstore/include/sgns-blockstore/LocalBlockStore.hpp` (store interface)

**Analog:** itself — the "Concrete backend-only surface" section (`MarkUploadedAccepted`/`MarkUploadedDurable`/`MarkUploadedDurableMany`/`GetUploadState`/`GetUploadsInState`/`EvictLocal` declarations, each with Doxygen `@brief/@param/@return/@warning`).

**Pattern:** new methods (`GetSpilledAt` / `GetDurableWithSpillTime` / `EvictLocalAndMarkDisposed` / `IsDisposed` / `GetDisposed` + trim) land in that SAME section as concrete `LocalBlockStore` methods — **never as pure virtuals on `BlockStore`/`BlockStoreTooling`** (frozen-contract discipline; the manager holds the concrete type). Publish new CF-name constants beside `kBlocksColumnFamilyName`/`kUploadJournalColumnFamilyName` (~:28-35) and the `DisposedRecord` content struct beside `UploadState` (~:42-48). Follow the `@warning` precedent of `EvictLocal` (:785-790 — its warning literally names this milestone's durability-gated eviction).

---

### `SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp` / `.cpp` (service, event-driven + batch)

**Analog:** itself — the drainer is the twice-proven own-thread pattern the GC thread mirrors (CONTEXT D-06).

**Thread lifecycle pattern** (`ColdStorageManager.cpp` `Start`, :79-152 — the GC thread copies this shape: idempotent guard, stop-flag reset, seeding scan, cv-poll loop; per CONTEXT/RESEARCH §6.2 the GC pass replaces `DrainOnce(); AdvanceDurabilityOnce();` and the tick begins with `RefreshStagingStats()` + `staging_healthy_` gate):
```cpp
    void ColdStorageManager::Start()
    {
        if ( thread_.joinable() )
        {
            return; // already running - idempotent
        }
        // ... one-time WARN posture ...
        stop_flag_.store( false );
        drain_requested_.store( false );
        current_delay_ = std::chrono::milliseconds( options_.drain_interval_ms );
        failure_streak_ = 0;
        thread_        = std::thread(
            [this]()
            {
                {
                    std::lock_guard<std::mutex> lock( *cold_store_mutex_ );
                    auto accepted = local_block_store_->GetUploadsInState( /* ... */ );
                    // restart seeding from ONE journal scan
                }
                while ( !stop_flag_.load() )
                {
                    MarkBusy();
                    const bool quiescent = DrainOnce();
                    AdvanceDurabilityOnce( quiescent );
                    MarkIdle();

                    std::unique_lock<std::mutex> lock( wait_mutex_ );
                    const bool                   woken = wait_cv_.wait_for(
                        lock, current_delay_, [this] { return stop_flag_.load() || drain_requested_.load(); } );
                    lock.unlock();

                    if ( stop_flag_.load() )
                    {
                        break; // between-cycles stop check guarantees join termination
                    }
                }
            } );
    }
```

**Bounded-stop pattern** (`Stop`, :153-186 — flag → notify → bounded grace on `idle_cv_` → unconditional join; the GC join slots into the manager's `Stop()` after the final-flush block, mirroring how the final flush was added in Phase 10):
```cpp
    void ColdStorageManager::Stop()
    {
        stop_flag_.store( true );
        wait_cv_.notify_all();
        if ( thread_.joinable() )
        {
            std::unique_lock<std::mutex> lock( idle_mutex_ );
            idle_cv_.wait_for( lock, kShutdownGraceWindow, [this] { return idle_; } );
            lock.unlock();
            thread_.join();
        }
        // Phase-10 D-04 final flush follows here AFTER the join...
```

**Header-decl pattern** (`ColdStorageManager.hpp`): copy the layout — public constants (`kEvictionDurabilityGate` — cite it in the GC gate, state must be EXACTLY `UploadedDurable`), `DurabilityOptions` nested struct (the template for `RetentionOptions`: age/dry-run/interval/grace with 0-means-default), then private state split into "drainer-thread-only" (no sync needed — in-memory evicting marks D-15 go here) vs "status atomics" (`std::atomic<size_t>`/`std::atomic<bool>` read lock-free by `GetStatus()` — the gc_* fields go here), plus `admin_mutex_` serialization for `RefreshStagingStats()` (:549 — the GC tick calls this BEFORE reading `staging_healthy_`).

**DI shape:** the manager is constructed BEFORE `CrdtDatastore` exists — add a post-construction `AttachGcDependencies(...)` (ungated hooks interface), called in `GlobalDB::Init` right after `m_crdtDatastore` is created (globaldb.cpp :766) and BEFORE `GlobalDB::Start()` starts the GC thread (`StartColdStorageManager()` at :912-914, invoked from `Start()` at :943).

---

### `SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp` (boundary types)

**Analog:** itself — `ColdStorageStatus` (struct at ~:45-77) and `ColdUploadState` (~:27-38).

**Pattern:** every new GC status field is a defaulted PLAIN member appended to `ColdStorageStatus` (Phase-8 D-08 "fields can grow"), exactly as Phase 10 appended the flush/staging blocks with their `// PLAIN TYPES ONLY (Pitfall 5 ...)` comments:
```cpp
    struct ColdStorageStatus
    {
        size_t              pending_upload_count{ 0 };
        ColdStorageWatermark watermark{ ColdStorageWatermark::None };
        bool                drainer_healthy{ false };
        // ... Phase-10 flush + staging fields, each defaulted, each
        // commented with its decision letter ...
        bool     staging_healthy{ false };     ///< conservative predicate (D-12) - the GC-inhibition signal Phase 11 consumes
        // v1.1 Phase 11 additions follow the SAME shape:
        // bool gc_enabled{false}; bool gc_dry_run{false}; ...
    };
```
`ColdUploadState` gains an additive `Unreadable` value (MI-02 entrance decision) — append-only like the existing `NoRecord/Pending/Accepted/Durable` set. New bridges (`StartColdStorageGc`/`StopColdStorageGc`/`GetColdGcStatus` as needed) copy the null-safe shape of `StartColdStorageManager`/`StopColdStorageManager`/`GetColdStorageManagerStatus` (~:180-215). NO sgns-blockstore type may cross this header.

---

### `SuperGenius/src/crdt/globaldb/globaldb.hpp` / `.cpp` (controller: config parse + lifecycle)

**Analog:** itself — two templates.

**(1) Strict nested-config parse** (`ParseColdStorageConfig`, the `(d1b)` durability block ~:254-289 — the literal template for the `retention` block; D-04's required age adds a post-loop check that the age key was seen):
```cpp
            // (d1b) D-11 (Phase 10): nested "durability" sub-object ...
            if ( key == "durability" )
            {
                if ( !member->value.IsObject() )
                {
                    return outcome::failure(
                        std::string( "crdt_config.json: 'blockstore.durability' must be an object" ) );
                }
                for ( auto sub = member->value.MemberBegin(); sub != member->value.MemberEnd(); ++sub )
                {
                    const std::string sub_key = sub->name.GetString();
                    const bool is_uint_key =
                        ( sub_key == "flush_min_interval_ms" || sub_key == "flush_max_interval_ms" );
                    if ( !is_uint_key )
                    {
                        return outcome::failure(
                            "crdt_config.json: unknown key 'blockstore.durability." + sub_key + "'" );
                    }
                    if ( !sub->value.IsUint() )
                    {
                        return outcome::failure( "crdt_config.json: 'blockstore.durability." + sub_key
                                                 + "' must be a uint" );
                    }
                    // ... assign ...
                }
                continue; // handled - never falls into the string/bool checks
            }
```
Plus the normalization discipline (`(d3)` ~:335-355): 0-means-default POST-parse, cross-field rules judged on EFFECTIVE values with both numbers in the error string. The retention block adds: `retention_age_ms` REQUIRED (`retention` present without it ⇒ loud, per D-04), `dry_run` bool, `gc_interval_ms`/`grace_ms` uint (D-07/D-13). `LogSummary()` (:100-117) gains the non-secret retention knobs only.

**(2) Own-thread lifecycle** (`StartBackupLoop`/`StopBackupLoop`, :835-883 — the original member of the pattern; `ShutdownNow`'s ordering at :476-515 shows where the GC join lives: `StopBackupLoop()` → `StopColdStorageManager()` (GC join extends INSIDE this slot, after the drainer join/final flush) → `StopColdReadService()` → lifecycle-mutex teardown):
```cpp
    void GlobalDB::ShutdownNow()
    {
        // ...
        StopBackupLoop();
        // D-11 (v1.1 Phase 8): the drainer stops IMMEDIATELY AFTER the
        // backup loop and BEFORE the lifecycle_mutex_ teardown block -
        // bounded grace then join while the stores still live.
        StopColdStorageManager();
        // READ-02 (v1.1 Phase 9): the re-warm worker stops beside the
        // drainer and still BEFORE the lifecycle-mutex teardown ...
        StopColdReadService();
        // ... broadcaster/crdt_datastore teardown, m_datastore.reset() ...
```
The retention-inert WARN (§5.3 interplay: `retention` present while gate (e) leaves cold storage disabled) lands at the `LoadCrdtConfig` call site posture — one line, never silent-disable.

**Construction-order integration point** (Init, :714-766): `OpenColdStorageStack` (:714) → `StartColdReadService()` (:731) → `dagSyncer` with hook (:750) → `m_crdtDatastore` LAST (:766). The GC dependency attach slots between :766 and `Start()`.

---

### `SuperGenius/src/crdt/cold_read_fallback.hpp` (hook interface)

**Analog:** itself — `HasLocalCold` (~:82-96) is the exact declaration shape `HasDisposed(cid)` copies (bool contract, freeze-safe, local point lookup only, Doxygen `@note` explaining the pubsub-receive-path freeze hazard):
```cpp
        /**
         * @brief       Cold-dir presence check, LOCAL TIER ONLY (D-08/D-09).
         * @param[in]   cid the content identifier
         * @return      true when the cold dir holds the CID; false on
         *              absence AND on any non-authoritative failure (the
         *              bool contract must never block or throw for the
         *              freeze-sensitive pubsub-path callers - D-08)
         * @note        NEVER performs S3 or network I/O: HasBlock runs on
         *              the pubsub receive path where remote I/O re-opens
         *              the whole-node-freeze hazard (D-08).  */
        virtual bool HasLocalCold( const CID &cid ) = 0;
```
`HasDisposed` = same shape, one line of semantics changed ("marker hit = already integrated; reads never consult it — D-12"). Implementation lives in the gated `ColdReadService` (or the manager) — this header stays free of every sgns-blockstore type.

---

### `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` (component: dedup + LRU)

**Analog:** itself — `HasBlock` (:663-685). The D-11 disposed-marker term slots AFTER the Phase-9 cold-dir term (~:680-685), same gating shape:
```cpp
    outcome::result<bool> GraphsyncDAGSyncer::HasBlock( const CID &cid ) const
    {
        auto getNodeResult       = GetNodeFromMerkleDAG( cid );
        auto getCachedNodeResult = GrabCIDBlock( cid );

        if ( getNodeResult.has_value() || getCachedNodeResult.has_value() )
        {
            return true;
        }

        // D-09 (v1.1 Phase 9): third check, cold-dir presence - gated on
        // the hook being non-null ... LOCAL TIER ONLY (D-08) ...
        if ( cold_read_hook_ != nullptr && cold_read_hook_->HasLocalCold( cid ) )
        {
            return true;
        }

        return false;
    }
```
New fourth term: `if ( cold_read_hook_ != nullptr && cold_read_hook_->HasDisposed( cid ) ) { return true; }` — three call sites inherit with zero audits: `pubsub_broadcaster_ext.cpp:632` (`AddMultiCIDInfo` route dedup), `crdt_datastore.cpp:706` (head processing), `:1881` (job status).

**LRU invalidation** (`DeleteCIDBlock`, :1102-1110 — currently LRU-only; the D-16 hot-cleanup step calls it AFTER the hot-store deletes so `HasBlock` stays honest — A6):
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

**Walk mechanics (ANTI-PATTERN WARNING):** `TraverseCIDsLinks` (:921-1043) is the nearest iterative-walk precedent (`std::deque` work queue + visited set, per-node `getLinks()`) — copy ONLY the deque/visited mechanics. Its `isResolved` skips (:950-955, :1009-1012) mark PROCESSING state, not reachability; reusing them under-counts reachability ⇒ wrongful eviction (the one unsafe direction, RESEARCH Pitfall 1). The GC walk traverses every link unconditionally. Node reads go through `GetNodeWithoutRequest` (:687-711) — hot-first then cold chain, `dagMutex_` held only inside `GetNodeFromMerkleDAG` (per-node granularity, never across batches).

---

### `SuperGenius/src/account/GeniusNode.cpp` (config bootstrap)

**Analog:** itself — `LoadCrdtConfig` (:557-640). The strict-parse call + throw + one-line-log-only-when-enabled shape is already in place and needs NO structural change for retention (parse errors flow through the existing `throw std::runtime_error( cold_storage_result.error() )`; the `LogSummary()` line extends automatically):
```cpp
        // Strict tri-state "blockstore" parse (INTG-02, v1.1 Phase 7). ...
        auto cold_storage_result = crdt::GlobalDB::ParseColdStorageConfig( config_text );
        if ( cold_storage_result.has_error() )
        {
            throw std::runtime_error( cold_storage_result.error() );
        }
        cold_storage_config_ = cold_storage_result.value();
        // Pitfall 9: nothing new is logged when disabled - one info line
        // ONLY when enabled, and it carries LogSummary() ...
        if ( cold_storage_config_.enabled )
        {
            node_logger_->info( "crdt_config.json: cold storage blockstore enabled: {}",
                                cold_storage_config_.LogSummary() );
        }
```
The only likely addition: the retention-present-but-inert WARN (retention configured while cold storage disabled — RESEARCH §5.3), placed in this same function, one rate-free line.

---

### `SuperGenius/test/src/crdt/cold_storage_config_gate_test.cpp` (test, transform)

**Analog:** itself — the `Durability*` matrix (:374-436). Copy the exact five-test shape for `Retention*`:
```cpp
TEST( ColdStorageConfigGate, DurabilityUnknownKeyFails )
{
    auto result = Parse( std::string( kEnabledConfigBody ) + R"(, "durability": {"bogus": 1}}})", NoEnv() );
    ASSERT_TRUE( result.has_error() );
    EXPECT_NE( result.error().find( "unknown key 'blockstore.durability.bogus'" ), std::string::npos );
}

TEST( ColdStorageConfigGate, DurabilityOnlySectionDisables )
{
    // Phase-7 (e) inheritance: a durability-only section never activates
    // cold storage (the wallet blank form relies on it).
    auto result = Parse( R"({"blockstore": {"durability": {"flush_min_interval_ms": 250}}})", NoEnv() );
    ASSERT_FALSE( result.has_error() );
    EXPECT_FALSE( result.value().enabled );
}
```
Retention matrix (RESEARCH §5 "Code Examples"): `RetentionAbsentSubObjectDisablesGc` (D-02), `RetentionWithoutAgeFails` (D-04 — the NEW twist, no durability analog), `RetentionUnknownKeyFails`, `RetentionDryRunAndKnobsParseAndNormalize` (0-takes-only-its-default per-knob semantics, :384-395 precedent), `RetentionInertWhenBlockstoreBlank` (§5.3 + the WARN). This file stays registered UNCONDITIONALLY (not under `SGNS_COLD_STORAGE`) so the Tier-1 lane is non-empty on OFF builds.

---

### `SuperGenius/test/src/crdt/cold_storage_gc_test.cpp` (NEW — SC1/SC2 guard + eligibility + fault tests)

**Analog:** `SuperGenius/test/src/crdt/cold_storage_durability_test.cpp` — copy its file-header comment discipline, fixture, and helpers wholesale.

**Fixture + fake-wiring pattern** (:1-145): direct manager construction over a real `LocalBlockStore` on a fresh temp dir, `InMemoryS3Client` + `InMemoryS3AdminClient` fakes via the relative include dir, `PollUntil` bounded-wait helper (never fixed sleeps), `NextUniqueDir` short-path discipline (Windows MAX_PATH), `MakeCid`/`SpanOf` helpers:
```cpp
// Internal fakes - relative-include-dir privilege (test-surface only).
#include "InMemoryS3AdminClient.hpp"
#include "InMemoryS3Client.hpp"

#include "crdt/globaldb/BlockStoreBackedIpfsDatastore.hpp"
#include "crdt/globaldb/ColdStorageManager.hpp"
```
```cpp
    /// Bounded poll loop with deadline - never a fixed sleep, so the suite
    /// stays stable on loaded Windows CI-equivalent machines.
    bool PollUntil( const std::function<bool()> &predicate,
                    std::chrono::milliseconds       deadline,
                    std::chrono::milliseconds       step = std::chrono::milliseconds( 10 ) )
```
Header-comment landmines to copy: "every library result is guarded with `has_value()` BEFORE `.value()/.error()` (policy::terminate alias)" and the `sgns::CID`-vs-library-`Cid` wrap note.

**Test-name pattern:** `TEST_F( ColdStorageDurabilityTest, eviction_gate_constant_and_per_cid_state )` (:607) and `crash_reconciliation_mixed_leftovers` (:646) are the direct precedents for the GC gate/fault cases; the fault kit surface (`SetFlipBytesForKey`, `S3FaultKind`, `S3AdminFaultKind`, `CrashPoint::BeforeCommit` on `LocalBlockStore`) drives crash-mid-grace and crash-between-halves tests. The SC1 keyspace guard's prefix-spy hot datastore is a test-local decorator injected as the GC's hot-store dependency (see No Analog Found).

---

### `SuperGenius/test/src/crdt/cold_storage_gc_retrievability_test.cpp` (NEW — GC-03 legs)

**Analog:** `SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp` (Phase-9 chain harness: chain Get CID-verification via `SetFlipBytesForKey`, rehydrate-silence assertions) — evict a CID through a driven GC pass, then prove both legs: `GetNodeWithoutRequest` resolves via the S3 fake CID-verified and rehydrated, and the responder chain (`HasBlock`/`GetNodeWithoutRequest` cold-serve) serves it; both legs additionally assert the D-12 split (no read path surfaces NotFound). Two-GlobalDB in-process graphsync lane (optional strongest form): the `globaldb_integration.cpp` / pubsub-graphsync harness shape per RESEARCH §8.2.

---

### `SuperGenius/test/src/crdt/CMakeLists.txt` (build config)

**Analog:** itself — the `cold_storage_durability_test` block at the end of the file (copy verbatim per new suite):
```cmake
if(SGNS_COLD_STORAGE)
addtest(cold_storage_durability_test
    cold_storage_durability_test.cpp
)

target_link_libraries(cold_storage_durability_test
    sgns-blockstore::sgns-blockstore
    crdt_globaldb
)

target_include_directories(cold_storage_durability_test PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../../../../thirdparty/sgns-blockstore/src"
)

set_tests_properties(cold_storage_durability_test PROPERTIES LABELS "Tier1")
endif()
```
The config-gate extension stays in the unconditional block (mid-file). Tier-label discipline: hermetic GC suites = `Tier1`; live/MinIO = `Tier2`/`Tier3` only, never in the CI lane.

---

### `thirdparty/sgns-blockstore/test/local_block_store_test.cpp` + `test/CMakeLists.txt` (library tests)

**Analog:** itself + `local_block_store_crash_test.cpp` (reopen/no-flush-close oracle discipline). New library cases: spill-timestamp written-at-birth and absent-for-pre-existing-records (backfill), reopen-an-old-store-dir auto-creates the new CFs (A1 coverage — fixture dirs exist under `test-data/local-blockstore*`), `EvictLocalAndMarkDisposed` batch atomicity under `CrashPoint::BeforeCommit`, `IsDisposed`/`GetDisposed` roundtrip, trim bounds. Registration: `addtest(...)` + `set_tests_properties(... LABELS "Tier1")` — the per-target comment block convention (`# D-13 ...`) is mandatory in this CMakeLists (verified throughout).

---

### Live-tier GC E2E + evidence/runbook (NEW — TEST-03, dev-gated)

**Analog:** `thirdparty/sgns-blockstore/test/s3d_roundtrip_e2e.cpp` — copy the two-run fresh-process shape, the env-gate struct that names every missing var, and the loud `[SGNS_BLOCKSTORE][...]` skip lines:
```cpp
    /// @brief The env gate for BOTH runs: the S3D endpoint quartet plus
    ///        the run-state handoff path. Names every missing var.
    struct S3dE2EEnv
    {
        std::string endpoint;
        // ...
        bool ok = false;
    };
```
Registration precedent (test/CMakeLists.txt :213-226): `addtest(s3d_roundtrip_e2e ...)` + `set_tests_properties(s3d_roundtrip_e2e PROPERTIES LABELS "Tier3")` — the GC E2E is the same Tier3 class (never CI); the MinIO-binary opt-in roundtrip copies the `SGNS_BLOCKSTORE_TEST_MINIO_BIN` Tier2 shape (`s3_block_store_minio_test`, :187-203). Evidence artifacts + README runbook follow the committed-evidence precedent under `docs/evidence/s3d-spike/` (recommended home: `thirdparty/sgns-blockstore/docs/evidence/gc-e2e/` — planner-ruling discretion).

---

### `GeniusWallet/assets/crdt_config.json` (config asset — GUARD, inverted pattern)

**Current tracked content (verified):**
```json
{
  "backup_enabled": true,
  "backup_interval_minutes": 15,
  "backup_keep_count": 12,
  "backup_auto_restore_on_repair_failure": true,
  "blockstore": {
    "backpressure": {},
    "durability": {}
  }
}
```
**This file must NOT gain a `retention` key** — not even a blank `"retention": {}` (D-04 makes that a LOUD startup failure for every wallet) and never an example-with-age (would arm eviction). The Phase-7/10 blank-form parity precedent is deliberately INVERTED for destructive features (RESEARCH Pitfall 5). The planner should encode this as a guard test/assertion (e.g., the config-gate suite or review checklist asserting the asset diff contains no `retention`), not as a diff.

## Shared Patterns

### Own-thread lifecycle (never `io_`, never the pubsub asio context)
**Source:** `SuperGenius/src/crdt/globaldb/globaldb.cpp:835-883` (`StartBackupLoop`/`StopBackupLoop`) and `ColdStorageManager.cpp:79-200` (`Start`/`Stop`)
**Apply to:** the GC thread (fourth member), its shutdown join, any test that drives passes
The cv-poll loop with `wait_for` + predicate (stop-flag OR work-requested), between-cycle stop checks, `MarkBusy`/`MarkIdle` for the bounded stop grace, and the ordering slot in `ShutdownNow` (:476-515).

### Strict tri-state nested-config parsing
**Source:** `globaldb.cpp` `ParseColdStorageConfig` — `(d1b)` durability block (~:254-289), `(d3)` normalization (~:335-355), gate `(e)` (~:373-380)
**Apply to:** the `retention` sub-object parse, the required-age rule (D-04), cross-field rules, `LogSummary` extension
Present-but-not-object ⇒ loud; unknown key ⇒ loud naming `blockstore.<sub>.<key>`; wrong type ⇒ loud naming key + expected type; 0-means-default per-knob POST-parse normalization; sub-object-only sections never activate (gate (e)); errors name EFFECTIVE values.

### Single-store atomic WriteBatch (library ownership discipline)
**Source:** `thirdparty/sgns-blockstore/src/LocalBlockStore.cpp` — `Put` (:356-366), `MarkUploadedDurableMany` (:655-720), `EvictLocal` (:800-824)
**Apply to:** spill-timestamp side-CF write, `EvictLocalAndMarkDisposed`, disposed-marker trim, hot-store cleanup batch (via the hot RocksDB face)
Validate → `FaultGate` → `MakeKey` preamble; read-gates before writes; ONE `rocksdb::WriteBatch` + ONE sync `Write`; `MapStatus` for every status. The D-16 two-half composition: library batch first, idempotent hot cleanup second — never a batch mixing both stores (Pitfall 3).

### outcome::result + has_value-before-value
**Source:** every analog above; stated as a test-file landmine in `cold_storage_durability_test.cpp` header (:24-26)
**Apply to:** ALL new code — library `result<T, BlockStatus>`, SuperGenius `outcome::result`, `BOOST_OUTCOME_TRY` on pure-outcome paths; never `.value()` an unguarded result (`policy::terminate` alias). `CidOf` carries `std::error_code` — map explicitly, never `OUTCOME_TRY` across the `BlockStatus` envelope.

### Ungated-boundary plain types (header hygiene)
**Source:** `ColdStorageStack.hpp:15-22` ("deliberately free of every sgns-blockstore type") + `cold_read_fallback.hpp:1-16`
**Apply to:** every new status field, hook method, and bridge
`globaldb.hpp`, `globaldb.cpp`, `ColdStorageStack.hpp`, `cold_read_fallback.hpp` never include gated sgns-blockstore headers; `ColdStorageManager.hpp` and the decorator are GATED TU headers; defaults/null-hook checks keep OFF builds byte-identical (Phase-7 bar; `HasBlock`'s `cold_read_hook_ != nullptr` gating is the model).

### Tier-1 registration + fail-closed lane
**Source:** `SuperGenius/test/src/crdt/CMakeLists.txt` (end block) + `thirdparty/sgns-blockstore/test/CMakeLists.txt` (:1-226)
**Apply to:** every new test target
`addtest()` + `set_tests_properties(... LABELS "Tier1")`, `if(SGNS_COLD_STORAGE)` gating for library-linking suites, relative include dir for non-installed fakes (`../../../../thirdparty/sgns-blockstore/src`), unconditional config-gate suite keeps `-L Tier1 --no-tests=error` non-vacuous on OFF builds; verification runs inside `build/<Platform>/<Config>` (`.planning/codebase/TESTING.md`).

### Rate-limited, source-distinguishable logging
**Source:** `ColdStorageManager.cpp` (watermark heartbeat `kHeartbeatPeriod`, one-time `Start()` WARN) + `globaldb.cpp` `LogSummary` redaction-by-omission (:100-117)
**Apply to:** all GC log lines
`gc:`-prefixed vocabulary distinguishable from `cold read:`/drain/flush/peer lines; per-pass one-line summary; rate-limited event lines; never credentials, never CIDs at info on hot paths.

## No Analog Found

Files/artifacts with no safe in-codebase analog (planner uses RESEARCH.md shapes instead):

| File / Artifact | Role | Data Flow | Reason + Nearest Mechanics |
|------------------|------|-----------|---------------------------|
| GC fresh reachability walk (inside `ColdStorageManager.cpp`) | algorithm | batch transform | Nearest walk `TraverseCIDsLinks` (graphsync_dagsyncer.cpp:921-1043) has FORBIDDEN skip semantics (`isResolved` skips :950-955/:1009-1012 under-count reachability ⇒ wrongful eviction). Copy only its `std::deque` work-queue + visited-set mechanics; traverse every link unconditionally (RESEARCH §2.3). |
| Prefix-spy hot datastore (test-local, in `cold_storage_gc_test.cpp`) | test utility | spy/decorator | No existing spy datastore in-tree. Decorator shape from `BlockStoreBackedIpfsDatastore` (wraps an `IpfsDatastore`, forwards, tallies by key prefix: binary CID keys, `<cid>sealed`, `/crdt/s/...`, `/crdt/t|k|h/`). This IS the SC1 "provably never" instrument. |
| Epoch watermark record (SC5) | model/record | batch | Novel record (per-topic min-head-height floor + max height + computed-at) — computation + storage only, nothing deletion-gated. No analog; heads heights come from `CrdtHeads::GetList`'s `max_value`/per-topic values (crdt_heads.cpp:259-285). Pin by key prefix. |
| Heads-equality re-check helper | algorithm | request-response | Novel use of a verified surface: `CrdtDatastore::GetHeadList()` → `CrdtHeads::GetList({})` (shared-lock in-memory cache read) compared against the pass-start snapshot — the §2.2 exactness lemma. No existing caller does set comparison; the snapshot source itself is the analog. |

## Metadata

**Analog search scope:** `SuperGenius/src/crdt/` (globaldb, impl), `SuperGenius/src/account/`, `SuperGenius/test/src/crdt/`, `thirdparty/sgns-blockstore/{include,src,test,docs}`, `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/impl/`, `GeniusWallet/assets/`
**Files scanned:** 20 read at cited ranges; all classification anchors verified this session (line numbers drift-checked against 11-RESEARCH.md — `ColdStorageManager.hpp` constant/struct anchors cited by symbol where Phase-10 additions shifted lines)
**Tracked-source gate:** all cited analogs verified via `git ls-files` inside their submodules (SuperGenius / sgns-blockstore / GeniusWallet) — 2026-10-27
**Pattern extraction date:** 2026-10-27
