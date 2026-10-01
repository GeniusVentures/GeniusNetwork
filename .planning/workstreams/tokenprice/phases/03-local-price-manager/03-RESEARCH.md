# Phase 3 Research: Local Price Manager

**Phase:** 3 — Local Price Manager (workstream `tokenprice`)
**Date:** 2026-10-01
**Status:** Complete — ready for planning
**Inputs:** 03-CONTEXT.md (D-01..D-16, binding) · REQUIREMENTS.md (LPM-01..04, FRESH-01/02 manager-side, TEST-02) · ROADMAP.md Phase 3 · 02-CONTEXT.md + 02-VERIFICATION.md (gaps #2/#3) · 01-CONTEXT.md (envelope contract D-06..D-12) · working-tree code (every citation below read today; SuperGenius `dev_tokenprice`)

---

## Executive Summary — What the planner must know

1. **The manager is a self-contained single-threaded state machine** over one `io_context` + one dedicated thread + one strand. With the fetch chain running **inline inside a strand handler** (blocking the manager thread — consistent with D-03 single-in-flight and D-13's "zero logic change" for the real client), D-03/D-07 are enforced *structurally by asio handler serialization*: no explicit in-flight state machine is needed. This is the single biggest simplification available to the plan.
2. **D-14 is a breaking change to Phase 2 test fixtures** (not just an additive field): `IsTransientTruthTable` and `ShouldRetryCapsAtThreeForTransient` in `price_facade_test.cpp` construct `{NetworkError, 0}` failures that become non-transient under strict classification. The plan must schedule those fixture updates.
3. **D-12 (hold-off skip) needs no new manager code.** The hold-off lives inside each `PriceHttpClient` instance (Phase 2 D-13); a held-off tier returns `RateLimitExceeded{429}` with zero network, and the manager's uniform failure-escalation does the rest. Manager tests document this with a scripted fake.
4. **`PriceHttpClient::FetchPrices`'s `ioc` parameter is currently vestigial** — the implementation creates a fresh `attemptIoc` per attempt (`PriceHttpClient.cpp:109`) and never touches the passed one. D-02's "instances receive the manager's ioc at construction" and D-13's "adapter closes over the ioc" must be reconciled by the planner; the honest reading is the adapter closes over the ioc to satisfy the signature, with **zero runtime effect** today. Do not build machinery around that parameter.
5. **The token.gnus.ai tier cannot reuse `PriceHttpClient`'s parse branch as-is** — the envelope format (`{currency, prices:{id:number}, fetchedAt, age, source, stale}`) differs from CoinGecko's `{id:{usd:number}}`. The envelope parse must be a separately testable unit so D-16's byte-real fixtures can drive it without sockets (`PriceHttpClient` has no transport seam to fake).

---

## 1. Strand-serialized state over a dedicated ioc + thread (D-02/D-03/D-04)

### The idiom, concretely

```cpp
class LocalPriceManager
{
public:
    LocalPriceManager( std::shared_ptr<IPriceSource> coinGeckoTier,
                       std::shared_ptr<IPriceSource> gnusServiceTier,
                       std::chrono::milliseconds      coalescingWindow = std::chrono::milliseconds( 50 ),
                       Clock                          now              = [] { return std::chrono::system_clock::now(); } );
    ~LocalPriceManager();

    PriceResult<std::vector<PriceQuote>> GetQuotes( const std::vector<std::string> &ids,
                                                    const std::string              &currency );

private:
    // Declaration order is load-bearing (see "Destruction order" below):
    // ioc_ first (outlives timers), thread_ last (joined in dtor body first).
    std::shared_ptr<boost::asio::io_context>                       ioc_;
    std::unique_ptr<boost::asio::executor_work_guard<
        boost::asio::io_context::executor_type>>                   work_;
    boost::asio::strand<boost::asio::io_context::executor_type>    strand_;
    // L1 cache, per-currency pending windows (with steady_timers), waiters:
    // ALL strand-confined — no mutexes.
    std::thread                                                     thread_;
};
```

Construction: `ioc_` → `work_ = make_work_guard(ioc_->get_executor())` → `strand_(ioc_->get_executor())` → `thread_([ioc]{ ioc->run(); })`. The work guard keeps `run()` alive forever (the manager has no natural idle point — timers and posted handlers come and go); without it, `run()` returns the instant the queue drains and the thread exits.

**Strand typedef precedent in-tree:** `SuperGenius/src/api/transport/impl/ws/ws_client_impl.hpp:22` — `using ExecutorType = boost::asio::strand<boost::asio::io_context::executor_type>;`. No other in-tree strand usage exists; this is greenfield-but-conventional.

### Blocking-caller bridge (D-01): promise/future set from strand handlers

```cpp
PriceResult<std::vector<PriceQuote>> LocalPriceManager::GetQuotes( ids, currency )
{
    if ( ids.empty() )
    {
        return outcome::failure( PriceFetchFailure{ PriceFetchError::EmptyInput, 0 } );
    }
    std::promise<PriceResult<std::vector<PriceQuote>>> promise;
    auto future = promise.get_future();
    boost::asio::post( strand_,
        [this, ids, currency, p = std::move(promise)]() mutable
        {
            HandleRequestOnStrand( ids, currency, std::move( p ) );
        } );
    return future.get(); // D-01: blocking — caller sleeps until the chain resolves
}
```

**In-tree precedents to cite in the plan:**
- `HTTPClient::ExecuteBlocking` (`thirdparty/AsyncIOManager/src/HTTPClient.cpp:344-361`) — the promise-from-completion-handler bridge, including the subtlety that the work guard must be released *on the io thread before `run()` can observe it* (a held-forever guard deadlocks `run()`; noted "P-8" there). The manager's guard is intentionally held forever (different lifecycle), so that specific hazard doesn't apply — but the promise/future shape is the same.
- `HttpStubServer` (`SuperGenius/test/testutil/http_stub/HttpStubServer.hpp:64-77`, `.cpp:100-127`) — **the closest full precedent for "own ioc + work guard + thread + clean shutdown"**: `Start()` binds/accepts on its own context; `Shutdown()` uses post-then-stop-then-join ordering ("R6" comment) — post the close onto the io thread, `ioc_->stop()`, `join()`, then `workGuard_->reset()`. The manager's destructor follows this discipline.
- `GeniusNode::HostConnectedness` (`SuperGenius/src/account/GeniusNode.hpp:1455-1480`, doc comment) — the post-onto-owning-thread-and-wait bridge with the explicit **deadlock caveat**: "when we are already running on it, the query runs inline (posting would deadlock)". `GetQuotes` must document the same constraint: it may only be called from threads **other than** the manager's runner thread. (Phase 3 tests call it from test threads; Phase 4's `GeniusNode::GetCoinprice` callers are node threads — both safe. No inline-fallback is needed this phase; document the constraint in the header's Doxygen.)

### Destruction order — the two landmines

1. **Member destruction order.** Members destruct in reverse declaration order. Timers (inside per-currency window structs stored in maps) must die before the `io_context`; the `std::thread` must be joined before *anything* dies. Therefore: declare `ioc_` **first**, state maps in the middle, `thread_` **last**, and do the real teardown in the destructor body: (a) post onto strand: cancel all window timers, resolve every outstanding waiter promise with a failure (e.g. `{NetworkError, 0}` + log "shutting down") — **otherwise blocked `GetQuotes` callers hang forever**; (b) `work_->reset()`; (c) `thread_.join()` (do NOT call `ioc_->stop()` if you want queued handlers to drain — `stop()` abandons them; the stub uses `stop()` because it has no waiters — the manager should prefer drain-then-join, matching the "resolve waiters first" step). `std::thread`'s destructor calls `std::terminate` on a joinable thread — the explicit join is mandatory.
2. **Static destruction order fiasco** (PITFALLS.md #12): the manager must be a stack/Member object with deterministic lifetime, never a lazy singleton destroyed at static-destruction time. Phase 3 only builds the class; Phase 4 makes it a `GeniusNode` member. A unit test should construct/destroy the manager in a loop to prove clean teardown.

### The blocking-walk trade-off (accept and document, per D-03/D-04)

The tier fetches (`IPriceSource::FetchPrices` → `PriceHttpClient::FetchPrices`) are **blocking** (up to ~3 attempts × 5s timeout + 1s/2s backoff ≈ 18s worst-case per tier under timeouts; typically far less). Running the chain walk inline inside the strand handler blocks the manager thread for that duration, which means:

- New `GetQuotes` posts (any currency) queue behind the walk and run after — **exactly D-07's "new window dispatches after the in-flight fetch completes"**, for free.
- A window timer armed before the walk fires *late* (after the walk returns). Since D-03 mandates single-in-flight anyway, cross-currency batch serialization is the accepted behavior. Bounded by the tier retry schedule.
- The `sleep_for` backoff inside `PriceHttpClient`'s retry loop (`PriceHttpClient.cpp:127`) executes on the manager's **dedicated** thread — the PITFALLS #11 warning ("never block an Asio thread") is satisfied *because the thread is private*; nothing else runs there. This is the whole point of D-02's dedicated thread: the stall is contained by construction.

An alternative (async `HTTPClient::Execute` chains with strand-posted completions and `steady_timer` backoff) would keep the strand live during fetches but requires restructuring `PriceHttpClient`'s retry loop — contradicting D-13's "zero logic change". **Recommendation: inline blocking walk.** D-04's parenthetical "the fetch runs as async work on the manager's thread" reads as: *async from the caller's perspective* (the caller's `GetQuotes` parks on a future), *inline on the strand thread*. The plan should state this interpretation explicitly.

### The throwaway-ioc pattern being superseded — and the layering clarification

`coinprices.cpp:133` (`getCurrentPricesOnce`) creates a fresh `io_context` per call and runs it to completion on the caller's thread; `PriceHttpClient::FetchPrices` does the same per *attempt* (`PriceHttpClient.cpp:106-109`, comment: "Fresh context per attempt: a run()-to-completion ioc cannot be reliably reused…"). D-02 supersedes this **at the manager level only** — a fresh-per-call ioc cannot host cross-call state (the pending window, the L1, the waiters) and cannot coalesce across threads, and a shared ioc without a single owner thread hits the `run()`/`restart()` tail-coupling landmine (02-VERIFICATION gap #2). **The leaf exchange keeping its throwaway ioc is correct and stays** — it never reuses a context, so gap #2's hazard cannot occur there. The layering to document:

| Layer | Executor | Lifetime | Why |
|---|---|---|---|
| Manager state (L1, windows, timers, waiters) | manager's ioc + strand + 1 thread | process-long (D-02) | cross-call coalescing requires shared, single-owner state |
| Leaf HTTP exchange (`ExecuteBlocking`) | fresh ioc per attempt, inside `PriceHttpClient` | per attempt | run()-to-completion contexts must not be reused (gap #2); no change (D-04) |

**`FetchPrices`'s `ioc` parameter is dead** (verified: `PriceHttpClient.cpp` references the parameter only in its signature at `:43`; the exchange uses `attemptIoc` at `:109`). D-04's "no signature change" therefore costs nothing; D-13's adapter "closing over the manager's ioc" merely forwards an ignored argument. The plan should note this so nobody wires behavior to that parameter.

---

## 2. Coalescing window mechanics (D-05/D-06/D-07/D-08)

### State (all strand-confined)

```cpp
struct PendingWaiter
{
    std::vector<std::string>                                 requestedIds; // full original request
    std::vector<PriceQuote>                                  immediate;    // fresh-L1 subset (D-06)
    std::promise<PriceResult<std::vector<PriceQuote>>>       done;
};

struct PendingWindow
{
    std::set<std::string>                          ids;    // the union so far (D-05)
    std::vector<PendingWaiter>                     waiters;
    std::unique_ptr<boost::asio::steady_timer>     timer;  // null until armed
};

std::map<std::string, PendingWindow> windows_; // key = currency (D-08)
```

Keying by currency gives D-08 (per-currency batches) for free and makes the L1 keying question natural: **recommend `std::map<std::string, std::map<std::string, PriceQuote>>` keyed currency → id** (or `map<pair<id,currency>, PriceQuote>`) — quotes for the same id in different currencies are distinct values; the facade already stamps `quote.currency` per quote.

### The request handler (strand-serialized)

```
HandleRequestOnStrand(ids, currency, promise):
  immediate = []; misses = []
  for id in ids:                      # D-06 — fresh hits serve now
      if L1[currency] has id and ClassifyFreshness(now(), quote.timestamp) == Fresh:
          q = quote; q.source = LocalCache; immediate.push(q)   # LPM-01
      else: misses.insert(id)
  if misses.empty(): promise.set(success(immediate)); return    # zero network (LPM-01)
  w = windows_[currency]
  if w.timer == nullptr:             # first miss arms the window (D-05)
      w.timer = make_unique<steady_timer>(*ioc_)
      w.timer->expires_after(coalescingWindow_)
      w.timer->async_wait(strand-wrapped: DispatchBatchOnStrand(currency))
  w.ids ∪= misses                    # the union (D-05)
  w.waiters.push_back({ids, immediate, promise})
  # caller blocks on future.get() — including the first caller (D-05 accepted cost)
```

### Dispatch + inline chain walk

```
DispatchBatchOnStrand(currency):
  batch = std::move(windows_[currency]); windows_.erase(currency)
  if batch.ids.empty(): return
  remaining = batch.ids
  if not remaining.empty():                       # Tier 1 — CoinGecko direct
      r1 = coinGeckoTier_->FetchPrices(remaining, currency)
      if r1 failed: (log tier-1 failure w/ r1.error().Message())
      else: StoreInL1(r1 quotes); remaining -= ids(r1)
  if not remaining.empty():                       # Tier 2 — token.gnus.ai (D-09 gap-chase)
      r2 = gnusServiceTier_->FetchPrices(remaining, currency)
      if r2 failed: (log)
      else: StoreInL1(r2 quotes); remaining -= ids(r2)
  # Tier 3/4 — assemble per waiter (D-10/D-11 LKG lives in the L1 itself)
  for waiter in batch.waiters:
      quotes = waiter.immediate
      for id in waiter.requestedIds not already covered:
          if L1[currency] has id:
              band = ClassifyFreshness(now(), L1[id].timestamp)
              if band == Fresh:        q = L1[id]; q.source = LocalCache; quotes.push(q)
              elif band == StaleButUsable:  q = L1[id]; q.source = LocalCache; q.stale = true; quotes.push(q)  # D-10/D-11 — timestamp unchanged
              # Unavailable (>5min): never served (FRESH-02)
      quotes.empty() ? promise.set(failure <last tier failure or NoDataFound>) : promise.set(success(quotes))
```

Notes the plan must encode:
- **Wholesale vs partial escalation (D-09)** falls out naturally: a failed tier leaves `remaining` untouched (whole miss-set escalates); a successful-but-partial tier shrinks `remaining` by exactly the ids it returned (gap-chase). Completed ids are never re-added because they were removed from `remaining`. A `Blocked{403}` on one id inside an otherwise-good CoinGecko batch is *indistinguishable from absence* at the facade level (Phase 1 D-09 semantics: absent ids are not errors) — so the "WAF-blocked id poisons the batch" concern D-09 rejected is handled by gap-chasing that id at tier 2.
- **Empty-vs-partial waiter resolution**: follow the facade's convention (`PriceHttpClient.cpp:168-176`): absent ids simply don't appear; only an *empty overall* result is a failure. Surface as an explicit planner decision (Phase 4's `GetCoinprice` maps naturally: present ids → map entries).
- **Cached-error poisoning (PITFALLS #14)**: only quotes that came back in a *successful* tier response enter the L1. Tier failures never write cache entries. There is no negative caching in v1 (a failed fetch is retried on the next request after the window) — bounded by the facade hold-off for 429s.
- **Timer never needs cancel** in normal flow (it fires → dispatch). Cancel paths exist only in destruction.

### Deterministic testing of the window (TEST-02; PITFALLS #19)

The window duration **must be a constructor parameter** (`coalescingWindow_`, default `50ms`). Do not try to inject a clock into `steady_timer` (it's `steady_clock`-typed; not injectable without abstracting the timer — overkill). Instead use the two-regime technique, mirroring Phase 1's empirically-proven approach ("assert on cause, not wall time" — real timers, call-count assertions):

- **Default regime for most tests: window = `0ms`.** `expires_after(0ms)` fires on the next event-loop turn; every test that doesn't assert coalescing gets near-instant dispatch. (Caveat: with 0ms, requests posted *after* the first handler ran may land in a second batch — so 0ms tests must not assert batch counts.)
- **Coalescing regime (LPM-02 tests): window = large (e.g. `1000ms`).** The test posts N requests (N threads calling `GetQuotes`, or N sequential posts made *before* the window can fire), the fake source returns instantly, and the assertion is `fake.callCount == 1` **and** the ids vector the fake received == the union, **and** each waiter's result contains exactly its requested subset. A 1s window vs. microseconds of posting gives CI-proof margins — the same philosophy as Phase 1's `coordinator.coalescing.test.ts` ("two concurrent overlapping id-sets → exactly ONE upstream call", asserted via MSW call count over real 15ms timers).
- **Band/aging tests**: injectable `Clock now` (manager constructor, same `std::function<system_clock::time_point()>` type as `RateLimitHoldOff::Clock` at `PriceRetryPolicy.hpp:82`) — tests hold a `time_point` variable and advance it (pattern: `RateLimitHoldOffWithInjectableClock`, `price_facade_test.cpp:217-233`; `kEpochBase` discipline, `price_quote_test.cpp:16-18`). This drives L1-hit/expiry/LKG-band assertions with zero wall-clock dependence.

**Design reference for the window state machine:** `SuperGenius/pricecoordinator/src/coordinator.ts:33-152` — the DO's `collecting {ids, waiters}` + `inflight` + `scheduleFlush()` idempotent timer + synchronous-prologue-before-await (registration happens before any yielding — the C++ strand makes the whole handler atomic, which is even stronger than the DO's input-gate trick). Worth citing in the plan as the same single-flight pattern, two scopes (03-CONTEXT's D-15 framing).

---

## 3. The `IPriceSource` seam and the two-tier adapters (D-13, D-16)

### Interface (new header, `SuperGenius/src/coinprices/IPriceSource.hpp`)

```cpp
namespace sgns
{
    /// @brief One price-fetch tier behind the LocalPriceManager (D-13).
    /// Shape matches PriceHttpClient::FetchPrices minus the (currently
    /// vestigial) ioc parameter.
    class IPriceSource
    {
    public:
        virtual ~IPriceSource() = default;

        /// @return One PriceQuote per id the source returned (absent ids are
        /// not errors — Phase 1 D-09), or a status-bearing PriceFetchFailure.
        virtual PriceResult<std::vector<PriceQuote>> FetchPrices( const std::vector<std::string> &tokenIds,
                                                                  const std::string              &currency = "usd" ) = 0;
    };
} // namespace sgns
```

Pure virtual class (the expected convention per 03-CONTEXT discretion note). Header-only — no CMake source entry.

### Reconciling D-02's "ioc at construction" with D-13's "adapter closes over the ioc"

Two shapes, both valid; **recommend (a)** for smallest diff to Phase 2 files (D-14 already touches them; nothing else needs to):

**(a) Thin adapter (recommended):**
```cpp
class PriceHttpClientSource : public IPriceSource   // may live in LocalPriceManager.hpp or its own header
{
public:
    PriceHttpClientSource( std::shared_ptr<boost::asio::io_context> ioc,
                           std::string baseUrl, /* PriceHttpClient config args… */ )
        : ioc_( std::move( ioc ) ), client_( std::move( baseUrl ) /* , … */ ) {}

    PriceResult<std::vector<PriceQuote>> FetchPrices( const std::vector<std::string> &ids,
                                                      const std::string              &currency ) override
    {
        return client_.FetchPrices( ioc_, ids, currency );  // ioc forwarded — currently ignored inside
    }
private:
    std::shared_ptr<boost::asio::io_context> ioc_;
    PriceHttpClient                           client_;
};
```

**(b) `PriceHttpClient` itself implements `IPriceSource`** — add an optional ioc constructor parameter stored as a member; a no-ioc `FetchPrices(ids, currency)` overload forwards to the existing method. This is the most literal reading of D-02 ("both PriceHttpClient instances receive the manager's ioc at construction") but changes the Phase 2 constructor signature and adds an overload to a class whose tests construct it positionally (`price_facade_test.cpp:42-47` passes 5 args; appending a 6th defaulted param is safe, but it's still more surface than the adapter).

Either way, the manager holds `std::shared_ptr<IPriceSource> coinGeckoTier_, gnusServiceTier_` — production wires two `PriceHttpClientSource`s (default base URLs `https://api.coingecko.com` and `https://token.gnus.ai`; exact configurability is Phase 4 / LPM-09 — constructor params here so Phase 4 can thread config through), tests wire fakes.

### `FakePriceSource` (test fixture, in the new test suite)

```cpp
class FakePriceSource : public sgns::IPriceSource
{
public:
    struct Call { std::vector<std::string> ids; std::string currency; };
    // Scriptable result sequence or a fixed result; counts every call and
    // records the ids/currency of each — the LPM-02/LPM-03 assertions.
    void SetResult( sgns::PriceResult<std::vector<sgns::PriceQuote>> r );
    int               callCount = 0;
    std::vector<Call> calls;
};
```

Zero sockets by construction (TEST-02's letter). `HttpStubServer`/`price_test_support` is NOT linked into the manager suite — it stays a Phase 4 integration-test asset.

### The envelope-parse problem (the two tiers differ in the parse layer)

`PriceHttpClient`'s single parse branch (`PriceHttpClient.cpp:153-175`) understands CoinGecko's `/simple/price` shape `{ "genius-ai": { "usd": 0.19 } }`. The token.gnus.ai tier returns the **Phase 1 envelope**: `{ "currency": "usd", "prices": { "genius-ai": 0.19 }, "fetchedAt": 1790719234, "age": 17, "source": "coingecko", "stale": false }` (`pricecoordinator/src/envelope.ts:17-24`; query path `GET /v1/prices?ids=<csv>&vs=<currency>` — note `vs=`, not `vs_currencies=`). The tiers differ in: URL path/query, request-target builder, body parse, quote assembly (timestamp/source/stale mapping). Retry/hold-off/timeout/status-gate logic is identical.

**Recommendation — extract parsing into free functions and parameterize the client minimally:**
- New header `PriceEnvelopeParse.hpp` (or fold into a `PriceResponseParsers.hpp`): `ParseCoinGeckoSimplePrice(body, ids, currency, fetchTime) → PriceResult<vector<PriceQuote>>` and `ParseGnusPriceEnvelope(body, ids, currency) → PriceResult<vector<PriceQuote>>`. `PriceHttpClient.cpp`'s parse branch calls the first (behavior-identical refactor); the token.gnus.ai adapter (or a `ResponseFormat` constructor parameter on `PriceHttpClient` — see below) calls the second.
- Envelope→quote mapping rules (from Phase 1 D-06/D-06a/D-11 + envelope.ts):
  - `quote.asset` = each key of `prices`; `quote.price` = value; `quote.currency` = envelope `currency`.
  - `quote.timestamp` = `sys_time<std::chrono::seconds>{ fetchedAt }` — **envelope `fetchedAt` is epoch SECONDS** (envelope.ts:29 comment, "Landmine 10") and is the **max across returned ids**, not per-id — all quotes from one envelope share it (PITFALLS #15: fix units in the type system; never bare int64 across APIs).
  - `quote.source`: envelope `"coingecko"` → `PriceSource::CoinGecko`; `"coingecko-cache"` → `PriceSource::GnusPriceService` (Phase 1 D-06's explicit C++ mapping). **Counterintuitive but contractual**: a token.gnus.ai-tier *response* can carry `source=CoinGecko` quotes — the envelope's source describes the upstream that produced the price, not which client tier served it. The plan must state this so a reviewer doesn't "fix" it.
  - `quote.stale` = envelope `stale` verbatim.
  - Absent ids (requested but not in `prices`) are not errors (D-09) — same partial-coverage rule the facade already applies.
- Two wiring options for the token.gnus.ai tier: (i) a `ResponseFormat { CoinGeckoSimplePrice, GnusEnvelope }` constructor parameter on `PriceHttpClient` switching target-builder + parse call (one class, two instances — closest to 03-CONTEXT's "second instance with a different base URL"); (ii) a separate thin `GnusPriceServiceClient` reusing the transport+retry skeleton. **Prefer (i)** — the retry/hold-off/status-gate machinery is the valuable part and shouldn't be duplicated; note the target builder differs (`/api/v3/simple/price?ids=…&vs_currencies=…` vs `/v1/prices?ids=…&vs=…`, `PriceHttpClient.cpp:93-94`).
- **D-16 fixtures without sockets**: since `PriceHttpClient` has no transport seam, the byte-real envelope JSON drives the *parse function* directly (unit tests over `ParseGnusPriceEnvelope` with literal JSON copied verbatim from Phase 1 artifacts). Fixture sources on disk today: the design reference `.planning/research/pricing_coordinator.md` (normative JSON examples), `pricecoordinator/test/envelope.freshness.test.ts` (`expect(env).toEqual({ currency:"usd", prices:{bitcoin:61234.12}, fetchedAt:…, age:17, source:"coingecko", stale:false })`), and `coordinator.upstream-failure.test.ts` (stale-serve envelopes with `source:"coingecko-cache"`, `stale:true`). Embed as `const char*` literals in the C++ test (the `kGoodBody`/`kCloudFront403` pattern, `price_facade_test.cpp:20-24`) with a comment citing the source file. Optionally add a hermetic guard: the manager test suite contains no `http://`/`https://` string outside comments (the 02-VERIFICATION hermeticity grep precedent).

---

## 4. D-14 fold-in — precise edit points (Phase 2 gap #3)

**The problem (02-VERIFICATION gap #3, verified on disk today):** the facade maps *every* transport failure to `{PriceFetchError::NetworkError, 0}` before `ShouldRetry` (`PriceHttpClient.cpp:115-117`), and `IsTransient` returns true for any `{NetworkError, 0}` (`PriceRetryPolicy.cpp:35-38`) — so `TLS_HANDSHAKE_FAILED`, `TLS_CA_LOAD_FAILED`, `WRITE_FAILED`, `READ_INTERRUPTED` are all retried (bounded 3, real backoff). The strict classifier `IsTransientTransport` exists (`PriceRetryPolicy.cpp:10-27`, true only for `TIMEOUT`/`CONNECT_FAILED`/`RESOLVE_FAILED`) but is used only for the log label (`PriceHttpClient.cpp:118-123`), never the retry decision.

**Edit points (three files, all SuperGenius — no AsyncIOManager changes this phase):**

1. **`PriceFetchError.hpp:39-42`** — extend `PriceFetchFailure` with the transport classification. Two shapes:
   - **(a) carry the enum**: `std::optional<http::ClientError> transportError;` — requires `#include <HTTPTypes.hpp>` in this header. Precedent: `PriceRetryPolicy.hpp:3` already includes `<HTTPTypes.hpp>`; consumers of these headers already add `${AsyncIOManager_INCLUDE_DIR}` (`price_facade/CMakeLists.txt:5`). The new manager test must do the same.
   - **(b) avoid the include**: a plain `int transportErrorValue = 0;` (raw enum value, 0 = none/classified) — `PriceRetryPolicy.cpp` (which sees `HTTPTypes.hpp` via its own header) casts. Sidesteps header propagation entirely.
   Aggregate-init backward compatibility: existing `{ code, status }` braced initializers keep compiling (new member defaulted) — **but see the test-breakage note below**.
2. **`PriceRetryPolicy.cpp:29-38` (`IsTransient`)** — gate on the classification:
   ```cpp
   bool IsTransient( const PriceFetchFailure &error )
   {
       if ( error.httpStatus != 0 ) return false;               // unchanged (D-11)
       if ( error.code != PriceFetchError::NetworkError ) return false;
       return error.transportError && IsTransientTransport( *error.transportError );  // strict D-14
   }
   ```
   **Strictness decision for the planner:** an *unclassified* `{NetworkError, 0}` (no transport info) — transient (legacy behavior) or permanent (strict)? Strict is the honest reading of D-11/D-14 ("TLS-handshake/CA-load/write failures stop being blindly retried") and every facade path will populate the field; recommend strict, and note it flips two Phase 2 test fixtures (below).
3. **`PriceHttpClient.cpp:113-127` (transport-failure branch of the retry loop)** — populate the field and reuse the already-computed classifier:
   ```cpp
   const auto transportError = static_cast<http::ClientError>( result.error().value() );
   lastFailure = PriceFetchFailure{ PriceFetchError::NetworkError, 0, transportError }; // shape (a)
   ```
   The log label at `:118-123` can then read `IsTransientTransport(transportError)` directly. `ShouldRetry(lastFailure, …)` at `:125` needs **no change** — gating now happens inside `IsTransient`. `ShouldRetry` itself (`PriceRetryPolicy.cpp:40-50`) is unchanged. `IsTransientTransport` (`:10-27`) is already correct.

**Test impact — must be planned, not discovered:**
- `price_facade_test.cpp:177-197` (`IsTransientTruthTable`): the three `{ {E::NetworkError, 0}, true }` rows become false under strict classification → update fixtures to carry `TIMEOUT`/`CONNECT_FAILED`/`RESOLVE_FAILED` and add false rows for `TLS_HANDSHAKE_FAILED`/`TLS_CA_LOAD_FAILED`/`WRITE_FAILED`/`READ_INTERRUPTED`.
- `price_facade_test.cpp:199-206` (`ShouldRetryCapsAtThreeForTransient`): its `transient{NetworkError, 0}` fixture → GiveUp at every attempt under strict rules → fix by carrying `TIMEOUT`.
- Behavioral tests are unaffected: `TimeoutRetriesToCapThree` drives a real 300ms read-timeout → transport classifies `TIMEOUT` → still transient → still 3 attempts. `Blocked403…`/`RateLimited429…` paths don't touch transport classification.
- New TEST-02 assertions this unlocks: policy-level cases proving `TLS_CA_LOAD_FAILED` → `GiveUp` at attempt 1; manager-level: a fake tier-1 returning `{Blocked, 403}` → tier-1 called exactly once, tier-2 immediately invoked with the full miss-set (the manager-visible encoding of "403/429 never retried against CoinGecko").
- Hermetic facade-level wiring test for a CA-load failure is awkward today (the facade hard-pins `SGNS_DEFAULT_CACERT_PATH`, `PriceHttpClient.cpp:110-113`); forcing `TLS_CA_LOAD_FAILED` hermetically would need a caCertFile constructor override. Policy-level coverage satisfies TEST-02's letter; note the optional param as a planner choice (tiny additive constructor arg, default = pinned path).

---

## 5. Test determinism inventory (TEST-02)

| Technique | Where established (Phase 2 precedent) | Phase 3 use |
|---|---|---|
| Injectable `system_clock` function (`RateLimitHoldOff::Clock`, `std::function<time_point()>`) | `PriceRetryPolicy.hpp:80-115`; driven in `RateLimitHoldOffWithInjectableClock` (`price_facade_test.cpp:217-233`) | Manager constructor takes the same `Clock` type → L1 band decisions (fresh hit / 60s expiry / stale-band LKG / >5min unavailable) and boundary cases at exactly 60s/300s (closed-on-fresh, D-16) |
| Fixed epoch base, no `system_clock::now()` in tests | `price_quote_test.cpp:16-18` (`kEpochBase`) | All band tests build timestamps arithmetically off a fixed base |
| Injectable durations (zero-backoff `RetryConfig`) | `ZeroBackoffConfig`, `price_facade_test.cpp:12-18` | `coalescingWindow` ctor param: `0ms` default regime for most tests; **large window** (e.g. 1000ms) for the LPM-02 dedupe tests where the assertion is fake `callCount == 1` + union-of-ids + per-waiter subsets |
| Call-count assertions over real (generous-margin) timers | Phase 1 `coordinator.coalescing.test.ts:49-67` (MSW call count over real 15ms windows — "assert on cause, not wall time", PITFALLS #19) | The C++ equivalent: long window, N concurrent `GetQuotes` from N `std::thread`s, one fake call |
| Literal fixture strings | `kGoodBody`/`kCloudFront403`, `price_facade_test.cpp:20-24` | D-16 envelope fixtures: byte-real JSON copied from Phase 1 test expectations/design reference, source cited in a comment |
| House test rule (AgentDocs/CLAUDE.md §6/§7) | wait-condition templates; **never `sleep_for` in tests** | Manager tests never sleep — window=0 or long-window+join-the-threads; every waiter's future is the synchronization primitive |
| Hermeticity grep | 02-VERIFICATION: no `api.coingecko.com`, no `https://` in price suites | Manager suite: fakes only; no `HttpStubServer` link; no network strings |

**Suggested TEST-02 case matrix** (maps to ROADMAP Phase 3 criteria 1-4):

1. Fresh L1 hit: zero fake calls, `source == LocalCache`, `stale == false`, timestamp unchanged (LPM-01; Pitfall-12 lifetime check "second request within 60s performs zero client calls").
2. L1 expiry: clock advanced >60s → refetch (LPM-01); boundary: exactly 60s = still Fresh (D-16).
3. Partial L1 hit: only misses travel upstream (D-06) — assert the fake's received ids vector.
4. Coalescing: N requests within window → one call, union ids, per-waiter subsets (LPM-02).
5. Batching: multi-id request → single call with `ids={a,b,c}` (LPM-03 — assert the fake's captured ids).
6. New-misses-during-inflight queue (D-07): burst A (fake scripted slow/deferred), burst B arrives → second batch after first completes, no id fetched twice (assert per-call ids disjoint).
7. Tier-1 wholesale failure (403 / 429 / timeout) → tier-2 receives the full miss-set (LPM-04, D-09).
8. Tier-1 partial success → tier-2 receives only the gaps (D-09).
9. Both tiers fail + L1 has stale-band entry → served `source == LocalCache`, `stale == true`, **timestamp unchanged** (D-10/D-11, FRESH-02).
10. Both fail + entry >5min → not served; result is failure (FRESH-02 unavailable band; boundary: exactly 300s = StaleButUsable).
11. Held-off tier-1 (fake scripted `{RateLimitExceeded, 429}`) → chain proceeds to tier-2 immediately; tier-1 called once (D-12 documented at manager level; the real hold-off mechanics remain facade-tested, `HeldOffTierSkipsNetworkEntirely`).
12. Retry classification (D-14): policy truth-table incl. TLS classes never retried; manager-level 403 never re-queries tier-1.
13. Envelope fixtures (D-16): `ParseGnusPriceEnvelope` over byte-real Phase 1 JSON — fresh (`"coingecko"` → `PriceSource::CoinGecko`, `stale=false`), stale-serve (`"coingecko-cache"` → `GnusPriceService`, `stale=true`), `fetchedAt` seconds→timestamp conversion, partial `prices` (D-09).
14. Empty ids → `EmptyInput` (facade parity, `PriceHttpClient.cpp:49-52`).
15. Concurrency smoke: parallel `GetQuotes` across currencies → per-currency batches (D-08).
16. Construction/destruction loop: clean teardown, no hang with a blocked waiter (destructor resolves promises).

**Suite placement:** new `SuperGenius/test/src/price_manager/` sibling (the four existing price suites are one-concern-per-directory: `price_quote`, `price_http_client`, `price_facade`, `price_retrieval`). All 16 cases in one binary is fine (Phase 2's largest suite is 15 cases); split files only if the planner prefers (addtest supports multiple sources).

---

## 6. Build & registration wiring

### `SuperGenius/src/coinprices/CMakeLists.txt` (modify — `add_library` block, lines 1-6)

```cmake
add_library(coinprices
    coinprices.cpp
    PriceRetryPolicy.cpp
    PriceHttpClient.cpp
    LocalPriceManager.cpp        # NEW
)
```
Header-only additions (`IPriceSource.hpp`, parse-function header) need no listing. **No new link dependencies**: `Boost::headers` PUBLIC (strand/timer/promise all header-only; `boost::asio` needs no `Boost::system` link here — asio standalone header usage is already the pattern in `PriceHttpClient.hpp:9`), `AsyncIOManager` already PRIVATE, `rapidjson` already PRIVATE (envelope parsing uses it). Keep `SGNS_DEFAULT_CACERT_PATH` as-is.

### `SuperGenius/test/src/price_manager/` (new)

```cmake
addtest(price_manager_test
    price_manager_test.cpp          # (+ price_envelope_parse_test.cpp if split)
)

target_include_directories(price_manager_test PRIVATE ${AsyncIOManager_INCLUDE_DIR})  # if D-14 shape (a) reaches PriceFetchError.hpp
target_link_libraries(price_manager_test
    coinprices
    Boost::headers
)
```
- `addtest()` (`SuperGenius/cmake/functions.cmake:8-37`) supplies GTest mains, ctest registration, output dirs, `disable_clang_tidy`, the Windows Vulkan-DLL copy — nothing extra needed.
- Model on `price_facade/CMakeLists.txt` (which sets the AsyncIOManager include dir) rather than `price_quote` (minimal). Do **not** link `price_test_support` — zero sockets.
- Threads: `std::thread`/`std::promise` — on the GCC/Linux configs `Threads::Threads` is typically pulled transitively via GTest; Phase 2's `price_http_client_test` uses `std::thread` (stub server) with no explicit Threads link (`test/testutil/http_stub/CMakeLists.txt` links only `Boost::headers`) — follow that precedent; if an MSVC/Linux link error appears, `target_link_libraries(... Threads::Threads)` is the two-line fix.

### `SuperGenius/test/src/CMakeLists.txt` (modify — after line 22)

```cmake
add_subdirectory(price_facade)
add_subdirectory(price_manager)   # NEW
```

### Submodule commit discipline (memory: nested-submodule rule)

All Phase 3 changes are **SuperGenius-only** (`src/coinprices/` + `test/src/`) — no AsyncIOManager/thirdparty edits (D-14 touches SuperGenius files exclusively). Commits land on SuperGenius `dev_tokenprice`, then the root pointer bump at phase close. No pushes.

---

## 7. File-by-file change inventory (planning input)

| File | Action | Content |
|---|---|---|
| `src/coinprices/IPriceSource.hpp` | **new** | pure-virtual `FetchPrices(ids, currency)` (§3) |
| `src/coinprices/PriceResponseParsers.hpp/.cpp` *(name planner's choice)* | **new** | `ParseCoinGeckoSimplePrice` (moved from `PriceHttpClient.cpp:153-175`, behavior-identical) + `ParseGnusPriceEnvelope` (envelope contract, §3) |
| `src/coinprices/LocalPriceManager.hpp/.cpp` | **new** (D-15) | ioc+work+strand+thread, `GetQuotes` blocking bridge, L1, per-currency windows, inline chain walk, injectable window+clock (§1/§2) |
| `src/coinprices/PriceHttpClient.hpp/.cpp` | **modify** (D-14; maybe envelope tier) | retry-loop transport classification (§4); optionally `ResponseFormat` param + target-builder split for the token.gnus.ai tier (§3) |
| `src/coinprices/PriceFetchError.hpp` | **modify** (D-14) | `PriceFetchFailure` transport-classification field (§4) |
| `src/coinprices/PriceRetryPolicy.hpp/.cpp` | **modify** (D-14) | `IsTransient` strict gating (§4) |
| `src/coinprices/CMakeLists.txt` | **modify** | + `LocalPriceManager.cpp` (+ parser .cpp) (§6) |
| `test/src/price_manager/CMakeLists.txt` + `price_manager_test.cpp` (+ envelope parse test) | **new** | 16-case matrix, `FakePriceSource`, D-16 fixtures (§5) |
| `test/src/CMakeLists.txt` | **modify** | + `add_subdirectory(price_manager)` (§6) |
| `test/src/price_facade/price_facade_test.cpp` | **modify** (D-14 fallout) | truth-table + cap fixtures carry transport classification (§4) |
| `src/account/GeniusNode.cpp/.hpp`, `coinprices.cpp` legacy retriever | **do NOT touch** | Phase 4 owns the cutover (LPM-09/LPM-10); seam read only for shape fidelity (`GeniusNode.cpp:3510-3566`, `m_tokenPriceCache` at `GeniusNode.hpp:1487-1490` — note the seam's miss-collection loop at `:3510-3520` is the model for D-06) |

## 8. Risks & open points for the planner

1. **Blocking walk blocks the whole strand** (accepted per D-03/D-04 — §1). Document that cross-currency windows serialize behind an in-flight walk; worst-case waiter latency ≈ tier-1 (≤3×5s + 3s backoff) + tier-2 (same) ≈ ~36s theoretical, typically <1s. Whether the manager should tighten the retry budget when called through the chain (e.g., 1 attempt per tier) is an open point — the decisions don't mandate it; flag to planner as a tunable, default = inherit facade config.
2. **D-14 strictness flips two Phase 2 fixtures** (§4) — schedule the test updates in the same task as the code change or CI goes red mid-phase.
3. **Include propagation if D-14 shape (a)**: `PriceFetchError.hpp` gains `<HTTPTypes.hpp>`; every consumer needs `${AsyncIOManager_INCLUDE_DIR}` — today only the new suite is affected. Shape (b) (`int` field) avoids it entirely.
4. **`GetQuotes` must never be called from the manager's own thread** (future-wait self-deadlock — the `HostConnectedness` caveat). Doxygen-note the constraint; a debug assertion (`ioc_->get_executor().running_in_this_thread()`… actually strand context check: `strand_.running_in_this_thread()`) is a cheap guard worth adding.
5. **Destructor must resolve outstanding waiters** before joining, or blocked callers hang at shutdown (§1); a test for this (case 16) is cheap insurance.
6. **Envelope `fetchedAt` is max-of-ids, not per-id** — all quotes from one envelope share a timestamp; slightly conservative freshness. Acceptable (documented Phase 1 D-11); do not invent per-id timestamps.
7. **Source-mapping counterintuition** (§3): token.gnus.ai responses yield `PriceSource::CoinGecko` quotes when the envelope says `"coingecko"` — contractual per Phase 1 D-06; the *serving* tier is only distinguishable via the manager's logs. Plan should pin this in a comment and a fixture test.
8. **L1 store granularity**: per-(currency,id) keying is required (D-08); the stored entry keeps the fetch-time `source` for diagnostics while *serving* rewrites to `LocalCache` (LPM-01/D-11) — two representations, one entry; make the copy-on-serve explicit.
9. **No negative caching** (PITFALLS #14): failures never enter L1; next request re-attempts after a fresh window. Bounded by facade hold-off for 429. Note in plan so a reviewer doesn't add error-caching.
10. **Windows CRLF/format**: new files follow Phase 2 file style (Ullman braces, trailing-underscore privates + `m_logger`, Doxygen on public APIs — the `PriceHttpClient.hpp` house pattern).

---

*Research complete. Sources: all files cited read from the working tree 2026-10-01 (SuperGenius `dev_tokenprice`): coinprices module (6 files), price_facade/price_quote suites + CMake, testutil/http_stub, AsyncIOManager `HTTPClient.hpp/.cpp` + `HTTPTypes.hpp`, `ws_client_impl.hpp`, `GeniusNode.cpp/.hpp` seam, `pricecoordinator/src/{envelope,coordinator,index}.ts` + `test/{envelope.freshness,coordinator.coalescing}.test.ts`, workstream planning docs (03-CONTEXT/DISCUSSION-LOG, REQUIREMENTS, ROADMAP, STATE, 02-CONTEXT/VERIFICATION/PATTERNS, 01-CONTEXT, research/{ARCHITECTURE,PITFALLS}.md).*
