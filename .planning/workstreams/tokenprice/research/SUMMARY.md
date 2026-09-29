# Project Research Summary

**Project:** PriceCoordinator — Local Manager + token.gnus.ai Fallback (workstream: tokenprice, milestone v1.0)
**Domain:** Hybrid token-price service — C++ Local Price Manager inside SuperGenius + TypeScript Cloudflare Worker (SQLite Durable Object) fallback tier
**Researched:** 2026-09-29
**Confidence:** HIGH — all four dimensions grounded in the 2026-09-29 live CoinGecko diagnosis (`/memories/repo/coingecko-price-api-frontend.md`), verified workspace source reads (files/lines cited in each dimension file), and registry-verified toolchain pins; MEDIUM only on external-domain claims (Chainlink/SWR/CoinGecko-pro behavior) and the Node.js engine floor

## Executive Summary

The motivating failure is fully diagnosed: CoinGecko's anonymous `/simple/price` endpoint applies a path-scoped 403 CloudFront/WAF IP-reputation block (while `/ping` and `/coins/list` return 200 from the same IP) and a header-less, minutes-scale 429 cooldown, and the current client compounds both — `FileManager::LoadASync` swallows HTTP status (a 403 HTML page becomes `JSON Parse Error: 3` in logs), there is no User-Agent, and a 3×250/500 ms `sleep_for` retry loop actively re-triggers the limiter. Upstream of all that, keyless access is being squeezed to zero by attrition. The recommended answer is a two-tier hybrid: a C++ Local Price Manager (L1 cache, ~50 ms coalescing, multi-id batching, fallback chain) replacing `CoinGeckoPriceRetriever` behind the unchanged `GetCoinprice` seam, plus a TypeScript Cloudflare Worker at `token.gnus.ai` (SQLite Durable Object single-flight + `caches.default` shared cache) that sees only the ~2% failure tail — sized to fit Cloudflare's free tier, with clients provably keyless and any upstream key living only in a server-side Worker secret.

Experts build this domain on honest staleness rather than hard freshness: a Chainlink-style envelope (`{currency, prices, fetchedAt, age, source, stale}`) with shared freshness bands (0–60 s fresh / 60 s–5 min stale-usable / >5 min unavailable), enforced identically on both tiers via a golden JSON fixture consumed by both the vitest and GTest trees. Hermetic tests are a first-class deliverable, not an afterthought — CI runner egress IPs are near-permanently blocked on `/simple/price`, so the existing live-network tests (`price_retrieval_test`, `account_management_test.SetPayoutAddress`) prove nothing and are the reason an aarch64-Debug CI exclusion exists today (`SuperGenius/.github/workflows/cmake.yml:649`). Every new test runs against an injected fake or a scriptable Beast stub server on `127.0.0.1:0`, including the exact CloudFront 403 HTML fixture captured in the diagnosis.

Key risks and mitigations: (1) retry storms re-triggering the minutes-scale limiter — mitigated by typed status handling, never retrying 403/429, and a mandatory ≥60 s self-imposed hold-off (CoinGecko sends no `Retry-After` — ever); (2) DO/Beast async lifetime and eviction traps — mitigated by self-owning `enable_shared_from_this` sessions, persisting to DO storage before responding, and alarm-driven refresh; (3) TLS verification theater — the vendored static OpenSSL has no default CA paths and Asio doesn't check hostnames by default, so the client must do all four steps (pinned in-repo `cacert.pem`, `verify_peer`, `SSL_set1_host`, SNI) on all five platforms; (4) cached-error poisoning — only 200-with-expected-shape enters any cache, with per-id presence tracking against CoinGecko's silent id omission. This milestone delivers Worker + C++ **code and tests only** — no deployment; on-chain source is deferred to v2+ behind a reserved `PriceSource::OnChain` enum value.

## Key Findings

### Recommended Stack

Worker side (`SuperGenius/tokenpriceservice/`, a self-contained sibling of `src/` invisible to CMake): wrangler `^4.144.0`, `@cloudflare/vitest-plugin` `^1.3.3` (the Aug-2026 renamed successor to `vitest-pool-workers` — never use the old package), vitest **pinned `^4.1.0`, not 5.x** (hard plugin peer range), `@cloudflare/workers-types` `^5.20260929.1`, TypeScript `~5.9.x` (7.x is too new). The DO must be SQLite-backed (`new_sqlite_classes` migration — KV-backed DOs are paid-only) and the migration list is immutable once committed. C++ side: **zero new vendored thirdparty libraries** — Boost.Beast (already linked in `price_retrieval_test` on all 5 CI platforms) for a scoped ~200-line HTTPS client with truthful status/headers/UA/timeouts; rapidjson (already `PRIVATE`-linked by `coinprices`) for envelope parsing; GTest + a plain-HTTP Beast stub-server fixture for hermetic tests. The only new asset is a pinned Mozilla `cacert.pem` (~250 KB) loaded uniformly on all platforms.

