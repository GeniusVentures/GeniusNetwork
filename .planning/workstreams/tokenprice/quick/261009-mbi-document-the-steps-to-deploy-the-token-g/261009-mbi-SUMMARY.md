---
phase: tokenprice-quick-261009-mbi
plan: 01
subsystem: pricecoordinator
tags: [deployment, runbook, cloudflare-workers, token-gnus-ai]
requires: []
provides: [token.gnus.ai deployment runbook]
affects: []
tech-stack:
  added: []
  patterns: [operator runbook, secrets-as-placeholders (D-04)]
key-files:
  created:
    - SuperGenius/pricecoordinator/DEPLOYMENT.md
  modified: []
decisions:
  - Runbook documents both custom-domain options (dashboard-first, routes-stanza alternative); the wrangler.jsonc routes edit is documented but NOT applied (operator action at deploy time)
  - All commands copy-pasteable from repo root except wrangler commands, which are explicitly cd-guarded to SuperGenius/pricecoordinator
metrics:
  duration: 4min
  completed: "2026-10-09"
status: complete
estimate_present: true
actuals:
  tokens: 2630   # chars/4 over DEPLOYMENT.md (10504 chars), the only file changed
  tasks: 2
  commits: 1     # measured: git rev-list --count 3c41ab311..HEAD in SuperGenius submodule
plan_head_before: 3c41ab311
plan_head_after: 0fd1de762
repo: SuperGenius (submodule, branch dev_tokenprice)
---

# Quick Task 261009-mbi: token.gnus.ai Deployment Runbook Summary

One-liner: Operator runbook (SuperGenius/pricecoordinator/DEPLOYMENT.md) taking token.gnus.ai from zero to a live Cloudflare Worker — prerequisites, dual pre-deploy gates, wrangler auth, deploy + DO migration, optional CoinGecko secret, custom-domain attach, live verification, C++ client resolution, and rollback — with zero worker code changes.

## What Was Done

### Task 1: Author the runbook

Created `SuperGenius/pricecoordinator/DEPLOYMENT.md` (273 lines) covering all eleven planned sections:

1. **Overview** — tier-2 fallback price feed behind `GET /v1/prices?ids=...&vs=...` returning a PriceEnvelope; canonical origin `https://token.gnus.ai`; caches.default read-through tier with canonical keys + FRESH-ONLY admission ahead of the PriceCoordinator DO (one instance per currency via idFromName).
2. **Prerequisites** — Cloudflare Free plan works (SQLite-backed DO storage class, migration v1 `new_sqlite_classes`); gnus.ai zone must be on the same account; Node ≥ 20; wrangler ^4.136.3 vendored — never a global install.
3. **Pre-deploy gates** — `npm --prefix SuperGenius/pricecoordinator run test` and `... run typecheck`, both must exit 0.
4. **Authentication** — `npx wrangler login` (interactive) or `CLOUDFLARE_API_TOKEN` (CI; "Edit Cloudflare Workers" template, account-scoped).
5. **Deploy** — `npx wrangler deploy` from `SuperGenius/pricecoordinator`; uploads worker + applies DO migration; workers.dev preview route goes live.
6. **Optional CoinGecko key** — `npx wrangler secret put COINGECKO_API_KEY` with the D-04 hard rule stated inline (secrets only in wrangler secret / local .dev.vars, never wrangler.jsonc, never committed; `.dev.vars` confirmed gitignored).
7. **Custom domain** — states wrangler.jsonc has NO routes stanza today; option (a) dashboard attach (auto-provisions DNS + cert), option (b) `routes: [{ "pattern": "token.gnus.ai", "custom_domain": true }]` + re-deploy; making token.gnus.ai primary by disabling workers.dev (dashboard or `"workers_dev": false`). The edit is documented as an operator action at deploy time — NOT applied in this task.
8. **Production cautions** — `BATCH_WINDOW_MS_OVERRIDE` never in production (test seam per src/index.ts Env docblock); no message-queue/KV bindings (SRVC-07); never change the DO storage class away from SQLite.
9. **Post-deploy verification** — happy-path curl expecting 200 / `stale: false` / `Cache-Control: public, max-age=45`; 404 not_found and 405 method_not_allowed negatives; `ids=gnus,gnus` canonicalization check; DO dashboard health and `npx wrangler tail`.
10. **C++ client resolution** — zero code changes; `PriceEndpoints.hpp` `kFallbackBaseUrlDefault = "https://token.gnus.ai"` with the client appending `/v1/prices`; `SGNS_PRICE_FALLBACK_URL` (tier-2) / `SGNS_COINGECKO_URL` (tier-1) overrides; one curl reproducing exactly the C++ fallback request.
11. **Ops** — `npx wrangler rollback` / `versions list`; compatibility_date changes are a deliberate follow-up, never routine.

