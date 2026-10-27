# Roadmap: rocksdb-backup

## Milestones

- ✅ **v1.0 CRDT Cold-Storage BlockStore Library (Sia s3d backend)** — Phases 1-5, 21/21 requirements (shipped 2026-10-22) — archive: [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md)
- 🚧 **v1.1 SuperGenius Cold-Storage Integration & CRDT Garbage Collection** — Phases 6-12, 15/15 requirements mapped (roadmap created 2026-10-22)

<details>
<summary>✅ v1.0 CRDT Cold-Storage BlockStore Library (Phases 1-5) — SHIPPED 2026-10-22</summary>

- [x] Phase 1: BlockStore Contract, Memory Backend & Conformance Kit (3/3 plans) — completed 2026-10-20
- [x] Phase 2: LocalBlockStore (RocksDB Cold Tier) (3/3 plans) — completed 2026-10-20
- [x] Phase 3: minio-cpp Integration & S3Client Adapter (4/4 plans incl. 03-04 gap closure) — completed 2026-10-21
- [x] Phase 4: S3BlockStore & Sia s3d Roundtrip (3/3 plans) — completed 2026-10-22
- [x] Phase 5: Fault Injection & Three-Tier Hardening (3/3 plans) — completed 2026-10-22

Full phase details, plans, and success criteria: [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md)
Requirements (21/21 complete): [milestones/v1.0-REQUIREMENTS.md](milestones/v1.0-REQUIREMENTS.md)
Milestone audit (passed): [milestones/v1.0-MILESTONE-AUDIT.md](milestones/v1.0-MILESTONE-AUDIT.md)

</details>

## Phases (v1.1 — active)

- [x] **Phase 6: sgns-blockstore v1.1 Library Prerequisites — blake2b-256 CIDs & Installed S3 Client Factory** - Remove the two hard blockers additively: the CID hash gate widened to accept blake2b-256 (the shape of every CRDT DAG block) and an installed `OpenMinioS3Client` factory (completed 2026-10-22)
- [x] **Phase 7: SuperGenius Build Wiring & Config Gate** - Both `CommonBuildParameters.cmake` files resolve sgns-blockstore from the install tree; the `crdt_config.json` blockstore section defines the blank=disabled / malformed=loud contract; hermetic Tier-1 CI lane from day one (completed 2026-10-23)
- [x] **Phase 8: Spill-on-Write & Background Drainer** - Every CRDT block Put journals locally at the `IpfsDatastore` seam (no remote I/O under `dagMutex_`); a dedicated drainer thread uploads to S3 with crash-resume and an explicit backpressure policy (completed 2026-10-23)
- [x] **Phase 9: Cold Read Fallback — Local Reads & Graphsync Serving** - Hot-store misses fetch Local→S3 with CID-verify and re-cache; graphsync serves cold CIDs asynchronously off the responder's inline path; transport failure never surfaces as NotFound (completed 2026-10-26)
- [x] **Phase 10: Flush-Gated Durability Advancement** - `Durable` becomes an evidence-backed state (s3d `/objects/flush` + `pendingObjects==0` → `MarkUploadedDurable`), making the eviction durability gate real before anything deletes (completed 2026-10-26)
- [ ] **Phase 11: Retention GC of Cold-Eligible CRDT Data** - Eviction-only GC behind durability + non-reachability gates with bounded disposed-CID markers; evicted CIDs stay retrievable end-to-end; live s3d spill→GC→retrieve evidence (dev-gated)
- [ ] **Phase 12: Integration Hardening, Fault Races & Fresh-Clone Proof** - Evict×serve×drain races, resurrection counter-test, s3d-down soak, and fresh-clone Tier-1 green on Windows/Linux/macOS with cold storage ON

## Phase Details (v1.1)

### Phase 6: sgns-blockstore v1.1 Library Prerequisites — blake2b-256 CIDs & Installed S3 Client Factory

