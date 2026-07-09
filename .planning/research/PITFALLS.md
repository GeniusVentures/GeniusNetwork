# Pitfalls: C++ Thread-Safety in Async P2P Libraries

**Research Date:** 2026-07-08

## Critical Pitfalls

### P1 — Lock Held Across Async Callback
**What:** Mutex locked, then an async operation is initiated (e.g., `async_write`), and the lock is held until the completion handler runs — but the handler may run on a different thread.
**Warning signs:** `mutex_.lock()` followed by `socket_.async_write_some(...)` with no `unlock()` before the callback.
**Prevention:** Never hold a lock across an async initiation. Release before `async_*` call. Use `strand::post` to serialize instead.
**Phase:** Audit & Fix phase (Phase 2)

### P2 — False Strand Confinement
**What:** Assuming a handler runs on a strand when it was actually posted to the wrong strand, or the strand's `io_context` is run from multiple threads (making strand dispatch honor the strand but `post`/`dispatch` semantics differ).
**Warning signs:** `io_context::run()` called from multiple threads with strand usage.
**Prevention:** Verify each strand's `io_context` has exactly one runner thread, or use explicit locking alongside strands. Document strand threading model.
**Phase:** Audit phase (Phase 1)

### P3 — TOCTOU on Shared Collections
**What:** Check-then-act on shared containers: `if (map.find(key) != end) { map[key] = ...; }` without lock held across both operations.
**Warning signs:** Conditional writes to shared containers, especially after async callbacks.
**Prevention:** Hold lock for entire read-modify-write sequence, or use `try_emplace`/`insert_or_assign` atomically.
**Phase:** Audit & Fix phase (Phase 2)

### P4 — Unsynchronized Smart Pointer Mutation
**What:** `shared_ptr<T>` read in one thread while another thread resets or reassigns it. `shared_ptr`'s refcount is atomic, but the pointed-to object and the pointer variable itself are not.
**Warning signs:** `shared_ptr` members reassigned in one callback, read in another, with no synchronization.
**Prevention:** Use `atomic_load`/`atomic_store` for `shared_ptr` (C++20) or protect with mutex.
**Phase:** Audit phase (Phase 1)

### P5 — libp2p Callback Threading Unknown
**What:** Assuming libp2p callbacks run on a particular thread or strand when the libp2p library's threading model may differ.
**Warning signs:** No explicit dispatch to a known strand/thread in libp2p protocol handlers.
**Prevention:** Add explicit strand dispatch as first line of every Bitswap callback that libp2p invokes.
**Phase:** Consumer integration phase (Phase 3)

### P6 — Data Race from "Harmless" Logging
**What:** Log statements that read shared state (e.g., queue sizes, peer counts) outside locks because "it's just logging."
**Warning signs:** Unlocked reads of members in log/debug statements.
**Prevention:** Either hold lock for the read, make the member atomic, or copy under lock to a local for logging.
**Phase:** Audit phase (Phase 1)

### P7 — Over-Synchronization Degrading Performance
**What:** Adding coarse locks that serialize Bitswap operations, killing throughput. Fixing thread safety by turning concurrent operations sequential.
**Warning signs:** Single mutex guarding all Bitswap state, acquired at top of every callback.
**Prevention:** Prefer strand-based serialization per component. Use fine-grained locks per independent data structure. Benchmark before/after.
**Phase:** Fix phase (Phase 2)

### P8 — Neglecting Consumer API Contract Changes
**What:** Changing Bitswap's internal synchronization (e.g., requiring callers to hold a lock before calling an API) without updating consumers.
**Warning signs:** New `REQUIRES` annotations or lock acquisitions added to public Bitswap headers.
**Prevention:** After every Bitswap synchronization change, grep SuperGenius and AsyncIOManager for affected calls. Update callers to meet new contract.
**Phase:** Consumer update phase (Phase 3)

## Phase Mapping Summary

| Pitfall | Phase 1 (Audit) | Phase 2 (Fix) | Phase 3 (Consumers) |
|---------|:---:|:---:|:---:|
| P1 Lock across async | Identify | Fix | — |
| P2 False strand | Identify | Fix | Verify |
| P3 TOCTOU | Identify | Fix | — |
| P4 shared_ptr race | Identify | Fix | — |
| P5 libp2p threading | Identify | — | Fix |
| P6 Logging race | Identify | Fix | — |
| P7 Over-synchronization | — | Guard against | — |
| P8 Consumer contract | — | Document | Update |

---
*Pitfalls analysis: 2026-07-08*
