---
phase: 15-evidence-aware-cold-serving-forced-walk-recovery
reviewed: 2026-11-17T00:00:00Z
depth: standard
files_reviewed: 26
files_reviewed_list:
  - SuperGenius/src/account/proto/SGTransaction.proto
  - SuperGenius/src/crdt/cold_read_fallback.hpp
  - SuperGenius/src/crdt/crdt_datastore.hpp
  - SuperGenius/src/crdt/globaldb/CMakeLists.txt
  - SuperGenius/src/crdt/globaldb/ColdReadService.cpp
  - SuperGenius/src/crdt/globaldb/ColdReadService.hpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStackStub.cpp
  - SuperGenius/src/crdt/globaldb/globaldb.cpp
  - SuperGenius/src/crdt/globaldb/globaldb.hpp
  - SuperGenius/src/crdt/graphsync_dagsyncer.hpp
  - SuperGenius/src/crdt/impl/crdt_datastore.cpp
  - SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp
  - SuperGenius/src/transaction/PruneEligibility.cpp
  - SuperGenius/src/transaction/PruneEligibility.hpp
  - SuperGenius/src/transaction/TransactionManager.cpp
  - SuperGenius/src/transaction/TransactionManager.hpp
  - SuperGenius/src/transaction/TxPruner.cpp
  - SuperGenius/test/src/account/prune_eligibility_test.cpp
  - SuperGenius/test/src/blockchain/CMakeLists.txt
  - SuperGenius/test/src/blockchain/node_startup_test.cpp
  - SuperGenius/test/src/crdt/CMakeLists.txt
  - SuperGenius/test/src/crdt/cold_evidence_matrix_test.cpp
  - SuperGenius/test/src/crdt/cold_prune_gate_test.cpp
  - SuperGenius/test/src/crdt/globaldb_erase_test.cpp
findings:
  critical: 1
  warning: 2
  info: 3
  total: 6
status: issues_found
---

# Phase 15: Code Review Report

**Reviewed:** 2026-11-17
**Depth:** standard
**Files Reviewed:** 26 (10 production, 16 test/build)
**Status:** issues_found

## Summary

Scope: the full `095c8c502..af644481f` diff of the SuperGenius submodule — the evidence-aware cold-serving chain (PrunedBlockRecord proto, PruneEvidenceClass predicate, consult-before-cold-Get fork, refusal taxonomy, re-warm gate), the forced-walk D-05 matrix with walk_gaps abort, the D-06 bounded getNode overload, and the 15-01/15-02/15-03 test deliverables (evidence matrix, node walk legs, erase-gate atomicity, cold-enabled failover).

High-level assessment: the implementation is unusually disciplined and matches the three plan SUMMARYs closely. Every claim I could mechanically verify held up: the consult sits before the cold Get and covers all three classifying surfaces (`FetchNodeFromColdStorage` at `graphsync_dagsyncer.cpp:868` serves both `getNode` and `GetNodeWithoutRequest`; the re-warm worker consults at `ColdReadService.cpp:439`; the responder-side `TraverseCIDsLinks` resolves children through `GetNodeWithoutRequest` at `graphsync_dagsyncer.cpp:1175`); the budget check at `graphsync_dagsyncer.cpp:483` caps attempted peers at exactly 8 with the unbounded sentinel unreachable; the D-05 matrix, gap-abort frontier clearing, and counter routing are all as specified; the walk mutex discipline (pop under lock, fetch unlocked, fold under lock) is correct; the lambda install at `globaldb.cpp:870` precedes the re-warm thread start at `:918` (no torn `std::function` read); the proto is append-only; the erase vector-widening preserves the single-batch atomicity (pinned by the interrupt-step tests). The test suites assert production surfaces, not mocks, and the enumeration claims (16 serve cells, 5 walk legs, 32 total) match the instantiations.

