# Phase 10: Flush-Gated Durability Advancement - Pattern Map

**Mapped:** 2026-10-26
**Files analyzed:** 21 (12 modified, 9 new)
**Analogs found:** 19 / 21 (2 first-use surfaces flagged — see "No Analog Found")

**Scope note:** the phase touches three git trees. Analog paths below are
submodule-relative and ALL verified `git ls-files`-tracked this session:
`thirdparty/sgns-blockstore` (branch `main`), `SuperGenius` (branch
`dev_blockstore`), `GeniusWallet` (wallet asset). No `.gsd` mirror paths.

---

## File Classification

### Library — thirdparty/sgns-blockstore (Wave 1)

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `include/sgns-blockstore/S3AdminClient.hpp` (NEW) | interface / facade | request-response | `include/sgns-blockstore/S3Client.hpp` | exact |
| `src/S3AdminClient.cpp` (NEW; cpp-httplib impl + `OpenS3dAdminClient`) | service client impl | request-response | `src/MinioS3Client.hpp` + `src/MinioS3Client.cpp` (Pimpl, one-function failure classification, factory) | role-match (transport is first-use — see No Analog) |
| `src/InMemoryS3AdminClient.hpp` (+ `.cpp` if stateful) (NEW) | test fake | request-response (scripted) | `src/InMemoryS3Client.hpp` | exact |
| `include/sgns-blockstore/LocalBlockStore.hpp` (MOD) | model / journal API | batch (scan + transactional write) | itself — concrete-only surface section :184-260 | exact |
| `src/LocalBlockStore.cpp` (MOD) | model / journal impl | batch | itself — `GetPendingUploads` :559-589 + `TransitionJournal` :660-697 | exact |
| `src/CMakeLists.txt` (MOD) | config (build) | — | itself — `add_library` + PRIVATE-link precedent :1-24 | exact |
| `test/api_hygiene_test.cpp` (MOD) | test (hygiene gate) | compile-time | itself — include-everything block :46-61 | exact |
| `test/s3_admin_client_test.cpp` (NEW) | test | request-response | `test/in_memory_s3_client_test.cpp` + `test/LoopbackHttpStub.hpp` | role-match |
| `test/CMakeLists.txt` (MOD) | config (test registration) | — | itself — `in_memory_s3_client_test` block :70-79 | exact |
| `docs/s3d-durability.md` (MOD) | docs | — | itself (§3 wording + admin-auth note; RESEARCH §1.4/§1.1 corrections) | n/a (doc edit) |

### SuperGenius — dev_blockstore (Waves 1-2)

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `src/crdt/globaldb/ColdStorageManager.hpp` (MOD) | service (background drainer) | event-driven (timer/quiescence loop) | itself — backoff/cadence/status sections | exact |
| `src/crdt/globaldb/ColdStorageManager.cpp` (MOD) | service impl | event-driven | itself — loop :47-83, `Stop` :85-101, `DrainOnce` :123-241, backoff :243-260 | exact |
| `src/crdt/globaldb/ColdStorageStack.hpp` (MOD) | model (status DTO) + bridges | read-only snapshot | itself — `ColdStorageStatus` :51-58, bridge :144 | exact |
| `src/crdt/globaldb/ColdStorageStack.cpp` (MOD) | factory + bridge impl | request-response (stack open) | itself — backpressure normalization :117-152, null-safe bridges :168-210 | exact |
| `src/crdt/globaldb/globaldb.hpp` (MOD) | model (config) | transform (config → struct) | itself — `BackpressureOptions` :85-99, `ColdStorageEnvLookup` :121-132 | exact |
| `src/crdt/globaldb/globaldb.cpp` (MOD) | config parser + env + accessors | transform | itself — backpressure sub-object :159-213, normalization/pair-rule :243-271, `DefaultColdStorageEnvLookup` :75-91, `GetColdStorageStatus` :796-806, `ShutdownNow` :394-412 | exact |
| `src/account/GeniusNode.cpp` (MOD) | config load integration | transform | itself — `LoadCrdtConfig` parse+log block :620-634 | exact |
| `GeniusWallet/assets/crdt_config.json` (MOD) | config asset | — | itself — blank `backpressure` form (schema parity) | exact |
| `test/src/crdt/cold_storage_durability_test.cpp` (NEW) | test (SC1-SC4 suite) | event-driven assertions | `test/src/crdt/cold_storage_spill_test.cpp` — fixture :368-424, `crash_restart_reconciles` :656, `shutdown_grace_joins` :798 | exact |
| `test/src/crdt/CMakeLists.txt` (MOD) | config (test registration) | — | itself — `cold_storage_fallback_test` block :104-122 | exact |
| `test/src/crdt/cold_storage_config_gate_test.cpp` (MOD) | test (config matrix) | transform | itself — `Backpressure*` block :256-365 | exact |

---

## Pattern Assignments

### `include/sgns-blockstore/S3AdminClient.hpp` (interface, request-response) — D-05

