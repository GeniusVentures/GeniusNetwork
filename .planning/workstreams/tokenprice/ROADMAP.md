# Roadmap: PriceCoordinator — Local Manager + token.gnus.ai Fallback (v1.0)

**Workstream:** tokenprice
**Status:** 🚧 PLANNING
**Phases:** 1-5
**Total Plans:** 18

## Overview

This milestone delivers a two-tier hybrid price system. Phase 1 builds the new-toolchain side first — the `token.gnus.ai` TypeScript Cloudflare Worker with a SQLite-backed Durable Object for single-flight coalescing and `caches.default` as the shared per-colo cache — because it pins the envelope contract every later tier parses, and because the Cloudflare toolchain (`@cloudflare/vitest-plugin`, vitest 4.x pin, `new_sqlite_classes` Free-plan constraint) is the riskiest unfamiliar ground; de-risking it early protects the C++ schedule. Phases 2-3 build the C++ side in two coherent units: the transport-level correctness layer (Boost.Beast client with truthful status handling, TLS verification, a `PriceQuote` surface and freshness bands), then the orchestration layer (L1 cache, ~50ms coalescing, multi-id batching, the four-tier fallback chain). Phase 4 wires the manager into the `GeniusNode::GetCoinprice` seam and converts the network-dependent tests (`account_management_test.SetPayoutAddress`, `price_retrieval_test`) to hermetic stub-backed equivalents. Phase 5 lands CI: a path-filtered `worker-tests` job and removal of the aarch64-Debug `GTEST_FILTER` exclusion that the hermetic conversion makes obsolete.

## Phases

- [x] **Phase 1: token.gnus.ai Worker Service** — TypeScript Cloudflare Worker + SQLite Durable Object + Cache API serving the `/v1/prices` envelope, hermetically tested in workerd
- [ ] **Phase 2: C++ Price HTTP Client & Quote Surface** — Boost.Beast client with truthful status/UA/TLS/timeouts, `PriceQuote`/`PriceSource` types, freshness-band classification, scriptable local stub server
- [ ] **Phase 3: Local Price Manager** — L1 cache, request coalescing, multi-id batching, and the four-tier fallback chain (L1 → CoinGecko → token.gnus.ai → last-known-good)
- [ ] **Phase 4: GeniusNode Integration & Hermetic Tests** — configurable endpoints, `GetCoinprice`/`GetGNUSPrice` seam cutover, `SetPayoutAddress` + `price_retrieval_test` made hermetic
- [ ] **Phase 5: CI Integration** — `worker-tests` GitHub job, removal of the aarch64-Debug price-test exclusion

## Phase Details

### Phase 1: token.gnus.ai Worker Service

**Goal**: A complete, hermetically-tested Worker + Durable Object service implementing the design reference's envelope contract — the shared-cache/coalescing fallback that ~2% of client traffic will hit
**Depends on**: Nothing (first phase; independent of all C++ work)
**Requirements**: SRVC-01, SRVC-02, SRVC-03, SRVC-04, SRVC-05, SRVC-06, SRVC-07, SRVC-08, TEST-01, FRESH-01 (envelope-side)
**Success Criteria** (what must be TRUE):

  1. `GET /v1/prices?ids=bitcoin,ethereum&vs=usd` returns `{ currency, prices, fetchedAt, age, source, stale }` with correct semantics for fresh, stale-but-usable, and unavailable cases
  2. Concurrent requests with overlapping id-sets during one freshness window produce exactly one mocked-upstream CoinGecko call (asserted by call count), and each caller receives its requested subset
  3. Upstream 429/5xx/timeout returns either a stale-flagged cached envelope or a structured JSON error — never a 500 crash
  4. `npm ci && npm run typecheck && npm run test` passes with zero network egress (CoinGecko fully mocked)
  5. The DO migration uses `new_sqlite_classes` and DO state survives eviction within the test runtime; no Queues/KV bindings exist anywhere in `wrangler.jsonc`

**Plans**: 5 plans

Plans:
**Wave 1**

- [x] 01-01: Project scaffold — `package.json` with STACK.md-pinned versions (`wrangler@^4.144.0`, `@cloudflare/vitest-plugin@^1.3.3`, `vitest@^4.1.0`, `@cloudflare/workers-types`, TS `~5.9`), `wrangler.jsonc` with SQLite DO migration, tsconfig, vitest config; hello-world fetch test green

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 01-02: `GET /v1/prices` request validation (SRVC-08) + envelope response + keyless client surface with server-side-only key binding (SRVC-01, SRVC-06)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 01-03: `PriceCoordinator` Durable Object — `idFromName` per-currency instances, `ctx.storage.sql` price table, single-flight coalescing, stale-serving on upstream failure (SRVC-02, SRVC-03, SRVC-05)

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 01-04: `caches.default` read-through with sub-60s TTL ahead of the DO (SRVC-04)

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 01-05: Full hermetic vitest suite — coalescing call-count proofs, freshness/stale envelopes, upstream 429/5xx/timeout, malformed-request 4xx, DO eviction persistence (TEST-01; verifies SRVC-07 by config inspection)

