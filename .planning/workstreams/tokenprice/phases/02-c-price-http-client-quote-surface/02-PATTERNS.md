# Phase 2 Pattern Mapping — C++ Price HTTP Client & Quote Surface

**Phase:** 2 — C++ Price HTTP Client & Quote Surface (workstream `tokenprice`)
**Date:** 2026-09-30
**Inputs:** 02-CONTEXT.md (D-01..D-16) · 02-RESEARCH.md §1–§10 · working-tree code (all excerpts below read today; line numbers verified)
**Scope:** pattern extraction only — every file Phase 2 creates/modifies, its closest in-tree analog, and the concrete pattern to replicate.

---

## File Mapping Table

| # | New/Modified file | Role | Data flow | Closest analog | Pattern source (verified lines) |
|---|---|---|---|---|---|
| 1 | `thirdparty/AsyncIOManager/include/HTTPTypes.hpp` (new) | Pure data types: `RequestOptions`, `Response`, `ClientError` + outcome category | consumed by HTTPClient, HTTPLoader adapter, SuperGenius facade | `include/HTTPCommon.hpp` (`HTTPDevice::Error` enum + outcome aliases) | `HTTPCommon.hpp:20-24, 29-47` |
| 2 | `thirdparty/AsyncIOManager/include/HTTPClient.hpp` (new) | Sibling status-aware device class: `Execute` (async, caller ioc) / `ExecuteBlocking` | façade call → response struct up | `include/HTTPCommon.hpp` (`HTTPDevice` decl, `CompletionCallback` typedef) | `HTTPCommon.hpp:49-68, 85-105` |
| 3 | `thirdparty/AsyncIOManager/src/HTTPClient.cpp` (new) | Impl: resolve → connect → TLS/plain → write → read → parse status/headers/body | one object per request, `shared_from_this` chain | `src/HTTPCommon.cpp` (`HTTPDevice` impl) | `HTTPCommon.cpp:19-46` (deadline), `:85-95` (SNI), `:142-156` (chain), `:193-196` (request), `:207-236` (read) |
| 4 | `thirdparty/AsyncIOManager/src/HTTPLoader.cpp` (mod) | Scheme-aware loader: 2 instances (tls/443 + plain/80), registers BOTH `"https"` and `"http"` | `FileManager::LoadASync` → prefix dispatch → device | itself (`InitializeSingleton` + ctor registration) | `HTTPLoader.cpp:15-35` |
| 5 | `thirdparty/AsyncIOManager/include/HTTPLoader.hpp` (mod) | ctor gains `(bool tls, unsigned defaultPort)`; keep `FileLoader` override surface | same | `include/HTTPLoader.hpp` (SINGLETON_PTR + CompletionCallback) | `HTTPLoader.hpp:12-17, 33-52` |
| 6 | `thirdparty/AsyncIOManager/src/CMakeLists.txt` (mod) | add `HTTPClient.cpp` to STATIC lib | build | itself | `src/CMakeLists.txt:1-16` |
| 7 | `SuperGenius/src/coinprices/PriceQuote.hpp` (new) | `PriceSource` enum + `PriceQuote` struct (QUOTE-01/02, D-14) | produced by façade, consumed by Phase 3 manager | `src/coinprices/coinprices.hpp` (class-local types, `outcome::result` returns) | `coinprices.hpp:14-46` |
| 8 | `SuperGenius/src/coinprices/PriceFreshness.hpp` (new) | `FreshnessBand` + `ClassifyFreshness` (FRESH-02, D-16) | `now − timestamp` → band | (pure function; style analog `PriceQuote.hpp` above) | conventions section |
| 9 | `SuperGenius/src/coinprices/PriceFetchError.hpp` (new) | D-15 taxonomy: legacy `PriceError` values + `Blocked`/`HttpStatus`; `PriceFetchFailure{code, httpStatus}` | façade failure path → Phase 3 logging | `coinprices.hpp:22-30` + `coinprices.cpp:5-27` (`OUTCOME_CPP_DEFINE_CATEGORY_3`) | excerpt P-ERR below |
| 10 | `SuperGenius/src/coinprices/PriceRetryPolicy.hpp/.cpp` (new) | `RetryConfig` (1s/2s cap-3 injectable), `IsTransient` (D-11), `ShouldRetry`, `RateLimitHoldOff` injectable clock (D-13) | error classification → retry decision / tier skip | `coinprices.cpp:124-141` (existing retry loop — the anti-pattern to replace) | excerpt P-RETRY below |
| 11 | `SuperGenius/src/coinprices/PriceHttpClient.hpp/.cpp` (new) | Price façade over `sgns::HTTPClient`: UA/5s-timeout defaults, status gate before JSON, retry composition | stub/CoinGecko → HTTPClient → status gate → rapidjson → `PriceQuote` | `coinprices.cpp:143-210` (`getCurrentPricesOnce`: ioc + work guard + LoadASync + callback + JSON parse) | excerpt P-FACADE below |
| 12 | `SuperGenius/src/coinprices/certs/cacert.pem` (new) | Pinned CA bundle (D-07) | loaded by `RequestOptions::caCertFile` → `load_verify_file` | **no analog** — no `.pem` exists anywhere in SuperGenius (verified). Binary-ish asset: source from curl.se mozilla bundle; do NOT hand-edit | — |
| 13 | `SuperGenius/src/coinprices/CMakeLists.txt` (mod) | add new .cpps; `SGNS_DEFAULT_CACERT_PATH` compile definition | build | itself | `coinprices/CMakeLists.txt:1-16` |
| 14 | `SuperGenius/test/testutil/http_stub/HttpStubServer.hpp/.cpp` + `CMakeLists.txt` (new) | Beast stub server: 127.0.0.1:0, per-path `ScriptedResponse`, own ioc+thread, clean Shutdown | test → stub listens; client (upgraded surface) → stub | `thirdparty/AsyncIOManager/src/WSCommon.cpp` (Beast in-tree) + `src/api/transport/impl/ws/ws_client_impl.hpp:1-16` (Beast includes) + `test/testutil/primitives/CMakeLists.txt` (testutil static lib) | excerpts P-STUB, P-TESTUTIL below |
| 15 | `SuperGenius/test/src/price_http_client/CMakeLists.txt` + `price_http_client_test.cpp` (new) | Hermetic matrix suite (`/ok`,`/blocked`,`/ratelimited`,`/slow`,`/hang`,`/notfound`) | drives façade → stub; no network | `test/src/price_retrieval/` (suite layout) + `cmake/functions.cmake addtest()` (ctest registration) + `test/src/CMakeLists.txt:19` (`add_subdirectory` pattern) | excerpts P-TEST, P-ADDTEST below |

