# Phase 8: Spill-on-Write & Background Drainer - Pattern Map

**Mapped:** 2026-10-23
**Files analyzed:** 14 (7 new + 7 modified; 1 of the modified is a conditional CI decision — Open Question 1)
**Analogs found:** 12 / 13 core files have a usable in-repo analog (2 of those are "new pattern, fully-specified interface" partials)

All analog paths below verified git-TRACKED this session (`git ls-files` non-empty in each owning repo: SuperGenius, thirdparty/ipfs-lite-cpp, thirdparty/sgns-blockstore — its own nested repo, tracked source not a mirror — GeniusWallet). Line numbers re-verified against the working tree on 2026-10-23 (post-Phase-7).

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `SuperGenius/src/crdt/globaldb/globaldb.hpp` (MOD) | config/model + lifecycle member declarations | CRUD (config struct) | itself — `ColdStorageOptions` :52-77, backup member block :434-441 | exact (in-place extension) |
| `SuperGenius/src/crdt/globaldb/globaldb.cpp` (MOD) | wiring: parser + seam construction + shutdown ordering | transform (JSON→options); request-response (factory seam) | itself — `ParseColdStorageConfig` :103-246, seam :502-524, `ShutdownNow` :293-327 | exact (in-place extension) |
| `SuperGenius/src/crdt/globaldb/BlockStoreBackedIpfsDatastore.hpp/.cpp` (NEW) | component (decorator on `IpfsDatastore`) | CRUD + file-I/O (local journal batch) | `thirdparty/ipfs-lite-cpp/.../impl/datastore_rocksdb.cpp` (the inner store it wraps) + `datastore.hpp` interface | role-match (no decorator exists yet in SuperGenius — see No Analog Found) |
| `SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp/.cpp` (NEW) | service (background drainer thread) | event-driven (cv poll loop) + batch (per-poll drain) | backup loop `globaldb.cpp:609-656` + member block `globaldb.hpp:434-441` | exact (role + data flow) |
| `SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp` (NEW, always compiled) | factory declaration / DTO (status struct) | request-response | `LocalBlockStore.hpp` pimpl discipline (zero RocksDB types in header) | role-match |
| `SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp` (NEW, gated ON) | factory impl (real stack assembly) | request-response | `S3BlockStore::Open` composition + `upload_drainer_test.cpp` SetUp assembly | role-match |
| `SuperGenius/src/crdt/globaldb/ColdStorageStackStub.cpp` (NEW, gated OFF) | stub (loud failure) | request-response | loud-failure posture of `ParseColdStorageConfig` (:148-171) | partial (no stub precedent — see No Analog Found) |
| `SuperGenius/src/crdt/globaldb/CMakeLists.txt` (MOD) | build config | — | `SuperGenius/test/src/crdt/CMakeLists.txt:44-59` (`if(SGNS_COLD_STORAGE)` conditional registration) | role-match |
| `SuperGenius/test/src/crdt/cold_storage_spill_test.cpp` (NEW) | test (hermetic Tier-1) | batch + event-driven assertions | `thirdparty/sgns-blockstore/test/upload_drainer_test.cpp` + `cold_storage_config_gate_test.cpp` + `cold_storage_link_proof_test.cpp` | exact (composite of three) |
| `SuperGenius/test/src/crdt/CMakeLists.txt` (MOD) | build config (test registration) | — | itself :44-73 (Phase-7 cold-storage block) | exact (in-place extension) |
| `GeniusWallet/assets/crdt_config.json` (MOD) | config asset (schema parity) | — | itself (Phase-7 blank-form posture: `"blockstore": {}`) | exact (in-place extension) |
| `SuperGenius/.github/workflows/cmake.yml` (MOD, conditional — Open Q1) | CI config | — | itself :188-209 (configure args) | exact (in-place, if planner flips the gate) |

**Not classified as files:** none. The `UploadDrainer`/`LocalBlockStore` library is consumed, not modified (frozen v1.0 + Phase-6 surface).

## Pattern Assignments

### `SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp/.cpp` (service, event-driven + batch)

