# Phase 4: GeniusNode Integration & Hermetic Tests - Research

**Researched:** 2026-10-01
**Domain:** C++ node integration (Boost.Asio/C++17) — seam cutover, env-var configuration, hermetic test conversion
**Confidence:** HIGH (all code-state claims verified by direct file reads this session; line numbers are current as of HEAD `a3192a2ce` on `SuperGenius` branch `dev_tokenprice`)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Endpoint configuration (LPM-09)**
- **D-01:** Endpoint base URLs are configured via **environment variables only** — no `GeniusNodeConfig` fields, no `sgns_config.json` keys. Precedent: the in-tree `SGNS_CONSOLE_LOG_TESTS` / `SGNS_DEBUGLOGS` env gates. `GeniusNodeConfig` stays untouched (it is a brace-initialized aggregate; appending fields would touch every construction site for no benefit).
- **D-02:** **Tier-specific names** (exact strings planner's discretion, `SGNS_COINGECKO_URL` / `SGNS_PRICE_FALLBACK_URL` expected): one var for the tier-1 CoinGecko base URL, one for the tier-2 token.gnus.ai base URL. A test can redirect each tier independently — distinct hosts or one host with distinct paths.
- **D-03:** Env is read **at manager construction**; tests set the env vars **before `GeniusNode::New()`** (Windows `SetEnvironmentVariable` / POSIX `setenv`), restoring in teardown. No post-construction setter method is added. Consequence: the `AccountManagement` fixture (which builds `node_` in its ctor) sets the env vars in its **fixture constructor before `GeniusNode::New`**, redirecting every node the suite constructs — that is desired; the whole suite becomes hermetic.
- **D-04:** **Scheme in the URL decides transport security.** A stub base URL (`http://127.0.0.1:PORT`) speaks plain HTTP via Phase 2's plain-HTTP support; TLS + pinned-CA verification applies only to production `https://` defaults. No test certificates, no TLS stub.

**Seam cutover mechanics (LPM-10)**
- **D-05:** GeniusNode holds a **lazy `std::shared_ptr<LocalPriceManager>`** — constructed on the first price call (`GetCoinprice`), not in the node constructor. Node startup stays light: no runner thread until a price is actually needed; suites that never touch prices pay nothing. The manager's destructor (drain-then-join per Phase 3 D-02) handles teardown — planner places its release in `~GeniusNode`'s ordered teardown so the runner thread joins before the io/threads machinery it may reference goes away.
- **D-06:** **Delete the old state outright:** `m_tokenPriceCache`, `m_lastApiCall`, `MIN_API_CALL_INTERVAL`, the `PriceInfo` cache struct, and `GetCoinprice`'s miss-collection loop all disappear from `GeniusNode.hpp/.cpp`. The manager's L1 supersedes them. No dead members left behind.
- **D-07:** **Partial-map semantics preserved:** `GetCoinprice` returns the map of prices it has (fresh or fetched); an id the chain couldn't serve is simply **absent** from the map; failure is returned only when **nothing** is servable — exactly today's partial-data behavior and Phase 3's `GetQuotes` partial-success semantics. `GetGNUSPrice`'s existing finite/positive `genius-ai` check then yields `NO_PRICE` when absent — that validation is untouched.
- **D-08 (carried from Phase 3, binding here):** `GetQuotes` must never be called from the manager's own runner thread (future-wait self-deadlock). All node-side callers (`GetProcessCost` path, gRPC-free) are off-thread — safe by construction; the planner should note this constraint in the seam wiring.

**Retriever retirement**
- **D-09 (user decision, overriding REQUIREMENTS wording):** `CoinGeckoPriceRetriever` is **deleted entirely** — the whole class, `getCurrentPrices`/`getCurrentPricesOnce`, the historical methods (`getHistoricalPrices`/`getHistoricalPriceRange`), `decodeChunkedTransfer`, `formatDate` — and with it the `GeniusNode::GetCoinPriceByDate`/`GetCoinPricesByDateRange` forwarding seams. Zero consumers verified.

**Hermetic test shapes (TEST-04/TEST-05)**
- **D-10:** `price_retrieval_test` is **rewritten as a stub-driven integration suite**: it drives the real wired path — `GeniusNode::GetCoinprice` (or the seam as wired) against `HttpStubServer` with env-var redirection — and gets **registered with CTest**. Historical-endpoint tests are deleted with the retriever (D-09).
- **D-11:** **One stub instance, both tiers:** both env vars point at the same `HttpStubServer`, distinguished by scripted paths — `/api/v3/simple/price` (CoinGecko shape, tier 1) and `/v1/prices` (Phase 1 envelope shape, tier 2).
- **D-12:** `account_management_test` sets the env vars in its **fixture constructor before any `GeniusNode::New`**, both tiers → the shared stub with a valid `genius-ai` price scripted. The 3-node topology, escrow flow, and all assertions stay untouched — only the price source changes.
- **D-13:** The rewritten integration suite includes a **warm-then-fail script**: the stub's first responses succeed (populating the manager's L1/LKG), then a scenario flips the stub to 403-HTML/429 — the fallback tier or stale-served LKG keeps `GetCoinprice` serving.

### Claude's Discretion
- Exact env-var names (D-02 fixes the tier-specific shape; strings follow the `SGNS_*` convention).
- Where/how the env read is implemented (free function in the coinprices module vs. inline in the lazy-ctor site) and whether unset-env falls back to constants shared with tests.
- The lazy-manager construction site's exact shape (member function `GetOrCreatePriceManager()` vs. inline `if (!priceManager_)` in `GetCoinprice`).
- Placement of the manager reset within `~GeniusNode`'s ordered teardown (constraint: runner thread joins before members it could reference are gone).
- How much of `coinprices.hpp/.cpp` remains after D-09 (module keeps only the Phase 2/3 files; the `CoinPrices` logger tag stays) — planner decides file disposition.
- The rewritten `price_retrieval_test`'s internal organization (which scenarios as separate TEST_Fs) and its CMake registration mechanics (`addtest`).
- Fixture env save/restore helpers (test-local RAII or gtest Environment) — must not leak redirecting env into other suites in the same ctest shard.
- Assertion style for fallback/LKG scenarios through the seam.

### Deferred Ideas (OUT OF SCOPE)
- CI workflow changes (`worker-tests` job, aarch64-Debug exclusion removal + MNN/Vulkan thirdparty rider): Phase 5.
- Live end-to-end test (real `wrangler dev` worker + C++ manager over loopback): future milestone.
- Config-file operability for price endpoints (`sgns_config.json`/`GeniusNodeConfig`): rejected for v1 per D-01.
- Second hold-off timer for the token.gnus.ai tier.

