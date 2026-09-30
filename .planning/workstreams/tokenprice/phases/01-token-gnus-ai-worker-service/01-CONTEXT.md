# Phase 1: token.gnus.ai Worker Service - Context

**Gathered:** 2026-09-29
**Status:** Ready for planning

<domain>
## Phase Boundary

A complete, hermetically-tested TypeScript Cloudflare Worker + SQLite-backed Durable Object + Cache API service implementing the `/v1/prices` envelope contract — the shared-cache/coalescing fallback tier that ~2% of client traffic will hit. Code + tests only; live deployment is DEPLOY-01 (deferred). This phase pins the envelope contract that Phase 2/3 C++ code parses.

Requirements in scope: SRVC-01 through SRVC-08, TEST-01, FRESH-01 (envelope-side semantics).

</domain>

<decisions>
## Implementation Decisions

### Repo placement
- **D-01:** The Worker project lives at `SuperGenius/pricecoordinator/` — inside the SuperGenius submodule, sibling of `src/` (precedent: `evmrelay/`, `gRPCForSuperGenius/`, `GeniusKDF/`). This is required for Phase 5's path-filtered `worker-tests` job in `SuperGenius/.github/workflows/cmake.yml` — GitHub workflows only trigger on paths inside their own repository, so the job as written in plan 05-01 only works if the directory is in the SuperGenius repo.
- **D-02:** Directory name is `pricecoordinator` (named after the DO class / design concept) — this **overrides** the `tokenpriceservice` name used in research/STACK.md and research/ARCHITECTURE.md examples. Downstream plans, CI path filters, and docs must use `SuperGenius/pricecoordinator/` consistently.
- **D-03:** The directory is invisible to CMake (no `CMakeLists.txt` coupling; plain `package.json` project) so the 16-config C++ matrix is unaffected. `node_modules` must be gitignored inside the submodule.

### CoinGecko key handling (SRVC-06)
- **D-04:** Optional secret wired now: the Worker reads `env.COINGECKO_API_KEY` (a wrangler secret binding, optional — never in `wrangler.jsonc`, never in any response or client). When set, upstream CoinGecko calls carry the `x-cg-demo-api-key` header; when unset, calls are anonymous. Tests must cover both paths.
- **D-05:** Key scope is global — applied identically to all upstream calls regardless of which `PriceCoordinator:<CURRENCY>` DO instance issues them. Currency is not a key axis. Clients (C++ node) stay keyless by design.

