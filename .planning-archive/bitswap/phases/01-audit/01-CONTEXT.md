# Phase 1: Audit - Context

**Gathered:** 2026-07-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Complete thread-safety analysis of `thirdparty/ipfs-bitswap-cpp` — inventory every shared mutable state location, classify synchronization coverage, review all lock usage, and trace all third-party boundary crossings (libp2p, AsyncIOManager, consumer code in SuperGenius). Produce a CONCURRENCY-MAP.md document as the primary audit deliverable.

Requirements covered: AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04, AUDIT-05, AUDIT-06.
</domain>

<decisions>
## Implementation Decisions

### Audit Deliverable Format
- **D-01:** Primary deliverable is a single Markdown document (`CONCURRENCY-MAP.md`) with tables — human-readable, actionable for Phase 2 planning.
- **D-02:** Full structured report containing: data domains table (member→guard→classification), lock call-chain analysis, boundary crossing matrix, thread-entry-point inventory, and a master findings summary table.
- **D-03:** Granularity is every member variable + every call site. Include helper struct fields (ContentRequestContext, BitswapRequestContext) in the inventory.
- **D-04:** Data domains table includes a severity column (CRITICAL/HIGH/MEDIUM/LOW) directly inline — no separate findings section needed for the inventory itself.

### Static Analysis Tooling Strategy
- **D-05:** Manual audit only for Phase 1. No TSAN, Clang thread-safety annotations, or Helgrind setup. Constraint: Windows/MSVC monolithic thirdparty build. May revisit tooling with WSL in Phase 2.
- **D-06:** Balanced audit scope — give equal weight to: unprotected shared state, lock ordering/deadlock paths, async safety (locks held across callbacks), and thread identity assumptions at boundaries.
- **D-07:** Per-request context objects (BitswapRequestContext, ContentRequestContext) MUST be audited as shared mutable state. Their strand confinement should be verified, not assumed.

### Boundary Analysis Depth
- **D-08:** Audit ALL consumer call sites in SuperGenius — GeniusNode (initialization + mirroring), processing layer (ProcessingSubTaskQueueAccessor, ProcessingService, ProcessingNode), and FileManager.
- **D-09:** Trace libp2p protocol handler dispatch and event bus subscription to determine what thread/strand invokes Bitswap callbacks (handle(), onNewConnection()).
- **D-10:** Verify Bitswap→RocksDB boundary. Note if the architectural doc's claim of a direct boundary is inaccurate (Bitswap uses flat files, not RocksDB). If consumer callbacks store blocks into RocksDB, document the callback→RocksDB threading implications.
- **D-11:** Trace AsyncIOManager io_context threading model — how many threads, single vs pool, same context as libp2p?

### Findings Classification & Severity
- **D-12:** Severity scale: CRITICAL (data corruption/crash), HIGH (definite data race), MEDIUM (potential race under specific interleaving), LOW (style/performance/non-functional).
- **D-13:** Category column on each finding: Missing Lock, Lock Order/Deadlock, Async Safety (lock held across async call), Thread Confusion (wrong thread assumption), Atomic Ordering, Documentation Gap.
- **D-14:** CONFIRMED/SUSPECTED confidence flag on each finding. CONFIRMED = clearly provable from source. SUSPECTED = likely but needs runtime verification.
- **D-15:** Master findings table at the end of CONCURRENCY-MAP.md — single table with all columns (severity, category, location, evidence, confidence, recommended fix).

### the agent's Discretion
- Exact table column layout and section ordering within CONCURRENCY-MAP.md — downstream agents have flexibility as long as all decided content is present.
- How to categorize edge-case findings that span multiple categories.
- Level of detail in lock call-chain diagrams (pseudocode vs actual code snippets).
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Planning Docs
- `.planning/ROADMAP.md` — Phase 1 goal, requirements AUDIT-01..06, 5 success criteria
- `.planning/REQUIREMENTS.md` — Detailed per-requirement spec (AUDIT-01 through AUDIT-06)
- `.planning/PROJECT.md` — Project scope, constraints, out-of-scope items, coding standard

### Codebase Maps
- `.planning/codebase/ARCHITECTURE.md` — System architecture, threading model constraints, component dependencies
- `.planning/codebase/CONCERNS.md` — Known concerns including threading-related issues (recursive mutex in processing_service)
- `.planning/codebase/STACK.md` — Full technology stack and build system details