### Phase 2: C++ Price HTTP Client & Quote Surface

**Goal**: The transport-correctness layer — a Boost.Beast HTTPS client scoped to the price module that surfaces real status codes/headers, verifies TLS, sends a proper User-Agent, honors timeouts, and retries only transient errors — plus the provider-independent `PriceQuote` types and the local stub server that makes all of it hermetically testable
**Depends on**: Nothing hard — envelope parsing targets the Phase 1 contract but Phase 2 can proceed against the documented contract in parallel; stub-server tests are contract-independent
**Requirements**: QUOTE-01, QUOTE-02, LPM-05, LPM-06, LPM-07, LPM-08, FRESH-02 (classification), TEST-03
**Success Criteria** (what must be TRUE):

  1. A 403-HTML response from the stub logs an error containing `403` and is classified as blocked — never reaches the JSON parser, never produces `JsonParseError`
  2. Requests carry a meaningful `User-Agent`, perform SNI + certificate verification against the pinned in-repo CA bundle, and time out (connect/handshake/read ≈ 5s) rather than hanging
  3. 403 falls through immediately and 429 never triggers a sub-minute retry against CoinGecko; only timeout/reset/DNS errors retry, with real backoff
  4. `PriceQuote{asset, currency, price, timestamp, source, stale}` and `PriceSource{LocalCache, CoinGecko, GnusPriceService, OnChain}` compile and freshness bands (0-60s / 60s-5min / >5min) classify correctly
  5. The stub server (127.0.0.1, OS-assigned port, plain HTTP, scriptable status/body per path) serves the 403-HTML and 429 fixtures from the diagnosis and drives all tests with no live network

**Plans**: 4 plans

Plans:
**Wave 1**

- [ ] 02-01: `PriceQuote` type + `PriceSource` enum + freshness-band classifier with unit tests (QUOTE-01/02, FRESH-02)
- [ ] 02-02: Boost.Beast HTTPS client in the price module — status/headers surfaced, UA header, `beast::tcp_stream::expires_after` timeouts, SNI, `verify_peer` + pinned `cacert.pem` (LPM-05/06/08)

**Wave 2** *(blocked on Wave 1 completion)*

- [ ] 02-03: Scriptable Beast stub server test fixture + client-level tests against 200/403-HTML/429/timeout cases (TEST-03)

**Wave 3** *(blocked on Wave 2 completion)*

- [ ] 02-04: Retry/backoff policy — transient-only classification, real backoff, 403/429 immediate fall-through (LPM-07)

### Phase 3: Local Price Manager

**Goal**: The orchestration layer — an in-memory L1 cache, a ~50ms request-coalescing window that unions requested ids, multi-id batching into single `/simple/price` calls, and the four-tier fallback chain with last-known-good — all unit-tested through an injected client interface with zero sockets
**Depends on**: Phase 2 (consumes `PriceQuote`, the client interface, and freshness bands)
**Requirements**: LPM-01, LPM-02, LPM-03, LPM-04, FRESH-01 (manager-side), FRESH-02 (fallback decisions), TEST-02
**Success Criteria** (what must be TRUE):

  1. A cache hit within 60s returns without any network I/O, reported `source: LocalCache`; a request after expiry refetches
  2. N concurrent requests arriving within ~50ms collapse into one upstream call for the union of ids, each waiter receiving its subset
  3. When CoinGecko direct fails (403/429/timeout), the manager queries `token.gnus.ai`; when that also fails, a quote ≤5min old is served stale-flagged; only >5min-or-nothing errors
  4. Every behavior above is proven with an injected fake client — the unit suite opens no sockets and runs deterministically

**Plans**: 4 plans

Plans:

- [ ] 03-01: L1 cache — timestamped entries, 60s freshness window, thread-safe (LPM-01)
- [ ] 03-02: Coalescing window (~50ms) + multi-id batching into one `/simple/price` call (LPM-02, LPM-03)
- [ ] 03-03: Four-tier fallback chain with band-aware decisions and last-known-good (LPM-04, FRESH-01/02)
- [ ] 03-04: Full injected-fake unit suite — L1 hit, dedupe, fallback order, last-known-good, retry classification (TEST-02)

### Phase 4: GeniusNode Integration & Hermetic Tests

