---
phase: 1
name: Audit
wave: 1
depends_on: ["01-PLAN"]
requirements: [AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04, AUDIT-05, AUDIT-06]
files_modified:
  - ".planning/phases/01-audit/CONCURRENCY-MAP.md"
  - ".planning/phases/01-audit/01-VERIFICATION.md"
autonomous: true
---

# Plan 02: Complete CONCURRENCY-MAP.md — Full Thread-Safety Audit

**Objective:** Produce the complete CONCURRENCY-MAP.md document covering all 6 mutex domains, unprotected shared state, boundary crossing matrix, thread entry-point inventory, strand confinement analysis, and the master findings summary table. Plus write VERIFICATION.md confirming all AUDIT requirements are met.

**Covered Requirements:** AUDIT-01 (full inventory), AUDIT-02 (all state classified), AUDIT-03 (all lock usage reviewed), AUDIT-04 (atomic operations — document absence), AUDIT-05 (callback/strand safety), AUDIT-06 (all boundary crossings traced)

---

<threat_model>
All threats from Plan 01 apply. Additional threats specific to the remaining domains:

| Threat | Affected State | Impact | Severity |
|--------|---------------|--------|----------|
| Lock ordering deadlock potential | 6 mutexes with only 1 documented ordering | Future code additions could introduce deadlock | MEDIUM |
| ContentRequestContext data race | All ContentRequestContext fields — accessed from libp2p thread AND io_context | Corrupted file assembly, lost chunks | HIGH |
| BitswapRequestContext timer race | `callbacks_`, `responseTimer_` — io_context timer vs libp2p HandleResponse | Double callback, use-after-move | MEDIUM |
| Callback re-entrancy deadlock | `HandleResponse()` invoked while `mutexRequestCallbacks_` held | Non-recursive mutex deadlock if callback re-enters Bitswap | MEDIUM |
| libp2p thread identity assumption | `handle()` and all its continuations run on libp2p threads — not documented | Future async changes may violate implicit thread contract | LOW |
</threat_model>

---

## Tasks

### Task 1: Audit `mutexRequestCallbacks_` + `mutexContentRequests_` Domains

<action>
Write the data domain entries for mutexRequestCallbacks_ (guards: requestContexts_) and mutexContentRequests_ (guards: contentRequests_) into CONCURRENCY-MAP.md.

For mutexRequestCallbacks_ domain — trace all access sites:
1. bitswap.hpp:324-325 — declaration
2. bitswap.cpp:271-285 — processReceivedBlocks: lock_guard, find, HandleResponse invocation
3. bitswap.cpp:324-336 — messageSent: lock_guard, find, emplace
4. Verify: lock held across callback invocation at line 279 (HandleResponse called while guard active)
5. Verify: lock released before async read at line 339

For mutexContentRequests_ domain — trace all access sites:
1. bitswap.hpp:327-328 — declaration
2. bitswap.cpp:540-542 — setupContentRequest: lock_guard, emplace
3. bitswap.cpp:553-561 — timeout handler: lock_guard, find, erase, callback invocation
4. bitswap.cpp:573-574 — failContentRequest: lock_guard, erase
5. bitswap.cpp:890-891 — checkContentRequestComplete: lock_guard, erase

Key findings:
- FINDING: Callback under lock (MEDIUM/CONFIRMED/Async Safety) — processReceivedBlocks line 271-279 invokes HandleResponse() while mutexRequestCallbacks_ is held. If any BlockCallback re-enters Bitswap and acquires mutexRequestCallbacks_, non-recursive mutex → deadlock.
- FINDING: Timeout callback access (LOW/CONFIRMED/Async Safety) — Content timeout handler at line 553 fires on io_context, accesses contentRequests_ with lock_guard. Safe but different thread context noted.
- Lock ordering: mutexRequestCallbacks_ → mutexProviders_ (via processReceivedBlocks→markProviderSuccess). Document this ordering.
</action>

<read_first>
- thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp (lines 324-328)
- thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (lines 255-349 for processReceivedBlocks and messageSent, lines 530-575 for setupContentRequest, failContentRequest, timeout)
- .planning/phases/01-audit/01-RESEARCH.md (§1 rows 6-9, §2.4 lock-across-async analysis, §2.1 lock ordering)
</read_first>