### Requirements Corrections (planner must apply)
- REQUIREMENTS.md Out-of-Scope "Historical price endpoints kept compiling" is **superseded by D-09** (deleted this phase); update the table wording when Phase 4 lands.
- Plan seed 04-01's "`CoinGeckoPriceRetriever` retired or reduced to what still compiles" resolves to **deleted entirely** (D-09).
- TEST-04's "exclusion removed" clause remains Phase 5 scope. Phase 4 delivers only the hermetic-conversion clause.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| LPM-09 | Price endpoint base URL(s) configurable (env var) with CoinGecko defaults, so tests point at a local stub | Env-read pattern (§Env-Var Precedent), default constants, `PriceHttpClientSource` ctor params verified; manager construction timing (lazy, first `GetCoinprice`) verified |
| LPM-10 | `GeniusNode::GetGNUSPrice`/`GetCoinprice` seam preserved: same `outcome::result` surface, finite/positive validation unchanged, `GetProcessCost` compiles/passes unmodified | Full call-chain read (`GetProcessCost`→`GetGNUSPrice`→`GetCoinprice`), error-category mechanics, partial-map semantics, all external call sites enumerated (§Seam Cutover Map) |
| TEST-04 | `account_management_test.SetPayoutAddress` runs hermetically against the local stub (hermetic-conversion clause only) | Fixture ctor structure, per-test fixture lifetime, CMake link pattern, env set-before-`New` ordering constraints verified (§Test Conversion) |
| TEST-05 | `price_retrieval_test` replaced by hermetic, CTest-registered equivalents (no live CoinGecko) | Current unregistered state confirmed; `addtest` mechanics; `HttpStubServer` API; heavyweight-node-link requirements documented (§Test Conversion) |
</phase_requirements>

## Summary

Phase 4 is a surgical cutover with an unusually clean blast radius. Everything the phase wires together already exists and is tested: `LocalPriceManager` (blocking `GetQuotes`, own ioc + runner thread + drain-join dtor), `PriceHttpClientSource` (production `IPriceSource` adapter taking a base-URL ctor param), and `HttpStubServer` (per-path scripting, OS-assigned port). The production-side new code is tiny: one env-read (two `std::getenv` calls with production-default fallbacks), one lazy-manager member + construction helper in `GeniusNode`, one mapping from `PriceResult<std::vector<PriceQuote>>` to `outcome::result<std::map<std::string,double>>` preserving partial-map semantics, and a dtor release. The deletion side (`CoinGeckoPriceRetriever` + its two forwarders + four `GeniusNode` cache members + one ctor-init entry) is verified to have exactly two consumers: `GeniusNode.cpp` itself and `price_retrieval_test` — nothing in gRPC, SGProcessingManager, GeniusSDK source, or api/ touches it. `NodeExample.cpp:446` calls `GetCoinprice` (the seam, which survives) and GeniusSDK calls `GetGNUSPrice`/`GetProcessCost` (both survive unmodified).

