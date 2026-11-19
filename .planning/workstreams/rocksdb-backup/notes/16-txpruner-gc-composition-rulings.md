# TxPruner × GC Composition Rulings (v1.2 Phase 16)

**Ruled:** 2026-11-18
**Context commits:** SuperGenius `af644481f` (Phase 15 close) → `20519ce87` (16-02 Task 1, the consult chain) → the 16-02 Task 2 test commit on `dev_coldstorage_additions`
**Requirements:** COMP-03 (SC3 fail-safe), COMP-01 (D-02 Interaction-C readers)
**Decisions ruled here:** D-02, D-10, D-11, D-12 (16-CONTEXT); D-01 recorded for completeness

This is the workstream planning doc Phase 18's policy record cites (D-12's both-homes rule: code comments at the two destructive homes + this full analysis).

---

## (a) The starvation interplay

`ColdStorageManager`'s retention GC disposes a block through `EvictLocalAndMarkDisposed`: ONE library-atomic batch deletes the cold-dir bytes, **deletes the journal record**, writes the disposed marker, and (HALF 2) cleans the hot rows — while **remote S3 still serves the bytes** (v1.2 never deletes remote).

After that disposal, `TxPruner`'s cold gate reads the constituent CID's journal state as **NoRecord — forever**. Pre-Phase-16, that group vanished into the undifferentiated `cold_deferred_groups` counter: stranded prune mass was invisible to operators (MI-02 never-healthy-by-omission), indistinguishable from never-spilled deferrals.

## (b) The D-10 ruling — cross-marker skip with a split counter

`ColdGateAdmitsGroup`'s **NoRecord arm** (and only that arm) consults the GC module's disposed-marker keyspace through the library API:

```
TxPruner (NoRecord arm)
  → GlobalDB::IsColdDisposed( cid )          [const, lifecycle_mutex_]
  → ColdStorageManager::IsDisposed( cid )    [cold_store_mutex_]
  → LocalBlockStore::IsDisposed( cid )       [the library-owned keyspace]
```

- **Disposed** → `++stats.cold_disposed_stranded_groups`, defer. NEVER an erase: under-prune is the fail-safe direction (the last copy survives — the local value row plus the remote bytes).
- **Not disposed** → today's `cold_deferred_groups` path, byte-identical to pre-phase behavior (the never-spilled shape).
- **Consult error** → freeze-safe false (the `ColdReadService::HasDisposed` posture) → the deferred path; both arms defer, so the fail-safe direction holds even when the consult itself fails.
- Surfaced in the per-cycle INFO line as `cold_disposed_stranded={}` between `cold_unreadable={}` and `skipped={}` — counters, never failure reasons.
- One builder per namespace (Pitfall 5): the keyspace is owned by sgns-blockstore; no marker key is constructed in TxPruner, PruneEligibility, or GlobalDB. `PruneEligibility.{hpp,cpp}` carry zero diff lines for the whole phase.

### The re-journal nuance (recorded from the S3a leg's diagnosis)

On a node whose remote is **reachable**, the evaluator's own block-gate parse read (`GetLocalDeltaKeys` → `GetNodeWithoutRequest` → the cold chain) re-hydrates the disposed block from remote and **re-journals it** (Pending → the drainer re-uploads → Durable) — the correct self-healing production path, which a later cycle then prunes normally. The **stranded steady state is therefore the remote-unreachable posture** (fetch fails → block verdict takes the BLOCK_ALREADY_ERASED branch → the gate reads the journal exactly as the disposal left it). LEG S3a scripts this with a faulted S3 `Get` after the disposal; this nuance is why the stranded counter must be read as "disposed AND not currently re-hydrating", not "disposed ever".

## (c) One-cycle observability lag

Guard 5 (Phase 14 D-06) collapses every non-Durable journal state into `COLD_NOT_DURABLE`, so the split classification lives at **admission** (`RunCycle`'s group filter), not in the evaluator. A disposal landing **mid-cycle** (after the gate's read, before anything else) is classified by the **next** cycle. This is observability latency, not steady-state misclassification (16-RESEARCH Pitfall 4, assumption A1). Zero-lag would require widening guard 5's error value — a Phase-14 contract change ruled out of scope.

