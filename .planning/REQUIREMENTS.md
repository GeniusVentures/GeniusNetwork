# Requirements: Genius Network — IPFS Bitswap Thread Safety

**Defined:** 2026-07-08
**Core Value:** All concurrent access to IPFS Bitswap state is provably free of data races — verified through static analysis, code audit, and runtime tests.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Audit

- [x] **AUDIT-01**: Inventory all shared mutable state in ipfs-bitswap-cpp (member variables, statics, callback-captured state) — produce a concurrency map document
- [x] **AUDIT-02**: Verify synchronization coverage for every shared state location (mutex, atomic, or strand confinement) — flag any unprotected access
- [x] **AUDIT-03**: Review all mutex usage for deadlock potential, lock-across-async-call violations, and re-entrancy risks
- [x] **AUDIT-04**: Review all atomic operations for correct memory ordering and compound-operation atomicity
- [x] **AUDIT-05**: Verify callback/strand safety — every handler runs on the intended execution context
- [x] **AUDIT-06**: Trace all third-party boundary crossings (libp2p → Bitswap, Bitswap → AsyncIOManager, CRDT → Bitswap, Bitswap → RocksDB) for thread context assumptions

### Fix

- [ ] **FIX-01**: Guard or strand-confine all unprotected shared mutable state identified in AUDIT-02
- [ ] **FIX-02**: Resolve all deadlock risks and lock-across-async violations identified in AUDIT-03
- [ ] **FIX-03**: Correct all atomic ordering and compound-operation issues identified in AUDIT-04
- [ ] **FIX-04**: Add explicit strand dispatch for any callback running on wrong execution context (AUDIT-05)
- [ ] **FIX-05**: Ensure no over-synchronization — benchmark Bitswap throughput before and after fixes to confirm no performance regression

### Consumer Updates

- [ ] **CONS-01**: Update SuperGenius Bitswap integration to match any API/synchronization contract changes from FIX phase
- [ ] **CONS-02**: Update AsyncIOManager Bitswap integration to match any API/synchronization contract changes from FIX phase
- [ ] **CONS-03**: Verify SuperGenius CRDT layer correctness with updated Bitswap threading model
- [ ] **CONS-04**: Verify AsyncIOManager event-loop integration correctness with updated Bitswap

### Testing

- [ ] **TEST-01**: Set up ThreadSanitizer (TSAN) build configuration for ipfs-bitswap-cpp
- [ ] **TEST-02**: Write GTest-based concurrent stress tests exercising all Bitswap operations under multi-threaded access
- [ ] **TEST-03**: Verify TSAN-clean test suite passes with zero data-race reports

### Documentation

- [ ] **DOCS-01**: Document Bitswap thread-safety guarantees and concurrency model (strand/mutex strategy per component)
- [ ] **DOCS-02**: Document any API contract changes for Bitswap consumers (SuperGenius, AsyncIOManager)
- [ ] **DOCS-03**: Add TSAN suppression file with documented rationale for each suppression

## v2 Requirements

Deferred to future release.

### Advanced Verification

- **VERF-01**: Formal lock ordering verification via Helgrind or Clang thread safety annotations
- **VERF-02**: Deterministic concurrency fuzz testing with controlled thread interleavings
- **VERF-03**: CI-integrated TSAN regression suite running on every commit to Bitswap-related code

## Out of Scope

| Feature | Reason |
|---------|--------|
| Full rewrite of ipfs-bitswap | Audit and fix only — preserve existing protocol behavior |
| Thread-safety audit of other thirdparty IPFS libs (ipfs-lite-cpp, ipfs-pubsub) | Scope limited to ipfs-bitswap per idea document |
| Performance optimization not related to thread safety | Separate concern |
| SuperGenius-wide thread-safety audit | Only Bitswap integration points |
| Replacing Boost.Asio with alternative async framework | Would ripple through entire codebase |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| AUDIT-01 | Phase 1 | Complete |
| AUDIT-02 | Phase 1 | Complete |
| AUDIT-03 | Phase 1 | Complete |
| AUDIT-04 | Phase 1 | Complete |
| AUDIT-05 | Phase 1 | Complete |
| AUDIT-06 | Phase 1 | Complete |
| FIX-01 | Phase 2 | Pending |
| FIX-02 | Phase 2 | Pending |
| FIX-03 | Phase 2 | Pending |
| FIX-04 | Phase 2 | Pending |
| FIX-05 | Phase 2 | Pending |
| CONS-01 | Phase 3 | Pending |
| CONS-02 | Phase 3 | Pending |
| CONS-03 | Phase 3 | Pending |
| CONS-04 | Phase 3 | Pending |
| TEST-01 | Phase 2 | Pending |
| TEST-02 | Phase 2 | Pending |
| TEST-03 | Phase 2 | Pending |
| DOCS-01 | Phase 2 | Pending |
| DOCS-02 | Phase 3 | Pending |
| DOCS-03 | Phase 2 | Pending |

**Coverage:**
- v1 requirements: 21 total
- Mapped to phases: 21
- Unmapped: 0

---
*Requirements defined: 2026-07-08*
*Last updated: 2026-07-08 after initial definition*