**Not touched (D-02):** `HTTPCommon.cpp/.hpp` (`HTTPDevice`), `FileManager.cpp` registry, `processing_subtask_queue_accessor_impl.cpp`, `coinprices.cpp` historical endpoints (`:296-336`, `:444-483`), `GeniusNode.cpp:3510-3585` seam.

---

## Pattern Details

### P-1 — `HTTPClient.cpp` ← `HTTPCommon.cpp` deadline machinery (the core reuse)

The whole timeout architecture already exists and is parameterized; replicate verbatim, widening `seconds`→`milliseconds` (D-10) and generalizing the socket parameter for the plain/TLS variant stream. `thirdparty/AsyncIOManager/src/HTTPCommon.cpp:19-46`:

```cpp
    using SslSocket = boost::asio::ssl::stream<boost::asio::ip::tcp::socket>;

    struct Deadline
    {
        std::shared_ptr<boost::asio::steady_timer> timer;
        std::shared_ptr<std::atomic_bool>          expired;
    };

    Deadline ArmDeadline( const std::shared_ptr<boost::asio::io_context> &ioc,
                          const std::shared_ptr<SslSocket>               &socket,
                          std::chrono::seconds                            timeout )
    {
        Deadline deadline{ std::make_shared<boost::asio::steady_timer>( *ioc ),
                           std::make_shared<std::atomic_bool>( false ) };
        deadline.timer->expires_after( timeout );
        deadline.timer->async_wait(
            [timer = deadline.timer, socket, expired = deadline.expired]( const boost::system::error_code &error )
            {
                if ( !error )
                {
                    expired->store( true );
                    boost::system::error_code ignored;
                    socket->lowest_layer().cancel( ignored );
                }
            } );
        return deadline;
    }

    void CancelDeadline( const Deadline &deadline )
    {
        boost::system::error_code ignored;
        deadline.timer->cancel( ignored );
    }
```

