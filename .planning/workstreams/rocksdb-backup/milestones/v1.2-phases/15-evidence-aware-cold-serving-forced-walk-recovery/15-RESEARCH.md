# Phase 15: Evidence-Aware Cold Serving & Forced-Walk Recovery - Research

**Researched:** 2026-11-17
**Domain:** CRDT read-path evidence semantics + forced-walk recovery (C++17/20, SuperGenius `dev_coldstorage_additions`)
**Confidence:** HIGH

## Summary

Phase 15 makes prune evidence — not cold bytes — the authority on every read path. Two research-discovered bugs are fixed at verified anchor points on the current merged line (HEAD `095c8c502`, i.e. Phase 14 complete on top of merge `2af184fa1`): (1) the **cold-chain resurrection gap** — `FetchNodeFromColdStorage` (`graphsync_dagsyncer.cpp:780-856`) serves and Rehydrates any CID whose cold `Get` succeeds, with zero prune-evidence consultation anywhere on that path; and (2) the **forced-walk GC-evicted conflation** — `ProcessForcedWalkCID` (`crdt_datastore.cpp:440-495`) skips ANY `!retained && sealed` CID as `skipped_pruned`, so a GC-evicted ancestor (cold-resident, no evidence) is never restored. Both sites were re-read line-by-line this session; the fix seams are exactly where the v1.2 research (§(b), §(d), §3.1, §3.4) predicted, with line numbers shifted by Phase 14's guard-5 landing (all shifts mapped in the Anchor Re-Location table below).

All four CONTEXT.md research directives were fulfilled: (1) the walk/failover numbers D-06 derives from are **verified in source** — `bootstrap_walk_max_blocks_ = 10000`, `bootstrap_walk_max_retries_ = 8` (`GeniusNode.hpp:1223-1225`), `MAX_FAILED_ROOT_RETRIES = 8` (`crdt_datastore.hpp:730`), `CID_FAILURE_SUPPRESSION{4}` (`graphsync_dagsyncer.hpp:226`), `kTotalFetchTimeout = 20s` / `kInProgressRequestTimeout = 120s` (`graphsync_dagsyncer.cpp:28/:21`) — plus develop-19-07's recorded failover observations (attempts ≤8 RefusalFailover, [1,4] PrunedMesh); a concrete constant derivation is recorded below. (2) A5 re-verified: the merged line carries the identical plumbing-only posture (the wire refusal status remains not directly observable from tests; behavior-assertion discipline + a new test-only observable seam is the Phase 15 shape). (3) All anchors re-located at `095c8c502`. (4) Phase 14 D-01's single-CID removal set **holds** — `EraseTransactionEntryWithMarker` resolves ONE path+ONE CID and stages ONE marker pair per erase, so D-01's one-`/prune/blk`-marker-per-erase widening is sound.

**Primary recommendation:** Implement the tri-state predicate as a `ColdReadFallback` extension (seam-side enum, `ColdReadService` sole implementor, GlobalDB-injected at the `globaldb.cpp:824-852` wiring seam), consult it inside `FetchNodeFromColdStorage` after cold-`Get` success / before `Rehydrate`, widen `EraseEntry`'s `extra_entry` to a vector of pairs, replace the walk's `!retained && sealed` skip with the D-05 evidence matrix, and add ONE named per-CID peer-failover constant derived from the recorded 8-bound everywhere.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Widen `EraseEntry`'s `extra_entry` to a vector — the opaque pair parameter becomes a vector of pairs; TxPruner passes both `/prune/tx` and `/prune/blk`; `EraseEntry` stays THE single atomic staging point. Key shapes built in `PruneEligibility` (D-C1). Phase 14 D-01's single-CID removal-set ruling is the load-bearing premise.
- **D-02:** `/prune/blk/<cid>` value carries a back-reference record — erased-at generation + the `/prune/tx` hash back-reference, shaped in `PruneEligibility` alongside the key builder.
- **D-03:** No backfill, no lookup fallback — v1.1 never deployed (user-confirmed 2026-11-17); `/prune/blk` evidence starts fresh from Phase 15.
- **D-04:** Source-consistency ruling — `HasBlock` stays bool and its body is UNCHANGED; SC3 means all surfaces derive from the ONE role-aware GlobalDB predicate.
- **D-05:** Fourth quadrant = bounded peers, then loud abort — distinct walk-gap error + counter (never a skip counter).
- **D-06:** Failover-budget defaults derive from recorded v1.1 walk-recovery numbers — named internal constants, rationale recorded; Phase 17 SC2's probe validates/re-tunes. No config knobs.
- **D-07:** Mirror develop's SURV-02 exactly — distinct `GraphsyncDAGSyncer::Error`, responder refuses cleanly with standard status, requesters fail over through EXISTING `RecordCIDFailure`. ZERO wire/proto changes (a new *message* in `SGTransaction.proto` for the marker record value is node-local storage, not a wire change — same class as `PrunedTransactionRecord`).

### The Agent's Discretion
- TEST-01 fake architecture (seeded real-RocksDB markers vs in-memory fake)
- Predicate injection mechanics (extend `ColdReadFallback` vs separate role flag)
- Cold-present probe mechanics in the walk
- `Error` enum naming/placement in `ApplyColdPrecedence`; walk-gap error + counter naming
- Consistency-test shape proving SC3's source-consistency
- Tier placement (Tier-1 expected per Phase 14 D-09)
- Interrupt-seam extensions for induced-evidence tests

