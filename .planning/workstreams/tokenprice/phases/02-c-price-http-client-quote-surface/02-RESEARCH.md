# Phase 2 Research: C++ Price HTTP Client & Quote Surface

**Phase:** 2 — C++ Price HTTP Client & Quote Surface
**Date:** 2026-09-30
**Status:** Complete — ready for planning
**Inputs:** 02-CONTEXT.md (D-01..D-16, binding) · REQUIREMENTS.md · ROADMAP.md · 01-CONTEXT.md · AsyncIOManager/SuperGenius source (all citations below from code actually read)

---

## Domain Overview

Phase 2 delivers the transport-correctness layer for C++ price fetching, redirected by D-01: the status-aware HTTPS transport is an **upgrade to `thirdparty/AsyncIOManager`** (branch `dev_tokenprice`), not a price-scoped Beast client in SuperGenius. SuperGenius contributes the provider-independent `PriceQuote`/`PriceSource` types, the freshness classifier, the retry/hold-off policy, and a Beast-based **test-only** stub server under `SuperGenius/test/`. Everything must be hermetically testable (TEST-03) and leave `FileManager::LoadASync` behavior byte-identical for existing consumers (D-02).

**Line-number deltas vs 02-CONTEXT.md canonical refs** (code was re-verified today; intent identical, lines slightly off):
- UA hard-coded: `HTTPCommon.cpp:193-196` (not ~196)
- `\r\n\r\n` slice: find at `HTTPCommon.cpp:239`, body slice at `:249` (not ~255ff)
- `"http"` registration commented out: `HTTPLoader.cpp:30` (not line 34); active `"https"` registration at `:31`
- Deadline timers 10s/10s/30s: `HTTPCommon.cpp:142`, `:153`, `:197` — confirmed
- `s_verify_peer`: definition `HTTPCommon.cpp:72`, `verify_none` branch `:128-131` — confirmed
- `parseHTTPUrl` at `URLStringUtil.cpp:38-86`; default port "443" at `:68` — confirmed
- `coinprices.cpp`: `decodeChunkedTransfer` at `:30`, retry loop `:124-140`, throwaway `io_context` `:169`, `LoadASync` `:178`, `ioc->run()` `:200` (CONTEXT said 133/178/23/100-112 — close, actual lines cited above)

---

## Technical Findings

### 1. Upgrading HTTPDevice in-place vs a sibling status-aware class

**Recommendation: sibling class. Keep `HTTPDevice` untouched.**

`HTTPDevice` (`thirdparty/AsyncIOManager/include/HTTPCommon.hpp:29-136`, `src/HTTPCommon.cpp:66-268`) is hard-wired to the legacy contract:
- Constructor takes `(host, path, port, parse, save)` (hpp:59-61) — no room for UA/timeouts/TLS-policy without breaking the two call sites.
- Response is `ResultType = pair<vector<string>, vector<vector<char>>>` (hpp:44-45) — filename + body only; status line and all headers are discarded at the `find("\r\n\r\n")` slice (`HTTPCommon.cpp:239`, `:249`). This is LPM-05's root defect.
- `StartHTTPGet` builds a raw string request with hard-coded UA `GeniusAI/1.0 (SGNS AsyncIO Manager)` (`HTTPCommon.cpp:193-196`).
- The stream type is unconditionally `ssl::stream<tcp::socket>` (`HTTPCommon.cpp:85`) — no plain-HTTP path exists.

The only caller is `HTTPLoader::LoadASync` (`HTTPLoader.cpp:61-62`), which constructs one device per request — the codebase has **no device-reuse or connection-pool state anywhere**, so "per-request state vs device reuse" is a non-issue by construction: the new class follows the same one-object-per-request pattern (`shared_from_this` + lambda capture chain, `HTTPCommon.cpp:144-156`).

D-02 requires zero behavior change for `processing_subtask_queue_accessor_impl.cpp` (`:388` LoadASync call), `coinprices.cpp` (3 call sites: `:178`, `:305`, `:454`), and `GeniusNode.cpp` (`:1698` InitializeSingletons). A sibling class gives that guarantee structurally — `HTTPDevice.cpp` is not edited, so HTTPS `LoadASync` consumers cannot regress. 02-CONTEXT.md explicitly authorizes "additive on HTTPDevice **or a sibling device class within AsyncIOManager**."

