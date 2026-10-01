# Phase 3: Local Price Manager - Context

**Gathered:** 2026-10-01
**Status:** Ready for planning

<domain>
## Phase Boundary

The orchestration layer — `LocalPriceManager`, a single new C++ class in `SuperGenius/src/coinprices/` that owns all device-side price state and logic: the in-memory L1 cache (LPM-01), the ~50ms coalescing window with id-union batching (LPM-02/LPM-03), and the four-tier fallback chain fresh L1 → CoinGecko direct → token.gnus.ai → last-known-good with band-aware decisions (LPM-04, FRESH-01/02 manager-side). All behavior is unit-proven through an injected `IPriceSource` fake — zero sockets, deterministic (TEST-02). This phase also folds in the Phase 2 verification gap #3 fix (transport-error classification in `PriceFetchFailure`, retries gated on `IsTransientTransport`).

The manager performs **no I/O of its own** — it orchestrates two `PriceHttpClient` instances (CoinGecko, token.gnus.ai) behind the `IPriceSource` interface. Endpoint configurability (LPM-09) and the `GeniusNode::GetCoinprice` seam cutover (LPM-10) are Phase 4; the manager's blocking `GetQuotes` surface is designed as a drop-in for that seam but is not wired to it here.

Requirements in scope: LPM-01, LPM-02, LPM-03, LPM-04, FRESH-01 (manager-side band decisions), FRESH-02 (fallback decisions), TEST-02, plus the gap #3 retry-classification fix in the Phase 2 types.

</domain>

<decisions>
## Implementation Decisions

### Caller surface & ownership (Threading & API shape)
- **D-01:** The manager's public surface is **blocking**: `GetQuotes(ids, currency) → PriceResult<std::vector<PriceQuote>>`. An L1 hit returns without waiting; a miss blocks the calling thread until the chain resolves. This is a drop-in match for the Phase 4 `GeniusNode::GetCoinprice` seam (`outcome::result<std::map<std::string,double>>`) — no async callback surface is built (an async core + blocking wrapper was explicitly not chosen; revisit only if a real consumer appears).
- **D-02 (user decision, refining Phase 2's D-09 forward-note):** The manager owns **one `io_context` and one dedicated runner thread** started at construction and joined at destruction. The user's construction-time ioc idea ("when constructing a PriceHttpClient we could pass an ioc to it and have it use that") is adopted and completed with the runner thread: both `PriceHttpClient` instances receive the manager's ioc at construction. This **supersedes the throwaway-per-call ioc pattern** (`coinprices.cpp:133`) — that pattern remains fine for one-shot use but cannot coalesce across threads (a shared ioc run by multiple threads hits the run()/restart() tail-coupling landmine flagged in Phase 2 verification gap #2). All manager state (L1 cache, pending-window registry, timers, futures) is **strand-serialized** on that ioc — no hand-rolled mutex/condition-variable leader election.
- **D-03:** **Single in-flight fetch at a time.** The pending window naturally serializes upstream traffic; there is no concurrent tier fan-out. (Concurrent-tier pre-querying was considered and rejected — more states to test, and the ~5s per-request timeout already bounds the chain tail.)
- **D-04:** `PriceHttpClient::FetchPrices`'s existing `ioc` parameter needs no signature change — the manager passes its own ioc from within the strand; `ExecuteBlocking` is not used by the manager (the fetch runs as async work on the manager's thread).

