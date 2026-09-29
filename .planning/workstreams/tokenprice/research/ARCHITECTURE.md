# Architecture Research

**Domain:** Hybrid token-price system — C++ Local Price Manager inside the SuperGenius node + TypeScript Cloudflare Worker (`token.gnus.ai`) fallback
**Researched:** 2026-09-29
**Confidence:** HIGH — every integration point below was verified against workspace source this pass (files/lines cited)

---

## Standard Architecture

### System Overview

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ CALLERS (unchanged)                                                          │
│   GeniusSDK.cpp:707/728  GeniusSDKGetProcessCost                              │
│   GeniusNode.cpp:2679    ProcessImage → GetProcessCost (GeniusNode.cpp:2797) │
├──────────────────────────────────────────────────────────────────────────────┤
│ SEAM (preserved, LPM-10)                                                     │
│   GeniusNode::GetGNUSPrice (GeniusNode.cpp:2828, decl hpp:397)               │
│   GeniusNode::GetCoinprice (GeniusNode.cpp:3510, decl hpp:822)               │
├──────────────────────────────────────────────────────────────────────────────┤
│ NEW: Local Price Manager (SuperGenius/src/coinprices/, own io_context+thread)│
│  ┌───────────────┐ ┌──────────────┐ ┌───────────────────────────────┐        │
│  │ L1 cache 60s  │ │ Coalescing   │ │ Fallback chain (band-aware)   │        │
│  │ (LPM-01)      │ │ window ~50ms │ │ L1→CG→token.gnus.ai→LKG (5m)  │        │
│  └───────────────┘ └──────────────┘ └───────────────────────────────┘        │
│  ┌───────────────────────────────┐ ┌───────────────────────────────┐        │
│  │ PriceQuote / PriceSource      │ │ Beast HTTPS client (scoped)    │        │
│  │ {asset,currency,price,ts,     │ │ status/UA/SNI/verify_peer/5s  │        │
│  │  source,stale}  (QUOTE-01/02) │ │ timeouts  (LPM-05..08)        │        │
│  └───────────────────────────────┘ └───────────────────────────────┘        │
├──────────────────────────────────────────────────────────────────────────────┤
│ FALLBACK TIER 2: token.gnus.ai Worker (NEW — SuperGenius/tokenpriceservice/) │
│   GET /v1/prices?ids=…&vs=usd → {currency,prices,fetchedAt,age,source,stale} │
│  ┌───────────────────┐  ┌────────────────────────────────────────┐           │
│  │ caches.default    │→ │ Durable Object "PriceCoordinator:USD"  │           │
│  │ read-through ≤60s │  │ SQLite-backed, single-flight coalescing│           │
│  └───────────────────┘  └──────────────────┬─────────────────────┘           │
│                                            ▼                                  │
│                                     CoinGecko (key server-side only, SRVC-06)│
├──────────────────────────────────────────────────────────────────────────────┤
│ TEST FIXTURES (new)                                                          │
│   Beast plain-HTTP stub server (127.0.0.1:0, scriptable) — TEST-03           │
│   Injected PriceHttpClient fake (zero sockets) — TEST-02                      │
│   workerd vitest suite with mocked upstream — TEST-01                        │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Status | Location / evidence |
|-----------|----------------|--------|---------------------|
| `GeniusNode::GetCoinprice` / `GetGNUSPrice` | Public price seam; caching gate today | **Modified** (Phase 4) | `SuperGenius/src/account/GeniusNode.cpp:3510`, `:2828`; decls `GeniusNode.hpp:822`, `:397` |
| `GetProcessCost` | Primary caller; converts price → minion cost | **Unchanged** (LPM-10) | `GeniusNode.cpp:2797` (call to `GetGNUSPrice` at `:2809`); also `GeniusNode.cpp:2679` inside `ProcessImage`; SDK: `GeniusSDK/src/GeniusSDK.cpp:707`, `:728` |
| `CoinGeckoPriceRetriever` | Today's transport (status-swallowing, sleep-retry) | **Retired** (Phase 4); historical endpoints kept compiling | `SuperGenius/src/coinprices/coinprices.cpp` — retry+`sleep_for` at `:100-112`, per-request temp `io_context` at `:133`, URL `:137`, `FileManager::LoadASync` `:142`, `decodeChunkedTransfer` `:23`, JSON parse `:168` |
| `PriceManager` | L1 cache, ~50ms coalescing, multi-id batching, fallback chain, last-known-good | **New** (Phase 3) | new files in `SuperGenius/src/coinprices/` |
| `PriceQuote` / `PriceSource` | Provider-independent quote surface + freshness bands | **New** (Phase 2) | new header in `SuperGenius/src/coinprices/` |
| Beast HTTPS price client | Truthful status/headers, UA, SNI, `verify_peer` + pinned CA, 5s timeouts, transient-only retry | **New** (Phase 2) | new files in `SuperGenius/src/coinprices/`; deliberately does **not** touch `FileManager`/`HTTPDevice` (`thirdparty/AsyncIOManager/src/HTTPCommon.cpp:196` UA hard-coded, headers+status stripped at `:255ff`, `s_verify_peer` dead toggle at `:72`, `:128-131`) |
| Worker `/v1/prices` + `PriceCoordinator` DO | Shared fallback tier: per-colo cache, single-flight, SQLite persistence, stale-serving | **New** (Phase 1) | new dir `SuperGenius/tokenpriceservice/` (STACK.md recommendation, sibling of `src/`) |
| Beast stub server fixture | Scriptable canned 200/403-HTML/429/timeout on `127.0.0.1:0` | **New** (Phase 2) | test helper, `SuperGenius/test/src/price_retrieval/` |
| `account_management_test.SetPayoutAddress` | Today network-dependent (calls `GetProcessCost` at `account_management_test.cpp:333`, `ProcessImage` at `:352`) | **Modified** (Phase 4) | `SuperGenius/test/src/account/account_management_test.cpp:136` |
| `price_retrieval_test` | Live CoinGecko smoke tests, built but **not** CTest-registered | **Modified/replaced** (Phase 4) | `SuperGenius/test/src/price_retrieval/CMakeLists.txt:1` ("build it, but do not register") |
| CI workflow | aarch64-Debug excludes `SetPayoutAddress` via `GTEST_FILTER`; gets `worker-tests` job | **Modified** (Phase 5) | `SuperGenius/.github/workflows/cmake.yml:649`, job added near test steps |
| GeniusNode price-cache members | `m_tokenPriceCache` (60s) + 5s `MIN_API_CALL_INTERVAL` gate — superseded by manager L1 | **Removed** (Phase 4) | `GeniusNode.hpp:1481-1490`; ctor init `GeniusNode.cpp:237` |