Secrets appear only as placeholders (`<your-api-token>`, `<your-api-key>`) — T-261009-01 mitigated.

- **Commit:** `0fd1de762` (SuperGenius submodule, branch `dev_tokenprice`)

### Task 2: Validate against the checkout

- **Gates run verbatim from repo root:** `npm --prefix SuperGenius/pricecoordinator run test` → **10 files / 63 tests passed, exit 0** (miniflare `deleteAllDurableObjects` stderr lines are pre-existing harness noise, not failures); `npm --prefix SuperGenius/pricecoordinator run typecheck` → exit 0.
- **Artifact cross-checks (all grounded):**
  - `wrangler.jsonc` — `PRICE_COORDINATOR` DO binding + `new_sqlite_classes` migration v1 present; no routes stanza (as documented).
  - `package.json` — `test` (vitest run) and `typecheck` (dual tsc --noEmit) scripts present; wrangler ^4.136.3 devDependency confirmed.
  - `src/index.ts` — `Env` declares `COINGECKO_API_KEY?` and `BATCH_WINDOW_MS_OVERRIDE?`; FRESH-only admission + `max-age=45` confirmed in `fetchFromCoordinator`.
  - `SuperGenius/src/coinprices/PriceEndpoints.hpp` — `kFallbackBaseUrlDefault = "https://token.gnus.ai"` (client appends `/v1/prices`), `SGNS_COINGECKO_URL` (tier-1), `SGNS_PRICE_FALLBACK_URL` (tier-2) all present as documented.
  - `.dev.vars` confirmed in `pricecoordinator/.gitignore`.
- **Documentation-only confirmed:** `git status --porcelain` for `src/`, `wrangler.jsonc`, `package.json` → empty ("worker source untouched"). The runbook's required-token check (Task 1 `<automated>`) passed: all 13 required strings present verbatim.

## Deviations from Plan

None material. One environment note: Task 2's `<automated>` verify block, written as a nested `powershell -NoProfile -Command "..."` string, could not be invoked verbatim from inside PowerShell (the outer shell expanded `$?` before the inner parser saw it — a quoting artifact, exit 1 with a parse error). Both constituent checks were instead executed with identical semantics directly in the shell: the typecheck gate re-ran green (exit 0) and the `git status --porcelain` documentation-only check returned empty. The two pre-deploy gates themselves were run verbatim as separate commands from the repo root, exactly as documented in the runbook.

## Auth Gates

None (deploy/auth actions are documented for the operator; nothing executed against Cloudflare).

## Known Stubs

None — documentation-only task; no stubs, no unrun verifies (both gates executed and green).

## Threat Flags

None — no new security-relevant surface introduced. T-261009-01 (placeholders only) and T-261009-02 (workers.dev second-origin guidance + primary-route instructions) mitigated in the runbook text; T-261009-03 accepted per plan.

## Self-Check: PASSED

- `SuperGenius/pricecoordinator/DEPLOYMENT.md` — FOUND (committed, 273 lines)
- Commit `0fd1de762` — FOUND on `dev_tokenprice` (verified via `git log`)
- Worker source (`src/`, `wrangler.jsonc`, `package.json`) — unmodified (git status clean for those paths)
- Parent repo `W:/gnus/GeniusNetwork` — no staged `SuperGenius` entry; no parent-repo commits made
