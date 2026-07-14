---
phase: 1
name: Audit
wave: 1
depends_on: []
requirements: [AUDIT-01]
files_modified:
  - ".planning/phases/01-audit/SKELETON.md"
  - ".planning/phases/01-audit/CONCURRENCY-MAP.md"
autonomous: true
---

# Plan 01: Walking Skeleton — Audit `mutexBlockStore_` Domain

**Objective:** Produce a minimal end-to-end audit slice proving the methodology works — audit the `mutexBlockStore_` domain completely and write the first data domain entry into CONCURRENCY-MAP.md. This is the Walking Skeleton: one complete mutex domain traced end-to-end from header declaration through every access site to classified findings.

**Covered Requirements:** AUDIT-01 (first domain inventoried), AUDIT-02 (first domain classified)

---

<threat_model>
### Concurrency Threats in Audit Scope

| Threat | Affected State | Impact | Severity |
|--------|---------------|--------|----------|
| Data race on `cacheDir_` (std::string) | `cacheDir_` — no mutex | String corruption → crash or incorrect file paths | CRITICAL |
| Data race on config members | `maxPeerAttempts_`, `peerFailureThreshold_` — no setter lock | Torn read on 32-bit platforms, inconsistent behavior | HIGH |
| Detached thread concurrent access | `blockStore_`, `publishedContent_`, `cacheDir_` via PublishFile/PublishDirectory | Multiple threads modifying shared containers concurrently | HIGH |
| const_cast mutation of shared state | `blockStore_` via `GetBlock()` → `tryLoadFromDisk()` | Concurrent mutation through const interface | HIGH |
| ContentRequestContext strand violation | All ContentRequestContext fields accessed from libp2p thread AND io_context | Corrupted file assembly, lost blocks, wrong content | HIGH |
| Callback invoked under lock | `HandleResponse()` called while `mutexRequestCallbacks_` held | Deadlock if callback re-enters Bitswap | MEDIUM |
| BitswapRequestContext timer race | `HandleResponseTimeout()` (io_context) races with `HandleResponse()` (libp2p thread) | Double callback invocation, use-after-move | MEDIUM |
</threat_model>

---

## Tasks

### Task 1: Write SKELETON.md — Project Walking Skeleton

<action>
Create SKELETON.md at `.planning/phases/01-audit/SKELETON.md`. Document the audit project skeleton:
- Project: IPFS Bitswap Thread Safety Audit
- Phase 1 deliverable: CONCURRENCY-MAP.md
- First vertical slice: mutexBlockStore_ domain
- Skeleton proves: full source tracing methodology works for one domain → scales to all 6 mutex domains
- Include the skeleton audit entry for mutexBlockStore_ domain (to be written in Task 2)
</action>

<read_first>
- .planning/phases/01-audit/01-RESEARCH.md (data domains table §1, findings C-1 through C-10 in §6)
- .planning/phases/01-audit/01-CONTEXT.md (D-01 through D-04 for deliverable format decisions)
- .planning/PROJECT.md (project scope and constraints)
- .planning/codebase/ARCHITECTURE.md (system architecture context)
</read_first>

<acceptance_criteria>
- SKELETON.md exists at `.planning/phases/01-audit/SKELETON.md`
- SKELETON.md contains a section "## Walking Skeleton" describing the first vertical slice
- SKELETON.md documents the project scaffolding (purpose, deliverable, methodology)
- SKELETON.md links to the skeleton audit entry in CONCURRENCY-MAP.md (or includes it inline)
- SKELETON.md contains a "## Verification" section explaining how this one domain proves the methodology
</acceptance_criteria>

---

### Task 2: Audit `mutexBlockStore_` Domain — Complete Data Domain Entry

<action>
Write the first fully-verified data domain entry into `.planning/phases/01-audit/CONCURRENCY-MAP.md`. This covers the `mutexBlockStore_` domain (members: `blockStore_`, `publishedContent_`).

For every access site, document:
- File and line number
- Thread context (main init, libp2p thread, io_context, detached thread, consumer thread)
- Lock acquisition pattern (lock_guard present? held across async boundary?)
- Classification: MUTEX-GUARDED or FLAGGED

