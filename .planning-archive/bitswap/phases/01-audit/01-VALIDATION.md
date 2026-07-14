# Phase 1: Audit — Validation Strategy

**Phase:** 1 (Audit)
**Phase Slug:** 01-audit
**Created:** 2026-07-08
**Nyquist Dimension:** 8 — Validation Coverage

---

## Validation Architecture

### Core Principle

Every finding in RESEARCH.md §6 must be independently verifiable from source code alone. Since this is a manual audit phase (no TSAN/Helgrind), validation is source-level: trace every access path, confirm the classification, and ensure no false positives or missed issues.

### Validation Dimensions

| Dimension | Description | Verification Method |
|-----------|------------|-------------------|
| **D1: Completeness** | Every shared mutable member variable is inventoried | Cross-reference bitswap.hpp member list against data domains table (RESEARCH.md §1) |
| **D2: Access Accuracy** | Every access to each member is traced and classified | For each FLAGGED member: verify every read/write site has no lock. For each GUARDED member: verify every read/write site has correct lock. |
| **D3: Lock Ordering** | All multi-mutex acquisitions documented, no deadlock cycles | Trace every method that acquires >1 mutex. Verify no reverse-order path exists. |
| **D4: Async Safety** | No lock held across async callback boundaries | For every `async_wait` / `newStream` / `read` / `write` call: verify enclosing lock is released before call. |
| **D5: Strand Confinement** | Per-request context objects correctly strand-confined | Verify all ContentRequestContext/BitswapRequestContext accesses are on the io_context strand. |
| **D6: Boundary Correctness** | Thread context assumptions at every boundary are documented | Verify each entry in the boundary crossing matrix (RESEARCH.md §3) against actual libp2p dispatch code. |
| **D7: Severity Calibration** | All findings have correct severity assignment | Verify each CRITICAL/HIGH/MEDIUM/LOW against the severity definitions (CONTEXT.md D-12) |

### Deliverable: CONCURRENCY-MAP.md

The primary Phase 1 deliverable synthesizes RESEARCH.md into the final audit document. Validation ensures every claim in CONCURRENCY-MAP.md is traceable to RESEARCH.md evidence.

---

## Success Criteria Mapping

| ROADMAP.md Criterion | Validated By | Gate |
|---------------------|-------------|------|
| 1. Concurrency map exists covering all shared mutable state | D1 — all members inventoried | D1 pass |
| 2. Every state classified (guarded/atomic/strand/FLAGGED) | D2 — all accesses traced and classified | D2 pass |
| 3. Lock usage reviewed for deadlock/re-entrancy/async | D3 + D4 — lock ordering documented, async safety verified | D3 + D4 pass |
| 4. Atomic operations reviewed | D2 subset — atomic-specific access analysis | Research confirmed: no `std::atomic` usage in Bitswap (no atomics needed for audit beyond noting absence) |
| 5. Boundary crossings traced | D6 — all boundaries documented with thread context | D6 pass |

---

## Verification Commands

Since this is a manual audit, verification is source-level grep. For each finding:

```bash
# Verify no other unprotected access to cacheDir_ (C-1)
rg "cacheDir_" thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp

# Verify lock ordering (C-7 callback deadlock check)
rg "lock_guard.*mutexRequestCallbacks_" thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp
rg "HandleResponse" thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp

# Verify detached thread count (C-3)
rg "\.detach\(\)" thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp

# Verify all const_cast sites (C-4)
rg "const_cast" thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp

# Verify cleanupStaleProviders call sites (C-8)
rg "cleanupStaleProviders" thirdparty/ipfs-bitswap-cpp/ -r
rg "cleanupStaleProviders" SuperGenius/src/ -r
rg "cleanupStaleProviders" thirdparty/AsyncIOManager/ -r
```

---

## Verification Evidence Standards

| Finding Confidence | Evidence Required |
|-------------------|------------------|
| **CONFIRMED** | Exact line numbers for every write site + every read site. Counter-example: if claiming "no lock," prove no lock_guard in scope for any call path. |
| **SUSPECTED** | Plausible interleaving scenario documented. Marked for TSAN verification in Phase 2. |

---

*Validation strategy complete: 2026-07-08*
