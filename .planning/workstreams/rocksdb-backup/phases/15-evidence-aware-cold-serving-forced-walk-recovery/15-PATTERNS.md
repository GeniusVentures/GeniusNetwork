# Phase 15: Evidence-Aware Cold Serving & Forced-Walk Recovery - Pattern Map

**Mapped:** 2026-11-17
**Files analyzed:** 14 (10 production modification sites, 4 test suites)
**Analogs found:** 14 / 14 (every file is an extension of a verified seam — this is a composition phase per RESEARCH: "every mechanism this phase needs already exists as a verified seam")

**Tracked-source gate:** all analog paths verified `git ls-files` non-empty inside the `SuperGenius` submodule at HEAD `095c8c502`. No mirror paths. All line numbers below were re-read this session on the current merged line.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `SuperGenius/src/crdt/cold_read_fallback.hpp` | hook (ungated seam interface) | request-response (tri-state point lookup) | same file: `ColdReadStatus` struct + `HasDisposed()` virtual | exact |
| `SuperGenius/src/crdt/globaldb/ColdReadService.hpp` / `.cpp` | service (gated implementor) | request-response | same files: existing `@copydoc` override block | exact |
| `SuperGenius/src/crdt/globaldb/globaldb.hpp` / `.cpp` | store (facade: erase compose + DI wiring) | CRUD (atomic batch) + DI | same files: `EraseEntry` staging :1540-1590, wiring seam :824-852 | exact |
| `SuperGenius/src/crdt/graphsync_dagsyncer.hpp` | controller (error taxonomy + named constants) | request-response | same file: Error enum append block :50-66, `CID_FAILURE_SUPPRESSION` :226 | exact |
| `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` | controller (read path + responder) | request-response | same file: `FetchNodeFromColdStorage` :780-856, `ApplyColdPrecedence` :41-67, error-string switch :70-98 | exact |
| `SuperGenius/src/crdt/crdt_datastore.hpp` | model (walk status counters) | event-driven | same file: `ForcedWalkStatus` :79-88 | exact |
| `SuperGenius/src/crdt/impl/crdt_datastore.cpp` | controller (walk engine) | event-driven (graph traversal) | same file: conflation branch :452-458, counter log :299-322 | exact |
| `SuperGenius/src/transaction/PruneEligibility.hpp` / `.cpp` | utility (evidence key/value/lookup) | CRUD (KV point lookup) | same files: `LookupPrunedEntry` :179-246, `BuildPruneMarkerKey` :172-176, `BuildPruneMarkerEntry` :248-269 | exact |
| `SuperGenius/src/transaction/TransactionManager.cpp` | service (erase caller) | CRUD | same file: `EraseTransactionEntryWithMarker` :4718-4768 | exact |
| `SuperGenius/src/account/proto/SGTransaction.proto` | model (serialization) | transform | same file: `PrunedTransactionRecord` :70-76 | exact |
| `SuperGenius/test/src/crdt/cold_evidence_matrix_test.cpp` (NEW — name is planner discretion) | test (Tier-1 hermetic matrix) | fixture composition {hot}×{cold}×{evidence} | `cold_prune_gate_test.cpp` kit :244-460 + `ColdPruneJournalSeedTest` :1112-1185 | exact |
| `SuperGenius/test/src/crdt/globaldb_erase_test.cpp` (extend) | test (failover evidence) | request-response (peer failover) | same file: `GlobalDBEraseRefusalFailoverTest` :1044-1230 | exact |
| `SuperGenius/test/src/crdt/cold_prune_gate_test.cpp` (extend — erase-gate matrix legs) | test | CRUD (erase gate) | same file: `Gate_*` / `Composition_*` tests :862-1700 | exact |
| `SuperGenius/test/src/blockchain/node_startup_test.cpp` (extend or sibling suite — walk-abort legs) | test | event-driven walk | same file: `ForcedBootstrapWalkRunsBeforeBlockchainIsReady` :543, `...RetriesLateValidatorAfterReady` :573 | role-match |

**No Analog Found:** one discretion item only — see the section at the end (stub `ColdReadFallback` fake). Everything else composes a verified in-file sibling.

## Pattern Assignments

### `SuperGenius/src/crdt/cold_read_fallback.hpp` (hook interface, request-response)

