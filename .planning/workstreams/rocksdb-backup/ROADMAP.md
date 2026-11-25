# Roadmap: rocksdb-backup

## Milestones

- ✅ **v1.0 CRDT Cold-Storage BlockStore Library (Sia s3d backend)** — Phases 1-5, 21/21 requirements (shipped 2026-10-22) — archive: [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md)
- ✅ **v1.1 SuperGenius Cold-Storage Integration & CRDT Garbage Collection** — Phases 6-12, 21 plans, 3/3 TEST requirements (shipped 2026-11-10) — archive: [milestones/v1.1-ROADMAP.md](milestones/v1.1-ROADMAP.md)
- ✅ **v1.2 SuperGenius Cold-Storage Archive Integration** — Phases 13-19, 25 plans, 20/20 requirements (shipped 2026-11-25) — archive: [milestones/v1.2-ROADMAP.md](milestones/v1.2-ROADMAP.md)

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

<details>
<summary>✅ v1.2 SuperGenius Cold-Storage Archive Integration (Phases 13-19) — SHIPPED 2026-11-25</summary>

- [x] **Phase 13: Bootstrap Branch Merge & Composition Baseline** - Merge `fix/trust-genesis-bootstrap` into `dev_coldstorage_additions` with the full existing suite green — the gate for all v1.2 recovery/walk work (completed 2026-11-16 — merge `2af184fa1`; SC2 zero-regression 167/167 post vs composed pre baseline)
- [x] **Phase 14: Durability-Gated TxPruner Eligibility** - A cold-enabled node never erases hot data that is not evidence-Durable in cold — fail closed, TOCTOU re-checked under the compose lock, gate composes with (not into) the eligibility evaluator (completed 2026-11-16)
- [x] **Phase 15: Evidence-Aware Cold Serving & Forced-Walk Recovery** - Evidence outranks bytes on every path — fixes the cold-chain resurrection gap and the forced-walk GC-evicted conflation; hermetic tri-state evidence fakes land here (completed 2026-11-24)
- [x] **Phase 16: TxPruner × GC Composition Hardening** - Close the stale-LRU erase window, prove the TxPruner×GC interleave matrix, rule the disposal-starvation interplay fail-safe (under-prune) (completed 2026-11-24)
- [x] **Phase 17: Seal Growth Measurement & Decision** - Measure seal growth at representative workloads (probe first — it feeds Phase 15's walk bounds) and record the accept-vs-redesign decision with capacity math (completed 2026-11-24 — 52.000 B/row measured at 10^6/10^7; 10^8 extrapolated 5.2 GB / ~16 s full sweep; accept, redesign deferred to D-11 numeric triggers)
- [x] **Phase 18: Role Downgrade, Collectibility Policy & GC Walk-Gap Exemption** - The two-halves rule recorded as one policy (cold permanent this milestone + GC walk-gap exemption); archive→light downgrade E2E-proven (completed 2026-11-19 — interlock: persisted role fingerprint + `downgrade_acknowledged` ack key + start-normally disarm)
- [x] **Phase 19: Cross-Feature Fault-Race Matrix & Three-Platform CI Capstone** - Induced failures across erase × serve × recovery cannot resurrect, partially validate, or lose last copies; recovery-walk suites green on Windows/macOS/Linux with cold storage ON (completed 2026-11-25 — X1..X11 matrix; Tier-1 fail-closed lane green on all three platforms across dispatches D1–D8, final HEAD `41776b0c0`)

Full phase details, plans, and success criteria: [milestones/v1.2-ROADMAP.md](milestones/v1.2-ROADMAP.md)
Requirements (20/20 complete): [milestones/v1.2-REQUIREMENTS.md](milestones/v1.2-REQUIREMENTS.md)
Milestone audit (passed post-closure — 20/20 requirements, 7/7 phases, 30/30 integration seams, 7/7 E2E flows): [milestones/v1.2-MILESTONE-AUDIT.md](milestones/v1.2-MILESTONE-AUDIT.md)
Milestone summary (onboarding): [reports/MILESTONE_SUMMARY-v1.2.md](reports/MILESTONE_SUMMARY-v1.2.md)

*Deferred signals carried forward (see STATE.md `## Deferred Items` and the v1.2 audit's advisory findings): 13-REVIEW F-1 unbounded `routing_` growth (pubsub_broadcaster_ext.cpp:643 / graphsync_dagsyncer.cpp:361, no eviction path); 13-REVIEW F-2 `bootstrap_walk_max_retries: 0` not expressible (explicit zero silently falls back to 8); soak-scale GC eviction-storm hardening; TEST-03 MinIO-binary live leg (runbook `18-USER-SETUP.md`); permanent cmake.yml ON-leg baseline (activates at develop merge); v2 contract asks — cold collectibility machinery (sgns-blockstore Remove), `DisposedDurable` terminal state, seal storage redesign on D-11 triggers; composition with develop Phase 17/20 once they land.*

</details>

---
*Roadmap created: 2026-10-19 (v1.0) — v1.1 phases added 2026-10-22, shipped & archived 2026-11-10 — v1.2 phases added 2026-11-13, shipped & archived 2026-11-25 — rocksdb-backup workstream*
