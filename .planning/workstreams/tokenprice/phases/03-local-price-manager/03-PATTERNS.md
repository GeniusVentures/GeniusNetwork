# Phase 3 Pattern Mapping — Local Price Manager

**Phase:** 3 — Local Price Manager (workstream `tokenprice`)
**Date:** 2026-10-01
**Inputs:** 03-CONTEXT.md (D-01..D-16) · 03-RESEARCH.md §1–§8 · working-tree code (all excerpts below read today; line numbers verified)
**Scope:** pattern extraction only — every file Phase 3 creates/modifies, its closest in-tree analog, and the concrete pattern to replicate.

---

## File Mapping Table

| # | New/Modified file | Role | Data flow | Closest analog | Pattern source (verified lines) |
|---|---|---|---|---|---|
| 1 | `src/coinprices/IPriceSource.hpp` (new) | Pure-virtual tier seam: `FetchPrices(ids, currency) → PriceResult<vector<PriceQuote>>` (D-13) | manager → tier (CoinGecko / token.gnus.ai); tests → `FakePriceSource` | `thirdparty/AsyncIOManager/include/FileLoader.hpp` (pure-virtual loader interface) + `PriceHttpClient::FetchPrices` signature | excerpt P-4 |
| 2 | `src/coinprices/PriceResponseParsers.hpp/.cpp` (new; name planner's choice) | `ParseCoinGeckoSimplePrice` (moved from facade, behavior-identical) + `ParseGnusPriceEnvelope` (Phase-1 envelope contract, D-16) | 200-body string → `vector<PriceQuote>`; facade + token.gnus.ai tier both call | `PriceHttpClient.cpp:153-175` (the parse branch being extracted) + `pricecoordinator/src/envelope.ts:17-24` (the contract) | excerpts P-7, P-7b |
| 3 | `src/coinprices/LocalPriceManager.hpp` (new, D-15) | Manager decl: ioc+work+strand+thread, blocking `GetQuotes`, L1 cache, per-currency pending windows, injectable window+clock | caller thread → future ← strand handler → tier chain → L1 → waiter | `HttpStubServer.hpp:69-79` (member layout: ioc / guard / thread) + `PriceRetryPolicy.hpp:80-115` (injectable `Clock`) + `ws_client_impl.hpp:22` (strand typedef) | excerpts P-1, P-3, P-8 |
| 4 | `src/coinprices/LocalPriceManager.cpp` (new, D-15) | Manager impl: ctor starts thread, `GetQuotes` promise/future bridge, `HandleRequestOnStrand`, `DispatchBatchOnStrand` inline chain walk, dtor resolves waiters → guard reset → join | same | `HttpStubServer.cpp:47-60, 100-127` (Start/Shutdown lifecycle) + `HTTPClient.cpp:344-361` (`ExecuteBlocking` promise bridge) + `GeniusNode.hpp:1455-1480` (`HostConnectedness` own-thread caveat) | excerpts P-1, P-2 |
| 5 | `src/coinprices/PriceFetchError.hpp` (mod, D-14) | `PriceFetchFailure` gains transport classification (shape a `optional<http::ClientError>` or b `int`, planner decides) | facade retry loop populates → `IsTransient` consumes | `PriceRetryPolicy.hpp:3` (the `<HTTPTypes.hpp>` include precedent) + `HTTPTypes.hpp:75-86` (`ClientError` enum) | excerpts P-6, P-6a |
| 6 | `src/coinprices/PriceRetryPolicy.hpp/.cpp` (mod, D-14) | `IsTransient` gates on `IsTransientTransport` under `{NetworkError, 0}` (strict) | `PriceFetchFailure` → retry decision | itself — `PriceRetryPolicy.cpp:10-27` (`IsTransientTransport`, already correct) vs `:29-38` (`IsTransient`, the coarse line being fixed) | excerpt P-6b |
| 7 | `src/coinprices/PriceHttpClient.hpp/.cpp` (mod) | D-14: populate transport classification in retry loop (`:113-127`); optionally `ResponseFormat` ctor param + target-builder split + parse-extraction call-through for the token.gnus.ai tier | tier response → parser → quotes | itself — `:93-94` (target builder), `:153-175` (parse branch), `:104-127` (retry loop edit site) | excerpts P-6c, P-7 |
| 8 | `src/coinprices/CMakeLists.txt` (mod) | + `LocalPriceManager.cpp` (+ parser .cpp) in `add_library` | build | itself (`coinprices/CMakeLists.txt:1-6`) | excerpt P-10 |
| 9 | `test/src/price_manager/CMakeLists.txt` + `price_manager_test.cpp` (+ `price_envelope_parse_test.cpp` if split) (new) | 16-case TEST-02 matrix; `FakePriceSource` (scriptable, call-counting); D-16 byte-real envelope fixtures; zero sockets | test → manager → fakes; no `HttpStubServer` link | `test/src/price_facade/CMakeLists.txt` (suite + include dirs) + `price_facade_test.cpp:12-24` (ZeroBackoffConfig / literal fixtures) + `price_quote_test.cpp:16-18` (`kEpochBase`) | excerpts P-8, P-9, P-10 |
| 10 | `test/src/CMakeLists.txt` (mod) | + `add_subdirectory(price_manager)` after `price_facade` (line 23) | build registration | itself (`test/src/CMakeLists.txt:20-23` — the four price suites) | excerpt P-10 |
| 11 | `test/src/price_facade/price_facade_test.cpp` (mod, D-14 fallout) | `IsTransientTruthTable` (`:177-197`) three `{NetworkError,0}` rows carry transport classes + new false rows; `ShouldRetryCapsAtThreeForTransient` (`:199-206`) fixture carries `TIMEOUT` | policy truth table | itself | excerpt P-6d |

**Not touched (Phase 4 owns):** `src/account/GeniusNode.cpp/.hpp` (`GetCoinprice` seam at `GeniusNode.cpp:3508-3565`, `m_tokenPriceCache` — read-only shape reference; its miss-collection loop `:3510-3520` is the model for D-06), `coinprices.cpp` legacy retriever (`:121-210` stays compiling).

---

## Pattern Details

### P-1 — Manager executor lifecycle ← `HttpStubServer` (the closest full precedent)

`HttpStubServer` is the only in-tree class owning *its own* `io_context` + work guard + dedicated thread with clean shutdown — exactly the manager's D-02 shape. Replicate the member layout and the Start/Shutdown discipline.

**Member declaration order** (`SuperGenius/test/testutil/http_stub/HttpStubServer.hpp:65-79`) — the manager mirrors this with `ioc_` first, state maps middle, `thread_` last (reverse-destruction: timers die before ioc; thread joined in dtor body first):

```cpp
    private:
        void DoAccept();
        void HandleSession( boost::asio::ip::tcp::socket socket );

        std::shared_ptr<boost::asio::io_context>                       ioc_;
        std::shared_ptr<boost::asio::ip::tcp::acceptor>                acceptor_;
        std::shared_ptr<boost::asio::executor_work_guard<
            boost::asio::io_context::executor_type>>                   workGuard_;
        std::thread                                                    thread_;
        // ... state maps, mutexes (manager: NO mutexes — strand instead)
```

**Construction** (`HttpStubServer.cpp:47-60`) — ioc → work guard → run thread; the guard keeps `run()` alive with no pending work (the manager has no natural idle point):

```cpp
    void HttpStubServer::Start()
    {
        ioc_      = std::make_shared<boost::asio::io_context>();
        acceptor_ = std::make_shared<tcp::acceptor>( *ioc_ );
        workGuard_ = std::make_shared<boost::asio::executor_work_guard<boost::asio::io_context::executor_type>>(
            ioc_->get_executor() );
        // ... bind/listen ...
        DoAccept();
        thread_ = std::thread( [this]() { ioc_->run(); } );
    }
```

**Shutdown** (`HttpStubServer.cpp:100-127`) — post-then-stop-then-join ordering (the "R6" comment). **One deliberate divergence for the manager:** it has blocked waiters, so the destructor must (a) post onto the strand: cancel window timers + resolve every outstanding waiter promise with a failure (otherwise blocked `GetQuotes` callers hang forever — RESEARCH §1 landmine 1), (b) `work_->reset()`, (c) `thread_.join()` — and **prefer drain-then-join over `ioc_->stop()`** (`stop()` abandons queued handlers; the stub uses it only because it has no waiters):

```cpp
    void HttpStubServer::Shutdown()
    {
        if ( !started_ )
        {
            return;
        }
        started_ = false;
        // Post-then-stop ordering avoids the join-deadlock (R6): the close
        // runs on the io thread, then stop() unblocks run(), then join.
        net::post( *ioc_,
                   [this]()
                   {
                       boost::system::error_code ig;
                       acceptor_->close( ig );
                       // ... close tracked sockets ...
                   } );
        ioc_->stop();
        if ( thread_.joinable() )
        {
            thread_.join();
        }
        workGuard_->reset();
    }
```

Also replicate the destructor delegating to Shutdown (`HttpStubServer.cpp:27-33`: `~HttpStubServer() { if (started_) Shutdown(); }`) — for the manager, unconditional (it always starts its thread in the ctor).

**Timer usage precedent** (same file, `HandleSession` delay path): `std::make_shared<boost::asio::steady_timer>( *ioc_ )` + `expires_after(delay)` + `async_wait` capturing the timer shared_ptr — the exact shape for the ~50ms coalescing window (D-05).

### P-2 — Blocking-caller bridge ← `HTTPClient::ExecuteBlocking` + the `HostConnectedness` caveat

**The promise-from-completion-handler bridge** (`thirdparty/AsyncIOManager/src/HTTPClient.cpp:344-361`). `GetQuotes` uses the same shape, posting onto the strand instead of `Execute`, and parking on `future.get()` (D-01). Note the contrast: `ExecuteBlocking` releases its guard *inside* the handler so `run()` can return; the manager's guard is held forever (different lifecycle — the thread outlives each request):

```cpp
    HTTPClient::Result HTTPClient::ExecuteBlocking( std::shared_ptr<boost::asio::io_context> ioc, const http::RequestOptions &options )
    {
        std::promise<Result>                                                                            promise;
        std::future<HTTPClient::Result>                                                                 future = promise.get_future();
        auto workGuard = std::make_shared<boost::asio::executor_work_guard<boost::asio::io_context::executor_type>>(
            ioc->get_executor() );

        Execute( ioc,
                 options,
                 [&promise, workGuard]( std::shared_ptr<boost::asio::io_context>, Result result )
                 {
                     promise.set_value( std::move( result ) );
                     // Release the guard on the io thread BEFORE run() can
                     // observe it -- held-forever guards deadlock run() (P-8).
                     workGuard->reset();
                 } );

        ioc->run();
        return future.get();
    }
```

`GetQuotes` becomes: empty-ids guard → `promise`/`future` → `boost::asio::post(strand_, [this, ids, currency, p = std::move(promise)]() mutable { HandleRequestOnStrand(...); })` → `return future.get();`.

**The never-call-from-own-thread caveat** (`SuperGenius/src/account/GeniusNode.hpp:1455-1480`, doc comment on `HostConnectedness`) — replicate this Doxygen wording style on `GetQuotes`; a `strand_.running_in_this_thread()` debug assertion is the cheap guard (RESEARCH §8.4):

> *"This helper posts the query onto the pubsub io_context and waits for the answer... When the context is unavailable, already stopped, or when we are already running on it, the query runs inline (posting would deadlock)."*

Phase 3 callers (test threads, and Phase 4's node threads) are all off-thread — safe by construction; document only.

### P-3 — Strand typedef ← `ws_client_impl.hpp:22` (the only in-tree precedent)

`SuperGenius/src/api/transport/impl/ws/ws_client_impl.hpp:22`:

```cpp
    class WsClientImpl : public std::enable_shared_from_this<WsClientImpl> {
    public:
        // Define a type alias for context to make usage clear for the caller
        using Context = boost::asio::io_context;
        using ExecutorType = boost::asio::strand<boost::asio::io_context::executor_type>;
```

Replicate the typedef verbatim in `LocalPriceManager` (private or public-for-tests alias). No other in-tree strand usage exists — greenfield-but-conventional. All manager state (L1, `windows_`, waiters) is strand-confined; **no mutexes anywhere in the manager** (contrast `HttpStubServer`'s three mutexes — it has no strand; the strand replaces them).

### P-4 — `IPriceSource` pure-virtual seam ← `FileLoader.hpp` + the `FetchPrices` signature

The house interface convention (`thirdparty/AsyncIOManager/include/FileLoader.hpp:16-50`): pure-virtual class, `virtual ~FileLoader() {}` public dtor, Doxygen `@brief/@param/@return` per method, zero implementation:

```cpp
class FileLoader
{
public:
    using ResultType =
        outcome::result<std::shared_ptr<std::pair<std::vector<std::string>, std::vector<std::vector<char>>>>>;
    // ...
    /// @brief virtual destructor to prevent memory leaks from derived classes
    virtual ~FileLoader() {}

    /// @brief Load a file into memory
    /// @param filename URL prefix based filename to load from, ...
    /// @return a shared void pointer to the in memory data that was loaded ...
    virtual std::shared_ptr<void> LoadFile( std::string filename ) = 0;
```

`IPriceSource` follows this exactly, with the return type lifted from `PriceHttpClient::FetchPrices` minus the (vestigial — RESEARCH §1: dead parameter, never touched past the signature) `ioc` argument. Interface shape (header-only, no CMake source entry):

```cpp
    class IPriceSource
    {
    public:
        virtual ~IPriceSource() = default;
        virtual PriceResult<std::vector<PriceQuote>> FetchPrices( const std::vector<std::string> &tokenIds,
                                                                  const std::string              &currency = "usd" ) = 0;
    };
```

The Doxygen `@return` wording copies the facade's partial-coverage contract verbatim (`PriceHttpClient.hpp:48-53`): *"One PriceQuote per id the source returned (unknown ids are absent, not errors — Phase-1 D-09 semantics), or a status-bearing PriceFetchFailure."*

**Production adapter** (thin `PriceHttpClientSource` holding `shared_ptr<io_context>` + `PriceHttpClient`, forwarding `client_.FetchPrices(ioc_, ids, currency)` — RESEARCH §3 shape (a), recommended over modifying the Phase-2 ctor): may live in `LocalPriceManager.hpp` or its own header.

### P-5 — Coalescing window state machine ← `pricecoordinator/src/coordinator.ts` (same single-flight, two scopes — D-15)

The DO's `collecting {ids, waiters}` + idempotent `scheduleFlush()` (`SuperGenius/pricecoordinator/src/coordinator.ts:33-35, 66-72, 126-137`) is the design blueprint; the strand makes the C++ version *stronger* (whole handler atomic — no input-gate trick needed):

```ts
  private collecting: { ids: Set<string>; waiters: Waiter[] } | null = null;
  private inflight = false;
  // ...
  private scheduleFlush(): void {
    if (this.flushTimer !== undefined) return; // idempotent
    this.flushTimer = setTimeout(() => {
      this.flushTimer = undefined;
      void this.flush();
    }, BATCH_WINDOW_MS);
  }
```

And the waiter-resolve fan-out (`coordinator.ts:143-146`): `for (const w of batch.waiters) w.resolve(pick(fresh, w.ids));` — each waiter gets its *requested subset* of the batch result (LPM-02/LPM-03 assertion basis: one upstream call, per-waiter subsets).

C++ translation (all strand-confined): `PendingWindow { std::set<std::string> ids; std::vector<PendingWaiter> waiters; std::unique_ptr<steady_timer> timer; }`, `std::map<std::string, PendingWindow> windows_` keyed by currency (D-08). Timer-armed == window-open (the idempotence equivalent: arm only when `timer == nullptr`). Dispatch = move the window out, `windows_.erase(currency)`, then the inline blocking chain walk. D-07 needs no explicit state machine: new posts queue behind the in-flight walk *structurally* (asio handler serialization).

### P-6 — D-14 transport classification (three-file edit, Phase-2 gap #3)

**P-6a — the enum being carried** (`thirdparty/AsyncIOManager/include/HTTPTypes.hpp:74-86`):

```cpp
        /// @brief Error taxonomy for the status-aware client surface.
        enum class ClientError
        {
            RESOLVE_FAILED        = 1,
            CONNECT_FAILED        = 2,
            TLS_HANDSHAKE_FAILED  = 3,
            TLS_CA_LOAD_FAILED    = 4,
            WRITE_FAILED          = 5,
            READ_INTERRUPTED      = 6,
            NO_HEADER             = 7,
            TIMEOUT               = 8,
        };
```

Shape (a) adds `std::optional<http::ClientError> transportError;` to `PriceFetchFailure` (`PriceFetchError.hpp:32-72`, currently `{code, httpStatus}`) — include precedent is `PriceRetryPolicy.hpp:3` (`#include <HTTPTypes.hpp>`); consumers then need `${AsyncIOManager_INCLUDE_DIR}` (the new manager suite must set it, as `price_facade/CMakeLists.txt:5` does). Shape (b) (`int transportErrorValue = 0`) avoids the propagation entirely — planner decides; defaulted member keeps existing `{code, status}` braced initializers compiling.

**P-6b — the gate** (`PriceRetryPolicy.cpp:29-38` today — the coarse line D-14 replaces):

```cpp
    bool IsTransient( const PriceFetchFailure &error )
    {
        // Only pure transport failures are retryable (D-11): any HTTP status
        // at all (403/429/404/5xx...) means the server answered — retrying
        // cannot change the answer.
        if ( error.httpStatus != 0 )
        {
            return false;
        }
        return error.code == PriceFetchError::NetworkError;   // ← the blind spot
    }
```

becomes the strict gate delegating to the already-correct classifier above it (`IsTransientTransport`, `PriceRetryPolicy.cpp:10-27`, true only for `TIMEOUT`/`CONNECT_FAILED`/`RESOLVE_FAILED` — unchanged): `return error.transportError && IsTransientTransport( *error.transportError );` (strict on unclassified — RESEARCH §4 recommendation; flips the two fixtures below). `ShouldRetry` (`:41-51`) and `IsTransientTransport` need **zero changes**.

**P-6c — the population site** (`PriceHttpClient.cpp:113-127` today — classification computed then *discarded*):

```cpp
            if ( !result )
            {
                // Transport failure — classify transiency before mapping
                const auto transportError = result.error();
                lastFailure              = PriceFetchFailure{ PriceFetchError::NetworkError, 0 };
                m_logger->warn( "Price fetch attempt {}/{} failed: transport {} ({})",
                                attempt,
                                retryConfig_.maxAttempts,
                                transportError.message(),
                                IsTransientTransport( static_cast<http::ClientError>( transportError.value() ) )
                                    ? "transient"
                                    : "permanent" );
                if ( ShouldRetry( lastFailure, attempt, retryConfig_ ) == RetryDecision::Retry )
```

becomes: `lastFailure = PriceFetchFailure{ PriceFetchError::NetworkError, 0, static_cast<http::ClientError>( transportError.value() ) };` — the log label reuses the stored value; `ShouldRetry` at `:125` unchanged (gating moved inside `IsTransient`).

**P-6d — the fixture fallout** (`price_facade_test.cpp:177-197`, three rows go false under strict rules):

```cpp
    const std::vector<std::pair<sgns::PriceFetchFailure, bool>> cases = {
        { { E::NetworkError, 0 }, true },           // timeout
        { { E::NetworkError, 0 }, true },           // connection reset
        { { E::NetworkError, 0 }, true },           // DNS failure
```

→ carry `TIMEOUT`/`CONNECT_FAILED`/`RESOLVE_FAILED` in those rows, add false rows for `TLS_HANDSHAKE_FAILED`/`TLS_CA_LOAD_FAILED`/`WRITE_FAILED`/`READ_INTERRUPTED`; `ShouldRetryCapsAtThreeForTransient` (`:199-206`) — its `transient{NetworkError, 0}` fixture becomes `transient{NetworkError, 0, http::ClientError::TIMEOUT}`. Behavioral tests unaffected (real timeout → classifies `TIMEOUT` → still transient → still 3 attempts). Schedule fixture updates **in the same task** as the code change (RESEARCH §8.2 — CI goes red otherwise).

### P-7 — Parse extraction ← the facade's own parse branch; envelope contract from `envelope.ts`

**P-7a — what moves** (`PriceHttpClient.cpp:153-175`, the CoinGecko parse loop — behavior-identical extraction into `ParseCoinGeckoSimplePrice`):

```cpp
            const auto                fetchTime = std::chrono::system_clock::now();
            std::vector<PriceQuote>   quotes;
            for ( const auto &id : tokenIds )
            {
                // IsNumber covers int and double literals — CoinGecko may
                // serialize whole-number prices without a decimal point
                if ( document.IsObject() && document.HasMember( id.c_str() ) && document[id.c_str()].IsObject()
                     && document[id.c_str()].HasMember( currency.c_str() )
                     && document[id.c_str()][currency.c_str()].IsNumber() )
                {
                    PriceQuote quote;
                    quote.asset     = id;
                    quote.currency  = currency;
                    quote.price     = document[id.c_str()][currency.c_str()].GetDouble();
                    quote.timestamp = fetchTime; // D-14: fetch time
                    quote.source    = PriceSource::CoinGecko;
                    quote.stale     = false;
                    quotes.push_back( std::move( quote ) );
                }
                // Unknown ids stay absent — partial coverage, not an error
            }
```

**P-7b — the envelope contract** (`SuperGenius/pricecoordinator/src/envelope.ts:17-24`) — the second parser's spec:

```ts
export interface PriceEnvelope {
  currency: string;
  prices: Record<string, number>;
  fetchedAt: number; // epoch seconds — max(fetchedAt of returned ids)
  age: number; // seconds — now − fetchedAt
  source: SourceKind;   // "coingecko" | "coingecko-cache" — exactly two (D-06)
  stale: boolean;
}
```

Mapping rules (Phase-1 D-06/D-11, pin in comments so reviewers don't "fix" them): `fetchedAt` is epoch **seconds** (never ms — PITFALLS #15) and **max-of-ids, shared by all quotes**; envelope `"coingecko"` → `PriceSource::CoinGecko`, `"coingecko-cache"` → `GnusPriceService` — *a token.gnus.ai-tier response legitimately carries `source=CoinGecko` quotes* (envelope source = the upstream that produced the price, not the serving tier); absent ids are not errors (same partial rule as P-7a). `PriceQuote::FetchedAtEpochSeconds()` (`PriceQuote.hpp:52-61`) is the interop accessor for the seconds round-trip.

**Tier wiring** (RESEARCH §3, prefer option i): a `ResponseFormat { CoinGeckoSimplePrice, GnusEnvelope }` ctor param on `PriceHttpClient` switches target builder (`"/api/v3/simple/price?ids=…&vs_currencies=…"` at `PriceHttpClient.cpp:93` vs `"/v1/prices?ids=…&vs=…"`) + parse call. Retry/hold-off/status-gate machinery is shared — do not duplicate it in a second client class.

### P-8 — Determinism kit: injectable clock, fixed epoch, injectable durations, literal fixtures

All four techniques are established Phase-2 test patterns; the manager suite reuses each:

**Injectable `Clock`** (`PriceRetryPolicy.hpp:80-86`) — the manager constructor takes the same type for L1 band decisions:

```cpp
        /// @brief Injectable clock for hermetic tests.
        using Clock = std::function<std::chrono::system_clock::time_point()>;

        /// @param now Clock source; defaults to the real system clock.
        explicit RateLimitHoldOff( Clock now = [] { return std::chrono::system_clock::now(); } )
            : now_( std::move( now ) )
        {
        }
```

Driven by a captured variable (`price_facade_test.cpp:217-233`, `RateLimitHoldOffWithInjectableClock`): `auto now = time_point{} + hours(1000); auto nowFn = [&now]() { return now; };` … `now += seconds(59);` — advance time by mutation, never sleep.

**Fixed epoch base** (`price_quote_test.cpp:16-18`) — every band test builds timestamps arithmetically; no `system_clock::now()` in tests:

```cpp
    // Fixed epoch base for all timestamp arithmetic — no system_clock::now()
    // anywhere in this suite (hermetic, deterministic).
    const auto kEpochBase = std::chrono::system_clock::time_point{} + std::chrono::seconds( 1727712000 );
```

**Injectable durations** (`price_facade_test.cpp:12-18`) — `coalescingWindow` is a ctor param (0ms default regime for most tests; ~1000ms for LPM-02 dedupe tests where the assertion is fake `callCount == 1` + union-of-ids + per-waiter subsets — "assert on cause, not wall time"):

```cpp
    sgns::RetryConfig ZeroBackoffConfig()
    {
        sgns::RetryConfig config;
        config.backoffBeforeRetry = { std::chrono::milliseconds( 0 ),
                                      std::chrono::milliseconds( 0 ),
                                      std::chrono::milliseconds( 0 ) };
        return config;
    }
```

**Literal fixture strings** (`price_facade_test.cpp:20-24`) — D-16's byte-real envelope JSON embeds the same way, with a comment citing the Phase-1 source file:

```cpp
    const char *kGoodBody = R"({"genius-ai":{"usd":0.19},"bitcoin":{"usd":61234.12}})";
    const char *kCloudFront403 =
        "<!DOCTYPE html><html><body><h1>403 ERROR</h1>...";
```

House test rules carry over: never `sleep_for` in tests (every waiter's future is the synchronization primitive); hermeticity — no `http://`/`https://` strings, no `price_test_support`/`HttpStubServer` link in this suite.

### P-9 — L1 semantics ← `PriceQuote`/`PriceFreshness` types + the `GetCoinprice` miss-collection loop

**Band decisions** consume `PriceFreshness.hpp` unchanged — constants at `:8-9` (`inline constexpr std::chrono::seconds kFreshMaxAge{ 60 }; kStaleMaxAge{ 300 };`) and `ClassifyFreshness` (`:30-45`, closed-on-fresh boundaries: exactly 60s = Fresh, exactly 300s = StaleButUsable — boundary tests assert at these exact deltas per D-16). One cache, two service modes (D-10): Fresh serves normally, StaleButUsable serves **only** when both tiers fail (with `source = LocalCache`, `stale = true`, **timestamp unchanged** — D-11), Unavailable never serves.

**Store granularity**: per-(currency,id) keying — `std::map<std::string, std::map<std::string, PriceQuote>>` keyed currency → id (D-08; quotes for the same id in different currencies are distinct values; the facade already stamps `quote.currency`). Stored entry keeps fetch-time `source` for diagnostics; *serving* rewrites to `LocalCache` on a copy — two representations, one entry, copy-on-serve explicit.

**The miss-collection model** (`GeniusNode.cpp:3510-3520` — read-only; the seam Phase 4 cuts over, and the exact shape D-06 mirrors):

```cpp
        for ( const auto &tokenId : tokenIds )
        {
            auto it = m_tokenPriceCache.find( tokenId );

            if ( it != m_tokenPriceCache.end() && ( currentTime - it->second.lastUpdate ) < m_cacheValidityDuration )
            {
                // Use cached price if it's still valid
                result[tokenId] = it->second.price;
            }
            else
            {
                // Add to the list of tokens that need fresh data
                tokensToFetch.push_back( tokenId );
            }
        }
```

`HandleRequestOnStrand` is this loop with `ClassifyFreshness` replacing the raw duration compare and fresh hits returning via the promise immediately (zero network — LPM-01).

### P-10 — Build & registration wiring

**Library** (`src/coinprices/CMakeLists.txt:1-6` — append the new .cpps; header-only additions (`IPriceSource.hpp`, parser header if header-only) need no listing; no new link dependencies — `Boost::headers` PUBLIC covers strand/timer/promise, `rapidjson` already PRIVATE for parsing):

```cmake
add_library(coinprices
    coinprices.cpp
    PriceRetryPolicy.cpp
    PriceHttpClient.cpp
    # + LocalPriceManager.cpp  (+ parser .cpp)  — NEW
)
```

**Suite** — model on `price_facade` (NOT `price_quote`-minimal and NOT `price_retrieval`, which is a non-ctest live smoke): `addtest()` from `cmake/functions.cmake:8-37` supplies GTest mains, ctest registration, 600s timeout, output dirs, `disable_clang_tidy`, and the Windows Vulkan-DLL copy — nothing extra needed:

```cmake
addtest(price_manager_test
    price_manager_test.cpp
)

target_include_directories(price_manager_test PRIVATE ${AsyncIOManager_INCLUDE_DIR})
target_link_libraries(price_manager_test
    coinprices
    Boost::headers
)
```

The `AsyncIOManager_INCLUDE_DIR` include dir is required if D-14 shape (a) puts `<HTTPTypes.hpp>` into `PriceFetchError.hpp`. Do **not** link `price_test_support`/`HttpStubServer` (zero sockets). `std::thread`/`std::promise` need no explicit Threads link on the existing configs (precedent: `price_http_client_test` uses `std::thread` via the stub with only `Boost::headers`); `target_link_libraries(... Threads::Threads)` is the two-line fix if a platform complains.

**Registration** (`test/src/CMakeLists.txt:20-23` — append after `price_facade`):

```cmake
add_subdirectory(price_retrieval)
add_subdirectory(price_quote)
add_subdirectory(price_http_client)
add_subdirectory(price_facade)
# add_subdirectory(price_manager)  — NEW
```

---

## FakePriceSource sketch (test fixture, P-4 + P-8 combined)

Scriptable result + call recording — the LPM-02/LPM-03/D-07/D-09 assertion engine; zero sockets by construction:

```cpp
    class FakePriceSource : public sgns::IPriceSource
    {
    public:
        struct Call { std::vector<std::string> ids; std::string currency; };
        void SetResult( sgns::PriceResult<std::vector<sgns::PriceQuote>> r ) { result_ = std::move( r ); }
        sgns::PriceResult<std::vector<sgns::PriceQuote>> FetchPrices( const std::vector<std::string> &ids,
                                                                      const std::string              &currency ) override
        {
            ++callCount;
            calls.push_back( { ids, currency } );
            return result_;
        }
        int               callCount = 0;
        std::vector<Call> calls;
    };
```

Assertions it enables (RESEARCH §5 matrix): `callCount == 1` (coalescing), `calls[0].ids == union` (LPM-03), per-call ids disjoint (D-07 no-double-fetch), tier-2 ids == gaps-only (D-09 gap-chase). The D-07 "in-flight" scenario scripts a deferred/late result (e.g. a latch-gated lambda or result sequence) so burst B arrives while batch A walks.

## Conventions checklist (apply to every new file)

- `#pragma once` + Doxygen file-header comment (`PriceHttpClient.hpp:1-8` house pattern)
- Ullman braces; PascalCase types/methods; trailing-underscore privates (`baseUrl_`, `holdOffDuration_`) with `m_logger` for the logger member (both conventions coexist in `PriceHttpClient.hpp:77-80`); `k`-prefixed constants (`kUserAgent`, `kFreshMaxAge`)
- Doxygen `@brief/@param/@return` on every public method; `@note` for contract landmines (boundary rules, own-thread caveat, envelope source semantics)
- `base::Logger m_logger = sgns::base::createLogger( "LocalPriceManager" );` — one per class, exact facade pattern
- `PriceResult<T>` (terminate policy) for all fallible surfaces — never raw outcome
- 4-space indent, includes grouped: own header → project → thirdparty → std (mirror `PriceHttpClient.cpp:7-16`)

## Anti-patterns to avoid (verified hazards)

- **Throwaway per-call ioc at the manager level** (`coinprices.cpp:157-160` — fresh ioc + work guard + `LoadASync` + `ioc->run()` per call): cannot host cross-call state; superseded by D-02. The *leaf* exchange keeping its per-attempt ioc (`PriceHttpClient.cpp:109-110`) is correct and stays — run()-to-completion contexts must never be reused (02-VERIFICATION gap #2).
- **`ioc_->stop()` in the manager dtor** — abandons queued handlers; drain-then-join instead (P-1 divergence note).
- **Unjoined thread** — `std::thread` dtor calls `std::terminate`; the join is mandatory and must precede member destruction (P-1 ordering).
- **Negative caching** — tier failures never write L1 entries (no error caching in v1; bounded by facade hold-off).
- **Re-basing LKG timestamps** — D-11: serve the original fetch time, `stale: true`, `source: LocalCache`, timestamp untouched.
- **Static-lifetime manager** — never a lazy singleton (static-destruction-order fiasco, PITFALLS #12); Phase 4 makes it a `GeniusNode` member.
- **Mutexes in the manager** — the strand replaces them; if a mutex looks necessary, the state isn't strand-confined.
