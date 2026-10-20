# Feature Research

**Domain:** CID-native cold-storage/archive BlockStore library (`sgns-blockstore`, thirdparty/ submodule) for SuperGenius CRDT/IPLD histories
**Researched:** 2026-10-19
**Confidence:** MEDIUM (evidence is source-code-level from canonical upstream repos and official vendor docs; several critical findings cross-verified across independent systems — see per-finding notes and Confidence Caveats)

**Scope guard (from milestone context):** v1 vertical slice = architecture-doc Phase 1 (BlockStore abstraction, memory + RocksDB-backed local backends, CID verification) + Phase 2 (S3 backend via MinIO C++ SDK adapter, conditional/idempotent writes, structured errors, metrics) **only**. NO tiered retrieval/racing, NO path sharding, NO eviction policy, NO CARv2 this milestone. Existing SuperGenius CRDT/GlobalDB, IpfsDatastore-over-RocksDB, Graphsync, libp2p, and the RocksDB `BackupEngine` path in `globaldb.cpp` are already built and stay untouched.

## Feature Landscape

### Table Stakes (Users Expect These)

The reference systems (boxo/kubo Blockstore, S5 `Store`/`BlobStore`, IPFS Cluster state manager, Sia s3d) converge on a small core operation set. A v1 cold-storage block library missing any of these feels broken to anyone who has used an IPFS-adjacent store.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| `Put(CID, bytes)` with verify-before-accept | Every reference store assumes content-addressed invariant; flatfs documents "identical keys guarantee identical values" as the safety foundation | LOW | Verify bytes hash to the CID on entry (reject `Corrupt` on mismatch). Reuses existing `sgns::common` CID/multihash primitives (same family as `ipfs-lite-cpp`'s `common::getCidOf`) |
| `Get(CID)` returning structured result | Core operation; boxo `Get`, S5 `open_read_bytes`, existing `IpfsDatastore::get` | LOW–MED | Return `BlockStatus` (Found/NotFound/TemporarilyUnavailable/Corrupt/Unauthorized) + diagnostic per the architecture doc — NOT a bare error code |
| `Has(CID)` | boxo `Has`, S5 `exists`, `IpfsDatastore::contains`; S3 `HeadObject` (fully supported by s3d) | LOW | Cheap existence check without transferring bytes |
| `GetSize(CID)` | boxo `GetSize`, S5 `size` | LOW | S3 `HeadObject` content-length; useful for restore planning and quota math |
| Batched `PutMany` | boxo `PutMany` exists specifically for request-cost amortization | MED | For S3 backend this is N sequential conditional PUTs initially — still worth having the API shape now so callers don't loop naively forever |
| CID verification on every read (toggleable, default ON) | boxo `HashOnRead(bool)`; S5 `BlobStore` "handles BlobId verification (hash checking)"; architecture-doc acceptance criteria #4/#7 | MED | Implement as a `ValidatingBlockStore`-style wrapper OR built into backends; must be ON by default for a *cold-storage trust* library, with an escape hatch for hot paths |
| Structured error taxonomy separating authoritative-NotFound vs transport failure vs corruption | Architecture-doc acceptance #6/#7 ("backend timeouts do not become NotFound"); boxo's `AllKeysChanWithErr` exists precisely because best-effort errors weren't enough | MED | This is the single most important correctness feature. Transport failure MUST be `TemporarilyUnavailable`, never `NotFound`. Only authoritative absence may be (briefly) negative-cached — and negative caching itself is out of v1 scope |
| Memory backend | Architecture-doc Phase 1 explicit; boxo/S5 both ship one; enables deterministic hermetic tests | LOW | Mirror `InMemoryDatastore` role from `ipfs-lite-cpp`; budgeted/evicting variant is explicitly NOT v1 (S5's W-TinyLFU memory store shows what that becomes) |
| RocksDB-backed local backend | Architecture-doc Phase 1 ("wrap the existing local block store"); RocksDB already in thirdparty | MED | Wrap-or-adapt the `RocksdbDatastore` pattern from `ipfs-lite-cpp` rather than inventing a new column layout; this is the `LocalCommitted` durability tier |
| Enumerate/List CIDs | boxo `AllKeysChan`/`AllKeysChanWithErr`, S5 `Store::list`, s3d `ListObjectsV2` (fully supported) | MED | Required for verify-all/audit and restore-to-local. **Critical design constraint from boxo's documented regret:** keying by multihash-only loses the codec (enumeration returns Raw-codec CIDs). The key layout must preserve the full CID so enumeration is lossless |
| Idempotent conditional create-only puts | AWS S3 `If-None-Match:*` (PutObject, 2024+); **s3d independently implements `If-None-Match`/`If-Match` on PutObject/CopyObject/CompleteMultipartUpload "evaluated atomically with the write"** — cross-verified across two implementations | MED | 412 Precondition Failed on an existing key maps to `AlreadyExists`-as-success (content-addressed: same key ⇒ same bytes). This is the write-once guarantee for immutable blocks. Requires verifying the MinIO C++ SDK exposes raw conditional headers (open item — see Gaps) |
| Durability-acknowledgment levels in the API | Architecture doc's `DurabilityLevel` enum (LocalCommitted / ObjectStoreAccepted / ObjectStoreDurable); S5 `Store::sync()` is an explicit durability barrier | MED | v1 must at minimum distinguish LocalCommitted vs ObjectStoreAccepted, and *document* that s3d's returned-200 PUT means staged-locally (see Differentiators note on the durable signal). Eviction wiring is out of scope, but the state model must exist in the types now or Phase 5 retrofits painfully |
| Restore-to-local by CID | Architecture-doc acceptance #3 ("fresh node can retrieve the block by CID from Sia s3d"); IPFS Cluster's whole restore model is metadata-import + re-fetch-by-CID | MED | Mostly composition: Get + verify + write to local backend. Provide as a small helper (`CopyBetweenStores` / `Restore(cid, localStore)`) rather than a bespoke protocol — IPFS Cluster demonstrates restore = enumeration/manifest + ordinary fetches |
| Deadlines / cancellation in options | Architecture doc (`GetBlock(cid, deadline)`, `request_timeout_ms`); boxo threads context through everything | MED | Follow SuperGenius Boost.Asio conventions; options struct per the doc's `ReadOptions`/`WriteOptions` |
| Internal `S3Client` adapter interface (no SDK type leakage) | Architecture-doc Phase 2 explicit; S5 shows backend isolation (rust-s3 behind `Store`); protects against SDK swap (MinIO → AWS SDK → OpenDAL) | MED | Four operations suffice for v1: PutObject (conditional), GetObject, HeadObject, DeleteObject, + ListObjectsV2 for enumeration |

### Differentiators (Competitive Advantage)

Not required for "feels complete," but high value for a *cold-storage* library specifically (as opposed to a cache or full IPFS node).

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Versioned, codec-preserving key layout (`v1/blocks/<codec-prefix>/<cid>`) | The S3 key layout is the on-disk contract — nearly free now, brutal to retrofit; boxo's multihash-only keying is a documented limitation; versioned `v1/` prefix lets the layout evolve without bucket migration | LOW | Architecture doc already specifies this shape. Decide fan-out width (e.g. first 2–4 base32 chars) at design time; fan-out primarily aids ListObjects/audit, not GET/HEAD |
| `VerifyAll` / audit operation (enumerate + Get + verify each) | Cold storage earns trust through periodic scrubbing; no reference system ships it as a first-class op, but all the pieces (list + verify-on-read) exist — cheap composition, high assurance value | MED | Streaming, cancellable, reports per-CID corruption with source attribution. Natural v1.x addition once list+verify land in v1 |
| Durability-state observation for s3d (staged-vs-durable probe) | s3d's returned-200 PUT means *staged on local disk* (README: "Objects are buffered on disk before being uploaded to Sia in the background"); the observable signals are the admin API `GET /stats/uploads` + `/prometheus` upload-pipeline metrics and `sia.diskUsageLimit` backpressure | MED–HIGH | Architecture doc open question #5. v1: expose `ObjectStoreAccepted` honestly and surface pending-upload stats as diagnostics. Discovering a per-object durable signal (if any — check `openapi.yml` + `x-amz` metadata during Phase 2 testing) becomes a defined follow-up, not a blocker |
| Additive coexistence with the existing RocksDB `BackupEngine` path | Two independent durability mechanisms (hot-state DB backup vs cold block archive) that don't interact; ops teams can adopt the archive without touching existing backup/restore behavior in `globaldb.cpp` | LOW | Mostly a matter of separate directories/config/prefixes and an explicit compatibility test; document the division of responsibility |
| Consistent test-suite contract across backends | S5 has `s5_core::testutil::StoreTests` run against every backend (incl. `#[ignore]` S3 test against a live MinIO); guarantees Memory == RocksDB == S3 behavior | LOW–MED | One `BlockStoreTest` fixture instantiated per backend; include a live s3d/MinIO integration tier mirroring the architecture doc's "test against a local S3-compatible test service and Sia s3d" |
| Metrics hooks (put/get latency, bytes, hit/miss, corruption counters) | Architecture-doc Phase 2 lists metrics; s3d itself sets the precedent (Prometheus pipeline metrics) | MED | Hook points in the interface layer, not per-backend ad hoc; exact exposition (prometheus vs counters) follows SuperGenius conventions |

### Anti-Features (Commonly Requested, Often Problematic)

These are deferred items (tiering, sharding, eviction, CAR) **plus** tempting additions the research argues against. Each has a concrete trigger for reconsideration.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Tiered retrieval / staggered peer-vs-S3 racing | "The architecture doc has a TieredBlockStore, surely we need it now" | It's explicitly Phase 3; racing policy needs measured latencies (open question #4) and Graphsync integration to race *against* — neither exists yet; premature policy = untestable tuning knobs | Ship backends independently composable now; add `TieredBlockStore` in the phase the doc schedules it |
| Path-based sharding / rendezvous ownership | Feels like the "real" distributed design | Explicitly Phase 4; depends on unresolved open question #2 (which path component is stable enough to own a shard) and new mutable-registry machinery | Physical keys are CID-derived in v1 (the CID is authoritative); sharding is a namespace-layer concern layered later |
| Local cache eviction (LRU/watermarks/pinning) | "It's called a cache in the doc" | Explicitly Phase 5; eviction before a durability-state model risks silent data loss, and the CRDT correctness section forbids treating evicted-as-deleted until causal stability is specified | v1 local store is unbounded/grow-only (cold archive semantics); durability states exist in the type system, eviction policy comes after |
| CARv2 packing / multi-block objects | "Millions of one-block S3 objects sounds wasteful" | Doc is explicit: measure first. **s3d already bin-packs small objects into 4 MiB-sector slabs** (background loop, waste threshold 10%) — adding CAR packing before measuring stacks two packing layers that solve overlapping problems | One CID → one S3 object; benchmark s3d metadata/PUT throughput/SQLite growth; add CARv2 only if numbers justify (doc Phase 6) |
| CRDT-history garbage collection / tombstone purging | "Old history must be deletable eventually" | Doc: initial versions must avoid permanent deletion of archived CRDT history; GC requires a formally defined causal-stability + reachability policy (open question #13) that doesn't exist | Archive is append-only in v1; `Remove(CID)` exists in the interface (boxo parity) but the *policy* calling it lives far upstream |
| Mutable path→CID registry inside the library | "Resolve(path) is in the doc" | The namespace layer is deliberately separate (doc: "Namespace and immutable storage"); SuperGenius CRDT/GlobalDB already owns path state; duplicating it creates two sources of truth | Library knows only CID→bytes; path resolution stays in SuperGenius (existing CRDT), matching S5's registry/blob separation and Cluster's state/pin split |
| Peer retrieval (Graphsync/libp2p) inside the library | "Why can't the block store fetch from peers?" | Already exists as SuperGenius/Graphsync machinery; wiring it here couples the library to libp2p and violates "knows about CIDs and bytes only"; it's Phase 3's `PeerBlockStore` | Keep the library network-free; a future `PeerBlockStore` implements the same interface *outside* or beside it |
| Full S3 surface (versioning, lifecycle, bucket policies, multipart) | "s3d supports them, expose them" | s3d supports versioning + lifecycle + policies, but v1 blocks are small immutable write-once objects — none of these add correctness; multipart has a 5 MiB minimum part (above typical CRDT block size) | Conditional PUT, GET/HEAD/LIST/DELETE only; revisit multipart when measured block sizes justify it |
| Negative caching / caching NotFound results | "Repeated misses hammer the backend" | Architecture doc acceptance #6: transport failures must never become NotFound; only authoritative absence may be negative-cached, briefly — and there's no eviction machinery in v1 to manage it | Correct error taxonomy in v1; negative caching arrives with the Phase 3/5 cache layers |
| Generic key-value passthrough (non-CID keys) | "While we're here, store configs too" | Destroys the content-addressed invariant everything else relies on (flatfs's write-once safety, conditional-put idempotency, verify-on-read) | The library is CID-only by contract; anything mutable belongs to RocksDB/GlobalDB consumers |

## Feature Dependencies

```
[Conditional create-only Put (If-None-Match)]
    └──requires──> [Internal S3Client adapter]
                       └──requires──> [MinIO C++ SDK]  (NEW thirdparty dependency)

[CID verify on Put/Get] ──requires──> [sgns::common CID + multihash primitives]
                                              └──(already exist in thirdparty family)

[Structured error taxonomy] ──underpins──> [Everything]
[Enumerate/List CIDs] ──requires──> [Codec-preserving key layout (v1/blocks/...)]
[Restore-to-local] ──requires──> [Get + verify-on-read + enumerate-or-manifest]

[DurabilityLevel types] ──requires──> [Local backend (RocksDB)] + [S3 backend]
        └──observation──> [s3d staged-vs-durable signal]  (open: admin stats today)

[VerifyAll/audit (v1.x)] ──requires──> [Enumerate] + [verify-on-read]
[Backend test-suite contract] ──requires──> [Memory backend] (deterministic reference)

[Existing globaldb BackupEngine path] ──coexists (no dependency)──> [this library]
```

### Dependency Notes

- **Conditional Put requires the S3Client adapter** — and *verifying* the MinIO C++ SDK can send raw `If-None-Match` headers is a Phase-2 entrance criterion (the S3 semantics are cross-verified; the client library's header exposure is not yet — see Gaps).
- **Enumerate requires the codec-preserving layout decision** — changing key layout after real data lands in a bucket requires migration; that's why layout is a v1 table-stakes-adjacent differentiator despite being trivially cheap now.
- **DurabilityLevel is a type-system dependency for Phase 5** — eviction (later milestone) consumes it; defining it now costs little, retrofitting it later costs an API break.
- **The library must NOT depend on** Graphsync, libp2p, CRDT code, `globaldb`, or the existing `BackupEngine` path — dependency direction is one-way (SuperGenius may consume `sgns-blockstore`, never the reverse), matching the architecture doc's layering rule.

## MVP Definition

### Launch With (v1 — architecture-doc Phase 1 + Phase 2)

- [ ] `BlockStore` interface + `Block`/`BlockStatus`/`GetBlockResult`/`PutResult`/`DeleteResult` + `ReadOptions`/`WriteOptions` (deadlines, verify toggle) — the contract everything else implements
- [ ] CID verification on Put (reject mismatch) and on Get (default ON) — content-addressed trust foundation
- [ ] `MemoryBlockStore` — deterministic hermetic tests
- [ ] `LocalBlockStore` over RocksDB (existing thirdparty) — the LocalCommitted tier
- [ ] Internal `S3Client` adapter interface (Put/Get/Head/Delete/List) with MinIO C++ SDK implementation behind it
- [ ] `S3BlockStore` with `v1/blocks/` codec-preserving layout, direct CID→object mapping (one block per object)
- [ ] Conditional create-only puts via `If-None-Match:*`; 412 → AlreadyExists-success mapping; retry-safe idempotency
- [ ] Structured error taxonomy (authoritative NotFound vs TemporarilyUnavailable vs Corrupt vs Unauthorized) with diagnostics
- [ ] Enumerate/List CIDs (local iterator + S3 ListObjectsV2)
- [ ] Restore-to-local helper (Get + verify + local Put), proven by the acceptance-criteria E2E: fresh instance retrieves from Sia s3d and verifies
- [ ] `DurabilityLevel` type surface (LocalCommitted/ObjectStoreAccepted/ObjectStoreDurable) with honest `ObjectStoreAccepted` semantics documented for s3d staging
- [ ] Shared backend test-suite contract instantiated for all three backends + one live s3d/MinIO integration test
- [ ] Basic metrics hook points + structured logging per SuperGenius conventions

### Add After Validation (v1.x)

- [ ] `VerifyAll`/audit scrub — trigger: first real archive deployment wanting integrity attestation
- [ ] s3d durable-signal probe (admin `/stats/uploads` polling or per-object metadata if found in `openapi.yml`) — trigger: Phase-2 live testing against real s3d
- [ ] Batched/multi-key Put optimizations, GET byte-range reads — trigger: measured throughput data
- [ ] Prefix-fanout tuning, listing pagination ergonomics — trigger: first large-bucket audits

### Future Consideration (v2+ — mapped to doc Phases 3–6)

- [ ] `TieredBlockStore` + `PeerBlockStore` (Graphsync fallback/racing) — Phase 3
- [ ] Path sharding, rendezvous ownership, shard manifests — Phase 4
- [ ] Durability-driven safe eviction, watermark/pinning policy — Phase 5
- [ ] CARv2 packing (only if benchmarks justify) — Phase 6
- [ ] CRDT-history GC policy (requires formal causal-stability spec)

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| BlockStore interface + result types | HIGH | LOW | P1 |
| CID verify on Put/Get | HIGH | LOW | P1 |
| Memory backend | HIGH | LOW | P1 |
| RocksDB local backend | HIGH | MED | P1 |
| Structured error taxonomy | HIGH | MED | P1 |
| S3Client adapter + S3BlockStore (v1/ layout) | HIGH | MED | P1 |
| Conditional create-only puts | HIGH | MED | P1 |
| Enumerate/List CIDs | MED–HIGH | MED | P1 |
| Restore-to-local helper | HIGH | LOW–MED | P1 |
| DurabilityLevel type surface | MED (now) / HIGH (Phase 5) | LOW | P1 |
| Backend test-suite contract + live s3d test | HIGH | LOW–MED | P1 |
| VerifyAll/audit | MED–HIGH | MED | P2 |
| Metrics hooks | MED | MED | P2 |
| s3d durable-signal probe | MED | MED | P2 |
| Batched PutMany beyond naive | MED | MED | P2 |
| Tiered retrieval / racing | HIGH (later) | HIGH | P3 |
| Path sharding | HIGH (later) | HIGH | P3 |
| Eviction policy | HIGH (later) | HIGH | P3 |
| CARv2 packing | UNKNOWN (measure first) | HIGH | P3 |
| CRDT-history GC | UNKNOWN | VERY HIGH | P3 |

**Priority key:** P1 = this milestone's vertical slice; P2 = fast-follow once real s3d testing begins; P3 = later milestones per architecture-doc phasing.

## Competitor Feature Analysis

| Feature | boxo/kubo (Go) | S5 s5-rs (Rust) | IPFS Cluster | Our Approach (sgns-blockstore v1) |
|---------|----------------|------------------|--------------|-----------------------------------|
| Core ops | Put/PutMany/Get/Has/GetSize/DeleteBlock/AllKeysChan | put_bytes/put_stream/open_read_bytes/size/list/delete/rename/exists | (state layer: Add/Rm/List/Get/Has; bytes live in IPFS nodes) | Put/PutMany/Get/Has/GetSize/Remove/Enumerate — full-CID keys (avoid boxo's codec-loss) |
| Verification | `HashOnRead` toggle + `ValidatingBlockstore` wrapper | `BlobStore` facade hash-checks every blob | Trusts IPFS node pins | Verify-on-put always; verify-on-get default ON; verify-all scrub as v1.x op |
| Backend set | datastore-backed (leveldb/flatfs/etc.) | Memory/Local/S3/Sia-renterd/Indexd-Sia/Fjall-packed | n/a (delegates to IPFS) | Memory + RocksDB local + S3-compatible (s3d first) — deliberately minimal |
| Durability semantics | fsync via datastore layer | Explicit `Store::sync()` barrier | Raft/CRDT consensus on metadata | `DurabilityLevel` enum; honest staged-vs-durable docs for s3d |
| Conditional/idempotent writes | First-successful-writer-wins (content-addressed safety) | Idempotent by content address | n/a | `If-None-Match:*` create-only + 412-as-success (AWS + s3d verified) |
| Backup/restore | Repo tools / `ipfs dag export` (CAR) | Cold-recovery via blob-hash list enumeration | `state export`/`import` JSON stream, offline, round-trip no-op | Enumerate + restore-to-local by CID; manifest/CAR deferred |
| Enumeration contract | `AllKeysChanWithErrer` (truncation reporting added later — lesson) | `Store::list` streams paths | `State.List` streams pins | Cancellable iterator with error-completeness reporting from day one |
| Small-object packing | n/a (flatfs files) | Fjall store packs blobs into SSTs | n/a | None — rely on s3d slab bin-packing; measure before adding CAR |

## Confidence Caveats

The GSD confidence seam rates the delivery providers used here (`github` source inspection, direct doc fetch) as LOW because they are not its recognized curated-provider ids. The underlying evidence quality is stronger than that label suggests, and is documented per finding:

- **HIGH-quality evidence (canonical source / official docs, current):** S5 `Store` trait shape and backend set (read directly from s5-rs `main`, Oct 2026); boxo Blockstore interface incl. codec-loss limitation (read from ipfs/boxo `main`); IPFS Cluster state export/import/round-trip (source + sharness tests); s3d staging, packing, conditional-request support (official README, v0.2.1, fetched Oct 2026); AWS S3 conditional-write semantics incl. 412/409/404 behaviors (official AWS docs, current).
- **Cross-verified:** conditional `If-None-Match` writes (AWS docs + s3d README independently); core operation set (boxo + S5 + existing `IpfsDatastore` + Cluster all corroborate).
- **MEDIUM/LOW, flagged honestly:** "s3d has no documented per-object durable-on-Sia signal" — absence verified only against the README, not the full `openapi.yml`/admin API surface; treat as *not yet found*, not *does not exist* (architecture-doc open question #5). MinIO C++ SDK conditional-header exposure: unverified (STACK-domain follow-up). Versioned-prefix (`v1/`) convention: industry practice observed across systems, not a single normative spec.

## Sources

- S5 (s5-rs) source, `main` branch (fetched 2026-10-19): `s5_core/src/store.rs` (Store trait, sync, StoreFeatures), `s5_core/src/blob/store.rs` (BlobStore verification facade), `blob_stores/{memory,local,s3,sia,fjall}`, `stores/indexd`, `s5_core/README.md` — https://github.com/s5-dev/s5-rs
- boxo Blockstore source, `main` (fetched 2026-10-19): `blockstore/blockstore.go`, `validating_blockstore.go`, `idstore.go`, `bloom_cache.go`, `twoqueue_cache.go`, `gateway/blockstore.go` — https://github.com/ipfs/boxo
- go-ds-flatfs README, v0.6.1 (fetched 2026-10-19): content-addressed-only restrictions, first-successful-writer-wins, sharding functions — https://github.com/ipfs/go-ds-flatfs
- IPFS Cluster source, `master` (fetched 2026-10-19): `cmdutils/state.go` (Import/Export/Clean), `state/`, `sharness/t0052-*, t0053-*, t0054-*` (export/import/cleanup round-trip tests), CHANGELOG v0.14.3 — https://github.com/ipfs-cluster/ipfs-cluster
- Sia s3d README, v0.2.1 (fetched 2026-10-19): upload packing/staging, conditional requests, admin upload stats, config (`sia.diskUsageLimit`), compatibility matrix — https://github.com/SiaFoundation/s3d
- AWS S3 User Guide, "How to prevent object overwrites with conditional writes" (current as of 2026-10): `If-None-Match:*`/`If-Match` on PutObject/CopyObject/CompleteMultipartUpload, 412/409/404 behaviors — https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-writes.html
- Local codebase anchors: `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/datastore.hpp` (existing IpfsDatastore surface), `SuperGenius/src/crdt/globaldb/globaldb.cpp` (existing BackupEngine path — untouched), `supergenius-sharded-ipld-cache-architecture.md` (authoritative architecture)

---
*Feature research for: sgns-blockstore cold-storage library (rocksdb-backup workstream, milestone v1.0)*
*Researched: 2026-10-19*
