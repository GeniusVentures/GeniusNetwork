---
phase: 04-geniusnode-integration-hermetic-tests
plan: 01
subsystem: pricing
tags: [env-config, price-manager, seam-cutover, code-deletion, boost-asio]

requires:
  - phase: 03-local-price-manager
    provides: LocalPriceManager (L1 cache, coalescing, four-tier fallback), PriceHttpClientSource adapter
provides:
  - Env-configurable price endpoints (SGNS_COINGECKO_URL / SGNS_PRICE_FALLBACK_URL) with CoinGecko/token.gnus.ai defaults
  - GeniusNode::GetCoinprice served by the lazily constructed LocalPriceManager (blocking, partial-map semantics)
  - sgns::testutil::ScopedEnvVar CRT-family RAII env guard (shared by hermetic suites)
  - Full deletion of CoinGeckoPriceRetriever and all GeniusNode price-cache state
affects: [04-02 account suite conversion, 04-03 price_retrieval rewrite, processing_nodes suites, Phase 5 CI]

tech-stack:
  added: []
  patterns:
    - "Lazy service construction: GetOrCreatePriceManager() reads env at construction, never cached in a static (D-03)"
    - "Env-var-only endpoint config via header-only free functions with exported default constants (O1)"

key-files:
  created:
    - SuperGenius/src/coinprices/PriceEndpoints.hpp
    - SuperGenius/test/testutil/scoped_env.hpp
  modified:
    - SuperGenius/src/account/GeniusNode.hpp
    - SuperGenius/src/account/GeniusNode.cpp
    - SuperGenius/src/coinprices/CMakeLists.txt
    - SuperGenius/src/coinprices/PriceFetchError.hpp
    - SuperGenius/test/testutil/genius_node_test_access.hpp
    - SuperGenius/test/src/processing_nodes/child_tokens_test.cpp
    - SuperGenius/test/src/processing_nodes/processing_nodes_test.cpp
    - SuperGenius/test/src/processing_nodes/CMakeLists.txt
    - .planning/workstreams/tokenprice/REQUIREMENTS.md
  deleted:
    - SuperGenius/src/coinprices/coinprices.hpp
    - SuperGenius/src/coinprices/coinprices.cpp

key-decisions:
  - "O1 resolved: env read as free functions in PriceEndpoints.hpp with exported default constants"
  - "Teardown: explicit priceManager_.reset() immediately after ShutdownForDestruction() in ~GeniusNode (RESEARCH Pitfall 9)"
  - "Failure mapping: GetQuotes failure -> Error::NO_PRICE (in-category; GetGNUSPrice re-maps anyway)"

patterns-established:
  - "Hermetic price redirect pattern: stub Start -> ScopedEnvVar both tiers -> GeniusNode::New (ordering is load-bearing)"

requirements-completed: [LPM-09, LPM-10]

coverage:
  - id: D1
    description: "PriceEndpoints.hpp env-config with CoinGecko defaults, no static caching"
    requirement: LPM-09
    verification:
      - kind: unit
        ref: "source gate: literals SGNS_COINGECKO_URL/SGNS_PRICE_FALLBACK_URL/https://api.coingecko.com/https://token.gnus.ai present; zero 'static' in read path"
        status: pass
      - kind: command
        ref: "cmake --build SuperGenius\\build\\Windows\\Release --config Release --target coinprices (exit 0)"
        status: pass
    human_judgment: false
  - id: D2
    description: "ScopedEnvVar CRT-family RAII env guard"
    requirement: LPM-09
    verification:
      - kind: unit
        ref: "source gate: _putenv_s/_putenv under _WIN32, setenv/unsetenv otherwise, no SetEnvironmentVariable"
        status: pass
      - kind: command
        ref: "genius_node build exit 0"
        status: pass
    human_judgment: false
  - id: D3
    description: "GetCoinprice cutover to lazy LocalPriceManager with preserved surface"
    requirement: LPM-10
    verification:
      - kind: command
        ref: "cmake --build ... --target genius_node exit 0; --target account_management_test exit 0"
        status: pass
      - kind: unit
        ref: "source gates: priceManager_.reset() after ShutdownForDestruction(); GetOrCreatePriceManager()->GetQuotes present; tokenIds.empty() short-circuit; zero diff hunks in GetProcessCost/GetGNUSPrice bodies"
        status: pass
    human_judgment: false
  - id: D4
    description: "Full D-06/D-09 deletion: retriever, cache state, historical forwarders, CMake entry"
    requirement: LPM-10
    verification:
      - kind: command
        ref: "grep gates: 0 matches for CoinGeckoPriceRetriever / cache members / historical decls under SuperGenius/src; coinprices.hpp/.cpp absent; CMake keeps target coinprices"
        status: pass
      - kind: command
        ref: "ctest -R 'price_quote_test|price_http_client_test|price_facade_test|price_manager_test' — 4/4 passed"
        status: pass
    human_judgment: false
  - id: D5
    description: "REQUIREMENTS.md Out-of-Scope row records the D-09 supersession"
    verification:
      - kind: command
        ref: "task verify: 'Kept compiling'=0, 'D-09'>=1 — PASS"
        status: pass
    human_judgment: false

