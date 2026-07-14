# Phase 3: Consumer Integration - Context

**Gathered:** 2026-07-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Update SuperGenius and AsyncIOManager to match Bitswap API and synchronization contract changes from Phase 2, verify all integration points through code review, and document the consumer-facing thread-safety contract. Requirements covered: CONS-01, CONS-02, CONS-03, CONS-04, DOCS-02.

Phase 2's changes that impact consumers: (1) PublishFile/PublishDirectory callbacks now fire on io_context instead of detached threads, (2) cacheDir_ is mutex-guarded, (3) SetMaxPeerAttempts/SetPeerFailureThreshold converted to atomics, (4) GetBlock() lost const — no production code calls it, (5) ContentRequestContext strand-confined.
</domain>

<decisions>
## Implementation Decisions

### Publish Callback Migration
- **D-01:** IPFSSaver keeps temp file cleanup on io_context — no consumer code changes needed. Temp file removal is a fast filesystem operation that won't block io_context.
- **D-02:** Document PublishFile/PublishDirectory callback thread contract (io_context dispatch) via Doxygen @note comments in `bitswap.hpp`. Future consumers need to know this guarantee.
- **D-03:** Bitswap's own `concurrency_publish_test.cpp` is sufficient for publish callback verification. No need to run IPFSSaver integration tests separately.

### Verification Strategy (CONS-01..CONS-04)
- **D-04:** Code review only — builds and existing tests already pass on the primary dev platform (Windows MSVC). No new tests needed.
- **D-05:** Review focus on thread context correctness at each integration call site:
  - HasBlock called from any thread (method is mutex-guarded, no change)
  - setCacheDir called before Bitswap starts async operations (unchanged pattern)
  - PublishFile/PublishDirectory callbacks handle io_context dispatch safely (D-01)
  - Verify no production code calls GetBlock() through a const reference (compile error now)
  - RequestContent callbacks remain on their calling thread context (unchanged)
- **D-06:** CRDT layer correctness (CONS-03) is covered by existing processing and storage tests passing — Bitswap is used indirectly through the processing layer's data availability checks, which are mutex-guarded. No separate CRDT-specific verification needed.

### Documentation (DOCS-02)
- **D-07:** Extend `CONCURRENCY-MAP.md` with a "Phase 3: Consumer Contract" section — a method-by-method table with columns: Method, Caller Thread Requirement, Callback Thread, Mutex/Atomic Guarantee, Phase 2 Change Summary. This is the canonical thread-safety reference for consumers.
- **D-08:** Supplement with inline Doxygen @note comments on methods whose threading contract changed (PublishFile, PublishDirectory, getCacheDir, setCacheDir). Inline docs are minimal pointers — the full contract lives in CONCURRENCY-MAP.md.

### Multi-Platform Build Scope
- **D-09:** Verify on Windows (primary dev platform, already confirmed passing) + let CI handle Linux and other platforms. Phase 2 changes are standard C++ (mutex, atomic, io_context::post) — no platform-specific code.
- **D-10:** CI build results are non-blocking — Phase 3 completes when Windows is verified and code review is done. CI failures on other platforms become bugs to fix, not phase blockers.

### the agent's Discretion
- Exact table column layout in CONCURRENCY-MAP.md consumer contract section.
- Which specific methods get inline Doxygen annotations in bitswap.hpp (minimum: PublishFile, PublishDirectory, getCacheDir, setCacheDir).
- Code review checklist format (informal per-call-site notes or structured table).
- Whether the consumer contract section in CONCURRENCY-MAP.md includes methods that did NOT change (for completeness).
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Planning Docs
- `.planning/ROADMAP.md` — Phase 3 goal, requirements CONS-01..04 + DOCS-02, 4 success criteria
- `.planning/REQUIREMENTS.md` — Detailed per-requirement spec (CONS-01 through DOCS-02)
- `.planning/PROJECT.md` — Project scope, constraints, coding standard, out-of-scope items

### Prior Phase Artifacts
- `.planning/phases/01-audit/CONCURRENCY-MAP.md` — Complete Phase 1 thread-safety audit: 10 findings (C-1 through C-10), data domains table, boundary crossing matrix. **This is the primary document to extend with the consumer contract section.**
- `.planning/phases/01-audit/01-CONTEXT.md` — Phase 1 decisions: severity scale, finding categories, CONFIRMED/SUSPECTED flags
- `.planning/phases/02-fix-test/02-CONTEXT.md` — Phase 2 decisions: fix sequencing (D-01..D-03), detached thread replacement (D-04..D-05), test organization (D-06..D-08), deferred items (D-09..D-10)

### Bitswap Source
- `thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp` — Full class definition, public API surface, 6 mutex domains. Target for Doxygen thread-safety annotations (D-02, D-08).
- `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` — Full implementation. Reference for understanding how Phase 2 fixes work (io_context::post, atomics, mutex additions).

### Consumer Code — SuperGenius
- `SuperGenius/src/account/GeniusNode.cpp` — Bitswap construction (line ~1307), setCacheDir (line ~1314), FileManager::setBitswap (line ~1317), HasBlock (line ~797), RequestContent (line ~802), unpersistBlock (line ~3432)
- `SuperGenius/src/processing/processing_subtask_queue_accessor_impl.cpp` — HasBlock for data availability checks (line ~564)
- `SuperGenius/src/processing/processing_service.hpp` — setBitswap propagation hub (line 70)
- `SuperGenius/src/processing/processing_node.hpp` — setBitswap cascading propagation (line 69)

