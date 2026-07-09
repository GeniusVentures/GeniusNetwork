# Research Summary: IPFS Bitswap Thread-Safety Audit

**Synthesized:** 2026-07-08

## Key Findings

### Stack
Use **ThreadSanitizer (TSAN)** as primary data-race detector, supplemented by **clang-tidy** for static concurrency checks and **Clang thread safety annotations** (`GUARDED_BY`, `REQUIRES`) for compile-time guarantees. Integrate with existing **GTest** framework for stress tests. Helgrind as optional secondary tool for lock-ordering bugs.

### Audit Dimensions (Table Stakes)
1. **Shared mutable state inventory** — catalog every concurrent-access variable
2. **Synchronization primitive audit** — verify mutex/atomic/strand coverage for each
3. **Lock usage correctness** — deadlock potential, lock-across-async, re-entrancy
4. **Atomic operation correctness** — memory ordering, compare-exchange patterns
5. **Callback/strand safety** — verify handler execution context
6. **Third-party boundary crossings** — libp2p, IPFS-Lite, AsyncIOManager, CRDT, RocksDB integration points

### Architecture
Bitswap has four key concurrent components: **WantlistManager**, **BlockRequestScheduler**, **PeerTracker**, and **SessionManager**. Each maintains mutable state accessed from network callbacks, timer expirations, and user-initiated requests. The library integrates with libp2p (protocol handlers), AsyncIOManager (event loop coordination), and SuperGenius CRDT (block storage) — each introducing thread-boundary crossings that need verification.

### Watch Out For
- **Lock held across async callbacks** — the #1 C++ async threading bug
- **False strand confinement** — assuming strand serialization when io_context runs on multiple threads
- **libp2p callback threading unknown** — must explicitly dispatch to known strands
- **Consumer API contract changes** — internal Bitswap sync changes must propagate to SuperGenius/AsyncIOManager callers
- **Over-synchronization** — coarse locks can serialize Bitswap, killing P2P throughput

### Recommended Phase Structure
1. **Phase 1: Audit** — Read-only inventory of all shared state, concurrency boundary tracing, tooling setup (TSAN build)
2. **Phase 2: Fix & Test** — Apply synchronization fixes to Bitswap internals, add TSAN tests
3. **Phase 3: Consumer Integration** — Update SuperGenius and AsyncIOManager for any API contract changes, verify integration points

---
*Summary synthesized: 2026-07-08*