**Replicate:** timer lambda captures the socket shared_ptr (keeps stream alive through timeout fire — R1 mitigation); `expired` atomic is the timeout-vs-error discriminator used at every failure site (`HTTPCommon.cpp:180-184`):

```cpp
                    handle_read(
                        ioc,
                        outcome::failure( connect_deadline.expired->load() ? Error::TIMEOUT : Error::CONNECT_ERROR ),
                        false,
                        false );
```

Arm at exactly three sites (connect `:142`, handshake `:153`, read `:197`); pass `RequestOptions` values instead of the `10/10/30s` literals.

### P-2 — `HTTPClient.cpp` async chain + TLS setup ← `HTTPCommon.cpp:106-156`

```cpp
        //Create SSL Context
        auto ssl_context = std::make_shared<boost::asio::ssl::context>( boost::asio::ssl::context::tls );

        //Disclude certain older insecure options
        ssl_context->set_options( boost::asio::ssl::context::default_workarounds | boost::asio::ssl::context::no_sslv2 |
                                  boost::asio::ssl::context::no_sslv3 );

        // ponytail: global toggle so tests with self-signed certs can disable verification
        if ( !s_verify_peer )
        {
            ssl_context->set_verify_mode( boost::asio::ssl::verify_none );
        }

        //Create Socket with SSL Context
        auto socket = std::make_shared<boost::asio::ssl::stream<boost::asio::ip::tcp::socket>>( *ioc, *ssl_context );
        if ( !SSL_set_tlsext_host_name( socket->native_handle(), http_host_.c_str() ) )
        {
            unsigned long err = ERR_get_error();
            throw std::runtime_error( "Failed to set SNI: " + std::string( ERR_reason_error_string( err ) ) );
        }

        //Connect socket
        auto connect_deadline = ArmDeadline( ioc, socket, std::chrono::seconds( 10 ) );
        boost::asio::async_connect(
            socket->lowest_layer(),
            *endpoints,
            [self = shared_from_this(), ioc, ssl_context, socket, endpoints, handle_read, connect_deadline](
                const boost::system::error_code &connect_error,
                const boost::asio::ip::tcp::endpoint & )
```

**Replicate:** options/SNI lines as-is; **replace** the `s_verify_peer` no-op block with the D-06/D-07 sequence: `set_verify_mode(verify_peer)` → `load_verify_file(*options.caCertFile, ec)` (error_code overload → `TLS_CA_LOAD_FAILED`, never throw) → `set_verify_callback(ssl::host_name_verification(host))`. Keep the `[self = shared_from_this(), ioc, socket, ..., deadline]` capture shape and the nested `async_connect → async_handshake → write/read` ladder with `CancelDeadline` first in every completion handler.

### P-3 — request build + read-until-EOF ← `HTTPCommon.cpp:192-236`

```cpp
        std::string get_request   = "GET " + http_path_ + " HTTP/1.1\r\nHost: " + http_host_ +
                                    "\r\nUser-Agent: GeniusAI/1.0 (SGNS AsyncIO Manager)\r\nConnection: close\r\n\r\n";
        auto        read_deadline = ArmDeadline( ioc, socket, std::chrono::seconds( 30 ) );
        boost::asio::async_write(
            *socket,
            boost::asio::buffer( get_request ),
            [self = shared_from_this(), ioc, ssl_context, handle_read, socket, read_deadline](
                const boost::system::error_code &write_error,
                std::size_t )
```

…then `async_read(*socket, *headerbuff, transfer_all(), …)` accepting `eof` as success (`:216-221`), vector-izing the streambuf (`:223-226`).

