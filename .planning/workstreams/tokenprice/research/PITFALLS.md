# Pitfalls Research

**Domain:** Hybrid token-price system — TypeScript Cloudflare Worker (SQLite Durable Object + Cache API) and C++ Boost.Beast Local Price Manager added to the existing SuperGenius node
**Researched:** 2026-09-29
**Confidence:** HIGH — grounded in the 2026-09-29 live diagnosis (`/memories/repo/coingecko-price-api-frontend.md`), verified toolchain pins (`research/STACK.md`), and the actual source being replaced (`SuperGenius/src/coinprices/coinprices.cpp`, `SuperGenius/test/src/price_retrieval/price_retrieval_test.cpp`, `thirdparty/AsyncIOManager/src/HTTPCommon.cpp`)

These pitfalls are specific to **adding** this system to **this** codebase. Every item names the phase (P1–P5, per `ROADMAP.md`) where prevention belongs. Recurring grounding facts from the diagnosis:

- CoinGecko `/simple/price` returns **path-scoped 403** (CloudFront/AWS-WAF IP-reputation, UA-blind) while `/ping` and `/coins/list` return **200 from the same IP** — an IP can be half-blocked.
- After bursts, **429 persists for minutes**, and there are **no `x-ratelimit-*` / `Retry-After` headers anywhere** — callers fly blind.
- GitHub/Azure CI runner egress IPs are **near-permanently blocked** on `/simple/price`.
- Today's client swallows HTTP status (403 HTML → `JsonParseError 3` in logs), sends no User-Agent, and retries 3× at 250/500 ms — actively re-triggering the limiter.

---

## Critical Pitfalls

### A. Cloudflare Worker / Durable Object side (Phase 1)

### Pitfall 1: Single-flight map checked *after* the first `await` — double-fetch, or leaked waiters that hang forever

**What goes wrong:**
The `PriceCoordinator` DO deduplicates concurrent upstream CoinGecko fetches with an in-memory `Map<string, Promise>`. Two failure modes: (a) the map is populated *after* `await`ing anything (even `ctx.storage.get`), so two interleaved requests both see "no pending fetch" and both fetch — silently defeating coalescing, and success-criterion 2 ("exactly one mocked upstream call") passes in tests only because test concurrency happens to be sequential; (b) the pending entry isn't deleted in the rejection path, so every subsequent request awaits an already-rejected promise — permanent failure until the DO is evicted.

**Why it happens:**
Durable Object **input gates** block new events only while *storage* operations are outstanding — an outbound `fetch()` does **not** hold the input gate, so requests interleave across awaits. Developers assume DO requests serialize like transactions; they only serialize up to the first non-storage await.

