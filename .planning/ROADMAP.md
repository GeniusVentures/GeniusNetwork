# Roadmap: Genius Network — IPFS Bitswap Thread Safety

**Created:** 2026-07-08
**Granularity:** Coarse (3 phases)
**Project Mode:** Vertical MVP

---

## Phase Overview

| # | Phase | Goal | Requirements | Success Criteria |
|---|-------|------|--------------|------------------|
| 1 | Audit | Complete thread-safety analysis of ipfs-bitswap | AUDIT-01..06 | 5 |
| 2 | Fix & Test | Fix all thread-safety issues and verify | FIX-01..05, TEST-01..03, DOCS-01, DOCS-03 | 5 |
| 3 | Consumer Integration | Update SuperGenius & AsyncIOManager for any API changes | CONS-01..04, DOCS-02 | 4 |

---

### Phase 1: Audit

**Goal:** Complete thread-safety analysis of ipfs-bitswap-cpp — identify every shared mutable state location, synchronization gap, and concurrency boundary.
**Mode:** mvp

**Requirements:** AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04, AUDIT-05, AUDIT-06

**Success Criteria:**
1. Concurrency map document exists covering all shared mutable state in ipfs-bitswap-cpp source files
2. Every shared state location is classified as: mutex-guarded, atomic, strand-confined, or FLAGGED (unprotected)
3. All lock usage reviewed for deadlock, re-entrancy, and lock-across-async violations — documented
4. All atomic operations reviewed for memory ordering and compound-operation correctness
5. All third-party boundary crossings (libp2p→Bitswap, Bitswap→AsyncIOManager, CRDT→Bitswap, Bitswap→RocksDB) traced for thread context assumptions

---

### Phase 2: Fix & Test

**Goal:** Apply synchronization fixes to all identified issues, set up ThreadSanitizer testing, and verify zero data races under concurrent load.
**Mode:** mvp

**Requirements:** FIX-01, FIX-02, FIX-03, FIX-04, FIX-05, TEST-01, TEST-02, TEST-03, DOCS-01, DOCS-03

**Success Criteria:**
1. All FLAGGED shared state from Phase 1 is protected by mutex, atomic, or strand confinement
2. All deadlock risks and lock-across-async violations resolved
3. TSAN build configuration working for ipfs-bitswap-cpp target
4. GTest concurrent stress tests pass with zero TSAN data-race reports
5. Bitswap throughput benchmark shows no significant regression from synchronization additions

---

### Phase 3: Consumer Integration

**Goal:** Update SuperGenius and AsyncIOManager to match any Bitswap API or synchronization contract changes, verify all integration points.
**Mode:** mvp

**Requirements:** CONS-01, CONS-02, CONS-03, CONS-04, DOCS-02

**Success Criteria:**
1. SuperGenius builds and links successfully with updated ipfs-bitswap-cpp
2. AsyncIOManager builds and links successfully with updated ipfs-bitswap-cpp
3. CRDT layer Bitswap integration verified correct with updated threading model
4. AsyncIOManager event-loop integration verified correct — no strand violations at Bitswap boundary

---

*Roadmap created: 2026-07-08*
