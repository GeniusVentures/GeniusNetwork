---
phase: 01-token-gnus-ai-worker-service
plan: 02
subsystem: api
tags: [cloudflare-workers, rest-api, validation, envelope, coingecko, testing]

requires:
  - phase: 01-token-gnus-ai-worker-service/01-01
    provides: scaffolded project, vitest-in-workerd harness, MSW network, egress guard
provides:
  - "Envelope wire contract: {currency, prices, fetchedAt, age, source, stale} with D-06/D-06a/D-09/D-11 semantics — the single integration surface Phase 2/3 C++ parses"
  - "parsePricesRequest allowlist validation (SRVC-08) rejecting before any DO/cache interaction"
  - "fetchUpstream CoinGecko client — key read ONLY here (SRVC-06/D-04/D-05), status-before-parse, JS-level AbortController timeout"
  - "Router error taxonomy (D-08): 400 invalid_request / 404 not_found / 405 method_not_allowed / 502 upstream_error{upstreamStatus} — JSON bodies, never 500"
  - "Single DO-call-site seam function in index.ts (interim: direct upstream; 01-03 swaps the body)"
affects: [01-03 DO, 01-04 cache, 01-05 full suite, phase-2 envelope parser, phase-3 fallback chain]

tech-stack:
  added: []
  patterns:
    - "Discriminated-union parse result ({ok:true,...} | {ok:false,status,code,message})"
    - "Typed error class (UpstreamError) carrying upstreamStatus for truthful 502s"
    - "TDD RED→GREEN per task with failing-test commits"

key-files:
  created:
    - SuperGenius/pricecoordinator/src/envelope.ts
    - SuperGenius/pricecoordinator/src/validate.ts
    - SuperGenius/pricecoordinator/src/upstream.ts
    - SuperGenius/pricecoordinator/test/envelope.freshness.test.ts
    - SuperGenius/pricecoordinator/test/router.validation.test.ts
    - SuperGenius/pricecoordinator/test/key.test.ts
  modified:
    - SuperGenius/pricecoordinator/src/index.ts
    - SuperGenius/pricecoordinator/test/hello.test.ts
    - SuperGenius/pricecoordinator/tsconfig.json

key-decisions:
  - "buildEnvelope takes an explicit `staleServe` boolean supplied by the caller — source is freshness-based (D-06a) with the cache value reachable ONLY via the stale-serve path; the coordinator in 01-03 owns that flag"
  - "classifyAge treats exactly-60s as fresh and exactly-300s as stale (D-12 ≤ semantics); boundaries pinned by tests at 59/60/61 and 299/300/301"
  - "Hello tests updated rather than deleted: they still prove both invocation styles + MSW layering + egress canary, now asserting the route-table 404 on GET /"
  - "tsconfig gained target:esnext (Set spread iteration under strict mode)"

patterns-established:
  - "Error body contract { error: { code, message, upstreamStatus? } } with code tokens: invalid_request, not_found, method_not_allowed, upstream_error (egress_blocked is test-only)"
  - "Env override in unit-style tests via `{ ...spread } as unknown as Env` (plugin 1.2.x has no generated Env typing)"
  - "Timeout tests: MSW handler returning a never-resolving Promise + vi.advanceTimersByTimeAsync(UPSTREAM_TIMEOUT_MS + slack)"

requirements-completed: [SRVC-01, SRVC-06, SRVC-08, FRESH-01]

duration: 35min
completed: 2026-09-30
---

# Plan 01-02: Router + Envelope + Upstream Summary

**The Worker's request/response contract layer is live and pinned by tests: six-key envelope, allowlist validation, D-08 error taxonomy, and server-side-only CoinGecko key binding — 35/35 hermetic tests green.**

## Performance

- **Duration:** ~35 min
- **Tasks:** 2/2 (both TDD: RED commit → GREEN commit)
- **Tests:** 35 passing (19 envelope/validation + 12 router/key + 4 hello)

## Task Commits (SuperGenius @ dev_tokenprice)

1. **Task 1 RED** — `dff04dd44` (test: failing envelope freshness + validation)
2. **Task 1 GREEN** — `f885ee814` (feat: envelope model + request validation)
3. **Task 2 RED** — `b885ad0c4` (test: failing router contract + key/timeout)
4. **Task 2 GREEN** — `fd3c30957` (feat: router + upstream client, hello adjusted)

