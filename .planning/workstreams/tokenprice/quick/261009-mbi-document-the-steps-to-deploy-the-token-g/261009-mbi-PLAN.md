---
phase: tokenprice-quick-261009-mbi
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - SuperGenius/pricecoordinator/DEPLOYMENT.md
autonomous: true
requirements: [Q-261009-MBI]

estimate:
  tokens: 22000
  raw_tokens: 15000
  tasks: 2
  confidence: med
---

<objective>
Produce a deployment runbook (SuperGenius/pricecoordinator/DEPLOYMENT.md) that takes an operator from zero to a live token.gnus.ai price-coordinator Cloudflare Worker, verified against the C++ client's expectations, with no worker code changes.

Purpose: The worker code is complete and fully tested (milestone v1.1, plans 01-01..01-05) but has never been deployed; the user asked for the concrete steps to put token.gnus.ai live as the tier-2 fallback price feed.
Output: One Markdown runbook. No source files modified.
</objective>

<execution_context>
@~/.copilot/gsd-core/workflows/execute-plan.md
@~/.copilot/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/workstreams/tokenprice/STATE.md
@SuperGenius/pricecoordinator/wrangler.jsonc
@SuperGenius/pricecoordinator/package.json
@SuperGenius/pricecoordinator/src/index.ts
@SuperGenius/src/coinprices/PriceEndpoints.hpp
</context>

<tasks>

<task type="auto">
  <name>Task 1: Author the token.gnus.ai deployment runbook</name>
  <files>SuperGenius/pricecoordinator/DEPLOYMENT.md</files>
  <action>
Create SuperGenius/pricecoordinator/DEPLOYMENT.md as a step-by-step operator runbook. All commands must be copy-pasteable with cwd at the repo root (document when a step requires cd SuperGenius/pricecoordinator instead — wrangler resolves wrangler.jsonc from the working directory). Use npx wrangler (wrangler ^4.136.3 is vendored in node_modules — never instruct a global install). Cover, in order:

1. **Overview**: what the worker is (tier-2 fallback price feed behind GET /v1/prices?ids=...&vs=..., returning a PriceEnvelope), canonical origin https://token.gnus.ai, caches.default read-through tier with FRESH-ONLY admission ahead of the PriceCoordinator Durable Object (one instance per currency via idFromName).
2. **Prerequisites**: Cloudflare account — the Free plan works because the DO uses the SQLite-backed storage class (migration v1 new_sqlite_classes, per wrangler.jsonc); the gnus.ai DNS zone must be on that same Cloudflare account for the custom-domain step; Node ≥ 20; wrangler already vendored (no npm install needed).
3. **Pre-deploy gates** (both must be green before deploying): npm --prefix SuperGenius/pricecoordinator run test and npm --prefix SuperGenius/pricecoordinator run typecheck.
4. **Authentication**: interactive npx wrangler login, or the CI alternative CLOUDFLARE_API_TOKEN environment variable (dashboard token using the "Edit Cloudflare Workers" template, account-scoped).
5. **Deploy**: from SuperGenius/pricecoordinator run npx wrangler deploy — note this uploads the worker and applies the DO migration; the workers.dev preview route (price-coordinator.&lt;subdomain&gt;.workers.dev) becomes live.
6. **Optional CoinGecko key**: npx wrangler secret put COINGECKO_API_KEY (per D-04: secrets live ONLY in wrangler secret / local .dev.vars, never in wrangler.jsonc, never committed; without it the worker runs keyless at lower CoinGecko rate limits).
7. **Custom domain token.gnus.ai**: state plainly that wrangler.jsonc has NO routes stanza today, and give two operator options — (a) dashboard: Workers & Pages → price-coordinator → Settings → Domains & Routes → Add → Custom Domain "token.gnus.ai" (auto-provisions DNS + cert, requires the gnus.ai zone on the account); (b) edit wrangler.jsonc to add routes: [{ "pattern": "token.gnus.ai", "custom_domain": true }] then re-run npx wrangler deploy. Document making token.gnus.ai the primary route (disabling the workers.dev route via the dashboard or "workers_dev": false) since the canonical cache keys and the C++ default hardcode token.gnus.ai. This edit is an operator action at deploy time — do NOT apply it in this task.
8. **Production cautions**: BATCH_WINDOW_MS_OVERRIDE must NOT be set in production (test seam only, per src/index.ts Env docblock); never add message-queue or KV bindings (SRVC-07); never change the DO storage class away from SQLite (Free plan + ctx.storage.sql depend on it).
9. **Post-deploy verification**: curl "https://token.gnus.ai/v1/prices?ids=gnus&vs=usd" expecting 200 with a PriceEnvelope whose stale is false and Cache-Control: public, max-age=45 on fresh admission; negative checks (unknown path → 404 {"error":{"code":"not_found",...}}, POST → 405 method_not_allowed); cache canonicalization check (repeat with ids=gnus,gnus — same canonical key); DO health via dashboard Storage & Databases → Durable Objects → PriceCoordinator and live logs via npx wrangler tail from the pricecoordinator directory.
10. **C++ client resolution**: zero code changes needed — SuperGenius/src/coinprices/PriceEndpoints.hpp kFallbackBaseUrlDefault is https://token.gnus.ai and the client appends /v1/prices; SGNS_PRICE_FALLBACK_URL overrides tier-2, SGNS_COINGECKO_URL overrides tier-1 (tier-2 is exercised when tier-1 is unset or fails); include one curl that reproduces exactly what the C++ fallback request will hit.
11. **Ops**: npx wrangler rollback / versions list for incident recovery; compatibility_date changes require a deliberate follow-up, not part of routine deploys.

