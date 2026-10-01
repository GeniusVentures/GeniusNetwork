# Phase 4: GeniusNode Integration & Hermetic Tests - Context

**Gathered:** 2026-10-01
**Status:** Ready for planning

<domain>
## Phase Boundary

The integration phase — the Phase 3 `LocalPriceManager` replaces `CoinGeckoPriceRetriever` behind the existing `GeniusNode::GetCoinprice`/`GetGNUSPrice` seam with configurable endpoints (LPM-09/LPM-10), the legacy retriever is **deleted entirely**, and the two network-dependent test surfaces become hermetic: `account_management_test.SetPayoutAddress` runs against the local stub (TEST-04 clause 1 — the CI-exclusion-removal clause is Phase 5's), and `price_retrieval_test` is rewritten as a registered, stub-driven integration suite proving the full wiring — env-var redirect → manager → node seam → fallback tiers — with zero live CoinGecko (TEST-05).

Requirements in scope: LPM-09, LPM-10, TEST-04 (hermetic-conversion clause only), TEST-05.

**Not in this phase:** any CI workflow change (`SuperGenius/.github/workflows/cmake.yml` is Phase 5), live Worker deployment, wallet-side price paths.

</domain>

<decisions>
## Implementation Decisions

### Endpoint configuration (LPM-09)
- **D-01:** Endpoint base URLs are configured via **environment variables only** — no `GeniusNodeConfig` fields, no `sgns_config.json` keys. Precedent: the in-tree `SGNS_CONSOLE_LOG_TESTS` / `SGNS_DEBUGLOGS` env gates. `GeniusNodeConfig` stays untouched (it is a brace-initialized aggregate; appending fields would touch every construction site for no benefit).
- **D-02:** **Tier-specific names** (exact strings planner's discretion, `SGNS_COINGECKO_URL` / `SGNS_PRICE_FALLBACK_URL` expected): one var for the tier-1 CoinGecko base URL, one for the tier-2 token.gnus.ai base URL. A test can redirect each tier independently — distinct hosts or one host with distinct paths.
- **D-03:** Env is read **at manager construction**; tests set the env vars **before `GeniusNode::New()`** (Windows `SetEnvironmentVariable` / POSIX `setenv`), restoring in teardown. No post-construction setter method is added. Consequence: the `AccountManagement` fixture (which builds `node_` in its ctor) sets the env vars in its **fixture constructor before `GeniusNode::New`**, redirecting every node the suite constructs — that is desired; the whole suite becomes hermetic.
- **D-04:** **Scheme in the URL decides transport security.** A stub base URL (`http://127.0.0.1:PORT`) speaks plain HTTP via Phase 2's plain-HTTP support; TLS + pinned-CA verification applies only to production `https://` defaults. No test certificates, no TLS stub.

### Seam cutover mechanics (LPM-10)
- **D-05:** GeniusNode holds a **lazy `std::shared_ptr<LocalPriceManager>`** — constructed on the first price call (`GetCoinprice`), not in the node constructor. Node startup stays light: no runner thread until a price is actually needed; suites that never touch prices pay nothing. The manager's destructor (drain-then-join per Phase 3 D-02) handles teardown — planner places its release in `~GeniusNode`'s ordered teardown so the runner thread joins before the io/threads machinery it may reference goes away.
- **D-06:** **Delete the old state outright:** `m_tokenPriceCache`, `m_lastApiCall`, `MIN_API_CALL_INTERVAL`, the `PriceInfo` cache struct, and `GetCoinprice`'s miss-collection loop all disappear from `GeniusNode.hpp/.cpp`. The manager's L1 supersedes them. No dead members left behind.
- **D-07:** **Partial-map semantics preserved:** `GetCoinprice` returns the map of prices it has (fresh or fetched); an id the chain couldn't serve is simply **absent** from the map; failure is returned only when **nothing** is servable — exactly today's partial-data behavior (`GeniusNode.cpp:3548-3560`) and Phase 3's `GetQuotes` partial-success semantics. `GetGNUSPrice`'s existing finite/positive `genius-ai` check then yields `NO_PRICE` when absent — that validation is untouched (LPM-10's "same surface, unchanged validation").
- **D-08 (carried from Phase 3, binding here):** `GetQuotes` must never be called from the manager's own runner thread (future-wait self-deadlock). All node-side callers (`GetProcessCost` path, gRPC-free) are off-thread — safe by construction; the planner should note this constraint in the seam wiring.

### Retriever retirement
- **D-09 (user decision, overriding REQUIREMENTS wording):** `CoinGeckoPriceRetriever` is **deleted entirely** — the whole class, `getCurrentPrices`/`getCurrentPricesOnce`, the historical methods (`getHistoricalPrices`/`getHistoricalPriceRange`), `decodeChunkedTransfer`, `formatDate` — and with it the `GeniusNode::GetCoinPriceByDate`/`GetCoinPricesByDateRange` forwarding seams. Verified during discussion: **zero consumers** in `SuperGenius/src/api/`, `gRPCForSuperGenius/`, `SGProcessingManager/`, `GeniusSDK/`, or any other test — the only callers were `price_retrieval_test` itself. This supersedes REQUIREMENTS.md's Out-of-Scope entry "Historical price endpoints kept compiling behind the existing surface" (see Requirements Corrections below).

### Hermetic test shapes (TEST-04/TEST-05)
- **D-10:** `price_retrieval_test` is **rewritten as a stub-driven integration suite**: it drives the real wired path — `GeniusNode::GetCoinprice` (or the seam as wired) against `HttpStubServer` with env-var redirection — and gets **registered with CTest** (it is currently deliberately unregistered as a live smoke test). Historical-endpoint tests are deleted with the retriever (D-09).
- **D-11:** **One stub instance, both tiers:** both env vars point at the same `HttpStubServer`, distinguished by scripted paths — `/api/v3/simple/price` (CoinGecko shape, tier 1) and `/v1/prices` (Phase 1 envelope shape, tier 2). This proves tier-1-fails → tier-2-serves through the real node seam with one fixture. (Two stub instances: rejected as zero added coverage; CoinGecko-tier-only: rejected because tier 2 is undeployed (DEPLOY-01 deferred) so an unredirected fallback URL would just fail.)
- **D-12:** `account_management_test` sets the env vars in its **fixture constructor before any `GeniusNode::New`**, both tiers → the shared stub with a valid `genius-ai` price scripted. The 3-node topology, escrow flow, and all assertions stay untouched — only the price source changes; `GetProcessCost` computes deterministically against the scripted price.
- **D-13:** The rewritten integration suite includes a **warm-then-fail script**: the stub's first responses succeed (populating the manager's L1/LKG), then a scenario flips the stub to 403-HTML/429 — the fallback tier or stale-served LKG keeps `GetCoinprice` serving. This proves the milestone's Core Value (price-dependent paths never hard-fail when CoinGecko is WAF/limit-blocked) end-to-end through the node seam, beyond what `price_manager_test` already proves with fakes.

### Claude's Discretion
- Exact env-var names (D-02 fixes the tier-specific shape; strings follow the `SGNS_*` convention).
- Where/how the env read is implemented (free function in the coinprices module vs. inline in the lazy-ctor site) and whether unset-env falls back to constants shared with tests.
- The lazy-manager construction site's exact shape (member function `GetOrCreatePriceManager()` vs. inline `if (!priceManager_)` in `GetCoinprice`).
- Placement of the manager reset within `~GeniusNode`'s ordered teardown (constraint: runner thread joins before members it could reference are gone — follow `ReleaseRuntimeMembersAfterIoStopped`/destructor ordering conventions).
- How much of `coinprices.hpp/.cpp` remains after D-09 (module keeps only the Phase 2/3 files; the `CoinPrices` logger tag stays for the new components) — planner decides file disposition.
- The rewritten `price_retrieval_test`'s internal organization (which scenarios as separate TEST_Fs: happy/403-fallback/429-holdoff/LKG) and its CMake registration mechanics (`addtest` now that it's hermetic).
- Fixture env save/restore helpers (test-local RAII or gtest Environment) — must not leak redirecting env into other suites in the same ctest shard.
- Assertion style for fallback/LKG scenarios through the seam (price value equality vs. presence + sanity), consistent with the deterministic scripted prices.

### Requirements Corrections (planner must apply)
- **REQUIREMENTS.md Out-of-Scope "Historical price endpoints (`getHistoricalPrices`/`getHistoricalPriceRange`) redesign | Kept compiling behind the existing surface"** is **superseded by D-09**: the historical endpoints and their carriers are deleted this phase. Update REQUIREMENTS.md's Out-of-Scope table wording when Phase 4 lands (or note the supersession in the plan) so the docs match reality.
- Roadmap Phase 4 plan seed 04-01's "`CoinGeckoPriceRetriever` retired or reduced to what still compiles" resolves to **retired — deleted entirely** (D-09).
- TEST-04's "exclusion removed" clause remains Phase 5 scope (per Phase 1's cross-phase correction: the aarch64-Debug exclusion's real cause is MNN/Vulkan, so removal needs the thirdparty rider — re-scope when Phase 5 is planned). Phase 4 delivers only the hermetic-conversion clause.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### The seam being cut over (primary)
- `SuperGenius/src/account/GeniusNode.cpp:3510-3565` — `GetCoinprice` today: miss-collection loop, per-call retriever, partial-data error handling (D-07's model); also `GetCoinPriceByDate`/`GetCoinPricesByDateRange` forwarders (deleted per D-09)
- `SuperGenius/src/account/GeniusNode.cpp:2797-2845` — `GetProcessCost` → `GetGNUSPrice` call chain (the consumer whose compile-and-pass proves LPM-10) with the finite/positive validation that stays untouched
- `SuperGenius/src/account/GeniusNode.hpp:1487-1490` — `m_tokenPriceCache`/`m_lastApiCall`/`MIN_API_CALL_INTERVAL` (deleted per D-06)
- `SuperGenius/src/account/GeniusNode.hpp:79-88,150` — `GeniusNodeConfig` aggregate + `GeniusNode::New` (NOT modified per D-01)
- `SuperGenius/src/account/GeniusNode.cpp` (`~GeniusNode`/`ReleaseRuntimeMembersAfterIoStopped`/`ShutdownForDestruction`) — the ordered-teardown sequence D-05's manager release must slot into

### Phase 3 delivered code (what gets wired in)
- `SuperGenius/src/coinprices/LocalPriceManager.hpp/.cpp` — the manager: blocking `GetQuotes(ids, currency)`, lazy-constructible, own ioc + runner thread + drain-join destructor
- `SuperGenius/src/coinprices/IPriceSource.hpp` + `SuperGenius/src/coinprices/PriceHttpClientSource.hpp` — the tier seam and production adapter (constructor takes base URL — the env read feeds these, D-01/D-02)
- `SuperGenius/src/coinprices/PriceHttpClient.hpp` — `ResponseFormat` enum (`CoinGeckoSimplePrice` vs envelope — the two stub paths of D-11), baseUrl/retry/hold-off/CA-path constructor params
- `SuperGenius/src/coinprices/PriceFetchError.hpp`, `PriceQuote.hpp`, `PriceFreshness.hpp` — failure/status types the seam maps to partial-vs-error (D-07)
- `SuperGenius/src/coinprices/coinprices.hpp/.cpp` — the legacy retriever being deleted (D-09): all three endpoints, `decodeChunkedTransfer`, throwaway-ioc pattern at `coinprices.cpp:133`

### Test fixtures being converted
- `SuperGenius/test/src/account/account_management_test.cpp` — fixture ctor builds `node_` before TEST_Fs (why D-03/D-12 put env-setting in the fixture ctor); `SetPayoutAddress` TEST_F at line 136 with the 3-node topology and `GetProcessCost` call at line 333
- `SuperGenius/test/src/price_retrieval/price_retrieval_test.cpp` — the live smoke suite being rewritten (D-10); its three tests map to: current → integration happy path, historical×2 → deleted with D-09
- `SuperGenius/test/src/price_retrieval/CMakeLists.txt` — currently unregistered-by-design comment; becomes `addtest`-registered (D-10)
- `SuperGenius/test/testutil/http_stub/HttpStubServer.hpp/.cpp` — the scriptable stub (Phase 2): per-path status/body scripting, OS-assigned port, `Url()` builder — the single instance both tiers point at (D-11)
- `SuperGenius/test/src/price_facade/price_facade_test.cpp` — usage precedent for HttpStubServer scripting (403-HTML/429 fixtures, `/api/v3/simple/price` path)
- `SuperGenius/test/src/account/CMakeLists.txt` — `addtest`/link pattern for account_management_test

### Workstream planning
- `.planning/workstreams/tokenprice/REQUIREMENTS.md` — LPM-09/LPM-10, TEST-04/TEST-05 definitions; note the Out-of-Scope historical-endpoints entry superseded by D-09
- `.planning/workstreams/tokenprice/ROADMAP.md` — Phase 4 goal, 4 success criteria, plan seeds 04-01..04-03 (04-01 resolves to full deletion per D-09)
- `.planning/workstreams/tokenprice/phases/03-local-price-manager/03-CONTEXT.md` — Phase 3 decisions D-01..D-16 the manager was built under (esp. D-01 blocking surface, D-02 ioc+thread, D-13 test seams, D-16 envelope fixtures)
- `.planning/workstreams/tokenprice/phases/02-c-price-http-client-quote-surface/02-CONTEXT.md` — Phase 2 decisions (D-07 CA bundle, D-13 hold-off, D-09 caller-ioc) inherited by the wiring
- `.planning/workstreams/tokenprice/phases/01-token-gnus-ai-worker-service/01-CONTEXT.md` — envelope contract (D-06..D-09) the tier-2 stub path replays; its deferred section carries the MNN/Vulkan exclusion correction referenced by D-13's Phase-5 note

### Diagnosis
- `/memories/repo/coingecko-price-api-frontend.md` — motivating CoinGecko diagnosis (403 WAF, 429s, no rate-limit headers) — the warm-then-fail scenarios of D-13 script exactly these

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `HttpStubServer` (Phase 2) — proven scriptable stub; drives the whole hermetic conversion (D-11/D-12) with per-path status/body scripting and `LastUserAgent` capture
- `LocalPriceManager` + `PriceHttpClientSource` (Phase 3) — the wired-in components; both tier base URLs are constructor params, so the env read (D-01) is the only new production code in the coinprices module
- `price_facade_test.cpp` — the canonical stub-scripting test style (fixture starts stub, scripts per-path responses) the rewritten suite copies
- Phase 3's `FakePriceSource` fixtures (`price_manager_test.cpp`) — reference for what the integration suite does NOT need to re-prove (manager-internal behavior); integration covers wiring only

### Established Patterns
- Env-var gates: `SGNS_CONSOLE_LOG_TESTS` / `SGNS_DEBUGLOGS` (`GeniusNode.cpp` InitLoggers) — the `SGNS_*` env precedent D-01/D-02 follow
- Lazy service construction + `ReleaseRuntimeMembersAfterIoStopped` ordered teardown — the node's existing lifecycle pattern D-05 slots into
- `addtest()` ctest registration under `SuperGenius/test/src/<suite>/` — how the rewritten price_retrieval suite gets registered (D-10)
- Per-test-directory isolation in `AccountManagement` fixture (`am_full_node_<n>` paths) — env save/restore must be equally leak-free across the shard (Claude's discretion item)

### Integration Points
- `GeniusNode::GetCoinprice` is the single cutover point; `GetGNUSPrice`/`GetProcessCost`/`ProcessImage` compile and pass unmodified (LPM-10 success criterion 2 — the acceptance proof)
- The env read feeds exactly two constructor arguments (tier-1/tier-2 base URLs) into the lazy manager construction — the smallest possible surface for LPM-09
- `price_retrieval_test` CMake registration flips from deliberately-unregistered to `addtest` — CI (Phase 5) then runs it inside the existing ctest invocation with no new matrix entries (TEST-06's constraint respected early)

</code_context>

<specifics>
## Specific Ideas

- User's constraint on test honesty for `SetPayoutAddress`: the 3-node escrow flow and every assertion stay untouched — only the price source swaps to the stub; the test must remain the same test, hermetically.
- User's reasoning on one-stub-both-tiers: tier 2 (token.gnus.ai) is undeployed (DEPLOY-01 deferred), so leaving its URL at production default in tests would just produce failures — redirecting both tiers is the only configuration that proves the fallback wiring deterministically.
- The warm-then-fail scenario ordering matters: LKG must exist before the failure flip, otherwise the second phase of the scenario has nothing stale to serve (Phase 3 D-10 — LKG is the aged L1 entry, not a separate store).

</specifics>

<deferred>
## Deferred Ideas

- **CI workflow changes** — `worker-tests` job, aarch64-Debug exclusion removal (with its MNN/Vulkan thirdparty rider): Phase 5, unchanged.
- **Live end-to-end test** (real `wrangler dev` worker + C++ manager over loopback): carried forward from Phase 3's deferred list — future milestone candidate.
- **Config-file operability for price endpoints** (`sgns_config.json` keys / `GeniusNodeConfig` fields): rejected for v1 per D-01 (env-only); revisit only if operators ask for persistent configuration.
- **Second hold-off timer for the token.gnus.ai tier**: carried forward unchanged from Phase 3 (D-12 there: none in v1).

</deferred>

---

*Phase: 4-GeniusNode Integration & Hermetic Tests*
*Context gathered: 2026-10-01*