**Analog:** `include/sgns-blockstore/S3Client.hpp` — the exact seam shape the
facade sits beside. Copy: config struct (with never-logged credential fields +
`tlsVerify` default-true), scriptable fault enum, virtual class with
`result<T, BlockStatus>` returns, free `Open*` factory. Header banner carries
the design-constraint block; installed via the existing
`install(DIRECTORY include/ ... FILES_MATCHING "*.hpp")` glob (library
CMakeLists.txt:59-62) — no CMake install edit needed for the header.

**Config-struct pattern** (`S3Client.hpp:67-78`):
```cpp
struct S3ClientConfig
{
    std::string endpoint;         ///< host, e.g. "127.0.0.1"
    ...
    std::string accessKey;        ///< credential - never logged
    std::string secretKey;        ///< credential - never logged
    std::string bucket;           ///< target bucket (pre-provisioned)
};
```
→ `S3AdminClientConfig` (RESEARCH §6.1): `endpoint` (base URL,
`http://127.0.0.1:8001` default), `adminPassword` (credential — never
logged), `tlsVerify = true`, PLUS client-side read-timeout fields (RESEARCH
§1.4 — s3d has no server deadline).

**Fault-enum pattern** (`S3Client.hpp:129-137`):
```cpp
/// @brief Scriptable fault kinds (mirrors FaultController's enum).
enum class S3FaultKind
{
    None,         ///< normal operation
    Unavailable,  ///< op fails TemporarilyUnavailable (never NotFound)
    CorruptData,  ///< op fails Corrupt
    Unauthorized, ///< op fails Unauthorized
};
```
→ `S3AdminFaultKind { None, Unreachable, FlushFails, GarbageStats, SlowFlush }`
lives in the installed header only if the fake needs it from SuperGenius
tests — prefer mirroring the split used today: `S3FaultKind` IS installed
(beside the seam) while the fake itself stays in `src/`. Planner ruling;
either satisfies D-05.

**Virtual-class + factory pattern** (`S3Client.hpp:144-152`, `:211-213`):
```cpp
class S3Client
{
public:
    virtual ~S3Client() = default;
    virtual result<S3PutResult, BlockStatus> Put(
        const std::string& key, ...) = 0;
    ...
};

result<std::shared_ptr<S3Client>, BlockStatus> OpenMinioS3Client(
    const S3ClientConfig& config);
```
→ `class S3AdminClient { virtual result<void, BlockStatus> Flush() = 0;
virtual result<UploadStats, BlockStatus> GetUploadStats() = 0; };` +
`OpenS3dAdminClient(const S3AdminClientConfig&)`. Result alias + frozen
`BlockStatus` taxonomy reused unchanged — RESEARCH §1.5: every failure class
is `TemporarilyUnavailable`, NEVER `NotFound`.

---

### `src/S3AdminClient.cpp` (client impl, request-response) — D-05/D-06

**Analog:** `src/MinioS3Client.hpp` — Pimpl with ZERO SDK types in the header,
factory `Open`, and the one-function failure classifier discipline.

**Pimpl + factory pattern** (`MinioS3Client.hpp:36-58`):
```cpp
class MinioS3Client final : public S3Client
{
public:
    static result<std::unique_ptr<MinioS3Client>, BlockStatus> Open(
        const S3ClientConfig& config);
    ...
private:
    MinioS3Client();
    class Impl;
    std::unique_ptr<Impl> impl_;
};
```
→ same shape for the concrete admin client; ALL cpp-httplib + nlohmann tokens
live in the `.cpp` only. The header-banner contract to copy verbatim-in-spirit
(MinioS3Client.hpp:10-14): "every SDK failure string is classified in exactly
ONE function inside the .cpp... an unrecognized failure NEVER reads as
NotFound" — the admin mapper's default bucket is `TemporarilyUnavailable`.

**Transport precedent (build-level):** cpp-httplib is already a hard
dependency — `find_package(httplib CONFIG REQUIRED)` at library
`CMakeLists.txt:40-42` (linked today only through miniocpp). The admin client
is the library's FIRST direct httplib consumer (see No Analog Found); link
`httplib::httplib` and `nlohmann_json::nlohmann_json` PRIVATE beside
`miniocpp::miniocpp` in `src/CMakeLists.txt` (exact precedent, :11-24):
```cmake
target_link_libraries(sgns-blockstore
    PUBLIC p2p::p2p_cid
    PUBLIC RocksDB::rocksdb
    PRIVATE miniocpp::miniocpp      # minio-cpp stays PRIVATE: ...
    PRIVATE ipfs-lite-cpp::blake2   # ... exactly like blake2 (Phase 6)
    # ADD: PRIVATE httplib::httplib, PRIVATE nlohmann_json::nlohmann_json
)
```

**Basic-auth shape (from the committed evidence, not openapi guesswork):**
`Authorization: Basic base64(":" + adminPassword)` — EMPTY username, s3d
ignores it (spike runbook README.md:75 `curl.exe -u ":$PW"`; RESEARCH §1.1).
Set `Client::set_read_timeout` from the config (RESEARCH §1.4/Pitfall 4 —
the unconditional `Stop()` join is bounded ONLY by this).

---

### `src/InMemoryS3AdminClient.hpp` (test fake, scripted request-response) — D-05

**Analog:** `src/InMemoryS3Client.hpp` — the fake this one sits beside. Copy:
`final : public S3AdminClient`, `CONFORMANCE-TEST SEAM: production code MUST
NOT call this` doc tags on every scripting method, small `mutable std::mutex`
for the cheap no-data-race statement, scriptable state under it.

