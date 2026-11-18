# Phase 16: TxPruner × GC Composition Hardening - Research

**Researched:** 2026-11-18
**Domain:** Concurrent-erase composition safety in SuperGenius CRDT GlobalDB — LRU-cache invalidation windows, marker-namespace crossfire, interleave-convergence proofs, GC-disposal starvation ruling
**Confidence:** HIGH (every code claim verified by direct file reads against the current post-Phase-15 working tree at SuperGenius HEAD `af644481f`; every design claim traced to 16-CONTEXT locked decisions or the v1.2 research corpus)

## Summary

Phase 16 hardens the composition of the two independent hot-data pruners — TxPruner (transaction-history prune, Light nodes) and ColdStorageManager's GC (retention eviction of unreachable cold-backed blocks) — which run concurrently by design (D-01: convergence-proof, never unify). Three things must land: (1) **COMP-01** closes the stale-LRU window in `GlobalDB::EraseEntry` — guard 3 rejects LRU-resident CIDs only at compose-start, while `FetchNodeFromColdStorage`'s rehydrate path (`graphsync_dagsyncer.cpp:898`) and `BlockReceivedCallback` (`:1034`) insert into the same LRU with no compose lock held; a post-commit `DeleteCIDBlock` in `EraseEntry` (unconditional for every caller, D-04) closes it, mirroring GC's A6 ordering. (2) **COMP-02** proves the interleave matrix — a product crossing {TxPruner erase × GC pass × concurrent LRU insert} over all six shared surfaces (set rows, block bytes, LRU, seals, `/prune/tx` + `/prune/blk` markers, disposed markers), at two layers (deterministic seam-stepped + barrier-driven real-thread, D-06), asserting both erase orders converge to one fixed point defined at BOTH byte level (prefix-spy exact-key enumeration) and observable level (`HasBlock`/`getNode`/evidence predicate, D-08). (3) **COMP-03** rules the GC-disposal starvation interplay — after GC's `EvictLocalAndMarkDisposed` deletes the journal record, TxPruner's gate reads `NoRecord` and defers forever; the ruling (cross-marker skip with a SPLIT counter, D-10) makes stranded mass operator-visible while keeping under-prune the direction, asserted by a two-leg test (deterministic journal-injection + one dev-gated live leg, D-11).

The critical re-location finding: **every CONTEXT-cited anchor moved**. Phase 15 landed 6 commits (`638053925..af644481f`) widening `EraseEntry` (`extra_entries` now a vector carrying BOTH markers, staged `globaldb.cpp:1651-1663`), adding `/prune/blk` markers (`PruneEligibility.hpp:421`), and threading the evidence consult through the cold chain (`FetchNodeFromColdStorage:868-882`). `EraseEntry` moved from ~:1374 to **:1512-1684**; `StageBlockRemoval` from ~:618 to **:707-720**; GC's A6 `DeleteCIDBlock` from ~:1346 to **:1352**; `RunCycle` from ~:141 to **:146-345** with the Phase-14 cold gate now a named helper `ColdGateAdmitsGroup` at **:67-130**. The full drift table with verbatim quotes is the **Anchor Re-Location Record** below — downstream plans MUST cite these, not the v1.2 research line numbers.

Two load-bearing verifications this session: (a) **D-02's Interaction-C claim is TRUE on the current line** — GC's `kEvictionDurabilityGate` read (`ColdStorageManager.cpp:1075`) executes inside the `cold_store_mutex_` scope opened at `:1021`, and TxPruner's guard-5 read chains compose lock → `lifecycle_mutex_` → `cold_store_mutex_` (`globaldb.cpp:1486-1510` → `ColdStorageManager.cpp:727-731`); both destructive durability readers already serialize on `cold_store_mutex_`. (b) the code anticipates this phase — guard 5's comment names "Phase 16's Interaction-C ruling surface" (`globaldb.cpp:1625-1633`), so the ruling documents what the locks already do; it adds no new lock.

**Primary recommendation:** Implement COMP-01 as a post-commit `m_dagSyncer->DeleteCIDBlock( cid )` in `EraseEntry` placed after the seal re-assert (before `return outcome::success();` at `globaldb.cpp:1683`), with a NEW observe-and-continue interrupt seam (sibling of the abort-contract `SetEraseInterruptHookForTest` steps 1-3) to force the exact insert-between-guard-and-commit window deterministically; implement COMP-03's split counter at `ColdGateAdmitsGroup`'s `NoRecord` arm via a `GlobalDB → ColdStorageManager → LocalBlockStore::IsDisposed` bridge mirroring `GetColdUploadState`'s D-09 pass-through shape; build COMP-02's matrix as a new Tier-1 suite reusing `PrefixSpyHotStore`, the journal-injection kit, and both interrupt-hook families, plus one Tier-3 live leg.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Sequencing ruling (Interaction C form)**
- **D-01:** **Convergence-proof — no new mutual exclusion** — TxPruner cycles and GC passes remain free to run concurrently; the interleave matrix proves both erase orders converge to one fixed point. Matches SC2's letter ("concurrent TxPruner and GC passes") and the research lean ("no coordination needed" for the reverse order; row-level idempotence already safe). Hard mutex serialization (the 261029-uj0 GcPassOnce class) was explicitly considered and rejected — it would add coupling the "never unify" decision resists and weaken what SC2 proves — **Reversibility:** costly — the matrix evidence contract is built against the concurrency claim; switching to a mutex later re-opens SC2's meaning and orphans the barrier-driven suites
- **D-02:** **Interaction-C read ruling = existing locks suffice** — the ruling asserts both destructive durability readers (GC mark-time `kEvictionDurabilityGate`, TxPruner in-compose re-check from Phase 14 D-06) already serialize on existing locks (`cold_store_mutex_` / compose lock). Verify on the post-Phase-15 line, document at both destructive homes, race-test the invariant. No new gate, no symmetric GC re-check machinery — remote S3 is never deleted in v1.2, so contradictory beliefs cannot destroy the last copy
- **D-03:** **Fix-forward on divergence** — if a red-first matrix test finds a legal interleave that does NOT converge, it is treated as an idempotence-contract bug in one pruner: repair the half and keep concurrency. Divergences are not design-level signals requiring escalation or a fallback lock

