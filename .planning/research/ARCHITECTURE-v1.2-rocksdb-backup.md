# Architecture Research: v1.2 Cold-Storage Archive Tier & Pruning Integration

**Workstream:** rocksdb-backup (subsequent milestone, "SuperGenius Cold-Storage Archive Integration")
**Researched:** 2026-11-13
**Mode:** Project research — ARCHITECTURE (integration mapping against real code)
**Baseline examined:** SuperGenius `dev_coldstorage_additions` (working tree), `fix/trust-genesis-bootstrap` @ `d556f86de` (local branch), seed note `.planning/workstreams/rocksdb-backup/notes/develop-merge-erase-vs-cold-storage-gap.md` (2026-11-13 revision)

**Overall confidence: HIGH** — every integration point below was verified against the working tree or the branch blob; no claim rests on training data. Branch-side citations are marked `(branch)`.

---

## 0. The Existing Architecture in One View (anchor points)

```
GlobalDB::New  (globaldb.cpp:812-882)
 ├─ RocksdbDatastore (hot IpfsDatastore, same RocksDB as CRDT face)
 ├─ [cold enabled] BlockStoreBackedIpfsDatastore decorator (journal-first spill; seal/is_sealed
 │   are PURE FORWARDS — seals are TEXT keys "<cid>sealed" in the HOT store namespace)
 ├─ GraphsyncDAGSyncer(block_datastore=decorator, graphsync, host, cold_read_hook)
 │   └─ m_dagSyncer concrete handle exists FOR EraseEntry's StageBlockRemoval (globaldb.cpp:880-882)
 ├─ ColdStorageManager (drainer + flush-gated durability + retention GC threads)
 ├─ ColdReadService → injected as the ungated ColdReadFallback hook
 └─ AttachColdStorageGc(cold_manager_, m_crdtDatastore, dagSyncer, m_datastore)  (globaldb.cpp:899-901)

Read paths (graphsync_dagsyncer.cpp):
 getNode(cid)              :324  = GrabCIDBlock(LRU) → GetNodeFromMerkleDAG(hot)
                                  → FetchNodeFromColdStorage  :357  (D-01 COLD BEFORE PEERS)
                                  → peers (route failover) → ApplyColdPrecedence  :41 (D-03)
 GetNodeWithoutRequest(cid):725  = hot → LRU → cold chain (responder/GC walk reads)
 HasBlock(cid)             :686  = 4 terms: hot(:688) / LRU(:689) / HasLocalCold(:703, D-09)
                                  / HasDisposed(:717, D-11 DEDUP-ONLY, D-12 split)
 FetchNodeFromColdStorage  :750  = hook->Get (LocalBlockStore→S3, CID-verified) →
                                  hook->Rehydrate (BYTES ONLY through decorator set()) → hot re-read

Erase path (develop, merged):
 TxPruner::RunCycle (TxPruner.cpp:82) → per eligible tx
   → TransactionManager::EraseTransactionEntryPruned (TransactionManager.cpp:4769)
   → EraseTransactionEntryWithMarker (:4712): resolve path+CID, build /prune/tx/<hash> marker
   → GlobalDB::EraseEntry (globaldb.cpp:1374): ONE compose-locked WriteBatch =
       StageEraseElement (set/tombstone rows) + StageBlockRemoval (raw CID block)
       + raw map remove + /prune/ marker put; guards (head/sync-root/LRU/seal-exists);
       post-commit seal re-assert → POST_COMMIT_ERASE_ANOMALY on vanish

GC path (v1.1):
 ColdStorageManager::GcPassOnce (:860): heads snapshot → full walk → eligibility
   (journal state EXACTLY kEvictionDurabilityGate, :1072-1076) → mark (grace)
 ProcessDueMarks (:1209): heads re-check (D-14) → HALF 1 EvictLocalAndMarkDisposed
   (cold bytes + journal + disposed marker, library-atomic) → HALF 2 RunHotCleanup
   (:1317: hot batch deletes binary CID key + block's own set rows + DeleteCIDBlock
   LRU; seal DELIBERATELY RETAINED) → FinishOrphanedHotCleanups (crash half-2 completion)
```

Key roles: `NodeType::{Full=0, Light=1, Archive=2}` (`src/account/NodeType.hpp:31-35`). TxPruner is **Light-only** (GATE-01, `TxPruner.cpp:70-79`; wiring re-check `GeniusNode.cpp` ~4978). Cold storage is gated by the `blockstore` config section — **independent of NodeType**; a Light+cold node is constructible today.

---

## 1. Integration Point Map (per feature)

### (a) Durability-gated TxPruner eligibility

