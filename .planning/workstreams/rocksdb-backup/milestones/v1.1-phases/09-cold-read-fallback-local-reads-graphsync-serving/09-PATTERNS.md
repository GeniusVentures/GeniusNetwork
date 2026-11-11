# Phase 9: Cold Read Fallback — Local Reads & Graphsync Serving - Pattern Map

**Mapped:** 2026-10-26
**Files analyzed:** 13 (4 new, 9 modified)
**Analogs found:** 12 / 13 (1 novel mechanism — per-CID re-warm coalescing — has no in-tree analog; RESEARCH §8.1 sketch is the reference)

**Tracked-source gate (#3645):** every analog below verified `git ls-files` non-empty inside the `SuperGenius/` submodule (branch `dev_blockstore`) or the `thirdparty/sgns-blockstore` submodule. No gitignored mirror paths are named.

**Naming note:** file names for NEW files follow RESEARCH §4.2/§6.2 suggestions (`cold_read_fallback.hpp`, `ColdReadService.hpp/.cpp`, `ColdServeDagService`); the planner may rename, but the gated/ungated boundary assignments below are binding (CONTEXT constraints + Phase-7/8 header-hygiene gate).

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `SuperGenius/src/crdt/cold_read_fallback.hpp` (NEW — ungated hook interface) | interface / abstraction | request-response (`Get`, `HasLocalCold`) + event enqueue (`EnqueueRewarm`) | `SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp` (ungated bridge header, zero library types) | role-match |
| `SuperGenius/src/crdt/globaldb/ColdReadService.hpp` (NEW — gated TU header) | service (background executor) | batch / event-driven (bounded queue) | `SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp` | exact |
| `SuperGenius/src/crdt/globaldb/ColdReadService.cpp` (NEW — gated TU) | service (re-warm worker + chain impl) | batch + request-response | `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp` | exact |
| `ColdServeDagService` wrapper (NEW — ungated TU; own file or folded into `impl/graphsync_dagsyncer.cpp` — planner's call) | middleware / delegating decorator | request-response (delegate-or-enqueue, never block) | `SuperGenius/src/crdt/globaldb/BlockStoreBackedIpfsDatastore.hpp/.cpp` (delegating decorator shape) | role-match |
| `SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp` (NEW) | test (fault-injected honesty suite) | request-response under injected faults | `SuperGenius/test/src/crdt/cold_storage_spill_test.cpp` | exact |
| `SuperGenius/test/src/crdt/cold_read_freeze_latency_test.cpp` (NEW — SC2 latency-budget + freeze regression; name tentative) | test (latency benchmark) | latency-injected request-response | `cold_storage_spill_test.cpp` `LatencyInjectingS3Client` (:226-279) + `PollUntil` (:57-70) | exact |
| `SuperGenius/src/crdt/graphsync_dagsyncer.hpp` (MOD) | interface extension | — | itself: `Error` enum (:47-55), `CID_FAILURE_SUPPRESSION` constant (:154-157), ctor + members (:100, :208-215) | exact (self) |
| `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` (MOD) | read-path orchestration | request-response + peer fetch | itself: `getNode` (:205-227), `HasBlock` (:511-517), `GetNodeWithoutRequest` (:519-528), `StartSync` (:549-556), `OUTCOME_CPP_DEFINE_CATEGORY_3` (:31-56), anon-namespace constants (:19-27) | exact (self) |
| `SuperGenius/src/crdt/globaldb/globaldb.cpp` + `globaldb.hpp` (MOD) | composition root / lifecycle | construction + ordered shutdown | itself: cold seam (:604-627), DAGSyncer construction (:643), `ShutdownNow()` (:390-424), bridge methods (:791-799), members (`globaldb.hpp:480-489`) | exact (self) |
| `SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp/.cpp` + `ColdStorageStackStub.cpp` (MOD) | factory + lifecycle bridges | construction | itself: bridge trio + bundle (`ColdStorageStack.hpp:53-119`) | exact (self) |
| `SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp/.cpp` (MOD — `remote_store_mutex_` serialization) | service | batch | itself: `cold_store_mutex_` discipline (`ColdStorageManager.cpp` `DrainOnce` phases (i)-(iii), ~:137-215) | exact (self) |
| `SuperGenius/src/crdt/globaldb/BlockStoreBackedIpfsDatastore.hpp/.cpp` (MOD — expected comment/marker-touch only; `get()` STAYS a pure forward per RESEARCH §4.1) | decorator | request-response | itself: `get()` (:120-125) | exact (self) |
| `SuperGenius/test/src/crdt/CMakeLists.txt` + `SuperGenius/src/crdt/globaldb/CMakeLists.txt` (MOD) | build config | — | itself: gated test registration (`test/src/crdt/CMakeLists.txt:98-113`), gated TU split (`globaldb/CMakeLists.txt:20-31`) | exact (self) |

---

## Pattern Assignments

### `ColdReadService.hpp/.cpp` — the cold-read service + re-warm executor (NEW, gated)

**Analog:** `SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp` + `.cpp` (exact — same role, same data flow: own thread, bounded work items, shared store handles, explicit Stop/join)

**Gated-TU header banner pattern** (`ColdStorageManager.hpp:7-13`):
```cpp
 * GATED TU HEADER: compiled (and includable) ONLY under
 * SGNS_COLD_STORAGE - it carries sgns-blockstore types. globaldb.hpp and
 * globaldb.cpp reach this class EXCLUSIVELY through the ColdStorageStack
 * bridges (D-10 - no library type crosses the ungated boundary).
```
`ColdReadService.hpp` must carry the same banner; `globaldb.hpp`/`globaldb.cpp`/`ColdStorageStack.hpp` must NEVER include it.

**Thread lifecycle — `Start()` / `Stop()` / enqueue-only** (`ColdStorageManager.cpp` ~:49-108) — the cold-serve executor copies this shape exactly (flag → notify → bounded grace → unconditional join; enqueue is try-op, never runs on the caller's thread):
```cpp
    void ColdStorageManager::Start()
    {
        if ( thread_.joinable() )
        {
            return; // already running - idempotent
        }
        stop_flag_.store( false );
        ...
        thread_        = std::thread(
            [this]()
            {
                while ( !stop_flag_.load() )
                {
                    MarkBusy();
                    DrainOnce();
                    MarkIdle();

                    std::unique_lock<std::mutex> lock( wait_mutex_ );
                    const bool                   woken = wait_cv_.wait_for(
                        lock, current_delay_, [this] { return stop_flag_.load() || drain_requested_.load(); } );
                    lock.unlock();

                    if ( stop_flag_.load() )
                    {
                        break; // between-cycles stop check guarantees join termination
                    }
                    (void)woken; // drain_requested wake falls through to the next cycle
                }
            } );
    }

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
    }

    void ColdStorageManager::RequestDrain()
    {
        // SC2: enqueue ONLY - flag + notify; the single-thread loop picks
        // it up and the drain body never runs on the requester's thread.
        drain_requested_.store( true );
        wait_cv_.notify_all();
    }
```
Phase-9 deltas the executor must add on top of this shape: a **bounded queue** (compile-time `kMaxRewarmQueueDepth` ≈ 64; overflow = drop + count + rate-limited warn, NEVER block the enqueuer) and per-CID coalescing (novel — see *No Analog Found*).

**Compile-time constants pattern** (`ColdStorageManager.hpp:93-97`) — D-12's defaults live as `static constexpr` members with derivation comments, never config knobs:
```cpp
        /// Backoff multiplier per failed cycle (D-03; compile-time, D-05).
        static constexpr uint32_t kBackoffFactor = 2;
        /// Shutdown grace window for in-flight cycle work (D-11; NOT a
        /// knob - D-05).
        static constexpr std::chrono::milliseconds kShutdownGraceWindow{ 5000 };
```
RESEARCH §7.3 derives: re-warm budget 4 s, 1 worker thread, queue bound 64, shutdown grace 5 s. Mirror `kShutdownGraceWindow{ 5000 }` exactly.

**Split-phase mutex discipline for store access** (`ColdStorageManager.cpp` `DrainOnce` ~:137-215) — the cold-read chain's tier access copies the lock-scoping rules: `LocalBlockStore` ops under `cold_store_mutex_` (local RocksDB, microseconds); the S3 op phase runs with its own lock discipline (Phase 9: the NEW `remote_store_mutex_` — §6.3 remote-store serialization trap):
```cpp
        // (i) snapshot the pending set and fetch each item's bytes - local
        // RocksDB ops only, under the SHARED mutex ...
        {
            std::lock_guard<std::mutex> lock( *cold_store_mutex_ );
            auto pending = local_block_store_->GetPendingUploads();
            ...
        }
        // (ii) remote Puts with createOnly semantics - NO lock held (D-01:
        // remote S3 latency must never block the publisher).
        for ( const auto &item : items )
        {
            auto put = remote_block_store_->Put( ... );
            ...
        }
        // (iii) re-acquire the mutex: MarkUploadedAccepted ONLY for ...
```
The re-warm worker's `S3BlockStore::Get` must take `remote_store_mutex_` around the call, and the drainer's phase-(ii) Put loop gains the same lock (MinioS3Client has no concurrent-call guarantee — MinioS3Client.hpp:31-34 per RESEARCH §6.3).

**Constructor + null-check pattern** (`ColdStorageManager.cpp:23-37`):
```cpp
        ColdStorageManager::ColdStorageManager( std::shared_ptr<sgns::blockstore::LocalBlockStore> local_block_store,
                                                std::shared_ptr<sgns::blockstore::S3BlockStore>    remote_block_store,
                                                std::shared_ptr<std::mutex>                        cold_store_mutex,
                                                BackpressureOptions                                options )
            : local_block_store_( std::move( local_block_store ) ),
              ...
        {
            BOOST_ASSERT_MSG( local_block_store_ != nullptr, "local block store is nullptr" );
            ...
        }
```
Plus: deleted copy/move (`ColdStorageManager.hpp:72-75`), destructor calls `Stop()` before members die, atomics-backed status if any status getter is added.

---

### `SuperGenius/src/crdt/cold_read_fallback.hpp` — ungated hook interface (NEW)

**Analog:** `SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp` (role-match — an ALWAYS-COMPILED header that deliberately carries zero sgns-blockstore types; its :15-22 banner states the discipline verbatim):
```cpp
 * ALWAYS COMPILED - both SGNS_COLD_STORAGE build configurations link this
 * TU set - and deliberately free of every sgns-blockstore type: the real
 * implementation lives in ColdStorageStack.cpp (compiled only under
 * SGNS_COLD_STORAGE) and the stub in ColdStorageStackStub.cpp (compiled
 * when OFF). Default builds must stay pristine: no library include, no
 * library symbol, no new code path (the Phase-7 byte-identical bar).
```
The hook header may reference only `CID`, `sgns::common::Buffer`, and std types. It must live where `crdt_graphsync_dagsyncer` can include it WITHOUT linking sgns-blockstore (the gated implementation lives in `crdt_globaldb`, which links the library only under the gate — see `globaldb/CMakeLists.txt:20-31`). Placement next to `graphsync_dagsyncer.hpp` (i.e., `src/crdt/`) fits the dependency direction; the gated impl is injected at the single DAGSyncer construction site.

**Interface shape to copy** — RESEARCH "Code Examples" hook sketch (status payload replaces the library type so nothing library-shaped crosses):
```cpp
struct ColdReadStatus { enum Class { NotFound, TemporarilyUnavailable, Corrupt, Unauthorized } cls; bool fromRemoteTier; };
class ColdReadFallback
{
public:
    virtual ~ColdReadFallback() = default;
    virtual ColdReadStatus Get( const CID &cid, sgns::common::Buffer &out ) = 0;
    virtual bool           HasLocalCold( const CID &cid ) = 0;
    virtual bool           EnqueueRewarm( const CID &cid ) = 0;
    virtual void           Rehydrate( const CID &cid, const sgns::common::Buffer &bytes ) = 0;
};
```
Doxygen `@brief/@param/@return/@note` on every virtual (Coding Standards; every ColdStorageStack bridge carries one).

---

### `ColdServeDagService` — responder wrapper (NEW, ungated)

**Analog (structural):** `SuperGenius/src/crdt/globaldb/BlockStoreBackedIpfsDatastore.hpp/.cpp` — the codebase's delegating-decorator precedent: final class, ctor takes inner + asserts non-null, overrides delegate to `inner_`, every deviation is commented with its decision ID. No `MerkleDagService` wrapper exists in-tree today (the responder currently gets the raw `dagService_`), so the decorator's *shape* is the analog; the interface contract (`getNode`/`select`/`addNode`/`removeNode`/`markResolved`/`isResolved`, merkledag_service.hpp:33-46 per RESEARCH §6.2) defines the method set.

**Core rule the wrapper encodes** — the freeze-hazard comment it must preserve, `graphsync_dagsyncer.cpp:549-556` (verbatim, in `StartSync()`):
```cpp
        // Not shared_from_this(): graphsync serves incoming requests off this service on the
        // libp2p host's io_context, and GraphsyncDAGSyncer::getNode fetches a block it does not
        // have from the network, polling for up to two minutes. That pins the host's only
        // thread and freezes the whole node. Responders serve what they already hold.
        graphsync_->start( dagService_, blockCallback );
```
Phase 9 replaces the `dagService_` argument with the wrapper; the wrapper's `getNode` delegates, and on miss does `hook->EnqueueRewarm(cid)` (try-op) then **returns the failure unchanged** — the responder maps a `getNode` failure to `RS_NOT_FOUND` (graphsync_impl.cpp:368-385 per RESEARCH §1.1). Never wait, never sleep, never lock a mutex that the fetch path holds across I/O. RESEARCH "Code Examples" gives the full wrapper body to copy.

**Delegation precedent** (`BlockStoreBackedIpfsDatastore.cpp:104-119` — the pure-forward style with per-method rationale comments):
```cpp
    IPFS::outcome::result<void> BlockStoreBackedIpfsDatastore::seal( const CID &key )
    {
        // Seal markers are TEXT keys in the hot store's namespace - the
        // cold store never sees them.
        return inner_->seal( key );
    }
```

---

### `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` + `graphsync_dagsyncer.hpp` (MOD)

**Analog:** itself — the modification target; the excerpts below are the exact seams to extend.

**Chain insertion point 1 — `getNode` (:205-227):** insert the cold leg AFTER the hot miss, BEFORE `GetRouteKeys` (D-01 cold-before-peers):
```cpp
    outcome::result<std::shared_ptr<ipfs_lite::ipld::IPLDNode>> GraphsyncDAGSyncer::getNode( const CID &cid ) const
    {
        auto node = GrabCIDBlock( cid );
        if ( !node.has_error() ) { ... return node; }

        node = GetNodeFromMerkleDAG( cid );
        if ( !node.has_error() ) { ... return node; }

        // [NEW: FetchNodeFromColdStorage(cid) here — runs OUTSIDE dagMutex_]

        BOOST_OUTCOME_TRY( auto route_keys, GetRouteKeys( cid ) );
```
**Chain insertion point 2 — `GetNodeWithoutRequest` (:519-528, verbatim today):**
```cpp
    outcome::result<std::shared_ptr<ipfs_lite::ipld::IPLDNode>> GraphsyncDAGSyncer::GetNodeWithoutRequest(
        const CID &cid ) const
    {
        auto getNodeResult = GetNodeFromMerkleDAG( cid );

        if ( getNodeResult.has_value() )
        {
            return getNodeResult;
        }

        return GrabCIDBlock( cid );
    }
```
**`HasBlock` (:511-517, verbatim today) — D-08/D-09 gated cold-dir check appends after both miss:**
```cpp
    outcome::result<bool> GraphsyncDAGSyncer::HasBlock( const CID &cid ) const
    {
        auto getNodeResult       = GetNodeFromMerkleDAG( cid );
        auto getCachedNodeResult = GrabCIDBlock( cid );

        return getNodeResult.has_value() || getCachedNodeResult.has_value();
    }
```
**DO NOT TOUCH — `GetNodeFromMerkleDAG` (:1006-1010) holds `dagMutex_` (the publish mutex); no cold I/O may be added here:**
```cpp
    outcome::result<std::shared_ptr<ipfs_lite::ipld::IPLDNode>> GraphsyncDAGSyncer::GetNodeFromMerkleDAG(
        const CID &cid ) const
    {
        std::lock_guard lock( dagMutex_ );
        return dagService_->getNode( cid );
    }
```
**Error enum + category (additive value for `TemporarilyUnavailable` surfacing)** — `graphsync_dagsyncer.hpp:47-55`:
```cpp
        enum class Error : uint8_t
        {
            CID_NOT_FOUND = 0,     ///< The requested CID wasn't found
            ROUTE_NOT_FOUND,       ///< Route for the CID wasn't found
            PEER_BLACKLISTED,      ///< The peer that has the CID is blacklisted
            TIMED_OUT,             ///< The request has timed out
            DAGSYNCER_NOT_STARTED, ///< Start wasn't called, or StopSync was called
            GRAPHSYNC_IS_NULL,     ///< Graphsync member is nullptr
            HOST_IS_NULL,          ///< Graphsync member is nullptr
        };
```
and `impl/graphsync_dagsyncer.cpp:31-56` `OUTCOME_CPP_DEFINE_CATEGORY_3( sgns::crdt, GraphsyncDAGSyncer::Error, e )` — **a new enum value MUST gain a `case` in this switch** (the switch is exhaustive; missing case = silent "Unknown error"). Append the value at the END of the enum (it's `uint8_t`-valued sequentially; reordering changes serialized/compared values).
**Compile-time-constants precedent in the .cpp** — anonymous namespace at :19-27 (`kInProgressRequestTimeout`, `kTotalFetchTimeout`) with derivation comments; serve-deadline/rewarm constants follow this style in the gated TU instead.
**Test-only seam precedent** — `SetBlacklistBackoffTimeoutForTest` (`graphsync_dagsyncer.hpp:120-128`, static + `std::atomic` member, "No production caller may invoke this method") is the model if the honesty tests need a probe.
**Constructor** (`graphsync_dagsyncer.hpp:100-102`, `impl/graphsync_dagsyncer.cpp:58-60`): add the optional hook parameter LAST, defaulting to null ⇒ byte-identical disabled builds.

---

### `SuperGenius/src/crdt/globaldb/globaldb.cpp` + `globaldb.hpp` (MOD)

**Analog:** itself — Phase-8 seam + lifecycle.

**Construction seam (:604-643)** — the hook/service is constructed in the same enabled-gated block and injected into the DAGSyncer at its ONE construction site:
```cpp
        std::shared_ptr<ipfs_lite::ipfs::IpfsDatastore> block_datastore = ipfsDataStore;
        if ( cold_storage_options_.enabled )
        {
            const auto database_path_absolute = boost::filesystem::absolute( m_databasePath ).string();
            auto        stack = OpenColdStorageStack( cold_storage_options_, database_path_absolute, ipfsDataStore );
            ...
            block_datastore   = stack.value().data_store;
            cold_data_store_  = block_datastore;
            cold_manager_     = std::move( stack.value().manager );
            cold_store_mutex_ = std::move( stack.value().cold_store_mutex );
        }
        ...
        auto dagSyncer = std::make_shared<GraphsyncDAGSyncer>( block_datastore, graphsync, host );
```
Members live at `globaldb.hpp:480-489` (`cold_data_store_`, `cold_manager_` behind a forward-declared `class ColdStorageManager;` at :28 — a cold-read-service member follows the same forward-declare pattern). Disabled path must remain byte-identical: hook = null, no construction.

**Shutdown ordering (:390-402)** — the cold-read executor stop slots beside `StopColdStorageManager()`, BEFORE the lifecycle-mutex teardown (in-flight re-warms finish their decorator writes while the stores live):
```cpp
        //SetIncomingBroadcastEnabled( false );
        StopBackupLoop();
        // D-11 (v1.1 Phase 8): the drainer stops IMMEDIATELY AFTER the
        // backup loop and BEFORE the lifecycle_mutex_ teardown block -
        // bounded grace then join while the stores still live.
        StopColdStorageManager();
```
**Bridge-method pattern (:791-799)** — new lifecycle methods delegate to null-safe free bridges, never to the gated class directly:
```cpp
    void GlobalDB::StopColdStorageManager()
    {
        sgns::crdt::StopColdStorageManager( cold_manager_ );
    }
```

---

### `ColdStorageStack.hpp/.cpp` + `ColdStorageStackStub.cpp` (MOD)

**Analog:** itself — the bridge trio. New bridges (`StartColdReadService`/`StopColdReadService` or a bundle field + bridges) copy the null-safe signature style (`ColdStorageStack.hpp:96-119`):
```cpp
    /**
     * @brief      Stop the drainer thread with bounded grace then join
     *             (null-safe no-op when null; D-11).
     * @param[in]  manager the bundle's manager (may be null)
     */
    void StopColdStorageManager( const std::shared_ptr<ColdStorageManager> &manager );
```
`ColdStorageBundle` (`ColdStorageStack.hpp:64-71`) gains the cold-read service handle (and the new `remote_store_mutex_` if the planner routes it through the bundle). **ODR landmine:** the stub and the real TU define the SAME symbols by design — any new bridge must be added to BOTH `ColdStorageStack.cpp` and `ColdStorageStackStub.cpp` (`globaldb/CMakeLists.txt:4-11` comment documents the violation risk).

**Assembly style** (`ColdStorageStack.cpp:36-130`): try/catch around library Open factories (they throw `std::invalid_argument` on bad options — "a loud outcome failure, never a throw through the embedder"), every library result guarded `has_value()` BEFORE `.value()`/`.error()`, failure strings carry `BlockStatus` detail but never credentials ("redaction by omission").

---

### `SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp` (+ freeze/latency test) (NEW)

**Analog:** `SuperGenius/test/src/crdt/cold_storage_spill_test.cpp` (exact — same hermetic direct-construction discipline: real `LocalBlockStore` on a fresh temp dir + `InMemoryS3Client` fake behind `S3BlockStore` + shared mutex + test-local inner datastore; NO GlobalDB scaffolding).

**Harness utilities to copy verbatim** (spill test :57-137):
- `PollUntil(predicate, deadline, step=10ms)` — "never a fixed sleep, so the suite stays stable on loaded Windows CI-equivalent machines" (the re-warm-completion waits need this)
- `NextUniqueDir()` / `FreshDir()` — short relative paths under the build tree (Windows MAX_PATH), wipe-before-Open
- `MakeCid(payload)` — `CidOf(SpanOf(payload), MulticodecType::Code::RAW)` (library CID constructor)
- `FastOptions(...)` — short-interval manager options shape

**The rehydrate-silence spy analog — `FakeInnerDatastore`** (spill test :140-207): a test-local in-memory `IpfsDatastore` counting `set`/`seal` calls is exactly the SC4 "exactly set (+optional seal) fire; zero broadcast" observer. Extend it with call recording; a fake broadcaster is only needed if the planner tests at a layer that can reach one (the decorator `set()` never reaches `Broadcast` by construction — RESEARCH §2.3).

**Fault + latency kit**:
- Op-level fault: `InMemoryS3Client` `SetFault(S3Op::Get, S3FaultKind::Unavailable)` and `SetFaultForKey` (InMemoryS3Client.hpp:75-110) — the SC1 no-NotFound-escape script
- Corruption: `SetFlipBytesForKey(key, true)` — the `Corrupt + Remote` detector; Local-tier corruption via `FaultKind::CorruptData` on `LocalBlockStore` (publicly inherits `FaultController`, LocalBlockStore.hpp:117-122)
- Latency: mirror `LatencyInjectingS3Client` (spill test :226-279 — a `~55-line S3Client` subclass, atomic per-op delay, delegates everything else) **with the sleep moved to `Get`** for the SC2 benchmark:
```cpp
    class LatencyInjectingS3Client final : public sgns::blockstore::S3Client
    {
    public:
        LatencyInjectingS3Client( std::shared_ptr<InMemoryS3Client> inner,
                                  std::chrono::milliseconds           per_put_latency )
            : inner_( std::move( inner ) ), latency_ms_( per_put_latency.count() ) {}
        void SetPutLatency( std::chrono::milliseconds per_put_latency )
        {
            latency_ms_.store( per_put_latency.count() );
        }
        sgns::blockstore::result<sgns::blockstore::S3PutResult, sgns::blockstore::BlockStatus> Put(
            const std::string &key, const std::vector<uint8_t> &bytes,
            const sgns::blockstore::PutObjectOptions &options = {} ) override
        {
            const auto latency = latency_ms_.load();
            if ( latency > 0 ) { std::this_thread::sleep_for( std::chrono::milliseconds( latency ) ); }
            return inner_->Put( key, bytes, options );
        }
        ... // Get/Head/Delete delegate
```

**Test registration** — `test/src/crdt/CMakeLists.txt:98-113` verbatim (gated block + fake-header relative include + MANDATORY `set_tests_properties` because `addtest()` has no LABELS support; :50-54 comment states the convention; the unconditional `cold_storage_config_gate_test` at :79-88 keeps the Tier-1 lane non-empty on OFF builds):
```cmake
if(SGNS_COLD_STORAGE)
addtest(cold_storage_fallback_test
    cold_storage_fallback_test.cpp
)

target_link_libraries(cold_storage_fallback_test
    sgns-blockstore::sgns-blockstore
    crdt_globaldb
)

target_include_directories(cold_storage_fallback_test PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../../../../thirdparty/sgns-blockstore/src"
)

set_tests_properties(cold_storage_fallback_test PROPERTIES LABELS "Tier1")
endif()
```

---

### `BlockStoreBackedIpfsDatastore.hpp/.cpp` (MOD — marker-comment touch only)

**Analog:** itself. `get()` (:120-125) carries the Phase-9 marker and STAYS a pure forward (RESEARCH §4.1: the chain must NOT land here — `get()` is reached both under `dagMutex_` and inline on the single-thread responder):
```cpp
    IPFS::outcome::result<BlockStoreBackedIpfsDatastore::Value> BlockStoreBackedIpfsDatastore::get(
        const CID &key ) const
    {
        // Phase 9 adds the cold fallback; today: pure forward.
        return inner_->get( key );
    }
```
The only expected edit: update the marker comment to point at where the chain actually landed. The rehydrate write path (`set()`, :49-95) is reused UNCHANGED — its journal-then-hot-write composition is SC4's dedicated path (RESEARCH §2.1 proves re-journal idempotency).

---

### `SuperGenius/src/crdt/globaldb/CMakeLists.txt` (MOD)

**Analog:** itself — gated TU split (:20-31) + unity-build exclusion (:10-11). New gated TUs (`ColdReadService.cpp` and, if separate, the hook impl) join the `SGNS_COLD_STORAGE` block AND the `SKIP_UNITY_BUILD_INCLUSION` list:
```cmake
set_source_files_properties(ColdStorageStack.cpp ColdStorageStackStub.cpp
    ColdStorageManager.cpp BlockStoreBackedIpfsDatastore.cpp PROPERTIES SKIP_UNITY_BUILD_INCLUSION ON)
...
if(SGNS_COLD_STORAGE)
target_sources(crdt_globaldb PRIVATE
    ColdStorageStack.cpp
    ColdStorageManager.cpp
    BlockStoreBackedIpfsDatastore.cpp
)
target_link_libraries(crdt_globaldb PRIVATE sgns-blockstore::sgns-blockstore)
else()
target_sources(crdt_globaldb PRIVATE
    ColdStorageStackStub.cpp
)
endif()
```
If the new bridge symbols are added, `ColdStorageStackStub.cpp` must define them too (same-symbol ODR rule above).

---

## Shared Patterns

### 1. Gated-TU / ungated-boundary hygiene (applies to EVERY new file)
**Source:** `ColdStorageStack.hpp:15-22` banner, `ColdStorageManager.hpp:7-13` banner, `BlockStoreBackedIpfsDatastore.hpp:7-15` banner, `globaldb/CMakeLists.txt:4-31`.
Rules: (a) `globaldb.hpp`, `globaldb.cpp`, `ColdStorageStack.hpp` NEVER include gated sgns-blockstore-carrying headers; (b) the hook interface + wrapper compile ungated with zero library types; (c) gated impls live only in `crdt_globaldb` under `SGNS_COLD_STORAGE`; (d) stub defines the same bridge symbols; (e) disabled build = nothing constructed = byte-identical (null hook ⇒ `HasBlock`/`GetNodeWithoutRequest`/`getNode`/responder unchanged).

### 2. Own-thread lifecycle — never `io_`, never the pubsub asio context
**Source:** `ColdStorageManager.hpp:26-45` (design comment), `.cpp` Start/Stop excerpt above.
**Apply to:** the re-warm executor and any cold-serve worker. Shape: own `std::thread` + cv + `stop_flag_` + `idle_cv_` grace + unconditional join; destructor calls `Stop()`; enqueue = flag/try-queue + notify ONLY. The responder wrapper itself spawns nothing and waits never.

### 3. Library result landmine — `result<T, BlockStatus>` uses `policy::terminate`
**Source:** `ColdStorageStack.cpp:13-15` ("Every library result is guarded with has_value() BEFORE .value()/.error() - the library result alias uses policy::terminate (Cid.hpp landmine)"); spill test :36-38; `BlockStoreBackedIpfsDatastore.cpp:83-92` (the `catch ( const std::invalid_argument &e )` pattern for out-of-set multihash throws at library entry).
**Apply to:** every direct `LocalBlockStore`/`S3BlockStore` call in the chain, executor, and tests. An unguarded `.error()` on a success value (or vice versa) TERMINATES the node — this bit prior phases.

### 4. Rate-limited BlockStatus logging, redaction by omission
**Source:** `BlockStoreBackedIpfsDatastore.hpp:62-72` (`ShouldLogJournalFailure`, `kJournalFailureLogInterval{1}`, suppressed-count) + `.cpp:66-80`:
```cpp
                        logger_->error(
                            "cold-storage journal write failed (code {}), {} more suppressed",
                            static_cast<int>( journaled.error().code ),
                            suppressed_journal_failures_ );
```
**Apply to:** all cold-read failure lines (§3.4 wording: cold vs peer distinguishable, `BlockStatus.code` only, no CID stringification on hot paths, never endpoint/credential values). Also `ColdStorageStack.cpp` failure-message style: `"cold storage: ... failed (" + status.message + ")"`.

### 5. `outcome::result` + additive error-enum extension
**Source:** `graphsync_dagsyncer.hpp:47-55` + `impl/graphsync_dagsyncer.cpp:31-56` (`OUTCOME_CPP_DEFINE_CATEGORY_3` switch).
**Apply to:** the `TemporarilyUnavailable` surfacing (research OQ4 recommends additive enum value `COLD_STORAGE_TEMPORARILY_UNAVAILABLE` appended AFTER `HOST_IS_NULL`, with its `case` added to the category switch). Never reorder existing values.

### 6. Shared-mutex store serialization
**Source:** `ColdStorageStack.cpp` (single `cold_store_mutex` created once, shared by decorator + drainer), `ColdStorageManager.cpp` split-phase lock scopes.
**Apply to:** new `remote_store_mutex_` (S3 Get vs drainer Put serialization — §6.3 trap) created in the stack factory, threaded through the bundle, taken per-call by both the drainer phase (ii) and the re-warm worker.

### 7. Coding-standard conventions (Coding Standards.md / AGENTS.md — binding on all files)
- Ullman/Allman braces on their own line, indented (every excerpt above demonstrates)
- PascalCase types/functions; trailing-underscore members (`dagService_`, `cold_store_mutex_`); `kCamelCase` compile-time constants (`kShutdownGraceWindow`, `kTotalFetchTimeout`)
- `Get`/`Is`/`Set` accessor prefixes; `BOOST_ASSERT_MSG` nullptr checks in constructors; deleted copy/move on thread-owning classes
- Doxygen `@brief/@param[@param[in]/@param[out]/@return/@note` blocks on every public header declaration (decision-ID comments in prose: "D-05", "SC2" — the Phase-7/8 files cite their decisions inline; Phase 9 files must cite READ-01/READ-02/D-01..D-12/SC1..SC5 the same way)
- Include guards `SUPERGENIUS_CRDT_<MODULE>_HPP`; namespace `sgns::crdt`; `outcome::result<T>` for fallible ops; `gsl::span<const uint8_t>` for buffer views

### 8. Test discipline (hermetic Tier-1)
**Source:** spill test file banner (:1-40) + `TESTIG.md` conventions; `test/src/crdt/CMakeLists.txt:50-54`.
**Apply to:** direct construction (no GlobalDB/libp2p), `PollUntil` not fixed sleeps, `has_value()` guards, `static_cast<void>` inside `EXPECT_THROW` where needed, gated registration + `set_tests_properties(... LABELS "Tier1")`, unconditional config-gate test keeps `ctest -L Tier1 --no-tests=error` honest on OFF builds. The SC2 latency benchmark never compares ON-vs-OFF builds — distributions under identical injected latency only (Phase-8 SC1 rule).

---

## No Analog Found

| File / Mechanism | Role | Data Flow | Reason | Reference Instead |
|------|------|-----------|--------|-------------------|
| Per-CID re-warm coalescing (`std::map<CID, RewarmState>` + mutex, attach-or-find-hot; RESEARCH §8.1) | utility (dedup state) | event-driven | No in-tree per-key in-flight dedup exists; nearest spirit is the drainer's flag+notify but it has no keyed state | RESEARCH §8.1 sketch (explicitly "no futures, no waiter lists — nobody waits"); do NOT build shared_future fan-out |
| `BlockStatus{StatusClass, BlockSource}` → seam mapping table (SC3) | transform (error taxonomy) | transform | Novel table — no existing BlockStatus→`GraphsyncDAGSyncer::Error` translation exists (the decorator logs codes raw) | RESEARCH §3.2 table (authoritative; enum verbatim from `thirdparty/sgns-blockstore/include/sgns-blockstore/BlockStatus.hpp:29-55`, git-tracked in the sgns-blockstore submodule) |

Everything else has an in-tree analog listed above.

## Metadata

**Analog search scope:** `SuperGenius/src/crdt/**` (globaldb, impl, headers), `SuperGenius/test/src/crdt/`, `SuperGenius/src/crdt/globaldb/CMakeLists.txt`, `thirdparty/sgns-blockstore/include/` (via RESEARCH-verified citations; tracked in its own submodule)
**Files scanned:** 12 analog sources read directly (ColdStorageManager.hpp/.cpp, ColdStorageStack.hpp/.cpp, BlockStoreBackedIpfsDatastore.hpp/.cpp, graphsync_dagsyncer.hpp + impl sections, globaldb.cpp sections, cold_storage_spill_test.cpp sections, both CMakeLists)
**Tracked-source gate:** all named SuperGenius analogs verified via `git ls-files` on submodule branch `dev_blockstore` (2026-10-26)
**Pattern extraction date:** 2026-10-26
