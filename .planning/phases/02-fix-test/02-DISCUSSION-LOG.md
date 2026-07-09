# Phase 2: Fix & Test - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-08
**Phase:** 2-Fix & Test
**Areas discussed:** Fix sequencing & risk, TSAN build platform, Test organization & scope, Detached thread replacement

---

## Fix Sequencing & Risk

| Option | Description | Selected |
|--------|-------------|----------|
| Severity-first | CRITICAL → HIGH → MEDIUM → LOW | ✓ |
| Dependency-aware | Simpler standalone fixes first, build momentum | |
| Pass-based batching | Thematic passes (mutex/atomic, thread model, defensive) | |

**User's choice:** Severity-first
**Notes:** Fastest path to safety. Carries more risk on complex fixes first.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Simple HIGH first | C-2 + C-4 before C-3 + C-5 within HIGH tier | ✓ |
| Architecture-first | C-3 + C-5 first to define threading model | |
| Head to tail | C-2 → C-3 → C-4 → C-5 in audit order | |

**User's choice:** Simple HIGH first
**Notes:** De-risk complex fixes by building fix patterns on simpler code.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Micro-benchmark harness | GTest-based, ops/sec under concurrent threads | |
| Integration benchmark | Real/peer-based block exchange measurement | |
| Skip for now | Deferred — focus on correctness first | ✓ |

**User's choice:** Skip for now (after asking "How would we even benchmark?")
**Notes:** Benchmarking Bitswap throughput is non-trivial — needs mock peer, mock blocks, and careful metrics. Focus on correctness.

---

## TSAN Build Platform

| Option | Description | Selected |
|--------|-------------|----------|
| WSL2 + Clang TSAN | Local dev, independent Bitswap build | |
| CI-only Linux TSAN | GitHub Actions, keeps local MSVC unchanged | |
| Hybrid: WSL dev + CI gate | Both local and CI coverage | |

**User's choice:** Deferred (free-text: "We need to defer this and just handle potential deadlocks or crashes. Trying to compile this entire project, let alone WSL is far too difficult to do immediately.")
**Notes:** TSAN, TEST-01, TEST-03, and DOCS-03 are all deferred. Validation is through code review and manual verification.

---

## Test Organization & Scope

| Option | Description | Selected |
|--------|-------------|----------|
| In thirdparty/ipfs-bitswap-cpp | Self-contained, needs build system wiring | |
| In SuperGenius/test/src/bitswap | Reuses existing GTest infrastructure | ✓ |

**User's choice:** In SuperGenius/test/src/bitswap
**Notes:** Leverage existing test macros, CMake addtest(), and Bitswap link dependency.

---

| Option | Description | Selected |
|--------|-------------|----------|
| All finding-aligned scenarios | ~7-8 fixtures, one per finding | ✓ |
| Top 3 most dangerous | Only CRITICAL+HIGH | |
| Manual verification only | Skip concurrent tests | |

**User's choice:** All finding-aligned scenarios
**Notes:** Comprehensive coverage of every identified race window.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Multi-threaded stress | N threads, M iterations, check invariants | ✓ |
| Targeted race-window | Artificial timing to widen specific windows | |
| Both: stress + targeted | Broad + precise tests | |

**User's choice:** Multi-threaded stress
**Notes:** Simple, broad approach. Tests correctness under concurrent load without flaky timing dependencies.

---

## Detached Thread Replacement

| Option | Description | Selected |
|--------|-------------|----------|
| io_context::post | Serialize on existing Bitswap io_context | ✓ |
| Strand dispatch | Dedicated strand for publish work | |
| Refactor to sync callback | Remove threading, make callers block | |

**User's choice:** io_context::post
**Notes:** Simplest fix. Changes what thread runs work, not the API surface.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Keep callback, note the change | Preserve callback, document thread context change | ✓ |
| Remove callback, add future | std::future for explicit wait | |
| Remove callback, fire-and-forget | No completion signal | |

**User's choice:** Keep callback, note the change
**Notes:** Callback fires on io_context instead of detached thread. Phase 3 consumers need awareness but no API surface change.

---

## the agent's Discretion

- Mock/fixture strategy for Bitswap tests
- Exact lock documentation format (code comments vs header annotations)
- cacheDir_ fix approach (mutex vs immutable-post-init)
- ContentRequestContext fix approach (mutex vs strand confinement)

## Deferred Ideas

- FIX-05: Throughput benchmarks
- TEST-01: TSAN build configuration
- TEST-03: TSAN-clean verification
- DOCS-03: TSAN suppression file
- WSL2 build environment setup