**Where the gate goes:** `TxPruner::RunCycle` step (3), the block-group work-list filter (`TxPruner.cpp:147-185`). Today a group enters the work list iff its block report is `erasable`. The cold gate adds: *when the node's GlobalDB has cold storage enabled*, a group is admitted only if `globaldb.GetColdUploadState(cid) == ColdUploadState::Durable` for the group's delta-block CID. Defer the whole group otherwise (group-or-defer discipline already exists, `TxPruner.cpp:167-173`).

**Why there and not in `PruneEligibility::Evaluate`:** the evaluator is contractually PURE over committed CRDT state — zero writes, zero service references, driven on committed state only (D-C6, `PruneEligibility.hpp` class doc). `RunCycle` already receives `crdt::GlobalDB&` (`TxPruner.cpp:82-86`) and is the designated mutation owner. The ungated per-CID bridge already exists and is lifecycle-safe: `GlobalDB::GetColdUploadState` (`globaldb.hpp:562`, impl `globaldb.cpp:1035` → `ColdStorageStack.hpp:222` null-safe bridge → `ColdStorageManager::GetUploadState` under `cold_store_mutex_`).

**Exact `kEvictionDurabilityGate` shape:** `ColdStorageManager.hpp:130-137` defines the compile-time constant `UploadState::UploadedDurable` — "no config knob can lower it (never accept-is-durable)". The GC's consuming precedent is `ColdStorageManager.cpp:1072-1076`: `!state.has_value() || state.value() != kEvictionDurabilityGate` → not eligible. The TxPruner gate mirrors this through the ungated enum (`ColdStorageStack.hpp:60-74`): **Durable permits; NoRecord / Pending / Accepted / Unreadable all defer.** The `Unreadable` case is exactly the MI-02 widening the enum already carries — "not eligible, loudly — never healthy-by-omission"; the gate should log it, not silently skip.

