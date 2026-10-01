---
phase: 03-local-price-manager
plan: 01
subsystem: coinprices
tags: [price, local-manager, strand, l1-cache]
requires:
  - "SuperGenius/src/coinprices/PriceHttpClient.hpp (the FetchPrices signature mirrored; untouched)"
  - "SuperGenius/src/coinprices/PriceFreshness.hpp (ClassifyFreshness — the only freshness authority)"
provides:
  - "sgns::IPriceSource — pure-virtual tier seam (D-13)"
  - "sgns::PriceHttpClientSource — production adapter over PriceHttpClient (D-04)"
  - "sgns::LocalPriceManager — strand-serialized executor + L1 cache + blocking GetQuotes (D-01..D-06, D-15)"
  - "price_manager_test suite + FakePriceSource fixture (first TEST-02 slice)"
affects:
  - "SuperGenius/src/coinprices/CMakeLists.txt"
  - "SuperGenius/test/src/CMakeLists.txt"
tech-stack:
  added: []
  patterns:
    - "Strand-confined state machine: one io_context + work guard + one dedicated runner thread (HttpStubServer P-1 layout)"
    - "Promise/future blocking bridge onto a strand (HTTPClient::ExecuteBlocking P-2 shape)"
    - "Copy-on-serve L1 caching with ClassifyFreshness band decisions (P-9)"
key-files:
  created:
    - SuperGenius/src/coinprices/IPriceSource.hpp
    - SuperGenius/src/coinprices/PriceHttpClientSource.hpp
    - SuperGenius/src/coinprices/LocalPriceManager.hpp
    - SuperGenius/src/coinprices/LocalPriceManager.cpp
    - SuperGenius/test/src/price_manager/CMakeLists.txt
    - SuperGenius/test/src/price_manager/price_manager_test.cpp
  modified:
    - SuperGenius/src/coinprices/CMakeLists.txt
    - SuperGenius/test/src/CMakeLists.txt
key-decisions:
  - "Fetch chain runs INLINE inside the strand handler (blocking the manager's private thread) — D-03/D-04 accepted design; strand serialization gives D-07 structurally later"
  - "FakePriceSource gained a SetSyntheticSuccess mode so concurrency tests can script success for ANY requested id set (fixed-result scripting returned nothing servable for distinct ids)"
requirements-completed: [LPM-01, TEST-02]
coverage:
  - deliverable: "IPriceSource seam + PriceHttpClientSource adapter"
    verification:
      - kind: command
        ref: "cmake --build ... --target coinprices --config Release (green; headers compile into the library)"
        status: pass
    human_judgment: false
  - deliverable: "LocalPriceManager skeleton with L1 cache and blocking GetQuotes"
    verification:
      - kind: tests
        ref: "price_manager_test#FreshL1HitServesWithZeroTierCalls,L1ExpiryRefetchesFromTier,ExactlySixtySecondsIsStillFresh,PartialL1HitFetchesOnlyMisses,EmptyIdsReturnsEmptyInputWithoutPosting,ConcurrentGetQuotesAcrossThreadsAllResolve,ConstructDestroyLoopDoesNotHang"
        status: pass
    human_judgment: false
  - deliverable: "CMake wiring (library source + suite registration)"
    verification:
      - kind: command
        ref: "ctest -R 'price_manager_test|price_quote_test|price_http_client_test|price_facade_test' — 4/4 suites passed"
        status: pass
    human_judgment: false
duration: 32 min
completed: 2026-10-01T21:55:43.158Z
---

# Phase 3 Plan 01: Local Price Manager Foundation Summary

Strand-serialized LocalPriceManager (ioc + work guard + strand + one runner thread) with the IPriceSource tier seam, the PriceHttpClientSource production adapter, a currency→id keyed L1 cache with band-aware copy-on-serve, the blocking promise/future GetQuotes bridge, drain-then-join teardown, and the 7-case hermetic price_manager_test suite — zero network by construction.

**Duration:** ~32 min | **Tasks:** 5/5 | **Files:** 8 (6 created, 2 modified)

## Accomplishments

- `IPriceSource.hpp` — pure-virtual seam: `FetchPrices(ids, currency="usd") → PriceResult<vector<PriceQuote>>`, FileLoader.hpp house convention, partial-coverage Doxygen contract copied from the facade (D-13).
- `PriceHttpClientSource.hpp` — header-only production adapter closing over the manager's ioc with zero Phase 2 signature changes; `@note` documents that the facade's ioc parameter is vestigial (D-04).
- `LocalPriceManager.hpp/.cpp` — member order load-bearing (ioc_ first, thread_ last): ctor builds ioc→work guard→strand→thread; `GetQuotes` asserts off-strand, fails empty ids synchronously, posts a promise onto the strand and parks on `future.get()` (D-01); `HandleRequestOnStrand` does the D-06 fresh/miss split (ClassifyFreshness only), serves fresh hits with zero network rewriting source to LocalCache on a copy (LPM-01), single-tier inline dispatch, `StoreInL1` keeps fetch-time source/timestamp verbatim (no negative caching); dtor = shutdown post → guard reset → join, never `ioc_->stop()`.
- CMake: `LocalPriceManager.cpp` into coinprices; `price_manager_test` registered via `addtest` with the AsyncIOManager include dir, linking exactly `coinprices` + `Boost::headers` (no sockets).
- Tests: `FakePriceSource` (SetResult/SetResults/SetSyntheticSuccess/CallCount/Calls/WaitForCalls/Reset — mutex+cv observability) and 7 L1 cases: fresh hit zero-tier-calls with timestamp equality, 61s expiry refetch, exactly-60s boundary, partial hit fetches only `{"c"}`, empty input, 8-thread concurrency smoke, 10× construct/destroy loop. All green.

