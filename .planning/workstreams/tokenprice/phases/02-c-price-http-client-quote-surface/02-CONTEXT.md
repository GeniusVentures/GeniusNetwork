# Phase 2: C++ Price HTTP Client & Quote Surface - Context

**Gathered:** 2026-09-30
**Status:** Ready for planning

<domain>
## Phase Boundary

The transport-correctness layer for C++ price fetching — delivered as an **upgrade to AsyncIOManager's HTTPDevice** (user decision, overriding the research/roadmap sketch of a price-scoped Beast client) plus the provider-independent `PriceQuote` types and the scriptable stub server that makes everything hermetically testable.

Requirements in scope: QUOTE-01, QUOTE-02, LPM-05, LPM-06 (reinterpreted — see D-01), LPM-07, LPM-08, FRESH-02 (classification side), TEST-03.

**Critical redirection:** The roadmap's plan seeds (02-02 "Boost.Beast HTTPS client in the price module", 02-03 "Beast stub server fixture") are superseded by D-01 — the status-aware HTTPS transport is built in `thirdparty/AsyncIOManager` (dev_tokenprice branch), consumed from `SuperGenius/src/coinprices/`. The stub server may still use Beast locally as a test fixture (`SuperGenius/test/`) since it's test-only code, but it drives the upgraded HTTPDevice surface, not a parallel client.

</domain>

<decisions>
## Implementation Decisions

