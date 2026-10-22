# Pitfalls Research

**Domain:** Integrating a shipped cold-storage blockstore library (`thirdparty/sgns-blockstore`) into an existing CRDT-over-IPFS node (SuperGenius): config-gated construction, spill-on-write, read fallback, GC.
**Researched:** 2026-10-22
**Workstream:** rocksdb-backup (milestone v1.1)
**Confidence:** HIGH (repo code and library evidence are cited per claim; the one external claim — upstream `go-ds-crdt` has no tombstone GC — is MEDIUM/web, see Sources)

**Proposed v1.1 phase labels used below** (v1.1 ROADMAP has no phases yet at time of research; roadmapper finalizes names/numbers):

- **C1 — Config-gated construction & build wiring** (crdt_config.json → cold storage; blank = disabled; CMake/find_package wiring)
- **C2 — Spill-on-write** (every CRDT block → LocalBlockStore journal → drainer → s3d)
- **C3 — Read fallback** (local reads + graphsync serving from cold tier)
- **C4 — GC & retention** (cold-eligible CRDT data past retention, retrievability preserved)
- **C5 — Integration hardening** (fault injection, teardown ordering, CI tier enforcement — mirrors v1.0 Phase 5)

**Library-mitigated vs integration-layer (read this first):**

| Risk area | Already mitigated by shipped v1.0 library | NEW at the SuperGenius integration layer |
|---|---|---|
| Failure taxonomy honesty | `StatusClass` separates authoritative `NotFound` from `TemporarilyUnavailable` (`BlockStatus.hpp:29-40`); messages never embed secrets (P11) | SuperGenius's `DAGSyncer`/`outcome` channel is single-valued — mapping that collapses the taxonomy (P1, P9) |
| Journal atomicity | Block bytes + `PendingUpload` record in ONE synced WriteBatch (`LocalBlockStore.hpp:55-63`, BACK-04); crash-window pair modeled | Eviction **eligibility policy** that consults journal state before removing bytes (P4, P13) |
| Upload-drain correctness | Idempotent re-drain (`alreadyPresent` converges), per-item failure isolation (`UploadDrainer.hpp:26-39`) | Drain **scheduling**, serialization, backpressure, journal-growth policy (P3) |
| CID verification | Client-side hash verification on every `Get`; ETag-over-ciphertext explicitly not a proof (`s3d-durability.md` §4) | Verifying before **serving to peers** on the graphsync responder path (P8) |
| s3d staged-vs-durable honesty | `ObjectStoreAccepted` encodes accepted-is-max-provable (`Durability.hpp:34-47`, evidence-cited) | The **eviction policy decision** built on top of that ceiling (P5) |
| Fault injection seams | `FaultController`, `SetFlipBytesForKey`, tier-labeled tests, loud env-gated skips (`testing-tiers.md`) | Wiring those seams into SuperGenius test paths; CI tier discipline in SuperGenius lanes (P12) |
| Crash recovery of the cold tier | Journal reconciliation on reopen replays unflushed WAL tail | GlobalDB **backup engine is blind to the cold journal** (Moderate 3) |

Everything else in this document is integration-layer NEW risk.

---

## Critical Pitfalls

### Pitfall 1: A cold-tier miss is read as authoritative absence on the CRDT read path

**What goes wrong:**
After GC evicts block bytes from RocksDB, every "do we have this CID?" answer in SuperGenius becomes ambiguous. `GraphsyncDAGSyncer::HasBlock` (`SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp:511-517`) returns `true` only if `GetNodeFromMerkleDAG` (RocksDB) or `GrabCIDBlock` (in-memory LRU) succeeds — an evicted block reads as `false`, which to `CrdtDatastore` means "unprocessed / absent". Consequences: external CIDs get re-requested from peers that never had them (fetch storms, failed roots), `getBlock`-style callers receive `CID_NOT_FOUND` for data the node actually owns, and `GetKey`/`QueryKeyValues` (`crdt_datastore.hpp:158-176`) silently lose cold data if GC also removes CRDT set rows. This is exactly the architecture doc invariant "a cache miss must not be interpreted as an absent or unprocessed CRDT operation" (`supergenius-sharded-ipld-cache-architecture.md`, CRDT correctness requirements).

**Why it happens:**
The `DAGSyncer` interface (`SuperGenius/src/crdt/dagsyncer.hpp:29-40`) has exactly two outcomes: have-it or error. There is no third "resident in cold tier" state, so the natural first integration collapses `BlockStatus::TemporarilyUnavailable` and cold-resident into one miss-shaped failure. The library taxonomy (`BlockStatus.hpp:29-40`) was built to prevent precisely this conflation — but only the integration layer can preserve it across the seam.

**How to avoid:**
Introduce a cold-aware wrapper (or extend the internal seam) so that RocksDB-miss + cold-store-present = a distinct "cold-resident" state, and RocksDB-miss + cold-store-`TemporarilyUnavailable` = "unknown, do not treat as absent". `HasBlock` semantics must become "have it locally OR can retrieve it from cold before deadline". Only a cold `NotFound` (authoritative) may ever surface as not-found. Add an integration conformance test that injects `FaultController` transport faults and asserts no NotFound-shaped result escapes (the library kit pattern extended to the SuperGenius side).

**Warning signs:**
- Spike in `getNode` fetch attempts / `RecordCIDFailure` for CIDs the node itself authored.
- Failed-root retries (`RetryDueFailedRoots` activity in logs) for old roots immediately after GC runs.
- Peers blacklisting this node after it serves graphsync `Partial/RequestFailed` for its own broadcast heads.

**Phase to address:** C3 (read fallback) — the state model must be designed in C3's plan, before C4 GC makes misses common.

---

### Pitfall 2: Synchronous spill on the CRDT commit path (per-block PUT amplification blocking the batch)

