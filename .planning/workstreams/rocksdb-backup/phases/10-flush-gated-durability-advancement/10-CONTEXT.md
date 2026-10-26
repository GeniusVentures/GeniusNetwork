# Phase 10: Flush-Gated Durability Advancement - Context

**Gathered:** 2026-10-26
**Status:** Ready for planning

<domain>
## Phase Boundary

`Durable` becomes an evidence-backed state, not an assumption. This phase delivers:

1. **DUR-01 / SC1 — flush-gated advancement:** a flush cadence on the Phase-8 drainer drives s3d `POST /objects/flush` (bucket-scoped, blocking — cost acknowledged) and observes `pendingObjects==0` via `GET /stats/uploads` before advancing journal records `ObjectStoreAccepted → Durable` (`MarkUploadedDurable`); a record marked Durable is always backed by that evidence, never by accepted-is-durable assumption
2. **SC2 — the observable gate:** per-CID journal state transitions `LocalCommitted → ObjectStoreAccepted → Durable` are observable (aggregate counts + per-CID query), and local bytes become evictable only once `Durable` is recorded — the exact gate Phase 11's eviction consults, testable standalone
3. **SC3 — fault honesty:** crash-between-journal-and-drain recovers via journal reconciliation; an s3d outage never surfaces as NotFound; drainer/GC-scheduler/backup-loop shutdown interplay is ordered and race-free under load
4. **SC4 — staging health:** `pendingObjects`/`bufferUsed`/`bufferLimit` (plus a conservative healthy predicate) are monitored and exposed so Phase 11's GC can be inhibited while staging is unhealthy

Out of this phase: retention GC and eviction execution (Phase 11 — this phase only makes the gate honest), cross-actor fault races / fresh-clone proof (Phase 12), per-object durability-signal polling (out of scope milestone-wide — s3d v0.2.1 has no per-object signal; fast-follow), mobile legs (Future — option stays OFF), any change to the GlobalDB backup engine (out of scope milestone-wide).

Requirements: DUR-01.

</domain>

<decisions>
## Implementation Decisions