**Recommended API shape** (names are suggestions; the planner owns final naming per Claude's Discretion):

```cpp
// include/HTTPTypes.hpp  (new — pure data types, no .cpp needed)
namespace sgns::http
{
    struct RequestOptions
    {
        std::string userAgent;                    // D-08: per-request UA
        std::chrono::milliseconds connectTimeout{ 10000 };
        std::chrono::milliseconds handshakeTimeout{ 10000 };
        std::chrono::milliseconds readTimeout{ 30000 };
        std::optional<std::string> caCertFile;    // D-07: pinned CA path; nullopt => TLS off (plain)
        std::vector<std::pair<std::string, std::string>> extraHeaders;
    };

    struct Response
    {
        unsigned status = 0;                       // real status code — LPM-05 root fix
        std::string reason;
        std::multimap<std::string, std::string> headers;  // case preserved as received
        std::string body;
    };

    enum class ClientError   // transport-layer failures (status 0 => no HTTP response at all)
    {
        RESOLVE_FAILED = 1, CONNECT_FAILED, TLS_HANDSHAKE_FAILED, TLS_CA_LOAD_FAILED,
        WRITE_FAILED, READ_INTERRUPTED, NO_HEADER, TIMEOUT,
    };
}

// include/HTTPClient.hpp (new)
class HTTPClient : public std::enable_shared_from_this<HTTPClient>
{
public:
    using Result = outcome::result<http::Response>;
    using Completion = std::function<void( std::shared_ptr<boost::asio::io_context>, Result )>;

    HTTPClient( std::string host, std::string target, std::string port );  // target = path+query (D-04)

    /// Async — caller-supplied io_context per D-09. One request per HTTPClient object.
    void Execute( std::shared_ptr<boost::asio::io_context> ioc,
                  const http::RequestOptions &,
                  Completion onDone );

    /// Sync convenience for Phase-2 price facade: runs `ioc` with a work guard until
    /// completion (mirrors today's coinprices.cpp:169-200 pattern but on a caller ioc).
    Result ExecuteBlocking( std::shared_ptr<boost::asio::io_context> ioc,
                            const http::RequestOptions & );
};
```

Key surface properties:
- **TLS on/off decided by `caCertFile` + the scheme the loader saw** (see §2) — plain HTTP uses `tcp::socket`, HTTPS uses `ssl::stream<tcp::socket>` with `verify_peer` + `load_verify_file` + SNI + hostname check (§3).
- Deadline machinery: reuse the existing `ArmDeadline`/`CancelDeadline` pattern verbatim (`HTTPCommon.cpp:19-46`) — it already takes a `std::chrono::seconds timeout` parameter (`:21`), so parameterization is just threading `RequestOptions` values into the three call sites (`:142` connect, `:153` handshake, `:197` read). Change the signature to `milliseconds` for sub-second test injection.
- **Parsing without touching the async path:** keep the existing read-until-EOF `async_read` + `streambuf` approach (`HTTPCommon.cpp:207-236`), then split status/headers/body **synchronously** from the completed buffer. Two viable implementations:
  - **(a) Beast parser (recommended):** `boost::beast::http::response_parser<boost::beast::http::string_body>` fed with `parser.put(buffer)` after the read completes. Correct handling of status line, header folding/case, content-length/chunked for free. **Precedent: AsyncIOManager already builds against Beast** — `WSCommon.cpp:83` constructs `beast::websocket::stream` and `src/CMakeLists.txt` compiles it today, and Boost 1.85 ships `libs/beast/include` in the thirdparty boost checkout (verified). D-01 is about *where the code lives*, not which library parses bytes; Beast-inside-AsyncIOManager honors it.
  - (b) Raw hand parsing of the status line + headers (~80 lines; must handle case-insensitive header lookup, folding). Matches `HTTPDevice`'s no-Beast style but is strictly more code with more edge cases.
  Planner picks; both satisfy D-01..D-04. Note D-04 says chunked is *not required* — with (a) it is free robustness; with (b) it stays out of scope.

**File layout in AsyncIOManager** (matches existing `include/` + `src/` split; headers under `include/` are installed by `CMakeLists.txt:74`):
- `include/HTTPTypes.hpp` — `RequestOptions`, `Response`, `ClientError` + outcome category
- `include/HTTPClient.hpp` — the sibling device class
- `src/HTTPClient.cpp` — implementation
- `src/CMakeLists.txt` — add `HTTPClient.cpp` to the `add_library(AsyncIOManager STATIC ...)` list (`src/CMakeLists.txt:1-16`)

### 2. Plain-HTTP loader enablement (D-03) — the scheme-stripping trap

**Critical finding:** `FileManager::LoadASync` parses the URL and passes the **scheme-stripped remainder** to the loader: `getURLComponents(url, prefix, filePath, suffix)` then `loader->LoadASync(filePath, ...)` (`src/FileManager.cpp:77-81`). By the time `HTTPLoader::LoadASync` runs, `"http://host/path"` and `"https://host/path"` are **indistinguishable** — both arrive as `host/path`. Simply un-commenting `FileManager::GetInstance().RegisterLoader("http", this)` (`HTTPLoader.cpp:30`) and re-registering the *same* singleton is therefore **not viable**: the loader cannot know whether to TLS-handshake or to default the port to 80 vs 443 (`parseHTTPUrl` defaults to "443" unconditionally, `URLStringUtil.cpp:68`).

**Resolution within the existing virtual-scheme design (D-03):** register **two `HTTPLoader` instances**, each constructed with a scheme flag — the registry maps prefix → `FileLoader*` (`FileManager.hpp:79`, `FileManager.cpp:13-16`), so nothing about the design changes:

```cpp
// HTTPLoader.cpp
HTTPLoader::HTTPLoader( bool tls, unsigned defaultPort ) : useTLS_(tls), defaultPort_(defaultPort) {}
void HTTPLoader::InitializeSingleton()
{
    if ( _instance == nullptr ) { _instance = new HTTPLoader( true, 443 ); }
    FileManager::GetInstance().RegisterLoader( "https", _instance );
    if ( _plainInstance == nullptr ) { _plainInstance = new HTTPLoader( false, 80 ); }
    FileManager::GetInstance().RegisterLoader( "http", _plainInstance );
}
```

`HTTPLoader::LoadASync` then dispatches: `https` → legacy `HTTPDevice` (untouched, D-02); `http` → new `HTTPClient` with `caCertFile = nullopt`, adapted back into the legacy `ResultType` (filename from path + body). Port handling: `parseHTTPUrl` leaves explicit `host:port` intact (`URLStringUtil.cpp:64-76`) — the stub URL `http://127.0.0.1:54321/path` parses correctly today; only the *default* port differs (443→80), handled by the loader instance's `defaultPort_` when `parseHTTPUrl` returned its hard-coded 443 and the instance is the plain one. (Minimal, no `parseHTTPUrl` signature change — honors D-04's "no URL-shape rework".)