**What goes wrong:**
The write path is synchronous end-to-end: `PutKey` → `Publish` (`crdt_datastore.cpp:1455-1462`) → `AddDAGNode` enqueues to the dag worker (`crdt_datastore.cpp:1586-1614`) → caller blocks in `WaitForJob` until the worker finishes (`crdt_datastore.cpp:1616-1707`, hard 20-minute timeout at `:1699`). The worker's `ProcessJobIteration` does `set_->Merge` then `dagSyncer_->addNode` (`crdt_datastore.cpp:984-1035`). If spill-on-write is implemented as an inline S3 PUT inside that sequence, every CRDT commit (including consensus publishes and registrations, per the comment at `graphsync_dagsyncer.cpp:22-26`) gains a remote RTT; with s3d slow or down, every publish eventually dies on the 20-minute `WaitForJob` timeout — i.e., a storage-tier outage becomes a consensus outage. Even without S3 in the picture, an inline `LocalBlockStore::Put` is one extra `sync=true` WAL fsync per block (`LocalBlockStore.hpp`, D-10 duty note) on the hot path.

**Why it happens:**
"Spill every CRDT block on write" reads like "add a call after addNode", and the worker thread is the one place all blocks pass through (`ProcessJobIteration` at `crdt_datastore.cpp:1029` is the single choke point).

**How to avoid:**
Spill = enqueue-to-local-journal only, on the worker thread (one atomic WriteBatch: bytes + `PendingUpload` — the library already makes this crash-safe); S3 transfer happens exclusively on a separate drainer thread consuming `GetPendingUploads`. The CRDT commit must never wait on the network. Keep the spill hook off `WaitForJob`'s critical section where possible (after `addNode` success, before job completion notification, is acceptable for the journal commit; the S3 drain never is).

**Warning signs:**
- `WaitForJob: Still waiting` info logs (`crdt_datastore.cpp:1677`) appearing on publishes during s3d instability.
- Publish latency percentiles tracking s3d RTT.
- `numberOfDagWorkers` threads saturating at 100% during drain catch-up.

**Phase to address:** C2.

---

### Pitfall 3: Unbounded journal growth when s3d is slow or down (missing backpressure policy)

**What goes wrong:**
Every CRDT block becomes a `PendingUpload` journal record in the LocalBlockStore's own RocksDB (by design — that IS the crash-safe buffer). If s3d is down for hours/days, the journal grows without bound on the same disk as hot state; combined with the node continuing to write hot RocksDB, the volume fills. Worse interaction: disk-full on s3d's staging directory already inhibits its uploads (`s3d-durability.md` §2, `bufferUsed`/`bufferLimit`); a full disk locally then breaks BOTH stores. `UploadDrainer` is a synchronous one-shot with a single-threaded-use contract (`UploadDrainer.hpp:75-85`) — it has no scheduling, retry/backoff, or bounded-queue behavior; that is all integration-layer.

**Why it happens:**
The v1.0 drainer was a tooling one-shot; the "service-ification" (periodic drain, backoff, alarms) is new v1.1 work and easy to scope out as "just call DrainPendingUploads in a loop".

**How to avoid:**
Explicit backpressure policy chosen in C2's plan, with the options on record: (1) unbounded journal + watermark alarm + ops runbook (journal is disk-bounded, and eviction is inhibited — disk grows but nothing is lost); (2) bounded pending-set: when the journal exceeds a threshold, spill enqueue degrades to "keep block hot-only and retry spill later" (never drops bytes — the block remains in GlobalDB RocksDB until spilled); (3) never "fail the write" — the consensus path must not become read-only because a storage tier is down. Serialize drains (one drainer thread; a second concurrent drain races the journal against the library's single-threaded contract). Export metrics: pending count/bytes, drain success rate, oldest pending age.

**Warning signs:**
- `GetPendingUploads` count monotonic non-decreasing across drain cycles.
- Cold-store directory disk usage growing in lockstep with hot-store usage during an s3d outage.
- Oldest-pending-age metric exceeding the retention window you plan to use in C4 (GC eligibility will be starved — see P4).

**Phase to address:** C2 (policy + drainer service), exercised in C5 (fault injection with s3d down).

---

### Pitfall 4: Evicting local bytes before `ObjectStoreAccepted` is recorded

**What goes wrong:**
GC frees disk by removing local block bytes. If eligibility is computed from CRDT retention timestamps alone (age, cold-status) and does not consult the upload journal, it can evict a block still in `PendingUpload` state (upload never acknowledged). The drainer's next pass hits a local Get miss for that CID — the documented per-item failure "the bytes were evicted" (`UploadDrainer.hpp:26-33`) — and the only copy of the block is gone: the remote never received it, the local bytes were deleted. Silent permanent data loss of CRDT history.

**Why it happens:**
The library owns journal *atomicity* (bytes + journal birth in one WriteBatch, `LocalBlockStore.hpp:55-63`) but deliberately does not own eviction *policy*. A GC implementer naturally reaches for "old + cold = delete" and forgets the journal is the third input. The v1.0 library provides `BlockStoreTooling` / `GetPendingUploads` and `UploadState` exactly so the integration can check this — nothing enforces it.

**How to avoid:**
Eviction eligibility = (retention age satisfied) AND (journal state ≥ `UploadedAccepted` for that CID) AND (not pinned) AND (no in-flight drain snapshot covering it — see P13). Implement as an explicit state-machine check with the journal lookup in the same critical section as the eviction decision; add a fault-injection test in C5: `CrashPoint::BeforeCommit` / failed remote Put followed by a GC pass must never remove bytes. Grace interval (e.g., evict only blocks accepted ≥ N minutes ago) absorbs s3d's acknowledged-but-ack-lost races.

**Warning signs:**
- Drain logs containing local-Get-miss items correlated with GC passes in the preceding window.
- Journal pending count dropping without a matching rise in remote object count.
- Disk freed by GC exceeding the remote store's reported object bytes.

**Phase to address:** C4 (policy), C5 (fault-injection proof).

---

### Pitfall 5: Treating `ObjectStoreAccepted` as durable — s3d staged-vs-durable correlated loss

**What goes wrong:**
Even a correct journal says only `UploadedAccepted`. For s3d v0.2.1, a 200-OK PUT means *received into local staging on the s3d host* — there is no per-object staged-vs-durable signal, the stats counters are pipeline-global and racy under concurrency, and the only staged→durable primitive is the bucket-scoped, blocking `POST /objects/flush` (`s3d-durability.md` §2-§3; committed evidence in `docs/evidence/s3d-spike/`). If GC evicts local bytes after `Accepted`, the only remaining copy lives in s3d's staging directory — on a disk that can be the same machine or fail with it. A staging-disk-full condition (`bufferLimit`) silently inhibits future uploads while GC keeps evicting → progressive, invisible loss of everything not yet transferred. The library already encodes the honest ceiling (`Durability.hpp:34-47`: "durability NOT yet proven"; "a store NEVER reports an `achieved` level it has not verified") — the trap is the integration building an eviction policy that assumes more.