### Envelope & error contract (SRVC-01, SRVC-05, SRVC-08; consumed by Phase 2/3)
- **D-06:** `source` string values are exactly two: `"coingecko"` (live upstream fetch) and `"coingecko-cache"` (DO stale-served from SQL) — matching the design reference's JSON examples verbatim. No third value for `caches.default`-served responses. The C++ side (Phase 3) maps these to `PriceSource::CoinGecko` / `PriceSource::GnusPriceService` respectively — the envelope `source` describes the upstream that produced the price, not which client tier served it.
- **D-07:** Upstream failure (429/5xx/timeout) with usable DO cache → serve stale-first: 200 + envelope, `stale: true`, `source: "coingecko-cache"`. A structured error response is returned only when nothing usable exists. (SRVC-05's first clause; FRESH-02.)
- **D-08:** Error responses: 502 + JSON error body `{ "error": { "code", "message", "upstreamStatus"? } }` for upstream failure with nothing usable cached (`upstreamStatus` included whenever CoinGecko returned an HTTP status — truthful diagnosis, unlike today's swallowed 403); 400 for malformed `ids`/`vs` (SRVC-08); 404 unknown paths; 405 non-GET methods. Never a 500 crash.
- **D-09:** Partial id coverage: CoinGecko's `/simple/price` omits unknown ids from its response; the envelope's `prices` object includes only the ids CoinGecko returned, absent otherwise — no error for partial coverage, no `missing` field. Clients derive absence by diffing requested vs returned.

### DO storage semantics (SRVC-02, SRVC-03, FRESH-01)
- **D-10:** `ctx.storage.sql` table is one row per id: `id TEXT PRIMARY KEY, price REAL, fetchedAt INTEGER`. Each CoinGecko id keeps its own last-known price/timestamp; a partial batch response never clobbers older rows for ids not returned.
- **D-11:** Timestamps are per-id. The envelope's `fetchedAt` = max(fetchedAt of returned ids), `age` = now − that max, and `stale: true` when ANY returned id is >60s old.
- **D-12:** Freshness gates exactly per FRESH-01: DO serves from SQL without refetch when every requested id is ≤60s old; refetches only ids older than 60s; rows aged 60s–5min are served (flagged `stale: true`, `source: "coingecko-cache"`) only when the upstream fetch fails; rows >5min are never served (unavailable band).

### Claude's Discretion
- Exact npm script names beyond `dev`/`test`/`typecheck`, vitest test-file organization, `wrangler.jsonc` `compatibility_date` value, error `code` string tokens, internal module split (`index.ts`/`coordinator.ts`/`envelope.ts` per ARCHITECTURE.md sketch or otherwise), single-flight promise-sharing implementation details inside the DO, and SQL row pruning policy (delete >5min rows vs keep-but-unservable) — all left to research/planning.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream planning
- `.planning/workstreams/tokenprice/REQUIREMENTS.md` — SRVC-01..08, TEST-01, FRESH-01 definitions; Out of Scope table (no deployment, no Queues/KV, keyless clients)
- `.planning/workstreams/tokenprice/ROADMAP.md` — Phase 1 goal, success criteria, and the 5 plan seeds
- `.planning/workstreams/tokenprice/STATE.md` — current workstream position

### Research (verified 2026-09-29)
- `.planning/workstreams/tokenprice/research/STACK.md` — toolchain pins (wrangler@^4.144.0, @cloudflare/vitest-plugin@^1.3.3, vitest@^4.1.0 pinned NOT 5.x, @cloudflare/workers-types, TS ~5.9), minimal `wrangler.jsonc` with `new_sqlite_classes` migration, "What NOT to Use" table
- `.planning/workstreams/tokenprice/research/ARCHITECTURE.md` — recommended project structure (§Recommended Project Structure — note the `tokenpriceservice/` name there is superseded by D-02), component responsibilities
- `.planning/workstreams/tokenprice/research/PITFALLS.md` — toolchain landmines (vitest-plugin rename, vitest 4.x pin, Free-plan SQLite DO constraint)
- `.planning/research/pricing_coordinator.md` — the design reference: hybrid architecture rationale, envelope JSON examples (source strings D-06), freshness bands, DO coalescing model, Free-tier limit math

### Diagnosis
- `/memories/repo/coingecko-price-api-frontend.md` — the motivating CoinGecko diagnosis (403 path-scoped WAF, minutes-scale 429, no rate-limit headers, `coinprices.cpp` client bugs); includes the 2026-09-29 correction about the aarch64-Debug CI exclusion's real cause (MNN/Vulkan, not CoinGecko)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None for Phase 1 TypeScript work — this is a greenfield Node project. The only relationship to existing code is contractual: the envelope (D-06..D-09) will be parsed by Phase 2/3 C++ code in `SuperGenius/src/coinprices/`.

### Established Patterns
- SuperGenius tree hosts non-`src/` self-contained subtrees (`evmrelay/`, `gRPCForSuperGenius/`, `GeniusKDF/`, `SGProcessingManager/`) — `pricecoordinator/` follows this precedent (D-01).
- CI precedent: `SuperGenius/.github/workflows/cmake.yml` — the Phase 5 `worker-tests` job will live there with a `paths:` filter on `pricecoordinator/**`; that filter is only possible because of D-01.

### Integration Points
- **Envelope contract** (`GET /v1/prices?ids=<csv>&vs=<currency>` → `{currency, prices, fetchedAt, age, source, stale}`) is the single integration surface — consumed by the Phase 3 fallback chain via the Phase 2 Beast client. Keep it exact.
- **CoinGecko upstream**: `https://api.coingecko.com/api/v3/simple/price?ids=<csv>&vs_currencies=<currency>` — anonymous today, optional `x-cg-demo-api-key` header per D-04.

</code_context>

<specifics>
## Specific Ideas

- The design reference's JSON examples are normative for the envelope: happy path (`"source": "coingecko"`, `"stale": false`, `fetchedAt` epoch seconds) and stale path (`"source": "coingecko-cache"`, `"stale": true`).
- Coalescing proof style (TEST-01): assert on mocked-upstream **call counts** — concurrent requests with overlapping id-sets during one freshness window must produce exactly one upstream call, each caller receiving its requested subset (per-test-file DO isolation regenerates state, so call-count assertions are the deterministic proof, not timing).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

### Cross-phase correction (for Phase 5 / TEST-04, not this phase)
User correction captured 2026-09-29: `AccountManagement.SetPayoutAddress`'s Linux aarch64-Debug `GTEST_FILTER` exclusion in `SuperGenius/.github/workflows/cmake.yml` exists because of the **MNN `VulkanInstance` assert** (no usable Vulkan device on the ARM runner's lavapipe ICD; Debug-only since `NDEBUG` compiles the assert out) — **not** because of the CoinGecko network dependency. Hermetic prices (Phase 4) alone will NOT make that exclusion removable; removal additionally requires the thirdparty MNN rebuild (graceful Vulkan degradation, already a rider on the next thirdparty rebuild). Phase 5 plan 05-02 and TEST-04's exclusion-removal clause need re-scoping when Phase 5 is planned — the `worker-tests` job half of TEST-06 is unaffected. The hermetic conversion of `SetPayoutAddress` itself (TEST-04 clause 1, Phase 4) remains fully valid and valuable: the test is genuinely network-dependent on live CoinGecko today via `GetProcessCost` → `GetGNUSPrice`.

</deferred>

---

*Phase: 1-token.gnus.ai Worker Service*
*Context gathered: 2026-09-29*