### Coalescing mechanics
- **D-05:** **Fixed ~50ms collection window.** The first cache miss arms a `steady_timer` on the strand; ids arriving before it fires join the pending batch; dispatch covers the **union**; all waiters (including the first caller) block on futures until the fetch lands. The first caller always pays ~50ms — accepted as the price of a single larger batch (this is exactly the roadmap's "~50ms coalescing window"; immediate-dispatch/join-in-flight and hybrid-append variants were rejected).
- **D-06:** **Partial L1 hits fetch only the misses.** Fresh-in-cache ids are served immediately; only missing/stale ids enter the pending window and the upstream batch. Mirrors today's `GeniusNode::GetCoinprice` miss-collection loop (`GeniusNode.cpp:3510-3520`) — no all-or-nothing refetch of fresh quotes.
- **D-07:** **New misses during an in-flight fetch open a NEW pending window** which dispatches after the in-flight fetch completes (single-in-flight rule, D-03). Ids already being fetched are not re-added. Two rapid bursts produce at most two sequential batches; no id is ever fetched twice concurrently. (Wait-then-immediate-dispatch was rejected as harder to make deterministic.)
- **D-08:** Coalescing/batching applies **per currency** — requests for different currencies do not share a batch (the upstream call is per-currency by construction: `ids=<csv>&vs_currencies=<c>`). Exact data structure for per-currency windows is planner's discretion.

### Fallback chain
- **D-09:** **Batch escalation with per-id gap-chase.** A wholesale CoinGecko failure (403/429/timeout/5xx/transport — after the Phase 2 retry/hold-off policy runs its course) escalates the **entire miss-set** to token.gnus.ai. A **successful-but-partial** CoinGecko response gap-chases only the missing ids at token.gnus.ai (Phase 1 D-09 semantics: absent ids are not errors). Completed ids are never re-fetched in the same chain walk. Strict batch-only (gaps fall to LKG/error) was rejected — a WAF-blocked id would poison every batch containing it; per-id independent chains were rejected — they destroy LPM-03 batching.
- **D-10:** **Last-known-good is not a separate store** — it is the L1 cache entry that has aged into the stale band (60s–5min per `ClassifyFreshness`). One cache, two service modes: fresh entries serve normally (LPM-01), stale entries serve **only** when both network tiers fail (FRESH-02). Entries older than 5min are unavailable — never served (the >5min band is hard-unavailable; a separate keep-forever LKG map was explicitly rejected as contradicting the locked bands).
- **D-11:** A last-known-good quote is served with **`source: LocalCache`, `stale: true`, timestamp unchanged** (the real D-14 fetch time — never re-based). The consumer sees "this value came from my cache and it is old." Serving with the original provider's source enum was rejected — it blurs which tier served the quote and invites confusion with the envelope's `source` semantics (Phase 1 D-06).
- **D-12:** The CoinGecko 429 hold-off (Phase 2 D-13) integrates as: while held off, the chain's CoinGecko tier is **skipped entirely** — requests go L1 → (hold-off check) → token.gnus.ai → LKG. token.gnus.ai gets **no second hold-off** in v1 — it is the shared-cache tier by design (its own worker enforces upstream politeness); adding one is a deferred idea if abuse is ever observed.

### Test seam & Phase 2 gap #3 fold-in
- **D-13:** **One `IPriceSource` interface** — `FetchPrices(ids, currency) → PriceResult<std::vector<PriceQuote>>`, matching `PriceHttpClient::FetchPrices`'s shape exactly so the real client implements it with zero logic change (the ioc parameter is not part of the interface — see D-04; the concrete adapter closes over the manager's ioc). The manager holds two `IPriceSource` instances (CoinGecko tier, token.gnus.ai tier). Unit tests inject `FakePriceSource` objects with scriptable results and call counting — zero sockets (TEST-02's letter). Stub-URL injection (real client + `HttpStubServer`) was rejected for the unit suite — that pattern stays available for Phase 4 integration tests; per-tier separate interfaces were rejected as pure duplication.
- **D-14 (fold-in of Phase 2 verification gap #3):** Phase 3 extends `PriceFetchFailure` to carry the transport error classification (e.g. a `ClientError`/transient flag) and gates retry decisions on `IsTransientTransport`, so TLS-handshake/CA-load/write failures stop being blindly retried. This lands in the Phase 2 files (`PriceFetchError.hpp`, `PriceRetryPolicy.*`, `PriceHttpClient.cpp` retry loop) as a Phase 3 plan item — TEST-02's "retry classification (403/429 never retried against CoinGecko)" assertions then document the precise behavior.
- **D-15 (user decision):** Class name is **`LocalPriceManager`**, files `LocalPriceManager.hpp/.cpp` in `SuperGenius/src/coinprices/` — matches the roadmap's phase name and keeps the device-side distinction vs. the Worker's server-side `PriceCoordinator` DO (same single-flight pattern, two scopes — naming must not conflate them).
- **D-16 (envelope contract fidelity):** The Phase 3 fake `IPriceSource` fixtures replay **real envelope JSON captured from Phase 1's worker test output** — the C++ parsing path (via a `token.gnus.ai`-tier adapter over `PriceHttpClient`) is exercised against the true Phase 1 contract, without sockets. A live end-to-end test (real `wrangler dev` worker + C++ manager over loopback) is deferred — see Deferred Ideas.

### Claude's Discretion
- Exact `IPriceSource` header name/location and whether the interface is pure virtual class or `std::function` injection — planner decides (pure virtual class is the expected convention).
- Internal data structures: L1 cache keyed how (per-id `PriceQuote` map vs. per-(id,currency)), pending-window per-currency structure (D-08), future/promise plumbing from strand to blocking caller.
- The ~50ms constant's name/config surface (compile-time constant vs. constructor parameter for tests) — must be injectable for deterministic zero-delay tests.
- Whether the gap #3 classification rides as a new `PriceFetchFailure` field or a variant — planner decides with conventions in mind (D-14 fixes the behavior, not the shape).
- Logging detail level for chain-walk traces (which tier tried, what failed) — follow `base::Logger` conventions from Phase 2.
- How much of `coinprices.cpp`'s legacy retriever gets deleted vs. left compiling — Phase 4 owns the cutover; Phase 3 only adds the manager and touches the Phase 2 files per D-14.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 2 delivered code (the foundation this phase builds on)
- `SuperGenius/src/coinprices/PriceHttpClient.hpp` — the facade the manager orchestrates: constructor (baseUrl, RetryConfig, holdOffDuration, clock, requestTimeout), `FetchPrices(ioc, ids, currency)`, `AttemptsLastFetch()`, `kUserAgent`
- `SuperGenius/src/coinprices/PriceQuote.hpp` — `PriceQuote{asset, currency, price, timestamp, source, stale}` with D-14 fetch-time semantics; `PriceSource` enum incl. `LocalCache`/`GnusPriceService`
- `SuperGenius/src/coinprices/PriceFreshness.hpp` — `kFreshMaxAge{60}`/`kStaleMaxAge{300}`, `ClassifyFreshness` with closed-on-fresh boundaries — the bands the fallback decisions consume
- `SuperGenius/src/coinprices/PriceFetchError.hpp` — `PriceFetchFailure{code, httpStatus}` — **extended by this phase** per D-14
- `SuperGenius/src/coinprices/PriceRetryPolicy.hpp/.cpp` — `RetryConfig`, `IsTransient`, `IsTransientTransport`, `ShouldRetry`, `RateLimitHoldOff` (injectable clock) — **retry gating changes here** per D-14
- `SuperGenius/src/coinprices/coinprices.cpp:121-210` — legacy `getCurrentPrices`/`getCurrentPricesOnce`: the throwaway-ioc pattern (line ~133) D-02 supersedes, and the pre-existing naive cache/retry being replaced
- `SuperGenius/src/account/GeniusNode.cpp:3510-3565` — `GetCoinprice` seam + `m_tokenPriceCache`/`MIN_API_CALL_INTERVAL` — the Phase 4 cutover target this manager's surface must drop into (LPM-10); read for seam-shape fidelity, do not modify this phase

### Workstream planning
- `.planning/workstreams/tokenprice/REQUIREMENTS.md` — LPM-01..04, FRESH-01/02 (manager side), TEST-02 definitions; Out of Scope table
- `.planning/workstreams/tokenprice/ROADMAP.md` — Phase 3 goal, 4 success criteria, plan seeds 03-01..03-04
- `.planning/workstreams/tokenprice/phases/02-c-price-http-client-quote-surface/02-CONTEXT.md` — Phase 2 decisions D-01..D-16 this phase inherits (esp. D-09 caller-ioc, D-11..D-13 retry/hold-off, D-14/D-16 timestamp/bands)
- `.planning/workstreams/tokenprice/phases/02-c-price-http-client-quote-surface/02-VERIFICATION.md` — gap #3 (retry-classification coarseness: facade maps every transport failure to `{NetworkError,0}` before `ShouldRetry`) — the precise problem D-14 fixes; also gap #2 (run()/restart() landmine) motivating D-02's dedicated thread
- `.planning/workstreams/tokenprice/phases/01-token-gnus-ai-worker-service/01-CONTEXT.md` — envelope contract decisions D-06..D-09/D-11/D-12 (source semantics, partial coverage, per-id fetchedAt) the token.gnus.ai tier consumes

### Design reference & research
- `.planning/research/pricing_coordinator.md` — the hybrid design reference: device-side manager vs. server-side coordinator split, fallback chain rationale
- `.planning/workstreams/tokenprice/research/ARCHITECTURE.md` — system overview (its transport-component sketch is superseded by Phase 2 D-01)
- `/memories/repo/coingecko-price-api-frontend.md` — motivating diagnosis (403 path-scoped WAF, minutes-scale 429, no rate-limit headers)

### Phase 1 worker (contract source for fixtures per D-16)
- `SuperGenius/pricecoordinator/` — the worker + DO implementation and tests; the envelope test output the C++ fake fixtures replay

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PriceHttpClient` (Phase 2) — implements the CoinGecko tier today; wraps `sgns::HTTPClient` (AsyncIOManager) with status gate, UA, 5s timeouts, retry + hold-off. The token.gnus.ai tier is a second instance with a different base URL — but note it must parse the **envelope** format, not CoinGecko's `/simple/price` format; the facade's parse layer is where the two tiers differ (planner decides: parameterize the facade or thin adapters over `IPriceSource`)
- `PriceQuote`/`PriceFreshness`/`PriceRetryPolicy` — complete and tested (34 gtest cases, 3 suites); this phase consumes them unchanged except D-14's classification extension
- `HttpStubServer` (`SuperGenius/test/testutil/http_stub/`) — NOT used in Phase 3 unit tests (zero sockets), but stays available for Phase 4 integration tests
- `base::Logger` pattern (`sgns::base::createLogger`) — used by `PriceHttpClient`; the manager follows it

### Established Patterns
- Strand-serialized state over a dedicated ioc+thread — standard Boost.Asio; no in-tree precedent at this granularity, but the AsyncIOManager `HTTPClient` async-chain pattern (Phase 2 P-1/P-2 in 02-PATTERNS.md) is the house style for asio callbacks
- `outcome::result`-typed fallible surfaces; `PriceResult<T>` alias with `terminate` policy (non-error_code error type)
- Test suites under `SuperGenius/test/src/<suite>/` with `addtest()` ctest registration (see `test/src/price_retrieval/CMakeLists.txt`, `price_facade_test` from Phase 2)
- Injectable clock pattern (`RateLimitHoldOff::Clock`) — extend the same idea to the 50ms window and L1 timestamps for deterministic tests

### Integration Points
- Phase 4 consumes: `LocalPriceManager::GetQuotes` drops into `GeniusNode::GetCoinprice` (LPM-09/LPM-10 — endpoint config fields should be constructor parameters so Phase 4 can wire env/config)
- The two-tier `IPriceSource` wiring: production = `PriceHttpClient` instances (CoinGecko base URL default `https://api.coingecko.com`, token.gnus.ai base URL default `https://token.gnus.ai`); tests = fakes (D-13)
- Freshness bands feed both L1 service decisions (LPM-01) and fallback escalation (D-09/D-10) — single source of truth in `PriceFreshness.hpp`

</code_context>

<specifics>
## Specific Ideas

- User's exact framing on the executor: "when constructing a PriceHttpClient we could pass an ioc to it and have it use that" — adopted (D-02), completed with one runner thread after the analysis showed a shared ioc without an owner cannot coalesce safely (run()/restart() tail-coupling — Phase 2 verification gap #2).
- User's definitional anchor for the manager: it is the device-side counterpart of the Worker's server-side `PriceCoordinator` — same single-flight idea, two scopes. Do not conflate them in naming or docs (D-15).
- User's test-coverage concern: Phase 1's worker tests run the real pricecoordinator in workerd (mocked upstream, zero sockets); Phase 2's C++ tests use real loopback sockets; Phase 3's manager tests are pure fakes. The only cross-tier contract check is D-16's captured-envelope replay — keep those fixtures byte-real.

</specifics>

<deferred>
## Deferred Ideas

- **Live end-to-end test** — real `wrangler dev` worker + C++ manager over loopback HTTP, asserting the full wire path (envelope → transport → manager → quote). New capability, needs Node toolchain inside the C++ test environment — its own phase; candidate for a future milestone after Phase 5.
- **Second hold-off timer for the token.gnus.ai tier** — only if abuse/429s from the shared tier are ever observed (D-12 documents the v1 stance: none).
- **Async (callback/future) `GetQuotes` variant** — D-01 locks blocking-only; revisit when a real async consumer exists.
- Carried forward unchanged from Phase 1's deferred section: the aarch64-Debug `GTEST_FILTER` exclusion removal requires the MNN/Vulkan thirdparty rebuild rider — re-scope Phase 5's plan 05-02 and TEST-04's exclusion-removal clause when Phase 5 is planned.

</deferred>

---

*Phase: 3-Local Price Manager*
*Context gathered: 2026-10-01*