<acceptance_criteria>
- CONCURRENCY-MAP.md Data Domains table has entries for mutexRequestCallbacks_ and mutexContentRequests_
- mutexRequestCallbacks_ entry lists all 4 access sites with file:line
- mutexContentRequests_ entry lists all 5 access sites with file:line
- Lock ordering documented: mutexRequestCallbacks_ → mutexProviders_
- Callback-under-lock finding documented with line 279 evidence
- Timeout handler thread context documented (io_context vs libp2p thread)
</acceptance_criteria>

---

### Task 2: Audit `mutexActiveStreams_` + `mutexDiskIndex_` Domains

<action>
Write data domain entries for mutexActiveStreams_ (guards: activeStreams_) and mutexDiskIndex_ (guards: diskIndex_).

For mutexActiveStreams_ — trace all access sites:
1. bitswap.hpp:330-331 — declaration
2. bitswap.cpp:419-431 — RequestBlockWithRetry: lock_guard, find, isClosed check, erase. Lock released before newStream
3. bitswap.cpp:465-467 — retry callback: lock_guard, erase (on stream creation failure)
4. bitswap.cpp:501-504 — newStream success callback: lock_guard, emplace → released before writeBitswapMessageToStream

For mutexDiskIndex_ — trace all access sites:
1. bitswap.hpp:339-340 — declaration
2. bitswap.cpp:1476-1478 — HasBlock: lock_guard, count (check)
3. bitswap.cpp:1937-1939 — buildDiskIndex: lock_guard, clear
4. bitswap.cpp:1948-1950 — buildDiskIndex loop: lock_guard, insert (per-file!)
5. bitswap.cpp:1978-1980 — persistBlock: lock_guard, insert
6. bitswap.cpp:2038-2040 — unpersistBlock: lock_guard, erase
7. bitswap.cpp:2058-2063 — tryLoadFromDisk: lock_guard, count (check)
8. bitswap.cpp:2070-2071 — tryLoadFromDisk: lock_guard, erase (file disappeared)

Key findings:
- FINDING: buildDiskIndex lock/re-lock pattern (LOW/CONFIRMED/Async Safety) — line 1937-1939 acquires lock to clear, releases, then re-acquires per file at lines 1948-1950. Between clear and first insert, diskIndex_ is empty — other threads see empty index. If tryLoadFromDisk runs between buildDiskIndex lines, it may miss a file that was just cleared.
- Active streams reuse pattern: lock held for minimal scope (line 419-431), released before async newStream. Safe.
</action>

<read_first>
- thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp (lines 330-331, 339-340)
- thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (lines 402-508 for active streams, lines 1922-2101 for disk persistence)
- .planning/phases/01-audit/01-RESEARCH.md (§1 rows 10-11, 16-17)
</read_first>

<acceptance_criteria>
- CONCURRENCY-MAP.md Data Domains table has entries for mutexActiveStreams_ and mutexDiskIndex_
- mutexActiveStreams_ entry lists all 4 access sites with file:line
- mutexDiskIndex_ entry lists all 8 access sites with file:line
- buildDiskIndex lock/re-lock pattern documented as finding
- Active streams lock scope confirmed released before async operations
</acceptance_criteria>

---

### Task 3: Audit `mutexProviders_` Domain + Config Members + Unprotected State

<action>
Write data domain entries for mutexProviders_ (guards: providers_, partial guards: maxPeerAttempts_, peerFailureThreshold_) and the unprotected state members (cacheDir_, maxPeerAttempts_, peerFailureThreshold_).

For mutexProviders_ — trace all access sites:
1. bitswap.hpp:342-345 — declaration
2. bitswap.cpp:1550-1569 — AddProvider: lock_guard, find (via findProvider), emplace_back
3. bitswap.cpp:1574-1594 — RemoveProvider: lock_guard, find, remove_if, erase
4. bitswap.cpp:1599-1607 — GetProviders: lock_guard, find, return copy
5. bitswap.cpp:1611-1613 — ClearProviders: lock_guard, erase
6. bitswap.cpp:1637-1643 — GetTotalProviderCount: lock_guard, iteration + sum
7. bitswap.cpp:1646-1663 — GetProviderDebugInfo: lock_guard, iteration
8. bitswap.cpp:1667-1725 — selectBestProvider: lock_guard, find, sort, select
9. bitswap.cpp:1729-1752 — markProviderFailure: lock_guard, find (via findProvider)
10. bitswap.cpp:1754-1770 — markProviderSuccess: lock_guard, find (via findProvider)
11. bitswap.cpp:1772-1805 — cleanupStaleProviders: lock_guard, remove_if, erase (DEAD CODE — never called)
12. findProvider at bitswap.cpp:1535-1546 — internal helper, no lock itself, must be called under lock

