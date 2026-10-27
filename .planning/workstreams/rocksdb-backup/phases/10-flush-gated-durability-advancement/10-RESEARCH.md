---
phase: 10
phase_name: Flush-Gated Durability Advancement
workstream: rocksdb-backup
milestone: v1.1
requirement: DUR-01
researched: 2026-10-26
researcher: gsd-phase-researcher
confidence: HIGH
---

# Phase 10: Flush-Gated Durability Advancement - Research

**Researched:** 2026-10-26
**Domain:** s3d admin-API durability advancement on the Phase-8 drainer (sgns-blockstore library + SuperGenius cold-storage stack)
**Confidence:** HIGH (every load-bearing fact verified in-tree this session; the s3d openapi re-fetched live from the pinned tag)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions (D-01..D-13 — bold statements verbatim from `10-CONTEXT.md`; full rationale/reversibility text lives there)

- **D-01:** **Hybrid flush trigger — drain-quiescence + interval floor + max backstop** — the flush fires after the drainer goes quiescent with accepted-unadvanced records, rate-limited by a minimum interval floor (don't hammer s3d), plus a max-interval backstop so a record can never wait longer than a bound for its durability advancement.
- **D-02:** **The flush call is owned by the Phase-8 drainer thread** — flush runs on the drainer after a drain batch; drain→flush→observe→mark is naturally serialized with no new thread lifecycle (single-supplier evidence model preserved).
- **D-03:** **Snapshot-at-flush-initiation advancement semantics** — only records already `ObjectStoreAccepted` when the flush began advance to Durable after `pendingObjects==0` is observed; anything accepted later waits for the next cycle.
- **D-04:** **Best-effort final flush inside the D-11 shutdown grace window** — after the drainer stops, shutdown makes one bounded flush+observe+mark attempt within the existing grace budget; leftovers stay Accepted and resume via the Phase-8 D-12 first-poll path at next startup.
- **D-05:** **The flush/stats admin client lives in sgns-blockstore as an additive facade** — e.g. `Flush()` + `UploadStats()` next to the existing `S3Client` surface; the `InMemoryS3Client` fake gains a fake admin endpoint so every hermetic Tier-1 fault test fakes flush/stats natively.
- **D-06:** **Verify-then-env credential posture** — the researcher first verifies s3d v0.2.1's admin auth scheme. If admin reuses existing S3 credentials: zero new surface. If separate: an env-only var per the Phase-7 D-07 credentials-in-env posture — admin credentials never at rest in config files, never logged. *(Research verdict below: SEPARATE.)*
- **D-07:** **Flush/stats failures mirror the drainer backoff discipline** — exponential backoff, capped, reset on success (Phase-8 D-03 shape); records simply stay Accepted; sustained flush failure raises the existing watermark-alarm logging discipline and flags drainer health in the status getter. Flush failure never blocks writes and never surfaces as NotFound.
- **D-08:** **Extend the Phase-8 D-08 status getter** — add per-state record counts (pending / accepted / durable) plus last-flush evidence (timestamp, result, observed counters). Additive fields per the Phase-8 D-08 "fields can grow" note.
- **D-09:** **Per-CID `GetUploadState` pass-through on `ColdStorageManager`** — a thin wrapper over the library's existing `GetUploadState(cid)`.
- **D-10:** **The eviction-gate durability state is fixed at `UploadedDurable`, compile-time** — no configurable lower bar.
- **D-11:** **Minimal knob set under a nested `blockstore.durability` sub-object** — the flush cadence knobs (e.g. `flush_min_interval_ms`, `flush_max_interval_ms`; exact names agent discretion). Absent knobs = documented built-in defaults; strictness and tri-state semantics inherit Phase 7 unchanged (unknown key inside = loud startup failure).
- **D-12:** **The staging-health predicate lands now** — the status getter carries the raw counters (`pendingObjects`/`bufferUsed`/`bufferLimit`) PLUS a conservative `staging healthy` flag.
- **D-13:** **Stats freshness via on-tick + on-demand** — stats are observed on every cadence tick AND an on-demand refresh entry point exists for the Phase-11 GC to consult before inhibiting. No independent poller thread.

### The Agent's Discretion (researched + recommended below)

Default values (interval floor/backstop/backoff/health thresholds/`bufferLimit==0` handling); exact knob names inside `blockstore.durability`; library facade API shape (class/methods/placement, `UploadStats` struct fields); how the fake admin endpoint models flush semantics; researcher verification items (admin auth scheme, endpoint topology, `UploadStats` schema); `MarkUploadedDurable` batch mechanics (snapshot enumeration + batched RocksDB writes); how last-flush evidence is held; SC3 fault-test design; where staging-healthy evaluation runs; Tier-1 registration mechanics; exact log wording (flush failures distinguishable from drain/peer failures); whether flush-cadence rate-limit state is separate from drain backoff state.

### Deferred Ideas (OUT OF SCOPE)

Retention GC and eviction execution (Phase 11); cross-actor fault races / fresh-clone proof (Phase 12); per-object durability-signal polling (fast-follow milestone-wide); mobile legs (Future); GlobalDB backup engine changes (milestone-wide). Vulkan capability-probe fix stays in the todo backlog (keyword match only).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DUR-01 | Recorded durability advances LocalCommitted → ObjectStoreAccepted → Durable via s3d `/objects/flush` + `pendingObjects==0` evidence (`MarkUploadedDurable`); local bytes become evictable only after the configured durability state is recorded | §1 pins the admin endpoints/auth/schemas; §2 pins the drainer hook points (D-01/D-02); §3 pins the journal state machine + the accepted-enumeration GAP that must be closed; §4–§7 pin observability, config, facade, shutdown, and the test surface |
</phase_requirements>

## Project Constraints (from AGENTS.md / SuperGenius CLAUDE.md)

- C++17, Corelinux-derived style (`Coding Standards.md`): Ullman braces, PascalCase types/methods, `m_`/trailing-underscore members, `k`-prefixed compile-time constants; Doxygen `@brief/@param/@return` on public interfaces.
- `outcome::result` for fallible ops; every library result guarded with `has_value()` BEFORE `.value()`/`.error()` (`policy::terminate` alias — Cid.hpp:37-45, the standing landmine).
- "Gates, not promises" (SuperGenius CLAUDE.md): rules that matter are enforced by ctest/CI, not comments alone.
- "Refactor first, then change behavior"; one owning module per domain; never duplicate logic (grep before writing).
- Build-system pre-PR checklist applies (this phase touches no CMake routing beyond additive sources/tests, but the wrapper-vcxproj header-staleness hazard still applies to installed-header changes — §6).
- Verification runs inside the `build/<Platform>/<Config>` tree (`.planning/codebase/TESTING.md`); `addtest()` + `set_tests_properties(... LABELS "Tier1")` registration; `ctest -L Tier1 --no-tests=error` fail-closed lane.
- Credentials never logged, never at rest in config (Phase-7 D-07 posture; `BlockStatus.hpp` message rule).

## Summary

Phase 10 is composition over two proven substrates: the Phase-8 `ColdStorageManager` drainer loop (SuperGenius, `dev_blockstore`) and the frozen v1.0 journal state machine (`LocalBlockStore`). The one genuinely new external surface is the s3d admin API, and this session re-verified it live from the pinned tag's `openapi.yml`: **the admin API is a separate always-enabled listener (default `127.0.0.1:8001`) authenticated by HTTP Basic with a configured admin password — username ignored — and does NOT reuse the S3 SigV4 credentials.** That resolves D-06 to its "separate" branch: an env-only credential (recommended `SGNS_BLOCKSTORE_S3_ADMIN_PASSWORD`, matching the test-tier precedent name shape) plus a non-secret admin-endpoint config key. Second live-verified fact with plan-binding weight: **`POST /objects/flush` takes NO bucket parameter** — its openapi description says "Uploads all pending objects to Sia immediately… Blocks until done", i.e. the flush is process-global; the ROADMAP/CONTEXT "bucket-scoped" phrasing is an imprecision to correct in docs, not a decision conflict (the cost acknowledgment gets broader, not weaker). Only two responses are documented for flush (200 / 500 "Internal error while pinning, or the request was cancelled"), so the admin facade must classify every non-200 + transport error conservatively as a retryable could-not-obtain failure (never NotFound), per the frozen taxonomy.

The research also found the one real library gap the planner cannot guess around: **there is no way today to enumerate `UploadedAccepted` records.** `GetPendingUploads` returns only `PendingUpload`-state CIDs [VERIFIED: BlockStoreTooling.hpp:70-90 — "Returns the CIDs whose upload-journal state is PendingUpload"], so the D-03 snapshot (the set of records Accepted when flush began) — which must be re-derivable from the journal after crash-restart — needs an additive concrete `LocalBlockStore` method (e.g. `GetUploadsInState(UploadState)`), mirroring the existing `GetPendingUploads` body with a state filter. Relatedly, `TransitionJournal` does NOT check the record's current state [VERIFIED: LocalBlockStore.cpp:660-697 — read-gate is record existence, not source state], so the Accepted-only discipline is caller-side by construction — exactly why the snapshot enumeration must filter on `UploadedAccepted`.

On the SuperGenius side everything slots in additively: the flush tick lands at the end of the drainer's cycle (D-02 — the thread loop and its boundaries are pinned §2 with line anchors); the status getter extends with plain-type fields only (the ungated `ColdStorageStack.hpp` must stay free of library types); the D-09 pass-through is friction-free because `sgns::blockstore::Cid` IS `libp2p::multi::ContentIdentifier` by alias [VERIFIED: Cid.hpp:47-53]; and `blockstore.durability` inherits the exactly-proven `blockstore.backpressure` sub-object parse pattern (0-means-default, loud unknown keys, post-normalization cross-field rule).

**Primary recommendation:** Ship the library slice first (admin client + fake + accepted-state enumeration + optional batched marks), wire the cadence into the drainer's cycle end with snapshot-at-initiation implemented as the journal scan itself, keep every new status field a plain type behind the ungated boundary, and give the admin client explicit client-side timeouts so "blocking" flush can never hang the unconditional shutdown join.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| s3d admin HTTP (flush + stats) | sgns-blockstore library (new admin facade, D-05) | — | The library owns the s3d characterization (`docs/s3d-durability.md`) and its test kit; SuperGenius-side HTTP would duplicate s3d knowledge and force a fake HTTP layer into Tier-1; genius-tube reuses the same seam |
| Flush cadence policy (D-01 trigger, D-03 snapshot, advancement) | SuperGenius `ColdStorageManager` (drainer thread) | — | D-02: drain→flush→observe→mark serialized on the drainer; the library's one-shot drainer deliberately never invokes Durable transitions (UploadDrainer.hpp journal discipline) |
| Journal state advancement (`MarkUploadedDurable`) | `LocalBlockStore` (existing primitive) | manager (orchestrates) | Journal transitions are backend-owned (v1.0 D-06); the manager composes, never touches RocksDB |
| Accepted-set enumeration (D-03 snapshot source) | `LocalBlockStore` (NEW additive method) | — | `GetPendingUploads` is Pending-only; CORE-06 keeps enumeration off `BlockStore`; journal-transition precedent keeps it concrete on LocalBlockStore |
| Per-CID upload-state query (D-09) | `ColdStorageManager` + ungated bridge | `ColdStorageStack.hpp` bridge | globaldb.cpp reaches the manager only through bridges (Phase-8 D-10); the bridge takes the libp2p CID (alias = library Cid) and returns an ungated enum |
| Durability knobs (`blockstore.durability`) | `GlobalDB::ParseColdStorageConfig` (globaldb.cpp) | `LoadCrdtConfig` (GeniusNode.cpp) + wallet asset | Strict tri-state parse is the Phase-7 pattern; env-never-activates inherits |
| Admin credential | env only (`SGNS_BLOCKSTORE_S3_ADMIN_PASSWORD`) | — | D-06 verdict: separate scheme; Phase-7 D-07 credentials-in-env posture |
| Staging-health evaluation (D-12/D-13) | drainer tick (evaluate + cache) | on-demand refresh entry (manager method) | Getter stays atomics-only (D-08 no-scan discipline); no poller thread (D-13) |
| Shutdown final flush (D-04) | `ColdStorageManager::Stop()` after join | GlobalDB::ShutdownNow (existing call site) | One bounded attempt within the existing grace mechanism; stores still live until Stop returns |

## Standard Stack (all in-repo — no new external packages)

### Core

| Component | Version/State | Purpose | Why Standard |
|-----------|---------------|---------|--------------|
| `sgns-blockstore` (submodule, branch `main`, HEAD `ad07cab`) | v1.0 + Phase-6 widening | Journal state machine, S3 client seam, fake, fault kit; gains the D-05 admin facade + accepted enumeration | Frozen v1.0 contract; every surface read this session |
| `ColdStorageManager` + drainer (SuperGenius, branch `dev_blockstore`, HEAD `b17643b5a`) | Phase-8 shipped | The thread the flush cadence attaches to (D-02); status getter (D-08); shutdown slots (D-04) | Phase-8/9 proven lifecycle; anchors §2 |
| s3d admin API (external, pinned **v0.2.1**, commit `312789a`) | characterized v1.0 + re-verified this session | `POST /objects/flush`, `GET /stats/uploads` | Only documented staged→durable primitive (§1) |
| cpp-httplib (superbuild, `find_package(httplib CONFIG REQUIRED)`) | existing hard dependency of the library build [VERIFIED: sgns-blockstore/CMakeLists.txt:40-42] | Plain-HTTP basic-auth transport for the admin client | Already linked for miniocpp; no new dependency |
| nlohmann_json (superbuild, `thirdparty/json`; config at `thirdparty/build/Windows/Debug/json/share/cmake/nlohmann_json/`) | existing superbuild install [VERIFIED this session] | Parsing the `UploadStats` JSON body | Never hand-roll JSON parsing (Don't Hand-Roll); PRIVATE link keeps it off the installed surface |

### Supporting

| Component | Purpose | When to Use |
|-----------|---------|-------------|
| `InMemoryS3Client` + `S3FaultKind` kit | existing S3-side fake; the admin fake follows its placement (src/, non-installed) | every hermetic Tier-1 test |
| `OpenMinioS3Client` factory (installed) | production S3 client construction precedent for the admin factory shape | mirror for `OpenS3dAdminClient` |
| GTest ~1.14 (superbuild) | all test binaries | existing `addtest()` pattern |
| curl.exe (OS-bundled) | dev-session evidence captures (runbook re-run) | live-tier only, never CI |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Standalone `S3AdminClient` interface + factory (recommended) | `Flush()`/`UploadStats()` methods on `S3BlockStore` (D-05's literal example) | Methods-on-store couples the S3-object facade to admin protocol and churns `S3BlockStore::Open`; standalone keeps the store S3-shaped and the admin independently faked. Both satisfy D-05's letter (additive, in-library, beside the `S3Client` surface) |
| Fresh accepted-set scan at flush initiation (recommended) | Manager-maintained in-memory accepted set | In-memory is lost at crash; D-03+SC3 require journal-derivable snapshots; the scan runs only on rate-limited flush cycles |
| Batched `MarkUploadedDurableMany` (recommended, additive) | Loop of single `MarkUploadedDurable` | Loop is correct but one sync WriteBatch (one fsync) per record; after a long outage the backstop recovery would fsync N times. Batch = one fsync + all-or-nothing crash window. Details in Design Notes |
| Env-only admin password, default-on flush with loud absence warn (recommended) | Require credential when `durability` explicitly configured | Stricter require-mode is louder but couples flush activation to operator bookkeeping; default-on matches D-11 "absent knobs = defaults" and D-07's failure discipline already alarms. Planner may flip; flagged in Open Questions (RESOLVED Q1) |

## 1. The s3d Admin Surface (D-06 verdict + endpoint shapes) — PRIMARY QUESTION

### 1.1 D-06 verdict: the admin auth scheme is SEPARATE from the S3 credentials

[VERIFIED: https://raw.githubusercontent.com/SiaFoundation/s3d/v0.2.1/openapi.yml — fetched live this session] The openapi `info.description` states, verbatim:

> "s3d serves an admin API on a separate HTTP address for monitoring the background upload pipeline. It is always enabled and defaults to 127.0.0.1:8001. Requests are authenticated via HTTP Basic authentication using the configured admin password; the username is ignored."

`components.securitySchemes` defines `basicAuth: {type: http, scheme: basic}` and the document-level `security: [{basicAuth: []}]` applies it to every endpoint. Corroborated by the committed live-spike runbook [VERIFIED: thirdparty/sgns-blockstore/docs/evidence/s3d-spike/README.md:75 — `curl.exe -s -X POST -u ":$PW" "$ADMIN/objects/flush"` (empty username, admin password) and :39-40 — `SGNS_BLOCKSTORE_TEST_S3D_ADMIN_PASSWORD` sourced from "s3d config adminPassword"].

**Consequences for D-06's branch:**
- Admin does NOT reuse the S3 SigV4 access/secret keys → the separate-credential branch fires.
- **Recommended env var: `SGNS_BLOCKSTORE_S3_ADMIN_PASSWORD`** — matches the production prefix `SGNS_BLOCKSTORE_S3_*` (Phase-7) and the test-tier precedent `SGNS_BLOCKSTORE_TEST_S3D_ADMIN_PASSWORD`; s3d's own concept is a *password* (the CONTEXT's example name `SGNS_BLOCKSTORE_S3_ADMIN_KEY` says "key" — naming is discretion, but password is the accurate s3d term). Extend `ColdStorageEnvLookup` (globaldb.hpp:121-131) with an `admin_password` member; `DefaultColdStorageEnvLookup` reads exactly this one var (unset/empty = none). Env value-only, never activates anything (Phase-7 D-08 posture inherited).
- **Admin endpoint URL is NOT a secret** → belongs in config, not env. Recommended: optional `admin_endpoint` string key at the `blockstore` level (sibling of `endpoint` — it is connection topology, not cadence); empty = documented s3d default `http://127.0.0.1:8001`. Alternative (inside `durability`) is defensible; planner ruling. See §5.

### 1.2 Topology

Separate HTTP listener, default `127.0.0.1:8001` (S3 API defaults to `:8000`) [VERIFIED: openapi `info.description` + `servers` block; runbook prerequisite 4]. "Always enabled" — no s3d-side toggle. The v1.0 spike ran plain HTTP on loopback; the runbook warns never to TLS-verify s3d's per-start self-signed cert when TLS is used [VERIFIED: runbook prerequisites + 04-RESEARCH Security table]. Ops note already filed in v1.1 PITFALLS: "Unauthenticated s3d admin endpoint reachable → `/objects/flush`, stats tampering → Loopback/firewall s3d admin port; document in ops runbook" [VERIFIED: .planning/research/PITFALLS-rocksdb-backup-2026-10-22.md Security Mistakes table].

### 1.3 `GET /stats/uploads` — exact shape

openapi [VERIFIED: fetched this session] — `operationId: getUploadStats`, tag `metrics`, sole documented response `200` with `#/components/schemas/UploadStats`. Field inventory with verbatim descriptions for the fields this phase consumes:

| Field | openapi description (verbatim) |
|-------|-------------------------------|
| `pendingObjects` | "Objects buffered on disk waiting to be uploaded to Sia." |
| `pendingSize` | "Total size of pending objects in bytes." |
| `uploadedObjects` | "Objects fully uploaded to the Sia network." |
| `uploadedSize` | "Total size of uploaded objects in bytes." |
| `unpinnedObjects` | "Objects uploaded to Sia but not yet pinned in the indexer." |
| `failedUploads` | "Failed upload attempts since the process started." |
| `orphanedObjects` | "Deleted or overwritten objects pending cleanup." |
| `multipartUploads` | "In-progress multipart uploads." |
| `bufferUsed` | "Bytes held on disk in the uploads directory, covering objects awaiting upload, objects uploaded but not yet pinned, and the parts of multipart uploads still in progress. Objects sharing a file are counted once." |
| `bufferLimit` | "Configured disk buffer limit in bytes. Zero means unlimited." |
| `transfer` | `$ref TransferStats` — `ingressActive/ingressBytes/ingressRate/uploadBytes/uploadRate` (ints) + `activeUploads` (array, "Omitted when none are in flight"), each with `label/objects/size/sent/finalizing` |

All counters are `integer`/`int64` and **pipeline-global** (no per-bucket dimension anywhere in the schema) [VERIFIED: openapi; also s3d-durability.md §2 — "Every counter is pipeline-global"]. Raw captured body, verbatim [VERIFIED: docs/evidence/s3d-spike/stats-after-put.txt:1]:

```json
{"pendingObjects":1,"pendingSize":38,"uploadedObjects":0,"uploadedSize":0,"unpinnedObjects":0,"failedUploads":0,"orphanedObjects":0,"multipartUploads":0,"bufferUsed":38,"bufferLimit":10737418240,"transfer":{"ingressActive":0,"ingressBytes":38,"ingressRate":0,"uploadBytes":0,"uploadRate":0}}
```

The after-flush closure observation (`pendingObjects:0, uploadedObjects:1, bufferUsed:0`) is committed at `stats-after-flush.txt` and `e2e-stats-captures.txt` [VERIFIED: both files read this session]. `GET /prometheus` also exists (`s3d_upload_`/`s3d_transfer_` prefixes) [VERIFIED: openapi] — not needed this phase; JSON stats is the seam.

**Observation semantics for SC1:** the flush-gate evidence is `pendingObjects == 0` observed AFTER a flush returns 200. Because flush is process-global and counters are process-global, a foreign writer sharing the s3d can stage objects between flush-return and stats-read, making `pendingObjects` transiently non-zero. The correct posture (already implied by D-03): a non-zero observation simply means "not this cycle" — records stay Accepted, retry next cycle; no incorrect mark can ever happen because marks only follow an actually-observed zero. The single-supplier model (one node's drainer as the only uploader — D-02's evidence-model rationale) is the documented operating assumption; a shared-s3d deployment gets slower advancement, never wrong advancement.

### 1.4 `POST /objects/flush` — exact shape

openapi [VERIFIED: fetched this session] — `operationId: flushObjects`, tag `uploads`, description verbatim:

> "Uploads all pending objects to Sia immediately, regardless of padding, and pins them so their local pending files are removed. Blocks until done."

Responses: `200` "All pending objects were flushed to Sia." / `500` "Internal error while pinning, or the request was cancelled." **The path item declares NO parameters — there is no bucket argument; the flush is process-global.** The runbook invokes it bucket-free [VERIFIED: runbook:75].

⚠️ **Factual correction to carry into the plans/docs:** ROADMAP SC1 and 10-CONTEXT DUR-01/SC1 say "bucket-scoped"; `s3d-durability.md` §3 hedges "bucket/global-scoped". The pinned tag's openapi supports **process-global** (no bucket parameter, "all pending objects"). This contradicts no D-01..D-13 decision — the acknowledged cost simply covers every bucket's pending objects, and the evidence (`pendingObjects==0`) is correspondingly process-wide. Wave 1 should correct the wording in `docs/s3d-durability.md` §3 while adding the admin client.

**No server-side deadline exists** — "Blocks until done" with no timeout parameter. A large backlog (or a slow Sia upload) makes the HTTP call arbitrarily long. Two plan-binding consequences: (a) the admin client MUST set a client-side read timeout (cpp-httplib `Client::set_read_timeout`) so the drainer thread and the D-04 final flush are bounded; (b) a client-side timeout is *safe for correctness* — if s3d completes the flush after our timeout, the next tick's stats observation still sees `pendingObjects==0` and advancement proceeds on valid evidence.

### 1.5 Admin error taxonomy (what the facade must classify)

The openapi documents ONLY 200 and (for flush) 500 — no 502/503/504 shapes, no documented error body schema for the admin API [VERIFIED: openapi paths read this session; the 503-SlowDown/412 taxonomy in `s3d-durability.md` §5-§6 belongs to the S3 API, not the admin API]. Therefore the admin facade's mapping is deliberately conservative:

| Condition | Classification (reuse frozen `BlockStatus` classes) |
|-----------|------------------------------------------------------|
| Transport failure / timeout / non-200 (incl. 500) / non-JSON body / JSON missing required fields | FAILURE, `TemporarilyUnavailable` — "the answer could not be obtained"; retryable per D-07 backoff |
| `pendingObjects` present and `0` | SUCCESS (evidence obtained) |
| Any condition | NEVER `NotFound` (nothing about flush/stats is authoritative absence) |

The garbage/truncation fault shapes the question mentions are *fake-side test semantics* (§8): the fake admin client scripts them; the facade's conservative mapping makes them all exercise the same retryable path. Parsing via nlohmann_json (§6) — strict field presence checks, integer types, unknown extra fields tolerated (schema-forward).

## 2. Drainer Integration Points (D-01/D-02 — file:line anchors)

All in [VERIFIED: SuperGenius/src/crdt/globaldb/ColdStorageManager.{hpp,cpp} — read this session]:

| Anchor | Fact |
|--------|------|
| ColdStorageManager.hpp:107-110 | `kBackoffFactor = 2` (compile-time); `kShutdownGraceWindow{5000}` ms — "NOT a knob - D-05" |
| ColdStorageManager.hpp:115 | `void DrainOnce()` — the per-poll drain body the flush step follows |
| ColdStorageManager.cpp:47-83 | `Start()` spawns the thread; the lambda's comment: "D-12: the FIRST poll IS the crash-restart reconciliation"; loop = `MarkBusy(); DrainOnce(); MarkIdle();` then `wait_cv_.wait_for(current_delay_, stop||drain_requested)` |
| ColdStorageManager.cpp:85-101 | `Stop()`: `stop_flag_` → notify → `idle_cv_.wait_for(kShutdownGraceWindow, idle)` → **unconditional `thread_.join()`** — comment: "only after it returns may the owner close/destroy the stores (Pitfall-5 ordering)" |
| ColdStorageManager.cpp:127-160 | DrainOnce phase (i): under `cold_store_mutex_` — `GetPendingUploads()` + local `Get` per CID into `items`; empty ⇒ `BackoffReset(); UpdateWatermark(0); return;` |
| ColdStorageManager.cpp:162-205 | phase (ii): remote Puts UNLOCKED from the cold-store mutex, each under `remote_store_mutex_` per item (Phase-9 serialization); success slot = achieved OR alreadyPresent ⇒ `succeeded` |
| ColdStorageManager.cpp:207-221 | phase (iii): under `cold_store_mutex_` — `MarkUploadedAccepted(cid)` for succeeded; comment at :213-215: "UploadedDurable is NEVER written here (Phase-10 boundary)" |
| ColdStorageManager.cpp:223-241 | partial-success cycle = failed cycle (OQ3); `UpdateWatermark(items.size() - succeeded.size())` |
| ColdStorageManager.cpp:243-260 | `RecordFailedCycle()` (streak++, `healthy_=false`, double delay to cap) / `BackoffReset()` (reset to `options_.drain_interval_ms`) |
| ColdStorageManager.hpp:170-176 | drainer-thread-only state: `current_delay_`, `failure_streak_`, `last_heartbeat_`; status atomics `pending_count_`/`watermark_`/`healthy_` |
| ColdStorageManager.cpp:105-120 | `GetStatus()` reads three atomics — "no journal scan, no lock" |

**Where the flush tick slots (D-02):** at the END of the loop body, after `DrainOnce()` returns (equivalently after phase iii's watermark update inside `DrainOnce`, or as a sibling call in the lambda). Two structural options — recommend **inside the loop body after `DrainOnce()`** (`DrainOnce(); AdvanceDurabilityOnce();` before `MarkIdle()`), so the quiescence signal is naturally available:

**Quiescence definition (D-01, recommended):** the just-finished drain cycle ended with zero pending records — i.e. `GetPendingUploads()` returned empty, or every item succeeded (`succeeded.size() == items.size()`). Expose it from `DrainOnce` (return value or out-param) rather than re-deriving.

**Recommended trigger predicate (evaluated on the drainer thread, cycle end):**
```
should_flush = (accepted_unadvanced_count > 0)                       // something to advance
            && ( now - last_flush_attempt >= flush_min_interval_ms ) // D-01 floor
            && ( quiescent_this_cycle                                 // D-01 quiescence
              || now - last_advancement >= flush_max_interval_ms )   // D-01 backstop
```
The backstop forces a flush even mid-activity (a record can never wait longer than the bound — D-01's letter). `accepted_unadvanced_count` comes from the snapshot enumeration itself (§3) — enumerate first (cheap journal scan, rate-limited by the floor), flush only if non-empty.

**Rate-limit state (discretion):** recommend a SEPARATE flush-failure streak + delay from the drain backoff state — the semantics differ (drain failure = data not yet remote; flush failure = remote-but-unproven), D-07 wants flush failures distinguishable in health/logs, and coupling them would make drain backoff suppress flush cycles (or vice versa). Same discipline shape: factor 2, compile-time cap (recommend reusing `kBackoffFactor` + a compile-time flush cap, NOT a knob), reset on success. The cadence floor itself (`last_flush_attempt`) is separate from both.

**Why the drainer thread (D-02) is safe here:** the admin client is a NEW connection (not `S3BlockStore`) so `remote_store_mutex_` is not involved; nothing else waits on the drainer; `Stop()`'s join is the only consumer of its lifetime — which is exactly why the admin client needs the §1.4 timeout.

**D-12 first-poll resume interplay (SC3):** after crash-restart, `PendingUpload` leftovers re-drain via the first poll (existing path). `UploadedAccepted` leftovers (drained pre-crash, never advanced) are invisible to `GetPendingUploads` — the flush cadence's snapshot enumeration picks them up at the first eligible flush tick. They are bounded by the max-interval backstop; no startup gate needed. This is the "crash-between-journal-and-drain recovers via journal reconciliation" test's second leg (§8).

## 3. Library Journal / Durability Record Shape (D-03 snapshot, bulk marks)

All in [VERIFIED: thirdparty/sgns-blockstore — read this session]:

| Anchor | Fact |
|--------|------|
| LocalBlockStore.hpp:42-48 | `enum class UploadState { PendingUpload, UploadedAccepted, UploadedDurable }` — verbatim comments: "committed locally, remote upload not yet acknowledged" / "object store acknowledged receipt (durability unproven)" / "object store proved durable storage" |
| LocalBlockStore.cpp:94-96 | Journal record codec: "[version-byte 0x01]" + state byte "0x00=Pending, 0x01=UploadedAccepted, 0x02=UploadedDurable"; undecodable reads back conservatively as PendingUpload (LocalBlockStore.hpp:226-233 doc) |
| LocalBlockStore.hpp:216 | `result<void, BlockStatus> MarkUploadedDurable(const Cid& cid)` — "Moves the CID's journal record to UploadedDurable; the block leaves the pending set. Same no-fabrication rule" (no record ⇒ `NotFound+Local`, never fabricates) |
| LocalBlockStore.hpp:226 | `result<UploadState, BlockStatus> GetUploadState(const Cid& cid)` — the D-09 primitive, exists as-is |
| LocalBlockStore.cpp:559-589 | `GetPendingUploads()` — journal-CF iterator + `JournalRecord::Decode`, filters to PendingUpload state |
| LocalBlockStore.cpp:660-697 | `TransitionJournal(cid, new_state)` — read-journal-first (record-existence gate only), then ONE atomic sync WriteBatch per transition; **no source-state check** — `MarkUploadedDurable` on a still-Pending record would succeed |
| LocalBlockStore.cpp:648-657 | `MarkUploadedAccepted` / `MarkUploadedDurable` are thin wrappers over TransitionJournal |
| LocalBlockStore.hpp:239-247 | `EvictLocal` — unconditional, "the caller owns eviction policy… @warning D-10 caveat: evicting a block whose journal state is not UploadedDurable may discard the ONLY copy" — the Phase-11 gate this phase makes honest (D-10) |
| Durability.hpp:19-47 | `DurabilityLevel { LocalCommitted, PeerReplicated, ObjectStoreAccepted, ObjectStoreDurable }` + "A store NEVER reports an `achieved` level it has not verified" |
| UploadDrainer.hpp (journal discipline) | "The journal advances to the Accepted level ONLY on remote-present outcomes… The Durable-level transition is deliberately OUT of the drainer" — the library's one-shot drainer stays untouched; Phase 10's advancement lives in the SuperGenius manager (correct ownership) |

### 3.1 The GAP: no accepted-state enumeration exists

[VERIFIED: BlockStoreTooling.hpp:63-90 — `GetPendingUploads` doc: "Returns the CIDs whose upload-journal state is **PendingUpload** — blocks committed locally whose remote upload has never been acknowledged"]. There is no surface (tooling, concrete, or facade) that enumerates `UploadedAccepted` records. Consequences:

1. **D-03 snapshot:** the snapshot must be the set of records in `UploadedAccepted` at flush initiation, re-derivable after crash. An in-memory manager set is disqualified (crash loses it → Accepted leftovers never advance → SC3 fails).
2. **D-08 per-state counts:** pending comes from the existing enumeration; accepted/durable counts have no source.

**Recommended additive surface (library, Wave 1):** a concrete method on `LocalBlockStore` (journal-transition precedent: `MarkUploadedAccepted`/`MarkUploadedDurable`/`GetUploadState` live concrete-only, LocalBlockStore.hpp:180-233):

```cpp
/// Enumerate the CIDs whose journal record is in the requested state
/// (generalizes GetPendingUploads' scan; same ordering contract:
/// lexicographic over encoded CID bytes, snapshot at call start).
result<std::vector<Cid>, BlockStatus> GetUploadsInState(UploadState state);
```
Do NOT add a pure virtual to `BlockStoreTooling` — it has exactly two pure virtuals today and every implementer (incl. `MemoryBlockStore`) would break (v1.0 frozen-contract discipline). The manager already holds the concrete `LocalBlockStore` type. With this method, **the D-03 snapshot IS the enumeration**: `GetUploadsInState(UploadedAccepted)` under `cold_store_mutex_` at flush initiation — records marked Accepted after the scan are provably excluded (by-construction snapshot semantics, no timestamp bookkeeping).

### 3.2 Bulk `MarkUploadedDurable` mechanics

Single-CID `MarkUploadedDurable` is one atomic sync WriteBatch (one WAL fsync) per record [VERIFIED: LocalBlockStore.cpp:689-696]. For the snapshot set of size N, the loop costs N fsyncs. **Recommended additive (optional but cheap): `MarkUploadedDurableMany(gsl::span<const Cid>)`** composing ONE sync WriteBatch over pre-verified records — atomic all-or-nothing (a crash mid-advancement leaves either all or none marked: a *stronger* crash window than the loop), one fsync, per-item NotFound isolation optional (recommend: skip-and-continue on no-record, mirroring the no-fabrication rule; outer failure only for wholesale batch failure). Implementation sits directly beside `TransitionJournal` (same batch body, N keys). Policy tradeoffs in Design Notes.

### 3.3 D-10 (compile-time eviction gate)

`EvictLocal` never consults durability (frozen v1.0, correctly). D-10 fixes the Phase-11 gate at `UploadedDurable` with no config: recommend a named `static constexpr UploadState kEvictionDurabilityGate = UploadState::UploadedDurable;` in the gated manager TU (the SC2 test cites it), and the SC2 standalone test asserts per-CID state transitions through the D-09 getter.

## 4. Observability: Status Getter, Per-CID Pass-Through, Staging Health (D-08/D-09/D-12/D-13)

### 4.1 What exists (Phase-8 D-08)

[VERIFIED: ColdStorageStack.hpp:37-66 — verbatim struct]:
```cpp
enum class ColdStorageWatermark { None, Warn, Critical };
struct ColdStorageStatus
{
    size_t               pending_upload_count{ 0 };
    ColdStorageWatermark watermark{ ColdStorageWatermark::None };
    bool                 drainer_healthy{ false };
};
```
Backed by drainer atomics; `GlobalDB::GetColdStorageStatus()` (globaldb.cpp:796-806) rides the active-accessor pattern under `lifecycle_mutex_`.

### 4.2 The ungated-boundary constraint (plan-binding)

`ColdStorageStack.hpp` is ALWAYS COMPILED and "deliberately free of every sgns-blockstore type" [VERIFIED: ColdStorageStack.hpp:15-22]; globaldb.cpp reaches the manager ONLY through bridges (Phase-8 D-10). Therefore **every D-08/D-12 extension field must be a plain type** (integral/bool/enum declared in the ungated header) — the library `UploadStats` struct must NOT cross; flatten the needed counters. Recommended additive shape (all defaulted, additive per the "fields can grow" note):

```cpp
struct ColdStorageStatus
{
    // ... existing three fields unchanged ...
    size_t accepted_upload_count{ 0 };   ///< journal records in UploadedAccepted
    size_t durable_upload_count{ 0 };    ///< journal records in UploadedDurable
    // Last-flush evidence (D-08): valid flag + outcome + observed counters
    bool     last_flush_valid{ false };
    bool     last_flush_ok{ false };
    uint64_t last_flush_unix_ms{ 0 };
    uint64_t last_flush_pending_objects{ 0 };  // observed at advancement
    uint64_t last_flush_buffer_used{ 0 };
    uint64_t last_flush_buffer_limit{ 0 };
    // Staging health (D-12): raw counters + conservative predicate result
    uint64_t staging_pending_objects{ 0 };
    uint64_t staging_buffer_used{ 0 };
    uint64_t staging_buffer_limit{ 0 };
    uint64_t staging_failed_uploads{ 0 };
    bool     staging_healthy{ false };
};
```
Counts are drainer-maintained atomics updated at cycle boundaries + after advancement (never a journal scan on `GetStatus()` — the D-08 no-scan discipline). Seed after restart: pending from the first-poll enumeration; accepted/durable from one `GetUploadsInState` scan (pending-state call also available) at the first cycle — the same single-scan cost class as the existing reconciliation poll. (Alternative: session-relative durable counter — rejected: D-08's "per-state record counts" reads as journal truth.)

### 4.3 D-09 pass-through — zero CID friction

`sgns::blockstore::Cid` IS `libp2p::multi::ContentIdentifier` by alias [VERIFIED: Cid.hpp:47-53 — "using Cid = libp2p::multi::ContentIdentifier; … zero conversion friction for SuperGenius CRDT call sites"]. The Phase-9 "no implicit ctor" landmine concerned IpldNode wrappers, not this seam. Recommended bridge (ungated ColdStorageStack.hpp + gated .cpp):

```cpp
// ungated enum, ColdStorageWatermark precedent
enum class ColdUploadState { NoRecord, Pending, Accepted, Durable };
ColdUploadState GetColdUploadState( const std::shared_ptr<ColdStorageManager> &manager,
                                     const CID &cid );  // maps library GetUploadState
```
Plus a null-safe manager method `GetUploadState(cid)` holding `cold_store_mutex_` (the library is single-threaded-use; the Phase-11 GC calls this from its own thread — the mutex discipline is already proven for exactly this shape).

### 4.4 Staging-health predicate (D-12) + freshness (D-13)

- **Evaluate on the flush tick, cache in atomics; `GetStatus()` reads only the cache** (adding an HTTP call or journal scan to the getter would break the lock-free D-08 contract). Recommended predicate (conservative, all inputs from one stats GET):
  `staging_healthy = admin_reachable_last_tick && (bufferLimit == 0 || bufferUsed <= kStagingBufferFraction * bufferLimit) && (failedUploads delta since previous tick == 0)` — `kStagingBufferFraction` compile-time (recommend `0.8`); `bufferLimit==0` means unlimited (openapi verbatim, §1.3) so the buffer clause is vacuously true there. [Recommendation — thresholds are D-12 discretion]
- **D-13 on-demand refresh:** a manager method (e.g. `RefreshStagingStats()`) doing one bounded stats GET + predicate re-evaluation + cache update, for Phase-11 GC to call before inhibiting. It races the drainer tick's admin calls → serialize with a small dedicated `admin_mutex_` (the admin client is the only shared object; ~zero contention). No poller thread.

## 5. Config Surface (D-11) — parse anchors, knob names, defaults

### 5.1 The pattern to inherit (exactly proven)

[VERIFIED: globaldb.cpp:111-316 — `ParseColdStorageConfig`]: whole-file parse failure ⇒ lenient-disabled (:129-134); absent `blockstore` ⇒ disabled (:137-142); present-but-not-object ⇒ loud (:145-150); strict single-member loop — unknown key loud naming `blockstore.<key>` (:163-213); nested `backpressure` sub-object at :160-199 with its own strict loop, unknown-key loud naming `blockstore.backpressure.<key>`, uint-only types; 0-means-default normalization (:243-262) + post-normalization cross-field rule `warn_pending < critical_pending` (:263-271); file-intent gate — env overrides values, never activates (:274-307). `LoadCrdtConfig` invokes it and throws `std::runtime_error` on error; logs one `LogSummary()` line only when enabled [VERIFIED: GeniusNode.cpp:556-636, parse call at :620-628]. Wallet asset parity: `GeniusWallet/assets/crdt_config.json` currently `{"blockstore": {"backpressure": {}}}` [VERIFIED: read this session] — Phase 10 adds `"durability": {}` (blank form).

### 5.2 Proposed `blockstore.durability` sub-object (D-11 — names are discretion; these follow the snake_case precedent)

| Key | Type | Default (0/absent) | Rationale |
|-----|------|--------------------|-----------|
| `flush_min_interval_ms` | uint | **30000** | floor between quiescence-triggered flushes; bounds s3d flush rate (process-global, blocking — §1.4); ≥ drain-interval default (5000) so the cadence is clearly the slower loop |
| `flush_max_interval_ms` | uint | **300000** | D-01 backstop: a record never waits longer for advancement; 5 min bounds durability latency at trivial flush cost at steady state |

Validation (post-normalization, mirrors the warn<critical rule): `flush_min_interval_ms <= flush_max_interval_ms` — loud failure naming both effective values. Strictness inherits: unknown key inside `durability` ⇒ loud `crdt_config.json: unknown key 'blockstore.durability.<key>'`; wrong type ⇒ loud; not-an-object ⇒ loud. `durability`-only section ⇒ still disabled (Phase-7 (e) inheritance — optional-fields-only never activates).

**Struct/plumbing:** `ColdStorageOptions::DurabilityOptions { uint32_t flush_min_interval_ms{0}; uint32_t flush_max_interval_ms{0}; }` + `DurabilityOptions durability;` member beside `BackpressureOptions` (globaldb.hpp:91-99 precedent); normalization defense duplicated in `OpenColdStorageStack` (the ColdStorageStack.cpp:117-152 backpressure-defense precedent). `LogSummary()` extends with the two knobs (non-secret). Admin endpoint (`admin_endpoint`, §1.1) and admin password (env-only) are NOT durability knobs: endpoint sits at the `blockstore` level (string, optional, empty = `http://127.0.0.1:8001` documented); password extends `ColdStorageEnvLookup`.

### 5.3 The silent-disable hazard (must be loud)

v1.1 PITFALLS UX table: "Silent-disable on malformed config — operators believe spill/GC is on… Loud startup failure or CRITICAL + health flag" [VERIFIED: PITFALLS-rocksdb-backup-2026-10-22.md]. For Phase 10 the concrete shape: cold storage enabled + admin password ABSENT ⇒ durability advancement cannot ever succeed. Recommended posture (default-on flush per D-11): a one-time startup WARN naming the env var + flush attempts fail per D-07 backoff (health flag false, watermark-style logging) — loud, never silent. Stricter alternative (fail startup when `durability` explicitly configured but password missing) is defensible; resolved default-on — see Open Questions (RESOLVED Q1).

## 6. The Library Admin Facade (D-05) — shape, transport, hygiene

### 6.1 Recommended API (installed, beside S3Client.hpp)

New installed header `S3AdminClient.hpp` (install rule already globs `include/**/*.hpp` [VERIFIED: sgns-blockstore/CMakeLists.txt:59-62]):

```cpp
namespace sgns::blockstore {
    /// Mirrors the s3d UploadStats schema (openapi v0.2.1); plain fields.
    struct UploadStats
    {
        uint64_t pendingObjects{}, pendingSize{}, uploadedObjects{}, uploadedSize{},
                 unpinnedObjects{}, failedUploads{}, orphanedObjects{}, multipartUploads{},
                 bufferUsed{}, bufferLimit{};               // int64 counters, verbatim names
        // transfer: ingressActive/ingressBytes/ingressRate/uploadBytes/uploadRate
        // (activeUploads omitted from the struct — transient in-flight progress,
        //  explicitly not per-object durability signal; s3d-durability.md §2)
        uint64_t ingressActive{}, ingressBytes{}, ingressRate{}, uploadBytes{}, uploadRate{};
    };

    struct S3AdminClientConfig
    {
        std::string endpoint;        ///< base URL, e.g. "http://127.0.0.1:8001"
        std::string adminPassword;   ///< credential - never logged
        bool        tlsVerify = true;///< T-3-02 posture; loopback plain-HTTP lane opts out explicitly
        // + client-side timeouts (see §1.4): read timeout for Flush must be settable
    };

    class S3AdminClient  // virtual, mirroring S3Client's seam shape
    {
    public:
        virtual ~S3AdminClient() = default;
        /// POST /objects/flush — blocking server-side; bounded by the client
        /// read timeout. FAILURE is TemporarilyUnavailable-class, never NotFound.
        virtual result<void, BlockStatus> Flush() = 0;
        /// GET /stats/uploads — FAILURE is TemporarilyUnavailable-class
        /// (incl. undecodable body); success carries the parsed counters.
        virtual result<UploadStats, BlockStatus> GetUploadStats() = 0;
    };

    result<std::shared_ptr<S3AdminClient>, BlockStatus> OpenS3dAdminClient(
        const S3AdminClientConfig &config);   // OpenMinioS3Client precedent (S3Client.hpp:211)
}
```
Transport: cpp-httplib `Client` with `Authorization: Basic base64(":" + password)` (username empty — §1.1); JSON via nlohmann (`find_package(nlohmann_json CONFIG REQUIRED)`; the superbuild already installs it — §Standard Stack; link PRIVATE beside miniocpp/blake2 in src/CMakeLists.txt). Result alias + BlockStatus taxonomy reused unchanged (zero new failure classes). The manager owns the admin client; `S3BlockStore` stays S3-object-shaped (Alternative considered in Standard Stack; both satisfy D-05).

### 6.2 The fake (D-05 — "InMemoryS3Client fake gains a fake admin endpoint")

Recommended: `InMemoryS3AdminClient` in `src/` beside `InMemoryS3Client.hpp` (deliberately NOT installed; SuperGenius tests reach it via the proven relative-include-dir workaround [VERIFIED: test/src/crdt/CMakeLists.txt:105-113]). Scriptable surface (test-seam discipline, "CONFORMANCE-TEST SEAM: production code MUST NOT call"):
- `SetStats(UploadStats)` — the body the next `GetUploadStats()` serves;
- `SetAdminFault(S3AdminFaultKind)` — recommended kinds: `None`, `Unreachable` (transport → TemporarilyUnavailable), `FlushFails` (500-equivalent → TemporarilyUnavailable), `GarbageStats` (non-JSON/missing-fields body → TemporarilyUnavailable), `SlowFlush(ms)` (blocking/timeout semantics for the D-04 grace test);
- `flush_count()` / `stats_count()` accessors — the cadence assertions (SC1: flush observed before marks; floor respected) assert on these;
- Optional flush hook (`std::function<void()>` on flush) for cross-fake coordination (e.g. flip the S3 fake's pending model) — keeps each fake single-purpose; tests coordinate explicitly.

### 6.3 Library hygiene gates to extend (Wave-1 checklist)

- `api_hygiene_test.cpp` enumerates installed headers by explicit include — add `S3AdminClient.hpp` (the Phase-4 promotion precedent, 04-RESEARCH Pitfall 1).
- `header_hygiene_check.cmake` bans non-installed includes from installed headers — the new header must include only `BlockStatus.hpp`/`Cid.hpp`-class installed types.
- Wrapper-vcxproj staleness: deployed-header hash check after adding the installed header (04-RESEARCH Pitfall 6, MSVC no-dependent-rebuild landmine).
- `docs/s3d-durability.md` §3 wording correction (process-global flush, §1.4) + admin-auth note belong in the same library change-set.

## 7. Shutdown Interplay (D-04 / SC3)

**Verified current order** [VERIFIED: globaldb.cpp:387-424]: `ShutdownNow()` → `StopBackupLoop()` (:398) → `StopColdStorageManager()` (:402) → `StopColdReadService()` (:408) → `lifecycle_mutex_` teardown (broadcaster Stop, crdt CancelAndCloseNow). The backup engine touches GlobalDB's RocksDB, never the cold store — the interplay is ordering discipline only.

**D-04 placement (recommended):** the final bounded flush+observe+mark runs INSIDE `ColdStorageManager::Stop()`, after `thread_.join()`, before returning (the contract comment — "only after it returns may the owner close/destroy the stores" — makes Stop the last safe point). Shape:
1. guard with a `final_flush_done_` atomic (Stop is idempotent; the attempt runs exactly once — also covers the destructor path);
2. enumerate the accepted snapshot under `cold_store_mutex_` — **required**: the Phase-9 re-warm worker may still be running (it stops at :408, AFTER the manager at :402) and touches the local store under the same mutex;
3. one admin Flush with a SHORT timeout (its own compile-time budget, e.g. `kFinalFlushBudget{2000}` ms — NOT the cadence timeout; D-04 "one bounded attempt within the existing grace budget") + one stats GET + marks (batched preferred, §3.2);
4. any failure at any step: log one line, leave records Accepted, return — leftovers resume via the first-poll/first-flush-cycle paths at next startup (the single resume-code-path property D-04 wants).

**The unbounded-join hazard (plan-binding):** `Stop()`'s `thread_.join()` is unconditional [VERIFIED: ColdStorageManager.cpp:96-100]. A cadence flush in flight when stop fires delays join until the HTTP call returns — without the §1.4 client-side read timeout this is unbounded (s3d has no server deadline). Two mitigations, take both: (a) admin client timeouts (§6.1); (b) skip a NEW flush cycle when `stop_flag_` is already set (check before initiating; an in-flight one is bounded by (a)).

**SC3 shutdown test surface (hermetic):** manager-level `Stop()` under load — publisher thread setting blocks through the decorator + fake admin scripted `SlowFlush`/`FlushFails` → assert: join returns bounded, no crash, records left Accepted, journal intact; then reconstruct a manager over the same `coldstore` dir → first poll re-drains Pending and the first flush cycle advances Accepted (the reconciliation proof). GlobalDB-level ordering (:398-:408) is structural; assert it only if an existing integration test already exercises ShutdownNow with cold storage on (optional).

## Design Notes — flush-cadence cost vs `MarkUploadedDurable` batching policy (ROADMAP-requested)

**The cost being traded:** s3d `POST /objects/flush` is process-global, blocking, and triggers Sia uploads + pins for every pending object [VERIFIED: openapi §1.4]. It is not free and not scoped to our bucket. The cadence knobs (D-11) exist to price it: `flush_min_interval_ms` bounds flush frequency; `flush_max_interval_ms` bounds durability latency.

**Policy recommendation:** quiescence-gated advancement with a generous floor (30 s) and a 5-min backstop. At steady state (drain keeps up), each flush advances exactly the records accepted since the last flush — flush count tracks write-burst count, not write rate (D-01's rejection of quiescence-only-without-floor and pure-timer is the right read: the floor prevents flush hammering during sustained bursts; the backstop prevents starvation under sustained activity that never goes quiescent). Sustained-burst behavior: a flush every `flush_max_interval_ms` at worst, each advancing the accumulated accepted set — the batching falls out of the cadence naturally.

**Batching policy:** enumerate-then-batch (`MarkUploadedDurableMany`, one sync WriteBatch) rather than per-record marks. Correctness: identical post-state; crash window is tighter (all-or-nothing vs N windows). Cost: one fsync vs N — after a long s3d outage the drainer may have thousands of Accepted records when the backstop flush finally fires; N sync batches could hold the drainer thread (and thus a shutdown join) for seconds-to-minutes. The single-CID loop remains correct if the planner prefers zero new library surface beyond enumeration — but then the shutdown-grace math (D-04) must assume N fsyncs inside the bounded budget, which argues for the batch anyway. **Recommended: ship the batched variant in Wave 1.**

**Evidence-vs-cost note:** the stats GET rides every flush (D-13 on-tick) and is cheap; no additional polling. Counter-deltas-are-never-per-object-proof (s3d-durability.md §2 concurrency limitation) stays law: the only per-record claim ever made is "was Accepted in the pre-flush snapshot AND `pendingObjects==0` was observed after a flush that returned success" — a set-level argument, exactly D-03.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON parsing of `UploadStats` | ad-hoc string scanning | nlohmann_json (superbuild, PRIVATE link) | truncation/garbage/number-format edge cases; the fake's `GarbageStats` fault exists precisely to test the parser's failure path |
| HTTP + basic auth | raw sockets / minio-cpp reuse | cpp-httplib `Client` (already a hard dep of the library build) | minio-cpp is SigV4-S3-shaped; the admin API is plain basic-auth JSON |
| Journal state advancement | direct RocksDB writes | `MarkUploadedDurable` (+ the additive batched variant) | Journal transitions are backend-owned (v1.0 D-06); the manager never touches RocksDB |
| Accepted-set tracking | in-memory manager set | journal enumeration (`GetUploadsInState`) | crash-restart must re-derive the D-03 snapshot (SC3) |
| Backoff/cadence lifecycle | new thread/timer infra | the existing drainer loop + Phase-8 backoff shape | D-02: no new thread lifecycle; twice-proven pattern |
| Status plumbing | new RPC/status system | additive `ColdStorageStatus` fields + bridges | Phase-8 D-08 "fields can grow"; ungated-boundary discipline |
| Fault injection | hand-rolled flags | `S3AdminFaultKind` on the fake admin (S3FaultKind precedent) | deterministic, composable with the existing kit |

**Key insight:** every mechanism below the policy line (journal states, transitions, taxonomy, fakes, drainer lifecycle, config parse) is a shipped, guard-tested contract read this session. Phase 10's genuinely new artifacts are: one library header+impl+fake, one concrete enumeration method, one optional batched mark, the manager's cadence/advance/observe step, additive status fields, one config sub-object, and tests.

## Common Pitfalls

### Pitfall 1: Treating the flush as bucket-scoped
**What goes wrong:** a design that assumes `POST /objects/flush` can target one bucket (the ROADMAP's wording) over-promises cost isolation; evidence (`pendingObjects==0`) is process-global.
**Why:** planning docs said "bucket-scoped"; the pinned openapi has NO bucket parameter (§1.4).
**Avoid:** facade takes no bucket; doc wording corrected in Wave 1; shared-s3d deployments understood as slower-advancement-only.
**Warning signs:** any plan task passing a bucket to Flush; per-bucket cost claims.

### Pitfall 2: Accepted records stranded after restart
**What goes wrong:** crash leaves records `UploadedAccepted`; `GetPendingUploads` never lists them (Pending-only), so nothing re-derives the advancement set → they wait forever.
**Why:** the enumeration gap (§3.1) + in-memory snapshot designs.
**Avoid:** snapshot = journal enumeration at flush initiation; the first flush cycle after restart picks Accepted leftovers up (bounded by the backstop). Test it explicitly (SC3).
**Warning signs:** `accepted_upload_count` non-zero and `durable_upload_count` frozen across restarts.

### Pitfall 3: Marking records that were not in the snapshot
**What goes wrong:** marking a record Accepted *after* flush initiation on the same evidence — the accepted-is-durable assumption sneaks back in.
**Why:** `TransitionJournal` does not check source state (§3); a "mark everything currently Accepted" step taken after a delayed stats read reintroduces the race D-03 exists to kill.
**Avoid:** the enumerated vector IS the advancement set — marks iterate exactly it, captured under `cold_store_mutex_` before the flush call.
**Warning signs:** any code path calling `MarkUploadedDurable` with a CID not taken from the snapshot vector.

### Pitfall 4: Unbounded shutdown join via blocking flush
**What goes wrong:** `Stop()`'s unconditional join waits out an in-flight flush with no server deadline; shutdown hangs (SC3's race-free-under-load failure).
**Why:** "Blocks until done" + no client timeout (§1.4/§7).
**Avoid:** client read timeouts (cadence + a shorter final-flush budget) + skip-new-flush-when-stopping.
**Warning signs:** shutdown latency correlating with s3d backlog size.

### Pitfall 5: Library types crossing the ungated boundary
**What goes wrong:** `UploadStats` (library type) placed in `ColdStorageStatus` — the always-compiled header gains an sgns-blockstore include; OFF builds break (Phase-7 byte-identical bar).
**Why:** convenience of passing the parsed struct through.
**Avoid:** plain-type fields only (§4.2); bridge returns an ungated enum (§4.3).
**Warning signs:** any `#include <sgns-blockstore/...>` in `ColdStorageStack.hpp`/`globaldb.hpp` diffs.

### Pitfall 6: Flush failures poisoning the drain backoff (or vice versa)
**What goes wrong:** one shared failure streak couples the two loops — drain backoff suppresses flush cycles, or flush 500s make the drainer look unhealthy when draining is fine.
**Why:** sharing `current_delay_`/`failure_streak_` is the "obvious" reuse.
**Avoid:** separate cadence/backoff state (§2); log lines distinguish flush vs drain failures by wording (D-07).
**Warning signs:** drain-interval doubling in logs during an admin-only outage.

### Pitfall 7: Silent durability-off when the admin password is absent
**What goes wrong:** enabled cold storage + no `SGNS_BLOCKSTORE_S3_ADMIN_PASSWORD` → every flush fails; operators believe data is durable-advanced when records sit Accepted forever.
**Why:** the silent-disable UX pitfall (§5.3).
**Avoid:** one-time startup WARN naming the env var + health/staging flags false + watermark-discipline logging on sustained failure.
**Warning signs:** `accepted_upload_count` monotonic with `last_flush_ok == false` and no operator-visible alarm.

### Pitfall 8: Hand-rolled JSON or assuming the stats body shape
**What goes wrong:** string-scraping `pendingObjects` breaks on truncation/garbage (the 502/503/504/truncation shapes the question asks about are FAKE-side tests precisely because s3d doesn't document them for admin); missing-field bodies crash or misparse zero.
**Why:** the admin error taxonomy is undocumented beyond 200/500 (§1.5).
**Avoid:** nlohmann strict field presence; every parse failure → TemporarilyUnavailable; the `GarbageStats` fault test pins it.
**Warning signs:** any `find("\"pendingObjects\"")`-style code.

## Code Examples

### The flush step at the drainer cycle end (shape — gated TU)
```cpp
// Modeled on the verified loop at ColdStorageManager.cpp:56-80 and the
// split-phase DrainOnce (:123-241). Runs on the drainer thread ONLY (D-02).
void ColdStorageManager::AdvanceDurabilityOnce( bool quiescent_this_cycle )
{
    // (0) cadence gate — D-01 hybrid trigger, separate flush-backoff state
    if ( !FlushCadenceAllows( quiescent_this_cycle ) ) { return; }
    // (i) D-03 snapshot: the enumeration IS the snapshot (journal-derived,
    //     re-derivable after crash). Library types never leave the gated TU.
    std::vector<sgns::blockstore::Cid> snapshot;
    {
        std::lock_guard<std::mutex> lock( *cold_store_mutex_ );
        auto accepted = local_block_store_->GetUploadsInState(
            sgns::blockstore::UploadState::UploadedAccepted ); // additive, §3.1
        if ( !accepted.has_value() ) { RecordFlushFailedCycle(); return; }
        snapshot = std::move( accepted.value() );
    }
    if ( snapshot.empty() ) { RecordFlushIdle(); return; }
    // (ii) flush (bounded by the admin client's read timeout — §1.4)
    auto flushed = admin_client_->Flush();
    if ( !flushed.has_value() ) { RecordFlushFailedCycle(); return; } // D-07 backoff
    // (iii) observe — evidence gate; non-zero simply means "not this cycle"
    auto stats = admin_client_->GetUploadStats();
    if ( !stats.has_value() ) { RecordFlushFailedCycle(); return; }
    UpdateStagingHealth( stats.value() );                    // D-12/D-13 on-tick
    if ( stats.value().pendingObjects != 0 ) { RecordFlushNoEvidence(); return; }
    // (iv) advance exactly the snapshot (batched preferred — §3.2/Design Notes)
    {
        std::lock_guard<std::mutex> lock( *cold_store_mutex_ );
        auto marked = local_block_store_->MarkUploadedDurableMany( snapshot );
        if ( !marked.has_value() ) { RecordFlushFailedCycle(); return; }
    }
    RecordFlushSucceeded( stats.value() );                   // evidence cache, D-08
    BackoffResetFlush();
}
```

### Tier-1 registration (verbatim pattern; the new suite follows it)
```cmake
# Verified: SuperGenius/test/src/crdt/CMakeLists.txt:98-113 (Phase-8/9 precedent)
if(SGNS_COLD_STORAGE)
addtest(cold_storage_durability_test
    cold_storage_durability_test.cpp
)
target_link_libraries(cold_storage_durability_test
    sgns-blockstore::sgns-blockstore
    crdt_globaldb
)
target_include_directories(cold_storage_durability_test PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../../../../thirdparty/sgns-blockstore/src"
)
set_tests_properties(cold_storage_durability_test PROPERTIES LABELS "Tier1")
endif()
```

### Config matrix extension (the backpressure block is the template)
```cpp
// Verified pattern: cold_storage_config_gate_test.cpp:256-360 (Backpressure* cases)
TEST( ColdStorageConfigGate, DurabilityAbsentSubObjectGivesDefaults )
TEST( ColdStorageConfigGate, DurabilityZeroKnobTakesOnlyItsDefault )
TEST( ColdStorageConfigGate, DurabilityUnknownKeyFails )        // "unknown key 'blockstore.durability.bogus'"
TEST( ColdStorageConfigGate, DurabilityMinAboveMaxFails )       // post-normalization rule, §5.2
TEST( ColdStorageConfigGate, DurabilityOnlySectionDisables )    // Phase-7 (e) inheritance
TEST( ColdStorageConfigGate, AdminEndpointOptionalString )
```

## State of the Art (in-codebase drift watch)

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| s3d durability unobservable per-object; accepted-is-max-provable | flush + pipeline-global counters as SET-level evidence (this phase) | Phase 10 | the eviction gate becomes evidence-backed without a per-object signal (fast-follow polling still out of scope) |
| `GetPendingUploads` the only journal enumeration | + `GetUploadsInState` (additive) | Phase 10 | D-03 snapshots journal-derived; per-state counts sourceable |
| Drainer marks Accepted only ("Phase-10 boundary" comment, ColdStorageManager.cpp:213-215) | drainer also advances Durable behind the flush gate | Phase 10 | the comment gets replaced by the advancement step it anticipated |
| `MarkUploadedDurable` caller/tooling-only (UploadDrainer.hpp discipline; v1.0 D-04) | production advancement exists — in the SuperGenius manager, NOT the library one-shot drainer | Phase 10 | library drainer contract unchanged (correct: it has no cadence/evidence context) |

**Deprecated/outdated to correct in-tree:** "bucket-scoped flush" wording (ROADMAP SC1, 10-CONTEXT SC1, s3d-durability.md §3 "bucket/global-scoped") → process-global per the pinned openapi (§1.4).

## Security Domain (ASVS L1 — `security_enforcement: true`, `security_block_on: high` [VERIFIED: .planning/config.json])

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | Admin HTTP Basic (`adminPassword`, username ignored — §1.1); credential env-only (`SGNS_BLOCKSTORE_S3_ADMIN_PASSWORD`), never in config files, never logged (D-06 + Phase-7 D-07 posture) |
| V3 Session Management | no | per-request basic auth; no sessions |
| V4 Access Control | yes | admin endpoint loopback-default (`127.0.0.1:8001`); ops note: firewall/loopback the admin port (v1.1 PITFALLS Security table — `/objects/flush`, stats tampering) |
| V5 Input Validation | yes | stats JSON parsed strictly (nlohmann; field presence + integer types); parse failure → TemporarilyUnavailable, never trusted defaults; no caller-supplied URLs beyond the configured endpoint |
| V6 Cryptography | no new surface | TLS verify default-ON in the admin config (T-3-02 posture); loopback plain-HTTP is the documented s3d lane (self-signed per-start cert must not be verified) |
| V9/V10 Logging | yes | password never formatted (redaction by omission — `BlockStatus.hpp` message rule + Phase-7 LogSummary discipline); flush/drain/peer failures distinguishable by wording (D-07) |

| Threat Pattern | STRIDE | Standard Mitigation |
|----------------|--------|---------------------|
| Admin credential leakage into logs/status | Information Disclosure | env-only; `S3AdminClientConfig` fields never logged; evidence cache stores counters, not credentials |
| Flush/stats response tampering (hostile/misconfigured proxy) | Tampering | counters used only as advancement *permission* (conservative direction: tampered non-zero ⇒ no advancement, records stay Accepted — fail-safe); tampered zero ⇒ advancement on false evidence — bounded by loopback-default topology + TLS option |
| DoS via unbounded blocking flush | DoS | client read timeouts + skip-flush-when-stopping (§7); drainer-thread isolation (D-02) keeps writes/reads unaffected |
| Silent durability-off | Information Disclosure (operator deception) | loud startup warn + health flags (§5.3) |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | s3d v0.2.1 remains the characterized pin (33 commits on master at v1.0 research; no re-release gates this phase) | §1 | a pin bump requires re-running the spike runbook + re-characterizing s3d-durability.md (documented rule) — flush/stats shapes could shift |
| A2 | cpp-httplib `Client` basic-auth + read-timeout mechanics suffice for the admin endpoint (library links it for miniocpp today; direct use not yet exercised in-repo) | §6 | minor — worst case an adapter tweak; LoopbackHttpStub (test kit) can wire-verify pre-merge |
| A3 | nlohmann_json superbuild target name/link works from the library's ExternalProject context (config file located this session; consumption not yet written) | §6 | configure-time fix; fallback: vendor nothing, resolve via the same httplib-style explicit find |
| A4 | Default knob values (30 s floor / 300 s backstop) and the 0.8 buffer fraction are reasonable starting points (recommendations, not measured) | §5.2/§4.4 | operational tuning later; knobs exist precisely for this — defaults documented, not load-bearing for correctness |
| A5 | `bufferLimit` semantics (zero = unlimited) and counter globality hold for every s3d build at the pin (openapi + captured bodies agree) | §1.3/§4.4 | predicate treats zero-limit as unconstrained — if semantics differed, health flag could under-report; single captured deployment agrees |
| A6 | A `MarkUploadedDurableMany` composed as one sync WriteBatch preserves the no-fabrication rule per item (skip-and-continue on missing records) — implementation detail not yet written | §3.2 | if implemented as all-or-nothing on missing records, a concurrent eviction could abort a batch; per-item skip mirrors existing semantics (design note in §3.2) |

Everything else in this document is `[VERIFIED: file:line]` or `[VERIFIED: fetched URL]` against sources read this session.

## Open Questions (RESOLVED)

All three questions were ruled at planning (2026-10-26); the rulings are implemented in 10-01 and restated inline below.

1. **Missing-admin-password posture (default-on + loud warn vs hard-fail when `durability` explicitly configured)** — §5.3 recommends default-on + one-time WARN + D-07 alarms. If the planner reads D-11's "absent knobs = defaults" as activating flush by default, confirm the loud-warn shape; a hard-fail mode is a one-line alternative behind the same parse.
   - What we know: D-06 resolves to env-only credential; silent-disable is a documented UX pitfall.
   - What's unclear: whether the user wants startup to FAIL when durability is explicitly configured but the credential is absent.
   - Recommendation: default-on + loud warn (matches D-11/D-07 letter); surface at plan review.
   - RESOLVED (planner ruling, implemented in 10-01 Task 3): default-on flush + one-time startup WARN naming SGNS_BLOCKSTORE_S3_ADMIN_PASSWORD + D-07 backoff/alarm discipline on sustained failure; no hard-fail mode — flush activation never couples to operator bookkeeping.
2. **`admin_endpoint` key placement** (`blockstore.admin_endpoint` recommended vs inside `durability`) — pure schema taste; both strictness-equivalent. Planner picks; wallet asset updated in the same task.
   - RESOLVED (planner ruling, implemented in 10-01 Task 3): `blockstore.admin_endpoint` at the blockstore level, sibling of `endpoint` — connection topology, not cadence, not a secret; wallet asset parity in the same task.
3. **Batched-marks inclusion in Wave 1** (recommended IN, §3.2/Design Notes) vs minimal single-CID loop — scope decision; correctness identical, shutdown-budget math differs.
   - RESOLVED (planner ruling, implemented in 10-01 Task 2): `MarkUploadedDurableMany` ships in Wave 1 — one sync WriteBatch = one fsync + all-or-nothing crash window + bounded shutdown budget; the Task-1 tracer advances via the single-CID loop and Task 2 switches the call site.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| sgns-blockstore superbuild install (ExternalProject via CommonTargets.CMake:862-920) | library changes (D-05/§3) rebuild through it | ✓ `thirdparty/build/Windows/Debug/sgns-blockstore` (config verified this session) | v1.0+Phase-6, main @ `ad07cab` | — |
| SuperGenius `dev_blockstore` build (SGNS_COLD_STORAGE=ON) | gated TUs + Tier-1 suites | ✓ (Phase 7-9 lane; HEAD `b17643b5a`) | — | OFF builds keep the config-gate Tier-1 lane non-empty |
| s3d binary v0.2.1 + Sia account | live-tier verification only (dev-gated; never CI) | ✗ not at `W:\gnus\s3d.exe`; env script `W:\gnus\s3d-spike-env.ps1` present (names/values not read) | v0.2.1 pin | runbook download path (official GitHub release ~7 MB); hermetic Tier-1 needs none of it — the fake admin covers SC1-SC4 |
| `W:\gnus\minio-community.exe` | optional MinIO tier (not required this phase) | ✓ (verified this session) | RELEASE.2025-04-22 | unused by Phase 10 plans |
| nlohmann_json superbuild install | UploadStats parsing | ✓ config at `thirdparty/build/Windows/Debug/json/share/cmake/nlohmann_json/` (verified this session) | superbuild pin | — |
| cpp-httplib | admin client transport | ✓ (`find_package(httplib CONFIG REQUIRED)` already in the library build) | superbuild pin | — |

**Missing dependencies with no fallback:** none blocking — every Wave-1/Wave-2 deliverable is hermetic. A dev-gated live re-verification of flush/stats against a real s3d (runbook) is recommended before close-out but is not a plan blocker; flag as optional human-gated evidence.

**Missing dependencies with fallback:** none.

## Sources

### Primary (HIGH confidence — read this session)
- `thirdparty/sgns-blockstore/docs/s3d-durability.md` (§1-§6 complete); `docs/evidence/s3d-spike/{README.md, stats-before-put.txt, stats-after-put.txt, stats-after-flush.txt, e2e-stats-captures.txt, staged-read-headers.txt}`
- `https://raw.githubusercontent.com/SiaFoundation/s3d/v0.2.1/openapi.yml` — fetched 2026-10-26: admin API description (separate listener, basic auth, username ignored), `securitySchemes`, `/stats/uploads`, `/objects/flush` (no parameters; 200/500 only), `UploadStats`/`TransferStats`/`ActiveUpload` schemas verbatim
- `thirdparty/sgns-blockstore/include/sgns-blockstore/{LocalBlockStore,Cid,Durability,UploadDrainer,BlockStoreTooling,S3Client}.hpp`; `src/{LocalBlockStore.cpp, InMemoryS3Client.hpp}`; `CMakeLists.txt`; `src/CMakeLists.txt`
- `SuperGenius/src/crdt/globaldb/{ColdStorageManager.hpp, ColdStorageManager.cpp, ColdStorageStack.hpp, ColdStorageStack.cpp, BlockStoreBackedIpfsDatastore.hpp, BlockStoreBackedIpfsDatastore.cpp, globaldb.hpp, globaldb.cpp}` — Phase-8/9 anchors cited inline (§2, §4, §5, §7)
- `SuperGenius/src/account/GeniusNode.cpp:556-636` (LoadCrdtConfig); `GeniusWallet/assets/crdt_config.json`
- `SuperGenius/test/src/crdt/{CMakeLists.txt, cold_storage_config_gate_test.cpp, cold_storage_spill_test.cpp}`
- `thirdparty/build/CommonTargets.CMake:862-920`; superbuild install probes (sgns-blockstore, nlohmann_json) this session
- `.planning/workstreams/rocksdb-backup/{REQUIREMENTS.md, STATE.md}`; `10-CONTEXT.md`; `.planning/research/PITFALLS-rocksdb-backup-2026-10-22.md`; `04-RESEARCH.md` (v1.0 archive — openapi fetch provenance); `09-RESEARCH.md` (sibling structure + Phase-9 anchors)
- `.planning/config.json` (nyquist_validation: false — Validation Architecture section omitted per phase instructions; security_enforcement: true)

### Secondary (MEDIUM confidence)
- None — every load-bearing claim is primary-sourced this session.

### Tertiary (LOW confidence)
- None — recommendations (defaults, names, shapes) are clearly labeled discretion recommendations, not factual claims.

## Metadata

**Confidence breakdown:**
- s3d admin surface (D-06, endpoints, schemas, error taxonomy): HIGH — openapi fetched live at the pinned tag this session + committed evidence artifacts re-read
- Library state machine + the enumeration gap: HIGH — headers and journal implementation read this session with verbatim quotes
- Drainer/status/config/shutdown anchors (SuperGenius): HIGH — every cited file read this session at the cited lines
- Recommendations (knob defaults, facade shape, predicate thresholds): MEDIUM — grounded in the verified facts but explicitly discretion; the planner/user finalize

**Research date:** 2026-10-26
**Valid until:** 2026-11-25 (stable tree; s3d pin rule: any pin bump invalidates §1 — re-run the spike runbook)
