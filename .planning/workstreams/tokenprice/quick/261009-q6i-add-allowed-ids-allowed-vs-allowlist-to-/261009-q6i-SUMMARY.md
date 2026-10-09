---
phase: quick-261009-q6i
plan: 261009-q6i
subsystem: tokenprice
tags: [pricecoordinator, cloudflare-worker, allowlist, security-hardening, srvc-08]
status: complete
duration: 8min
completed: 2026-10-09
submodule_commit: cc5fac5adb3c6be31142ce5b6430d325e5bdb83d
submodule_branch: dev_price_validation
estimate:
  tokens: 35000
actuals:
  tasks: 3
  commits: 1
files:
  - SuperGenius/pricecoordinator/src/validate.ts
  - SuperGenius/pricecoordinator/src/index.ts
  - SuperGenius/pricecoordinator/wrangler.jsonc
  - SuperGenius/pricecoordinator/vitest.config.ts
  - SuperGenius/pricecoordinator/test/envelope.freshness.test.ts
  - SuperGenius/pricecoordinator/test/router.validation.test.ts
  - SuperGenius/pricecoordinator/test/config.test.ts
  - SuperGenius/pricecoordinator/DEPLOYMENT.md
requirements: [SRVC-08]
---

# Quick Task 261009-q6i: ALLOWED_IDS / ALLOWED_VS allowlist for the price coordinator

Enforced an id/currency allowlist in the token.gnus.ai worker so it can no
longer be abused as a general-purpose CoinGecko proxy (quota burn, shared
rate-limit trips), while the sole real consumer — the SuperGenius C++
LocalPriceManager (genius-ai/usd only) — is unaffected. Widenable later by
editing wrangler vars (config change, no code).

## What changed

- `src/validate.ts` — `AllowedLists` type, `DEFAULT_ALLOWED_IDS/VS` constants,
  `resolveAllowlist(env)` (split on commas, trim, lowercase, drop empties;
  unset/whitespace-empty → default constants — fail closed, never open).
  `parsePricesRequest(url, allowed = <closed default>)`: existing format
  validation sequence untouched; membership gate appended immediately before
  the success return (ids first, then vs), reusing `bad()` → same 400
  `invalid_request` shape with message naming the policy and the rejected
  token. File header documents the two-stage design.
- `src/index.ts` — `Env.ALLOWED_IDS?/ALLOWED_VS?` (plain vars: public config
  per D-04, no store bindings per SRVC-07); router call site threads
  `parsePricesRequest(url, resolveAllowlist(env))` — gate stays ahead of
  cache and DO.
- `wrangler.jsonc` — `vars` stanza (`ALLOWED_IDS: "genius-ai"`,
  `ALLOWED_VS: "usd"`); header D-04 bullet clarified (plain non-secret
  config vars are fine inline — D-04 bans credentials). Nothing else added.
- `vitest.config.ts` — `miniflare.bindings` widened with
  `ALLOWED_IDS`/`ALLOWED_VS` (fixture ids + `genius-ai`; `usd,eur`) so the
  existing SELF.fetch integration suite (~30 fixture-id call sites) stays
  green; production default stays closed in wrangler.jsonc. Binding
  precedence (miniflare bindings override wrangler vars) verified
  empirically — the suite passes.
- Tests — `envelope.freshness.test.ts`: `resolveAllowlist` describe (unset →
  default closed, whitespace-empty → default, trim/dedupe) + membership unit
  cases (no-arg default closed 400 naming bitcoin, eur currency policy,
  multi-id pass, mixed allowed+disallowed 400); the two legacy positive
  cases thread an explicit wide allowlist. `router.validation.test.ts`:
  default-closed router describe (bitcoin 400, eur 400, format-first
  ordering asserting `[a-z0-9-]+` wording, genius-ai/usd end-to-end 200 with
  `{ "genius-ai": 0.42 }`, stale false). `config.test.ts`: vars shape guard
  (`^[a-z0-9-]+(,[a-z0-9-]+)*$`, contains genius-ai/usd).
- `DEPLOYMENT.md` — §8 subsection "Allowlist enforcement — ALLOWED_IDS /
  ALLOWED_VS" (why/what/defaults/widen/compliance); §9 negative curl for
  `ids=bitcoin` (expect 400 policy message) next to the existing genius-ai
  happy path.

## Gate results

- `npm --prefix SuperGenius/pricecoordinator run test` — **76/76 passed,
  10/10 files** (was 64 before: +12 allowlist tests, 2 adjusted)
- `npm --prefix SuperGenius/pricecoordinator run typecheck` — green (both
  tsconfig projects)

## Commit

- SuperGenius submodule, branch `dev_price_validation`:
  **`cc5fac5adb3c6be31142ce5b6430d325e5bdb83d`**
  `feat(tokenprice): allowlist price coordinator ids/currencies
  (ALLOWED_IDS/ALLOWED_VS)` — 8 files, +249/−11, with proxy-abuse rationale
  body and `Co-authored-by: Copilot` trailer.
- Parent repo: submodule pointer shows unstaged `M SuperGenius` only (orchestrator
  handles the parent commit); no staged SuperGenius entry. Pre-existing
  nested `SGProcessingManager` dirty pointer left untouched.

## Deviations from Plan

**1. [Rule 3 - Blocking issue] Added `genius-ai` to the vitest miniflare
allowlist seam**
- **Found during:** Task 2 (suite run)
- **Issue:** The plan's Task 1 fixture list for `vitest.config.ts` omitted
  `genius-ai`, but the plan's own Task 2 end-to-end test
  (`SELF.fetch /v1/prices?ids=genius-ai&vs=usd` → 200) requires it — the
  plan text even states "the test bindings, which include genius-ai and
  usd". Without it the test 400'd (id `genius-ai` not in the seam list).
- **Fix:** Added `genius-ai` to the seam's `ALLOWED_IDS` (production
  wrangler.jsonc unchanged — still `genius-ai` only).
- **Files modified:** `vitest.config.ts`
- **Commit:** included in cc5fac5ad

## Security invariants verified

- Unset/empty `ALLOWED_IDS`/`ALLOWED_VS` → genius-ai/usd only (default
  closed at BOTH `resolveAllowlist` and the `parsePricesRequest` parameter
  default) — unit- and router-tested.
- Format validation stays first (router test pins `[a-z0-9-]+` wording ahead
  of the membership gate).
- No KV/queue bindings introduced; vars are plain public config (SRVC-07,
  D-04) — `config.test.ts` still guards these.
- Disallowed requests return before any `caches.default` or DO interaction.

## Deploy note

Live enforcement on token.gnus.ai takes effect only after the user redeploys
(DEPLOYMENT.md §5). After redeploy, the §9 negative check
(`curl "https://token.gnus.ai/v1/prices?ids=bitcoin&vs=usd"` → 400 with
policy message) should be run; `ids=genius-ai&vs=usd` stays 200.