**Scripting-surface pattern** (`InMemoryS3Client.hpp:41-50`, `:115-130`):
```cpp
/**
 * @brief Script a fault for one op kind ...
 * @note CONFORMANCE-TEST SEAM: production code MUST NOT call this.
 */
void SetFault(S3Op op, S3FaultKind kind);
...
private:
    std::optional<BlockStatus> FaultGate(const std::string& key,
                                         S3Op op) const;
    mutable std::mutex mutex_;
    std::map<std::string, std::vector<uint8_t>> objects_;
```
→ `SetStats(UploadStats)`, `SetAdminFault(S3AdminFaultKind)`,
`flush_count()` / `stats_count()` cadence-probe accessors, optional
`std::function<void()>` flush hook (RESEARCH §6.2). Placement: `src/`,
deliberately NOT installed — SuperGenius tests reach it via the
relative-include-dir workaround (verified:
`SuperGenius/test/src/crdt/CMakeLists.txt:105-113`).

---

### `include/sgns-blockstore/LocalBlockStore.hpp` + `src/LocalBlockStore.cpp` (model, batch) — D-03/§3.1/§3.2

**Analog:** itself. The two new methods land in the "Concrete backend-only
surface" section (`LocalBlockStore.hpp:184-260`) — NOT on `BlockStoreTooling`
(two pure virtuals only; adding one breaks every implementer incl.
`MemoryBlockStore` — frozen v1.0 discipline, RESEARCH §3.1).

**Enumeration analog** — `src/LocalBlockStore.cpp:559-589`
(`GetPendingUploads`), the body `GetUploadsInState(UploadState)` generalizes
with a state filter:
```cpp
result<std::vector<Cid>, BlockStatus> LocalBlockStore::GetPendingUploads()
{
    // A plain CF iterator over the default BytewiseComparator is
    // snapshot-consistent and yields keys in byte-lexicographic order
    // over the encoded CID bytes - the frozen ordering contract ...
    std::vector<Cid> pending;
    std::unique_ptr<rocksdb::Iterator> it(
        impl_->db_->NewIterator(impl_->ro_, impl_->journal_));
    for (it->SeekToFirst(); it->Valid(); it->Next())
    {
        const auto record = JournalRecord::Decode(it->value());
        if (!record || *record != UploadState::PendingUpload)
        {
            continue;   // <-- becomes: != requested_state
        }
        ...
    }
    if (!it->status().ok())
    {
        return MapStatus(it->status(), "GetPendingUploads: journal scan failed");
    }
    return pending;
}
```
Keep: snapshot-at-call-start semantics (this IS the D-03 snapshot —
journal-derived, crash-re-derivable), undecodable-key skip, status check
after the loop. Doxygen on the new method mirrors the `GetPendingUploads`
doc at `BlockStoreTooling.hpp:70-90` + the ordering contract sentence.

**Batched-mark analog** — `src/LocalBlockStore.cpp:660-697`
(`TransitionJournal`), the WriteBatch body `MarkUploadedDurableMany` composes
over N keys:
```cpp
result<void, BlockStatus> LocalBlockStore::TransitionJournal(
    const Cid& cid, UploadState new_state)
{
    ValidateCidHash(cid);
    if (auto gate = FaultGate(fault_))
    {
        return gate.value();
    }
    ...
    // Read-journal-first (T-02-08): transitions move Put-born records
    // only - marking an unknown CID would fabricate upload state, so
    // the NotFound branch writes NOTHING.
    std::string record;
    const auto present = impl_->db_->Get(
        impl_->ro_, impl_->journal_, KeySlice(key.value()), &record);
    if (present.IsNotFound())
    {
        return BlockStatus{StatusClass::NotFound, BlockSource::Local, ...};
    }
    ...
    // ONE atomic journal update per transition (D-06).
    rocksdb::WriteBatch batch;
    batch.Put(impl_->journal_, KeySlice(key.value()),
              JournalRecord::Encode(new_state));
    const auto committed = impl_->db_->Write(impl_->wo_, &batch);
```
→ the batched variant: per-item read-gate loop (skip-and-continue on
no-record — per-item no-fabrication isolation, RESEARCH §3.2/A6), ONE
`WriteBatch` + ONE sync `Write` for the whole snapshot. NOTE the verified
hazard the caller must respect: `TransitionJournal` does NOT check source
state — the Accepted-only discipline is caller-side (the manager enumerates
`UploadedAccepted` and marks exactly that vector; RESEARCH Pitfall 3).

**Header-doc analogs to mirror** (`LocalBlockStore.hpp:202-233`):
`MarkUploadedAccepted`/`MarkUploadedDurable`/`GetUploadState` doc blocks
(no-fabrication rule, NotFound+Local on missing record, undecodable-reads-
as-PendingUpload conservatism).

---

### `src/crdt/globaldb/ColdStorageManager.{hpp,cpp}` (service, event-driven) — D-01/D-02/D-03/D-04/D-07/D-09/D-12/D-13

