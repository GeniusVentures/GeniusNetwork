# Features: Thread-Safety Audit Dimensions

**Research Date:** 2026-07-08

## Table Stakes (Must Audit)

### T1 — Shared Mutable State Inventory
Identify every mutable variable, collection, or structure accessible from more than one thread in ipfs-bitswap-cpp. Includes:
- Member variables of core classes (WantlistManager, BlockRequestScheduler, PeerTracker, SessionManager)
- Static/file-scope variables
- Callback-captured state in async operations
- Configuration/options mutated after initialization

### T2 — Synchronization Primitive Audit
For every shared mutable state location, verify:
- Guarded by a mutex or atomic (explicit synchronization)
- Or safely confined to a single Boost.Asio strand (implicit synchronization)
- Or provably immutable after initialization (lock-free read-only)
- Document the synchronization strategy chosen for each

### T3 — Lock Usage Correctness
Check each mutex/lock for:
- Deadlock potential (lock ordering consistency)
- Lock held across async operations (strand violation in Asio)
- Lock held across callbacks into unknown code (re-entrancy risk)
- Lock granularity (too coarse = contention, too fine = deadlock)

### T4 — Atomic Operation Correctness
For each `std::atomic` usage:
- Correct memory ordering (not default `seq_cst` everywhere)
- Correct compare_exchange loop patterns
- Atomicity of compound operations (check-then-act races)

### T5 — Callback/Strand Safety
Verify async callbacks:
- No shared state mutation from non-strand callbacks
- Strand dispatch correctness for multi-strand components
- Lifetimes: objects alive through callback completion (shared_ptr/weak_ptr patterns)

### T6 — Third-Party Boundary Crossings
Thread-safety at boundaries where Bitswap calls into:
- libp2p (its own thread pools)
- IPFS-Lite (block storage callbacks)
- AsyncIOManager (event loop coordination)
- SuperGenius CRDT layer (distributed state syncer)
- RocksDB (block storage I/O threads)

## Differentiators (Advanced)

### D1 — Formal Lock Ordering Verification
Instrument Helgrind or Clang annotations to verify lock-acquisition ordering across all mutex pairs.

### D2 — Deterministic Concurrency Testing
Fuzz test state-machine transitions under controlled interleavings (via dependency injection of scheduler, or Boost.Fiber deterministic scheduling).

### D3 — Performance Regression Guard
Benchmark before/after thread-safety fixes to ensure synchronization overhead doesn't degrade Bitswap throughput.

## Anti-Features (Deliberately NOT)

| Anti-Feature | Reason |
|-------------|--------|
| Global mutex (Big Kernel Lock) | Would serialize all Bitswap operations, destroying async I/O benefits |
| Rewriting Bitswap protocol logic | Scope is thread-safety only — protocol behavior must be preserved |
| Replacing Boost.Asio with another async framework | Would ripple through entire codebase; scope-limited |
| Per-variable mutexes everywhere | Kills cache locality; prefer strand confinement where possible |
| Ignoring false positives | TSAN suppression files must be maintained — suppress real false positives, not real races |