### Bitswap Source (Primary Audit Target)
- `thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp` — Full class definition, 6 mutex domains, member declarations
- `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` — Full implementation (2098 lines), all lock usage, detached threads, async callbacks
- `thirdparty/ipfs-bitswap-cpp/src/bitswap_message.hpp` — BitswapMessage class (protobuf wrapper)
- `thirdparty/ipfs-bitswap-cpp/src/bitswap_message.cpp` — BitswapMessage implementation
- `thirdparty/ipfs-bitswap-cpp/src/merkledag_encoder.hpp` — MerkleDAG encoding (used in Publish paths)

### Consumer Code (Boundary Analysis)
- `SuperGenius/src/account/GeniusNode.cpp` ~line 1307-1317 — Bitswap construction, initialization, cache dir setup
- `SuperGenius/src/account/GeniusNode.cpp` ~line 754-805 — Bitswap mirroring integration
- `SuperGenius/src/processing/processing_subtask_queue_accessor_impl.hpp` — Bitswap for data availability checks
- `SuperGenius/src/processing/processing_service.hpp` — Bitswap propagation to processing nodes
- `SuperGenius/src/processing/processing_node.hpp` — Bitswap cached for accessor creation

### Build System
- `thirdparty/build/CommonTargets.CMake` — ipfs-bitswap-cpp build target and dependency chain
- `thirdparty/AsyncIOManager/build/CommonBuildParameters.cmake` — Bitswap dependency in AsyncIOManager

### Libp2p (Callback Thread Context)
- `thirdparty/libp2p/` — libp2p source for protocol handler dispatch and event bus threading (trace dispatcher to determine what thread calls Bitswap::handle() and onNewConnection())
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **6 existing `mutable std::mutex` members** in Bitswap.hpp — already partitioning data into mutex-guarded domains. The audit starts from this existing structure rather than from scratch.
- **`ContentRequestContext` and `BitswapRequestContext`** — per-request shared_ptr-managed contexts with deadline_timer for timeouts. Pattern is consistent across all request flows.

### Established Patterns
- **Lock scoping:** Lock guards use RAII (`std::lock_guard`), held for the minimum scope, released before async callbacks fire. Strong pattern throughout the codebase.
- **shared_from_this():** All async callbacks capture `shared_from_this()` or `weak_from_this()`. Lifetime safety appears handled.
- **Coding standard mismatch:** Bitswap uses trailing `_` for members (e.g., `mutexRequestCallbacks_`), while the project standard is `m_` prefix. The audit should note but NOT fix this — it's a style concern, not a thread-safety issue.

### Integration Points
- **GeniusNode::initialize()** creates Bitswap with a shared `io_context`, wires it to processing service and FileManager via `setBitswap()`.
- **Processing layer** holds `shared_ptr<Bitswap>` for data availability checks — used to verify IPFS results are locally fetchable.
- **Bitswap::initialize()** registers a protocol handler with libp2p host AND builds disk index — call order matters.
- **Bitswap::start()** is a separate call (after initialize) that subscribes to the event bus for connection events. This two-phase init is worth noting in boundary analysis.

### Pre-Identified Issues (Scout Findings)
- **Detached threads:** `PublishFile()` and `PublishDirectory()` use `std::thread(...).detach()` — these bypass the io_context and access shared state concurrently with Asio handlers.
- **Unsynchronized `cacheDir_`:** Read/written from multiple threads (setCacheDir, getCacheDir, buildDiskIndex, persistBlock, tryLoadFromDisk) with no mutex.
- **Unsynchronized config:** `maxPeerAttempts_` and `peerFailureThreshold_` have setters without lock protection.
- **Lock nesting:** `processReceivedBlocks` (holds `mutexRequestCallbacks_`) → `markProviderSuccess` (acquires `mutexProviders_`). Lock order: callbacks → providers.
- **const_cast:** `GetBlock()` and `HasBlock()` are const methods that call `tryLoadFromDisk()` via `const_cast` — this mutates shared state through a const reference.
- **6 separate mutexes:** No documented lock ordering across domains — potential for future deadlock if two methods acquire two different mutexes in reverse order.
</code_context>

<specifics>
## Specific Ideas

The user noted that compiling bitswap with TSAN or Clang is difficult in the monolithic thirdparty Windows/MSVC build. Manual audit only. If tooling becomes available via WSL in Phase 2, the audit document should be structured to make adding tool-verified findings straightforward (CONFIRMED/SUSPECTED flag already supports this).
</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within Phase 1 scope.
</deferred>

---

*Phase: 1-Audit*
*Context gathered: 2026-07-08*
