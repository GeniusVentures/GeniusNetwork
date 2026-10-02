---
phase: 04-geniusnode-integration-hermetic-tests
plan: 03
subsystem: testing
tags: [hermetic-tests, integration, fallback-chain, ctest-registration]

requires:
  - phase: 04-geniusnode-integration-hermetic-tests
    provides: 04-01 ScopedEnvVar + env-var names + cut-over GetCoinprice seam; 04-02 proven full-node bootstrap pattern
provides:
  - Hermetic, CTest-registered price_retrieval_test proving env-redirect -> lazy manager -> node seam -> both fallback tiers end-to-end
affects: [Phase 5 CI]

tech-stack:
  added: []
  patterns:
    - "One-stub-both-tiers integration fixture: distinct scripted paths per tier, path-only keys (stub strips query strings)"

key-files:
  created: []
  modified:
    - SuperGenius/test/src/price_retrieval/price_retrieval_test.cpp
    - SuperGenius/test/src/price_retrieval/CMakeLists.txt

key-decisions:
  - "O2 resolved: full-GeniusNode integration (heavyweight link shape) — the honest reading of D-10"
  - "O3 resolved: true >60s LKG aging NOT proven through the seam (clock unreachable); stays in price_manager_test — no clock-injection seam added to production"

patterns-established:
  - "Mid-test re-script flip (OnPath 403/429) as the warm-then-fail mechanism through the node seam"

requirements-completed: [TEST-05]

coverage:
  - id: D1
    description: "Hermetic CTest-registered integration suite, zero live-network cases"
    requirement: TEST-05
    verification:
      - kind: integration
        ref: "ctest -R price_retrieval_test — 1/1 Passed; all 5 TEST_Fs OK (direct run evidence)"
        status: pass
      - kind: unit
        ref: "source gate: 0 matches for CoinGeckoPriceRetriever/getHistorical*/api.coingecko.com; ctest -N lists the suite (registered)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Real wired path proven: env-redirect -> lazy manager -> node seam -> fallback tiers"
    requirement: TEST-05
    verification:
      - kind: integration
        ref: "HappyPathServesCoinGeckoShape OK (exact scripted prices); Tier1BlockedFallsBackToTier2Envelope OK (0.21 envelope value served); EmptyIdsReturnsEmptyMap OK (seam contract)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Warm-then-fail core-value proof through the seam (D-13)"
    requirement: TEST-05
    verification:
      - kind: integration
        ref: "WarmThenFailServesFreshL1 OK — 403-HTML flip after L1 warm-up still serves 0.19; RateLimitedTierStillServes OK"
        status: pass
    human_judgment: false
  - id: D4
    description: "New suite coexists with the four Phase 2/3 price suites"
    verification:
      - kind: command
        ref: "ctest -R 'price' — 5/5 Passed (quote/http_client/facade/manager/retrieval)"
        status: pass
    human_judgment: false

duration: 35 min
completed: 2026-10-01
status: complete
---

# Phase 4 Plan 03: price_retrieval_test Hermetic Rewrite Summary

**Full-node integration suite now proves the whole fallback chain through the real GetCoinprice seam — one stub serving both tiers, 5/5 scenarios green on loopback only, CTest-registered for the first time.**

## Performance

- **Duration:** ~35 min
- **Tasks:** 1/1
- **Files:** 2 (test rewrite + CMake rewrite)

## Accomplishments
- `PriceRetrievalIntegrationTest` fixture: one `HttpStubServer` scripting both tier paths (`/api/v3/simple/price` CoinGecko shape, `/v1/prices` Phase 1 envelope with byte-real fixture values), env guards for both tiers, then the account suite's proven node bootstrap — strict ctor ordering verified in source
- Five TEST_Fs through the real seam: happy path (partial map, absent unknown id), 403-HTML → tier-2 envelope fallback, warm-then-fail fresh-L1 (D-13 core value), 429 → tier-2 + hold-off tolerance, empty-ids → success-empty-map
- CTest registration via `addtest` + heavyweight `genius_node_test json_secure_storage price_test_support` link + 3-platform WHOLEARCHIVE block (the suite was deliberately unregistered before)
- Old live-CoinGecko smoke suite (3 tests incl. both historical-endpoint tests) deleted with the retriever per D-09

## Task Commits

1. **Task 1: suite rewrite + CMake registration** — `523383fb1` (test)

## Files Created/Modified
- `SuperGenius/test/src/price_retrieval/price_retrieval_test.cpp` — complete rewrite (~215 lines)
- `SuperGenius/test/src/price_retrieval/CMakeLists.txt` — registered heavyweight shape

## Decisions Made
- O2 → full-node integration; O3 → LKG aging left to `price_manager_test` (no production clock seam added)
- Per-test unique data dirs (`price_retrieval_node_N`) to avoid colliding with the account suite's `am_full_node_N` dirs

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Anonymous-namespace helpers failed to resolve `test::` prefix (C2653)**
- **Found during:** Task 1 (first build)
- **Issue:** The `using namespace sgns::test;` directive does not make `test::` usable as a namespace alias inside the anonymous-namespace helper functions
- **Fix:** Fully qualified `sgns::test::WriteTrustedSgnsConfig` / `MakeNodeReadyWithLocalTrust` / `removeAllWithRetry` at the three call sites
- **Files modified:** `price_retrieval_test.cpp`
- **Verification:** build exit 0
- **Committed in:** `523383fb1`

**Total deviations:** 1 auto-fixed. **Impact:** none — mechanical qualification.

## Self-Check: PASSED

- Source gates: 0 retriever/historical/live-URL matches; both scripted paths present; 403 flips present; ctor order Start < env < New verified at the construction site (initial False was the file-header doc comment, not code)
- ctest -N lists the suite; ctest run 1/1 Passed; all 5 TEST_Fs OK individually; combined `ctest -R price` 5/5 Passed
