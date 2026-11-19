# Phase 17: Seal Growth Measurement & Decision - Pattern Map

**Mapped:** 2026-11-18
**Files analyzed:** 6 (3 create, 2 modify, 1 conditional modify)
**Analogs found:** 6 / 6 (one sub-component — the evidence JSON emitter — has no in-repo analog; see No Analog Found)

**Anchor status:** SuperGenius HEAD verified this session at `741980f5dc461aa964edb93f7f52a85a79c2ee51` (= the research's ruled commit). **Every excerpt below was re-read first-hand in the current working tree and all line numbers match 17-RESEARCH.md's anchor record exactly — no drift.** Re-run the research's anchor procedure (symbols, not lines) at execution start if HEAD moves.

**Tracked-source gate:** all analog paths verified `git ls-files` TRACKED (SuperGenius paths checked from within the submodule; `.planning` paths from repo root). No gitignored/mirror paths are cited.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `SuperGenius/test/src/crdt/cold_seal_growth_test.cpp` *(create; exact name is planner discretion per CONTEXT)* | test (env-knobbed benchmark/probe harness) | batch (volume seeding) + transform (enumeration timing) + file-I/O (RocksDB + evidence emit) | `SuperGenius/test/src/crdt/cold_storage_wallclock_soak.cpp` | exact (harness discipline); 3 secondary analogs below |
| `SuperGenius/test/src/crdt/CMakeLists.txt` *(modify: one registration block)* | config (test/build registration) | n/a | `cold_compose_matrix_test` block, `test/src/crdt/CMakeLists.txt:436-472` (Tier1) + `cold_storage_wallclock_soak` block `:575-592` (Tier3) | exact |
| `.planning/workstreams/rocksdb-backup/notes/17-seal-growth-decision.md` *(create; exact filename is discretion, home is the notes/ tree)* | documentation (decision/rulings record, D-10) | n/a | `.planning/workstreams/rocksdb-backup/notes/16-txpruner-gc-composition-rulings.md` | exact |
| `.planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-*-evidence/` *(create: JSON + rendered MD + run captures, D-09)* | evidence artifact | file-I/O | `.planning/workstreams/rocksdb-backup/milestones/v1.1-phases/12-integration-hardening-fault-races-fresh-clone-proof/12-soak-evidence/` | role-match (trio shape exact; the JSON layer has NO precedent) |
| `.planning/workstreams/rocksdb-backup/STATE.md` *(modify: one key-decisions bullet)* | config (workstream state) | n/a | STATE.md `## Accumulated Context` → `**Key decisions ...**` bullet list (`:45-55`) | exact |
| `SuperGenius/src/crdt/graphsync_dagsyncer.hpp` *(CONDITIONAL modify — D-12 out-of-band case only)* | production constants (walk-bound re-tune, SC2) | n/a | itself — the derivation comment at `:58-81` + `kForcedWalkPeerFailoverPerCid{ 8 }` at `:82` carry the in-code amendment contract | exact (self-amendment site) |

---

## Pattern Assignments

### `SuperGenius/test/src/crdt/cold_seal_growth_test.cpp` (test harness, batch + transform + file-I/O)

**Primary analog:** `SuperGenius/test/src/crdt/cold_storage_wallclock_soak.cpp` (whole file, ~600 lines) — the env-knobbed measurement-harness discipline: Doxygen header stating tier + env gates, `EnvOr`/`EnvSet` knob helpers, minimal-stack construction, stdout-status-as-evidence.

**Secondary analogs (per leg):**
- Volume/density seeding discipline → Phase 14 journal-injection kit, `cold_prune_gate_test.cpp:690-810`
- Fidelity-leg enumeration instrument → Phase 11 prefix-spy, `cold_storage_gc_test.cpp:432-575`
- Real-walk seal-seeding surface → W3 ghost-CID leg, `node_startup_test.cpp:1065-1134`

**Header + env-gate pattern** (`cold_storage_wallclock_soak.cpp:1-34` — copy this header shape: brief naming the phase/decision IDs, the evidence-is-stdout claim, and the NAMES-only env rule):

```cpp
/**
 * @file       cold_storage_wallclock_soak.cpp
 * @brief      Dev-gated wall-clock soak (TEST-02 SC3 / D-07, v1.1
 *             Phase 12 plan 12-02 Task 3) - NEVER in the Tier-1 lane.
 *
 * One long-running scenario (default 30 minutes,
 * SGNS_COLD_STORAGE_SOAK_DURATION_MIN overrides; 20-40 min is the
 * accepted window) ... printing timestamped status lines ... to
 * stdout - the status capture IS the evidence.
 *
 * Env gates (NAMES only - never values in committed captures):
 *   SGNS_COLD_STORAGE_SOAK_ENABLE=1      - required to run (else skip)
 *   SGNS_COLD_STORAGE_SOAK_DURATION_MIN  - minutes (default 30)
 *   SGNS_COLD_STORAGE_SOAK_RESUME=1      - resume-after-kill mode
 *
 * Hermetic: InMemoryS3Client / InMemoryS3AdminClient fakes only.
 */
```

The seal probe's equivalent knobs (CONTEXT D-08 discretion): scale, DAG shape (depth/fan-out/mix per D-05), cache state (D-03), repetition count (D-12 band). Big legs dev-gated like `SOAK_ENABLE`; the bounded 10⁶ floor leg runs ungated in Tier-1 (D-07) — model the ungated shape on any existing Tier-1 suite header (e.g. `cold_compose_matrix_test.cpp`).

**Env-knob helper** (`cold_storage_wallclock_soak.cpp:108-115`, verbatim — integers only, V5 posture):

```cpp
    uint64_t EnvOr( const char *name, uint64_t fallback )
    {
        const char *raw = std::getenv( name );
        return raw == nullptr || *raw == '\0'
                   ? fallback
                   : static_cast<uint64_t>( std::strtoull( raw, nullptr, 10 ) );
    }
```

(`EnvSet(name)` at `:117-121` is the boolean-valued companion; `PollUntil` at `:90-106` is the sanctioned wait helper if any leg needs one.)

**Minimal-stack construction** (`cold_storage_wallclock_soak.cpp:173-186` + the vendored wrap at `:206-210` — the D-08/Pattern-1 stack: plain `storage::rocksdb` → `getDB()` → `ipfs_lite::rocksdb::create` → vendored `RocksdbDatastore`; NO GlobalDB/node for volume/enumeration/density legs):

```cpp
        rocksdb::Options hot_options;
        hot_options.create_if_missing = true;
        auto opened_hot = rocksdb::create( kHotDir, hot_options );
        if ( !opened_hot.has_value() )
        {
            return false;
        }
        out.hot = std::move( opened_hot.value() );
        // ... (LocalBlockStore/S3 fakes are cold-storage-specific — the
        //      seal probe omits them; seals live only in the hot store)
        auto ipfs_db = sgns::ipfs_lite::rocksdb::create( out.hot->getDB() );
        if ( !ipfs_db.has_value() )
        {
            return false;
        }
        out.inner     = std::make_shared<sgns::ipfs_lite::ipfs::RocksdbDatastore>( ipfs_db.value() );
```

Production-equivalent construction for reference: `globaldb.cpp:815-822` (`IpfsRocksDb::create(m_datastore->getDB())` → `RocksdbDatastore`). Growing-DB legs (D-02) should ALSO set GlobalDB's production options (`globaldb.cpp:690-697`): `target_file_size_base/max_compaction_bytes/write_buffer_size = 32 MiB`, `level0_file_num_compaction_trigger = 1`, `target_file_size_multiplier = 1`, `level_compaction_dynamic_level_bytes = false` — and fingerprint whichever options are used into the evidence JSON (D-09, Pitfall 4).

**Fixture-root constants** (`cold_storage_wallclock_soak.cpp:151-154` — fixed roots under `test-data/`, NOT FreshDir, so growing-DB/resume legs reopen the same dirs):

```cpp
    constexpr const char *kHotDir  = "test-data/cold-storage-wallclock/hot";
    constexpr const char *kColdDir = "test-data/cold-storage-wallclock/cold";
```

**Seeding discipline — direct-CF kit shape** (`cold_prune_gate_test.cpp:690-712` — the Phase 14 D-08a precedent the volume legs extend; note the lock-discipline comment pattern — a direct-open helper is legal only while the owning GlobalDB is CLOSED):

```cpp
    //
    // Journal-CF seeding machinery (v1.2 Phase 14 plan 14-03 Task 1,
    // D-08a): deterministic arbitrary-state injection against the
    // coldstore's PUBLISHED upload_journal column family. LOCK
    // DISCIPLINE: the helper opens the coldstore RocksDB directly and is
    // therefore legal ONLY while the fixture's GlobalDB is CLOSED (a
    // second Open against a live store hits the RocksDB dir lock) — the
    // three-phase same-dir flow (populate -> TeardownStack -> seed ->
    // BuildStackOnDir reopen) enforces it structurally.
    //
```

For the seal probe the seeding goes through the SANCTIONED surfaces instead of raw CF writes (GATE-03/D-C1 — see Shared Patterns): seals via `markResolved`/`seal()`, `/prune/blk` density fixtures via `WritePrunedBlockEntryForTest`. Copy the kit's *structure* (codec constants co-located, key helper mirrors the one home, hygiene asserts before write — `cold_prune_gate_test.cpp:714-724` shows the `JournalKeyOf` mirror + `EXPECT_FALSE(cid.has_error())` shape), not its raw-Put mechanics.

**Fidelity-leg enumeration instrument** (`cold_storage_gc_test.cpp:432-475` — the Phase 11 prefix-spy; a `BufferStorage` decorator wrapping `std::shared_ptr<rocksdb> inner`, tallying per-key ops under mutex):

```cpp
    class PrefixSpyHotStore final : public BufferStorage
    {
    public:
        explicit PrefixSpyHotStore( std::shared_ptr<rocksdb> inner )
            : inner_( std::move( inner ) )
        {
        }

        /// Operations whose key CONTAINS the needle (prefix segments like
        /// "/t/", "/h/", "/k/", "/s/" match under any namespace root).
        uint64_t OpsMatching( const std::string &needle ) const
        {
            std::lock_guard<std::mutex> lock( mutex_ );
            uint64_t                    total = 0;
            for ( const auto &[key, ops] : op_by_key_ )
            {
                if ( key.find( needle ) != std::string::npos )
                {
                    total += ops;
                }
            }
            return total;
        }
```

(continues with `ProtectedPrefixOps()`/`TotalOps()`/`WriteOpsMatching()`/`TotalWriteOps()` and forwarded `get/put/contains/cursor/batch` overrides at `:477-575`; `SpyBufferBatch` wrapper just above at `:400-420` region). The fidelity leg adapts this discipline to exact-key byte comparison: seeded `<cid>sealed` rows vs walk-produced rows must be byte-identical (D-04).

**Real-walk seal-seeding surface** (`node_startup_test.cpp:1104-1116` — the W3 precedent; the ONLY sanctioned seal-seeding path, real content-addressed CIDs whose bytes exist nowhere):

```cpp
    auto ghost_a = sgns::ipfs_lite::ipld::IPLDNodeImpl::createFromString( "walk gap ghost a - bytes exist nowhere" );
    auto ghost_b = sgns::ipfs_lite::ipld::IPLDNodeImpl::createFromString( "walk gap ghost b - bytes exist nowhere" );
    ASSERT_TRUE( ghost_a );
    ASSERT_TRUE( ghost_b );
    // ...
    ASSERT_TRUE( syncerOf( node_db )->markResolved( ghost_a->getCID() ).has_value() );
    ASSERT_TRUE( syncerOf( node_db )->markResolved( ghost_b->getCID() ).has_value() );
```

Syncer-side aliases for reference: `GraphsyncDAGSyncer::markResolved`/`isResolved` at `graphsync_dagsyncer.cpp:1202-1213` (both take `dagMutex_` then delegate `dagService_->`). Open Question 2 (node-level W-shape vs datastore-level walk) is planner discretion — the W3 block shows the node-level shape if chosen.

**Enumeration leg — raw iterator, streaming count** (`src/storage/rocksdb/rocksdb.hpp:26-40, 103-105` defines the surface; `QueryResult = std::map<Buffer,Buffer>` at `:40` is why `query(prefix)` is FORBIDDEN at 10⁷ — it materializes every KV):

```cpp
        using Iterator     = ::ROCKSDB_NAMESPACE::Iterator;
        using ReadOptions  = ::ROCKSDB_NAMESPACE::ReadOptions;
        using Options      = ::ROCKSDB_NAMESPACE::Options;
        // ...
        using QueryResult  = std::map<Buffer, Buffer>;   // <-- materializes; do NOT use at scale
        // ...
        [[nodiscard]] const std::shared_ptr<DB> &getDB() const
        {
            return db_;
        }
```

Leg skeleton (17-RESEARCH Code Examples, composed from that surface — suffix-filter because seals share the default CF with binary block keys and `/crdt/` rows, Pitfall 1):

```cpp
auto db_handle = hot_store->getDB();
std::unique_ptr<ROCKSDB_NAMESPACE::Iterator> it(
    db_handle->NewIterator( ROCKSDB_NAMESPACE::ReadOptions() ) );
uint64_t seals = 0, others = 0;
uint64_t seal_key_bytes = 0;
const auto t0 = std::chrono::steady_clock::now();
for ( it->SeekToFirst(); it->Valid(); it->Next() )
{
    const auto k = it->key().ToString();
    if ( k.size() > 6 && k.compare( k.size() - 6, 6, "sealed" ) == 0 )
    {
        ++seals;
        seal_key_bytes += k.size() + it->value().size();  // value is empty by shape
    }
    else
    {
        ++others;  // the shared-CF denominator (D-11's hot-store % context)
    }
}
```

Cold-cache variant (D-03, mechanics are discretion per CONTEXT): `ReadOptions::fill_cache = false` and/or fresh-process resume-mode reopen (the soak's `SGNS_COLD_STORAGE_SOAK_RESUME=1` same-dir reopen at `cold_storage_wallclock_soak.cpp:23-27` is the precedent for the latter).

**The measured row** (vendored, verbatim — `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/impl/datastore_rocksdb.cpp:48-66`; NEVER hand-construct, NEVER edit this file):

```cpp
    IPFS::outcome::result<void> RocksdbDatastore::seal( const CID &key )
    {
        BOOST_OUTCOME_TRY( auto cid_string, key.toString() );
        cid_string += "sealed";
        common::Buffer key_buf;
        key_buf.put( cid_string );
        common::Buffer value_buf;
        return rocksdb_->put( key_buf, std::move( value_buf ) );
    }
```

Value is an EMPTY buffer — per-seal store cost ≈ key bytes (~52 B CIDv0 / ~65 B CIDv1 + index overhead; the probe measures the real number).

**Density-fixture seeding + reading** (D-06; `src/transaction/PruneEligibility.cpp:358-369` test writer verbatim; reader `LookupPrunedBlockEntry` at `:295-331` returns `std::pair<PrunedBlockLookup, std::optional<SGTransaction::PrunedBlockRecord>>` — tri-state + malformed-as-error; both builders at `:286-293`/`:333-356` are the ONE home per D-C1):

```cpp
    outcome::result<void> PruneEligibility::WritePrunedBlockEntryForTest( crdt::GlobalDB   &db,
                                                                          const std::string &cid_string,
                                                                          const std::string &tx_hash,
                                                                          uint64_t          generation )
    {
        // TEST-ONLY (see header): the production write joins the erase
        // WriteBatch so value XOR markers hold atomically (D-01).
        auto entry = BuildPruneBlockMarkerEntry( cid_string, tx_hash, generation );
        return db.PutRaw( entry.first, entry.second );
    }
```

Density = `/prune/blk`-bearing ancestry / total ancestry per fixture DAG shape; denominator is the generator's emitted DAG (known exactly — Pitfall 7).

---

### `SuperGenius/test/src/crdt/CMakeLists.txt` (config, registration block)

**Analog:** the neighboring `cold_compose_matrix_test` Tier-1 block (`:436-472`) and `cold_storage_wallclock_soak` Tier-3 block (`:575-592`). Copy a neighboring block VERBATIM and rename (Pitfall 8 — the audit exists because `addtest()` has no LABELS support).

**Tier-1 registration shape** (`:436-472`, abridged to the skeleton — full block includes the identical `target_include_directories` / `target_link_libraries` / MSVC-APPLE-else whole-archive triad):

```cmake
# ...comment naming the phase/decision + why Tier1...
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

# ...whole-archive triad for genius_node_test (MSVC /WHOLEARCHIVE, APPLE -force_load, else -Wl,--whole-archive)...

set_tests_properties(cold_compose_matrix_test PROPERTIES LABELS "Tier1")
endif()
```

**Tier-3 dev-gated shape** (`:575-592` — the pattern for any big-leg entry IF the planner splits targets; note the deliberate no-Tier1 comment):

```cmake
# Dev-gated wall-clock soak (TEST-02 SC3 / D-07, plan 12-02 Task 3):
# env-gated (SGNS_COLD_STORAGE_SOAK_ENABLE), Tier3 - NEVER Tier1, and
# the registration line deliberately carries no Tier1 label. ...
if(SGNS_COLD_STORAGE)
addtest(cold_storage_wallclock_soak
    cold_storage_wallclock_soak.cpp
)

target_link_libraries(cold_storage_wallclock_soak
    sgns-blockstore::sgns-blockstore
    crdt_globaldb
    crdt_datastore
    rocksdb
)


set_tests_properties(cold_storage_wallclock_soak PROPERTIES LABELS "Tier3")
endif()
```

**Wiring guards** (`test/tier1_audit_check.cmake`, enforced by the registered `tier1_static_audit` test): (1) every `addtest(cold_*` needs a matching `set_tests_properties(cold_* ... LABELS)` line; (2) every target linking `sgns-blockstore::sgns-blockstore` sits inside `if(SGNS_COLD_STORAGE)`; (3) `cold_storage_wallclock_soak` carries NO Tier1 label. A pure seal probe links neither blockstore nor gated includes → Open Question 1 recommends mirroring neighbors anyway and letting the audit arbitrate.

---

### `.planning/workstreams/rocksdb-backup/notes/17-seal-growth-decision.md` (documentation, decision record)

**Analog:** `.planning/workstreams/rocksdb-backup/notes/16-txpruner-gc-composition-rulings.md` (whole file, ~120 lines) — the D-10 shape precedent. Copy its structure exactly:

```markdown
# TxPruner × GC Composition Rulings (v1.2 Phase 16)

**Ruled:** 2026-11-18
**Context commits:** SuperGenius `af644481f` (Phase 15 close) → `20519ce87` (16-02 Task 1, the consult chain) → the 16-02 Task 2 test commit on `dev_coldstorage_additions`
**Requirements:** COMP-03 (SC3 fail-safe), COMP-01 (D-02 Interaction-C readers)
**Decisions ruled here:** D-02, D-10, D-11, D-12 (16-CONTEXT); D-01 recorded for completeness

This is the workstream planning doc Phase 18's policy record cites (D-12's both-homes rule: ...).

---

## (a) The starvation interplay
## (b) The D-10 ruling — ...
## (c) One-cycle observability lag
## (d) Options considered and rejected        <-- TABLE: Option | Verdict | Why
## (e) D-02 — Interaction-C ruling: ...
## (f) D-01 — sequencing record
## Evidence                                   <-- per-leg evidence bullets citing committed artifacts
## Deferred item registered by this phase's diagnosis
## Forward pointers                           <-- its Phase 17 pointer exists; Phase 17's doc points at Phase 18/19 + future redesign
```

Phase 17's doc adapts: (a) the growth being accepted; (b) the SC3 ruling with capacity math (D-13 spectrum-band: representative mix + deep-chain/wide-fan-out endpoints as the uncertainty band); (c) the D-12 tolerance-band derivation (variance numbers BEFORE the verdict — Pitfall 6); (d) options table (accept vs spill/compaction/sidecar, citing REQUIREMENTS Future); Evidence cites the committed JSON; Forward pointers → Phase 18 policy record, Phase 19 capstone, future redesign milestone. **Citation list per the research's v1.1 ruling:** (1) the in-code derivation comment `graphsync_dagsyncer.hpp:58-82`, (2) `crdt_datastore.hpp:743` + `GeniusNode.hpp:1225` sibling 8-bounds, (3) develop-line `SuperGenius/.planning/phases/19-pruned-node-survival-recovery-hardening/19-07-SUMMARY.md` (`RefusalFailover ≤ 8`, `PrunedMesh [1,4]`), (4) this phase's own probe numbers. Do NOT cite "v1.1 recovery-suite SUMMARYs" — that citation does not resolve. The doc also documents D-11 numeric triggers (each citing the JSON) and the D-08 re-run instructions.

---

### `17-*-evidence/` directory (evidence artifact, file-I/O)

**Analog:** `milestones/v1.1-phases/12-integration-hardening-fault-races-fresh-clone-proof/12-soak-evidence/` — the committed-evidence trio. Copy its README discipline (`12-soak-evidence/README.md`):

- **The binary** section: source path, `cmake --build ... --target <name>`, working directory (`SuperGenius/build/Windows/Debug/test_bin/Debug` — fixture roots are `test-data/...` relative to it)
- **Env gates** table headed "NAMES only — never values in captures"
- **Run procedure** numbered steps to reproduce the evidence
- **Files** list: `README.md` (runbook) + `run-capture.md` (transcript) + `status-capture.txt` (status-line excerpts)
- **Redaction grep** before commit (credential-value shapes = 0 matches)

**Upgrade per D-09:** add machine-readable JSON beside the MD (raw numbers, hardware/OS/build fingerprint, RocksDB options, dataset fingerprint) + a rendered MD table. The JSON emitter itself has NO in-repo analog — see No Analog Found.

---

### `.planning/workstreams/rocksdb-backup/STATE.md` (config, one-line entry)

**Analog:** the `## Accumulated Context` → `**Key decisions (from v1.2 research SUMMARY, 2026-11-13):**` bullet list at `:45-55`. Existing Phase-17 bullet (`:55`):

```markdown
- SEAL probe feeds Phase 15's walk bounds (probe = first plan of Phase 17; the recorded decision closes citing real walk-recovery numbers)
```

Add ONE bullet in the same voice recording the closed decision (accept vs future design + where the rulings doc + triggers live), and update `## Current Position` per the usual STATE.md session flow.

---

### `SuperGenius/src/crdt/graphsync_dagsyncer.hpp` (CONDITIONAL production touch, D-12 out-of-band case ONLY)

**Analog:** itself. The amendment site already carries the contract in-code (`:58-82`; verified verbatim this session — comment `:58-81`, constant `:82`):

```cpp
        /**
         * @brief      Per-CID peer-failover budget for the forced walk's
         *             recovery fetches (RECOVER-04/D-06, v1.2 Phase 15).
         *
         * Derivation - the codebase's three independent 8-bounds converge:
         * the failed-root retry ladder (MAX_FAILED_ROOT_RETRIES = 8,
         * crdt_datastore.hpp), the bootstrap walk retry bound
         * (bootstrap_walk_max_retries_ = 8, GeniusNode.hpp), and the
         * observed refusal-failover attempts (<= 8 RefusalFailover,
         * develop 19-07-SUMMARY); PrunedMesh's observed [1,4] shows
         * healthy meshes need well under it. ...
         *
         * Deliberately NOT a config knob (Phase 14 D-04 no-new-config-
         * surface posture): Phase 17 SC2's ancestry-density probe
         * validates/re-tunes this constant against real walk-recovery
         * numbers (derive-now, refine-later - both halves of the recorded
         * Phase 15 <-> 17 dependency stay honored). ...
         */
        static constexpr uint32_t kForcedWalkPeerFailoverPerCid{ 8 };
```

If (and only if) the probe lands outside the recorded tolerance band: change the value, extend the derivation comment with the probe's numbers + band, and record the amendment at BOTH homes (here + the decision doc — Phase 16 D-12's both-homes rule). The verdict must be recorded BEFORE the edit (Pitfall 6 / Security table). No other production diff is sanctioned.

---

## Shared Patterns

### Sanctioned-path seeding (GATE-03 + D-C1)
**Source:** `ColdStorageManager.cpp:1210-1212` ruling text; `datastore_rocksdb.cpp:48-66`; `PruneEligibility.cpp:286-369`; W3 usage `node_startup_test.cpp:1116`
**Apply to:** every seeding leg of the harness
Seals ONLY via `seal()`/`markResolved` (never `put(<cid>+"sealed")`); `/prune/*` keys ONLY via `PruneEligibility` builders/`WritePrunedBlockEntryForTest` (never string formatting); presence checks ONLY via `is_sealed`/`isResolved`. The `seal()` overhead is itself part of the measured seeding rate.

### Read/count/time-only posture (invariant 3)
**Source:** REQUIREMENTS governing invariant 3; CONTEXT domain
**Apply to:** every leg
No delete, no remove, no `DeleteRange`, no re-shaping anywhere in the harness. The only sanctioned production touch is the conditional D-12 re-tune.

### Env-knobbed determinism + NAMES-only evidence
**Source:** `cold_storage_wallclock_soak.cpp:1-34, 108-121`; `12-soak-evidence/README.md`
**Apply to:** harness knobs + all committed captures
Env NAMES documented, VALUES never committed; integers-only parsing (`EnvOr`); fixture roots under constant `test-data/...` relatives.

### Label parity + cold-storage gating
**Source:** `test/src/crdt/CMakeLists.txt:436-472, 575-592`; `test/tier1_audit_check.cmake`
**Apply to:** the CMake registration
Every `addtest(cold_*` gets a `set_tests_properties(... LABELS "Tier1")` line; blockstore-linking targets sit inside `if(SGNS_COLD_STORAGE)`; big wall-clock legs never carry Tier1. Run `tier1_static_audit` as the wiring test.

### Both-homes amendment rule
**Source:** `notes/16-txpruner-gc-composition-rulings.md` header ("code comments at the two destructive homes + this full analysis")
**Apply to:** the conditional walk-bounds re-tune
Amendment lands at the constant's home (`graphsync_dagsyncer.hpp:58-82`) AND in `notes/17-seal-growth-decision.md`.

## No Analog Found

| File/Component | Role | Data Flow | Reason |
|----------------|------|-----------|--------|
| Evidence JSON emitter (inside `cold_seal_growth_test.cpp` or the evidence dir tooling) | utility (serialization) | file-I/O | No JSON exists anywhere in the workstream evidence tree (12-soak-evidence is text/MD only — research A27). Use the research's sanctioned fallback: a ~30-line hand-rolled flat emitter (numbers + fingerprint strings), avoiding the nlohmann linkage question. If an existing test target already links nlohmann/json, reuse is a simplification — verify before assuming (research A5). |
| Knobbed DAG-spectrum generator (depth × fan-out × mix) | utility (fixture generation) | batch | No existing env-knobbed DAG-shape generator in-tree. Closest partial: the W3 fixture's manual link-construction shape (`node_startup_test.cpp:1108-1130` — `IPLDNodeImpl::createFromString` + `addLink` + `addDestination`). Compose the generator from that primitive; the knob semantics (D-05) are new code by design. |

## Metadata

**Analog search scope:** `SuperGenius/test/src/crdt/`, `SuperGenius/test/src/blockchain/`, `SuperGenius/test/` (CMake + audit), `SuperGenius/src/crdt/`, `SuperGenius/src/transaction/`, `SuperGenius/src/storage/rocksdb/`, `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/impl/`, `.planning/workstreams/rocksdb-backup/{notes,STATE.md,milestones/v1.1-phases/}`
**Files scanned:** 11 analogs opened first-hand (wallclock soak, prune-gate kit, gc-test spy, node-startup W3, crdt CMakeLists, tier1 audit via research+grep, dagsyncer.hpp, PruneEligibility.cpp, datastore_rocksdb.cpp, rocksdb.hpp, rulings doc + soak-evidence README + STATE.md)
**Anchor line:** SuperGenius `741980f5dc461aa964edb93f7f52a85a79c2ee51` — verified current this session; all excerpts match the research anchor record with zero drift
**Pattern extraction date:** 2026-11-18