**Replicate:** `Connection: close` stays (R10 — no keep-alive parsing); UA becomes `RequestOptions::userAgent` (D-08); the terminal `find("\r\n\r\n")` slice (`:239-259`, which discards status — LPM-05's defect) is **replaced** by a synchronous Beast parse of the completed buffer: `beast::http::response_parser<beast::http::string_body>` + `parser.put(...)`, yielding `Response{status, reason, headers, body}`.

### P-4 — `HTTPLoader.cpp` two-instance scheme split ← itself + `FileManager` registry

Current state, `thirdparty/AsyncIOManager/src/HTTPLoader.cpp:15-35`:

```cpp
    HTTPLoader *HTTPLoader::_instance = nullptr;

    void HTTPLoader::InitializeSingleton()
    {
        if ( _instance == nullptr )
        {
            _instance = new HTTPLoader();
        }
    }

    HTTPLoader::HTTPLoader()
    {
        //FileManager::GetInstance().RegisterLoader("http", this);
        FileManager::GetInstance().RegisterLoader( "https", this );
    }
```

**Modify to (research §2 — R2: scheme is stripped before dispatch, so one instance CANNOT serve both):**

```cpp
    HTTPLoader::HTTPLoader( bool useTLS, unsigned defaultPort )
        : useTLS_( useTLS ), defaultPort_( defaultPort )
    {
    }

    void HTTPLoader::InitializeSingleton()
    {
        if ( _instance == nullptr )
        {
            _instance = new HTTPLoader( true, 443 );
        }
        FileManager::GetInstance().RegisterLoader( "https", _instance );
        if ( _plainInstance == nullptr )
        {
            _plainInstance = new HTTPLoader( false, 80 );
        }
        FileManager::GetInstance().RegisterLoader( "http", _plainInstance );
    }
```

`LoadASync` dispatch: `https` → legacy `HTTPDevice` (byte-identical, D-02); `http` → `HTTPClient` with `caCertFile=nullopt`, result adapted back into the legacy `ResultType` (filename from path, body only — document that the legacy `http://` path stays status-blind). Idempotency guard (R4) preserved — `FileManager::InitializeSingletons()` is called repeatedly (e.g. `coinprices.cpp:174`). Registry mechanics being extended (`FileManager.cpp:13-16` `loaders[prefix] = handlerLoader`; `FileManager.cpp:77-81` prefix strip then `loader->LoadASync(filePath, ...)`): no changes needed there.

### P-5 — `HTTPTypes.hpp` error surface ← `HTTPCommon.hpp` enum + outcome aliases

`thirdparty/AsyncIOManager/include/HTTPCommon.hpp:20-47`:

```cpp
namespace outcome
{
    using libp2p::outcome::failure;
    using libp2p::outcome::result;
    using libp2p::outcome::success;
}

namespace sgns
{
    using namespace boost::asio;

    class HTTPDevice : public std::enable_shared_from_this<HTTPDevice>
    {
    public:
        enum class Error
        {
            COULD_NOT_RESOLVE = 1,
            HANDSHAKE_ERROR   = 2,
            CONNECT_ERROR     = 3,
            CON_INTERRUPT     = 4,
            NO_HEADER         = 5,
            REQ_FAILED        = 6,
            TIMEOUT           = 7,
        };
        using ResultType =
            outcome::result<std::shared_ptr<std::pair<std::vector<std::string>, std::vector<std::vector<char>>>>>;
```

**Replicate:** same `outcome` alias block, `sgns` namespace, `enum class Error` style with `= 1` first value, and an `OUTCOME_CPP_DEFINE_CATEGORY_3( sgns, http::ClientError, e )` message function in the matching .cpp — exact switch shape from `HTTPCommon.cpp:53-70` (`return "HTTP operation timed out";` … `return "Unknown error";`).

### P-6 — `PriceFetchError.hpp` ← `coinprices` PriceError pattern

`SuperGenius/src/coinprices/coinprices.hpp:22-30` + `coinprices.cpp:5-27`:

```cpp
        // Define error types for specific failures
        enum class PriceError {
            EmptyInput = 1,
            NetworkError,
            JsonParseError,
            NoDataFound,
            RateLimitExceeded,
            DateTooOld
        };
```

```cpp
OUTCOME_CPP_DEFINE_CATEGORY_3( sgns, CoinGeckoPriceRetriever::PriceError, e )
{
    switch ( e )
    {
        case sgns::CoinGeckoPriceRetriever::PriceError::EmptyInput:
            return "Empty Input";
        ...
        case sgns::CoinGeckoPriceRetriever::PriceError::DateTooOld:
            return "Date exceeds year limit";
    }
    return "Unknown error";
}
```

**Replicate (D-15):** keep all six legacy values + add `HttpStatus`, `Blocked`; category function formats the status into the message (`"HTTP 403 (blocked) from <url>"` — roadmap criterion 1); recommended struct-error carrier `PriceFetchFailure{ PriceFetchError code; unsigned httpStatus = 0; }` so tests assert `failure.httpStatus == 403` without string-matching. The structural LPM-05 guarantee lives in the façade layering (status gate before rapidjson), not in the enum.

### P-7 — `PriceRetryPolicy` ← existing retry loop (the anti-pattern being replaced)

`SuperGenius/src/coinprices/coinprices.cpp:124-141` — today: fixed 3 attempts, `250ms * attempt` sleep, retries **everything** (including what will be 403/429 bodies):

```cpp
        static constexpr int kMaxAttempts = 3;
        for ( int attempt = 1; attempt <= kMaxAttempts; ++attempt )
        {
            auto result = getCurrentPricesOnce( tokenIds );
            if ( result || attempt == kMaxAttempts )
            {
                return result;
            }

            const auto delay = std::chrono::milliseconds( 250 * attempt );
            m_logger->warn( "Current price request attempt {}/{} failed: {}; retrying in {} ms",
                            attempt,
                            kMaxAttempts,
                            result.error().message(),
                            delay.count() );
            std::this_thread::sleep_for( delay );
        }
        return outcome::failure( PriceError::NetworkError );
```

**Replicate the shape, change the semantics (D-11/D-12):** same attempt-loop skeleton + warn log; transient set becomes `IsTransient(e)` == TIMEOUT/CON_INTERRUPT/COULD_NOT_RESOLVE only; backoff constants come from injectable `RetryConfig{1000ms, 2000ms}` (tests pass zeros); cap stays 3 with tests asserting *no fourth attempt*. `RateLimitHoldOff` (D-13) is new pure-state code — injectable `Clock = std::function<time_point()>`, `holdUntil_` member, `TriggerHoldOff(s)` / `IsHeldOff()`.

### P-8 — `PriceHttpClient` façade ← `getCurrentPricesOnce`

`SuperGenius/src/coinprices/coinprices.cpp:168-200` — the client being replaced:

```cpp
            // Create HTTP request
            auto                                   ioc      = std::make_shared<boost::asio::io_context>();
            boost::asio::io_context::executor_type executor = ioc->get_executor();
            boost::asio::executor_work_guard<boost::asio::io_context::executor_type> workGuard( executor );
            std::string url = "https://api.coingecko.com/api/v3/simple/price?ids=" + tokenIdsList +
                              "&vs_currencies=usd";
            FileManager::GetInstance().InitializeSingletons();
            std::string res;
            bool        requestSucceeded = true;

            auto result = FileManager::GetInstance().LoadASync(
                url,
                false,
                false,
                ioc,
                [this,
                 &res,
                 &requestSucceeded]( outcome::result<...> buffers )
                {
                    if ( buffers )
                    {
                        res = std::string( buffers.value()->second[0].begin(), buffers.value()->second[0].end() );
                    }
                    else
                    {
                        requestSucceeded = false;
                        m_logger->error( "Failed to get coin price: {}", buffers.error().message() );
                    }
                },
                "file" );

            ioc->run();
```

**Replicate:** the work-guard + `ioc->run()` completion pattern becomes `HTTPClient::ExecuteBlocking` on a **caller-supplied** ioc (D-09 — Phase 3's manager owns it; throwaway per-request ioc dies here). Callback `[this, &res, &requestSucceeded]` capture style and `m_logger->error("... {}", ...)` formatting stay. **New in the façade:** check `response.status == 200` before any rapidjson call (LPM-05 structural guarantee — makes `JsonParseError` unreachable for non-200 by construction); set CoinGecko-friendly UA (D-08); 5s timeouts (D-10); compose `PriceRetryPolicy` + `RateLimitHoldOff`.

### P-9 — Stub server ← Beast precedent in AsyncIOManager + WS client includes

Beast already compiles inside `thirdparty/AsyncIOManager` — `src/WSCommon.cpp:69-83`:

```cpp
        //Create SSL Context, using context::tls to accept the highest version client/server can deal with
        auto ctx = std::make_shared<boost::asio::ssl::context>( boost::asio::ssl::context::tls );

        //Disclude certain older insecure options
        ctx->set_options( boost::asio::ssl::context::default_workarounds | boost::asio::ssl::context::no_sslv2 |
                          boost::asio::ssl::context::no_sslv3 );

        //Create Socket
        auto ws =
            std::make_shared<boost::beast::websocket::stream<boost::asio::ssl::stream<boost::asio::ip::tcp::socket>>>(
                *ioc,
                *ctx );
```

And the include set already proven in a SuperGenius test TU — `test/src/price_retrieval/price_retrieval_test.cpp:1-16`:

```cpp
#include <gtest/gtest.h>
#include <boost/beast/core.hpp>
#include <boost/beast/http.hpp>
#include <boost/beast/ssl.hpp>
#include <boost/beast/version.hpp>
#include <boost/asio/connect.hpp>
#include <boost/asio/ip/tcp.hpp>
#include <boost/asio/ssl/stream.hpp>
...
namespace beast = boost::beast;
namespace http = beast::http;
namespace net = boost::asio;
namespace ssl = boost::asio::ssl;
using tcp = net::ip::tcp;
```

**Replicate:** stub session = accept → `http::async_read` header → script-table lookup → optional `steady_timer` delay / park (`hang`) → `http::response<http::string_body>` write → close. Bind `{net::ip::make_address("127.0.0.1"), 0}` then `acceptor.local_endpoint().port()` (R5); own io_context + `std::thread([&]{ ioc.run(); })`, `Shutdown()` posts close + stop before join (R6). Test-side client keeps its own caller ioc (D-09) — never shared executors.

### P-10 — Test suite + testutil lib ← `price_retrieval` + `addtest()` + testutil static-lib pattern

`SuperGenius/test/src/price_retrieval/CMakeLists.txt:1-16` (note: **live smoke test — deliberately NOT ctest-registered**; the new hermetic suite SHOULD use `addtest` instead):

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

set_target_properties(price_retrieval_test PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/test_bin
)
disable_clang_tidy(price_retrieval_test)
```

`SuperGenius/cmake/functions.cmake:3-30` — `addtest()` gives ctest registration, gtest_main+gmock_main, xunit XML, TIMEOUT 600, `test_bin` output dir, `disable_clang_tidy`, and the Windows Vulkan-DLL copy — all built in:

```cmake
function(addtest test_name)
    add_executable(${test_name} ${ARGN})
    addtest_part(${test_name} ${ARGN})
    target_link_libraries(${test_name}
        GTest::gtest_main
        GTest::gmock_main
    )
    file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/xunit)
    set(xml_output "--gtest_output=xml:${CMAKE_BINARY_DIR}/xunit/xunit-${test_name}.xml")
    add_test(
        NAME ${test_name}
        COMMAND $<TARGET_FILE:${test_name}> ${xml_output}
    )
    set_tests_properties(${test_name} PROPERTIES TIMEOUT 600)
    ...
```

Testutil static-lib pattern — `SuperGenius/test/testutil/primitives/CMakeLists.txt`:

```cmake
add_library(testutil_primitives_generator
    hash_creator.cpp
)
target_link_libraries(testutil_primitives_generator
    blob
)
```

and its parent `test/testutil/CMakeLists.txt` already `add_subdirectory`s from that tree (`:5-6`) — add `add_subdirectory(http_stub)` there. Suite registration: `add_subdirectory(price_http_client)` in `test/src/CMakeLists.txt` (pattern: `:19` `add_subdirectory(price_retrieval)`).

GTest fixture shape from `price_retrieval_test.cpp:28-35`:

```cpp
class PriceRetrievalTest : public ::testing::Test
{
protected:
    static void SetUpTestSuite() {}
    static void TearDownTestSuite() {}
};


TEST_F(PriceRetrievalTest, GetCurrentPrice)
```

### P-11 — CMake edits ← existing lists

`thirdparty/AsyncIOManager/src/CMakeLists.txt:1-16` — append `HTTPClient.cpp` (and keep alphabetical-ish grouping):

```cmake
add_library(AsyncIOManager STATIC
    FILECommon.cpp
    FileManager.cpp
    HTTPCommon.cpp
    HTTPLoader.cpp
    ...
```

Public-header install (why new headers MUST live in `include/`) — `thirdparty/AsyncIOManager/CMakeLists.txt:74`:

```cmake
# Install Headers
install(DIRECTORY "${CMAKE_SOURCE_DIR}/include/" DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}" FILES_MATCHING PATTERN "*.h*")
```

`SuperGenius/src/coinprices/CMakeLists.txt:1-16` — add new sources + compile-def:

```cmake
add_library(coinprices
    coinprices.cpp
)

target_include_directories(coinprices PRIVATE ${AsyncIOManager_INCLUDE_DIR})
target_link_libraries(coinprices
    PUBLIC
    Boost::headers
    logger
    outcome
    PRIVATE
    rapidjson
    AsyncIOManager
)

supergenius_install(coinprices)
```

Add `PriceRetryPolicy.cpp PriceHttpClient.cpp` to the list; `target_compile_definitions(coinprices PRIVATE SGNS_DEFAULT_CACERT_PATH="${CMAKE_CURRENT_SOURCE_DIR}/certs/cacert.pem")` (D-07 default; config override wins).

---

## Conventions (verified from the analogs — apply to every new file)

**AsyncIOManager (thirdparty):**
- Namespace: `sgns` (plain — no nested sub-namespace today; `using namespace boost::asio;` at namespace top). New types may use `sgns::http` per research sketch, but plain `sgns` matches every existing device (`HTTPDevice`, `WSDevice`).
- Headers: PascalCase `HTTPCommon.hpp`, `FileManager.hpp` in `include/`; legacy lowercase allowed (`URLStringUtil.h`). New: `HTTPClient.hpp`, `HTTPTypes.hpp`.
- Members: trailing underscore (`http_host_`, `http_port_`, `downloading_`); logger is the `m_logger` exception.
- Logger: `sgns::asiomgr::Logger m_logger = sgns::asiomgr::createLogger( "HTTPCommon" );` — pass the class name string.
- Errors: nested `enum class Error { X = 1, ... }` + `OUTCOME_CPP_DEFINE_CATEGORY_3( sgns, <Enclosing>::Error, e )` defined at file top BEFORE `namespace sgns`, switch returns `const char*`, trailing `return "Unknown error";`.
- outcome aliases in every header: `namespace outcome { using libp2p::outcome::failure/result/success; }`.
- Async: `std::enable_shared_from_this<>`, lambda chains capture `[self, ioc, socket, handle_read, deadline]`, `boost::asio::post` for callback-on-error paths.
- Singletons: `SINGLETON_PTR( HTTPLoader )` macro + static `_instance` + `InitializeSingleton()` with nullptr guard.
- Braces: Ullman/Allman — opening brace on its own line, even for lambdas; 4-space indent; spaces inside parens `( x, y )` per the reformatted source.

**SuperGenius (`src/coinprices/`):**
- Namespace `sgns`; logger `base::Logger m_logger = sgns::base::createLogger( "CoinPrices" );`.
- New headers PascalCase (`PriceQuote.hpp` etc.) per Coding Standards; the lowercase `coinprices.hpp` is legacy — do not rename it this phase.
- Fallible ops return `outcome::result<T>`; category macro identical to P-6.
- Retry/flow constants: `static constexpr int kMaxAttempts = 3;` — k-prefixed constexpr precedent exists in-tree.

**Tests:** fixture class + `TEST_F`; `disable_clang_tidy` always; `RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/test_bin`; Beast alias block (`namespace beast/http/net/ssl; using tcp`) at TU top.

**cacert.pem:** no analog — treat as a vendored binary asset (curl.se mozilla bundle); never hand-edit, never lint, just pin + reference by path.

---

## Build & Commit Flow

**Windows surgical rebuild for AsyncIOManager changes** (from repo memory `thirdparty-inner-vcxproj-rebuild.md` — top-level vcxproj is a wrapper; the real project is nested):

1. `& "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe" W:\gnus\GeniusNetwork\thirdparty\build\Windows\Release\AsyncIOManager\src\AsyncIOManager-build\src\AsyncIOManager.vcxproj /p:Configuration=Release /p:Platform=x64 /m`
2. Copy fresh lib: `...\AsyncIOManager-build\src\Release\AsyncIOManager.lib` → `...\AsyncIOManager\lib\AsyncIOManager.lib` (SuperGenius links `lib\`; the trees drift)
3. Rebuild the SuperGenius target (linker picks the lib by timestamp)

Verification: marker strings in the exe; `link.read.1.tlog` under `<proj>.dir\Release\<proj>.tlog\` shows consumed libs. SuperGenius finds the package via `build/CommonBuildParameters.cmake:406-409` (`find_package(AsyncIOManager CONFIG REQUIRED)`, includes from `include/` — hence headers land there, never `src/`).

**Submodule commit order (D-05; innermost-first, never push):**

1. `thirdparty/AsyncIOManager` — create `dev_tokenprice` from current detached HEAD `009dc3d`, commit source+CMake
2. `thirdparty` (superproject, on `develop`) — create `dev_tokenprice`, commit the AsyncIOManager pointer bump
3. `SuperGenius` (already on `dev_tokenprice`) — commit coinprices + tests + testutil
4. Root `GeniusNetwork` (currently `dev_persisprocresults`) — pointer bumps at phase completion; flag to user before switching anything; NEVER push any level

---

## PATTERN MAPPING COMPLETE

- `thirdparty/AsyncIOManager/include/HTTPTypes.hpp` — new; analog `HTTPCommon.hpp` enum/outcome-alias block; category macro in a .cpp
- `thirdparty/AsyncIOManager/include/HTTPClient.hpp` — new; analog `HTTPCommon.hpp` `HTTPDevice` decl (enable_shared_from_this, CompletionCallback typedef)
- `thirdparty/AsyncIOManager/src/HTTPClient.cpp` — new; analog `HTTPCommon.cpp` (ArmDeadline P-1, TLS/SNI P-2, request/read P-3, Beast sync parse replaces the `\r\n\r\n` slice)
- `thirdparty/AsyncIOManager/src/HTTPLoader.cpp` — mod; itself (two-instance scheme split, `"http"`+`"https"` registration)
- `thirdparty/AsyncIOManager/include/HTTPLoader.hpp` — mod; ctor `(bool tls, unsigned defaultPort)`
- `thirdparty/AsyncIOManager/src/CMakeLists.txt` — mod; append `HTTPClient.cpp` to STATIC list
- `SuperGenius/src/coinprices/PriceQuote.hpp` — new; analog `coinprices.hpp` type/namespace style
- `SuperGenius/src/coinprices/PriceFreshness.hpp` — new; pure classifier, closed-on-fresh bounds (D-16)
- `SuperGenius/src/coinprices/PriceFetchError.hpp` — new; analog `PriceError` + `OUTCOME_CPP_DEFINE_CATEGORY_3` (P-6)
- `SuperGenius/src/coinprices/PriceRetryPolicy.hpp/.cpp` — new; analog retry loop skeleton, semantics replaced (P-7)
- `SuperGenius/src/coinprices/PriceHttpClient.hpp/.cpp` — new; analog `getCurrentPricesOnce` work-guard/callback pattern (P-8)
- `SuperGenius/src/coinprices/certs/cacert.pem` — new; NO analog (vendored curl.se bundle)
- `SuperGenius/src/coinprices/CMakeLists.txt` — mod; new sources + `SGNS_DEFAULT_CACERT_PATH` (P-11)
- `SuperGenius/test/testutil/http_stub/` (`HttpStubServer.hpp/.cpp` + CMakeLists) — new; analogs `WSCommon.cpp` Beast (P-9) + testutil static-lib CMake (P-10)
- `SuperGenius/test/src/price_http_client/` (CMakeLists + test) — new; analog `price_retrieval` suite + `addtest()`; registered via `test/src/CMakeLists.txt` + `testutil/CMakeLists.txt` add_subdirectory

**Written:** `W:\gnus\GeniusNetwork\.planning\workstreams\tokenprice\phases\02-c-price-http-client-quote-surface\02-PATTERNS.md` (single output file; no other files touched; no git commands run)