**Analog:** itself — Phase-8's twice-proven drainer. The flush step is a
sibling of `DrainOnce()` inside the loop; cadence/backoff state mirrors the
existing backoff state; the final flush lands in `Stop()`.

**Loop-insertion point** (`ColdStorageManager.cpp:47-83`, the `Start()`
lambda):
```cpp
while ( !stop_flag_.load() )
{
    MarkBusy();
    DrainOnce();
    MarkIdle();

    std::unique_lock<std::mutex> lock( wait_mutex_ );
    const bool                   woken = wait_cv_.wait_for(
        lock, current_delay_, [this] { return stop_flag_.load() || drain_requested_.load(); } );
    ...
}
```
→ insert `AdvanceDurabilityOnce( quiescent )` after `DrainOnce()` before
`MarkIdle()` (RESEARCH §2 recommended option — quiescence signal naturally
available; `DrainOnce` gains a return value/out-param). Also: the file-banner
"Phase-10 boundary" note (ColdStorageManager.cpp:13-14) and the in-body
comment at :213-215 get REPLACED by the advancement step they anticipated.

**Stop/join pattern for the D-04 final flush** (`ColdStorageManager.cpp:85-101`):
```cpp
void ColdStorageManager::Stop()
{
    stop_flag_.store( true );
    wait_cv_.notify_all();
    if ( thread_.joinable() )
    {
        // D-11: bounded grace for in-flight cycle work, then the
        // unconditional join - only after it returns may the owner
        // close/destroy the stores (Pitfall-5 ordering). ...
        std::unique_lock<std::mutex> lock( idle_mutex_ );
        idle_cv_.wait_for( lock, kShutdownGraceWindow, [this] { return idle_; } );
        lock.unlock();
        thread_.join();
    }
}
```
→ the ONE bounded final flush+observe+mark attempt goes AFTER `thread_.join()`
and BEFORE return (last point where stores provably live), guarded by a
`final_flush_done_` atomic (Stop is idempotent; also covers the destructor
path which already calls `Stop()` — ColdStorageManager.cpp:50-53). Snapshot
enumeration inside it takes `cold_store_mutex_` (the Phase-9 re-warm worker
stops LATER in `ShutdownNow` — RESEARCH §7 step 2).

**Backoff-discipline pattern to mirror for flush failures (D-07, SEPARATE
state — Pitfall 6)** (`ColdStorageManager.cpp:243-260`):
```cpp
void ColdStorageManager::RecordFailedCycle()
{
    ++failure_streak_;
    healthy_.store( false, std::memory_order_relaxed );
    const auto cap     = std::chrono::milliseconds( options_.backoff_cap_ms );
    const auto doubled = current_delay_ * kBackoffFactor;
    if ( current_delay_ < cap )
    {
        current_delay_ = doubled < cap ? doubled : cap;
    }
}
```
→ `RecordFlushFailedCycle()` / `BackoffResetFlush()` twins with their own
streak + delay + compile-time cap (`kBackoffFactor = 2` reuse,
ColdStorageManager.hpp:107-110 pattern for `constexpr` knobs — NOT config
knobs). Log wording must make flush failures distinguishable from drain
failures (D-07): prefix lines `"cold-storage flush ..."` vs the existing
`"cold-storage drainer ..."` / `"cold-storage pending uploads ..."` family.

**Split-phase lock discipline** (`ColdStorageManager.cpp:127-160` phase (i),
`:162-205` phase (ii) unlocked, `:207-221` phase (iii) re-locked) — the
advance step follows the identical shape: snapshot enumeration under
`cold_store_mutex_`, the admin HTTP calls UNLOCKED (new connection —
`remote_store_mutex_` NOT involved, RESEARCH §2), marks re-locked:
```cpp
// (iii) re-acquire the mutex: MarkUploadedAccepted ONLY for
// remote-present outcomes. UploadedDurable is NEVER written here
// (Phase-10 boundary).
{
    std::lock_guard<std::mutex> lock( *cold_store_mutex_ );
    for ( const auto &cid : succeeded )
    {
        auto marked = local_block_store_->MarkUploadedAccepted( cid );
```

**Status-atomics pattern (D-08 no-scan discipline)**
(`ColdStorageManager.hpp:170-176`):
```cpp
// Status atomics (D-08): read lock-free by GetStatus.
std::atomic<size_t>              pending_count_{ 0 };
std::atomic<ColdStorageWatermark> watermark_{ ColdStorageWatermark::None };
std::atomic<bool>                healthy_{ false };
```
→ add `accepted_count_`, `durable_count_`, last-flush evidence atomics
(valid/ok/unix_ms/observed counters), staging-health atomics
(pending_objects/buffer_used/buffer_limit/failed_uploads/healthy). All
maintained on the drainer tick + after advancement; `GetStatus()`
(ColdStorageManager.cpp:105-120) stays a pure atomic read. `GetUploadState`
pass-through (D-09) and `RefreshStagingStats()` (D-13) are new manager
methods: the former holds `cold_store_mutex_` (library single-threaded-use),
the latter serializes admin access behind a small dedicated `admin_mutex_`.

**Watermark/logging pattern for sustained-flush-failure alarms**
(`ColdStorageManager.cpp:262-323`, `UpdateWatermark`) — transition-logged
crossings + `kHeartbeatPeriod`-rate-limited held-state lines; D-07's
sustained-flush-failure alarm extends this family.

