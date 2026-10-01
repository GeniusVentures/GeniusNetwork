---
phase: 02-c-price-http-client-quote-surface
plan: 03
subsystem: coinprices-tests
tags: [testing, http-stub, hermetic, testutil]
requires:
  - sgns::HTTPClient surface (02-02)
provides:
  - sgns::testutil::HttpStubServer (scriptable 127.0.0.1 OS-port Beast stub; Phase 4 reuses it)
  - price_test_support static lib
  - price_http_client_test hermetic matrix (11 cases)
affects: []
tech-stack:
  added: []
  patterns:
    - Beast accept/session loop with per-path script table
    - work-guard release inside completion (P-8 discipline)
key-files:
  created:
    - SuperGenius/test/testutil/http_stub/HttpStubServer.hpp
    - SuperGenius/test/testutil/http_stub/HttpStubServer.cpp
    - SuperGenius/test/testutil/http_stub/CMakeLists.txt
    - SuperGenius/test/src/price_http_client/price_http_client_test.cpp
    - SuperGenius/test/src/price_http_client/CMakeLists.txt
  modified:
    - SuperGenius/test/testutil/CMakeLists.txt
    - SuperGenius/test/src/CMakeLists.txt
    - thirdparty/AsyncIOManager/src/HTTPClient.cpp (transport fixes this plan's tests forced)
    - thirdparty/AsyncIOManager/src/HTTPLoader.cpp (async dispatch fix)
key-decisions:
  - ParseResponse feeds Beast incrementally (loop put() until consumed==0, then put_eof) — a single put() on a full response consumes headers only (119/145 bytes observed) and put_eof on an incomplete body errors as NO_HEADER
  - ExecuteBlocking releases its work guard inside the completion callback — held-forever guards deadlock ioc->run()
  - Plain-HTTP loader dispatch uses async Execute, never ExecuteBlocking — the caller owns the ioc run-loop
  - HTTPClient must be make_shared'd (shared_from_this lifetime); request string kept alive via shared_ptr through async_write
requirements-completed: [TEST-03, LPM-05]
coverage:
  - deliverable: "HttpStubServer scriptable fixture (TEST-03)"
    verification:
      - kind: test
        ref: "test/src/price_http_client/price_http_client_test.cpp#StubBindsLoopbackWithOsAssignedPort+TwoStubsBindDifferentPorts+ShutdownJoinsWithoutHang"
        status: pass
    human_judgment: false
  - deliverable: "Client matrix: 200/403-HTML/429/404 truth (LPM-05)"
    verification:
      - kind: test
        ref: "test/src/price_http_client/price_http_client_test.cpp#Ok200+Blocked403Html+RateLimited429+NotFound404"
        status: pass
    human_judgment: false
  - deliverable: "Timeout + UA + plain-loader paths (LPM-06 halves, D-03)"
    verification:
      - kind: test
        ref: "test/src/price_http_client/price_http_client_test.cpp#ReadTimeoutSlow+ReadTimeoutHang+UserAgentPropagates+PlainLoaderHttpUrl"
        status: pass
    human_judgment: false
  - deliverable: "Suite stability"
    verification:
      - kind: command
        ref: "3 consecutive ctest runs — 100% each"
        status: pass
    human_judgment: false
duration: 95 min
completed: 2026-09-30
---

# Phase 2 Plan 03: Stub Server + Hermetic Client Matrix Summary

Beast-based scriptable `HttpStubServer` (127.0.0.1, OS-assigned port, per-path status/body/content-type/delay/hang) as reusable test infrastructure, plus the 11-case hermetic matrix proving the 02-02 surface behaviorally: 200 round-trip, 403-HTML (transport SUCCESS with truthful status, never reaches the parser), 429, 404, slow+hang read timeouts classifying `ClientError::TIMEOUT`, UA propagation, and the plain-HTTP `FileManager::LoadASync` loader path. The bring-up surfaced and fixed four real transport bugs in 02-02's code.

## Accomplishments

- `HttpStubServer` (namespace `sgns::testutil`): `OnPath`/`Start`/`Port`/`Url`/`Shutdown` + `LastUserAgent` capture; own ioc + thread; post-then-stop Shutdown ordering; parked sessions for `/hang`; `price_test_support` static lib under testutil
- `price_http_client_test` (11 tests, registered via `addtest`): full roadmap criterion 1/2(timeout half)/5 evidence; `ParseBodyIfOk` helper encodes the status-before-parse discipline in-suite; zero non-loopback hosts
- Transport fixes forced by the matrix (committed `1888f6b`, `ebb89ab`): incremental Beast parse loop; `ExecuteBlocking` guard release in completion; async (not blocking) loader dispatch; request-buffer lifetime; plus the earlier `sgns::http` category registration repair
- 3× consecutive green runs; `price_quote_test` still green alongside

## Deviations from Plan

**[Rule 1 - Bug in 02-02 implementation] Beast single-put parse defect** — Found during: Task 2 first green-path run | Issue: `parser.put()` consumed only headers (119/145 bytes) — a single call on a full response leaves the body unconsumed, and `put_eof()` on the incomplete body failed as NO_HEADER | Fix: incremental feed loop until consumed==0 then put_eof | Files: `AsyncIOManager/src/HTTPClient.cpp` | Verification: Ok200/403/429/404 green | Commit: 1888f6b

**[Rule 1 - Bug in 02-02 implementation] ExecuteBlocking work-guard deadlock** — Found during: Task 2 matrix run | Issue: guard held for the whole call meant `ioc->run()` never returned after completion | Fix: `make_shared` guard released inside the completion callback | Files: same | Commit: 1888f6b

**[Rule 1 - Bug in 02-02 implementation] Plain-loader blocking dispatch** — Found during: PlainLoaderHttpUrl bring-up | Issue: loader's `ExecuteBlocking` would double-run/deadlock the caller's work-guarded ioc | Fix: async `Execute` with adapter completion (mirrors HTTPS dispatch shape) | Files: `AsyncIOManager/src/HTTPLoader.cpp` | Commit: ebb89ab

**[Rule 1 - Bug in 02-02 implementation] Request-string dangling view + HTTPClient lifetime** — Found during: Ok200 hang diagnosis | Issue: `get_request` captured by reference into the async chain (dies at StartExchange return); stack-constructed HTTPClient threw bad_weak_ptr on shared_from_this | Fix: `make_shared<std::string>` request + tests use `make_shared<HTTPClient>` | Files: same + test file | Commit: 1888f6b

**[Rule 2 - Environment] Stale-obj incremental builds** — Found during: instrumented rebuilds | Issue: MSBuild considered HTTPClient.obj up-to-date despite newer source (tlog staleness), producing exes without the fixes | Fix: delete the obj before rebuilding during bring-up | Files: none in git | Commit: n/a

**Total deviations:** 5 (4 auto-fixed code bugs + 1 environment workaround). **Impact:** 02-02's surface is now behaviorally proven, which was this plan's entire purpose — the matrix caught every one of them.

## Verification Results

1. Build: `price_test_support` + `price_http_client_test` + `coinprices` + `price_quote_test` — all green
2. Test: `ctest -R "price_http_client_test|price_quote_test"` — **100% × 3 consecutive runs** (11 + 8 cases)
3. Hermeticity: only 127.0.0.1 in the suite source; no `https://` or `api.coingecko.com` strings
4. Timeout determinism: `/slow` (500ms client vs 3s server) and `/hang` both classify TIMEOUT; no flakes across runs
5. No live network in any verification step

## Issues Encountered

An editor-held buffer repeatedly reverted `HTTPClient.cpp` between sessions (the file-lock/`cl.exe` incident); final state verified clean via raw-disk reads and committed. Noted for future sessions: verify source-on-disk timestamps before trusting incremental builds.

## Next Phase Readiness

Ready for 02-04: the facade composes this proven transport; the stub + matrix pattern extends for its retry/hold-off tests.

## Self-Check: PASSED