**Analog:** the same file — `ColdReadStatus` seam-side enum mirror and the freeze-safe point-lookup virtuals. The new `PruneEvidenceClass` enum + `LookupPruneEvidence( const CID & )` virtual copy this file's two load-bearing rules: (1) no library/domain type crosses the gated/ungated boundary (header file comment, lines 5-16); (2) null-hook keeps disabled builds byte-identical.

**Seam-side enum mirror pattern** (`ColdReadStatus`, :30-44 — the shape `PruneEvidenceClass` mirrors; note it references NO transaction-layer type):

```cpp
struct ColdReadStatus
{
    enum class Class
    {
        NotFound,               ///< authoritative absence only (SC1)
        TemporarilyUnavailable, ///< transport/outage/timeout - never NotFound (D-03)
        Corrupt,                ///< bytes failed CID verification; tier attributed (SC3)
        Unauthorized,           ///< authentication/permission failure (SC3)
    };

    Class cls{ Class::NotFound }; ///< the failure classification (meaningful on failure)
    bool   fromRemoteTier{ false }; ///< tier that produced the failure (false=Local, true=Remote)
};
```

**Point-lookup virtual pattern** (`HasDisposed`, :117-135 region — bool contract sibling; `LookupPruneEvidence` is its tri-state counterpart):

```cpp
virtual bool HasDisposed( const CID &cid ) = 0;
```

Placement rule: the new virtual joins the interface AFTER `Rehydrate` with a Doxygen block citing the Phase 15 decision (D-04 source-consistency / SC3), mirroring how every existing virtual cites its phase+decision (`D-11, v1.1 Phase 11`, `D-04/SC4`, ...).

---

### `SuperGenius/src/crdt/globaldb/ColdReadService.hpp` / `.cpp` (service, request-response)

**Analog:** the same class — the ONLY `ColdReadFallback` implementor (`class ColdReadService final : public ColdReadFallback`, ColdReadService.hpp:48). The new override adds a `std::function`-shaped member (GlobalDB-installed) and follows the existing override block verbatim:

**Override block pattern** (ColdReadService.hpp, the `@copydoc` run):

```cpp
/** @copydoc ColdReadFallback::Get() */
ColdReadStatus Get( const CID &cid, sgns::common::Buffer &out ) override;

/** @copydoc ColdReadFallback::HasLocalCold() */
bool HasLocalCold( const CID &cid ) override;

/** @copydoc ColdReadFallback::HasDisposed() */
bool HasDisposed( const CID &cid ) override;
```

Discipline to copy from the header comment (lines 1-27): thread discipline per store handle; the class never grows GlobalDB types into its signature — the GlobalDB dependency arrives as an injected callable at construction (dependency direction GlobalDB→service, per RESEARCH Pattern 1).

---

### `SuperGenius/src/crdt/globaldb/globaldb.hpp` / `.cpp` (store facade, CRUD + DI)

**Analog 1 — the D-01 widening point.** Current signature (globaldb.hpp:517-519, quoted verbatim):

```cpp
outcome::result<void> EraseEntry( const std::string                              &key,
                                  const CID                                      &cid,
                                  const std::optional<std::pair<Buffer, Buffer>> &extra_entry = std::nullopt );
```

becomes `const std::optional<std::vector<std::pair<Buffer, Buffer>>> &extra_entries = std::nullopt`. Copy the doc-comment discipline: the existing `@param[in] extra_entry` block documents the opacity contract ("The buffers are OPAQUE: GlobalDB stays generic and never inspects or builds key shapes") — the widened param keeps that wording, extended to the vector. Pitfall 6: widen the slot ONLY — guards, compose lock, and post-commit seal re-assert stay untouched (Phase 16 lands COMP-01 on the same function).

**Analog 2 — the staging loop.** globaldb.cpp:1560-1569 (compose section, quoted verbatim):

```cpp
// The caller-built extra entry (D-C1: the /prune/tx/<hash> marker)
// joins the SAME batch after the raw-map removal, before the single
// commit -- value XOR marker is established atomically. The buffers
// are opaque; key shapes stay with the caller (Phase-16 D-01).
if ( extra_entry.has_value() )
{
    BOOST_OUTCOME_TRY( batch->put( extra_entry->first, extra_entry->second ) );
}
BOOST_OUTCOME_TRY( batch->commit() );
```