### Deferred Ideas (OUT OF SCOPE)
- Vulkan capability-probe deadlock todo (keyword-only match; same ruling as Phases 13/14)
- Wire-level graphsync "pruned" signal (rejected per D-07)
- `/prune/blk` backfill migration or `/prune/tx`-scan fallback (moot per D-03)
- Phase 16: `EraseEntry` post-commit `DeleteCIDBlock` (stale-LRU window close)
- Phase 17: seal growth measurement + walk-bound probe
- Phase 18: collectibility policy + role downgrade; Phase 19: fault-race matrix + 3-platform CI
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SERVE-01 | TxPruner-erased CID answered with pruned semantics even when cold bytes exist; cold chain consults evidence before serving; no resurrection | Predicate consult inside `FetchNodeFromColdStorage` (:780-856) between cold-`Get` success and `Rehydrate`; terminal distinct error; D-01/D-02 marker staging supplies the evidence |
| SERVE-02 | GC-evicted CID (no evidence) on cold-enabled node served through cold chain and re-warmed; evict ≈ DETACH; masquerading counter-tests both directions | No-evidence branch serves + Rehydrates (existing v1.1 path preserved verbatim); counter-tests via the refusal-matrix fixture; `EvictServe_HalfWindowS3Fetch_ResolvesCidVerified` precedent [CITED: v1.1 12-01-SUMMARY] |
| SERVE-03 | Tri-state answer consistent across `HasBlock`, `getNode`, cold chain via ONE role-aware GlobalDB predicate | Predicate owned by GlobalDB, injected once at `globaldb.cpp:824-852` seam; `HasBlock` body untouched (D-04); consistency test shape below |
| SERVE-04 | Pruned distinct from not-found at protocol surface; requesters fail over correctly | New `GraphsyncDAGSyncer::Error` value appended to enum (`graphsync_dagsyncer.hpp:50-66`); `ApplyColdPrecedence` refusal class; existing `RecordCIDFailure` failover; A5 discipline below |
| RECOVER-02 | Forced walk restores GC-evicted ancestors from cold; never conflates GC-evicted with pruned | `ProcessForcedWalkCID` :452-458 branch replaced by the D-05 evidence matrix; `getNode` cold-before-peers already serves + Rehydrates synchronously (guarantee 1 below) |
| RECOVER-03 | Walk never resurrects TxPruner-erased elements; `CanRestoreElement` composition terminal | `CanRestoreElement` (`PruneEligibility.cpp:156-170`) verified terminal (PRUNED→false, VALUE_PRESENT_INVARIANT_VIOLATION→failure); block-level `/prune/blk` skip bounds the walk; guard wired at `GeniusNode.cpp:1664-1667` |
| RECOVER-04 | Peer-failover bounded per-CID; walk-gaps abort-never-skip | Named constants derived below (D-06); `ForcedWalkStatus` gains a distinct walk-gap counter sibling of `skipped_pruned` (`crdt_datastore.hpp:79-88`) |
| TEST-01 | Hermetic evidence-aware fakes model the PrunedLookup tri-state; refusal matrix as product {hot}×{cold}×{evidence: none/PRUNED/malformed}×{serve, walk visit, erase-gate} | Real-GlobalDB + raw-surface seeding (Phase 14 D-08 kit precedent: `cold_prune_gate_test.cpp`) as primary; stub predicate via the seam for syncer-layer suites; static-hook injection pattern (`SetColdUploadStateHookForTest`) |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Prune-evidence tri-state predicate | GlobalDB (storage owner) | — | GlobalDB owns the raw store where `/prune/*` markers live (`GetRaw` surface `LookupPrunedEntry` already uses) and owns the cold-stack wiring seam; single owner makes SC3's source-consistency testable |
| Cold-chain evidence consult | GraphsyncDAGSyncer read path | GlobalDB (via injected hook) | The consult must sit between cold-`Get` success and `Rehydrate` — inside `FetchNodeFromColdStorage`, which only the syncer owns; evidence itself comes from the injected predicate |
| Responder wire refusal | ColdServeDagService (graphsync responder) | syncer Error classification | Standard status only (D-07); the distinct semantics live in the syncer-layer `Error`, never on the wire |
| Walk decision matrix | CrdtDatastore forced walk | syncer `getNode` (fetch) | The `!retained && sealed` branch is walk-local; the actual restore rides `getNode`'s cold-before-peers chain unchanged |
| `/prune/blk` marker staging | `EraseEntry` compose path (GlobalDB) | PruneEligibility (key/value builders), TransactionManager (caller) | D-01 keeps `EraseEntry` THE single atomic staging point; D-C1 keeps key shapes in PruneEligibility |
| Failover budget enforcement | `getNode` route walk | Forced-walk gap mapping | The per-CID peer bound must live where peers are consulted (`getNode` :396-634 loop); the walk maps exhaustion to its distinct abort |
| Tri-state fakes | Test tier (Tier-1) | — | Hermetic-first discipline; no production surface |

## Anchor Re-Location (directive 3) — current merged line @ `095c8c502`

All anchors below were opened and read this session. CONTEXT.md anchors were taken at merge `2af184fa1`; Phase 14 (`dc788261d`→`095c8c502`) shifted `globaldb.*` (~+100 lines from guard 5) and `TxPruner.*`.

### `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp`
| Anchor | Was | Now | Notes |
|---|---|---|---|
| `kInProgressRequestTimeout` / `kTotalFetchTimeout` | — | **:21** / **:28** | `std::chrono::seconds( 120 )` / `std::chrono::seconds( 20 )` [VERIFIED, quoted verbatim from source] |
| `ApplyColdPrecedence` | :41-67 | **:41-67** (unchanged) | Free fn in anon namespace; maps `ColdReadStatus::Class` over `CID_NOT_FOUND`/`ROUTE_NOT_FOUND` only |
| Error-string switch (`OUTCOME_CPP_DEFINE_CATEGORY_3`) | — | **:70-98** | New error value needs a case here |
| `ColdServeDagService::getNode` | :108-124 | **:108-124** (unchanged) | Responder: hot-first delegation + fire-and-forget `EnqueueRewarm`; comment cites `RS_NOT_FOUND` as the honest don't-have |
| `GraphsyncDAGSyncer::getNode` | :324-614 | **:334-634** | Cold chain at :376; `RecordCIDFailure` :528/:550/:571/:587; FAILED-branch CID-vs-connection split :547-571 |
| `StageBlockRemoval` | :618-633 | **:639-655** | |
| `HasBlock` | :686-723 | **:705-748** | 4 terms; term 3 `HasLocalCold` ~:726; term 4 `HasDisposed` ~:737; **body stays unchanged (D-04)** |
| `GetNodeWithoutRequest` | :725-806 (span) | **:755-777** | Delegates cold leg to `FetchNodeFromColdStorage(cid, grabResult)` |
| `FetchNodeFromColdStorage` | :750-806 | **:780-856** | **THE SC1/SC2 fork**: cold `Get` success → `!bytes.empty()` branch (:807-812) → `Rehydrate` (:816) — no evidence consult today |
| `StartSync` wrapper install | — | **:858-881** (wrapper at :869) | `cold_serve_wrapper_` = ColdServeDagService(dagService_, cold_read_hook_.get()) |
| seal accessors `markResolved`/`isResolved` | :1083-1092 | **:1113-1122** | Also `InitCIDBlock` :1125, `IsCIDInCache` :1151, `GrabCIDBlock` :1156, `DeleteCIDBlock` :1169 |
| `RecordCIDFailure` / suppression consumption | — | **:1398** / **:1424** | `failure_age > CID_FAILURE_SUPPRESSION` |

### `SuperGenius/src/crdt/globaldb/globaldb.hpp` / `.cpp`
| Anchor | Was | Now | Notes |
|---|---|---|---|
| `ColdUploadState` fwd decl | :43 | **:43** | |
| `EraseEntry` signature incl. `extra_entry` | :489 | **:482-519** (signature **:517-519**) | Current param verbatim: `const std::optional<std::pair<Buffer, Buffer>> &extra_entry = std::nullopt` [VERIFIED: globaldb.hpp:517-519] — the D-01 widening point |
| `SetEraseInterruptHookForTest` | — | **:522-527** | Steps 1/2/3 = after CRDT/block/raw-map staging |
| `SetColdUploadStateHookForTest` | — | **:532-549** | Phase 14's induced-regression seam — the pattern induced-evidence tests extend |
| `GetColdUploadState` | :576 | **:610** | |
| Cold-stack wiring / injection seam | globaldb.cpp:819-846 | **globaldb.cpp:824-852** | `OpenColdStorageStack` call :828; `cold_read_hook` :840; `cold_read_service_` :841-842; `StartColdReadService()` :846; hook → DAGSyncer ctor :864 |
| `EraseEntry` impl + guards | :1428-1466 | **globaldb.cpp:1440-1587** | Compose lock :1453; guards 1-4 :1467-~1503; **guard 5 (COLD_NOT_DURABLE, Phase 14) :~1509-1551**; `extra_entry` staging **:1564-1567** (`batch->put( extra_entry->first, extra_entry->second )` :1566); post-commit seal re-assert :1571-1587 |
| Guard 3 (LRU) | :1428-1432 | within :1467-1503 block | Now the third guard inside the compose section |