**Goal**: The shipped library accepts every CID the SuperGenius CRDT DAG actually produces and lets any consumer construct the production S3 client from the install tree — both integration blockers removed additively, library-only, with the conformance kit extended as the proof instrument
**Depends on**: Nothing within v1.1 (first v1.1 phase; builds on the shipped v1.0 library)
**Requirements**: LIB-01, LIB-02
**Success Criteria** (what must be TRUE):
  1. A CIDv1/DAG_CBOR/blake2b-256 block — the exact shape `getCidOf` gives every CRDT block — round-trips Put→Get byte-identical and CID-verified through sgns-blockstore, proven by known blake2b-256/DAG_CBOR vectors added to the conformance kit and run green against Memory, Local, and S3 backends
  2. Verify-on-put/get checks bytes against the CID's own multihash for both sha-256 and blake2b-256 — a byte-flipped blake2b block is rejected as `Corrupt` with source attribution — and the S3 key layout gains the `dag-cbor` codec token, observable by inspecting stored object keys
  3. No public-API break: all v1.0 sha-256 conformance, guard, and hygiene tests pass unchanged, and no installed header gains a minio-cpp/SDK type (existing compile-time checks stay green)
  4. `OpenMinioS3Client(const S3ClientConfig&)` is declared in installed `S3Client.hpp`, and an out-of-tree consumer TU constructs the production client linking only `sgns-blockstore::sgns-blockstore` from the install tree (compile+link proof)