**Blast radius of enabling "http": zero.** Today an `http://` URL throws `std::range_error("No loader registered for prefix http")` from `FileManager.cpp:58`. No SuperGenius consumer uses `http://` (only `https` in coinprices/processing, `ipfs://`, `file://`). Registering the scheme is purely additive. Note honestly: the legacy `http://` `LoadASync` path remains status-blind (adapter strips status) — acceptable and documented; only the new `Execute` surface surfaces status.

### 3. TLS verification with pinned in-repo cacert.pem (D-06/D-07)

Current state confirms the dead toggle: `s_verify_peer = true` (`HTTPCommon.cpp:72`) merely *skips* `set_verify_mode(verify_none)` (`:128-131`); nothing ever calls `verify_peer`, `load_verify_file`, or a hostname check. `WSDevice` is no better — `set_default_verify_paths()` with a commented-out `set_verify_callback` (`WSCommon.cpp:76-79`).

New-surface configuration (Boost 1.85 / OpenSSL, both already linked — `AsyncIOManager/CMakeLists.txt:34` `find_package(OpenSSL REQUIRED)`):

```cpp
sslCtx = std::make_shared<boost::asio::ssl::context>( boost::asio::ssl::context::tls );
sslCtx->set_options( ssl::context::default_workarounds | ssl::context::no_sslv2 | ssl::context::no_sslv3 );  // as today, HTTPCommon.cpp:123-125
sslCtx->set_verify_mode( ssl::verify_peer );                          // D-06
boost::system::error_code ec;
sslCtx->load_verify_file( *options.caCertFile, ec );                  // D-07 pinned bundle
if ( ec ) return failure( ClientError::TLS_CA_LOAD_FAILED );          // never throw past the API
sslCtx->set_verify_callback( ssl::host_name_verification( host ) );   // hostname check (Asio ≥1.73)
SSL_set_tlsext_host_name( sock->native_handle(), host.c_str() );      // SNI — same call as HTTPCommon.cpp:135
```

- `ssl::host_name_verification` (header `<boost/asio/ssl/host_name_verification.hpp>`) composes with `verify_peer` and gives RFC 6125 name checking; Boost in-tree is 1.85 (`thirdparty/boost/boost/version.hpp:22` → `BOOST_VERSION 108500`), comfortably past 1.73.
- **cacert.pem placement:** transport must not own the file — `RequestOptions::caCertFile` is just a path. The bundle ships with SuperGenius: recommend `SuperGenius/src/coinprices/certs/cacert.pem` (curl.se mozilla bundle), with the price client's default path overridable per D-07. Runtime resolution: default to a path relative to the executable / compile-time absolute source-tree definition set by `coinprices/CMakeLists.txt` (`target_compile_definitions(coinprices PRIVATE SGNS_DEFAULT_CACERT_PATH="...")`), config override wins. **No `.pem` exists anywhere in SuperGenius today** (verified by search) — this file is new.
- **Platform pitfalls:** Windows — OpenSSL reads the file fine but the path must exist at runtime from the exe's working directory (hence compile-time-absolute or exe-relative default; CI checkouts move). Linux/macOS containers have no system-store dependency either way (D-07's point — consistent across the 16-config matrix). `load_verify_file` throws on missing file — the code above uses the `error_code` overload and maps to `TLS_CA_LOAD_FAILED`. One more: `host_name_verification` against a raw-IP host can fail — price endpoints are hostnames, and the stub is plain HTTP, so this never bites in-scope paths (noted in Risks).
- Hermetic TLS-negative test option: stub with a self-signed cert + client verifying against the real cacert.pem → `TLS_HANDSHAKE_FAILED`. Requires committing a throwaway test cert pair or generating via OpenSSL API in-fixture; keep **optional/stretch** (§ Testing Strategy) — the mandatory matrix needs no TLS.

### 4. Per-request timeouts (D-10)

`ArmDeadline(ioc, socket, std::chrono::seconds)` (`HTTPCommon.cpp:19-37`) is already duration-parameterized — the new surface simply passes `RequestOptions` values instead of literals at the three arm sites (`:142` 10s connect, `:153` 10s handshake, `:197` 30s read). Two mechanical adjustments:

1. Widen the signature to `std::chrono::milliseconds` (tests inject e.g. 50ms for deterministic timeout scenarios; price defaults set 5000ms each per LPM-06).
2. Generalize the socket parameter: the helper captures `shared_ptr<SslSocket>` (`:22-24`) and cancels via `socket->lowest_layer().cancel()` (`:34`). For a variant stream (`std::variant<tcp::socket, ssl::stream<tcp::socket>>`), cancel becomes `std::visit([](auto &s){ s.lowest_layer().cancel(ec); }, ...)` — same ownership pattern (timer lambda holds the stream shared_ptr, keeping it alive through timeout fire; this is also what makes handshake-timeout safe today, see Risks R1).