**Why it happens:**
"Accepted" sounds like "done". The v1.0 audit's accepted-is-max-provable finding (S3D-03) is recorded in library docs, but the v1.1 eviction-policy author may not internalize that the ceiling applies to *every* eviction decision, not just the API naming.

**How to avoid:**
Make the eviction durability bar an explicit, documented policy decision in C4: (a) evict-after-`Accepted` as an accepted operational risk (v1.0 precedent: AR-05-1 accepted-risk pattern in `05-SECURITY.md`) with s3d staging on separate storage from the node, or (b) require a flush + stats-observed `pendingObjects==0` (or per-bucket drain) before each GC batch evicts — accepting flush's blocking, bucket-scoped cost. Regardless of choice: monitor `pendingObjects`/`bufferUsed`/`bufferLimit` via the admin API and **inhibit GC while staging is unhealthy**, mirroring the architecture doc's operational-implications list ("disk-full and low-balance conditions must inhibit eviction"). Never read counter deltas as per-object proof (§2 concurrency limitation).

**Warning signs:**
- s3d `pendingObjects` non-zero for hours; `bufferUsed` approaching `bufferLimit`.
- GC freeing bytes while s3d `uploadedObjects` stays flat.
- Restore drills (fresh node retrieving evicted CIDs) failing only for blocks evicted during high upload concurrency.

**Phase to address:** C4 (policy decision, documented as accepted-risk or flush-gated), C5 (crash/loss-of-s3d-machine scenario tests).

---

### Pitfall 6: Purging tombstones (or set rows) that live CRDT merges still need — resurrection

**What goes wrong:**
`CrdtSet` is an Add-Wins Observed-Remove set (`crdt_set.hpp:12-15`): a tombstone row is what hides an older element. If GC purges tombstone rows "because they are old", any later re-delivery of the old element — via restore-from-cold re-merge, via a slow peer's rebroadcast (`StartRebroadcastHeads` re-announces heads periodically, `crdt_datastore.hpp:105`), or via `BlockReceivedCallback` accepting a re-sent block (`graphsync_dagsyncer.cpp:606`) — re-adds the value with no tombstone to outrank it. Deleted registrations/records resurrect on some nodes and not others → divergence the CRDT can no longer resolve. This is the doc invariant "tombstones cannot be purged merely because they are old" + "restoration must not resurrect values hidden by later tombstones". Note the upstream reference implementation `go-ds-crdt` (which this datastore is explicitly based on, `crdt_datastore.hpp:13`) still has **no** tombstone/history GC in production — only whole-DAG `PurgeDAG` — and even that recent deletion work needed a follow-up ErrNotFound-check fix (upstream #341/#344). There is no proven recipe to copy; v1.1 GC is novel territory.

**Why it happens:**
Tombstone rows look like garbage in RocksDB scans (old, small, never read). The pressure to "GC all cold-eligible CRDT data" invites treating `/r/` rows as cold data. Causal stability (all current and future peers have merged the tombstone) is unprovable in open-membership pubsub.

**How to avoid:**
v1.1 GC scope: evict **block bytes** (IPLD blocks in the dagService store) and optionally cold *value* rows — but tombstone rows (`/namespace/r/...`) are NEVER purged in v1.1; they stay pinned forever, and this is recorded as a formal decision with a follow-up flag for a future causal-stability-specified GC (the architecture doc's own gating: "Archive garbage collection can be added only after reachability, retention, and tombstone stability are explicitly specified"). Keep current heads, current values of live keys, and genesis pinned (doc's pinning policy). Add a resurrection test: delete key → GC → re-deliver the pre-delete delta block → assert key stays absent on every node.

**Warning signs:**
- QueryKeyValues returning keys that were `DeleteKey`'d before a GC pass.
- Cross-node `PrintDataStore`/query divergence after one node restored from cold.
- Review comments mentioning tombstone pruning by age anywhere in the C4 plan.

**Phase to address:** C4 (hard scope boundary), decision recorded in C1's SPEC so the roadmap never schedules tombstone GC without a new research pass.

---

### Pitfall 7: Heads' causal reachability broken — resolved-marker vs block-bytes divergence

**What goes wrong:**
Heads reference their causal history as DAG links. `TraverseCIDsLinks` **skips** children whose CID `isResolved` (`graphsync_dagsyncer.cpp`, resolved-skip logic in the traversal loop ~756-765; `markResolved` at `:799`) and `GetLinksToFetch` drives fetches from the walk. Two divergent failure modes from GC touching only one half of the (block bytes, resolved marker) pair:
- **Evict bytes, keep marker:** traversal silently skips the missing subtree — incomplete DAG walks with no error; any consumer trusting the walk (dependency filters, `GetDeltaFromNode` graph resolution) sees a subtly wrong graph.
- **Purge marker, bytes evicted:** every re-walk (e.g., after restart, or when a head is re-processed) enqueues network fetches for cold CIDs from peers that may have obtained them only from *this* node → failed fetches → root retries → peer blacklisting (`BlackListPeer`, never-connected backoff caps at 30 minutes, `graphsync_dagsyncer.cpp:880-920`).

**Why it happens:**
RocksDB holds several parallel keyspaces for one CID (block bytes in the IpfsDatastore, resolved markers in the dagService, heads in `/namespace/heads/`, set rows in the CRDT namespace). Nothing in the existing code evicts anything but whole caches, so no precedent exists for keeping them consistent under deletion — the C4 GC author must invent the invariant.

**How to avoid:**
GC treats (block bytes + resolved marker + set rows for that delta) as **one unit**: either all present or all cold-evicted-together, with rehydration restoring all before any re-walk. Pin heads + N recent ancestors per topic. When a walk encounters a cold-resident CID, it must rehydrate synchronously-with-deadline (C3 mechanism) or fail loudly — never skip silently. Add a C4 test: evict → restart → rebroadcast-heads → assert walks complete via cold reads and no peer fetches for evicted CIDs are attempted.