However, the adversarial pass found one genuine defeat of the phase's headline security property under concurrency (CR-01): the serve-side consult-to-Rehydrate window is not serialized against a concurrent TxPruner erase, so a marker that commits mid-serve is outrun and erased bytes are resurrected hot — and the hot path never re-consults evidence, so the resurrection persists until eviction. Two robustness warnings and three info items round out the report. None of the test files exhibited reliability defects (missing assertions, flaky shapes) beyond the standard negative-assertion sleep idiom.

## Critical Issues

### CR-01: Serve-side TOCTOU — a TxPruner erase committing between the evidence consult and Rehydrate resurrects erased bytes hot, persistently

**File:** `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp:868-895` (consult → Get → Rehydrate); `SuperGenius/src/crdt/globaldb/ColdReadService.cpp:496-510` (Rehydrate body); contrast `SuperGenius/src/crdt/globaldb/globaldb.cpp:1532` (erase-side compose lock)
**Issue:** `FetchNodeFromColdStorage` classifies evidence once (line 868), then performs the cold Get (line 883) and `Rehydrate` (~line 890) with no lock and no re-consult. `GlobalDB::EraseEntry` serializes its guards/staging/commit under the compose lock, but the serve path takes no compose lock, so the following interleaving is reachable:

1. Serve thread (getNode / GetNodeWithoutRequest / re-warm worker): consult answers `NoEvidence` (no marker yet).
2. Erase thread: `EraseEntry` compose lock → guards pass (the CID is sealed, not cached — the serve path has not cached it, `GrabCIDBlock` already missed — not a head, not pending) → one batch commits: hot value + block bytes removed, `/prune/tx` and `/prune/blk` markers written.
3. Serve thread: cold Get returns the (still cold-resident, Durable) bytes → `Rehydrate` writes them hot → node serves the erased block.

The marker is now present while hot bytes exist — and `GetNodeWithRouteBudget`'s hot legs (`GrabCIDBlock` at :380, `GetNodeFromMerkleDAG` at :389) return without ever consulting evidence, so the resurrected block keeps serving until the next eviction/GC. This directly violates the phase's core invariant ("Pruned is TERMINAL: no cold Get, no Rehydrate — erased bytes are never resurrected") and the request's threat-model charter ("any path where … evidence could [fail to prevent] resurrect[ing] erased bytes"). The window is not merely theoretical: the cold Get can take seconds on the S3 tier, TxPruner cycles run periodically, and the erased CID being concurrently served is the normal steady-state for a light node answering peer requests.

Scope notes (verified): the **walk** path is protected by construction — `ProcessForcedWalkCID` calls `InitCIDBlock` before the fetch (`crdt_datastore.cpp:526-529`), whose contentless LRU entry makes `EraseEntry` guard (3) (`IsCIDInCache`, `globaldb.cpp:1583`) defer the erase. The plain getNode/GetNodeWithoutRequest/re-warm paths have no such guard. Element-level raw-map entries erased by `EraseEntry` stay erased, and the walk's replay guard remains terminal, so the blast radius is block-byte serving rather than full element resurrection — but block bytes are exactly what this phase exists to gate.

**Fix:** Close the window on the serve side. Minimal, freeze-safe option — mirror the walk's discipline and re-verify after the slow leg:

```cpp
// FetchNodeFromColdStorage, after the cold Get returns non-empty bytes:
if ( !bytes.empty() )
{
    // CR-01 fix: re-classify AFTER the (slow) cold Get — an erase that
    // committed inside the consult->Get window must still refuse.
    switch ( cold_read_hook_->LookupPruneEvidence( cid ) )
    {
        case PruneEvidenceClass::Pruned:
            return outcome::failure( Error::HISTORY_PRUNED_LOCALLY );
        case PruneEvidenceClass::Malformed:
            return outcome::failure( Error::PRUNE_EVIDENCE_CORRUPT );
        case PruneEvidenceClass::NoEvidence:
            break;
    }
    cold_read_hook_->Rehydrate( cid, bytes ); // never executes for a refused CID
    ...
}
```

