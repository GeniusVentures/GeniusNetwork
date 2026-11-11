# Phase 9: Cold Read Fallback — Local Reads & Graphsync Serving - Context

**Gathered:** 2026-10-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Cold data becomes readable. This phase delivers:

1. **READ-01 — local read fallback chain:** a hot-store miss resolves hot → LocalBlockStore → S3BlockStore → peers, CID-verified at every cold tier, re-cached into the hot store before returning; under transport faults the failure surfaces as `TemporarilyUnavailable`, never `NotFound` — a fault-injected test proves no NotFound-shaped result escapes the seam
2. **READ-02 — graphsync async cold-serve:** a peer request for a CID not held locally performs an async cold fetch on a bounded dedicated executor with a deadline below the peer stream timeout, off the responder's inline path (the documented whole-node-freeze hazard at `graphsync_dagsyncer.cpp:549-553`), CID-verifies, then serves; during an s3d outage the responder still serves local content and never freezes libp2p stream processing
3. **SC3 — honest miss taxonomy at the seam:** the first-class `BlockStatus` mapping holds — no peer-blacklist writes and no `RecordCIDFailure` from s3d blips; `Corrupt` attributes its source; `HasBlock` is cold-aware in the local-only sense (see D-08/D-09)
4. **SC4 — dedicated rehydrate path:** restored blocks enter through a path that writes bytes + resolved marker only; zero pubsub broadcast, zero `AddRoute`, heads unchanged (no restore re-entry storms)
5. **SC5 — hermetic Tier-1 fallback tests** (fake S3 + fault injection: taxonomy honesty, responder non-blocking, rehydrate silence) in the Phase-7 fail-closed lane

Out of this phase: flush-gated durability advancement (Phase 10), retention GC (Phase 11), cross-actor fault races / fresh-clone proof (Phase 12), any new config schema surface (D-12 — compile-time only), mobile legs (Future — option stays OFF).

