# Phase 9: Cold Read Fallback — Local Reads & Graphsync Serving - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-26
**Phase:** 9-Cold Read Fallback — Local Reads & Graphsync Serving
**Workstream:** rocksdb-backup
**Areas discussed:** Fallback chain ordering, Cold-serve degradation, HasBlock cold-awareness, New config knobs

---

## Fallback chain ordering

| Option | Description | Selected |
|--------|-------------|----------|
| Cold before peers | hot → LocalBlockStore → S3 → peers. Deterministic, no peer dependency; required shape for Phase-11 GC-evicted CIDs (GC-03) and READ-01's letter. Cost: a peer-held block read may first pay an S3 miss. | ✓ |
| Peers before cold | hot → peers → cold as last resort. Preserves today's latency for recent blocks; GC-evicted reads pay a full peer-failure timeout before S3. | |
| Research decides | Researcher measures s3d GET latency vs peer fetch latency and recommends. | |

**User's choice:** Cold before peers
**Notes:** Became D-01.

| Option | Description | Selected |
|--------|-------------|----------|
| Fall through to peers | Cold transport failure logs + counts, then chain continues to peers; only total failure surfaces, classified honestly. Phase-12 soak carries outage visibility. | ✓ |
| Fail fast, no masking | Cold transport failure surfaces immediately as TemporarilyUnavailable. Honest but a local read fails while a peer holds the block. | |
| Split by status | Definitive NotFound in both tiers → fall through; transport → surface immediately. Most precise, most states to test. | |

**User's choice:** Fall through to peers
**Notes:** Became D-03.

| Option | Description | Selected |
|--------|-------------|----------|
| Always re-cache | Every successful cold fetch writes back into the hot store via the dedicated rehydrate path; spill re-journals implicitly via Phase 8. | ✓ |
| S3-only re-cache | Only deepest-miss reads re-enter hot; Local-tier hits stay cold-resident. | |
| Planner decides | Planner picks (always / S3-only / LRU-bounded) once numbers are known. | |

**User's choice:** Always re-cache
**Notes:** Became D-04.

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, both tiers | LocalBlockStore cold dir consulted before S3 — local-disk hit avoids the S3 round trip; matches READ-01's "Local tier → S3 tier". | ✓ |
| S3 only | S3 is the single cold read source; Local tier is drain staging. Loses the local-disk cold hit. | |
| Research confirms | Researcher confirms Local tier's readable-store vs staging-only role in the shipped contracts. | |

**User's choice:** Yes, both tiers
**Notes:** Became D-02.

---

## Cold-serve degradation

| Option | Description | Selected |
|--------|-------------|----------|
| Don't-have + re-warm | Deadline expiry: respond negatively now, background re-warm continues into the hot store so the next request is local. Matches SC2's "conscious degradation" branch. | ✓ |
| Hold to deadline | Responder holds the peer's request open until fetch completes or deadline expires. Fewer negative answers; slow s3d inflates held requests. | |
| Hybrid | Planner picks per load: don't-have under load, hold when idle. Most adaptive, most states. | |

**User's choice:** Don't-have + re-warm
**Notes:** Became D-05.

| Option | Description | Selected |
|--------|-------------|----------|
| On with blockstore | Cold-serve ON whenever blockstore enabled — no extra switch; deadline + bounded executor are the safety mechanisms; honesty tests are the evidence bar. | ✓ |
| Sub-gated off | Separate opt-in flag defaults OFF until measured latency budget proves safe; flipped later. | |
| On + tunable deadline | On by default with an explicit config escape hatch (middle ground). | |

**User's choice:** On with blockstore
**Notes:** Became D-06.

| Option | Description | Selected |
|--------|-------------|----------|
| Coalesced, same executor | One in-flight re-warm per CID; later requests attach or find it hot; own (longer) budget. | ✓ |
| Independent per miss | Each deadline miss schedules its own re-warm; a hammering peer multiplies S3 fetches. | |
| No re-warm | Deadline miss just completes negatively; warming only via ordinary local reads. | |

**User's choice:** Coalesced, same executor
**Notes:** Became D-07.

---

## HasBlock cold-awareness

| Option | Description | Selected |
|--------|-------------|----------|
| Local-only check | HasBlock = held-locally only (hot + cold-dir Has point lookup). The "retrievable before deadline" half lives in the fetch paths. Pubsub path stays freeze-proof. | ✓ |
| Full cold lookup | HasBlock consults S3 with the deadline wherever called — literal SC3 reading; pubsub path pays an S3 round trip per miss, re-opening the freeze hazard. | |
| Two-mode HasBlock | Local-only default + explicit cold-aware variant for read entry points that can afford it. Two semantics, callers must pick. | |

**User's choice:** Local-only check
**Notes:** Became D-08.

| Option | Description | Selected |
|--------|-------------|----------|
| Gated, after hot | Cold-dir Has-check after the hot check misses, only when cold enabled — disabled deployments keep byte-identical HasBlock. | ✓ |
| Gated, before hot | Cold-dir check first; risks surprising ordering where hot must be authoritative. | |
| Hot-only, amend SC3 | HasBlock stays hot-only; SC3's wording amended to "held locally" only. Deviates from SC3's letter. | |

**User's choice:** Gated, after hot
**Notes:** Became D-09.

---

## New config knobs

| Option | Description | Selected |
|--------|-------------|----------|
| Compile-time only | No new config section; serve deadline, executor size, re-warm budget are compile-time defaults. Phase-8 D-05 posture carries; SC2's measurement documents the default. | ✓ |
| Minimal read knobs | A `blockstore.read` sub-object with 1-2 knobs (e.g. serve_deadline_ms). Extends the shipped schema (costly). | |
| Full read section | Serve deadline + executor size + re-warm budget exposed. Most schema surface. | |

**User's choice:** Compile-time only
**Notes:** Became D-12.

---

## The Agent's Discretion

- Exact compile-time default values (serve deadline, executor size, re-warm budget) — derived from the SC2 latency-budget measurement
- Where the fallback chain lives (decorator read path vs `GetNodeWithoutRequest` vs both), constrained by SC3's at-the-seam mapping
- Executor mechanics: pool shape, queue bounds, shutdown join ordering relative to the drainer lifecycle
- Negative-response semantics toward peers on deadline expiry (what the graphsync layer supports)
- The exact BlockStatus → SuperGenius error mapping table (SC3)
- Rehydrate mechanics: bytes + resolved marker composition, "resolved marker" in library terms
- Whether `GetNodeWithoutRequest` gains the cold chain; call-site audit of pubsub-received CIDs vs D-08
- Hermetic test construction for the freeze regression + latency benchmark (no live endpoints)
- Exact log wording (s3d blips distinguishable from peer failures)
- Tier-1 registration mechanics; read-path per-CID coalescing beyond planner necessity

## Deferred Ideas

- `blockstore.read` config sub-object — milestone-Future metrics surface (this phase is compile-time only, D-12)
- Cold-serve latency metrics / per-CID cold-fetch telemetry — milestone-Future metrics list
- Extended read-path in-flight coalescing — later hardening if SC2 evidence shows stampede behavior