### `SuperGenius/src/crdt/impl/crdt_datastore.cpp` / `crdt_datastore.hpp`
| Anchor | Was | Now | Notes |
|---|---|---|---|
| `RequestForcedWalk` | :212-470 (span) | **:212-278** | `max_blocks` bound; `ForcedWalkState::Queued/Running/Incomplete/Completed/Cancelled` |
| `FinishForcedWalkLocked` | — | **:299-322** | Counter log: visited/fetched/restored/skipped_pruned/skipped_existing/deferred/errors/limit_reached |
| `ProcessForcedWalkStep` / `forcedWalkStepActive_` | :336-435 | **:339-400** | One-CID-at-a-time on the DAG worker |
| `QueueForcedWalkLinks` | — | **:402-438** | `InheritRoutes(parent→child)` before persist |
| `ProcessForcedWalkCID` | :440-470 | **:440-495** | **The conflation branch :452-458** (quoted below); fetch `retained ? GetStoredNode : getNode` :471 |
| `RecoverMissingElements` | — | **:497-586** | Element guard call :552-564; `resource_unavailable_try_again` → deferred |
| `RecoveryElementGuard` / `ForcedWalkStatus` | — | **crdt_datastore.hpp:67 / :79-88** | `skipped_pruned` :85 — walk-gap counter joins here |
| `MAX_FAILED_ROOT_RETRIES` | — | **crdt_datastore.hpp:730** | `static constexpr uint32_t MAX_FAILED_ROOT_RETRIES = 8;` [VERIFIED, quoted verbatim] |

### Transaction / walk-driver anchors
| Anchor | Was | Now | Notes |
|---|---|---|---|
| `EraseTransactionEntryWithMarker` | TransactionManager.cpp:4718 | **:4718-4768** (unchanged start) | Directive-4 verification below |
| `PrunedLookup` enum | — | **PruneEligibility.hpp:115-129** | Values verbatim: `PRUNED`, `NOT_FOUND`, `VALUE_PRESENT_INVARIANT_VIOLATION` [VERIFIED: PruneEligibility.hpp:115-129] |
| `CanRestoreElement` | PruneEligibility.cpp:156-170 | **:156-170** (unchanged) | Decl `PruneEligibility.hpp:342-348` |
| `PRUNE_MARKER_PREFIX` | — | **PruneEligibility.hpp:~395** | `static constexpr std::string_view PRUNE_MARKER_PREFIX = "/prune/tx/";` [VERIFIED, quoted verbatim] — the `/prune/blk/` sibling constant's home |
| `BuildPruneMarkerKey` / `LookupPrunedEntry` / `BuildPruneMarkerEntry` | — | **PruneEligibility.cpp:172-176 / :179-246 / :248-269** | Malformed marker → `std::errc::bad_message` (T-17-0502 discipline — `/prune/blk` mirrors this) |
| `RequestBootstrapWalk` + guard | GeniusNode.cpp:1571-1630, guard :1618 | **:1617-1703**, guard **:1664-1667** | `return PruneEligibility::CanRestoreElement( *db, element.key() );` |
| Walk bounds | — | **GeniusNode.hpp:1223-1225** | Verbatim: `bool force_bootstrap_walk_ = false;` / `size_t bootstrap_walk_max_blocks_ = 10000;` / `size_t bootstrap_walk_max_retries_ = 8;` [VERIFIED: GeniusNode.hpp:1223-1225] |
| TxPruner gate (Phase 14) | — | **TxPruner.cpp:77-130** | `HasColdStorage()` :94, `GetColdUploadState` :109, `cold_deferred_groups` :106/:126; seams `kInterruptAfterColdGate` :277, `kInterruptBeforeErase` :293 |
| GC parity | ColdStorageManager.cpp:1072-1076 / :1317-1345 | **:1072-1076** / **:1317-1352** | `kEvictionDurabilityGate` consumption; `RunHotCleanup` + `DeleteCIDBlock` :1352 |