---

### `src/crdt/globaldb/ColdStorageStack.{hpp,cpp}` (model + bridges) — D-08/D-09/Pitfall 5

**Analog:** itself. `ColdStorageStack.hpp` is ALWAYS COMPILED and
"deliberately free of every sgns-blockstore type" (header banner :15-22) —
every new field is a PLAIN type; the library `UploadStats` struct must NOT
cross (Pitfall 5).

**DTO-extension pattern** (`ColdStorageStack.hpp:37-58`):
```cpp
enum class ColdStorageWatermark
{
    None,     ///< below the warn threshold
    Warn,     ///< at/above warn_pending, below critical_pending
    Critical, ///< at/above critical_pending
};

struct ColdStorageStatus
{
    size_t              pending_upload_count{ 0 };                    ///< pending-upload record count
    ColdStorageWatermark watermark{ ColdStorageWatermark::None };     ///< current watermark
    bool                drainer_healthy{ false };                     ///< false while a failure streak is held
};
```
→ append the defaulted additive fields per RESEARCH §4.2 (accepted/durable
counts, last-flush evidence block, staging counters + `staging_healthy`) +
a sibling ungated enum for D-09:
```cpp
enum class ColdUploadState { NoRecord, Pending, Accepted, Durable };
```
(mapping the library `UploadState` triple + no-record, exactly the
`ColdStorageWatermark` ungated-enum precedent).

**Null-safe bridge pattern** (`ColdStorageStack.cpp:183-193` and
`:144`-decl):
```cpp
ColdStorageStatus GetColdStorageManagerStatus( const std::shared_ptr<ColdStorageManager> &manager )
{
    return manager ? manager->GetStatus() : ColdStorageStatus{};
}
```
→ `GetColdUploadState(manager, cid)` same ternary shape.

**Stack-open pattern for admin-client wiring + normalization defense**
(`ColdStorageStack.cpp:73-105` construction sequence, `:117-152` defense):
```cpp
// Drainer options: normalize any still-0 knob to its built-in
// default (parsed configs arrive already normalized; programmatic
// configs defend here), then enforce the pair rule loudly.
GlobalDB::ColdStorageOptions::BackpressureOptions backpressure = options.backpressure;
if ( backpressure.drain_interval_ms == 0 )
{
    backpressure.drain_interval_ms = kDefaultDrainIntervalMs;
}
...
if ( backpressure.warn_pending >= backpressure.critical_pending )
{
    return outcome::failure( "cold storage: backpressure requires warn_pending < critical_pending " ... );
}
```
→ duplicate the durability normalization (`flush_min_interval_ms` /
`flush_max_interval_ms` 0-means-default + `min <= max` rule) in
`OpenColdStorageStack`, construct the admin client via `OpenS3dAdminClient`
right beside `OpenMinioS3Client` (:85-97), pass `DurabilityOptions` + client
into the manager ctor. The `try { ... } catch ( const std::invalid_argument &e )`
wrapper (:155-160) already converts library throws to outcome failures — keep
the new construction inside it.

---

### `src/crdt/globaldb/globaldb.{hpp,cpp}` (config model + parser + env) — D-06/D-11

**Analog:** itself — the exactly-proven nested-sub-object parse.

**Nested-options-struct pattern** (`globaldb.hpp:85-99`):
```cpp
struct BackpressureOptions
{
    uint32_t drain_interval_ms{ 0 };  ///< poll cadence floor; 0 = default 5000
    uint32_t warn_pending{ 0 };       ///< warn watermark ...; 0 = default 10000
    uint32_t critical_pending{ 0 };   ///< critical watermark; 0 = default 100000
    uint32_t backoff_cap_ms{ 0 };     ///< exponential-backoff cap; 0 = default 60000
};
BackpressureOptions backpressure;
```
→ `struct DurabilityOptions { uint32_t flush_min_interval_ms{0}; uint32_t
flush_max_interval_ms{0}; };` + `DurabilityOptions durability;` member +
`admin_endpoint` string member at the `ColdStorageOptions` level (non-secret
connection topology; RESEARCH §5.2). `LogSummary()` (globaldb.cpp:93-104)
extends with the two knobs + admin_endpoint — credential members NEVER
referenced.

**Env-lookup extension pattern** (`globaldb.cpp:75-91`):
```cpp
ColdStorageEnvLookup lookup;
const char *access_env = std::getenv( "SGNS_BLOCKSTORE_S3_ACCESS_KEY" );
const char *secret_env = std::getenv( "SGNS_BLOCKSTORE_S3_SECRET_KEY" );
if ( access_env != nullptr && *access_env != '\0' )
{
    lookup.access_key = access_env;
}
```
→ add `admin_password` member (`globaldb.hpp:121-126`) read from
`SGNS_BLOCKSTORE_S3_ADMIN_PASSWORD` in exactly this unset-or-empty-is-none
shape. Env value-only — never activates anything (Phase-7 D-08 posture).

