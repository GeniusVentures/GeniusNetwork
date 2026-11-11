# Phase 12: Integration Hardening, Fault Races & Fresh-Clone Proof - Pattern Map

**Mapped:** 2026-10-27
**Files analyzed:** 12 (new + modified)
**Analogs found:** 12 / 12 (11 exact, 1 role-match)

All analog paths verified git-tracked (`git ls-files` non-empty inside their submodule: SuperGenius, thirdparty/sgns-blockstore). No gitignored/mirror paths cited.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `SuperGenius/test/src/crdt/cold_storage_fault_race_test.cpp` (NEW — SC1 matrix + D-12 audit walk + jitter legs) | test | event-driven (barrier-synchronized concurrency) | `SuperGenius/test/src/crdt/cold_storage_gc_test.cpp` | exact |
| `SuperGenius/test/src/crdt/cold_storage_resurrection_test.cpp` (NEW — SC2 counter-test) | test | pub-sub | `SuperGenius/test/src/graphsync/pubsub_graphsync_test.cpp` | exact |
| `SuperGenius/test/src/crdt/cold_storage_soak_test.cpp` (NEW — SC3 iteration soak + teardown + restart) | test | streaming (sustained publish under fault) | `cold_storage_spill_test.cpp` `s3d_down_window_keeps_publishing` + `cold_storage_durability_test.cpp` `shutdown_under_load_slow_flush_bounded` | exact |
| `SuperGenius/test/src/crdt/cold_storage_wallclock_soak*.cpp` (NEW — dev-gated wall-clock binary, name at discretion) | test (dev-gated, NEVER Tier-1) | streaming | `thirdparty/sgns-blockstore/test/s3d_gc_e2e.cpp` + `docs/evidence/gc-e2e/` | exact |
| `SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp` (MODIFY — D-16 seam declarations) | service (additive test seam) | event-driven | `SetGcMidPassHookForTesting` in the same header | exact |
| `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp` (MODIFY — D-16 seam impl + invocation) | service (additive test seam) | event-driven | `SetGcMidPassHookForTesting` impl + invocation sites in the same TU | exact |
| `SuperGenius/test/src/crdt/` S3 timing decorator (NEW — test-local `S3Client` wrapper: latency/on-op hooks; § RESEARCH "Alternatives" first choice) | utility (test helper) | request-response (decorator) | `CountingS3Client` in `cold_storage_gc_test.cpp:338-381` | exact |
| `SuperGenius/.github/workflows/cmake.yml` (MODIFY — permanent ON leg D-02a + fake-source overlay §5.3) | config (CI) | batch | Existing matrix include legs + "Download thirdparty release" + "Tier-1 fail-closed lane" steps | exact |
| `SuperGenius/.github/workflows/build-release-tags.yml` (MODIFY — ON configure + run-tests posture D-02b + overlay) | config (CI) | batch | Existing `thirdparty_tag`/`run_tests` inputs + download step + exit-78 gates | exact |
| `SuperGenius/test/tier1_audit_check.cmake` (NEW — tier-label audit port SC4 + registration) | utility (build-time static audit) | batch (static scan) | `thirdparty/sgns-blockstore/test/tier1_audit_check.cmake` | exact |
| `SuperGenius/test/src/crdt/CMakeLists.txt` (MODIFY — register new suites + optional `SGNS_BLOCKSTORE_TEST_SRC_DIR` override) | config (build) | batch | Existing cold-storage registration blocks in the same file | exact |
| Fresh-clone checklist evidence doc (NEW — D-05; location at discretion) | docs | n/a | `thirdparty/sgns-blockstore/docs/evidence/gc-e2e/README.md` (trio format, lighter posture) | role-match |

## Pattern Assignments

### `SuperGenius/test/src/crdt/cold_storage_fault_race_test.cpp` (test, event-driven)

**Analog:** `SuperGenius/test/src/crdt/cold_storage_gc_test.cpp` — the real-fixture harness the matrix builds on (real hot RocksDB + spy + counting S3 + decorator + ColdReadService + driven GC passes).