## Recommended Project Structure

```text
SuperGenius/
├── src/coinprices/                  # existing module — grows, stays one CMake target
│   ├── coinprices.{hpp,cpp}         # existing; historical endpoints keep compiling
│   ├── PriceQuote.hpp               # NEW: quote struct, PriceSource enum, band classifier
│   ├── PriceManager.{hpp,cpp}       # NEW: L1 cache, coalescing, fallback chain
│   ├── HTTPPriceClient.{hpp,cpp}    # NEW: Beast client + injectable interface
│   ├── PriceEndpoints.{hpp}         # NEW: config resolution (env vars, defaults)
│   ├── CMakeLists.txt               # MODIFIED: new sources; +OpenSSL::SSL, +Boost::system
│   └── cacert.pem                   # NEW: pinned Mozilla CA bundle (~250 KB data asset)
├── tokenpriceservice/               # NEW: self-contained Worker project (no CMake coupling)
│   ├── package.json                 # STACK.md-pinned dev deps only
│   ├── wrangler.jsonc               # DO binding + new_sqlite_classes migration
│   ├── tsconfig.json
│   ├── vitest.config.ts
│   └── src/
│       ├── index.ts                 # fetch handler: validate → cache → DO
│       ├── coordinator.ts           # PriceCoordinator DO class
│       └── envelope.ts              # envelope types + freshness semantics (shared contract)
└── test/src/
    ├── price_retrieval/             # REWRITTEN hermetic: manager suite, client-vs-stub suite
    │   ├── CMakeLists.txt           # MODIFIED: addtest-registered hermetic targets + stub lib
    │   ├── price_stub_server.{hpp,cpp}   # NEW: Beast plain-HTTP scriptable fixture
    │   ├── price_manager_test.cpp        # NEW: injected fake (no sockets)
    │   ├── price_client_stub_test.cpp    # NEW: client vs stub incl. 403-HTML/429
    │   └── price_retrieval_test.cpp      # REPLACED (live-network cases removed, TEST-05)
    └── account/
        ├── CMakeLists.txt           # MODIFIED: link stub helper into account_management_test
        └── account_management_test.cpp  # MODIFIED: point nodes at stub via env/setter
```

