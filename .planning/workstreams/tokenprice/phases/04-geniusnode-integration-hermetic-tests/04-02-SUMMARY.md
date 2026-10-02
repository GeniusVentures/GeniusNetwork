---
phase: 04-geniusnode-integration-hermetic-tests
plan: 02
subsystem: testing
tags: [hermetic-tests, http-stub, env-redirect, account-suite]

requires:
  - phase: 04-geniusnode-integration-hermetic-tests
    provides: 04-01 ScopedEnvVar guard, env-var names, cut-over GetCoinprice seam
provides:
  - Hermetic account_management_test — SetPayoutAddress resolves GetProcessCost against a loopback stub (no live CoinGecko)
affects: [Phase 5 CI (aarch64-Debug exclusion removal)]

tech-stack:
  added: []
  patterns:
    - "Fixture-ctor env redirect: stub Start -> ScopedEnvVar both tiers -> GeniusNode::New; per-TEST_F fresh stub/node/manager"

key-files:
  created: []
  modified:
    - SuperGenius/test/src/account/account_management_test.cpp
    - SuperGenius/test/src/account/CMakeLists.txt

key-decisions:
  - "D-12 honored: ctor-level redirect, whole-suite hermetic; assertions byte-untouched"

patterns-established:
  - "Per-test fresh stub + env guard in fixture ctor/dtor (no SetUp/TearDown — env must precede New which precedes SetUp)"

requirements-completed: [TEST-04]

coverage:
  - id: D1
    description: "SetPayoutAddress passes with both price tiers redirected to the local stub, no live CoinGecko"
    requirement: TEST-04
    verification:
      - kind: integration
        ref: "account_management_test.exe --gtest_filter=AccountManagement.SetPayoutAddress — PASSED (35.2s)"
        status: pass
      - kind: integration
        ref: "ctest -R '^account_management_test$' — 1/1 Passed (69.7s)"
        status: pass
      - kind: unit
        ref: "source gates: ctor order Start<envCG<envFB<New True; OnPath(/api/v3/simple/price) present; diff = 28 insertions, 0 deletions (TEST_F bodies untouched)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Env redirection leak-free — prior env state restored after each TEST_F"
    requirement: TEST-04
    verification:
      - kind: integration
        ref: "full suite green via ctest (suite's other tests unaffected by the redirect — guards restore per test)"
        status: pass
    human_judgment: false

duration: 25 min
completed: 2026-10-01
status: complete
---

# Phase 4 Plan 02: account_management_test Hermetic Conversion Summary

**SetPayoutAddress now runs against a loopback HttpStubServer serving genius-ai@0.19 USD — the suite's live-CoinGecko dependency is gone; every TEST_F body byte-untouched.**

## Performance

- **Duration:** ~25 min
- **Tasks:** 1/1
- **Files:** 2 (test + CMake)

## Accomplishments
- Fixture ctor scripts `/api/v3/simple/price` → 200 `{"genius-ai":{"usd":0.19}}`, starts the stub (OS-assigned port), sets both `SGNS_COINGECKO_URL`/`SGNS_PRICE_FALLBACK_URL` guards, then runs the existing bootstrap verbatim — strict D-12 ordering verified in source
- Fixture dtor resets env guards before `stub_.Shutdown()` (member order: guards declared after stub_)
- `GetProcessCost` inside `SetPayoutAddress` is now deterministic against the scripted 0.19 price
- One CMake line: `price_test_support` linked for the stub include

## Task Commits

1. **Task 1: fixture conversion + CMake link** — `aeb2aba6d` (test)

## Files Created/Modified
- `SuperGenius/test/src/account/account_management_test.cpp` — hermetic fixture (28 insertions, 0 deletions)
- `SuperGenius/test/src/account/CMakeLists.txt` — link line

## Decisions Made
None beyond plan — ctor/dtor placement (not SetUp/TearDown) per RESEARCH Pattern 3; guard member order per the plan's member-order rule.

## Deviations from Plan

None - plan executed exactly as written.

## Self-Check: PASSED

- Build exit 0; focused `SetPayoutAddress` run PASSED; full suite ctest 1/1 Passed
- Hermetic proof: the only price traffic is loopback (stub on 127.0.0.1; both tiers redirected before `GeniusNode::New`)
- Zero-hunk gate: diff shows 28 insertions, 0 deletions — no TEST_F body changed