The vector widening turns the single `put` into a loop over `*extra_entries` at the SAME position: after `batch->remove( Buffer{}.put( key ) )` and interrupt step 3, before the single `commit()`.

**Analog 3 — the predicate injection seam.** globaldb.cpp:824-852 (quoted core):

```cpp
auto        stack = OpenColdStorageStack( cold_storage_options_, database_path_absolute, ipfsDataStore );
...
cold_read_hook      = stack.value().cold_read_hook;
cold_read_service_  = std::move( stack.value().cold_read_service );
// READ-02 (plan 09-02): the re-warm worker starts at
// construction time beside the service so every serve miss
// finds the executor live (own thread - Phase-8 D-10).
StartColdReadService();
```

The GlobalDB-installed evidence callable lands between the `cold_read_service_` assignment (:841-842) and the DAGSyncer construction (:864) — the exact window RESEARCH pins. Copy the comment style: cite the phase + decision id in the comment.

---

### `SuperGenius/src/crdt/graphsync_dagsyncer.hpp` (controller taxonomy, request-response)

**Analog 1 — append-only Error enum** (:50-66, tail quoted verbatim):

```cpp
// READ-01/SC3 (v1.1 Phase 9): the honest cold-storage failure
// classes - appended AFTER HOST_IS_NULL (uint8_t-sequential;
// existing values are never reordered so serialized/compared
// values stay stable). ...
COLD_STORAGE_TEMPORARILY_UNAVAILABLE, ///< Cold tier transport/outage/timeout (D-03)
COLD_STORAGE_CORRUPT,                 ///< Cold-tier bytes failed CID verification (SC3)
COLD_STORAGE_UNAUTHORIZED,            ///< Cold-tier authentication/permission failure (SC3)
};
```

The refusal value (name is discretion: `HISTORY_PRUNED_LOCALLY`-class) appends AFTER `COLD_STORAGE_UNAUTHORIZED` with the same comment block citing SERVE-04/D-07. Never reorder (uint8_t-sequential).

**Analog 2 — named internal constant** (`CID_FAILURE_SUPPRESSION`, :226, verbatim):

```cpp
// Per-(peer, CID) re-request suppression. Must stay below CrdtDatastore's
// failed-root retry cadence (5s base doubling to a 60s cap), or local
// retries against a sole route no-op: at 30s the first two retries (t+5s,
// t+15s) deterministically skip the only route and burn their budget.
static constexpr std::chrono::seconds CID_FAILURE_SUPPRESSION{ 4 };
```

`kForcedWalkPeerFailoverPerCid = 8` (D-06) copies this shape exactly: `static constexpr`, private, rationale-comment recording the derivation (three converging 8-bounds: `MAX_FAILED_ROOT_RETRIES` crdt_datastore.hpp:730, `bootstrap_walk_max_retries_` GeniusNode.hpp:1225, observed RefusalFailover ≤8 from 19-07-SUMMARY), and the Phase 17 probe re-tune note. No config knob.

---

### `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` (controller read path, request-response)

**Analog 1 — THE consult site (SC1/SC2 fork).** `FetchNodeFromColdStorage` :780-856; the `!bytes.empty()` success branch (:807-816, quoted verbatim) is where the predicate consult inserts BEFORE `Rehydrate`:

```cpp
const ColdReadStatus status = cold_read_hook_->Get( cid, bytes );
if ( !bytes.empty() )
{
    // D-04: re-cache through the dedicated rehydrate path BEFORE
    // returning (bytes only - SC4; the decorator set() journals +
    // writes hot, local disk only).
    cold_read_hook_->Rehydrate( cid, bytes );
```

Order is load-bearing: consult between the `Get` success and this `Rehydrate` (never rehydrate-then-check). Note this function ALREADY carries the `out_cold_classified`/`out_cold_status` aggregation outputs — the refusal path should follow the same early-return shape as the existing `MapColdReadStatus` failure return at the function tail.

**Analog 2 — classification mapping.** `ApplyColdPrecedence` :41-67 (free fn in anonymous namespace) shows the precedence-switch idiom the refusal classification mirrors; the new error value also needs a case in the `OUTCOME_CPP_DEFINE_CATEGORY_3` string switch :70-98 — copy the one-line-per-case shape:

