# Feature Research

**Domain:** CRDT cold-storage integration + garbage collection for a Merkle-CRDT blockchain node (SuperGenius v1.1, rocksdb-backup workstream)
**Researched:** 2026-10-22
**Confidence:** MEDIUM (web findings cross-checked across ≥2 independent sources or first-party repos fetched directly; SuperGenius-internal claims are HIGH — read directly from code at the cited file:line)

---

## How SuperGenius's CRDT Actually Works Today (grounding for every category below)

All citations verified in-repo at research time:

| Mechanism | Where | Fact |
|---|---|---|
| Delta CRDT set (add-wins observed-remove, priority = node height) | `SuperGenius/src/crdt/crdt_datastore.hpp:49` ("based on https://github.com/ipfs/go-ds-crdt") | Same data model as go-ds-crdt / the Merkle-CRDT paper (arXiv 2004.00107) |
| Element version history | `SuperGenius/src/crdt/crdt_set.hpp:341` | `/set/s/<key>/<block>` — every add/put version, kept forever |
| Tombstones | `SuperGenius/src/crdt/crdt_set.hpp:342` | `/set/t/<key>/<block>` — `PutTombs` writes them (`crdt_set.cpp:762-791`); `Delta` proto carries `repeated Element tombstones = 2` (`crdt/proto/delta.proto:6`) |
| Current value + priority | `SuperGenius/src/crdt/crdt_set.hpp:343-345` | `/set/k/<key>/{v,p}` — resolution reads this, not the version history |
| Tombstone creation on delete | `SuperGenius/src/crdt/impl/crdt_set.cpp:171-174` (`CreateDeltaToRemove`) | `GlobalDB::Remove` produces a tombstone delta — soft delete only |
| **No CRDT GC exists** | grep over `SuperGenius/src/crdt/**` | Only "purge" hit is `PurgeOldBackups` (RocksDB *backup* keep-count, `globaldb/globaldb.cpp:420-423`). Explicit TODO `crdt_data_filter.cpp:178`: *"Figure out how to remove tombstones even recorded ones"*; its call site is commented out (`impl/crdt_datastore.cpp:976`) |
| Heads with heights, per topic | `SuperGenius/src/crdt/crdt_heads.hpp` (`Add`/`Replace`/`GetHeadHeight`/`GetList`, path `/namespace/topic/cid`) | Height bookkeeping already exists → epoch/level watermarks are computable |
| Block bytes live in the SAME RocksDB as CRDT metadata | `SuperGenius/src/crdt/globaldb/globaldb.cpp:322-329` | `IpfsRocksDb::create(m_datastore->getDB())` → `RocksdbDatastore` → handed to `GraphsyncDAGSyncer` (`globaldb.cpp:344`). **This is the exact seam where a `BlockStoreBackedIpfsDatastore` drops in** |
| IpfsDatastore interface to implement | `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/datastore.hpp` | `contains/set/get/remove` + vestigial `seal()`/"prune" + `is_sealed()` (never implemented in SuperGenius — a free future hook for pruning gates) |
| In-memory LRU ≠ persistence | `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp:820-862` | `InitCIDBlock`/`IsCIDInCache`/`DeleteCIDBlock` only touch `lru_cid_cache_`; persisted blocks go through `dagService_->addNode` (`crdt_datastore.cpp:1029`) |
| Processed-marker machinery | `SuperGenius/src/crdt/dagsyncer.hpp` (`HasBlock`, `markResolved`, `isResolved`) | The dedup/"already processed" state a GC must not silently destroy |
| Existing retention precedent | `SuperGenius/src/account/GeniusNode.cpp:540-551`, `GeniusNode.hpp:1179-1180` | `result_retention_hours_` (default 168h, 0=keep forever) + `result_retention_max_mb_` (0=no cap) from `sgns_config.json` |
| Existing GC engine precedent | `SuperGenius/src/account/GeniusNode.cpp:4675-4805` (`StartResultGC`/`RunResultGC`) | Dual-trigger (age OR over-cap) mtime-sorted oldest-first file eviction, `bitswap_->unpersistBlock(cid)`, timer at `max(1, retention/10)` hours + 30s initial pass, logged counts/bytes |
| Config-gated CRDT construction precedent | `SuperGenius/src/account/GeniusNode.cpp:553-601` (`LoadCrdtConfig`) | `crdt_config.json` → `GlobalDB::BackupOptions` (enabled, interval, keep_count, auto_restore) with sane re-defaulting |
| Shipped blockstore (v1.0) | `thirdparty/sgns-blockstore/include/sgns-blockstore/*.hpp` | Frozen v1 `BlockStore` (Put/Get/Has/GetSize/PutMany, `BlockStatus` taxonomy, `DurabilityLevel`), `LocalBlockStore` + journal + `EvictLocal`, `S3BlockStore`, one-shot `UploadDrainer` (single-threaded v1 contract), `BlockStoreTooling::GetPendingUploads` |
| **CID hash blocker** | `thirdparty/sgns-blockstore/include/sgns-blockstore/BlockStore.hpp:88-103` | v1 API accepts **sha-256 multihash only**; the repo's CRDT CBOR path (`sgns::common::getCidOf`) produces **blake2b-256** CIDs — "a documented v1 non-goal; widening … later is additive." **Spill-on-write of every CRDT block requires this widening first** |
| Crash-safe work-journal pattern | `SuperGenius/src/crdt/globaldb/crdt_work_journal.hpp` (Seen/Processing/Stalled + leases, RocksDB-persisted) | Reusable pattern for resumable GC passes |
| External source of truth | `SuperGenius/src/crdt/crdt_datastore.hpp:35-36` (forward-declares `ValidatorRegistry`); blockchain layer | SuperGenius has the consensus anchor the Merkle-CRDT paper says GC requires |