**Policy posture (opinionated):**
- Cold-enabled Light node → gate **mandatory, compile-time-shaped, not a knob** ("never erase what isn't in cold" — the node's own cold tier is its archive backstop; this is what makes role model (f) coherent).
- Cold-disabled Light node → develop behavior unchanged (erase without a cold gate; availability served by network archive nodes — BIP-159 posture). This keeps the disabled path byte-identical, the v1.1 discipline.
- Wiring surfaces a one-time INFO at `StartPruneTimerIfConfigured` (`GeniusNode.cpp` ~4966) when `pruning.enabled && blockstore.enabled` both hold, documenting the tiered-light posture.

**Reporting:** add a `PruneReason`-adjacent evidence code or a `PruneCycleStats` counter (e.g. `cold_deferred_groups`) rather than a new failure reason — the group is deferred, not ineligible-forever; the journal state can advance to Durable on a later drainer cycle and the next prune cycle re-evaluates. This preserves the named-evidence discipline (nothing silently dropped).

**Granularity note:** the gate is per delta-block CID (group-level), matching the erase's unit. Multiple txs in one block each call `EraseTransactionEntryPruned`; each `EraseEntry` stages `StageBlockRemoval` of the same CID (idempotent `remove`), so per-group gating before the first erase is correct and sufficient.

### (b) HasBlock / getNode 4th-term composition with PrunedLookup refusal

**Who answers first today (merged tree), for a TxPruner-erased CID on a Light+cold node:**

| Path | Term order | Answer for erased CID |
|---|---|---|
| `HasBlock` :686 | hot → LRU → `HasLocalCold` :703 → `HasDisposed` :717 | **TRUE** — term 3 hits while the local cold dir holds the journal's staged bytes; after GC disposal, term 4 hits (disposed marker, within cap). Correct for **dedup** (already-integrated re-delivery drops; the retained seal makes re-processed deltas inert). |
| `getNode` :324 / `GetNodeWithoutRequest` :725 | hot → LRU → cold chain `FetchNodeFromColdStorage` :750 | **Serves + Rehydrates** — the cold chain has NO prune-evidence consultation anywhere. On a Light node this *resurrects hot bytes the node chose to erase*. |
| Forced walk (branch) | block-level `!retained && sealed` skip → element-level `CanRestoreElement` | Block-level skip treats *any* missing sealed block as a prune boundary — conflates TxPruner-erased with GC-evicted (see (d)). |

**The gap:** evidence-based refusal exists only in the walk's element guard (`PruneEligibility::CanRestoreElement`, branch `PruneEligibility.cpp:156-170`: allowlist → hash → `LookupPrunedEntry` → refuse iff `PRUNED`; `VALUE_PRESENT_INVARIANT_VIOLATION` → hard error). The general read path never consults it. v1.2 must make the cold hook evidence-aware:

- **Where:** `FetchNodeFromColdStorage` (`graphsync_dagsyncer.cpp:750-806`) after a successful cold `Get`, before `Rehydrate`. The ungated TU must stay free of domain types — extend the `ColdReadFallback` interface (`src/crdt/cold_read_fallback.hpp`) with an evidence predicate (e.g. `virtual bool PruneEvidenceRefuses(const CID&)`) implemented by the gated `ColdReadService`… except the `/prune/` markers live in the HOT store (`GetRaw`), not the cold stack — so the natural owner is **GlobalDB**, which owns both the raw store and the marker namespace. Concrete shape: GlobalDB injects a small evidence-predicate (or role flag) into `ColdReadService` at the existing `OpenColdStorageStack` seam (`globaldb.cpp:819-846`).
- **Role-awareness:** Archive/Full nodes never have prune markers (GATE-01), so the predicate is vacuously false and serving is unchanged — **an archive node answers HasBlock=true and serves TxPruner-erased CIDs from hot or cold via re-warm without any special-casing, because the case cannot arise on them**. Only Light nodes (the only erasers) consult evidence.
- **Answer shape (SURV-02/03):** refusal must be distinguishable from not-found. `ApplyColdPrecedence` (`graphsync_dagsyncer.cpp:41-67`) already carries a classification surface — add a refusal class mapped to a distinct `GraphsyncDAGSyncer::Error` (peer-facing "history pruned on this node", the BIP-159 `NOPRUNE`-style distinction) rather than folding into `CID_NOT_FOUND`.
- **Block-level evidence (new, small):** prune markers are per-tx (`/prune/tx/<hash>`), but the refusal points above are per-CID. A block is erased only when *every* carried key was eligible (`EvaluateDeltaBlockErasable`, D-C3), so writing a node-local **`/prune/blk/<cid>` marker in the same erase batch** gives O(1) CID-keyed refusal. `EraseEntry`'s `extra_entry` parameter (`globaldb.hpp:489`, staged at `globaldb.cpp:1462-1466`) is deliberately opaque and already carries one pair — either widen it to a vector or have `EraseTransactionEntryWithMarker` stage the block marker when the block's last member erases (the TxPruner knows the group). Marker home: `PruneEligibility` (the D-C1 precedent — "callers never rebuild key shapes").

### (c) TxPruner hot cleanup × GC `RunHotCleanup` — unify or sequence?

**Overlap inventory (same physical rows/keys):**

| Artifact | TxPruner path | GC path |
|---|---|---|
| Raw binary CID key | `StageBlockRemoval` (`graphsync_dagsyncer.cpp:618-633`, staged in EraseEntry batch) | `RunHotCleanup` batch remove (`ColdStorageManager.cpp:1317-1345`) |
| CRDT set rows `/crdt/s\|t/<key>/<cid>` | `StageEraseElement` (elements **and** tombstones) | `RunHotCleanup` `row_keys` (block's own membership rows, from delta content) |
| LRU cache | **NOT invalidated** — guard 3 (`globaldb.cpp:1428-1432`) rejects LRU-cached CIDs *at compose start only* | Explicitly invalidated: `DeleteCIDBlock` after hot deletes (A6, `ColdStorageManager.cpp:1346-1348`) |
| Seal `<cid>sealed` | retained (post-commit re-assert, `globaldb.cpp:1471-1485`) | retained (GATE-03 comment, `ColdStorageManager.cpp:1327-1333`) |
| Cold tier | untouched | HALF 1 evicts local cold bytes + journal, writes disposed marker; **remote S3 object never deleted** |

**Recommendation: DO NOT unify — sequence + close the LRU window.** The two pruners have different guards, different evidence, and different recovery semantics (GC = retention *eviction* of unreachable blocks, cold-backed, resurrection-safe via disposed-marker dedup; TxPruner = local *history prune* of spent-finalized txs, value-XOR-marker, network data untouched). Both are idempotent on absent keys, so row-level interleaving is already safe. The real work items:

1. **Close the stale-LRU window in `EraseEntry`** (found during this research): guard 3 runs under the compose lock, but `GrabCIDBlock` inserts into the LRU from `getNode` *without* the compose lock — a concurrent fetch between guard-check and commit leaves a stale LRU entry serving erased bytes (HasBlock term 2 then answers true). Fix: post-commit `m_dagSyncer->DeleteCIDBlock(cid)` in `EraseEntry`, mirroring GC's A6 ordering.
2. **GC-disposal starves TxPruner (document, don't fix yet):** GC HALF 1 deletes the journal record (`EvictLocalAndMarkDisposed`). After that, `GetColdUploadState` reads `NoRecord` → the (a) gate defers the group *forever* — hot value rows stranded while the remote S3 copy still exists and the cold chain can still serve it (`FetchNodeFromColdStorage` reads LocalBlockStore→S3 directly, not the journal). Options: (i) accept + document (under-prune, safe direction — recommended for v1.2); (ii) gate accepts disposed-marker + verified remote presence (sync S3 GET per candidate — bounded but adds remote I/O to the prune cycle); (iii) library change: disposal preserves a terminal evidence state (e.g. `DisposedDurable`) instead of deleting the record — cleanest evidence model, touches the frozen-ish LocalBlockStore journal schema; defer to v2 alongside epoch-based deletion compaction.
3. **Reverse order is safe by construction:** if TxPruner erases hot rows of a CID GC has marked evicting — the erase doesn't move heads (guard 1 guarantees non-head), GC's delete-time heads re-check (D-14, `ColdStorageManager.cpp:1253-1261`) passes, HALF 1 proceeds on cold bytes, HALF 2 no-ops on absent hot keys. No coordination needed.

### (d) Forced walk × the cold hook — ordering guarantees for re-warm during recovery

**Where the walk's fetch hits the cold hook (branch code, will auto-merge):**
`CrdtDatastore::ProcessForcedWalkCID` (branch `crdt_datastore.cpp:440-470`):
```
retained = dagSyncer_->HasStoredBlock(cid)   // branch impl = HasRawBlockBytes (RAW HOT DATASTORE ONLY)
sealed   = dagSyncer_->isResolved(cid)       // the seal row
if (!retained && sealed) → skipped_pruned     // "preserve prune boundary", walk does NOT fetch
node = retained ? dagSyncer_->GetStoredNode(cid)   // branch impl = GetNodeFromMerkleDAG (HOT ONLY)
                : dagSyncer_->getNode(cid)          // FULL chain: LRU → hot → COLD → peers
```
Branch impls verified at branch `graphsync_dagsyncer.cpp:561-570` (`HasStoredBlock = HasRawBlockBytes`, `GetStoredNode = GetNodeFromMerkleDAG`). The branch does not touch `getNode`/`GetNodeWithoutRequest`/`HasBlock` bodies beyond adding these overrides → the merge keeps OUR cold-chained versions (consistent with the seed's "only `GeniusNode.cpp` conflicts; all CRDT seams auto-merge" forecast).

**The conflation bug to fix in v1.2:** `!retained && sealed` skips *any* missing sealed block. On a cold node a **GC-evicted** ancestor (cold bytes present, remote durable) is skipped as if pruned — exactly the history an archive node should restore from cold. The refinement: distinguish by evidence —
- `!retained && sealed && cold-present` (local cold dir, disposed marker, or a cold-chain probe) → **fetch via `getNode`** (cold chain serves before peers; offline-capable, CID-verified);
- `!retained && sealed && /prune/blk evidence` (from (b)) → **skip** (evidence refuses; the element-level `CanRestoreElement` guard at branch `GeniusNode.cpp:1618` already refuses pruned-element restore during replay — both layers needed: block-level skip bounds the walk, element-level guard is the authority).

**Ordering guarantees re-warm needs during recovery (verified against current code):**
1. **Fetch→rehydrate→serve is synchronous inside `getNode`**: `FetchNodeFromColdStorage` calls `hook->Rehydrate(cid, bytes)` inline (`graphsync_dagsyncer.cpp:770-780`) *before returning the node* — so by the time the walk parses links and queues children (`QueueForcedWalkLinks`, branch `crdt_datastore.cpp:390-420`), parent bytes are already hot.
2. **Rehydrate writes BYTES ONLY — no seal** (the 09-RESEARCH §2.4 ruling, documented on `ColdReadFallback::Rehydrate`): sealing an unprocessed crash-window block would make its delta permanently unmergeable. The walk's element-application path owns sealing after successful replay — this division must be preserved when the walk restores from cold.
3. **Re-warm re-journals**: `Rehydrate` goes through the Phase-8 decorator `set()` (journal + hot write) — every cold-restored block creates a fresh `PendingUpload` record; the drainer re-Puts with createOnly semantics and converges to `alreadyPresent` (verified drainer behavior, `ColdStorageManager.cpp` DrainOnce success-slot comment). Harmless but worth a test assertion during recovery-at-scale.
4. **One-CID-at-a-time on the DAG worker**: `forcedWalkStepActive_` (branch `crdt_datastore.cpp:336-435`) serializes steps; the inline cold fetch is bounded by existing worker tolerance (the D-01 design note for `getNode`). No new lock ordering vs `dagMutex_`: the cold chain runs outside `dagMutex_` by construction; `Rehydrate` takes only the decorator's `cold_store_mutex_` + hot write path.
5. **Lifecycle ordering already supports the walk**: the re-warm worker stops later in `ShutdownNow` than the drainer (`StopColdReadService` at `globaldb.cpp:611` vs drainer join in `StopColdStorageManager`), and the walk's rehydrate is inline anyway — no shutdown window where the walk fetches cold with dead stores.

### (e) Seal storage options

**Facts:** seals are `<cid>sealed` **text keys in the hot IpfsDatastore** — `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/impl/datastore_rocksdb.cpp:51/58/61` (`cid_string += "sealed"`); the spill decorator forwards `seal/is_sealed` untouched and documents why (`BlockStoreBackedIpfsDatastore.hpp` header: "seal markers are TEXT keys in the hot store's namespace"); nothing ever deletes them (GC retains, `ColdStorageManager.cpp:1327-1333`; erase re-asserts, `globaldb.cpp:1471`); GATE-03 bans the `"sealed"` literal in SuperGenius production src/ (access only via `markResolved`/`isResolved`, `graphsync_dagsyncer.cpp:1083-1092`). They are now load-bearing three ways: erase guard 4, the walk's ancestry index (`isResolved` per visited node), and the walk's prune-boundary signal — O(all processed CIDs), hot, forever.

**Options:**
1. **Accept + document + measure (recommended for v1.2).** RocksDB serves billions of small point-lookup keys; the real cost is compaction write-amp and cache pressure, and the reads are point lookups under `dagMutex_`. Deliverable: a growth assessment (count via one offline prefix scan tool or an estimate metric; cite block-ingest rate), an explicit invariant doc ("seals are permanent, hot, O(processed CIDs)"), and a decision record. Matches the seed's "assess compaction/spill options or accept + document".
2. **Separate column family** in ipfs-lite's `RocksdbDatastore`. Isolates compaction and enables per-CF tuning, but it is a *thirdparty* library change (fork maintenance) and the SuperGenius-side access stays behind `markResolved`/`isResolved` anyway. Defer unless measurements demand it.
3. **SuperGenius-owned sidecar namespace** (e.g. node-local `/crdt/seals/<cid>` via `GetRaw/PutRaw`). Moves ownership into a face GlobalDB controls, enables future policy/spill without thirdparty changes — but `markResolved/isResolved` are ipfs-lite interface methods called throughout the CRDT stack; a parallel marker creates two truths for one fact. Only viable as a full migration with a compatibility shim; high risk for low current pain. Reject for now.
4. **Spill seals into sgns-blockstore** — **rejected**: the frozen v1 BlockStore contract is CID→codec-preserved-block-bytes; seals are not DAG blocks; extending the library API for this breaks the contract's shape guarantees for zero durability benefit (a seal losing bytes is recoverable — it only degrades to "unresolved" fail-closed).

### (f) Role-downgrade (archive → light) data flow

**Config surfaces today are independent:** `node_type` (sgns_config.json → `NodeType`) and the `blockstore` cold section (crdt config, tri-state gate, INTG-01). Nothing binds cold storage to Archive/Full; GATE-01 binds only *pruning* to Light. So the downgrade is: restart same DBs + cold config with `node_type=light` and `pruning.enabled=true`.

**Data flow after downgrade (how the already-built pieces compose):**
```
archive era:  every block spilled → journal Durable (flush-gated) → remote S3 objects (permanent)
downgrade:    node_type=light → prune timer arms (GeniusNode.cpp:4966+; Light check ~4978)
cycle:        TxPruner::Evaluate (spend-recency window) → (a) durability gate sees ARCHIVE-ERA
              Durable records → hot erase permitted (value+block+raw map, ONE batch, /prune/ marker)
              → seals retained → local cold copies eventually GC-evicted (retention age, unreachable)
              → remote S3 objects REMAIN (no remote-deletion path exists in v1.1; epoch-based
                deletion compaction is explicitly v2+ deferred in STATE.md)
serving:      pruned-hot + cold-resident + no prune evidence → this node still SERVES from cold
              (its own backstop — feature (b) semantics); with /prune evidence → refuses (light
              semantics). Local evidence decides; cold is never authoritative on its own
              (the CanRestoreElement ruling, generalized).
```
**Collectibility policy (candidate #4) — opinionated:** cold writes are **permanent-once-written** for v1.2. Network-coordinated collection (prove ≥1 archive replica elsewhere before deleting your copy) needs proof machinery that does not exist anywhere in the stack — document the invariant, keep local-cold hygiene to the existing GC (which already reclaims the local tier while leaving remote objects), and defer coordinated collection to v2+ with the epoch-deletion work. The v1.2 deliverable is the *documented downgrade flow + an E2E test*: archive-era data remains obtainable through the cold chain after the role flip; TxPruner erases only Durable-backed hot rows; `/prune/` markers accumulate from zero; evidence refusal (b) activates only as markers appear.

---

## 2. Component Changes (new vs modified)

### Modified (production)

| Component | File | Change |
|---|---|---|
| TxPruner | `src/transaction/TxPruner.cpp/.hpp` | Durability gate in `RunCycle` block-group filter; `cold_deferred` stats counter; Light+cold posture log line |
| PruneEligibility | `src/transaction/PruneEligibility.hpp/.cpp` | (post-merge) block-level prune-marker home: `BuildPruneBlockMarkerEntry` (`/prune/blk/<cid>`, D-C1 discipline) + `LookupPrunedBlock` |
| TransactionManager | `src/transaction/TransactionManager.cpp` | `EraseTransactionEntryWithMarker` stages the block marker when the erase completes a block group (TxPruner supplies group knowledge) |
| GlobalDB / EraseEntry | `src/crdt/globaldb/globaldb.cpp/.hpp` | Post-commit `DeleteCIDBlock` LRU invalidation (closes the stale-LRU window); evidence predicate + role flag injected into the cold stack at `OpenColdStorageStack` |
| ColdReadFallback / ColdReadService | `src/crdt/cold_read_fallback.hpp`, `src/crdt/globaldb/ColdReadService.hpp/.cpp` | Evidence-aware serve refusal (`PruneEvidenceRefuses`-shape predicate consumed in `FetchNodeFromColdStorage`), new refusal classification (SURV-02/03 distinguishable) |
| GraphsyncDAGSyncer | `src/crdt/impl/graphsync_dagsyncer.cpp/.hpp` | Consume the refusal classification in `getNode`/`GetNodeWithoutRequest`/`ApplyColdPrecedence`; new Error value for "history pruned on this node"; responder (`ColdServeDagService`) applies the same refusal |
| CrdtDatastore (via merge) | `src/crdt/impl/crdt_datastore.cpp` | Walk skip-rule refinement: `!retained && sealed` splits into cold-restorable (fetch) vs prune-evidenced (skip) |
| GeniusNode | `src/account/GeniusNode.cpp` | **Merge conflicts (only forecast file)**; downgrade wiring notes; Light+cold WARN/INFO |

### New (non-production-code deliverables)

- `/prune/blk/<cid>` marker namespace (constants + builders — code, but data-layout only).
- Docs: cold-permanence/collectibility policy; seal growth assessment + decision record; tiered-node model writeup (archive vs tiered-light vs plain-light).
- Tests: merge-composition suite (walk × cold), durability-gate suite (Accepted/Pending/Unreadable deferrals), evidence-refusal suite (serve vs refuse vs not-found tri-state), TxPruner×GC interleave suite, downgrade E2E.

### Explicitly NOT changed

- sgns-blockstore library contract (frozen v1) — no seal spill, no `DisposedDurable` state this milestone (documented as v2 option only).
- GC's two-phase D-16 machinery, drainer, flush-gated durability — consumed as-is.
- `HasBlock`'s 4-term answer (dedup semantics are already correct for both marker kinds).

---

## 3. Data Flow Diagrams (text)

### 3.1 Read path after v1.2 (evidence-aware cold chain)

```
getNode(cid) / GetNodeWithoutRequest(cid)
  └─ hot → LRU ─ miss → FetchNodeFromColdStorage(cid)
                             └─ cold Get (LocalBlockStore → S3, CID-verified)
                                  ├─ hit ─→ [NEW] prune-evidence predicate (GlobalDB-injected)
                                  │            ├─ role ∈ {Full, Archive} → SERVE + Rehydrate(bytes-only)
                                  │            ├─ /prune/blk/<cid> present → REFUSE "history pruned"
                                  │            │   (distinct error; SURV-02/03; no Rehydrate)
                                  │            └─ no evidence → SERVE + Rehydrate (archive semantics:
                                  │                cold bytes + no evidence = restorable history)
                                  └─ miss/fault → peers (getNode only) / classified error (D-03)
```

### 3.2 Durability-gated erase cycle (Light+cold node)

```
TxPruner tick (io timer, generation snapshot) ── RunCycle
  ├─ TickGateSettled? (READY, no missing history, settle window)
  ├─ Evaluate() verbatim (pure; spend-recency window D-02)
  ├─ block reports (PRUNE-03) ── erasable groups
  ├─ [NEW] per group: GetColdUploadState(cid)
  │     ├─ Durable            → admit
  │     ├─ NoRecord/Pending/Accepted → defer whole group (next cycle re-checks)
  │     └─ Unreadable         → defer + LOUD log (MI-02: never healthy-by-omission)
  └─ per tx: re-verify consumed → EraseTransactionEntryPruned
        └─ GlobalDB::EraseEntry (compose lock; guards 1-4; ONE batch:
             set/tombstone rows + raw CID block + raw map + /prune/tx/<hash>
             [+ /prune/blk/<cid> on group completion]; seal untouched;
             post-commit seal re-assert [+ NEW post-commit DeleteCIDBlock])
```

### 3.3 TxPruner × GC composition (sequence, not unification)

```
                     ┌── GC thread (10-min passes) ─────────────────────────────┐
 cold-backed block ──┤ heads snapshot → full walk → unreachable + age + journal │
                     │ == UploadedDurable → MARK (grace) → heads re-check       │
                     │ → HALF1 EvictLocalAndMarkDisposed (cold bytes+journal+   │
                     │   disposed marker, atomic) → HALF2 RunHotCleanup         │
                     │   (hot CID key + set rows + DeleteCIDBlock; SEAL KEPT)   │
                     └──────────────────────────────────────────────────────────┘
                     ┌── TxPruner timer (10-min cycles) ────────────────────────┐
 spent-finalized tx ─┤ Evaluate → block gate → [NEW] durability gate            │
                     │ → EraseEntry batch (hot rows + block + /prune markers;   │
                     │   SEAL KEPT) → [NEW] post-commit LRU invalidate          │
                     └──────────────────────────────────────────────────────────┘
 interleavings:  GC-then-TxPruner on same CID → journal gone → gate defers forever
                 (ACCEPTED for v1.2: under-prune, safe; v2 option: DisposedDurable
                 journal state or remote-presence verification)
                 TxPruner-then-GC on same CID → GC no-ops on absent hot keys; safe
 both:           idempotent removes; seals retained by both; remote S3 permanent
```

### 3.4 Forced walk on a cold node (post-merge, post-refinement)

```
RequestBootstrapWalk (GeniusNode) → GlobalDB::RequestForcedWalk → CrdtDatastore queue
 per CID (one at a time, DAG worker):
   retained = HasStoredBlock (raw hot only) ; sealed = isResolved
   ├─ retained → GetStoredNode (hot only)
   ├─ !retained && sealed:
   │    ├─ [NEW] cold-present (local dir / disposed / probe) → getNode → cold chain
   │    │      → Rehydrate(bytes-only, re-journals PendingUpload) → replay elements
   │    │        → CanRestoreElement guard per element (refuses /prune/tx evidence)
   │    │        → seal after successful replay (walk owns sealing — NOT rehydrate)
   │    └─ [NEW] /prune/blk evidence → skip (prune boundary preserved, bounded walk)
   └─ !retained && !sealed → getNode (cold → peers; InitCIDBlock before,
          DeleteCIDBlock on failure — existing branch discipline)
   links → InheritRoutes(parent→child) → frontier (max_blocks bound, retry cadence)
```

### 3.5 Role downgrade timeline

```
t0 archive: spill everything → journal Durable → S3 objects (permanent)
t1 restart light (+pruning): prune timer arms; cold stack unchanged (still serving)
t2 cycles:  gate sees Durable (archive-era) → hot erase proceeds per window policy
            → /prune/ markers accumulate → evidence refusal activates per 3.1
t3 steady:  local cold copies GC-evicted by retention; remote objects remain forever
            (v1.2 invariant: cold writes are permanent-once-written)
```

---

## 4. Suggested Build Order (with rationale)

1. **Branch merge: `fix/trust-genesis-bootstrap` → current line.**
   Everything recovery-related (walk code, `CanRestoreElement`, `HasStoredBlock`/`GetStoredNode` overrides) must land before composition tests can exist. Conflict surface is forecast to be `GeniusNode.cpp` only (seed note; verified: the branch's `getNode`/`HasBlock`/`GetNodeWithoutRequest` bodies don't touch our cold-hook hunks, so the CRDT seams auto-merge keeping our 4-term `HasBlock` and cold-chained reads). Verify post-merge: `HasBlock` still 4-term; `GetNodeWithoutRequest` still cold-chained; GATE-03 still passes.

2. **Durability-gated TxPruner eligibility.**
   Depends only on the already-shipped `GetColdUploadState` bridge — no dependency on the merge. But sequencing it after the merge lets its tests run against the final evaluator shape (branch makes `IsAllowlistedTxKey` static, etc.). Establishes "never erase what isn't in cold" — the precondition that makes archive-serve semantics (3) honest on tiered-light nodes.

3. **Archive-serve from cold + evidence-based refusal.**
   Depends on 1 (walk present — its skip-rule refinement rides this work) and 2 (the tiered-light model: erased CIDs are exactly the Durable-backed ones whose cold copies remain). Delivers the `/prune/blk` marker (rides the erase batch), the refusal classification in the cold chain, the responder refusal, and the walk's cold-restorable-vs-pruned split.

4. **TxPruner × GC composition hardening.**
   Depends on 2 (the gate defines the disposal-starvation interplay being documented) and shares the marker infrastructure from 3. Scope: post-commit LRU invalidation in `EraseEntry` (the stale-LRU window found in this research), the interleave test matrix, the stranded-group documentation, optional cross-marker skip (TxPruner defers disposed-marker CIDs explicitly for cleaner evidence rather than relying on NoRecord).

5. **Seal capacity assessment.**
   Independent of 1-4 (measurement + decision record only). Schedule late so the assessment can cite real walk-recovery numbers from 3's tests; outcome is expected to be "accept + document" with CF-migration as a measured trigger.

6. **Role-downgrade flow + collectibility policy.**
   Depends on 2 + 3 semantics being settled (the downgrade test exercises exactly: gate over archive-era Durable records, evidence refusal activation, cold-chain availability). Mostly documentation + one E2E test; the policy deliverable (cold permanence) closes candidate #4.

Parallelism note: 5 can run anytime; 2 can start before 1 completes (different files) but its verification tests should land after 1. The order above is the dependency-safe serialization.

---

## 5. Sources

All sources are repository files (working tree `dev_coldstorage_additions` unless marked `(branch)` = `fix/trust-genesis-bootstrap` @ `d556f86de`, inspected via `git show`), plus the workstream seed note. Confidence HIGH throughout for code-shape claims; the *forecast* that only `GeniusNode.cpp` conflicts is MEDIUM (merge not yet executed).

- `.planning/PROJECT.md` (rocksdb-backup v1.0/v1.1 shipped scope)
- `.planning/workstreams/rocksdb-backup/notes/develop-merge-erase-vs-cold-storage-gap.md` (2026-11-13 seed: tiered-node model, candidate list, merge forecast)
- `SuperGenius/src/crdt/globaldb/globaldb.cpp` — :812-882 cold seam + DAGSyncer ctor; :899-901 GC attach; :1374-1487 EraseEntry; :1035 upload-state bridge
- `SuperGenius/src/crdt/globaldb/globaldb.hpp` — :489 EraseEntry contract; :562 GetColdUploadState; :687-712 cold members
- `SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp` — :130-137 kEvictionDurabilityGate; :344-382 GcPassOnce contract; :476/:494 ProcessDueMarks/RunHotCleanup
- `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp` — :860 GcPassOnce; :1072-1076 eligibility gate; :1209-1345 ProcessDueMarks/RunHotCleanup; :1360+ FinishOrphanedHotCleanups
- `SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp` — :60-74 ColdUploadState (incl. Unreadable/MI-02)
- `SuperGenius/src/crdt/globaldb/BlockStoreBackedIpfsDatastore.hpp` — seal forwards, remove() hot-only
- `SuperGenius/src/crdt/cold_read_fallback.hpp` — hook interface, D-12 split, Rehydrate bytes-only ruling
- `SuperGenius/src/crdt/globaldb/ColdReadService.hpp` — re-warm queue bounds, Stop lifecycle
- `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` — :324-614 getNode; :41 ApplyColdPrecedence; :686-723 HasBlock; :725-806 GetNodeWithoutRequest/FetchNodeFromColdStorage; :108-124 ColdServeDagService; :618-633 StageBlockRemoval; :1083-1092 seal accessors
- `SuperGenius/src/transaction/TxPruner.cpp` — :70-79 GATE-01; :82-240 RunCycle (gate insertion at :147-185)
- `SuperGenius/src/transaction/PruneEligibility.hpp/.cpp` — PruneReason/PrunedLookup/marker contract/evaluator purity (D-C6)
- `SuperGenius/src/transaction/TransactionManager.cpp` — :4712-4775 EraseTransactionEntryWithMarker
- `SuperGenius/src/account/GeniusNode.cpp` — :4966-5060 StartPruneTimerIfConfigured; :5160-5230 RunPruneCycle
- `SuperGenius/src/account/NodeType.hpp` — :31-35 roles
- `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/impl/datastore_rocksdb.cpp` — :51/58/61 `<cid>sealed` key
- (branch) `src/crdt/dagsyncer.hpp` :31-45; `src/crdt/impl/graphsync_dagsyncer.cpp` :561-570; `src/crdt/impl/crdt_datastore.cpp` :212-470 (RequestForcedWalk / ProcessForcedWalkStep / ProcessForcedWalkCID / QueueForcedWalkLinks); `src/transaction/PruneEligibility.cpp` :156-170 (CanRestoreElement); `src/account/GeniusNode.cpp` :1571-1630 (RequestBootstrapWalk, guard at :1618)