### Consumer Code — AsyncIOManager
- `thirdparty/AsyncIOManager/src/IPFSSaver.cpp` — PublishFile (line ~107), PublishDirectory (line ~190). Primary consumer of Phase 2's changed callbacks.
- `thirdparty/AsyncIOManager/src/IPFSLoader.cpp` — setBitswap (line ~207), uses Bitswap via IPFSDevice wrapper for RequestContent
- `thirdparty/AsyncIOManager/src/IPFSCommon.cpp` — Standalone Bitswap construction (line ~76), external Bitswap wrapper (line ~86), RequestContent (line ~185)
- `thirdparty/AsyncIOManager/src/FileManager.cpp` — setBitswap propagation center (line ~244), forwards to IPFSSaver and IPFSLoader, extracts cacheDir

### Build System
- `thirdparty/build/CommonTargets.CMake` — ipfs-bitswap-cpp build target and dependency chain
- `thirdparty/AsyncIOManager/CMakeLists.txt` — Bitswap dependency declaration (find_package)
- `SuperGenius/src/account/CMakeLists.txt` — Bitswap linkage in GeniusNode module
- `SuperGenius/src/processing/CMakeLists.txt` — Bitswap linkage in processing module

### Codebase Maps
- `.planning/codebase/ARCHITECTURE.md` — Threading model (Boost.Asio io_context, strands), component dependencies, Bitswap integration points
- `.planning/codebase/INTEGRATIONS.md` — Bitswap's role in the IPFS storage pipeline
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **6 mutex domains** in bitswap.hpp — fixes extend existing synchronization, API surface preserved for all consumer-facing methods except GetBlock() const removal.
- **CONCURRENCY-MAP.md** — Phase 1 deliverable, 503 lines covering every shared state location. Extending this document (D-07) rather than creating a new one keeps thread-safety information consolidated.
- **GTest test infrastructure** — Phase 2 concurrency tests already exercise all changed methods under multi-threaded access. Consumer tests in SuperGenius (processing_result_durability_test.cpp) and AsyncIOManager (ipfs_loader_test.cpp, ipfs_saver_test.cpp) provide integration coverage.

### Established Patterns
- **shared_ptr propagation:** Bitswap is constructed by GeniusNode, stored as shared_ptr, propagated through ProcessingService -> ProcessingNode -> SubTaskQueueAccessorImpl and FileManager -> IPFSSaver/IPFSLoader. All consumers hold shared_ptr — lifetime is safe.
- **Two-phase init:** Bitswap::initialize() configures protocol handler and disk index; Bitswap::start() subscribes to event bus. Consumers call these in order. Unchanged by Phase 2.
- **setBitswap() pattern:** Consistent across all consumers — stores shared_ptr, forwards to downstream components. No consumer stores raw pointer or weak_ptr.

### Integration Points
- **GeniusNode** is the sole constructor of Bitswap in production code. AsyncIOManager's IPFSCommon also constructs Bitswap in standalone mode (tests/examples only — production always gets external Bitswap from GeniusNode via FileManager::setBitswap).
- **IPFSSaver** is the only production consumer of PublishFile/PublishDirectory. Its callbacks do temp file cleanup — confirmed safe on io_context (D-01).
- **SubTaskQueueAccessorImpl** is the only production consumer of HasBlock (for result data availability validation). HasBlock is mutex-guarded — safe from any thread.
- **No production code** calls SetMaxPeerAttempts, SetPeerFailureThreshold, or GetBlock. These are exercised only by the Phase 2 concurrency test suite.

### Phase 2 Changes — Consumer Impact Summary
| Method | Change | Production Consumers Affected | Action Needed |
|--------|--------|------------------------------|---------------|
| PublishFile | Callback fires on io_context | IPFSSaver (line ~107) | Verify callback is io_context-safe (D-01) |
| PublishDirectory | Callback fires on io_context | IPFSSaver (line ~190) | Verify callback is io_context-safe (D-01) |
| getCacheDir/setCacheDir | Mutex-guarded | GeniusNode, FileManager | Verify setCacheDir called before async access (unchanged pattern) |
| HasBlock | Unchanged (already mutex-guarded) | GeniusNode, SubTaskQueueAccessorImpl | No action needed |
| RequestContent | Unchanged | GeniusNode, IPFSLoader | No action needed |
| GetBlock | Lost const | None (test-only) | Verify no production code added that calls via const ref |
| SetMaxPeerAttempts | Converted to atomic | None (test-only) | No action needed |
| SetPeerFailureThreshold | Converted to atomic | None (test-only) | No action needed |
</code_context>

<specifics>
## Specific Ideas

The user confirmed builds and tests already pass on Windows MSVC with updated Bitswap. No new tests needed — code review only for verification. Focus on thread context correctness, not API surface changes (which are minimal). Documentation should extend CONCURRENCY-MAP.md rather than creating new standalone docs.
</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within Phase 3 scope.
</deferred>

---

*Phase: 3-Consumer-Integration*
*Context gathered: 2026-07-09*