Architecture-doc invariants (verbatim constraints, `supergenius-sharded-ipld-cache-architecture.md` ~lines 340-378): local eviction is **not** a logical delete; a cache miss must not be interpreted as an absent CRDT op; **"tombstones cannot be purged merely because they are old"**; current heads must retain causal history; restoration must not resurrect tombstoned values; **"garbage collection requires a formally defined causal-stability and reachability policy"**; initial versions should avoid permanent deletion of archived history; disk-full/low-balance inhibit eviction.

---

## Feature Landscape

### Table Stakes (Users Expect These)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Config-gated construction from `crdt_config.json` | Every other subsystem (`sgns_config`, `crdt_config` backup, log_config) is config-gated; cold storage off by default | LOW | Follow `LoadCrdtConfig` (`GeniusNode.cpp:553-601`) verbatim: defaults struct → parse → re-default zeros; log effective config |
| Spill-on-write for every CRDT block | The milestone's core promise: no CRDT block may exist only in hot RocksDB | MEDIUM | Hook the `IpfsDatastore::set()` seam (globaldb.cpp:322-329); `LocalBlockStore::Put` (atomic batch + journal) then periodic drain. **Blocked on blake2b-256 CID widening in sgns-blockstore (BlockStore.hpp:88-103)** |
| Cold-store read fallback: miss → fetch → verify → serve → re-cache | IPFS nodes/gateways all verify fetched bytes against the CID before publishing them to the cache; the read path in the architecture doc specifies exactly this | MEDIUM | `BlockStoreBackedIpfsDatastore::get()`: local RocksDB → `S3BlockStore::Get` (re-verifying, shipped) → write-back to local. Graphsync serving gets the fallback for free because `GraphsyncDAGSyncer` reads through the same `IpfsDatastore` (`globaldb.cpp:344`) |
| Authoritative-miss vs transport-failure distinction | Architecture doc: "Only authoritative absence should be negative-cached … Transport failures must not become cached NotFound" | LOW (shipped in `BlockStatus`) | Preserve the taxonomy across the IpfsDatastore adapter: map S3 outage/timeout to distinct failures, never to "block absent" |
| Periodic background drain of pending uploads | s3d ships a background upload loop as the default mode of operation; a node can't rely on an operator running one-shot drains | MEDIUM | Wrap the shipped one-shot `DrainPendingUploads` in a `boost::asio::steady_timer` loop — reuse the `gc_timer_` pattern (`GeniusNode.cpp:4697`). Respect the v1 single-threaded drainer contract (serialize drains) |
| Bounded upload concurrency | s3d: `uploadThreads` default 4 | LOW | One drain in flight; optional per-remote-Put deadline via shipped `WriteOptions` |
| Shutdown behavior: drain-or-resume | Long-running nodes are killed; pending state must be safe either way | LOW-MEDIUM | Two valid patterns with precedent: (a) s3d `flush`-style blocking drain on shutdown; (b) journal-preserving stop-and-resume — the v1.0 upload journal is already crash-recoverable, so (b) is cheaper and equally safe. Order after `GlobalDB::ShutdownNow`/`CancelAndCloseNow` (`globaldb.cpp:131-147`) |
| Age-based retention for cold-eligible data | Existing precedent: `result_retention_hours` (168h default, 0=disable) — operators already have this mental model | MEDIUM | Timer cadence precedent: `max(1, retention/10)` hours + 30s initial pass (`GeniusNode.cpp:4684-4696`) |
| Size-based cap | Existing precedent: `result_retention_max_mb`; IPFS Kubo StorageMax watermark; s3d `diskUsageLimit` (10 GiB default) | MEDIUM | Dual trigger (age OR over-cap), oldest-first, like `RunResultGC` |
| Explicit disable + protected namespaces | 0=keep-forever semantics exist today; heads/genesis must never be evicted (architecture doc PIN rules) | LOW | Hard-coded PIN set (heads namespace, current-epoch pointers) immune to retention scan |
| GC visibility: counts/bytes/pending metrics | `RunResultGC` logs deleted count/bytes (`GeniusNode.cpp:4798-4802`); s3d exposes pipeline metrics via admin API | LOW | `BlockStoreTooling::GetPendingUploads` already enumerates the pending set; log per-pass reclaimed bytes + pending backlog |