**Nested-sub-object parse pattern** (`globaldb.cpp:159-213`, the `d1` block
inside the strict single-member loop):
```cpp
if ( key == "backpressure" )
{
    if ( !member->value.IsObject() )
    {
        return outcome::failure(
            std::string( "crdt_config.json: 'blockstore.backpressure' must be an object" ) );
    }
    for ( auto sub = member->value.MemberBegin(); sub != member->value.MemberEnd(); ++sub )
    {
        const std::string sub_key = sub->name.GetString();
        const bool is_uint_key = ( sub_key == "drain_interval_ms" || ... );
        if ( !is_uint_key )
        {
            return outcome::failure(
                "crdt_config.json: unknown key 'blockstore.backpressure." + sub_key + "'" );
        }
        if ( !sub->value.IsUint() )
        {
            return outcome::failure( "crdt_config.json: 'blockstore.backpressure." + sub_key
                                     + "' must be a uint" );
        }
        ...
    }
    continue; // handled - never falls into the string/bool checks
}
```
→ clone as the `key == "durability"` branch (uint-only knobs, loud
`blockstore.durability.<key>` naming) + `key == "admin_endpoint"` string
entry in the outer string-key set (`:200-204`). Post-normalization cross-field
rule mirrors `:243-271` (warn<critical → `flush_min_interval_ms <=
flush_max_interval_ms`, loud with both effective values). Phase-7 (e)
inheritance needs NO new code: optional-fields-only sections already land
disabled at `:274-307`.

**Accessor pattern** (`globaldb.cpp:796-806`, active-accessor under
`lifecycle_mutex_`):
```cpp
ColdStorageStatus GlobalDB::GetColdStorageStatus() const
{
    std::lock_guard<std::mutex> lock( lifecycle_mutex_ );
    if ( shutdown_started_.load() )
    {
        return ColdStorageStatus{};
    }
    return GetColdStorageManagerStatus( cold_manager_ );
}
```
→ `GetColdUploadState(cid)` accessor + bridge follow the identical shape.