Access sites to trace for `blockStore_`:
1. `Bitswap.hpp:334` — declaration under `mutex mutexBlockStore_`
2. `bitswap.cpp:1296-1307` — `storeBlock()`: emplace (lock_guard OK)
3. `bitswap.cpp:1100-1103` — `encodeChunkedFile()`: find (lock_guard OK)
4. `bitswap.cpp:1111-1127` — `encodeChunkedFile()`: find, contentSize update (lock_guard OK)
5. `bitswap.cpp:1176-1204` — `encodeAndStoreDirectory()`: find, contentSize read (lock_guard OK)
6. `bitswap.cpp:1210-1216` — `encodeAndStoreDirectory()`: find, contentSize write (lock_guard OK)
7. `bitswap.cpp:1312-1318` — `handleWantlistRequest()`: find (lock_guard OK, released before tryLoadFromDisk)
8. `bitswap.cpp:1323-1329` — `handleWantlistRequest()`: find after tryLoadFromDisk (lock_guard OK)
9. `bitswap.cpp:1376-1382` — `PublishFile()` detached thread: find, emplace (lock_guard OK but DETACHED THREAD)
10. `bitswap.cpp:1414-1423` — `PublishDirectory()` detached thread: iteration, emplace (lock_guard OK but DETACHED THREAD)
11. `bitswap.cpp:1446-1459` — `PublishData()`: find, emplace (lock_guard OK)
12. `bitswap.cpp:1469-1473` — `HasBlock()`: count (lock_guard OK)
13. `bitswap.cpp:1484-1490` — `GetBlock()`: find (lock_guard OK)
14. `bitswap.cpp:1494-1499` — `GetBlock()`: find after const_cast→tryLoadFromDisk (lock_guard OK, but const_cast)
15. `bitswap.cpp:1506-1520` — `UnpublishContent()`: find, erase iteration (lock_guard OK)
16. `bitswap.cpp:1525-1532` — `ListPublishedContent()`: iteration, reserve (lock_guard OK)
17. `bitswap.cpp:2084-2093` — `tryLoadFromDisk()`: emplace (lock_guard OK)

For `publishedContent_`:
1. `bitswap.hpp:335` — declaration
2. `bitswap.cpp:1382` — PublishFile detached thread: emplace
3. `bitswap.cpp:1423` — PublishDirectory detached thread: emplace
4. `bitswap.cpp:1459` — PublishData: emplace
5. `bitswap.cpp:1507-1520` — UnpublishContent: find, erase
6. `bitswap.cpp:1525-1532` — ListPublishedContent: iteration

Use the table format from CONTEXT.md D-01 (data domains table with columns: Member, Mutex Guard, Access Sites, Classification, Severity, Notes).

Include a severity for each finding per CONTEXT.md D-12 (CRITICAL/HIGH/MEDIUM/LOW).
Include a confidence flag per CONTEXT.md D-14 (CONFIRMED/SUSPECTED).
Include a category per CONTEXT.md D-13 (Missing Lock, Lock Order/Deadlock, Async Safety, Thread Confusion, Atomic Ordering, Documentation Gap).

Key findings to surface for this domain:
- **FINDING: Detached thread access (HIGH/CONFIRMED/Thread Confusion)** — PublishFile and PublishDirectory run on detached std::thread, accessing blockStore_ and publishedContent_. Lock is held but detached threads can't be joined/coordinated. Multiple publishes create parallel detached threads.
- **FINDING: const_cast mutation (HIGH/CONFIRMED/Async Safety)** — GetBlock() const method calls const_cast→tryLoadFromDisk which modifies blockStore_. Violates const-correctness = thread-safety contract.
- **FINDING: tryLoadFromDisk gap in handleWantlistRequest (LOW/CONFIRMED/Documentation Gap)** — Lock released between first check and tryLoadFromDisk, another thread may load the block. Redundant disk I/O but no data corruption.
</action>

<read_first>
- thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp (lines 333-335: mutexBlockStore_, blockStore_, publishedContent_ declarations)
- thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp (read full file — all access sites listed above)
- .planning/phases/01-audit/01-RESEARCH.md (data domains table row #13-14, findings C-1, C-3, C-4)
- .planning/phases/01-audit/01-CONTEXT.md (D-04 for severity inline, D-12 through D-15 for classification rules)
</read_first>

<acceptance_criteria>
- CONCURRENCY-MAP.md exists at `.planning/phases/01-audit/CONCURRENCY-MAP.md`
- CONCURRENCY-MAP.md contains a Data Domains table with at least the mutexBlockStore_ domain entry
- The `mutexBlockStore_` domain entry lists ALL 17 access sites for `blockStore_` with file:line references
- The `mutexBlockStore_` domain entry lists ALL 6 access sites for `publishedContent_` with file:line references
- Each access site has: thread context, lock acquisition pattern, and classification
- At least 3 findings documented with severity (per D-12), category (per D-13), and confidence (per D-14)
- Detached thread finding documented with evidence (exact line numbers for .detach() calls)
- const_cast finding documented with evidence (exact line 1492)
- The Walking Skeleton methodology is proven — this one domain entry demonstrates the pattern for all 6 domains
</acceptance_criteria>

---

<verification>
### Goal-Backward Verification

**Phase Goal:** Complete thread-safety analysis of ipfs-bitswap-cpp
**Plan Contribution:** First complete mutex domain verified — proves methodology for scale-out

**must_haves:**
- SKELETON.md written with project scaffolding and Walking Skeleton documentation
- CONCURRENCY-MAP.md created with mutexBlockStore_ domain fully traced
- Every access site numbered with file:line evidence
- Thread context documented per site
- At least 3 findings with severity/category/confidence

**Wave:** 1 (no dependencies, no parallel constraints)
</verification>
