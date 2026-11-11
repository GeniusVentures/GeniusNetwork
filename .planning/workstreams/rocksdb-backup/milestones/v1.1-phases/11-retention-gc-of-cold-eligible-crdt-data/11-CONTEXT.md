# Phase 11: Retention GC of Cold-Eligible CRDT Data - Context

**Gathered:** 2026-10-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Cold-eligible CRDT data past retention is evicted locally — never deleted remotely, never touching tombstones or CRDT metadata — behind the two-phase durability + non-reachability gate, with evicted CIDs still retrievable end-to-end and the live s3d E2E evidence committed. This phase delivers:

1. **GC-01 / SC1 — retention policy scan:** a configurable retention age in `crdt_config.json` identifies cold-eligible CIDs (`spilled-CID index ∩ age-past-retention ∖ head-reachable ∩ Durable`); policy evaluation provably never enumerates or writes tombstone/CRDT-metadata keyspaces; protected namespaces (heads, genesis, current-epoch pointers) are pinned — guard test
2. **GC-02 / SC2 — two-phase eviction:** mark-as-evicting (visible to readers and drain snapshots) → grace → physical delete; unit-atomic across block bytes + resolved marker + set rows; `DeleteCIDBlock` LRU invalidation keeps `HasBlock` honest; a bounded disposed-CID marker yields authoritative `NotFound` (re-delivery scope only) plus re-broadcast dedup; tombstones and CRDT metadata are never purged in v1.1 (guard test + SPEC scope boundary)
3. **GC-03 / SC3 — evicted-CID retrievability:** a GC-evicted CID remains retrievable end-to-end — both a graphsync request and a local read resolve from the blockstore, CID-verified — hermetic proof in the Tier-1 lane
4. **TEST-03 / SC4 — live tier (dev-gated, never in CI):** the live s3d spill → GC → retrieve E2E with committed evidence artifacts, plus the MinIO-binary opt-in roundtrip
5. **SC5 — epoch watermark record:** computed and stored (computation only — nothing is deletion-gated on it in v1.1), with per-pass reclaimed counts/bytes and a dry-run mode

Out of this phase: epoch-based deletion compaction / tombstone purging (v2+ — v1.1 is eviction-only), cross-actor fault races / resurrection counter-test / fresh-clone proof (Phase 12), mobile legs (Future — option stays OFF), any change to the GlobalDB backup engine (out of scope milestone-wide).

Requirements: GC-01, GC-02, GC-03, TEST-03.

</domain>

<decisions>
## Implementation Decisions