### Test anchors (merged line)
- `test/src/crdt/globaldb_erase_test.cpp` — `EraseNodeCollection` **:90**, `GlobalDBEraseRedeliveryTest` **:521**, `GlobalDBEraseRefusalFailoverTest` **:1044**, `PrunedPeerRefusalFailsOverToServingPeer` **:1116** (D-07's failover-evidence extension point)
- `test/src/blockchain/node_startup_test.cpp` — `ForcedBootstrapWalkRunsBeforeBlockchainIsReady` **:543**, `ForcedBootstrapWalkRetriesLateValidatorAfterReady` **:573** (the walk suites: walk-before-ready, Incomplete+deferred, retry-after-READY, stays-READY)
- Phase 14 kit: `cold_prune_gate_test.cpp`, `cold_prune_toctou_test.cpp`, `cold_prune_live_smoke_test.cpp` (static-hook + interrupt-seam discipline)
- v1.1 Tier-1 cold kit: `cold_storage_gc_test.cpp`, `cold_storage_fault_race_test.cpp`, `cold_storage_resurrection_test.cpp`, `cold_storage_gc_retrievability_test.cpp`

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| (none new — pinned mechanisms only) | — | — | v1.2 governing decision: zero new dependencies; all work composes RocksDB 9.4.0, s3d v0.2.1, vendored ipfs-lite-cpp unedited, minio-cpp 1.0.0 [CITED: STATE.md v1.2 key decisions] |

### Supporting (existing seams this phase composes)
| Mechanism | Location | Purpose | When to Use |
|-----------|----------|---------|-------------|
| `ColdReadFallback` interface | `src/crdt/cold_read_fallback.hpp` | Ungated hook the syncer holds; `ColdReadService` is the ONLY implementor (`final`, `ColdReadService.hpp:48`) | Predicate injection — extend this interface (see Pattern 1) |
| `PrunedLookup` tri-state | `PruneEligibility.hpp:115-129` | The evidence vocabulary TEST-01 fakes model | `/prune/blk` lookup mirrors it |
| `EraseEntry` atomic staging | `globaldb.cpp:1440-1587` | One compose-locked WriteBatch: erase + markers | D-01 vector widening |
| Interrupt/static-hook seams | `SetEraseInterruptHookForTest`, `SetColdUploadStateHookForTest` | Induced-evidence injection | Red-first counter-tests |
| `RecordCIDFailure` + `CID_FAILURE_SUPPRESSION` | `graphsync_dagsyncer.cpp:1398`, `graphsync_dagsyncer.hpp:226` | Per-CID failover accounting | SERVE-04 — reuse, never re-derive |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Extend `ColdReadFallback` with evidence lookup | Separate parallel interface held by the syncer | Second pointer + second injection path; violates the one-seam discipline; rejected (Pattern 1 rationale) |
| GlobalDB-built predicate injected into `ColdReadService` | Syncer queries GlobalDB directly | Ungated TU would need GlobalDB types — breaks the header-hygiene gate [VERIFIED: cold_read_fallback.hpp:13-16 "no library type ever crosses the gated/ungated boundary"] |
| Vector `extra_entry` (D-01, LOCKED) | TransactionManager stages `/prune/blk` separately | Second write = erase-without-marker window; violates atomicity-by-construction; re-litigated and rejected in CONTEXT |

**Installation:** none.

## Package Legitimacy Audit

No external packages are installed by this phase (zero-new-dependencies milestone constraint [CITED: STATE.md]). No registry queries needed; no `[ASSUMED]` package names appear in this research.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| — | — | — | — | — | — | none — pinned mechanisms only |

## Architecture Patterns

### System Architecture Diagram

```mermaid
flowchart TD
    subgraph ReadPaths["Read paths (SC1/SC2/SC3)"]
        GN["getNode(cid) :334"] --> HOT1["hot + LRU"]
        HOT1 -->|miss| FNF["FetchNodeFromColdStorage :780"]
        GNR["GetNodeWithoutRequest :755"] --> HOT2["hot + LRU"]
        HOT2 -->|miss| FNF
        RESP["ColdServeDagService::getNode :108 (responder)"] -->|hot miss| RW["EnqueueRewarm (fire-and-forget) + honest don't-have"]
        FNF --> CGET["cold Get (Local→S3, CID-verified)"]
        CGET -->|bytes| PRED{"[NEW] GlobalDB evidence predicate<br/>(injected at globaldb.cpp:824-852)"}
        PRED -->|role=Archive/Full| SERVE["SERVE + Rehydrate (bytes-only)"]
        PRED -->|"/prune/blk present"| REFUSE["REFUSE — distinct Error::HISTORY_PRUNED*<br/>TERMINAL: no Rehydrate, no peer fall-through"]
        PRED -->|no evidence| SERVE2["SERVE + Rehydrate (evict ≈ DETACH)"]
        PRED -->|malformed| FAILCLOSED["hard error (T-17-0502 discipline)"]
        CGET -->|miss/fault| PEERS["peers (getNode only) + ApplyColdPrecedence"]
        REFUSE --> REQ["requester: RecordCIDFailure → failover to archive peer"]
    end
    subgraph Walk["Forced walk (SC4)"]
        STEP["ProcessForcedWalkCID :440"] --> RET{"retained? (HasStoredBlock=raw hot)"}
        RET -->|yes| GETS["GetStoredNode (hot only)"]
        RET -->|no + sealed| MATRIX{"[NEW] D-05 matrix<br/>(replaces !retained&&sealed skip :452-458)"}
        MATRIX -->|"/prune/blk"| SKIP["skip — skipped_pruned (bounded walk)"]
        MATRIX -->|cold-present / no evidence| GETN["getNode → cold chain → Rehydrate<br/>→ replay → CanRestoreElement per element<br/>→ walk owns sealing"]
        MATRIX -->|neither (4th quadrant)| BOUNDED["getNode peer leg — [NEW] per-CID budget<br/>exhausted → DISTINCT walk-gap error + counter<br/>ABORT, never skip"]
        RET -->|no + !sealed| GETN2["getNode (existing discipline)"]
    end
    subgraph Erase["Erase path (D-01/D-02)"]
        TXP["TxPruner::RunCycle (gated, Phase 14)"] --> ETM["EraseTransactionEntryPruned"]
        ETM --> PE2["PruneEligibility builds BOTH marker pairs<br/>/prune/tx/<hash> + /prune/blk/<cid>"]
        PE2 --> EE["EraseEntry(key, cid, vector<pair>)<br/>ONE compose-locked WriteBatch"]
    end
```

### Recommended Project Structure
```
SuperGenius/src/
├── crdt/cold_read_fallback.hpp        # seam-side PruneEvidenceClass enum + new virtual
├── crdt/globaldb/ColdReadService.hpp/.cpp  # implements lookup via GlobalDB-injected callable
├── crdt/globaldb/globaldb.hpp/.cpp     # extra_entry vector widening + predicate injection
├── crdt/impl/graphsync_dagsyncer.cpp   # FetchNodeFromColdEvidence consult; Error value; walk-budget
├── crdt/impl/crdt_datastore.cpp        # D-05 matrix + walk-gap counter
├── crdt/graphsync_dagsyncer.hpp        # Error enum append; budget constant
├── transaction/PruneEligibility.hpp/.cpp  # /prune/blk key builder + back-ref record + lookup
├── transaction/TransactionManager.cpp  # passes the marker vector
└── account/proto/SGTransaction.proto   # PrunedBlockRecord message (node-local value; not a wire change)
SuperGenius/test/src/crdt/              # evidence-matrix suite (Tier-1) + walk suites + failover extension
```

### Pattern 1: Predicate injection at the one seam (SC3's single-owner rule)
**What:** A seam-side tri-state enum + one new virtual on `ColdReadFallback`; `ColdReadService` implements it by calling a GlobalDB-installed `std::function`; GlobalDB installs it at the existing wiring point immediately after `OpenColdStorageStack` returns (between `cold_read_service_` assignment `globaldb.cpp:841-842` and the DAGSyncer construction `:864`).
**When to use:** exactly this phase — SC3 requires ONE predicate owned by GlobalDB.
**Why this shape [VERIFIED facts]:**
- `ColdReadService` is the ONLY implementor of `ColdReadFallback` (`class ColdReadService final : public ColdReadFallback`, ColdReadService.hpp:48) — one implementation site, no fan-out.
- The ungated header's hygiene rule is explicit: "deliberately free of every sgns-blockstore types … no library type ever crosses the gated/ungated boundary" [VERIFIED: cold_read_fallback.hpp:8-16] — the enum must live seam-side, mirroring `ColdReadStatus` (same file :27-42), NOT reference `PrunedLookup` (transaction-layer type).
- GlobalDB cannot be referenced from the ungated TU; a `std::function`-shaped injection keeps the dependency direction GlobalDB→service.
- Null-hook discipline preserved: disabled builds keep byte-identical behavior (the Phase-7 bar, cited at cold_read_fallback.hpp:11-13).

```cpp
// cold_read_fallback.hpp — seam-side mirror (shape; final naming is planner discretion)
enum class PruneEvidenceClass : uint8_t
{
    NoEvidence,   ///< no /prune/blk marker — cold bytes are restorable history
    Pruned,       ///< marker present — node-local terminal refusal
    Malformed,    ///< marker bytes failed decode — fail-closed hard error
};
// inside ColdReadFallback:
virtual PruneEvidenceClass LookupPruneEvidence( const CID &cid ) = 0;
```
*Default-virtual vs pure: pure is cleaner (one implementor); if test stubs multiply, a non-virtual default returning `NoEvidence` avoids forcing fakes to care — planner's call.*

### Pattern 2: The consult point — evidence BEFORE Rehydrate (SC1/SC2 fork)
**What:** Inside `FetchNodeFromColdStorage` (`:780-856`), consult the predicate in the `!bytes.empty()` success branch BEFORE `cold_read_hook_->Rehydrate( cid, bytes )` (:816). `Pruned` → return `outcome::failure(Error::HISTORY_PRUNED*)` with NO Rehydrate (never write resurrected bytes); `NoEvidence` → existing serve+Rehydrate verbatim; `Malformed` → hard error.
**Terminality in `getNode`:** the distinct refusal error must NOT fall through to the peer leg — evidence outranks bytes AND peers (node-local terminality, governing invariant 2). Mechanically: either return immediately at the consult site (it is inside the cold leg both `getNode` and `GetNodeWithoutRequest` share) or extend `ApplyColdPrecedence` so a recorded refusal outranks everything — returning immediately at the consult site is the smaller, order-preserving change; the `ApplyColdPrecedence` naming/placement is the discretion item.
**When to use:** every cold-chain serve.

### Pattern 3: D-01 vector widening (atomic staging preserved)
**What:** `EraseEntry`'s third parameter becomes `const std::optional<std::vector<std::pair<Buffer, Buffer>>> &extra_entries = std::nullopt` (current: `const std::optional<std::pair<Buffer, Buffer>> &extra_entry = std::nullopt` [VERIFIED: globaldb.hpp:517-519]). The staging loop at :1564-1567 puts each pair into the SAME batch after raw-map removal, before the single commit. `PruneEligibility` gains `BuildPruneBlockMarkerEntry(cid, tx_hash, generation)` returning the pair (D-C1: key home + record shape live there; callers never rebuild); `TransactionManager::EraseTransactionEntryWithMarker` assembles the 2-element vector.
**Why:** marker-without-erase and erase-without-marker windows remain impossible by construction — the D-01 locked decision's mechanics confirmed feasible at the verified staging site.

### Pattern 4: `/prune/blk` record shape (D-02)
**What:** A new `PrunedBlockRecord` message in `SGTransaction.proto` beside `PrunedTransactionRecord` (:66-76, fields verbatim: `string tx_path = 1; string cid = 2; bool has_erased_at_height = 3; uint64 erased_at_height = 4;` [VERIFIED: SGTransaction.proto:70-76]). Back-reference fields: the erasing `/prune/tx` hash + erased-at generation (the TxPruner generation already counted in `PruneCycleStats`). Key: `"/prune/blk/" + cid.toString()`. Presence IS the refusal signal; the record buys operator traceability and feeds Phase 17's ancestry-density measurement. New message = backward-compatible proto extension; node-local raw-store value, never a wire format (D-07's zero-wire-change constraint untouched).

