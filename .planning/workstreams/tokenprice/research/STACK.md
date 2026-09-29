# Stack Research

**Domain:** Hybrid token-price service — TypeScript Cloudflare Worker (token.gnus.ai) + C++ Local Price Manager inside SuperGenius
**Researched:** 2026-09-29
**Confidence:** HIGH for Cloudflare/npm versions (verified against npm registry & Cloudflare docs, 2026-09-29) · HIGH for C++ side (verified against workspace source) · MEDIUM for Node.js engine floor (not directly verified)

Context for the roadmapper: this milestone adds **two codebases** — (a) a TypeScript Cloudflare Worker + SQLite-backed Durable Object (code + tests only, no deployment), and (b) a C++ Local Price Manager + fallback chain replacing today's `CoinGeckoPriceRetriever` behavior in `SuperGenius/src/coinprices/`. Everything below is scoped to those two additions plus hermetic test infrastructure. **Zero new vendored thirdparty C++ libraries.**

---

## Recommended Stack

### Core Technologies — Worker side (`token.gnus.ai`)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `wrangler` | `^4.144.0` (dev dep) | Build/dev/deploy CLI, `wrangler.jsonc` config, local `workerd` runtime via `wrangler dev` | The only supported Workers toolchain; 4.x runs DOs + Cache API locally on the real `workerd` runtime (not a JS polyfill). Verified current: 4.144.0 published 2026-09-29. |
| `@cloudflare/vitest-plugin` | `^1.3.3` (dev dep) | Vitest integration that runs tests **inside** the Workers runtime (miniflare/workerd under the hood), isolated per-test storage, declarative outbound-fetch mocking | **This is now Cloudflare's recommended package** — it *replaced* `@cloudflare/vitest-pool-workers` (Aug 2026 docs; migration guide + codemod exist). Same API surface, renamed package. Verified peer dep: `vitest ^4.1.0`. |
| `vitest` | `^4.1.0` — **pin 4.x, do NOT take 5.x** | Test runner for Worker unit/integration tests | Hard constraint from the plugin's peerDependencies (`vitest: ^4.1.0`). Vitest 5.0.2 is latest but incompatible with the plugin today. |
| `@cloudflare/workers-types` | `^5.20260929.1` (dev dep) | Runtime typings (`DurableObjectState`, `DurableObjectNamespace`, `CacheStorage`, `Fetcher`) | Verified current. Alternative: `wrangler types` generates project-specific types from `wrangler.jsonc` — fine either way; hand-listed types are simpler for one service. |
| TypeScript | `~5.9.x` (dev dep) | Type-checking (`tsc --noEmit`) | TS 7.0.2 (the Go-port compiler) just hit `latest` and is too new for the Workers toolchain — wrangler/vitest templates and the plugin's own devDeps (5.8.3) are still on 5.x. Wrangler bundles code with esbuild, so `tsc` is type-check-only. |
| Durable Objects (SQLite-backed) | runtime feature, configured via `wrangler.jsonc` | Single-flight request coalescing across clients (`PriceCoordinator:USD` object) + per-currency state | SQLite-backed DOs are **available on the Workers Free plan** (key-value-backed are paid-only — must use `new_sqlite_classes` in the migration). 100k DO requests/day free is ample at ~2% fallback traffic. `ctx.storage.sql` gives a tiny table for prices; in-memory map + SQL persistence both fine. |
| `caches.default` (Cache API) | runtime feature | Shared per-colo cache in front of the DO (worker checks cache → DO on miss → `cache.put` with `Cache-Control`) | Available on Free; per-datacenter (each colo warms independently) — exactly what the design doc calls for. Works locally in `wrangler dev` / vitest-plugin (miniflare `cacheAPI`). |

**Minimal `wrangler.jsonc`** (wrangler now generates JSONC by default; TOML equally supported — pick JSONC for `$schema` autocomplete):

```jsonc
{
  "$schema": "node_modules/wrangler/config-schema.json",
  "name": "token-price-coordinator",
  "main": "src/index.ts",
  "compatibility_date": "2026-09-01",          // pin; bump deliberately
  "durable_objects": { "bindings": [{ "name": "PRICE_COORDINATOR", "class_name": "PriceCoordinator" }] },
  "migrations": [{ "tag": "v1", "new_sqlite_classes": ["PriceCoordinator"] }]  // NOT new_classes: Free plan requires SQLite-backed
}
```