Key findings for providers:
- findProvider returns raw pointer valid only under lock. All callers hold lock. SAFE but fragile.
- selectBestProvider reads peerFailureThreshold_ under lock (line 1680). Safe for this read path.
- cleanupStaleProviders is dead code — never called (confirmed by grep). CR #3038 finding.
- Provider methods well-protected internally. No reverse lock ordering with other domains.

For unprotected state — document as FLAGGED:

**cacheDir_ (CRITICAL/CONFIRMED/Missing Lock):**
- Write: setCacheDir() line 1908-1914 — no lock
- Read via getCacheDir(): line 1917-1920 — no lock
- Read via buildDiskIndex(): line 1924 — no lock
- Read via persistBlock(): line 1965 — no lock
- Read via tryLoadFromDisk(): line 2047 — no lock
- Read via cidToFilePath(): line 1960 — no lock
- Read via unpersistBlock(): line 2011 — no lock
- Threads: main init, libp2p, io_context, DETACHED THREAD

**maxPeerAttempts_ (HIGH/CONFIRMED/Missing Lock):**
- Write: SetMaxPeerAttempts() line 1616-1619 — no lock
- Read: selectBestProvider() line 1713 — under mutexProviders_
- Read: requestBlockWithProviders() line 1809 — NO lock
- Read: requestBlockWithProvidersFromRoot() line 1854 — NO lock

**peerFailureThreshold_ (HIGH/CONFIRMED/Missing Lock):**
- Write: SetPeerFailureThreshold() line 1621-1624 — no lock
- Read: selectBestProvider() line 1680 — under mutexProviders_
- Read: markProviderFailure() line 1737 — under mutexProviders_

**started_ (LOW/CONFIRMED/Documentation Gap):**
- Write: start() line 220-221 — BOOST_ASSERT guard
- Read: nowhere externally. Internal use only.
</action>

<read_first>
- thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp (lines 338, 342-345)
- thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (lines 1535-1805 for providers, lines 1908-1920 for cacheDir, lines 1616-1624 for config setters)
- .planning/phases/01-audit/01-RESEARCH.md (§1 rows 15, 18-21, §6 findings C-1, C-2, C-8)
</read_first>

<acceptance_criteria>
- CONCURRENCY-MAP.md Data Domains table has entry for mutexProviders_ with all 12 access sites
- CONCURRENCY-MAP.md has FLAGGED entries for cacheDir_, maxPeerAttempts_, peerFailureThreshold_
- cacheDir_ entry shows all 8 access sites with file:line and thread context for each
- maxPeerAttempts_ and peerFailureThreshold_ show all read/write sites with and without lock
- cleanupStaleProviders documented as dead code
- findProvider() raw pointer pattern documented with safety analysis
- Each FLAGGED entry has severity, category, confidence per CONTEXT.md D-12..D-14
</acceptance_criteria>

---

### Task 4: Write Boundary Crossing Matrix

<action>
Add the Boundary Crossing Matrix section to CONCURRENCY-MAP.md. Document all thread context boundaries:

1. **libp2p → Bitswap:**
   - Protocol handler dispatch → Bitswap::handle(): libp2p dispatch thread
   - Event bus OnNewConnection → Bitswap::onNewConnection(): event bus dispatch thread
   - Async read/write continuations in handle(): libp2p I/O thread
   - Continuous server read loop (lines 164-201): persists on libp2p thread indefinitely

2. **Consumer (SuperGenius) → Bitswap:**
   - GeniusNode initialization (line 1308-1317): main init thread
   - GeniusNode mirroring callback (line 754-805): processing service callback thread
   - ProcessingSubTaskQueueAccessor: processing worker thread
   - ProcessingService: processing node thread
   - FileManager: various threads

3. **Bitswap → Consumer (Callbacks):**
   - BlockCallback fires from: libp2p thread (HandleResponse), io_context (timeout)
   - ContentCallback fires from: libp2p thread (checkContentRequestComplete), io_context (timeout)
   - PublishCallback fires from: DETACHED std::thread