### Structure Rationale

- **`src/coinprices/` stays the single C++ module:** it is already linked into `genius_node` via `GENIUS_NODE_LIBS` (`SuperGenius/src/CMakeLists.txt:19`, `add_subdirectory` at `:57`) and consumed by `GeniusNode.cpp`. Adding files there requires no new link wiring anywhere except the module's own `CMakeLists.txt` (today links `Boost::headers`, `logger`, `outcome` PUBLIC; `rapidjson`, `AsyncIOManager` PRIVATE — Beast needs `Boost::system` and OpenSSL added PRIVATE; precedent: `price_retrieval_test` already links `OpenSSL::SSL` for Beast).
- **`tokenpriceservice/` as sibling of `src/`:** the SuperGenius tree already hosts non-`src/` self-contained subtrees (`evmrelay/`, `gRPCForSuperGenius/`, `GeniusKDF/`, `SGProcessingManager/`). A Node project must not entangle the 16-config C++ matrix; a plain directory with `package.json` is invisible to CMake and path-filtered in CI.
- **Stub server as a test helper linked into both test binaries:** `account_management_test` (`test/src/account/CMakeLists.txt:35-39`) and the new price tests need the same fixture; a small helper library (or compiled pair in each `CMakeLists.txt`, matching the repo's `addtest` conventions in `SuperGenius/cmake/functions.cmake:8`) avoids a second process and port lifecycle.

## Architectural Patterns

### Pattern 1: Preserve the seam, replace behind it (LPM-10)

**What:** `GetProcessCost` → `GetGNUSPrice` → `GetCoinprice` keeps its exact signatures and `outcome::result` surface; only `GetCoinprice`'s *body* changes from "consult node cache, maybe construct `CoinGeckoPriceRetriever`" to "delegate to `PriceManager`".

**When to use:** whenever external behavior (SDK exports, error codes, finite/positive validation in `GetGNUSPrice` at `GeniusNode.cpp:2836-2842`) must not change.

**Trade-offs:** callers stay synchronous (see Pattern 3); in exchange, zero GeniusSDK/wallet changes and `Error::NO_PRICE` semantics survive verbatim.

**Verified call graph today:**
```text
GeniusSDKGetProcessCost      GeniusSDK.cpp:707, :728
  └─ GeniusNode::GetProcessCost        GeniusNode.cpp:2797 (also from ProcessImage :2679)
       └─ GetGNUSPrice                 GeniusNode.cpp:2828  (decl hpp:397)
            └─ GetCoinprice({"genius-ai"})   GeniusNode.cpp:2830 → :3510 (decl hpp:822)
                 ├─ m_tokenPriceCache lookup (60s TTL)   GeniusNode.cpp:3518-3520
                 ├─ MIN_API_CALL_INTERVAL gate (5s)      GeniusNode.cpp:3533
                 └─ CoinGeckoPriceRetriever::getCurrentPrices  (stack object, :3534)
                      └─ getCurrentPricesOnce             coinprices.cpp:114ff
```

### Pattern 2: Dedicated io_context + thread for the manager

**What:** `PriceManager` owns a private `boost::asio::io_context` and one worker thread — not the node's shared `io_` pool.

**When to use:** leaf subsystem whose async ops have multi-second timeouts and no dependency on the node object graph.

**Trade-offs:** one extra thread per node vs. protecting the shared pool. The node's `io_` runs exactly `DEFAULT_IO_THREADS = 4` threads (`GeniusNode.hpp`, ctor spawn at `GeniusNode.cpp:292-296`); parking 5s HTTP chains there would starve posted lifecycle work. In-tree precedent for the dedicated-context pattern: PubSub's own context kept alive via `pubsub_context_keepalive_` (`GeniusNode.hpp` ownership-order comment); today's coinprices code already avoids the node pool by building a *temporary* `io_context` per request (`coinprices.cpp:133`), just wastefully and on the caller's thread.

**Teardown:** an independent context makes destruction ordering trivial — `Stop()` cancels timers, drains handlers, joins the thread — sidestepping the fragile `io_` teardown ordering documented around `GeniusNode.cpp:2206-2242`.

### Pattern 3: Synchronous facade over async internals

**What:** `PriceManager::GetPrices(ids, budget)` blocks the caller on a `std::future` (bounded total budget) while coalescing/fallback/backoff run as async ops on the manager's thread.

**When to use:** the seam is synchronous today (`GetCoinprice` runs `ioc->run()` on the caller thread, `coinprices.cpp:166`-ish; SDK callers hold `GeniusSDKMutex`, `GeniusSDK.cpp:352`), so blocking callers already exist — but today's worst case is ~3×(10s connect+10s handshake+30s read from `HTTPCommon.cpp` deadlines) ≈ 150s. The facade gives a hard cap (≈ 5s CoinGecko + 5s Worker + small backoff ≈ 12s).

**Trade-offs:** not a true async refactor (explicitly out of scope — gRPC/API surface changes excluded); bounded latency is strictly better than today; `sleep_for` retry hostility (`coinprices.cpp:108`, and 1100ms pacing in historical at `:330`) is replaced by `steady_timer` backoff off the caller thread.

### Pattern 4: Two-tier hybrid traffic shaping

**What:** devices hit CoinGecko direct (batched + coalesced); the Worker sees only fallback traffic (~2%), where DO single-flight + `caches.default` absorb cross-client amplification. Clients stay keyless (SRVC-06) — a key in a distributed binary is not a secret.

**When to use:** upstream rate-limits by IP reputation and applies opaque minutes-scale cooldowns (diagnosis memory: path-scoped 403 CloudFront WAF block, 429 with no `x-ratelimit-*`/`Retry-After` headers).

**Trade-offs:** Worker is a SPOF for its tier only; L1 + last-known-good (≤5 min) keep the node functional when both tiers are unreachable.

## Data Flow

### Request Flow — TODAY (verified)

```text
SDK/wallet → GeniusSDKGetProcessCost (GeniusSDK.cpp:707)
  → GetProcessCost (GeniusNode.cpp:2797)
  → GetGNUSPrice (:2828) → GetCoinprice({"genius-ai"}) (:3510)
      m_tokenPriceCache hit <60s?  → serve (GeniusNode.cpp:3518-3523)
      miss + ≥5s since last call?  → stack CoinGeckoPriceRetriever (:3534)
        getCurrentPrices: up to 3 attempts, sleep_for 250/500ms between (coinprices.cpp:100-112)
          getCurrentPricesOnce: fresh io_context (:133)
          → FileManager::LoadASync → HTTPDevice GET api.coingecko.com/simple/price
            · UA hard-coded "GeniusAI/1.0" (HTTPCommon.cpp:196)
            · status line+headers DISCARDED — body returned regardless (HTTPCommon.cpp:255ff)
            · verify_peer never actually enabled (HTTPCommon.cpp:72,128-131)
            · deadlines 10s/10s/30s
          ← body (a 403 is CloudFront HTML!)
          → decodeChunkedTransfer (:23) → rapidjson parse (:168)
             403-HTML ⇒ "JSON Parse Error: 3" — status invisible in logs
  ← failure propagates all the way up; NO fallback, NO last-known-good beyond 60s cache
  GetGNUSPrice fails ⇒ GetProcessCost returns 0 ⇒ ProcessImage → PROCESS_COST_ERROR
```

### Request Flow — AFTER

```text
GetProcessCost → GetGNUSPrice → GetCoinprice (unchanged signatures)
  → PriceManager::GetPrices(ids, budget)          [sync facade, Pattern 3]
      1. L1 fresh (0–60s)?  → PriceQuote{source: LocalCache}, ZERO network I/O
      2. miss → register waiter; if no batch in flight, steady_timer 50ms window opens
      3. window expires → ONE batched call for UNION of waiter ids (LPM-02/03)
      4. Tier A: CoinGecko direct /simple/price via Beast client
           200 → parse → PriceQuote{source: CoinGecko} → populate L1 → resolve waiters
           403 → fall through NOW (LPM-07)
           429 → fall through, no sub-minute retry against CoinGecko
           timeout/reset/DNS → one bounded steady_timer backoff retry, then fall through
      5. Tier B: GET https://token.gnus.ai/v1/prices?ids=…&vs=usd
           Worker: validate (SRVC-08) → caches.default match? → serve
                   miss → DO PriceCoordinator:USD (idFromName) single-flight
                     → upstream CoinGecko (key from env secret, server-side only)
                     → SQLite-persist prices; upstream fail → serve stale-flagged (SRVC-05)
           ← envelope {currency, prices, fetchedAt, age, source, stale}
           → PriceQuote{source: GnusPriceService} → populate L1
      6. Tier C: last-known-good ≤5min → serve PriceQuote{stale: true}
      7. >5min / never had one → error ⇒ GetGNUSPrice → Error::NO_PRICE (unchanged semantics)
```

### State Management

- **C++ side:** L1 cache is a `std::map<std::string, PriceQuote>` guarded by one mutex, touched only on the manager thread (waiters resolved via promises). Replaces the node-level `m_tokenPriceCache`/`m_lastApiCall` members (`GeniusNode.hpp:1487-1490`, ctor init `GeniusNode.cpp:237`) — delete at cutover.
- **Worker side:** DO SQLite table (prices per id, `fetchedAt`) survives eviction (SRVC-03); `caches.default` holds ≤60s responses per colo; both are runtime state, no coordination with C++ beyond the envelope contract.
- **Freshness bands (FRESH-01/02)** are computed identically on both sides of the wire: 0–60s fresh / 60s–5min stale-usable / >5min unavailable.

### Key Data Flows

1. **Cost estimation (the only production caller):** `GetProcessCost` gets a bounded-latency, always-eventually-priced path — worst case last-known-good instead of `0`.
2. **Fallback envelope contract:** Phase 1's `{currency, prices, fetchedAt, age, source, stale}` JSON is the *only* coupling between the TypeScript and C++ codebases — parsed by rapidjson in the C++ client; no proto, no shared build.

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 1 node (dev/test) | L1 + CoinGecko direct suffices; Worker tier ~never touched; stub server replaces everything in tests |
| 1k–10k nodes | Coalescing + 60s L1 keeps per-device CoinGecko load at ≤1 call/min; Worker sees only blocked-device overflow; DO single-flight + per-colo cache absorb the rest |
| 100k+ nodes | Worker remains fallback-only; if its free-tier DO request budget (100k/day) ever binds, add upstreams behind the Worker (SRC-02) or keyed CoinGecko (SRC-03) — both v2, designed for |

### Scaling Priorities

1. **First bottleneck:** CoinGecko anonymous `/simple/price` (already 403-ing datacenter IPs today) — mitigated *now* by batching/coalescing/fallback, not by retries.
2. **Second bottleneck:** Worker DO free-tier request count — only reachable if CoinGecko blocks whole consumer IP ranges; acceptable at ~2% fallback traffic (v2 levers above).

## Anti-Patterns

### Anti-Pattern 1: Retrying 403/429 with short backoff (the current bug)

**What people do:** `getCurrentPrices` retries any failure 3× with 250/500ms sleeps (`coinprices.cpp:100-112`).
**Why it's wrong:** CoinGecko's 429 cooldown is minutes-scale and headerless (diagnosis) — sub-second retries re-trigger the limiter and prolong the block.
**Do this instead:** LPM-07 — retry only timeout/reset/DNS; 403 falls through immediately; 429 falls through without any sub-minute retry.

### Anti-Pattern 2: Feeding non-200 bodies to the JSON parser

**What people do:** `HTTPDevice` returns body regardless of status (`HTTPCommon.cpp:255ff`), so 403 HTML becomes "JSON Parse Error: 3".
**Why it's wrong:** operators never see the real status; classification (blocked vs. transient) is impossible.
**Do this instead:** LPM-05 — Beast client checks `res.result()` first; non-2xx never reaches rapidjson; the logged error contains the integer status.

### Anti-Pattern 3: Fixing `FileManager`/`HTTPDevice` in place

**What people do:** "just surface status codes in the shared loader."
**Why it's wrong:** every MNN/IPFS/SFTP loader consumer changes behavior at once — a cross-cutting risk this milestone forbids (out-of-scope table, REQUIREMENTS.md).
**Do this instead:** new Beast client scoped to `coinprices`; AsyncIOManager untouched (its dead verify-peer toggle logged as a known pre-existing issue, STACK.md).

### Anti-Pattern 4: Inserting config fields mid-struct

**What people do:** add `PriceEndpoint` to `DevConfig` next to related fields.
**Why it's wrong:** `GeniusNodeConfig` is an aggregate initialized *positionally* at every test call site (e.g. `account_management_test.cpp:78`, `:168`, `:171` — `{ "0xcafe", "0.35", "1.0", TOKEN_ID, path }`) and parsed by name in `GeniusSDK.cpp:91` (`ParseDevConfig`). Mid-struct insertion breaks all of them silently.
**Do this instead:** env vars primary (`SGNS_PRICE_COINGECKO_URL`, `SGNS_PRICE_SERVICE_URL`) read once at manager construction, plus a `SetPriceEndpoints(...)` injection method on `GeniusNode` following the `SetChainlistFetcher` precedent (`GeniusNode.hpp:903`, impl `GeniusNode.cpp:3838`); if a struct field is ever added, append it **last** with a default.

### Anti-Pattern 5: One request per token id

**What people do:** call `/simple/price` per id.
**Why it's wrong:** N× the rate-limit exposure for data one query returns.
**Do this instead:** LPM-03 — union the coalescing window's ids into one `ids=a,b,c&vs_currencies=usd` call (already the shape today's code builds at `coinprices.cpp:137`).

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| CoinGecko `/simple/price` | Direct HTTPS from C++ (Tier A) *and* from Worker upstream | Keyless from clients (SRVC-06); Worker key via secret binding only; expect 403/429 without headers — never rely on `x-ratelimit-*` |
| `token.gnus.ai` Worker | HTTPS `GET /v1/prices` from C++ (Tier B) | Code+tests only this milestone (DEPLOY-01 deferred); C++ parses the documented envelope, so Phase 2/3 develop against the contract without the Worker deployed |

