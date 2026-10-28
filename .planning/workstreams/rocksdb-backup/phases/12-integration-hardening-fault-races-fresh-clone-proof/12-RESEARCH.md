---
phase: 12
phase_name: Integration Hardening, Fault Races & Fresh-Clone Proof
workstream: rocksdb-backup
milestone: v1.1
requirements: TEST-02
researched: 2026-10-27
researcher: gsd-phase-researcher
confidence: HIGH
---

# Phase 12: Integration Hardening, Fault Races & Fresh-Clone Proof - Research

**Researched:** 2026-10-27
**Domain:** cross-actor fault-race evidence over the shipped Phase-8/9/10/11 cold-storage stack (drainer + flush cadence + cold-read chain + re-warm executor + retention GC), an s3d-outage soak, and a three-platform CI fresh-clone proof
**Confidence:** HIGH (every load-bearing in-repo fact verified at file:line this session; the one genuinely open implementation choice — how the ON CI lane obtains the non-installed test fakes — is isolated with options in §5.3 and Open Questions)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions (D-01..D-16 — bold statements verbatim from `12-CONTEXT.md`; full rationale/reversibility text lives there)

**Fresh-clone proof surface (SC4)**
- **D-01:** The proof is the CI ON-lane on all three platforms, enabled by a thirdparty tag build that SuperGenius pulls from a specified tag — the thirdparty release cut happens in/around this phase; SuperGenius CI consumes that specified tag. No local fresh-clone run — CI is the sole proof surface (also avoids a ~100+ GB thirdparty build on the dev machine's W: drive)
- **D-02:** Both CI surfaces carry the ON lane — (a) a permanent cold-storage-ON configure leg in `cmake.yml`, and (b) the `build-release-tags.yml` dispatch with the `thirdparty_tag` input and cold storage ON for the one-time milestone evidence — with the testing flag enabled on the tag build so `ctest -L Tier1` actually runs there
- **D-03:** User checkpoint for the thirdparty tag cut — the phase wires everything; a human checkpoint has the user dispatch the thirdparty tag build and confirm the tag exists before the SuperGenius ON-lane runs against it. The executor never dispatches workflows and never pushes
- **D-04:** "Only pushed commits" is inherent + fail-closed validated — where a runbook/script kicks off, it validates the tested SHAs exist on their remotes before starting
- **D-05:** Evidence is minimal: a checklist doc with results — SHAs, tags, platforms, pass counts; raw logs live in CI run history, not committed artifacts

**Soak assertion semantics (SC3)**
- **D-06:** "Bounded journal growth" = no-multiply + drain — during the outage, pending-record count ≤ distinct published CIDs, the Phase-8 watermark + alarm fire at their configured thresholds, AND after the fault clears the journal drains to zero (or pre-outage baseline) within a bounded window. Two phases: outage + recovery. A literal hard cap was rejected (Phase-8 D-01..D-04 locked unbounded-journal + watermark + alarm)
- **D-07:** Both soak shapes — an iteration-based soak (N publish cycles under sustained fault; deterministic, CI-safe) in the Tier-1 CI lane, plus one dev-gated wall-clock soak (tens of minutes, never in CI) with committed evidence
- **D-08:** Full-stack actors under one sustained outage — publishes + drainer attempts + flush-cadence backoff + GC inhibited (staging-unhealthy flag) + peer cold-fetch attempts + graphsync serving all inside the soak window
- **D-09:** Teardown covers clean Stop() AND kill-9 mid-soak — clean Stop() under load (bounded grace-flush attempt, ordered joins backup-loop → drainer → GC thread → cold-serve executor, no hangs/deadlocks); kill-9 mid-soak + restart asserts journal reconciliation, pending re-drain, no duplication

**Race & resurrection methodology (SC1/SC2)**
- **D-10:** Deterministic barriers + randomized jitter, both — deterministic barrier-driven interleavings for the named hazard crossings plus randomized `FaultController` timing-jitter iterations with end-state invariant checks
- **D-11:** Matrix = pairwise + all-three, timed at the risky phase boundaries — evict×serve, evict×drain, serve×drain plus the simultaneous triple, each crossing driven at the dangerous moments: GC mark, grace-expiry, delete-batch, delete-time re-check/cancel, re-warm attach
- **D-12:** Zero-lost-blocks proof = per-scenario asserts + full end-state audit + log scans — each scenario asserts its expected end state; at suite end an audit walk asserts every published CID is exactly one of {hot, cold-local, S3-retrievable CID-verified, disposed-with-remote-copy}; log-scan asserts prove zero peer-blacklist writes and zero misattributed `Corrupt` originating from storage failures
- **D-13:** Resurrection counter-test lives at node level via pubsub re-delivery — in-process GlobalDB pair: put value → CRDT delete (tombstone) → force GC past retention + grace (tiny test-config ages) → evict → re-deliver the pre-delete delta block through the pubsub path → assert the value is absent in BOTH nodes' set queries, no re-integration occurred (disposed-marker dedup), and the remote copy is intact

**Fix-forward posture**
- **D-14:** Fixes may go additive into the library — defects found by the evidence may be fixed in SuperGenius and additively in sgns-blockstore; no removals or renames of public API. Any library change means the thirdparty tag checkpoint (D-03) re-cuts before the fresh-clone proof runs
- **D-15:** Deep defects checkpoint the user — one failed fix attempt or a locked-decision touch ⇒ pause with findings + options; no unbounded autonomous fix loops
- **D-16:** Minimal test seams in product code are allowed — deterministic race-driving may add small test-only hook/barrier points, test-build-gated or otherwise inert in release builds, kept minimal and documented per seam

### The Agent's Discretion (verbatim from 12-CONTEXT.md)
- Exact barrier/hook mechanics per named crossing (which seams D-16 needs: GC mark/grace-expiry/delete-batch/delete-time-re-check, re-warm attach, drain snapshot)
- N for the Tier-1 iteration soak; the wall-clock soak's duration (tens of minutes) and its committed-evidence artifact format
- The bounded drain window's assertion form (timeout bound, polling cadence)
- `cmake.yml` ON-leg shape (matrix leg vs separate job) and the exact dispatch-toggle wiring that enables testing on the tag build (D-02)
- The tier-label audit's mechanics (SC4: script vs checklist — verifying every new test is labeled Tier1/Tier2/Tier3 and gated accordingly)
- The minimal checklist doc's location and shape (D-05)
- Log-scan mechanics for the zero-blacklist / zero-misattributed-Corrupt asserts
- How the resurrection test forces GC past retention + grace (tiny ages in test config vs direct pass invocation)
- Regression-test discipline per landed fix (failing-first test in the Tier-1 lane)
- Per-scenario expected-end-state table design (which end states are legal per crossing)
- Randomized-iteration count and seed policy for the jitter legs (reproducibility on failure)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope. (Reviewed todo "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" — fourth consecutive phase reviewed-not-folded; stays backlog.)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description (REQUIREMENTS.md) | Research Support |
|----|-------------------------------|------------------|
| TEST-02 | Hardening evidence — evict × serve × drain fault races, a resurrection counter-test (restore must not resurrect GC'd values), an s3d-unavailable soak with bounded journal growth, and fresh-clone Tier-1 green on Windows/Linux/macOS with cold storage ON | §1 (race topology + named crossings + seam inventory), §2 (fault-kit gaps for D-10/D-11), §3 (resurrection path + forcing mechanics), §4 (soak observables + precedents + teardown ordering), §5 (CI wiring + the fakes-not-installed landmine + tier-label audit mechanics), §6 (landmines), Environment Availability |
</phase_requirements>

## Project Constraints (from AGENTS.md / copilot-instructions.md / workstream locks)

- C++17/C++20, CMake — match existing SuperGenius conventions; **no new external dependencies** (workstream Out of Scope: "New external dependencies (AWS SDK, curl, etc.)").
- Corelinux-derived style (`Coding Standards.md`): Ullman braces, PascalCase types/methods, `m_`/trailing-underscore members, `Get`/`Is`/`Set` prefixes, Doxygen on public interfaces, `outcome::result<T>` for fallible operations.
- Every library result guarded with `has_value()` BEFORE `.value()` (standing landmine).
- Header hygiene (binding since Phase 7): `globaldb.hpp/.cpp`, `ColdStorageStack.hpp` never include gated sgns-blockstore headers; `ColdStorageManager.hpp` is a GATED TU header (SGNS_COLD_STORAGE only); ungated code reaches the stack only through `ColdStorageStack` bridges; status types stay plain [VERIFIED: ColdStorageManager.hpp:6-11 — "GATED TU HEADER"]. New D-16 seams must respect this boundary.
- Blank `blockstore` config = nothing constructed = byte-identical behavior — every new path inherits; D-16 seams must be inert when cold storage is disabled or in release builds.
- Testing discipline (`.planning/codebase/TESTING.md`): verification inside `build/<Platform>/<Config>`; `addtest()` + `set_tests_properties(... LABELS "Tier1")`; `ctest -L Tier1 --no-tests=error` fail-closed lane; the library's `tier1_audit_check.cmake` bans fixed sleeps in test sources [VERIFIED: thirdparty/sgns-blockstore/test/tier1_audit_check.cmake:37-43 — patterns `std::this_thread::sleep_for`, `sleep_for`, `sleep[(]`, `usleep[(]`, `nanosleep[(]`, `Sleep[(]`].
- Commit discipline: innermost submodule first (thirdparty bumps precede SuperGenius commits — the Phase-10/11 SUMMARY commit patterns).
- `workflow.nyquist_validation: false` [VERIFIED: .planning/config.json] — Validation Architecture section omitted per phase instructions. `security_enforcement: true`, ASVS L1, block-on high — Security Domain included below.

## Summary

Phase 12 is an evidence phase over four shipped, guard-tested actors — the Phase-8 drainer + backpressure/watermark, the Phase-9 cold-read chain + re-warm executor, the Phase-10 flush cadence + staging health, and the Phase-11 GC thread + two-phase eviction — and the milestone's reproducibility contract. Three structural facts shape everything. **(1) The thread/lock topology is now fully enumerable.** Six concurrency lanes touch the cold-storage state: the drainer thread, the GC thread, the pubsub delivery-lane thread (single-threaded — serve/read/merge callbacks must never block), the CRDT DAG workers, the re-warm worker thread, and arbitrary publisher threads; they meet at exactly four locks (`cold_store_mutex_`, `remote_store_mutex_`, `admin_mutex_`, `dagMutex_`) plus the heads mutex, the blacklist/routing mutexes, and the LRU cache (§1.1). Every D-11 crossing maps onto a named interleaving at a named line — and the only interleavings that can produce SC1's feared outcomes (`Corrupt`-from-race, lost blocks, storage-attributed blacklist writes) are the ones where the serve path's cold fetch or the drain path's remote Put crosses the GC's HALF1/HALF2 window and the delete-time re-check. **(2) The fault kit has failure injection but almost no timing injection.** `InMemoryS3Client` scripts only failure kinds (`S3FaultKind` None/Unavailable/CorruptData/Unauthorized, key-scoped overlay, byte-flip); the ONLY existing timing surfaces are the admin fake's `SetSlowFlushDelayMs` + `SetOnFlush` barrier hook [VERIFIED: InMemoryS3AdminClient.hpp:73-97]. D-10/D-11 therefore require an additive extension — per-op latency + on-op barrier hooks on the S3 data fake (mirroring `SetOnFlush`) plus D-16 barrier seams at the GC-side crossings (`SetGcMidPassHookForTesting` exists but fires only between walk and heads-re-check, not at grace-expiry/delete-batch/HALF1↔HALF2). **(3) The fresh-clone proof has one hard, previously-unforced wiring fact:** the SuperGenius cold-storage Tier-1 targets include the NON-installed library test fakes via a relative source path (`../../../../thirdparty/sgns-blockstore/src` — `InMemoryS3Client.hpp`/`InMemoryS3AdminClient.hpp` live in `thirdparty/sgns-blockstore/src/`, and the library installs only `include/` [VERIFIED: sgns-blockstore/CMakeLists.txt:65-73]), while CI extracts the thirdparty RELEASE tarball (install trees only). No CI lane has ever compiled these tests. The ON leg must additionally materialize the fakes' source (sparse checkout overlay or an overridable include-dir variable) — §5.3 rules the options; this is the phase's one OPEN planner decision with a strong recommendation.

On the evidence side, everything else slots into proven instruments: the resurrection path is fully pinned (pubsub receive → `AddMultiCIDInfo` → four-term `HasBlock` whose disposed-marker term drops re-delivery before any merge — with the CRDT merge loop as the trimmed-marker fallback where tombstone dominance must hold), the soak's observables are already atomic-backed (`pending_upload_count`, `watermark`, `staging_healthy_`, held-watermark heartbeat lines), the Phase-10 `shutdown_under_load_slow_flush_bounded` and Phase-8 `s3d_down_window_keeps_publishing` tests are the exact shapes D-07/D-09 extend, and the shutdown join order D-09 asserts is verified in code (backup loop → drainer join → final flush → GC join → re-warm executor → lifecycle teardown → broadcaster → CRDT close).

**Primary recommendation:** Add the fault-kit timing surface first (S3 data-fake `SetLatencyMs`/`SetOnOp` hooks + GC-side barrier seams at the five named crossings — all additive, D-16-documented), build the race matrix over the existing real-fixture harness (`cold_storage_gc_test` fixture + counting/prefix-spy S3 + hot store), drive resurrection through `PubSubBroadcasterExt::OnMessage` re-delivery on the two-GlobalDB topology (full-libp2p lane once, `pubsub_graphsync_test` shape; wrapper-level for the rest), compose the soak from the Phase-8/10 precedents with tiny configured watermarks, and wire the ON CI leg with a sparse thirdparty-source overlay (or include-dir override) BEFORE the tag cut so D-03's checkpoint only has to fire once.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Timing-injection surface (D-10/D-11) | `InMemoryS3Client` (library test kit, additive) | GC/manager D-16 seams (SuperGenius) | The crossings happen at S3-op boundaries and GC phase boundaries; hooks at both ends make interleavings drivable from the test thread; the admin fake's `SetOnFlush` is the in-repo precedent |
| Deterministic barriers (D-10) | Test-only hooks in product code (D-16: manager GC seams, re-warm enqueue) | S3-fake on-op hooks | Barriers must fire INSIDE the actor's critical sections (e.g., between heads-re-check and HALF1) — only a product-side seam reaches there; test-build-gated or inert-in-release |
| Randomized jitter legs (D-10) | `InMemoryS3Client` latency scripting | seeded RNG in the test harness | Jitter belongs at the I/O boundary where real timing variance lives; seed policy gives reproducibility |
| Race-matrix end-state audit (D-12) | Test-side audit walk over {hot, cold-local, S3, disposed} | counting S3 client + prefix-spy hot store | The legal-state enumeration is test logic over shipped observation surfaces (`Get`/`Has`/`IsDisposed`/`ObjectKeys`) |
| Resurrection counter-test (D-13) | `PubSubBroadcasterExt::OnMessage` re-delivery over two-GlobalDB topology | full libp2p lane (`pubsub_graphsync_test` shape) for one end-to-end case | The pubsub path is the realistic vector; the disposed-marker dedup and (trimmed-marker) tombstone dominance both live on this path |
| Soak harness (D-06..D-09) | SuperGenius Tier-1 suite (iteration soak) + dev-gated wall-clock binary | `ColdStorageManager` status atomics + library journal enumeration | Assertions ride shipped observables; no new product observation surface needed |
| Fresh-clone ON lane (D-01/D-02) | SuperGenius CI workflows (`cmake.yml` leg + `build-release-tags.yml` posture) | thirdparty `build-targets.yml` dispatch (user checkpoint D-03) | CI is the sole proof surface by D-01; the tag cut is the thirdparty dispatch the user runs |
| Fake-source availability in CI (§5.3) | SuperGenius test CMake (overridable include dir) or ON-leg sparse checkout overlay | (option C) install the fakes — library change, D-14 re-cut | The fakes are source-tree-only; the tarball carries install trees only — the ON leg must bridge this without a library change (recommendation §5.3) |
| Tier-label audit (SC4) | CMake-script static audit (library `tier1_audit_check.cmake` precedent) | checklist doc (D-05) | Registration-vs-label count + gating check is mechanically checkable; the library already proves the CMake-script shape |

## Standard Stack (all in-repo — no external packages)

### Core
| Component | Version/State | Purpose | Why Standard |
|-----------|---------------|---------|--------------|
| `sgns-blockstore` fault kit (`InMemoryS3Client`, `InMemoryS3AdminClient`, `FaultController`, `S3FaultKind`, `S3AdminFaultKind`, `CrashPoint`) | shipped; gains additive timing hooks this phase | Every race/soak/resurrection instrument | The kit every Phase 7-11 hermetic test already drives; additive extension per D-14 |
| `ColdStorageManager` (GC thread + drainer + flush cadence + staging health) | shipped Phases 8/10/11 | The evict/drain actor under race; `GcPassOnce` driven-pass seam; D-16 seam host | Single home of both store handles + both mutexes; `GetStatus()` atomics are the soak's assertion surface |
| `ColdReadService` + `ColdReadFallback` hook + `ColdServeDagService` | shipped Phase 9/11 | The serve actor; re-warm executor (kRewarmBudget 4 s, queue 64, shutdown grace 5 s) | The deadline-budget clause rides these compile-time constants |
| `PubSubBroadcasterExt` + gossip delivery lane | shipped (dedicated delivery lane in ipfs-pubsub) | The resurrection re-delivery vector | OnMessage → AddMultiCIDInfo → HasBlock is the dedup point D-13 exercises |
| SuperGenius CI (`cmake.yml` "Release Build CI" + `build-release-tags.yml`) + thirdparty `build.yml`/`build-targets.yml` | shipped | The SC4 proof surface; ON-leg + tag-consumption wiring | D-01/D-02 plug into existing matrix legs, toggles, and the `thirdparty_tag` input |

### Supporting
| Component | Purpose | When to Use |
|-----------|---------|-------------|
| `poll_until`/`assertWaitForCondition` helpers (test side) | deadline-bounded polling (never fixed sleeps) | every new test — the library audit bans fixed sleeps; SuperGenius tests already use `PollUntil` [VERIFIED: cold_storage_durability_test.cpp:833] |
| Counting S3 client wrapper + prefix-spy hot store (Phase-11 fixture) | zero-network-traffic proofs + keyspace-boundary proofs | race scenarios + D-12 audit walk |
| `SetBlacklistBackoffTimeoutForTest` (syncer) | blacklist state inspection without production backoff windows | zero-blacklist asserts (state-based; log-scan optional) [VERIFIED: graphsync_dagsyncer.cpp:1189-1192] |
| `pubsub_graphsync_test.cpp` harness shape | real two-GlobalDB in-process libp2p topology | one full-wire resurrection case (D-13's realistic vector at full fidelity) [VERIFIED: test/src/graphsync/pubsub_graphsync_test.cpp:91-120] |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| S3-fake on-op hooks (recommended) | test-local decorator subclass of `S3Client` wrapping the fake | A test-local decorator adds latency/hooks WITHOUT touching the library at all — zero D-14 re-cut risk. Recommended as the FIRST choice for latency+jitter; library hooks only if a barrier must fire inside `S3BlockStore`'s own verify path (it does not — crossings are at manager/syncer granularity). Planner picks per seam |
| Sparse-checkout overlay for fakes in CI (recommended) | install the fakes into the library's install tree | Installing the fakes is a library change (installed-surface growth, hygiene gates, D-14 re-cut) for a CI-only problem; overlay/override solves it in the consumer repo. See §5.3 |
| Iteration soak in Tier-1 + wall-clock soak dev-gated (D-07, locked) | single wall-clock soak | locked — not open |

**Installation:** none — no packages, no Package Legitimacy Audit required (no external packages installed this phase).

## Package Legitimacy Audit

Not applicable — this phase installs no external packages (in-repo C++/CMake/CI only).

## 1. SC1 — The Race Topology, Verified

### 1.1 Threads and locks (the full map)

**Threads/lanes that touch cold-storage state:**

| # | Lane | Created at | Role in the races |
|---|------|-----------|-------------------|
| T1 | Drainer thread (`thread_`) | `ColdStorageManager::Start()` [VERIFIED: ColdStorageManager.cpp:163-240] | `DrainOnce` + `AdvanceDurabilityOnce` per cycle; first poll = crash-restart reconciliation |
| T2 | GC thread (`gc_thread_`) | `Start()` under `gc_enabled_` [VERIFIED: ColdStorageManager.cpp:229-257] | `GcPassOnce` loop at `gc_interval_ms` cadence |
| T3 | Pubsub delivery-lane thread | `GossipPubSub::Start` — dedicated `m_delivery_context`/`m_delivery_strand`/`m_delivery_thread` [VERIFIED: thirdparty/ipfs-pubsub/src/ipfs_pubsub/gossip_pubsub.cpp:506-522, 764-812] | `OnMessage` → `AddMultiCIDInfo` → `HasBlock`; single-threaded strand — a blocked callback blocks ALL deliveries (depth warning at `kDeliveryDepthWarning`) |
| T4 | CRDT DAG workers | CrdtDatastore worker pool (`dagWorkerMutex_`, `pending_jobs_`) | merge path (`MergeDataFromDelta`), `HasBlock` at crdt_datastore.cpp:706/:1881 [VERIFIED: crdt_datastore.cpp:705-712, 1879-1882] |
| T5 | Re-warm worker (`rewarm_thread_`) | `ColdReadService::Start` [VERIFIED: ColdReadService.cpp:346-351] | `RewarmWorkerLoop` with `kRewarmBudget` deadline check [VERIFIED: ColdReadService.cpp:422] |
| T6 | Publisher threads | arbitrary (`PutKey` callers) | decorator `set()` journals under `cold_store_mutex_` [VERIFIED: BlockStoreBackedIpfsDatastore.cpp:53-61] |
| T7 | Backup loop | GlobalDB (Phase-0 era) | joined FIRST at shutdown |

**Locks:**

| Lock | Guarded by it | Taken at (verified) |
|------|---------------|---------------------|
| `cold_store_mutex_` (shared ptr, ONE instance) | ALL `LocalBlockStore` access (library single-threaded-use contract) + journal transitions | decorator set :61; drainer snapshot :438 / marks :509; flush snapshot :583 / marks :646; `GetUploadState` :676; GC eligibility :900, mark capture :1025, HALF1 :1121, GetDisposed :1191, Trim :1252 |
| `remote_store_mutex_` (shared ptr) | ALL `S3BlockStore` access (drain Puts vs cold-read Gets) | drainer remote Put phase per item :489; orphan-rescan remote Get :1216; cold-read chain S3 Gets (Phase-9 wiring) |
| `admin_mutex_` | admin client (flush/stats) vs `RefreshStagingStats` | drainer tick :605-606; refresh :688-689; final flush :305 |
| `dagMutex_` | hot DAG service ops | `addNode` :307; `GetNodeFromMerkleDAG` :1270; (also :615/:624/:1062/:1068) |
| heads `mutex_` (CrdtHeads) | in-memory heads cache | `GetHeadList` shared-lock reads (crdt_heads.cpp — snapshot source) |
| `blacklist_mutex_` | blacklist map | `AddToBlackList` :1127, `IsOnBlackList` :1197 |
| `gc_hook_mutex_` | mid-pass hook swap | ColdStorageManager.cpp:704, :974 |
| LRU cache internal | `lru_cid_cache_` | `GrabCIDBlock`/`add` (FetchNodeFromColdStorage re-cache :758) |

### 1.2 The GC pass step order (where the evict actor is, exactly)

`GcPassOnce` fixed order [VERIFIED: ColdStorageManager.cpp:786-855]: (0) stop check → (1) `RefreshStagingStats` + staging gate (unhealthy ⇒ inhibited tick) → tick bookkeeping → `FinishOrphanedHotCleanups` (skipped under dry_run) → `EvaluatePass` → `ProcessDueMarks` → `TrimDisposedMarkers` → status + `WriteEpochWatermark`.

`EvaluatePass` [VERIFIED: :857-1066]: heads snapshot (`GetHeadList`) → `WalkReachable` (per-node reads via `GetNodeWithoutRequest`; `dagMutex_` only inside `GetNodeFromMerkleDAG`) → eligibility under `cold_store_mutex_` (`GetDurableWithSpillTime` + `GetUploadState` per candidate; strictly-past age; reachable ∖; EXACTLY `kEvictionDurabilityGate`) → mid-pass hook (under `gc_hook_mutex_`) → heads-equality re-check (ANY diff ⇒ abort, zero candidates) → mark capture (under `cold_store_mutex_`: cold-dir `Get`, delta parse for row keys; then seal check on hot store; everything stored in `EvictingMark` including the mark-time heads snapshot).

`ProcessDueMarks` [VERIFIED: :1072-1141]: per mark — defer check (`gc_tick_counter_ <= mark.mark_tick || now < marked_at + grace_ms` ⇒ retain) → delete-time re-check (CURRENT heads vs **the mark's own snapshot**; ANY diff ⇒ cancel, keep bytes) → dry_run retain → **HALF1** `EvictLocalAndMarkDisposed` under `cold_store_mutex_` (failure ⇒ mark retained) → **HALF2** `RunHotCleanup` (hot batch: binary CID key + `<cid>sealed` + exactly the block's own s-rows; then `DeleteCIDBlock` LRU invalidation AFTER deletes) — **HALF2 runs OUTSIDE `cold_store_mutex_`**.

### 1.3 The serve paths (where the serve actor is)

- **Requester/local read:** `getNode` → LRU → hot (`GetNodeFromMerkleDAG`) → **cold-before-peers** `FetchNodeFromColdStorage` (Local→S3 via `cold_read_hook_->Get`, CID-verified, `Rehydrate` + LRU add) → peer ladder under `kTotalFetchTimeout = 20 s` [VERIFIED: graphsync_dagsyncer.cpp:28, :328-:564]. `GetNodeWithoutRequest` is the same chain without the peer leg (:702-725).
- **Responder:** graphsync serves via `ColdServeDagService::getNode` — hot-first delegation to `inner_->getNode`; on miss, fire-and-forget `EnqueueRewarm` and return the error (honest don't-have; RS_NOT_FOUND) [VERIFIED: :108-125]. The wrapper is installed at `graphsync_->start(cold_serve_wrapper_, ...)` (:816-817).
- **`HasBlock` (4 terms):** hot → LRU → `HasLocalCold` → `HasDisposed` [VERIFIED: :663-700] — the last is dedup-only (D-12 split): direct reads never consult the marker as absence.

### 1.4 The drain path (where the drain actor is)

`DrainOnce` [VERIFIED: ColdStorageManager.cpp:424-:540]: pending snapshot + item fetch under `cold_store_mutex_` (:438) → remote Put phase **UNLOCKED** w.r.t. `cold_store_mutex_` but per-item under `remote_store_mutex_` (:489) → journal marks under `cold_store_mutex_` (:509). `AdvanceDurabilityOnce` [VERIFIED: :542-:672]: Accepted snapshot under `cold_store_mutex_` (:583) → `Flush` + `GetUploadStats` under `admin_mutex_` (:606) → `MarkUploadedDurableMany` under `cold_store_mutex_` (:646), marking EXACTLY the pre-flush snapshot (D-03).

### 1.5 The named risky interleavings (D-11 matrix → concrete crossings)

| Crossing | Risky moment | Interleaving | Expected-safe outcome (assert) |
|---|---|---|---|
| evict × serve | GC HALF1 committed, serve's cold fetch already past Local-miss | fetch resolves from **S3** (remote copy intact — eviction ≠ delete); or re-warm re-journals via `Rehydrate` (safe re-learn, fresh journal Pending) | block retrievable CID-verified; no `Corrupt`; end state ∈ D-12 legal set |
| evict × serve | `RunHotCleanup` hot batch vs responder's hot read / LRU grab on same CID | reader may hit hot bytes mid-window or miss and fall to cold chain; `DeleteCIDBlock` AFTER deletes keeps `HasBlock` honest (A6) | never a torn read; `HasBlock` never true-with-no-bytes (the disposed term answers) |
| evict × serve | re-warm attach (`EnqueueRewarm`) racing mark/delete | re-warm of an about-to-evict CID re-journals it (Pending) — next pass sees non-Durable ⇒ not eligible; or post-evict re-warm = re-learn | no lost block; journal state consistent; marker coexists with re-learned bytes (Phase-11 proven) |
| evict × drain | GC eligibility enumeration vs drainer's Accepted→Durable mark window | a CID mid-advance is Accepted (not Durable) ⇒ not eligible; a just-marked Durable CID becomes eligible next pass — safe both ways | no eviction of non-Durable bytes (gate is compile-time) |
| evict × drain | drainer remote Put (unlocked phase) vs HALF1 journal delete | drain snapshot holds the item; eviction requires Durable — a Pending/Accepted CID in the drain snapshot can't be evicted concurrently (state gate, both under `cold_store_mutex_` when touching journal) | no drain item ever hits "bytes evicted" (Pitfall-4 class) |
| serve × drain | injected S3 latency holds `remote_store_mutex_` per-op while a peer cold-fetch (re-warm) needs the same lock | serialized per-op; the fetch must still complete within `kRewarmBudget` (4 s) or the budget check drops it (queue re-enqueue cheap per D-07) | fetch within deadline budget or honest don't-have; no deadlock; no peer-blacklist write |
| all three | grace-expiry processing + a publish making the CID reachable again + a serve in flight | delete-time re-check (heads vs mark's snapshot) cancels — bytes kept, CID returns to normal | cancel path taken; end state hot; no `Corrupt`; no blacklist |
| all three | delete-batch mid-flight + drainer tick + pubsub re-delivery of the same CID | HALF1 atomic; re-delivery drops at `HasDisposed` (marker written in HALF1); drain unaffected (journal record deleted in HALF1 — a re-learn re-journals fresh) | exactly-once semantics; audit-walk legal end state |

**The blacklist-write sites SC1 polices** [VERIFIED: graphsync_dagsyncer.cpp :421 (request setup failed), :466 (request state not found), :523 (FAILED state + connection-failure status)] — each is behind `IsConnectionFailureStatus` and cold-classification precedence (`ApplyColdPrecedence`, :39 comment: "any cold classification override TIMED_OUT / PEER_BLACKLISTED …"). A storage failure surfacing as a peer failure would be the defect class; the assert is state-based (`IsOnBlackList` empty after scenarios with no real peers) plus optional log-scan of `Blacklisting peer` lines.

### 1.6 Seams that EXIST vs seams D-16 must ADD

**Existing (verified):**
- `ColdStorageManager::SetGcMidPassHookForTesting` — fires between walk and heads-equality finalization ONLY [VERIFIED: ColdStorageManager.cpp:974-980]
- `LocalBlockStore::SetCrashPointForTesting` (Put-path crash seam) [VERIFIED: LocalBlockStore.hpp:468]; `SetSpilledAt` (age test seam, :347)
- Library `FaultController` entry-gate on the eviction batch (11-02's crash-atomicity case used it; the single Write has no mid-commit window)
- `InMemoryS3AdminClient`: `SetStats`, `SetAdminFault`, **`SetSlowFlushDelayMs`** (sleep-based latency), **`SetOnFlush`** (post-flush barrier hook), `flush_count()`/`stats_count()` [VERIFIED: InMemoryS3AdminClient.hpp:60-97]
- `InMemoryS3Client`: `SetFault`/`SetFaultForKey` (op + key-scoped), `SetFlipBytesForKey`, `ClearFaults`, `ObjectKeys()` [VERIFIED: InMemoryS3Client.hpp:48-118]
- `GraphsyncDAGSyncer::SetBlacklistBackoffTimeoutForTest` (:1189)
- `GcPassOnce` is directly callable from tests (the driven-pass seam) [VERIFIED: ColdStorageManager.hpp:299-301 doc]

**Missing for D-10/D-11 (the D-16 list, mapped to crossings):**
1. **Grace-expiry / pre-delete-batch seam** — hook at the top of `ProcessDueMarks` per-mark processing (before the heads re-check) → drives "reachable-again at the last moment" and "serve in flight at delete"
2. **Delete-time re-check seam** — hook between the heads re-check and HALF1 → drives the cancel-vs-commit knife edge
3. **HALF1↔HALF2 seam** — hook between the library batch and `RunHotCleanup` → drives crash-window races (serve reads hot bytes while cold-dir + journal are gone)
4. **Re-warm attach observation** — `ColdReadService` enqueue/coalescing observation point (or use the S3-fake on-op hook as the attach barrier)
5. **Drain-snapshot observation** — the admin fake's `SetOnFlush` covers the flush boundary; a drain-side equivalent is an on-op hook on the S3 data fake firing at the first remote Put
6. **S3 data-fake timing**: per-op/per-key latency (`SetLatencyMs(op[, key])`) and on-op barrier hooks (`SetOnOp(op, fn)`) — mirroring `SetOnFlush`; PLUS a jitter primitive (bounded random delay around a base) for D-10's jitter legs

**Recommendation (§ Alternatives):** implement latency/on-op timing as a **test-local decorator around `S3Client`** (wraps the fake; no library change, no re-cut) and spend D-16 product seams only on the GC-side boundaries 1-3 (+ optionally 4) — gated exactly like `SetGcMidPassHookForTesting` (null in production, documented per seam, never called by production code).

## 2. Fault Kit — What Exists Today (D-10/D-11 gap analysis)

- Library `FaultController` conformance seam: `FaultKind { None, Unavailable, CorruptData, Unauthorized }` — failure classes ONLY, no timing [VERIFIED: FaultController.hpp:17-24]
- `S3FaultKind { None, Unavailable, CorruptData, Unauthorized }` over `S3Op` on the data fake; key-scoped overlay precedence [VERIFIED: S3Client.hpp:120-134, InMemoryS3Client.cpp:20-52]
- `S3AdminFaultKind { None, Unreachable, FlushFails, GarbageStats }` [VERIFIED: S3AdminClient.hpp:109-114]
- Admin fake timing: `SetSlowFlushDelayMs` sleeps INSIDE `Flush` (tests keep delays tiny); `SetOnFlush` hook fires after every non-faulted-at-entry Flush — the comment calls it "the barrier point tests use to observe an in-flight flush from the scripting thread" [VERIFIED: InMemoryS3AdminClient.hpp:73-80, doc verbatim]
- **Conclusion:** timing injection exists ONLY on the admin/flush boundary. The evict/serve/drain crossings all sit on the S3 data path and the GC thread's phase boundaries — both need the additive surface described in §1.6. This is the enabling work of Wave 1 (it gates the whole matrix).
- Determinism discipline: the library's Tier-1 audit bans fixed sleeps in test sources [VERIFIED: tier1_audit_check.cmake:37-43]; the repo's known hazard class is sleep-based test polling (the `PollUntil`/`assertWaitForCondition` helpers are the sanctioned shape; Phase-10's soak-adjacent tests poll with deadlines, e.g. `PollUntil(..., std::chrono::milliseconds(10000))` [VERIFIED: cold_storage_durability_test.cpp:833]). Barriers make the deterministic legs sleep-free by construction.

## 3. SC2 — Resurrection Counter-Test Path, Verified

**The re-delivery vector (pubsub receive path):**
`GossipPubSub` delivery lane (single-threaded strand) → `PubSubBroadcasterExt::OnMessage` [VERIFIED: pubsub_broadcaster_ext.cpp:128-280] → membership/auth gates → `BroadcastMessage` parse → `DecodeBroadcast` (:241) → blacklist gate (:261) → **`AddMultiCIDInfo`** (:623) → per-CID `HasBlock` (:630):
- **Disposed-marker hit ⇒ `HasBlock=true` ⇒ "already have block" ⇒ `new_content=false` ⇒ message never enqueued** — zero merge, zero S3 traffic (the Phase-11 storm test proved 25 deliveries → zero S3 Gets) [VERIFIED: 11-03-SUMMARY coverage D2; graphsync_dagsyncer.cpp:691-700]
- If the marker were TRIMMED (bounded memory, D-10 Phase 11): `new_content=true` ⇒ `messageQueue_` + notify (:269-275) ⇒ CRDT `processNextMessage` loop re-checks `HasBlock` (crdt_datastore.cpp:706) ⇒ walks/merges the delta via `MergeDataFromDelta` (:1862) ⇒ **tombstone dominance is the last line** — the pre-delete delta carries `AddElement` at a LOWER height than the CRDT-delete tombstone; tombstone rows (`TombsPrefix(key).ChildString(tomb.id())`) are NEVER purged (GC-02 guard; byte-identical t/k/h proof) ⇒ the value stays absent in `/crdt/k/<key>/v` computation
- **The counter-test therefore proves BOTH lines for SC2:** (a) the dedup line (marker present ⇒ no re-integration at all — assert value absent in BOTH nodes, no re-journal, zero S3 Gets via the counting client) and (b) optionally the trimmed-marker fallback (tombstone dominates re-integration — the strongest form; planner may scope (b) as the marker-trim resurrection leg)

**Forcing GC past retention + grace (the agent-discretion item, resolved):**
- Config route: `RetentionOptions{ retention_age_ms = 1, grace_ms = 1, gc_interval_ms = small }` — **footgun: `grace_ms == 0` NORMALIZES to `kDefaultGraceMs` (60000) under the 0-equals-default discipline** [VERIFIED: ColdStorageManager.hpp:105-125 — "The two cadence knobs follow the 0-equals-default discipline and normalize to kDefaultGcIntervalMs / kDefaultGraceMs at construction"]; tests must set explicit small positive values. Same for `gc_interval_ms == 0` → 600000.
- Driven-pass route (simpler, fully deterministic): call `GcPassOnce()` directly from the test thread (the documented seam) — pass 1 marks; **defer-to-next-tick requires a LATER tick** (`gc_tick_counter_ <= mark.mark_tick` retains) and elapsed grace, so pass 2 (after grace ms) deletes [VERIFIED: ProcessDueMarks defer check, :1089-1094]. `SetSpilledAt` can backdate ages without sleeping past retention.
- Recommend: driven passes with explicit tiny grace (1 ms) + `SetSpilledAt` backdating — the 11-02 suite's proven mechanics.

**Topology (D-13 "in-process GlobalDB pair (11-03 lane precedent)"):** note the honest history — 11-03 documented-deviated and did NOT rebuild the libp2p two-GlobalDB wire (its legs proved request-entry + responder wrapper over a shared fake) [VERIFIED: 11-03-SUMMARY Deviation 1]. The actual full-fidelity precedent in-tree is `pubsub_graphsync_test.cpp` `MultiGlobalDBTest` (two `GossipPubSub` instances, real GlobalDB pairs, in-process libp2p wire) [VERIFIED: test/src/graphsync/pubsub_graphsync_test.cpp:91-120]. Options for Phase 12: (a) one full-wire two-GlobalDB case with cold storage ON on the receiving node (GC + re-delivery at full fidelity — heaviest, ~libp2p boot cost); (b) drive `OnMessage` directly with a hand-encoded `BroadcastMessage` (deterministic, no libp2p — the realistic-vector caveat is that it skips the delivery lane); (c) `CRDTMirrorBroadcaster` queue injection (crdt-level only — weakest fidelity, NOT the pubsub path D-13 names). Recommend (a) once for SC2's letter + (b) for the race-matrix-adjacent dedup assertions (already proven pattern in the storm test).

## 4. SC3 — Soak Observables, Journal Lifecycle, Teardown, Budgets

**Journal record lifecycle (states + where observable):** `PendingUpload → UploadedAccepted → UploadedDurable` (`UploadState` tri-state; `LocalCommitted → ObjectStoreAccepted → ObjectStoreDurable` durability levels). Observables, all atomic-backed via `GetStatus()` [VERIFIED: ColdStorageManager.hpp:377-381 doc, ColdStorageStack.hpp:67-104]: `pending_upload_count`, `accepted_upload_count`, `durable_upload_count`, `watermark` (`None/Warn/Critical`), `staging_healthy` + raw staging counters, `flush_*` evidence, `gc_*` fields. Per-CID: `GetUploadState` pass-through (MI-02: NotFound↔NoRecord vs `Unreadable`).

**D-06 assertion mechanics (verified surfaces):**
- no-multiply: pending count ≤ distinct published CIDs — assert `GetStatus().pending_upload_count <= unique_cids_published` at sampled points; retries never duplicate records (journal keyed by CID; re-Put of present block writes no new record — re_put_is_idempotent proven in 08)
- watermark/alarm fire at configured thresholds: set tiny `warn_pending`/`critical_pending` in `BackpressureOptions` (defaults 10000/100000 [VERIFIED: globaldb.hpp:100-104]); assert `watermark` transitions Warn→Critical and back (down-crossing "watermark recovered" is also logged — recovery is signal [VERIFIED: UpdateWatermark, ColdStorageManager.cpp:1472-1538]); held-watermark heartbeat every 60 s for the wall-clock soak's "for the soak duration" evidence
- post-recovery drain: after fault clear, poll `pending_upload_count == 0` (or baseline) within a bounded window (discretion: e.g. 30 s poll/2 min bound — the Phase-10 resume-poll shape at cold_storage_durability_test.cpp:850-856)
- GC inhibition during outage: staging-unhealthy ⇒ `gc: tick inhibited` + `gc_inhibited_staging` status [VERIFIED: GcPassOnce step (1)]

**Publishes continue for the soak duration:** the decorator `set()` never blocks on remote I/O (journal-first, SPILL-01) — the Phase-8 outage-window precedent `s3d_down_window_keeps_publishing` is the exact shape [VERIFIED: cold_storage_spill_test.cpp:725]. Arm `S3FaultKind::Unavailable` on Put (op-level) for the outage; the admin fake `Unreachable`/`FlushFails` for the flush-cadence backoff leg (D-08: flush backoff is SEPARATE state — Pitfall 6).

**Teardown-under-load (D-09):** verified join order — `GlobalDB::ShutdownNow`: `StopBackupLoop()` → `StopColdStorageManager()` → `StopColdReadService()` → lifecycle-mutex teardown (`m_datastore.reset()`) → `broadcaster->Stop()` → `crdt_datastore->CancelAndCloseNow()` [VERIFIED: globaldb.cpp:584-629]; inside `ColdStorageManager::Stop()`: drainer flag→notify→`kShutdownGraceWindow` (5000 ms) bounded wait→join → ONE final flush (`kFinalFlushBudgetMs` 2000 ms, `final_flush_done_` exactly-once) → GC flag→notify→join [VERIFIED: ColdStorageManager.cpp:260-353]. D-09's "backup-loop → drainer → GC thread → cold-serve executor" ordering is exactly this. The Phase-10 test `shutdown_under_load_slow_flush_bounded` [VERIFIED: cold_storage_durability_test.cpp:809-856] is the extend-me shape: publisher thread + slow flush armed mid-load + bounded Stop() assertion (grace + final budget + margin) + fresh-manager resume proof. Phase 12 adds the GC actor + in-flight evict marks to the load mix.

**kill-9 mid-soak + restart (D-09):** precedent `crash_restart_reconciles` [VERIFIED: cold_storage_spill_test.cpp:656-723 — blocks journaled with NO manager ever started, then a fresh manager's first poll reconciles]. True kill-9 = separate process: the two-fresh-process shape exists in `s3d_gc_e2e` (SpillRun/EvictRun) and `local_block_store_crash_test`; for the wall-clock soak, a runbook-driven process kill + relaunch asserting: journal reconciliation (first-poll re-drain), pending → 0, no duplication (createOnly convergence), no partial states. In-process approximation (destroy manager mid-flight, reopen store dir) is the CI-safe surrogate for the iteration lane.

**Peer cold-fetch deadline budget (SC3 last clause):** `kRewarmBudget = 4000 ms` (comment: "must complete before the peer's ~5 s first" — the peer-side retry budget), `kMaxRewarmQueueDepth = 64` (overflow drops + counts; next request re-enqueues), `kRewarmShutdownGraceWindow = 5000 ms` [VERIFIED: ColdReadService.hpp:106-124]. The budget check is per-item in `RewarmWorkerLoop` (:422 — items whose enqueue age exceeds budget are dropped). Inject latency on the S3 data path (new decorator/hook) and assert: fetches complete ≤ 4 s or are dropped-with-count (never hang, never exceed), responder serves don't-have meanwhile, and after latency clears the retry ladder serves CID-verified. `kTotalFetchTimeout = 20 s` bounds the requester-side peer ladder [VERIFIED: graphsync_dagsyncer.cpp:28].

**Soak shapes (D-07):** iteration soak = N publish cycles under sustained fault, deterministic count, Tier-1 lane (no fixed sleeps — poll with deadlines). Wall-clock soak = dev-gated binary (tens of minutes), committed evidence (D-05 note: TEST-03's committed-artifact standard applies HERE per D-07 — capture format discretion; the gc-e2e evidence-trio pattern — run capture + corroborating capture + runbook — is the precedent).

## 5. SC4 — Fresh-Clone Proof Surface, Verified

### 5.1 The thirdparty release-cut machinery (what the user dispatches at D-03)

- `thirdparty/.github/workflows/build-targets.yml` — the dispatch UI ("Multiplatform build and upload"): `release-tag` input + per-target toggles (`BUILD_WINDOWS_RELEASE` etc.); generates the matrix JSON for the reusable engine [VERIFIED: build-targets.yml:8-68,108-115]
- `thirdparty/.github/workflows/build.yml` — the engine: `inputs.upload`, `release-tag`, `sgns_enable_release_symbols`; `IS_TAG_RELEASE`/`RELEASE_TAG` derivation (per-target `branch` tags when no explicit release-tag) [VERIFIED: build.yml:3-34,149-152]; build → **sgns-blockstore Tier-1 tests run in the thirdparty build itself** on Win/Linux/OSX legs (`ctest --test-dir sgns-blockstore/src/sgns-blockstore-build -C <type> -L Tier1 --no-tests=error` — build.yml:375-377) → tarball (`tar --no-wildcards-match-slash --exclude='./*/src' --exclude='./*/tmp' --transform=...` — :384-387) → tag via REST API (git-push of workflow-touching commits is rejected without `workflows` scope — :390-435) → staged upload with 5 retries (uploads.github.com intermittently fails 1-2 GiB assets with HTTP 500 — :437-480) with near-atomic asset swap
- Tarball-content constraint (inline-documented): build trees MUST live under `*/src` or they leak into the tarball and "blow the 2 GiB asset limit (HTTP 422)" — the shaderc entry's short-`BINARY_DIR` rationale [VERIFIED: CommonTargets.cmake:432-441]. sgns-blockstore uses the default `<prefix>/src/sgns-blockstore-build` — compliant (and that is exactly where build.yml's ctest looks)
- sgns-blockstore superbuild entry + deps (minio-cpp, pugixml, json) verified present in the release: `ExternalProject_Add(sgns-blockstore ...)` with the TESTING-last-arg discipline and the FindZLIB shim [VERIFIED: CommonTargets.cmake:862-907]

### 5.2 The SuperGenius consumption side (where the ON lane plugs in)

- `cmake.yml` ("Release Build CI"): matrix legs carry per-leg `cmake_args` (e.g. Linux-x86_64 Release: `-DSGNS_PRINT_LOGS=ON`) — **the ON leg is a new matrix include (or separate job) adding `-DSGNS_COLD_STORAGE=ON`** [VERIFIED: cmake.yml:167-208, configure at :523]; `RUN_TESTS` gates `Linux || OSX || (Windows && Release)` (:157) — all three desktop legs the proof needs run tests on at least one build-type each; Tier-1 ctest step: `ctest . -j $CTEST_JOBS -C <type> --output-on-failure -L Tier1 --no-tests=error` (:617, :701); thirdparty arrives as the RELEASE tarball into `github.workspace/thirdparty` (:318-331)
- `build-release-tags.yml` ("SuperGenius Tag Build"): `thirdparty_tag` input (:10), `run_tests` input (:76-77) with the same platform gating (:192), per-leg `exit 78` skip gates (:255-259), "Download thirdparty release" resolves `THIRDPARTY_TAG` (main/develop → `TARGET_ID-branch-type`, else the tag verbatim) and sets `THIRDPARTY_BUILD_DIR` with the Windows `pwd -W` GITHUB_ENV discipline (:409-451), container images + runner resolution mirroring develop CI. **D-02b = dispatch with thirdparty_tag=<the cut tag>, run_tests=true, and the ON configure added to the workflow**
- `SGNS_COLD_STORAGE` option + find chain (both consumers): SuperGenius at `SuperGenius/build/CommonBuildParameters.cmake:415-446` (option :415; mobile FORCE-OFF :417; the ordered hint chain pugixml→nlohmann_json→httplib→miniocpp→sgns-blockstore :436-444, deliberately OUTSIDE the libssh2 PREFER_CONFIG window); GeniusSDK at `GeniusSDK/cmake/CommonBuildParameters.cmake:325-366` (same shape). NOTE the path: SuperGenius's file is `build/CommonBuildParameters.cmake`, NOT `cmake/` [VERIFIED: git grep — 3 files carry the option]

### 5.3 THE LANDMINE: the test fakes are not installed — CI has never compiled these tests

- The SuperGenius cold-storage Tier-1 targets reach the library's test fakes via a RELATIVE SOURCE path: `target_include_directories(... "${CMAKE_CURRENT_LIST_DIR}/../../../../thirdparty/sgns-blockstore/src")` [VERIFIED: test/src/crdt/CMakeLists.txt:96-98 and the same pattern for spill/fallback/durability/gc suites]
- The fakes (`InMemoryS3Client.hpp`, `InMemoryS3AdminClient.hpp`) live in `thirdparty/sgns-blockstore/src/` — **the library installs ONLY `include/` + lib + export** [VERIFIED: sgns-blockstore/CMakeLists.txt:65-99 — `install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/include/" ...)`]
- CI's `thirdparty/` is the extracted RELEASE tarball (install trees: `sgns-blockstore/{include,lib}`) — **`sgns-blockstore/src/` does not exist there** ⇒ every `if(SGNS_COLD_STORAGE)` test target EXCEPT `cold_storage_config_gate_test` (registered unconditionally, links only `crdt_globaldb`) FAILS TO CONFIGURE/COMPILE in CI today. Consistent with history: no CI leg has ever set the option (TEST-01 traceability: "Windows local lane green; CI yaml committed, runtime on push")
- **Options (planner rules; recommendation first):**
  - **(A) Sparse source overlay in the ON leg (recommended):** after tarball extract, checkout the thirdparty repo at the SAME tag, sparse-limited to `sgns-blockstore/src`, overlaid into `github.workspace/thirdparty/sgns-blockstore/` — disjoint subpaths (`src/` vs `include/`,`lib/`), no collision; zero library change, no re-cut. Cost: workflow steps in both CI surfaces + the checkout must use the tag (or the SuperGenius-tested thirdparty SHA) so fakes match the built library
  - **(B) Overridable include dir in SuperGenius test CMake:** a cache var (e.g. `SGNS_BLOCKSTORE_TEST_SRC_DIR`, default = today's relative path) + the ON leg points it wherever it staged the sparse checkout — same CI-side source fetch as (A), slightly cleaner CMake; pure SuperGenius-repo change
  - **(C) Install the fakes from the library:** additive but grows the INSTALLED surface (header-hygiene/api-hygiene gates apply; the "test-surface-only src/ privilege" note in test/CMakeLists.txt:29 is a deliberate posture) — a D-14 library change forcing the tag re-cut before the proof. Only if (A)/(B) prove unworkable
- Related wiring facts for the ON leg: `THIRDPARTY_BUILD_DIR` must point at the extracted install tree (already does); ctest parallelism picks exist (:584-595); self-hosted runner resolution job picks runners (fail-open to GitHub-hosted) (:86-120)

### 5.4 Tier-label audit (SC4, mechanical)

The library's proven shape: `tier1_audit_check.cmake` — (1) fixed-sleep pattern scan over test sources with an allowlist, (2) registration-vs-label count guard ("registers more tests than it labels ... a new unlabeled test trips the audit before CI can run it") [VERIFIED: tier1_audit_check.cmake:3-11,35-43]. SuperGenius has NO equivalent today. The Phase-12 audit (discretion: script vs checklist — recommend script): count `addtest(` vs `set_tests_properties(... LABELS "Tier1")` under `test/src/crdt/CMakeLists.txt`'s cold-storage block(s), assert equality, and assert every new suite is inside `if(SGNS_COLD_STORAGE)` iff it links `sgns-blockstore::sgns-blockstore` (the config-gate exemption rule already documented inline). Register the audit itself as a Tier-1 ctest (belt-and-suspenders, the library precedent).

### 5.5 "Pushed commits only" (D-04) + evidence (D-05)

CI builds pushed commits by construction; the runbook/checklist validates SHAs-on-remote before the dispatch (a `git ls-remote` check per repo — SuperGenius, thirdparty; GeniusSDK is not on the proof's critical path since SC4 names SuperGenius's ctest). Everything through Phase 11 is already pushed (user-confirmed in CONTEXT specifics). The checklist doc (D-05, location discretion — recommend workstream planning dir or SuperGenius docs; NOT committed raw logs) records: tag names, SHAs, per-platform configure line, Tier-1 pass counts, the ON-option evidence, and the audit result.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Timing injection | ad-hoc sleeps in tests to "hit" interleavings | barrier hooks (deterministic legs) + fake/decorator latency scripting (jitter legs) | sleeps are flake, banned by the library audit pattern, and cannot hit critical sections deterministically |
| Race observation | log-scraping to detect interleavings | the existing seams (`SetOnFlush`, `SetGcMidPassHookForTesting`, new D-16 seams) + counting fakes + state asserts | barriers observe the EXACT crossing; logs are lossy and racy to scan |
| Blacklist-write proof | parsing logger output for blacklist lines | state-based assert (`IsOnBlackList` after scenarios with no peers) + optional corroborating log-scan | state is ground truth; `SetBlacklistBackoffTimeoutForTest` precedent for blacklist inspection |
| Soak assertions | new product metrics/telemetry | `GetStatus()` atomics + watermark transitions + staging flags | everything D-06 asserts is already exported (§4); no product change needed |
| Two-node topology | a new network harness | `pubsub_graphsync_test.cpp` harness shape (once) + `OnMessage`-level driving (matrix) | the full-wire harness exists; wrapper-level driving is deterministic and proven (11-03) |
| Fresh-clone local build | standing up a local three-platform build | the CI ON lane (D-01 locked) + user-dispatched tag cut | ~100+ GB thirdparty build on W: drive; CI is the locked proof surface |
| Tier-label policing | manual checklist review | CMake-script static audit (library precedent) | mechanical, fail-closed, runs in the lane |

**Key insight:** every instrument this phase needs either exists (seams, fakes, status atomics, harnesses, CI plumbing) or is a small additive extension at a named boundary (§1.6, §5.3). The novel work is composition under sustained fault — not new mechanisms.

## Runtime State Inventory

> Phase 12 is an evidence phase — it creates no new persisted schema and renames nothing. Inventory of runtime state the phase must RESPECT:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | Test fixture dirs under `test-data/` + build-tree test binaries' local dirs (spill/crash/durability suites create per-run RocksDB dirs); zero production-schema changes this phase | None beyond existing fixture hygiene (removeAllWithRetry pattern) |
| Live service config | `GeniusWallet/assets/crdt_config.json` — untouched (no new knobs this phase; soak uses test-local configs) | None |
| OS-registered state | None — threads only, joined at shutdown (verified ordering §4) | None |
| Secrets/env vars | `SGNS_BLOCKSTORE_S3_*`, `_ADMIN_PASSWORD` — unchanged; never in soak logs/evidence | Redaction grep over any committed soak evidence (the gc-e2e precedent) |
| Build artifacts | CI: extracted thirdparty release trees + (new) sparse fake-source overlay; local: existing build trees | The ON leg's overlay is new CI state — document in the workflow step (§5.3) |
| Git refs | The thirdparty release TAG (user-created at D-03) + its SHA | Runbook validates tag/SHA on remote before dispatch (D-04) |

## Common Pitfalls

### Pitfall 1: The ON CI leg cannot compile the cold-storage tests (fakes not in the tarball)
**What goes wrong:** the first ON-lane run fails at configure/compile — `../../../../thirdparty/sgns-blockstore/src` does not exist in the CI workspace (§5.3).
**Why:** the fakes are source-tree-only by design; no CI leg ever set the option, so it never surfaced.
**Avoid:** wire the sparse-source overlay (option A/B) as part of Wave 3's FIRST task, before the tag cut; verify locally by configuring the tests against an install-tree-only thirdparty layout.
**Warning signs:** configure errors on `InMemoryS3Client.hpp` in the ON run.

### Pitfall 2: `grace_ms = 0` / `gc_interval_ms = 0` in test configs silently means 60 s / 10 min
**What goes wrong:** the resurrection/race tests stall or time out waiting for grace expiry that never comes quickly.
**Why:** the 0-equals-default normalization [VERIFIED: ColdStorageManager.hpp ctor docs + RetentionOptions].
**Avoid:** explicit small positive values (e.g. 1 ms) in test `RetentionOptions`; driven passes with `SetSpilledAt` backdating for age.
**Warning signs:** marks never processed; "defer-to-next-tick" retains forever in test output.

### Pitfall 3: Blocking the pubsub delivery lane
**What goes wrong:** a test callback (or a barrier hook invoked on the lane) blocks — all subsequent gossip deliveries stall; in production the same class is the freeze hazard.
**Why:** the delivery lane is a single-threaded strand [VERIFIED: gossip_pubsub.cpp:506-522, 764-812].
**Avoid:** barrier hooks on the pubsub path must be non-blocking (flag+cv, not wait-for-test-thread); `HasLocalCold`/`HasDisposed` are point lookups precisely to stay freeze-proof — keep any new hook the same class.
**Warning signs:** delivery-depth warnings ("Subscriber-delivery lane depth reached ...") in test logs.

### Pitfall 4: Fixed sleeps in new tests (the flake + audit-ban class)
**What goes wrong:** CI flake; the library-side audit discipline (and repo hazard history) treats sleep-based sync as a defect.
**Avoid:** `PollUntil`/deadline polling for liveness; barriers for ordering. Never `sleep_for` to "wait for" an actor.
**Warning signs:** any `sleep_for` in a new test source.

### Pitfall 5: Misreading the delete-time re-check's comparison basis
**What goes wrong:** race tests mutate heads between the WRONG pair of points and pass vacuously (or fail spuriously).
**Why:** `ProcessDueMarks` compares CURRENT heads vs **the mark's own pass-start snapshot** (not the current tick's) [VERIFIED: ColdStorageManager.cpp:1111-1119 + EvictingMark doc].
**Avoid:** the cancel-scenario barrier must fire between the per-mark heads re-check and HALF1 (the new seam), with heads mutated to differ from the MARK's snapshot.
**Warning signs:** "delete-time cancel" logs not appearing when the scenario intends them.

### Pitfall 6: HALF2 is not under `cold_store_mutex_` — and that's correct
**What goes wrong:** a "fix" that widens the lock to make a race "impossible" would couple hot-store cleanup to remote I/O state and violate the split-phase discipline.
**Why:** HALF2 (hot batch + LRU invalidation) deliberately runs after the library half, unlocked vs `cold_store_mutex_` [VERIFIED: ProcessDueMarks :1121-1139].
**Avoid:** drive the window with the HALF1↔HALF2 seam; assert end states, don't widen locks.
**Warning signs:** any plan step adding `cold_store_mutex_` scope around hot cleanup.

### Pitfall 7: Latency injection via the admin fake's sleep model on the DATA path
**What goes wrong:** copying `SetSlowFlushDelayMs`'s in-call sleep into the shared S3 fake serializes ALL ops behind the sleep (the fake's own mutex) — latency becomes an outage.
**Why:** `InMemoryS3Client` holds `mutex_` around op dispatch; a sleeping op blocks the counting probes too.
**Avoid:** per-key/per-op latency with fine granularity, hooks invoked OUTSIDE the fake's lock (or document lock discipline on the hook), or the test-local decorator (§ Alternatives) which needs no lock changes.
**Warning signs:** soak throughput collapsing to one-op-per-latency-unit.

### Pitfall 8: Assuming the 11-03 "two-GlobalDB lane" already exists as a full-wire harness
**What goes wrong:** planning cites a precedent that was a documented deviation — the libp2p two-GlobalDB wire was NOT rebuilt in 11-03 (request-entry + responder-wrapper were proven instead).
**Avoid:** budget the one full-wire case explicitly (or scope to OnMessage-level driving and record the fidelity caveat); the real harness shape is `pubsub_graphsync_test.cpp`.
**Warning signs:** plan tasks referencing "the 11-03 two-GlobalDB lane" without a build step.

### Pitfall 9: s3d's blocking flush semantics bleeding into soak assumptions
**What goes wrong:** expecting flush evidence during outage — the LIVE s3d `/objects/flush` blocks until the client budget cancels (11-04's 900 s finding); hermetically, `SetSlowFlushDelayMs`/`FlushFails` model it, but the soak must not assert flush progression during the outage — only backoff + watermark + publish continuity.
**Why:** Phase-11 live evidence; D-06's assertions are deliberately outage-phase (no-multiply + alarm) then recovery-phase (drain).
**Warning signs:** assertions on `durable_upload_count` increasing during the outage window.

### Pitfall 10: Windows runner/environment specifics on the tag build
**What goes wrong:** path-length (shaderc's 260-char MSBuild precedent), `pwd -W` vs MSYS path in `THIRDPARTY_BUILD_DIR`, bash-vs-WSL shell selection — all previously fixed landmines in the tag workflow.
**Avoid:** reuse the existing steps verbatim; only ADD the ON configure + (if needed) the fake-source overlay step.
**Warning signs:** any new GITHUB_ENV write not following the existing Windows branch pattern.

## Code Examples

### The barrier-hook precedent to mirror (admin fake)
```cpp
// Source: thirdparty/sgns-blockstore/src/InMemoryS3AdminClient.hpp:88-93 [VERIFIED]
/**
 * @brief Optional hook invoked after every (non-faulted-at-entry)
 *        Flush completes - the barrier point tests use to observe
 *        an in-flight flush from the scripting thread.
 * @note CONFORMANCE-TEST SEAM: production code MUST NOT call this.
 */
void SetOnFlush( std::function<void()> hook );
```

### The GC test-seam precedent to mirror (manager)
```cpp
// Source: SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp:262-272 [VERIFIED]
/**
 * @brief      TEST-ONLY mid-pass hook (the library's
 *             SetCrashPointForTesting precedent): invoked between
 *             the pass-start heads snapshot/walk and the
 *             heads-equality finalization ...
 *             PRODUCTION CODE MUST NEVER CALL SetGcMidPassHookForTesting.
 */
void SetGcMidPassHookForTesting( std::function<void()> hook );
```
New D-16 seams (pre-delete-batch, pre-HALF1 post-recheck, between-halves) copy this exact shape: `std::function` member + swap mutex + null-in-production + Doxygen naming the crossing.

### The driven-pass + defer-to-next-tick eviction rhythm (tests)
```cpp
// Two driven passes evict: pass 1 marks (grace not elapsed, mark_tick == current);
// after grace_ms elapses, pass 2 processes due marks (gc_tick_counter_ advanced).
// Source: ColdStorageManager.cpp:1089-1094 [VERIFIED] — the defer predicate:
//   if ( gc_tick_counter_ <= mark.mark_tick
//        || now_ms < mark.marked_at_unix_ms + retention_.grace_ms )
//       { retained.push_back( std::move( mark ) ); continue; }
```

### The bounded-Stop assertion shape (extend for D-09)
```cpp
// Source: SuperGenius/test/src/crdt/cold_storage_durability_test.cpp:838-847 [VERIFIED]
const int64_t bound_ms = ColdStorageManager::kShutdownGraceWindow.count()
                       + ColdStorageManager::kFinalFlushBudgetMs.count() + 3000 /* margin */;
EXPECT_LT( stop_elapsed_ms, bound_ms ) << "Stop() must stay bounded by grace + final budget";
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Sleep-based test synchronization | PollUntil/deadline polling (SuperGenius) + barrier hooks; fixed sleeps audit-banned (library) | v1.0 Phase 5 / v1.1 Phases 8-11 | Phase 12's deterministic legs must be barrier-driven, not timed |
| Subscriber delivery on the gossip I/O thread (whole-node freeze hazard) | Dedicated single-threaded delivery lane with depth warning | ipfs-pubsub (in-tree) | The hazard moved but the discipline stands: pubsub-path callbacks stay non-blocking |
| Accepted-is-durable assumption | Flush-gated, evidence-backed Durable (Phase 10); GC gate compile-time `UploadedDurable` (Phase 11) | v1.1 | The soak's recovery-phase assertions mark Durable only on real evidence |
| Eviction as a single cross-store transaction | Two idempotent single-store halves with an under-eviction-safe crash window (Phase 11 D-16 ruling) | v1.1 Phase 11 | The race matrix's HALF1↔HALF2 window is DESIGNED, not accidental — drive it, don't "fix" it |

**Deprecated/outdated:**
- 11-RESEARCH's "CRDT DAG blocks are CIDv1/DAG_CBOR/blake2b-256" — empirically corrected by the 11-01 tracer: delta nodes are CIDv0/DAG_PB/sha256 (`EquivalentCidClaim` accepts both encodings) [VERIFIED: 11-01-SUMMARY key-decisions]. Phase-12 fixtures must use real delta blocks.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | A sparse checkout of `thirdparty@<tag>` limited to `sgns-blockstore/src` can overlay the extracted tarball dir without conflict (disjoint subpaths: `src/` vs `include/`,`lib/`) | §5.3 (A) | Low: paths verified disjoint; if tar gains a `src` entry the overlay order (checkout first, tar extract second) still wins — verify in the leg's first run |
| A2 | A test-local `S3Client` decorator can wrap `InMemoryS3Client` for latency/on-op hooks without library changes (the `S3Client` interface is the only consumed surface at `S3BlockStore` construction) | §1.6/§2 | Low: `S3BlockStore` takes the `S3Client` pointer (BACK-07 note); if some path down-casts to the concrete fake, fall back to additive fake hooks (D-14) |
| A3 | CI runners' disk/time budgets tolerate the ON configure + cold-storage Tier-1 suites on all three platforms (the suites are hermetic, seconds-scale locally) | §5 | Low-Medium: cold suites run in seconds locally; ON configure adds the sgns-blockstore link chain — first ON run is the checkpoint (D-03 ordering absorbs it) |
| A4 | The tag-build `run_tests=true` path executes the cold-storage tests once the ON configure is added (RUN_TESTS gating already covers Linux/OSX/Windows-Release) | §5.2 | Low: gating verified; the only new dependency is A1's source availability |
| A5 | Two driven `GcPassOnce` calls with 1 ms grace + backdated `SetSpilledAt` ages deterministically evict in tests (the 11-02 suite's proven mechanics transfer) | §3 | Low: same code paths already exercised by 20 green GC cases |

**No other claims are assumed — every load-bearing factual claim above carries a `[VERIFIED: file:line]` tag from this session.**

## Open Questions

1. **Fake-source acquisition in the ON CI lane (the §5.3 ruling)**
   - What we know: the fakes are source-only; the tarball is install-only; the include path is a hard-coded relative source path [VERIFIED]
   - What's unclear: whether the team prefers the workflow-side overlay (A), the CMake-variable override (B), or installing the fakes (C — forces a tag re-cut)
   - Recommendation: (B) with (A)'s checkout step — smallest blast radius, pure SuperGenius-repo change; planner rules and the D-03 checkpoint sequence accounts for it
2. **Full-wire two-GlobalDB resurrection case: in Wave 1 or trimmed?**
   - What we know: D-13 names the pubsub path; `OnMessage`-level driving proves the dedup/tombstone lines deterministically; the full libp2p wire adds fidelity at harness cost (Pitfall 8)
   - Recommendation: one full-wire case in Wave 1 (SC2's letter deserves the wire once); OnMessage-level for everything else; the verifier's 11-03 precedent accepted wrapper-level for GC-03 — flag the same conscious choice here
3. **Wall-clock soak evidence artifact format + duration (D-07 discretion)**
   - What we know: tens of minutes, never CI, committed evidence; the gc-e2e trio (run capture + corroboration + runbook) is the precedent
   - Recommendation: `SuperGenius/test/...` or workstream evidence dir + trio format; duration 20-40 min (long enough for held-watermark heartbeats at 60 s cadence to appear ≥ once under load)
4. **Jitter-leg iteration count + seed policy (D-10 discretion)**
   - Recommendation: N=200-500 iterations per pairwise crossing in the Tier-1 lane (bounded by suite budget), fixed default seed overridable via env (repro on failure), per-iteration end-state invariant checks (the D-12 audit walk on a sampled subset + final full audit)

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Windows dev build tree (`build/Windows/<Config>`) | local Tier-1 iteration during development | ✓ | existing (Phases 7-11 ran on it) | — |
| Local thirdparty superbuild install tree | local SGNS_COLD_STORAGE=ON configure | ✓ | Phase-11-current (sgns-blockstore + deps) | — |
| GitHub Actions runners (self-hosted windows/linux_x64/linux_arm/mac + fallbacks) | SC4 ON lane + tag build | ✓ | resolve-runners job picks online runners [VERIFIED: cmake.yml:85-120] | GitHub-hosted fallback (already wired) |
| thirdparty release tag with sgns-blockstore | SC4 tag-consumption leg | ✗ (the D-03 cut happens this phase) | — | none — the D-03 checkpoint gates Wave 3's final evidence on it |
| Live s3d / MinIO | NOT required (SC1-SC3 hermetic; wall-clock soak hermetic per D-06/D-07) | n/a | — | — |

**Missing dependencies with no fallback:** the thirdparty release tag (by design — D-03's user checkpoint creates it).
**Missing dependencies with fallback:** none else.

## Security Domain

### Applicable ASVS Categories (L1, block-on high)

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | no new auth surface (CI dispatch auth is GitHub's; existing GNUS_TOKEN_1 pattern unchanged) |
| V3 Session Management | no | none |
| V4 Access Control | no | D-16 seams are inert-by-default callbacks, never reachable in production flows (the `SetGcMidPassHookForTesting` contract verbatim: "PRODUCTION CODE MUST NEVER CALL ...") |
| V5 Input Validation | yes (config unchanged) | Phase-7 strict parser inherited verbatim — no new config keys this phase; soak/race configs are test-local |
| V6 Cryptography | no | no new crypto; CID verification rides the shipped verify paths (race tests MUST NOT weaken `EquivalentCidClaim` checks — zero-`Corrupt`-from-race is the assertion) |
| V14 Config (adjacent) | yes | CI workflow edits follow least-change; no new secrets; GITHUB_ENV writes follow the existing quoting/path discipline |

### Known Threat Patterns for this phase's surface

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Test seams left armed in production builds | Tampering/EoP | D-16 contract: null-default callbacks, no production caller, documented per seam; release builds never invoke them (assert via the existing "PRODUCTION CODE MUST NEVER CALL" doc + review grep) |
| Secret leakage into committed soak evidence | Information Disclosure | redaction grep over evidence artifacts (the gc-e2e credential-value-shape=0 precedent); env NAMES only in runbooks |
| CI workflow injection via dispatch inputs | Elevation | `thirdparty_tag`/`run_tests` flow only into existing gh CLI/env steps — no `run: ${{ input }}` interpolation of attacker-controlled strings; keep new steps script-constant |
| Denial of service via unbounded soak in CI | DoS (CI budget) | iteration soak is CI-safe by construction (D-07); wall-clock soak is dev-gated and NEVER registered in the Tier-1 lane |

## Sources

### Primary (HIGH confidence — all read this session at file:line)
- `SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp/.cpp` — full GC/drainer/flush topology, seams, Stop ordering, watermarks, RetentionOptions normalization
- `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` — HasBlock 4 terms, getNode cold-before-peers, ColdServeDagService, blacklist sites, kTotalFetchTimeout, test seam
- `SuperGenius/src/crdt/globaldb/pubsub_broadcaster_ext.cpp` — OnMessage gates → DecodeBroadcast → AddMultiCIDInfo → queue
- `SuperGenius/src/crdt/impl/crdt_datastore.cpp:705-712,1860-1882` — merge-loop HasBlock sites
- `thirdparty/ipfs-pubsub/src/ipfs_pubsub/gossip_pubsub.cpp:506-522,760-830` — delivery lane + teardown
- `thirdparty/sgns-blockstore`: FaultController.hpp, S3Client.hpp, S3AdminClient.hpp, LocalBlockStore.hpp, InMemoryS3Client/AdminClient (.hpp/.cpp), tier1_audit_check.cmake, CMakeLists.txt (install rules), testing-tiers.md
- `SuperGenius/src/crdt/globaldb/ColdReadService.hpp/.cpp` — re-warm constants + loop
- `SuperGenius/src/crdt/globaldb/globaldb.cpp:584-629` — ShutdownNow ordering; `globaldb.hpp:100-107` — backpressure defaults
- `SuperGenius/test/src/crdt/` — CMakeLists registration discipline; cold_storage_durability_test.cpp (shutdown-under-load, acceptance-race); cold_storage_spill_test.cpp (outage window, crash-restart, grace joins)
- `SuperGenius/test/src/graphsync/pubsub_graphsync_test.cpp` — two-GlobalDB harness
- CI: `SuperGenius/.github/workflows/cmake.yml`, `build-release-tags.yml`; `thirdparty/.github/workflows/build.yml`, `build-targets.yml`; `thirdparty/build/CommonTargets.cmake` (sgns-blockstore/minio-cpp/pugixml entries, shaderc constraint); `SuperGenius/build/CommonBuildParameters.cmake:415-446`; `GeniusSDK/cmake/CommonBuildParameters.cmake:325-366`
- Planning: 12-CONTEXT.md (D-01..D-16), REQUIREMENTS.md, ROADMAP.md Phase 12, STATE.md; 09/10/11-CONTEXT.md; 11-RESEARCH.md; 11-01..11-04-SUMMARY.md; 11-VERIFICATION.md; research SUMMARY/PITFALLS 2026-10-22

### Secondary (MEDIUM)
- None — no external documentation was required (all in-repo)

### Tertiary (LOW)
- None

## Metadata

**Confidence breakdown:**
- Race topology / seams: HIGH — every mutex/seam/step verified at file:line this session
- Fault-kit gap analysis: HIGH — enum + hook surfaces read directly
- Soak observables/precedents: HIGH — tests + constants + ordering verified
- Fresh-clone wiring: HIGH with ONE open planner choice (§5.3) — the gap is verified; the remedy is a recommendation
- Landmines: HIGH — each traced to in-repo evidence or a committed SUMMARY/VERIFICATION finding

**Research date:** 2026-10-27
**Valid until:** 2026-11-27 (stable in-repo surfaces; CI workflows are the fastest-moving — re-verify workflow line numbers if dispatch ergonomics changed)