**How to avoid:**
Set the pending-promise map entry **synchronously, before the first `await`**, and remove it in a `finally`. Better: eliminate request-time fetches entirely — use `ctx.storage.setAlarm()` to refresh every ~55 s so the DO *always* has data and request-time coalescing degenerates to a cache read (also fixes Pitfall 9's thundering herd). Assert upstream **call count** in tests with truly concurrent `Promise.all` requests, not sequential awaits.

**Warning signs:**
Tests where concurrent callers are fired sequentially; mock-upstream call count of 2 that "sometimes" appears; production `source: coingecko` bursts that dwarf the 60 s refresh cadence.

**Phase to address:** Phase 1 (plan 01-03 coalescing; hardened in 01-05 tests).

---

### Pitfall 2: DO eviction mid-flight — single-flight state is memory, and memory vanishes

**What goes wrong:**
Durable Objects can be evicted/restarted at any moment (and do, aggressively, on the Free plan when idle). In-flight `fetch()` completions are lost; requests routed to the evicted instance throw (`Durable Object reset` errors surface to the Worker). The in-memory pending map and any prices not yet flushed to `ctx.storage.sql` evaporate. Code that assumes the DO instance is a stable long-lived process (e.g., a `setInterval` refresh loop) simply stops.

**Why it happens:**
"State survives eviction" is true only for what went through `ctx.storage`. Developers treat the DO like a tiny always-on server.

**How to avoid:**
Persist every accepted price to `ctx.storage.sql` **before** responding to the client that requested it. Use `alarm()` (which wakes an evicted DO) instead of timers for the refresh loop. In the Worker's `fetch` handler, treat a thrown DO call as retryable-once (idempotent GET — safe). Test eviction explicitly by creating a new DO instance with the same `idFromName` and asserting prices survive (ROADMAP Phase 1 criterion 5 already demands this — keep it).

**Warning signs:**
Prices reverting to `fetchedAt` of hours ago after quiet periods; intermittent 500s that a manual refresh fixes; refresh that stops after a day until poked.

**Phase to address:** Phase 1 (plans 01-03/01-05).

---

### Pitfall 3: Migration tag mistakes — `new_classes` vs `new_sqlite_classes`, and editing an applied tag

**What goes wrong:**
Three variants: (a) `new_classes: ["PriceCoordinator"]` — KV-backed DO, **paid plan only**; everything works perfectly in local `wrangler dev`/vitest (miniflare doesn't enforce plan limits) and then deploy to the Free workers.dev account fails. (b) Editing the `v1` migration *after* it has ever been applied (to fix (a)) — wrangler refuses with an old/new-migration mismatch. (c) Appending a second class later without a fresh unique tag, or trying to switch a class between KV- and SQLite-backed without `transfer`.

**Why it happens:**
Migrations are append-only deployment history, but during development (where "deployment" is only ever local) they feel like ordinary config. The Free-plan SQLite requirement is invisible to every local tool.

**How to avoid:**
Start with `new_sqlite_classes` (STACK.md pins this). Treat the migration list as immutable once committed. Since deployment is out of scope for this milestone, add a **config-inspection test** that reads `wrangler.jsonc` and asserts: migrations use `new_sqlite_classes`, contain no `new_classes`, and no Queues/KV bindings exist — so the constraint is enforced in CI forever, not at some future deploy (ROADMAP plan 01-05 already includes this; don't cut it).

**Warning signs:**
Any `new_classes` string in the config; a migration edited in a PR review; "it deployed fine locally" as evidence.

**Phase to address:** Phase 1 (plans 01-01, 01-05).

---

### Pitfall 4: Cache API gotchas — silent no-store, per-colo semantics, and query-string cache-key fragmentation

**What goes wrong:**
- `cache.put()` **resolves successfully even when nothing is stored**: responses without a cacheable `Cache-Control` (needs explicit `max-age`/`s-maxage`; `no-store`/`private`/`Set-Cookie` responses are never stored). Every request sails through to the DO while the code believes it's caching.
- The cache key includes the **full URL**, so `ids=bitcoin,ethereum` and `ids=ethereum,bitcoin` are different entries — the L1 batching on the device side produces arbitrary id permutations, shredding the colo cache into near-zero hit rate.
- `caches.default` is **per-colo**: one-region tests show high hit rates; production warms hundreds of independent caches. Also, since each colo misses independently, the DO still absorbs global misses — cache ≠ substitute for DO-side data.

**Why it happens:**
The Cache API looks like a KV/map but is an HTTP cache with HTTP-cache rules. Per-colo behavior has no local analogue (miniflare has exactly one "colo").

**How to avoid:**
Build the cache key from a **canonical, sorted, deduplicated** `ids` list before both `cache.match` and `cache.put`. Set `Cache-Control: public, max-age=45` (sub-60 s per plan 01-04) on the response *and* assert in a test that a `cache.match` immediately after `cache.put` hits (that test fails the moment the header requirement is violated). Never put a `Set-Cookie`-bearing response (don't set cookies at all).

**Warning signs:**
DO request counts equal to Worker request counts in any dashboard; hit-rate tests that pass only with a fixed id order.

**Phase to address:** Phase 1 (plan 01-04).

---

### Pitfall 5: Worker tests that secretly egress — the suite inherits CoinGecko's CI-runner IP block

**What goes wrong:**
The vitest-plugin intercepts `fetch` only where mocks are declared. A test path that reaches `fetch()` without a matching mock performs a **real network call**. On a developer machine this may even return 200; on GitHub runners (`ubuntu-latest`) the egress IPs are near-permanently 403-blocked on `/simple/price` (diagnosis) — the suite becomes "green locally, red in CI" or flaky by IP reputation, reintroducing exactly the disease Phase 4/5 exist to cure, on the new codebase.

**Why it happens:**
Fetch mocking is opt-in per-request-pattern; the default failure mode is passthrough, not error.

**How to avoid:**
Configure the fetch mock to **fail closed**: unmatched outbound fetches must throw (fetchMock in "must-mock" style) or run a final `assertNoOutstandingRequests()` after the suite. Add one canary test asserting that a fetch to `api.coingecko.com` without a registered mock throws. Keep `npm test` meaningful in CI by never allowing silent passthrough (Phase 5 job depends on this property).

**Warning signs:**
Tests whose duration varies with network; a mock list that doesn't cover error paths; CI logs showing `403` from the worker test job.

**Phase to address:** Phase 1 (plan 01-05), enforced by Phase 5 (worker-tests job).

---

### Pitfall 6: Single global DO (`PriceCoordinator:USD`) is a pinned, serialized hotspot

**What goes wrong:**
`idFromName("USD")` creates exactly one DO instance, physically resident in **one colo** for its lifetime. Every cache-missing request worldwide routes to that datacenter and executes serially under DO input gates. Under the fallback-herd scenario (Pitfall 9) this is both a latency floor and a throughput ceiling — and every such request is also a DO request against the 100k/day Free limit, while cache hits are not.

**Why it happens:**
"Per-currency object" sounds sharded but is sharded across *currencies* (1), not load.

**How to avoid:**
Keep DO work per request tiny (storage read + envelope), put `caches.default` in front so steady-state misses are near-zero, and prefer alarm-driven refresh so requests never trigger upstream fetches inside the DO. If limits ever loom, shard by id-set hash — but only with evidence; don't pre-shard.

**Warning signs:**
p99 latency pinned to the DO's colo RTT; DO request count tracking Worker request count after cold start.

**Phase to address:** Phase 1 (design decision in 01-03; verified in 01-05).

---

### B. C++ Boost.Beast / Asio side (Phase 2)

### Pitfall 7: Async stream lifetime errors — handlers firing into freed objects

**What goes wrong:**
Beast's async ops (`async_connect`, `async_handshake`, `async_write`, `async_read`) capture the stream, buffer, request, and response by reference via the completion lambda's enclosing state. If any of those are locals of a function that returns while an op is pending (or the client object is destroyed from under a pending op — easy when the caller gives up via timeout), the handler invokes UB: crashes on some platforms, silent corruption on MSVC Release only. The existing `coinprices.cpp` dodges this only by blocking on `ioc->run()` per request with a fresh io_context.

**Why it happens:**
Beast tutorials show `std::shared_ptr` session chains precisely because raw ownership is wrong here; retrofitting blocking-style code (the current module's shape) into async Beast is where it bites.

**How to avoid:**
Make the HTTP client operation a self-owning `std::enable_shared_from_this` session object holding stream+buffer+request+response+deadline, destroying itself on completion/error. Cancel the deadline timer and close the socket in every error path (including timeout). One canonical session shape, reused for both CoinGecko and token.gnus.ai hosts.

**Warning signs:**
Random `EXCEPTION_ACCESS_VIOLATION` in `ssl::stream` teardown; crashes that appear only in Release or under load; "works with the stub, dies against the real server" (real network varies op interleavings).

**Phase to address:** Phase 2 (plan 02-02).

---

### Pitfall 8: Timeouts that don't cover the whole chain — resolver gaps, per-op budgets, and a 15 s worst case

**What goes wrong:**
`beast::tcp_stream::expires_after` covers stream ops, **not** `resolver::async_resolve` (a hung DNS lookup blocks indefinitely — common on flaky networks). Setting 5 s separately before connect, handshake, and read yields a 5+5+5 = 15 s worst case, blowing the fallback budget for a tier that's supposed to be a *quick* failure. Conversely inheriting today's AsyncIOManager numbers (10/10/30 s) makes the four-tier chain unbounded.

**Why it happens:**
Timeout APIs are per-operation; the fallback chain needs a *total* budget. The old code never had a caller-visible timeout at all, so there's no precedent in-tree.

**How to avoid:**
One **total deadline** (≈5 s per tier): resolve with its own timeout (or resolve once and cache the endpoint), then set `expires_after(remaining)` before each subsequent op, decrementing the remainder. Test the hang case in the stub suite by having the stub accept-then-stall (write headers, never finish body) and assert the client aborts at the budget.

**Warning signs:**
`GetProcessCost` calls occasionally taking 30+ s; tests that only cover "connection refused" (fast-fail) and never "connected but silent."

**Phase to address:** Phase 2 (plan 02-02; stub case in 02-03).

---

### Pitfall 9: TLS verification with vendored static OpenSSL — no default paths, **and** chain-verify without hostname-verify is theater

**What goes wrong:**
- `ssl::context::set_default_verify_paths()` finds nothing on Windows/Android/iOS with the vendored static OpenSSL (no populated `OPENSSLDIR`), so `verify_peer` fails every handshake with "unable to get local issuer certificate" — and the historically tempting "fix" is turning verification off, which is exactly the pre-existing hole (`HTTPDevice::SetVerifyPeer` is a dead toggle; today **no cert is actually verified** anywhere in AsyncIOManager).
- Worse: `ssl::verify_peer` alone only checks the chain against CAs. **Asio's SSL stream does not check the hostname** unless `SSL_set1_host` (or `X509_VERIFY_PARAM_set1_host`) is also set — without it, any CA-valid cert for *any* domain is accepted.
- Missing SNI (`SSL_set_tlsext_host_name` before handshake): CloudFront (CoinGecko) and Cloudflare (token.gnus.ai) are both name-based — you get the wrong/default certificate and fail, or in some configs a generic cert that *happens* to chain.

**Why it happens:**
Each piece (CA load, verify mode, hostname, SNI) is a separate OpenSSL/Asio call; samples online routinely show one or two of the four.

**How to avoid:**
The new client does all four, always: load the **pinned in-repo `cacert.pem`** (uniform across all five platforms per STACK.md — never probe OS stores), `set_verify_mode(ssl::verify_peer)`, `SSL_set1_host(host)` + `SSL_set_tlsext_host_name(host, sctx)`. Add an explicit negative test: stub-server cert (self-signed) must be rejected. Decide the runtime **location** of `cacert.pem` now — it's a data asset that must ship in the bundle on Windows/Linux/macOS/iOS/Android and be found from the test binary's CWD; a CMake copy/install step is part of the feature, not an afterthought.

**Warning signs:**
Handshake error 20/21 on Windows but not Linux CI; a config flag to disable verification; `grep SSL_set1_host` returning nothing.

**Phase to address:** Phase 2 (plan 02-02).

---

### Pitfall 10: Feeding non-JSON bodies to rapidjson — the 403-HTML → `JsonParseError 3` trap, plus compression and chunking

**What goes wrong:**
The current failure mode, verbatim: CloudFront's 403 is an HTML page; `FileManager::LoadASync` returns the body regardless of status; rapidjson produces `kParseErrorValueInvalid` (code 3); logs say "JSON Parse Error: 3" and **never say 403**. Nobody diagnosing from logs can tell a block from a parser bug. Two siblings: (a) Beast does **not** decompress — if the request sends `Accept-Encoding: gzip`, CloudFront may answer compressed and the parser sees binary garbage; (b) porting the existing hand-rolled `decodeChunkedTransfer()` into the new client — Beast already dechunks `Transfer-Encoding: chunked`, so double-decoding corrupts bodies.

**Why it happens:**
The old transport hid status and headers, so the parser became the de-facto error detector. "It parsed fine in the stub" because stubs return clean JSON.

**How to avoid:**
Hard rule: **check status first, Content-Type second, body shape third** — a non-2xx never reaches rapidjson; a body starting with `<` is classified `Blocked/RateLimited/Server` by status, not parsed. Never send `Accept-Encoding` (identity default → no compression); treat any unexpected `Content-Encoding` on a response as a transport error. Delete `decodeChunkedTransfer` with the old retriever — Beast owns dechunking.

**Warning signs:**
Any `document.Parse` reachable from a non-200 path; log lines mentioning parse errors without the HTTP status adjacent; `Accept-Encoding` in the request builder.

**Phase to address:** Phase 2 (plans 02-02/02-03 — the 403-HTML fixture is already a Phase 2 success criterion).

---

### Pitfall 11: Blocking a Boost.Asio thread — sleep-retries, the 50 ms coalescing window, and the nested-`run()` self-deadlock

**What goes wrong:**
Three ways to freeze the node: (a) the current code's `std::this_thread::sleep_for(250ms×3)` retry — if this ran on a shared Asio thread it would stall every other handler; the new coalescing window (~50 ms) is an even bigger temptation to "just sleep." (b) Implementing the manager on the node's **shared io_context** (AsyncIOManager's, which services MNN/IPFS/SFTP loads) — price I/O now competes with and can stall unrelated subsystems. (c) The sneakiest: the call path `GetProcessCost → GetGNUSPrice → GetCoinprice` is **synchronous**; bridging async Beast to it with `ioc.run()` on the calling thread deadlocks **if the caller is itself a handler on that io_context** (the completion can't run until the outer handler returns). The old code accidentally avoided this by creating a fresh io_context per request — expensive, but deadlock-free. Naively "optimizing" to one shared io_context + blocking wait reintroduces the deadlock.

**Why it happens:**
The seam is synchronous; the transport is async; something must bridge, and the bridge is where every Asio anti-pattern lives.

**How to avoid:**
Give the price manager its **own dedicated io_context + one thread**; expose the synchronous API via `std::future`/promise (wait with the total-deadline timeout); implement the coalescing window and all backoff with `steady_timer` async waits on that context — never `sleep_for` in production paths. The shared AsyncIOManager io_context stays untouched (STACK.md already scopes this: client is coinprices-local).

**Warning signs:**
`sleep_for` anywhere in the new module; `run()`/`run_one()` on an io_context the caller doesn't exclusively own; node-wide stalls correlated with price fetches.

**Phase to address:** Phase 2 (client shape, plan 02-02) and Phase 3 (window mechanics, plan 03-02).

---

### Pitfall 12: Per-call construction cost and the dead L1 cache — the cutover trap

**What goes wrong:**
`GeniusNode::GetCoinprice` (`GeniusNode.cpp:3510`) constructs `CoinGeckoPriceRetriever` **on the stack per call**. If the Phase 4 cutover copies that shape, every `GetProcessCost` builds a new manager: a new ssl_context (re-reading the ~250 KB CA bundle!), empty L1 cache, no last-known-good — the cache and LKG tiers become dead code and every call pays full TLS setup. Symmetric trap: making the manager a lazy singleton with threads/io_context invites the **static destruction order fiasco** (threads destroyed after the io_context they run on, at exit).

**Why it happens:**
The old retriever was stateless-per-call by design; the new one is stateful, and the seam doesn't change shape to signal that.

**How to avoid:**
Manager is a long-lived member (of `GeniusNode`/component factory) constructed once and injected; ssl_context built once and shared (thread-safe for handshakes after setup); explicit teardown before the io_context dies. A Phase 3 unit test should assert "second request within 60 s performs zero client calls" against the *injected fake* — which fails immediately if lifetime is wrong.

**Warning signs:**
`PriceManager` appearing as a stack local anywhere; CA-bundle read count > 1 per process in logs; L1 hit rate of 0 in production metrics.

**Phase to address:** Phase 3 (lifetime semantics) and Phase 4 (cutover, plan 04-01).

---

### C. Fallback-chain pitfalls (Phases 2–4)

### Pitfall 13: Retry storms re-triggering the minutes-scale limiter — client AND worker amplification

**What goes wrong:**
The diagnosis is explicit: 429 cooldown is **minutes-scale with no headers**, and today's 250/500 ms retries actively deepen the block. New variants: (a) treating 429 as "transient" in the new retry policy and retrying at 1 s — same disease; (b) **fallback-tier amplification** — when CoinGecko blocks a population of nodes, they all fall to token.gnus.ai; if the Worker then upstream-fetches per request, one CoinGecko 429 event turns N client calls into N upstream calls from a single egress IP, guaranteeing the Worker gets itself blocked (Cloudflare egress IP reputation with CoinGecko is not a free pass); (c) after the Worker itself is limited, its 429 propagates back down to thousands of nodes that all retry in lockstep.

**Why it happens:**
Each tier's retry policy looks locally reasonable; the limiter is global and header-less, so no tier can see the shared budget.

**How to avoid:**
Client: **never** re-request CoinGecko within a self-imposed hold-off (≥60 s) after a 429/403 — the hold-off is mandatory because `Retry-After` will never arrive; 403 = immediate permanent-tier-fallthrough (IP reputation won't unblock in seconds). Worker: alarm-driven refresh (Pitfall 1) means zero request-time upstream fetches, structurally eliminating amplification; otherwise the DO must hold-off after an upstream 429 and serve stale during it. Propagate a `retry-after`-style hint in the *envelope* (`nextFetchAfter`) since upstreams won't send headers — our two halves can cooperate even when CoinGecko won't.

**Warning signs:**
Any retry whose backoff is < 60 s on a 429; Worker upstream call count ≈ Worker request count; correlated failure spikes across nodes.

**Phase to address:** Phase 2 (retry classification, plan 02-04), Phase 1 (DO hold-off), Phase 3 (chain wiring, plan 03-03).

---

### Pitfall 14: Cached-error poisoning — a block that outlives the block

**What goes wrong:**
A 403/429 envelope (or a zero/absent price) gets stored like a good result: into `caches.default` with a 45 s TTL, into the DO's SQL table as "current," or into the C++ L1 as fresh — now every client is "blocked" for the cache duration even though the limiter may have lifted, and the DO may serve the error envelope as stale-but-usable for minutes. Subtle variant: **partial-response poisoning** — CoinGecko's `/simple/price` silently *omits* unknown/delisted ids and returns 200 with the subset found; caching that subset as "complete for the requested set" makes the missing id look un-fetchable for a minute.

**Why it happens:**
Read-through caching code paths store whatever came back; the distinction "response about prices" vs "response about the request failing" has to be deliberate.

**How to avoid:**
Only 200-with-expected-shape enters any cache; error statuses either aren't cached at all or get a short explicit negative-TTL (seconds) with a distinct marker. Track per-id presence: cache the *ids actually returned*; a request for an omitted id is a miss, not a hit. Unit tests for each tier: "429 then upstream recovers" must recover at the negative-TTL boundary, not at the good-TTL boundary.

**Warning signs:**
Error statuses appearing in cache-hit logs; `source: coingecko-cache` envelopes whose `prices` are empty; bug reports of "stuck blocked" that fix themselves after exactly the cache TTL.

**Phase to address:** Phase 1 (worker caches, 01-03/01-04) and Phase 3 (L1, plan 03-01/03-03).

---

### Pitfall 15: Clock skew and unit confusion in freshness bands — everything stale, or nothing ever stale

**What goes wrong:**
The envelope carries `fetchedAt` (server clock) and `age`; the client computes freshness 0–60 s / 60–300 s / >300 s. Failure modes: (a) comparing server `fetchedAt` to local wall clock on a skewed device/VM (embedded boards are routinely minutes off; NTP-less even more) → all fresh data classified stale → constant refetch → self-inflicted rate limiting; or the inverse; (b) **seconds vs milliseconds**: the envelope spec says seconds (`1790719234`), while the existing repo code is already hedging with `timestamp > 9999999999` heuristics in `coinprices.cpp` — one side emitting ms makes every quote look 55,000 years old or brand-new depending on direction; (c) trusting server-computed `age` blindly and passing it through as if measured now.

**Why it happens:**
Two clocks, two units, three tiers, no single definition of "when was this measured, by whose clock."

**How to avoid:**
Client-side aging uses a **monotonic clock anchored at receipt** (`steady_clock` at envelope-arrival) for all band decisions; `fetchedAt` is metadata for logs/UI only. Fix units in the type system (`std::chrono::seconds` end-to-end; never bare `int64_t` across an API). Never compute bands from wall-clock deltas. Unit tests pin the bands with injected clocks (Phase 2 classifier tests, plan 02-01).

**Warning signs:**
`int64_t` timestamps crossing function boundaries; any `system_clock::now() - fetchedAt` expression; skew appearing only on certain devices.

**Phase to address:** Phase 2 (classifier, plan 02-01) and Phase 3 (band decisions, plan 03-03).

---

### Pitfall 16: Last-known-good served as fresh — the `outcome::result<double>` seam erases the stale flag

**What goes wrong:**
The design's whole point is honest staleness (`stale: true`), but `GetGNUSPrice` must keep returning `outcome::result<double>` (Phase 4 criterion: seam unchanged). Once a stale LKG price flows into that `double`, **nothing downstream can tell** — `GetProcessCost` prices a job with a 4:59-old quote as if live, and if CoinGecko stays blocked for hours, LKG quietly degrades from "minutes old" to "hours old" while the system behaves normally. Related: LKG accepting garbage on a malformed-but-200 response (a 0 or absurd value) and then serving it forever; LKG lost entirely on node restart (in-memory only → first-boot after outage = hard failure).

**Why it happens:**
The seam's type is a scalar; the honesty lives in the metadata the seam can't carry. Preserving the seam (correctly, for compatibility) collides with propagating the honesty.

**How to avoid:**
Keep the existing finite/positive validation at the seam **and add a sanity band** (e.g., reject quotes > 100× or < 0.01× LKG without an explicit override) before LKG admission. Cap LKG service by absolute age (the >5 min band means *error*, not LKG-forever — decide explicitly whether LKG has a hard expiry, e.g., 1 h, then fail). Log `source` + `age` on **every** seam call so staleness is at least observable. If policy ever needs staleness downstream, that's a deliberate seam change, not this milestone.

**Warning signs:**
`GetProcessCost` outputs that track a price frozen at an outage timestamp; no log line containing the price source; LKG entries with no age field.

**Phase to address:** Phase 3 (LKG policy, plan 03-03) and Phase 4 (seam logging/validation, plan 04-01).

---

### D. Testing pitfalls (Phases 2–5)

### Pitfall 17: Tests that secretly depend on the network — both existing suites, and the health-check delusion

**What goes wrong:**
`price_retrieval_test.GetCurrentPrice/GetHistoricalPrices` hit **live CoinGecko today**; from CI runners that's a guaranteed 403 (path-scoped IP block, per diagnosis) — the exact reason `account_management_test.SetPayoutAddress` is on the aarch64-Debug `GTEST_FILTER` exclusion list. If Phase 4 converts `SetPayoutAddress` but leaves *any* live-network case anywhere, the exclusion can't actually be removed (Phase 5 criterion 2 fails) and the disease persists under a new name. Subtler: even "hermetic" tests can DNS-resolve hostnames; and a health/status probe that pings CoinGecko's `/ping` to decide "is the tier up" is **worse than nothing** — `/ping` returns 200 while `/simple/price` 403s from the same IP (diagnosis), so the probe reports healthy exactly when the tier is blocked.

**Why it happens:**
The live tests were convenient originals; the path-scoped nature of the block makes casual probes actively misleading.

**How to avoid:**
Zero-tolerance rule for the converted suites: stub/fake only, `127.0.0.1` literals (not `localhost`, to skip resolver variance), OS-assigned ports. Health classification of CoinGecko comes from **`/simple/price` behavior itself** (a real request's status), never from a different endpoint. Phase 5's worker job stays hermetic per Pitfall 5.

**Warning signs:**
Any `api.coingecko.com` literal in test sources; a `IsCoinGeckoUp()` helper; CI failures that "can't reproduce locally."

**Phase to address:** Phase 4 (plans 04-02/04-03), enforced by Phase 5.

---

### Pitfall 18: Stubs that are nicer than the real thing — headers that don't exist, bodies that are never chunked, and the handshakes that never stall

**What goes wrong:**
Real-world responses that stubs omit: (a) a stub that returns `Retry-After: 5` on 429 **trains the code to rely on a header CoinGecko never sends** (diagnosis) — production then reads `nullptr`/absent and either crashes, hangs, or falls back to a default that contradicts the tested behavior; (b) stubs always send `Content-Length` JSON — never chunked, never gzipped, never an HTML error page — so transport handling written against the stub (see Pitfall 10) is untested against reality; (c) stubs fail fast (refused connection); real servers accept, send headers, then stall — timeout code paths (Pitfall 8) never execute; (d) stubs don't reset mid-body.

**Why it happens:**
Stubs are written from the API docs (happy path) rather than from observed failures — this repo is unusual in having a diagnosis file with the *actual* 403 HTML and header-less 429 to build fixtures from.

**How to avoid:**
Make the stub scriptable per-request for: status-only responses, headerless 429, **the CloudFront 403 HTML fixture**, chunked encoding, truncated bodies, and accept-then-stall. Add an explicit test that the client behaves identically with and without `Retry-After` (it must ignore it — budget is self-imposed per Pitfall 13). Where possible, replay the exact bytes captured in the diagnosis.

**Warning signs:**
`Retry-After` or `x-ratelimit` strings in production parsing code; a stub whose every response has `Content-Length`; no stall-mode in the stub API.

**Phase to address:** Phase 2 (stub server, plan 02-03) — the fixture set is the prevention.

---

### Pitfall 19: Flaky coalescing tests — real timers, tight assertions, and slow CI runners

**What goes wrong:**
"N requests within ~50 ms collapse into one upstream call" tested with real sleeps and wall-clock asserts: passes on a dev box, flakes on shared/aarch64-emulated/Windows runners where scheduling jitter pushes arrivals past the window. On the Worker side, per-test-file storage isolation regenerates DO state (STACK.md), so a coalescing test that depends on a warm DO from another file fails mysteriously; `wrangler dev` state persisted under `.wrangler/state` across runs makes the *same* test pass/fail depending on leftovers ("haunted" cache). Also: leftover `.wrangler/state` can mask a broken `cache.put` (Pitfall 4) because a previous run cached the response.

**Why it happens:**
Coalescing is inherently timing-based, and CI timing is the one variable you don't control.

**How to avoid:**
Assert on **cause, not wall time**: upstream mock *call counts* with requests fired concurrently (Worker, per STACK.md), and on the C++ side inject the window/clock so the test sequences arrivals deterministically instead of sleeping. Give the coalescing assertion tolerance (arrivals "within the window" is the code's job to decide — tests decide the *order*, not the milliseconds). Isolate state: unique cache keys/DO names per test, clean `.wrangler/state` in the npm test script, never rely on cross-file state.

**Warning signs:**
`sleep(50)` in test code; assertions like `elapsed < 60`; tests that pass on retry; CI flakes that never reproduce under `--repeat`.

**Phase to address:** Phase 1 (plan 01-05) and Phase 3 (plan 03-04).

---

### E. CoinGecko-specific traps (Phases 1–4)

### Pitfall 20: Designing around documented rate limits that contradict each other — and headers that never come

**What goes wrong:**
The design reference records the inconsistency: Demo is "100 calls/min, 10k/month" on the pricing page, ~30/min in support docs, 5–15/min keyless. Code calibrated to any of these numbers is wrong; code that *waits for* `x-ratelimit-remaining`/`Retry-After` to know the budget **waits forever** — they are empirically absent (diagnosis). This is the trap that produced the current hostile retry loop.

**Why it happens:**
Normal API hygiene (read the docs, honor the headers) actively misleads here; the docs disagree and the headers lie by omission.

**How to avoid:**
Self-imposed conservative budget on both tiers (client and Worker), sized below the *worst-case* documented number (keyless ≈ 5–15/min ⇒ poll ≈ every 60 s is safely inside), plus reactive hold-off ≥ 60 s on any 429. Never branch on rate-limit headers — absence is the norm; add a defensive parse *only* if a header appears, never a dependency. The Worker's key (server-side secret, never embedded in the C++ binary) moves it to the 30–100/min class when added — treat that as headroom, not a license.

**Warning signs:**
Any code reading `x-ratelimit-*`; constants like `30` justified by "the docs"; poll intervals < 60 s for a value that updates ~60 s anyway.

**Phase to address:** Phase 1 (worker budget), Phase 2 (retry classification, plan 02-04), Phase 3 (chain wiring).

---

### Pitfall 21: id-vs-symbol confusion and the silently-omitted id — `genius-ai`, not `GNUS`

**What goes wrong:**
`/simple/price?ids=` takes CoinGecko **ids** (`bitcoin`, `genius-ai`), not symbols (`BTC`, `GNUS`) — `/simple/symbol_price` is a different endpoint. Passing `gnus` or `GNUS` returns **200 with that id simply missing** (no error), which the current code surfaces as `NoDataFound` — indistinguishable from a block or an outage. And ids are not stable forever: CoinGecko delists/renames ids when coins re-list, silently turning a working integration into a 200-with-empty-subset at some future date. Mitigation: treat "requested id absent from a 200 response" as a first-class outcome (distinct from blocked/timeout — see Pitfall 14's partial-poisoning link), log it loudly, and have a config-level mapping (`GNUS → gnus-ai`) owned in one place.

**Phase to address:** Phase 2 (response classification, plan 02-02) and Phase 4 (the id mapping at the seam, plan 04-01).

**Why it happens:**
Every other exchange API in the ecosystem uses symbols; the distinction between the two CoinGecko endpoints is easy to miss, and the failure is silent.

---

### Pitfall 22: Assuming the fallback's egress is clean — Cloudflare worker IPs have reputation too

**What goes wrong:**
token.gnus.ai fetches CoinGecko from Cloudflare egress IPs — shared with every other Worker on the planet hammering free APIs. Those ranges already carry reputation baggage; a 429/403 regime against the Worker is *plausible at any time*, independent of our traffic. If the C++ chain treats "Worker returned 429/stale" as "Worker broken" and starts hammering CoinGecko direct again, the herd un-coalesces (Pitfall 13's loop). The chain must read the Worker's envelope honestly: `stale: true` + `source` + `age` mean "fallback is degraded but alive — keep using it."

**Why it happens:**
The Worker is *our* service; it feels like it should be reliable on our terms. Its upstream dependence is invisible in its uptime.

**How to avoid:**
Worker signals degradation in-band (stale envelope, `nextFetchAfter` hint) rather than only via errors (Pitfall 13); client distinguishes "fallback errored" from "fallback served stale." Monitor Worker upstream status in logs from day one.

**Warning signs:**
Client retry logic keyed on Worker 4xx/429 without reading the envelope body; no visibility into the Worker's own upstream success rate.

**Phase to address:** Phase 1 (envelope semantics) and Phase 3 (chain decisions, plan 03-03).

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Turning off TLS verify "to unblock Windows build" | Handshake passes today | Reintroduces the exact pre-existing hole (verify-peer is already dead in AsyncIOManager); MITM-able price feeds | Never — load the pinned bundle instead (Pitfall 9) |
| Skipping the config-inspection test for `wrangler.jsonc` | One less test | `new_classes` Free-plan failure surfaces only at first real deploy (Pitfall 3) | Never |
| Caching by raw query string (`ids=...` as-given) | Simpler cache key | Per-colo cache fragments to ~0% hits (Pitfall 4) | Never — canonicalize ids |
| Testing coalescing with real sleeps | Quick to write | Perma-flaky CI; engineers start ignoring the suite (Pitfall 19) | Never in CI; acceptable for a one-off manual probe |
| Keeping live-CoinGecko tests "just for manual runs" | Apparent extra coverage | Someone wires them into CI later; runner-IP 403 flakiness returns (Pitfall 17) | Only behind an explicit opt-in flag excluded from ctest by default |
| LKG with no absolute age cap | Never fails while degraded | Hours-old prices price jobs silently (Pitfall 16) | Only if a deliberate product decision is recorded |
| Passing timestamps as bare `int64_t` | Less typing | s-vs-ms bugs the repo already hedges around (Pitfall 15) | Never — `std::chrono` end-to-end |
| Hard-coding the `GNUS → gnus-ai` mapping at call sites | Cuts a config field | One delist/rename breaks every site; silent empty subsets (Pitfall 21) | Never — single config-owned mapping |
| Returning 403 bodies to the JSON parser "because shape is checked later" | Skips one if-statement | `JsonParseError 3` obscuring blocks again (Pitfall 10) | Never |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Cloudflare Cache API | `cache.put` without `Cache-Control`, expecting it to behave like KV; assuming global replication | Treat as per-colo HTTP cache: explicit `Cache-Control: public, max-age=45`, canonical sorted-id keys, assert round-trip hit in a test (Pitfall 4) |
| Durable Objects | Pending-fetch map set after first `await`; state kept only in memory; timers instead of alarms | Set single-flight entry synchronously pre-await; persist via `ctx.storage.sql` before responding; `alarm()` for refresh; handle eviction-retry (Pitfalls 1–2) |
| `wrangler.jsonc` migrations | `new_classes` on a Free plan; editing an applied tag | `new_sqlite_classes` from day one; append-only tags; config-inspection test (Pitfall 3) |
| CoinGecko `/simple/price` | Relying on rate-limit headers; probing health via `/ping`; treating omitted ids as errors | Self-imposed budget + reactive hold-off; health = real request status; absent-id is its own outcome (Pitfalls 17, 20, 21) |
| CoinGecko via CloudFront | Sending `Accept-Encoding` then parsing; expecting `Content-Length`; retrying 429 at sub-minute | Identity encoding; status-before-parse; 403/429 never re-hit within 60 s (Pitfalls 10, 13) |
| Beast + Asio in SuperGenius | Reusing the node's shared io_context; `ioc.run()` bridge on a caller that's already a handler; stack-local manager per `GetCoinprice` call | Dedicated io_context + thread, future-bridge, injected long-lived manager (Pitfalls 11–12) |
| Vendored static OpenSSL (5 platforms) | `set_default_verify_paths()` and moving on; `verify_peer` without hostname check; runtime-relative `cacert.pem` path | Pinned bundle loaded explicitly; `SSL_set1_host` + SNI always; asset shipped via CMake on every platform (Pitfall 9) |
| `GeniusNode::GetCoinprice` seam | Changing the return type to carry staleness; dropping the finite/positive check | Keep `outcome::result<double>`; log `source`+`age` at the seam; sanity-band LKG admission (Pitfall 16) |
| Worker ↔ C++ envelope contract | C++ trusting server `age`/`fetchedAt` with local wall clock; ms vs s drift | Client ages by monotonic clock from receipt; seconds pinned in types (Pitfall 15) |
| Env-var endpoint override for tests | Two test suites in one process setting different env vars | Env/config read once into injected config object; per-test instance injection, not process-global mutation (Phase 4) |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|-----------------|
| Fresh ssl_context (CA reload) per request | ~250 KB parse per price call; latency floor ms→tens of ms | Build ssl_context once, share across requests (Pitfall 12) | First real deployment with per-call construction |
| Stack-local manager per `GetCoinprice` call | L1 hit rate 0; every call = full HTTPS round trip | Long-lived injected manager; hit-rate assertion in tests (Pitfall 12) | Day one of Phase 4 if the cutover copies the old shape |
| Coalescing window implemented with sleeps on shared Asio threads | Node-wide latency spikes every price poll | `steady_timer` on a dedicated context (Pitfall 11) | Under load, or whenever price I/O shares a context with MNN/IPFS |
| Worker doing request-time upstream fetches in the DO | Upstream calls ≈ requests; herd amplification on CoinGecko blocks | Alarm-driven ~55 s refresh; requests read storage only (Pitfalls 1, 13) | First time many nodes fall back simultaneously |
| `PriceCoordinator:USD` serving all traffic from one colo | Global p99 pinned to one datacenter's RTT; DO request quota erosion | caches.default absorbs steady state; keep DO per-request work tiny (Pitfall 6) | Cross-region traffic growth |
| Cache fragmentation from unsorted id lists | Cache hit rate ~0 despite implementation "working" | Canonical sorted deduped key (Pitfall 4) | As soon as batching permutes id order |
| Nested `run()` deadlock when the sync seam is called from an Asio handler | Intermittent full stalls of the calling subsystem | Dedicated io_context + future bridge; never `run()` a context you don't own (Pitfall 11) | The first caller that's already on Asio |
| Self-inflicted rate limiting via skewed clocks | Constant refetch loops; 429 storms with no upstream change | Monotonic-clock aging; self-imposed budget independent of headers (Pitfalls 15, 20) | Devices with drifted clocks, NTP-less networks |

---

*Pitfalls research for: PriceCoordinator — Local Manager + token.gnus.ai Fallback (workstream: tokenprice)*
*Grounded in: `.planning/research/pricing_coordinator.md`, `research/STACK.md`, `/memories/repo/coingecko-price-api-frontend.md`, `SuperGenius/src/coinprices/coinprices.cpp`, `SuperGenius/test/src/price_retrieval/price_retrieval_test.cpp`, `ROADMAP.md` phases 1–5*