The two test conversions are where the subtlety lives. Three verified landmines matter most to the planner: (1) **env-set/see consistency on Windows** — MSVC's `getenv` reads the CRT environment copy, so tests should set vars with `_putenv_s` (not Win32 `SetEnvironmentVariable`) to guarantee the production `std::getenv` read sees the redirect; (2) **stub-port-before-env ordering** — the env value embeds the stub's OS-assigned port, so the fixture must start the stub *then* set env *then* `GeniusNode::New`; (3) **the Release vs Debug build-tree split** — the Phase 2/3 price suites are registered only in `build/Windows/Release` (tests #98–101); the Debug tree is stale (147 tests, no price suites). All Phase 4 verification should target the Release tree.

One CONTEXT.md assumption needs correcting for the planner: `ReleaseRuntimeMembersAfterIoStopped()` (GeniusNode.cpp:2062) currently has **zero callers** — it is dead scaffolding; the live teardown mechanism is the destructor body plus implicit reverse-declaration-order destruction of the ownership-order member block (GeniusNode.hpp:954–1106). The lazy manager (which owns its *own* ioc/thread and references no node members) can therefore be released either explicitly early in the `~GeniusNode` body (recommended — bounded and deterministic; the manager dtor resolves any parked `GetQuotes` waiters) or via declaration-order placement; both are safe.

**Primary recommendation:** Implement the env read as free functions in the coinprices module (production constants `https://api.coingecko.com` / `https://token.gnus.ai`, unset → defaults), cut `GetCoinprice` over to a lazily-constructed manager via a `GetOrCreatePriceManager()` helper with explicit reset at the top of `~GeniusNode` after `ShutdownForDestruction()`, delete D-06/D-09 state, and convert both suites with per-test fixtures (fresh stub → set env via CRT-family calls → `GeniusNode::New` → assertions → restore env in fixture dtor).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Endpoint base-URL configuration | coinprices module (env-read free fn) | — | Read at manager construction (D-03); keeping it in the module lets tests and any future consumer share the constants; no node-level config churn (D-01) |
| Price cache + fetch orchestration | `LocalPriceManager` (Phase 3, unchanged) | — | Already owns L1/coalescing/fallback; node-level cache members are deleted (D-06) |
| `GetCoinprice` seam surface | `GeniusNode` (adapter only) | — | Signature, partial-map semantics, and error surface stay; body becomes map-building over `GetQuotes` |
| `GetGNUSPrice` / `GetProcessCost` | `GeniusNode` (untouched) | — | LPM-10's acceptance proof: compile and pass unmodified |
| Manager lifecycle (lazy ctor + teardown) | `GeniusNode` | `LocalPriceManager` dtor | Node starts light (D-05); manager drain-joins its own thread; explicit release in `~GeniusNode` |
| HTTP stub + scripting | `test/testutil/http_stub` (`price_test_support`) | — | Existing Phase 2 asset; both tiers via one instance (D-11) |
| Env set/restore in tests | per-suite RAII helper (new, test-local) | — | No existing in-tree helper (verified); must be leak-free across the ctest shard |

## Standard Stack

### Core (all existing — zero new dependencies this phase)

| Library/Component | Version | Purpose | Why Standard |
|---|---|---|---|
| `LocalPriceManager` | Phase 3 (HEAD) | Blocking `GetQuotes(ids, currency)`; strand-serialized L1; drain-join dtor | The component being wired; ctor `(coinGeckoTier, gnusServiceTier, coalescingWindow=50ms, now)` takes tier `IPriceSource`s — base URLs are baked into the adapters, not the manager |
| `PriceHttpClientSource` | Phase 3 (header-only) | Production tier adapter; ctor `(ioc, baseUrl, RetryConfig{}, holdOff=60s, clock, requestTimeout=5000ms, ResponseFormat)` | The env read feeds exactly its `baseUrl` and `responseFormat` params |
| `PriceHttpClient` | Phase 2 | Scheme decides TLS (`http://`→plain — D-04 satisfied by construction); builds `/api/v3/simple/price?ids=..&vs_currencies=..` or `/v1/prices?ids=..&vs=..` | Verified `PriceHttpClient.cpp:66-99` |
| `HttpStubServer` / `price_test_support` | Phase 2 | Scriptable stub; `OnPath/Start/Port/Url/Shutdown/LastUserAgent` | Verified API incl. query-string stripping (path-only script keys) — makes D-11's one-stub-both-tiers work |
| `std::getenv` (POSix/CRT) | C++ std | Production env read | Matches the in-tree runtime env-read precedent (`SGNS_E2E_REAL_RPC`, `mock_transport_factory.hpp:41`) |

**Installation:** none — no new packages, files only. `coinprices` CMake target persists; only its source list shrinks (drop `coinprices.cpp`).

## Package Legitimacy Audit

Not applicable — this phase installs **zero external packages** (milestone-wide decision: zero new vendored thirdparty; everything needed is in-tree). No registry lookups required.

## Architecture Patterns

### System Architecture Diagram — the cutover

```mermaid
flowchart TD
    subgraph tests["Test process (per-test fixture)"]
        F["Fixture ctor:<br/>1. stub.Start()  → Port()<br/>2. set SGNS_COINGECKO_URL=http://127.0.0.1:P<br/>   set SGNS_PRICE_FALLBACK_URL=http://127.0.0.1:P<br/>3. GeniusNode::New(...)"]
        FDTOR["Fixture dtor:<br/>restore env vars"]
    end

    subgraph node["GeniusNode (production)"]
        PC["GetCoinprice(ids)<br/>outcome::result<map<string,double>>"]
        LAZY["GetOrCreatePriceManager()  [lazy, D-05]<br/>reads env (D-01/D-03) →<br/>PriceHttpClientSource(tier1 URL, CoinGeckoSimplePrice)<br/>PriceHttpClientSource(tier2 URL, GnusEnvelope)<br/>→ LocalPriceManager(t1, t2)"]
        GP["GetGNUSPrice()<br/>{'genius-ai'} + finite/positive check → NO_PRICE  (untouched)"]
        GC["GetProcessCost(procmgr)  (untouched)"]
        PI["ProcessImage(json)  (untouched)"]
        DTOR["~GeniusNode:<br/>ShutdownForDestruction() →<br/>price_manager_.reset()  [recommended slot] →<br/>pubsub Stop → io stop/join → ..."]
    end

    subgraph mgr["LocalPriceManager (Phase 3, unchanged)"]
        GQ["GetQuotes(ids, currency)  [BLOCKING, D-08: never on runner thread]"]
        L1["L1 cache / coalescing / 4-tier fallback"]
    end

    subgraph wire["Wire"]
        T1["PriceHttpClient tier1<br/>GET {base1}/api/v3/simple/price?ids=..&vs_currencies=usd"]
        T2["PriceHttpClient tier2<br/>GET {base2}/v1/prices?ids=..&vs=usd  (envelope)"]
    end

    subgraph stub["HttpStubServer (tests only)"]
        S1["script '/api/v3/simple/price' → 200 {\"genius-ai\":{\"usd\":0.19}}<br/>or 403-HTML / 429 (D-13 warm-then-fail)"]
        S2["script '/v1/prices' → 200 envelope JSON"]
    end

    GC --> GP --> PC
    PI --> GC
    PC -->|"first call"| LAZY
    PC -->|"every call"| GQ
    LAZY --> GQ
    GQ --> L1 --> T1
    L1 -->|"tier1 fail / gap"| T2
    T1 -.->|"env redirect (tests)"| S1
    T2 -.->|"env redirect (tests)"| S2
    F --> node
    FDTOR --> F
```

### Pattern 1: Runtime env-read with production-default fallback
**What:** free functions in the coinprices module; unset or empty → production constant.
**When to use:** the only new production config surface (LPM-09).
In-tree precedent (verified, `SuperGenius/test/src/mock/mock_transport_factory.hpp:34-45`):
```cpp
inline bool UseRealRpcTransport()
{
    static const bool kUseReal = []()
    {
        const char *env = std::getenv( "SGNS_E2E_REAL_RPC" );
        return env != nullptr && std::string( env ) == "1";
    }();
    return kUseReal;
}
```
The production version must **not** cache in a `static` (unlike the test helper) — D-03 requires the read at manager construction, and a static would freeze the first read process-wide, breaking per-test redirection in suites that construct nodes with different stub ports in one process.

### Pattern 2: Lazy service construction (D-05)
**What:** member `std::shared_ptr<LocalPriceManager> priceManager_;` + private helper:
```cpp
// Source: adapted from the node's lazy-construction conventions (e.g. blockchain_ guards)
std::shared_ptr<LocalPriceManager> GeniusNode::GetOrCreatePriceManager()
{
    if ( !priceManager_ )
    {
        priceManager_ = std::make_shared<LocalPriceManager>(
            std::make_shared<PriceHttpClientSource>( /*ioc*/ ..., PriceEndpoints::CoinGeckoBaseUrl(),
                                                     ..., ResponseFormat::CoinGeckoSimplePrice ),
            std::make_shared<PriceHttpClientSource>( ..., PriceEndpoints::FallbackBaseUrl(),
                                                     ..., ResponseFormat::GnusEnvelope ) );
    }
    return priceManager_;
}
```
Note (verified from `PriceHttpClientSource.hpp`): the adapter takes the **manager's** ioc, but the manager builds its ioc internally — so the adapters cannot be constructed before the manager exists. The construction must happen as: create the two sources closing over a placeholder ioc? **No** — correct order is: `auto ioc = make_shared<io_context>()` is *inside* the manager. Resolution options for the planner: (a) give `LocalPriceManager` a factory-parameter form — but that modifies Phase 3 code (avoid); (b) construct the manager first with the sources receiving the manager's ioc — chicken-and-egg; (c) **verified workable**: `PriceHttpClientSource` stores the ioc shared_ptr and only forwards it in `FetchPrices`; `PriceHttpClient` itself builds a **fresh per-attempt ioc** anyway (`PriceHttpClient.cpp:109` — "Fresh context per attempt"; the passed ioc is currently vestigial, documented in `PriceHttpClientSource.hpp`). Therefore the sources can be constructed with **any** ioc (e.g., a fresh throwaway) with zero runtime effect today; or simpler — pass `std::make_shared<boost::asio::io_context>()` from the lazy-ctor site. The vestigial-ioc note in `PriceHttpClientSource.hpp` explicitly says "do not build machinery around that parameter." Recommend: sources get a dedicated throwaway ioc each (or one shared), documented as satisfying D-02/D-04 construction wiring with zero runtime effect.

### Pattern 3: Per-test fixture with env redirect (D-03/D-12)
**What:** fixture ctor orders: stub start → env set → `GeniusNode::New`; fixture dtor restores env. gtest constructs/destructs the fixture around **each** TEST_F — verified the `AccountManagement` ctor (account_management_test.cpp:63-85) already runs per-test (its `next_test_index` counter depends on it), so every test gets a fresh node **and a fresh lazily-constructed manager** — no L1/hold-off carryover between tests in a suite.

### Pattern 4: `addtest()` CTest registration
**What:** `SuperGenius/cmake/functions.cmake:8-39` — `add_executable` + `add_test` with xunit XML output, TIMEOUT 600, output to `${CMAKE_BINARY_DIR}/test_bin`, Vulkan DLL copy on WIN32, gtest_main link. Existing precedent: `test/src/price_facade/CMakeLists.txt` (one `addtest` + link block) is the minimal registered-suite shape; `test/src/account/CMakeLists.txt:36-60` is the heavyweight genius-node-linking shape (addtest + `target_link_libraries(... genius_node_test json_secure_storage)` + platform WHOLEARCHIVE block).

### Anti-Patterns to Avoid
- **Caching the env read in a function-local static** (breaks per-test port redirection).
- **Setting test env with Win32 `SetEnvironmentVariable` while production reads `std::getenv`** (CRT-copy mismatch — see Pitfall 1).
- **Keeping any "just in case" forwarding shim to the deleted retriever** (D-09 is a full delete; the REQUIREMENTS Out-of-Scope wording is superseded).
- **Calling `GetQuotes` from anything that might run on the manager's strand** (self-deadlock; D-08 — the manager asserts it in debug).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---|---|---|---|
| Price caching/fetching logic | Any node-side cache remnants | `LocalPriceManager` (delete `m_tokenPriceCache` etc., D-06) | Manager's L1 supersedes; keeping both creates two sources of truth for freshness |
| URL parsing/validation of env values | Custom URL validator | `PriceHttpClient`'s existing `parseHTTPUrl` path (`PriceHttpClient.cpp:66-79` — malformed base URL → `PriceFetchFailure`) | Already tested (Phase 2); malformed env values fail truthfully, not catastrophically |
| HTTP stub / scripting | New fake server | `HttpStubServer` via `price_test_support` | Phase 2 asset; per-path status/body/hang scripting, UA capture, port OS-assigned |
| Env save/restore | Ad-hoc set/unset pairs | (Must be written — no in-tree helper exists; verified.) One small RAII guard header in the test tree | The only hand-rolled piece; keep it ~30 lines, CRT-family setters, restore-exact-state-in-dtor |
| Map adaptation quotes→prices | A new cache/DTO layer | Direct loop: `for (q : quotes) map[q.asset] = q.price;` | One quote per requested id by construction (Phase 3 semantics) |

## Common Pitfalls

### Pitfall 1: Windows CRT-vs-Win32 environment mismatch (D-03 wording correction)
**What goes wrong:** CONTEXT.md D-03 names `SetEnvironmentVariable` for Windows. MSVC's `getenv` family reads **the CRT's copy of the environment** (`_environ`), not the raw process environment segment; changes made with Win32 `SetEnvironmentVariable` are not guaranteed visible to `getenv`, and vice versa `_putenv` changes are not guaranteed visible to Win32 `GetEnvironmentVariable`. [CITED: learn.microsoft.com/cpp/c-runtime-library/reference/getenv-wgetenv — "getenv and _putenv use the copy of the environment pointed to by the global variable _environ … operates only on the data structures accessible to the run-time library and not on the environment segment created for the process by the operating system."]
**How to avoid:** Production reads with `std::getenv` (portable). Tests **set/unset with the matching CRT family**: `_putenv_s(name, value)` / `_putenv("NAME=")` to remove, on Windows; `setenv`/`unsetenv` on POSIX. One `#ifdef _WIN32` RAII guard covers both. Also note MSVC emits C4996 for `getenv` in some configs — in-tree code already uses `std::getenv` freely (mock_transport_factory.hpp) and no `/WX` was found in the compiler options, so no suppression needed.
**Warning signs:** test redirects env but the node still hits production CoinGecko (fetch timeouts, flaky suite) — classic symptom of the two-copy split.

### Pitfall 2: Stub-port-before-env ordering dependency
**What goes wrong:** the env value is `http://127.0.0.1:<port>` where the port is OS-assigned at `stub.Start()`. Setting env before `Start()` embeds a wrong port.
**How to avoid:** fixture ctor sequence is strictly: (1) `stub_.Start();` (2) set both env vars from `stub_.Url("")` base; (3) `GeniusNode::New(...)`. (Lazy manager construction also gives slack — env is read at the *first `GetCoinprice`*, not at `New` — but do not rely on that; keep D-12's strict order.)

### Pitfall 3: Empty-ids semantics change at the seam
**What goes wrong today's-way vs tomorrow's-way:** current `GetCoinprice({})` returns **success with an empty map** (loop finds nothing to fetch; retriever never called). `LocalPriceManager::GetQuotes({})` returns **failure `EmptyInput`** (facade parity, verified `LocalPriceManager.cpp:82-87`). If the adapter propagates that failure, `GetCoinprice({})` changes from success-empty-map to error — a silent surface break nobody tests today.
**How to avoid:** the seam adapter short-circuits empty input → `outcome::success({})` before calling `GetQuotes`. (`GetGNUSPrice` never passes empty; `NodeExample cmd_price` guards args; but the seam contract is preserved.)

### Pitfall 4: Losing the partial-map error mapping
**What goes wrong:** mapping manager failure 1:1 onto the retriever's old `PriceError` (deleted with D-09) or dropping the error entirely.
**How to avoid:** verified current behavior (GeniusNode.cpp:3548-3560): fetch failure + non-empty cached result → **success with partial data**; failure + nothing → **error**. Manager mirrors this (`NothingServableSurfacesLastTierFailure` in price_manager_test). Adapter rule: `GetQuotes` success → map from returned quotes (requested-but-absent ids stay absent — D-07); `GetQuotes` failure → `outcome::failure(Error::NO_PRICE)` (natural in-category mapping; `GetGNUSPrice` re-validates and maps to `NO_PRICE` anyway, and `GetProcessCost` only checks has_error). Exact error-code choice is planner's discretion within the untouched-surface constraint.

### Pitfall 5: Behavior delta — `MIN_API_CALL_INTERVAL` throttling disappears
**What goes wrong:** today a second `GetCoinprice` within 5s of the last API call serves **cache-only** (possibly an empty map for fresh misses). The manager replaces this with 60s freshness bands + 50ms coalescing + 429 hold-off. Nothing in the current test tree asserts the 5s throttle (verified — only account/SetPayoutAddress and the live smoke suite touch prices), but anyone reading old behavior docs could "restore" it.
**How to avoid:** delete the members (D-06) and do not re-add throttling; the manager owns pacing now.

### Pitfall 6: 429 hold-off and L1 state leaking across tests
**What goes wrong:** tier-1 429 arms a **60s hold-off** inside that manager's `RateLimitHoldOff`; a warm L1 persists in the manager. If a suite shared one node/manager across TEST_Fs, a 429 in test A would skip CoinGecko-tier in test B.
**How to avoid:** per-test fixtures (gtest default) construct a fresh node → fresh lazy manager per test. Verified `AccountManagement` already works this way. Within `SetPayoutAddress`, three nodes exist but only `node_requester` ever calls `GetProcessCost` → only one manager exists. Also true for the warm-then-fail scenario (D-13): re-scripting the same path with `OnPath` mid-test is safe (mutex-guarded, verified) — the flip happens on one manager deliberately.

### Pitfall 7: Verifying in the stale Debug build tree
**What goes wrong:** `build/Windows/Debug` predates Phase 2 — `ctest -N` there lists 147 tests with **no** price suites (only `price_retrieval_test.exe` built from the live code sits in test_bin); `build/Windows/Release` is current (tests #18 account_management_test, #98-101 price_quote/price_http_client/price_facade/price_manager).
**How to avoid:** run all Phase 4 verification in the **Release** tree (commands in §Environment Availability). If Debug runs are wanted, a reconfigure is needed first.

### Pitfall 8: Deleting `coinprices.cpp` without its CMake entry
**What goes wrong:** link failure or stale-archive confusion.
**How to avoid:** `SuperGenius/src/coinprices/CMakeLists.txt:2-7` `add_library(coinprices coinprices.cpp PriceRetryPolicy.cpp PriceHttpClient.cpp PriceResponseParsers.cpp LocalPriceManager.cpp)` — remove `coinprices.cpp` from the list; keep the target name (GeniusSDK vcxproj files reference `coinprices.lib` — build artifacts regenerate; no GeniusSDK source changes needed since its call sites are the surviving seams, verified `GeniusSDK.cpp:359,707,728`).

### Pitfall 9: Manager teardown slot (CONTEXT correction)
**What goes wrong:** planning the release around `ReleaseRuntimeMembersAfterIoStopped()` — which has **zero callers today** (verified: only definition at GeniusNode.cpp:2062 and declaration at hpp:1387 exist in the entire src+test tree). The live teardown is the `~GeniusNode` body (cpp:2199-2274: `ShutdownForDestruction()` → pubsub keepalive/Stop → `io_->stop()` → join io threads → upnp join → sleep → implicit reverse-order member destruction).
**How to avoid:** the manager owns its own ioc/thread and references **no** node members — so the simplest deterministic slot is an explicit `priceManager_.reset()` in the `~GeniusNode` body right after `ShutdownForDestruction()` (before `pubsub_->Stop()`): any parked `GetQuotes` waiter is resolved with NetworkError by the manager dtor (verified LocalPriceManager.cpp:39-68) and the runner thread joins while the node is fully intact. Declaration-order-only placement also works (declare the member among the *last* privates so it dies first) but relies on implicit ordering. Recommend the explicit reset.

### Pitfall 10: `HttpStubServer` script keys are path-only
**Verified good news, but worth knowing:** the stub strips query strings when matching scripts (`HttpStubServer.cpp:129-133`), so `/api/v3/simple/price?ids=genius-ai&vs_currencies=usd` matches the `/api/v3/simple/price` script. This is what makes D-11's one-stub-both-tiers (same host:port, distinct paths) work without query-aware scripting.

## Code Examples

### The seam adapter (core of plan 04-01)
```cpp
// Source: synthesized from verified current code —
//   GeniusNode.cpp:3510-3563 (today's GetCoinprice, partial-data semantics)
//   LocalPriceManager.hpp:88-97 (GetQuotes surface)
//   PriceHttpClientSource.hpp (tier ctor) / PriceHttpClient.cpp:66-99 (scheme+targets)
outcome::result<std::map<std::string, double>> GeniusNode::GetCoinprice( const std::vector<std::string> &tokenIds )
{
    if ( tokenIds.empty() )
    {
        return std::map<std::string, double>{}; // preserve today's empty-in → empty-map success (Pitfall 3)
    }
    auto quotesResult = GetOrCreatePriceManager()->GetQuotes( tokenIds, "usd" );
    if ( !quotesResult )
    {
        node_logger_->error( "GetCoinprice failed: {}", quotesResult.error().Message() );
        return outcome::failure( Error::NO_PRICE ); // planner's-discretion mapping; GetGNUSPrice re-maps anyway
    }
    std::map<std::string, double> result;
    for ( const auto &quote : quotesResult.value() )
    {
        result[quote.asset] = quote.price; // absent ids stay absent (D-07 partial-map)
    }
    return result;
}
```
`GetGNUSPrice` (cpp:2828-2844) and `GetProcessCost` (cpp:2797-2826) stay byte-identical.

### Env read (production, coinprices module)
```cpp
// Source: adapted from mock_transport_factory.hpp:34-45 (in-tree runtime env precedent)
// NO static caching — D-03 requires read-at-manager-construction for per-test redirection.
inline std::string GetPriceBaseUrl( const char *envName, const char *productionDefault )
{
    const char *value = std::getenv( envName );
    return ( value && *value ) ? std::string( value ) : std::string( productionDefault );
}
// SGNS_COINGECKO_URL    → default "https://api.coingecko.com"   (client appends /api/v3/simple/price)
// SGNS_PRICE_FALLBACK_URL → default "https://token.gnus.ai"     (client appends /v1/prices)
```

### Test env RAII guard (new, test-local — Claude's discretion item, recommended shape)
```cpp
// Source: synthesized; CRT-family setters per MS docs (Pitfall 1)
class ScopedEnvVar
{
public:
    ScopedEnvVar( std::string name, std::string value )
        : name_( std::move( name ) ), hadValue_( std::getenv( name_.c_str() ) != nullptr ),
          oldValue_( hadValue_ ? std::getenv( name_.c_str() ) : "" )
    {
#ifdef _WIN32
        _putenv_s( name_.c_str(), value.c_str() );
#else
        setenv( name_.c_str(), value.c_str(), /*overwrite=*/1 );
#endif
    }
    ~ScopedEnvVar()
    {
#ifdef _WIN32
        _putenv( ( name_ + "=" + oldValue_ ).c_str() ); // empty value removes on Win CRT
#else
        if ( hadValue_ ) setenv( name_.c_str(), oldValue_.c_str(), 1 ); else unsetenv( name_.c_str() );
#endif
    }
private:
    std::string name_, oldValue_;
    bool        hadValue_;
};
```
Fixture usage (account_management_test.cpp ctor, line 63 region):
```cpp
AccountManagement()
{
    stub_.OnPath( "/api/v3/simple/price", { 200, "application/json", R"({"genius-ai":{"usd":0.19}})" } );
    stub_.Start(); // OS-assigned port — BEFORE env, BEFORE New (Pitfall 2)
    const auto base = "http://127.0.0.1:" + std::to_string( stub_.Port() );
    envGuardCoinGecko_  = std::make_unique<ScopedEnvVar>( "SGNS_COINGECKO_URL", base );
    envGuardFallback_   = std::make_unique<ScopedEnvVar>( "SGNS_PRICE_FALLBACK_URL", base );
    // ... existing ctor body verbatim: removeAllWithRetry, create_directories, WriteNetworkConfig,
    //     SetSecureStorageFactory, WriteTrustedNodeConfig, GeniusNode::New, trust confirm ...
}
```

### D-11 one-stub-both-tiers scripting (price_retrieval_test rewrite)
```cpp
// Source: price_facade_test.cpp:63/82/95 scripting style + PriceHttpClient.cpp:95-99 target paths
stub_.OnPath( "/api/v3/simple/price", { 200, "application/json", R"({"genius-ai":{"usd":0.19}})" } );
stub_.OnPath( "/v1/prices",
              { 200, "application/json",
                R"({"currency":"usd","prices":{"genius-ai":0.21},"fetchedAt":1790719217,"age":17,"source":"coingecko-cache","stale":false})" } );
// warm-then-fail (D-13): after a successful GetCoinprice populates L1, flip tier 1:
stub_.OnPath( "/api/v3/simple/price", { 403, "text/html", "<html>403 ERROR cloudfront</html>" } );
// next GetCoinprice must still serve: fresh-L1 hit (or tier-2 envelope if L1 aged out)
```
Envelope fixture values cross-checked against Phase 1 worker tests (`envelope.freshness.test.ts`: 61234.12 / epoch 1790719217; per Phase 3 VERIFICATION) — keep fixtures byte-real.

## Current Code State Map (verified this session, HEAD `a3192a2ce`)

All CONTEXT.md canonical line numbers re-verified; deltas noted:

| Site | Location (current) | Notes / drift from CONTEXT |
|---|---|---|
| `GetProcessCost` | `GeniusNode.cpp:2797-2826` | Calls `GetGNUSPrice()` at 2807 — untouched |
| `GetGNUSPrice` | `GeniusNode.cpp:2828-2844` | finite/positive `genius-ai` check → `NO_PRICE` — untouched |
| `GetCoinprice` | `GeniusNode.cpp:3510-3563` | Miss-collection loop + per-call retriever; partial-data handling at 3548-3560 — the cutover body |
| `GetCoinPriceByDate` / `GetCoinPricesByDateRange` | `GeniusNode.cpp:3567-3573` / `3575-3582` | Delete (D-09) — also delete declarations at `GeniusNode.hpp:830, 841` |
| Cache members to delete | `GeniusNode.hpp:1481-1490` | `PriceInfo` struct 1481-1485, `m_tokenPriceCache` 1487, **`m_cacheValidityDuration` 1488** (also D-06 scope), `m_lastApiCall` 1489, `MIN_API_CALL_INTERVAL` 1490 — CONTEXT listed 1487-1490; the struct at 1481-1485 goes too |
| Ctor init-list entry to delete | `GeniusNode.cpp` ctor init list: `m_lastApiCall( std::chrono::system_clock::now() - MIN_API_CALL_INTERVAL )` | In the reordered ctor (~line 1386) — easy to miss |
| Include to replace | `GeniusNode.hpp:43` `#include "coinprices/coinprices.hpp"` | → `LocalPriceManager.hpp` + `PriceHttpClientSource.hpp` (or fwd-decl + cpp includes) |
| `GeniusNodeConfig` | `GeniusNode.hpp:77-87`; `New` at 150 | NOT modified (D-01) — verified brace-initialized aggregate |
| `~GeniusNode` | `GeniusNode.cpp:2199-2274` | Manager reset slots after `ShutdownForDestruction()` (see Pitfall 9) |
| `ReleaseRuntimeMembersAfterIoStopped` | `GeniusNode.cpp:2062-2125`, decl hpp:1387 | **ZERO callers** — dead code; do not plan around it |
| `"CoinPrices"` logger config | `GeniusNode.cpp:1334, 1396` | Becomes inert when retriever dies (new components log as `PriceHttpClient`/`LocalPriceManager`); leave-or-clean is discretion |
| Legacy retriever | `src/coinprices/coinprices.hpp/.cpp` (~530 lines) | Consumers: `GeniusNode.cpp:3536/3572/3581` + `price_retrieval_test.cpp:46/79/105` — **and nothing else** (verified across `SuperGenius/src`, `gRPCForSuperGenius/`, `SGProcessingManager/`, `GeniusSDK/src`, `SuperGenius/test`) |
| Seam survivors | `NodeExample.cpp:446` (`GetCoinprice`), `GeniusSDK.cpp:359` (`GetGNUSPrice`), `GeniusSDK.cpp:707/728` (`GetProcessCost`) | All keep compiling unchanged (LPM-10); gRPC/api has zero price surface (verified) |
| coinprices CMake | `src/coinprices/CMakeLists.txt:2-7` | Drop `coinprices.cpp` from `add_library` (Pitfall 8) |
| `account_management_test` | Fixture ctor 63-85 (`node_ = New` at 77); `SetPayoutAddress` TEST_F at 136; `GetProcessCost` at 333 | No SetUp/TearDown overrides today — env guard lives in ctor/dtor |
| account test CMake | `test/src/account/CMakeLists.txt:36-60` | addtest + `genius_node_test json_secure_storage` + WHOLEARCHIVE block + `SGNS_PROCESSING_ASSETS_DIR` def; adding `price_test_support` to link gives `HttpStubServer.hpp` include |
| `price_retrieval_test` | 3 live tests; CMake: deliberately unregistered (`add_executable`, no `add_test`) | Rewrite + register (D-10); driving `GetCoinprice` requires a full node → link shape mirrors account suite (`genius_node_test` + `json_secure_storage` + WHOLEARCHIVE + `price_test_support`) |
| `HttpStubServer` | `test/testutil/http_stub/` → lib `price_test_support` | API verified (§Standard Stack); include as `"HttpStubServer.hpp"` when linking `price_test_support`, or `"testutil/http_stub/HttpStubServer.hpp"` via the test-root include dir (`test/CMakeLists.txt` `include_directories(${CMAKE_CURRENT_SOURCE_DIR})`) |

## Threading Audit (D-08)

Verified node-side call graph of the price seam — **all callers are external/off-thread today**:

| Call site | Thread | Safe? |
|---|---|---|
| `GeniusNode::ProcessImage` → `GetProcessCost` → `GetGNUSPrice` → `GetCoinprice` (cpp:2679→2797→2807→2830→3510) | External API caller thread (test main thread; SDK caller thread) | ✓ |
| `account_management_test.cpp:333` `node_requester->GetProcessCost(...)` | gtest main thread | ✓ |
| `GeniusSDK.cpp:359` `GeniusNodeInstance->GetGNUSPrice()` | SDK caller thread (under `GeniusSDKMutex`) | ✓ |
| `NodeExample.cpp:446` `node->GetCoinprice(tokenIds)` | console thread | ✓ |

Nothing on the node's io threads or the manager's strand calls the seam today. `LocalPriceManager::GetQuotes` debug-asserts `!strand_.running_in_this_thread()` (LocalPriceManager.cpp:75-76) as a backstop. The seam wiring should carry the D-08 doxygen note: `GetCoinprice` is **blocking** (parks caller up to the tier retry schedule worst case ≈ 5s×attempts when both tiers time out) — do not call from io callbacks. Note the lazy first call pays the manager-construction cost plus the fetch (one-time thread spawn).

## State of the Art

Not applicable externally — no framework/ecosystem movement this phase (internal C++17 codebase, zero new deps). The relevant "current state" is the Current Code State Map above.

## Runtime State Inventory

Not a rename/refactor/migration phase — omitted per protocol. (Closest analog: GeniusSDK **build artifacts** reference `coinprices.lib` by name; the target name persists and artifacts regenerate on rebuild — no SDK source or linkage changes required.)

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Env-var names `SGNS_COINGECKO_URL` / `SGNS_PRICE_FALLBACK_URL` | Env read | Trivial rename; CONTEXT explicitly leaves strings to planner |
| A2 | Manager failure → `Error::NO_PRICE` at the seam | Seam adapter | Low: consumers only check `has_error()`; any in-category error works |
| A3 | Sources constructed with a throwaway ioc in the lazy ctor (vestigial param) | Pattern 2 | If Phase 2's vestigial-ioc note is outdated, adapter signature may need the manager's ioc — verify at implementation; `PriceHttpClientSource.hpp`'s own comment (read this session) says the param is unused inside the facade |
| A4 | A "true LKG (>60s stale) through the node seam" scenario is NOT included in the integration suite (cannot time-skip the manager's real clock through the seam; sleeping 61s in a test is not acceptable) — LKG stays proven in `price_manager_test` with the injectable clock; D-13 is satisfied by tier-2 fallback + fresh-L1 warm-then-fail | Test conversion | If the user wants literal LKG-through-the-seam, a test-only clock injection into the node's manager construction would be needed (new seam) — flag as an open question rather than silently descope |
| A5 | Debug tree reconfigure is out of scope; Phase 4 verifies in Release | Environment | If CI (Phase 5) or the user requires Debug-local verification, add a reconfigure step |

## Open Questions (RESOLVED)

> **Resolutions (locked at planning):** O1 → resolved in `04-01-PLAN.md` (free functions in `PriceEndpoints.hpp` with exported default constants); O2, O3 → resolved in `04-03-PLAN.md` (full-`GeniusNode` integration suite with 5-scenario TEST_F list; LKG-through-seam excluded — stays proven in `price_manager_test`, no clock-injection seam added).

1. **Env read placement (discretion, recommend deciding in plan):** free functions in a new tiny header (`PriceEndpoints.hpp`) in coinprices vs. statics on `PriceHttpClient`. Recommendation: free functions + exported production-default constants so tests assert defaults without duplicating strings.
2. **`price_retrieval_test` fixture weight (D-10 "or the seam as wired"):** full-`GeniusNode` integration (links `genius_node_test`, mirrors account fixture bootstrap: `WriteNetworkConfig`, `WriteTrustedNodeConfig`/local trust, in-memory secure storage, `OfflineChainlistFetcher`) — the honest reading of D-10 ("drives the real wired path — `GeniusNode::GetCoinprice`"). Accept the heavyweight link + ~seconds-per-test node bootstrap; alternatively split scenarios between this suite (wiring) and existing suites (manager internals already proven). Planner sets the TEST_F list (suggested: happy-path current price; 403→tier-2 envelope fallback; warm-then-fail fresh-L1; 429 handling; empty-ids seam contract).
3. **A4 (LKG-through-the-seam):** confirm with user whether D-13's "stale-served LKG" clause is satisfied by the manager-level unit proof (recommended) or demands a seam-level scenario requiring a clock-injection seam.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| CMake + VS 17 2022 generator | build | ✓ | VS 2022 x64, CMake (Strawberry bundle) | — |
| Build tree `SuperGenius/build/Windows/Release` | all verification | ✓ | current (Phase 2/3 suites registered: #18, #98-101) | — |
| Build tree `SuperGenius/build/Windows/Debug` | (optional) | ✗ stale | 147 tests, no price suites | Verify in Release only, or reconfigure Debug |
| ctest | test runner | ✓ | ships with CMake | run exes directly |
| Network loopback 127.0.0.1 | stub-based tests | ✓ | — | — |
| Live internet | NOTHING in this phase | — | — | removed by design (that's the point) |

**Verification commands (Windows, from repo root):**
```powershell
# Build the affected targets (multi-config VS generator — always pass --config)
cmake --build SuperGenius\build\Windows\Release --config Release --target account_management_test
cmake --build SuperGenius\build\Windows\Release --config Release --target price_retrieval_test
cmake --build SuperGenius\build\Windows\Release --config Release --target genius_node   # production lib cutover

# Run via ctest (xml output wired by addtest)
ctest --test-dir SuperGenius\build\Windows\Release -C Release -R "^account_management_test$" --output-on-failure
ctest --test-dir SuperGenius\build\Windows\Release -C Release -R "price" --output-on-failure

# Focused direct run (gtest filter; exes land in test_bin\<Config>\ on multi-config)
SuperGenius\build\Windows\Release\test_bin\Release\account_management_test.exe --gtest_filter=AccountManagement.SetPayoutAddress

# Regression: the four Phase 2/3 suites must stay green
ctest --test-dir SuperGenius\build\Windows\Release -C Release -R "price_quote_test|price_http_client_test|price_facade_test|price_manager_test" --output-on-failure
```
CMake automatically reconfigures on CMakeLists edits during `--build` (new env-guard header/`price_test_support` link edits trigger it; no manual configure needed). Note `addtest` sets TIMEOUT 600s and copies `vulkan-1.dll` beside each exe on WIN32 — inherited automatically.

**Regression blast radius to keep green:** `NodeExample` (builds against `genius_node`), `GeniusSDK` targets (link `coinprices.lib`; sources untouched), all account-suite tests, all four price suites. The Debug tree, if later reconfigured, must compile `genius_node_test` with the cutover too (SGNS_CONSOLE_LOG_TESTS define is compiled into the lib, not the exe — per the comment at `src/account/CMakeLists.txt:107-113`).

## Security Domain

ASVS level 1; phase surface is small.

| ASVS Category | Applies | Standard Control |
|---|---|---|
| V2 Authentication | no | — (no auth surface) |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | yes | Env-provided URLs flow only into `PriceHttpClient`, whose existing `parseHTTPUrl` gate rejects malformed bases (`PriceHttpClient.cpp:66-79` → `PriceFetchFailure`); status-gate-before-parse (LPM-05) already prevents body interpretation of non-200s |
| V6 Cryptography | no new | TLS verify_peer + pinned CA only on `https://` defaults (D-04); plain HTTP permitted **by design** for stub URLs — operator-controlled env, same trust class as any env config |
| V8 Data Protection | no | no secrets in scope (keyless by design, SRVC-06 lineage) |

| Pattern | STRIDE | Standard Mitigation |
|---|---|---|
| Env-var URL hijack (point node at attacker host) | Spoofing/Tampering | Accepted: env is operator-controlled, same as process config generally; no secrets flow to the price tier (keyless) |
| 403-HTML body fed to parser | Tampering | Pre-existing Phase 2 status gate — preserved unchanged |

## Sources

### Primary (HIGH confidence)
- Direct reads of all files cited in the Current Code State Map (workspace, HEAD `a3192a2ce`, branch `dev_tokenprice`) — every line number in this document was read this session
- `ctest -N` output of both Windows build trees (Debug: 147 tests/stale; Release: current)
- `.planning/workstreams/tokenprice/phases/{01,02,03}-*/` CONTEXT + VERIFICATION artifacts (Phase 1 envelope fixture values, Phase 2/3 mechanics)

### Secondary (MEDIUM-HIGH)
- [CITED: learn.microsoft.com/cpp/c-runtime-library/reference/getenv-wgetenv] — CRT `_environ` copy semantics (Pitfall 1)

### Tertiary (LOW)
- None — no WebSearch-only claims used

## Metadata

**Confidence breakdown:**
- Code state (seam, manager, stub, tests, CMake): HIGH — everything read directly, line numbers current
- Deletion safety (zero consumers beyond the two named): HIGH — exhaustive greps across SuperGenius src/test, gRPCForSuperGenius, SGProcessingManager, GeniusSDK src, api/, examples
- Env mechanics (CRT vs Win32): MEDIUM-HIGH — MS-documented behavior; exact UCRT sync nuance is why the recommendation uses the CRT family on both sides (immune to either behavior)
- Test-fixture design (RAII guard, ordering): MEDIUM — synthesized from verified constraints, not yet executed (that's the plan's job)

**Research date:** 2026-10-01
**Valid until:** code-state claims valid until the next commit touching `SuperGenius/src/account` or `src/coinprices` (this is the pre-planning snapshot)

---

## RESEARCH COMPLETE

**Key findings:**

1. **The cutover is surgical and the deletion is safe.** `CoinGeckoPriceRetriever` + forwarders + cache members have exactly two consumers (`GeniusNode.cpp` and `price_retrieval_test`); every external surface (`NodeExample` `GetCoinprice`, GeniusSDK `GetGNUSPrice`/`GetProcessCost`, gRPC — zero) survives the cutover unmodified. Full deletion inventory documented with exact current line numbers, including the easily-missed ctor init-list `m_lastApiCall(...)` entry and `GeniusNode.hpp:43` include.

2. **CONTEXT.md teardown assumption corrected:** `ReleaseRuntimeMembersAfterIoStopped()` has **zero callers** (dead code). The live teardown is the `~GeniusNode` body — and since the lazy manager owns its own ioc/thread and references no node members, the recommended release slot is an explicit `priceManager_.reset()` right after `ShutdownForDestruction()`, which also resolves any parked `GetQuotes` waiters deterministically.

3. **Windows env landmine identified and neutralized:** D-03's `SetEnvironmentVariable` wording conflicts with MSVC `getenv`'s CRT-copy semantics; tests must set env via `_putenv_s`/`setenv` (CRT family) matching the production `std::getenv` read. Production env read must NOT cache in a function-local static (breaks per-test stub-port redirection).

4. **Fixture ordering constraint:** stub `Start()` (OS-assigned port) → set env vars → `GeniusNode::New`. Per-test gtest fixtures give every test a fresh lazily-constructed manager — no L1/429-hold-off leakage across tests; `HttpStubServer`'s path-only script-key matching (query strings stripped) is what makes D-11's one-stub-both-tiers work.

5. **Verification must target the Release tree:** `build/Windows/Debug` is stale (no Phase 2/3 suites registered); Release has account_management_test (#18) and price suites (#98-101) current. Exact build/ctest/gtest-filter commands documented.

6. **Seam semantics preserved with three explicit rules:** empty-ids → success-empty-map (manager would fail `EmptyInput` — adapter short-circuits); manager success → partial map (absent ids stay absent, D-07); manager failure → in-category error (planner's discretion, `NO_PRICE` natural). The old 5s `MIN_API_CALL_INTERVAL` throttling is superseded by manager pacing — a deliberate, documented behavior delta.

7. **Vestigial-ioc note for the lazy ctor:** `PriceHttpClientSource`'s ioc param is documented (in its own header) as unused inside the facade's fetch path (fresh per-attempt context); the sources can be constructed with a throwaway ioc at the lazy-ctor site with zero runtime effect — flagged as assumption A3 to re-verify at implementation.

8. **D-13 scope honesty:** true >60s-LKG-through-the-seam cannot be time-skipped (the injectable clock is manager-internal, not reachable through the node seam); warm-then-fail covers fresh-L1 + tier-2-fallback deterministically, with LKG staying proven in `price_manager_test` — open question O3 for user confirmation.

9. **Threading audit (D-08) confirms safety by construction:** every current caller of the price seam is an external/off thread (test main, SDK caller, console); the manager carries a debug assert backstop; the seam docs should carry the "blocking — do not call from io callbacks" note.

10. **Zero new packages; zero new vendored thirdparty** — the only hand-rolled artifact is a ~30-line test-tree RAII env guard (no in-tree helper exists; verified).