### Core Technologies — C++ side (Local Price Manager)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **Boost.Beast** (already in tree) | Boost 1.85.0 (GeniusSDK) / 1.89 (SuperGenius thirdparty) | The HTTP client for both CoinGecko direct and `token.gnus.ai` calls: full access to **status code, response headers, timeouts, User-Agent, chunked decoding** | Already proven in this repo: `SuperGenius/test/src/price_retrieval/price_retrieval_test.cpp` includes and links `boost/beast/http.hpp` today, on every CI platform. Header-only (links `Boost::headers` + `Boost::system`). Solves exactly the defects found in the diagnosis: status swallowed, fixed UA, no caller-visible timeout. |
| **Boost.Asio SSL** (already in tree) | same Boost; OpenSSL 3.x vendored in thirdparty | HTTPS for api.coingecko.com and token.gnus.ai; SNI via `SSL_set_tlsext_host_name` | Same stack `HTTPDevice` already uses (`thirdparty/AsyncIOManager/src/HTTPCommon.cpp`). See TLS/cert-verification callout below — the existing code effectively does **not** verify certs; the new client must. |
| **rapidjson** (already in tree) | vendored in `thirdparty/rapidjson`, linked `PRIVATE` by `coinprices` today | Parse CoinGecko `/simple/price` and the new envelope (`currency/prices/fetchedAt/age/source/stale`) | Continuity: `coinprices.cpp` already parses with it; envelope is flat and trivial. Header-only, zero new deps. `boost_json` is *also* already a found component — either works; keep rapidjson to match the module being replaced. |
| GTest (already in tree) | ~1.14 vendored | C++ unit tests for cache/coalescing/fallback/freshness bands | Standard for `SuperGenius/test/`; `price_retrieval_test` already exists there to extend/replace. |
| `std::mutex` / `std::condition_variable` / `boost::asio::steady_timer` | C++17 stdlib + Boost | L1 cache locking + the ~50 ms coalescing window + backoff timers | All in-tree; no new deps. A single dedicated `io_context` (or one std::thread + cv) drives the coalescing batch. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `unstable_dev` (from `wrangler`) | with wrangler `^4.144.0` | Spin the Worker in-process from a Node test for black-box integration tests against the *real* bundle | Optional. Prefer vitest-plugin's in-runtime `SELF` fetch for unit/integration; use `unstable_dev` only if we want a test that exercises the built artifact the way a separate process would (e.g., alongside the C++ client E2E). |
| `miniflare` | 5.x (transitive — do NOT add directly) | Low-level simulator; vitest-plugin and wrangler both embed it | Don't take it as a direct dependency; listed so the roadmapper knows it's what actually runs tests locally. |
| CA certificate bundle (data file, not a library) | Mozilla `cacert.pem` snapshot, pinned in-repo | `ssl_context->load_verify_locations()` for peer verification on Windows/macOS/Android/iOS where `set_default_verify_paths()` has nothing to load | See TLS section — this is the one *asset* (a ~250 KB text file) the C++ side needs. Not a thirdparty *build* addition. |
| `@cloudflare/codemods` | n/a | `vitest:pool-workers-to-vitest-plugin` codemod | Only if any reference code was scaffolded on the old `vitest-pool-workers` package. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `wrangler dev` | Local dev server (real `workerd`, DOs + Cache API simulated, SQLite persistence under `.wrangler/state`) | Default local mode; binds 127.0.0.1:8787 (override `--port`). The C++ client tests can point at it over plain HTTP for a full-stack local E2E. |
| Node.js `>= 20 LTS` (recommend 22 LTS) | Runs wrangler/vitest | Wrangler 4 requires modern Node (18+ floor); CI should use `actions/setup-node@v4` with `node: 22`. Engine floor not re-verified this pass — MEDIUM confidence. |
| `tsc --noEmit` + `vitest run` | Type-check gate + test gate for the Worker | Add both as separate npm scripts; only `vitest run` (and optionally tsc) in CI. |
| CTest (existing) | Registers the new C++ price tests + stub server fixture | Follow `SuperGenius/test/src/price_retrieval/CMakeLists.txt` pattern; new `add_executable` + `set_tests_properties`. |

## Integration Points with Existing SuperGenius Code

