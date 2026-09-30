---
phase: 02-c-price-http-client-quote-surface
plan: 01
subsystem: coinprices
tags: [price, quote-types, freshness]
requires:
  - coinprices.hpp legacy module (unchanged)
provides:
  - sgns::PriceSource enum (LocalCache, CoinGecko, GnusPriceService, OnChain)
  - sgns::PriceQuote struct (asset, currency, price, timestamp, source, stale, FetchedAtEpochSeconds())
  - sgns::FreshnessBand enum (Fresh, StaleButUsable, Unavailable)
  - sgns::ClassifyFreshness(fetchedAt, now)
  - sgns::kFreshMaxAge / sgns::kStaleMaxAge shared constants
affects: []
tech-stack:
  added: []
  patterns:
    - header-only value types in coinprices module
key-files:
  created:
    - SuperGenius/src/coinprices/PriceQuote.hpp
    - SuperGenius/src/coinprices/PriceFreshness.hpp
    - SuperGenius/test/src/price_quote/price_quote_test.cpp
    - SuperGenius/test/src/price_quote/CMakeLists.txt
  modified:
    - SuperGenius/test/src/CMakeLists.txt
key-decisions:
  - ClassifyFreshness compares age at the clock's native duration precision (no duration_cast truncation) so ms-exact D-16 boundary cases (59999ms/60000ms/60001ms, 300000ms/300001ms) classify correctly
requirements-completed: [QUOTE-01, QUOTE-02, FRESH-02]
coverage:
  - deliverable: "PriceQuote + PriceSource types (QUOTE-01/02, D-14)"
    verification:
      - kind: test
        ref: "test/src/price_quote/price_quote_test.cpp#PriceQuoteTest"
        status: pass
    human_judgment: false
  - deliverable: "Freshness-band classifier with D-16 closed boundaries (FRESH-02)"
    verification:
      - kind: test
        ref: "test/src/price_quote/price_quote_test.cpp#PriceFreshnessTest.BoundaryTable"
        status: pass
    human_judgment: false
  - deliverable: "Registered hermetic ctest suite price_quote_test"
    verification:
      - kind: command
        ref: "ctest -R price_quote_test (1/1 Passed)"
        status: pass
    human_judgment: false
duration: 18 min
completed: 2026-09-30
---

# Phase 2 Plan 01: Quote Types + Freshness Classifier Summary

Provider-independent quote surface: `PriceQuote`/`PriceSource` header-only types with D-14 fetch-time timestamp semantics and epoch-seconds interop accessor, plus the D-16 freshness-band classifier (closed-on-fresh boundaries at 60s/300s) with shared `inline constexpr` band constants, proven by a hermetic registered GTest suite.

## Accomplishments

- `PriceQuote.hpp` (QUOTE-01/02): `PriceSource` enum with exactly `LocalCache`, `CoinGecko`, `GnusPriceService`, `OnChain` (reserved, SRC-01 deferred); `PriceQuote` struct with D-14 fetch-time `std::chrono::system_clock::time_point timestamp` and `FetchedAtEpochSeconds()` interop accessor
- `PriceFreshness.hpp` (FRESH-02): `FreshnessBand` enum, `ClassifyFreshness(fetchedAt, now)`, `inline constexpr kFreshMaxAge{60}` / `kStaleMaxAge{300}` shared by code and tests
- `price_quote_test` suite (8 tests, 13-case D-16 boundary table driven by the shared constants — zero sockets, zero `system_clock::now()` in assertion paths), registered via `addtest()` with ctest
- `test/src/CMakeLists.txt` gains `add_subdirectory(price_quote)` next to `price_retrieval`

## Deviations from Plan

**[Rule 3 - Bug in planned implementation sketch] ClassifyFreshness duration truncation** — Found during: Task 2 boundary table execution | Issue: comparing `duration_cast<seconds>`-truncated age made 60001ms classify Fresh and 300001ms classify StaleButUsable, violating the plan's own ms-exact boundary table (59999/60000/60001, 300000/300001) | Fix: compare the native-duration `now - fetchedAt` directly against the constants (chrono handles mixed-precision comparison exactly) | Files: `src/coinprices/PriceFreshness.hpp` | Verification: full 13-case boundary table green | Commit: 3a64b62c1

**Total deviations:** 1 auto-fixed. **Impact:** none — the fix tightens boundary correctness; constants and API shape unchanged.

## Verification Results

1. Build: `cmake --build ... --target coinprices price_quote_test --config Release` — PASS (coinprices.lib rebuilt clean, header-only addition)
2. Test: `ctest -R price_quote_test --output-on-failure` — PASS (100%: 1/1 test, 8/8 gtest cases)
3. Source assertions: all four `PriceSource` enumerators + `FetchedAtEpochSeconds` present; `kFreshMaxAge`/`kStaleMaxAge` present; both band comparisons use `<=` — PASS
4. No-regression: `price_retrieval_test` target still configures/builds (not run — live network by design) — PASS

## Issues Encountered

None

## Next Phase Readiness

Ready for 02-02 (parallel Wave-1 transport work — no dependency) and Phase 3's manager consumption of these types.

## Self-Check: PASSED
