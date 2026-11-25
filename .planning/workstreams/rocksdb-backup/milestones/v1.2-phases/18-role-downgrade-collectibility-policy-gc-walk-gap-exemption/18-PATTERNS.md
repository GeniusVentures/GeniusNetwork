# Phase 18: Role Downgrade, Collectibility Policy & GC Walk-Gap Exemption - Pattern Map

**Mapped:** 2026-11-19
**Anchor line:** SuperGenius `84d87d462c529cbea93c2a67b907805cdd04a243` (`dev_coldstorage_additions`, == origin; re-verified via `git -C SuperGenius rev-parse HEAD` this session — matches 18-RESEARCH's anchor record, no drift)
**Files analyzed:** 13 (6 production modified/contingency, 3 new tests, 1 test-config modified, 3 planning docs)
**Analogs found:** 13 / 13 (every file has an exact or role-match analog; zero "no analog" entries)

**Tracked-source gate (#3645):** every analog path below verified via `git -C SuperGenius ls-files -- <path>` (all print) and `git ls-files` in the outer repo for the `notes/`/`STATE.md` planning paths. No gitignored mirrors named.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp` | service (GC pass walk) | batch (per-pass transform) | itself — gap site `:845-861`; consult-arm shape `graphsync_dagsyncer.cpp:866-880` | exact |
| `SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp` | model (counter/status fields) | batch | itself — `RetentionOptions :96-111`, status atomics `:603+` | exact |
| `SuperGenius/src/account/GeniusNode.cpp` | controller (node wiring / arm gate) | config-driven startup | itself — Light-check WARN-return `:5202-5210`; config reads `:481-536` | exact |
| `SuperGenius/src/transaction/PruneEligibility.hpp` | config + utility (ack-key parse, fingerprint key home) | request-response (parse) + CRUD (raw map) | itself — `PruningConfig :243-292`, prefix statics `:418-421`, builder docs `:510-610` | exact |
| `SuperGenius/src/transaction/PruneEligibility.cpp` | utility (FromJSON body + fingerprint read/compare/write helper) | CRUD (node-local raw map) | itself — `LookupPrunedEntry :180-236` | exact |
| `SuperGenius/src/crdt/globaldb/globaldb.cpp` / `.hpp` | persistence facade — **contingency, expected zero-diff** | CRUD | itself — `GetRaw :432`, `PutRaw :440` (already public; no widening needed) | exact (reference) |
| `SuperGenius/src/transaction/TxPruner.cpp` / `.hpp` | service — **expected zero-diff** (counter-naming analog only) | batch | itself — `PruneCycleStats :68-110` | role-match |
| `SuperGenius/test/src/crdt/cold_gc_walk_gap_exempt_test.cpp` (**NEW**) | test (red-first counter-test, Tier-1) | batch (direct-drive) | `cold_storage_gc_test.cpp` — fixture `:599-780`, `MakeManager :721-733`, `Backdate :750-755` | exact |
| `SuperGenius/test/src/crdt/cold_downgrade_e2e_test.cpp` (**NEW**) | test (t0→t3 timeline + interlock legs, Tier-1) | batch (in-process re-open) | `cold_evidence_matrix_test.cpp` — `TeardownStack :344-380`, `BuildStackOnDir :390-517` | exact |
| `SuperGenius/test/src/crdt/cold_downgrade_live_smoke_test.cpp` (**NEW**) | test (dev-gated live leg, Tier-3) | batch (live wire) | `cold_compose_live_smoke_test.cpp` — env-gate header `:1-46` | exact |
| `SuperGenius/test/src/crdt/CMakeLists.txt` | config (suite registration) | — | itself — Tier-1 block `:386-434`, Tier-3 block `:437-510` | exact |
| `.planning/workstreams/rocksdb-backup/notes/18-collectibility-policy-downgrade-interlock.md` (**NEW**) | documentation (rulings record) | — | `notes/16-txpruner-gc-composition-rulings.md` + `notes/17-seal-growth-decision.md` | exact |
| `.planning/workstreams/rocksdb-backup/STATE.md` | documentation (one-liner) | — | itself — SEAL-01 one-liner at `:56` | exact |

**Reference-only surfaces (consult vocabulary — NO modification, cite as-is):** `GraphsyncDAGSyncer::LookupPruneEvidence` (`src/crdt/impl/graphsync_dagsyncer.cpp:366-376`, public + ungated), `PruneEvidenceClass` (`src/crdt/cold_read_fallback.hpp:66-72`), `NodeType`/`ReplicatesAllAccounts` (`src/account/NodeType.hpp:31-37,48`), `SetColdStorageStackClientsForTesting` (`src/crdt/globaldb/ColdStorageStack.hpp:340+`), `SetPruneEvidenceLookupOnColdReadService` (`ColdStorageStack.hpp:320`).

---

## Pattern Assignments

### `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp` (service, per-pass batch)

**Analog:** itself at the gap site + `graphsync_dagsyncer.cpp`'s consult switch

**Core pattern — the gap site being modified** (`WalkReachable`, `:845-861` — inside `WalkReachable :798-863`, the walk already holds `gc_dag_syncer_`):

```cpp
auto node = gc_dag_syncer_->GetNodeWithoutRequest( current );
if ( !node.has_value() )
{
    // Walk gap: a head-reachable link is missing from EVERY
    // tier (hot, LRU, cold dir, remote). Reachability below it
    // is not computable - abort the pass toward under-eviction
    // rather than guessing (the only safe direction).
    auto current_str = current.toString();
    logger_->warn(
        "gc: pass-aborted-walk-gap - CID {} is head-reachable but missing from "
        "every tier; reachability not computable (under-eviction)",
        current_str.has_value() ? current_str.value()
                                : std::string( "<unencodable CID: " )
                                      + current_str.error().message() + ">" );
    return { {}, false };
}
```

**Consult-arm shape to copy verbatim-in-structure** (`FetchNodeFromColdStorage`'s consult, `src/crdt/impl/graphsync_dagsyncer.cpp:866-880` — the ONLY permissive arm is `Pruned`; `Malformed` fails closed; `NoEvidence` falls through to legacy):

```cpp
switch ( cold_read_hook_->LookupPruneEvidence( cid ) )
{
    case PruneEvidenceClass::Pruned:
        logger_->debug( "cold read: CID {} refused - node-local prune evidence outranks bytes",
                        cid.toString().value() );
        return outcome::failure( Error::HISTORY_PRUNED_LOCALLY );
    case PruneEvidenceClass::Malformed:
        logger_->error( "cold read: CID {} prune evidence is corrupt - failing closed",
                        cid.toString().value() );
        return outcome::failure( Error::PRUNE_EVIDENCE_CORRUPT );
    case PruneEvidenceClass::NoEvidence:
        break; // SC2: the existing v1.1 serve path, unchanged
}
```

The consult entry point (no new surface — D-02 satisfied by construction), `graphsync_dagsyncer.cpp:366-376`:

```cpp
std::optional<PruneEvidenceClass> GraphsyncDAGSyncer::LookupPruneEvidence( const CID &cid ) const
{
    if ( cold_read_hook_ == nullptr )
    {
        // The walk's surface-availability signal (D-05): nullopt = cold
        // disabled = preserve the legacy sealed+missing skip.
        return std::nullopt;
    }
    return cold_read_hook_->LookupPruneEvidence( cid );
}
```

**Counter pattern — per-pass plain member + end-of-pass atomic publish + INFO** (`GcPassOnce :869-987`; reset ~`:918-921`, publish + INFO `:936-945`):

```cpp
++gc_tick_counter_;
pass_reclaimed_count_  = 0;      // per-pass reset — the walk-exempted counter joins here
pass_reclaimed_bytes_  = 0;
...
gc_last_pass_candidates_.store( candidates.size(), std::memory_order_relaxed );
gc_last_pass_reclaimed_count_.store( pass_reclaimed_count_, std::memory_order_relaxed );
gc_last_pass_reclaimed_bytes_.store( pass_reclaimed_bytes_, std::memory_order_relaxed );
logger_->info( "gc: pass complete - {} candidate(s), {} evicted (retention {} ms, dry_run {})",
               candidates.size(), pass_reclaimed_count_, retention_.retention_age_ms, gc_dry_run_ );
```

D-04's walk-exempted counter follows this exact two-level shape (plain `pass_walk_exempted_` under `gc_pass_mutex_` single-writer; publish to a `gc_last_pass_exempted_` atomic; extend the `:942` INFO line). Note: the counter lives HERE in the GC pass stats — NOT in `TxPruner::PruneCycleStats` (see TxPruner entry).

**Ruling-comment pattern (both-homes discipline)** — the `[D-12, v1.2 Phase 16, COMP-03 — ...]` block at `:1298-1305` is the exact shape the exemption site's comment copies (cites `notes/18-*` by path):

```cpp
// [D-12, v1.2 Phase 16, COMP-03 — the starvation interplay
// home] This disposal deletes the cold journal record and
// writes the disposed marker as ONE library-atomic batch; ...
// The v2 DisposedDurable terminal state (REQUIREMENTS Future)
// is the recorded follow-up.
```

**Error handling:** fail toward under-eviction — every non-`Pruned` consult arm keeps today's `return { {}, false }` abort. The exempted CID is a LEAF: `continue` WITHOUT pushing its links (18-RESEARCH Pitfall 6).

---

### `SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp` (model)

**Analog:** itself — pinned-prefix constants + status atomics

**Key-home pattern** (`:124-127` — the fingerprint record joins this family if planner puts its KEY constant here; the RESEARCH default is a `PruneEligibility` `/prune/`-family home instead):

```cpp
static constexpr const char *kGcPinnedPrefix{ "/crdt/gc/" };
static constexpr const char *kGcEpochWatermarkKey{ "/crdt/gc/epoch-watermark" };
```

**Status-atomic pattern** (`:603+` — if the exempted count is surfaced beyond the INFO line):

```cpp
// Status atomics (D-08): read lock-free by GetStatus.
std::atomic<size_t>              pending_count_{ 0 };
std::atomic<ColdStorageWatermark> watermark_{ ColdStorageWatermark::None };
```

---

### `SuperGenius/src/account/GeniusNode.cpp` (controller, config-driven startup)

**Analog:** itself — the Light-check WARN-return IS the disarm shape (D-06)

**Core pattern — the interlock gate home** (`StartPruneTimerIfConfigured :5194-5290`; the gate inserts between the Light check and the `TxPruner::New` arm at `:5218-5228`):

```cpp
void GeniusNode::StartPruneTimerIfConfigured()
{
    // SC-5 default-off consent gate: an absent/disabled pruning config must
    // reach nothing below this line — no timer, no evaluator, no log cycle.
    if ( !pruning_config_.enabled )
    {
        return;
    }
    // GATE-01 role gate at the wiring (defense in depth — the evaluator
    // and the TxPruner service re-check at construction). Light nodes
    // only; full/archive never erase.
    if ( node_type_ != NodeType::Light )
    {
        node_logger_->warn( "Pruning enabled but node_type={} is not Light — pruning is light-only; "
                            "prune cycle not started",
                            node_type_ );
        return;
    }
    // ... TxPruner::New arm (:5218-5228) + timer wiring (:5230-5290)
```

The interlock copies this exact WARN+return posture: node starts normally (nothing above the gate changes), pruner disarmed, one loud WARN naming the ack key and the `notes/18-*` checklist path.

**Config-read pattern** (`LoadSgnsConfig`, pruning object `:518-536` — the ack key parses inside `PruningConfig::FromJSON`, this block only guards object-ness and delegates; node_type read `:481-493`; cold config `:630-710`):

```cpp
if ( config_json.HasMember( "pruning" ) && config_json["pruning"].IsObject() )
{
    pruning_config_ = PruningConfig::FromJSON( config_json["pruning"] );
    if ( pruning_config_.disabled_reason )
    {
        node_logger_->warn( "sgns_config.json: {}", *pruning_config_.disabled_reason );
    }
    node_logger_->info( "sgns_config.json: pruning enabled={}, finality_window={}, dry_run={}, "
                        "max_erases_per_cycle={}, settle_seconds={}", ... );
}
```

**Fingerprint wiring:** all three inputs (`node_type_`, `pruning_config_`, cold-enabled) are resolved members by the time the gate runs; the record read/compare/write goes through `tx_globaldb_`'s raw surface (`GetRaw`/`PutRaw`). Crash-between-read-and-write is safe (stale fingerprint ⇒ re-detected next boot).

---

### `SuperGenius/src/transaction/PruneEligibility.hpp` (config + utility)

**Analog:** itself — `PruningConfig` per-key parse discipline + prefix statics

**Ack-key parse home** (`PruningConfig :243-292` — the new key follows the same per-key type-checked, absent-keeps-default, fail-closed posture; note the `disabled_reason` carrier pattern):

```cpp
struct PruningConfig
{
    bool enabled = false;
    std::optional<uint64_t> finality_window;
    bool dry_run = false;
    uint64_t max_erases_per_cycle = 100;
    uint64_t settle_seconds = 60;
    /// Set when FromJSON had to fail-close an enabled request (missing
    /// finality_window); carries the operator-facing reason.
    std::optional<std::string> disabled_reason;
    ...
    static PruningConfig FromJSON( const rapidjson::Value &pruning_object );
};
```

**Key-statics pattern** (`:418-421` — the fingerprint's key constant joins this block or mirrors it; D-C1 one-key-home):

```cpp
/// Node-local marker key namespace (CRDTWorkJournal prefix discipline:
/// same shared RocksDB, direct datastore writes, never broadcast).
static constexpr std::string_view PRUNE_MARKER_PREFIX = "/prune/tx/";

/// Node-local BLOCK marker key namespace (v1.2 Phase 15, D-02): ...
static constexpr std::string_view PRUNE_BLOCK_MARKER_PREFIX = "/prune/blk/";
```

**TEST-ONLY writer contract** (`WritePrunedBlockEntryForTest :600+` — "No production caller may invoke this method"; the fingerprint's test helper, if any, copies this `@note` posture; evidence seeding in both new suites goes through THIS writer, never hand-built keys):

```cpp
/**
 * @brief       TEST-ONLY block-marker writer (the TEST-01 seam).
 * ...
 * @note        No production caller may invoke this method.
 */
static outcome::result<void> WritePrunedBlockEntryForTest( crdt::GlobalDB  &db,
                                                           const std::string &cid_string,
                                                           const std::string &tx_hash,
                                                           uint64_t          generation );
```

---

### `SuperGenius/src/transaction/PruneEligibility.cpp` (utility, CRUD on raw map)

**Analog:** itself — `LookupPrunedEntry :180-236` (the fingerprint read helper's GetRaw + error-arm shape)

```cpp
crdt::GlobalDB::Buffer marker_key;
marker_key.put( BuildPruneMarkerKey( tx_hash ) );
auto marker = db.GetRaw( marker_key );
if ( marker.has_error() )
{
    if ( marker.error() == storage::DatabaseError::NOT_FOUND )
    {
        // No marker: this node never pruned the transaction.
        return std::make_pair( PrunedLookup::NOT_FOUND, std::nullopt );
    }
    return outcome::failure( marker.error() );
}
SGTransaction::PrunedTransactionRecord record;
if ( !record.ParseFromArray( marker.value().data(), static_cast<int>( marker.value().size() ) ) )
{
    // T-17-0502: a malformed marker is an ERROR, never a silent PRUNED.
    MarkerLogger()->error( "Pruned marker for tx {} is malformed", tx_hash );
    return outcome::failure( std::errc::bad_message );
}
```

The fingerprint read copies these arms: `NOT_FOUND` ⇒ first-run (no downgrade — Pitfall 2), unreadable/malformed ⇒ the SAFE arm, never arm-anyway-on-parse-failure (Pitfall 3). The write side mirrors `WriteEpochWatermark`'s advisory posture (below). The `RoleFingerprint` helper may live here as statics or a sibling header — planner's pick (18-RESEARCH §Code Examples 2).

---

### `SuperGenius/src/crdt/globaldb/globaldb.cpp` / `.hpp` (persistence facade — expected zero-diff)

**Analog:** itself — the raw surface the fingerprint uses, already public (`globaldb.hpp :425-441`):

```cpp
/**
 * @brief Reads a node-local key straight from RocksDB, bypassing the CRDT layer.
 * @return The stored value, or `operation_canceled` once shutdown released the store.
 */
outcome::result<Buffer> GetRaw( const Buffer &key ) const;

/**
 * @brief Writes a node-local key straight to RocksDB, bypassing the CRDT layer.
 */
outcome::result<void> PutRaw( const Buffer &key, const Buffer &value );
```

**Node-local record write precedent** (`WriteEpochWatermark`, `ColdStorageManager.cpp:1494-1583`; key build + direct-face put + advisory warn at `:1567-1583`):

```cpp
sgns::storage::Buffer key;
key.put( std::string( kGcEpochWatermarkKey ) );
sgns::storage::Buffer value;
value.put( record );
auto written = gc_hot_store_->put( key, value );
if ( !written.has_value() )
{
    // Advisory bookkeeping: one rate-limited warn, never an abort.
    logger_->warn( "gc: epoch watermark write failed (advisory record; no pass impact)" );
}
```

**Atomicity contract citation** (if any doc/comment needs the value-XOR-markers precedent — `EraseEntry` staging, `globaldb.cpp:1700-1719`): caller-built `extra_entries` pairs join the SAME WriteBatch as the erase before the single commit. The fingerprint does NOT need this — it is a standalone node-local record, not erase-coupled.

**Expected diff: none.** Touch only if the fingerprint helper needs an exposure that `GetRaw`/`PutRaw` doesn't already cover (per 18-RESEARCH: they cover it).

---

### `SuperGenius/src/transaction/TxPruner.cpp` / `.hpp` (expected zero-diff)

**Analog:** itself — `PruneCycleStats :68-110` is the counter NAMING/DOCUMENTATION precedent D-04's walk-exempted counter mirrors (never-healthy-by-omission, split-counter with rationale doc-comments):

```cpp
/// Erasable block groups DEFERRED because the constituent CID's
/// journal record is gone AND the GC disposed-marker is present
/// ... The split exists so operators can see
/// stranded prune mass (never-healthy-by-omission, MI-02).
uint64_t cold_disposed_stranded_groups = 0;
```

And the per-cycle INFO surfacing precedent (`TxPruner.cpp:422-440` — counters, never failure reasons):

```cpp
logger_->info( "Prune cycle [generation {}]: examined={}, eligible={}, erased={}, held_blocks={}, "
               "cold_deferred={}, cold_unreadable={}, cold_disposed_stranded={}, skipped={}, errors={}, duration_ms={}, "
               "watermark={} — bytes reclaimed: not measured until Phase 20", ... );
```

**Expected diff: none** — D-04's counter lives in the GC pass stats (ColdStorageManager), not here; `PruneCycleStats` is cited for shape only (the `notes/16` "zero diff lines" precedent). The interrupt seams the E2E may use: `TxPruner::SetCycleInterruptHookForTest` + `kInterruptBeforeErase` (`TxPruner.hpp:289`) — cleared in teardown (see shared pattern).

---

### `SuperGenius/test/src/crdt/cold_gc_walk_gap_exempt_test.cpp` (NEW — Tier-1 red-first counter-test)

**Analog:** `cold_storage_gc_test.cpp` — the hermetic GC fixture family (real stores, fake S3, direct `GcPassOnce` drive)

**Core fixture pattern** (`:599-780`; `MakeManager`/`AttachGcDependencies` `:721-733`):

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

**Deterministic retention age** (`Backdate :750-755` — the t3/counter-test age setup):

```cpp
void Backdate( const Cid &cid, uint64_t age_ms )
{
    std::lock_guard<std::mutex> lock( *cold_store_mutex_ );
    auto written = shared_local_->SetSpilledAt( cid, UnixNowMs() - age_ms );
    ASSERT_TRUE( written.has_value() );
}
```

**Fixture composition** (SetUp `:601-655`): real hot RocksDB + `LocalBlockStore` cold dir + `InMemoryS3Client`/`InMemoryS3AdminClient` + real `ColdReadService`/`GraphsyncDAGSyncer` (with `cold_read_service_` as the hook — this is how evidence becomes consultable to the walk WITHOUT the full GlobalDB stack) + `CrdtDatastore::New` + `AttachGcDependencies`. **Test-side deletion** (D-03's "the fake can delete"): `InMemoryS3Client` supports deletion; local leg via `shared_local_` surfaces; `DeriveTestKey` (`:217`) derives the fake-S3 object key. **Evidence seeding:** `PruneEligibility::WritePrunedBlockEntryForTest` over the real db (or `SetPruneEvidenceLookup` install for the stub posture — `ColdReadService.cpp:478-494`, nullptr ⇒ NoEvidence). **Red-first:** LEG-1 (evidence present + hot gone + cold present) must be observed failing BEFORE the consult lands (Pitfall 8).

---

### `SuperGenius/test/src/crdt/cold_downgrade_e2e_test.cpp` (NEW — Tier-1 t0→t3 timeline)

**Analog:** `cold_evidence_matrix_test.cpp` — the full-GlobalDB hermetic stack with in-process re-open

**Teardown pattern** (`TeardownStack :344-380` — copy wholesale; seam-clearing FIRST, pubsub LAST):

```cpp
void TeardownStack()
{
    // Fixture discipline: a hook armed by a failing case must never
    // leak further - clear EVERY static seam before any teardown
    // touches the stores.
    sgns::TxPruner::SetCycleInterruptHookForTest( nullptr );
    crdt::GlobalDB::SetColdUploadStateHookForTest( nullptr );
    crdt::GlobalDB::SetEraseInterruptHookForTest( nullptr );

    if ( blockchain_ ) { (void)blockchain_->Stop(); }
    tm_.reset(); blockchain_.reset(); account_.reset();
    if ( db_ )    { db_->ShutdownNow(); }
    db_.reset();
    try { if ( pubs_ ) { pubs_->Stop(); } }
    catch ( const std::exception &err ) { ... }
    pubs_.reset(); io_.reset();
}
```

**Re-open pattern** (`BuildStackOnDir :390-517` — same hot dir = in-process restart; role param at the `TransactionManager::New` call `:495-505`):

```cpp
tm_ = sgns::TransactionManager::New( db_, io_, account_, blockchain_,
                                     sgns::NodeType::Light,   // ← the t1 role flip point
                                     0, kTimestampTolerance, kMutabilityWindow );
```

**Held-drainer posture** (hermetic cold block `:424-452`; the SC3 no-re-drain recipe — faulted fakes so NO drain/flush can advance anything):

```cpp
fake_s3_    = std::make_shared<sgns::blockstore::InMemoryS3Client>();
fake_admin_ = std::make_shared<sgns::blockstore::InMemoryS3AdminClient>();
if ( !inject_hermetic_clients )
{
    // The HELD-journal posture: the same hermetic fakes,
    // faulted - no drain pass or flush cycle can advance
    // any journal record (seed determinism).
    fake_s3_->SetFault( sgns::blockstore::S3Op::Put,
                        sgns::blockstore::S3FaultKind::Unavailable );
    fake_admin_->SetAdminFault( sgns::blockstore::S3AdminFaultKind::Unreachable );
}
sgns::crdt::SetColdStorageStackClientsForTesting(
    std::static_pointer_cast<sgns::blockstore::S3Client>( fake_s3_ ),
    std::static_pointer_cast<sgns::blockstore::S3AdminClient>( fake_admin_ ) );
...
// Hygiene: the process-global override has served its purpose.
sgns::crdt::SetColdStorageStackClientsForTesting( nullptr, nullptr );
```

**Leg order = D-12's timeline:** t0 archive-open (seed via real CRDT Put, `WaitAllDurable`, fingerprint written) → teardown → t1 light re-open (interlock fire/disarm + ack leg + birth-tiered-light control leg per Pitfall 2) → t2 prune cycle (held drainer, `stats.erased > 0`, journal stays Durable, `LookupPrunedBlockEntry == PRUNED`, `GetNodeWithoutRequest` error `HISTORY_PRUNED_LOCALLY`) → t3 retention GC (`Backdate` + direct `GcPassOnce`, walk_exact, exempted > 0, `EvictLocalAndMarkDisposed` observed, remote-backed serve of non-pruned cold). Waits: `PollUntil` bounded predicates only.

---

### `SuperGenius/test/src/crdt/cold_downgrade_live_smoke_test.cpp` (NEW — Tier-3 dev-gated)

**Analog:** `cold_compose_live_smoke_test.cpp` — the env-gated live-leg header contract (`:1-46`)

**File-header/env-gate pattern** (copy the shape: brief + ENV GATE + posture honesty + operator runbook; gate = `SGNS_BLOCKSTORE_TEST_MINIO_BIN`, loud labelled skip without it, `LABELS "Tier3"`, never in the Tier-1 lane):

```cpp
/**
 * @file       cold_compose_live_smoke_test.cpp
 * @brief      D-11b dev-gated live SC3 leg ...: a real MinIO community server +
 *             the PRODUCTION S3 client + ...
 *             ENV GATE (the v1.1 TEST-03 pattern,
 *             thirdparty/sgns-blockstore/docs/testing-tiers.md):
 *             dev-gated opt-in via SGNS_BLOCKSTORE_TEST_MINIO_BIN ...
 *             Without the gate the suite loud-skips with a labelled
 *             message; it NEVER runs in the Tier-1 CI lane ...
 *             Posture honesty (D-11's hybrid rule): the deterministic
 *             stand-in is cold_compose_matrix_test ...; when the
 *             environment cannot run it, the recorded posture is
 *             loud-skip + the deterministic leg — never silence.
 */
```

`MinioChildProcess` + `TcpPortAnswers` are copied VERBATIM from `cold_prune_live_smoke_test.cpp` (named-exception precedent — name the copy in the commit message).

---

### `SuperGenius/test/src/crdt/CMakeLists.txt` (config — registration)

**Analog:** itself — the two registration blocks

**Tier-1 pattern** (`:386-434` — comment block stating purpose + gates, then `addtest` + include + link set + whole-archive + label):

```cmake
# Evidence-aware cold-serving matrix (...): ...
if(SGNS_COLD_STORAGE)
addtest(cold_evidence_matrix_test
    cold_evidence_matrix_test.cpp
)
target_include_directories(cold_evidence_matrix_test PRIVATE
    ${AsyncIOManager_INCLUDE_DIR}
)
target_link_libraries(cold_evidence_matrix_test
    sgns-blockstore::sgns-blockstore
    crdt_globaldb
    crdt_datastore
    rocksdb
    genius_node_test
    p2p::p2p_logger
    logger
)
if(MSVC)
    target_link_options(cold_evidence_matrix_test PUBLIC /WHOLEARCHIVE:$<TARGET_FILE:genius_node_test>)
elseif(APPLE)
    target_link_options(cold_evidence_matrix_test PUBLIC -force_load "$<TARGET_FILE:genius_node_test>")
else()
    target_link_options(cold_evidence_matrix_test PUBLIC
        "-Wl,--whole-archive"
        "$<TARGET_FILE:genius_node_test>"
        "-Wl,--no-whole-archive"
    )
endif()
set_tests_properties(cold_evidence_matrix_test PROPERTIES LABELS "Tier1")
endif()
```

**Tier-3 pattern** (`:437-510`): identical block with `set_tests_properties(... PROPERTIES LABELS "Tier3")` and the header comment naming the env gate. The downgrade E2E uses the `cold_evidence_matrix_test` link set verbatim (it needs the same `genius_node_test` whole-archive for the `PruneEligibility` test helpers + `TransactionManager` fixture); the counter-test likely matches `cold_compose_matrix_test`'s leaner set (same minus `ipfs-lite-cpp::ipfs_datastore_in_memory` unless a re-warm leg appears). `ctest -L Tier1` contract — never `-LE`, `--no-tests=error` discipline.

---

### `.planning/workstreams/rocksdb-backup/notes/18-collectibility-policy-downgrade-interlock.md` (NEW — rulings doc)

**Analog:** `notes/16-txpruner-gc-composition-rulings.md` (+ `notes/17-seal-growth-decision.md` for the decision-record variant)

**Header pattern** (`notes/16 :1-11`):

```markdown
# TxPruner × GC Composition Rulings (v1.2 Phase 16)

**Ruled:** 2026-11-18
**Context commits:** SuperGenius `af644481f` (Phase 15 close) → ... on `dev_coldstorage_additions`
**Requirements:** COMP-03 (SC3 fail-safe), COMP-01 (D-02 Interaction-C readers)
**Decisions ruled here:** D-02, D-10, D-11, D-12 (16-CONTEXT); D-01 recorded for completeness

This is the workstream planning doc Phase 18's policy record cites (...)
```

**Body shape:** lettered sections `(a)`, `(b)`, ... each carrying one ruling with mechanism prose + verbatim key constants/code refs; an options-considered-and-rejected table (`## (d) Options considered and rejected` — D-14's v2 sketch and D-05's rejected WARN-only belong in this shape); `## Evidence` (test legs, red-first signature); `## Deferred item ...` (if any); `## Forward pointers` (REQUIREMENTS Future cross-refs — v2 `Remove`/`DisposedDurable`). `notes/17` adds committed-evidence citation by JSON key where numbers exist (not needed here — no measurements). The doc carries: two-halves policy, permanent-once-written invariant, v2 contract-ask sketch (D-14), GC exemption record, operator downgrade checklist (D-08 — its own section, cited by path from the ack-key docs), tiered-node model (archive/tiered-light/plain-light), downgrade timeline.

### `.planning/workstreams/rocksdb-backup/STATE.md` (one-liner)

**Analog:** the SEAL-01 line at `:56` — one bullet in the v1.2 key-decisions list: date-stamped, verdict-bearing, citing the notes doc by path:

```markdown
- SEAL-01 measured and decided (2026-11-19): accept hot seal growth — ... (evidence: phases/17-.../17-seal-growth-evidence/); redesign deferred to the recorded D-11 numeric triggers in notes/17-seal-growth-decision.md; ...
```

Phase 18's line: POLICY-01/02 decided (date) — cold permanent this milestone + exemption shipped as code + interlock proven; cite `notes/18-collectibility-policy-downgrade-interlock.md` by path.

---

## Shared Patterns

### 1. Evidence consult — one predicate, fail-closed arms
**Source:** `graphsync_dagsyncer.cpp:866-880` (switch shape) + `:366-376` (entry point)
**Apply to:** the gap-site consult in `ColdStorageManager.cpp` — the ONLY permissive arm is `Pruned ⇒ exempted-leaf-continue`; `Malformed` and `NoEvidence`/`nullopt` keep today's abort. Never a GC-local `/prune/blk` read, never error-code matching, never age.

### 2. WARN + return disarm gate (fail-toward-under-erase)
**Source:** `GeniusNode.cpp:5202-5210`
**Apply to:** the interlock gate (same file, inserted after the Light check). Node fully starts; pruner disarmed; WARN names the ack key + checklist path. Every fingerprint-read failure arm resolves SAFE (disarm or no-downgrade — never arm-on-parse-failure).

### 3. Per-key type-checked config parse, absent-keeps-default
**Source:** `PruningConfig::FromJSON` (`PruneEligibility.hpp:243-292`, body in `.cpp`)
**Apply to:** the ack key (inside the `"pruning"` object — 18-RESEARCH A1); the `disabled_reason`-style carrier if the ack needs an operator-facing message.

### 4. Node-local raw record (key statics + GetRaw/PutRaw + advisory write)
**Source:** `PruneEligibility.hpp:418-421` (prefix discipline) + `PruneEligibility.cpp:180-200` (read arms) + `ColdStorageManager.cpp:1567-1583` (advisory write) + `globaldb.hpp:425-441` (surface)
**Apply to:** the role fingerprint. Keyspace under the `/prune/` family or a pinned `/crdt/`-style prefix — never a swept keyspace (Pitfall 4). One key home (D-C1).

### 5. Never-healthy-by-omission counters, surfaced in INFO
**Source:** `PruneCycleStats` doc-comments (`TxPruner.hpp:95-110`) + per-cycle INFO (`TxPruner.cpp:422-440`) + per-pass INFO (`ColdStorageManager.cpp:942-945`)
**Apply to:** the walk-exempted counter — per-exempted-CID increment, per-pass reset alongside `pass_reclaimed_count_`, published to a status atomic at pass end, appended to the `:942` INFO line. Counters, never failure reasons.

### 6. Both-homes ruling comments
**Source:** `[D-12, v1.2 Phase 16, COMP-03 — ...]` block at `ColdStorageManager.cpp:1298-1305`
**Apply to:** the exemption site, the interlock gate, and the ack-key parse — each carries a `[D-0x, v1.2 Phase 18 — ...]` comment citing `notes/18-collectibility-policy-downgrade-interlock.md`.

### 7. Hermetic full-stack + in-process re-open (TEST-ONLY client override)
**Source:** `cold_evidence_matrix_test.cpp:344-517` (`SetColdStorageStackClientsForTesting` around `GlobalDB::New`, clear-after hygiene, `ShutdownNow` teardown, `BuildStackOnDir` re-open, role param at `TransactionManager::New`)
**Apply to:** the downgrade E2E + interlock legs. Re-inject fakes BEFORE `GlobalDB::New`, clear AFTER. Declaration order == reverse destruction order.

### 8. Determinism kit (no wall-clock, no background-thread timing)
**Source:** `Backdate`/`SetSpilledAt` (`cold_storage_gc_test.cpp:750-755`), direct `GcPassOnce()` with `gc_interval_ms = 0` dormant, `PollUntil` bounded waits, `FreshDir` per case, held-drainer faulted fakes (`cold_evidence_matrix_test.cpp:441-452`)
**Apply to:** all three new test files (Windows-CI discipline, 18-RESEARCH Pitfall 9).

### 9. Static test-seam clearing in teardown
**Source:** `TeardownStack` (`cold_evidence_matrix_test.cpp:347-351`): `TxPruner::SetCycleInterruptHookForTest(nullptr)` + `GlobalDB::SetColdUploadStateHookForTest(nullptr)` + `GlobalDB::SetEraseInterruptHookForTest(nullptr)` — clear EVERY seam first
**Apply to:** any new suite using interrupt/window hooks (`kInterruptBeforeErase`, erase-window observer — `globaldb.hpp:527/:537`, `TxPruner.hpp:289`).

### 10. Red-first counter-test discipline
**Source:** 18-CONTEXT D-01 + the v1.1 resurrection-suite precedent (cited 18-RESEARCH Pitfall 8); LEG-naming + red-signature capture shape from `cold_compose_matrix_test` (S3a `SC3-UNDIFFERENTIATED` signature, `notes/16` Evidence section)
**Apply to:** `cold_gc_walk_gap_exempt_test.cpp` — LEG-1 written and observed failing against the unmodified walk before the consult lands.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| — | — | — | No entries. Every file-to-touch has an exact or role-match analog on this line. The novel composition (t0→t3 single-node timeline) assembles entirely from verified fixtures. |

The only genuinely new artifacts with no line-by-line precedent are minor naming/shape choices reserved to the planner per 18-CONTEXT "The Agent's Discretion": ack-key exact name, fingerprint record layout, counter field names, `notes/18-*` exact filename, and whether `RoleFingerprint` lives in `PruneEligibility` or a sibling header — each is a variation on a pattern above, not a missing pattern.

## Metadata

**Analog search scope:** `SuperGenius/src/{crdt,transaction,account}/`, `SuperGenius/test/src/crdt/`, `.planning/workstreams/rocksdb-backup/{notes,STATE.md}`
**Files scanned:** 20 analog files read (non-overlapping ranges); all anchors verified at `84d87d462` (= 18-RESEARCH anchor line; no drift, no re-location needed)
**Tracked-source gate:** all 20 analogs pass `git ls-files` (submodule or outer repo as appropriate)
**Pattern extraction date:** 2026-11-19
**Anchor-drift note for the planner:** re-run 18-RESEARCH's Anchor Re-Location Record (Steps 1-4) only if a commit lands on `dev_coldstorage_additions` before execution touches the anchored files.