1. **Call path preserved:** `GetProcessCost` → `GeniusNode::GetGNUSPrice` (`GeniusNode.cpp:2828`) → today `GetCoinprice` (`GeniusNode.cpp:3510`) constructs a stack `CoinGeckoPriceRetriever` and calls `getCurrentPrices`. The Local Price Manager replaces the retriever behind this same seam (a `PriceProvider`-style interface); `GetGNUSPrice` keeps returning `outcome::result<double>` with its existing finite/positive check.
2. **New module, not an edit-in-place:** implement the manager as new files (e.g. `PriceManager.{hpp,cpp}`, `PriceQuote.hpp`, `HTTPPriceClient.{hpp,cpp}`) inside `SuperGenius/src/coinprices/` (or sibling module), keeping `CoinGeckoPriceRetriever` compiling until cutover; `CMakeLists.txt` there already links `Boost::headers`, `rapidjson`, `AsyncIOManager`, `logger`, `outcome` — Beast needs only `Boost::headers`+`Boost::system` (already transitively present).
3. **Why a new Beast client instead of extending `FileManager::LoadASync`:** the existing path (`HTTPCommon.cpp:196`) sends a hard-coded `User-Agent: GeniusAI/1.0`, strips headers at `HTTPCommon.cpp:255` and returns the body regardless of status — the exact bug from the diagnosis. Surfacing status/headers there would ripple into every other consumer (MNN/IPFS/SFTP loaders). A ~200-line Beast client scoped to `coinprices` is strictly safer; leave AsyncIOManager untouched this milestone.
4. **`HTTPDevice::SetVerifyPeer` is currently a dead toggle:** default `s_verify_peer=true` never calls `set_verify_mode(verify_peer)` nor loads CAs, so OpenSSL's default (`SSL_VERIFY_NONE`) applies — certs are not actually verified today. The new client must set `verify_peer` + SNI + load the pinned CA bundle. (Log this as a known pre-existing issue; don't fix AsyncIOManager here.)
5. **Hermetic `account_management_test.SetPayoutAddress`:** give the manager a configurable base URL (env var / `GeniusNodeConfig` field, default `https://api.coingecko.com`); the test injects `http://127.0.0.1:<stub-port>/`. After that, delete the aarch64-Debug `GTEST_FILTER` exclusion of `AccountManagement.SetPayoutAddress` in `SuperGenius/.github/workflows/cmake.yml:649`.

## TLS/HTTPS Considerations by Platform (C++ client)

| Platform | Verification source | Notes |
|----------|--------------------|-------|
| Linux (x86_64/aarch64) | `ssl::context::set_default_verify_paths()` → `/etc/ssl/certs` | Vendored static OpenSSL still honors the system dir on Debian/Ubuntu runners. |
| Windows (MSVC 2022) | **No default paths** — load the in-repo pinned `cacert.pem` | OpenSSL static build has no OPENSSLDIR with certs. (Alternative — extract from Windows ROOT store via CryptoAPI — is more code for no gain.) |
| macOS (universal) | In-repo `cacert.pem` | Vendored OpenSSL's OPENSSLDIR won't exist; `/etc/ssl/cert.pem` is system-clang-linked LibreSSL — don't rely on it. |
| Android / iOS | In-repo `cacert.pem` | No guaranteed system store access through static OpenSSL; the bundle is the only portable answer. |

Decision: **always load the pinned in-repo bundle** (uniform across all 5 platforms, hermetic, no OS probing). SNI (`SSL_set_tlsext_host_name`) is mandatory for both api.coingecko.com (CloudFront) and token.gnus.ai (Cloudflare). Timeouts via Beast's `beast::tcp_stream::expires_after` (connect+handshake+read ≈ 5 s — today's HTTPDevice uses 10/10/30 s, far too slow for a fallback chain).

## Installation

Worker side (new directory, e.g. `SuperGenius/tokenpriceservice/` — sibling to `src/`, self-contained):

```bash
# package.json (dev-only deps — nothing ships to production runtime)
npm i -D wrangler@^4.144.0 @cloudflare/vitest-plugin@^1.3.3 vitest@^4.1.0 @cloudflare/workers-types@^5.20260929.1 typescript@~5.9.0

# scripts:
#   "dev":   "wrangler dev"
#   "test":  "vitest run"
#   "typecheck": "tsc --noEmit"
```

C++ side: **nothing to install.** Boost.Beast/Asio/SSL, rapidjson, fmt, GTest, OpenSSL are all already built by `thirdparty/`. The only new file is the pinned `cacert.pem` data asset.

## Test Infrastructure

**Worker (hermetic, no network):**
- `@cloudflare/vitest-plugin` with `defineWorkersConfig` (vitest.config.ts) reading `wrangler.jsonc` — tests run in workerd with real DO (SQLite) + Cache API, isolated per test file.
- CoinGecko upstream mocked via the plugin's declarative outbound request mocking (`fetch` interception) or a service-binding test double — assert 200-envelope / stale-envelope / 429-passthrough / coalescing behavior deterministically.