4. **Bitswap → Filesystem:**
   - persistBlock(): various threads, uses mutexDiskIndex_ only for index
   - tryLoadFromDisk(): libp2p thread, io_context (via const_cast)
   - buildDiskIndex(): main init thread only

Use matrix format: Source Thread → Entry Point → Bitswap Locks Acquired → Destination Thread for callbacks.

Verify each boundary against actual code. For libp2p thread assumptions, note that the libp2p dispatch threading model must be verified (currently assumed based on callback patterns, not confirmed from libp2p source).
</action>

<read_first>
- .planning/phases/01-audit/01-RESEARCH.md (§3 Boundary Crossing Matrix, §4 Thread Entry-Point Inventory)
- thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (lines 104-116 for initialize handler registration, lines 218-240 for start/OnNewConnection subscription, lines 123-216 for handle() and server read loop)
- SuperGenius/src/account/GeniusNode.cpp (lines 1306-1317 for construction, lines 754-805 for mirroring integration)
- SuperGenius/src/processing/processing_service.hpp (line 123 for Bitswap member)
- SuperGenius/src/processing/processing_node.hpp (line 116 for Bitswap member)
- SuperGenius/src/processing/processing_subtask_queue_accessor_impl.hpp (line 111 for Bitswap member)
</read_first>

<acceptance_criteria>
- CONCURRENCY-MAP.md contains a "## Boundary Crossing Matrix" section
- Matrix has entries for all 4 boundary categories (libp2p→Bitswap, Consumer→Bitswap, Bitswap→Callbacks, Bitswap→Filesystem)
- Each matrix row has: source thread, entry point, locks acquired, callback thread context
- libp2p dispatch thread assumptions explicitly noted as needing verification from libp2p source
- Detached thread for PublishCallback documented as HIGH severity finding
- Consumer call sites documented with file:line for GeniusNode and processing layer
- Bitswap→RocksDB entry: "No direct boundary — Bitswap uses flat files. Consumer callbacks may store to RocksDB."
</acceptance_criteria>

---

### Task 5: Write Thread Entry-Point Inventory + Strand Confinement Analysis

<action>
Add the Thread Entry-Point Inventory and Strand Confinement Analysis sections to CONCURRENCY-MAP.md.

**Thread Entry-Point Inventory:** Table of every function that can be called from outside Bitswap. Columns: Function, Visibility, Called From, Thread Context(s), Locks Acquired, Notes. Use the inventory from RESEARCH.md §4 as source data. Flag entries where thread context is ambiguous or undocumented.

**Strand Confinement Analysis:**
For ContentRequestContext — document all field access paths and their thread contexts:
- processUnixFSBlock (libp2p thread via callback): modifies pendingCIDs, completedCIDs, collectedFiles, filesInProgress, cidToPath, chunkToCidIndex, requestQueue
- setupContentRequest timeout handler (io_context): sets timedOut, reads callback
- processRequestQueue delay timer (io_context): reads requestQueue, sets processingQueue
- checkContentRequestComplete (libp2p thread): reads pendingCIDs, filesInProgress, acquires mutexContentRequests_

Document the race window: libp2p callback modifies ContentRequestContext fields while io_context timeout handler may fire simultaneously. The `processingQueue` flag only serializes processRequestQueue() calls — does not protect other fields.

For BitswapRequestContext — document the timer race:
- HandleResponse (libp2p thread via processReceivedBlocks): iterates callbacks_, modifies responseTimer_
- HandleResponseTimeout (io_context via deadline_timer): calls HandleResponse → same fields
- Both may execute concurrently if block arrives during timer expiry window.

Key finding: ContentRequestContext needs explicit strand confinement. Options: (a) post all callbacks to io_context strand, (b) add mutex to ContentRequestContext, (c) document current assumptions and accept risk.
</action>

<read_first>
- .planning/phases/01-audit/01-RESEARCH.md (§4 Thread Entry-Point Inventory, §5 Strand Confinement Analysis)
- thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp (lines 104-118 for BitswapRequestContext, lines 120-167 for ContentRequestContext)
- thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (lines 65-90 for BitswapRequestContext methods, lines 92-95 for ContentRequestContext constructor, lines 577-1008 for ContentRequestContext access paths)
</read_first>