### Internal Boundaries

| Boundary | Communication | Verified anchor |
|----------|---------------|------------------|
| `GetProcessCost` ↔ `GetGNUSPrice` ↔ `GetCoinprice` | Direct C++ calls — **unchanged** | `GeniusNode.cpp:2797`, `:2828`, `:3510`; decls `hpp:373`, `:397`, `:822` |
| `GetCoinprice` ↔ `PriceManager` | New direct delegation (replaces retriever + node cache) | `GeniusNode.cpp:3510-3561` rewritten; cache members `hpp:1481-1490` removed |
| `genius_node` ↔ `coinprices` | Existing CMake link — no new wiring | `SuperGenius/src/CMakeLists.txt:19` (`GENIUS_NODE_LIBS`), `:57`; `src/account/CMakeLists.txt:92-97,104-106` |
| `coinprices` ↔ Boost.Beast/OpenSSL | New PRIVATE links in module CMake | `src/coinprices/CMakeLists.txt` (currently `Boost::headers`+`outcome`+`logger` PUBLIC, `rapidjson`+`AsyncIOManager` PRIVATE); add `Boost::system`, `OpenSSL::SSL`; precedent `test/src/price_retrieval/CMakeLists.txt:9-12` already links `OpenSSL::SSL` for Beast on every CI platform |
| Tests ↔ stub server | In-process Beast server, env-var endpoint override | `addtest` conventions `SuperGenius/cmake/functions.cmake:8`; `account_management_test` link line `test/src/account/CMakeLists.txt:39` gains the helper; aarch64-Debug exclusion `SuperGenius/.github/workflows/cmake.yml:649` removed in Phase 5 |
| Worker ↔ C++ build | **None** — directory invisible to CMake | `tokenpriceservice/` sibling of `src/`; CI path filter keeps Node setup off C++-only PRs (TEST-06) |
| GeniusSDK | **Zero changes** | `GeniusSDK.cpp:350-369` (`GeniusSDKGetGNUSPrice`), `:707/:728` compile untouched (LPM-10) |
| Historical price APIs | Kept compiling behind existing surface | `GeniusNode.cpp:3567` (`GetCoinPriceByDate`), `:3575` (`GetCoinPricesByDateRange`) — explicitly out of scope |