### Pattern 5: The D-05 walk matrix (replaces the conflation branch)
**What:** Replace `ProcessForcedWalkCID` :452-458 — verbatim today:
```cpp
if ( !retained && sealed )
{
    ++progress.skipped_pruned;
    logger_->debug( "Forced walk CID {}: missing sealed block, preserving prune boundary", cid_string );
    return outcome::success();
}
```
[VERIFIED: crdt_datastore.cpp:452-458]
with the evidence matrix: (a) `/prune/blk` present → skip (`skipped_pruned`, terminal — block-level skip bounds the walk); (b) no evidence → `getNode` (the cold chain serves before peers, synchronously Rehydrates, and the existing element-level `CanRestoreElement` guard stays terminal authority — both layers per research §(d)); (c) neither cold nor evidence (4th quadrant) → `getNode` peer leg bounded by the new per-CID budget; exhausted → **distinct walk-gap error + dedicated counter** (sibling of `skipped_pruned` in `ForcedWalkStatus`, `crdt_datastore.hpp:79-88`), the walk ABORTS (never skips — no silently-validated partial history).
**Cold-present probe (discretion):** for counter fidelity, classify before fetch via `HasLocalCold` || `HasDisposed` (freeze-safe point lookups already on the hook) — but the fetch itself is `getNode` either way, so a probe miss that `getNode`'s cold chain still serves is behaviorally correct (just counted as 4th-quadrant). The cheap probe is recommended for the restore-vs-peer counter split.

### Anti-Patterns to Avoid
- **Consulting evidence in `HasBlock`'s body** — D-04 locks the 4-term bool answer (dedup-correct; the retained seal makes re-delivered deltas inert). The consistency requirement is source-consistency, not shape-consistency.
- **Folding the refusal into `CID_NOT_FOUND`** — destroys SERVE-04's failover semantics; develop rejected the same shape; BIP-159-NOPRUNE-style distinction required.
- **Falling through to peers after a `Pruned` refusal** — resurrection via peer fetch; evidence is node-locally terminal.
- **Rehydrate-then-check** — writes resurrected bytes before refusing; the consult must precede `Rehydrate` (:816).
- **A walk-gap skip counter** — D-05: abort-never-skip; a gap must be loud (distinct error + counter + Incomplete walk).
- **Building `/prune/blk` key shapes at call sites** — D-C1: `PruneEligibility` is the one home (mirror `BuildPruneMarkerKey`).
- **Treating `GetNodeWithoutRequest`'s cold leg as separate** — it delegates to the same `FetchNodeFromColdStorage`; one consult site covers both read surfaces.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CID-keyed refusal evidence | Scan `/prune/tx` records per CID lookup | `/prune/blk/<cid>` point marker (D-01/D-02) | O(1) lookup; prefix scans are the WR-04 anti-pattern `LookupPrunedEntry` already documents |
| Peer failover accounting | New blacklist/route machinery | `RecordCIDFailure` + `HasRecentCIDFailure` + `CID_FAILURE_SUPPRESSION` (:1398/:1424) | CID-scoped, connection-vs-CID distinction proven by 19-07 |
| Cold classification surface | New error taxonomy | `ColdReadStatus` + `MapColdReadStatus` + `ApplyColdPrecedence` | Extend the verified SC3-mapping surface |
| Induced-evidence injection | New test hooks per case | Static-hook + interrupt-seam pattern (`SetColdUploadStateHookForTest`, `SetEraseInterruptHookForTest`, `kInterruptBeforeErase`/`kInterruptAfterColdGate`) | Phase 14 precedent; process-global, cleared in teardown |
| Tri-state vocabulary | New enum per layer | `PrunedLookup` (transaction) + one seam-side mirror enum (ungated TU) | Header-hygiene gate forbids crossing domain types |
| Re-warm during walk | Walk-side fetch machinery | `getNode` cold-before-peers chain | Five verified ordering guarantees (below) already hold |

**Key insight:** every mechanism this phase needs already exists as a verified seam; the work is composition (one predicate, one consult site, one widened staging slot, one matrix branch) — which is exactly why the v1.2 research could pin the design before implementation.

### The five re-warm ordering guarantees (verified on the merged line) [CITED: ARCHITECTURE-v1.2 §(d), spot-verified in source this session]
1. Fetch→rehydrate→serve is synchronous inside `getNode` — parent bytes are hot before `QueueForcedWalkLinks` parses links (`Rehydrate` called inline at `graphsync_dagsyncer.cpp:816`).
2. Rehydrate writes BYTES ONLY, never seals — the walk's element-application path owns sealing after successful replay (09-RESEARCH §2.4 ruling, documented on `ColdReadFallback::Rehydrate`).
3. Re-warm re-journals through the Phase-8 decorator `set()` — fresh `PendingUpload` records converge via drainer `alreadyPresent`; harmless, assert during recovery-at-scale.
4. One-CID-at-a-time on the DAG worker (`forcedWalkStepActive_` :339-400); no new lock ordering vs `dagMutex_` (cold chain runs outside it).
5. Lifecycle ordering supports the walk (re-warm worker stops later than the drainer in `ShutdownNow`).

## Runtime State Inventory

> Included because D-01 is a signature refactor on the erase path. Not a rename/migration phase otherwise.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | `/prune/tx/<hash>` markers exist in hot stores of dev/test nodes from Phase 14 work; **no `/prune/blk` rows exist anywhere** (new namespace) | None — D-03: no backfill, no fallback lookup; evidence starts fresh |
| Live service config | None — no external services carry the erased-string/marker state (markers are node-local RocksDB rows) | None |
| OS-registered state | None — no tasks/services/registrations reference these symbols | None |
| Secrets/env vars | None — no env or secret names change | None |
| Build artifacts | `SuperGenius/build/Windows/Release` — stale objects after header changes (`cold_read_fallback.hpp` is included widely); full Tier-1 lane re-run required | Rebuild + `ctest -L Tier1` (Phase 14 D-09 contract) |

## Common Pitfalls

### Pitfall 1: Evidence consult on the cold-miss path only
**What goes wrong:** consulting `/prune/blk` only when cold bytes exist leaves the cold-miss + evidence case serving from PEERS (resurrection by peer). **Why:** the natural insertion point (the `!bytes.empty()` branch) hides the sibling case. **How to avoid:** the consult precedes/parallels the cold `Get` result handling — `Pruned` is terminal regardless of cold hit/miss (note: GC never deletes `/prune/blk` markers — they are hot-store raw keys, not journal-enumerated blocks; markers survive cold-byte disposal, so evidence-without-cold-bytes is a REAL state). **Warning signs:** a test where evidence exists, cold dir is empty, and getNode still returns peer bytes.

### Pitfall 2: HasBlock "fix" temptation (SC3 shape-vs-source)
**What goes wrong:** making `HasBlock` return false for pruned CIDs breaks the D-12 dedup split (terms 3/4 intentionally answer TRUE; re-delivery dedup + seal-retained inertness). **How to avoid:** D-04 is locked — body unchanged; consistency = one predicate source, many surface shapes. **Warning signs:** any diff touching `HasBlock` :705-748.

