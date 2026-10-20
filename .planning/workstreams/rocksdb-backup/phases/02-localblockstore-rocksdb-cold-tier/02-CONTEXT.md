# Phase 2: LocalBlockStore (RocksDB Cold Tier) - Context

**Gathered:** 2026-10-20
**Status:** Ready for planning

<domain>
## Phase Boundary

`LocalBlockStore` delivers durable local persistence for CID-addressed blocks through its own RocksDB instance — the LocalCommitted tier and the crash-safety machinery (atomic writes, durable upload journal, verify-on-read) that Phase 4's S3 tier reuses. This phase delivers:

1. `LocalBlockStore` backend: own RocksDB instance/directory (consumer-provided RocksDB via `find_package(RocksDB CONFIG)`, stable API surface compatible with both 9.4 and 11.1 — never the GlobalDB handle)
2. Atomic block writes via single-WriteBatch commit (block bytes + journal record together)
3. The durable upload journal (`PendingUpload` / `UploadedAccepted` / `UploadedDurable`), active from the first Put, with restart reconciliation and pending-set enumeration on the tooling interface
4. Journal state-transition methods on the backend type (Phase 4's uploader composes over them)
5. Verify-on-read with corruption self-heal (evict-and-surface)
6. `EvictLocal` (unconditional, caller-owned policy)
7. Crash-safety proof via in-process reopen tests through the Phase-1 `FaultController` seam (minimal: the two success criteria + corruption rejection)
8. Phase-1 conformance kit green against `LocalBlockStore`; `FaultController` implemented so fault conformance tests run
9. `DEPENDS rocksdb` added to the sgns-blockstore entry in `CommonTargets.cmake`

Out of this phase: S3/minio-cpp anything (Phases 3–4), the full fault/crash matrix (Phase 5), durability-gated eviction policy (deferred future work), consumer wiring in `CommonBuildParameters.cmake`, any SuperGenius production change.

Requirements: BACK-03, BACK-04.

</domain>

<decisions>
## Implementation Decisions

### Storage layout
- **D-01:** Block bytes live **inside RocksDB as values** under `cid.toBytes()` keys (byte-compatible with `RocksdbDatastore` — future migration aid) in the store's own instance/directory. No app-level blob files, no second storage substrate — **Reversibility:** costly — the on-disk key/value layout is the migration anchor; a later blob-file mode could only be added behind options, never swapped out from under existing stores
- **D-02:** Write atomicity = **one WriteBatch** committing block bytes + journal record together. An interrupted write leaves NOTHING (Get → `NotFound`, journal has no record) — success criterion 3 satisfied by construction. BACK-03's "(temp + fsync + rename)" is satisfied by RocksDB's own WAL commit machinery — headers document this mapping. Criterion 4's "sweeps stale temp files" is **vacuous by design** (no temp files exist); startup sweep = journal reconciliation only — **Reversibility:** costly — the crash-safety contract is what the conformance kit, crash tests, and Phase-5 matrix assert against

### Upload journal
- **D-03:** Journal is **active from day one**: every `Put` atomically records `state=PendingUpload` in the same WriteBatch as the block (the PITFALLS warning — journal must exist from the slice's first write path or later tests fight the design). Records persist until explicitly transitioned; nothing auto-drains them in this phase — **Reversibility:** costly — Phase 4's uploader and Phase 5's crash matrix bind to these birth semantics
- **D-04:** Journal lives in a **column family of the same RocksDB instance** — the structural consequence of D-02 (a WriteBatch cannot span databases); one WAL covers block+journal atomicity — **Reversibility:** costly — journal substrate change is an on-disk migration
- **D-05:** Restart reconciliation surfaces the pending set through **enumeration on the tooling/audit interface** (CORE-06 placement — enumeration never on `BlockStore`). Synchronous scan at open; NO callback machinery in v1 — Phase 4's uploader iterates the set — **Reversibility:** reversible — callbacks can be added later additively
- **D-06:** State transitions are **concrete methods on `LocalBlockStore`** (e.g. `MarkUploadedAccepted(cid)` / `MarkUploadedDurable(cid)`) plus a state-reading accessor — never on the `BlockStore` interface. Phase 4 composes without reopening internals; `EvictLocal` and tooling can read state — **Reversibility:** costly — the method set on the published backend type binds once Phase 4 calls it

### Crash testing
- **D-07:** Crash simulation = **in-process reopen through the `FaultController` seam**: tests inject failure points, then close-without-clean-shutdown and reopen — RocksDB WAL recovery does the real work. No subprocess-kill machinery (Windows portability weighed) — **Reversibility:** reversible — Phase 5 may add subprocess kills additively
- **D-08:** Phase-2 crash scope = **minimal proof of the two success criteria**: crash-before-commit → `NotFound`; crash-after-commit → block + pending record both present and reconciled; plus corruption rejection via the conformance kit. The full fault matrix (upload-interleaved kills, etc. — which need Phase 4) stays in Phase 5 — **Reversibility:** reversible — planning may shift the boundary if a case is cheap to include

### Corruption & eviction
- **D-09:** Corrupt-on-read = **evict + surface**: the detecting `Get` returns `Corrupt` with source attribution for THAT call, and atomically removes the bad entry (block bytes + journal record) so subsequent Gets → `NotFound` and a re-Put repairs (the research's "self-heal"). `Get` becomes write-capable only on the corruption path — **Reversibility:** costly — conformance assertions and Phase-5 corruption tests bind to self-heal semantics
- **D-10:** `EvictLocal` is **unconditional**: atomically removes block bytes + journal record regardless of journal state; the caller owns eviction policy. Durability-gated eviction remains deferred future work (REQUIREMENTS Future list / architecture-doc Phase 5). The data-loss-when-pending caveat is documented in the header — **Reversibility:** costly — the Phase-1 guard test placement (D-16 there) and the future policy layer build on these semantics

### the agent's Discretion
- Column-family layout details (blocks CF vs journal CF naming, options)
- Journal record value schema (state encoding, any timestamps/counts)
- RocksDB options/tuning (compression, WAL settings) and the shape of any `LocalBlockStoreOptions` beyond the directory path
- RocksDB error → taxonomy mapping specifics (IO/lock/corruption errors → `TemporarilyUnavailable`/`Corrupt` per frozen CORE-02 rules)
- `FaultController` fault-point granularity for LocalBlockStore
- Test-file layout inside the repo's `test/` conventions (conformance instantiation file, crash-test file)
- Exact transition-method and accessor names (the D-06 surface, not its placement)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Authoritative design
- `supergenius-sharded-ipld-cache-architecture.md` (workspace root) — the architecture doc this milestone implements; its local-cache atomicity rules and eviction ≠ delete invariants

### Workstream planning
- `.planning/workstreams/rocksdb-backup/REQUIREMENTS.md` — BACK-03, BACK-04 (this phase); Future list (eviction-policy gating deferred)
- `.planning/workstreams/rocksdb-backup/ROADMAP.md` — Phase 2 goal + 4 success criteria
- `.planning/workstreams/rocksdb-backup/phases/01-blockstore-contract-memory-backend-conformance-kit/01-CONTEXT.md` — frozen Phase-1 decisions D-01..D-16 this phase builds on (result envelope, `PutOutcome`, `FaultController`, `EvictLocal` placement, conformance macro)

### Research (2026-10-19)
- `.planning/research/SUMMARY-rocksdb-backup-2026-10-19.md` — "Phase 2: LocalBlockStore over RocksDB" section: deliverables list, avoids-list
- `.planning/research/PITFALLS-rocksdb-backup-2026-10-19.md` — pitfalls 3 (torn writes) & 4 (crash windows); P2 mitigation row (temp+fsync+rename / journal / verify-on-read) — interpreted through D-02/D-03 above
- `.planning/research/ARCHITECTURE-rocksdb-backup-2026-10-19.md` — anti-patterns 1 & 6 (standalone instance; never GlobalDB handle); `cid.toBytes()` key compatibility with `RocksdbDatastore`; `globaldb.cpp:322-344` evidence
- `.planning/research/STACK-rocksdb-backup-2026-10-19.md` — RocksDB 9.4.0 vs 11.1.2 dual-compat mandate, stable-API-only rule, `find_package(RocksDB CONFIG)` convention

### Phase-1 codebase (the foundation being extended)
- `thirdparty/sgns-blockstore/include/sgns-blockstore/BlockStore.hpp` — the frozen interface LocalBlockStore implements
- `thirdparty/sgns-blockstore/include/sgns-blockstore/BlockStatus.hpp`, `Durability.hpp`, `Options.hpp`, `Capabilities.hpp`, `Cid.hpp` — frozen type system; Cid.hpp carries the library-local `result<R,S,policy::terminate>` alias ALL new headers must use (never bare `outcome::result<..., BlockStatus>`)
- `thirdparty/sgns-blockstore/include/sgns-blockstore/FaultController.hpp` — the seam D-07 crash tests extend
- `thirdparty/sgns-blockstore/include/sgns-blockstore/BlockStoreTooling.hpp` — where D-05 pending-set enumeration lands
- `thirdparty/sgns-blockstore/test/conformance/BlockStoreConformanceTests.hpp` — the kit LocalBlockStore instantiates (`SGNS_BLOCKSTORE_CONFORMANCE_TESTS`)
- `thirdparty/sgns-blockstore/src/MemoryBlockStore.cpp` — reference backend pattern (status mapping, verification)

### Build integration
- `thirdparty/build/CommonTargets.cmake` — sgns-blockstore entry (Phase 1) gains `DEPENDS rocksdb` + `-DRocksDB_DIR:PATH=${_FINDPACKAGE_ROCKSDB_DIR}`; rocksdb precedent at `~:140-173`
- `Coding Standards.md` (workspace root) — C++ style: Ullman braces, PascalCase types/headers, `m_`/trailing-underscore members, Doxygen on public interfaces

### Testing conventions
- `.planning/codebase/TESTING.md` — GTest via superbuild, verification-inside-`build/<Platform>/<Config>`-tree rule

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Phase-1 contract headers (`include/sgns-blockstore/*.hpp`) — everything LocalBlockStore implements is already frozen; no header changes expected except adding `LocalBlockStore.hpp` and tooling enumeration
- `FaultController.hpp` + conformance-kit fault probing — implementing the controller on LocalBlockStore yields fault conformance tests for free (Phase-1 D-10)
- Library-local `result<R,S,policy::terminate>` alias in `Cid.hpp` — **mandatory** for any new header (boost outcome + struct error types landmine; `.value()` on failure terminates — guard with `has_value()`)
- Superbuild RocksDB target (`thirdparty/rocksdb`, 9.4.0) + `_FINDPACKAGE_ROCKSDB_DIR` export — already orchestrated in CommonTargets

### Established Patterns
- `MemoryBlockStore` — status mapping + CID verification pattern to mirror
- Conformance instantiation via one macro in the backend's test TU
- `ExternalProject_Add` + `DEPENDS` + `BUILD_BYPRODUCTS` for ninja determinism
- `outcome::result` conventions with plain-GTest assertions (no outcome macros in kit)

### Integration Points
- `thirdparty/build/CommonTargets.cmake` sgns-blockstore entry — add rocksdb dependency (BUILD/DEPENDS wiring is this phase's only superbuild change)
- `BlockStoreTooling.hpp` — gains the pending-uploads enumeration surface (D-05)
- Phase 4 seam: transition methods (D-06) + pending set (D-05) are exactly what `S3BlockStore`'s uploader will consume

### Landmines (verified in Phase 1)
- `policy::terminate` result alias — see above; also never `OUTCOME_TRY` a `CidOf` failure (default `std::error_code` type) into a `BlockStatus` envelope — map explicitly
- `ContentIdentifier` has no default ctor — test fixtures use member-initializers
- Inner-tree build recipe: edit → build `thirdparty/build/Windows/Debug/sgns-blockstore/src/sgns-blockstore-build` → ctest there

</code_context>

<specifics>
## Specific Ideas

- Locked semantic sketch of the Put path: `Put(cid, bytes)` → one WriteBatch{ block-CF: cid.toBytes() → bytes; journal-CF: cid.toBytes() → {state=PendingUpload} } → WAL commit
- Crash-window model (what tests prove): before-commit ⇒ nothing exists; after-commit ⇒ block + PendingUpload both exist. There is no intermediate state — that absence IS criterion 3
- Corrupt-read flow: Get → verify fails → return `Corrupt` (this call) + WriteBatch{ remove block entry; remove journal entry } → later Gets `NotFound` → re-Put repairs
- `EvictLocal` flow: same removal WriteBatch, caller-initiated, journal state irrelevant

</specifics>

<deferred>
## Deferred Ideas

- Durability-gated eviction policy (refuse `EvictLocal` on non-`UploadedDurable`) — explicitly future work per REQUIREMENTS; the backend stays policy-free
- Subprocess-kill crash tests — Phase 5 may add for ground-truth realism
- Startup callback hand-off for pending uploads — additive later if Phase 4 wants push instead of iteration

### Reviewed Todos (not folded)
- "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" (`.planning/todos/2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md`) — matched only on the generic keyword "crash" (score 0.2); unrelated to the BlockStore library; already reviewed and not folded in Phase 1 — stays with base SuperGenius planning

</deferred>

---

*Phase: 2-LocalBlockStore (RocksDB Cold Tier)*
