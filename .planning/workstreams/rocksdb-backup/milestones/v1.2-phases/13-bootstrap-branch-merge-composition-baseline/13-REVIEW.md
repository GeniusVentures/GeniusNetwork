---
phase: "13"
reviewed_files: 21
total_findings: 2
critical: 0
major: 0
minor: 1
info: 1
---

# Phase 13 Code Review

**Scope:** Retrospective, advisory review of the phase-13 production surface — SuperGenius `4ae8a9a4e` (baseline test fix) and merge commit `2af184fa1` (parents `4ae8a9a4e` + `d556f86de`).
**Production delta reviewed:** `git diff 4ae8a9a4e 2af184fa1 -- src/` (19 files, +942/−66), plus the rewritten resurrection test and the example config.
**Required reading verified:** 13-01..13-04-SUMMARY.md, 13-SECURITY.md (accepted risks AR-13-01/AR-13-02 not re-litigated).

## Summary

The composition is clean at the source level. The single hand-composed `ShutdownForDestruction()` hunk is race-free (shutdown flag CAS'd before the `lifecycle_mutex_` barrier; every timer/handle arm and cancel path is serialized by the same recursive mutex; callbacks hold only weak refs). The merged bootstrap machinery — `RequestTrustBootstrapHeads`'s epoch-guarded retry chain, `RequestBootstrapWalk`'s status-driven retry policy, and the `CrdtDatastore` forced-walk engine — was traced for lock ordering (`dagWorkerMutex_` → `forcedWalkMutex_`, `forcedWalkMutex_` → `routing_mutex_`, all strictly one-directional with CV notifies outside the forced-walk mutex), worker re-entry (`forcedWalkStepActive_`), cross-thread safety of `CrdtHeads::GetList` / `ActiveCRDTDataStore()` / the static `ConsensusManager::RegisterSlotKeyHandler`, and the `TransactionManager::New` nullptr contract (both call sites check). The forced walk respects prune boundaries (`!retained && sealed` → skip), merges through the CRDT-idempotent `set_->Merge` without rewriting heads or seals, and is bounded by per-database retry caps. No critical or major defects found; two minor/info observations survive the six phases of subsequent green CI as acceptable-but-worth-recording trade-offs. The closed threat register and the D-15 binary composition gates as recorded in the summaries are consistent with what the merged source shows.

## Findings

### F-1: Unbounded `routing_` accumulation for already-stored CIDs
- Severity: minor
- File: `SuperGenius/src/crdt/globaldb/pubsub_broadcaster_ext.cpp:643-647` (with `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp:361`, `:1566-1573`)
- Issue: `AddMultiCIDInfo` now hoists `dagSyncer_->AddRoute( cid, peer_id, addr_vector )` above the have-block `continue` (previously, already-present blocks skipped the trailing `AddRoute`). This is the deliberate enabler for forced-walk recovery — retained heads need source peers — but it creates a route-lifecycle gap: `EraseRoute` is only invoked from `addNode` (`graphsync_dagsyncer.cpp:361`), which is never called for blocks already present. Consequently, every distinct already-stored CID announced by a peer (join, reconnect, head re-broadcast) permanently adds a `routing_` map entry (CID key + peer-key vector) that nothing evicts; `MoveRoutePeerToFront` only reorders. On a long-running node this is unbounded growth proportional to the distinct announced-and-stored CID set — a slow resource-lifetime leak rather than a correctness bug (route refresh for present blocks is otherwise harmless; lookups are mutex-guarded).
- Suggestion: Give present-block routes a bounded lifecycle — e.g., a periodic sweep evicting routes whose CID is both stored and sealed and whose peer list has not been used within N trust-sync intervals, or an LRU cap on `routing_` size with forced-walk-active CIDs pinned. Alternatively, record this as an accepted risk in the threat register with an operator-visible metric on `routing_.size()`.

### F-2: `bootstrap_walk_max_retries: 0` cannot express "disable retries"
- Severity: info
- File: `SuperGenius/src/account/GeniusNode.cpp:456-469` (`read_walk_limit` lambda in `LoadSgnsConfig`)
- Issue: The config reader rejects `value == 0` and falls back to the default (8). An operator who explicitly sets `bootstrap_walk_max_retries: 0` intending to disable incomplete-walk retries instead gets 8 retries. The fallback is fail-safe and warned ("must be a positive integer... using 8"), so impact is negligible — eight extra bounded walks — but the intent "0 = no retries" is not expressible.
- Suggestion: Either accept `0` for `bootstrap_walk_max_retries` specifically (treat as retry-disabled) or document in the example `sgns_config.json` / operator docs that the minimum configurable value is 1 and disablement is achieved by leaving `force_bootstrap_walk` false.

---

## Verified-Clean Notes (evidence for the empty upper severities)

- **Composed `ShutdownForDestruction` hunk** (`GeniusNode.cpp:2819-2834`): `shutdown_started_` is CAS'd before the barrier; `RequestBootstrapWalk`/`RequestTrustBootstrapHeads` re-check it under `lifecycle_mutex_`; the timer/handle cancel in the barrier is therefore race-free, and `ScheduleBootstrapWalkCheck` is only reachable after the flag check under the same mutex.
- **Epoch-guarded retry chain** (`GeniusNode.cpp:806-812`, `:1563-1610`): `++transition_epoch_` + handle cancel under lock; scheduled retries carry their epoch and fail closed on epoch mismatch, shutdown, or `account_service_switching_`; the scheduler→`io_` post keeps lifecycle locking off PubSub's context.
- **Lock discipline**: wait-predicate path `dagWorkerMutex_` → `forcedWalkMutex_` (`crdt_datastore.cpp:150-158`) has no reverse-order taker; `QueueForcedWalkLinks` takes `forcedWalkMutex_` → `routing_mutex_` with no inverse; all `dagWorkerCv_` notifies occur outside `forcedWalkMutex_`; `forcedWalkStepActive_` prevents concurrent steps across workers.
- **Cross-thread safety**: `CrdtHeads::GetList` holds `shared_lock(mutex_)` (`crdt_heads.cpp:259-283`); `GlobalDB::ActiveCRDTDataStore()` is mutex-guarded with shutdown check (`globaldb.cpp:659-668`); `ConsensusManager::RegisterSlotKeyHandler` static map is guarded by `slot_key_handlers_mutex_` (`Consensus.cpp:593-594`).
- **`TransactionManager::New` nullptr contract**: both production call sites null-check — `GeniusNode.cpp:1262-1267` and the migration fix (`Migration3_6_0To3_7_0.cpp:293-297`); `InitializeUTXOs` failure calls `Stop()` before returning nullptr.
- **Forced-walk correctness**: prune boundary preserved (`!retained && sealed` → `skipped_pruned`, `crdt_datastore.cpp:472-478`); recovery merges only genuinely-missing elements/tombstones via CRDT-idempotent `set_->Merge` with no head/seal rewrite; a filter-stripped-empty delta is a safe no-op (`crdt_set.cpp:914-922`); retry accounting is bounded (Incomplete+visited>0 capped at `bootstrap_walk_max_retries_`; `limit_reached` halts pending operator action; Incomplete+visited==0 is unreachable given queue-time invariants).
- **`AddListenTopic` reorder** (`globaldb.cpp:1297-1304`): enroll-before-subscribe ordering is correct for immediately-firing subscription callbacks.
- **Test rewrite `4ae8a9a4e`**: asserts the keep-seal retention contract with a bounded `PollUntil` window and a zero-S3-traffic invariant across 25 re-deliveries — strictly more robust than the replaced fetch-occurred expectation; no reliability concerns.
- **Example config** (`example/node_test/sgns_config.json`): documents the three new keys with recovery disabled — matches the opt-in default contract.

## Reviewed Files

Production (`git diff 4ae8a9a4e 2af184fa1 -- src/`): `src/account/GeniusNode.cpp`, `src/account/GeniusNode.hpp`, `src/crdt/crdt_data_filter.hpp`, `src/crdt/crdt_datastore.hpp`, `src/crdt/dagsyncer.hpp`, `src/crdt/globaldb/globaldb.cpp`, `src/crdt/globaldb/globaldb.hpp`, `src/crdt/globaldb/pubsub_broadcaster_ext.cpp`, `src/crdt/graphsync_dagsyncer.hpp`, `src/crdt/impl/crdt_data_filter.cpp`, `src/crdt/impl/crdt_datastore.cpp`, `src/crdt/impl/graphsync_dagsyncer.cpp`, `src/migration/Migration3_6_0To3_7_0.cpp`, `src/transaction/PruneEligibility.cpp`, `src/transaction/PruneEligibility.hpp`, `src/transaction/TransactionConsensusHandler.cpp`, `src/transaction/TransactionConsensusHandler.hpp`, `src/transaction/TransactionManager.cpp`, `src/transaction/TransactionManager.hpp`; baseline commit `4ae8a9a4e`: `test/src/crdt/cold_storage_resurrection_test.cpp`; merge delta: `example/node_test/sgns_config.json`.

---

_Reviewed: 2026-11-24_
_Reviewer: gsd-code-reviewer (retrospective, advisory)_
_Depth: deep (per-file + cross-file call/lock tracing)_