**Plans**: 3/3 plans complete
Plans:
**Wave 1**
- [x] 06-01-PLAN.md — blake2 build wiring (ipfs-lite-cpp::blake2 link + superbuild entry) + 3-arg `CidOf` overload with pinned known vectors and committed `getCidOf` cross-check evidence (LIB-01)

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 06-02-PLAN.md — blake2b-256 hash-gate widening in the three backends (gates to exactly {sha-256, blake2b-256}, verify against the CID's own multihash on put/get, `dag-cbor` S3 key codec token, conformance-kit + guard-test extension/retarget) (LIB-01)

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 06-03-PLAN.md — Installed `OpenMinioS3Client` factory in `S3Client.hpp` + install-tree out-of-tree consumer compile/link/construct proof (Tier-1 hermetic ctest) + `config.cmake.in` find_dependency hardening exactly as the proof forces (LIB-02)

**Research note**: standard pattern — the library's own conformance kit and decision framework specify how additive widening is tested; no research-phase needed. Planner decisions: widen to exactly blake2b-256 vs a general multihash set; the S3 key-layout token change is free (no sha-256 production objects exist yet).

### Phase 7: SuperGenius Build Wiring & Config Gate

**Goal**: The integration exists and is off by default — SuperGenius and GeniusSDK resolve sgns-blockstore through the superbuild install tree, and the `crdt_config.json` blockstore section establishes the blank=disabled / malformed=loud contract every subsequent phase builds on, with the hermetic Tier-1 CI lane in place from day one
**Depends on**: Phase 6
**Requirements**: INTG-01, INTG-02, TEST-01
**Success Criteria** (what must be TRUE):
  1. A fresh configure+build on all desktop platforms resolves sgns-blockstore via `find_package(sgns-blockstore CONFIG REQUIRED)` in both `CommonBuildParameters.cmake` files (explicit `*_DIR` hints, ordered after the miniocpp dependency chain, outside the libssh2 `PREFER_CONFIG` window) and links `sgns-blockstore::sgns-blockstore` — dual RocksDB (9.4/11.1) coexistence proven in one binary on Windows/Linux/macOS; the option is OFF by default and OFF on iOS/Android until mobile install trees are verified
  2. With the blockstore section blank or absent, node behavior is byte-identical to today — no blockstore constructed, no new code paths taken — proven by a hermetic config-gate test
  3. A present-but-malformed section fails startup loudly with a precise message (never a silent disable); `SGNS_BLOCKSTORE_S3_ACCESS_KEY`/`_SECRET_KEY` env vars take precedence over config values; a log-scan test proves credentials are never printed (endpoint/bucket logged, keys redacted)
  4. TEST-01 anchor: hermetic Tier-1 SuperGenius-side tests (InMemoryS3Client fake; config-gate cases first) run under `ctest -L Tier1 --no-tests=error` fail-closed on all platforms — no Docker, no live endpoints — and every subsequent phase lands its tests in this lane

**Plans**: 3/3 plans complete
Plans:
**Wave 1**
- [x] 07-01-PLAN.md — Gated CMake consumption block in both `CommonBuildParameters.cmake` files (`SGNS_COLD_STORAGE` default OFF, FORCE-off on iOS/Android, hints + httplib→miniocpp→sgns-blockstore finds outside the PREFER_CONFIG window) + Windows ON-build one-binary link proof + dual-RocksDB no-pin/no-second-archive evidence + thirdparty-tarball CI-readiness verdict (INTG-01)

**Wave 2** *(blocked on Wave 1)*
- [x] 07-02-PLAN.md — `ColdStorageOptions` + strict tri-state `blockstore` parser on the crdt layer (file-intent activation rule; required-field check after env resolution per D-04/D-07/D-08) + loud `std::runtime_error` surfacing + credentials-never-logged summary + threading through `GlobalDB::New` as a trailing defaulted parameter (INTG-02)

**Wave 3** *(blocked on Wave 2)*
- [x] 07-03-PLAN.md — Config-gate hermetic test matrix (15 cases: blank/absent/optional-only ⇒ disabled, partial/unknown-key/wrong-type ⇒ loud, corrupt-file ⇒ lenient, env precedence + never-activates, log-scan) registered unconditionally in the fail-closed Tier-1 lane + CI Tier-1 step (+ ON-lane per readiness verdict) + `GeniusWallet` asset parity (`"blockstore": {}`) + Settings-editor whitelist filter + M3 posture documentation (D-09/D-10) (TEST-01 + INTG-02 SC2/SC3)

**Research note**: standard patterns (AsyncIOManager consumption precedent; `LoadCrdtConfig` at `GeniusNode.cpp:552-610`), fully cited in STACK.md. Planner decisions: canonical section name (`blockstore` vs `s3d.*` — pick one, use everywhere); M3 cold-journal backup posture (co-schedule a backup vs declare the journal rebuildable).

### Phase 8: Spill-on-Write & Background Drainer

**Goal**: Every CRDT block write spills — the `IpfsDatastore` seam journals block + PendingUpload locally in one atomic batch with zero remote I/O on the `dagMutex_`-held write path, and a dedicated drainer thread moves the journal to S3 with crash-resume and an explicit backpressure policy
**Depends on**: Phase 7
**Requirements**: SPILL-01, SPILL-02
**Success Criteria** (what must be TRUE):
  1. Every CRDT block Put passing the `IpfsDatastore` seam (`globaldb.cpp:329`) journals block + PendingUpload record into `LocalBlockStore` as one atomic RocksDB batch — local WAL only, no remote I/O inline — and a benchmark proves publish latency is independent of drainer/s3d state (drainer paused vs running)
  2. A background drainer thread (backup-loop lifecycle pattern — never `io_`, never the pubsub asio context) drains the journal to S3 with exactly one drain in flight; ops-triggered drains enqueue, never run inline
  3. After crash-restart, startup reconciles `GetPendingUploads` leftovers and re-drains idempotently (S3 conditional create-only makes re-puts safe) — nothing lost, nothing duplicated; shutdown drains-or-resumes cleanly with ordered thread joins
  4. The backpressure policy is explicit, implemented, and tested: s3d slow/unavailable behavior follows the chosen policy (unbounded-journal+watermark+alarm or bounded-degrade) and the consensus write path never fails due to cold-store state — an s3d-down window leaves publishes succeeding
  5. Hermetic spill tests (fake S3: journal-write, drain, crash-resume, backpressure) run in the Tier-1 lane

**Plans**: 3/3 plans complete
Plans:
**Wave 1**
- [x] 08-01-PLAN.md — gated cold-storage stack (factory/stub split, coldstore dir) + `BlockStoreBackedIpfsDatastore` journal-spill decorator at the `GlobalDB::New` seam (journal-first, remove hot-only, D-04) + hermetic spill journal Tier-1 tests + local tree reconfigured ON (SPILL-01)

**Wave 2** *(blocked on Wave 1)*
- [x] 08-02-PLAN.md — `blockstore.backpressure` strict config (D-05/D-06/D-07, 0-defaults, loud validation, wallet parity) + `ColdStorageManager` drainer thread (split-phase drain that never holds the shared mutex across remote I/O, backoff, dual count watermark with always-on alarm, status getter, bounded-grace shutdown, first-poll crash reconciliation) + lifecycle/shutdown join ordering (SPILL-02)

**Wave 3** *(blocked on Wave 2)*
- [x] 08-03-PLAN.md — behavior evidence suite (drain-to-S3, crash-resume, s3d-down backpressure window, enqueue-never-inline, shutdown grace) + SC1 latency-independence benchmark (drainer paused vs running under injected latency — never ON-vs-OFF) + partial-success backoff + CI-readiness Phase-8 disposition (SPILL-01/SPILL-02 evidence)

**Research note**: standard pattern — the backup-loop thread pattern is twice-proven (`globaldb.cpp:429-477`) and journal/drainer semantics are shipped library contracts. Phase-local research: enumerate the exact `IpfsRocksDb` block-key layout before adapter code is written. Planner decision: backpressure = unbounded-journal+watermark+alarm vs bounded-degrade. *(Resolved in 08-CONTEXT D-01..D-12 + 08-RESEARCH: key layout byte-identical CIDs both tiers; drainer hosting = SuperGenius-owned thread with a split-phase per-poll body so remote I/O never runs under the shared mutex; CI ON-lane stays blocked-on-thirdparty-release-cut per the Phase-7 verdict.)*

### Phase 9: Cold Read Fallback — Local Reads & Graphsync Serving

**Goal**: Cold data is readable — hot-store misses resolve through Local→S3 with CID-verify and re-cache for both local reads and graphsync serving, the miss-taxonomy is honest (transport failure is never authoritative absence), and the responder is never blocked inline
**Depends on**: Phase 8
**Requirements**: READ-01, READ-02
**Success Criteria** (what must be TRUE):
  1. A local node read that misses the hot datastore fetches from the blockstore (Local tier → S3 tier), CID-verifies, re-caches, then returns; under injected transport faults the failure surfaces as `TemporarilyUnavailable`, never `NotFound` — a fault-injected test proves no NotFound-shaped result escapes the seam
  2. Graphsync serving for a CID not held locally performs an async cold fetch on a bounded dedicated executor with a deadline below the peer stream timeout, off the responder's inline path, CID-verifies, then serves — during an s3d outage the responder still serves local content and never freezes libp2p stream processing (whole-node-freeze regression test)
  3. The first-class `BlockStatus` mapping holds at the seam: no peer-blacklist writes and no `RecordCIDFailure` from s3d blips; `Corrupt` attributes its source; `HasBlock` is cold-aware ("held locally OR retrievable before deadline")
  4. Restored blocks enter through a dedicated rehydrate path — bytes + resolved marker only; zero pubsub broadcast, zero `AddRoute`, heads unchanged (no restore re-entry storms)
  5. Hermetic fallback tests (fake S3 + fault injection: taxonomy honesty, responder non-blocking, rehydrate silence) run in the Tier-1 lane

**Plans**: 3/3 plans complete
Plans:
**Wave 1**
- [x] 09-01-PLAN.md — READ-01 tracer: `ColdReadFallback` hook (ungated) + gated `ColdReadService` chain (hot miss → LocalBlockStore → S3BlockStore, CID-verified → re-cache via decorator `set()`, D-01..D-04) + `BlockStatus` taxonomy mapping at the seam (three additive `Error` values) + `remote_store_mutex_` + `getNode` pre-peer cold leg (D-03 fall-through + cold-precedence) + gated `HasBlock` cold-dir check (D-08/D-09) + hermetic `cold_storage_fallback_test` (READ-01)

**Wave 2** *(blocked on Wave 1)*
- [x] 09-02-PLAN.md — READ-02: re-warm executor (single worker, queue bound 64, per-CID coalescing D-07, 4 s budget / 5 s grace as D-12 compile-time defaults) + `ColdServeDagService` responder wrapper (delegate-or-enqueue, never block — D-05/D-06) + shutdown slot per Phase-8 D-10/D-11 + SC2 latency-budget benchmark & freeze regression (`cold_read_freeze_latency_test`) (READ-02)

**Wave 3** *(blocked on Wave 2)*
- [x] 09-03-PLAN.md — Fault-injection honesty suite (no-NotFound-escape, no peer-blacklist/per-(peer,cid) failure from cold blips, Corrupt attribution both tiers, rehydrate silence SC4, responder-freeze regression under faulted+slow s3d) + Tier-1 fail-closed lane proof + registration/label parity (READ-01/READ-02 evidence)

**Research note**: `--research-phase` recommended — responder-side async cold serving is novel in this codebase (the current responder is deliberately local-only); the executor/deadline design needs exploration and the cold-serve latency budget measured before enabling by default.

### Phase 10: Flush-Gated Durability Advancement

**Goal**: `Durable` is an evidence-backed state, not an assumption — recorded durability advances LocalCommitted → ObjectStoreAccepted → Durable via s3d `/objects/flush` + `pendingObjects==0` evidence before bulk `MarkUploadedDurable`, making the eviction safety gate honest before any GC exists
**Depends on**: Phase 9
**Requirements**: DUR-01
**Success Criteria** (what must be TRUE):
  1. A flush cadence drives s3d `POST /objects/flush` (bucket-scoped, blocking — cost acknowledged) and observes `pendingObjects==0` before advancing durability records; a record marked Durable is always backed by that evidence, never by accepted-is-durable assumption
  2. Per-CID journal state transitions LocalCommitted → ObjectStoreAccepted → Durable are observable, and local bytes become evictable only after the configured durability state is recorded — the exact gate Phase 11's eviction consults, testable standalone
  3. Fault injections pass: crash-between-journal-and-drain recovers via journal reconciliation; an s3d outage never surfaces as NotFound; drainer/GC-scheduler/backup-loop shutdown interplay is ordered and race-free under load
  4. Staging health (`pendingObjects`/`bufferUsed`/`bufferLimit`) is monitored and exposed so later GC can be inhibited while staging is unhealthy

**Plans**: 2/2 plans complete
Plans:
**Wave 1**
- [x] 10-01-PLAN.md — TRACER: s3d admin facade in sgns-blockstore (`S3AdminClient` + `OpenS3dAdminClient` + `InMemoryS3AdminClient` fake, D-05/D-06) + `GetUploadsInState`/`MarkUploadedDurableMany` + drainer flush cadence with D-03 snapshot-at-initiation evidence gate (D-01/D-02/D-07) + per-CID/per-state observability (`ColdUploadState` bridge, `kEvictionDurabilityGate`, D-08/D-09/D-10) + `blockstore.durability` config sub-object + `admin_endpoint` + `SGNS_BLOCKSTORE_S3_ADMIN_PASSWORD` (D-11) + D-04 bounded final flush in Stop() (DUR-01 SC1+SC2)

**Wave 2** *(blocked on Wave 1)*
- [x] 10-02-PLAN.md — SC3 fault-injection honesty (crash-between-journal-and-drain reconciliation, admin-outage-never-NotFound with independent backoffs, shutdown-under-load with SlowFlush, idempotent-replay + acceptance-race assumption discharge) + SC4 staging-health predicate + staging counters/flag in status + `RefreshStagingStats` (D-12/D-13) + restart count seeding (DUR-01 SC3+SC4 + the Phase-11 GC-inhibition gate)

**Research note**: light — flush-cadence cost vs `MarkUploadedDurable` batching policy against s3d's bucket-scoped blocking flush is a design note, not a full research pass. Planner decision: the documented durability-bar policy (flush-gated vs accepted-risk-with-separate-staging).

### Phase 11: Retention GC of Cold-Eligible CRDT Data

**Goal**: Cold-eligible CRDT data past retention is evicted locally — never deleted remotely, never touching tombstones or CRDT metadata — behind the two-phase durability + non-reachability gate, with evicted CIDs still retrievable end-to-end and the live s3d E2E evidence committed
**Depends on**: Phase 9 (fallback makes evicted data retrievable), Phase 10 (durability gate is real)
**Requirements**: GC-01, GC-02, GC-03, TEST-03
**Success Criteria** (what must be TRUE):
  1. A configurable retention age in `crdt_config.json` identifies cold-eligible CIDs (spilled-CID index ∩ age-past-retention ∖ head-reachable ∩ Durable); policy evaluation provably never enumerates or writes tombstone/CRDT-metadata keyspaces and protected namespaces (heads, genesis, current-epoch pointers) are pinned — guard test
  2. Eviction is two-phase (mark-as-evicting, visible to readers and drain snapshots → grace → physical delete) and unit-atomic: block bytes, resolved marker, and set rows evicted as one unit; `DeleteCIDBlock` LRU invalidation keeps `HasBlock` honest; a bounded disposed-CID marker yields authoritative `NotFound` plus re-broadcast dedup; tombstones and CRDT metadata are never purged in v1.1 (guard test + SPEC scope boundary)
  3. A GC-evicted CID remains retrievable end-to-end: both a graphsync request and a local read for it resolve from the blockstore, CID-verified — hermetic proof in the Tier-1 lane (GC-03)
  4. TEST-03 (dev-gated, never in CI): the live s3d E2E — spill → GC → retrieve — passes with committed evidence artifacts, and the MinIO-binary opt-in roundtrip is available (v1.0 Tier-2/3 precedent)
  5. The epoch watermark record is computed and stored (computation only — nothing is deletion-gated on it in v1.1), with per-pass reclaimed counts/bytes and a dry-run mode

**Plans**: TBD (suggested: 4)
**Suggested plan waves**:
**Wave 1**
- 11-01-PLAN.md — Retention policy scan + reachability walk (`CrdtHeads::GetList` → link walk, batched off `io_`) + protected/pinned namespaces + epoch watermark record (GC-01)

**Wave 2** *(blocked on Wave 1)*
- 11-02-PLAN.md — Two-phase eviction + durability-record gate consult (Phase 10 output) + bounded disposed-CID markers + block/marker/set-row unit atomicity + `DeleteCIDBlock` LRU invalidation (GC-02)

**Wave 3** *(blocked on Wave 2)*
- 11-03-PLAN.md — Evicted-CID retrievability E2E (graphsync + local read, CID-verified) + tombstone/metadata never-purged guards + dry-run mode + per-pass metrics in the Tier-1 lane (GC-03)

**Wave 4** *(blocked on Wave 3; human checkpoint for the live session)*
- 11-04-PLAN.md — TEST-03 live tier: live s3d spill → GC → retrieve E2E with committed evidence artifacts + MinIO-binary opt-in roundtrip (TEST-03)

**Research note**: `--research-phase` recommended — the most novel phase; no proven upstream recipe exists (go-ds-crdt ships no tombstone GC; PurgeDAG is admin-only and needed a follow-up fix). Open: reachability-walk cost model (O(history), batching, scheduling), retention age evidence (priority-height vs wall-clock vs app-level horizon), disposed-CID marker column-family design.

### Phase 12: Integration Hardening, Fault Races & Fresh-Clone Proof

**Goal**: The integration's trust claims hold under induced failure and reproducible builds — cross-actor races are proven safe, GC resurrection is counter-tested, outages soak without unbounded growth, and a fresh clone builds and passes Tier-1 on all three desktop platforms with cold storage ON
**Depends on**: Phase 11
**Requirements**: TEST-02
**Success Criteria** (what must be TRUE):
  1. Evict × serve × drain fault races under `FaultController` timing injection: zero `Corrupt`-from-race, zero lost blocks, zero peer-blacklist writes originating from storage failures
  2. The resurrection counter-test passes: delete → GC → re-deliver a pre-delete delta ⇒ the value is absent everywhere (restore must not resurrect GC'd values)
  3. An s3d-unavailable soak shows bounded journal growth, the alarm firing, and publishes continuing to succeed for the soak duration; teardown-under-load joins cleanly; peer cold-fetch under injected s3d latency stays within its deadline budget
  4. Fresh-clone proof using only pushed commits across the three repos (SuperGenius, GeniusSDK, thirdparty/sgns-blockstore): configure + build + `ctest -L Tier1` green on Windows, Linux, and macOS with the cold-storage option ON; every new test is labeled and gated (tier-label audit passes)

**Plans**: TBD (suggested: 3)
**Suggested plan waves**:
**Wave 1**
- 12-01-PLAN.md — Fault-race matrix (evict × serve × drain under timing injection) + resurrection counter-test (TEST-02)

**Wave 2** *(blocked on Wave 1)*
- 12-02-PLAN.md — s3d-down soak with bounded-journal assertion + teardown-under-load + peer cold-fetch under injected s3d latency (TEST-02)

**Wave 3** *(blocked on Wave 2)*
- 12-03-PLAN.md — Fresh-clone three-platform Tier-1-green proof (pushed commits only, option ON) + tier-label/gating audit (TEST-02 closing evidence)

**Research note**: standard — v1.0's fault kit, tier contract, and evidence-capture habits are directly reusable.

## Phase Ordering Rationale

- **Library before consumer (6→7):** the v1.0 CID gate throws on the very first CRDT block (all blake2b-256) and the production client header is not installed — no SuperGenius code can spill or construct so much as one block before Phase 6 lands
- **Existence before behavior (7→8):** the find_package chain and config gate must precede any gated feature — blank-must-mean-disabled is itself a Phase 7 deliverable, and TEST-01's hermetic lane starts there
- **Fill before read (8→9):** fallback needs content in the cold store to fall back to; write and read directions share one adapter but ship as separate phases for risk isolation, and the miss-taxonomy must be designed before GC makes misses common
- **Gate before delete (10→11):** GC's eligibility check consumes the durability record; Phase 10 makes that state evidence-backed, Phase 11 consumes it — evicting before durability is proven loses data silently
- **Destructive work strictly last of the functional phases (11):** GC depends on fallback for retrievability (GC-03) and on the journal for its safety gate (GC-02); it is the only phase that removes anything anywhere
- **Prove at the end (12):** the cross-cutting races (evict × serve × drain) can only be proven once all actors exist; fresh-clone proof caps the milestone (v1.0 Phase 5 discipline)
- **Cross-cutting TEST requirements:** TEST-01 anchors in Phase 7 and every phase extends the hermetic Tier-1 lane (v1.0 day-one precedent); TEST-03's live evidence completes in Phase 11 because the E2E is spill → GC → retrieve (needs GC); TEST-02 is the Phase 12 capstone

## Progress (v1.1)

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 6. sgns-blockstore v1.1 Library Prerequisites | 3/3 | In Progress|  |
| 7. SuperGenius Build Wiring & Config Gate | 3/3 | In Progress|  |
| 8. Spill-on-Write & Background Drainer | 3/3 | In Progress|  |
| 9. Cold Read Fallback | 3/3 | In Progress|  |
| 10. Flush-Gated Durability Advancement | 2/2 | In Progress|  |
| 11. Retention GC of Cold-Eligible CRDT Data | 0/4 | Not started | - |
| 12. Integration Hardening, Fault Races & Fresh-Clone Proof | 0/3 | Not started | - |

---
*Roadmap created: 2026-10-19 (v1.0) — v1.1 phases added 2026-10-22 — rocksdb-backup workstream (v1.0: 21/21 shipped; v1.1: 15/15 requirements mapped)*
