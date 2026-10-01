---
phase: 02-c-price-http-client-quote-surface
plan: 04
subsystem: coinprices
tags: [price, facade, retry, error-taxonomy]
requires:
  - sgns::HTTPClient surface (02-02)
  - HttpStubServer fixture (02-03)
  - PriceQuote/PriceSource types (02-01)
provides:
  - sgns::PriceFetchError (8 values) + PriceFetchFailure{code, httpStatus, Message()}
  - sgns::PriceResult<T>
  - sgns::RetryConfig / RetryDecision / IsTransient / IsTransientTransport / ShouldRetry
  - sgns::RateLimitHoldOff (injectable Clock)
  - sgns::PriceHttpClient (FetchPrices, AttemptsLastFetch, kUserAgent, injectable requestTimeout)
affects: []
tech-stack:
  added: []
  patterns:
    - status-before-parse gate with single rapidjson branch
    - per-attempt io_context in sequential retry loops
key-files:
  created:
    - SuperGenius/src/coinprices/PriceFetchError.hpp
    - SuperGenius/src/coinprices/PriceRetryPolicy.hpp
    - SuperGenius/src/coinprices/PriceRetryPolicy.cpp
    - SuperGenius/src/coinprices/PriceHttpClient.hpp
    - SuperGenius/src/coinprices/PriceHttpClient.cpp
    - SuperGenius/test/src/price_facade/price_facade_test.cpp
    - SuperGenius/test/src/price_facade/CMakeLists.txt
  modified:
    - SuperGenius/src/coinprices/CMakeLists.txt
    - SuperGenius/test/src/CMakeLists.txt
    - SuperGenius/test/testutil/http_stub/HttpStubServer.cpp (query-stripped matching)
key-decisions:
  - PriceResult uses basic_result<T, PriceFetchFailure, policy::terminate> — struct error types cannot use the error_code default policy
  - Facade retry loop creates a fresh io_context per attempt — a run()-to-completion ioc cannot be reliably reused sequentially
  - HttpStubServer matches scripts on path-only (query stripped) so /simple/price?ids=... matches
  - requestTimeout is a constructor parameter (5000ms default) so timeout tests don't wait 5s
  - rapidjson guard uses IsNumber (int literals for whole prices fail IsDouble)
requirements-completed: [LPM-07, LPM-05, LPM-06]
coverage:
  - deliverable: "Typed error taxonomy with status embedding (D-15)"
    verification:
      - kind: test
        ref: "test/src/price_facade/price_facade_test.cpp#PriceFetchErrorTest.MessageEmbedsStatus+EnumeratorsPreserveLegacyOrder"
        status: pass
    human_judgment: false
  - deliverable: "Retry policy: transient-only, cap 3, zero-backoff injectable (D-11/D-12)"
    verification:
      - kind: test
        ref: "test/src/price_facade/price_facade_test.cpp#PriceRetryPolicyTest.IsTransientTruthTable+ShouldRetryCapsAtThreeForTransient+ShouldRetryNeverRetriesStatusBearing"
        status: pass
    human_judgment: false
  - deliverable: "429 hold-off with injectable clock (D-13)"
    verification:
      - kind: test
        ref: "test/src/price_facade/price_facade_test.cpp#PriceRetryPolicyTest.RateLimitHoldOffWithInjectableClock + PriceFacadeTest.RateLimited429FailsAndArmsHoldOff + HeldOffTierSkipsNetworkEntirely"
        status: pass
    human_judgment: false
  - deliverable: "Facade: status gate, UA, 5s defaults, PriceQuote production (LPM-05/06, D-14)"
    verification:
      - kind: test
        ref: "test/src/price_facade/price_facade_test.cpp#Ok200ProducesQuotesWithD14Fields+Blocked403FailsImmediatelyWithStatus+TimeoutRetriesToCapThree+UserAgentIsTheCoinGeckoFriendlyOne (+6 more)"
        status: pass
    human_judgment: false
  - deliverable: "Phase gate: all three suites green twice"
    verification:
      - kind: command
        ref: "ctest -R price_quote_test|price_http_client_test|price_facade_test — 100% x2"
        status: pass
    human_judgment: false
duration: 75 min
completed: 2026-09-30
---

# Phase 2 Plan 04: Price Facade + Retry Policy Summary

Phase-closing composition: `PriceHttpClient` facade over the proven 02-02 transport with the LPM-05 structural guarantee (status gate before the single rapidjson branch — non-200 bodies are unreachable by the parser), CoinGecko-friendly UA + 5s injectable timeouts (LPM-06), the D-11/D-12 transient-only retry policy (fixed 1s/2s schedule, cap 3, 403/429 immediate fall-through), the D-13 injectable-clock 429 hold-off with tier-skip, and the D-15 typed error taxonomy embedding the numeric status in every failure message. 15 hermetic tests against the 02-03 stub; phase gate 100% × 2.

