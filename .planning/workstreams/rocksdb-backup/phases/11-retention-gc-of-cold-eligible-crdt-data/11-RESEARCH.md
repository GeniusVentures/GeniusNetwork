---
phase: 11
phase_name: Retention GC of Cold-Eligible CRDT Data
workstream: rocksdb-backup
milestone: v1.1
requirements: GC-01, GC-02, GC-03, TEST-03
researched: 2026-10-27
researcher: gsd-phase-researcher
confidence: HIGH
---

# Phase 11: Retention GC of Cold-Eligible CRDT Data - Research

**Researched:** 2026-10-27
**Domain:** local eviction-only garbage collection over the Phase-8/9/10 cold-storage stack (sgns-blockstore journal + SuperGenius CRDT hot store)
**Confidence:** HIGH (every load-bearing in-repo fact verified at file:line this session; the genuinely novel design questions are isolated, reasoned from verified premises, and flagged for the planner)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions (D-01..D-16 — bold statements verbatim from `11-CONTEXT.md`; full rationale/reversibility text lives there)

**Retention age evidence & activation (GC-01)**
- **D-01:** **Wall-clock age from the journal/spill timestamp** — each spilled CID's journal timestamp is the age evidence; the operator mental model is "keep N days", matching GC-01's literal "age threshold in `crdt_config.json`". The researcher verifies whether the spilled-CID index/journal records a usable timestamp today and adds one additively if not.
- **D-02:** **Explicit opt-in activation** — `blockstore.retention` absent → no GC actor constructed, byte-identical behavior (Phase-7 tri-state posture). Present → GC runs.
- **D-03:** **Dry-run is a config flag** — `dry_run` inside `blockstore.retention`: a persisted observe-only posture; the delete step is simply suppressed.
- **D-04:** **Age key required when `retention` is present** — `blockstore.retention` present but no age key → loud startup failure. Unknown keys inside stay loud per Phase-7 strictness.

**Reachability walk & GC scheduling (GC-01)**
- **D-05:** **Full fresh walk each pass** — every GC pass walks the DAG from `CrdtHeads::GetList` to fresh completion; no persisted reachability state. The O(history) cost is accepted: passes are infrequent, run off the write path, batched with a resumable cursor.
- **D-06:** **Dedicated GC thread** — own thread mirroring the twice-proven backup-loop/drainer pattern (never `io_`, never the pubsub asio context) with its own stop + join slot in the `GlobalDB::Shutdown` ordering. The staging-health flag (Phase-10 D-12) gates its tick; the D-13 on-demand stats refresh (Phase-10) is consulted before inhibition.
- **D-07:** **Interval knob + documented default** — a `gc_interval_ms`-style cadence knob in `blockstore.retention` with a documented built-in default.
- **D-08:** **Heads snapshot at pass start + per-CID re-check at mark** — the pass walks against a heads snapshot taken at pass start, and before any CID transitions to evicting, its non-reachability is re-verified against CURRENT heads as a cheap point check. The grace window is pure safety margin, never the only correctness line.

**Disposed-CID markers (GC-02)**
- **D-09:** **Markers live in the library** — a disposed-CID record (column family or keyspace) inside sgns-blockstore's `LocalBlockStore` RocksDB, so block-bytes + resolved-marker + disposed-marker atomicity is a single-store RocksDB batch, and genius-tube gets the same primitive for free.
- **D-10:** **Bound = count cap + marker age, whichever trims first** — both values documented built-in defaults; a trimmed CID that re-arrives is simply re-learned (re-journal → re-spill → re-drain).
- **D-11:** **Re-broadcast dedup extends `HasBlock`** — the disposed-marker lookup slots into `HasBlock` after the cold-dir check (same RocksDB-point-lookup class as Phase-9 D-09 — freeze-safe, no network). A marker hit means "already integrated".
- **D-12:** **Split semantics: `NotFound` is a re-delivery concept only** — authoritative NotFound/skip applies only to the pubsub/CRDT dedup path; direct reads always resolve through the Phase-9 cold chain. NotFound never escapes a read path for a disposed CID.

**Two-phase eviction mechanics (GC-02)**
- **D-13:** **Grace duration is a config knob with a documented default** — the mark→delete grace lands as a knob in `blockstore.retention`.
- **D-14:** **Delete-time re-check + cancel** — physical delete re-verifies non-reachability against current heads immediately before the destructive batch (the same cheap point check as at mark). Reachable-again → cancel: clear the mark, keep the bytes.
- **D-15:** **Evicting marks are in-memory** — GC-thread state surfaced via the status getter; only the terminal disposed marker persists. Crash mid-grace → marks vanish, nothing was deleted, the next pass re-walks and re-marks from scratch.
- **D-16:** **Library-atomic destructive batch, then idempotent hot-store cleanup** — the destructive step is ONE single-store RocksDB batch in the library (block bytes + resolved marker + disposed marker together); hot-store set-row removal follows as an idempotent cleanup step. A crash between them leaves orphaned hot bytes that still count as present → the next pass re-evicts them (under-eviction direction — safe). Hot-first ordering was rejected; write-ahead intent records were rejected.

### The Agent's Discretion (verbatim from 11-CONTEXT.md)
- Exact knob names inside `blockstore.retention` (age, dry-run, interval, grace — subject to D-02/D-03/D-04/D-07/D-13 semantics + Phase-7 strictness inheritance: absent sub-object = disabled; unknown key inside = loud startup failure; wallet asset `crdt_config.json` ships blank-form parity)
- Exact built-in default values (cadence interval, grace duration, marker count cap, marker max-age)
- Timestamp recording mechanics if the journal lacks a per-CID timestamp today (additive journal column vs side index) — researcher verifies what exists and picks the additive shape
- Walk batching mechanics: batch size, cursor persistence (in-pass resumability vs across-pass), and how the walk reads without holding `dagMutex_` across batches
- Protected/pinned namespace enumeration (heads, genesis, current-epoch pointers) and how the never-enumerates-tombstone-keyspaces guard test proves it
- Marker record content (disposed-at, reclaimed bytes, original size, reason) and the per-pass metrics surface (SC5 reclaimed counts/bytes)
- Epoch watermark record shape (SC5: computation + storage only — nothing deletion-gated on it in v1.1)
- Status-getter extension fields (evicting count, last-pass metrics, dry-run indicator) — additive per the Phase-8 D-08 "fields can grow" note
- `DeleteCIDBlock` LRU invalidation mechanics keeping `HasBlock` honest post-eviction
- Whether the GC thread or the library owns the disposed-marker trim sweep mechanics
- Tier-1 guard test design (fault kit reuse: `InMemoryS3Client` + `FaultController`), and TEST-03's live evidence artifact format + runbook location (dev-gated, never in CI)
- MinIO-binary opt-in roundtrip mechanics (v1.0 Tier-2/3 precedent)
- Exact log-message wording (constraint: GC pass/dedup/eviction events distinguishable from drain/flush and peer failures)
- Tier-1 test target registration mechanics (Phase-7 lane, `ctest -L Tier1 --no-tests=error`, tier-label discipline)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope. (Reviewed todo "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" — unrelated, stays backlog.)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description (REQUIREMENTS.md) | Research Support |
|----|-------------------------------|------------------|
| GC-01 | A configurable retention policy (age threshold in `crdt_config.json`) identifies cold-eligible CRDT data; policy evaluation never touches tombstones or head-reachable causal history | §1 (the timestamp GAP + additive shape), §2 (walk + snapshot/re-check semantics), §5 (config surface + D-04 wallet-asset consequence), §8 (guard-test design) |
| GC-02 | Eviction-only GC removes block bytes locally (two-phase: durability-record gate + non-reachability check; block bytes, resolved marker, and set rows evicted as one unit) and writes a bounded disposed-CID marker yielding authoritative `NotFound` + re-broadcast dedup; tombstones and CRDT metadata are never purged in v1.1 | §3 (two-phase mechanics + the D-16 unit-atomicity reconciliation), §4 (markers + `HasBlock` extension + D-12 split), §6 (thread/lifecycle), §8 (fault tests) |
| GC-03 | Any GC-evicted CID remains retrievable end-to-end — a graphsync request or local read for it resolves from the blockstore, CID-verified | §4.3 (read-path split semantics ride the verified Phase-9 chain unchanged), §8.2 (hermetic Tier-1 lanes for both legs) |
| TEST-03 | Dev-gated live tier — MinIO-binary opt-in roundtrip plus one live s3d spill → GC → retrieve E2E with committed evidence artifacts; never in CI | §8.3 (live-tier design, v1.0 Tier-2/3 precedent, env probes), Environment Availability |
</phase_requirements>

## Project Constraints (from AGENTS.md / SuperGenius CLAUDE.md / copilot-instructions.md)

- C++17/C++20, CMake — match existing SuperGenius conventions; **no new external dependencies** (workstream Out of Scope table).
- Corelinux-derived style (`Coding Standards.md`): Ullman braces, PascalCase types/methods, `m_`/trailing-underscore members, `Get`/`Is`/`Set` accessor prefixes, Doxygen `@brief/@param/@return/@note` on public interfaces, `outcome::result<T>` for fallible operations.
- **Every library result guarded with `has_value()` BEFORE `.value()`** (`policy::terminate` alias — the standing landmine; Cid.hpp:37-45).
- "Gates, not promises": rules that matter are enforced by ctest/CI, not comments alone — SC1/SC2 guard tests ARE the deliverable.
- Header hygiene (Phase-7/8/9/10, binding): `globaldb.hpp`, `globaldb.cpp`, `ColdStorageStack.hpp` must NEVER include gated sgns-blockstore headers; `ColdStorageManager.hpp` and the decorator are GATED TU headers (SGNS_COLD_STORAGE only); ungated code reaches the stack only through `ColdStorageStack` free-function bridges. Every new status field must be a plain type [VERIFIED: ColdStorageStack.hpp:15-22 — "deliberately free of every sgns-blockstore type"].
- Blank `blockstore` config = nothing constructed = byte-identical behavior (Phase-7 SC2 bar); Phase 11 inherits for every new path (`HasBlock` disposed check, GC thread, retention config).
- Credentials never logged, never at rest in config (Phase-7 D-07 posture); `LogSummary()` extends only with non-secret knobs.
- Testing discipline (`.planning/codebase/TESTING.md`): verification runs inside `build/<Platform>/<Config>`; `addtest()` + `set_tests_properties(... LABELS "Tier1")` registration; `ctest -L Tier1 --no-tests=error` fail-closed lane.
- `workflow.nyquist_validation: false` [VERIFIED: .planning/config.json] — Validation Architecture section omitted per phase instructions. `security_enforcement: true`, ASVS L1, block-on high — Security Domain included below.

