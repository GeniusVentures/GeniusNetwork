---
status: partial

# remaining: items 2 and 4 need extended live traffic (try price_live_check --repeat N)

phase: 02-c-price-http-client-quote-surface
source: [02-VERIFICATION.md human_verification]
started: 2026-10-05
audit_acknowledged:
  milestone: v1.1
  at: 2026-10-07
  gap_snapshot: "partial::scenarios=0"
---

## Tests

### 1. Live TLS against real CoinGecko

expected: HTTPS exchange to api.coingecko.com succeeds with a valid chain
result: pass
note: example/price_live_check (Windows Release) ran PriceHttpClient against https://api.coingecko.com 3/3 OK via the pinned CA bundle; genius-ai and bitcoin quotes returned.

### 2. Live WAF behavior of the new UA

expected: fewer 403s than the old UA
result: partial
note: 9 consecutive requests with the new UA saw no 403; a before/after comparison against the old UA was not run.

### 3. HTTPClient.cpp editor buffer vs disk

expected: unsaved `ioc->restart()` defense is committed or discarded
result: partial
note: thirdparty/AsyncIOManager/src/HTTPClient.cpp on disk has no `restart` and git status is clean. If the editor still holds the unsaved buffer, discard it, or commit it. Correct the 02-04-SUMMARY wording either way.

### 4. End-to-end 403/429 semantics vs real endpoint

expected: live responses match stub fixtures
result: pass (429 only)
note: price_live_check --repeat 30 --delay-ms 1500: 8 OK, then real HTTP 429 on request 9 (logged with literal 429, code=RateLimitExceeded, attempts=1, no retry), then the 60s hold-off skipped the remaining 21 with attempts=0. Real 403 HTML not reproduced (WAF did not block).

## Gaps

- Live-only items (1 full, 2, 4) deferred to production observation.
