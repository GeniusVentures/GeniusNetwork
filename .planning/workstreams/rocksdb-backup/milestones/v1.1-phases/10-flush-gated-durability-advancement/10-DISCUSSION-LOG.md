# Phase 10: Flush-Gated Durability Advancement - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-26
**Phase:** 10 - Flush-Gated Durability Advancement
**Areas discussed:** Flush cadence & trigger, Flush/stats client home, Gate observability, Knobs & health feed

---

## Gray-Area Selection

All four offered areas were selected. A todo cross-reference found one weak match (score 0.2, keyword "crash" only): "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" — reviewed and NOT folded (unrelated to cold storage).

## Flush cadence & trigger

| Option | Description | Selected |
|--------|-------------|----------|
| Hybrid (quiescence + floor + backstop) | Flush after drain quiescence with accepted-unadvanced records, rate-limited by a minimum interval floor, plus a max-interval backstop | ✓ |
| Quiescence-only | Flush immediately after every drain batch that leaves accepted records — fastest advancement, most flush calls | |
| Time interval | Fixed timer flushes whatever is accepted — predictable load, constant latency | |
| Count threshold | Flush when ≥ N accepted records — batches work, starves under slow write rates | |

**User's choice:** Hybrid
**Notes:** —
| Question | Options | Selected |
|---|---|---|
| Who owns the flush call? | Drainer thread / Separate thread / You decide | Drainer thread ✓ |
| Which records advance after pendingObjects==0? | Snapshot at flush initiation / All at observation time / You decide | Snapshot at flush initiation ✓ |
| Final flush inside the D-11 shutdown grace window? | Best-effort in grace / No flush at shutdown / You decide | Best-effort in grace ✓ |

**Notes:** Drainer-thread ownership preserves the single-supplier evidence model from the v1.0 spike (stats counters are documented racy under concurrency). Snapshot semantics make "never accepted-is-durable" hold by construction rather than by implicit reliance on serialization.

## Flush/stats client home

| Option | Description | Selected |
|--------|-------------|----------|
| Library facade | Additive admin surface in sgns-blockstore (Flush() + UploadStats()); InMemoryS3Client test kit gains a fake admin; genius-tube consumes the same seam; Phase-6 additive-widening precedent | ✓ |
| SuperGenius-side | Keep library frozen; SuperGenius calls admin REST directly — duplicates s3d knowledge, needs a SuperGenius-side fake HTTP layer | |
| Types-only split | Library defines stats types/contracts; SuperGenius implements transport | |

**User's choice:** Library facade
| Question | Options | Selected |
|---|---|---|
| Admin authentication surface? | Verify-then-env / Config field + env / You decide | Verify-then-env ✓ |
| Flush/stats failure handling? | Backoff + health flag / Silent retry / You decide | Backoff + health flag ✓ |

**Notes:** Hermetic Tier-1 fault tests must fake the flush/stats endpoints — the library home lets the InMemoryS3Client kit do that natively. Credential branch collapses if s3d admin reuses S3 credentials (researcher verifies against the v0.2.1 spike runbook).

## Gate observability

| Option | Description | Selected |
|--------|-------------|----------|
| Extend D-08 getter | Per-state counts + last-flush evidence added to the Phase-8 status getter — one queryable, test-assertable surface | ✓ |
| Separate getter | A distinct durability-status getter — two surfaces instead of one | |
| Logs only | Transition log lines — not assertable/queryable; weak fit for SC2 | |

**User's choice:** Extend D-08 getter
| Question | Options | Selected |
|---|---|---|
| Per-CID query exposure? | Pass-through of GetUploadState on ColdStorageManager / Counts only | Pass-through ✓ |
| Eviction-gate state fixed or configurable? | Fixed at Durable (compile-time) / Configurable bar with Durable default / You decide | Fixed at Durable ✓ |

**Notes:** A configurable lower gate would ship a data-loss footgun in the schema; DUR-01's "configured durability state" reads as "the state this milestone configures". Future exposure stays additive if a proven need (external S3 replication) appears.

## Knobs & health feed

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal knobs | blockstore.durability sub-object with the minimal cadence set; absent = documented defaults; P7 strictness inherited (P8 D-05 posture) | ✓ |
| Compile-time | Zero new schema surface until metrics evidence justifies (P9 D-12 posture) | |
| You decide | Planner decides knob-by-knob | |

**User's choice:** Minimal knobs
| Question | Options | Selected |
|---|---|---|
| Staging-health predicate: Phase 10 or Phase 11? | Fields + predicate now / Raw fields only / You decide | Fields + predicate now ✓ |
| Stats freshness for the GC inhibitor? | On-tick + on-demand / Independent poll / You decide | On-tick + on-demand ✓ |

**Notes:** Cadence is an operator-relevant s3d-cost tradeoff — cost-relevant knobs earn exposure per the Phase-8 posture. The predicate lands while the flush-loop observation machinery is fresh so Phase 11 consumes it without schema change.

---

## the agent's Discretion

- Built-in default values (interval floor/backstop, backoff params, health thresholds, bufferLimit==0 handling)
- Exact knob names inside blockstore.durability
- Library facade API shape (class/method signatures, UploadStats struct field set)
- InMemoryS3Client fake-admin modeling (blocking, counter transitions, fault injection)
- Researcher verification: s3d admin auth scheme, admin endpoint topology, UploadStats schema field names
- Snapshot enumeration + MarkUploadedDurable batch mechanics
- Last-flush evidence storage (in-memory vs persisted)
- SC3 fault-injection test design (crash reconciliation, outage taxonomy, shutdown interplay)
- Staging-healthy evaluation placement (on-tick cached vs computed on read)
- Tier-1 test registration mechanics; exact log wording; flush rate-limit state vs drain backoff state separation

## Deferred Ideas

None raised during discussion.