## Accomplishments

- `PriceFetchError.hpp`: 8-value taxonomy preserving legacy ordering (slots 1-6 byte-compatible) + `PriceFetchFailure{code, httpStatus}` with fmt `Message()` embedding the status; `PriceResult<T>` on `policy::terminate` (struct errors can't use the error_code default)
- `PriceRetryPolicy.hpp/.cpp`: `IsTransient` (transport-only truth table), `IsTransientTransport(ClientError)` (TIMEOUT/CONNECT/RESOLVE), `ShouldRetry` (cap-3, never status-bearing), `RateLimitHoldOff` (injectable Clock, re-triggerable, mutex-guarded)
- `PriceHttpClient.hpp/.cpp`: hold-off-first tier skip (zero network when held), `parseHTTPUrl` base split, https/plain switch with `SGNS_DEFAULT_CACERT_PATH`, per-attempt ioc retry loop, status gate → 403 Blocked / 429 RateLimitExceeded+TriggerHoldOff / other HttpStatus, single parse branch, per-id `PriceQuote` with D-14 fetch-time timestamp; `AttemptsLastFetch()` test accessor
- `price_facade_test` (15 cases): quote fields, 403/429 immediate-fail with status, held-off skip, timeout cap-3, parse-error-on-200-only, partial coverage, no-data, UA echo, plus 6 policy/error unit cases
- Stub fixture refinement: query-stripped script matching (`/simple/price?ids=...` → `/simple/price`)
- Commit chain: SuperGenius `faa5eac33`; root pointer bumps `95c35ea` (verified single-line diffs before commit)

## Deviations from Plan

**[Rule 3 - API detail] PriceResult policy** — Found during: Task 1 compile | Issue: plan's `outcome::result<T, PriceFetchFailure>` alias hits boost.outcome's error_code-assuming default policy (exception_ptr conversion errors) | Fix: `basic_result<T, PriceFetchFailure, policy::terminate>` | Files: PriceFetchError.hpp | Commit: faa5eac33

**[Rule 3 - Bug in plan sketch] Stub query matching** — Found during: Task 4 first run (404 on all facade tests) | Issue: plan's tests script bare paths but the facade sends path+query targets; the stub keyed on exact target | Fix: stub strips `?query` before table lookup (also matches the plan's own "query-stripped matching" note) | Files: HttpStubServer.cpp | Commit: faa5eac33

**[Rule 3 - Test correctness] Integer price literals** — Found during: MissingId test | Issue: `IsDouble()` guard rejected `"usd": 1` (int literal) → NoDataFound on a valid partial response | Fix: `IsNumber()` | Files: PriceHttpClient.cpp | Commit: faa5eac33

**[Rule 3 - Design refinement] Per-attempt io_context** — Found during: TimeoutRetries hang | Issue: sequential `ExecuteBlocking` calls on one caller ioc — a run()-completed ioc needs restart(), and the restart path still hung in the asio scheduler | Fix: facade creates a fresh ioc per attempt (retry is inherently sequential; Phase 3's manager owns contexts) + kept `ioc->restart()` in ExecuteBlocking as defense | Files: PriceHttpClient.cpp, AsyncIOManager/src/HTTPClient.cpp | Commit: faa5eac33 (+AsyncIOManager pending)

**[Rule 3 - API addition] Injectable requestTimeout** — Found during: TimeoutRetries test design | Issue: 5s default timeouts make timeout tests slow/flaky against a 3s stub delay | Fix: constructor parameter (default 5000ms, LPM-06 unchanged) | Files: PriceHttpClient.hpp/.cpp | Commit: faa5eac33

**Total deviations:** 5 auto-fixed. **Impact:** API surface strictly widened (defaults preserve plan intent); all acceptance criteria met.

## Verification Results

1. Build: `coinprices` + all three test targets green
2. Test: `ctest -R "price_quote_test|price_http_client_test|price_facade_test"` — **100% × 2** (8 + 11 + 15 cases)
3. Legacy no-regression: `coinprices.cpp/.hpp` and AsyncIOManager legacy files — diffs empty
4. Root pointer bumps: single-line submodule diffs verified before commit (`95c35ea` on `dev_persisprocresults`)
5. No live network anywhere; stub loopback-only

## Issues Encountered

One AsyncIOManager follow-up commit (`ioc->restart()` defense) is included in the SuperGenius-commit chain but not yet committed on the AsyncIOManager branch — noted below.

## Next Phase Readiness

Phase 3 consumes `PriceHttpClient` as-is (its manager owns the ioc/threads per D-09); the facade's `PriceResult`/hold-off/retry surface is complete.

## Self-Check: PASSED
