# Phase 4: GeniusNode Integration & Hermetic Tests - Pattern Map

**Mapped:** 2026-10-01
**Files analyzed:** 10 (7 modified/rewritten, 2 deleted-in-part, 2 new; 1 CMake of the deletion target)
**Analogs found:** 8 / 10 (2 have no in-tree analog — both are small new utilities whose reference shape comes from 04-RESEARCH.md §Code Examples)

All code-state line numbers below were read directly this session at `SuperGenius` HEAD `a3192a2ce` (branch `dev_tokenprice`) and match 04-RESEARCH.md's Current Code State Map.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `SuperGenius/src/account/GeniusNode.hpp` | model (node class header) | request-response | itself — regions being deleted (`PriceInfo` block hpp:1481-1490, historical decls hpp:830-849) + `src/coinprices/LocalPriceManager.hpp` (member-declaration/layout conventions) | exact (self) |
| `SuperGenius/src/account/GeniusNode.cpp` | service (seam adapter) | request-response (blocking) | itself — `GetCoinprice` cpp:3510-3563 (semantics to preserve) + `~GeniusNode` cpp:2199-2274 (teardown slot) + `test/src/mock/mock_transport_factory.hpp:34-45` (env read) | exact (self) |
| `SuperGenius/src/coinprices/coinprices.hpp` / `coinprices.cpp` | service (legacy HTTP retriever) | request-response | **deleted entirely (D-09)** — no analog needed; deletion inventory in RESEARCH Current Code State Map | n/a (deletion) |
| `SuperGenius/src/coinprices/CMakeLists.txt` | config (build) | n/a | itself — `add_library` list at lines 2-7 | exact (self) |
| NEW `SuperGenius/src/coinprices/PriceEndpoints.hpp` (name = RESEARCH O1 recommendation; planner may rename) | utility (env-read + default constants) | config-read (manager-ctor time) | `test/src/mock/mock_transport_factory.hpp:34-45` — **partial**: test-side AND caches in a static (the exact anti-pattern to avoid) | role-match (with anti-pattern warning) |
| `SuperGenius/test/src/account/account_management_test.cpp` | test (integration fixture) | request-response | `test/src/price_facade/price_facade_test.cpp` (stub scripting) + its own fixture ctor (cpp:63-85, the node bootstrap to keep verbatim) | exact |
| `SuperGenius/test/src/account/CMakeLists.txt` | config (test build) | n/a | itself (addtest+link+WHOLEARCHIVE block) + `test/src/price_facade/CMakeLists.txt` (the `price_test_support` link line to copy) | exact (self) |
| `SuperGenius/test/src/price_retrieval/price_retrieval_test.cpp` | test (integration suite, rewritten) | request-response | `test/src/price_facade/price_facade_test.cpp` (fixture + scripting style) + `test/src/account/account_management_test.cpp` (full-node bootstrap) | exact (composite) |
| `SuperGenius/test/src/price_retrieval/CMakeLists.txt` | config (test build, rewritten) | n/a | `test/src/account/CMakeLists.txt:35-66` (heavyweight genius-node-linking addtest shape) | exact |
| NEW test-tree RAII env guard (e.g. `SuperGenius/test/testutil/scoped_env.hpp`; location is discretion) | utility (test) | n/a | **none exists in-tree** (verified by research) — reference shape: RESEARCH §Code Examples "Test env RAII guard" | none |

---

## Pattern Assignments

### `SuperGenius/src/account/GeniusNode.hpp` (model header, request-response)

**Analog:** itself (deletion regions) + `LocalPriceManager.hpp` (declaration conventions)