and/or init the LRU entry at the top of the NoEvidence serve path (`InitCIDBlock`-shaped) so `EraseEntry` guard (3) defers the erase until the serve completes — the existing deferral design then serializes the two paths. Apply the same re-consult to the re-warm worker's Get→Rehydrate window (`ColdReadService.cpp:452-465`). Add a deterministic repro test by pausing the cold Get (fault-injected delay on the S3 fake) while a `SetEraseInterruptHookForTest`-style hook commits the erase mid-window.

## Warnings

### WR-01: GlobalDB evidence lambda fails OPEN when `CID::toString()` fails — contradicts the phase's own Pitfall 7 fail-closed discipline

**File:** `SuperGenius/src/crdt/globaldb/globaldb.cpp:874-876`
**Issue:** The lambda degrades a `toString()` failure to an empty string (`cid_string_result.has_value() ? … : std::string()`), builds the key `"/prune/blk/"` (prefix only), which `GetRaw` answers NOT_FOUND → `NoEvidence` → the cold chain serves. Every other unreadable-evidence condition in the same lambda (GetRaw error → Malformed, parse failure → Malformed, zero-length → Malformed) fails closed per Pitfall 7; a CID that cannot be stringified is equally "unreadable evidence" and should never classify as absent. The marker was written under the CID's correct string form (the erase path resolves `path_and_cid.second` as a string), so a consult-time stringification failure silently misses the refusal row. The path requires a degenerate/corrupted in-memory CID, so practical reachability is low — but the phase's charter is exactly that malformed evidence never serves.
**Fix:** Treat a `toString()` failure as Malformed:

```cpp
const auto cid_string_result = cid.toString();
if ( cid_string_result.has_error() )
{
    m_logger->warn( "prune evidence key build failed for CID (toString error {}) - failing closed",
                    cid_string_result.error().message() );
    return PruneEvidenceClass::Malformed;
}
```

### WR-02: Per-CID failover budget is consumed by peers whose request never initiates (synchronous RequestNode failures burn the bound)

**File:** `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp:483-507`
**Issue:** `++attempted_peers` (line 493) executes before `RequestNode` (line 496); when the subscription fails synchronously (dial refused outright), the handler blacklists the peer and `continue`s without refunding the budget — despite the header contract stating a peer "counts as ATTEMPTED once its request … and RequestNode initiates". With `kForcedWalkPeerFailoverPerCid = 8`, eight dead-address routes (e.g., stale gossip routes) exhaust the budget before a live ninth route is tried, converting a recoverable fetch into a walk-gap abort. The direction is fail-closed (the bound is never exceeded — no security impact), but it degrades the RECOVER-02 restore availability the phase adds and makes the budget semantically "distinct route candidates contacted" rather than "requests attempted".
**Fix:** Refund on synchronous initiation failure — move the increment after the subscription check, or decrement in the error arm:

```cpp
ClearRequestStatus( cid );
auto subscription = RequestNode( peerID, address, cid );
if ( subscription.has_error() )
{
    // The request never initiated - it must not consume the per-CID budget.
    --attempted_peers; // (or relocate ++attempted_peers below this check)
    logger_->warn( ... );
    (void) BlackListPeer( peerID );
    continue;
}
++attempted_peers;
```

## Info

### IN-01: Two parallel decoders of the `/prune/blk` row — `PruneEligibility::LookupPrunedBlockEntry` has no production caller

**File:** `SuperGenius/src/transaction/PruneEligibility.cpp:295-331`; `SuperGenius/src/crdt/globaldb/globaldb.cpp:870-910`
**Issue:** The production consult is the GlobalDB lambda; `LookupPrunedBlockEntry` (the documented D-C1 home) is consumed only by tests. The key-prefix mirror is documented and test-pinned, but the *decode* logic (empty check + `ParseFromArray` + verdict mapping) is duplicated in two TUs with only test coverage cross-pinning them. A future edit to one decoder (e.g., record-shape change) can silently diverge the other.
**Fix:** Extract the shared classification (empty/parse → Malformed, present → Pruned) into one inline helper both TUs include, or record the second decode home beside `kPruneBlockMarkerPrefix` so the next editor finds both.

### IN-02: `EraseTransactionEntryPruned` default `generation = 0` records `has_erased_at_generation = true` with a synthetic value