**Stale-LRU close (SC1 mechanics)**
- **D-04:** **Cleanup lives in `EraseEntry`, unconditional for every caller** — the post-commit `DeleteCIDBlock` over the removal-set CIDs executes for all erase paths through `EraseEntry` (single home, extending Phase 15's "EraseEntry stays THE single staging point" philosophy). GC's own A6 `DeleteCIDBlock` in `RunHotCleanup` stays untouched — idempotent double-delete is harmless, and GC's sanctioned hot-cleanup order is never edited by this phase — **Reversibility:** costly — the single-home placement is the load-bearing fix for the window; unwinding it re-opens the bug class for future `EraseEntry` callers
- **D-05:** **Guard 3 stays; post-commit delete only closes the race window** — the compose-start LRU rejection (guard 3, `globaldb.cpp:1428-1432`) keeps deferring erases of LRU-resident CIDs; admission semantics are unchanged (compose-don't-pick; smallest behavioral delta). Full GC parity (removing guard 3 so cached CIDs erase immediately) was considered and rejected — a bigger admission change than SC1's letter demands, touching the compose-path guards Phase 14 built evidence against

**Interleave matrix (SC2 evidence shape)**
- **D-06:** **Both test layers** — real-thread barrier-driven races for true-concurrency claims (v1.1 discipline: barriers, never sleeps, env-knob reproducibility on every nondeterministic test) PLUS deterministic seam-stepped interleavings for exact repro of specific orderings (Phase 14 D-07 interrupt-seam precedent). Each covers what the other can't — the 261029-uj0 OSX faults were real-thread timing seams can't reproduce; SC1's exact window (insert between guard-check and commit) can't be forced reliably by real threads
- **D-07:** **Marker-namespace crossfire folded into the matrix** — one matrix product crosses {TxPruner erase × GC hot-cleanup × `GrabCIDBlock` insert} over ALL shared surfaces: set rows, block bytes, LRU, seal rows, AND both marker namespaces — with Pitfall 5's crossfire invariants (tombstones, disposed markers, `/prune/` markers byte-identical across each run) asserted as matrix rows. One product proves SC2 and the crossfire guard together
- **D-08:** **Fixed point = rows + answers** — "both erase orders converging to one fixed point" is asserted at BOTH layers: (a) byte-level row convergence via exact prefix enumeration of every touched keyspace (Phase 11's prefix-spy hot datastore instrument); AND (b) observable equivalence — `HasBlock` / `getNode` / evidence predicate answer identically from either order's end state — **Reversibility:** costly — this is the mechanical definition of SC2's "one fixed point"; weakening either layer re-opens what convergence means
- **D-09:** **Tier-1 entry, no soak leg** — the deterministic matrix suites (seam-stepped + barrier-driven on real RocksDB/GlobalDB, no services) enter the CI Tier-1 contract this phase (Phase 14 D-09 fresh-clone-safe precedent; feeds the Phase 19 three-platform capstone). No soak-scale leg — SC2 is a correctness claim, not a capacity claim; scale evidence belongs to Phase 17/19

**Starvation ruling (SC3 disposition)**
- **D-10:** **Cross-marker skip — explicit deferral with split counters, still under-prune** — TxPruner's gate consults GC's disposed-marker keyspace for NoRecord constituents: disposed → explicit deferral surfaced by a SPLIT counter (cold_deferred vs stranded-by-disposal), never an erase. Operators can see stranded prune mass (matters for Phase 17 measurement and Phase 18 policy; MI-02 never-healthy-by-omission precedent from Phase 14 D-03). Marker reads go through the GC module's key builder — no third builder (Pitfall 5). Erase-on-disposed (remote-presence verification) was considered and rejected — adds S3 GET I/O to the prune cycle and weakens the fail-closed posture; research recommended against it for v1.2 — **Reversibility:** costly — the split counter becomes an operator-facing contract Phase 17/18 evidence cites; collapsing it back into one undifferentiated mass loses the stranded-rows observability
- **D-11:** **SC3 fail-safe test = both legs** — (a) deterministic Tier-1 leg via the Phase 14 D-08 journal-injection kit (delete the journal record directly = disposal simulation; assert defer + split counter, written red-first); PLUS (b) one dev-gated live leg where a real GC pass disposes and a subsequent TxPruner cycle defers with the stranded counter — mirroring the 14-D-08 hybrid posture (the injection alone might model the wrong post-disposal state)
- **D-12:** **Ruling documentation = code + doc** — code comments at both destructive homes (the TxPruner gate site + `ColdStorageManager`'s `EvictLocalAndMarkDisposed`) stating the interplay and the under-prune ruling, PLUS a workstream planning doc carrying the full ruled analysis (options considered, v2 `DisposedDurable` pointer, stranded-rows lifecycle). The planning doc is what Phase 18's policy record cites; the sequencing/Interaction-C ruling (D-02) gets the same code-at-both-homes treatment

### The Agent's Discretion
- Exact interrupt-seam placement/naming for the SC1 window counter-test (sibling of `kInterruptBeforeErase` / Phase 14's `kInterruptAfterColdGate`)
- Barrier design and env-knob scheme for the real-thread legs (flake containment on the Windows/macOS lanes — poll predicates, never fixed sleeps)
- Prefix-spy reuse specifics: which keyspaces the exact-key enumeration covers per fixture
- Counter naming for the D-10 split (e.g. `cold_deferred_groups` vs a stranded-disposed companion) and how it surfaces in the per-cycle INFO summary
- Matrix fixture design — which CIDs overlap across the two pruners' sets, seal row fixtures, both marker namespaces in play
- Home and name for the workstream ruling doc (phase dir vs `notes/`)
- Whether `EraseEntry`'s post-commit delete iterates the removal-set vector mechanically or reuses a helper (implementation shape)
- Anchor re-location strategy against the final post-Phase-15 state (see domain status note) — researcher rules exact procedure

### Deferred Ideas (OUT OF SCOPE)
- **`DisposedDurable` journal terminal state** — the v2 answer to the starvation interplay (preserve terminal evidence instead of deleting the journal record); already recorded in REQUIREMENTS Future — touches the frozen-ish LocalBlockStore journal schema
- **Erase-on-disposed (disposed marker + verified remote presence as erase-sufficient)** — research option (ii), rejected this phase (adds S3 GET I/O to the prune cycle, weakens fail-closed); revisit only alongside v2 collection machinery
- **Hard mutual exclusion of TxPruner cycle × GC pass** — the 261029-uj0 mutex class, explicitly rejected by D-01 in favor of convergence-proof; recorded here so future readers know it was considered, not missed
- **Removing guard 3 for full GC parity** — considered and rejected by D-05; if LRU-residency deferral ever proves costly, that's a measured trigger for a future phase
- **Soak-scale composition evidence** — correctness claims only this phase (D-09); scale belongs to Phase 17 measurement and Phase 19's capstone
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| COMP-01 | EraseEntry's post-commit cleanup is hardened to GC's parity — the stale-LRU window (guard checks at compose-start only, no post-commit DeleteCIDBlock) is closed. | Anchor Record §1/§3: `EraseEntry` :1512-1684, guard 3 :1567-1573, post-commit insertion point :1666-1683; inserter sites `graphsync_dagsyncer.cpp:898` + `:1034`; `DeleteCIDBlock` :1258-1265 is idempotent and lock-free (no new lock edge under the compose lock); `m_dagSyncer` is the concrete type (globaldb.hpp:769) so the call needs no interface change |
| COMP-02 | Concurrent TxPruner and GC passes are proven safe under an interleave matrix covering overlapping set rows, seal rows, and the block LRU — both idempotent on absent keys, seals untouched by both. | Anchor Record §2/§4/§5: both pruners' full current paths with line-verified staging surfaces; `RunHotCleanup` :1317-1353 batch shape + A6; seal retention comments at both homes; test-infrastructure inventory (PrefixSpyHotStore, fault-race suite, journal-injection kit, interrupt-hook families) |
| COMP-03 | The GC-disposal starvation interplay (journal record deleted → gate reads NoRecord while remote S3 still serves) is ruled, documented, and its fail-safe direction (under-prune) is asserted by test. | Anchor Record §4/§6: `EvictLocalAndMarkDisposed` :1281 under `cold_store_mutex_`; `ColdGateAdmitsGroup` NoRecord arm :118-128; disposed point-lookup `LocalBlockStore::IsDisposed` via `ColdReadService.cpp:286` (the library-owned key builder — no third builder); D-02 lock verification (both readers serialize on `cold_store_mutex_`) |
</phase_requirements>

## Project Constraints (from copilot-instructions.md / AGENTS.md)

- **C++ conventions (Corelinux-derived)**: Ullman braces, PascalCase types, `m_`/trailing-underscore member prefix, PascalCase headers, `Get`/`Is`/`Set` accessor prefixes, Doxygen `@brief`/`@param`/`@return` on public interfaces, `outcome::result<T>` for fallible operations, `[[nodiscard]]` where discarding is an error.
- **SuperGenius/CLAUDE.md build discipline**: no POSIX shell in build commands (`sh -c` breaks native Windows — drive multi-command logic via `${CMAKE_COMMAND} -P` script mode); default-off opt-ins must execute nothing in a default build; never duplicate logic (second use → move to shared module first); no business logic in transport layer; "Gates, not promises" — a rule that matters is enforced by ctest/CI; refactor first, then change.
- **Serialization**: no new wire formats this phase — everything is local RocksDB rows and in-process LRU state.
- **GSD workstream routing**: all artifacts under `.planning/workstreams/rocksdb-backup/`; code changes live in the `SuperGenius` submodule on `dev_coldstorage_additions`.
- **Tier discipline (v1.1 norm, D-09)**: hermetic deterministic suites registered `LABELS "Tier1"` via `set_tests_properties` (addtest has no LABELS support — `test/src/crdt/CMakeLists.txt:88-101` documents this); dev-gated live legs `LABELS "Tier3"`; `ctest -L` never `-LE`; label-count audit with teeth.
- **Zero new dependencies (STATE.md v1.2 ruling)**: all work composes pinned mechanisms (RocksDB 9.4.0, vendored ipfs-lite-cpp unedited, sgns-blockstore frozen v1 contract).
- **Anti-layering rule (verified 15-03 deviation 1)**: `globaldb_integration_test` must NOT link `genius_transaction_objs` (inverts crdt→transaction dependency); marker seeding in globaldb-scoped suites uses direct `PutRaw` at `PRUNE_BLOCK_MARKER_PREFIX` with byte-identical records instead of the PruneEligibility test helpers.

## Anchor Re-Location Record (MANDATORY — post-Phase-15 line)

**Re-location procedure ruled by this researcher (per Agent's Discretion):** (1) establish submodule state via `git -C SuperGenius log --oneline -12` — HEAD is `af644481f` on `dev_coldstorage_additions`; Phase 14 = `dc788261d..095c8c502`, Phase 15 = `638053925..af644481f`; working tree clean except untracked `test-data/`. (2) Re-grep every CONTEXT-cited symbol and READ each function body in full (grep alone is insufficient per the in-repo provenance rule). (3) Record new line ranges with verbatim quotes below. Downstream plans MUST cite these anchors; the v1.2 research numbers (merge `2af184fa1`) and even the 16-CONTEXT numbers (cited at `095c8c502`) are STALE for `EraseEntry`, `StageBlockRemoval`, `RunCycle`, and the marker homes.

### Drift table (old citation → verified current)

| Anchor | Cited (stale) | **Verified current** | Delta |
|---|---|---|---|
| `GlobalDB::EraseEntry` body | ~:1374-1451 | **:1512-1684** (`globaldb.cpp`) | +138 lines (guards 5 + widened vector + interrupt hooks landed) |
| Guard 3 (LRU reject at compose start) | :1428-1432 | **:1567-1573** | moved |
| Guard 5 (cold re-check, NEW since research) | — | **:1586-1634** | Phase 14 addition |
| `extra_entries` staging | :1462-1466 | **:1651-1663** (vector loop) | widened by Phase 15 |
| Post-commit seal re-assert | :1471-1485 | **:1666-1681** | moved |
| **SC1 insertion point** (after re-assert, before success) | — | **:1682-1683** | NEW — D-04's `DeleteCIDBlock` home |
| `globaldb.hpp` `EraseEntry` signature | :489 | **:521-524** | widened vector |
| `GraphsyncDAGSyncer::StageBlockRemoval` | :618-633 | **:707-720** | moved |
| `GrabCIDBlock` / `DeleteCIDBlock` / `IsCIDInCache` | — | **:1245-1257 / :1258-1265 / :1239-1242** | located |
| LRU insert sites (SC1 inserters) | "getNode insert sites" | **:898** (`FetchNodeFromColdStorage` rehydrate) and **:1034** (`BlockReceivedCallback` → `AddCIDBlock` :1218-1237) | enumerated |
| `getNode` / `GetNodeWithRouteBudget` | :750-806 (FetchNode) | **:347-354 / :356-365 / :377-435**; `FetchNodeFromColdStorage` **:848-942** | Phase 15 restructured |
| `GetNodeWithoutRequest` | — | **:823-846** | located |
| `HasBlock` (4-term) | — | **:772-812** (4th term = disposed marker :803-804) | located |
| GC `RunHotCleanup` | :1317-1345 | **:1317-1353** | ~same |
| GC A6 `DeleteCIDBlock` | :1346-1348 | **:1352** | moved +2 |
| GC seal-retention comment | :1327-1333 | **:1324-1333** | ~same |
| GC delete-time heads re-check (D-14) | :1253-1261 | **:1240-1253** | ~same |
| `EvictLocalAndMarkDisposed` call (HALF 1) | — | **:1281** (under `cold_store_mutex_` :1280) | located |
| `kEvictionDurabilityGate` consumption | :1072-1076 | **:1075-1077** (inside `cold_store_mutex_` scope opened :1021) | verified |
| `GcPassOnce` (the rejected mutex class) | — | **:860-870** (takes `gc_pass_mutex_` :870) | located |
| `TxPruner::RunCycle` | :141-176 | **:146-345** (cold gate helper `ColdGateAdmitsGroup` **:67-130**) | restructured by Phase 14 |
| TxPruner interrupt seams | :198 | **:273-283** (`kInterruptAfterColdGate`), **:291-296** (`kInterruptBeforeErase`); constants at hpp **:263-279** | moved |
| `PruneCycleStats` | hpp :68 | **:68-110** — `cold_deferred_groups` **:92**, `cold_unreadable_groups` **:102** | same start, extended |
| `/prune/blk` prefix | — | **`PRUNE_BLOCK_MARKER_PREFIX = "/prune/blk/"`** hpp **:421** (`PRUNE_MARKER_PREFIX = "/prune/tx/"` **:415**) | Phase 15 addition |
| `EraseTransactionEntryWithMarker` (marker staging) | — | **TransactionManager.cpp:4719-4783** (both markers built :4752-4760, `EraseEntry` call :4765); `EraseTransactionEntryPruned` **:4791-4797** | located |

### Verbatim anchor quotes (checkable)

**1. `EraseEntry` signature + guards (globaldb.cpp:1512-1516, 1567-1573, 1608-1610):**
```cpp
    outcome::result<void> GlobalDB::EraseEntry(
        const std::string                                              &key,
        const CID                                                      &cid,
        const std::optional<std::vector<std::pair<Buffer, Buffer>>>    &extra_entries )
```
```cpp
        // (3) LRU-cached block.
        if ( m_dagSyncer->IsCIDInCache( cid ) )
        {
            m_logger->error( "{}: cid {} is in the block cache, refusing erase", __func__, cid.toString().value() );
            return outcome::failure( Error::INVALID_PARAMETERS );
        }
```
```cpp
        if ( HasColdStorage() && GetColdUploadState( cid ) != ColdUploadState::Durable )
        {
```
[VERIFIED: SuperGenius/src/crdt/globaldb/globaldb.cpp:1512-1516, 1567-1573, 1608-1610]

**2. Post-commit seal re-assert and the SC1 insertion point (globaldb.cpp:1664-1684):**
```cpp
        BOOST_OUTCOME_TRY( batch->commit() );

        // The seal marker is never staged for removal above; if it is gone
        // now, something erased it out-of-band -- fail loudly with a
        // DISTINCT error: ...
        BOOST_OUTCOME_TRY( auto still_resolved, m_dagSyncer->isResolved( cid ) );
        if ( !still_resolved )
        {
            m_logger->error( "{}: seal marker vanished after erase - seal-addressing bug (erase already committed)",
                             __func__ );
            return outcome::failure( Error::POST_COMMIT_ERASE_ANOMALY );
        }

        return outcome::success();
    }
```
[VERIFIED: SuperGenius/src/crdt/globaldb/globaldb.cpp:1664-1684] — the D-04 post-commit `DeleteCIDBlock` slots between the re-assert block and `return outcome::success();`.

**3. The two concurrent LRU inserters (the SC1 window's racers):**
```cpp
                // LRU insert per the GrabCIDBlock pattern so the read does
                // not pay a second hot lookup (AddCIDBlock shape).
                (void)lru_cid_cache_.add( cid, node.value() );
```
[VERIFIED: SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp:896-898 — inside `FetchNodeFromColdStorage`, which runs outside `dagMutex_` by construction (READ-01 comment :836-839) and holds NO compose lock]
```cpp
        if ( AddCIDBlock( cid, node.value() ) )
        {
            logger_->error( " Block received without CRDT asking for it explicitly " );
        }
```
[VERIFIED: SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp:1034-1037 — `BlockReceivedCallback`, the libp2p receive path]

**4. `DeleteCIDBlock` — the closing primitive (idempotent, no dagMutex_):**
```cpp
    outcome::result<void> GraphsyncDAGSyncer::DeleteCIDBlock( const CID &cid )
    {
        if ( lru_cid_cache_.remove( cid ) )
        {
            logger_->debug( "Block removed from LRU cache: CID {}", cid.toString().value() );
        }
        return outcome::success();
    }
```
[VERIFIED: SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp:1258-1265 — always succeeds (absent-key remove is a no-op); takes no lock, so calling it under `EraseEntry`'s compose lock adds NO lock-order edge]

**5. GC's sanctioned order — HALF 2 + A6 (ColdStorageManager.cpp:1317-1353):**
```cpp
    void ColdStorageManager::RunHotCleanup( const sgns::blockstore::Cid  &cid,
                                            const std::vector<std::string> &row_keys )
    {
        ...
        auto batch = gc_hot_store_->batch();
        ... (binary CID key + row_keys removes) ...
        (void)batch->commit();
        // A6: LRU invalidation AFTER the hot deletes - post-cleanup the
        // hot and LRU HasBlock terms miss and the disposed-marker term
        // answers (HasBlock stays honest through the whole window).
        (void)gc_dag_syncer_->DeleteCIDBlock( cid_key );
```
[VERIFIED: SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp:1317-1352 — the ordering COMP-01 mirrors; stays untouched per D-04. Seal retention comment: "The seal/resolved marker is DELIBERATELY RETAINED (develop's GATE-03 invariant...)" at :1324-1333]

**6. The starvation source — HALF 1 journal deletion (ColdStorageManager.cpp:1273-1287):**
```cpp
            sgns::blockstore::DisposedRecord record;
            ...
            {
                std::lock_guard<std::mutex> lock( *cold_store_mutex_ );
                auto evicted = local_block_store_->EvictLocalAndMarkDisposed( mark.cid, record );
```
[VERIFIED: SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp:1273-1281 — `EvictLocalAndMarkDisposed` deletes cold bytes + journal + writes the disposed marker as one library-atomic batch under `cold_store_mutex_`; this is the D-10 consult source and a D-12 comment home]

**7. D-02 lock verification — both destructive durability readers serialize on `cold_store_mutex_`:**
```cpp
        {
            std::lock_guard<std::mutex> lock( *cold_store_mutex_ );
            auto durable = local_block_store_->GetDurableWithSpillTime();
            ...
                auto state = local_block_store_->GetUploadState( entry.cid );
                if ( !state.has_value() || state.value() != kEvictionDurabilityGate )
```
[VERIFIED: SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp:1021-1077 — GC's mark-time `kEvictionDurabilityGate` read executes INSIDE the `cold_store_mutex_` scope]
```cpp
    ColdUploadState GlobalDB::GetColdUploadState( const CID &cid ) const
    {
        ...
        std::lock_guard<std::mutex> lock( lifecycle_mutex_ );
        ...
        return sgns::crdt::GetColdUploadState( cold_manager_, cid );
```
[VERIFIED: SuperGenius/src/crdt/globaldb/globaldb.cpp:1486-1509 → ColdStorageManager.cpp:727-731 (`std::lock_guard<std::mutex> lock( *cold_store_mutex_ ); return local_block_store_->GetUploadState( cid );`) — TxPruner's guard-5 read chains compose lock → `lifecycle_mutex_` → `cold_store_mutex_`. The D-02 ruling therefore documents existing behavior; guard 5's own comment names the handoff: "the only Durable-record removals are GC disposal paths yielding NoRecord, which a later cycle's gate defers) and is Phase 16's Interaction-C ruling surface, not this lock's" (globaldb.cpp:1625-1633).]

**8. The D-10 consult point — `ColdGateAdmitsGroup` NoRecord arm (TxPruner.cpp:67-130):**
```cpp
                case crdt::ColdUploadState::NoRecord:
                case crdt::ColdUploadState::Pending:
                case crdt::ColdUploadState::Accepted:
                default:
                    // Includes the default arm (T-14-01): an unknown
                    // future enum value can never admit.
                    ++stats.cold_deferred_groups;
                    return false;
```
[VERIFIED: SuperGenius/src/transaction/TxPruner.cpp:118-128 — the split counter splits THIS arm: `NoRecord` + disposed-marker hit → the new stranded counter; `NoRecord` + no marker → `cold_deferred_groups` as today; `Pending`/`Accepted`/default never consult (the journal record exists — not disposed)]

**9. The disposed-marker point lookup (the library-owned key builder — no third builder):**
```cpp
            auto disposed = local_block_store_->IsDisposed( cid );
```
[VERIFIED: SuperGenius/src/crdt/globaldb/ColdReadService.cpp:286 (inside `ColdReadService::HasDisposed`, consumed as `HasBlock`'s fourth term at graphsync_dagsyncer.cpp:803-804: `if ( cold_read_hook_ != nullptr && cold_read_hook_->HasDisposed( cid ) )`) — the disposed-marker keyspace is owned by the sgns-blockstore library (`LocalBlockStore`); D-10's "GC module's key builder" = routing the consult through this library API, never hand-building marker keys in TxPruner. Note `ColdStorageManager` does NOT currently expose an `IsDisposed` point-lookup — only `GetDisposed()` (:1368, full enumeration) and `TrimDisposedMarkers` (:1445); a small manager pass-through under `cold_store_mutex_` mirroring `GetUploadState` (:727-731) is the natural bridge shape.]

**10. Counter + INFO homes (TxPruner.hpp:92, TxPruner.cpp:396-413):**
```cpp
        uint64_t cold_deferred_groups = 0;
```
```cpp
        logger_->info( "Prune cycle [generation {}]: examined={}, eligible={}, erased={}, held_blocks={}, "
                       "cold_deferred={}, cold_unreadable={}, skipped={}, errors={}, duration_ms={}, "
                       "watermark={} — bytes reclaimed: not measured until Phase 20",
```
[VERIFIED: SuperGenius/src/transaction/TxPruner.hpp:92; SuperGenius/src/transaction/TxPruner.cpp:397-399 — the D-10 split counter lands in `PruneCycleStats` (:68-110) beside `cold_deferred_groups`/`cold_unreadable_groups` (:92/:102) and joins this INFO line]

**11. Interrupt-hook families (the D-06 seam substrate):**
- `GlobalDB::SetEraseInterruptHookForTest( std::function<bool( int step )> hook )` — steps "1 = after CRDT-entry staging, 2 = after block staging, 3 = after raw-map staging; a @c true return aborts the erase WITHOUT committing" [VERIFIED: SuperGenius/src/crdt/globaldb/globaldb.hpp:527-534; fired at globaldb.cpp:1637-1650; static `erase_interrupt_hook_for_test_` :810-812]
- `TxPruner::SetCycleInterruptHookForTest` — constants `kInterruptAfterEvaluation = 1`, `kInterruptBeforeErase = 2`, `kInterruptBeforeStatus = 3`, `kInterruptAfterStatus = 4`, `kInterruptAfterColdGate = 5` [VERIFIED: SuperGenius/src/transaction/TxPruner.hpp:263-279; fired at TxPruner.cpp:199/:277/:293/:345/:389; static `cycle_interrupt_hook_for_test_` TxPruner.cpp:132]
- `GlobalDB::SetColdUploadStateHookForTest( std::function<std::optional<ColdUploadState>( const CID & )> hook )` — the Phase-14 D-07 induced-regression injector, consulted FIRST by `GetColdUploadState` [VERIFIED: SuperGenius/src/crdt/globaldb/globaldb.hpp:543-553]
- GC hooks: `gc_pre_half_one_hook_` (:1256-1267), `gc_between_halves_hook_` (:1288-1301), mid-pass hook (:1101, :1232-1234) — TEST-ONLY, invoked OUTSIDE `cold_store_mutex_` [VERIFIED: SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp]

**12. Marker key homes (Phase 15's landed namespace — D-07's crossfire surfaces):**
```cpp
        static constexpr std::string_view PRUNE_MARKER_PREFIX = "/prune/tx/";
        ...
        static constexpr std::string_view PRUNE_BLOCK_MARKER_PREFIX = "/prune/blk/";
```
[VERIFIED: SuperGenius/src/transaction/PruneEligibility.hpp:415, 421 — builders `BuildPruneMarkerKey`/`BuildPruneBlockMarkerKey` (cpp :172/:286), entries `BuildPruneMarkerEntry`/`BuildPruneBlockMarkerEntry` (cpp :252/:338), lookups `LookupPrunedEntry` (:180+)/`LookupPrunedBlockEntry` (:295+). The `/prune/blk` record carries the erasing `/prune/tx` hash back-reference + `erased_at_generation` (Phase 15 D-02), staged as BOTH markers in one vector by `TransactionManager::EraseTransactionEntryWithMarker` (TransactionManager.cpp:4752-4760).]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Post-commit LRU invalidation (SC1) | GlobalDB (`EraseEntry`, crdt layer) | GraphsyncDAGSyncer (`DeleteCIDBlock` primitive) | `EraseEntry` is THE single staging/commit point (Phase 15 D-01 philosophy); the LRU primitive already exists and is exposed on the concrete `m_dagSyncer` handle |
| LRU insert (the racer) | GraphsyncDAGSyncer (cold rehydrate + network receive) | — | Both insert sites live in the dag syncer; neither holds (or should hold) the compose lock |
| Interleave-matrix evidence (SC2) | Test tier (Tier-1 suites) | — | Correctness claim proven by suites, not production coordination (D-01: no new mutual exclusion in production code) |
| Disposed-marker consult (SC3) | TxPruner cycle filter (`ColdGateAdmitsGroup`) | GlobalDB bridge → ColdStorageManager → LocalBlockStore | Mirrors the Phase-14 gate placement (PRUNE-03: gate at `RunCycle`, evaluator pure); keyspace owned by the library |
| Split counter surfacing | `PruneCycleStats` + per-cycle INFO | — | The existing counter home Phase 14 established |
| Interaction-C ruling docs (D-02/D-12) | Code comments at both destructive homes + workstream doc | — | Decision explicitly assigns documentation to both homes |
| Convergence fixed-point assertion | Test tier (prefix-spy bytes + observable predicates) | — | D-08's two-layer definition |

## Standard Stack

### Core (zero new libraries — all pinned, all verified in-tree)

| Mechanism | Version/Pin | Purpose | Why Standard |
|---|---|---|---|
| `GraphsyncDAGSyncer::DeleteCIDBlock` | in-tree (:1258-1265) | SC1's closing primitive | Idempotent, lock-free, already GC's A6 mechanism — reuse, don't wrap |
| `GlobalDB::EraseEntry` compose path | in-tree (:1512-1684) | Single staging/commit home | Phase 15's "THE single staging point" philosophy extended by D-04 |
| `PrefixSpyHotStore` | in-tree test instrument (fault_race :568, gc_test :440) | D-08 byte-level convergence | Phase 11's exact-key enumeration precedent, twice reused |
| Barrier-driven race pattern | in-tree (`cold_storage_fault_race_test.cpp`, 14 TEST_Fs) | D-06 real-thread layer | The v1.1 13-case matrix discipline + jitter seeding (:1616) |
| Interrupt-hook seams | in-tree (3 families, Anchor Record §11) | D-06 deterministic layer | Phase 14 D-07 precedent |
| Journal-injection kit | in-tree (`cold_prune_gate_test.cpp`) | D-11 Tier-1 leg | Phase 14 D-08: direct journal-CF seeding against a real GlobalDB |
| GTest + CTest Tier labels | pinned | Suite registration | `LABELS "Tier1"`/`"Tier3"` via `set_tests_properties` |

### Supporting

| Mechanism | Purpose | When to Use |
|---|---|---|
| `SetColdUploadStateHookForTest` | State-flip injection (Durable→NoRecord mid-cycle) | SC3 deterministic leg variant; Interaction-C race test |
| `gc_pre_half_one_hook_` / `gc_between_halves_hook_` | Park GC at its knife edges | Matrix rows crossing GC's commit boundaries |
| `ColdEvidenceMatrixTest` fixture recipe | Real cold-enabled GlobalDB + S3 fakes + seed helpers | Matrix fixtures needing both pruners live |
| `InMemoryS3Client`/`InMemoryS3AdminClient` ("hermetic.invalid") | Cold tier without services | Every Tier-1 leg |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|---|---|---|
| Post-commit `DeleteCIDBlock` in `EraseEntry` | Lock the LRU on insert (share compose lock) | Rejected: adds a lock-order edge to the hot read path for zero benefit; inserters run on the libp2p io_context where blocking is forbidden (responder-freeze class) |
| Split counter at admission (`ColdGateAdmitsGroup`) | Classify inside guard 5's `COLD_NOT_DURABLE` refusal | Guard 5 collapses all non-Durable states into one error — the state is not visible there; admission is where `NoRecord` is distinguishable (documented as an implementation nuance, not a locked decision) |
| New `IsDisposed` manager pass-through | Route through `ColdReadService::HasDisposed` | The cold-read hook object is owned by the dag syncer's cold chain; GlobalDB does not naturally expose it — the manager pass-through mirrors `GetColdUploadState`'s proven D-09 shape |

**Installation:** none — zero new dependencies (STATE.md v1.2 ruling).

## Package Legitimacy Audit

Not applicable — this phase installs no external packages. All mechanisms are in-tree (verified by direct reads above). No `[ASSUMED]` package names appear in this research.

## Architecture Patterns

### System Architecture Diagram

```text
                        ┌───────────────────────────── concurrent by design (D-01) ─────────────────────────────┐
                        │                                                                                     │
 TxPruner timer thread  │                                                      GC thread (10-min passes)          │
 ───────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────┼──────
 RunCycle (:146)        │                                                     GcPassOnce (:860, gc_pass_mutex_)    │
  ├─ Evaluate (pure)    │                                                      ├─ heads snapshot + full walk       │
  ├─ group filter       │                                                      ├─ eligibility scan UNDER            │
  │   └─ ColdGateAdmitsGroup (:67)                                             │     cold_store_mutex_ (:1021)      │
  │       ├─ Durable → admit                                                     │     └─ kEvictionDurabilityGate    │
  │       ├─ NoRecord ──[NEW D-10]── consult LocalBlockStore::IsDisposed ───────┼── reads same journal ──────────┤
  │       │                 ├─ disposed → stranded counter (defer)               │                                  │
  │       │                 └─ absent   → cold_deferred_groups (today)           │                                  │
  │       └─ Pending/Accepted/Unreadable → defer (today)                         ├─ delete-time heads re-check       │
  └─ per-tx EraseTransactionEntryPruned (:301)                                   ├─ HALF 1 EvictLocalAndMarkDisposed │
       └─ GlobalDB::EraseEntry (:1512) ── compose lock ──                        │    (cold bytes+journal+disposed    │
            ├─ guards 1-4 (:1548-1585)                                           │     marker, cold_store_mutex_)     │
            ├─ guard 5 cold re-check (:1608) ── lifecycle→cold_store_mutex_ ─────┼── BOTH READERS SERIALIZE ───────┤
            ├─ stage: set rows + block + raw map + BOTH markers (:1636-1663)     └─ HALF 2 RunHotCleanup (:1317)    │
            ├─ ONE commit (:1664)                                                    ├─ batch: CID key + rows        │
            ├─ post-commit seal re-assert (:1666-1681)                               └─ A6 DeleteCIDBlock (:1352)    │
            └─ [NEW COMP-01] post-commit DeleteCIDBlock (:~1682)  ←──── mirrors A6 ordering ─────┘
                                                                                              ▲
 concurrent LRU inserters (NO compose lock):                                                  │
   FetchNodeFromColdStorage rehydrate :898 ───────────────────────────────────────────────────┘
   BlockReceivedCallback :1034 (libp2p io_context)                                    lru_cid_cache_
```

A reader traces the primary use case: a CID caught by both pruners — TxPruner's erase commits its batch; the post-commit delete evicts whatever a concurrent insert placed in the LRU between guard 3 and commit; GC's own A6 delete is idempotent over the same cache; both orders converge because every half is idempotent on absent keys and seals are never staged by either.

### Recommended Project Structure (new files this phase)

```text
SuperGenius/
├── src/crdt/globaldb/globaldb.cpp            # EraseEntry post-commit DeleteCIDBlock (SC1)
├── src/crdt/globaldb/globaldb.hpp            # (only if the new test seam declares here)
├── src/crdt/globaldb/ColdStorageManager.cpp  # D-12 comment at EvictLocalAndMarkDisposed; (optional) IsDisposed pass-through
├── src/transaction/TxPruner.cpp              # D-10 disposed consult in ColdGateAdmitsGroup + INFO line
├── src/transaction/TxPruner.hpp              # stranded counter in PruneCycleStats
├── test/src/crdt/cold_compose_matrix_test.cpp   # NEW — SC2 interleave matrix (seam-stepped + barrier legs), Tier-1
│      (+ registration in test/src/crdt/CMakeLists.txt, LABELS "Tier1")
│      (+ Tier-3 live SC3 leg — either here behind an env gate or a sibling file, per fixture discipline)
.planning/workstreams/rocksdb-backup/
├── notes/ (or phase dir — Agent's Discretion)  # D-12 ruling doc: starvation analysis + Interaction-C + v2 pointer
```

### Pattern 1: Compose-don't-pick (D-04/D-05 posture)
**What:** production changes compose at the existing single home (`EraseEntry`) and the existing gate (`ColdGateAdmitsGroup`); GC's sanctioned order and the evaluator stay untouched.
**When to use:** every production edit this phase.
**Evidence:** GC's `RunHotCleanup` order is documented as sanctioned at :1324-1333; `PruneEligibility` carries the Phase-14 purity contract (cold_prune_gate_test.cpp header quotes it verbatim; the phase-level purity gate was `git diff --exit-code 2af184fa1` on `PruneEligibility.{hpp,cpp}` — Phase 16 needs no PruneEligibility edit at all, since the disposed consult routes through the library API, not a new key builder).

### Pattern 2: Two-layer proof (D-06/D-08)
**What:** every correctness claim gets (a) a deterministic seam-stepped leg reproducing the exact ordering, and (b) a barrier-driven real-thread leg; convergence asserted at byte level (prefix-spy) AND observable level (`HasBlock`/`getNode`/evidence predicate).
**When to use:** SC1's window counter-test, SC2's matrix, SC3's defer test.

### Pattern 3: Dedicated counter, never a failure reason (Phase 14 D-03 → D-10)
**What:** distinct unhealthy states get distinct counters surfaced in the per-cycle INFO line — the stranded-by-disposal split extends `cold_deferred_groups`/`cold_unreadable_groups`.

### Anti-Patterns to Avoid
- **Deleting the LRU entry on interrupt-abort paths:** hook steps 1-3 return early WITHOUT committing (globaldb.cpp:1637-1650) — nothing was erased, so the LRU entry is NOT stale there. Only post-commit paths invalidate. (The `POST_COMMIT_ERASE_ANOMALY` return at :1678 also follows a landed commit — whether the delete precedes that return is a planner call; the bytes are gone either way.)
- **Consulting disposed markers on Pending/Accepted:** the journal record exists — the block was never disposed; consult only the `NoRecord` arm.
- **Hand-building disposed-marker keys in TxPruner:** Pitfall 5's one-builder-per-namespace rule — route through the library API.
- **Sleeps in race tests:** barriers + poll predicates only (v1.1 discipline; Windows/macOS lanes).
- **Second erase driver:** everything flows through `EraseTransactionEntryWithMarker` → `EraseEntry`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---|---|---|---|
| LRU invalidation | Custom cache-coherence or insert locking | `DeleteCIDBlock` post-commit | Idempotent no-op on absent keys; GC already proved the ordering (A6) |
| Exact-keyspace assertions | Substring/overlap matching | `PrefixSpyHotStore` | Phase 11 instrument; substring matching is Pitfall 5's named trap |
| Deterministic interleavings | Custom flags/timeouts | The three interrupt-hook families | Steps already fire at every relevant boundary; `true`-aborts prove all-or-nothing |
| Disposed-marker lookup | New key builder in TxPruner/PruneEligibility | `LocalBlockStore::IsDisposed` (via manager pass-through) | Library owns the keyspace; third builders are the crossfire trap |
| Journal-state injection | Fakes mocking the journal | Direct journal-CF seeding (D-08 kit) | The gate reads the journal, not bytes; injection is faithful and deterministic |
| Tier registration | Plain addtest | `addtest` + `set_tests_properties(LABELS "Tier1")` | addtest has no LABELS support (CMakeLists.txt:88-91 documents this) |

**Key insight:** every mechanism this phase needs already exists in-tree and is line-verified; the work is one ~5-line production insertion, one gate-arm refinement, comments, and a large evidence suite.

## Common Pitfalls

### Pitfall 1: SC1 test that doesn't reproduce the actual window
**What goes wrong:** the counter-test inserts into the LRU BEFORE `EraseEntry` starts — guard 3 then rejects the erase (INVALID_PARAMETERS), and the test passes vacuously without exercising the post-commit path.
**Why:** the existing hook's contract is abort-on-true at steps 1-3; there is no fire-and-continue seam between guard 3 and commit.
**How to avoid:** the new seam (Agent's Discretion: placement/naming) must fire AFTER guard evaluation and BEFORE `batch->commit()` (:1664) with a continue contract — the hook performs `AddCIDBlock( cid, node )` mid-window and lets the erase proceed; the assertion is `GrabCIDBlock( cid )` fails post-return (pre-fix: serves stale node — red). A real-thread leg parks the erase on the seam while a second thread drives `FetchNodeFromColdStorage` (or `AddCIDBlock`) — barrier, never sleep.
**Warning signs:** test passes with the fix reverted; assertions only on `IsCIDInCache`.

### Pitfall 2: Matrix asserts end-states but not fixed-point equivalence
**What goes wrong:** each interleaving's end state is checked against its own expectations; the two erase orders are never compared to EACH OTHER.
**How to avoid:** D-08's two layers: run order A (TxPruner-then-GC) and order B (GC-then-TxPruner) from identical fixtures; assert (a) prefix-spy key-set byte-equality across every touched keyspace, and (b) `HasBlock`/`getNode`/`LookupPruneEvidence`/`LookupPrunedBlockEntry` answer identically from both end states.

### Pitfall 3: Crossfire invariants checked by substring
**What goes wrong:** "only these rows touched" asserted via key-substring matching misses sibling-namespace eats (elems namespace is a SIBLING under the set root; `GetKeysPrefix` carries no trailing slash — empirically pinned in 11-02).
**How to avoid:** exact prefix enumeration per keyspace: `/prune/tx/`, `/prune/blk/`, disposed markers (via `GetDisposed`), tombstone/set rows, seal rows (via `isResolved`, never the `"sealed"` literal — GATE-03 bans it in production src/), binary CID keys.
**Warning signs:** any new test code concatenating prefix strings.

### Pitfall 4: The split counter misclassifies the in-compose refusal
**What goes wrong:** guard 5's `COLD_NOT_DURABLE` (RunCycle :305-318) increments `cold_deferred_groups` even when the cause was disposal — the stranded mass leaks back into the undifferentiated counter mid-cycle.
**Why:** guard 5 collapses all non-Durable states into one error value; the state isn't visible at the call site.
**How to avoid:** classify at admission (`ColdGateAdmitsGroup`, where `NoRecord` is distinguishable); accept that a mid-cycle disposal re-classifies next cycle (the group is re-admitted and hits the split arm). Document this one-cycle lag in the ruling doc — it is observability latency, not misclassification of the eventual steady state.

### Pitfall 5: Layering inversion in test wiring
**What goes wrong:** new globaldb-scoped suites link `genius_transaction_objs` for PruneEligibility helpers → LNK2019-by-design (the layering rule in `src/crdt/globaldb/CMakeLists.txt`).
**How to avoid:** seed markers via direct `PutRaw` at `PRUNE_BLOCK_MARKER_PREFIX` with byte-identical records (the 15-03 reconciled pattern), or place suites needing the helpers where `genius_node_test`'s whole-archive already provides them.

### Pitfall 6: Verify commands naming files instead of ctest targets
**What goes wrong:** plan verify steps name `globaldb_erase_test.cpp` / `crdt_erase_test.cpp` — not ctest names; `-R` silently skips (the exact no-silent-drop failure TEST-01 prohibits; caught twice in 15-03).
**How to avoid:** ctest registration names only: `cold_prune_gate_test`, `cold_prune_toctou_test`, `cold_evidence_matrix_test`, `cold_storage_fault_race_test`, `globaldb_integration_test`, `crdt_test`, `node_startup_test` (walk legs live there).

### Pitfall 7: macOS/Windows flake classes in the real-thread legs
**What:** barrier waits on starved runners; zombie `cl.exe`/RocksDB `LOCK` fixture-dir contention; CloudflareWARP adapter (environmental — document, don't chase).
**How to avoid:** poll predicates never fixed sleeps; distinct base path per node/fixture; env-knob reproducibility on every nondeterministic test (jitter seeds like `Jitter_PairwiseSeededIterations` :1616); gtest filter grammar positive-negative with ONE dash.

### Pitfall 8: Editing GC's sanctioned order "for symmetry"
**What:** any edit to `RunHotCleanup`'s batch/A6 sequence violates D-04's explicit "stays untouched" — the double-delete is harmless precisely because neither side coordinates.

## Code Examples

### SC1: the post-commit close (insertion at globaldb.cpp:~1682)
```cpp
        BOOST_OUTCOME_TRY( auto still_resolved, m_dagSyncer->isResolved( cid ) );
        if ( !still_resolved )
        {
            m_logger->error( "{}: seal marker vanished after erase - seal-addressing bug (erase already committed)",
                             __func__ );
            return outcome::failure( Error::POST_COMMIT_ERASE_ANOMALY );
        }

        // [COMP-01, D-04] Post-commit LRU invalidation — GC-parity with
        // RunHotCleanup's A6 ordering: a concurrent GrabCIDBlock-path
        // insert (FetchNodeFromColdStorage rehydrate / BlockReceivedCallback)
        // between guard 3's compose-start check and this commit cannot
        // survive — the stale entry would serve erased bytes through
        // HasBlock's second term. Unconditional for EVERY caller of
        // EraseEntry (single home); idempotent when the cache never held
        // the CID; takes no lock (no compose-lock edge). [D-05: guard 3
        // stays — admission semantics unchanged, this only closes the
        // window.]
        (void)m_dagSyncer->DeleteCIDBlock( cid );

        return outcome::success();
```
// Source: composed from [VERIFIED: globaldb.cpp:1666-1684] + [VERIFIED: ColdStorageManager.cpp:1346-1352 A6 comment]; shape mirrors GC's `(void)gc_dag_syncer_->DeleteCIDBlock( cid_key );`.

### D-10: the NoRecord split (TxPruner.cpp ColdGateAdmitsGroup arm)
```cpp
                case crdt::ColdUploadState::NoRecord:
                    // [COMP-03, D-10] Cross-marker skip: NoRecord on a
                    // cold-bearing node means never-spilled OR GC-disposed
                    // (EvictLocalAndMarkDisposed deleted the journal record
                    // while remote S3 still serves). Consult the GC module's
                    // disposed-marker keyspace THROUGH the library API (no
                    // third builder): disposed strands the group (visible
                    // counter, never an erase — under-prune is the fail-safe
                    // direction); absent keeps today's cold_deferred path.
                    if ( globaldb.IsColdDisposed( cid.value() ) )
                    {
                        ++stats.cold_disposed_stranded_groups;  // name: Agent's Discretion
                        return false;
                    }
                    ++stats.cold_deferred_groups;
                    return false;
```
// Source: composed from [VERIFIED: TxPruner.cpp:118-128]; the `IsColdDisposed` bridge mirrors [VERIFIED: globaldb.cpp:1486-1509 GetColdUploadState → ColdStorageManager.cpp:727-731]; counter name is explicitly Agent's Discretion.

### D-11 leg (a): journal-injection disposal simulation (test sketch)
```cpp
// Delete the journal record directly = GC disposal simulation (Phase 14 D-08 kit).
// Red-first: with the consult absent, the cycle counts cold_deferred_groups;
// post-fix it counts the stranded counter and erases NOTHING.
ASSERT_TRUE(DeleteJournalRecordCf(real_globaldb, cid));   // direct CF write, deterministic
auto stats = DriveOnePruneCycle(real_globaldb, seeded_group);
EXPECT_EQ(stats.erased, 0u);                              // under-prune, never destruction
EXPECT_EQ(stats.cold_disposed_stranded_groups, 1u);       // the split (name TBD)
EXPECT_EQ(ValueStillPresent(real_globaldb, tx_key), true); // the last hot copy survives
```
// Source: kit recipe from [VERIFIED: cold_prune_gate_test.cpp:1-64 header — "pre-seed the journal column family directly ... against a real GlobalDB, no live remote, deterministic"].

## State of the Art (internal evolution)

| Old Approach | Current Approach | When Changed | Impact |
|---|---|---|---|
| `EraseEntry` single opaque `extra_entry` pair | `extra_entries` vector carrying BOTH markers | Phase 15 (`638053925`) | SC1's post-commit delete joins a widened, marker-aware path |
| 2-term `HasBlock` (hot + LRU) | 4-term (hot, LRU, cold-dir, disposed-marker) | v1.1 Phases 9/11 | D-08's observable-equivalence surface is richer — assert all four terms' inputs converge |
| Cold chain consults no prune evidence | `FetchNodeFromColdStorage` evidence consult, terminal refusals | Phase 15 (`HISTORY_PRUNED_LOCALLY`/`PRUNE_EVIDENCE_CORRUPT`) | Matrix rows must treat refused CIDs as terminal in both orders |
| Single `cold_deferred_groups` counter | Split: deferred vs unreadable (Phase 14) → +stranded-by-disposal (this phase, D-10) | Phase 14 → 16 | Operator-visible stranded mass feeds Phase 17/18 |
| Research anchors at `2af184fa1` | Post-Phase-15 line `af644481f` | Phase 15 close | This document's Anchor Re-Location Record supersedes all earlier line numbers |

**Deprecated/outdated:** v1.2-research line cites for `EraseEntry` (:1374-1451), `StageBlockRemoval` (:618-633), `RunCycle` (:141-176), GC A6 (:1346-1348) — do NOT use in plans.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Guard 5's error collapsing (all non-Durable → `COLD_NOT_DURABLE`) means the split classification must live at admission, accepting a one-cycle observability lag for mid-cycle disposals | Pitfall 4 / Code Examples | Low — steady-state classification is correct; if the planner wants zero lag, guard 5's error would need widening (a Phase-14 contract change — likely rejectable as out of scope) |
| A2 | `lru_cid_cache_` internal synchronization makes `DeleteCIDBlock` under the compose lock safe (no external lock taken at :1258-1265; `GrabCIDBlock`/`IsCIDInCache` are `const` and unlocked) | Anchor Record §4 | Low-Medium — if the LRU type required an external mutex, GC's A6 call site (outside that mutex) would already race; the existing unlocked usage at 5 sites is the evidence. Plans should not introduce `dagMutex_` into the call |
| A3 | `ColdStorageManager` needs a small new `IsDisposed`-shaped pass-through under `cold_store_mutex_` (none exists; only `GetDisposed()` full enumeration) | Code Examples D-10 | Low — alternative is exposing the cold-read hook; both are small. Flagged so the planner budgets the accessor |
| A4 | The `/prune/blk` marker's back-reference record (erasing tx hash + generation) needs no extension for SC2's crossfire rows (presence + byte-identity is what the matrix asserts) | Pitfall 3 | Low — Phase 17 measurement may extend it later; not this phase's concern |
| A5 | Tier-1 suites can drive a real GC pass hermetically (InMemory fakes + forced `GcPassOnce` invocation or its natural timer under test-accelerated retention) for the seam-stepped matrix legs, as `cold_storage_gc_test` already does | Standard Stack / Patterns | Low — the GC suite is the precedent; if the timer cannot be forced deterministically, `GcPassOnce` is public on the manager |

## Open Questions

1. **New seam contract shape (Agent's Discretion, needs a planner ruling)**
   - What we know: the existing `SetEraseInterruptHookForTest` aborts on true at steps 1-3 (hpp :527-534); SC1 needs fire-and-continue between guard 3 and commit.
   - What's unclear: extend the existing hook with step 4 whose return is ignored (overloads the contract) vs a sibling hook (e.g., a mid-compose observer) — the CONTEXT hints "sibling of `kInterruptBeforeErase`".
   - Recommendation: sibling observe-and-continue hook with its own steps, documented as NOT an abort seam — keeps the abort contract honest.

2. **Whether the Tier-3 live SC3 leg lives in a new file or extends `cold_prune_live_smoke_test.cpp`**
   - What we know: the Tier-3 precedent is `cold_prune_live_smoke_test` (CMakeLists :440-470, env-gated, loud-skip-verified).
   - Recommendation: planner's call; a sibling file keeps the runbook surface distinct.

3. **Does the SC1 delete also run on the `POST_COMMIT_ERASE_ANOMALY` path?**
   - What we know: the commit landed there too (:1666-1681), so the LRU entry is equally stale; but the function returns failure immediately.
   - Recommendation: place the delete BEFORE the seal re-assert's failure return OR duplicate it on that path — planner rules; document either way (the bytes are gone; leaving a stale LRU entry on an anomaly path re-opens the class the fix closes).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| SuperGenius build tree (`build/Windows/{Debug,Release}`) | All suites | ✓ | present in workspace | — |
| CTest tier lanes (`-L Tier1`/`-L Tier3`) | D-09 registration | ✓ | in `test/src/crdt/CMakeLists.txt` | — |
| `SGNS_COLD_STORAGE` CMake guard + InMemory S3 fakes | Cold-enabled legs | ✓ | 15-03 landed the guarded block for `globaldb_integration_test` | — |
| Live cold stack (real drainer/GC/S3) | Tier-3 SC3 leg only | dev-gated | env knob | loud-skip (the 14-03 runbook precedent) |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** the Tier-3 live leg is dev-gated by design (D-11) — loud-skip verification is the shipped evidence in CI.

*(Validation Architecture section omitted — `workflow.nyquist_validation` is explicitly `false` in `.planning/config.json`.)*

## Security Domain

`security_enforcement: true`, ASVS level 1, block on high. This phase adds no new network, auth, or input-parsing surface; the security-relevant content is local data integrity.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | no new surface |
| V3 Session Management | no | no new surface |
| V4 Access Control | no | node-role gating unchanged (`TxPruner::New` NodeType::Light check, TxPruner.cpp:135-145 — untouched) |
| V5 Input Validation | yes (existing, unchanged) | malformed `/prune/*` markers already fail closed (`PRUNE_EVIDENCE_CORRUPT`, PruneEligibility.cpp:317-328 discipline); the matrix asserts this stays loud |
| V6 Cryptography | no | CID content addressing untouched; `EquivalentCidClaim` verification stays in force in all fixtures |
| V8 Data Protection | yes (local) | SC1 closes an information-exposure bug class: a stale LRU entry serves locally-erased bytes through `HasBlock`'s second term after the erase committed — the fix is the control |

### Known Threat Patterns for this domain

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Stale-cache serving erased bytes | Information Disclosure | SC1's post-commit `DeleteCIDBlock` (this phase) |
| Destruction of the last copy under concurrent pruning | Tampering/DoS | Guard 5 + D-02 lock serialization (verified) + fail-to-under-prune everywhere (D-10); SC3 test asserts the direction |
| Contradictory durability beliefs between destructive systems | Tampering | Both readers serialize on `cold_store_mutex_` (verified this session); ruling documented at both homes (D-12) |
| Crossfire erasing another namespace's evidence | Tampering | One-builder-per-namespace + exact-prefix matrix rows (D-07) |

## Sources

### Primary (HIGH confidence)
- Direct file reads (this session, SuperGenius @ `af644481f`): `globaldb.cpp` (:1486-1690), `globaldb.hpp` (:480-585, :769, :810-812), `graphsync_dagsyncer.cpp` (:340-435, :700-760, :772-812, :823-960, :990-1050, :1180-1300), `ColdStorageManager.cpp` (:1000-1100, :1240-1370), `ColdReadService.cpp` (:276-305 grep), `TxPruner.cpp` (:55-415), `TxPruner.hpp` (:60-110, :263-301, :356-375), `PruneEligibility.hpp`/:cpp (marker homes), `TransactionManager.cpp` (:4700-4800), `test/src/crdt/CMakeLists.txt`, `cold_prune_gate_test.cpp` (:1-130), `cold_evidence_matrix_test.cpp` (structure), `cold_storage_fault_race_test.cpp` (structure)
- `.planning/workstreams/rocksdb-backup/phases/16-...-hardening/16-CONTEXT.md` — D-01..D-12 (binding)
- `.planning/workstreams/rocksdb-backup/REQUIREMENTS.md` — COMP-01/02/03 + governing invariants 1-4
- `.planning/research/ARCHITECTURE-v1.2-rocksdb-backup.md` §(c) — overlap inventory + three work items
- `.planning/research/PITFALLS-v1.2-rocksdb-backup.md` — Pitfalls 4/5/11, Interaction C, test-guidance 4/6/7
- `.planning/workstreams/rocksdb-backup/phases/14-.../14-CONTEXT.md` (D-02/D-06/D-07/D-08/D-09), `15-.../15-CONTEXT.md` (D-01..D-07), `15-03-SUMMARY.md` (deviations: layering rule, ctest names, SGNS_COLD_STORAGE wiring)

### Secondary (MEDIUM confidence)
- `.planning/research/SUMMARY-v1.2-rocksdb-backup.md` — phase-4 scope row; `STACK-v1.2` row 5 ("unify or explicitly sequence" — ruled: sequence); `FEATURES-v1.2` TS-3 (quotes truncated in grep; substance cross-checked against ARCHITECTURE §(c))

### Tertiary (LOW confidence)
- None — no external web sources were consulted (all search providers disabled in config; the domain is entirely in-repo). No claim in this document rests on training data alone.

## Metadata

**Confidence breakdown:**
- Anchor re-location: HIGH — every anchor read in full this session against HEAD `af644481f`, verbatim quotes recorded
- D-02 lock verification: HIGH — both reader paths traced through their lock scopes (`cold_store_mutex_` :1021/:727-731; compose→lifecycle→cold_store chain :1486-1509)
- Production-change shape (SC1/SC3): HIGH — insertion points and primitives line-verified; counter/bridge naming left to planner per Agent's Discretion
- Test-infrastructure reuse: HIGH — suites, fixtures, labels, and the 15-03 layering/ctest-name lessons verified
- Pitfalls: HIGH (system-specific, source-grounded)

**Research date:** 2026-11-18
**Valid until:** the next commit touching `EraseEntry`, `RunHotCleanup`, `ColdGateAdmitsGroup`, or the interrupt-hook families (Phase 16's own edits will re-drift these anchors — executors must re-grep before editing)