**Fixture pattern** (`cold_storage_gc_test.cpp:599-660` — copy this composition; it is exactly the evict/serve/drain actor set):
```cpp
class ColdStorageGcTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        // The REAL hot CRDT RocksDB store ... wrapped in the SC1 spy.
        hot_dir_ = FreshDir( "hot" );
        // ... rocksdb::create( hot_dir_, hot_options );
        spy_      = std::make_shared<PrefixSpyHotStore>( real_hot_ );
        // The cold tier (the durability-suite fixture shape).
        shared_local_dir_ = FreshDir( "cold" );
        // ... LocalBlockStore::Open ...
        fake_       = std::make_shared<InMemoryS3Client>();
        counting_   = std::make_shared<CountingS3Client>( fake_ );
        auto opened_remote = S3BlockStore::Open( counting_ );
        // ...
        // ONE underlying RocksDB wrapped TWICE (production shared-DB shape)
        auto ipfs_db = sgns::ipfs_lite::rocksdb::create( real_hot_->getDB() );
        inner_     = std::make_shared<sgns::ipfs_lite::ipfs::RocksdbDatastore>( ipfs_db.value() );
        decorator_ = std::make_shared<BlockStoreBackedIpfsDatastore>(
            inner_, shared_local_, cold_store_mutex_, sgns::base::createLogger( "ColdStorageGc" ) );
        // The REAL cold-read chain as the DAGSyncer hook (cold-dir term,
        // disposed-marker term, direct-read cold chain)
        remote_store_mutex_ = std::make_shared<std::mutex>();
        cold_read_service_  = std::make_shared<ColdReadService>(
            shared_local_, remote_, cold_store_mutex_, remote_store_mutex_, decorator_ );
        dagsyncer_ = std::make_shared<GraphsyncDAGSyncer>(
            decorator_, nullptr, nullptr /* no graphsync/host needed for the no-request path */,
            cold_read_service_ );
        broadcaster_ = std::make_shared<NoopBroadcaster>();
        crdt_        = CrdtDatastore::New(
            real_hot_, HierarchicalKey( "/namespace" ), dagsyncer_, broadcaster_,
            CrdtOptions::DefaultOptions() );
```

**Manager construction + driven-pass seam** (`cold_storage_gc_test.cpp:678-695` — races drive `GcPassOnce` from the test thread):
```cpp
    std::shared_ptr<ColdStorageManager> MakeManager(
        const ColdStorageManager::BackpressureOptions &backpressure,
        const ColdStorageManager::DurabilityOptions   &durability,
        const ColdStorageManager::RetentionOptions    &retention )
    {
        auto remote_store_mutex = std::make_shared<std::mutex>();
        manager_                = std::make_shared<ColdStorageManager>(
            shared_local_, remote_, cold_store_mutex_, remote_store_mutex,
            backpressure, durability, fake_admin_, retention );
        manager_->AttachGcDependencies( crdt_.get(), dagsyncer_.get(), spy_ );
        return manager_;
    }
```

**Age backdating + durability wait** (`cold_storage_gc_test.cpp:735-750` — the deterministic no-sleep eviction rhythm; Pitfall 2 requires explicit tiny positive `grace_ms`):
```cpp
    void WaitAllDurable( const std::vector<Cid> &cids )
    {
        ASSERT_TRUE( PollUntil( [&] { return AllInState( cids, UploadState::UploadedDurable ); },
                                std::chrono::milliseconds( 10000 ) ) )
            << "seed blocks did not reach UploadedDurable within deadline";
    }

    void Backdate( const Cid &cid, uint64_t age_ms )
    {
        std::lock_guard<std::mutex> lock( *cold_store_mutex_ );
        auto written = shared_local_->SetSpilledAt( cid, UnixNowMs() - age_ms );
        ASSERT_TRUE( written.has_value() );
    }
```

**Zero-S3-traffic probe** (`cold_storage_gc_test.cpp:1739-1745` — the D-12 audit-walk observability style):
```cpp
    const uint64_t gets_before = counting_->get_calls();
    // ... scenario ...
    EXPECT_EQ( counting_->get_calls(), gets_before )
```

**Naming/structure:** anonymous namespace for helpers; `@given/@when/@then` block comments above each `TEST_F` (see `cold_storage_spill_test.cpp:719-724`); `TEST_F( ColdStorageSpillTest, name )` underscore_naming.

---

### `SuperGenius/test/src/crdt/cold_storage_resurrection_test.cpp` (test, pub-sub)

**Analog:** `SuperGenius/test/src/graphsync/pubsub_graphsync_test.cpp` — the ONLY real two-GlobalDB in-process libp2p harness in-tree (Pitfall 8: 11-03 did NOT rebuild this wire; use this file, not "the 11-03 lane").

**Two-node topology pattern** (`pubsub_graphsync_test.cpp:91-186` — two `GossipPubSub`, separate io_contexts per host, real `GlobalDB::New` pairs):
```cpp
TEST_F( PubsubGraphsyncTest, MultiGlobalDBTest )
{
    std::string binaryPath = boost::dll::program_location().parent_path().string();
    std::string basePath1  = binaryPath + "/pubsub_graphsync_pubs1";
    std::string basePath2  = binaryPath + "/pubsub_graphsync_pubs2";
    // ...
    sgns::test::removeAllWithRetry( basePath1 );
    sgns::test::removeAllWithRetry( basePath2 );
    // ...
    auto pubs1        = std::make_shared<sgns::ipfs_pubsub::GossipPubSub>();
    auto start1Future = pubs1->Start( 0, {} );
    auto pubs2        = std::make_shared<sgns::ipfs_pubsub::GossipPubSub>();
    auto start2Future = pubs2->Start( 0, {} );
    // One shared private context here races both hosts' yamux WriteQueue:
    // each scheduler runs on its own host's io_context.
    auto io_context  = pubs1->GetAsioContext();
    auto io_context2 = pubs2->GetAsioContext();
    auto scheduler   = std::make_shared<libp2p::basic::SchedulerImpl>(
        std::make_shared<libp2p::basic::AsioSchedulerBackend>( io_context ),
        libp2p::basic::Scheduler::Config{ std::chrono::milliseconds( 100 ) } );
    // ...
    auto globaldb_ret1 = sgns::crdt::GlobalDB::New( io_context, basePath1, pubs1,
        sgns::crdt::CrdtOptions::DefaultOptions(), graphsyncnetwork, scheduler, generator );
    auto globaldb_ret2 = sgns::crdt::GlobalDB::New( io_context2, basePath2, pubs2,
        sgns::crdt::CrdtOptions::DefaultOptions(), graphsyncnetwork2, scheduler2, generator2 );
    // ...
    gdb1->AddBroadcastTopic( "test1" );
    gdb2->AddBroadcastTopic( "test1" );
```