### Transport: upgrade AsyncIOManager, not a parallel Beast client
- **D-01 (user decision 2026-09-30):** The status-aware HTTPS transport work lands in `thirdparty/AsyncIOManager` — NOT as a price-scoped Boost.Beast client in `SuperGenius/src/coinprices/`. User challenge: "we have asynciomanager for http retrieval... if we need to update anything for status, TLS, timeouts, we should update asynciomanager." The new surface must surface real status codes/headers (LPM-05's root fix — today `HTTPCommon.cpp:255ff` slices at `\r\n\r\n` and discards status), support plain HTTP, and take configurable timeouts/UA. This **rewording note applies to LPM-06** ("Boost.Beast client scoped to the price module") and to roadmap success criteria 2/5 and plan seeds 02-02/02-03 — the intent (truthful status, TLS verify, UA, timeouts, stub-driven tests) is unchanged; the vehicle is AsyncIOManager.
- **D-02:** The existing `LoadASync` callback contract is untouched — `processing_subtask_queue_accessor_impl.cpp` and all IPFS/file consumers see zero behavior change. The status-aware request surface is additive on `HTTPDevice` (or a sibling device class within AsyncIOManager).
- **D-03:** Plain-HTTP support (needed for the TEST-03 stub at 127.0.0.1) is added through the existing **virtual scheme-loader singleton design** — `FileManager::RegisterLoader("http", ...)` (today commented out at `HTTPLoader.cpp:34`, only `"https"` is registered). User emphasis: "asynciomanager is a kind of singleton design that handles many types of URLs... through virtual classes" — extend that pattern, don't bypass it.
- **D-04 (user corrections on URL handling):** No URL-shape rework is needed — `parseHTTPUrl` already splits host/path and passes query strings through in the path (user: "I'm pretty sure we already send a path+query url... not seeing a problem really"). The only real gaps are non-HTTPS support and the TLS/status work. Chunked-transfer handling is NOT new-surface scope (the CoinGecko `/simple/price` path won't need it; historical endpoints are Phase 4's problem if kept at all).

### Submodule mechanics
- **D-05 (user decision):** The AsyncIOManager/thirdparty work is included **in Phase 2 itself** — "just make sure to make a dev_tokenprice on asynciomanager/thirdparty." Create `dev_tokenprice` branches on the AsyncIOManager submodule (and thirdparty superproject if pointer bumps require it). Commit order innermost-first: AsyncIOManager → SuperGenius → root GeniusNetwork (per standing memory on nested-submodule discipline). Never push without explicit per-command approval.

### TLS & connection policy
- **D-06:** TLS verification (verify_peer + SNI + hostname check) is enabled on the **new status-aware surface only** — existing `LoadASync` consumers keep today's behavior. (Fixes the latent no-op: `s_verify_peer=true` skips `verify_none` but nothing ever positively verifies.) Zero blast radius beyond the new API.
- **D-07:** CA trust comes from an **in-repo `cacert.pem`** shipped with SuperGenius, path configurable at construction. No system-trore dependency — consistent across the 16-config CI matrix and containers.
- **D-08:** `User-Agent` becomes a **per-request/per-device parameter**. Price requests send a CoinGecko-friendly UA (product/contact info per their API etiquette); other consumers can keep `GeniusAI/1.0 (SGNS AsyncIO Manager)` or set their own.
- **D-09 (user decision):** Threading model stays as today — **caller supplies the io_context** ("continue as we have been doing, I think we provide an ioc"). HTTPDevice remains executor-agnostic; no owned thread pool in AsyncIOManager. The Phase 3 price manager will own its io_context + thread (replacing today's throwaway per-request `io_context` at `coinprices.cpp:133`).
- **D-10:** Timeouts are **per-request parameters** on the new surface; the price client sets ≈5s connect/handshake/read per LPM-06. Existing `LoadASync` keeps the current 10/10/30s deadlines.

### Retry & backoff
- **D-11:** Retryable set is **transport errors only**: timeout, connection reset, DNS failure. Never retry 403/429/any 4xx/5xx body or malformed responses.
- **D-12:** Backoff is a **fixed 1s → 2s → 4s schedule, cap 3 attempts total**, constants configurable at construction (tests may inject 0ms — the fixed shape keeps unit tests deterministic).
- **D-13:** 429 handling uses a **client-side hold-off timer**: a 429 from CoinGecko sets a hold-until timestamp; until it expires the CoinGecko tier is skipped entirely (fallback goes straight to token.gnus.ai). Injectable clock for hermetic tests. This is the enforcement mechanism behind LPM-07's "no sub-minute retries against CoinGecko".

### Quote types & error model
- **D-14:** `PriceQuote::timestamp` means **fetch time** (the moment the price was fetched — aligned with the envelope's `fetchedAt` and the DO's per-id `fetchedAt` rows per Phase 1 D-11). Freshness bands are computed as `now − timestamp`. No local-store-time re-basing.
- **D-15:** Error taxonomy is a **typed price-specific enum in `outcome::result`** following the existing `CoinGeckoPriceRetriever::PriceError` pattern — extended to carry the real HTTP status alongside (e.g. transport error with optional status), satisfying LPM-05's "logged error string contains the actual status code".
- **D-16:** Freshness band boundaries are **closed on the fresh side**: age ≤ 60s = Fresh; 60s < age ≤ 5min = StaleButUsable; age > 5min = Unavailable. Exactly-60s is Fresh, exactly-5min is StaleButUsable. Matches FRESH-01/02 and the Worker's D-12 gates.

### Claude's Discretion
- Exact new-surface API shape on HTTPDevice (method names, request/response struct fields), where the class sits in AsyncIOManager's file layout, and how the plain-HTTP loader class relates to the existing HTTPS device (virtual base vs template vs two classes).
- `PriceQuote`/`PriceSource` header location and exact field types (`std::chrono::system_clock::time_point` vs `int64_t` epoch) — planner decides with conventions in mind.
- Stub server implementation details (Beast is fine for the test fixture; OS-assigned port via acceptor; per-path scripted responses) as long as it drives the upgraded HTTPDevice surface and serves the 403-HTML/429 fixtures.
- cacert.pem sourcing (curl.se bundle vs extract) and its exact in-repo location.
- Retry-state placement (per-device vs price-client-owned) as long as the hold-off timer is injectable-clock testable.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Transport code being upgraded (primary)
- `thirdparty/AsyncIOManager/src/HTTPCommon.cpp` — `HTTPDevice` today: SNI set (~line 137), UA hard-coded (~line 196), deadline timers 10/10/30s, status stripped at `\r\n\r\n` slice (~line 255ff), `s_verify_peer` no-op toggle (lines 72, 128-131)
- `thirdparty/AsyncIOManager/src/HTTPLoader.cpp` — scheme-loader singleton; `"http"` registration commented out (line 34), `parseHTTPUrl` → `HTTPDevice` flow
- `thirdparty/AsyncIOManager/src/URLStringUtil.cpp` — `parseHTTPUrl` (line 40ff): host/path split, query stays in path, default port 443
- `thirdparty/AsyncIOManager/src/FileManager.hpp` — the loader-registry singleton the new surface extends

### Price module (consumer side)
- `SuperGenius/src/coinprices/coinprices.cpp` — the client being replaced: throwaway io_context (line 133), `FileManager::LoadASync` call (line 178), `decodeChunkedTransfer` hack (line 23), retry+sleep (lines 100-112)
- `SuperGenius/src/coinprices/coinprices.hpp` — existing `PriceError` enum pattern D-15 extends
- `SuperGenius/src/coinprices/CMakeLists.txt` — module link structure (Boost::headers, rapidjson, AsyncIOManager)
- `SuperGenius/src/account/GeniusNode.cpp:3510-3585` — `GetCoinprice` seam + the three retriever endpoints (current/historical/range); only `getCurrentPrices` is in the price path

### Workstream planning
- `.planning/workstreams/tokenprice/REQUIREMENTS.md` — QUOTE-01/02, LPM-05..08, FRESH-02, TEST-03 definitions; note LPM-06's "Boost.Beast" wording is superseded by D-01 here
- `.planning/workstreams/tokenprice/ROADMAP.md` — Phase 2 goal + plan seeds 02-01..02-04 (02-02/02-03 vehicle superseded by D-01; intent unchanged)
- `.planning/workstreams/tokenprice/phases/01-token-gnus-ai-worker-service/01-CONTEXT.md` — Phase 1 envelope contract decisions (D-06..D-12) this phase's parsing targets; `fetchedAt` semantics
- `.planning/workstreams/tokenprice/research/ARCHITECTURE.md` — system overview; its "Beast HTTPS price client" component sketch is superseded by D-01

### Build mechanics (submodule flow)
- `/memories/repo/thirdparty-inner-vcxproj-rebuild.md` — Windows inner-vcxproj rebuild flow for AsyncIOManager changes (copy lib, rebuild SuperGenius target)
- `/memories/repo/asynciomanager-save-location-url.md` — prior AsyncIOManager branch-fix precedent (dev_elmbridge flow)

### Diagnosis
- `/memories/repo/coingecko-price-api-frontend.md` — motivating diagnosis: 403 path-scoped WAF, minutes-scale 429, no rate-limit headers, coinprices.cpp client bugs

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `HTTPDevice` deadline machinery (`ArmDeadline`/`CancelDeadline`, HTTPCommon.cpp:13-52) — works correctly; the new surface keeps the pattern but parameterizes the durations (D-10)
- `parseHTTPUrl` (URLStringUtil.cpp) — already passes path+query; no rework needed (D-04)
- Scheme-loader registry (`FileManager::RegisterLoader`) — the extension point for plain HTTP (D-03)
- `CoinGeckoPriceRetriever::PriceError` (coinprices.hpp) — the outcome-enum pattern D-15 follows
- Beast WebSocket usage (`SuperGenius/src/api/transport/impl/ws/ws_client_impl.hpp`) — precedent for Beast in test fixtures if the stub server uses it

### Established Patterns
- AsyncIOManager loaders are scheme-keyed virtual classes behind the `FileManager` singleton — the new surface extends this pattern rather than adding a parallel transport (user-stated design intent, D-03)
- SuperGenius modules link `Boost::headers` + `outcome` and expose `outcome::result<T>` surfaces; price module errors follow the enum-category pattern
- Test binaries live under `SuperGenius/test/src/<suite>/` with GTest, `disable_clang_tidy`, and `RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/test_bin` (see `test/src/price_retrieval/CMakeLists.txt`)

### Integration Points
- `SuperGenius/src/coinprices/CMakeLists.txt` links `AsyncIOManager` PRIVATE — the upgraded surface flows in through that existing link; no new dependency
- Phase 3 consumes: the `PriceQuote`/`PriceSource` types (D-14/D-16), the new-surface request API with per-request timeouts/UA, and the retry classification + hold-off timer (D-11..D-13)
- Phase 4 consumes: endpoint configurability on top of this client for stub redirection (TEST-04/05)
- The Phase 1 envelope (`fetchedAt` per-id max, D-11 of 01-CONTEXT.md) is what D-14's timestamp semantics align with

</code_context>

<specifics>
## Specific Ideas

- User's framing for the transport: "if we need to update anything for status, TLS, timeouts, we should update asynciomanager" — treat AsyncIOManager as the shared transport asset, not a frozen thirdparty dependency.
- User's reminder that localhost stub tests don't need HTTPS: the plain-HTTP loader registration is the enabler, and it's a two-line un-comment plus dispatch work in the existing virtual design.
- The 403-HTML and 429 fixtures from the CoinGecko diagnosis remain the canonical stub scenarios (roadmap criterion 1: 403 logs an error containing `403`, never reaches the JSON parser).

</specifics>

<deferred>
## Deferred Ideas

None new this phase. Carried forward from Phase 1's deferred section (unchanged): the aarch64-Debug `GTEST_FILTER` exclusion removal requires the MNN/Vulkan thirdparty rebuild rider — re-scope Phase 5's plan 05-02 and TEST-04's exclusion-removal clause when Phase 5 is planned.

### Roadmap wording corrections required by D-01 (planner must apply)
- ROADMAP Phase 2 success criteria 2 & 5 and plan seeds 02-02/02-03 reference "Boost.Beast HTTPS client in the price module" — the delivered artifact is the upgraded AsyncIOManager surface consumed by the price module. Success criteria intent (truthful status, SNI+verify_peer+pinned CA, ≈5s timeouts, 403/429 semantics, stub-driven hermetic tests) is unchanged; plans should be authored against the AsyncIOManager vehicle with the same acceptance assertions.
- REQUIREMENTS LPM-06's "(not `FileManager::LoadASync`)" phrasing: the *throwaway-io_context status-blind usage pattern* is what's being left behind; the new surface may live behind FileManager's registry as long as it is status-aware, TLS-verifying, timeout/UA-configurable (D-01..D-03).

</deferred>

---

*Phase: 2-C++ Price HTTP Client & Quote Surface*
*Context gathered: 2026-09-30*
