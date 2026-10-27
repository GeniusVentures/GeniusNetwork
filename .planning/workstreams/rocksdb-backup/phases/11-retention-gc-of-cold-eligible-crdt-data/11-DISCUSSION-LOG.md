# Phase 11: Retention GC of Cold-Eligible CRDT Data - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-27
**Phase:** 11-Retention GC of Cold-Eligible CRDT Data
**Areas discussed:** Retention age evidence, Reachability walk + scheduling, Disposed-CID markers, Two-phase eviction grace

---

## Retention age evidence

| Option | Description | Selected |
|--------|-------------|----------|
| Wall-clock from journal | Each spilled CID's journal/spill timestamp is the age evidence; "keep N days" operator model matching GC-01's literal "age threshold"; researcher verifies timestamp availability; clock skew only shifts eligibility timing — gates keep it safe | ✓ |
| Priority-height watermark | CRDT-native monotonic evidence, no clock dependence, SC5 computes related state; but height-distance is not operator-intuitive and height→time is app-dependent | |
| App-level horizon | GlobalDB app layer declares the horizon (go-ds-crdt compaction-hint precedent); most flexible but pushes policy into app code and core still needs a default | |

**User's choice:** Wall-clock from journal
**Notes:** ROADMAP explicitly listed this as an open planner decision (priority-height vs wall-clock vs app-level horizon).

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit opt-in | `blockstore.retention` absent → no GC actor constructed, byte-identical (Phase-7 tri-state); destructive feature gets a deliberate operator act | ✓ |
| Default-on with age | Blockstore enabled + retention absent → GC runs with built-in default age; aggressive, contradicts blank-means-disabled | |
| Staged: dry-run first | Retention present but not armed → dry-run only until a second flag arms eviction; safest but adds a second knob | |

**User's choice:** Explicit opt-in

| Option | Description | Selected |
|--------|-------------|----------|
| Config flag | `dry_run` inside `blockstore.retention`; persisted observe-only posture; same evidence surface, delete suppressed | ✓ |
| Ops-triggered pass | One-off dry-run via the ops/status surface (Phase-8 drain-enqueue precedent); no continuous observe mode | |
| Both | Config posture + on-demand trigger; most flexible, extra surface to document/test | |

**User's choice:** Config flag

| Option | Description | Selected |
|--------|-------------|----------|
| Age required | Retention present without age key → loud startup failure; destructive default must be typed, not implied | ✓ |
| Built-in default | Phase-8 D-07 posture: knobs optional with documented default; but silently arms deletion on a partial object | |

**User's choice:** Age required

---

## Reachability walk + scheduling

| Option | Description | Selected |
|--------|-------------|----------|
| Full walk each pass | Fresh DAG walk from `CrdtHeads::GetList` every pass; no stale state; trivially auditable; O(history) accepted via infrequent off-write-path batched passes with resumable cursor | ✓ |
| Persisted reachable-set | Incremental marks, O(new) per pass; stale/missing mark = wrongful-eviction hazard; mark keyspace needs its own GC | |
| Bloom filter | False positives cause under-eviction (safe) but deletion rests on probabilistic evidence; rebuild is a full walk anyway | |

**User's choice:** Full walk each pass

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated GC thread | Backup-loop/drainer pattern (never io_, never pubsub asio context), own join slot; walk never stalls drain/flush; staging-health gates its tick | ✓ |
| Ride the drainer | No new actor, but long walks delay flush advancement and couple health domains | |
| Bounded executor | Phase-9 re-warm executor precedent; walk steps are sequential/cursor-coupled — parallelism buys little | |

**User's choice:** Dedicated GC thread

| Option | Description | Selected |
|--------|-------------|----------|
| Interval knob + default | `gc_interval_ms`-style knob with documented default (Phase-8 D-05/D-06 + 10 D-11 flush-cadence precedent); staging-health gate per tick | ✓ |
| Compile-time only | Phase-9 D-12 posture; but GC interval is a real cost/space tradeoff next to retention age | |
| Adaptive trigger | Idle/candidate-based triggers; untestable scheduling policy | |

**User's choice:** Interval knob + default

| Option | Description | Selected |
|--------|-------------|----------|
| Snapshot + re-check at mark | Pass walks a heads snapshot; non-reachability re-verified against CURRENT heads before marking evicting (Phase-10 D-03 precedent); grace = pure safety margin | ✓ |
| Grace-window only | Walk once, rely on grace + final check; grace becomes a correctness parameter | |
| Publish fence | dagMutex_ coordination at mark time; couples GC to the write path mutex | |

**User's choice:** Snapshot + re-check at mark