```cpp
case sgns::crdt::GraphsyncDAGSyncer::Error::COLD_STORAGE_UNAUTHORIZED:
    return "Cold storage rejected the request (authentication/permission failure)";
```

**Analog 3 — responder refusal (SERVE-04).** `ColdServeDagService::getNode` :108-124 (quoted core) — refusal stays the honest don't-have on the wire; the distinct semantics live ONLY in the syncer-layer error:

```cpp
auto node = inner_->getNode( cid );
if ( node.has_error() && hook_ != nullptr )
{
    // ... the failure returns UNCHANGED so the
    // responder completes the request negatively NOW (RS_NOT_FOUND,
    // the honest don't-have). ...
    (void)hook_->EnqueueRewarm( cid );
}
return node;
```

**Analog 4 — failover accounting (reuse, never re-derive).** `RecordCIDFailure` :1398-1406 + `HasRecentCIDFailure` :1411-1434 (CID-scoped `(peer-multihash, CID)` key map under `cid_failures_mutex_`, suppression-window expiry). The per-CID failover budget composes with this existing machinery.

---

### `SuperGenius/src/crdt/crdt_datastore.hpp` (model, event-driven)

**Analog:** `ForcedWalkStatus` :79-88 (quoted verbatim) — the walk-gap counter joins as a sibling field:

```cpp
struct ForcedWalkStatus
{
    ForcedWalkState state            = ForcedWalkState::Idle;
    size_t          visited          = 0;
    size_t          fetched          = 0;
    size_t          restored         = 0;
    size_t          skipped_pruned   = 0;
    size_t          skipped_existing = 0;
    size_t          deferred         = 0;
    size_t          errors           = 0;
    bool            limit_reached    = false;
};
```

Pitfall 5: the walk-gap counter is a NEW distinct field (e.g. `walk_gaps`), never a reuse of `deferred` (deferred entries retry; a true gap never resolves). The abort predicate in `FinishForcedWalkLocked` (:299-322, see below) must treat `walk_gaps != 0` as Incomplete-abort, distinct from the existing `errors != 0 || deferred != 0`Incomplete condition.

---

### `SuperGenius/src/crdt/impl/crdt_datastore.cpp` (controller walk engine, event-driven)

**Analog — the D-05 replacement site.** `ProcessForcedWalkCID` conflation branch :452-458 (quoted verbatim — this is the code the evidence matrix replaces):

```cpp
if ( !retained && sealed )
{
    ++progress.skipped_pruned;
    logger_->debug( "Forced walk CID {}: missing sealed block, preserving prune boundary", cid_string );
    return outcome::success();
}
```