**Warning signs:**
- `TraverseCIDsLinks: Skipping traversal of resolved child` for CIDs whose bytes are gone from RocksDB (assert in a debug cross-check tool).
- Post-restart fetch storms of old CIDs; spikes in `ROUTE_NOT_FOUND`/`CID_NOT_FOUND` from `getNode` (`graphsync_dagsyncer.cpp:205+`).

**Phase to address:** C4 (invariant + tooling), depends on C3 rehydrate.

---

### Pitfall 8: Blocking the graphsync responder (libp2p io_context) on slow cold fetches

**What goes wrong:**
Once local bytes are evicted, peers' graphsync requests for them hit the responder. The responder currently serves only from `dagService_` (`graphsync_->start(dagService_, blockCallback)`, `graphsync_dagsyncer.cpp:532-558`) — and the comment at `:546-551` records that this is *deliberate*: making the responder fetch over the network "pins the host's only thread and freezes the whole node". A naive read-fallback that turns responder misses into synchronous s3d GETs reintroduces exactly that freeze: one slow s3d stalls all libp2p stream processing (every protocol, not just graphsync). The requesting side has `kTotalFetchTimeout = 20s` / `kInProgressRequestTimeout = 120s` budgets (`graphsync_dagsyncer.cpp:21-27`); the serving side has libp2p stream deadlines and a single-threaded io_context — different constraints, easy to conflate.

**Why it happens:**
"Read fallback for graphsync serving" sounds symmetric with the client-side fetch path, so implementers reuse the blocking `getNode` pattern on the serving side.

**How to avoid:**
Cold fetches for serving run on a dedicated executor/thread pool with bounded concurrency and a deadline shorter than the peer's stream timeout; results post back into the responder asynchronously (or the responder answers "don't have" on cold-miss and the block is re-warmed for the *next* request — an acceptable degradation that must be a conscious choice, not an accident). Verify CID before serving (the library verifies on `Get`; s3d ETag is over ciphertext and is never a proof, `s3d-durability.md` §4). Budget: warm-path serves stay zero-async; cold-path serves are bounded and rare by construction of C4 retention.

**Warning signs:**
- Node-wide libp2p latency (identify, pubsub gossip) spiking when peers request cold CIDs.
- io_context thread CPU/queue depth rising with cold-serve rate.
- graphsync request timeouts on the *peer's* side correlated with s3d latency.

**Phase to address:** C3 (design), C5 (slow-backend fault injection on the serving path).

---

### Pitfall 9: Negative-caching transport failures — taxonomy collapse at the SuperGenius seam

**What goes wrong:**
The library's core promise is "transport failures must not become cached `NotFound`" (`BlockStatus.hpp:29-40`; architecture doc read path: "Only authoritative absence should be negative-cached, and then only briefly"). SuperGenius code has no such distinction: `outcome::result` failures are undifferentiated, and existing machinery actively converts failures into lasting state — peer blacklisting (`BlackListPeer`, entries never erased, `graphsync_dagsyncer.cpp:990-1004`), per-CID failure records (`RecordCIDFailure`), and route removal. If a cold `TemporarilyUnavailable` (s3d timeout) is mapped to a `CID_NOT_FOUND`-shaped error at the integration seam, one s3d blip can poison `HasBlock` answers and blacklist/route state for 30 minutes (never-connected backoff cap), turning a transient backend outage into a self-inflicted serving outage.

**Why it happens:**
The mapping code is one `switch` in a wrapper, written before the failure-mode taxonomy is internalized; `StatusClass` has four members but the SuperGenius error enums (`GraphsyncDAGSyncer::Error`) effectively have two buckets (not-found vs everything-else), and "everything-else" already flows into blacklist bookkeeping.

**How to avoid:**
Preserve `BlockStatus` (code + source) up to the decision point. Explicit mapping table, code-reviewed as a first-class artifact in C3: `NotFound` → may be treated as absence (and only briefly negative-cached, if at all); `TemporarilyUnavailable` → "unknown": no blacklist writes, no `RecordCIDFailure`, retry with backoff; `Corrupt` → attribute to source (`Remote`/`Peer`), never serve, alarm (this is the P8 verification net); `Unauthorized` → ops alarm, not absence. Conformance-test each row with `FaultController` injection.

**Warning signs:**
- Blacklist entries created during s3d outage windows.
- Any `static_cast`-style narrowing of `BlockStatus::code` to a boolean have/don't-have.
- Cold-read latency metric showing cached misses (negative cache) surviving past backend recovery.

**Phase to address:** C3 (mapping table + tests).

---

### Pitfall 10: Config traps — silent-disable on malformed config, blank-vs-missing semantics, credentials in plaintext JSON

**What goes wrong:**
Three sub-traps, all landing in `crdt_config.json` handling that extends the existing `LoadCrdtConfig` precedent (`SuperGenius/src/account/GeniusNode.cpp:551-610`):
1. **Silent-disable on malformed config.** The existing pattern is warn-and-continue with defaults (`:570-574`) — tolerable for backups, dangerous here: a typo'd cold-storage config silently disables spill; the node looks healthy, disk creeps for weeks, and GC (which depends on spill state) can never become eligible — or worse, a partially-parsed config enables spill with a default/garbage endpoint and every drain fails forever (P3 interaction).
2. **Blank-vs-missing field semantics.** Milestone contract: blank = disabled = current behavior preserved. The trap is treating *malformed* as blank (silent disable) or treating blank `enabled` as true (spill on by surprise). Every field needs an explicit tri-state decision: missing / blank / present-invalid.
3. **Credentials in plaintext JSON.** The architecture doc is explicit: credentials from env vars, protected secret files, or a secret manager — "rather than the main configuration file". Putting `access_key`/`secret_key` inline in `crdt_config.json` violates it and mirrors secrets into backups (GlobalDB backups, node-disk images).

**Why it happens:**
Copy-pasting the `LoadCrdtConfig` pattern is the path of least resistance, and it was fine for its original blast radius. Credentials-in-config is what every S3 SDK quickstart shows.