## Suggested Build Order (dependency-respecting)

Mirrors the existing ROADMAP phases; the dependency reasoning:

1. **Phase 1 — Worker service** (independent). No C++ dependency; pins the envelope contract `{currency, prices, fetchedAt, age, source, stale}` that Phase 3's Tier B parses. Also front-loads the riskiest unfamiliar toolchain (vitest-plugin, SQLite DO, `new_sqlite_classes`).
2. **Phase 2 — Beast client + `PriceQuote` + stub server** (parallel with Phase 1; no hard dep). Envelope parsing targets the *documented* contract; stub-server and retry/tls tests are contract-independent. Produces the injectable client interface Phase 3 fakes.
3. **Phase 3 — `PriceManager`** (depends on Phase 2: types, client interface, band classifier). Pure orchestration, zero sockets (TEST-02 fake).
4. **Phase 4 — GeniusNode cutover + hermetic tests** (depends on Phase 3). Seam delegation, config surface (env + setter), retire retriever/cache members, convert `SetPayoutAddress` and `price_retrieval_test` to the stub.
5. **Phase 5 — CI** (depends on Phase 1 tests existing and Phase 4 hermeticity being proven). `worker-tests` job; remove the `cmake.yml:649` exclusion and verify the aarch64-Debug leg.

Critical path: **2 → 3 → 4 → 5** (C++ chain); Phase 1 can run concurrently with 2–3 and must merely land before Phase 5's `worker-tests` job.

