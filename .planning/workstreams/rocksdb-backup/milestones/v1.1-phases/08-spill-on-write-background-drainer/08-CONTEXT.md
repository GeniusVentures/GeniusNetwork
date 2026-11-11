# Phase 8: Spill-on-Write & Background Drainer - Context

**Gathered:** 2026-10-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Every CRDT block write spills — the write path and the drain path land together, config-gated. This phase delivers:

1. **SPILL-01 — journal spill at the seam:** a `BlockStoreBackedIpfsDatastore` decorator at the `IpfsDatastore` construction seam inside `GlobalDB::New` (the `globaldb.cpp:329` seam cited in research — exact lines re-verified at implementation) journals block + PendingUpload record into `LocalBlockStore` as **one atomic RocksDB batch** with zero remote I/O on the `dagMutex_`-held write path; `remove` stays hot-only (eviction ≠ CRDT deletion); a benchmark proves publish latency is independent of drainer/s3d state
2. **SPILL-02 — background drainer:** a `ColdStorageManager`-owned drainer thread (backup-loop lifecycle pattern — never `io_`, never the pubsub asio context) drains the journal to S3 with exactly one drain in flight; ops-triggered drains enqueue, never run inline; crash-restart reconciles `GetPendingUploads` leftovers idempotently (S3 createOnly makes re-puts safe); shutdown drains-or-resumes with ordered joins
3. **Backpressure policy (the roadmap's named planner decision):** explicit, implemented, tested — the consensus write path never fails due to remote cold-store state; an s3d-down window leaves publishes succeeding
4. **Hermetic Tier-1 spill tests** (fake S3: journal-write, drain, crash-resume, backpressure) in the Phase-7 fail-closed lane

Out of this phase: read fallback / cold serves (Phase 9), flush-gated durability advancement (Phase 10), retention GC and M3 rebuild tooling (Phase 11), cross-actor fault races and fresh-clone proof (Phase 12), mobile legs (Future — option stays OFF).

Requirements: SPILL-01, SPILL-02 (TEST-01 lane extension rides along per the roadmap's cross-cutting note).

</domain>

<decisions>
## Implementation Decisions

### Backpressure policy (SPILL-02 / SC4 — the roadmap's named planner decision)
- **D-01:** **Unbounded journal + alarm** — when s3d is slow/unavailable the journal grows without bound; writes are never blocked and spill is never skipped; disk is the pressure valve. Bounded-degrade and the opt-in hard cap were rejected: stopping journaling breaks SC1's "every Put journals" letter and creates cold-store gaps whose safety would lean entirely on Phase 10's durability gate; the alarm gives operators the signal instead of silent degradation — **Reversibility:** costly — the outage-behavior contract is what SC4's evidence (s3d-down window, publishes keep succeeding) tests; switching to a bounded shape later changes observable operator-facing behavior and the test suite behind it
- **D-02:** **Dual watermark on pending-upload record count** — warn + critical thresholds measured in pending-upload records (the exact unit `GetPendingUploads` yields); byte-based journal accounting is deferred to the milestone-Future metrics surface — **Reversibility:** reversible — adding byte watermarks later is additive; the count unit composes with the status getter (D-08)
- **D-03:** **Exponential backoff, capped, reset on success** — consecutive s3d failures back off exponentially to a cap; first success resets. Bounded endpoint hammering during long outages, prompt catch-up on recovery. Exact floor/cap values are agent discretion (cap configurable per D-06) — **Reversibility:** reversible — cadence mechanics behind config knobs
- **D-04:** **Local journal-write failure fails the publish** — when cold storage is enabled, hot-write + journal are one mandatory pair; a journal-write failure (disk full, IO error) fails the Put loudly. SC4's "consensus write path never fails due to cold-store state" is scoped to **remote** s3d state: a local journal-disk failure is a node-down event (the hot store typically shares the disk). Best-effort-continue was rejected — it would tolerate temporary silent cold gaps and require needs-rebuild reconciliation machinery before Phase 11's rebuild tooling exists — **Reversibility:** costly — this is the write-path error contract; loosening it later re-opens the silent-cold-gap hazard SC1 exists to prevent

### Config surface (extends the Phase 7 D-01/D-02 schema)
- **D-05:** **Minimal ops knob set only** — exactly: drain poll interval, backoff cap, warn watermark, critical watermark. Everything else (batch size, retry floor, grace window) stays compile-time constant until metrics evidence (milestone-Future) justifies exposure — **Reversibility:** costly — the config schema is a published contract the wallet asset ships; the Phase-8 set defines the surface operators document against
- **D-06:** **Nested `blockstore.backpressure` sub-object** — the four knobs live under `blockstore.backpressure` (e.g. `drain_interval_ms`, `warn_pending`, `critical_pending`, `backoff_cap_ms`; exact names agent discretion). Phase 11's retention gets a sibling sub-object later. Tri-state semantics inherit Phase 7 unchanged: absent sub-object = all defaults; unknown key inside = loud startup failure (D-05 posture of Phase 7) — **Reversibility:** costly — field paths bind the node parser, wallet asset, and operator docs (same class as Phase 7 D-02)
- **D-07:** **Knobs optional, always-on built-in defaults** — absent knobs mean documented built-in defaults with the watermark alarm **always active**. Safe-by-default: a stock deployment that never reads the docs keeps its backpressure signal. No opt-in alarm — **Reversibility:** costly — the always-on default is the operator contract SC4's outage evidence binds

### Alarm observability (v1.1 shape — metrics framework stays milestone-Future)
- **D-08:** **Log + queryable status getter** — rate-limited warn/critical log lines PLUS a status getter on the drainer exposing at minimum: journal depth (pending count), watermark state, drainer health. Assertable in hermetic Tier-1 tests, consumable by GeniusSDK later, and the natural consult point for Phase 10's staging-health posture (ROADMAP Phase 10 SC4: "monitored and exposed so later GC can be inhibited"). Deliberately not a metrics framework — **Reversibility:** reversible — additive getter; fields can grow with later phases
- **D-09:** **Transition + heartbeat logging** — every threshold crossing is logged (down-crossings/recovery included — recovery is signal too) plus a rate-limited heartbeat while a watermark is held, so a multi-hour outage stays visible in logs — **Reversibility:** reversible

### Drainer lifecycle & ownership
- **D-10:** **ColdStorageManager is a GlobalDB member** — mirroring the backup loop: lifecycle tied to `GlobalDB::New`/`Shutdown`, constructed behind the Phase 7 config gate (blank config = nothing constructed, SC2 of Phase 7 preserved). Seam, journal, and drainer teardown live in one place; no CComponentFactory global state; the status getter rides the existing active-accessor pattern (`ActiveDataStore` et al. under `lifecycle_mutex_`); hermetic tests construct the manager directly — **Reversibility:** costly — ownership binds the shutdown join ordering and the construction wiring through `GlobalDB::New`
- **D-11:** **Clean shutdown = bounded grace wait, then resume** — shutdown stops new work and gives the drainer a bounded grace window for in-flight work; journal leftovers resume at next startup via the standard crash-restart reconciliation — one resume code path serves both crash and clean-stop. Full blocking drain was rejected (unbounded shutdown latency during an s3d outage, exactly when shutting down to fix things) — **Reversibility:** costly — SC3's "drains-or-resumes cleanly with ordered thread joins" evidence binds this shape; the grace-window value is what planners size
- **D-12:** **Crash-restart reconciliation is async — the drainer's first poll** — node start latency unaffected; the first poll enumerates `GetPendingUploads` and re-drains as normal operation (idempotent via S3 createOnly); no separate synchronous startup gate — **Reversibility:** reversible — adding a sync gate later would be additive

### The Agent's Discretion
- Exact built-in default values (drain interval, backoff floor/cap, watermark thresholds, grace window, heartbeat rate-limit period) — researcher/planner derive from s3d behavior; they become the documented defaults of D-07
- Exact knob names inside `blockstore.backpressure` (subject to D-06 nesting + Phase 7 strictness inheritance)
- Status-getter signature shape and exact field set (D-08's three fields are the minimum)
- Decorator mechanics: how the atomic block+PendingUpload RocksDB batch composes with the inner `IpfsRocksDb` write, and the ordering of journal vs inner write (subject to D-04's fail-loud contract)
- How the SC1 latency-independence benchmark is built on the `InMemoryS3Client` fake (drainer paused vs running, injected-latency shape)
- Drainer thread-function placement (member function vs free function) and grace-window implementation
- Library hosting split: reuse the shipped v1.0 `UploadDrainer` vs a SuperGenius-side loop calling library APIs — researcher confirms against the shipped contracts
- Tier-1 test target registration mechanics (Phase 7's lane, `ctest -L Tier1 --no-tests=error`, tier-label discipline)
- Ops-triggered drain enqueue surface (mechanism is planner's call; SC2's enqueue-never-inline is the constraint)
- Exact log-message wording (constraint: D-09's transition + heartbeat discipline)
- Enumeration of the exact `IpfsRocksDb` block-key layout (roadmap research note) — phase-local research, planner consumes

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream planning (v1.1)
- `.planning/workstreams/rocksdb-backup/REQUIREMENTS.md` — SPILL-01, SPILL-02 (this phase's letter); Out of Scope table (backup engine untouched, no new deps, blank-config byte-identical)
- `.planning/workstreams/rocksdb-backup/ROADMAP.md` — Phase 8 goal, 5 success criteria, 3 suggested plan waves, research note (the backpressure planner decision is now D-01..D-04; IpfsRocksDb key-layout enumeration is phase-local research)

### Prior phase context (binding decisions this phase builds on)
- `.planning/workstreams/rocksdb-backup/phases/07-supergenius-build-wiring-config-gate/07-CONTEXT.md` — D-01..D-10: the `blockstore` schema this phase extends, tri-state semantics, env surface (credentials-only, never activates), M3 journal-rebuildable posture
- `.planning/workstreams/rocksdb-backup/phases/06-sgns-blockstore-v1-1-library-prerequisites-blake2b-256-cids/06-CONTEXT.md` — installed `OpenMinioS3Client` factory contract (eager validation, zero network I/O at construction) and blake2b CID acceptance this phase's blocks rely on

### Research (v1.1, 2026-10-22)
- `.planning/research/SUMMARY-rocksdb-backup-2026-10-22.md` — phase mapping; the seam/journal/drainer synthesis
- `.planning/research/PITFALLS-rocksdb-backup-2026-10-22.md` — silent-disable and logging pitfalls; backpressure landmines
- `.planning/research/STACK-rocksdb-backup-2026-10-22.md` — file:line citations for the seam and backup-loop pattern

### Code being modified (read before editing)
- `SuperGenius/src/crdt/globaldb/globaldb.cpp` — the `IpfsDatastore` construction seam inside `GlobalDB::New` (~:329 in the research snapshot; re-verify after Phase 7 edits), the backup loop (~:429-477 pattern reference for D-10), `Shutdown()` ordering (`StopBackupLoop()` → broadcaster `Stop()` → `CancelAndCloseNow()` — the drainer stop slots in per D-10/D-11), and the `lifecycle_mutex_` active-accessor pattern the status getter rides
- `GeniusWallet/assets/crdt_config.json` — gains `blockstore.backpressure` schema parity (blank form per Phase 7's D-03 posture)

### Library surface being consumed (frozen v1.0 + Phase 6)
- `thirdparty/sgns-blockstore/include/sgns-blockstore/` — `LocalBlockStore` (atomic block+PendingUpload journal batch, `GetPendingUploads`), `S3BlockStore` (createOnly idempotent re-puts), `S3Client.hpp` / installed `OpenMinioS3Client`
- `thirdparty/sgns-blockstore/test/` — the `InMemoryS3Client` fake driving every hermetic Tier-1 spill test; the shipped upload-journal/UploadDrainer contracts (hosting split confirmed by researcher)
- `thirdparty/sgns-blockstore/docs/testing-tiers.md` — tier contract; Tier-1 fail-closed lane discipline

### Authoritative design
- `supergenius-sharded-ipld-cache-architecture.md` (workspace root) — journal-then-drain discipline, eviction ≠ delete invariant, the write-path vertical this phase delivers

### Conventions & testing
- `Coding Standards.md` (workspace root) — C++ style for `ColdStorageManager` and decorator code
- `.planning/codebase/TESTING.md` — verification-inside-`build/<Platform>/<Config>`-tree rule; `addtest()` registration; Tier-1 lane wiring
- `.planning/codebase/INTEGRATIONS.md` — RocksDB / IPFS / s3d integration context

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Backup loop** (`globaldb.cpp`) — the twice-proven thread lifecycle pattern D-10 mirrors: own thread, explicit Stop + join, never `io_`, never the pubsub asio context
- **Phase 7 `ColdStorageOptions` + strict tri-state parser** — the construction gate the drainer activates behind; blank config constructs nothing (byte-identical bar)
- **v1.0 library contracts** — atomic journal batch, `GetPendingUploads` enumeration, createOnly S3 idempotency (crash-resume safety), `InMemoryS3Client` fake
- **Phase 7 Tier-1 hermetic lane** — the fail-closed `ctest -L Tier1` lane every Phase 8 spill test registers in

### Established Patterns
- Active-accessor pattern under `lifecycle_mutex_` (`ActiveDataStore`/`ActiveCRDTDataStore`/`ActiveBroadcaster`) — the D-08 status getter follows it
- Shutdown ordering discipline: `StopBackupLoop()` first, teardown under `lifecycle_mutex_`, ordered joins — the drainer stop slots in after backup-loop stop, before datastore teardown
- Rate-limited structured logging via the existing logger (spdlog/soralog) — D-09's heartbeat uses it

### Integration Points
- The `IpfsDatastore` construction seam inside `GlobalDB::New` — decorator wraps the inner `IpfsRocksDb` datastore; gated on `ColdStorageOptions` presence
- `blockstore.backpressure` sub-object extends the Phase 7 parser (strictness and tri-state inherited)
- `ColdStorageManager` member slots into `GlobalDB::Shutdown()` ordering per D-10/D-11

</code_context>

<specifics>
## Specific Ideas

- Locked config shape (blank sub-object = all defaults, alarm always on; exact names/defaults agent discretion):
  ```json
  "blockstore": {
    "endpoint": "", "bucket": "", "access_key": "", "secret_key": "",
    "backpressure": {
      "drain_interval_ms": 0, "warn_pending": 0, "critical_pending": 0, "backoff_cap_ms": 0
    }
  }
  ```
  (`0` = built-in default; required S3 fields and tri-state semantics per Phase 7)
- **SC4 scope clarification (D-04):** "never fails due to cold-store state" covers **remote** s3d state only — a local journal-write failure fails the Put loudly when cold storage is enabled
- Watermark unit is pending-upload **record count** via `GetPendingUploads` — not bytes

</specifics>

<deferred>
## Deferred Ideas

- Byte-based journal watermarks — milestone-Future metrics surface (with journal-depth metrics)
- M3 needs-rebuild reconciliation tooling — Phase 11 (with GC, its consumer)
- Metrics framework beyond the D-08 status getter — milestone-Future
- Bounded-degrade / opt-in hard cap for disk-constrained operators — explicitly **rejected** in D-01, not deferred; revisit only with a concrete disk-constrained deployment requirement

### Reviewed Todos (not folded)
- `2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md` — "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" (area: testing) matched Phase 8 by keywords only (crash, create, path, cpp); ruled unrelated to the blockstore workstream in Phases 6 and 7 — standing ruling carried forward; stays a backlog todo for its own task/phase

</deferred>

---

*Phase: 8-Spill-on-Write & Background Drainer*