<acceptance_criteria>
- CONCURRENCY-MAP.md contains a "## Thread Entry-Point Inventory" section
- Table lists ALL public API methods and ALL callback entry points with thread context
- Functions where thread context is assumed (not confirmed) are explicitly marked
- CONCURRENCY-MAP.md contains a "## Strand Confinement Analysis" section
- ContentRequestContext strand violation documented with evidence (libp2p thread vs io_context)
- Specific fields at risk enumerated: pendingCIDs, completedCIDs, collectedFiles, filesInProgress, cidToPath, chunkToCidIndex
- BitswapRequestContext timer race documented with evidence (HandleResponse vs HandleResponseTimeout)
- Both strand violations classified with severity and confidence
</acceptance_criteria>

---

### Task 6: Write Master Findings Summary Table + Atomic Operations Review

<action>
Add the Master Findings Summary Table and Atomic Operations Review sections to CONCURRENCY-MAP.md.

**Master Findings Table:** Single consolidated table per CONTEXT.md D-15. All 10 findings from RESEARCH.md §6, organized by severity (CRITICAL first):

| # | Severity | Category | Location | Description | Evidence | Confidence |
|---|----------|----------|----------|-------------|----------|-----------|
| C-1 | CRITICAL | Missing Lock | cacheDir_ | No synchronization on std::string | See Task 3 | CONFIRMED |
| C-2 | HIGH | Missing Lock | maxPeerAttempts_, peerFailureThreshold_ | Setters no lock, partial reader lock | See Task 3 | CONFIRMED |
| C-3 | HIGH | Thread Confusion | PublishFile/PublishDirectory | Detached threads access shared state | See Plan 01 Task 2 | CONFIRMED |
| C-4 | HIGH | Async Safety | GetBlock() | const_cast mutates blockStore_ | See Plan 01 Task 2 | CONFIRMED |
| C-5 | HIGH | Missing Lock | ContentRequestContext | No synchronization, accessed from 2 threads | See Task 5 | CONFIRMED |
| C-6 | MEDIUM | Async Safety | BitswapRequestContext | Timer (io_context) races with HandleResponse (libp2p) | See Task 5 | SUSPECTED |
| C-7 | MEDIUM | Async Safety | processReceivedBlocks | Callback invoked under mutexRequestCallbacks_ | See Task 1 | CONFIRMED |
| C-8 | MEDIUM | Documentation Gap | cleanupStaleProviders | Dead code, never called | See Task 3 | CONFIRMED |
| C-9 | MEDIUM | Thread Confusion | handle() server loop | Persistent libp2p thread callback chain | See Task 4 | CONFIRMED |
| C-10 | LOW | Documentation Gap | All 6 mutexes | No lock ordering documentation | Global | CONFIRMED |

**Atomic Operations Review:** Section confirming no `std::atomic` usage in Bitswap. Document:
- Grep of entire codebase for `std::atomic`, `atomic<`, `::atomic` returned zero results in bitswap source
- maxPeerAttempts_ and peerFailureThreshold_ use plain `size_t`/`int` — should be `std::atomic<size_t>` / `std::atomic<int>` per finding C-2
- No other candidates for atomic conversion found
- If Phase 2 adds atomics, memory ordering should default to `std::memory_order_seq_cst` unless explicitly relaxed with justification
</action>

<read_first>
- .planning/phases/01-audit/01-RESEARCH.md (§6 Master Findings Table, §8 Config Members Access Map)
- .planning/phases/01-audit/01-CONTEXT.md (D-12 through D-15 for severity/category/confidence/table format)
- thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp (scan for any atomic usage)
- thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (scan for any atomic usage)
</read_first>

<acceptance_criteria>
- CONCURRENCY-MAP.md contains a "## Master Findings Summary" section
- Single table with all 10 findings organized by severity
- Each finding row has: number, severity, category, location, description, evidence reference, confidence
- CONCURRENCY-MAP.md contains an "## Atomic Operations Review" section
- Atomic review confirms zero std::atomic usage in Bitswap source
- Atomic review recommends atomic conversion for maxPeerAttempts_ and peerFailureThreshold_
- Atomic review documents default memory ordering recommendation
</acceptance_criteria>

---

### Task 7: Write VERIFICATION.md — Audit Completeness Verification