**How to avoid:**
Strict schema validation for the cold-storage section: absent section → feature off (log once, info); section present but malformed/unknown fields → **fail loud** (refuse startup or refuse to enable the feature with a CRITICAL log and a health-flag, an explicit decision recorded in C1) — do not fall back to defaults silently. Credentials via environment variables following the proven v1.0 test-gate pattern (`SGNS_BLOCKSTORE_TEST_S3D_*`, `testing-tiers.md`) and a production `SGNS_COLD_STORAGE_*` set; config holds only endpoint/bucket/prefix/policy. Add tests: missing file → off; blank section → off; malformed → loud; credentials-in-file → rejected with pointer to env.

**Warning signs:**
- `Invalid crdt_config.json ... using defaults` warn lines in production logs (grep for the `:571` message).
- Cold-storage metrics absent while operators believe spill is on.
- `access_key` appearing in `crdt_config.json` examples or backups.

**Phase to address:** C1.

---

### Pitfall 11: Restored-from-cold blocks re-entering the CRDT pipeline as new data

**What goes wrong:**
Rehydration/restore must write retrieved blocks back into local storage. If the restore path routes through the broadcast-facing machinery — `BlockReceivedCallback` (`graphsync_dagsyncer.cpp:606`, which processes unsolicited blocks, walks links, adds routes) or `AddCIDBlock`/LRU + any future re-broadcast — restored history can be re-announced to peers as if newly received, triggering `Block received without CRDT asking for it explicitly` error paths (`graphsync_dagsyncer.cpp:641`), route pollution, or redundant DAG walks on every peer. Merge idempotency saves *values* only where tombstones survive (P6); the *messaging* side effects are not idempotent. Separately, GlobalDB's own restore precedent (`globaldb.cpp:250-282`, RocksDB BackupEngine restore with `std::abort` on failure) shows restoration is treated as a deliberate, destructive, logged operation — cold restore should inherit that seriousness, not be a quiet side effect of a read.

**Why it happens:**
The read path (C3) and the restore path (C4) both "put bytes back", and the only existing put-back APIs are the broadcast-facing ones.

**How to avoid:**
Dedicated restore/rehydrate API: verify CID (library does) → write block bytes + resolved marker + (nothing else) → no pubsub broadcast, no `BlockReceivedCallback`, no head mutation. Rehydration on the read path (C3) and bulk restore tooling (C4) both use it. Test: restore a large old batch → assert zero pubsub messages emitted, zero `AddRoute` calls, heads unchanged.

**Warning signs:**
- Pubsub CRDT broadcast traffic spikes during restore drills.
- `Block received without CRDT asking for it explicitly` errors during rehydration.
- Peers reporting re-delivery of CIDs they already merged.

**Phase to address:** C3 (rehydrate-on-read), C4 (bulk restore tooling).

---

### Pitfall 12: Build/CI traps — hard-required dependency, unpinned submodules, no Docker in CI, tier discipline

**What goes wrong:**
Four concrete traps specific to this repo's structure:
1. **Hard-required dependency breaks all builds.** If SuperGenius's CMake unconditionally `find_package`s sgns-blockstore, every build leg (Windows MSVC, Linux, macOS; plus SDK/wallet downstream builds) now requires the thirdparty superbuild chain `json→pugixml→minio-cpp→sgns-blockstore` to have completed. At v1.0 close, all three repos carried **unpushed commits** (root ~39, thirdparty 8, sgns-blockstore 16 — v1.0 audit tech-debt): a fresh clone or CI leg without those commits fails to configure at all.
2. **Docker assumptions in tests.** SuperGenius/CI runners have no Docker (v1.0 decision C2). Any integration test that assumes a containerized S3/s3d silently can't run; the proven pattern is the MinIO **server binary as a child process** (`testing-tiers.md`, Tier2, `SGNS_BLOCKSTORE_TEST_MINIO_BIN`) with fakes for Tier1 and s3d strictly dev-gated (Tier3).
3. **Tier-label drift.** The fail-closed `ctest -L Tier1 --no-tests=error` lane only works if every new test is labeled; an unlabeled SuperGenius cold-integration test silently never runs in CI, and a live-S3 test without an env gate fails hermetic legs (or worse, passes while skipping — the no-skip-meta-test decision means loud labelled skips are the enforcement).
4. **Single build tree / export seam.** Builds originate from `build/<Platform>/<Debug|Release>`; the consumption seam is `_FINDPACKAGE_SGNS_BLOCKSTORE_CONFIG_DIR` (v1.0 audit item 6). Mis-wiring the prefix path works on the dev machine and breaks CI.

Related Windows-specific trap (also C1): the process will contain **two RocksDB instances** — SuperGenius's own (`storage::rocksdb`, `globaldb.cpp`) and LocalBlockStore's independently compiled one (dual-compat 9.4/11.1, pimpl-isolated, `LocalBlockStore.hpp:96-105`). The library's D-01 rule (never share the GlobalDB handle or directory, `LocalBlockStore.hpp:71-80`) keeps data separate, but static linking on MSVC with mismatched RocksDB versions risks symbol/ODD collisions — align the thirdparty build's RocksDB version with SuperGenius's at configure time and verify one binary links cleanly on all three platforms.

**Why it happens:**
Three repos, three remotes, one superbuild; the library was proven standalone but "consumed by SuperGenius" was explicitly out of v1.0 scope — the export seam was "ready" but never exercised by a consumer.

**How to avoid:**
Config-gated CMake option (e.g., `SGNS_COLD_STORAGE`, default OFF until submodules are pinned and pushed; ON via the same config gating as runtime). Mirror the tier discipline in SuperGenius test registration from day one (labels + env gates + loud skips, no fixed sleeps, loopback-only binds — `tier1_static_audit` patterns). A C1 exit criterion: fresh-clone build+`ctest -L Tier1` green on Windows/Linux/macOS with the option ON, from pushed commits only.

**Warning signs:**
- CI configure failures mentioning `sgns-blockstore` not found.
- Any new test with no `LABELS` property.
- Local builds green, CI builds red (prefix-path divergence).

**Phase to address:** C1 (wiring + tiers), C5 (fresh-clone leg proof).

---

### Pitfall 13: GC racing in-flight reads and drains (eviction mid-serve → Corrupt classification)