**Core technologies:**
- Boost.Beast + Asio SSL (in-tree, Boost 1.85/1.89 + vendored OpenSSL 3.x): scoped price HTTP client — solves the status-swallowing/UA/timeout defects without touching `FileManager`/`HTTPDevice` (whose consumers — MNN/IPFS/SFTP — must not change behavior)
- SQLite-backed Durable Object (`PriceCoordinator:USD` via `idFromName`): single-flight coalescing + persisted last-known-good — free-plan compatible, "queue-like behavior without an async Queue"
- `caches.default` (Cache API, ~45 s TTL): per-colo shared cache in front of the DO — free; canonical sorted-deduped ids cache keys to avoid fragmentation
- `@cloudflare/vitest-plugin` + `wrangler dev`: tests run inside the real `workerd` runtime with DO/Cache API and declarative outbound-fetch mocking — fully hermetic
- Dedicated `io_context` + one thread for the manager: price I/O never touches the node's shared 4-thread pool; synchronous facade via `std::future` with a hard total budget (~12 s worst case vs. today's ~150 s)

### Expected Features

**Must have (table stakes):** truthful typed HTTP status handling (403/429/5xx/timeout never reach the JSON parser); transient-only retry with immediate fallthrough on 403/429; no blocking sleeps; L1 cache with 60 s fresh band and per-quote timestamps; ~50 ms coalescing window + multi-id batching (one `/simple/price` call per window); fallback chain L1 → CoinGecko direct → token.gnus.ai → last-known-good (≤5 min) → typed error; configurable base URLs (env vars — hermetic tests and the `SetPayoutAddress` fix depend on it); ~5 s per-tier timeout budget; client-side rate budget. Worker: `GET /v1/prices` with input validation + structured errors; the freshness envelope; DO single-flight; edge cache; serve-stale from DO storage; optional server-side key via wrangler secret. Cross-cutting: golden envelope fixture shared by both test trees; injectable `PriceHttpClient` + fake; scriptable stub server; clock injection in both codebases.

**Should have (competitive):** freshness-band constants as a single shared spec (Worker TTL 45 s < fresh band 60 s < stale ceiling 5 min, with a cross-tier consistency test); provider-independent `PriceQuote {asset, currency, price, timestamp, source, stale}` + `PriceSource` enum (`OnChain` reserved); per-currency DO naming from day one; observability (`X-Price-Cache: HIT|MISS` headers, source/age log line at every seam resolution — today's logs actively lie); honest partial-result semantics; keyless-client guarantee (guard test asserting no key-like config in the client).

**Defer (v2+):** live deployment of token.gnus.ai (explicitly out of v1 scope); DO alarm cache pre-warm; multi-provider upstream arbitration (CoinGecko + CryptoCompare/Binance — HIGH complexity, id normalization); on-chain/DEX oracle source; multi-currency beyond USD; historical-price path migration; persistent disk last-known-good.

### Architecture Approach

Preserve the seam, replace behind it: `GetProcessCost` → `GetGNUSPrice` → `GetCoinprice` keeps exact signatures and `outcome::result` semantics (`Error::NO_PRICE` survives verbatim; zero GeniusSDK/wallet changes); only `GetCoinprice`'s body changes to delegate to a long-lived `PriceManager` (constructed once — never a per-call stack object like today's retriever, which would kill L1/LKG and re-read the CA bundle per call), and `GeniusNode`'s duplicated cache members (`m_tokenPriceCache`, `MIN_API_CALL_INTERVAL` gate) are deleted at cutover to avoid split-brain freshness. The Worker lives in a new `SuperGenius/tokenpriceservice/` directory with no CMake coupling; the envelope JSON is the *only* contract between the two codebases.

**Major components:**
1. `PriceManager` (new, `src/coinprices/`) — L1 cache, coalescing window, batching, fallback chain, last-known-good; owns a dedicated io_context + thread
2. Beast HTTPS price client (new, `src/coinprices/`) — truthful status, UA, SNI, `verify_peer` + pinned CA, total-deadline timeouts; self-owning session objects
3. `PriceQuote`/`PriceSource` (new header) — provider-independent quote surface + band classifier (monotonic-clock-based)
4. Worker `/v1/prices` + `PriceCoordinator` DO (new, `tokenpriceservice/`) — validation, edge cache, SQLite single-flight, stale-serving, optional secret key
5. Test fixtures — injectable client fake (zero sockets), scriptable Beast stub server on `127.0.0.1:0` (shared by price and account tests), hermetic vitest suite with fail-closed fetch mocks