### Retention age evidence & activation (GC-01)
- **D-01:** **Wall-clock age from the journal/spill timestamp** — each spilled CID's journal timestamp is the age evidence; the operator mental model is "keep N days", matching GC-01's literal "age threshold in `crdt_config.json`". The researcher verifies whether the spilled-CID index/journal records a usable timestamp today and adds one additively if not. Clock skew only shifts eligibility timing — the durability + non-reachability gates keep eligibility safe, and eviction is recoverable via GC-03. Priority-height watermarks (SC5's epoch record still gets computed/stored per SC5) and app-level horizons were rejected as the primary evidence: height-distance is not operator-intuitive and the height→time mapping is app-dependent — **Reversibility:** costly — the evidence basis binds the eligibility semantics, the SC1 guard tests, and operator docs; switching evidence later re-opens the policy contract
- **D-02:** **Explicit opt-in activation** — `blockstore.retention` absent → no GC actor constructed, byte-identical behavior (Phase-7 tri-state posture). Present → GC runs. A destructive feature gets a deliberate operator act, same shape as the blockstore gate itself. Default-on-with-age was rejected: every spilling deployment would start deleting local bytes without operator action — **Reversibility:** costly — the activation contract is what operators document against; changing default-on later is an operator-facing behavior change
- **D-03:** **Dry-run is a config flag** — `dry_run` inside `blockstore.retention` (exact name agent discretion): a persisted observe-only posture. Same evidence surface either way (logs + per-pass metrics); the delete step is simply suppressed. The operator validates eligibility decisions for as long as they want before arming real eviction — **Reversibility:** reversible — a config flag, additive
- **D-04:** **Age key required when `retention` is present** — `blockstore.retention` present but no age key → loud startup failure. No operator unknowingly inherits a built-in eviction age they never chose; a destructive default must be typed, not implied. Unknown keys inside stay loud per Phase-7 strictness — **Reversibility:** costly — required-key semantics bind the node parser, the wallet asset, and operator docs (same class as Phase-7 D-02 / Phase-8 D-06)

### Reachability walk & GC scheduling (GC-01)
- **D-05:** **Full fresh walk each pass** — every GC pass walks the DAG from `CrdtHeads::GetList` to fresh completion; no persisted reachability state exists to go stale. Correctness is trivially auditable and eviction is destructive, so evidence freshness beats cleverness. The O(history) cost is accepted: passes are infrequent, run off the write path, and are batched with a resumable cursor (the roadmap's "batched off `io_`"). Persisted reachable-sets were rejected: a stale/missing mark is a wrongful-eviction hazard (the unsafe failure direction) and the mark keyspace would itself need GC; bloom filters were rejected: deletion would rest on probabilistic evidence and the rebuild is a full walk anyway — **Reversibility:** costly — freshness-as-correctness is the model the SC1 guard tests and the wrongful-eviction safety argument are stated over; a cached design later re-opens that proof
- **D-06:** **Dedicated GC thread** — own thread mirroring the twice-proven backup-loop/drainer pattern (never `io_`, never the pubsub asio context) with its own stop + join slot in the `GlobalDB::Shutdown` ordering. A multi-second walk must not stall drain/flush advancement, and GC health stays independent. The staging-health flag (Phase-10 D-12) gates its tick; the D-13 on-demand stats refresh (Phase-10) is consulted before inhibition. Riding the drainer was rejected (long walks delay durability advancement, couple two health domains); a bounded executor was rejected (walk steps are sequential/cursor-coupled — parallelism buys little and queue bounds become accidental throttles) — **Reversibility:** costly — the lifecycle and shutdown-join ordering bind the interplay tests (same class as Phase-10 D-02)
- **D-07:** **Interval knob + documented default** — a `gc_interval_ms`-style cadence knob in `blockstore.retention` (exact name agent discretion) with a documented built-in default, matching the Phase-8 D-05/D-06 posture (cost-relevant cadence knobs earn exposure) and the Phase-10 D-11 flush-cadence precedent. The staging-health gate applies per tick; dry-run uses the same cadence. Compile-time-only was rejected: walk cost vs reclaimed bytes is a real operator tradeoff next to retention age; adaptive triggers were rejected: trigger conditions become untestable scheduling policy — **Reversibility:** reversible — knob mechanics behind documented defaults
- **D-08:** **Heads snapshot at pass start + per-CID re-check at mark** — the pass walks against a heads snapshot taken at pass start (its universe), and before any CID transitions to evicting, its non-reachability is re-verified against CURRENT heads as a cheap point check. Mirrors Phase-10 D-03's snapshot-at-initiation precedent. The grace window (D-13/D-14) is pure safety margin, never the only correctness line. Grace-only closure was rejected (grace duration would become a correctness parameter); publish fences were rejected (couples the GC pass to the write path's mutex — the inline-hold hazard the drainer design exists to avoid) — **Reversibility:** costly — this is the eligibility-correctness contract the SC1/SC2 guard tests are stated over; loosening it re-opens the mid-walk race

### Disposed-CID markers (GC-02)
- **D-09:** **Markers live in the library** — a disposed-CID record (column family or keyspace) inside sgns-blockstore's `LocalBlockStore` RocksDB. The library already owns the block + journal keyspaces and `EvictLocal`, so block-bytes + resolved-marker + disposed-marker atomicity is a single-store RocksDB batch, and genius-tube gets the same primitive for free (Phase-10 D-05 facade precedent). Node-side key-prefixes were rejected (eviction atomicity would span two stores and the marker is node-local policy duplicating a library primitive); a separate store was rejected (a third lifecycle + crash-consistency story for a bounded record set) — **Reversibility:** costly — the library's public API surface is a published contract consumed by SuperGenius and genius-tube; re-homing later is a deprecation
- **D-10:** **Bound = count cap + marker age, whichever trims first** — a max-marker-count cap AND a marker max-age. Bounded memory under re-delivery storms and bounded staleness for quiet histories. A trimmed CID that re-arrives is simply re-learned (re-journal → re-spill → re-drain); the remote copy still exists, so re-learning is safe. Both values are documented built-in defaults; knob exposure per Phase-8 D-05 minimalism is agent discretion — **Reversibility:** reversible — bound mechanics behind built-in defaults
- **D-11:** **Re-broadcast dedup extends `HasBlock`** — the disposed-marker lookup slots into `HasBlock` after the cold-dir check (the same RocksDB-point-lookup class as Phase-9 D-09 — freeze-safe, no network). A marker hit means "already integrated": pubsub re-delivery drops at the existing call sites (`pubsub_broadcaster_ext.cpp:632`, `crdt_datastore.cpp:706/:1881`) with zero new call-site audits; on the responder path `HasBlock=true` composes with the Phase-9 cold-serve chain (`GetNode` → decorator `Get` → cold fetch). `HasBlock`'s meaning extends to "held locally OR cold-dir OR known-disposed". Receive-path-only checks were rejected (other re-entry points miss the dedup and every future call site must remember) — **Reversibility:** costly — the extended `HasBlock` meaning becomes the dedup contract on the freeze-sensitive pubsub receive path (same class as Phase-9 D-08)
- **D-12:** **Split semantics: `NotFound` is a re-delivery concept only** — authoritative NotFound/skip applies only to the pubsub/CRDT dedup path (marker hit = already integrated, drop). Direct reads — local read or graphsync serve for a disposed CID — always resolve through the Phase-9 cold chain (Local tier → S3, CID-verified, re-cache). NotFound never escapes a read path for a disposed CID; the GC-03 guard tests state both halves. NotFound-everywhere was rejected: it contradicts GC-03's "remains retrievable end-to-end" letter and makes the GC-03 E2E test impossible — **Reversibility:** costly — the NotFound-vs-cold-fetch split is the observable error contract GC-03's E2E and taxonomy tests are stated over

### Two-phase eviction mechanics (GC-02)
- **D-13:** **Grace duration is a config knob with a documented default** — the mark→delete grace lands as a knob in `blockstore.retention` (exact name agent discretion). Operators with bursty re-delivery patterns can widen it. Grace is a safety margin, not a correctness parameter (D-08/D-14 carry correctness), but exposure was chosen over the Phase-9 D-12 compile-time posture — **Reversibility:** costly — field paths bind the node parser, the wallet asset, and operator docs (same class as Phase-8 D-06)
- **D-14:** **Delete-time re-check + cancel** — physical delete re-verifies non-reachability against current heads immediately before the destructive batch (the same cheap point check as at mark). Reachable-again → cancel: clear the mark, keep the bytes, the CID returns to normal. Two correctness lines (mark + delete) with the grace window between them for detection; the deletion decision is always made on fresh evidence. Grace-only closure was rejected (a real check→delete race whose width equals the grace); event-driven cancel was rejected (pubsub re-delivery ≠ reachability — quiet local relinks fire nothing) — **Reversibility:** costly — the deletion-correctness contract the SC2 fault tests bind
- **D-15:** **Evicting marks are in-memory** — GC-thread state surfaced via the status getter; only the terminal disposed marker persists. Crash mid-grace → marks vanish, nothing was deleted, the next pass re-walks and re-marks from scratch. No stale-mark recovery or reconciliation code exists; fresh-walk correctness (D-05) makes the intermediate state disposable. Persisted marks were rejected (a third journal state plus recovery machinery for a short window — the Phase-8 D-12 reconciliation cost without its necessity) — **Reversibility:** reversible — internal state posture; persistence could be added later additively
- **D-16:** **Library-atomic destructive batch, then idempotent hot-store cleanup** — the destructive step is ONE single-store RocksDB batch in the library (block bytes + resolved marker + disposed marker together); hot-store set-row removal follows as an idempotent cleanup step. A crash between them leaves orphaned hot bytes that still count as present → the next pass re-evicts them (under-eviction direction — safe; the remote copy + GC-03 retrieval make leftovers harmless). Mirrors the Phase-8 journal-then-drain split-store discipline. Hot-first ordering was rejected (the crash window pays needless re-spill work); write-ahead intent records were rejected (machinery the safe-direction analysis does not require) — **Reversibility:** costly — the crash-consistency story the SC2/fault-injection tests bind

### The Agent's Discretion
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

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream planning (v1.1)
- `.planning/workstreams/rocksdb-backup/REQUIREMENTS.md` — GC-01, GC-02, GC-03, TEST-03 (this phase's letters); Out of Scope table (tombstones never purged in v1.1; epoch-based deletion compaction is v2+)
- `.planning/workstreams/rocksdb-backup/ROADMAP.md` — Phase 11 goal, 5 success criteria, 4 suggested plan waves, research note (`--research-phase` recommended — the most novel phase; no proven upstream recipe: go-ds-crdt ships no tombstone GC, PurgeDAG is admin-only and needed a follow-up fix)

### Prior phase context (binding decisions this phase builds on)
- `.planning/workstreams/rocksdb-backup/phases/10-flush-gated-durability-advancement/10-CONTEXT.md` — the durability gate this phase's eviction consults (D-09 per-CID `GetUploadState` pass-through, D-10 gate = `UploadedDurable` compile-time), the staging-health predicate + on-demand refresh the GC inhibitor consumes (D-12/D-13), the status-getter surface GC extends (D-08)
- `.planning/workstreams/rocksdb-backup/phases/09-cold-read-fallback-local-reads-graphsync-serving/09-CONTEXT.md` — the cold-before-peers read chain (D-01..D-04) GC-03 retrievability rides; `HasBlock` local-only semantics + cold-dir check (D-08/D-09) that D-11 extends; rehydrate silence (SC4)
- `.planning/workstreams/rocksdb-backup/phases/08-spill-on-write-background-drainer/08-CONTEXT.md` — the spilled-CID journal the retention scan enumerates, `ColdStorageManager` ownership/lifecycle (D-10/D-11) the GC thread joins alongside, config-knob posture (D-05/D-06: the retention sibling sub-object was reserved here)
- `.planning/workstreams/rocksdb-backup/phases/07-supergenius-build-wiring-config-gate/07-CONTEXT.md` — the `blockstore` config schema, tri-state semantics, strictness, and wallet-asset parity D-02/D-04 inherit

### Research (v1.1, 2026-10-22)
- `.planning/research/SUMMARY-rocksdb-backup-2026-10-22.md` — the seam synthesis; the v1.1 GC-shape decision (local-tombstone/eviction-only, bounded disposed-CID markers, tombstones/metadata never purged)
- `.planning/research/PITFALLS-rocksdb-backup-2026-10-22.md` — silent-disable and logging pitfalls
- `.planning/research/STACK-rocksdb-backup-2026-10-22.md` — file:line citations for the seam and backup-loop pattern

### Library surface being consumed/extended (frozen v1.0 + Phases 6/10)
- `thirdparty/sgns-blockstore/include/sgns-blockstore/LocalBlockStore.hpp` — the journal + block keyspaces D-09's disposed-CID record joins; `UploadState` enum, `GetUploadState`, `MarkUploadedDurable`, `GetPendingUploads`, `EvictLocal` (whose v1.0 warning names exactly this milestone's durability-gated eviction)
- `thirdparty/sgns-blockstore/include/sgns-blockstore/BlockStore.hpp` + `BlockStatus.hpp` — the read/status contracts and the taxonomy D-12's split semantics are stated over
- `thirdparty/sgns-blockstore/include/sgns-blockstore/Durability.hpp` — the durability-level states the eviction gate consults
- `thirdparty/sgns-blockstore/test/` — the `InMemoryS3Client` + `FaultController` fault kit every hermetic Tier-1 GC test reuses
- `thirdparty/sgns-blockstore/docs/testing-tiers.md` — tier contract; Tier-1 fail-closed lane discipline
- `thirdparty/sgns-blockstore/docs/s3d-durability.md` — the s3d characterization backing TEST-03's live E2E (staged ≠ durable; flush semantics)

### Code being modified (read before editing)
- `SuperGenius/src/crdt/globaldb/` — the Phase-8 `ColdStorageManager` the GC thread joins (lifecycle, shutdown slots); `globaldb.cpp` `Shutdown()` ordering gains the GC join; the `IpfsDatastore` seam (`GlobalDB::New`)
- `SuperGenius/src/crdt/impl/crdt_heads.cpp` — `CrdtHeads::GetList` (:259) — the walk's entry point and the heads snapshot source (D-08)
- `SuperGenius/src/crdt/impl/crdt_datastore.cpp` — `HasBlock` call sites (:706, :1881) D-11's dedup lands behind; the CRDT set-row keyspace the hot-cleanup step (D-16) removes rows from
- `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` — the responder (`HasBlock` :511, `GetNodeWithoutRequest` :519) whose cold-serve chain D-12's read semantics ride
- `SuperGenius/src/crdt/globaldb/pubsub_broadcaster_ext.cpp` — the pubsub receive-path `HasBlock` caller (:632) the dedup silently protects
- `SuperGenius/src/account/GeniusNode.cpp` — `LoadCrdtConfig` (:552-610 pattern) gains the `blockstore.retention` sub-object parsing (strict per Phase-7 posture; age required per D-04)
- `GeniusWallet/assets/crdt_config.json` — schema parity for the new sub-object (blank form per Phase-7 D-03 posture)

### Authoritative design
- `supergenius-sharded-ipld-cache-architecture.md` (workspace root) — the eviction ≠ delete invariant; the GC design intent D-12's split semantics implement

### Conventions & testing
- `Coding Standards.md` (workspace root) — C++ style for the GC thread, walk, marker, and parser code
- `.planning/codebase/TESTING.md` — verification-inside-`build/<Platform>/<Config>`-tree rule; `addtest()` registration; Tier-1 lane wiring
- `.planning/codebase/INTEGRATIONS.md` — RocksDB / IPFS / CRDT integration context

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Phase-8 `ColdStorageManager` + drainer** — the lifecycle/ownership pattern the dedicated GC thread mirrors (D-06); its status getter is the surface GC extends (evicting count, per-pass metrics)
- **Phase-10 durability surfaces** — per-CID `GetUploadState` pass-through (D-09 of Phase 10) is exactly the eviction gate check; the staging-healthy flag + `RefreshStagingStats` on-demand refresh are the GC inhibitor inputs
- **Phase-9 cold chain + cold-serve** — the Local→S3 CID-verified fetch paths GC-03's retrievability proofs exercise unchanged; `ColdServeDagService`/re-warm executor unchanged
- **Library journal APIs** — `GetPendingUploads`-adjacent enumeration seeds the retention scan; `EvictLocal` is the destructive primitive D-16's batch composes with
- **`InMemoryS3Client` + `FaultController`/`S3FaultKind`** — the fault kit for crash-mid-grace, re-delivery-storm, and staging-unhealthy inhibition tests
- **Phase-7 Tier-1 hermetic lane** — the fail-closed `ctest -L Tier1` lane every GC guard test registers in

### Established Patterns
- Own-thread lifecycle (backup loop, drainer, Phase-9 executor): never `io_`, never the pubsub asio context; ordered shutdown joins — the GC thread is the fourth member
- Snapshot-at-initiation evidence semantics (Phase-10 D-03) — D-08's heads snapshot + re-check applies the same shape to eligibility
- Tri-state config strictness: absent = disabled = byte-identical; present-but-malformed = loud startup failure — `blockstore.retention` inherits; D-04 makes the age key required
- Safe-direction crash analysis (under-eviction is always safe because the remote copy + GC-03 retrieval exist) — D-16's composition and D-10's re-learn both rest on it
- Active-accessor pattern under `lifecycle_mutex_`; rate-limited structured logging + watermark alarms

### Integration Points
- `LoadCrdtConfig` + `GeniusWallet/assets/crdt_config.json` gain the `blockstore.retention` sub-object (age required, dry-run, interval, grace)
- `ColdStorageManager` gains the GC thread + its shutdown join slot (after drainer/flush, alongside the Phase-9 executor ordering)
- `HasBlock` gains the disposed-marker point lookup after the cold-dir check (gated on cold storage enabled)
- sgns-blockstore gains the disposed-CID column family/record + the eviction batch surface (additive, genius-tube-shared)
- The status getter gains evicting count + last-pass metrics fields

</code_context>

<specifics>
## Specific Ideas

Factual constraints from the milestone's committed decisions that bind this phase:

- Eligibility is the intersection `spilled-CID index ∩ age-past-retention ∖ head-reachable ∩ Durable` (ROADMAP SC1) — the durability leg consults Phase-10's evidence-backed `UploadedDurable` records (compile-time gate, Phase-10 D-10; no configurable lower bar)
- GC is inhibited while staging is unhealthy (Phase-10 D-12 flag, fresh via D-13 on-demand refresh)
- Tombstones and CRDT metadata are never purged in v1.1 — guard-tested, SPEC scope boundary; epoch-based deletion compaction is v2+
- The epoch watermark record is computation + storage only in v1.1 (SC5) — nothing is deletion-gated on it
- Every restored/re-learned block enters via the Phase-9 rehydrate path (bytes + resolved marker only; zero pubsub broadcast, zero `AddRoute`) — a trimmed marker's re-learn must stay silent the same way
- TEST-03 is dev-gated and never in CI; the E2E is spill → GC → retrieve with committed evidence artifacts; the MinIO-binary opt-in roundtrip follows the v1.0 Tier-2/3 precedent
- Wrongful eviction is the one unsafe failure direction — every design choice that trades safety for cost (fresh walk, re-check at mark, re-check at delete, in-memory disposable marks) was chosen to fail toward under-eviction

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

### Reviewed Todos (not folded)
- "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" (`.planning/todos/2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md`) — matched only on the keyword "fix" (score 0.2); unrelated to retention GC; left for its own track

</deferred>

---

*Phase: 11-Retention GC of Cold-Eligible CRDT Data*