duration: 75 min
completed: 2026-10-01
status: complete
---

# Phase 4 Plan 01: Configurable Price Endpoints + GeniusNode Seam Cutover Summary

**Env-var price endpoints (SGNS_COINGECKO_URL/SGNS_PRICE_FALLBACK_URL) + GetCoinprice rebuilt on the lazy LocalPriceManager, with CoinGeckoPriceRetriever and all node price-cache state deleted (D-09).**

## Performance

- **Duration:** ~75 min
- **Tasks:** 3/3
- **Files:** 11 modified/created, 2 deleted (SuperGenius) + 1 planning doc (root)

## Accomplishments
- `PriceEndpoints.hpp`: production env read as `inline` free functions with exported default constants; deliberately no function-local static (fresh read per manager construction)
- `scoped_env.hpp`: CRT-family RAII guard (`_putenv_s`/`setenv`) with exact prior-state restore — the shared utility 04-02/04-03 consume
- `GeniusNode::GetCoinprice` rewritten: empty-ids → success-empty-map short-circuit (Pitfall 3), `GetOrCreatePriceManager()->GetQuotes`, quote→map loop with absent-stay-absent semantics (D-07), `Error::NO_PRICE` on failure; blocking-call Doxygen note (D-08)
- Teardown: explicit `priceManager_.reset()` immediately after `ShutdownForDestruction()` in `~GeniusNode`
- Deleted (D-06/D-09): `coinprices.hpp/.cpp` (~530 lines), `GetCoinPriceByDate`/`GetCoinPricesByDateRange`, `PriceInfo`/`m_tokenPriceCache`/`m_cacheValidityDuration`/`m_lastApiCall`/`MIN_API_CALL_INTERVAL`, ctor initializer, both `"CoinPrices"` logger config lines, `coinprices.cpp` from CMake (target name kept for GeniusSDK artifacts)
- `PriceFetchError.hpp` doc comment reworded to past-tense D-09 rationale — comment lines only, no code/enum change (git diff verified)
- `GetProcessCost`/`GetGNUSPrice` byte-identical (zero diff hunks in either body — LPM-10 proof)

## Task Commits

1. **Task 1: PriceEndpoints.hpp + scoped_env.hpp** — `8de045e52` (feat)
2. **Task 2: Seam cutover + full D-06/D-09 deletion** — `79a2f6e1c` (feat)
3. **Task 3: REQUIREMENTS.md D-09 supersession** — root `c0426cb` (docs)

## Files Created/Modified
- `SuperGenius/src/coinprices/PriceEndpoints.hpp` — env read + default constants (LPM-09)
- `SuperGenius/test/testutil/scoped_env.hpp` — `sgns::testutil::ScopedEnvVar`
- `SuperGenius/src/account/GeniusNode.hpp/.cpp` — fwd-decl, lazy member + helper, rewritten seam, deletions, teardown
- `SuperGenius/src/coinprices/CMakeLists.txt` — dropped `coinprices.cpp`
- `SuperGenius/src/coinprices/PriceFetchError.hpp` — comment-only touch-up
- `SuperGenius/test/testutil/genius_node_test_access.hpp` — `CacheGnusPrice` removed (deviation)
- `SuperGenius/test/src/processing_nodes/{child_tokens,processing_nodes}_test.cpp` + CMake — deviation conversion
- `.planning/workstreams/tokenprice/REQUIREMENTS.md` — Out-of-Scope supersession

