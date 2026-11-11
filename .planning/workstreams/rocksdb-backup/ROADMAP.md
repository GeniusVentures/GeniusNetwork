# Roadmap: rocksdb-backup

## Milestones

- ✅ **v1.0 CRDT Cold-Storage BlockStore Library (Sia s3d backend)** — Phases 1-5, 21/21 requirements (shipped 2026-10-22) — archive: [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md)
- ✅ **v1.1 SuperGenius Cold-Storage Integration & CRDT Garbage Collection** — Phases 6-12, 21 plans, 3/3 TEST requirements (shipped 2026-11-10) — archive: [milestones/v1.1-ROADMAP.md](milestones/v1.1-ROADMAP.md)

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

<details>
<summary>✅ v1.1 SuperGenius Cold-Storage Integration & CRDT Garbage Collection (Phases 6-12) — SHIPPED 2026-11-10</summary>

- [x] **Phase 6: sgns-blockstore v1.1 Library Prerequisites — blake2b-256 CIDs & Installed S3 Client Factory** - Remove the two hard blockers additively: the CID hash gate widened to accept blake2b-256 (the shape of every CRDT DAG block) and an installed `OpenMinioS3Client` factory (completed 2026-10-22)
- [x] **Phase 7: SuperGenius Build Wiring & Config Gate** - Both `CommonBuildParameters.cmake` files resolve sgns-blockstore from the install tree; the `crdt_config.json` blockstore section defines the blank=disabled / malformed=loud contract; hermetic Tier-1 CI lane from day one (completed 2026-10-23)
- [x] **Phase 8: Spill-on-Write & Background Drainer** - Every CRDT block Put journals locally at the `IpfsDatastore` seam (no remote I/O under `dagMutex_`); a dedicated drainer thread uploads to S3 with crash-resume and an explicit backpressure policy (completed 2026-10-23)
- [x] **Phase 9: Cold Read Fallback — Local Reads & Graphsync Serving** - Hot-store misses fetch Local→S3 with CID-verify and re-cache; graphsync serves cold CIDs asynchronously off the responder's inline path; transport failure never surfaces as NotFound (completed 2026-10-26)
- [x] **Phase 10: Flush-Gated Durability Advancement** - `Durable` becomes an evidence-backed state (s3d `/objects/flush` + `pendingObjects==0` → `MarkUploadedDurable`), making the eviction durability gate real before anything deletes (completed 2026-10-26)
- [x] **Phase 11: Retention GC of Cold-Eligible CRDT Data** - Eviction-only GC behind durability + non-reachability gates with bounded disposed-CID markers; evicted CIDs stay retrievable end-to-end; live s3d spill→GC→retrieve evidence (dev-gated) (completed 2026-10-27)
- [x] **Phase 12: Integration Hardening, Fault Races & Fresh-Clone Proof** - Evict×serve×drain races, resurrection counter-test, s3d-down soak, and fresh-clone Tier-1 green on Windows/Linux/macOS with cold storage ON (completed 2026-11-10 — SC4 closed by tag-build run 42905264387: 153/153 Windows, 152/152 Linux, 155/155 OSX, cold storage ON, test_coldstorage_rtti)

Full phase details, plans, and success criteria: [milestones/v1.1-ROADMAP.md](milestones/v1.1-ROADMAP.md)
Requirements (3/3 TEST requirements complete): [milestones/v1.1-REQUIREMENTS.md](milestones/v1.1-REQUIREMENTS.md)
Milestone audit (passed — 3/3 requirements, 7/7 phases, 5/5 integration seams, 1/1 E2E flow): [milestones/v1.1-MILESTONE-AUDIT.md](milestones/v1.1-MILESTONE-AUDIT.md)

</details>

## Phases

_No active phases — v1.1 archived 2026-11-10. Start the next milestone with `/gsd-new-milestone`._

Deferred signals carried forward (see STATE.md `## Deferred Items` and the v1.1 audit's tech-debt section): soak-scale GC eviction-storm hardening; TEST-03 MinIO-binary live leg (runbook); permanent cmake.yml ON-leg baseline (activates at develop merge).

---
*Roadmap created: 2026-10-19 (v1.0) — v1.1 phases added 2026-10-22, shipped & archived 2026-11-10 — rocksdb-backup workstream*