## Summary

Phase 11 is the first phase that DELETES local state, on top of three shipped and guard-tested substrates: the Phase-8 spill journal (`LocalBlockStore` — every block born with a journal record in the same WriteBatch as its cold-dir bytes), the Phase-9 cold-read chain (`GraphsyncDAGSyncer` helpers + `ColdReadFallback` hook — Local tier → S3 tier, CID-verified, rehydrate-bytes-only), and the Phase-10 evidence-backed durability gate (`kEvictionDurabilityGate = UploadedDurable`, `GetUploadState` pass-through, `staging_healthy` + `RefreshStagingStats` inhibitor inputs). The eligibility intersection `spilled ∩ age-past-retention ∖ head-reachable ∩ Durable` maps one-to-one onto surfaces that exist today — with exactly ONE hard library gap: **the journal records no timestamp.** The `JournalRecord` codec is exactly two bytes, `[version-byte 0x01][state-byte]` [VERIFIED: LocalBlockStore.cpp:104-141], so D-01's wall-clock age evidence does not exist and must be added additively (§1 recommends a side column family written in `Put`'s existing atomic batch, with backfill-on-first-scan for pre-existing records — under-eviction-safe).

Three structural facts shape the whole design, all verified this session. **(1) The eviction unit spans two RocksDB instances.** The hot CRDT RocksDB holds block bytes (binary `cid.toBytes()` keys), seal markers (TEXT `<cid-string>sealed` keys — datastore_rocksdb.cpp:47-56), set element rows (TEXT `/crdt/s/<key>/<block-cid-string>` — the delta's own rows, keyed by block CID string via `set_->Merge(aDelta, cid_string)`, crdt_datastore.cpp:986-996), tombstones `/crdt/t/...`, current values `/crdt/k/<key>/{v,p}`, and heads — while the library's cold-dir RocksDB holds the cold block bytes + journal. D-16's "one unit" is therefore necessarily two atomic per-store batches with a defined cross-store crash window whose failure direction is under-eviction (safe). The CONTEXT's D-16 parenthetical "(block bytes + resolved marker + disposed marker together)" cannot literally mean the hot-store seal key inside a library batch — the reconciliation is §3.1's ruling (flagged for the planner). **(2) The set-row keys are computable from the block itself.** A delta block carries its elements in its protobuf content, and its element rows are `ElemsPrefix(key).ChildString(blockCidString)` [VERIFIED: crdt_set.cpp:707, :773] — so the hot cleanup removes exactly the block's own rows without ever enumerating the `s` keyspace, and the tombstone/`k`/`h` keyspaces stay untouched by construction. **(3) Reachability is a pure function of the heads set.** Blocks are immutable and content-addressed; the DAG closure from a given head set can never change unless the head set changes. This makes D-08/D-14's "cheap point check against CURRENT heads" exact rather than heuristic: re-verify by comparing the current heads (one `GetHeadList()` call over the in-memory cache, `std::shared_lock`) to the pass-start snapshot — unchanged heads ⇒ the snapshot's reachable-set is still exact; changed heads ⇒ defer/cancel (under-eviction).

On the integration side everything slots into proven patterns: the GC thread is the fourth own-thread lifecycle member (after backup loop, drainer, re-warm executor) with its join slot inside the existing `StopColdStorageManager` ordering; the `retention` config sub-object copies the exactly-proven `durability` parse block (globaldb.cpp:254-289) with one NEW twist — D-04's required age key means the wallet asset must NOT ship a blank `"retention": {}` (that would fail loudly for every wallet); the disposed-marker `HasBlock` extension lands after the Phase-9 `HasLocalCold` check at the three verified call sites (pubsub_broadcaster_ext.cpp:632; crdt_datastore.cpp:706/:1881) with zero new call-site audits; and the epoch watermark (SC5) is computation+storage only. Two Phase-10 review items arrive as entrance decisions: MI-02 (NoRecord-vs-unreadable at the `GetColdUploadState` bridge — eviction must not key off an IO error misread as absence) and MI-01 (prefer journal-derived counts over the status counter).

**Primary recommendation:** Ship the library slice first (spill-timestamp side CF + disposed-CID CF + the D-16 `EvictLocalAndMarkDisposed` single-batch primitive + enumeration surfaces), implement the GC pass as a fresh per-pass reachability walk on a dedicated thread inside `ColdStorageManager` (post-construction dependency injection for heads/DAG access — the manager is constructed before `CrdtDatastore` exists), gate every destructive step behind heads-equality re-checks that fail toward under-eviction, extend `HasBlock` with the disposed-marker point lookup, and prove SC1/SC2/SC3 with a prefix-spy hot datastore + the shipped fault kit in the Tier-1 lane.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Spill-timestamp evidence (D-01) | sgns-blockstore `LocalBlockStore` (additive side CF in `Put`'s batch) | — | The journal/blocks keyspaces are library-owned (v1.0 D-06 backend-owned transitions); SuperGenius writing timestamps into the library's RocksDB would duplicate ownership; genius-tube inherits for free (D-09 rationale) |
| Disposed-CID marker store + bounded trim | `LocalBlockStore` (new CF + record + trim) | GC thread (sweeps) | D-09: single-store atomicity with the eviction batch; the library owns the keyspace, the GC thread may own the sweep cadence (discretion) |
| Destructive eviction batch (D-16 step 1) | `LocalBlockStore` new primitive (ONE WriteBatch: bytes + journal + timestamp + disposed marker) | — | Library-atomic by D-09/D-16; `EvictLocal` (:800-824) is the shape to compose/extend |
| Hot-store cleanup (D-16 step 2: hot bytes + seal + the block's `s` rows) | SuperGenius GC service (via hot RocksDB batch + `DeleteCIDBlock`) | — | Seal/set-row keys are hot-store CRDT-namespace keys; row keys computable from the parsed delta; idempotent by design |
| Retention policy evaluation (eligibility scan) | GC thread (journal enumeration only) | — | SC1: policy evaluation enumerates ONLY the spilled-CID index (library `GetUploadsInState` + timestamp reads); never touches hot CRDT keyspaces |
| Reachability walk + snapshot/re-check | GC thread over `CrdtDatastore::GetHeadList` + `GraphsyncDAGSyncer` reads | — | Heads cache is the verified snapshot source; block reads per-node take `dagMutex_` briefly (never across batches) |
| Durability gate consult | `ColdStorageManager::GetUploadState` (Phase-10 D-09) under `cold_store_mutex_` | MI-02-aware bridge | `kEvictionDurabilityGate` compile-time; NoRecord-vs-unreadable must be distinguished (entrance decision) |
| Staging-health inhibition | `staging_healthy_` + `RefreshStagingStats()` (Phase-10 D-12/D-13) | — | Consulted per GC tick before inhibition; already shipped |
| Re-delivery dedup (`HasBlock` extension) | `GraphsyncDAGSyncer::HasBlock` + gated disposed-marker point lookup | — | D-11: slots after `HasLocalCold` (:680); same freeze-safe RocksDB-point-lookup class; three verified call sites inherit |
| Retention config parse | `GlobalDB::ParseColdStorageConfig` (nested `retention` block) | `LoadCrdtConfig` (GeniusNode.cpp:620-628) + wallet asset | Strict-loop + D-04 required-key + activation interplay (§5) |
| GC observability | `ColdStorageStatus` plain-type extension + bridges | — | Phase-8 D-08 "fields can grow"; ungated-boundary discipline (no library types) |
| Epoch watermark (SC5) | GC thread (compute) → local hot-store record (node-local, non-replicated) | — | Computation + storage only in v1.1; nothing deletion-gated |

## Standard Stack (all in-repo — no new external packages)

### Core
| Component | Version/State | Purpose | Why Standard |
|-----------|---------------|---------|--------------|
| `sgns-blockstore` (submodule, `main` @ `ad07cab` + Phases 6/10 additions) | v1.0+ | Journal state machine, `GetUploadsInState`, `EvictLocal`, `MarkUploadedDurableMany`, `S3AdminClient` facade; gains the timestamp side-CF, disposed-CID CF, and the D-16 destructive primitive | Frozen contract + every surface read this session; single-store atomicity home (D-09) |
| `ColdStorageManager` (SuperGenius, `dev_blockstore`) | Phases 8+10 shipped | Drainer + flush cadence + staging health + `GetUploadState` pass-through; gains the GC thread + status fields | The lifecycle pattern D-06 mirrors; owns both store handles + both mutexes |
| `ColdReadFallback` hook + `ColdReadService` (Phase 9) | shipped | The cold chain GC-03 rides UNCHANGED: `Get` (Local→S3, CID-verified), `HasLocalCold`, `Rehydrate` (bytes-only) | The retrieval proof exists; GC only removes the hot/local copies above it |
| GTest + `addtest()` + `set_tests_properties(LABELS "Tier1")` | existing | Fail-closed hermetic lane | Phase-7/8/9/10 discipline [VERIFIED: test/src/crdt/CMakeLists.txt pattern] |

### Supporting
| Component | Purpose | When to Use |
|-----------|---------|-------------|
| `InMemoryS3Client` (+ `SetFlipBytesForKey`, per-op `S3FaultKind`) | hermetic S3 tier for GC-03 retrieval + re-learn tests | every Tier-1 GC test |
| `InMemoryS3AdminClient` (+ `S3AdminFaultKind`) [VERIFIED: src/InMemoryS3AdminClient.hpp:40-97] | staging-health inhibition tests (GC skips ticks when staging unhealthy) | inhibition + dry-run suites |
| `FaultController`/`FaultKind` on `LocalBlockStore` | Local-tier faults (Unavailable/CorruptData) for gate + batch failure tests | fault kit reuse |
| `CrashPoint::BeforeCommit` seam | crash-window tests (crash mid-grace, crash between library batch and hot cleanup) | D-15/D-16 fault tests |
| LatencyInjecting `S3Client` decorator pattern (test-local subclass) | slow-cold-fetch during walk/eviction (never inline-wait) | optional latency lane |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Side CF for spill timestamps (recommended, §1) | JournalRecord codec v2 (timestamp inside the record) | Codec v2 touches every decode site and requires `TransitionJournal` to carry the timestamp through re-encode; side CF is purely additive, immutable from birth, and untouched by transitions. Both atomic (same `Put` batch). Planner may flip; flagged in Open Questions |
| Manager-owned GC thread (CONTEXT integration point) | Sibling `ColdGcService` (ColdReadService shape) constructed after `CrdtDatastore` | Sibling gets natural constructor DI (manager is built BEFORE `CrdtDatastore` exists); manager-owned matches the CONTEXT's stated integration point and shares mutex/store access. Either satisfies D-06; recommend manager-owned + post-construction attach (§6) |
| Defer-grace-to-next-tick (recommended) | Inline grace sleep on the GC thread | Inline is simpler but a long grace makes stop-responsiveness and cadence awkward; deferred marks (marked_at + due-processing each tick) reuse the cv-wait loop naturally. Discretion |
| Two-GlobalDB in-process libp2p harness for GC-03 graphsync leg | Wrapper-level (`ColdServeDagService` + responder semantics) proof | The two-node harness is the true end-to-end (request → don't-have+re-warm → retry → serve); the wrapper-level proof is cheaper. GC-03's letter ("a graphsync request … resolves") favors the two-node lane for at least one test; Phase-9 deemed node-level optional — planner weighs cost |

**Installation:** none — no new packages, no Package Legitimacy Audit required (no external packages installed this phase).

## 1. The D-01 Timestamp GAP — verified, and the additive shape

### 1.1 What exists today (the gap is real)
The journal record carries state ONLY — verbatim codec [VERIFIED: thirdparty/sgns-blockstore/src/LocalBlockStore.cpp:104-141]:

```cpp
struct JournalRecord
{
    static constexpr char kVersionByte = 0x01;
    static std::string Encode(UploadState state) { ... return std::string{kVersionByte, state_byte}; }
    static std::optional<UploadState> Decode(const rocksdb::Slice& value)
    {
        if (value.size() == 2 && value[0] == kVersionByte) { ... }
        return UploadState::PendingUpload; // conservative fallback
    }
};
```

`Put` writes bytes + (new-block-only) journal record in ONE batch [VERIFIED: LocalBlockStore.cpp:357-366]:
```cpp
rocksdb::WriteBatch batch;
batch.Put(impl_->blocks_, KeySlice(key.value()), ...);
if (!already_present)
{
    batch.Put(impl_->journal_, KeySlice(key.value()),
              JournalRecord::Encode(UploadState::PendingUpload));
}
```

No timestamp anywhere in the journal, blocks, or any library keyspace (grep for timestamp/disposed across the library returns only the Tier-3 e2e state file). **D-01's premise is confirmed: the age evidence must be added.**

### 1.2 Recommended additive shape: a spill-timestamp side column family
- New CF (e.g. `kSpillTimesColumnFamilyName = "spill_times"`), key = the same encoded-CID key as blocks/journal, value = 8-byte little-endian uint64 unix-millis of the Put (birth). Written in `Put`'s EXISTING WriteBatch when `!already_present` — birth-time atomicity for free, zero decode-surface churn, and `TransitionJournal` re-encodes never touch it (timestamps immutable from birth).
- CF creation on EXISTING stores: `Open` already sets `db_options.create_missing_column_families = true` and passes explicit descriptors [VERIFIED: LocalBlockStore.cpp:241, :248-256] — adding a descriptor entry extends old stores in place. (The RocksDB behavior — a descriptor CF absent from an existing DB is created on Open — is the documented purpose of that flag [ASSUMED, near-zero risk; cover with a reopen-an-old-store-dir test in Wave 1; reusable fixture dirs exist under `test-data/local-blockstore*`.)
- **Pre-existing records have no timestamp.** Backfill-on-first-scan: the first GC pass that encounters a Durable record with no side-CF entry writes `now` as its spilled-at (state-preserving, additive) and treats age as measured from backfill. This is the under-eviction-safe direction (old blocks wait one extra retention period at most) and requires no migration tooling.
- Read surface (additive, concrete on `LocalBlockStore` per the journal-transition precedent): `GetSpilledAt(cid) -> result<uint64_t>` (NotFound when absent) and a scan-friendly variant — e.g. widen `GetUploadsInState` with an optional out-struct, or add `GetDurableWithSpillTime()` returning `{Cid, spilled_at_ms}` pairs so the retention scan is ONE pass over the journal CF + point-reads in the side CF (both local RocksDB — microseconds per key).

### 1.3 Why not codec v2
`TransitionJournal` reads then re-encodes the record [VERIFIED: :726-760]; a v2 timestamp must be carried through every re-encode, every decode site (`GetUploadsInState`, `GetPendingUploads`, `GetUploadState`) changes, and the 2-byte conservative-decode contract ("undecodable reads back as PendingUpload") gains legacy-record edge cases. The side CF avoids all of it. Both are defensible; planner ruling (Open Questions).

## 2. Reachability Walk (D-05/D-08) — mechanics, cost, and the exactness lemma

### 2.1 The verified entry point and snapshot source
- `CrdtDatastore::GetHeadList()` [VERIFIED: crdt_datastore.hpp:264 — `outcome::result<CrdtHeads::CRDTListResult> GetHeadList();`] delegates to `CrdtHeads::GetList(topics)` — an in-memory cache read under `std::shared_lock lock( mutex_ )`, returning per-topic head-CID sets plus `max_value` (max height) [VERIFIED: crdt_heads.cpp:259-285]. Calling with an empty topic set yields ALL topics — that is the pass universe.
- Heads are persisted under the heads namespace (cache primed from storage by `PrimeCache`, keys `/<namespace>/<topic>/<cid>` [VERIFIED: crdt_heads.cpp:288-320]) — the walk roots are exactly the heads-cache contents; the GC pins them for free (walk roots ∈ reachable set by construction).

### 2.2 The exactness lemma (why the "cheap point check" is sound)
Blocks are immutable and content-addressed; a block's links never change. Therefore **reachability-from-heads is a pure function of the head set**: if the current heads equal the pass-start snapshot heads, the snapshot's computed reachable-set is still EXACT (no block can have become reachable without a head change). This converts D-08's "per-CID re-verification against CURRENT heads" and D-14's delete-time re-check into a heads-set comparison — one `GetHeadList()` call (shared_lock over the in-memory cache; microseconds) — rather than a per-CID DAG re-walk. Operational rule:
- At mark (per candidate/batch) and at delete (per destructive batch): re-read `GetHeadList()`; if the head multiset differs from the snapshot → skip/cancel that candidate this pass (under-eviction direction). Log one rate-limited line naming the pass as aborted-on-heads-change.
- Heads only ever change through `Add`/`Replace` on the CRDT merge path [VERIFIED: crdt_heads.cpp Add/Replace — cache_ mutations under `mutex_`], i.e., a changed-heads observation always means new causal history may exist.

### 2.3 Walk mechanics (batching, threading, locks)
- Shape: iterative work-queue over `getLinks()` per node — the codebase's own precedent is `TraverseCIDsLinks` (graphsync_dagsyncer.cpp:921-1043, `std::deque` work queue, visited set). **DO NOT reuse its skip semantics**: it skips `isResolved` roots/children (:950-955, :1009-1012) — resolution marks processing state, NOT reachability; skipping resolved children would UNDER-count reachability → wrongful eviction (the one unsafe direction). The GC walk traverses every link unconditionally.
- Reads: via `GetNodeWithoutRequest` (public on `DAGSyncer`), which is hot-first then cold-chain (Phase-9). Per-node reads take `dagMutex_` only inside `GetNodeFromMerkleDAG` (short critical sections — never held across batches; the agent-discretion item is satisfied by this per-node granularity: process N nodes, release, check stop-flag, next batch).
- Cold-chain side effect during walk: if the walk meets a CID already evicted (only possible after a prior wrongful eviction or a relink onto old history), `FetchNodeFromColdStorage` rehydrates it (S3 fetch → hot + fresh journal → re-drain). Self-healing and safe (D-10's re-learn); rare by construction. Log it distinctly (it is also the GC-03 property exercising itself live).
- Cost model [ASSUMED — back-of-envelope]: visited set ≈ 50-100 bytes/CID in an `unordered_set` → 1M-block history ≈ 50-100 MB resident during a pass, plus one hot-store read per block. O(history) accepted by D-05; passes infrequent; recommend documenting the scaling note in the SC1 evidence header. No bloom filters, no persisted reachable-sets (both rejected by D-05).
- Batching (discretion): recommend batch = 256-1024 nodes between stop-flag checks; cursor is in-pass only (the visited set + work queue ARE the cursor; a pass aborted on heads-change simply restarts fresh next tick — D-05 freshness-as-correctness).

### 2.4 What reachability must include (pinning)
- All heads (walk roots — pinned by construction).
- SC1's protected namespaces: heads (covered), **genesis**, **current-epoch pointers**. In this codebase there is no CRDT-genesis pinned-root registry today [VERIFIED: no such concept in crdt/ — the genesis references in-tree are blockchain-side]; the practical v1.1 pin set = heads + the SC5 epoch-record keys (new, written by the GC itself — pin by prefix) + any operator-pinned roots if the planner adds the hook (discretion: a `retention.pinned_cids`-style list was NOT decided; keep v1.1 minimal — heads + epoch-record prefix, documented).
- In-flight work is protected by TWO independent gates without extra code: a block being processed right now was written seconds ago (age ≪ retention) and its journal state is Pending/Accepted (not Durable) — both exclude eligibility.

## 3. Two-Phase Eviction + Unit Atomicity (GC-02 / D-13..D-16)

### 3.1 The D-16 reconciliation (planner must rule — flagged)
The eviction unit per GC-02/ROADMAP SC2 = {block bytes, resolved marker, set rows}. Verified locations:
- **Hot block bytes**: binary `cid.toBytes()` keys in the hot RocksDB (`RocksdbDatastore::set/get/remove`, datastore_rocksdb.cpp:50-56/:76-80 — created over `m_datastore->getDB()`, i.e. the SAME RocksDB as the CRDT namespaces [VERIFIED: globaldb.cpp Init, `IpfsRocksDb::create( m_datastore->getDB() )`]).
- **Resolved marker**: a TEXT key in the hot store — verbatim [VERIFIED: datastore_rocksdb.cpp:47-56]: `cid_string += "sealed";` … `rocksdb_->put( key_buf, … )`. NOTE: `remove(key)` removes only the binary CID key — **no existing API removes a seal marker**; the hot cleanup needs an additive unseal/remove path (direct hot-store delete of the `<cid-string>sealed` key via the `storage::rocksdb` face, or an added `IpfsDatastore` method).
- **Set rows**: TEXT keys `/crdt/s/<key>/<block-cid-string>` — the delta block's OWN element rows; the ID is the block CID string [VERIFIED: crdt_datastore.cpp:986-996 `set_->Merge( aDelta, cid_string )`; crdt_set.cpp:707 `ElemsPrefix( key ).ChildString( aID )`, :773 `TombsPrefix( key ).ChildString( tomb.id() )`]. The block's protobuf content carries its element keys — parse the delta (from the cold-dir copy BEFORE deleting it) to compute the exact row keys; no `s`-keyspace enumeration ever runs.

The CONTEXT D-16 wording "(block bytes + resolved marker + disposed marker together)" in a LIBRARY batch cannot include the hot-store seal key (different RocksDB). The coherent reading, consistent with D-16's own crash analysis ("orphaned HOT bytes … hot-store set-row removal FOLLOWS"):
1. **Library batch (ONE WriteBatch, the destructive step):** delete cold-dir block bytes + delete journal record + delete spill-timestamp entry + PUT disposed-CID marker — the additive composition of `EvictLocal` [VERIFIED shape: LocalBlockStore.cpp:800-824] with the marker write.
2. **Hot cleanup (idempotent, follows):** delete hot block bytes + delete `<cid>sealed` key + delete the block's `/crdt/s/<key>/<cid>` rows + `DeleteCIDBlock` LRU invalidation — all in ONE hot-store `BufferBatch` commit (same RocksDB ⇒ per-store atomic), computable from the parsed delta + CID string.
Crash between 1 and 2 → orphaned hot bytes "still count as present"; the next pass re-evicts them via disposed-marker enumeration + hot-presence point check (see §4.2). **The planner should write this reconciliation into PLAN 11-02's task notes and the SC2 guard-test wording** (SC2's "one unit" = the policy unit with two idempotent halves and a safe-direction crash window).

### 3.2 Phase mechanics (mark → grace → delete)
- **Mark (in-memory, D-15):** GC-thread set `{cid → marked_at, parsed-row-keys, size}` surfaced as an evicting count via atomics in the status getter. Visible to "readers and drain snapshots" as STATUS (the SC2 letter's visibility) — hot bytes still present during grace, so reads/drains are behaviorally unchanged; the disposed marker does not exist yet, so `HasBlock` still answers via hot bytes. Zero behavioral gates needed during grace — the simplicity is the point of D-15.
- **Grace (D-13):** knob with documented default (recommend 60000 ms). Mechanics discretion — recommend defer-to-next-tick (marks carry `marked_at`; each tick processes due marks first, then new marks) over an inline sleep: stop-responsive, cadence-consistent.
- **Delete-time re-check (D-14):** heads-equality check (§2.2) immediately before the destructive batch. Changed → cancel: clear mark, keep bytes, CID returns to normal (next pass re-evaluates). Dry-run (D-03): the delete step is suppressed after the SAME evaluation — logs + per-pass metrics identical, one line says dry-run.
- **Crash mid-grace (D-15):** marks vanish with the process; nothing was deleted; next pass re-walks. No recovery machinery — test it (§8).

### 3.3 Re-learn after eviction (reversibility of the whole design)
A trimmed marker or a re-delivered/re-read evicted CID re-enters via the Phase-9 chain: read → hot miss → Local miss (cold-dir gone) → S3 `Get` (CID-verified) → `Rehydrate` = decorator `set()` = fresh hot bytes + fresh journal record → drainer re-puts with createOnly (alreadyPresent converges, no overwrite; Phase-9 §2.1 verified) → fresh eligibility clock. **Rehydrate stays bytes-only** [VERIFIED: cold_read_fallback.hpp:116-124 — "NO resolved/seal marker this phase"]. The seal-restoration half of the eviction unit (09-RESEARCH §2.4: restore the marker "from eviction-time knowledge") is optional Phase-11 scope: if the disposed marker records `was_sealed`, the rehydrate path for disposed CIDs MAY restore the seal honestly (the block was fully processed pre-eviction). Recommend recording `was_sealed` in the marker NOW (cheap, additive) and ruling restoration explicitly — restoring is only honest for markers that say so; never seal a crash-window block.

## 4. Disposed-CID Markers + `HasBlock` (D-09..D-12)

### 4.1 Library surface (additive, concrete on LocalBlockStore)
- New CF (e.g. `kDisposedColumnFamilyName = "disposed_cids"`), key = encoded CID, value = a small record: `{disposed_at_unix_ms (u64), reclaimed_bytes (u64), original_size (u64), reason (enum/byte), was_sealed (bool)}` (content is discretion; these fields serve SC5 metrics + §3.3).
- Additive methods: `MarkDisposed`-batch composed in the D-16 primitive (§3.1); `IsDisposed(cid) -> result<bool>` (point lookup); `GetDisposed()` enumeration (trim sweep + orphaned-hot-bytes re-scan); trim = delete-oldest until under count cap AND drop age-past-max-age (D-10: whichever trims first). Bound defaults (discretion): recommend count cap 100000, max age 30 days — both documented constants in the manager/library header (public for test citation, the `kEvictionDurabilityGate` precedent).
- **Do NOT add pure virtuals to `BlockStore`/`BlockStoreTooling`** — v1.0 frozen-contract discipline (the manager holds the concrete type; Phase-10 `GetUploadsInState` precedent).

### 4.2 The orphaned-hot-bytes re-scan (D-16's "next pass re-evicts them")
After the library batch commits, the journal record is gone and a disposed marker exists — the ordinary eligibility scan (journal enumeration) no longer sees the CID. The pass therefore needs a first step: enumerate `GetDisposed()`; for each, point-check hot presence (`GetNodeFromMerkleDAG`/hot `contains`); present → run the idempotent hot cleanup (§3.1 step 2). This is also the crash-between-halves recovery path and a per-pass metric (leftover count). Marker hits with no hot bytes are just dedup state (until trimmed).

### 4.3 `HasBlock` extension (D-11) + the D-12 split semantics
Current verified shape (graphsync_dagsyncer.cpp:663-685): hot → LRU → `HasLocalCold`. The disposed-marker lookup slots AFTER `HasLocalCold` — same RocksDB point-lookup class, freeze-safe, gated on cold storage enabled. Callers inherit with zero new audits at the three verified sites: `pubsub_broadcaster_ext.cpp:632` (`AddMultiCIDInfo` — route dedup), `crdt_datastore.cpp:706` (head processing), `:1881` (job status). Hook surface: add `HasDisposed(cid)` to the gated cold-read service / hook chain (ungated interface extension, no library types).
- **Re-delivery dedup (D-11/D-12):** marker hit ⇒ `HasBlock` true ⇒ pubsub re-delivery drops at the existing call sites ("already integrated") — no fetch storm, no route spam.
- **Split semantics (D-12):** reads NEVER see NotFound for a disposed CID — the local-read leg (`GetNodeWithoutRequest`) and the responder cold-serve chain (`getNode` pre-peer leg → `ColdServeDagService` don't-have + re-warm) ride the Phase-9 cold chain unchanged; a disposed-but-hot-missing CID resolves from Local(cold-dir, if re-learned)→S3, CID-verified, re-cached. NotFound exists ONLY as the pubsub/dedup concept. GC-03's E2E states both halves.

## 5. Config Surface (D-02/D-03/D-04/D-07/D-13)

### 5.1 The pattern to inherit — exactly proven twice
[VERIFIED: globaldb.cpp:119-407 — `ParseColdStorageConfig`] The `durability` nested block (:254-289) is the literal template for `retention`: present-but-not-object ⇒ loud (`'blockstore.retention' must be an object`); strict single-member sub-loop with unknown-key loud naming `blockstore.retention.<key>`; uint-only for numeric knobs; 0-means-default normalization POST-parse with cross-field rules; the whole-file/absent-section lenient gates (a/b) and the file-intent activation gate (e) unchanged. `LogSummary()` (globaldb.cpp:100-117) gains the retention knobs (non-secret). `LoadCrdtConfig` [VERIFIED: GeniusNode.cpp:557-640] throws on parse error and logs one line only when enabled — unchanged.

### 5.2 Proposed `blockstore.retention` sub-object (names are discretion; recommended)
| Key | Type | Rule | Recommended default |
|-----|------|------|---------------------|
| `retention_age_ms` (or `age_ms`) | uint | **REQUIRED (D-04)** — present-subobject-without-age ⇒ loud startup failure | none (must be typed) |
| `dry_run` | bool | optional, default false (D-03) | false |
| `gc_interval_ms` | uint | optional, 0 = default (D-07) | 600000 (10 min) |
| `grace_ms` | uint | optional, 0 = default (D-13) | 60000 |

Cross-field rule (mirrors warn<critical): `grace_ms < gc_interval_ms` recommended (a mark must come due within a reasonable cadence) — planner taste; loudness of unknown keys inherits Phase-7 strictness verbatim.

### 5.3 Activation interplay (D-02 + the Phase-7 gate (e))
GC requires spill + durability, so it can only run when cold storage is ENABLED — which today requires endpoint/bucket/credentials in the FILE [VERIFIED: gate (e), globaldb.cpp:373-380: optional-fields-only section ⇒ disabled REGARDLESS of env]. Therefore: `retention` present while `blockstore` is otherwise blank ⇒ cold storage disabled ⇒ GC inert (log one WARN when retention is present-but-inert — the silent-disable pitfall). `retention`-only sections never activate anything (Phase-7 (e) inheritance). **Wallet asset consequence (planner must rule):** D-04 makes `"retention": {}` a LOUD failure (present, no age) — the asset `GeniusWallet/assets/crdt_config.json` [VERIFIED current: `{"backup_enabled":…, "blockstore": {"backpressure": {}, "durability": {}}}`] must NOT gain a blank `retention` sub-object. Recommended parity: omit the key entirely + document the example in operator docs; shipping an example-with-age would arm eviction on wallets. This inverts the Phase-7/10 blank-form precedent BY DESIGN (a destructive feature earns no blank form) — surface at plan review.

## 6. GC Thread, Lifecycle, and Dependency Injection (D-06)

### 6.1 The construction-order fact (drives the injection shape)
Verified `GlobalDB::Init` order: hot RocksDB open → `IpfsRocksDb::create(m_datastore->getDB())` + `RocksdbDatastore` → cold stack (`OpenColdStorageStack` — decorator, manager, cold-read service; `StartColdReadService()` immediately) → `GraphsyncDAGSyncer` (with hook) → `PubSubBroadcasterExt` → **`m_crdtDatastore` LAST**. The manager (the GC thread's home per the CONTEXT integration point) is constructed BEFORE `CrdtDatastore` exists — the GC's heads/walk dependencies (`GetHeadList`, DAG reads, hot store, hot-cleanup batch) cannot be constructor parameters of the manager. Recommended shape: a post-construction attach on the manager (e.g. `AttachGcDependencies(crdt_datastore, dag_syncer)` or an ungated `ColdGcHooks` interface implemented in a gated TU), called in `Init` right after `m_crdtDatastore` is created, BEFORE `GlobalDB::Start()` starts the GC thread (drainer starts in `Start()` → `StartColdStorageManager()` — the same slot starts GC; `cold_manager_` reaching `Start()` without attached dependencies when retention is configured is a programmer error — assert/log-fail-closed).

### 6.2 Lifecycle + shutdown slot
- Own `std::thread` + cv poll loop (interval knob), stop-flag checks between walk batches — the drainer's exact shape [VERIFIED: ColdStorageManager.hpp:26-45 lifecycle docs; Start/Stop at :47-83 pattern]. Never `io_`, never the pubsub asio context.
- Per-tick order: (0) stop check → (1) staging-health gate: `RefreshStagingStats()` (D-13) then read `staging_healthy_`; unhealthy ⇒ skip tick with a rate-limited distinguishable line → (2) orphaned-hot-bytes re-scan (§4.2) → (3) heads snapshot + fresh walk (§2) → (4) eligibility: journal Durable-set ∩ age>retention (§1 reads) ∖ reachable ∖ pinned → (5) mark due-and-passing candidates (heads-equality re-check per batch) → (6) process due marks from previous ticks: heads-equality re-check → library batch → hot cleanup → metrics → (7) marker trim sweep (discretion: GC thread owns it) → (8) epoch-watermark record write (SC5).
- Shutdown: extend `ColdStorageManager::Stop()` — after the drainer join (and its D-04 final flush), stop the GC thread (flag → notify → bounded grace → join; marks vanish per D-15; a delete batch mid-flight completes or the next pass re-runs §4.2 — both safe). Ordering stays inside the existing `StopColdStorageManager()` slot [VERIFIED: globaldb.cpp:491-495 — backup loop → manager → cold-read service → lifecycle-mutex teardown]. The GC thread touches the hot store + library only; it must be joined before `m_datastore.reset()` — satisfied by the existing slot.
- **MI-02 entrance decision** [VERIFIED: 10-REVIEW-DISPOSITION.md:23 — "GetColdUploadState maps transient RocksDB errors to NoRecord, conflating absent with unreadable … Carry to Phase-11 planner as an entrance decision (distinguish Unreadable from NoRecord at the bridge)"]: the eviction gate must not treat an IO-error-misread-as-NoRecord as "not Durable ⇒ evict-anyway" — under D-10's compile-time gate a NoRecord CID is NOT eligible (only Durable is), so the safe direction already holds for eligibility; the danger is the INVERSE use (treating NoRecord as proof-of-anything). Rule: gate consult = state must be EXACTLY `Durable`; anything else (NoRecord, Pending, Accepted, unreadable) ⇒ not eligible. Recommend widening the ungated `ColdUploadState` with an `Unreadable` value (additive enum) at the bridge in Wave 1.
- **MI-01** [VERIFIED: :22 — durable-count inflation when records vanish mid-cycle; "prefer journal-derived counts there"]: the GC enumerates the journal directly (`GetUploadsInState`) and must NOT consume `durable_upload_count_` for eligibility decisions.

## 7. Observability (status getter, metrics, logging)

`ColdStorageStatus` extends additively, PLAIN TYPES ONLY (Pitfall-5 discipline) [VERIFIED: ColdStorageStack.hpp:45-77 current shape]:
```cpp
// v1.1 Phase 11 additions (all defaulted — Phase-8 D-08 "fields can grow")
bool     gc_enabled{ false };          ///< retention configured (actor constructed)
bool     gc_dry_run{ false };          ///< observe-only posture (D-03)
bool     gc_inhibited_staging{ false };/////< last tick skipped on staging health
size_t   gc_evicting_count{ 0 };       ///< in-memory marks held (D-15)
uint64_t gc_last_pass_unix_ms{ 0 };
size_t   gc_last_pass_candidates{ 0 };
size_t   gc_last_pass_reclaimed_count{ 0 };
uint64_t gc_last_pass_reclaimed_bytes{ 0 };
size_t   gc_disposed_marker_count{ 0 };
```
Backed by GC-thread atomics (the drainer's no-scan getter discipline). Per-pass one-line summary (candidates/marks/deletes/reclaimed/dry-run/leftovers) + rate-limited event lines for mark/delete/cancel/relearn/trim. Log-wording constraint: GC events distinguishable from drain/flush/peer failures (prefix vocabulary, e.g. `gc:` / `cold read:` / `drain:` / `flush:`), never logging CIDs at info on hot paths, never credentials.

## 8. Testing Design (SC1–SC5, GC-03, TEST-03)

### 8.1 Tier-1 guard tests (SC1/SC2) — the fail-closed lane
Registration: the exact Phase-8/9/10 pattern — `addtest(...)` under `if(SGNS_COLD_STORAGE)`, link `sgns-blockstore::sgns-blockstore crdt_globaldb`, relative include dir for the non-installed fakes, `set_tests_properties(... LABELS "Tier1")` [VERIFIED: test/src/crdt/CMakeLists.txt:98-113 precedent].
- **SC1 keyspace guard (the "provably never" test):** wrap the hot `storage::rocksdb` face in a counting spy (test-local decorator tallying reads/writes/deletes by key prefix) injected as the GC's hot-store dependency; run a full pass (mark+delete, real walk over a seeded DAG); assert ZERO operations under `/crdt/t/`, `/crdt/h/`, `/crdt/k/` and under any prefix except {binary CID keys, `<cid>sealed` keys, the block's own `/crdt/s/<key>/<cid>` rows, the epoch-record prefix}; assert the eligibility scan enumerated ONLY library surfaces (spy the library side via the fake/enum counts or assert via the spy that no `s`-keyspace QUERY ran before any delete). Structural companion: the GC code path has no `QueryElements`/tombs accessor calls (grep-guard in review).
- **SC1 eligibility-matrix unit tests:** age-gate (young Durable block not evicted), reachability-gate (head-reachable old block not evicted; newly-head-referenced candidate cancelled at mark/delete re-check — the heads-change race test), durability-gate (Accepted ≠ eligible; `kEvictionDurabilityGate` cited), pin tests (heads never eligible; epoch-record prefix never touched).
- **SC2 unit-atomicity + fault tests:** happy path (library batch + hot cleanup leave: hot bytes gone, seal gone, the block's s-rows gone, tombstones/k/v/h INTACT, disposed marker present, `HasBlock` = disposed-true via D-11); crash mid-grace (kill manager between mark and delete — next pass re-walks, nothing deleted); crash between halves (arm a test seam between library batch and hot cleanup — next pass's §4.2 re-scan completes the cleanup); delete-time re-check cancel (mutate heads between mark and delete ⇒ bytes kept); re-delivery storm (publish the disposed CID via the fake broadcaster path ⇒ dropped at `HasBlock`, zero S3 gets); marker trim (cap + age ⇒ trimmed; re-delivered trimmed CID re-learns through the chain — re-journal observed).
- **SC2 never-purged guard:** after N passes with aggressive retention over a store containing tombstones, byte-compare the `/crdt/t/`, `/crdt/k/`, `/crdt/h/` keyspaces before/after — identical (the spy covers per-op; this is the end-state proof).
- **SC5:** epoch record computed+stored (per-topic min-head-height floor + max height + computed-at; from `GetList`'s per-topic heights — the milestone SUMMARY's "min-head-height floor, computation only" shape); dry-run: identical evidence surface, zero deletes, metrics populated.

### 8.2 GC-03 retrievability (Tier-1, hermetic)
- **Local-read leg:** evict a CID (real pass or driven marks) → `GetNodeWithoutRequest` → resolves via S3 fake (`InMemoryS3Client`), CID-verified (`SetFlipBytesForKey` proves verification on the negative side), rehydrated hot; disposed marker still present (re-learn did not clear it — dedup continues until trim).
- **Graphsync leg:** extend the Phase-9 responder harness (`ColdServeDagService` + re-warm executor): request an evicted CID → immediate don't-have → re-warm pulls from the S3 fake → retry serves CID-verified. One true two-GlobalDB in-process libp2p test (`pubsub_graphsync_test.cpp` harness shape) with a SHARED S3 fake as the second node's cold tier is the strongest form — the planner weighs its link cost per the Phase-9 precedent (wrapper-level Tier-1 mandatory, node-level recommended once).
- Both legs assert the D-12 split: no read path ever surfaces NotFound for the disposed CID.

### 8.3 TEST-03 live tier (dev-gated, never CI)
Follow the v1.0 Tier-2/3 contract exactly [VERIFIED: thirdparty/sgns-blockstore/docs/testing-tiers.md — env-gated opt-in with loud labelled `[SGNS_BLOCKSTORE][…]` skips; labels carry inspectability; `s3d_roundtrip_e2e` two-run fresh-process precedent; evidence committed under docs/evidence/s3d-spike/]:
- **Live s3d spill → GC → retrieve E2E:** one (or two-run) fresh-process scenario — node with cold storage + retention (age small, dry-run off) writes blocks → verify drain + flush + Durable (stats captures) → GC pass (pass metrics + reclaimed bytes captured) → local read + graphsync request for an evicted CID resolves CID-verified. Evidence artifacts: config used, stats/pass/log captures, retrieved-block digest — committed under an evidence dir (recommend `thirdparty/sgns-blockstore/docs/evidence/gc-e2e/` or a SuperGenius-side runbook sibling; discretion listed in CONTEXT) + a README runbook citing the env gates (`SGNS_BLOCKSTORE_TEST_S3D_*` precedent).
- **MinIO-binary opt-in roundtrip:** the Tier-2 `SGNS_BLOCKSTORE_TEST_MINIO_BIN` shape with `W:\gnus\minio-community.exe` (RELEASE.2025-04-22, verified present) — GC over a MinIO-backed cold tier roundtrip (spill → durable via MinIO (admin flush path differs — the fake admin covers semantics hermetically; the live MinIO leg exercises the S3 tier only) → evict → retrieve).
- Never registered in the CI lane; labels `Tier2`/`Tier3` only; human checkpoint wave (Wave 4) per the roadmap.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Destructive local removal | direct RocksDB deletes in SuperGenius | the library's batch primitive (EvictLocal composed with the marker — §3.1) | keyspace ownership (v1.0 D-06); single-store atomicity (D-09); genius-tube shares it |
| Reachability computation | bloom filters / persisted mark sets | fresh full walk per pass (D-05) + heads-equality exactness (§2.2) | deletion must rest on exact evidence; a stale mark is the wrongful-eviction hazard |
| Age evidence | file mtimes / in-memory maps | spill-timestamp side CF in the library (§1) | crash-derivable, birth-atomic, library-owned |
| Re-delivery dedup | per-call-site checks | the extended `HasBlock` (D-11) | three verified call sites inherit; future call sites can't forget |
| Eviction eligibility counting | the status counters | journal enumeration (`GetUploadsInState`) | MI-01: counters are advisory, journal is truth |
| Thread lifecycle | asio timers / io_ posts | own std::thread + cv + bounded Stop (drainer pattern) | Phase-8/9/10 thrice-proven; never the pubsub context |
| Fault injection | ad-hoc flags | `InMemoryS3Client`/`InMemoryS3AdminClient`/`FaultKind`/`CrashPoint` kit | deterministic crash-window + fault tests |
| Hot keyspace proof | log scraping | prefix-spy datastore (test-local decorator) | the SC1 "provably never" needs an observed boundary, not assertions |

**Key insight:** every destructive primitive composes from shipped, guard-tested library surfaces (`EvictLocal`'s batch shape, `GetUploadsInState`, `GetUploadState`, `kEvictionDurabilityGate`, the Phase-9 chain). The genuinely new artifacts are: one timestamp source, one marker keyspace + record, one composite destructive primitive, the walk + policy loop on a thread, config + status + tests.

## Runtime State Inventory

> Phase 11 creates/deletes persisted state — inventory of what exists at runtime that the phase must respect:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data (library cold dirs) | Existing `LocalBlockStore` RocksDB dirs (production + `test-data/local-blockstore*`, `cold-storage-*` fixtures) — 2 CFs today (blocks, upload_journal), NO timestamps | Code edit: Open() descriptors gain new CFs (auto-created via `create_missing_column_families=true`); NO data migration — missing timestamps backfill lazily (§1.2) |
| Stored data (hot CRDT RocksDB) | Block bytes + `/crdt/s|t|k|h` namespaces + `<cid>sealed` keys in ONE store | Deletion code must touch only the evicted block's own keys; tombstones/k/h never written |
| Live service config | `GeniusWallet/assets/crdt_config.json` ships blank sub-objects today | MUST NOT gain blank `retention` (D-04 makes it a loud failure) — omit + document (§5.3) |
| OS-registered state | None — no scheduled tasks/services embedded | None — verified by design (threads only, joined at shutdown) |
| Secrets/env vars | `SGNS_BLOCKSTORE_S3_*` (+ Phase-10 `_ADMIN_PASSWORD`) | No new env vars required; never logged |
| Build artifacts | SuperGenius Tier-1 lane links the library via superbuild install | Additive sources/tests only; wrapper-vcxproj header-staleness hazard applies IF installed library headers change (new disposed-marker API on existing installed header — run the deployed-header hash check) |

## Common Pitfalls

### Pitfall 1: Reusing `TraverseCIDsLinks` semantics for the walk
**What goes wrong:** its `isResolved` skips (root :950-955, child :1009-1012) under-count reachability → resolved-but-reachable history looks unreachable → wrongful eviction (the one unsafe direction).
**Why:** resolution marks processing state, not reachability; the two coincide only for fully-processed recent deltas.
**Avoid:** GC walk traverses every link unconditionally (§2.3); guard test seeds a resolved old subtree still linked from heads and asserts non-eligibility.
**Warning signs:** eligibility sets that correlate with seal markers.

### Pitfall 2: Misreading "cheap point check" as per-CID re-walk (or skipping it)
**What goes wrong:** a literal per-CID reachability test is O(history) per candidate (unworkable — designs start "optimizing" it away); skipping the re-check re-opens the mid-walk race D-08 exists to kill.
**Why:** the exactness lemma (§2.2) is what makes the check both cheap AND exact — heads-equality ⇔ snapshot reachability still valid.
**Avoid:** encode the lemma in the plan + tests (heads-change between walk and mark ⇒ candidate skipped; between mark and delete ⇒ cancelled).
**Warning signs:** any plan text scheduling "partial re-walks for verification".

### Pitfall 3: The D-16 wording trap — trying to put the seal key in the library batch
**What goes wrong:** block bytes/seal/set-rows span TWO RocksDB instances; a "single batch" reading invites either hot keys written via the library (ownership violation) or the marker hoisted hot (D-09 violation).
**Avoid:** §3.1's two idempotent halves + safe crash window; planner writes the reconciliation explicitly.
**Warning signs:** any WriteBatch mixing hot-store and library keys.

### Pitfall 4: Eligibility keyed off NoRecord (MI-02)
**What goes wrong:** an IO error at the `GetColdUploadState` bridge reads as NoRecord; code that treats "no record" as "safe to evict" (e.g., orphan cleanup misapplied) evicts on unreadable evidence.
**Avoid:** gate = state exactly `Durable`; add `Unreadable` to the ungated bridge enum (§6.2).
**Warning signs:** `case NoRecord:` branches leading to destructive calls.

### Pitfall 5: Wallet asset arming eviction
**What goes wrong:** parity instinct adds `"retention": {}` to `crdt_config.json` → D-04 makes every wallet startup fail loudly (or worse, an example-with-age silently arms GC).
**Avoid:** omit the key; document in operator docs (§5.3).
**Warning signs:** any wallet-asset diff containing `retention`.

### Pitfall 6: GC work on `io_` or holding `dagMutex_` across a batch
**What goes wrong:** the pubsub host is single-threaded (Phase-9 binding fact — gossip_pubsub.cpp:518, globaldb.cpp:637-643); any GC wait/deadline inline freezes the node; a held `dagMutex_` stalls publishes.
**Avoid:** own thread; per-node lock granularity (§2.3); staging-health consult via the shipped `RefreshStagingStats()`.
**Warning signs:** GC code posting to asio contexts or holding mutexes across batch boundaries.

### Pitfall 7: Walk reading evicted blocks and re-learning them en masse
**What goes wrong:** after bulk eviction + head relink onto old history, the walk hits many holes → each triggers an S3 fetch + rehydrate (self-healing but expensive; looks like a fetch storm).
**Avoid:** expected and safe (§2.3); rate-limit the distinct log line; metrics count relearns-during-walk; if measurements show storms, re-warm coalescing already exists (Phase-9 D-07 map).
**Warning signs:** `gc: relearned during walk` lines dominating pass logs.

### Pitfall 8: Disposed markers unbounded / never trimmed
**What goes wrong:** markers accumulate forever (re-delivery dedup memory + disk); or trimming breaks dedup assumptions.
**Avoid:** D-10 dual bound (count + age); trimmed CID re-arrives ⇒ re-learn (safe — remote copy exists); trim is a metrics-visible step.
**Warning signs:** `gc_disposed_marker_count` monotonic across weeks.

### Pitfall 9: Library types crossing the ungated boundary
**What goes wrong:** disposed-record structs or `UploadState` in `ColdStorageStack.hpp` — OFF builds break (Phase-7 bar).
**Avoid:** plain-type status fields (§7); ungated `HasDisposed` on the hook interface (no library types).
**Warning signs:** any `#include <sgns-blockstore/...>` in ungated headers' diffs.

### Pitfall 10: Sealing on re-learn without eviction-time knowledge
**What goes wrong:** blanket seal-on-rehydrate seals crash-window unprocessed blocks (Phase-9 §2.4 ruling) — their deltas never merge.
**Avoid:** rehydrate stays bytes-only; seal restoration only if the disposed marker records `was_sealed` and only for marker hits (§3.3); planner rules explicitly.
**Warning signs:** any `seal(` call on the rehydrate path not gated on a marker record.

## Code Examples

### The D-16 destructive primitive (library — shape)
```cpp
// Composes the verified EvictLocal batch (LocalBlockStore.cpp:800-824) with
// the marker + timestamp deletions — ONE sync WriteBatch:
result<void, BlockStatus> LocalBlockStore::EvictLocalAndMarkDisposed(
    const Cid& cid, const DisposedRecord& record)
{
    ... // ValidateCidHash + FaultGate + MakeKey (the EvictLocal preamble)
    rocksdb::WriteBatch batch;
    batch.Delete(impl_->blocks_,   KeySlice(key.value()));  // cold-dir bytes
    batch.Delete(impl_->journal_,  KeySlice(key.value()));  // journal record
    batch.Delete(impl_->spill_times_, KeySlice(key.value())); // age evidence
    batch.Put(impl_->disposed_,  KeySlice(key.value()),
              DisposedRecord::Encode(record));              // terminal marker
    const auto committed = impl_->db_->Write(impl_->wo_, &batch);
    ...
}
```

### The pass loop (manager — shape, gated TU)
```cpp
// Runs on the GC thread ONLY (D-06). Never io_, never the pubsub context.
void ColdStorageManager::GcPassOnce()
{
    RefreshStagingStats();                       // Phase-10 D-13 (admin_mutex_-serialized)
    if ( !staging_healthy_.load() ) { RecordGcInhibitedStaging(); return; }
    FinishOrphanedHotCleanups();                 // §4.2: disposed markers ∩ hot-present
    const auto snapshot = heads_->GetHeadList(); // pass universe (D-08)
    auto reachable     = WalkReachable(snapshot);// §2: fresh full walk, no resolved-skips
    for ( auto& [cid, spilled_at, size] : EnumerateDurableWithSpillTime() ) // §1 reads
    {
        if ( NowMs() - spilled_at < retention_.age_ms )      continue; // D-01
        if ( reachable.count( cid ) )                        continue; // D-05/D-08
        if ( IsPinned( cid ) )                                continue; // SC1
        if ( !HeadsUnchanged( snapshot ) )   { AbortPassOnHeadsChange(); return; } // §2.2
        MarkEvicting( cid, size );                          // in-memory (D-15)
    }
    ProcessDueMarks( snapshot );  // grace elapsed -> re-check heads -> library batch
                                 // -> idempotent hot cleanup -> metrics (D-14/D-16)
    TrimDisposedMarkers();       // D-10 dual bound
    WriteEpochWatermark( snapshot ); // SC5: computation + storage ONLY
}
```

### The `HasBlock` tail (D-11 — after the verified Phase-9 check at :680)
```cpp
// graphsync_dagsyncer.cpp HasBlock — after HasLocalCold misses:
// D-11 (v1.1 Phase 11): fourth term, disposed-marker point lookup — the
// same freeze-safe RocksDB point-lookup class. Marker hit = "already
// integrated": re-delivery drops at the existing call sites; READS never
// see this term (they ride the cold chain — D-12 split semantics).
if ( cold_read_hook_ != nullptr && cold_read_hook_->HasDisposed( cid ) )
{
    return true;
}
```

### Config matrix extension (the durability block is the template)
```cpp
// Verified pattern: cold_storage_config_gate_test.cpp Backpressure*/Durability*
TEST( ColdStorageConfigGate, RetentionAbsentSubObjectDisablesGc )          // D-02
TEST( ColdStorageConfigGate, RetentionWithoutAgeFails )                    // D-04 loud
TEST( ColdStorageConfigGate, RetentionUnknownKeyFails )                    // Phase-7 strict
TEST( ColdStorageConfigGate, RetentionDryRunAndKnobsParseAndNormalize )    // D-03/D-07/D-13
TEST( ColdStorageConfigGate, RetentionInertWhenBlockstoreBlank )           // §5.3 interplay + WARN
```

## State of the Art (in-codebase drift watch)

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `EvictLocal` unconditional, caller-owns-policy (v1.0 warning names "this milestone's durability-gated eviction") | Phase-11 composes it behind `kEvictionDurabilityGate` + non-reachability + age | this phase | the v1.0 `@warning` is finally honored by a caller |
| `HasBlock` = hot ∨ LRU ∨ cold-dir (Phase-9) | + disposed-marker term (D-11) | this phase | meaning extends to "held OR cold-dir OR known-disposed"; reads unaffected (D-12) |
| Journal = state-only 2-byte records | + spill-timestamp side CF | this phase | D-01 age evidence exists; transitions untouched |
| Rehydrate = bytes-only, unconditionally (Phase-9 SC4 ruling) | optionally seal-restoring for disposed markers IF `was_sealed` recorded | this phase (planner-ruled) | the 09-RESEARCH §2.4 deferral resolves without unprocessed-block hazard |
| Milestone-research wording "GC never writes /crdt/s" (SUMMARY 2026-10-22) | REQUIREMENTS GC-02 + ROADMAP SC2 + CONTEXT D-16: the block's OWN `s` rows are part of the eviction unit | requirements authority | SC1 guard = never ENUMERATES in policy evaluation; tombstones/`k`/`h` never written; planner encodes the reconciled boundary |

**Deprecated/outdated to correct in-tree:** none blocking — the SUMMARY wording tension above should be noted in the SPEC/plan rather than edited history.

## Security Domain (ASVS L1 — `security_enforcement: true`, `security_block_on: high` [VERIFIED: .planning/config.json])

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no new surface | existing S3/admin credentials unchanged; no new env vars |
| V3 Session Management | no | none |
| V4 Access Control | yes (new destructive capability) | GC activation = explicit opt-in (D-02) + required age (D-04) + cold-storage-enabled precondition; dry-run observe-only posture (D-03); deletion NEVER gated on config alone — durability + non-reachability + age all required |
| V5 Input Validation | yes | retention knobs strictly parsed (uint/bool, unknown-key loud, cross-field rules); marker records written by the library's own codec, never caller strings |
| V6 Cryptography | no new surface | CID verification on every cold fetch (library `Get`, never bypassed); content-addressing makes eviction safe-by-verification |
| V9/V10 Logging | yes | no credentials in any new log line (`LogSummary` discipline); rate-limited, source-distinguishable event wording |

| Threat Pattern | STRIDE | Standard Mitigation |
|----------------|--------|---------------------|
| Wrongful eviction (data loss at the node) | Tampering/Destruction | four-way gate (age ∩ spilled ∖ reachable ∩ Durable) + heads-equality re-checks at mark AND delete + grace margin + dry-run; every failure mode steers to under-eviction; remote copy + GC-03 retrieval bound the blast radius |
| Malformed/hostile config arming deletion | Tampering | D-02/D-04: absent = off; no age = loud failure; unknown keys loud; blank blockstore keeps GC inert |
| Re-delivered stale data resurrecting hidden values | Tampering | tombstones never purged (SC2 guard); re-learn enters via bytes-only rehydrate (no merge) — the Phase-12 resurrection counter-test formalizes it |
| Log-based disclosure | Information Disclosure | no new secrets; CID-level logging rate-limited off hot paths |
| Marker store poisoning via re-learn loops | DoS | D-10 dual bound + idempotent batches; re-learn converges (createOnly S3 semantics) |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | RocksDB `DB::Open` with an extended CF descriptor creates the new CFs on an EXISTING store (the flag `create_missing_column_families=true` is set [VERIFIED in-tree]; the old-store behavior is its documented purpose but was not exercised this session) | §1.2 | low — Wave-1 reopen-an-old-dir test covers it; fixture dirs exist under `test-data/` |
| A2 | Recommended default values (interval 10 min, grace 60 s, marker cap 100k, marker age 30 d) and knob names | §5.2/§4.1 | none — explicit discretion, documented constants, planner/user finalize |
| A3 | Heads-equality ⇒ snapshot reachability exact (the §2.2 lemma) — derived from verified premises (content-addressed immutable blocks; heads as sole dynamic roots), not from an executed test | §2.2 | the correctness core; encoded as SC1/SC2 tests; if a hidden root source existed (it was searched for — none found), pinning extends it |
| A4 | Walk memory ≈ 50-100 bytes/CID (unordered_set of CIDs) — back-of-envelope | §2.3 | sizing note only; knobs/docs would be retuned |
| A5 | s3d Windows binary (present at `W:\gnus\s3d_windows_amd64` + zip) runs with the existing spike-env script + a funded Sia account | Env | TEST-03 live leg blocked until the dev session verifies; hermetic tiers unaffected |
| A6 | The LRU `remove` + hot delete ordering leaves no window where `HasBlock` lies (post-cleanup both terms miss; the marker term answers) | §3.1/§4.3 | ordering detail; SC2 `HasBlock`-honesty test pins it |
| A7 | MinIO live leg semantics (no admin flush on real MinIO — durability evidence is s3d-specific; the MinIO roundtrip exercises the S3 tier only) | §8.3 | test-scope framing only |

Everything else in this document is `[VERIFIED: file:line]` against sources read this session.

## Open Questions (RESOLVED)

Every question below is resolved by a planner ruling recorded in the Phase-11 PLAN files; each Disposition line names the ruling location. Nothing in this section remains open.

1. **D-16 "resolved marker in the library batch" reconciliation** — the seal key is hot-store; the library batch cannot contain it. Recommended ruling in §3.1 (library batch = cold bytes + journal + timestamp + marker; hot cleanup = hot bytes + seal + s-rows + LRU). Planner writes it into 11-02 + the SC2 test wording.
   - What we know: all key locations verified; D-16's own crash analysis implies the two-half shape.
   - What's unclear: whether the user intended "resolved marker" to mean the journal record (the batch's third delete).
   - Recommendation: adopt §3.1; note the naming in the plan; no user decision needed unless they object at review.
   - Disposition: RESOLVED — 11-02-PLAN.md `<objective>` (planner-ruling paragraph: §3.1 adopted — library batch = cold bytes + journal record + spill timestamp + disposed marker; hot-cleanup half = hot bytes + seal key + the block's own s-rows + LRU invalidation), encoded in 11-02 must_haves ("Unit atomicity, reconciled D-16") and Task 1.
2. **Journal codec v2 vs side CF for timestamps** (§1.3) — side CF recommended; planner confirms.
   - Disposition: RESOLVED — 11-01-PLAN.md `<context>` planner-rulings line (#2): side column family (`spill_times`, birth-atomic in Put's existing WriteBatch) adopted, codec v2 rejected; implemented in 11-01 Task 1 + the LocalBlockStore must_haves artifact.
3. **GC thread ownership + DI shape** (§6.1) — manager-owned per CONTEXT integration point with post-construction attach; sibling-service alternative documented.
   - Disposition: RESOLVED — 11-01-PLAN.md `<context>` planner-rulings line (#3): manager-owned GC thread inside ColdStorageManager with post-construction `AttachGcDependencies` at the §6.1 Init slot (after m_crdtDatastore, before Start()); implemented in 11-01 Task 1 + key_links.
4. **Grace mechanics** (§3.2) — defer-to-next-tick recommended over inline wait.
   - Disposition: RESOLVED — 11-01-PLAN.md `<context>` planner-rulings line (#4): defer-to-next-tick adopted; the grace_ms knob parses in 11-01 Task 2, the mark/ProcessDueMarks mechanics land in 11-02 must_haves + Task 1.
5. **Seal restoration on re-learn** (§3.3) — record `was_sealed` now; whether v1.1 restores is a one-line planner ruling (recommend: restore only on marker-hit rehydrate, ship in 11-02 only if cheap; else defer with the field recorded).
   - Disposition: RESOLVED — 11-02-PLAN.md `<objective>` (OQ-5 ruling): `was_sealed` is RECORDED in the DisposedRecord now; NO restoration ships in v1.1 (rehydrate stays bytes-only per Phase-9 SC4 — documented deferral, enforced by 11-02's no-seal-restoration prohibition).
6. **TEST-03 evidence artifact home + runbook location** (§8.3) — recommend following the s3d-spike precedent shape; exact dir is listed discretion.
   - Disposition: RESOLVED — 11-04-PLAN.md flagged_assumptions: evidence + runbook committed under `thirdparty/sgns-blockstore/docs/evidence/gc-e2e/` following the s3d-spike precedent, with the Task-3 blocking human checkpoint as the confirmation point; encoded in 11-04 artifacts + Task 1 action.
7. **Pin set completeness** (§2.4) — v1.1 = heads + epoch-record prefix; whether an operator-pinned-CID knob is added is discretion NOT decided (recommend deferring to keep the config surface minimal).
   - Disposition: RESOLVED — 11-01-PLAN.md `<context>` planner-rulings line (#7): v1.1 pin set = heads + the `/crdt/gc/` epoch-record prefix; operator pinned-CID knob deferred out of v1.1 to keep the config surface minimal (documented deferral); encoded in 11-01 must_haves (eligibility intersection) + prohibitions.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| sgns-blockstore superbuild install | library changes (§1/§4) rebuild through it | ✓ `thirdparty/build/Windows/Debug/sgns-blockstore` | v1.0+Phases 6/10 | — |
| SuperGenius `dev_blockstore` build (SGNS_COLD_STORAGE=ON) | GC thread + Tier-1 suites | ✓ (Phases 7-10 lane) | — | OFF builds keep the config-gate Tier-1 lane non-empty |
| s3d binary (live TEST-03) | live spill→GC→retrieve E2E | ◐ `W:\gnus\s3d_windows_amd64\` + zip present; `W:\gnus\s3d-spike-env.ps1` present (contents not read) | v0.2.1 pin | runbook download path; dev-gated only — never CI; Wave-4 human checkpoint |
| Sia account + funding (live s3d) | TEST-03 | ✗ not verified this session | — | same posture as v1.0 spike; operator provisioned it before |
| `W:\gnus\minio-community.exe` | Tier-2 MinIO roundtrip | ✓ verified present | RELEASE.2025-04-22 | env-gated opt-in skips loudly without `SGNS_BLOCKSTORE_TEST_MINIO_BIN` |
| Fault kit (`InMemoryS3Client`, `InMemoryS3AdminClient`, `FaultController`, `CrashPoint`) | all hermetic tests | ✓ shipped (Phases 8-10) | — | — |

**Missing dependencies with no fallback:** none blocking — Waves 1-3 are fully hermetic.
**Missing dependencies with fallback:** live-s3d account verification (TEST-03) — dev-session item inside the Wave-4 human checkpoint, exactly as the roadmap gates it.

## Sources

### Primary (HIGH confidence — read this session, file:line)
- `thirdparty/sgns-blockstore/include/sgns-blockstore/LocalBlockStore.hpp` (UploadState enum :42-48 verbatim; EvictLocal/GetUploadsInState/MarkUploadedDurableMany docs; column-family constants); `src/LocalBlockStore.cpp` (JournalRecord codec :104-141 verbatim; Open :217-273 incl. `create_missing_column_families` :241 + descriptors :248-256; Put :296-400 incl. the new-block-only journal batch :357-366; GetUploadsInState :559-594; TransitionJournal :726-760; EvictLocal :800-824); `src/InMemoryS3AdminClient.hpp` (:40-97)
- `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` (HasBlock :663-685; GetNodeWithoutRequest :687-711; FetchNodeFromColdStorage :713-760 incl. rehydrate+LRU; TraverseCIDsLinks :921-1043 incl. resolved-skips :950-955/:1009-1012; AddCIDBlock/GrabCIDBlock/IsCIDInCache :1073-1100; DeleteCIDBlock :1102-1110 verbatim — LRU-only; cold pre-peer leg :335-356)
- `SuperGenius/src/crdt/cold_read_fallback.hpp` (hook interface; D-12 mapping; rehydrate bytes-only ruling :116-124)
- `SuperGenius/src/crdt/crdt_set.hpp` (namespaces verbatim: `elemsNamespace_="s"`, `tombsNamespace_="t"`, `keysNamespace_="k"`, `valueSuffix_="v"`, `prioritySuffix_="p"`; Elems/Tombs/Keys prefix methods); `src/crdt/impl/crdt_set.cpp` (PutElems :669-747 — `ElemsPrefix(key).ChildString(aID)` :707; PutTombs :749-799 — :773; Merge :804-814)
- `SuperGenius/src/crdt/impl/crdt_datastore.cpp` (MergeDataFromDelta :986-996 verbatim — `set_->Merge(aDelta, cid_string)`; ProcessJobIteration's own DeleteCIDBlock use :1032; HasBlock call sites :706/:1881)
- `SuperGenius/src/crdt/impl/crdt_heads.cpp` (GetList :259-285 verbatim — cache_, shared_lock, CRDTListResult{heads, max_value}; Add/Replace; PrimeCache :288-320)
- `SuperGenius/src/crdt/crdt_datastore.hpp` (GetHeadList :264; heads_ :481; headsNamespace_ "h" :488)
- `SuperGenius/src/crdt/globaldb/globaldb.cpp` (ShutdownNow :476-515 — backup→manager→cold-read ordering; Init construction order — IpfsRocksDb over `m_datastore->getDB()`, OpenColdStorageStack, dagSyncer, m_crdtDatastore last; ParseColdStorageConfig :119-407 incl. durability block :254-289 + gates (a)-(g); StartBackupLoop/StopBackupLoop :835-883; LogSummary :100-117; GetColdStorageStatus/GetColdUploadState :885-905)
- `SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp` (kEvictionDurabilityGate :65-68 verbatim; DurabilityOptions; GetUploadState/RefreshStagingStats declarations; staging atomics; lifecycle docs); `ColdStorageStack.hpp` (ColdStorageStatus :45-77 current fields; ColdUploadState; bundle + bridges; ungated-boundary discipline :15-22)
- `SuperGenius/src/crdt/globaldb/pubsub_broadcaster_ext.cpp` (AddMultiCIDInfo HasBlock :632)
- `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/impl/datastore_rocksdb.cpp` (seal/is_sealed :47-65 verbatim — `cid_string += "sealed"`; remove removes only the binary key)
- `SuperGenius/src/account/GeniusNode.cpp` (LoadCrdtConfig :557-640 — strict parse call + throw + LogSummary-on-enabled)
- `GeniusWallet/assets/crdt_config.json` (current content verbatim in §5.3)
- `.planning/workstreams/rocksdb-backup/` — REQUIREMENTS.md (GC-01..03, TEST-03, Out of Scope); STATE.md; ROADMAP phase-11 section (via orchestrator brief); `11-CONTEXT.md` (all decisions); `10-RESEARCH.md` + `10-REVIEW-DISPOSITION.md` (:22-23 MI-01/MI-02 verbatim)
- `.planning/research/SUMMARY-rocksdb-backup-2026-10-22.md` (GC shape, epoch watermark "min-head-height floor, computation only", go-ds-crdt/PurgeDAG survey); `thirdparty/sgns-blockstore/docs/testing-tiers.md` (tier contract, env gates, Tier-3 evidence discipline)
- `.planning/config.json` (nyquist_validation false; security_enforcement true, ASVS L1, block-on high)
- `supergenius-sharded-ipld-cache-architecture.md` (:314-332 write/durability path + eviction-after-policy; :342-365 cache/eviction rules — "Eviction removes only local cached bytes"; :365-377 CRDT correctness requirements — tombstones-not-purged, reachability policy, no-permanent-deletion-initially)
- Environment probes this session (s3d dir/zip, minio exe, spike-env script)

### Secondary (MEDIUM)
- None — every load-bearing claim is primary-sourced this session.

### Tertiary (LOW)
- RocksDB CF-creation-on-existing-store behavior (A1) — documented flag purpose, not exercised this session.

## Metadata

**Confidence breakdown:**
- Library surfaces (journal, EvictLocal, CFs, fakes): HIGH — headers + implementation read at cited lines with verbatim quotes
- Hot-store keyspaces (blocks/seal/s|t|k|h namespaces, construction order, shutdown order): HIGH — same
- Eviction-unit reconciliation (§3.1) + heads-exactness lemma (§2.2): HIGH confidence in the derivation (from verified premises), flagged for planner encoding — the two genuinely novel design points
- Recommendations (knob names/defaults, DI shape, grace mechanics, test lanes): MEDIUM — grounded in verified facts, explicitly discretion

**Research date:** 2026-10-27
**Valid until:** 2026-11-26 (stable tree; re-verify the cited line anchors if `dev_blockstore` or sgns-blockstore `main` move — the Phase-10 MI-01/MI-02 dispositions and `kEvictionDurabilityGate` are the load-bearing Phase-10 surfaces)
