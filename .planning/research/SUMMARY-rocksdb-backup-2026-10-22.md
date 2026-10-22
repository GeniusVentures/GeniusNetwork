# Project Research Summary

**Project:** rocksdb-backup v1.1 — SuperGenius Cold-Storage Integration & CRDT Garbage Collection
**Domain:** Blockchain node storage tiering (CRDT-over-IPFS node consuming a shipped content-addressed cold-store library)
**Researched:** 2026-10-22
**Confidence:** HIGH (all SuperGenius/thirdparty/library claims verified in-tree with file:line cites; external comparables MEDIUM, cross-checked; one LOW source flagged and immaterial)

**Milestone framing:** SuperGenius consumes the shipped `sgns-blockstore` v1.0 library — config-gated (`crdt_config.json` s3d fields, blank = disabled = current behavior), spill-on-write of every CRDT block, cold-store read fallback for graphsync serving + local reads, GC of all cold-eligible CRDT data past retention preserving retrievability. User decisions locked: spill-on-write (all blocks); GC scope = all cold-eligible CRDT data; retrieval = graphsync + local reads.

---

## Executive Summary

v1.1 is consumer-side integration of an already-proven library: the SuperGenius node gains a cold-storage tier (S3/s3d) behind its existing CRDT stack, with **zero changes to `GraphsyncDAGSyncer`, `CrdtDatastore`, `PubSubBroadcasterExt`, or ipfs-lite-cpp**. All four research files converge on the same shape: one `IpfsDatastore` decorator (`BlockStoreBackedIpfsDatastore`) at the single construction seam (`globaldb.cpp:329`) delivers spill-on-write, read fallback, and GC eviction for *every* block — writes serialize through `MerkleDagServiceImpl::addNode` → `set` and all reads (local + graphsync serving) resolve through `get` on the same object. Durability is journal-then-drain: `LocalBlockStore::Put` (one atomic RocksDB WriteBatch) inline on the write path, `UploadDrainer` on a dedicated thread mirroring the twice-proven `StartBackupLoop` pattern. When the config section is blank or absent, nothing is constructed and behavior is byte-identical to today.