## Files Created/Modified

- `src/envelope.ts` — PriceEnvelope/PriceRow/SourceKind; FRESH_SEC=60, STALE_SEC=300, BATCH_WINDOW_MS=15, UPSTREAM_TIMEOUT_MS=8000, MAX_IDS_PER_REQUEST=50; nowSec/parseSec/classifyAge/usableRows/buildEnvelope
- `src/validate.ts` — parsePricesRequest discriminated union, ids `[a-z0-9-]+` deduped ≤50, vs `[a-z]{2,10}`
- `src/upstream.ts` — fetchUpstream + UpstreamError; x-cg-demo-api-key iff set; AbortController timeout; status-before-parse
- `src/index.ts` — route table, JSON error bodies, single DO-call-site seam (interim direct upstream), Env interface
- `test/envelope.freshness.test.ts` (19), `test/router.validation.test.ts` (12), `test/key.test.ts` (7... 6 tests incl. timeout), `test/hello.test.ts` adjusted

## Final Error-Code Tokens

`invalid_request` (400) · `not_found` (404) · `method_not_allowed` (405) · `upstream_error` (502, optional `upstreamStatus`) · `egress_blocked` (test-only, 599)

## The Env Interface

```ts
export interface Env {
  PRICE_COORDINATOR: DurableObjectNamespace;
  COINGECKO_API_KEY?: string; // optional (D-04) — read only in upstream.ts
}
```

## Interim DO-Call-Site Wiring

`fetchFromCoordinator(env, ids, currency)` in `src/index.ts` — one seam function; body currently calls `fetchUpstream` directly and builds a fresh-success envelope (`staleServe=false`). Commented `interim:` marker at the body. Plan 01-03 replaces the body with `env.PRICE_COORDINATOR.get(idFromName(currency)).fetch(...)` + stale/error relay; plan 01-04 wraps the seam with `caches.default`.

## Envelope-Semantics Edge Cases Discovered (D-06a)

- **Fresh-from-SQL** and **mixed-band success** both yield `source:"coingecko"` — the "only" clause is enforced by making `"coingecko-cache"` reachable solely through the explicit `staleServe=true` argument; band membership alone can never produce it (pinned by the mixed-band test).
- Partial-refresh shape (requested {a,b}, `a` fresh, `b` 120s because CoinGecko omitted it) → `stale:true, source:"coingecko"` — correct per D-06a; callers see staleness without a cache-tier marker.
- `fetchedAt` starts at 0 and `age` is computed from max of *returned* ids only — an all-absent response (CoinGecko returns nothing) would produce `fetchedAt:0, age:<now>`; 01-03's coordinator must treat empty-row + upstream-success as a partial-coverage envelope (D-09), never an error.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — missing critical] tsconfig needed `target: "esnext"`**
- Set spread iteration (`[...new Set(tokens)]`) errors under the default target. Added `target` alongside `lib` — no behavioral change to the bundled output (wrangler/esbuild controls the real target).

**2. [Rule 3 — test correction] parseSec test passed seconds to a ms→s function**
- The RED-phase test asserted `parseSec(1790719234.9) === 1790719234` — wrong input magnitude. Fixed the test to pass milliseconds (`1_790_719_234_900.9`). The implementation was correct (Landmine 10: seconds everywhere).

**3. [Rule 3 — anticipated adjustment] hello.test.ts expectations updated**
- The plan explicitly authorized this: the real route table 404s `GET /`. Tests now assert `404 not_found` JSON for both invocation styles; MSW-layering and egress-canary tests unchanged and still green.

**Total deviations:** 3 auto-fixed, 0 user-facing. **Impact:** none on contract semantics.

## Self-Check: PASSED

- `npm run test` → 35/35 (4 files); `npm run typecheck` → 0; `npm ci` unaffected since 01-01
- Boundary greps: `59`×6, `301`×2 in envelope.freshness.test.ts
- Only source strings in envelope.ts: `coingecko`, `coingecko-cache` (no third value)
- `interim` marker present in index.ts; upstream.ts contains x-cg-demo-api-key (L34), AbortController (L40), response.ok guard (L56)
- Happy-path six-key envelope deep-matches the design reference; 4xx table + keyed/anonymous/timeout all green