Use placeholder text (e.g. &lt;your-api-key&gt;) everywhere a secret would appear — the runbook itself must never contain a real credential (D-04).
  </action>
  <verify>
    <automated>powershell -NoProfile -Command "$t=@('npx wrangler deploy','npx wrangler login','CLOUDFLARE_API_TOKEN','wrangler secret put COINGECKO_API_KEY','token.gnus.ai','custom_domain','BATCH_WINDOW_MS_OVERRIDE','SGNS_PRICE_FALLBACK_URL','SGNS_COINGECKO_URL','npm --prefix SuperGenius/pricecoordinator run test','npm --prefix SuperGenius/pricecoordinator run typecheck','PriceEndpoints.hpp','max-age=45'); $m=$t|Where-Object{-not(Select-String -Path 'SuperGenius/pricecoordinator/DEPLOYMENT.md' -Pattern ([regex]::Escape($_)) -Quiet)}; if($m){Write-Output ('MISSING: '+($m -join ', ')); exit 1}else{Write-Output 'all required tokens present'}</automated>
  </verify>
  <done>DEPLOYMENT.md exists with all eleven sections; every required command, env var, and URL listed above appears verbatim; no real credentials present; no worker source files touched.</done>
</task>

<task type="auto">
  <name>Task 2: Validate the runbook against the checkout</name>
  <files>SuperGenius/pricecoordinator/DEPLOYMENT.md</files>
  <action>
Ground every claim in the runbook against the repo so the operator never hits a dead command. (a) Run the two documented pre-deploy gates verbatim from the repo root — both must pass; if a documented command fails while the equivalent direct command passes, fix the runbook's command line (not the code). (b) Cross-check every repo artifact the runbook names: wrangler.jsonc contains the PRICE_COORDINATOR DO binding and new_sqlite_classes migration; package.json defines the test/typecheck scripts; src/index.ts declares COINGECKO_API_KEY and BATCH_WINDOW_MS_OVERRIDE on Env; SuperGenius/src/coinprices/PriceEndpoints.hpp contains kFallbackBaseUrlDefault "https://token.gnus.ai" and the SGNS_PRICE_FALLBACK_URL / SGNS_COINGECKO_URL overrides. Correct the runbook where reality differs — never the source. (c) Confirm the deliverable stayed documentation-only: git status for SuperGenius/pricecoordinator/src, SuperGenius/pricecoordinator/wrangler.jsonc, and SuperGenius/pricecoordinator/package.json must show no modifications.
  </action>
  <verify>
    <automated>powershell -NoProfile -Command "npm --prefix SuperGenius/pricecoordinator run typecheck; if(-not $?){exit 1}; if(git status --porcelain SuperGenius/pricecoordinator/src SuperGenius/pricecoordinator/wrangler.jsonc SuperGenius/pricecoordinator/package.json){Write-Output 'worker source modified!'; exit 1}else{Write-Output 'worker source untouched'}</automated>
  </verify>
  <done>Both documented pre-deploy gates run green from the repo root exactly as written in DEPLOYMENT.md; every named artifact/env var resolves in the checkout; worker source, wrangler.jsonc, and package.json are unmodified (git-clean).</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| runbook → operator terminal | Deployment credentials and secrets flow through commands documented here |
| operator → Cloudflare | wrangler auth token grants account-level Worker deploy rights |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-261009-01 | Information Disclosure | DEPLOYMENT.md | high | mitigate | Placeholders only for secrets; D-04 rule stated inline (never in wrangler.jsonc, never committed); .dev.vars marked local-only |
| T-261009-02 | Spoofing | workers.dev preview route | medium | mitigate | Runbook instructs making token.gnus.ai the primary route and disabling the default workers.dev route to avoid a second live origin clients could pin |
| T-261009-03 | Tampering | CLOUDFLARE_API_TOKEN in CI | low | accept | Token handling is standard Cloudflare practice; runbook only names the env var, never stores it |
</threat_model>

<verification>
- SuperGenius/pricecoordinator/DEPLOYMENT.md exists and covers prerequisites → pre-deploy gates → auth → deploy → secret → custom domain → verification → C++ resolution → ops.
- The documented gate commands pass verbatim from the repo root (Task 2 runs them).
- git shows no changes under SuperGenius/pricecoordinator/src, wrangler.jsonc, or package.json.
</verification>

<success_criteria>
A reader with a Cloudflare account and the gnus.ai zone can go from clone to a verified live https://token.gnus.ai/v1/prices endpoint using only the runbook, and the existing C++ tier-2 fallback picks it up with zero code changes.
</success_criteria>

<output>
Create .planning/workstreams/tokenprice/quick/261009-mbi-document-the-steps-to-deploy-the-token-g/261009-mbi-SUMMARY.md when done
</output>