The timeout-vs-error discrimination already exists and must be preserved: `deadline.expired->load() ? Error::TIMEOUT : Error::CONNECT_ERROR` (`HTTPCommon.cpp:180-184`, `:168-171` analog for read at `:224-228`) — retry classification (D-11) keys off exactly this distinction.

### 5. Stub server design (TEST-03)

Beast is approved for the test fixture (D-01's explicit carve-out) and precedented in-tree: `SuperGenius/src/api/transport/impl/ws/ws_client_impl.hpp:11-13` includes Beast headers, and `price_retrieval_test.cpp:2-9` already includes the full Beast http/ssl set — so the test CMake already has the include paths working.

**Design** — `SuperGenius/test/testutil/http_stub/` (shared fixture location; Phase 4's `SetPayoutAddress` hermetic conversion reuses it):

```cpp
class HttpStubServer   // test-only; plain HTTP; 127.0.0.1; OS-assigned port
{
public:
    struct ScriptedResponse
    {
        unsigned status = 200;
        std::string contentType = "application/json";
        std::string body;
        std::chrono::milliseconds delay{ 0 };   // sleep before writing — drives read-timeout tests deterministically
        bool hang = false;                      // accept, never respond — read-timeout without delay math
    };
    void OnPath( std::string path, ScriptedResponse r );          // per-path script table; default 404
    void Start();                                                 // bind {127.0.0.1, 0}, spawn accept loop
    uint16_t Port() const;                                        // acceptor.local_endpoint().port()
    std::string Url( std::string path ) const;                    // "http://127.0.0.1:<port><path>"
    void Shutdown();                                              // stop acceptor, close sessions, join thread
};
```

- **OS-assigned port:** `tcp::acceptor a( ioc, { net::ip::make_address("127.0.0.1"), 0 } )` then `a.local_endpoint().port()` — no port races, no fixed-port collisions across parallel ctest shards (R7).
- **Threading:** the stub owns one `io_context` + one dedicated thread (`std::thread([&]{ ioc.run(); })`) started in `Start()`, joined in `Shutdown()`. Test-side client keeps *its own* caller-supplied ioc (D-09) — the two never share executors, avoiding strand/reentrancy hazards. `Shutdown()` must post `acceptor.cancel()/close()` + `ioc.stop()` before join, and use `allow_unused` work-guard teardown so a hung scripted `delay` can't deadlock teardown (bounded delays only).
- **Session model:** accept → `async_read` one request header (path is all we need) → look up script table → optional `steady_timer` wait (`delay`) or park forever (`hang`) → `http::response<http::string_body>` write → close. `Connection: close` per request keeps it stateless (mirrors `HTTPDevice`'s own `Connection: close` request header, `HTTPCommon.cpp:196`).
- **Fixture injection:** tests script `/ok` → 200 `{"genius-ai":{"usd":0.19}}`, `/blocked` → **403 + CloudFront-style HTML body** (the diagnosis fixture), `/ratelimited` → 429 (empty or JSON body), `/slow` → delay 5s (client read-timeout 1s fires first), `/hang` → `hang=true`.
- **Drives the upgraded surface:** every client-side assertion goes through `HTTPClient::Execute` (via the Phase-2 price facade) — the stub never talks to a parallel client (D-01's requirement that the fixture "drives the upgraded HTTPDevice surface").
- **CMake:** build as a small static lib `price_test_support` (or header-only with inline impl) under `test/testutil/http_stub/`, linked by the new suite. `test/testutil/CMakeLists.txt` already `addtest`s from that tree (`:1-2`), so the directory is compiled today.

### 6. PriceQuote/PriceSource types + freshness classifier (QUOTE-01/02, FRESH-02, D-14/D-16)

**Location:** `SuperGenius/src/coinprices/` (module exists with exactly 3 files today: `CMakeLists.txt`, `coinprices.cpp`, `coinprices.hpp`). Two new headers, following the PascalCase header convention from `Coding Standards.md` / CONVENTIONS.md (the lowercase `coinprices.hpp` is legacy; new files go PascalCase): `PriceQuote.hpp`, `PriceFreshness.hpp`. Pure header-only (no .cpp, no linkage changes needed beyond maybe nothing — headers only).

```cpp
// SuperGenius/src/coinprices/PriceQuote.hpp
enum class PriceSource { LocalCache, CoinGecko, GnusPriceService, OnChain };   // QUOTE-02; OnChain reserved (SRC-01)

struct PriceQuote                                       // QUOTE-01
{
    std::string                            asset;       // CoinGecko id ("genius-ai")
    std::string                            currency;    // "usd"
    double                                 price = 0.0;
    std::chrono::system_clock::time_point  timestamp;   // D-14: fetch time == envelope fetchedAt
    PriceSource                            source = PriceSource::CoinGecko;
    bool                                   stale  = false;
    int64_t FetchedAtEpochSeconds() const;              // interop with Phase-1 envelope (01-CONTEXT D-11)
};

// SuperGenius/src/coinprices/PriceFreshness.hpp
enum class FreshnessBand { Fresh, StaleButUsable, Unavailable };
FreshnessBand ClassifyFreshness( std::chrono::system_clock::time_point fetchedAt,
                                 std::chrono::system_clock::time_point now );   // FRESH-02, D-16
```

- **`system_clock::time_point` over int64 epoch** (recommended): D-14 aligns with the envelope's `fetchedAt` epoch seconds, and band math is plain subtraction; the epoch accessor keeps wire-format interop explicit at the boundary. Planner may flip to int64 seconds — either satisfies D-14 as long as semantics are documented; recommend time_point + accessor for type safety.
- **Boundary closure (D-16):** `age <= 60s` → Fresh (exactly-60s is Fresh); `60s < age <= 5min` → StaleButUsable (exactly-5min is StaleButUsable); `> 5min` → Unavailable. Implement with `<=` on both upper bounds — no half-open traps.
- **Constants:** expose `kFreshMaxAge = 60s`, `kStaleMaxAge = 5min` as `inline constexpr` in the header so Phase 3's band-aware fallback and any test share one definition (01-CONTEXT D-12 gates use the same numbers).
- **Unit tests:** pure, no sockets — a table test at 0s, 59.9s, exactly 60s, 60.1s, 4:59, exactly 5:00, 5:00.001 asserting the D-16 closures; plus `PriceSource`/`PriceQuote` compile-and-field tests.

### 7. Retry/backoff + 429 hold-off timer (LPM-07, D-11..D-13)

Today's retry is the hostile one from the diagnosis: fixed 3 attempts with 250/500ms sleeps that re-trigger CoinGecko's limiter (`coinprices.cpp:124-140` — `sleep_for` at `:139`), and it retries *everything* including what will be 403/429 bodies.

**Deliverable shape** — `SuperGenius/src/coinprices/PriceRetryPolicy.hpp` (header + small cpp, or folded into the price facade):

```cpp
struct RetryConfig                       // D-12: fixed schedule, injectable constants
{
    int         maxAttempts      = 3;                        // cap 3 total
    std::array<std::chrono::milliseconds, 2> backoffBeforeRetry{ 1000ms, 2000ms }; // then 4s wait after 3rd? see note
    // tests construct with all-zero backoff for determinism
};

enum class RetryDecision { Retry, GiveUp };

// D-11 classification — transport errors ONLY
bool IsTransient( PriceFetchError e );   // TIMEOUT, CONNECT_RESET (CON_INTERRUPT), DNS (COULD_NOT_RESOLVE)
                                         // -> false for any status-bearing error, parse errors, 403, 429

RetryDecision ShouldRetry( PriceFetchError e, int attempt, const RetryConfig & );
```

- **Transient set (D-11):** `TIMEOUT`, `CON_INTERRUPT` (maps to connection reset), `COULD_NOT_RESOLVE` (DNS). Everything carrying an HTTP status — 403, 429, any 4xx/5xx — and all parse/malformed errors: `false`, fall through immediately.
- **Schedule (D-12):** attempts 1→2 wait 1s, 2→3 wait 2s, cap 3 attempts (the "4s" is the would-be next step that never runs; keep the constant in the array for completeness or document cap-3 as the truncation — planner wording choice, tests assert *no fourth attempt*).
- **429 hold-off (D-13):** client-side per-tier state in the price facade:

```cpp
class RateLimitHoldOff
{
public:
    using Clock = std::function<std::chrono::system_clock::time_point()>;   // injectable for tests
    explicit RateLimitHoldOff( Clock now = []{ return std::chrono::system_clock::now(); } );
    void   TriggerHoldOff( std::chrono::seconds duration );   // a 429 sets hold-until = now + duration
    bool   IsHeldOff() const;                                 // true => skip CoinGecko tier entirely
private:
    std::chrono::system_clock::time_point holdUntil_{};
    Clock                                  now_;
};
```

  Duration: the diagnosis showed minutes-scale cooldowns with **no `Retry-After`/`x-ratelimit-*` headers** (coingecko memory:11) — so the duration is a local constant (recommend ≥60s to satisfy LPM-07's "no sub-minute retries"), never parsed from headers that don't exist. Injectable clock makes `TriggerHoldOff(60s); IsHeldOff()==true; advance clock; IsHeldOff()==false` a deterministic unit test.
- **Placement:** retry-state and hold-off live in the SuperGenius price facade (per D-13's "client-side"), *not* in AsyncIOManager — the transport stays a single-shot request/response primitive; the policy composes it. Phase 3's manager consumes both as-is.

### 8. Error taxonomy (LPM-05, D-15)

Follow `CoinGeckoPriceRetriever::PriceError` (`coinprices.hpp:22-30`, category at `coinprices.cpp:5-27`) — enum + `OUTCOME_CPP_DEFINE_CATEGORY_3` message function — extended per D-15 to carry status:

```cpp
// SuperGenius/src/coinprices/PriceFetchError.hpp  (or folded into the facade header)
enum class PriceFetchError
{
    EmptyInput = 1, NetworkError, JsonParseError, NoDataFound,
    RateLimitExceeded, DateTooOld,          // legacy values preserved (D-15 follows the existing pattern)
    HttpStatus,                             // any non-2xx; status carried alongside (below)
    Blocked,                                // 403 WAF — distinct so callers can special-case logging
};
```

Carrying the number alongside an `outcome::result` error_code enum: the enum value can't hold the int, so the facade returns `outcome::result<T, PriceFetchFailure>` where `struct PriceFetchFailure { PriceFetchError code; unsigned httpStatus = 0; }` (libp2p outcome supports custom error types), **or** — simpler, zero new machinery — keep `result<T>` with plain enum and guarantee the status appears in `message()`:

**The structural guarantee LPM-05 asks for does not live in the enum at all — it lives in the layering:**
1. Transport (`HTTPClient::Execute`) returns `Response{status, headers, body}` on *success*. A 403 is a **successful transport** with `status=403`; there is no code path where a 403 body is delivered without its status.
2. The price facade checks `response.status == 200` **before** any rapidjson call; non-200 maps to `PriceFetchError::Blocked`/`HttpStatus`/`RateLimitExceeded` with the message formatted `"HTTP 403 (blocked) from <url>"` — the log line contains the literal `403` (roadmap criterion 1).
3. Therefore `JsonParseError` is *unreachable* for non-200 bodies by construction — no discipline required.

Recommendation: struct-error variant (`PriceFetchFailure`) so tests can assert `failure.httpStatus == 403` without string-matching; fall back to message-only if the planner prefers minimal outcome gymnastics. Either satisfies D-15; the layering guarantee is the non-negotiable part.

### 9. Windows build mechanics (repo-memory grounded)

From `/memories/repo/thirdparty-inner-vcxproj-rebuild.md` — editing AsyncIOManager sources and running `cmake --build thirdparty\build\Windows\Release --target AsyncIOManager` **does nothing useful**: the top-level `AsyncIOManager.vcxproj` is a wrapper; the real project is nested. Surgical sequence:

1. `MSBuild.exe W:\gnus\GeniusNetwork\thirdparty\build\Windows\Release\AsyncIOManager\src\AsyncIOManager-build\src\AsyncIOManager.vcxproj /p:Configuration=Release /p:Platform=x64 /m` (MSBuild at `C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe`, not on PATH).
2. Copy the fresh lib from `...\AsyncIOManager-build\src\Release\AsyncIOManager.lib` → `...\AsyncIOManager\lib\AsyncIOManager.lib` (SuperGenius links against `lib\` — the two trees drift).
3. Rebuild the SuperGenius target (linker picks the lib up by timestamp).

Consumption chain (verified): `SuperGenius/build/CommonBuildParameters.cmake:406-409` sets `AsyncIOManager_INCLUDE_DIR=${_THIRDPARTY_BUILD_DIR}/AsyncIOManager/include`, `AsyncIOManager_DIR=.../lib/cmake/AsyncIOManager`, `find_package(AsyncIOManager CONFIG REQUIRED)`; `coinprices/CMakeLists.txt:2,4,14` uses `${AsyncIOManager_INCLUDE_DIR}` + links `AsyncIOManager` PRIVATE. **New public headers must land in `AsyncIOManager/include/`** (installed by `AsyncIOManager/CMakeLists.txt:74`) — headers in `src/` would be invisible to SuperGenius.

Submodule/branch state (verified read-only today):
- `thirdparty/AsyncIOManager` is **detached HEAD at `009dc3d`** (a `origin/main`→`develop` merge) — D-05's `dev_tokenprice` branch must be created from this commit first thing.
- `thirdparty` superproject is on `develop` — the AsyncIOManager pointer bump needs a thirdparty commit (D-05 says branch `dev_tokenprice` there too).
- `SuperGenius` is already on `dev_tokenprice`.
- Root `GeniusNetwork` is on `dev_persisprocresults` — flag for the planner: root pointer bump (thirdparty + SuperGenius) is a completion-time commit; **do not** switch the root branch mid-phase without the user.
- Commit order innermost-first: AsyncIOManager → thirdparty (pointer) → SuperGenius → root. Never push (standing memory).

CI note: the 16-config matrix builds thirdparty from scratch, so new files in `src/CMakeLists.txt` need no matrix changes; the new SuperGenius test suite registers through the normal `addtest` path (`SuperGenius/cmake/functions.cmake:1-26` — GTest + ctest + `test_bin` output + `disable_clang_tidy` built in).

### 10. Implementation risk register

| # | Risk | Evidence | Mitigation |
|---|------|----------|------------|
| R1 | SSL stream destroyed while handshake in flight on timeout | Timer lambda captures `socket` shared_ptr (`HTTPCommon.cpp:27-31`), async-op chains capture `self`/socket — keep identical ownership in `HTTPClient`; cancel via `lowest_layer().cancel()` then deliver `TIMEOUT` exactly once (guard with the `expired` atomic as today) |
| R2 | One `HTTPLoader` singleton for both schemes can't distinguish http/https (scheme stripped before dispatch) | `FileManager.cpp:77-81` strips prefix; `HTTPLoader.cpp:30-31` | Two instances with scheme/default-port flags (§2) — never re-register `this` for both |
| R3 | Existing `LoadASync` consumers regress | `processing_subtask_queue_accessor_impl.cpp:388`, `coinprices.cpp:178/305/454`, `GeniusNode.cpp:1698` | `HTTPDevice` + `HTTPLoader` https path untouched; new code is a sibling; enabling "http" is additive (today it throws `range_error`, `FileManager.cpp:58`) |
| R4 | Singleton init order / double registration | `FileManager::InitializeSingletons` (`FileManager.cpp:45-55`) called repeatedly (e.g. `coinprices.cpp:174`) | Keep `InitializeSingleton` idempotent (`_instance == nullptr` guard as today, `HTTPLoader.cpp:18-23`); plain instance gets the same guard |
| R5 | Stub port races / parallel-shard collisions | fixed ports collide under ctest sharding | Bind `{127.0.0.1, 0}`, read `local_endpoint().port()` after bind (§5) |
| R6 | Stub teardown deadlock (scripted delay/session threads) | one-thread io_context + join | `Shutdown()` posts acceptor close + session cancel + `ioc.stop()` before join; only bounded `delay`s used for timeout tests; `hang` sessions closed by socket close on teardown |
| R7 | cacert.pem missing at runtime → `load_verify_file` throws | OpenSSL behavior; no pem exists in SuperGenius today | Use the `error_code` overload → `TLS_CA_LOAD_FAILED` error, never an exception across the API; compile-time default path + config override (D-07); tests run plain-HTTP so unaffected |
| R8 | `host_name_verification` fails for raw-IP hosts | RFC 6125 semantics | In-scope URLs are hostnames (api.coingecko.com, token.gnus.ai); stub is plain HTTP. Document: don't point the verifying surface at `https://<ip>` |
| R9 | Beast parser inside AsyncIOManager breaks some platform build | Beast is header-only; Boost 1.85 ships it (`thirdparty/boost/libs/beast/include` verified); `WSCommon.cpp:83` already compiles Beast in this lib | Same include/link environment as WSCommon; if any config fails, fall back to raw status-line parsing (§1 option b) — surface unchanged either way |
| R10 | Read-until-EOF assumes `Connection: close` | `HTTPCommon.cpp:196` sends it; stub replies per-request close | New client also sends `Connection: close`; no keep-alive parsing needed |
| R11 | `variant` stream + deadline cancel plumbing mistakes | new code | Centralize cancel in one `std::visit` helper; unit-test timeout against `/slow` and `/hang` stub paths |
| R12 | Windows Firewall prompt on listen | localhost bind usually exempt | Bind 127.0.0.1 only (never 0.0.0.0); CI runners don't prompt for loopback listeners |
| R13 | Historical endpoints (`getHistoricalPrices`/`Range`) still use throwaway ioc + LoadASync | `coinprices.cpp:296-336`, `:444-483` | Explicitly out of scope (kept compiling); Phase 2 touches only the current-price path |

---

## Recommended Architecture

Honor D-01..D-16 exactly; the planner authors plans against this shape.

**AsyncIOManager (branch `dev_tokenprice`, new files only):**

```
thirdparty/AsyncIOManager/
├── include/
│   ├── HTTPTypes.hpp        (new) RequestOptions / Response / ClientError + outcome category
│   └── HTTPClient.hpp       (new) sibling status-aware device: Execute (async, caller ioc),
│                             ExecuteBlocking; per-request UA/timeouts/CA (D-08/D-09/D-10);
│                             plain-or-TLS stream; verify_peer+load_verify_file+SNI+
│                             host_name_verification when CA provided (D-06/D-07)
└── src/
    ├── HTTPClient.cpp       (new) impl — ArmDeadline pattern reused, Beast sync parse of
    │                          buffered response (or raw parse; planner choice)
    ├── HTTPLoader.cpp       (mod) scheme-aware ctor (tls flag + default port 443/80);
    │                          registers BOTH "https" (legacy HTTPDevice path) and "http"
    │                          (new HTTPClient adapted to legacy ResultType)   (D-03)
    └── CMakeLists.txt       (mod) add HTTPClient.cpp
```

`HTTPDevice.cpp/.hpp`: **untouched** (D-02's strongest form).

**SuperGenius (branch `dev_tokenprice`):**

```
SuperGenius/src/coinprices/
├── PriceQuote.hpp           (new) PriceSource enum (QUOTE-02) + PriceQuote struct (QUOTE-01),
│                            system_clock timestamp = fetch time (D-14), epoch accessor
├── PriceFreshness.hpp       (new) FreshnessBand + ClassifyFreshness with closed-on-fresh
│                            boundaries (D-16); kFreshMaxAge=60s / kStaleMaxAge=5min constants
├── PriceFetchError.hpp      (new) D-15 taxonomy: legacy PriceError values + Blocked/HttpStatus,
│                            PriceFetchFailure{code, httpStatus} struct-error carrier
├── PriceRetryPolicy.hpp/.cpp(new) RetryConfig (1s/2s cap-3, injectable), IsTransient (D-11),
│                            ShouldRetry; RateLimitHoldOff with injectable clock (D-13)
├── PriceHttpClient.hpp/.cpp (new) facade over sgns::HTTPClient: price defaults (CoinGecko-
│                            friendly UA per D-08, 5s timeouts per D-10), status gate before
│                            any JSON parse (LPM-05 structural guarantee), retry composition
│                            (LPM-07); consumed by Phase 3's manager
├── certs/cacert.pem         (new) pinned CA bundle (D-07), path configurable
└── CMakeLists.txt           (mod) add new sources; compile-def default cacert path
```

**Test fixture + suite:**

```
SuperGenius/test/testutil/http_stub/
├── HttpStubServer.hpp/.cpp  (new) Beast, 127.0.0.1:0, per-path ScriptedResponse{status,body,
│                            contentType,delay,hang}, own io_context+thread, clean Shutdown
└── CMakeLists.txt           (new) price_test_support static lib
SuperGenius/test/src/price_http_client/
├── CMakeLists.txt           (new) addtest(price_http_client_test ...) — ctest-registered,
│                            hermetic, links coinprices + price_test_support
└── price_http_client_test.cpp (new) matrix below
```

**Plan-seed mapping note (roadmap wording correction per 02-CONTEXT deferred section):** 02-01 → the SuperGenius type headers + classifier tests; 02-02 → the AsyncIOManager `HTTPClient` + HTTPLoader http registration + facade (same acceptance assertions as the Beast-client seed: truthful status, SNI+verify_peer+pinned CA, ≈5s timeouts, UA); 02-03 → stub fixture + client-level matrix; 02-04 → retry/hold-off. Waves: 02-01 ∥ 02-02 independent; 02-03 after 02-02 (needs the surface + can test transport directly); 02-04 after 02-02 (classification needs the error taxonomy; hold-off is pure unit).

---

## Dependencies & Integration Points

- **Submodule flow (D-05):** `thirdparty/AsyncIOManager` (create `dev_tokenprice` from current detached HEAD `009dc3d`) → commit; `thirdparty` superproject (create `dev_tokenprice` from `develop`) → pointer bump commit; `SuperGenius` (`dev_tokenprice`, already checked out) → source + test commits; root `GeniusNetwork` (currently `dev_persisprocresults`) → pointer bump at completion, flag to user, **never push**.
- **CMake/link facts:** SuperGenius finds AsyncIOManager via config package (`CommonBuildParameters.cmake:406-409`); `coinprices` links `AsyncIOManager` PRIVATE + `${AsyncIOManager_INCLUDE_DIR}` (`src/coinprices/CMakeLists.txt:2,14`); public headers must be in `AsyncIOManager/include/` (installed, `AsyncIOManager/CMakeLists.txt:74`); Windows surgical rebuild = inner vcxproj → copy lib → rebuild SuperGenius target (§9, repo memory).
- **Consumer seams:** Phase 3 consumes `PriceQuote`, `PriceFreshness`, `PriceRetryPolicy`/`RateLimitHoldOff`, and `PriceHttpClient` (its io_context ownership per D-09 replaces today's throwaway per-request ioc at `coinprices.cpp:169`). Phase 4 consumes endpoint configurability + the stub fixture. The `GeniusNode::GetCoinprice` seam (`GeniusNode.cpp:3510-3565`) is **not** touched in Phase 2 (Phase 4's LPM-10).
- **Contract alignment:** `PriceQuote::timestamp` ≡ envelope `fetchedAt` (01-CONTEXT D-11: per-id max) — Phase 2 defines the type + classifier only; envelope *parsing* is Phase 3.
- **Test wiring:** `addtest()` gives ctest registration, GTest link, `test_bin` output, `disable_clang_tidy` automatically (`cmake/functions.cmake:1-26`); new suite added via `test/src/CMakeLists.txt` `add_subdirectory(price_http_client)` (pattern: `:19` for price_retrieval). No CI matrix changes.

## Testing Strategy

**Hermetic client-level matrix** (`price_http_client_test`, stub-driven, zero network egress):

| Stub path | Script | Assertion |
|-----------|--------|-----------|
| `/ok` | 200, `{"genius-ai":{"usd":0.19}}` | Facade returns prices; `PriceQuote` fields correct (source=CoinGecko, timestamp≈now, stale=false) |
| `/blocked` | 403 + CloudFront-style HTML | Error is `Blocked`, message contains literal `403`, `httpStatus==403`; **rapidjson never invoked** (assert via classification — `JsonParseError` impossible); 403 not retried (attempt count == 1) |
| `/ratelimited` | 429 | `RateLimitExceeded` + `RateLimitHoldOff.IsHeldOff()==true`; with injected clock advanced past duration → false; CoinGecko tier skip logic verified; not retried |
| `/slow` | 200 delayed 5s, client readTimeout 1s | `TIMEOUT`, classified transient, retried per policy (backoff 0ms in tests), exactly cap-3 attempts |
| `/hang` | accept, never respond | Same as `/slow` (deterministic, no timing math) |
| `/notfound` | 404 | `HttpStatus` w/ status 404, not retried |
| (TLS stretch) | https stub, self-signed cert, client CA = real bundle | `TLS_HANDSHAKE_FAILED` — optional; requires committed test cert or in-fixture OpenSSL generation. Not blocking; core matrix needs no TLS |

**Unit tests (no sockets):** classifier boundary table (0 / 59.9 / 60.0 / 60.1 / 4:59 / 5:00 / 5:00.001 — D-16 closures); `IsTransient` truth table over the full error enum; `ShouldRetry` attempt-count cap with all-zero backoff config; hold-off clock injection; `PriceQuote` field/round-trip.

**Determinism:** all sleeps are policy-config zeros or stub-owned bounded delays; no wall-clock dependence except the injectable clock; loopback-only sockets; OS-assigned ports (parallel-safe).

## Open Questions

None blocking. Two resolved-by-default choices the planner may revisit:
1. **Beast-inside-AsyncIOManager for response parsing** (recommended, §1) vs raw status-line parsing — both honor D-01; WSCommon precedent makes Beast low-risk.
2. **cacert.pem runtime resolution** default (compile-time path + config override, §3) — exact mechanism (compile definition vs exe-relative) is plan-level detail; D-07's "configurable at construction" is satisfied either way.

---
*Researched: 2026-09-30 · gsd-phase-researcher · all file/line citations verified against working tree at research time*
