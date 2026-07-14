# SKELETON.md — IPFS Bitswap Thread Safety Audit

**Project:** Genius Network — IPFS Bitswap Thread Safety
**Phase 1:** Audit
**Created:** 2026-07-08

---

## Project Scaffolding

| Element | Value |
|---------|-------|
| **Audit Target** | `thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp` + `bitswap.cpp` (2098 lines) |
| **Primary Deliverable** | `CONCURRENCY-MAP.md` — complete concurrency map of all shared mutable state |
| **Methodology** | Manual source-level audit: trace every member variable through every access site, classify synchronization coverage, document findings |
| **Scope** | 22 member variables, 6 mutex domains, 2 helper struct contexts, 4 boundary categories |
| **Classification Taxonomy** | MUTEX-GUARDED, FLAGGED, STRAND-CONFINED, SHARED-CONST, EXTERNAL |

### Phase 1 Success Criteria

1. Concurrency map document exists covering all shared mutable state in Bitswap source files
2. Every shared state location classified as: MUTEX-GUARDED, atomic, STRAND-CONFINED, or FLAGGED (unprotected)
3. All lock usage reviewed for deadlock, re-entrancy, and lock-across-async violations — documented
4. All atomic operations reviewed for memory ordering and compound-operation correctness
5. All third-party boundary crossings (libp2p→Bitswap, Bitswap→AsyncIOManager, CRDT→Bitswap, Bitswap→RocksDB) traced for thread context assumptions

---

## Walking Skeleton

### First Vertical Slice: `mutexBlockStore_` Domain

The Walking Skeleton proves the audit methodology works end-to-end by completing one full mutex domain — `mutexBlockStore_` and its guarded members — before scaling to all 6 domains.

**Domain:** `mutexBlockStore_` guards `blockStore_` (map<CID, StoredBlock>) and `publishedContent_` (map<CID, PublishedContent>)

**Why this domain?**
- Largest access-surface area (23 total access sites across both members) — stress-tests the tracing methodology
- Contains 3 HIGH-severity findings (detached thread access, const_cast mutation, tryLoadFromDisk gap) — proves the classification framework
- Exercises all 4 thread contexts: main init, libp2p thread, io_context, detached thread — proves the thread context inventory approach
- Simple lock pattern (single RAII lock_guard, never nested with other mutexes) — clean baseline for lock analysis

**Skeleton audit entry:** See `CONCURRENCY-MAP.md` § Data Domains Table — `mutexBlockStore_` row (first complete entry in the audit).

### Methodology Walk-Through

For each member variable in a mutex domain:
1. **Locate** the declaration in `bitswap.hpp` — note the mutex it groups under
2. **Find** every access site in `bitswap.cpp` — use grep + manual trace on member name
3. **Document** the thread context at each site: main init, libp2p I/O thread, io_context, or detached thread
4. **Verify** lock acquisition at each site: is lock_guard present? Is it released before async calls?
5. **Classify** each access site as MUTEX-GUARDED or FLAGGED
6. **Assign** severity, category, and confidence per CONTEXT.md D-12..D-14

This pattern scales to all 6 mutex domains: mutexBlockStore_, mutexRequestCallbacks_, mutexContentRequests_, mutexActiveStreams_, mutexDiskIndex_, mutexProviders_.

### Data Domains Inventory (All 6)

| # | Mutex Domain | Guarded Members | Access Sites (est.) | Key Findings |
|---|-------------|-----------------|---------------------|--------------|
| 1 | `mutexBlockStore_` | `blockStore_`, `publishedContent_` | 23 | C-3 (detached thread), C-4 (const_cast) |
| 2 | `mutexRequestCallbacks_` | `requestContexts_` | 4 | C-7 (callback under lock) |
| 3 | `mutexContentRequests_` | `contentRequests_` | 5 | Strand violation (ContentRequestContext) |
| 4 | `mutexActiveStreams_` | `activeStreams_` | 4 | Lock released before async → SAFE |
| 5 | `mutexDiskIndex_` | `diskIndex_` | 8 | C-1 (buildDiskIndex re-lock gap) |
| 6 | `mutexProviders_` | `providers_` (+ partial: `maxPeerAttempts_`, `peerFailureThreshold_`) | 12 | C-2 (config race), C-8 (dead code) |

### Unprotected State (FLAGGED)

| Member | Type | Severity | Finding |
|--------|------|----------|---------|
| `cacheDir_` | `std::string` | CRITICAL | C-1 — 8 read/write sites, 4 thread contexts, no lock |
| `maxPeerAttempts_` | `size_t` | HIGH | C-2 — setter unprotected, partial reader lock |
| `peerFailureThreshold_` | `int` | HIGH | C-2 — setter unprotected, partial reader lock |
| `started_` | `bool` | LOW | Written once at init, BOOST_ASSERT guarded |

---

## Verification

The Walking Skeleton validates the methodology by proving that one complete mutex domain can be traced end-to-end:

| Check | Method | Evidence |
|-------|--------|----------|
| Every access site found | grep `blockStore_` across bitswap.cpp | 17 sites confirmed (Plan 01 Task 2) |
| Thread context identified | Manual code trace of caller chain for each site | 4 thread types confirmed |
| Lock pattern verified | Read lock_guard scope for each site | 17/17 sites have lock_guard |
| Findings classified | Applied D-12..D-14 taxonomy | 3 findings: HIGH, HIGH, LOW |
| Methodology documented | SKELETON.md (this file) | Pattern extractable for remaining 5 domains |

**Result:** The Walking Skeleton proves the methodology. The same grep→trace→classify→document pattern applies unchanged to the remaining 5 mutex domains. Scale-out risk is low — each domain uses identical RAII lock_guard patterns and similar access-site density.

---

*Skeleton defined: 2026-07-08*
