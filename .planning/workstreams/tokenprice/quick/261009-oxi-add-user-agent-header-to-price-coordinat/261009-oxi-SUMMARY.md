---
quick_id: 261009-oxi
slug: add-user-agent-header-to-price-coordinat
status: complete
date: 2026-10-09
plan: 261009-oxi-PLAN.md
commit: 3df8433b3
---

# Summary — Add User-Agent header to price coordinator CoinGecko upstream fetch

**Status: complete** — root cause fixed, verified locally by the user, committed to
`dev_tokenprice` as `3df8433b3`.

## Problem

Live testing of the deployed worker (`price-coordinator.yellow-snow-2071.workers.dev`)
and local `wrangler dev` both returned `502 upstream_error, coinGecko responded 403`.
Controlled probing from the user's residential IP isolated the cause:

- `curl` **with** its default UA → `/simple/price` returns 200
- same request with the UA **stripped** → 403 with body
  `"Please add a descriptive User-Agent to your request..."`
- `/ping` returns 200 either way

Cloudflare Workers `fetch` sends no User-Agent unless explicitly set, and
`fetchUpstream` only set headers when the API key was present — so every worker
request, anywhere, was UA-less and 403'd.

This empirically resolves the deferred tokenprice item "Phase 02 live WAF/UA
comparison and real 403 response" (was `partial`): the operative gate is the UA
requirement, not only the IP-reputation block the 2026-09-29 research recorded.

## Changes (commit `3df8433b3`, SuperGenius submodule)

- `pricecoordinator/src/upstream.ts` — exported constant
  `UPSTREAM_USER_AGENT = "GNUS-PriceCoordinator/1.0 (https://token.gnus.ai)"`,
  set unconditionally before the D-04/D-05 key block (key binding untouched)
- `pricecoordinator/test/key.test.ts` — additive msw test asserting the UA on
  both keyed and anonymous paths, importing the constant
- `pricecoordinator/DEPLOYMENT.md` — verification examples fixed to
  `ids=genius-ai` (the real CoinGecko id for GNUS; plain `gnus` returns
  `prices:{}` per D-09) + note documenting the coin-id gotcha

## Verification

- Gates: `npm --prefix SuperGenius/pricecoordinator run test` → 10 files /
  **64 tests passed** (63 + 1 new); `npm run typecheck` clean
- User local verification (wrangler dev + browser, held before commit per plan):
  - `ids=bitcoin` → 200, `{"bitcoin":82447}`, `stale:false`, `max-age=45`
  - `ids=genius-ai` → 200, `{"genius-ai":1.43}`, `age:0`, `source:"coingecko"`
  - pre-fix the same requests returned 503-shaped `502 upstream_error` 403s
- Scope fence: only the three files above changed in the submodule

## Follow-ups (not in this task)

- Redeploy the worker (`npx wrangler deploy`) to pick up the fix on the live
  preview route; then attach the `token.gnus.ai` custom domain per DEPLOYMENT.md §7
- Optionally set `COINGECKO_API_KEY` via `wrangler secret put` for higher rate
  limits (no longer strictly required for the 403)
- Consider updating the deferred-items table entry for the Phase 02 UAT item to
  reflect the confirmed diagnosis