**File:** `SuperGenius/src/transaction/TransactionManager.hpp:1100-1102`; `SuperGenius/src/transaction/PruneEligibility.cpp:338-358`
**Issue:** `BuildPruneBlockMarkerEntry` unconditionally sets `has_erased_at_generation(true)`; a caller using the defaulted `generation = 0` persists a record that claims a generation tag that was never threaded from `TxPruner::RunCycle`. No production caller currently uses the default (TxPruner is the sole caller and passes the real generation), so the hazard is latent.
**Fix:** Either drop the default (force callers to be explicit) or set `has_erased_at_generation` only when the caller actually supplied one (e.g., `std::optional<uint64_t>`).

### IN-03: Dead arm in the walk-gap abort log

**File:** `SuperGenius/src/crdt/impl/crdt_datastore.cpp:562-566`
**Issue:** `graphsync_syncer != nullptr ? GraphsyncDAGSyncer::kForcedWalkPeerFailoverPerCid : 0` — the `: 0` arm is unreachable: reaching the bounded fetch on the `!retained && sealed` path requires `evidence == NoEvidence`, which requires `graphsync_syncer != nullptr` (a null syncer leaves `evidence` nullopt and returns early at the skip). Harmless dead code, but it implies a budget-less gap path that does not exist.
**Fix:** Log the constant directly (the surrounding matrix guarantees the syncer is non-null on this branch).

---

## Verification Notes (evidence for the clean bill on everything else)

- **Consult coverage:** one switch at `graphsync_dagsyncer.cpp:868` gates `getNode` (cold leg via `FetchNodeFromColdStorage` at :411), `GetNodeWithoutRequest` (:845), the responder traversal (:1175), and the re-warm worker (`ColdReadService.cpp:439` consult precedes its Get at :452). Terminality check at :421-427 prevents peer-leg fall-through for both refusals before `GetRouteKeys`.
- **Budget bound:** `attempted_peers == peer_failover_budget` → break (:483-492); the 1-arg virtual delegates with `uint32_t` max (:345-353), which the counter can never reach — general callers are unaffected. Walk-side gap routing keys off `progress.walk_gaps` (counter, not error-value), clearing `forcedWalkFrontier_` under the re-acquired walk mutex (`crdt_datastore.cpp:384-405`).
- **Mutex/atomic discipline:** `ProcessForcedWalkStep` pops under `forcedWalkMutex_`, runs the (up-to-20s) fetch unlocked, folds counters under re-acquired lock with `forcedWalkStepActive_` re-entrancy guard — no fetch under the walk mutex, no counter tearing. `prune_evidence_lookup_` is installed (`globaldb.cpp:870`) strictly before `StartColdReadService` (`:918`) and before the hook reaches the syncer — thread-creation happens-before makes the unsynchronized read safe; tests likewise install before `Start()`.
- **D-01 atomicity:** the widened vector staging loop (`globaldb.cpp:1634-1640`) puts both markers into the same WriteBatch between the raw-map removal and the single commit, inside the compose lock; interrupt steps 1/2/3 prove all-or-nothing across both namespaces (`cold_prune_gate_test.cpp`, `ColdPruneEraseInterruptTest`).
- **Proto:** `PrunedBlockRecord` is append-only with fresh field numbers 1-3 — wire-compatible.
- **Test reliability:** W1's filter registration (the 15-02 deviation-4 fix) is present (`node_startup_test.cpp:916`); the negative re-warm assertions use the bounded `kRewarmBudget + 250ms` sleep idiom after a polled positive control — the standard, non-flaky shape for negatives; no assertion-free legs or skipped parameterizations found; the 16+5+11 leg enumeration matches the SUMMARY claims.
- **`CanRestoreElement` byte-identity / `HasBlock` non-intersection (D-04):** confirmed — no hunk touches `HasBlock` or `CanRestoreElement`; `HasBlock` retains its four-term bool contract (proven by the flip-test's stable-TRUE assertion).

_Reviewed: 2026-11-17_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