## Decisions Made
- O1 → free functions in a new header with exported constants (tests assert defaults without duplicating strings)
- Teardown slot → explicit reset right after `ShutdownForDestruction()`, before the pubsub keepalive block (Pitfall 9; `ReleaseRuntimeMembersAfterIoStopped` left untouched as dead code)
- Failure mapping → `Error::NO_PRICE` (in-category; `GetGNUSPrice` re-validates and re-maps anyway)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Missing dependency] Two additional test suites wrote the deleted price cache via friend accessors**
- **Found during:** Task 2 (account_management_test build failed)
- **Issue:** The plan's D-09 consumer inventory listed only `GeniusNode.cpp` + `price_retrieval_test.cpp`, but `processing_nodes_test.cpp` (3× `CacheGnusPrice` calls) and `child_tokens_test.cpp` (`SetGNUSPrice` local accessor + 1 call + `CacheGnusPrice` in CreateNode) injected prices directly into `m_tokenPriceCache` through `GeniusNodeTestAccess` — they broke compile when the cache members were deleted
- **Fix:** Converted both suites to the same hermetic pattern this phase establishes: `HttpStubServer` scripting `/api/v3/simple/price` with `{"genius-ai":{"usd":1.0}}` (identical 1.0 USD value the accessors injected), `ScopedEnvVar` guards for both tiers set before any node construction, restored after node teardown; removed `CacheGnusPrice` from `genius_node_test_access.hpp` and `SetGNUSPrice` from the local accessor; linked `price_test_support`
- **Files modified:** `child_tokens_test.cpp`, `processing_nodes_test.cpp`, `processing_nodes/CMakeLists.txt`, `genius_node_test_access.hpp`
- **Verification:** both targets build exit 0 (release tree); `child_tokens_test`/`processing_nodes_test` runtime runs deferred to their normal CI/shard runs — they are heavyweight multi-node suites (500s timeout class) and were not part of this plan's verify set
- **Committed in:** `79a2f6e1c` (part of Task 2 commit)

**2. [Rule 1 - Bug] `std::make_shared<PriceHttpClientSource>` failed with braced-default arguments**
- **Found during:** Task 2 (first genius_node build)
- **Issue:** `/*retryConfig=*/{}` and the commented-argument style confused overload resolution under MSVC (C2672 no matching overloaded function)
- **Fix:** Named `RetryConfig{}` and dropped the inline comments; explicit remaining defaulted args kept
- **Files modified:** `SuperGenius/src/account/GeniusNode.cpp`
- **Verification:** genius_node build exit 0
- **Committed in:** `79a2f6e1c`

**Total deviations:** 2 auto-fixed (1 missing-dependency, 1 compile fix). **Impact:** low — the accessor conversion extends this phase's hermetic pattern to two more suites (strictly in the spirit of TEST-04/D-12); the compile fix is mechanical.

## Self-Check: PASSED

- Task 1 acceptance: all literals present; 0 `static` in PriceEndpoints read path (2 matches are Doxygen prose); scoped_env has `_putenv_s`/`_putenv`/`setenv`/`unsetenv` and no `SetEnvironmentVariable` call (mentions are the rationale comment); coinprices + genius_node builds exit 0
- Task 2 acceptance: 0 deleted-member matches in hpp; `priceManager_.reset()` @2209, `GetOrCreatePriceManager()->GetQuotes` @3556, empty-ids short-circuit @3551; files absent; 0 `CoinGeckoPriceRetriever` under `SuperGenius/src`; PriceFetchError diff comment-only; 0 `"CoinPrices"` logger lines; genius_node + account_management_test builds exit 0; 4/4 price suites green
- Task 3 acceptance: `'Kept compiling'=0; 'D-09' citations=1` — PASS
- Plan-level verification: all three verify commands exit 0
