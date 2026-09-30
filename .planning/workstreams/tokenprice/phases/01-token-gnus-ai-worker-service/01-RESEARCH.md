# Phase 1: token.gnus.ai Worker Service - Research

**Researched:** 2026-09-29
**Domain:** TypeScript Cloudflare Worker + SQLite-backed Durable Object + Cache API, hermetically tested via `@cloudflare/vitest-plugin` inside workerd
**Confidence:** HIGH (toolchain verified against npm registry 2026-09-29; test APIs verified against Cloudflare docs updated 2026-09-28 and cloudflare/workers-sdk source/fixtures on `main`)

<user_constraints>
## User Constraints (from CONTEXT.md — binding)

### Locked Decisions
- **D-01:** Project lives at `SuperGenius/pricecoordinator/` — inside the SuperGenius submodule, sibling of `src/` (required for Phase 5's path-filtered `worker-tests` job in `SuperGenius/.github/workflows/cmake.yml`).
- **D-02:** Directory name is `pricecoordinator` — **overrides** the `tokenpriceservice/` name in research/STACK.md and research/ARCHITECTURE.md examples. All plans, CI path filters, and docs use `SuperGenius/pricecoordinator/`.
- **D-03:** Directory invisible to CMake (plain `package.json` project, no CMake coupling); `node_modules` gitignored inside the submodule.
- **D-04:** Optional secret wired now: Worker reads `env.COINGECKO_API_KEY` (wrangler secret binding, optional — never in `wrangler.jsonc`, never in any response or client). When set, upstream calls carry `x-cg-demo-api-key`; when unset, anonymous. Tests cover both paths.
- **D-05:** Key scope is global — identical for all `PriceCoordinator:<CURRENCY>` DO instances. Clients stay keyless.
- **D-06:** `source` values are exactly `"coingecko"` | `"coingecko-cache"` — no third value for `caches.default`-served responses.
- **D-07:** Upstream failure (429/5xx/timeout) with usable DO cache → 200 + envelope, `stale: true`, `source: "coingecko-cache"`. Structured error only when nothing usable exists.
- **D-08:** Errors: 502 + `{ "error": { "code", "message", "upstreamStatus"? } }` for upstream failure with nothing usable; 400 malformed `ids`/`vs`; 404 unknown paths; 405 non-GET. Never a 500 crash.
- **D-09:** Partial id coverage: envelope `prices` includes only ids CoinGecko returned; no error, no `missing` field.
- **D-10:** `ctx.storage.sql` table: one row per id — `id TEXT PRIMARY KEY, price REAL, fetchedAt INTEGER`. Partial batches never clobber older rows.
- **D-11:** Timestamps per-id. Envelope `fetchedAt` = max(fetchedAt of returned ids), `age` = now − max, `stale: true` when ANY returned id >60s old.
- **D-12:** Freshness gates per FRESH-01: all requested ids ≤60s → serve from SQL, no refetch; refetch only ids >60s; 60s–5min rows served (flagged stale) only on upstream failure; >5min never served.

### Claude's Discretion
- npm script names beyond `dev`/`test`/`typecheck`; vitest test-file organization; `compatibility_date` value; error `code` string tokens; internal module split; single-flight implementation details; SQL row pruning policy (>5min: delete vs keep-unservable).

### Deferred Ideas (OUT OF SCOPE)
- None within this phase. Live deployment (DEPLOY-01), Queues, KV, client-side keys all excluded.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SRVC-01 | `GET /v1/prices?ids=<csv>&vs=<currency>` returns envelope with exact field semantics | Envelope type + builder pattern (KF-6); per-currency DO routing (KF-5) |
| SRVC-02 | DO `PriceCoordinator` per-currency single-flight — one upstream call per freshness window for concurrent overlapping id-sets | Batch-window coalescing pattern with input-gate-safe synchronous prologue (KF-4) |
| SRVC-03 | SQLite DO via `new_sqlite_classes`; state survives eviction in tests | `ctx.storage.sql` sync API (KF-5); `evictDurableObject` test API (KF-7) |
| SRVC-04 | `caches.default` read-through, sub-60s TTL, ahead of DO | Cache API fully functional in workerd test runtime with real HTTP-cache semantics (KF-3); canonical-key pattern |
| SRVC-05 | Upstream 429/5xx/timeout: stale-serve or structured error, never crash | MSW error mocks + JS-level AbortController timeout (KF-2, KF-8); hold-off pattern (Pitfalls) |
| SRVC-06 | Keyless clients; server-side-only key via `env.COINGECKO_API_KEY` | Env-override unit-test pattern (KF-9); secrets stay in `wrangler secret` / `.dev.vars` (KF-1) |
| SRVC-07 | No Queues, no KV anywhere in price path | Config-inspection test via `?raw` JSONC import (KF-10) |
| SRVC-08 | Malformed requests → 4xx JSON error | Validation module + table-driven tests (Implementation Notes 01-02) |
| TEST-01 | Hermetic vitest-plugin suite in workerd, real DO-SQLite + Cache API, CoinGecko mocked, coalescing proven by call counts | MSW `setupNetwork` official pattern (KF-2); fake-timers coalescing test (KF-6); fail-closed egress canary (KF-11) |
| FRESH-01 | Envelope band semantics: ≤60s fresh / 60s–5min stale / >5min unavailable | `vi.useFakeTimers` + `vi.setSystemTime` work in workerd (KF-8); band constants exported for tests |
</phase_requirements>

---

## Recommended Approach

A single self-contained npm project at `SuperGenius/pricecoordinator/` with 5 source files (`index.ts` router, `coordinator.ts` DO class, `envelope.ts` types/bands, `upstream.ts` CoinGecko client, `validate.ts` request parsing), configured by one `wrangler.jsonc` (SQLite DO migration, no Queues/KV bindings, no secrets inline) and tested by a vitest suite that runs inside workerd via `cloudflareTest({ wrangler: { configPath } })`. CoinGecko is mocked with `@msw/cloudflare`'s `setupNetwork()` — Cloudflare's own 2026 fixture pattern — with a **fail-closed egress guard** so unmatched outbound fetches throw rather than silently egress. Coalescing is proven deterministically by fake-timer-driven upstream call counts, not wall-clock timing.

**Primary recommendation:** Build the DO around a **synchronous SQL prologue + joinable batch window**: `ctx.storage.sql` reads are synchronous, so each DO `fetch()` can check freshness, serve fresh, or register into an in-flight batch **before its first `await`** — which the DO input-gate model makes atomic — then one debounced upstream call covers the union of all ids registered during a ~15 ms window. Test eviction with `evictDurableObject()`, alarms with `runDurableObjectAlarm()`, staleness with `vi.useFakeTimers()`, and the config with a `wrangler.jsonc?raw` import test.

### Toolchain (verified against npm registry 2026-09-29 [VERIFIED: npm registry])

| Package | Pin | Verified version | Role |
|---------|-----|------------------|------|
| `wrangler` | `^4.144.0` | 4.144.0 (2026-09-29) | dev server, config schema; embeds miniflare 5.x + workerd |
| `@cloudflare/vitest-plugin` | `^1.3.3` | 1.3.3; peerDeps `vitest ^4.1.0`, deps `wrangler 4.144.0`, `miniflare 5.20260926.1-alpha` | runs tests inside workerd |
| `vitest` | `^4.1.0` — **pin 4.x, NOT 5.x** | 4.1.11 latest in `^4.1.0`; 5.0.2 latest overall (incompatible) | test runner |
| `@cloudflare/workers-types` | `^5.20260929.1` | 5.20260930.1 | runtime typings |
| `typescript` | `~5.9.0` — **NOT 7.x** | 7.0.2 is latest (Go port; toolchain not ready) | typecheck only (wrangler bundles via esbuild) |
| `msw` | `^3.0.0` | 3.0.0 | outbound fetch mocking (used by `@msw/cloudflare`) |
| `@msw/cloudflare` | `^0.2.0` | 0.2.0; peerDeps `msw >=3` | `setupNetwork()` — intercepts workerd `fetch` |

All dev-only; nothing ships to the production runtime. All seven have official source repos and **no postinstall scripts** [VERIFIED: npm registry].

---

## Validation Architecture

> `workflow.nyquist_validation` is `false` in `.planning/config.json`, but the orchestrator requested this section — it doubles as the success-criteria → test map the planner needs.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | vitest 4.1.x + `@cloudflare/vitest-plugin` 1.3.3, executing inside workerd (real DO SQLite + Cache API) |
| Config file | `vitest.config.ts` (`cloudflareTest({ wrangler: { configPath: "./wrangler.jsonc" } })`) |
| Quick run command | `npm run test` (≈ seconds; fully hermetic) |
| Full suite command | `npm ci && npm run typecheck && npm run test` (the phase's success criterion 4) |

### Success Criteria → Test Map
| # | Success criterion | How tested | Test file (plan 01-05 unless noted) |
|---|-------------------|------------|-------------------------------------|
| 1 | Envelope fields correct for fresh / stale-usable / unavailable | Fake-clock band tests: set system time, seed SQL rows at known `fetchedAt`, assert `{currency, prices, fetchedAt, age, source, stale}` per band | `envelope.freshness.test.ts` |
| 2 | Concurrent overlapping id-sets → exactly 1 upstream call; subsets returned | Two un-awaited `SELF.fetch()` calls + `vi.advanceTimersByTimeAsync(BATCH_WINDOW)`; assert MSW handler invocation count === 1; assert each response's `prices` keys equal its requested subset | `coordinator.coalescing.test.ts` |
| 3 | Upstream 429/5xx/timeout → stale envelope or structured JSON error, never 500 | MSW handlers returning 429/500/HTML-403; hang-gate mock for timeout (JS `AbortController` + fake timers). Assert 200-stale when cache usable; 502 `{error:{code,message,upstreamStatus}}` when not | `coordinator.upstream-failure.test.ts` |
| 4 | `npm ci && typecheck && test` green, zero egress | MSW covers all upstream calls; fail-closed canary test asserts unmocked fetch throws; `npm run typecheck` = `tsc --noEmit` over src + test projects | `hermeticity.test.ts` + CI gate |
| 5 | `new_sqlite_classes` migration; state survives eviction; no Queues/KV in config | (a) `config.test.ts` imports `wrangler.jsonc?raw`, parses JSONC, asserts migration tag + absence of `new_classes`/Queues/KV bindings; (b) `evictDurableObject(stub)` then re-fetch → prices survive | `config.test.ts`, `coordinator.eviction.test.ts` |

### Requirement coverage beyond the criteria
- **SRVC-08**: table-driven 400 tests (missing/empty `ids`, >MAX_IDS, invalid `vs` chars, unknown path → 404, POST → 405) — `router.validation.test.ts`
- **SRVC-04**: `cache.match` hit after `cache.put` round-trip; canonical-key test (permuted id order hits same entry); `Cache-Control: public, max-age=45` header assertion — `cache.test.ts`. Negative test: response without `Cache-Control` is **not** stored (workerd enforces real HTTP-cache rules — see KF-3)
- **SRVC-06**: keyed path via unit-style `worker.fetch(request, {...env, COINGECKO_API_KEY: "k"}, ctx)` — assert mock saw `x-cg-demo-api-key`; assert no response body ever contains the key — `key.test.ts`
- **TEST-01**: the whole suite is the deliverable; call-count assertions are the coalescing proof
- **FRESH-01**: band boundaries at 60s and 300s asserted exactly (59s fresh / 61s stale-flagged / 301s unservable)

### Sampling Rate
- **Per task commit:** `npm run test` (hermetic, fast)
- **Phase gate:** `npm ci && npm run typecheck && npm run test` green before `/gsd-verify-work`

### Wave 0 Gaps
None — greenfield; test infrastructure is itself deliverable of plans 01-01/01-05.

---

## Key Findings

Numbered per the orchestrator's research focus. Provenance: `[VERIFIED: …]` confirmed via tool this session against an authoritative source; `[CITED: …]` from official docs; `[ASSUMED]` training knowledge flagged for confirmation.

### KF-1: Minimal `wrangler.jsonc` — exact shape [VERIFIED: cloudflare/workers-sdk fixture `fixtures/vitest-plugin-examples/durable-objects/wrangler.jsonc`]

```jsonc
{
  "$schema": "node_modules/wrangler/config-schema.json",
  "name": "price-coordinator",
  "main": "src/index.ts",
  "compatibility_date": "2026-09-01",
  "durable_objects": {
    "bindings": [
      { "name": "PRICE_COORDINATOR", "class_name": "PriceCoordinator" }
    ]
  },
  "migrations": [
    { "tag": "v1", "new_sqlite_classes": ["PriceCoordinator"] }
  ]
}
```

- The fixture proves this exact skeleton (bindings + `new_sqlite_classes`) loads in vitest-plugin. Cloudflare's own fixture omits `compatibility_date` so vitest infers the latest; STACK.md's pinned `2026-09-01` also works and is what CI/dev will use — either is fine, pin it explicitly [CITED: developers.cloudflare.com/workers/testing/vitest-integration/configuration — wrangler options are merged, miniflare overrides take precedence].
- **Secrets (D-04):** secrets NEVER appear in `wrangler.jsonc`. Deployed: `npx wrangler secret put COINGECKO_API_KEY`. Local dev: a `.dev.vars` file (dotenv syntax, gitignored) read automatically by `wrangler dev` [CITED: developers.cloudflare.com/workers/configuration/secrets — "Put secrets for use in local development in either a `.dev.vars` file or a `.env` file… Do not commit… add `.dev.vars*` and `.env*` to `.gitignore`"]. Because the key is **optional**, do NOT use the `secrets.required` config property (it fails deploys on missing secrets). The Worker reads `env.COINGECKO_API_KEY` and treats `undefined` as anonymous.
- Migrations are append-only once applied anywhere; since deployment is deferred, the config-inspection test (KF-10) is the permanent guard [CITED: PITFALLS.md Pitfall 3].

### KF-2: Hermetic upstream mocking — `@msw/cloudflare` `setupNetwork()` is the official 2026 pattern [VERIFIED: cloudflare/workers-sdk fixtures `request-mocking/{vitest.config.ts,test/setup.ts,test/server.ts,test/direct.test.ts,test/exports.test.ts}`]

```ts
// test/server.ts
import { setupNetwork } from "@msw/cloudflare";
export const network = setupNetwork();

// test/setup.ts  (registered via vitest.config.ts `test.setupFiles`)
import { afterAll, afterEach, beforeAll } from "vitest";
import { network } from "./server";
beforeAll(() => network.enable());
afterEach(() => network.resetHandlers());
afterAll(() => network.disable());

// test/coordinator.coalescing.test.ts — call-count capture
import { http, HttpResponse } from "msw";
let upstreamCalls = 0;
beforeEach(() => {
  upstreamCalls = 0;
  network.use(
    http.get("https://api.coingecko.com/api/v3/simple/price", () => {
      upstreamCalls++;                                   // the coalescing proof
      return HttpResponse.json({ bitcoin: { usd: 61234.12 } });
    })
  );
});
```

- Verified properties: MSW intercepts the worker's outbound `fetch` inside workerd for **both** invocation styles — unit (`worker.fetch(request, env, ctx)`) and integration (`exports.default.fetch(...)` / `SELF.fetch(...)`) — Cloudflare's fixture demonstrates both, including a comment noting `exports.default.fetch` dispatches into a fresh request I/O context while mocks still apply [VERIFIED: fixture `exports.test.ts`].
- The legacy `fetchMock` (undici `MockAgent` re-export) **still exists** — `import { env, fetchMock, SELF } from "cloudflare:test"` per the package's own AGENTS.md [VERIFIED: cloudflare/workers-sdk `packages/vitest-plugin/AGENTS.md`] — but no current docs guide exists for it and the official recipe list points at MSW. **Use MSW as primary.**
- **Fail-closed egress (hermeticity guarantee):** belt-and-braces beyond MSW:
  1. Try `setupNetwork({ onUnhandledRequest: "error" })` [ASSUMED — the option is standard in msw's server/worker APIs but was not verified for `setupNetwork`; confirm at implementation].
  2. Regardless, add a `miniflare.outboundService(request)` handler in `vitest.config.ts` that **throws** for any URL other than the mocked CoinGecko origin — `outboundService` intercepts ALL outbound `fetch`/`connect` from the worker under test [VERIFIED: miniflare README `WorkerOptions.outboundService`; used in workers-sdk fixture `vitest-plugin-examples/misc/vitest.config.ts`]. This is the strongest fail-closed primitive: nothing leaves workerd without passing through it.
  3. Canary test: an unmocked fetch to `api.coingecko.com/other-path` must throw.

### KF-3: `caches.default` IS fully testable in vitest-plugin — no abstraction needed for plan 01-04 [VERIFIED]

This was research question #1 and the answer is definitive:

- The Cache API is **enabled by default** in the workerd test runtime; miniflare's `cacheAPI?: boolean` option exists only to *disable* it ("If `false`, default and named caches will be disabled. The Cache API will still be available, it just won't cache anything") [VERIFIED: miniflare README `WorkerOptions.cacheAPI`].
- workers-sdk's own vitest-plugin test suite exercises `caches.default.put/match` inside a workerd test [VERIFIED: `packages/vitest-plugin/test/validation.test.ts`], and the `kv-r2-caches` fixture tests worker code doing `caches.default.match(request)` / `ctx.waitUntil(caches.default.put(request, response.clone()))` [VERIFIED: fixture `src/helpers.ts`] — exactly our read-through shape.
- The local cache implements **real Cloudflare HTTP-cache semantics**, not a naive map [VERIFIED: `packages/miniflare/src/workers/cache/cache.worker.ts` + its test suite]:
  - `put` **silently no-ops** (resolves fine) for responses with `Cache-Control: private`, `no-store`, `no-cache`, or any `Set-Cookie` — so a missing/uncacheable `Cache-Control` header means "never cached", and the round-trip hit test doubles as a permanent regression guard (PITFALLS Pitfall 4).
  - Expiration honors `max-age`, `s-maxage` (s-maxage wins), and `Expires`.
  - Cache key = full URL (query string included) → canonicalization mandatory (see Landmines).
- **TTL-expiry caveat:** miniflare's cache computes expiry with its internal timer abstraction (`this.timers.now()`), which vitest fake timers do **not** control [VERIFIED: `cache.worker.ts` uses `MiniflareDurableObject`/`Timers` from `miniflare:shared`]. So do NOT test "cache entry expires at 45s" with `vi.advanceTimersByTime`. Instead: assert the `Cache-Control: public, max-age=45` header value on served responses + the put→match hit + miss-on-different-key. TTL correctness follows from construction.
- Per-colo semantics are inherently untestable locally (miniflare has one "colo") — acceptable; SRVC-04's testable content is the read-through ordering and key canonicalization.

**Recommended pattern (plan 01-04):**

```ts
// src/index.ts — canonical key + read-through
const cacheKey = new URL("https://token.gnus.ai/v1/prices");
cacheKey.searchParams.set("ids", [...ids].sort().join(",")); // sorted + deduped
cacheKey.searchParams.set("vs", currency);

let response = await caches.default.match(cacheKey.toString());
if (response) return response;                    // per-colo hit; DO untouched

response = await env.PRICE_COORDINATOR
  .get(env.PRICE_COORDINATOR.idFromName(currency)).fetch(doRequest);
if (response.ok) {
  response = new Response(response.body, response); // clone-able re-wrap if needed
  response.headers.set("Cache-Control", "public, max-age=45");
  ctx.waitUntil(caches.default.put(cacheKey.toString(), response.clone()));
}
return response;
```

Only 200 envelopes enter the cache (error responses are never cached — Pitfall 14, cached-error poisoning). Because 45s < 60s freshness, a cache hit is always in the fresh band — the cache tier can never serve stale, which keeps D-06's two-value `source` honest.

### KF-4: Single-flight coalescing inside the DO — synchronous prologue + joinable batch window [CITED + VERIFIED APIs; pattern derived]

This was research question #2. Two facts drive the design:

1. **`ctx.storage.sql` is synchronous.** Unlike the async KV-style `storage.get/put`, `sql.exec()` returns a `SqlStorageCursor` synchronously [CITED: developers.cloudflare.com/durable-objects/api/sql-api — `SqlStorage.exec(query, ...params)`]. So the freshness check reads SQL **without awaiting**, keeping the request prologue atomic.
2. **DO events run one-at-a-time up to the first non-storage await; an outbound `fetch` does NOT hold the input gate** [CITED: developers.cloudflare.com/durable-objects/reference/incoming-events/ + PITFALLS Pitfall 1]. Therefore any check-then-register sequence performed entirely before the first `await` is race-free — and anything populated after an `await` is not.

**"Exactly one upstream call" for overlapping id-sets** (success criterion 2) requires a *union batch*: once `fetch()` is in flight you cannot add ids to it. So the first request opens a short **collecting window**; requests arriving during it join the batch (union ids + register waiter); when the window closes, ONE upstream call fetches the union and every waiter receives its subset. Requests arriving while the batch is *in flight* start a new collecting batch (bounded transient overlap of ≤2 calls — never within the tested window).

```ts
// src/coordinator.ts — the core shape (details are plan 01-03's to finalize)
import { DurableObject } from "cloudflare:workers";
import { FRESH_MS, BATCH_WINDOW_MS, MAX_IDS_PER_BATCH } from "./envelope";

interface Waiter { ids: string[]; resolve: (rows: Map<string, Row>) => void;
                   reject: (e: unknown) => void; }

export class PriceCoordinator extends DurableObject {
  private collecting: { ids: Set<string>; waiters: Waiter[] } | null = null;
  private inflight = false;
  private holdOffUntil = 0;                      // upstream 429/403 back-pressure

  async fetch(request: Request): Promise<Response> {
    // --- SYNCHRONOUS PROLOGUE: no await ⇒ atomic under input gates ---
    const { ids, currency } = parsePricesRequest(request);      // throws 400-shape errors
    const now = Math.floor(Date.now() / 1000);
    const rows = readRows(this.ctx.storage.sql, ids);           // sync SQL read
    const needed = ids.filter((id) => !rows.has(id) || now - rows.get(id)!.fetchedAt > FRESH_MS);

    if (needed.length === 0) {
      return envelopeFromRows(currency, rows, ids, now);        // fresh: no upstream, no join
    }
    if (Date.now() < this.holdOffUntil || this.inflight) {
      // cannot join an in-flight fetch; open/join a NEW collecting batch
    }
    this.collecting ??= { ids: new Set(), waiters: [] };
    if (this.collecting.ids.size + needed.length > MAX_IDS_PER_BATCH) { /* flush later batch */ }
    for (const id of needed) this.collecting.ids.add(id);
    const waiter = new Promise<Map<string, Row>>((resolve, reject) =>
      this.collecting!.waiters.push({ ids: needed, resolve, reject }));
    this.scheduleFlush();                       // setTimeout(flush, BATCH_WINDOW_MS) — idempotent
    // --- END PROLOGUE (first await is below) ---
    const merged = new Map([...rows, ...(await waiter)]);
    return envelopeFromRows(currency, merged, ids, now);
  }

  private scheduleFlush() {
    if (this.flushTimer) return;
    this.flushTimer = setTimeout(() => { this.flushTimer = undefined; void this.flush(); },
                                 BATCH_WINDOW_MS);
  }

  private async flush() {
    const batch = this.collecting; this.collecting = null; this.inflight = true;
    try {
      const fresh = await fetchUpstream([...batch.ids], this.env);   // MSW-intercepted in tests
      persistRows(this.ctx.storage.sql, fresh);   // INSERT OR REPLACE per id — partial-safe (D-10)
      for (const w of batch.waiters) w.resolve(pick(fresh, w.ids));
    } catch (e) {
      for (const w of batch.waiters) w.reject(e); // reject ⇒ callers fall to stale/error path
    } finally { this.inflight = false; }
  }
}
```

Key rules encoded above (each traces to a PITFALLS.md item):
- Batch/waiter registration happens **before any `await`** (Pitfall 1a).
- Waiters are rejected on upstream failure and the pending entry is cleared in `finally` — no permanently-poisoned map (Pitfall 1b); rejection triggers the D-07 stale-serve path in the caller.
- Rows persist to SQL **inside `flush()` before waiters resolve** — data is durable before any client sees it (Pitfall 2).
- `setTimeout` (not `setInterval`, not an alarm) drives the window; alarms are too coarse (second-granularity) for a 15 ms window. An optional `alarm()` refinement (pre-seeding hot ids / pruning) can use `runDurableObjectAlarm(stub)` in tests [VERIFIED: cloudflare:test API].
- The `DurableObject` base class from `cloudflare:workers` (not the bare-class style) is the current fixture pattern; `this.ctx`/`this.env` come from `super(ctx, env)` [VERIFIED: fixture `durable-objects/src/index.ts`].

**How call-count assertions should be structured (TEST-01):**

```ts
it("coalesces concurrent overlapping id-sets into one upstream call", async ({ expect }) => {
  vi.useFakeTimers();
  // (real timers restored in afterEach)
  const p1 = SELF.fetch("https://token.gnus.ai/v1/prices?ids=bitcoin,ethereum&vs=usd");
  const p2 = SELF.fetch("https://token.gnus.ai/v1/prices?ids=bitcoin,solana&vs=usd");
  await vi.advanceTimersByTimeAsync(BATCH_WINDOW_MS + 5);   // fire + settle the batch
  const [r1, r2] = await Promise.all([p1, p2]);
  expect(upstreamCalls).toBe(1);                            // THE assertion
  const b1 = await r1.json(), b2 = await r2.json();
  expect(Object.keys(b1.prices).sort()).toEqual(["bitcoin", "ethereum"]);
  expect(Object.keys(b2.prices).sort()).toEqual(["bitcoin", "solana"]);
});
```

Firing both requests **un-awaited** then advancing fake time is deterministic — no sleeps, no scheduling jitter (PITFALLS Pitfall 19). The mocked handler's closure counter is the proof; per-test-file storage isolation makes cross-test leakage a non-issue within a file only if `reset()` runs (see KF-8).

### KF-5: SQLite DO storage — schema + sync access [CITED]

```sql
CREATE TABLE IF NOT EXISTS prices (
  id        TEXT PRIMARY KEY,
  price     REAL NOT NULL,
  fetchedAt INTEGER NOT NULL          -- epoch SECONDS (D-11; seconds, never ms)
);
```

- Initialize via `ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS …")` in the constructor (or lazily in `readRows`) — D1-style migration files do not apply to DO SQL.
- Write path: `INSERT OR REPLACE INTO prices (id, price, fetchedAt) VALUES (?, ?, ?)` per returned id — a partial CoinGecko response only touches returned ids, preserving older rows (D-10).
- Read path: `SELECT id, price, fetchedAt FROM prices WHERE id IN (…)` — `exec` is synchronous; results iterate via `for (const row of cursor)` / `.toArray()` [CITED: SQL API docs]. Exact cursor helper names to confirm during implementation [ASSUMED: `.toArray()`].
- Pruning (discretion): simplest is a `DELETE FROM prices WHERE fetchedAt < ?` piggy-backed on each successful `flush()` (>5 min rows are unservable anyway per D-12, so deleting them changes no behavior and bounds storage).
- `new_sqlite_classes` (not `new_classes`) is both the Free-plan requirement and what makes `ctx.storage.sql` available; KV-backed DOs are paid-only [CITED: STACK.md; PITFALLS Pitfall 3].

### KF-6: Fake timers work inside workerd — the freshness-band lever [VERIFIED: fixture `vitest-plugin-examples/misc/test/fake-timers.test.ts`]

```ts
beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

it("fake system time", () => {
  vi.setSystemTime(new Date(2023, 0, 1));
  expect(new Date()).toMatchInlineSnapshot(`2023-01-01T00:00:00.000Z`);
});
it("advances fake time", () => {
  const fn = vi.fn(); setTimeout(fn, 1000);
  vi.advanceTimersByTime(500); expect(fn).not.toHaveBeenCalled();
  vi.advanceTimersByTime(500); expect(fn).toHaveBeenCalled();
});
```

This is Cloudflare's own fixture, verbatim — so all three FRESH-01 band tests (59s/61s/301s), the batch window, and the upstream timeout are clock-injectable with **zero real waiting**. Caveats:
- Use `advanceTimersByTimeAsync` (not the sync variant) when promises must settle mid-advance.
- As noted in KF-3, miniflare-internal timers (cache TTL) are NOT fake-timer-controlled — keep cache tests to hit/miss/header assertions.
- Export the band/window constants from `envelope.ts` so tests import the same numbers the code uses (`FRESH_MS`, `STALE_MS`, `BATCH_WINDOW_MS`, `UPSTREAM_TIMEOUT_MS`) — no magic numbers duplicated in tests.

### KF-7: DO eviction/hibernation IS directly testable — `evictDurableObject` exists [VERIFIED: developers.cloudflare.com/workers/testing/vitest-integration/test-apis/ (page updated 2026-09-28)]

Research question #3, answered from the official Test APIs reference:

| API | Purpose |
|-----|---------|
| `evictDurableObject(stub, opts?)` | Gracefully tears down the running DO instance — "reset in-memory state… eviction waits up to 30 seconds for in-flight requests to drain" — **durable storage preserved**. Exactly success criterion 5. |
| `evictAllDurableObjects(opts?)` | Same, all running DOs |
| `abortAllDurableObjects()` | Forcible teardown, discards memory, does NOT delete persisted data |
| `runDurableObjectAlarm(stub)` | Runs + clears a scheduled alarm immediately; returns whether one ran |
| `runInDurableObject(stub, cb)` | Runs a callback *inside* the DO instance — seed/spy on instance state |
| `listDurableObjectIds(ns)` | IDs created in the namespace — "Respects per-file storage isolation" |
| `reset()` | "Deletes all data from all attached bindings" — between-tests reset within a file |

The docs' own eviction test is precisely our criterion-5 shape:

```ts
it("preserves stored data across eviction", async () => {
  const stub = env.PRICE_COORDINATOR.get(env.PRICE_COORDINATOR.idFromName("USD"));
  await SELF.fetch("…/v1/prices?ids=bitcoin&vs=usd");           // populates SQL
  await evictDurableObject(stub);                                // memory torn down
  const res = await SELF.fetch("…/v1/prices?ids=bitcoin&vs=usd");
  const body = await res.json();
  expect(body.prices.bitcoin).toBe(61234.12);                    // survived — from SQL
  expect(upstreamCalls).toBe(1);                                 // no refetch needed? see note
});
```

Note: post-eviction, a fetch within the freshness window must serve from SQL (0 additional upstream calls); advance fake time past 60s first if you want to prove the *refetch* path instead. `runInDurableObject` is also handy to seed SQL rows with back-dated `fetchedAt` directly (avoids fake-clock contortions in stale-band tests).

### KF-8: Per-test isolation — per-FILE by default; `reset()` for within-file [CITED + VERIFIED APIs]

Research question #7. The plugin "Implements isolated per-test-file storage" [VERIFIED: vitest-integration index]. Consequences:

- Each test **file** gets a fresh workerd context (DO storage, KV, caches) — no cross-file contamination, and `listDurableObjectIds` confirms files can't see each other's objects.
- Within a file, tests **share** storage — so add to the file-level setup:

```ts
afterEach(async () => {
  await reset();                    // wipe persisted binding data (DO SQL rows)
  await abortAllDurableObjects();   // wipe DO in-memory state (pending batch, hold-off, timers)
  network.resetHandlers();          // MSW handlers
  vi.useRealTimers();
});
```

  (`reset()` from `cloudflare:test`; `abortAllDurableObjects()` chosen over `evictAllDurableObjects()` in afterEach because eviction waits up to 30s for drains while abort is immediate; use the gentle `evictDurableObject` only in the dedicated eviction test.) Whether `reset()` clears `caches.default` in addition to bindings is not explicitly documented [ASSUMED: it does, since cache state is part of the per-file storage context] — belt-and-braces: use test-unique id sets so cache keys never collide across tests.
- Belt-and-braces regardless: unique cache keys/DO id-sets per test where overlap could mask a bug (PITFALLS Pitfall 19).

### KF-9: Keyed-path testing via env spread (D-04/SRVC-06) [VERIFIED: workers-sdk fixture `ai-vectorize/test/index.spec.ts` pattern]

```ts
it("sends x-cg-demo-api-key when the secret is set", async ({ expect }) => {
  let seenHeader: string | null = null;
  network.use(http.get("https://api.coingecko.com/api/v3/simple/price", ({ request }) => {
    seenHeader = request.headers.get("x-cg-demo-api-key");
    return HttpResponse.json({ bitcoin: { usd: 1 } });
  }));
  const testEnv = { ...env, COINGECKO_API_KEY: "test-key-123" };   // unit-style env override
  const ctx = createExecutionContext();
  const res = await worker.fetch(new IncomingRequest(
    "https://token.gnus.ai/v1/prices?ids=bitcoin&vs=usd"), testEnv, ctx);
  await waitOnExecutionContext(ctx);
  expect(seenHeader).toBe("test-key-123");
  expect(await res.text()).not.toContain("test-key-123");           // SRVC-06: never echoed
});
```

The anonymous path is the default (no binding in `wrangler.jsonc`; no `.dev.vars` in test env). Assert `seenHeader === null` there. 502 error bodies containing `upstreamStatus` must also be checked against key leakage.

### KF-10: Config-inspection test (SRVC-07 + Free-plan guard) via `?raw` import

Tests execute in workerd (no `fs`), but they pass through Vite transforms, and Vite's `?raw` suffix imports any file as a string [CITED: vite.dev guide/assets#explicit-import]. So:

```ts
// test/config.test.ts
import wranglerRaw from "../wrangler.jsonc?raw";
import { it, expect } from "vitest";

function parseJsonc(text: string): unknown { /* strip // and /* */ comments, JSON.parse */ }

it("uses SQLite-backed DO migrations (Free plan)", () => {
  const cfg = parseJsonc(wranglerRaw) as any;
  expect(cfg.migrations.some((m: any) => m.new_sqlite_classes?.includes("PriceCoordinator"))).toBe(true);
  expect(JSON.stringify(cfg.migrations)).not.toContain("new_classes\":[");   // no KV-backed
});
it("has no Queues or KV bindings (SRVC-07)", () => {
  const cfg = parseJsonc(wranglerRaw) as any;
  expect(cfg.queues).toBeUndefined();
  expect(cfg.kv_namespaces).toBeUndefined();
  expect(JSON.stringify(cfg.durable_objects?.bindings ?? [])).not.toMatch(/queue|kv/i);
});
it("never inlines secrets (D-04)", () => {
  expect(wranglerRaw).not.toContain("COINGECKO_API_KEY");
});
```

Fallback if `?raw` misbehaves with `.jsonc` extension resolution: a tiny `scripts/check-config.mjs` run as an extra npm script (`node:fs` available there) [ASSUMED that `?raw` works under the plugin's Vite pipeline — high likelihood since `main` and tests are documented as Vite-transformed; verify in plan 01-05 wave 0].

### KF-11: Upstream timeout must be JS-level for fake-timer control

`AbortSignal.timeout()` in workerd is implemented natively and is **not** driven by vitest fake timers [ASSUMED — native timer plumbing; not verified]. Implement the timeout explicitly so tests control it:

```ts
const ctrl = new AbortController();
const t = setTimeout(() => ctrl.abort(new Error("upstream timeout")), UPSTREAM_TIMEOUT_MS);
try { return await fetch(url, { ...init, signal: ctrl.signal }); }
finally { clearTimeout(t); }
```

A "timeout" test then needs no real delay: register an MSW handler whose response is gated on a test-controlled promise (never resolving), shrink nothing, `advanceTimersByTimeAsync(UPSTREAM_TIMEOUT_MS + 1)`, assert the D-07/D-08 behavior. Rejected/aborted fetches must reject waiters (flush catch) — never hang (Pitfall 1b).

### KF-12: `SELF` vs `exports.default` vs direct `worker.fetch` — all three live [VERIFIED: plugin source `src/worker/lib/cloudflare/test.ts` exports `env, SELF, runInDurableObject, …`; docs Test APIs; fixtures]

| Style | Import | Use for |
|-------|--------|---------|
| Unit | `import worker from "../src/index"` + `worker.fetch(req, env, ctx)` | Router validation tests, keyed-env override (env spread), cache-off paths |
| Integration (legacy) | `SELF` from `cloudflare:test` | Coalescing/eviction tests through the full worker incl. `caches.default` |
| Integration (current) | `exports` from `cloudflare:workers` | Same as SELF; docs note it does not expose Assets — irrelevant here |

MSW mocks apply to all three [VERIFIED: request-mocking fixture covers unit + exports styles]. Use `SELF`/`exports` for anything that must traverse the cache tier; use unit style where env override is needed.

### KF-13: Project layout + scripts for `pricecoordinator/`

```
SuperGenius/pricecoordinator/
├── package.json
├── package-lock.json          # committed — npm ci requires it (success criterion 4)
├── wrangler.jsonc
├── tsconfig.json              # src project
├── vitest.config.ts
├── .gitignore                 # node_modules/, .wrangler/, .dev.vars*, *.log
├── src/
│   ├── index.ts               # fetch handler: validate → cache → DO (SRVC-01/04/08)
│   ├── coordinator.ts         # PriceCoordinator DO (SRVC-02/03/05)
│   ├── envelope.ts            # types, band constants, envelope builder (D-06..D-11, FRESH-01)
│   ├── upstream.ts            # CoinGecko URL builder, key header, JS-level timeout (D-04/05)
│   └── validate.ts            # ids/vs parsing + limits (SRVC-08)
└── test/
    ├── tsconfig.json          # types: ["@cloudflare/vitest-plugin/types"]
    ├── setup.ts               # MSW enable/reset/disable lifecycle
    ├── server.ts              # export const network = setupNetwork()
    ├── helpers.ts             # IncomingRequest alias, fetchPrices(), parseJsonc, counters
    ├── config.test.ts         # KF-10
    ├── router.validation.test.ts
    ├── envelope.freshness.test.ts
    ├── coordinator.coalescing.test.ts
    ├── coordinator.upstream-failure.test.ts
    ├── coordinator.eviction.test.ts
    ├── cache.test.ts
    ├── key.test.ts
    └── hermeticity.test.ts
```

```jsonc
// package.json — scripts (names beyond dev/test/typecheck are discretion)
{
  "private": true,
  "scripts": {
    "dev": "wrangler dev",
    "test": "vitest run",
    "typecheck": "tsc --noEmit -p tsconfig.json && tsc --noEmit -p test/tsconfig.json"
  },
  "devDependencies": {
    "@cloudflare/vitest-plugin": "^1.3.3",
    "@cloudflare/workers-types": "^5.20260929.1",
    "@msw/cloudflare": "^0.2.0",
    "msw": "^3.0.0",
    "typescript": "~5.9.0",
    "vitest": "^4.1.0",
    "wrangler": "^4.144.0"
  }
}
```

```ts
// vitest.config.ts
import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: {
        // Fail-closed egress guard: any outbound fetch not matching the mocked
        // CoinGecko origin throws instead of leaving workerd. (KF-2)
        outboundService(request) {
          return new Response(
            JSON.stringify({ error: { code: "egress_blocked",
              message: `unexpected outbound fetch in test: ${request.url}` } }),
            { status: 599 });
        },
      },
    }),
  ],
  test: { setupFiles: ["./test/setup.ts"] },
});
```

**Layering subtlety:** if `outboundService` intercepted everything, it would also intercept the CoinGecko fetches MSW is meant to mock. The expected layering — MSW patches the worker's own `fetch` global *inside* the isolate, so mocked requests are answered before ever descending to `outboundService`; only unmocked requests reach it [ASSUMED — layering inferred from MSW patching the global vs `outboundService` sitting beneath the worker; verify in plan 01-01/01-05 wave 0 with the canary test, and drop the guard to a canary-only assertion if interference appears]. The canary test (unmocked path → error) settles this empirically on day one.

`test/tsconfig.json` per docs [CITED: write-your-first-test]:

```jsonc
{
  "extends": "../tsconfig.json",
  "compilerOptions": {
    "moduleResolution": "bundler",
    "types": ["@cloudflare/vitest-plugin/types"]
  },
  "include": ["./**/*.ts", "../src/**/*.ts"]
}
```

Root `tsconfig.json`: `"module": "esnext"`, `"moduleResolution": "bundler"`, `"types": ["@cloudflare/workers-types"]`, `"strict": true`, `"noEmit": true`, `"include": ["src/**/*.ts"]`, `"lib": ["esnext"]`. Either hand-written `Env` (`interface Env { PRICE_COORDINATOR: DurableObjectNamespace; COINGECKO_API_KEY?: string }`) or `wrangler types` output — hand-written is simpler for one service (STACK.md concurs).

### KF-14: Modern DO class style + `idFromName` per currency

```ts
import { DurableObject } from "cloudflare:workers";

export class PriceCoordinator extends DurableObject {
  constructor(ctx: DurableObjectState, env: Env) { super(ctx, env); }
  // ...
}
```

[VERIFIED: durable-objects fixture uses `class Counter extends DurableObject` with `this.ctx.storage`.] The Worker routes: `env.PRICE_COORDINATOR.get(env.PRICE_COORDINATOR.idFromName(currency.toUpperCase())).fetch(…)` — one instance per currency (D-05: currency is not a key axis; the key header is applied in `upstream.ts` identically everywhere).

### KF-15: 2026-era breaking changes checklist (vs PITFALLS.md)

| Change | Status | Impact here |
|--------|--------|-------------|
| `@cloudflare/vitest-pool-workers` → `@cloudflare/vitest-plugin` (renamed, v1) | Confirmed — plugin 1.3.3 is current; codemod exists for legacy code | New project starts on the plugin; never install the old package |
| vitest pinned to `^4.1.0` (5.0.x exists, incompatible) | Confirmed via peerDeps | Hard pin in package.json; do not `npm update` past 4.x |
| TypeScript 7 (Go port) is `latest`; toolchain on 5.x | Confirmed (7.0.2 latest) | `~5.9.0` tilde pin |
| `evictDurableObject` / `evictAllDurableObjects` / `abortAllDurableObjects` test APIs | New since old pool-workers docs | Eviction testing is first-class (KF-7) |
| `exports` from `cloudflare:workers` (successor to `SELF`-only) | Present; `SELF` still exported | Either works; use `SELF` for cache-traversing integration tests |
| DO base class `DurableObject` from `cloudflare:workers` | Current fixture style | Use it (KF-14) |
| MSW-based request mocking is the documented recipe (`@msw/cloudflare`) | Official fixture | Primary mocking strategy (KF-2) |
| `cacheAPI` miniflare option (and deprecated `cache` option it supersedes) | Present in plugin's own tests | Leave enabled (default); do not set it |

---

## Landmines & Pitfalls

Phase-1-specific. Cross-referenced to PITFALLS.md (P#) which remains canonical.

1. **Single-flight map populated after first `await` (P1).** The DO interleaves across non-storage awaits. Register into `collecting` in the synchronous prologue only. Test with genuinely concurrent un-awaited requests — sequential awaits in tests hide the bug.
2. **Leaked rejected waiters (P1b).** Reject waiters and clear batch state in `finally`; a poisoned pending entry freezes the DO until eviction.
3. **In-memory-only state (P2).** Persist rows inside `flush()` before resolving waiters. Eviction test (KF-7) is the guard.
4. **`new_classes` instead of `new_sqlite_classes` (P3).** Everything passes locally and dies at first real deploy. The config test (KF-10) makes it a permanent CI failure, plus guard against editing an applied migration tag later (append-only).
5. **Cache API silent no-store (P4).** `cache.put` resolves even when nothing was stored (missing `Cache-Control`, `private`/`no-store`/`no-cache`, `Set-Cookie`). Always set `Cache-Control: public, max-age=45` and keep the put→match round-trip test. Never set cookies on responses.
6. **Query-string cache-key fragmentation (P4).** `ids=btc,eth` ≠ `ids=eth,btc`. Canonicalize: dedupe → sort → join before both `match` and `put`.
7. **Secret egress in tests (P5).** Unmocked fetch passthrough is the default failure mode. Fail-closed: MSW covers all expected calls + `outboundService` guard (KF-2/KF-13) + canary test. The Phase 5 CI job inherits this property.
8. **Cached-error poisoning (P14).** Only 200-with-valid-shape envelopes enter `caches.default`; 429/5xx/timeout responses are never cached; DO stale-serving must not treat an absent id (CoinGecko 200-with-omission, D-09) as fetchable-within-window incorrectly — absent ids simply stay absent from `prices`.
9. **Upstream 429 re-triggering (P13).** After a 429/403, set `holdOffUntil = now + 60s` (in-memory; optional SQL persistence) so subsequent requests during hold-off go straight to stale/error without upstream calls — prevents the Worker amplifying a CoinGecko block from its own egress IP. Never retry 429/403 sub-minute. `Retry-After`/`x-ratelimit-*` will not arrive (diagnosis) — do not branch on them.
10. **Timestamps in ms (P15).** Envelope `fetchedAt` and SQL `fetchedAt` are epoch **seconds** (design reference: `1790719234`). Helper `nowSec()` in `envelope.ts` is the only place `Date.now()` is divided.
11. **Timing-based tests (P19).** No `sleep()` in tests; fake timers + call counts only. Also no reliance on cross-test-file state; within-file `reset()` + `abortAllDurableObjects()` (KF-8).
12. **Fake timers vs native/miniflare timers.** `vi.useFakeTimers` controls JS `setTimeout` (batch window, our AbortController timeout) but not `AbortSignal.timeout()` (native) nor miniflare cache TTL internals. Use the JS-level timeout pattern (KF-11); assert cache TTL by header, not by waiting (KF-3).
13. **`npm ci` without a committed lockfile.** Success criterion 4 requires `npm ci`; commit `package-lock.json`. Ensure `.gitignore` covers `node_modules/`, `.wrangler/`, `.dev.vars*` — SuperGenius' existing `.gitignore` has **no** `node_modules` entry (verified this session), so `pricecoordinator/.gitignore` must carry them (scoped to the subdirectory — least invasive to the submodule).
14. **Health-probe fallacy (P17, forward-looking).** Do not add any "is CoinGecko up" ping; `/ping` returns 200 while `/simple/price` 403s from the same IP. The DO's knowledge of upstream health = the last real request's status, nothing else.
15. **Body re-use in cache read-through.** `caches.default.put(key, response.clone())` then returning `response` — a Response body can be consumed once; clone before `put`, and never `put` an already-consumed response. Similarly re-wrap DO→client responses with fresh headers rather than mutating a used body.
16. **`reset()` in `afterEach` while fake timers active.** Reset storage after restoring real timers if `reset()` awaits internals sensitive to clock fakes [ASSUMED — order sensitivity unverified; simply calling `vi.useRealTimers()` first in afterEach avoids the question].

---

## Implementation Notes per Plan Seed

### 01-01 — Project scaffold
- Create exactly the layout in KF-13: `package.json` (pins from the verified table), `wrangler.jsonc` (KF-1), two tsconfigs, `vitest.config.ts` (KF-13), `.gitignore` (Landmine 13), `test/setup.ts` + `test/server.ts` (MSW lifecycle), a stub `src/index.ts` (`export default { fetch: () => new Response("ok") }`).
- Hello-world test: unit style (`worker.fetch` + `createExecutionContext`/`waitOnExecutionContext`) and one `SELF.fetch` integration — proves both invocation paths and the plugin wiring before any domain code.
- Also land the `outboundService` guard + hermeticity canary here (or in 01-05 if preferred) — earliest possible proof of zero egress. Resolve the MSW-vs-outboundService layering question (KF-13 note) in this plan's verification.
- Verify: `npm ci && npm run typecheck && npm run test` green from an empty cache dir.

### 01-02 — Router: validation + envelope + keyless surface (SRVC-01, SRVC-06, SRVC-08)
- `validate.ts`: parse `ids` (non-empty CSV, each id `[a-z0-9-]+`, dedupe, cap `MAX_IDS_PER_REQUEST` — recommend 50), `vs` (lowercase letters, recommend `[a-z]{2,10}`); return typed result or a 400 error descriptor. Route table: `GET /v1/prices` only; 404 with JSON error body for unknown paths; 405 for non-GET (D-08). Error `code` tokens (discretion): `invalid_request`, `not_found`, `method_not_allowed`, `upstream_error`, `egress_blocked` is test-only.
- `envelope.ts`: `PriceEnvelope` type, band constants (`FRESH_MS=60_000`→ seconds constants per D-12: 60/300), `nowSec()`, builder computing `fetchedAt=max(rows)`, `age`, `stale=any(id>60s)`, `source` per D-06 (see Open Question 1 for the fresh-from-SQL case).
- Stub the DO call as a not-implemented 501 so the router is testable standalone; table-driven validation tests + 404/405 tests here. Keyed/anonymous tests can stub the upstream too, but the full key coverage naturally lands in 01-05/`key.test.ts`.
- Cache tier deliberately NOT in this plan (01-04's job) — keep the DO call site a single function for 01-04 to wrap.

### 01-03 — `PriceCoordinator` DO (SRVC-02, SRVC-03, SRVC-05; D-10..D-12)
- Implement KF-4's shape: sync SQL prologue, joinable collecting batch, `setTimeout` flush window (recommend `BATCH_WINDOW_MS = 15`), `inflight` flag, per-id INSERT OR REPLACE (D-10), stale-serve on upstream failure with `holdOffUntil` 60s after 429/403 (Landmine 9), >5min rows never served (D-12) and pruned on flush (discretion, recommended).
- `upstream.ts`: builds `https://api.coingecko.com/api/v3/simple/price?ids=<sorted csv>&vs_currencies=<currency>`, attaches `x-cg-demo-api-key` iff `env.COINGECKO_API_KEY` set (D-04/D-05), JS-level AbortController timeout (KF-11, recommend 8000ms), sends no `Accept-Encoding` (forward-compat with the diagnosis; identity default), maps non-2xx → thrown typed error carrying `upstreamStatus`, checks status BEFORE JSON parse (never feed 403-HTML to JSON.parse — P10 discipline ported to the Worker side).
- Caller-side error handling in `coordinator.ts`: waiter rejection → if usable rows exist within 60s–5min → 200 stale envelope (D-07); else → the DO returns a structured 502 descriptor the Worker relays (D-08). Nothing throws out of `fetch()`.
- Tests (can land here or in 01-05): coalescing call-count (KF-4 snippet), partial-response non-clobbering (upstream returns subset; older row survives — D-10), 429/5xx/timeout matrix, hold-off (second request during hold-off makes no upstream call and serves stale), freshness bands incl. >5min-unservable.
- Optional (only if trivial): `alarm()` pruning + `runDurableObjectAlarm` test — do not let it expand scope; the debounced window does NOT use alarms.

### 01-04 — `caches.default` read-through (SRVC-04)
- Wrap 01-02's DO call site with KF-3's pattern: canonical key (sorted/deduped ids + vs), `match` before DO, `put` after 200-only with `Cache-Control: public, max-age=45`, `ctx.waitUntil` for the put. Only-fresh-invariant: 45s < 60s so cache never serves stale (supports D-06's two-value source).
- Tests: put→match round-trip hit; canonicalization (permuted/duped query hits same entry; different id-set misses); header assertion (`Cache-Control: public, max-age=45` present on DO-sourced 200s); error responses never cached (429 → next request still reaches DO); cache-off unit tests via direct `worker.fetch` where needed. Do NOT test TTL expiry via fake timers (KF-3 caveat).
- Also assert DO-request-count reduction if observable: with cache primed, second identical request makes zero upstream calls (counter unchanged) — the observable proxy for "bypasses the DO".

### 01-05 — Full hermetic suite + config inspection (TEST-01; SRVC-07 by inspection)
- Assemble the complete file set from KF-13; move/complete tests landed incrementally in 01-02..01-04; add `coordinator.eviction.test.ts` (KF-7), `config.test.ts` (KF-10), `hermeticity.test.ts` (canary: unmocked CoinGecko path must not egress — asserts the guard), `key.test.ts` (both paths + no-leak).
- Suite-wide `afterEach`: `vi.useRealTimers()` → `await reset()` → `await abortAllDurableObjects()` → `network.resetHandlers()` (KF-8).
- Final gate: `npm ci && npm run typecheck && npm run test` from clean — the phase's criterion 4. This is also the exact command set Phase 5's `worker-tests` job will run, so keep it single-command clean.

---

## Package Legitimacy Audit

slopcheck was installed and run, but it probes **PyPI**, where npm-scoped names legitimately do not exist — it emitted false `[SLOP]` verdicts for `@cloudflare/vitest-plugin`, `@msw/cloudflare`, `@cloudflare/workers-types` (cross-ecosystem confusion, the documented ~9% hallucination vector in reverse). Its run also pip-installed two unrelated PyPI junk packages (`wrangler` 0.1.8.6, `typescript` 0.0.12) which were uninstalled immediately after. Per protocol, since slopcheck could not validate the correct ecosystem, the npm verification below leans on `npm view` (registry existence, postinstall scripts, source repos) **plus** official Cloudflare documentation and first-party fixtures — which per the provenance rules is what confers confidence:

| Package | Registry | Age | Downloads | Source Repo | postinstall | Disposition |
|---------|----------|-----|-----------|-------------|-------------|-------------|
| wrangler | npm | ~5 yrs (4.x line) | Cloudflare first-party | github.com/cloudflare/workers-sdk | none | Approved [VERIFIED: npm registry + Cloudflare docs] |
| @cloudflare/vitest-plugin | npm | ~1 mo (v1 rename, Aug 2026) | Cloudflare first-party (successor of vitest-pool-workers) | github.com/cloudflare/workers-sdk | none | Approved [VERIFIED: npm registry + Cloudflare docs + fixtures] |
| vitest | npm | ~5 yrs | ecosystem standard | github.com/vitest-dev/vitest | none | Approved [VERIFIED: npm registry] |
| @cloudflare/workers-types | npm | ~5 yrs | Cloudflare first-party | github.com/cloudflare/workerd | none | Approved [VERIFIED: npm registry] |
| typescript | npm | 12+ yrs | Microsoft | github.com/microsoft/TypeScript | none | Approved [VERIFIED: npm registry] |
| msw | npm | ~6 yrs | 6M+/wk class | github.com/mswjs/msw | none | Approved [VERIFIED: npm registry + official CF fixture] |
| @msw/cloudflare | npm | ~1 yr (0.2.0) | new but mswjs first-party | github.com/mswjs/cloudflare | none | Approved [VERIFIED: npm registry + official CF request-mocking fixture] |

**Packages removed due to slopcheck [SLOP] verdict:** none (its three PyPI false-positives are npm packages verified above on npm).
**Packages flagged [SUS]:** none on npm. Note for the planner: `@msw/cloudflare` is young (0.x) — if the team prefers zero 0.x deps, the fallback is `fetchMock` from `cloudflare:test` (still exported, verified) or a `miniflare.outboundService`-based mock entirely within first-party tooling; MSW remains the recommended primary because it is Cloudflare's documented recipe.

---

## Runtime State Inventory

Not a rename/refactor/migration phase — greenfield addition. For completeness:
- **Stored data:** None — the DO SQL table is created at runtime by the new code; no existing records anywhere.
- **Live service config:** None — no deployment this phase (DEPLOY-01 deferred).
- **OS-registered state:** None.
- **Secrets/env vars:** `COINGECKO_API_KEY` is new, optional, and exists only as a future `wrangler secret` / local `.dev.vars` entry — never in git (gitignore it).
- **Build artifacts:** `pricecoordinator/node_modules/` and `.wrangler/` must be gitignored from day one (Landmine 13); no existing artifacts carry stale names.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Node.js ≥ 20 (recommend 22; local has newer) | wrangler/vitest execution | ✓ | v24.16.0 (verified this session) | — |
| npm | install/test lifecycle | ✓ | 11.15.0 | — |
| npm registry access | `npm ci` | ✓ (online dev machine) | — | — |
| workerd binary | test runtime | ✓ via npm (bundled in wrangler/miniflare) | 5.20260926.x | — |
| CoinGecko network access | **nothing** — suite is hermetic by design | not required | — | MSW mocks |
| Cloudflare account | nothing this phase (no deploy) | not required | — | — |

**Missing dependencies with no fallback:** none — everything needed installs from `package.json`. CI (Phase 5) will use `actions/setup-node@v4` with Node 22 per STACK.md.

---

## Security Domain

`security_enforcement: true`, ASVS level 1, block-on high. Surface is small: one public unauthenticated GET endpoint.

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | no | Public read-only price endpoint by design |
| V3 Session Management | no | No sessions |
| V4 Access Control | no | No privileged operations |
| V5 Input Validation | **yes** | `validate.ts` — allowlist regex for ids/vs, count caps (MAX_IDS_PER_REQUEST), reject before any upstream or cache interaction (SRVC-08); canonicalization before cache keys (Landmine 6) |
| V6 Cryptography | no | No crypto operations; TLS handled by platform |
| V14 Config | **yes** | Secrets only via `wrangler secret`/`.dev.vars` (D-04); config-inspection test asserts no secrets/Queues/KV inline (KF-10) |

| Threat pattern | STRIDE | Mitigation |
|----------------|--------|------------|
| API-key leakage into responses/logs | Information Disclosure | Key read only in `upstream.ts`; test asserts no response body contains it (KF-9); never in `wrangler.jsonc` (config test) |
| Cache poisoning via unvalidated query | Tampering | Strict `ids`/`vs` allowlists before any cache write; canonical sorted keys; only well-formed 200 envelopes cached (Landmine 8) |
| Amplification against upstream (DoS by proxy) | DoS | Single-flight coalescing + 60s hold-off after 429/403 (Landmine 9); batch size cap |
| Unbounded request size | DoS | `MAX_IDS_PER_REQUEST` cap + URL length inherently bounded by validation (SRVC-08) |
| SSRF-style abuse of the Worker as generic proxy | Tampering/SSRF | Router serves exactly one path; outbound fetches go only to the hard-coded CoinGecko base URL built from validated ids — never from caller-supplied URLs |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `setupNetwork({ onUnhandledRequest: "error" })` accepts the standard MSW option | KF-2 | Low — `outboundService` guard + canary test provide fail-closed regardless |
| A2 | MSW interception resolves before `outboundService` sees mocked requests (layering) | KF-13 | Medium — if inverted, mocks never fire; discovered on day one by the canary test; fallback is dropping the guard to canary-only or pure-`outboundService` mocking |
| A3 | `wrangler.jsonc?raw` Vite import works under the plugin's transform pipeline | KF-10 | Low — fallback is a Node-side `scripts/check-config.mjs` npm script |
| A4 | `AbortSignal.timeout()` is not fake-timer-controllable in workerd | KF-11 | Low — the JS-level AbortController pattern is used regardless, so no dependency on this |
| A5 | DO SQL cursor `.toArray()` helper name / exact iteration ergonomics | KF-5 | Low — `for (const row of cursor)` is the documented baseline; confirm in editor during 01-03 |
| A6 | `reset()` clears caches.default along with bindings | KF-8 | Low — unique-per-test cache keys are belt-and-braces |
| A7 | Batch window of ~15ms and MAX_IDS_PER_REQUEST=50 are sane | Implementation Notes | Low — both are exported constants, trivially tunable |

---

## Open Questions (RESOLVED)

1. **Envelope `source` for fresh-from-SQL serving — RESOLVED by user decision D-06a (2026-09-29), overturning the tier-based recommendation below.**
   - **Binding answer (D-06a):** `source` is **freshness-based**: any envelope whose returned ids are all ≤60s old reports `"coingecko"` — including fresh data the DO served from SQL without refetching. `"coingecko-cache"` appears **only** on stale-served-on-upstream-failure envelopes (ages 60s–5min, `stale: true`).
   - ~~Recommendation: **tier-based** — any envelope built from SQL rows is `"coingecko-cache"` (fresh: `stale:false`; upstream-failure stale: `stale:true` per D-07); `"coingecko"` is reserved for envelopes built from this cycle's live upstream response.~~ **Superseded — do NOT implement.** The user chose the provenance-based alternative: fresh-SQL → `"coingecko"`. All plans (01-02..01-05) and PATTERNS.md implement D-06a; executors must follow D-06a, not the struck-through recommendation.
2. **MSW vs `outboundService` layering (A2)** — RESOLVED empirically: settled by the 01-01/01-05 canary test; fallback path defined.
3. **Batch window size / caps (A7)** — RESOLVED as discretion per CONTEXT.md; recommended defaults given (~15ms window, MAX_IDS_PER_REQUEST=50); no user input needed unless desired.
4. **SQL row pruning policy** — RESOLVED as discretion (D-10 area); recommended delete-on-flush for >5min rows; alternative keep-but-unservable is behaviorally identical, just unbounded storage.

All questions resolved; Q1's binding answer is D-06a in 01-CONTEXT.md.

---

## Sources

### Primary (HIGH confidence)
- npm registry (verified 2026-09-29, via `npm view`): `@cloudflare/vitest-plugin` 1.3.3 (peerDeps + deps incl. wrangler 4.144.0 / miniflare 5.20260926.1-alpha), `wrangler` 4.144.0, `vitest` 4.1.x/5.0.2, `@cloudflare/workers-types` 5.20260930.1, `typescript` 7.0.2, `msw` 3.0.0, `@msw/cloudflare` 0.2.0 (peer msw ≥3) — all with source repos, none with postinstall scripts
- developers.cloudflare.com/workers/testing/vitest-integration/test-apis/ (updated 2026-09-28) — `evictDurableObject`, `evictAllDurableObjects`, `abortAllDurableObjects`, `runDurableObjectAlarm`, `runInDurableObject`, `listDurableObjectIds`, `reset()`, `env`/`exports`, `createExecutionContext`
- developers.cloudflare.com/workers/testing/vitest-integration/{index,configuration,write-your-first-test,recipes} (Aug 2026) — per-test-file isolation, `cloudflareTest({ wrangler, miniflare })` merge semantics, tsconfig `types` entry, integration styles
- cloudflare/workers-sdk repo `main` (fetched 2026-09-29): fixtures `vitest-plugin-examples/{request-mocking,durable-objects,kv-r2-caches,misc,fake-timers,ai-vectorize,rpc}`; `packages/vitest-plugin/AGENTS.md` (`fetchMock`/`SELF` exports); `packages/miniflare/README.md` (`cacheAPI`, `outboundService`, `durableObjects useSQLite`, persistence); `packages/miniflare/src/workers/cache/*` + cache plugin tests (HTTP-cache semantics: no-store/private/Set-Cookie rejection, max-age/s-maxage, CF-Cache-Status)
- developers.cloudflare.com/workers/configuration/secrets (Jul 2026) — `wrangler secret put`, `.dev.vars`/`.env` local handling, gitignore guidance, `secrets.required` semantics
- Workstream canonical refs: `research/STACK.md`, `research/ARCHITECTURE.md`, `research/PITFALLS.md`, `.planning/research/pricing_coordinator.md`, `01-CONTEXT.md`, `REQUIREMENTS.md`

### Secondary (MEDIUM confidence)
- vite.dev — `?raw` import suffix (standard Vite feature; plugin-pipeline behavior to confirm)
- DO SQL API details (sync `exec`, cursor iteration) from Cloudflare docs knowledge — confirm exact helpers during 01-03

### Tertiary (LOW confidence)
- None material; all LOW items are logged as assumptions A1–A7 with fallbacks

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every version/peerDep verified on npm; every API verified against current official docs or first-party fixtures
- Architecture/patterns: HIGH — coalescing/eviction/cache/testing patterns all backed by working fixture code; the one derived element (batch-window DO) is assembled from verified primitives
- Pitfalls: HIGH — extends PITFALLS.md with two newly verified constraints (cache-TTL vs fake timers; native timeout vs fake timers)

**Research date:** 2026-09-29
**Valid until:** 2026-10-29 (npm pins move fast; re-verify `vitest`/`vitest-plugin` peer ranges if planning slips past ~2 weeks)