### Differentiators (Competitive Advantage)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Disposed-CID local tombstones** (the recommended GC remnant) | After retention-based disposal, keep a tiny "this CID was disposed" record so graphsync answers authoritative NotFound instantly, peer re-broadcasts dedup correctly, and nothing refetches forever | MEDIUM | go-ds-crdt's PurgeDAG deletes processed-block markers and maintainers immediately flagged re-broadcast head resurrection (PR #341 review); keeping a bounded marker is the safer inverse. Implement as a dedicated RocksDB CF or bounded set with its own retention |
| Staggered peer-vs-cold-store race on read miss | Hides S3/s3d latency behind peer fetches (doc: query best peer at t=0, object store at t≈100ms, first verified result wins) | MEDIUM | Doc-recommended default; needs coalescing first |
| Request coalescing for concurrent same-CID misses | Prevents thundering-herd refetch; standard in IPFS gateways, explicitly listed in the doc's read path | MEDIUM | In-flight map CID→waiters in the adapter |
| Brief TTL negative cache (authoritative misses only) | Repeated gets for genuinely absent CIDs stop hitting S3 | LOW | Only after `NotFound` (authoritative); never after outage/timeout |
| Epoch/level watermark computation from heads | Uses existing `CrdtHeads` heights to derive a "stable floor" below which nothing is reachable from any head | MEDIUM | First concrete step of the causal-stability spec v1.0 deferred; floor = min(height) across all known topics' heads, persisted as a watermark record |
| Admin whole-namespace purge (PurgeDAG-style ops tool) | Decommission a subnet/topic cleanly; go-ds-crdt shipped exactly this shape (PR #341) with the hard lessons: quiesce workers first, delete heads LAST, resumable | HIGH | Off-by-default tool, not an automatic GC; requires namespace quiesce (`ShutdownNow`-like) |
| Backpressure: staging-disk cap inhibits spill | s3d `diskUsageLimit` analog; architecture doc: "disk-full and low-balance conditions must inhibit eviction" | MEDIUM | When local pending bytes > cap: shed (stop accepting new spills, keep hot-store writes) + alert; never silently drop |
| Shutdown flush command (s3d `flush` analog) | Operators can force-drain before backup/snapshot windows | LOW | Blocking `DrainPendingUploads` call exposed at node level |
| **Consensus-anchored epoch compaction + checkpoint bootstrap** (the "delete entirely" endgame) | The paper's requirement — "an external source of truth (i.e. a blockchain)" — is exactly what SuperGenius has; validators agree an epoch checkpoint, everything below the epoch's stable floor is hard-deleted network-wide, new/rejoining nodes bootstrap from the checkpoint instead of replaying genesis | HIGH | v2+; needs epoch snapshot format, checkpoint restore path, and refusing deltas below the epoch watermark (protocol version bump) |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Purge tombstones by age alone | "They're old, delete them" | **Explicitly forbidden** by the architecture doc ("tombstones cannot be purged merely because they are old"); a late/slow replica replaying an old delta would resurrect a deleted value; go-ds-crdt ships no tombstone GC at all for exactly this reason | Causal-stability-gated disposal (epoch watermark), or keep tombstones and only evict bytes |
| Apply the result-cache mtime GC pattern directly to CRDT blocks | `RunResultGC` already exists and looks reusable | CRDT blocks need **reachability + stability**, not age: a block below a head's causal history is still required (doc: "current heads must retain access to their required causal history") | Protected-namespace scan + stability watermark; never a blind directory walk |
| Add Delete/Remove to the frozen BlockStore contract | "GC needs to delete from S3 too" | Contract permanence: "no Remove/Delete/Erase member … will EVER exist on this interface" (BlockStore.hpp CORE-05/CORE-06 note); GC is a policy *above* the store | GC operates on CRDT metadata + local eviction; cold-store reclamation is a separate ops/admin surface, if ever |
| Delete-entirely with no disposal marker | Cleanest possible state | Peer re-broadcast of an old head → endless remote fetch loops / reprocessing; the PurgeDAG review's resurrection hazard, but continuous instead of admin-triggered | Disposed-CID local tombstone (bounded) — see comparison below |
| Interpret cache miss as "operation never happened" | Simplifies read modeling | Doc: "a cache miss must not be interpreted as an absent or unprocessed CRDT operation"; breaks convergence reasoning | Miss → cold fetch; disposal → authoritative NotFound via marker |
| Treat s3d "accepted" as durable, then evict | Frees hot bytes faster | v1.0 E2E documented finding: s3d gives **no per-object durability signal** (accepted ≠ durable on Sia); snapshot docs confirm buffered objects can be listed-but-unreadable | Evict only at the journal's conservative level; keep `Durable` transitions out until durability polling ships (already a v1.0 deferred item) |
| Run GC/drainer work on CRDT worker threads | Fewer threads | Blocks delta processing (`ProcessJobIteration` workers); drainer is single-threaded v1 contract; blocking the hot path stalls the whole DAG walk | Dedicated io_context timer strand, serialized with drains |
| Unbounded in-memory pending/scan sets | Simpler code | PurgeDAG review: buffering all keys in memory scales with key count (OOM risk flagged by maintainer) | Batched scans with bounded working sets; `CRDTWorkJournal`-style resume state |

## Feature Dependencies

```
[Spill-on-write for CRDT blocks]
    └──requires──> [sgns-blockstore CID widening: blake2b-256]   (BlockStore.hpp:88-103 v1 non-goal)
    └──requires──> [BlockStoreBackedIpfsDatastore adapter]  (IpfsDatastore seam, globaldb.cpp:322-329)
    └──requires──> [Config-gated construction]              (crdt_config.json)

[Cold-store read fallback]
    └──requires──> [BlockStoreBackedIpfsDatastore adapter]
    └──requires──> [Authoritative-miss vs transport-failure mapping]   (BlockStatus taxonomy)
    └──enhances──> [Graphsync serving]  (same IpfsDatastore instance, globaldb.cpp:344)

[Periodic drainer]
    └──requires──> [Spill-on-write]  (something must enqueue)
    └──requires──> [Shutdown drain-or-resume]  (lifecycle completeness)
    └──enhances──> [Backpressure: staging-disk cap]

[Retention GC (age+size, cold-eligible only)]
    └──requires──> [Spill-on-write]  (bytes must be cold before hot GC)
    └──requires──> [Protected namespaces / PIN set]
    └──requires──> [Disposed-CID tombstones]  (post-GC correctness)
    └──enhances──> [Authoritative NotFound on disposed CIDs]

[Epoch watermark (stability floor)]
    └──requires──> [CrdtHeads heights]  (already present, crdt_heads.hpp)
    └──enhances──> [Retention GC]  (reachability gate beyond age/size)

[Consensus-anchored epoch compaction + checkpoint bootstrap]  (v2+)
    └──requires──> [Epoch watermark]
    └──requires──> [Checkpoint snapshot + restore path]  (new bootstrap, not genesis replay)
    └──conflicts──> [Genesis-replay bootstrap for pre-epoch deltas]  (must refuse deltas below watermark)

[Admin namespace purge]
    └──requires──> [Namespace quiesce]  (stop rebroadcast/repair/walk workers — PurgeDAG lesson)
```

### Dependency Notes

- **Spill-on-write requires CID widening before anything else**: every CRDT delta block is CBOR-CID'd via `sgns::common::getCidOf` (blake2b-256), which the v1 sha-256-only `BlockStore` rejects by design. This is additive per the header's own note — but it is Phase-1 gating work.
- **GC and read-fallback both hang off the adapter**: one `BlockStoreBackedIpfsDatastore` implementation unlocks serving, local reads, and eviction; it is the highest-leverage single artifact.
- **Retention GC conflicts with nothing but depends on tombstone markers**: disposing without markers creates the resurrection/refetch hazards the doc and PurgeDAG review both warn about.
- **Epoch compaction conflicts with genesis-replay bootstrap**: once pre-epoch data is deleted, old deltas must be refused (below-watermark rejection), which is a protocol-level change — hence v2+.

## MVP Definition

### Launch With (v1.1)

- [ ] sgns-blockstore CID hash widening (sha-256 + blake2b-256) — prerequisite for everything else
- [ ] `BlockStoreBackedIpfsDatastore` adapter at the `globaldb.cpp:322-329` seam — local-first `get`, authoritative-miss taxonomy preserved, write-through to `LocalBlockStore`
- [ ] Config-gated construction from `crdt_config.json` (cold storage fully off by default; node behavior bit-identical when disabled)
- [ ] Spill-on-write for every CRDT block (journal-backed, crash-safe)
- [ ] Periodic background drainer: timer-driven, bounded (one drain in flight), shutdown = stop-and-resume via journal, pending-set visibility/logging
- [ ] Cold-store read fallback incl. graphsync serving through the adapter
- [ ] Retention GC of cold-eligible CRDT data: age (`crdt_gc_retention_hours`, 0=disable) + size cap (`crdt_gc_max_mb`), oldest-first, protected namespaces (heads, genesis, current-epoch pointers), per-pass metrics
- [ ] Disposed-CID local tombstones with their own bounded retention
- [ ] Epoch watermark record (min-head-height floor, persisted) — computation only, no deletion gated on it yet

### Add After Validation (v1.x)

- [ ] Staggered peer-vs-cold race + adaptive tier policy — once fallback latency is measured
- [ ] Request coalescing + brief authoritative-only negative cache
- [ ] Per-namespace retention classes (PIN/LRU/TTL policy table from the architecture doc)
- [ ] Backpressure: staging-disk cap inhibiting new spills + alerting
- [ ] Admin flush command (blocking drain)
- [ ] Admin whole-namespace purge (quiesced, heads-last, resumable — PurgeDAG precedent)

### Future Consideration (v2+)

- [ ] Consensus-anchored epoch compaction + checkpoint bootstrap — the formal causal-stability spec v1.0 explicitly deferred; needs epoch snapshot format, restore path, below-watermark delta rejection
- [ ] Tombstone-metadata compaction (drop superseded `/set/s` + `/set/t` versions below a *proven-stable* watermark, keep `/set/k/{v,p}`) — only meaningful after the stability spec exists
- [ ] Cold-store-side reclamation (deleting from S3 at all) — deliberately out of scope; no Delete on the frozen contract
- [ ] CARv2 packing / scale probe — already a v1.0 deferred item

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| CID widening (blake2b-256) | Enabler | LOW | P1 |
| BlockStoreBackedIpfsDatastore adapter | HIGH | MEDIUM | P1 |
| Config-gated construction | HIGH | LOW | P1 |
| Spill-on-write | HIGH | MEDIUM | P1 |
| Periodic drainer + lifecycle | HIGH | MEDIUM | P1 |
| Cold-store read fallback (reads + graphsync) | HIGH | MEDIUM | P1 |
| Retention GC (age+size, protected namespaces) | HIGH | MEDIUM | P1 |
| Disposed-CID tombstones | HIGH (correctness) | MEDIUM | P1 |
| Epoch watermark computation | MEDIUM | LOW-MEDIUM | P1/P2 (ship the record early) |
| Coalescing / negative cache / race | MEDIUM | MEDIUM | P2 |
| Backpressure staging cap | MEDIUM | MEDIUM | P2 |
| Admin purge / flush tools | MEDIUM | HIGH / LOW | P2 |
| Epoch compaction + checkpoint bootstrap | HIGH | HIGH | P3 (v2+) |
| Tombstone-metadata compaction | MEDIUM | HIGH | P3 (v2+) |

## Comparable-System Feature Analysis

| Capability | go-ds-crdt (reference impl) | IPFS Kubo / gateways | Yorkie (CRDT doc DB) | Sia s3d | SuperGenius v1.1 target |
|---|---|---|---|---|---|
| Deletion model | Soft (tombstones) only | Unpin + mark-sweep GC of unpinned blocks | `removedAt` tombstone → purged when stable | S3 DeleteObject; snapshots unpin | Soft delete (existing) + retention-driven disposal of cold data |
| Tombstone GC | **None shipped**; admin `PurgeDAG` (whole-namespace hard delete, PR #341) | n/a (pin-based) | Version-vector min across *active* clients covers tombstone timestamp; server-coordinated | n/a | v1.1: none (markers only); v2+: epoch-gated |
| Stability detection | None | Pin set | Server-computed min version vector | n/a | Heads-height watermark now; consensus epoch later |
| Late/rejoining replica | Full-DAG replay from genesis | Sync via DHT/bitswap | Snapshot replaces state (GC skipped) | Snapshot restore (buffered objects listed-but-unreadable) | Genesis replay now; epoch checkpoint in v2+ |
| Tiered read (miss→fetch→verify→re-cache) | DAGSyncer (IPFS-Lite) | Gateway/core read path, CID-verify before publish | n/a | S3 GET | Adapter: local → S3 → verify → serve → re-cache |
| Background upload | n/a | n/a | n/a | Bin-packing loop, `uploadDeadline` 24h, `uploadThreads` 4, `diskUsageLimit` 10 GiB, `flush`, Prometheus metrics | Periodic one-shot drainer, journal resume, bounded, logged |
| Retention shape | keep_count backups only | Pins + StorageMax watermark | Vector coverage | Object Lock retention; staging disk cap | Age + size dual trigger (in-house precedent) |
| Admin hard delete | PurgeDAG (quiesce required, heads last, resumable) | `ipfs repo gc` | Disable-GC flag; explicit `GarbageCollect(vv)` returns purge count | snapshots delete (unpin + record removal) | Namespace purge = v1.x tool |

**Key lessons imported:** (1) the reference implementation ships **no** tombstone GC — that is a deliberate safety default, not an oversight; (2) hard delete exists there only as a quiesced, heads-last, resumable admin op; (3) Yorkie proves per-tombstone GC is tractable *only* with a coordinator computing a minimum watermark over known-active members; (4) s3d is the model for drainer lifecycle/backpressure/metrics; (5) IPFS pins are the model for protected namespaces.

---

## GC Options Comparison: Local Tombstone vs Delete Entirely (user-requested decision)

**Context:** after cold-eligible CRDT data passes retention, what remains locally?

### Option A — Delete entirely (bytes + all metadata, incl. processed markers)
**What breaks:** peer re-broadcast of a head whose block was disposed → no processed marker (`HasBlock`/`markResolved`, `dagsyncer.hpp`) → the node re-requests it forever or stalls DAG walks; graphsync cannot distinguish "disposed" from "not yet synced"; a late replica's delta replay hits misses that look like sync gaps. This is precisely the PurgeDAG-review resurrection hazard, but continuous and uncoordinated instead of admin-triggered.
**Cost:** LOW to build, HIGH to debug in production.
**Verdict:** rejected for v1.1.

### Option B — Local tombstone (dispose bytes; keep a bounded disposal marker per CID)
**What works:** authoritative NotFound for disposed CIDs (fast, no S3 round-trip); correct dedup of re-broadcast heads; no resurrection ambiguity ("restoration must not resurrect values hidden by later tombstones" is trivially preserved — the marker IS the negative knowledge); marker set itself gets retention (bounded, oldest-first — markers are age-safe *because they are not CRDT tombstones*, they are node-local disposal records, not replicated state).
**Cost:** MEDIUM (new CF + scan integration + GC of the marker set).
**Verdict:** **recommended for v1.1.** It is the minimal remnant that keeps every architecture-doc invariant intact while reclaiming hot bytes.

### Option C — Compaction to value-summary (keep `/set/k/{v,p}`, drop old `/set/s` + `/set/t` versions below a stability floor)
**What works:** shrinks actual CRDT metadata, not just block bytes; preserves current-value resolution (which reads `/set/k`, `crdt_set.hpp:343`).
**What breaks if rushed:** a replica replaying pre-floor deltas re-adds elements whose hiding tombstones were dropped → resurrection. Requires the causal-stability spec the architecture doc demands before *any* archive GC.
**Verdict:** v2+, strictly gated on epoch watermarks.

### Option D — Consensus-anchored epoch deletion ("delete entirely, done right")
**What works:** the Merkle-CRDT paper (Sec. VI-B) states discarding DAG parts requires knowing every replica is aware — via replica-set knowledge **or an external source of truth such as a blockchain**; SuperGenius has both a blockchain and a `ValidatorRegistry`. Below a consensus-agreed epoch floor, delete entirely network-wide; new/rejoining nodes bootstrap from the epoch checkpoint (paper also notes shipping a snapshot beats genesis replay for large DAGs).
**Cost:** HIGH — epoch snapshot format, checkpoint restore, below-watermark delta rejection (protocol bump), cross-node coordination.
**Verdict:** the v2+ endgame the user's "delete entirely" instinct is actually pointing at; v1.1 only prepares the watermark record.

### Recommendation
**v1.1 = Option B**, with Option C/D's preconditions (epoch watermark record, formal causal-stability spec) started but not gating deletions on them. Rationale: go-ds-crdt (the system SuperGenius's CRDT is explicitly modeled on) ships no tombstone GC at all; Yorkie shows per-tombstone GC needs an active-membership watermark SuperGenius won't have until epochs exist; the architecture doc forbids the cheap variants (age-only purge, miss-as-absent) and directs initial versions to avoid permanent deletion of archived history. Option B reclaims the hot-bytes win now and leaves every door open.

---

## Sources

| Source | Type | Confidence | Key claim supported |
|---|---|---|---|
| `SuperGenius/src/crdt/**` (files/lines cited in grounding table) | Local code (curated) | HIGH | No CRDT GC exists; tombstone/element/key namespaces; heads heights; seam; TODO at crdt_data_filter.cpp:178 |
| `thirdparty/sgns-blockstore/include/sgns-blockstore/BlockStore.hpp:88-103`, `UploadDrainer.hpp` | Local code (shipped v1.0) | HIGH | sha-256-only v1 API; blake2b non-goal note; drainer single-thread contract; no-Delete permanence |
| `supergenius-sharded-ipld-cache-architecture.md` ~lines 265-378 | Local design doc (curated) | HIGH | Read/write paths, cache behavior, CRDT correctness invariants |
| `SuperGenius/src/account/GeniusNode.cpp:540-551, 553-601, 4675-4805` | Local code | HIGH | result_retention config + GC engine; crdt_config.json loading pattern |
| go-ds-crdt repo + PR #341 (github.com/ipfs/go-ds-crdt, merged 2025-04) | First-party repo/PR (fetched directly) | MEDIUM (seam tier; primary source) | No tombstone GC; PurgeDAG semantics, review hazards (resurrection, heads-last, resumable, memory, offline getter) |
| Merkle-CRDTs paper, arXiv 2004.00107 (ar5iv full text, fetched directly) | Academic (the CRDT model SG is based on) | MEDIUM (seam tier; primary source) | Ever-growing DAG; GC left as future work; deletion requires replica-set knowledge or blockchain source of truth; snapshot-beats-replay |
| Sia s3d README (github.com/SiaFoundation/s3d, fetched directly) | First-party docs | MEDIUM (seam tier; primary source) | Upload packing loop, uploadDeadline 24h, uploadThreads 4, diskUsageLimit 10 GiB, flush, pipeline metrics, snapshot flush semantics |
| IPFS persistence/pinning docs (docs.ipfs.tech/concepts/persistence, fetched directly) | First-party docs | MEDIUM (seam tier; primary source) | GC deletes unpinned data; pinning = retention control; pinning services as durable tier |
| Yorkie GC design (deepwiki.com/yorkie-team/yorkie 4.5, indexed from repo) | Secondary (repo-derived wiki) | MEDIUM | Tombstone model; min-version-vector GC safety rule; server coordination; disable flag; purge-count metrics |
| "From Causality to Stability" (VUB, MPLR 2020) + causal-stability articles (via search) | Secondary | MEDIUM | Causal stability needs membership + reliable causal broadcast; offline-replica frontier freeze |
| ralph / ORDHMap library | — | LOW (not directly reachable; 404 on guessed URL) | Mechanism inferred from cross-checked secondary sources only; flagged as gap |

## Gaps to Address Later

- **ralph/ORDHMap primary source** not reached — the ORDHMap-specific GC mechanism is inferred from Yorkie + stability literature; if the planner wants it cited authoritatively, locate the actual repo first (LOW confidence today).
- **Exact RocksDB key layout of `IpfsRocksDb`** (block-key prefix/column family inside the shared DB) not yet enumerated — needed before the adapter's spill scan can be written; phase-local research.
- **Epoch checkpoint format** deliberately un-researched (v2+ scope).
- **Kubo `StorageMax`/`StorageGCWatermark` exact semantics** cited from general IPFS docs knowledge, not the settings page directly — verify if the size-cap config is modeled on it.