**Analog:** backup loop in `globaldb.cpp:609-656` — the "twice-proven" thread lifecycle D-10 mandates copying. This is the strongest analog in the phase.

**Thread member declarations** — copy this member cluster shape from `globaldb.hpp:434-441` (declare the manager's thread/mutex/cv as Manager-owned members, not GlobalDB-owned — D-10 keeps them inside the manager):

```cpp
// SuperGenius/src/crdt/globaldb/globaldb.hpp:434-441 (analog — backup members)
        BackupOptions                                     backup_options_{};
        ColdStorageOptions                                cold_storage_options_{};
        std::string                                       backup_directory_;
        std::atomic_bool                                  stop_backup_thread_{ false };
        std::atomic_bool                                  shutdown_started_{ false };
        std::thread                                       backup_thread_;
        std::mutex                                        backup_wait_mutex_;
        std::condition_variable                           backup_wait_cv_;
```

**Start/lifecycle pattern** (`globaldb.cpp:609-647`) — copy: guard clause, `0 ⇒ default` knob normalization, stop-flag reset, thread spawn, cv `wait_for` with predicate, between-cycles stop check:

```cpp
// SuperGenius/src/crdt/globaldb/globaldb.cpp:609-647 (analog)
    void GlobalDB::StartBackupLoop()
    {
        if ( !backup_options_.enabled || backup_thread_.joinable() || !m_pubsub )
        {
            return;
        }

        if ( backup_options_.interval_minutes == 0 )
        {
            backup_options_.interval_minutes = 15;      // <-- D-07's "0/default ⇒ built-in" precedent
        }
        ...
        stop_backup_thread_.store( false );
        backup_thread_ = std::thread(
            [this]()
            {
                CreateBackupNow();                       // <-- D-12 precedent: FIRST cycle before first wait

                while ( !stop_backup_thread_.load() )
                {
                    std::unique_lock<std::mutex> lock( backup_wait_mutex_ );
                    const bool                   stop_requested = backup_wait_cv_.wait_for(
                        lock,
                        std::chrono::minutes( backup_options_.interval_minutes ),
                        [this]() { return stop_backup_thread_.load(); } );
                    lock.unlock();

                    if ( stop_requested )
                    {
                        break;
                    }
                    CreateBackupNow();
                }
            } );
    }
```

Deltas the drainer adds on top of this shape (per D-03/D-11, from 08-RESEARCH Pattern 3): the wait duration is the *current backoff delay* (not a fixed interval), the predicate also wakes on `drain_requested_` (ops-trigger enqueue, never inline), and the loop body updates status atomics. First-cycle-before-first-wait (`CreateBackupNow()` above) IS the D-12 crash-reconciliation precedent.

**Stop/join pattern** (`globaldb.cpp:649-656`) — copy, extended with D-11's bounded grace wait between notify and join:

```cpp
// SuperGenius/src/crdt/globaldb/globaldb.cpp:649-656 (analog)
    void GlobalDB::StopBackupLoop()
    {
        stop_backup_thread_.store( true );
        backup_wait_cv_.notify_all();
        if ( backup_thread_.joinable() )
        {
            backup_thread_.join();
        }
    }
```

**Start slot** (`globaldb.cpp:659-670`): `Start()` calls `StartBackupLoop()` last — the drainer start slots beside it:

```cpp
// SuperGenius/src/crdt/globaldb/globaldb.cpp:659-670 (analog)
    void GlobalDB::Start()
    {
        if ( started_ )
        {
            return;
        }
        StartCIDReceiving();
        StartCICSync();
        StartRebroadcastHeads();
        started_ = true;
        StartBackupLoop();          // <-- cold-storage drainer start slots here (D-10)
    }
```

**Includes/logging pattern** (`globaldb.cpp:1-33`): plain `std::thread`/`<chrono>` (already included at :31-32); logger via `sgns::base::createLogger( "GlobalDB" )` member (`globaldb.hpp:479`) — the manager creates its own named logger the same way (D-09 transitions/heartbeat ride it).

**Error handling:** `outcome::result` throughout; library results are `policy::terminate` — ALWAYS guard with `has_value()` before `.value()/.error()` (see Shared Patterns).

---

### `SuperGenius/src/crdt/globaldb/globaldb.cpp` parser extension (D-05/D-06 `blockstore.backpressure`)

**Analog:** `ParseColdStorageConfig` 2-arg overload, `globaldb.cpp:103-246` — extend THIS function in place; strictness and tri-state inherit unchanged.

**Single-member strict loop** (`globaldb.cpp:127-171`) — copy verbatim shape for the nested `backpressure` sub-object (IsUint members instead of string/bool):

```cpp
// SuperGenius/src/crdt/globaldb/globaldb.cpp:127-146 (analog — excerpt)
        for ( auto member = section.MemberBegin(); member != section.MemberEnd(); ++member )
        {
            const std::string key = member->name.GetString();
            const bool        is_string_key =
                ( key == "endpoint" || key == "bucket" || key == "access_key" || key == "secret_key" || key == "prefix" );
            const bool is_bool_key = ( key == "path_style" || key == "tls" );
            if ( !is_string_key && !is_bool_key )
            {
                return outcome::failure( "crdt_config.json: unknown key 'blockstore." + key + "'" );
            }
            if ( is_string_key && !member->value.IsString() )
            {
                return outcome::failure( "crdt_config.json: 'blockstore." + key + "' must be a string" );
            }
```

New-error message shape (research-locked): `"crdt_config.json: unknown key 'blockstore.backpressure.<k>'"` — same prefix discipline.

**Sub-object presence semantics** — absent `backpressure` ⇒ all defaults (D-07), mirroring the absent-section check at `globaldb.cpp:118-123`; present-but-not-object ⇒ loud, mirroring :125-129. New this phase: `warn_pending >= critical_pending` (both non-zero) ⇒ loud naming the pair (08-RESEARCH Pitfall 9c).

**Options struct extension** — `ColdStorageOptions` at `globaldb.hpp:52-77` gains the nested knobs; copy the Doxygen + default-member style exactly, and extend `LogSummary()` (`globaldb.cpp:90-96`, redaction-by-omission) with watermark/backpressure fields ONLY — never credentials.

---

### `SuperGenius/src/crdt/globaldb/globaldb.cpp` seam construction + shutdown ordering

**Analog:** the construction seam itself, `globaldb.cpp:502-524`:

```cpp
// SuperGenius/src/crdt/globaldb/globaldb.cpp:502-524 (analog — THE seam)
        auto ipfsDBResult = IpfsRocksDb::create( m_datastore->getDB() );
        if ( ipfsDBResult.has_error() )
        {
            m_logger->error( "Unable to create database for IPFS datastore" );
            return Error::IPFS_DB_NOT_CREATED;
        }

        auto ipfsDataStore = std::make_shared<RocksdbDatastore>( ipfsDBResult.value() );  // :509 — decorator wraps HERE
        ...
        auto dagSyncer = std::make_shared<GraphsyncDAGSyncer>( ipfsDataStore, graphsync, host );  // :524 — hand DECORATOR to syncer
```

Gated wiring: when `cold_storage_options_.enabled`, the factory-produced decorator replaces `ipfsDataStore` in the `GraphsyncDAGSyncer` constructor call; inner store stays byte-identical otherwise (blank-config byte-identical bar, Phase-7 SC2).

**Shutdown ordering analog** — `ShutdownNow` `globaldb.cpp:293-327`; drainer stop slots immediately after `StopBackupLoop()` (:304) and BEFORE the `lifecycle_mutex_` teardown block (:306-313):

```cpp
// SuperGenius/src/crdt/globaldb/globaldb.cpp:293-327 (analog — excerpt)
    void GlobalDB::ShutdownNow()
    {
        bool expected = false;
        if ( !shutdown_started_.compare_exchange_strong( expected, true ) )
        {
            return;
        }
        m_logger->info( "GlobalDB shutdown start" );
        StopBackupLoop();                      // :303 — drainer Stop() slots IMMEDIATELY AFTER this (D-10/D-11)
        std::shared_ptr<PubSubBroadcasterExt> broadcaster;
        std::shared_ptr<CrdtDatastore>        crdt_datastore;
        {
            std::lock_guard<std::mutex> lock( lifecycle_mutex_ );   // :307 — teardown happens only after joins
            broadcaster    = std::move( m_broadcaster );
            crdt_datastore = std::move( m_crdtDatastore );
            m_datastore.reset();
        }
```

**Status getter (D-08) analog** — active-accessor pattern, `globaldb.cpp:329-339`:

```cpp
// SuperGenius/src/crdt/globaldb/globaldb.cpp:329-339 (analog)
    std::shared_ptr<GlobalDB::RocksDB> GlobalDB::ActiveDataStore() const
    {
        std::lock_guard<std::mutex> lock( lifecycle_mutex_ );
        if ( shutdown_started_.load() )
        {
            return nullptr;
        }
        return m_datastore;
    }
```

`GetColdStorageStatus()` copies this: `lifecycle_mutex_` + `shutdown_started_` check, then reads the manager's atomics — no journal scan under the lock.

**Cold-store directory derivation analog** — `ResolveBackupDirectory` `globaldb.cpp:554-557`:

```cpp
// SuperGenius/src/crdt/globaldb/globaldb.cpp:554-557 (analog)
    std::string GlobalDB::ResolveBackupDirectory( const std::string &databasePathAbsolute ) const
    {
        return ( std::filesystem::path( databasePathAbsolute ) / "backups" ).string();
    }
```

Sibling derivation (`<db>/coldstore`) copies this one-liner; NEVER inside `<db>/backups` (RocksDB BackupEngine dir; M3 D-09).

---

### `SuperGenius/src/crdt/globaldb/BlockStoreBackedIpfsDatastore.hpp/.cpp` (component/decorator)

**Analog (interface to implement):** `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/datastore.hpp:24-80` — six pure virtuals; the decorator implements all, forwarding five and journaling in `set`:

```cpp
// thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/datastore.hpp:24-62 (interface excerpt)
    class IpfsDatastore
    {
    public:
        using Value = common::Buffer;
        virtual ~IpfsDatastore() = default;
        virtual IPFS::outcome::result<bool> contains( const CID &key ) const = 0;
        virtual IPFS::outcome::result<void> set( const CID &key, Value value ) = 0;
        virtual IPFS::outcome::result<void> seal( const CID &key ) = 0;
        virtual IPFS::outcome::result<bool> is_sealed( const CID &key ) const = 0;
        virtual IPFS::outcome::result<Value> get( const CID &key ) const = 0;
        virtual IPFS::outcome::result<void> remove( const CID &key ) = 0;
```

**Analog (inner-store semantics to preserve):** `datastore_rocksdb.cpp:44-52` — the inner `set` has NO CID-verify (`// TODO(turuslan): FIL-117`); the journal-first `LocalBlockStore::Put` becomes the integrity gate:

```cpp
// thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/impl/datastore_rocksdb.cpp:44-52 (analog — inner set)
    IPFS::outcome::result<void> RocksdbDatastore::set( const CID &key, Value value )
    {
        // TODO(turuslan): FIL-117 maybe check value hash matches cid
        BOOST_OUTCOME_TRY( auto encoded_key, encode( key ) );
        return rocksdb_->put( encoded_key, common::Buffer( std::move( value ) ) );
    }
```

`remove`/`seal`/`is_sealed` forward hot-only (seal keys are TEXT `cid.toString()+"sealed"`, `datastore_rocksdb.cpp:54-70` — coexist in the same CF; decorator must not touch them).

**Error mapping:** journal failure ⇒ `outcome::failure( IpfsDatastoreError::UNKNOWN )` (the enum carries only `NOT_FOUND=1`/`UNKNOWN=1000`, `ipfs_datastore_error.hpp:17-24`); wrap the journal Put in `try/catch (const std::invalid_argument&)` (out-of-set-hash programmer-error throw, `BlockStore.hpp:50-60`) so a hostile CID can never terminate the node. `set()` must hold the shared `cold_store_mutex_` (single-threaded-use library contract) — full skeleton in 08-RESEARCH "Code Examples / journal spill".

---

### `SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp` / `.cpp` / `ColdStorageStackStub.cpp` (factory + gated impl)

**Analog (header hygiene):** `LocalBlockStore.hpp` pimpl discipline — `ColdStorageStack.hpp` (always compiled, included by default OFF builds) must contain ZERO sgns-blockstore types, exactly as the library keeps RocksDB out of its header:

```cpp
// thirdparty/sgns-blockstore/include/sgns-blockstore/LocalBlockStore.hpp:96-100 (analog — header-hygiene rationale)
     * Pimpl (Phase-2 Pattern 1): zero RocksDB types in this header - all
     * rocksdb::* usage lives in LocalBlockStore.cpp, so a consumer's
     * compile can never be broken by RocksDB version differences
```

**Analog (stack assembly):** the composition order proven in `thirdparty/sgns-blockstore/test/upload_drainer_test.cpp:93-103` (SetUp) — `LocalBlockStore::Open(LocalBlockStoreOptions{dir})` → `S3Client` (production: `OpenMinioS3Client` from `S3Client.hpp`; construction is eagerly validating with zero network I/O — proven in `cold_storage_link_proof_test.cpp:44-50`) → `S3BlockStore::Open(client, options)`:

```cpp
// thirdparty/sgns-blockstore/test/upload_drainer_test.cpp:93-103 (analog — assembly order)
        void SetUp() override
        {
            auto opened_local =
                LocalBlockStore::Open(LocalBlockStoreOptions{ FreshDir() });
            ASSERT_TRUE(opened_local);
            local_ = std::move(opened_local.value());
            fake_ = std::make_shared<InMemoryS3Client>();
            auto opened_remote = S3BlockStore::Open(fake_);
            ASSERT_TRUE(opened_remote);
            remote_ = std::move(opened_remote.value());
        }
```

`S3BlockStore::Open(std::shared_ptr<S3Client>, S3BlockStoreOptions{keyPrefix="v1/blocks"})` — throws `std::invalid_argument` on null client / empty prefix (`S3BlockStore.hpp:96-108`); shared_ptr injection keeps a handle for tests.

**Analog (stub's loud failure):** the loud-failure posture of the parser (`globaldb.cpp:148-171` — every detectable malformation names the offender in the message). The stub returns "not constructed" for disabled config and a loud `outcome::failure("binary built without SGNS_COLD_STORAGE ...")` when config requests cold storage on an OFF build (P10 silent-disable trap). No stub/factory-split precedent exists in SuperGenius — see No Analog Found.

**CMake gating analog:** `SuperGenius/test/src/crdt/CMakeLists.txt:44-59` — conditional source registration under `if(SGNS_COLD_STORAGE)`; the real `ColdStorageStack.cpp` enters `add_library(crdt_globaldb ...)` sources under the same gate with `target_link_libraries(crdt_globaldb PRIVATE sgns-blockstore::sgns-blockstore)`; the gate option itself lives in `SuperGenius/build/CommonBuildParameters.cmake:415-446` (already shipped by Phase 7 — do not duplicate). NOTE: `src/crdt/globaldb/CMakeLists.txt:10` sets `UNITY_BUILD ON` — the new TUs' include hygiene must not collide (research suggests `UNITY_BUILD OFF` for the gated TUs if needed).

---

### `SuperGenius/test/src/crdt/cold_storage_spill_test.cpp` (test, hermetic Tier-1)

Three-part analog composite:

**1. Fixture/assembly analog — `thirdparty/sgns-blockstore/test/upload_drainer_test.cpp`** (drain, crash-resume, backpressure cases): copy the `FreshDir()`/`NextUniqueDir()` short-path discipline (:74-89 — Windows MAX_PATH), `MakeCid` via `CidOf` + `MulticodecType::Code::RAW` (:63-67), the `@given/@when/@then` comment style (:113-118), and assertions on the journal triple (`GetUploadState`/`GetPendingUploads`/byte identity :138-146). Header include discipline (:39-43): installed `<sgns-blockstore/...>` headers + the fake via relative src include `"InMemoryS3Client.hpp"` — in SuperGenius the fake needs the explicit include-dir workaround (08-RESEARCH Pitfall 6):

```cmake
target_include_directories(cold_storage_spill_test PRIVATE "${CMAKE_CURRENT_LIST_DIR}/../../../../thirdparty/sgns-blockstore/src")
```

**2. Hermetic discipline analog — `SuperGenius/test/src/crdt/cold_storage_config_gate_test.cpp:1-49`**: in-memory JSON fixtures, injected env lookup, zero file-I/O/zero network, outcome-message-content assertions (`EXPECT_NE(result.error().find("..."), std::string::npos)`), file-header comment documenting registration rationale. Parser-extension cases for `backpressure` (unknown key, wrong type, `warn>=critical`, `0`-default) extend this file's matrix style.

**3. Library-facing guard analog — `SuperGenius/test/src/crdt/cold_storage_link_proof_test.cpp:44-58`**: `has_value()` before `.value()` on every library result (policy::terminate landmine) and `static_cast<void>` inside `EXPECT_THROW` to honor `[[nodiscard]]`.

**Benchmark shape (SC1):** no latency hook exists in the fake (`InMemoryS3Client.hpp` — fault kinds only, verified :60-98); the latency-injecting wrapper implements the public `S3Client` interface (`S3Client.hpp:52+`, `result<...>` envelope, synchronous-blocking contract) around the fake, sleeping in `Put` — test-local ~30-line class per 08-RESEARCH Pitfall 8. Compare drainer-paused vs drainer-running, never ON-vs-OFF.

**Registration analog — `SuperGenius/test/src/crdt/CMakeLists.txt:44-73`** (copy verbatim structure): gated `addtest(cold_storage_spill_test ...)` + `target_link_libraries(... sgns-blockstore::sgns-blockstore)` + `set_tests_properties(... PROPERTIES LABELS "Tier1")` under `if(SGNS_COLD_STORAGE)` (it links the library — cannot be unconditional, unlike the config-gate test; the lane stays non-empty via the unconditional config-gate test at :65-73).

---

### `GeniusWallet/assets/crdt_config.json` (config asset)

**Analog:** itself — current content (verified :1-8) already carries the Phase-7 blank form `"blockstore": {}`; Phase 8 extends schema parity the same way (blank sub-object = all defaults, D-07 posture; wallet asset never activates anything):

```json
{
  "backup_enabled": true,
  "backup_interval_minutes": 15,
  "backup_keep_count": 12,
  "backup_auto_restore_on_repair_failure": true,
  "blockstore": {}
}
```

---

## Shared Patterns

### Thread lifecycle (backup-loop pattern)
**Source:** `globaldb.cpp:609-656` + `globaldb.hpp:434-441`
**Apply to:** `ColdStorageManager` (drainer thread), any ops-trigger enqueue surface.
Own `std::thread` + `std::condition_variable` + atomic stop flag; never `io_`, never the pubsub asio context; stop = flag → notify → (D-11: bounded grace wait) → join, BEFORE any store teardown under `lifecycle_mutex_`.

### Strict config parsing (Phase-7 tri-state posture)
**Source:** `globaldb.cpp:103-246`
**Apply to:** the `blockstore.backpressure` sub-object inside `ParseColdStorageConfig`.
Single-member loop; unknown key/wrong type ⇒ `outcome::failure("crdt_config.json: ... 'blockstore.backpressure.<k>' ...")`; absent sub-object ⇒ defaults; whole-file failures stay lenient.

### Active accessor under `lifecycle_mutex_`
**Source:** `globaldb.cpp:329-339` (also `ActiveCRDTDataStore` :341+)
**Apply to:** `GlobalDB::GetColdStorageStatus()` (D-08) — lock, `shutdown_started_` check, read manager atomics, return; never a journal scan under the lock.

### outcome::result + `has_value()` guards
**Source:** `globaldb.cpp:502-509` (production); `cold_storage_link_proof_test.cpp:44-50` (test)
**Apply to:** every sgns-blockstore call site. Library `result` alias is `policy::terminate` — unguarded `.value()/.error()` on a failure TERMINATES. Error category declaration precedent: `OUTCOME_CPP_DEFINE_CATEGORY_3` at `globaldb.cpp:36-56`.

### Credential redaction by omission
**Source:** `LogSummary()` `globaldb.cpp:90-96`
**Apply to:** every new log line (manager heartbeat, watermark transitions, journal-failure errors): endpoint/bucket/prefix/watermarks OK; accessKey/secretKey NEVER referenced (Phase-7 T-7-03 carries forward).

### Hot-path logging discipline
**Source:** existing logger usage in `globaldb.cpp` (level-gated, e.g. `~GlobalDB` debug line :289-292)
**Apply to:** decorator `set()` — no per-block info logs, no `cid.toString()` on the spill path (v1.1 research M6); D-09 rate-limited heartbeat lives in the MANAGER, not the write path.

### Tier-1 registration
**Source:** `SuperGenius/test/src/crdt/CMakeLists.txt:44-73`
**Apply to:** `cold_storage_spill_test`. `addtest()` + mandatory `set_tests_properties(... LABELS "Tier1")` (addtest has no LABELS support); gated under `if(SGNS_COLD_STORAGE)` because it links the library; lane runs `ctest -L Tier1 --no-tests=error` from inside `build/<Platform>/<Config>`; local tree needs reconfigure `-DSGNS_COLD_STORAGE=ON` (cache verified OFF this session).

### C++ style
**Source:** `Coding Standards.md` (workspace root) + `globaldb.hpp` Doxygen blocks
**Apply to:** all new files — Ullman braces, PascalCase types/methods, `m_`/trailing-underscore members, `@brief/@param/@return` on public interfaces, `[[nodiscard]]` where discarding is an error, `outcome::result` over exceptions for expected failures.

## No Analog Found

Files with no close match in the codebase (planner uses 08-RESEARCH.md patterns instead):

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `BlockStoreBackedIpfsDatastore.hpp/.cpp` | component (decorator) | CRUD + file-I/O | No `IpfsDatastore` decorator exists anywhere in `SuperGenius/src` (verified: zero `public IpfsDatastore` matches). The interface (`datastore.hpp:24-80`), the inner-store semantics (`datastore_rocksdb.cpp`), and the full journal-first skeleton (08-RESEARCH Pattern 2 + Code Examples) fully specify it. |
| `ColdStorageStack.cpp` / `ColdStorageStackStub.cpp` | factory impl / stub | request-response | No factory-vs-stub source-gating precedent in SuperGenius production code (Phase 7 deferred this discretion; architecture anti-pattern bans `#ifdef` in shared headers — hence conditional source inclusion). Gate mechanics analog: `CommonBuildParameters.cmake:415-446` + `test/src/crdt/CMakeLists.txt:44-59`; loud-failure posture analog: parser :148-171. |

## Metadata

**Analog search scope:** `SuperGenius/src/crdt/globaldb/`, `SuperGenius/test/src/crdt/`, `SuperGenius/build/`, `thirdparty/sgns-blockstore/{include,src,test}/`, `thirdparty/ipfs-lite-cpp/ipfs_lite/`, `GeniusWallet/assets/`
**Tracked-source gate:** all analogs verified `git ls-files` non-empty in their owning repos (SuperGenius; ipfs-lite-cpp; sgns-blockstore nested repo; GeniusWallet) — no mirror paths emitted
**Files read this session:** 14 analog files (targeted non-overlapping ranges; globaldb.cpp ~450 lines across 5 ranges, globaldb.hpp 2 ranges)
**Pattern extraction date:** 2026-10-23
**Line-number validity:** re-verified 2026-10-23 against post-Phase-7 tree; re-verify `globaldb.cpp` anchors only if a commit touches `Init`/`ShutdownNow`/backup loop before implementation