## Sources

- Verified workspace source this pass:
  - `SuperGenius/src/account/GeniusNode.cpp` — `:229-296` (io_context + 4-thread pool), `:237` (cache init), `:2797-2826` (`GetProcessCost`), `:2828-2843` (`GetGNUSPrice`), `:3510-3561` (`GetCoinprice`), `:3567/:3575` (historical), `:3838` (`SetChainlistFetcher` impl), `:2206-2242` (teardown ordering)
  - `SuperGenius/src/account/GeniusNode.hpp` — `:76-88` (`DevConfig` aggregate), `:373/:397/:822` (seam decls), `:903` (injection precedent), `:1481-1490` (price cache members)
  - `SuperGenius/src/coinprices/coinprices.{hpp,cpp}` + `CMakeLists.txt` — full read
  - `SuperGenius/src/CMakeLists.txt:19,57`; `SuperGenius/src/account/CMakeLists.txt:91-131`
  - `SuperGenius/test/src/price_retrieval/CMakeLists.txt` + `price_retrieval_test.cpp` (Beast already linked; not CTest-registered)
  - `SuperGenius/test/src/account/CMakeLists.txt:35-61,314`; `account_management_test.cpp:77-78,136,167-171,333,352`
  - `SuperGenius/.github/workflows/cmake.yml:633-667` (aarch64-Debug `GTEST_FILTER` exclusion at `:649`)
  - `thirdparty/AsyncIOManager/src/HTTPCommon.cpp:72,128-131,196,255ff` (UA hard-coded, verify-peer dead toggle, headers/status stripped)
  - `GeniusSDK/src/GeniusSDK.cpp:91,350-369,707,728`
- `.planning/workstreams/tokenprice/research/STACK.md` (toolchain pins, CA-bundle decision, worker layout, CI sketch)
- `.planning/workstreams/tokenprice/REQUIREMENTS.md` + `ROADMAP.md` (requirement IDs, phase mapping)
- `.planning/research/pricing_coordinator.md` (hybrid design reference)
- `/memories/repo/coingecko-price-api-frontend.md` (403/429 diagnosis motivating the design)

---
*Architecture research for: PriceCoordinator — Local Manager + token.gnus.ai Fallback (workstream: tokenprice)*
*Researched: 2026-09-29*