### Pitfall 3: The gossip-cache nondeterminism in failover tests (19-07's recorded lesson)
**What goes wrong:** broadcast-sequenced refusal tests are coin-flips — grafting relays every cached publish at once, so which route registers first is a cache race. **How to avoid:** the two-part proof — hermetic ordered-`AddRoute` + one direct `getNode` for the mechanism; ordering-free mesh E2E for convergence [CITED: 19-07-SUMMARY key-decisions]. Also: discard directly-fetched LRU blocks between phases (`DeleteCIDBlock`) or the broadcast intake silently skips the CID. **Warning signs:** refusal tests green only with huge windows.

### Pitfall 4: Guessed wire-status constants (A5)
**What goes wrong:** asserting an unverified graphsync status value welds tests to a guess. **How to avoid:** assert observable behavior (failover completed, `IsOnBlackList` false, storage-deterministic refusal) + record the observed value; add a test-only observable only if it surfaces honestly (see A5 section). **Warning signs:** any `EXPECT` on a status constant not quoted from source.

### Pitfall 5: Walk-gap misclassification as `deferred`
**What goes wrong:** mapping the 4th-quadrant exhaustion onto the existing `deferred` counter re-runs the walk forever (deferred entries retry; a true gap never resolves). **How to avoid:** dedicated walk-gap counter + distinct error; the walk finishes Incomplete. **Warning signs:** `deferred > 0` in a no-evidence-no-cold-no-peer fixture.

### Pitfall 6: Vector-widening breaking the Phase-16 surface
**What goes wrong:** redesigning the erase path beyond the parameter widening collides with Phase 16's COMP-01 (post-commit `DeleteCIDBlock`) landing on the same function. **How to avoid:** widen the slot, nothing else — guards, compose lock, post-commit seal re-assert untouched. **Warning signs:** diffs in `EraseEntry` beyond the parameter + staging loop.

### Pitfall 7: Malformed-evidence legs treated as PRUNED
**What goes wrong:** a garbage `/prune/blk` value silently refusing service (or silently serving). **How to avoid:** `Malformed` → hard error, mirroring T-17-0502 (`LookupPrunedEntry` returns `std::errc::bad_message`, PruneEligibility.cpp:192-196); the refusal matrix explicitly includes the malformed leg. **Warning signs:** any `catch`-all defaulting to `NoEvidence`.

## Code Examples

### SC1/SC2 fork (consult placement; illustrative — final shape is planner's)
```cpp
// graphsync_dagsyncer.cpp, FetchNodeFromColdStorage (:780-856), after cold Get (:807)
// BEFORE Rehydrate (:816) — order is load-bearing (Pitfall 1 / anti-pattern):
if ( cold_read_hook_ != nullptr )
{
    switch ( cold_read_hook_->LookupPruneEvidence( cid ) )
    {
        case PruneEvidenceClass::Pruned:
            logger_->debug( "cold read: CID {} refused — node-local prune evidence", cid.toString().value() );
            return outcome::failure( Error::HISTORY_PRUNED_LOCALLY ); // TERMINAL — no Rehydrate, no peers
        case PruneEvidenceClass::Malformed:
            logger_->error( "cold read: CID {} prune evidence malformed — failing closed", cid.toString().value() );
            return outcome::failure( Error::COLD_STORAGE_CORRUPT );   // fail-closed class; distinct value is discretion
        case PruneEvidenceClass::NoEvidence:
            break; // fall through to the existing serve+Rehydrate path verbatim (SC2)
    }
}
cold_read_hook_->Rehydrate( cid, bytes );
```

### /prune/blk lookup (PruneEligibility home; mirrors LookupPrunedEntry discipline)
```cpp
// PruneEligibility.cpp — sibling of LookupPrunedEntry (:179-246); malformed => bad_message
outcome::result<PrunedBlockLookup> PruneEligibility::LookupPrunedBlockEntry( crdt::GlobalDB &db,
                                                                             const std::string &cid_string )
{
    crdt::GlobalDB::Buffer key;
    key.put( BuildPruneBlockMarkerKey( cid_string ) ); // "/prune/blk/" + cid
    auto marker = db.GetRaw( key );
    if ( marker.has_error() )
    {
        if ( marker.error() == storage::DatabaseError::NOT_FOUND )
        {
            return PrunedBlockLookup::NoEvidence;
        }
        return outcome::failure( marker.error() );
    }
    SGTransaction::PrunedBlockRecord record;
    if ( !record.ParseFromArray( marker.value().data(), static_cast<int>( marker.value().size() ) ) )
    {
        MarkerLogger()->error( "Pruned block marker for cid {} is malformed", cid_string );
        return outcome::failure( std::errc::bad_message ); // T-17-0502 discipline
    }
    return PrunedBlockLookup::Pruned; // presence IS the evidence; record = traceability (D-02)
}
```

### Walk matrix (D-05; replaces :452-458)
```cpp
if ( !retained && sealed )
{
    if ( /* /prune/blk evidence for cid */ )
    {
        ++progress.skipped_pruned;              // terminal prune boundary — bounded walk
        return outcome::success();
    }
    // No evidence: GC-evicted-or-unknown. getNode = cold chain FIRST (synchronous
    // Rehydrate; walk owns sealing after replay), peers second (bounded per-CID).
    // Exhaustion of BOTH cold and the per-CID peer budget => distinct walk-gap
    // error + progress.walk_gaps; the walk ABORTS Incomplete (never skips).
}
```

## D-06 Failover-Budget Derivation (directive 1)

**Recorded numbers (all verified this session unless cited):**

| Number | Value | Source | Verbatim quote |
|---|---|---|---|
| Walk block bound | 10000 | [VERIFIED: GeniusNode.hpp:1224] | `size_t bootstrap_walk_max_blocks_  = 10000; ///< Maximum distinct blocks per recovery walk.` |
| Walk retry bound | 8 | [VERIFIED: GeniusNode.hpp:1225] | `size_t bootstrap_walk_max_retries_ = 8;     ///< Maximum retries of non-empty incomplete walks.` |
| Root retry ladder | 8 | [VERIFIED: crdt_datastore.hpp:730] | `static constexpr uint32_t             MAX_FAILED_ROOT_RETRIES = 8;` |
| CID-failure suppression | 4 s | [VERIFIED: graphsync_dagsyncer.hpp:226] | `static constexpr std::chrono::seconds CID_FAILURE_SUPPRESSION{ 4 };` |
| Whole-fetch budget | 20 s | [VERIFIED: graphsync_dagsyncer.cpp:28] | `constexpr auto kTotalFetchTimeout = std::chrono::seconds( 20 );` |
| IN_PROGRESS per-peer give-up | 120 s | [VERIFIED: graphsync_dagsyncer.cpp:21] | `constexpr auto kInProgressRequestTimeout = std::chrono::seconds( 120 );` |
| RefusalFailover observed attempts | ≤ 8 | [CITED: 19-07-SUMMARY T-19-0701] | "mesh window asserts attempts bounded (<=8 RefusalFailover, <=4 PrunedMesh Phase B)" |
| PrunedMesh Phase B attempts | [1,4] | [CITED: 19-07-SUMMARY] | "attempts in [1,4]" |
| Walk suites on merged line | green, 8131 ms / 1026 ms | [CITED: 13-03-SUMMARY] | "ForcedBootstrapWalkRunsBeforeBlockchainIsReady 8131ms" |