**C++ (hermetic, no network):**
- Unit tests: manager constructed with an injected `PriceHttpClient` interface (fake returning canned envelopes incl. 403-HTML, 429, timeout) — verifies freshness bands, L1 hit, coalescing dedupe, fallback order, last-known-good, retry/backoff policy (never retry 403/429).
- Stub server: a ~100-line **Boost.Beast plain-HTTP server on 127.0.0.1:0** (OS-assigned port) inside the test binary — scriptable status/body per path. Plain HTTP avoids TLS/cert machinery in tests; the client takes a full base URL so production still uses HTTPS.
- Optional full-stack local E2E (manual / one CI job): `wrangler dev` serves the real worker on 127.0.0.1; C++ client pointed at it — proves the envelope contract end-to-end with zero internet.
- Rewrite/extend `SuperGenius/test/src/price_retrieval/` — existing tests hit live CoinGecko (`GetCurrentPrice` etc.); replace with hermetic equivalents so the suite stops being network-dependent.

## CI Integration (`SuperGenius/.github/workflows/cmake.yml`)

1. **New lightweight job `worker-tests`** (separate from the 16-matrix build): `runs-on: ubuntu-latest`, `actions/setup-node@v4` (node 22, `cache: npm` scoped to the worker dir), `npm ci`, `npm run typecheck`, `npm run test`. Fully hermetic — vitest-plugin/miniflare never egress. Trigger on `paths:` filter for the worker directory, plus the existing push/PR branches, so C++-only PRs don't pay the Node setup.
2. **C++ side needs no new CI job**: hermetic tests run inside the existing `ctest` invocation. After `SetPayoutAddress` is made hermetic, remove it from the aarch64-Debug `GTEST_FILTER` exclusion (`cmake.yml:649`) — that's a small, verifiable win to phase in.
3. Do **not** add `wrangler deploy` to CI (deployment is out of scope / manual per milestone definition).

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `@cloudflare/vitest-plugin` 1.3.3 | `@cloudflare/vitest-pool-workers` 0.22.0 | Never for new code — Cloudflare explicitly directs new projects to the plugin (renamed successor, same API). Old package only if pinning an existing legacy project. |
| vitest 4.1.x | vitest 5.0.x | Not until the plugin's peer range includes 5.x. |
| Boost.Beast client in `coinprices` | Extend `FileManager`/`HTTPDevice` (AsyncIOManager) | Only if a *second* subsystem later needs status/headers — then do it once, properly, with a compat review across MNN/IPFS/SFTP loaders. Out of scope now. |
| Boost.Beast client | libcurl (`find_package(CURL)`) | Rejected: new system dependency on 5 platforms, breaks the "vendored static, hermetic" build model; Beast already proven in-tree. |
| rapidjson | `boost_json` (already a found Boost component) | Either is defensible; boost_json has a nicer API but rapidjson keeps `coinprices` homogeneous. Switch only if the module is being rewritten anyway. |
| Pinned in-repo CA bundle | OS cert store probing per platform | OS stores only if the bundle's update cadence ever becomes a compliance problem. |
| SQLite-backed DO (`new_sqlite_classes`) | KV-backed DO (`new_classes`) | KV-backed requires Workers Paid — non-starter for this milestone. |
| `caches.default` + DO | Cloudflare Queues / Workers KV for hot cache | Explicitly rejected in the design doc (Queues free tier ≈ 3,333 msgs/day; KV free = 1,000 writes/day). |
| `wrangler.jsonc` | `wrangler.toml` | Pure preference; TOML is fully supported — pick JSONC for schema autocomplete. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `@cloudflare/vitest-pool-workers` | Superseded by `@cloudflare/vitest-plugin` (Aug 2026); migration guide live | `@cloudflare/vitest-plugin@^1.3.3` |
| vitest 5.x with the plugin | Peer range is `^4.1.0` — install fails/warns | vitest `^4.1.0` |
| TypeScript 7.x | Go-port compiler, brand new; Workers templates/tooling still on 5.x | TypeScript `~5.9` |
| Cloudflare Queues in the price path | Free tier ops accounting makes it unusable (≈3 msgs/price-request) | DO single-flight |
| KV as hot price cache | 1,000 writes/day free cap vs 60 s updates | `caches.default` + DO |
| Embedding a CoinGecko API key in the C++ client | Public binary/mobile key ≠ secret | Keyless client; key lives only in the Worker (`secret`, server-side) |
| New vendored thirdparty C++ lib (curl, cpr, nlohmann) | Violates milestone constraint; everything needed is in-tree | Boost.Beast + rapidjson |
| Retrying 403/429 with short backoff | Re-triggers CoinGecko's minutes-scale limiter (diagnosis) | Retry only transient transport errors; 429 → fall through to token.gnus.ai; 403 → immediately fall through |
| `std::this_thread::sleep_for` retry loop in production path | Blocks caller, hostile to limiter (current bug) | `steady_timer` async backoff or scheduled re-fetch |
| Relying on `x-ratelimit-*`/`Retry-After` from CoinGecko | Empirically absent (diagnosis, 2026-09-29) | Our own conservative client-side budget + freshness bands |