<action>
Write `.planning/phases/01-audit/01-VERIFICATION.md`. Verify every AUDIT requirement against CONCURRENCY-MAP.md content.

Run grep-based verification:
```bash
# AUDIT-01: Confirm all shared mutable state is inventoried
rg "cacheDir_|maxPeerAttempts_|peerFailureThreshold_|blockStore_|publishedContent_|requestContexts_|contentRequests_|activeStreams_|diskIndex_|providers_" thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp

# AUDIT-02: Confirm all FLAGGED entries are documented in CONCURRENCY-MAP.md
rg "FLAGGED" .planning/phases/01-audit/CONCURRENCY-MAP.md

# AUDIT-03: Confirm lock ordering documented
rg "lock.*order|Lock Order|deadlock" .planning/phases/01-audit/CONCURRENCY-MAP.md

# AUDIT-04: Confirm atomic review present
rg "atomic|Atomic" .planning/phases/01-audit/CONCURRENCY-MAP.md

# AUDIT-05: Confirm strand confinement analysis
rg "strand|Strand|ContentRequestContext.*race|timer.*race" .planning/phases/01-audit/CONCURRENCY-MAP.md

# AUDIT-06: Confirm boundary matrix covers all boundaries
rg "boundary|Boundary|libp2p.*Bitswap|SuperGenius.*Bitswap|Filesystem|RocksDB" .planning/phases/01-audit/CONCURRENCY-MAP.md

# Verify no unresolved SUSPECTED findings without TSAN plan reference
rg "SUSPECTED" .planning/phases/01-audit/CONCURRENCY-MAP.md
```

For each requirement, verify:
- AUDIT-01: Every member from bitswap.hpp §1 appears in CONCURRENCY-MAP.md Data Domains table
- AUDIT-02: Every entry has a classification (MUTEX-GUARDED, STRAND-CONFINED, or FLAGGED)
- AUDIT-03: Lock ordering documented, deadlock analysis complete, re-entrancy checked, async safety verified
- AUDIT-04: Atomic operations reviewed (absence documented, recommendation for Phase 2 made)
- AUDIT-05: Strand confinement analyzed for ContentRequestContext and BitswapRequestContext, findings documented
- AUDIT-06: Boundary crossing matrix covers libp2p→Bitswap, Consumer→Bitswap, Bitswap→Callbacks, Bitswap→Filesystem

Document each requirement as PASSED or FAILED with evidence.
</action>

<read_first>
- .planning/phases/01-audit/CONCURRENCY-MAP.md (will be complete after Tasks 1-6)
- .planning/REQUIREMENTS.md (AUDIT-01 through AUDIT-06 specs)
- .planning/ROADMAP.md (Phase 1 success criteria)
- .planning/phases/01-audit/01-VALIDATION.md (validation dimensions D1-D7)
</read_first>

<acceptance_criteria>
- 01-VERIFICATION.md exists at `.planning/phases/01-audit/01-VERIFICATION.md`
- Every AUDIT requirement (01-06) has a PASSED/FAILED verdict
- PASSED verdicts cite specific sections of CONCURRENCY-MAP.md as evidence
- Any FAILED verdict includes specific gap description
- Success criteria checklist from ROADMAP.md mapped to verification evidence
- grep command outputs documented as verification evidence where applicable
- All 7 validation dimensions from VALIDATION.md addressed
</acceptance_criteria>

---

<verification>
### Goal-Backward Verification

**Phase Goal:** Complete thread-safety analysis of ipfs-bitswap-cpp
**Plan Contribution:** Full CONCURRENCY-MAP.md with all 6 domains, boundary matrix, strand analysis, findings, and verification

**must_haves:**
- Data domains table covering all 6 mutex domains + all unprotected state
- Every access site traced with file:line evidence
- Boundary crossing matrix covering all 4 boundary categories + RocksDB clarification
- Thread entry-point inventory for all public API and callback entry points
- Strand confinement analysis for ContentRequestContext and BitswapRequestContext
- Master findings table with all 10 findings (6 CONFIRMED, 1 SUSPECTED)
- Atomic operations review documenting absence + Phase 2 recommendation
- VERIFICATION.md confirming all 6 AUDIT requirements met

**Wave:** 1 (depends on Plan 01 for CONCURRENCY-MAP.md scaffolding)
</verification>
