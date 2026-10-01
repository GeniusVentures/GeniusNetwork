# Requirements: PriceCoordinator — Local Manager + token.gnus.ai Fallback (v1.0)

**Defined:** 2026-09-29
**Workstream:** tokenprice
**Core Value:** Price-dependent paths (`GetProcessCost` → `GeniusNode::GetGNUSPrice`) never hard-fail when CoinGecko's anonymous endpoint is WAF/rate-limit blocked — resilient pricing via a two-tier hybrid (device-side Local Price Manager primary, `token.gnus.ai` shared-cache fallback)

**Inputs:** `.planning/research/pricing_coordinator.md` (hybrid design) · `.planning/workstreams/tokenprice/research/STACK.md` (toolchain, verified 2026-09-29) · `/memories/repo/coingecko-price-api-frontend.md` (diagnosis: 403 path-scoped WAF block, minutes-scale 429, no rate-limit headers, `coinprices.cpp` client bugs)

## v1 Requirements

Requirements for the PriceCoordinator milestone. Each maps to roadmap phases (traceability filled at roadmap creation).

### Worker Service — `token.gnus.ai` (SRVC)

- [x] **SRVC-01**: TypeScript Cloudflare Worker serves `GET /v1/prices?ids=<csv>&vs=<currency>` returning the envelope `{ currency, prices: { <id>: <number> }, fetchedAt, age, source, stale }` with the exact field semantics from the design reference
- [x] **SRVC-02**: Durable Object class `PriceCoordinator` (one instance per currency, e.g. `PriceCoordinator:USD` via `idFromName`) provides cross-client single-flight request coalescing — concurrent requests for overlapping id-sets result in exactly one upstream CoinGecko call per freshness window
- [x] **SRVC-03**: SQLite-backed Durable Object via the `new_sqlite_classes` migration tag (Free-plan requirement; KV-backed `new_classes` is paid-only); price state survives DO eviction within the test runtime
- [x] **SRVC-04**: Worker consults `caches.default` before the DO and populates it on miss with a sub-60s TTL, so per-colo repeated requests bypass the DO entirely
- [x] **SRVC-05**: Upstream CoinGecko errors are handled truthfully: 429/5xx/timeouts do not crash the worker; the DO serves stale-but-usable cached prices (`"stale": true`, `source` indicating cache) when available, and a structured error envelope when not
- [x] **SRVC-06**: Clients are keyless — no CoinGecko API key appears in any client-facing code, config, or response; if a key exists it is read exclusively server-side (Worker secret/`env` binding)
- [x] **SRVC-07**: No Cloudflare Queues and no Workers KV anywhere in the price path (explicit design decision — Queues free-tier op accounting and KV's 1,000 writes/day cap make both unusable)
- [x] **SRVC-08**: Malformed requests (missing/empty `ids`, oversized id lists, invalid `vs`) are rejected with 4xx and a JSON error body, not a 500

### Local Price Manager — C++ (LPM)

- [ ] **LPM-01**: In-memory L1 cache holds fetched prices with timestamps; a hit within the freshness window (60s) is served without any network I/O and reported with `source: LocalCache`
- [ ] **LPM-02**: Concurrent requests for prices arriving within the coalescing window (~50ms) collapse into a single upstream call covering the union of requested ids; all waiters receive their requested subsets
- [ ] **LPM-03**: Multi-id requests are batched into one CoinGecko `/simple/price` call (`ids=a,b,c&vs_currencies=usd`) — never one request per id
- [ ] **LPM-04**: Fallback chain in order: fresh L1 cache → CoinGecko direct → `token.gnus.ai` → last-known-good (stale ≤ 5 min); each tier is attempted only when the prior tier fails
- [x] **LPM-05**: HTTP status codes are surfaced truthfully — a 403/429/5xx from CoinGecko is logged with its real status and classified (not fed to the JSON parser as a misleading `JsonParseError`); the logged error string for a blocked request contains the actual status code
- [x] **LPM-06**: All outbound HTTP requests send a meaningful `User-Agent` header and use the Boost.Beast client scoped to the price module (not `FileManager::LoadASync`), with connect/handshake/read timeouts ≈ 5s
- [ ] **LPM-07**: Retry policy: only transient transport errors (timeout, connection reset, DNS) are retried, with real backoff; 403 falls through to the next tier immediately; 429 falls through without re-triggering CoinGecko's limiter (no sub-minute retries against CoinGecko)
- [x] **LPM-08**: HTTPS peer verification is enabled in the new client (verify_peer + SNI + pinned in-repo CA bundle — the existing `HTTPDevice` verify toggle is a no-op and out of scope)
- [ ] **LPM-09**: The price endpoint base URL(s) are configurable (env var and/or `GeniusNodeConfig` field) with CoinGecko defaults, so tests can point at a local stub
- [ ] **LPM-10**: `GeniusNode::GetGNUSPrice` / `GetCoinprice` seam is preserved: same `outcome::result` surface, finite/positive price validation unchanged, existing call sites (`GetProcessCost`) compile and pass without modification

### Provider-Independent Quote Surface (QUOTE)

- [x] **QUOTE-01**: A `PriceQuote` type exposes `asset`, `currency`, `price`, `timestamp`, `source`, `stale` — decoupling callers from which provider served the quote
- [x] **QUOTE-02**: `PriceSource` enum defines `LocalCache`, `CoinGecko`, `GnusPriceService`, and a reserved-but-unimplemented `OnChain` value

### Freshness Bands (FRESH)

- [x] **FRESH-01**: Quotes are classified 0–60s = fresh / 60s–5min = stale-but-usable / >5min = unavailable, in both the Worker envelope (`stale` field, `age` seconds) and the C++ manager (band-aware fallback decisions)
- [x] **FRESH-02**: A stale-but-usable quote is served (flagged) rather than failing, when no fresher source is reachable; only the >5min band is treated as unavailable for the fallback chain

### Test Infrastructure & CI (TEST)

- [x] **TEST-01**: Worker unit/integration tests run via `@cloudflare/vitest-plugin` + `vitest@^4.1.0` inside the local workerd runtime with real DO-SQLite and Cache API, CoinGecko mocked — hermetic, zero network egress, deterministic (coalescing proven by upstream call-count assertions)
- [ ] **TEST-02**: C++ Local Price Manager is unit-tested against an injected client interface (no sockets): L1 hit, coalescing dedupe, fallback order, last-known-good, freshness bands, retry classification (403/429 never retried against CoinGecko)
- [x] **TEST-03**: A scriptable local HTTP stub server (Boost.Beast, `127.0.0.1`, OS-assigned port, plain HTTP) serves canned status/body responses for client-level tests including the 403-HTML and 429 cases from the diagnosis
- [ ] **TEST-04**: `account_management_test.SetPayoutAddress` runs hermetically against the local stub (configurable endpoint), and its Linux aarch64-Debug `GTEST_FILTER` exclusion in `SuperGenius/.github/workflows/cmake.yml` is removed
- [ ] **TEST-05**: The existing network-dependent `price_retrieval_test` cases are replaced by hermetic equivalents (no live CoinGecko calls in the suite)
- [ ] **TEST-06**: CI gains a lightweight `worker-tests` job (Node 22, `npm ci` → typecheck → `vitest run`, path-filtered) separate from the 16-config C++ build matrix; C++ price tests run inside the existing `ctest` invocation with no new matrix entries

## v2 Requirements

Deferred to future milestones. Tracked but not in current roadmap.

### Deployment (DEPLOY)

- **DEPLOY-01**: Live deployment of the Worker to `token.gnus.ai` (routes/custom domain, secrets provisioning, migrations applied) — this milestone delivers code + tests only
- **DEPLOY-02**: Operational hardening of the deployed service (analytics/alerting, abuse limiting on `/v1/prices`)

### Sources & Providers (SRC)

- **SRC-01**: `OnChain` price source implementation (dex/on-chain oracle) — enum value reserved this milestone, explicitly deferred
- **SRC-02**: Additional fallback upstreams behind the Worker (e.g. CryptoCompare/Binance public APIs) per the diagnosis memory's multi-upstream sketch
- **SRC-03**: Paid/keyed CoinGecko access for the Worker (if traffic ever justifies it) — key handling already designed for server-side-only

## Out of Scope

Explicitly excluded from v1.0. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Live Worker deployment / `wrangler deploy` in CI | Milestone definition: code + tests only; deployment is a later/manual step (DEPLOY-01) |
| Cloudflare Queues or Workers KV in the price path | Explicit design rejection — free-tier limits (Queues ~3,333 msgs/day; KV 1,000 writes/day) make them unusable |
| On-chain/dex price source | Deferred per milestone charter (SRC-01); enum value reserved only |
| CoinGecko API key in any client (C++ node, SDK, wallet) | A key in a distributed binary is not a secret; clients stay keyless by design |
| New vendored thirdparty C++ libraries (curl, cpr, nlohmann, etc.) | Everything needed (Boost.Beast/Asio/SSL, rapidjson, fmt, GTest, OpenSSL) is already built in-tree; stack research verified zero additions |
| Refactoring `FileManager`/`HTTPDevice` (AsyncIOManager) to surface status codes / fix the verify-peer dead toggle | Touches every MNN/IPFS/SFTP loader consumer; new Beast client is scoped to the price module instead. Pre-existing issues logged in STACK.md for a future milestone |
| GeniusWallet Flutter price-path changes | Wallet has its own separate CoinGecko usage; out of scope unless trivially relevant |
| gRPC exposure of price data | No API surface change requested; `GetGNUSPrice` C++ seam is the only integration point |
| Historical price endpoints (`getHistoricalPrices`/`getHistoricalPriceRange`) redesign | Kept compiling behind the existing surface; only the current-price path is in scope |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SRVC-01 | Phase 1 | Mapped |
| SRVC-02 | Phase 1 | Mapped |
| SRVC-03 | Phase 1 | Mapped |
| SRVC-04 | Phase 1 | Mapped |
| SRVC-05 | Phase 1 | Mapped |
| SRVC-06 | Phase 1 | Mapped |
| SRVC-07 | Phase 1 | Mapped |
| SRVC-08 | Phase 1 | Mapped |
| LPM-01 | Phase 3 | Mapped |
| LPM-02 | Phase 3 | Mapped |
| LPM-03 | Phase 3 | Mapped |
| LPM-04 | Phase 3 | Mapped |
| LPM-05 | Phase 2 | Mapped |
| LPM-06 | Phase 2 | Mapped |
| LPM-07 | Phase 2 | Mapped |
| LPM-08 | Phase 2 | Mapped |
| LPM-09 | Phase 4 | Mapped |
| LPM-10 | Phase 4 | Mapped |
| QUOTE-01 | Phase 2 | Mapped |
| QUOTE-02 | Phase 2 | Mapped |
| FRESH-01 | Phases 1 + 3 | Mapped (envelope semantics Phase 1; manager band decisions Phase 3) |
| FRESH-02 | Phases 2 + 3 | Mapped (classification Phase 2; fallback decisions Phase 3) |
| TEST-01 | Phase 1 | Mapped |
| TEST-02 | Phase 3 | Mapped |
| TEST-03 | Phase 2 | Mapped |
| TEST-04 | Phases 4 + 5 | Mapped (hermetic conversion Phase 4; CI exclusion removal Phase 5) |
| TEST-05 | Phase 4 | Mapped |
| TEST-06 | Phase 5 | Mapped |

**Coverage:**

- v1 requirements: 28 total
- Mapped to phases: 28
- Unmapped: 0 ✓

---
*Requirements defined: 2026-09-29*
*Last updated: 2026-09-29 after ROADMAP.md creation (Phases 1-5, 18 plans) — 100% coverage*