### Critical Pitfalls

1. **Retry storms against a header-less, minutes-scale limiter** (client *and* Worker amplification) — never retry 403/429; ≥60 s self-imposed hold-off after 429; prefer DO alarm-driven refresh so requests never trigger request-time upstream fetches; never branch on `x-ratelimit-*`/`Retry-After` (empirically absent — a stub that sends them trains broken behavior)
2. **DO single-flight checked after the first `await` (double-fetch) and eviction mid-flight** — input gates only cover storage ops, not outbound `fetch`; set the pending map synchronously before any await, delete in `finally`, persist to `ctx.storage.sql` before responding, use `alarm()` not timers; test with truly concurrent `Promise.all` and assert upstream *call counts*
3. **Beast async lifetime + timeout coverage** — self-owning `enable_shared_from_this` sessions (handlers firing into freed objects = UB, MSVC-Release-only crashes); one **total** per-tier deadline (~5 s) decremented across resolve/connect/handshake/read — `expires_after` doesn't cover `async_resolve`, and per-op budgets yield 15 s+
4. **TLS verification theater** — all four steps always (pinned `cacert.pem`, `verify_peer`, `SSL_set1_host`, SNI); `set_default_verify_paths()` finds nothing with vendored static OpenSSL on Windows/macOS/mobile; chain-verify without hostname-verify accepts any CA-valid cert; missing SNI gets the wrong cert from CloudFront/Cloudflare; ship the bundle via CMake copy/install as part of the feature
5. **Cached-error poisoning and silent id omission** — only 200-with-expected-shape enters any cache (short negative-TTL for errors); track per-id presence (CoinGecko 200s silently omit unknown ids — `GNUS` vs `genius-ai` is the live example); plus the related trap: LKG must have a sanity band and an explicit hard expiry, and the `outcome::result<double>` seam erases the stale flag — log `source` + `age` on every seam call

## Implications for Roadmap