**Shutdown-ordering anchor (D-04 site)** (`globaldb.cpp:394-412`):
`StopBackupLoop()` → `StopColdStorageManager()` (final flush rides INSIDE
the manager's `Stop()` — no new ordering slot, no new actor) →
`StopColdReadService()` → lifecycle-mutex teardown. Structural: no edit
expected beyond possibly a comment; cite in the SC3 test.

---

### `src/account/GeniusNode.cpp` (config load integration)

**Analog:** itself — `LoadCrdtConfig` :620-634:
```cpp
auto cold_storage_result = crdt::GlobalDB::ParseColdStorageConfig( config_text );
if ( cold_storage_result.has_error() )
{
    throw std::runtime_error( cold_storage_result.error() );
}
cold_storage_config_ = cold_storage_result.value();
if ( cold_storage_config_.enabled )
{
    node_logger_->info( "crdt_config.json: cold storage blockstore enabled: {}",
                        cold_storage_config_.LogSummary() );
}
```
The parse call itself needs NO change (durability rides inside
`ColdStorageOptions`). The missing-admin-password startup WARN (RESEARCH
§5.3, one-time, naming the env var) hooks here or at stack-open — planner
picks; either way the "one info line ONLY when enabled" discipline
(Pitfall 9 note at :627-630) is the template.

### `GeniusWallet/assets/crdt_config.json` (config asset)

**Analog:** itself — current content (verified):
```json
{
  "backup_enabled": true,
  ...
  "blockstore": {
    "backpressure": {}
  }
}
```
→ add `"durability": {}` inside `blockstore` (blank form, Phase-7 D-03
posture; blank = defaults = no activation change).

---

### `test/src/crdt/cold_storage_durability_test.cpp` (test, SC1-SC4)

**Analog:** `test/src/crdt/cold_storage_spill_test.cpp` — the Phase-8 manager
suite. Copy its fixture wiring verbatim, then script the admin fake.

**Fixture pattern** (`cold_storage_spill_test.cpp:368-424`):
```cpp
class ColdStorageSpillTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        auto opened_local = LocalBlockStore::Open( LocalBlockStoreOptions{ FreshDir() } );
        ASSERT_TRUE( opened_local.has_value() );
        local_  = std::move( opened_local.value() );
        fake_   = std::make_shared<InMemoryS3Client>();
        auto opened_remote = S3BlockStore::Open( fake_ );
        ASSERT_TRUE( opened_remote.has_value() );
        ...
    }

    std::shared_ptr<ColdStorageManager> MakeManager( const ColdStorageManager::BackpressureOptions &options )
    {
        auto remote_store_mutex = std::make_shared<std::mutex>();
        return std::make_shared<ColdStorageManager>(
            shared_local_, std::move( remote ), cold_store_mutex_, remote_store_mutex, options );
    }
```
→ the durability fixture adds `InMemoryS3AdminClient fake_admin_` and passes
it (plus fast `DurabilityOptions` — small intervals so cadence tests run in
ms, the `FastOptions(100)` precedent at :97-105) into the widened ctor.

**Scenario analogs:** `crash_restart_reconciles` :656-697 (reopen over the
same dir + fresh manager + fake — the SC3 crash-between-journal-and-drain
leg, extended with Accepted leftovers), `shutdown_grace_joins` :798-825
(Stop then fresh manager over the same directory — the D-04/SC3 shutdown
leg, scripted `SlowFlush`), `s3d_down_window_keeps_publishing` :718 (the
outage-never-NotFound leg riding the Phase-9 taxonomy),
`partial_success_cycle_advances_and_backs_off` :952 (evidence-gate negative:
`pendingObjects != 0` ⇒ no marks). SC2 per-CID transitions assert through
the D-09 getter + `kEvictionDurabilityGate` constant; SC1 cadence asserts on
`flush_count()` (floor respected, marks follow flush).

**Given/when/then doc blocks** — every test carries the `@given/@when/@then`
comment pair (spill test :418-424 et al.); keep the convention.

### `test/src/crdt/CMakeLists.txt` (registration)

**Analog:** itself — the `cold_storage_fallback_test` block (:104-122),
verbatim template:
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
The relative include dir is what reaches `InMemoryS3AdminClient.hpp` (and
`InMemoryS3Client.hpp`) — non-installed `src/` headers, test-surface-only
privilege (08-RESEARCH Pitfall 6 precedent, comment block at :85-90).

### `test/src/crdt/cold_storage_config_gate_test.cpp` (config matrix)

**Analog:** itself — the `Backpressure*` block :256-365. The `Durability*`
cases clone the fixture-compose trick (`kEnabledConfigBody` at :264-267 —
config body WITHOUT closers, cases append their sub-object + closers):
```cpp
constexpr const char *kEnabledConfigBody =
    R"({"blockstore": {"endpoint": "10.0.0.1", "bucket": "b1", "access_key": "a", "secret_key": "s")";

TEST( ColdStorageConfigGate, BackpressureUnknownKeyFails )
{
    auto result = Parse( std::string( kEnabledConfigBody ) + R"(, "backpressure": {"bogus": 1}}})", NoEnv() );
    ASSERT_TRUE( result.has_error() );
    EXPECT_NE( result.error().find( "unknown key 'blockstore.backpressure.bogus'" ), std::string::npos );
}
```
→ `DurabilityAbsentSubObjectGivesDefaults`, `DurabilityZeroKnobTakesOnlyItsDefault`,
`DurabilityUnknownKeyFails` (`'blockstore.durability.bogus'`),
`DurabilityMinAboveMaxFails` (the new pair rule), `DurabilityOnlySectionDisables`,
`AdminEndpointOptionalString` — the RESEARCH §Code-Examples list, all one
shape.

### Library test registration + hygiene (`test/CMakeLists.txt`, `test/api_hygiene_test.cpp`, `test/s3_admin_client_test.cpp`)

**Registration analog** (`test/CMakeLists.txt:70-79`):
```cmake
addtest(in_memory_s3_client_test in_memory_s3_client_test.cpp)
target_include_directories(in_memory_s3_client_test PRIVATE ${CMAKE_SOURCE_DIR}/src)
target_link_libraries(in_memory_s3_client_test
    sgns-blockstore
    p2p::p2p_cid
)
set_tests_properties(in_memory_s3_client_test PROPERTIES LABELS "Tier1")
```
→ `s3_admin_client_test` same block. Wire-tier fault shapes (truncated/garbage
bodies against the REAL httplib client, not the fake) reuse
`LoopbackHttpStub` (`test/LoopbackHttpStub.hpp` — raw-socket 127.0.0.1-only
scripted server, FIFO responses, request capture for header-on-the-wire
evidence; link `ws2_32` on WIN32 per the :52-60 precedent) — this is the A2
wire-verification lane.

**Hygiene-gate analog** (`test/api_hygiene_test.cpp:46-61` — the
include-everything block in dependency order):
```cpp
#include <sgns-blockstore/Cid.hpp>
#include <sgns-blockstore/BlockStatus.hpp>
...
#include <sgns-blockstore/S3Client.hpp>
...
#include <sgns-blockstore/UploadDrainer.hpp>
```
→ insert `#include <sgns-blockstore/S3AdminClient.hpp>` (compiling this TU
with exactly `sgns-blockstore + p2p::p2p_cid` IS the standalone-consumer +
no-SDK-leak proof for the new header — httplib/nlohmann must stay PRIVATE).
Complementary static gate: `test/header_hygiene_check.cmake` bans
non-installed includes from installed headers — the new header includes only
`BlockStatus.hpp`/`Cid.hpp`-class installed types. Post-add: wrapper-vcxproj
deployed-header staleness check (04-RESEARCH Pitfall 6).

---

## Shared Patterns

### 1. Ungated-boundary discipline (Pitfall 5)
**Source:** `SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp:15-22` (banner)
**Apply to:** every `ColdStorageStatus` extension, the D-09 bridge, `globaldb.hpp`.
No `#include <sgns-blockstore/...>` may appear in `ColdStorageStack.hpp` /
`globaldb.hpp` diffs; library types flatten to plain fields at the boundary
(`ColdStorageWatermark` :37-45 is the ungated-enum precedent).

### 2. Result-guard before `.value()`/`.error()`
**Source:** `ColdStorageStack.cpp:16-19` (banner) + every library call site in
`ColdStorageManager.cpp` / `ColdStorageStack.cpp`.
```cpp
auto opened_local = sgns::blockstore::LocalBlockStore::Open( ... );
if ( !opened_local.has_value() )
{
    return outcome::failure( ... opened_local.error().message ... );
}
```
The library result alias is `policy::terminate` (Cid.hpp:37-45 landmine) —
guard EVERY `Flush()` / `GetUploadStats()` / `GetUploadsInState` /
`MarkUploadedDurableMany` result.

### 3. Backoff discipline (D-07)
**Source:** `ColdStorageManager.cpp:243-260` (`RecordFailedCycle`/`BackoffReset`,
factor-2, cap, reset-on-success).
**Apply to:** flush-failure handling — as a SEPARATE streak/delay pair
(Pitfall 6: drain failures and flush failures never poison each other's
backoff), compile-time cap, log wording distinguishing the two families.

### 4. Strict tri-state config parse (D-11)
**Source:** `globaldb.cpp:111-316` — lenient-at-file-level, absent=disabled,
unknown/wrong-type loud naming `<section>.<key>`, 0-means-default
normalization, post-normalization cross-field rule, env-never-activates.
**Apply to:** the `durability` sub-object branch + `admin_endpoint` key;
matrix tests in `cold_storage_config_gate_test.cpp`.

### 5. Credentials never logged / never at rest
**Source:** `globaldb.hpp:63-66` + `globaldb.cpp:93-104` (`LogSummary`
redaction-by-omission) + `S3Client.hpp:74-75` ("credential - never logged").
**Apply to:** `admin_password` — env-only resolution, no log line, no error
string, no status field ever formats it; `S3AdminClientConfig` doc comments
carry the same tags.

### 6. Tier-1 registration discipline
**Source:** `SuperGenius/test/src/crdt/CMakeLists.txt:104-122` +
`thirdparty/sgns-blockstore/test/CMakeLists.txt` (every `addtest()` +
`set_tests_properties(... LABELS "Tier1")`).
**Apply to:** both new suites; the fail-closed lane is
`ctest -L Tier1 --no-tests=error` inside the `build/<Platform>/<Config>` tree
(`.planning/codebase/TESTING.md`).

### 7. CONFORMANCE-TEST SEAM discipline
**Source:** `src/InMemoryS3Client.hpp:41-50` (`@note CONFORMANCE-TEST SEAM:
production code MUST NOT call this`).
**Apply to:** every `InMemoryS3AdminClient` scripting method (`SetStats`,
`SetAdminFault`, counters, flush hook).

### 8. Never-NotFound failure taxonomy
**Source:** `S3Client.hpp:99-101` (Head success-slot doc) +
`MinioS3Client.hpp:10-14` (one-function classifier, default bucket).
**Apply to:** the admin facade — transport/timeout/non-200/non-JSON/missing-
field all map to `TemporarilyUnavailable` (retryable, D-07); NOTHING about
flush/stats is authoritative absence (RESEARCH §1.5).

---

## No Analog Found

| File | Role | Data Flow | Reason / Planner Guidance |
|------|------|-----------|---------------------------|
| `src/S3AdminClient.cpp` (cpp-httplib direct use) | service client impl | request-response | The library's only HTTP client today is minio-cpp (SigV4-S3-shaped); cpp-httplib is found+linked but has NO direct in-repo consumer (RESEARCH A2). Use the RESEARCH §6.1 sketch + `S3Client.hpp` seam discipline; wire-verify pre-merge with `test/LoopbackHttpStub.hpp` (raw-socket scripted server, :17-23 — genuine wire bytes, any fault shape). |
| nlohmann_json consumption in the library build | parse | transform | No existing nlohmann use in either submodule (SuperGenius config parsing is rapidjson — its STRICT-field discipline at `globaldb.cpp:159-213` is the closest parse-strictness analog). Research A3 flags configure-time risk; fallback is the httplib-style explicit `find_package` + PRIVATE link. Strict field-presence + integer-type checks; every parse failure → `TemporarilyUnavailable` (Pitfall 8: no `find("\"pendingObjects\"")` string-scraping). |

(`docs/s3d-durability.md` §3 wording fix + admin-auth note is a doc edit with
no code analog — source of truth is RESEARCH §1.1/§1.4, quoted verbatim from
the pinned-tag openapi.)

---

## Metadata

**Analog search scope:** `thirdparty/sgns-blockstore/{include,src,test,docs}`,
`SuperGenius/src/{crdt/globaldb,account}`, `SuperGenius/test/src/crdt`,
`GeniusWallet/assets`. Every named analog verified `git ls-files`-tracked in
its submodule this session (sgns-blockstore `main`, SuperGenius
`dev_blockstore`).
**Files scanned:** ~22 read in full or targeted ranges; grep-verified TEST
matrices and symbol line numbers.
**Key line anchors verified this session:** ColdStorageManager.cpp
47-83/85-101/105-120/123-241/243-260; ColdStorageStack.cpp 73-105/117-152/
168-210; globaldb.cpp 75-104/111-316/394-412/796-806; globaldb.hpp 85-99/
121-132; LocalBlockStore.cpp 559-589/648-697; LocalBlockStore.hpp 42-48/
184-260; S3Client.hpp 67-78/129-137/144-152/211-213; test registrations as
cited.
**Pattern extraction date:** 2026-10-26