**What goes wrong:**
Two race windows: (1) a graphsync responder or `getNode` is mid-read of a block's bytes from RocksDB while GC deletes that key — depending on read pattern this yields a partial read whose hash fails, surfacing as `StatusClass::Corrupt` for a perfectly good block, tripping the P9 alarm path and source attribution (`BlockSource::Local`) wrongly; (2) the drainer snapshotted the pending set and GC evicts bytes between snapshot and `local.Get` → drain item fails (recorded, not fatal to siblings — `UploadDrainer.hpp:26-33`) but the bytes may be unrecoverable if the remote Put never ran (P4's atomicity gap made real by the race). The existing GC precedent in this codebase, `RunResultGC` (`GeniusNode.cpp:4727-4810`), does raw `std::filesystem::remove` with zero coordination against readers — copying that pattern for CRDT blocks bakes in both races.

**Why it happens:**
Filesystem-style GC (the only in-repo precedent) needs no coordination because result files have no concurrent readers; CRDT blocks have many (responder, DAG walks, drainer, merge path), and RocksDB reads don't fail cleanly under concurrent delete of the key mid-iteration.

**How to avoid:**
Two-phase eviction: mark-as-evicting (checked by read paths and drain snapshots; new reads rehydrate instead) → grace interval → physical delete. Or a read-reference/pin count per CID (the pin set from the architecture doc's cache policy doubles as this). Eviction batches take the pending-drain snapshot into account (skip CIDs in the current snapshot). C5 fault test: drive eviction concurrently with serving and draining under `FaultController` timing control; assert zero `Corrupt` classifications and zero lost blocks.

**Warning signs:**
- `Corrupt`/`BlockSource::Local` statuses appearing only during GC windows.
- Drain items failing with local-Get-miss interleaved with GC log lines.
- Any new code calling raw RocksDB `Delete`/`remove` on block storage without the two-phase dance.

**Phase to address:** C4 (mechanism), C5 (race-injection proof).

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Inline S3 PUT in `ProcessJobIteration` (vs journal+drainer) | "Spill-on-write done" in one line | Consensus latency coupled to storage backend; 20-min `WaitForJob` failures during outages (P2) | Never |
| Map all cold failures to `CID_NOT_FOUND` | Fits existing error enums, no interface churn | Blacklist poisoning, miss-as-absence divergence (P1, P9) | Never |
| GC tombstones by age in v1.1 | Reclaims the most annoying small keys | Resurrection divergence with no CRDT-internal fix (P6) | Never (until a causal-stability spec exists) |
| One drain loop thread with no policy ("call `DrainPendingUploads` every N seconds") | Minimal C2 code | Unbounded journal growth, concurrent-drain races (P3) | Prototyping only, before first integration test |
| Credentials inline in `crdt_config.json` | Zero new config plumbing | Secrets in config backups/images (P10) | Never |
| Unlabeled / env-ungated live-S3 tests in SuperGenius | Tests pass on dev machine | CI either fails or silently skips; tier contract erodes (P12) | Never |
| Skip CID conversion fuzzing (libp2p CID ↔ library `Cid`) | Conversion "obviously" round-trips | One codec/version-bit bug corrupts every spilled block's addressability | Never — v1.0's C1 CID-conflict decision exists precisely because this area bit once |
| Reuse `RunResultGC` file-deletion pattern for blocks | Familiar, small diff | Mid-read deletes → `Corrupt` storms, lost blocks (P13) | Never |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Sia s3d | Assuming 200-OK = durable; reading `/stats/uploads` counter deltas as per-object proof | `ObjectStoreAccepted` is the ceiling; flush is bucket-scoped+blocking; monitor `pendingObjects`/`bufferUsed`/`bufferLimit` and inhibit eviction when unhealthy (`s3d-durability.md` §2-§3) |
| s3d ETag | Treating ETag/digest as content proof | Client-side CID verification only; ETag is over client-encrypted ciphertext (§4) |
| MinIO C++ SDK | Letting SDK types leak past the adapter | Types stay behind `S3Client` adapter (library discipline); integration code sees only `BlockStore` |
| LocalBlockStore | Pointing it at the GlobalDB RocksDB dir/handle to "save a DB" | Own directory only (D-01, `LocalBlockStore.hpp:71-80`); GlobalDB backup engine won't cover it either way (Moderate 3) |
| UploadDrainer | Two threads draining "for throughput" | Single-threaded-use contract (`UploadDrainer.hpp:75-85`); serialize, or extend the library deliberately |
| GlobalDB BackupEngine | Assuming backups now cover cold state | Backups cover GlobalDB's DB only; cold journal/bytes need their own backup story or documented rebuild path |
| graphsync responder | Making the responder fetch from cold synchronously | Off-io_context executor, deadline, bounded concurrency, CID verify before serve (P8) |
| libp2p peer blacklisting | Letting storage-tier failures write blacklist state | Blacklist only for peer-transport failures; `TemporarilyUnavailable` never touches it (P9) |
| `lru_cid_cache_` | Assuming it mirrors RocksDB state | It diverges after eviction — call `DeleteCIDBlock` (`graphsync_dagsyncer.cpp:855`) on evict (Moderate 4) |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Per-block S3 PUT (one CID = one object) | s3d SQLite metadata growth, request-cost, slow drains | It's the v1.0-blessed v1 layout; measure PUT throughput/metadata before considering CARv2 (architecture doc Phase-6 guidance) — do not add packing in v1.1 | Tens of millions of objects |
| Per-block `sync=true` WAL fsync on spill | Publish p99 following disk fsync latency | Journal-batch spill (library commits bytes+journal in one batch); keep S3 out of the path (P2) | Slow/overlay disks, Windows |
| `cid.toString()` per block in spill/GC hooks | CPU burn on hot path (existing code guards it by log level, e.g., `crdt_datastore.cpp:1594-1603`) | Level-guarded logging; avoid toString in non-log spill logic | High block rates |
| Rebroadcast-driven cold fetch storms | Fetch spikes after head rebroadcast on nodes with evicted history | Cold-aware Has/Get (P1) + rehydrate-with-deadline (P7) | First GC pass + any rebroadcast |
| Negative-cached misses | Cold reads failing minutes after s3d recovery | Preserve taxonomy; brief negative cache for authoritative NotFound only (P9) | First s3d blip |
| Bulk restore re-merge storms | Restore saturating dag workers | Restore writes bytes only, no re-merge of already-merged deltas (P11); idempotent by tombstone retention | Large restores |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| S3 credentials in `crdt_config.json` | Secret disclosure via config backups, node images, logs | Env vars / secret files (`SGNS_COLD_STORAGE_*`), never the config file (P10; architecture doc credentials rule) |
| Secrets inside `BlockStatus.message` | Leaking keys through logs/metrics | Library rule P11 (`BlockStatus.hpp:66-69`) — keep human-readable context only at the integration layer too |
| Serving unverified bytes from cold | Corrupt/tampered object served to peers, poisoning their DAGs | Verify hash→CID before serve (library `Get` does; keep it on the responder path, P8) |
| Trusting s3d ETag as integrity | Ciphertext digest proves nothing about content | Client-side verification only (`s3d-durability.md` §4) |
| Unauthenticated s3d admin endpoint reachable | `/objects/flush`, stats tampering | Loopback/firewall s3d admin port; document in ops runbook |

## UX Pitfalls (node-operator facing)

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Silent-disable on malformed config (P10) | Operators believe spill/GC is on; disk fills for weeks | Loud startup failure or CRITICAL + health flag; one-line status log of resolved config |
| No cold-storage observability | Journal growth, drain failures, hit rates invisible | Export pending count/bytes, oldest-pending-age, drain rate, cold hit/miss, eviction eligibility count; reuse the tier-3 evidence-capture habit |
| GC with no dry-run | Operators afraid to enable retention | `gc_dry_run` mode logging what would be evicted; first production pass at conservative retention |
| Restore is undocumented magic | Recovery drills improvised during an incident | C4 deliverable: restore runbook + drill evidence, mirroring v1.0's committed-evidence pattern |

## "Looks Done But Isn't" Checklist

- [ ] **Spill enabled:** Often missing journal-state accounting — verify a killed-mid-drain node re-drains everything pending after restart (journal reconciliation is the library's; the *service* wiring is yours).
- [ ] **"Durable" claims:** Often missing the accepted-vs-durable distinction — verify any docs/metrics claiming durability cite `ObjectStoreDurable` only if a flush policy exists; default reality is `Accepted` (P5).
- [ ] **Read fallback:** Often missing the serving side — verify a *peer* can graphsync-fetch a block this node evicted, under s3d latency, without freezing the node (P8).
- [ ] **HasBlock correctness:** Often missing cold-residency — verify `HasBlock` true ⇒ retrievable within deadline after RocksDB eviction (P1, P7).
- [ ] **GC:** Often missing the journal check and the two-phase dance — verify GC never removes bytes for a `PendingUpload` block, and never deletes mid-read (P4, P13).
- [ ] **Config:** Often missing malformed-vs-blank tests — verify the three cases (missing/blank/malformed) produce three distinct, intended behaviors (P10).
- [ ] **Shutdown:** Often missing drainer/fetch-pool joins — verify teardown under active cold traffic doesn't SIGABRT (precedent: 2026-09-19 macOS teardown crash noted at `graphsync_dagsyncer.hpp:96-107`).
- [ ] **CI:** Often missing tier labels on new tests — verify `ctest -L Tier1 --no-tests=error` still counts every new cold test (P12).
- [ ] **Fresh clone:** Often missing pushed-commit verification — verify a clean clone of all three repos configures and builds with cold storage ON (P12).

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Evicted-before-accepted (P4) | HIGH (potentially unrecoverable) | Stop GC; inventory journal-failed items; recover bytes from any peer that merged the block (request by CID) or from GlobalDB backup predating eviction; post-mortem the eligibility gate |
| Accepted-not-durable loss (P5) | HIGH | Restore s3d host staging if intact; else same as P4 for objects never transferred; re-evaluate flush policy |
| Resurrection (P6) | MEDIUM | Re-issue authoritative tombstone deltas (new higher-priority `DeleteKey` broadcasts); audit divergence via `QueryKeyValues` diff across nodes |
| Resolved-marker divergence (P7) | MEDIUM | Bulk rehydrate-from-cold for affected heads, rebuild resolved markers from completed walks; worst case re-walk from heads with fetch enabled |
| Blacklist poisoning from taxonomy collapse (P9) | LOW | Restart clears in-memory blacklist state; fix mapping; verify routes re-added by rebroadcast (routes are kept by design, `graphsync_dagsyncer.cpp:990-994`) |
| Journal divergence after GlobalDB backup-restore (Moderate 3) | MEDIUM | Prefer re-drain of the cold journal as-is; if impossible, rebuild journal from remote listing (CID-verified HEAD per object) |
| CI tier erosion (P12) | LOW | Re-label, re-gate; `tier1_audit`-style count guard if adopted on SuperGenius side |

## Moderate Pitfalls

### Moderate 1: Dual RocksDB versions in one process (MSVC static linking)
**What goes wrong:** SuperGenius links its RocksDB; LocalBlockStore embeds another (pimpl, dual-compat 9.4/11.1). Data separation is enforced (D-01) but MSVC static-link symbol collision is possible if versions diverge.
**Prevention:** Align thirdparty build's RocksDB to SuperGenius's; C1 exit test links one binary on all three platforms.
**Phase:** C1.

### Moderate 2: Teardown ordering — new threads vs store close
**What goes wrong:** Drainer (C2) and cold-fetch pool (C3) outliving `LocalBlockStore::Close`/GlobalDB teardown — v1.0's accepted W-1 (no post-Close guard on data-path methods) turns from latent to live crash. Precedent: the 2026-09-19 macOS teardown SIGABRT documented at `graphsync_dagsyncer.hpp:96-107`.
**Prevention:** Join new threads in the existing drain-then-stop sequence (`StopSyncerAfterWorkerDrain` ordering); crash-safety for in-flight work is otherwise journal-covered.
**Phase:** C2/C3 (as each thread lands), re-proven in C5.

### Moderate 3: GlobalDB backup engine blind to the cold tier
**What goes wrong:** `CreateBackupNow`/auto-restore (`globaldb.cpp:365-420`, `:250-282`) covers only GlobalDB's RocksDB. Restoring GlobalDB from backup while the cold store (separate directory, separate DB) is at a different point-in-time yields CRDT-state/journal divergence.
**Prevention:** Document; either back up the cold dir on the same schedule or declare the journal rebuildable (pending set re-derivable from remote listing / re-drain). Decide in C1, implement where decided.
**Phase:** C1 (decision), C4 (tooling if chosen).

### Moderate 4: `lru_cid_cache_` divergence after eviction
**What goes wrong:** In-memory LRU (`GrabCIDBlock`, `graphsync_dagsyncer.cpp:842`) says "have it" for a block whose RocksDB bytes were GC'd — serves from memory until LRU eviction, then flips to miss; window of inconsistent answers.
**Prevention:** GC calls `DeleteCIDBlock` (`:855`) for every evicted CID as part of the one-unit eviction (P7).
**Phase:** C4.

### Moderate 5: Concurrent drains racing the journal
**What goes wrong:** Two drain invocations (e.g., periodic service + manual ops trigger) interleave `GetPendingUploads`/`MarkUploadedAccepted` against a single-threaded-use contract (`UploadDrainer.hpp:75-85`).
**Prevention:** Single drainer owner (mutex or single-thread design); ops-triggered drain enqueues a request, doesn't run inline.
**Phase:** C2.

### Moderate 6: Spill-path log spam / hot-path cost
**What goes wrong:** Per-block info logs (pattern already present: topics logged at info in `CreateIPLDNode`, `crdt_datastore.cpp` ~1480) multiplied by spill/GC hooks drown logs and burn CPU on `toString`.
**Prevention:** Debug/trace with level guards for per-block events; info only for aggregates (per-batch counts, per-GC-pass summaries).
**Phase:** C2.

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| P1 Miss-as-absence | C3 | Fault-injected conformance test: cold-resident and TemporarilyUnavailable produce distinct, non-absence results at the DAGSyncer seam |
| P2 Sync spill blocking commits | C2 | Publish-latency benchmark with drainer paused == latency with drainer running; s3d-down soak: publishes keep succeeding |
| P3 Journal growth / backpressure | C2 (+C5) | Soak with s3d down: journal growth bounded by policy, alarm fires, no write failures; serialized drains proven |
| P4 Evict-before-accepted | C4 (+C5) | Fault test: failed/slow remote Put + GC pass ⇒ zero evicted pending bytes |
| P5 Accepted≠durable | C4 (+C5) | Policy doc (accepted-risk or flush-gated); staging disk-full scenario inhibits GC; loss-of-s3d-host recovery drill |
| P6 Tombstone purge/resurrection | C4 | Resurrection test: delete → GC → re-deliver pre-delete delta ⇒ key absent everywhere; tombstone rows untouched |
| P7 Heads/resolved divergence | C4 | Evict → restart → rebroadcast: walks complete via cold reads, no peer fetches for evicted CIDs, no silent resolved-skips |
| P8 Blocking responder | C3 (+C5) | Peer fetch of evicted block under injected s3d latency: node's other libp2p protocols unaffected; bytes CID-verified |
| P9 Taxonomy collapse / negative caching | C3 | Mapping-table conformance per StatusClass row via FaultController; no blacklist writes from storage failures |
| P10 Config semantics / credentials | C1 | Three-case config test (missing/blank/malformed); credentials-in-config rejected |
| P11 Restore re-entry | C3/C4 | Bulk restore emits zero pubsub broadcasts, zero AddRoute, heads unchanged |
| P12 Build/CI/submodules | C1 (+C5) | Fresh-clone (pushed commits only) Tier1-green on Win/Linux/macOS with option ON; every new test labeled/gated |
| P13 GC races | C4 (+C5) | Concurrent eviction × serving × draining under timing control: zero Corrupt-from-race, zero lost blocks |
| M1 Dual RocksDB | C1 | Three-platform link of one binary |
| M2 Teardown | C2/C3 (+C5) | Teardown-under-load test, no SIGABRT |
| M3 Backup blind spot | C1/C4 | Decision recorded; restore drill consistent across both stores |
| M4 LRU divergence | C4 | Evicted CID absent from LRU immediately post-GC |
| M5 Concurrent drains | C2 | Only one drain active under ops + timer triggers |
| M6 Log spam | C2 | Log-volume budget per 1k blocks spilled |

## Sources

- `supergenius-sharded-ipld-cache-architecture.md` — CRDT correctness invariants, read/write paths, durability levels, s3d operational implications, key risks (curated project doc; HIGH)
- `SuperGenius/src/crdt/crdt_datastore.hpp`, `impl/crdt_datastore.cpp` — write path, `Publish`/`AddDAGNode`/`WaitForJob` (lines cited above), worker architecture (repo code; HIGH)
- `SuperGenius/src/crdt/dagsyncer.hpp`, `graphsync_dagsyncer.hpp/.cpp` — serving path, `getNode`/`HasBlock`/`StartSync` responder comment, blacklist/backoff, LRU cache (repo code; HIGH)
- `SuperGenius/src/crdt/crdt_set.hpp` — Add-Wins Observed-Remove semantics, tombstone model (repo code; HIGH)
- `SuperGenius/src/crdt/globaldb/globaldb.{hpp,cpp}` — construction seam, BackupEngine restore/abort precedent (repo code; HIGH)
- `SuperGenius/src/account/GeniusNode.cpp` — `LoadCrdtConfig` silent-defaults pattern (:551-610), `RunResultGC` uncoordinated-eviction precedent (:4727-4810) (repo code; HIGH)
- `thirdparty/sgns-blockstore/include/sgns-blockstore/BlockStatus.hpp`, `Durability.hpp`, `LocalBlockStore.hpp`, `UploadDrainer.hpp` — taxonomy, durability ceiling, journal atomicity, drainer contract (library code + docs; HIGH)
- `thirdparty/sgns-blockstore/docs/s3d-durability.md`, `testing-tiers.md` — s3d staged-vs-durable evidence (committed spike artifacts), CI tier contract (library docs w/ committed evidence; HIGH)
- `.planning/workstreams/rocksdb-backup/milestones/v1.0-MILESTONE-AUDIT.md` — what v1.0 proved (21/21, W-1, AR-05-1, unpushed-commit tech debt, export seam) (curated audit; HIGH)
- `github.com/ipfs/go-ds-crdt` — upstream reference implementation: no production tombstone/history GC; `PurgeDAG` (#341) and follow-up fix (#344) are its only deletion-adjacent work (web; MEDIUM — supports P6 novelty claim only)