Requirements: READ-01, READ-02 (TEST-01 lane extension rides along per the roadmap's cross-cutting note).

</domain>

<decisions>
## Implementation Decisions

### Local-read fallback chain (READ-01 / SC1)
- **D-01:** **Cold before peers** — the local read chain is hot datastore → LocalBlockStore → S3BlockStore → peers. Deterministic resolution with no peer dependency; this is the required shape for Phase-11 GC-evicted CIDs (GC-03 end-to-end retrieval) and the literal reading of READ-01 ("miss the hot datastore → fetch from the blockstore"). Peers-before-cold was rejected: GC-evicted reads would pay a full peer-failure timeout before S3 — **Reversibility:** costly — the chain order is the read-path contract SC1's fault-injection evidence and Phase-11's GC-03 retrieval proofs are stated over; reordering after Phase 11 ships changes what an evicted-CID read costs
- **D-02:** **Both cold tiers are read sources** — LocalBlockStore (cold dir, same disk) is consulted before S3; a cold-dir hit avoids the S3 round trip. The library's tiering (`LocalBlockStore::Get` → `S3BlockStore::Get`, both CID-verifying) maps directly — **Reversibility:** reversible — tier selection is internal chain mechanics
- **D-03:** **Cold transport failure falls through to peers** — when the cold tiers are reachable-but-failing (s3d down, network fault) during a local read, the failure is logged + counted and the chain continues to peers; only failure across all sources surfaces, classified honestly (definitive absence at both cold tiers + peers = NotFound; transport = TemporarilyUnavailable). Peers can mask cold-store state, so Phase-12's soak carries the outage-signal visibility — **Reversibility:** costly — fall-through-vs-fail-fast is the observable error contract the SC1 fault-injection suite tests
- **D-04:** **Always re-cache** — every successful cold fetch (either tier) writes back into the hot store through the dedicated rehydrate path (SC4) before the read returns; spill re-journals implicitly since Phase-8 spill-on-write is the default write path. S3-only re-cache was rejected: Local-tier reads would keep paying the cold lookup forever — **Reversibility:** reversible — re-cache policy is internal to the chain

### Cold-serve degradation (READ-02 / SC2 — the roadmap's named planner decision)
- **D-05:** **Don't-have + re-warm** — on deadline expiry the responder completes the peer's request negatively now (the peer's own retry ladder fails over), and a background re-warm continues fetching the block into the hot store so the NEXT request for that CID is served locally. Bounded responder work per request; matches SC2's "conscious don't-have+re-warm degradation if the budget is exceeded" branch. Hold-to-deadline was rejected: a slow s3d inflates concurrent held requests across many peers — **Reversibility:** costly — the degradation shape is the responder's peer-facing contract the SC2 outage tests bind
- **D-06:** **Cold-serve is on whenever the blockstore section is enabled** — no extra activation switch; the deadline + bounded executor are the safety mechanisms and the Phase-9 honesty tests (responder-freeze regression, s3d-outage serving) are the evidence bar. Matches the Phase-7/8 single-switch posture: blank config = nothing constructed = today's behavior — **Reversibility:** costly — adding a sub-gate after ship splits the activation contract operators document against
- **D-07:** **Coalesced re-warm on the same bounded executor** — one in-flight re-warm per CID; concurrent deadline-missed requests for the same CID attach to the in-flight re-warm or find it hot. The re-warm carries its own (longer) budget. Independent-per-miss was rejected: a peer hammering the same cold CID would multiply S3 fetches — **Reversibility:** reversible — coalescing mechanics behind internal state

### HasBlock cold-awareness (SC3)
- **D-08:** **HasBlock stays local-only** — hot check then cold-dir presence check; NEVER an S3/network lookup from `HasBlock`. SC3's "retrievable before deadline" half is honored by the fetch paths (the graphsync cold-serve path and the local-read chain), which are the paths that actually fetch. `HasBlock` runs on the pubsub receive path (`pubsub_broadcaster_ext.cpp:632`) and CRDT datastore (`crdt_datastore.cpp:706, 1881`) — exactly where the documented whole-node-freeze hazard lives; a full cold lookup there would re-open it — **Reversibility:** costly — this interpretation of SC3 is what the whole-node-freeze regression test (SC2) and the HasBlock tests bind; loosening it re-exposes the freeze hazard
- **D-09:** **Cold-dir check slots after the hot check misses, gated on cold storage enabled** — disabled deployments keep byte-identical HasBlock (the Phase-7 SC2 bar). `LocalBlockStore::Has` is a RocksDB point lookup — fast enough to keep every caller freeze-proof — **Reversibility:** reversible — check placement is internal

### Config surface
- **D-12:** **Compile-time only — no new config knobs this phase** — serve deadline, executor size, and re-warm budget are compile-time defaults; Phase-8 D-05's minimal-knob posture carries unchanged (nothing exposed until the milestone-Future metrics surface justifies it). SC2's latency-budget measurement documents the built-in default instead of a knob. The `blockstore` schema (Phase 7 D-01/D-02 + Phase 8 D-06 `backpressure` sub-object) is unchanged — **Reversibility:** reversible — adding a `blockstore.read` sub-object later is an additive schema extension

### The Agent's Discretion
- Exact compile-time default values (serve deadline vs peer stream timeout headroom, executor size, re-warm budget) — researcher/planner derive from the SC2 latency-budget measurement; they become the documented built-in defaults of D-12
- Where the fallback chain lives: extending the Phase-8 `BlockStoreBackedIpfsDatastore` decorator's `Get`/read path vs `GraphsyncDAGSyncer::GetNodeWithoutRequest` vs both — planner's call, constrained by SC3's "mapping holds at the seam"
- Executor mechanics (thread-pool shape, queue bounds, shutdown join ordering relative to the D-10/D-11 drainer lifecycle) — planner designs; bounded + never the responder's inline path are the constraints
- Negative-response semantics toward the peer on deadline expiry (graphsync partial/final response shape) — researcher confirms what the graphsync layer supports
- The exact `BlockStatus{StatusClass, BlockSource}` → SuperGenius error mapping table at the seam (SC3's table) — researcher enumerates the library's status codes; the honesty rules (no blacklist, no RecordCIDFailure, Corrupt attributes source, TemporarilyUnavailable-vs-NotFound) are the constraints
- Rehydrate path mechanics: how bytes + resolved marker compose with the hot-store write and what "resolved marker" is in library terms — researcher confirms against the library's rehydrate/journal contracts
- Whether `GetNodeWithoutRequest` gains the same cold-chain awareness as the decorator read path (and how pubsub-received CIDs interact with D-08) — planner decides per call-site audit
- How the SC2 whole-node-freeze regression test is built (hermetic, Tier-1, InMemoryS3Client + injected latency/faults) and how the latency-budget benchmark measures cold-serve without live endpoints
- Exact log-message wording (constraint: s3d blips must be distinguishable from peer failures in logs)
- Tier-1 test target registration mechanics (Phase-7 lane, `ctest -L Tier1 --no-tests=error`, tier-label discipline)
- In-flight cold-fetch coalescing for concurrent local reads of the same CID (mirror of D-07 for the read path) — planner's call

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream planning (v1.1)
- `.planning/workstreams/rocksdb-backup/REQUIREMENTS.md` — READ-01, READ-02 (this phase's letters); GC-03 (the Phase-11 retrieval guarantee D-01 exists to serve); Out of Scope table
- `.planning/workstreams/rocksdb-backup/ROADMAP.md` — Phase 9 goal, 5 success criteria, 3 suggested plan waves, research note (`--research-phase` recommended — responder-side async cold serving is novel in this codebase)

### Prior phase context (binding decisions this phase builds on)
- `.planning/workstreams/rocksdb-backup/phases/08-spill-on-write-background-drainer/08-CONTEXT.md` — the decorator this phase extends for reads, ColdStorageManager ownership/lifecycle (D-10/D-11), backpressure contract (D-01..D-04), config-knob posture (D-05) this phase inherits via D-12
- `.planning/workstreams/rocksdb-backup/phases/07-supergenius-build-wiring-config-gate/07-CONTEXT.md` — the `blockstore` config schema + tri-state semantics + env surface; the byte-identical disabled bar (SC2) D-09 preserves
- `.planning/workstreams/rocksdb-backup/phases/06-sgns-blockstore-v1-1-library-prerequisites-blake2b-256-cids/06-CONTEXT.md` — installed `OpenMinioS3Client` factory contract and blake2b CID acceptance the read chain relies on

### Research (v1.1, 2026-10-22)
- `.planning/research/SUMMARY-rocksdb-backup-2026-10-22.md` — the seam synthesis; single-decorator read/write framing
- `.planning/research/PITFALLS-rocksdb-backup-2026-10-22.md` — silent-disable and logging pitfalls; the freeze-hazard class
- `.planning/research/STACK-rocksdb-backup-2026-10-22.md` — file:line citations for the seam and the responder path

### Code being modified (read before editing)
- `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` — the responder: `HasBlock` (:511), `GetNodeWithoutRequest` (:519), the local-only-responder rationale + freeze-hazard comment (:549-553), `RecordCIDFailure`/`BlackListPeer` call sites the taxonomy must not trip (:360-:419), `BlockReceivedCallback` (:607)
- `SuperGenius/src/crdt/graphsync_dagsyncer.hpp` — DAGSyncer interface surface (`HasBlock`, `getNode`, `RequestProgressCallback`)
- `SuperGenius/src/crdt/globaldb/BlockStoreBackedIpfsDatastore.cpp` — the Phase-8 decorator whose read path this phase extends; existing BlockStatus logging precedent (:67)
- `SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp` — the Phase-8 stack factory; BlockStatus detail logging (:77)
- `SuperGenius/src/crdt/globaldb/globaldb.cpp` — the `IpfsDatastore` construction seam in `GlobalDB::New`, `Shutdown()` ordering the cold-serve executor's join slots into (Phase-8 D-10/D-11 pattern)
- `SuperGenius/src/crdt/globaldb/pubsub_broadcaster_ext.cpp` — `HasBlock` caller on the pubsub receive path (:632) — the freeze-sensitive call site behind D-08
- `SuperGenius/src/crdt/impl/crdt_datastore.cpp` — `HasBlock` callers (:706, :1881); the CRDT read path the fallback chain serves
- `SuperGenius/src/crdt/dagsyncer.hpp` — the `DAGSyncer` interface contract

### Library surface being consumed (frozen v1.0 + Phase 6)
- `thirdparty/sgns-blockstore/include/sgns-blockstore/BlockStore.hpp` — the read contract: `Get` (CID-verified, NotFound semantics documented), `Has`, `GetSize`; outcome::result<T, BlockStatus> everywhere
- `thirdparty/sgns-blockstore/include/sgns-blockstore/BlockStatus.hpp` — `StatusClass` + `BlockSource` attribution — SC3's mapping table is stated over these codes
- `thirdparty/sgns-blockstore/include/sgns-blockstore/LocalBlockStore.hpp` — Local-tier `Get`/`Has`, upload-state journal (`MarkUploadedAccepted`/`MarkUploadedDurable`/`GetUploadState`) the rehydrate path's "resolved marker" likely maps onto
- `thirdparty/sgns-blockstore/include/sgns-blockstore/S3BlockStore.hpp` — S3-tier `Get`
- `thirdparty/sgns-blockstore/include/sgns-blockstore/FaultController.hpp` + `thirdparty/sgns-blockstore/include/sgns-blockstore/S3Client.hpp` — `FaultKind`/`S3FaultKind` scriptable faults driving SC1/SC5 fault injection (S3Op surface :120)
- `thirdparty/sgns-blockstore/test/` — the `InMemoryS3Client` fake every hermetic Tier-1 fallback test reuses
- `thirdparty/sgns-blockstore/docs/testing-tiers.md` — tier contract; Tier-1 fail-closed lane discipline

### Authoritative design
- `supergenius-sharded-ipld-cache-architecture.md` (workspace root) — the cold-read fallback design intent; eviction ≠ delete invariant (GC-03 lineage); the read-path vertical this phase delivers

### Conventions & testing
- `Coding Standards.md` (workspace root) — C++ style for the executor, mapping table, and decorator read-path code
- `.planning/codebase/TESTING.md` — verification-inside-`build/<Platform>/<Config>`-tree rule; `addtest()` registration; Tier-1 lane wiring
- `.planning/codebase/INTEGRATIONS.md` — IPFS/graphsync + RocksDB integration context

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Phase-8 `BlockStoreBackedIpfsDatastore` decorator + `ColdStorageStack`** — already wraps the inner datastore at the `GlobalDB::New` seam with both tiers constructed; the read chain extends this same object — no new seam
- **`ColdStorageManager` lifecycle (Phase-8 D-10/D-11)** — the membership/ownership/shutdown-join pattern the cold-serve executor and re-warm tasks slot into alongside the drainer
- **Library read contracts** — `LocalBlockStore::Get`/`S3BlockStore::Get` CID-verify internally; `Has` is a cheap point lookup; `BlockStatus{StatusClass, BlockSource}` gives source attribution for free
- **`FaultController`/`S3FaultKind` scriptable faults + `InMemoryS3Client`** — the fault-injection kit the SC1 honesty suite and SC5 tests are built on
- **Phase-7 Tier-1 hermetic lane** — the fail-closed `ctest -L Tier1` lane every Phase-9 fallback test registers in

### Established Patterns
- Local-only-responder discipline (`graphsync_dagsyncer.cpp:549-553`) — the documented freeze hazard; Phase 9's async cold fetch must respect it via the bounded executor + deadline, never `shared_from_this()` fetch-on-serve
- Active-accessor pattern under `lifecycle_mutex_`; ordered shutdown joins (backup loop → drainer → executor) per Phase-8 D-10/D-11
- Rate-limited BlockStatus logging (`BlockStoreBackedIpfsDatastore.cpp:67`, `ColdStorageStack.cpp:77`) — the cold-read failure logging extends it

### Integration Points
- Decorator `Get`/read path — where the hot → Local → S3 chain lands (D-01..D-04)
- `GraphsyncDAGSyncer` responder path — where the async cold fetch + don't-have + re-warm serve shape lands (D-05..D-07); `HasBlock` gains the gated cold-dir check (D-08/D-09)
- `GlobalDB::Shutdown()` — gains the cold-serve executor join in the established ordering

</code_context>

<specifics>
## Specific Ideas

- The fallback chain, in order: **hot datastore → LocalBlockStore → S3BlockStore → peers** (D-01/D-02)
- Taxonomy rule of thumb: **definitive absence everywhere = NotFound; anything transport-shaped = TemporarilyUnavailable**; cold failures never write peer blacklists and never call `RecordCIDFailure` (SC3)
- Rehydrate = bytes + resolved marker only — no pubsub broadcast, no `AddRoute`, heads untouched (SC4); spill re-journaling rides Phase-8's write path implicitly
- One in-flight re-warm per CID, later requests attach or find it hot (D-07)

</specifics>

<deferred>
## Deferred Ideas

- A `blockstore.read` config sub-object (serve deadline / executor knobs) — deferred to the milestone-Future metrics surface per Phase-8 D-05 posture; this phase is compile-time only (D-12)
- Cold-serve latency metrics / per-CID cold-fetch telemetry — milestone-Future metrics list
- Read-path per-CID in-flight coalescing beyond what the planner deems necessary — candidate for later hardening if SC2 evidence shows stampede behavior

### Reviewed Todos (not folded)
- `2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md` — "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" (area: testing) matched Phase 9 by keyword only (path); standing unrelated ruling from Phases 6-8 carried forward — stays a backlog todo for its own task/phase

</deferred>

---

*Phase: 9-Cold Read Fallback — Local Reads & Graphsync Serving*
*Context gathered: 2026-10-26*
