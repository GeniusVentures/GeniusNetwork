# Genius Network — IPFS Bitswap Thread Safety

## What This Is

A focused effort to audit and harden the `thirdparty/ipfs-bitswap` C++ library for thread safety, then propagate any required API changes to SuperGenius and AsyncIOManager — the two consumers of ipfs-bitswap in the Genius Network decentralized AI/ML blockchain node. Bitswap is the data exchange protocol that moves blocks between IPFS peers; thread-safety defects here can cause data races, crashes, or silent corruption in a multi-threaded asynchronous node.

## Core Value

All concurrent access to IPFS Bitswap state is provably free of data races — verified through static analysis, code audit, and runtime tests — ensuring the CRDT/storage layer never corrupts or loses blocks under concurrent load.

## Requirements

### Validated

- &#x2713; Block-lattice cryptocurrency node (SuperGenius) with AI/ML processing — existing
- &#x2713; CRDT-based distributed state synchronization over IPFS — existing
- &#x2713; IPFS data block exchange via Bitswap protocol (ipfs-bitswap-cpp) — existing
- &#x2713; Asynchronous I/O via Boost.Asio event loops managed by AsyncIOManager — existing
- &#x2713; libp2p peer-to-peer networking layer — existing
- &#x2713; RocksDB persistent local storage — existing
- &#x2713; Protocol Buffer serialization for all wire formats — existing

### Active

- [ ] Thread-safety audit of `thirdparty/ipfs-bitswap` — identify all shared mutable state and synchronization gaps
- [ ] Fix or guard all non-thread-safe code paths in ipfs-bitswap
- [ ] Update SuperGenius Bitswap integration to match any API/threading contract changes
- [ ] Update AsyncIOManager Bitswap integration to match any API/threading contract changes
- [ ] Add thread-safety regression tests (data-race detection via TSAN or equivalent)
- [ ] Document thread-safety guarantees and concurrency model for Bitswap consumers

### Out of Scope

- Full rewrite of ipfs-bitswap — audit and fix only, not redesign the Bitswap protocol
- Other thirdparty IPFS libraries (ipfs-lite-cpp, ipfs-pubsub) — scope is limited to ipfs-bitswap
- Performance optimization unrelated to thread safety
- SuperGenius-wide thread-safety audit beyond Bitswap integration points

## Context

- **Codebase:** Genius Network monorepo with Git submodules. SuperGenius is C++17, ipfs-bitswap is a thirdparty C++ library built as part of the `thirdparty/` orchestration layer.
- **Threading model:** SuperGenius uses Boost.Asio for async I/O with multiple threads. AsyncIOManager coordinates event loops. Shared mutable state is common and requires explicit synchronization (mutexes, atomics).
- **Bitswap role:** Bitswap is the IPFS block exchange protocol — nodes request blocks from peers and respond to block requests. It maintains internal state (wantlists, peer tracking, block storage) that may be accessed concurrently from different Asio strands/threads.
- **Known concerns:** The architecture document flags that "Mutex/atomic operations required for shared state" in the threading model. Bitswap interacts with libp2p (which has its own threading), the CRDT layer (which syncs state asynchronously), and the storage layer (RocksDB) — all concurrently.
- **Existing codebase map:** `.planning/codebase/ARCHITECTURE.md` and `.planning/codebase/STACK.md` provide full architecture and dependency documentation.

## Constraints

- **Tech stack:** C++17, CMake, Boost.Asio, libp2p, existing thirdparty build system
- **Compatibility:** Changes to ipfs-bitswap must not break SuperGenius or AsyncIOManager builds on any supported platform (Windows x64, Linux, macOS, iOS, Android)
- **Build system:** ipfs-bitswap is built via `thirdparty/build/{Platform}/CMakeLists.txt`; any new files or dependencies must be registered there
- **Testing:** GTest testing framework; TSAN/Helgrind recommended for data-race detection
- **Coding standard:** Corelinux-derived C++ style per `Coding Standards.md` — Ullman braces, PascalCase types, `m_` member prefix

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Audit-only scope for ipfs-bitswap (not full rewrite) | Minimize risk to existing CRDT/storage pipeline | — Pending |
| Use ThreadSanitizer (TSAN) for data-race detection | Best available tool for C++ data-race detection, supported by Clang/GCC | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-07-08 after initialization*
