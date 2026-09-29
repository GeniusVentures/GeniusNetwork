# Feature Research

**Domain:** Resilient crypto token-price service — device-side Local Price Manager (C++, SuperGenius) + shared-cache/coalescing fallback Worker (token.gnus.ai, Cloudflare Worker + SQLite Durable Object)
**Researched:** 2026-09-29
**Confidence:** HIGH for grounding (every table-stakes item traces to the 2026-09-29 diagnosis, the design reference, or a workspace source read) · MEDIUM for external-domain claims (Chainlink/SWR/CoinGecko-pro behavior is public-reference knowledge, not re-verified this pass)

Scope note for the roadmapper: this milestone adds **two codebases + shared test infrastructure**. Features below are tagged **[C]** = C++ Local Price Manager, **[W]** = Worker/DO service, **[X]** = cross-cutting/testing. The seam is fixed: `GetProcessCost` → `GeniusNode::GetGNUSPrice` → `GetCoinprice` (`GeniusNode.cpp:3510`) must keep returning `outcome::result<...>`; the manager replaces the stack-constructed `CoinGeckoPriceRetriever` behind that seam.

---

## Feature Landscape

### Table Stakes (Users Expect These)

For this milestone "users" are (a) `GetProcessCost`/wallet callers who must never see a hard failure or a silently-wrong price, and (b) GNUS node operators whose devices must not get rate-limited into uselessness. Missing any of these means the motivating bug (hard-fail / misleading `JSON Parse Error: 3` when CoinGecko 403s) survives in some form.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| [C] Truthful HTTP status handling — typed errors for 403/429/5xx/timeout, never feed HTML to the JSON parser | Diagnosis bug #1: today `FileManager::LoadASync` returns the body regardless of status, so a CloudFront 403 HTML page becomes `JSON Parse Error: 3` in logs; callers cannot distinguish "blocked" from "broken" | LOW | New scoped Beast client (Beast already linked in `price_retrieval_test` on all 5 platforms). Do NOT extend `FileManager::LoadASync` — ripples into MNN/IPFS/SFTP loaders (STACK.md decision). Map status → existing-style error codes + real status in the log line |
| [C] Retry only transient transport errors; never retry 403/429 | Diagnosis bug #3: the current 3×250/500ms loop re-triggers CoinGecko's minutes-scale 429 limiter; 403 is path-scoped WAF, retrying is pure waste | LOW | On 429/403: fall through to next tier *immediately* (no sleep). On timeout/connect-error: bounded backoff, minutes-scale or delegate to scheduled refetch |
| [C] No blocking sleeps in the caller path | `std::this_thread::sleep_for` (current code) blocks the node caller and hammers the limiter | LOW | `steady_timer`-based async backoff or drop-retry-and-fallthrough; `GetCoinprice` seam stays non-blocking |
| [C] `User-Agent` + sane headers on outbound requests | Diagnosis bug #2 (harmless today, fragile); a bare GET from a custom Beast client looks exactly like a scraper | LOW | Configurable UA string, default honest product token (`GeniusNode/<version>`) — not a browser spoof |
| [C] Multi-id batching — one `/simple/price` call for all pending ids | CoinGecko natively supports `ids=a,b,c`; per-token requests are the #1 waste multiplier (design ref: order-of-magnitude reduction) | LOW | Today's retriever already joins ids; preserve it, but batch *across* coalesced waiters too |
| [C] L1 in-memory cache, 60s freshness | CoinGecko public data itself updates ~every 60s — caching shorter buys nothing; `GetProcessCost` is cost *estimation*, not settlement | LOW-MEDIUM | A naive version already exists (`m_tokenPriceCache` + `m_cacheValidityDuration` in `GeniusNode`) but is per-node, timestamp-less, and duplicated; consolidate ONE authoritative cache in the manager with per-quote `fetchedAt` |
| [C] Request coalescing / single-flight (~25–100ms window) | Concurrent requests for the same tokens (multi-subtask processing bursts) must become one upstream call; design ref: ~50ms window | MEDIUM | `std::mutex` + `condition_variable` (or one dedicated `io_context` thread). Waiters get the same result; N waiters → 1 request. Needs injectable clock for deterministic tests |
| [C] Fallback chain: L1 fresh → CoinGecko direct (batched) → token.gnus.ai → last-known-good → error | The whole point: `GetGNUSPrice` must never hard-fail while any tier has data; anonymous direct access is being squeezed to zero (diagnosis: deprecation-by-attrition) | MEDIUM | Each hop triggered by typed failure (429/403/timeout), never by retrying the same tier. Last-known-good is in-memory (process lifetime) for v1 |
| [C] Stale-serving within a freshness band (0–60s fresh / 60s–5min stale-but-usable / >5min unavailable) | Price retrieval "doesn't need to fail because the quote is 61 seconds old" (design ref); today expired entries are silently *dropped*, so a 61s-old price is treated as no price | MEDIUM | Requires per-quote timestamps + `stale`/`source` carried through the seam. Band constants live in ONE place shared by policy checks (client) and envelope (server) |
| [C] Configurable price endpoints (base URLs via config/env) | Hermetic tests need `http://127.0.0.1:<port>/`; also the pre-req for fixing `account_management_test.SetPayoutAddress` (currently live-internet dependent, CI-excluded on aarch64-Debug at `cmake.yml:649`) | LOW | Default `https://api.coingecko.com` + `https://token.gnus.ai`; override via `GeniusNodeConfig` field or env var consumed by the test fixture |
| [C] Caller-visible timeouts (connect+handshake+read ≈ 5s total) | Today's HTTPDevice uses 10/10/30s — a fallback chain that takes 40s to fail is not a fallback | LOW | `beast::tcp_stream::expires_after`; per-tier timeout budget so worst-case total is bounded (~10–12s across both tiers) |
| [C] Client-side request budget (self-imposed min interval between upstream calls) | CoinGecko sends **no** `x-ratelimit-*`/`Retry-After` headers (empirical, diagnosis) — callers fly blind; must assume the worst advertised keyless limits | LOW-MEDIUM | Generalizes today's `MIN_API_CALL_INTERVAL` into the manager; conservative default (≤1 direct call/60s per currency-pair set), configurable |
| [W] `GET /v1/prices?ids=...&vs=usd` with input validation | Any public price API must reject empty ids, oversized id lists, malformed input — with a structured error, not a 500 | LOW | Cap ids per request (e.g. ≤50), whitelist charset, cap total URL length. Structured JSON errors (`{"error": {...}}`) on every failure path |
| [W] Response envelope: `currency / prices / fetchedAt / age / source / stale` | Clients need to make freshness policy decisions without trusting their own clock vs. the server's; bare `{id: price}` maps (raw CoinGecko shape) can't express staleness or origin | LOW | The design ref specifies this exact shape; it is the contract both sides pin with golden-fixture tests |
| [W] Durable Object single-flight coalescing across clients | THE reason the DO exists: clients A/B/C wanting overlapping id sets within the window → exactly one CoinGecko call, each gets their subset — "queue-like behavior without an async Queue" (design ref) | MEDIUM | `PriceCoordinator:USD` via `idFromName`; SQLite-backed (`new_sqlite_classes` — KV-backed DOs are paid-only). In-flight promise dedupe + pending-id merge |
| [W] Shared cache in front of the DO (`caches.default` + `Cache-Control`) | Warm colos answer without touching the DO at all; free tier, per-colo warming is fine for prices | LOW | `cache.put` with ~45s TTL (below the 60s freshness band so a cache HIT is still "fresh"). KV is rejected (1,000 writes/day free) |
| [W] Serve-stale from DO storage when upstream fails (envelope `stale:true`, `source:"coingecko-cache"`) | If CoinGecko 403s/429s the Worker's egress too (its IPs are datacenter IPs — same WAF risk as CI runners), the fallback tier must still answer | MEDIUM | Last-known-good per id persisted in DO SQL with `fetchedAt`; serves within the stale band (≤5min), errors past it |
| [W] Optional server-side upstream key (wrangler secret), never in the client | Keyless anonymous access is being squeezed to zero; the Worker is the ONLY place a key can live safely. Note: without a key, the Worker's own CoinGecko fetches share the same anonymous-WAF risk as any client — the key is what makes the fallback tier robust | LOW | `COINGECKO_API_KEY` secret, header `x-cg-demo-api-key` when present. Keyless default for v1 (code + tests only), keyed-ready |
| [W] Truthful upstream status handling in the Worker (don't wrap a 403 HTML page in a 200) | Same bug class as client bug #1, server-side: pass through structured 502/503-with-reason, or serve stale | LOW | Never emit a 200 whose body is upstream error noise; the client's fallback logic keys off *our* status codes |
| [W] Hermetic Worker tests (in-runtime vitest, mocked upstream fetch) | Network-dependent tests are exactly the disease being cured; CI runners' egress IPs are near-permanently WAF-blocked (diagnosis) | MEDIUM | `@cloudflare/vitest-plugin` (replaced `vitest-pool-workers`, Aug 2026), declarative outbound-fetch mocking, `SELF` fetch; assert upstream call *counts* to prove coalescing (STACK.md) |
| [X] Hermetic C++ tests: injectable `PriceHttpClient` interface + fake | Cache hits, freshness bands, coalescing dedupe, fallback order, retry policy must all be assertable with zero sockets | MEDIUM | One seam interface; GTest fakes return canned envelopes incl. 403-HTML, 429, timeout. All I/O goes through it — this is the feature that makes everything else testable |
| [X] Stub HTTP server fixture (plain-HTTP Beast listener on 127.0.0.1:0) | True end-to-end behavior (real status codes, real parse) without internet | MEDIUM | Scriptable status/body per path; ~100 lines, in-test-binary. Plain HTTP avoids TLS machinery; client takes a full base URL so production stays HTTPS |
| [X] Replace live-network `price_retrieval_test` with hermetic equivalents | The current suite hits live CoinGecko and is deliberately NOT registered with CTest (`CMakeLists.txt:2` — "build it, but do not register") — i.e., today there is effectively no CI coverage of price retrieval | MEDIUM | Keep one opt-in live smoke test (manual target), register the hermetic suite with CTest |

### Differentiators (Competitive Advantage)

These are what make the system *good* rather than merely *not-broken*. They align with the workstream's Core Value: price-dependent paths never hard-fail, and the architecture stays provider-independent.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| [W+C] Envelope metadata design (`age` computed server-side, `source`, `stale`) | Client freshness policy without clock-sync games: the server stamps `fetchedAt`/`age`, the client decides with its *own* clock only for its local cache. This is the Chainlink-oracle pattern (answer + `updatedAt` + deviation/heartbeat bounds) brought to an HTTP price API | LOW | Design ref specifies the shape; the differentiator is *enforcing* it as the only contract both sides consume (golden JSON fixture shared by TS and C++ test trees) |
| [X] Freshness-band policy as a single shared constant set (0–60s / 60s–5min / >5min) | One policy, two enforcement points, no drift: Worker TTL (45s cache) < fresh band (60s) < client stale ceiling (5min). Drift between tiers = subtle mispricing bugs | MEDIUM | Ship as a tiny shared spec (JSON/constants documented in the contract fixture); cross-tier consistency test asserts Worker TTL < client fresh band |
| [C] Keyless-client architecture (provably no key material in shipped binaries) | Public executable/mobile keys aren't secrets; keeping devices keyless preserves the distributed-IP property that motivated the hybrid design AND removes a key-rotation/leak surface across 5 platforms | LOW | Mostly constraint + guard test: assert no key-like config fields exist in the client config schema; keys only ever in Worker secrets |
| [C] Provider-independent quote surface — `PriceQuote { asset, currency, price, timestamp, source, stale }`, `enum class PriceSource { LocalCache, CoinGecko, GnusPriceService, OnChain }` | Adding the deferred on-chain/oracle source later becomes a new enum value, not an API break; callers (incl. `GetGNUSPrice`) can log/decide on provenance. Avoids CoinGecko's id-map shape leaking into GeniusNode | LOW-MEDIUM | `OnChain` declared-but-unimplemented this milestone (reserved value only). Note today's seam returns a bare `map<string,double>` — enriching the *internal* return while keeping the public seam stable is the design task |
| [W] Per-currency DO naming (`PriceCoordinator:USD`) | Multi-currency (`vs=eur,...`) later is a new DO instance, not a redesign; per-currency failure isolation | LOW | `idFromName(vs-currency)` from day one even though only USD is exercised |
| [W] Cache pre-warm via DO alarm / cron trigger | A *cold* fallback tier answering its first request after an outage must still fetch from CoinGecko — pre-warming keeps last-known-good young so serve-stale windows are maximal exactly when direct access is failing fleet-wide | MEDIUM | DO `alarm()` refetch every ~45–60s while any traffic has been seen; hermetic-testable with clock injection. Strong v1.x candidate |
| [W] Debug/observability headers on Worker responses (`X-Price-Cache: HIT\|MISS`, `X-Coalesced: n`) | Diagnosing "why is my price stale" from client logs alone is guesswork; one header turns it into a fact. Cheap, no PII | LOW | Also structured `console.log` lines with upstream status + call counts (visible in `wrangler tail`) |
| [C] Observability at the seam: log tier, source, age on every `GetCoinprice` resolution | Node operators need to see "served LocalCache, age 41s" vs "fell back to token.gnus.ai, stale" in existing spdlog output — today logs actively *lie* (`JSON Parse Error: 3` during a 403) | LOW | One structured log line per resolution; rate-limited to avoid spam on hot paths |
| [X] Clock-injection seams in both codebases | Freshness/coalescing/TTL logic is all time-based; without injectable clocks the tests either sleep (slow, flaky) or don't cover the interesting transitions (60s boundary, 5min boundary, 50ms window) | MEDIUM | C++: injectable `std::function<time_point()>` / test clock; TS: `vi.useFakeTimers` + DO alarm seams. This is the difference between "tested the happy path" and "tested the bands" |
| [C] Honest partial-result semantics at the seam | Today `GetCoinprice` silently returns a *subset* when some ids' cache is expired and the fetch fails or the min-interval hasn't elapsed — callers can't tell missing-from-unavailable. Quote metadata makes partialness visible | LOW-MEDIUM | With `PriceQuote` (per-id source/age), missing ids are explicitly absent rather than ambiguously absent; `GetGNUSPrice`'s existing finite/positive check stays |
| [W] Multi-provider upstream in the Worker (CoinGecko primary; CryptoCompare/Binance-public secondary) | A single upstream means the fallback tier inherits every CoinGecko outage/WAF policy; a second keyless source makes the Worker genuinely resilient, and it's the natural home for provider arbitration | HIGH | Deferred beyond v1.0 (design ref: "eventually other price sources"). Envelope `source` field already reserves room for it |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| [W] Cloudflare Queues in the price path ("cache and queue") | Queues *sound* like the right coalescing primitive | Free tier ≈10k ops/day, ~3 ops per delivered message → ≈3,333 messages/day; billed per message even batched; async Queue behind a synchronous API request is an impedance mismatch (design ref, explicit) | DO single-flight: same coalescing, synchronous, ~free at expected volume |
| [W] Workers KV for the hot price cache | KV is the obvious Cloudflare cache | 1,000 writes/day free vs. a 60s-update workload (1,440 writes/day/id minimum) — exhausted by a single asset | `caches.default` (per-colo, free) + DO SQL for last-known-good |
| [W] Making token.gnus.ai the *primary* client path ("one clean API for everyone") | Simpler client, one place to control | Collapses thousands of device IPs into one rate-limit domain and one budget: 10k devices × 1 req/min = 14.4M/day vs. 100k/day free — three orders of magnitude over; also a centralization point the design explicitly rejects | Direct-first hybrid: ~98% served locally/direct; Worker sees only the ~2% failure tail (tens of thousands/day — fits free tier) |
| [C] Embedding a CoinGecko API key in the C++ client / GeniusSDK binary | "Then we won't get 429'd" | A key in a public binary/mobile app is not a secret — it will be extracted, shared, and burned; also un-ratelimitable per device | Keyless client; key (if any) lives only in the Worker as a server-side secret |
| [C] Over-fresh polling (TTL < 60s, or refetch per `GetProcessCost` call) | "Prices change fast" | CoinGecko public data updates ~60s — polling faster buys stale-identical data while spending rate budget; `GetProcessCost` is estimation, not settlement | 60s fresh band; 60s–5min stale-but-usable; the use-site tolerates (and is *told* it got) stale data |
| [C] Retrying 403/429 with short backoff (status quo) | "Retry until it works" | 429 cooldown is minutes-scale and header-less; 250–500ms retries re-trigger it; 403 is WAF path-scoped — retries are 100% waste (diagnosis bug #3) | Never retry 403/429 — fall through tiers immediately; bounded backoff only on transient transport errors |
| [C+W] Relying on `x-ratelimit-*` / `Retry-After` from CoinGecko | "Standard API convention" | Empirically absent on the anonymous tier (probed 2026-09-29: no such headers on 200/403/429) — code keyed on them silently degrades to no throttling at all | Self-imposed conservative client budget + freshness bands; if headers ever appear, treat as bonus signal only |
| [C] Extending `FileManager::LoadASync` to surface status/headers | "Fix the bug where it lives" | Every MNN/IPFS/SFTP loader shares that path; changing its return contract ripples across the codebase for one consumer | Scoped ~200-line Beast client inside `coinprices`; revisit a shared client only when a second subsystem needs it |
| [C] Single-provider lock-in baked into the client API (returning CoinGecko's raw id→map, no source/age) | "Simplest interface" | Adding the deferred on-chain/oracle source later becomes a breaking change at the `GetCoinprice` seam; provenance/staleness unverifiable by callers | `PriceQuote` surface with `source`/`stale` from day one; `OnChain` reserved |
| [C] Multiple uncoordinated cache layers (today: `GeniusNode::m_tokenPriceCache` AND the retriever's retry loop AND `MIN_API_CALL_INTERVAL`, each half-aware of the others) | Each layer "helps" | Split-brain freshness, silent partial results, min-interval gate silently dropping expired ids (real behavior at `GeniusNode.cpp:3532-3556`); bugs hide in the gaps | ONE authoritative L1 cache in the Local Price Manager; `GeniusNode` delegates and stops owning price state |
| [W+C] Serving stale data without flagging it (bare map, `stale` omitted) | "Caller doesn't care" | Misprices cost estimates *silently* — worse than failing, because nobody investigates; makes the freshness bands decorative | `stale`/`age`/`source` always present in envelope and quotes; honest logging at the seam |
| [W] Unbounded coalescing window / unbounded batch size | "Coalesce harder" | Window grows → every request pays the window as latency; giant id lists can trip upstream limits and amplify one bad response to all waiters | 25–100ms window cap (design ref: ~50ms); cap ids per request (≤50); split oversized batches |
| [X] `wrangler deploy` in CI | "Ship it automatically" | Deployment is explicitly out of scope this milestone (code + tests only); auto-deploy of an unreviewed price oracle path is a production-risk footgun | Manual deploy later; CI runs typecheck + vitest only |
| [X] Live-internet tests in CI (status quo for `price_retrieval_test`, and `SetPayoutAddress` today) | "Tests the real thing" | CI runner egress IPs are near-permanently WAF-blocked on `/simple/price` (diagnosis — this is *why* those tests fail/excluded); results are flaky-by-environment, proving nothing | Hermetic fakes/stub server as the gate; one opt-in live smoke target for manual runs |

## Feature Dependencies

```
[C] Truthful HTTP status handling
    └──requires──> [C] Scoped Beast client (in-tree Boost.Beast, timeouts, UA)
                        └──requires──> (nothing new — Boost/rapidjson/OpenSSL already built by thirdparty)

[C] Fallback chain (L1 -> CG direct -> token.gnus.ai -> last-known-good)
    └──requires──> [C] Truthful status handling        (can't *trigger* fallback without typed 403/429/timeout)
    └──requires──> [C] L1 cache + per-quote timestamps (fresh-check precedes any network)
    └──requires──> [W] Envelope contract               (client parses Worker responses)
                          └──requires──> [W] /v1/prices endpoint + validation

[C] L1 cache + stale-serving bands
    └──requires──> [C] Provider-independent PriceQuote surface (timestamp/source/stale fields are where the band decision lives)
    └──requires──> [X] Clock injection                 (boundary tests: 60s / 5min)

[C] Request coalescing (single-flight, ~50ms)
    └──requires──> [C] Multi-id batching               (waiters' id sets merge into ONE /simple/price call)
    └──requires──> [X] Clock injection                 (deterministic window tests)

[W] DO single-flight coalescing
    └──requires──> SQLite-backed DO migration (`new_sqlite_classes`; KV-backed = paid-only)
[W] Serve-stale from DO
    └──requires──> [W] DO single-flight                (same object owns last-known-good state)
    └──enhances──> [C] Fallback chain                  (Worker answers even when ITS upstream is blocked)
[W] Cache pre-warm (DO alarm)  ──enhances──> [W] Serve-stale   (younger last-known-good = longer stale windows)

[X] Hermetic SetPayoutAddress fix + CI-exclusion removal (cmake.yml:649)
    └──requires──> [C] Configurable endpoints          (test points at stub server)
    └──requires──> [X] Stub HTTP server fixture

[X] Stub server E2E          ──enhances──> [W] Envelope contract  (real bytes both ways, zero internet)
[X] Golden envelope fixture  ──enhances──> [W+C] Envelope contract (same fixture in vitest AND GTest trees pins the schema)

[C] Keyless-client guarantee ──conflicts──> any temptation toward [C] embedded API key (anti-feature)
[W] Direct-first hybrid      ──conflicts──> [W] Worker-as-primary  (mutually exclusive traffic models)
[C] One authoritative L1     ──conflicts──> retaining GeniusNode::m_tokenPriceCache as a second cache (must delegate or delete)
```

### Dependency Notes

- **Fallback chain requires truthful status first:** the entire chain is *driven by* typed failure codes. If 403 still arrives as a parse error, the chain can't distinguish "fall through" from "give up". This dictates phase ordering: client transport fix precedes (or ships with) chain logic.
- **Envelope contract is the join point between the two codebases:** Worker can be built and hermetically tested first only if the golden fixture is defined in the same phase; otherwise the C++ parser is written against a moving target.
- **Hermetic test fix unlocks the CI win:** removing the aarch64-Debug `GTEST_FILTER` exclusion is only legitimate after `SetPayoutAddress` provably never touches the internet — which requires configurable endpoints + stub server.
- **`GeniusNode` cache delegation is mandatory, not optional:** leaving `m_tokenPriceCache` in place creates the exact split-brain anti-feature the manager exists to remove.
- **DO single-flight and serve-stale share state:** last-known-good lives in the same DO as the in-flight map; splitting them across storage (e.g., last-known-good in KV) reintroduces the rejected KV write-cap problem.

## MVP Definition

### Launch With (v1)

MVP = the motivating failure mode is dead: `GetProcessCost` → `GetGNUSPrice` cannot hard-fail while any tier has data, logs tell the truth, and every test runs without internet. Worker is code + tests only (no deployment).

- [ ] [C] Scoped Beast HTTP client with truthful status handling, UA, ~5s timeout budget — kills diagnosis bugs #1/#2 at the root
- [ ] [C] Retry policy: transient-only, bounded backoff, immediate fallthrough on 403/429 — kills diagnosis bug #3
- [ ] [C] L1 cache (60s fresh band) with per-quote timestamps, replacing `GeniusNode`'s duplicated cache
- [ ] [C] Request coalescing (~50ms window) + multi-id batching — the traffic-multiplier fix
- [ ] [C] Fallback chain L1 → CoinGecko direct → token.gnus.ai → last-known-good (in-memory) → typed error
- [ ] [C] Freshness bands 0–60s / 60s–5min stale-usable / >5min unavailable, enforced client-side
- [ ] [C] Provider-independent `PriceQuote` + `PriceSource` (OnChain reserved) behind the unchanged `GetCoinprice` seam
- [ ] [C] Configurable base URLs (default CoinGecko + token.gnus.ai; test override to stub)
- [ ] [W] `/v1/prices` endpoint: validation, structured errors, envelope (`currency/prices/fetchedAt/age/source/stale`)
- [ ] [W] SQLite DO single-flight coalescing (`PriceCoordinator:USD`) + `caches.default` front cache (~45s TTL)
- [ ] [W] Serve-stale from DO last-known-good within the band; truthful upstream status handling; optional server-side key via secret
- [ ] [X] Golden envelope fixture shared by both test trees
- [ ] [X] Hermetic C++ unit tests (injectable client + fake: 403-HTML/429/timeout/band boundaries/coalescing dedupe/fallback order) + stub-server E2E, registered with CTest; live smoke test demoted to opt-in
- [ ] [X] Hermetic Worker tests (vitest-plugin, mocked upstream, coalescing proven by call-count) + `tsc --noEmit` gate
- [ ] [X] Hermetic `SetPayoutAddress` + removal of the aarch64-Debug CI exclusion

### Add After Validation (v1.x)

- [ ] [W] Cache pre-warm via DO alarm — trigger: observed cold-start stale windows in practice
- [ ] [W] Debug headers (`X-Price-Cache`, `X-Coalesced`) + structured tail-able logs — trigger: first field diagnosis session
- [ ] [C] Client budget tuning from fleet telemetry — trigger: real 429-frequency data post-rollout
- [ ] [W] Live deployment of token.gnus.ai — trigger: v1 code reviewed + envelope contract stable (explicitly out of v1 scope)
- [ ] [X] Full-stack local E2E in CI (wrangler dev + C++ client) — trigger: if stub-server E2E leaves contract gaps

### Future Consideration (v2+)

- [ ] [C] On-chain/DEX oracle as a `PriceSource::OnChain` implementation — deferred by milestone definition; the quote surface reserves room
- [ ] [W] Multi-provider upstream arbitration (CryptoCompare/Binance-public secondary) — defer until single-upstream failure rates are known; HIGH complexity (cross-provider id normalization)
- [ ] [C+W] Multi-currency (`vs` beyond USD) — per-currency DO naming already reserves room; no consumer today
- [ ] [C] Historical price path (`GetCoinPriceByDate`/`ByDateRange`) migration to the new client + caching — different CoinGecko endpoints, different caching economics (immutable-by-date answers cache far longer); no current failure report forcing it
- [ ] [C] Persistent (disk) last-known-good across node restarts — only matters if outages + restarts correlate in practice

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| [C] Truthful status handling | HIGH | LOW | P1 |
| [C] Transient-only retry + no blocking sleeps | HIGH | LOW | P1 |
| [C] L1 cache + freshness bands | HIGH | MEDIUM | P1 |
| [C] Coalescing + batching | HIGH | MEDIUM | P1 |
| [C] Fallback chain incl. last-known-good | HIGH | MEDIUM | P1 |
| [C] `PriceQuote`/`PriceSource` surface | HIGH | LOW-MEDIUM | P1 |
| [C] Configurable endpoints | HIGH | LOW | P1 |
| [W] `/v1/prices` + envelope + validation | HIGH | LOW | P1 |
| [W] DO single-flight + caches.default | HIGH | MEDIUM | P1 |
| [W] Serve-stale + truthful upstream handling + optional secret key | HIGH | MEDIUM | P1 |
| [X] Hermetic tests both sides + golden fixture | HIGH | MEDIUM | P1 |
| [X] SetPayoutAddress hermetic + CI-exclusion removal | MEDIUM | LOW | P1 |
| [X] Clock-injection seams | MEDIUM | MEDIUM | P1 (test-infra; without it the P1 band tests don't exist) |
| [W] Debug headers + structured logs | MEDIUM | LOW | P2 |
| [C] Seam observability (tier/source/age log line) | MEDIUM | LOW | P2 |
| [W] DO alarm pre-warm | MEDIUM | MEDIUM | P2 |
| [W] Per-currency DO naming (USD-only exercised) | LOW | LOW | P1 (design-time choice, zero marginal cost) |
| [W] Multi-provider upstream | HIGH | HIGH | P3 |
| [C] On-chain source implementation | HIGH | HIGH | P3 (reserved enum value in v1) |
| [C] Historical path migration | MEDIUM | MEDIUM | P3 |
| [C] Persistent last-known-good | LOW | MEDIUM | P3 |

**Priority key:**
- P1: Must have for launch
- P2: Should have, add when possible
- P3: Nice to have, future consideration

## Competitor Feature Analysis

Reference architectures for this domain (public behavior, not re-verified this pass — MEDIUM confidence on external columns):

| Feature | CoinGecko (paid/keyed tier) | Chainlink price feeds | SWR / stale-while-revalidate HTTP pattern | Our Approach |
|---------|------------------------------|------------------------|-------------------------------------------|--------------|
| Staleness signaling | Rate-limit + status codes; body carries data only | `updatedAt` per answer + heartbeat/deviation-threshold bounds — the gold standard for "old answer vs no answer" | `Age`/`X-SWR` headers; serve stale then revalidate | Envelope `fetchedAt`/`age`/`stale` + freshness bands — Chainlink-style explicitness at HTTP level, enforced identically both tiers |
| Coalescing | N/A (upstream) | N/A (push model) | Single-flight in cache layers (dedupe in-flight revalidation) | DO single-flight server-side + ~50ms window client-side — same pattern at both tiers |
| Fallback/multi-source | N/A (is the source) | Decentralized oracles, aggregation on-chain | Origin failover at CDN/edge | L1 → direct → token.gnus.ai → last-known-good; multi-provider upstream deferred (v2+) |
| Caching | Upstream-side | N/A | Core feature (RFC 5861) | 60s client L1; 45s edge cache; DO last-known-good — TTLs derived from the source's own ~60s update cadence |
| Keyless clients | Moving away from it (free → keyed attrition, per diagnosis) | N/A (on-chain reads) | N/A | Keyless clients by design; key (if any) server-side only in the Worker |
| Cost model | Per-call pricing | Per-update gas | Free (HTTP semantics) | Cloudflare free tier sized by the ~2%-fallback traffic model (100k Worker req/day, 100k DO req/day) |

## Sources

- Design reference: `.planning/research/pricing_coordinator.md` — hybrid architecture, freshness bands, envelope shape, DO-vs-Queues/KV free-tier math, keyless-client mandate
- Diagnosis: `/memories/repo/coingecko-price-api-frontend.md` + live probes 2026-09-29 — path-scoped 403 WAF block, header-less minutes-scale 429, the three client bugs, CI-runner IP blocking
- Stack research: `.planning/workstreams/tokenprice/research/STACK.md` — verified toolchain pins (vitest-plugin, vitest 4.x, SQLite DO), Beast-in-tree evidence, TLS/CA-bundle plan, CI integration shape
- Workspace source (read this pass): `SuperGenius/src/coinprices/coinprices.{hpp,cpp}` (retry loop, status swallowing, chunked-decode hack), `SuperGenius/src/account/GeniusNode.cpp:3509-3560` (`GetCoinprice` cache/throttle/silent-partial behavior), `SuperGenius/test/src/price_retrieval/` (live-network tests, unregistered with CTest), `GeniusNode.cpp:3570-3585` (uncached historical paths)
- Project context: `.planning/PROJECT.md` (tokenprice workstream target features)
- External domain references (public knowledge, not re-verified): Chainlink price-feed staleness model (updatedAt/heartbeat/deviation), RFC 5861 stale-while-revalidate, CoinGecko pricing/docs pages for keyed tiers

---
*Feature research for: PriceCoordinator — Local Manager + token.gnus.ai Fallback (workstream: tokenprice)*
*Researched: 2026-09-29*