---

## Disposed-CID markers

| Option | Description | Selected |
|--------|-------------|----------|
| Library journal/CF | Disposed-CID record in sgns-blockstore's LocalBlockStore RocksDB; single-store atomic batch (bytes + resolved marker + disposed marker); genius-tube shares the primitive | ✓ |
| Node key-prefix | IpfsRocksDb prefix; eviction atomicity spans two stores; duplicates a library primitive | |
| Separate store | Cleanest isolation; third lifecycle + crash-consistency story for a bounded record set | |

**User's choice:** Library journal/CF

| Option | Description | Selected |
|--------|-------------|----------|
| Count cap + age | Max count AND max age, whichever trims first; bounded memory under storms + bounded staleness; trimmed CID re-arrivals re-learn safely | ✓ |
| Count cap only | FIFO/LRU trim; quiet nodes keep stale markers forever | |
| Age expiry only | Bounded time; re-delivery storms grow the set without bound within the window | |

**User's choice:** Count cap + age

| Option | Description | Selected |
|--------|-------------|----------|
| Extend HasBlock | Marker lookup after the cold-dir check (RocksDB point lookup, freeze-safe, 9 D-09 class); existing call sites dedup free; responder composes with cold-serve | ✓ |
| Receive-path only | Surgical pubsub pre-journal check; other re-entry points miss it | |
| Both | HasBlock + explicit receive-path check; duplicates what HasBlock answers | |

**User's choice:** Extend HasBlock

| Option | Description | Selected |
|--------|-------------|----------|
| Split semantics | NotFound/skip is re-delivery-only; direct reads always cold-fetch (Local → S3, CID-verified, re-cache); guard tests state both halves | ✓ |
| NotFound everywhere | Disposed CIDs answer NotFound on all paths until re-pinned; contradicts GC-03's retrievable-end-to-end | |
| Agent discretion | Defer the classification the GC-03 guard tests need pinned now | |

**User's choice:** Split semantics

---

## Two-phase eviction grace

| Option | Description | Selected |
|--------|-------------|----------|
| Compile-time constant | Phase-9 D-12 posture; grace is a safety margin, not a correctness parameter | |
| Config knob | Grace knob in `blockstore.retention` with documented default; bursty re-delivery operators can widen it | ✓ |
| Adaptive grace | Scales with pass duration/candidate count; untestable delete timing | |

**User's choice:** Config knob
**Notes:** Selected against the recommended compile-time posture — operator flexibility preferred.

| Option | Description | Selected |
|--------|-------------|----------|
| Delete-time re-check + cancel | Delete re-verifies non-reachability immediately before the destructive batch; reachable-again → clear mark, keep bytes; two correctness lines | ✓ |
| Grace only, no re-check | Check→delete race whose width equals the grace | |
| Event-driven cancel | Cancel on observed re-delivery/re-publish; quiet local relinks fire nothing | |

**User's choice:** Delete-time re-check + cancel

| Option | Description | Selected |
|--------|-------------|----------|
| In-memory marks | GC-thread state via status getter; only disposed marker persists; crash mid-grace → next pass re-walks; no recovery machinery | ✓ |
| Persisted marks | Survive restarts mid-grace; third journal state + reconciliation machinery | |
| Persisted, cleared on boot | Crash-safe by reset; persistence buys nothing | |

**User's choice:** In-memory marks

| Option | Description | Selected |
|--------|-------------|----------|
| Library-atomic, then hot cleanup | One library RocksDB batch (bytes + resolved marker + disposed marker); hot set-row removal idempotent after; crash between → orphaned hot bytes re-evicted next pass (safe direction) | ✓ |
| Hot-first, then library | Crash window pays needless re-spill work | |
| Write-ahead intent | Strongest all-store atomicity; machinery the safe-direction analysis doesn't require | |

**User's choice:** Library-atomic, then hot cleanup

---

## the agent's Discretion

- Exact knob names inside `blockstore.retention`; built-in default values (interval, grace, marker cap, marker age)
- Journal timestamp mechanics if absent today (additive column vs side index)
- Walk batching/cursor mechanics; protected-namespace enumeration; guard-test proof technique
- Marker record content; per-pass metrics surface; epoch watermark record shape
- Status-getter extension fields; `DeleteCIDBlock` LRU invalidation mechanics
- Tier-1 test design; TEST-03 evidence artifact format + runbook; MinIO roundtrip mechanics; log wording

## Deferred Ideas

None — discussion stayed within phase scope. One todo reviewed and not folded (Vulkan capability-probe deadlock fix — keyword-only match, unrelated).