## (d) Options considered and rejected

| Option | Verdict | Why |
|---|---|---|
| **Erase-on-disposed** (disposed marker + verified remote presence as erase-sufficient) | **Rejected for v1.2** | Adds S3 GET I/O to every prune cycle's admission path and weakens the fail-closed posture (a remote-presence check that lies — truncated/quorum-stale evidence — would authorize destruction of the last local copy). Revisit only with v2 collection machinery. |
| **`DisposedDurable` journal terminal state** | **The v2 answer — REQUIREMENTS Future** | Preserve terminal evidence instead of deleting the journal record: the gate would read a positive terminal state instead of consulting a second keyspace. Touches the frozen-ish `LocalBlockStore` journal schema — out of v1.2's zero-new-dependencies, pinned-mechanism budget. |
| **Hard mutual exclusion of TxPruner × GC** | **Rejected per D-01** | The 261029-uj0 `GcPassOnce` mutex class was considered, not missed: it adds coupling the "never unify the pruners" decision resists and weakens what SC2's convergence proof claims. Both pruners are idempotent on absent keys; existing locks suffice (see (e)). |

## (e) D-02 — Interaction-C ruling: existing locks suffice

Both destructive durability readers serialize on **`cold_store_mutex_`**:

- **GC's mark-time `kEvictionDurabilityGate` read** executes inside the lock scope opened at the top of `GcPassOnce`'s eligibility scan (`ColdStorageManager.cpp`, the `std::lock_guard` over `*cold_store_mutex_` before `GetDurableWithSpillTime`).
- **TxPruner's in-compose re-check** (Phase 14 D-06, guard 5) reaches the journal through the chain **compose lock → `lifecycle_mutex_` → `cold_store_mutex_`** (`GlobalDB::GetColdUploadState` → `ColdStorageManager::GetUploadState`).

Verified at `af644481f` (16-RESEARCH Anchor Record §7). **No new lock is added or needed in v1.2**: remote S3 is never deleted, so contradictory durability beliefs can never destroy the last copy — the worst interleave is a stale-believed-Durable read that defers or under-prunes. The ruling is documented at both destructive homes in code (the guard-5 comment block in `globaldb.cpp`; the gate-consumption comment in `ColdStorageManager.cpp`).

## (f) D-01 — sequencing record

TxPruner cycles and GC passes remain **free to run concurrently**; the SC2 interleave matrix (16-03) proves both erase orders converge to one fixed point. The composition hardening is sequence + the SC1 window close (16-01's post-commit `DeleteCIDBlock`), never unification or mutex serialization.

## Evidence

- `cold_compose_matrix_test` LEG S3a (hermetic disposal → stranded counter, erased == 0, value survives; red-first signature `SC3-UNDIFFERENTIATED` captured pre-consult), LEG S3b (journal-deletion negative control: marker-miss keeps `cold_deferred`), LEG S3c (Pending arm never consults even with a marker).
- `cold_compose_live_smoke_test` (Tier-3, dev-gated MinIO): a real GC disposal strands a real TxPruner cycle with the block still fetchable from remote (D-11b).

## Deferred item registered by this phase's diagnosis

- **Coldstore handle leak after retention-GC shutdown** (hardening): after a GC-bearing GlobalDB shuts down, an in-process object retains the coldstore's RocksDB handle indefinitely — a post-teardown `LocalBlockStore::Open` fails with `LOCK ... being used by another process` past 45 s, while the identical teardown without retention releases cleanly (S3b's direct RocksDB reopen works). Benign in production (the store outlives shutdown interest); blocks post-teardown coldstore probes in tests. Candidate: audit `AttachColdStorageGc`'s capture graph / the cold-read chain's engaged-path allocations.

## Forward pointers

- **Phase 17** (seals measurement): `cold_disposed_stranded_groups` is an input to stranded-mass measurement.
- **Phase 18** (collectibility policy + role downgrade): this doc is the policy record's citation for the stranded-rows lifecycle and the rejected erase-on-disposed option.
- **v2 `DisposedDurable`** (REQUIREMENTS Future): the terminal-evidence answer that removes the second-keyspace consult.
