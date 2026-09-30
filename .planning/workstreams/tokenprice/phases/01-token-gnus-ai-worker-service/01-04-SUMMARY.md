---
phase: 01-token-gnus-ai-worker-service
plan: 04
subsystem: infra
tags: [cloudflare-workers, cache-api, http-cache, read-through, canonicalization]

requires:
  - phase: 01-token-gnus-ai-worker-service/01-03
    provides: DO-routed worker with the single seam function
provides:
  - "caches.default read-through tier ahead of the DO (SRVC-04): canonical keys, match-before-DO, fresh-only admission, max-age=45 via waitUntil"
  - "Fresh-only admission invariant: cache hits are always fresh-band — D-06's two-value source stays honest (D-06a)"
  - "Empirical cache-API findings for this workerd build (see key decisions) — load-bearing for 01-05"
affects: [01-05 suite consolidation, Phase 5 worker-tests CI]

tech-stack:
  added: []
  patterns:
    - "Request-keyed cache match/put (string-URL keys under-key in this build)"
    - "Verification-request discipline: unique superset/subset ids to force cache-misses when fake time can't expire the real-clock TTL"

key-files:
  created:
    - SuperGenius/pricecoordinator/test/cache.test.ts
  modified:
    - SuperGenius/pricecoordinator/src/index.ts
    - SuperGenius/pricecoordinator/test/coordinator.coalescing.test.ts
    - SuperGenius/pricecoordinator/test/coordinator.upstream-failure.test.ts

key-decisions:
  - "KF-3 DISAGREEMENT FOUND (empirically): string-URL cache keys matched too broadly in this workerd/miniflare build — distinct query strings collided on one entry. Fixed by constructing a Request for the canonical URL and using it for BOTH match and put. If the plugin is upgraded (see 01-01 pin deviation), retest whether plain-URL keys behave per docs."
  - "KF-3 caveat CONFIRMED exactly as researched: the cache TTL runs on miniflare's own real-time clock — vi.setSystemTime cannot expire entries. All DO-behavior verification requests (01-03 files) now carry a unique extra id (superset) or subset so their canonical key differs from any primed entry — cache-missing by construction, immune to this limitation forever."
  - "Admission guard: stale-serve 200s excluded by parsing the body once and requiring stale === false — the D-12 >5min bound can never be breached via the cache tier."
  - "Stale-non-admission PROOF technique: age-growth identity — a cached copy would replay the identical age; a live DO re-read grows with setSystemTime. Counter-based proofs alone were ambiguous under hold-off."

patterns-established:
  - "Canonical key: new URL('https://token.gnus.ai/v1/prices') + sorted/deduped ids + vs, always as a Request object"
  - "Two independently constructed Responses (client + cached) from one parsed body — zero clone hazards"

requirements-completed: [SRVC-04]

duration: 40min
completed: 2026-09-30
---

# Plan 01-04: Cache Read-Through Summary

**SRVC-04 delivered: a per-colo cache tier ahead of the Durable Object with canonical keys and fresh-only admission — 58/58 tests green, and two empirical cache-API findings recorded that 01-05 and any future plugin upgrade must respect.**

## Performance

- **Duration:** ~40 min
- **Tasks:** 1/1 (TDD: RED `b795714b8` → GREEN `0cd632962`)
- **Tests:** 58 passing (8 files)

## The Canonical-Key Algorithm

```ts
const key = new URL("https://token.gnus.ai/v1/prices");
key.searchParams.set("ids", [...new Set(ids)].sort().join(","));
key.searchParams.set("vs", currency);
const cacheRequest = new Request(key.toString(), { method: "GET" }); // Request-keyed!
```

## Empirical Findings vs Research (KF-3)

| Research claim | Empirical result (plugin 1.2.4 / this workerd) |
|---|---|
| Cache key = full URL incl. query (string OK) | **String-URL keys under-key** — distinct queries collided; Request-keyed match/put required |
| TTL not fake-timer controllable | **Confirmed** — setSystemTime does not expire entries; unique-key verification requests are the permanent pattern |
| put silently no-ops without Cache-Control | Header always set on the cached Response; round-trip hit test guards regressions |
| Per-colo semantics untestable locally | Accepted — read-through ordering + canonicalization are the tested content |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — environment] Request-keyed cache API** (see key decisions — string keys collided).
**2. [Rule 3 — test construction] Verification requests made cache-missing via unique superset ids** — the plan anticipated this discipline for subsets; the real-clock TTL made it mandatory for *all* fake-time DO-verifications.
**3. [Rule 3 — comment hygiene]** Reworded a doc comment that contained the literal `set-cookie` token (the acceptance grep).

**Total deviations:** 3 auto-fixed. **Impact:** none — every acceptance criterion verified.

## Self-Check: PASSED

- `npm run test` → 58/58 (8 files), exit 0; typecheck exit 0
- Round-trip: second identical request leaves `upstreamCalls` unchanged (7 grep matches for the assertion pattern)
- `caches.default.match`/`put`/`max-age=45`/`ctx.waitUntil` all present in `src/index.ts`; admission guards on the parsed body's `stale === false`
- Canonicalization: permuted + duped lists hit one entry; different sets miss
- Error exclusion (502 never served from cache) + stale-200 exclusion (age-growth identity proof) both green
