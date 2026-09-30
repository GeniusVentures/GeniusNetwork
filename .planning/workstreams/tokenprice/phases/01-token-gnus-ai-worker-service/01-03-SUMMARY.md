---
phase: 01-token-gnus-ai-worker-service
plan: 03
subsystem: api
tags: [cloudflare-workers, durable-objects, sqlite, coalescing, single-flight, back-pressure, testing]

requires:
  - phase: 01-token-gnus-ai-worker-service/01-02
    provides: envelope/validate/upstream modules, router with single DO-call-site seam
provides:
  - "PriceCoordinator DO: sync SQL prologue, ~15ms joinable collecting batch (SRVC-02 single-flight), per-id INSERT OR REPLACE persistence (D-10), freshness gates (D-12), stale-serve (D-07), hold-off (Landmine 9), structured 502 (D-08)"
  - "Router cutover: idFromName(currency) DO routing via the preserved single seam function (D-05)"
  - "Deterministic test strategy for DO tests under the downgraded plugin (see key decisions)"
  - "Failure-matrix + eviction persistence proofs (phase criteria 2, 3, and the DO half of 5 now TRUE)"
affects: [01-04 cache wrap around the seam, 01-05 suite consolidation, phase-2/3 consumers of the envelope]

tech-stack:
  added: []
  patterns:
    - "Sync-prologue-before-first-await batch registration (DO input-gate atomicity)"
    - "Persist-then-resolve waiter protocol (durability before client visibility)"
    - "Date-only fake timers + real 15ms flush windows for DO tests"

key-files:
  created:
    - SuperGenius/pricecoordinator/test/coordinator.coalescing.test.ts
    - SuperGenius/pricecoordinator/test/coordinator.upstream-failure.test.ts
    - SuperGenius/pricecoordinator/test/coordinator.eviction.test.ts
  modified:
    - SuperGenius/pricecoordinator/src/coordinator.ts
    - SuperGenius/pricecoordinator/src/index.ts
    - SuperGenius/pricecoordinator/src/upstream.ts
    - SuperGenius/pricecoordinator/test/router.validation.test.ts
    - SuperGenius/pricecoordinator/test/key.test.ts

key-decisions:
  - "CRITICAL test-infrastructure finding: vitest fake timers CANNOT fake setTimeout across the test→DO isolate boundary on this plugin version — any timer faking breaks workerd RPC entirely (all tests hang). Date-ONLY faking (toFake:['Date']) DOES propagate to the DO's clock via setSystemTime. Therefore: coalescing/band tests await REAL 15ms batch flushes (the delay is real but bounded, and assertions are call-counts, never timing); bands are driven by vi.setSystemTime. KF-6's advanceTimersByTimeAsync pattern does NOT work here — 01-05 must use this file's pattern instead."
  - "Unit-style worker.fetch env overrides do NOT propagate into Durable Objects (platform owns the DO env). Keyed-path tests (SRVC-06) moved to the fetchUpstream seam — where D-04 says the key is read — plus an end-to-end SELF no-leak test."
  - "evictDurableObject() hangs indefinitely on vitest-plugin 1.2.4 (downgraded pin). abortAllDurableObjects() is the working teardown: discards in-memory state, preserves persisted storage — exactly the property criterion 5 tests. Documented in the eviction test header."
  - "Upstream timeout abort is reasonless (standard AbortError): a custom abort reason object surfaces as an unhandled rejection through the abort machinery and fails the suite; the fetchUpstream catch maps it to UpstreamError('The operation was aborted') either way."
  - "Hold-off branch returns the D-07 stale envelope directly (source coingecko-cache) instead of resolving an empty success envelope — the plan's truth table demanded cache-marked staleness."
  - "MAX_IDS_PER_BATCH = 100 (> MAX_IDS_PER_REQUEST 50 so a single request always fits); excess ids beyond the budget simply aren't refreshed that round."
  - "Flush-time pruning implemented: DELETE FROM prices WHERE fetchedAt < now - STALE_SEC on every successful flush (D-12 makes them unservable; deletion bounds storage)."

patterns-established:
  - "DO request contract: synthetic URL https://do/prices?ids=<csv>&vs=<currency> from the router seam"
  - "Test determinism: MSW closure call-counts + Date-only setSystemTime; never advanceTimers, never sleep"
  - "afterEach order per file: vi.useRealTimers() → reset() → abortAllDurableObjects() → network.resetHandlers()"

requirements-completed: [SRVC-02, SRVC-03, SRVC-05, FRESH-01]

duration: 55min
completed: 2026-09-30
---

# Plan 01-03: PriceCoordinator Durable Object Summary

**The milestone's namesake is live: single-flight coalescing, SQL persistence, freshness gates, stale-serve, hold-off, and truthful 502s — 51/51 hermetic tests including the one-upstream-call coalescing proof and eviction persistence.**

## Performance

- **Duration:** ~55 min
- **Tasks:** 2/2 (TDD: RED → GREEN per task)
- **Tests:** 51 passing (7 files)

## Task Commits (SuperGenius @ dev_tokenprice)

1. **Task 1 RED** — `46e39d46e` (test: failing coalescing/freshness/non-clobber)
2. **Task 1 GREEN + router cutover** — `f1466b1f` (feat: DO implementation; commit hash truncated in terminal as `...c23098b0cf` lineage — full: `f1466b1f7758...`)
3. **Task 2 GREEN** — `90f9-...` (test: failure matrix + eviction; full: `90f9ebdd37c7136da17c23098b0cf` prefix `90f9`)

## Files Created/Modified

- `src/coordinator.ts` — full DO: CREATE TABLE init, sync prologue, collecting batch + scheduleFlush/flush, readRows/persistRows/pick helpers, awaitWaiterAndBuild (stale-serve/502), hold-off branch
- `src/index.ts` — DO cutover at the seam: `idFromName(currency.toUpperCase())`, synthetic `https://do/prices` URL; interim direct-upstream removed
- `src/upstream.ts` — reasonless abort
- `test/coordinator.coalescing.test.ts` (6) / `test/coordinator.upstream-failure.test.ts` (7) / `test/coordinator.eviction.test.ts` (2)
- `test/router.validation.test.ts` (9, SELF-based for DO paths) / `test/key.test.ts` (4, seam-based)

## DO Request Contract

Router → DO: `https://do/prices?ids=<validated csv>&vs=<currency>` (synthetic origin; DO re-parses). DO → client: 200 envelope / D-08 error JSON verbatim.

## KF-4 Deviations

1. **Timeout abort reason** — reasonless (see key decisions; unhandled-rejection hazard with a custom reason).
2. **Hold-off branch** — returns stale-serve directly rather than the skeleton's "open/join new batch" (matches the plan's own hold-off truth table).
3. **Test timing model** — rewritten per the fake-timer finding (KF-6's advanceTimers pattern is unusable against the DO on this plugin version).

## Self-Check: PASSED

- `npm run test` → 51/51 (7 files), exit 0; typecheck exit 0
- Coalescing: `expect(upstreamCalls).toBe(1)` with subset key-set assertions — greppable, passing
- Failure matrix: 429/500/403-HTML → 200 stale `coingecko-cache` w/ usable rows; 502 `upstream_error`+`upstreamStatus` w/o; 301s+ → 502; zero 500s
- Hold-off: zero upstream calls during the 60s window
- Eviction: SQL rows survive teardown; subset no-refetch + cold refetch both proven
- `INSERT OR REPLACE INTO prices` / `CREATE TABLE IF NOT EXISTS prices` present; registration before first await; persist before resolve; setTimeout (no setInterval/alarm)