**Derivation (prescriptive):**
- `kForcedWalkPeerFailoverPerCid = 8` — a named internal constant in the `getNode` route walk (or walk-callable parameter) bounding distinct peers consulted per CID. Derivation: the codebase's three independent 8-bounds converge (root ladder 8, walk retries 8, observed refusal-failover ≤8); PrunedMesh's [1,4] shows healthy meshes need well under it; suppression (4 s) already prevents immediate re-consultation, so a count bound composes with, not fights, the time bound.
- `kTotalFetchTimeout = 20 s` stays the wall-clock backstop (unchanged) — count bound for fairness/DoS, time bound for liveness.
- Walk-gap policy: **first gap aborts** (no threshold constant needed) — "aborts-never-skips" is categorical, not budgetary.
- Naming/values are internal constants (no config knobs — Phase 14 D-04 posture). Phase 17 SC2's probe validates or re-tunes against real ancestry-density numbers; both halves of the recorded 15↔17 dependency stay honored.

## A5 Caveat Re-Verification (directive 2)

**Develop's A5 record** [CITED: 19-07-SUMMARY key-decisions]: "The exact on-wire status was not directly observable from the test; transport logs interleaved 'RS_FULL_CONTENT but no blocks received' warnings on failed requests. Behavior asserted per T-19-0703" — `HasRecentCIDFailure`/`GetRequestStatus` are private; the classification was proven through public consequences (`IsOnBlackList` false + storage-deterministic refusal + the peer still serving fresh data).

**Merged-line status (this session):** the posture is UNCHANGED —
- The FAILED-branch classification plumbing exists and is private (`GetRequestStatus`, `IsConnectionFailureStatus` at graphsync_dagsyncer.cpp:547-571); `RecordCIDFailure` :1398 remains the public-behavior seam.
- The responder's honest don't-have is documented in-source: `ColdServeDagService::getNode` "returns UNCHANGED so the responder completes the request negatively NOW (RS_NOT_FOUND, the honest don't-have)" [VERIFIED: graphsync_dagsyncer.cpp:117-121 comment].
- No test-only observable for the wire status exists on the merged line.

**Phase 15 shape (prescriptive):** exercise the refusal on cold-enabled nodes by EXTENDING the merged-line `GlobalDBEraseRefusalFailoverTest` (:1044, `PrunedPeerRefusalFailsOverToServingPeer` :1116) with evidence-refusal legs, asserting the SAME public consequences (failover completes, no blacklist, storage-deterministic refusal, bounded attempts ≤ `kForcedWalkPeerFailoverPerCid`). If a wire-status observable is wanted, add a test-only static hook in the Phase-14 discipline (sibling of `SetColdUploadStateHookForTest`) — do NOT guess constants; record the observed value in the SUMMARY. Zero wire/proto changes stand.

## Phase 14 D-01 Single-CID Removal Set — Verification (directive 4)

**HOLDS on the current line.** [VERIFIED: TransactionManager.cpp:4718-4768, read this session]
- `EraseTransactionEntryWithMarker( tx_hash, stage_pruned_marker )` resolves `ResolveTransactionPathAndCID( tx_hash )` to ONE `path` + ONE cid string (:4737-4740) — "Path and CID always come from the SAME network".
- Exactly one marker pair: `std::optional<std::pair<crdt::GlobalDB::Buffer, crdt::GlobalDB::Buffer>> extra_entry;` (:4746) filled once from `PruneEligibility::BuildPruneMarkerEntry( tx_hash, path )` (:4749).
- Exactly one erase call: `globaldb_m->EraseEntry( path, cid, extra_entry )` (:4755) — one batch deletes the block's bytes + CRDT entries + raw-map entry + stages the marker.

**Consequence for D-01 here:** one erase = one CID = one `/prune/blk` marker. The widened vector carries exactly TWO pairs per TxPruner erase (`/prune/tx` + `/prune/blk`); the one-block-marker-per-erase premise is sound. Non-TxPruner callers (`EraseTransactionEntry`, stage=false) pass a 1-element vector (or nullopt) — signature change is mechanical at the two call sites (:4755, plus tests using `EraseEntry`).

## TEST-01 Fake Architecture (discretion item — recommendation)

**Recommendation: real-GlobalDB raw-surface seeding as PRIMARY; seam-level stub predicate as SECONDARY.**
- **Primary** — the Phase 14 D-08 journal-injection precedent scaled up: a real GlobalDB (real RocksDB, `SGNS_COLD_STORAGE` build, InMemory S3 fake via `SetColdStorageStackClientsForTesting`) with `/prune/tx`, `/prune/blk`, malformed variants, and journal states seeded directly onto the raw surface (`PutRaw`/`WritePrunedEntryForTest`-shaped helpers). The refusal matrix {hot}×{cold}×{evidence}×{serve, walk visit, erase-gate} is fixture composition over real stores: hot = put/erase; cold = spill or direct LocalBlockStore/S3 seeding; evidence = seeded marker rows. This is Tier-1 (fresh-clone-safe, no services) per Phase 14 D-09.
- **Secondary** — a stub `ColdReadFallback` (trivial once the interface carries `LookupPruneEvidence`) for syncer-layer classification suites where a full GlobalDB is disproportionate — the tri-state is then a table-driven return value.
- **Rationale:** the predicate reads real raw-store state; injection is faithful for evidence exactly as it was for journal state in Phase 14 ("the gate reads the journal, not the bytes, so injection is faithful" — same argument, new namespace). The stub covers the ungated-TU classification surface cheaply. Both back every SERVE/RECOVER/PRUNE suite without live services.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Cold chain serves bytes unconditionally (v1.1 Phase 9 READ-01) | Evidence-aware consult before Rehydrate | this phase | kills the resurrection gap |
| `!retained && sealed` walk skip (bootstrap branch) | Evidence matrix + bounded 4th quadrant | this phase | kills the GC-evicted conflation |
| `/prune/tx` only evidence (develop 19-05) | + `/prune/blk` CID-keyed O(1) refusal | this phase | block-level refusal without tx scans |

**Deprecated/outdated:** nothing on the merged line is obsoleted — `HasBlock`, `ApplyColdPrecedence`, `Rehydrate`, `RecordCIDFailure` are all preserved and extended-by-composition.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `PrunedBlockRecord` proto message addition is "not a wire change" under D-07 (node-local raw-store value, same class as `PrunedTransactionRecord`) | Pattern 4 | If ruled a wire change, D-02's record must become an opaque encoded buffer built by PruneEligibility (mechanically similar; small rework) |
| A2 | Guard/line ranges cited as "~" (guard 5 inner lines, HasBlock term boundaries) are within a few lines | Anchor table | Executor re-greps; no design impact |
| A3 | Named constant `kForcedWalkPeerFailoverPerCid = 8` placement inside `getNode` (vs walk-side wrapper) is acceptable to the planner | D-06 derivation | If walk-side only, `getNode` signature needs a budget parameter — larger change; planner decides |
| A4 | GATE-01 role facts unchanged by Phase 15 (Archive/Full never prune; predicate vacuously NoEvidence on them) | Predicate design | If roles changed since, predicate needs an explicit role flag (the alternate discretion shape) |
| A5-assumption | The responder's RS_NOT_FOUND-class status remains adequate refusal semantics for cold-enabled refusals (no new wire signal wanted) | A5 section | Contradiction would re-open D-07 — out of scope by lock |

All other claims in this research were verified in source this session or cited from committed planning artifacts.

## Open Questions (RESOLVED)

All four items were planner-discretion delegations; each is now locked in a phase plan's rulings — none remains an open unknown.