Based on research, suggested phase structure (mirrors the workstream ROADMAP's P1–P5):

### Phase 1: Worker service (`token.gnus.ai` code + hermetic tests)
**Rationale:** Independent of all C++ work; pins the envelope contract every later phase consumes; front-loads the riskiest unfamiliar toolchain (vitest-plugin, SQLite DO, `new_sqlite_classes`).
**Delivers:** `/v1/prices` endpoint (validation, structured errors), `PriceCoordinator` DO (single-flight, SQLite persistence, stale-serving), `caches.default` integration, envelope types, golden-fixture hermetic vitest suite, wrangler config-inspection test (asserts SQLite migration + no Queues/KV + no `new_classes`).
**Addresses:** [W] table-stakes block — endpoint, envelope, DO coalescing, edge cache, serve-stale, truthful upstream status, optional secret key; [X] hermetic Worker tests.
**Avoids:** Pitfalls 1–6 (post-await single-flight check, eviction, migration tags, cache no-store/key-fragmentation, test egress, DO hotspot) and 14 (error caching) server-side.

### Phase 2: C++ transport — Beast client, `PriceQuote`, stub server
**Rationale:** Parallel with Phase 1 (no hard dependency — parsing targets the documented contract); produces the injectable client interface Phase 3 fakes.
**Delivers:** Scoped Beast HTTPS client (typed status, UA, SNI, hostname-verified TLS with pinned CA bundle, total-deadline timeouts, transient-only retry classification), `PriceQuote`/`PriceSource` + band classifier, scriptable plain-HTTP stub server fixture (status-only, headerless 429, CloudFront 403 HTML, chunked, truncated, accept-then-stall modes), client-vs-stub test suite, pinned `cacert.pem` + CMake install step.
**Addresses:** [C] truthful status, headers, timeouts, retry policy; [X] stub fixture; kills diagnosis bugs #1–#3 at the root.
**Avoids:** Pitfalls 7–11 (session lifetime, timeout gaps, TLS theater, HTML-to-parser, nested-`run()` deadlock), 18 (stubs nicer than reality), 21 (id-vs-symbol).

### Phase 3: `PriceManager` orchestration
**Rationale:** Depends on Phase 2's types, client interface, and band classifier; pure orchestration testable with zero sockets.
**Delivers:** L1 cache (60 s band) with per-quote timestamps, ~50 ms coalescing window + multi-id batching, fallback chain (L1 → CoinGecko → token.gnus.ai → last-known-good ≤5 min), client-side rate budget + 429 hold-off, long-lived lifetime semantics (one CA read, shared ssl_context), envelope parsing (Phase 1 contract), manager unit suite against the injected fake.
**Addresses:** [C] cache, coalescing, fallback chain, freshness bands, `PriceQuote` surface, configurable endpoints.
**Avoids:** Pitfalls 12 (per-call construction), 13 (chain wiring), 15 (clock skew/units — monotonic anchoring), 16 (LKG policy), 19 (deterministic coalescing tests via injected clock).

### Phase 4: `GeniusNode` cutover + hermetic test conversion
**Rationale:** Depends on Phase 3; swaps the implementation behind the seam and retires the old paths only once the replacement is proven.
**Delivers:** `GetCoinprice` delegation to the manager, config surface (env vars + `SetPriceEndpoints` setter following the `SetChainlistFetcher` precedent — no mid-struct `DevConfig` insertion), deletion of `m_tokenPriceCache`/`MIN_API_CALL_INTERVAL`, retirement of `CoinGeckoPriceRetriever` from the seam, hermetic conversion of `price_retrieval_test` (CTest-registered; live smoke demoted to opt-in) and `account_management_test.SetPayoutAddress` (stub-injected), `GNUS → genius-ai` id mapping in one place.
**Addresses:** [C] seam preservation (LPM-10), configurable endpoints; [X] hermetic C++ tests, CI-exclusion unlock.
**Avoids:** Pitfalls 12 (cutover lifetime), 16 (seam logging/validation), 17 (zero-tolerance network rule — `127.0.0.1` literals, no `/ping` health probes).

### Phase 5: CI integration
**Rationale:** Depends on Phase 1's tests existing and Phase 4's hermeticity being proven.
**Delivers:** New lightweight `worker-tests` GitHub job (node 22, `npm ci` + `tsc --noEmit` + `vitest run`, path-filtered so C++-only PRs skip Node setup), removal of the aarch64-Debug `GTEST_FILTER` exclusion at `cmake.yml:649`, verification of that CI leg.
**Addresses:** [X] CI gates for both codebases; no `wrangler deploy` in CI (deployment out of scope).
**Avoids:** Pitfalls 5 (fail-closed fetch mocks make the job trustworthy) and 17 (hermeticity is what makes exclusion removal legitimate).

### Phase Ordering Rationale

- **Envelope contract is the join point:** Phase 1 pins it so Phase 2/3 parse a stable target; without the golden fixture defined alongside, the C++ parser chases a moving target
- **Critical path is 2 → 3 → 4 → 5** (the C++ chain); Phase 1 runs concurrently with 2–3 and must merely land before Phase 5's worker job
- **Fallback chain requires truthful status first** — the chain is *driven by* typed failure codes, so transport (Phase 2) strictly precedes orchestration (Phase 3)
- **Hermeticity precedes CI changes** — removing the aarch64-Debug exclusion is only legitimate after `SetPayoutAddress` provably never touches the internet (configurable endpoints + stub server, Phases 2–4)
- **`GeniusNode` cache delegation is mandatory, not optional** — leaving `m_tokenPriceCache` in place recreates the split-brain anti-feature the manager exists to remove

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 1 (DO/cache specifics):** vitest-plugin is a recently renamed package (Aug 2026) — migration-era docs may still reference `vitest-pool-workers`; pin exact behaviors (fail-closed fetch mocking config, per-test-file DO isolation, `.wrangler/state` cleanup) during plan-writing
- **Phase 2 (TLS asset plumbing):** runtime location/discovery of `cacert.pem` across 5 platforms + test-binary CWD needs a concrete CMake decision (copy-to-build-tree vs install rule) — design it in the plan, not in review
- **Phase 4 (config surface):** `GeniusNodeConfig` aggregate is positionally initialized at many test call sites — the env-var + setter approach is decided, but each touched call site needs enumerating during planning

Phases with standard patterns (skip research-phase):
- **Phase 3:** pure orchestration over interfaces produced by Phase 2 — standard C++ patterns (mutex + future facade, injectable clock)
- **Phase 5:** conventional GitHub Actions job; path filters and setup-node are boilerplate

---
*Research summary for: PriceCoordinator — Local Manager + token.gnus.ai Fallback (workstream: tokenprice)*
*Synthesized from: STACK.md, FEATURES.md, ARCHITECTURE.md, PITFALLS.md (all 2026-09-29)*
