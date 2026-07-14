# Architecture: IPFS Bitswap Concurrency Boundaries

**Research Date:** 2026-07-08

## Bitswap Internal Components

### WantlistManager
- **Role:** Tracks which CIDs each peer wants. Sends wantlist updates.
- **State:** Map of peer → set of CIDs (mutable, concurrent access from network events)
- **Concurrency:** Accessed by incoming network messages (wantlist updates from peers) and outgoing requests (local wantlist changes)

### BlockRequestScheduler
- **Role:** Decides which peers to request blocks from, manages in-flight requests.
- **State:** Peer prioritization, active request tracking, timeout management
- **Concurrency:** Timer expirations + incoming block responses + new wantlist entries

### PeerTracker / PeerManager
- **Role:** Tracks peer responsiveness, latency, availability.
- **State:** Per-peer statistics (mutable, updated on every interaction)
- **Concurrency:** Updated from network I/O callbacks and timer callbacks simultaneously

### SessionManager
- **Role:** Manages Bitswap sessions (scoped block exchanges).
- **State:** Active sessions, per-session wantlists and block caches
- **Concurrency:** Session creation/destruction + block request/response within sessions

## Consumer Integration Points

### AsyncIOManager → Bitswap
```
AsyncIOManager::io_context (Asio event loop, potentially multiple threads)
    ↓ dispatches to
ipfs-bitswap-cpp callbacks (block received, wantlist updated, peer event)
    ↓ may call back into
AsyncIOManager (to schedule more I/O)
```

**Risk:** Callback re-entrancy. Bitswap callbacks invoked from Asio handlers may call back into AsyncIOManager, creating nested dispatch chains.

### SuperGenius CRDT → Bitswap
```
CRDT Datastore (distributed state sync)
    ↓ requests blocks via
ipfs-bitswap-cpp (request blocks by CID, announce wantlists)
    ↓ delivers blocks to
RocksDB (via IPFS-Lite blockstore callback)
```

**Risk:** Block delivery callback fires from Bitswap's internal thread context; CRDT layer may assume single-threaded access.

### libp2p → Bitswap
```
libp2p Host (peer connections, protocol handlers)
    ↓ routes Bitswap protocol messages
ipfs-bitswap-cpp protocol handler
    ↓ processes wantlist updates, block requests, block responses
```

**Risk:** libp2p may deliver messages concurrently across multiple connection threads. Bitswap handler must be re-entrant.

## Concurrency Model (Inferred)

From the codebase map and Boost.Asio usage:
1. **Strand-based:** Main Bitswap operations likely run on one or more Asio strands
2. **Callback-driven:** All I/O is async; state changes happen in completion handlers
3. **Multiple event sources:** Network messages, timers, user-initiated requests all produce concurrent events

## Suggested Build Order for Audit

1. **Read-only phase:** Inventory all shared state without modifying code — produce a concurrency map
2. **Consumer boundary analysis:** Trace how SuperGenius and AsyncIOManager call into Bitswap — identify thread crossing points
3. **Internal analysis:** For each Bitswap component, verify strand confinement or mutex protection
4. **Fix phase:** Apply minimal synchronization fixes
5. **Consumer update phase:** If Bitswap API contract changes, update SuperGenius and AsyncIOManager
6. **Verification phase:** TSAN + stress tests

---
*Architecture analysis: 2026-07-08*