**Goal**: The manager replaces `CoinGeckoPriceRetriever` behind the existing `GetCoinprice`/`GetGNUSPrice` seam with configurable endpoints, and the two network-dependent test suites become hermetic — removing the live-internet dependency that got `SetPayoutAddress` excluded from Linux aarch64-Debug CI
**Depends on**: Phase 3 (the manager being integrated)
**Requirements**: LPM-09, LPM-10, TEST-04, TEST-05
**Success Criteria** (what must be TRUE):

  1. Endpoint base URLs are configurable (env var and/or `GeniusNodeConfig`) with CoinGecko defaults; a test redirects the node to the local stub with no code change
  2. `GetProcessCost` → `GetGNUSPrice` compiles and passes unmodified — same `outcome::result<double>` surface, finite/positive validation intact
  3. `account_management_test.SetPayoutAddress` passes entirely against the local stub, no live CoinGecko
  4. `price_retrieval_test` contains no live-network cases — every scenario is stub- or fake-driven

**Plans**: 3 plans

Plans:

- [ ] 04-01: Configurable price endpoints (env/config) + cutover of `GetCoinprice` to the Local Price Manager; `CoinGeckoPriceRetriever` retired or reduced to what still compiles (LPM-09, LPM-10)
- [ ] 04-02: `SetPayoutAddress` pointed at the local stub, hermetic and green (TEST-04)
- [ ] 04-03: `price_retrieval_test` converted to hermetic equivalents (TEST-05)

### Phase 5: CI Integration

**Goal**: CI reflects the new reality — Worker tests run as a cheap hermetic job, and the aarch64-Debug exclusion that existed only because of the live-internet dependency is gone
**Depends on**: Phase 1 (worker tests exist), Phase 4 (exclusion is safe to remove)
**Requirements**: TEST-06, TEST-04 (exclusion removal)
**Success Criteria** (what must be TRUE):

  1. A `worker-tests` job (Node 22, `npm ci` → typecheck → `vitest run`, path-filtered to the worker directory) runs green on GitHub-hosted ubuntu-latest without network access to CoinGecko
  2. The Linux aarch64-Debug `GTEST_FILTER` exclusion of `AccountManagement.SetPayoutAddress` is removed from `SuperGenius/.github/workflows/cmake.yml` and the full suite passes there
  3. C++-only PRs do not trigger the Node toolchain setup (path filter verified)

**Plans**: 2 plans

Plans:

- [ ] 05-01: Add `worker-tests` job to `SuperGenius/.github/workflows/cmake.yml` (TEST-06)
- [ ] 05-02: Remove the aarch64-Debug `SetPayoutAddress` exclusion; run/verify the affected matrix leg (TEST-06, closes TEST-04)

## Progress

**Execution Order:** Phases 1 → 2 → 3 → 4 → 5 (Phases 1 and 2 may overlap — no hard dependency; 2 → 3 → 4 → 5 are sequential)

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. token.gnus.ai Worker Service | 5/5 | Complete    | 2026-09-30 |
| 2. C++ Price HTTP Client & Quote Surface | 0/4 | Not started | - |
| 3. Local Price Manager | 0/4 | Not started | - |
| 4. GeniusNode Integration & Hermetic Tests | 0/3 | Not started | - |
| 5. CI Integration | 0/2 | Not started | - |

---

## Milestone Summary

**Key Decisions:**

- **Worker first (Phase 1)** — the Cloudflare toolchain is the riskiest unfamiliar ground (vitest-plugin rename, vitest 4.x pin, `new_sqlite_classes` Free-plan constraint), and the envelope contract it pins is what Phase 2-3 C++ code parses. De-risking it early protects the C++ schedule. Phases 1 and 2 have no hard dependency and can overlap if desired.
- **C++ split into transport (Phase 2) vs orchestration (Phase 3)** — mirrors the two failure classes from the diagnosis: transport bugs (swallowed status, no UA, no TLS verification, hostile retries) are fixed and proven independently of the cache/coalescing/fallback logic, so each phase's tests stay small and deterministic.
- **Integration + hermetic tests as their own phase (Phase 4)** — cutover of a live `GeniusNode` seam and conversion of two existing test suites is a coherent, independently-verifiable unit; keeping it out of Phase 3 keeps the manager pure and injectable.
- **CI as its own phase (Phase 5)** — small but cross-cutting (touches the workflow file all 16 build-matrix legs share); isolating it makes verification a single matrix-leg run plus one new job.
- **Envelope contract defined by Phase 1, consumed by Phase 3** — FRESH-01 spans both sides; the worker-side semantics land with SRVC-01 in Phase 1, the manager-side band decisions in Phase 3 (traceability lists both).
- **Zero new vendored thirdparty** (per STACK.md) — the only new assets are the pinned CA bundle and the Worker's own `package.json` dev-dependency set.

---
*Roadmap created: 2026-09-29 from REQUIREMENTS.md v1.0 (28 requirements) + STACK.md research*