1. **Exact refusal `Error` enum value name** — `HISTORY_PRUNED_LOCALLY` vs `PRUNED_LOCALLY` vs similar; placement appended after `COLD_STORAGE_UNAUTHORIZED` (`graphsync_dagsyncer.hpp:50-66`, `uint8_t` — append-only is backward compatible). Discretion; planner picks. **RESOLVED — locked in 15-01:** `HISTORY_PRUNED_LOCALLY` (refusal) + `PRUNE_EVIDENCE_CORRUPT` (fail-closed malformed), both appended after `COLD_STORAGE_UNAUTHORIZED`.
2. **Pure virtual vs defaulting virtual on `ColdReadFallback::LookupPruneEvidence`** — one production implementor today; default-returning-NoEvidence is kinder to test stubs. Discretion. **RESOLVED — locked in 15-01:** pure virtual on `ColdReadFallback`; `ColdReadService` is the sole production implementor, and the empty-callable → NoEvidence posture covers the test-stub case.
3. **Whether the per-CID peer budget lands in `getNode` unconditionally or behind a walk-passed parameter** — see A3; both are safe; the unconditional bound changes general fetch behavior (in the safe direction — bounded failover is RECOVER-04's letter for recovery, arguably desirable globally). Planner + user checkpoint if unconditional. **RESOLVED — locked in 15-02:** walk-passed parameter — a `getNode(cid, peer_failover_budget)` overload with the 1-arg virtual delegating through an unbounded sentinel; the unconditional variant was ruled out precisely because it changes general fetch behavior (the flagged checkpoint condition therefore never arises).
4. **Erase-gate matrix legs scope** — SC5's "erase-gate" column rides the Phase 14 gate suites (`cold_prune_gate_test`) extended with `/prune/blk` assertions; whether those extensions live in the gate suite file or the new evidence-matrix suite is planner's call. **RESOLVED — locked in 15-03:** the erase-gate column extends the gate suite file (`cold_prune_gate_test.cpp`) while the product legs live in `cold_evidence_matrix_test.cpp` — the split follows each suite's fixture strengths.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Windows toolchain + CMake preset | all builds | ✓ | `SuperGenius/build/Windows/Release` (proven by Phase 14 evidence 2026-11-16) | — |
| ctest Tier-1 lane | TEST-01 suites | ✓ | `-C Release -L Tier1` (proven 14-01/14-03) | — |
| InMemory S3 fakes | hermetic cold legs | ✓ | `SetColdStorageStackClientsForTesting` + sgns-blockstore fault kit [VERIFIED: ColdStorageStack.cpp:57-70] | — |
| Live S3/MinIO | dev-gated smoke only | ✗ (runbook-deferred, v1.1 posture) | loud-skip pattern (`cold_prune_live_smoke_test`) |
| gtest filter infra | all suites | ✓ | `--gtest_filter`, `ASSERT_WAIT_FOR_CONDITION` | — |

**Missing dependencies with no fallback:** none — hermetic-first discipline covers all SC evidence; the live leg stays dev-gated Tier-2/3 by design.

## Security Domain

> `security_enforcement: true`, ASVS level 1, block_on high [VERIFIED: .planning/config.json workflow block].

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | no new auth surfaces |
| V3 Session Management | no | — |
| V4 Access Control | yes (node-local) | role-aware predicate (GATE-01: only Light nodes prune → only Light nodes refuse-on-evidence); fail-closed malformed evidence |
| V5 Input Validation | yes | marker records decoded via protobuf `ParseFromArray` with fail-closed on malformed (T-17-0502 discipline); CID keys content-addressed |
| V6 Cryptography | no new | CID verification stays inside the sgns-blockstore chain Get (never bypassed — the integrity control cited on `ColdReadFallback::Get`) |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Resurrection via cold bytes after deliberate erase | Tampering | evidence-before-Rehydrate consult; terminal refusal (SC1) |
| Resurrection via peers after refusal | Tampering | refusal terminal in `getNode` — no peer fall-through |
| Malformed marker forging silent refuse/serve | Tampering | `Malformed` → hard error, never a guess (Pitfall 7) |
| Failover storms on refusal fan-out | DoS | per-CID budget (D-06) + existing `CID_FAILURE_SUPPRESSION` + `RecordCIDFailure` (CID-scoped, never connection-blacklist) |
| Walk-gap silently validating partial history | Spoofing/Tampering | abort-never-skip; distinct walk-gap error + counter; walk finishes Incomplete |
| Information disclosure via pruned-vs-notfound distinction | Info Disclosure (accepted) | node-local, BIP-159-precedent distinction; no key material or user data in markers (hash/CID/generation only — D-03 logging discipline from 17-CONTEXT applies) |

## Sources

### Primary (HIGH confidence — read in source this session)
- `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` — :21-28, :41-67, :108-124, :334-634, :639-655, :705-748, :755-856, :858-881, :1113-1169, :1398-1424
- `SuperGenius/src/crdt/cold_read_fallback.hpp` — full interface + `ColdReadStatus` + `MapColdReadStatus`
- `SuperGenius/src/crdt/globaldb/globaldb.hpp` — :43, :482-549, :610; `globaldb.cpp` — :824-880, :1440-1587
- `SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp` — :57-140 (test-client override seam); `ColdStorageManager.cpp` — :1072-1076, :1317-1352
- `SuperGenius/src/crdt/impl/crdt_datastore.cpp` — :212-586; `crdt_datastore.hpp` — :67, :79-88, :730
- `SuperGenius/src/transaction/PruneEligibility.hpp` — :115-129, :342-348, :395-437; `PruneEligibility.cpp` — :156-284
- `SuperGenius/src/transaction/TransactionManager.cpp` — :4718-4780
- `SuperGenius/src/account/GeniusNode.cpp` — :443-480, :1617-1703; `GeniusNode.hpp` — :1223-1225, :1733
- `SuperGenius/src/transaction/TxPruner.cpp` — :77-130, :277-310, :397-404
- `SuperGenius/src/account/proto/SGTransaction.proto` — :66-76
- `SuperGenius/test/src/crdt/globaldb_erase_test.cpp` — :90, :521, :1044, :1116; `test/src/blockchain/node_startup_test.cpp` — :543-573

### Secondary (MEDIUM confidence — committed planning artifacts)
- `SuperGenius/.planning/phases/19-pruned-node-survival-recovery-hardening/19-07-PLAN.md` + `19-07-SUMMARY.md` + `19-RESEARCH.md` (A5; RefusalFailover/PrunedMesh numbers; gossip-cache lessons)
- `.planning/research/ARCHITECTURE-v1.2-rocksdb-backup.md` §(b), §(c), §(d), §3.1-3.4
- `.planning/workstreams/rocksdb-backup/phases/13-*/13-03-SUMMARY.md` (merged-line walk-suite evidence)
- `.planning/workstreams/rocksdb-backup/milestones/v1.1-phases/12-*/12-01-SUMMARY.md` (resurrection counter-test precedents)
- `.planning/workstreams/rocksdb-backup/phases/14-*/14-CONTEXT.md` + `14-*-PLAN.md` (D-01 removal-set; D-08/D-09 test posture; Windows/Release commands)

### Tertiary (LOW confidence)
- none — no claim in this research rests on an unverified secondary source

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new dependencies; every mechanism verified in source
- Architecture: HIGH — both bug sites, the injection seam, and all five ordering guarantees read line-by-line this session
- Pitfalls: HIGH — each grounded in a code observation or a committed SUMMARY record

**Research date:** 2026-11-17
**Valid until:** 2026-12-17 (stable — merged line `095c8c502`; invalidate early if Phase 16 work starts on `EraseEntry`)