Two facts about the library *as shipped* make a pure consumer-side plan impossible and force a Phase-0 library touch (additive, inside our own `thirdparty/sgns-blockstore` repo — not a new dependency): **(1)** every CRDT block CID is CIDv1/DAG_CBOR/**blake2b-256** (`cid.cpp:129-135`) but the library's API throws `std::invalid_argument` on any non-sha-256 multihash (`Cid.hpp:50-56`) — spill and fallback are both impossible until the hash gate is widened (the header itself says widening is additive); **(2)** the production `MinioS3Client` impl header is not installed, so SuperGenius cannot construct the real client — an installed factory (e.g. `OpenMinioS3Client` declared in `S3Client.hpp`) is required. Build wiring is likewise non-trivial: `find_package(sgns-blockstore CONFIG REQUIRED)` in **both** `CommonBuildParameters.cmake` files, placed **after** the miniocpp dependency chain (the static-lib `$<LINK_ONLY:miniocpp>` export fails configure otherwise), mirroring the AsyncIOManager pattern.

The dominant risks are all integration-layer: an inline S3 PUT inside `set` would stall every block add and every read (the path holds `dagMutex_`); a cold-tier miss misread as authoritative absence poisons `HasBlock`, peer blacklists, and CRDT convergence (the #1 pitfall in every comparable system); evicting local bytes before remote durability is *proven* loses data silently (s3d's `ObjectStoreAccepted` ≠ durable — no per-object signal exists in v0.2.1); and purging CRDT tombstones resurrects deleted values irrecoverably. Mitigations are converged: journal-then-drain (never inline S3), a first-class `BlockStatus`-taxonomy mapping table at the seam (transport failure is never NotFound), an explicit eviction durability gate (flush + `pendingObjects==0` → `MarkUploadedDurable`, or a documented accepted-risk), and **v1.1 GC = local eviction only** — block bytes evicted, tombstones/CRDT metadata never touched, bounded disposed-CID markers kept for authoritative-NotFound, epoch compaction deferred to v2+. The comparable-system survey backs this: go-ds-crdt (the reference impl SuperGenius's CRDT is modeled on) ships **no** tombstone GC at all, and the Merkle-CRDT paper says true deletion requires replica-set knowledge or a blockchain anchor — which SuperGenius has, but only for v2+.

---

## Key Findings

### Recommended Stack

No new external dependencies anywhere — v1.1 consumes the shipped chain (`sgns-blockstore::sgns-blockstore` + its transitive closure) via the thirdparty superbuild install tree. The consumer-side CMake block (explicit `*_DIR` hints for pugixml → nlohmann_json → htttplib → miniocpp → sgns-blockstore, in that order, outside the libssh2 `PREFER_CONFIG` window) is fully specified in STACK.md with verified paths; the identical block goes into `GeniusSDK/cmake/CommonBuildParameters.cmake` (SDK statically links the node lib, so its final executables must resolve the same imported targets).

**Core technologies:**
- `sgns-blockstore::sgns-blockstore` (namespaced export, v1.0.0) — the cold tier behind the frozen `BlockStore` contract; link only this target, never miniocpp directly (`$<LINK_ONLY:...>` propagates the SDK — SC2 containment).
- `find_package(... CONFIG REQUIRED)` against the superbuild install tree — the repo's universal consumption pattern (rocksdb, libp2p, ipfs-lite-cpp all work this way); `add_subdirectory`/`FetchContent` explicitly rejected.
- `crdt_config.json` new `blockstore` (a.k.a. `s3d`) section — blank/absent = disabled; maps 1:1 onto `S3ClientConfig`/`S3BlockStoreOptions`/`LocalBlockStoreOptions`; follows the `LoadCrdtConfig` precedent (`GeniusNode.cpp:552-610`).
- Env overrides `SGNS_BLOCKSTORE_S3_ACCESS_KEY`/`_SECRET_KEY` (+ optionally `_ENDPOINT`/`_BUCKET`) — secrets never logged; config log line prints endpoint/bucket, redacts keys.
- `MemoryBlockStore` (installed header) — the cold-tier fake for all SuperGenius-side wrapper tests; hermetic CI stays hermetic (no Docker in runners; live s3d stays dev-gated Tier-3).
- `UploadDrainer` + `LocalBlockStore` journal — shipped, crash-safe, idempotent; v1.1 wraps the one-shot drain on a periodic cadence.

**Critical version/constraint notes:** library `outcome` results use `policy::terminate` — unchecked `.value()` on an error **terminates the node**; always guard `has_value()` first and convert by extracting value/error. Dual RocksDB (9.4/11.1) accepted via no-version `find_dependency`; MSVC static runtime matches on both sides today; never re-resolve or bump the miniocpp chain pins independently.

### Expected Features

**Must have (table stakes, v1.1 = all P1):**
- sgns-blockstore blake2b-256 CID widening (+ `dag-cbor` S3 key codec token) — the enabler for everything
- `BlockStoreBackedIpfsDatastore` adapter at the `globaldb.cpp:329` seam — the single highest-leverage artifact
- Config-gated construction (blank = disabled = byte-identical behavior; malformed = loud, not silent-default)
- Spill-on-write of every CRDT block (journal-backed, crash-safe)
- Periodic background drainer (timer-driven, one drain in flight, shutdown = stop-and-resume via journal, pending-set visibility)
- Cold read fallback covering graphsync serving *and* local reads through the one adapter
- Authoritative-miss vs transport-failure taxonomy preserved across the seam
- Retention GC of cold-eligible data: age + size dual trigger (in-house `RunResultGC` precedent), oldest-first, protected namespaces (heads/genesis/current pointers), per-pass metrics
- Disposed-CID local tombstones (bounded) — authoritative NotFound after disposal, dedup of re-broadcast heads
- Epoch watermark record (min-head-height floor, computation only, no deletion gated on it yet)

**Should have (differentiators — v1.x after validation):**
- Request coalescing + brief authoritative-only negative cache + staggered peer-vs-cold race
- Backpressure: staging-disk cap inhibiting new spills + alerting (never fail the consensus write)
- Admin flush command (blocking drain) and quiesced whole-namespace purge tool (PurgeDAG lessons: heads last, resumable)
- Per-namespace retention classes

**Defer (v2+):**
- Consensus-anchored epoch compaction + checkpoint bootstrap (the paper's blockchain-anchored deletion — SuperGenius has the anchor; needs epoch snapshot format, restore path, below-watermark delta rejection, protocol bump)
- Tombstone-metadata compaction below a *proven-stable* watermark; cold-store-side (S3) reclamation (no Delete exists on the frozen contract, by design); CARv2 packing

**Anti-features (research is explicit — do not build):** tombstone purge by age (forbidden by the architecture doc; go-ds-crdt ships none deliberately); `Delete/Remove` on `BlockStore` (contract permanence, CORE-05/06); cache-miss-as-absence; treating s3d accepted-as-durable; GC/drainer on CRDT worker or pubsub asio threads; unbounded in-memory scan sets.

### Architecture Approach

One decorator, one thread pattern, one GC rule. The write path (`GlobalDB::Put` → `Publish` → DAG worker → `addNode` under `dagMutex_` → `MerkleDagServiceImpl::addNode` → `set`) and both read paths (graphsync responder `graphsync_impl.cpp:374`; local `GetNodeFromMerkleDAG` `graphsync_dagsyncer.cpp:1006`) all funnel through the single `IpfsDatastore` — so the decorator at `globaldb.cpp:329` captures everything with one wiring change. Spill journals locally inline (fast WAL commit) and never touches the network on the hot path; a dedicated drain thread (backup-loop precedent, never `io_` and never the pubsub asio context — that context serves graphsync and must not block) uploads in the background; startup reconciles `GetPendingUploads` crash leftovers. GC touches **only the block-bytes keyspace** of the CRDT RocksDB (raw `cid.toBytes()` keys), gated on (retention age) ∩ (¬reachable from current heads) ∩ (`UploadedDurable`), executing as `remove` hot copy + `EvictLocal` cold copy — the S3 object is never deleted, and the `/crdt/s`, `/crdt/t`, `/crdt/k`, `/crdt/h` metadata keyspaces are never enumerated or written by GC.

**Major components:**
1. `sgns-blockstore` v1.1 (library, additive) — blake2b-256 widening, dag-cbor key token, installed `OpenMinioS3Client` factory, optional `config.cmake.in` dependency hardening
2. `BlockStoreBackedIpfsDatastore` (NEW, SuperGenius, `src/crdt/globaldb/`) — spill-on-`set`, fallback-on-`get`, pass-through `contains`/`seal`/`is_sealed`; `remove` = hot-only (eviction ≠ CRDT deletion)
3. `ColdStorageManager` (NEW, may live inside GlobalDB) — owns `LocalBlockStore` + `S3BlockStore`, drainer thread, flush/durability cadence, GC pass; lifecycle mirrors `StartBackupLoop`/`ShutdownNow`
4. `GlobalDB::New/Init/Start/ShutdownNow` (MODIFIED) — `ColdStorageOptions` param, wrapper construction at :329, thread start/join ordering
5. `GeniusNode::LoadCrdtConfig` + `InitDatabase` (MODIFIED) — config parse, credential resolution, options threading
6. GC scheduler (NEW) — retention pass with reachability pinning and two-phase eviction
7. Build files (MODIFIED) — `SuperGenius/build/CommonBuildParameters.cmake`, `GeniusSDK/cmake/CommonBuildParameters.cmake`, `SuperGenius/src/crdt/CMakeLists.txt`; `GeniusWallet/assets/crdt_config.json` schema parity

### Critical Pitfalls

1. **Cold-tier miss read as authoritative absence (P1)** — `DAGSyncer` has only have-it/error outcomes; a collapsed mapping re-requests owned CIDs (fetch storms), serves failed roots, and can diverge nodes. Avoid: cold-resident = distinct state; only authoritative cold `NotFound` may surface as not-found; fault-injected conformance test that no NotFound-shaped result escapes under transport faults.
2. **Synchronous spill on the commit path (P2)** — `set` runs under `dagMutex_`; inline S3 makes a storage outage a consensus outage (20-min `WaitForJob` deaths). Avoid: journal-then-drain only; publish latency must be independent of drainer/s3d state (benchmark proves it).
3. **Evicting before durability is proven (P4+P5)** — s3d `ObjectStoreAccepted` = staged on the s3d host, not durable; no per-object signal exists. Avoid: eviction eligibility consults journal state in the same critical section; durability bar = flush + `pendingObjects==0` → `MarkUploadedDurable` (or a documented accepted-risk with s3d staging on separate storage); GC inhibited while staging is unhealthy.
4. **Tombstone purge → resurrection (P6)** — AWORset tombstones are the only thing hiding old elements; purging them lets any re-delivered delta resurrect deleted values with no CRDT-internal fix; the reference impl ships none and even its admin PurgeDAG needed a follow-up fix. Avoid: hard scope boundary — v1.1 GC never touches tombstone/metadata rows; resurrection test in the plan; epoch compaction only in v2+ behind a causal-stability spec.
5. **Blocking the graphsync responder on cold fetches (P8)** — the responder deliberately serves only from the local store; naive sync fallback freezes all libp2p stream processing. Avoid: cold serves on a bounded dedicated executor with deadline < peer stream timeout, results posted back asynchronously (or consciously answer "don't have" + re-warm); CID-verify before serving.
6. **Build/CI traps (P12)** — unpushed commits across three repos at v1.0 close; hard-required `find_package` breaks fresh clones; no Docker in CI; unlabeled tests silently never run. Avoid: gate the two `find_package` calls behind an option (default OFF until submodules are pinned/pushed; OFF on IOS/ANDROID unless a mobile leg is verified); tier labels + loud skips from day one; fresh-clone Tier1-green exit criterion.

Also load-bearing: taxonomy collapse → peer-blacklist poisoning (P9), GC racing in-flight reads/drains (P13 → two-phase eviction), restored blocks re-entering the pubsub pipeline (P11 → dedicated rehydrate API, zero broadcast), config tri-state semantics + credentials (P10), teardown ordering under load (M2), dual RocksDB in one MSVC binary (M1), GlobalDB backup blind to the cold dir (M3), LRU divergence after eviction (M4 → `DeleteCIDBlock` on evict).

---

## Implications for Roadmap

The two phase-numbering schemes in the research (ARCHITECTURE's 0–6, PITFALLS' C1–C5) merge cleanly into **one build order, Phases 0–6**. Dependency logic: the library must accept real CRDT CIDs before SuperGenius can link a spilled block (0) ⇒ build wiring + the config gate before any behavior (1) ⇒ spill fills S3 before fallback can read it (2→3) ⇒ the durability gate must be real before anything deletes (4) ⇒ GC strictly last — it depends on fallback for retrievability and on the journal for its safety gate (5) ⇒ cross-cutting fault-injection/fresh-clone proof caps the milestone (6).

### Phase 0: sgns-blockstore v1.1 — CRDT-CID support & installed client factory
**Rationale:** Hard blocker, verified in all four files: CRDT CIDs are blake2b-256 (`cid.cpp:129-135`) and the v1 API throws on non-sha-256 (`Cid.hpp:50-56`); independently, `MinioS3Client.hpp` is not installed so no consumer can build the production client. Both fixes are additive and library-only — zero SuperGenius coupling, conformance kit extends naturally.
**Delivers:** blake2b-256 widening (verify-on-put/get against the CID's own multihash), `dag-cbor` codec token in the S3 key layout, installed `OpenMinioS3Client(const S3ClientConfig&)` factory in `S3Client.hpp`, optional `find_dependency` hardening in `config.cmake.in`, conformance cases with blake2b DAG_CBOR CIDs.
**Addresses:** the enabler feature (P1 in FEATURES' matrix); STACK Constraints A/B/C.
**Avoids:** Anti-Pattern 4 (spilling before the gate is widened — first block would throw); SC2 containment breach (factory keeps minio-cpp types out of installed headers).
**Decisions for the planner:** widen to *exactly* blake2b-256 or a general multihash set; S3 key-layout compatibility (moot — no sha-256 objects in production yet, so the layout is free to change).

### Phase 1: Build wiring + config gate & options plumbing
**Rationale:** Nothing compiles without the find_package chain, and the gate must exist before the gated feature; merging ARCH's phases 1–2 matches PITFALLS' C1 scope exactly (both are "make it exist, off by default").
**Delivers:** the CMake block in both `CommonBuildParameters.cmake` files (explicit `*_DIR` hints, after the miniocpp chain, outside the PREFER_CONFIG window, optionally gated `SGNS_COLD_STORAGE` OFF-by-default and OFF on mobile until verified); `ColdStorageOptions`; `LoadCrdtConfig` extension with strict tri-state semantics (absent section → off; blank → off; present-but-malformed → **fail loud**, an explicit decision — not the legacy silent-defaults pattern); credential resolution (env `SGNS_BLOCKSTORE_S3_*` overrides config; never logged); threading through `GlobalDB::New`; wallet asset schema parity; the M3 decision (back up the cold dir on the same schedule, or declare the journal rebuildable).
**Uses:** AsyncIOManager consumption pattern; `LoadCrdtConfig` precedent; `GeniusWallet/assets/crdt_config.json` distribution model.
**Avoids:** P10 (silent-disable, blank-vs-missing confusion, credentials in plaintext-and-logged), P12 (fresh-clone breakage, unlabeled tests), M1 (dual-RocksDB link proof on all three platforms).
**Decision for the planner:** canonical section name (`blockstore` per STACK's schema vs `s3d.*` per ARCH's shorthand — semantics identical; pick one and use it everywhere).

### Phase 2: Spill-on-write + background drainer
**Rationale:** Fills S3 first; the adapter's `set` path and the drain service are one risk unit; fallback (Phase 3) needs content to fall back to.
**Delivers:** `BlockStoreBackedIpfsDatastore::set` (inner RocksDB write + gated `LocalBlockStore::Put` journal spill), `ColdStorageManager` drainer thread (backup-loop pattern; **neither** `io_` **nor** the pubsub asio context), startup `GetPendingUploads` reconciliation, shutdown stop-and-resume ordering in `ShutdownNow`, backpressure policy (chosen explicitly: unbounded-journal+watermark+alarm, or bounded-degrade — never fail the consensus write), serialized single drain (ops-triggered drains enqueue, never run inline), pending-count/bytes/oldest-age metrics.
**Implements:** Architecture Patterns 2 (journal-then-drain) and 3 (backup-loop thread).
**Avoids:** P2 (publish latency coupled to s3d — benchmark with drainer paused vs running), P3 (unbounded journal growth during s3d outage — soak test), M5 (concurrent drains), M6 (per-block log spam), M2 (teardown join ordering).

### Phase 3: Cold read fallback — local reads + graphsync serving
**Rationale:** With S3 filling, the `get` path becomes testable end-to-end; the state model here (cold-resident, unknown-vs-absent) must be designed *before* GC makes misses common.
**Delivers:** `get` = inner miss → `LocalBlockStore` → `S3BlockStore` (CID-verified) → re-cache → serve; cold-aware `HasBlock` ("have locally OR retrievable before deadline"); the first-class `BlockStatus` mapping table (NotFound → may-be-absence; TemporarilyUnavailable → unknown, no blacklist writes, no `RecordCIDFailure`; Corrupt → attribute + alarm; Unauthorized → ops alarm); responder cold-fetches on a bounded dedicated executor with deadline (or the conscious "don't-have + re-warm" degradation); dedicated rehydrate API (bytes + resolved marker only — zero pubsub broadcast, zero `AddRoute`, heads unchanged).
**Avoids:** P1 (miss-as-absence), P8 (responder freeze), P9 (blacklist poisoning from s3d blips), P11 (restore re-entry storms).
**Decision for the planner:** cold-serve latency budget on the responder path — measure before enabling by default.

### Phase 4: Durability advancement & lifecycle hardening
**Rationale:** The eviction gate must be real before GC exists; this makes `UploadedDurable` an honest state rather than an assumption.
**Delivers:** flush cadence (admin `POST /objects/flush`, bucket-scoped and blocking — acknowledged cost) + observe `pendingObjects==0` → bulk `MarkUploadedDurable`; the documented durability-bar policy; fault injection for crash-between-journal-and-drain and s3d-outage ≠ NotFound; drainer/GC/backup-loop shutdown interplay; staging-health monitoring (`pendingObjects`/`bufferUsed`/`bufferLimit`) wired to inhibit later GC.
**Avoids:** P5 (accepted-as-durable correlated loss), M2 (teardown under load), the v1.0 W-1 latent crash window becoming live.

### Phase 5: GC of cold-eligible CRDT data
**Rationale:** Strictly last: depends on Phase 3 for retrievability and Phase 4 for its safety gate — evicting before either exists destroys data. It is also the only phase that removes anything anywhere.
**Delivers:** retention scan over the spilled-CID index ∩ age-past-retention ∖ reachable(`CrdtHeads::GetList` → link walk) ∩ `UploadedDurable` → `remove` + `EvictLocal`; age + size dual trigger, oldest-first, batched off `io_`; protected/pinned namespaces (heads, genesis, current-epoch pointers); **disposed-CID local tombstones** (bounded, own retention — they are node-local disposal records, not CRDT tombstones); two-phase eviction (mark-as-evicting checked by readers and drain snapshots → grace → physical delete) + `DeleteCIDBlock` LRU invalidation; per-pass reclaimed counts/bytes + dry-run mode; the epoch watermark record (computation only, no deletion gated on it); restore runbook + drill.
**Avoids:** P4 (evict-before-accepted), P6 (tombstone purge/resurrection — hard scope boundary recorded in the SPEC), P7 (resolved-marker/bytes divergence — evict as one unit), P13 (mid-read/mid-drain races), M4 (LRU divergence).
**Decisions for the planner:** retention age evidence (priority-height vs wall-clock vs per-namespace app-level horizon); eviction durability bar if not settled in Phase 4; reachability-walk cost model and batching.

### Phase 6: Integration hardening, fault injection & fresh-clone proof
**Rationale:** Mirrors v1.0's Phase 5 discipline; the cross-cutting races (eviction × serving × draining under timing control) can only be proven once all actors exist.
**Delivers:** the full fault-kit reuse (`FaultController` timing injection: zero Corrupt-from-race, zero lost blocks, zero blacklist writes from storage failures); resurrection test (delete → GC → re-deliver pre-delete delta ⇒ absent everywhere); s3d-down soak (bounded journal, alarm fires, publishes keep succeeding); peer cold-fetch under injected s3d latency; teardown-under-load; fresh-clone (pushed commits only) configure+build+`ctest -L Tier1` green on Windows/Linux/macOS with the option ON; every new test labeled and gated.
**Avoids:** P12 (tier-label drift, submodule unpinned), every "Looks Done But Isn't" checklist item in PITFALLS.md.

### Phase Ordering Rationale

- **Library before consumer (0→1):** the CID gate throws on the very first CRDT block; no SuperGenius code can so much as link a spilled block before it.
- **Existence before behavior (1→2):** the config gate and build chain must precede any gated feature; blank-must-mean-disabled is itself a Phase-1 deliverable.
- **Fill before read (2→3):** fallback needs S3 content to fall back to; both live in one adapter but ship as separate phases for risk isolation.
- **Gate before delete (4→5):** GC's eligibility check consumes the durability journal; Phase 4 makes that state honest, Phase 5 consumes it.
- **Delete last, prove at the end (5→6):** GC is the only destructive phase and depends on both prior directions; the milestone capstone proves the cross-phase races.
- **Grouping by architecture:** Phases 2–4 all live in the adapter + manager pair (one seam, three behaviors, shipped incrementally); Phase 0 stays library-only so it can land and be verified independently.

### Research Flags

Phases likely needing deeper research during planning (`/gsd-plan-phase --research-phase`):
- **Phase 3:** responder-side async cold serving is novel in this codebase (the current responder is deliberately local-only); needs the executor/deadline design explored and the latency budget measured. The exact `IpfsRocksDb` block-key layout (prefix/CF inside the shared DB) is unenumerated and needed for adapter scans.
- **Phase 5:** the most novel phase — reachability-walk cost model (O(history), batching, scheduling), age-evidence semantics (priority-height vs wall-clock), disposed-CID marker column-family design, two-phase eviction. No proven recipe exists upstream (go-ds-crdt ships none; PurgeDAG is admin-only and needed a follow-up fix).
- **Phase 4 (light):** flush-cadence cost vs `MarkUploadedDurable` batching policy against s3d's bucket-scoped blocking flush — a design note, not a full research pass.

Phases with standard patterns (skip research-phase):
- **Phase 0:** the library's own conformance kit and decision framework already specify how additive widening is tested.
- **Phase 1:** AsyncIOManager consumption pattern + `LoadCrdtConfig` precedent, both fully cited with file:line in STACK.md.
- **Phase 2:** backup-loop thread pattern is twice-proven in `globaldb.cpp:429-477`; the journal and drainer semantics are shipped library contracts.
- **Phase 6:** v1.0's fault kit, tier contract, and evidence-capture habits are directly reusable.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Build mechanism, exported-target names, install-tree layout, config seam all verified in-tree with file:line cites; sole MEDIUM: mobile superbuild leg coverage unverified |
| Features | HIGH | SuperGenius-internal grounding read directly from code; comparables (go-ds-crdt, s3d, IPFS, Yorkie) MEDIUM but cross-checked ≥2 sources; one LOW source (ralph/ORDHMap) immaterial to the converged decision |
| Architecture | HIGH | Every seam/mutex/thread claim read from the tree this session; s3d durability facts trace to committed evidence (`s3d-durability.md`) |
| Pitfalls | HIGH | Repo and library evidence cited per claim; the one external claim (go-ds-crdt has no tombstone GC) is MEDIUM/web but corroborated by first-party repo + PR history |

**Overall confidence:** HIGH — the research is unusually convergent: all four files independently identified the same seam, the same blocker, the same drain discipline, and the same GC scope boundary.

### Gaps to Address

Genuinely open — preserve for planner/user decisions:

- **blake2b widening vs dual-CID mapping:** research unanimously recommends widening (dual-CID violates "the CID is authoritative" and complicates GC); open sub-question = which multihashes beyond blake2b-256 and the S3 key-layout token change. Decide in Phase 0's SPEC.
- **Retention age evidence:** priority-height (monotonic per-topic, already in `/crdt/h`) vs wall-clock vs per-namespace app-level horizon — priorities are not timestamps, so height-based retention needs a mapping decision. Phase 5.
- **Graphsync cold-serve latency budget:** unmeasured; the design (async executor vs don't-have+re-warm) should not be locked before measurement. Phase 3.
- **Mobile superbuild leg coverage:** unverified whether iOS/Android legs produce the sgns-blockstore + minio-cpp install trees; until verified, gate the find_package calls OFF on mobile (desktop-first is the honest v1.1 posture — cold storage is a node-operator feature). Phase 1.
- **GlobalDB backup vs cold-store dir:** the backup engine is blind to the cold journal (M3) — either co-schedule a backup of the cold dir or declare the journal rebuildable (re-drain / CID-verified remote listing). Phase 1 decision, Phase 5 tooling if chosen.
- **Eviction durability bar:** flush-gated (safe, blocking) vs accepted-risk with separate staging storage (fast, operational exposure) — the v1.0 AR-05-1 accepted-risk pattern exists if chosen. Phase 4/5.
- **Backpressure policy:** unbounded-journal+alarm vs bounded-degrade (hot-only until drained). Phase 2.
- **Config section naming:** `blockstore` (STACK schema) vs `s3d.*` (ARCH shorthand) — same semantics, pick one canonically across node + wallet assets. Phase 1.
- **`IpfsRocksDb` key layout enumeration:** needed before adapter spill/GC scans are written. Phase-local research, Phase 2/5.
- **ralph/ORDHMap primary source** (LOW, unreached): immaterial — the GC decision converges on eviction-only regardless; do not spend planner time on it.

---

## Sources

Aggregated from the four research files (full per-claim citations live there).

### Primary (HIGH confidence — read directly from this tree, 2026-10-22)
- `SuperGenius/src/crdt/**` — write path (`crdt_datastore.cpp` Publish/AddDAGNode/WaitForJob/DAG worker), serving path (`graphsync_dagsyncer.cpp` addNode/getNode/HasBlock/StartSync responder comment/blacklist/LRU/TraverseCIDsLinks), `crdt_set.hpp` AWORset + keyspaces, `crdt_heads.hpp` heights, `globaldb.cpp` construction seam :322-365, backup loop :429-477, ShutdownNow :113-135
- `thirdparty/sgns-blockstore/**` — frozen v1.0 contract (`BlockStore`, `LocalBlockStore`, `S3BlockStore`, `UploadDrainer`, `BlockStoreTooling`, `Cid`, `Durability`, `BlockStatus`), CMake export/install rules, `docs/s3d-durability.md` (committed spike evidence), `docs/testing-tiers.md`
- `thirdparty/ipfs-lite-cpp/**` — `IpfsDatastore` interface, `getCidOf` = CIDv1/DAG_CBOR/blake2b-256 (`cid.cpp:129-135`), `merkledag_service_impl.cpp` addNode→set / getNode→get
- `SuperGenius/build/` + `GeniusSDK/cmake/` + `thirdparty/build/CommonTargets.cmake` — consumption patterns, superbuild entries, PREFER_CONFIG trap, install-tree config dirs
- `SuperGenius/src/account/GeniusNode.cpp` — `LoadCrdtConfig` :552-610, `StartResultGC`/`RunResultGC` :4674-4805, retention config, io_context precedents
- `supergenius-sharded-ipld-cache-architecture.md` — CRDT correctness invariants, read/write paths, durability levels, credential guidance
- `.planning/workstreams/rocksdb-backup/` — v1.0 REQUIREMENTS (deferred wiring), v1.0 MILESTONE-AUDIT (W-1, AR-05-1, unpushed-commit debt), STATE.md v1.1 context

### Secondary (MEDIUM confidence — first-party external, fetched directly)
- `github.com/ipfs/go-ds-crdt` + PR #341/#344 — reference impl ships no tombstone GC; PurgeDAG semantics and review hazards (resurrection, heads-last, resumable, memory bounds)
- Merkle-CRDTs paper (arXiv 2004.00107, Sec. VI-B) — DAG GC requires replica-set knowledge or a blockchain source of truth; snapshot-beats-replay
- Sia `s3d` README — upload packing loop, `uploadDeadline`/`uploadThreads`/`diskUsageLimit`/flush/metrics lifecycle model
- IPFS persistence/pinning docs — pin-based GC, size watermarks, negative-result discipline
- Yorkie GC design (repo-derived wiki) — min-version-vector tombstone purge over *active* members (needs a coordinator SuperGenius won't have until epochs)

### Tertiary (LOW confidence)
- ralph/ORDHMap — primary repo unreachable; mechanism inferred from cross-checked secondary sources; immaterial to the converged eviction-only decision

---
*Research completed: 2026-10-22*
*Ready for roadmap: yes*