## Commit

- SuperGenius `dev_tokenprice` @ `2258dbeaa` — `feat(coinprices): LocalPriceManager foundation - IPriceSource seam, strand-serialized executor, L1 cache (LPM-01, D-01..D-06/D-13/D-15)`
- Root pointer bump deferred to 03-04 (phase close-out). AsyncIOManager/thirdparty untouched.

## Deviations from Plan

**[Rule 1 - Fixture gap] FakePriceSource.SetSyntheticSuccess added** — Found during: Task 4 | Issue: the plan's concurrency case scripts "tier1 to succeed for any id set", but a fixed-result fake returns quotes only for the fixed ids, so 8 threads requesting distinct ids resolved empty → the case failed on first run | Fix: added a synthetic mode that echoes one success quote per requested id (stamping the call's currency); concurrency case now scripts `SetSyntheticSuccess()` | Files: `SuperGenius/test/src/price_manager/price_manager_test.cpp` | Verification: all 7 cases green | Commit: 2258dbeaa

**[Rule 1 - MSVC compile error] Results vector of non-default-constructible PriceResult** — Found during: Task 4 | Issue: `std::vector<PriceResult<...>> results(8)` failed to compile — the terminate-policy result type has no default constructor | Fix: each thread records its own success bool instead | Files: same test file | Verification: build green, case passes | Commit: 2258dbeaa

**Total deviations:** 2 auto-fixed (fixture gap, compile error). **Impact:** none — both confined to the test file; production code matches the plan exactly.

## Self-Check: PASSED

- Task 1 AC: `IPriceSource.hpp` declares `class IPriceSource` in `sgns` with defaulted virtual dtor + exactly one pure-virtual `FetchPrices` (grep FetchPrices: 2 hits = decl + Doxygen) — PASS. `PriceHttpClientSource` override body is a single forwarding return — PASS. Both header-only, no CMake listing, `PriceHttpClient.hpp` untouched (`git diff HEAD~1 --stat` shows only the 8 plan files) — PASS.
- Task 2 AC: member order ioc_→work_→strand_→tiers/config/clock→cache_→m_logger→thread_ (thread_ last) — PASS. `.cpp` has make_work_guard-style construction, `boost::asio::post( strand_` in GetQuotes, `future.get()` as return, dtor post→reset→join, NO `ioc_->stop()` in code (grep hit is the comment explaining why), NO `std::mutex` — PASS. No raw 60/300 literals compared against timestamps — bands via ClassifyFreshness — PASS. Copy-on-serve + tier-source-preserved serving implemented — PASS. GetQuotes Doxygen documents blocking + never-from-own-thread — PASS.
- Task 3 AC: `add_library` lists `LocalPriceManager.cpp` after `PriceHttpClient.cpp`; suite CMake has `addtest` + include dir + exactly coinprices/Boost::headers (no price_test_support/AsyncIOManager in link); `add_subdirectory(price_manager)` directly after price_facade — PASS.
- Task 4 AC: suite builds, 7/7 green; FakePriceSource derives `sgns::IPriceSource` with all 7 API members, no HttpStubServer include; FreshL1Hit asserts CallCount==0 + LocalCache + exact timestamp equality; PartialL1Hit asserts exact `{"c"}`; zero `sleep_for` in code (grep hits are comments) — PASS.
- Task 5 AC: 4/4 price suites pass in one ctest invocation; commit on dev_tokenprice contains `LocalPriceManager foundation`; AsyncIOManager clean; nothing pushed — PASS.

## Verification Results

| Check | Result |
|---|---|
| `ctest -R price_manager_test` (7 cases) | PASSED |
| `ctest -R "price_manager_test\|price_quote_test\|price_http_client_test\|price_facade_test"` (4 suites) | 100% PASSED |
| Hermeticity grep (sleep_for/HttpStubServer/api.coingecko.com in code) | 0 code hits |
| `std::mutex` / `ioc_->stop()` in LocalPriceManager.cpp code | 0 hits |
| `git -C SuperGenius log -1` | 2258dbeaa on dev_tokenprice |

Ready for 03-02 (coalescing window).