The matrix keeps the branch position and counter idiom: (a) `/prune/blk` evidence → the existing `++progress.skipped_pruned` + return-success shape verbatim; (b) no evidence → fall through to the EXISTING fetch discipline two statements below (`retained ? GetStoredNode : getNode`, :471) — no new fetch machinery (Don't-Hand-Roll table); (c) 4th quadrant exhaustion → `++progress.walk_gaps` + distinct error return, mirroring the `NODE_DESERIALIZATION` failure-return shape already in this function.

**Counter log sibling.** `FinishForcedWalkLocked` :299-322 — the log line gains the new counter in the same format string, and the Incomplete predicate gains the walk-gap term:

```cpp
forcedWalkStatus_.state = forcedWalkStatus_.errors != 0 || forcedWalkStatus_.deferred != 0
                              ? ForcedWalkState::Incomplete
                              : ForcedWalkState::Completed;
logger_->info( "Forced walk {}: visited={}, fetched={}, restored={}, skipped_pruned={}, "
               "skipped_existing={}, deferred={}, errors={}, limit_reached={}", ... );
```

---

### `SuperGenius/src/transaction/PruneEligibility.hpp` / `.cpp` (utility, CRUD lookup)

**This is the strongest analog cluster in the phase** — `/prune/blk` is a sibling namespace of `/prune/tx` with identical discipline.

**Analog 1 — prefix constant + key builder.** `PRUNE_MARKER_PREFIX` (hpp, ~:393-395) and `BuildPruneMarkerKey` (cpp :172-176, verbatim):

```cpp
std::string PruneEligibility::BuildPruneMarkerKey( const std::string &tx_hash )
{
    // Node-local prefix discipline (CRDTWorkJournal shape): the hash keys
    // the entry, the tx PATH travels inside the record value.
    return std::string( PRUNE_MARKER_PREFIX ) + tx_hash;
}
```

`PRUNE_BLOCK_MARKER_PREFIX = "/prune/blk/"` + `BuildPruneBlockMarkerKey( cid_string )` mirror these exactly (D-C1: PruneEligibility is the ONE key home — callers never rebuild).

**Analog 2 — the tri-state lookup with fail-closed malformed.** `LookupPrunedEntry` :179-246 (core legs verbatim):

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

`LookupPrunedBlockEntry` copies: `GetRaw` point lookup → `NOT_FOUND` mapping → `ParseFromArray` → `std::errc::bad_message` on malformed (T-17-0502 / Pitfall 7). Drop the tx-path-suffix and value-presence legs (block markers are CID-keyed; no WR-04 suffix check applies) but KEEP the invariant-violation loudness philosophy if an equivalent invariant emerges.

**Analog 3 — the marker value builder.** `BuildPruneMarkerEntry` :248-269 (verbatim core):

```cpp
SGTransaction::PrunedTransactionRecord record;
record.set_tx_path( resolved_tx_path );

base::Buffer key_buffer;
key_buffer.put( BuildPruneMarkerKey( tx_hash ) );
base::Buffer value_buffer;
value_buffer.put( record.SerializeAsString() );
return { std::move( key_buffer ), std::move( value_buffer ) };
```

`BuildPruneBlockMarkerEntry( cid_string, tx_hash, generation )` mirrors: build the proto record (D-02 back-reference: erasing `/prune/tx` hash + erased-at generation from `PruneCycleStats`), serialize, return the buffer pair for the caller to stage. The comment discipline ("the production twin of WritePrunedEntryForTest's body") should be replicated, plus a `WritePrunedBlockEntryForTest` sibling for TEST-01 seeding (mirrors `WritePrunedEntryForTest` at :271+).

**Analog 4 — terminal element guard (unchanged, composition point).** `CanRestoreElement` :156-170 — stays terminal authority at element level; the block-level `/prune/blk` skip bounds the walk; both layers per research §(d). Do NOT modify this function.

---

### `SuperGenius/src/transaction/TransactionManager.cpp` (service caller, CRUD)

**Analog:** `EraseTransactionEntryWithMarker` :4718-4768 — the marker-assembly site that passes the widened vector (core verbatim):

```cpp
std::optional<std::pair<crdt::GlobalDB::Buffer, crdt::GlobalDB::Buffer>> extra_entry;
if ( stage_pruned_marker )
{
    extra_entry = PruneEligibility::BuildPruneMarkerEntry( tx_hash, path );
}

// Atomic two-level erase + map-entry delete in one WriteBatch; the
// staged extra entry (the pruned driver's marker pair) joins the SAME
// batch, so value XOR marker holds atomically.
BOOST_OUTCOME_TRY( globaldb_m->EraseEntry( path, cid, extra_entry ) );
```

becomes a 2-element vector: `BuildPruneMarkerEntry( tx_hash, path )` + `BuildPruneBlockMarkerEntry( cid_string, tx_hash, generation )`. Keep the load-bearing comment about building markers AFTER `ResolveTransactionPathAndCID` from the SAME path the erase targets (WR-02, :4737-4750). The non-TxPruner caller `EraseTransactionEntry` (:4770-4775, `stage_pruned_marker=false`) stays a no-marker pass — mechanically compatible with the widened default.

---

### `SuperGenius/src/account/proto/SGTransaction.proto` (model, transform)

**Analog:** `PrunedTransactionRecord` :66-76 (verbatim):

```protobuf
// Node-local marker that a transaction's history was physically pruned
// (D-04). Key layout: "/prune/tx/" + tx hash on the node-local raw surface;
// the tx PATH travels in the value because lookups are by hash. Written only
// in the same WriteBatch as the Phase-18 erase (value XOR marker, atomic).
message PrunedTransactionRecord
{
    string tx_path = 1;
    string cid = 2;
    bool has_erased_at_height = 3;
    uint64 erased_at_height = 4;
}
```

`PrunedBlockRecord` sits BESIDE it with the same comment discipline (key layout stated in the comment; node-local, never a wire format — D-07/A1): back-reference fields = erasing `/prune/tx` hash + erased-at generation. Appending a new message is the established backward-compatible extension path; regeneration is handled by the normal proto build (`compile_proto_to_cpp`).

---

### `SuperGenius/test/src/crdt/cold_evidence_matrix_test.cpp` (NEW test, fixture matrix)

**Analog:** the Phase 14 kit in `cold_prune_gate_test.cpp` — the exact "real-GlobalDB raw-surface seeding" architecture RESEARCH recommends as PRIMARY.

**Fixture + teardown discipline** (:244-280) — clear EVERY process-global seam before teardown, in this order:

```cpp
~ColdPruneGateTest() override
{
    TeardownStack();
}
...
sgns::TxPruner::SetCycleInterruptHookForTest( nullptr );
crdt::GlobalDB::SetColdUploadStateHookForTest( nullptr );
crdt::GlobalDB::SetEraseInterruptHookForTest( nullptr );
```

Teardown order (blockchain → tm/account → `db_->ShutdownNow()` → `pubs_->Stop()`) is a verified invariant — copy `TeardownStack()` wholesale; new suites add their own hook clears to the same block (a `/prune/blk`-related seam, if added, joins here).

**Hermetic cold posture** (`BuildStackOnDir`, :380-440 core) — cold ON via test-only client override with a never-contacted endpoint; InMemory S3 fake; hygiene clear immediately after construction:

```cpp
cold.enabled   = true;
cold.endpoint  = "hermetic.invalid"; // overridden below - never contacted
...
fake_s3_    = std::make_shared<sgns::blockstore::InMemoryS3Client>();
fake_admin_ = std::make_shared<sgns::blockstore::InMemoryS3AdminClient>();
...
sgns::crdt::SetColdStorageStackClientsForTesting(
    std::static_pointer_cast<sgns::blockstore::S3Client>( fake_s3_ ),
    std::static_pointer_cast<sgns::blockstore::S3AdminClient>( fake_admin_ ) );
...
// Hygiene: the process-global override has served its purpose.
sgns::crdt::SetColdStorageStackClientsForTesting( nullptr, nullptr );
```

The faulted-fake variant (`SetFault( S3Op::Put, S3FaultKind::Unavailable )` + `SetAdminFault( Unreachable )`) is the held-journal determinism posture — the same knobs back the {cold} leg of the matrix (cold-present vs cold-empty).

**Matrix/product shape** — `ColdPruneJournalSeedTest` :1112-1115 + the PHASE A/B/C discipline (:1119-1185):

```cpp
class ColdPruneJournalSeedTest : public ColdPruneGateTest,
                                 public ::testing::WithParamInterface<std::string>
{
};
```

with PHASE A populate → PHASE B `TeardownStack()` + direct RocksDB seed (`SeedJournalRecord( hot_dir + "/coldstore", cid_str, seed )` — dir lock freed by teardown) → PHASE C `BuildStackOnDir(...)` reopen + drive. The evidence matrix {evidence: none/PRUNED/malformed} seeds `/prune/blk` rows the same way (via a `WritePrunedBlockEntryForTest`-shaped helper or direct `PutRaw` before/after teardown as the lock discipline requires), composed with hot put/erase and cold spill/seed for the product. Test naming follows the file's `SubjectBehavior` convention (`Gate_...`, `Composition_...` → e.g. `Evidence_...`, `Serve_...`, `Walk_...`). Red-first counter-tests (SC2 masquerading, both directions) follow the Phase 14 precedent of writing the failing assertion first.

**Tier placement:** Tier-1 lane registration + `ctest -L Tier1` contract per Phase 14 D-09; live legs (if any) follow `cold_prune_live_smoke_test.cpp`'s loud-skip pattern — dev-gated, never Tier-1.

---

### `SuperGenius/test/src/crdt/globaldb_erase_test.cpp` (extend, failover evidence)

**Analog:** `GlobalDBEraseRefusalFailoverTest` :1044-1230 — D-07's failover-evidence extension point.

**Fixture + syncer accessor** (:1044-1052, verbatim):

```cpp
class GlobalDBEraseRefusalFailoverTest : public GlobalDBEraseRedeliveryTest
{
protected:
    /// The concrete DAG syncer owning the route walk and the per-peer
    /// failure accounting; the broadcaster hands it out as void.
    static std::shared_ptr<sgns::crdt::GraphsyncDAGSyncer> syncerOf( sgns::crdt::GlobalDB &db )
    {
        return std::static_pointer_cast<sgns::crdt::GraphsyncDAGSyncer>( db.GetBroadcaster()->GetDagSyncer() );
    }
};
```

**Topology + two-part proof** — `PrunedPeerRefusalFailsOverToServingPeer` :1116+: `EraseNodeCollection` (multi-node addNode recipe at :90) with the hermetic Part 1 (requester joins NO topic; ordered `AddRoute` registers pruned-peer-first; ONE direct `syncer.getNode( cid )` walks the production route) + mesh Part 2 (grafted topic, cached-publish learning, bounded attempts) + Part 3 (`EXPECT_FALSE( syncer.IsOnBlackList( ... ) )` — CID-scoped, never connection-blacklisted). Extend with cold-enabled nodes carrying `/prune/blk` evidence; assert the SAME public consequences (failover completes, no blacklist, bounded attempts ≤ `kForcedWalkPeerFailoverPerCid`).

**Pitfall 3 discipline** (from the test's own comment, :1103-1115): broadcast-sequenced refusal tests are coin-flips — keep the hermetic ordered-`AddRoute` half deterministic and discard directly-fetched LRU blocks between phases (`DeleteCIDBlock`) or broadcast intake silently skips the CID.

---

### `SuperGenius/test/src/crdt/cold_prune_gate_test.cpp` (extend, erase-gate legs)

**Analog:** the in-file `Gate_*` tests (:862 `Gate_DurableAdmitsAndErases`, :953 `Gate_PendingDefersWholeGroupAsCounter`, :1044 `Gate_ColdDisabledNodeVacuousBranch`) and the induced-regression seam usage (:1347-1391):

```cpp
sgns::crdt::GlobalDB::SetColdUploadStateHookForTest(
    [ ... ]( const CID & ) -> std::optional<crdt::ColdUploadState> { ... } );
...
sgns::crdt::GlobalDB::SetColdUploadStateHookForTest( nullptr );
```

The erase-gate matrix legs (SC5's fourth column) extend these with `/prune/blk` assertions: after a gated erase, the block marker row EXISTS and the tx marker row EXISTS in the same commit (D-01 atomicity — the interrupt seams at steps 1/2/3 prove all-or-nothing across BOTH markers). New interrupt-seam extensions (discretion item) follow `TxPruner.cpp`'s `InterruptRequested( kInterruptAfterColdGate )` / `kInterruptBeforeErase` usage at :277/:293 — observation seam fires at the boundary under test, `true` = abort.

---

### `SuperGenius/test/src/blockchain/node_startup_test.cpp` (extend or sibling, walk-abort legs)

**Analog:** `ForcedBootstrapWalkRunsBeforeBlockchainIsReady` :543-567 — the poll-for-walk-state shape (verbatim core):

```cpp
ASSERT_NO_FATAL_FAILURE( test::assertWaitForCondition(
    [&]
    {
        const auto db = GeniusNodeTestAccess::TransactionDatabaseOf( fixture.node );
        return db && db->GetForcedWalkStatus().state == crdt::CrdtDatastore::ForcedWalkState::Completed;
    },
    std::chrono::milliseconds( kReadyPollTimeoutMs ),
    "opt-in forced walkthrough was not requested before genesis became available" ) );
```

Walk-abort legs (SC4) poll for `ForcedWalkState::Incomplete` + the new `walk_gaps` counter > 0 + the distinct walk-gap error surfaced — same `GeniusNodeTestAccess::TransactionDatabaseOf` + `GetForcedWalkStatus()` observability path, `NodeTeardownGuard` for cleanup. RECOVER-02 restore legs assert `restored` increments and the re-warmed block is hot+sealed via the existing `HasLocalBlock`/raw-seal-key probes used at :598-605.

---

## Shared Patterns

### Fail-closed malformed evidence (T-17-0502 discipline)
**Source:** `SuperGenius/src/transaction/PruneEligibility.cpp:189-196`
**Apply to:** `LookupPrunedBlockEntry`, the `ColdReadService` predicate leg, and every matrix {malformed} leg.

```cpp
if ( !record.ParseFromArray( marker.value().data(), static_cast<int>( marker.value().size() ) ) )
{
    // T-17-0502: a malformed marker is an ERROR, never a silent PRUNED.
    MarkerLogger()->error( "Pruned marker for tx {} is malformed", tx_hash );
    return outcome::failure( std::errc::bad_message );
}
```

### Error-enum append + string-switch case (SERVE-04)
**Source:** `SuperGenius/src/crdt/graphsync_dagsyncer.hpp:50-66` + `impl/graphsync_dagsyncer.cpp:70-98`
**Apply to:** the new refusal Error value — append after `COLD_STORAGE_UNAUTHORIZED` (uint8_t-sequential, never reorder), add the one-line case to `OUTCOME_CPP_DEFINE_CATEGORY_3`, decide `ApplyColdPrecedence` interaction (discretion: consult-site early return is the smaller change).

### Static test-hook seams + teardown clearing
**Source:** `globaldb.hpp:522-549` (`SetEraseInterruptHookForTest`, `SetColdUploadStateHookForTest`), `cold_prune_gate_test.cpp:272-274`
**Apply to:** any induced-evidence seam added this phase (discretion item). Shape: process-global `std::function` hook, invoked FIRST at the read/compose seam, `nullptr`-to-clear, cleared in fixture teardown BEFORE any store teardown, doc-comment "PRODUCTION CODE MUST NEVER CALL".

### Decision-citation comment convention
**Source:** every analog above (`D-03 (v1.1 Phase 9)...`, `v1.2 Phase 14, D-07`, `T-17-0502`, `WR-02`)
**Apply to:** ALL new code this phase — comments cite `v1.2 Phase 15` + the decision id (D-01..D-07) + the requirement id (SERVE-0x/RECOVER-0x). Coding style per `Coding Standards.md`: Ullman braces, PascalCase methods/types, `camelCase` locals, trailing-underscore members, Doxygen `@brief/@param/@note` on public interfaces.

### Named internal constant with recorded derivation (D-06)
**Source:** `graphsync_dagsyncer.hpp:222-227` (`CID_FAILURE_SUPPRESSION`)
**Apply to:** `kForcedWalkPeerFailoverPerCid = 8` — `static constexpr`, private, derivation in the comment (root ladder 8 @ `crdt_datastore.hpp:730`; walk retries 8 @ `GeniusNode.hpp:1225`; observed ≤8 @ 19-07-SUMMARY), Phase 17 re-tune note, NO config knob.

### Hermetic seed-reopen determinism (PHASE A/B/C)
**Source:** `cold_prune_gate_test.cpp:1119-1185`
**Apply to:** every matrix leg needing seeded raw-store state: populate (drainer held) → `TeardownStack()` → seed the RocksDB dir directly (lock free) → `BuildStackOnDir` reopen → drive + assert. Never construct the production S3 client against an unresolvable host.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| Stub `ColdReadFallback` fake (in-memory, returns table-driven `PruneEvidenceClass`) — SECONDARY test architecture, RESEARCH discretion recommendation | test double | request-response | `ColdReadService` is the ONLY implementor on the line today; no stub/fake `ColdReadFallback` exists anywhere in `SuperGenius/test/`. Planner: if chosen, model it on the interface's own doc contracts (null-safe, freeze-safe, no I/O) and the value-parameterized `ColdPruneJournalSeedTest` table shape; otherwise use the real-GlobalDB PRIMARY architecture which has a full analog. |

## Metadata

**Analog search scope:** `SuperGenius/src/crdt/`, `SuperGenius/src/transaction/`, `SuperGenius/src/account/proto/`, `SuperGenius/test/src/crdt/`, `SuperGenius/test/src/blockchain/` (greps + targeted reads; all anchors re-located at submodule HEAD `095c8c502`)
**Files scanned:** 16 source/test files read in targeted ranges
**Tracked-source verification:** `git ls-files` (run in `SuperGenius/`) — all 16 named analogs tracked
**Pattern extraction date:** 2026-11-17
