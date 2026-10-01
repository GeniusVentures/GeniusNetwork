---
phase: 03-local-price-manager
plan: 03
subsystem: coinprices
tags: [price, fallback-chain, transport-classification, envelope-parser]
requires:
  - "03-02 LocalPriceManager with coalescing window"
  - "03-01 PriceHttpClient facade (retry/hold-off/status machinery)"
provides:
  - "PriceFetchFailure::transportError (std::optional<http::ClientError>) — D-14 shape (a)"
  - "Strict IsTransient: TIMEOUT/CONNECT_FAILED/RESOLVE_FAILED only; unclassified NetworkError NOT transient"
  - "PriceResponseParsers: ParseCoinGeckoSimplePrice (extracted behavior-identically) + ParseGnusPriceEnvelope (Phase-1 envelope contract)"
  - "ResponseFormat ctor param on PriceHttpClient/PriceHttpClientSource — token.gnus.ai tier is a second real instance"
  - "Two-tier remaining-set walk with gap-chase escalation + band-aware per-waiter assembly (Fresh serve / StaleButUsable stale-flagged LKG / Unavailable skip)"
affects:
  - "SuperGenius/test/src/price_facade/price_facade_test.cpp (D-14 fixture updates, same task as the code)"
tech-stack:
  added: []
  patterns:
    - "Remaining-set chain walk: failed tier leaves the set intact (wholesale escalation), partial success shrinks it (gap-chase) — D-09 in ~20 lines"
    - "LKG is not a separate store — one cache, two service modes (D-10); structural FRESH-02 compliance (a tier success re-classifies the entry Fresh)"
key-files:
  created:
    - SuperGenius/src/coinprices/PriceResponseParsers.hpp
    - SuperGenius/src/coinprices/PriceResponseParsers.cpp
  modified:
    - SuperGenius/src/coinprices/PriceFetchError.hpp
    - SuperGenius/src/coinprices/PriceRetryPolicy.cpp
    - SuperGenius/src/coinprices/PriceHttpClient.hpp
    - SuperGenius/src/coinprices/PriceHttpClient.cpp
    - SuperGenius/src/coinprices/PriceHttpClientSource.hpp
    - SuperGenius/src/coinprices/LocalPriceManager.cpp
    - SuperGenius/src/coinprices/CMakeLists.txt
    - SuperGenius/test/src/price_facade/price_facade_test.cpp
    - SuperGenius/test/src/price_manager/price_manager_test.cpp
key-decisions:
  - "Parser JsonParseError re-wrap: parse functions carry status 0; the facade wraps with response.status on the 200 path (facade parity preserved)"
  - "First Task-4 draft dropped the tier-returned-quote merge from per-waiter assembly (only L1 lookups were added) — 7 cases red; restored the merge per the plan's 'assembly prologue stays' instruction"
  - "http::ClientError lives in sgns::http — test fixtures qualify with sgns::http::ClientError"
requirements-completed: [LPM-04, FRESH-01, FRESH-02]
coverage:
  - deliverable: "D-14 strict transport classification + facade population + fixture updates (one commit unit)"
    verification:
      - kind: tests
        ref: "price_facade_test#IsTransientTruthTable (16 rows incl. 5 new false rows), ShouldRetryCapsAtThreeForTransient (TIMEOUT fixture), TimeoutRetriesToCapThree (real timeout still 3 attempts)"
        status: pass
    human_judgment: false
  - deliverable: "Parser extraction + ResponseFormat tier wiring"
    verification:
      - kind: tests
        ref: "price_facade_test + price_http_client_test 100% green (behavior-identical extraction)"
        status: pass
    human_judgment: false
  - deliverable: "Two-tier fallback chain with gap-chase and LKG assembly"
    verification:
      - kind: tests
        ref: "price_manager_test#Tier1WholesaleFailureEscalatesFullMissSetToTier2,Tier1PartialSuccessGapChasesOnlyMissingIds,BothTiersFailStaleEntryServesLastKnownGood,BothTiersFailOverFiveMinutesIsUnavailable,ExactlyThreeHundredSecondsStillServesLastKnownGood,MixedFreshImmediateAndStaleLkgAssembly,Blocked403NeverRetriesTier1AndGoesStraightToTier2,NothingServableSurfacesLastTierFailure"
        status: pass
    human_judgment: false
duration: 22 min
completed: 2026-10-01T22:12:00Z
---

# Phase 3 Plan 03: Four-Tier Fallback Chain + D-14 + Envelope Parser Summary