**Delete — cache members (hpp:1481-1490, includes the struct CONTEXT's D-06 list omitted):**
```cpp
        struct PriceInfo
        {
            double                                             price;      ///< Cached USD token price.
            std::chrono::time_point<std::chrono::system_clock> lastUpdate; ///< Time when @ref price was fetched.
        };

        std::map<std::string, PriceInfo>                   m_tokenPriceCache; ///< Cached token price data by token id.
        const std::chrono::minutes                         m_cacheValidityDuration{ 1 }; ///< Price cache TTL.
        std::chrono::time_point<std::chrono::system_clock> m_lastApiCall{}; ///< Last external price API call time.
        static constexpr std::chrono::seconds              MIN_API_CALL_INTERVAL{ 5 }; ///< Minimum price API interval.
```
(The whole block goes, struct included — RESEARCH state map adds `m_cacheValidityDuration` at 1488 beyond CONTEXT's 1487-1490 list.)

**Delete — historical-forwarder declarations (hpp:828-849),** keeping `GetCoinprice`'s declaration (hpp:817-822) with its doc comment updated (cache mention in "using a short local cache" is now wrong — reword to the manager).

**Replace include (hpp:43):**
```cpp
#include "coinprices/coinprices.hpp"        // DELETE — the retriever is gone (D-09)
// → include LocalPriceManager.hpp / PriceHttpClientSource.hpp in the .cpp;
//   in the header prefer a forward declaration (class LocalPriceManager;) —
//   GeniusNode.hpp is widely included; a fwd-decl + shared_ptr member keeps
//   the price headers out of every consumer's include path.
```

**Add — lazy member declaration.** Follow the class's existing member-comment style (Doxygen `///<` trailing comments, `m_`-legacy vs trailing-underscore is mixed here; the price members being deleted used `m_`, but newer members like `io_thread_count_` use trailing underscore — match the surrounding ownership-order block at hpp:954-1106, i.e. trailing underscore):
```cpp
        std::shared_ptr<LocalPriceManager> priceManager_{}; ///< Lazily constructed on first GetCoinprice (D-05); owns its own ioc+thread; reset early in ~GeniusNode.
```
Placement note (RESEARCH Pitfall 9): explicit `.reset()` in the dtor body is the recommended mechanism, so declaration placement is not load-bearing — but declaring it among the last privates gives reverse-order destruction as a backstop.

---

### `SuperGenius/src/account/GeniusNode.cpp` (service, request-response)

**Analog 1 — itself: `GetCoinprice` today (cpp:3510-3563).** The partial-map semantics D-07 preserves live in the error tail (cpp:3546-3560):
```cpp
            else
            {
                // Handle the error case
                // If we have some cached data, continue with what we have
                if ( result.empty() )
                {
                    // Only return error if we have no data at all
                    return newPricesResult.error();
                }
                // Otherwise, continue with partial data and log the error
            }
```
The rewrite keeps exactly this contract via the manager: success → map of returned quotes (absent ids stay absent); failure → in-category error (`Error::NO_PRICE`, planner discretion). Plus the empty-ids short-circuit → `outcome::success({})` (RESEARCH Pitfall 3 — today's empty-in → empty-map-success must not become `EmptyInput` failure).

**Analog 2 — env read precedent (`test/src/mock/mock_transport_factory.hpp:34-45`):**
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
⚠️ **Copy the `std::getenv` read, NOT the `static` caching.** D-03 requires read-at-manager-construction so per-test stub-port redirection works; a function-local static freezes the first read process-wide. Also do not copy `SGNS_CONSOLE_LOG_TESTS`/`SGNS_DEBUGLOGS` (InitLoggers) as *shape* — they are boolean gates read once at startup; this is a string read per manager construction.

**Analog 3 — teardown slot: `~GeniusNode` body (cpp:2199-2274), head excerpt:**
```cpp
    GeniusNode::~GeniusNode()
    {
        node_logger_->debug( "~GeniusNode CALLED" );

        ShutdownForDestruction();

        // GraphSync retains PubSub's libp2p host, whose sockets are backed by
        // PubSub's io_context. ...
        if ( pubsub_ )
        {
            pubsub_context_keepalive_ = pubsub_->GetAsioContext();
        }
```
Recommended insertion: `priceManager_.reset();` immediately after `ShutdownForDestruction();` and before the `pubsub_` block — the manager owns its own ioc/thread and references no node members, so it drains/joins while the node is fully intact (RESEARCH Pitfall 9; `ReleaseRuntimeMembersAfterIoStopped` is dead code with zero callers — do not plan around it).

**Constructor init-list deletion:** the ctor (~cpp:1386 region) initializes `m_lastApiCall( std::chrono::system_clock::now() - MIN_API_CALL_INTERVAL )` — delete that initializer with the members (easy to miss; from RESEARCH's verified state map).

**Ctor wiring — the constructor signatures the lazy helper must match exactly:**

`LocalPriceManager` ctor (`src/coinprices/LocalPriceManager.hpp:40-46`) — tiers first, both required, no single-tier overload:
```cpp
        LocalPriceManager( std::shared_ptr<IPriceSource> coinGeckoTier,
                           std::shared_ptr<IPriceSource> gnusServiceTier,
                           std::chrono::milliseconds      coalescingWindow = std::chrono::milliseconds( 50 ),
                           Clock                          now              = [] { return std::chrono::system_clock::now(); } );
```
`GetQuotes` (same header, ~lines 60-72): `PriceResult<std::vector<PriceQuote>> GetQuotes( const std::vector<std::string> &ids, const std::string &currency = "usd" )` — **BLOCKING; never call from the manager's runner thread (D-08)**. The node-side callers are all off-thread today (RESEARCH Threading Audit); carry a doxygen note on `GetCoinprice`: blocking, do not call from io callbacks.

`PriceHttpClientSource` ctor (`src/coinprices/PriceHttpClientSource.hpp:29-40`) — header-only adapter; ioc first, baseUrl second, `ResponseFormat` last:
```cpp
        PriceHttpClientSource( std::shared_ptr<boost::asio::io_context> ioc,
                               std::string                              baseUrl,
                               RetryConfig                              retryConfig     = {},
                               std::chrono::seconds                     holdOffDuration = std::chrono::seconds( 60 ),
                               RateLimitHoldOff::Clock                  clock = [] { return std::chrono::system_clock::now(); },
                               std::chrono::milliseconds                requestTimeout = std::chrono::milliseconds( 5000 ),
                               ResponseFormat                           responseFormat = ResponseFormat::CoinGeckoSimplePrice )
```
Chicken-and-egg resolution (RESEARCH Pattern 2 / assumption A3): the manager builds its ioc internally, but the source's ioc param is documented vestigial (`PriceHttpClient` builds a fresh per-attempt context; the header's own comment says "do not build machinery around that parameter"). Construct each source with a throwaway `std::make_shared<boost::asio::io_context>()` at the lazy-ctor site — zero runtime effect. Re-verify the vestigial note at implementation.

Tier formats: tier 1 `ResponseFormat::CoinGeckoSimplePrice` (default), tier 2 `ResponseFormat::GnusEnvelope`. Scheme in the base URL string decides TLS (`http://127.0.0.1:P` → plain, D-04) — no code needed, it is `PriceHttpClient` behavior.

**Untouched — the acceptance proof (do not edit; cite in plan verification):**
- `GetGNUSPrice` (cpp:2828-2844): the finite/positive `genius-ai` check yielding `Error::NO_PRICE` stays byte-identical
- `GetProcessCost` (cpp:2797-2826): calls `GetGNUSPrice()` at ~2807, stays byte-identical
- External survivors: `NodeExample.cpp:446` (`GetCoinprice`), `GeniusSDK.cpp:359` (`GetGNUSPrice`), `GeniusSDK.cpp:707/728` (`GetProcessCost`)

**Delete — forwarders (cpp:3567-3582):** `GetCoinPriceByDate` and `GetCoinPricesByDateRange` bodies, each a 3-line retriever delegation. Also decide the now-inert `"CoinPrices"` logger config at cpp:1334/1396 (leave-or-clean is discretion; new components log as `PriceHttpClient`/`LocalPriceManager`).

The full seam-adapter body (empty-ids short-circuit → `GetOrCreatePriceManager()->GetQuotes` → quote→map loop → `NO_PRICE` on failure) is synthesized and verified in 04-RESEARCH.md §Code Examples "The seam adapter" — the planner should lift it verbatim into the plan's action list.

---

### `SuperGenius/src/coinprices/coinprices.hpp/.cpp` (deleted, D-09)

No analog needed — full deletion. Consumers verified at exactly: `GeniusNode.cpp:3536/3572/3581` and `price_retrieval_test.cpp:46/79/105` (nothing in `src/api/`, `gRPCForSuperGenius/`, `SGProcessingManager/`, `GeniusSDK/`, or other tests). The rewritten `price_retrieval_test` (below) removes the last consumer. Do not leave a forwarding shim.

### `SuperGenius/src/coinprices/CMakeLists.txt` (config)

**Analog:** itself, lines 2-7:
```cmake
add_library(coinprices
    coinprices.cpp
    PriceRetryPolicy.cpp
    PriceHttpClient.cpp
    PriceResponseParsers.cpp
    LocalPriceManager.cpp
)
```
Change: drop `coinprices.cpp` from the list only. Keep the target name `coinprices` (GeniusSDK build artifacts reference `coinprices.lib`; artifacts regenerate — RESEARCH Pitfall 8). Everything else (CA-path compile def, link block, `supergenius_install`) stays.

If the env read lands as `PriceEndpoints.hpp` in this module (RESEARCH O1 recommendation), it is header-only — no CMake source-list change for it, and exporting the default constants lets tests assert defaults without duplicating strings.

### NEW `SuperGenius/src/coinprices/PriceEndpoints.hpp` (utility, config-read)

**Analog (partial, with warning):** `mock_transport_factory.hpp:34-45` (excerpt above). Differences from the analog: (1) production code, not test helper — `inline` free functions in `namespace sgns`, Doxygen `@brief/@return` per convention; (2) **no static caching**; (3) returns the env string or the production default when unset/empty:
```cpp
// Reference shape (RESEARCH §Code Examples "Env read"):
inline std::string GetPriceBaseUrl( const char *envName, const char *productionDefault )
{
    const char *value = std::getenv( envName );
    return ( value && *value ) ? std::string( value ) : std::string( productionDefault );
}
// SGNS_COINGECKO_URL     → default "https://api.coingecko.com"  (client appends /api/v3/simple/price)
// SGNS_PRICE_FALLBACK_URL → default "https://token.gnus.ai"     (client appends /v1/prices)
```
Env names `SGNS_COINGECKO_URL`/`SGNS_PRICE_FALLBACK_URL` are planner discretion (A1) but follow the `SGNS_*` precedent exactly.

---

### `SuperGenius/test/src/account/account_management_test.cpp` (test fixture)

**Analog 1 — its own fixture ctor (cpp:63-85).** This is the node bootstrap that stays verbatim; the env redirect slots at the TOP, before `GeniusNode::New` (D-03/D-12). Ordering is strict: stub `Start()` (OS-assigned port) → set env from `stub_.Url("")` base → existing ctor body (RESEARCH Pitfall 2):
```cpp
    AccountManagement()
    {
        test::removeAllWithRetry( path.string() );
        boost::filesystem::create_directories( path );
        sgns::GeniusNode::WriteNetworkConfig( path.generic_string() + '/', /*port_seed=*/0, /*auto_dht=*/false );
        // Inject in-memory secure storage to avoid OS keychain prompts during tests
        GeniusAccount::SetSecureStorageFactory( []( const std::string &identifier ) -> std::shared_ptr<ISecureStorage>
                                                { return std::make_shared<MemorySecureStorage>( identifier ); } );

        const auto bootstrapper = WriteTrustedNodeConfig(
            path, "90bd26f57e3c243358666f32ff8321181545f4ddd8c981aceac163f26b05eaaa", "Full", true );
        assert( bootstrapper );
        Blockchain::SetAuthorizedFullNodeAddress( bootstrapper->GetAddress() );

        node_ = sgns::GeniusNode::New(
            { "0xcafe", "0.35", "1.0", TOKEN_ID, path.generic_string() + '/' },
            sgns::FromPrivateKey{ "90bd26f57e3c243358666f32ff8321181545f4ddd8c981aceac163f26b05eaaa" } );
        node_->SetChainlistFetcher( sgns::test::OfflineChainlistFetcher() );
        assert( node_ != nullptr );
        ConfirmConfiguredTrust( node_ );
        assert( node_->GetState() == GeniusNode::NodeState::READY );
    }
```
Insertion shape (fixture gains `sgns::testutil::HttpStubServer stub_;` + `std::unique_ptr<ScopedEnvVar>` guards as members, guard ctor calls before the existing body, stub scripted with a valid `genius-ai` price, `stub_.Start()` first; a fixture dtor — none exists today — restores env and `stub_.Shutdown()`). Every TEST_F in the suite gets this (gtest constructs the fixture per test — that is desired: whole-suite hermetic per D-12). The `SetPayoutAddress` TEST_F (line 136) and its `GetProcessCost` call (line 333) stay untouched:
```cpp
    auto        cost      = node_requester->GetProcessCost( *procmgr.value() );
```

**Analog 2 — stub scripting style** (`price_facade_test.cpp:26-31` constants + `:64` scripting):
```cpp
    const char *kGoodBody = R"({"genius-ai":{"usd":0.19},"bitcoin":{"usd":61234.12}})";
    const char *kCloudFront403 =
        "<!DOCTYPE html><html><body><h1>403 ERROR</h1><p>ERROR: The request could not be "
        ... // byte-real CloudFront 403 HTML — copy verbatim from price_facade_test.cpp
```
For D-12 a single line suffices: `stub_.OnPath( "/api/v3/simple/price", { 200, "application/json", R"({"genius-ai":{"usd":0.19}})" } );`

**Include style** (price_facade_test.cpp:8): `#include "HttpStubServer.hpp"` — resolves once `price_test_support` is linked (CMake change below). The account suite's existing testutil includes use `"testutil/..."` — either works given the test-root include dir; match whichever the link provides.

### `SuperGenius/test/src/account/CMakeLists.txt` (test config)

**Analog:** itself (cpp shape stays) + one line copied from `test/src/price_facade/CMakeLists.txt:12`. Current registration (lines 35-46):
```cmake
addtest(account_management_test
    account_management_test.cpp
)

target_link_libraries(account_management_test genius_node_test json_secure_storage)

target_compile_definitions(account_management_test PRIVATE
    SGNS_PROCESSING_ASSETS_DIR="${PROJECT_ROOT}/test/src/processing_nodes")
```
Change: add `price_test_support` to the `target_link_libraries` line → `target_link_libraries(account_management_test genius_node_test json_secure_storage price_test_support)`. The existing WHOLEARCHIVE block (lines ~56-66) already covers the suite — no change there. `HttpStubServer.hpp` include path comes with the `price_test_support` target's interface include dirs (as in price_facade).

---

### `SuperGenius/test/src/price_retrieval/price_retrieval_test.cpp` (test, rewritten)

**Composite analog — fixture skeleton from `price_facade_test.cpp:33-60`:**
```cpp
class PriceFacadeTest : public ::testing::Test
{
protected:
    static void SetUpTestSuite() {}
    static void TearDownTestSuite() {}

    void SetUp() override
    {
        stub_.Start();
    }

    void TearDown() override
    {
        stub_.Shutdown();
    }

    sgns::testutil::HttpStubServer stub_;
    ...
};
```
Differences for the rewrite: the node bootstrap from the `AccountManagement` ctor (WriteNetworkConfig / SetSecureStorageFactory / WriteTrustedNodeConfig / `GeniusNode::New` / OfflineChainlistFetcher / ConfirmConfiguredTrust — copy the account fixture's sequence, it is the proven minimal full-node bring-up) replaces the bare fixture; and because env must be set before `New` while the port comes from `Start()`, prefer ctor/dtor ordering (stub+env+New in ctor; restore env + Shutdown in dtor) over SetUp/TearDown — SetUp runs after the ctor, i.e. after `New` (RESEARCH Pattern 3).

**Scripting — D-11 one-stub-both-tiers** (paths from `PriceHttpClient` target builders; query strings are stripped by the stub when matching — `HttpStubServer.cpp:129-133` — so path-only keys work):
```cpp
stub_.OnPath( "/api/v3/simple/price", { 200, "application/json", R"({"genius-ai":{"usd":0.19}})" } );
stub_.OnPath( "/v1/prices",
              { 200, "application/json",
                R"({"currency":"usd","prices":{"genius-ai":0.21},"fetchedAt":1790719217,"age":17,"source":"coingecko-cache","stale":false})" } );
```

**Scripting — D-13 warm-then-fail.** The in-test re-script precedent is `price_facade_test.cpp` `HeldOffTierSkipsNetworkEntirely` (lines ~104-118), which flips a scripted path mid-test:
```cpp
    // Arm via first response, then flip:
    stub_.OnPath( "/api/v3/simple/price", { 403, "text/html", kCloudFront403 } );  // or { 429, "text/html", "Too Many Requests" }
```
Apply after a successful `GetCoinprice` populated L1; the next call must still serve via fresh-L1 (or tier-2 envelope). Scenario→TEST_F split is discretion; suggested set in RESEARCH Open Question 2 (happy / 403→tier-2 / warm-then-fail fresh-L1 / 429 / empty-ids seam contract).

**Assertion style** — copy `price_facade_test.cpp:67-85` (`ASSERT_TRUE` on result, `EXPECT_DOUBLE_EQ` on scripted prices, `EXPECT_EQ(stub_.LastUserAgent(path), ...)` available if wanted). Scripted prices are deterministic — assert exact values.

**What NOT to re-prove:** manager-internal behaviors already covered by `price_manager_test` (freshness bands, LKG aging — clock not reachable through the node seam, RESEARCH A4/O3); client transport behaviors covered by `price_facade_test`/`price_http_client_test`. The rewrite proves wiring only.

**HttpStubServer API surface** (`test/testutil/http_stub/HttpStubServer.hpp:33-56`) for the plan's action list:
```cpp
        struct ScriptedResponse
        {
            unsigned                status      = 200;
            std::string             contentType = "application/json";
            std::string             body;
            std::chrono::milliseconds delay{ 0 };
            bool                    hang = false;
        };
        void OnPath( std::string path, ScriptedResponse r );
        void Start();
        uint16_t Port() const;
        std::string Url( std::string path ) const;
        void Shutdown();
        std::string LastUserAgent( const std::string &path ) const;
```

### `SuperGenius/test/src/price_retrieval/CMakeLists.txt` (test config, rewritten)

**From** (current, deliberately unregistered — whole file):
```cmake
# Live CoinGecko smoke test: build it, but do not register it with CTest.
add_executable(price_retrieval_test
    price_retrieval_test.cpp
    )

target_link_libraries(price_retrieval_test
    GTest::gtest_main
    rapidjson
    OpenSSL::SSL
    coinprices
)
...
```
**To** — the heavyweight registered shape from `test/src/account/CMakeLists.txt:35-66`:
```cmake
addtest(price_retrieval_test
    price_retrieval_test.cpp
)

target_link_libraries(price_retrieval_test genius_node_test json_secure_storage price_test_support)

if(MSVC)
    target_link_options(price_retrieval_test PUBLIC /WHOLEARCHIVE:$<TARGET_FILE:genius_node_test>)
elseif(APPLE)
    target_link_options(price_retrieval_test PUBLIC -force_load "$<TARGET_FILE:genius_node_test>")
else()
    target_link_options(price_retrieval_test PUBLIC
        "-Wl,--whole-archive"
        "$<TARGET_FILE:genius_node_test>"
        "-Wl,--no-whole-archive"
    )
endif()
```
Why heavyweight: driving `GeniusNode::GetCoinprice` requires a full node, so link `genius_node_test` + `json_secure_storage` (account-suite shape) plus `price_test_support` (stub). Note `addtest` (defined `SuperGenius/cmake/functions.cmake:8-39`) already provides: `gtest_main`/`gmock_main` link, xunit XML output, `add_test` registration, TIMEOUT 600, `test_bin` output dir, Vulkan DLL copy on WIN32, clang-tidy disabled — the rewrite's CMake is just addtest + link + WHOLEARCHIVE. Also add the `SGNS_PROCESSING_ASSETS_DIR` compile-definition only if scenarios build a `ProcessingManager` (account suite needed it for `GetProcessCost`'s `ParseBlockSize`; a price-only suite likely does not — planner decides per scenario list). Drop the old `set_target_properties(RUNTIME_OUTPUT_DIRECTORY ...)` and `disable_clang_tidy` — `addtest` does both.

### NEW test-tree RAII env guard (utility)

No in-tree analog (verified). Reference shape = RESEARCH §Code Examples "Test env RAII guard" (~30 lines): CRT-family setters on both platforms (`_putenv_s`/`_putenv` on `_WIN32`, `setenv`/`unsetenv` otherwise), captures prior value in ctor, restores exact prior state (set vs. unset) in dtor. The CRT-family requirement is the Pitfall-1 landmine: production reads `std::getenv` (CRT copy) — Win32 `SetEnvironmentVariable` writes are not guaranteed visible to it, despite D-03's wording. Location discretion: a shared `test/testutil/` header is natural if both suites use it (they both do); keep it test-tree only.

---

## Shared Patterns

### Stub-scripting fixture
**Source:** `SuperGenius/test/src/price_facade/price_facade_test.cpp:33-64` (fixture + first TEST_F)
**Apply to:** `account_management_test.cpp` fixture, rewritten `price_retrieval_test.cpp`
Fixture owns `sgns::testutil::HttpStubServer stub_;`; script with `OnPath(path, {status, contentType, body})` before/around the act; assert on scripted (deterministic) values; `LastUserAgent` available. Path-only script keys (query stripped). Mid-test re-scripting is safe (mutex-guarded) — the D-13 flip mechanism.

### Full-node bootstrap in fixtures
**Source:** `SuperGenius/test/src/account/account_management_test.cpp:63-85` (ctor) + helpers at 28-52 (`WriteTrustedNodeConfig`, `ConfirmConfiguredTrust` in anonymous namespace)
**Apply to:** rewritten `price_retrieval_test.cpp`
The proven minimal bring-up: per-test unique dir → `WriteNetworkConfig` → `SetSecureStorageFactory(MemorySecureStorage)` → `WriteTrustedNodeConfig` → `GeniusNode::New` → `SetChainlistFetcher(OfflineChainlistFetcher())` → `ConfirmConfiguredTrust`. Env redirect slots between storage factory and `New` (strictly after `stub_.Start()`).

### CTest registration — two shapes
**Source (light):** `SuperGenius/test/src/price_facade/CMakeLists.txt` (whole file, 13 lines) — `addtest(...)` + `target_link_libraries(... coinprices price_test_support ...)`
**Source (heavy):** `SuperGenius/test/src/account/CMakeLists.txt:35-66` — addtest + `genius_node_test json_secure_storage` + 3-platform WHOLEARCHIVE block
**Apply to:** `price_retrieval/CMakeLists.txt` (heavy, +`price_test_support`), `account/CMakeLists.txt` (add `price_test_support` to existing link line only)
`addtest` semantics: `SuperGenius/cmake/functions.cmake:8-39`.

### Env set/restore (CRT family) + env read (no caching)
**Source:** synthesized — RESEARCH §Code Examples "Test env RAII guard" + "Env read (production)" (in-tree partial precedent: `mock_transport_factory.hpp:34-45`, static-caching deliberately NOT copied)
**Apply to:** the new RAII guard (tests), `PriceEndpoints.hpp` (production)
Rules: production reads `std::getenv` at manager construction, never cached in a static; tests set with `_putenv_s`/`setenv`, restore exact prior state; ordering stub-Start → env → `New`.

### Partial-map seam semantics
**Source:** `SuperGenius/src/account/GeniusNode.cpp:3546-3560` (today's error tail) + `LocalPriceManager.hpp` `GetQuotes` doc (blocking, partial-success)
**Apply to:** the `GetCoinprice` rewrite
Empty ids → success-empty-map; manager success → quotes-to-map loop (absent stay absent); manager failure → `Error::NO_PRICE` (in-category; `GetGNUSPrice` re-maps anyway). `GetGNUSPrice`/`GetProcessCost` byte-identical.

---

## No Analog Found

| File | Role | Data Flow | Reason / Reference Instead |
|------|------|-----------|---------------------------|
| `SuperGenius/test/testutil/scoped_env.hpp` (or similar; new) | utility (test) | n/a | No in-tree env save/restore helper exists (research-verified). Use RESEARCH §Code Examples "Test env RAII guard" verbatim as the spec (~30 lines). |
| `SuperGenius/src/coinprices/PriceEndpoints.hpp` (new) | utility (production env read) | config-read | Closest in-tree env read (`mock_transport_factory.hpp`) is test-side and static-cached — an anti-pattern for D-03. Use RESEARCH §Code Examples "Env read (production)"; structure follows project header conventions (`@brief` Doxygen, `#pragma once`, `namespace sgns`). |

## Metadata

**Analog search scope:** `SuperGenius/src/account/`, `SuperGenius/src/coinprices/`, `SuperGenius/test/src/{price_facade,price_retrieval,account,mock}/`, `SuperGenius/test/testutil/http_stub/`, `SuperGenius/cmake/functions.cmake`
**Files read this session:** 12 (4 test-tree, 5 coinprices-module/seam, 2 CMake, 1 cmake-functions) — all excerpts above are direct reads at HEAD `a3192a2ce`; RESEARCH-only claims (ctor init-list line, `HttpStubServer.cpp` query-strip, logger-config lines, NodeExample/GeniusSDK call sites) are marked by reference.
**Pattern extraction date:** 2026-10-01
**Notes for planner:** (1) line numbers drift as soon as edits land — cite by symbol + approximate line in PLAN.md; (2) RESEARCH Open Questions O1 (env-read placement), O2 (fixture weight/TEST_F list), O3 (LKG-through-seam scope) should be resolved in the plan; (3) verification commands target the **Release** tree (Debug tree is stale — RESEARCH Pitfall 7).