### Flush cadence & advancement (DUR-01 / SC1)
- **D-01:** **Hybrid flush trigger — drain-quiescence + interval floor + max backstop** — the flush fires after the drainer goes quiescent with accepted-unadvanced records, rate-limited by a minimum interval floor (don't hammer s3d), plus a max-interval backstop so a record can never wait longer than a bound for its durability advancement. Quiescence-only, pure-timer, and count-threshold were rejected: the first scales flush calls with write rate, the second makes durability latency a constant regardless of activity, the third starves under slow write rates without a backstop anyway — **Reversibility:** reversible — cadence mechanics sit behind the D-11 knobs and compile-time defaults
- **D-02:** **The flush call is owned by the Phase-8 drainer thread** — flush runs on the drainer after a drain batch; drain→flush→observe→mark is naturally serialized with no new thread lifecycle. This preserves the single-supplier evidence model the v1.0 spike was captured under (the stats counters are process-global and documented racy under concurrent uploads — "counter deltas must NEVER be read as per-object proof"); a blocking flush stalls nothing because the drainer is idle at that point; SC3's shutdown-ordering proof gains no new actor — **Reversibility:** costly — the serialized evidence model and the SC3 shutdown-interplay tests bind the threading shape; re-homing flush to another thread later re-opens the racy-counter hazard and the shutdown proof
- **D-03:** **Snapshot-at-flush-initiation advancement semantics** — only records already `ObjectStoreAccepted` when the flush began advance to Durable after `pendingObjects==0` is observed; anything accepted later waits for the next cycle. "Never accepted-is-durable" holds by construction rather than by leaning on the D-02 serialization invariant implicitly — **Reversibility:** costly — this is the advancement-correctness contract SC1's evidence tests are stated over; loosening it re-opens the accepted-is-durable assumption the milestone exists to kill
- **D-04:** **Best-effort final flush inside the D-11 shutdown grace window** — after the drainer stops, shutdown makes one bounded flush+observe+mark attempt within the existing grace budget; leftovers stay Accepted and resume via the Phase-8 D-12 first-poll path at next startup. No unbounded shutdown latency; one resume code path serves both crash and clean-stop — **Reversibility:** reversible — shutdown behavior within the existing grace mechanism

### s3d admin surface (library + credentials)
- **D-05:** **The flush/stats admin client lives in sgns-blockstore as an additive facade** — e.g. `Flush()` + `UploadStats()` next to the existing `S3Client` surface. The library already owns the s3d characterization (`docs/s3d-durability.md`) and its test kit; the `InMemoryS3Client` fake gains a fake admin endpoint so every hermetic Tier-1 fault test fakes flush/stats natively; genius-tube consumes the same seam later. SuperGenius-side HTTP was rejected — it would duplicate s3d knowledge outside the library, force a SuperGenius-side fake HTTP layer for Tier-1 tests, and genius-tube would re-implement it. Follows the Phase-6 additive-widening precedent (blake2b) — **Reversibility:** costly — the library's public API surface is a published contract consumed by SuperGenius and genius-tube; re-homing it later is a deprecation
- **D-06:** **Verify-then-env credential posture** — the researcher first verifies s3d v0.2.1's admin auth scheme (the spike used basic auth with an admin password; whether admin reuses the S3 credentials is a researchable fact). If admin reuses existing S3 credentials: zero new surface. If separate: an env-only var (e.g. `SGNS_BLOCKSTORE_S3_ADMIN_KEY`) per the Phase-7 D-07 credentials-in-env posture — admin credentials never at rest in config files, never logged — **Reversibility:** costly — env var names are operator-facing contracts (same class as Phase-7 D-07)
- **D-07:** **Flush/stats failures mirror the drainer backoff discipline** — exponential backoff, capped, reset on success (Phase-8 D-03 shape); records simply stay Accepted (no data risk — the journal is unbounded+alarm by design); sustained flush failure raises the existing watermark-alarm logging discipline and flags drainer health in the status getter. Flush failure never blocks writes and never surfaces as NotFound — **Reversibility:** reversible — failure-handling mechanics behind internal state

### Observability & the eviction gate (SC2)
- **D-08:** **Extend the Phase-8 D-08 status getter** — add per-state record counts (pending / accepted / durable) plus last-flush evidence (timestamp, result, observed counters). One queryable surface, assertable in Tier-1 tests, additive fields per the Phase-8 D-08 "fields can grow" note — **Reversibility:** reversible — additive getter fields
- **D-09:** **Per-CID `GetUploadState` pass-through on `ColdStorageManager`** — a thin wrapper over the library's existing `GetUploadState(cid)`; the Phase-11 eviction gate calls it per candidate CID; natural seed for the later "evictable?" predicate — **Reversibility:** reversible — additive wrapper
- **D-10:** **The eviction-gate durability state is fixed at `UploadedDurable`, compile-time** — no configurable lower bar. The milestone locked flush-gated as THE bar; a knob selecting `Accepted` would let operators opt into evicting the-only-copy data — a data-loss footgun in the shipped schema. DUR-01's "configured durability state" reads as "the durability state this milestone configures" (i.e. Durable). If a legitimate need appears (e.g. proven external S3 replication), a knob can be added additively later — **Reversibility:** reversible — future exposure is additive; the SC2 gate tests bind Durable in the meantime

### Config surface & staging health (SC4)
- **D-11:** **Minimal knob set under a nested `blockstore.durability` sub-object** — the flush cadence knobs (e.g. `flush_min_interval_ms`, `flush_max_interval_ms`; exact names agent discretion) are operator-facing because cadence is a real s3d-cost/durability-latency tradeoff (Phase-8 D-05 posture: cost-relevant knobs earn exposure). Absent knobs = documented built-in defaults; strictness and tri-state semantics inherit Phase 7 unchanged (unknown key inside = loud startup failure) — **Reversibility:** costly — field paths bind the node parser, the wallet asset, and operator docs (same class as Phase-7 D-02 / Phase-8 D-06)
- **D-12:** **The staging-health predicate lands now** — the status getter carries the raw counters (`pendingObjects`/`bufferUsed`/`bufferLimit`) PLUS a conservative `staging healthy` flag (e.g. admin reachable AND `bufferUsed` below a fraction of `bufferLimit` AND no sustained `failedUploads` growth; exact definition agent discretion). Phase 11's GC inhibitor consumes the flag directly without schema change; defining it while the flush loop's observation machinery is fresh avoids re-deriving the semantics under GC pressure — **Reversibility:** costly — the predicate semantics become the GC-inhibition contract Phase 11's safety evidence binds
- **D-13:** **Stats freshness via on-tick + on-demand** — stats are observed on every cadence tick (a cheap GET alongside flush) AND an on-demand refresh entry point exists for the Phase-11 GC to consult before inhibiting. No independent poller thread; GC acts on fresh evidence; steady-state observation cost stays tied to the flush cadence — **Reversibility:** reversible — observation schedule is internal

### The Agent's Discretion
- Exact built-in default values (interval floor, max backstop, backoff floor/cap, health-flag thresholds such as the `bufferUsed`/`bufferLimit` fraction, `bufferLimit==0`-means-unlimited handling) — researcher/planner derive from s3d behavior; they become the documented defaults of D-11
- Exact knob names inside `blockstore.durability` (subject to D-11 nesting + Phase-7 strictness inheritance)
- Library facade API shape: class name, method signatures, placement next to `S3Client`, and the `UploadStats` struct field set (the openapi field inventory in `docs/s3d-durability.md` §2 is the source)
- How the `InMemoryS3Client` fake admin endpoint models flush semantics (blocking behavior, counter transitions, admin-unreachable fault injection for SC3)
- Researcher verification items: s3d v0.2.1 admin auth scheme (separate admin password vs reuses S3 credentials — resolves D-06's branch), admin endpoint paths/port topology (same listener as the S3 API or separate), exact `UploadStats` schema field names
- `MarkUploadedDurable` batch mechanics: how the snapshot set is enumerated (e.g. `GetPendingUploads` + `GetUploadState` filter) and whether marks compose into batched RocksDB writes
- How last-flush evidence is held (in-memory status vs persisted record)
- SC3 fault-injection test design: crash-between-journal-and-drain (extends the Phase-8 D-12 reconciliation pattern), s3d-outage-never-NotFound (rides the Phase-9 D-03 taxonomy), shutdown interplay of drainer + backup loop (+ the Phase-9 executor join slots) under load
- Where the staging-healthy evaluation runs (evaluated on the flush tick and cached vs computed on getter read)
- Tier-1 test target registration mechanics (Phase-7 lane, `ctest -L Tier1 --no-tests=error`, tier-label discipline)
- Exact log-message wording (constraint: flush failures distinguishable from drain failures and peer failures)
- Whether the flush cadence's rate-limit state is separate from the drain backoff state

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream planning (v1.1)
- `.planning/workstreams/rocksdb-backup/REQUIREMENTS.md` — DUR-01 (this phase's letter); Out of Scope table (per-object durability-signal polling is fast-follow, backup engine untouched, blank-config byte-identical)
- `.planning/workstreams/rocksdb-backup/ROADMAP.md` — Phase 10 goal, 4 success criteria, 2 suggested plan waves, research note (light: flush-cadence/batching is a design note; the durability-bar decision itself was resolved at milestone level — this CONTEXT's D-01..D-13 now cover the note's remaining cadence/batching ground)

### Prior phase context (binding decisions this phase builds on)
- `.planning/workstreams/rocksdb-backup/phases/08-spill-on-write-background-drainer/08-CONTEXT.md` — the drainer thread/lifecycle D-02 attaches the flush to (D-10/D-11 ownership + shutdown ordering, D-12 async crash-restart reconciliation, D-01..D-04 backpressure, D-08 status getter this phase extends, D-03 backoff shape D-07 mirrors)
- `.planning/workstreams/rocksdb-backup/phases/09-cold-read-fallback-local-reads-graphsync-serving/09-CONTEXT.md` — the outage-never-NotFound taxonomy (D-03) SC3's outage injections ride; the executor shutdown-join slots the SC3 ordering proof must include
- `.planning/workstreams/rocksdb-backup/phases/07-supergenius-build-wiring-config-gate/07-CONTEXT.md` — the `blockstore` config schema, tri-state semantics, and credentials-in-env posture (D-01..D-08) the `durability` sub-object and D-06 inherit

### Research (v1.1, 2026-10-22)
- `.planning/research/SUMMARY-rocksdb-backup-2026-10-22.md` — the seam synthesis; durability-bar milestone decision
- `.planning/research/PITFALLS-rocksdb-backup-2026-10-22.md` — silent-disable and logging pitfalls
- `.planning/research/STACK-rocksdb-backup-2026-10-22.md` — file:line citations for the seam and backup-loop pattern

### The s3d flush mechanism — authoritative characterization (v1.0 evidence)
- `thirdparty/sgns-blockstore/docs/s3d-durability.md` — THE key doc for this phase: §2 the `GET /stats/uploads` field inventory + the racy-concurrency caveat ("counter deltas must NEVER be read as per-object proof"; evidence captured single-supplier); §3 `POST /objects/flush` semantics ("Uploads all pending objects … Blocks until done") + the before/put/flush evidence triple; §4 staged reads (no distinguishing header — a Durable mark can never rest on a successful GET); §6 operational notes (503 SlowDown disk-pressure → TemporarilyUnavailable; staged ≠ durable remains the model)
- `thirdparty/sgns-blockstore/docs/evidence/s3d-spike/README.md` — the live spike runbook (admin basic-auth usage, flush + stats capture steps) the researcher re-runs/consults for D-06 auth verification
- `thirdparty/sgns-blockstore/docs/evidence/s3d-spike/e2e-stats-captures.txt` — raw counter bodies including the after-flush closure observation

### Library surface being consumed/extended (frozen v1.0 + Phase 6; D-05 adds the admin facade)
- `thirdparty/sgns-blockstore/include/sgns-blockstore/LocalBlockStore.hpp` — `UploadState` enum (:42 — `PendingUpload`/`UploadedAccepted`/`UploadedDurable`, the DUR-01 state machine), `GetUploadState` (:226), `MarkUploadedDurable`, `TransitionJournal` (private batch body), `EvictLocal` with the D-10 warning that durability-gated eviction is exactly this milestone's deferred work
- `thirdparty/sgns-blockstore/include/sgns-blockstore/Durability.hpp` — `DurabilityLevel` (LocalCommitted → ObjectStoreAccepted → ObjectStoreDurable) + "a store NEVER reports an achieved level it has not verified"
- `thirdparty/sgns-blockstore/include/sgns-blockstore/S3Client.hpp` — the `S3Client`/`S3Op` surface the D-05 admin facade sits beside
- `thirdparty/sgns-blockstore/test/` — the `InMemoryS3Client` fake that gains the fake admin endpoint (D-05) for every hermetic Tier-1 test
- `thirdparty/sgns-blockstore/docs/testing-tiers.md` — tier contract; Tier-1 fail-closed lane discipline

### Code being modified (read before editing)
- `SuperGenius/src/crdt/globaldb/` — the Phase-8 `ColdStorageManager` (drainer thread, status getter, shutdown slots) the flush cadence attaches to; `globaldb.cpp` `Shutdown()` ordering the D-04 grace-flush slots into
- `SuperGenius/src/account/GeniusNode.cpp` — `LoadCrdtConfig` (:552-610 pattern) gains the `blockstore.durability` sub-object parsing (strict per Phase-7 posture)
- `GeniusWallet/assets/crdt_config.json` — schema parity for the new sub-object (blank form per Phase-7 D-03 posture)

### Authoritative design
- `supergenius-sharded-ipld-cache-architecture.md` (workspace root) — the durability-levels source the library enum quotes; the flush-gated durability-bar decision

### Conventions & testing
- `Coding Standards.md` (workspace root) — C++ style for the facade, cadence loop, and getter-extension code
- `.planning/codebase/TESTING.md` — verification-inside-`build/<Platform>/<Config>`-tree rule; `addtest()` registration; Tier-1 lane wiring
- `.planning/codebase/INTEGRATIONS.md` — RocksDB / IPFS / s3d integration context

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Phase-8 `ColdStorageManager` + drainer thread** — the flush tick slots into the existing drain loop (D-02); its lifecycle, config gating, and shutdown joins already exist and are proven
- **Phase-8 D-08 status getter** — the additive surface D-08 extends (per-state counts, last-flush evidence, staging-health fields + flag)
- **Library journal APIs** — `UploadState`/`GetUploadState`/`MarkUploadedDurable` give the state machine, per-CID query, and the advancement primitive for free; `GetPendingUploads` enumerates candidates for the D-03 snapshot
- **`InMemoryS3Client` + `FaultController`/`S3FaultKind`** — the fault-injection kit SC3's outage/crash tests extend (fake admin endpoint per D-05)
- **Phase-7 Tier-1 hermetic lane** — the fail-closed `ctest -L Tier1` lane every Phase-10 test registers in

### Established Patterns
- Drainer-loop lifecycle on `ColdStorageManager` (own thread, never `io_`, never the pubsub asio context); ordered shutdown joins (backup loop → drainer [+ grace flush per D-04] → Phase-9 executor)
- Active-accessor pattern under `lifecycle_mutex_` — the extended status getter rides it
- Rate-limited structured logging + watermark alarm discipline (Phase-8 D-02/D-09) — D-07's flush-failure signaling extends it
- Tri-state config strictness (absent = disabled = byte-identical; present-but-malformed = loud) — `blockstore.durability` inherits
- Evidence discipline from the v1.0 spike: single-supplier observation, counter deltas never read as per-object proof, ETag is ciphertext (never a durability attestation), staged reads indistinguishable from durable reads

### Integration Points
- The drainer loop gains the flush→observe→advance step + cadence state (D-01/D-02/D-03)
- `ColdStorageManager` status getter gains durability fields; per-CID `GetUploadState` pass-through (D-08/D-09)
- sgns-blockstore gains the additive admin facade + test-kit fake admin (D-05)
- `LoadCrdtConfig` + `GeniusWallet/assets/crdt_config.json` gain the `blockstore.durability` sub-object (D-11)
- `GlobalDB::Shutdown()` gains the bounded grace-flush attempt (D-04)

</code_context>

<specifics>
## Specific Ideas

Factual constraints quoted from the committed v1.0 evidence that bind implementation choices:

- s3d v0.2.1 `POST /objects/flush`: "Uploads all pending objects to Sia immediately, regardless of padding, and pins them so their local pending files are removed. Blocks until done." — bucket/global-scoped, not per-object; the only documented primitive that moves pending → uploaded+pinned on demand
- Stats counters are pipeline-global; the evidence triple (before-put / after-put / after-flush) was captured single-supplier with one drain in flight; counter deltas must never be read as per-object proof
- No admin endpoint answers "is object K staged or durable"; the only per-object-adjacent signal (`transfer.activeUploads[].label`) is transient in-flight progress — hence snapshot-at-initiation (D-03) rather than per-object confirmation
- Staged objects already serve GET/HEAD 200 with no distinguishing header — a successful read is never durability evidence
- Disk-pressure PUTs render as 503 SlowDown → `TemporarilyUnavailable` (the correct class; never NotFound)
- s3d is pinned at v0.2.1; a future pin bump requires re-running the spike runbook and re-characterizing `docs/s3d-durability.md`

</specifics>

<deferred>
## Deferred Items

### Reviewed Todos (not folded)
- "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" (testing area) — matched only on the keyword "crash" (score 0.2); unrelated to cold storage; stays in the todo backlog for its own phase

</deferred>