The complete L1-fresh → CoinGecko → token.gnus.ai → last-known-good chain with gap-chase escalation and band-aware LKG assembly, plus the D-14 strict transport-classification fold-in (Phase 2 gap #3 closed) and the two-tier response parsers making token.gnus.ai a second real PriceHttpClient.

**Duration:** ~22 min | **Tasks:** 5/5 | **Files:** 11 (2 created, 9 modified)

## Accomplishments

- **D-14 fold-in (one commit unit):** `PriceFetchFailure` gains defaulted `std::optional<http::ClientError> transportError`; `IsTransient` gates strictly (`TIMEOUT`/`CONNECT_FAILED`/`RESOLVE_FAILED` only; unclassified `{NetworkError, 0}` NOT transient); the facade populates the field from `result.error().value()` and the warn log reuses the class; `price_facade_test` truth-table rows carry classifications with 5 new false rows and the cap fixture carries `TIMEOUT` — landed same-task per the CI-red rule. All Phase 2 behavioral tests unchanged and green.
- **Parser extraction:** `PriceResponseParsers.hpp/.cpp` — `ParseCoinGeckoSimplePrice` (the facade loop moved verbatim; fetchTime parameterized) and `ParseGnusPriceEnvelope` (envelope contract: fetchedAt epoch-SECONDS shared timestamp, two-value source mapping with unknown-source→JsonParseError, absent-ids-not-errors, stale verbatim). Facade parse branch delegates; JsonParseError re-wrapped with the 200 status.
- **ResponseFormat wiring:** 6th defaulted ctor param on `PriceHttpClient` + passthrough on `PriceHttpClientSource`; target builders split (`/api/v3/simple/price?...&vs_currencies=` vs `/v1/prices?...&vs=`); `PriceResponseParsers.cpp` in CMake.
- **Two-tier walk + band-aware assembly in `DispatchBatchOnStrand`:** remaining-set walk (failed tier → wholesale escalation; partial tier → gap-chase; completed ids never re-added); per-waiter assembly = immediate LocalCache copies + tier-returned quotes (tier source preserved) + L1 lookups only for uncovered ids (Fresh serve / StaleButUsable `stale=true` timestamp-untouched / Unavailable skip); empty-overall surfaces `lastTierFailure`; info-level chain trace per dispatch.
- **8 chain test cases** (6 red-first: escalation, gap-chase, LKG, 300s boundary, mixed-band, 403-escalation; 2 regression guards: unavailable, surfaced-last-tier-failure). Suite now 21 cases, all green; 4/4 price suites green.

## Commit

- SuperGenius `dev_tokenprice` @ `3388b6d62` — `feat(coinprices): four-tier fallback chain + D-14 transport classification + envelope parser (LPM-04, FRESH-01/02, D-09..D-14)`

## Deviations from Plan

**[Rule 1 - Namespace qualification] `http::ClientError` needed `sgns::` qualification in test fixtures** — Found during: Task 1 build | Issue: HTTPTypes.hpp declares the enum inside `sgns::http`, so bare `http::ClientError`/`C::` uses failed to compile | Fix: `sgns::http::ClientError` in both fixtures | Files: `price_facade_test.cpp` | Verification: suite green | Commit: 3388b6d62

**[Rule 1 - Implementation slip] Task-4 rewrite dropped the tier-quote merge from per-waiter assembly** — Found during: Task 4 verify | Issue: my walk rewrite kept only the new L1 lookups and omitted merging `fetched` quotes into each waiter's assembled vector (the plan said the assembly prologue stays) — 7 cases red with "0 unresolved after tiers, 1 failed" | Fix: collect tier-returned quotes into `fetched` during the walk and merge per waiter before L1 lookups | Files: `LocalPriceManager.cpp` | Verification: 21/21 green | Commit: 3388b6d62

**[Rule 1 - MSVC] Non-default-constructible PriceResult ternary** — Found during: Task 2 build | Issue: `PriceResult<...> parsed;` default-init deleted (terminate policy) | Fix: initialize via the ternary expression directly | Files: `PriceHttpClient.cpp` | Verification: build green | Commit: 3388b6d62

**Total deviations:** 3 auto-fixed. **Impact:** none — final code matches the plan's semantics exactly; the dropped-merge slip was caught by the TDD red cases before commit.

## Self-Check: PASSED

- Task 1 AC: `PriceFetchFailure` has `transportError` + header includes `<HTTPTypes.hpp>`; two-field initializers still compile (unaffected rows untouched); strict IsTransient with `IsTransientTransport( *error.transportError )`; IsTransientTransport/ShouldRetry byte-identical; facade populates the third field (`transportClass`); price_facade_test green incl. TimeoutRetriesToCapThree==3 and the 5 new false rows; quote/http_client suites green — PASS.
- Task 2 AC: parsers declared in `sgns` with the landmine Doxygen notes; no inline `quotes.push_back` loop remains in PriceHttpClient.cpp; target builders differ exactly in path and `vs` vs `vs_currencies`; adapter forwards responseFormat; CMake lists PriceResponseParsers.cpp; both suites 100% — PASS.
- Task 3 AC: 8 cases compiled; 6 red before Task 4 (escalation/gap-chase/LKG/300s/mixed/403), 2 guards green — PASS (one intermediate full-suite run showed a transient 7th failure: a 1s-window case racing under build load; clean re-runs and the final gate show 21/21).
- Task 4 AC: 21 cases green; both tiers referenced with tier 2 under `!remaining.empty()`; three band branches present, StaleButUsable sets stale and does not touch timestamp, Unavailable skips; StoreInL1 only on success paths; no mutex — PASS.
- Task 5 AC: 4/4 suites one invocation; commit message matches; tree clean; nothing pushed; no thirdparty changes — PASS.

## Verification Results

| Check | Result |
|---|---|
| price_manager_test (21 cases) | PASSED |
| 4-suite ctest gate | 100% PASSED |
| price_facade policy tests (updated fixtures) | PASSED |
| `git -C SuperGenius log -1` | 3388b6d62 on dev_tokenprice |

Ready for 03-04 (TEST-02 completion + phase close-out).