**Imports pattern** (`pubsub_graphsync_test.cpp:1-36`): `testutil/wait_condition.hpp` (`assertWaitForCondition`), `testutil/remove_all.hpp` (`removeAllWithRetry`), `crdt/globaldb/globaldb.hpp`, `crdt/dagsyncer.hpp`, graphsync network headers, per-host `SchedulerImpl`/`AsioSchedulerBackend`.

**Second analog (matrix-adjacent legs):** `OnMessage`-level driving with a hand-encoded `BroadcastMessage` — the 11-03 storm-test pattern already proven in `SuperGenius/test/src/crdt/cold_storage_gc_retrievability_test.cpp` (registered same block style; zero-S3-Get dedup asserts via `counting_->get_calls()`). Full-wire once (SC2's letter); `OnMessage`-level for the rest.

**Resurrection forcing:** driven `GcPassOnce()` passes + explicit tiny `RetentionOptions{ retention_age_ms = 1, grace_ms = 1 }` + `SetSpilledAt` backdating (Pitfall 2: `grace_ms == 0` normalizes to 60000 — `ColdStorageManager.hpp:96-106`).

---

### `SuperGenius/test/src/crdt/cold_storage_soak_test.cpp` (test, streaming under fault)

**Analog 1 — outage window + watermark + drain (D-06/D-08):** `SuperGenius/test/src/crdt/cold_storage_spill_test.cpp:725-775`:
```cpp
TEST_F( ColdStorageSpillTest, s3d_down_window_keeps_publishing )
{
    fake_->SetFault( sgns::blockstore::S3Op::Put, sgns::blockstore::S3FaultKind::Unavailable );
    auto manager = MakeManager( FastOptions( 100, 5, 10 ) );
    manager->Start();

    // First six sets: crosses Warn (>=5, <10) observably.
    for ( int i = 0; i < 6; ++i )
    {
        const std::string payload = "outage window payload " + std::to_string( i );
        CID               cid_key( MakeCid( payload ) );
        auto res = decorator_->set( cid_key, IpfsDatastore::Value( SpanOf( payload ) ) );
        ASSERT_TRUE( res.has_value() ) << "set() must succeed during the outage";
    }
    ASSERT_TRUE( PollUntil( [&] { return manager->GetStatus().watermark == ColdStorageWatermark::Warn; },
                            std::chrono::milliseconds( 10000 ) ) )
        << "watermark must reach Warn";
    // ... Critical ...
    EXPECT_FALSE( manager->GetStatus().drainer_healthy );

    // Heal: everything drains, watermark recovers to None (down-crossing).
    fake_->ClearFaults();
    ASSERT_TRUE( PollUntil( [&] {
        const auto status = manager->GetStatus();
        return status.pending_upload_count == 0 && status.watermark == ColdStorageWatermark::None;
    },
                            std::chrono::milliseconds( 10000 ) ) )
        << "post-heal catch-up must drain fully and recover the watermark";
    manager->Stop();
}
```
The soak composes this with: flush-cadence faults (`fake_admin_->SetAdminFault( S3AdminFaultKind::Unreachable/FlushFails )` — separate state from the data-path outage), GC inhibition (staging-unhealthy), peer cold-fetch attempts, and graphsync serving (D-08 full-stack actors). Assert `pending_upload_count <= distinct_published_cids` at sampled points (no-multiply, D-06).

**Analog 2 — teardown-under-load with bounded Stop (D-09):** `SuperGenius/test/src/crdt/cold_storage_durability_test.cpp:809-856`:
```cpp
TEST_F( ColdStorageDurabilityTest, shutdown_under_load_slow_flush_bounded )
{
    auto inner     = std::make_shared<FakeInnerDatastore>();
    auto decorator = std::make_shared<BlockStoreBackedIpfsDatastore>(
        inner, shared_local_, cold_store_mutex_, sgns::base::createLogger( "ColdStorageDurability" ) );

    auto manager = MakeManager( FastOptions(), FastDurability( 10000, 20000 ) );
    manager->Start();

    std::atomic<bool> publishing{ true };
    std::thread publisher( [&] { /* decorator->set loop, 5 ms pacing */ } );

    ASSERT_TRUE( PollUntil( [&] { return manager->GetStatus().accepted_upload_count >= 2; },
                            std::chrono::milliseconds( 10000 ) ) );
    fake_admin_->SetSlowFlushDelayMs( 3000 ); // > kFinalFlushBudgetMs (2000)

    const auto   stop_start = std::chrono::steady_clock::now();
    manager->Stop();
    const auto   stop_elapsed_ms = /* duration ms */;
    publishing.store( false );
    publisher.join();

    const int64_t bound_ms = ColdStorageManager::kShutdownGraceWindow.count()
                           + ColdStorageManager::kFinalFlushBudgetMs.count() + 3000 /* margin */;
    std::cout << "[measurement] Stop() under SlowFlush load returned in " << stop_elapsed_ms
              << " ms (bound " << bound_ms << " ms)\n";
    EXPECT_LT( stop_elapsed_ms, bound_ms ) << "Stop() must stay bounded by grace + final budget";
```
Phase 12 extends the load mix with the GC actor + in-flight evict marks (join order verified: backup loop → drainer [+final flush] → GC thread → cold-serve executor — `globaldb.cpp:584-629`, `ColdStorageManager.cpp:260-353`).

**Analog 3 — kill-9/restart reconciliation (D-09 leg 2):** `cold_storage_spill_test.cpp:656-723` `crash_restart_reconciles` — journal with NO manager started (crash shape), scoped release of the store handle, reopen same dir with fresh fake PRE-LOADED with one block, then:
```cpp
    ASSERT_TRUE( PollUntil( [&] {
        const auto status = manager->GetStatus();
        return status.pending_upload_count == 0 && status.drainer_healthy;
    },
                            std::chrono::milliseconds( 10000 ) ) );
    // Exactly N distinct remote objects - nothing lost, nothing duplicated.
    EXPECT_EQ( fake2->ObjectKeys().size(), kBlocks );
```
In-process surrogate for the iteration lane; true two-fresh-process kill-9 is the wall-clock soak's runbook leg (next assignment).

---

### Wall-clock soak binary + committed evidence (test, dev-gated — NEVER Tier-1)

**Analog:** `thirdparty/sgns-blockstore/test/s3d_gc_e2e.cpp` + `thirdparty/sgns-blockstore/docs/evidence/gc-e2e/` (README.md + run-capture.md + stats-capture.txt — the evidence trio D-07 names as the standard).

**Gating/doc pattern** (`thirdparty/sgns-blockstore/docs/evidence/gc-e2e/README.md:1-30`):
```markdown
# GC Live-Tier Evidence (TEST-03, v1.1 Phase 11 plan 11-04)

Dev-gated live evidence that the Phase-11 GC vertical — spill → GC →
retrieve — works against the REAL s3d backend. Never CI: both targets are
env-gated with loud labelled skips and labeled Tier2/Tier3 only.

## Env gates (NAMES only — never commit values)
- `SGNS_BLOCKSTORE_TEST_S3D_ENDPOINT` — ...
```
Copy: env-gated skips with loud labels, Tier2/Tier3 labels only (never Tier1), two-fresh-process run procedure (`--gtest_filter=...SpillRun` / `...EvictRun`), committed captures with env NAMES only (redaction precedent: credential-value-shape must be 0).

---

### `SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp` + `.cpp` (MODIFY — D-16 seams)

**Analog:** `SetGcMidPassHookForTesting` — the exact seam contract, in the same files. New seams (pre-delete-batch at top of per-mark processing; post-heads-re-check/pre-HALF1; between HALF1↔HALF2) copy this shape verbatim.

**Declaration pattern** (`ColdStorageManager.hpp:262-272`):
```cpp
        /**
         * @brief      TEST-ONLY mid-pass hook (the library's
         *             SetCrashPointForTesting precedent): invoked between
         *             the pass-start heads snapshot/walk and the
         *             heads-equality finalization - the seam the
         *             heads-change abort case uses to mutate heads inside
         *             the pass window. PRODUCTION CODE MUST NEVER CALL
         *             SetGcMidPassHookForTesting.
         * @param[in]  hook the callback (null clears)
         */
        void SetGcMidPassHookForTesting( std::function<void()> hook );
```

**Implementation + invocation pattern** (`ColdStorageManager.cpp:702-706` setter; `:974-980` guarded invocation under `gc_hook_mutex_`):
```cpp
    void ColdStorageManager::SetGcMidPassHookForTesting( std::function<void()> hook )
    {
        std::lock_guard<std::mutex> lock( gc_hook_mutex_ );
        gc_mid_pass_hook_ = std::move( hook );
    }
    // ... at the crossing (EvaluatePass):
            std::lock_guard<std::mutex> lock( gc_hook_mutex_ );
            if ( gc_mid_pass_hook_ )
            {
                gc_mid_pass_hook_();
            }
```

**Where the new seams land (verified anchors in `ColdStorageManager.cpp`):** `ProcessDueMarks` at `:1072`; per-mark defer check `:1089-1094`; delete-time re-check (CURRENT heads vs the MARK's snapshot — Pitfall 5) `:1111-1119`; **HALF1** `EvictLocalAndMarkDisposed` at `:1122` under `cold_store_mutex_`; **HALF2** `RunHotCleanup( mark.cid, mark.hot_row_keys )` at `:1133` — deliberately OUTSIDE `cold_store_mutex_` (Pitfall 6: never widen the lock; drive the window instead). Header hygiene binding since Phase 7: `ColdStorageManager.hpp` is a GATED TU header (`SGNS_COLD_STORAGE` only) — seams are inert-by-default, null in production, documented per seam.

**Library-side hook precedent (second analog):** `thirdparty/sgns-blockstore/src/InMemoryS3AdminClient.hpp:88-93`:
```cpp
        /**
         * @brief Optional hook invoked after every (non-faulted-at-entry)
         *        Flush completes - the barrier point tests use to observe
         *        an in-flight flush from the scripting thread.
         * @note CONFORMANCE-TEST SEAM: production code MUST NOT call this.
         */
        void SetOnFlush( std::function<void()> hook );
```

---

### Test-local S3 timing decorator (NEW helper — latency/on-op hooks + jitter)

**Analog:** `CountingS3Client` in `SuperGenius/test/src/crdt/cold_storage_gc_test.cpp:338-381` — the proven test-local `S3Client` wrapper; the timing decorator is the same shape plus per-op latency (deadline-bounded, NOT unbounded sleep) and an on-op barrier callback fired BEFORE/OUTSIDE delegating:

```cpp
    /**
     * @brief Test-local S3Client wrapper counting Get calls before
     *        delegating to the in-memory fake - the D-11 zero-S3-traffic
     *        probe (the fallback-suite CountingS3Client shape).
     */
    class CountingS3Client final : public sgns::blockstore::S3Client
    {
    public:
        explicit CountingS3Client( std::shared_ptr<InMemoryS3Client> inner )
            : inner_( std::move( inner ) )
        {
        }

        uint64_t get_calls() const
        {
            return get_calls_;
        }

        sgns::blockstore::result<sgns::blockstore::S3PutResult, sgns::blockstore::BlockStatus> Put(
            const std::string &key, const std::vector<uint8_t> &bytes,
            const sgns::blockstore::PutObjectOptions &options = {} ) override
        {
            return inner_->Put( key, bytes, options );
        }

        sgns::blockstore::result<sgns::blockstore::S3Object, sgns::blockstore::BlockStatus> Get(
            const std::string &key ) override
        {
            ++get_calls_;
            return inner_->Get( key );
        }
        // Head/Delete forward identically ...
    private:
        std::shared_ptr<InMemoryS3Client> inner_;
        std::atomic<uint64_t>             get_calls_{ 0 };
    };
```
**Why decorator-first (Pitfall 7):** `InMemoryS3Client` holds `mutex_` around op dispatch — sleeping INSIDE the fake serializes counting probes too; the decorator adds latency/hooks without touching the fake's lock. `PrefixSpyHotStore` (`cold_storage_gc_test.cpp:440+`) is the same decorator discipline for the hot store (D-12 keyspace audit walk).

---

### `SuperGenius/.github/workflows/cmake.yml` (MODIFY — permanent ON leg D-02a + fake-source overlay)

**Analog:** the existing matrix include legs + download + Tier-1 steps in the same file.

**Matrix-include pattern** (`cmake.yml:178-196` — the ON leg is a new include carrying `-DSGNS_COLD_STORAGE=ON` in `cmake_args`; the option parses at `SuperGenius/build/CommonBuildParameters.cmake:415-446`):
```yaml
        include:
          - target: iOS
            id: iOS
            runner_key: mac
            cmake_args: -DPLATFORM=OS64
          # ...
          - target: Linux
            id: Linux-x86_64
            abi: x86_64
            build-type: Release
            runner_key: linux_x64
            container: ghcr.io/geniusventures/almalinux-8:latest
            cmake_args: -DSGNS_PRINT_LOGS=ON
```

**Configure step consumes `matrix.cmake_args` verbatim** (`cmake.yml:518-523`):
```yaml
        run: cmake -S build/${{ matrix.target }} -B ${{ env.BUILD_DIRECTORY }} -DCMAKE_BUILD_TYPE=${{ matrix.build-type }} ${{ env.COMPILER_PIN }} -DTHIRDPARTY_BUILD_DIR=${{ env.THIRDPARTY_BUILD_DIR }} -DZKLLVM_BUILD_DIR=${{ env.ZKLLVM_BUILD_DIR }} ${{ matrix.cmake_args }}
```

**Thirdparty tarball arrival — where the sparse overlay step appends** (`cmake.yml:315-331`):
```yaml
      - name: Download thirdparty release
        working-directory: ${{ github.workspace }}
        shell: bash
        run: |
          mkdir thirdparty && cd thirdparty
          if [ "$IS_TAG" = true ]; then
            tag="$RESOLVED_BRANCH"
          else
            tag="${{ matrix.id }}-$RESOLVED_BRANCH-${{ matrix.build-type }}"
          fi
          gh release download "$tag" --repo GeniusVentures/thirdparty -p "$FILE_NAME"
          tar -zxf "$FILE_NAME"
          # CMake on Windows needs a native path, not the MSYS one.
          echo "THIRDPARTY_BUILD_DIR=$([ "${{ matrix.target }}" = Windows ] && pwd -W || pwd)/$BUILD_DIRECTORY" >> $GITHUB_ENV
```
The overlay step (§5.3 option A) slots directly after `tar -zxf`: checkout `GeniusVentures/thirdparty` at the matching tag/SHA sparse-limited to `sgns-blockstore/src`, overlay into `thirdparty/sgns-blockstore/` (disjoint subpaths — install tree carries only `include/`,`lib/` per `thirdparty/sgns-blockstore/CMakeLists.txt:65-99`). Option B instead adds a cache var in `SuperGenius/test/src/crdt/CMakeLists.txt` (next assignment). Pitfall 10: reuse existing steps verbatim; no new GITHUB_ENV writes outside the Windows `pwd -W` branch pattern.

**Test gating the ON leg inherits** (`cmake.yml:157`): `RUN_TESTS: ${{ matrix.target == 'Linux' || matrix.target == 'OSX' || (matrix.target == 'Windows' && matrix.build-type == 'Release') }}`. **Tier-1 fail-closed lane** (`cmake.yml:610-617`):
```yaml
      - name: Tier-1 fail-closed lane
        if: ${{ !cancelled() && env.RUN_TESTS == 'true' && matrix.target != 'Linux' }}
        working-directory: ${{ github.workspace }}/SuperGenius/${{ env.BUILD_DIRECTORY }}
        # TEST-01 (v1.1 Phase 7): -L Tier1 never includes unlabeled tests
        # and --no-tests=error fails an empty selection ...
        run: ctest . -j ${{ env.CTEST_JOBS }} -C ${{ matrix.build-type }} --output-on-failure -L Tier1 --no-tests=error
```
(The Linux variant of the same lane is at `:695-701`.)

---

### `SuperGenius/.github/workflows/build-release-tags.yml` (MODIFY — ON configure + run-tests posture D-02b)

**Analog:** the same file's existing inputs, gating, and download machinery.

**Dispatch inputs already present** (`build-release-tags.yml:9-14`, `:75-77`):
```yaml
      thirdparty_tag:
        description: 'Tag for thirdparty dependencies (defaults to main tag if not specified); "main" or "develop" pulls the rolling branch releases from the Release Build CI'
        required: false
        type: string
      # ...
      run_tests:
        description: "Run the CTest suite after building (same platform gating and exclusions as Release Build CI)"
        default: false
        type: boolean
```
D-02b = dispatch with `thirdparty_tag=<cut tag>`, `run_tests=true`, plus the added ON configure arg. Gating mirrors develop CI (`:187-192`):
```yaml
      RUN_TESTS: ${{ inputs.run_tests && (matrix.target == 'Linux' || matrix.target == 'OSX' || (matrix.target == 'Windows' && matrix.build-type == 'Release')) }}
```

**Skip gates to leave untouched** (`:253-259`): `if: ${{ github.event_name == 'workflow_dispatch' && !inputs[format('build_{0}{1}_{2}', matrix.target, matrix.abi && format('-{0}', matrix.abi) || '', matrix.build-type)] }}` → `exit 78`.

**Tag resolution + `THIRDPARTY_BUILD_DIR` discipline** (`:401-451`): `THIRDPARTY_TAG` from `github.event.inputs.thirdparty_tag || github.event.inputs.tag`; `"main"/"develop"` → `${TARGET_ID}-${THIRDPARTY_TAG}-${build-type}` else the tag verbatim; `gh release download ... && tar -zxf`; Windows branch writes `THIRDPARTY_BUILD_DIR=$(pwd -W)/${BUILD_DIRECTORY}` (Pitfall 10 — any new step follows this exact branch pattern). The fake-source overlay step appends inside/after this step, pinned to the SAME tag.

---

### `SuperGenius/test/tier1_audit_check.cmake` (NEW — SC4 tier-label audit port)

**Analog:** `thirdparty/sgns-blockstore/test/tier1_audit_check.cmake` — port the structure, rescope the pattern tables to SuperGenius's Phase-12 concerns.

**Script-mode shape** (`tier1_audit_check.cmake:1-14` — header documents the contract and the registration):
```cmake
# tier1_audit_check.cmake - CMake script-mode (-P) static audit gating the
# Tier-1 hermetic contract (D-14, Phase 5). Fails with file:line when any
# test source contains a fixed-sleep construct outside the allowlist ...
# and when test/CMakeLists.txt registers more tests than it labels with
# PROPERTIES LABELS (a new unlabeled test trips the audit before CI can
# run it ...).
#
# Registered from test/CMakeLists.txt as:
#   add_test(NAME tier1_static_audit
#            COMMAND ${CMAKE_COMMAND} -DSRC_DIR=${CMAKE_SOURCE_DIR} -P
#                    ${CMAKE_CURRENT_SOURCE_DIR}/tier1_audit_check.cmake)
```
Key mechanics to port: `file(GLOB_RECURSE ...)` over test sources; `file(STRINGS)` line scan; pattern tables (`:35-43` sleep patterns `std::this_thread::sleep_for`, `sleep_for`, `sleep[(]`, `usleep[(]`, `nanosleep[(]`, `Sleep[(]`); registration-vs-label count guard (`:118+`): count `addtest(`/`add_test(` vs `set_tests_properties(... LABELS` and `FATAL_ERROR` on mismatch. **SuperGenius rescope (SC4):** count `addtest(` vs `set_tests_properties(... LABELS "Tier1")` under `SuperGenius/test/src/crdt/CMakeLists.txt`, and assert every suite linking `sgns-blockstore::sgns-blockstore` sits inside `if(SGNS_COLD_STORAGE)` (the config-gate exemption rule). Register the audit itself as a Tier-1 ctest from `SuperGenius/test/CMakeLists.txt` (root: `include_directories(...)` + `add_subdirectory(src)` at `:1-7`) — belt-and-suspenders, the library precedent.

---

### `SuperGenius/test/src/crdt/CMakeLists.txt` (MODIFY — registration + include-dir override)

**Analog:** the existing cold-storage blocks in the same file — the gated-registration discipline every new suite copies.

**Gated block pattern** (`CMakeLists.txt:168-194`, the `cold_storage_gc_test` block):
```cmake
# Retention-GC observe-only tests (GC-01 SC1/SC5, v1.1 Phase 11 plan
# 11-01). Registered ONLY under SGNS_COLD_STORAGE: links
# sgns-blockstore::sgns-blockstore plus the InMemoryS3Client and
# InMemoryS3AdminClient fakes via the relative include dir (both fake
# headers are deliberately not installed). The Tier-1 lane stays
# non-empty on OFF builds via the unconditional config-gate test.
if(SGNS_COLD_STORAGE)
addtest(cold_storage_gc_test
    cold_storage_gc_test.cpp
)

target_link_libraries(cold_storage_gc_test
    sgns-blockstore::sgns-blockstore
    crdt_globaldb
    crdt_datastore
    rocksdb
)

target_include_directories(cold_storage_gc_test PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../../../../thirdparty/sgns-blockstore/src"
)

set_tests_properties(cold_storage_gc_test PROPERTIES LABELS "Tier1")
endif()
```
The relative include dir IS the §5.3 landmine (tarball has no `src/`). Option B (recommended with A's checkout): hoist the path into a cache var —
```cmake
set(SGNS_BLOCKSTORE_TEST_SRC_DIR "${CMAKE_CURRENT_LIST_DIR}/../../../../thirdparty/sgns-blockstore/src"
    CACHE PATH "sgns-blockstore test-fake source dir (ON CI lane points at the sparse overlay)")
```
— and use it in every block. **Unconditional exemption precedent** (`:62-80`): `cold_storage_config_gate_test` registers OUTSIDE the gate (links only `crdt_globaldb`) so `ctest -L Tier1 --no-tests=error` never passes vacuously on OFF builds. The wall-clock soak binary registers with a NON-Tier1 label (Tier2/Tier3) or a standalone env-gated target — never Tier1 (D-07).

---

### Fresh-clone checklist evidence doc (NEW — D-05)

**Analog:** `thirdparty/sgns-blockstore/docs/evidence/gc-e2e/README.md` — copy the shape (targets table, env-gate NAMES-only rule, run procedure, per-run captures), lighten per D-05 (SHAs, tags, platforms, pass counts, ON-option evidence, audit result; raw logs stay in CI run history). Location at planner discretion (workstream planning dir or SuperGenius docs). Include the D-04 fail-closed SHA validation step (`git ls-remote` per repo: SuperGenius + thirdparty) at the top of the run procedure. For the WALL-CLOCK soak's evidence (D-07), the committed-artifact trio standard applies — `docs/evidence/gc-e2e/{README.md,run-capture.md,stats-capture.txt}` is the format.

## Shared Patterns

### Test registration (apply to EVERY new suite)
**Source:** `SuperGenius/test/src/crdt/CMakeLists.txt:62-80, 168-194`
`if(SGNS_COLD_STORAGE)` → `addtest(name files...)` → `target_link_libraries` (always `sgns-blockstore::sgns-blockstore` + `crdt_globaldb`) → `target_include_directories(... sgns-blockstore/src)` → `set_tests_properties(name PROPERTIES LABELS "Tier1")` → `endif()`. Explanatory comment block above each registration (requirement ID + phase + why gated).

### Deadline polling — never fixed sleeps
**Source:** `SuperGenius/test/src/crdt/cold_storage_durability_test.cpp:84-97`; ban enforced by `thirdparty/sgns-blockstore/test/tier1_audit_check.cmake:35-43`
```cpp
    bool PollUntil( const std::function<bool()> &predicate,
                    std::chrono::milliseconds       deadline,
                    std::chrono::milliseconds       step = std::chrono::milliseconds( 10 ) )
    {
        const auto end = std::chrono::steady_clock::now() + deadline;
        while ( std::chrono::steady_clock::now() < end )
        {
            if ( predicate() ) { return true; }
            std::this_thread::sleep_for( step );
        }
        return predicate();
    }
```
Every cold-storage suite carries this helper at file top (same anonymous-namespace layout). Deterministic legs use barriers instead of polling; jitter legs use seeded latency (D-10). NOTE: the library audit bans `sleep_for` in ITS test tree — the SuperGenius port's pattern table must allowlist the `PollUntil` helper lines or scan only for unbounded forms, per the planner's discretion item.

### Test-seam contract (D-16)
**Source:** `ColdStorageManager.hpp:262-272` + `InMemoryS3AdminClient.hpp:88-93`
`std::function<void()>` member + dedicated swap mutex + null-in-production + invocation guarded at the named crossing + Doxygen carrying the exact phrase "PRODUCTION CODE MUST NEVER CALL ..." (or "CONFORMANCE-TEST SEAM: production code MUST NOT call this"). Never called by production code; inert when cold storage disabled.

### Test-local decorator (wrap-delegate-observe)
**Source:** `CountingS3Client` (`cold_storage_gc_test.cpp:338-381`), `PrefixSpyHotStore` (`:440+`), `SpyBufferBatch` (`:385-436`)
Final class implementing the interface, holding `std::shared_ptr<Inner>`, forwarding every op, tallying/firing hooks at the boundary. Atomic counters for cross-thread observation. The timing decorator extends this with per-op/per-key latency + `SetOnOp(op, fn)` mirroring `SetOnFlush`.

### Fault scripting kit
**Source:** `InMemoryS3Client.hpp:48-118`, `InMemoryS3AdminClient.hpp:60-97`
`SetFault(S3Op, S3FaultKind)` / `SetFaultForKey(key, op, kind)` (key-scoped precedence) / `SetFlipBytesForKey` / `ClearFaults()` / `ObjectKeys()`; admin: `SetStats`, `SetAdminFault(S3AdminFaultKind)`, `SetSlowFlushDelayMs`, `SetOnFlush`, `flush_count()`, `stats_count()`. Race legs = `SetFaultForKey` for "exactly one item fails"; soak outage = op-level `Unavailable` on Put + admin `Unreachable`/`FlushFails` for the flush-cadence leg (separate state).

### Bounded-shutdown assertion
**Source:** `cold_storage_durability_test.cpp:838-847`
`EXPECT_LT( stop_elapsed_ms, kShutdownGraceWindow + kFinalFlushBudgetMs + margin )` with a `[measurement]` stdout line — D-09's teardown legs reuse verbatim, extending the actor mix.

### GITHUB_ENV / Windows path discipline
**Source:** `cmake.yml:329-331`, `build-release-tags.yml:443-450`
`echo "THIRDPARTY_BUILD_DIR=$([ "${{ matrix.target }}" = Windows ] && pwd -W || pwd)/${BUILD_DIRECTORY}" >> $GITHUB_ENV` — every new CI step writes paths through this branch pattern (Pitfall 10).

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| (CI sparse-source overlay step content) | config (CI step) | batch | No in-repo workflow has ever sparse-checked-out a second repo into the workspace — nearest anchor is the "Download thirdparty release" step (`cmake.yml:315-331`, `build-release-tags.yml:401-451`) where it appends; overlay mechanics are new but mechanics-only (research A1: paths verified disjoint) |
| (kill-9 true process-kill mechanics) | test (runbook) | streaming | No SuperGenius test kills an external process mid-soak; the two-fresh-process shape exists in `thirdparty/sgns-blockstore/test/s3d_gc_e2e.cpp` (SpillRun/EvictRun) — runbook-driven, dev-gated, not CI |

All other files have exact in-repo analogs above.

## Metadata

**Analog search scope:** `SuperGenius/test/src/crdt/`, `SuperGenius/test/src/graphsync/`, `SuperGenius/test/CMakeLists.txt`, `SuperGenius/src/crdt/globaldb/`, `SuperGenius/.github/workflows/`, `thirdparty/sgns-blockstore/{src,include,test,docs/evidence}`, `thirdparty/sgns-blockstore/test-data` (absent → evidence lives in `docs/evidence/`)
**Files scanned:** 14 analog files read (all targeted, non-overlapping ranges)
**Tracked-source gate:** all cited analogs verified via `git ls-files` inside their submodules (SuperGenius; thirdparty/sgns-blockstore) — 2026-10-27
**Pattern extraction date:** 2026-10-27