## Stack Patterns by Variant

**If the target is the Worker (`token.gnus.ai`):**
- TypeScript ESM, modules-format Worker (`export default { fetch }`), one DO class `PriceCoordinator` exported from the same script
- Worker `fetch`: validate `ids`/`vs` → `caches.default.match` → DO `getFromNamespace(idFromName("USD"))` → `cache.put(resp, {expirationTtl: 45})`
- Because per-test-file isolation regenerates DO state, coalescing tests should use `vi.useFakeTimers`-friendly seams (clock injection) or assert on the mocked upstream *call count*

**If the target is the C++ node:**
- `PriceQuote { asset, currency, price, timestamp, source, stale }` with `enum class PriceSource { LocalCache, CoinGecko, GnusPriceService, OnChain }` (`OnChain` declared, unimplemented — reserved enum value only)
- Fallback chain: L1 fresh → CoinGecko direct (batched, coalesced) → token.gnus.ai → last-known-good (stale ≤ 5 min) → error
- All I/O through one injectable interface so GTest fakes never open a socket

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|----------------|-------|
| `@cloudflare/vitest-plugin@1.3.3` | `vitest@^4.1.0` (+ `@vitest/runner`, `@vitest/snapshot` ^4.1.0) | Hard peer range — verified from registry metadata 2026-09-29 |
| `wrangler@4.144.0` | Node ≥ 18 (use 20/22 LTS); embeds miniflare 5.x + workerd | `wrangler dev` local mode covers DO-SQLite + Cache API |
| `@cloudflare/workers-types@5.20260929.1` | TS 5.x `lib` setup via tsconfig `types` | Generated `wrangler types` is the alternative |
| Boost.Beast (1.85/1.89 in-tree) | Boost.Asio SSL + vendored OpenSSL 3.x | Header-only; already compiled in test targets on all 5 platforms |
| rapidjson (vendored) | `coinprices` `PRIVATE` link | Unpinned vendored snapshot — do not bump for this milestone |
| DO SQLite on Free plan | `new_sqlite_classes` migration tag required | `new_classes` (KV-backed) is paid-only |

## Sources

- npm registry (verified 2026-09-29): `wrangler` 4.144.0 · `@cloudflare/vitest-plugin` 1.3.3 (peerDeps inspected) · `vitest` 5.0.2 latest / 4.1.0 required · `miniflare` 5.20260926.1-alpha · `@cloudflare/workers-types` 5.20260929.1 · `typescript` 7.0.2 latest — **HIGH**
- Cloudflare docs: Vitest integration index + "Migrate to Vitest plugin" guide (states plugin replaces pool-workers; codemod `vitest:pool-workers-to-vitest-plugin`) — **HIGH**
- Design reference `.planning/research/pricing_coordinator.md` (Free-plan DO/Workers/Queues/KV limits, freshness bands, envelope contract) — carried input
- Diagnosis memory `/memories/repo/coingecko-price-api-frontend.md` (403/WAF path-scoped block, 429 no-headers, client bugs) — carried input
- Workspace source (verified this pass): `SuperGenius/src/coinprices/{coinprices.cpp,coinprices.hpp,CMakeLists.txt}` · `SuperGenius/src/account/GeniusNode.cpp:2798-2853,3510` · `thirdparty/AsyncIOManager/src/HTTPCommon.cpp:120-280` (UA hard-coded :196, headers stripped :255, verify-peer dead toggle :127-131) · `SuperGenius/test/src/price_retrieval/price_retrieval_test.cpp` (Beast already linked) · `GeniusSDK/cmake/CommonBuildParameters.cmake` (Boost 1.85.0, GTest, fmt, OpenSSL, rapidjson, AsyncIOManager) · `SuperGenius/.github/workflows/cmake.yml:646-667` (aarch64-Debug GTEST_FILTER exclusion) — **HIGH**
- Node.js engine floor for wrangler 4 (18+) — **MEDIUM, not re-verified this pass**

---
*Stack research for: PriceCoordinator — Local Manager + token.gnus.ai Fallback (workstream: tokenprice)*
*Researched: 2026-09-29*
